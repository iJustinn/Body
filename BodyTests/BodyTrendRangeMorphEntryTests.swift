//
//  BodyTrendRangeMorphEntryTests.swift
//  BodyTests
//
//  Covers the Week/Month/6M/Year chart's range-morph union: every range's
//  calendar points merge into one mark set, with off-range dates carried as
//  invisible placeholders so a range switch morphs marks in place instead of
//  replacing them.
//

import XCTest
@testable import Body

final class BodyTrendRangeMorphEntryTests: XCTestCase {
    /// Fixed "today" (a real local midnight) so the calendar-point functions
    /// never touch `Date()`.
    private static let today = Calendar.bodyGregorian.startOfDay(
        for: Date(timeIntervalSinceReferenceDate: 500 * 86_400)
    )
    /// Day offset with no sample — a current-range gap day.
    private static let gapDayOffset = 2

    private static func dayStart(_ offset: Int) -> Date {
        Calendar.bodyGregorian.date(byAdding: .day, value: -offset, to: today) ?? today
    }

    /// 400 days of noon samples (values 60...69 repeating by day offset),
    /// minus the gap day — enough history for every range's buckets.
    private static let series = HealthTrendSeries(
        points: (0..<400).compactMap { offset -> HealthTrendDataPoint? in
            guard offset != gapDayOffset,
                  let date = Calendar.bodyGregorian.date(
                      byAdding: DateComponents(day: -offset, hour: 12),
                      to: today
                  ) else {
                return nil
            }
            return HealthTrendDataPoint(date: date, value: 60 + Double(offset % 10))
        }
        .sorted { $0.date < $1.date }
    )

