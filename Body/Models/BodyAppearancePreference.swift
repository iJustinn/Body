//
//  BodyAppearancePreference.swift
//  Body
//

import SwiftUI

enum BodySleepStageDisplayPreference {
    static let defaultShowsSubMinuteAwakeStages = true

    static func showsSubMinuteAwakeStages(defaults: UserDefaults = .standard) -> Bool {
        guard let storedValue = defaults.object(
            forKey: BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey
        ) as? Bool else {
            return defaultShowsSubMinuteAwakeStages
        }

        return storedValue
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

    // Kinds whose detail page offers a per-day (intraday) view. Must stay in
    // sync with `supportsMetricDayView` in BodyHealthMetricDetailView.
    static let dayViewKinds: [HealthMetricKind] = [
        .heartRate,
        .heartRateVariability,
        .respiratoryRate,
        .oxygenSaturation,
        .activeEnergy,
        .steps
    ]

    var supportedComparisonCharts: Set<SourceComparisonChartKind> {
        switch self {
        case .readiness:
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
            return String(localized: "Heart Rate")
        case .sleep:
            return String(localized: "Sleep")
        case .basics:
            return String(localized: "Basics")
        case .heartRateVariability:
            return String(localized: "HRV")
        case .restingHeartRate:
            return String(localized: "Resting Heart Rate")
        case .respiratoryRate:
            return String(localized: "Respiratory Rate")
        case .steps:
            return String(localized: "Steps")
        case .oxygenSaturation:
            return String(localized: "Blood Oxygen")
        case .activeEnergy:
            return String(localized: "Active Energy")
        case .restingEnergy:
            return String(localized: "Resting Energy")
        case .exerciseMinutes:
            return String(localized: "Exercise Minutes")
        case .wristTemperature:
            return String(localized: "Skin Temperature")
        case .timeInDaylight:
            return String(localized: "sourcePicker.timeInDaylight", defaultValue: "Time in Daylight")
        default:
            return String(localized: "Data")
        }
    }
}

struct BodyHealthDataSourceOption: Codable, Equatable, Identifiable {
    static let allSources = BodyHealthDataSourceOption(id: "all", name: "Apple Health")
    static let noComparison = BodyHealthDataSourceOption(id: "none", name: String(localized: "No Comparison"))
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

    var iconBundleIdentifierHint: String? {
        if isAllSources || isNoComparison || isCombinedSource {
            return nil
        }

        let disambiguatedPrefix = "source:bundle="
        guard id.hasPrefix(disambiguatedPrefix) else {
            return id
        }

        let remainder = id.dropFirst(disambiguatedPrefix.count)
        guard let nameRange = remainder.range(of: "|name=") else {
            return String(remainder)
        }

        return String(remainder[remainder.startIndex..<nameRange.lowerBound])
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
        let nextOption = option.isNoComparison ? BodyHealthDataSourceOption.allSources : option
        if nextOption.id == defaultOption.id {
            nextOptions.removeValue(forKey: kind)
        } else {
            nextOptions[kind] = nextOption
        }

        return BodyHealthDataSourceSelection(defaultOption: defaultOption, selectedOptions: nextOptions)
    }

