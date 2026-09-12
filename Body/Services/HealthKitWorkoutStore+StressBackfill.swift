//
//  HealthKitWorkoutStore+StressBackfill.swift
//  Body
//
//  Progressive Stress history walk, so the trend charts reach a year instead of
//  the ~34 days the intraday day-sample cache can score.
//
//  Every other metric reaches a year through one cheap daily
//  `HKStatisticsCollectionQuery`. Stress cannot: it scores 15-minute windows, so
//  it needs raw heart-rate samples, and a year of those is far too heavy for one
//  fetch. So the history is filled the same way the workout record baseline is
//  (`HealthKitWorkoutStore+Records.swift`): a one-time, resumable, cancellable
//  scan that runs only after a refresh has finished, never inside one, and
//  persists every chunk before starting the next.
//
//  Two things differ from the record scan, both forced by how Stress is scored:
//
//  1. The walk runs FORWARD, from the oldest day toward today. `robustBaseline`
//     only ever reads days dated strictly before the day being scored, so a
//     backward walk would hand every chunk a baseline with no history behind it
//     and score nothing at all.
//  2. Each chunk publishes the recorded days, BOTH stress series rebuilt from
//     them, and the walk marker in one snapshot write. `recordedStressDays` and
//     `trends.stress` are separate stored fields, so records alone never reach
//     the chart, and a marker that outran its records would leave a permanent
//     hole in the history.
//

import Foundation
import HealthKit

extension HealthKitWorkoutStore {
    /// 30 days per chunk: a year is roughly a dozen round-trips, and one chunk's
    /// raw heart-rate fetch (~30 × a day of samples) and its ~2 900 window scans
    /// stay comparable to the recompute a normal refresh already performs.
    private static let stressBackfillChunkDays = 30

    /// The input batch must settle before history scoring. Record and journal
    /// scans share admission at their unit boundaries; a retained record task
    /// (including an empty/failed baseline) is not a Stress data dependency.
    func scheduleStressBackfillIfNeeded() {
        guard stressBackfillTask == nil,
              pendingStressInputLoadTask == nil,
              mayStartQuietMaintenance,
              !healthTrends.stressBackfillComplete,
              !isClearingLocalCache,
              !isRefreshing,
              permissionSelection.includes(.heart),
              BodyDashboardFetchSelection.load().includes(.stress),
              authorizationState == .authorized else {
            return
        }

        let epoch = currentCacheEpoch
        stressBackfillTask = Task { [weak self] in
            await self?.runStressBackfill(capturedEpoch: epoch)
        }
    }

    /// Cancels the walk and waits for it to actually exit, so a caller about to
    /// wipe or re-scope the recorded days can be sure no chunk write is still
    /// queued behind it. The task clears its own handle on the way out.
    func cancelStressBackfill() async {
        guard let task = stressBackfillTask else { return }
        task.cancel()
        await task.value
    }

    /// Walks `stressBackfillScannedThrough` (or the horizon) forward in ~30-day
    /// chunks until it reaches the window the per-refresh recompute owns.
    private func runStressBackfill(capturedEpoch: Int) async {
        defer { stressBackfillTask = nil }

        let calendar = Calendar.bodyGregorian
        let capturedSignature = currentStressRecordContextSignature
        var earliestHeartRate: Date?
        while !healthTrends.stressBackfillComplete, !Task.isCancelled {
            let completed = await performQuietMaintenanceUnit(.stressHistory) { [self] _ in
                guard mayApplyStressBackfill(capturedEpoch: capturedEpoch, capturedSignature: capturedSignature) else { return false }
                if earliestHeartRate == nil { earliestHeartRate = await engine.earliestHeartRateSampleDate() }
                guard let earliestHeartRate, mayPublishQuietMaintenance else { return false }
                let scoreDay = calendar.startOfDay(for: Date())
                let floor = calendar.date(byAdding: .day, value: -HealthDashboardSnapshot.stressRecordedDayRetention,
                                          to: scoreDay) ?? scoreDay
                let horizon = max(calendar.startOfDay(for: earliestHeartRate), floor)
                let end = HealthDashboardSnapshot.stressComputedWindowStart(scoreDay: scoreDay, calendar: calendar)
                let cursor = max(healthTrends.stressBackfillScannedThrough.map { calendar.startOfDay(for: $0) } ?? horizon, horizon)
                let chunkEnd = min(calendar.date(byAdding: .day, value: Self.stressBackfillChunkDays, to: cursor) ?? end, end)
                let summaries: [StressDaySummary]
                if cursor < end {
                    guard let fetched = await stressBackfillChunkSummaries(from: cursor, to: chunkEnd, calendar: calendar) else { return false }
                    summaries = fetched
                } else { summaries = [] }
                guard mayApplyStressBackfill(capturedEpoch: capturedEpoch, capturedSignature: capturedSignature) else { return false }
                applyStressBackfillChunk(summaries: summaries, scannedThrough: chunkEnd,
                                         complete: chunkEnd >= end, calendar: calendar, persists: false)
                return await persistDashboardSnapshotDurably()
            }
            if !completed { return }
        }
    }

