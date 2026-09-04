//
//  BodyRadarChartTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class BodyRadarChartTests: XCTestCase {
    private func night(day: Int) -> BodyRadarNight {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = day
        let date = Calendar.bodyGregorian.date(from: components) ?? Date()
        return BodyRadarNight(date: date, state: .noSigns, evidence: 0.5)
    }

    private var points: [BodyRadarChartPoint] {
        (1...3).map { BodyRadarChartPoint(night: night(day: $0)) }
    }

    func testNearestPointPicksTheSlotTheScrubIsInside() {
        let points = points
        let slotStart = points[1].night.date

        for hour in [0.5, 12.0, 23.5] {
            let selected = slotStart.addingTimeInterval(hour * 60 * 60)
            XCTAssertEqual(
                BodyRadarChart.nearestPoint(to: selected, in: points)?.id,
                points[1].id,
                "A scrub \(hour)h into the second night's slot should select that night"
            )
        }
    }

    func testNearestPointSwitchesAtTheSlotBoundary() {
        let points = points
        let boundary = points[1].night.date

        XCTAssertEqual(
            BodyRadarChart.nearestPoint(to: boundary.addingTimeInterval(-60), in: points)?.id,
            points[0].id
        )
        XCTAssertEqual(
            BodyRadarChart.nearestPoint(to: boundary.addingTimeInterval(60), in: points)?.id,
            points[1].id
        )
    }

    func testNearestPointOnEmptyInputIsNil() {
        XCTAssertNil(BodyRadarChart.nearestPoint(to: Date(), in: []))
    }
}
