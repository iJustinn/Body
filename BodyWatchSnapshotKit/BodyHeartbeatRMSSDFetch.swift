//
//  BodyHeartbeatRMSSDFetch.swift
//  BodyWatchSnapshotKit
//
//  RMSSD for the Stress metric, shared by Body and BodyWatch. On iOS and
//  watchOS 27 Apple writes it as its own quantity (`heartRateVariabilityRMSSD`,
//  the "Recovery HRV" of Apple Watch Series 12 and Ultra 4), which is one
//  ordinary sample query. Older watches write none, so each
//  `HKHeartbeatSeriesSample` is streamed beat by beat and reduced through
//  `StressRMSSD` (shared with the calculator's tests, so the math has exactly
//  one implementation) instead.
//
//  The scan moved here from the iOS `HealthKitFetchEngine+HeartbeatSeries.swift`
//  so the watch's Stress compute runs literally the same code. It is a fan-out
//  of streaming queries, so each platform brings its own `Limits`, and the
//  phone admits every query through its HealthKit query budget.
//

import Foundation
import HealthKit

enum BodyHeartbeatRMSSDFetch {
    /// Bounds on the beat-to-beat scan.
    struct Limits: Sendable {
        /// Newest-first cap on the series scanned. A cap hit must starve the
        /// OLDEST data, never the most recent day, so the series query sorts
        /// descending.
        let seriesLimit: Int
        /// Concurrent beat streams. Each one is a live HealthKit query, so the
        /// fan-out is capped rather than run over every series at once.
        let concurrency: Int
        /// Per-series ceiling on the beat stream, and the ceiling on the whole
        /// scan. A single wedged series must not hold the scan, and a wedged
        /// scan must not outlive the refresh that started it.
        let seriesTimeout: Duration
        let overallTimeout: Duration

        /// The phone's scan, off its critical refresh path.
        static let phone = Limits(
            seriesLimit: 120,
            concurrency: 4,
            seriesTimeout: .seconds(5),
            overallTimeout: .seconds(20)
        )
        /// The watch's scan, capped tighter because an expired background task
        /// loses the whole compute. The same in foreground and background:
        /// skipping it in background would let the compute throttle starve the
        /// foreground.
        static let watch = Limits(
            seriesLimit: 24,
            concurrency: 2,
            seriesTimeout: .seconds(3),
            overallTimeout: .seconds(6)
        )
    }

    /// Admits one HealthKit query of the scan. `nil` means the query may not
    /// run and counts as that query failing; otherwise the returned closure is
    /// called exactly once when the query ends. The phone passes its pool
    /// permit here, so a permit brackets ONE query, never the whole fan-out.
    typealias QueryAdmission = @Sendable () async -> (@Sendable () -> Void)?

    /// Runs every query as is: the watch has no shared query budget.
    static let admitsEveryQuery: QueryAdmission = { {} }

