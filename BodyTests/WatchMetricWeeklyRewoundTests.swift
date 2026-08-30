//
//  WatchMetricWeeklyRewoundTests.swift
//  BodyTests
//
//  `WatchMetric.weeklyRewound` keeps the Exercise Minutes complication's
//  rightmost bar on today: a snapshot cached across midnight must shift its
//  elapsed days out and append empty slots instead of holding yesterday's
//  window (the cache is only rewritten when the phone pushes).
//

import XCTest

@testable import Body

final class WatchMetricWeeklyRewoundTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func metric(weekly: [Double?]?) -> WatchMetric {
        WatchMetric(
            kind: WatchMetricKindKey.exerciseMinutes,
            title: "Exercise Minutes",
            displayValue: "38",
            unit: "",
            score: nil,
            fillFraction: 0,
            weekly: weekly
        )
    }

    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    func testFreshSnapshotPassesThroughUnchanged() {
        let weekly: [Double?] = [12, 30, nil, 45, 22, 0, 38]
        let rewound = metric(weekly: weekly).weeklyRewound(from: date(28), to: date(28, hour: 23), calendar: calendar)
        XCTAssertEqual(rewound, weekly)
    }

    func testSnapshotFromYesterdayShiftsOneDayOutAndAppendsAnEmptySlot() {
        let rewound = metric(weekly: [12, 30, nil, 45, 22, 0, 38]).weeklyRewound(from: date(27, hour: 23), to: date(28, hour: 0), calendar: calendar)
        XCTAssertEqual(rewound, [30, nil, 45, 22, 0, 38, nil])
    }

    func testWeekOldSnapshotYieldsSevenEmptySlots() {
        let rewound = metric(weekly: [12, 30, nil, 45, 22, 0, 38]).weeklyRewound(from: date(1), to: date(28), calendar: calendar)
        XCTAssertEqual(rewound, Array(repeating: nil, count: 7))
    }

    func testShortOrMissingWeeklyNormalizesToSevenSlots() {
        XCTAssertEqual(metric(weekly: [5, 7]).weeklyRewound(from: date(28), to: date(28), calendar: calendar), [nil, nil, nil, nil, nil, 5, 7])
        XCTAssertEqual(metric(weekly: nil).weeklyRewound(from: date(28), to: date(28), calendar: calendar), Array(repeating: nil, count: 7))
    }

    func testClockRolledBackwardDoesNotShift() {
        let weekly: [Double?] = [12, 30, nil, 45, 22, 0, 38]
        let rewound = metric(weekly: weekly).weeklyRewound(from: date(28), to: date(27), calendar: calendar)
        XCTAssertEqual(rewound, weekly)
    }
}
