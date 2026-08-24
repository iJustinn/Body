//
//  WorkoutRouteHeroAnchorTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
@testable import Body

final class WorkoutRouteHeroAnchorTests: XCTestCase {
    func testResultIsMidpointOfInsetAndContentTop() {
        let result = BodyWorkoutRouteHeroAnchor.targetCenterY(
            topInset: 59,
            contentMinY: 200,
            fallbackContentMinY: 384
        )

        // contentTop = 59 + 200 = 259; center = (59 + 259) / 2 = 159.
        XCTAssertEqual(result, 159, accuracy: 1e-9)
    }

    func testFallbackUsedWhenContentMinYIsNil() {
        let result = BodyWorkoutRouteHeroAnchor.targetCenterY(
            topInset: 59,
            contentMinY: nil,
            fallbackContentMinY: 384
        )

        // contentTop = 59 + 384 = 443; center = (59 + 443) / 2 = 251.
        XCTAssertEqual(result, 251, accuracy: 1e-9)
    }

    func testPureFunctionIgnoresCallbackOrder() {
        // Whether the inset "arrived" before or after the content measurement, the
        // same (inset, contentMinY) pair must produce the same result — the whole
        // point of computing at read time instead of caching a baked screen-y.
        let direct = BodyWorkoutRouteHeroAnchor.targetCenterY(
            topInset: 59,
            contentMinY: 200,
            fallbackContentMinY: 384
        )

        _ = BodyWorkoutRouteHeroAnchor.targetCenterY(
            topInset: 0,
            contentMinY: 200,
            fallbackContentMinY: 384
        )

        let afterInsetArrives = BodyWorkoutRouteHeroAnchor.targetCenterY(
            topInset: 59,
            contentMinY: 200,
            fallbackContentMinY: 384
        )

        XCTAssertEqual(afterInsetArrives, direct, accuracy: 1e-9)
    }
}
