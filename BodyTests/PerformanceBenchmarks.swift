//
//  PerformanceBenchmarks.swift
//  BodyTests
//
//  Baseline `measure` benchmarks for the CPU-bound helpers touched by the
//  0.9.2 performance work. Run before and after a change to compare; the
//  functions themselves stay behavior-identical, so these double as
//  regression guards for the hot paths.
//
//  Skipped by default: this class is in the `Parallel` test-plan
//  configuration's skip list because `measure` timings are noisy across
//  machines and don't belong in a normal CI run. To run it deliberately,
//  select the class in Xcode's Test navigator, or from the CLI:
//  xcodebuild -project body.xcodeproj -scheme Body \
//    -destination 'platform=iOS Simulator,name=iPhone 17' \
//    -only-testing:BodyTests/PerformanceBenchmarks test
//

import XCTest
@testable import Body

final class PerformanceBenchmarks: XCTestCase {
    private static let calendar: Calendar = {
        var calendar = Calendar.bodyGregorian
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-09-01 00:00 UTC, fixed so fixtures are deterministic across runs.
    private static let anchor = Date(timeIntervalSince1970: 1_788_220_800)

    private func dailySeries(days: Int, endingAt end: Date = PerformanceBenchmarks.anchor) -> HealthTrendSeries {
        let calendar = Self.calendar
        let endDay = calendar.startOfDay(for: end)
        let points = (0..<days).compactMap { offset -> HealthTrendDataPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else {
                return nil
            }
            return HealthTrendDataPoint(date: day, value: 60 + Double(offset % 23))
        }
        return HealthTrendSeries(points: points.reversed())
    }

    private func intradaySeries(pointCount: Int, endingAt end: Date = PerformanceBenchmarks.anchor) -> HealthTrendSeries {
        let sampleSpacing: TimeInterval = 5 * 60
        let points = (0..<pointCount).map { offset in
            HealthTrendDataPoint(
                date: end.addingTimeInterval(-Double(pointCount - offset) * sampleSpacing),
                value: 55 + Double(offset % 70)
            )
        }
        return HealthTrendSeries(points: points)
    }

    func testBaselineLineChartCompressionOverRecentYear() {
        let series = dailySeries(days: 365)
        measure {
            _ = series.lineChartCalendarPoints(to: .recentYear)
        }
    }

    func testBaselineMetricCardPreviewPointsPerDashboardRender() {
        // One dashboard render builds previews for ~15 cards.
        let series = dailySeries(days: 365)
        measure {
            for _ in 0..<15 {
                _ = BodyHomeMetricCardPreview.calendarPoints(from: series)
            }
        }
    }

    func testBaselineHourlyBucketsOverLargeIntradaySeries() {
        let series = intradaySeries(pointCount: 50_000)
        let day = Self.calendar.startOfDay(for: Self.anchor)
        measure {
            _ = series.hourlyAverageBuckets(on: day)
        }
    }
}
