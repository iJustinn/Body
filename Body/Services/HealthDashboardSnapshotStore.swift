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
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "HealthDashboardSnapshotStore")

    static func saveSecondarySelectionSignature(_ signature: String, defaults: UserDefaults = .standard) {
        defaults.set(signature, forKey: secondarySelectionSignatureKey)
    }

    static func loadSecondarySelectionSignature(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: secondarySelectionSignatureKey)
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

    static func save(
        _ snapshot: HealthDashboardSnapshot,
        defaults: UserDefaults = .standard,
        fileURL: URL? = snapshotFileURL
    ) {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Health dashboard snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let fileURL else {
            logger.error("Health dashboard snapshot file save skipped because file URL is unavailable.")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            defaults.removeObject(forKey: healthDashboardSnapshotKey)
        } catch {
            logger.error("Health dashboard snapshot file write failed: \(error.localizedDescription, privacy: .public)")
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
