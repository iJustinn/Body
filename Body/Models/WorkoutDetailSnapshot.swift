//
//  WorkoutDetailSnapshot.swift
//  Body
//
//  On-disk payload for one workout's expensive detail reads (GPS route, metric
//  series, heart rate recovery), so re-opening a workout doesn't re-scan
//  HealthKit. The persisted shapes are DTOs rather than `Codable` conformances
//  on the models themselves: the models live in BodyMetricsKit / app targets
//  that compile into four products, and a `Codable` extension declared in
//  another file can't synthesize its members anyway.
//
//  Only positive payloads are ever written, so nothing here encodes a
//  "confirmed absent" state — a missing field means "not cached", not "known
//  empty".
//

import Foundation

struct WorkoutDetailSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    /// Optional so a file written before versioning (or by a future build)
    /// still decodes; the store treats nil or a mismatch as a cache miss.
    let schemaVersion: Int?
    let workoutID: UUID
    var route: PersistedWorkoutRoute?
    /// Added after v1 shipped, so it stays optional and the schema version is
    /// unchanged: files written before it decode with nil, which the store
    /// already treats as "not cached".
    var splitData: PersistedWorkoutSplitData?
    var metricSeries: PersistedWorkoutMetricSeries?
    var heartRateRecoveryBPM: Double?

    init(
        schemaVersion: Int? = WorkoutDetailSnapshot.currentSchemaVersion,
        workoutID: UUID,
        route: PersistedWorkoutRoute? = nil,
        splitData: PersistedWorkoutSplitData? = nil,
        metricSeries: PersistedWorkoutMetricSeries? = nil,
        heartRateRecoveryBPM: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.workoutID = workoutID
        self.route = route
        self.splitData = splitData
        self.metricSeries = metricSeries
        self.heartRateRecoveryBPM = heartRateRecoveryBPM
    }

    /// True when the snapshot carries nothing worth keeping on disk.
    var isEmpty: Bool {
        route == nil && splitData == nil && metricSeries == nil && heartRateRecoveryBPM == nil
    }
}

struct PersistedRouteCoordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let speed: Double
    let altitude: Double?

    init(model: RouteCoordinate) {
        latitude = model.latitude
        longitude = model.longitude
        speed = model.speed
        altitude = model.altitude
    }

    func toModel() -> RouteCoordinate {
        RouteCoordinate(latitude: latitude, longitude: longitude, speed: speed, altitude: altitude)
    }
}

struct PersistedElevationSample: Codable, Equatable, Sendable {
    let offset: TimeInterval
    let meters: Double

    init(model: WorkoutElevationSample) {
        offset = model.offset
        meters = model.meters
    }

    func toModel() -> WorkoutElevationSample {
        WorkoutElevationSample(offset: offset, meters: meters)
    }
}

struct PersistedWorkoutRoute: Codable, Equatable, Sendable {
    let coordinates: [PersistedRouteCoordinate]
    let locality: String?
    let elevationProfile: [PersistedElevationSample]

    init(model: WorkoutRoute) {
        coordinates = model.coordinates.map(PersistedRouteCoordinate.init(model:))
        locality = model.locality
        elevationProfile = model.elevationProfile.map(PersistedElevationSample.init(model:))
    }

    func toModel() -> WorkoutRoute {
        WorkoutRoute(
            coordinates: coordinates.map { $0.toModel() },
            locality: locality,
            elevationProfile: elevationProfile.map { $0.toModel() }
        )
    }
}

struct PersistedDistanceSample: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let meters: Double

    func toModel() -> WorkoutDistanceSample {
        WorkoutDistanceSample(startDate: startDate, endDate: endDate, meters: meters)
    }
}

struct PersistedTimeSegment: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    func toModel() -> WorkoutTimeSegment {
        WorkoutTimeSegment(startDate: startDate, endDate: endDate)
    }
}

struct PersistedStepSample: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date
    let count: Double

    func toModel() -> WorkoutStepSample {
        WorkoutStepSample(startDate: startDate, endDate: endDate, count: count)
    }
}

