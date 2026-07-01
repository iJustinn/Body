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

    // MARK: - Incomplete history gating

    func testIncompleteHistorySkipsCalibrationAndCapsConfidence() {
        let priors = (0..<3).map { _ in ratedPrior(rating: 8) }
        let result = estimate(
            workout(avgHR: bpm(hrrFraction: 0.72)),
            maxHeartRate: maxHR,
            restingHeartRate: restHR,
            priors: priors,
            isComplete: false
        )
        XCTAssertEqual(result?.calibrationBias ?? -1, 0)
        XCTAssertEqual(result?.confidence, .medium)
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
