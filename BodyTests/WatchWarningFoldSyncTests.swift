//
//  WatchWarningFoldSyncTests.swift
//  BodyTests
//
//  The two way warning fold sync's shared rules (`WatchWarningFoldSync`) and
//  the iPhone's end of it (`BodyMetricWarningFoldDates`): stamps are whole
//  seconds and always strictly after the last stamp the device knows, even one
//  set by a device whose clock runs ahead; a record wins only when strictly
//  newer, so a tie and a duplicate delivery change nothing; the payload codec;
//  and the iPhone applying watch records to its dismissed set, storing the
//  watch's own stamp rather than its "now", so both devices settle on the
//  same record.
//

import XCTest
@testable import Body

final class WatchWarningFoldSyncTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "WatchWarningFoldSyncTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Midday on 2026-10-04 in the test's time zone, plus a fraction of a
    /// second so the flooring is visible.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!.addingTimeInterval(0.75)
    }

    private var flooredNow: Date {
        Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down))
    }

    private func event(_ kind: MetricWarningKind, daysAgo: Int = 0) -> MetricWarningEvent {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: now)!.addingTimeInterval(-3 * 3_600)
        return MetricWarningEvent(kind: kind, startDate: start, endDate: start, extremeValue: 130, sampleCount: 1)
    }

    private func key(_ kind: MetricWarningKind, daysAgo: Int = 0) -> String {
        BodyDismissedMetricWarnings.entryKey(for: event(kind, daysAgo: daysAgo), calendar: calendar)
    }

    private var storedDismissed: Set<String> {
        BodyDismissedMetricWarnings.storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.dismissedMetricWarningsKey) ?? ""
        ).entries
    }

    private func storeDismissed(_ entries: Set<String>) {
        defaults.set(BodyDismissedMetricWarnings(entries: entries).rawValue, forKey: BodyAppearancePreference.dismissedMetricWarningsKey)
    }

    private func storeDates(_ dates: [String: Date]) {
        defaults.set(dates.mapValues(\.timeIntervalSinceReferenceDate), forKey: BodyAppearancePreference.metricWarningFoldDatesKey)
    }

    private func apply(_ records: [WatchWarningFoldSync.Record]) -> Bool {
        BodyMetricWarningFoldDates.applying(records, now: now, defaults: defaults, calendar: calendar)
    }

    // MARK: - Stamps

    func testStampFloorsToWholeSecondsWithoutACurrentStamp() {
        let stamp = WatchWarningFoldSync.stamp(now: now, after: nil)

        XCTAssertEqual(stamp, flooredNow)
        XCTAssertEqual(stamp.timeIntervalSinceReferenceDate.rounded(.down), stamp.timeIntervalSinceReferenceDate)
    }

    func testStampIsStrictlyAfterTheCurrentStamp() {
        // An older stamp: now wins.
        XCTAssertEqual(WatchWarningFoldSync.stamp(now: now, after: flooredNow.addingTimeInterval(-90)), flooredNow)
        // The same second: one second past it.
        XCTAssertEqual(WatchWarningFoldSync.stamp(now: now, after: flooredNow), flooredNow.addingTimeInterval(1))
        // A fractional stamp in the same second floors before the step.
        XCTAssertEqual(WatchWarningFoldSync.stamp(now: now, after: now), flooredNow.addingTimeInterval(1))
    }

    /// The other device's clock runs ahead: the change made here must still
    /// beat the stamp it replaces, or a later unfold would lose to an earlier
    /// fold.
    func testStampStaysAfterACurrentStampAheadOfNow() {
        let ahead = now.addingTimeInterval(300.4)

        let stamp = WatchWarningFoldSync.stamp(now: now, after: ahead)

        XCTAssertEqual(stamp, Date(timeIntervalSinceReferenceDate: ahead.timeIntervalSinceReferenceDate.rounded(.down) + 1))
        XCTAssertTrue(WatchWarningFoldSync.supersedes(stamp, current: ahead))
    }

    func testSupersedesIsStrictAndANilStampIsTheDistantPast() {
        XCTAssertTrue(WatchWarningFoldSync.supersedes(flooredNow.addingTimeInterval(1), current: flooredNow))
        XCTAssertFalse(WatchWarningFoldSync.supersedes(flooredNow, current: flooredNow), "a tie keeps what is there")
        XCTAssertFalse(WatchWarningFoldSync.supersedes(flooredNow.addingTimeInterval(-1), current: flooredNow))
        XCTAssertTrue(WatchWarningFoldSync.supersedes(Date(timeIntervalSinceReferenceDate: 0), current: nil))
        XCTAssertFalse(WatchWarningFoldSync.supersedes(.distantPast, current: nil))
    }

    // MARK: - Payload

    func testPayloadRoundTripsTheRecords() throws {
        let records = [
            WatchWarningFoldSync.Record(key: key(.highHeartRate), isFolded: true, changedAt: flooredNow),
            WatchWarningFoldSync.Record(key: key(.lowHeartRate), isFolded: false, changedAt: flooredNow.addingTimeInterval(-60))
        ]

        let payload = try XCTUnwrap(WatchWarningFoldSync.payload(for: records))

        XCTAssertNotNil(payload[WatchWarningFoldSync.recordsKey] as? Data)
        XCTAssertEqual(WatchWarningFoldSync.records(from: payload), records)
    }

    func testJunkOrAMissingKeyDecodesToNil() {
        XCTAssertNil(WatchWarningFoldSync.records(from: [:]))
        XCTAssertNil(WatchWarningFoldSync.records(from: [WatchBaselineSync.requestKey: true]))
        XCTAssertNil(WatchWarningFoldSync.records(from: [WatchWarningFoldSync.recordsKey: Data("junk".utf8)]))
        XCTAssertNil(WatchWarningFoldSync.records(from: [WatchWarningFoldSync.recordsKey: "not data"]))
    }

    /// The phone's stamp reaches the watch inside the snapshot, whose dates
    /// are ISO 8601 without fractions: a whole second stamp comes back equal,
    /// so the two devices' records compare as a tie rather than flipping.
    func testAStampSurvivesTheSnapshotEncodingUnchanged() throws {
        let stamp = WatchWarningFoldSync.stamp(now: now, after: nil)
        var snapshot = WatchMetricsSnapshot(generatedAt: flooredNow, lastRefreshDate: flooredNow, metrics: [])
        snapshot.metricWarnings = [
            WatchMetricWarning(
                kind: MetricWarningKind.highHeartRate.rawValue,
                startDate: flooredNow,
                threshold: 120,
                foldKey: key(.highHeartRate),
                isFolded: true,
                foldChangedAt: stamp
            )
        ]

        let data = try XCTUnwrap(snapshot.encoded())
        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data)?.metricWarnings?.first?.foldChangedAt)

        XCTAssertEqual(decoded, stamp)
        XCTAssertFalse(WatchWarningFoldSync.supersedes(stamp, current: decoded))
        XCTAssertFalse(WatchWarningFoldSync.supersedes(decoded, current: stamp))
    }

    // MARK: - Fold keys

    func testEntryKeyIsTheEntryDismissingStores() {
        let warning = event(.highHeartRate)

        let dismissed = BodyDismissedMetricWarnings.storedValue(from: "").dismissing(warning, now: now, calendar: calendar)

        XCTAssertEqual(dismissed.entries, [BodyDismissedMetricWarnings.entryKey(for: warning, calendar: calendar)])
        XCTAssertEqual(BodyDismissedMetricWarnings.entryKey(for: warning, calendar: calendar), "highHeartRate@2026-10-04")
    }

    func testThresholdWarningEntriesAcceptEveryKindAndRejectTheRest() {
        for kind in MetricWarningKind.allCases {
            XCTAssertTrue(BodyDismissedMetricWarnings.isThresholdWarningEntry("\(kind.rawValue)@2026-10-04"), kind.rawValue)
        }

        for entry in [
            "bodyRadar@2026-10-04",
            "",
            "highHeartRate",
            "highHeartRate@",
            "@2026-10-04",
            "lowBloodPressure@2026-10-04",
            "highHeartRate@2026-10-04@2026-10-05",
            "highHeartRate@2026-1-04",
            "highHeartRate@26-10-04",
            "highHeartRate@2026-02-31",
            "highHeartRate@2026-13-01",
            "highHeartRate@2026/10/04",
            "highHeartRate@abcd-ef-gh",
            "HighHeartRate@2026-10-04"
        ] {
            XCTAssertFalse(BodyDismissedMetricWarnings.isThresholdWarningEntry(entry), entry)
        }
    }

    // MARK: - Applying watch records

    func testANewerFoldRecordFoldsTheWarning() {
        let record = WatchWarningFoldSync.Record(key: key(.highHeartRate), isFolded: true, changedAt: flooredNow)

        XCTAssertTrue(apply([record]))

        XCTAssertEqual(storedDismissed, [key(.highHeartRate)])
        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults), [key(.highHeartRate): flooredNow])
    }

    func testANewerUnfoldRecordUnfoldsTheWarning() {
        let folded = flooredNow.addingTimeInterval(-600)
        storeDismissed([key(.highHeartRate), key(.lowHeartRate)])
        storeDates([key(.highHeartRate): folded])

        XCTAssertTrue(apply([WatchWarningFoldSync.Record(key: key(.highHeartRate), isFolded: false, changedAt: folded.addingTimeInterval(5))]))

        XCTAssertEqual(storedDismissed, [key(.lowHeartRate)])
        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults)[key(.highHeartRate)], folded.addingTimeInterval(5))
    }

    /// A tie is the phone's own state coming back (or a duplicate delivery),
    /// and an older record lost the race: neither changes anything or writes.
    func testOlderAndTiedRecordsAreRejected() {
        let stamp = flooredNow.addingTimeInterval(-600)
        storeDismissed([key(.highHeartRate)])
        storeDates([key(.highHeartRate): stamp])

        XCTAssertFalse(apply([WatchWarningFoldSync.Record(key: key(.highHeartRate), isFolded: false, changedAt: stamp)]))
        XCTAssertFalse(apply([WatchWarningFoldSync.Record(key: key(.highHeartRate), isFolded: false, changedAt: stamp.addingTimeInterval(-1))]))

        XCTAssertEqual(storedDismissed, [key(.highHeartRate)])
        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults), [key(.highHeartRate): stamp])
    }

    /// Storing the watch's stamp, not the phone's "now", is what makes the
    /// phone's next push carry the very record the watch holds (a tie there).
    func testTheRecordsOwnStampIsStoredRatherThanNow() {
        let watchStamp = flooredNow.addingTimeInterval(3_600)

        XCTAssertTrue(apply([WatchWarningFoldSync.Record(key: key(.lowHeartRate), isFolded: true, changedAt: watchStamp)]))

        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults)[key(.lowHeartRate)], watchStamp)
    }

    /// A fold made before two way sync has no stamp, so any record beats it.
    func testALegacyUnstampedEntryLosesToAnyRecord() {
        storeDismissed([key(.highWristTemperature)])

        let record = WatchWarningFoldSync.Record(
            key: key(.highWristTemperature),
            isFolded: false,
            changedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        XCTAssertTrue(apply([record]))

        XCTAssertTrue(storedDismissed.isEmpty)
        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults)[key(.highWristTemperature)], record.changedAt)
    }

    func testInvalidKeysAreSkippedAndNothingIsWritten() {
        let records = [
            WatchWarningFoldSync.Record(key: "bodyRadar@2026-10-04", isFolded: true, changedAt: flooredNow),
            WatchWarningFoldSync.Record(key: "junk", isFolded: true, changedAt: flooredNow),
            // Past the retention window.
            WatchWarningFoldSync.Record(key: key(.highHeartRate, daysAgo: 70), isFolded: true, changedAt: flooredNow)
        ]

        XCTAssertFalse(apply(records))

        XCTAssertNil(defaults.object(forKey: BodyAppearancePreference.dismissedMetricWarningsKey))
        XCTAssertNil(defaults.object(forKey: BodyAppearancePreference.metricWarningFoldDatesKey))
    }

    func testAMixedBatchAppliesItsValidRecordsAndWritesBothKeys() {
        let records = [
            WatchWarningFoldSync.Record(key: "bodyRadar@2026-10-04", isFolded: true, changedAt: flooredNow),
            WatchWarningFoldSync.Record(key: key(.highHeartRate), isFolded: true, changedAt: flooredNow)
        ]

        XCTAssertTrue(apply(records))

        XCTAssertEqual(defaults.string(forKey: BodyAppearancePreference.dismissedMetricWarningsKey), key(.highHeartRate))
        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults), [key(.highHeartRate): flooredNow])
    }

    // MARK: - Stamping the phone's own changes

    func testRecordChangeStampsNowInWholeSeconds() {
        BodyMetricWarningFoldDates.recordChange(of: event(.highHeartRate), now: now, defaults: defaults, calendar: calendar)

        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults), [key(.highHeartRate): flooredNow])
    }

    /// The watch's clock ran ahead when it stamped the fold the phone
    /// accepted: the phone's unfold must still land after it.
    func testRecordChangeStampsAfterARemoteStampAheadOfNow() {
        let remote = flooredNow.addingTimeInterval(120)
        storeDates([key(.highHeartRate): remote])

        BodyMetricWarningFoldDates.recordChange(of: event(.highHeartRate), now: now, defaults: defaults, calendar: calendar)

        XCTAssertEqual(BodyMetricWarningFoldDates.load(defaults: defaults)[key(.highHeartRate)], remote.addingTimeInterval(1))
    }

    func testStampsPastTheRetentionWindowArePruned() {
        let old = key(.lowHeartRate, daysAgo: 61)
        let recent = key(.lowHeartRate, daysAgo: 59)
        storeDates([old: flooredNow.addingTimeInterval(-61 * 86_400), recent: flooredNow.addingTimeInterval(-59 * 86_400)])

        BodyMetricWarningFoldDates.recordChange(of: event(.highHeartRate), now: now, defaults: defaults, calendar: calendar)

        let dates = BodyMetricWarningFoldDates.load(defaults: defaults)
        XCTAssertNil(dates[old])
        XCTAssertNotNil(dates[recent])
        XCTAssertNotNil(dates[key(.highHeartRate)])
    }
}
