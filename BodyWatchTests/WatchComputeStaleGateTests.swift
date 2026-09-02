//
//  WatchComputeStaleGateTests.swift
//  BodyWatchTests
//
//  Locks the recompute gate (`WatchMetricsModel.isComputeStale`). A compute is
//  ~20 HealthKit round trips, so the battery backstop is that the ATTEMPT
//  throttle comes first: an empty snapshot still computes, but at most once per
//  `staleInterval`, so a watch that can never fill it (HealthKit denied, no
//  readable data) doesn't run a full compute on every app open (H-09).
//

import XCTest
@testable import BodyWatch

final class WatchComputeStaleGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private var staleInterval: TimeInterval { WatchMetricsSnapshot.staleInterval }

    private func snapshot(metrics: [WatchMetric]) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: now, metrics: metrics)
    }

    private func freshHeartRate() -> WatchMetric {
        var metric = WatchMetric(
            kind: WatchMetricKindKey.heartRate,
            title: "Heart Rate",
            displayValue: "62",
            unit: "bpm",
            score: nil,
            fillFraction: 0.5,
            rawValue: 62
        )
        metric.computedAt = now
        return metric
    }

    private func isStale(
        metrics: [WatchMetric],
        lastComputeAttemptDate: Date?,
        lastComputeDate: Date? = nil
    ) -> Bool {
        WatchMetricsModel.isComputeStale(
            snapshot: snapshot(metrics: metrics),
            lastComputeAttemptDate: lastComputeAttemptDate,
            lastComputeDate: lastComputeDate,
            scansWorkoutMinutes: true,
            isMetricVisible: { _ in true },
            now: now
        )
    }

    // MARK: - Empty snapshot

    func testEmptySnapshotComputesWhenNothingHasBeenAttempted() {
        XCTAssertTrue(isStale(metrics: [], lastComputeAttemptDate: nil))
    }

    /// H-09: the empty-snapshot case used to short-circuit ABOVE the throttle,
    /// so a watch whose compute can never populate anything recomputed on every
    /// single app open.
    func testEmptySnapshotIsThrottledByARecentAttempt() {
        XCTAssertFalse(
            isStale(metrics: [], lastComputeAttemptDate: now.addingTimeInterval(-staleInterval / 2))
        )
    }

    func testEmptySnapshotComputesAgainOnceTheAttemptWindowPassed() {
        XCTAssertTrue(
            isStale(metrics: [], lastComputeAttemptDate: now.addingTimeInterval(-staleInterval - 60))
        )
    }

    // MARK: - Populated snapshot (unchanged behaviour)

    func testStaleVisibleMetricComputesWhenTheAttemptWindowPassed() {
        var stale = freshHeartRate()
        stale.computedAt = now.addingTimeInterval(-24 * 60 * 60)
        XCTAssertTrue(isStale(metrics: [stale], lastComputeAttemptDate: nil))
        XCTAssertTrue(
            isStale(metrics: [stale], lastComputeAttemptDate: now.addingTimeInterval(-staleInterval - 60))
        )
        // Still throttled inside the window.
        XCTAssertFalse(
            isStale(metrics: [stale], lastComputeAttemptDate: now.addingTimeInterval(-60))
        )
    }

    func testFreshMetricsAndARecentComputeAreNotStale() {
        XCTAssertFalse(
            isStale(metrics: [freshHeartRate()], lastComputeAttemptDate: nil, lastComputeDate: now)
        )
        // Fresh metrics but no successful compute yet this launch: still runs.
        XCTAssertTrue(
            isStale(metrics: [freshHeartRate()], lastComputeAttemptDate: nil, lastComputeDate: nil)
        )
    }

    /// A hidden metric is not on screen, so its staleness must not drive the
    /// gate (the visibility closure is the model's own `isMetricVisible`).
    func testHiddenMetricsAreNotScanned() {
        var stale = freshHeartRate()
        stale.computedAt = now.addingTimeInterval(-24 * 60 * 60)
        XCTAssertFalse(
            WatchMetricsModel.isComputeStale(
                snapshot: snapshot(metrics: [stale]),
                lastComputeAttemptDate: nil,
                lastComputeDate: now,
                scansWorkoutMinutes: true,
                isMetricVisible: { _ in false },
                now: now
            )
        )
    }
}
