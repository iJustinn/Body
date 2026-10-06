import XCTest
import HealthKit
import UserNotifications
@testable import Body

final class MetricWarningSubmissionTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: (calendar: Calendar, date: Date) = (.bodyGregorian, Date())
        func read() -> (calendar: Calendar, date: Date) { lock.withLock { value } }
        func change(zone: Bool) {
            lock.withLock {
                if zone {
                    value.calendar.timeZone = TimeZone(secondsFromGMT: value.calendar.timeZone.secondsFromGMT() == 0 ? 3600 : 0)!
                } else {
                    value.date = value.calendar.date(byAdding: .day, value: 1, to: value.date)!
                }
            }
        }
    }
    private actor Gate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if open { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            open = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private actor Probe {
        var count = 0
        var foreground = false
        var fail = false
        /// The add count each time a pass handed the ledger over.
        var notified: [Int] = []
        func notify() { notified.append(count) }
        /// Whether the task's lease was valid each time a pass handed the ledger over.
        var leaseValidity: [Bool?] = []
        func recordLease(_ valid: Bool?) { leaseValidity.append(valid) }
        private var foregroundChecks = 0
        func foregroundOnCheck(_ target: Int) -> Bool {
            foregroundChecks += 1
            return foregroundChecks == target
        }
        func setForeground() { foreground = true }
        func setFailure(_ value: Bool) { fail = value }
        func add() throws {
            count += 1
            if fail { throw NSError(domain: "InjectedDelivery", code: 1) }
        }
    }

    private func defaults() throws -> UserDefaults {
        let name = "BodyTests.WarningSubmission.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { suite.removePersistentDomain(forName: name) }
        suite.set(true, forKey: BodyAppearancePreference.metricWarningNotificationsKey)
        suite.set(BodyMetricWarningSelection(enabledKinds: [.lowHeartRate]).rawValue,
                  forKey: BodyAppearancePreference.metricWarningsKey)
        return suite
    }

    private func event() -> MetricWarningEvent {
        .init(kind: .lowHeartRate, startDate: Date(), endDate: Date(), extremeValue: 35, sampleCount: 1)
    }

    func testSettingsChangesDuringFetchPreventSubmission() async throws {
        for key in [BodyAppearancePreference.metricWarningNotificationsKey,
                    BodyAppearancePreference.metricWarningsKey,
                    BodyAppearancePreference.metricWarningThresholdsKey,
                    BodyAppearancePreference.healthDataSourceSelectionKey,
                    BodyAppearancePreference.healthPermissionSelectionKey,
                    BodyAppearancePreference.customHealthSourceGroupsKey] {
            let suite = try defaults(), gate = Gate(), probe = Probe()
            let started = expectation(description: key)
            let warning = event()
            let evaluator = MetricWarningBackgroundEvaluator(
                defaults: suite,
                delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
                warningQuery: { _ in started.fulfill(); await gate.wait(); return [.lowHeartRate: .success(warning)] },
                isForegroundActive: { false }
            )
            let task = Task { await evaluator.evaluate() }
            await fulfillment(of: [started], timeout: 3)
            suite.set("changed", forKey: key)
            await gate.release()
            let outcome = await task.value
            XCTAssertEqual(outcome, .skipped)
            let count = await probe.count
            XCTAssertEqual(count, 0, key)
            XCTAssertNil(suite.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey))
        }
    }

    func testForegroundOrCancellationDuringFetchPreventsSubmission() async throws {
        for cancel in [false, true] {
            let suite = try defaults(), gate = Gate(), probe = Probe()
            let started = expectation(description: "fetch")
            let warning = event()
            let evaluator = MetricWarningBackgroundEvaluator(
                defaults: suite,
                delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
                warningQuery: { _ in started.fulfill(); await gate.wait(); return [.lowHeartRate: .success(warning)] },
                isForegroundActive: { await probe.foreground }
            )
            let task = Task { await evaluator.evaluate() }
            await fulfillment(of: [started], timeout: 3)
            if cancel { task.cancel() } else { await probe.setForeground() }
            await gate.release()
            let outcome = await task.value
            XCTAssertEqual(outcome, .skipped)
            let count = await probe.count
            XCTAssertEqual(count, 0)
        }
    }

    func testCalendarOrDayChangeDuringFetchPreventsSubmission() async throws {
        for zone in [false, true] {
            let suite = try defaults(), gate = Gate(), probe = Probe(), clock = Clock()
            let started = expectation(description: "calendar-sensitive fetch")
            let warning = event()
            let evaluator = MetricWarningBackgroundEvaluator(
                defaults: suite,
                delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
                warningQuery: { _ in started.fulfill(); await gate.wait(); return [.lowHeartRate: .success(warning)] },
                calendarContext: { clock.read() }, isForegroundActive: { false }
            )
            let task = Task { await evaluator.evaluate() }
            await fulfillment(of: [started], timeout: 3)
            clock.change(zone: zone)
            await gate.release()
            let outcome = await task.value
            XCTAssertEqual(outcome, .skipped)
            let count = await probe.count
            XCTAssertEqual(count, 0)
        }
    }

    func testSeedDuringAddSurvivesAndOverlappingEvaluationDoesNotSubmit() async throws {
        let suite = try defaults(), gate = Gate(), probe = Probe()
        let started = expectation(description: "add")
        let warning = event()
        let evaluator = MetricWarningBackgroundEvaluator(
            defaults: suite,
            delivery: .init(authorization: { .authorized }, add: { _ in
                try await probe.add(); started.fulfill(); await gate.wait()
            }),
            warningQuery: { _ in [.lowHeartRate: .success(warning)] },
            isForegroundActive: { false }
        )
        let task = Task { await evaluator.evaluate() }
        await fulfillment(of: [started], timeout: 3)
        let nextDay = Calendar.bodyGregorian.date(byAdding: .day, value: 1, to: warning.startDate)!
        await evaluator.seed(kinds: [.lowBloodOxygen: warning.startDate, .lowHeartRate: nextDay])
        let overlapping = await evaluator.evaluate()
        XCTAssertEqual(overlapping, .skipped)
        await gate.release()
        let outcome = await task.value
        XCTAssertEqual(outcome, .success)
        let count = await probe.count
        XCTAssertEqual(count, 1)
        let ledger = MetricWarningNotificationLedger.storedValue(
            from: suite.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey) ?? "")
        var expected = MetricWarningNotificationLedger.defaultValue
        expected.markNotified(kind: .lowBloodOxygen, on: warning.startDate, calendar: .bodyGregorian)
        expected.markNotified(kind: .lowHeartRate, on: nextDay, calendar: .bodyGregorian)
        XCTAssertEqual(ledger, expected)
    }

    func testFailedAddDoesNotAdvanceLedgerAndNextEvaluationRetries() async throws {
        let suite = try defaults(), probe = Probe()
        let warning = event()
        let evaluator = MetricWarningBackgroundEvaluator(
            defaults: suite,
            delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
            warningQuery: { _ in [.lowHeartRate: .success(warning)] },
            isForegroundActive: { false }
        )
        await probe.setFailure(true)
        let failure = await evaluator.evaluate()
        XCTAssertEqual(failure, .failure)
        XCTAssertNil(suite.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey))
        await probe.setFailure(false)
        let success = await evaluator.evaluate()
        XCTAssertEqual(success, .success)
        let count = await probe.count
        XCTAssertEqual(count, 2)
    }

    /// The watch skips a kind the phone notified today only once a push
    /// carries the ledger, so a pass that posted hands it over once, after the
    /// add. A failed add, or a kind already notified today, hands nothing over.
    func testAPassThatPostedHandsTheLedgerOverOnce() async throws {
        let suite = try defaults(), probe = Probe()
        let warning = event()
        let evaluator = MetricWarningBackgroundEvaluator(
            defaults: suite,
            delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
            warningQuery: { _ in [.lowHeartRate: .success(warning)] },
            isForegroundActive: { false }
        )
        let afterPosting: @Sendable () async -> Void = { await probe.notify() }

        await probe.setFailure(true)
        let failed = await evaluator.evaluate(afterPosting: afterPosting)
        XCTAssertEqual(failed, .failure)
        var notified = await probe.notified
        XCTAssertEqual(notified, [])

        await probe.setFailure(false)
        let posted = await evaluator.evaluate(afterPosting: afterPosting)
        XCTAssertEqual(posted, .success)
        notified = await probe.notified
        XCTAssertEqual(notified, [2], "Once, after the add that succeeded")
        XCTAssertNotNil(suite.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey))

        let repeated = await evaluator.evaluate(afterPosting: afterPosting)
        XCTAssertEqual(repeated, .success)
        notified = await probe.notified
        XCTAssertEqual(notified, [2], "Already notified today: nothing posted, nothing handed over")
    }

    /// The background task runs the pass under its lease, and the watch
    /// publish after a post needs that lease still valid: the store publishes
    /// nothing under an invalid one. So the fetch ends only a lease it made
    /// itself. Unlike the tests above, this goes through the real
    /// `fetchWarnings`, against a fake store with one low reading.
    func testTheRealFetchLeavesTheTasksLeaseValidForTheWatchPublish() async throws {
        let heartRate = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRate))
        let reading = Date().addingTimeInterval(-60)
        let fake = FakeHealthStore()
        fake.scriptSources(for: heartRate, .sources([]))
        fake.scriptSamples(for: heartRate, .samples([
            HKQuantitySample(
                type: heartRate,
                quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 35),
                start: reading,
                end: reading
            )
        ]))
        let suite = try defaults(), probe = Probe()
        let evaluator = MetricWarningBackgroundEvaluator(
            defaults: suite,
            healthStore: fake,
            delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
            isForegroundActive: { false }
        )
        let lease = BodyBackgroundLease(duration: .seconds(60))

        let outcome = await lease.run {
            await evaluator.evaluate(afterPosting: { await probe.recordLease(BodyBackgroundLease.current?.isValid) })
        }

        XCTAssertEqual(outcome, .success)
        let count = await probe.count
        XCTAssertEqual(count, 1)
        let leaseValidity = await probe.leaseValidity
        XCTAssertEqual(leaseValidity, [true], "The watch publish runs under the task's lease, still valid")
        XCTAssertTrue(lease.isValid, "The task ends its own lease, not the fetch")
    }

    func testHeadlessThresholdRemainsCapturedWhileForegroundThresholdTracksSettings() async {
        let key = BodyAppearancePreference.metricWarningThresholdsKey
        let prior = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(prior, forKey: key) }
        let captured = BodyMetricWarningThresholds(overrides: [.lowBloodOxygen: 90])
        UserDefaults.standard.set(BodyMetricWarningThresholds(overrides: [.lowBloodOxygen: 94]).rawValue, forKey: key)
        let engine = HealthKitFetchEngine(permission: .defaultValue, healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
            healthStore: FakeHealthStore(), capturedWarningThresholds: captured)
        let pinned = await engine.warningThreshold(for: .lowBloodOxygen)
        XCTAssertEqual(pinned, 90)
        let foreground = HealthKitFetchEngine(permission: .defaultValue, healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
            healthStore: FakeHealthStore())
        let live = await foreground.warningThreshold(for: .lowBloodOxygen)
        XCTAssertEqual(live, 94)
    }

    func testMidLoopAdmissionExitPreservesEarlierFailureAndSuccessfulLedger() async throws {
        for posted in [false, true] {
            for failed in [false, true] {
                let suite = try defaults(), probe = Probe()
                suite.set(BodyMetricWarningSelection(enabledKinds: Set(MetricWarningKind.allCases)).rawValue,
                          forKey: BodyAppearancePreference.metricWarningsKey)
                let first = event()
                let last = MetricWarningEvent(kind: .lowBloodOxygen, startDate: first.startDate,
                                              endDate: first.endDate, extremeValue: 85, sampleCount: 1)
                let results: MetricWarningBackgroundEvaluator.WarningResults = [
                    .lowHeartRate: .success(posted ? first : nil),
                    .highHeartRate: failed ? .failure : .success(nil),
                    .lowBloodOxygen: .success(last)
                ]
                let evaluator = MetricWarningBackgroundEvaluator(
                    defaults: suite,
                    delivery: .init(authorization: { .authorized }, add: { _ in try await probe.add() }),
                    warningQuery: { _ in results },
                    // Initial admission, optional first add, then reject the last add.
                    isForegroundActive: { await probe.foregroundOnCheck(posted ? 3 : 2) }
                )
                let outcome = await evaluator.evaluate(afterPosting: { await probe.notify() })
                XCTAssertEqual(outcome, failed ? (posted ? .partialFailure : .failure) : .skipped)
                let count = await probe.count
                XCTAssertEqual(count, posted ? 1 : 0, "The final warning must never be submitted")
                let notified = await probe.notified
                XCTAssertEqual(notified.count, posted ? 1 : 0, "An admission exit after a post still hands the ledger over")
                let ledger = MetricWarningNotificationLedger.storedValue(
                    from: suite.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey) ?? "")
                var expected = MetricWarningNotificationLedger.defaultValue
                if posted { expected.markNotified(kind: .lowHeartRate, on: first.startDate, calendar: .bodyGregorian) }
                XCTAssertEqual(ledger, expected, "Only successful submissions advance the ledger")
            }
        }
    }
}
