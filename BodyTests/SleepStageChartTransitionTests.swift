//
//  SleepStageChartTransitionTests.swift
//  BodyTests
//
//  Covers the stage chart's date-switch choreography geometry: while the chart
//  is flattened every segment sits on the Core row (where it dissolves into the
//  flat band), and the band spans the night's full extent.
//

import XCTest
@testable import Body

final class SleepStageChartTransitionTests: XCTestCase {
    private func date(hour: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: hour * 3600)
    }

    private func segment(stage: SleepStage, startHour: Double, endHour: Double) -> SleepStageSegment {
        SleepStageSegment(stage: stage, startDate: date(hour: startHour), endDate: date(hour: endHour))
    }

    func testFlattenedSegmentsAllSitOnTheCoreRow() {
        for stage in SleepStage.allCases {
            XCTAssertEqual(
                BodySleepStageChart.segmentYRange(for: stage, isFlattened: true),
                BodySleepStageChart.flattenedYRange
            )
        }
        XCTAssertEqual(
            BodySleepStageChart.flattenedYRange,
            (SleepStage.core.chartPosition - 0.32)...(SleepStage.core.chartPosition + 0.32)
        )
    }

    func testSteadySegmentsKeepTheirOwnStageRows() {
        for stage in SleepStage.allCases {
            XCTAssertEqual(
                BodySleepStageChart.segmentYRange(for: stage, isFlattened: false),
                (stage.chartPosition - 0.32)...(stage.chartPosition + 0.32)
            )
        }
    }

    func testNightSpanCoversFirstStartThroughLastEnd() {
        let snapshot = SleepStageSnapshot(
            date: date(hour: 0),
            segments: [
                segment(stage: .core, startHour: 23, endHour: 25),
                segment(stage: .deep, startHour: 25, endHour: 26),
                segment(stage: .rem, startHour: 26, endHour: 30.5)
            ]
        )

        XCTAssertEqual(
            BodySleepStageChart.nightSpan(of: snapshot),
            date(hour: 23)...date(hour: 30.5)
        )
    }

    func testNightSpanIsNilWithoutSegments() {
        XCTAssertNil(BodySleepStageChart.nightSpan(of: SleepStageSnapshot(date: nil, segments: [])))
    }

    // MARK: - Fractional plot space (no lateral movement on a date switch)

    func testNormalizedPlotDateMapsTheNightOntoTheFixedSpan() {
        let span = date(hour: 23)...date(hour: 30)

        XCTAssertEqual(
            BodySleepStageChart.normalizedPlotDate(for: span.lowerBound, nightSpan: span),
            BodySleepStageChart.plotReferenceStart
        )
        XCTAssertEqual(
            BodySleepStageChart.normalizedPlotDate(for: span.upperBound, nightSpan: span),
            BodySleepStageChart.plotReferenceStart.addingTimeInterval(BodySleepStageChart.plotSpan)
        )
        XCTAssertEqual(
            BodySleepStageChart.normalizedPlotDate(for: date(hour: 26.5), nightSpan: span),
            BodySleepStageChart.plotReferenceStart.addingTimeInterval(BodySleepStageChart.plotSpan / 2)
        )
    }

    func testNightsOfDifferentLengthsShareTheSamePlotEdges() {
        // The invariant behind "the bar never slides": whatever night is shown,
        // its start and end land on the same two x positions, so a date switch
        // only resizes what is between them.
        let shortNight = date(hour: 0)...date(hour: 5)
        let longNight = date(hour: 100)...date(hour: 109)

        XCTAssertEqual(
            BodySleepStageChart.normalizedPlotDate(for: shortNight.lowerBound, nightSpan: shortNight),
            BodySleepStageChart.normalizedPlotDate(for: longNight.lowerBound, nightSpan: longNight)
        )
        XCTAssertEqual(
            BodySleepStageChart.normalizedPlotDate(for: shortNight.upperBound, nightSpan: shortNight),
            BodySleepStageChart.normalizedPlotDate(for: longNight.upperBound, nightSpan: longNight)
        )
    }

    func testRealDateInvertsTheNormalizedPlotDate() {
        let span = date(hour: 22.25)...date(hour: 30.75)
        let sample = date(hour: 27.5)
        let normalized = BodySleepStageChart.normalizedPlotDate(for: sample, nightSpan: span)

        XCTAssertEqual(
            try XCTUnwrap(BodySleepStageChart.realDate(forNormalized: normalized, nightSpan: span))
                .timeIntervalSinceReferenceDate,
            sample.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
        XCTAssertNil(BodySleepStageChart.realDate(forNormalized: normalized, nightSpan: nil))
    }

    func testTransitionPhasesAddUpToTheNumericFlipDuration() {
        // Collapse + the frame that publishes the incoming night flattened +
        // expand must total the numeric flip the times run.
        XCTAssertEqual(
            BodySleepStageChart.phaseDuration * 2 + BodySleepStageChart.swapSettleDelay,
            BodySleepStageChart.transitionDuration,
            accuracy: 0.0001
        )
        XCTAssertEqual(BodySleepStageChart.transitionDuration, 0.4)
        XCTAssertGreaterThan(BodySleepStageChart.swapSettleDelay, 0)
    }
}
