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

    nonisolated static func sleepSummary(
        from samples: [HKCategorySample],
        date: Date,
        showsSubMinuteAwakeStages: Bool = true
    ) -> SleepSummary? {
        let duration = HealthKitWorkoutStore.sleepDuration(from: samples)
        guard duration > 0 else {
            return nil
        }

        return SleepSummary(
            duration: duration,
            stageSnapshot: SleepStageSnapshot(
                date: date,
                segments: sleepStageSegments(
                    from: samples,
                    showsSubMinuteAwakeStages: showsSubMinuteAwakeStages
                )
            )
        )
    }

    nonisolated static func isSleepTimelineSample(_ sample: HKCategorySample) -> Bool {
        isAsleep(sample) || sleepStage(for: sample, includeUnspecified: false) == .awake
    }

    nonisolated private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    nonisolated static func sleepStageSegments(
        from samples: [HKCategorySample],
        showsSubMinuteAwakeStages: Bool = true
    ) -> [SleepStageSegment] {
        let explicitSegments = samples.compactMap { sample -> SleepStageSegment? in
            guard let stage = sleepStage(for: sample, includeUnspecified: false) else {
                return nil
            }
            if !showsSubMinuteAwakeStages,
               stage == .awake,
               sample.endDate.timeIntervalSince(sample.startDate) < 60 {
                return nil
            }

            return SleepStageSegment(
                stage: stage,
                startDate: sample.startDate,
                endDate: sample.endDate
            )
        }
        let explicitIntervals = explicitSegments.map { segment in
            (start: segment.startDate, end: segment.endDate)
        }
        let unspecifiedSegments = samples.flatMap { sample -> [SleepStageSegment] in
            guard isUnspecifiedSleep(sample) else {
                return []
            }

            return uncoveredSleepIntervals(
                in: (start: sample.startDate, end: sample.endDate),
                coveredBy: explicitIntervals
            )
            .map { interval in
                SleepStageSegment(stage: .core, startDate: interval.start, endDate: interval.end)
            }
        }

        return (explicitSegments + unspecifiedSegments).sorted { $0.startDate < $1.startDate }
    }

    nonisolated private static func isUnspecifiedSleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    nonisolated private static func uncoveredSleepIntervals(
        in interval: (start: Date, end: Date),
        coveredBy coverageIntervals: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        guard interval.end > interval.start else {
            return []
        }

        var uncoveredIntervals = [interval]
        let sortedCoverageIntervals = coverageIntervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        for coverageInterval in sortedCoverageIntervals {
            uncoveredIntervals = uncoveredIntervals.flatMap { uncoveredInterval in
                guard coverageInterval.start < uncoveredInterval.end,
                      coverageInterval.end > uncoveredInterval.start else {
                    return [uncoveredInterval]
                }

                var nextIntervals: [(start: Date, end: Date)] = []
                if coverageInterval.start > uncoveredInterval.start {
                    nextIntervals.append((
                        start: uncoveredInterval.start,
                        end: min(coverageInterval.start, uncoveredInterval.end)
                    ))
                }
                if coverageInterval.end < uncoveredInterval.end {
                    nextIntervals.append((
                        start: max(coverageInterval.end, uncoveredInterval.start),
                        end: uncoveredInterval.end
                    ))
                }
                return nextIntervals.filter { $0.end > $0.start }
            }

            if uncoveredIntervals.isEmpty {
                return []
            }
        }

        return uncoveredIntervals
    }

    nonisolated private static func sleepStage(for sample: HKCategorySample, includeUnspecified: Bool) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .awake:
            return .awake
        case .asleepREM:
            return .rem
        case .asleepCore:
            return .core
        case .asleepDeep:
            return .deep
        case .asleep, .asleepUnspecified:
            return includeUnspecified ? .core : nil
        default:
            return nil
        }
    }

    nonisolated static func summary(
        for workout: HKWorkout,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        effortLevel: Double? = nil
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        let averageHeartRate = averageHeartRate(from: heartRateSamples)

        return WorkoutSummary(
            id: workout.uuid,
            type: HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType),
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            averageHeartRateBeatsPerMinute: averageHeartRate,
            effortLevel: effortLevel,
            heartRateSamples: downsampleHeartRateSamples(heartRateSamples),
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
        effortLevel: Double? = nil
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)

        return WorkoutSummary(
            id: workout.uuid,
            type: HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType),
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            averageHeartRateBeatsPerMinute: cached.averageHeartRateBeatsPerMinute,
            effortLevel: effortLevel,
            heartRateSamples: cached.heartRateSamples ?? [],
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
