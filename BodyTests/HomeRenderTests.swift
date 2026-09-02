//
//  HomeRenderTests.swift
//  BodyTests
//
//  Covers the Home render-cost work: the animatable polyline's identity and
//  padding rules (a wrong `.zero` makes insert/remove transitions draw nothing,
//  and zero padding used to sweep new vertices in from the origin), and the
//  trend comparison chart's value domain, which moved out of per-bar computed
//  properties into a static helper.
//

import SwiftUI
import XCTest
@testable import Body

@MainActor
final class HomeRenderTests: XCTestCase {

    // MARK: - AnimatableVector

    private func vector(_ points: [CGPoint]) -> AnimatableVector {
        AnimatableVector(points: points)
    }

    func testZeroIsTheAdditiveIdentity() {
        let v = vector([CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4), CGPoint(x: 5, y: 6)])

        XCTAssertEqual((AnimatableVector.zero + v).values, v.values)
        XCTAssertEqual((v + AnimatableVector.zero).values, v.values)
        XCTAssertEqual((v - AnimatableVector.zero).values, v.values)
    }

    func testSubtractingAVectorFromItselfIsZero() {
        let v = vector([CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)])

        XCTAssertEqual((v - v).magnitudeSquared, 0, accuracy: 0.000_001)
    }

    func testPaddingRepeatsTheLastPointRatherThanTheOrigin() {
        let short = vector([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 40)])
        let long = vector([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 0)
        ])

        // `long - short` pads `short` with a repeat of (30, 40), so the third
        // component is (0 - 30, 0 - 40) rather than (0, 0).
        XCTAssertEqual((long - short).values, [-10, -20, -30, -40, -30, -40])
    }

    func testInterpolationBetweenPolylinesStaysInsideTheInputBounds() {
        let four = [
            CGPoint(x: 0, y: 10),
            CGPoint(x: 10, y: 30),
            CGPoint(x: 20, y: 20),
            CGPoint(x: 30, y: 40)
        ]
        let six = [
            CGPoint(x: 0, y: 5),
            CGPoint(x: 8, y: 25),
            CGPoint(x: 16, y: 15),
            CGPoint(x: 24, y: 35),
            CGPoint(x: 32, y: 12),
            CGPoint(x: 40, y: 28)
        ]

        let allPoints = four + six
        let minimumX = allPoints.map(\.x).min() ?? 0
        let maximumX = allPoints.map(\.x).max() ?? 0
        let minimumY = allPoints.map(\.y).min() ?? 0
        let maximumY = allPoints.map(\.y).max() ?? 0

        let start = vector(four)
        let end = vector(six)

        for step in 0...10 {
            let fraction = Double(step) / 10
            // The same shape SwiftUI's animation uses: start + (end - start) * t.
            var delta = end - start
            delta.scale(by: fraction)
            let interpolated = start + delta

            for point in interpolated.points {
                XCTAssertGreaterThanOrEqual(point.x, minimumX - 0.000_001)
                XCTAssertLessThanOrEqual(point.x, maximumX + 0.000_001)
                XCTAssertGreaterThanOrEqual(point.y, minimumY - 0.000_001)
                XCTAssertLessThanOrEqual(point.y, maximumY + 0.000_001)
            }
        }
    }

    // MARK: - Comparison chart domain

    private typealias Domain = BodyHomeTrendComparisonChart.Domain

    func testBarDomainIsAnchoredToZero() {
        let domain = BodyHomeTrendComparisonChart.domain(values: [40, 60, 50], chartStyle: .bar)

        XCTAssertEqual(domain.minimum, 0)
        XCTAssertGreaterThan(domain.maximum, 60)
    }

    func testAllEqualLineSeriesKeepsAFiniteNonEmptyDomain() {
        let domain = BodyHomeTrendComparisonChart.domain(values: [72, 72, 72, 72], chartStyle: .line)

        XCTAssertTrue(domain.minimum.isFinite)
        XCTAssertTrue(domain.maximum.isFinite)
        XCTAssertLessThan(domain.minimum, domain.maximum)
        XCTAssertLessThanOrEqual(domain.minimum, 72)
        XCTAssertGreaterThanOrEqual(domain.maximum, 72)
    }

    func testSinglePointSeriesKeepsAFiniteNonEmptyDomain() {
        let domain = BodyHomeTrendComparisonChart.domain(values: [12], chartStyle: .line)

        XCTAssertLessThan(domain.minimum, domain.maximum)
        XCTAssertLessThanOrEqual(domain.minimum, 12)
        XCTAssertGreaterThanOrEqual(domain.maximum, 12)
    }

    func testEmptySeriesFallsBackToADrawableDomain() {
        let line = BodyHomeTrendComparisonChart.domain(values: [], chartStyle: .line)
        let bar = BodyHomeTrendComparisonChart.domain(values: [], chartStyle: .bar)

        XCTAssertEqual(line, Domain(minimum: 0, maximum: 2))
        XCTAssertEqual(bar, Domain(minimum: 0, maximum: 2))
    }

    func testNonFiniteValuesAreIgnoredByTheDomain() {
        let domain = BodyHomeTrendComparisonChart.domain(
            values: [10, .nan, 20, .infinity],
            chartStyle: .bar
        )

        XCTAssertEqual(domain.minimum, 0)
        XCTAssertTrue(domain.maximum.isFinite)
        XCTAssertGreaterThan(domain.maximum, 20)
    }

    func testBarHeightsAreClampedToThePlotAndKeepAFloor() {
        let domain = BodyHomeTrendComparisonChart.domain(values: [0, 100], chartStyle: .bar)

        let missing = BodyHomeTrendComparisonChart.barHeight(for: nil, in: 100, domain: domain)
        let full = BodyHomeTrendComparisonChart.barHeight(for: 1_000, in: 100, domain: domain)
        let none = BodyHomeTrendComparisonChart.barHeight(for: -50, in: 100, domain: domain)

        XCTAssertGreaterThanOrEqual(missing, 4)
        XCTAssertEqual(full, 100, accuracy: 0.000_001)
        XCTAssertEqual(none, 4, accuracy: 0.000_001)
    }

    func testYPositionIsInvertedAgainstThePlotHeight() {
        let domain = Domain(minimum: 0, maximum: 100)
        let size = CGSize(width: 10, height: 50)

        XCTAssertEqual(BodyHomeTrendComparisonChart.yPosition(for: 0, in: size, domain: domain), 50, accuracy: 0.000_001)
        XCTAssertEqual(BodyHomeTrendComparisonChart.yPosition(for: 100, in: size, domain: domain), 0, accuracy: 0.000_001)
        XCTAssertEqual(BodyHomeTrendComparisonChart.yPosition(for: 50, in: size, domain: domain), 25, accuracy: 0.000_001)
    }
}
