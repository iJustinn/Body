//
//  WatchMetricsModelApplyTests.swift
//  BodyWatchTests
//
//  Locks `WatchMetricsModel.apply` (H-10, M-33, L-36): the RAW snapshot is what
//  reaches disk, the displayed one is sanitized, an unchanged push neither
//  re-saves nor reloads the complication timelines, and a save that FAILED is
//  retried on the next call rather than being recorded as persisted.
//
//  The model's `init` reads the real snapshot store and UserDefaults, so every
//  assertion here is on RELATIVE spy counts around a call, never on an absolute
//  count or on whatever the device happens to have stored.
//

import XCTest
@testable import BodyWatch

@MainActor
final class WatchMetricsModelApplyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    /// Mutable spy state. A class so the escaping closures share it.
    private final class Spy {
        var persisted: [WatchMetricsSnapshot] = []
        var reloads = 0
        var saveSucceeds = true
    }

    private func metric() -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.heartRate,
            title: "Heart Rate",
            displayValue: "62",
            unit: "bpm",
            score: nil,
            fillFraction: 0.5,
            rawValue: 62
        )
    }

    /// A snapshot whose publish line is far ahead of anything the device could
    /// have stored, so the model's initial `lastPersistedSnapshot` can't match.
    private func snapshot(revision: UInt64) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: t0.addingTimeInterval(Double(revision)),
            lastRefreshDate: t0,
            metrics: [metric()],
            publisherEpoch: "apply-tests",
            revision: revision
        )
    }

    private func makeModel() -> (WatchMetricsModel, Spy) {
        let spy = Spy()
        let model = WatchMetricsModel(
            persistSnapshot: { snapshot in
                guard spy.saveSucceeds else { return false }
                spy.persisted.append(snapshot)
                return true
            },
            reloadTimelines: { spy.reloads += 1 }
        )
        return (model, spy)
    }

    /// H-10: the same snapshot applied twice must persist and reload ONCE. The
    /// per-push `reloadAllTimelines()` was the watch's biggest complication
    /// budget cost.
    func testUnchangedSnapshotIsNotRepersistedOrReloaded() {
        let (model, spy) = makeModel()
        let raw = snapshot(revision: 1)

        model.applyForTesting(raw)
        XCTAssertEqual(spy.persisted.count, 1)
        XCTAssertEqual(spy.reloads, 1)

        model.applyForTesting(raw)
        XCTAssertEqual(spy.persisted.count, 1)
        XCTAssertEqual(spy.reloads, 1)

        // A genuinely different snapshot still goes through.
        model.applyForTesting(snapshot(revision: 2))
        XCTAssertEqual(spy.persisted.count, 2)
        XCTAssertEqual(spy.reloads, 2)
    }

    /// A failed save must NOT be recorded as persisted, or the early-out would
    /// swallow the retry and the complications would never see the value.
    func testFailedSaveIsRetriedOnTheNextApply() {
        let (model, spy) = makeModel()
        let raw = snapshot(revision: 3)

        spy.saveSucceeds = false
        model.applyForTesting(raw)
        XCTAssertTrue(spy.persisted.isEmpty)
        XCTAssertEqual(spy.reloads, 0)

        spy.saveSucceeds = true
        model.applyForTesting(raw)
        XCTAssertEqual(spy.persisted.count, 1)
        XCTAssertEqual(spy.reloads, 1)
    }

    /// L-36: sanitization is a DISPLAY guard, so the raw snapshot is what gets
    /// persisted while the published one is sanitized.
    func testRawSnapshotIsPersistedAndSanitizedOneIsDisplayed() {
        let (model, spy) = makeModel()
        var stale = metric()
        stale.kind = WatchMetricKindKey.sleep
        stale.title = "Sleep"
        // A night that ended two days ago: sanitization clears the headline at
        // display time, but the stored bytes must keep it.
        stale.measuredAt = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        stale.computedAt = stale.measuredAt
        var raw = snapshot(revision: 4)
        raw.metrics = [stale]

        model.applyForTesting(raw)

        XCTAssertEqual(spy.persisted.last, raw)
        XCTAssertEqual(model.snapshot, raw.sanitized())
    }
}
