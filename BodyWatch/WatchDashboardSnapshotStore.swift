//
//  WatchDashboardSnapshotStore.swift
//  BodyWatch
//
//  Caches the watch's own assembled `HealthDashboardSnapshot` in the watch App
//  Group so a relaunch / background wake can start from the last computed state.
//  Watch-only: the iPhone keeps its own dashboard cache, and per-device App
//  Groups don't sync across the phone/watch boundary.
//

import Foundation
import os

enum WatchDashboardSnapshotStore {
    static let appGroupIdentifier = "group.com.zihengthedeveloper.Body"
    private static let fileName = "watchDashboardSnapshot.json"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchDashboardStore")

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(fileName)
    }

    static func load() -> HealthDashboardSnapshot? {
        guard let fileURL else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return nil
        } catch {
            logger.error("Dashboard cache read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HealthDashboardSnapshot.self, from: data)
        } catch {
            logger.error("Dashboard cache decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func save(_ snapshot: HealthDashboardSnapshot) {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Dashboard cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
