//
//  HealthTrendValueRangeTests.swift
//  BodyTests
//
//  `HealthTrendRangeSeries.valueRange` builds a `ClosedRange` from the minimum
//  low and the maximum high, which traps when a point's low sits above every
//  high. Covers the ordering fix and the nil paths.
//

import XCTest
@testable import Body

final class HealthTrendValueRangeTests: XCTestCase {
    private func point(_ day: Double, low: Double, high: Double) -> HealthTrendRangeDataPoint {
        HealthTrendRangeDataPoint(
            date: Date(timeIntervalSince1970: 1_700_000_000 + day * 86_400),
            lowValue: low,
            highValue: high,
            averageValue: (low + high) / 2
        )
    }

    func testValueRangeOrdersInvertedBounds() throws {
        // The only finite low (80) is above the only finite high (40).
        let series = HealthTrendRangeSeries(points: [
            point(0, low: 80, high: 40)
        ])

        let range = try XCTUnwrap(series.valueRange)
        XCTAssertEqual(range.lowerBound, 40)
        XCTAssertEqual(range.upperBound, 80)
    }

    func testValueRangeIsNilForEmptySeries() {
        XCTAssertNil(HealthTrendRangeSeries(points: []).valueRange)
    }

    func testValueRangeIsNilWhenNoBoundIsFinite() {
        let series = HealthTrendRangeSeries(points: [
            point(0, low: .nan, high: .infinity)
        ])

        XCTAssertNil(series.valueRange)
    }
}
