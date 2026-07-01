//
//  WorkoutEffortEstimator.swift
//  Body
//

import Foundation

/// Predicts a workout's effort on the same 1...10 scale the user rates on, so the
/// effort editor can pre-fill a suggestion for unrated workouts. Deterministic and
/// explainable by design: `raw = base + durationModifier + zoneBump + calibrationBias
/// + readinessModifier`, clamped to 1...10.
///
/// Personal baselines over universal thresholds: the primary path scores average HR
/// as a fraction of the user's heart-rate reserve (resting → age-estimated max), and
/// a calibration step nudges toward the user's own past self-ratings. Ratings that
/// were themselves accepted suggestions are excluded from calibration (see
/// `Input.suggestionAcceptedWorkoutIDs`) so the estimator never trains on its own
/// output. Intentionally separate from `ActivityReadinessImpact.estimatedEffort`,
/// which is a cruder universal estimate feeding readiness drain.
enum WorkoutEffortEstimator {
    struct Input {
        let workout: WorkoutSummary
        /// Age-estimated max HR (220 − age); nil when date of birth is unavailable.
        let userMaxHeartRate: Double?
        /// Resting HR (bpm) on or near the workout day; nil when unavailable.
        let restingHeartRate: Double?
        /// Workouts of any type in the 30 days before this one, from loaded months.
        let priorWorkouts: [WorkoutSummary]
        /// Session-saved rating overlay (`workoutEffortOverrides`); wins over the
        /// baked `effortLevel`, which only catches up on the next refresh.
        let priorRatingOverrides: [UUID: Double]
        /// Workouts whose saved rating was an accepted suggestion, excluded from
        /// calibration so the estimator can't learn from itself.
        let suggestionAcceptedWorkoutIDs: Set<UUID>
        /// False while any spanned month is still loading — history-derived parts
        /// (calibration, fallback deltas) are skipped rather than computed on a
        /// partial window.
        let isHistoryComplete: Bool
        /// Frozen morning readiness (0–100) for the workout's day, if recorded.
        let morningReadiness: Int?

        init(
            workout: WorkoutSummary,
            userMaxHeartRate: Double? = nil,
            restingHeartRate: Double? = nil,
            priorWorkouts: [WorkoutSummary] = [],
            priorRatingOverrides: [UUID: Double] = [:],
            suggestionAcceptedWorkoutIDs: Set<UUID> = [],
            isHistoryComplete: Bool = true,
            morningReadiness: Int? = nil
        ) {
            self.workout = workout
            self.userMaxHeartRate = userMaxHeartRate
            self.restingHeartRate = restingHeartRate
            self.priorWorkouts = priorWorkouts
            self.priorRatingOverrides = priorRatingOverrides
            self.suggestionAcceptedWorkoutIDs = suggestionAcceptedWorkoutIDs
            self.isHistoryComplete = isHistoryComplete
            self.morningReadiness = morningReadiness
        }
    }

    enum Basis: Equatable {
        case heartRateReserve
        case percentMaxHeartRate
        case workoutProfile
    }

    enum Confidence: Equatable {
        case high
        case medium
        case low
    }

    struct Estimate: Equatable {
        /// The 1...10 suggestion shown in the editor.
        let score: Int
        /// Pre-rounding value, already clamped to 1...10.
        let rawScore: Double
        let basis: Basis
        let confidence: Confidence
        /// Applied calibration bias; 0 when fewer than `minimumRatedPriorCount`
        /// eligible rated priors exist.
        let calibrationBias: Double
    }

    // MARK: - Constants

    /// Piecewise-linear anchors (fraction of heart-rate reserve → score), aligned with
    /// `WorkoutEffortPresentation` bands: Easy <4, Moderate <7, Hard <9, All Out ≥9.
    static let heartRateReserveAnchors: [(fraction: Double, score: Double)] = [
        (0.35, 1.0), (0.55, 3.5), (0.72, 6.5), (0.85, 8.5), (0.95, 10.0)
    ]
    /// Anchors for the %-of-max-HR path used when no plausible resting HR exists.
    static let percentMaxAnchors: [(fraction: Double, score: Double)] = [
        (0.55, 1.0), (0.68, 3.5), (0.80, 6.5), (0.89, 8.5), (0.96, 10.0)
    ]
    static let minimumRatedPriorCount = 3
    static let calibrationBiasLimit = 2.0
    static let zoneBumpLimit = 1.0
    /// Resting HR outside this band is treated as bad data → %maxHR path.
    static let plausibleRestingHeartRateRange = 30.0...100.0
    /// Minimum reserve (max − resting) for HRR math to be meaningful.
    static let minimumHeartRateReserve = 20.0
    static let shortSessionMinutes = 15.0
    static let longSessionMinutes = 45.0
    static let readinessHardDayThreshold = 40
    static let readinessEasyDayThreshold = 85

