//
//  WatchDeltaFetcher.swift
//  BodyWatch
//
//  The watch's short HealthKit re-query over the delta window, on top of the
//  phone's seeded history. Deliberately a THIN SHIM: every query and every
//  transformation below is a call into the shared `BodyWatchSnapshotKit` leaves
//  the iOS `HealthKitFetchEngine` also calls (`BodyHealthSourceResolver`,
//  `BodyHealthQuantityFetch`, `BodyRestingEnergyEstimates`,
//  `BodyHeartbeatRMSSDFetch`, `BodySleepFetch`, `BodyWorkoutFetch`,
//  `BodyWorkoutEffortFetcher`, `BodyMetricWarningFetch`). Two leaves are not
//  called by the phone yet:
//  `BodyHealthQuantityFetch.dailyCumulativeSeries`, the week of daily totals
//  behind the Steps, Active Energy and Resting Energy cards, which mirrors the
//  engine's `fetchDailyCumulativeQuantitySeries` and shares its resting energy
//  estimate fold; and `BodyHealthQuantityFetch.intradayRangeBuckets`, the 30
//  minute slots behind the Heart Rate, HRV and Blood Oxygen chart
//  complications, which the watch's own Heart Rate and HRV detail pages read
//  through too (`WatchHealthStore`), so a complication and its page chart the
//  same slots (the Blood Oxygen page draws the snapshot's chart itself). This
//  file owns no query logic of its own — a hand-forked watch fetch layer
//  drifted from the phone within a day in the June 2026 standalone-compute
//  attempt (a 26-hour night), and this file exists precisely so there is
//  nothing left to drift.
//
//  Two rules run through everything here:
//  * Source parity — every source-selectable read resolves the PHONE's synced
//    selection with `strictWhenMissing: true`. A selection the watch can't match
//    to one of its own `HKSource`s resolves `.unresolved` and the read is
//    SKIPPED with failure semantics (keep the seed) rather than silently
//    widening to all sources. Widening is what made the first attempt disagree
//    with the phone. Steps, active energy and resting energy are the one
//    documented exception (see `fetchDelta`).
//  * Tri-state outcomes — a query failure (`.failure`) preserves the seed
//    untouched, while a genuine empty result still clears its window. See
//    `WatchFetchOutcome`.
//

import Foundation
import HealthKit

