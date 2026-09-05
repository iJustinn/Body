//
//  HealthKitFetchEngine+TrainingLoad.swift
//  Body
//

import Foundation
import HealthKit

// Training-load summary + trend series, backed by a shared workout fetch
// (`TrainingLoadCalculator.summaryWindowDayCount` days: the Year chart range
// plus the chronic-EWA warm-up) memoized on the engine actor
// (`sharedTrainingLoadWorkoutsTask`).
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

    /// Fetches (or reuses an in-flight fetch of) the training-load
    /// workout window. Concurrent callers within the same refresh await the
    /// same `Task`; the memo is invalidated whenever the trend anchor date is
    /// (re)set on the engine.
    ///
    /// Cancelling any one caller cancels the shared fetch for all of them. That
    /// is intended: the three callers belong to the same refresh generation, so
    /// a cancelled refresh should stop the query rather than leave it running
    /// for siblings that are being cancelled alongside it.
    func sharedTrainingLoadWorkouts(
        window: TrainingLoadWorkoutsWindow
    ) async throws -> [WorkoutSummary] {
        if let task = sharedTrainingLoadWorkoutsTask,
           sharedTrainingLoadWorkoutsWindow == window {
            return try await awaitSharedTrainingLoadWorkouts(task, window: window)
        }

        let task = Task<[WorkoutSummary], Error> { [self] in
            let signpostState = BodyPerformanceSignposts.signposter.beginInterval("TrainingLoadWorkouts")
            defer { BodyPerformanceSignposts.signposter.endInterval("TrainingLoadWorkouts", signpostState) }
            return try await fetchWorkoutSummaries(
                startDate: window.start,
                endDate: window.end,
                includesHeartRateSamples: false,
                includesDetailMetrics: false,
                requiresValidatedEffort: true
            )
        }
        sharedTrainingLoadWorkoutsTask = task
        sharedTrainingLoadWorkoutsWindow = window
        return try await awaitSharedTrainingLoadWorkouts(task, window: window)
    }

    /// Shared by both await sites above: propagates the caller's cancellation to
    /// the memoized task, and drops the memo when it throws so a failure isn't
    /// replayed to every later caller in this refresh.
    private func awaitSharedTrainingLoadWorkouts(
        _ task: Task<[WorkoutSummary], Error>,
        window: TrainingLoadWorkoutsWindow
    ) async throws -> [WorkoutSummary] {
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            // Only if the memo is still this fetch: an anchor change may have
            // replaced it while we were suspended, and that entry is valid.
            if sharedTrainingLoadWorkoutsTask == task, sharedTrainingLoadWorkoutsWindow == window {
                sharedTrainingLoadWorkoutsTask = nil
                sharedTrainingLoadWorkoutsWindow = nil
            }
            throw error
        }
    }

    func fetchTrainingLoadSummary(calendar: Calendar) async -> QueryOutcome<HealthMetricSummary> {
        let date = anchorDate ?? Date()
        let window = trainingLoadWorkoutsWindow(calendar: calendar)

        do {
            let workouts = try await sharedTrainingLoadWorkouts(window: window)
            return .success(
                TrainingLoadCalculator.summary(
                    on: date,
                    from: workouts,
                    startDate: window.start,
                    calendar: calendar
                )
            )
        } catch {
            Self.logTrendQueryFailure("trainingLoad", error: error)
            return .failure
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

    /// Dense day-indexed Training Load loads (408 slots) for the phone→watch
    /// compute seed (on-watch realtime compute, Phase 3): reuses the SAME
    /// memoized `sharedTrainingLoadWorkouts` window `fetchTrainingLoadSummary`/
    /// `fetchTrainingLoadSeries` already populate this refresh, so calling
    /// this alongside them (before the anchor date is cleared) never triggers
    /// a second workout fetch. `nil` on a query failure — same keep-stale
    /// convention as `fetchTrainingLoadSeries` — so the caller preserves its
    /// previously-cached seed instead of publishing a blanked one.
    func trainingLoadDailyLoadSeed(calendar: Calendar) async -> (startDay: Date, loads: [Double])? {
        let end = anchorDate ?? Date()
        let window = trainingLoadWorkoutsWindow(calendar: calendar)

        do {
            let workouts = try await sharedTrainingLoadWorkouts(window: window)
            return TrainingLoadCalculator.dailyLoadValues(
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
