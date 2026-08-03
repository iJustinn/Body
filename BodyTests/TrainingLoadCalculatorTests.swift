//
//  TrainingLoadCalculatorTests.swift
//  BodyTests
//
//  Golden regression for the Phase 1 refactor that split `dailySeries`'s
//  acute/chronic EWA loop out into `series(fromDailyLoads:)` and added the
//  dense `dailyLoadValues(from:startDate:endDate:calendar:)` the phone→watch
//  compute seed transports. Locks the exact math against hand-computed
//  expected ratios so the split can't silently change the numbers, and checks
//  the refactored path (`dailyLoadValues` → reconstituted pairs →
//  `series(fromDailyLoads:)`) reproduces `dailySeries` exactly.
//

import XCTest
@testable import Body

final class TrainingLoadCalculatorTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func day(_ offset: Int, from start: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    /// 5 consecutive days, workouts on day 0/2/4 only (day 1/3 are zero-load
    /// gaps) — enough to exercise the EWA's day-to-day decay.
    private func fixture() -> (start: Date, end: Date, workouts: [WorkoutSummary]) {
        let start = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end = day(4, from: start)
        let workouts = [
            WorkoutSummary(type: .running, startDate: day(0, from: start), duration: 3_600, effortLevel: 8),
            WorkoutSummary(type: .running, startDate: day(2, from: start), duration: 1_800, effortLevel: 6),
            WorkoutSummary(type: .running, startDate: day(4, from: start), duration: 5_400, effortLevel: 4)
        ]
        return (start, end, workouts)
    }

    /// Hand-computed (via an independent double-precision replay of the EWA
    /// recurrence, not by reading the implementation) acute/chronic ratios for
    /// the fixture's daily loads `[480.0, 0.0, 180.0, 0.0, 360.0]` with the
    /// production 7-day acute / 42-day chronic smoothing factors. The ratio is
    /// scale-invariant, so these match the ratios for `[8, 0, 3, 0, 6]` too —
    /// only the dense-array test below checks the actual load magnitudes.
    private let expectedRatios: [Double] = [
        1.0,
        0.7865853658536585,
        0.7082482124616956,
        0.5570976793143825,
        0.634509906202084
    ]

    func testDailySeriesMatchesHandComputedEWARatios() {
        let (start, end, workouts) = fixture()
        let series = TrainingLoadCalculator.dailySeries(from: workouts, startDate: start, endDate: end, calendar: calendar)

        XCTAssertEqual(series.points.count, expectedRatios.count)
        for (offset, expected) in expectedRatios.enumerated() {
            let point = series.point(on: day(offset, from: start))
            XCTAssertEqual(point?.value ?? .nan, expected, accuracy: 1e-9, "day \(offset)")
        }
    }

    func testDailyLoadValuesProducesTheDenseZeroFilledArray() {
        let (start, end, workouts) = fixture()
        let result = TrainingLoadCalculator.dailyLoadValues(from: workouts, startDate: start, endDate: end, calendar: calendar)

        // `TrainingLoadCalculator.load` is `(duration in seconds / 60) * effort`
        // i.e. minutes × effort: day 0 = 60min × 8 = 480, day 2 = 30min × 6 = 180,
        // day 4 = 90min × 4 = 360.
        let unwrapped = try! XCTUnwrap(result)
        XCTAssertEqual(unwrapped.startDay, start)
        XCTAssertEqual(unwrapped.loads, [480.0, 0.0, 180.0, 0.0, 360.0])
    }

    /// The refactored composition path — `dailyLoadValues` reconstituted into
    /// `(date, load)` pairs and fed through `series(fromDailyLoads:)` — must
    /// reproduce `dailySeries` exactly, since that's now its only caller.
    func testSeriesFromDailyLoadsComposedFromDailyLoadValuesMatchesDailySeries() throws {
        let (start, end, workouts) = fixture()
        let direct = TrainingLoadCalculator.dailySeries(from: workouts, startDate: start, endDate: end, calendar: calendar)

        let dense = try XCTUnwrap(TrainingLoadCalculator.dailyLoadValues(from: workouts, startDate: start, endDate: end, calendar: calendar))
        let reconstituted = dense.loads.enumerated().map { offset, load in
            (date: day(offset, from: dense.startDay), load: load)
        }
        let composed = TrainingLoadCalculator.series(fromDailyLoads: reconstituted)

        XCTAssertEqual(composed, direct)
    }

    func testEmptyWorkoutsProduceEmptySeriesAndNilDailyLoadValues() {
        let series = TrainingLoadCalculator.dailySeries(from: [])
        XCTAssertTrue(series.isEmpty)
        XCTAssertNil(TrainingLoadCalculator.dailyLoadValues(from: []))

        // `dailySeries([])` never reaches `series(fromDailyLoads:)` — its own
        // empty guard short-circuits first (`dailyLoadPoints` is already
        // empty). Call `series(fromDailyLoads:)` DIRECTLY with an empty array
        // so its own guard is what's actually exercised.
        XCTAssertEqual(TrainingLoadCalculator.series(fromDailyLoads: []), .empty)
    }
}
