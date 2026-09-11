import Foundation
import UserNotifications

/// App-local choices are independent of the system's authorization status.
enum BodyNotificationPreferences {
    static let masterKey = "notifications.enabled"
    static let stressKey = "notifications.stress"
    static let sleepKey = "notifications.sleep"
    static let workoutKey = "notifications.workouts"
    static let migrationKey = "notifications.migrated.v1"
    static let enabledSinceKey = "notifications.enabledSince"
    static let revisionKey = "notifications.revision"
    static let automaticPromptKey = "notifications.automaticPrompt"
    static let onboardingPromptKey = "notifications.onboardingPrompt"

    static func migrate(defaults: UserDefaults = .standard, now: Date = Date()) {
        // Independent addition: installations that already migrated v1 also
        // receive the new category, without overwriting an explicit opt-out.
        if defaults.object(forKey: sleepKey) == nil {
            defaults.set(true, forKey: sleepKey)
            defaults.set(now, forKey: sleepKey + ".since")
        }
        guard !defaults.bool(forKey: migrationKey) else { return }
        let existing = !(defaults.string(forKey: BodyAppearancePreference.onboardingCompletedVersionKey) ?? "").isEmpty
        let warning = BodyAppearancePreference.metricWarningNotificationsKey
        if defaults.object(forKey: warning) == nil { defaults.set(!existing, forKey: warning) }
        for key in [masterKey, stressKey, workoutKey] where defaults.object(forKey: key) == nil {
            defaults.set(true, forKey: key)
        }
        defaults.set(now, forKey: enabledSinceKey)
        defaults.set(!existing, forKey: onboardingPromptKey)
        defaults.set(existing, forKey: automaticPromptKey)
        defaults.set(true, forKey: migrationKey)
    }

    static func enabled(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: masterKey) as? Bool ?? true) && defaults.bool(forKey: key)
    }

    static func since(_ key: String, defaults: UserDefaults = .standard, now: Date = Date()) -> Date {
        defaults.object(forKey: key + ".since") as? Date
            ?? defaults.object(forKey: enabledSinceKey) as? Date ?? now
    }

    static func changed(key: String, defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(UUID().uuidString, forKey: revisionKey)
        if key == masterKey || key == stressKey { defaults.set(now, forKey: stressKey + ".since") }
        if key == masterKey || key == sleepKey { defaults.set(now, forKey: sleepKey + ".since") }
        if key == masterKey || key == workoutKey { defaults.set(now, forKey: workoutKey + ".since") }
        if enabled(BodyAppearancePreference.metricWarningNotificationsKey, defaults: defaults) {
            BodyBackgroundRefreshScheduler.schedule()
        } else {
            BodyBackgroundRefreshScheduler.cancelPending()
        }
    }
}

@MainActor
final class BodyNotificationPermission {
    static let shared = BodyNotificationPermission()
    private var requesting = false

    func request() async {
        guard !requesting, BodyAppRuntime.isForegroundActive else { return }
        requesting = true
        defer { requesting = false }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined,
              BodyAppRuntime.isForegroundActive else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        BodyBackgroundRefreshScheduler.schedule()
    }
}
