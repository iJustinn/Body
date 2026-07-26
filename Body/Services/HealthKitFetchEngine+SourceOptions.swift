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

        let kinds = HealthMetricKind.sourceSelectableKinds.filter { kind in
            permissionSelection.includes(healthPermission(forSourceKind: kind))
                && !healthSampleTypes(forSourceKind: kind).isEmpty
        }

        // Fan the per-kind source queries out concurrently instead of awaiting
        // them one kind at a time — on a first refresh this is ~13 serial
        // `HKSourceQuery` round-trips that gate the dashboard fetch. Each child
        // hops onto the actor and suspends in its query, so all queries are in
        // flight at once; the (cheap, CPU-only) `sourceOptionsAndMap` assembly
        // stays on the actor below.
        let kindSources = await withTaskGroup(of: KindSources.self) { group in
            for kind in kinds {
                group.addTask { await self.fetchKindSources(for: kind) }
            }

            var collected: [KindSources] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        // Merge only successfully discovered kinds: a failed kind keeps its
        // prior source map (so a resolvable selection stays resolvable) and is
        // omitted from the returned options (the store keeps its prior options).
        // The permission signature is recorded ONLY when every kind succeeded,
        // so a partial failure re-runs discovery on the next refresh (the guard
        // above short-circuits only after a fully-successful run).
        var nextOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
        var nextSourcesByKind = healthSourcesByKind
        var anyKindFailed = false
        for kindSource in kindSources {
            guard let sources = kindSource.sources else {
                anyKindFailed = true
                continue
            }
            let (options, sourcesByID) = sourceOptionsAndMap(from: sources)
            nextOptionsByKind[kindSource.kind] = options
            nextSourcesByKind[kindSource.kind] = sourcesByID
        }

        healthSourcesByKind = nextSourcesByKind
        if !anyKindFailed {
            fetchedHealthDataSourcePermissionRawValue = permissionRawValue
        }
        return nextOptionsByKind
    }

    private func fetchKindSources(for kind: HealthMetricKind) async -> KindSources {
        KindSources(
            kind: kind,
            sources: await fetchHealthDataSources(for: healthSampleTypes(forSourceKind: kind))
        )
    }

    /// One metric kind's discovered sources, carried out of the concurrent
    /// fetch task group. A `nil` `sources` marks a failed discovery for the
    /// kind. `@unchecked Sendable` is sound because `HKSource` is immutable
    /// metadata (read-only; never mutated after the query returns) — HealthKit
    /// just doesn't annotate it `Sendable`.
    private struct KindSources: @unchecked Sendable {
        let kind: HealthMetricKind
        let sources: [HKSource]?
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
                            name: identityName(for: source)
                        )
                    })
                    return sourceNameKeys.count > 1 ? bundleIdentifier : nil
                }
        )
        for source in sortedSources {
            let sourceID = BodyHealthDataSourceOption.individualSourceID(
                bundleIdentifier: source.bundleIdentifier,
                name: identityName(for: source),
                disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(source.bundleIdentifier)
            )
            sourcesByID[sourceID, default: []].append(source)
        }

        let groupedSources = Dictionary(grouping: sortedSources) { source in
            BodyHealthDataSourceOption.normalizedSourceName(identityName(for: source))
        }
        for group in groupedSources.values where group.count > 1 {
            sourcesByID[BodyHealthDataSourceOption.combinedSourceID(for: identityName(for: group[0]))] = group
        }

        let options: [BodyHealthDataSourceOption]
        if combinesHealthDataSourcesByName {
            options = groupedSources.values.map { group in
                let optionID = group.count > 1
                    ? BodyHealthDataSourceOption.combinedSourceID(for: identityName(for: group[0]))
                    : BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: group[0].bundleIdentifier,
                        name: identityName(for: group[0]),
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(group[0].bundleIdentifier)
                    )
                return BodyHealthDataSourceOption(
                    id: optionID,
                    name: BodyHealthDataSourceOption.combinedSourceDisplayName(for: displayName(for: group[0]))
                )
            }
        } else {
            options = sortedSources.map { source in
                return BodyHealthDataSourceOption(
                    id: BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: source.bundleIdentifier,
                        name: identityName(for: source),
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(source.bundleIdentifier)
                    ),
                    name: displayName(for: source)
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
        return trimmedName.isEmpty ? String(localized: "Unknown Source") : trimmedName
    }

    /// Locale-stable name used for persisted option IDs and grouping keys. A
    /// blank source name falls back to a fixed English string so switching the
    /// app language never re-keys the same HealthKit source and drops the user's
    /// selected source override. Only `displayName(for:)` is localized.
    private func identityName(for source: HKSource) -> String {
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unknown Source" : trimmedName
    }

    /// Returns `nil` when ANY per-sample-type source query fails (device
    /// locked, store unavailable) rather than genuinely returning no sources —
    /// the caller fails the whole kind so an unresolved source selection keeps
    /// the cache instead of silently querying all sources (H4).
    private func fetchHealthDataSources(for sampleTypes: [HKSampleType]) async -> [HKSource]? {
        // Fan the per-sample-type `HKSourceQuery` round-trips out concurrently
        // instead of awaiting them one at a time. Results are collected by
        // index so the merge below can replay the exact same first-wins,
        // iteration-order precedence as the old serial loop.
        var resultsByIndex = [[HKSource]?](repeating: [], count: sampleTypes.count)
        await withTaskGroup(of: IndexedSources.self) { group in
            for (index, sampleType) in sampleTypes.enumerated() {
                group.addTask {
                    IndexedSources(index: index, sources: await self.fetchHealthDataSources(for: sampleType))
                }
            }

            for await result in group {
                resultsByIndex[result.index] = result.sources
            }
        }

        var sourcesByIdentifier: [String: HKSource] = [:]
        for sources in resultsByIndex {
            guard let sources else {
                return nil
            }
            for source in sources {
                let sourceKey = BodyHealthDataSourceOption.individualSourceIdentityKey(
                    bundleIdentifier: source.bundleIdentifier,
                    name: identityName(for: source)
                )
                if sourcesByIdentifier[sourceKey] == nil {
                    sourcesByIdentifier[sourceKey] = source
                }
            }
        }
        return Array(sourcesByIdentifier.values)
    }

    /// One sample type's discovered sources, carried out of the concurrent
    /// fetch task group, tagged with its original index so the merge can
    /// replay first-wins precedence in the same order as a serial loop. A
    /// `nil` `sources` marks a failed query. `@unchecked Sendable` mirrors
    /// `KindSources` above — sound because `HKSource` is immutable metadata
    /// that HealthKit just doesn't annotate `Sendable`. A raw tuple can't be
    /// marked `@unchecked Sendable`, hence this wrapper struct.
    private struct IndexedSources: @unchecked Sendable {
        let index: Int
        let sources: [HKSource]?
    }

    private func fetchHealthDataSources(for sampleType: HKSampleType) async -> [HKSource]? {
        await withCheckedContinuation { continuation in
            let query = HKSourceQuery(
                sampleType: sampleType,
                samplePredicate: nil
            ) { _, sources, error in
                guard let sources else {
                    Self.logTrendQueryFailure("sources:\(sampleType.identifier)", error: error)
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Array(sources))
            }

            healthStore.execute(query)
        }
    }
}
