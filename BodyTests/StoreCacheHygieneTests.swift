//
//  StoreCacheHygieneTests.swift
//  BodyTests
//
//  Pure-decision coverage for the store/settings hygiene fixes: the auto-apply
//  write loop stops mid-batch when Auto-Apply is switched off (M2); the
//  cache-epoch skip decision guarding resurrection after Clear Cache (H7); and
//  the negative-elapsed staleness rule for warm resumes (L1).
//

import XCTest
@testable import Body

final class StoreCacheHygieneTests: XCTestCase {

    // MARK: - M2: auto-apply loop stops mid-batch via shouldContinue

    @MainActor
    func testAutoApplyLoopStopsMidBatchWhenShouldContinueFlipsOff() async {
        let ids = (0..<5).map { _ in UUID() }
        var writeCalls: [UUID] = []
        let writer = HealthKitWorkoutStore.AutoApplyEffortWriter(
            write: { id, _ in
                writeCalls.append(id)
                return .written
            },
            isWriteAuthorized: { true }
        )
        let candidates = ids.map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 6)
        }

        // Simulates Auto-Apply switched off after two writes: `shouldContinue` is
        // checked before each candidate, so the third candidate stops the batch
        // before any further write.
        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: writer,
            shouldContinue: { writeCalls.count < 2 }
        )

        XCTAssertEqual(writeCalls, Array(ids.prefix(2)))
        XCTAssertEqual(result.appliedIDs, Set(ids.prefix(2)))
        XCTAssertFalse(result.writeAuthRevoked)
    }

    @MainActor
    func testAutoApplyLoopRunsFullBatchWhenShouldContinueStaysTrue() async {
        let ids = (0..<3).map { _ in UUID() }
        var writeCalls: [UUID] = []
        let writer = HealthKitWorkoutStore.AutoApplyEffortWriter(
            write: { id, _ in
                writeCalls.append(id)
                return .written
            },
            isWriteAuthorized: { true }
        )
        let candidates = ids.map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 6)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: writer,
            shouldContinue: { true }
        )

        XCTAssertEqual(writeCalls, ids)
        XCTAssertEqual(result.appliedIDs, Set(ids))
    }

    @MainActor
    func testAutoApplyLoopStopsImmediatelyWhenShouldContinueFalse() async {
        var writeCalls: [UUID] = []
        let writer = HealthKitWorkoutStore.AutoApplyEffortWriter(
            write: { id, _ in
                writeCalls.append(id)
                return .written
            },
            isWriteAuthorized: { true }
        )
        let candidates = (0..<3).map {
            _ in HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: UUID(), score: 6)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: writer,
            shouldContinue: { false }
        )

        XCTAssertTrue(writeCalls.isEmpty)
        XCTAssertTrue(result.appliedIDs.isEmpty)
    }

    // MARK: - H7: cache-epoch skip decision

    func testMayApplyLoadOnlyWhenEpochUnchanged() {
        // No clear landed since the load captured the epoch — the load applies.
        XCTAssertTrue(HealthKitWorkoutStore.mayApplyLoad(capturedEpoch: 0, currentEpoch: 0))
        XCTAssertTrue(HealthKitWorkoutStore.mayApplyLoad(capturedEpoch: 3, currentEpoch: 3))
        // A Clear Cache bumped the epoch mid-load — the load must be skipped.
        XCTAssertFalse(HealthKitWorkoutStore.mayApplyLoad(capturedEpoch: 0, currentEpoch: 1))
        // Multiple clears while the load was suspended still skip.
        XCTAssertFalse(HealthKitWorkoutStore.mayApplyLoad(capturedEpoch: 2, currentEpoch: 5))
    }

    // MARK: - H4: cold-start source resolver keeps the stored selection

    @MainActor
    func testColdStartKeepsStoredIndividualSourceUntilDiscovery() {
        // A custom per-metric source the user previously chose.
        let individual = BodyHealthDataSourceOption(
            id: "bundle=com.example.tracker|name=example",
            name: "Example Tracker"
        )
        let selection = BodyHealthDataSourceSelection.defaultValue.setting(.heartRate, option: individual)
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 6, year: 2026, workouts: [], calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty,
            initialSummaryContextSignature: nil,
            initialHealthDataSourceSelection: selection
        )

        // `healthDataSourceOptionsByKind` is empty until source discovery runs, so
        // a cold start must KEEP the stored individual source rather than
        // collapsing it to All Sources (H4). A kind the user never customized
        // still resolves to All Sources.
        XCTAssertEqual(store.selectedHealthDataSourceOption(for: .heartRate), individual)
        XCTAssertTrue(store.selectedHealthDataSourceOption(for: .steps).isAllSources)
    }

    // MARK: - L1: negative-elapsed staleness

    func testIsWithinFreshIntervalTreatsNegativeElapsedAsStale() {
        // Fresh: non-negative and under the window.
        XCTAssertTrue(HealthKitWorkoutStore.isWithinFreshInterval(0, limit: 60))
        XCTAssertTrue(HealthKitWorkoutStore.isWithinFreshInterval(10, limit: 60))
        // Stale: at or beyond the window.
        XCTAssertFalse(HealthKitWorkoutStore.isWithinFreshInterval(60, limit: 60))
        XCTAssertFalse(HealthKitWorkoutStore.isWithinFreshInterval(120, limit: 60))
        // Backward clock jump — a negative elapsed counts as stale, not fresh, so
        // it neither suppresses a resume (debounce) nor pins the warm path.
        XCTAssertFalse(HealthKitWorkoutStore.isWithinFreshInterval(-1, limit: 60))
        XCTAssertFalse(HealthKitWorkoutStore.isWithinFreshInterval(-10_000, limit: 300))
    }
}
