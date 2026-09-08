//
//  WristTemperatureBaselineTests.swift
//  BodyTests
//
//  L-39: `wristTemperatureBaseline(from:)` used to mask "no finite values" as
//  0 via `?? 0`, which a caller could mistake for a real reading. It was
//  deleted in favor of routing its one caller through
//  `wristTemperatureBaselineIfAvailable`, which stays optional.
import XCTest
@testable import Body

final class WristTemperatureBaselineTests: XCTestCase {
    func testWristTemperatureBaselineIfAvailableReturnsNilForNoFiniteValues() {
        let series = HealthTrendSeries(points: [])

        XCTAssertNil(wristTemperatureBaselineIfAvailable(from: series))
    }
}
