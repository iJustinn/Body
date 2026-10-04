//
//  WatchWarningFoldStoreTests.swift
//  BodyWatchTests
//
//  The watch's end of the two way warning fold sync (`WatchWarningFoldStore`):
//  with no tap of its own the watch shows the phone's state; a tap records a
//  change stamped strictly after the state it replaces and sends exactly that
//  record; the record shows only while it beats the phone's published stamp,
//  so a newer phone change wins and a tie (the phone echoing the watch's own
//  record back) goes to the phone; records survive a relaunch and age out;
//  and on a phone push the records it doesn't reflect yet are sent again.
//

import XCTest
@testable import BodyWatch

@MainActor
final class WatchWarningFoldStoreTests: XCTestCase {
    private final class Clock {
        var now = Date(timeIntervalSinceReferenceDate: 812_800_000.6)
    }

    private final class Outbox {
        var batches: [[WatchWarningFoldSync.Record]] = []
    }

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "WatchWarningFoldStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeStore(clock: Clock, outbox: Outbox = Outbox()) -> WatchWarningFoldStore {
        WatchWarningFoldStore(defaults: defaults, now: { clock.now }, send: { outbox.batches.append($0) })
    }

    private func warning(
        _ foldKey: String = "highHeartRate@2026-10-04",
        isFolded: Bool = false,
        foldChangedAt: Date? = nil
    ) -> WatchMetricWarning {
        WatchMetricWarning(
            kind: String(foldKey.prefix { $0 != "@" }),
            startDate: Date(timeIntervalSinceReferenceDate: 812_780_000),
            threshold: 120,
            foldKey: foldKey,
            isFolded: isFolded,
            foldChangedAt: foldChangedAt
        )
    }

    private func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
    }

    func testThePushedStateShowsWithoutALocalRecord() {
        let store = makeStore(clock: Clock())

        XCTAssertTrue(store.isFolded(warning(isFolded: true, foldChangedAt: Date(timeIntervalSinceReferenceDate: 812_700_000))))
        XCTAssertFalse(store.isFolded(warning(isFolded: false)))
        XCTAssertTrue(store.records.isEmpty)
    }

    /// The phone's clock runs ahead of the watch's: the tap still lands after
    /// the phone's stamp, so the phone accepts it.
    func testToggleRecordsAfterThePushedStampAndSendsExactlyOneRecord() throws {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)
        let phoneStamp = wholeSeconds(clock.now).addingTimeInterval(30)
        let pushed = warning(isFolded: false, foldChangedAt: phoneStamp)

        store.toggle(pushed)

        let expected = WatchWarningFoldSync.Record(key: pushed.foldKey, isFolded: true, changedAt: phoneStamp.addingTimeInterval(1))
        XCTAssertEqual(store.records, [pushed.foldKey: expected])
        XCTAssertEqual(outbox.batches, [[expected]])
        XCTAssertTrue(store.isFolded(pushed))
    }

    func testToggleStampsNowWhenThePushedStampIsOlder() {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)

        store.toggle(warning(isFolded: true, foldChangedAt: wholeSeconds(clock.now).addingTimeInterval(-3_600)))

        XCTAssertEqual(outbox.batches.count, 1)
        XCTAssertEqual(outbox.batches.first?.first?.changedAt, wholeSeconds(clock.now))
        XCTAssertEqual(outbox.batches.first?.first?.isFolded, false)
    }

    /// The phone changed the warning after the watch's tap: its newer stamp
    /// wins over the local record.
    func testANewerPushedStampBeatsTheLocalRecord() throws {
        let clock = Clock()
        let store = makeStore(clock: clock)
        store.toggle(warning(isFolded: false))
        let local = try XCTUnwrap(store.records["highHeartRate@2026-10-04"])
        XCTAssertTrue(local.isFolded)

        let newerPush = warning(isFolded: false, foldChangedAt: local.changedAt.addingTimeInterval(10))

        XCTAssertFalse(store.isFolded(newerPush))
    }

    /// The phone accepted the watch's record and pushed it back with the same
    /// stamp: a tie, which goes to the phone. Here the two agree; a tie with a
    /// different state shows the phone's.
    func testATieGoesToThePhone() throws {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)
        store.toggle(warning(isFolded: false))
        let local = try XCTUnwrap(store.records["highHeartRate@2026-10-04"])

        XCTAssertTrue(store.isFolded(warning(isFolded: true, foldChangedAt: local.changedAt)))
        XCTAssertFalse(store.isFolded(warning(isFolded: false, foldChangedAt: local.changedAt)))

        // A tap on the tied state flips the phone's state, stamped after it.
        store.toggle(warning(isFolded: false, foldChangedAt: local.changedAt))
        XCTAssertEqual(outbox.batches.last, [WatchWarningFoldSync.Record(key: local.key, isFolded: true, changedAt: local.changedAt.addingTimeInterval(1))])
    }

    func testRecordsPersistAcrossInstancesSharingDefaults() {
        let clock = Clock()
        let first = makeStore(clock: clock)
        first.toggle(warning(isFolded: false))
        first.toggle(warning("highWristTemperature@2026-10-04", isFolded: true))

        let second = makeStore(clock: clock)

        XCTAssertEqual(second.records, first.records)
        XCTAssertEqual(second.records.count, 2)
        XCTAssertTrue(second.isFolded(warning(isFolded: false)))
        XCTAssertFalse(second.isFolded(warning("highWristTemperature@2026-10-04", isFolded: true)))
    }

    func testRecordsOlderThanTheRetentionWindowArePrunedOnWrite() {
        let clock = Clock()
        let store = makeStore(clock: clock)
        store.toggle(warning("lowHeartRate@2026-08-01"))
        clock.now = clock.now.addingTimeInterval(30 * 86_400)
        store.toggle(warning("lowHeartRate@2026-08-31"))

        clock.now = clock.now.addingTimeInterval(31 * 86_400)
        store.toggle(warning("lowHeartRate@2026-10-01"))

        XCTAssertEqual(Set(store.records.keys), ["lowHeartRate@2026-08-31", "lowHeartRate@2026-10-01"])
        XCTAssertEqual(Set(makeStore(clock: clock).records.keys), ["lowHeartRate@2026-08-31", "lowHeartRate@2026-10-01"])
    }

    /// Two taps inside one second still order: each stamp is strictly after
    /// the one it replaces, so the phone applies the unfold after the fold.
    func testFoldThenUnfoldGivesStrictlyIncreasingStamps() throws {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)
        let pushed = warning(isFolded: false)

        store.toggle(pushed)
        store.toggle(pushed)

        XCTAssertEqual(outbox.batches.map(\.count), [1, 1])
        let fold = try XCTUnwrap(outbox.batches.first?.first)
        let unfold = try XCTUnwrap(outbox.batches.last?.first)
        XCTAssertTrue(fold.isFolded)
        XCTAssertFalse(unfold.isFolded)
        XCTAssertEqual(fold.changedAt, wholeSeconds(clock.now))
        XCTAssertEqual(unfold.changedAt, fold.changedAt.addingTimeInterval(1))
        XCTAssertFalse(store.isFolded(pushed))
    }

    // MARK: - Resending what the phone hasn't applied

    /// Two taps the phone never saw (sent before the session activated, say):
    /// the phone's push still carries its older stamps, so both go again, in
    /// one send.
    func testResendSendsOnlyRecordsThatStillBeatThePushedStamp() throws {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)
        store.toggle(warning("highHeartRate@2026-10-04"))
        store.toggle(warning("lowHeartRate@2026-10-04"))
        store.toggle(warning("highWristTemperature@2026-10-04"))
        let high = try XCTUnwrap(store.records["highHeartRate@2026-10-04"])
        let low = try XCTUnwrap(store.records["lowHeartRate@2026-10-04"])
        let skin = try XCTUnwrap(store.records["highWristTemperature@2026-10-04"])
        outbox.batches.removeAll()

        store.resendUnacknowledged(in: [
            warning("highHeartRate@2026-10-04", foldChangedAt: high.changedAt.addingTimeInterval(-60)),
            warning("lowHeartRate@2026-10-04"),
            // The phone applied this one and pushed its stamp back.
            warning("highWristTemperature@2026-10-04", isFolded: true, foldChangedAt: skin.changedAt)
        ])

        XCTAssertEqual(outbox.batches, [[high, low]])
    }

    /// The phone's push reflects the tap (a tie) or a later phone change (a
    /// newer stamp): nothing to resend.
    func testResendSendsNothingWhenThePushedStampIsEqualOrNewer() throws {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)
        store.toggle(warning("highHeartRate@2026-10-04"))
        store.toggle(warning("lowHeartRate@2026-10-04"))
        let high = try XCTUnwrap(store.records["highHeartRate@2026-10-04"])
        let low = try XCTUnwrap(store.records["lowHeartRate@2026-10-04"])
        outbox.batches.removeAll()

        store.resendUnacknowledged(in: [
            warning("highHeartRate@2026-10-04", isFolded: true, foldChangedAt: high.changedAt),
            warning("lowHeartRate@2026-10-04", isFolded: false, foldChangedAt: low.changedAt.addingTimeInterval(5))
        ])

        XCTAssertTrue(outbox.batches.isEmpty)
    }

    /// A record for a warning the phone no longer publishes (yesterday's, say)
    /// is never sent, even though nothing ever acknowledged it.
    func testResendIgnoresRecordsForKeysNotInThePush() {
        let clock = Clock()
        let outbox = Outbox()
        let store = makeStore(clock: clock, outbox: outbox)
        store.toggle(warning("highHeartRate@2026-10-03"))
        outbox.batches.removeAll()

        store.resendUnacknowledged(in: [warning("highHeartRate@2026-10-04")])

        XCTAssertTrue(outbox.batches.isEmpty)
        XCTAssertEqual(Set(store.records.keys), ["highHeartRate@2026-10-03"])
    }

    func testResendSendsNothingWithoutLocalRecords() {
        let outbox = Outbox()
        let store = makeStore(clock: Clock(), outbox: outbox)

        store.resendUnacknowledged(in: [warning("highHeartRate@2026-10-04"), warning("lowHeartRate@2026-10-04")])

        XCTAssertTrue(outbox.batches.isEmpty)
    }
}