/// The Splits section's HealthKit inputs, downsampled for disk. There is
/// deliberately no `init(model:)`: a workout's raw distance/step samples are
/// unbounded (a long ride can carry tens of thousands), so every write must go
/// through `downsampled(from:)`, which is the only way to build one. `toModel()`
/// is the sole reverse mapping.
struct PersistedWorkoutSplitData: Codable, Equatable, Sendable {
    /// Merge targets: the downsampler aims for `targetSampleCount` and refuses
    /// to persist at all past `maximumSampleCount`, so the advertised cap holds
    /// by construction rather than by hope.
    private static let targetSampleCount = 1_000
    private static let maximumSampleCount = 1_500
    /// A merged distance sample must stay far below the calculator's coarseness
    /// guard, which rejects the whole workout if any sample covers a full unit.
    private static let maximumMergedMeters = 50.0
    /// A gap this long between samples is a pause; merging across it would smear
    /// distance over the pause and shift interpolated split boundaries.
    private static let maximumMergeGapSeconds = 15.0
    /// Caps on the merged sample itself, so many sub-`maximumMergeGapSeconds`
    /// pauses can't accumulate into minutes of smear.
    private static let maximumMergedSpanSeconds = 120.0
    private static let maximumMergedGapTotalSeconds = 30.0

    let distanceSamples: [PersistedDistanceSample]
    let segments: [PersistedTimeSegment]
    let stepSamples: [PersistedStepSample]

    func toModel() -> WorkoutSplitData {
        WorkoutSplitData(
            distanceSamples: distanceSamples.map { $0.toModel() },
            segments: segments.map { $0.toModel() },
            stepSamples: stepSamples.map { $0.toModel() }
        )
    }

    /// Downsamples a workout's split inputs for disk by merging consecutive
    /// samples into runs, summing their meters/counts exactly (the calculator
    /// sums meters, so a rounded total would move every split boundary).
    ///
    /// Runs never cross a pause, never grow coarse enough to disturb the
    /// calculator's guards, and never cross a recorded segment boundary — the
    /// calculator prorates a straddling sample's meters across the windows it
    /// touches, so a merge over a boundary redistributes distance between two
    /// segments and can flip their per-segment 15% validation.
    ///
    /// Returns nil when there is nothing positive to persist, or when the merged
    /// result is still too large to be worth a cache file.
    static func downsampled(from model: WorkoutSplitData) -> PersistedWorkoutSplitData? {
        guard !model.distanceSamples.isEmpty else { return nil }

        let segments = model.segments.map {
            PersistedTimeSegment(startDate: $0.startDate, endDate: $0.endDate)
        }
        // Both a segment's start and its end are boundaries the calculator
        // prorates against.
        let boundaries = segments.flatMap { [$0.startDate, $0.endDate] }

        let distanceSamples = merged(
            model.distanceSamples.sorted { $0.startDate < $1.startDate },
            boundaries: boundaries,
            maximumValue: maximumMergedMeters,
            start: { $0.startDate },
            end: { $0.endDate },
            value: { $0.meters },
            make: { PersistedDistanceSample(startDate: $0, endDate: $1, meters: $2) }
        )
        let stepSamples = merged(
            model.stepSamples.sorted { $0.startDate < $1.startDate },
            boundaries: boundaries,
            maximumValue: nil,
            start: { $0.startDate },
            end: { $0.endDate },
            value: { $0.count },
            make: { PersistedStepSample(startDate: $0, endDate: $1, count: $2) }
        )

        guard distanceSamples.count <= maximumSampleCount,
              stepSamples.count <= maximumSampleCount else {
            return nil
        }

        return PersistedWorkoutSplitData(
            distanceSamples: distanceSamples,
            segments: segments,
            stepSamples: stepSamples
        )
    }

    /// Walks `sorted` (already chronological) in runs of at most `stride`
    /// samples, ending a run early whenever merging the next sample would break
    /// one of the invariants above. A sample that straddles a segment boundary
    /// on its own can't be merged in either direction, so it is emitted as-is.
    private static func merged<Sample, Output>(
        _ sorted: [Sample],
        boundaries: [Date],
        maximumValue: Double?,
        start: (Sample) -> Date,
        end: (Sample) -> Date,
        value: (Sample) -> Double,
        make: (Date, Date, Double) -> Output
    ) -> [Output] {
        guard !sorted.isEmpty else { return [] }

        let stride = max(1, Int(ceil(Double(sorted.count) / Double(targetSampleCount))))
        var output: [Output] = []
        output.reserveCapacity(sorted.count / stride + 1)

        var index = 0
        while index < sorted.count {
            let first = sorted[index]
            let runStart = start(first)
            var runEnd = end(first)
            var total = value(first)
            var gapSeconds = 0.0
            var length = 1
            index += 1

            while length < stride, index < sorted.count {
                let candidate = sorted[index]
                let gap = max(0, start(candidate).timeIntervalSince(runEnd))
                let candidateEnd = max(runEnd, end(candidate))
                if let maximumValue, total + value(candidate) > maximumValue { break }
                if gap > maximumMergeGapSeconds { break }
                if candidateEnd.timeIntervalSince(runStart) > maximumMergedSpanSeconds { break }
                if gapSeconds + gap > maximumMergedGapTotalSeconds { break }
                if crossesBoundary(boundaries, from: runStart, to: candidateEnd) { break }

                runEnd = candidateEnd
                total += value(candidate)
                gapSeconds += gap
                length += 1
                index += 1
            }

            output.append(make(runStart, runEnd, total))
        }

        return output
    }

