//
//  WatchSourceResolver.swift
//  BodyWatch
//
//  Turns the phone's synced per-metric source selection (carried in the compute
//  seed) into the predicate a watch-side HealthKit read may run with — the one
//  place on the watch that does so, shared by the delta compute
//  (`WatchDeltaFetcher`) and the live HR/HRV path (`WatchHealthStore`).
//
//  Resolution is STRICT (`strictWhenMissing: true`): if the user picked a
//  specific source on the phone and this watch can't match it among its own
//  `HKSource`s — or source discovery failed — the read is SKIPPED and the
//  existing value stands. The alternative (a nil predicate, i.e. every source)
//  is what made the June 2026 standalone compute disagree with the phone, and
//  it would equally corrupt the live path: a user comparing a chest strap
//  against the watch would suddenly see the watch's own heart rate.
//

import Foundation
import HealthKit

/// Whether a watch-side read may run, and with which source filter. `.skip`
/// covers both "the phone hid this category" and "the selected source is
/// unresolvable here" — in both cases the caller keeps what it already has.
/// `@unchecked Sendable`: the only payload is an `NSPredicate` built at the
/// resolution site and never mutated afterwards, so it is read-only across the
/// task-group hop in `reads(for:...)`.
enum WatchSourceRead: @unchecked Sendable {
    case skip
    case run(NSPredicate?)
}

enum WatchSourceResolver {
    /// Resolves one metric kind. `nil` `selection` (no seed yet) keeps the
    /// pre-compute behavior: read every source, exactly as the live path did
    /// before the phone ever synced a selection.
    ///
    /// `expectedSourceIDsByKind` (from the seed) is the phone's own discovered
    /// source universe per kind: an All-Sources read is only phone-equivalent
    /// when this watch can see every source the phone aggregates, so the read
    /// is validated against it before running unfiltered.
    static func read(
        for kind: HealthMetricKind,
        selection: BodyHealthDataSourceSelection?,
        expectedSourceIDsByKind: [String: [String]]?,
        customGroups: [BodyCustomHealthSourceGroup],
        permission: BodyHealthPermissionSelection,
        store: any BodyHealthQuerying
    ) async -> WatchSourceRead {
        guard permission.includes(BodyHealthSourceResolver.permission(forSourceKind: kind)) else {
            return .skip
        }
        guard let selection else { return .run(nil) }

        let option = selection.option(for: kind)
        // All Sources / No Comparison run unfiltered — but only after checking
        // that "all sources" MEANS THE SAME THING here as on the phone. The
        // phone's aggregate can include phone-only or third-party sources whose
        // samples never replicate to this watch; querying just the watch-local
        // subset would return a "successful" partial series that the splice
        // would then treat as authoritative, deleting the phone-seeded points
        // and recomputing Readiness from incomplete data. When any
        // phone-expected source is missing locally, the read is skipped and
        // the seeded values stand. An absent expected list (older phone build,
        // or discovery never ran) keeps the legacy unfiltered read.
        guard !option.isAllSources, !option.isNoComparison else {
            return await allSourcesRead(
                for: kind,
                expectedSourceIDs: expectedSourceIDsByKind?[kind.rawValue],
                customGroups: customGroups,
                store: store
            )
        }

        let sampleTypes = BodyHealthSourceResolver.sourceSampleTypes(for: kind)
        guard !sampleTypes.isEmpty,
              let sources = await BodyHealthSourceResolver.discoverSources(
                  for: sampleTypes,
                  store: store
              ) else {
            return .skip
        }

        // `combinesSourcesByName` is deliberately NOT threaded through from the
        // seed: it only shapes the returned `options` list (which this discards),
        // never `sourcesByID`, which always carries both the individual and the
        // combined-by-name IDs. The stored option ID the user picked on the
        // phone already encodes which of the two they chose, so keying by it is
        // sufficient — and passing the flag would suggest a dependency that
        // isn't there.
        // A custom group only some of whose members this watch can see resolves
        // to the visible subset — the same partial-membership behavior a
        // combined-name selection has here. Zero visible members registers no
        // bucket, so strict resolution skips and the seeded values stand.
        let (_, sourcesByID) = BodyHealthSourceResolver.sourceOptionsAndMap(
            from: sources,
            combinesSourcesByName: false,
            customGroups: customGroups,
            // The locale-stable IDENTITY name, never a localized display name:
            // the option IDs must key exactly as the phone keyed them.
            displayName: BodyHealthSourceResolver.identityName(for:)
        )
        switch BodyHealthSourceResolver.resolution(
            option: option,
            discovered: sourcesByID,
            strictWhenMissing: true
        ) {
        case .allSources:
            return .run(nil)
        case .predicate(let predicate):
            return .run(predicate)
        case .unresolved:
            return .skip
        }
    }

    /// Batch form for the compute's input kinds. Fans the per-kind resolution
    /// out concurrently instead of awaiting one kind at a time, the same
    /// reasoning as the phone's `fetchHealthDataSourceOptions`: each kind's
    /// `read(for:...)` is its own round trip of `HKSourceQuery`s.
    static func reads(
        for kinds: [HealthMetricKind],
        selection: BodyHealthDataSourceSelection?,
        expectedSourceIDsByKind: [String: [String]]?,
        customGroups: [BodyCustomHealthSourceGroup],
        permission: BodyHealthPermissionSelection,
        store: any BodyHealthQuerying
    ) async -> [HealthMetricKind: WatchSourceRead] {
        await withTaskGroup(of: (HealthMetricKind, WatchSourceRead).self) { group in
            for kind in kinds {
                group.addTask {
                    let result = await read(
                        for: kind,
                        selection: selection,
                        expectedSourceIDsByKind: expectedSourceIDsByKind,
                        customGroups: customGroups,
                        permission: permission,
                        store: store
                    )
                    return (kind, result)
                }
            }

            var reads: [HealthMetricKind: WatchSourceRead] = [:]
            for await (kind, result) in group {
                reads[kind] = result
            }
            return reads
        }
    }

    /// The All-Sources validation described in `read(for:...)`: unfiltered only
    /// when every source the PHONE discovered for this kind is also visible to
    /// this watch's HealthKit (compared by the shared disambiguated identity
    /// IDs, which every discovered source registers).
    private static func allSourcesRead(
        for kind: HealthMetricKind,
        expectedSourceIDs: [String]?,
        customGroups: [BodyCustomHealthSourceGroup],
        store: any BodyHealthQuerying
    ) async -> WatchSourceRead {
        guard let expectedSourceIDs, !expectedSourceIDs.isEmpty else {
            return .run(nil)
        }

        let sampleTypes = BodyHealthSourceResolver.sourceSampleTypes(for: kind)
        guard !sampleTypes.isEmpty,
              let sources = await BodyHealthSourceResolver.discoverSources(
                  for: sampleTypes,
                  store: store
              ) else {
            return .skip
        }
        let (_, sourcesByID) = BodyHealthSourceResolver.sourceOptionsAndMap(
            from: sources,
            combinesSourcesByName: false,
            customGroups: customGroups,
            displayName: BodyHealthSourceResolver.identityName(for:)
        )
        let visible = Set(sourcesByID.keys)
        return expectedSourceIDs.allSatisfy(visible.contains) ? .run(nil) : .skip
    }
}
