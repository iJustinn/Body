//
//  HealthKitFetchEngine+MetricSeries.swift
//  Body
//
//  Reads every per-bucket input the workout detail's time-series charts need
//  (pace or speed, cadence, stride length, ground contact time, vertical
//  oscillation, power) in ONE pass, so opening a sheet costs one bundle read rather
//  than one read per card. Buckets come from HealthKit itself
//  (`HKStatisticsCollectionQueryDescriptor`), which deduplicates overlapping
//  iPhone/Watch sources the way a raw sample walk can't. Deliberately separate
//  from the splits read so the splits' 5% divergence guard can never discard
//  valid series data. Every quantity stays in its canonical HealthKit unit;
//  unit choice is the presentation's.
//

import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Per-bucket series inputs for a workout. Returns `.empty` when the workout
    /// can't be fetched, the activity has no distance pace/speed, the Workout
    /// Metrics permission is opted out, or the workout has no wall-clock
    /// duration. Cancellation (a dismissed detail sheet) is propagated so the
    /// caller can tell "no data" from "didn't finish reading"; any other
    /// per-metric failure leaves that field empty and flags `hadReadFailure`, so
    /// one unreadable metric can't blank the rest — or be cached as absent.
    func workoutMetricSeriesData(workoutID: UUID) async throws -> WorkoutMetricSeriesData {
        guard let workout = try await fetchWorkout(id: workoutID) else {
            return .empty
        }

        let type = HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType)
        let paceStyle = type.paceStyle
        guard paceStyle == .distancePace || paceStyle == .speed else {
            return .empty
        }

        // Every series here is a Workout Metric, so honor the same opt-out as the
        // summary cadence path — without this the cards would surface whenever
        // `.stepCount` happens to be authorized via the separate Steps toggle.
        guard permissionSelection.includes(.workoutMetrics) else {
            return .empty
        }

        let start = workout.startDate
        let end = workout.endDate
        let wallDuration = end.timeIntervalSince(start)
        guard wallDuration > 0 else {
            return .empty
        }

        // At most ~60 buckets across the workout, but never finer than 30 s —
        // below that the watch's sample resolution makes buckets noise rather
        // than signal. Paused stretches simply yield empty buckets.
        let bucketSeconds = max(30, Int(ceil(wallDuration / 60)))
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let interval = DateComponents(second: bucketSeconds)

        var hadReadFailure = false

        var distanceMeters: [Int: Double] = [:]
        if let distanceIdentifier = BodyWorkoutFetch.distanceQuantityTypeIdentifier(for: type) {
            let sums = try await readMetric(distanceIdentifier) {
                try await self.bucketedCumulativeSums(
                    identifier: distanceIdentifier,
                    unit: .meter(),
                    predicate: workoutPredicate,
                    start: start,
                    end: end,
                    bucketSeconds: bucketSeconds,
                    interval: interval
                )
            }
            if let sums {
                distanceMeters = sums
            } else {
                hadReadFailure = true
            }
        }

        var steps: [Int: Double] = [:]
        if type.supportsStepCadence {
            let sums = try await readMetric(.stepCount) {
                try await self.bucketedCumulativeSums(
                    identifier: .stepCount,
                    unit: .count(),
                    predicate: workoutPredicate,
                    start: start,
                    end: end,
                    bucketSeconds: bucketSeconds,
                    interval: interval
                )
            }
            if let sums {
                steps = sums
            } else {
                hadReadFailure = true
            }
        }

        // Running form: only Apple Watch running sessions record these, and only
        // on supported hardware — asking for them elsewhere is a wasted query.
        var strideLengthMeters: WorkoutMetricSeriesData.NativeSeries?
        var groundContactTimeMs: WorkoutMetricSeriesData.NativeSeries?
        var verticalOscillationCm: WorkoutMetricSeriesData.NativeSeries?
        if type == .running {
            let runningSeries: [(HKQuantityTypeIdentifier, HKUnit)] = [
                (.runningStrideLength, .meter()),
                (.runningGroundContactTime, .secondUnit(with: .milli)),
                (.runningVerticalOscillation, .meterUnit(with: .centi))
            ]
            for (identifier, unit) in runningSeries {
                let series = try await readMetric(identifier) {
                    try await self.bucketedDiscreteSeries(
                        identifier: identifier,
                        unit: unit,
                        workout: workout,
                        predicate: workoutPredicate,
                        start: start,
                        end: end,
                        bucketSeconds: bucketSeconds,
                        interval: interval
                    )
                }
                guard let series else {
                    hadReadFailure = true
                    continue
                }
                switch identifier {
                case .runningStrideLength:
                    strideLengthMeters = series
                case .runningGroundContactTime:
                    groundContactTimeMs = series
                default:
                    verticalOscillationCm = series
                }
            }
        }

        var cyclingCadenceRPM: WorkoutMetricSeriesData.NativeSeries?
        if type == .cycling {
            let series = try await readMetric(.cyclingCadence) {
                try await self.bucketedDiscreteSeries(
                    identifier: .cyclingCadence,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    workout: workout,
                    predicate: workoutPredicate,
                    start: start,
                    end: end,
                    bucketSeconds: bucketSeconds,
                    interval: interval
                )
            }
            if let series {
                cyclingCadenceRPM = series
            } else {
                hadReadFailure = true
            }
        }

        // Same double-optional contract as the cadence block above: `readMetric`
        // answers nil when the query threw (→ `hadReadFailure`), while a
        // successful read with no samples answers `.some(nil)` — series stays nil
        // and the bundle is still cacheable.
        var powerWatts: WorkoutMetricSeriesData.NativeSeries?
        if let source = type.powerSource {
            let identifier: HKQuantityTypeIdentifier = source == .running ? .runningPower : .cyclingPower
            let series = try await readMetric(identifier) {
                try await self.bucketedDiscreteSeries(
                    identifier: identifier,
                    unit: .watt(),
                    workout: workout,
                    predicate: workoutPredicate,
                    start: start,
                    end: end,
                    bucketSeconds: bucketSeconds,
                    interval: interval
                )
            }
            if let series {
                powerWatts = series
            } else {
                hadReadFailure = true
            }
        }

        return WorkoutMetricSeriesData(
            bucketSeconds: TimeInterval(bucketSeconds),
            startDate: start,
            endDate: end,
            bucketActiveSeconds: Self.bucketActiveSeconds(
                workout: workout,
                start: start,
                end: end,
                bucketSeconds: bucketSeconds
            ),
            distanceMeters: distanceMeters,
            steps: steps,
            strideLengthMeters: strideLengthMeters,
            groundContactTimeMs: groundContactTimeMs,
            verticalOscillationCm: verticalOscillationCm,
            cyclingCadenceRPM: cyclingCadenceRPM,
            powerWatts: powerWatts,
            hadReadFailure: hadReadFailure
        )
    }

    /// Runs one metric's read. Cancellation propagates (the caller must not cache
    /// a half-read bundle); any other failure is logged and reported as `nil` so
    /// the remaining metrics still make it into the bundle.
    private func readMetric<Value>(
        _ identifier: HKQuantityTypeIdentifier,
        _ read: () async throws -> Value
    ) async throws -> Value? {
        do {
            return try await read()
        } catch {
            if error is CancellationError || Task.isCancelled {
                throw error
            }
            Self.logTrendQueryFailure(identifier.rawValue, error: error)
            return nil
        }
    }

    /// Per-bucket discrete average/min/max for a natively recorded metric, plus
    /// the session-wide average/max for the card headers. `nil` when the type is
    /// unavailable or no bucket carries a sample (the source doesn't record it).
    private func bucketedDiscreteSeries(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout,
        predicate: NSPredicate,
        start: Date,
        end: Date,
        bucketSeconds: Int,
        interval: DateComponents
    ) async throws -> WorkoutMetricSeriesData.NativeSeries? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: quantityType, predicate: predicate),
            options: [.discreteAverage, .discreteMin, .discreteMax],
            anchorDate: start,
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: healthStore)

        var buckets: [WorkoutMetricSeriesData.NativeBucket] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard let average = statistics.averageQuantity() else {
                // No samples landed in this bucket (pause, or a source that
                // doesn't record this metric) — leave a gap.
                return
            }
            let value = average.doubleValue(for: unit)
            buckets.append(WorkoutMetricSeriesData.NativeBucket(
                index: Self.bucketIndex(of: statistics.startDate, start: start, bucketSeconds: bucketSeconds),
                average: value,
                minimum: statistics.minimumQuantity()?.doubleValue(for: unit) ?? value,
                maximum: statistics.maximumQuantity()?.doubleValue(for: unit) ?? value
            ))
        }
        guard !buckets.isEmpty else {
            return nil
        }

        // Prefer the statistics the workout already carries (free, no query).
        var sessionAverage = workout.statistics(for: quantityType)?.averageQuantity()?.doubleValue(for: unit)
        var sessionMax = workout.statistics(for: quantityType)?.maximumQuantity()?.doubleValue(for: unit)
        if sessionAverage == nil, sessionMax == nil {
            // Samples exist but aren't attached as workout statistics (common
            // when they were written alongside, not by, the workout source) —
            // one session-wide query fills the headers.
            let sessionStatistics = try await sessionStatistics(
                quantityType: quantityType,
                unit: unit,
                predicate: predicate
            )
            sessionAverage = sessionStatistics.average
            sessionMax = sessionStatistics.maximum
        }

        return WorkoutMetricSeriesData.NativeSeries(
            buckets: buckets.sorted { $0.index < $1.index },
            sessionAverage: sessionAverage,
            sessionMax: sessionMax
        )
    }

    /// Session-wide discrete average/maximum over the workout's own samples.
    /// Throws on a query FAILURE so the caller doesn't render headers that
    /// silently disagree with the bars.
    private func sessionStatistics(
        quantityType: HKQuantityType,
        unit: HKUnit,
        predicate: NSPredicate
    ) async throws -> (average: Double?, maximum: Double?) {
        try await trackedThrowingHealthQuery { resume in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, statistics, error in
                if let error {
                    resume(.failure(error))
                    return
                }
                resume(.success((
                    average: statistics?.averageQuantity()?.doubleValue(for: unit),
                    maximum: statistics?.maximumQuantity()?.doubleValue(for: unit)
                )))
            }
            healthStore.execute(query)
        }
    }

    /// Per-bucket cumulative sums for a totalling metric, as HealthKit's own
    /// source-deduplicated statistics. Empty buckets are omitted.
    private func bucketedCumulativeSums(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate,
        start: Date,
        end: Date,
        bucketSeconds: Int,
        interval: DateComponents
    ) async throws -> [Int: Double] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return [:]
        }

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: quantityType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: healthStore)

        var sums: [Int: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard let sum = statistics.sumQuantity()?.doubleValue(for: unit), sum > 0 else { return }
            sums[Self.bucketIndex(of: statistics.startDate, start: start, bucketSeconds: bucketSeconds)] = sum
        }
        return sums
    }

    /// Seconds of each bucket window that are *active* time: the window length
    /// minus its overlap with the workout's paused stretches. Pace and cadence
    /// divide by these, so a paused bucket and the short final bucket both get
    /// their real duration instead of a full `bucketSeconds`. Buckets with no
    /// active time are omitted entirely.
    private static func bucketActiveSeconds(
        workout: HKWorkout,
        start: Date,
        end: Date,
        bucketSeconds: Int
    ) -> [Int: Double] {
        let pauses = pausedIntervals(workout: workout, start: start, end: end)
        let bucketLength = TimeInterval(bucketSeconds)
        let bucketCount = max(1, Int(ceil(end.timeIntervalSince(start) / bucketLength)))

        var active: [Int: Double] = [:]
        for index in 0..<bucketCount {
            let windowStart = start.addingTimeInterval(Double(index) * bucketLength)
            let windowEnd = min(start.addingTimeInterval(Double(index + 1) * bucketLength), end)
            var seconds = windowEnd.timeIntervalSince(windowStart)
            guard seconds > 0 else { continue }
            for pause in pauses {
                let overlapStart = max(windowStart, pause.start)
                let overlapEnd = min(windowEnd, pause.end)
                if overlapEnd > overlapStart {
                    seconds -= overlapEnd.timeIntervalSince(overlapStart)
                }
            }
            if seconds > 0 {
                active[index] = seconds
            }
        }
        return active
    }

    /// The workout's paused stretches, merged from both pause flavors the watch
    /// records: an explicit `.pause`/`.resume` pair and the auto-pause
    /// `.motionPaused`/`.motionResumed` pair. A pause with no matching resume
    /// (the session ended while paused) runs to `end`.
    private static func pausedIntervals(
        workout: HKWorkout,
        start: Date,
        end: Date
    ) -> [(start: Date, end: Date)] {
        let events = (workout.workoutEvents ?? []).sorted { $0.dateInterval.start < $1.dateInterval.start }
        var intervals: [(start: Date, end: Date)] = []
        var pauseStart: Date?

        for event in events {
            switch event.type {
            case .pause, .motionPaused:
                if pauseStart == nil {
                    pauseStart = event.dateInterval.start
                }
            case .resume, .motionResumed:
                if let pauseStart {
                    intervals.append((start: pauseStart, end: event.dateInterval.start))
                }
                pauseStart = nil
            default:
                continue
            }
        }
        if let pauseStart {
            intervals.append((start: pauseStart, end: end))
        }

        return intervals.compactMap { interval in
            let clampedStart = max(start, interval.start)
            let clampedEnd = min(end, interval.end)
            guard clampedEnd > clampedStart else { return nil }
            return (start: clampedStart, end: clampedEnd)
        }
    }

    /// 0-based bucket index of a statistics window, from the workout start.
    private static func bucketIndex(of date: Date, start: Date, bucketSeconds: Int) -> Int {
        Int(floor(date.timeIntervalSince(start) / Double(bucketSeconds)))
    }
}
