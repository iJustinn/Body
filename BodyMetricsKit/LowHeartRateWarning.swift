//
//  LowHeartRateWarning.swift
//  Body
//

import Foundation

/// A stretch of consecutive sub-threshold heart rate readings, mirroring Apple's
/// "Low Heart Rate" notification. Persisted with the summary so the home card can
/// flag today's episode without waiting for the intraday samples to load.
struct LowHeartRateEvent: Codable, Equatable, Hashable, Sendable {
    var startDate: Date
    var endDate: Date
    var minimumBPM: Double
    var sampleCount: Int
}

/// Shared detection rules for the low heart rate warning. The threshold lives here
/// so the HealthKit predicate, the chart rule and the copy all read the same number.
enum LowHeartRateWarning {
    static let thresholdBPM: Double = 40

    /// Sub-threshold readings further apart than this belong to separate episodes,
    /// so two isolated lows hours apart never merge into one near-full-day window.
    static let episodeMaxGap: TimeInterval = 30 * 60

    /// Breathing room around the episode in the detail chart, so a single low
    /// sample still renders as a readable window.
    static let chartWindowPadding: TimeInterval = 10 * 60

    /// Earliest episode of the day, or `nil` when nothing fell below `threshold`.
    static func detect(
        in series: HealthTrendSeries,
        on day: Date,
        calendar: Calendar = .bodyGregorian,
        threshold: Double = thresholdBPM
    ) -> LowHeartRateEvent? {
        detect(inSamples: series.points(on: day, calendar: calendar).points, threshold: threshold)
    }

    /// Same detection over already day-sliced samples, for callers that fetched the
    /// sub-threshold readings directly.
    static func detect(
        inSamples points: [HealthTrendDataPoint],
        threshold: Double = thresholdBPM
    ) -> LowHeartRateEvent? {
        let lows = points
            .filter { $0.value.isFinite && $0.value < threshold }
            .sorted { $0.date < $1.date }

        guard let first = lows.first else {
            return nil
        }

        var episode = [first]
        for point in lows.dropFirst() {
            guard let previous = episode.last,
                  point.date.timeIntervalSince(previous.date) <= episodeMaxGap else {
                break
            }
            episode.append(point)
        }

        return LowHeartRateEvent(
            startDate: episode[0].date,
            endDate: episode[episode.count - 1].date,
            minimumBPM: episode.map(\.value).min() ?? first.value,
            sampleCount: episode.count
        )
    }

    /// Padded window around the episode, clamped to the day it happened on. Always
    /// non-degenerate so the chart has an x-domain to scale against.
    static func chartWindow(
        for event: LowHeartRateEvent,
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
}
