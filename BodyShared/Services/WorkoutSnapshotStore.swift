//
//  WorkoutSnapshotStore.swift
//  Body
//

import Foundation
import os

enum WorkoutSnapshotStore {
    static let appGroupIdentifier = "group.com.zihengthedeveloper.Body"
    static let currentMonthSnapshotKey = "currentMonthWorkoutSnapshot"
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutSnapshotStore")

    static var sharedUserDefaults: UserDefaults? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return nil
        }
        #endif

        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil else {
            logger.error("App group container unavailable for \(appGroupIdentifier, privacy: .public)")
            return nil
        }

        return UserDefaults(suiteName: appGroupIdentifier)
    }

    static func save(_ snapshot: WorkoutMonthSnapshot, defaults: UserDefaults? = sharedUserDefaults) {
        guard let defaults else {
            logger.error("Snapshot save skipped because shared defaults are unavailable.")
            return
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Snapshot encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        defaults.set(data, forKey: currentMonthSnapshotKey)
    }

    static func load(defaults: UserDefaults? = sharedUserDefaults) -> WorkoutMonthSnapshot? {
        guard let defaults else {
            logger.error("Snapshot load skipped because shared defaults are unavailable.")
            return nil
        }

        guard let data = defaults.data(forKey: currentMonthSnapshotKey) else { return nil }

        do {
            return try JSONDecoder().decode(WorkoutMonthSnapshot.self, from: data)
        } catch {
            logger.error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func loadOrPlaceholder(defaults: UserDefaults? = sharedUserDefaults) -> WorkoutMonthSnapshot {
        load(defaults: defaults) ?? .placeholder
    }

    static func seedPreviewSnapshotIfNeeded(defaults: UserDefaults? = sharedUserDefaults) {
        guard load(defaults: defaults) == nil else { return }
        save(.placeholder, defaults: defaults)
    }
}
