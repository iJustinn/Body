//
//  WatchDeltaFetcher.swift
//  BodyWatch
//
//  The watch's short HealthKit re-query over the delta window, on top of the
//  phone's seeded history. Deliberately a THIN SHIM: every query and every
//  transformation below is a call into the shared `BodyWatchSnapshotKit` leaves
//  the iOS `HealthKitFetchEngine` also calls (`BodyHealthSourceResolver`,
//  `BodyHealthQuantityFetch`, `BodySleepFetch`, `BodyWorkoutFetch`,
//  `BodyWorkoutEffortFetcher`). It owns no query logic of its own — a
//  hand-forked watch fetch layer drifted from the phone within a day in the
//  June 2026 standalone-compute attempt (a 26-hour night), and this file exists
//  precisely so there is nothing left to drift.
//
//  Two rules run through everything here:
//  * Source parity — every source-selectable read resolves the PHONE's synced
//    selection with `strictWhenMissing: true`. A selection the watch can't match
//    to one of its own `HKSource`s resolves `.unresolved` and the read is
//    SKIPPED with failure semantics (keep the seed) rather than silently
//    widening to all sources. Widening is what made the first attempt disagree
//    with the phone.
//  * Tri-state outcomes — a query failure (`.failure`) preserves the seed
//    untouched, while a genuine empty result still clears its window. See
//    `WatchFetchOutcome`.
//

import Foundation
import HealthKit

/// One latest-sample reading with the sample's own measurement time — the real
/// watermark the compute stamps onto the metric it feeds (never `Date()`).
struct WatchDeltaSample {
    let value: Double
    let measuredAt: Date
}

/// Everything one delta run read, in the shape `WatchComputeCoordinator`
/// splices onto the seed. Every field defaults to the seed-preserving value, so
/// a permission-off or unresolved-source kind simply never gets written.
struct WatchComputeDelta {
    var heartRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var restingHeartRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var heartRateVariabilitySeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var respiratoryRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var oxygenSaturationSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var wristTemperatureSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var sleepNights: WatchFetchOutcome<[SleepDaySummary]> = .failure
    var workouts: WatchFetchOutcome<[WorkoutSummary]> = .failure

    var heartRateSample: WatchDeltaSample?
    var restingHeartRateSample: WatchDeltaSample?
    var heartRateVariabilitySample: WatchDeltaSample?

    /// The most recent night assembled this run (the phone's `fetchSleepSummary`
    /// picks the same one: the grouping with the latest stage date). Whether it
    /// still counts as TODAY's night is decided by `SleepSummary.asOf` in the
    /// snapshot builder, exactly as on the phone.
    var latestNight: SleepSummary?
}

