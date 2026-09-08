import HealthKit
import XCTest
@testable import Body

final class WorkoutEffortValidationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_500_000)
    private func engine(_ fake: FakeHealthStore, directory: URL? = nil) -> HealthKitFetchEngine {
        HealthKitFetchEngine(permission: .defaultValue, healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
            healthStore: fake, effortLedgerDirectoryURL: directory)
    }
    private func workout() -> HKWorkout {
        HKWorkout(activityType: .running, start: now.addingTimeInterval(-150 * 86400),
            end: now.addingTimeInterval(-150 * 86400 + 3600))
    }
    private func effort(_ score: Double) throws -> HKQuantitySample {
        .init(type: try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore)),
            quantity: .init(unit: .appleEffortScore(), doubleValue: score), start: now, end: now)
    }

    func testAgedScoreExpiresFailureDoesNotValidateAndSuccessfulAbsenceDeletes() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore))
        let workout = workout()
        let engine = engine(fake)
        fake.scriptSamples(for: type, .samples([try effort(7)]))
        let first = await engine.fetchEffortLevels(forWorkouts: [workout], now: now)
        XCTAssertEqual(first.levels[workout.uuid], 7)
        fake.scriptSamples(for: type, .failure(nil))
        let fresh = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(86399))
        XCTAssertTrue(fresh.failedIDs.isEmpty)
        let failed = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(86400))
        XCTAssertEqual(failed.levels[workout.uuid], 7)
        XCTAssertEqual(failed.failedIDs, [workout.uuid])
        let dates = await engine.effortWorkoutDatesByID
        XCTAssertEqual(dates[workout.uuid]?.validatedAt, now)
        fake.scriptSamples(for: type, .samples([]))
        let deleted = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(86401))
        XCTAssertNil(deleted.levels[workout.uuid])
        XCTAssertTrue(deleted.failedIDs.isEmpty)
        fake.scriptSamples(for: type, .samples([try effort(9)]))
        let late = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(2 * 86400 + 1))
        XCTAssertEqual(late.levels[workout.uuid], 9)
    }

    func testOverlappingExpiredGathersReuseAdmittedScoreOrAbsenceWithoutFailure() async throws {
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore))
        for peerHasScore in [false, true] {
            let fake = FakeHealthStore()
            let engine = engine(fake)
            let workout = workout()
            fake.scriptSamples(for: type, .samples([try effort(7)]))
            _ = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(-86400))
            let before = fake.leafRequests.count
            let delayedSamples = peerHasScore ? [] : [try effort(5)]
            fake.scriptSamples(for: type, .delay(.milliseconds(500), then: .samples(delayedSamples)))
            let now = now
            let delayed = Task { await engine.fetchEffortLevels(forWorkouts: [workout], now: now) }
            defer { delayed.cancel() }
            for _ in 0..<100 where fake.leafRequests.count == before {
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertEqual(fake.leafRequests.count, before + 1)
            fake.scriptSamples(for: type, .samples(peerHasScore ? [try effort(9)] : []))
            let peer = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(1))
            let late = await delayed.value
            XCTAssertTrue(peer.failedIDs.isEmpty)
            XCTAssertTrue(late.failedIDs.isEmpty)
            XCTAssertEqual(peer.levels[workout.uuid], peerHasScore ? 9 : nil)
            XCTAssertEqual(late.levels, peer.levels, "Late gather must not overwrite admitted score or absence")
            XCTAssertEqual(fake.leafRequests.count, before + 2, "Both expired gathers queried")
        }
    }

    func testLegacyMissingTimestampRollbackAndChangedDatesAreStale() throws {
        let workout = workout()
        let legacy = WorkoutEffortLedgerEntry(startDate: workout.startDate, endDate: workout.endDate, effort: 7)
        let data = try JSONEncoder().encode(legacy)
        XCTAssertNil(try JSONDecoder().decode(WorkoutEffortLedgerEntry.self, from: data).validatedAt)
        var range = WorkoutEffortDateRange(startDate: workout.startDate, endDate: workout.endDate)
        XCTAssertFalse(HealthKitFetchEngine.effortValidationIsFresh(range, startDate: workout.startDate, endDate: workout.endDate, now: now))
        range.validatedAt = now
        XCTAssertFalse(HealthKitFetchEngine.effortValidationIsFresh(range, startDate: workout.startDate, endDate: workout.endDate, now: now.addingTimeInterval(-1)))
        XCTAssertFalse(HealthKitFetchEngine.effortValidationIsFresh(range, startDate: workout.startDate, endDate: workout.endDate.addingTimeInterval(1), now: now))
    }

    func testTrainingLoadRejectsExpiredCachedFallbackAndAllThreeConsumersFailClosed() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore))
        let workout = workout()
        let engine = engine(fake)
        fake.scriptSamples(for: type, .samples([try effort(7)]))
        _ = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(-10 * 86400))
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        fake.scriptSamples(for: type, .failure(nil))
        await engine.setHealthTrendAnchorDate(now)
        let summary = await engine.fetchTrainingLoadSummary(calendar: .bodyGregorian)
        if case .success = summary { XCTFail("Cached effort fallback must not renew derived freshness") }
        let series = await engine.fetchTrainingLoadSeries(calendar: .bodyGregorian)
        let seed = await engine.trainingLoadDailyLoadSeed(calendar: .bodyGregorian)
        XCTAssertNil(series)
        XCTAssertNil(seed)
        let cached = await engine.effortLevelsByWorkoutID
        XCTAssertEqual(cached[workout.uuid], 7)
    }

    func testValidationTimestampSurvivesLedgerReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EffortValidation.\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let workout = workout()
        let entry = WorkoutEffortLedgerEntry(startDate: workout.startDate, endDate: workout.endDate,
            effort: 6, validatedAt: now)
        XCTAssertTrue(WorkoutEffortLedgerStore.save(.init(entries: [workout.uuid: entry]), directoryURL: directory))
        let fake = FakeHealthStore()
        let engine = engine(fake, directory: directory)
        let result = await engine.fetchEffortLevels(forWorkouts: [workout], now: now.addingTimeInterval(1))
        XCTAssertEqual(result.levels[workout.uuid], 6)
        XCTAssertTrue(fake.leafRequests.isEmpty)
    }

    func testClearDuringSuspendedEffortReadCannotRepopulateOrValidate() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .workoutEffortScore))
        fake.scriptSamples(for: type, .delay(.milliseconds(200), then: .samples([try effort(7)])))
        let engine = engine(fake)
        let workout = workout()
        let now = now
        let task = Task { await engine.fetchEffortLevels(forWorkouts: [workout], now: now) }
        for _ in 0..<100 where fake.leafRequests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(fake.leafRequests.isEmpty)
        await engine.clearWorkoutEffortCache()
        let result = await task.value
        XCTAssertEqual(result.failedIDs, [workout.uuid])
        let dates = await engine.effortWorkoutDatesByID
        let levels = await engine.effortLevelsByWorkoutID
        XCTAssertTrue(dates.isEmpty)
        XCTAssertTrue(levels.isEmpty)
    }
}