    // MARK: - Estimate

    /// nil only for pathological input (non-finite or non-positive duration); every
    /// other workout gets a suggestion, degrading through the fallback path.
    static func estimate(for input: Input) -> Estimate? {
        let workout = input.workout
        guard workout.duration.isFinite, workout.duration > 0 else {
            return nil
        }

        let durationMinutes = workout.duration / 60
        let basis = resolveBasis(for: workout, input: input)
        let base = baseScore(for: workout, basis: basis, input: input)
        var raw = base + durationModifier(durationMinutes: durationMinutes)

        if basis != .workoutProfile {
            raw += zoneBump(for: workout, basis: basis, input: input)
        } else if input.isHistoryComplete {
            raw += fallbackIntensityDelta(for: workout, priors: input.priorWorkouts)
        }

        var calibrationBias = 0.0
        var calibrationActive = false
        if input.isHistoryComplete {
            if let bias = self.calibrationBias(for: workout, input: input) {
                calibrationBias = bias
                calibrationActive = true
                raw += bias
            }
        }

        if let readiness = input.morningReadiness {
            if readiness < readinessHardDayThreshold {
                raw += 0.5
            } else if readiness > readinessEasyDayThreshold {
                raw -= 0.5
            }
        }

        guard raw.isFinite else {
            return nil
        }

        let clamped = min(max(raw, 1), 10)
        let confidence: Confidence
        switch basis {
        case .workoutProfile:
            confidence = .low
        case .heartRateReserve, .percentMaxHeartRate:
            confidence = calibrationActive ? .high : .medium
        }

        return Estimate(
            score: min(max(Int(clamped.rounded()), 1), 10),
            rawScore: clamped,
            basis: basis,
            confidence: confidence,
            calibrationBias: calibrationBias
        )
    }

    // MARK: - Base score

    /// Maps a heart-rate-reserve fraction to a 1...10 score via the HRR anchors.
    static func heartRateReserveScore(fraction: Double) -> Double {
        interpolatedScore(fraction: fraction, anchors: heartRateReserveAnchors)
    }

    /// Maps an average-HR-as-fraction-of-max to a 1...10 score via the %max anchors.
    static func percentMaxScore(fraction: Double) -> Double {
        interpolatedScore(fraction: fraction, anchors: percentMaxAnchors)
    }

    /// Session-RPE grows with time: a hard half hour and a hard two hours are not the
    /// same effort. Small penalty for very short sessions, +0.5 per hour past 45 min.
    static func durationModifier(durationMinutes: Double) -> Double {
        if durationMinutes < shortSessionMinutes {
            return -0.5
        }
        if durationMinutes > longSessionMinutes {
            return min(1.5, (durationMinutes - longSessionMinutes) / 60 * 0.5)
        }
        return 0
    }

    /// Baseline effort by modality when no HR is available. Groupings intentionally
    /// mirror `ActivityReadinessImpact.typeWeight` but this is its own table — effort
    /// anchors shouldn't silently move if readiness-drain weights are retuned.
    static func fallbackTypeAnchor(for type: BodyWorkoutType) -> Double {
        switch type {
        case .yoga, .pilates, .taiChi, .mindAndBody, .flexibility, .barre,
             .walking, .wheelchairWalkPace, .golf, .bowling, .archery, .curling,
             .fishing, .cooldown, .preparationAndReadiness:
            return 3.0
        case .running, .hiit, .jumpRope, .kickboxing, .boxing, .stairClimbing,
             .stairs, .crossCountrySkiing, .rowing, .cycling, .swimming,
             .mixedCardio, .mixedMetabolicCardioTraining:
            return 7.0
        case .strengthTraining, .functionalStrengthTraining, .coreTraining:
            return 6.0
        default:
            return 5.0
        }
    }

    private static func resolveBasis(for workout: WorkoutSummary, input: Input) -> Basis {
        guard positive(averageHeartRate(for: workout)) != nil,
              let maxHeartRate = positive(input.userMaxHeartRate),
              maxHeartRate >= 100 else {
            return .workoutProfile
        }

        if let resting = positive(input.restingHeartRate),
           plausibleRestingHeartRateRange.contains(resting),
           maxHeartRate - resting >= minimumHeartRateReserve {
            return .heartRateReserve
        }
        return .percentMaxHeartRate
    }

