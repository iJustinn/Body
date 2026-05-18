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
            data = try JSONEncoder().encode(snapshot)
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

    static func load(fileURL: URL?) -> WorkoutMonthSnapshot? {
        guard let fileURL else {
            logger.error("Snapshot load skipped because shared snapshot file URL is unavailable.")
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        do {
            return try JSONDecoder().decode(WorkoutMonthSnapshot.self, from: data)
        } catch {
            logger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func loadOrPlaceholder() -> WorkoutMonthSnapshot {
        load() ?? .placeholder
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

    static func seedPreviewSnapshotIfNeeded() {
        guard load() == nil else { return }
        save(.placeholder)
    }
}
