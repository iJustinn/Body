//
//  WorkoutSnapshotStore.swift
//  Body
//

import Foundation
import os

enum WorkoutSnapshotStore {
    static let appGroupIdentifier = "group.com.zihengthedeveloper.Body"
    static let currentMonthSnapshotFileName = "currentMonthWorkoutSnapshot.json"
    static let previousMonthSnapshotFileName = "previousMonthWorkoutSnapshot.json"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutSnapshotStore")

    static var sharedContainerURL: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return nil
        }
        #endif

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            logger.error("App group container unavailable for \(appGroupIdentifier, privacy: .public)")
            return nil
        }

        return containerURL
    }

    static var snapshotFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(currentMonthSnapshotFileName)
    }

    static var previousSnapshotFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(previousMonthSnapshotFileName)
    }

    @discardableResult
    static func save(_ snapshot: WorkoutMonthSnapshot) -> Bool {
        save(snapshot, fileURL: snapshotFileURL)
    }

    @discardableResult
    static func save(_ snapshot: WorkoutMonthSnapshot, fileURL: URL?) -> Bool {
        guard let fileURL else {
            logger.error("Snapshot save skipped because shared snapshot file URL is unavailable.")
            return false
        }

        let data: Data
        do {
            // `.sortedKeys` keeps the encoded bytes deterministic so the
            // save-if-changed compare below actually dedupes writes;
            // `JSONEncoder` randomizes key order between calls otherwise.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(snapshot)
        } catch {
            logger.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
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

    static func load() -> WorkoutMonthSnapshot? {
        load(fileURL: snapshotFileURL)
    }

    /// Memoizes decoded snapshots keyed by file identity (mtime + size) so the
    /// widget extension's repeated timeline passes don't re-read and re-decode
    /// the same App-Group JSON. Lock-protected because widget providers may call
    /// `load` concurrently (project is Swift 5 language mode, no strict
    /// concurrency). Every `load` re-stats the file, so a cross-process rewrite
    /// (atomic write → new mtime) invalidates the entry. Both `load` funnels
    /// (current + previous month) route through `load(fileURL:)`.
    private final class LoadCache {
        private let lock = NSLock()
        private var entries: [URL: (modificationDate: Date, fileSize: Int, snapshot: WorkoutMonthSnapshot)] = [:]

        func snapshot(for url: URL, modificationDate: Date, fileSize: Int) -> WorkoutMonthSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[url],
                  entry.modificationDate == modificationDate,
                  entry.fileSize == fileSize else {
                return nil
            }
            return entry.snapshot
        }

        func store(_ snapshot: WorkoutMonthSnapshot, for url: URL, modificationDate: Date, fileSize: Int) {
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

    static func load(fileURL: URL?) -> WorkoutMonthSnapshot? {
        guard let fileURL else {
            logger.error("Snapshot load skipped because shared snapshot file URL is unavailable.")
            return nil
        }

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

        do {
            let snapshot = try JSONDecoder().decode(WorkoutMonthSnapshot.self, from: data)
            if let modificationDate, let fileSize {
                loadCache.store(snapshot, for: fileURL, modificationDate: modificationDate, fileSize: fileSize)
            }
            return snapshot
        } catch {
            logger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            loadCache.remove(fileURL)
            return nil
        }
    }

    /// Single launch-path read: returns the cached current-month snapshot,
    /// seeding the preview placeholder on first launch so widgets have
    /// content before HealthKit authorization. Replaces the separate seed +
    /// load calls that decoded the same file twice at launch.
    static func loadOrSeedPlaceholder() -> WorkoutMonthSnapshot {
        if let snapshot = load() {
            return snapshot
        }

        save(.placeholder)
        return .placeholder
    }

    @discardableResult
    static func savePrevious(_ snapshot: WorkoutMonthSnapshot) -> Bool {
        save(snapshot, fileURL: previousSnapshotFileURL)
    }

    static func loadPrevious() -> WorkoutMonthSnapshot? {
        load(fileURL: previousSnapshotFileURL)
    }

    static func loadCurrentOrPreviousIfEmpty() -> WorkoutMonthSnapshot {
        let current = load()
        if let current, current.workoutCount > 0 {
            return current
        }
        if let previous = loadPrevious(), previous.workoutCount > 0 {
            return previous
        }
        return current ?? .placeholder
    }

    static func exists(fileURL: URL? = snapshotFileURL) -> Bool {
        guard let fileURL else {
            return false
        }

        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func fileSize(at fileURL: URL?) -> Int64 {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    static var totalDiskSizeBytes: Int64 {
        fileSize(at: snapshotFileURL) + fileSize(at: previousSnapshotFileURL)
    }

    static func delete(fileURL: URL? = snapshotFileURL) {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Snapshot file delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func deletePrevious() {
        delete(fileURL: previousSnapshotFileURL)
    }
}
