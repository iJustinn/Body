//
//  StressModels.swift
//  Body
//

import Foundation

/// Garmin-convention stress bands over the 0-100 score.
enum StressBand: String, Codable, Equatable, CaseIterable {
    case rest
    case low
    case medium
    case high

    static let displayOrder: [StressBand] = [.rest, .low, .medium, .high]

    static func band(for score: Int) -> StressBand {
        switch score {
        case ...25:
            return .rest
        case 26...50:
            return .low
        case 51...75:
            return .medium
        default:
            return .high
        }
    }

    static func band(for score: Double) -> StressBand {
        band(for: Int(score.rounded()))
    }

    /// Numeric [min, max] of this band's score range.
    var scoreBounds: (min: Double, max: Double) {
        switch self {
        case .rest: return (0, 25)
        case .low: return (26, 50)
        case .medium: return (51, 75)
        case .high: return (76, 100)
        }
    }

    var lowerBound: Double? {
        switch self {
        case .rest: return nil
        case .low: return 25.5
        case .medium: return 50.5
        case .high: return 75.5
        }
    }

    var upperBound: Double? {
        switch self {
        case .rest: return 25.5
        case .low: return 50.5
        case .medium: return 75.5
        case .high: return nil
        }
    }

    var title: String {
        switch self {
        case .rest:
            return String(localized: "stress.band.rest", defaultValue: "Rest", table: "BodyMetricsKit")
        case .low:
            return String(localized: "stress.band.low", defaultValue: "Relaxed", table: "BodyMetricsKit")
        case .medium:
            return String(localized: "stress.band.medium", defaultValue: "Engaged", table: "BodyMetricsKit")
        case .high:
            return String(localized: "stress.band.high", defaultValue: "Stressed", table: "BodyMetricsKit")
        }
    }

    var scoreRangeText: String {
        switch self {
        case .rest: return "0-25"
        case .low: return "26-50"
        case .medium: return "51-75"
        case .high: return "76-100"
        }
    }

    var explanation: String {
        switch self {
        case .rest:
            return String(
                localized: "stress.band.rest.explanation",
                defaultValue: "Your body is in a recovery state, with little physiological arousal.",
                table: "BodyMetricsKit"
            )
        case .low:
            return String(
                localized: "stress.band.low.explanation",
                defaultValue: "A calm, everyday level of arousal. Nothing is taxing your system.",
                table: "BodyMetricsKit"
            )
        case .medium:
            return String(
                localized: "stress.band.medium.explanation",
                defaultValue: "Moderate arousal. Normal for a busy or focused stretch of the day.",
                table: "BodyMetricsKit"
            )
        case .high:
            return String(
                localized: "stress.band.high.explanation",
                defaultValue: "High arousal. Your body is working noticeably harder than at rest.",
                table: "BodyMetricsKit"
            )
        }
    }
}

/// One 15-minute slice of a day's stress curve.
struct StressWindow: Equatable {
    /// `.activity` windows are masked (movement drives HR, not arousal) and `.unscored`
    /// windows are genuine chart gaps — neither ever contributes a zero to the day.
    enum State: Equatable {
        case scored(score: Double, hrOnly: Bool)
        case activity
        case unscored
    }

    var interval: DateInterval
    var state: State

    var score: Double? {
        guard case let .scored(score, _) = state else {
            return nil
        }

        return score
    }

    var band: StressBand? {
        score.map { StressBand.band(for: $0) }
    }

    var isHROnly: Bool {
        guard case let .scored(_, hrOnly) = state else {
            return false
        }

        return hrOnly
    }

    var isScored: Bool {
        score != nil
    }
}

/// A day's stress rollup. Doubles as the persisted recorded entry, so it also carries
/// the per-day baseline aggregates — the intraday day-sample cache only reaches back
/// ~32 days, and it is stripped from the saved dashboard snapshot.
struct StressDaySummary: Codable, Equatable {
    var date: Date
    var averageScore: Int?
    var minutesByBand: [StressBand: Int]
    var scoredWindowCount: Int
    var hrvCoveredWindowCount: Int
    /// Median of this day's unmasked awake window-median heart rates — the quiet-HR
    /// baseline is built from these, one per distinct day.
    var quietHRMedian: Double?
    /// Median of this day's beat-to-beat RMSSD samples, feeding the RMSSD baseline.
    var rmssdDailyMedian: Double?
    /// Lowest and highest scored-window scores for the day, nil when nothing scored.
    /// Feeds the intraday min-max range band behind the trend charts' average line.
    var minScore: Int?
    var maxScore: Int?
    /// Minutes masked out as movement (`.activity` windows). Not a band — the day
    /// breakdown shows it as its own row so the rows account for the whole
    /// measured day, and the percentages share the scored + activity denominator.
    var activityMinutes: Int

