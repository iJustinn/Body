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
    var metricSeries: PersistedWorkoutMetricSeries?
    var heartRateRecoveryBPM: Double?

    init(
        schemaVersion: Int? = WorkoutDetailSnapshot.currentSchemaVersion,
        workoutID: UUID,
        route: PersistedWorkoutRoute? = nil,
        metricSeries: PersistedWorkoutMetricSeries? = nil,
        heartRateRecoveryBPM: Double? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.workoutID = workoutID
        self.route = route
        self.metricSeries = metricSeries
        self.heartRateRecoveryBPM = heartRateRecoveryBPM
    }

    /// True when the snapshot carries nothing worth keeping on disk.
    var isEmpty: Bool {
        route == nil && metricSeries == nil && heartRateRecoveryBPM == nil
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
