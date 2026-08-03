//
//  WatchSparklineCurrentDotTests.swift
//  BodyWatchTests
//
//  Covers the sparkline's faded "current" dot gate
//  (`WatchSparklineView.currentDotValue`): the dot needs a finite today (last)
//  slot and a finite current value strictly below it — it only marks a same-day
//  decrease.
//

import XCTest
@testable import BodyWatch

final class WatchSparklineCurrentDotTests: XCTestCase {
    func testNilCurrentValueReturnsNil() {
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, 80], currentValue: nil))
    }

    func testMissingTodaySlotReturnsNil() {
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, nil], currentValue: 72))
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [], currentValue: 72))
    }

    func testCurrentValueNotBelowTodayReturnsNil() {
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, 80], currentValue: 80))
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, 80], currentValue: 85))
    }

    func testCurrentValueBelowTodayReturnsIt() {
        XCTAssertEqual(WatchSparklineView.currentDotValue(values: [70, 75, 80], currentValue: 72), 72)
    }

    func testNonFiniteInputsReturnNil() {
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, 80], currentValue: .nan))
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, .nan], currentValue: 72))
        XCTAssertNil(WatchSparklineView.currentDotValue(values: [70, 75, 80], currentValue: -.infinity))
    }
}
