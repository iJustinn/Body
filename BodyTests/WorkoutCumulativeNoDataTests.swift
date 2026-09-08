import HealthKit
import XCTest
@testable import Body

final class WorkoutCumulativeNoDataTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let noData = NSError(domain: HKErrorDomain, code: HKError.errorNoData.rawValue)

    private func fixture() throws -> (FakeHealthStore, HealthKitFetchEngine, HKWorkout, WorkoutSummary) {
        let fake = FakeHealthStore()
        // Indoor avoids the unrelated native VO2 callback path, which is outside
        // FakeHealthStore's seam. Cadence and distance still run for indoor runs.
        let workout = HKWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800),
            workoutEvents: nil, totalEnergyBurned: nil, totalDistance: nil,
            metadata: [HKMetadataKeyIndoorWorkout: true])
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        for identifier: HKQuantityTypeIdentifier in [.workoutEffortScore, .vo2Max] {
            fake.scriptSamples(for: try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: identifier)), .samples([]))
        }
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: [.workouts, .workoutMetrics]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake, effortLedgerDirectoryURL: nil)
        let cached = WorkoutSummary(id: workout.uuid, type: .running, startDate: start, duration: 1800,
            distanceMeters: 5000, averageStepCadenceSPM: 180)
        return (fake, engine, workout, cached)
    }

    private func script(_ fake: FakeHealthStore, _ identifier: HKQuantityTypeIdentifier,
                        _ value: FakeHealthStore.Script) throws {
        fake.scriptStatistics(for: try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: identifier)), value)
    }

    private func fetch(_ engine: HealthKitFetchEngine, fake: FakeHealthStore,
        cached: WorkoutSummary? = nil) async throws -> HealthKitFetchEngine.WorkoutSummariesFetchResult {
        let start = start
        let task = Task { try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false,
            reusableSummariesByID: cached.map { [$0.id: $0] } ?? [:]) }
        let outcome = await OneShotDeadlineRace.run(deadline: .seconds(5)) { await task.result }
        task.cancel()
        guard case .finished(let result) = outcome else {
            let nativeTypes = fake.executedQueries.map { $0.objectType?.identifier ?? "unknown" }
            XCTFail("Unexpected suspended fixture. Leaves: \(fake.leafRequests); native queries: \(nativeTypes)")
            throw CancellationError()
        }
        return try result.get()
    }

    func testTypedNoDataClearsCachedFieldsAndValidatesMonthAndRecordInput() async throws {
        let (fake, engine, workout, cached) = try fixture()
        try script(fake, .stepCount, .failure(noData))
        try script(fake, .distanceWalkingRunning, .failure(noData))
        let result = try await fetch(engine, fake: fake, cached: cached)
        XCTAssertFalse(result.hadQueryFailure)
        XCTAssertFalse(result.hasUnvalidatedDetails)
        XCTAssertTrue(result.unvalidatedRecordIDs.isEmpty)
        let summary = try XCTUnwrap(result.workouts.first)
        XCTAssertNil(summary.distanceMeters)
        XCTAssertNil(summary.averageStepCadenceSPM)
        var month = WorkoutMonthSnapshot.make(month: 11, year: 2023, workouts: result.workouts)
        month.recordValidation(at: start, context: "same", previous: nil,
            allDetailsValidated: !result.hasUnvalidatedDetails, hadQueryFailure: result.hadQueryFailure)
        XCTAssertEqual(month.validatedAt, start)
        var ledger = WorkoutRecordLedger()
        ledger.upsert(cached)
        XCTAssertTrue(ledger.applyValidatedBaselineChunk(workouts: result.workouts,
            scannedThrough: start, unvalidatedRecordIDs: result.unvalidatedRecordIDs))
        XCTAssertNil(ledger.contributions[workout.uuid]?.values[.distance])
        // The generic seam still exposes the original error; only workout reads normalize.
        let generic = await fake.cumulativeQuantity(.init(
            quantityType: try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .stepCount)),
            predicate: nil, options: .cumulativeSum))
        guard case .failure = generic else { return XCTFail("Do not normalize general statistics") }
    }

    func testOtherErrorsRemainFailuresAndPreserveCachedValues() async throws {
        let errors: [Error?] = [nil,
            NSError(domain: HKErrorDomain, code: HKError.errorAuthorizationDenied.rawValue),
            NSError(domain: HKErrorDomain, code: HKError.errorDatabaseInaccessible.rawValue),
            NSError(domain: HKErrorDomain, code: HKError.errorInvalidArgument.rawValue),
            NSError(domain: "UnrelatedDomain", code: HKError.errorNoData.rawValue)]
        for error in errors {
            let (fake, engine, workout, cached) = try fixture()
            try script(fake, .stepCount, .failure(error))
            try script(fake, .distanceWalkingRunning, .failure(error))
            let result = try await fetch(engine, fake: fake, cached: cached)
            XCTAssertTrue(result.hadQueryFailure)
            XCTAssertTrue(result.hasUnvalidatedDetails)
            XCTAssertEqual(result.unvalidatedRecordIDs, [workout.uuid])
            XCTAssertEqual(result.workouts.first?.distanceMeters, cached.distanceMeters)
            XCTAssertEqual(result.workouts.first?.averageStepCadenceSPM, cached.averageStepCadenceSPM)
            var month = WorkoutMonthSnapshot.make(month: 11, year: 2023, workouts: result.workouts)
            month.recordValidation(at: start, context: "same", previous: nil,
                allDetailsValidated: !result.hasUnvalidatedDetails, hadQueryFailure: result.hadQueryFailure)
            XCTAssertNil(month.validatedAt)
        }
    }

    func testSuccessfulCumulativeValuesKeepUnitsAndCadenceCalculation() async throws {
        let (fake, engine, _, _) = try fixture()
        fake.scriptCumulativeQuantity(for: try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .stepCount)),
            quantity: HKQuantity(unit: .count(), doubleValue: 3000))
        fake.scriptCumulativeQuantity(for: try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)),
            quantity: HKQuantity(unit: .meter(), doubleValue: 4500))
        let result = try await fetch(engine, fake: fake)
        XCTAssertEqual(result.workouts.first?.averageStepCadenceSPM, 100)
        XCTAssertEqual(result.workouts.first?.distanceMeters, 4500)
        XCTAssertFalse(result.hasUnvalidatedDetails)
    }

    func testCancelledCadenceReadDoesNotValidateMonth() async throws {
        let (fake, engine, _, _) = try fixture()
        try script(fake, .stepCount, .never)
        try script(fake, .distanceWalkingRunning, .failure(noData))
        let start = start
        let task = Task { try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false) }
        for _ in 0..<100 where !fake.leafRequests.contains(.statistics(HKQuantityTypeIdentifier.stepCount.rawValue)) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(fake.leafRequests.contains(.statistics(HKQuantityTypeIdentifier.stepCount.rawValue)))
        task.cancel()
        let result = try await task.value
        XCTAssertTrue(result.hadQueryFailure)
        XCTAssertTrue(result.hasUnvalidatedDetails)
    }
}
