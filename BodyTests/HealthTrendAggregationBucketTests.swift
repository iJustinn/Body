//
//  HealthTrendAggregationBucketTests.swift
//  BodyTests
//
//  Covers the long-range chart bucketing rule in `bodyTrendAggregationBuckets`
//  (via `HealthTrendSeries.chartCalendarPoints`/`sourceComparisonChartCalendarPoints`):
//  buckets must anchor from the newest day (today) backwards so a leftover
//  partial bucket falls on the oldest end, not the newest. Regression coverage
//  for the bug where 6-month/year charts silently dropped today's reading.
//

import XCTest
@testable import Body

final class HealthTrendAggregationBucketTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    /// One data point per day for `range.dayCount` days ending at `today`
    /// (inclusive). Every day gets `baseValue` except `today`, which gets
    /// `todayValue` — a large outlier so any bucket average that includes
    /// today is easy to distinguish from one that doesn't.
    private func makeDailySeries(
        range: BodyHealthTrendRange,
        today: Date,
        baseValue: Double = 1,
        todayValue: Double = 1000
    ) -> HealthTrendSeries {
        let todayStart = calendar.startOfDay(for: today)
        let points = (0..<range.dayCount).map { offset -> HealthTrendDataPoint in
            let day = calendar.date(byAdding: .day, value: -(range.dayCount - 1) + offset, to: todayStart)!
            let isToday = offset == range.dayCount - 1
            return HealthTrendDataPoint(date: day, value: isToday ? todayValue : baseValue)
        }
        return HealthTrendSeries(points: points)
    }

    private func windowStart(for range: BodyHealthTrendRange, today: Date) -> Date {
        let todayStart = calendar.startOfDay(for: today)
        return calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: todayStart)!
    }

    func testYearRangeChartPointsIncludeToday() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
        let series = makeDailySeries(range: .recentYear, today: today)

        let points = series.chartCalendarPoints(to: .recentYear, calendar: calendar, date: today)

        XCTAssertEqual(points.count, BodyHealthTrendRange.recentYear.chartCalendarPointCount)
        let lastPoint = try XCTUnwrap(points.last)
        XCTAssertEqual(lastPoint.endDate, calendar.startOfDay(for: today))
        // 365 / 12 = 30 full buckets, remainder 5 (dropped from the oldest
        // end) -> every kept bucket, including the last, is a full 12-day
        // bucket: 11 base-value days plus 1 (today) outlier.
        let expectedAverage = (11 * 1.0 + 1000) / 12
        XCTAssertEqual(lastPoint.value ?? 0, expectedAverage, accuracy: 0.001)
    }

    func testSixMonthRangeDropsOldestPartialBucketAndKeepsToday() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
        let range = BodyHealthTrendRange.recentSixMonths
        let series = makeDailySeries(range: range, today: today)

        let points = series.chartCalendarPoints(to: range, calendar: calendar, date: today)

        // 183 / 6 = 30 full buckets with remainder 3 -> the oldest partial
        // bucket (3 days) is dropped, leaving exactly 30 full 6-day buckets.
        XCTAssertEqual(points.count, range.chartCalendarPointCount)
        XCTAssertEqual(points.count, 30)

        let droppedDayCount = range.dayCount % range.chartAggregationDayCount
        let expectedFirstBucketStart = calendar.date(
            byAdding: .day,
            value: droppedDayCount,
            to: windowStart(for: range, today: today)
        )
        let firstPoint = try XCTUnwrap(points.first)
        XCTAssertEqual(firstPoint.startDate, expectedFirstBucketStart)

        let lastPoint = try XCTUnwrap(points.last)
        XCTAssertEqual(lastPoint.endDate, calendar.startOfDay(for: today))
        XCTAssertEqual(lastPoint.value ?? 0, (5 * 1 + 1000) / 6, accuracy: 0.001)
    }

    func testSourceComparisonBucketsAlignAcrossPrimaryAndSecondarySeries() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
        let range = BodyHealthTrendRange.recentYear
        let primary = makeDailySeries(range: range, today: today, baseValue: 1, todayValue: 1000)
        let secondary = makeDailySeries(range: range, today: today, baseValue: 50, todayValue: 2000)

        let primaryPoints = primary.sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: today)
        let secondaryPoints = secondary.sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: today)

        XCTAssertEqual(primaryPoints.count, secondaryPoints.count)
        XCTAssertFalse(primaryPoints.isEmpty)
        for (primaryPoint, secondaryPoint) in zip(primaryPoints, secondaryPoints) {
            XCTAssertEqual(primaryPoint.startDate, secondaryPoint.startDate)
            XCTAssertEqual(primaryPoint.endDate, secondaryPoint.endDate)
        }

        // Both series' final bucket must include today.
        XCTAssertEqual(primaryPoints.last?.endDate, calendar.startOfDay(for: today))
        XCTAssertEqual(secondaryPoints.last?.endDate, calendar.startOfDay(for: today))
    }
}
