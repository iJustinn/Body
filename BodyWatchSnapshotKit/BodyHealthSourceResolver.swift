//
//  BodyHealthSourceResolver.swift
//  BodyWatchSnapshotKit
//
//  Apple Health source discovery + identity, shared by Body and BodyWatch.
//  Source-selection divergence is what broke the first standalone-watch-compute
//  attempt (the watch read every source while the phone applied a per-metric
//  source predicate), so the grouping/identity rules and the selection →
//  predicate resolution live here once and both platforms compile the same
//  code. The iOS `HealthKitFetchEngine` keeps its actor-side memoization
//  (`healthSourcesByKind`, the permission-signature latch) on top of these
//  leaves; the watch resolves against the source map it discovers locally.
//

import Foundation
import HealthKit

/// A selectable Apple Health data source for one metric: either a single
/// `HKSource`, every source that shares a normalized name (a "combined"
/// option), or the all-sources / no-comparison sentinels.
///
/// Lives in the shared folder because the persisted option IDs are the
/// identity currency of source selection — the watch has to key its own
/// discovered `HKSource`s exactly the way the phone did, or a selection
/// synced from the phone would resolve to a different (or no) source.
struct BodyHealthDataSourceOption: Codable, Equatable, Identifiable {
    static let allSources = BodyHealthDataSourceOption(id: "all", name: "Apple Health")
    /// The no-comparison sentinel's ID. The option value itself
    /// (`BodyHealthDataSourceOption.noComparison`) is declared iOS-side, where
    /// its localized display name belongs; only the ID is needed here.
    static let noComparisonID = "none"
    private static let combinedSourcePrefix = "combined-name:"
    private static let customSourcePrefix = "custom:"

    let id: String
    let name: String

    var isAllSources: Bool {
        id == Self.allSources.id
    }

    var isNoComparison: Bool {
        id == Self.noComparisonID
    }

    var isCombinedSource: Bool {
        id.hasPrefix(Self.combinedSourcePrefix)
    }

    var isCustomSource: Bool {
        id.hasPrefix(Self.customSourcePrefix)
    }

