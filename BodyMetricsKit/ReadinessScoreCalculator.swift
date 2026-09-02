//
//  ReadinessScoreCalculator.swift
//  Body
//

import Foundation

enum ReadinessScoreCalculator {
    struct DailyValue: Equatable {
        var date: Date
        var value: Double
    }

    struct Baseline: Equatable {
        var median: Double
        var spread: Double
        var validDayCount: Int
    }

    private enum ReadinessMetric: Hashable {
        case heartRateVariability
        case restingHeartRate
        case trainingLoad
        case respiratoryRate
        case oxygenSaturation
        case wristTemperature
    }

    /// A source-consistent reading: the value and the baseline always come
    /// from the same series (overnight or whole-day), never mixed.
    private struct MetricReading {
        var value: Double
        var baseline: Baseline
    }

    private struct AutonomicAssessment {
        var combinedZScore: Double
        var drivers: [ReadinessDriver]
        var bestBaselineDayCount: Int
    }

    private struct SleepAssessment {
        var componentScore: Int
        var quality: Double
        var drivers: [ReadinessDriver]
        var historyDayCount: Int
    }

    private struct TrainingAssessment {
        var componentScore: Int
        var ratio: Double
        var driver: ReadinessDriver?
        var pointCount: Int
    }

    private struct VitalsAssessment {
        var componentScore: Int
        var maxAnomalyProgress: Double
        var drivers: [ReadinessDriver]
        var bestBaselineDayCount: Int
    }

    private struct ReadinessDailySeriesContext {
        private let calendar: Calendar
        private let wholeDayValuesByMetric: [ReadinessMetric: [Date: Double]]
        private let wholeDayBaselineCachesByMetric: [ReadinessMetric: ReadinessBaselineCache]
        private let overnightValuesByMetric: [ReadinessMetric: [Date: Double]]
        private let overnightBaselineCachesByMetric: [ReadinessMetric: ReadinessBaselineCache]

        init(
            trends: HealthTrendSnapshot,
            healthSummary: HealthSummarySnapshot,
            today: Date,
            calendar: Calendar
        ) {
            self.calendar = calendar
            wholeDayValuesByMetric = [
                .heartRateVariability: Self.currentValuesByDay(from: trends.heartRateVariability, calendar: calendar),
                .restingHeartRate: Self.currentValuesByDay(from: trends.restingHeartRate, calendar: calendar),
                .trainingLoad: Self.currentValuesByDay(from: trends.trainingLoad, calendar: calendar),
                .respiratoryRate: Self.currentValuesByDay(from: trends.respiratoryRate, calendar: calendar),
                .oxygenSaturation: Self.currentValuesByDay(from: trends.oxygenSaturation, calendar: calendar),
                .wristTemperature: Self.currentValuesByDay(from: trends.wristTemperature, calendar: calendar)
            ]
            wholeDayBaselineCachesByMetric = [
                .heartRateVariability: ReadinessBaselineCache(series: trends.heartRateVariability, floor: MetricFloor.hrv, calendar: calendar),
                .restingHeartRate: ReadinessBaselineCache(series: trends.restingHeartRate, floor: MetricFloor.heartRate, calendar: calendar),
                .respiratoryRate: ReadinessBaselineCache(series: trends.respiratoryRate, floor: MetricFloor.respiratoryRate, calendar: calendar),
                .oxygenSaturation: ReadinessBaselineCache(series: trends.oxygenSaturation, floor: MetricFloor.oxygenSaturation, calendar: calendar),
                .wristTemperature: ReadinessBaselineCache(series: trends.wristTemperature, floor: MetricFloor.wristTemperature, calendar: calendar)
            ]

            let currentDaySleep = ReadinessScoreCalculator.currentDaySleepSummary(
                healthSummary.sleep,
                for: today,
                today: today,
                calendar: calendar
            )
            let overnightSeriesByMetric: [ReadinessMetric: HealthTrendSeries] = [
                .heartRateVariability: Self.overnightSeries(\.heartRateVariability, sleepHistory: trends.sleepHistory, currentDaySleep: currentDaySleep, today: today, calendar: calendar),
                .restingHeartRate: Self.overnightSeries(\.heartRate, sleepHistory: trends.sleepHistory, currentDaySleep: currentDaySleep, today: today, calendar: calendar),
                .respiratoryRate: Self.overnightSeries(\.respiratoryRate, sleepHistory: trends.sleepHistory, currentDaySleep: currentDaySleep, today: today, calendar: calendar),
                .oxygenSaturation: Self.overnightSeries(\.oxygenSaturation, sleepHistory: trends.sleepHistory, currentDaySleep: currentDaySleep, today: today, calendar: calendar),
                .wristTemperature: Self.overnightSeries(\.wristTemperatureCelsius, sleepHistory: trends.sleepHistory, currentDaySleep: currentDaySleep, today: today, calendar: calendar)
            ]
            overnightValuesByMetric = overnightSeriesByMetric.mapValues {
                Self.currentValuesByDay(from: $0, calendar: calendar)
            }
            overnightBaselineCachesByMetric = [
                .heartRateVariability: ReadinessBaselineCache(series: overnightSeriesByMetric[.heartRateVariability] ?? .empty, floor: MetricFloor.hrv, calendar: calendar),
                .restingHeartRate: ReadinessBaselineCache(series: overnightSeriesByMetric[.restingHeartRate] ?? .empty, floor: MetricFloor.heartRate, calendar: calendar),
                .respiratoryRate: ReadinessBaselineCache(series: overnightSeriesByMetric[.respiratoryRate] ?? .empty, floor: MetricFloor.respiratoryRate, calendar: calendar),
                .oxygenSaturation: ReadinessBaselineCache(series: overnightSeriesByMetric[.oxygenSaturation] ?? .empty, floor: MetricFloor.oxygenSaturation, calendar: calendar),
                .wristTemperature: ReadinessBaselineCache(series: overnightSeriesByMetric[.wristTemperature] ?? .empty, floor: MetricFloor.wristTemperature, calendar: calendar)
            ]
        }

