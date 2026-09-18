//
//  MetricThresholdWarning.swift
//  Body
//

import Foundation

/// The Apple-style threshold warnings Body detects (plus Body's own for
/// respiratory rate and wrist temperature): a reading past a limit today. The default limit and its editable range live here so the HealthKit
/// predicate, the chart rule and the copy all read the same numbers.
enum MetricWarningKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case lowHeartRate
    case highHeartRate
    case lowBloodOxygen
    case highRespiratoryRate
    case highWristTemperature

    var id: String {
        rawValue
    }

    var metric: HealthMetricKind {
        switch self {
        case .lowHeartRate, .highHeartRate:
            return .heartRate
        case .lowBloodOxygen:
            return .oxygenSaturation
        case .highRespiratoryRate:
            return .respiratoryRate
        case .highWristTemperature:
            return .wristTemperature
        }
    }

    /// The value used when the user hasn't picked their own. Compared strictly:
    /// a reading exactly at the threshold never warns.
    var defaultThreshold: Double {
        switch self {
        case .lowHeartRate:
            return 40
        case .highHeartRate:
            return 120
        case .lowBloodOxygen:
            return 90
        case .highRespiratoryRate:
            return 20
        case .highWristTemperature:
            // Wrist skin temperature, always in °C: cooler than core temperature,
            // so a night above this is well past a typical baseline.
            return 38
        }
    }

    /// Bounds of the Settings wheel picker for a custom threshold.
    var thresholdRange: ClosedRange<Double> {
        switch self {
        case .lowHeartRate:
            return 30...60
        case .highHeartRate:
            return 100...200
        case .lowBloodOxygen:
            return 80...95
        case .highRespiratoryRate:
            return 12...30
        case .highWristTemperature:
            return 35...40
        }
    }

    /// The picker's granularity: whole units, except tenths of a degree for
    /// wrist temperature, whose readings only move by tenths.
    var thresholdStep: Double {
        self == .highWristTemperature ? 0.1 : 1
    }

    /// Decimal places a threshold of this kind carries (see `thresholdStep`).
    var thresholdDecimals: Int {
        self == .highWristTemperature ? 1 : 0
    }

    /// Every value the picker offers, built by index rather than by striding
    /// so a 0.1 step never drifts into 37.300000000000004.
    var thresholdValues: [Double] {
        let count = Int(((thresholdRange.upperBound - thresholdRange.lowerBound) / thresholdStep).rounded())
        return (0...count).map { quantizedThreshold(thresholdRange.lowerBound + Double($0) * thresholdStep) }
    }

    /// The value snapped to the picker's step and clamped into its range, so a
    /// stored override always matches one of `thresholdValues` exactly.
    func quantizedThreshold(_ value: Double) -> Double {
        let clamped = min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
        let scale = pow(10, Double(thresholdDecimals))
        return (clamped * scale).rounded() / scale
    }

    /// Unit shown next to a threshold value. `"bpm"` and `"br/min"` are
    /// localization keys in the app catalog; `"%"` and `"°C"` are symbol-only
    /// and need no translation. Wrist temperature thresholds are stored in °C
    /// and converted for display when the user prefers Fahrenheit.
    var unitLabelKey: String {
        switch self {
        case .lowHeartRate, .highHeartRate:
            return "bpm"
        case .lowBloodOxygen:
            return "%"
        case .highRespiratoryRate:
            return "br/min"
        case .highWristTemperature:
            return "°C"
        }
    }

    var isAbove: Bool {
        switch self {
        case .highHeartRate, .highRespiratoryRate, .highWristTemperature:
            return true
        case .lowHeartRate, .lowBloodOxygen:
            return false
        }
    }

    /// Apple's high heart rate notification only counts readings taken while
    /// inactive, which we approximate by dropping samples inside a workout.
    var excludesWorkouts: Bool {
        self == .highHeartRate
    }
}

