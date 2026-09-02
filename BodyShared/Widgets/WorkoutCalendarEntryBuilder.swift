//
//  WorkoutCalendarEntryBuilder.swift
//  BodyShared
//
//  Builds the widget timeline entries for a cached workout month snapshot.
//  Kept out of `BodyWidgetExtension` (which isn't compiled into any test
//  target) so the entry-scheduling logic is testable; the provider only maps
//  the result onto `WorkoutCalendarEntry`/`Timeline`.
//

import Foundation

enum WorkoutCalendarEntryBuilder {
    /// Fallback reload cadence when nothing else refreshes the widget.
    static let refreshInterval: TimeInterval = 1_800

    /// An entry at `now` plus, when the month is still running, one at the next
    /// month start carrying an empty snapshot: `.after` is only an
    /// earliest-reload hint, so without that dated entry the widget could keep
    /// showing last month's calendar past the boundary.
    static func timeline(
        snapshot: WorkoutMonthSnapshot,
        isPro: Bool,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> (entries: [(date: Date, snapshot: WorkoutMonthSnapshot, isPro: Bool)], reloadAfter: Date) {
        var entries: [(date: Date, snapshot: WorkoutMonthSnapshot, isPro: Bool)] = [(now, snapshot, isPro)]
        if let nextMonthStart = calendar.dateInterval(of: .month, for: now)?.end {
            entries.append(
                (nextMonthStart, .makeEmpty(generatedAt: nextMonthStart, calendar: calendar), isPro)
            )
        }

        let nextRefresh = calendar.date(byAdding: .minute, value: 30, to: now)
            ?? now.addingTimeInterval(refreshInterval)
        return (entries, nextRefresh)
    }
}