        func wholeDayValue(on date: Date, metric: ReadinessMetric) -> Double? {
            wholeDayValuesByMetric[metric]?[calendar.startOfDay(for: date)]
        }

        func wholeDayBaseline(for date: Date, metric: ReadinessMetric) -> Baseline? {
            wholeDayBaselineCachesByMetric[metric]?.baseline(for: date)
        }

        func overnightValue(on date: Date, metric: ReadinessMetric) -> Double? {
            overnightValuesByMetric[metric]?[calendar.startOfDay(for: date)]
        }

        func overnightBaseline(for date: Date, metric: ReadinessMetric) -> Baseline? {
            overnightBaselineCachesByMetric[metric]?.baseline(for: date)
        }

        private static func currentValuesByDay(
            from series: HealthTrendSeries,
            calendar: Calendar
        ) -> [Date: Double] {
            var latestPointByDay: [Date: HealthTrendDataPoint] = [:]
            for point in series.points where point.value.isFinite {
                let day = calendar.startOfDay(for: point.date)
                if let existing = latestPointByDay[day], existing.date > point.date {
                    continue
                }
                latestPointByDay[day] = point
            }

            return latestPointByDay.mapValues(\.value)
        }

        /// One point per night from the hydrated sleep-history vitals, plus
        /// the current day's sleep summary when history does not cover it.
        private static func overnightSeries(
            _ vital: KeyPath<SleepVitalsSummary, Double?>,
            sleepHistory: SleepHistorySnapshot,
            currentDaySleep: SleepSummary?,
            today: Date,
            calendar: Calendar
        ) -> HealthTrendSeries {
            var valuesByDay: [Date: Double] = [:]
            for day in sleepHistory.days {
                guard let value = day.summary.vitals[keyPath: vital], value.isFinite else {
                    continue
                }
                valuesByDay[calendar.startOfDay(for: day.date)] = value
            }

            let todayKey = calendar.startOfDay(for: today)
            if valuesByDay[todayKey] == nil,
               let value = currentDaySleep?.vitals[keyPath: vital],
               value.isFinite {
                valuesByDay[todayKey] = value
            }

            return HealthTrendSeries(points: valuesByDay.map { day, value in
                HealthTrendDataPoint(date: day, value: value)
            })
        }
    }

