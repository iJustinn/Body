//
//  WatchHealthStore.swift
//  BodyWatch
//
//  The watch's cheap live path: reads its own latest HR / HRV samples directly
//  from HealthKit so those metrics can freshen between phone pushes, and owns
//  the HealthKit authorization requests for both this path and the on-device
//  compute (`WatchComputeCoordinator`, which does its own reads through the
//  shared fetch leaves). It also reads the "Last 8 hours" HR / HRV charts
//  (`intradayBuckets`) behind the same source filter as the live values.
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
    /// temperature, and for Stress the heartbeat series, Recovery HRV, steps
    /// and active energy), filtered by the phone's synced permission selection so a
    /// category the user hid is never requested. Requested lazily, on the first
    /// compute after the selection changes.
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

    /// The live source filters for HR and HRV, resolved from the phone's seeded
    /// selection. Resolved once per refresh (inside this actor, off the main
    /// actor) and handed to both reads below.
    func liveSourceReads(
        permission: BodyHealthPermissionSelection
    ) async -> (heartRate: WatchSourceRead, heartRateVariability: WatchSourceRead) {
        let seed = WatchComputeSeedStore.load()
        // A seed EXISTS on disk but wouldn't decode (corrupt bytes, or a schema
        // this build refuses): the phone has synced a source selection we can no
        // longer read. Falling through to a nil selection would widen the live
        // reads to EVERY source — precisely the divergence H1 exists to prevent
        // — so skip instead and keep what's on screen. Only a watch that has
        // genuinely never received a seed keeps the legacy all-sources behavior.
        if seed == nil, WatchComputeSeedStore.hasStoredSeed() {
            return (.skip, .skip)
        }
        // No seed yet (a watch that has never received one) → the pre-compute
        // behavior: read every source.
        let selection = seed.map {
            BodyHealthDataSourceSelection.storedValue(from: $0.settings.healthDataSourceSelectionRaw)
        }
        let customGroups = BodyCustomHealthSourceGroupStore.groups(
            from: seed?.settings.customHealthSourceGroupsRaw ?? ""
        )

        async let heartRate = WatchSourceResolver.read(
            for: .heartRate,
            selection: selection,
            expectedSourceIDsByKind: seed?.expectedSourceIDsByKind,
            customGroups: customGroups,
            permission: permission,
            store: store
        )
        async let heartRateVariability = WatchSourceResolver.read(
            for: .heartRateVariability,
            selection: selection,
            expectedSourceIDsByKind: seed?.expectedSourceIDsByKind,
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

    /// The "Last 8 hours" chart's slots for HR or HRV over `window`, or nil to
    /// keep what's on screen (see `WatchIntradayChartStore.Load`). One
    /// statistics collection query with 30 minute intervals anchored at the
    /// window's start: like `mostRecentQuantity`, a statistics query resolves
    /// the `HKQuantitySeries` a workout stores its heart rate in beat by beat,
    /// where a sample query would return one blob per workout. The predicate
    /// keeps HealthKit's default overlap matching, so a series that started
    /// before the window still contributes its in-window beats; the earlier
    /// ones fall into slots that are never enumerated.
    func intradayBuckets(
        kind: String,
        permission: BodyHealthPermissionSelection,
        window: WatchIntradayWindow
    ) async -> [WatchIntradayBucket]? {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        switch kind {
        case WatchMetricKindKey.heartRate:
            identifier = .heartRate
            unit = HKUnit.count().unitDivided(by: .minute())
        case WatchMetricKindKey.heartRateVariability:
            // SDNN, the same type the HRV headline reads.
            identifier = .heartRateVariabilitySDNN
            unit = .secondUnit(with: .milli)
        default:
            return []
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        let sourceReads = await liveSourceReads(permission: permission)
        let source = kind == WatchMetricKindKey.heartRate ? sourceReads.heartRate : sourceReads.heartRateVariability
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

        var interval = DateComponents()
        interval.minute = Int(WatchIntradayWindow.slotLength / 60)
        let outcome = await store.statisticsCollection(
            BodyStatisticsCollectionRequest(
                quantityType: type,
                predicate: BodyHealthSourceResolver.combinedPredicate(
                    startDate: window.start,
                    endDate: nil,
                    sourcePredicate: sourcePredicate
                ),
                options: [.discreteAverage, .discreteMin, .discreteMax],
                anchorDate: window.start,
                intervalComponents: interval
            )
        )
        // A locked (off wrist) watch has the query fail; keep the chart.
        guard case .success(let collection) = outcome else { return nil }

        var buckets: [WatchIntradayBucket] = []
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
            guard let average = statistics.averageQuantity()?.doubleValue(for: unit),
                  let minimum = statistics.minimumQuantity()?.doubleValue(for: unit),
                  let maximum = statistics.maximumQuantity()?.doubleValue(for: unit),
                  average.isFinite, minimum.isFinite, maximum.isFinite else {
                return
            }
            buckets.append(WatchIntradayBucket(start: statistics.startDate, minimum: minimum, maximum: maximum, average: average))
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
