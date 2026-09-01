//
//  BodyHeartRateRangeMorphTests.swift
//  BodyTests
//
//  Covers the heart-rate-style range chart's range-switch morphing rule: the
//  chart renders the union of ALL ranges' bucket dates permanently — the
//  current range's marks verbatim, every other range's as invisible
//  placeholders carrying their own range's geometry — so a Week/Month/6M/Year
//  switch animates opacity and positions instead of inserting/removing marks
//  (which Swift Charts pops). The average line is split into one two-point
//  series per ADJACENT-average pair with a stable role + start-date id;
//  unmatched pairs collapse to zero-length placeholders at their own start,
//  and a bucket with no average breaks the line rather than being spanned.
//

import Foundation
import XCTest
@testable import Body

final class BodyHeartRateRangeMorphTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func date(day: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(day) * 86_400)
    }

    private func rangePoint(day: Int, low: Double?, high: Double?) -> HealthTrendRangeCalendarPoint {
        HealthTrendRangeCalendarPoint(
            date: date(day: day),
            lowValue: low,
            highValue: high,
            averageValue: nil
        )
    }

    private func averageEntry(
        role: BodyHealthSourceRole = .primary,
        day: Int,
        value: Double
    ) -> BodyHeartRateRangeAverageEntry {
        BodyHeartRateRangeAverageEntry(
            sourceName: role == .primary ? "Primary" : "Secondary",
            sourceRole: role,
            date: date(day: day),
            value: value
        )
    }

    // MARK: - Union bars

    func testUnionBarEntriesKeepCurrentGeometryOnSharedDatesAndOwnGeometryOnPlaceholders() {
        let current = [rangePoint(day: 0, low: 50, high: 90)]
        let other = [
            [rangePoint(day: 0, low: 10, high: 20), rangePoint(day: 1, low: 30, high: 40)],
            [rangePoint(day: 1, low: 70, high: 80), rangePoint(day: 2, low: 55, high: 65)]
        ]

        let entries = BodyHeartRateRangeTrendChart.unionBarEntries(
            currentPoints: current,
            otherRangePoints: other
        )

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        // Day 0: the current range's geometry wins, visibly.
        XCTAssertEqual(entries[0].point.lowValue, 50)
        XCTAssertFalse(entries[0].isPlaceholder)
        // Day 1: the first other range claims the date, with its own geometry.
        XCTAssertEqual(entries[1].point.lowValue, 30)
        XCTAssertTrue(entries[1].isPlaceholder)
        XCTAssertEqual(entries[2].point.lowValue, 55)
        XCTAssertTrue(entries[2].isPlaceholder)
    }

    func testUnionBarEntriesKeepValuelessCurrentDatesButSkipValuelessOffRangeDates() {
        let current = [rangePoint(day: 0, low: 50, high: 90), rangePoint(day: 1, low: nil, high: nil)]
        let other = [[rangePoint(day: 2, low: nil, high: nil)]]

        let entries = BodyHeartRateRangeTrendChart.unionBarEntries(
            currentPoints: current,
            otherRangePoints: other
        )

        // A valueless current-range date still renders (nothing) exactly as
        // today; a valueless off-range date has no geometry to fade through.
        XCTAssertEqual(entries.map(\.point.date), [date(day: 0), date(day: 1)])
        XCTAssertEqual(entries.map(\.isPlaceholder), [false, false])
    }

    func testEmptyCurrentDateYieldsItsSlotToAValuedOffRangeBucket() {
        let current = [rangePoint(day: 0, low: 50, high: 90), rangePoint(day: 1, low: nil, high: nil)]
        let other = [[rangePoint(day: 1, low: 30, high: 40)]]

        let entries = BodyHeartRateRangeTrendChart.unionBarEntries(
            currentPoints: current,
            otherRangePoints: other
        )

        // Day 1 draws nothing in the current range — a common case for today's
        // still-incomplete data, which a longer range already aggregates. The
        // valued off-range bucket takes that slot and waits there invisibly, so
        // selecting its range morphs the bar in instead of popping it.
        XCTAssertEqual(entries.map(\.point.date), [date(day: 0), date(day: 1)])
        XCTAssertEqual(entries.map(\.isPlaceholder), [false, true])
        XCTAssertEqual(entries[1].point.lowValue, 30)
        XCTAssertEqual(entries[1].point.highValue, 40)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
    }

    /// End-to-end over real calendar-point aggregation (fixed `date:`, no
    /// `Date()`): the union covers every range's valued bucket dates exactly
    /// once, flagging exactly the off-range dates as placeholders.
    func testUnionBarEntriesCoverEveryRangeDateOnceFromAggregatedSeries() throws {
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 5)))
        let todayStart = calendar.startOfDay(for: today)
        let dayCount = BodyHealthTrendRange.maximumDayCount
        let series = HealthTrendRangeSeries(
            points: (0..<dayCount).map { offset in
                HealthTrendRangeDataPoint(
                    date: calendar.date(byAdding: .day, value: -(dayCount - 1) + offset, to: todayStart)!,
                    lowValue: 50 + Double(offset % 10),
                    highValue: 100 + Double(offset % 10),
                    averageValue: 70
                )
            }
        )
        let selectedRange = BodyHealthTrendRange.recentWeek
        let currentPoints = series.chartCalendarPoints(to: selectedRange, calendar: calendar, date: today)
        let otherPoints = BodyHealthTrendRange.allCases
            .filter { $0 != selectedRange }
            .map { series.chartCalendarPoints(to: $0, calendar: calendar, date: today) }

        let entries = BodyHeartRateRangeTrendChart.unionBarEntries(
            currentPoints: currentPoints,
            otherRangePoints: otherPoints
        )

        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        let currentDates = Set(currentPoints.map(\.date))
        let expectedDates = currentDates.union(
            otherPoints.flatMap { $0.filter(\.hasValue).map(\.date) }
        )
        XCTAssertEqual(Set(entries.map(\.point.date)), expectedDates)
        for entry in entries {
            XCTAssertEqual(entry.isPlaceholder, !currentDates.contains(entry.point.date))
        }
        // Placeholders carry their own range's aggregated geometry, verbatim.
        let otherPointsFlat = otherPoints.flatMap { $0 }
        for entry in entries where entry.isPlaceholder {
            XCTAssertTrue(otherPointsFlat.contains(entry.point))
        }
    }

    // MARK: - Average-line segments

    func testAverageLineSegmentsPairConsecutiveEntriesPerSourceWithStableIds() {
        let entries = [
            averageEntry(day: 0, value: 60),
            averageEntry(day: 1, value: 70),
            averageEntry(day: 2, value: 65),
            averageEntry(role: .secondary, day: 0, value: 55),
            averageEntry(role: .secondary, day: 1, value: 58)
        ]

        let segments = BodyHeartRateRangeTrendChart.averageLineSegments(from: entries, isPlaceholder: false)

        XCTAssertEqual(segments.map(\.id), [
            "primary-seg-\(date(day: 0).timeIntervalSinceReferenceDate)",
            "primary-seg-\(date(day: 1).timeIntervalSinceReferenceDate)",
            "secondary-seg-\(date(day: 0).timeIntervalSinceReferenceDate)"
        ])
        XCTAssertEqual(segments.map(\.startValue), [60, 70, 55])
        XCTAssertEqual(segments.map(\.endValue), [70, 65, 58])
        XCTAssertTrue(segments.allSatisfy { !$0.isPlaceholder })
    }

    func testAverageLineSegmentsBreakAtABucketWithNoAverage() {
        // Day 2 has no average, so it never becomes an entry: the line runs
        // day 0 → day 1 and stops rather than striding over the missing day.
        let segments = BodyHeartRateRangeTrendChart.averageLineSegments(
            from: [
                averageEntry(day: 0, value: 60),
                averageEntry(day: 1, value: 70),
                averageEntry(day: 3, value: 65)
            ],
            isPlaceholder: false
        )

        XCTAssertEqual(segments.map(\.startDate), [date(day: 0)])
        XCTAssertEqual(segments.map(\.endDate), [date(day: 1)])
    }

    func testAverageLineSegmentsJoinBucketsWhoseSpansTouch() {
        // 6M/Year buckets cover several days each: neighbours still connect,
        // and a skipped bucket still breaks the line.
        func bucketEntry(startDay: Int, endDay: Int, value: Double) -> BodyHeartRateRangeAverageEntry {
            BodyHeartRateRangeAverageEntry(
                sourceName: "Primary",
                sourceRole: .primary,
                date: date(day: endDay),
                value: value,
                spanStartDate: date(day: startDay),
                spanEndDate: date(day: endDay)
            )
        }

        let segments = BodyHeartRateRangeTrendChart.averageLineSegments(
            from: [
                bucketEntry(startDay: 0, endDay: 5, value: 60),
                bucketEntry(startDay: 6, endDay: 11, value: 62),
                bucketEntry(startDay: 18, endDay: 23, value: 64)
            ],
            isPlaceholder: false
        )

        XCTAssertEqual(segments.map(\.startDate), [date(day: 5)])
        XCTAssertEqual(segments.map(\.endDate), [date(day: 11)])
    }

    func testAverageLineSegmentsLeaveASinglePointSourceWithoutPairs() {
        let segments = BodyHeartRateRangeTrendChart.averageLineSegments(
            from: [averageEntry(day: 0, value: 60)],
            isPlaceholder: false
        )

        XCTAssertTrue(segments.isEmpty)
    }

    func testUnionAverageLineSegmentsCollapseUnmatchedPairsToTheirOwnStart() {
        let current = [averageEntry(day: 0, value: 60), averageEntry(day: 1, value: 70)]
        let other = [[
            averageEntry(day: 0, value: 100),
            averageEntry(day: 1, value: 110),
            averageEntry(day: 2, value: 120)
        ]]

        let segments = BodyHeartRateRangeTrendChart.unionAverageLineSegments(
            currentEntries: current,
            otherRangeEntries: other
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(Set(segments.map(\.id)).count, segments.count)
        // Day 0's pair id exists in both: the current range's geometry wins.
        XCTAssertFalse(segments[0].isPlaceholder)
        XCTAssertEqual(segments[0].endValue, 70)
        // Day 1's pair only exists off-range: zero-length at its own start.
        XCTAssertTrue(segments[1].isPlaceholder)
        XCTAssertEqual(segments[1].startDate, date(day: 1))
        XCTAssertEqual(segments[1].endDate, date(day: 1))
        XCTAssertEqual(segments[1].startValue, 110)
        XCTAssertEqual(segments[1].endValue, 110)
    }

    // MARK: - Union average dots

    func testUnionAverageDotEntriesAddOffRangeDotsAsPlaceholdersAtTheirOwnValue() {
        let current = [averageEntry(day: 0, value: 60)]
        let other = [
            [averageEntry(day: 0, value: 100), averageEntry(day: 1, value: 110)],
            [averageEntry(day: 1, value: 200), averageEntry(role: .secondary, day: 0, value: 55)]
        ]

        let entries = BodyHeartRateRangeTrendChart.unionAverageDotEntries(
            currentEntries: current,
            otherRangeEntries: other
        )

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
        // The current range's dot stays visible at its own value.
        XCTAssertEqual(entries[0].value, 60)
        XCTAssertFalse(entries[0].isPlaceholder)
        // Day 1: the first other range claims the id, at its own value.
        XCTAssertEqual(entries[1].value, 110)
        XCTAssertTrue(entries[1].isPlaceholder)
        // Same date, other source role: a distinct id, kept as a placeholder.
        XCTAssertEqual(entries[2].sourceRole, .secondary)
        XCTAssertEqual(entries[2].value, 55)
        XCTAssertTrue(entries[2].isPlaceholder)
    }
}
