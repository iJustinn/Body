//
//  WatchSleepDebtChartViewTests.swift
//  BodyWatchTests
//
//  Locks the Sleep detail page's Sleep Debt band colors to the iPhone chart's
//  edges (`BodySleepDebtChart.bandColor`): the low color under 2 hours, pink
//  from 2 through 4 hours inclusive, and red past 4.
//

import SwiftUI
import XCTest
@testable import BodyWatch

final class WatchSleepDebtChartViewTests: XCTestCase {
    private let lowColor = Color.green

    private func bandColor(_ debt: TimeInterval) -> Color {
        WatchSleepDebtChartView.bandColor(for: debt, lowColor: lowColor)
    }

    func testJustUnderTwoHoursIsLow() {
        XCTAssertEqual(bandColor(SleepDebtChartModel.lowDebtUpperBound - 1), lowColor)
    }

    func testExactlyTwoHoursIsModerate() {
        XCTAssertEqual(bandColor(SleepDebtChartModel.lowDebtUpperBound), WatchSleepDebtChartView.moderateColor)
    }

    func testExactlyFourHoursIsModerate() {
        XCTAssertEqual(bandColor(SleepDebtChartModel.moderateDebtUpperBound), WatchSleepDebtChartView.moderateColor)
    }

    func testJustOverFourHoursIsHigh() {
        XCTAssertEqual(bandColor(SleepDebtChartModel.moderateDebtUpperBound + 1), .red)
    }
}
