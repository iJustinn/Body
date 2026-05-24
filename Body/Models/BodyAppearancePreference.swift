//
//  BodyAppearancePreference.swift
//  Body
//

import SwiftUI

enum BodyAppearancePreference {
    static let selectedThemeKey = "selectedTheme"
    static let selectedAccentKey = "selectedAppAccent"
    static let selectedUnitPreferenceKey = "selectedUnitPreference"
    static let followsSystemUnitsKey = "followsSystemUnits"
    static let selectedWeightUnitKey = "selectedWeightUnit"
    static let selectedDistanceUnitKey = "selectedDistanceUnit"
    static let selectedEnergyUnitKey = "selectedEnergyUnit"
    static let selectedTemperatureUnitKey = "selectedTemperatureUnit"
    static let sleepDurationGoalMinutesKey = "sleepDurationGoalMinutes"
    static let showSleepScoreKey = "showSleepScore"
    static let homeCardOrderKey = "homeCardOrder"
    static let summaryCardSelectionKey = "summaryCardSelection"
    static let defaultTrendRangeKey = "defaultTrendRange"
    static let homeTrendCardSelectionKey = "homeTrendCardSelection"
    static let healthPermissionSelectionKey = "healthPermissionSelection"
    static let healthDataSourceSelectionKey = "healthDataSourceSelection"
    static let secondaryHealthDataSourceSelectionKey = "secondaryHealthDataSourceSelection"
    static let combinesHealthDataSourcesByNameKey = "combinesHealthDataSourcesByName"
    static let bodyProIconShowsBackKey = "bodyProIconShowsBack"
    static let creatorSurpriseIconsUnlockedKey = "creatorSurpriseIconsUnlocked"

    static func bodyProIconAssetName(showsBack: Bool) -> String {
        showsBack ? "BodyProIconBack" : "BodyProIcon"
    }
}

enum BodySleepDurationGoal {
    static let minimumMinutes = 4 * 60
    static let maximumMinutes = 12 * 60
    static let stepMinutes = 15
    static let defaultMinutes = 8 * 60
    static let defaultDuration: TimeInterval = 8 * 60 * 60

    static func storedMinutes(from rawValue: Int?) -> Int {
        guard let rawValue else {
            return defaultMinutes
        }

        return min(max(rawValue, minimumMinutes), maximumMinutes)
    }

    static func duration(from minutes: Int) -> TimeInterval {
        TimeInterval(storedMinutes(from: minutes) * 60)
    }

    static func displayText(for minutes: Int) -> String {
        BodyValueFormat.durationText(for: duration(from: minutes))
    }
}

enum SourceComparisonChartKind: Hashable, CaseIterable {
    case bar
    case range
    case rangeBandLine
    case line
    case dayLine
}

extension HealthMetricKind {
    static let sourceSelectableKinds: [HealthMetricKind] = [
        .heartRate,
        .sleep,
        .basics,
        .heartRateVariability,
        .restingHeartRate,
        .respiratoryRate,
        .steps,
        .oxygenSaturation,
        .activeEnergy,
        .restingEnergy,
        .exerciseMinutes,
        .wristTemperature,
        .timeInDaylight
    ]

    var supportsHealthDataSourceSelection: Bool {
        Self.sourceSelectableKinds.contains(self)
    }

    var supportedComparisonCharts: Set<SourceComparisonChartKind> {
        switch self {
        case .recovery:
            return []
        case .sleep:
            return [.line]
        case .heartRate:
            return [.range, .rangeBandLine, .dayLine]
        case .restingHeartRate:
            return [.line, .dayLine]
        case .heartRateVariability:
            return [.range, .rangeBandLine, .dayLine]
        case .oxygenSaturation:
            return [.range, .dayLine]
        case .activeEnergy, .steps:
            return [.bar, .dayLine]
        case .restingEnergy, .exerciseMinutes:
            return [.bar]
        case .basics,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
            return []
        }
    }

    var usesSourceComparisonBarChart: Bool { supportedComparisonCharts.contains(.bar) }
    var usesSourceComparisonRangeChart: Bool { supportedComparisonCharts.contains(.range) }
    var usesSourceComparisonRangeBandLineChart: Bool { supportedComparisonCharts.contains(.rangeBandLine) }
    var usesSourceComparisonLineChart: Bool { supportedComparisonCharts.contains(.line) }
    var usesSourceComparisonDayLineChart: Bool { supportedComparisonCharts.contains(.dayLine) }

    var supportsSecondaryHealthDataSourceSelection: Bool {
        !supportedComparisonCharts.isDisjoint(with: [.bar, .range, .line, .dayLine])
    }

    var sourcePickerTitle: String {
        switch self {
        case .heartRate:
            return "Heart Rate"
        case .sleep:
            return "Sleep"
        case .basics:
            return "Basics"
        case .heartRateVariability:
            return "HRV"
        case .restingHeartRate:
            return "Resting Heart Rate"
        case .respiratoryRate:
            return "Respiratory Rate"
        case .steps:
            return "Steps"
        case .oxygenSaturation:
            return "Blood Oxygen"
        case .activeEnergy:
            return "Active Energy"
        case .restingEnergy:
            return "Resting Energy"
        case .exerciseMinutes:
            return "Exercise Minutes"
        case .wristTemperature:
            return "Wrist Temperature"
        case .timeInDaylight:
            return "Time in Daylight"
        default:
            return "Data"
        }
    }
}

