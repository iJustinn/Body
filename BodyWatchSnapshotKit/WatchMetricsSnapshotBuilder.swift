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
        perKindDataAsOf: ((String) -> Date?)? = nil
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
            return stampedMetric
        }
        return WatchMetricsSnapshot(
            generatedAt: now,
            lastRefreshDate: lastRefreshDate,
            metrics: stamped,
            sleepNight: sleepNight,
            sleepStages: sleepStages
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
        let score = readiness.score
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
            weeklyCurrentValue: readiness.activityDrainMorningScore != nil
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
            rangeMax: high
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