    private struct ReadinessBaselineCache {
        private struct BaselinePoint {
            var day: Date
            var date: Date
            var value: Double
        }

        private let points: [BaselinePoint]
        private let floor: Double
        private let calendar: Calendar

        init(series: HealthTrendSeries, floor: Double, calendar: Calendar) {
            self.floor = floor
            self.calendar = calendar
            points = series.points.compactMap { point in
                guard point.value.isFinite else {
                    return nil
                }

                return BaselinePoint(
                    day: calendar.startOfDay(for: point.date),
                    date: point.date,
                    value: point.value
                )
            }
            .sorted { first, second in
                guard first.day == second.day else {
                    return first.day < second.day
                }

                return first.date < second.date
            }
        }

        func baseline(for date: Date) -> Baseline? {
            let scoringDay = calendar.startOfDay(for: date)
            let oldestDay = calendar.date(
                byAdding: .day,
                value: -ReadinessScoreCalculator.baselineDayCount,
                to: scoringDay
            ) ?? scoringDay.addingTimeInterval(-Double(ReadinessScoreCalculator.baselineDayCount) * 86_400)
            let recentCutoff = calendar.date(
                byAdding: .day,
                value: -ReadinessScoreCalculator.recentExclusionDayCount,
                to: scoringDay
            ) ?? scoringDay

            let startIndex = lowerBound(for: oldestDay)
            let endIndex = lowerBound(for: scoringDay)
            guard startIndex < endIndex else {
                return nil
            }

            let priorPoints = Array(points[startIndex..<endIndex])
            let olderPoints = priorPoints.filter { $0.day < recentCutoff }
            let baselinePoints = olderPoints.count >= 28 ? olderPoints : priorPoints
            let numericValues = baselinePoints.map(\.value).sorted()

            guard numericValues.count >= ReadinessScoreCalculator.minimumBaselineDayCount else {
                return nil
            }

            let medianValue = ReadinessScoreCalculator.median(numericValues)
            let deviations = numericValues.map { abs($0 - medianValue) }.sorted()
            let spread = max(1.4826 * ReadinessScoreCalculator.median(deviations), floor)

            return Baseline(
                median: medianValue,
                spread: spread,
                validDayCount: numericValues.count
            )
        }

        private func lowerBound(for day: Date) -> Int {
            var lower = 0
            var upper = points.count

            while lower < upper {
                let middle = (lower + upper) / 2
                if points[middle].day < day {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }

            return lower
        }
    }

    static let baselineDayCount = 56
    static let recentExclusionDayCount = 3
    static let minimumBaselineDayCount = 14

    static func summary(
        on date: Date,
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        calendar: Calendar = .bodyGregorian,
        today: Date = Date()
    ) -> ReadinessSummary {
        readinessSummary(
            on: date,
            healthSummary: healthSummary,
            trends: trends,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar,
            today: today,
            context: ReadinessDailySeriesContext(
                trends: trends,
                healthSummary: healthSummary,
                today: today,
                calendar: calendar
            )
        )
    }

