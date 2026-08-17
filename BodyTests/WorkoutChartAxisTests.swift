//
//  WorkoutChartAxisTests.swift
//  BodyTests
//
//  Covers the shared y-axis helper the workout-detail charts range with: the
//  padding pass, the tick-multiple search, and the degenerate inputs a sensor
//  can hand it.
//

import XCTest
@testable import Body

final class WorkoutChartAxisTests: XCTestCase {
    private func axis(
        _ low: Double,
        _ high: Double,
        step: Double,
        minimumSpan: Double,
        clampToZero: Bool = false
    ) -> (range: ClosedRange<Double>, ticks: [Double]) {
        WorkoutChartAxis.niceRange(
            low: low,
            high: high,
            step: step,
            minimumSpan: minimumSpan,
            clampToZero: clampToZero
        )
    }

    private func assertTicks(
        _ result: (range: ClosedRange<Double>, ticks: [Double]),
        _ expected: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.ticks.count, expected.count, file: file, line: line)
        for (actual, wanted) in zip(result.ticks, expected) {
            XCTAssertEqual(actual, wanted, accuracy: 0.0001, file: file, line: line)
        }
        XCTAssertEqual(result.range.lowerBound, expected.first ?? 0, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(result.range.upperBound, expected.last ?? 0, accuracy: 0.0001, file: file, line: line)
    }

    // MARK: - Worked examples

    func testHillRangeBorrowsTwoMetreTicks() {
        // 45…52 m: pad = max(0.25, 0.7) = 0.7 → 44.3…52.7, widened to the 10 m
        // minimum span → 43.5…53.5; 5 m ticks would give 3 intervals but 2 m ticks
        // already fit in six, so the finer ladder rung wins → 42…54.
        assertTicks(axis(45, 52, step: 5, minimumSpan: 10), [42, 44, 46, 48, 50, 52, 54])
    }

    func testASmallSpanBorrowsFinerTicksThanTheStep() {
        // 47…52 m with a 6 m floor: pad = max(0.25, 0.5) = 0.5 → 46.5…52.5, already
        // past the minimum span; 5 m ticks give 2 intervals but 2 m ticks give 4, so
        // the finer rung is reached first → 46…54.
        assertTicks(axis(47, 52, step: 5, minimumSpan: 6), [46, 48, 50, 52, 54])
        // A stride-like 1.00…1.03 m: pad = max(0.0025, 0.003) = 0.003 → 0.997…1.033,
        // widened to the 0.3 m floor → 0.865…1.165; 0.05 m ticks need 7 intervals, so
        // the ladder settles on 0.10 m → 0.8…1.2.
        assertTicks(axis(1.00, 1.03, step: 0.05, minimumSpan: 0.3), [0.8, 0.9, 1.0, 1.1, 1.2])
    }

    func testFlatDataStillGetsAReadableRange() {
        // No span of its own: pad = half the finest tick either side, then out to
        // the 10 m minimum span → 95…105, which 2 m ticks cover in six intervals.
        assertTicks(axis(100, 100, step: 5, minimumSpan: 10), [94, 96, 98, 100, 102, 104, 106])
    }

    func testClampToZeroShiftsTheWholeRangeUp() {
        // 1…3: pad = max(0.25, 0.2) = 0.25 → 0.75…3.25, widened to the 5-unit
        // minimum span → −0.5…4.5; clamping shifts by 0.5 to 0…5, on 1-unit ticks.
        assertTicks(axis(1, 3, step: 5, minimumSpan: 5, clampToZero: true), [0, 1, 2, 3, 4, 5])
    }

    func testNegativeElevationIsPreservedWithoutClamping() {
        // −30…−10: pad = max(0.25, 2) = 2 → −32…−8, snapping outward on the 5 m
        // grid to −35…−5 (6 intervals); below sea level stays below.
        assertTicks(axis(-30, -10, step: 5, minimumSpan: 10), [-35, -30, -25, -20, -15, -10, -5])
    }

    func testMinimumSpanWidensSymmetrically() {
        // A flat 10 pads to 9.95…10.05, just short of four either side of the
        // minimum span, so the data stays centred at 6…14 on 2-unit ticks.
        let result = axis(10, 10, step: 1, minimumSpan: 8)
        XCTAssertGreaterThanOrEqual(result.range.upperBound - result.range.lowerBound, 8)
        assertTicks(result, [6, 8, 10, 12, 14])
    }

    // MARK: - Degenerate inputs

    func testReversedBoundsAreSwapped() {
        XCTAssertEqual(axis(52, 45, step: 5, minimumSpan: 10).ticks, axis(45, 52, step: 5, minimumSpan: 10).ticks)
    }

    func testNonFiniteBoundsAreTreatedAsZero() {
        // 0…0 padded by half the finest tick, then out to the 10 m minimum span →
        // −5…5, which 2 m ticks cover in six intervals.
        assertTicks(axis(.nan, .nan, step: 5, minimumSpan: 10), [-6, -4, -2, 0, 2, 4, 6])
        // 0…20: pad = max(0.25, 2) = 2 → −2…22 → 5 m ticks → −5…25 (6 intervals).
        assertTicks(axis(.nan, 20, step: 5, minimumSpan: 10), [-5, 0, 5, 10, 15, 20, 25])
    }

    func testNonPositiveStepFallsBackToOne() {
        // Step 1: pad = max(0.05, 0.7) = 0.7 → 44.3…52.7, widened to the 10-unit
        // minimum span → 43.5…53.5, then 2-unit ticks → 42…54.
        let expected: [Double] = [42, 44, 46, 48, 50, 52, 54]
        assertTicks(axis(45, 52, step: 0, minimumSpan: 10), expected)
        assertTicks(axis(45, 52, step: -3, minimumSpan: 10), expected)
    }

    // MARK: - Invariants

    func testEveryRangeKeepsThreeToSevenTicksAndItsMinimumSpan() {
        let steps: [(step: Double, minimumSpan: Double)] = [
            (0.05, 0.3), (0.2, 1), (0.5, 1), (5, 5), (10, 20), (50, 60), (20, 30)
        ]
        for index in 0..<400 {
            let low = Double(index % 97) * 0.37 - 20
            let high = low + Double(index % 53) * 1.13
            for (step, minimumSpan) in steps {
                for clampToZero in [true, false] {
                    let result = axis(low, high, step: step, minimumSpan: minimumSpan, clampToZero: clampToZero)
                    XCTAssertGreaterThanOrEqual(result.ticks.count, 3)
                    XCTAssertLessThanOrEqual(result.ticks.count, 7)
                    XCTAssertGreaterThanOrEqual(
                        result.range.upperBound - result.range.lowerBound,
                        minimumSpan - 0.0001
                    )
                    if clampToZero {
                        XCTAssertGreaterThanOrEqual(result.range.lowerBound, 0)
                    } else {
                        // Only the clamped axis may leave data outside itself, and
                        // only below zero, where rates and counts never land.
                        XCTAssertTrue(result.range.contains(low))
                        XCTAssertTrue(result.range.contains(high))
                    }
                }
            }
        }
    }
}
