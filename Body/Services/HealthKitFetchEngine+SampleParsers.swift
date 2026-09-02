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

    /// Shared with the watch's delta re-query via `BodyHealthQuantityFetch` so
    /// both sides normalize a percentage read the same way.
    nonisolated static func normalizedPercentDisplayValue(_ value: Double) -> Double {
        BodyHealthQuantityFetch.normalizedPercent(value)
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
        showsSubMinuteAwakeStages: Bool = true,
        showsLeadingTrailingAwakeStages: Bool = true,
        timeZoneLedger: BodyTimeZoneLedger = BodyTimeZoneLedger()
    ) -> SleepSummary? {
        // Watch sleep samples carry no `HKMetadataKeyTimeZone`, so the shared
        // parser leaves the zone nil; the device time-zone ledger back-fills it
        // for the wake day so timezone-aware scoring can recognize a travel
        // night instead of always reading it in the current zone.
        BodySleepFetch.sleepSummary(
            from: samples,
            date: date,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
            showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages,
            timeZoneIdentifier: { timeZoneLedger.zoneIdentifier(on: $0) }
        )
    }

    nonisolated static func sleepStageSegments(
        from samples: [HKCategorySample],
        showsSubMinuteAwakeStages: Bool = true,
        showsLeadingTrailingAwakeStages: Bool = true
    ) -> [SleepStageSegment] {
        BodySleepSampleParser.sleepStageSegments(
            from: samples,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
            showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages
        )
    }

    // `HKWorkout` → `WorkoutSummary` mapping (and the activity-type switch it
    // uses) now lives in the shared `BodyWorkoutFetch` (Body + BodyWatch) so the
    // watch builds identical workout summaries; call sites use
    // `BodyWorkoutFetch.summary(...)` directly.
}
