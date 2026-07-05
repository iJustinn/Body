//
//  HealthKitFetchEngine+TrainingLoad.swift
//  Body
//

import Foundation
import HealthKit

// Training-load summary + trend series, backed by a shared 180-day workout
// fetch memoized on the engine actor (`sharedTrainingLoadWorkoutsTask`).
// The memo is invalidated whenever the trend anchor date is (re)set.
extension HealthKitFetchEngine {
    func trainingLoadWorkoutsWindow(calendar: Calendar) -> TrainingLoadWorkoutsWindow {
        let anchor = anchorDate ?? Date()
        let dayStart = calendar.startOfDay(for: anchor)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -Self.trainingLoadSummaryDayCount, to: dayStart)
            ?? dayStart.addingTimeInterval(-TimeInterval(Self.trainingLoadSummaryDayCount) * 86_400)
        return TrainingLoadWorkoutsWindow(start: start, end: dayEnd)
    }

    /// Fetches (or reuses an in-flight fetch of) the 180-day training-load
    /// workout window. Concurrent callers within the same refresh await the
    /// same `Task`; the memo is invalidated whenever the trend anchor date is
    /// (re)set on the engine.
    func sharedTrainingLoadWorkouts(
        window: TrainingLoadWorkoutsWindow
    ) async throws -> [WorkoutSummary] {
        if let task = sharedTrainingLoadWorkoutsTask,
           sharedTrainingLoadWorkoutsWindow == window {
            return try await task.value
        }

        let task = Task<[WorkoutSummary], Error> { [self] in
            let signpostState = BodyPerformanceSignposts.signposter.beginInterval("TrainingLoadWorkouts")
            defer { BodyPerformanceSignposts.signposter.endInterval("TrainingLoadWorkouts", signpostState) }
            return try await fetchWorkoutSummaries(
                startDate: window.start,
                endDate: window.end,
                includesHeartRateSamples: false,
                includesDetailMetrics: false
            )
        }
        sharedTrainingLoadWorkoutsTask = task
        sharedTrainingLoadWorkoutsWindow = window
        return try await task.value
    }

    func fetchTrainingLoadSummary(calendar: Calendar) async -> HealthMetricSummary? {
        let date = anchorDate ?? Date()
        let window = trainingLoadWorkoutsWindow(calendar: calendar)

        do {
            let workouts = try await sharedTrainingLoadWorkouts(window: window)
            return TrainingLoadCalculator.summary(
                on: date,
                from: workouts,
                startDate: window.start,
                calendar: calendar
            )
        } catch {
            return nil
        }
    }

    /// Returns `nil` when the underlying workout fetch throws (a query failure,
    /// not an empty history), so the assembly layer keeps the cached series
    /// instead of blanking training load.
    func fetchTrainingLoadSeries(calendar: Calendar) async -> HealthTrendSeries? {
        let end = anchorDate ?? Date()
        let window = trainingLoadWorkoutsWindow(calendar: calendar)

        do {
            let workouts = try await sharedTrainingLoadWorkouts(window: window)
            return TrainingLoadCalculator.dailySeries(
                from: workouts,
                startDate: window.start,
                endDate: end,
                calendar: calendar
            )
        } catch {
            Self.logTrendQueryFailure("trainingLoad", error: error)
            return nil
        }
    }
}
