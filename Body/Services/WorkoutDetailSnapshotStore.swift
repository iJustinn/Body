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

    /// Drops cached details for workouts that are no longer in the user's
    /// history, plus any file whose name isn't a workout UUID at all.
    static func prune(keeping: Set<UUID>, directoryURL: URL? = defaultDirectoryURL) {
        for fileURL in jsonFileURLs(in: directoryURL) {
            let id = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent)
            if let id, keeping.contains(id) { continue }
            remove(fileURL)
        }
    }

    static func stripMetricSeries(directoryURL: URL? = defaultDirectoryURL) {
        strip(directoryURL: directoryURL) { snapshot in
            guard snapshot.metricSeries != nil else { return nil }
            var stripped = snapshot
            stripped.metricSeries = nil
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
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            logger.error("Workout detail write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Excluded from backup on creation: the contents are rebuildable from
    /// HealthKit, and GPS traces shouldn't ride along into iCloud backups.
    private static func createDirectoryIfNeeded(_ directoryURL: URL) throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) { return }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var url = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func remove(_ fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Workout detail delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
