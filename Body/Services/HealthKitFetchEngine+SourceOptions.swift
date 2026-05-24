//
//  HealthKitFetchEngine+SourceOptions.swift
//  Body
//

import Foundation
import HealthKit

// Source-option discovery: enumerates the Apple Health sources available
// for each source-selectable metric and groups them into combined-name
// buckets (so e.g. two "Apple Watch" sources can show as one combined
// pick). The grouped result is memoized in the engine's actor state
// (`healthSourcesByKind`) so subsequent fetches reuse the source map.
extension HealthKitFetchEngine {
    func fetchHealthDataSourceOptions(calendar: Calendar) async -> [HealthMetricKind: [BodyHealthDataSourceOption]]? {
        let permissionRawValue = permissionSelection.rawValue
        if fetchedHealthDataSourcePermissionRawValue == permissionRawValue,
           !healthSourcesByKind.isEmpty {
            return nil
        }

        var nextOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
        var nextSourcesByKind: [HealthMetricKind: [String: [HKSource]]] = [:]

        for kind in HealthMetricKind.sourceSelectableKinds {
            guard permissionSelection.includes(healthPermission(forSourceKind: kind)),
                  !healthSampleTypes(forSourceKind: kind).isEmpty else {
                continue
            }

            let sources = await fetchHealthDataSources(for: healthSampleTypes(forSourceKind: kind))
            let (options, sourcesByID) = sourceOptionsAndMap(from: sources)

            nextOptionsByKind[kind] = options
            nextSourcesByKind[kind] = sourcesByID
        }

        healthSourcesByKind = nextSourcesByKind
        fetchedHealthDataSourcePermissionRawValue = permissionRawValue
        return nextOptionsByKind
    }

    private func sourceOptionsAndMap(
        from sources: [HKSource]
    ) -> (options: [BodyHealthDataSourceOption], sourcesByID: [String: [HKSource]]) {
        let sortedSources = sources.sorted { lhs, rhs in
            let lhsName = displayName(for: lhs)
            let rhsName = displayName(for: rhs)
            if lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        var sourcesByID: [String: [HKSource]] = [:]
        let duplicateNameBundleIdentifiers = Set(
            Dictionary(grouping: sortedSources, by: \.bundleIdentifier)
                .compactMap { bundleIdentifier, sources in
                    let sourceNameKeys = Set(sources.map { source in
                        BodyHealthDataSourceOption.individualSourceIdentityKey(
                            bundleIdentifier: source.bundleIdentifier,
                            name: displayName(for: source)
                        )
                    })
                    return sourceNameKeys.count > 1 ? bundleIdentifier : nil
                }
        )
        for source in sortedSources {
            let sourceID = BodyHealthDataSourceOption.individualSourceID(
                bundleIdentifier: source.bundleIdentifier,
                name: displayName(for: source),
                disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(source.bundleIdentifier)
            )
            sourcesByID[sourceID, default: []].append(source)
        }

        let groupedSources = Dictionary(grouping: sortedSources) { source in
            BodyHealthDataSourceOption.normalizedSourceName(displayName(for: source))
        }
        for group in groupedSources.values where group.count > 1 {
            let displayName = displayName(for: group[0])
            sourcesByID[BodyHealthDataSourceOption.combinedSourceID(for: displayName)] = group
        }

        let options: [BodyHealthDataSourceOption]
        if combinesHealthDataSourcesByName {
            options = groupedSources.values.map { group in
                let displayName = displayName(for: group[0])
                let optionID = group.count > 1
                    ? BodyHealthDataSourceOption.combinedSourceID(for: displayName)
                    : BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: group[0].bundleIdentifier,
                        name: displayName,
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(group[0].bundleIdentifier)
                    )
                return BodyHealthDataSourceOption(
                    id: optionID,
                    name: BodyHealthDataSourceOption.combinedSourceDisplayName(for: displayName)
                )
            }
        } else {
            options = sortedSources.map { source in
                let displayName = displayName(for: source)
                return BodyHealthDataSourceOption(
                    id: BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: source.bundleIdentifier,
                        name: displayName,
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(source.bundleIdentifier)
                    ),
                    name: displayName
                )
            }
        }

        return (
            options.sorted { lhs, rhs in
                if lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame {
                    return lhs.id < rhs.id
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            },
            sourcesByID
        )
    }

    private func displayName(for source: HKSource) -> String {
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unknown Source" : trimmedName
    }

    private func fetchHealthDataSources(for sampleTypes: [HKSampleType]) async -> [HKSource] {
        var sourcesByIdentifier: [String: HKSource] = [:]
        for sampleType in sampleTypes {
            let sources = await fetchHealthDataSources(for: sampleType)
            for source in sources {
                let sourceKey = BodyHealthDataSourceOption.individualSourceIdentityKey(
                    bundleIdentifier: source.bundleIdentifier,
                    name: displayName(for: source)
                )
                if sourcesByIdentifier[sourceKey] == nil {
                    sourcesByIdentifier[sourceKey] = source
                }
            }
        }
        return Array(sourcesByIdentifier.values)
    }

    private func fetchHealthDataSources(for sampleType: HKSampleType) async -> [HKSource] {
        await withCheckedContinuation { continuation in
            let query = HKSourceQuery(
                sampleType: sampleType,
                samplePredicate: nil
            ) { _, sources, _ in
                continuation.resume(returning: Array(sources ?? []))
            }

            healthStore.execute(query)
        }
    }
}
