//
//  HealthSummarySnapshot.swift
//  Body
//

import Foundation

enum HealthMetricKind: String, CaseIterable, Identifiable {
    case sleep
    case restingHeartRate
    case bodyMass
    case bodyFatPercentage
    case heartRateVariability
    case oxygenSaturation
    case vo2Max
    case bodyMassIndex
    case activeEnergy
    case restingEnergy

    var id: String {
        rawValue
    }
}

struct HealthSummarySnapshot: Equatable {
    var sleep: SleepSummary
    var restingHeartRate: HealthMetricSummary
    var bodyMass: HealthMetricSummary
    var bodyFatPercentage: HealthMetricSummary
    var heartRateVariability: HealthMetricSummary
    var oxygenSaturation: HealthMetricSummary
    var vo2Max: HealthMetricSummary
    var bodyMassIndex: HealthMetricSummary
    var activeEnergy: HealthMetricSummary
    var restingEnergy: HealthMetricSummary

    var isEmpty: Bool {
        sleep.duration == nil &&
            restingHeartRate.value == nil &&
            bodyMass.value == nil &&
            bodyFatPercentage.value == nil &&
            heartRateVariability.value == nil &&
            oxygenSaturation.value == nil &&
            vo2Max.value == nil &&
            bodyMassIndex.value == nil &&
            activeEnergy.value == nil &&
            restingEnergy.value == nil
    }

    static let empty = HealthSummarySnapshot(
        sleep: SleepSummary(duration: nil),
        restingHeartRate: HealthMetricSummary(value: nil),
        bodyMass: HealthMetricSummary(value: nil),
        bodyFatPercentage: HealthMetricSummary(value: nil),
        heartRateVariability: HealthMetricSummary(value: nil),
        oxygenSaturation: HealthMetricSummary(value: nil),
        vo2Max: HealthMetricSummary(value: nil),
        bodyMassIndex: HealthMetricSummary(value: nil),
        activeEnergy: HealthMetricSummary(value: nil),
        restingEnergy: HealthMetricSummary(value: nil)
    )

    static let placeholder = HealthSummarySnapshot(
        sleep: SleepSummary(duration: 28_740),
        restingHeartRate: HealthMetricSummary(value: 60),
        bodyMass: HealthMetricSummary(value: 69.3),
        bodyFatPercentage: HealthMetricSummary(value: 13.1),
        heartRateVariability: HealthMetricSummary(value: 38.4),
        oxygenSaturation: HealthMetricSummary(value: 97),
        vo2Max: HealthMetricSummary(value: 41.0),
        bodyMassIndex: HealthMetricSummary(value: 22.1),
        activeEnergy: HealthMetricSummary(value: 520),
        restingEnergy: HealthMetricSummary(value: 1_690)
    )
}

struct SleepSummary: Equatable {
    var duration: TimeInterval?
    var stageSnapshot: SleepStageSnapshot

    init(duration: TimeInterval?, stageSnapshot: SleepStageSnapshot = .empty) {
        self.duration = duration
        self.stageSnapshot = stageSnapshot
    }
}

struct SleepStageSnapshot: Equatable {
    var date: Date?
    var segments: [SleepStageSegment]

    var isEmpty: Bool {
        segments.isEmpty
    }

    static let empty = SleepStageSnapshot(date: nil, segments: [])
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
    var oxygenSaturation: HealthTrendSeries
    var vo2Max: HealthTrendSeries
    var bodyMassIndex: HealthTrendSeries
    var activeEnergy: HealthTrendSeries
    var restingEnergy: HealthTrendSeries

    static let empty = HealthTrendSnapshot(
        sleep: .empty,
        restingHeartRate: .empty,
        bodyMass: .empty,
        bodyFatPercentage: .empty,
        heartRateVariability: .empty,
        oxygenSaturation: .empty,
        vo2Max: .empty,
        bodyMassIndex: .empty,
        activeEnergy: .empty,
        restingEnergy: .empty
    )

    func series(for kind: HealthMetricKind) -> HealthTrendSeries {
        switch kind {
        case .sleep:
            return sleep
        case .restingHeartRate:
            return restingHeartRate
        case .bodyMass:
            return bodyMass
        case .bodyFatPercentage:
            return bodyFatPercentage
        case .heartRateVariability:
            return heartRateVariability
        case .oxygenSaturation:
            return oxygenSaturation
        case .vo2Max:
            return vo2Max
        case .bodyMassIndex:
            return bodyMassIndex
        case .activeEnergy:
            return activeEnergy
        case .restingEnergy:
            return restingEnergy
        }
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