actor WatchDeltaFetcher {
    private let store = HKHealthStore()

    /// Runs the whole delta window in one pass.
    ///
    /// `windowStart` is `WatchDeltaSplicer.deltaStart(dataThrough:)`; sleep
    /// starts one day earlier so a night that BEGAN before the window but wakes
    /// inside it is still sessionized whole.
    func fetchDelta(
        seed: WatchComputeSeed,
        permission: BodyHealthPermissionSelection,
        windowStart: Date,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) async -> WatchComputeDelta {
        guard HKHealthStore.isHealthDataAvailable() else { return WatchComputeDelta() }

        let selection = BodyHealthDataSourceSelection.storedValue(
            from: seed.settings.healthDataSourceSelectionRaw
        )
        let customGroups = BodyCustomHealthSourceGroupStore.groups(
            from: seed.settings.customHealthSourceGroupsRaw ?? ""
        )
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: windowStart) ?? windowStart

        // Resolve every source-selectable kind's predicate up front (one
        // `HKSourceQuery` fan-out per kind), so the reads below only ever run
        // with a predicate the phone would have produced.
        let reads = await WatchSourceResolver.reads(
            for: BodyHealthSourceResolver.watchComputeSourceKinds,
            selection: selection,
            expectedSourceIDsByKind: seed.expectedSourceIDsByKind,
            customGroups: customGroups,
            permission: permission,
            store: store
        )

        var delta = WatchComputeDelta()

        async let heartRateSeries = dailySeries(
            .heartRate, unit: Self.beatsPerMinute, aggregation: .average,
            sourceKind: .heartRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let restingHeartRateSeries = dailySeries(
            .restingHeartRate, unit: Self.beatsPerMinute, aggregation: .average,
            sourceKind: .restingHeartRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let heartRateVariabilitySeries = dailySeries(
            .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), aggregation: .average,
            sourceKind: .heartRateVariability, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let respiratoryRateSeries = dailySeries(
            .respiratoryRate, unit: Self.beatsPerMinute, aggregation: .average,
            sourceKind: .respiratoryRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let oxygenSaturationSeries = dailySeries(
            .oxygenSaturation, unit: .percent(), aggregation: .average,
            sourceKind: .oxygenSaturation, reads: reads,
            start: windowStart, end: now, calendar: calendar,
            valueTransform: BodyHealthQuantityFetch.normalizedPercent
        )
        async let wristTemperatureSeries = dailySeries(
            .appleSleepingWristTemperature, unit: .degreeCelsius(), aggregation: .average,
            sourceKind: .wristTemperature, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        // Latest-sample summaries: bounded to the daily trend window, matching
        // the phone's `latestQuantity`, so a local read can never introduce a
        // reading older than the charts can show. The value on the card and its
        // stamped watermark are still the sample's own. A reading that ages out
        // of the window later is cleared at display time by
        // `WatchMetricsSnapshot.sanitized(asOf:)` — an absent read here only
        // preserves the seed (see `latestSample`).
        async let heartRateSample = latestSample(
            .heartRate, unit: Self.beatsPerMinute,
            sourceKind: .heartRate, reads: reads,
            now: now, calendar: calendar
        )
        async let restingHeartRateSample = latestSample(
            .restingHeartRate, unit: Self.beatsPerMinute,
            sourceKind: .restingHeartRate, reads: reads,
            now: now, calendar: calendar
        )
        async let heartRateVariabilitySample = latestSample(
            .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli),
            sourceKind: .heartRateVariability, reads: reads,
            now: now, calendar: calendar
        )
        async let sleep = sleepDelta(
            seed: seed, reads: reads,
            start: sleepStart, end: now, calendar: calendar
        )
        async let workouts = workoutDelta(
            permission: permission, start: windowStart, end: now
        )

        delta.heartRateSeries = await heartRateSeries
        delta.restingHeartRateSeries = await restingHeartRateSeries
        delta.heartRateVariabilitySeries = await heartRateVariabilitySeries
        delta.respiratoryRateSeries = await respiratoryRateSeries
        delta.oxygenSaturationSeries = await oxygenSaturationSeries
        delta.wristTemperatureSeries = await wristTemperatureSeries
        delta.heartRateSample = await heartRateSample
        delta.restingHeartRateSample = await restingHeartRateSample
        delta.heartRateVariabilitySample = await heartRateVariabilitySample

        let resolvedSleep = await sleep
        delta.sleepNights = resolvedSleep.nights
        delta.latestNight = resolvedSleep.latestNight

        delta.workouts = await workouts

        return delta
    }

    // MARK: - Quantity reads

    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    private func dailySeries(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        aggregation: BodyDailyQuantityAggregation,
        sourceKind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier),
              case .run(let resolvedSourcePredicate) = reads[sourceKind] else {
            return .failure
        }

        return await BodyHealthQuantityFetch.dailyQuantitySeries(
            store: store,
            quantityType: quantityType,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            aggregation: aggregation,
            unit: unit,
            start: start,
            end: end,
            calendar: calendar,
            valueTransform: valueTransform
        )
    }

    private func latestSample(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        now: Date,
        calendar: Calendar
    ) async -> WatchDeltaSample? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier),
              case .run(let resolvedSourcePredicate) = reads[sourceKind] else {
            return nil
        }

        let outcome = await BodyHealthQuantityFetch.latestQuantitySample(
            store: store,
            quantityType: quantityType,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: BodyHealthTrendRange.recentTrendWindowStart(anchor: now, calendar: calendar),
                endDate: now,
                sourcePredicate: resolvedSourcePredicate
            )
        )
        // Both `.failure` and a genuine `.success(nil)` yield nil here: on the
        // watch an absent reading means "this device has no local data", not an
        // authoritative clear, so the seeded summary value survives either way.
        guard case .success(let sample) = outcome, let sample else { return nil }
        let value = sample.quantity.doubleValue(for: unit)
        guard value.isFinite else { return nil }
        return WatchDeltaSample(value: value, measuredAt: sample.endDate)
    }

    // MARK: - Sleep

    private func sleepDelta(
        seed: WatchComputeSeed,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date,
        calendar: Calendar
    ) async -> (nights: WatchFetchOutcome<[SleepDaySummary]>, latestNight: SleepSummary?) {
        guard case .run(let resolvedSourcePredicate) = reads[.sleep] else {
            return (.failure, nil)
        }

        let samples = await BodySleepFetch.sleepSamples(
            store: store,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            sort: NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        )
        guard case .success(let sleepSamples) = samples else {
            return (.failure, nil)
        }

        // The seeded day → time-zone map stands in for the phone's
        // `BodyTimeZoneLedger`, so a travel night is read in the zone it was
        // slept in on both devices. Days the phone couldn't resolve fall back to
        // this watch's current zone.
        let zoneIdentifiersByDay = seed.settings.recentTimeZoneIdentifiersByDay ?? [:]
        let dayFormatter = BodyDateFormatterCache.formatter(
            dateFormat: "yyyy-MM-dd",
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: calendar.timeZone
        )
        let groupings = BodySleepFetch.sleepDayGroupings(
            from: sleepSamples,
            calendar: calendar,
            showsSubMinuteAwakeStages: seed.settings.showsSubMinuteAwakeSleepStages,
            showsLeadingTrailingAwakeStages: seed.settings.showsLeadingTrailingAwakeSleepStages,
            timeZoneIdentifier: { day in
                zoneIdentifiersByDay[dayFormatter.string(from: day)] ?? TimeZone.current.identifier
            }
        )

        // Seeded per-night vitals, keyed by wake day: the fallback when one
        // vital's own query is unavailable this run (failed, or its source
        // unresolved). The splice replaces seeded nights WHOLESALE by wake day,
        // so without this a single transient vital failure would strip the
        // phone-provided value off every re-fetched night — and move readiness.
        var seededVitalsByDay: [Date: SleepVitalsSummary] = [:]
        for night in seed.trends.sleepHistory.days {
            seededVitalsByDay[calendar.startOfDay(for: night.date)] = night.summary.vitals
        }

        let hydrated = await hydrateSleepVitals(
            for: groupings,
            reads: reads,
            seededVitalsByDay: seededVitalsByDay,
            calendar: calendar
        )
        // Same pick as the phone's `fetchSleepSummary`: the night with the
        // latest stage date. `SleepSummary.asOf` decides whether it is TODAY's.
        let latestNight = hydrated.max { lhs, rhs in
            (lhs.summary.stageSnapshot.date ?? .distantPast) < (rhs.summary.stageSnapshot.date ?? .distantPast)
        }?.summary

        return (.success(hydrated), latestNight)
    }

    /// One batched OR-compound query per nocturnal vital across all the delta
    /// nights, partitioned per night in memory — the shared
    /// `vitalWindowSamples` + `averageVitalValues` pair the phone uses.
    ///
    /// Tri-state per VITAL: a column whose query ran keeps its own results
    /// (including honest per-night nils — genuinely no samples in that night);
    /// a column that was UNAVAILABLE this run (query failed, source
    /// unresolved/skipped) falls back to `seededVitalsByDay` per night instead
    /// of blanking — the enclosing sleep result stays `.success` and these
    /// nights REPLACE the seeded ones wholesale in the splice, so an
    /// all-nil column would strip the phone's own values and move readiness on
    /// a transient failure.
    private func hydrateSleepVitals(
        for groupings: [SleepDayGrouping],
        reads: [HealthMetricKind: WatchSourceRead],
        seededVitalsByDay: [Date: SleepVitalsSummary],
        calendar: Calendar
    ) async -> [SleepDaySummary] {
        let indexedIntervals = groupings.enumerated().compactMap { index, grouping in
            grouping.mainSessionInterval.map { (index: index, interval: $0) }
        }
        var days = groupings.map(\.day)
        guard !indexedIntervals.isEmpty else { return days }

        let intervals = indexedIntervals.map(\.interval)
        async let heartRates = averagedVital(
            .heartRate, unit: Self.beatsPerMinute, sourceKind: .heartRate,
            reads: reads, intervals: intervals
        )
        async let heartRateVariabilities = averagedVital(
            .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), sourceKind: .heartRateVariability,
            reads: reads, intervals: intervals
        )
        async let respiratoryRates = averagedVital(
            .respiratoryRate, unit: Self.beatsPerMinute, sourceKind: .respiratoryRate,
            reads: reads, intervals: intervals
        )
        async let oxygenSaturations = averagedVital(
            .oxygenSaturation, unit: .percent(), sourceKind: .oxygenSaturation,
            reads: reads, intervals: intervals,
            valueTransform: BodyHealthQuantityFetch.normalizedPercent
        )
        async let wristTemperatures = averagedVital(
            .appleSleepingWristTemperature, unit: .degreeCelsius(), sourceKind: .wristTemperature,
            reads: reads, intervals: intervals
        )

        let resolvedHeartRates = await heartRates
        let resolvedHeartRateVariabilities = await heartRateVariabilities
        let resolvedRespiratoryRates = await respiratoryRates
        let resolvedOxygenSaturations = await oxygenSaturations
        let resolvedWristTemperatures = await wristTemperatures

        // An available column is authoritative at its offset (even nil); an
        // unavailable one (nil column) falls back to the seeded night's value.
        func value(_ column: [Double?]?, at offset: Int, fallback: Double?) -> Double? {
            guard let column else { return fallback }
            return column[offset]
        }
        for (offset, entry) in indexedIntervals.enumerated() {
            let seeded = seededVitalsByDay[calendar.startOfDay(for: days[entry.index].date)]
            days[entry.index].summary.vitals = SleepVitalsSummary(
                heartRate: value(resolvedHeartRates, at: offset, fallback: seeded?.heartRate),
                heartRateVariability: value(resolvedHeartRateVariabilities, at: offset, fallback: seeded?.heartRateVariability),
                respiratoryRate: value(resolvedRespiratoryRates, at: offset, fallback: seeded?.respiratoryRate),
                oxygenSaturation: value(resolvedOxygenSaturations, at: offset, fallback: seeded?.oxygenSaturation),
                wristTemperatureCelsius: value(resolvedWristTemperatures, at: offset, fallback: seeded?.wristTemperatureCelsius)
            )
        }
        return days
    }

    /// `nil` = this vital was UNAVAILABLE this run (no quantity type, source
    /// resolution said skip, or the query failed) — the caller falls back to
    /// the seeded value per night. A non-nil array is authoritative, including
    /// its per-night nils (queried, genuinely nothing in that window).
    private func averagedVital(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        intervals: [DateInterval],
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> [Double?]? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier),
              case .run(let resolvedSourcePredicate) = reads[sourceKind] else {
            return nil
        }

        switch await BodySleepFetch.vitalWindowSamples(
            store: store,
            quantityType: quantityType,
            intervals: intervals,
            sourcePredicate: resolvedSourcePredicate,
            unit: unit,
            valueTransform: valueTransform
        ) {
        case .failure:
            return nil
        case .success(let samples):
            return BodySleepFetch.averageVitalValues(samples: samples, intervals: intervals)
        }
    }

    // MARK: - Workouts

    private func workoutDelta(
        permission: BodyHealthPermissionSelection,
        start: Date,
        end: Date
    ) async -> WatchFetchOutcome<[WorkoutSummary]> {
        guard permission.includes(.workouts) else { return .failure }

        // Workouts are never source-selectable, so this needs no resolution.
        // `includesWorkoutMetrics: false` — the watch's Training Load reads only
        // duration + effort, and the detail metrics ride a separate toggle.
        guard case .success(let workouts) = await BodyWorkoutFetch.workouts(
            store: store, start: start, end: end
        ) else {
            return .failure
        }

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)
        for workout in workouts {
            // Effort is resolved per compute and never cached across computes:
            // the watch has no HealthKit observer to invalidate a cached
            // "no rating yet", and a stale negative would silently drop the
            // workout's real intensity out of Training Load (the `6a4d28e`
            // lesson). Each workout is resolved exactly once per run, so a
            // within-run cache would buy nothing.
            let effortOutcome = await BodyWorkoutEffortFetcher.savedEffortOutcome(
                for: workout, store: store
            )
            let effortLevel: Double?
            switch effortOutcome {
            case .found(let effort):
                effortLevel = effort
            case .noSavedEffort:
                // Genuinely unrated: `TrainingLoadCalculator` applies its
                // intentional default effort.
                effortLevel = nil
            case .failed:
                // One transiently-failed relationship query poisons the whole
                // delta: an `effortUnresolved` workout is EXCLUDED from
                // Training Load (and its wake-cycle drain), so returning
                // `.success` here would replay an undercounted load over the
                // seeded day — and stamp it, plus the drain-less readiness, as
                // fresh. Failing the delta keeps the seeded Training Load /
                // readiness authoritative instead (the same
                // failure-keeps-seed rule every other query follows).
                return .failure
            }

            summaries.append(
                BodyWorkoutFetch.summary(
                    for: workout,
                    effortLevel: effortLevel,
                    effortUnresolved: nil,
                    includesWorkoutMetrics: false
                )
            )
        }

        return .success(summaries)
    }
}