    /// Apple's Recovery HRV quantity, `nil` below iOS and watchOS 27 where the
    /// type does not exist.
    static var recoveryHRVIdentifier: HKQuantityTypeIdentifier? {
        if #available(iOS 27, watchOS 27, *) {
            return .heartRateVariabilityRMSSD
        }
        return nil
    }

    /// The Stress metric's RMSSD series over `predicate`'s window: Apple's
    /// Recovery HRV samples when the watch writes any, otherwise `scan`. A
    /// failed or empty Recovery read falls through to the scan, so Recovery
    /// HRV hardware never scans. `.failure` only when the scan failed.
    ///
    /// The watch's entry point. The phone runs the same two steps itself
    /// (`HealthKitFetchEngine.fetchHeartbeatRMSSDSamples`) so its Recovery read
    /// keeps the engine's own source gate and query permit.
    static func rmssdSamples(
        store: any BodyHealthQuerying,
        predicate: NSPredicate?,
        limits: Limits,
        onFailure: (@Sendable (String, Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        if let identifier = recoveryHRVIdentifier,
           let recoveryType = HKObjectType.quantityType(forIdentifier: identifier),
           case .success(let recovery) = await BodyHealthQuantityFetch.quantitySampleSeries(
               store: store,
               quantityType: recoveryType,
               predicate: predicate,
               unit: .secondUnit(with: .milli),
               onFailure: { onFailure?(identifier.rawValue, $0) }
           ),
           !recovery.isEmpty {
            return .success(recovery)
        }

        return await scan(store: store, predicate: predicate, limits: limits, onFailure: onFailure)
    }

    /// One RMSSD point per readable heartbeat series matching `predicate`,
    /// dated on the series' `endDate` so it lines up with the SDNN samples the
    /// calculator compares it against, in ascending time order.
    ///
    /// `.failure` when the scan itself failed (device locked, store
    /// unavailable, XPC drop, cancellation, or the overall timeout) so the
    /// caller keeps what it has instead of blanking it; a successful empty
    /// result (the simulator, or a user whose watch records no beat-to-beat
    /// data) is `.success(.empty)` and lets Stress degrade to the SDNN path.
    /// Individual series that fail, time out, or carry too few clean intervals
    /// are dropped without failing the scan.
    static func scan(
        store: any BodyHealthQuerying,
        predicate: NSPredicate?,
        limits: Limits,
        admission: @escaping QueryAdmission = admitsEveryQuery,
        onFailure: (@Sendable (String, Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        let request = BodySampleRequest(
            sampleType: HKSeriesType.heartbeat(),
            predicate: predicate,
            limit: limits.seriesLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        )

        // Scan and deadline are unstructured tasks so the deadline can cancel
        // the scan while this function awaits it; the caller's cancellation is
        // forwarded by hand. `Task`, not `Task.detached`: the scan must inherit
        // the caller's task-locals (the phone's query pool) and priority.
        let scanTask = Task { () -> HealthTrendSeries? in
            guard let samples = await seriesSamples(
                store: store, request: request, admission: admission, onFailure: onFailure
            ) else {
                return nil
            }
            guard !samples.isEmpty else {
                return .empty
            }

            let series = await rmssdSeries(
                store: store, samples: samples, limits: limits, admission: admission, onFailure: onFailure
            )
            // A deadline (or the caller) that cancels mid fan-out leaves only
            // the series that finished first: a failure, never a short scan
            // passed off as complete.
            guard !Task.isCancelled else {
                return nil
            }
            return series
        }
        let deadlineTask = Task {
            try? await ContinuousClock().sleep(for: limits.overallTimeout)
            scanTask.cancel()
        }

        let series = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }
        deadlineTask.cancel()

        guard let series else {
            return .failure
        }
        return .success(series)
    }

    /// The series samples themselves, newest first: metadata only, no beats yet.
    private static func seriesSamples(
        store: any BodyHealthQuerying,
        request: BodySampleRequest,
        admission: QueryAdmission,
        onFailure: (@Sendable (String, Error?) -> Void)?
    ) async -> [HKHeartbeatSeriesSample]? {
        guard let release = await admission() else { return nil }
        defer { release() }
        guard !Task.isCancelled else { return nil }
        let outcome = await store.samples(request)
        guard !Task.isCancelled else { return nil }
        switch outcome {
        case .success(let samples): return samples.compactMap { $0 as? HKHeartbeatSeriesSample }
        case .failure(let error):
            onFailure?(HKSeriesType.heartbeat().identifier, error)
            return nil
        case .cancelled: return nil
        }
    }

    private static func rmssdSeries(
        store: any BodyHealthQuerying,
        samples: [HKHeartbeatSeriesSample],
        limits: Limits,
        admission: @escaping QueryAdmission,
        onFailure: (@Sendable (String, Error?) -> Void)?
    ) async -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []

        await withTaskGroup(of: HealthTrendDataPoint?.self) { group in
            var next = 0
            while next < samples.count, next < limits.concurrency {
                let sample = samples[next]
                group.addTask {
                    await rmssdPoint(
                        store: store, sample: sample, timeout: limits.seriesTimeout,
                        admission: admission, onFailure: onFailure
                    )
                }
                next += 1
            }
            while let point = await group.next() {
                if let point {
                    points.append(point)
                }
                // A cancelled scan's result is discarded, so start no more streams.
                guard next < samples.count, !Task.isCancelled else {
                    continue
                }
                let sample = samples[next]
                group.addTask {
                    await rmssdPoint(
                        store: store, sample: sample, timeout: limits.seriesTimeout,
                        admission: admission, onFailure: onFailure
                    )
                }
                next += 1
            }
        }

        // The series query ran newest-first; the day-sample series is
        // ascending, so restore time order before handing it back.
        return HealthTrendSeries(points: points.sorted { $0.date < $1.date })
    }

    private static func rmssdPoint(
        store: any BodyHealthQuerying,
        sample: HKHeartbeatSeriesSample,
        timeout: Duration,
        admission: @escaping QueryAdmission,
        onFailure: (@Sendable (String, Error?) -> Void)?
    ) async -> HealthTrendDataPoint? {
        let beatsTask = Task { () -> [StressRMSSD.RRInterval]? in
            await heartbeatIntervals(store: store, sample: sample, admission: admission, onFailure: onFailure)
        }
        let deadlineTask = Task {
            try? await ContinuousClock().sleep(for: timeout)
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

    /// Streams one series' beats into successive RR intervals. `nil` on a
    /// failed or cancelled/timed-out stream so the caller drops the series
    /// rather than computing RMSSD from a truncated prefix.
    private static func heartbeatIntervals(
        store: any BodyHealthQuerying,
        sample: HKHeartbeatSeriesSample,
        admission: QueryAdmission,
        onFailure: (@Sendable (String, Error?) -> Void)?
    ) async -> [StressRMSSD.RRInterval]? {
        guard let release = await admission() else { return nil }
        defer { release() }
        let beats = HeartbeatIntervalAccumulator()

        // A streaming query keeps calling back until `done`; the box resumes
        // exactly once and drops the rest, and stops the query on cancellation
        // (the kit's form of the engine's `runCancellableQuery`).
        let box = BodyQueryResumeBox<[StressRMSSD.RRInterval]?>(stop: { store.stop($0) })
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.install(continuation: continuation, cancelledValue: nil) { resume in
                    let query = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, timeSinceSeriesStart, precededByGap, done, error in
                        guard error == nil else {
                            onFailure?("heartbeatSeriesBeats", error)
                            resume(nil)
                            return
                        }

                        beats.append(timeSinceSeriesStart: timeSinceSeriesStart, precededByGap: precededByGap)
                        if done {
                            resume(beats.intervals)
                        }
                    }

                    store.execute(query)
                    return query
                }
            }
        } onCancel: {
            box.cancel(cancelledValue: nil)
        }
    }
}

/// Accumulates one `HKHeartbeatSeriesQuery`'s beats into RR intervals. HealthKit
/// delivers beats on its own queue, so every access is lock-guarded (which is
/// what makes `@unchecked Sendable` sound here, as in `BodyQueryResumeBox`).
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
