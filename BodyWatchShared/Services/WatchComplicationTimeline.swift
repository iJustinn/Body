//
//  WatchComplicationTimeline.swift
//  BodyWatchShared
//
//  Builds the widget timeline entries for a cached snapshot. Kept out of
//  `BodyWatchWidgetExtension` (which isn't compiled into any test target) so
//  the entry-scheduling logic is testable; the provider only maps the result
//  onto `WatchMetricEntry`/`Timeline`.
//

import Foundation

enum WatchComplicationTimeline {
    /// Fallback reload cadence when nothing pushes a real update in the
    /// meantime. 12 reloads/day/kind, down from the prior 30-minute cadence;
    /// the larger battery saving is the removed per-push
    /// `reloadAllTimelines()` (H-10/S-09).
    static let refreshInterval: TimeInterval = 2 * 60 * 60

    /// Entries at `now` and at the next local midnight (snapshot re-sanitized
    /// for that instant so a sleep night that ends at midnight clears, and
    /// `weeklyRewound` consumers shift, without an app launch), plus one at
    /// the instant the Stress complication's reading ages out
    /// (`WatchStressTimeline.latestReading(asOf:)`), so it blanks on time, and
    /// the fallback reload date. With a `slidingWindow` (the intraday chart
    /// complications' window length), also one at every local half hour from
    /// `now` through `now + slidingWindow`: the chart ends at its entry's date,
    /// so it slides on a slot at a time, until everything it held has slid
    /// out. Dates shared between the rules get a single entry. Real refreshes
    /// still come from the app's `reloadTimelines` after a persisted change.
    static func entries(
        snapshot: WatchMetricsSnapshot,
        now: Date,
        slidingWindow: TimeInterval? = nil,
        calendar: Calendar = .current
    ) -> (entries: [(date: Date, snapshot: WatchMetricsSnapshot)], reloadAfter: Date) {
        let todayStart = calendar.startOfDay(for: now)
        // Midnight via `calendar.date(byAdding:)` also advances the trend
        // window by one day, so a reading exactly at the 365-day edge clears
        // one day early in that entry; harmless.
        let midnight = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(24 * 60 * 60)
        let stressExpiry = snapshot.stressTimeline?.latestScoredWindow
            .map { $0.end.addingTimeInterval(WatchStressTimeline.readingMaxAge) }

        var dates: Set<Date> = [midnight]
        if let stressExpiry {
            dates.insert(stressExpiry)
        }
        if let slidingWindow {
            // Each step is the current slot's end, the charts' own half hour
            // alignment (`WatchIntradayWindow.endingAt`), and always lies
            // past the date it started from.
            let last = now.addingTimeInterval(slidingWindow)
            var boundary = WatchIntradayWindow.endingAt(now, calendar: calendar).plotEnd
            while boundary <= last {
                dates.insert(boundary)
                boundary = WatchIntradayWindow.endingAt(boundary, calendar: calendar).plotEnd
            }
        }
        var entries: [(date: Date, snapshot: WatchMetricsSnapshot)] = [(now, snapshot.sanitized(asOf: now))]
        for date in dates.sorted() where date > now {
            entries.append((date, snapshot.sanitized(asOf: date)))
        }
        return (entries, now.addingTimeInterval(refreshInterval))
    }

    /// The metric the exercise week complication charts. Falls back to the
    /// legacy `exerciseMinutes` metric when a stale/older snapshot doesn't
    /// carry `workoutMinutes` yet (version skew across a phone/watch pair).
    static func exerciseWeekMetric(in snapshot: WatchMetricsSnapshot) -> WatchMetric? {
        snapshot.metric(forKind: WatchMetricKindKey.workoutMinutes)
            ?? snapshot.metric(forKind: WatchMetricKindKey.exerciseMinutes)
    }
}
