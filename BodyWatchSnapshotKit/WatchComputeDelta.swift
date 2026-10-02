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
    /// The Heart Rate and HRV week charts' daily min/max capsules
    /// (`trends.heartRateRanges` / `heartRateVariabilityRanges`). Display only:
    /// deliberately NOT readiness inputs (`WatchComputeAssembly.readinessBlockers`),
    /// so a failed range read keeps the seed's capsules and never blocks a score.
    var heartRateRanges: WatchFetchOutcome<HealthTrendRangeSeries> = .failure
    var heartRateVariabilityRanges: WatchFetchOutcome<HealthTrendRangeSeries> = .failure
    var respiratoryRateSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var oxygenSaturationSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var wristTemperatureSeries: WatchFetchOutcome<HealthTrendSeries> = .failure
    var sleepNights: WatchFetchOutcome<[SleepDaySummary]> = .failure
    var workouts: WatchFetchOutcome<[WorkoutSummary]> = .failure

    /// Stress's intraday inputs over whole days (`WatchDeltaFetcher`'s Stress
    /// window: today, plus yesterday when the last 12 hours reach into it), in
    /// the shape of the phone's day-sample series: raw heart rate and SDNN
    /// samples, RMSSD points (Recovery HRV, or one per heartbeat series), and
    /// hourly step and active energy sums. Stress is stamped only when every
    /// permitted one succeeded (`WatchComputeAssembly.dataAsOf`).
    var stressHeartRateSamples: WatchFetchOutcome<HealthTrendSeries> = .failure
    var stressSDNNSamples: WatchFetchOutcome<HealthTrendSeries> = .failure
    var stressRMSSDSamples: WatchFetchOutcome<HealthTrendSeries> = .failure
    var stressHourlySteps: WatchFetchOutcome<HealthTrendSeries> = .failure
    var stressHourlyActiveEnergy: WatchFetchOutcome<HealthTrendSeries> = .failure

    /// The Steps, Active Energy and Resting Energy cards' trailing week of
    /// daily totals (`WatchDeltaFetcher`'s fixed week: today and the six days
    /// before it, one point per day with a sum), read by the watch alone:
    /// there is no seeded history for these kinds (the seed collapses their
    /// series to `.empty`), so a successful read replaces the series wholesale
    /// and feeds both the card's headline (today's point) and its 7 day bars.
    /// Stamped in `WatchComputeAssembly.dataAsOf` only on success, so a failed
    /// read is never adopted over what the card shows.
    var stepsWeek: WatchFetchOutcome<HealthTrendSeries> = .failure
    var activeEnergyWeek: WatchFetchOutcome<HealthTrendSeries> = .failure
    var restingEnergyWeek: WatchFetchOutcome<HealthTrendSeries> = .failure

    /// Source kinds this watch holds no HealthKit source for at all
    /// (`WatchSourceRead.unavailable`). Their series stay `.failure`, so the
    /// seed is preserved, but they do not block Readiness.
    var carriedKinds: Set<HealthMetricKind> = []

    var heartRateSample: WatchDeltaSample?
    var restingHeartRateSample: WatchDeltaSample?
    var heartRateVariabilitySample: WatchDeltaSample?

    /// The most recent night assembled this run (the phone's `fetchSleepSummary`
    /// picks the same one: the grouping with the latest stage date). Whether it
    /// still counts as TODAY's night is decided by `SleepSummary.asOf` in the
    /// snapshot builder, exactly as on the phone.
    var latestNight: SleepSummary?
}
