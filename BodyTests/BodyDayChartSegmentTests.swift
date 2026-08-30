//
//  BodyDayChartSegmentTests.swift
//  BodyTests
//
//  Covers the all-day metric chart's line-segmenting rule: consecutive dots
//  that are 4 hours or more apart must start a new segment (so the line does
//  not connect across long data gaps), while closer dots stay connected.
//

import SwiftUI
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

    // MARK: - Day-stable context-interval identity (highlight morphing)

    private func interval(
        kind: BodyHealthMetricDayContextInterval.Kind,
        title: String,
        startHour: Double
    ) -> BodyHealthMetricDayContextInterval {
        BodyHealthMetricDayContextInterval(
            kind: kind,
            startDate: date(hour: startHour),
            endDate: date(hour: startHour + 1),
            title: title,
            symbolName: "bed.double.fill",
            color: .blue
        )
    }

    func testAssigningOrdinalsGivesDayStableIdsPerKindAndTitle() {
        let intervals = BodyHealthMetricDayChart.assigningOrdinals(to: [
            interval(kind: .sleep, title: "Sleep", startHour: 0),
            interval(kind: .workout, title: "Run", startHour: 7),
            interval(kind: .sleep, title: "Nap", startHour: 13),
            interval(kind: .workout, title: "Run", startHour: 17),
            interval(kind: .workout, title: "Yoga", startHour: 20)
        ])

        XCTAssertEqual(
            intervals.map(\.id),
            ["sleep-Sleep-0", "workout-Run-0", "sleep-Nap-0", "workout-Run-1", "workout-Yoga-0"]
        )
    }

    // MARK: - Reference-day plotting (cross-day morphing)

    func testNormalizedPlotDateMapsSameTimeOfDayOnDifferentDaysToTheSameDate() {
        XCTAssertEqual(
            BodyHealthMetricDayChart.normalizedPlotDate(for: date(hour: 9.5), dayStart: date(hour: 0)),
            BodyHealthMetricDayChart.normalizedPlotDate(for: date(hour: 249.5), dayStart: date(hour: 240))
        )
    }

    func testNormalizedPlotDateClampsOutOfDayDatesToTheDomainEdges() {
        let dayStart = date(hour: 24)
        let domainStart = BodyHealthMetricDayChart.normalizedPlotDate(for: dayStart, dayStart: dayStart)

        XCTAssertEqual(
            BodyHealthMetricDayChart.normalizedPlotDate(for: date(hour: 23), dayStart: dayStart),
            domainStart
        )
        XCTAssertEqual(
            BodyHealthMetricDayChart.normalizedPlotDate(for: date(hour: 49), dayStart: dayStart),
            domainStart.addingTimeInterval(86_400)
        )
    }

    // MARK: - Placeholder dots (cross-day fade)

    /// The chart always passes a local-midnight `dayStart`, and the hour keys
    /// inside `addingPlaceholderDots` come from local hour-of-day — so these
    /// tests must anchor on a real local midnight, not the GMT reference
    /// instant `date(hour:)` uses. Jan 1 2001 has no DST transition anywhere.
    private static let placeholderDayStart = Calendar.bodyGregorian.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    private func dayEntry(
        hour: Int,
        value: Double,
        role: BodyHealthSourceRole = .primary,
        dayStart: Date = BodyDayChartSegmentTests.placeholderDayStart
    ) -> BodyHealthMetricDayChartEntry {
        BodyHealthMetricDayChartEntry(
            sourceName: role == .primary ? "Primary" : "Secondary",
            sourceRole: role,
            bucket: HealthTrendHourlyBucket(
                hourStart: dayStart.addingTimeInterval(TimeInterval(hour) * 3_600),
                averageValue: value,
                samples: []
            ),
            segmentIndex: 0
        )
    }

    private func hourIndex(of entry: BodyHealthMetricDayChartEntry) -> Int {
        Int(entry.bucket.hourStart.timeIntervalSince(Self.placeholderDayStart) / 3_600)
    }

    func testAddingPlaceholderDotsFillsEveryHourWithInvisibleDots() {
        let real = [dayEntry(hour: 2, value: 10), dayEntry(hour: 20, value: 30)]
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: real,
            fullEntries: real,
            dayStart: Self.placeholderDayStart
        )

        XCTAssertEqual(filled.count, 24)
        XCTAssertEqual(filled.filter { !$0.isPlaceholder }.map(\.plotDate), real.map(\.plotDate))
        // Placeholder ids reuse the role-hour scheme, so a real dot on another
        // day lands on the same identity and fades through it.
        XCTAssertEqual(Set(filled.map(\.id)).count, 24)
        XCTAssertTrue(filled.filter(\.isPlaceholder).allSatisfy { $0.id.hasPrefix("primary-") })
    }

    func testPlaceholderDotsBorrowTheNearestHourValuePreferringEarlierOnTies() {
        let real = [dayEntry(hour: 2, value: 10), dayEntry(hour: 20, value: 30)]
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: real,
            fullEntries: real,
            dayStart: Self.placeholderDayStart
        )
        let valueByHour = Dictionary(
            uniqueKeysWithValues: filled.map { (hourIndex(of: $0), $0.averageValue) }
        )

        XCTAssertEqual(valueByHour[3], 10)
        XCTAssertEqual(valueByHour[19], 30)
        // Hour 11 is 9 hours from both data hours; the earlier one wins.
        XCTAssertEqual(valueByHour[11], 10)
    }

    func testCollapsedFlatRunHoursFadeAtTheirOwnValue() {
        // Hours 0-2 hold a flat 80 before a jump at hour 3, so collapsing
        // drops the interior hour-1 dot. Its placeholder must sit at the run's
        // own value — not a nearest-neighbor borrow.
        let full = [
            dayEntry(hour: 0, value: 80), dayEntry(hour: 1, value: 80),
            dayEntry(hour: 2, value: 80), dayEntry(hour: 3, value: 95)
        ]
        let visible = BodyHealthMetricDayChart.collapsingUnchangedRunPoints(full)
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: visible,
            fullEntries: full,
            dayStart: Self.placeholderDayStart
        )
        let hourOne = filled.first { hourIndex(of: $0) == 1 }

        XCTAssertEqual(visible.map { hourIndex(of: $0) }, [0, 2, 3])
        XCTAssertEqual(hourOne?.isPlaceholder, true)
        XCTAssertEqual(hourOne?.averageValue, 80)
    }

    func testMakeLineSegmentsPairsConsecutiveReadingsAndBreaksAtFourHourGaps() {
        // Hours 1,2,3 chain into two pairs; the 3→9 jump (6h ≥ 4h) breaks the
        // line, leaving hour 9 an isolated reading with no real pair.
        let full = [
            dayEntry(hour: 1, value: 60), dayEntry(hour: 2, value: 70),
            dayEntry(hour: 3, value: 65), dayEntry(hour: 9, value: 80)
        ]
        let segments = BodyHealthMetricDayChart.makeLineSegments(
            from: full,
            dayStart: Self.placeholderDayStart
        )
        let real = segments.filter { !$0.isPlaceholder }

        XCTAssertEqual(real.map(\.hourIndex), [1, 2])
        XCTAssertEqual(real.map(\.startValue), [60, 70])
        XCTAssertEqual(real.map(\.endValue), [70, 65])
        // Every other hour holds an invisible placeholder, one mark per hour.
        XCTAssertEqual(segments.count, 24)
        XCTAssertEqual(Set(segments.map(\.id)).count, 24)
    }

    func testMakeLineSegmentsSpansSubThresholdGapsDirectly() {
        // 3h apart stays connected, exactly like the rendered line's gap rule.
        let full = [dayEntry(hour: 2, value: 60), dayEntry(hour: 5, value: 90)]
        let real = BodyHealthMetricDayChart.makeLineSegments(
            from: full,
            dayStart: Self.placeholderDayStart
        ).filter { !$0.isPlaceholder }

        XCTAssertEqual(real.map(\.hourIndex), [2])
        XCTAssertEqual(real.first?.endValue, 90)
    }

    func testLineSegmentPlaceholderSitsOnTheHourOwnReadingWhenItHasOne() {
        // Hour 9's reading is isolated (no pair), so its placeholder collapses
        // onto the reading itself — a segment appearing there on another day
        // grows out of the dot rather than a borrowed midpoint.
        let full = [
            dayEntry(hour: 1, value: 60), dayEntry(hour: 2, value: 70),
            dayEntry(hour: 9, value: 80)
        ]
        let segments = BodyHealthMetricDayChart.makeLineSegments(
            from: full,
            dayStart: Self.placeholderDayStart
        )
        let hourNine = segments.first { $0.hourIndex == 9 }

        XCTAssertEqual(hourNine?.isPlaceholder, true)
        XCTAssertEqual(hourNine?.startValue, 80)
        XCTAssertEqual(hourNine?.startPlotDate, full[2].plotDate)
        XCTAssertEqual(hourNine?.endPlotDate, full[2].plotDate)
    }

    // MARK: - A configured source that is silent today (fade out, not pop)

    /// Primary readings a silent secondary can borrow: hour 2 reads 10, hour
    /// 20 reads 30, so hour 3 borrows 10, hour 19 borrows 30, and hour 11 (nine
    /// hours from both) borrows the earlier one.
    private var anchoringPrimaryEntries: [BodyHealthMetricDayChartEntry] {
        [dayEntry(hour: 2, value: 10), dayEntry(hour: 20, value: 30)]
    }

    func testMakeLineSegmentsFillsAConfiguredSourceWithNoDataFromTheOtherSource() {
        let segments = BodyHealthMetricDayChart.makeLineSegments(
            from: anchoringPrimaryEntries,
            dayStart: Self.placeholderDayStart,
            configuredRoles: [.primary, .secondary]
        )
        let secondary = segments.filter { $0.sourceRole == .secondary }
        let valueByHour = Dictionary(uniqueKeysWithValues: secondary.map { ($0.hourIndex, $0.startValue) })

        // Every hour keeps a secondary mark, so the line drawn on the previous
        // day animates to opacity 0 instead of freezing then popping.
        XCTAssertEqual(secondary.count, 24)
        XCTAssertTrue(secondary.allSatisfy(\.isPlaceholder))
        XCTAssertTrue(secondary.allSatisfy { $0.startPlotDate == $0.endPlotDate })
        XCTAssertTrue(secondary.allSatisfy { $0.startValue == $0.endValue })
        XCTAssertEqual(Set(secondary.map(\.id)).count, 24)
        XCTAssertEqual(valueByHour[3], 10)
        XCTAssertEqual(valueByHour[19], 30)
        XCTAssertEqual(valueByHour[11], 10)
    }

    func testAddingPlaceholderDotsFillsAConfiguredSourceWithNoDataFromTheOtherSource() {
        let real = anchoringPrimaryEntries
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: real,
            fullEntries: real,
            dayStart: Self.placeholderDayStart,
            configuredRoles: [.primary, .secondary]
        )
        let secondary = filled.filter { $0.sourceRole == .secondary }
        let valueByHour = Dictionary(uniqueKeysWithValues: secondary.map { (hourIndex(of: $0), $0.averageValue) })

        XCTAssertEqual(filled.count, 48)
        XCTAssertEqual(secondary.count, 24)
        XCTAssertTrue(secondary.allSatisfy(\.isPlaceholder))
        XCTAssertTrue(secondary.allSatisfy { $0.id.hasPrefix("secondary-") })
        XCTAssertEqual(Set(secondary.map(\.id)).count, 24)
        XCTAssertEqual(valueByHour[3], 10)
        XCTAssertEqual(valueByHour[19], 30)
        XCTAssertEqual(valueByHour[11], 10)
    }

    func testSingleSourceDayAddsNoSecondaryMarks() {
        let real = anchoringPrimaryEntries
        let segments = BodyHealthMetricDayChart.makeLineSegments(
            from: real,
            dayStart: Self.placeholderDayStart
        )
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: real,
            fullEntries: real,
            dayStart: Self.placeholderDayStart
        )

        XCTAssertTrue(segments.allSatisfy { $0.sourceRole == .primary })
        XCTAssertTrue(filled.allSatisfy { $0.sourceRole == .primary })
        XCTAssertEqual(segments.count, 24)
        XCTAssertEqual(filled.count, 24)
    }

    func testConfiguredSourcesWithNoFiniteDataAnywhereAddNoMarks() {
        XCTAssertTrue(
            BodyHealthMetricDayChart.makeLineSegments(
                from: [],
                dayStart: Self.placeholderDayStart,
                configuredRoles: [.primary, .secondary]
            ).isEmpty
        )
        XCTAssertTrue(
            BodyHealthMetricDayChart.addingPlaceholderDots(
                to: [],
                fullEntries: [],
                dayStart: Self.placeholderDayStart,
                configuredRoles: [.primary, .secondary]
            ).isEmpty
        )

        // Readings exist but none of them plot, so there is still no value for
        // a placeholder to sit on.
        let nonfinite = [
            dayEntry(hour: 2, value: .nan),
            dayEntry(hour: 6, value: .infinity, role: .secondary)
        ]
        XCTAssertTrue(
            BodyHealthMetricDayChart.makeLineSegments(
                from: nonfinite,
                dayStart: Self.placeholderDayStart,
                configuredRoles: [.primary, .secondary]
            ).isEmpty
        )
        XCTAssertEqual(
            BodyHealthMetricDayChart.addingPlaceholderDots(
                to: nonfinite,
                fullEntries: nonfinite,
                dayStart: Self.placeholderDayStart,
                configuredRoles: [.primary, .secondary]
            ).map(\.id),
            nonfinite.map(\.id)
        )
    }

    func testASilentPrimaryBorrowsTheSecondarySourcesReadings() {
        // The anchoring works either way round: the drawn source is the one
        // with data, whichever role it holds.
        let secondaryOnly = [
            dayEntry(hour: 4, value: 55, role: .secondary),
            dayEntry(hour: 5, value: 65, role: .secondary)
        ]
        let segments = BodyHealthMetricDayChart.makeLineSegments(
            from: secondaryOnly,
            dayStart: Self.placeholderDayStart,
            configuredRoles: [.primary, .secondary]
        )
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: secondaryOnly,
            fullEntries: secondaryOnly,
            dayStart: Self.placeholderDayStart,
            configuredRoles: [.primary, .secondary]
        )
        let primarySegments = segments.filter { $0.sourceRole == .primary }
        let primaryDots = filled.filter { $0.sourceRole == .primary }

        XCTAssertEqual(primarySegments.count, 24)
        XCTAssertTrue(primarySegments.allSatisfy(\.isPlaceholder))
        XCTAssertEqual(primarySegments.first { $0.hourIndex == 0 }?.startValue, 55)
        XCTAssertEqual(primarySegments.first { $0.hourIndex == 23 }?.startValue, 65)
        XCTAssertEqual(primaryDots.count, 24)
        XCTAssertTrue(primaryDots.allSatisfy(\.isPlaceholder))
        XCTAssertEqual(primaryDots.first { hourIndex(of: $0) == 12 }?.averageValue, 65)
    }

    func testPlaceholderCountFollowsADaylightSavingDaysHourCount() throws {
        // The other tests key off `placeholderDayStart`, a local midnight, so
        // resolve it under the ambient time zone before swapping in one that
        // has a transition.
        _ = Self.placeholderDayStart
        let originalTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        addTeardownBlock { NSTimeZone.default = originalTimeZone }

        // March 10 2024 springs forward in New York: a 23-hour day.
        let calendar = Calendar.bodyGregorian
        let noon = try XCTUnwrap(
            DateComponents(calendar: calendar, year: 2024, month: 3, day: 10, hour: 12).date
        )
        let dayStart = calendar.startOfDay(for: noon)
        let real = [
            dayEntry(hour: 1, value: 60, dayStart: dayStart),
            dayEntry(hour: 3, value: 70, dayStart: dayStart)
        ]
        let segments = BodyHealthMetricDayChart.makeLineSegments(from: real, dayStart: dayStart)
        let filled = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: real,
            fullEntries: real,
            dayStart: dayStart
        )
        let secondaryFill = BodyHealthMetricDayChart.addingPlaceholderDots(
            to: real,
            fullEntries: real,
            dayStart: dayStart,
            configuredRoles: [.primary, .secondary]
        )

        XCTAssertEqual(segments.count, 23)
        XCTAssertEqual(Set(segments.map(\.id)).count, 23)
        XCTAssertEqual(filled.count, 23)
        XCTAssertEqual(Set(filled.map(\.id)).count, 23)
        XCTAssertEqual(secondaryFill.filter { $0.sourceRole == .secondary }.count, 23)
    }
}
