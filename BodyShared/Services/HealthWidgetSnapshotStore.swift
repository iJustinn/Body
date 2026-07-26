//
//  HealthWidgetSnapshotStore.swift
//  Body
//
//  Persists the slim health widget snapshot to the shared App Group container
//  so the widget extension can read the trend + sleep-stage data the app
//  computed. Mirrors WorkoutSnapshotStore.
//

import Foundation
import os

enum HealthWidgetSnapshotStore {
    static let appGroupIdentifier = WorkoutSnapshotStore.appGroupIdentifier
    static let snapshotFileName = "healthWidgetSnapshot.json"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "HealthWidgetSnapshotStore")

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
        sharedContainerURL?.appendingPathComponent(snapshotFileName)
    }

    /// Saves the snapshot. Returns `true` when the on-disk bytes changed (so the
    /// caller can decide whether a widget timeline reload is warranted).
    @discardableResult
    static func save(_ snapshot: HealthWidgetSnapshot, fileURL: URL? = snapshotFileURL) -> Bool {
        guard let fileURL else {
            logger.error("Health widget snapshot save skipped because shared file URL is unavailable.")
            return false
        }

        let data: Data
        do {
            // `.sortedKeys` keeps the encoded bytes deterministic so the
            // save-if-changed compare below actually gates widget reloads;
            // `JSONEncoder` randomizes key order between calls otherwise.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(snapshot)
        } catch {
            logger.error("Health widget snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        if let existing = try? Data(contentsOf: fileURL) {
            if existing == data {
                return false
            }
            // A periodic re-save with unchanged content still gets a fresh
            // `generatedDate` from the caller, which would otherwise defeat the
            // byte-compare above on every call. Re-encode the incoming
            // snapshot with the on-disk `generatedDate` substituted in; if
            // that now matches the on-disk bytes, the content is unchanged
            // and the write (and its new timestamp) is skipped.
            if let existingSnapshot = try? JSONDecoder().decode(HealthWidgetSnapshot.self, from: existing) {
                var restampedSnapshot = snapshot
                restampedSnapshot.generatedDate = existingSnapshot.generatedDate
                let restampedEncoder = JSONEncoder()
                restampedEncoder.outputFormatting = [.sortedKeys]
                if let restamped = try? restampedEncoder.encode(restampedSnapshot), restamped == existing {
                    return false
                }
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            logger.error("Health widget snapshot file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Memoizes decoded snapshots keyed by file identity (mtime + size) so the
    /// widget extension's repeated timeline passes don't re-read and re-decode
    /// the same App-Group JSON. Lock-protected because widget providers may call
    /// `load` concurrently (project is Swift 5 language mode, no strict
    /// concurrency). Every `load` re-stats the file, so a cross-process rewrite
    /// (atomic write → new mtime) invalidates the entry.
    private final class LoadCache {
        private let lock = NSLock()
        private var entries: [URL: (modificationDate: Date, fileSize: Int, snapshot: HealthWidgetSnapshot)] = [:]

        func snapshot(for url: URL, modificationDate: Date, fileSize: Int) -> HealthWidgetSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[url],
                  entry.modificationDate == modificationDate,
                  entry.fileSize == fileSize else {
                return nil
            }
            return entry.snapshot
        }

        func store(_ snapshot: HealthWidgetSnapshot, for url: URL, modificationDate: Date, fileSize: Int) {
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

    static func load(fileURL: URL? = snapshotFileURL) -> HealthWidgetSnapshot? {
        guard let fileURL else {
            logger.error("Health widget snapshot load skipped because shared file URL is unavailable.")
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
            logger.error("Health widget snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            loadCache.remove(fileURL)
            return nil
        }

        do {
            let snapshot = try JSONDecoder().decode(HealthWidgetSnapshot.self, from: data)
            if let modificationDate, let fileSize {
                loadCache.store(snapshot, for: fileURL, modificationDate: modificationDate, fileSize: fileSize)
            }
            return snapshot
        } catch {
            logger.error("Health widget snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            loadCache.remove(fileURL)
            return nil
        }
    }

    static func loadOrPlaceholder(fileURL: URL? = snapshotFileURL) -> HealthWidgetSnapshot {
        load(fileURL: fileURL) ?? .placeholder
    }

    static func exists(fileURL: URL? = snapshotFileURL) -> Bool {
        guard let fileURL else {
            return false
        }

        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func fileSize(at fileURL: URL? = snapshotFileURL) -> Int64 {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    static var totalDiskSizeBytes: Int64 {
        fileSize(at: snapshotFileURL)
    }

    static func delete(fileURL: URL? = snapshotFileURL) {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Health widget snapshot file delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
