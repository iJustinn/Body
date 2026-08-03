//
//  WatchSnapshotFreshnessTests.swift
//  BodyWatchTests
//
//  Locks the watch-side snapshot ordering (`WatchMetricsSnapshot.supersedes`) and
//  the per-kind live-freshness windows. The comparator must order snapshots by the
//  phone's monotonic (epoch, revision) pair rather than the device clock, so a
//  clock rollback can't let a stale payload outrank a newer one, a reinstall wins,
//  and a legacy payload (no epoch) still falls back to `generatedAt`.
//

import XCTest
@testable import BodyWatch

final class WatchSnapshotFreshnessTests: XCTestCase {
    private func snapshot(
        epoch: String?,
        revision: UInt64?,
        generatedAt: Date
    ) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: generatedAt,
            lastRefreshDate: nil,
            metrics: [],
            publisherEpoch: epoch,
            revision: revision
        )
    }

    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)

    // MARK: - supersedes: same epoch → revision authoritative

    func testHigherRevisionSupersedesEvenWithEarlierGeneratedAt() {
        // Clock rolled back: the newer publish has an EARLIER generatedAt but a
        // higher revision, and must still win.
        let incoming = snapshot(epoch: "A", revision: 5, generatedAt: t0)
        let current = snapshot(epoch: "A", revision: 4, generatedAt: t1)

        XCTAssertTrue(incoming.supersedes(current))
        XCTAssertFalse(current.supersedes(incoming))
    }

    func testLowerRevisionDoesNotSupersede() {
        let incoming = snapshot(epoch: "A", revision: 3, generatedAt: t1)
        let current = snapshot(epoch: "A", revision: 7, generatedAt: t0)

        XCTAssertFalse(incoming.supersedes(current))
    }

    func testEqualRevisionTieBreaksOnGeneratedAt() {
        let later = snapshot(epoch: "A", revision: 2, generatedAt: t1)
        let earlier = snapshot(epoch: "A", revision: 2, generatedAt: t0)

        XCTAssertTrue(later.supersedes(earlier))
        XCTAssertFalse(earlier.supersedes(later))
    }

    func testEqualEpochRevisionAndDateDoesNotSupersede() {
        // Two byte-identical snapshots (the dedupe case): neither supersedes.
        let a = snapshot(epoch: "A", revision: 2, generatedAt: t0)
        let b = snapshot(epoch: "A", revision: 2, generatedAt: t0)

        XCTAssertFalse(a.supersedes(b))
        XCTAssertFalse(b.supersedes(a))
    }

    func testNilRevisionTreatedAsZeroWithinSameEpoch() {
        let withRevision = snapshot(epoch: "A", revision: 1, generatedAt: t0)
        let noRevision = snapshot(epoch: "A", revision: nil, generatedAt: t1)

        // rev 1 > (nil→0), so the revisioned payload wins despite the older date.
        XCTAssertTrue(withRevision.supersedes(noRevision))
        XCTAssertFalse(noRevision.supersedes(withRevision))
    }

    // MARK: - supersedes: different / unknown epoch → reinstall wins

    func testDifferentEpochAcceptsIncomingRegardlessOfRevision() {
        // Reinstall mints a fresh epoch and restarts revision at 1; it must still
        // supersede the old install's high-revision snapshot.
        let reinstalled = snapshot(epoch: "B", revision: 1, generatedAt: t0)
        let old = snapshot(epoch: "A", revision: 999, generatedAt: t1)

        XCTAssertTrue(reinstalled.supersedes(old))
    }

    func testEpochedIncomingSupersedesLegacyCurrent() {
        let incoming = snapshot(epoch: "A", revision: 1, generatedAt: t0)
        let legacy = snapshot(epoch: nil, revision: nil, generatedAt: t1)

        XCTAssertTrue(incoming.supersedes(legacy))
    }

    func testLegacyIncomingSupersedesEpochedCurrent() {
        // Only one side carries an epoch (unknown pairing): accept incoming.
        let incoming = snapshot(epoch: nil, revision: nil, generatedAt: t0)
        let current = snapshot(epoch: "A", revision: 1, generatedAt: t1)

        XCTAssertTrue(incoming.supersedes(current))
    }

    // MARK: - supersedes: both legacy → generatedAt rule

    func testBothLegacyOrderByGeneratedAt() {
        let later = snapshot(epoch: nil, revision: nil, generatedAt: t1)
        let earlier = snapshot(epoch: nil, revision: nil, generatedAt: t0)

        XCTAssertTrue(later.supersedes(earlier))
        XCTAssertFalse(earlier.supersedes(later))
        XCTAssertFalse(later.supersedes(later))
    }

    // MARK: - Schema evolution

    func testLegacyPayloadWithoutEpochOrRevisionDecodes() throws {
        // A snapshot from a phone build before the epoch/revision fields existed:
        // the JSON omits both keys and must still decode (nil epoch + revision).
        let json = """
        {"generatedAt":"2001-09-09T01:46:40Z","metrics":[]}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data))

        XCTAssertNil(decoded.publisherEpoch)
        XCTAssertNil(decoded.revision)
    }

    func testEpochAndRevisionRoundTrip() throws {
        let original = snapshot(epoch: "epoch-1", revision: 42, generatedAt: t0)
        let data = try XCTUnwrap(original.encoded())
        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: data))

        XCTAssertEqual(decoded.publisherEpoch, "epoch-1")
        XCTAssertEqual(decoded.revision, 42)
        XCTAssertTrue(decoded.supersedes(snapshot(epoch: "epoch-1", revision: 41, generatedAt: t1)))
    }

    // MARK: - Per-kind live-freshness windows

    func testLiveFreshnessLimitIsPerKind() {
        XCTAssertEqual(WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.heartRate), 30 * 60)
        XCTAssertEqual(WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.heartRateVariability), 4 * 60 * 60)
    }

    func testLiveFreshnessLimitFallsBackToSnapshotIntervalForOtherKinds() {
        XCTAssertEqual(
            WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.restingHeartRate),
            WatchMetricsSnapshot.staleInterval
        )
        XCTAssertEqual(
            WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.readiness),
            WatchMetricsSnapshot.staleInterval
        )
    }

    // MARK: - Clock-domain freshness helpers (WatchMetricsModel)
    //
    // These back the watch-local (`lastComputeAttemptDate`, `lastComputeDate`)
    // and phone-stamped (`lastRefreshDate`, `computedAt`/`liveUpdatedAt`)
    // staleness gates in `WatchMetricsModel`. The gates themselves are private
    // main-actor instance state driven from HealthKit/WatchConnectivity, so
    // they aren't reachable from a unit test; these exercise the pure helper
    // functions the gates are built on, which is the only testable seam for
    // the future-date behavior described below.

    func testFreshLocalDateRejectsFutureDate() {
        // A watch-local clock rollback (or a bad persisted stamp): a date in
        // the future must read as NOT fresh, so the caller treats it as stale
        // and allows recompute rather than parking on it forever.
        let now = t1
        let future = t1.addingTimeInterval(60)
        XCTAssertFalse(WatchMetricsModel.isFreshLocalDate(future, limit: WatchMetricsSnapshot.staleInterval, now: now))
    }

    func testFreshLocalDateAcceptsWithinLimitNotInFuture() {
        let now = t1
        let recent = t1.addingTimeInterval(-60)
        XCTAssertTrue(WatchMetricsModel.isFreshLocalDate(recent, limit: WatchMetricsSnapshot.staleInterval, now: now))
    }

    func testFreshLocalDateRejectsBeyondLimit() {
        let now = t1
        let stale = t1.addingTimeInterval(-WatchMetricsSnapshot.staleInterval - 1)
        XCTAssertFalse(WatchMetricsModel.isFreshLocalDate(stale, limit: WatchMetricsSnapshot.staleInterval, now: now))
    }

    func testFreshPhoneDateToleratesAFewSecondsInTheFuture() {
        // Ordinary phone/watch clock skew: a phone-stamped date a few seconds
        // ahead of the watch's clock must still read as fresh, not stale.
        let now = t1
        let slightlyFuture = t1.addingTimeInterval(5)
        XCTAssertTrue(WatchMetricsModel.isFreshPhoneDate(slightlyFuture, limit: WatchMetricsSnapshot.staleInterval, now: now))
    }

    func testFreshPhoneDateRejectsFarBeyondSkewTolerance() {
        // Past the staleInterval skew allowance, a future phone stamp is no
        // longer ordinary clock skew and must read as stale.
        let now = t1
        let farFuture = t1.addingTimeInterval(WatchMetricsSnapshot.staleInterval + 60)
        XCTAssertFalse(WatchMetricsModel.isFreshPhoneDate(farFuture, limit: WatchMetricsSnapshot.staleInterval, now: now))
    }

    func testFreshPhoneDateRejectsBeyondLimit() {
        let now = t1
        let stale = t1.addingTimeInterval(-WatchMetricsSnapshot.staleInterval - 1)
        XCTAssertFalse(WatchMetricsModel.isFreshPhoneDate(stale, limit: WatchMetricsSnapshot.staleInterval, now: now))
    }
}