    /// Cancellation, the cache epoch, and the record context — a source or
    /// permission change mid-walk means the chunk was scored under inputs the
    /// records no longer describe, so it is discarded rather than published.
    private func mayApplyStressBackfill(capturedEpoch: Int, capturedSignature: String) -> Bool {
        mayPublishQuietMaintenance && !isRefreshing
            && Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: currentCacheEpoch)
            && currentStressRecordContextSignature == capturedSignature
    }

    /// Fetches one chunk's transient inputs and scores its days. `nil` on any
    /// query failure. Nothing here touches the shared ~32-day day-sample cache:
    /// a year of raw samples must never be persisted into it.
    private func stressBackfillChunkSummaries(
        from chunkStart: Date,
        to chunkEnd: Date,
        calendar: Calendar
    ) async -> [StressDaySummary]? {
        var samplesByKind: [HealthMetricKind: HealthTrendSeries] = [:]
        for kind in Self.stressIntradaySampleKinds
        where permissionSelection.includes(HealthKitFetchEngine.healthPermission(forMetric: kind)) {
            guard let samples = await engine.fetchIntradayDaySamples(
                for: kind,
                calendar: calendar,
                startDate: chunkStart,
                endDate: chunkEnd
            ) else {
                return nil
            }
            samplesByKind[kind] = samples
        }

        guard let sleepIntervalsByDay = await engine.fetchStressBackfillSleepIntervals(
            startDate: chunkStart,
            endDate: chunkEnd,
            calendar: calendar
        ) else {
            return nil
        }

        // A day early: a session that started before the chunk's first midnight
        // still masks that day's opening windows.
        var workouts: [WorkoutSummary] = []
        if permissionSelection.includes(.workouts) {
            let workoutStart = calendar.date(byAdding: .day, value: -1, to: chunkStart) ?? chunkStart
            do {
                workouts = try await engine.fetchWorkoutSummaries(
                    startDate: workoutStart,
                    endDate: chunkEnd,
                    includesHeartRateSamples: false,
                    includesDetailMetrics: false
                )
            } catch {
                return nil
            }
        }

        let inputs = StressDayInput.dayInputs(
            from: chunkStart,
            to: chunkEnd,
            heartRateSamples: samplesByKind[.heartRate]?.points ?? [],
            sdnnSamples: samplesByKind[.heartRateVariability]?.points ?? [],
            hourlySteps: samplesByKind[.steps]?.points ?? [],
            hourlyActiveEnergy: samplesByKind[.activeEnergy]?.points ?? [],
            workouts: workouts,
            sleepIntervalsByDay: sleepIntervalsByDay,
            calendar: calendar
        )
        guard !inputs.isEmpty else {
            return []
        }

        // The context reduction (sorting/scanning the recorded + fresh HR, HRV,
        // and RMSSD series) and the ~30-day `daySummary` scan are the actual CPU
        // cost of a chunk; both are pure functions over value types, so they run
        // detached instead of blocking the main actor the resumed fetch landed
        // on. Only value-typed state captured above (`inputs`, `healthSummary`,
        // `healthTrends`, `activityRingHistory`) crosses the hop — the caller
        // re-validates the epoch/signature/refresh guards on the main actor
        // before publishing whatever this returns.
        let now = Date()
        let snapshot = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        return await Task.detached(priority: .utility) {
            // Each day scanned once: the same analyses feed the quiet-HR medians
            // the context reduces and the summaries scored against it.
            let analyses = inputs.map { StressDayAnalysis(input: $0, calendar: calendar, now: now) }
            let context = snapshot.stressBackfillContext(chunkAnalyses: analyses, calendar: calendar)
            return analyses.map { analysis in
                analysis.summary(baselines: context.baselines(for: analysis.date))
            }
        }.value
    }
}

extension HealthKitFetchEngine {
    /// Start date of the oldest readable heart-rate sample, or nil when there is
    /// none (or the reads aren't authorized — HealthKit reports both as an empty
    /// result).
    ///
    /// A single ascending, limit-1 query, exactly like `earliestWorkoutStartDate`:
    /// the history walk needs a floor to start from, and walking back from today
    /// until a chunk comes up empty would either stop early on a gap or never
    /// stop at all. Deliberately unfiltered by source selection — this is only a
    /// floor, and a narrower one could hide readable history.
    func earliestHeartRateSampleDate() async -> Date? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        // Only the Stress history walk asks for this floor, so it always spends
        // the background budget.
        return await withBackgroundQueryPool {
            await runCancellableQuery(cancelledValue: Date?.none) { resume in
                HKSampleQuery(
                    sampleType: quantityType,
                    predicate: nil,
                    limit: 1,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
                ) { _, samples, _ in
                    resume(samples?.first?.startDate)
                }
            }
        }
    }
}
