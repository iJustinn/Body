//
//  WorkoutChartMonthSwipeTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
@testable import Body

final class WorkoutChartMonthSwipeTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func date(year: Int, month: Int, day: Int = 15) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: - Direction

    func testSwipeLeftAdvancesAndSwipeRightGoesBack() {
        XCTAssertEqual(
            BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: -80, height: 4)),
            .next
        )
        XCTAssertEqual(
            BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: 80, height: -4)),
            .previous
        )
    }

    func testShortHorizontalDragIsNotASwipe() {
        XCTAssertNil(BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: -40, height: 0)))
        XCTAssertNil(BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: 39, height: 0)))
        XCTAssertNotNil(BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: -41, height: 0)))
    }

    /// A drag that is far enough sideways but also travels downward must not
    /// switch months: the chart lives inside the scroll view whose pull-to-refresh
    /// fires at ~70 pt down, and one drag doing both is the failure mode.
    func testDiagonalDragIsRejected() {
        XCTAssertNil(BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: -100, height: 80)))
        XCTAssertNil(BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: 100, height: -50)))
        // Exactly on the 2:1 boundary is still rejected; comfortably past it passes.
        XCTAssertNil(BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: 100, height: 50)))
        XCTAssertEqual(
            BodyWorkoutChartSwipe.direction(forTranslation: CGSize(width: 100, height: 49)),
            .previous
        )
    }

    // MARK: - Adjacent month

    func testDecemberToJanuaryCrossesTheYear() throws {
        let now = try date(year: 2026, month: 3)

        XCTAssertEqual(
            BodyWorkoutChartSwipe.adjacentMonthYear(
                from: BodyMonthYear(month: 12, year: 2025),
                direction: .next,
                relativeTo: now,
                calendar: calendar
            ),
            BodyMonthYear(month: 1, year: 2026)
        )
    }

    func testJanuaryToDecemberCrossesTheYearBackwards() throws {
        let now = try date(year: 2026, month: 3)

        XCTAssertEqual(
            BodyWorkoutChartSwipe.adjacentMonthYear(
                from: BodyMonthYear(month: 1, year: 2026),
                direction: .previous,
                relativeTo: now,
                calendar: calendar
            ),
            BodyMonthYear(month: 12, year: 2025)
        )
    }

    func testSwipingPastTheCurrentMonthIsANoOp() throws {
        let now = try date(year: 2026, month: 8)

        XCTAssertNil(
            BodyWorkoutChartSwipe.adjacentMonthYear(
                from: BodyMonthYear(month: 8, year: 2026),
                direction: .next,
                relativeTo: now,
                calendar: calendar
            )
        )
        // The step just below the ceiling still resolves.
        XCTAssertEqual(
            BodyWorkoutChartSwipe.adjacentMonthYear(
                from: BodyMonthYear(month: 7, year: 2026),
                direction: .next,
                relativeTo: now,
                calendar: calendar
            ),
            BodyMonthYear(month: 8, year: 2026)
        )
    }

    /// The oldest reachable month is the first entry of the picker's own list —
    /// 36 months back, inclusive of the current one — so the floor is September
    /// 2023 when today is August 2026.
    func testSwipingBeforeTheOldestListedMonthIsANoOp() throws {
        let now = try date(year: 2026, month: 8)
        let oldest = try XCTUnwrap(
            BodyMonthYearPicker.monthYearList(monthsToShow: 36, relativeTo: now, calendar: calendar).first
        )
        XCTAssertEqual(oldest, BodyMonthYear(month: 9, year: 2023))

        XCTAssertNil(
            BodyWorkoutChartSwipe.adjacentMonthYear(
                from: oldest,
                direction: .previous,
                relativeTo: now,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            BodyWorkoutChartSwipe.adjacentMonthYear(
                from: BodyMonthYear(month: 10, year: 2023),
                direction: .previous,
                relativeTo: now,
                calendar: calendar
            ),
            oldest
        )
    }

    /// A month the picker can't represent at all (already outside its window, or
    /// in the future) has no adjacent month either — the swipe does nothing
    /// rather than teleporting the selection into the list.
    func testMonthOutsideTheListHasNoNeighbor() throws {
        let now = try date(year: 2026, month: 8)

        for direction in [BodyWorkoutChartSwipe.Direction.next, .previous] {
            XCTAssertNil(
                BodyWorkoutChartSwipe.adjacentMonthYear(
                    from: BodyMonthYear(month: 8, year: 2023),
                    direction: direction,
                    relativeTo: now,
                    calendar: calendar
                )
            )
            XCTAssertNil(
                BodyWorkoutChartSwipe.adjacentMonthYear(
                    from: BodyMonthYear(month: 9, year: 2026),
                    direction: direction,
                    relativeTo: now,
                    calendar: calendar
                )
            )
        }
    }

    func testEveryStepStaysInsideThePickerList() throws {
        let now = try date(year: 2026, month: 8)
        let reachable = BodyMonthYearPicker.monthYearList(monthsToShow: 36, relativeTo: now, calendar: calendar)

        for (index, monthYear) in reachable.enumerated() {
            let next = BodyWorkoutChartSwipe.adjacentMonthYear(
                from: monthYear,
                direction: .next,
                relativeTo: now,
                calendar: calendar
            )
            let previous = BodyWorkoutChartSwipe.adjacentMonthYear(
                from: monthYear,
                direction: .previous,
                relativeTo: now,
                calendar: calendar
            )

            XCTAssertEqual(next, index == reachable.count - 1 ? nil : reachable[index + 1])
            XCTAssertEqual(previous, index == 0 ? nil : reachable[index - 1])
        }
    }

    // MARK: - Short month names

    // The month picker's optional short form must be the abbreviated month plus
    // the year, uppercased. The formatter cache always uses `Locale.current`, so
    // the exact English string is only asserted when the tests run in English.
    func testShortDisplayNameIsUppercasedAbbreviatedMonth() {
        let september2026 = BodyMonthYear(month: 9, year: 2026)
        let short = september2026.shortDisplayName

        XCTAssertEqual(short, short.uppercased())
        XCTAssertFalse(short.contains("September"))
        XCTAssertTrue(short.contains("2026"))
        if Locale.current.language.languageCode?.identifier == "en" {
            XCTAssertEqual(short, "SEP 2026")
        }
    }
}
