//
//  HealthKitFetchEngine+SampleParsers.swift
//  Body
//

import Foundation
import HealthKit

// Static, pure-function helpers split out of `HealthKitFetchEngine.swift` so
// the engine's main file can focus on actor-isolated orchestration. Anything
// here is `nonisolated static` — no actor isolation, no HealthKit fetch
// orchestration, no `@Published` interaction. Helpers used outside this
// extension (called via `Self.foo` from the main engine file) are internal;
// helpers used only by other helpers in this extension stay `private`.
extension HealthKitFetchEngine {
    nonisolated static func activityDateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.calendar = calendar
        return components
    }

    nonisolated static func activityRingSummary(from summary: HKActivitySummary) -> ActivityRingSummary {
        ActivityRingSummary(
            move: ActivityRingMetric(
                value: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                goal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
            ),
            exercise: ActivityRingMetric(
                value: summary.appleExerciseTime.doubleValue(for: .minute()),
                goal: summary.appleExerciseTimeGoal.doubleValue(for: .minute())
            ),
            stand: ActivityRingMetric(
                value: summary.appleStandHours.doubleValue(for: .count()),
                goal: summary.appleStandHoursGoal.doubleValue(for: .count())
            )
        )
    }

    nonisolated static func normalizedPercentDisplayValue(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    nonisolated static func dailyQuantityValue(
        from samples: [HKQuantitySample],
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        valueTransform: (Double) -> Double
    ) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }

        switch aggregation {
        case .average:
            let values = samples
                .map { valueTransform($0.quantity.doubleValue(for: unit)) }
                .filter(\.isFinite)

            guard !values.isEmpty else {
                return nil
            }

            return values.reduce(0, +) / Double(values.count)
        case .latest:
            guard let sample = samples.max(by: { $0.endDate < $1.endDate }) else {
                return nil
            }

            let value = valueTransform(sample.quantity.doubleValue(for: unit))
            return value.isFinite ? value : nil
        }
    }

    // Sleep-sample parsing now lives in the shared `BodySleepSampleParser`
    // (Body + BodyWatch) so iOS and the watch build identical sleep inputs.
    // These keep their signatures as thin forwarders for callers + tests.
    nonisolated static func sleepSummary(
        from samples: [HKCategorySample],
        date: Date,
        showsSubMinuteAwakeStages: Bool = true
    ) -> SleepSummary? {
        BodySleepSampleParser.sleepSummary(
            from: samples,
            date: date,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages
        )
    }

    nonisolated static func isSleepTimelineSample(_ sample: HKCategorySample) -> Bool {
        BodySleepSampleParser.isSleepTimelineSample(sample)
    }

    nonisolated static func sleepStageSegments(
        from samples: [HKCategorySample],
        showsSubMinuteAwakeStages: Bool = true
    ) -> [SleepStageSegment] {
        BodySleepSampleParser.sleepStageSegments(
            from: samples,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages
        )
    }

    nonisolated static func summary(
        for workout: HKWorkout,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        effortLevel: Double? = nil,
        cardioFitnessVO2Max: Double? = nil,
        averageStepCadenceSPM: Double? = nil
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        let averageHeartRate = averageHeartRate(from: heartRateSamples)
        let type = HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType)

        return WorkoutSummary(
            id: workout.uuid,
            type: type,
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            averageHeartRateBeatsPerMinute: averageHeartRate,
            maximumHeartRateBeatsPerMinute: maximumHeartRate(from: heartRateSamples),
            effortLevel: effortLevel,
            heartRateSamples: downsampleHeartRateSamples(heartRateSamples),
            elevationAscendedMeters: elevationAscendedMeters(for: workout),
            averagePowerWatts: averagePowerWatts(for: workout, type: type),
            averageStepCadenceSPM: averageStepCadenceSPM,
            averageCyclingCadenceRPM: averageCyclingCadenceRPM(for: workout, type: type),
            swimmingStrokeCount: swimmingStrokeCount(for: workout, type: type),
            cardioFitnessVO2Max: cardioFitnessVO2Max,
            sourceName: workout.sourceRevision.source.name
        )
    }

    /// Summary for a workout whose heart-rate payload is reused from a cached
    /// summary (passive resumes; eligibility decided by
    /// `heartRateReuseEligibleWorkoutIDs`). Metadata comes fresh from the
    /// `HKWorkout`; the cached average + samples are copied verbatim — the
    /// cached average was computed from the raw samples *before* downsampling,
    /// so re-deriving it from the stored ≤96 samples would drift.
    nonisolated static func summary(
        for workout: HKWorkout,
        reusingHeartRateFrom cached: WorkoutSummary,
        effortLevel: Double? = nil,
        cardioFitnessVO2Max: Double? = nil,
        averageStepCadenceSPM: Double? = nil
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        let type = HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType)

        return WorkoutSummary(
            id: workout.uuid,
            type: type,
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            averageHeartRateBeatsPerMinute: cached.averageHeartRateBeatsPerMinute,
            maximumHeartRateBeatsPerMinute: cached.maximumHeartRateBeatsPerMinute,
            effortLevel: effortLevel,
            heartRateSamples: cached.heartRateSamples ?? [],
            elevationAscendedMeters: elevationAscendedMeters(for: workout),
            averagePowerWatts: averagePowerWatts(for: workout, type: type),
            averageStepCadenceSPM: averageStepCadenceSPM,
            averageCyclingCadenceRPM: averageCyclingCadenceRPM(for: workout, type: type),
            swimmingStrokeCount: swimmingStrokeCount(for: workout, type: type),
            cardioFitnessVO2Max: cardioFitnessVO2Max,
            sourceName: workout.sourceRevision.source.name
        )
    }

    nonisolated private static func activeEnergyKilocalories(for workout: HKWorkout) -> Double? {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        return workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    nonisolated private static func totalEnergyKilocalories(for workout: HKWorkout) -> Double? {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        guard let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
              let basalEnergy = workout.statistics(for: basalEnergyType)?
              .sumQuantity()?
              .doubleValue(for: .kilocalorie()) else {
            return activeEnergy
        }

        return (activeEnergy ?? 0) + basalEnergy
    }

    nonisolated private static func averageHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        let values = samples.map(\.beatsPerMinute).filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated private static func maximumHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        samples.map(\.beatsPerMinute).filter(\.isFinite).max()
    }

    nonisolated private static func elevationAscendedMeters(for workout: HKWorkout) -> Double? {
        (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
    }

    /// Average running/cycling power (W), best-effort from the workout's attached
    /// statistics — present only when the recording source accumulated it.
    nonisolated private static func averagePowerWatts(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        let identifier: HKQuantityTypeIdentifier
        if type.supportsRunningPower {
            identifier = .runningPower
        } else if type.paceStyle == .speed {
            identifier = .cyclingPower
        } else {
            return nil
        }
        return discreteAverage(for: workout, identifier: identifier, unit: .watt())
    }

    nonisolated private static func averageCyclingCadenceRPM(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        guard type.paceStyle == .speed else { return nil }
        return discreteAverage(
            for: workout,
            identifier: .cyclingCadence,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
    }

    nonisolated private static func swimmingStrokeCount(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        guard type.paceStyle == .swimPace,
              let strokeType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) else {
            return nil
        }
        return workout.statistics(for: strokeType)?.sumQuantity()?.doubleValue(for: .count())
    }

    nonisolated private static func discreteAverage(
        for workout: HKWorkout,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return workout.statistics(for: quantityType)?.averageQuantity()?.doubleValue(for: unit)
    }

    nonisolated private static func downsampleHeartRateSamples(
        _ samples: [WorkoutHeartRateSample],
        maximumCount: Int = 96
    ) -> [WorkoutHeartRateSample] {
        let sortedSamples = samples.sorted { $0.date < $1.date }
        guard sortedSamples.count > maximumCount, maximumCount > 1 else {
            return sortedSamples
        }

        let stride = Double(sortedSamples.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            sortedSamples[Int((Double(index) * stride).rounded())]
        }
    }
}