enum BodyHealthPermission: String, CaseIterable, Identifiable {
    case activityRings
    case workouts
    case sleep
    case heart
    case basics
    case bloodOxygen
    case respiratory
    case energy
    case exerciseMinutes
    case wristTemperature
    case timeInDaylight
    case steps

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .activityRings:
            return "Activity Rings"
        case .workouts:
            return "Workouts"
        case .sleep:
            return "Sleep"
        case .heart:
            return "Heart"
        case .basics:
            return "Basics"
        case .bloodOxygen:
            return "Blood Oxygen"
        case .respiratory:
            return "Respiratory"
        case .energy:
            return "Energy"
        case .exerciseMinutes:
            return "Exercise Minutes"
        case .wristTemperature:
            return "Wrist Temperature"
        case .timeInDaylight:
            return "Time in Daylight"
        case .steps:
            return "Steps"
        }
    }

    var subtitle: String {
        switch self {
        case .activityRings:
            return "Move, Exercise, and Stand rings"
        case .workouts:
            return "Workout history, effort, and details"
        case .sleep:
            return "Sleep duration, stages, and score"
        case .heart:
            return "Heart rate and HRV"
        case .basics:
            return "Weight, body fat, and BMI"
        case .bloodOxygen:
            return "Blood oxygen readings"
        case .respiratory:
            return "Breathing rate readings"
        case .energy:
            return "Active and resting calories"
        case .exerciseMinutes:
            return "Exercise minute totals"
        case .wristTemperature:
            return "Sleeping wrist temperature"
        case .timeInDaylight:
            return "Daylight exposure time"
        case .steps:
            return "Step count totals"
        }
    }

    var iconName: String {
        switch self {
        case .activityRings:
            return "circle.circle.fill"
        case .workouts:
            return "figure.strengthtraining.traditional"
        case .sleep:
            return "bed.double.fill"
        case .heart:
            return "heart.fill"
        case .basics:
            return "scalemass.fill"
        case .bloodOxygen:
            return "drop.fill"
        case .respiratory:
            return "lungs.fill"
        case .energy:
            return "bolt.fill"
        case .exerciseMinutes:
            return "figure.run"
        case .wristTemperature:
            return "thermometer.medium"
        case .timeInDaylight:
            return "sun.max.fill"
        case .steps:
            return "figure.walk"
        }
    }

    var tintColor: Color {
        switch self {
        case .activityRings:
            return .pink
        case .workouts:
            return .orange
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .heart:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
        case .basics:
            return .purple
        case .bloodOxygen,
             .respiratory,
             .wristTemperature:
            return Color(red: 0.00, green: 0.75, blue: 0.85)
        case .energy,
             .exerciseMinutes:
            return Color(red: 1.00, green: 0.38, blue: 0.12)
        case .timeInDaylight:
            return .blue
        case .steps:
            return .green
        }
    }
}

struct BodyHealthPermissionSelection: Equatable {
    static let defaultValue = BodyHealthPermissionSelection(
        enabledPermissions: Set(BodyHealthPermission.allCases)
    )
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var enabledPermissions: Set<BodyHealthPermission>

    var rawValue: String {
        guard !enabledPermissions.isEmpty else {
            return "none"
        }

        return BodyHealthPermission.allCases
            .filter { enabledPermissions.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    var enabledCount: Int {
        enabledPermissions.count
    }

    func includes(_ permission: BodyHealthPermission) -> Bool {
        enabledPermissions.contains(permission)
    }

    func setting(_ permission: BodyHealthPermission, isEnabled: Bool) -> BodyHealthPermissionSelection {
        var nextPermissions = enabledPermissions
        if isEnabled {
            nextPermissions.insert(permission)
        } else {
            nextPermissions.remove(permission)
        }

        return BodyHealthPermissionSelection(enabledPermissions: nextPermissions)
    }

    static func storedValue(from rawValue: String) -> BodyHealthPermissionSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodyHealthPermissionSelection(enabledPermissions: [])
        }

        let permissions = Set(trimmedValue.split(separator: ",").compactMap {
            BodyHealthPermission(rawValue: String($0))
        })

        guard !permissions.isEmpty else {
            return defaultValue
        }

        return BodyHealthPermissionSelection(enabledPermissions: permissions)
    }

    static func load(defaults: UserDefaults = .standard) -> BodyHealthPermissionSelection {
        storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.healthPermissionSelectionKey)
                ?? defaultRawValue
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: BodyAppearancePreference.healthPermissionSelectionKey)
    }
}

struct BodyHealthDataSourceOption: Codable, Equatable, Identifiable {
    static let allSources = BodyHealthDataSourceOption(id: "all", name: "Apple Health")
    static let noComparison = BodyHealthDataSourceOption(id: "none", name: "No Comparison")
    private static let combinedSourcePrefix = "combined-name:"

    let id: String
    let name: String

    var isAllSources: Bool {
        id == Self.allSources.id
    }

    var isNoComparison: Bool {
        id == Self.noComparison.id
    }

    var isCombinedSource: Bool {
        id.hasPrefix(Self.combinedSourcePrefix)
    }

    static func normalizedSourceName(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Unknown Source" : trimmedName
        let normalizedName = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if normalizedName == "iwatch x" || normalizedName == "iwatchx" {
            return "iwatchx"
        }

        return normalizedName
    }

    static func combinedSourceDisplayName(for name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Unknown Source" : trimmedName
        return normalizedSourceName(displayName) == "iwatchx" ? "iWatchX" : displayName
    }

