//
//  WatchMetricsSnapshotStoreLoadCacheTests.swift
//  BodyWatchTests
//
//  Watch-side counterpart to BodyTests/SnapshotStoreLoadCacheTests. The watch
//  metrics store is a Body-target membership exception (watch-only), so it can't
//  be reached from the iOS test bundle — this watchOS unit-test target hosts on
//  the BodyWatch app and `@testable import`s it to exercise the same file-identity
//  load memoization (rewrite / delete / garbage) the iOS stores are tested for.
//
//  The cache is keyed by file identity (mtime + size), so each test uses a unique
//  temp-file URL to keep the process-wide static cache from bleeding between cases.
//

import XCTest
@testable import BodyWatch

final class WatchMetricsSnapshotStoreLoadCacheTests: XCTestCase {
    private func uniqueFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyWatchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("watchMetricsSnapshot.json")
    }

    func testLoadInvalidatesOnRewrite() throws {
        let fileURL = try uniqueFileURL()
        let snapshotA = WatchMetricsSnapshot.empty
        let snapshotB = WatchMetricsSnapshot.placeholder

        WatchMetricsSnapshotStore.save(snapshotA, fileURL: fileURL)
        XCTAssertEqual(WatchMetricsSnapshotStore.load(fileURL: fileURL), snapshotA)

        WatchMetricsSnapshotStore.save(snapshotB, fileURL: fileURL)
        XCTAssertEqual(WatchMetricsSnapshotStore.load(fileURL: fileURL), snapshotB)
    }

    func testRepeatedLoadReturnsEqualResult() throws {
        let fileURL = try uniqueFileURL()
        let snapshot = WatchMetricsSnapshot.placeholder

        WatchMetricsSnapshotStore.save(snapshot, fileURL: fileURL)

        let first = WatchMetricsSnapshotStore.load(fileURL: fileURL)
        let second = WatchMetricsSnapshotStore.load(fileURL: fileURL)

        XCTAssertEqual(first, snapshot)
        XCTAssertEqual(first, second)
    }

    func testLoadReturnsNilAfterDelete() throws {
        let fileURL = try uniqueFileURL()

        WatchMetricsSnapshotStore.save(.placeholder, fileURL: fileURL)
        XCTAssertNotNil(WatchMetricsSnapshotStore.load(fileURL: fileURL))

        // No `delete(fileURL:)` on the watch store — remove the file directly to
        // exercise the cache's fileReadNoSuchFile → invalidation path.
        try FileManager.default.removeItem(at: fileURL)
        XCTAssertNil(WatchMetricsSnapshotStore.load(fileURL: fileURL))
    }

    func testLoadReturnsNilForGarbageBytesRepeatedly() throws {
        let fileURL = try uniqueFileURL()

        WatchMetricsSnapshotStore.save(.placeholder, fileURL: fileURL)
        XCTAssertNotNil(WatchMetricsSnapshotStore.load(fileURL: fileURL))

        try Data("not json at all".utf8).write(to: fileURL, options: [.atomic])

        XCTAssertNil(WatchMetricsSnapshotStore.load(fileURL: fileURL))
        XCTAssertNil(WatchMetricsSnapshotStore.load(fileURL: fileURL))
    }
}
