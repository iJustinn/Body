//
//  HealthWidgetPointRewindingWeekTests.swift
//  BodyTests
//
//  Covers `HealthWidgetPoint.rewindingWeek`, the entry-load re-alignment behind
//  the Exercise Minutes lock screen widget. The widget snapshot cache is only
//  rewritten when the app runs, so a cache written before midnight would keep
//  drawing yesterday's window (and yesterday's weekday letters) under a
//  "THIS WEEK" header until the next launch. Re-windowing at load keeps the
//  rightmost bar on today no matter how old the cache is.
//

import XCTest
@testable import Body

final class HealthWidgetPointRewindingWeekTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func day(_ offsetFromToday: Int, from today: Date) -> Date {
        calendar.date(byAdding: .day, value: offsetFromToday, to: calendar.startOfDay(for: today))!
    }

    /// Seven daily points ending on `lastDay`, values 1...7 oldest first.
    private func week(endingOn lastDay: Date) -> [HealthWidgetPoint] {
        (0..<7).map { offset in
            HealthWidgetPoint(
                date: calendar.date(byAdding: .day, value: offset - 6, to: lastDay)!,
                value: Double(offset + 1)
            )
        }
    }

    private let now = Date(timeIntervalSinceReferenceDate: 780_000_000)

    func testFreshWeekPassesThroughUnchanged() {
        let points = week(endingOn: day(0, from: now))

        let rewound = HealthWidgetPoint.rewindingWeek(points, to: now, calendar: calendar)

        XCTAssertEqual(rewound, points)
    }

    func testWeekEndingYesterdayShiftsSoTodayIsRightmostWithOneNilPad() {
        let points = week(endingOn: day(-1, from: now))

        let rewound = HealthWidgetPoint.rewindingWeek(points, to: now, calendar: calendar)

        XCTAssertEqual(rewound.count, 7)
        // The oldest day fell out of the window; the six survivors slid left.
        XCTAssertEqual(rewound.map(\.value), [2, 3, 4, 5, 6, 7, nil])
        XCTAssertEqual(rewound.last?.date, day(0, from: now))
        XCTAssertNil(rewound.last?.value, "Today has no reading yet, so its bar must be a stub.")
        XCTAssertEqual(rewound.first?.date, day(-6, from: now))
    }

    func testVeryStaleWeekYieldsSevenEmptyDays() {
        let points = week(endingOn: day(-30, from: now))

        let rewound = HealthWidgetPoint.rewindingWeek(points, to: now, calendar: calendar)

        XCTAssertEqual(rewound.count, 7)
        XCTAssertTrue(rewound.allSatisfy { $0.value == nil })
        // Dates still describe the current window, so the weekday letters stay
        // honest even when every bar is a stub.
        XCTAssertEqual(rewound.map(\.date), (0..<7).map { day($0 - 6, from: now) })
    }

    func testEmptyCacheStillYieldsSevenDatedDays() {
        let rewound = HealthWidgetPoint.rewindingWeek([], to: now, calendar: calendar)

        XCTAssertEqual(rewound.count, 7)
        XCTAssertEqual(rewound.map(\.date), (0..<7).map { day($0 - 6, from: now) })
        XCTAssertTrue(rewound.allSatisfy { $0.value == nil })
    }

    func testWindowIsAlignedToDayStartsRegardlessOfPointTimestamps() {
        // Cached points carry a mid-day timestamp; the re-windowed output must
        // key off calendar days, not the raw instants.
        let noon = calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: now))!
        let points = week(endingOn: noon)

        let rewound = HealthWidgetPoint.rewindingWeek(points, to: now, calendar: calendar)

        XCTAssertEqual(rewound.count, 7)
        XCTAssertEqual(rewound.map(\.value), [1, 2, 3, 4, 5, 6, 7])
    }
}
