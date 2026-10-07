//
//  WatchWeekBarsViewTests.swift
//  BodyWatchTests
//
//  Locks the shared daily-total bar chart (`WatchWeekBarsView`, drawn on the
//  Steps, Active Energy and Resting Energy pages and their complications): the
//  bar scaling against the week's best day, the one letter weekday labels, and
//  which pages draw bars instead of the line sparkline.
//

import SwiftUI
import XCTest
@testable import BodyWatch

final class WatchWeekBarsViewTests: XCTestCase {
    func testBarsScaleAgainstTheWeekMaxWithAThreePointFloor() {
        XCTAssertEqual(WatchWeekBarsView.barHeight(for: 11_020, weekMax: 11_020, in: 60), 60)
        XCTAssertEqual(WatchWeekBarsView.barHeight(for: 5_510, weekMax: 11_020, in: 60), 30)
        // A sliver of a day still shows as a bar, never a hairline.
        XCTAssertEqual(WatchWeekBarsView.barHeight(for: 1, weekMax: 11_020, in: 60), 3)
        // A week with no best day draws the floor for whatever value asked.
        XCTAssertEqual(WatchWeekBarsView.barHeight(for: 10, weekMax: 0, in: 60), 3)
    }

    func testWeekdayLettersAreOneCharacterPerDay() throws {
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        for offset in 0..<7 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: day))
            XCTAssertEqual(WatchWeekBarsView.weekdayLetter(for: date).count, 1)
        }
    }

    func testOnlyTheDailyTotalPagesDrawBars() {
        for kind in WatchMetricKindKey.dailyTotalKinds {
            XCTAssertTrue(WatchMetricDetailView.drawsWeekBars(forKind: kind), kind)
        }
        for kind in WatchMetricKindKey.displayOrder where !WatchMetricKindKey.dailyTotalKinds.contains(kind) {
            XCTAssertFalse(WatchMetricDetailView.drawsWeekBars(forKind: kind), kind)
        }
        XCTAssertFalse(WatchMetricDetailView.drawsWeekBars(forKind: WatchMetricKindKey.workoutMinutes))
    }

    func testDailyTotalsSitDirectlyUnderRestingHRInTheDisplayOrder() {
        let order = WatchMetricKindKey.displayOrder
        XCTAssertEqual(order.firstIndex(of: WatchMetricKindKey.steps), 7)
        XCTAssertEqual(
            Array(order[7...9]),
            [WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy, WatchMetricKindKey.restingEnergy]
        )
        XCTAssertEqual(order[6], WatchMetricKindKey.restingHeartRate)
        XCTAssertEqual(order.last, WatchMetricKindKey.wristTemperature)
    }
}
