//
//  ReadinessDayTimeline.swift
//  Body
//

import Foundation

/// Derives the readiness detail page's intraday day-view line: the day's frozen
/// morning score, drained by that day's workouts (`ActivityReadinessImpact`),
/// with each workout's drain ramped linearly across its interval.
///
/// The window is the **calendar day** (like every other metric day view), while
/// the live tile drains over the **wake cycle** (`ReadinessComputeSupport`), so
/// today's endpoint typically — but not always — matches the tile: a post-midnight
/// pre-wake workout or a cross-midnight wake cycle can differ. For identical
/// morning score + workout inputs the endpoint matches
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
            guard workoutEndDate > workout.startDate,
                  let workoutInterval = DateInterval(start: workout.startDate, end: workoutEndDate)
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
        guard date > impact.startDate else {
            return 0
        }
        guard date < impact.endDate else {
            return 1
        }

        let duration = impact.endDate.timeIntervalSince(impact.startDate)
        guard duration > 0 else {
            return 1
        }

        return date.timeIntervalSince(impact.startDate) / duration
    }
}