    private static func baseScore(for workout: WorkoutSummary, basis: Basis, input: Input) -> Double {
        switch basis {
        case .workoutProfile:
            return fallbackTypeAnchor(for: workout.type)
        case .heartRateReserve, .percentMaxHeartRate:
            guard let averageHeartRate = positive(averageHeartRate(for: workout)),
                  let fraction = intensityFraction(
                    beatsPerMinute: averageHeartRate,
                    basis: basis,
                    input: input
                  ) else {
                return fallbackTypeAnchor(for: workout.type)
            }
            return anchorScore(fraction: fraction, basis: basis)
        }
    }

    /// The same average the detail tile shows: stored average, else the sample mean.
    private static func averageHeartRate(for workout: WorkoutSummary) -> Double? {
        WorkoutMetricComparisonBuilder.displayedAverageHeartRate(for: workout)
    }

    private static func anchorScore(fraction: Double, basis: Basis) -> Double {
        basis == .heartRateReserve
            ? heartRateReserveScore(fraction: fraction)
            : percentMaxScore(fraction: fraction)
    }

    /// Converts a bpm value to the basis' intensity fraction (HRR% or %maxHR).
    private static func intensityFraction(
        beatsPerMinute: Double,
        basis: Basis,
        input: Input
    ) -> Double? {
        guard let maxHeartRate = positive(input.userMaxHeartRate) else {
            return nil
        }
        switch basis {
        case .heartRateReserve:
            guard let resting = positive(input.restingHeartRate),
                  maxHeartRate - resting >= minimumHeartRateReserve else {
                return nil
            }
            return (beatsPerMinute - resting) / (maxHeartRate - resting)
        case .percentMaxHeartRate:
            return beatsPerMinute / maxHeartRate
        case .workoutProfile:
            return nil
        }
    }

    private static func interpolatedScore(
        fraction: Double,
        anchors: [(fraction: Double, score: Double)]
    ) -> Double {
        guard fraction.isFinite, let first = anchors.first, let last = anchors.last else {
            return 1
        }
        if fraction <= first.fraction {
            return first.score
        }
        if fraction >= last.fraction {
            return last.score
        }
        for index in 1..<anchors.count {
            let upper = anchors[index]
            guard fraction <= upper.fraction else { continue }
            let lower = anchors[index - 1]
            let progress = (fraction - lower.fraction) / (upper.fraction - lower.fraction)
            return lower.score + progress * (upper.score - lower.score)
        }
        return last.score
    }

    // MARK: - Zone bump

    /// How much the hard parts exceeded the session average, weighted by how long they
    /// lasted — so interval sessions (whose average understates the work) get credit
    /// while steady sessions at any intensity get ~0 (their hard-parts mean ≈ the
    /// session mean, avoiding double counting on top of `base`).
    private static func zoneBump(for workout: WorkoutSummary, basis: Basis, input: Input) -> Double {
        guard let maxHeartRate = positive(input.userMaxHeartRate),
              let samples = workout.heartRateSamples,
              let zones = WorkoutHeartRateZones.zones(samples: samples, maxHeartRate: maxHeartRate),
              let sessionAverage = positive(averageHeartRate(for: workout)),
              let sessionFraction = intensityFraction(beatsPerMinute: sessionAverage, basis: basis, input: input) else {
            return 0
        }

        let hardShare = zones
            .filter { $0.zone >= 4 }
            .reduce(0) { $0 + $1.fraction }
        guard hardShare > 0 else {
            return 0
        }

        // Classify samples with the same threshold zones() uses for zone 4.
        let hardThreshold = Double(Int((maxHeartRate * WorkoutHeartRateZones.lowerBoundFractions[3]).rounded()))
        let hardSamples = samples.filter { $0.beatsPerMinute >= hardThreshold }
        guard !hardSamples.isEmpty else {
            return 0
        }
        let hardMean = hardSamples.reduce(0) { $0 + $1.beatsPerMinute } / Double(hardSamples.count)
        guard let hardFraction = intensityFraction(beatsPerMinute: hardMean, basis: basis, input: input) else {
            return 0
        }

        let gap = anchorScore(fraction: hardFraction, basis: basis)
            - anchorScore(fraction: sessionFraction, basis: basis)
        return min(zoneBumpLimit, max(0, gap * hardShare))
    }

    // MARK: - Fallback personal intensity delta

    /// No-HR path: how this workout's output compares to the user's same-type recent
    /// history. Energy rate first; raw speed only when energy is unavailable. Speed is
    /// always meters/second — never display pace — so "faster = harder" keeps the right
    /// sign for pace-style types too.
    private static func fallbackIntensityDelta(for workout: WorkoutSummary, priors: [WorkoutSummary]) -> Double {
        let sameType = priors.filter { $0.type == workout.type }

        if let delta = energyRateDelta(for: workout, priors: sameType) {
            return delta
        }
        return speedDelta(for: workout, priors: sameType) ?? 0
    }

