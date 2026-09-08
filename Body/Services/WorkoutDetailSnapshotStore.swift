//
//  WorkoutDetailSnapshotStore.swift
//  Body
//
//  One JSON file per workout under app-private Application Support, keyed by the
//  workout's UUID. App-private rather than the App Group container because GPS
//  traces are sensitive and no extension needs them.
//
//  Not thread-safe by design: callers serialize every mutation on the app's
//  persist queue, so the store carries no lock of its own.
//

import Foundation
import os

enum WorkoutDetailSnapshotStore {
    private static let directoryName = "WorkoutDetails"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutDetailSnapshotStore")

    static var defaultDirectoryURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Workout detail snapshot directory unavailable.")
            return nil
        }

        return applicationSupportURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    @discardableResult
    static func save(_ snapshot: WorkoutDetailSnapshot, directoryURL: URL? = defaultDirectoryURL) -> Bool {
        guard let directoryURL else {
            return false
        }

        let data: Data
        do {
            // `.sortedKeys` keeps the encoded bytes deterministic so the
            // byte-compare below actually dedupes writes; `JSONEncoder`
            // randomizes key order between calls otherwise.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(snapshot)
        } catch {
            logger.error("Workout detail encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let fileURL = fileURL(for: snapshot.workoutID, in: directoryURL)
        if let existing = try? Data(contentsOf: fileURL), existing == data {
            return false
        }

        return write(data, to: fileURL, in: directoryURL)
    }

    static func load(workoutID: UUID, directoryURL: URL? = defaultDirectoryURL) -> WorkoutDetailSnapshot? {
        guard let directoryURL,
              let snapshot = loadFile(at: fileURL(for: workoutID, in: directoryURL)) else {
            return nil
        }
        return snapshot
    }

    /// Drops one workout's stored details. Used when a live read confirms Apple
    /// Health no longer returns a detail the file claims, so the stale positive
    /// doesn't seed again on the next launch. A missing file is a no-op.
    static func delete(workoutID: UUID, directoryURL: URL? = defaultDirectoryURL) {
        guard let directoryURL else {
            return
        }
        let fileURL = fileURL(for: workoutID, in: directoryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }
        remove(fileURL)
    }

    /// Journal invalidation needs a durable receipt, unlike best-effort eviction.
    static func invalidateForJournal(ids: Set<UUID>?, directoryURL: URL? = defaultDirectoryURL) -> Bool {
        guard let directoryURL else { return false }
        do {
            if let ids {
                for id in ids {
                    let file = fileURL(for: id, in: directoryURL)
                    if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                }
            } else if FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.removeItem(at: directoryURL)
            }
            return true
        } catch { return false }
    }

    /// Drops cached details for workouts that are no longer in the user's
    /// history, plus any file whose name isn't a workout UUID at all. Among the
    /// remaining files (not in `keeping`), only the `retainingRecentLimit` most
    /// recently PERSISTED are kept, going by file modification time rather than
    /// access time — snapshots are written once and complete, so persist-recency
    /// is an honest retention key here, not a stand-in for LRU. This bounds
    /// on-disk growth now that `isWorkoutDetailPersistable` no longer restricts
    /// persistence to the current/previous month.
    static func prune(keeping: Set<UUID>, retainingRecentLimit: Int = 200, directoryURL: URL? = defaultDirectoryURL) {
        var keptOthers: [(url: URL, modified: Date)] = []
        for fileURL in jsonFileURLs(in: directoryURL) {
            guard let id = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) else {
                remove(fileURL)
                continue
            }
            if keeping.contains(id) { continue }

            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            keptOthers.append((fileURL, modified))
        }

        guard keptOthers.count > retainingRecentLimit else { return }

        keptOthers.sort { $0.modified > $1.modified }
        for entry in keptOthers[retainingRecentLimit...] {
            remove(entry.url)
        }
    }

    /// Drops both workout-metric payloads together. Splits are dropped whole
    /// rather than sample-by-sample: a partially stripped payload still satisfies
    /// the session cache after the user re-enables permissions, so cadence would
    /// never refetch. With the whole payload gone, a re-enable simply reloads live
    /// and re-persists a complete one.
    static func stripWorkoutMetricsPayloads(directoryURL: URL? = defaultDirectoryURL) {
        strip(directoryURL: directoryURL) { snapshot in
            guard snapshot.metricSeries != nil || snapshot.splitData != nil else { return nil }
            var stripped = snapshot
            stripped.metricSeries = nil
            stripped.splitData = nil
            return stripped
        }
    }

    static func stripHeartRateRecovery(directoryURL: URL? = defaultDirectoryURL) {
        strip(directoryURL: directoryURL) { snapshot in
            guard snapshot.heartRateRecoveryBPM != nil else { return nil }
            var stripped = snapshot
            stripped.heartRateRecoveryBPM = nil
            return stripped
        }
    }

    static func deleteAll(directoryURL: URL? = defaultDirectoryURL) {
        guard let directoryURL, FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch {
            logger.error("Workout detail directory delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func totalDiskSizeBytes(directoryURL: URL? = defaultDirectoryURL) -> Int64 {
        guard let directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: [.fileSizeKey]
              ) else {
            return 0
        }

        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }

    private static func fileURL(for workoutID: UUID, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("\(workoutID.uuidString).json")
    }

    private static func jsonFileURLs(in directoryURL: URL?) -> [URL] {
        guard let directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directoryURL,
                  includingPropertiesForKeys: nil
              ) else {
            return []
        }
        return contents.filter { $0.pathExtension == "json" }
    }

    private static func loadFile(at fileURL: URL) -> WorkoutDetailSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Workout detail read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(WorkoutDetailSnapshot.self, from: data),
              snapshot.schemaVersion == WorkoutDetailSnapshot.currentSchemaVersion else {
            // Corrupt or stale-schema file: remove it so it doesn't linger as
            // dead weight and get re-attempted (and re-fail) on every load.
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return snapshot
    }

    /// Rewrites every stored file through `transform`, which returns nil when
    /// the file needs no change. A file left with no payloads is deleted rather
    /// than kept as an empty shell.
    private static func strip(
        directoryURL: URL?,
        transform: (WorkoutDetailSnapshot) -> WorkoutDetailSnapshot?
    ) {
        guard let directoryURL else { return }

        for fileURL in jsonFileURLs(in: directoryURL) {
            guard let snapshot = loadFile(at: fileURL),
                  let stripped = transform(snapshot) else {
                continue
            }

            if stripped.isEmpty {
                remove(fileURL)
                continue
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(stripped) else { continue }
            write(data, to: fileURL, in: directoryURL)
        }
    }

    @discardableResult
    private static func write(_ data: Data, to fileURL: URL, in directoryURL: URL) -> Bool {
        do {
            try createDirectoryIfNeeded(directoryURL)
            // Complete-until-first-unlock protection: a background refresh can
            // read this file while the device is locked, so
            // `.completeUnlessOpen` would break that read.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            logger.error("Workout detail write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Excluded from backup, retroactively on older builds' directories too:
    /// the contents are rebuildable from HealthKit, and GPS traces shouldn't
    /// ride along into iCloud backups.
    private static func createDirectoryIfNeeded(_ directoryURL: URL) throws {
        try BodySnapshotDirectory.prepare(directoryURL)
    }

    private static func remove(_ fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Workout detail delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
