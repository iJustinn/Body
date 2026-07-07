//
//  ActivityReadinessImpactTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class ActivityReadinessImpactTests: XCTestCase {
    private let fixedStart = Date(timeIntervalSince1970: 1_700_000_000)

    private func workout(
        _ type: BodyWorkoutType,
        minutes: Double,
        effort: Double? = nil,
        avgHR: Double? = nil,
        activeEnergy: Double? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            type: type,
            startDate: fixedStart,
            duration: minutes * 60,
            activeEnergyKilocalories: activeEnergy,
            averageHeartRateBeatsPerMinute: avgHR,
            effortLevel: effort
        )
    }

    // MARK: - Type weighting

    func testHigherImpactTypeDrainsMoreAtEqualDurationAndEffort() {
        let running = ActivityReadinessImpact.perWorkoutDrain(workout(.running, minutes: 60, effort: 8))
        let strength = ActivityReadinessImpact.perWorkoutDrain(workout(.strengthTraining, minutes: 60, effort: 8))
        let yoga = ActivityReadinessImpact.perWorkoutDrain(workout(.yoga, minutes: 60, effort: 8))

        XCTAssertGreaterThan(running, strength)
        XCTAssertGreaterThan(strength, yoga)
        XCTAssertGreaterThan(yoga, 0)
    }

    func testTypeWeightGroups() {
        XCTAssertEqual(ActivityReadinessImpact.typeWeight(.running), 1.20, accuracy: 0.0001)
        XCTAssertEqual(ActivityReadinessImpact.typeWeight(.strengthTraining), 1.00, accuracy: 0.0001)
        XCTAssertEqual(ActivityReadinessImpact.typeWeight(.yoga), 0.40, accuracy: 0.0001)
        XCTAssertEqual(ActivityReadinessImpact.typeWeight(.pickleball), 0.80, accuracy: 0.0001) // long-tail default
    }

    // MARK: - Effort

    func testHigherEffortDrainsMore() {
        let hard = ActivityReadinessImpact.perWorkoutDrain(workout(.running, minutes: 45, effort: 9))
        let easy = ActivityReadinessImpact.perWorkoutDrain(workout(.running, minutes: 45, effort: 3))
        XCTAssertGreaterThan(hard, easy)
    }

    func testEstimatesEffortFromHeartRateWhenEffortMissing() {
        let highHR = ActivityReadinessImpact.estimatedEffort(for: workout(.running, minutes: 45, avgHR: 165))
        let lowHR = ActivityReadinessImpact.estimatedEffort(for: workout(.running, minutes: 45, avgHR: 105))
        XCTAssertGreaterThan(highHR, lowHR)
        XCTAssertGreaterThan(highHR, 5) // 165 bpm should read as harder than neutral
    }

    func testEstimatesEffortFromEnergyWhenEffortMissing() {
        // ~11 kcal/min → energy estimate ~9, well above the neutral default.
        let energetic = ActivityReadinessImpact.estimatedEffort(
            for: workout(.cycling, minutes: 30, activeEnergy: 330)
        )
        XCTAssertGreaterThan(energetic, 5)
    }

    func testFallsBackToNeutralEffortWithoutMetrics() {
        let effort = ActivityReadinessImpact.estimatedEffort(for: workout(.other, minutes: 30))
        XCTAssertEqual(effort, TrainingLoadCalculator.defaultEffortLevel, accuracy: 0.0001)
    }

    func testEffortClampedIntoOneToTenRange() {
        XCTAssertEqual(ActivityReadinessImpact.estimatedEffort(for: workout(.running, minutes: 30, effort: 50)), 10, accuracy: 0.0001)
        XCTAssertEqual(ActivityReadinessImpact.estimatedEffort(for: workout(.running, minutes: 30, effort: -5)), 1, accuracy: 0.0001)
    }

    // MARK: - Saturation, cap, floor inputs

    func testSingleWorkoutNeverExceedsSingleCap() {
        let extreme = ActivityReadinessImpact.perWorkoutDrain(workout(.hiit, minutes: 600, effort: 10))
        XCTAssertLessThan(extreme, ActivityReadinessImpact.maxSingleWorkoutDrain)
    }

    func testTotalDrainCapped() {
        let many = (0..<5).map { _ in workout(.running, minutes: 180, effort: 10) }
        let drain = ActivityReadinessImpact.drainPoints(workouts: many)
        XCTAssertLessThanOrEqual(drain, ActivityReadinessImpact.totalDrainCap)
        XCTAssertEqual(drain, ActivityReadinessImpact.totalDrainCap, accuracy: 0.0001)
    }

    func testEmptyAndZeroDurationDrainNothing() {
        XCTAssertEqual(ActivityReadinessImpact.drainPoints(workouts: []), 0, accuracy: 0.0001)
        XCTAssertEqual(ActivityReadinessImpact.perWorkoutDrain(workout(.running, minutes: 0, effort: 9)), 0, accuracy: 0.0001)
    }

    func testDramaticMagnitudeForHardHourLongSession() {
        // A hard ~hour-long run should land in the "about two bands" range.
        let drain = ActivityReadinessImpact.drainPoints(workouts: [workout(.running, minutes: 60, effort: 9)])
        XCTAssertGreaterThan(drain, 25)
    }

    // MARK: - Low-end display softening (displayedScore mapper)

    func testDisplayedScoreLeavesNormalRangeUnchanged() {
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: 100), 100)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: 42), 42)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: 6), 6)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: 5), 5) // floor boundary
    }

    func testDisplayedScoreHoldsFloorFromZeroThroughLowPositives() {
        // Raw 0…4 all show the 5% floor; raw 0 is the user's headline case.
        for raw in 0...4 {
            XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: raw), 5, "raw \(raw)")
        }
    }

    func testDisplayedScoreEasesOnePointPerFivePointDeficit() {
        // Holds at the floor until a full 5% of deficit accumulates, then steps down.
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -1), 5)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -4), 5)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -5), 4)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -10), 3)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -15), 2)
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -20), 1)
    }

    func testDisplayedScoreReachesZeroOnlyAtDeepDeficit() {
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -24), 1) // just above the boundary
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -25), 0) // first 0
        XCTAssertEqual(ActivityReadinessImpact.displayedScore(forRawScore: -45), 0) // never below 0
    }

    func testDisplayedScoreIsMonotonicNonIncreasing() {
        var previous = Int.max
        for raw in stride(from: 30, through: -50, by: -1) {
            let value = ActivityReadinessImpact.displayedScore(forRawScore: raw)
            XCTAssertLessThanOrEqual(value, previous, "raw \(raw) rose to \(value) from \(previous)")
            previous = value
        }
    }

    // MARK: - Wake normalization (HealthKitWorkoutStore freeze/drain windows)

    func testFreezeWakeTimeRequiresSameScoringDayAndNotFuture() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let now = day.addingTimeInterval(11 * 3_600)
        let sameDayWake = day.addingTimeInterval(7 * 3_600)

        XCTAssertEqual(
            HealthKitWorkoutStore.freezeWakeTime(sleepEnd: sameDayWake, scoringDay: day, now: now, calendar: calendar),
            sameDayWake
        )
        // Stale wake from days ago → nil (freeze falls back to 10:00, not the stale time).
        XCTAssertNil(HealthKitWorkoutStore.freezeWakeTime(
            sleepEnd: day.addingTimeInterval(-2 * 24 * 3_600), scoringDay: day, now: now, calendar: calendar
        ))
        // Future wake → nil; missing → nil.
        XCTAssertNil(HealthKitWorkoutStore.freezeWakeTime(
            sleepEnd: now.addingTimeInterval(3_600), scoringDay: day, now: now, calendar: calendar
        ))
        XCTAssertNil(HealthKitWorkoutStore.freezeWakeTime(sleepEnd: nil, scoringDay: day, now: now, calendar: calendar))
    }

    func testWakeCycleStartKeepsRecentWakeButBoundsStaleSleep() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let now = day.addingTimeInterval(0.5 * 3_600) // 00:30 — just past midnight

        // Recent wake (~17.5h ago): kept, so an evening workout's drain survives past midnight.
        let recentWake = now.addingTimeInterval(-17.5 * 3_600)
        XCTAssertEqual(HealthKitWorkoutStore.wakeCycleStart(now: now, sleepEnd: recentWake, calendar: calendar), recentWake)

        // Stale wake (~30h ago): rejected → window starts at midnight of `now`.
        let staleWake = now.addingTimeInterval(-30 * 3_600)
        XCTAssertEqual(
            HealthKitWorkoutStore.wakeCycleStart(now: now, sleepEnd: staleWake, calendar: calendar),
            calendar.startOfDay(for: now)
        )
        // Missing → midnight.
        XCTAssertEqual(
            HealthKitWorkoutStore.wakeCycleStart(now: now, sleepEnd: nil, calendar: calendar),
            calendar.startOfDay(for: now)
        )
    }

    // MARK: - Workout-attributed hero explanation

    private func readiness(score: Int) -> ReadinessSummary {
        ReadinessSummary(
            score: score,
            status: ReadinessStatus.status(for: score),
            confidence: .high,
            components: [],
            drivers: [ReadinessDriver(kind: .mostlyTypical, message: "", impact: 0)]
        )
    }

    func testWorkoutDroppingBandAttributesDropToTraining() {
        let morning = readiness(score: 70) // Moderate
        let hard = workout(.running, minutes: 60, effort: 9) // heavy drain → into Low
        let drained = HealthDashboardSnapshot.draining(morning, with: [hard])

        XCTAssertEqual(drained.status, .low)
        XCTAssertEqual(drained.activityDrainMorningScore, 70)
        let drain = drained.activityDrainPoints ?? 0
        // Moderate → Low uses the generic training-attributed wording.
        XCTAssertEqual(
            drained.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .moderate, drain: drain)
        )
        // The training wording differs from the light-activity wording.
        XCTAssertNotEqual(
            drained.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .low, drain: 0)
        )
    }

    func testMeaningfulSameBandDrainReadsAsTraining() {
        // Regression: a large drain that stays inside the band (Low → Low) must read as real
        // training, not "light activity" — the classifier keys on drain size, not band change.
        let morning = readiness(score: 64) // top of Low
        let real = workout(.running, minutes: 30, effort: 6) // ~23-point drain, stays in Low
        let drained = HealthDashboardSnapshot.draining(morning, with: [real])

        XCTAssertEqual(drained.status, .low) // same band
        let drain = drained.activityDrainPoints ?? 0
        XCTAssertGreaterThanOrEqual(drain, ReadinessStatus.meaningfulActivityDrain)
        // Uses the training (dropped) wording, NOT the light-activity wording.
        XCTAssertEqual(
            drained.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .low, drain: drain)
        )
        XCTAssertNotEqual(
            drained.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .low, drain: 0)
        )
    }

    func testHardWorkoutFromVeryLowMorningReadsAsTrainingNotLight() {
        // Regression for the floor-clamp gap: a demanding session on an already-low morning
        // clamps the *displayed* score to the floor, so the visible delta looks tiny — but the
        // actual drain is large and must still read as training, not "light activity."
        let morning = readiness(score: 8) // Poor, near the floor
        let hard = workout(.running, minutes: 120, effort: 10) // near-max single-workout drain
        let drained = HealthDashboardSnapshot.draining(morning, with: [hard])

        let drain = drained.activityDrainPoints ?? 0
        let displayedDelta = 8 - (drained.score ?? 8)
        XCTAssertLessThan(displayedDelta, ReadinessStatus.meaningfulActivityDrain)     // display looks light
        XCTAssertGreaterThanOrEqual(drain, ReadinessStatus.meaningfulActivityDrain)    // real drain is heavy

        XCTAssertEqual(
            drained.heroExplanation,
            ReadinessStatus.poor.activityDrainHeroExplanation(morningStatus: .poor, drain: drain)
        )
        // Not the light-activity copy that the displayed delta alone would have selected.
        XCTAssertNotEqual(
            drained.heroExplanation,
            ReadinessStatus.poor.activityDrainHeroExplanation(morningStatus: .poor, drain: displayedDelta)
        )
    }

    func testDeepDropFromTopBandsGetsSeriousWording() {
        let hard = workout(.running, minutes: 60, effort: 9) // heavy drain → crashes to Low

        let fromPrime = HealthDashboardSnapshot.draining(readiness(score: 98), with: [hard])
        XCTAssertEqual(fromPrime.status, .low)
        XCTAssertEqual(fromPrime.activityDrainMorningScore, 98)
        let primeDrain = fromPrime.activityDrainPoints ?? 0
        XCTAssertEqual(
            fromPrime.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .prime, drain: primeDrain)
        )

        let fromHigh = HealthDashboardSnapshot.draining(readiness(score: 88), with: [hard])
        XCTAssertEqual(fromHigh.status, .low)
        XCTAssertEqual(fromHigh.activityDrainMorningScore, 88)
        let highDrain = fromHigh.activityDrainPoints ?? 0
        XCTAssertEqual(
            fromHigh.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .high, drain: highDrain)
        )

        // The three Low origins (Prime, High, Moderate) all read distinctly.
        let genericLowDrop = ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .moderate, drain: 30)
        XCTAssertNotEqual(fromPrime.heroExplanation, fromHigh.heroExplanation)
        XCTAssertNotEqual(fromPrime.heroExplanation, genericLowDrop)
        XCTAssertNotEqual(fromHigh.heroExplanation, genericLowDrop)
    }

    func testLightWorkoutHoldingBandReadsAsLightActivity() {
        let morning = readiness(score: 55) // Low
        let light = workout(.yoga, minutes: 20, effort: 3) // small drain, stays Low
        let drained = HealthDashboardSnapshot.draining(morning, with: [light])

        XCTAssertEqual(drained.status, .low)
        XCTAssertEqual(drained.activityDrainMorningScore, 55)
        let drain = drained.activityDrainPoints ?? 0
        XCTAssertLessThan(drain, ReadinessStatus.meaningfulActivityDrain) // genuinely light
        XCTAssertEqual(
            drained.heroExplanation,
            ReadinessStatus.low.activityDrainHeroExplanation(morningStatus: .low, drain: drain)
        )
        // Light-activity wording replaces (is not) the morning-driver explanation.
        XCTAssertNotEqual(drained.heroExplanation, morning.heroExplanation)
    }

    func testNoWorkoutKeepsMorningDriverExplanation() {
        let morning = readiness(score: 55)
        let undrained = HealthDashboardSnapshot.draining(morning, with: [])
        XCTAssertNil(undrained.activityDrainMorningScore)
        XCTAssertEqual(undrained.heroExplanation, morning.heroExplanation)
    }
}
