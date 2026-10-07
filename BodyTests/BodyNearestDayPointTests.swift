//
//  BodyNearestDayPointTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// A scrub on a chart whose marks plot with `unit: .day` must select the bar under
/// the finger. Comparing against each day's midnight handed the right half of every
/// bar to the next day (feedback: "it shows the detail of the next column").
final class BodyNearestDayPointTests: XCTestCase {
    private var days: [Date] {
        (1...3).map { day in
            var components = DateComponents()
            components.year = 2026
            components.month = 9
            components.day = day
            return Calendar.bodyGregorian.date(from: components) ?? Date()
        }
    }

    func testScrubAnywhereInsideADaySelectsThatDay() {
        let days = days

        for hour in [0.5, 12.0, 18.0, 23.5] {
            let selected = days[1].addingTimeInterval(hour * 60 * 60)
            XCTAssertEqual(
                bodyNearestDayPoint(to: selected, in: days) { $0 },
                days[1],
                "A scrub \(hour)h into the second day should select that day"
            )
        }
    }

    func testSelectionSwitchesAtTheDayBoundary() {
        let days = days
        let boundary = days[1]

        XCTAssertEqual(bodyNearestDayPoint(to: boundary.addingTimeInterval(-60), in: days) { $0 }, days[0])
        XCTAssertEqual(bodyNearestDayPoint(to: boundary.addingTimeInterval(60), in: days) { $0 }, days[1])
    }

    func testEmptyInputIsNil() {
        XCTAssertNil(bodyNearestDayPoint(to: Date(), in: [Date]()) { $0 })
    }
}
