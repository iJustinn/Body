//
//  HealthKitFetchEngine+HeartbeatSeries.swift
//  Body
//
//  Beat-to-beat RMSSD for the Stress metric. Apple exposes no RMSSD quantity —
//  only SDNN — so each `HKHeartbeatSeriesSample` has to be streamed beat by beat
//  and reduced through `StressRMSSD` (shared with the calculator's tests, so the
//  math has exactly one implementation). Deliberately kept OFF the critical
//  refresh path: it is a fan-out of streaming queries and the refresh deadline
//  must never wait on it.
//

import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Newest-first cap on the series scan. A cap hit must starve the OLDEST
    /// data, never the most recent day, so the sample query sorts descending.
    nonisolated static let heartbeatSeriesFetchLimit = 120
    /// Per-series ceiling on the beat stream, and the ceiling on the whole
    /// fan-out. A single wedged series must not hold the fetch, and a wedged
    /// fetch must not outlive the refresh that started it.
    nonisolated static let heartbeatSeriesQueryTimeout: Duration = .seconds(5)
    nonisolated static let heartbeatFetchTimeout: Duration = .seconds(20)
    /// Concurrent beat streams. Each one is a live HealthKit query, so the
    /// fan-out is capped rather than run over the full 120 series at once.
    nonisolated static let heartbeatSeriesConcurrency = 4

    /// One RMSSD point per readable heartbeat series in the window, dated on the
    /// series' `endDate` so it lines up with the SDNN samples the calculator
    /// compares it against.
    ///
    /// Returns `nil` when the scan itself failed (device locked, store
    /// unavailable, XPC drop, unresolved source selection, cancellation, or the
    /// overall timeout) so the store keeps its cached RMSSD series instead of
    /// blanking it; a successful empty result — the simulator, or a user whose
    /// watch records no beat-to-beat data — returns `.empty` and lets Stress
    /// degrade to the SDNN path. Individual series that fail, time out, or
    /// carry too few clean intervals are dropped without failing the fetch.
    func fetchHeartbeatRMSSDSamples(startDate: Date, endDate: Date) async -> HealthTrendSeries? {
        // The RMSSD series is an HRV input, so it must be constrained to the
        // same source the HRV metric is pinned to — otherwise a pinned SDNN
        // source would be scored against another device's beat-to-beat data.
        if sourceSelectionUnresolved(for: .heartRateVariability) {
            return nil
        }

        let predicate = combinedPredicate(
            startDate: startDate,
            endDate: endDate,
            sourceKind: .heartRateVariability
        )

        // Query and deadline are unstructured tasks rather than task-group
        // children so the closures stay on this actor (same constraint as
        // `runActivityRingDayQuery`); cancellation is forwarded by hand.
        let fetchTask = Task { () -> HealthTrendSeries? in
            guard let samples = await self.fetchHeartbeatSeriesSamples(predicate: predicate) else {
                return nil
            }
            guard !samples.isEmpty else {
                return .empty
            }

            return await self.heartbeatRMSSDSeries(for: samples)
        }
        let deadlineTask = Task {
            try? await ContinuousClock().sleep(for: Self.heartbeatFetchTimeout)
            fetchTask.cancel()
        }

        let series = await withTaskCancellationHandler {
            await fetchTask.value
        } onCancel: {
            fetchTask.cancel()
        }
        deadlineTask.cancel()

        if series == nil {
            Self.logTrendQueryFailure("heartbeatSeriesRMSSD", error: nil)
        }

        return series
    }

    /// The series samples themselves — metadata only, no beats yet.
    private func fetchHeartbeatSeriesSamples(predicate: NSPredicate?) async -> [HKHeartbeatSeriesSample]? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        // Cancellation resumes with `nil`, like a query failure, so the store
        // keeps the cached series. See `runCancellableQuery`.
        return await runCancellableQuery(cancelledValue: nil) { resume in
            HKSampleQuery(
                sampleType: HKSeriesType.heartbeat(),
                predicate: predicate,
                limit: Self.heartbeatSeriesFetchLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    Self.logTrendQueryFailure(HKSeriesType.heartbeat().identifier, error: error)
                    resume(nil)
                    return
                }

                resume(samples.compactMap { $0 as? HKHeartbeatSeriesSample })
            }
        }
    }

    private func heartbeatRMSSDSeries(for samples: [HKHeartbeatSeriesSample]) async -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []

        await withTaskGroup(of: HealthTrendDataPoint?.self) { group in
            var next = 0
            while next < samples.count, next < Self.heartbeatSeriesConcurrency {
                let sample = samples[next]
                group.addTask { await self.heartbeatRMSSDPoint(for: sample) }
                next += 1
            }
            while let point = await group.next() {
                if let point {
                    points.append(point)
                }
                guard next < samples.count else {
                    continue
                }
                let sample = samples[next]
                group.addTask { await self.heartbeatRMSSDPoint(for: sample) }
                next += 1
            }
        }

        // The series query ran newest-first; the cached day-sample series is
        // ascending, so restore time order before handing it back.
        return HealthTrendSeries(points: points.sorted { $0.date < $1.date })
    }

    private func heartbeatRMSSDPoint(for sample: HKHeartbeatSeriesSample) async -> HealthTrendDataPoint? {
        let beatsTask = Task { () -> [StressRMSSD.RRInterval]? in
            await self.heartbeatIntervals(for: sample)
        }
        let deadlineTask = Task {
            try? await ContinuousClock().sleep(for: Self.heartbeatSeriesQueryTimeout)
            beatsTask.cancel()
        }

        let intervals = await withTaskCancellationHandler {
            await beatsTask.value
        } onCancel: {
            beatsTask.cancel()
        }
        deadlineTask.cancel()

        guard let intervals,
              let rmssd = StressRMSSD.rmssdMilliseconds(intervals: intervals),
              rmssd.isFinite else {
            return nil
        }

        return HealthTrendDataPoint(date: sample.endDate, value: rmssd)
    }

    /// Streams one series' beats into successive RR intervals. `nil` on a failed
    /// or cancelled/timed-out stream so the caller drops the series rather than
    /// computing RMSSD from a truncated prefix.
    private func heartbeatIntervals(for sample: HKHeartbeatSeriesSample) async -> [StressRMSSD.RRInterval]? {
        let beats = HeartbeatIntervalAccumulator()

        // A streaming query keeps calling back until `done`; the coordinator
        // resumes exactly once and drops the rest, and stops the query on
        // cancellation. See `runCancellableQuery`.
        return await runCancellableQuery(cancelledValue: nil) { resume in
            HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, timeSinceSeriesStart, precededByGap, done, error in
                guard error == nil else {
                    Self.logTrendQueryFailure("heartbeatSeriesBeats", error: error)
                    resume(nil)
                    return
                }

                beats.append(timeSinceSeriesStart: timeSinceSeriesStart, precededByGap: precededByGap)
                if done {
                    resume(beats.intervals)
                }
            }
        }
    }
}

/// Accumulates one `HKHeartbeatSeriesQuery`'s beats into RR intervals. HealthKit
/// delivers beats on its own queue, so every access is lock-guarded (which is
/// what makes `@unchecked Sendable` sound here, as in `CancellableQueryCoordinator`).
private final class HeartbeatIntervalAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var previousBeatTime: TimeInterval?
    private var collected: [StressRMSSD.RRInterval] = []

    /// The first beat has no predecessor, so it only seeds the cursor.
    /// `precededByGap` marks a beat that follows a detection gap: the interval
    /// ENDING on it spans the gap, so the flag rides on that interval and
    /// `StressRMSSD` drops the successive difference across it.
    func append(timeSinceSeriesStart: TimeInterval, precededByGap: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if let previousBeatTime {
            collected.append(
                StressRMSSD.RRInterval(
                    seconds: timeSinceSeriesStart - previousBeatTime,
                    precededByGap: precededByGap
                )
            )
        }
        previousBeatTime = timeSinceSeriesStart
    }

    var intervals: [StressRMSSD.RRInterval] {
        lock.lock()
        defer { lock.unlock() }

        return collected
    }
}
