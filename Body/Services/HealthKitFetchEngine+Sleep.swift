//
//  HealthKitFetchEngine+Sleep.swift
//  Body
//

import Foundation
import HealthKit

// Sleep summary, daily history, and per-sleep-day vitals hydration.
// Split out of `HealthKitFetchEngine.swift` to keep the main file focused on
// orchestration and shared helpers. These actor methods call into shared
// predicate / interval / permission helpers that live on the main engine
// file with internal access so this extension can reach them.
extension HealthKitFetchEngine {
    func fetchSleepSummary(calendar: Calendar) async -> QueryOutcome<SleepSummary> {
        timeZoneLedger.recordCurrentZone()
        guard permissionSelection.includes(.sleep) else {
            return .success(nil)
        }

        guard HKObjectType.categoryType(forIdentifier: .sleepAnalysis) != nil else {
            return .success(nil)
        }
        if sourceSelectionUnresolved(for: .sleep) {
            return .failure
        }

        let endDate = anchorDate ?? Date()
        let startDate = calendar.date(byAdding: .day, value: -14, to: endDate) ?? endDate.addingTimeInterval(-1_209_600)
        nonisolated(unsafe) let predicate = combinedPredicate(startDate: startDate, endDate: endDate, sourceKind: .sleep)
        nonisolated(unsafe) let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let showsSubMinuteAwakeStages = BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()
        let showsLeadingTrailingAwakeStages = BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()

        let store = healthStore
        let samplesOutcome = await trackedExternalHealthQuery(cancelledValue: .failure) {
            await BodySleepFetch.sleepSamples(
                store: store,
                predicate: predicate,
                sort: sort,
                onFailure: { Self.logTrendQueryFailure("sleepAnalysis", error: $0) }
            )
        }

        guard case .success(let sleepSamples) = samplesOutcome else {
            return .failure
        }
        let groupings = sleepDayGroupings(
            from: sleepSamples,
            calendar: calendar,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
            showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages
        )
        guard let grouping = groupings.max(by: { lhs, rhs in
            (lhs.day.summary.stageSnapshot.date ?? .distantPast)
                < (rhs.day.summary.stageSnapshot.date ?? .distantPast)
        }) else {
            return .success(nil)
        }
        var summary = grouping.day.summary
        guard let interval = grouping.mainSessionInterval else {
            return .success(summary)
        }

        // Sleep is resolved as one atomic summary field: a failed nocturnal
        // vital query keeps the whole cached sleep card rather than showing a
        // fresh card with a blank vital. The window is the main session only, so
        // an afternoon nap on the same wake day can't stretch it across the day.
        switch await fetchSleepVitals(startDate: interval.start, endDate: interval.end) {
        case .failure:
            return .failure
        case .success(let vitals):
            if let vitals {
                summary.vitals = vitals
            }
            return .success(summary)
        }
    }

