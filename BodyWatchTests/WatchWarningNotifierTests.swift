//
//  WatchWarningNotifierTests.swift
//  BodyWatchTests
//
//  The watch's own warning notifications (`WatchWarningNotifier`): a check
//  is due when its episode started today, its kind is on in the phone's
//  Warnings at the phone's current limit, it didn't start inside a workout
//  (High Heart Rate), the phone's notifications are on, neither device
//  notified the kind today, and, for High Heart Rate, the episode has been
//  over for 30 minutes. In the foreground a due warning is only marked and
//  reported to the phone; in the background it is posted under the phone's
//  identifier and copy, and marked and reported only once posted. The
//  permission is asked for only while the phone's notifications are on and
//  the watch has never asked. A compute merge hands its snapshot over.
//
//  Every test gets its own UserDefaults suite for the watch's ledger and a
//  fake notification center, so nothing is posted and no real ledger moves.
//  Dates are hours of one fixed day in the test machine's own time zone, and
//  every day key, fold key and identifier is built by `MetricWarningDayKey`.
//

import UserNotifications
import XCTest
@testable import BodyWatch

@MainActor
final class WatchWarningNotifierTests: XCTestCase {
    private final class Center: @unchecked Sendable {
        var status: UNAuthorizationStatus = .authorized
        var addFails = false
        var added: [UNNotificationRequest] = []
        var authorizationRequests = 0
    }

    private final class Outbox {
        var batches: [[WatchWarningNotificationSync.Record]] = []
    }

    private struct AddFailure: Error {}

    private final class NoWorkoutChanges: WatchWorkoutChangeDetecting, @unchecked Sendable {
        func detectChanges(now: Date) async -> Bool { false }
        func commitDetectedChanges() async {}
    }

