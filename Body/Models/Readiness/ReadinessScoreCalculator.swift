//
//  ReadinessScoreCalculator.swift
//  Body
//

import Foundation

enum ReadinessScoreCalculator {
    private struct ComponentResult {
        var component: ReadinessComponent
        var drivers: [ReadinessDriver]
        var bestBaselineDayCount: Int
    }

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

    private struct ReadinessDailySeriesContext {
        private let calendar: Calendar
        private let currentValuesByMetric: [ReadinessMetric: [Date: Double]]
        private let baselineCachesByMetric: [ReadinessMetric: ReadinessBaselineCache]

        init(trends: HealthTrendSnapshot, calendar: Calendar) {
            self.calendar = calendar
            currentValuesByMetric = [
                .heartRateVariability: Self.currentValuesByDay(from: trends.heartRateVariability, calendar: calendar),
                .restingHeartRate: Self.currentValuesByDay(from: trends.restingHeartRate, calendar: calendar),
                .trainingLoad: Self.currentValuesByDay(from: trends.trainingLoad, calendar: calendar),
                .respiratoryRate: Self.currentValuesByDay(from: trends.respiratoryRate, calendar: calendar),
                .oxygenSaturation: Self.currentValuesByDay(from: trends.oxygenSaturation, calendar: calendar),
                .wristTemperature: Self.currentValuesByDay(from: trends.wristTemperature, calendar: calendar)
            ]
            baselineCachesByMetric = [
                .heartRateVariability: ReadinessBaselineCache(series: trends.heartRateVariability, floor: MetricFloor.hrv, calendar: calendar),
                .restingHeartRate: ReadinessBaselineCache(series: trends.restingHeartRate, floor: MetricFloor.heartRate, calendar: calendar),
                .respiratoryRate: ReadinessBaselineCache(series: trends.respiratoryRate, floor: MetricFloor.respiratoryRate, calendar: calendar),
                .oxygenSaturation: ReadinessBaselineCache(series: trends.oxygenSaturation, floor: MetricFloor.oxygenSaturation, calendar: calendar),
                .wristTemperature: ReadinessBaselineCache(series: trends.wristTemperature, floor: MetricFloor.wristTemperature, calendar: calendar)
            ]
        }

        func currentValue(on date: Date, metric: ReadinessMetric) -> Double? {
            let day = calendar.startOfDay(for: date)
            return currentValuesByMetric[metric]?[day]
        }

        func baseline(for date: Date, metric: ReadinessMetric) -> Baseline? {
            baselineCachesByMetric[metric]?.baseline(for: date)
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
        calendar: Calendar = .bodyGregorian
    ) -> ReadinessSummary {
        readinessSummary(
            on: date,
            healthSummary: healthSummary,
            trends: trends,
            idealSleepDuration: idealSleepDuration,
            calendar: calendar,
            context: nil
        )
    }