    /// A `nil` `history` means the grouping query itself failed (device locked,
    /// store unavailable) rather than genuinely returning no nights, so the
    /// assembly layer keeps the cached sleep history — which feeds readiness —
    /// instead of blanking it. Permission-off and a missing sample type still
    /// return an (intentionally cleared) empty snapshot. `vitalsHadFailure`
    /// reports a nocturnal-vital query failure even when grouping succeeded; those
    /// vitals are merged from `cachedSleepHistory` (matched by wake day) rather
    /// than blanked, but the trend leaf still withholds the freshness TTL.
    func fetchDailySleepHistory(
        calendar: Calendar,
        sourceOption: BodyHealthDataSourceOption? = nil,
        hydrateVitals: Bool = true,
        maxDays: Int? = nil,
        cachedSleepHistory: SleepHistorySnapshot? = nil
    ) async -> SleepHistoryFetchResult {
        timeZoneLedger.recordCurrentZone()
        guard permissionSelection.includes(.sleep) else {
            return .empty
        }

        guard HKObjectType.categoryType(forIdentifier: .sleepAnalysis) != nil else {
            return .empty
        }
        if sourceSelectionUnresolved(for: .sleep, option: sourceOption) {
            return SleepHistoryFetchResult(history: nil, vitalsHadFailure: false)
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        // Whole-window refetch (the assembled history replaces the cached one),
        // so clamping the start simply shortens the window rather than leaving a
        // hole. `maxDays` counts query days back from the interval end.
        var startDate = interval.start
        if let maxDays,
           let clampedStart = calendar.date(byAdding: .day, value: -maxDays, to: interval.end),
           clampedStart > startDate {
            startDate = clampedStart
        }
        nonisolated(unsafe) let predicate = combinedPredicate(
            startDate: startDate,
            endDate: interval.end,
            sourceKind: .sleep,
            sourceOption: sourceOption
        )
        nonisolated(unsafe) let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let showsSubMinuteAwakeStages = BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()
        let showsLeadingTrailingAwakeStages = BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()

        let store = healthStore
        let samplesOutcome = await trackedExternalHealthQuery(cancelledValue: .failure) {
            await BodySleepFetch.sleepSamples(
                store: store,
                predicate: predicate,
                sort: sort,
                onFailure: { Self.logTrendQueryFailure("sleepAnalysis", error: $0) }
            )
        }

        guard case .success(let sleepSamples) = samplesOutcome else {
            return SleepHistoryFetchResult(history: nil, vitalsHadFailure: false)
        }
        let groupings = sleepDayGroupings(
            from: sleepSamples,
            calendar: calendar,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
            showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages
        )

        let days = groupings.map(\.day)
        guard hydrateVitals else {
            return SleepHistoryFetchResult(history: SleepHistorySnapshot(days: days), vitalsHadFailure: false)
        }

        // Hydrate sleep vitals with one OR-compound query per vital type,
        // partitioned per night in memory. The prior per-day fan-out issued
        // up to ~365 days × 5 HK queries per full refresh; this issues
        // exactly 5 regardless of day count, with the same per-night
        // predicates so only in-night samples cross the HK IPC boundary.
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("SleepVitalsHydration")
        let hydration = await hydrateSleepVitals(for: groupings, cachedSleepHistory: cachedSleepHistory)
        BodyPerformanceSignposts.signposter.endInterval("SleepVitalsHydration", signpostState)

        return SleepHistoryFetchResult(
            history: SleepHistorySnapshot(days: hydration.days),
            vitalsHadFailure: hydration.vitalsHadFailure
        )
    }

    /// Per-wake-day grouping via the shared `BodySleepFetch` (Body + BodyWatch),
    /// with the iOS device time-zone ledger supplying the zone for nights whose
    /// samples carry no `HKMetadataKeyTimeZone` (Apple Watch sleep never does).
    /// The watch passes its seeded day → zone map instead.
    nonisolated private func sleepDayGroupings(
        from sleepSamples: [HKCategorySample],
        calendar: Calendar,
        showsSubMinuteAwakeStages: Bool,
        showsLeadingTrailingAwakeStages: Bool
    ) -> [SleepDayGrouping] {
        // One reading of the ledger for the whole grouping: the closure below is
        // called once per night, and each call used to re-read and re-decode the
        // stored records.
        let resolver = timeZoneLedger.snapshot()
        return BodySleepFetch.sleepDayGroupings(
            from: sleepSamples,
            calendar: calendar,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
            showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages,
            timeZoneIdentifier: { resolver.zoneIdentifier(on: $0) }
        )
    }

    /// Main sleep session per wake day inside one bounded window, keyed by wake
    /// day — the rest context the progressive Stress history backfill needs for
    /// the chunk it is about to score.
    ///
    /// Deliberately not `fetchDailySleepHistory(hydrateVitals: false)`: that one
    /// always queries the whole year-long trend interval, so a thirteen-chunk
    /// walk would re-read every night thirteen times. This reads the chunk only.
    /// The query starts a day early so a session that began the evening before
    /// the chunk's first day is still grouped onto it.
    ///
    /// `nil` means the query failed (device locked, store unavailable,
    /// unresolved source selection) rather than "no nights": the caller must
    /// abandon the chunk instead of scoring it with the sleep mask missing.
    func fetchStressBackfillSleepIntervals(
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) async -> [Date: DateInterval]? {
        guard permissionSelection.includes(.sleep),
              HKObjectType.categoryType(forIdentifier: .sleepAnalysis) != nil else {
            return [:]
        }
        if sourceSelectionUnresolved(for: .sleep) {
            return nil
        }

        let queryStart = calendar.date(byAdding: .day, value: -1, to: startDate) ?? startDate
        nonisolated(unsafe) let predicate = combinedPredicate(startDate: queryStart, endDate: endDate, sourceKind: .sleep)
        nonisolated(unsafe) let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let store = healthStore
        let samplesOutcome = await trackedExternalHealthQuery(cancelledValue: .failure) {
            await BodySleepFetch.sleepSamples(
                store: store,
                predicate: predicate,
                sort: sort,
                onFailure: { Self.logTrendQueryFailure("sleepAnalysis", error: $0) }
            )
        }
        guard case .success(let sleepSamples) = samplesOutcome else {
            return nil
        }

        let groupings = sleepDayGroupings(
            from: sleepSamples,
            calendar: calendar,
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()
        )

        var intervalsByWakeDay: [Date: DateInterval] = [:]
        for grouping in groupings {
            guard let interval = grouping.mainSessionInterval else {
                continue
            }
            intervalsByWakeDay[calendar.startOfDay(for: grouping.day.date)] = interval
        }
        return intervalsByWakeDay
    }

    private func hydrateSleepVitals(
        for groupings: [SleepDayGrouping],
        cachedSleepHistory: SleepHistorySnapshot?
    ) async -> (days: [SleepDaySummary], vitalsHadFailure: Bool) {
        let indexedIntervals = groupings.enumerated().compactMap { index, grouping in
            grouping.mainSessionInterval.map { (index: index, interval: $0) }
        }
        guard !indexedIntervals.isEmpty else {
            return (groupings.map(\.day), false)
        }

        let outcomes = await fetchSleepVitals(forIntervals: indexedIntervals.map(\.interval))

        // On a per-vital query FAILURE, merge that vital from the cached night
        // with the same wake day (`SleepDayGrouping.day.date`) so a transient
        // failure doesn't blank an existing vital; a successful value — including
        // a genuine nil — replaces it. No cached night → the fetched value stands.
        var cachedVitalsByWakeDay: [Date: SleepVitalsSummary] = [:]
        if outcomes.hadFailure {
            for day in cachedSleepHistory?.days ?? [] {
                cachedVitalsByWakeDay[day.date] = day.summary.vitals
            }
        }

        var hydrated = groupings.map(\.day)
        for (offset, entry) in indexedIntervals.enumerated() {
            let cachedVitals = cachedVitalsByWakeDay[hydrated[entry.index].date]
            hydrated[entry.index].summary.vitals = SleepVitalsSummary(
                heartRate: Self.resolvedSleepVital(outcomes.heartRate, at: offset, cached: cachedVitals?.heartRate),
                heartRateVariability: Self.resolvedSleepVital(outcomes.heartRateVariability, at: offset, cached: cachedVitals?.heartRateVariability),
                respiratoryRate: Self.resolvedSleepVital(outcomes.respiratoryRate, at: offset, cached: cachedVitals?.respiratoryRate),
                oxygenSaturation: Self.resolvedSleepVital(outcomes.oxygenSaturation, at: offset, cached: cachedVitals?.oxygenSaturation),
                wristTemperatureCelsius: Self.resolvedSleepVital(outcomes.wristTemperatureCelsius, at: offset, cached: cachedVitals?.wristTemperatureCelsius)
            )
        }
        return (hydrated, outcomes.hadFailure)
    }

    /// One night's value for a vital: on a query FAILURE keep the cached value
    /// (merged by wake day in `hydrateSleepVitals`), otherwise use the per-night
    /// fetched average (`nil` = genuinely no samples, clears). Mirrors
    /// `resolvedSummaryValue` at the per-vital, per-night grain.
    nonisolated static func resolvedSleepVital(
        _ outcome: QueryOutcome<[Double?]>,
        at index: Int,
        cached: Double?
    ) -> Double? {
        switch outcome {
        case .failure:
            return cached
        case .success(let values):
            guard let values, index < values.count else {
                return nil
            }
            return values[index]
        }
    }

    /// One sample query per vital type covering every night interval (via an
    /// OR-compound of the per-night predicates), averaged per night with
    /// `averageVitalValues`. Matches the per-interval queries it replaces:
    /// same predicates, units, and per-sample value transforms. A per-vital query
    /// FAILURE is preserved as `.failure` (not collapsed to blank nights) so
    /// `hydrateSleepVitals` can merge that vital from cache; permission-off yields
    /// a success of all-nil (genuine absence, clears).
    func fetchSleepVitals(forIntervals intervals: [DateInterval]) async -> SleepVitalsIntervalOutcomes {
        guard !intervals.isEmpty else {
            return .empty
        }

        let emptyValues = [Double?](repeating: nil, count: intervals.count)
        async let heartRates: QueryOutcome<[Double?]> = fetchIfPermitted(.heart, default: .success(emptyValues)) {
            await self.averagedVitalOutcome(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .heartRate,
                intervals: intervals
            )
        }
        async let heartRateVariabilities: QueryOutcome<[Double?]> = fetchIfPermitted(.heart, default: .success(emptyValues)) {
            await self.averagedVitalOutcome(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                sourceKind: .heartRateVariability,
                intervals: intervals
            )
        }
        async let respiratoryRates: QueryOutcome<[Double?]> = fetchIfPermitted(.respiratory, default: .success(emptyValues)) {
            await self.averagedVitalOutcome(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .respiratoryRate,
                intervals: intervals
            )
        }
        async let oxygenSaturations: QueryOutcome<[Double?]> = fetchIfPermitted(.bloodOxygen, default: .success(emptyValues)) {
            await self.averagedVitalOutcome(
                for: .oxygenSaturation,
                unit: .percent(),
                sourceKind: .oxygenSaturation,
                intervals: intervals,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let wristTemperatures: QueryOutcome<[Double?]> = fetchIfPermitted(.wristTemperature, default: .success(emptyValues)) {
            await self.averagedVitalOutcome(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                sourceKind: .wristTemperature,
                intervals: intervals
            )
        }

        return await SleepVitalsIntervalOutcomes(
            heartRate: heartRates,
            heartRateVariability: heartRateVariabilities,
            respiratoryRate: respiratoryRates,
            oxygenSaturation: oxygenSaturations,
            wristTemperatureCelsius: wristTemperatures
        )
    }

    /// Fetches one vital's window samples and averages them per night, preserving
    /// a query FAILURE as `.failure` so the merge layer can fall back to cache.
    private func averagedVitalOutcome(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind?,
        intervals: [DateInterval],
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 }
    ) async -> QueryOutcome<[Double?]> {
        switch await fetchVitalSamples(
            for: identifier,
            unit: unit,
            sourceKind: sourceKind,
            intervals: intervals,
            valueTransform: valueTransform
        ) {
        case .failure:
            return .failure
        case .success(let samples):
            return .success(BodySleepFetch.averageVitalValues(samples: samples ?? [], intervals: intervals))
        }
    }

    /// All samples for one vital across the night intervals, sorted ascending
    /// by start date, with the per-sample value transform already applied
    /// (matching `dailyQuantityValue`, which transforms before averaging).
    private func fetchVitalSamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind?,
        intervals: [DateInterval],
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 }
    ) async -> QueryOutcome<[SleepVitalWindowSample]> {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind) {
            return .failure
        }

