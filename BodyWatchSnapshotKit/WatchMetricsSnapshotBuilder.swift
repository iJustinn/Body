//
//  WatchMetricsSnapshotBuilder.swift
//  Body
//
//  Builds the compact `WatchMetricsSnapshot` pushed to the watch from the
//  iPhone's already-computed dashboard state. Reuses `BodyValueFormat` so the
//  watch values match the phone exactly, and precomputes each ring's 0...1 fill
//  (the watch never recomputes scores — only the live HR/HRV fill, against the
//  carried range).
//
//  Pure value-type inputs only (no `HKSource` / non-Sendable HealthKit objects
//  cross to the watch).
//

import Foundation

enum WatchMetricsSnapshotBuilder {
    static func makeSnapshot(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        lastRefreshDate: Date?,
        permissionSelection: BodyHealthPermissionSelection,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        // The unit Active Energy and Resting Energy are formatted in, their
        // headline and week alike, as the iPhone cards show them. The phone
        // passes the user's preference and the watch's compute the one the
        // seed carries. Kilocalories (the default) keeps every caller that
        // predates these metrics compiling and formatting as before.
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference = .kilocalories,
        idealSleepDuration: TimeInterval,
        showSleepScore: Bool = true,
        now: Date = Date(),
        // The trailing week's workout minutes (oldest → today, 7 slots, an
        // explicit `0` for a day with no workouts), summed by the caller from
        // the workouts it already holds — this kit never fetches. `nil` (the
        // default) omits the Weekly Workout Time metric entirely, so a caller
        // that hasn't loaded the week yet can't publish a falsely empty one.
        workoutWeeklyMinutes: [Double?]? = nil,
        // Phone→watch compute (Phase 1d): when provided, a kind's carried
        // range is the UNION of this override with its own local series
        // min/max, so the watch's short delta-fetched history doesn't shrink
        // the ring/chart bounds the phone's longer history already
        // established. `nil` for every kind (the default) reproduces today's
        // behavior byte-for-byte. Known limitation: a corrected/deleted
        // historical extreme lingers in the override until the next phone
        // publish rebuilds `seriesRanges` — display-only, self-healing.
        seriesRangeOverride: ((String) -> WatchSeriesRange?)? = nil,
        // When provided, stamps a kind's `computedAt` from this instead of the
        // uniform `lastRefreshDate` below — lets the phone pass honest
        // per-kind watermarks (e.g. a workout-only refresh that only moved
        // Training Load) instead of a single stale-looking timestamp for every
        // metric. `nil` (the default) reproduces today's uniform stamping.
        perKindDataAsOf: ((String) -> Date?)? = nil,
        // Whether to build the Sleep page's Sleep Debt (the last
        // `SleepDebtChartModel.watchNightCount` nights of the iPhone card's
        // 14 night debt). The phone passes its Body Pro and Summary Cards
        // toggle; the watch's compute always builds it, since the phone's
        // pushed flag decides visibility. `false` (the default) omits it, so
        // a caller that doesn't show it never pays for the model.
        includesSleepDebt: Bool = false,
        // The Stress page's "Last 12 hours" chart, built by the caller with
        // `WatchStressTimelineBuilder` (it needs the intraday day samples and
        // the workouts, which this builder never reads). Stamped as passed.
        stressTimeline: WatchStressTimeline? = nil,
        // The phone's custom workout colors for that chart's shading, a
        // display preference only the phone's publish passes.
        workoutColorOverrides: String? = nil
    ) -> WatchMetricsSnapshot {
        let tempPref = temperatureUnitPreference

        // Mirror the iPhone's Data > Permissions: omit hidden categories entirely
        // so the watch (and its live HR/HRV refresh) can't surface data the user
        // hid. `.heart` gates HR, HRV, and Resting HR.
        var metrics: [WatchMetric] = [readinessMetric(summary.readiness)]

        // The trusted night's day, carried on the snapshot so the watch can
        // re-run the staleness guard at display time on a snapshot that outlived
        // midnight in its cache (see `WatchMetricsSnapshot.sanitized`).
        var sleepNight: Date? = nil
        // The night's EVENT watermark (see `WatchMetric.measuredAt`), stamped
        // from the same trusted night as `sleepNight` so the two always
        // describe one session.
        var sleepNightEnd: Date? = nil
        // The same trusted night's stage segments for the watch Sleep Stages
        // complication — MAIN SESSION only, so naps stay out of the bar,
        // matching the iPhone Home Screen Sleep Stages widget.
        var sleepStages: [WatchSleepStageSegment]? = nil
        var sleepDebt: WatchSleepDebt? = nil

        if permissionSelection.includes(.sleep) {
            // Guards against carrying over a stale, previously-completed night
            // after midnight before today's own sleep session exists.
            let trustedSleep = summary.sleep.asOf(now)
            sleepNight = trustedSleep?.stageSnapshot.date
            sleepNightEnd = trustedSleep?.stageSnapshot.dateInterval?.end
            let mainSessionSegments = trustedSleep?.stageSnapshot.mainSession.segments ?? []
            sleepStages = mainSessionSegments.isEmpty
                ? nil
                : mainSessionSegments.map {
                    WatchSleepStageSegment(stage: $0.stage.rawValue, startDate: $0.startDate, endDate: $0.endDate)
                }
            metrics.append(sleepMetric(
                trustedSleep,
                recentSleepHistory: trends.sleepHistory,
                idealSleepDuration: idealSleepDuration,
                showScore: showSleepScore
            ))
            if includesSleepDebt {
                // The raw summary, as the iPhone card passes it: the model
                // applies the same `asOf` guard itself, filling in today only.
                sleepDebt = sleepDebtSnapshot(
                    sleepHistory: trends.sleepHistory,
                    currentDaySummary: summary.sleep,
                    trainingLoad: trends.trainingLoad,
                    sleepGoal: idealSleepDuration,
                    now: now,
                    // The information cutoff of both inputs: the sleep read
                    // and the Training Load the needs were raised by.
                    computedAt: [
                        perKindDataAsOf?(WatchMetricKindKey.sleep) ?? lastRefreshDate,
                        perKindDataAsOf?(WatchMetricKindKey.trainingLoad)
                    ].compactMap { $0 }.max()
                )
            }
        }
        if permissionSelection.includes(.heart) {
            metrics.append(rangeMetric(
                kind: WatchMetricKindKey.heartRate, title: String(localized: "Heart Rate", table: "BodyWatchSnapshotKit"), value: summary.heartRate.value,
                unit: "bpm", decimals: 0,
                seriesValues: values(trends.heartRate),
                overrideRange: seriesRangeOverride?(WatchMetricKindKey.heartRate)
            ))
            metrics.append(rangeMetric(
                kind: WatchMetricKindKey.heartRateVariability, title: String(localized: "HRV", table: "BodyWatchSnapshotKit"), value: summary.heartRateVariability.value,
                unit: "ms", decimals: 0,
                seriesValues: values(trends.heartRateVariability),
                overrideRange: seriesRangeOverride?(WatchMetricKindKey.heartRateVariability)
            ))
            metrics.append(rangeMetric(
                kind: WatchMetricKindKey.restingHeartRate, title: String(localized: "Resting HR", table: "BodyWatchSnapshotKit"), value: summary.restingHeartRate.value,
                unit: "bpm", decimals: 0,
                seriesValues: values(trends.restingHeartRate), invert: true,
                overrideRange: seriesRangeOverride?(WatchMetricKindKey.restingHeartRate)
            ))
            // Stress is heart-derived end to end, so it rides Heart too.
            metrics.append(stressMetric(summary: summary, now: now))
        }

        // The day's running totals (Steps, Active Energy, Resting Energy).
        // Build-time day guard, like the first of Stress's two guards (in
        // `stressMetric`): their `HealthMetricSummary` carries no date, so a
        // phone republish after midnight over a cached summary (a settings
        // change or a toggle before any overnight refresh) would otherwise
        // ship yesterday's total under `weeklyAsOf = now`, which the
        // display-time rule in `sanitized` then keeps, beside a week whose
        // today slot is blank. So the headline is published only when the
        // kind's watermark (the same one stamped as `computedAt` below) falls
        // on `now`'s day; the week is unaffected. The watch's compute stamps a
        // successful read with `now`, so there the guard never fires. Inline
        // because the stamping runs after the metrics are built.
        func todaysTotal(_ value: Double?, kind: String) -> Double? {
            guard let watermark = perKindDataAsOf?(kind) ?? lastRefreshDate,
                  Calendar.bodyGregorian.isDate(watermark, inSameDayAs: now) else { return nil }
            return value
        }
        // Energy in the display unit, the headline and the week alike (the
        // rule Skin Temp's week follows), so the chart and the value agree.
        func energyDisplay(kilocalories: Double) -> (value: Double, unit: String) {
            BodyValueFormat.energyValue(kilocalories: kilocalories, energyUnitPreference: energyUnitPreference)
        }
        func energyWeek(_ series: HealthTrendSeries) -> [Double?] {
            weekly(series, now: now).map { day in day.map { energyDisplay(kilocalories: $0).value } }
        }
        if permissionSelection.includes(.steps) {
            // No unit string, like the iPhone Steps card's summary: the title
            // already says Steps.
            metrics.append(dailyTotalMetric(
                kind: WatchMetricKindKey.steps, title: String(localized: "Steps", table: "BodyWatchSnapshotKit"),
                value: todaysTotal(summary.steps.value, kind: WatchMetricKindKey.steps),
                unit: "",
                weekValues: weekly(trends.steps, now: now)
            ))
        }
        if permissionSelection.includes(.energy) {
            let activeEnergy = todaysTotal(summary.activeEnergy.value, kind: WatchMetricKindKey.activeEnergy)
                .map { energyDisplay(kilocalories: $0) }
            metrics.append(dailyTotalMetric(
                kind: WatchMetricKindKey.activeEnergy, title: String(localized: "Active Energy", table: "BodyWatchSnapshotKit"),
                value: activeEnergy?.value,
                unit: activeEnergy?.unit ?? "",
                weekValues: energyWeek(trends.activeEnergy),
                usesKilojoules: energyUnitPreference == .kilojoules
            ))
            let restingEnergy = todaysTotal(summary.restingEnergy.value, kind: WatchMetricKindKey.restingEnergy)
                .map { energyDisplay(kilocalories: $0) }
            metrics.append(dailyTotalMetric(
                kind: WatchMetricKindKey.restingEnergy, title: String(localized: "Resting Energy", table: "BodyWatchSnapshotKit"),
                value: restingEnergy?.value,
                unit: restingEnergy?.unit ?? "",
                weekValues: energyWeek(trends.restingEnergy),
                usesKilojoules: energyUnitPreference == .kilojoules
            ))
        }
        if permissionSelection.includes(.workouts) {
            metrics.append(trainingLoadMetric(summary.trainingLoad.value))
            if let workoutWeeklyMinutes {
                // Complication-only: no ring, no dashboard card. Today's value
                // is the passed week's last day, the same series the stamping
                // below carries as `weekly`.
                metrics.append(workoutMinutesMetric(workoutWeeklyMinutes.last ?? nil))
                // Version-skew compatibility: an older watch binary's week
                // complication queries only the legacy `exerciseMinutes` kind,
                // and a phone push REPLACES the watch's metric set — without
                // this copy its configured complication would go blank until
                // the watch app itself updates. Same values, legacy kind; the
                // updated complication reads `workoutMinutes` first and never
                // touches it.
                metrics.append(workoutMinutesMetric(
                    workoutWeeklyMinutes.last ?? nil,
                    kind: WatchMetricKindKey.exerciseMinutes
                ))
            }
        }
        if permissionSelection.includes(.wristTemperature) {
            metrics.append(skinTempMetric(
                summary.wristTemperature.value,
                seriesValues: values(trends.wristTemperature),
                pref: tempPref,
                overrideRange: seriesRangeOverride?(WatchMetricKindKey.wristTemperature)
            ))
        }

        // Last 7 daily values per metric (oldest → today), in each metric's
        // display unit, for the watch metric-detail sparkline. Reuses the iPhone
        // "Week" chart's daily aggregation so the two match exactly.
        func weeklyValues(forKind kind: String) -> [Double?]? {
            switch kind {
            case WatchMetricKindKey.readiness: return weekly(trends.readiness, now: now)
            case WatchMetricKindKey.sleep: return weekly(trends.sleepHistory.durationSeries, now: now)
            case WatchMetricKindKey.heartRate: return weekly(trends.heartRate, now: now)
            case WatchMetricKindKey.heartRateVariability: return weekly(trends.heartRateVariability, now: now)
            case WatchMetricKindKey.restingHeartRate: return weekly(trends.restingHeartRate, now: now)
            case WatchMetricKindKey.trainingLoad: return weekly(trends.trainingLoad, now: now)
            case WatchMetricKindKey.stress: return weekly(trends.stress, now: now)
            // The same daily totals the cards' fill was scaled against.
            case WatchMetricKindKey.steps: return weekly(trends.steps, now: now)
            case WatchMetricKindKey.activeEnergy: return energyWeek(trends.activeEnergy)
            case WatchMetricKindKey.restingEnergy: return energyWeek(trends.restingEnergy)
            case WatchMetricKindKey.workoutMinutes: return workoutWeeklyMinutes
            // The legacy compatibility copy carries the same week (see the
            // version-skew comment where both metrics are appended).
            case WatchMetricKindKey.exerciseMinutes: return workoutWeeklyMinutes
            case WatchMetricKindKey.wristTemperature:
                // Match the card's display unit so the detail stats agree.
                return weekly(trends.wristTemperature, now: now).map { day in
                    day.map { BodyValueFormat.temperatureValue(celsius: $0, temperatureUnitPreference: tempPref).value }
                }
            default: return nil
            }
        }

        // Each day's min/max under the Heart Rate, HRV and Stress week charts
        // (the iPhone trend charts' range bars), windowed exactly like
        // `weekly` above, so slot i is the same day in both. nil for every
        // other kind.
        func weeklyRangeValues(forKind kind: String) -> [WatchDayRange?]? {
            switch kind {
            case WatchMetricKindKey.heartRate: return weeklyRanges(trends.heartRateRanges, now: now)
            case WatchMetricKindKey.heartRateVariability: return weeklyRanges(trends.heartRateVariabilityRanges, now: now)
            case WatchMetricKindKey.stress: return weeklyRanges(trends.stressRanges, now: now)
            default: return nil
            }
        }

        // The reading's own measurement time (`WatchMetric.measuredAt`): the
        // latest sample's `endDate` for the sample-headline vitals, the night's
        // end for sleep. Computed metrics (Readiness, Training Load) carry
        // none — their `computedAt` is the honest watermark.
        func measuredAt(forKind kind: String) -> Date? {
            switch kind {
            case WatchMetricKindKey.heartRate: return summary.heartRate.measuredAt
            case WatchMetricKindKey.heartRateVariability: return summary.heartRateVariability.measuredAt
            case WatchMetricKindKey.restingHeartRate: return summary.restingHeartRate.measuredAt
            case WatchMetricKindKey.sleep: return sleepNightEnd
            default: return nil
            }
        }

        let stamped = metrics.map { metric -> WatchMetric in
            var stampedMetric = metric
            stampedMetric.computedAt = perKindDataAsOf?(metric.kind) ?? lastRefreshDate
            stampedMetric.measuredAt = measuredAt(forKind: metric.kind)
            stampedMetric.weekly = weeklyValues(forKind: metric.kind)
            stampedMetric.weeklyRanges = weeklyRangeValues(forKind: metric.kind)
            stampedMetric.weeklyAsOf = stampedMetric.weekly == nil ? nil : now
            return stampedMetric
        }
        return WatchMetricsSnapshot(
            generatedAt: now,
            lastRefreshDate: lastRefreshDate,
            metrics: stamped,
            sleepNight: sleepNight,
            sleepStages: sleepStages,
            sleepDebt: sleepDebt,
            stressTimeline: stressTimeline,
            workoutColorOverrides: workoutColorOverrides
        )
    }

