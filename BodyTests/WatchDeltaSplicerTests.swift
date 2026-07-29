//
//  WatchDeltaSplicerTests.swift
//  BodyTests
//
//  Covers `WatchDeltaSplicer` (Phase 1c of the on-watch realtime compute
//  plan): the failure/empty/overlap/out-of-window splice semantics for both
//  a plain trend series and sleep history, plus `deltaStart`'s calendar-day
//  (not fixed-48h) math across a DST transition.
//

import XCTest
@testable import Body

final class WatchDeltaSplicerTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func point(_ day: Date, _ value: Double) -> HealthTrendDataPoint {
        HealthTrendDataPoint(date: day, value: value)
    }

    private func day(_ offset: Int, from start: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: start)!
    }

    // MARK: - deltaStart

    func testDeltaStartIsTwoCalendarDaysBeforeDataThroughsDay() throws {
        let dataThrough = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 14)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 15)))

        XCTAssertEqual(WatchDeltaSplicer.deltaStart(dataThrough: dataThrough, calendar: calendar), expected)
    }

    /// US spring-forward 2026 falls on March 8 (a 23-hour local day). A
    /// fixed-48h subtraction from `dataThrough` would land at a different
    /// instant than 2 CALENDAR days back — this locks that `deltaStart` uses
    /// calendar-day arithmetic, so the delta window is always "the last 2
    /// full local days plus today" regardless of DST.
    func testDeltaStartAcrossDSTTransitionUsesCalendarDaysNotFixedSeconds() throws {
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        let dataThrough = try XCTUnwrap(dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 10)))
        let expectedCalendarDayResult = try XCTUnwrap(dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let fixedFortyEightHourResult = dstCalendar.startOfDay(for: dataThrough).addingTimeInterval(-2 * 86_400)

        let result = WatchDeltaSplicer.deltaStart(dataThrough: dataThrough, calendar: dstCalendar)

        XCTAssertEqual(result, expectedCalendarDayResult)
        // The spring-forward day (Mar 8) is only 23h, so subtracting a fixed
        // 48h lands an hour earlier than the calendar-day result.
        XCTAssertNotEqual(result, fixedFortyEightHourResult)
    }

    // MARK: - splice (HealthTrendSeries)

    func testSpliceOnFailureKeepsSeedCompletelyUnchanged() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = HealthTrendSeries(points: [point(day(0, from: start), 1), point(day(5, from: start), 2)])

        let result = WatchDeltaSplicer.splice(
            seedSeries: seed, delta: .failure, from: day(3, from: start), calendar: calendar
        )

        XCTAssertEqual(result, seed)
    }

    func testSpliceOnSuccessEmptyClearsOnlyTheDeltaWindow() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = HealthTrendSeries(points: [
            point(day(0, from: start), 1),
            point(day(3, from: start), 2), // inside the window (>= windowStart)
            point(day(4, from: start), 3)  // inside the window
        ])
        let windowStart = day(3, from: start)

        let result = WatchDeltaSplicer.splice(
            seedSeries: seed, delta: .success(.empty), from: windowStart, calendar: calendar
        )

        XCTAssertEqual(result, HealthTrendSeries(points: [point(day(0, from: start), 1)]))
    }

    func testSpliceReplacesTheOverlappingWindowWithDeltaPoints() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = HealthTrendSeries(points: [
            point(day(0, from: start), 1),   // before window — kept
            point(day(3, from: start), 99),  // inside window — replaced
            point(day(4, from: start), 99)   // inside window — replaced
        ])
        let windowStart = day(3, from: start)
        let delta = HealthTrendSeries(points: [
            point(day(3, from: start), 10),
            point(day(4, from: start), 11),
            point(day(5, from: start), 12)
        ])

        let result = WatchDeltaSplicer.splice(
            seedSeries: seed, delta: .success(delta), from: windowStart, calendar: calendar
        )

        XCTAssertEqual(result, HealthTrendSeries(points: [
            point(day(0, from: start), 1),
            point(day(3, from: start), 10),
            point(day(4, from: start), 11),
            point(day(5, from: start), 12)
        ]))
    }

    func testSpliceIgnoresDeltaPointsOutsideTheWindow() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = HealthTrendSeries(points: [point(day(0, from: start), 1)])
        let windowStart = day(3, from: start)
        // A stray delta point BEFORE the window must never leak in, even
        // though the fetch itself succeeded.
        let delta = HealthTrendSeries(points: [
            point(day(1, from: start), 999),
            point(day(3, from: start), 10)
        ])

        let result = WatchDeltaSplicer.splice(
            seedSeries: seed, delta: .success(delta), from: windowStart, calendar: calendar
        )

        XCTAssertEqual(result, HealthTrendSeries(points: [
            point(day(0, from: start), 1),
            point(day(3, from: start), 10)
        ]))
    }

    // MARK: - spliceSleepHistory

    private func night(_ date: Date, duration: TimeInterval) -> SleepDaySummary {
        SleepDaySummary(date: date, summary: SleepSummary(duration: duration))
    }

    func testSpliceSleepHistoryOnFailureKeepsSeedUnchanged() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = SleepHistorySnapshot(days: [night(day(0, from: start), duration: 7 * 3_600)])

        let result = WatchDeltaSplicer.spliceSleepHistory(
            seed: seed, deltaNights: .failure, from: day(0, from: start), calendar: calendar
        )

        XCTAssertEqual(result, seed)
    }

    func testSpliceSleepHistoryOnSuccessEmptyClearsOnlyTheWindow() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = SleepHistorySnapshot(days: [
            night(day(0, from: start), duration: 7 * 3_600),  // before window
            night(day(3, from: start), duration: 8 * 3_600)   // inside window
        ])

        let result = WatchDeltaSplicer.spliceSleepHistory(
            seed: seed, deltaNights: .success([]), from: day(3, from: start), calendar: calendar
        )

        XCTAssertEqual(result, SleepHistorySnapshot(days: [night(day(0, from: start), duration: 7 * 3_600)]))
    }

    func testSpliceSleepHistoryReplacesOverlappingNightsKeyedByWakeDayAndIgnoresOutOfWindow() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let seed = SleepHistorySnapshot(days: [
            night(day(0, from: start), duration: 7 * 3_600),    // before window — kept
            night(day(3, from: start), duration: 1 * 3_600)     // inside window — replaced
        ])
        let windowStart = day(3, from: start)
        let deltaNights = [
            night(day(1, from: start), duration: 999 * 3_600), // out of window — ignored
            night(day(3, from: start), duration: 8 * 3_600),
            night(day(4, from: start), duration: 6 * 3_600)
        ]

        let result = WatchDeltaSplicer.spliceSleepHistory(
            seed: seed, deltaNights: .success(deltaNights), from: windowStart, calendar: calendar
        )

        XCTAssertEqual(result, SleepHistorySnapshot(days: [
            night(day(0, from: start), duration: 7 * 3_600),
            night(day(3, from: start), duration: 8 * 3_600),
            night(day(4, from: start), duration: 6 * 3_600)
        ]))
    }
}
