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
            logger.error("Health widget snapshot file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func load(fileURL: URL? = snapshotFileURL) -> HealthWidgetSnapshot? {
        guard let fileURL else {
            logger.error("Health widget snapshot load skipped because shared file URL is unavailable.")
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Health widget snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            return try JSONDecoder().decode(HealthWidgetSnapshot.self, from: data)
        } catch {
            logger.error("Health widget snapshot decode failed: \(error.localizedDescription, privacy: .public)")
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
