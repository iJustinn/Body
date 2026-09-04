//
//  HealthKitFetchEngine+SourceOptions.swift
//  Body
//

import Foundation
import HealthKit

/// One individually discovered Apple Health source, flattened across every
/// metric kind — the pool the custom-source membership UI picks from. Carries
/// the locale-stable `identityKey` a `BodyCustomHealthSourceGroup` stores
/// alongside the localized name the UI shows. A plain value struct, so it
/// crosses the engine's actor boundary.
struct BodyDiscoveredHealthSource: Equatable, Identifiable {
    let identityKey: String
    let name: String
    let bundleIdentifier: String

    var id: String { identityKey }
}

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
    /// Every individual source discovered for ANY kind, deduped by identity key
    /// — the membership pool for user-created custom sources. Union rather than
    /// per-kind because a group is one selection reused across metrics: a scale
    /// that only ever shows up under `.basics` still has to be pickable.
    func discoveredIndividualHealthSources() -> [BodyDiscoveredHealthSource] {
        var sourcesByIdentityKey: [String: BodyDiscoveredHealthSource] = [:]
        for bucket in healthSourcesByKind.values {
            for source in bucket.values.flatMap({ $0 }) {
                let identityKey = BodyHealthDataSourceOption.individualSourceIdentityKey(
                    bundleIdentifier: source.bundleIdentifier,
                    name: BodyHealthSourceResolver.identityName(for: source)
                )
                guard sourcesByIdentityKey[identityKey] == nil else { continue }
                sourcesByIdentityKey[identityKey] = BodyDiscoveredHealthSource(
                    identityKey: identityKey,
                    name: Self.displayName(for: source),
                    bundleIdentifier: source.bundleIdentifier
                )
            }
        }

        return sourcesByIdentityKey.values.sorted { lhs, rhs in
            if lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame {
                return lhs.identityKey < rhs.identityKey
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func fetchHealthDataSourceOptions(calendar: Calendar) async -> [HealthMetricKind: [BodyHealthDataSourceOption]]? {
        let contextRevision = queryContextRevision
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

        // A settings edit can reenter this actor while source queries suspend.
        // Never install buckets grouped for the retired configuration.
        guard queryContextRevision == contextRevision else { return nil }

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
                customGroups: customHealthSourceGroups,
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

    /// Identity-only provenance for cache admission, not another source picker
    /// cache. Missing kinds mean unresolved discovery; an empty known bucket
    /// is authoritative. Names are used only through the shared identity rule.
    func cacheSourceIdentities() -> [HealthMetricKind: [String: [String]]] {
        healthSourcesByKind.mapValues { bucket in
            var identities = bucket.mapValues { sources in
                Array(Set(sources.map {
                    BodyHealthDataSourceOption.individualSourceIdentityKey(
                        bundleIdentifier: $0.bundleIdentifier,
                        name: BodyHealthSourceResolver.identityName(for: $0)
                    )
                })).sorted()
            }
            identities[BodyHealthDataSourceOption.allSources.id] = Array(Set(identities.values.flatMap { $0 })).sorted()
            identities[BodyHealthDataSourceOption.noComparison.id] = []
            return identities
        }
    }

    /// Discovers sources for just `kinds` and merges them into the memoized map
    /// — the focused counterpart of `fetchHealthDataSourceOptions` for a
    /// headless caller (the background metric-warning evaluation) that needs a
    /// pinned source to RESOLVE without paying for the full option fan-out.
    /// Kinds already discovered this process, not source-selectable, without
    /// permission, or without sample types are skipped; a kind whose query
    /// fails simply stays absent, so its selection remains `.unresolved` and
    /// the leaf fetch skips with failure semantics (H4). Deliberately does NOT
    /// record `fetchedHealthDataSourcePermissionRawValue`: this is a partial
    /// discovery and must never short-circuit the full one.
    func discoverHealthSources(for kinds: Set<HealthMetricKind>) async {
        let pending = kinds.filter { kind in
            healthSourcesByKind[kind] == nil
                && kind.supportsHealthDataSourceSelection
                && permissionSelection.includes(healthPermission(forSourceKind: kind))
                && !healthSampleTypes(forSourceKind: kind).isEmpty
        }
        guard !pending.isEmpty else { return }

        let kindSources = await withTaskGroup(of: KindSources.self) { group in
            for kind in pending {
                group.addTask { await self.fetchKindSources(for: kind) }
            }

            var collected: [KindSources] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for kindSource in kindSources {
            guard let sources = kindSource.sources else { continue }
            let (_, sourcesByID) = BodyHealthSourceResolver.sourceOptionsAndMap(
                from: sources,
                combinesSourcesByName: combinesHealthDataSourcesByName,
                customGroups: customHealthSourceGroups,
                displayName: Self.displayName(for:)
            )
            healthSourcesByKind[kindSource.kind] = sourcesByID
        }
    }

    private func fetchKindSources(for kind: HealthMetricKind) async -> KindSources {
        KindSources(kind: kind, sources: await discoverKindSourcesBudgeted(for: kind))
    }

    /// One kind's source discovery, spending a query-pool permit and raced
    /// against `activityRingQueryTimeout`, exactly like `runActivityRingDayQuery`
    /// in `+ActivityRings.swift`. Shared by `fetchKindSources` (used by
    /// `fetchHealthDataSourceOptions`) and, through it, `discoverHealthSources(for:)`
    /// — the only two callers of kind-level source discovery.
    ///
    /// Returns `nil` on a genuine query failure, cancellation, or a timeout, so
    /// the caller keeps its prior source map rather than treating a stalled
    /// discovery as "no sources" (H4). Only the timeout case is logged here — a
    /// genuine per-sample-type failure is already logged, with a more specific
    /// context, by `BodyHealthSourceResolver.discoverSources`'s `onFailure`.
    ///
    /// Residual: `.basics` fans out over three sample types
    /// (`bodyMass`/`bodyFatPercentage`/`bodyMassIndex`) inside
    /// `BodyHealthSourceResolver.discoverSources` unbudgeted — that fan-out lives
    /// in the shared kit, which cannot reference `HealthKitQueryPool`, so this
    /// permit covers the kind as a whole rather than each of its leaf queries.
    /// The ceiling this budgets to is therefore about 3x the permit count for
    /// that one kind, not exact.
    private func discoverKindSourcesBudgeted(for kind: HealthMetricKind) async -> [HKSource]? {
        let semaphore = HealthKitQueryPool.current.semaphore
        await semaphore.acquire()
        defer { semaphore.release() }
        guard !Task.isCancelled else { return nil }

        let healthStore = healthStore
        let sampleTypes = healthSampleTypes(forSourceKind: kind)
        let queryTask = Task {
            await BodyHealthSourceResolver.discoverSources(
                for: sampleTypes,
                store: healthStore,
                onFailure: { context, error in
                    Self.logTrendQueryFailure(context, error: error)
                }
            )
        }
        let deadlineTask = Task {
            try? await ContinuousClock().sleep(for: Self.activityRingQueryTimeout)
            queryTask.cancel()
        }

        let sources = await withTaskCancellationHandler {
            await queryTask.value
        } onCancel: {
            queryTask.cancel()
        }
        deadlineTask.cancel()

        if sources == nil, queryTask.isCancelled, !Task.isCancelled {
            // The only way `queryTask` ends up cancelled while this task
            // itself is not is the deadline winning the race.
            Self.logTrendQueryFailure("sources:\(kind)", error: nil)
        }

        return sources
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
