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
        sleepStageSnapshot: SleepStageSnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        primarySourceName: (HealthMetricKind) -> String?,
        secondarySourceName: (HealthMetricKind) -> String?,
        date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> HealthWidgetSnapshot {
        let metricTrends = HealthWidgetMetric.allCases.map { metric in
            metricTrend(
                for: metric,
                trends: trends,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                primarySourceName: primarySourceName,
                secondarySourceName: secondarySourceName,
                date: date,
                calendar: calendar
            )
        }

        return HealthWidgetSnapshot(
            generatedDate: date,
            metricTrends: metricTrends,
            sleep: sleepStages(
                from: sleepStageSnapshot,
                sourceName: primarySourceName(.sleep),
                calendar: calendar
            )
        )
    }

    // MARK: - Metric trends

    private static func metricTrend(
        for metric: HealthWidgetMetric,
        trends: HealthTrendSnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        primarySourceName: (HealthMetricKind) -> String?,
        secondarySourceName: (HealthMetricKind) -> String?,
        date: Date,
        calendar: Calendar
    ) -> HealthWidgetMetricTrend {
        let kind = metric.healthMetricKind
        let transform = valueTransform(
            for: metric,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference
        )
        let format = averageFormatter(
            for: metric,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference
        )

        let primarySeries = trends.series(for: kind).mapValues(transform)
        let secondaryName = secondarySourceName(kind)
        let rawSecondary = trends.secondarySeries(for: kind)
        let secondarySeries = (secondaryName != nil && !rawSecondary.isEmpty)
            ? rawSecondary.mapValues(transform)
            : nil

        return HealthWidgetMetricTrend(
            metric: metric,
            primarySourceName: primarySourceName(kind),
            secondarySourceName: secondarySeries == nil ? nil : secondaryName,
            week: rangeTrend(
                range: .week,
                primarySeries: primarySeries,
                secondarySeries: secondarySeries,
                format: format,
                date: date,
                calendar: calendar
            ),
            month: rangeTrend(
                range: .month,
                primarySeries: primarySeries,
                secondarySeries: secondarySeries,
                format: format,
                date: date,
                calendar: calendar
            )
        )
    }

    private static func rangeTrend(
        range: HealthWidgetTrendRange,
        primarySeries: HealthTrendSeries,
        secondarySeries: HealthTrendSeries?,
        format: (Double) -> String,
        date: Date,
        calendar: Calendar
    ) -> HealthWidgetRangeTrend {
        HealthWidgetRangeTrend(
            primary: widgetSeries(
                from: primarySeries,
                range: range,
                format: format,
                date: date,
                calendar: calendar
            ),
            secondary: secondarySeries.map {
                widgetSeries(from: $0, range: range, format: format, date: date, calendar: calendar)
            }
        )
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

        let finiteValues = points.compactMap(\.value)
        let averageText = finiteValues.isEmpty
            ? nil
            : format(finiteValues.reduce(0, +) / Double(finiteValues.count))

        return HealthWidgetTrendSeries(points: points, averageText: averageText)
    }

    // MARK: - Value transforms & formatting (mirrors BodyHomeTrendCardFactory)

    private static func valueTransform(
        for metric: HealthWidgetMetric,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference
    ) -> (Double) -> Double {
        switch metric {
        case .wristTemperature:
            return { BodyValueFormat.temperatureValue(celsius: $0, temperatureUnitPreference: temperatureUnitPreference).value }
        case .activeEnergy, .restingEnergy:
            return { BodyValueFormat.energyValue(kilocalories: $0, energyUnitPreference: energyUnitPreference).value }
        default:
            return { $0 }
        }
    }

    private static func averageFormatter(
        for metric: HealthWidgetMetric,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference
    ) -> (Double) -> String {
        let temperatureUnit = BodyValueFormat.temperatureValue(
            celsius: 0,
            temperatureUnitPreference: temperatureUnitPreference
        ).unit
        let energyUnit = BodyValueFormat.energyValue(
            kilocalories: 0,
            energyUnitPreference: energyUnitPreference
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

    private static func followsSystemUnits(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: BodyAppearancePreference.followsSystemUnitsKey) as? Bool ?? true
    }
}