    private static func readinessSummary(
        on date: Date,
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        idealSleepDuration: TimeInterval,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?
    ) -> ReadinessSummary {
        let componentResults = [
            autonomicComponent(on: date, trends: trends, calendar: calendar, context: context),
            sleepComponent(
                on: date,
                healthSummary: healthSummary,
                trends: trends,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar
            ),
            trainingComponent(on: date, trends: trends, calendar: calendar, context: context),
            vitalsComponent(on: date, trends: trends, calendar: calendar, context: context)
        ].compactMap { $0 }

        guard !componentResults.isEmpty else {
            return .unavailable
        }

        let availableWeight = componentResults.reduce(0) { $0 + $1.component.weight }
        guard availableWeight > 0 else {
            return .unavailable
        }

        let weightedScore = componentResults.reduce(0) { partialResult, result in
            partialResult + Double(result.component.score ?? 0) * (result.component.weight / availableWeight)
        }
        let rawScore = min(max(Int(weightedScore.rounded()), 0), 100)
        let score = adjustedSummaryScore(rawScore, componentResults: componentResults)
        let drivers = prioritizedDrivers(from: componentResults)

        return ReadinessSummary(
            score: score,
            status: ReadinessStatus.status(for: score),
            confidence: confidence(for: componentResults),
            components: componentResults.map(\.component),
            drivers: drivers.isEmpty
                ? [ReadinessDriver(kind: .mostlyTypical, message: "Readiness signals are mostly typical.", impact: 0)]
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
        calendar: Calendar = .bodyGregorian
    ) -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []
        var day = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        guard day <= endDay else {
            return .empty
        }

        let context = ReadinessDailySeriesContext(trends: trends, calendar: calendar)
        while day <= endDay {
            let readiness = readinessSummary(
                on: day,
                healthSummary: healthSummary,
                trends: trends,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar,
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

    private static func autonomicComponent(
        on date: Date,
        trends: HealthTrendSnapshot,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?
    ) -> ComponentResult? {
        var scores: [Int] = []
        var drivers: [ReadinessDriver] = []
        var baselineCounts: [Int] = []

        if let value = currentValue(
            on: date,
            metric: .heartRateVariability,
            series: trends.heartRateVariability,
            calendar: calendar,
            context: context
        ),
           let baseline = baseline(
            for: date,
            metric: .heartRateVariability,
            series: trends.heartRateVariability,
            floor: MetricFloor.hrv,
            calendar: calendar,
            context: context
           ) {
            let favorableZScore = robustZScore(value: value, baseline: baseline)
            let progress = adverseProgress(-favorableZScore)
            scores.append(scoreFromBaselineZScore(favorableZScore))
            baselineCounts.append(baseline.validDayCount)
            if progress > 0 {
                drivers.append(ReadinessDriver(
                    kind: .hrvBelowBaseline,
                    message: "HRV is below baseline.",
                    impact: progress
                ))
            }
        }

        if let value = currentValue(
            on: date,
            metric: .restingHeartRate,
            series: trends.restingHeartRate,
            calendar: calendar,
            context: context
        ),
           let baseline = baseline(
            for: date,
            metric: .restingHeartRate,
            series: trends.restingHeartRate,
            floor: MetricFloor.heartRate,
            calendar: calendar,
            context: context
           ) {
            let favorableZScore = -robustZScore(value: value, baseline: baseline)
            let progress = adverseProgress(-favorableZScore)
            scores.append(scoreFromBaselineZScore(favorableZScore))
            baselineCounts.append(baseline.validDayCount)
            if progress > 0 {
                drivers.append(ReadinessDriver(
                    kind: .heartRateAboveBaseline,
                    message: "Resting heart rate is above baseline.",
                    impact: progress
                ))
            }
        }

        guard !scores.isEmpty else {
            return nil
        }

        return ComponentResult(
            component: ReadinessComponent(
                kind: .autonomic,
                score: averageScore(scores),
                weight: 30,
                message: "Heart signals compared with your baseline."
            ),
            drivers: drivers,
            bestBaselineDayCount: baselineCounts.max() ?? 0
        )
    }

    private static func sleepComponent(
        on date: Date,
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        idealSleepDuration: TimeInterval,
        calendar: Calendar
    ) -> ComponentResult? {
        let sleepSummary = trends.sleepHistory.summary(
            on: date,
            currentDaySummary: currentDaySleepSummary(healthSummary.sleep, for: date, calendar: calendar),
            today: Date(),
            calendar: calendar
        )
        guard let sleepSummary, let duration = sleepSummary.duration, duration > 0 else {
            return nil
        }

        var scores: [Int] = []
        var drivers: [ReadinessDriver] = []

        let goalDuration = idealSleepDuration > 0 ? idealSleepDuration : BodySleepDurationGoal.defaultDuration
        let durationProgress = min(max(duration / goalDuration, 0), 1.10)
        scores.append(scoreFromSleepProgress(durationProgress))
        if durationProgress < 0.85 {
            drivers.append(ReadinessDriver(
                kind: .sleepDurationBelowGoal,
                message: "Sleep duration is below goal.",
                impact: 1 - durationProgress
            ))
        }

        if let interval = sleepSummary.stageSnapshot.dateInterval {
            let inBedDuration = max(interval.duration, duration)
            if inBedDuration > 0 {
                let efficiency = min(max(1 - (sleepSummary.stageSnapshot.awakeDuration / inBedDuration), 0), 1)
                let continuityProgress = min(max((efficiency - 0.78) / 0.18, 0), 1)
                scores.append(scoreFromSleepProgress(continuityProgress))
                if continuityProgress < 0.65 {
                    drivers.append(ReadinessDriver(
                        kind: .sleepFragmented,
                        message: "Sleep was more fragmented than usual.",
                        impact: 1 - continuityProgress
                    ))
                }
            }
        }

        guard !scores.isEmpty else {
            return nil
        }

        return ComponentResult(
            component: ReadinessComponent(
                kind: .sleep,
                score: averageScore(scores),
                weight: 30,
                message: "Sleep amount and continuity."
            ),
            drivers: drivers,
            bestBaselineDayCount: trends.sleepHistory.days.count
        )
    }

    private static func currentDaySleepSummary(
        _ summary: SleepSummary,
        for date: Date,
        calendar: Calendar
    ) -> SleepSummary? {
        guard summary.duration != nil || !summary.stageSnapshot.isEmpty || !summary.vitals.isEmpty else {
            return nil
        }

        if let summaryDate = summary.stageSnapshot.date {
            return calendar.isDate(summaryDate, inSameDayAs: date) ? summary : nil
        }

        return calendar.isDate(date, inSameDayAs: Date()) ? summary : nil
    }

    private static func trainingComponent(
        on date: Date,
        trends: HealthTrendSnapshot,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?
    ) -> ComponentResult? {
        guard let value = currentValue(
            on: date,
            metric: .trainingLoad,
            series: trends.trainingLoad,
            calendar: calendar,
            context: context
        ), value.isFinite else {
            return nil
        }

        let result = trainingLoadScore(value)
        return ComponentResult(
            component: ReadinessComponent(
                kind: .training,
                score: result.score,
                weight: 25,
                message: "Recent load relative to your longer baseline."
            ),
            drivers: result.driver.map { [$0] } ?? [],
            bestBaselineDayCount: trends.trainingLoad.points.count
        )
    }

    private static func vitalsComponent(
        on date: Date,
        trends: HealthTrendSnapshot,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?
    ) -> ComponentResult? {
        var anomalyProgressValues: [Double] = []
        var drivers: [ReadinessDriver] = []
        var baselineCounts: [Int] = []

        appendHighSideAnomaly(
            kind: .respiratoryRateAboveBaseline,
            message: "Respiratory rate is above baseline.",
            date: date,
            metric: .respiratoryRate,
            series: trends.respiratoryRate,
            floor: MetricFloor.respiratoryRate,
            calendar: calendar,
            context: context,
            progressValues: &anomalyProgressValues,
            drivers: &drivers,
            baselineCounts: &baselineCounts
        )
        appendHighSideAnomaly(
            kind: .wristTemperatureAboveBaseline,
            message: "Wrist temperature is above baseline.",
            date: date,
            metric: .wristTemperature,
            series: trends.wristTemperature,
            floor: MetricFloor.wristTemperature,
            calendar: calendar,
            context: context,
            progressValues: &anomalyProgressValues,
            drivers: &drivers,
            baselineCounts: &baselineCounts
        )

        if let value = currentValue(
            on: date,
            metric: .oxygenSaturation,
            series: trends.oxygenSaturation,
            calendar: calendar,
            context: context
        ),
           let baseline = baseline(
            for: date,
            metric: .oxygenSaturation,
            series: trends.oxygenSaturation,
            floor: MetricFloor.oxygenSaturation,
            calendar: calendar,
            context: context
           ) {
            let adverseZScore = -robustZScore(value: value, baseline: baseline)
            let progress = max(adverseProgress(adverseZScore, start: 1.0, full: 2.5), value < 95 ? 0.35 : 0)
            if progress > 0 {
                anomalyProgressValues.append(progress)
                baselineCounts.append(baseline.validDayCount)
                drivers.append(ReadinessDriver(
                    kind: .oxygenSaturationLow,
                    message: "Blood oxygen is below its usual range.",
                    impact: progress
                ))
            }
        }

        guard !anomalyProgressValues.isEmpty else {
            return nil
        }

        let maxProgress = anomalyProgressValues.max() ?? 0
        return ComponentResult(
            component: ReadinessComponent(
                kind: .vitals,
                score: scoreFromPenaltyProgress(maxProgress),
                weight: 15,
                message: "Breathing, oxygen, and temperature anomalies."
            ),
            drivers: drivers,
            bestBaselineDayCount: baselineCounts.max() ?? 0
        )
    }

    private static func appendHighSideAnomaly(
        kind: ReadinessDriverKind,
        message: String,
        date: Date,
        metric: ReadinessMetric,
        series: HealthTrendSeries,
        floor: Double,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?,
        progressValues: inout [Double],
        drivers: inout [ReadinessDriver],
        baselineCounts: inout [Int]
    ) {
        guard let value = currentValue(
            on: date,
            metric: metric,
            series: series,
            calendar: calendar,
            context: context
        ),
              let baseline = baseline(
                for: date,
                metric: metric,
                series: series,
                floor: floor,
                calendar: calendar,
                context: context
              ) else {
            return
        }

        let progress = adverseProgress(robustZScore(value: value, baseline: baseline))
        guard progress > 0 else {
            return
        }

        progressValues.append(progress)
        baselineCounts.append(baseline.validDayCount)
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
                message: "Training load is elevated.",
                impact: progress
            )
        )
    }

    private static func confidence(for componentResults: [ComponentResult]) -> ReadinessConfidence {
        guard !componentResults.isEmpty else {
            return .unavailable
        }

        let componentCount = componentResults.count
        let bestBaselineDayCount = componentResults.map(\.bestBaselineDayCount).max() ?? 0

        if componentCount >= 3, bestBaselineDayCount >= 28 {
            return .high
        }

        if componentCount >= 2, bestBaselineDayCount >= 14 {
            return .medium
        }

        return .low
    }

    private static func prioritizedDrivers(from componentResults: [ComponentResult]) -> [ReadinessDriver] {
        componentResults
            .flatMap(\.drivers)
            .filter { $0.impact > 0 }
            .sorted { first, second in
                guard first.impact == second.impact else {
                    return first.impact > second.impact
                }

                return first.message < second.message
            }
            .prefix(3)
            .map { $0 }
    }

    private static func currentValue(
        on date: Date,
        metric: ReadinessMetric,
        series: HealthTrendSeries,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?
    ) -> Double? {
        if let context {
            return context.currentValue(on: date, metric: metric)
        }

        return currentValue(on: date, in: series, calendar: calendar)
    }

    private static func baseline(
        for date: Date,
        metric: ReadinessMetric,
        series: HealthTrendSeries,
        floor: Double,
        calendar: Calendar,
        context: ReadinessDailySeriesContext?
    ) -> Baseline? {
        if let context {
            return context.baseline(for: date, metric: metric)
        }

        return robustBaseline(
            for: date,
            values: dailyValues(from: series),
            floor: floor,
            calendar: calendar
        )
    }

    private static func currentValue(
        on date: Date,
        in series: HealthTrendSeries,
        calendar: Calendar
    ) -> Double? {
        series.points(on: date, calendar: calendar).points
            .filter { $0.value.isFinite }
            .sorted { $0.date < $1.date }
            .last?
            .value
    }

    private static func dailyValues(from series: HealthTrendSeries) -> [DailyValue] {
        series.points.compactMap { point in
            guard point.value.isFinite else {
                return nil
            }

            return DailyValue(date: point.date, value: point.value)
        }
    }

    private static func averageScore(_ scores: [Int]) -> Int {
        guard !scores.isEmpty else {
            return 0
        }

        let total = scores.reduce(0, +)
        return min(max(Int((Double(total) / Double(scores.count)).rounded()), 0), 100)
    }

    private static func adjustedSummaryScore(_ score: Int, componentResults: [ComponentResult]) -> Int {
        guard componentResults.contains(where: isSevereLimiter) else {
            return score
        }

        return min(score, 24)
    }

    private static func isSevereLimiter(_ result: ComponentResult) -> Bool {
        guard let componentScore = result.component.score else {
            return false
        }

        let strongestImpact = result.drivers.map(\.impact).max() ?? 0
        return componentScore <= 25 && strongestImpact >= 0.90
    }

    private static let neutralScore = 75

    private static func scoreFromBaselineZScore(_ zScore: Double) -> Int {
        if zScore >= 0 {
            let progress = min(max(zScore / 1.75, 0), 1)
            return Int((Double(neutralScore) + smoothStep(progress) * 25).rounded())
        }

        let progress = min(max(-zScore / 2.0, 0), 1)
        return Int((Double(neutralScore) - smoothStep(progress) * 70).rounded())
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

    private static func smoothStep(_ value: Double) -> Double {
        let normalized = min(max(value, 0), 1)
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
