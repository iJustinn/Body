//
//  WorkoutSplitCalculator.swift
//  BodyMetricsKit
//

import Foundation

/// A timestamped distance increment from a workout's distance samples.
struct WorkoutDistanceSample: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let meters: Double
}

/// A split segment the watch recorded into the workout (an `HKWorkoutEvent`
/// `.segment`) — the exact per-km/mi windows Apple Fitness shows.
struct WorkoutTimeSegment: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
}

/// A timestamped step-count increment from the workout's own step samples.
struct WorkoutStepSample: Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let count: Double
}

/// Everything the Splits section needs from HealthKit for one workout.
struct WorkoutSplitData: Equatable, Sendable {
    let distanceSamples: [WorkoutDistanceSample]
    let segments: [WorkoutTimeSegment]
    let stepSamples: [WorkoutStepSample]

    static let empty = WorkoutSplitData(distanceSamples: [], segments: [], stepSamples: [])
}

/// One per-unit split (kilometer or mile) derived from a workout's distance samples.
struct WorkoutSplit: Equatable, Identifiable {
    let index: Int              // 1-based
    let distanceMeters: Double  // == unitMeters except the final partial
    let durationSeconds: Double
    let isPartial: Bool
    let startDate: Date         // split window start, for per-split metrics like avg HR
    let endDate: Date           // split window end (boundary crossing, or last sample end)

    var id: Int { index }
}

/// Splits a workout's distance samples into per-unit splits with wall-clock durations.
enum WorkoutSplitCalculator {
    /// Builds per-unit splits from `samples`, measuring the first split from `workoutStart`
    /// and clipping every interval to `[workoutStart, workoutEnd]`. Returns `[]` when the
    /// data is too coarse for splits (any sample already covers a full unit).
    ///
    /// When the watch recorded `segments` (workout `.segment` events) and their
    /// per-segment distance matches `unitMeters`, splits use those exact windows —
    /// the same boundaries Apple Fitness shows — instead of interpolating boundary
    /// crossings from the distance samples, which can drift early in a run before
    /// GPS calibration settles.
    static func splits(
        samples: [WorkoutDistanceSample],
        unitMeters: Double,          // 1_000.0 or 1_609.344
        workoutStart: Date,
        workoutEnd: Date,
        segments: [WorkoutTimeSegment] = []
    ) -> [WorkoutSplit] {
        // Sort chronologically and drop samples that carry no forward distance.
        let ordered = samples
            .filter { $0.meters > 0 }
            .sorted { $0.startDate < $1.startDate }

        // Clip intervals to the workout window, trimming straddling samples' meters
        // proportionally so distance recorded outside the window can't inflate a split.
        var clipped: [WorkoutDistanceSample] = []
        for sample in ordered {
            let originalDuration = sample.endDate.timeIntervalSince(sample.startDate)
            if originalDuration <= 0 {
                guard sample.startDate >= workoutStart, sample.startDate <= workoutEnd else {
                    continue
                }
                clipped.append(sample)
                continue
            }
            let clippedStart = max(sample.startDate, workoutStart)
            let clippedEnd = min(sample.endDate, workoutEnd)
            guard clippedEnd > clippedStart else {
                continue
            }
            let fraction = clippedEnd.timeIntervalSince(clippedStart) / originalDuration
            clipped.append(WorkoutDistanceSample(
                startDate: clippedStart,
                endDate: clippedEnd,
                meters: sample.meters * fraction
            ))
        }

        // Granularity guard: a single sample covering a full unit is too coarse to split.
        guard clipped.allSatisfy({ $0.meters < unitMeters }) else {
            return []
        }
        guard let finalEnd = clipped.last?.endDate else {
            return []
        }

        if let segmentSplits = segmentBasedSplits(
            clippedSamples: clipped,
            segments: segments,
            unitMeters: unitMeters,
            finalEnd: finalEnd
        ) {
            return segmentSplits
        }

        var splits: [WorkoutSplit] = []
        var accumulated = 0.0
        var splitStart = workoutStart

        for sample in clipped {
            let sampleDuration = sample.endDate.timeIntervalSince(sample.startDate)
            var offset = 0.0
            while sample.meters - offset >= unitMeters - accumulated {
                let metersToBoundary = unitMeters - accumulated
                offset += metersToBoundary
                let crossTime = sampleDuration > 0
                    ? sample.startDate.addingTimeInterval((offset / sample.meters) * sampleDuration)
                    : sample.startDate
                let duration = crossTime.timeIntervalSince(splitStart)
                if duration > 0 {
                    splits.append(WorkoutSplit(
                        index: splits.count + 1,
                        distanceMeters: unitMeters,
                        durationSeconds: duration,
                        isPartial: false,
                        startDate: splitStart,
                        endDate: crossTime
                    ))
                }
                accumulated = 0
                splitStart = crossTime
            }
            accumulated += sample.meters - offset
        }

        // Partial final split once at least 10 m remain past the last boundary.
        if accumulated >= 10 {
            let duration = finalEnd.timeIntervalSince(splitStart)
            if duration > 0 {
                splits.append(WorkoutSplit(
                    index: splits.count + 1,
                    distanceMeters: accumulated,
                    durationSeconds: duration,
                    isPartial: true,
                    startDate: splitStart,
                    endDate: finalEnd
                ))
            }
        }

        return splits
    }

