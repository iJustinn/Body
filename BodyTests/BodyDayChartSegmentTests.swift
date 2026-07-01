//
//  BodyDayChartSegmentTests.swift
//  BodyTests
//
//  Covers the all-day metric chart's line-segmenting rule: consecutive dots
//  that are 4 hours or more apart must start a new segment (so the line does
//  not connect across long data gaps), while closer dots stay connected.
//

import XCTest
@testable import Body

final class BodyDayChartSegmentTests: XCTestCase {
    private func date(hour: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: hour * 3600)
    }

    func testSegmentIndicesBreakAtFourHourGaps() {
        // Gaps from previous dot: –, 1h, 1h, 4h, 1h, 5h -> three segments.
        let dates = [
            date(hour: 0), date(hour: 1), date(hour: 2),
            date(hour: 6), date(hour: 7), date(hour: 12)
        ]

        XCTAssertEqual(
            BodyHealthMetricDayChart.segmentIndices(forSortedPlotDates: dates, gapThreshold: 4 * 3600),
            [0, 0, 0, 1, 1, 2]
        )
    }

    func testSegmentIndicesKeepGapsUnderThresholdConnected() {
        // Just under 4h stays in one segment; exactly 4h breaks.
        XCTAssertEqual(
            BodyHealthMetricDayChart.segmentIndices(
                forSortedPlotDates: [date(hour: 0), date(hour: 3.9)],
                gapThreshold: 4 * 3600
            ),
            [0, 0]
        )
        XCTAssertEqual(
            BodyHealthMetricDayChart.segmentIndices(
                forSortedPlotDates: [date(hour: 0), date(hour: 4)],
                gapThreshold: 4 * 3600
            ),
            [0, 1]
        )
    }

    func testSegmentIndicesHandleEmptyAndSingle() {
        XCTAssertEqual(BodyHealthMetricDayChart.segmentIndices(forSortedPlotDates: []), [])
        XCTAssertEqual(BodyHealthMetricDayChart.segmentIndices(forSortedPlotDates: [date(hour: 9)]), [0])
    }
}
