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

    /// The value(s) shown on the home preview card, written with the same
    /// summary format BodyHomeView's per-metric cards use. One value for most
    /// metrics; two for the prominent Sleep (score + duration) and Skin Temp
    /// (deviation + actual).
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
        // The summary context of the shared metric table: the same decimals and
        // unit the Home summary card writes. Every metric reached through
        // `number`/`summaryUnit` below has a row, so the fallbacks are
        // unreachable (pinned by `HealthMetricPresentationTests`).
        let summaryFormat = metric.presentation?.summaryFormat
        let summaryUnit = summaryFormat?.unitSuffix ?? ""
        func single(_ value: String, _ unit: String) -> [HealthWidgetDisplayValue] {
            [HealthWidgetDisplayValue(value: value, unit: unit)]
        }
        func number(_ value: Double?) -> String {
            value.map { BodyValueFormat.numberText($0, decimals: summaryFormat?.decimals ?? 0) } ?? "--"
        }

        switch metric {
        case .readiness:
            let score = summary.readiness.score
            return single(score.map { "\($0)" } ?? "--", score == nil ? "" : "%")
        case .heartRate:
            return single(number(summary.heartRate.value), summaryUnit)
        case .restingHeartRate:
            return single(number(summary.restingHeartRate.value), summaryUnit)
        case .heartRateVariability:
            return single(number(summary.heartRateVariability.value), summaryUnit)
        case .respiratoryRate:
            return single(number(summary.respiratoryRate.value), summaryUnit)
        case .oxygenSaturation:
            return single(number(summary.oxygenSaturation.value), summaryUnit)
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
                HealthWidgetDisplayValue(value: score.map { "\($0)" } ?? "--", unit: score == nil ? "" : "pts"),
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
            return single(number(summary.steps.value), summaryUnit)
        case .activeEnergy:
            return single(
                energyValueText(summary.activeEnergy.value, energyUnitPreference, decimals: summaryFormat?.decimals ?? 0),
                energyUnitPreference.unitLabel
            )
        case .restingEnergy:
            return single(
                energyValueText(summary.restingEnergy.value, energyUnitPreference, decimals: summaryFormat?.decimals ?? 0),
                energyUnitPreference.unitLabel
            )
        case .exerciseMinutes:
            return single(number(summary.exerciseMinutes.value), summaryUnit)
        case .trainingLoad:
            return single(number(summary.trainingLoad.value), summaryUnit)
        case .timeInDaylight:
            return single(number(summary.timeInDaylight.value), summaryUnit)
        case .bodyMass:
            let unit = BodyValueFormat.massValue(kilograms: 0, weightUnitPreference: weightUnitPreference).unit
            let value = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(
                    kilograms: $0,
                    weightUnitPreference: weightUnitPreference,
                    decimals: summaryFormat?.decimals ?? 0
                ).value
            } ?? "--"
            return single(value, unit)
        case .bodyFatPercentage:
            return single(number(summary.bodyFatPercentage.value), summaryUnit)
        }
    }

    private static func energyValueText(
        _ kilocalories: Double?,
        _ energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        decimals: Int
    ) -> String {
        kilocalories.map {
            BodyValueFormat.numberText(
                BodyValueFormat.energyValue(kilocalories: $0, energyUnitPreference: energyUnitPreference).value,
                decimals: decimals
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

    // MARK: - Value transforms & formatting (shared with BodyHomeTrendCardFactory)

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

    /// The unit label for the metrics whose unit comes from a unit preference,
    /// in the trend context. `nil` when the unit is a fixed literal (it comes
    /// from the shared metric table) or when the metric has none.
    private static func trendUnitLabel(
        for unitPreference: HealthMetricPresentation.UnitPreferenceKind?,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> String? {
        switch unitPreference {
        case .temperature:
            return BodyValueFormat.temperatureValue(
                celsius: 0,
                temperatureUnitPreference: temperatureUnitPreference
            ).unit
        case .energy:
            return BodyValueFormat.energyValue(
                kilocalories: 0,
                energyUnitPreference: energyUnitPreference
            ).unit
        case .mass:
            return BodyValueFormat.massValue(
                kilograms: 0,
                weightUnitPreference: weightUnitPreference
            ).unit
        case nil:
            return nil
        }
    }

    private static func averageFormatter(
        for metric: HealthWidgetMetric,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> (Double) -> String {
        let presentation = metric.presentation
        let unit = trendUnitLabel(
            for: presentation.flatMap { $0.unitPreference },
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        )

        // Sleep is the one metric whose trend text is a duration rather than a
        // number with a unit, so it has no `trendFormat` row.
        guard let format = presentation?.trendFormat else {
            return { BodyValueFormat.sleepDurationText(for: $0 * 60 * 60) }
        }
        return { format.text($0, unit: unit) }
    }

    /// Formats a raw metric value (the same units `metricTrend` transforms
    /// from: celsius, kilocalories, kilograms) the way this widget metric's
    /// trend average text does, split into the numeric text and its unit.
    /// Used to check parity with `BodyHomeTrendCardFactory.formattedValue`.
    static func formattedValue(
        _ value: Double,
        for metric: HealthWidgetMetric,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> (value: String, unit: String?) {
        let transform = valueTransform(
            for: metric,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        )
        let transformed = transform(value)
        let presentation = metric.presentation

        // Sleep is the one metric whose trend text is a duration rather than a
        // number with a unit, so it has no `trendFormat` row.
        guard let format = presentation?.trendFormat else {
            return (BodyValueFormat.sleepDurationText(for: transformed * 60 * 60), nil)
        }
        let unit = format.unitSuffix ?? trendUnitLabel(
            for: presentation.flatMap { $0.unitPreference },
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        )
        return (BodyValueFormat.numberText(transformed, decimals: format.decimals), unit)
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