    var iconBundleIdentifierHint: String? {
        if isAllSources || isNoComparison || isCombinedSource || isCustomSource {
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
        // Fixed POSIX locale, never `.current`: these keys are PERSISTED by one
        // device and rebuilt on another, and locale-sensitive folding breaks
        // that round trip (Turkish folds "IWatch" to "\u{131}watch", not
        // "iwatch") — a combined/disambiguated selection would then fail
        // strict resolution on the watch despite the source being present.
        let normalizedName = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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
        // Fixed POSIX locale — see `normalizedSourceName` for why `.current`
        // would break the cross-device round trip of persisted identities.
        let nameKey = displayName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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

    static func customSourceID(for identifier: UUID) -> String {
        customSourcePrefix + identifier.uuidString
    }
}

/// Tri-state resolution of a metric's source selection into a query
/// predicate. `.unresolved` (a specific source is selected but source
/// discovery has not succeeded for this kind this process) must SKIP the
/// query with failure semantics — otherwise a nil predicate would silently
/// query every source and show all-source data for a custom-source user
/// (H4). `.allSources` intentionally applies no source filter (all-sources
/// / no-comparison selection, or a genuinely deleted source whose discovery
/// nonetheless succeeded).
enum BodyHealthSourceQueryResolution {
    case allSources
    case predicate(NSPredicate)
    case unresolved
}

/// One sample type's discovered sources, carried out of the concurrent
/// fetch task group, tagged with its original index so the merge can
/// replay first-wins precedence in the same order as a serial loop. A
/// `nil` `sources` marks a failed query. `@unchecked Sendable` is sound
/// because `HKSource` is immutable metadata (read-only; never mutated after
/// the query returns) — HealthKit just doesn't annotate it `Sendable`. A raw
/// tuple can't be marked `@unchecked Sendable`, hence this wrapper struct.
struct IndexedSources: @unchecked Sendable {
    let index: Int
    let sources: [HKSource]?

    init(index: Int, sources: [HKSource]?) {
        self.index = index
        self.sources = sources
    }
}

/// One metric kind's discovered sources, carried out of the concurrent
/// fetch task group. A `nil` `sources` marks a failed discovery for the
/// kind. `@unchecked Sendable` is sound for the same reason as
/// `IndexedSources` above.
struct KindSources: @unchecked Sendable {
    let kind: HealthMetricKind
    let sources: [HKSource]?

    init(kind: HealthMetricKind, sources: [HKSource]?) {
        self.kind = kind
        self.sources = sources
    }
}

enum BodyHealthSourceResolver {
    /// The source-selectable kinds the on-watch compute reads — the fan-out set
    /// for the watch's per-kind source resolution AND the kinds whose
    /// discovered-source identity lists the phone carries in the compute seed
    /// (`WatchComputeSeed.expectedSourceIDsByKind`), so an All-Sources read on
    /// the watch can verify it sees the same source universe the phone
    /// aggregated.
    static let watchComputeSourceKinds: [HealthMetricKind] = [
        .heartRate, .restingHeartRate, .heartRateVariability,
        .respiratoryRate, .oxygenSaturation, .wristTemperature, .sleep
    ]

    // MARK: - Kind → sample types / permission

    /// The sample types whose sources make up a metric kind's source list. The
    /// discovery query fans over exactly these, and the resulting option IDs are
    /// what a persisted selection is matched against — so the watch MUST discover
    /// over the same set as the phone or the same source would key differently.
    /// (`.basics` is three body-measurement types; every other kind is one.)
    static func sourceSampleTypes(for kind: HealthMetricKind) -> [HKSampleType] {
        switch kind {
        case .sleep:
            return [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)].compactMap { $0 }
        case .basics:
            return [
                HKObjectType.quantityType(forIdentifier: .bodyMass),
                HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
                HKObjectType.quantityType(forIdentifier: .bodyMassIndex)
            ].compactMap { $0 }
        default:
            // Every other source-selectable kind is one quantity type, read from
            // the query descriptor so discovery can never fan over a different
            // type than the reads do. A kind that is not source-selectable (or
            // is only a member of `.basics`, like the three above) has no source
            // list of its own.
            guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
                  descriptor.isSourceSelectable,
                  descriptor.sourceKind == kind else {
                return []
            }
            return [HKObjectType.quantityType(forIdentifier: descriptor.quantityType)].compactMap { $0 }
        }
    }

    /// The permission category that gates a source-selectable metric kind — the
    /// same gate on both platforms, so a category the user hid on the phone is
    /// never discovered or queried on the watch either.
    static func permission(forSourceKind kind: HealthMetricKind) -> BodyHealthPermission {
        switch kind {
        case .sleep:
            return .sleep
        case .basics:
            return .basics
        default:
            // Every other source kind is a query-descriptor kind and carries its
            // own permission there. `.cardioFitness` resolves through the same
            // row even though it is not source-selectable, so a future caller
            // can't silently inherit the `.heart` fallback below. A kind with no
            // row of its own (the three `.basics` members, readiness, stress,
            // vitals, trainingLoad) keeps that fallback.
            guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
                  descriptor.sourceKind == kind else {
                return .heart
            }
            return descriptor.permission
        }
    }

    // MARK: - Selection resolution

    /// Resolves a metric's selected source option against the sources
    /// discovered for that kind.
    ///
    /// `discovered` is `nil` when discovery has not succeeded for the kind
    /// (never ran, or failed and kept no prior map) — the selection is
    /// unresolved, so the caller skips the query rather than falling back to
    /// all sources.
    ///
    /// `strictWhenMissing` decides the present-but-missing-id case (discovery
    /// succeeded, but the selected source is not among the results):
    /// - `false` (iOS): the source is genuinely gone, so fall back to all
    ///   sources — the phone's long-standing behavior.
    /// - `true` (watch): resolve `.unresolved` instead. The watch's HKSource
    ///   identities are its own; silently widening to every source is exactly
    ///   what made the first on-watch compute disagree with the phone, so a
    ///   selection it can't match keeps the seeded values instead.
    static func resolution(
        option: BodyHealthDataSourceOption,
        discovered: [String: [HKSource]]?,
        strictWhenMissing: Bool
    ) -> BodyHealthSourceQueryResolution {
        switch resolutionDecision(option: option, discovered: discovered, strictWhenMissing: strictWhenMissing) {
        case .allSources:
            return .allSources
        case .unresolved:
            return .unresolved
        case .sources(let sources):
            guard sources.count > 1 else {
                guard let source = sources.first else {
                    return .allSources
                }
                return .predicate(HKQuery.predicateForObjects(from: source))
            }
            let sourcePredicates = sources.map { source in
                HKQuery.predicateForObjects(from: source)
            }
            return .predicate(NSCompoundPredicate(orPredicateWithSubpredicates: sourcePredicates))
        }
    }

    /// The decision half of `resolution(option:discovered:strictWhenMissing:)`,
    /// split out and generic over the source type: every branch above the final
    /// predicate construction depends only on the option's sentinels and the
    /// SHAPE of the discovery map, never on `HKSource` itself. That makes the
    /// whole strict-vs-lenient contract unit-testable with plain stand-ins —
    /// `HKSource` has no public initializer and `HKSource.default()` raises an
    /// Objective-C exception in a test host without a HealthKit bundle identity
    /// (e.g. an unsigned simulator run), which would abort the entire process.
    /// `.sources` is non-empty by construction.
    enum SourceResolutionDecision<Source>: Equatable where Source: Equatable {
        case allSources
        case unresolved
        case sources([Source])
    }

    static func resolutionDecision<Source>(
        option: BodyHealthDataSourceOption,
        discovered: [String: [Source]]?,
        strictWhenMissing: Bool
    ) -> SourceResolutionDecision<Source> {
        guard !option.isAllSources, !option.isNoComparison else {
            return .allSources
        }

        guard let discovered else {
            return .unresolved
        }
        guard let sources = discovered[option.id], !sources.isEmpty else {
            return strictWhenMissing ? .unresolved : .allSources
        }

        return .sources(sources)
    }

    /// Registers each user-created group's `custom:` ID as the union of its
    /// members' own buckets, so a custom selection resolves through the very
    /// same `sourcesByID` path (and OR-compound predicate) a `combined-name:`
    /// selection does. Generic for the same reason `resolutionDecision` is:
    /// nothing here depends on `HKSource`.
    ///
    /// A group whose members are ALL invisible to this device registers no
    /// bucket at all rather than an empty one — that leaves the ID
    /// present-but-missing, which is exactly the absent-bucket contract
    /// `resolutionDecision` already defines: lenient (iOS) widens to all
    /// sources, strict (watch) resolves `.unresolved` and the caller keeps what
    /// it has. A PARTIALLY visible group resolves to the visible subset, the
    /// same as a combined-name group discovered on one device only.
    static func registeringCustomGroupBuckets<Source>(
        _ sourcesByID: [String: [Source]],
        customGroups: [BodyCustomHealthSourceGroup],
        identityKey: (Source) -> String
    ) -> [String: [Source]] {
        var sourcesByID = sourcesByID
        for group in customGroups {
            var members: [Source] = []
            var seenIdentityKeys: Set<String> = []
            for memberKey in group.memberIdentityKeys.sorted() {
                for source in sourcesByID["source:" + memberKey] ?? [] {
                    guard seenIdentityKeys.insert(identityKey(source)).inserted else { continue }
                    members.append(source)
                }
            }
            guard !members.isEmpty else { continue }
            sourcesByID[group.id] = members
        }
        return sourcesByID
    }

    /// Combines an optional date window with an optional source predicate into
    /// the single predicate a leaf query runs with. Shared so the watch builds
    /// byte-identical predicates to the phone for the same window + selection.
    static func combinedPredicate(
        startDate: Date? = nil,
        endDate: Date? = nil,
        sourcePredicate: NSPredicate? = nil
    ) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        if startDate != nil || endDate != nil {
            predicates.append(HKQuery.predicateForSamples(withStart: startDate, end: endDate))
        }

        if let sourcePredicate {
            predicates.append(sourcePredicate)
        }

        switch predicates.count {
        case 0:
            return nil
        case 1:
            return predicates[0]
        default:
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
    }

    // MARK: - Grouping / identity

    /// Locale-stable name used for persisted option IDs and grouping keys. A
    /// blank source name falls back to a fixed English string so switching the
    /// app language never re-keys the same HealthKit source and drops the user's
    /// selected source override. Only the caller's `displayName` is localized.
    static func identityName(for source: HKSource) -> String {
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unknown Source" : trimmedName
    }

    /// Groups discovered sources into the pickable options for one metric kind
    /// and the ID → sources map that resolves a selection into a query
    /// predicate.
    ///
    /// `displayName` stays a caller-supplied closure because the *display* name
    /// is localized (iOS falls back to a localized "Unknown Source"), while
    /// every ID and grouping key runs through the locale-stable
    /// `identityName(for:)` — the map is the part both platforms must build
    /// identically, and it must not shift with the UI language.
    ///
    /// `customGroups` only extends the MAP — the user-created options are
    /// appended by the caller that owns them (they exist whether or not this
    /// kind discovered any of their members), while resolving one still
    /// requires a bucket registered here.
    static func sourceOptionsAndMap(
        from sources: [HKSource],
        combinesSourcesByName: Bool,
        customGroups: [BodyCustomHealthSourceGroup] = [],
        displayName: (HKSource) -> String
    ) -> (options: [BodyHealthDataSourceOption], sourcesByID: [String: [HKSource]]) {
        sourceOptionsAndMap(
            from: sources, combinesSourcesByName: combinesSourcesByName, customGroups: customGroups,
            bundleIdentifier: { $0.bundleIdentifier }, identityName: { Self.identityName(for: $0) },
            displayName: displayName
        )
    }

    /// The same grouping path with value-type source fixtures: HKSource has no
    /// public initializer in an unsigned test host.
    static func sourceOptionsAndMap<Source>(
        from sources: [Source],
        combinesSourcesByName: Bool,
        customGroups: [BodyCustomHealthSourceGroup] = [],
        bundleIdentifier: (Source) -> String,
        identityName: (Source) -> String,
        displayName: (Source) -> String
    ) -> (options: [BodyHealthDataSourceOption], sourcesByID: [String: [Source]]) {
        let sortedSources = sources.sorted { lhs, rhs in
            let lhsName = displayName(lhs)
            let rhsName = displayName(rhs)
            if lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedSame {
                return bundleIdentifier(lhs) < bundleIdentifier(rhs)
            }
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        var sourcesByID: [String: [Source]] = [:]
        let duplicateNameBundleIdentifiers = Set(
            Dictionary(grouping: sortedSources, by: bundleIdentifier)
                .compactMap { identifier, sources in
                    let sourceNameKeys = Set(sources.map { source in
                        BodyHealthDataSourceOption.individualSourceIdentityKey(
                            bundleIdentifier: bundleIdentifier(source),
                            name: identityName(source)
                        )
                    })
                    return sourceNameKeys.count > 1 ? identifier : nil
                }
        )
        for source in sortedSources {
            // Register BOTH identity forms for every source — the plain
            // bundle-ID form and the name-disambiguated form — because the ID
            // was PERSISTED by whichever device's discovery ran at selection
            // time. A phone that saw two same-bundle, different-name sources
            // persisted the disambiguated form; the watch may discover only
            // the selected one, and keying it by the device-LOCAL duplicate
            // set alone would leave that persisted ID present-but-missing —
            // strict resolution then skips local reads despite the selected
            // source sitting right there. The two forms coincide (and
            // dedupe via the same bucket) whenever disambiguation isn't
            // needed.
            let plainID = BodyHealthDataSourceOption.individualSourceID(
                bundleIdentifier: bundleIdentifier(source),
                name: identityName(source),
                disambiguatesBundleIdentifier: false
            )
            let disambiguatedID = BodyHealthDataSourceOption.individualSourceID(
                bundleIdentifier: bundleIdentifier(source),
                name: identityName(source),
                disambiguatesBundleIdentifier: true
            )
            sourcesByID[plainID, default: []].append(source)
            if disambiguatedID != plainID {
                sourcesByID[disambiguatedID, default: []].append(source)
            }
        }

        let groupedSources = Dictionary(grouping: sortedSources) { source in
            BodyHealthDataSourceOption.normalizedSourceName(identityName(source))
        }
        // Register the combined-name alias for EVERY group, including
        // singletons: a `combined-name:` selection is persisted by whichever
        // device saw multiple same-named sources (typically the iPhone seeing
        // both the phone and watch apps), but another device — the watch's own
        // HealthKit discovery in particular — may see only ONE of them. Without
        // the singleton alias that persisted ID would be present-but-missing
        // here, which the watch's strict resolution treats as `.unresolved`
        // (skip all local samples — the compute frozen on seed values) and the
        // phone's lenient resolution widens to all sources. Resolving to the
        // one matching source is what the selection means on this device.
        // Display is unaffected: the `options` picker list below keeps its own
        // count-aware ID choice.
        for group in groupedSources.values {
            sourcesByID[BodyHealthDataSourceOption.combinedSourceID(for: identityName(group[0]))] = group
        }

        sourcesByID = registeringCustomGroupBuckets(
            sourcesByID,
            customGroups: customGroups,
            identityKey: { source in
                BodyHealthDataSourceOption.individualSourceIdentityKey(
                    bundleIdentifier: bundleIdentifier(source),
                    name: identityName(source)
                )
            }
        )

        let options: [BodyHealthDataSourceOption]
        if combinesSourcesByName {
            options = groupedSources.values.map { group in
                let optionID = group.count > 1
                    ? BodyHealthDataSourceOption.combinedSourceID(for: identityName(group[0]))
                    : BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: bundleIdentifier(group[0]),
                        name: identityName(group[0]),
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(bundleIdentifier(group[0]))
                    )
                return BodyHealthDataSourceOption(
                    id: optionID,
                    name: BodyHealthDataSourceOption.combinedSourceDisplayName(for: displayName(group[0]))
                )
            }
        } else {
            options = sortedSources.map { source in
                return BodyHealthDataSourceOption(
                    id: BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: bundleIdentifier(source),
                        name: identityName(source),
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(bundleIdentifier(source))
                    ),
                    name: displayName(source)
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

    // MARK: - Discovery queries

    /// Returns `nil` when ANY per-sample-type source query fails (device
    /// locked, store unavailable) rather than genuinely returning no sources —
    /// the caller fails the whole kind so an unresolved source selection keeps
    /// the cache instead of silently querying all sources (H4).
    static func discoverSources(
        for sampleTypes: [HKSampleType],
        store: any BodyHealthQuerying,
        onFailure: ((String, Error?) -> Void)? = nil
    ) async -> [HKSource]? {
        // Fan the per-sample-type `HKSourceQuery` round-trips out concurrently
        // instead of awaiting them one at a time. Results are collected by
        // index so the merge below can replay the exact same first-wins,
        // iteration-order precedence as the old serial loop.
        var resultsByIndex = [[HKSource]?](repeating: [], count: sampleTypes.count)
        await withTaskGroup(of: IndexedSources.self) { group in
            for (index, sampleType) in sampleTypes.enumerated() {
                group.addTask {
                    IndexedSources(
                        index: index,
                        sources: await discoverSources(for: sampleType, store: store, onFailure: onFailure)
                    )
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

    /// One sample type's sources. `nil` marks a query failure OR cancellation
    /// (including the caller losing the race against its own deadline);
    /// `onFailure` receives the query context so the caller can log a genuine
    /// HealthKit failure its own way. Cancellation is not reported through
    /// `onFailure` — it is not a query failure, and the store's own
    /// `BodyQueryResumeBox` already stops the in-flight query.
    static func discoverSources(
        for sampleType: HKSampleType,
        store: any BodyHealthQuerying,
        onFailure: ((String, Error?) -> Void)? = nil
    ) async -> [HKSource]? {
        switch await store.sources(for: sampleType) {
        case .failure(let error):
            onFailure?("sources:\(sampleType.identifier)", error)
            return nil
        case .cancelled:
            return nil
        case .success(let sources):
            return sources
        }
    }
}
