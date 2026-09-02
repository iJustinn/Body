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
    /// `weeklyRewound` consumers shift, without an app launch), plus the
    /// fallback reload date. Real refreshes still come from the app's
    /// `reloadTimelines` after a persisted change.
    static func entries(
        snapshot: WatchMetricsSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> (entries: [(date: Date, snapshot: WatchMetricsSnapshot)], reloadAfter: Date) {
        let todayStart = calendar.startOfDay(for: now)
        // Midnight via `calendar.date(byAdding:)` also advances the trend
        // window by one day, so a reading exactly at the 365-day edge clears
        // one day early in that entry; harmless.
        let midnight = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now.addingTimeInterval(24 * 60 * 60)

        var entries: [(date: Date, snapshot: WatchMetricsSnapshot)] = [(now, snapshot.sanitized(asOf: now))]
        if midnight > now {
            entries.append((midnight, snapshot.sanitized(asOf: midnight)))
        }
        return (entries, now.addingTimeInterval(refreshInterval))
    }
}
