import HealthKit
import XCTest
@testable import Body

final class WorkoutRecordValidationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        HealthKitFetchEngine(permission: .init(enabledPermissions: [.workouts]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake, effortLedgerDirectoryURL: nil)
    }

    func testDistanceFailureRetainsContributionAndCheckpointThenEmptyAndRetryRepair() async throws {
        let workout = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800))
        let distanceType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning))
        let effortType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .workoutEffortScore))
        let fake = FakeHealthStore()
        let engine = makeEngine(fake)
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        fake.scriptSamples(for: effortType, .failure(nil))
        fake.scriptStatistics(for: distanceType, .failure(nil))

        var ledger = WorkoutRecordLedger()
        ledger.upsert(WorkoutSummary(id: workout.uuid, type: .running, startDate: start,
            duration: 1800, distanceMeters: 5000))
        ledger.scannedThrough = start
        let failed = try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false)
        XCTAssertEqual(failed.workouts.count, 1, "Display membership survives a detail failure")
        XCTAssertEqual(failed.unvalidatedRecordIDs, [workout.uuid])
        ledger.reconcile(workouts: failed.workouts, start: start, end: start.addingTimeInterval(3600),
            unvalidatedRecordIDs: failed.unvalidatedRecordIDs)
        XCTAssertEqual(ledger.contributions[workout.uuid]?.values[.distance], 5000)
        XCTAssertFalse(ledger.applyValidatedBaselineChunk(workouts: failed.workouts,
            scannedThrough: start.addingTimeInterval(3600), unvalidatedRecordIDs: failed.unvalidatedRecordIDs))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecordValidation.\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger, directoryURL: directory))
        ledger = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directory))
        XCTAssertEqual(ledger.scannedThrough, start)
        XCTAssertEqual(ledger.contributions[workout.uuid]?.values[.distance], 5000)

        fake.scriptCumulativeQuantity(for: distanceType, quantity: nil)
        let empty = try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false)
        XCTAssertTrue(empty.unvalidatedRecordIDs.isEmpty, "An effort failure is not a record-input failure")
        XCTAssertTrue(ledger.applyValidatedBaselineChunk(workouts: empty.workouts,
            scannedThrough: start.addingTimeInterval(3600), unvalidatedRecordIDs: empty.unvalidatedRecordIDs))
        XCTAssertNil(ledger.contributions[workout.uuid]?.values[.distance])
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger, directoryURL: directory))
        ledger = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directory))
        XCTAssertNil(ledger.contributions[workout.uuid]?.values[.distance])
        XCTAssertEqual(ledger.scannedThrough, start.addingTimeInterval(3600))

        fake.scriptCumulativeQuantity(for: distanceType, quantity: .init(unit: .meter(), doubleValue: 6000))
        let retry = try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false)
        ledger.reconcile(workouts: retry.workouts, start: start, end: start.addingTimeInterval(3600),
            unvalidatedRecordIDs: retry.unvalidatedRecordIDs)
        XCTAssertEqual(ledger.contributions[workout.uuid]?.values[.distance], 6000)
    }

    func testMembershipDeletionIsLimitedToSuccessfulCoveredInterval() {
        let inside = WorkoutSummary(id: UUID(), type: .running, startDate: start, duration: 1800, distanceMeters: 5000)
        let outside = WorkoutSummary(id: UUID(), type: .running, startDate: start.addingTimeInterval(-86400),
            duration: 1800, distanceMeters: 6000)
        var ledger = WorkoutRecordLedger()
        ledger.upsert([inside, outside])
        ledger.reconcile(workouts: [], start: start, end: start.addingTimeInterval(3600), unvalidatedRecordIDs: [])
        XCTAssertNil(ledger.contributions[inside.id])
        XCTAssertNotNil(ledger.contributions[outside.id])
    }

    func testCancelledDistanceReadCannotValidateChunk() async throws {
        let workout = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800))
        let distanceType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning))
        let effortType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .workoutEffortScore))
        let fake = FakeHealthStore()
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        fake.scriptSamples(for: effortType, .samples([]))
        fake.scriptStatistics(for: distanceType, .never)
        let engine = makeEngine(fake)
        let start = start
        let task = Task { try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false) }
        for _ in 0..<100 where !fake.leafRequests.contains(.statistics(distanceType.identifier)) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(fake.leafRequests.contains(.statistics(distanceType.identifier)))
        task.cancel()
        let result = try await task.value
        XCTAssertEqual(result.unvalidatedRecordIDs, [workout.uuid])
    }
}
