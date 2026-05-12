//
//  HealthSummarySnapshot.swift
//  Body
//

import Foundation

enum HealthMetricKind: String, CaseIterable, Identifiable {
    case sleep
    case basics
    case restingHeartRate
    case bodyMass
    case bodyFatPercentage
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case bodyMassIndex
    case activeEnergy
    case restingEnergy

    var id: String {
        rawValue
    }
}

struct HealthSummarySnapshot: Equatable {
    var activityRings: ActivityRingSummary
    var sleep: SleepSummary
    var restingHeartRate: HealthMetricSummary
    var bodyMass: HealthMetricSummary
    var bodyFatPercentage: HealthMetricSummary
    var heartRateVariability: HealthMetricSummary
    var respiratoryRate: HealthMetricSummary
    var oxygenSaturation: HealthMetricSummary
    var bodyMassIndex: HealthMetricSummary
    var activeEnergy: HealthMetricSummary
    var restingEnergy: HealthMetricSummary

    var isEmpty: Bool {
        activityRings.isEmpty &&
            sleep.duration == nil &&
            sleep.vitals.isEmpty &&
            restingHeartRate.value == nil &&
            bodyMass.value == nil &&
            bodyFatPercentage.value == nil &&
            heartRateVariability.value == nil &&
            respiratoryRate.value == nil &&
            oxygenSaturation.value == nil &&
            bodyMassIndex.value == nil &&
            activeEnergy.value == nil &&
            restingEnergy.value == nil
    }

    static let empty = HealthSummarySnapshot(
        activityRings: .empty,
        sleep: SleepSummary(duration: nil),
        restingHeartRate: HealthMetricSummary(value: nil),
        bodyMass: HealthMetricSummary(value: nil),
        bodyFatPercentage: HealthMetricSummary(value: nil),
        heartRateVariability: HealthMetricSummary(value: nil),
        respiratoryRate: HealthMetricSummary(value: nil),
        oxygenSaturation: HealthMetricSummary(value: nil),
        bodyMassIndex: HealthMetricSummary(value: nil),
        activeEnergy: HealthMetricSummary(value: nil),
        restingEnergy: HealthMetricSummary(value: nil)
    )

    static let placeholder = HealthSummarySnapshot(
        activityRings: ActivityRingSummary(
            move: ActivityRingMetric(value: 670, goal: 500),
            exercise: ActivityRingMetric(value: 76, goal: 40),
            stand: ActivityRingMetric(value: 8, goal: 10)
        ),
        sleep: SleepSummary(
            duration: 28_740,
            vitals: SleepVitalsSummary(
                heartRate: 58,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                wristTemperatureCelsius: 36.4
            )
        ),
        restingHeartRate: HealthMetricSummary(value: 60),
        bodyMass: HealthMetricSummary(value: 69.3),
        bodyFatPercentage: HealthMetricSummary(value: 13.1),
        heartRateVariability: HealthMetricSummary(value: 38.4),
        respiratoryRate: HealthMetricSummary(value: 14),
        oxygenSaturation: HealthMetricSummary(value: 97),
        bodyMassIndex: HealthMetricSummary(value: 22.1),
        activeEnergy: HealthMetricSummary(value: 520),
        restingEnergy: HealthMetricSummary(value: 1_690)
    )
}

struct ActivityRingSummary: Equatable {
    var move: ActivityRingMetric
    var exercise: ActivityRingMetric
    var stand: ActivityRingMetric

    var isEmpty: Bool {
        move.value == nil &&
            move.goal == nil &&
            exercise.value == nil &&
            exercise.goal == nil &&
            stand.value == nil &&
            stand.goal == nil
    }

    static let empty = ActivityRingSummary(
        move: .empty,
        exercise: .empty,
        stand: .empty
    )
}

struct ActivityRingMetric: Equatable {
    var value: Double?
    var goal: Double?

    var progress: Double {
        guard let value, let goal, goal > 0, value.isFinite, goal.isFinite else {
            return 0
        }

        return min(max(value / goal, 0), 1)
    }

    static let empty = ActivityRingMetric(value: nil, goal: nil)
}