    private let calendar = Calendar.bodyGregorian
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "WatchWarningNotifierTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// `hour`:`minute`:`second` on the fixed day.
    private func today(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: Date(timeIntervalSinceReferenceDate: 812_800_000))!
    }

    private var now: Date { today(14) }

    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: now)! }

    private func check(
        _ kind: MetricWarningKind,
        start: Date,
        end: Date? = nil,
        extreme: Double? = nil,
        threshold: Double? = nil
    ) -> WatchWarningCheck {
        WatchWarningCheck(
            kind: kind.rawValue,
            checkedAt: now,
            threshold: threshold ?? kind.defaultThreshold,
            episode: WatchWarningCheck.Episode(
                startDate: start,
                endDate: end ?? start.addingTimeInterval(10 * 60),
                extremeValue: extreme ?? (kind.isAbove ? kind.defaultThreshold + 12 : kind.defaultThreshold - 4)
            )
        )
    }

    /// The phone's settings: every watch card kind on at its default limit,
    /// notifications on, nothing notified.
    private func phoneSettings(
        enabled: [MetricWarningKind] = [.lowHeartRate, .highHeartRate, .highWristTemperature],
        thresholds: [MetricWarningKind: Double] = [:],
        notifies: Bool = true,
        notifiedDays: [MetricWarningKind: Date] = [:]
    ) -> WatchWarningSettings {
        let kinds: [MetricWarningKind] = [.lowHeartRate, .highHeartRate, .highWristTemperature]
        return WatchWarningSettings(
            thresholds: Dictionary(uniqueKeysWithValues: kinds.map { ($0.rawValue, thresholds[$0] ?? $0.defaultThreshold) }),
            enabledKinds: enabled.map(\.rawValue),
            notifies: notifies,
            notifiedDays: Dictionary(uniqueKeysWithValues: notifiedDays.map {
                ($0.key.rawValue, MetricWarningDayKey.dayText(for: $0.value, calendar: calendar))
            })
        )
    }

    private func due(
        _ checks: [WatchWarningCheck],
        settings: WatchWarningSettings?,
        spans: [WatchWorkoutSpan]? = nil,
        ledger: MetricWarningNotificationLedger = .defaultValue,
        at now: Date? = nil
    ) -> [MetricWarningEvent] {
        WatchWarningNotifier.due(
            checks: checks,
            settings: settings,
            spans: spans,
            watchLedger: ledger,
            now: now ?? self.now,
            calendar: calendar
        )
    }

    private func snapshot(
        _ checks: [WatchWarningCheck],
        settings: WatchWarningSettings? = nil,
        metrics: [WatchMetric] = []
    ) -> WatchMetricsSnapshot {
        var snapshot = WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: metrics)
        snapshot.warningSettings = settings ?? phoneSettings()
        snapshot.warningChecks = checks
        return snapshot
    }

    private func makeNotifier(center: Center, outbox: Outbox, foreground: Bool = false) -> WatchWarningNotifier {
        WatchWarningNotifier(
            delivery: WatchWarningNotifier.Delivery(
                authorizationStatus: { center.status },
                add: { request in
                    if center.addFails { throw AddFailure() }
                    center.added.append(request)
                },
                requestAuthorization: { center.authorizationRequests += 1 }
            ),
            send: { outbox.batches.append($0) },
            defaults: defaults,
            isForeground: { foreground }
        )
    }

    private var ledger: MetricWarningNotificationLedger {
        MetricWarningNotificationLedger.storedValue(
            from: defaults.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey) ?? ""
        )
    }

    private func dayText(_ date: Date) -> String {
        MetricWarningDayKey.dayText(for: date, calendar: calendar)
    }

    // MARK: - Due

    func testADueWarningCarriesItsEpisodeAndLimit() {
        let events = due([check(.lowHeartRate, start: today(3), end: today(3, 20), extreme: 36, threshold: 42)],
                         settings: phoneSettings(thresholds: [.lowHeartRate: 42]))

        XCTAssertEqual(events, [MetricWarningEvent(
            kind: .lowHeartRate,
            startDate: today(3),
            endDate: today(3, 20),
            extremeValue: 36,
            sampleCount: 1,
            threshold: 42
        )])
    }

    /// A workout still being recorded keeps a High Heart Rate episode open,
    /// so it waits until the episode has been over for the 30 minute grace.
    /// The other kinds don't wait.
    func testHighHeartRateIsDueOnlyOnceItsEpisodeHasSettled() {
        let settled = now.addingTimeInterval(-MetricThresholdWarning.workoutRecoveryGrace)

        XCTAssertEqual(due([check(.highHeartRate, start: today(13), end: settled)], settings: phoneSettings()).map(\.kind), [.highHeartRate])
        XCTAssertTrue(due([check(.highHeartRate, start: today(13), end: settled.addingTimeInterval(1))], settings: phoneSettings()).isEmpty)
        XCTAssertEqual(due([check(.lowHeartRate, start: today(13), end: now.addingTimeInterval(-60))], settings: phoneSettings()).map(\.kind), [.lowHeartRate])
    }

    func testAKindThePhoneNotifiedTodayIsNotDue() {
        let checks = [check(.lowHeartRate, start: today(3))]

        XCTAssertTrue(due(checks, settings: phoneSettings(notifiedDays: [.lowHeartRate: now])).isEmpty)
        XCTAssertEqual(due(checks, settings: phoneSettings(notifiedDays: [.lowHeartRate: yesterday, .highHeartRate: now])).count, 1)
    }

    func testAKindTheWatchNotifiedTodayIsNotDue() {
        let checks = [check(.lowHeartRate, start: today(3))]
        var notifiedToday = MetricWarningNotificationLedger.defaultValue
        notifiedToday.markNotified(kind: .lowHeartRate, on: today(1), calendar: calendar)
        var notifiedYesterday = MetricWarningNotificationLedger.defaultValue
        notifiedYesterday.markNotified(kind: .lowHeartRate, on: yesterday, calendar: calendar)

        XCTAssertTrue(due(checks, settings: phoneSettings(), ledger: notifiedToday).isEmpty)
        XCTAssertEqual(due(checks, settings: phoneSettings(), ledger: notifiedYesterday).count, 1)
    }

    /// The phone's notification switches off, or an older phone that sends no
    /// settings: nothing is due.
    func testNothingIsDueWithoutThePhonesNotifications() {
        let checks = [check(.lowHeartRate, start: today(3))]

        XCTAssertTrue(due(checks, settings: phoneSettings(notifies: false)).isEmpty)
        XCTAssertTrue(due(checks, settings: nil).isEmpty)
    }

    func testAKindTurnedOffInWarningsIsNotDue() {
        XCTAssertTrue(due([check(.lowHeartRate, start: today(3))], settings: phoneSettings(enabled: [.highHeartRate])).isEmpty)
    }

    /// The limit changed on the phone since the check, or the phone hasn't
    /// resolved it yet: the check waits for the next compute.
    func testACheckUnderAnotherLimitIsNotDue() {
        let checks = [check(.lowHeartRate, start: today(3), threshold: 40)]
        var unresolved = phoneSettings()
        unresolved.thresholds[MetricWarningKind.lowHeartRate.rawValue] = nil

        XCTAssertTrue(due(checks, settings: phoneSettings(thresholds: [.lowHeartRate: 45])).isEmpty)
        XCTAssertTrue(due(checks, settings: unresolved).isEmpty)
    }

    /// A High Heart Rate episode that started inside a workout, or within 30
    /// minutes after it, is never due; a Low Heart Rate one still is.
    func testAnEpisodeStartingInsideAWorkoutIsNotDueForHighHeartRate() {
        let spans = [WatchWorkoutSpan(start: today(10), end: today(11))]

        XCTAssertTrue(due([check(.highHeartRate, start: today(11, 30))], settings: phoneSettings(), spans: spans).isEmpty)
        XCTAssertEqual(due([check(.highHeartRate, start: today(11, 30, 1))], settings: phoneSettings(), spans: spans).count, 1)
        XCTAssertEqual(due([check(.lowHeartRate, start: today(10, 30))], settings: phoneSettings(), spans: spans).count, 1)
    }

    func testOnlyAnEpisodeStartingTodayIsDue() {
        XCTAssertTrue(due([check(.lowHeartRate, start: calendar.date(byAdding: .day, value: -1, to: today(23, 50))!)], settings: phoneSettings()).isEmpty)
        var none = check(.lowHeartRate, start: today(3))
        none.episode = nil
        XCTAssertTrue(due([none], settings: phoneSettings()).isEmpty)
    }

    // MARK: - Process

    /// On screen already: marked and reported, never posted, the phone's rule
    /// for what it shows on screen.
    func testInTheForegroundADueWarningIsMarkedAndReportedWithoutPosting() async {
        let center = Center()
        let outbox = Outbox()
        let notifier = makeNotifier(center: center, outbox: outbox, foreground: true)

        await notifier.process(snapshot([check(.lowHeartRate, start: today(3))]), now: now)

        XCTAssertTrue(center.added.isEmpty)
        XCTAssertEqual(ledger.lastNotifiedDayKeys, [.lowHeartRate: dayText(now)])
        XCTAssertEqual(outbox.batches, [[WatchWarningNotificationSync.Record(kind: "lowHeartRate", startDate: today(3))]])
    }

    func testInTheBackgroundADueWarningIsPostedThenMarkedAndReported() async throws {
        let center = Center()
        let outbox = Outbox()
        let notifier = makeNotifier(center: center, outbox: outbox)
        let start = today(9)
        let end = today(9, 40)

        await notifier.process(snapshot([check(.highHeartRate, start: start, end: end, extreme: 132)]), now: now)

        let request = try XCTUnwrap(center.added.first)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(request.identifier, MetricWarningDayKey.notificationIdentifier(kind: .highHeartRate, date: start, calendar: calendar))
        XCTAssertEqual(request.content.title, MetricWarningNotificationContent.title(for: .highHeartRate))
        XCTAssertEqual(request.content.body, "A periodic check found a heart rate of 132 bpm today, above your 120 bpm limit.")
        XCTAssertNotNil(request.content.sound)
        XCTAssertNil(request.trigger)
        XCTAssertEqual(ledger.lastNotifiedDayKeys, [.highHeartRate: dayText(start)])
        XCTAssertEqual(outbox.batches, [[WatchWarningNotificationSync.Record(kind: "highHeartRate", startDate: start)]])

        // Once marked, the next compute doesn't notify the kind again.
        await notifier.process(snapshot([check(.highHeartRate, start: start, end: end, extreme: 132)]), now: now.addingTimeInterval(1_800))
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(outbox.batches.count, 1)
    }

    /// The body reads the reading and the limit in the Skin Temp card's unit;
    /// a card without the flag (an older phone) reads as Celsius.
    func testASkinTemperatureBodyUsesTheSkinTempCardsUnit() async {
        let skinCheck = check(.highWristTemperature, start: today(4), extreme: 38.4)
        let event = MetricWarningEvent(
            kind: .highWristTemperature,
            startDate: today(4),
            endDate: today(4, 10),
            extremeValue: 38.4,
            sampleCount: 1,
            threshold: 38
        )
        var fahrenheitCard = WatchMetric(
            kind: WatchMetricKindKey.wristTemperature,
            title: "Skin Temp",
            displayValue: "97.2",
            unit: "°F",
            score: nil,
            fillFraction: 0.5,
            rawValue: 36.2
        )
        fahrenheitCard.usesFahrenheit = true
        var unflaggedCard = fahrenheitCard
        unflaggedCard.usesFahrenheit = nil

        let fahrenheitCenter = Center()
        await makeNotifier(center: fahrenheitCenter, outbox: Outbox())
            .process(snapshot([skinCheck], metrics: [fahrenheitCard]), now: now)
        XCTAssertEqual(
            fahrenheitCenter.added.map(\.content.body),
            [MetricWarningNotificationContent.body(for: event, temperatureUnitPreference: .fahrenheit)]
        )

        defaults.removeObject(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey)
        let celsiusCenter = Center()
        await makeNotifier(center: celsiusCenter, outbox: Outbox())
            .process(snapshot([skinCheck], metrics: [unflaggedCard]), now: now)
        XCTAssertEqual(
            celsiusCenter.added.map(\.content.body),
            [MetricWarningNotificationContent.body(for: event, temperatureUnitPreference: .celsius)]
        )
        XCTAssertNotEqual(fahrenheitCenter.added.first?.content.body, celsiusCenter.added.first?.content.body)
    }

    /// A refused post leaves the ledger and the phone untouched, so the next
    /// compute tries again.
    func testAFailedPostIsNeitherMarkedNorReported() async {
        let center = Center()
        center.addFails = true
        let outbox = Outbox()
        let notifier = makeNotifier(center: center, outbox: outbox)
        let checks = [check(.lowHeartRate, start: today(3))]

        await notifier.process(snapshot(checks), now: now)

        XCTAssertTrue(center.added.isEmpty)
        XCTAssertTrue(ledger.lastNotifiedDayKeys.isEmpty)
        XCTAssertTrue(outbox.batches.isEmpty)

        center.addFails = false
        await notifier.process(snapshot(checks), now: now)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(outbox.batches.count, 1)
    }

    /// Without permission nothing is posted, and nothing is marked, so the
    /// warning still notifies once the user allows notifications.
    func testWithoutPermissionNothingIsPostedMarkedOrReported() async {
        let checks = [check(.lowHeartRate, start: today(3))]

        for status in [UNAuthorizationStatus.denied, .notDetermined] {
            let center = Center()
            center.status = status
            let outbox = Outbox()

            await makeNotifier(center: center, outbox: outbox).process(snapshot(checks), now: now)

            XCTAssertTrue(center.added.isEmpty, "\(status.rawValue)")
            XCTAssertTrue(ledger.lastNotifiedDayKeys.isEmpty, "\(status.rawValue)")
            XCTAssertTrue(outbox.batches.isEmpty, "\(status.rawValue)")
        }

        let provisional = Center()
        provisional.status = .provisional
        await makeNotifier(center: provisional, outbox: Outbox()).process(snapshot(checks), now: now)
        XCTAssertEqual(provisional.added.count, 1)
    }

    // MARK: - Permission

    func testPermissionIsAskedOnlyWhileNotificationsAreOnAndNeverAsked() async {
        let center = Center()
        let notifier = makeNotifier(center: center, outbox: Outbox())

        center.status = .notDetermined
        await notifier.requestAuthorizationIfNeeded(settings: phoneSettings(notifies: false))
        await notifier.requestAuthorizationIfNeeded(settings: nil)
        XCTAssertEqual(center.authorizationRequests, 0)

        await notifier.requestAuthorizationIfNeeded(settings: phoneSettings())
        XCTAssertEqual(center.authorizationRequests, 1)

        for status in [UNAuthorizationStatus.authorized, .denied, .provisional] {
            center.status = status
            await notifier.requestAuthorizationIfNeeded(settings: phoneSettings())
        }
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    // MARK: - Model

    /// A compute merge hands the merged snapshot, with the checks and
    /// settings it kept, to the notifier at the compute's clock.
    func testAComputeMergeHandsItsSnapshotToTheNotifier() async {
        let center = Center()
        let outbox = Outbox()
        let computedAt = now
        let environment = WatchComputeEnvironment(
            isEligible: { true },
            loadPermission: { .defaultValue },
            isAuthorizationSettled: { _ in true },
            requestAuthorization: { _ in },
            compute: { _, generation, now in
                WatchComputeResult(
                    snapshot: WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: [], source: "watch"),
                    dataAsOf: [:],
                    coverage: now,
                    generation: generation
                )
            },
            changeTracker: NoWorkoutChanges(),
            scheduleBackgroundRefresh: { _ in },
            defaults: defaults,
            now: { computedAt }
        )
        let model = WatchMetricsModel(
            persistSnapshot: { _ in true },
            reloadTimelines: {},
            environment: environment,
            notifier: makeNotifier(center: center, outbox: outbox)
        )
        model.applyForTesting(snapshot([check(.lowHeartRate, start: today(3))]))

        await model.recomputeIfStale(force: true)

        XCTAssertEqual(
            center.added.map(\.identifier),
            [MetricWarningDayKey.notificationIdentifier(kind: .lowHeartRate, date: today(3), calendar: calendar)]
        )
        XCTAssertEqual(outbox.batches, [[WatchWarningNotificationSync.Record(kind: "lowHeartRate", startDate: today(3))]])
    }
}