    func settingDefault(option: BodyHealthDataSourceOption) -> BodyHealthDataSourceSelection {
        let nextDefaultOption = option.isNoComparison ? BodyHealthDataSourceOption.allSources : option
        let nextOptions = selectedOptions.filter { _, selectedOption in
            selectedOption.id != defaultOption.id && selectedOption.id != nextDefaultOption.id
        }

        return BodyHealthDataSourceSelection(
            defaultOption: nextDefaultOption,
            selectedOptions: nextOptions
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
        if option.id == defaultOption.id {
            nextOptions.removeValue(forKey: kind)
        } else {
            nextOptions[kind] = option
        }

        return BodyHealthSecondaryDataSourceSelection(defaultOption: defaultOption, selectedOptions: nextOptions)
    }

    func settingDefault(option: BodyHealthDataSourceOption) -> BodyHealthSecondaryDataSourceSelection {
        let nextOptions = selectedOptions.filter { _, selectedOption in
            selectedOption.id != defaultOption.id && selectedOption.id != option.id
        }

        return BodyHealthSecondaryDataSourceSelection(
            defaultOption: option,
            selectedOptions: nextOptions
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

struct BodyMetricDayViewSelection: Equatable {
    static let defaultValue = BodyMetricDayViewSelection(enabledKinds: Set(HealthMetricKind.dayViewKinds))
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var enabledKinds: Set<HealthMetricKind>

    var rawValue: String {
        guard !enabledKinds.isEmpty else {
            return "none"
        }

        return HealthMetricKind.dayViewKinds
            .filter { enabledKinds.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    var enabledCount: Int {
        enabledKinds.count
    }

    func includes(_ kind: HealthMetricKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func setting(_ kind: HealthMetricKind, isEnabled: Bool) -> BodyMetricDayViewSelection {
        var nextKinds = enabledKinds
        if isEnabled {
            nextKinds.insert(kind)
        } else {
            nextKinds.remove(kind)
        }

        return BodyMetricDayViewSelection(enabledKinds: nextKinds)
    }

    static func storedValue(from rawValue: String) -> BodyMetricDayViewSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodyMetricDayViewSelection(enabledKinds: [])
        }

        let kinds = Set(trimmedValue.split(separator: ",").compactMap {
            HealthMetricKind(rawValue: String($0))
        }.filter(HealthMetricKind.dayViewKinds.contains))

        guard !kinds.isEmpty else {
            return defaultValue
        }

        return BodyMetricDayViewSelection(enabledKinds: kinds)
    }
}

struct BodyDashboardFetchSelection: Equatable {
    private static let basicsMetricKinds: Set<HealthMetricKind> = [
        .bodyMass,
        .bodyFatPercentage,
        .bodyMassIndex
    ]
    private static let readinessDependencyKinds: Set<HealthMetricKind> = [
        .sleep,
        .heartRateVariability,
        .restingHeartRate,
        .trainingLoad,
        .respiratoryRate,
        .oxygenSaturation,
        .wristTemperature
    ]

    static let defaultValue = BodyDashboardFetchSelection(
        summaryCards: BodySummaryCardSelection.defaultValue,
        trendCards: BodyHomeTrendCardSelection.defaultValue
    )

    let includesActivityRings: Bool
    private let metricKinds: Set<HealthMetricKind>

    init(
        summaryCards: BodySummaryCardSelection,
        trendCards: BodyHomeTrendCardSelection,
        starredMetric: BodyHomeCardKind? = nil
    ) {
        // The star-metric hero shows Activity Rings regardless of the Summary Cards
        // toggle, so its HealthKit data must be fetched whenever it's starred.
        includesActivityRings = summaryCards.includes(.activityRings) || starredMetric == .activityRings

        var metrics = Set(summaryCards.selectedCards.compactMap(\.healthMetricKind))
        metrics.formUnion(trendCards.selectedCards.map(\.metricKind))

        // The starred hero shows its metric regardless of the Summary Cards toggle, so
        // its HealthKit data (and any derived dependencies, e.g. readiness's inputs
        // below) must be fetched whenever it's starred.
        if let starredMetricKind = starredMetric?.healthMetricKind {
            metrics.insert(starredMetricKind)
        }

        if metrics.contains(.basics) {
            metrics.formUnion(Self.basicsMetricKinds)
        }

        if metrics.contains(.readiness) {
            metrics.formUnion(Self.readinessDependencyKinds)
        }

        metricKinds = metrics
    }

    func includes(_ kind: HealthMetricKind) -> Bool {
        metricKinds.contains(kind)
    }

    static func load(defaults: UserDefaults = .standard) -> BodyDashboardFetchSelection {
        BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection.storedValue(
                from: defaults.string(forKey: BodyAppearancePreference.summaryCardSelectionKey)
                    ?? BodySummaryCardSelection.defaultRawValue
            ),
            trendCards: BodyHomeTrendCardSelection.storedValue(
                from: defaults.string(forKey: BodyAppearancePreference.homeTrendCardSelectionKey)
                    ?? BodyHomeTrendCardSelection.defaultRawValue
            ),
            starredMetric: BodyHomeCardKind.starredMetric(
                from: defaults.string(forKey: BodyAppearancePreference.starredMetricKey)
                    ?? BodyHomeCardKind.readiness.rawValue
            )
        )
    }
}

enum BodyHomeTrendCardKind: String, CaseIterable, Identifiable {
    case readiness
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
    case bodyMass
    case bodyFatPercentage

    static let defaultOrder: [BodyHomeTrendCardKind] = [
        .readiness,
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
        .timeInDaylight,
        .bodyMass,
        .bodyFatPercentage
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
        case .readiness:
            return String(localized: "Readiness")
        case .heartRate:
            return String(localized: "Heart Rate")
        case .restingHeartRate:
            return String(localized: "Resting Heart Rate")
        case .heartRateVariability:
            return String(localized: "HRV")
        case .respiratoryRate:
            return String(localized: "Respiratory Rate")
        case .oxygenSaturation:
            return String(localized: "Blood Oxygen")
        case .sleep:
            return String(localized: "Sleep")
        case .wristTemperature:
            return String(localized: "Skin Temperature")
        case .steps:
            return String(localized: "Steps")
        case .activeEnergy:
            return String(localized: "Active Energy")
        case .restingEnergy:
            return String(localized: "Resting Energy")
        case .exerciseMinutes:
            return String(localized: "Exercise Minutes")
        case .trainingLoad:
            return String(localized: "Training Load")
        case .timeInDaylight:
            return String(localized: "Time In Daylight")
        case .bodyMass:
            return String(localized: "Weight")
        case .bodyFatPercentage:
            return String(localized: "Body Fat")
        }
    }

    var subtitle: String {
        switch self {
        case .readiness:
            return String(localized: "Readiness score trend")
        case .heartRate:
            return String(localized: "Average heart rate trend")
        case .restingHeartRate:
            return String(localized: "Resting heart trend")
        case .heartRateVariability:
            return String(localized: "Readiness signal trend")
        case .respiratoryRate:
            return String(localized: "Breathing rate trend")
        case .oxygenSaturation:
            return String(localized: "Blood oxygen trend")
        case .sleep:
            return String(localized: "Sleep duration trend")
        case .wristTemperature:
            return String(localized: "Sleeping skin temperature trend")
        case .steps:
            return String(localized: "Daily step trend")
        case .activeEnergy:
            return String(localized: "Active calorie trend")
        case .restingEnergy:
            return String(localized: "Resting calorie trend")
        case .exerciseMinutes:
            return String(localized: "Exercise minute trend")
        case .trainingLoad:
            return String(localized: "Workout strain trend")
        case .timeInDaylight:
            return String(localized: "Outdoor daylight trend")
        case .bodyMass:
            return String(localized: "Body weight trend")
        case .bodyFatPercentage:
            return String(localized: "Body fat trend")
        }
    }

    var iconName: String {
        switch self {
        case .readiness:
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
        case .bodyMass:
            return "scalemass.fill"
        case .bodyFatPercentage:
            return "percent"
        }
    }

    var tintColor: Color {
        switch self {
        case .readiness:
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
        case .bodyMass:
            return Color(red: 0.50, green: 0.34, blue: 1.00)
        case .bodyFatPercentage:
            return Color(red: 1.00, green: 0.68, blue: 0.08)
        }
    }
}

enum BodyHomeCardKind: String, CaseIterable, Identifiable {
    case activityRings
    case readiness
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
        .sleep,
        .basics,
        .heartRate,
        .heartRateVariability,
        .trainingLoad,
        .readiness,
        .activeEnergy,
        .restingEnergy,
        .wristTemperature,
        .restingHeartRate,
        .oxygenSaturation,
        .respiratoryRate,
        .exerciseMinutes,
        .steps,
        .timeInDaylight,
        .activityRings
    ]

    static var defaultRawValue: String {
        rawValue(from: defaultOrder)
    }

    /// Metrics eligible to be promoted to the home-page "star" hero. Grows as more
    /// metrics get a hero treatment; today only Readiness qualifies.
    static let starEligible: [BodyHomeCardKind] = [.readiness]

    /// Parses the stored star-metric preference. Returns the kind only when it both
    /// parses and is currently star-eligible; empty / unknown / ineligible -> nil (None).
    static func starredMetric(from rawValue: String) -> BodyHomeCardKind? {
        guard let kind = BodyHomeCardKind(rawValue: rawValue), starEligible.contains(kind) else {
            return nil
        }
        return kind
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
        case .readiness:
            return .readiness
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
            return String(localized: "Activity Rings")
        case .readiness:
            return String(localized: "Readiness")
        case .exerciseMinutes:
            return String(localized: "Exercise Minutes")
        case .trainingLoad:
            return String(localized: "Training Load")
        case .wristTemperature:
            return String(localized: "Skin Temperature")
        case .timeInDaylight:
            return String(localized: "Time In Daylight")
        case .steps:
            return String(localized: "Steps")
        case .sleep:
            return String(localized: "Sleep")
        case .basics:
            return String(localized: "Basics")
        case .heartRate:
            return String(localized: "Heart Rate")
        case .restingHeartRate:
            return String(localized: "Resting Heart Rate")
        case .heartRateVariability:
            return String(localized: "HRV")
        case .oxygenSaturation:
            return String(localized: "Blood Oxygen")
        case .respiratoryRate:
            return String(localized: "Respiratory Rate")
        case .activeEnergy:
            return String(localized: "Active Energy")
        case .restingEnergy:
            return String(localized: "Resting Energy")
        }
    }

    var subtitle: String {
        switch self {
        case .activityRings:
            return String(localized: "Move, Exercise, and Stand progress")
        case .readiness:
            return String(localized: "Readiness from sleep, strain, and vitals")
        case .exerciseMinutes:
            return String(localized: "Daily exercise minute total")
        case .trainingLoad:
            return String(localized: "Workout strain ratio")
        case .wristTemperature:
            return String(localized: "Sleeping skin temperature")
        case .timeInDaylight:
            return String(localized: "Outdoor daylight exposure")
        case .steps:
            return String(localized: "Step count total")
        case .sleep:
            return String(localized: "Sleep score and duration")
        case .basics:
            return String(localized: "Weight, body fat, and BMI")
        case .heartRate:
            return String(localized: "Daily heart rate")
        case .restingHeartRate:
            return String(localized: "Resting beats per minute")
        case .heartRateVariability:
            return String(localized: "Readiness and stress signal")
        case .oxygenSaturation:
            return String(localized: "Blood oxygen range")
        case .respiratoryRate:
            return String(localized: "Breathing rate range")
        case .activeEnergy:
            return String(localized: "Active calories")
        case .restingEnergy:
            return String(localized: "Resting calories")
        }
    }

    var isBeta: Bool {
        switch self {
        case .readiness:
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
        case .readiness:
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
        case .readiness:
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

enum BodyAppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let defaultValue: BodyAppTheme = .dark

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "System")
        case .light:
            return String(localized: "Light")
        case .dark:
            return String(localized: "Dark")
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .system:
            return String(localized: "Auto")
        case .light:
            return String(localized: "Bright")
        case .dark:
            return String(localized: "Dim")
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
        if BodyAppTheme(rawValue: rawValue) == .dark {
            return .dark
        }

        return defaultValue
    }
}
