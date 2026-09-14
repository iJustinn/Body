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

    func testReadinessMigrationAddsCategoryWithoutResettingExistingChoices() {
        let defaults = suite()
        defaults.set(true, forKey: BodyNotificationPreferences.migrationKey)
        defaults.set(false, forKey: BodyNotificationPreferences.masterKey)
        BodyNotificationPreferences.migrate(defaults: defaults, now: day)
        XCTAssertTrue(defaults.bool(forKey: BodyNotificationPreferences.readinessKey))
        XCTAssertFalse(defaults.bool(forKey: BodyNotificationPreferences.masterKey))
        defaults.set(false, forKey: BodyNotificationPreferences.readinessKey)
        BodyNotificationPreferences.migrate(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: BodyNotificationPreferences.readinessKey))
    }

    func testReadinessDeliveryWaitsForSleepRetriesAndAnnouncesOncePerDay() async {
        let defaults = suite(), start = calendar.startOfDay(for: day)
        BodyNotificationPreferences.migrate(defaults: defaults, now: start)
        let now = start.addingTimeInterval(9 * 3600)
        let probe = Probe(), lease = BodyBackgroundLease()
        let service = BodyNotificationDelivery(defaults: defaults, delivery: .init(
            authorization: { .authorized }, add: { try await probe.add($0) }), foreground: { false })
        let provisional = RecordedReadinessEntry(date: start, score: 70, includedSleep: false, coverage: [])
        await service.deliverReadiness(provisional, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        XCTAssertNil(defaults.string(forKey: "notifications.readiness.lastDay"))
        let record = RecordedReadinessEntry(date: start, score: 82, includedSleep: true, coverage: [.sleepDuration])
        await probe.setFailure(true)
        await service.deliverReadiness(record, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        XCTAssertNil(defaults.string(forKey: "notifications.readiness.lastDay"))
        await probe.setFailure(false)
        await service.deliverReadiness(record, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        await service.deliverReadiness(record, lease: lease, isCurrent: { true }, now: now, calendar: calendar)
        let ids = await probe.ids
        XCTAssertEqual(ids, ["readiness.2023-11-15"])
        // Yesterday's record is never announced, and a since-date after the record day skips it.
        await service.deliverReadiness(record, lease: lease, isCurrent: { true }, now: now.addingTimeInterval(86400), calendar: calendar)
        let count = await probe.count(); XCTAssertEqual(count, 1)
    }

    func testReadinessForegroundSeedingAndDisabledCategory() async {
        let defaults = suite(), start = calendar.startOfDay(for: day), now = start.addingTimeInterval(9 * 3600)
        BodyNotificationPreferences.migrate(defaults: defaults, now: start)
        let record = RecordedReadinessEntry(date: start, score: 82, includedSleep: true, coverage: [.sleepDuration])
        let probe = Probe()
        let delivery = BodyNotificationDelivery.Delivery(authorization: { .authorized }, add: { try await probe.add($0) })
        let foreground = BodyNotificationDelivery(defaults: defaults, delivery: delivery, foreground: { true })
        await foreground.deliverReadiness(record, lease: nil, isCurrent: { true }, now: now, calendar: calendar)
        XCTAssertEqual(defaults.string(forKey: "notifications.readiness.lastDay"), "2023-11-15")
        let background = BodyNotificationDelivery(defaults: defaults, delivery: delivery, foreground: { false })
        await background.deliverReadiness(record, lease: BodyBackgroundLease(), isCurrent: { true }, now: now, calendar: calendar)
        let count = await probe.count(); XCTAssertEqual(count, 0)
        defaults.removeObject(forKey: "notifications.readiness.lastDay")
        defaults.set(false, forKey: BodyNotificationPreferences.readinessKey)
        await background.deliverReadiness(record, lease: BodyBackgroundLease(), isCurrent: { true }, now: now, calendar: calendar)
        XCTAssertNil(defaults.string(forKey: "notifications.readiness.lastDay"))
    }

    /// Sleep syncing while the app is closed: the background pass has no frozen record
    /// (observed leaves skip the derived recompute), so the notification pass freezes
    /// one itself from the persisted leaves, and only once the wake+10 window is open.
    func testBackgroundPassFreezesSleepInclusiveRecordForDelivery() async throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let inBed = scoreDay.addingTimeInterval(3_600), wake = inBed.addingTimeInterval(7 * 3_600)
        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        var summary = HealthSummarySnapshot.empty
        summary.sleep = SleepSummary(duration: 7 * 3_600, stageSnapshot: .init(date: scoreDay,
            segments: [.init(stage: .core, startDate: inBed, endDate: wake)]))
        trends.sleepHistory = SleepHistorySnapshot(days: [SleepDaySummary(date: scoreDay, summary: summary.sleep)])

        // A record frozen under an older input context, as the persisted cache may hold.
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: scoreDay))
        trends.recordedReadiness = [RecordedReadinessEntry(date: yesterday, score: 50, includedSleep: true, coverage: [.sleepDuration])]
        trends.recordedReadinessContext = "old"

        XCTAssertNil(HealthKitWorkoutStore.morningReadinessRecord(summary: summary, trends: trends,
            idealSleepDuration: 8 * 3_600, recordedReadinessContext: "new", now: wake.addingTimeInterval(300), calendar: calendar),
            "before wake+10 nothing is frozen, so nothing is announced")
        let freeze = try XCTUnwrap(HealthKitWorkoutStore.morningReadinessRecord(summary: summary, trends: trends,
            idealSleepDuration: 8 * 3_600, recordedReadinessContext: "new", now: wake.addingTimeInterval(900), calendar: calendar))
        let record = freeze.entry
        XCTAssertEqual(calendar.startOfDay(for: record.date), scoreDay)
        XCTAssertTrue(try XCTUnwrap(record.coverage).contains(.sleepDuration))
        XCTAssertEqual(freeze.context, "new")
        XCTAssertEqual(freeze.records, [record], "the stale-context record is dropped, as the dashboard recompute would")

        // Persisted as the pass does, the next foreground recompute under the same
        // context keeps the announced record instead of discarding it.
        var persisted = trends
        persisted.recordedReadiness = freeze.records
        persisted.recordedReadinessContext = freeze.context
        let reloaded = HealthDashboardSnapshot(summary: summary, trends: persisted).recalculatingReadiness(
            on: wake.addingTimeInterval(3_600), idealSleepDuration: 8 * 3_600, calendar: calendar, wakeTime: wake,
            now: wake.addingTimeInterval(3_600), freezesRecordedReadiness: true, recordedReadinessContext: "new")
        XCTAssertEqual(reloaded.trends.recordedReadiness, [record])

        let defaults = suite()
        BodyNotificationPreferences.migrate(defaults: defaults, now: scoreDay)
        let probe = Probe()
        let service = BodyNotificationDelivery(defaults: defaults, delivery: .init(
            authorization: { .authorized }, add: { try await probe.add($0) }), foreground: { false })
        await service.deliverReadiness(record, lease: BodyBackgroundLease(), isCurrent: { true },
                                       now: wake.addingTimeInterval(900), calendar: calendar)
        let ids = await probe.ids
        XCTAssertEqual(ids, ["readiness.2026-05-17"])
    }

    /// Success, then a failed refresh seconds later, then a successful retry: the
    /// stamp survives the failure untouched (same date, same context), so only the
    /// pass generation can tell the failed pass from the ones that validated.
    func testBackgroundFreezeRequiresSleepValidatedInThisPass() {
        let context = "ctx"
        let stamp = HealthDashboardSnapshotStore.Freshness(date: day, contextSignature: context)
        // Pass 1 validates sleep at 08:09:50.
        XCTAssertTrue(HealthKitWorkoutStore.sleepValidatedInThisPass(stamp, context: context,
            validatedGeneration: 1, currentGeneration: 1))
        // Pass 2 at 08:10:10 fails its sleep refresh: the stamp is still the 20-second-old one.
        XCTAssertFalse(HealthKitWorkoutStore.sleepValidatedInThisPass(stamp, context: context,
            validatedGeneration: 1, currentGeneration: 2))
        // Pass 3 retries and validates.
        XCTAssertTrue(HealthKitWorkoutStore.sleepValidatedInThisPass(stamp, context: context,
            validatedGeneration: 3, currentGeneration: 3))
        XCTAssertFalse(HealthKitWorkoutStore.sleepValidatedInThisPass(stamp, context: "other",
            validatedGeneration: 3, currentGeneration: 3))
        XCTAssertFalse(HealthKitWorkoutStore.sleepValidatedInThisPass(nil, context: context,
            validatedGeneration: 3, currentGeneration: 3))
        XCTAssertFalse(HealthKitWorkoutStore.sleepValidatedInThisPass(stamp, context: context,
            validatedGeneration: nil, currentGeneration: 1))
    }

    @MainActor func testReadinessRouteReplacesPendingWorkoutAndSleep() {
        let route = BodyNotificationRoute()
        route.receive(["workoutID": UUID().uuidString, "workoutStart": day.timeIntervalSince1970])
        route.receive(["metric": "sleep"])
        route.receive(["metric": "readiness"])
        XCTAssertNil(route.workout)
        XCTAssertNil(route.sleepRequestID)
        XCTAssertNotNil(route.readinessRequestID)
        XCTAssertEqual(route.selectedTab, .summary)
        route.receive(["metric": "sleep"])
        XCTAssertNil(route.readinessRequestID)
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
