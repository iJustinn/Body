import XCTest
import UserNotifications
@testable import Body

final class BodyNotificationTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_006_400)
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = .gmt; return c }
    private var baselines: StressBaselines { .init(quietHeartRate: .init(median: 60, spread: 3, validDayCount: 30)) }
    private func samples(_ value: Double, start: Date) -> [HealthTrendDataPoint] {
        [0, 240, 480, 720].map { .init(date: start.addingTimeInterval(Double($0)), value: value) }
    }
    private func suite() -> UserDefaults { UserDefaults(suiteName: "BodyNotificationsTests.\(UUID())")! }

    func testMigrationPreservesLegacyUnsetAndExplicitOffAndDefaultsNewInstallOn() {
        for existing in [false, true] {
            let defaults = suite()
            if existing { defaults.set("1.1.0", forKey: BodyAppearancePreference.onboardingCompletedVersionKey) }
            BodyNotificationPreferences.migrate(defaults: defaults, now: day)
            XCTAssertEqual(defaults.bool(forKey: BodyAppearancePreference.metricWarningNotificationsKey), !existing)
            XCTAssertTrue(defaults.bool(forKey: BodyNotificationPreferences.masterKey))
            XCTAssertTrue(defaults.bool(forKey: BodyNotificationPreferences.stressKey))
            defaults.set(false, forKey: BodyNotificationPreferences.workoutKey)
            BodyNotificationPreferences.migrate(defaults: defaults)
            XCTAssertFalse(defaults.bool(forKey: BodyNotificationPreferences.workoutKey))
        }
        let defaults = suite()
        defaults.set(false, forKey: BodyAppearancePreference.metricWarningNotificationsKey)
        BodyNotificationPreferences.migrate(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: BodyAppearancePreference.metricWarningNotificationsKey))
        defaults.set(false, forKey: BodyNotificationPreferences.masterKey)
        XCTAssertFalse(BodyNotificationPreferences.enabled(BodyNotificationPreferences.stressKey, defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: BodyNotificationPreferences.stressKey))
    }

    func testCoverageRejectsPartialSparseAndLargeGaps() {
        let interval = DateInterval(start: day, duration: 900)
        XCTAssertTrue(BodyStressNotificationState.hasCoverage(interval, samples: samples(90, start: day)))
        XCTAssertFalse(BodyStressNotificationState.hasCoverage(DateInterval(start: day, duration: 899), samples: samples(90, start: day)))
        XCTAssertFalse(BodyStressNotificationState.hasCoverage(interval, samples: Array(samples(90, start: day).prefix(2))))
        XCTAssertFalse(BodyStressNotificationState.hasCoverage(interval, samples: [0, 300, 899].map { .init(date: day.addingTimeInterval(Double($0)), value: 90) }))
    }

    func testEpisodeRearmsOnlyAfterScoredRecoveryAndCoalescesPerPass() {
        let start = calendar.startOfDay(for: day)
        var input = StressDayInput(date: start)
        // High, high, missing, low, high. The last episode wins this pass.
        for (index, value) in [(0, 90.0), (1, 90.0), (3, 60.0), (4, 90.0)] {
            input.heartRateSamples += samples(value, start: start.addingTimeInterval(Double(index) * 900))
        }
        let prior = BodyStressNotificationState(context: "a", through: start, high: false)
        let result = BodyStressNotificationState.evaluate(input: input, baselines: baselines, prior: prior,
            since: start, now: start.addingTimeInterval(6300), calendar: calendar)
        XCTAssertEqual(result.event?.interval.start, start.addingTimeInterval(3600))
        XCTAssertTrue(result.state.high)
        let again = BodyStressNotificationState.evaluate(input: input, baselines: baselines, prior: result.state,
            since: start, now: start.addingTimeInterval(6300), calendar: calendar)
        XCTAssertNil(again.event)
    }

    func testMaturitySleepAndActivityMasks() {
        let start = calendar.startOfDay(for: day)
        var input = StressDayInput(date: start, heartRateSamples: samples(90, start: start))
        let prior = BodyStressNotificationState(context: "a", through: start, high: false)
        func evaluate(_ now: Date) -> StressWindow? {
            BodyStressNotificationState.evaluate(input: input, baselines: baselines, prior: prior,
                since: start, now: now, calendar: calendar).event
        }
        XCTAssertNil(evaluate(start.addingTimeInterval(2699)))
        XCTAssertNotNil(evaluate(start.addingTimeInterval(2700)))
        input.sleepInterval = DateInterval(start: start, duration: 900)
        XCTAssertNil(evaluate(start.addingTimeInterval(2700)))
        input.sleepInterval = nil
        input.workoutIntervals = [DateInterval(start: start, duration: 300)]
        XCTAssertNil(evaluate(start.addingTimeInterval(2700)))
    }

    private func entry(id: UUID = UUID(), start: Date, duration: Double = 1800) -> WorkoutJournalEntry {
        .init(id: id, start: start, end: start.addingTimeInterval(duration), activityType: 37,
              duration: duration, sourceBundleIdentifier: "test")
    }

    func testDuplicateSessionOverlap() {
        let a = entry(start: day)
        XCTAssertTrue(BodyNotificationDelivery.duplicates(a, entry(start: day.addingTimeInterval(60))))
        XCTAssertFalse(BodyNotificationDelivery.duplicates(a, entry(start: day.addingTimeInterval(500))))
        XCTAssertFalse(BodyNotificationDelivery.duplicates(a, entry(start: day, duration: 600)))
        XCTAssertTrue(BodyNotificationDelivery.duplicates(a, a))
    }

    actor Probe {
        var ids: [String] = []
        var fail = false
        func add(_ request: UNNotificationRequest) throws {
            if fail { throw NSError(domain: "test", code: 1) }
            ids.append(request.identifier)
        }
        func setFailure(_ value: Bool) { fail = value }
        func count() -> Int { ids.count }
    }

    func testStagedWorkoutWaitsForCommitRetriesAndSurvivesRelaunch() async throws {
        let defaults = suite(), now = day.addingTimeInterval(3600)
        BodyNotificationPreferences.migrate(defaults: defaults, now: day)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("workouts.json")
        let probe = Probe()
        let delivery = BodyNotificationDelivery.Delivery(authorization: { .authorized }, add: { try await probe.add($0) })
        let service = BodyNotificationDelivery(file: file, defaults: defaults, delivery: delivery, foreground: { false })
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: day, predicateVersion: 1))
        journal.staging = nil
        let workout = entry(start: day)
        let staged = await service.stage([workout], generation: journal.generation, revision: 1, now: now)
        XCTAssertTrue(staged)
        let lease = BodyBackgroundLease()
        await service.deliverWorkouts(journal: journal, lease: lease, now: now)
        var count = await probe.count(); XCTAssertEqual(count, 0)
        journal.revision = 1; journal.entries[workout.id.uuidString] = workout
        await probe.setFailure(true)
        await service.deliverWorkouts(journal: journal, lease: lease, now: now)
        count = await probe.count(); XCTAssertEqual(count, 0)
        await probe.setFailure(false)
        let resumed = BodyNotificationDelivery(file: file, defaults: defaults, delivery: delivery, foreground: { false })
        await resumed.deliverWorkouts(journal: journal, lease: lease, now: now)
        await resumed.deliverWorkouts(journal: journal, lease: lease, now: now)
        count = await probe.count(); XCTAssertEqual(count, 1)
    }

    func testStressFailedSubmissionRetriesAndForegroundDoesNotDeliver() async throws {
        let defaults = suite(), start = calendar.startOfDay(for: day)
        BodyNotificationPreferences.migrate(defaults: defaults, now: start)
        let input = StressDayInput(date: start, heartRateSamples: samples(90, start: start))
        let now = start.addingTimeInterval(2700), probe = Probe()
        let delivery = BodyNotificationDelivery.Delivery(authorization: { .authorized }, add: { try await probe.add($0) })
        let service = BodyNotificationDelivery(defaults: defaults, delivery: delivery, foreground: { false })
        await probe.setFailure(true)
        let lease = BodyBackgroundLease()
        await service.evaluateStress(input: input, baselines: baselines, context: "a", lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        XCTAssertNil(defaults.data(forKey: "notifications.stress.state"))
        await probe.setFailure(false)
        await service.evaluateStress(input: input, baselines: baselines, context: "a", lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        await service.evaluateStress(input: input, baselines: baselines, context: "a", lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        let count = await probe.count(); XCTAssertEqual(count, 1)
        XCTAssertNotNil(defaults.data(forKey: "notifications.stress.state"))
        let fresh = suite()
        BodyNotificationPreferences.migrate(defaults: fresh, now: start)
        let foreground = BodyNotificationDelivery(defaults: fresh, delivery: delivery, foreground: { true })
        await foreground.evaluateStress(input: input, baselines: baselines, context: "a", lease: nil, isCurrent: { true }, now: now, calendar: calendar)
        let after = await probe.count(); XCTAssertEqual(after, 1)
        XCTAssertNotNil(fresh.data(forKey: "notifications.stress.state"))
    }

    func testDeniedAndExpiredStressPassLeaveProgressUntouched() async {
        let start = calendar.startOfDay(for: day), input = StressDayInput(date: calendar.startOfDay(for: day),
            heartRateSamples: samples(90, start: calendar.startOfDay(for: day)))
        for denied in [true, false] {
            let defaults = suite()
            BodyNotificationPreferences.migrate(defaults: defaults, now: start)
            let probe = Probe()
            let service = BodyNotificationDelivery(defaults: defaults, delivery: .init(
                authorization: { denied ? .denied : .authorized }, add: { try await probe.add($0) }), foreground: { false })
            let lease = BodyBackgroundLease()
            if !denied { lease.invalidate() }
            await service.evaluateStress(input: input, baselines: baselines, context: "a", lease: lease,
                isCurrent: { true }, now: start.addingTimeInterval(2700), calendar: calendar)
            let count = await probe.count(); XCTAssertEqual(count, 0)
            XCTAssertNil(defaults.data(forKey: "notifications.stress.state"))
        }
    }

    func testSleepMigrationAddsCategoryWithoutResettingExistingChoices() {
        let defaults = suite()
        defaults.set(true, forKey: BodyNotificationPreferences.migrationKey)
        defaults.set(false, forKey: BodyNotificationPreferences.masterKey)
        BodyNotificationPreferences.migrate(defaults: defaults, now: day)
        XCTAssertTrue(defaults.bool(forKey: BodyNotificationPreferences.sleepKey))
        XCTAssertFalse(defaults.bool(forKey: BodyNotificationPreferences.masterKey))
        defaults.set(false, forKey: BodyNotificationPreferences.sleepKey)
        BodyNotificationPreferences.migrate(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: BodyNotificationPreferences.sleepKey))
    }

    func testSleepDeliveryRetriesDeduplicatesAndSkipsHistoricalNights() async {
        let defaults = suite(), start = calendar.startOfDay(for: day)
        BodyNotificationPreferences.migrate(defaults: defaults, now: start)
        let end = start.addingTimeInterval(8 * 3600), now = end.addingTimeInterval(1800)
        let sleep = SleepSummary(duration: 8 * 3600, stageSnapshot: .init(date: start,
            segments: [.init(stage: .core, startDate: start, endDate: end)]))
        let probe = Probe(), lease = BodyBackgroundLease()
        let service = BodyNotificationDelivery(defaults: defaults, delivery: .init(
            authorization: { .authorized }, add: { try await probe.add($0) }), foreground: { false })
        await probe.setFailure(true)
        await service.deliverSleep(sleep, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        XCTAssertNil(defaults.data(forKey: "notifications.sleep.receipts"))
        await probe.setFailure(false)
        await service.deliverSleep(sleep, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        await service.deliverSleep(sleep, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        let count = await probe.count(); XCTAssertEqual(count, 1)
        var updated = sleep
        updated.stageSnapshot.segments.append(.init(stage: .core, startDate: end, endDate: end.addingTimeInterval(300)))
        await service.deliverSleep(updated, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        await service.deliverSleep(sleep, lease: lease, isCurrent: { true }, now: now.addingTimeInterval(86400), calendar: calendar)
        let after = await probe.count(); XCTAssertEqual(after, 1)
    }

    func testSleepForegroundSeedingAndDisabledCategory() async {
        let defaults = suite(), start = calendar.startOfDay(for: day), end = calendar.startOfDay(for: day).addingTimeInterval(8 * 3600)
        BodyNotificationPreferences.migrate(defaults: defaults, now: start)
        let sleep = SleepSummary(duration: 8 * 3600, stageSnapshot: .init(date: start,
            segments: [.init(stage: .core, startDate: start, endDate: end)]))
        let probe = Probe()
        let delivery = BodyNotificationDelivery.Delivery(authorization: { .authorized }, add: { try await probe.add($0) })
        let foreground = BodyNotificationDelivery(defaults: defaults, delivery: delivery, foreground: { true })
        await foreground.deliverSleep(sleep, lease: nil, isCurrent: { true }, now: end, calendar: calendar)
        XCTAssertNotNil(defaults.data(forKey: "notifications.sleep.receipts"))
        let background = BodyNotificationDelivery(defaults: defaults, delivery: delivery, foreground: { false })
        await background.deliverSleep(sleep, lease: BodyBackgroundLease(), isCurrent: { true }, now: end, calendar: calendar)
        let count = await probe.count(); XCTAssertEqual(count, 0)
        defaults.removeObject(forKey: "notifications.sleep.receipts")
        defaults.set(false, forKey: BodyNotificationPreferences.sleepKey)
        await background.deliverSleep(sleep, lease: BodyBackgroundLease(), isCurrent: { true }, now: end, calendar: calendar)
        XCTAssertNil(defaults.data(forKey: "notifications.sleep.receipts"))
    }

    @MainActor func testSleepRouteReplacesPendingWorkoutAndWaitsForReadiness() {
        let route = BodyNotificationRoute()
        route.receive(["workoutID": UUID().uuidString, "workoutStart": day.timeIntervalSince1970])
        route.receive(["metric": "sleep"])
        XCTAssertNil(route.workout)
        XCTAssertEqual(route.selectedTab, .summary)
        XCTAssertNotNil(route.sleepRequestID)
        XCTAssertFalse(route.ready)
        let first = route.sleepRequestID
        route.receive(["metric": "sleep"])
        XCTAssertNotEqual(route.sleepRequestID, first)
    }

    @MainActor func testRouteValidatesPayloadAndRetainsPendingWorkout() {
        let route = BodyNotificationRoute(), id = UUID()
        route.receive(["workoutID": id.uuidString, "workoutStart": day.timeIntervalSince1970])
        XCTAssertEqual(route.selectedTab, .workouts)
        XCTAssertEqual(route.workout?.id, id)
        XCTAssertFalse(route.ready)
        route.receive(["workoutID": "bad", "workoutStart": Double.nan])
        XCTAssertNil(route.workout)
        XCTAssertEqual(route.selectedTab, .summary)
    }
}
