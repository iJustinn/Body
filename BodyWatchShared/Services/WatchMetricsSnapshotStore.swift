//
//  WatchMetricsSnapshotStore.swift
//  BodyWatchShared
//
//  On-watch cache for the latest metrics snapshot, shared between the watch
//  app and the watch widget extension via the App Group container. Mirrors the
//  `WorkoutSnapshotStore` pattern (deterministic encode, save-if-changed).
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import Foundation
import os

enum WatchMetricsSnapshotStore {
    static let appGroupIdentifier = "group.com.zihengthedeveloper.Body"
    static let snapshotFileName = "watchMetricsSnapshot.json"
    private static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "WatchMetricsSnapshotStore"
    )

    static var sharedContainerURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            logger.error("App group container unavailable for \(appGroupIdentifier, privacy: .public)")
            return nil
        }
        return containerURL
    }

    static var snapshotFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(snapshotFileName)
    }

    @discardableResult
    static func save(_ snapshot: WatchMetricsSnapshot) -> Bool {
        save(snapshot, fileURL: snapshotFileURL)
    }

    @discardableResult
    static func save(_ snapshot: WatchMetricsSnapshot, fileURL: URL?) -> Bool {
        guard let fileURL else {
            logger.error("Save skipped: shared snapshot file URL unavailable.")
            return false
        }

        guard let data = snapshot.encoded() else {
            logger.error("Snapshot encode failed.")
            return false
        }

        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            logger.error("Snapshot file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func load() -> WatchMetricsSnapshot? {
        load(fileURL: snapshotFileURL)
    }

    /// Memoizes decoded snapshots keyed by file identity (mtime + size) so the
    /// watch complication providers' repeated timeline passes (7 complications ×
    /// families × getSnapshot+getTimeline) don't re-read and re-decode the same
    /// App-Group JSON. Lock-protected because providers may call `load`
    /// concurrently (project is Swift 5 language mode, no strict concurrency).
    /// Every `load` re-stats the file, so a cross-process rewrite (atomic write →
    /// new mtime) invalidates the entry.
    private final class LoadCache {
        private let lock = NSLock()
        private var entries: [URL: (modificationDate: Date, fileSize: Int, snapshot: WatchMetricsSnapshot)] = [:]

        func snapshot(for url: URL, modificationDate: Date, fileSize: Int) -> WatchMetricsSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[url],
                  entry.modificationDate == modificationDate,
                  entry.fileSize == fileSize else {
                return nil
            }
            return entry.snapshot
        }

        func store(_ snapshot: WatchMetricsSnapshot, for url: URL, modificationDate: Date, fileSize: Int) {
            lock.lock()
            entries[url] = (modificationDate, fileSize, snapshot)
            lock.unlock()
        }

        func remove(_ url: URL) {
            lock.lock()
            entries.removeValue(forKey: url)
            lock.unlock()
        }
    }

    private static let loadCache = LoadCache()

    static func load(fileURL: URL?) -> WatchMetricsSnapshot? {
        guard let fileURL else { return nil }

        // Stat before reading so a cache hit skips the read+decode, and a store
        // records the identity the decoded bytes actually came from. FileManager
        // (not URL.resourceValues) because URL caches resource values per
        // instance — a stale hit there would mask a rewrite behind the same URL.
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modificationDate = attributes?[.modificationDate] as? Date
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue
        if let modificationDate,
           let fileSize,
           let cached = loadCache.snapshot(for: fileURL, modificationDate: modificationDate, fileSize: fileSize) {
            return cached
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            loadCache.remove(fileURL)
            return nil
        } catch {
            logger.error("Snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            loadCache.remove(fileURL)
            return nil
        }

        guard let snapshot = WatchMetricsSnapshot.decoded(from: data) else {
            loadCache.remove(fileURL)
            return nil
        }

        if let modificationDate, let fileSize {
            loadCache.store(snapshot, for: fileURL, modificationDate: modificationDate, fileSize: fileSize)
        }
        return snapshot
    }
}
