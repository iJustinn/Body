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
            return String(localized: "Prime", table: "BodyMetricsKit")
        case .high:
            return String(localized: "High", table: "BodyMetricsKit")
        case .moderate:
            return String(localized: "Moderate", table: "BodyMetricsKit")
        case .low:
            return String(localized: "Low", table: "BodyMetricsKit")
        case .poor:
            return String(localized: "Poor", table: "BodyMetricsKit")
        case .unavailable:
            return String(localized: "Needs Data", table: "BodyMetricsKit")
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
            return String(localized: "Strong readiness signals. Most training is on the table.", table: "BodyMetricsKit")
        case .high:
            return String(localized: "Well prepared. Normal training should be fine.", table: "BodyMetricsKit")
        case .moderate:
            return String(localized: "Decent readiness. Keep load controlled.", table: "BodyMetricsKit")
        case .low:
            return String(localized: "Readiness is lagging. Favor easy work or rest.", table: "BodyMetricsKit")
        case .poor:
            return String(localized: "Rest or keep it very light until signals rebound.", table: "BodyMetricsKit")
        case .unavailable:
            return String(localized: "More Apple Health history is needed before scoring.", table: "BodyMetricsKit")
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
            return String(localized: "High confidence", table: "BodyMetricsKit")
        case .medium:
            return String(localized: "Medium confidence", table: "BodyMetricsKit")
        case .low:
            return String(localized: "Provisional", table: "BodyMetricsKit")
        case .unavailable:
            return String(localized: "Needs more data", table: "BodyMetricsKit")
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
            return String(localized: "Autonomic", table: "BodyMetricsKit")
        case .sleep:
            return String(localized: "Sleep", table: "BodyMetricsKit")
        case .training:
            return String(localized: "Training", table: "BodyMetricsKit")
        case .vitals:
            return String(localized: "Vitals", table: "BodyMetricsKit")
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

    /// Metric-aware explanation for the Home star hero: names the signal currently
    /// moving today's score, keyed to the strongest active driver. Falls back to the
    /// generic band `explanation` when nothing stands out is unresolved. The static
    /// per-band legend elsewhere keeps using `status.explanation`.
    var heroExplanation: String {
        status.heroExplanation(forDriver: drivers.first?.kind ?? .mostlyTypical)
    }
}

