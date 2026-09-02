//
//  WatchHealthStore.swift
//  BodyWatch
//
//  The watch's cheap live path: reads its own latest HR / HRV samples directly
//  from HealthKit so those metrics can freshen between phone pushes, and owns
//  the HealthKit authorization requests for both this path and the on-device
//  compute (`WatchComputeCoordinator`, which does its own reads through the
//  shared fetch leaves).
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
    /// temperature), filtered by the phone's synced permission selection so a
    /// category the user hid is never requested. Requested lazily, on the first
    /// compute after the selection changes.
    func requestComputeAuthorization(for selection: BodyHealthPermissionSelection) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read = BodyHealthReadTypes.watchComputeReadObjectTypes(for: selection)
        guard !read.isEmpty else { return }
        try? await store.requestAuthorization(toShare: [], read: read)
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