    enum CodingKeys: String, CodingKey {
        case date
        case averageScore
        case minutesByBand
        case scoredWindowCount
        case hrvCoveredWindowCount
        case quietHRMedian
        case rmssdDailyMedian
        case minScore
        case maxScore
        case activityMinutes
    }

    init(
        date: Date,
        averageScore: Int? = nil,
        minutesByBand: [StressBand: Int] = [:],
        scoredWindowCount: Int = 0,
        hrvCoveredWindowCount: Int = 0,
        quietHRMedian: Double? = nil,
        rmssdDailyMedian: Double? = nil,
        minScore: Int? = nil,
        maxScore: Int? = nil,
        activityMinutes: Int = 0
    ) {
        self.date = date
        self.averageScore = averageScore
        self.minutesByBand = minutesByBand
        self.scoredWindowCount = scoredWindowCount
        self.hrvCoveredWindowCount = hrvCoveredWindowCount
        self.quietHRMedian = quietHRMedian
        self.rmssdDailyMedian = rmssdDailyMedian
        self.minScore = minScore
        self.maxScore = maxScore
        self.activityMinutes = activityMinutes
    }

    var band: StressBand? {
        averageScore.map { StressBand.band(for: $0) }
    }

    func minutes(in band: StressBand) -> Int {
        minutesByBand[band, default: 0]
    }

    var totalScoredMinutes: Int {
        StressBand.displayOrder.reduce(0) { $0 + minutes(in: $1) }
    }

    /// Scored plus masked minutes: the denominator the day breakdown's rows share,
    /// so the four band rows and the Activity row sum to 100%.
    var totalMeasuredMinutes: Int {
        totalScoredMinutes + activityMinutes
    }

    // MARK: - Codable
    //
    // `[StressBand: Int]` isn't `CodingKeyRepresentable` (StressBand's synthesized
    // conformance doesn't pick it up), so the synthesized Codable would encode
    // `minutesByBand` as a flat, hash-ordered `[StressBand, Int, StressBand, Int, ...]`
    // array — the pair order changes between launches even for an identical value,
    // which defeats the snapshot store's save-if-changed byte compare (see
    // LessonsLearned.md, "JSONEncoder output is not byte-stable"). Encoding it as a
    // keyed `[String: Int]` instead lets `JSONEncoder`'s `.sortedKeys` output
    // formatting (which every snapshot-store encoder sets) stabilize the order.

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        averageScore = try container.decodeIfPresent(Int.self, forKey: .averageScore)
        let rawMinutesByBand = try container.decodeIfPresent([String: Int].self, forKey: .minutesByBand) ?? [:]
        var minutesByBand: [StressBand: Int] = [:]
        for (rawBand, minutes) in rawMinutesByBand {
            guard let band = StressBand(rawValue: rawBand) else { continue }
            minutesByBand[band] = minutes
        }
        self.minutesByBand = minutesByBand
        scoredWindowCount = try container.decodeIfPresent(Int.self, forKey: .scoredWindowCount) ?? 0
        hrvCoveredWindowCount = try container.decodeIfPresent(Int.self, forKey: .hrvCoveredWindowCount) ?? 0
        quietHRMedian = try container.decodeIfPresent(Double.self, forKey: .quietHRMedian)
        rmssdDailyMedian = try container.decodeIfPresent(Double.self, forKey: .rmssdDailyMedian)
        minScore = try container.decodeIfPresent(Int.self, forKey: .minScore)
        maxScore = try container.decodeIfPresent(Int.self, forKey: .maxScore)
        activityMinutes = try container.decodeIfPresent(Int.self, forKey: .activityMinutes) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(averageScore, forKey: .averageScore)
        let rawMinutesByBand = Dictionary(
            uniqueKeysWithValues: minutesByBand.map { ($0.key.rawValue, $0.value) }
        )
        try container.encode(rawMinutesByBand, forKey: .minutesByBand)
        try container.encode(scoredWindowCount, forKey: .scoredWindowCount)
        try container.encode(hrvCoveredWindowCount, forKey: .hrvCoveredWindowCount)
        try container.encodeIfPresent(quietHRMedian, forKey: .quietHRMedian)
        try container.encodeIfPresent(rmssdDailyMedian, forKey: .rmssdDailyMedian)
        try container.encodeIfPresent(minScore, forKey: .minScore)
        try container.encodeIfPresent(maxScore, forKey: .maxScore)
        try container.encode(activityMinutes, forKey: .activityMinutes)
    }
}