/// A stretch of consecutive past-threshold readings, mirroring Apple's health
/// notifications. Persisted with the summary so the home card can flag today's
/// episode without waiting for the intraday samples to load.
struct MetricWarningEvent: Codable, Equatable, Hashable, Sendable {
    var kind: MetricWarningKind
    var startDate: Date
    var endDate: Date
    var extremeValue: Double
    var sampleCount: Int
    /// The threshold this episode was detected against, so the card and detail
    /// copy read the user's number even after they change it.
    var threshold: Double

    init(
        kind: MetricWarningKind,
        startDate: Date,
        endDate: Date,
        extremeValue: Double,
        sampleCount: Int,
        /// `nil` falls back to the kind's default (legacy snapshots, tests).
        threshold: Double? = nil
    ) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.extremeValue = extremeValue
        self.sampleCount = sampleCount
        self.threshold = threshold ?? kind.defaultThreshold
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(MetricWarningKind.self, forKey: .kind)
        self.init(
            kind: kind,
            startDate: try container.decode(Date.self, forKey: .startDate),
            endDate: try container.decode(Date.self, forKey: .endDate),
            extremeValue: try container.decode(Double.self, forKey: .extremeValue),
            sampleCount: try container.decode(Int.self, forKey: .sampleCount),
            // Snapshots written before custom thresholds carry no value.
            threshold: try container.decodeIfPresent(Double.self, forKey: .threshold)
        )
    }
}

/// Shared detection rules for the metric threshold warnings.
enum MetricThresholdWarning {
    /// Past-threshold readings further apart than this belong to separate
    /// episodes, so two isolated events hours apart never merge into one
    /// near-full-day window.
    static let episodeMaxGap: TimeInterval = 30 * 60

    /// Breathing room around the episode in the detail chart, so a single
    /// sample still renders as a readable window.
    static let chartWindowPadding: TimeInterval = 10 * 60

    /// Recovery grace after a logged workout: heart rate stays elevated while
    /// cooling down, so readings this soon after the workout's end are still
    /// treated as in-workout by kinds that exclude workouts.
    static let workoutRecoveryGrace: TimeInterval = 30 * 60

