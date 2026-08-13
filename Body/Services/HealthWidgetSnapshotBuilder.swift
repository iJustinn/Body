//
//  HealthWidgetSnapshotBuilder.swift
//  Body
//
//  Converts the app's rich health types (HealthTrendSnapshot, SleepStageSnapshot)
//  into the slim, self-contained HealthWidgetSnapshot that the widget extension
//  reads from the App Group. Unit conversions and value formatting happen here,
//  where the user's preferences are available, so the widget stays preference-free.
//

import Foundation

extension HealthWidgetMetric {
    /// The app-side metric kind backing this widget metric.
    var healthMetricKind: HealthMetricKind {
        switch self {
        case .readiness: return .readiness
        case .heartRate: return .heartRate
        case .restingHeartRate: return .restingHeartRate
        case .heartRateVariability: return .heartRateVariability
        case .respiratoryRate: return .respiratoryRate
        case .oxygenSaturation: return .oxygenSaturation
        case .sleep: return .sleep
        case .wristTemperature: return .wristTemperature
        case .steps: return .steps
        case .activeEnergy: return .activeEnergy
        case .restingEnergy: return .restingEnergy
        case .exerciseMinutes: return .exerciseMinutes
        case .trainingLoad: return .trainingLoad
        case .timeInDaylight: return .timeInDaylight
        case .bodyMass: return .bodyMass
        case .bodyFatPercentage: return .bodyFatPercentage
        }
    }

    /// The kind whose source selection applies to this metric. Weight and Body
    /// Fat are fetched and source-selected together under `.basics` (see the
    /// `sourceKind: .basics` fetches in HealthKitFetchEngine), so their source
    /// name must be resolved there. `.bodyMass`/`.bodyFatPercentage` are not
    /// source-selectable and would otherwise fall back to the default source.
    var sourceSelectionKind: HealthMetricKind {
        switch self {
        case .bodyMass, .bodyFatPercentage:
            return .basics
        default:
            return healthMetricKind
        }
    }
}

private extension HealthWidgetTrendRange {
    var bodyRange: BodyHealthTrendRange {
        switch self {
        case .week: return .recentWeek
        case .month: return .recentMonth
        }
    }
}

