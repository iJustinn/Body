//
//  RecoveryModels.swift
//  Body
//

import Foundation

enum RecoveryStatus: String, Codable, Equatable {
    case prime
    case high
    case moderate
    case low
    case poor
    case unavailable

    static let displayOrder: [RecoveryStatus] = [.prime, .high, .moderate, .low, .poor]

    static func status(for score: Int?) -> RecoveryStatus {
        guard let score else {
            return .unavailable
        }

        switch score {
        case 96...100:
            return .prime
        case 75...95:
            return .high
        case 50..<75:
            return .moderate
        case 25..<50:
            return .low
        default:
            return .poor
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
            return "96-100%"
        case .high:
            return "75-95%"
        case .moderate:
            return "50-74%"
        case .low:
            return "25-49%"
        case .poor:
            return "0-24%"
        case .unavailable:
            return "--"
        }
    }

    var explanation: String {
        switch self {
        case .prime:
            return "Strong recovery signals. Most training is on the table."
        case .high:
            return "Well recovered. Normal training should be fine."
        case .moderate:
            return "Decent recovery. Keep load controlled."
        case .low:
            return "Recovery is lagging. Favor easy work or rest."
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
            return 25
        case .moderate:
            return 50
        case .high:
            return 75
        case .prime:
            return 95
        case .unavailable:
            return nil
        }
    }

    var upperBound: Double? {
        switch self {
        case .poor:
            return 25
        case .low:
            return 50
        case .moderate:
            return 75
        case .high:
            return 95
        case .prime:
            return nil
        case .unavailable:
            return nil
        }
    }
}

struct RecoveryStatusBreakdownEntry: Equatable, Identifiable {
    let status: RecoveryStatus
    let dayCount: Int
    let totalDayCount: Int

    var id: RecoveryStatus {
        status
    }

    var fractionOfTotal: Double {
        guard totalDayCount > 0 else {
            return 0
        }

        return Double(dayCount) / Double(totalDayCount)
    }
}

enum RecoveryStatusBreakdown {
    static func entries(
        for series: HealthTrendSeries,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [RecoveryStatusBreakdownEntry] {
        let statuses = series.calendarPoints(to: range, calendar: calendar, date: date)
            .compactMap { point -> RecoveryStatus? in
                guard let value = point.value, value.isFinite else {
                    return nil
                }

                let status = RecoveryStatus.status(for: Int(value.rounded()))
                return status == .unavailable ? nil : status
            }
        let countsByStatus = Dictionary(grouping: statuses) { $0 }
            .mapValues(\.count)
        let totalDayCount = countsByStatus.values.reduce(0, +)

        return RecoveryStatus.displayOrder.map { status in
            RecoveryStatusBreakdownEntry(
                status: status,
                dayCount: countsByStatus[status, default: 0],
                totalDayCount: totalDayCount
            )
        }
    }
}

enum RecoveryConfidence: String, Codable, Equatable {
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

enum RecoveryComponentKind: String, Codable, CaseIterable, Equatable {
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

enum RecoveryDriverKind: String, Codable, Equatable {
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

struct RecoveryComponent: Codable, Equatable, Identifiable {
    var kind: RecoveryComponentKind
    var score: Int?
    var weight: Double
    var message: String

    var id: RecoveryComponentKind {
        kind
    }
}

struct RecoveryDriver: Codable, Equatable, Identifiable {
    var kind: RecoveryDriverKind
    var message: String
    var impact: Double

    var id: RecoveryDriverKind {
        kind
    }
}

struct RecoverySummary: Codable, Equatable {
    var score: Int?
    var status: RecoveryStatus
    var confidence: RecoveryConfidence
    var components: [RecoveryComponent]
    var drivers: [RecoveryDriver]

    static let unavailable = RecoverySummary(
        score: nil,
        status: .unavailable,
        confidence: .unavailable,
        components: [],
        drivers: []
    )
}