    /// Whole-series min/max per metric kind (every point the passed trends
    /// carry — NOT a recent-week slice), using the SAME `values(_:)`
    /// filtering the range/skin-temp metrics themselves use — so a phone-built
    /// seed's ranges union with a watch's own local series by construction
    /// (see `seriesRangeOverride` above). Only the kinds `rangeMetric`/
    /// `skinTempMetric` cover; Readiness/Sleep/Training Load use fixed
    /// 0...100 / 0...2 bounds and aren't included.
    static func seriesRanges(from trends: HealthTrendSnapshot) -> [String: WatchSeriesRange] {
        let seriesByKind: [(String, HealthTrendSeries)] = [
            (WatchMetricKindKey.heartRate, trends.heartRate),
            (WatchMetricKindKey.heartRateVariability, trends.heartRateVariability),
            (WatchMetricKindKey.restingHeartRate, trends.restingHeartRate),
            (WatchMetricKindKey.wristTemperature, trends.wristTemperature)
        ]

        var ranges: [String: WatchSeriesRange] = [:]
        for (kind, series) in seriesByKind {
            let seriesValues = values(series)
            guard let low = seriesValues.min(), let high = seriesValues.max() else {
                continue
            }
            ranges[kind] = WatchSeriesRange(min: low, max: high)
        }
        return ranges
    }

