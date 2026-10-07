//
//  WatchWarningNotificationReceiveTests.swift
//  BodyTests
//
//  The iPhone end of the watch's own warning notifications: the watch sends
//  each warning it notified as `WatchWarningNotificationSync.payload(for:)`,
//  queued with `transferUserInfo` and, while the iPhone is reachable, as a
//  `sendMessage` too, and the iPhone marks those kinds in its notification
//  ledger (`MetricWarningBackgroundEvaluator.seed`) so it doesn't notify them
//  again that day. These pin the filter in front of the seed (today's records
//  of known kinds only), the payload parse, and the delegate methods: a
//  message gets its empty reply at once, and neither copy reaches the fold
//  handler. The delegate tests send only records the filter drops, so they
//  never write the app's real ledger. Calls the delegate methods directly, so
//  no paired watch or activated session is needed.
//

import XCTest
import WatchConnectivity
@testable import Body

@MainActor
final class WatchWarningNotificationReceiveTests: XCTestCase {
    private var savedFoldHandler: (@MainActor ([WatchWarningFoldSync.Record], (@MainActor @Sendable () -> Void)?) -> Void)?

    private let calendar = Calendar.bodyGregorian

    // The publisher is a process wide singleton, so the app's own handler is
    // put back after each test.
    override func setUp() async throws {
        try await super.setUp()
        savedFoldHandler = WatchConnectivityPublisher.shared.warningFoldHandler
    }

    override func tearDown() async throws {
        WatchConnectivityPublisher.shared.warningFoldHandler = savedFoldHandler
        try await super.tearDown()
    }

