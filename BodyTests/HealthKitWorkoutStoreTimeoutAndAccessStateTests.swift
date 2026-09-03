//
//  HealthKitWorkoutStoreTimeoutAndAccessStateTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

/// Covers two P2 findings:
///  - the 120s refresh-deadline timeout branch of `runRefreshWithDeadline`
///    must persist a workout month that already landed in memory before the
///    deadline fired, not just the dashboard snapshot.
///  - `isHealthPermissionLoadInFlight` must also count the unjoined
///    background activity-ring backfill task, not just `isRefreshing` and
///    `loadingActivityRingMonthKeys`.
final class HealthKitWorkoutStoreTimeoutAndAccessStateTests: XCTestCase {

    // MARK: - Finding A: timeout branch persists landed workout months

    @MainActor
    func testRefreshDeadlineTimeoutPersistsAlreadyLandedCurrentMonthSnapshot() async throws {
        // `persistRecentMonthSnapshots`'s normal save path writes to the real
        // App Group directory, which is unavailable in this unsigned test
        // target (`WorkoutSnapshotStore.sharedContainerURL` is nil here). Point
        // it at a scratch directory via the test-only override instead of
        // asserting against the (always-nil-here) real container.
        let snapshotDirectoryURL = temporaryMonthSnapshotDirectoryURL()
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = snapshotDirectoryURL
        addTeardownBlock {
            HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = nil
            try? FileManager.default.removeItem(at: snapshotDirectoryURL.deletingLastPathComponent())
        }

        let calendar = Calendar.bodyGregorian
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let month = try XCTUnwrap(components.month)
        let year = try XCTUnwrap(components.year)

        let landedWorkout = WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: now,
            duration: 1_800,
            activeEnergyKilocalories: 200,
            distanceMeters: 3_000,
            sourceName: "Tests"
        )
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: month,
            year: year,
            workouts: [landedWorkout],
            calendar: calendar
        )

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [initialSnapshot],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue
        )
        XCTAssertEqual(store.monthSnapshots[BodyWorkoutMonthKey(month: month, year: year)]?.workoutCount, 1)

        // A tiny deadline with a body that never finishes forces the timeout
        // branch deterministically without waiting on the real 120s deadline.
        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(60))
        }

        XCTAssertFalse(completed)

        // The save happens on `HealthKitWorkoutStore`'s serial persist queue,
        // asynchronously to `runRefreshWithDeadline`'s return — poll briefly
        // rather than assuming it has already landed.
        let persisted = try await waitForCondition(timeout: .seconds(5)) {
            WorkoutSnapshotStore.load(month: month, year: year, directoryURL: snapshotDirectoryURL)
        }
        XCTAssertEqual(persisted?.month, month)
        XCTAssertEqual(persisted?.year, year)
        XCTAssertEqual(persisted?.workoutCount, 1)
        XCTAssertEqual(persisted?.days.flatMap(\.workouts).first?.id, landedWorkout.id)
    }

    private func temporaryMonthSnapshotDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(WorkoutSnapshotStore.monthSnapshotsDirectoryName, isDirectory: true)
    }

    /// Polls `probe` until it returns a non-nil value or `timeout` elapses,
    /// for asserting on work handed off to the persist queue.
    private func waitForCondition<T>(
        timeout: Duration,
        probe: @escaping () -> T?
    ) async throws -> T? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = probe() {
                return value
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return probe()
    }

    // MARK: - Finding B: background ring backfill counts as in-flight

    /// The store reads both first-load defaults from standard defaults at
    /// init; park them so a previous run on this host cannot mask the
    /// fresh-install state, and restore them from the returned closure.
    /// Duplicated from `HealthKitWorkoutStoreTests` (owned by another agent
    /// concurrently) rather than shared, per this file's ownership scope.
    private func preserveInitialHealthLoadDefaults() -> () -> Void {
        let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        let preservedCompletion = HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
        return {
            if let preservedRefreshDate {
                HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(preservedRefreshDate)
            }
            if preservedCompletion {
                HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()
            } else {
                HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
            }
        }
    }

    @MainActor
    func testActivityRingHistoryTaskInFlightReportsCheckingForActivityRings() {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [WorkoutMonthSnapshot.make(
                month: 1,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            )],
            initialHealthDashboardSnapshot: .empty
        )

        // Simulate the unjoined background ring backfill still being in
        // flight — the property is `internal` (not `private`) specifically so
        // this can be set deterministically via @testable import instead of
        // racing the real HealthKit-backed chunk walk.
        store.activityRingHistoryTask = Task {}
        defer { store.activityRingHistoryTask?.cancel() }

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)

        XCTAssertEqual(states[.activityRings], .checking)
    }

    @MainActor
    func testNoActivityRingHistoryTaskDoesNotForceChecking() {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [WorkoutMonthSnapshot.make(
                month: 1,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            )],
            initialHealthDashboardSnapshot: .empty
        )

        XCTAssertNil(store.activityRingHistoryTask)

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)

        XCTAssertNotEqual(states[.activityRings], .checking)
    }
}