    private static func energyRateDelta(for workout: WorkoutSummary, priors: [WorkoutSummary]) -> Double? {
        guard let rate = energyRate(for: workout) else {
            return nil
        }
        let priorRates = priors.compactMap(energyRate(for:))
        guard priorRates.count >= minimumRatedPriorCount else {
            return nil
        }
        let mean = priorRates.reduce(0, +) / Double(priorRates.count)
        guard mean > 0 else {
            return nil
        }
        return min(max(4 * (rate / mean - 1), -2), 2)
    }

    private static func energyRate(for workout: WorkoutSummary) -> Double? {
        guard workout.duration.isFinite, workout.duration > 0,
              let energy = positive(workout.activeEnergyKilocalories) else {
            return nil
        }
        return energy / (workout.duration / 60)
    }

    private static func speedDelta(for workout: WorkoutSummary, priors: [WorkoutSummary]) -> Double? {
        guard let floor = speedDistanceFloor(for: workout.type),
              let speed = speed(for: workout, distanceFloor: floor) else {
            return nil
        }

        // Aggregate ratio of totals, mirroring WorkoutMetricComparisonBuilder: a mean
        // of per-workout speeds would let a short workout weigh the same as a long one.
        var totalDistance = 0.0
        var totalDuration = 0.0
        var count = 0
        for prior in priors {
            guard let distance = prior.distanceMeters, distance >= floor,
                  prior.duration.isFinite, prior.duration > 0 else {
                continue
            }
            totalDistance += distance
            totalDuration += prior.duration
            count += 1
        }
        guard count >= minimumRatedPriorCount, totalDistance > 0, totalDuration > 0 else {
            return nil
        }
        let aggregateSpeed = totalDistance / totalDuration
        guard aggregateSpeed > 0 else {
            return nil
        }
        return min(max(6 * (speed / aggregateSpeed - 1), -2), 2)
    }

    private static func speedDistanceFloor(for type: BodyWorkoutType) -> Double? {
        switch type.paceStyle {
        case .swimPace:
            return WorkoutMetricComparisonBuilder.minComparableSwimDistanceMeters
        case .distancePace, .speed:
            return WorkoutMetricComparisonBuilder.minComparableDistanceMeters
        case .none:
            return nil
        }
    }

    private static func speed(for workout: WorkoutSummary, distanceFloor: Double) -> Double? {
        guard let distance = workout.distanceMeters, distance >= distanceFloor,
              workout.duration.isFinite, workout.duration > 0 else {
            return nil
        }
        return distance / workout.duration
    }

    // MARK: - Calibration

    /// "Learns your scale": the mean gap between the user's past self-ratings and what
    /// the core formula would have scored those workouts, clamped to ±2. Same-type
    /// priors preferred; any-type as fallback. Priors whose rating was an accepted
    /// suggestion are excluded (no feedback loop). `core(prior)` is base + duration
    /// only — no zone bump or fallback deltas — so it's cheap and order-independent.
    private static func calibrationBias(for workout: WorkoutSummary, input: Input) -> Double? {
        let rated = ratedPriors(input: input)
        let sameType = rated.filter { $0.workout.type == workout.type }
        let pool = sameType.count >= minimumRatedPriorCount ? sameType : rated
        guard pool.count >= minimumRatedPriorCount else {
            return nil
        }

        let gaps = pool.map { prior -> Double in
            let basis = resolveBasis(for: prior.workout, input: input)
            let core = baseScore(for: prior.workout, basis: basis, input: input)
                + durationModifier(durationMinutes: prior.workout.duration / 60)
            return prior.rating - core
        }
        let bias = gaps.reduce(0, +) / Double(gaps.count)
        guard bias.isFinite else {
            return nil
        }
        return min(max(bias, -calibrationBiasLimit), calibrationBiasLimit)
    }

    private static func ratedPriors(input: Input) -> [(workout: WorkoutSummary, rating: Double)] {
        input.priorWorkouts.compactMap { prior in
            guard prior.duration.isFinite, prior.duration > 0,
                  !input.suggestionAcceptedWorkoutIDs.contains(prior.id),
                  let rating = input.priorRatingOverrides[prior.id] ?? prior.effortLevel,
                  rating.isFinite else {
                return nil
            }
            return (prior, min(max(rating, 1), 10))
        }
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}
