//
//  ReadinessCurrentTrendDotTests.swift
//  BodyTests
//
//  Covers the week chart's "current readiness" dot gate
//  (`BodyReadinessStatusPresentation.currentTrendDot`): the dot exists only for
//  today, only when today's workouts actually drained the live score, and only
//  when the drained score sits visibly below today's plotted (pre-drain) point.
//

import XCTest
@testable import Body

final class ReadinessCurrentTrendDotTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!
    }

    private func series(dayValues: [(dayOffset: Int, value: Double)]) -> HealthTrendSeries {
        let today = calendar.startOfDay(for: now)
        return HealthTrendSeries(points: dayValues.map { entry in
            let day = calendar.date(byAdding: .day, value: entry.dayOffset, to: today)!
            return HealthTrendDataPoint(
                date: calendar.date(byAdding: .hour, value: 8, to: day)!,
                value: entry.value
            )
        })
    }

    private func readiness(score: Int?, drainedFrom morningScore: Int? = nil) -> ReadinessSummary {
        ReadinessSummary(
            score: score,
            status: ReadinessStatus.status(for: score),
            confidence: .high,
            components: [],
            drivers: [],
            activityDrainMorningScore: morningScore
        )
    }

    func testNoDrainMarkerReturnsNil() {
        XCTAssertNil(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: readiness(score: 72),
            series: series(dayValues: [(-1, 76), (0, 80)]),
            calendar: calendar,
            now: now
        ))
    }

    func testNilReadinessReturnsNil() {
        XCTAssertNil(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: nil,
            series: series(dayValues: [(0, 80)]),
            calendar: calendar,
            now: now
        ))
    }

    func testDropClampedToZeroReturnsNil() {
        // Display softening can absorb the whole drain: the live score still
        // equals today's plotted value, so there is nothing to dot.
        XCTAssertNil(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: readiness(score: 80, drainedFrom: 80),
            series: series(dayValues: [(-1, 76), (0, 80)]),
            calendar: calendar,
            now: now
        ))
    }

    func testDrainedScoreBelowTodayPointReturnsDot() throws {
        let dot = try XCTUnwrap(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: readiness(score: 72, drainedFrom: 80),
            series: series(dayValues: [(-2, 68), (-1, 76), (0, 80)]),
            calendar: calendar,
            now: now
        ))

        XCTAssertEqual(dot.value, 72)
        XCTAssertTrue(calendar.isDate(dot.date, inSameDayAs: now))

        // The dot hangs off the exact point the chart plots for today, so the
        // x positions coincide.
        let todayPoint = series(dayValues: [(-2, 68), (-1, 76), (0, 80)])
            .lineChartCalendarPoints(to: .recentWeek, calendar: calendar, date: now)
            .last { $0.value?.isFinite == true }
        XCTAssertEqual(dot.date, todayPoint?.date)
    }

    func testSeriesWithoutTodayPointReturnsNil() {
        XCTAssertNil(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: readiness(score: 72, drainedFrom: 80),
            series: series(dayValues: [(-2, 68), (-1, 76)]),
            calendar: calendar,
            now: now
        ))
    }
}
