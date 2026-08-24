//
//  WorkoutHumidityScalingTests.swift
//  BodyTests
//
//  `BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue:)` — the
//  helper that accepts both HealthKit's 0…1 fraction and a third-party
//  source's already-scaled percent, and drops anything out of range.
//

import XCTest
@testable import Body

final class WorkoutHumidityScalingTests: XCTestCase {
    func testNormalizedHumidityPercent() {
        XCTAssertEqual(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 0.64) ?? .nan, 64, accuracy: 0.0001)
        XCTAssertEqual(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 64), 64)
        XCTAssertEqual(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 1.0), 100)
        XCTAssertEqual(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 0), 0)
        XCTAssertNil(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 5500))
        XCTAssertNil(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: -1))
        XCTAssertEqual(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 100), 100)
        XCTAssertNil(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: 100.5))
        XCTAssertNil(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: .nan))
        XCTAssertNil(BodyWorkoutFetch.normalizedHumidityPercent(fromPercentUnitValue: .infinity))
    }
}