    static func individualSourceIdentityKey(bundleIdentifier: String, name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? "Unknown Source" : trimmedName
        let nameKey = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return "bundle=\(bundleIdentifier)|name=\(nameKey)"
    }

    static func individualSourceID(
        bundleIdentifier: String,
        name: String,
        disambiguatesBundleIdentifier: Bool
    ) -> String {
        guard disambiguatesBundleIdentifier else {
            return bundleIdentifier
        }

        return "source:\(individualSourceIdentityKey(bundleIdentifier: bundleIdentifier, name: name))"
    }

    static func combinedSourceID(for name: String) -> String {
        combinedSourcePrefix + normalizedSourceName(name)
    }
}

struct BodyHealthDataSourceSelection: Equatable {
    private struct Storage: Codable {
        var defaultOption: BodyHealthDataSourceOption?
        var selectedOptions: [String: BodyHealthDataSourceOption]?
    }

    static let defaultValue = BodyHealthDataSourceSelection(defaultOption: .allSources, selectedOptions: [:])
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var defaultOption: BodyHealthDataSourceOption
    var selectedOptions: [HealthMetricKind: BodyHealthDataSourceOption]

    init(
        defaultOption: BodyHealthDataSourceOption = .allSources,
        selectedOptions: [HealthMetricKind: BodyHealthDataSourceOption]
    ) {
        self.defaultOption = defaultOption.isNoComparison ? .allSources : defaultOption
        self.selectedOptions = selectedOptions
    }

    var rawValue: String {
        let storage = Dictionary(uniqueKeysWithValues: selectedOptions.map { kind, option in
            (kind.rawValue, option)
        })
        let encodedStorage = Storage(
            defaultOption: defaultOption.isAllSources ? nil : defaultOption,
            selectedOptions: storage.isEmpty ? nil : storage
        )

        guard let data = try? JSONEncoder().encode(encodedStorage),
              let value = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return value
    }

    func option(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        guard kind.supportsHealthDataSourceSelection else {
            return .allSources
        }

        return selectedOptions[kind] ?? defaultOption
    }

    func setting(_ kind: HealthMetricKind, option: BodyHealthDataSourceOption) -> BodyHealthDataSourceSelection {
        guard kind.supportsHealthDataSourceSelection else {
            return self
        }

        var nextOptions = selectedOptions
        nextOptions[kind] = option.isNoComparison ? .allSources : option

        return BodyHealthDataSourceSelection(defaultOption: defaultOption, selectedOptions: nextOptions)
    }

    func settingDefault(option: BodyHealthDataSourceOption) -> BodyHealthDataSourceSelection {
        BodyHealthDataSourceSelection(
            defaultOption: option.isNoComparison ? .allSources : option,
            selectedOptions: selectedOptions
        )
    }

    func clearingOverride(for kind: HealthMetricKind) -> BodyHealthDataSourceSelection {
        var nextOptions = selectedOptions
        nextOptions.removeValue(forKey: kind)
        return BodyHealthDataSourceSelection(defaultOption: defaultOption, selectedOptions: nextOptions)
    }

    static func storedValue(from rawValue: String) -> BodyHealthDataSourceSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let data = trimmedValue.data(using: .utf8) else {
            return defaultValue
        }

        if let storage = try? JSONDecoder().decode(Storage.self, from: data),
           storage.defaultOption != nil || storage.selectedOptions != nil {
            let selectedOptionPairs: [(HealthMetricKind, BodyHealthDataSourceOption)] = (storage.selectedOptions ?? [:]).compactMap { rawKind, option in
                guard let kind = HealthMetricKind(rawValue: rawKind),
                      kind.supportsHealthDataSourceSelection else {
                    return nil
                }

                return (kind, option.isNoComparison ? .allSources : option)
            }
            return BodyHealthDataSourceSelection(
                defaultOption: storage.defaultOption ?? .allSources,
                selectedOptions: Dictionary(uniqueKeysWithValues: selectedOptionPairs)
            )
        }

        guard let legacyStorage = try? JSONDecoder().decode([String: BodyHealthDataSourceOption].self, from: data) else {
            return defaultValue
        }

        let selectedOptionPairs: [(HealthMetricKind, BodyHealthDataSourceOption)] = legacyStorage.compactMap { rawKind, option in
            guard let kind = HealthMetricKind(rawValue: rawKind),
                  kind.supportsHealthDataSourceSelection else {
                return nil
            }

            return (kind, option.isNoComparison ? .allSources : option)
        }
        let selectedOptions = Dictionary(uniqueKeysWithValues: selectedOptionPairs)

        return BodyHealthDataSourceSelection(defaultOption: .allSources, selectedOptions: selectedOptions)
    }

    static func load(defaults: UserDefaults = .standard) -> BodyHealthDataSourceSelection {
        storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.healthDataSourceSelectionKey)
                ?? defaultRawValue
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: BodyAppearancePreference.healthDataSourceSelectionKey)
    }
}

struct BodyHealthSecondaryDataSourceSelection: Equatable {
    private struct Storage: Codable {
        var defaultOption: BodyHealthDataSourceOption?
        var selectedOptions: [String: BodyHealthDataSourceOption]?
    }

    static let defaultValue = BodyHealthSecondaryDataSourceSelection(defaultOption: .noComparison, selectedOptions: [:])
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var defaultOption: BodyHealthDataSourceOption
    var selectedOptions: [HealthMetricKind: BodyHealthDataSourceOption]

