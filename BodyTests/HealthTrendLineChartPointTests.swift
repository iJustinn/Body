//
//  HealthTrendLineChartPointTests.swift
//  BodyTests
//
//  `compressedStableLineChartPoints`'s early-out (finite reading count at or
//  under the cap) must return only the finite readings, not every day in the
//  range including nil gaps, so callers that build an x-domain from these
//  points don't silently widen it back out to the full range.
//

import XCTest
@testable import Body

final class HealthTrendLineChartPointTests: XCTestCase {
    func testLineChartCalendarPointsUnderCapReturnsOnlyTheFinitePoints() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let monthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentMonth.dayCount - 1),
            to: currentDayStart
        ))
        // 30 days in the range, but only 20 carry a reading; the rest are gaps.
        let points = try (0..<BodyHealthTrendRange.recentMonth.dayCount).compactMap { offset -> HealthTrendDataPoint? in
            guard offset % 3 != 0 else {
                return nil
            }
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monthStart))
            return HealthTrendDataPoint(date: date, value: 100 + Double(offset))
        }
        XCTAssertEqual(points.count, 20)
        let series = HealthTrendSeries(points: points)

        let lineChartPoints = series.lineChartCalendarPoints(
            to: .recentMonth,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(lineChartPoints.count, 20)
        XCTAssertEqual(lineChartPoints.compactMap(\.value).count, 20)
    }

    func testLineChartCalendarPointsOverCapCompressesToTwentyFive() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let monthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentMonth.dayCount - 1),
            to: currentDayStart
        ))
        // All 30 days carry a reading, over the 25-point cap.
        let points = try (0..<BodyHealthTrendRange.recentMonth.dayCount).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monthStart))
            return HealthTrendDataPoint(date: date, value: 100 + Double(offset))
        }
        XCTAssertEqual(points.count, 30)
        let series = HealthTrendSeries(points: points)

        let lineChartPoints = series.lineChartCalendarPoints(
            to: .recentMonth,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(lineChartPoints.count, 25)
    }
}
