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

    // MARK: - Collapsing dots on flat runs (readiness day view)

    private func entry(hour: Double, value: Double, segmentIndex: Int = 0) -> BodyHealthMetricDayChartEntry {
        BodyHealthMetricDayChartEntry(
            sourceName: "Primary",
            sourceRole: .primary,
            bucket: HealthTrendHourlyBucket(
                hourStart: date(hour: hour),
                averageValue: value,
                samples: []
            ),
            segmentIndex: segmentIndex
        )
    }

    func testCollapsingFlatRunKeepsOnlyStartAndEndDots() {
        let flat = (0..<6).map { entry(hour: Double($0), value: 80) }
        let kept = BodyHealthMetricDayChart.collapsingUnchangedRunPoints(flat)

        XCTAssertEqual(kept.map(\.plotDate), [flat.first?.plotDate, flat.last?.plotDate].compactMap { $0 })
    }

    func testCollapsingKeepsEveryDotAroundAValueChange() {
        // 80,80,80,70,70,70 -> keep the run edges: hours 0, 2, 3, 5.
        let values: [Double] = [80, 80, 80, 70, 70, 70]
        let entries = values.enumerated().map { entry(hour: Double($0.offset), value: $0.element) }
        let kept = BodyHealthMetricDayChart.collapsingUnchangedRunPoints(entries)

        XCTAssertEqual(kept.map(\.plotDate), [0, 2, 3, 5].map { entries[$0].plotDate })
    }

    func testCollapsingTreatsSegmentsIndependently() {
        // Same flat value across a gap-split series: each segment keeps its own
        // start and end dot rather than collapsing across the gap.
        let entries = [
            entry(hour: 0, value: 80, segmentIndex: 0),
            entry(hour: 1, value: 80, segmentIndex: 0),
            entry(hour: 2, value: 80, segmentIndex: 0),
            entry(hour: 9, value: 80, segmentIndex: 1),
            entry(hour: 10, value: 80, segmentIndex: 1),
            entry(hour: 11, value: 80, segmentIndex: 1)
        ]
        let kept = BodyHealthMetricDayChart.collapsingUnchangedRunPoints(entries)

        XCTAssertEqual(kept.map(\.plotDate), [0, 2, 3, 5].map { entries[$0].plotDate })
    }
}