    init(
        defaultOption: BodyHealthDataSourceOption = .noComparison,
        selectedOptions: [HealthMetricKind: BodyHealthDataSourceOption]
    ) {
        self.defaultOption = defaultOption.isNoComparison ? .noComparison : defaultOption
        self.selectedOptions = selectedOptions
    }

    var rawValue: String {
        let storage = Dictionary(uniqueKeysWithValues: selectedOptions.map { kind, option in
            (kind.rawValue, option)
        })
        let encodedStorage = Storage(
            defaultOption: defaultOption.isNoComparison ? nil : defaultOption,
            selectedOptions: storage.isEmpty ? nil : storage
        )

        guard let data = try? JSONEncoder().encode(encodedStorage),
              let value = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return value
    }

    func option(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        guard kind.supportsSecondaryHealthDataSourceSelection else {
            return .noComparison
        }

        return selectedOptions[kind] ?? defaultOption
    }

    func setting(_ kind: HealthMetricKind, option: BodyHealthDataSourceOption) -> BodyHealthSecondaryDataSourceSelection {
        guard kind.supportsSecondaryHealthDataSourceSelection else {
            return self
        }

        var nextOptions = selectedOptions
        nextOptions[kind] = option

        return BodyHealthSecondaryDataSourceSelection(defaultOption: defaultOption, selectedOptions: nextOptions)
    }

    func settingDefault(option: BodyHealthDataSourceOption) -> BodyHealthSecondaryDataSourceSelection {
        BodyHealthSecondaryDataSourceSelection(
            defaultOption: option,
            selectedOptions: selectedOptions
        )
    }

    func clearingOverride(for kind: HealthMetricKind) -> BodyHealthSecondaryDataSourceSelection {
        var nextOptions = selectedOptions
        nextOptions.removeValue(forKey: kind)
        return BodyHealthSecondaryDataSourceSelection(defaultOption: defaultOption, selectedOptions: nextOptions)
    }

    var signature: String {
        (["default=\(defaultOption.id)"] + selectedOptions
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value.id)" })
            .joined(separator: "|")
    }

    static func storedValue(from rawValue: String) -> BodyHealthSecondaryDataSourceSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, let data = trimmedValue.data(using: .utf8) else {
            return defaultValue
        }

        if let storage = try? JSONDecoder().decode(Storage.self, from: data),
           storage.defaultOption != nil || storage.selectedOptions != nil {
            let selectedOptionPairs: [(HealthMetricKind, BodyHealthDataSourceOption)] = (storage.selectedOptions ?? [:]).compactMap { rawKind, option in
                guard let kind = HealthMetricKind(rawValue: rawKind),
                      kind.supportsSecondaryHealthDataSourceSelection else {
                    return nil
                }

                return (kind, option)
            }
            return BodyHealthSecondaryDataSourceSelection(
                defaultOption: storage.defaultOption ?? .noComparison,
                selectedOptions: Dictionary(uniqueKeysWithValues: selectedOptionPairs)
            )
        }

        guard let legacyStorage = try? JSONDecoder().decode([String: BodyHealthDataSourceOption].self, from: data) else {
            return defaultValue
        }

        let selectedOptionPairs: [(HealthMetricKind, BodyHealthDataSourceOption)] = legacyStorage.compactMap { rawKind, option in
            guard let kind = HealthMetricKind(rawValue: rawKind),
                  kind.supportsSecondaryHealthDataSourceSelection else {
                return nil
            }

            return (kind, option)
        }
        let selectedOptions = Dictionary(uniqueKeysWithValues: selectedOptionPairs)

        return BodyHealthSecondaryDataSourceSelection(defaultOption: .noComparison, selectedOptions: selectedOptions)
    }

    static func load(defaults: UserDefaults = .standard) -> BodyHealthSecondaryDataSourceSelection {
        storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.secondaryHealthDataSourceSelectionKey)
                ?? defaultRawValue
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: BodyAppearancePreference.secondaryHealthDataSourceSelectionKey)
    }
}

struct BodySummaryCardSelection: Equatable {
    static let defaultValue = BodySummaryCardSelection(selectedCards: Set(BodyHomeCardKind.defaultOrder))
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var selectedCards: Set<BodyHomeCardKind>

    var rawValue: String {
        guard !selectedCards.isEmpty else {
            return "none"
        }

        return BodyHomeCardKind.defaultOrder
            .filter { selectedCards.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    var enabledCount: Int {
        selectedCards.count
    }

    func includes(_ card: BodyHomeCardKind) -> Bool {
        selectedCards.contains(card)
    }

    func setting(_ card: BodyHomeCardKind, isEnabled: Bool) -> BodySummaryCardSelection {
        var nextCards = selectedCards
        if isEnabled {
            nextCards.insert(card)
        } else {
            nextCards.remove(card)
        }

        return BodySummaryCardSelection(selectedCards: nextCards)
    }

    static func storedValue(from rawValue: String) -> BodySummaryCardSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodySummaryCardSelection(selectedCards: [])
        }

        let cards = Set(trimmedValue.split(separator: ",").compactMap {
            BodyHomeCardKind(rawValue: String($0))
        })

        guard !cards.isEmpty else {
            return defaultValue
        }

        return BodySummaryCardSelection(selectedCards: cards)
    }
}

struct BodyHomeTrendCardSelection: Equatable {
    static let defaultValue = BodyHomeTrendCardSelection(selectedCards: Set(BodyHomeTrendCardKind.defaultOrder))
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var selectedCards: Set<BodyHomeTrendCardKind>

