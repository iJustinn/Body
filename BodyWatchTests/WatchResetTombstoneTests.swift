//
//  WatchResetTombstoneTests.swift
//  BodyWatchTests
//
//  Locks the Clear-Cache reset path (H7). A reset tombstone from the phone must
//  REPLACE the watch snapshot rather than blank-preserve merge (so cleared data
//  doesn't linger), keep its `(publisherEpoch, revision)` so a delayed
//  lower-revision same-epoch push can't resurrect the data it cleared, persist
//  across a watch restart via the store (never deleted — else `load() ?? .empty`
//  loses the ordering), and yield to a subsequent higher-revision push. The
//  reset routing lives in the pure `WatchMetricsModel.resolvedSnapshot(_:over:)`;
//  the persistence in `WatchMetricsSnapshotStore`.
//
//  Publisher-side (M5) capture-sequence gate tests are NOT here:
//  `WatchConnectivityPublisher` compiles only into the iOS `Body` target and is
//  unreachable from this watchOS bundle — see the WP-C report for the BodyTests
//  spec.
//

import XCTest
@testable import BodyWatch

final class WatchResetTombstoneTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let t2 = Date(timeIntervalSince1970: 3_000_000)

    private func metric(_ kind: String, displayValue: String, rawValue: Double?) -> WatchMetric {
        WatchMetric(
            kind: kind,
            title: kind,
            displayValue: displayValue,
            unit: "bpm",
            score: nil,
            fillFraction: rawValue == nil ? 0 : 0.5,
            rawValue: rawValue
        )
    }

    /// A snapshot carrying real readings (heart rate + readiness).
    private func dataSnapshot(epoch: String, revision: UInt64, generatedAt: Date) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: generatedAt,
            lastRefreshDate: generatedAt,
            metrics: [
                metric(WatchMetricKindKey.heartRate, displayValue: "62", rawValue: 62),
                metric(WatchMetricKindKey.readiness, displayValue: "80", rawValue: 80)
            ],
            publisherEpoch: epoch,
            revision: revision
        )
    }

    /// The empty tombstone the phone's Clear-Cache path pushes, already stamped
    /// by the publisher's `revisionAllocator` (epoch set, revision advanced).
    private func resetSnapshot(epoch: String, revision: UInt64, generatedAt: Date) -> WatchMetricsSnapshot {
        WatchMetricsSnapshot(
            generatedAt: generatedAt,
            lastRefreshDate: nil,
            metrics: [],
            publisherEpoch: epoch,
            revision: revision,
            isReset: true
        )
    }

    private func uniqueFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyWatchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("watchMetricsSnapshot.json")
    }

    // MARK: - Reset replaces (not merges) and keeps ordering

    func testResetSupersedesPriorAndReplacesWithEmptyTombstone() throws {
        let current = dataSnapshot(epoch: "A", revision: 5, generatedAt: t1)
        let reset = resetSnapshot(epoch: "A", revision: 6, generatedAt: t2)

        let tombstone = try XCTUnwrap(WatchMetricsModel.resolvedSnapshot(applying: reset, over: current))

        // The blank-preserve merge would keep the local HR/readiness; the reset
        // must instead clear everything…
        XCTAssertTrue(tombstone.metrics.isEmpty)
        XCTAssertEqual(tombstone.isReset, true)
        // …while retaining its own ordering so later stale pushes stay ordered.
        XCTAssertEqual(tombstone.publisherEpoch, "A")
        XCTAssertEqual(tombstone.revision, 6)
    }

    func testStaleLowerRevisionPushAfterResetIsRejected() {
        let tombstone = resetSnapshot(epoch: "A", revision: 6, generatedAt: t2)
        // A delayed pre-clear publish: same epoch, lower revision, carries data.
        let stalePush = dataSnapshot(epoch: "A", revision: 4, generatedAt: t1)

        XCTAssertNil(WatchMetricsModel.resolvedSnapshot(applying: stalePush, over: tombstone))
    }

    // MARK: - Persistence across a watch restart

    func testPersistedTombstoneSurvivesRestartAndStillRejectsStalePush() throws {
        let fileURL = try uniqueFileURL()
        let tombstone = resetSnapshot(epoch: "A", revision: 6, generatedAt: t2)

        // Persist exactly as the model does — save, never delete.
        XCTAssertTrue(WatchMetricsSnapshotStore.save(tombstone, fileURL: fileURL))

        // Restart: a fresh process re-reads the file (`load() ?? .empty`).
        let reloaded = try XCTUnwrap(WatchMetricsSnapshotStore.load(fileURL: fileURL))
        XCTAssertTrue(reloaded.metrics.isEmpty)
        XCTAssertEqual(reloaded.isReset, true)
        XCTAssertEqual(reloaded.revision, 6)

        // The reloaded tombstone still rejects a delayed lower-revision push.
        let stalePush = dataSnapshot(epoch: "A", revision: 4, generatedAt: t1)
        XCTAssertNil(WatchMetricsModel.resolvedSnapshot(applying: stalePush, over: reloaded))
    }

    func testDeletingTheTombstoneWouldResurrectDataDocumentingWhyWePersist() {
        // Contrast (why we persist instead of delete): after a restart with the
        // file deleted, the model falls back to `.empty` (no epoch), which a
        // delayed lower-revision push supersedes (unknown epoch → accept) — the
        // exact resurrection the persisted tombstone prevents.
        let stalePush = dataSnapshot(epoch: "A", revision: 4, generatedAt: t1)
        XCTAssertNotNil(WatchMetricsModel.resolvedSnapshot(applying: stalePush, over: .empty))
    }

    // MARK: - A later normal push repopulates

    func testHigherRevisionNormalPushAfterResetRepopulates() throws {
        let tombstone = resetSnapshot(epoch: "A", revision: 6, generatedAt: t2)
        let normalPush = dataSnapshot(epoch: "A", revision: 7, generatedAt: t2.addingTimeInterval(60))

        let resolved = try XCTUnwrap(WatchMetricsModel.resolvedSnapshot(applying: normalPush, over: tombstone))

        XCTAssertNotEqual(resolved.isReset, true)
        XCTAssertEqual(resolved.metrics.count, normalPush.metrics.count)
        XCTAssertEqual(resolved.metric(forKind: WatchMetricKindKey.heartRate)?.rawValue, 62)
    }

    // MARK: - Non-reset merge unchanged (blank-preserve regression guard)

    func testNonResetBlankPushStillPreservesGoodLocalValue() throws {
        // The refactor that extracted `merging` must keep the intentional
        // blank-preserve rule: a non-readiness metric arriving blank does NOT
        // overwrite a good local value.
        let current = dataSnapshot(epoch: "A", revision: 5, generatedAt: t1)
        let push = WatchMetricsSnapshot(
            generatedAt: t2,
            lastRefreshDate: t2,
            metrics: [metric(WatchMetricKindKey.heartRate, displayValue: "--", rawValue: nil)],
            publisherEpoch: "A",
            revision: 6
        )

        let resolved = try XCTUnwrap(WatchMetricsModel.resolvedSnapshot(applying: push, over: current))
        let hr = try XCTUnwrap(resolved.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(hr.rawValue, 62)
        XCTAssertEqual(hr.displayValue, "62")
    }

    // MARK: - isReset schema tolerance

    func testNilIsResetIsOmittedFromEncoding() throws {
        // A nil isReset must not appear in the payload, so non-reset snapshots
        // dedupe byte-for-byte exactly as before the field existed.
        let normal = dataSnapshot(epoch: "A", revision: 1, generatedAt: t0)
        XCTAssertNil(normal.isReset)
        let json = try XCTUnwrap(String(data: try XCTUnwrap(normal.encoded()), encoding: .utf8))
        XCTAssertFalse(json.contains("isReset"))
    }

    func testIsResetRoundTripsAndLegacyPayloadDecodesNil() throws {
        let reset = resetSnapshot(epoch: "A", revision: 2, generatedAt: t0)
        let decoded = try XCTUnwrap(WatchMetricsSnapshot.decoded(from: try XCTUnwrap(reset.encoded())))
        XCTAssertEqual(decoded.isReset, true)

        // A payload from a phone build before the field existed omits the key.
        let legacyJSON = #"{"generatedAt":"2001-09-09T01:46:40Z","metrics":[]}"#
        let legacy = try XCTUnwrap(
            WatchMetricsSnapshot.decoded(from: try XCTUnwrap(legacyJSON.data(using: .utf8)))
        )
        XCTAssertNil(legacy.isReset)
    }
}
