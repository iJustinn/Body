//
//  WatchHealthStore.swift
//  BodyWatch
//
//  The watch's cheap live path: reads its own latest HR / HRV samples directly
//  from HealthKit so those metrics can freshen between phone pushes, and owns
//  the HealthKit authorization requests for both this path and the on-device
//  compute (`WatchComputeCoordinator`, which does its own reads through the
//  shared fetch leaves). It also reads the "Last 8 hours" charts
//  (`intradayBuckets`): HR / HRV behind the same source filter as the live
//  values, and the Steps and Active Energy slot totals behind the compute's
//  movement source rule.
//
//  Source parity matters here too: once the phone has synced a specific source
//  selection, the live reads run behind the same strict-resolved predicate the
//  compute uses (`WatchSourceResolver`), so this path can't surface a source the
//  user excluded on the phone.
//

import Foundation
import HealthKit

actor WatchHealthStore {
    private let store = HKHealthStore()

    /// Authorizes the live HR/HRV reads only — the minimum this path needs.
    func requestLiveAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var read: Set<HKObjectType> = []
        [HKQuantityTypeIdentifier.heartRate, .heartRateVariabilitySDNN]
            .compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { read.insert($0) }
        guard !read.isEmpty else { return }
        try? await store.requestAuthorization(toShare: [], read: read)
    }

    /// Authorizes the broader read set the on-device compute needs (workouts +
    /// effort, the three heart types, respiratory, blood oxygen, sleep, wrist
    /// temperature, steps, active energy and resting energy for their own
    /// cards, steps and active energy also for Stress's movement mask, and for
    /// Stress the heartbeat series and Recovery HRV), filtered by the phone's
    /// synced permission selection so a category the user hid is never
    /// requested. Requested lazily, on the first compute after the selection
    /// changes.
    func requestComputeAuthorization(for selection: BodyHealthPermissionSelection) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read = BodyHealthReadTypes.watchComputeReadObjectTypes(for: selection)
        guard !read.isEmpty else { return }
        try? await store.requestAuthorization(toShare: [], read: read)
    }

    /// Whether the compute read set has ALREADY been put to the user, so reading
    /// it can never raise an authorization sheet. HealthKit persists this, which
    /// is what lets a background launch (the workout observer, a pushed context,
    /// a scheduled refresh) decide without the model's in-memory authorization
    /// task: those paths must never prompt, and must not read before a prompt
    /// has happened.
    func isComputeAuthorizationSettled(for selection: BodyHealthPermissionSelection) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let read = BodyHealthReadTypes.watchComputeReadObjectTypes(for: selection)
        guard !read.isEmpty else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: read)
        return status == .unnecessary
    }

    /// The phone's seeded source selection, as the live and chart reads resolve
    /// against it. Nil when a seed EXISTS on disk but wouldn't decode (corrupt
    /// bytes, or a schema this build refuses): the phone has synced a source
    /// selection we can no longer read. Falling through to a nil selection
    /// would widen the reads to EVERY source — precisely the divergence H1
    /// exists to prevent — so callers skip instead and keep what's on screen.
    /// Only a watch that has genuinely never received a seed keeps the legacy
    /// all-sources behavior (`selection` nil, `settings` nil).
    private struct SeededSelection {
        let selection: BodyHealthDataSourceSelection?
        let customGroups: [BodyCustomHealthSourceGroup]
        let expectedSourceIDsByKind: [String: [String]]?
        let settings: WatchComputeSettings?
    }

    private func seededSelection() -> SeededSelection? {
        let seed = WatchComputeSeedStore.load()
        if seed == nil, WatchComputeSeedStore.hasStoredSeed() {
            return nil
        }
        return SeededSelection(
            selection: seed.map {
                BodyHealthDataSourceSelection.storedValue(from: $0.settings.healthDataSourceSelectionRaw)
            },
            customGroups: BodyCustomHealthSourceGroupStore.groups(
                from: seed?.settings.customHealthSourceGroupsRaw ?? ""
            ),
            expectedSourceIDsByKind: seed?.expectedSourceIDsByKind,
            settings: seed?.settings
        )
    }

    /// The live source filters for HR and HRV, resolved from the phone's seeded
    /// selection. Resolved once per refresh (inside this actor, off the main
    /// actor) and handed to both reads below.
    func liveSourceReads(
        permission: BodyHealthPermissionSelection
    ) async -> (heartRate: WatchSourceRead, heartRateVariability: WatchSourceRead) {
        guard let seeded = seededSelection() else {
            return (.skip, .skip)
        }
        let selection = seeded.selection
        let customGroups = seeded.customGroups
        let seed = seeded

        async let heartRate = WatchSourceResolver.read(
            for: .heartRate,
            selection: selection,
            expectedSourceIDsByKind: seed.expectedSourceIDsByKind,
            customGroups: customGroups,
            permission: permission,
            store: store
        )
        async let heartRateVariability = WatchSourceResolver.read(
            for: .heartRateVariability,
            selection: selection,
            expectedSourceIDsByKind: seed.expectedSourceIDsByKind,
            customGroups: customGroups,
            permission: permission,
            store: store
        )
        return await (heartRate, heartRateVariability)
    }

    func latestHeartRate(source: WatchSourceRead = .run(nil)) async -> (value: Double, measuredAt: Date)? {
        await latestQuantity(
            .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            freshnessLimit: WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.heartRate),
            source: source
        )
    }

    func latestHRV(source: WatchSourceRead = .run(nil)) async -> (value: Double, measuredAt: Date)? {
        await latestQuantity(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            freshnessLimit: WatchMetricKindKey.liveFreshnessLimit(forKind: WatchMetricKindKey.heartRateVariability),
            source: source
        )
    }

    /// What one "Last 8 hours" kind reads: its quantity type and unit, the
    /// phone permission that gates it, how its slots aggregate (readings as
    /// min / average / max, totals as a sum), and whether it is energy. Pure,
    /// so the gate and the rows are testable without HealthKit. Resting Energy
    /// has no chart: the iPhone has no Day View for it either.
    struct IntradayQuery: Equatable {
        enum Aggregation: Equatable {
            case discrete
            case cumulativeSum
        }

        /// The kind the source resolver resolves (its descriptor row).
        let metricKind: HealthMetricKind
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let permission: BodyHealthPermission
        let aggregation: Aggregation
        /// The slot sums are kilocalories to be shown in the iPhone's kcal/kJ
        /// setting, like the card's headline.
        let isEnergy: Bool
    }

    /// The row for `kind`, or nil for a kind without a chart. HR and HRV spell
    /// the live path's literals; the daily total kinds come from the shared
    /// descriptor table the iPhone and the compute query from.
    nonisolated static func intradayQuery(forKind kind: String) -> IntradayQuery? {
        switch kind {
        case WatchMetricKindKey.heartRate:
            return IntradayQuery(
                metricKind: .heartRate,
                identifier: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                permission: .heart,
                aggregation: .discrete,
                isEnergy: false
            )
        case WatchMetricKindKey.heartRateVariability:
            // SDNN, the same type the HRV headline reads.
            return IntradayQuery(
                metricKind: .heartRateVariability,
                identifier: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                permission: .heart,
                aggregation: .discrete,
                isEnergy: false
            )
        case WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy:
            guard let metricKind = HealthMetricKind(rawValue: kind),
                  let descriptor = HealthMetricQueryDescriptor.descriptor(for: metricKind) else { return nil }
            return IntradayQuery(
                metricKind: metricKind,
                identifier: descriptor.quantityType,
                unit: descriptor.unit,
                permission: descriptor.permission,
                aggregation: .cumulativeSum,
                isEnergy: metricKind == .activeEnergy
            )
        default:
            return nil
        }
    }

    /// The "Last 8 hours" chart's slots for `kind` over `window`, or nil to
    /// keep what's on screen (see `WatchIntradayChartStore.Load`). One
    /// statistics collection query with 30 minute intervals anchored at the
    /// window's start. HR and HRV read min / average / max per slot: like
    /// `mostRecentQuantity`, a statistics query resolves the `HKQuantitySeries`
    /// a workout stores its heart rate in beat by beat, where a sample query
    /// would return one blob per workout. Steps and Active Energy read each
    /// slot's sum, like the hourly leaf behind Stress's movement mask: a slot
    /// with no sum, or a sum at or below zero, is absent rather than a zero
    /// bar. The predicate keeps HealthKit's default overlap
    /// matching, so a series that started before the window still contributes
    /// its in-window beats; the earlier ones fall into slots that are never
    /// enumerated.
    ///
    /// Sources: HR and HRV follow the live values' strict resolution. The two
    /// totals follow the compute's movement rule (`WatchDeltaFetcher`):
    /// resolved WITHOUT the phone's expected source universe, so a pinned or
    /// custom selection stays strict but All Sources reads what this watch can
    /// see, since the iPhone's pedometer never reaches the watch.
    func intradayBuckets(
        kind: String,
        permission: BodyHealthPermissionSelection,
        window: WatchIntradayWindow
    ) async -> [WatchIntradayBucket]? {
        guard let query = Self.intradayQuery(forKind: kind) else { return [] }
        guard let type = HKQuantityType.quantityType(forIdentifier: query.identifier) else { return nil }

        let source: WatchSourceRead
        var energyUnitPreference = BodyValueFormat.EnergyUnitPreference.kilocalories
        switch query.aggregation {
        case .discrete:
            let sourceReads = await liveSourceReads(permission: permission)
            source = kind == WatchMetricKindKey.heartRate ? sourceReads.heartRate : sourceReads.heartRateVariability
        case .cumulativeSum:
            // A seed on disk that won't decode: skip, as the live reads do.
            guard let seeded = seededSelection() else { return nil }
            source = await WatchSourceResolver.read(
                for: query.metricKind,
                selection: seeded.selection,
                expectedSourceIDsByKind: nil,
                customGroups: seeded.customGroups,
                permission: permission,
                store: store
            )
            if let settings = seeded.settings {
                energyUnitPreference = WatchComputeAssembly.energyUnitPreference(for: settings)
            }
        }

        let sourcePredicate: NSPredicate?
        switch source {
        case .run(let predicate):
            sourcePredicate = predicate
        case .unavailable:
            // No source for this kind on this watch at all: nothing to chart.
            return []
        case .skip:
            // The phone's selection couldn't be matched this time, which also
            // covers a source discovery that failed briefly. Reading anyway
            // would widen to every source, so keep the chart on screen.
            return nil
        }

        let predicate = BodyHealthSourceResolver.combinedPredicate(
            startDate: window.start,
            endDate: nil,
            sourcePredicate: sourcePredicate
        )

        var interval = DateComponents()
        interval.minute = Int(WatchIntradayWindow.slotLength / 60)
        let options: HKStatisticsOptions = query.aggregation == .discrete
            ? [.discreteAverage, .discreteMin, .discreteMax]
            : .cumulativeSum
        let outcome = await store.statisticsCollection(
            BodyStatisticsCollectionRequest(
                quantityType: type,
                predicate: predicate,
                options: options,
                anchorDate: window.start,
                intervalComponents: interval
            )
        )
        // A locked (off wrist) watch has the query fail; keep the chart.
        guard case .success(let collection) = outcome else { return nil }

        let unit = query.unit
        // The descriptor's value transform (identity for both today), so a
        // slot total is shaped exactly like the compute's hourly and daily sums.
        let transform = HealthMetricQueryDescriptor.descriptor(for: query.metricKind)?.valueTransform ?? { $0 }
        var buckets: [WatchIntradayBucket] = []
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
            switch query.aggregation {
            case .discrete:
                guard let average = statistics.averageQuantity()?.doubleValue(for: unit),
                      let minimum = statistics.minimumQuantity()?.doubleValue(for: unit),
                      let maximum = statistics.maximumQuantity()?.doubleValue(for: unit),
                      average.isFinite, minimum.isFinite, maximum.isFinite else {
                    return
                }
                buckets.append(WatchIntradayBucket(start: statistics.startDate, minimum: minimum, maximum: maximum, average: average))
            case .cumulativeSum:
                guard let raw = statistics.sumQuantity()?.doubleValue(for: unit) else { return }
                var sum = transform(raw)
                guard sum.isFinite, sum > 0 else { return }
                if query.isEnergy {
                    sum = BodyValueFormat.energyValue(kilocalories: sum, energyUnitPreference: energyUnitPreference).value
                }
                buckets.append(WatchIntradayBucket(start: statistics.startDate, minimum: sum, maximum: sum, average: sum))
            }
        }

        return buckets
    }

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        freshnessLimit: TimeInterval,
        source: WatchSourceRead
    ) async -> (value: Double, measuredAt: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        // `.skip`: the phone's selected source can't be matched on this watch
        // (or the category is hidden). Reading anyway would silently widen to
        // every source, so keep the value already on screen.
        guard case .run(let sourcePredicate) = source else { return nil }

        // Live readings only: a sample older than this kind's freshness limit
        // is stale sensor data (watch off-wrist, sensor off) and must not
        // masquerade as current — returning nil keeps the value the iPhone
        // pushed. The window is per-kind (HR ages fast, HRV slowly) so the
        // accepted sample matches what `WatchMetricsModel.isStale` considers
        // fresh and can't wedge the live-read loop.
        let windowStart = Date().addingTimeInterval(-freshnessLimit)
        let predicate = BodyHealthSourceResolver.combinedPredicate(
            startDate: windowStart,
            endDate: nil,
            sourcePredicate: sourcePredicate
        )

        if identifier == .heartRate {
            // The watch stores workout heart rate as `HKQuantitySeries`
            // samples, so a plain `HKSampleQuery` (below) returns one
            // aggregated entry per series blob instead of the newest beat.
            // A discrete-most-recent statistics query resolves the series at
            // datum granularity, so it is used here to get the actual latest
            // reading during a workout.
            let outcome = await BodyHealthQuantityFetch.mostRecentQuantity(
                store: store,
                quantityType: type,
                predicate: predicate
            )
            guard case .success(let result) = outcome, let result else { return nil }
            return (result.quantity.doubleValue(for: unit), result.endDate)
        }

        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }
            store.execute(query)
        }
    }
}