    private static func crossesBoundary(_ boundaries: [Date], from start: Date, to end: Date) -> Bool {
        boundaries.contains { $0 > start && $0 < end }
    }
}

struct PersistedWorkoutMetricSeries: Codable, Equatable, Sendable {
    struct NativeBucket: Codable, Equatable, Sendable {
        let index: Int
        let average: Double
        let minimum: Double
        let maximum: Double

        init(model: WorkoutMetricSeriesData.NativeBucket) {
            index = model.index
            average = model.average
            minimum = model.minimum
            maximum = model.maximum
        }

        func toModel() -> WorkoutMetricSeriesData.NativeBucket {
            WorkoutMetricSeriesData.NativeBucket(
                index: index,
                average: average,
                minimum: minimum,
                maximum: maximum
            )
        }
    }

    struct NativeSeries: Codable, Equatable, Sendable {
        let buckets: [NativeBucket]
        let sessionAverage: Double?
        let sessionMax: Double?

        init(model: WorkoutMetricSeriesData.NativeSeries) {
            buckets = model.buckets.map(NativeBucket.init(model:))
            sessionAverage = model.sessionAverage
            sessionMax = model.sessionMax
        }

        func toModel() -> WorkoutMetricSeriesData.NativeSeries {
            WorkoutMetricSeriesData.NativeSeries(
                buckets: buckets.map { $0.toModel() },
                sessionAverage: sessionAverage,
                sessionMax: sessionMax
            )
        }
    }

    let bucketSeconds: TimeInterval
    let startDate: Date
    let endDate: Date
    // `[Int: Double]` encodes as an unkeyed array whose element order follows
    // the dictionary's hash seed, which changes between launches — that would
    // defeat the store's byte-compare dedupe even under `.sortedKeys`. Stringify
    // the Int keys so these ride in a real keyed container.
    let bucketActiveSeconds: [String: Double]
    let distanceMeters: [String: Double]
    let steps: [String: Double]
    let strideLengthMeters: NativeSeries?
    let groundContactTimeMs: NativeSeries?
    let verticalOscillationCm: NativeSeries?
    let cyclingCadenceRPM: NativeSeries?

    init(model: WorkoutMetricSeriesData) {
        bucketSeconds = model.bucketSeconds
        startDate = model.startDate
        endDate = model.endDate
        bucketActiveSeconds = Self.stringKeyed(model.bucketActiveSeconds)
        distanceMeters = Self.stringKeyed(model.distanceMeters)
        steps = Self.stringKeyed(model.steps)
        strideLengthMeters = model.strideLengthMeters.map(NativeSeries.init(model:))
        groundContactTimeMs = model.groundContactTimeMs.map(NativeSeries.init(model:))
        verticalOscillationCm = model.verticalOscillationCm.map(NativeSeries.init(model:))
        cyclingCadenceRPM = model.cyclingCadenceRPM.map(NativeSeries.init(model:))
    }

    /// `hadReadFailure` is deliberately not persisted — only complete bundles
    /// are ever stored, so a loaded bundle is by construction failure-free.
    func toModel() -> WorkoutMetricSeriesData {
        WorkoutMetricSeriesData(
            bucketSeconds: bucketSeconds,
            startDate: startDate,
            endDate: endDate,
            bucketActiveSeconds: Self.intKeyed(bucketActiveSeconds),
            distanceMeters: Self.intKeyed(distanceMeters),
            steps: Self.intKeyed(steps),
            strideLengthMeters: strideLengthMeters?.toModel(),
            groundContactTimeMs: groundContactTimeMs?.toModel(),
            verticalOscillationCm: verticalOscillationCm?.toModel(),
            cyclingCadenceRPM: cyclingCadenceRPM?.toModel(),
            hadReadFailure: false
        )
    }

    private static func stringKeyed(_ values: [Int: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        result.reserveCapacity(values.count)
        for (key, value) in values {
            result[String(key)] = value
        }
        return result
    }

    /// Keys that don't parse back to `Int` are dropped: they can only come from
    /// a hand-edited or corrupt file, and a bucket index is the dictionary's
    /// only meaning.
    private static func intKeyed(_ values: [String: Double]) -> [Int: Double] {
        var result: [Int: Double] = [:]
        result.reserveCapacity(values.count)
        for (key, value) in values {
            guard let index = Int(key) else { continue }
            result[index] = value
        }
        return result
    }
}
