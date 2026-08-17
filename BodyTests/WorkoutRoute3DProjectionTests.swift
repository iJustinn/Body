//
//  WorkoutRoute3DProjectionTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
@testable import Body

final class WorkoutRoute3DProjectionTests: XCTestCase {
    /// Deck lift applied to every point, even a flat route.
    private let deckUnits = 0.05
    /// Full relief at ≥ 200 m of altitude range.
    private let maximumReliefUnits = 0.30
    private let fullReliefMetres = 200.0
    private let groundSquash = 0.55

    // MARK: - Fixture builders

    /// A fix at a real spatial position on a small lat/lon grid (so
    /// `WorkoutShareRouteProjection.normalizedPoints` never rejects it as degenerate),
    /// carrying the given altitude (or none).
    private func gridFix(_ index: Int, altitude: Double?) -> RouteCoordinate {
        RouteCoordinate(
            latitude: 10.00 + Double(index) * 0.002,
            longitude: 20.00 + Double(index) * 0.002,
            speed: 0,
            altitude: altitude
        )
    }

    private func route(_ altitudes: [Double?]) -> [RouteCoordinate] {
        altitudes.enumerated().map { gridFix($0.offset, altitude: $0.element) }
    }

    /// Lift of point `index`: the vertical gap between its `base` (ground) and `top`
    /// (lifted) points — the only altitude-derived quantity the projection exposes.
    private func lift(_ projected: WorkoutRoute3DProjection.Projected3D, _ index: Int) -> Double {
        Double(projected.base[index].y - projected.top[index].y)
    }

    // MARK: - Coverage gate

    func testNilForFewerThanTwoAltitudes() {
        let coordinates = route([100, nil, nil])
        XCTAssertNil(WorkoutRoute3DProjection.projected(for: coordinates))
    }

    func testExactlyFiftyPercentCoveragePasses() {
        // 2 of 4 fixes carry altitude — exactly the 50% floor.
        let coordinates = route([10, nil, 20, nil])
        XCTAssertNotNil(WorkoutRoute3DProjection.projected(for: coordinates))
    }

    func testBelowFiftyPercentCoverageFails() {
        // 2 of 5 fixes carry altitude — 40%, below the 50% floor (validCount itself is
        // still ≥ 2, so this exercises the coverage-ratio guard, not the count guard).
        let coordinates = route([10, nil, 20, nil, nil])
        XCTAssertNil(WorkoutRoute3DProjection.projected(for: coordinates))
    }

    // MARK: - Invalid-coordinate filtering

