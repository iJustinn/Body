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

    static func load(fileURL: URL?) -> WatchMetricsSnapshot? {
        guard let fileURL else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return WatchMetricsSnapshot.decoded(from: data)
    }
}