    /// Splits from the watch's recorded segment events, or nil to fall back to
    /// boundary interpolation. Each candidate window is kept only when its
    /// recorded distance (summed proportionally from the samples) is within 15%
    /// of `unitMeters` — generous enough to survive the early-run undercount the
    /// distance samples show before GPS calibration settles, while dropping pause
    /// slivers, off-unit windows (mile segments while viewing kilometers), and
    /// other non-split events mixed into the workout. Overlapping duplicates
    /// (e.g. the same split recorded as both a segment and a lap) keep the
    /// earliest window and drop the rest.
    private static func segmentBasedSplits(
        clippedSamples: [WorkoutDistanceSample],
        segments: [WorkoutTimeSegment],
        unitMeters: Double,
        finalEnd: Date
    ) -> [WorkoutSplit]? {
        var accepted: [WorkoutTimeSegment] = []
        for segment in segments.sorted(by: { $0.startDate < $1.startDate }) {
            guard segment.endDate > segment.startDate else { continue }
            let meters = meters(in: segment, samples: clippedSamples)
            guard abs(meters - unitMeters) <= unitMeters * 0.15 else { continue }
            if let previous = accepted.last,
               segment.startDate < previous.endDate.addingTimeInterval(-1) {
                continue
            }
            accepted.append(segment)
        }

        // The 15% window tolerance exists to survive the early-run undercount the
        // distance samples show at *interior* km/mi boundaries the watch genuinely
        // completed (GPS still calibrating). The trailing window has no such excuse:
        // it is either the leftover-to-workout-end partial or a sub-unit workout/lap,
        // so promoting it to a full unit would report a completed km/mi the run never
        // reached. Drop it unless it actually recorded a full unit (a 1 m epsilon
        // absorbs boundary-interpolation rounding); the partial-tail logic below then
        // reports its true distance. Interior windows keep the generous tolerance.
        if let last = accepted.last,
           meters(in: last, samples: clippedSamples) < unitMeters - 1 {
            accepted.removeLast()
        }
        guard !accepted.isEmpty else {
            return nil
        }

        // The accepted windows must account for roughly the whole workout — a
        // couple of manual laps in a long run shouldn't masquerade as its splits.
        // One extra window above floor(total/unit) is allowed because the sample
        // total itself undercounts early in a run (the drift these recorded
        // windows correct); fewer windows than the distance implies means the
        // events aren't per-unit splits.
        let totalMeters = clippedSamples.reduce(0) { $0 + $1.meters }
        let expectedCount = Int(totalMeters / unitMeters)
        guard accepted.count == expectedCount || accepted.count == expectedCount + 1 else {
            return nil
        }

        var splits = accepted.enumerated().map { index, segment in
            WorkoutSplit(
                index: index + 1,
                distanceMeters: unitMeters,
                durationSeconds: segment.endDate.timeIntervalSince(segment.startDate),
                isPartial: false,
                startDate: segment.startDate,
                endDate: segment.endDate
            )
        }

        // Partial tail after the last recorded segment, same 10 m threshold as the
        // interpolated path.
        let lastEnd = accepted[accepted.count - 1].endDate
        if finalEnd > lastEnd {
            let tail = meters(
                in: WorkoutTimeSegment(startDate: lastEnd, endDate: finalEnd),
                samples: clippedSamples
            )
            if tail >= 10 {
                splits.append(WorkoutSplit(
                    index: splits.count + 1,
                    distanceMeters: tail,
                    durationSeconds: finalEnd.timeIntervalSince(lastEnd),
                    isPartial: true,
                    startDate: lastEnd,
                    endDate: finalEnd
                ))
            }
        }
        return splits
    }

    /// Meters recorded within a time window, counting straddling samples proportionally.
    private static func meters(
        in segment: WorkoutTimeSegment,
        samples: [WorkoutDistanceSample]
    ) -> Double {
        samples.reduce(0) { total, sample in
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            if duration <= 0 {
                let inside = sample.startDate >= segment.startDate && sample.startDate <= segment.endDate
                return total + (inside ? sample.meters : 0)
            }
            let overlap = min(sample.endDate, segment.endDate)
                .timeIntervalSince(max(sample.startDate, segment.startDate))
            guard overlap > 0 else { return total }
            return total + sample.meters * (overlap / duration)
        }
    }
}

