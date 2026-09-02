//
//  BodyChartYDomainTests.swift
//  BodyTests
//
//  Covers `BodyHealthMetricTrendChart.computeYDomain(from:chartStyle:)`
//  against degenerate inputs (all-negative, all-equal) that could otherwise
//  produce a trapping (lowerBound > upperBound) ClosedRange. The other three
//  `computeYDomain`/`paddedDomain` sites fixed alongside this one are
//  `private static`, so they are not directly testable from here.
import XCTest
@testable import Body

final class BodyChartYDomainTests: XCTestCase {
    func testAllNegativeValuesLineStyleReturnsNonTrappingRange() {
        let domain = BodyHealthMetricTrendChart.computeYDomain(from: [-10, -5, -8], chartStyle: .line)

        XCTAssertLessThanOrEqual(domain.lowerBound, domain.upperBound)
    }

    func testAllNegativeValuesBarStyleReturnsNonTrappingRange() {
        let domain = BodyHealthMetricTrendChart.computeYDomain(from: [-10, -5, -8], chartStyle: .bar)

        XCTAssertLessThanOrEqual(domain.lowerBound, domain.upperBound)
    }

    func testAllEqualValuesLineStyleReturnsNonTrappingRange() {
        let domain = BodyHealthMetricTrendChart.computeYDomain(from: [0, 0, 0], chartStyle: .line)

        XCTAssertLessThanOrEqual(domain.lowerBound, domain.upperBound)
    }

    func testAllEqualValuesBarStyleReturnsNonTrappingRange() {
        let domain = BodyHealthMetricTrendChart.computeYDomain(from: [0, 0, 0], chartStyle: .bar)

        XCTAssertLessThanOrEqual(domain.lowerBound, domain.upperBound)
    }
}
