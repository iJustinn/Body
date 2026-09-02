//
//  WorkoutEffortEstimator.swift
//  Body
//

import Foundation

/// Predicts a workout's effort on the same 1...10 scale the user rates on, so the
/// effort editor can pre-fill a suggestion for unrated workouts. Deterministic and
/// explainable by design: `raw = base + durationModifier + intraSessionBump +
/// calibrationBias + readinessModifier`, clamped to 1...10.
///
/// A small "effort family" layer (`effortFamily(for:)`) tailors the HR paths to two
/// workout types whose average HR systematically understates effort. `.strength`
/// (inter-set rest) and `.gravity` (snowboarding/downhill lift rides) blend a robust
/// working-peak fraction into the base, and `.strength` further replaces the zone bump
/// with a set-density bump that counts work/rest cycles (falling back to the zone bump
/// when the samples are too coarse). Every other type is `.standard` and scores exactly
/// as before, bit-for-bit. Confidence tiers are intentionally left unchanged — a
/// strength-specific cap would delay `.high` for exactly the users this helps.
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

    /// Groups workout types that share a scoring quirk on the HR paths: strength
    /// training's inter-set rest depresses average HR, and gravity sports' lift rides
    /// do the same while effort tracks duration more directly. `.standard` reproduces
    /// today's behavior bit-for-bit.
    enum EffortFamily: Equatable {
        case strength
        case gravity
        case standard
    }

    /// `.workoutProfile` is always `.low` (no HR data to lean on). HR-based bases
    /// (`.heartRateReserve`, `.percentMaxHeartRate`) are `.low` until the 30-day
    /// comparison history is fully loaded — the score may still shift once it lands —
    /// then `.medium`, or `.high` once calibration is active.
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
    /// `.gravity` duration curve: +1.0 per hour past `longSessionMinutes`, capped.
    static let gravityDurationRatePerHour = 1.0
    static let gravityDurationCap = 3.0
    /// Peak-blend base (strength/gravity): the base fraction is a 50/50 mix of the
    /// average fraction and the higher of average vs. working-peak fraction.
    static let peakBlendWeight = 0.5
    /// Working peak = mean of the top 20% of HR samples by bpm.
    static let peakSampleShare = 0.2
    /// Below this many HR samples the blend is skipped (base is average-only).
    static let minimumSamplesForPeakBlend = 8
    /// Strength set-density bump: work/rest cycles are counted via a ±`setHysteresisBPM`
    /// hysteresis band and rewarded at `setDensitySlope` per set/min above the floor,
    /// capped at `setDensityBumpLimit`.
    static let setDensityBumpLimit = 1.5
    static let setHysteresisBPM = 5.0
    static let setDensityFloorSetsPerMinute = 0.1
    static let setDensitySlope = 3.75
    /// Above this median inter-sample interval the crossing count is too coarse to trust.
    static let maxSampleIntervalForSetDetection: TimeInterval = 90
    static let readinessHardDayThreshold = 40
    static let readinessEasyDayThreshold = 85

    // MARK: - Effort family

    /// Deliberately narrow: `.crossCountrySkiing` stays `.standard` (steady-state
    /// endurance); generic `.snowSports` stays `.standard` (nothing proves lift-based
    /// downhill behavior for it); racquet/team sports stay `.standard`.
    static func effortFamily(for type: BodyWorkoutType) -> EffortFamily {
        switch type {
        case .strengthTraining, .functionalStrengthTraining, .coreTraining:
            return .strength
        case .snowboarding, .downhillSkiing:
            return .gravity
        default:
            return .standard
        }
    }

    // MARK: - Estimate

    /// nil only for pathological input (non-finite or non-positive duration); every
    /// other workout gets a suggestion, degrading through the fallback path.
    static func estimate(for input: Input) -> Estimate? {
        let workout = input.workout
        guard workout.duration.isFinite, workout.duration > 0 else {
            return nil
        }

        let durationMinutes = workout.duration / 60
        let family = effortFamily(for: workout.type)
        let basis = resolveBasis(for: workout, input: input)
        let (base, baseFraction) = baseScore(for: workout, basis: basis, input: input)
        var raw = base + durationModifier(durationMinutes: durationMinutes, family: family)

        // `.strength` prefers the set-density bump (it needs no max HR, so it applies on
        // every basis including `.workoutProfile`); when its guards fail it returns nil and
        // strength falls back to the zone bump like everything else.
        let strengthBump = family == .strength ? setDensityBump(for: workout) : nil
        if let strengthBump {
            raw += strengthBump
        } else if basis != .workoutProfile {
            raw += zoneBump(for: workout, basis: basis, baseFraction: baseFraction, input: input)
        }
        if basis == .workoutProfile, input.isHistoryComplete {
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
            if input.isHistoryComplete {
                confidence = calibrationActive ? .high : .medium
            } else {
                // Calibration inputs weren't loaded, so this score may shift once the
                // 30-day history lands — low confidence keeps auto-apply from writing it.
                confidence = .low
            }
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
    /// `.gravity` (snowboarding/downhill skiing) uses a steeper curve: lift rides
    /// depress average HR, so effort tracks total time on the mountain more directly.
    static func durationModifier(durationMinutes: Double, family: EffortFamily = .standard) -> Double {
        switch family {
        case .gravity:
            if durationMinutes < shortSessionMinutes {
                return -0.5
            }
            if durationMinutes > longSessionMinutes {
                return min(gravityDurationCap, (durationMinutes - longSessionMinutes) / 60 * gravityDurationRatePerHour)
            }
            return 0
        case .strength, .standard:
            if durationMinutes < shortSessionMinutes {
                return -0.5
            }
            if durationMinutes > longSessionMinutes {
                return min(1.5, (durationMinutes - longSessionMinutes) / 60 * 0.5)
            }
            return 0
        }
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
        case .snowboarding, .downhillSkiing:
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

    /// Returns the base score and the intensity fraction it scored — `fraction` is nil
    /// on the `.workoutProfile` path (no HR) and when HR is present but unscorable.
    /// `zoneBump` reuses `fraction` as its baseline so the peak blend and the bump can't
    /// credit the same hard samples twice.
    private static func baseScore(for workout: WorkoutSummary, basis: Basis, input: Input) -> (score: Double, fraction: Double?) {
        switch basis {
        case .workoutProfile:
            return (fallbackTypeAnchor(for: workout.type), nil)
        case .heartRateReserve, .percentMaxHeartRate:
            guard let averageHeartRate = positive(averageHeartRate(for: workout)),
                  let avgFraction = intensityFraction(
                    beatsPerMinute: averageHeartRate,
                    basis: basis,
                    input: input
                  ) else {
                return (fallbackTypeAnchor(for: workout.type), nil)
            }
            let fraction = blendedBaseFraction(
                avgFraction: avgFraction,
                workout: workout,
                basis: basis,
                input: input
            )
            return (anchorScore(fraction: fraction, basis: basis), fraction)
        }
    }

    /// Strength/gravity families blend the average fraction with a robust working-peak
    /// fraction, because inter-set rest and lift rides depress average HR below the true
    /// working intensity. `.standard` returns the average fraction untouched (today's
    /// base, bit-for-bit). The `max` guard means a flat session never scores below its
    /// average-only base, and fewer than `minimumSamplesForPeakBlend` samples skips the
    /// blend entirely.
    private static func blendedBaseFraction(
        avgFraction: Double,
        workout: WorkoutSummary,
        basis: Basis,
        input: Input
    ) -> Double {
        let samples = workout.heartRateSamples
        guard effortFamily(for: workout.type) != .standard,
              let peakHeartRate = workingPeakHeartRate(samples: samples),
              let peakFraction = intensityFraction(beatsPerMinute: peakHeartRate, basis: basis, input: input) else {
            return avgFraction
        }
        return peakBlendWeight * avgFraction
            + (1 - peakBlendWeight) * max(avgFraction, peakFraction)
    }

    /// Working peak: the mean of the top `peakSampleShare` of samples by bpm (at least
    /// 3), robust to single spikes. nil below `minimumSamplesForPeakBlend` samples.
    private static func workingPeakHeartRate(samples: [WorkoutHeartRateSample]) -> Double? {
        guard samples.count >= minimumSamplesForPeakBlend else {
            return nil
        }
        let sorted = samples.map(\.beatsPerMinute).sorted(by: >)
        let count = max(3, Int((Double(sorted.count) * peakSampleShare).rounded()))
        let top = sorted.prefix(count)
        guard !top.isEmpty else {
            return nil
        }
        return top.reduce(0, +) / Double(top.count)
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

    /// How much the hard parts exceeded the base fraction, weighted by how long they
    /// lasted — so interval sessions (whose base understates the work) get credit while
    /// steady sessions at any intensity get ~0 (their hard-parts mean ≈ the base
    /// fraction, avoiding double counting on top of `base`). The baseline is the same
    /// fraction `baseScore` used, so a family peak blend and this bump can't credit the
    /// same hard samples twice.
    private static func zoneBump(for workout: WorkoutSummary, basis: Basis, baseFraction: Double?, input: Input) -> Double {
        let samples = workout.heartRateSamples
        guard let baseFraction,
              let maxHeartRate = positive(input.userMaxHeartRate),
              let zones = WorkoutHeartRateZones.zones(samples: samples, maxHeartRate: maxHeartRate) else {
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
            - anchorScore(fraction: baseFraction, basis: basis)
        return min(zoneBumpLimit, max(0, gap * hardShare))
    }

    // MARK: - Set-density bump

    /// Strength sessions live and die by set-to-set intensity swings, which average HR
    /// erases. A hysteresis state machine counts work/rest cycles from the HR samples and
    /// rewards denser sessions. Needs no max HR, so it works even on the `.workoutProfile`
    /// basis. Returns nil — so the caller falls back to `zoneBump` — when the samples are
    /// too few, the session too short, or the sampling too coarse to trust the count.
    private static func setDensityBump(for workout: WorkoutSummary) -> Double? {
        let samples = workout.heartRateSamples
        guard samples.count >= minimumSamplesForPeakBlend else {
            return nil
        }
        let durationMinutes = workout.duration / 60
        guard durationMinutes >= 10 else {
            return nil
        }

        let sorted = samples.sorted { $0.date < $1.date }
        let intervals = zip(sorted, sorted.dropFirst()).map { $1.date.timeIntervalSince($0.date) }
        guard let median = medianInterval(intervals),
              median <= maxSampleIntervalForSetDetection else {
            return nil
        }

        // Midline is the retained samples' own mean, not `displayedAverageHeartRate`: the
        // stored average is drawn from the full pre-downsample series, a different
        // population that would systematically skew the crossing count.
        let bpms = sorted.map(\.beatsPerMinute)
        let midline = bpms.reduce(0, +) / Double(bpms.count)
        let highThreshold = midline + setHysteresisBPM
        let lowThreshold = midline - setHysteresisBPM

        var setCount = 0
        var isHigh = false
        for bpm in bpms {
            if !isHigh, bpm >= highThreshold {
                isHigh = true
                setCount += 1
            } else if isHigh, bpm <= lowThreshold {
                isHigh = false
            }
        }

        let setsPerMinute = Double(setCount) / durationMinutes
        return min(setDensityBumpLimit, max(0, (setsPerMinute - setDensityFloorSetsPerMinute) * setDensitySlope))
    }

    private static func medianInterval(_ intervals: [TimeInterval]) -> TimeInterval? {
        guard !intervals.isEmpty else {
            return nil
        }
        let sorted = intervals.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
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
            let priorFamily = effortFamily(for: prior.workout.type)
            let core = baseScore(for: prior.workout, basis: basis, input: input).score
                + durationModifier(durationMinutes: prior.workout.duration / 60, family: priorFamily)
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