    var rawValue: String {
        guard !selectedCards.isEmpty else {
            return "none"
        }

        return BodyHomeTrendCardKind.defaultOrder
            .filter { selectedCards.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    var enabledCount: Int {
        selectedCards.count
    }

    func includes(_ card: BodyHomeTrendCardKind) -> Bool {
        selectedCards.contains(card)
    }

    func includes(_ kind: HealthMetricKind) -> Bool {
        guard let card = BodyHomeTrendCardKind(metricKind: kind) else {
            return false
        }

        return includes(card)
    }

    func setting(_ card: BodyHomeTrendCardKind, isEnabled: Bool) -> BodyHomeTrendCardSelection {
        var nextCards = selectedCards
        if isEnabled {
            nextCards.insert(card)
        } else {
            nextCards.remove(card)
        }

        return BodyHomeTrendCardSelection(selectedCards: nextCards)
    }

    static func storedValue(from rawValue: String) -> BodyHomeTrendCardSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodyHomeTrendCardSelection(selectedCards: [])
        }

        let cards = Set(trimmedValue.split(separator: ",").compactMap {
            BodyHomeTrendCardKind(rawValue: String($0))
        })

        guard !cards.isEmpty else {
            return defaultValue
        }

        return BodyHomeTrendCardSelection(selectedCards: cards)
    }
}

enum BodyHomeTrendCardKind: String, CaseIterable, Identifiable {
    case recovery
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case sleep
    case wristTemperature
    case steps
    case activeEnergy
    case restingEnergy
    case exerciseMinutes
    case trainingLoad
    case timeInDaylight

    static let defaultOrder: [BodyHomeTrendCardKind] = [
        .recovery,
        .heartRate,
        .restingHeartRate,
        .heartRateVariability,
        .respiratoryRate,
        .oxygenSaturation,
        .sleep,
        .wristTemperature,
        .steps,
        .activeEnergy,
        .restingEnergy,
        .exerciseMinutes,
        .trainingLoad,
        .timeInDaylight
    ]

    init?(metricKind: HealthMetricKind) {
        self.init(rawValue: metricKind.rawValue)
    }

    var id: String {
        rawValue
    }

    var metricKind: HealthMetricKind {
        HealthMetricKind(rawValue: rawValue) ?? .heartRate
    }

    var title: String {
        switch self {
        case .recovery:
            return "Recovery"
        case .heartRate:
            return "Heart Rate"
        case .restingHeartRate:
            return "Resting Heart Rate"
        case .heartRateVariability:
            return "HRV"
        case .respiratoryRate:
            return "Respiratory Rate"
        case .oxygenSaturation:
            return "Blood Oxygen"
        case .sleep:
            return "Sleep"
        case .wristTemperature:
            return "Wrist Temperature"
        case .steps:
            return "Steps"
        case .activeEnergy:
            return "Active Energy"
        case .restingEnergy:
            return "Resting Energy"
        case .exerciseMinutes:
            return "Exercise Minutes"
        case .trainingLoad:
            return "Training Load"
        case .timeInDaylight:
            return "Time In Daylight"
        }
    }

    var subtitle: String {
        switch self {
        case .recovery:
            return "Readiness score trend"
        case .heartRate:
            return "Average heart rate trend"
        case .restingHeartRate:
            return "Resting heart trend"
        case .heartRateVariability:
            return "Recovery signal trend"
        case .respiratoryRate:
            return "Breathing rate trend"
        case .oxygenSaturation:
            return "Blood oxygen trend"
        case .sleep:
            return "Sleep duration trend"
        case .wristTemperature:
            return "Sleeping wrist temperature trend"
        case .steps:
            return "Daily step trend"
        case .activeEnergy:
            return "Active calorie trend"
        case .restingEnergy:
            return "Resting calorie trend"
        case .exerciseMinutes:
            return "Exercise minute trend"
        case .trainingLoad:
            return "Workout strain trend"
        case .timeInDaylight:
            return "Outdoor daylight trend"
        }
    }

    var iconName: String {
        switch self {
        case .recovery:
            return "bolt.heart.fill"
        case .heartRate,
             .restingHeartRate:
            return "heart.fill"
        case .heartRateVariability:
            return "waveform.path.ecg"
        case .respiratoryRate:
            return "lungs.fill"
        case .oxygenSaturation:
            return "drop.fill"
        case .sleep:
            return "bed.double.fill"
        case .wristTemperature:
            return "thermometer.medium"
        case .steps:
            return "figure.walk"
        case .activeEnergy:
            return "flame.fill"
        case .restingEnergy:
            return "leaf.fill"
        case .exerciseMinutes:
            return "figure.run"
        case .trainingLoad:
            return "figure.strengthtraining.traditional"
        case .timeInDaylight:
            return "sun.max.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .recovery:
            return Color(red: 0.12, green: 0.68, blue: 0.55)
        case .heartRate,
             .restingHeartRate,
             .heartRateVariability:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
        case .respiratoryRate,
             .oxygenSaturation,
             .wristTemperature:
            return Color(red: 0.00, green: 0.75, blue: 0.85)
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .steps,
             .activeEnergy,
             .exerciseMinutes,
             .trainingLoad:
            return Color(red: 1.00, green: 0.38, blue: 0.12)
        case .restingEnergy:
            return Color(red: 0.14, green: 0.72, blue: 0.42)
        case .timeInDaylight:
            return Color(red: 0.10, green: 0.58, blue: 1.00)
        }
    }
}