        // Hoisted off the actor: `body` runs unstructured and `@Sendable`, so both
        // the store and the source predicate have to be resolved up front.
        let store = healthStore
        nonisolated(unsafe) let sourcePredicate = sourceKind.flatMap { combinedPredicate(sourceKind: $0) }
        switch await trackedExternalHealthQuery(cancelledValue: .failure, {
            await BodySleepFetch.vitalWindowSamples(
                store: store,
                quantityType: quantityType,
                intervals: intervals,
                sourcePredicate: sourcePredicate,
                unit: unit,
                valueTransform: valueTransform,
                onFailure: { Self.logTrendQueryFailure(identifier.rawValue, error: $0) }
            )
        }) {
        case .failure:
            return .failure
        case .success(let windowSamples):
            return .success(windowSamples)
        }
    }

    func fetchSleepVitals(startDate: Date, endDate: Date) async -> QueryOutcome<SleepVitalsSummary> {
        async let heartRate: QueryOutcome<HealthMetricSummary> = fetchIfPermitted(.heart, default: .success(nil)) {
            await sleepQuantitySummary(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .heartRate
            )
        }
        async let heartRateVariability: QueryOutcome<HealthMetricSummary> = fetchIfPermitted(.heart, default: .success(nil)) {
            await sleepQuantitySummary(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .heartRateVariability
            )
        }
        async let respiratoryRate: QueryOutcome<HealthMetricSummary> = fetchIfPermitted(.respiratory, default: .success(nil)) {
            await sleepQuantitySummary(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .respiratoryRate
            )
        }
        async let oxygenSaturation: QueryOutcome<HealthMetricSummary> = fetchIfPermitted(.bloodOxygen, default: .success(nil)) {
            await sleepQuantitySummary(
                for: .oxygenSaturation,
                unit: .percent(),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let wristTemperature: QueryOutcome<HealthMetricSummary> = fetchIfPermitted(.wristTemperature, default: .success(nil)) {
            await sleepQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .wristTemperature
            )
        }

        let resolvedHeartRate = await heartRate
        let resolvedHeartRateVariability = await heartRateVariability
        let resolvedRespiratoryRate = await respiratoryRate
        let resolvedOxygenSaturation = await oxygenSaturation
        let resolvedWristTemperature = await wristTemperature

        // Any failed nocturnal vital query fails the whole sleep vitals fetch so
        // the caller keeps the cached sleep card rather than showing a blank
        // vital. A confirmed-absent vital (`.success(nil)`) stays absent.
        if resolvedHeartRate.isFailure
            || resolvedHeartRateVariability.isFailure
            || resolvedRespiratoryRate.isFailure
            || resolvedOxygenSaturation.isFailure
            || resolvedWristTemperature.isFailure {
            return .failure
        }

        return .success(
            SleepVitalsSummary(
                heartRate: resolvedHeartRate.successValue?.value,
                heartRateVariability: resolvedHeartRateVariability.successValue?.value,
                respiratoryRate: resolvedRespiratoryRate.successValue?.value,
                oxygenSaturation: resolvedOxygenSaturation.successValue?.value,
                wristTemperatureCelsius: resolvedWristTemperature.successValue?.value
            )
        )
    }

    // `averageVitalValues` (per-night averaging of the batched window samples)
    // now lives in the shared `BodySleepFetch`, alongside the query that
    // produces the samples it partitions.
}

