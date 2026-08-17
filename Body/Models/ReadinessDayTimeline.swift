//
//  ReadinessDayTimeline.swift
//  Body
//

import Foundation

/// Derives the readiness detail page's intraday day-view line: a base morning
/// score, drained by the day's workouts (`ActivityReadinessImpact`), with each
/// workout's drain ramped linearly across its interval.
///
/// Today: the base is the live tile's score and the window is the **wake cycle**
/// (`ReadinessComputeSupport`), including a workout that ended before the
/// calendar day started (carried in as a drain applied from the first sample) —
/// matching `HealthDashboardSnapshot.draining`'s window exactly. Past days: the
/// base is the **frozen morning record** and the window is the calendar day. For
/// identical morning score + workout inputs the endpoint matches
/// `HealthDashboardSnapshot.draining` exactly (same cap, one-time total rounding,
/// sub-0.5 ignore rule, and display softening).
struct ReadinessDayTimeline: Equatable {
    /// One workout's share of the day's drain: the marginal contribution to the
    /// capped running total (in end-date order), so a session that lands after
    /// the `totalDrainCap` binds is attributed only what it actually moved.
    struct WorkoutImpact: Equatable, Identifiable {
        let id: UUID
        let workoutType: BodyWorkoutType
        let startDate: Date
        let endDate: Date
        let drainPoints: Double
        let sourceName: String

        var roundedDrainPoints: Int {
            Int(drainPoints.rounded())
        }
    }

    let morningScore: Int
    let impacts: [WorkoutImpact]
    let seriesEnd: Date

    /// The base score to drain for the day view: today prefers the live tile's
    /// undrained score (matching the hero/tile exactly); otherwise the frozen
    /// morning record, falling back to the trend point.
    static func morningScore(
        isToday: Bool,
        liveReadiness: ReadinessSummary?,
        recordedScore: Int?,
        trendValue: Double?
    ) -> Int? {
        if isToday, let score = liveReadiness?.score {
            return liveReadiness?.activityDrainMorningScore ?? score
        }
        if let recordedScore {
            return recordedScore
        }
        if let trendValue, trendValue.isFinite {
            return Int(trendValue.rounded())
        }
        return nil
    }

    static func make(
        morningScore: Int,
        workouts: [WorkoutSummary],
        dayInterval: DateInterval,
        now: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> ReadinessDayTimeline {
        // Drain magnitude comes from the whole workout (matching the live tile);
        // only the ramp window is clipped to the day.
        let clipped = workouts.compactMap { workout -> (interval: DateInterval, drain: Double, workout: WorkoutSummary)? in
            let workoutEndDate = workout.startDate.addingTimeInterval(workout.duration)
            guard workoutEndDate > workout.startDate else {
                return nil
            }

            // A wake-cycle workout that fully ended before today started (e.g. a
            // late wake yesterday) still drains the live tile — carry it in as a
            // zero-length impact at dayStart so the first sample already reflects it.
            if workoutEndDate <= dayInterval.start {
                let carryInInterval = DateInterval(start: dayInterval.start, end: dayInterval.start)
                return (carryInInterval, ActivityReadinessImpact.perWorkoutDrain(workout), workout)
            }

            guard let workoutInterval = DateInterval(start: workout.startDate, end: workoutEndDate)
                .clamped(to: dayInterval) else {
                return nil
            }

            return (workoutInterval, ActivityReadinessImpact.perWorkoutDrain(workout), workout)
        }
        .sorted { $0.interval.end < $1.interval.end }

        var impacts: [WorkoutImpact] = []
        var runningDrain = 0.0
        for entry in clipped {
            let cappedTotal = min(ActivityReadinessImpact.totalDrainCap, runningDrain + entry.drain)
            let marginalDrain = cappedTotal - runningDrain
            runningDrain = cappedTotal
            impacts.append(
                WorkoutImpact(
                    id: entry.workout.id,
                    workoutType: entry.workout.type,
                    startDate: entry.interval.start,
                    endDate: entry.interval.end,
                    drainPoints: marginalDrain,
                    sourceName: entry.workout.sourceName
                )
            )
        }

        // A sample exactly at next midnight belongs to the next day
        // (`HealthTrendSeries.points(on:)` filters `< nextDayStart`), so a past
        // day's series must end just inside the interval.
        let seriesEnd = min(now, dayInterval.end - 1)

        return ReadinessDayTimeline(
            morningScore: morningScore,
            impacts: impacts,
            seriesEnd: max(seriesEnd, dayInterval.start)
        )
    }

    /// Displayed readiness at a moment: the morning score minus every impact's
    /// drain scaled by how much of its workout has elapsed, mapped through the
    /// same softening/clamping as `HealthDashboardSnapshot.draining`.
    func displayedScore(at date: Date) -> Int {
        let totalDrain = impacts.reduce(0.0) { $0 + $1.drainPoints }
        guard totalDrain >= 0.5 else {
            return morningScore
        }

        let drain = impacts.reduce(0.0) { $0 + $1.drainPoints * completedFraction(of: $1, at: date) }
        let raw = morningScore - Int(drain.rounded())
        return min(morningScore, ActivityReadinessImpact.displayedScore(forRawScore: raw))
    }

    /// Synthetic intraday series for `BodyHealthMetricDayChart`: one sample every
    /// 15 minutes from the day start through `seriesEnd`, plus `seriesEnd` itself.
    /// Timestamps are unique — the chart's hourly averaging would double-weight
    /// duplicates.
    func sampledSeries(dayStart: Date? = nil) -> HealthTrendSeries {
        let start = dayStart ?? Calendar.bodyGregorian.startOfDay(for: seriesEnd)
        guard seriesEnd >= start else {
            return .empty
        }

        var sampleDates: [Date] = []
        var sampleDate = start
        while sampleDate < seriesEnd {
            sampleDates.append(sampleDate)
            sampleDate = sampleDate.addingTimeInterval(15 * 60)
        }
        sampleDates.append(seriesEnd)

        return HealthTrendSeries(
            points: sampleDates.map { date in
                HealthTrendDataPoint(date: date, value: Double(displayedScore(at: date)))
            }
        )
    }

    private func completedFraction(of impact: WorkoutImpact, at date: Date) -> Double {
        // Checked before the start-date guard so a zero-length carry-in impact
        // (startDate == endDate == dayStart) counts as complete at exactly dayStart.
        guard date < impact.endDate else {
            return 1
        }
        guard date > impact.startDate else {
            return 0
        }

        let duration = impact.endDate.timeIntervalSince(impact.startDate)
        guard duration > 0 else {
            return 1
        }

        return date.timeIntervalSince(impact.startDate) / duration
    }
}
