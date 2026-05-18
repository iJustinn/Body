//
//  RecoveryScoreCalculator.swift
//  Body
//

import Foundation

enum RecoveryScoreCalculator {
    private struct ComponentResult {
        var component: RecoveryComponent
        var drivers: [RecoveryDriver]
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

    static let baselineDayCount = 56
    static let recentExclusionDayCount = 3
    static let minimumBaselineDayCount = 14

    static func summary(
        on date: Date,
        healthSummary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        calendar: Calendar = .bodyGregorian
    ) -> RecoverySummary {
        let componentResults = [
            autonomicComponent(on: date, trends: trends, calendar: calendar),
            sleepComponent(on: date, healthSummary: healthSummary, trends: trends, calendar: calendar),
            trainingComponent(on: date, trends: trends, calendar: calendar),
            vitalsComponent(on: date, trends: trends, calendar: calendar)
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

        return RecoverySummary(
            score: score,
            status: RecoveryStatus.status(for: score),
            confidence: confidence(for: componentResults),
            components: componentResults.map(\.component),
            drivers: drivers.isEmpty
                ? [RecoveryDriver(kind: .mostlyTypical, message: "Recovery signals are mostly typical.", impact: 0)]
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
        calendar: Calendar = .bodyGregorian
    ) -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []
        var day = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        guard day <= endDay else {
            return .empty
        }

        while day <= endDay {
            let summary = summary(
                on: day,
                healthSummary: healthSummary,
                trends: trends,
                calendar: calendar
            )
            if let score = summary.score {
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
        calendar: Calendar
    ) -> ComponentResult? {
        var scores: [Int] = []
        var drivers: [RecoveryDriver] = []
        var baselineCounts: [Int] = []

        if let value = currentValue(on: date, in: trends.heartRateVariability, calendar: calendar),
           let baseline = robustBaseline(
            for: date,
            values: dailyValues(from: trends.heartRateVariability),
            floor: MetricFloor.hrv,
            calendar: calendar
           ) {
            let favorableZScore = robustZScore(value: value, baseline: baseline)
            let progress = adverseProgress(-favorableZScore)
            scores.append(scoreFromBaselineZScore(favorableZScore))
            baselineCounts.append(baseline.validDayCount)
            if progress > 0 {
                drivers.append(RecoveryDriver(
                    kind: .hrvBelowBaseline,
                    message: "HRV is below baseline.",
                    impact: progress
                ))
            }
        }

        if let value = currentValue(on: date, in: trends.restingHeartRate, calendar: calendar),
           let baseline = robustBaseline(
            for: date,
            values: dailyValues(from: trends.restingHeartRate),
            floor: MetricFloor.heartRate,
            calendar: calendar
           ) {
            let favorableZScore = -robustZScore(value: value, baseline: baseline)
            let progress = adverseProgress(-favorableZScore)
            scores.append(scoreFromBaselineZScore(favorableZScore))
            baselineCounts.append(baseline.validDayCount)
            if progress > 0 {
                drivers.append(RecoveryDriver(
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
            component: RecoveryComponent(
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
        var drivers: [RecoveryDriver] = []

        let durationProgress = min(max(duration / BodySleepDurationGoal.defaultDuration, 0), 1.10)
        scores.append(scoreFromSleepProgress(durationProgress))
        if durationProgress < 0.85 {
            drivers.append(RecoveryDriver(
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
                    drivers.append(RecoveryDriver(
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
            component: RecoveryComponent(
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
        calendar: Calendar
    ) -> ComponentResult? {
        guard let value = currentValue(on: date, in: trends.trainingLoad, calendar: calendar), value.isFinite else {
            return nil
        }

        let result = trainingLoadScore(value)
        return ComponentResult(
            component: RecoveryComponent(
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
        calendar: Calendar
    ) -> ComponentResult? {
        var anomalyProgressValues: [Double] = []
        var drivers: [RecoveryDriver] = []
        var baselineCounts: [Int] = []

        appendHighSideAnomaly(
            kind: .respiratoryRateAboveBaseline,
            message: "Respiratory rate is above baseline.",
            date: date,
            series: trends.respiratoryRate,
            floor: MetricFloor.respiratoryRate,
            calendar: calendar,
            progressValues: &anomalyProgressValues,
            drivers: &drivers,
            baselineCounts: &baselineCounts
        )
        appendHighSideAnomaly(
            kind: .wristTemperatureAboveBaseline,
            message: "Wrist temperature is above baseline.",
            date: date,
            series: trends.wristTemperature,
            floor: MetricFloor.wristTemperature,
            calendar: calendar,
            progressValues: &anomalyProgressValues,
            drivers: &drivers,
            baselineCounts: &baselineCounts
        )

        if let value = currentValue(on: date, in: trends.oxygenSaturation, calendar: calendar),
           let baseline = robustBaseline(
            for: date,
            values: dailyValues(from: trends.oxygenSaturation),
            floor: MetricFloor.oxygenSaturation,
            calendar: calendar
           ) {
            let adverseZScore = -robustZScore(value: value, baseline: baseline)
            let progress = max(adverseProgress(adverseZScore, start: 1.0, full: 2.5), value < 95 ? 0.35 : 0)
            if progress > 0 {
                anomalyProgressValues.append(progress)
                baselineCounts.append(baseline.validDayCount)
                drivers.append(RecoveryDriver(
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
            component: RecoveryComponent(
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
        kind: RecoveryDriverKind,
        message: String,
        date: Date,
        series: HealthTrendSeries,
        floor: Double,
        calendar: Calendar,
        progressValues: inout [Double],
        drivers: inout [RecoveryDriver],
        baselineCounts: inout [Int]
    ) {
        guard let value = currentValue(on: date, in: series, calendar: calendar),
              let baseline = robustBaseline(
                for: date,
                values: dailyValues(from: series),
                floor: floor,
                calendar: calendar
              ) else {
            return
        }

        let progress = adverseProgress(robustZScore(value: value, baseline: baseline))
        guard progress > 0 else {
            return
        }

        progressValues.append(progress)
        baselineCounts.append(baseline.validDayCount)
        drivers.append(RecoveryDriver(kind: kind, message: message, impact: progress))
    }

    private static func trainingLoadScore(_ value: Double) -> (score: Int, driver: RecoveryDriver?) {
        guard value.isFinite else {
            return (neutralScore, nil)
        }

        guard value > 1.30 else {
            return (scoreFromSustainableTrainingLoad(value), nil)
        }

        let progress = min(max((value - 1.30) / 0.25, 0), 1)
        return (
            scoreFromPenaltyProgress(progress, base: 70, minimum: 20),
            RecoveryDriver(
                kind: .trainingLoadElevated,
                message: "Training load is elevated.",
                impact: progress
            )
        )
    }

    private static func confidence(for componentResults: [ComponentResult]) -> RecoveryConfidence {
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

    private static func prioritizedDrivers(from componentResults: [ComponentResult]) -> [RecoveryDriver] {
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