    func testInvalidLatitudeFixesAreDroppedAndOutputsStayIndexAligned() throws {
        let validAltitudes: [Double] = [0, 50, 100, 150, 200]
        var mixed: [RouteCoordinate] = []
        for (offset, altitude) in validAltitudes.enumerated() {
            mixed.append(gridFix(offset, altitude: altitude))
            // An invalid-latitude fix after every valid one; `normalizedPoints` and the
            // projection both drop these before altitude/index alignment happens.
            mixed.append(RouteCoordinate(latitude: 200, longitude: 20, speed: 0, altitude: 999))
        }

        let mixedProjected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: mixed))
        let validOnly = route(validAltitudes.map { $0 })
        let validProjected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: validOnly))

        XCTAssertEqual(mixedProjected.top.count, validAltitudes.count)
        XCTAssertEqual(mixedProjected.base.count, validAltitudes.count)
        XCTAssertEqual(mixedProjected, validProjected)
    }

    // MARK: - Gap filling

    func testInternalGapInterpolatesLinearly() throws {
        // Two low-altitude fixes and seven high-altitude ones robustly pin the
        // percentile range to [0, 200] (see the relief tests below for why padding is
        // needed), with a single internal gap between two known, unclamped altitudes.
        let coordinates = route([0, 0, 50, nil, 150, 200, 200, 200, 200, 200, 200, 200])
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        // Altitude 100 (the linear interpolation of 50 and 150) should lift the gap
        // point exactly halfway between its neighbours' lifts — the height mapping is
        // affine in altitude here since none of the three points clamp against the
        // trimmed [0, 200] range.
        let neighbourAverage = (lift(projected, 2) + lift(projected, 4)) / 2
        XCTAssertEqual(lift(projected, 3), neighbourAverage, accuracy: 1e-9)
        XCTAssertEqual(lift(projected, 3), deckUnits + 0.15, accuracy: 1e-9)
    }

    func testLeadingAndTrailingGapsTakeNearest() throws {
        // Leading gap (index 0) takes index 1's altitude; trailing gap (index 3) takes
        // index 2's — both exactly 50% coverage, so the route still projects.
        let coordinates = route([nil, 50, 150, nil])
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        XCTAssertEqual(lift(projected, 0), lift(projected, 1), accuracy: 1e-9)
        XCTAssertEqual(lift(projected, 3), lift(projected, 2), accuracy: 1e-9)
    }

    // MARK: - Flat route

    func testFlatRouteLiftsEveryPointOntoTheSameDeck() throws {
        let coordinates = route([100, 100, 100, 100, 100])
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))
        let ground = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))

        for index in 0..<coordinates.count {
            XCTAssertEqual(projected.top[index].y, projected.base[index].y - deckUnits, accuracy: 1e-9)
            XCTAssertEqual(projected.base[index].y, ground[index].y * groundSquash, accuracy: 1e-9)
        }
    }

    // MARK: - Relief scaling

    /// Builds a 10-fix route where two fixes sit at `low` and eight at `high`, which
    /// pins the trimmed percentile range to exactly `[low, high]` — enough fixes on
    /// each plateau that the 2nd/98th-percentile indices still land on the extremes.
    private func reliefRoute(low: Double, high: Double) -> [RouteCoordinate] {
        route([low, low, high, high, high, high, high, high, high, high])
    }

    func test200MetreReliefLiftsTheHighPointByDeckPlusMaximumRelief() throws {
        let coordinates = reliefRoute(low: 0, high: fullReliefMetres)
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        XCTAssertEqual(lift(projected, 0), deckUnits, accuracy: 1e-9)
        XCTAssertEqual(lift(projected, 9), deckUnits + maximumReliefUnits, accuracy: 1e-9)
    }

    func test400MetreReliefClampsToTheMaximum() throws {
        let coordinates = reliefRoute(low: 0, high: 400)
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        XCTAssertEqual(lift(projected, 0), deckUnits, accuracy: 1e-9)
        XCTAssertEqual(lift(projected, 9), deckUnits + maximumReliefUnits, accuracy: 1e-9)
    }

    func test100MetreReliefIsHalfTheMaximum() throws {
        let coordinates = reliefRoute(low: 0, high: 100)
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        XCTAssertEqual(lift(projected, 0), deckUnits, accuracy: 1e-9)
        XCTAssertEqual(lift(projected, 9), deckUnits + maximumReliefUnits / 2, accuracy: 1e-9)
    }

    func testSingleSpikeAmongSmallVariationDoesNotSetTheRange() throws {
        // 20 fixes hovering ±5 m around 100 m, with one fix spiking to 1000 m. The
        // 2nd/98th percentile trim excludes the spike from the range entirely, so the
        // relief stays keyed to the ~10 m of ordinary variation.
        let spikeIndex = 5
        var altitudes: [Double] = []
        for index in 0..<20 {
            altitudes.append(index == spikeIndex ? 1000 : (index % 2 == 0 ? 95 : 105))
        }
        let coordinates = route(altitudes)
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        // Percentiles: sorted altitudes are ten 95s, nine 105s, then the 1000 spike
        // last; lo = sorted[Int(19*0.02)] = sorted[0] = 95, hi = sorted[Int(19*0.98)] =
        // sorted[18] = 105 — the spike itself never enters [lo, hi].
        let expectedReliefUnits = maximumReliefUnits * min(1, 10.0 / fullReliefMetres)

        // The spike's own lift clamps at the top of that (small) relief range, same as
        // any of the ordinary 105 m points — it never reaches further than they do.
        XCTAssertEqual(lift(projected, spikeIndex), deckUnits + expectedReliefUnits, accuracy: 1e-9)

        let nonSpikeLifts = (0..<20).filter { $0 != spikeIndex }.map { lift(projected, $0) }
        XCTAssertEqual(nonSpikeLifts.max() ?? 0, deckUnits + expectedReliefUnits, accuracy: 1e-9)
        // Well under what an unclipped 900 m spike-driven range would have produced.
        XCTAssertLessThan(nonSpikeLifts.max() ?? 0, deckUnits + 0.02)
    }

    // MARK: - Non-finite altitudes

    func testNonFiniteAltitudeIsTreatedAsMissing() throws {
        let withNaN = route([10, .nan, 20, nil])
        let withNil = route([10, nil, 20, nil])

        XCTAssertEqual(
            try XCTUnwrap(WorkoutRoute3DProjection.projected(for: withNaN)),
            try XCTUnwrap(WorkoutRoute3DProjection.projected(for: withNil))
        )
    }

    // MARK: - Yaw

    /// A due-east route at constant latitude: the latitude span is below the
    /// projection's degenerate epsilon, so every ground point sits at y = 0.5, while
    /// the longitude span sets the scale and spreads x across the full 0...1.
    private func eastWestRoute() -> [RouteCoordinate] {
        (0..<10).map { index in
            RouteCoordinate(latitude: 10, longitude: 20.00 + Double(index) * 0.002, speed: 0, altitude: 100)
        }
    }

    func testDefaultYawIsZero() throws {
        let coordinates = route([0, 50, 100, 150, 200])

        XCTAssertEqual(
            try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates)),
            try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates, yaw: 0))
        )
    }

    func testQuarterTurnSwingsTheEastEndTowardsTheCamera() throws {
        let coordinates = eastWestRoute()
        let ground = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
        // The fixture's premise: the last fix sits at the east end of a flat line.
        XCTAssertEqual(ground[9].x, 1, accuracy: 1e-9)
        XCTAssertEqual(ground[9].y, 0.5, accuracy: 1e-9)

        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates, yaw: .pi / 2))

        // A quarter turn clockwise takes (1, 0.5) to (0.5, 1) on the ground, which the
        // camera then squashes to y = 1 * 0.55.
        XCTAssertEqual(Double(projected.base[9].x), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Double(projected.base[9].y), groundSquash, accuracy: 1e-9)
    }

    func testFitReferenceIsTheRestPoseAndDoesNotTurn() throws {
        let coordinates = route([0, 50, 100, 150, 200])
        let rest = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))
        let turned = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates, yaw: 1.3))

        XCTAssertEqual(rest.fitReference, rest.top + rest.base)
        // The hero frames by this, so it has to stay put while the ribbon rotates.
        XCTAssertEqual(turned.fitReference, rest.fitReference)
        XCTAssertNotEqual(turned.top, rest.top)
    }

    func testNonFiniteYawIsTreatedAsZero() throws {
        let coordinates = route([0, 50, 100, 150, 200])
        let unturned = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates, yaw: 0))

        XCTAssertEqual(try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates, yaw: .nan)), unturned)
        XCTAssertEqual(try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates, yaw: .infinity)), unturned)
    }

    // MARK: - Lift units (the map compositor's entry point)

    /// The ribbon's lift is exactly what the projection puts between `base` and `top`,
    /// so the map's 2.5D route and the oblique hero rise by the same amount.
    func testLiftUnitsMatchTheProjectedRibbonsOwnLift() throws {
        let coordinates = route([0, 0, 50, 100, 150, 200, 200, 200, 200, 200])
        let lift = try XCTUnwrap(WorkoutRoute3DProjection.liftUnits(for: coordinates))
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))

        XCTAssertEqual(lift.count, coordinates.count)
        for index in coordinates.indices {
            XCTAssertEqual(lift[index], self.lift(projected, index), accuracy: 1e-9)
        }
    }

    /// The deck is part of the lift, not something the drawing adds: a dead-flat route
    /// still stands one deck off the ground.
    func testLiftUnitsIncludeTheDeckOnAFlatRoute() throws {
        let lift = try XCTUnwrap(WorkoutRoute3DProjection.liftUnits(for: route([100, 100, 100, 100, 100])))

        for value in lift {
            XCTAssertEqual(value, deckUnits, accuracy: 1e-9)
        }
    }

    func testLiftUnitsSpanDeckToDeckPlusFullRelief() throws {
        let lift = try XCTUnwrap(WorkoutRoute3DProjection.liftUnits(for: reliefRoute(low: 0, high: fullReliefMetres)))

        XCTAssertEqual(lift.min() ?? 0, deckUnits, accuracy: 1e-9)
        XCTAssertEqual(lift.max() ?? 0, deckUnits + maximumReliefUnits, accuracy: 1e-9)
    }

    func testLiftUnitsAreNilUnderTheSameRulesAsTheProjection() {
        // Too few altitudes, below the coverage floor, and a degenerate (treadmill
        // jitter) ground trace — every case that makes `projected` nil.
        XCTAssertNil(WorkoutRoute3DProjection.liftUnits(for: route([100, nil, nil])))
        XCTAssertNil(WorkoutRoute3DProjection.liftUnits(for: route([10, nil, 20, nil, nil])))

        let jitter = (0..<10).map { index in
            RouteCoordinate(latitude: 10 + Double(index) * 1e-6, longitude: 20, speed: 0, altitude: 100)
        }
        XCTAssertNil(WorkoutShareRouteProjection.normalizedPoints(for: jitter))
        XCTAssertNil(WorkoutRoute3DProjection.liftUnits(for: jitter))
    }

    func testLiftUnitsDropInvalidFixesLikeTheProjection() throws {
        var mixed: [RouteCoordinate] = []
        for (offset, altitude) in [0.0, 50, 100, 150, 200].enumerated() {
            mixed.append(gridFix(offset, altitude: altitude))
            mixed.append(RouteCoordinate(latitude: 200, longitude: 20, speed: 0, altitude: 999))
        }

        let lift = try XCTUnwrap(WorkoutRoute3DProjection.liftUnits(for: mixed))
        XCTAssertEqual(lift.count, 5)
    }

    // MARK: - Count / order preservation

    func testCountAndOrderArePreserved() throws {
        let coordinates = route([0, 50, 100, 150, 200])
        let projected = try XCTUnwrap(WorkoutRoute3DProjection.projected(for: coordinates))
        let ground = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))

        XCTAssertEqual(projected.top.count, coordinates.count)
        XCTAssertEqual(projected.base.count, coordinates.count)
        for index in 0..<coordinates.count {
            XCTAssertEqual(projected.top[index].x, ground[index].x, accuracy: 1e-9)
            XCTAssertEqual(projected.base[index].x, ground[index].x, accuracy: 1e-9)
        }
    }
}
