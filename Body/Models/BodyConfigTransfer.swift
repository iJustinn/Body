//
//  BodyConfigTransfer.swift
//  Body
//

import Foundation

/// Settings › Data › Config: the user's settings, metric sources and custom
/// sources as one JSON file, so a setup moves to another iPhone or survives a
/// reinstall. Values are copied verbatim from defaults over a fixed allowlist,
/// so the JSON-in-string keys (sources, custom sources, thresholds) stay exactly
/// what the app reads. The profile, Health categories, purchases, onboarding
/// stamps, migration flags and every cache stay behind.
enum BodyConfigTransfer {
    static let format = "body.config"
    static let schemaVersion = 1

    enum ValueType {
        case bool, int, double, string
    }

    struct Entry {
        let key: String
        let type: ValueType
        /// Workout colors live in the App Group suite the widgets read.
        var inAppGroup = false
    }

    static let entries: [Entry] = [
        // Appearance and units
        Entry(key: BodyAppearancePreference.selectedThemeKey, type: .string),
        Entry(key: BodyAppearancePreference.followsSystemUnitsKey, type: .bool),
        Entry(key: BodyAppearancePreference.selectedWeightUnitKey, type: .string),
        Entry(key: BodyAppearancePreference.selectedDistanceUnitKey, type: .string),
        Entry(key: BodyAppearancePreference.selectedEnergyUnitKey, type: .string),
        Entry(key: BodyAppearancePreference.selectedTemperatureUnitKey, type: .string),
        Entry(key: BodyAppearancePreference.navigationBarShowsLabelsKey, type: .bool),
        // Sleep
        Entry(key: BodyAppearancePreference.sleepDurationGoalMinutesKey, type: .int),
        Entry(key: BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey, type: .bool),
        Entry(key: BodyAppearancePreference.showsLeadingTrailingAwakeSleepStagesKey, type: .bool),
        Entry(key: BodyAppearancePreference.showSleepScoreKey, type: .bool),
        Entry(key: BodyAppearancePreference.showSleepDebtKey, type: .bool),
        Entry(key: BodyAppearancePreference.sleepStageBreakdownShowsOptimalRangesKey, type: .bool),
        Entry(key: BodyAppearancePreference.stressDayBreakdownShowsBarKey, type: .bool),
        // Home
        Entry(key: BodyAppearancePreference.homeCardOrderKey, type: .string),
        Entry(key: BodyAppearancePreference.summaryCardSelectionKey, type: .string),
        Entry(key: BodyAppearancePreference.homeTrendCardSelectionKey, type: .string),
        Entry(key: BodyAppearancePreference.starredMetricKey, type: .string),
        Entry(key: BodyAppearancePreference.defaultTrendRangeKey, type: .string),
        Entry(key: BodyAppearancePreference.metricDayViewSelectionKey, type: .string),
        Entry(key: BodyAppearancePreference.hrvDetailDisplayKindKey, type: .string),
        Entry(key: BodyAppearancePreference.readinessHeroShowsLevelKey, type: .bool),
        Entry(key: BodyAppearancePreference.dayRingShowsCaptionKey, type: .bool),
        Entry(key: BodyAppearancePreference.showReadinessAICommentKey, type: .bool),
        // Home background
        Entry(key: BodyAppearancePreference.homeBackgroundEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.homeBackgroundColorsKey, type: .string),
        Entry(key: BodyAppearancePreference.homeBackgroundSeparatorsKey, type: .string),
        Entry(key: BodyAppearancePreference.homeBackgroundProfilesKey, type: .string),
        // Workout colors
        Entry(key: BodyAppearancePreference.workoutColorOverridesKey, type: .string, inAppGroup: true),
        // Warnings
        Entry(key: BodyAppearancePreference.metricWarningsKey, type: .string),
        Entry(key: BodyAppearancePreference.metricWarningThresholdsKey, type: .string),
        Entry(key: BodyAppearancePreference.metricWarningsOnReadinessHeroKey, type: .bool),
        // Workouts
        Entry(key: BodyAppearancePreference.workoutEffortCardEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.showWorkoutEffortSuggestionsKey, type: .bool),
        Entry(key: BodyAppearancePreference.autoApplyWorkoutEffortKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutsChartSwipeSwitchesMonthKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutsMonthPickerUsesShortMonthKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutsChartShowsTypeBreakdownKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutRouteStyleKey, type: .string),
        Entry(key: BodyAppearancePreference.drawsWorkoutRouteOnLoadKey, type: .bool),
        // Equivalents
        Entry(key: BodyAppearancePreference.workoutEquivalentCardEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutEquivalentHiddenFoodsKey, type: .string),
        Entry(key: BodyAppearancePreference.workoutEquivalentPrefersMoreItemsKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutEquivalentUsesTotalEnergyKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutEquivalentEmojiScaleKey, type: .double),
        // Haptics
        Entry(key: BodyAppearancePreference.allHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.workoutEquivalentHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.chartScrubHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.cardTapHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.trendRangeHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.monthPickerHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.confirmationHapticsEnabledKey, type: .bool),
        Entry(key: BodyAppearancePreference.selectionHapticsEnabledKey, type: .bool),
        // Notifications
        Entry(key: BodyNotificationPreferences.masterKey, type: .bool),
        Entry(key: BodyNotificationPreferences.stressKey, type: .bool),
        Entry(key: BodyNotificationPreferences.sleepKey, type: .bool),
        Entry(key: BodyNotificationPreferences.readinessKey, type: .bool),
        Entry(key: BodyNotificationPreferences.workoutKey, type: .bool),
        Entry(key: BodyAppearancePreference.metricWarningNotificationsKey, type: .bool),
        // Sources
        Entry(key: BodyAppearancePreference.healthDataSourceSelectionKey, type: .string),
        Entry(key: BodyAppearancePreference.secondaryHealthDataSourceSelectionKey, type: .string),
        Entry(key: BodyAppearancePreference.combinesHealthDataSourcesByNameKey, type: .bool),
        Entry(key: BodyAppearancePreference.customHealthSourceGroupsKey, type: .string)
    ]

