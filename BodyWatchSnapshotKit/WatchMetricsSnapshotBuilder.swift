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
        now: Date = Date()
    ) -> WatchMetricsSnapshot {
        let tempPref = temperatureUnitPreference

        // Mirror the iPhone's Data > Permissions: omit hidden categories entirely
        // so the watch (and its live HR/HRV refresh) can't surface data the user
        // hid. `.heart` gates HR, HRV, and Resting HR.
        var metrics: [WatchMetric] = [readinessMetric(summary.readiness)]

        if permissionSelection.includes(.sleep) {
            metrics.append(sleepMetric(
                summary.sleep,
                recentSleepHistory: trends.sleepHistory,
                idealSleepDuration: idealSleepDuration,
                showScore: showSleepScore
            ))
        }
        if permissionSelection.includes(.heart) {
            metrics.append(rangeMetric(
                kind: WatchMetricKindKey.heartRate, title: "Heart Rate", value: summary.heartRate.value,
                unit: "bpm", decimals: 0,
                seriesValues: values(trends.heartRate)
            ))
            metrics.append(rangeMetric(
                kind: WatchMetricKindKey.heartRateVariability, title: "HRV", value: summary.heartRateVariability.value,
                unit: "ms", decimals: 0,
                seriesValues: values(trends.heartRateVariability)
            ))
            metrics.append(rangeMetric(
                kind: WatchMetricKindKey.restingHeartRate, title: "Resting HR", value: summary.restingHeartRate.value,
                unit: "bpm", decimals: 0,
                seriesValues: values(trends.restingHeartRate), invert: true
            ))
        }
        if permissionSelection.includes(.workouts) {
            metrics.append(trainingLoadMetric(summary.trainingLoad.value))
        }
        if permissionSelection.includes(.wristTemperature) {
            metrics.append(skinTempMetric(
                summary.wristTemperature.value,
                seriesValues: values(trends.wristTemperature),
                pref: tempPref
            ))
        }

        let stamped = metrics.map { metric -> WatchMetric in
            var stampedMetric = metric
            stampedMetric.computedAt = lastRefreshDate
            return stampedMetric
        }
        return WatchMetricsSnapshot(generatedAt: now, lastRefreshDate: lastRefreshDate, metrics: stamped)
    }

    // MARK: - Per-metric builders

    private static func readinessMetric(_ readiness: ReadinessSummary) -> WatchMetric {
        let score = readiness.score
        let status = ReadinessStatus.status(for: score)
        return WatchMetric(
            kind: WatchMetricKindKey.readiness,
            title: "Readiness",
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
            tint: status.watchTintComponents
        )
    }

    private static func sleepMetric(
        _ sleep: SleepSummary,
        recentSleepHistory: SleepHistorySnapshot,
        idealSleepDuration: TimeInterval,
        showScore: Bool
    ) -> WatchMetric {
        // Honor the phone's "Show Sleep Score" toggle: when off, omit the score
        // so the watch (and complications, which read `metric.score`) don't show it.
        // Compute the score with the user's sleep-duration goal + recent history
        // for vitals baselines, matching the iPhone (the bare `sleep.score` would
        // use the 8h default + empty history and diverge from the phone).
        let total = showScore
            ? SleepScoreSummary(
                sleep: sleep,
                idealSleepDuration: idealSleepDuration,
                recentSleepHistory: recentSleepHistory,
                on: sleep.stageSnapshot.date
            )?.total
            : nil
        return WatchMetric(
            kind: WatchMetricKindKey.sleep,
            title: "Sleep",
            displayValue: sleep.duration.map { BodyValueFormat.sleepDurationText(for: $0) } ?? "--",
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
        invert: Bool = false
    ) -> WatchMetric {
        WatchMetric(
            kind: kind,
            title: title,
            displayValue: value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: value == nil ? "" : unit,
            score: nil,
            fillFraction: value.map { fraction(of: $0, in: seriesValues, invert: invert) } ?? 0,
            rawValue: value,
            rangeMin: seriesValues.min(),
            rangeMax: seriesValues.max()
        )
    }

    private static func trainingLoadMetric(_ value: Double?) -> WatchMetric {
        let interval = TrainingLoadInterval.interval(for: value)
        return WatchMetric(
            kind: WatchMetricKindKey.trainingLoad,
            title: "Training Load",
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
            tint: interval?.watchTintComponents
        )
    }

    private static func skinTempMetric(
        _ celsius: Double?,
        seriesValues: [Double],
        pref: BodyValueFormat.TemperatureUnitPreference
    ) -> WatchMetric {
        let display = celsius.map { BodyValueFormat.temperatureDisplay(celsius: $0, temperatureUnitPreference: pref) }
        return WatchMetric(
            kind: WatchMetricKindKey.wristTemperature,
            title: "Skin Temp",
            displayValue: display?.value ?? "--",
            unit: display?.unit ?? "",
            score: nil,
            fillFraction: celsius.map { fraction(of: $0, in: seriesValues, invert: false) } ?? 0,
            rawValue: celsius,
            rangeMin: seriesValues.min(),
            rangeMax: seriesValues.max()
        )
    }

    // MARK: - Helpers

    private static func values(_ series: HealthTrendSeries) -> [Double] {
        series.points.map(\.value).filter(\.isFinite)
    }

    /// Position of `value` within `[min, max]` of the recent series, clamped to
    /// 0...1. Degenerate / empty ranges fall back to a half-full ring.
    private static func fraction(of value: Double, in values: [Double], invert: Bool) -> Double {
        guard let low = values.min(), let high = values.max(), high > low else { return 0.5 }
        let normalized = min(max((value - low) / (high - low), 0), 1)
        return invert ? 1 - normalized : normalized
    }

}
