//
//  WatchConnectivityPublisherGateTests.swift
//  BodyTests
//
//  M5: the watch-publish send gate orders snapshots by the publisher-owned
//  monotonic capture sequence instead of the wall-clock `generatedAt`, so a
//  device-clock rollback can't suppress every later publish. These exercise the
//  pure gate decision (`shouldQueue`) — the full `send` path needs a live
//  `WCSession`, but the ordering rule that matters is clock-immune and pure.
//  This lives in BodyTests (not BodyWatchTests) because the publisher is an
//  iOS-target type the watch tests can't see.
//

import XCTest
@testable import Body

final class WatchConnectivityPublisherGateTests: XCTestCase {

    // A lower capture sequence arriving after a higher one is dropped. Because
    // the gate never consults `generatedAt`, a NEWER wall-clock stamp on the
    // lower-sequence snapshot can't rescue it — ordering is capture-order, not
    // clock-order.
    func testLowerSequenceAfterHigherIsDroppedEvenWithNewerClock() {
        XCTAssertFalse(WatchConnectivityPublisher.shouldQueue(captureSequence: 2, afterLastQueued: 5))
    }

    // An advancing sequence is accepted even when the device clock ran backward:
    // the gate ignores `generatedAt`, so a backward-`generatedAt` snapshot with a
    // higher capture sequence is NOT dropped (the wall-clock gate would have
    // suppressed it and every later publish until the clock caught up).
    func testAdvancingSequenceAcceptedRegardlessOfBackwardClock() {
        XCTAssertTrue(WatchConnectivityPublisher.shouldQueue(captureSequence: 6, afterLastQueued: 5))
    }

    // The activation retry resends its ORIGINAL sequence. Resending the same
    // sequence (nothing newer queued in the meantime) passes the `>=` gate, so
    // the pending snapshot still ships after activation completes.
    func testRetryWithOriginalSequenceShipsWhenNothingNewerArrived() {
        XCTAssertTrue(WatchConnectivityPublisher.shouldQueue(captureSequence: 5, afterLastQueued: 5))
    }

    // ...but if a NEWER publish landed while activation was pending, the retry's
    // original (older) sequence is correctly dropped rather than resurrecting the
    // stale snapshot over the newer one. This is exactly why the retry keeps its
    // ORIGINAL sequence instead of allocating a fresh (newer) one — a fresh
    // sequence would let the stale retry outrank the newer publish.
    func testRetryWithOriginalSequenceIsDroppedWhenNewerPublishArrived() {
        XCTAssertFalse(WatchConnectivityPublisher.shouldQueue(captureSequence: 5, afterLastQueued: 6))
    }

    // The publisher-owned counter is strictly monotonic across allocations, so
    // capture order equals sequence order (and it lives on the process-wide
    // singleton, surviving a store re-creation).
    @MainActor
    func testNextCaptureSequenceIsStrictlyMonotonic() {
        let publisher = WatchConnectivityPublisher.shared
        let first = publisher.nextCaptureSequence()
        let second = publisher.nextCaptureSequence()
        let third = publisher.nextCaptureSequence()
        XCTAssertLessThan(first, second)
        XCTAssertLessThan(second, third)
    }
}
