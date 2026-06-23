//
//  ReadinessModels.swift
//  Body
//

import Foundation

enum ReadinessStatus: String, Codable, Equatable {
    case prime
    case high
    case moderate
    case low
    case poor
    case unavailable

    static let displayOrder: [ReadinessStatus] = [.prime, .high, .moderate, .low, .poor]

    static func status(for score: Int?) -> ReadinessStatus {
        guard let score else {
            return .unavailable
        }

        switch score {
        case 95...100:
            return .prime
        case 80...94:
            return .high
        case 65...79:
            return .moderate
        case 30...64:
            return .low
        default:
            return .poor
        }
    }

    /// Numeric [min, max] of this band's score range, for the watch corner gauge.
    /// nil for `.unavailable`.
    var scoreBounds: (min: Double, max: Double)? {
        switch self {
        case .prime: return (95, 100)
        case .high: return (80, 94)
        case .moderate: return (65, 79)
        case .low: return (30, 64)
        case .poor: return (0, 29)
        case .unavailable: return nil
        }
    }

    var title: String {
        switch self {
        case .prime:
            return "Prime"
        case .high:
            return "High"
        case .moderate:
            return "Moderate"
        case .low:
            return "Low"
        case .poor:
            return "Poor"
        case .unavailable:
            return "Needs Data"
        }
    }

    var scoreRangeText: String {
        switch self {
        case .prime:
            return "95-100%"
        case .high:
            return "80-94%"
        case .moderate:
            return "65-79%"
        case .low:
            return "30-64%"
        case .poor:
            return "0-29%"
        case .unavailable:
            return "--"
        }
    }

    var explanation: String {
        switch self {
        case .prime:
            return "Strong readiness signals. Most training is on the table."
        case .high:
            return "Well prepared. Normal training should be fine."
        case .moderate:
            return "Decent readiness. Keep load controlled."
        case .low:
            return "Readiness is lagging. Favor easy work or rest."
        case .poor:
            return "Rest or keep it very light until signals rebound."
        case .unavailable:
            return "More Apple Health history is needed before scoring."
        }
    }

    var lowerBound: Double? {
        switch self {
        case .poor:
            return nil
        case .low:
            return 30
        case .moderate:
            return 65
        case .high:
            return 80
        case .prime:
            return 95
        case .unavailable:
            return nil
        }
    }

    var upperBound: Double? {
        switch self {
        case .poor:
            return 30
        case .low:
            return 65
        case .moderate:
            return 80
        case .high:
            return 95
        case .prime:
            return nil
        case .unavailable:
            return nil
        }
    }
}

struct ReadinessStatusBreakdownEntry: Equatable, Identifiable {
    let status: ReadinessStatus
    let dayCount: Int
    let totalDayCount: Int

    var id: ReadinessStatus {
        status
    }

    var fractionOfTotal: Double {
        guard totalDayCount > 0 else {
            return 0
        }

        return Double(dayCount) / Double(totalDayCount)
    }
}

enum ReadinessStatusBreakdown {
    static func entries(
        for series: HealthTrendSeries,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [ReadinessStatusBreakdownEntry] {
        let statuses = series.calendarPoints(to: range, calendar: calendar, date: date)
            .compactMap { point -> ReadinessStatus? in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                let status = ReadinessStatus.status(for: Int(value.rounded()))
                return status == .unavailable ? nil : status
            }
        let countsByStatus = Dictionary(grouping: statuses) { $0 }
            .mapValues(\.count)
        let totalDayCount = countsByStatus.values.reduce(0, +)

        return ReadinessStatus.displayOrder.map { status in
            ReadinessStatusBreakdownEntry(
                status: status,
                dayCount: countsByStatus[status, default: 0],
                totalDayCount: totalDayCount
            )
        }
    }
}

enum ReadinessConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
    case unavailable

    var title: String {
        switch self {
        case .high:
            return "High confidence"
        case .medium:
            return "Medium confidence"
        case .low:
            return "Provisional"
        case .unavailable:
            return "Needs more data"
        }
    }
}

enum ReadinessComponentKind: String, Codable, CaseIterable, Equatable {
    case autonomic
    case sleep
    case training
    case vitals

    var title: String {
        switch self {
        case .autonomic:
            return "Autonomic"
        case .sleep:
            return "Sleep"
        case .training:
            return "Training"
        case .vitals:
            return "Vitals"
        }
    }
}

enum ReadinessDriverKind: String, Codable, Equatable {
    case hrvBelowBaseline
    case heartRateAboveBaseline
    case sleepDurationBelowGoal
    case sleepFragmented
    case trainingLoadElevated
    case respiratoryRateAboveBaseline
    case oxygenSaturationLow
    case wristTemperatureAboveBaseline
    case mostlyTypical
    case needsMoreData
}

struct ReadinessComponent: Codable, Equatable, Identifiable {
    var kind: ReadinessComponentKind
    var score: Int?
    var weight: Double
    var message: String

    var id: ReadinessComponentKind {
        kind
    }
}

struct ReadinessDriver: Codable, Equatable, Identifiable {
    var kind: ReadinessDriverKind
    var message: String
    var impact: Double

    var id: ReadinessDriverKind {
        kind
    }
}

struct ReadinessSummary: Codable, Equatable {
    var score: Int?
    var status: ReadinessStatus
    var confidence: ReadinessConfidence
    var components: [ReadinessComponent]
    var drivers: [ReadinessDriver]

    static let unavailable = ReadinessSummary(
        score: nil,
        status: .unavailable,
        confidence: .unavailable,
        components: [],
        drivers: []
    )
}
