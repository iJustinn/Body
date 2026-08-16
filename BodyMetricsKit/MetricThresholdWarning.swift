//
//  MetricThresholdWarning.swift
//  Body
//

import Foundation

/// The Apple-style threshold warnings Body detects: a reading past a limit
/// today. The default limit and its editable range live here so the HealthKit
/// predicate, the chart rule and the copy all read the same numbers.
enum MetricWarningKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case lowHeartRate
    case highHeartRate
    case lowBloodOxygen

    var id: String {
        rawValue
    }

    var metric: HealthMetricKind {
        switch self {
        case .lowHeartRate, .highHeartRate:
            return .heartRate
        case .lowBloodOxygen:
            return .oxygenSaturation
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
        }
    }

    /// Bounds of the Settings wheel picker for a custom threshold.
    var thresholdRange: ClosedRange<Int> {
        switch self {
        case .lowHeartRate:
            return 30...60
        case .highHeartRate:
            return 100...200
        case .lowBloodOxygen:
            return 80...95
        }
    }

    var thresholdStep: Int {
        1
    }

    /// Unit shown next to a threshold value. `"bpm"` is a localization key in the
    /// app catalog; `"%"` is symbol-only and needs no translation.
    var unitLabelKey: String {
        switch self {
        case .lowHeartRate, .highHeartRate:
            return "bpm"
        case .lowBloodOxygen:
            return "%"
        }
    }

    var isAbove: Bool {
        self == .highHeartRate
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

    private struct Pair: Hashable {
        var date: Date
        var value: Double
    }
}