    /// `hour`:`minute` on 2026-06-20, the day every filter test runs on.
    private func date(hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: hour, minute: minute)))
    }

    private func seed(_ records: [WatchWarningNotificationSync.Record]) throws -> [MetricWarningKind: Date] {
        WatchConnectivityPublisher.notifiedWarningSeed(from: records, now: try date(hour: 10), calendar: calendar)
    }

    // MARK: - Filter

    /// Today's records seed their kinds at their start. A kind sent twice
    /// keeps its first record; the ledger marks the same day either way.
    func testTodaysRecordsSeedTheirKinds() throws {
        let lowStart = try date(hour: 3, minute: 10)
        let skinStart = try date(hour: 6)

        let seeded = try seed([
            .init(kind: "lowHeartRate", startDate: lowStart),
            .init(kind: "highWristTemperature", startDate: skinStart),
            .init(kind: "lowHeartRate", startDate: try date(hour: 9))
        ])

        XCTAssertEqual(seeded, [.lowHeartRate: lowStart, .highWristTemperature: skinStart])
    }

    /// `seed` overwrites a kind's day, so a late queued copy from yesterday is
    /// dropped rather than un-marking today, even beside today's record of
    /// the same kind. A record dated tomorrow (a skewed clock) isn't today
    /// either.
    func testRecordsFromAnotherDayAreDropped() throws {
        let todayStart = try date(hour: 8, minute: 5)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: try date(hour: 23, minute: 30)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: try date(hour: 0, minute: 30)))

        XCTAssertEqual(try seed([.init(kind: "highHeartRate", startDate: yesterday)]), [:])
        XCTAssertEqual(try seed([.init(kind: "highHeartRate", startDate: tomorrow)]), [:])
        XCTAssertEqual(
            try seed([
                .init(kind: "highHeartRate", startDate: yesterday),
                .init(kind: "highHeartRate", startDate: todayStart)
            ]),
            [.highHeartRate: todayStart]
        )
    }

    /// A kind this build doesn't know (from a newer watch) is ignored, and the
    /// rest of the batch still seeds.
    func testAnUnknownKindIsIgnored() throws {
        let start = try date(hour: 7)

        let seeded = try seed([
            .init(kind: "highBloodPressure", startDate: start),
            .init(kind: "highWristTemperature", startDate: start)
        ])

        XCTAssertEqual(seeded, [.highWristTemperature: start])
    }

    // MARK: - Payload

    /// A payload without the key, with data under it that doesn't decode, or
    /// carrying fold records yields nil, while a real one round trips.
    func testAMalformedPayloadYieldsNil() throws {
        XCTAssertNil(WatchWarningNotificationSync.records(from: ["somethingElse": true]))
        XCTAssertNil(WatchWarningNotificationSync.records(from: [WatchWarningNotificationSync.recordsKey: Data("junk".utf8)]))
        XCTAssertNil(WatchWarningNotificationSync.records(from: [WatchWarningNotificationSync.recordsKey: "junk"]))
        let fold = try XCTUnwrap(WatchWarningFoldSync.payload(for: [
            WatchWarningFoldSync.Record(key: "highHeartRate@2026-06-20", isFolded: true, changedAt: try date(hour: 9))
        ]))
        XCTAssertNil(WatchWarningNotificationSync.records(from: fold))

        // Whole seconds, so the ISO 8601 round trip compares equal.
        let records = [WatchWarningNotificationSync.Record(kind: "highHeartRate", startDate: try date(hour: 8, minute: 5))]
        let payload = try XCTUnwrap(WatchWarningNotificationSync.payload(for: records))
        XCTAssertEqual(WatchWarningNotificationSync.records(from: payload), records)
    }

    // MARK: - Delegate

    /// A late copy: yesterday's High Heart Rate and a kind this build doesn't
    /// know, both of which the filter drops.
    private func lateCopyPayload() throws -> [String: Any] {
        let now = Date()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        return try XCTUnwrap(WatchWarningNotificationSync.payload(for: [
            .init(kind: "highHeartRate", startDate: yesterday),
            .init(kind: "highBloodPressure", startDate: now)
        ]))
    }

    /// A message gets its empty reply before the delegate returns, since
    /// nothing waits on the seed, and never reaches the fold handler. One
    /// whose data doesn't decode is some other message and gets the empty
    /// reply too.
    func testMessageRepliesAtOnceAndNeverReachesTheFoldHandler() async throws {
        try XCTSkipUnless(WCSession.isSupported(), "WatchConnectivity is unsupported on this destination")
        let folded = expectation(description: "fold handler")
        folded.isInverted = true
        WatchConnectivityPublisher.shared.warningFoldHandler = { _, completion in
            completion?()
            folded.fulfill()
        }
        let replies = ReplyBox()
        let messages: [[String: Any]] = [try lateCopyPayload(), [WatchWarningNotificationSync.recordsKey: Data("junk".utf8)]]

        for message in messages {
            WatchConnectivityPublisher.shared.session(
                WCSession.default,
                didReceiveMessage: message,
                replyHandler: { reply in
                    replies.count += 1
                    replies.allEmpty = replies.allEmpty && reply.isEmpty
                }
            )
        }

        XCTAssertEqual(replies.count, 2)
        XCTAssertTrue(replies.allEmpty)
        await fulfillment(of: [folded], timeout: 0.5)
    }

    /// The queued copy goes to the seed as well, never to the fold handler.
    func testQueuedCopyNeverReachesTheFoldHandler() async throws {
        try XCTSkipUnless(WCSession.isSupported(), "WatchConnectivity is unsupported on this destination")
        let folded = expectation(description: "fold handler")
        folded.isInverted = true
        WatchConnectivityPublisher.shared.warningFoldHandler = { _, completion in
            completion?()
            folded.fulfill()
        }

        WatchConnectivityPublisher.shared.session(WCSession.default, didReceiveUserInfo: try lateCopyPayload())

        await fulfillment(of: [folded], timeout: 0.5)
    }
}

/// What the reply handlers saw. The publisher replies synchronously from the
/// delegate call, which the test makes on the main actor, so it needs no lock.
private final class ReplyBox: @unchecked Sendable {
    var count = 0
    var allEmpty = true
}
