//
//  BodyAppearancePreference.swift
//  Body
//

import SwiftUI

enum BodySleepStageDisplayPreference {
    static let defaultShowsSubMinuteAwakeStages = true
    static let defaultShowsLeadingTrailingAwakeStages = true

    static func showsSubMinuteAwakeStages(defaults: UserDefaults = .standard) -> Bool {
        guard let storedValue = defaults.object(
            forKey: BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey
        ) as? Bool else {
            return defaultShowsSubMinuteAwakeStages
        }

        return storedValue
    }

    static func showsLeadingTrailingAwakeStages(defaults: UserDefaults = .standard) -> Bool {
        guard let storedValue = defaults.object(
            forKey: BodyAppearancePreference.showsLeadingTrailingAwakeSleepStagesKey
        ) as? Bool else {
            return defaultShowsLeadingTrailingAwakeStages
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

// `sourceSelectableKinds` / `supportsHealthDataSourceSelection` moved to
// `BodyWatchSnapshotKit/BodyHealthDataSourceSelection.swift` (Body + BodyWatch)
// alongside `BodyHealthDataSourceSelection`, which needs them to decode the
// phone's persisted selection on the watch.
extension HealthMetricKind {
    // Kinds whose detail page offers a per-day (intraday) view. Must stay in
    // sync with `supportsMetricDayView` in BodyHealthMetricDetailView.
    static let dayViewKinds: [HealthMetricKind] = [
        .readiness,
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
             .timeInDaylight,
             .vitals,
             .cardioFitness:
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

// `BodyHealthDataSourceOption` itself now lives in
// `BodyWatchSnapshotKit/BodyHealthSourceResolver.swift` (Body + BodyWatch) so
// the watch keys discovered `HKSource`s by exactly the same persisted IDs.
// Only the no-comparison sentinel stays here: its display name is localized
// against the iOS catalog, and no shared/watch code needs the value.
extension BodyHealthDataSourceOption {
    static let noComparison = BodyHealthDataSourceOption(
        id: BodyHealthDataSourceOption.noComparisonID,
        name: String(localized: "No Comparison")
    )
}

// `BodyHealthDataSourceSelection` moved to
// `BodyWatchSnapshotKit/BodyHealthDataSourceSelection.swift` (Body + BodyWatch):
// the watch decodes the phone's persisted `rawValue` out of the compute seed, so
// the encoding and its decoder must be one shared implementation.

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

extension BodyAppearancePreference {
    /// Set once the Cardio Fitness card has been offered to an existing layout.
    /// Lives here rather than beside the other keys in `BodyHealthSelections.swift`
    /// because the summary-card selection it migrates is iOS-only.
    static let summaryCardCardioFitnessMigratedKey = "summaryCardCardioFitnessMigrated"

    /// Set once the Cardio Fitness trend card has been offered to an existing
    /// layout. Keyed separately from the summary-card flag above: the two
    /// selections are stored independently, so a user who customized one but not
    /// the other must still be migrated for both.
    static let homeTrendCardCardioFitnessMigratedKey = "homeTrendCardCardioFitnessMigrated"

    /// The user's on-device display name shown on the Settings profile card.
    static let profileNameKey = "profileName"

    /// The user's on-device avatar, stored as a small JPEG. Empty `Data` means none.
    static let profileAvatarDataKey = "profileAvatarData"
}

/// The local-only user profile shown at the top of Settings. Nothing here is
/// uploaded; it only personalizes how the app looks for the person using it.
enum BodyUserProfile {
    /// Names longer than this are hard-truncated as they're typed — the card
    /// title has to stay on one line.
    static let maximumNameLength = 24

    /// The name to show, or `nil` when the user hasn't set one (so callers can
    /// fall back to the generic card title).
    static func displayName(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    static func load(defaults: UserDefaults = .standard) -> BodySummaryCardSelection {
        let stored = storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.summaryCardSelectionKey)
                ?? defaultRawValue
        )
        return migratingCardioFitnessIfNeeded(stored, defaults: defaults)
    }

    /// One-time migration that shows the Cardio Fitness card to users whose saved
    /// layout predates it. A stored selection only decodes the card raw values it
    /// was written with and never adopts new defaults, so a customized layout would
    /// otherwise never show the card — and because `BodyDashboardFetchSelection`
    /// derives what to fetch from the selected cards, its HealthKit data would never
    /// even be read. Only *visibility* needs this: `repairedOrder` already appends
    /// cards missing from a stored order, so ordering fixes itself.
    ///
    /// Keyed independently of every other migration flag: the permission migration
    /// early-returns on a flag anyone who has already launched the app carries, so
    /// an extension of it could never deliver something new. Idempotent and
    /// per-`defaults` domain; the flag also keeps a later opt-out from being undone.
    private static func migratingCardioFitnessIfNeeded(
        _ selection: BodySummaryCardSelection,
        defaults: UserDefaults
    ) -> BodySummaryCardSelection {
        guard !defaults.bool(forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey) else {
            return selection
        }

        // An empty selection is a deliberate "hide every card" choice, so adding one
        // back would override it. The flag is still recorded, keeping this one-time.
        var migrated = selection
        if !selection.selectedCards.isEmpty {
            migrated.selectedCards.insert(.cardioFitness)
        }

        if migrated != selection {
            defaults.set(migrated.rawValue, forKey: BodyAppearancePreference.summaryCardSelectionKey)
        }
        defaults.set(true, forKey: BodyAppearancePreference.summaryCardCardioFitnessMigratedKey)
        return migrated
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

    static func load(defaults: UserDefaults = .standard) -> BodyHomeTrendCardSelection {
        let stored = storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.homeTrendCardSelectionKey)
                ?? defaultRawValue
        )
        return migratingCardioFitnessIfNeeded(stored, defaults: defaults)
    }

    /// The trend-card twin of `BodySummaryCardSelection.migratingCardioFitnessIfNeeded`.
    /// A saved trend selection only decodes the raw values it was written with, so a
    /// customized list would never pick up a newly added card.
    ///
    /// The views read this selection through `@AppStorage`, not through `load`, so the
    /// write below is what reaches them: it lands in the same defaults key they observe,
    /// and `BodyDashboardFetchSelection.load` runs on the launch dashboard fetch.
    private static func migratingCardioFitnessIfNeeded(
        _ selection: BodyHomeTrendCardSelection,
        defaults: UserDefaults
    ) -> BodyHomeTrendCardSelection {
        guard !defaults.bool(forKey: BodyAppearancePreference.homeTrendCardCardioFitnessMigratedKey) else {
            return selection
        }

        // An empty selection is a deliberate "hide every trend" choice, so adding one
        // back would override it. The flag is still recorded, keeping this one-time.
        var migrated = selection
        if !selection.selectedCards.isEmpty {
            migrated.selectedCards.insert(.cardioFitness)
        }

        if migrated != selection {
            defaults.set(migrated.rawValue, forKey: BodyAppearancePreference.homeTrendCardSelectionKey)
        }
        defaults.set(true, forKey: BodyAppearancePreference.homeTrendCardCardioFitnessMigratedKey)
        return migrated
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

        let kindList = HealthMetricKind.dayViewKinds
            .filter { enabledKinds.contains($0) }
            .map(\.rawValue)
        return ([Self.currentFormatMarker] + kindList).joined(separator: ",")
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

    /// Marks a raw value written after the Readiness day view shipped. A value
    /// without it that enables exactly `preReadinessDefaultKinds` predates the
    /// readiness row and upgrades to the current default; a value carrying the
    /// marker is authoritative, so deselecting only Readiness sticks. Unknown
    /// tokens are already skipped by the kind parser, so old builds reading a
    /// marked value simply ignore the marker.
    private static let currentFormatMarker = "v2"

    /// The full day-view list as it shipped before Readiness joined. A persisted
    /// unmarked selection equal to this set predates the readiness row (it could
    /// not be deselected when the value was saved) rather than expressing a
    /// choice to exclude it, so it upgrades to the current default. Any other
    /// subset — and "none" — is an intentional selection and is preserved as-is.
    private static let preReadinessDefaultKinds: Set<HealthMetricKind> = [
        .heartRate,
        .heartRateVariability,
        .respiratoryRate,
        .oxygenSaturation,
        .activeEnergy,
        .steps
    ]

    static func storedValue(from rawValue: String) -> BodyMetricDayViewSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodyMetricDayViewSelection(enabledKinds: [])
        }

        let tokens = trimmedValue.split(separator: ",").map(String.init)
        let kinds = Set(tokens.compactMap {
            HealthMetricKind(rawValue: $0)
        }.filter(HealthMetricKind.dayViewKinds.contains))

        guard !kinds.isEmpty else {
            return defaultValue
        }

        guard tokens.contains(currentFormatMarker) || kinds != preReadinessDefaultKinds else {
            return defaultValue
        }

        return BodyMetricDayViewSelection(enabledKinds: kinds)
    }
}

/// Which metric threshold warnings surface in the UI. Display only: the
/// warnings are still detected, so turning one back on needs no refetch.
struct BodyMetricWarningSelection: Equatable {
    static let defaultValue = BodyMetricWarningSelection(enabledKinds: Set(MetricWarningKind.allCases))
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var enabledKinds: Set<MetricWarningKind>

    var rawValue: String {
        guard !enabledKinds.isEmpty else {
            return "none"
        }

        return MetricWarningKind.allCases
            .filter { enabledKinds.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }

    var enabledCount: Int {
        enabledKinds.count
    }

    var totalCount: Int {
        MetricWarningKind.allCases.count
    }

    func includes(_ kind: MetricWarningKind) -> Bool {
        enabledKinds.contains(kind)
    }

    func setting(_ kind: MetricWarningKind, isEnabled: Bool) -> BodyMetricWarningSelection {
        var nextKinds = enabledKinds
        if isEnabled {
            nextKinds.insert(kind)
        } else {
            nextKinds.remove(kind)
        }

        return BodyMetricWarningSelection(enabledKinds: nextKinds)
    }

    static func storedValue(from rawValue: String) -> BodyMetricWarningSelection {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return defaultValue
        }

        guard trimmedValue != "none" else {
            return BodyMetricWarningSelection(enabledKinds: [])
        }

        let kinds = Set(trimmedValue.split(separator: ",").compactMap {
            MetricWarningKind(rawValue: String($0))
        })

        guard !kinds.isEmpty else {
            return defaultValue
        }

        return BodyMetricWarningSelection(enabledKinds: kinds)
    }
}

/// The user's custom limits for the metric threshold warnings. Only overrides
/// are stored, so a kind the user never touched keeps following its default —
/// which for high heart rate tracks their max HR rather than a fixed number.
struct BodyMetricWarningThresholds: Equatable {
    static let defaultValue = BodyMetricWarningThresholds(overrides: [:])
    static var defaultRawValue: String {
        defaultValue.rawValue
    }

    var overrides: [MetricWarningKind: Int]

    var rawValue: String {
        guard !overrides.isEmpty else {
            return ""
        }

        let object = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder.sortedKeys.encode(object),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string
    }

    func override(for kind: MetricWarningKind) -> Int? {
        overrides[kind]
    }

    /// `nil` clears the override so the kind falls back to its default.
    func setting(_ kind: MetricWarningKind, to value: Int?) -> BodyMetricWarningThresholds {
        var nextOverrides = overrides
        if let value {
            nextOverrides[kind] = Self.clamped(value, to: kind)
        } else {
            nextOverrides.removeValue(forKey: kind)
        }

        return BodyMetricWarningThresholds(overrides: nextOverrides)
    }

    /// The limit to detect against: the user's override, else the default —
    /// zone 3's lower bound for high heart rate, the fixed value otherwise.
    func threshold(for kind: MetricWarningKind, maxHeartRate: Double? = nil) -> Double {
        if let override = overrides[kind] {
            return Double(override)
        }

        guard kind == .highHeartRate,
              let zoneThree = Self.zoneThreeLowerBound(maxHeartRate: maxHeartRate) else {
            return kind.defaultThreshold
        }

        return zoneThree
    }

    /// Lower bound of heart rate zone 3 (70 % of max HR), rounded to a whole
    /// beat and clamped into the picker's range. `nil` without a usable max HR,
    /// so callers fall back to the fixed default.
    static func zoneThreeLowerBound(maxHeartRate: Double?) -> Double? {
        guard let maxHeartRate, maxHeartRate.isFinite, maxHeartRate > 0 else {
            return nil
        }

        let fraction = WorkoutHeartRateZones.lowerBoundFractions[2]
        return Double(clamped(Int((maxHeartRate * fraction).rounded()), to: .highHeartRate))
    }

    static func storedValue(from rawValue: String) -> BodyMetricWarningThresholds {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let data = trimmedValue.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return defaultValue
        }

        var overrides: [MetricWarningKind: Int] = [:]
        for (key, value) in object {
            guard let kind = MetricWarningKind(rawValue: key) else {
                continue
            }
            overrides[kind] = clamped(value, to: kind)
        }

        return BodyMetricWarningThresholds(overrides: overrides)
    }

    private static func clamped(_ value: Int, to kind: MetricWarningKind) -> Int {
        min(max(value, kind.thresholdRange.lowerBound), kind.thresholdRange.upperBound)
    }
}

private extension JSONEncoder {
    /// Stable key order so the stored string only changes when a value does.
    static var sortedKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
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
    private static let vitalsMetricKinds: Set<HealthMetricKind> = [.sleep]

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

