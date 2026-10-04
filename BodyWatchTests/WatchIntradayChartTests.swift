//
//  WatchIntradayChartTests.swift
//  BodyWatchTests
//
//  Locks the "Last 8 hours" chart on the Heart Rate, HRV, Steps and Active
//  Energy pages: the rolling window opens 8 hours before the current local
//  half hour slot, the average line breaks across an hour without readings,
//  the value axis keeps every mark inside it (and starts at zero for the daily
//  totals' bars), the chart complications label it with round whole values,
//  hour labels sit on even local hours away from the plot's
//  edges, the daily total kinds take the bar style, only those four pages
//  show a chart, and the Heart Rate, HRV and Stress charts stand about half
//  again as tall as the page's other charts.
//

import XCTest
@testable import BodyWatch

final class WatchIntradayChartTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func date(day: Int = 30, _ hour: Int, _ minute: Int, _ second: Int = 0, in calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? self.calendar
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
    }

    private func bucket(_ minute: Double, min: Double = 60, max: Double = 60, average: Double = 60) -> WatchIntradayBucket {
        WatchIntradayBucket(start: base.addingTimeInterval(minute * 60), minimum: min, maximum: max, average: average)
    }

    private func chart(_ buckets: [WatchIntradayBucket]) -> WatchIntradayChart {
        WatchIntradayChart(window: WatchIntradayWindow.endingAt(base, calendar: calendar), buckets: buckets)
    }

    // MARK: - Window

    func testWindowOpensEightHoursBeforeTheCurrentSlot() {
        let now = date(15, 7, 30)
        let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
        XCTAssertEqual(window.start, date(7, 0))
        XCTAssertEqual(window.plotEnd, date(15, 30))
        XCTAssertEqual(window.end, now)
    }

    func testWindowReachesBackPastMidnight() {
        let window = WatchIntradayWindow.endingAt(date(2, 20), calendar: calendar)
        XCTAssertEqual(window.start, date(day: 29, 18, 0))
        XCTAssertEqual(window.plotEnd, date(2, 30))
    }

    func testWindowSlotsFollowLocalHalfHoursInAQuarterHourZone() {
        var kathmandu = Calendar(identifier: .gregorian)
        kathmandu.timeZone = TimeZone(identifier: "Asia/Kathmandu")!
        let window = WatchIntradayWindow.endingAt(date(10, 52, in: kathmandu), calendar: kathmandu)
        XCTAssertEqual(window.start, date(2, 30, in: kathmandu))
        XCTAssertEqual(window.plotEnd, date(11, 0, in: kathmandu))
    }

    // MARK: - Line runs

    func testLineBreaksAcrossAnHourWithoutReadings() {
        let runs = WatchIntradayChartGeometry.lineRuns([bucket(0), bucket(30), bucket(60), bucket(150)])
        XCTAssertEqual(runs.map { $0.map(\.start) }, [
            [bucket(0).start, bucket(30).start, bucket(60).start],
            [bucket(150).start]
        ])
    }

    func testLineBreaksAfterAnEmptyHourButBridgesOneEmptySlot() {
        // Starts 90 minutes apart: two empty 30 minute slots, an hour.
        XCTAssertEqual(WatchIntradayChartGeometry.lineRuns([bucket(0), bucket(90)]).count, 2)
        // Starts 60 minutes apart: one empty slot.
        XCTAssertEqual(WatchIntradayChartGeometry.lineRuns([bucket(0), bucket(60)]).count, 1)
    }

    func testLineRunsSortUnsortedSlotsAndAllowASingleSlot() {
        let runs = WatchIntradayChartGeometry.lineRuns([bucket(60), bucket(0), bucket(30)])
        XCTAssertEqual(runs.map { $0.map(\.start) }, [[bucket(0).start, bucket(30).start, bucket(60).start]])
        XCTAssertEqual(WatchIntradayChartGeometry.lineRuns([bucket(0)]).map(\.count), [1])
        XCTAssertTrue(WatchIntradayChartGeometry.lineRuns([]).isEmpty)
    }

    // MARK: - Value axis

    func testDomainCoversEveryCapsule() {
        let domain = WatchIntradayChartView.yDomain(
            for: chart([bucket(0, min: 50, max: 80, average: 60), bucket(30, min: 100, max: 150, average: 120)])
        )
        XCTAssertEqual(domain.lowerBound, 50 - 100 * 0.16, accuracy: 0.0001)
        XCTAssertEqual(domain.upperBound, 150 + 100 * 0.16, accuracy: 0.0001)
    }

    func testFlatValuesStillGetPadding() {
        let domain = WatchIntradayChartView.yDomain(
            for: chart([bucket(0, min: 44, max: 44, average: 44)])
        )
        XCTAssertLessThan(domain.lowerBound, 44)
        XCTAssertGreaterThan(domain.upperBound, 44)
    }

    func testTotalsDomainStartsAtZeroAndClearsTheTallestBar() {
        let domain = WatchIntradayChartView.yDomain(
            for: chart([bucket(0, min: 420, max: 420, average: 420), bucket(30, min: 2_210, max: 2_210, average: 2_210)]),
            style: .totals
        )
        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertEqual(domain.upperBound, 2_210 * 1.16, accuracy: 0.0001)
        XCTAssertEqual(WatchIntradayChartView.yDomain(for: chart([]), style: .totals), 0...1)
    }

    func testDomainNeverGoesBelowZero() {
        let domain = WatchIntradayChartView.yDomain(
            for: chart([bucket(0, min: 0.5, max: 3, average: 1)])
        )
        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertGreaterThan(domain.upperBound, 3)
    }

    /// The chart complications' axis labels: round whole values inside the
    /// range, at most three, and four only where three would leave one.
    func testValueTicksAreRoundWholeValuesInsideTheRange() {
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 52...98), [60, 80])
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 38.4...71.6), [40, 60])
        // A workout's wide Heart Rate range.
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 48...172), [50, 100, 150])
        // Steps of 20 would leave five and 50 one: 25 leaves three.
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 55...149), [75, 100, 125])
        // Under 10, no 2.5 step (20, 22.5, 25): never a fraction.
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 20...27.4), [20, 25])
        // A flat HRV: three would leave 45 alone, so four.
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 41...49), [42, 44, 46, 48])
        // Four would leave one too (step 2 gives five), so the one stays.
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 56...64), [60])
        // A single repeated reading's padded range: never a fraction.
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 60.76...63.24), [61, 62, 63])
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: 0...1), [0, 1])

        let domains: [ClosedRange<Double>] = [52...98, 41...49, 60.76...63.24, 12.3...19.9, 88...131]
        for domain in domains {
            let ticks = WatchIntradayChartGeometry.valueTicks(in: domain)
            XCTAssertFalse(ticks.isEmpty, "\(domain)")
            XCTAssertLessThanOrEqual(ticks.count, 4, "\(domain)")
            for tick in ticks {
                XCTAssertEqual(tick, tick.rounded(), "\(domain)")
                XCTAssertTrue(domain.contains(tick), "\(domain)")
            }
        }
    }

    // MARK: - Hour ticks

    func testHourTicksAreEvenHoursInsideTheWindow() {
        let ticks = WatchIntradayChartGeometry.hourTicks(in: date(7, 0)...date(15, 30), calendar: calendar)
        XCTAssertEqual(ticks, [date(8, 0), date(10, 0), date(12, 0), date(14, 0)])
    }

    func testHourTicksSkipHoursWithinHalfAnHourOfAnEdge() {
        XCTAssertEqual(
            WatchIntradayChartGeometry.hourTicks(in: date(7, 45)...date(15, 15), calendar: calendar),
            [date(10, 0), date(12, 0), date(14, 0)]
        )
        XCTAssertEqual(
            WatchIntradayChartGeometry.hourTicks(in: date(6, 45)...date(14, 15), calendar: calendar),
            [date(8, 0), date(10, 0), date(12, 0)]
        )
        XCTAssertEqual(
            WatchIntradayChartGeometry.hourTicks(in: date(7, 30)...date(14, 30), calendar: calendar),
            [date(10, 0), date(12, 0)]
        )
    }

    func testHourTicksFollowLocalHoursInAQuarterHourZone() {
        var kathmandu = Calendar(identifier: .gregorian)
        kathmandu.timeZone = TimeZone(identifier: "Asia/Kathmandu")!
        let ticks = WatchIntradayChartGeometry.hourTicks(
            in: date(2, 30, in: kathmandu)...date(11, 0, in: kathmandu),
            calendar: kathmandu
        )
        XCTAssertEqual(ticks, [4, 6, 8, 10].map { date($0, 0, in: kathmandu) })
    }

    // MARK: - Capsule width

    func testBarWidthStaysBetweenThreeAndTenPoints() {
        XCTAssertEqual(WatchIntradayChartView.barWidth(forPlotWidth: 10), 3)
        XCTAssertEqual(WatchIntradayChartView.barWidth(forPlotWidth: 1_000), 10)
        XCTAssertEqual(WatchIntradayChartView.barWidth(forPlotWidth: 165), 165 / 17 * 0.8, accuracy: 0.0001)
    }

    func testCapsuleWidthStaysBetweenTwoAndEightPoints() {
        XCTAssertEqual(WatchIntradayChartView.capsuleWidth(forPlotWidth: 10), 2)
        XCTAssertEqual(WatchIntradayChartView.capsuleWidth(forPlotWidth: 1_000), 8)
        XCTAssertEqual(WatchIntradayChartView.capsuleWidth(forPlotWidth: 165), 165 / 17 * 0.62, accuracy: 0.0001)
    }

    // MARK: - Style

    func testTotalsStyleForTheDailyTotalKindsOnly() {
        for kind in [WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy, WatchMetricKindKey.restingEnergy] {
            XCTAssertEqual(WatchIntradayChartView.Style.style(forKind: kind), .totals, kind)
        }
        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability, WatchMetricKindKey.sleep] {
            XCTAssertEqual(WatchIntradayChartView.Style.style(forKind: kind), .range, kind)
        }
    }

    // MARK: - Page gate

    func testOnlyTheFourIntradayPagesShowAChart() {
        let filled = chart([bucket(0)])
        for kind in [
            WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability,
            WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy
        ] {
            XCTAssertNotNil(WatchMetricDetailView.intradayChart(filled, kind: kind), kind)
        }
        for kind in [
            WatchMetricKindKey.sleep, WatchMetricKindKey.trainingLoad, WatchMetricKindKey.restingHeartRate,
            WatchMetricKindKey.stress, WatchMetricKindKey.wristTemperature, WatchMetricKindKey.restingEnergy
        ] {
            XCTAssertNil(WatchMetricDetailView.intradayChart(filled, kind: kind), kind)
        }
    }

    func testHeartAndStressChartsStandTaller() {
        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability, WatchMetricKindKey.stress] {
            XCTAssertEqual(WatchMetricDetailView.intradayChartHeight(forKind: kind), 130, kind)
        }
        for kind in [WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy, WatchMetricKindKey.restingEnergy] {
            XCTAssertEqual(WatchMetricDetailView.intradayChartHeight(forKind: kind), 86, kind)
        }
    }

    func testPreviewTotalsCarryOneNumberPerSlot() {
        let steps = WatchIntradayChart.preview(kind: WatchMetricKindKey.steps, now: base, calendar: calendar)
        XCTAssertFalse(steps.buckets.isEmpty)
        for bucket in steps.buckets {
            XCTAssertEqual(bucket.minimum, bucket.average)
            XCTAssertEqual(bucket.maximum, bucket.average)
            XCTAssertGreaterThan(bucket.average, 0)
        }
        XCTAssertLessThan(steps.buckets.count, 17, "an idle hour leaves slots out")
        XCTAssertEqual(WatchIntradayChart.preview(kind: WatchMetricKindKey.activeEnergy, now: base, calendar: calendar).buckets.count, steps.buckets.count)
    }

    func testNoChartWithoutReadings() {
        XCTAssertNil(WatchMetricDetailView.intradayChart(nil, kind: WatchMetricKindKey.heartRate))
        XCTAssertNil(WatchMetricDetailView.intradayChart(chart([]), kind: WatchMetricKindKey.heartRate))
    }
}
