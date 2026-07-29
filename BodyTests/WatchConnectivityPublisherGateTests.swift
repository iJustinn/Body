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
import WatchConnectivity
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

    // MARK: - Whole-context compute-seed budget (Phase 3)
    //
    // The compute seed (an optional, potentially large extra context key) must
    // never be the reason the always-required display snapshot fails to ship.
    // `shouldIncludeComputeSeed` is the pure gate `send` consults before adding
    // `WatchComputeSeed.applicationContextKey` to the context dict — exercised
    // here without a live `WCSession`.

    func testComputeSeedIncludedWhenTotalFitsBudget() {
        XCTAssertTrue(WatchConnectivityPublisher.shouldIncludeComputeSeed(
            snapshotSize: 2_000, permissionSize: 20, seedSize: 10_000, budget: 60_000
        ))
    }

    func testComputeSeedDroppedWhenTotalExceedsBudget() {
        XCTAssertFalse(WatchConnectivityPublisher.shouldIncludeComputeSeed(
            snapshotSize: 2_000, permissionSize: 20, seedSize: 100_000, budget: 60_000
        ))
    }

    func testComputeSeedBudgetBoundaryIsInclusive() {
        XCTAssertTrue(WatchConnectivityPublisher.shouldIncludeComputeSeed(
            snapshotSize: 50, permissionSize: 0, seedSize: 50, budget: 100
        ))
        XCTAssertFalse(WatchConnectivityPublisher.shouldIncludeComputeSeed(
            snapshotSize: 51, permissionSize: 0, seedSize: 50, budget: 100
        ))
    }

    func testComputeSeedBudgetDefaultsToTheSixtyKilobyteConstant() {
        XCTAssertTrue(WatchConnectivityPublisher.shouldIncludeComputeSeed(
            snapshotSize: 0, permissionSize: 0, seedSize: WatchConnectivityPublisher.contextSizeBudgetBytes
        ))
        XCTAssertFalse(WatchConnectivityPublisher.shouldIncludeComputeSeed(
            snapshotSize: 1, permissionSize: 0, seedSize: WatchConnectivityPublisher.contextSizeBudgetBytes
        ))
    }

    // MARK: - contexts(snapshotData:permissionRawValue:seedData:seedSettingsSignature:) (Phase 3)
    //
    // The two context dictionary SHAPES a send may use: `primary` (with the
    // seed, when supplied) and `fallback` (the same context minus the seed key,
    // used only for the size-driven retry). Both must always retain "snapshot" —
    // a send can never drop the always-required display payload — and both
    // carry the tiny settings-signature key, whose whole purpose is to survive
    // the seed blob being dropped.

    func testPrimaryContextContainsSnapshotPermissionAndSeedKeys() {
        let snapshotData = Data([0x01])
        let seedData = Data([0x02])
        let contexts = WatchConnectivityPublisher.contexts(
            snapshotData: snapshotData, permissionRawValue: "sleep,heart", seedData: seedData,
            seedSettingsSignature: "sig-1"
        )

        XCTAssertEqual(contexts.primary["snapshot"] as? Data, snapshotData)
        XCTAssertEqual(contexts.primary[BodyAppearancePreference.healthPermissionSelectionKey] as? String, "sleep,heart")
        XCTAssertEqual(contexts.primary[WatchComputeSeed.applicationContextKey] as? Data, seedData)
        XCTAssertEqual(contexts.primary[WatchComputeSeed.applicationContextSettingsSignatureKey] as? String, "sig-1")
    }

    func testFallbackContextOmitsTheSeedKeyButAlwaysRetainsSnapshot() {
        let snapshotData = Data([0x01])
        let seedData = Data([0x02])
        let contexts = WatchConnectivityPublisher.contexts(
            snapshotData: snapshotData, permissionRawValue: "sleep,heart", seedData: seedData,
            seedSettingsSignature: "sig-1"
        )

        XCTAssertEqual(contexts.fallback["snapshot"] as? Data, snapshotData)
        XCTAssertEqual(contexts.fallback[BodyAppearancePreference.healthPermissionSelectionKey] as? String, "sleep,heart")
        XCTAssertNil(contexts.fallback[WatchComputeSeed.applicationContextKey])
        // The signature must SURVIVE the seed drop — it is what lets the watch
        // invalidate a stored seed built under superseded settings.
        XCTAssertEqual(contexts.fallback[WatchComputeSeed.applicationContextSettingsSignatureKey] as? String, "sig-1")
    }

    func testContextsOmitThePermissionKeyWhenSelectionIsNil() {
        let contexts = WatchConnectivityPublisher.contexts(
            snapshotData: Data([0x01]), permissionRawValue: nil, seedData: nil,
            seedSettingsSignature: nil
        )

        XCTAssertNotNil(contexts.primary["snapshot"])
        XCTAssertNil(contexts.primary[BodyAppearancePreference.healthPermissionSelectionKey])
        XCTAssertNil(contexts.primary[WatchComputeSeed.applicationContextKey])
        // With no seed supplied, primary and fallback carry the same keys.
        XCTAssertEqual(contexts.primary.keys.sorted(), contexts.fallback.keys.sorted())
    }

    // MARK: - isSeedSizeFailure(_:) (Phase 3)

    func testIsSeedSizeFailureIsTrueOnlyForPayloadTooLarge() {
        XCTAssertTrue(WatchConnectivityPublisher.isSeedSizeFailure(WCError(.payloadTooLarge)))
        XCTAssertFalse(WatchConnectivityPublisher.isSeedSizeFailure(WCError(.sessionNotActivated)))
        XCTAssertFalse(WatchConnectivityPublisher.isSeedSizeFailure(WCError(.deliveryFailed)))
        XCTAssertFalse(WatchConnectivityPublisher.isSeedSizeFailure(NSError(domain: "test", code: 1)))
    }
}