enum BodyHomeCardKind: String, CaseIterable, Identifiable {
    case activityRings
    case recovery
    case exerciseMinutes
    case trainingLoad
    case wristTemperature
    case timeInDaylight
    case steps
    case sleep
    case basics
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case oxygenSaturation
    case respiratoryRate
    case activeEnergy
    case restingEnergy

    static let defaultOrder: [BodyHomeCardKind] = [
        .activityRings,
        .sleep,
        .basics,
        .heartRate,
        .heartRateVariability,
        .trainingLoad,
        .recovery,
        .activeEnergy,
        .restingEnergy,
        .wristTemperature,
        .restingHeartRate,
        .oxygenSaturation,
        .respiratoryRate,
        .exerciseMinutes,
        .steps,
        .timeInDaylight
    ]

    static var defaultRawValue: String {
        rawValue(from: defaultOrder)
    }

    var id: String {
        rawValue
    }

    var slotCount: Int {
        switch self {
        case .activityRings:
            return 2
        default:
            return 1
        }
    }

    var healthMetricKind: HealthMetricKind? {
        switch self {
        case .activityRings:
            return nil
        case .recovery:
            return .recovery
        case .exerciseMinutes:
            return .exerciseMinutes
        case .trainingLoad:
            return .trainingLoad
        case .wristTemperature:
            return .wristTemperature
        case .timeInDaylight:
            return .timeInDaylight
        case .steps:
            return .steps
        case .sleep:
            return .sleep
        case .basics:
            return .basics
        case .heartRate:
            return .heartRate
        case .restingHeartRate:
            return .restingHeartRate
        case .heartRateVariability:
            return .heartRateVariability
        case .oxygenSaturation:
            return .oxygenSaturation
        case .respiratoryRate:
            return .respiratoryRate
        case .activeEnergy:
            return .activeEnergy
        case .restingEnergy:
            return .restingEnergy
        }
    }

    var title: String {
        switch self {
        case .activityRings:
            return "Activity Rings"
        case .recovery:
            return "Recovery"
        case .exerciseMinutes:
            return "Exercise Minutes"
        case .trainingLoad:
            return "Training Load"
        case .wristTemperature:
            return "Wrist Temperature"
        case .timeInDaylight:
            return "Time In Daylight"
        case .steps:
            return "Steps"
        case .sleep:
            return "Sleep"
        case .basics:
            return "Basics"
        case .heartRate:
            return "Heart Rate"
        case .restingHeartRate:
            return "Resting Heart Rate"
        case .heartRateVariability:
            return "HRV"
        case .oxygenSaturation:
            return "Blood Oxygen"
        case .respiratoryRate:
            return "Respiratory Rate"
        case .activeEnergy:
            return "Active Energy"
        case .restingEnergy:
            return "Resting Energy"
        }
    }

    var subtitle: String {
        switch self {
        case .activityRings:
            return "Move, Exercise, and Stand progress"
        case .recovery:
            return "Readiness from sleep, strain, and vitals"
        case .exerciseMinutes:
            return "Daily exercise minute total"
        case .trainingLoad:
            return "Workout strain ratio"
        case .wristTemperature:
            return "Sleeping wrist temperature"
        case .timeInDaylight:
            return "Outdoor daylight exposure"
        case .steps:
            return "Step count total"
        case .sleep:
            return "Sleep score and duration"
        case .basics:
            return "Weight, body fat, and BMI"
        case .heartRate:
            return "Daily heart rate"
        case .restingHeartRate:
            return "Resting beats per minute"
        case .heartRateVariability:
            return "Recovery and stress signal"
        case .oxygenSaturation:
            return "Blood oxygen range"
        case .respiratoryRate:
            return "Breathing rate range"
        case .activeEnergy:
            return "Active calories"
        case .restingEnergy:
            return "Resting calories"
        }
    }

    var isBeta: Bool {
        switch self {
        case .recovery:
            return true
        case .activityRings,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps,
             .sleep,
             .basics,
             .heartRate,
             .restingHeartRate,
             .heartRateVariability,
             .oxygenSaturation,
             .respiratoryRate,
             .activeEnergy,
             .restingEnergy:
            return false
        }
    }

    var iconName: String {
        switch self {
        case .activityRings:
            return "circle.circle.fill"
        case .recovery:
            return "bolt.heart.fill"
        case .exerciseMinutes:
            return "figure.run"
        case .trainingLoad:
            return "figure.strengthtraining.traditional"
        case .wristTemperature:
            return "thermometer.medium"
        case .timeInDaylight:
            return "sun.max.fill"
        case .steps:
            return "figure.walk"
        case .sleep:
            return "bed.double.fill"
        case .basics:
            return "person.crop.circle.fill"
        case .heartRate,
             .restingHeartRate:
            return "heart.fill"
        case .heartRateVariability:
            return "waveform.path.ecg"
        case .oxygenSaturation:
            return "drop.fill"
        case .respiratoryRate:
            return "lungs.fill"
        case .activeEnergy:
            return "flame.fill"
        case .restingEnergy:
            return "leaf.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .activityRings:
            return .pink
        case .recovery:
            return Color(red: 0.12, green: 0.68, blue: 0.55)
        case .exerciseMinutes,
             .trainingLoad,
             .steps,
             .activeEnergy:
            return Color(red: 1.00, green: 0.38, blue: 0.12)
        case .wristTemperature,
             .oxygenSaturation,
             .respiratoryRate:
            return Color(red: 0.00, green: 0.75, blue: 0.85)
        case .timeInDaylight:
            return Color(red: 0.10, green: 0.58, blue: 1.00)
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .basics:
            return Color(red: 0.50, green: 0.34, blue: 1.00)
        case .heartRate,
             .restingHeartRate,
             .heartRateVariability:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
        case .restingEnergy:
            return Color(red: 0.14, green: 0.72, blue: 0.42)
        }
    }

