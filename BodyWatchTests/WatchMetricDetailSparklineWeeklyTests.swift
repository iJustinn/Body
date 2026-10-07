//
//  WatchMetricDetailSparklineWeeklyTests.swift
//  BodyWatchTests
//
//  Locks `WatchMetricDetailView.sparklineWeekly` (L-36): the weekly series is
//  first re-windowed from the snapshot's generation day onto today, then,
//  when the metric's headline is cleared (`!hasValue`), today's slot is
//  forced to nil so the sparkline doesn't show a value under a "--" headline.
//  `sparklineRanges` (the Heart Rate and HRV daily low/high capsules) follows
//  the same rewind and the same today rule, so each capsule stays under its
//  own day's point.
//

import XCTest
@testable import BodyWatch

final class WatchMetricDetailSparklineWeeklyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func metric(displayValue: String, rawValue: Double?, weekly: [Double?]?, weeklyRanges: [WatchDayRange?]? = nil) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.heartRateVariability,
            title: "HRV",
            displayValue: displayValue,
            unit: "ms",
            score: nil,
            fillFraction: 0,
            rawValue: rawValue,
            weekly: weekly,
            weeklyRanges: weeklyRanges
        )
    }

    private let week: [Double?] = [40, 42, 41, 45, 44, 43, 46]
    private let weekRanges: [WatchDayRange?] = [
        .init(low: 30, high: 50), .init(low: 31, high: 55), nil, .init(low: 33, high: 60),
        .init(low: 34, high: 52), .init(low: 35, high: 51), .init(low: 36, high: 58)
    ]

    func testClearedHeadlineNilsTodaysSlot() {
        let today = Date()
        let cleared = metric(displayValue: "--", rawValue: nil, weekly: [40, 42, 41, 45, 44, 43, 46])
        let weekly = WatchMetricDetailView.sparklineWeekly(metric: cleared, generatedAt: today, today: today, calendar: calendar)
        XCTAssertEqual(weekly?.last ?? nil, nil, "A cleared headline must not show a value in today's sparkline slot.")
        XCTAssertEqual(weekly?.dropLast().compactMap { $0 }, [40, 42, 41, 45, 44, 43], "History before today is unaffected.")
    }

    func testValuedHeadlineKeepsTodaysSlot() {
        let today = Date()
        let valued = metric(displayValue: "46", rawValue: 46, weekly: [40, 42, 41, 45, 44, 43, 46])
        let weekly = WatchMetricDetailView.sparklineWeekly(metric: valued, generatedAt: today, today: today, calendar: calendar)
        XCTAssertEqual(weekly?.last ?? nil, 46)
    }

    func testAllNilWeeklyStaysNil() {
        let today = Date()
        let cleared = metric(displayValue: "--", rawValue: nil, weekly: [nil, nil, nil])
        XCTAssertNil(WatchMetricDetailView.sparklineWeekly(metric: cleared, generatedAt: today, today: today, calendar: calendar))
    }

    func testClearedHeadlineGeneratedYesterdayKeepsYesterdaysValueShiftedAndNilsToday() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let cleared = metric(displayValue: "--", rawValue: nil, weekly: [40, 42, 41, 45, 44, 43, 46])
        let weekly = WatchMetricDetailView.sparklineWeekly(metric: cleared, generatedAt: yesterday, today: today, calendar: calendar)
        XCTAssertEqual(weekly?.last ?? nil, nil, "Today's slot, freshly shifted in, must stay nil.")
        XCTAssertEqual(weekly?.dropLast().last ?? nil, 46, "Yesterday's real value shifts into the second to last slot.")
    }

    func testValuedHeadlineGeneratedYesterdayStillShiftsSlots() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let valued = metric(displayValue: "46", rawValue: 46, weekly: [40, 42, 41, 45, 44, 43, 46])
        let weekly = WatchMetricDetailView.sparklineWeekly(metric: valued, generatedAt: yesterday, today: today, calendar: calendar)
        XCTAssertEqual(weekly?.last ?? nil, nil, "Re-windowing shifts in an empty today slot regardless of hasValue.")
        XCTAssertEqual(weekly?.dropLast().last ?? nil, 46, "Yesterday's real value shifts into the second to last slot.")
    }

    // MARK: - Daily ranges

    func testRangesKeepTodayWithAValuedHeadline() {
        let today = Date()
        let valued = metric(displayValue: "46", rawValue: 46, weekly: week, weeklyRanges: weekRanges)
        let ranges = WatchMetricDetailView.sparklineRanges(metric: valued, generatedAt: today, today: today, calendar: calendar)
        XCTAssertEqual(ranges, weekRanges)
    }

    func testClearedHeadlineNilsTodaysRange() {
        let today = Date()
        let cleared = metric(displayValue: "--", rawValue: nil, weekly: week, weeklyRanges: weekRanges)
        let ranges = WatchMetricDetailView.sparklineRanges(metric: cleared, generatedAt: today, today: today, calendar: calendar)
        XCTAssertEqual(ranges?.last ?? nil, nil, "No capsule under a \"--\" headline, like today's point.")
        XCTAssertEqual(ranges.map { Array($0.dropLast()) }, Array(weekRanges.dropLast()), "History before today is unaffected.")
    }

    func testRangesShiftWithTheWeekSoEachStaysUnderItsDay() {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let valued = metric(displayValue: "46", rawValue: 46, weekly: week, weeklyRanges: weekRanges)
        let weekly = WatchMetricDetailView.sparklineWeekly(metric: valued, generatedAt: yesterday, today: today, calendar: calendar)
        let ranges = WatchMetricDetailView.sparklineRanges(metric: valued, generatedAt: yesterday, today: today, calendar: calendar)
        XCTAssertEqual(ranges?.count, weekly?.count)
        XCTAssertEqual(ranges?.last ?? nil, nil, "Today's slot, freshly shifted in, has no range.")
        XCTAssertEqual(ranges?.dropLast().last ?? nil, weekRanges.last ?? nil, "Yesterday's range shifts with yesterday's point.")
        XCTAssertEqual(weekly?.dropLast().last ?? nil, 46)
    }

    func testMetricsWithoutRangesGetNone() {
        let today = Date()
        let plain = metric(displayValue: "46", rawValue: 46, weekly: week)
        XCTAssertNil(WatchMetricDetailView.sparklineRanges(metric: plain, generatedAt: today, today: today, calendar: calendar))
        let empty = metric(displayValue: "46", rawValue: 46, weekly: week, weeklyRanges: [nil, nil, nil])
        XCTAssertNil(WatchMetricDetailView.sparklineRanges(metric: empty, generatedAt: today, today: today, calendar: calendar))
    }

    func testRangeCapsuleWidthStaysBetweenFourAndEightPoints() {
        XCTAssertEqual(WatchSparklineView.rangeWidth(forSlotWidth: 4), 4)
        XCTAssertEqual(WatchSparklineView.rangeWidth(forSlotWidth: 100), 8)
        XCTAssertEqual(WatchSparklineView.rangeWidth(forSlotWidth: 25), 6.5, accuracy: 0.001)
    }
}
