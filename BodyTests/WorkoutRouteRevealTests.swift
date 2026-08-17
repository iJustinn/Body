//
//  WorkoutRouteRevealTests.swift
//  BodyTests
//
//  Geometry and timing behind the workout detail page's progressive route draw. The
//  animation itself can't be asserted, so the two pure pieces it's built from are:
//  `BodyWorkoutRouteReveal.fraction` (how far along the trace is at a given moment) and
//  `BodyWorkoutRoute3DHero.revealed` (which part of the ribbon that fraction selects).
//

import XCTest
import SwiftUI
@testable import Body

final class WorkoutRouteRevealTests: XCTestCase {

    // MARK: - Timing

    func testFractionHoldsAtZeroThroughTheStartDelay() {
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: 0), 0)
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: -1), 0)
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: BodyWorkoutRouteReveal.startDelay), 0)
        // Just inside the delay is still nothing drawn.
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: BodyWorkoutRouteReveal.startDelay - 0.01), 0)
    }

    func testFractionCompletesAtTheEndAndStaysClamped() {
        let end = BodyWorkoutRouteReveal.startDelay + BodyWorkoutRouteReveal.duration
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: end), 1)
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: end + 5), 1)
        // The teardown sleep runs past the end, so the timeline must already read 1 by
        // then or the swap to the static drawing would jump.
        XCTAssertEqual(BodyWorkoutRouteReveal.fraction(at: BodyWorkoutRouteReveal.totalDuration), 1)
    }

    func testFractionIsMonotonicAndEasesOut() {
        let start = BodyWorkoutRouteReveal.startDelay
        let duration = BodyWorkoutRouteReveal.duration

        var previous = BodyWorkoutRouteReveal.fraction(at: start)
        for step in 1...50 {
            let elapsed = start + duration * Double(step) / 50
            let value = BodyWorkoutRouteReveal.fraction(at: elapsed)
            XCTAssertGreaterThanOrEqual(value, previous, "reveal ran backwards at \(elapsed)")
            XCTAssertLessThanOrEqual(value, 1)
            previous = value
        }

        // Cubic ease-out: half the time is well past half the line, so a long route
        // doesn't crawl through its final third.
        let midpoint = BodyWorkoutRouteReveal.fraction(at: start + duration / 2)
        XCTAssertGreaterThan(midpoint, 0.5)
    }

    func testFractionFromAnEpochMatchesElapsedTime() {
        let epoch = Date(timeIntervalSinceReferenceDate: 1_000)
        let elapsed = BodyWorkoutRouteReveal.startDelay + BodyWorkoutRouteReveal.duration / 2
        XCTAssertEqual(
            BodyWorkoutRouteReveal.fraction(epoch: epoch, date: epoch.addingTimeInterval(elapsed)),
            BodyWorkoutRouteReveal.fraction(at: elapsed),
            accuracy: 1e-12
        )
    }

    // MARK: - Ribbon slicing

    /// An L: three points, the first leg 300 long and the second 100, so index-based and
    /// length-based cuts land in visibly different places.
    private let unevenTop: [CGPoint] = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 300, y: 0),
        CGPoint(x: 300, y: 100)
    ]
    private let unevenBase: [CGPoint] = [
        CGPoint(x: 0, y: 40),
        CGPoint(x: 300, y: 40),
        CGPoint(x: 300, y: 140)
    ]

    func testRevealedPacesByArcLengthNotPointIndex() {
        // Total length 400. At 0.5 the head is 200 along, i.e. two thirds of the way
        // through the FIRST segment — an index-based cut would instead have finished that
        // whole segment and be starting the second.
        let half = BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: 0.5)
        XCTAssertEqual(half.top.count, 2)
        XCTAssertEqual(half.top.last?.x ?? 0, 200, accuracy: 1e-6)
        XCTAssertEqual(half.top.last?.y ?? 0, 0, accuracy: 1e-6)
        // The base is cut at the same place, so the wall between them stays square.
        XCTAssertEqual(half.base.last?.x ?? 0, 200, accuracy: 1e-6)
        XCTAssertEqual(half.base.last?.y ?? 0, 40, accuracy: 1e-6)
    }

    func testRevealedInterpolatesIntoTheSecondSegment() {
        // 0.875 of 400 is 350: the whole first leg plus 50 of the 100-long second.
        let late = BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: 0.875)
        XCTAssertEqual(late.top.count, 3)
        XCTAssertEqual(late.top.last?.x ?? 0, 300, accuracy: 1e-6)
        XCTAssertEqual(late.top.last?.y ?? 0, 50, accuracy: 1e-6)
        XCTAssertEqual(late.base.last?.y ?? 0, 90, accuracy: 1e-6)
    }

    func testRevealedKeepsTopAndBaseTheSameLength() {
        for step in 0...20 {
            let fraction = CGFloat(step) / 20
            let sliced = BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: fraction)
            XCTAssertEqual(
                sliced.top.count,
                sliced.base.count,
                "mismatched polylines at \(fraction) would shear the ribbon's walls"
            )
            // Either nothing to draw yet, or a real segment — never a lone point, which
            // a round line cap would render as a stray dot.
            XCTAssertTrue(
                sliced.top.isEmpty || sliced.top.count >= 2,
                "a single point at \(fraction) would draw as a dot"
            )
        }
    }

    func testRevealedReturnsTheWholeRibbonAtOne() {
        let whole = BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: 1)
        XCTAssertEqual(whole.top, unevenTop)
        XCTAssertEqual(whole.base, unevenBase)

        // Anything past 1 is the same — the share card passes the default.
        let past = BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: 4)
        XCTAssertEqual(past.top, unevenTop)
    }

    func testRevealedDrawsNothingBeforeTheHeadHasMoved() {
        // The painter needs two points, so an empty slice is how the ribbon stays off
        // screen through the reveal's opening beat — a single point would show as a dot.
        let none = BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: 0)
        XCTAssertTrue(none.top.isEmpty)
        XCTAssertTrue(none.base.isEmpty)
    }

    func testRevealedHandlesDegenerateInput() {
        // A route projected end-on collapses to zero length: show it whole rather than
        // dividing by zero.
        let flat = [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)]
        let collapsed = BodyWorkoutRoute3DHero.revealed(top: flat, base: flat, fraction: 0.4)
        XCTAssertEqual(collapsed.top.count, 3)

        // Fewer than two points has no segment at all and passes straight through.
        let single = [CGPoint(x: 1, y: 1)]
        let tiny = BodyWorkoutRoute3DHero.revealed(top: single, base: single, fraction: 0.5)
        XCTAssertEqual(tiny.top.count, 1)
    }

    func testRevealedIsMonotonicInDrawnLength() {
        func drawnLength(_ points: [CGPoint]) -> CGFloat {
            guard points.count >= 2 else { return 0 }
            return zip(points, points.dropFirst()).reduce(0) { total, pair in
                let dx = pair.1.x - pair.0.x
                let dy = pair.1.y - pair.0.y
                return total + (dx * dx + dy * dy).squareRoot()
            }
        }

        var previous: CGFloat = 0
        for step in 0...20 {
            let fraction = CGFloat(step) / 20
            let length = drawnLength(BodyWorkoutRoute3DHero.revealed(top: unevenTop, base: unevenBase, fraction: fraction).top)
            XCTAssertGreaterThanOrEqual(length + 1e-6, previous, "the head moved backwards at \(fraction)")
            previous = length
        }
    }
}
