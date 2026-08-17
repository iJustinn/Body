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

    // MARK: - Where the dot parks while it is hidden

    func testRestingValueParksOnTodaysPlottedPoint() {
        let today = calendar.startOfDay(for: now)

        XCTAssertEqual(
            BodyHealthMetricTrendChart.currentValueRestingValue(
                for: (date: today, value: 72),
                markEntries: [BodyHealthTrendMarkEntry(date: today, value: 80, isPlaceholder: false)]
            ),
            80
        )
    }

    func testRestingValueUsesOffRangeDotGeometry() {
        // Off the week range today often has no plotted value of its own; the
        // entry then carries another range's reading as invisible dot geometry,
        // and that is where the dot has to park.
        let today = calendar.startOfDay(for: now)
        var entry = BodyHealthTrendMarkEntry(date: today, value: nil, isPlaceholder: false)
        entry.offRangeValue = 80

        XCTAssertEqual(
            BodyHealthMetricTrendChart.currentValueRestingValue(
                for: (date: today, value: 72),
                markEntries: [entry]
            ),
            80
        )
    }

    func testRestingValueFallsBackToTheDotsOwnValue() {
        // No geometry for the date at all: the dot parks in place and simply
        // fades, which is what it did before it could morph.
        XCTAssertEqual(
            BodyHealthMetricTrendChart.currentValueRestingValue(
                for: (date: calendar.startOfDay(for: now), value: 72),
                markEntries: []
            ),
            72
        )
    }

    func testRestingValueIsNilWithoutADot() {
        XCTAssertNil(
            BodyHealthMetricTrendChart.currentValueRestingValue(for: nil, markEntries: [])
        )
    }

    /// The morph is only as good as the coupling between the dot's date and the
    /// chart's mark entries: if they ever stop lining up, the dot silently falls
    /// back to parking in place instead of climbing into a plotted point.
    func testDotFindsPlottedGeometryToClimbIntoInEveryRange() throws {
        let trendSeries = series(dayValues: [(-2, 68), (-1, 76), (0, 80)])
        let dot = try XCTUnwrap(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: readiness(score: 72, drainedFrom: 80),
            series: trendSeries,
            calendar: calendar,
            now: now
        ))

        var pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]] = [:]
        for range in BodyHealthTrendRange.allCases {
            pointsByRange[range] = trendSeries.lineChartCalendarPoints(to: range, calendar: calendar, date: now)
        }

        for range in BodyHealthTrendRange.allCases {
            let markEntries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
                selectedRange: range,
                pointsByRange: pointsByRange
            )
            let plottedEntry = try XCTUnwrap(
                markEntries.first { $0.date == dot.date },
                "\(range) plots no dot geometry on the current-readiness dot's own date"
            )

            XCTAssertEqual(
                BodyHealthMetricTrendChart.currentValueRestingValue(for: dot, markEntries: markEntries),
                plottedEntry.dotValue,
                "\(range) parks the current-readiness dot away from the point plotted at its date"
            )
        }
    }

    func testWeekChartParksTheDotOnTodaysPreDrainPoint() throws {
        // The week chart is the only range that shows the dot, so this is the
        // travel the user actually watches: up into today's frozen morning
        // point, the one the drained dot hangs under.
        let trendSeries = series(dayValues: [(-2, 68), (-1, 76), (0, 80)])
        let dot = try XCTUnwrap(BodyReadinessStatusPresentation.currentTrendDot(
            readiness: readiness(score: 72, drainedFrom: 80),
            series: trendSeries,
            calendar: calendar,
            now: now
        ))
        let markEntries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: .recentWeek,
            pointsByRange: [
                .recentWeek: trendSeries.lineChartCalendarPoints(to: .recentWeek, calendar: calendar, date: now)
            ]
        )

        let restingValue = try XCTUnwrap(
            BodyHealthMetricTrendChart.currentValueRestingValue(for: dot, markEntries: markEntries)
        )
        XCTAssertEqual(restingValue, 80)
        XCTAssertGreaterThan(restingValue, dot.value, "the dot must climb up into the morning point, never down")
    }
}
