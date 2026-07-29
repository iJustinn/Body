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
//
// The queries and the grouping/identity rules themselves live in the shared
// `BodyHealthSourceResolver` (Body + BodyWatch); this extension is the
// actor-side memoization and the localized display naming around them.
extension HealthKitFetchEngine {
    /// The phone's discovered source universe per on-watch-compute kind, as
    /// sorted disambiguated identity IDs — carried in the compute seed
    /// (`WatchComputeSeed.expectedSourceIDsByKind`) so the watch can verify an
    /// All-Sources read actually sees every source the phone aggregates before
    /// treating its own store as phone-equivalent. Reads the memoized
    /// discovery (`healthSourcesByKind`); kinds discovery never resolved are
    /// simply absent (the watch then keeps its legacy unfiltered read).
    func watchComputeExpectedSourceIDs() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for kind in BodyHealthSourceResolver.watchComputeSourceKinds {
            guard let bucket = healthSourcesByKind[kind] else { continue }
            let ids = bucket.keys.filter { $0.hasPrefix("source:") }.sorted()
            if !ids.isEmpty {
                result[kind.rawValue] = ids
            }
        }
        return result
    }
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
            let (options, sourcesByID) = BodyHealthSourceResolver.sourceOptionsAndMap(
                from: sources,
                combinesSourcesByName: combinesHealthDataSourcesByName,
                displayName: Self.displayName(for:)
            )
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
            sources: await BodyHealthSourceResolver.discoverSources(
                for: healthSampleTypes(forSourceKind: kind),
                store: healthStore,
                onFailure: { context, error in
                    Self.logTrendQueryFailure(context, error: error)
                }
            )
        )
    }

    /// The user-facing source name. Localized — unlike
    /// `BodyHealthSourceResolver.identityName(for:)`, which keys persisted
    /// option IDs and must stay locale-stable so switching the app language
    /// never drops the user's selected source.
    nonisolated private static func displayName(for source: HKSource) -> String {
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? String(localized: "Unknown Source") : trimmedName
    }
}