actor WatchDeltaFetcher {
    private let store = HKHealthStore()

    /// Runs the whole delta window in one pass.
    ///
    /// `windowStart` is `WatchDeltaSplicer.deltaStart(dataThrough:)`; sleep
    /// starts one day earlier so a night that BEGAN before the window but wakes
    /// inside it is still sessionized whole, and workouts reach back a full
    /// week so the weekly workout-minutes bars can be built without a seed.
    /// Steps, active energy and resting energy read a fixed week of daily
    /// totals for the same reason (`weeklyTotalSeries`), whatever the window.
    /// `warningThresholds` are the iPhone's, for the warnings the watch
    /// checks itself (`todaysWarningReadings`); a kind without one isn't read.
    func fetchDelta(
        seed: WatchComputeSeed,
        permission: BodyHealthPermissionSelection,
        windowStart: Date,
        now: Date,
        calendar: Calendar = .bodyGregorian,
        warningThresholds: [MetricWarningKind: Double] = [:]
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
        async let resolvedReads = WatchSourceResolver.reads(
            for: BodyHealthSourceResolver.watchComputeSourceKinds,
            selection: selection,
            expectedSourceIDsByKind: seed.expectedSourceIDsByKind,
            customGroups: customGroups,
            permission: permission,
            store: store
        )
        // Steps, active energy and resting energy, resolved ONCE per run
        // beside the kinds above and handed to every read that uses them:
        // Stress's 15 minute movement mask and the week of daily totals behind
        // their own cards. A permission that is off resolves `.skip`.
        //
        // A deliberate deviation from the source parity rule above: these
        // kinds resolve WITHOUT the phone's expected source universe
        // (`expectedSourceIDsByKind: nil`), so a pinned or custom selection
        // stays strict but All Sources reads the sources this watch can see.
        // The iPhone's pedometer is almost always a phone source the watch
        // never sees, so the universe check would skip these reads, and with
        // them Stress and the three cards, for nearly everyone. The mask is a
        // per window threshold (more than 300 steps or 15 kcal in 15 minutes) that only matters
        // where the wrist is producing the heart rate being scored, and the
        // watch sees its own movement. The cards accept the cost: a total
        // built here counts only what this watch sees, so it can read lower
        // than the iPhone's while the watch is off the wrist, until a fresher
        // iPhone push replaces it (the merge keeps whichever is fresher, as
        // for Stress).
        async let resolvedMovementReads = WatchSourceResolver.reads(
            for: [.steps, .activeEnergy, .restingEnergy],
            selection: selection,
            expectedSourceIDsByKind: nil,
            customGroups: customGroups,
            permission: permission,
            store: store
        )
        let reads = await resolvedReads
        let movementReads = await resolvedMovementReads

        var delta = WatchComputeDelta()
        delta.carriedKinds = Set(reads.compactMap { kind, read in
            if case .unavailable = read { return kind }
            return nil
        })

        async let heartRateSeries = dailySeries(
            .heartRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let restingHeartRateSeries = dailySeries(
            .restingHeartRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let heartRateVariabilitySeries = dailySeries(
            .heartRateVariability, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let respiratoryRateSeries = dailySeries(
            .respiratoryRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let oxygenSaturationSeries = dailySeries(
            .oxygenSaturation, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let wristTemperatureSeries = dailySeries(
            .wristTemperature, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        // The HR / HRV / Blood Oxygen week charts' daily min/max capsules,
        // over the same window and source predicate as their averages above.
        async let heartRateRanges = dailyRangeSeries(
            .heartRate, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let heartRateVariabilityRanges = dailyRangeSeries(
            .heartRateVariability, reads: reads,
            start: windowStart, end: now, calendar: calendar
        )
        async let oxygenSaturationRanges = dailyRangeSeries(
            .oxygenSaturation, reads: reads,
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
            .heartRate, reads: reads,
            now: now, calendar: calendar
        )
        async let restingHeartRateSample = latestSample(
            .restingHeartRate, reads: reads,
            now: now, calendar: calendar
        )
        async let heartRateVariabilitySample = latestSample(
            .heartRateVariability, reads: reads,
            now: now, calendar: calendar
        )
        async let oxygenSaturationSample = latestSample(
            .oxygenSaturation, reads: reads,
            now: now, calendar: calendar
        )
        async let sleep = sleepDelta(
            seed: seed, reads: reads,
            start: sleepStart, end: now, calendar: calendar
        )
        async let workouts = workoutDelta(
            permission: permission, windowStart: windowStart, now: now, calendar: calendar
        )
        // Stress's intraday inputs, in the shapes the phone's
        // `fetchIntradayDaySamples` and heartbeat scan read. WHOLE days only:
        // the window opens at the midnight before the last 13 hours (the 12
        // hour chart's reach plus slack), so once those hours cross midnight
        // yesterday is read whole. The assembly recomputes each day these series
        // touch, and a partial yesterday would replace its seeded record with a
        // short day.
        let stressStart = calendar.startOfDay(for: now.addingTimeInterval(-WatchStressTimelineBuilder.span))
        async let stressHeartRateSamples = sampleSeries(
            .heartRate, reads: reads, start: stressStart, end: now
        )
        async let stressSDNNSamples = sampleSeries(
            .heartRateVariability, reads: reads, start: stressStart, end: now
        )
        async let stressRMSSDSamples = rmssdSamples(
            reads: reads, start: stressStart, end: now
        )
        // `stressStart` is a midnight, the 15 minute buckets' anchor.
        async let stressQuarterHourSteps = stressMovementSeries(
            .steps, reads: movementReads,
            start: stressStart, end: now, calendar: calendar
        )
        async let stressQuarterHourActiveEnergy = stressMovementSeries(
            .activeEnergy, reads: movementReads,
            start: stressStart, end: now, calendar: calendar
        )
        // The Heart Rate, HRV and Blood Oxygen chart complications (and the
        // Blood Oxygen page): the detail pages' "Last 8 hours" read, in the
        // same 30 minute slots on the same window, under the kinds'
        // resolution above (see `intradayChart`).
        let intradayWindow = WatchIntradayWindow.endingAt(now, calendar: calendar)
        async let heartRateIntraday = intradayChart(
            .heartRate, reads: reads, window: intradayWindow
        )
        async let heartRateVariabilityIntraday = intradayChart(
            .heartRateVariability, reads: reads, window: intradayWindow
        )
        async let oxygenSaturationIntraday = intradayChart(
            .oxygenSaturation, reads: reads, window: intradayWindow
        )
        // The Steps, Active Energy and Resting Energy cards: a fixed trailing
        // week of daily totals, today included, so every day the 7 day bars
        // draw sits inside the query (see `weeklyTotalSeries`).
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        async let stepsWeek = weeklyTotalSeries(
            .steps, reads: movementReads,
            start: weekStart, end: now, calendar: calendar
        )
        async let activeEnergyWeek = weeklyTotalSeries(
            .activeEnergy, reads: movementReads,
            start: weekStart, end: now, calendar: calendar
        )
        async let restingEnergyWeek = weeklyTotalSeries(
            .restingEnergy, reads: movementReads,
            start: weekStart, end: now, calendar: calendar
        )
        // The warnings the watch checks itself: today's readings for each
        // kind with a watch card and an iPhone threshold, under the kind's
        // resolution above (see `todaysWarningReadings`).
        async let warningReadings = todaysWarningReadings(
            thresholds: warningThresholds, reads: reads,
            now: now, calendar: calendar
        )

        delta.heartRateSeries = await heartRateSeries
        delta.restingHeartRateSeries = await restingHeartRateSeries
        delta.heartRateVariabilitySeries = await heartRateVariabilitySeries
        delta.respiratoryRateSeries = await respiratoryRateSeries
        delta.oxygenSaturationSeries = await oxygenSaturationSeries
        delta.wristTemperatureSeries = await wristTemperatureSeries
        delta.heartRateRanges = await heartRateRanges
        delta.heartRateVariabilityRanges = await heartRateVariabilityRanges
        delta.oxygenSaturationRanges = await oxygenSaturationRanges
        delta.heartRateSample = await heartRateSample
        delta.restingHeartRateSample = await restingHeartRateSample
        delta.heartRateVariabilitySample = await heartRateVariabilitySample
        delta.oxygenSaturationSample = await oxygenSaturationSample

        let resolvedSleep = await sleep
        delta.sleepNights = resolvedSleep.nights
        delta.latestNight = resolvedSleep.latestNight

        delta.workouts = await workouts

        delta.stressHeartRateSamples = await stressHeartRateSamples
        delta.stressSDNNSamples = await stressSDNNSamples
        delta.stressRMSSDSamples = await stressRMSSDSamples
        delta.stressQuarterHourSteps = await stressQuarterHourSteps
        delta.stressQuarterHourActiveEnergy = await stressQuarterHourActiveEnergy

        delta.heartRateIntraday = await heartRateIntraday
        delta.heartRateVariabilityIntraday = await heartRateVariabilityIntraday
        delta.oxygenSaturationIntraday = await oxygenSaturationIntraday

        delta.stepsWeek = await stepsWeek
        delta.activeEnergyWeek = await activeEnergyWeek
        delta.restingEnergyWeek = await restingEnergyWeek

        delta.warningReadings = await warningReadings

        return delta
    }

    // MARK: - Quantity reads

    /// Kept for `averagedVital` below: the nocturnal-vitals reads are keyed by
    /// sleep-session interval rather than by metric kind, so they do not go
    /// through `HealthMetricQueryDescriptor` the way the delta reads do.
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    /// The identifier, unit, source kind, aggregation and value transform all
    /// come from `HealthMetricQueryDescriptor` — the same table the phone's
    /// engine queries from — so a spliced watch point is always comparable with
    /// the phone's series. A kind with no descriptor row, or one whose trend is
    /// cumulative rather than daily, is not a watch delta kind: `.failure`
    /// preserves the seed rather than inventing a reading.
    private func dailySeries(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date,
        calendar: Calendar
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              let aggregation = descriptor.dailyAggregation,
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType),
              case .run(let resolvedSourcePredicate) = reads[descriptor.sourceKind] else {
            return .failure
        }
        let unit = descriptor.unit

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
            valueTransform: descriptor.valueTransform
        )
    }

    /// `dailySeries`' daily min/max counterpart for the Heart Rate, HRV and
    /// Blood Oxygen week charts' capsules: the same descriptor, source
    /// predicate and window, through the shared leaf that applies the phone's
    /// range point rule. `.failure` keeps the seed's capsules, and is never a
    /// readiness blocker.
    private func dailyRangeSeries(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date,
        calendar: Calendar
    ) async -> WatchFetchOutcome<HealthTrendRangeSeries> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType),
              case .run(let resolvedSourcePredicate) = reads[descriptor.sourceKind] else {
            return .failure
        }

        return await BodyHealthQuantityFetch.dailyQuantityRangeSeries(
            store: store,
            quantityType: quantityType,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            unit: descriptor.unit,
            start: start,
            end: end,
            calendar: calendar,
            valueTransform: descriptor.valueTransform
        )
    }

    /// The newest reading in the daily trend window, in the phone's display
    /// unit: the descriptor's `valueTransform` is applied (Blood Oxygen's
    /// `normalizedPercent`, which reads HealthKit's 0.97 as 97; identity for
    /// Heart Rate, Resting HR and HRV), as the phone's `latestQuantity` does.
    private func latestSample(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        now: Date,
        calendar: Calendar
    ) async -> WatchDeltaSample? {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType),
              case .run(let resolvedSourcePredicate) = reads[descriptor.sourceKind] else {
            return nil
        }
        let unit = descriptor.unit

        let predicate = BodyHealthSourceResolver.combinedPredicate(
            startDate: BodyHealthTrendRange.recentTrendWindowStart(anchor: now, calendar: calendar),
            endDate: now,
            sourcePredicate: resolvedSourcePredicate
        )

        if descriptor.quantityType == .heartRate {
            // The watch stores workout heart rate as `HKQuantitySeries`
            // samples, so a plain `HKSampleQuery` (below) returns one
            // aggregated entry per series blob instead of the newest beat.
            // A discrete-most-recent statistics query resolves the series at
            // datum granularity, so it is used here to get the actual latest
            // reading during a workout.
            let outcome = await BodyHealthQuantityFetch.mostRecentQuantity(
                store: store,
                quantityType: quantityType,
                predicate: predicate
            )
            guard case .success(let result) = outcome, let result else { return nil }
            let value = descriptor.valueTransform(result.quantity.doubleValue(for: unit))
            guard value.isFinite else { return nil }
            return WatchDeltaSample(value: value, measuredAt: result.endDate)
        }

        let outcome = await BodyHealthQuantityFetch.latestQuantitySample(
            store: store,
            quantityType: quantityType,
            predicate: predicate
        )
        // Both `.failure` and a genuine `.success(nil)` yield nil here: on the
        // watch an absent reading means "this device has no local data", not an
        // authoritative clear, so the seeded summary value survives either way.
        guard case .success(let sample) = outcome, let sample else { return nil }
        let value = descriptor.valueTransform(sample.quantity.doubleValue(for: unit))
        guard value.isFinite else { return nil }
        return WatchDeltaSample(value: value, measuredAt: sample.endDate)
    }

    // MARK: - Stress

    /// Raw samples for a Stress input (heart rate, SDNN): the descriptor's
    /// intraday `.sampleSeries` row under the kind's resolved source, so the
    /// watch scores the same points the phone's day-sample series holds. The
    /// `.heart` permission gate rides `reads`, which resolves `.skip` for a
    /// hidden category; any read that can't run leaves `.failure`.
    private func sampleSeries(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              descriptor.intradayDaySamples == .sampleSeries,
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType),
              case .run(let resolvedSourcePredicate) = reads[descriptor.sourceKind] else {
            return .failure
        }

        return await BodyHealthQuantityFetch.quantitySampleSeries(
            store: store,
            quantityType: quantityType,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            unit: descriptor.unit,
            valueTransform: descriptor.valueTransform
        )
    }

    /// Stress's RMSSD: Recovery HRV, else the beat-to-beat scan under the
    /// watch's capped limits. An HRV input, so it runs under the HRV source,
    /// exactly as on the phone.
    private func rmssdSamples(
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        guard case .run(let resolvedSourcePredicate) = reads[.heartRateVariability] else {
            return .failure
        }

        return await BodyHeartbeatRMSSDFetch.rmssdSamples(
            store: store,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            limits: .watch
        )
    }

    /// 15 minute sums for Stress's movement mask (steps, active energy), from
    /// `start`'s midnight like the phone's: the descriptor's intraday
    /// `.hourlyCumulative` row read in Stress's own buckets, under the kind's
    /// resolution in `movementReads` (resolved without the phone's source
    /// universe; see `fetchDelta`). A permission that is off resolves `.skip`
    /// and leaves `.failure`.
    private func stressMovementSeries(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date,
        calendar: Calendar
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              descriptor.intradayDaySamples == .hourlyCumulative,
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType),
              case .run(let resolvedSourcePredicate) = reads[descriptor.sourceKind] else {
            return .failure
        }

        return await BodyHealthQuantityFetch.intradayCumulativeSeries(
            store: store,
            quantityType: quantityType,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            unit: descriptor.unit,
            bucket: .quarterHour,
            start: start,
            end: end,
            calendar: calendar,
            valueTransform: descriptor.valueTransform
        )
    }

    // MARK: - Chart complications

    /// A Heart Rate, HRV or Blood Oxygen chart complication's last 8 hours:
    /// the detail page's read (`WatchHealthStore.intradayBuckets`) through the
    /// same shared leaf, with the descriptor's type, unit and value transform
    /// (SDNN in ms for HRV, as on the page; Blood Oxygen in percent, as on the
    /// iPhone) under the kind's resolution in `reads`. The predicate
    /// is the page's own, open ended on purpose (`endDate: nil`), so a heart
    /// rate series that started before the window still contributes its
    /// in-window beats. A kind with no source on this watch at all
    /// (`.unavailable`) reads as an empty chart, as the page's does, which
    /// removes the displayed one (Blood Oxygen's is left out of the snapshot
    /// instead, so the iPhone's stands: `WatchComputeAssembly.heartCharts`).
    /// A skipped resolution (Heart off, or a
    /// selection this watch can't match), a missing read or a failed query
    /// leaves `.failure`, which keeps it.
    private func intradayChart(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        window: WatchIntradayWindow
    ) async -> WatchFetchOutcome<WatchIntradayChart> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType) else {
            return .failure
        }

        switch reads[descriptor.sourceKind] {
        case .run(let resolvedSourcePredicate):
            let outcome = await BodyHealthQuantityFetch.intradayRangeBuckets(
                store: store,
                quantityType: quantityType,
                predicate: BodyHealthSourceResolver.combinedPredicate(
                    startDate: window.start,
                    endDate: nil,
                    sourcePredicate: resolvedSourcePredicate
                ),
                unit: descriptor.unit,
                start: window.start,
                end: window.end,
                valueTransform: descriptor.valueTransform
            )
            guard case .success(let buckets) = outcome else { return .failure }
            return .success(WatchIntradayChart(window: window, buckets: buckets))
        case .unavailable:
            return .success(WatchIntradayChart(window: window, buckets: []))
        default:
            return .failure
        }
    }

    // MARK: - Daily totals

    /// A week of daily totals for the Steps, Active Energy and Resting Energy
    /// cards and their 7 day bars: the descriptor's `.dailyCumulative` trend
    /// row, under the kind's resolution in `movementReads` (see `fetchDelta`),
    /// through the shared leaf that also applies the phone's resting energy
    /// scale-estimate rule. The window is a fixed week, like `workoutDelta`'s
    /// floor, rather than the delta window: there is no seeded history for
    /// these kinds to splice onto, so the assembly replaces their series with
    /// this read wholesale. A permission that is off resolves `.skip`, and any
    /// read that can't run leaves `.failure`, which stamps nothing.
    private func weeklyTotalSeries(
        _ kind: HealthMetricKind,
        reads: [HealthMetricKind: WatchSourceRead],
        start: Date,
        end: Date,
        calendar: Calendar
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              descriptor.trend == .dailyCumulative,
              let quantityType = HKObjectType.quantityType(forIdentifier: descriptor.quantityType),
              case .run(let resolvedSourcePredicate) = reads[descriptor.sourceKind] else {
            return .failure
        }

        return await BodyHealthQuantityFetch.dailyCumulativeSeries(
            store: store,
            quantityType: quantityType,
            predicate: BodyHealthSourceResolver.combinedPredicate(
                startDate: start,
                endDate: end,
                sourcePredicate: resolvedSourcePredicate
            ),
            unit: descriptor.unit,
            start: start,
            end: end,
            calendar: calendar,
            valueTransform: descriptor.valueTransform
        )
    }

    // MARK: - Warnings

    /// Today's readings behind each warning the watch checks itself
    /// (`WatchComputeAssembly.checkedWarningKinds`): the iPhone's own read
    /// (`BodyMetricWarningFetch.todaysReadings`) under the iPhone's threshold
    /// and the kind's metric's resolution in `reads`, so both heart rate
    /// kinds read under Heart Rate's source. A kind without a threshold, or
    /// whose resolution can't run (its permission off, a selection this
    /// watch can't match, no source here), isn't read and stays absent; a
    /// failed read answers `.failure`. Either keeps the kind's last check.
    private func todaysWarningReadings(
        thresholds: [MetricWarningKind: Double],
        reads: [HealthMetricKind: WatchSourceRead],
        now: Date,
        calendar: Calendar
    ) async -> [MetricWarningKind: WatchFetchOutcome<[HealthTrendDataPoint]>] {
        await withTaskGroup(of: (MetricWarningKind, WatchFetchOutcome<[HealthTrendDataPoint]>?).self) { group in
            for kind in WatchComputeAssembly.checkedWarningKinds {
                guard let threshold = thresholds[kind], let read = reads[kind.metric] else { continue }
                // The resolution crosses into the child task rather than its
                // predicate: `WatchSourceRead` is the Sendable wrapper.
                group.addTask { [store] in
                    guard case .run(let sourcePredicate) = read else { return (kind, nil) }
                    return (kind, await BodyMetricWarningFetch.todaysReadings(
                        for: kind,
                        store: store,
                        sourcePredicate: sourcePredicate,
                        threshold: threshold,
                        now: now,
                        calendar: calendar
                    ))
                }
            }

            var readings: [MetricWarningKind: WatchFetchOutcome<[HealthTrendDataPoint]>] = [:]
            for await (kind, outcome) in group {
                readings[kind] = outcome
            }
            return readings
        }
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
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 }
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
        windowStart: Date,
        now: Date,
        calendar: Calendar
    ) async -> WatchFetchOutcome<[WorkoutSummary]> {
        guard permission.includes(.workouts) else { return .failure }

        // Reaches back a full week when the delta window is shorter: the weekly
        // workout-minutes complication series is built from THIS fetch alone
        // (there is no seeded workout history to fall back on), so every day it
        // draws has to sit inside the query. Still bounded — a week is the
        // floor, never an unbounded widening.
        let weekStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now))
            ?? windowStart
        let start = min(windowStart, weekStart)

        // Workouts are never source-selectable, so this needs no resolution.
        // `includesWorkoutMetrics: false` — the watch's Training Load reads only
        // duration + effort, and the detail metrics ride a separate toggle.
        guard case .success(let workouts) = await BodyWorkoutFetch.workouts(
            store: store, start: start, end: now
        ) else {
            return .failure
        }

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)
        for workout in workouts {
            // Days BEFORE the delta window are carried for their DURATION only
            // (the weekly bars): Training Load overwrites no slot back there and
            // the readiness drain never reaches them, so resolving effort would
            // only add queries — and the failure below — for a number nothing
            // reads.
            guard workout.startDate >= windowStart else {
                summaries.append(
                    BodyWorkoutFetch.summary(
                        for: workout,
                        effortLevel: nil,
                        effortUnresolved: nil,
                        includesWorkoutMetrics: false
                    )
                )
                continue
            }
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
