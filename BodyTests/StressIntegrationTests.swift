//
//  StressIntegrationTests.swift
//  BodyTests
//
//  Snapshot-level Stress wiring: the `recalculatingStress` recompute, the
//  recorded-day accumulation it maintains, and the permission/Codable behaviour
//  of the new `HealthSummarySnapshot.stress` field. Pure model tests — the store
//  paths that call these are covered by `HealthKitWorkoutStoreTests`.
//

import XCTest
@testable import Body

final class StressIntegrationTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 0, minute: 0)) ?? Date()
    }

    /// Two heart-rate samples 6 minutes apart per window — just past the
    /// minimum-coverage rule, so every window scores.
    private func heartRateSamples(
        dayStart: Date,
        windowRange: Range<Int>,
        value: Double
    ) -> [HealthTrendDataPoint] {
        windowRange.flatMap { index -> [HealthTrendDataPoint] in
            let start = dayStart.addingTimeInterval(Double(index) * 900)
            return [
                HealthTrendDataPoint(date: start.addingTimeInterval(60), value: value),
                HealthTrendDataPoint(date: start.addingTimeInterval(420), value: value)
            ]
        }
    }

    /// Prior days carrying only the baseline aggregate, as the store accumulates
    /// them once the intraday samples have aged out of the ~32-day cache.
    private func recordedBaselineDays(
        endingBefore scoringDay: Date,
        dayCount: Int,
        quietHRMedian: Double,
        averageScore: Int? = 30
    ) -> [StressDaySummary] {
        (1...dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoringDay) else {
                return nil
            }

            return StressDaySummary(
                date: date,
                averageScore: averageScore,
                scoredWindowCount: 40,
                quietHRMedian: quietHRMedian
            )
        }
        .sorted { $0.date < $1.date }
    }

    private func snapshot(
        trends: HealthTrendSnapshot,
        summary: HealthSummarySnapshot = .empty
    ) -> HealthDashboardSnapshot {
        HealthDashboardSnapshot(summary: summary, trends: trends)
    }

    // MARK: - Recompute

    func testRecalculatingStressProducesTodaysSummaryAndSeries() throws {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: scoringDay,
            dayCount: 20,
            quietHRMedian: 60
        )
        // Today runs well above the 60 bpm quiet baseline.
        trends.heartRateDaySamples = HealthTrendSeries(
            points: heartRateSamples(dayStart: scoringDay, windowRange: 32..<48, value: 90)
        )

        let recomputed = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now
        )

        let today = try XCTUnwrap(recomputed.summary.stress)
        XCTAssertEqual(today.date, calendar.startOfDay(for: scoringDay))
        let score = try XCTUnwrap(today.averageScore)
        XCTAssertGreaterThan(score, 50)
        XCTAssertEqual(today.quietHRMedian, 90)
        XCTAssertGreaterThan(today.scoredWindowCount, 0)

        // 20 recorded days + today, all with a score.
        XCTAssertEqual(recomputed.trends.stress.points.count, 21)
        XCTAssertEqual(
            recomputed.trends.stress.points.last?.date,
            calendar.startOfDay(for: scoringDay)
        )
        XCTAssertEqual(recomputed.trends.stress.points.last?.value, Double(score))
    }

    /// `trends.stressRanges` is built alongside `trends.stress` from the same
    /// merged recorded days: only days carrying a scored min/max contribute a
    /// range point, and the freshly-computed today does.
    func testRecalculatingStressProducesRangeSeriesAlignedWithStressDays() throws {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        // Recorded baseline days predate min/max tracking (legacy records), so
        // they carry no min/max — only today's fresh compute should.
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: scoringDay,
            dayCount: 20,
            quietHRMedian: 60
        )
        // Two heart-rate levels across the day so today's windows spread
        // across a real min-max range, not a single repeated score.
        var samples = heartRateSamples(dayStart: scoringDay, windowRange: 32..<40, value: 90)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 40..<48, value: 62)
        trends.heartRateDaySamples = HealthTrendSeries(points: samples)

        let recomputed = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(recomputed.trends.stress.points.count, 21)
        // Only today carries a min/max, so it's the only range point.
        XCTAssertEqual(recomputed.trends.stressRanges.points.count, 1)
        let rangePoint = try XCTUnwrap(recomputed.trends.stressRanges.points.first)
        XCTAssertEqual(rangePoint.date, calendar.startOfDay(for: scoringDay))
        XCTAssertLessThan(rangePoint.lowValue, rangePoint.highValue)
        let recordedToday = try XCTUnwrap(recomputed.trends.recordedStressDays.last {
            calendar.startOfDay(for: $0.date) == calendar.startOfDay(for: scoringDay)
        })
        XCTAssertEqual(rangePoint.lowValue, Double(try XCTUnwrap(recordedToday.minScore)))
        XCTAssertEqual(rangePoint.highValue, Double(try XCTUnwrap(recordedToday.maxScore)))
        XCTAssertEqual(rangePoint.averageValue, recordedToday.averageScore.map(Double.init))
    }

    /// Without 14 distinct quiet-HR days there is no baseline, so every window is
    /// unscored (a calibration state) rather than scored against a stand-in.
    func testRecalculatingStressWithoutBaselineLeavesTodayUnscored() {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: scoringDay,
            dayCount: 5,
            quietHRMedian: 60,
            averageScore: nil
        )
        trends.heartRateDaySamples = HealthTrendSeries(
            points: heartRateSamples(dayStart: scoringDay, windowRange: 32..<48, value: 90)
        )

        let recomputed = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now
        )

        XCTAssertNil(recomputed.summary.stress?.averageScore)
        XCTAssertTrue(recomputed.trends.stress.points.isEmpty)
        // The day still records its quiet-HR aggregate, which is what lets the
        // baseline eventually calibrate.
        XCTAssertEqual(recomputed.summary.stress?.quietHRMedian, 90)
    }

    /// Workouts mask their windows, so the same heart rate reads as activity
    /// rather than stress.
    func testWorkoutsMaskTheirWindows() {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: scoringDay,
            dayCount: 20,
            quietHRMedian: 60
        )
        trends.heartRateDaySamples = HealthTrendSeries(
            points: heartRateSamples(dayStart: scoringDay, windowRange: 32..<48, value: 90)
        )
        let base = snapshot(trends: trends)

        let unmasked = base.recalculatingStress(on: scoringDay, calendar: calendar, now: now)
        let workoutStart = scoringDay.addingTimeInterval(8 * 3_600)
        let workout = WorkoutSummary(
            type: .running,
            startDate: workoutStart,
            duration: 4 * 3_600,
            endDate: workoutStart.addingTimeInterval(4 * 3_600)
        )
        let masked = base.recalculatingStress(
            on: scoringDay,
            workouts: [workout],
            calendar: calendar,
            now: now
        )

        XCTAssertGreaterThan(
            unmasked.summary.stress?.scoredWindowCount ?? 0,
            masked.summary.stress?.scoredWindowCount ?? 0
        )
    }

    // MARK: - Recorded days

    func testRecordedDaysReplaceSameDayAndPruneOldEntries() {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        let stale = StressDaySummary(
            date: calendar.date(byAdding: .day, value: -200, to: scoringDay) ?? scoringDay,
            averageScore: 12,
            quietHRMedian: 60
        )
        let staleToday = StressDaySummary(
            date: scoringDay,
            averageScore: 99,
            quietHRMedian: 99
        )
        trends.recordedStressDays = [stale]
            + recordedBaselineDays(endingBefore: scoringDay, dayCount: 20, quietHRMedian: 60)
            + [staleToday]
        trends.heartRateDaySamples = HealthTrendSeries(
            points: heartRateSamples(dayStart: scoringDay, windowRange: 32..<48, value: 62)
        )

        let recomputed = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now
        )

        // Older than the ~120-day retention: dropped.
        XCTAssertFalse(recomputed.trends.recordedStressDays.contains { $0.date == stale.date })
        // Today's stale record replaced by the fresh compute, not appended.
        let todayEntries = recomputed.trends.recordedStressDays.filter {
            calendar.startOfDay(for: $0.date) == calendar.startOfDay(for: scoringDay)
        }
        XCTAssertEqual(todayEntries.count, 1)
        XCTAssertNotEqual(todayEntries.first?.averageScore, 99)
        XCTAssertEqual(todayEntries.first?.quietHRMedian, 62)
        XCTAssertEqual(recomputed.trends.recordedStressDays.count, 21)
        XCTAssertEqual(
            recomputed.trends.recordedStressDays.map(\.date),
            recomputed.trends.recordedStressDays.map(\.date).sorted()
        )
    }

    func testChangedRecordContextDropsRecordedDays() {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressContext = "p[heart:1]"
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: scoringDay,
            dayCount: 20,
            quietHRMedian: 60
        )

        let kept = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now,
            recordedStressContext: "p[heart:1]"
        )
        XCTAssertEqual(kept.trends.recordedStressDays.count, 20)

        let dropped = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now,
            recordedStressContext: "p[heart:0]"
        )
        XCTAssertTrue(dropped.trends.recordedStressDays.isEmpty)
        XCTAssertEqual(dropped.trends.recordedStressContext, "p[heart:0]")
        XCTAssertTrue(dropped.trends.stress.points.isEmpty)
        XCTAssertNil(dropped.summary.stress)
    }

    // MARK: - Permissions

    func testFilteringWithoutHeartStripsStress() {
        var summary = HealthSummarySnapshot.empty
        summary.stress = StressDaySummary(date: day(2025, 3, 10), averageScore: 40)
        var trends = HealthTrendSnapshot.empty
        trends.stress = HealthTrendSeries(points: [HealthTrendDataPoint(date: day(2025, 3, 10), value: 40)])
        trends.recordedStressDays = [StressDaySummary(date: day(2025, 3, 10), averageScore: 40)]
        trends.stressRanges = HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: day(2025, 3, 10), lowValue: 10, highValue: 60, averageValue: 40)
        ])

        let withHeart = summary.filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.heart]))
        XCTAssertNotNil(withHeart.stress)

        let withoutHeart = summary.filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.steps]))
        XCTAssertNil(withoutHeart.stress)

        let filteredTrends = trends.filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.steps]))
        XCTAssertTrue(filteredTrends.stress.isEmpty)
        XCTAssertTrue(filteredTrends.recordedStressDays.isEmpty)
        XCTAssertTrue(filteredTrends.stressRanges.isEmpty)
    }

    // MARK: - Persistence

    func testSummaryCodableRoundTripsWithAndWithoutStress() throws {
        var withStress = HealthSummarySnapshot.empty
        withStress.stress = StressDaySummary(
            date: day(2025, 3, 10),
            averageScore: 44,
            minutesByBand: [.low: 120, .medium: 45],
            scoredWindowCount: 11,
            hrvCoveredWindowCount: 3,
            quietHRMedian: 63,
            rmssdDailyMedian: 41
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(
            HealthSummarySnapshot.self,
            from: encoder.encode(withStress)
        )
        XCTAssertEqual(decoded.stress, withStress.stress)
        XCTAssertFalse(decoded.isEmpty)

        // A snapshot written before the field existed decodes with `nil` rather
        // than failing (both types hand-roll `init(from:)`).
        let legacy = try decoder.decode(
            HealthSummarySnapshot.self,
            from: Data(#"{"metricWarnings":[]}"#.utf8)
        )
        XCTAssertNil(legacy.stress)
        XCTAssertTrue(legacy.isEmpty)

        var trends = HealthTrendSnapshot.empty
        trends.stress = HealthTrendSeries(points: [HealthTrendDataPoint(date: day(2025, 3, 10), value: 44)])
        trends.recordedStressDays = [withStress.stress].compactMap { $0 }
        trends.recordedStressContext = "p[heart:1]"
        let decodedTrends = try decoder.decode(
            HealthTrendSnapshot.self,
            from: encoder.encode(trends)
        )
        XCTAssertEqual(decodedTrends.stress, trends.stress)
        XCTAssertEqual(decodedTrends.recordedStressDays, trends.recordedStressDays)
        XCTAssertEqual(decodedTrends.recordedStressContext, "p[heart:1]")
    }

    /// `recordedStressDays` is what the snapshot store's save-if-changed byte
    /// compare runs against, so an unchanged trend snapshot must encode
    /// identically across launches. Uses `.sortedKeys`, matching every
    /// snapshot-store encoder (see `HealthDashboardSnapshotStore.makeSnapshotEncoder()`).
    func testTrendSnapshotWithRecordedStressDaysIsByteStableAcrossEncodes() throws {
        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = [
            StressDaySummary(
                date: day(2025, 3, 10),
                averageScore: 44,
                minutesByBand: [.rest: 10, .low: 120, .medium: 45, .high: 3],
                scoredWindowCount: 11,
                hrvCoveredWindowCount: 3,
                quietHRMedian: 63,
                rmssdDailyMedian: 41
            )
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(trends)
        let second = try encoder.encode(trends)
        XCTAssertEqual(first, second)
    }
}