    static let notificationKeys: Set<String> = [
        BodyNotificationPreferences.masterKey,
        BodyNotificationPreferences.stressKey,
        BodyNotificationPreferences.sleepKey,
        BodyNotificationPreferences.readinessKey,
        BodyNotificationPreferences.workoutKey,
        BodyAppearancePreference.metricWarningNotificationsKey
    ]

    /// The one-time card migrations re-add cards a stored layout predates. An
    /// imported layout is a deliberate choice, so they are marked done.
    static let cardMigrationKeys = [
        BodyAppearancePreference.summaryCardCardioFitnessMigratedKey,
        BodyAppearancePreference.summaryCardStressMigratedKey,
        BodyAppearancePreference.summaryCardBodyRadarMigratedKey,
        BodyAppearancePreference.homeTrendCardCardioFitnessMigratedKey,
        BodyAppearancePreference.homeTrendCardStressMigratedKey
    ]

    enum Value: Codable, Equatable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            }
        }

        /// The defaults object for `type`, or nil when the value has another
        /// type. A whole number stands in for a double, since JSON writes 1.0 as 1.
        func object(as type: ValueType) -> Any? {
            switch (type, self) {
            case (.bool, .bool(let value)): return value
            case (.int, .int(let value)): return value
            case (.double, .double(let value)): return value
            case (.double, .int(let value)): return Double(value)
            case (.string, .string(let value)): return value
            default: return nil
            }
        }
    }

    struct File: Codable, Equatable {
        var format: String
        var schemaVersion: Int
        var exportedAt: Date
        var appVersion: String?
        var build: String?
        var settings: [String: Value]
    }

    enum ImportError: Error, Equatable {
        case notAConfig
        case newerSchema
        case mismatchedValue(String)
    }

    static func export(
        defaults: UserDefaults = .standard,
        groupDefaults: UserDefaults? = BodyWorkoutColorStore.sharedDefaults,
        now: Date = Date(),
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        build: String? = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    ) throws -> Data {
        var settings: [String: Value] = [:]
        for entry in entries {
            // Unset keys stay out, so they import as the default.
            guard let store = entry.inAppGroup ? groupDefaults : defaults,
                  store.object(forKey: entry.key) != nil else { continue }
            switch entry.type {
            case .bool: settings[entry.key] = .bool(store.bool(forKey: entry.key))
            case .int: settings[entry.key] = .int(store.integer(forKey: entry.key))
            case .double: settings[entry.key] = .double(store.double(forKey: entry.key))
            case .string:
                if let value = store.string(forKey: entry.key) { settings[entry.key] = .string(value) }
            }
        }
        let file = File(
            format: format, schemaVersion: schemaVersion, exportedAt: now,
            appVersion: appVersion, build: build, settings: settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Decodes and validates a config file. Nothing is written until the whole
    /// file passes: the format, a schema this build understands, and every
    /// allowlisted value in its declared type.
    static func decode(_ data: Data) throws -> File {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(File.self, from: data), file.format == format else {
            throw ImportError.notAConfig
        }
        guard file.schemaVersion <= schemaVersion else {
            throw ImportError.newerSchema
        }
        for entry in entries {
            if let value = file.settings[entry.key], value.object(as: entry.type) == nil {
                throw ImportError.mismatchedValue(entry.key)
            }
        }
        return file
    }

    /// Makes the allowlisted keys an exact copy of the file: present keys are
    /// written, missing ones removed so they fall back to the default, unknown
    /// ones ignored. Returns the keys whose stored value changed.
    @discardableResult
    static func write(
        _ file: File,
        defaults: UserDefaults = .standard,
        groupDefaults: UserDefaults? = BodyWorkoutColorStore.sharedDefaults
    ) -> Set<String> {
        var changed: Set<String> = []
        for entry in entries {
            guard let store = entry.inAppGroup ? groupDefaults : defaults else { continue }
            let previous = store.object(forKey: entry.key) as? NSObject
            if let object = file.settings[entry.key]?.object(as: entry.type) {
                store.set(object, forKey: entry.key)
            } else {
                store.removeObject(forKey: entry.key)
            }
            if previous != store.object(forKey: entry.key) as? NSObject {
                changed.insert(entry.key)
            }
        }
        for key in cardMigrationKeys {
            defaults.set(true, forKey: key)
        }
        return changed
    }

    /// Writes the file, then runs what the Settings controls would have run for
    /// each change, so the store, the watch, the widgets and notifications
    /// follow without a relaunch.
    @MainActor
    static func apply(_ file: File, to store: HealthKitWorkoutStore) async {
        let changed = write(file)
        await store.reloadHealthSourceConfiguration()
        if changed.contains(BodyAppearancePreference.sleepDurationGoalMinutesKey) {
            store.sleepGoalDidChange()
        }
        store.republishCompanionSnapshots()
        BodyWidgetReloadCoalescer.shared.requestReload()

        guard !changed.isDisjoint(with: notificationKeys) else { return }
        BodyNotificationPreferences.changed(key: BodyNotificationPreferences.masterKey)
        store.healthChangeCoordinator?.contextDidChange()
        if notificationKeys.contains(where: {
            $0 != BodyNotificationPreferences.masterKey && BodyNotificationPreferences.enabled($0)
        }) {
            await BodyNotificationPermission.shared.request()
        }
    }
}
