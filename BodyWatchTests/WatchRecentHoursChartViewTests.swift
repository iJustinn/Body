//
//  WatchRecentHoursChartViewTests.swift
//  BodyWatchTests
//
//  Locks the intraday chart complications' drawing
//  (`WatchRecentHoursChartView`): the Heart Rate and HRV plot spans the
//  pages' 8 hour window and the Stress plot its 12, a chart read earlier
//  keeps only the slots still inside the window ending at the entry's date
//  (the current slot included), so a spike that has slid out no longer
//  stretches the value range, which runs exactly from the lowest to the
//  highest reading (unpadded, unlike the pages'), the caption takes the
//  plot's place only when nothing at all falls inside the window, the range
//  capsules keep a usable width, the Stress axis labels 0, 50 and 100, the
//  icon row is reserved only while a sleep, nap or workout band is in the
//  Stress window, and the plot leaves room for the axis, the hour row and the
//  icon row.
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
        XCTAssertEqual(values, 58...72)
        XCTAssertLessThan(values.upperBound, 140)
    }

    /// Unlike the pages' padded range, the complication's runs exactly from
    /// the lowest to the highest reading, so the chart spans the plot; one
    /// repeated value keeps the pages' range so its line sits mid plot.
    func testTheValueRangeSpansExactlyTheReadings() {
        let readings = [bucket(9, 0, min: 52, max: 61, average: 56), bucket(12, 0, min: 60, max: 131, average: 104)]
        XCTAssertEqual(WatchRecentHoursChartView.valueDomain(for: readings, in: heartDomain), 52...131)

        let flat = [bucket(9, 0, min: 62, max: 62, average: 62)]
        XCTAssertEqual(WatchRecentHoursChartView.valueDomain(for: flat, in: heartDomain), WatchIntradayChartGeometry.rangeDomain(for: flat))
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

    // MARK: - Layout

    func testStressAxisLabelsEveryOtherGridline() {
        XCTAssertEqual(WatchRecentHoursChartView.stressAxisScores, [0, 50, 100])
    }

    /// The Stress plot reserves the icon row only while a band it draws a
    /// symbol for overlaps its window (03:00 to 15:30 here).
    func testIconRowOnlyWhileASleepOrWorkoutBandIsInTheStressWindow() {
        let stressDomain = WatchRecentHoursChartView.domain(for: .stress(nil), endingAt: now, calendar: calendar)
        func iconRow(_ bands: [WatchStressContextBand]) -> Bool {
            WatchRecentHoursChartView.hasIconRow(
                .stress(timeline(start: date(14, 0), slots: [30, 32], context: bands)),
                domain: stressDomain
            )
        }

        XCTAssertTrue(iconRow([WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: date(1, 0), end: date(6, 0))]))
        XCTAssertTrue(iconRow([WatchStressContextBand(kind: WatchStressContextBand.napKind, start: date(13, 0), end: date(13, 30))]))
        XCTAssertTrue(iconRow([
            WatchStressContextBand(kind: WatchStressContextBand.workoutKind, start: date(12, 0), end: date(13, 0), workoutType: "running")
        ]))

        XCTAssertFalse(iconRow([]))
        // Ended before the window opened.
        XCTAssertFalse(iconRow([WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: date(0, 0), end: date(2, 30))]))
        // A kind this build doesn't know draws nothing, so it reserves nothing.
        XCTAssertFalse(iconRow([WatchStressContextBand(kind: "meditation", start: date(12, 0), end: date(13, 0))]))
        XCTAssertFalse(WatchRecentHoursChartView.hasIconRow(.stress(nil), domain: stressDomain))
        XCTAssertFalse(WatchRecentHoursChartView.hasIconRow(readings([bucket(12, 0)]), domain: heartDomain))
    }

    /// The plot sits right of the axis labels and above the hour row, inset
    /// by half a label (or half a taller mark), and drops under the icon row
    /// only when there is one.
    func testPlotLeavesTheAxisTheHourRowAndTheIconRow() {
        let size = CGSize(width: 175, height: 67)
        let hourRow = WatchRecentHoursChartView.hourRowHeight
        let labelHalf = WatchRecentHoursChartView.axisLabelHalfHeight

        let plain = WatchRecentHoursChartView.plotRect(in: size, axisWidth: 12, hasIconRow: false, markHalfHeight: 1.5)
        XCTAssertEqual(plain, CGRect(x: 12, y: labelHalf, width: 163, height: 67 - hourRow - 2 * labelHalf))

        let withIcons = WatchRecentHoursChartView.plotRect(in: size, axisWidth: 12, hasIconRow: true, markHalfHeight: 1.5)
        XCTAssertEqual(withIcons.minY, plain.minY + WatchRecentHoursChartView.iconRowHeight)
        XCTAssertEqual(withIcons.maxY, plain.maxY)
        XCTAssertEqual(withIcons.minX, plain.minX)

        let tallMark = WatchRecentHoursChartView.plotRect(in: size, axisWidth: 12, hasIconRow: false, markHalfHeight: 4)
        XCTAssertEqual(tallMark, CGRect(x: 12, y: 4, width: 163, height: 67 - hourRow - 8))
    }

    // MARK: - Capsules

    func testCapsuleWidthClamps() {
        // 55% of one of the 17 slots' share of the plot.
        XCTAssertEqual(WatchRecentHoursChartView.capsuleWidth(forPlotWidth: 170), 5.5, accuracy: 0.0001)
        XCTAssertEqual(WatchRecentHoursChartView.capsuleWidth(forPlotWidth: 20), 1.5)
        XCTAssertEqual(WatchRecentHoursChartView.capsuleWidth(forPlotWidth: 400), 6)
    }
}