enum HealthWidgetSnapshotBuilder {
    static func make(
        trends: HealthTrendSnapshot,
        summary: HealthSummarySnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference,
        idealSleepDuration: TimeInterval,
        showSleepScore: Bool,
        primarySourceName: (HealthMetricKind) -> String?,
        date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> HealthWidgetSnapshot {
        // Guard against carrying over a stale, previously-completed night into
        // the widget after midnight, before today's own sleep session exists.
        var summary = summary
        summary.sleep = summary.sleep.asOf(date, calendar: calendar) ?? SleepSummary(duration: nil)
        let sleepStageSnapshot = summary.sleep.stageSnapshot

        let metricTrends = HealthWidgetMetric.allCases.map { metric in
            metricTrend(
                for: metric,
                trends: trends,
                summary: summary,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                weightUnitPreference: weightUnitPreference,
                idealSleepDuration: idealSleepDuration,
                showSleepScore: showSleepScore,
                primarySourceName: primarySourceName,
                date: date,
                calendar: calendar
            )
        }

        return HealthWidgetSnapshot(
            generatedDate: date,
            metricTrends: metricTrends,
            sleep: sleepStages(
                from: sleepStageSnapshot.mainSession,
                sourceName: primarySourceName(.sleep),
                calendar: calendar
            )
        )
    }

    // MARK: - Metric trends

    private static func metricTrend(
        for metric: HealthWidgetMetric,
        trends: HealthTrendSnapshot,
        summary: HealthSummarySnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference,
        idealSleepDuration: TimeInterval,
        showSleepScore: Bool,
        primarySourceName: (HealthMetricKind) -> String?,
        date: Date,
        calendar: Calendar
    ) -> HealthWidgetMetricTrend {
        let kind = metric.healthMetricKind
        let transform = valueTransform(
            for: metric,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        )
        let format = averageFormatter(
            for: metric,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        )

        let primarySeries = trends.series(for: kind).mapValues(transform)

        return HealthWidgetMetricTrend(
            metric: metric,
            primarySourceName: primarySourceName(kind),
            week: widgetSeries(from: primarySeries, range: .week, format: format, date: date, calendar: calendar),
            month: widgetSeries(from: primarySeries, range: .month, format: format, date: date, calendar: calendar),
            displayValues: displayValues(
                for: metric,
                summary: summary,
                trends: trends,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                weightUnitPreference: weightUnitPreference,
                idealSleepDuration: idealSleepDuration,
                showSleepScore: showSleepScore,
                calendar: calendar
            )
        )
    }

    /// The value(s) shown on the home preview card, mirroring BodyHomeView's
    /// per-metric card construction. One value for most metrics; two for the
    /// prominent Sleep (score + duration) and Skin Temp (deviation + actual).
    private static func displayValues(
        for metric: HealthWidgetMetric,
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference,
        idealSleepDuration: TimeInterval,
        showSleepScore: Bool,
        calendar: Calendar
    ) -> [HealthWidgetDisplayValue] {
        func single(_ value: String, _ unit: String) -> [HealthWidgetDisplayValue] {
            [HealthWidgetDisplayValue(value: value, unit: unit)]
        }
        func number(_ value: Double?, _ decimals: Int) -> String {
            value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--"
        }

        switch metric {
        case .readiness:
            let score = summary.readiness.score
            return single(score.map { "\($0)" } ?? "--", score == nil ? "" : "%")
        case .heartRate:
            return single(number(summary.heartRate.value, 0), "bpm")
        case .restingHeartRate:
            return single(number(summary.restingHeartRate.value, 0), "bpm")
        case .heartRateVariability:
            return single(number(summary.heartRateVariability.value, 1), "ms")
        case .respiratoryRate:
            return single(number(summary.respiratoryRate.value, 0), "br/min")
        case .oxygenSaturation:
            return single(number(summary.oxygenSaturation.value, 0), "%")
        case .sleep:
            let duration = summary.sleep.duration.map { BodyValueFormat.sleepDurationText(for: $0) } ?? "--"
            guard showSleepScore else {
                return single(duration, "")
            }
            let score = SleepScoreSummary(
                sleep: summary.sleep,
                idealSleepDuration: idealSleepDuration,
                recentSleepHistory: trends.sleepHistory,
                on: summary.sleep.stageSnapshot.date,
                calendar: calendar
            )?.total
            return [
                HealthWidgetDisplayValue(value: score.map { "\($0)" } ?? "--", unit: score == nil ? "" : "PTS"),
                HealthWidgetDisplayValue(value: duration, unit: "")
            ]
        case .wristTemperature:
            let unit = BodyValueFormat.temperatureDisplay(
                celsius: 0,
                temperatureUnitPreference: temperatureUnitPreference
            ).unit
            let actual = summary.wristTemperature.value.map {
                BodyValueFormat.temperatureDisplay(celsius: $0, temperatureUnitPreference: temperatureUnitPreference).value
            } ?? "--"
            let deviation = wristTemperatureBaselineDeviationDisplay(
                currentCelsius: summary.wristTemperature.value,
                series: trends.series(for: .wristTemperature),
                temperatureUnitPreference: temperatureUnitPreference
            )
            return [
                HealthWidgetDisplayValue(value: deviation.value, unit: deviation.unit),
                HealthWidgetDisplayValue(value: actual, unit: unit)
            ]
        case .steps:
            return single(number(summary.steps.value, 0), "")
        case .activeEnergy:
            return single(energyValueText(summary.activeEnergy.value, energyUnitPreference), energyUnitPreference.unitLabel)
        case .restingEnergy:
            return single(energyValueText(summary.restingEnergy.value, energyUnitPreference), energyUnitPreference.unitLabel)
        case .exerciseMinutes:
            return single(number(summary.exerciseMinutes.value, 0), "")
        case .trainingLoad:
            return single(number(summary.trainingLoad.value, 2), "")
        case .timeInDaylight:
            return single(number(summary.timeInDaylight.value, 0), "min")
        case .bodyMass:
            let unit = BodyValueFormat.massValue(kilograms: 0, weightUnitPreference: weightUnitPreference).unit
            let value = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(kilograms: $0, weightUnitPreference: weightUnitPreference, decimals: 2).value
            } ?? "--"
            return single(value, unit)
        case .bodyFatPercentage:
            return single(number(summary.bodyFatPercentage.value, 1), "%")
        }
    }

    private static func energyValueText(
        _ kilocalories: Double?,
        _ energyUnitPreference: BodyValueFormat.EnergyUnitPreference
    ) -> String {
        kilocalories.map {
            BodyValueFormat.numberText(
                BodyValueFormat.energyValue(kilocalories: $0, energyUnitPreference: energyUnitPreference).value,
                decimals: 0
            )
        } ?? "--"
    }

    private static func widgetSeries(
        from series: HealthTrendSeries,
        range: HealthWidgetTrendRange,
        format: (Double) -> String,
        date: Date,
        calendar: Calendar
    ) -> HealthWidgetTrendSeries {
        let calendarPoints = series.calendarPoints(to: range.bodyRange, calendar: calendar, date: date)
        let points = calendarPoints.map { point in
            HealthWidgetPoint(
                date: point.date,
                value: point.value.flatMap { $0.isFinite ? $0 : nil }
            )
        }

        var widgetSeries = HealthWidgetTrendSeries(points: points, averageText: nil)
        widgetSeries.averageText = widgetSeries.average.map(format)
        widgetSeries.latestText = widgetSeries.latest.map(format)
        return widgetSeries
    }

    // MARK: - Value transforms & formatting (mirrors BodyHomeTrendCardFactory)

