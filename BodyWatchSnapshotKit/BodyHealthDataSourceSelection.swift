//
//  BodyHealthDataSourceSelection.swift
//  BodyWatchSnapshotKit
//
//  The per-metric Apple Health source selection, MOVED here from
//  `Body/Models/BodyAppearancePreference.swift` so Body and BodyWatch decode the
//  identical persisted encoding. The phone ships this container's `rawValue`
//  verbatim in the compute seed (`WatchComputeSettings.healthDataSourceSelectionRaw`);
//  the watch has to turn that string back into per-kind option IDs before it can
//  resolve a source predicate. A second, watch-local decoder for the same string
//  is exactly the kind of hand-fork that made the first standalone-watch-compute
//  attempt read different sources than the phone, so the ONE decoder lives here
//  and both platforms compile it.
//
//  Foundation-only (no SwiftUI): this folder is compiled into the watch app.
//

import Foundation

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

    /// A DETERMINISTIC one-line form of this selection for signature building.
    /// `rawValue` is a `JSONEncoder` dictionary encoding whose key order can
    /// differ between processes, so signing it directly makes an UNCHANGED
    /// selection produce a different settings signature after a phone relaunch
    /// — which the watch would misread as a settings change and strip its
    /// fresher local provenance for nothing. Sorted by kind, so equal logical
    /// selections always sign identically.
    var canonicalSignature: String {
        let perKind = selectedOptions
            .map { kind, option in "\(kind.rawValue)=\(option.id)" }
            .sorted()
            .joined(separator: ",")
        return "default=\(defaultOption.id);\(perKind)"
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

    /// Stable digest of the selected primary sources, mirroring
    /// `BodyHealthSecondaryDataSourceSelection.signature`. Stamped onto the
    /// day-sample sidecar so hydration can reject intraday samples captured
    /// under a different source selection (H6).
    var signature: String {
        (["default=\(defaultOption.id)"] + selectedOptions
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value.id)" })
            .joined(separator: "|")
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
