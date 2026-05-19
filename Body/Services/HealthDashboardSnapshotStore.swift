//
//  HealthDashboardSnapshotStore.swift
//  Body
//

import Foundation
import os

enum HealthDashboardSnapshotStore {
    static let healthDashboardSnapshotKey = "lastHealthDashboardSnapshot"
    static let healthDashboardSnapshotFileName = "lastHealthDashboardSnapshot.json"
    static let secondarySelectionSignatureKey = "lastHealthDashboardSecondarySelectionSignature"
    static let lastSuccessfulRefreshDateKey = "lastHealthDashboardSuccessfulRefreshDate"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "HealthDashboardSnapshotStore")

    static func saveSecondarySelectionSignature(_ signature: String, defaults: UserDefaults = .standard) {
        defaults.set(signature, forKey: secondarySelectionSignatureKey)
    }

    static func loadSecondarySelectionSignature(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: secondarySelectionSignatureKey)
    }

    /// Persisted timestamp of the last successful HealthKit refresh. Loaded at
    /// launch so the cold-start sync path can route through the same tiered
    /// TTL as a warm scene-phase resume: < 60 s → skip, < 5 min → current-month
    /// only, ≥ 5 min → full refresh. Without persistence, every cold start
    /// looked like "never refreshed before" and always paid the full refresh
    /// cost even when the on-disk snapshot was seconds old.
    static func saveLastSuccessfulRefreshDate(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastSuccessfulRefreshDateKey)
    }

    static func loadLastSuccessfulRefreshDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastSuccessfulRefreshDateKey) as? Date
    }

    static func clearLastSuccessfulRefreshDate(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastSuccessfulRefreshDateKey)
    }

    static var snapshotFileURL: URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            logger.error("Health dashboard snapshot file URL unavailable.")
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent("HealthDashboardSnapshotStore", isDirectory: true)
            .appendingPathComponent(healthDashboardSnapshotFileName)
    }

    @discardableResult
    static func save(
        _ snapshot: HealthDashboardSnapshot,
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> Bool {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Health dashboard snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        guard let fileURL else {
            logger.error("Health dashboard snapshot file save skipped because file URL is unavailable.")
            return false
        }

        if let existing = try? Data(contentsOf: fileURL), existing == data {
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
            return true
        } catch {
            logger.error("Health dashboard snapshot file write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func load(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> HealthDashboardSnapshot? {
        if let snapshot = loadFromFile(fileURL: fileURL) {
            return snapshot
        }

        guard let legacyData = defaults.data(forKey: healthDashboardSnapshotKey) else {
            return nil
        }

        guard let legacySnapshot = decode(legacyData) else {
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
            return nil
        }

        save(legacySnapshot, defaults: defaults, fileURL: fileURL)
        return legacySnapshot
    }

    static func loadOrEmpty(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) -> HealthDashboardSnapshot {
        load(defaults: defaults, fileURL: fileURL) ?? .empty
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
        fileSize(at: snapshotFileURL)
    }

    static func delete(
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) {
        defaults.removeObject(forKey: healthDashboardSnapshotKey)

        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Health dashboard snapshot file delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadFromFile(fileURL: URL?) -> HealthDashboardSnapshot? {
        guard let fileURL else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("Health dashboard snapshot file read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return decode(data)
    }

    private static func decode(_ data: Data) -> HealthDashboardSnapshot? {
        do {
            return try JSONDecoder().decode(HealthDashboardSnapshot.self, from: data)
        } catch {
            logger.error("Health dashboard snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