    // MARK: - Per-metric builders

    private static func readinessMetric(_ readiness: ReadinessSummary) -> WatchMetric {
        var metric = readinessMetric(score: readiness.score, isDrained: readiness.activityDrainMorningScore != nil)
        if let score = readiness.score,
           let cycleStart = readiness.activityDrainCycleStart,
           let contributions = readiness.activityDrainContributions {
            metric.drain = WatchReadinessDrainReport(
                undrainedScore: readiness.activityDrainMorningScore ?? score,
                cycleStart: cycleStart,
                contributions: contributions.map {
                    .init(id: $0.id.uuidString, start: $0.start, points: $0.points)
                }
            )
        }
        return metric
    }

    /// Every display field a readiness score decides. Separate from the
    /// summary-taking builder above so `WatchReadinessDrainReconciler` can
    /// render a reconciled score through the identical mapping.
    static func readinessMetric(score: Int?, isDrained: Bool) -> WatchMetric {
        let status = ReadinessStatus.status(for: score)
        return WatchMetric(
            kind: WatchMetricKindKey.readiness,
            title: String(localized: "Readiness", table: "BodyWatchSnapshotKit"),
            displayValue: score.map { "\($0)" } ?? "--",
            unit: score == nil ? "" : "%",
            score: score,
            fillFraction: score.map { Double($0) / 100 } ?? 0,
            rawValue: score.map(Double.init),
            rangeMin: 0,
            rangeMax: 100,
            // Corner gauge spans the current status band (e.g. High 80–94).
            levelMin: status.scoreBounds?.min,
            levelMax: status.scoreBounds?.max,
            // Color the ring by readiness status band (prime → purple, …),
            // matching the iOS readiness UI. nil score → kind's default tint.
            tint: status.watchTintComponents,
            // Highlight today's status band on the detail chart (chart bounds,
            // open-ended at the extremes) — mirrors `BodyReadinessStatusPresentation`.
            statusBand: status == .unavailable
                ? nil
                : WatchStatusBand(
                    min: status.lowerBound, max: status.upperBound,
                    label: status.title),
            // Detail sparkline's faded "current" dot: the drained score, only
            // when today's workouts actually drained (same gate as the iOS
            // week chart). The sparkline still requires it to sit strictly
            // below today's plotted slot before drawing.
            weeklyCurrentValue: isDrained
                ? score.map(Double.init)
                : nil
        )
    }

