//
//  StressLatestScoreTests.swift
//  BodyTests
//
//  Covers the Stress page's big number (`BodyStressBandPresentation.latestScore`):
//  today's latest scored window, rounded, whatever its age.
//

import XCTest
@testable import Body

final class StressLatestScoreTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private var today: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!)
    }

    private func window(_ minutes: Double, _ state: StressWindow.State) -> StressWindow {
        StressWindow(interval: DateInterval(start: today.addingTimeInterval(minutes * 60), duration: 15 * 60), state: state)
    }

    /// Trailing movement and unscored windows are skipped.
    func testTheLatestScoreIsTheLastScoredWindow() {
        XCTAssertEqual(BodyStressBandPresentation.latestScore(in: [
            window(0, .scored(score: 20, hrOnly: false)),
            window(15, .scored(score: 63.6, hrOnly: true)),
            window(30, .activity),
            window(45, .unscored)
        ]), 64)
    }

    func testNoScoredWindowMeansNoScore() {
        XCTAssertNil(BodyStressBandPresentation.latestScore(in: [window(0, .activity), window(15, .unscored)]))
        XCTAssertNil(BodyStressBandPresentation.latestScore(in: []))
    }
}
