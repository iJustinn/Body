//
//  WorkoutRouteHeroFitTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
@testable import Body

final class WorkoutRouteHeroFitTests: XCTestCase {
    func testUnitSquareFitsExactlyPerTheHeroFormula() throws {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0, y: 1),
            CGPoint(x: 1, y: 1)
        ]

        let fitted = try XCTUnwrap(BodyWorkoutRouteHeroFit.fittedPoints(
            points,
            in: CGSize(width: 390, height: 510),
            targetCenterY: 200,
            topInset: 59
        ))

        // availableWidth = 390 - 24*2 = 342; availableHeight = 2*(200-59-12) = 258;
        // scale = min(342, 258) * 0.9 = 232.2; center = (0.5, 0.5).
        XCTAssertEqual(fitted[0].x, 78.9, accuracy: 1e-6)
        XCTAssertEqual(fitted[0].y, 83.9, accuracy: 1e-6)
        XCTAssertEqual(fitted[3].x, 311.1, accuracy: 1e-6)
        XCTAssertEqual(fitted[3].y, 316.1, accuracy: 1e-6)
    }

    func testNilForZeroWidth() {
        let points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]

        XCTAssertNil(BodyWorkoutRouteHeroFit.fittedPoints(
            points,
            in: CGSize(width: 0, height: 510),
            targetCenterY: 200,
            topInset: 59
        ))
    }

    func testNilForFewerThanTwoPoints() {
        XCTAssertNil(BodyWorkoutRouteHeroFit.fittedPoints(
            [],
            in: CGSize(width: 390, height: 510),
            targetCenterY: 200,
            topInset: 59
        ))
        XCTAssertNil(BodyWorkoutRouteHeroFit.fittedPoints(
            [CGPoint(x: 0, y: 0)],
            in: CGSize(width: 390, height: 510),
            targetCenterY: 200,
            topInset: 59
        ))
    }
}