    private static func sleepMetric(
        _ sleep: SleepSummary?,
        recentSleepHistory: SleepHistorySnapshot,
        idealSleepDuration: TimeInterval,
        showScore: Bool
    ) -> WatchMetric {
        // Honor the phone's "Show Sleep Score" toggle: when off, omit the score
        // so the watch (and complications, which read `metric.score`) don't show it.
        // Compute the score with the user's sleep-duration goal + recent history
        // for vitals baselines, matching the iPhone (the bare `sleep.score` would
        // use the 8h default + empty history and diverge from the phone).
        let total = (showScore ? sleep : nil).flatMap {
            SleepScoreSummary(
                sleep: $0,
                idealSleepDuration: idealSleepDuration,
                recentSleepHistory: recentSleepHistory,
                on: $0.stageSnapshot.date
            )?.total
        }
        return WatchMetric(
            kind: WatchMetricKindKey.sleep,
            title: String(localized: "Sleep", table: "BodyWatchSnapshotKit"),
            displayValue: sleep?.duration.map { BodyValueFormat.sleepDurationText(for: $0) } ?? "--",
            unit: "",
            score: total,
            fillFraction: total.map { Double($0) / 100 } ?? 0,
            rawValue: total.map(Double.init),
            rangeMin: 0,
            rangeMax: 100
        )
    }

