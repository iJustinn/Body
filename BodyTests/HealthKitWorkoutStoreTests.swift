//
//  HealthKitWorkoutStoreTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStoreTests: XCTestCase {
    @MainActor
    func testWorkoutStoreKeepsRecentChartWindowToThreeMonths() {
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )
        let store = HealthKitWorkoutStore(initialSnapshot: initialSnapshot)

        XCTAssertEqual(HealthKitWorkoutStore.recentChartMonthCount, 3)
        XCTAssertEqual(store.snapshot(month: 5, year: 2026), initialSnapshot)

        let unloadedSnapshot = store.snapshot(month: 4, year: 2026)
        XCTAssertEqual(unloadedSnapshot.month, 4)
        XCTAssertEqual(unloadedSnapshot.year, 2026)
        XCTAssertEqual(unloadedSnapshot.workoutCount, 0)
        XCTAssertFalse(store.hasLoadedSnapshot(month: 4, year: 2026))
    }

    func testHealthKitWorkoutTypeMappingPreservesSpecificActivities() {
        let mappings: [(HKWorkoutActivityType, BodyWorkoutType)] = [
            (.running, .running),
            (.walking, .walking),
            (.traditionalStrengthTraining, .strengthTraining),
            (.functionalStrengthTraining, .functionalStrengthTraining),
            (.pickleball, .pickleball),
            (.pilates, .pilates),
            (.elliptical, .elliptical),
            (.rowing, .rowing),
            (.soccer, .soccer),
            (.tennis, .tennis),
            (.cooldown, .cooldown),
            (.swimBikeRun, .swimBikeRun),
            (.underwaterDiving, .underwaterDiving)
        ]

        for (activityType, bodyType) in mappings {
            XCTAssertEqual(HealthKitWorkoutStore.workoutType(for: activityType), bodyType)
        }
    }

    func testUnknownHealthKitWorkoutTypeFallsBackToOther() throws {
        let unknownActivityType = try XCTUnwrap(HKWorkoutActivityType(rawValue: 81))
        XCTAssertEqual(HealthKitWorkoutStore.workoutType(for: unknownActivityType), .other)
    }

    func testMergedSleepDurationDoesNotDoubleCountOverlaps() throws {
        let calendar = Calendar.bodyGregorian
        let firstStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
        let firstEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 5)))
        let secondStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 3)))
        let secondEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 7)))
        let thirdStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8)))
        let thirdEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 9, minute: 30)))

        let duration = HealthKitWorkoutStore.mergedSleepDuration(
            intervals: [
                (start: secondStart, end: secondEnd),
                (start: firstStart, end: firstEnd),
                (start: thirdStart, end: thirdEnd)
            ]
        )

        XCTAssertEqual(duration, 27_000)
    }
}
