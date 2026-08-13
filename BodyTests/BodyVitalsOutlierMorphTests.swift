//
//  BodyVitalsOutlierMorphTests.swift
//  BodyTests
//
//  Covers the vitals outlier chart's range-switch morph union: the rendered
//  entry list must carry every range's bucket end dates exactly once (current
//  range first, as visible bars; the rest as invisible placeholders at their
//  own range's geometry), so switching ranges morphs marks in place instead
//  of inserting/removing them.
//

import XCTest
@testable import Body

final class BodyVitalsOutlierMorphTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    /// Fixed "today" so bucket grids never depend on the wall clock.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: 17))!
    }

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: today))!
    }

    private func night(daysAgo: Int, deviation: Double = 0) -> VitalsNightAssessment {
        let region: SleepVitalRegion = deviation > 1 ? .high : (deviation < -1 ? .low : .typical)
        let measurement = VitalMeasurement(
            kind: .sleepingHeartRate,
            value: 50,
            baseline: ReadinessScoreCalculator.Baseline(median: 50, spread: 2, validDayCount: 20),
            normalizedDeviation: deviation,
            region: region,
            referenceRange: SleepVitalReferenceRange(typicalLowerBound: 45, typicalUpperBound: 55)
        )
        return VitalsNightAssessment(date: day(daysAgo), measurements: [measurement])
    }

    private func buckets(
        for range: BodyHealthTrendRange,
        nights: [VitalsNightAssessment]
    ) -> [BodyVitalsOutlierBucket] {
        BodyVitalsOutlierTrendChart.buckets(
            from: nights,
            days: BodyVitalsOutlierTrendChart.dayGrid(for: range, calendar: calendar, date: today),
            selectedRange: range,
            calendar: calendar
        )
    }

    private func unionEntries(
        currentRange: BodyHealthTrendRange,
        nights: [VitalsNightAssessment]
    ) -> [BodyVitalsOutlierBarEntry] {
        BodyVitalsOutlierTrendChart.unionBarEntries(
            currentBuckets: buckets(for: currentRange, nights: nights),
            otherRangeBuckets: BodyHealthTrendRange.allCases
                .filter { $0 != currentRange }
                .map { buckets(for: $0, nights: nights) }
        )
    }

    func testUnionCoversEveryRangesBucketEndDatesExactlyOnceWithCurrentRangeFirst() {
        let nights = [
            night(daysAgo: 0), night(daysAgo: 3), night(daysAgo: 20), night(daysAgo: 100)
        ]
        let entries = unionEntries(currentRange: .recentWeek, nights: nights)

        let expectedEndDates = Set(BodyHealthTrendRange.allCases.flatMap { range in
            buckets(for: range, nights: nights).map(\.endDate)
        })
        XCTAssertEqual(Set(entries.map(\.id)), expectedEndDates)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)

        // The current range's buckets lead the list as visible bars; every
        // other entry is an invisible placeholder.
        let weekEndDates = buckets(for: .recentWeek, nights: nights).map(\.endDate)
        XCTAssertEqual(entries.prefix(weekEndDates.count).map(\.id), weekEndDates)
        XCTAssertTrue(entries.prefix(weekEndDates.count).allSatisfy { !$0.isPlaceholder })
        XCTAssertTrue(entries.dropFirst(weekEndDates.count).allSatisfy(\.isPlaceholder))
    }

    func testPlaceholdersCarryTheirOwnRangesGeometry() throws {
        // Nights 8 and 10 days ago fall in the six-month range's 6-day bucket
        // spanning days 11...6 ago — its placeholder must sit at that bucket's
        // own start/end dates and aggregated deviations, not week geometry.
        let nights = [
            night(daysAgo: 1, deviation: 0.5),
            night(daysAgo: 8, deviation: 2),
            night(daysAgo: 10, deviation: -1.5)
        ]
        let entries = unionEntries(currentRange: .recentWeek, nights: nights)
        let sixMonthEntry = try XCTUnwrap(entries.first { $0.id == day(6) })

        XCTAssertTrue(sixMonthEntry.isPlaceholder)
        XCTAssertEqual(sixMonthEntry.bucket.date, day(11))
        XCTAssertEqual(sixMonthEntry.bucket.endDate, day(6))
        XCTAssertEqual(sixMonthEntry.bucket.minDeviation, -1.5)
        XCTAssertEqual(sixMonthEntry.bucket.maxDeviation, 2)
    }

    func testSharedEndDateResolvesToTheCurrentRangesBucket() throws {
        // Week and Month both bucket by single days, so a night 2 days ago
        // gives both ranges a bucket ending on the same date.
        let nights = [night(daysAgo: 2, deviation: 1.2)]
        let weekEntries = unionEntries(currentRange: .recentWeek, nights: nights)

        XCTAssertEqual(weekEntries.filter { $0.id == day(2) }.count, 1)
        let sharedEntry = try XCTUnwrap(weekEntries.first { $0.id == day(2) })
        XCTAssertFalse(sharedEntry.isPlaceholder)

        // With differing geometries on the shared date, the current range's
        // bucket still wins: the year's 12-day bucket ending today beats the
        // week's single-day bucket there when Year is selected.
        let spreadNights = [night(daysAgo: 0, deviation: 0.5), night(daysAgo: 5, deviation: 1.5)]
        let yearEntries = unionEntries(currentRange: .recentYear, nights: spreadNights)
        let todayEntry = try XCTUnwrap(yearEntries.first { $0.id == day(0) })

        XCTAssertFalse(todayEntry.isPlaceholder)
        XCTAssertEqual(todayEntry.bucket.date, day(11))
        XCTAssertEqual(yearEntries.first { $0.id == day(5) }?.isPlaceholder, true)
    }
}
