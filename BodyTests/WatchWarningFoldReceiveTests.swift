//
//  WatchWarningFoldReceiveTests.swift
//  BodyTests
//
//  The iPhone end of the two way warning fold sync: the watch sends each fold
//  as `WatchWarningFoldSync.payload(for:)`, queued with `transferUserInfo` and,
//  while the iPhone is reachable, as a `sendMessage` too. These drive the
//  publisher's delegate methods with that exact payload and check that the
//  records reach `warningFoldHandler` on the main actor, that the queued copy
//  comes without a completion (the handler then takes the debounced republish)
//  while a message's comes with one and its reply waits for it (the direct
//  republish), and that any other message never reaches the fold handler. Calls the delegate methods
//  directly, so no paired watch or activated session is needed.
//

import XCTest
import WatchConnectivity
@testable import Body

@MainActor
final class WatchWarningFoldReceiveTests: XCTestCase {
    private var savedFoldHandler: (@MainActor ([WatchWarningFoldSync.Record], (@MainActor @Sendable () -> Void)?) -> Void)?
    private var savedBaselineHandler: (@MainActor (@escaping @MainActor @Sendable (WatchBaselineSync.Reply) -> Void) -> Void)?

    /// Whole seconds, so the ISO 8601 round trip compares equal.
    private let records = [
        WatchWarningFoldSync.Record(
            key: "highHeartRate@2026-10-04",
            isFolded: true,
            changedAt: Date(timeIntervalSinceReferenceDate: 813_000_000)
        ),
        WatchWarningFoldSync.Record(
            key: "lowHeartRate@2026-10-04",
            isFolded: false,
            changedAt: Date(timeIntervalSinceReferenceDate: 813_000_042)
        )
    ]

    // The publisher is a process wide singleton, so the app's own handlers
    // are put back after each test.
    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(WCSession.isSupported(), "WatchConnectivity is unsupported on this destination")
        savedFoldHandler = WatchConnectivityPublisher.shared.warningFoldHandler
        savedBaselineHandler = WatchConnectivityPublisher.shared.baselineSyncHandler
    }

    override func tearDown() async throws {
        WatchConnectivityPublisher.shared.warningFoldHandler = savedFoldHandler
        WatchConnectivityPublisher.shared.baselineSyncHandler = savedBaselineHandler
        try await super.tearDown()
    }

    private func payload() throws -> [String: Any] {
        try XCTUnwrap(WatchWarningFoldSync.payload(for: records))
    }

    /// The queued copy reaches the handler with the records, on the main
    /// actor, and without a completion: nothing waits on it, so the handler
    /// republishes through the debounced path.
    func testUserInfoReachesTheHandlerOnTheMainActorWithoutACompletion() async throws {
        let handled = expectation(description: "handled")
        let expected = records
        WatchConnectivityPublisher.shared.warningFoldHandler = { received, completion in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(received, expected)
            XCTAssertNil(completion)
            handled.fulfill()
        }

        WatchConnectivityPublisher.shared.session(WCSession.default, didReceiveUserInfo: try payload())

        await fulfillment(of: [handled], timeout: 5)
    }

    /// The message hands the handler a completion, and its empty reply goes
    /// out only once that runs, which is what keeps a background wake up
    /// until the republish lands.
    func testMessageRepliesOnlyAfterTheHandlerCompletes() async throws {
        let handled = expectation(description: "handled")
        var pendingCompletion: (@MainActor @Sendable () -> Void)?
        let expected = records
        WatchConnectivityPublisher.shared.warningFoldHandler = { received, completion in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(received, expected)
            XCTAssertNotNil(completion)
            pendingCompletion = completion
            handled.fulfill()
        }
        let earlyReply = expectation(description: "reply before completion")
        earlyReply.isInverted = true
        let reply = expectation(description: "reply")
        let replyBox = ReplyBox()

        WatchConnectivityPublisher.shared.session(
            WCSession.default,
            didReceiveMessage: try payload(),
            replyHandler: { message in
                replyBox.count += 1
                replyBox.isEmpty = message.isEmpty
                earlyReply.fulfill()
                reply.fulfill()
            }
        )

        await fulfillment(of: [handled], timeout: 5)
        await fulfillment(of: [earlyReply], timeout: 0.5)
        XCTAssertEqual(replyBox.count, 0)

        try XCTUnwrap(pendingCompletion)()

        await fulfillment(of: [reply], timeout: 5)
        XCTAssertEqual(replyBox.count, 1)
        XCTAssertTrue(replyBox.isEmpty)
    }

    /// Without a handler (it is installed at launch, so this is a safety net)
    /// the message still gets its empty reply.
    func testMessageRepliesAtOnceWithoutAHandler() async throws {
        WatchConnectivityPublisher.shared.warningFoldHandler = nil
        let reply = expectation(description: "reply")
        let replyBox = ReplyBox()

        WatchConnectivityPublisher.shared.session(
            WCSession.default,
            didReceiveMessage: try payload(),
            replyHandler: { message in
                replyBox.isEmpty = message.isEmpty
                reply.fulfill()
            }
        )

        await fulfillment(of: [reply], timeout: 5)
        XCTAssertTrue(replyBox.isEmpty)
    }

    /// A message without the fold key (or with one that doesn't decode) never
    /// reaches the fold handler: some other message gets the empty reply, and a
    /// Sync Baseline request still goes to its own handler.
    func testOtherMessagesNeverReachTheFoldHandler() async throws {
        let folded = expectation(description: "fold handler")
        folded.isInverted = true
        WatchConnectivityPublisher.shared.warningFoldHandler = { _, completion in
            completion?()
            folded.fulfill()
        }
        let baseline = expectation(description: "baseline handler")
        WatchConnectivityPublisher.shared.baselineSyncHandler = { reply in
            reply(.unavailable)
            baseline.fulfill()
        }
        let otherReply = expectation(description: "other reply")
        let junkReply = expectation(description: "junk reply")
        let baselineReply = expectation(description: "baseline reply")

        WatchConnectivityPublisher.shared.session(
            WCSession.default,
            didReceiveMessage: ["somethingElse": true],
            replyHandler: { message in
                XCTAssertTrue(message.isEmpty)
                otherReply.fulfill()
            }
        )
        WatchConnectivityPublisher.shared.session(
            WCSession.default,
            didReceiveMessage: [WatchWarningFoldSync.recordsKey: Data("junk".utf8)],
            replyHandler: { message in
                XCTAssertTrue(message.isEmpty)
                junkReply.fulfill()
            }
        )
        WatchConnectivityPublisher.shared.session(
            WCSession.default,
            didReceiveMessage: [WatchBaselineSync.requestKey: true],
            replyHandler: { message in
                XCTAssertEqual(message[WatchBaselineSync.replyKey] as? String, WatchBaselineSync.Reply.unavailable.rawValue)
                baselineReply.fulfill()
            }
        )
        WatchConnectivityPublisher.shared.session(WCSession.default, didReceiveUserInfo: ["somethingElse": true])

        await fulfillment(of: [otherReply, junkReply, baseline, baselineReply], timeout: 5)
        await fulfillment(of: [folded], timeout: 0.5)
    }
}

/// What a reply handler saw. The publisher calls the reply from its main
/// actor task and the test reads the box on the main actor too, so it needs
/// no lock.
private final class ReplyBox: @unchecked Sendable {
    var count = 0
    var isEmpty = false
}