        if metrics.contains(.vitals) {
            metrics.formUnion(Self.vitalsMetricKinds)
        }

        metricKinds = metrics
    }

    func includes(_ kind: HealthMetricKind) -> Bool {
        metricKinds.contains(kind)
    }

    static func load(defaults: UserDefaults = .standard) -> BodyDashboardFetchSelection {
        BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection.load(defaults: defaults),
            trendCards: BodyHomeTrendCardSelection.load(defaults: defaults),
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
    case cardioFitness
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
        .cardioFitness,
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
        case .cardioFitness:
            return String(localized: "Cardio Fitness")
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
        case .cardioFitness:
            return String(localized: "VO₂ max trend")
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
        case .cardioFitness:
            return "arrow.up.heart.fill"
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
             .heartRateVariability,
             .cardioFitness:
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
    case vitals
    case cardioFitness

    static let defaultOrder: [BodyHomeCardKind] = [
        .sleep,
        .vitals,
        .trainingLoad,
        .basics,
        .heartRate,
        .heartRateVariability,
        .readiness,
        .activeEnergy,
        .restingEnergy,
        .restingHeartRate,
        .cardioFitness,
        .steps,
        .exerciseMinutes,
        .wristTemperature,
        .oxygenSaturation,
        .respiratoryRate,
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
        case .vitals:
            return .vitals
        case .cardioFitness:
            return .cardioFitness
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
        case .vitals:
            return String(localized: "Vitals")
        case .cardioFitness:
            return String(localized: "Cardio Fitness")
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
        case .vitals:
            return String(localized: "Overnight vitals vs your typical range")
        case .cardioFitness:
            return String(localized: "VO₂ max fitness level")
        }
    }

