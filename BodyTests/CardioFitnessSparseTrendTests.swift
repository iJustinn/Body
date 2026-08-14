//
//  CardioFitnessSparseTrendTests.swift
//  BodyTests
//
//  Covers `HealthTrendSeries.sparseLineChartCalendarPoints`, the line path for
//  metrics whose readings arrive days or weeks apart (Cardio Fitness records one
//  VO₂ max estimate per qualifying outdoor workout). The dense path averages
//  readings into fixed buckets and stamps each average at the bucket's end date;
//  these tests pin that the sparse path keeps every reading on its own day at
//  its own value, and that it still compresses once real readings outnumber the
//  range's visual cap.
//

import XCTest
@testable import Body

final class CardioFitnessSparseTrendTests: XCTestCase {

    private let calendar = Calendar.bodyGregorian

    private func today() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
    }

    /// A series with a reading every `strideDays` days going back from `today`.
    private func sparseSeries(
        readingCount: Int,
        strideDays: Int,
        today: Date,
        value: (Int) -> Double
    ) -> HealthTrendSeries {
        let points = (0..<readingCount).compactMap { index -> HealthTrendDataPoint? in
            guard let date = calendar.date(byAdding: .day, value: -index * strideDays, to: today) else {
                return nil
            }
            return HealthTrendDataPoint(date: calendar.startOfDay(for: date), value: value(index))
        }
        return HealthTrendSeries(points: points.sorted { $0.date < $1.date })
    }

    // MARK: - Real dates survive

    func testSparsePathKeepsEachReadingOnItsOwnDayOnTheYearRange() throws {
        let today = try today()
        // Roughly two readings a month for six months — the real Cardio Fitness
        // cadence, and well under the 25-point cap so nothing compresses.
        let series = sparseSeries(readingCount: 12, strideDays: 15, today: today) { index in
            40 + Double(index)
        }

        let points = series.sparseLineChartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: today
        )

        XCTAssertEqual(points.count, 12)
        XCTAssertEqual(points.map(\.date), series.points.map(\.date))
        XCTAssertEqual(points.compactMap(\.value), series.points.map(\.value))
    }

    /// The behaviour the sparse path exists to avoid: on the year range the dense
    /// path buckets 12 days at a time and stamps each bucket at its END date, so
    /// readings land away from the day they were measured.
    func testDensePathShiftsSparseReadingsOffTheirMeasurementDates() throws {
        let today = try today()
        let series = sparseSeries(readingCount: 12, strideDays: 15, today: today) { index in
            40 + Double(index)
        }
        let readingDates = Set(series.points.map(\.date))

        let dense = series.lineChartCalendarPoints(to: .recentYear, calendar: calendar, date: today)
        let sparse = series.sparseLineChartCalendarPoints(to: .recentYear, calendar: calendar, date: today)

        XCTAssertFalse(
            dense.allSatisfy { readingDates.contains($0.date) },
            "the dense path is expected to move points off their measurement dates"
        )
        XCTAssertTrue(
            sparse.allSatisfy { readingDates.contains($0.date) },
            "the sparse path must not"
        )
    }

    func testSparsePathDropsDaysWithNoReading() throws {
        let today = try today()
        let series = sparseSeries(readingCount: 3, strideDays: 20, today: today) { _ in 42 }

        let points = series.sparseLineChartCalendarPoints(
            to: .recentSixMonths,
            calendar: calendar,
            date: today
        )

        XCTAssertEqual(points.count, 3, "only real readings, not the empty days between them")
        XCTAssertTrue(points.allSatisfy(\.hasValue))
    }

    func testSparsePathIsEmptyWhenNoReadingFallsInTheRange() throws {
        let today = try today()
        // One reading 200 days ago: inside the year range, outside the week.
        let old = try XCTUnwrap(calendar.date(byAdding: .day, value: -200, to: today))
        let series = HealthTrendSeries(
            points: [HealthTrendDataPoint(date: calendar.startOfDay(for: old), value: 44)]
        )

        XCTAssertTrue(
            series.sparseLineChartCalendarPoints(to: .recentWeek, calendar: calendar, date: today).isEmpty
        )
        XCTAssertEqual(
            series.sparseLineChartCalendarPoints(to: .recentYear, calendar: calendar, date: today).count,
            1
        )
    }

    // MARK: - Compression

    func testReadingsUnderTheCapAreNotCompressed() throws {
        let today = try today()
        let cap = try XCTUnwrap(BodyHealthTrendRange.recentYear.lineChartMaximumPointCount)
        let series = sparseSeries(readingCount: cap, strideDays: 3, today: today) { index in
            40 + Double(index)
        }

        let points = series.sparseLineChartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: today
        )

        XCTAssertEqual(points.count, cap, "exactly at the cap must pass through untouched")
        XCTAssertEqual(points.map(\.date), series.points.map(\.date))
    }

    /// Thinning past the cap must DROP readings, never average them. Averaging
    /// would emit a VO₂ max that was never measured, stamped on a day it was
    /// never measured — the same distortion the sparse path exists to avoid.
    func testReadingsOverTheCapAreThinnedWithoutInventingValues() throws {
        let today = try today()
        let cap = try XCTUnwrap(BodyHealthTrendRange.recentYear.lineChartMaximumPointCount)
        // A daily reading for most of the year — far more than the cap. Values
        // are distinct per day, so any averaged point would not match a real one.
        let series = sparseSeries(readingCount: 300, strideDays: 1, today: today) { index in
            40 + Double(index) * 0.01
        }

        let points = series.sparseLineChartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: today
        )

        XCTAssertLessThanOrEqual(points.count, cap)
        XCTAssertFalse(points.isEmpty)

        // Every plotted point must be an untouched (date, value) pair from the
        // source series — not just a real date carrying a synthetic value.
        let readingsByDate = Dictionary(
            uniqueKeysWithValues: series.points.map { ($0.date, $0.value) }
        )
        for point in points {
            let recorded = try XCTUnwrap(readingsByDate[point.date], "unknown date \(point.date)")
            XCTAssertEqual(try XCTUnwrap(point.value), recorded, accuracy: .ulpOfOne)
        }

        // Endpoints survive so the visible span still runs edge to edge.
        XCTAssertEqual(points.first?.date, series.points.first?.date)
        XCTAssertEqual(points.last?.date, series.points.last?.date)
        XCTAssertEqual(Set(points.map(\.date)).count, points.count, "no reading picked twice")
    }

    func testThinningKeepsReadingsInChronologicalOrder() throws {
        let today = try today()
        let series = sparseSeries(readingCount: 120, strideDays: 2, today: today) { index in
            35 + Double(index % 11)
        }

        let dates = series.sparseLineChartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: today
        ).map(\.date)

        XCTAssertEqual(dates, dates.sorted())
    }

    func testWeekRangeHasNoCapAndKeepsEveryReading() throws {
        let today = try today()
        let series = sparseSeries(readingCount: 3, strideDays: 2, today: today) { _ in 41 }

        let points = series.sparseLineChartCalendarPoints(
            to: .recentWeek,
            calendar: calendar,
            date: today
        )

        XCTAssertNil(BodyHealthTrendRange.recentWeek.lineChartMaximumPointCount)
        XCTAssertEqual(points.count, 3)
    }

    // MARK: - Kind wiring

    func testOnlyCardioFitnessOptsIntoTheSparsePath() {
        XCTAssertTrue(HealthMetricKind.cardioFitness.usesSparseTrendReadings)
        for kind in HealthMetricKind.allCases where kind != .cardioFitness {
            XCTAssertFalse(
                kind.usesSparseTrendReadings,
                "\(kind) must keep the existing bucketed line path"
            )
        }
    }
}
