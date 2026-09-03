//
//  WatchSleepStagesChartSegmentsTests.swift
//  BodyWatchTests
//
//  Locks how the Sleep detail page's hypnogram reads the snapshot's raw
//  `sleepStages`: every known stage name maps to its `SleepStage`, an unknown
//  name (a newer phone) or an empty/inverted span is dropped rather than
//  drawn, and the chart orders what's left by start time.
//

import XCTest
@testable import BodyWatch

final class WatchSleepStagesChartSegmentsTests: XCTestCase {
    private let night = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func raw(_ stage: String, _ startMinute: Double, _ endMinute: Double) -> WatchSleepStageSegment {
        WatchSleepStageSegment(
            stage: stage,
            startDate: night.addingTimeInterval(startMinute * 60),
            endDate: night.addingTimeInterval(endMinute * 60)
        )
    }

    func testMapsEveryKnownStageName() {
        let segments = WatchSleepStagesChartView.segments(from: [
            raw("awake", 0, 5), raw("core", 5, 60), raw("deep", 60, 90), raw("rem", 90, 110)
        ])
        XCTAssertEqual(segments.map(\.stage), [.awake, .core, .deep, .rem])
        XCTAssertEqual(segments.first?.startDate, night)
        XCTAssertEqual(segments.last?.endDate, night.addingTimeInterval(110 * 60))
    }

    func testDropsUnknownStagesAndEmptySpans() {
        let segments = WatchSleepStagesChartView.segments(from: [
            raw("core", 0, 30),
            raw("lucid", 30, 40),
            raw("deep", 40, 40),
            raw("rem", 60, 50),
            raw("rem", 40, 70)
        ])
        XCTAssertEqual(segments.map(\.stage), [.core, .rem])
    }

    func testChartSortsSegmentsByStart() {
        let view = WatchSleepStagesChartView(segments: WatchSleepStagesChartView.segments(from: [
            raw("rem", 60, 80), raw("core", 0, 60)
        ]))
        XCTAssertEqual(view.segments.map(\.stage), [.core, .rem])
    }
}