    private static func readinessSummary(
        on date: Date,
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        idealSleepDuration: TimeInterval,
        calendar: Calendar,
        today: Date,
        context: ReadinessDailySeriesContext
    ) -> ReadinessSummary {
        let autonomic = autonomicAssessment(on: date, context: context)
        let sleep = sleepAssessment(
            on: date,
            healthSummary: healthSummary,
            trends: trends,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar,
            today: today
        )
        let training = trainingAssessment(on: date, trends: trends, context: context)
        let vitals = vitalsAssessment(on: date, context: context)

        guard autonomic != nil || sleep != nil || training != nil || vitals != nil else {
            return .unavailable
        }

        // The autonomic recovery core anchors the score; the other signals
        // act as bounded multiplicative penalties so good sleep or light
        // training can never dilute a crashed core back into the High band.
        let core = autonomic.map { recoveryCore(fromZScore: $0.combinedZScore) } ?? neutralCore
        let sleepFactor = sleep.map { sleepModifierFloor + (1 - sleepModifierFloor) * $0.quality } ?? 1
        let strainModifier = training.map { strainFactor(forTrainingLoadRatio: $0.ratio) } ?? 1
        let vitalsFactor = vitals.map { 1 - vitalsModifierWeight * $0.maxAnomalyProgress } ?? 1

        var score = min(max(Int((core * sleepFactor * strainModifier * vitalsFactor).rounded()), 0), 100)
        if let vitals, vitals.maxAnomalyProgress >= severeVitalsAnomalyThreshold {
            score = min(score, severeVitalsScoreCap)
        }

        var components: [ReadinessComponent] = []
        var bestBaselineDayCounts: [Int] = []
        if let autonomic {
            components.append(ReadinessComponent(
                kind: .autonomic,
                score: Int(recoveryCore(fromZScore: autonomic.combinedZScore).rounded()),
                weight: 30,
                message: String(localized: "Heart signals compared with your baseline.", table: "BodyMetricsKit")
            ))
            bestBaselineDayCounts.append(autonomic.bestBaselineDayCount)
        }
        if let sleep {
            components.append(ReadinessComponent(
                kind: .sleep,
                score: sleep.componentScore,
                weight: 30,
                message: String(localized: "Sleep amount and continuity.", table: "BodyMetricsKit")
            ))
            bestBaselineDayCounts.append(sleep.historyDayCount)
        }
        if let training {
            components.append(ReadinessComponent(
                kind: .training,
                score: training.componentScore,
                weight: 25,
                message: String(localized: "Recent load relative to your longer baseline.", table: "BodyMetricsKit")
            ))
            bestBaselineDayCounts.append(training.pointCount)
        }
        if let vitals {
            components.append(ReadinessComponent(
                kind: .vitals,
                score: vitals.componentScore,
                weight: 15,
                message: String(localized: "Breathing, oxygen, and temperature anomalies.", table: "BodyMetricsKit")
            ))
            bestBaselineDayCounts.append(vitals.bestBaselineDayCount)
        }

        let drivers = prioritizedDrivers(
            from: (autonomic?.drivers ?? [])
                + (sleep?.drivers ?? [])
                + (training?.driver.map { [$0] } ?? [])
                + (vitals?.drivers ?? [])
        )

        var confidence = Self.confidence(
            componentCount: components.count,
            bestBaselineDayCount: bestBaselineDayCounts.max() ?? 0
        )
        if autonomic == nil {
            // A neutral-filled core means the most important signal is
            // missing; never present that as a confident score.
            confidence = .low
        }

        return ReadinessSummary(
            score: score,
            status: ReadinessStatus.status(for: score),
            confidence: confidence,
            components: components,
            drivers: drivers.isEmpty
                ? [ReadinessDriver(kind: .mostlyTypical, message: String(localized: "Readiness signals are mostly typical.", table: "BodyMetricsKit"), impact: 0)]
                : drivers
        )
    }

    static func robustBaseline(
        for date: Date,
        values: [DailyValue],
        floor: Double,
        calendar: Calendar = .bodyGregorian
    ) -> Baseline? {
        let scoringDay = calendar.startOfDay(for: date)
        let oldestDay = calendar.date(
            byAdding: .day,
            value: -baselineDayCount,
            to: scoringDay
        ) ?? scoringDay.addingTimeInterval(-Double(baselineDayCount) * 86_400)
        let recentCutoff = calendar.date(
            byAdding: .day,
            value: -recentExclusionDayCount,
            to: scoringDay
        ) ?? scoringDay

        let priorValues = values
            .filter { value in
                let day = calendar.startOfDay(for: value.date)
                return day < scoringDay && day >= oldestDay && value.value.isFinite
            }
            .sorted { $0.date < $1.date }

        let olderValues = priorValues.filter { calendar.startOfDay(for: $0.date) < recentCutoff }
        let baselineValues = olderValues.count >= 28 ? olderValues : priorValues
        let numericValues = baselineValues.map(\.value).sorted()

        guard numericValues.count >= minimumBaselineDayCount else {
            return nil
        }

        let medianValue = median(numericValues)
        let deviations = numericValues.map { abs($0 - medianValue) }.sorted()
        let spread = max(1.4826 * median(deviations), floor)

        return Baseline(
            median: medianValue,
            spread: spread,
            validDayCount: numericValues.count
        )
    }

