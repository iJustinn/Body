//
//  ActivityReadinessImpact.swift
//  Body
//

import Foundation

/// Same-day acute "drain" that workouts apply to the **live** readiness tile.
///
/// This is intentionally separate from the readiness training-load component
/// (`ReadinessScoreCalculator`'s ACWR `strainModifier`), which is a multi-day
/// acute/chronic load ratio that barely moves the day a workout lands. The acute
/// drain is the same-day "I just trained" layer that ratio structurally misses —
/// the two model different things and are intentionally additive (the live score
/// is floored at 0 where they combine).
///
/// The drain is applied **only** to `summary.readiness` (today's tile). It is never
/// written into history/baselines: the recorded chart value is the frozen morning
/// score captured before any drain (see `HealthDashboardSnapshot.recalculatingReadiness`).
/// There is no time-decay — drain accumulates across the current wake cycle's
/// workouts and persists until the next morning's record resets it.
enum ActivityReadinessImpact {
    /// Largest drain a single maximal session can contribute (before the total cap).
    static let maxSingleWorkoutDrain = 40.0
    /// Saturation scale for `effectiveStrain` (minutes × effort × type weight).
    static let strainScale = 250.0
    /// Hard ceiling on the summed drain — caps "up to ~two status bands".
    static let totalDrainCap = 45.0
    /// Lowest score shown once same-day drain has pushed the raw score to zero.
    /// Below the floor the displayed value eases down instead of snapping to 0.
    static let displayFloor = 5
    /// Raw-score deficit that removes one displayed point below the floor.
    static let displayEaseStep = 5

    /// Total readiness points to subtract from the live score for the given workouts.
    /// Callers pass only the current wake cycle's post-wake workouts.
    static func drainPoints(workouts: [WorkoutSummary]) -> Double {
        let total = workouts.reduce(0.0) { $0 + perWorkoutDrain($1) }
        return min(totalDrainCap, total)
    }

    /// Maps the raw drained score (baseline − drain, which may be negative once the
    /// drain exceeds the baseline) onto a softened displayed value. A raw score of 0
    /// maps to `displayFloor` (5) instead of a demoralizing 0; each further
    /// `displayEaseStep` (5) points of deficit removes one displayed point, so the
    /// value reaches 0 only at −25 or lower. Raw scores at or above the floor are
    /// returned unchanged.
    ///
    /// - Note: Callers cap the result at the undrained score so an already-low baseline
    ///   is never lifted above where it started (see `HealthDashboardSnapshot.draining`).
    static func displayedScore(forRawScore raw: Int) -> Int {
        guard raw < displayFloor else { return raw }
        let deficit = max(0, -raw)
        return max(0, displayFloor - deficit / displayEaseStep)
    }

    /// Drain contributed by one workout: a saturating function of its effective
    /// strain (`durationMinutes × effort × typeWeight`).
    static func perWorkoutDrain(_ workout: WorkoutSummary) -> Double {
        guard workout.duration.isFinite, workout.duration > 0 else {
            return 0
        }

        let durationMinutes = workout.duration / 60
        let effectiveStrain = durationMinutes * estimatedEffort(for: workout) * typeWeight(workout.type)
        guard effectiveStrain.isFinite, effectiveStrain > 0 else {
            return 0
        }

        return maxSingleWorkoutDrain * (1 - exp(-effectiveStrain / strainScale))
    }

    /// Effort on the same 1...10 scale the UI uses. Prefers the saved effort score;
    /// when absent, estimates from the metrics we have (average HR, then active
    /// energy rate), falling back to the neutral default.
    static func estimatedEffort(for workout: WorkoutSummary) -> Double {
        if let effort = workout.effortLevel, effort.isFinite {
            return clampedEffort(effort)
        }

        var estimate: Double?
        if let averageHeartRate = workout.averageHeartRateBeatsPerMinute, averageHeartRate.isFinite {
            estimate = (averageHeartRate - 90) / 9
        }
        if workout.duration > 0,
           let activeEnergy = workout.activeEnergyKilocalories,
           activeEnergy.isFinite {
            let kilocaloriesPerMinute = activeEnergy / (workout.duration / 60)
            let energyEstimate = kilocaloriesPerMinute - 2
            estimate = max(estimate ?? energyEstimate, energyEstimate)
        }

        guard let estimate else {
            return TrainingLoadCalculator.defaultEffortLevel
        }
        return clampedEffort(estimate)
    }

    /// How much a given activity drains systemic readiness per unit of load.
    /// Grouped by modality; the long tail of sports falls through to `0.80`.
    static func typeWeight(_ type: BodyWorkoutType) -> Double {
        switch type {
        case .yoga, .pilates, .taiChi, .mindAndBody, .flexibility, .barre,
             .walking, .wheelchairWalkPace, .golf, .bowling, .archery, .curling,
             .fishing, .cooldown, .preparationAndReadiness:
            return 0.40
        case .running, .hiit, .jumpRope, .kickboxing, .boxing, .stairClimbing,
             .stairs, .crossCountrySkiing, .rowing, .cycling, .swimming,
             .mixedCardio, .mixedMetabolicCardioTraining:
            return 1.20
        case .strengthTraining, .functionalStrengthTraining, .coreTraining:
            return 1.00
        default:
            return 0.80
        }
    }

    private static func clampedEffort(_ effort: Double) -> Double {
        min(max(effort, 1), 10)
    }
}
