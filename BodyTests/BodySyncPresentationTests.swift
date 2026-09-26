import XCTest
@testable import Body

final class BodySyncPresentationTests: XCTestCase {
    func testCapturedFollowupGapDoesNotConfirmOrRestart() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let first = try XCTUnwrap(state.passID)
        state.report(.computing(.stress), owner: first, now: 1)
        state.record(published: true, owner: first)
        let pending = UUID()
        state.enqueue(pending, now: 13.5)
        state.finish(now: 14.067)
        state.advance(now: 14.8) // Original badge would already have confirmed.
        XCTAssertEqual(state.phase, .syncing)
        XCTAssertEqual(state.displayedStage, .syncing)
        let session = state.sessionID
        state.begin(now: 15.101)
        XCTAssertEqual(state.sessionID, session)
        XCTAssertNotEqual(state.displayedStage, .fetching)
        let second = try XCTUnwrap(state.passID)
        state.report(.computing(.trainingLoad), owner: second, now: 15.2)
        state.record(published: true, owner: second)
        state.finish(now: 20.128)
        state.release(pending, now: 20.13)
        state.advance(now: 20.72)
        XCTAssertEqual(state.phase, .syncing)
        XCTAssertNil(state.completedAt)
        let completionDate = Date(timeIntervalSince1970: 1_789_320_000)
        state.advance(now: 20.731, date: completionDate)
        XCTAssertEqual(state.phase, .updated)
        XCTAssertEqual(state.completedAt, completionDate)
        state.advance(now: 21, date: completionDate.addingTimeInterval(60))
        XCTAssertEqual(state.completedAt, completionDate)
        state.advance(now: 22.6)
        XCTAssertEqual(state.phase, .hidden)
        state.begin(now: 23)
        XCTAssertNil(state.completedAt)
    }

    func testThreeFollowupsPreserveSessionAndOldOwnersCannotReport() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let original = try XCTUnwrap(state.passID)
        let session = state.sessionID
        state.record(published: true, owner: original)
        for index in 1...3 {
            let time = Double(index) * 10
            let token = UUID()
            state.enqueue(token, now: time)
            state.finish(now: time)
            state.advance(now: time + 3)
            XCTAssertEqual(state.phase, .syncing)
            state.begin(now: time + 4)
            state.release(token, now: time + 4)
            state.report(.computing(.stress), owner: original, now: time + 5)
            XCTAssertEqual(state.sessionID, session)
            XCTAssertNotEqual(state.displayedStage, .computing(.stress))
        }
        state.finish(now: 40)
        state.advance(now: 41)
        XCTAssertEqual(state.phase, .updated)
    }

    func testNoOpContinuationClearingIsItsOwnSettleEdge() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        state.record(published: true, owner: try XCTUnwrap(state.passID))
        let token = UUID()
        state.enqueue(token, now: 1)
        state.finish(now: 2)
        state.advance(now: 100)
        XCTAssertEqual(state.phase, .syncing)
        XCTAssertNil(state.nextDeadline)
        state.release(token, now: 100)
        XCTAssertEqual(state.nextDeadline, 100.6)
        state.advance(now: 101)
        XCTAssertEqual(state.phase, .updated)
    }

    func testReplacingCancelledDebounceDoesNotClearNewOrAdmittingWork() {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let admitting = UUID(), old = UUID(), replacement = UUID()
        state.enqueue(admitting, now: 1)
        state.enqueue(old, now: 1)
        state.enqueue(replacement, replacing: old, now: 1.2)
        state.release(old, now: 1.3)
        state.finish(now: 2)
        XCTAssertEqual(state.pending, [admitting, replacement])
        state.release(replacement, now: 3)
        state.advance(now: 5)
        XCTAssertEqual(state.phase, .syncing)
        state.release(admitting, now: 6)
        state.advance(now: 7)
        XCTAssertEqual(state.phase, .hidden) // No publication.
    }

    func testRequiredFailureAfterPublicationShowsPartialResult() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        state.record(published: true, owner: try XCTUnwrap(state.passID))
        let token = UUID()
        state.enqueue(token, now: 1)
        state.finish(now: 2)
        state.begin(now: 4)
        state.record(failed: true, owner: try XCTUnwrap(state.passID))
        state.finish(now: 5)
        state.release(token, now: 5)
        state.advance(now: 6)
        XCTAssertEqual(state.phase, .partial)
    }

    func testFailedAndNoQuerySessionsNeverConfirm() throws {
        for failure in [true, false] {
            var state = BodySyncPresentation()
            state.begin(now: 0)
            state.record(failed: failure, owner: try XCTUnwrap(state.passID))
            state.finish(now: 1)
            state.advance(now: 2)
            XCTAssertEqual(state.phase, .hidden)
        }
    }

    func testDwellCoalescesToLatestNamedStageAndIgnoresStaleOwner() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let owner = try XCTUnwrap(state.passID)
        state.report(.computing(.readiness), owner: owner, now: 0.1)
        state.report(.computing(.stress), owner: owner, now: 0.2)
        state.report(.computing(.bodyRadar), owner: owner, now: 0.3)
        XCTAssertEqual(state.displayedStage, .fetching)
        state.advance(now: 0.5)
        XCTAssertEqual(state.displayedStage, .computing(.bodyRadar))
        state.report(.fetching, owner: UUID(), now: 1)
        XCTAssertEqual(state.displayedStage, .computing(.bodyRadar))
    }

    func testQuietSchedulingDoesNotRevealBadge() {
        var state = BodySyncPresentation()
        let token = UUID()
        state.enqueue(token, now: 0)
        state.advance(now: 10)
        XCTAssertEqual(state.phase, .hidden)
        state.release(token, now: 11)
        XCTAssertNil(state.nextDeadline)
    }

    func testInvalidationRejectsProgressAndPendingCleanupFromOldSession() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let oldOwner = try XCTUnwrap(state.passID)
        let oldToken = UUID()
        state.enqueue(oldToken, now: 0)
        state.invalidate()
        state.begin(now: 1)
        let newToken = UUID()
        state.enqueue(newToken, now: 1)
        state.report(.writingEffort, owner: oldOwner, now: 2)
        state.record(published: true, owner: oldOwner)
        state.release(oldToken, now: 2)
        XCTAssertEqual(state.pending, [newToken])
        XCTAssertFalse(state.didPublish)
        XCTAssertEqual(state.displayedStage, .fetching)
    }

    func testLaterRefreshStartsNewSessionAfterSettlementWithoutViewTimer() {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let old = state.sessionID
        state.finish(now: 1)
        state.begin(now: 5)
        XCTAssertNotEqual(state.sessionID, old)
        XCTAssertEqual(state.phase, .syncing)
    }

    func testQuickAutomaticSessionEndsWithoutShowingOrConfirming() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        XCTAssertFalse(state.isRevealed)
        XCTAssertEqual(state.nextDeadline, 0.5)
        state.record(published: true, owner: try XCTUnwrap(state.passID))
        state.finish(now: 0.3)
        // Only settling now, so the reveal deadline no longer applies.
        XCTAssertEqual(try XCTUnwrap(state.nextDeadline), 0.9, accuracy: 0.000_001)
        state.advance(now: 0.5)
        XCTAssertFalse(state.isRevealed)
        state.advance(now: 1)
        XCTAssertEqual(state.phase, .hidden)
        XCTAssertFalse(state.isRevealed)
        XCTAssertNil(state.completedAt)
        XCTAssertNil(state.nextDeadline)
    }

    func testSessionStillRunningAtRevealDelayShowsAndConfirms() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        let owner = try XCTUnwrap(state.passID)
        state.advance(now: 0.49)
        XCTAssertFalse(state.isRevealed)
        state.advance(now: 0.5)
        XCTAssertTrue(state.isRevealed)
        state.record(published: true, owner: owner)
        state.finish(now: 1)
        state.advance(now: 2)
        XCTAssertEqual(state.phase, .updated)
        state.advance(now: 5)
        XCTAssertEqual(state.phase, .hidden)

        // A queued follow-up alone keeps the next session open but never reveals it;
        // the follow-up's own pass does, once it begins after the delay.
        state.begin(now: 10)
        XCTAssertFalse(state.isRevealed)
        let followup = UUID()
        state.enqueue(followup, now: 10.1)
        state.finish(now: 10.2)
        state.advance(now: 10.5)
        XCTAssertFalse(state.isRevealed)
        XCTAssertNil(state.nextDeadline)
        state.advance(now: 11)
        XCTAssertFalse(state.isRevealed)
        XCTAssertEqual(state.phase, .syncing)
        state.begin(now: 11.2)
        XCTAssertTrue(state.isRevealed)
        state.release(followup, now: 11.3)
    }

    func testSessionHeldOpenOnlyByATokenEndsHidden() throws {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        state.record(published: true, owner: try XCTUnwrap(state.passID))
        let token = UUID()
        state.enqueue(token, now: 0.1)
        state.finish(now: 0.2)
        state.advance(now: 5)
        XCTAssertEqual(state.phase, .syncing)
        XCTAssertFalse(state.isRevealed)
        state.release(token, now: 5)
        state.advance(now: 6)
        XCTAssertEqual(state.phase, .hidden)
        XCTAssertFalse(state.isRevealed)
        XCTAssertNil(state.completedAt)
        XCTAssertNil(state.nextDeadline)
    }

    func testFollowupAfterRevealDelayShowsTheJoinedSessionAtOnce() {
        var state = BodySyncPresentation()
        state.begin(now: 0)
        state.finish(now: 0.3)
        state.advance(now: 0.5)
        XCTAssertFalse(state.isRevealed)
        let session = state.sessionID
        state.begin(now: 0.6)
        XCTAssertEqual(state.sessionID, session)
        XCTAssertTrue(state.isRevealed)
    }

    func testRevealShowsAtOnceAndIgnoresHiddenPresentation() throws {
        var state = BodySyncPresentation()
        state.reveal()
        XCTAssertFalse(state.isRevealed)
        state.begin(now: 0)
        state.reveal()
        XCTAssertTrue(state.isRevealed)
        XCTAssertNil(state.nextDeadline)
        state.record(published: true, owner: try XCTUnwrap(state.passID))
        state.finish(now: 0.1)
        state.advance(now: 1)
        XCTAssertEqual(state.phase, .updated)
    }
}