    /// The last `SleepDebtChartModel.watchNightCount` nights of the iPhone
    /// Sleep Debt card, built by the same shared model: a night reads only its
    /// own 14 night window, the day before it, and the history behind them,
    /// so each one carries the debt the card shows for it. Nil when the model
    /// has no nights.
    private static func sleepDebtSnapshot(
        sleepHistory: SleepHistorySnapshot,
        currentDaySummary: SleepSummary,
        trainingLoad: HealthTrendSeries,
        sleepGoal: TimeInterval,
        now: Date,
        computedAt: Date?
    ) -> WatchSleepDebt? {
        let nightCount = SleepDebtChartModel.watchNightCount
        let model = SleepDebtChartModel.make(
            entries: SleepDebtChartModel.entries(
                sleepHistory: sleepHistory,
                currentDaySummary: currentDaySummary,
                trainingLoad: trainingLoad,
                nightCount: nightCount,
                today: now
            ),
            sleepGoal: sleepGoal,
            nightCount: nightCount
        )
        guard !model.nights.isEmpty else { return nil }
        return WatchSleepDebt(
            debt: model.debt,
            nights: model.nights.map {
                WatchSleepDebt.Night(day: $0.day, debt: $0.debtAfterNight, isRecorded: $0.isRecorded)
            },
            computedAt: computedAt
        )
    }

