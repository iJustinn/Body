//
//  WatchRecentHoursChartViewTests.swift
//  BodyWatchTests
//
//  Locks the intraday chart complications' drawing
//  (`WatchRecentHoursChartView`): the Heart Rate and HRV plot spans the
//  pages' 8 hour window and the Stress plot its 12, a chart read earlier
//  keeps only the slots still inside the window ending at the entry's date
//  (the current slot included), so a spike that has slid out no longer
//  stretches the value range, the caption takes the plot's place only when
//  nothing at all falls inside the window, and the range capsules keep a
//  usable width.
//

import SwiftUI
import XCTest
@testable import BodyWatch

final class WatchRecentHoursChartViewTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: hour, minute: minute))!
    }

    /// 15:07: the Heart Rate and HRV plot runs 07:00 to 15:30, the Stress
    /// plot 03:00 to 15:30.
    private var now: Date { date(15, 7) }

    private var heartDomain: ClosedRange<Date> {
        WatchRecentHoursChartView.domain(for: readings([]), endingAt: now, calendar: calendar)
    }

    private func bucket(_ hour: Int, _ minute: Int, min: Double = 60, max: Double = 70, average: Double = 65) -> WatchIntradayBucket {
        WatchIntradayBucket(start: date(hour, minute), minimum: min, maximum: max, average: average)
    }

    private func readings(_ buckets: [WatchIntradayBucket]) -> WatchRecentHoursChartView.Content {
        .readings(buckets, tint: .red)
    }

    private func timeline(start: Date, slots: [Int?], context: [WatchStressContextBand] = []) -> WatchStressTimeline {
        WatchStressTimeline(
            start: start,
            end: start.addingTimeInterval(Double(slots.count) * WatchStressTimeline.slotLength),
            slots: slots,
            context: context,
            computedAt: nil
        )
    }

    // MARK: - Domain

    func testTheHeartPlotSpansEightHoursAndTheStressPlotTwelve() {
        let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
        XCTAssertEqual(heartDomain, window.start...window.plotEnd)
        XCTAssertEqual(heartDomain, date(7, 0)...date(15, 30))

        let stress = WatchRecentHoursChartView.domain(for: .stress(nil), endingAt: now, calendar: calendar)
        XCTAssertEqual(stress, WatchStressChartGeometry.domain(endingAt: now, calendar: calendar))
        XCTAssertEqual(stress, date(3, 0)...date(15, 30))
    }

    // MARK: - Visible slots

    func testVisibleBucketsDropSlotsOlderThanTheWindowAndKeepTheCurrentSlot() {
        let buckets = [bucket(6, 30), bucket(7, 0), bucket(12, 0), bucket(15, 0)]
        XCTAssertEqual(
            WatchRecentHoursChartView.visibleBuckets(buckets, in: heartDomain).map(\.start),
            [date(7, 0), date(12, 0), date(15, 0)]
        )
        // A slot starting on the plot's right edge would be drawn past it.
        XCTAssertTrue(WatchRecentHoursChartView.visibleBuckets([bucket(15, 30)], in: heartDomain).isEmpty)
    }

    func testAnOldSpikeOutsideTheWindowDoesNotStretchTheValueRange() {
        let spike = bucket(6, 0, min: 140, max: 180, average: 160)
        let rest = [bucket(9, 0, min: 58, max: 72, average: 64), bucket(14, 30, min: 60, max: 70, average: 66)]

        let values = WatchRecentHoursChartView.valueDomain(for: [spike] + rest, in: heartDomain)
        XCTAssertEqual(values, WatchIntradayChartGeometry.rangeDomain(for: rest))
        XCTAssertLessThan(values.upperBound, 140)
    }

    // MARK: - Empty plot

    func testNothingInTheWindowShowsTheCaption() {
        XCTAssertFalse(WatchRecentHoursChartView.hasPlot(readings([]), endingAt: now, calendar: calendar))
        XCTAssertFalse(WatchRecentHoursChartView.hasPlot(readings([bucket(6, 30)]), endingAt: now, calendar: calendar))
        XCTAssertTrue(WatchRecentHoursChartView.hasPlot(readings([bucket(15, 0)]), endingAt: now, calendar: calendar))

        XCTAssertFalse(WatchRecentHoursChartView.hasPlot(.stress(nil), endingAt: now, calendar: calendar))
        // Scored, but before the window opened.
        let old = timeline(start: date(1, 0), slots: [30, 40, 50, 60])
        XCTAssertFalse(WatchRecentHoursChartView.hasPlot(.stress(old), endingAt: now, calendar: calendar))
        // Unscored windows under sleep shading: no mark to draw either.
        let gaps = timeline(
            start: date(14, 0),
            slots: [nil, nil, nil, nil],
            context: [WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: date(13, 0), end: date(15, 0))]
        )
        XCTAssertFalse(WatchRecentHoursChartView.hasPlot(.stress(gaps), endingAt: now, calendar: calendar))
    }

    /// A stretch masked as movement has no score, but its floor stubs still
    /// chart, as on the Stress page.
    func testActivityOnlyStressStillDrawsThePlot() {
        let a = WatchStressTimeline.activityMarker
        let moving = timeline(start: date(14, 0), slots: [a, a, nil, a])
        XCTAssertNil(moving.latestScoredWindow)
        XCTAssertTrue(WatchRecentHoursChartView.hasPlot(.stress(moving), endingAt: now, calendar: calendar))
    }

    // MARK: - Capsules

    func testCapsuleWidthClamps() {
        // 55% of one of the 17 slots' share of the plot.
        XCTAssertEqual(WatchRecentHoursChartView.capsuleWidth(forPlotWidth: 170), 5.5, accuracy: 0.0001)
        XCTAssertEqual(WatchRecentHoursChartView.capsuleWidth(forPlotWidth: 20), 1.5)
        XCTAssertEqual(WatchRecentHoursChartView.capsuleWidth(forPlotWidth: 400), 6)
    }
}