    /// The interval a workout masks for workout-excluding kinds — the workout
    /// itself plus the recovery grace after it.
    static func workoutExclusionInterval(start: Date, end: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, end).addingTimeInterval(workoutRecoveryGrace))
    }

    /// The warnings that apply to a metric, in display order.
    static func kinds(for metric: HealthMetricKind) -> [MetricWarningKind] {
        MetricWarningKind.allCases.filter { $0.metric == metric }
    }

    /// Earliest episode of the day, or `nil` when nothing crossed the threshold.
    static func detect(
        _ kind: MetricWarningKind,
        in series: HealthTrendSeries,
        on day: Date,
        calendar: Calendar = .bodyGregorian,
        threshold: Double,
        excluding intervals: [DateInterval] = []
    ) -> MetricWarningEvent? {
        detect(
            kind,
            inSamples: series.points(on: day, calendar: calendar).points,
            threshold: threshold,
            excluding: intervals
        )
    }

    /// Same detection over already day-sliced samples, for callers that fetched
    /// the past-threshold readings directly.
    static func detect(
        _ kind: MetricWarningKind,
        inSamples points: [HealthTrendDataPoint],
        threshold: Double,
        excluding intervals: [DateInterval] = []
    ) -> MetricWarningEvent? {
        // Sources can write the same reading twice (phone + watch), which would
        // otherwise inflate `sampleCount`.
        var seen = Set<Pair>()
        let flagged = points
            .filter { point in
                guard point.value.isFinite else {
                    return false
                }
                guard kind.isAbove ? point.value > threshold : point.value < threshold else {
                    return false
                }
                guard !intervals.contains(where: { $0.contains(point.date) }) else {
                    return false
                }
                return seen.insert(Pair(date: point.date, value: point.value)).inserted
            }
            .sorted { $0.date < $1.date }

        guard let first = flagged.first else {
            return nil
        }

        var episode = [first]
        for point in flagged.dropFirst() {
            guard let previous = episode.last,
                  point.date.timeIntervalSince(previous.date) <= episodeMaxGap else {
                break
            }
            episode.append(point)
        }

        let values = episode.map(\.value)
        return MetricWarningEvent(
            kind: kind,
            startDate: episode[0].date,
            endDate: episode[episode.count - 1].date,
            extremeValue: (kind.isAbove ? values.max() : values.min()) ?? first.value,
            sampleCount: episode.count,
            threshold: threshold
        )
    }

    /// Padded window around the episode, clamped to the day it happened on. Always
    /// non-degenerate so the chart has an x-domain to scale against.
    static func chartWindow(
        for event: MetricWarningEvent,
        padding: TimeInterval = chartWindowPadding,
        clampedTo dayInterval: DateInterval
    ) -> DateInterval {
        let start = max(event.startDate.addingTimeInterval(-padding), dayInterval.start)
        let end = min(event.endDate.addingTimeInterval(padding), dayInterval.end)

        guard start < end else {
            return dayInterval
        }

        return DateInterval(start: start, end: end)
    }

    /// Roughly how many dots the warning chart's plot width fits without the
    /// rings piling on top of each other.
    static let chartPointMarkLimit = 36

    /// The readings the chart draws a dot on. A watch writes heart rate every
    /// few seconds, so an episode's window can hold hundreds of readings and
    /// their rings stack into a solid band. The line still runs through every
    /// reading; the dots are thinned to evenly spaced slots across the window,
    /// and a slot holding a past-threshold reading keeps that one, so the
    /// readings the warning is about are never the ones summarized away.
    static func chartPointMarks(
        for points: [HealthTrendDataPoint],
        in window: DateInterval,
        of event: MetricWarningEvent,
        limit: Int = chartPointMarkLimit
    ) -> [HealthTrendDataPoint] {
        guard points.count > limit, limit > 0, window.duration > 0 else {
            return points
        }

        let slotWidth = window.duration / Double(limit)
        var marks: [HealthTrendDataPoint] = []
        marks.reserveCapacity(limit + 1)

        var openSlot: Int?
        var candidate: HealthTrendDataPoint?

        for point in points.sorted(by: { $0.date < $1.date }) {
            let elapsed = point.date.timeIntervalSince(window.start)
            let slot = min(limit - 1, max(0, Int(elapsed / slotWidth)))

            guard slot == openSlot, let current = candidate else {
                if let candidate {
                    marks.append(candidate)
                }
                openSlot = slot
                candidate = point
                continue
            }

            let center = window.start.addingTimeInterval((Double(slot) + 0.5) * slotWidth)
            candidate = preferredMark(current, over: point, slotCenter: center, of: event)
        }

        if let candidate {
            marks.append(candidate)
        }

        return marks
    }

    /// Which of two readings in the same slot gets the dot: a past-threshold
    /// reading over an ordinary one, the more extreme of two past-threshold
    /// ones, and otherwise the reading nearest the slot's center, so the dots
    /// stay evenly spaced along the line.
    private static func preferredMark(
        _ lhs: HealthTrendDataPoint,
        over rhs: HealthTrendDataPoint,
        slotCenter: Date,
        of event: MetricWarningEvent
    ) -> HealthTrendDataPoint {
        let isPastThreshold: (Double) -> Bool = { value in
            event.kind.isAbove ? value > event.threshold : value < event.threshold
        }
        let lhsIsPastThreshold = isPastThreshold(lhs.value)

        guard lhsIsPastThreshold == isPastThreshold(rhs.value) else {
            return lhsIsPastThreshold ? lhs : rhs
        }

        if lhsIsPastThreshold {
            if event.kind.isAbove {
                return lhs.value >= rhs.value ? lhs : rhs
            }
            return lhs.value <= rhs.value ? lhs : rhs
        }

        let lhsDistance = abs(lhs.date.timeIntervalSince(slotCenter))
        return lhsDistance <= abs(rhs.date.timeIntervalSince(slotCenter)) ? lhs : rhs
    }

    private struct Pair: Hashable {
        var date: Date
        var value: Double
    }
}
