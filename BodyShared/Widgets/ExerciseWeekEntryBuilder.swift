//
//  ExerciseWeekEntryBuilder.swift
//  BodyShared
//
//  Builds the seven rolling days of workout minutes behind the iPhone lock
//  screen widget, plus its weekday labels. Kept out of `BodyWidgetExtension`
//  (which isn't compiled into any test target) so the windowing logic is
//  testable; the provider only reads the App Group and wraps the result.
//

import Foundation

enum ExerciseWeekEntryBuilder {
    /// Seven points, oldest first, with today rightmost.
    static func points(
        current: WorkoutMonthSnapshot?,
        previous: WorkoutMonthSnapshot?,
        usePlaceholderWhenEmpty: Bool,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [HealthWidgetPoint] {
        let hasData = (current?.workoutCount ?? 0) > 0 || (previous?.workoutCount ?? 0) > 0
        if !hasData && usePlaceholderWhenEmpty {
            return placeholderPoints(now: now, calendar: calendar)
        }

        // Dense per-day points for the current + previous month (every
        // in-month day, including zero-duration ones) so re-windowing
        // below always finds a real (non-nil) point for a rest day
        // instead of padding it with nil.
        let allPoints = points(from: current, calendar: calendar)
            + points(from: previous, calendar: calendar)
        // Re-window at load time: the cache is only rewritten when the app
        // runs, so a cache from an earlier day must be re-aligned so the
        // rightmost bar is always today.
        return HealthWidgetPoint.rewindingWeek(allPoints, to: now, calendar: calendar)
    }

    /// One point per day in `snapshot`'s month, minutes of total workout
    /// duration (0 for days with no workouts).
    static func points(from snapshot: WorkoutMonthSnapshot?, calendar: Calendar) -> [HealthWidgetPoint] {
        guard let snapshot else { return [] }
        return snapshot.days.compactMap { day in
            guard let date = calendar.date(from: DateComponents(year: snapshot.year, month: snapshot.month, day: day.day)) else {
                return nil
            }
            return HealthWidgetPoint(date: date, value: day.totalDuration / 60)
        }
    }

    /// Sample week for the widget gallery preview, built locally (no App
    /// Group read, no HealthWidgetSnapshot dependency).
    static func placeholderPoints(now: Date, calendar: Calendar = .bodyGregorian) -> [HealthWidgetPoint] {
        let today = calendar.startOfDay(for: now)
        let sampleMinutes: [Double] = [30, 45, 0, 60, 25, 50, 40]
        return sampleMinutes.enumerated().map { offset, minutes in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
            return HealthWidgetPoint(date: date, value: minutes)
        }
    }

    /// Weekday letter for `date`, in the user's locale. Deliberately not
    /// `Calendar.bodyRotatedVeryShortWeekdaySymbols` (that rotates by
    /// `firstWeekday`, which is wrong for a rolling window that isn't a
    /// calendar week) and not locale-less `Calendar.bodyGregorian` symbols.
    /// Mirrors `WorkoutMonthSnapshot.swift`'s weekday-symbol pattern.
    static func weekdayLetter(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.isEmpty ? fallback : symbols
        let index = calendar.component(.weekday, from: date) - 1
        guard source.indices.contains(index) else { return "" }
        return source[index]
    }
}