struct SleepSummary: Equatable {
    var duration: TimeInterval?
    var stageSnapshot: SleepStageSnapshot
    var vitals: SleepVitalsSummary

    init(
        duration: TimeInterval?,
        stageSnapshot: SleepStageSnapshot = .empty,
        vitals: SleepVitalsSummary = .empty
    ) {
        self.duration = duration
        self.stageSnapshot = stageSnapshot
        self.vitals = vitals
    }

    var score: SleepScoreSummary? {
        SleepScoreSummary(sleep: self)
    }
}

struct SleepVitalsSummary: Equatable {
    var heartRate: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperatureCelsius: Double?

    var isEmpty: Bool {
        heartRate == nil &&
            respiratoryRate == nil &&
            oxygenSaturation == nil &&
            wristTemperatureCelsius == nil
    }

    static let empty = SleepVitalsSummary(
        heartRate: nil,
        respiratoryRate: nil,
        oxygenSaturation: nil,
        wristTemperatureCelsius: nil
    )
}

enum SleepVitalRegion: Equatable {
    case low
    case typical
    case high
}

enum SleepVitalStatusTitle {
    static func text(for regions: [SleepVitalRegion]) -> String {
        let outlierCount = regions.filter { $0 != .typical }.count

        switch outlierCount {
        case 0:
            return "Typical"
        case 1:
            return "1 Outlier"
        default:
            return "\(outlierCount) Outliers"
        }
    }
}

struct SleepVitalReferenceRange: Equatable {
    var typicalLowerBound: Double
    var typicalUpperBound: Double

    func region(for value: Double) -> SleepVitalRegion {
        if value < typicalLowerBound {
            return .low
        }

        if value > typicalUpperBound {
            return .high
        }

        return .typical
    }

    func markerPosition(for value: Double) -> Double {
        let typicalSpan = max(typicalUpperBound - typicalLowerBound, 1)
        let lowerBound = typicalLowerBound - typicalSpan
        let upperBound = typicalUpperBound + typicalSpan
        let totalSpan = upperBound - lowerBound

        guard totalSpan > 0, value.isFinite else {
            return 0.5
        }

        return min(max((value - lowerBound) / totalSpan, 0), 1)
    }
}

struct SleepStageSnapshot: Equatable {
    var date: Date?
    var segments: [SleepStageSegment]

    var isEmpty: Bool {
        segments.isEmpty
    }

    var dateInterval: DateInterval? {
        guard let startDate = segments.map(\.startDate).min(),
              let endDate = segments.map(\.endDate).max(),
              endDate > startDate else {
            return nil
        }

        return DateInterval(start: startDate, end: endDate)
    }

    func duration(for stage: SleepStage) -> TimeInterval {
        segments
            .filter { $0.stage == stage }
            .reduce(0) { partialResult, segment in
                partialResult + max(0, segment.endDate.timeIntervalSince(segment.startDate))
            }
    }

    static let empty = SleepStageSnapshot(date: nil, segments: [])
}

struct SleepScoreSummary: Equatable {
    let total: Int
    let categories: [SleepScoreCategory]

    init?(sleep: SleepSummary) {
        guard let duration = sleep.duration, duration > 0 else {
            return nil
        }

        let categoryScores = [
            Self.category(
                kind: .duration,
                value: duration,
                target: 8 * 60 * 60,
                maximumPoints: 50
            ),
            Self.category(
                kind: .rem,
                value: sleep.stageSnapshot.duration(for: .rem),
                target: 90 * 60,
                maximumPoints: 25
            ),
            Self.category(
                kind: .deep,
                value: sleep.stageSnapshot.duration(for: .deep),
                target: 75 * 60,
                maximumPoints: 25
            )
        ]
        categories = categoryScores
        total = categoryScores.reduce(0) { $0 + $1.points }
    }

    private static func category(
        kind: SleepScoreCategory.Kind,
        value: TimeInterval,
        target: TimeInterval,
        maximumPoints: Int
    ) -> SleepScoreCategory {
        let progress = min(max(value / target, 0), 1)
        return SleepScoreCategory(
            kind: kind,
            points: Int((progress * Double(maximumPoints)).rounded()),
            maximumPoints: maximumPoints,
            progress: progress
        )
    }
}