/// View-ready split rows: index, pace/speed value, per-split average heart rate,
/// and the fastest highlight. Keeps the workout detail view dumb, mirroring
/// `WorkoutDetailPresentation`.
struct WorkoutSplitsPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: Int
        let indexText: String          // "1", "2", …; partial: fraction like "0.4"
        let valueText: String          // paceText or speedText output
        let heartRateText: String?     // average BPM over the split, nil when no samples
        let cadenceText: String?       // average steps/min over the split, nil when no steps
        let barFraction: Double        // 0…1 of the slowest split, so fastest = shortest bar
        let isFastest: Bool
        let isSlowest: Bool
        let isPartial: Bool
        let accessibilityLabel: String
    }

    let unitHeaderText: String         // "km" / "mi" (localized), the segment column
    let valueHeaderText: String        // "Pace" / "Speed" (localized)
    let heartRateHeaderText: String    // "Avg HR" (localized)
    let cadenceHeaderText: String      // "Step Cadence" (localized)
    let rows: [Row]

    init?(
        splits: [WorkoutSplit],
        paceStyle: WorkoutPaceStyle,
        distanceUnitPreference: BodyValueFormat.DistanceUnitPreference,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        stepSamples: [WorkoutStepSample] = [],
        locale: Locale = .current
    ) {
        guard paceStyle == .distancePace || paceStyle == .speed else {
            return nil
        }

        // Fastest highlight considers complete splits only; nil if none exist.
        let completeSplits = splits.filter { !$0.isPartial }
        guard let fastest = completeSplits.max(by: { Self.speed($0) < Self.speed($1) }) else {
            return nil
        }
        let fastestID = fastest.id

        // Slowest highlight mirrors the fastest one: complete splits only. The strict
        // comparison keeps the two flags mutually exclusive — with a single complete
        // split, or every split at identical pace, `max` and `min` land on different
        // rows that aren't meaningfully faster or slower, so neither earns the red.
        let slowestID = completeSplits
            .min(by: { Self.speed($0) < Self.speed($1) })
            .flatMap { Self.speed($0) < Self.speed(fastest) ? $0.id : nil }

        let useMiles = distanceUnitPreference == .miles
        let unitMeters = useMiles ? 1_609.344 : 1_000.0

        unitHeaderText = useMiles
            ? String(localized: "mi", table: "BodyMetricsKit")
            : String(localized: "km", table: "BodyMetricsKit")
        valueHeaderText = paceStyle == .speed
            ? String(localized: "Speed", table: "BodyMetricsKit")
            : String(localized: "Pace", table: "BodyMetricsKit")
        heartRateHeaderText = String(localized: "Avg HR", table: "BodyMetricsKit")
        cadenceHeaderText = String(localized: "Step Cadence", table: "BodyMetricsKit")

        // Bar length tracks pace (seconds per meter) across the complete splits only:
        // the slowest complete split fills the bar, the fastest is shortest. A partial
        // tail is routinely slower than every complete split (a few metres of cool-down
        // stretched over minutes), so scaling to it would shrink every real split; it is
        // clamped to a full bar below instead.
        let slowestPace = completeSplits.map { $0.durationSeconds / $0.distanceMeters }.max() ?? 0

        // `averageHeartRate(in:samples:)` runs once per split and needs ascending
        // samples, so sort once here rather than inside the loop.
        let sortedHeartRateSamples = heartRateSamples.sorted { $0.date < $1.date }

        rows = splits.map { split in
            let indexText = split.isPartial
                ? BodyValueFormat.numberText(split.distanceMeters / unitMeters, decimals: 1, locale: locale)
                : "\(split.index)"
            let valueText: String
            switch paceStyle {
            case .speed:
                valueText = BodyValueFormat.speedText(
                    meters: split.distanceMeters,
                    seconds: split.durationSeconds,
                    distanceUnitPreference: distanceUnitPreference,
                    locale: locale
                )
            default:
                valueText = BodyValueFormat.paceText(
                    meters: split.distanceMeters,
                    seconds: split.durationSeconds,
                    distanceUnitPreference: distanceUnitPreference,
                    locale: locale
                )
            }
            let heartRateText = Self.averageHeartRate(in: split, samples: sortedHeartRateSamples)
                .map { "\(Int($0.rounded()))" }
            let cadenceText = Self.stepCadence(in: split, samples: stepSamples)
                .map { "\(Int($0.rounded()))" }
            let barFraction = slowestPace > 0
                ? min(max((split.durationSeconds / split.distanceMeters) / slowestPace, 0), 1)
                : 0
            let isFastest = split.id == fastestID
            let isSlowest = split.id == slowestID
            var accessibilityLabel = useMiles
                ? String(localized: "Mile \(indexText), \(valueText)", table: "BodyMetricsKit")
                : String(localized: "Kilometer \(indexText), \(valueText)", table: "BodyMetricsKit")
            if let heartRateText {
                accessibilityLabel += ", " + String(localized: "Average heart rate \(heartRateText) BPM", table: "BodyMetricsKit")
            }
            if let cadenceText {
                accessibilityLabel += ", " + String(localized: "Step Cadence", table: "BodyMetricsKit") + " \(cadenceText)"
            }
            if isFastest {
                accessibilityLabel += ", " + String(localized: "Fastest split", table: "BodyMetricsKit")
            }
            if isSlowest {
                accessibilityLabel += ", " + String(localized: "Slowest split", table: "BodyMetricsKit")
            }
            return Row(
                id: split.id,
                indexText: indexText,
                valueText: valueText,
                heartRateText: heartRateText,
                cadenceText: cadenceText,
                barFraction: barFraction,
                isFastest: isFastest,
                isSlowest: isSlowest,
                isPartial: split.isPartial,
                accessibilityLabel: accessibilityLabel
            )
        }
    }

    private static func speed(_ split: WorkoutSplit) -> Double {
        split.distanceMeters / split.durationSeconds
    }

    /// Steps per minute over the split's window: step samples counted with
    /// proportional overlap (a sample straddling the boundary contributes its
    /// in-window share) divided by the window's minutes.
    private static func stepCadence(
        in split: WorkoutSplit,
        samples: [WorkoutStepSample]
    ) -> Double? {
        let minutes = split.durationSeconds / 60
        guard minutes > 0 else { return nil }

        let steps = samples.reduce(0.0) { total, sample in
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            if duration <= 0 {
                let inside = sample.startDate >= split.startDate && sample.startDate <= split.endDate
                return total + (inside ? sample.count : 0)
            }
            let overlap = min(sample.endDate, split.endDate)
                .timeIntervalSince(max(sample.startDate, split.startDate))
            guard overlap > 0 else { return total }
            return total + sample.count * (overlap / duration)
        }
        guard steps > 0 else { return nil }
        return steps / minutes
    }

    /// Time-weighted mean BPM over the split's window (trapezoidal integration of
    /// the piecewise-linear HR curve, matching how Apple Fitness averages splits —
    /// a plain per-sample mean skews toward moments the watch happened to sample
    /// densely). When the window holds fewer than two samples (sparse cadence or a
    /// short edge split), falls back to the sample nearest the window's midpoint so
    /// every split with any workout HR data still shows a value.
    ///
    /// `samples` must already be sorted ascending by `date`; the caller sorts once for
    /// the whole table rather than once per split.
    private static func averageHeartRate(
        in split: WorkoutSplit,
        samples: [WorkoutHeartRateSample]
    ) -> Double? {
        guard !samples.isEmpty else { return nil }

        var weightedSum = 0.0
        var coveredSeconds = 0.0

        for (sample, next) in zip(samples, samples.dropFirst()) {
            // Clamp each inter-sample segment to the split window and integrate
            // the linearly interpolated BPM across the clamped portion.
            let segmentStart = sample.date.timeIntervalSinceReferenceDate
            let segmentEnd = next.date.timeIntervalSinceReferenceDate
            let clampedStart = max(segmentStart, split.startDate.timeIntervalSinceReferenceDate)
            let clampedEnd = min(segmentEnd, split.endDate.timeIntervalSinceReferenceDate)
            guard clampedEnd > clampedStart, segmentEnd > segmentStart else { continue }

            let span = segmentEnd - segmentStart
            let bpmAt = { (t: Double) -> Double in
                sample.beatsPerMinute
                    + (next.beatsPerMinute - sample.beatsPerMinute) * ((t - segmentStart) / span)
            }
            let duration = clampedEnd - clampedStart
            weightedSum += (bpmAt(clampedStart) + bpmAt(clampedEnd)) / 2 * duration
            coveredSeconds += duration
        }

        if coveredSeconds > 0 {
            return weightedSum / coveredSeconds
        }

        let midpoint = split.startDate.addingTimeInterval(
            split.endDate.timeIntervalSince(split.startDate) / 2
        )
        return samples.min {
            abs($0.date.timeIntervalSince(midpoint)) < abs($1.date.timeIntervalSince(midpoint))
        }?.beatsPerMinute
    }
}
