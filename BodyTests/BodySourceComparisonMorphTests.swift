//
//  BodySourceComparisonMorphTests.swift
//  BodyTests
//
//  Covers the union-entry rule behind the source-comparison charts' range-switch
//  morph: every range's paired buckets stay resident, off-range ones as
//  invisible placeholders at their own range's aggregation and pair offsets, so
//  a switch animates opacity and position instead of inserting/removing marks.
//

import XCTest
@testable import Body

final class BodySourceComparisonMorphTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    /// Fixed anchor so bucket dates never depend on the wall clock.
    private let anchorDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func dailySeries(dayCount: Int = 400, offset: Double) -> HealthTrendSeries {
        let dayStart = calendar.startOfDay(for: anchorDate)
        let points = (0..<dayCount).compactMap { dayOffset -> HealthTrendDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: dayStart) else {
                return nil
            }
            return HealthTrendDataPoint(date: date, value: offset + Double(dayOffset % 17))
        }
        return HealthTrendSeries(points: points)
    }

    private func dailyRangeSeries(dayCount: Int = 400, offset: Double) -> HealthTrendRangeSeries {
        let dayStart = calendar.startOfDay(for: anchorDate)
        let points = (0..<dayCount).compactMap { dayOffset -> HealthTrendRangeDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: dayStart) else {
                return nil
            }
            let low = offset + Double(dayOffset % 11)
            return HealthTrendRangeDataPoint(date: date, lowValue: low, highValue: low + 20, averageValue: low + 8)
        }
        return HealthTrendRangeSeries(points: points)
    }

    private var barComparison: BodyHealthSourceComparisonTrend {
        BodyHealthSourceComparisonTrend(
            primary: BodyHealthSourceTrend(role: .primary, sourceName: "Watch", series: dailySeries(offset: 100)),
            secondary: BodyHealthSourceTrend(role: .secondary, sourceName: "Ring", series: dailySeries(offset: 200))
        )
    }

    private var rangeComparison: BodyHealthSourceRangeComparisonTrend {
        BodyHealthSourceRangeComparisonTrend(
            primary: BodyHealthSourceRangeTrend(role: .primary, sourceName: "Watch", series: dailyRangeSeries(offset: 50)),
            secondary: BodyHealthSourceRangeTrend(role: .secondary, sourceName: "Ring", series: dailyRangeSeries(offset: 70))
        )
    }

    private func otherRanges(than selected: BodyHealthTrendRange) -> [BodyHealthTrendRange] {
        BodyHealthTrendRange.allCases.filter { $0 != selected }
    }

    // MARK: - Paired bar chart

    func testUnionBarEntriesKeepEveryRangeBucketExactlyOnce() {
        let comparison = barComparison
        let current = BodyHealthSourceComparisonBarChart.barEntries(
            comparison: comparison,
            range: .recentWeek,
            calendar: calendar,
            date: anchorDate
        )
        let others = otherRanges(than: .recentWeek).map {
            BodyHealthSourceComparisonBarChart.barEntries(
                comparison: comparison,
                range: $0,
                calendar: calendar,
                date: anchorDate
            )
        }
        let union = BodyHealthSourceComparisonBarChart.unionBarEntries(
            currentEntries: current,
            otherRangeEntries: others
        )

        XCTAssertEqual(Set(union.map(\.id)).count, union.count)
        // Every current entry survives, unflagged and ahead of the placeholders.
        XCTAssertEqual(Array(union.prefix(current.count)).map(\.id), current.map(\.id))
        XCTAssertTrue(union.prefix(current.count).allSatisfy { !$0.isPlaceholder })
        XCTAssertTrue(union.dropFirst(current.count).allSatisfy(\.isPlaceholder))
        // Each other range contributes its own valued buckets.
        for rangeEntries in others {
            for entry in rangeEntries where entry.value?.isFinite == true {
                XCTAssertTrue(union.contains { $0.id == entry.id }, "missing \(entry.id)")
            }
        }
    }

    func testUnionBarPlaceholdersKeepTheirOwnRangeGeometry() {
        let comparison = barComparison
        let current = BodyHealthSourceComparisonBarChart.barEntries(
            comparison: comparison,
            range: .recentWeek,
            calendar: calendar,
            date: anchorDate
        )
        let yearEntries = BodyHealthSourceComparisonBarChart.barEntries(
            comparison: comparison,
            range: .recentYear,
            calendar: calendar,
            date: anchorDate
        )
        let union = BodyHealthSourceComparisonBarChart.unionBarEntries(
            currentEntries: current,
            otherRangeEntries: [yearEntries]
        )
        // A Year bucket the Week never shows keeps that bucket's own aggregated
        // value and its own pair-offset x, so it fades in where it belongs.
        let currentIDs = Set(current.map(\.id))
        let yearOnly = try? XCTUnwrap(yearEntries.first { !currentIDs.contains($0.id) && $0.value?.isFinite == true })
        let placeholder = union.first { $0.id == yearOnly?.id }

        XCTAssertNotNil(yearOnly)
        XCTAssertEqual(placeholder?.isPlaceholder, true)
        XCTAssertEqual(placeholder?.value, yearOnly?.value)
        XCTAssertEqual(placeholder?.chartDate, yearOnly?.chartDate)
    }

    func testUnionBarEntriesPreferTheCurrentRangeOnSharedIDs() {
        let comparison = barComparison
        let month = BodyHealthSourceComparisonBarChart.barEntries(
            comparison: comparison,
            range: .recentMonth,
            calendar: calendar,
            date: anchorDate
        )
        let week = BodyHealthSourceComparisonBarChart.barEntries(
            comparison: comparison,
            range: .recentWeek,
            calendar: calendar,
            date: anchorDate
        )
        let union = BodyHealthSourceComparisonBarChart.unionBarEntries(
            currentEntries: month,
            otherRangeEntries: [week]
        )
        let sharedID = try? XCTUnwrap(Set(month.map(\.id)).intersection(week.map(\.id)).first)
        let resolved = union.filter { $0.id == sharedID }

        XCTAssertNotNil(sharedID)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.isPlaceholder, false)
        XCTAssertEqual(resolved.first?.chartDate, month.first { $0.id == sharedID }?.chartDate)
    }

    // MARK: - Paired min-max range chart

    func testUnionRangeEntriesKeepEveryRangeBucketExactlyOnce() {
        let comparison = rangeComparison
        let current = BodyHealthSourceComparisonRangeChart.rangeEntries(
            comparison: comparison,
            range: .recentMonth,
            calendar: calendar,
            date: anchorDate
        )
        let others = otherRanges(than: .recentMonth).map {
            BodyHealthSourceComparisonRangeChart.rangeEntries(
                comparison: comparison,
                range: $0,
                calendar: calendar,
                date: anchorDate
            )
        }
        let union = BodyHealthSourceComparisonRangeChart.unionRangeEntries(
            currentEntries: current,
            otherRangeEntries: others
        )

        XCTAssertEqual(Set(union.map(\.id)).count, union.count)
        XCTAssertEqual(Array(union.prefix(current.count)).map(\.id), current.map(\.id))
        XCTAssertTrue(union.dropFirst(current.count).allSatisfy(\.isPlaceholder))
        XCTAssertTrue(union.dropFirst(current.count).allSatisfy(\.hasValue))
    }

    func testUnionRangePlaceholdersKeepTheirOwnLowHighAndPairOffset() {
        let comparison = rangeComparison
        let current = BodyHealthSourceComparisonRangeChart.rangeEntries(
            comparison: comparison,
            range: .recentWeek,
            calendar: calendar,
            date: anchorDate
        )
        let sixMonths = BodyHealthSourceComparisonRangeChart.rangeEntries(
            comparison: comparison,
            range: .recentSixMonths,
            calendar: calendar,
            date: anchorDate
        )
        let union = BodyHealthSourceComparisonRangeChart.unionRangeEntries(
            currentEntries: current,
            otherRangeEntries: [sixMonths]
        )
        let currentIDs = Set(current.map(\.id))
        let sixMonthOnly = try? XCTUnwrap(sixMonths.first { !currentIDs.contains($0.id) && $0.hasValue })
        let placeholder = union.first { $0.id == sixMonthOnly?.id }

        XCTAssertNotNil(sixMonthOnly)
        XCTAssertEqual(placeholder?.isPlaceholder, true)
        XCTAssertEqual(placeholder?.lowValue, sixMonthOnly?.lowValue)
        XCTAssertEqual(placeholder?.highValue, sixMonthOnly?.highValue)
        XCTAssertEqual(placeholder?.chartDate, sixMonthOnly?.chartDate)
    }

    // MARK: - Empty current slots

    /// An entry with no reading draws nothing in any of the three charts, so it
    /// must not hold its id against another range's valued entry: the valued
    /// one takes the slot invisibly and morphs in when its range is selected.
    func testEmptyCurrentEntriesYieldTheirSlotToValuedOffRangeEntries() {
        let day = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let empty = HealthTrendCalendarPoint(date: day, value: nil)
        let valued = HealthTrendCalendarPoint(date: day, value: 42)

        let dots = BodyHealthSourceComparisonLineChart.unionDotEntries(
            currentEntries: [
                BodyHealthSourceComparisonLineEntry(sourceName: "Watch", sourceRole: .primary, point: empty)
            ],
            otherRangeEntries: [[
                BodyHealthSourceComparisonLineEntry(sourceName: "Watch", sourceRole: .primary, point: valued)
            ]]
        )
        XCTAssertEqual(dots.count, 1)
        XCTAssertEqual(dots.first?.value, 42)
        XCTAssertEqual(dots.first?.isPlaceholder, true)

        let bars = BodyHealthSourceComparisonBarChart.unionBarEntries(
            currentEntries: [
                BodyHealthSourceComparisonBarEntry(sourceName: "Watch", sourceRole: .primary, point: empty, chartDate: day)
            ],
            otherRangeEntries: [[
                BodyHealthSourceComparisonBarEntry(sourceName: "Watch", sourceRole: .primary, point: valued, chartDate: day)
            ]]
        )
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(bars.first?.value, 42)
        XCTAssertEqual(bars.first?.isPlaceholder, true)

        let emptyBucket = HealthTrendRangeCalendarPoint(date: day, lowValue: nil, highValue: nil, averageValue: nil)
        let valuedBucket = HealthTrendRangeCalendarPoint(date: day, lowValue: 40, highValue: 60, averageValue: 50)
        let ranges = BodyHealthSourceComparisonRangeChart.unionRangeEntries(
            currentEntries: [
                BodyHealthSourceComparisonRangeEntry(sourceName: "Watch", sourceRole: .primary, point: emptyBucket, chartDate: day)
            ],
            otherRangeEntries: [[
                BodyHealthSourceComparisonRangeEntry(sourceName: "Watch", sourceRole: .primary, point: valuedBucket, chartDate: day)
            ]]
        )
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges.first?.lowValue, 40)
        XCTAssertEqual(ranges.first?.isPlaceholder, true)
    }

    func testLineSegmentsBreakAtADayASourceNeverRecorded() {
        let dayStart = calendar.startOfDay(for: anchorDate)
        func entry(dayOffset: Int, value: Double?) -> BodyHealthSourceComparisonLineEntry {
            BodyHealthSourceComparisonLineEntry(
                sourceName: "Watch",
                sourceRole: .primary,
                point: HealthTrendCalendarPoint(
                    date: calendar.date(byAdding: .day, value: -dayOffset, to: dayStart) ?? dayStart,
                    value: value
                )
            )
        }

        let segments = BodyHealthSourceComparisonLineChart.lineSegments(
            from: [
                entry(dayOffset: 3, value: 50),
                entry(dayOffset: 2, value: nil),
                entry(dayOffset: 1, value: 54),
                entry(dayOffset: 0, value: 56)
            ],
            isPlaceholder: false
        )

        // Only the touching pair draws: the day with no reading leaves its two
        // neighbours as unconnected dots.
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.startValue, 54)
        XCTAssertEqual(segments.first?.endValue, 56)
    }

    func testEmptyCurrentEntriesSurviveWhenNoRangeHasAValueThere() {
        let day = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let empty = HealthTrendCalendarPoint(date: day, value: nil)

        let dots = BodyHealthSourceComparisonLineChart.unionDotEntries(
            currentEntries: [
                BodyHealthSourceComparisonLineEntry(sourceName: "Watch", sourceRole: .primary, point: empty)
            ],
            otherRangeEntries: [[
                BodyHealthSourceComparisonLineEntry(sourceName: "Watch", sourceRole: .primary, point: empty)
            ]]
        )

        XCTAssertEqual(dots.count, 1)
        XCTAssertNil(dots.first?.value)
        XCTAssertEqual(dots.first?.isPlaceholder, false)
    }

    func testRangeEntriesSeparateThePairBySourceRole() {
        let comparison = rangeComparison
        let entries = BodyHealthSourceComparisonRangeChart.rangeEntries(
            comparison: comparison,
            range: .recentWeek,
            calendar: calendar,
            date: anchorDate
        )
        let primary = try? XCTUnwrap(entries.first { $0.sourceRole == .primary })
        let secondary = entries.first { $0.sourceRole == .secondary && $0.date == primary?.date }

        XCTAssertNotNil(primary)
        XCTAssertNotNil(secondary)
        // The pair straddles its bucket date, so the two bars never overlap.
        XCTAssertNotEqual(primary?.chartDate, secondary?.chartDate)
        XCTAssertLessThan(try XCTUnwrap(primary?.chartDate), try XCTUnwrap(secondary?.chartDate))
    }
}
