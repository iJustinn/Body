//
//  WatchStressChartTests.swift
//  BodyWatchTests
//
//  Locks the Stress page's "Last 8 hours" chart: it shares the Heart Rate and
//  HRV charts' window and hour labels, places each 15 minute window by its
//  own interval clamped to that window, drops windows outside it and the
//  unscored gaps, clips the context shading, and only the Stress page shows
//  the chart, only while a window falls inside the last 8 hours.
//

import XCTest
@testable import BodyWatch

final class WatchStressChartTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(day: Int = 30, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// 15:07: the window runs 07:00 to 15:30.
    private var now: Date { date(15, 7) }
    private var domain: ClosedRange<Date> { WatchStressChartView.domain(endingAt: now, calendar: calendar) }

    private func timeline(start: Date, slots: [Int?], end: Date? = nil, context: [WatchStressContextBand] = []) -> WatchStressTimeline {
        WatchStressTimeline(
            start: start,
            end: end ?? start.addingTimeInterval(Double(slots.count) * WatchStressTimeline.slotLength),
            slots: slots,
            context: context,
            computedAt: nil
        )
    }

    // MARK: - Window and ticks

    func testDomainIsTheIntradayWindow() {
        let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
        XCTAssertEqual(domain, window.start...window.plotEnd)
        XCTAssertEqual(domain, date(7, 0)...date(15, 30))
    }

    func testTicksReuseTheIntradayHourTicks() {
        let ticks = WatchStressChartView.ticks(endingAt: now, calendar: calendar)
        XCTAssertEqual(ticks, WatchIntradayChartView.hourTicks(in: domain, calendar: calendar))
        XCTAssertEqual(ticks, [date(8, 0), date(10, 0), date(12, 0), date(14, 0)])
    }

    // MARK: - X mapping

    func testFractionMapsAcrossTheDomainAndClamps() {
        XCTAssertEqual(WatchStressChartView.fraction(for: date(7, 0), in: domain), 0)
        XCTAssertEqual(WatchStressChartView.fraction(for: date(15, 30), in: domain), 1)
        XCTAssertEqual(WatchStressChartView.fraction(for: date(11, 15), in: domain), 0.5, accuracy: 0.0001)
        XCTAssertEqual(WatchStressChartView.fraction(for: date(5, 0), in: domain), 0)
        XCTAssertEqual(WatchStressChartView.fraction(for: date(18, 0), in: domain), 1)
    }

    func testMarksArePlacedByTheirWindow() {
        let marks = WatchStressChartView.marks(
            in: timeline(start: date(11, 15), slots: [40, WatchStressTimeline.activityMarker]),
            domain: domain
        )
        let quarter = 15.0 / 510.0
        XCTAssertEqual(marks.map(\.slot), [.scored(40), .activity])
        XCTAssertEqual(marks[0].xStart, 0.5, accuracy: 0.0001)
        XCTAssertEqual(marks[0].xEnd, 0.5 + quarter, accuracy: 0.0001)
        XCTAssertEqual(marks[1].xStart, 0.5 + quarter, accuracy: 0.0001)
        XCTAssertEqual(marks[1].xEnd, 0.5 + 2 * quarter, accuracy: 0.0001)
    }

    /// The latest window is drawn only up to the timeline's `end`, and one
    /// starting at `end` is cut to nothing and skipped.
    func testTheLatestWindowStopsAtTheTimelineEnd() {
        let marks = WatchStressChartView.marks(
            in: timeline(start: date(14, 45), slots: [40, 42, 44], end: date(15, 7)),
            domain: domain
        )
        XCTAssertEqual(marks.map(\.slot), [.scored(40), .scored(42)])
        XCTAssertEqual(marks[1].xEnd, WatchStressChartView.fraction(for: date(15, 7), in: domain), accuracy: 0.0001)
    }

    // MARK: - Visible windows

    func testWindowsOutsideTheDomainAreDropped() {
        // 06:30 and 06:45 end at or before 07:00; 07:00 is the first inside.
        let marks = WatchStressChartView.marks(
            in: timeline(start: date(6, 30), slots: [20, 22, 24]),
            domain: domain
        )
        XCTAssertEqual(marks.map(\.slot), [.scored(24)])
        XCTAssertEqual(marks[0].xStart, 0)
    }

    func testAWindowStraddlingTheDomainStartIsClipped() {
        let marks = WatchStressChartView.marks(in: timeline(start: date(6, 50), slots: [30]), domain: domain)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].xStart, 0)
        XCTAssertEqual(marks[0].xEnd, WatchStressChartView.fraction(for: date(7, 5), in: domain), accuracy: 0.0001)
    }

    func testUnscoredWindowsAreGaps() {
        let marks = WatchStressChartView.marks(in: timeline(start: date(12, 0), slots: [nil, 50, nil]), domain: domain)
        XCTAssertEqual(marks.map(\.slot), [.scored(50)])
        XCTAssertEqual(marks[0].xStart, WatchStressChartView.fraction(for: date(12, 15), in: domain), accuracy: 0.0001)
    }

    func testATimelineOlderThanTheWindowHasNothingToDraw() {
        let old = timeline(start: date(4, 0), slots: [30, 35, 40, 45, 50, 55, 60, 65])
        XCTAssertTrue(old.hasMarks)
        XCTAssertTrue(WatchStressChartView.marks(in: old, domain: domain).isEmpty)
        XCTAssertFalse(WatchStressChartView.hasVisibleMarks(old, endingAt: now, calendar: calendar))
    }

    // MARK: - Context bands

    func testContextBandsAreClippedToTheDomain() {
        let sleep = WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: date(0, 0), end: date(8, 0))
        let workout = WatchStressContextBand(
            kind: WatchStressContextBand.workoutKind,
            start: date(13, 0),
            end: date(14, 0),
            workoutType: "running"
        )
        let earlier = WatchStressContextBand(kind: WatchStressContextBand.napKind, start: date(5, 0), end: date(6, 0))
        let spans = WatchStressChartView.contextSpans(
            in: timeline(start: date(7, 0), slots: [30], context: [earlier, sleep, workout]),
            domain: domain
        )
        XCTAssertEqual(spans.map(\.band), [sleep, workout])
        XCTAssertEqual(spans[0].xStart, 0)
        XCTAssertEqual(spans[0].xEnd, WatchStressChartView.fraction(for: date(8, 0), in: domain), accuracy: 0.0001)
        XCTAssertEqual(spans[1].xStart, WatchStressChartView.fraction(for: date(13, 0), in: domain), accuracy: 0.0001)
    }

    // MARK: - Y mapping and mark width

    func testScoresMapFromTheFloorToTheTopAndClamp() {
        let plot = CGRect(x: 0, y: 10, width: 100, height: 40)
        XCTAssertEqual(WatchStressChartView.y(forScore: 0, in: plot), 50)
        XCTAssertEqual(WatchStressChartView.y(forScore: 100, in: plot), 10)
        XCTAssertEqual(WatchStressChartView.y(forScore: 25, in: plot), 40)
        XCTAssertEqual(WatchStressChartView.y(forScore: 140, in: plot), 10)
        XCTAssertEqual(WatchStressChartView.y(forScore: -5, in: plot), 50)
    }

    func testMarksAreInsetButNeverNarrowerThanTheMinimum() {
        let plot = CGRect(x: 0, y: 0, width: 200, height: 40)
        let wide = WatchStressChartView.markSpan(xStart: 0.5, xEnd: 0.53, in: plot)
        XCTAssertEqual(wide.x, 101, accuracy: 0.0001)
        XCTAssertEqual(wide.width, 4, accuracy: 0.0001)
        let narrow = WatchStressChartView.markSpan(xStart: 0.5, xEnd: 0.505, in: plot)
        XCTAssertEqual(narrow.width, CGFloat(StressChartStyle.markMinimumWidth))
    }

    // MARK: - Page gate

    func testOnlyTheStressPageShowsTheChart() {
        let recent = timeline(start: date(12, 0), slots: [40])
        XCTAssertNotNil(
            WatchMetricDetailView.stressTimeline(recent, kind: WatchMetricKindKey.stress, now: now, calendar: calendar)
        )
        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.sleep, WatchMetricKindKey.trainingLoad] {
            XCTAssertNil(WatchMetricDetailView.stressTimeline(recent, kind: kind, now: now, calendar: calendar), kind)
        }
    }

    func testNoChartWithoutAWindowToDraw() {
        let stress = WatchMetricKindKey.stress
        XCTAssertNil(WatchMetricDetailView.stressTimeline(nil, kind: stress, now: now, calendar: calendar))
        XCTAssertNil(WatchMetricDetailView.stressTimeline(timeline(start: date(12, 0), slots: []), kind: stress, now: now, calendar: calendar))
        XCTAssertNil(
            WatchMetricDetailView.stressTimeline(timeline(start: date(12, 0), slots: [nil, nil]), kind: stress, now: now, calendar: calendar)
        )
        XCTAssertNil(
            WatchMetricDetailView.stressTimeline(timeline(start: date(4, 0), slots: [40, 42]), kind: stress, now: now, calendar: calendar)
        )
        // Movement alone still draws its stubs, so the chart shows.
        XCTAssertNotNil(
            WatchMetricDetailView.stressTimeline(
                timeline(start: date(12, 0), slots: [WatchStressTimeline.activityMarker]),
                kind: stress,
                now: now,
                calendar: calendar
            )
        )
    }

    // MARK: - Preview fixture

    func testPreviewEndsAtNowOnTheStressGrid() {
        let preview = WatchStressTimeline.preview(now: now, calendar: calendar)
        XCTAssertEqual(preview.start, date(6, 0))
        XCTAssertEqual(preview.end, now)
        XCTAssertEqual(preview.computedAt, now)
        XCTAssertEqual(preview.interval(at: preview.slots.count - 1), DateInterval(start: date(15, 0), end: now))
        XCTAssertTrue(WatchStressChartView.hasVisibleMarks(preview, endingAt: now, calendar: calendar))
        XCTAssertEqual(
            Set(preview.context.map(\.kind)),
            [WatchStressContextBand.sleepKind, WatchStressContextBand.workoutKind]
        )
    }

    /// The Stress card's symbol keeps the iPhone card's fixed Stress pink
    /// whatever the band, while a banded card like Training Load keeps its
    /// carried status color.
    func testStressCardSymbolUsesTheStressPinkNotTheBandColor() {
        let relaxedGreen = WatchMetricColor(red: 0.20, green: 0.80, blue: 0.45)
        let stress = WatchMetric(
            kind: WatchMetricKindKey.stress, title: "Stress", displayValue: "42", unit: "",
            score: 42, fillFraction: 0.42, rawValue: 42, rangeMin: 0, rangeMax: 100, tint: relaxedGreen
        )
        XCTAssertEqual(WatchMetricCardView.symbolTint(for: stress), WatchMetricColor(red: 0.90, green: 0.35, blue: 0.75))

        let trainingLoad = WatchMetric(
            kind: WatchMetricKindKey.trainingLoad, title: "Training Load", displayValue: "1.05", unit: "",
            score: nil, fillFraction: 0.5, rawValue: 1.05, rangeMin: 0, rangeMax: 2, tint: relaxedGreen
        )
        XCTAssertEqual(WatchMetricCardView.symbolTint(for: trainingLoad), relaxedGreen)
    }
}