    private static func rangeMetric(
        kind: String,
        title: String,
        value: Double?,
        unit: String,
        decimals: Int,
        seriesValues: [Double],
        invert: Bool = false,
        overrideRange: WatchSeriesRange? = nil
    ) -> WatchMetric {
        let low = unionMin(seriesValues.min(), overrideRange?.min)
        let high = unionMax(seriesValues.max(), overrideRange?.max)
        return WatchMetric(
            kind: kind,
            title: title,
            displayValue: value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: value == nil ? "" : unit,
            score: nil,
            fillFraction: value.map { fraction(of: $0, low: low, high: high, invert: invert) } ?? 0,
            rawValue: value,
            rangeMin: low,
            rangeMax: high
        )
    }

    private static func trainingLoadMetric(_ value: Double?) -> WatchMetric {
        let interval = TrainingLoadInterval.interval(for: value)
        return WatchMetric(
            kind: WatchMetricKindKey.trainingLoad,
            title: String(localized: "Training Load", table: "BodyWatchSnapshotKit"),
            displayValue: value.map { BodyValueFormat.numberText($0, decimals: 2) } ?? "--",
            unit: "",
            score: nil,
            // Ratio band 0...2 (optimal ~0.8–1.3 lands mid-ring).
            fillFraction: value.map { min(max($0 / 2.0, 0), 1) } ?? 0,
            rawValue: value,
            rangeMin: 0,
            rangeMax: 2,
            // Corner gauge spans the current load band; tint matches it.
            levelMin: interval?.watchGaugeBounds.min,
            levelMax: interval?.watchGaugeBounds.max,
            tint: interval?.watchTintComponents,
            // Highlight today's load band on the detail chart (chart bounds,
            // open-ended at the extremes) — mirrors `BodyTrainingLoadIntervalPresentation`.
            statusBand: interval.map {
                WatchStatusBand(
                    min: $0.lowerBound, max: $0.upperBound,
                    label: $0.title)
            }
        )
    }

