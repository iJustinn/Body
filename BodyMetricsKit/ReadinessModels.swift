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
        case 95...:
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

    /// The morning (pre-drain) score when today's workouts have drained the live tile, else
    /// nil. Non-nil marks "a workout pulled today's tile down"; the hero derives the pre-drain
    /// band from it for the deep-drop copy. The *size* of the drop comes from
    /// `activityDrainPoints`, not this minus the displayed score. Optional so snapshots
    /// persisted before this field decode as nil (no drain).
    var activityDrainMorningScore: Int?

    /// Points the workout actually drained (pre-softening/clamping), or nil when no drain.
    /// The hero sizes the drop from THIS: when the morning score sits near the floor, a
    /// demanding session is clamped in the display (e.g. 8% → 0%), so the visible delta
    /// understates the effort and would misread as a light activity. Optional so pre-existing
    /// snapshots decode as nil.
    var activityDrainPoints: Int?

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
    ///
    /// When today's workouts drained the live score (`activityDrainMorningScore` set),
    /// the workout-aware explanation takes over so the hero attributes the drop to
    /// training instead of the (now-misleading) morning driver.
    var heroExplanation: String {
        // Past midnight before wake, today's sleep session isn't recorded yet, so the
        // sleep component drops out while the score still computes from the other signals.
        // Keep the number as-is but tell the user we're still waiting on sleep.
        if score != nil, !components.contains(where: { $0.kind == .sleep }) {
            return String(localized: "Today's sleep data isn't in yet. Get some rest and check back later for a more accurate result.", table: "BodyMetricsKit")
        }
        if let morningScore = activityDrainMorningScore {
            // Size the drop from the actual drain; fall back to the displayed delta only for
            // legacy snapshots that recorded the morning score before `activityDrainPoints` existed.
            let drain = activityDrainPoints ?? (morningScore - (score ?? morningScore))
            return status.activityDrainHeroExplanation(
                morningStatus: ReadinessStatus.status(for: morningScore),
                drain: drain
            )
        }
        return status.heroExplanation(forDriver: drivers.first?.kind ?? .mostlyTypical)
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
                return String(localized: "Resting heart rate is slightly higher than your baseline, but every other signal is strong. Prime to go.", table: "BodyMetricsKit")
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
                return String(localized: "Resting heart rate is slightly higher than your baseline, yet you're well prepared for a normal day.", table: "BodyMetricsKit")
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
                return String(localized: "Resting heart rate is higher than your baseline. Readiness is moderate; hold the intensity back.", table: "BodyMetricsKit")
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
                return String(localized: "Resting heart rate is higher than your baseline, so your system hasn't fully settled. Keep it light.", table: "BodyMetricsKit")
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
                return String(localized: "Resting heart rate is markedly higher than your baseline. Prioritize rest until it settles.", table: "BodyMetricsKit")
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

    /// Points of same-day drain (morning − current score) at or above which today's
    /// activity reads as real training rather than a light activity — so the hero
    /// attributes the dip to the workout even when the band did not change. A genuinely
    /// light session drains only a few points; a real workout drains well into double digits.
    static let meaningfulActivityDrain = 10

    /// Hero explanation for when today's workouts drained the live score. `morningStatus`
    /// is the band before the drain and `drain` is how many points the workout actually
    /// removed (pre-softening, so a floor-clamped display doesn't shrink it). A drain of
    /// `meaningfulActivityDrain`+ reads as real training (earned training fatigue), whether or
    /// not the band changed; a smaller drain reads as a light activity, with the status still
    /// reflecting recovery signals. `.unavailable` can't occur here (a drained score is always
    /// numeric) but falls back safely.
    func activityDrainHeroExplanation(morningStatus: ReadinessStatus, drain: Int) -> String {
        if drain >= Self.meaningfulActivityDrain {
            switch self {
            case .high:
                return String(localized: "Today's workout took some energy out of you, but readiness is still high. You can carry on with your training.", table: "BodyMetricsKit")
            case .moderate:
                return String(localized: "Today's workout has lowered your readiness. This is training load, not under recovery. Focus on resting for the rest of the day.", table: "BodyMetricsKit")
            case .low:
                // A crash from the top bands to Low is a serious same-day drop worth its own line.
                switch morningStatus {
                case .prime:
                    return String(localized: "Today's workout was very demanding, taking readiness from an exceptional state all the way down to a low point. That's a big training load, so some active recovery for the rest of the day would help.", table: "BodyMetricsKit")
                case .high:
                    return String(localized: "Today's workout brought readiness from high down to low. That was a considerable session, so rest and recover fully for the rest of the day.", table: "BodyMetricsKit")
                default:
                    return String(localized: "Your lower readiness is mainly from today's workout. It reflects the effort you put in, not poor recovery. Give your body some rest for the rest of the day.", table: "BodyMetricsKit")
                }
            case .poor:
                return String(localized: "You've done enough training today. You've reached training fatigue, and doing more could risk injury. Prioritize rest and recovery.", table: "BodyMetricsKit")
            case .prime, .unavailable:
                return explanation
            }
        }

        switch self {
        case .prime:
            return String(localized: "You've already worked out today and readiness is still prime. There's room to push a little harder.", table: "BodyMetricsKit")
        case .high:
            return String(localized: "A light activity today nudged your readiness down a little, but it's still high. Train as planned.", table: "BodyMetricsKit")
        case .moderate:
            return String(localized: "Today's activity was light, so your moderate readiness mainly reflects your recovery signals. Keep the load controlled.", table: "BodyMetricsKit")
        case .low:
            return String(localized: "Only a light activity today, so your low readiness mainly reflects your recovery signals, not training.", table: "BodyMetricsKit")
        case .poor:
            return String(localized: "Just a light activity today. Your poor readiness reflects your recovery signals, so rest well to recover better.", table: "BodyMetricsKit")
        case .unavailable:
            return explanation
        }
    }
}
