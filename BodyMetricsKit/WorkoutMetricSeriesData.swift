//
//  WorkoutMetricSeriesData.swift
//  BodyMetricsKit
//
//  Raw per-bucket inputs for the workout detail's time-series charts (pace or
//  speed, cadence, stride length, ground contact time, vertical oscillation), as
//  read from HealthKit in one pass by
//  `HealthKitFetchEngine.workoutMetricSeriesData(workoutID:)`. Buckets are fixed
//  `bucketSeconds`-wide wall-clock windows anchored at `startDate`; `index` is
//  0-based from the workout start. Every quantity is in its canonical HealthKit
//  unit (meters, count, ms, cm, rpm); unit choice belongs to the presentation.
//

import Foundation

struct WorkoutMetricSeriesData: Equatable {
    /// One bucket of discrete statistics for a natively recorded metric.
    struct NativeBucket: Equatable {
        let index: Int
        let average: Double
        let minimum: Double
        let maximum: Double
    }

    /// A natively recorded metric's buckets plus its session-wide discrete
    /// average / maximum (nil when HealthKit carries no session statistics).
    struct NativeSeries: Equatable {
        let buckets: [NativeBucket]
        let sessionAverage: Double?
        let sessionMax: Double?
    }

    let bucketSeconds: TimeInterval
    let startDate: Date
    /// HealthKit's wall-clock workout end (includes paused time).
    let endDate: Date
    /// Seconds of each bucket window that overlap the workout's *active* time
    /// (pause/resume events removed, clamped to `endDate`), so a paused stretch
    /// or a short final bucket divides by its real duration. Buckets with no
    /// active time are absent.
    let bucketActiveSeconds: [Int: Double]
    /// HealthKit-deduplicated cumulative distance (meters) per bucket.
    let distanceMeters: [Int: Double]
    /// HealthKit-deduplicated cumulative step count per bucket (stepping activities).
    let steps: [Int: Double]
    /// `runningStrideLength`, meters (running only).
    let strideLengthMeters: NativeSeries?
    /// `runningGroundContactTime`, milliseconds (running only).
    let groundContactTimeMs: NativeSeries?
    /// `runningVerticalOscillation`, centimeters (running only).
    let verticalOscillationCm: NativeSeries?
    /// `cyclingCadence`, revolutions per minute (cycling only).
    let cyclingCadenceRPM: NativeSeries?
    /// True when at least one metric's read failed (that metric is nil, the
    /// others are still valid). The store must not cache such a bundle.
    let hadReadFailure: Bool

    static let empty = WorkoutMetricSeriesData(
        bucketSeconds: 0,
        startDate: Date(timeIntervalSince1970: 0),
        endDate: Date(timeIntervalSince1970: 0),
        bucketActiveSeconds: [:],
        distanceMeters: [:],
        steps: [:],
        strideLengthMeters: nil,
        groundContactTimeMs: nil,
        verticalOscillationCm: nil,
        cyclingCadenceRPM: nil,
        hadReadFailure: false
    )
}