    var isBeta: Bool {
        switch self {
        case .readiness:
            return true
        case .vitals,
             .cardioFitness,
             .activityRings,
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
            return "person"
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
        case .vitals:
            return "heart.badge.bolt"
        case .cardioFitness:
            return "arrow.up.heart.fill"
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
             .heartRateVariability,
             .cardioFitness:
            return Color(red: 1.00, green: 0.25, blue: 0.45)
        case .restingEnergy:
            return Color(red: 0.14, green: 0.72, blue: 0.42)
        case .vitals:
            return Color(red: 0.25, green: 0.62, blue: 1.00)
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
        let cards = repairedOrder(order).filter { selection.includes($0) }

        return BodyHomeCardGridPacking.rows(slotCounts: cards.map(\.slotCount)).map { indices in
            BodyHomeCardLayoutRow(cards: indices.map { cards[$0] })
        }
    }

    /// The grid's visible cards in their stored order, flattened. The Home grid renders
    /// from this rather than from `layoutRows` so every card keeps one identity across a
    /// reorder — see `BodyHomeCardGridLayout`.
    static func visibleOrder(
        from order: [BodyHomeCardKind],
        visibleIn selection: BodySummaryCardSelection = .defaultValue
    ) -> [BodyHomeCardKind] {
        repairedOrder(order).filter { selection.includes($0) }
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

/// The single rule the Home card grid packs by: two slots per row, and a card that needs
/// both slots owns its row. `BodyHomeCardKind.layoutRows` and the on-screen
/// `BodyHomeCardGridLayout` both pack through here so the model and the layout cannot drift.
enum BodyHomeCardGridPacking {
    static let slotsPerRow = 2

    /// Groups consecutive item indices into rows holding at most `slotsPerRow` slots.
    static func rows(slotCounts: [Int]) -> [[Int]] {
        var rows: [[Int]] = []
        var currentRow: [Int] = []
        var currentSlots = 0

        for (index, rawSlots) in slotCounts.enumerated() {
            let slots = max(1, rawSlots)

            if slots >= slotsPerRow {
                if !currentRow.isEmpty {
                    rows.append(currentRow)
                    currentRow = []
                    currentSlots = 0
                }

                rows.append([index])
                continue
            }

            if currentSlots + slots > slotsPerRow {
                rows.append(currentRow)
                currentRow = []
                currentSlots = 0
            }

            currentRow.append(index)
            currentSlots += slots

            if currentSlots == slotsPerRow {
                rows.append(currentRow)
                currentRow = []
                currentSlots = 0
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
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
