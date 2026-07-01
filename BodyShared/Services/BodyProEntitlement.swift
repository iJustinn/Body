//
//  BodyProEntitlement.swift
//  Body
//

import Foundation

/// Shared, synchronous source of truth for whether Body Pro is unlocked.
///
/// `BodyProStore` (the StoreKit owner in the app) writes this cache whenever the
/// entitlement changes. Everything that needs the flag *synchronously* and outside
/// SwiftUI — the widget timeline providers and the plain `HealthKitWorkoutStore` —
/// reads it from here. It is backed by the App Group suite so the widget process sees
/// the same value the app wrote, and falls back to locked when the suite is unavailable.
enum BodyProEntitlement {
    /// Posted (on the calling thread) only when `setUnlocked` actually changes the value.
    static let didChangeNotification = Notification.Name("BodyProEntitlementDidChange")

    private static let unlockedKey = "bodyProUnlocked"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier)
    }

    /// Whether Body Pro is currently unlocked. Falls back to `false` (locked) when the
    /// App Group suite can't be reached, mirroring the guarded-container pattern the
    /// other shared stores use.
    static var isUnlocked: Bool {
        sharedDefaults?.bool(forKey: unlockedKey) ?? false
    }

    /// Writes the cached flag. The single site that posts `didChangeNotification`, and
    /// only when the value actually changes, so repeated entitlement refreshes don't
    /// fan out redundant notifications.
    static func setUnlocked(_ unlocked: Bool) {
        guard let defaults = sharedDefaults, defaults.bool(forKey: unlockedKey) != unlocked else {
            return
        }

        defaults.set(unlocked, forKey: unlockedKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
