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
}
