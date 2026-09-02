//
//  WatchComputeDelta.swift
//  Body
//
//  What one watch delta run read, in the shape `WatchComputeAssembly` splices
//  onto the phone seed. Lives in the kit with the assembly (rather than beside
//  the `WatchDeltaFetcher` that produces it) so the phone's test target can
//  build one and drive the real assembly with it.
//

import Foundation

/// One latest-sample reading with the sample's own measurement time — the real
/// watermark the compute stamps onto the metric it feeds (never `Date()`).
struct WatchDeltaSample {
    let value: Double
    let measuredAt: Date
}

/// Everything one delta run read, in the shape `WatchComputeCoordinator`
/// splices onto the seed. Every field defaults to the seed-preserving value, so
/// a permission-off or unresolved-source kind simply never gets written.
struct WatchComputeDelta {
    var heartRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var restingHeartRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var heartRateVariabilitySeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var respiratoryRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var oxygenSaturationSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var wristTemperatureSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var sleepNights: WatchFetchOutcome<[SleepDaySummary]> = .failure
    var workouts: WatchFetchOutcome<[WorkoutSummary]> = .failure

    var heartRateSample: WatchDeltaSample?
    var restingHeartRateSample: WatchDeltaSample?
    var heartRateVariabilitySample: WatchDeltaSample?

    /// The most recent night assembled this run (the phone's `fetchSleepSummary`
    /// picks the same one: the grouping with the latest stage date). Whether it
    /// still counts as TODAY's night is decided by `SleepSummary.asOf` in the
    /// snapshot builder, exactly as on the phone.
    var latestNight: SleepSummary?
}