/// Result of `fetchDailySleepHistory`: the resolved history (`nil` = the
/// grouping query itself failed, so the caller keeps the cached history) plus
/// whether a nocturnal-vital query failed even though grouping succeeded (those
/// vitals were merged from cache, but the trend leaf still withholds the TTL).
struct SleepHistoryFetchResult {
    let history: SleepHistorySnapshot?
    let vitalsHadFailure: Bool

    static let empty = SleepHistoryFetchResult(history: .empty, vitalsHadFailure: false)
}

/// Per-vital outcomes for a batch of night intervals. Each vital is either a
/// query FAILURE (whole vital query errored — merge that vital from the cached
/// night) or a success carrying per-interval averages aligned to the intervals
/// passed to `fetchSleepVitals` (`nil` = genuinely no samples that night).
struct SleepVitalsIntervalOutcomes {
    let heartRate: HealthKitFetchEngine.QueryOutcome<[Double?]>
    let heartRateVariability: HealthKitFetchEngine.QueryOutcome<[Double?]>
    let respiratoryRate: HealthKitFetchEngine.QueryOutcome<[Double?]>
    let oxygenSaturation: HealthKitFetchEngine.QueryOutcome<[Double?]>
    let wristTemperatureCelsius: HealthKitFetchEngine.QueryOutcome<[Double?]>

    var hadFailure: Bool {
        heartRate.isFailure
            || heartRateVariability.isFailure
            || respiratoryRate.isFailure
            || oxygenSaturation.isFailure
            || wristTemperatureCelsius.isFailure
    }

    static let empty = SleepVitalsIntervalOutcomes(
        heartRate: .success(nil),
        heartRateVariability: .success(nil),
        respiratoryRate: .success(nil),
        oxygenSaturation: .success(nil),
        wristTemperatureCelsius: .success(nil)
    )
}
