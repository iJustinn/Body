//
//  WorkoutEffortEstimatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutEffortEstimatorTests: XCTestCase {
    /// 190 max − 50 resting = 140 reserve, so HRR fractions map to clean bpm values.
    private let maxHR = 190.0
    private let restHR = 50.0

    private func workout(
        id: UUID = UUID(),
        type: BodyWorkoutType = .running,
        start: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval = 1800,
        distance: Double? = nil,
        activeEnergy: Double? = nil,
        avgHR: Double? = nil,
        effortLevel: Double? = nil,
        hrSamples: [WorkoutHeartRateSample] = []
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            type: type,
            startDate: start,
            duration: duration,
            activeEnergyKilocalories: activeEnergy,
            distanceMeters: distance,
            averageHeartRateBeatsPerMinute: avgHR,
            effortLevel: effortLevel,
            heartRateSamples: hrSamples
        )
    }

    private func hrSamples(_ values: [Double]) -> [WorkoutHeartRateSample] {
        values.enumerated().map {
            WorkoutHeartRateSample(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double($0.offset)),
                beatsPerMinute: $0.element
            )
        }
    }

    /// Samples spaced `interval` seconds apart, so set-density guards on median
    /// inter-sample spacing can be exercised.
    private func timedSamples(_ values: [Double], interval: TimeInterval) -> [WorkoutHeartRateSample] {
        values.enumerated().map {
            WorkoutHeartRateSample(
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double($0.offset) * interval),
                beatsPerMinute: $0.element
            )
        }
    }

    private func estimate(
        _ workout: WorkoutSummary,
        maxHeartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        priors: [WorkoutSummary] = [],
        overrides: [UUID: Double] = [:],
        accepted: Set<UUID> = [],
        isComplete: Bool = true,
        readiness: Int? = nil
    ) -> WorkoutEffortEstimator.Estimate? {
        WorkoutEffortEstimator.estimate(for: WorkoutEffortEstimator.Input(
            workout: workout,
            userMaxHeartRate: maxHeartRate,
            restingHeartRate: restingHeartRate,
            priorWorkouts: priors,
            priorRatingOverrides: overrides,
            suggestionAcceptedWorkoutIDs: accepted,
            isHistoryComplete: isComplete,
            morningReadiness: readiness
        ))
    }

    /// bpm producing the given heart-rate-reserve fraction under maxHR/restHR.
    private func bpm(hrrFraction: Double) -> Double {
        restHR + hrrFraction * (maxHR - restHR)
    }

    // MARK: - Anchor mappings

    func testHeartRateReserveAnchorScores() {
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.35), 1.0)
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.55), 3.5)
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.72), 6.5)
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.85), 8.5)
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.95), 10.0)
    }

    func testHeartRateReserveInterpolatesAndClampsAtEnds() {
        // Midpoint of (0.35 → 1.0) and (0.55 → 3.5).
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.45), 2.25, accuracy: 1e-9)
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 0.10), 1.0)
        XCTAssertEqual(WorkoutEffortEstimator.heartRateReserveScore(fraction: 1.20), 10.0)
    }

    func testPercentMaxAnchorScores() {
        XCTAssertEqual(WorkoutEffortEstimator.percentMaxScore(fraction: 0.55), 1.0)
        XCTAssertEqual(WorkoutEffortEstimator.percentMaxScore(fraction: 0.80), 6.5)
        XCTAssertEqual(WorkoutEffortEstimator.percentMaxScore(fraction: 0.96), 10.0)
        // Midpoint of (0.55 → 1.0) and (0.68 → 3.5).
        XCTAssertEqual(WorkoutEffortEstimator.percentMaxScore(fraction: 0.615), 2.25, accuracy: 1e-9)
    }

    // MARK: - Path selection

    func testUsesHeartRateReservePathWhenAllInputsPlausible() {
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(result?.basis, .heartRateReserve)
        XCTAssertEqual(result?.rawScore ?? 0, 6.5, accuracy: 1e-9)
        XCTAssertEqual(result?.confidence, .medium)
    }

    func testFallsBackToPercentMaxWithoutRestingHeartRate() {
        let result = estimate(workout(avgHR: 0.80 * maxHR), maxHeartRate: maxHR)
        XCTAssertEqual(result?.basis, .percentMaxHeartRate)
        XCTAssertEqual(result?.rawScore ?? 0, 6.5, accuracy: 1e-9)
    }

    func testImplausibleRestingHeartRateUsesPercentMaxPath() {
        let tooLow = estimate(workout(avgHR: 150), maxHeartRate: maxHR, restingHeartRate: 20)
        XCTAssertEqual(tooLow?.basis, .percentMaxHeartRate)

        let tooHigh = estimate(workout(avgHR: 150), maxHeartRate: maxHR, restingHeartRate: 120)
        XCTAssertEqual(tooHigh?.basis, .percentMaxHeartRate)
    }

    func testNoMaxHeartRateUsesWorkoutProfilePath() {
        let result = estimate(workout(avgHR: 150))
        XCTAssertEqual(result?.basis, .workoutProfile)
        XCTAssertEqual(result?.confidence, .low)
    }

    func testNoHeartRateDataUsesWorkoutProfilePath() {
        let result = estimate(workout(), maxHeartRate: maxHR, restingHeartRate: restHR)
        XCTAssertEqual(result?.basis, .workoutProfile)
    }

    // MARK: - Fallback type anchors

    func testFallbackTypeAnchors() {
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .yoga), 3.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .walking), 3.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .running), 7.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .hiit), 7.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .strengthTraining), 6.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .tennis), 5.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .snowboarding), 6.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .downhillSkiing), 6.0)
        XCTAssertEqual(WorkoutEffortEstimator.fallbackTypeAnchor(for: .snowSports), 5.0)
    }

    func testWorkoutProfileScoreIsTypeAnchorPlusDurationModifier() {
        let result = estimate(workout(type: .yoga, duration: 1800))
        XCTAssertEqual(result?.rawScore ?? 0, 3.0, accuracy: 1e-9)
        XCTAssertEqual(result?.score, 3)
    }

    // MARK: - Duration modifier

    func testDurationModifierValues() {
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 10), -0.5)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 15), 0)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 45), 0)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 105), 0.5, accuracy: 1e-9)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 400), 1.5)
    }

    func testDurationModifierGravityCurve() {
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 14, family: .gravity), -0.5)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 30, family: .gravity), 0)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 105, family: .gravity), 1.0, accuracy: 1e-9)
        XCTAssertEqual(WorkoutEffortEstimator.durationModifier(durationMinutes: 300, family: .gravity), 3.0)
    }

    // MARK: - Effort family

    func testEffortFamilyMapping() {
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .strengthTraining), .strength)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .functionalStrengthTraining), .strength)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .coreTraining), .strength)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .snowboarding), .gravity)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .downhillSkiing), .gravity)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .running), .standard)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .crossCountrySkiing), .standard)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .snowSports), .standard)
        XCTAssertEqual(WorkoutEffortEstimator.effortFamily(for: .tennis), .standard)
    }

    func testGravityDurationCapAndSnowboardNoHRFullDay() {
        // No HR → workoutProfile basis, anchor 6.0; 5 h duration hits the gravity cap
        // of +3.0 → raw 9, low confidence.
        let result = estimate(workout(type: .snowboarding, duration: 5 * 3600))
        XCTAssertEqual(result?.basis, .workoutProfile)
        XCTAssertEqual(result?.rawScore ?? 0, 9.0, accuracy: 1e-9)
        XCTAssertEqual(result?.confidence, .low)
    }

    // MARK: - Zone bump

    func testSteadyHighHeartRateSessionGetsNoZoneBump() {
        // All samples in zone 4 at the same bpm: the hard-parts mean equals the session
        // mean, so the bump must be ~0 — the average already priced the intensity in.
        let steadySamples = hrSamples(Array(repeating: 160.0, count: 200))
        let withSamples = estimate(
            workout(avgHR: nil, hrSamples: steadySamples),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let withoutSamples = estimate(
            workout(avgHR: 160),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(
            withSamples?.rawScore ?? -1,
            withoutSamples?.rawScore ?? 1,
            accuracy: 1e-9
        )
    }

    func testIntervalSessionScoresAboveSteadyEquivalentAndBumpIsCapped() throws {
        // 100 easy samples (120 bpm, zone 2) then 100 hard (180 bpm, zone 5): session
        // mean 150 but half the time near max. The gap × share exceeds the cap, so the
        // interval workout lands exactly +1.0 above its sample-free equivalent.
        let intervalSamples = hrSamples(
            Array(repeating: 120.0, count: 100) + Array(repeating: 180.0, count: 100)
        )
        let interval = estimate(
            workout(avgHR: nil, hrSamples: intervalSamples),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let steadyEquivalent = estimate(
            workout(avgHR: 150),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let intervalRaw = try XCTUnwrap(interval?.rawScore)
        let steadyRaw = try XCTUnwrap(steadyEquivalent?.rawScore)
        XCTAssertEqual(intervalRaw - steadyRaw, 1.0, accuracy: 1e-9)
    }

    func testStandardFamilyScoresUnchanged() {
        // Regression pin: a running (`.standard`) workout with zone-4 time exercises the
        // zoneBump path. Its base fraction is the plain average (no peak blend) and the
        // zoneBump baseline is that same fraction, so the score is byte-identical to the
        // pre-change formula. 180×120 bpm (zone 2) + 20×180 bpm (zone 4+): session mean
        // 126 → base 3.4107…; uncapped zoneBump 0.5984… → raw 4.0091….
        let samples = hrSamples(Array(repeating: 120.0, count: 180) + Array(repeating: 180.0, count: 20))
        let result = estimate(
            workout(type: .running, avgHR: nil, hrSamples: samples),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(result?.rawScore ?? 0, 4.009152907394113, accuracy: 1e-9)
    }

    func testZoneBumpMeasuredAgainstBlendedBase() {
        // Snowboarding (`.gravity`) with oscillating 95/155 samples: the base fraction is
        // the peak blend (0.6428…), and zoneBump measures the hard samples against that
        // blended baseline — not the lower average — so the riding peaks aren't credited
        // twice. base 5.1386… + gravity duration (+0.75 at 90 min) + bump 0.9068… =
        // 6.7955…. A regressed average baseline would cap the bump at 1.0 → 6.8886….
        let osc = (0..<200).map { $0 % 2 == 0 ? 95.0 : 155.0 }
        let result = estimate(
            workout(type: .snowboarding, duration: 5400, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(result?.rawScore ?? 0, 6.795516853823091, accuracy: 1e-9)
    }

    // MARK: - Peak-blend base

    func testStrengthPeakBlendRaisesBaseAboveAverageOnly() {
        // Oscillating 95/155 bpm strength samples: the working peak (155) lifts the base
        // fraction above the plain average (blended base 5.1386…), and the dense set
        // structure adds the capped +1.5 set-density bump → 6.6386…. Either way the
        // strength score exceeds the identical session scored as `.standard` (average-only
        // base + zone bump).
        let osc = (0..<200).map { $0 % 2 == 0 ? 95.0 : 155.0 }
        let strength = estimate(
            workout(type: .strengthTraining, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let averageOnly = estimate(
            workout(type: .running, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(strength?.rawScore ?? 0, 6.638655462184873, accuracy: 1e-9)
        XCTAssertGreaterThan(strength?.rawScore ?? 0, averageOnly?.rawScore ?? 0)
    }

    func testPeakBlendNeverLowersBase() {
        // Flat 130 bpm samples: the working peak equals the average, so the `max` guard
        // keeps the blended base identical to the average-only base (no samples).
        let flat = estimate(
            workout(type: .strengthTraining, avgHR: nil, hrSamples: hrSamples(Array(repeating: 130.0, count: 200))),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let averageOnly = estimate(
            workout(type: .strengthTraining, avgHR: 130),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(flat?.rawScore ?? 0, averageOnly?.rawScore ?? -1, accuracy: 1e-9)
    }

    func testStrengthWithoutSamplesDegradesToAverageOnly() {
        // Stored average HR but no samples: the blend is skipped, so the strength base
        // is the plain average — identical to the same average scored as `.standard`.
        let strength = estimate(
            workout(type: .strengthTraining, avgHR: 130),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let standard = estimate(
            workout(type: .running, avgHR: 130),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(strength?.rawScore ?? 0, 3.8781512605042003, accuracy: 1e-9)
        XCTAssertEqual(strength?.rawScore ?? 0, standard?.rawScore ?? -1, accuracy: 1e-9)
    }

    // MARK: - Set-density bump

    func testSetDensityBumpCountsHysteresisCrossings() {
        // 40 min, 12 work/rest cycles (samples every 50 s): 12 sets / 40 min = 0.3 sets/min
        // → (0.3 − 0.1) × 3.75 = +0.75. No max HR → workoutProfile basis, so the base is the
        // strength anchor 6.0 and the set bump applies regardless → 6.75.
        let cycles = Array(repeating: [100.0, 100.0, 160.0, 160.0], count: 12).flatMap { $0 }
        let moderate = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: nil, hrSamples: timedSamples(cycles, interval: 50))
        )
        XCTAssertEqual(moderate?.basis, .workoutProfile)
        XCTAssertEqual(moderate?.rawScore ?? 0, 6.75, accuracy: 1e-9)

        // 24 cycles / 40 min = 0.6 sets/min → (0.6 − 0.1) × 3.75 = 1.875, capped at +1.5.
        let dense = Array(repeating: [100.0, 160.0], count: 24).flatMap { $0 }
        let capped = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: nil, hrSamples: timedSamples(dense, interval: 50))
        )
        XCTAssertEqual(capped?.rawScore ?? 0, 7.5, accuracy: 1e-9)
    }

    func testSetDensityBumpUsesSampleMeanMidline() {
        // Stored average HR is 200, but the retained samples average 130. Crossings must be
        // counted against the sample mean (130 ± 5), not the stored average — a 200 midline
        // would see no sample reach 205 and count 0 sets. 12 sets / 40 min → +0.75 → 6.75.
        let cycles = Array(repeating: [110.0, 110.0, 150.0, 150.0], count: 12).flatMap { $0 }
        let result = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: 200, hrSamples: timedSamples(cycles, interval: 50))
        )
        XCTAssertEqual(result?.rawScore ?? 0, 6.75, accuracy: 1e-9)
    }

    func testSetDensityBumpIgnoresSubHysteresisNoise() {
        // ±3 bpm wobble around the mean stays inside the ±5 hysteresis band, so the state
        // machine counts no sets and the bump is 0 (rawScore is the bare strength anchor).
        let wobble = Array(repeating: [127.0, 133.0], count: 40).flatMap { $0 }
        let result = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: nil, hrSamples: timedSamples(wobble, interval: 30))
        )
        XCTAssertEqual(result?.rawScore ?? 0, 6.0, accuracy: 1e-9)
    }

    func testSetDensityBumpSkipsCoarseSampling() {
        // 120 s spacing → median inter-sample interval exceeds 90 s, so setDensityBump
        // returns nil and strength falls back to zoneBump — scoring identically to the same
        // samples on a gravity workout (which always uses zoneBump) at a duration where both
        // curves add 0.
        let values = (0..<20).map { $0 % 2 == 0 ? 120.0 : 180.0 }
        let coarseStrength = estimate(
            workout(type: .strengthTraining, duration: 2280, avgHR: nil, hrSamples: timedSamples(values, interval: 120)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let gravityEquivalent = estimate(
            workout(type: .snowboarding, duration: 2280, avgHR: nil, hrSamples: timedSamples(values, interval: 120)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(coarseStrength?.rawScore ?? 0, gravityEquivalent?.rawScore ?? -1, accuracy: 1e-9)

        // The same samples at 30 s spacing pass the guard, so setDensityBump replaces the
        // zone bump and the score changes.
        let fineStrength = estimate(
            workout(type: .strengthTraining, duration: 2280, avgHR: nil, hrSamples: timedSamples(values, interval: 30)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertNotEqual(fineStrength?.rawScore ?? 0, coarseStrength?.rawScore ?? 0, accuracy: 1e-9)
    }

    func testSetDensityBumpHandlesUnsortedSamples() {
        // Samples arrive out of date order; setDensityBump sorts by date first, so a reversed
        // array counts the same crossings (and same sample mean) as the ordered one.
        let cycles = Array(repeating: [100.0, 100.0, 160.0, 160.0], count: 12).flatMap { $0 }
        let ordered = timedSamples(cycles, interval: 50)
        let orderedResult = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: nil, hrSamples: ordered)
        )
        let shuffledResult = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: nil, hrSamples: ordered.reversed())
        )
        XCTAssertEqual(orderedResult?.rawScore ?? 0, 6.75, accuracy: 1e-9)
        XCTAssertEqual(shuffledResult?.rawScore ?? 0, orderedResult?.rawScore ?? -1, accuracy: 1e-9)
    }

    func testStrengthNoMaxHeartRateStillGetsSetBump() {
        // No date of birth → no max HR → workoutProfile basis (today those samples would be
        // ignored entirely). setDensityBump needs no max HR, so the strength set structure
        // still lifts the score above the bare anchor (6.0 + 0.75).
        let cycles = Array(repeating: [100.0, 100.0, 160.0, 160.0], count: 12).flatMap { $0 }
        let result = estimate(
            workout(type: .strengthTraining, duration: 2400, avgHR: nil, hrSamples: timedSamples(cycles, interval: 50))
        )
        XCTAssertEqual(result?.basis, .workoutProfile)
        XCTAssertEqual(result?.confidence, .low)
        XCTAssertEqual(result?.rawScore ?? 0, 6.75, accuracy: 1e-9)
    }

    func testStrengthUsesSetBumpNotZoneBump() {
        // Identical oscillating samples on HR basis: strength routes through setDensityBump
        // (dense sets → capped +1.5) while gravity routes through zoneBump (+0.9069). The
        // blended base and 0 duration modifier are identical, so the score difference is
        // exactly the bump difference — proving strength does not use the zone bump.
        let osc = (0..<200).map { $0 % 2 == 0 ? 95.0 : 155.0 }
        let strength = estimate(
            workout(type: .strengthTraining, duration: 1800, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        let gravity = estimate(
            workout(type: .snowboarding, duration: 1800, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(strength?.rawScore ?? 0, 6.638655462184873, accuracy: 1e-9)
        XCTAssertEqual(gravity?.rawScore ?? 0, 6.045516853823091, accuracy: 1e-9)
        XCTAssertGreaterThan(strength?.rawScore ?? 0, gravity?.rawScore ?? 0)
    }

    // MARK: - Fallback personal intensity deltas

    func testEnergyRateDeltaAgainstSameTypePriors() {
        // 10 kcal/min vs an 8 kcal/min prior mean → 4 × 25% = +1.0 on the type anchor.
        let priors = (0..<3).map { _ in workout(type: .strengthTraining, activeEnergy: 240) }
        let result = estimate(
            workout(type: .strengthTraining, activeEnergy: 300),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 7.0, accuracy: 1e-9)
    }

    func testEnergyRateDeltaIsClamped() {
        let priors = (0..<3).map { _ in workout(type: .strengthTraining, activeEnergy: 240) }
        let result = estimate(
            workout(type: .strengthTraining, activeEnergy: 960),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 8.0, accuracy: 1e-9) // 6 + clamp(+2)
    }

    func testEnergyRateDeltaNeedsThreePriors() {
        let priors = (0..<2).map { _ in workout(type: .strengthTraining, activeEnergy: 240) }
        let result = estimate(
            workout(type: .strengthTraining, activeEnergy: 300),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 6.0, accuracy: 1e-9)
    }

    func testFasterRunProducesPositiveSpeedDelta() {
        // Pace-style type: current 3.33 m/s vs 2.78 m/s aggregate → +20% speed → +1.2.
        // Computing on raw speed keeps the sign right even though runs display pace.
        let priors = (0..<3).map { _ in workout(type: .running, duration: 1800, distance: 5000) }
        let result = estimate(
            workout(type: .running, duration: 1500, distance: 5000),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 8.2, accuracy: 1e-9)
    }

    func testFasterCycleProducesPositiveSpeedDelta() {
        let priors = (0..<3).map { _ in workout(type: .cycling, duration: 2250, distance: 20000) }
        let result = estimate(
            workout(type: .cycling, duration: 1800, distance: 20000),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 8.5, accuracy: 1e-9) // 7 + clamp(6 × 25%)
    }

    func testRunBelowDistanceFloorGetsNoSpeedDelta() {
        let priors = (0..<3).map { _ in workout(type: .running, duration: 1800, distance: 5000) }
        let result = estimate(
            workout(type: .running, duration: 1500, distance: 350),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 7.0, accuracy: 1e-9)
    }

    func testSwimHonorsLowerDistanceFloor() {
        // 150 m clears the 100 m swim floor (a run would need 400 m). Same +20% speed.
        let priors = (0..<3).map { _ in workout(type: .swimming, duration: 180, distance: 150) }
        let result = estimate(
            workout(type: .swimming, duration: 150, distance: 150),
            priors: priors
        )
        let anchor = WorkoutEffortEstimator.fallbackTypeAnchor(for: .swimming)
        // duration 150 s = 2.5 min → short-session −0.5; delta 6 × 20% = +1.2.
        XCTAssertEqual(result?.rawScore ?? 0, anchor - 0.5 + 1.2, accuracy: 1e-9)
    }

    func testEnergyDeltaWinsOverSpeedDelta() {
        // Both energy and distance present: energy is the primary signal, so the
        // (larger) speed delta must not stack or replace it.
        let priors = (0..<3).map { _ in
            workout(type: .running, duration: 1800, distance: 5000, activeEnergy: 240)
        }
        let result = estimate(
            workout(type: .running, duration: 1800, distance: 9000, activeEnergy: 300),
            priors: priors
        )
        XCTAssertEqual(result?.rawScore ?? 0, 8.0, accuracy: 1e-9) // 7 + energy(+1), not speed(+2)
    }

    // MARK: - Calibration

    private func ratedPrior(type: BodyWorkoutType = .running, rating: Double?) -> WorkoutSummary {
        workout(type: type, avgHR: bpm(hrrFraction: 0.72), effortLevel: rating)
    }

    func testCalibrationLearnsUserScaleFromSameTypePriors() {
        // Priors' core is 6.5 but the user rated them 8 → bias +1.5 nudges the current
        // (identical) workout from 6.5 to 8.0.
        let priors = (0..<3).map { _ in ratedPrior(rating: 8) }
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors
        )
        XCTAssertEqual(result?.calibrationBias ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(result?.rawScore ?? 0, 8.0, accuracy: 1e-9)
        XCTAssertEqual(result?.confidence, .high)
    }

    func testCalibrationBiasIsClamped() {
        let priors = (0..<3).map { _ in ratedPrior(rating: 10) } // gap 3.5 each
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors
        )
        XCTAssertEqual(result?.calibrationBias ?? 0, 2.0, accuracy: 1e-9)
    }

    func testCalibrationFallsBackToAnyTypePriors() {
        let priors = (0..<3).map { _ in ratedPrior(type: .cycling, rating: 8) }
        let result = estimate(
            workout(type: .running, avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors
        )
        XCTAssertEqual(result?.calibrationBias ?? 0, 1.5, accuracy: 1e-9)
    }

    func testSessionOverridesWinOverBakedRatings() {
        // Baked effortLevel says 4 but the user re-rated to 8 this session; the overlay
        // must drive the bias until the next refresh bakes it in.
        let priors = (0..<3).map { _ in ratedPrior(rating: 4) }
        let overrides = Dictionary(uniqueKeysWithValues: priors.map { ($0.id, 8.0) })
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors,
            overrides: overrides
        )
        XCTAssertEqual(result?.calibrationBias ?? 0, 1.5, accuracy: 1e-9)
    }

    func testSuggestionAcceptedPriorsAreExcludedFromCalibration() {
        // All three rated priors were accepted suggestions → no usable history, so the
        // estimator must not learn from its own output (bias 0, confidence medium).
        let priors = (0..<3).map { _ in ratedPrior(rating: 8) }
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors,
            accepted: Set(priors.map(\.id))
        )
        XCTAssertEqual(result?.calibrationBias ?? -1, 0)
        XCTAssertEqual(result?.confidence, .medium)
    }

    func testPriorCountsAgainOnceRemovedFromAcceptedSet() {
        let priors = (0..<3).map { _ in ratedPrior(rating: 8) }
        let excluded = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors,
            accepted: Set(priors.map(\.id))
        )
        let restored = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors,
            accepted: []
        )
        XCTAssertEqual(excluded?.calibrationBias ?? -1, 0)
        XCTAssertEqual(restored?.calibrationBias ?? 0, 1.5, accuracy: 1e-9)
    }

    func testFewerThanThreeRatedPriorsMeansNoBias() {
        let priors = (0..<2).map { _ in ratedPrior(rating: 8) } + [ratedPrior(rating: nil)]
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors
        )
        XCTAssertEqual(result?.calibrationBias ?? -1, 0)
        XCTAssertEqual(result?.confidence, .medium)
    }

    func testCalibrationUsesFamilyAwareCore() {
        // Strength priors rated 7, with oscillating samples so the family-aware core
        // (peak blend) scores them higher than the old average-only core. The learned
        // bias is measured against that same higher core, so it is immediately smaller
        // than the (clamped) bias the average-only core would have produced.
        let osc = (0..<200).map { $0 % 2 == 0 ? 95.0 : 155.0 }
        func priors(type: BodyWorkoutType) -> [WorkoutSummary] {
            (0..<3).map { _ in workout(type: type, avgHR: nil, effortLevel: 7, hrSamples: hrSamples(osc)) }
        }
        let strength = estimate(
            workout(type: .strengthTraining, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors(type: .strengthTraining)
        )
        let averageOnly = estimate(
            workout(type: .running, avgHR: nil, hrSamples: hrSamples(osc)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors(type: .running)
        )
        XCTAssertEqual(strength?.calibrationBias ?? 0, 1.8613445378151274, accuracy: 1e-9)
        XCTAssertEqual(averageOnly?.calibrationBias ?? 0, 2.0, accuracy: 1e-9)
        XCTAssertLessThan(strength?.calibrationBias ?? 0, averageOnly?.calibrationBias ?? 0)
    }

    // MARK: - Incomplete history gating

    func testIncompleteHistorySkipsCalibrationAndConfidenceIsLow() {
        let priors = (0..<3).map { _ in ratedPrior(rating: 8) }
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors,
            isComplete: false
        )
        XCTAssertEqual(result?.calibrationBias ?? -1, 0)
        XCTAssertEqual(result?.confidence, .low)
        XCTAssertEqual(result?.rawScore ?? 0, 6.5, accuracy: 1e-9)
    }

    func testIncompleteHistorySkipsFallbackDeltas() {
        let priors = (0..<3).map { _ in workout(type: .strengthTraining, activeEnergy: 240) }
        let result = estimate(
            workout(type: .strengthTraining, activeEnergy: 300),
            priors: priors,
            isComplete: false
        )
        XCTAssertEqual(result?.rawScore ?? 0, 6.0, accuracy: 1e-9)
    }

    // MARK: - Readiness modifier

    func testLowReadinessAddsHalfPoint() {
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            readiness: 35
        )
        XCTAssertEqual(result?.rawScore ?? 0, 7.0, accuracy: 1e-9)
    }

    func testHighReadinessSubtractsHalfPoint() {
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            readiness: 90
        )
        XCTAssertEqual(result?.rawScore ?? 0, 6.0, accuracy: 1e-9)
    }

    func testMidRangeOrMissingReadinessLeavesScoreAlone() {
        let mid = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            readiness: 60
        )
        let none = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(mid?.rawScore ?? 0, 6.5, accuracy: 1e-9)
        XCTAssertEqual(none?.rawScore ?? 0, 6.5, accuracy: 1e-9)
    }

    // MARK: - Clamping, rounding, degenerate input

    func testVeryEasyShortWorkoutClampsToOne() {
        // Base 1.0 − 0.5 short-session penalty → raw 0.5 clamps to 1.
        let result = estimate(
            workout(duration: 600, avgHR: bpm(hrrFraction: 0.10)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR
        )
        XCTAssertEqual(result?.rawScore, 1.0)
        XCTAssertEqual(result?.score, 1)
    }

    func testMaximalWorkoutClampsToTen() {
        // Base 10 + low-readiness bump → raw 10.5 clamps to 10.
        let result = estimate(
            workout(avgHR: maxHR),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            readiness: 35
        )
        XCTAssertEqual(result?.rawScore, 10.0)
        XCTAssertEqual(result?.score, 10)
    }

    func testDegenerateDurationsReturnNil() {
        XCTAssertNil(estimate(workout(duration: 0), maxHeartRate: maxHR))
        XCTAssertNil(estimate(workout(duration: -300), maxHeartRate: maxHR))
        XCTAssertNil(estimate(workout(duration: .nan), maxHeartRate: maxHR))
        XCTAssertNil(estimate(workout(duration: .infinity), maxHeartRate: maxHR))
    }

    func testNonFiniteMetricFieldsAreIgnoredNotFatal() {
        let result = estimate(
            workout(type: .strengthTraining, activeEnergy: .nan, avgHR: .infinity)
        )
        XCTAssertEqual(result?.basis, .workoutProfile)
        XCTAssertEqual(result?.rawScore ?? 0, 6.0, accuracy: 1e-9)
    }

    // MARK: - HealthTrendSeries.latestValue

    private var calendar: Calendar { .bodyGregorian }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)))!
    }

    func testLatestValueFindsExactDayPoint() {
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: day(0), value: 50),
            HealthTrendDataPoint(date: day(4), value: 55)
        ])
        XCTAssertEqual(series.latestValue(onOrBefore: day(4), maxAgeDays: 45, calendar: calendar), 55)
    }

    func testLatestValueFallsBackToEarlierDay() {
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: day(0), value: 50),
            HealthTrendDataPoint(date: day(4), value: 55)
        ])
        XCTAssertEqual(series.latestValue(onOrBefore: day(2), maxAgeDays: 45, calendar: calendar), 50)
    }

    func testLatestValueIgnoresFuturePoints() {
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: day(6), value: 60)
        ])
        XCTAssertNil(series.latestValue(onOrBefore: day(2), maxAgeDays: 45, calendar: calendar))
    }

    func testLatestValueHonorsAgeCutoff() {
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: day(0), value: 50)
        ])
        XCTAssertEqual(series.latestValue(onOrBefore: day(45), maxAgeDays: 45, calendar: calendar), 50)
        XCTAssertNil(series.latestValue(onOrBefore: day(46), maxAgeDays: 45, calendar: calendar))
    }

    func testLatestValueOnEmptySeriesIsNil() {
        XCTAssertNil(HealthTrendSeries.empty.latestValue(onOrBefore: day(0), maxAgeDays: 45, calendar: calendar))
    }
}
