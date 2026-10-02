//
//  WatchStressTimelineBuilder.swift
//  BodyWatchSnapshotKit
//
//  Builds the Stress page's "Last 8 hours" chart (`WatchStressTimeline`) from
//  a dashboard snapshot that still carries the intraday day samples. The
//  phone's publisher and the watch's compute both call it, so the chart the
//  watch shows is the same function of the same inputs on either device, and
//  the same windows the iPhone's Day View draws.
//

import Foundation

enum WatchStressTimelineBuilder {
    /// How far back the timeline reaches. The page draws the last 8 hours
    /// before the current half hour slot, so it never looks further back than
    /// 8h30m; the extra half hour is slack.
    static let span: TimeInterval = 9 * 60 * 60

    /// The Stress windows overlapping `[now - span, now]` and the sleep and
    /// workout shading behind them, or nil when no window is scored or masked
    /// as activity (nothing to draw).
    ///
    /// One `stressWindows(forDays:)` call scores the one or two days the span
    /// touches against the same baselines `recalculatingStress` uses.
    /// `workouts` is the activity mask for every day that scan reads (the
    /// phone's whole stress window, the watch's fetched delta), not just the
    /// span's: each scanned day's quiet heart rate feeds today's baseline, and
    /// an unmasked workout on an older day would move it.
    ///
    /// `computedAt` is the timeline's own provenance (`WatchStressTimeline.computedAt`).
    static func make(
        dashboard: HealthDashboardSnapshot,
        workouts: [WorkoutSummary],
        now: Date,
        calendar: Calendar,
        computedAt: Date?
    ) -> WatchStressTimeline? {
        let spanStart = now.addingTimeInterval(-span)
        var days = [calendar.startOfDay(for: spanStart)]
        let today = calendar.startOfDay(for: now)
        if today != days[0] {
            days.append(today)
        }

        let windowsByDay = dashboard.stressWindows(forDays: days, workouts: workouts, calendar: calendar, now: now)
        let windows = days
            .flatMap { windowsByDay[$0] ?? [] }
            .filter { $0.interval.end > spanStart && $0.interval.start < now }
        guard let start = windows.first?.interval.start else { return nil }

        var slots: [Int?] = []
        for window in windows {
            // Windows step 15 minutes from each local midnight, and every day
            // is a whole number of steps (a DST day has 92 or 100), so the grid
            // runs on unbroken across midnight and a window's slot is its
            // distance from `start` in steps. The rounding only snaps floating
            // point residue onto that grid.
            let index = Int((window.interval.start.timeIntervalSince(start) / WatchStressTimeline.slotLength).rounded())
            guard index >= 0 else { continue }
            if index >= slots.count {
                slots.append(contentsOf: Array(repeating: nil, count: index - slots.count + 1))
            }
            switch window.state {
            case let .scored(score, _):
                slots[index] = Int(score.rounded())
            case .activity:
                slots[index] = WatchStressTimeline.activityMarker
            case .unscored:
                slots[index] = nil
            }
        }
        // A trailing gap draws nothing, so it isn't shipped.
        while let last = slots.last, last == nil {
            slots.removeLast()
        }
        guard slots.contains(where: { $0 != nil }) else { return nil }

        return WatchStressTimeline(
            start: start,
            end: now,
            slots: slots,
            context: contextBands(
                dashboard: dashboard,
                workouts: workouts,
                days: days,
                span: DateInterval(start: spanStart, end: now),
                calendar: calendar
            ),
            computedAt: computedAt
        )
    }

    /// The shading behind the windows, the same context the iPhone's Stress
    /// Day View draws: each day's main sleep session and naps (from the sleep
    /// history, or today's live summary), and each workout to its real end,
    /// clipped to the span and sorted by start.
    private static func contextBands(
        dashboard: HealthDashboardSnapshot,
        workouts: [WorkoutSummary],
        days: [Date],
        span: DateInterval,
        calendar: Calendar
    ) -> [WatchStressContextBand] {
        var bands: [WatchStressContextBand] = []
        func append(_ kind: String, start: Date, end: Date, workoutType: String? = nil) {
            let clippedStart = max(start, span.start)
            let clippedEnd = min(end, span.end)
            guard clippedEnd > clippedStart else { return }
            let band = WatchStressContextBand(kind: kind, start: clippedStart, end: clippedEnd, workoutType: workoutType)
            // Two days can resolve the same night (today's live summary and
            // its history entry), which would shade it twice.
            if !bands.contains(band) {
                bands.append(band)
            }
        }

        for day in days {
            let stages = dashboard.trends.sleepHistory.summary(
                on: day,
                currentDaySummary: dashboard.summary.sleep,
                today: span.end,
                calendar: calendar
            )?.stageSnapshot
            if let session = stages?.mainSession.dateInterval {
                append(WatchStressContextBand.sleepKind, start: session.start, end: session.end)
            }
            for nap in stages?.napSessions ?? [] {
                if let interval = nap.dateInterval {
                    append(WatchStressContextBand.napKind, start: interval.start, end: interval.end)
                }
            }
        }
        for workout in workouts {
            append(
                WatchStressContextBand.workoutKind,
                start: workout.startDate,
                end: workout.effectiveEndDate,
                workoutType: workout.type.rawValue
            )
        }
        return bands.sorted { $0.start < $1.start }
    }
}
