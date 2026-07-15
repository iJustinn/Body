//
//  TrainingLoadCalculator.swift
//  Body
//

import Foundation

enum TrainingLoadCalculator {
    static let defaultEffortLevel = 5.0
    /// Workout look-back for the acute/chronic EWA. Shared by the iOS engine and
    /// the watch so both seed the EWA from the same start → identical ratios.
    static let summaryWindowDayCount = 180
    private static let acuteDayCount = 7
    private static let chronicDayCount = 42

    static func load(for workout: WorkoutSummary) -> Double? {
        guard workout.duration.isFinite, workout.duration > 0 else {
            return nil
        }

        // A failed-and-uncached effort lookup (H12) is excluded from load rather
        // than counted as the default effort — otherwise a transient query failure
        // fabricates a mid-intensity workout in the acute/chronic EWA. A genuinely
        // unrated workout keeps the intentional default below.
        if workout.effortUnresolved == true {
            return nil
        }

        let effort = workout.effortLevel.map(clampedEffortLevel) ?? defaultEffortLevel
        let load = (workout.duration / 60) * effort
        return load.isFinite && load > 0 ? load : nil
    }

    static func dailySeries(
        from workouts: [WorkoutSummary],
        startDate: Date? = nil,
        endDate: Date? = nil,
        calendar: Calendar = .bodyGregorian
    ) -> HealthTrendSeries {
        let dailyLoads = dailyLoadPoints(
            from: workouts,
            startDate: startDate,
            endDate: endDate,
            calendar: calendar
        )
        guard !dailyLoads.isEmpty else {
            return .empty
        }

        let acuteSmoothing = smoothingFactor(forDayCount: acuteDayCount)
        let chronicSmoothing = smoothingFactor(forDayCount: chronicDayCount)
        var acuteLoad: Double?
        var chronicLoad: Double?

        let points = dailyLoads.compactMap { day, load -> HealthTrendDataPoint? in
            acuteLoad = exponentiallyWeightedAverage(
                previousValue: acuteLoad,
                newValue: load,
                smoothingFactor: acuteSmoothing
            )
            chronicLoad = exponentiallyWeightedAverage(
                previousValue: chronicLoad,
                newValue: load,
                smoothingFactor: chronicSmoothing
            )

            guard let acuteLoad,
                  let chronicLoad,
                  chronicLoad > 0,
                  acuteLoad.isFinite,
                  chronicLoad.isFinite else {
                return nil
            }

            return HealthTrendDataPoint(date: day, value: acuteLoad / chronicLoad)
        }

        return HealthTrendSeries(points: points)
    }

    static func summary(
        on date: Date = Date(),
        from workouts: [WorkoutSummary],
        startDate: Date? = nil,
        calendar: Calendar = .bodyGregorian
    ) -> HealthMetricSummary? {
        let selectedDay = calendar.startOfDay(for: date)
        let series = dailySeries(
            from: workouts,
            startDate: startDate,
            endDate: selectedDay,
            calendar: calendar
        )
        guard let value = series.point(on: selectedDay)?.value else {
            return nil
        }

        return HealthMetricSummary(value: value)
    }

    private static func dailyLoadPoints(
        from workouts: [WorkoutSummary],
        startDate: Date?,
        endDate: Date?,
        calendar: Calendar
    ) -> [(date: Date, load: Double)] {
        let loadsByDay = workouts.reduce(into: [Date: Double]()) { partialResult, workout in
            guard let load = load(for: workout) else {
                return
            }

            let day = calendar.startOfDay(for: workout.startDate)
            partialResult[day, default: 0] += load
        }

        guard let firstDay = startDate.map({ calendar.startOfDay(for: $0) }) ?? loadsByDay.keys.min(),
              let lastDay = endDate.map({ calendar.startOfDay(for: $0) }) ?? loadsByDay.keys.max(),
              firstDay <= lastDay else {
            return []
        }

        var points: [(date: Date, load: Double)] = []
        var day = firstDay
        while day <= lastDay {
            points.append((date: day, load: loadsByDay[day] ?? 0))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }
        return points
    }

    private static func clampedEffortLevel(_ effortLevel: Double) -> Double {
        guard effortLevel.isFinite else {
            return defaultEffortLevel
        }

        return min(max(effortLevel, 1), 10)
    }

    private static func smoothingFactor(forDayCount dayCount: Int) -> Double {
        2 / (Double(dayCount) + 1)
    }

    private static func exponentiallyWeightedAverage(
        previousValue: Double?,
        newValue: Double,
        smoothingFactor: Double
    ) -> Double {
        guard let previousValue else {
            return newValue
        }

        return smoothingFactor * newValue + (1 - smoothingFactor) * previousValue
    }
}

enum TrainingLoadInterval: Hashable {
    case stopTraining
    case optimal
    case mediumInjuryRisk
    case highInjuryRisk

    static let displayOrder: [TrainingLoadInterval] = [
        .highInjuryRisk,
        .mediumInjuryRisk,
        .optimal,
        .stopTraining
    ]

    var title: String {
        switch self {
        case .stopTraining:
            return String(localized: "Resting", table: "BodyMetricsKit")
        case .optimal:
            return String(localized: "Optimal", table: "BodyMetricsKit")
        case .mediumInjuryRisk:
            return String(localized: "Medium Injury Risk", table: "BodyMetricsKit")
        case .highInjuryRisk:
            return String(localized: "High Injury Risk", table: "BodyMetricsKit")
        }
    }

    var lowerBound: Double? {
        switch self {
        case .stopTraining:
            return nil
        case .optimal:
            return 0.8
        case .mediumInjuryRisk:
            return 1.3
        case .highInjuryRisk:
            return 1.5
        }
    }

    var upperBound: Double? {
        switch self {
        case .stopTraining:
            return 0.8
        case .optimal:
            return 1.3
        case .mediumInjuryRisk:
            return 1.5
        case .highInjuryRisk:
            return nil
        }
    }

    var boundaryValues: [Double] {
        [lowerBound, upperBound].compactMap { $0 }
    }

    static func interval(for value: Double?) -> TrainingLoadInterval? {
        guard let value, value.isFinite else {
            return nil
        }

        if value < 0.8 {
            return .stopTraining
        } else if value <= 1.3 {
            return .optimal
        } else if value <= 1.5 {
            return .mediumInjuryRisk
        } else {
            return .highInjuryRisk
        }
    }
}

struct TrainingLoadIntervalBreakdownEntry: Equatable, Identifiable {
    let interval: TrainingLoadInterval
    let dayCount: Int
    let totalDayCount: Int

    var id: TrainingLoadInterval {
        interval
    }

    var fractionOfTotal: Double {
        guard totalDayCount > 0 else { return 0 }
        return Double(dayCount) / Double(totalDayCount)
    }
}

enum TrainingLoadIntervalBreakdown {
    static func entries(
        for series: HealthTrendSeries,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [TrainingLoadIntervalBreakdownEntry] {
        let intervals = series.calendarPoints(to: range, calendar: calendar, date: date)
            .compactMap { point in
                TrainingLoadInterval.interval(for: point.value)
            }
        let countsByInterval = Dictionary(grouping: intervals) { $0 }
            .mapValues(\.count)
        let totalDayCount = countsByInterval.values.reduce(0, +)

        return TrainingLoadInterval.displayOrder.map { interval in
            TrainingLoadIntervalBreakdownEntry(
                interval: interval,
                dayCount: countsByInterval[interval, default: 0],
                totalDayCount: totalDayCount
            )
        }
    }
}
