//
//  RecoveryScoreCalculatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class RecoveryScoreCalculatorTests: XCTestCase {

    // MARK: - Sleep Goal (C1 regression)

    /// Regression for C1: the sleep component must honor the caller's
    /// `idealSleepDuration` rather than `BodySleepDurationGoal.defaultDuration`.
    /// A user with a 6-hour goal who slept exactly 6 hours should NOT see a
    /// "below goal" driver, even though 6 hours is well below the 8-hour
    /// hardcoded default the calculator previously used.
    func testSleepComponentHonorsShorterUserGoal() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let sixHours: TimeInterval = 6 * 60 * 60
        let trends = trendsWithSleepDuration(sixHours, on: scoreDay, calendar: calendar)

        let summary = RecoveryScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: sixHours,
            calendar: calendar
        )

        let sleep = try XCTUnwrap(summary.components.first { $0.kind == .sleep })
        XCTAssertNotNil(sleep.score)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sleep.score), 75)
        XCTAssertFalse(summary.drivers.contains { $0.kind == .sleepDurationBelowGoal })
    }

    /// Same fixture, but using the default 8-hour goal: the user only slept
    /// 6 hours, which is 0.75 of the goal — should drop into the
    /// "below goal" branch and yield a noticeably lower sleep score.
    func testSleepComponentPenalizesSameDurationAgainstLongerGoal() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let sixHours: TimeInterval = 6 * 60 * 60
        let eightHours: TimeInterval = 8 * 60 * 60
        let trends = trendsWithSleepDuration(sixHours, on: scoreDay, calendar: calendar)

        let summary = RecoveryScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: eightHours,
            calendar: calendar
        )

        let sleep = try XCTUnwrap(summary.components.first { $0.kind == .sleep })
        XCTAssertNotNil(sleep.score)
        XCTAssertLessThan(try XCTUnwrap(sleep.score), 75)
        XCTAssertTrue(summary.drivers.contains { $0.kind == .sleepDurationBelowGoal })
    }

    /// Direct sanity check that the goal parameter actually changes the score
    /// for identical sleep input — guards against future regressions where
    /// the parameter is accepted but silently dropped on the way down.
    func testSleepComponentScoreDiffersWhenOnlyGoalChanges() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let sixHours: TimeInterval = 6 * 60 * 60
        let trends = trendsWithSleepDuration(sixHours, on: scoreDay, calendar: calendar)

        let lenientGoal = RecoveryScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: 6 * 60 * 60,
            calendar: calendar
        )
        let strictGoal = RecoveryScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: 9 * 60 * 60,
            calendar: calendar
        )

        let lenientSleepScore = try XCTUnwrap(lenientGoal.components.first { $0.kind == .sleep }?.score)
        let strictSleepScore = try XCTUnwrap(strictGoal.components.first { $0.kind == .sleep }?.score)
        XCTAssertGreaterThan(lenientSleepScore, strictSleepScore)
    }

    /// `dailySeries` recomputes recovery for every day in the window. It must
    /// thread the configured sleep goal through to each call rather than
    /// silently using the default.
    func testDailySeriesForwardsSleepGoalToEachDay() throws {
        let calendar = Calendar.bodyGregorian
        let endDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let startDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: endDay))
        let sixHours: TimeInterval = 6 * 60 * 60
        let trends = trendsWithSleepDurationForEachDay(
            sixHours,
            startDay: startDay,
            endDay: endDay,
            calendar: calendar
        )

        let lenient = RecoveryScoreCalculator.dailySeries(
            healthSummary: .empty,
            trends: trends,
            startDate: startDay,
            endDate: endDay,
            idealSleepDuration: 6 * 60 * 60,
            calendar: calendar
        )
        let strict = RecoveryScoreCalculator.dailySeries(
            healthSummary: .empty,
            trends: trends,
            startDate: startDay,
            endDate: endDay,
            idealSleepDuration: 9 * 60 * 60,
            calendar: calendar
        )

        XCTAssertEqual(lenient.points.count, 3)
        XCTAssertEqual(strict.points.count, 3)
        for index in 0..<3 {
            XCTAssertGreaterThan(
                lenient.points[index].value,
                strict.points[index].value,
                "Day \(index) recovery score should be higher when the configured goal is shorter"
            )
        }
    }

    // MARK: - Robust Baseline

    func testRobustBaselineReturnsNilBelowMinimumDays() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let values = dailyValues(
            constants: Array(repeating: 50.0, count: RecoveryScoreCalculator.minimumBaselineDayCount - 1),
            endingDayBefore: scoreDay,
            calendar: calendar
        )

        XCTAssertNil(RecoveryScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 0.1,
            calendar: calendar
        ))
    }

    func testRobustBaselineComputesMedianFromPriorWindow() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let values = dailyValues(
            constants: Array(repeating: 60.0, count: 20),
            endingDayBefore: scoreDay,
            calendar: calendar
        )

        let baseline = try XCTUnwrap(RecoveryScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 0.1,
            calendar: calendar
        ))

        XCTAssertEqual(baseline.median, 60, accuracy: 0.0001)
        XCTAssertEqual(baseline.spread, 0.1, accuracy: 0.0001, "constant input → MAD is 0 → spread should be floored")
        XCTAssertEqual(baseline.validDayCount, 20)
    }

    func testRobustBaselineExcludesScoringDayAndFuture() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        var values = dailyValues(
            constants: Array(repeating: 60.0, count: 20),
            endingDayBefore: scoreDay,
            calendar: calendar
        )
        // An extreme outlier ON the scoring day must not pull the baseline.
        values.append(RecoveryScoreCalculator.DailyValue(date: scoreDay, value: 9_999))

        let baseline = try XCTUnwrap(RecoveryScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 0.1,
            calendar: calendar
        ))

        XCTAssertEqual(baseline.median, 60, accuracy: 0.0001)
        XCTAssertEqual(baseline.validDayCount, 20)
    }

    // MARK: - Robust Z-Score

    func testRobustZScoreFormula() {
        let baseline = RecoveryScoreCalculator.Baseline(median: 60, spread: 5, validDayCount: 20)
        XCTAssertEqual(RecoveryScoreCalculator.robustZScore(value: 65, baseline: baseline), 1.0, accuracy: 0.0001)
        XCTAssertEqual(RecoveryScoreCalculator.robustZScore(value: 50, baseline: baseline), -2.0, accuracy: 0.0001)
    }

    func testRobustZScoreReturnsZeroForZeroSpread() {
        let baseline = RecoveryScoreCalculator.Baseline(median: 60, spread: 0, validDayCount: 20)
        XCTAssertEqual(RecoveryScoreCalculator.robustZScore(value: 99, baseline: baseline), 0)
    }

    func testRobustZScoreReturnsZeroForNonFiniteValue() {
        let baseline = RecoveryScoreCalculator.Baseline(median: 60, spread: 5, validDayCount: 20)
        XCTAssertEqual(RecoveryScoreCalculator.robustZScore(value: .nan, baseline: baseline), 0)
        XCTAssertEqual(RecoveryScoreCalculator.robustZScore(value: .infinity, baseline: baseline), 0)
    }

    // MARK: - Summary aggregation

    func testSummaryReturnsUnavailableWithNoSignals() {
        let summary = RecoveryScoreCalculator.summary(
            on: Date(),
            healthSummary: .empty,
            trends: .empty
        )

        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.status, .unavailable)
        XCTAssertEqual(summary.confidence, .unavailable)
    }

    // MARK: - Helpers

    private func trendsWithSleepDuration(
        _ duration: TimeInterval,
        on date: Date,
        calendar: Calendar
    ) -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(date: date, summary: SleepSummary(duration: duration))
        ])
        return trends
    }

    private func trendsWithSleepDurationForEachDay(
        _ duration: TimeInterval,
        startDay: Date,
        endDay: Date,
        calendar: Calendar
    ) -> HealthTrendSnapshot {
        var days: [SleepDaySummary] = []
        var day = calendar.startOfDay(for: startDay)
        let lastDay = calendar.startOfDay(for: endDay)
        while day <= lastDay {
            days.append(SleepDaySummary(date: day, summary: SleepSummary(duration: duration)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }
        var trends = HealthTrendSnapshot.empty
        trends.sleepHistory = SleepHistorySnapshot(days: days)
        return trends
    }

    private func dailyValues(
        constants: [Double],
        endingDayBefore scoreDay: Date,
        calendar: Calendar
    ) -> [RecoveryScoreCalculator.DailyValue] {
        constants.enumerated().compactMap { offset, value in
            // Place values starting one day before scoreDay, going back in time.
            // This guarantees they fall inside the 56-day pre-window.
            guard let date = calendar.date(byAdding: .day, value: -(offset + 1), to: scoreDay) else {
                return nil
            }

            return RecoveryScoreCalculator.DailyValue(date: date, value: value)
        }
    }
}