extension ReadinessStatus {
    /// One authored sentence per real signal, per band — so the hero says what is
    /// actually driving readiness (short sleep, high load, soft HRV, …) instead of a
    /// single generic line. `.unavailable` and the `.needsMoreData` driver fall back to
    /// the generic `explanation` (the "needs more history" caveat).
    func heroExplanation(forDriver driver: ReadinessDriverKind) -> String {
        if self == .unavailable || driver == .needsMoreData {
            return explanation
        }

        switch self {
        case .prime:
            switch driver {
            case .hrvBelowBaseline:
                return String(localized: "Readiness is prime even with HRV a touch under baseline. You're primed to train.", table: "BodyMetricsKit")
            case .heartRateAboveBaseline:
                return String(localized: "Resting heart rate ticked up slightly, but every other signal is strong. Prime to go.", table: "BodyMetricsKit")
            case .sleepDurationBelowGoal:
                return String(localized: "Sleep ran a little short, yet recovery still landed in the prime range.", table: "BodyMetricsKit")
            case .sleepFragmented:
                return String(localized: "Sleep was a bit broken, but your recovery signals still read prime.", table: "BodyMetricsKit")
            case .trainingLoadElevated:
                return String(localized: "Load is building and you've absorbed it. Readiness is prime for a hard effort.", table: "BodyMetricsKit")
            case .respiratoryRateAboveBaseline:
                return String(localized: "Breathing rate is a hair high, but nothing's holding you back. Prime to train.", table: "BodyMetricsKit")
            case .oxygenSaturationLow:
                return String(localized: "Blood oxygen dipped slightly, though overall readiness is prime.", table: "BodyMetricsKit")
            case .wristTemperatureAboveBaseline:
                return String(localized: "Skin temperature is a touch high, but recovery still reads prime.", table: "BodyMetricsKit")
            case .mostlyTypical:
                return String(localized: "Every signal is on or above baseline. You're primed for your hardest training.", table: "BodyMetricsKit")
            case .needsMoreData:
                return explanation
            }
        case .high:
            switch driver {
            case .hrvBelowBaseline:
                return String(localized: "HRV is a little under baseline, but recovery is solid. Normal training is fine.", table: "BodyMetricsKit")
            case .heartRateAboveBaseline:
                return String(localized: "Resting heart rate is slightly elevated, yet you're well prepared for a normal day.", table: "BodyMetricsKit")
            case .sleepDurationBelowGoal:
                return String(localized: "Sleep was a bit short, but readiness is high. A normal session should feel good.", table: "BodyMetricsKit")
            case .sleepFragmented:
                return String(localized: "Sleep was somewhat restless, though your signals still read high. Train as planned.", table: "BodyMetricsKit")
            case .trainingLoadElevated:
                return String(localized: "Training load is up and you're handling it well. Readiness stays high.", table: "BodyMetricsKit")
            case .respiratoryRateAboveBaseline:
                return String(localized: "Breathing rate is slightly high, but you're well recovered. Normal training is fine.", table: "BodyMetricsKit")
            case .oxygenSaturationLow:
                return String(localized: "Blood oxygen is a touch low, yet overall readiness is high.", table: "BodyMetricsKit")
            case .wristTemperatureAboveBaseline:
                return String(localized: "Skin temperature is a little high, but recovery reads high. Train as planned.", table: "BodyMetricsKit")
            case .mostlyTypical:
                return String(localized: "Your signals sit comfortably above baseline. You're well prepared to train.", table: "BodyMetricsKit")
            case .needsMoreData:
                return explanation
            }
        case .moderate:
            switch driver {
            case .hrvBelowBaseline:
                return String(localized: "HRV is running below baseline. Readiness is okay, but keep the load controlled.", table: "BodyMetricsKit")
            case .heartRateAboveBaseline:
                return String(localized: "Resting heart rate is up a bit. Readiness is moderate; hold the intensity back.", table: "BodyMetricsKit")
            case .sleepDurationBelowGoal:
                return String(localized: "Sleep came up short last night, so keep today's training moderate.", table: "BodyMetricsKit")
            case .sleepFragmented:
                return String(localized: "Restless sleep has readiness at a moderate level. Keep the effort in check.", table: "BodyMetricsKit")
            case .trainingLoadElevated:
                return String(localized: "Recent load is elevated. Readiness is moderate, so manage the intensity.", table: "BodyMetricsKit")
            case .respiratoryRateAboveBaseline:
                return String(localized: "Breathing rate is above baseline. Readiness is moderate; keep it measured.", table: "BodyMetricsKit")
            case .oxygenSaturationLow:
                return String(localized: "Blood oxygen is below your norm, nudging readiness to moderate. Keep load controlled.", table: "BodyMetricsKit")
            case .wristTemperatureAboveBaseline:
                return String(localized: "Skin temperature is above baseline. Readiness is moderate, so keep it measured.", table: "BodyMetricsKit")
            case .mostlyTypical:
                return String(localized: "Signals are mostly typical. Readiness is decent, so keep the load controlled.", table: "BodyMetricsKit")
            case .needsMoreData:
                return explanation
            }
        case .low:
            switch driver {
            case .hrvBelowBaseline:
                return String(localized: "HRV is sitting below your baseline and recovery is still catching up. Favor easy work.", table: "BodyMetricsKit")
            case .heartRateAboveBaseline:
                return String(localized: "Resting heart rate is running high, so your system hasn't fully settled. Keep it light.", table: "BodyMetricsKit")
            case .sleepDurationBelowGoal:
                return String(localized: "Short sleep last night is the main drag on today's readiness.", table: "BodyMetricsKit")
            case .sleepFragmented:
                return String(localized: "Broken, restless sleep is holding readiness back. Ease into the day.", table: "BodyMetricsKit")
            case .trainingLoadElevated:
                return String(localized: "Recent training load has piled up and readiness is paying for it. Favor recovery.", table: "BodyMetricsKit")
            case .respiratoryRateAboveBaseline:
                return String(localized: "Overnight breathing rate is elevated, a sign of extra load. Take it easy.", table: "BodyMetricsKit")
            case .oxygenSaturationLow:
                return String(localized: "Blood oxygen dipped below your norm. Go gently until it recovers.", table: "BodyMetricsKit")
            case .wristTemperatureAboveBaseline:
                return String(localized: "Skin temperature is above baseline, often an early strain or illness cue. Keep it light.", table: "BodyMetricsKit")
            case .mostlyTypical:
                return String(localized: "Signals are mixed but nothing stands out. Readiness is simply low today. Favor easy work.", table: "BodyMetricsKit")
            case .needsMoreData:
                return explanation
            }
        case .poor:
            switch driver {
            case .hrvBelowBaseline:
                return String(localized: "HRV is well below baseline and your body needs recovery. Rest or keep it very light.", table: "BodyMetricsKit")
            case .heartRateAboveBaseline:
                return String(localized: "Resting heart rate is markedly elevated. Prioritize rest until it settles.", table: "BodyMetricsKit")
            case .sleepDurationBelowGoal:
                return String(localized: "Very little sleep last night has readiness low. Rest is the priority today.", table: "BodyMetricsKit")
            case .sleepFragmented:
                return String(localized: "Badly broken sleep has left you short on recovery. Keep it very light or rest.", table: "BodyMetricsKit")
            case .trainingLoadElevated:
                return String(localized: "Training load has outpaced recovery and readiness is low. Back off and rest.", table: "BodyMetricsKit")
            case .respiratoryRateAboveBaseline:
                return String(localized: "Breathing rate is well above baseline, a strong load or illness cue. Rest up.", table: "BodyMetricsKit")
            case .oxygenSaturationLow:
                return String(localized: "Blood oxygen is notably low. Take it very easy until it recovers.", table: "BodyMetricsKit")
            case .wristTemperatureAboveBaseline:
                return String(localized: "Skin temperature is well above baseline, a common illness signal. Rest today.", table: "BodyMetricsKit")
            case .mostlyTypical:
                return String(localized: "Multiple signals are down together and readiness is poor. Rest or keep it very light.", table: "BodyMetricsKit")
            case .needsMoreData:
                return explanation
            }
        case .unavailable:
            return explanation
        }
    }
}