    /// Today's Stress, the same number the iPhone card shows: the day's
    /// average score, published only when the rollup is dated `now`'s day (a
    /// summary that outlived midnight reads "--", and `weeklyAsOf` lets the
    /// watch re-check the day at display time). The status band, gauge bounds
    /// and tint follow the latest reading when it is still current
    /// (`stressCurrentScore`), otherwise the average, as on the iPhone card.
    /// A blank card carries no band, like an unavailable Readiness.
    private static func stressMetric(summary: HealthSummarySnapshot, now: Date) -> WatchMetric {
        let average = summary.stress.flatMap { stress in
            Calendar.bodyGregorian.isDate(stress.date, inSameDayAs: now) ? stress.averageScore : nil
        }
        let band = average.map { StressBand.band(for: summary.stressCurrentScore ?? $0) }
        return WatchMetric(
            kind: WatchMetricKindKey.stress,
            title: String(localized: "Stress", table: "BodyWatchSnapshotKit"),
            displayValue: average.map { "\($0)" } ?? "--",
            unit: "",
            score: average,
            fillFraction: average.map { min(max(Double($0) / 100, 0), 1) } ?? 0,
            rawValue: average.map(Double.init),
            rangeMin: 0,
            rangeMax: 100,
            levelMin: band?.scoreBounds.min,
            levelMax: band?.scoreBounds.max,
            tint: band?.watchTintComponents,
            statusBand: band.map {
                WatchStatusBand(min: $0.lowerBound, max: $0.upperBound, label: $0.title)
            }
        )
    }

    /// A running daily total (Steps, Active Energy, Resting Energy): today's
    /// total so far as the headline, already in the display unit and grouped
    /// with no decimals like the iPhone card's summary, with the ring filled
    /// against the best day of the week the card carries (`weekValues`, the
    /// same display unit; today included). No ring band and no `measuredAt`:
    /// the headline is a sum over the day, not one sample, so `computedAt` is
    /// the honest watermark. `usesKilojoules` is set for the two energy kinds
    /// only.
    private static func dailyTotalMetric(
        kind: String,
        title: String,
        value: Double?,
        unit: String,
        weekValues: [Double?],
        usesKilojoules: Bool? = nil
    ) -> WatchMetric {
        let high = (weekValues + [value]).compactMap { $0 }.max()
        let fill: Double
        if let value, let high, high > 0 {
            fill = min(max(value / high, 0), 1)
        } else {
            fill = 0
        }
        return WatchMetric(
            kind: kind,
            title: title,
            displayValue: value.map { BodyValueFormat.numberText($0, decimals: 0) } ?? "--",
            unit: value == nil ? "" : unit,
            score: nil,
            fillFraction: fill,
            rawValue: value,
            rangeMin: 0,
            rangeMax: high,
            usesKilojoules: usesKilojoules
        )
    }

