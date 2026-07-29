//
//  ReadinessComputeSupport.swift
//  Body
//
//  Pure wake-cycle statics behind the iPhone's morning-freeze + same-day
//  activity drain, extracted out of `HealthKitWorkoutStore` (which now
//  delegates to these) so the watch's on-device compute (Phase 4) can reuse
//  the identical math instead of hand-forking it — the divergence that broke
//  the June 2026 standalone-compute attempt.
//

import Foundation

enum ReadinessComputeSupport {
    /// A wake (sleep-end) older than this is treated as stale/missing — the drain
    /// window falls back to midnight so a days-old sleep summary can't span days.
    static let maxWakeCycleSeconds: TimeInterval = 24 * 3_600

    /// Wake time valid for freezing the scoring day's morning record: the sleep
    /// session must have ended on the scoring day and not in the future. Otherwise
    /// `nil`, so the freeze uses its 10:00-local fallback — a stale multi-day-old
    /// sleep end must not anchor the freeze before that fallback.
    static func freezeWakeTime(
        sleepEnd: Date?,
        scoringDay: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let sleepEnd, sleepEnd <= now, calendar.isDate(sleepEnd, inSameDayAs: scoringDay) else {
            return nil
        }
        return sleepEnd
    }

    /// Start of the current wake cycle for the activity-drain window: the most
    /// recent sleep end when it is recent enough (so an evening workout's drain
    /// survives past midnight), otherwise midnight — so a stale multi-day-old
    /// sleep end can't make the window span days.
    static func wakeCycleStart(now: Date, sleepEnd: Date?, calendar: Calendar) -> Date {
        if let sleepEnd, sleepEnd <= now, now.timeIntervalSince(sleepEnd) <= maxWakeCycleSeconds {
            return sleepEnd
        }
        return calendar.startOfDay(for: now)
    }

    /// Workouts done since the start of the current wake cycle, up to `now` —
    /// the pure window filter behind `HealthKitWorkoutStore.currentWakeCycleWorkouts`
    /// (which keeps its month-cache read and hands the flattened workouts here)
    /// and, from Phase 4, the watch's own delta-fetched workouts.
    static func wakeCycleWorkouts(
        from workouts: [WorkoutSummary],
        now: Date,
        sleepEnd: Date?,
        calendar: Calendar
    ) -> [WorkoutSummary] {
        let cycleStart = wakeCycleStart(now: now, sleepEnd: sleepEnd, calendar: calendar)
        return workouts.filter { $0.startDate >= cycleStart && $0.startDate <= now }
    }
}
