//
//  WatchMetricDetailSparklineWeeklyTests.swift
//  BodyWatchTests
//
//  Locks `WatchMetricDetailView.sparklineWeekly` (L-36): the weekly series is
//  first re-windowed from the snapshot's generation day onto today, then,
//  when the metric's headline is cleared (`!hasValue`), today's slot is
//  forced to nil so the sparkline doesn't show a value under a "--" headline.
//

import XCTest
@testable import BodyWatch

final class WatchMetricDetailSparklineWeeklyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func metric(displayValue: String, rawValue: Double?, weekly: [Double?]?) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.heartRateVariability,
            title: "HRV",
            displayValue: displayValue,
            unit: "ms",
            score: nil,
            fillFraction: 0,
            rawValue: rawValue,
            weekly: weekly
        )
    }

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
}
