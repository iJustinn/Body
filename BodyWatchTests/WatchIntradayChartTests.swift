//
//  WatchIntradayChartTests.swift
//  BodyWatchTests
//
//  Locks the "Last 8 hours" chart on the Heart Rate, HRV, Blood Oxygen, Steps
//  and Active Energy pages: the rolling window opens 8 hours before the
//  current local half hour slot, the average line breaks across an hour
//  without readings, the value axis keeps every mark inside it (and starts at
//  zero for the daily totals' bars, and stops half a unit above Blood
//  Oxygen's 100% so no label passes it), the chart complications label it
//  with round whole values, hour labels sit on even local hours away from the
//  plot's edges, the daily total kinds take the bar style, only those five
//  pages show a chart (Blood Oxygen's from the snapshot, not the live store),
//  and the Heart Rate, HRV, Blood Oxygen and Stress charts stand about half
//  again as tall as the page's other charts.
//
//  The snapshot's chart re-windowed to now keeps only the slots inside the
//  current window, and two reads of a combined kind (Blood Oxygen) merge slot
//  by slot: the later window, the union of both charts' slots inside it, the
//  later chart winning a shared slot (the incoming one on a tie), sorted, and
//  nothing when no slot is left.
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

    /// A slot starting at `hour`:`minute` on the test day, every field `value`
    /// unless `average` names another.
    private func slot(_ hour: Int, _ minute: Int, _ value: Double, average: Double? = nil) -> WatchIntradayBucket {
        WatchIntradayBucket(start: date(hour, minute), minimum: value, maximum: value, average: average ?? value)
    }

    /// A chart read at `hour`:`minute` on the test day, holding `buckets`.
    private func chart(endingAt hour: Int, _ minute: Int, _ buckets: [WatchIntradayBucket]) -> WatchIntradayChart {
        WatchIntradayChart(window: WatchIntradayWindow.endingAt(date(hour, minute), calendar: calendar), buckets: buckets)
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

    // MARK: - Re-windowing the snapshot's chart

    /// A chart read at 15:07 (window 07:00 to 15:30) shown at 17:20 (window
    /// 09:00 to 17:30): the slots before 09:00 drop, the rest stay as they
    /// were, on the current window.
    func testWindowedKeepsTheSlotsInsideTheCurrentWindow() throws {
        let read = chart(endingAt: 15, 7, [slot(7, 0, 95), slot(8, 30, 96), slot(9, 0, 97), slot(14, 30, 98)])

        let shown = try XCTUnwrap(read.windowed(endingAt: date(17, 20), calendar: calendar))

        XCTAssertEqual(shown.window, WatchIntradayWindow.endingAt(date(17, 20), calendar: calendar))
        XCTAssertEqual(shown.buckets, [slot(9, 0, 97), slot(14, 30, 98)])
    }

    /// Shown in the same window it was read in, the chart is unchanged but
    /// for the window's `end`, which follows `now`.
    func testWindowedInTheSameSlotKeepsEverySlot() throws {
        let read = chart(endingAt: 15, 7, [slot(7, 0, 95), slot(15, 0, 97)])

        let shown = try XCTUnwrap(read.windowed(endingAt: date(15, 20), calendar: calendar))

        XCTAssertEqual(shown.buckets, read.buckets)
        XCTAssertEqual(shown.window.start, read.window.start)
        XCTAssertEqual(shown.window.plotEnd, read.window.plotEnd)
        XCTAssertEqual(shown.window.end, date(15, 20))
    }

    /// Nothing left in the current window, or nothing read at all: no chart,
    /// so the page doesn't scroll for an empty one.
    func testWindowedIsNilWithoutASlotInTheCurrentWindow() {
        XCTAssertNil(chart(endingAt: 15, 7, [slot(7, 0, 95), slot(8, 30, 96)]).windowed(endingAt: date(17, 20), calendar: calendar))
        XCTAssertNil(chart(endingAt: 15, 7, []).windowed(endingAt: date(15, 7), calendar: calendar))
        XCTAssertNil(chart(endingAt: 15, 7, [slot(9, 0, 97)]).windowed(endingAt: date(23, 50), calendar: calendar))
    }

    // MARK: - Combining two reads (Blood Oxygen)

    /// An iPhone push built at 15:07 from samples it read earlier, then a
    /// watch read at 16:12: the later window, every slot of either chart that
    /// starts in it, and the watch's slot where both have one.
    func testCombinedTakesTheLaterWindowAndTheUnionOfSlots() throws {
        let phone = chart(endingAt: 15, 7, [slot(7, 30, 94), slot(10, 0, 96), slot(13, 0, 95)])
        let watch = chart(endingAt: 16, 12, [slot(10, 0, 98), slot(15, 30, 97)])

        let combined = try XCTUnwrap(phone.combined(with: watch))

        XCTAssertEqual(combined.window, watch.window)
        XCTAssertEqual(combined.buckets, [slot(10, 0, 98), slot(13, 0, 95), slot(15, 30, 97)])
    }

    /// The later chart wins whichever side it is on, so the order of the
    /// call doesn't change the result.
    func testCombinedIsTheSameEitherWayRound() {
        let earlier = chart(endingAt: 15, 7, [slot(9, 0, 94), slot(12, 0, 95)])
        let later = chart(endingAt: 16, 12, [slot(12, 0, 99), slot(16, 0, 97)])

        XCTAssertEqual(earlier.combined(with: later), later.combined(with: earlier))
        XCTAssertEqual(earlier.combined(with: later)?.buckets, [slot(9, 0, 94), slot(12, 0, 99), slot(16, 0, 97)])
    }

    /// On an equal window end the incoming chart wins the shared slot.
    func testCombinedTieGoesToTheIncomingChart() {
        let held = chart(endingAt: 15, 7, [slot(12, 0, 95), slot(13, 0, 96)])
        let incoming = chart(endingAt: 15, 7, [slot(12, 0, 98)])

        XCTAssertEqual(held.combined(with: incoming)?.buckets, [slot(12, 0, 98), slot(13, 0, 96)])
        XCTAssertEqual(incoming.combined(with: held)?.buckets, [slot(12, 0, 95), slot(13, 0, 96)])
    }

    /// Slots of either chart before the later window's start drop.
    func testCombinedDropsSlotsBeforeTheLaterWindow() {
        let old = chart(endingAt: 9, 10, [slot(1, 30, 95), slot(3, 0, 96), slot(8, 30, 97)])
        let new = chart(endingAt: 11, 40, [slot(2, 30, 94), slot(11, 0, 98)])

        XCTAssertEqual(new.window.start, date(3, 30))
        XCTAssertEqual(old.combined(with: new)?.buckets, [slot(8, 30, 97), slot(11, 0, 98)])
    }

    /// Unsorted input still encodes in start order, so a snapshot holding the
    /// result stays byte for byte the same across devices.
    func testCombinedSortsTheSlotsByStart() throws {
        let a = chart(endingAt: 15, 7, [slot(14, 0, 96), slot(8, 0, 95)])
        let b = chart(endingAt: 15, 20, [slot(11, 30, 97), slot(9, 0, 94)])

        let starts = try XCTUnwrap(a.combined(with: b)).buckets.map(\.start)

        XCTAssertEqual(starts, [date(8, 0), date(9, 0), date(11, 30), date(14, 0)])
    }

    /// Every combined slot stays on the half hour grid of the window it
    /// lands in, so the two devices' slots for one half hour share a key.
    func testCombinedSlotsStayOnTheWindowsGrid() throws {
        let phone = chart(endingAt: 15, 7, [slot(7, 0, 95), slot(10, 30, 96)])
        let watch = chart(endingAt: 17, 45, [slot(12, 0, 97), slot(17, 30, 98)])

        let combined = try XCTUnwrap(phone.combined(with: watch))

        for bucket in combined.buckets {
            let offset = bucket.start.timeIntervalSince(combined.window.start)
            XCTAssertEqual(offset.truncatingRemainder(dividingBy: WatchIntradayWindow.slotLength), 0, "\(bucket.start)")
            XCTAssertGreaterThanOrEqual(offset, 0)
            XCTAssertLessThan(bucket.start, combined.window.plotEnd)
        }
    }

    /// No slot left after the window moves on, or an empty read meeting
    /// nothing in its window: no chart.
    func testCombinedIsNilWhenNoSlotIsLeft() {
        let old = chart(endingAt: 3, 10, [slot(1, 0, 95)])
        let emptyLater = chart(endingAt: 15, 7, [])

        XCTAssertNil(old.combined(with: emptyLater))
        XCTAssertNil(emptyLater.combined(with: old))
        XCTAssertNil(emptyLater.combined(with: emptyLater))
    }

    /// An empty later read only re-windows what is held: a read that found
    /// nothing never deletes the other device's slots inside its window.
    func testAnEmptyLaterReadKeepsTheHeldSlotsInsideItsWindow() {
        let held = chart(endingAt: 15, 7, [slot(7, 30, 94), slot(12, 0, 96)])
        let empty = chart(endingAt: 16, 12, [])

        let combined = held.combined(with: empty)

        XCTAssertEqual(combined?.window, empty.window)
        XCTAssertEqual(combined?.buckets, [slot(12, 0, 96)])
    }

    /// Nothing to combine with leaves the chart as it is.
    func testCombinedWithNothingReturnsTheChart() {
        let held = chart(endingAt: 15, 7, [slot(12, 0, 96)])
        XCTAssertEqual(held.combined(with: nil), held)
    }

    /// The merges' entry point: with nothing held, an incoming chart with
    /// slots is taken as is and an empty or missing one leaves nothing;
    /// with a chart held it combines.
    func testCombiningHandlesAMissingCurrentChart() {
        let incoming = chart(endingAt: 15, 7, [slot(12, 0, 96)])
        let held = chart(endingAt: 14, 0, [slot(9, 0, 95)])

        XCTAssertEqual(WatchIntradayChart.combining(nil, with: incoming), incoming)
        XCTAssertNil(WatchIntradayChart.combining(nil, with: chart(endingAt: 15, 7, [])))
        XCTAssertNil(WatchIntradayChart.combining(nil, with: nil))
        XCTAssertEqual(WatchIntradayChart.combining(held, with: nil), held)
        XCTAssertEqual(WatchIntradayChart.combining(held, with: incoming), held.combined(with: incoming))
        XCTAssertEqual(WatchIntradayChart.combining(held, with: incoming)?.buckets, [slot(9, 0, 95), slot(12, 0, 96)])
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

    /// A lone 100% reading: padded to 98...102, then capped half a unit
    /// above the ceiling, so the dot keeps room inside the plot and the axis
    /// labels stop at 100.
    func testCeilingCapsALoneReadingAtTheCeiling() {
        let domain = WatchIntradayChartGeometry.rangeDomain(for: [bucket(0, min: 100, max: 100, average: 100)], ceiling: 100)

        XCTAssertEqual(domain, 98...100.5)
        XCTAssertEqual(WatchIntradayChartGeometry.valueTicks(in: domain), [98, 99, 100])
        // Without a ceiling the same reading pads past 100.
        XCTAssertEqual(WatchIntradayChartGeometry.rangeDomain(for: [bucket(0, min: 100, max: 100, average: 100)]), 98...102)
    }

    /// A spread reaching 100 caps the same way; one whose padded top stays
    /// under the cap is left as it is, and a reading past the ceiling (not a
    /// real percent) keeps the plain padding so it never clips.
    func testCeilingOnlyCapsWhenThePaddingPassesIt() {
        XCTAssertEqual(WatchIntradayChartGeometry.rangeDomain(for: [bucket(0, min: 94, max: 100, average: 97)], ceiling: 100), 93...100.5)
        XCTAssertEqual(WatchIntradayChartGeometry.rangeDomain(for: [bucket(0, min: 94, max: 97, average: 96)], ceiling: 100), 93...98)
        XCTAssertEqual(
            WatchIntradayChartGeometry.rangeDomain(for: [bucket(0, min: 95, max: 101, average: 98)], ceiling: 100),
            WatchIntradayChartGeometry.rangeDomain(for: [bucket(0, min: 95, max: 101, average: 98)])
        )
        XCTAssertEqual(WatchIntradayChartGeometry.rangeDomain(for: [], ceiling: 100), 0...1)
    }

    /// Whatever the readings, no axis label ever reads above 100%.
    func testCeilingKeepsEveryTickAtOrBelowIt() {
        let spreads: [[WatchIntradayBucket]] = [
            [bucket(0, min: 100, max: 100, average: 100)],
            [bucket(0, min: 99, max: 100, average: 99)],
            [bucket(0, min: 96, max: 100, average: 98), bucket(30, min: 93, max: 97, average: 95)],
            [bucket(0, min: 88, max: 100, average: 95)],
            [bucket(0, min: 97, max: 99, average: 98)],
            WatchIntradayChart.preview(kind: WatchMetricKindKey.oxygenSaturation, now: base, calendar: calendar).buckets
        ]
        for buckets in spreads {
            let domain = WatchIntradayChartGeometry.rangeDomain(for: buckets, ceiling: 100)
            XCTAssertLessThanOrEqual(domain.upperBound, 100.5, "\(buckets.map(\.maximum))")
            XCTAssertGreaterThanOrEqual(domain.upperBound, buckets.map(\.maximum).max() ?? 0)
            let ticks = WatchIntradayChartGeometry.valueTicks(in: domain)
            XCTAssertFalse(ticks.isEmpty, "\(domain)")
            XCTAssertTrue(ticks.allSatisfy { $0 <= 100 }, "\(ticks)")
        }
    }

    /// The page's chart passes the kind's ceiling to the `.range` axis; the
    /// bars' axis ignores it.
    func testPageDomainFollowsTheKindsCeiling() {
        let full = chart([bucket(0, min: 100, max: 100, average: 100)])
        let ceiling = WatchMetricKindKey.valueCeiling(forKind: WatchMetricKindKey.oxygenSaturation)

        XCTAssertEqual(ceiling, 100)
        XCTAssertEqual(WatchIntradayChartView.yDomain(for: full, style: .range, ceiling: ceiling), 98...100.5)
        XCTAssertEqual(WatchIntradayChartView.yDomain(for: full, style: .range), 98...102)
        let totals = WatchIntradayChartView.yDomain(for: full, style: .totals, ceiling: ceiling)
        XCTAssertEqual(totals.lowerBound, 0)
        XCTAssertEqual(totals.upperBound, 116, accuracy: 0.0001)
        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability, WatchMetricKindKey.steps] {
            XCTAssertNil(WatchMetricKindKey.valueCeiling(forKind: kind), kind)
        }
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
        for kind in [
            WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability,
            WatchMetricKindKey.oxygenSaturation, WatchMetricKindKey.sleep
        ] {
            XCTAssertEqual(WatchIntradayChartView.Style.style(forKind: kind), .range, kind)
        }
    }

    // MARK: - Page gate

    func testOnlyTheFiveIntradayPagesShowAChart() {
        let filled = chart([bucket(0)])
        for kind in [
            WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability,
            WatchMetricKindKey.oxygenSaturation, WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy
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

    /// Blood Oxygen's page draws the snapshot's chart, never a live read: the
    /// store doesn't read it, and the live kinds don't take the snapshot's.
    @MainActor
    func testBloodOxygenChartsFromTheSnapshotNotTheStore() {
        XCTAssertEqual(WatchMetricDetailView.snapshotChartKinds, [WatchMetricKindKey.oxygenSaturation])
        XCTAssertFalse(WatchIntradayChartStore.chartKinds.contains(WatchMetricKindKey.oxygenSaturation))
        XCTAssertTrue(WatchMetricDetailView.snapshotChartKinds.isDisjoint(with: WatchIntradayChartStore.chartKinds))
    }

    func testHeartAndStressChartsStandTaller() {
        for kind in [
            WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability,
            WatchMetricKindKey.oxygenSaturation, WatchMetricKindKey.stress
        ] {
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

    /// The Blood Oxygen preview: whole percents, one slot reaching 100 so the
    /// capped axis shows, and the latest slot averaging 97 like the page's
    /// headline.
    func testPreviewBloodOxygenReadsWholePercents() throws {
        let preview = WatchIntradayChart.preview(kind: WatchMetricKindKey.oxygenSaturation, now: base, calendar: calendar)
        XCTAssertFalse(preview.buckets.isEmpty)
        for bucket in preview.buckets {
            for value in [bucket.minimum, bucket.average, bucket.maximum] {
                XCTAssertEqual(value, value.rounded())
                XCTAssertTrue((90...100).contains(value), "\(value)")
            }
            XCTAssertLessThanOrEqual(bucket.minimum, bucket.average)
            XCTAssertLessThanOrEqual(bucket.average, bucket.maximum)
        }
        XCTAssertEqual(preview.buckets.map(\.maximum).max(), 100)
        XCTAssertEqual(try XCTUnwrap(preview.buckets.max { $0.start < $1.start }).average, 97)
    }

    func testNoChartWithoutReadings() {
        XCTAssertNil(WatchMetricDetailView.intradayChart(nil, kind: WatchMetricKindKey.heartRate))
        XCTAssertNil(WatchMetricDetailView.intradayChart(chart([]), kind: WatchMetricKindKey.heartRate))
    }
}