    private static func valueTransform(
        for metric: HealthWidgetMetric,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> (Double) -> Double {
        switch metric {
        case .wristTemperature:
            return { BodyValueFormat.temperatureValue(celsius: $0, temperatureUnitPreference: temperatureUnitPreference).value }
        case .activeEnergy, .restingEnergy:
            return { BodyValueFormat.energyValue(kilocalories: $0, energyUnitPreference: energyUnitPreference).value }
        case .bodyMass:
            return { BodyValueFormat.massValue(kilograms: $0, weightUnitPreference: weightUnitPreference).value }
        default:
            return { $0 }
        }
    }

    private static func averageFormatter(
        for metric: HealthWidgetMetric,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> (Double) -> String {
        let temperatureUnit = BodyValueFormat.temperatureValue(
            celsius: 0,
            temperatureUnitPreference: temperatureUnitPreference
        ).unit
        let energyUnit = BodyValueFormat.energyValue(
            kilocalories: 0,
            energyUnitPreference: energyUnitPreference
        ).unit
        let massUnit = BodyValueFormat.massValue(
            kilograms: 0,
            weightUnitPreference: weightUnitPreference
        ).unit

        switch metric {
        case .readiness, .oxygenSaturation:
            return { BodyValueFormat.numberText($0, decimals: 0) + "%" }
        case .heartRate, .restingHeartRate:
            return { BodyValueFormat.numberText($0, decimals: 0) + " BPM" }
        case .heartRateVariability:
            return { BodyValueFormat.numberText($0, decimals: 0) + " ms" }
        case .respiratoryRate:
            return { BodyValueFormat.numberText($0, decimals: 0) + " br/min" }
        case .sleep:
            return { BodyValueFormat.sleepDurationText(for: $0 * 60 * 60) }
        case .wristTemperature:
            return { BodyValueFormat.numberText($0, decimals: 1) + " " + temperatureUnit }
        case .steps:
            return { BodyValueFormat.numberText($0, decimals: 0) + " steps" }
        case .activeEnergy, .restingEnergy:
            return { BodyValueFormat.numberText($0, decimals: 0) + " " + energyUnit }
        case .exerciseMinutes, .timeInDaylight:
            return { BodyValueFormat.numberText($0, decimals: 0) + " min" }
        case .trainingLoad:
            return { BodyValueFormat.numberText($0, decimals: 2) }
        case .bodyMass:
            return { BodyValueFormat.numberText($0, decimals: 1) + " " + massUnit }
        case .bodyFatPercentage:
            return { BodyValueFormat.numberText($0, decimals: 1) + "%" }
        }
    }

    // MARK: - Sleep stages

    private static func sleepStages(
        from snapshot: SleepStageSnapshot,
        sourceName: String?,
        calendar: Calendar
    ) -> HealthWidgetSleepStages {
        let segments = snapshot.segments.compactMap { segment -> HealthWidgetSleepSegment? in
            guard let stage = HealthWidgetSleepStage(rawValue: segment.stage.rawValue) else {
                return nil
            }
            return HealthWidgetSleepSegment(
                stage: stage,
                startDate: segment.startDate,
                endDate: segment.endDate
            )
        }

        let night = snapshot.date.map { calendar.startOfDay(for: $0) }
        return HealthWidgetSleepStages(
            night: night,
            sourceName: segments.isEmpty ? nil : sourceName,
            segments: segments
        )
    }

    // MARK: - Unit preference resolution (mirrors BodyHomeView)

    static func storedTemperatureUnitPreference(
        defaults: UserDefaults = .standard
    ) -> BodyValueFormat.TemperatureUnitPreference {
        if followsSystemUnits(defaults: defaults) {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }
        let rawValue = defaults.string(forKey: BodyAppearancePreference.selectedTemperatureUnitKey)
            ?? BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: rawValue)
    }

    static func storedEnergyUnitPreference(
        defaults: UserDefaults = .standard
    ) -> BodyValueFormat.EnergyUnitPreference {
        if followsSystemUnits(defaults: defaults) {
            return BodyValueFormat.EnergyUnitPreference.systemValue(locale: .current)
        }
        let rawValue = defaults.string(forKey: BodyAppearancePreference.selectedEnergyUnitKey)
            ?? BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
        return BodyValueFormat.EnergyUnitPreference.storedValue(from: rawValue)
    }

    static func storedWeightUnitPreference(
        defaults: UserDefaults = .standard
    ) -> BodyValueFormat.WeightUnitPreference {
        if followsSystemUnits(defaults: defaults) {
            return BodyValueFormat.WeightUnitPreference.systemValue(locale: .current)
        }
        let rawValue = defaults.string(forKey: BodyAppearancePreference.selectedWeightUnitKey)
            ?? BodyValueFormat.WeightUnitPreference.defaultValue.rawValue
        return BodyValueFormat.WeightUnitPreference.storedValue(from: rawValue)
    }

    static func storedShowSleepScore(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: BodyAppearancePreference.showSleepScoreKey) as? Bool ?? true
    }

    private static func followsSystemUnits(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: BodyAppearancePreference.followsSystemUnitsKey) as? Bool ?? true
    }
}
