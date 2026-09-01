//
//  WorkoutRouteHeroFitTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
import MapKit
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

    // MARK: - 3D Map camera correction

    func testCorrectedFramingShrinksOnTheBindingAxisAndRecentres() throws {
        let correction = try XCTUnwrap(BodyWorkoutRouteMapHero.correctedFraming(
            measured: CGRect(x: 45, y: 80, width: 300, height: 150),
            target: CGRect(x: 120, y: 120, width: 150, height: 100),
            screenCenter: CGPoint(x: 195, y: 255),
            distance: 1000,
            centerMapPoint: MKMapPoint(x: 5000, y: 9000),
            groundMapSize: MKMapSize(width: 600, height: 300),
            groundScreenSize: CGSize(width: 300, height: 150),
            minimumDistance: 100
        ))

        // Width binds (300/150 = 2 against 150/100 = 1.5), so the camera pulls back 2x
        // and the on-screen scale halves.
        XCTAssertEqual(correction.distance, 2000, accuracy: 1e-6)
        // At half scale the measured centre lands 35 pt below the target, so the look-at
        // point moves south (+y in map points) to bring the content back up.
        XCTAssertEqual(correction.center.x, 5000, accuracy: 1e-6)
        XCTAssertEqual(correction.center.y, 9140, accuracy: 1e-6)
    }

    func testCorrectedFramingHoldsTheMinimumDistanceFloor() throws {
        let correction = try XCTUnwrap(BodyWorkoutRouteMapHero.correctedFraming(
            measured: CGRect(x: 170, y: 230, width: 50, height: 50),
            target: CGRect(x: 95, y: 155, width: 200, height: 200),
            screenCenter: CGPoint(x: 195, y: 255),
            distance: 1000,
            centerMapPoint: MKMapPoint(x: 5000, y: 9000),
            groundMapSize: MKMapSize(width: 600, height: 300),
            groundScreenSize: CGSize(width: 50, height: 50),
            minimumDistance: 1000
        ))

        // The route wants to come closer than the floor allows: the size can't be
        // matched, and the framing keeps the floor.
        XCTAssertEqual(correction.distance, 1000, accuracy: 1e-6)
    }

    func testCorrectedFramingStopsOnceItIsWithinTolerance() {
        XCTAssertNil(BodyWorkoutRouteMapHero.correctedFraming(
            measured: CGRect(x: 120.5, y: 120.5, width: 150, height: 100),
            target: CGRect(x: 120, y: 120, width: 150, height: 100),
            screenCenter: CGPoint(x: 195, y: 255),
            distance: 1000,
            centerMapPoint: MKMapPoint(x: 5000, y: 9000),
            groundMapSize: MKMapSize(width: 600, height: 300),
            groundScreenSize: CGSize(width: 150, height: 100),
            minimumDistance: 100
        ))
    }
}
