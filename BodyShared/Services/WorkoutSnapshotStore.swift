//
//  WorkoutSnapshotStore.swift
//  Body
//

import Foundation
import os

enum WorkoutSnapshotStore {
    static let appGroupIdentifier = "group.com.zihengthedeveloper.Body"
    static let currentMonthSnapshotFileName = "currentMonthWorkoutSnapshot.json"
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

    static func save(_ snapshot: WorkoutMonthSnapshot) {
        save(snapshot, fileURL: snapshotFileURL)
    }

    static func save(_ snapshot: WorkoutMonthSnapshot, fileURL: URL?) {
        guard let fileURL else {
            logger.error("Snapshot save skipped because shared snapshot file URL is unavailable.")
            return
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            logger.error("Snapshot file write failed: \(error.localizedDescription, privacy: .public)")
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

    static func seedPreviewSnapshotIfNeeded() {
        guard load() == nil else { return }
        save(.placeholder)
    }
}