    static func storedOrder(from rawValue: String) -> [BodyHomeCardKind] {
        let parsedOrder = rawValue.split(separator: ",").compactMap { rawCard -> BodyHomeCardKind? in
            if rawCard == "workoutDuration" {
                return .wristTemperature
            }

            return BodyHomeCardKind(rawValue: String(rawCard))
        }

        return repairedOrder(parsedOrder)
    }

    static func rawValue(from order: [BodyHomeCardKind]) -> String {
        repairedOrder(order).map(\.rawValue).joined(separator: ",")
    }

    static func reordered(
        _ order: [BodyHomeCardKind],
        moving source: BodyHomeCardKind,
        to destination: BodyHomeCardKind
    ) -> [BodyHomeCardKind] {
        let baseOrder = repairedOrder(order)

        guard source != destination,
              let sourceIndex = baseOrder.firstIndex(of: source),
              let destinationIndex = baseOrder.firstIndex(of: destination) else {
            return baseOrder
        }

        var result = baseOrder
        result.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? min(destinationIndex, result.count) : destinationIndex
        result.insert(source, at: insertionIndex)
        return repairedOrder(result)
    }

    static func layoutRows(
        from order: [BodyHomeCardKind],
        visibleIn selection: BodySummaryCardSelection = .defaultValue
    ) -> [BodyHomeCardLayoutRow] {
        var rows: [BodyHomeCardLayoutRow] = []
        var currentCards: [BodyHomeCardKind] = []
        var currentSlots = 0

        for card in repairedOrder(order) where selection.includes(card) {
            if card.slotCount >= 2 {
                if !currentCards.isEmpty {
                    rows.append(BodyHomeCardLayoutRow(cards: currentCards))
                    currentCards = []
                    currentSlots = 0
                }

                rows.append(BodyHomeCardLayoutRow(cards: [card]))
                continue
            }

            if currentSlots + card.slotCount > 2 {
                rows.append(BodyHomeCardLayoutRow(cards: currentCards))
                currentCards = []
                currentSlots = 0
            }

            currentCards.append(card)
            currentSlots += card.slotCount

            if currentSlots == 2 {
                rows.append(BodyHomeCardLayoutRow(cards: currentCards))
                currentCards = []
                currentSlots = 0
            }
        }

        if !currentCards.isEmpty {
            rows.append(BodyHomeCardLayoutRow(cards: currentCards))
        }

        return rows
    }

    private static func repairedOrder(_ order: [BodyHomeCardKind]) -> [BodyHomeCardKind] {
        var seen = Set<BodyHomeCardKind>()
        var repaired = order.filter { seen.insert($0).inserted }

        for card in defaultOrder where !seen.contains(card) {
            repaired.append(card)
        }

        return repaired
    }
}

struct BodyHomeCardLayoutRow: Equatable, Identifiable {
    let cards: [BodyHomeCardKind]

    var id: String {
        cards.map(\.rawValue).joined(separator: "-")
    }

    var slotCount: Int {
        cards.reduce(0) { $0 + $1.slotCount }
    }
}

enum BodyHealthTrendRange: String, CaseIterable, Identifiable {
    case recentWeek
    case recentMonth
    case recentSixMonths
    case recentYear

    static let defaultValue: BodyHealthTrendRange = .recentWeek
    static let bodyFatWeightLineChartMaximumPointCount = 20

