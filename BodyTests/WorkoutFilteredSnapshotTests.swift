//
//  WorkoutFilteredSnapshotTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutFilteredSnapshotTests: XCTestCase {
    func testDisplaySnapshotKeepsOnlyMatchingWorkoutsAndPreservesDayBucketsAndGeneratedAt() throws {
        let running = workout(day: 6, type: .running, duration: 2_400)
        let walking = workout(day: 6, type: .walking, duration: 3_000)
        let strength = workout(day: 9, type: .strengthTraining, duration: 3_600)
        let generatedAt = try XCTUnwrap(
            Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))
        )
        let snapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [running, walking, strength],
            calendar: .bodyGregorian,
            generatedAt: generatedAt
        )

        let filtered = BodyWorkoutFilterLogic.displaySnapshot(
            from: snapshot,
            matchingIDs: [running.id, strength.id]
        )

        XCTAssertEqual(filtered.month, snapshot.month)
        XCTAssertEqual(filtered.year, snapshot.year)
        XCTAssertEqual(filtered.generatedAt, snapshot.generatedAt)
        XCTAssertEqual(filtered.days.count, snapshot.days.count)
        XCTAssertEqual(filtered.days.map(\.dateKey), snapshot.days.map(\.dateKey))
        XCTAssertEqual(filtered.workoutCount, 2)
        XCTAssertEqual(filtered.day(6)?.workouts, [running])
        XCTAssertEqual(filtered.day(9)?.workouts, [strength])
        XCTAssertEqual(filtered.workoutTypeBreakdown.map(\.type), [.strengthTraining, .running])
    }

    func testDisplaySnapshotWithNoMatchesYieldsValidEmptyMonth() {
        let snapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [
                workout(day: 6, type: .running, duration: 2_400),
                workout(day: 9, type: .strengthTraining, duration: 3_600)
            ],
            calendar: .bodyGregorian
        )

        let filtered = BodyWorkoutFilterLogic.displaySnapshot(from: snapshot, matchingIDs: [])

        XCTAssertEqual(filtered.days.count, 31)
        XCTAssertEqual(filtered.workoutCount, 0)
        XCTAssertEqual(filtered.activeDayCount, 0)
        XCTAssertEqual(filtered.workoutTypeBreakdown, [])
    }

    func testDisplaySnapshotWithAllMatchesEqualsOriginal() {
        let workouts = [
            workout(day: 6, type: .running, duration: 2_400),
            workout(day: 6, type: .walking, duration: 3_000),
            workout(day: 9, type: .strengthTraining, duration: 3_600)
        ]
        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: workouts, calendar: .bodyGregorian)

        let filtered = BodyWorkoutFilterLogic.displaySnapshot(
            from: snapshot,
            matchingIDs: Set(workouts.map(\.id))
        )

        XCTAssertEqual(filtered, snapshot)
    }

    func testDisplaySnapshotNeverMovesWorkoutsBetweenDayBuckets() throws {
        // The persisted snapshot doesn't record the calendar/time zone that
        // formed its day buckets, so filtering must preserve each workout's
        // original day even when re-bucketing its startDate would disagree
        // (e.g. after a time-zone change).
        let boundaryWorkout = workout(day: 3, type: .running, duration: 2_400)
        let generatedAt = try XCTUnwrap(
            Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))
        )
        let snapshot = WorkoutMonthSnapshot(
            month: 5,
            year: 2026,
            generatedAt: generatedAt,
            days: [
                WorkoutDaySummary(dateKey: "2026-05-02", day: 2, workouts: [boundaryWorkout]),
                WorkoutDaySummary(dateKey: "2026-05-03", day: 3, workouts: [])
            ]
        )

        let filtered = BodyWorkoutFilterLogic.displaySnapshot(
            from: snapshot,
            matchingIDs: [boundaryWorkout.id]
        )

        XCTAssertEqual(filtered.day(2)?.workouts, [boundaryWorkout])
        XCTAssertEqual(filtered.day(3)?.workouts, [])
    }

    private func workout(day: Int, type: BodyWorkoutType, duration: TimeInterval) -> WorkoutSummary {
        WorkoutSummary(
            type: type,
            startDate: Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: day, hour: 8)) ?? Date(),
            duration: duration,
            activeEnergyKilocalories: 100,
            distanceMeters: 1_000,
            sourceName: "Tests"
        )
    }
}