    private static let pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]] = Dictionary(
        uniqueKeysWithValues: BodyHealthTrendRange.allCases.map { range in
            (range, series.chartCalendarPoints(to: range, date: today))
        }
    )

    // MARK: - Union entries

    func testUnionHasOneEntryPerDateWithCurrentRangePriority() {
        let entries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: .recentWeek,
            pointsByRange: Self.pointsByRange
        )
        let entriesByDate = Dictionary(
            entries.map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // One entry per distinct date, covering every range's dates.
        XCTAssertEqual(entries.count, entriesByDate.count)
        XCTAssertEqual(
            Set(entries.map(\.date)),
            Set(BodyHealthTrendRange.allCases.flatMap { range in
                Self.pointsByRange[range]!.map(\.date)
            })
        )

        // Selected-range dates win the merge and are never placeholders.
        for point in Self.pointsByRange[.recentWeek]! {
            let entry = entriesByDate[point.date]
            XCTAssertEqual(entry?.isPlaceholder, false)
            XCTAssertEqual(entry?.value, point.value)
        }
    }

    func testPlaceholderEntriesCarryTheirOwningRangeValue() {
        let entries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: .recentWeek,
            pointsByRange: Self.pointsByRange
        )

        // 20 days back exists only in Month (not Week, not a 6M/Year bucket
        // end), so Month owns the placeholder.
        let monthOnlyDate = Self.dayStart(20)
        let monthEntry = entries.first { $0.date == monthOnlyDate }
        XCTAssertEqual(monthEntry?.isPlaceholder, true)
        XCTAssertEqual(
            monthEntry?.value,
            Self.pointsByRange[.recentMonth]!.first { $0.date == monthOnlyDate }?.value
        )

        // 36 days back ends both a 6M and a Year bucket with different
        // averages — the fixed Week → Month → 6M → Year order is observable.
        let bucketDate = Self.dayStart(36)
        let sixMonthValue = Self.pointsByRange[.recentSixMonths]!.first { $0.date == bucketDate }?.value
        let yearValue = Self.pointsByRange[.recentYear]!.first { $0.date == bucketDate }?.value
        XCTAssertNotNil(sixMonthValue)
        XCTAssertNotNil(yearValue)
        XCTAssertNotEqual(sixMonthValue, yearValue)

        let bucketEntry = entries.first { $0.date == bucketDate }
        XCTAssertEqual(bucketEntry?.isPlaceholder, true)
        XCTAssertEqual(bucketEntry?.value, sixMonthValue)
    }

    func testCurrentRangeGapDaysKeepNilValueAndAreNotPlaceholders() {
        let entries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: .recentWeek,
            pointsByRange: Self.pointsByRange
        )
        let gapEntry = entries.first { $0.date == Self.dayStart(Self.gapDayOffset) }

        XCTAssertNotNil(gapEntry)
        XCTAssertNil(gapEntry?.value)
        XCTAssertEqual(gapEntry?.isPlaceholder, false)
    }

    func testEmptySelectedRangeDayBorrowsOffRangeDotGeometry() throws {
        // A day the selected range has no reading for, which a longer range
        // already aggregates — today, before the day's data is complete.
        let pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]] = [
            .recentWeek: [HealthTrendCalendarPoint(date: Self.today, value: nil)],
            .recentMonth: [],
            .recentSixMonths: [HealthTrendCalendarPoint(date: Self.today, value: 64)],
            .recentYear: [HealthTrendCalendarPoint(date: Self.today, value: 70)]
        ]

        let entries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: .recentWeek,
            pointsByRange: pointsByRange
        )
        let entry = try XCTUnwrap(entries.first { $0.date == Self.today })

        // The day keeps its own (empty) slot, so bar style still draws its gray
        // no-data bar...
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entry.value)
        XCTAssertFalse(entry.isPlaceholder)
        // ...while line style gets an invisible dot at the 6M value (first in
        // `allCases` order), which then fades in on a switch to 6M rather than
        // being inserted.
        XCTAssertEqual(entry.offRangeValue, 64)
        XCTAssertEqual(entry.dotValue, 64)
        XCTAssertFalse(entry.showsDot)
    }

    func testValuedSelectedRangeDayNeverBorrowsAnotherRangeValue() throws {
        let entries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: .recentWeek,
            pointsByRange: Self.pointsByRange
        )
        let entry = try XCTUnwrap(entries.first { $0.date == Self.today })

        XCTAssertNotNil(entry.value)
        XCTAssertNil(entry.offRangeValue)
        XCTAssertEqual(entry.dotValue, entry.value)
        XCTAssertTrue(entry.showsDot)
        // Off-range placeholders draw no dot either, at their own value.
        let placeholder = try XCTUnwrap(entries.first { $0.isPlaceholder })
        XCTAssertFalse(placeholder.showsDot)
        XCTAssertEqual(placeholder.dotValue, placeholder.value)
    }

    func testTodayDateAnchorsEveryRange() {
        for range in BodyHealthTrendRange.allCases {
            // Aggregated buckets are keyed by bucket END date, so today ends
            // every range's newest mark and all four share that identity.
            XCTAssertTrue(Self.pointsByRange[range]!.contains { $0.date == Self.today })

            let entries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
                selectedRange: range,
                pointsByRange: Self.pointsByRange
            )
            XCTAssertEqual(entries.first { $0.date == Self.today }?.isPlaceholder, false)
        }
    }

    // MARK: - Line segments

    func testSegmentsPairConsecutiveFinitePointsWithStartDateIds() {
        let segments = BodyHealthMetricTrendChart.makeTrendLineSegments(
            selectedRange: .recentWeek,
            pointsByRange: Self.pointsByRange
        )
        let real = segments.filter { !$0.isPlaceholder }
        let finite = Self.pointsByRange[.recentWeek]!.filter { $0.value?.isFinite == true }

        XCTAssertEqual(real.count, finite.count - 1)
        for (index, segment) in real.enumerated() {
            XCTAssertEqual(segment.startDate, finite[index].date)
            XCTAssertEqual(segment.endDate, finite[index + 1].date)
            XCTAssertEqual(segment.startValue, finite[index].value)
            XCTAssertEqual(segment.endValue, finite[index + 1].value)
            XCTAssertEqual(segment.id, "seg-\(segment.startDate.timeIntervalSinceReferenceDate)")
        }

        // The pair around the gap day connects across it, like the drawn line.
        XCTAssertTrue(real.contains {
            $0.startDate == Self.dayStart(Self.gapDayOffset + 1)
                && $0.endDate == Self.dayStart(Self.gapDayOffset - 1)
        })
    }

    func testPlaceholderSegmentsAreZeroLengthAndFlagged() {
        let segments = BodyHealthMetricTrendChart.makeTrendLineSegments(
            selectedRange: .recentWeek,
            pointsByRange: Self.pointsByRange
        )

        // 13 days back starts a pair only in Month, so its segment id has no
        // selected-range counterpart and must collapse in place.
        let monthOnlyDate = Self.dayStart(13)
        let placeholder = segments.first { $0.startDate == monthOnlyDate }
        let owningValue = Self.pointsByRange[.recentMonth]!.first { $0.date == monthOnlyDate }?.value

        XCTAssertNotNil(owningValue)
        XCTAssertEqual(placeholder?.isPlaceholder, true)
        XCTAssertEqual(placeholder?.endDate, monthOnlyDate)
        XCTAssertEqual(placeholder?.startValue, owningValue)
        XCTAssertEqual(placeholder?.endValue, owningValue)
    }
}