    static var maximumDayCount: Int {
        allCases.map(\.dayCount).max() ?? defaultValue.dayCount
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .recentWeek:
            return "Week"
        case .recentMonth:
            return "Month"
        case .recentSixMonths:
            return "6 Months"
        case .recentYear:
            return "Year"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .recentWeek:
            return "7 days"
        case .recentMonth:
            return "30 days"
        case .recentSixMonths:
            return "6 months"
        case .recentYear:
            return "1 year"
        }
    }

    var iconName: String {
        switch self {
        case .recentWeek:
            return "calendar.day.timeline.leading"
        case .recentMonth:
            return "calendar.badge.clock"
        case .recentSixMonths:
            return "calendar.badge.plus"
        case .recentYear:
            return "calendar"
        }
    }

    var tintColor: Color {
        switch self {
        case .recentWeek:
            return .blue
        case .recentMonth:
            return .green
        case .recentSixMonths:
            return .orange
        case .recentYear:
            return .purple
        }
    }

    var chartTitle: String {
        switch self {
        case .recentWeek:
            return "Last 7 Days"
        case .recentMonth:
            return "Last 30 Days"
        case .recentSixMonths:
            return "Last 6 Months"
        case .recentYear:
            return "Last Year"
        }
    }

    var dayCount: Int {
        switch self {
        case .recentWeek:
            return 7
        case .recentMonth:
            return 30
        case .recentSixMonths:
            return 183
        case .recentYear:
            return 365
        }
    }

    var axisStrideDayCount: Int {
        switch self {
        case .recentWeek:
            return 1
        case .recentMonth:
            return 7
        case .recentSixMonths:
            return 30
        case .recentYear:
            return 60
        }
    }

    var chartAggregationDayCount: Int {
        switch self {
        case .recentWeek,
             .recentMonth:
            return 1
        case .recentSixMonths:
            return 6
        case .recentYear:
            return 12
        }
    }

    var chartCalendarPointCount: Int {
        let fullBucketCount = dayCount / chartAggregationDayCount
        return max(fullBucketCount, 1)
    }

    static let sourceComparisonBucketDoublingFactor = 2
    static let sourceComparisonBarWidthScale: CGFloat = 1.12
    static let sourceComparisonBucketOffsetFraction: Double = 0.16

    var sourceComparisonChartAggregationDayCount: Int {
        switch self {
        case .recentWeek:
            return chartAggregationDayCount
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return chartAggregationDayCount * Self.sourceComparisonBucketDoublingFactor
        }
    }

    var lineChartMaximumPointCount: Int? {
        switch self {
        case .recentWeek:
            return nil
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return 25
        }
    }

    var chartBarWidth: CGFloat {
        switch self {
        case .recentWeek:
            return 32
        case .recentMonth:
            return 7
        case .recentSixMonths,
             .recentYear:
            return 8
        }
    }

    func chartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        switch self {
        case .recentSixMonths,
             .recentYear:
            return availableWidth <= 330 ? 5 : chartBarWidth
        case .recentWeek,
             .recentMonth:
            return chartBarWidth
        }
    }

    func sourceComparisonChartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        let widenedBarWidth = chartBarWidth(forAvailableWidth: availableWidth) * Self.sourceComparisonBarWidthScale
        switch self {
        case .recentWeek:
            return widenedBarWidth / 2
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return widenedBarWidth
        }
    }

    var sourceComparisonChartDateOffset: TimeInterval {
        let secondsPerDay: Double = 24 * 60 * 60
        return Double(sourceComparisonChartAggregationDayCount) * secondsPerDay * Self.sourceComparisonBucketOffsetFraction
    }

    func sourceComparisonRangeChartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        let widenedBarWidth = heartRateRangeChartBarWidth(forAvailableWidth: availableWidth) * Self.sourceComparisonBarWidthScale
        switch self {
        case .recentWeek:
            return widenedBarWidth / 2
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return widenedBarWidth
        }
    }

    func heartRateRangeChartBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        switch self {
        case .recentWeek:
            return 24
        case .recentMonth,
             .recentSixMonths,
             .recentYear:
            return chartBarWidth(forAvailableWidth: availableWidth)
        }
    }

    var showsPointMarks: Bool {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return true
        }
    }

    var usesPreviewLineChartStyle: Bool {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return true
        }
    }

    var usesMetricColorLineStroke: Bool {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return true
        }
    }

    var trendLineWidth: CGFloat {
        3
    }

    var linePointDiameter: CGFloat {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return 8
        }
    }

    var lineCurrentPointDiameter: CGFloat {
        switch self {
        case .recentWeek,
             .recentMonth,
             .recentSixMonths,
             .recentYear:
            return 10
        }
    }

    func axisLabel(for date: Date) -> String {
        switch self {
        case .recentWeek:
            return date.formatted(.dateTime.weekday(.abbreviated))
        case .recentMonth:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .recentSixMonths,
             .recentYear:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    static func storedValue(from rawValue: String) -> BodyHealthTrendRange {
        BodyHealthTrendRange(rawValue: rawValue) ?? defaultValue
    }
}

enum BodyAppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultValue: BodyAppTheme = .system

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .system:
            return "Auto"
        case .light:
            return "Bright"
        case .dark:
            return "Dim"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .system:
            return .teal
        case .light:
            return .orange
        case .dark:
            return .indigo
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func storedValue(from rawValue: String) -> BodyAppTheme {
        BodyAppTheme(rawValue: rawValue) ?? defaultValue
    }
}

enum BodyAppAccent: String, CaseIterable, Identifiable {
    case blue
    case purple
    case pink
    case green
    case orange
    case teal
    case indigo
    case red
    case gray

    static let defaultValue: BodyAppAccent = .blue

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .blue:
            return "Blue"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        case .teal:
            return "Teal"
        case .indigo:
            return "Indigo"
        case .red:
            return "Red"
        case .gray:
            return "Gray"
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .blue:
            return "Classic"
        case .purple:
            return "Vivid"
        case .pink:
            return "Rose"
        case .green:
            return "Fresh"
        case .orange:
            return "Warm"
        case .teal:
            return "Calm"
        case .indigo:
            return "Deep"
        case .red:
            return "Bold"
        case .gray:
            return "Neutral"
        }
    }

    var iconName: String {
        switch self {
        case .blue:
            return "drop.fill"
        case .purple:
            return "sparkles"
        case .pink:
            return "heart.fill"
        case .green:
            return "leaf.fill"
        case .orange:
            return "sun.max.fill"
        case .teal:
            return "water.waves"
        case .indigo:
            return "moon.stars.fill"
        case .red:
            return "flame.fill"
        case .gray:
            return "circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .blue:
            return .blue
        case .purple:
            return .purple
        case .pink:
            return .pink
        case .green:
            return .green
        case .orange:
            return .orange
        case .teal:
            return .teal
        case .indigo:
            return .indigo
        case .red:
            return .red
        case .gray:
            return .gray
        }
    }

    static func storedValue(from rawValue: String) -> BodyAppAccent {
        BodyAppAccent(rawValue: rawValue) ?? defaultValue
    }
}