struct SleepScoreCategory: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case duration
        case rem
        case deep

        var displayName: String {
            switch self {
            case .duration:
                return "Duration"
            case .rem:
                return "REM"
            case .deep:
                return "Deep"
            }
        }
    }

    let kind: Kind
    let points: Int
    let maximumPoints: Int
    let progress: Double

    var id: Kind {
        kind
    }
}

struct SleepStageSegment: Equatable, Identifiable {
    var stage: SleepStage
    var startDate: Date
    var endDate: Date

    var id: String {
        "\(stage.rawValue)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)"
    }
}

enum SleepStage: String, CaseIterable, Equatable, Identifiable {
    case awake
    case rem
    case core
    case deep

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .awake:
            return "Awake"
        case .rem:
            return "REM"
        case .core:
            return "Core"
        case .deep:
            return "Deep"
        }
    }

    var chartPosition: Double {
        switch self {
        case .awake:
            return 4
        case .rem:
            return 3
        case .core:
            return 2
        case .deep:
            return 1
        }
    }

    static func stage(at position: Double) -> SleepStage? {
        allCases.first { $0.chartPosition == position }
    }
}

struct HealthMetricSummary: Equatable {
    var value: Double?
}

struct HealthTrendSnapshot: Equatable {
    var sleep: HealthTrendSeries
    var restingHeartRate: HealthTrendSeries
    var bodyMass: HealthTrendSeries
    var bodyFatPercentage: HealthTrendSeries
    var heartRateVariability: HealthTrendSeries
    var respiratoryRate: HealthTrendSeries
    var oxygenSaturation: HealthTrendSeries
    var bodyMassIndex: HealthTrendSeries
    var activeEnergy: HealthTrendSeries
    var restingEnergy: HealthTrendSeries

    static let empty = HealthTrendSnapshot(
        sleep: .empty,
        restingHeartRate: .empty,
        bodyMass: .empty,
        bodyFatPercentage: .empty,
        heartRateVariability: .empty,
        respiratoryRate: .empty,
        oxygenSaturation: .empty,
        bodyMassIndex: .empty,
        activeEnergy: .empty,
        restingEnergy: .empty
    )

    func series(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .sleep:
            return sleep
        case .basics:
            return .empty
        case .restingHeartRate:
            return restingHeartRate
        case .bodyMass:
            return bodyMass
        case .bodyFatPercentage:
            return bodyFatPercentage
        case .heartRateVariability:
            return heartRateVariability
        case .respiratoryRate:
            return respiratoryRate
        case .oxygenSaturation:
            return oxygenSaturation
        case .bodyMassIndex:
            return bodyMassIndex
        case .activeEnergy:
            return activeEnergy
        case .restingEnergy:
            return restingEnergy
        }
    }
}

struct BasicsTrendSummary: Equatable {
    var weight: HealthTrendSeries
    var bodyFat: HealthTrendSeries

    var isEmpty: Bool {
        weight.isEmpty && bodyFat.isEmpty
    }

    static let empty = BasicsTrendSummary(weight: .empty, bodyFat: .empty)

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .current, date: Date = Date()) -> BasicsTrendSummary {
        BasicsTrendSummary(
            weight: weight.limited(to: range, calendar: calendar, date: date),
            bodyFat: bodyFat.limited(to: range, calendar: calendar, date: date)
        )
    }
}

struct HealthTrendSeries: Equatable {
    var points: [HealthTrendDataPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    static let empty = HealthTrendSeries(points: [])

    func mapValues(_ transform: (Double) -> Double) -> HealthTrendSeries {
        HealthTrendSeries(
            points: points.map {
                HealthTrendDataPoint(date: $0.date, value: transform($0.value))
            }
        )
    }

    func limited(to range: BodyHealthTrendRange, calendar: Calendar = .current, date: Date = Date()) -> HealthTrendSeries {
        guard range != .recentMonth else {
            return self
        }

        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        return HealthTrendSeries(
            points: points.filter { point in
                point.date >= startDate && point.date < endDate
            }
        )
    }
}

struct HealthTrendDataPoint: Equatable, Identifiable {
    var date: Date
    var value: Double

    var id: Date {
        date
    }
}
