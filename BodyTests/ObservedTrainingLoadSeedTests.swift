import HealthKit
import XCTest
@testable import Body

/// An observed Training Load repair (any saved effort rating, an Auto-Apply
/// write, a background revalidation) used to clear the compute seed's
/// Training Load piece before reading and never rebuild it. Every later
/// publish then shipped a seed without daily loads, the watch replaced its
/// stored seed with it, and the watch's Training Load replay (and with it its
/// Readiness stamp) stayed off until the next full iPhone refresh.
@MainActor
final class ObservedTrainingLoadSeedTests: XCTestCase {
    private struct Fixture {
        let store: HealthKitWorkoutStore
        let health: FakeHealthStore
        let ledger: BodyHealthDirtyWorkStore
        /// Rated, inside the hint span.
        let rated: HKWorkout
        /// Unrated, inside the hint span: counts at the default effort, no hint.
        let unrated: HKWorkout
        /// Rated, older than the hint span.
        let old: HKWorkout
    }

    private var effortType: HKQuantityType {
        HKObjectType.quantityType(forIdentifier: .workoutEffortScore)!
    }

    private func scriptEffort(_ health: FakeHealthStore, for workout: HKWorkout, _ script: FakeHealthStore.Script) {
        health.scriptSamples(
            for: effortType,
            matching: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil),
            script
        )
    }

    private func effort(_ score: Double, for workout: HKWorkout) -> FakeHealthStore.Script {
        .samples([HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: score),
            start: workout.endDate,
            end: workout.endDate
        )])
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        // The store restores and persists this seed through standard defaults.
        let persistedSeed = UserDefaults.standard.object(forKey: HealthDashboardSnapshotStore.watchTrainingLoadSeedKey)
        HealthDashboardSnapshotStore.clearWatchTrainingLoadSeed()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            BodyAppRuntime.setForegroundActive(foreground)
            restoreDefaults()
            UserDefaults.standard.set(persistedSeed, forKey: HealthDashboardSnapshotStore.watchTrainingLoadSeedKey)
            try? FileManager.default.removeItem(at: directory)
        }

        let now = Date()
        let rated = makeTestWorkout(activityType: .running, start: now.addingTimeInterval(-3 * 3_600),
            end: now.addingTimeInterval(-2 * 3_600), metadata: nil)
        let unrated = makeTestWorkout(activityType: .cycling, start: now.addingTimeInterval(-26 * 3_600),
            end: now.addingTimeInterval(-25.5 * 3_600), metadata: nil)
        let old = makeTestWorkout(activityType: .running, start: now.addingTimeInterval(-10 * 86_400),
            end: now.addingTimeInterval(-10 * 86_400 + 45 * 60), metadata: nil)
        let health = FakeHealthStore()
        health.scriptSamples(for: HKObjectType.workoutType(), .samples([old, unrated, rated]))
        health.scriptSamples(for: effortType, .samples([]))
        scriptEffort(health, for: rated, effort(4, for: rated))
        scriptEffort(health, for: old, effort(6, for: old))

        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let ledger = BodyHealthDirtyWorkStore(file: directory.appendingPathComponent("dirty.json"),
            domains: [.trainingLoad], context: store.currentObserverLedgerContext())
        try await body(Fixture(store: store, health: health, ledger: ledger,
                               rated: rated, unrated: unrated, old: old))
    }

    /// A Training Load delivery (an effort rating saved anywhere) and the
    /// foreground repair it schedules.
    @discardableResult
    private func repairTrainingLoad(_ fixture: Fixture) async throws -> Bool {
        await fixture.ledger.mark([.trainingLoad], context: fixture.store.currentObserverLedgerContext())
        let pending = await fixture.ledger.receipt(for: .trainingLoad)
        let receipt = try XCTUnwrap(pending)
        return await fixture.store.repairObservedMetrics([(.trainingLoad, receipt)], ledger: fixture.ledger)
    }

    private func published(_ store: HealthKitWorkoutStore) -> BodyCompanionPublishInput {
        store.makeCompanionPublishInput(shared: store.makeSharedPublishInput())
    }

    private func loadSum(_ input: BodyCompanionPublishInput) throws -> Double {
        try XCTUnwrap(input.trainingLoadDailyLoads).reduce(0, +)
    }

    func testObservedRepairRebuildsTheSeedWithTheNewRatingAndNoNewStamp() async throws {
        try await withFixture { fixture in
            let before = Date()
            let repaired = try await repairTrainingLoad(fixture)
            XCTAssertTrue(repaired)
            let first = published(fixture.store)
            let loads = try XCTUnwrap(first.trainingLoadDailyLoads)
            XCTAssertEqual(loads.count, 408, "407 lookback days plus today")
            let through = try XCTUnwrap(first.trainingLoadDataThrough)
            XCTAssertGreaterThanOrEqual(through, before)
            let startDay = try XCTUnwrap(first.trainingLoadStartDay)
            XCTAssertEqual(startDay, Calendar.bodyGregorian.date(
                byAdding: .day, value: -407, to: Calendar.bodyGregorian.startOfDay(for: through)
            ))
            // 60 min at 4, 30 min at the default 5, 45 min at 6.
            XCTAssertEqual(try loadSum(first), 60 * 4 + 30 * 5 + 45 * 6, accuracy: 1e-9)
            // Only the rated workout inside the span: the unrated one has no
            // rating to hint, and the old one is outside any delta window.
            XCTAssertEqual(first.trainingLoadEffortHints, [fixture.rated.uuid.uuidString: 4])
            // A repair pass mints no Training Load watermark.
            XCTAssertNil(first.trainingLoadComputeDate)

            // Re-rated (on the watch, in Fitness, or by Auto-Apply): the next
            // observed repair rebuilds the loads and the hint from the new
            // rating, still under no new watermark.
            scriptEffort(fixture.health, for: fixture.rated, effort(9, for: fixture.rated))
            let reRated = try await repairTrainingLoad(fixture)
            XCTAssertTrue(reRated)
            let second = published(fixture.store)
            XCTAssertEqual(try loadSum(second) - loadSum(first), 60 * (9 - 4), accuracy: 1e-9)
            XCTAssertEqual(second.trainingLoadEffortHints, [fixture.rated.uuid.uuidString: 9])
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(second.trainingLoadDataThrough), through)
            XCTAssertNil(second.trainingLoadComputeDate)
        }
    }

    func testFailedObservedReadKeepsThePreviousSeed() async throws {
        try await withFixture { fixture in
            let repaired = try await repairTrainingLoad(fixture)
            XCTAssertTrue(repaired)
            let first = published(fixture.store)
            XCTAssertNotNil(first.trainingLoadDailyLoads)

            // Training Load requires validated effort, so one failed rating
            // read fails the whole repair.
            scriptEffort(fixture.health, for: fixture.rated, .failure(nil))
            let failedRepair = try await repairTrainingLoad(fixture)
            XCTAssertFalse(failedRepair)

            let after = published(fixture.store)
            XCTAssertEqual(after.trainingLoadStartDay, first.trainingLoadStartDay)
            XCTAssertEqual(after.trainingLoadDailyLoads, first.trainingLoadDailyLoads)
            XCTAssertEqual(after.trainingLoadDataThrough, first.trainingLoadDataThrough)
            XCTAssertEqual(after.trainingLoadEffortHints, first.trainingLoadEffortHints)
        }
    }

    /// The periodic background check (`runBackground` revalidating a Training
    /// Load validated over 30 minutes ago) used to strip the seed with no
    /// delivery at all.
    func testBackgroundRevalidationRebuildsTheSeed() async throws {
        try await withFixture { fixture in
            let repaired = try await repairTrainingLoad(fixture)
            XCTAssertTrue(repaired)
            let first = published(fixture.store)

            scriptEffort(fixture.health, for: fixture.rated, effort(7, for: fixture.rated))
            BodyAppRuntime.setForegroundActive(false)
            let changed = await fixture.store.repairObservedMetrics(
                [], ledger: fixture.ledger, background: BodyBackgroundLease(), revalidating: [.trainingLoad]
            )
            XCTAssertTrue(changed)

            let after = published(fixture.store)
            XCTAssertEqual(after.trainingLoadDailyLoads?.count, 408)
            XCTAssertEqual(after.trainingLoadEffortHints, [fixture.rated.uuid.uuidString: 7])
            XCTAssertGreaterThanOrEqual(
                try XCTUnwrap(after.trainingLoadDataThrough), try XCTUnwrap(first.trainingLoadDataThrough)
            )
            XCTAssertNil(after.trainingLoadComputeDate)
        }
    }
}