    static func robustZScore(value: Double, baseline: Baseline) -> Double {
        guard value.isFinite, baseline.spread > 0 else {
            return 0
        }

        return (value - baseline.median) / baseline.spread
    }

    static func dailySeries(
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        startDate: Date,
        endDate: Date,
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration,
        calendar: Calendar = .bodyGregorian,
        today: Date = Date()
    ) -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []
        var day = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        guard day <= endDay else {
            return .empty
        }

        let context = ReadinessDailySeriesContext(
            trends: trends,
            healthSummary: healthSummary,
            today: today,
            calendar: calendar
        )
        while day <= endDay {
            let readiness = readinessSummary(
                on: day,
                healthSummary: healthSummary,
                trends: trends,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar,
                today: today,
                context: context
            )
            if let score = readiness.score {
                points.append(HealthTrendDataPoint(date: day, value: Double(score)))
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return HealthTrendSeries(points: points)
    }

    // MARK: - Source resolution

    /// The autonomic pair switches sources atomically: overnight HRV + HR are
    /// used only when both have a qualifying overnight baseline (≥ 14 nights
    /// in the window). A metric missing its overnight value on the scoring
    /// day is simply absent for that day — never swapped for the whole-day
    /// value against an overnight baseline.
    private static func autonomicReadings(
        on date: Date,
        context: ReadinessDailySeriesContext
    ) -> (heartRateVariability: MetricReading?, heartRate: MetricReading?) {
        if let overnightHRVBaseline = context.overnightBaseline(for: date, metric: .heartRateVariability),
           let overnightHeartRateBaseline = context.overnightBaseline(for: date, metric: .restingHeartRate) {
            return (
                context.overnightValue(on: date, metric: .heartRateVariability).map {
                    MetricReading(value: $0, baseline: overnightHRVBaseline)
                },
                context.overnightValue(on: date, metric: .restingHeartRate).map {
                    MetricReading(value: $0, baseline: overnightHeartRateBaseline)
                }
            )
        }

        return (
            wholeDayReading(on: date, metric: .heartRateVariability, context: context),
            wholeDayReading(on: date, metric: .restingHeartRate, context: context)
        )
    }

    private static func wholeDayReading(
        on date: Date,
        metric: ReadinessMetric,
        context: ReadinessDailySeriesContext
    ) -> MetricReading? {
        guard let value = context.wholeDayValue(on: date, metric: metric),
              let baseline = context.wholeDayBaseline(for: date, metric: metric) else {
            return nil
        }

        return MetricReading(value: value, baseline: baseline)
    }

    private static func vitalsReading(
        on date: Date,
        metric: ReadinessMetric,
        context: ReadinessDailySeriesContext
    ) -> MetricReading? {
        if let overnightBaseline = context.overnightBaseline(for: date, metric: metric) {
            return context.overnightValue(on: date, metric: metric).map {
                MetricReading(value: $0, baseline: overnightBaseline)
            }
        }

        return wholeDayReading(on: date, metric: metric, context: context)
    }

    // MARK: - Component assessments

    private static func autonomicAssessment(
        on date: Date,
        context: ReadinessDailySeriesContext
    ) -> AutonomicAssessment? {
        let readings = autonomicReadings(on: date, context: context)
        var weightedZScore = 0.0
        var totalWeight = 0.0
        var drivers: [ReadinessDriver] = []
        var baselineCounts: [Int] = []

        if let heartRateVariability = readings.heartRateVariability {
            let zScore = clampedZScore(robustZScore(
                value: heartRateVariability.value,
                baseline: heartRateVariability.baseline
            ))
            weightedZScore += hrvZScoreWeight * zScore
            totalWeight += hrvZScoreWeight
            baselineCounts.append(heartRateVariability.baseline.validDayCount)
            let progress = adverseProgress(-zScore)
            if progress > 0 {
                drivers.append(ReadinessDriver(
                    kind: .hrvBelowBaseline,
                    message: String(localized: "HRV is below baseline.", table: "BodyMetricsKit"),
                    impact: progress
                ))
            }
        }

        if let heartRate = readings.heartRate {
            let zScore = clampedZScore(-robustZScore(value: heartRate.value, baseline: heartRate.baseline))
            weightedZScore += heartRateZScoreWeight * zScore
            totalWeight += heartRateZScoreWeight
            baselineCounts.append(heartRate.baseline.validDayCount)
            let progress = adverseProgress(-zScore)
            if progress > 0 {
                drivers.append(ReadinessDriver(
                    kind: .heartRateAboveBaseline,
                    message: String(localized: "Resting heart rate is above baseline.", table: "BodyMetricsKit"),
                    impact: progress
                ))
            }
        }

        guard totalWeight > 0 else {
            return nil
        }

        return AutonomicAssessment(
            combinedZScore: weightedZScore / totalWeight,
            drivers: drivers,
            bestBaselineDayCount: baselineCounts.max() ?? 0
        )
    }

    private static func sleepAssessment(
        on date: Date,
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        idealSleepDuration: TimeInterval,
        calendar: Calendar,
        today: Date
    ) -> SleepAssessment? {
        let sleepSummary = trends.sleepHistory.summary(
            on: date,
            currentDaySummary: currentDaySleepSummary(healthSummary.sleep, for: date, today: today, calendar: calendar),
            today: today,
            calendar: calendar
        )
        guard let sleepSummary, let duration = sleepSummary.duration, duration > 0 else {
            return nil
        }

        var scores: [Int] = []
        var qualityValues: [Double] = []
        var drivers: [ReadinessDriver] = []

        let goalDuration = idealSleepDuration > 0 ? idealSleepDuration : BodySleepDurationGoal.defaultDuration
        let durationProgress = min(max(duration / goalDuration, 0), 1.10)
        scores.append(scoreFromSleepProgress(durationProgress))
        qualityValues.append(min(durationProgress, 1))
        if durationProgress < 0.85 {
            drivers.append(ReadinessDriver(
                kind: .sleepDurationBelowGoal,
                message: String(localized: "Sleep duration is below goal.", table: "BodyMetricsKit"),
                impact: 1 - durationProgress
            ))
        }

        if let interval = sleepSummary.stageSnapshot.dateInterval {
            let inBedDuration = max(interval.duration, duration)
            if inBedDuration > 0 {
                let efficiency = min(max(1 - (sleepSummary.stageSnapshot.awakeDuration / inBedDuration), 0), 1)
                let continuityProgress = min(max((efficiency - 0.78) / 0.18, 0), 1)
                scores.append(scoreFromSleepProgress(continuityProgress))
                qualityValues.append(continuityProgress)
                if continuityProgress < 0.65 {
                    drivers.append(ReadinessDriver(
                        kind: .sleepFragmented,
                        message: String(localized: "Sleep was more fragmented than usual.", table: "BodyMetricsKit"),
                        impact: 1 - continuityProgress
                    ))
                }
            }
        }

        return SleepAssessment(
            componentScore: averageScore(scores),
            quality: qualityValues.reduce(0, +) / Double(qualityValues.count),
            drivers: drivers,
            historyDayCount: trends.sleepHistory.days.count
        )
    }

    private static func currentDaySleepSummary(
        _ summary: SleepSummary,
        for date: Date,
        today: Date,
        calendar: Calendar
    ) -> SleepSummary? {
        guard summary.duration != nil || !summary.stageSnapshot.isEmpty || !summary.vitals.isEmpty else {
            return nil
        }

        if let summaryDate = summary.stageSnapshot.date {
            return calendar.isDate(summaryDate, inSameDayAs: date) ? summary : nil
        }

        return calendar.isDate(date, inSameDayAs: today) ? summary : nil
    }

    private static func trainingAssessment(
        on date: Date,
        trends: HealthTrendSnapshot,
        context: ReadinessDailySeriesContext
    ) -> TrainingAssessment? {
        guard let value = context.wholeDayValue(on: date, metric: .trainingLoad), value.isFinite else {
            return nil
        }

        let result = trainingLoadScore(value)
        return TrainingAssessment(
            componentScore: result.score,
            ratio: value,
            driver: result.driver,
            pointCount: trends.trainingLoad.points.count
        )
    }

    private static func vitalsAssessment(
        on date: Date,
        context: ReadinessDailySeriesContext
    ) -> VitalsAssessment? {
        var anomalyProgressValues: [Double] = []
        var drivers: [ReadinessDriver] = []
        var baselineCounts: [Int] = []

        appendHighSideAnomaly(
            kind: .respiratoryRateAboveBaseline,
            message: String(localized: "Respiratory rate is above baseline.", table: "BodyMetricsKit"),
            date: date,
            metric: .respiratoryRate,
            context: context,
            progressValues: &anomalyProgressValues,
            drivers: &drivers,
            baselineCounts: &baselineCounts
        )
        appendHighSideAnomaly(
            kind: .wristTemperatureAboveBaseline,
            message: String(localized: "Skin temperature is above baseline.", table: "BodyMetricsKit"),
            date: date,
            metric: .wristTemperature,
            context: context,
            progressValues: &anomalyProgressValues,
            drivers: &drivers,
            baselineCounts: &baselineCounts
        )

        if let reading = vitalsReading(on: date, metric: .oxygenSaturation, context: context) {
            let adverseZScore = -robustZScore(value: reading.value, baseline: reading.baseline)
            let progress = max(
                adverseProgress(adverseZScore, start: 1.0, full: 2.5),
                reading.value < 95 ? 0.35 : 0
            )
            if progress > 0 {
                anomalyProgressValues.append(progress)
                baselineCounts.append(reading.baseline.validDayCount)
                drivers.append(ReadinessDriver(
                    kind: .oxygenSaturationLow,
                    message: String(localized: "Blood oxygen is below its usual range.", table: "BodyMetricsKit"),
                    impact: progress
                ))
            }
        }

        guard !anomalyProgressValues.isEmpty else {
            return nil
        }

        let maxProgress = anomalyProgressValues.max() ?? 0
        return VitalsAssessment(
            componentScore: scoreFromPenaltyProgress(maxProgress),
            maxAnomalyProgress: maxProgress,
            drivers: drivers,
            bestBaselineDayCount: baselineCounts.max() ?? 0
        )
    }

    private static func appendHighSideAnomaly(
        kind: ReadinessDriverKind,
        message: String,
        date: Date,
        metric: ReadinessMetric,
        context: ReadinessDailySeriesContext,
        progressValues: inout [Double],
        drivers: inout [ReadinessDriver],
        baselineCounts: inout [Int]
    ) {
        guard let reading = vitalsReading(on: date, metric: metric, context: context) else {
            return
        }

        let progress = adverseProgress(robustZScore(value: reading.value, baseline: reading.baseline))
        guard progress > 0 else {
            return
        }

        progressValues.append(progress)
        baselineCounts.append(reading.baseline.validDayCount)
        drivers.append(ReadinessDriver(kind: kind, message: message, impact: progress))
    }

    private static func trainingLoadScore(_ value: Double) -> (score: Int, driver: ReadinessDriver?) {
        guard value.isFinite else {
            return (neutralScore, nil)
        }

        guard value > 1.30 else {
            return (scoreFromSustainableTrainingLoad(value), nil)
        }

        let progress = min(max((value - 1.30) / 0.25, 0), 1)
        return (
            scoreFromPenaltyProgress(progress, base: 70, minimum: 20),
            ReadinessDriver(
                kind: .trainingLoadElevated,
                message: String(localized: "Training load is elevated.", table: "BodyMetricsKit"),
                impact: progress
            )
        )
    }

    private static func confidence(
        componentCount: Int,
        bestBaselineDayCount: Int
    ) -> ReadinessConfidence {
        guard componentCount > 0 else {
            return .unavailable
        }

        if componentCount >= 3, bestBaselineDayCount >= 28 {
            return .high
        }

        if componentCount >= 2, bestBaselineDayCount >= 14 {
            return .medium
        }

        return .low
    }

    private static func prioritizedDrivers(from drivers: [ReadinessDriver]) -> [ReadinessDriver] {
        drivers
            .filter { $0.impact > 0 }
            .sorted { first, second in
                guard first.impact == second.impact else {
                    return first.impact > second.impact
                }

                return first.kind.rawValue < second.kind.rawValue
            }
            .prefix(3)
            .map { $0 }
    }

    private static func averageScore(_ scores: [Int]) -> Int {
        guard !scores.isEmpty else {
            return 0
        }

        let total = scores.reduce(0, +)
        return min(max(Int((Double(total) / Double(scores.count)).rounded()), 0), 100)
    }

    // MARK: - Score curves

    private static let neutralScore = 75
    private static let neutralCore = 70.0
    private static let hrvZScoreWeight = 0.65
    private static let heartRateZScoreWeight = 0.35
    private static let adverseZScoreCap = -2.5
    private static let favorableZScoreCap = 2.0
    private static let sleepModifierFloor = 0.75
    private static let vitalsModifierWeight = 0.45
    private static let severeVitalsAnomalyThreshold = 0.95
    private static let severeVitalsScoreCap = 25

    /// Single-metric artifact guard: one wild sample cannot move the combined
    /// z beyond what the curve treats as a full crash or full recovery.
    private static func clampedZScore(_ zScore: Double) -> Double {
        min(max(zScore, adverseZScoreCap), favorableZScoreCap)
    }

    /// Logistic recovery curve mapping the combined autonomic z-score to the
    /// score anchor: z −2.5 → 7.6, −2 → 11, −1 → 33, 0 → 72, +1 → 92, +2 → 96.
    private static func recoveryCore(fromZScore zScore: Double) -> Double {
        5 + 92 / (1 + exp(-(zScore + 0.55) / 0.55))
    }

    private static func strainFactor(forTrainingLoadRatio ratio: Double) -> Double {
        guard ratio.isFinite, ratio > 1.0 else {
            return 1
        }

        if ratio <= 1.3 {
            return 1 - 0.10 * (ratio - 1.0) / 0.3
        }

        if ratio <= 1.6 {
            return 0.90 - 0.20 * (ratio - 1.3) / 0.3
        }

        return 0.70
    }

    private static func scoreFromSleepProgress(_ progress: Double) -> Int {
        let clamped = min(max(progress, 0), 1.10)
        switch clamped {
        case 1...:
            return 96
        case 0.85..<1:
            let normalized = (clamped - 0.85) / 0.15
            return Int((75 + normalized * 21).rounded())
        case 0.65..<0.85:
            let normalized = (clamped - 0.65) / 0.20
            return Int((50 + normalized * 25).rounded())
        default:
            return Int((20 + clamped / 0.65 * 30).rounded())
        }
    }

    private static func scoreFromSustainableTrainingLoad(_ value: Double) -> Int {
        switch value {
        case ..<0.70:
            return 96
        case 0.70..<1.00:
            let progress = (value - 0.70) / 0.30
            return Int((96 - progress * 18).rounded())
        case 1.00..<1.20:
            let progress = (value - 1.00) / 0.20
            return Int((78 - progress * 8).rounded())
        default:
            let progress = (value - 1.20) / 0.10
            return Int((70 - progress * 8).rounded())
        }
    }

    private static func scoreFromPenaltyProgress(_ progress: Double, base: Double = Double(neutralScore), minimum: Double = 5) -> Int {
        Int((base - min(max(progress, 0), 1) * (base - minimum)).rounded())
    }

    private static func adverseProgress(_ zScore: Double, start: Double = 0.5, full: Double = 2.0) -> Double {
        let normalized = min(max((zScore - start) / (full - start), 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private enum MetricFloor {
        static let hrv = 5.0
        static let heartRate = 3.0
        static let respiratoryRate = 0.6
        static let oxygenSaturation = 1.0
        static let wristTemperature = 0.2
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }

        return values[middle]
    }
}