    /// Whole minutes of workout time for the day, in the same 0-decimal,
    /// unitless formatting the iPhone uses. No ring is drawn for this kind (the
    /// complication renders the carried `weekly` bars), so the fill stays 0.
    private static func workoutMinutesMetric(
        _ minutes: Double?,
        kind: String = WatchMetricKindKey.workoutMinutes
    ) -> WatchMetric {
        WatchMetric(
            kind: kind,
            title: String(localized: "Weekly Workout Time", table: "BodyWatchSnapshotKit"),
            displayValue: minutes.map { BodyValueFormat.numberText($0, decimals: 0) } ?? "--",
            unit: "",
            score: nil,
            fillFraction: 0
        )
    }

    private static func skinTempMetric(
        _ celsius: Double?,
        seriesValues: [Double],
        pref: BodyValueFormat.TemperatureUnitPreference,
        overrideRange: WatchSeriesRange? = nil
    ) -> WatchMetric {
        // `rangeMin`/`rangeMax` (and the fraction below) stay in the RAW
        // Celsius domain `seriesValues` is already in, matching the domain
        // `seriesRanges(from:)` builds its override in by construction — the
        // display-unit conversion (`temperatureDisplay`) only touches the
        // formatted string, never the carried range/fraction.
        let display = celsius.map { BodyValueFormat.temperatureDisplay(celsius: $0, temperatureUnitPreference: pref) }
        let low = unionMin(seriesValues.min(), overrideRange?.min)
        let high = unionMax(seriesValues.max(), overrideRange?.max)
        return WatchMetric(
            kind: WatchMetricKindKey.wristTemperature,
            title: String(localized: "Skin Temp", table: "BodyWatchSnapshotKit"),
            displayValue: display?.value ?? "--",
            unit: display?.unit ?? "",
            score: nil,
            fillFraction: celsius.map { fraction(of: $0, low: low, high: high, invert: false) } ?? 0,
            rawValue: celsius,
            rangeMin: low,
            rangeMax: high,
            usesFahrenheit: pref == .fahrenheit
        )
    }

    // MARK: - Helpers

    private static func values(_ series: HealthTrendSeries) -> [Double] {
        series.points.map(\.value).filter(\.isFinite)
    }

    /// The recent week as 7 daily values (oldest → today; `nil` for a day with no
    /// reading), using the same daily aggregation as the iPhone "Week" trend chart.
    private static func weekly(_ series: HealthTrendSeries, now: Date) -> [Double?] {
        series.calendarPoints(to: .recentWeek, date: now).map(\.value)
    }

    /// The recent week's daily min/max as 7 slots (oldest → today; `nil` for a
    /// day without a finite low and high, which `calendarPoints` already
    /// drops), over the same days as `weekly(_:now:)`. `nil` when no day has
    /// one, so a trend snapshot without the range series ships no field.
    private static func weeklyRanges(_ series: HealthTrendRangeSeries, now: Date) -> [WatchDayRange?]? {
        let days = series.calendarPoints(to: .recentWeek, date: now).map { point -> WatchDayRange? in
            guard let low = point.lowValue, let high = point.highValue else { return nil }
            return WatchDayRange(low: low, high: high)
        }
        return days.contains { $0 != nil } ? days : nil
    }

    /// The lower of the local series' minimum and an optional override bound —
    /// `nil` override reproduces `values.min()` exactly.
    private static func unionMin(_ localMin: Double?, _ overrideMin: Double?) -> Double? {
        [localMin, overrideMin].compactMap { $0 }.min()
    }

    /// The higher of the local series' maximum and an optional override bound —
    /// `nil` override reproduces `values.max()` exactly.
    private static func unionMax(_ localMax: Double?, _ overrideMax: Double?) -> Double? {
        [localMax, overrideMax].compactMap { $0 }.max()
    }

    /// Position of `value` within `[low, high]`, clamped to 0...1. Degenerate /
    /// missing bounds fall back to a half-full ring.
    private static func fraction(of value: Double, low: Double?, high: Double?, invert: Bool) -> Double {
        guard let low, let high, high > low else { return 0.5 }
        let normalized = min(max((value - low) / (high - low), 0), 1)
        return invert ? 1 - normalized : normalized
    }

}
