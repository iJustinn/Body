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
        // Beyond the 400-day retention the history backfill needs: a 200-day-old
        // entry is now deliberately KEPT (see `testRecordedDaysWithinYearRetentionSurvive`).
        let stale = StressDaySummary(
            date: calendar.date(byAdding: .day, value: -420, to: scoringDay) ?? scoringDay,
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

        // Older than the 400-day retention: dropped.
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

    /// The retention has to reach a year plus a baseline halo, or the history
    /// backfill's oldest chunks would be pruned by the publish that writes them.
    func testRecordedDaysWithinYearRetentionSurvive() {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        let backfilled = StressDaySummary(
            date: calendar.date(byAdding: .day, value: -200, to: scoringDay) ?? scoringDay,
            averageScore: 33,
            quietHRMedian: 60
        )
        let yearEdge = StressDaySummary(
            date: calendar.date(byAdding: .day, value: -365, to: scoringDay) ?? scoringDay,
            averageScore: 21,
            quietHRMedian: 61
        )
        trends.recordedStressDays = [yearEdge, backfilled]

        let recomputed = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(recomputed.trends.recordedStressDays.map(\.date), [yearEdge.date, backfilled.date])
        XCTAssertEqual(recomputed.trends.stress.points.count, 2)
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

    /// The backfill marker describes the very days a context change drops, so it
    /// has to go with them — otherwise the walk reports a completed history over
    /// records that no longer exist and never rescans.
    func testChangedRecordContextClearsBackfillMarker() {
        let scoringDay = day(2025, 3, 10)
        let now = scoringDay.addingTimeInterval(12 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressContext = "p[heart:1]"
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: scoringDay,
            dayCount: 20,
            quietHRMedian: 60
        )
        trends.stressBackfillScannedThrough = calendar.date(byAdding: .day, value: -40, to: scoringDay)
        trends.stressBackfillComplete = true

        let kept = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now,
            recordedStressContext: "p[heart:1]"
        )
        XCTAssertTrue(kept.trends.stressBackfillComplete)
        XCTAssertNotNil(kept.trends.stressBackfillScannedThrough)

        let dropped = snapshot(trends: trends).recalculatingStress(
            on: scoringDay,
            calendar: calendar,
            now: now,
            recordedStressContext: "p[heart:0]"
        )
        XCTAssertFalse(dropped.trends.stressBackfillComplete)
        XCTAssertNil(dropped.trends.stressBackfillScannedThrough)
    }

    // MARK: - History backfill

    /// Recorded days, both stress series and the walk marker move together in
    /// one publish: `recordedStressDays` and `trends.stress` are separate stored
    /// fields, so records alone would never reach the Year chart.
    func testBackfillChunkUpsertsDaysRebuildsSeriesAndAdvancesMarker() throws {
        let today = day(2025, 3, 10)
        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: today,
            dayCount: 5,
            quietHRMedian: 60
        )

        let chunkEnd = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        let backfilled = (1...3).compactMap { offset -> StressDaySummary? in
            guard let date = calendar.date(byAdding: .day, value: -(60 + offset), to: today) else {
                return nil
            }

            return StressDaySummary(
                date: date,
                averageScore: 40 + offset,
                scoredWindowCount: 30,
                quietHRMedian: 58,
                minScore: 20,
                maxScore: 70
            )
        }

        let merged = snapshot(trends: trends).mergingStressBackfillChunk(
            backfilled,
            scannedThrough: chunkEnd,
            complete: false,
            on: today,
            calendar: calendar
        )

        XCTAssertEqual(merged.trends.recordedStressDays.count, 8)
        XCTAssertEqual(
            merged.trends.recordedStressDays.map(\.date),
            merged.trends.recordedStressDays.map(\.date).sorted()
        )
        XCTAssertEqual(merged.trends.stress.points.count, 8)
        XCTAssertEqual(merged.trends.stressRanges.points.count, 3)
        XCTAssertEqual(merged.trends.stressBackfillScannedThrough, chunkEnd)
        XCTAssertFalse(merged.trends.stressBackfillComplete)
        // Untouched: the walk never scores a day inside the live window.
        XCTAssertNil(merged.summary.stress)

        // A second chunk resumes from the marker and keeps the first chunk's days.
        let nextEnd = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let resumed = merged.mergingStressBackfillChunk(
            [
                StressDaySummary(
                    date: calendar.date(byAdding: .day, value: -50, to: today) ?? today,
                    averageScore: 55,
                    quietHRMedian: 59
                )
            ],
            scannedThrough: nextEnd,
            complete: true,
            on: today,
            calendar: calendar
        )
        XCTAssertEqual(resumed.trends.recordedStressDays.count, 9)
        XCTAssertEqual(resumed.trends.stressBackfillScannedThrough, nextEnd)
        XCTAssertTrue(resumed.trends.stressBackfillComplete)
        XCTAssertTrue(resumed.trends.recordedStressDays.contains { $0.date == backfilled[0].date })
    }

    /// A day the live recompute already recorded wins over a backfilled one: the
    /// walk fetches no beat-to-beat RMSSD, so overwriting would downgrade it.
    func testBackfillChunkDoesNotOverwriteExistingRecordedDays() throws {
        let today = day(2025, 3, 10)
        let existingDay = calendar.date(byAdding: .day, value: -40, to: today) ?? today

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = [
            StressDaySummary(date: existingDay, averageScore: 70, quietHRMedian: 62, rmssdDailyMedian: 44)
        ]

        let merged = snapshot(trends: trends).mergingStressBackfillChunk(
            [StressDaySummary(date: existingDay, averageScore: 10, quietHRMedian: 51)],
            scannedThrough: today,
            complete: true,
            on: today,
            calendar: calendar
        )

        let kept = try XCTUnwrap(merged.trends.recordedStressDays.first)
        XCTAssertEqual(kept.averageScore, 70)
        XCTAssertEqual(kept.rmssdDailyMedian, 44)
    }

    /// The walk runs forward for a reason: `robustBaseline` only reads days
    /// dated strictly BEFORE the day it is scoring. Inside one chunk that means
    /// the opening days stay uncalibrated until 14 of their own predecessors
    /// exist, and nothing is ever scored against a day still in its future.
    func testBackfillChunkScoresDaysOnlyAgainstPriorDays() throws {
        let chunkStart = day(2025, 1, 1)
        let dayCount = 20
        let chunkEnd = calendar.date(byAdding: .day, value: dayCount, to: chunkStart) ?? chunkStart
        let now = calendar.date(byAdding: .day, value: dayCount + 5, to: chunkStart) ?? chunkStart

        var samples: [HealthTrendDataPoint] = []
        for offset in 0..<dayCount {
            let dayStart = calendar.date(byAdding: .day, value: offset, to: chunkStart) ?? chunkStart
            // The last day runs hot; every earlier day sits on the quiet baseline.
            samples += heartRateSamples(
                dayStart: dayStart,
                windowRange: 32..<48,
                value: offset == dayCount - 1 ? 90 : 60
            )
        }

        let inputs = StressDayInput.dayInputs(
            from: chunkStart,
            to: chunkEnd,
            heartRateSamples: samples,
            sdnnSamples: [],
            hourlySteps: [],
            hourlyActiveEnergy: [],
            workouts: [],
            sleepIntervalsByDay: [:],
            calendar: calendar
        )
        XCTAssertEqual(inputs.count, dayCount)

        let context = snapshot(trends: .empty).stressBackfillContext(
            chunkInputs: inputs,
            calendar: calendar,
            now: now
        )
        let summaries = inputs.map { input in
            StressScoreCalculator.daySummary(
                for: input,
                baselines: context.baselines(for: input.date),
                calendar: calendar,
                now: now
            )
        }

        // 13 prior days is one short of the minimum, 14 is enough.
        XCTAssertNil(summaries[13].averageScore)
        XCTAssertNotNil(summaries[14].averageScore)
        // Every day still records its quiet-HR aggregate, which is what lets the
        // later days in the same chunk calibrate at all.
        XCTAssertEqual(summaries[0].quietHRMedian, 60)
        // The hot final day reads far above the quiet days it follows.
        let hot = try XCTUnwrap(summaries[dayCount - 1].averageScore)
        let calm = try XCTUnwrap(summaries[dayCount - 2].averageScore)
        XCTAssertGreaterThan(hot, calm)
    }

    /// The chunk after it inherits those days through the records the publish
    /// left behind, so its very first day is calibrated from the start.
    func testBackfillChunkScoresFirstDayAgainstEarlierChunksRecords() throws {
        let chunkStart = day(2025, 2, 1)
        let chunkEnd = calendar.date(byAdding: .day, value: 2, to: chunkStart) ?? chunkStart
        let now = calendar.date(byAdding: .day, value: 10, to: chunkStart) ?? chunkStart

        var trends = HealthTrendSnapshot.empty
        trends.recordedStressDays = recordedBaselineDays(
            endingBefore: chunkStart,
            dayCount: 20,
            quietHRMedian: 60
        )

        let inputs = StressDayInput.dayInputs(
            from: chunkStart,
            to: chunkEnd,
            heartRateSamples: heartRateSamples(dayStart: chunkStart, windowRange: 32..<48, value: 90),
            sdnnSamples: [],
            hourlySteps: [],
            hourlyActiveEnergy: [],
            workouts: [],
            sleepIntervalsByDay: [:],
            calendar: calendar
        )
        let context = snapshot(trends: trends).stressBackfillContext(
            chunkInputs: inputs,
            calendar: calendar,
            now: now
        )
        let first = try XCTUnwrap(inputs.first)
        let summary = StressScoreCalculator.daySummary(
            for: first,
            baselines: context.baselines(for: first.date),
            calendar: calendar,
            now: now
        )

        XCTAssertGreaterThan(try XCTUnwrap(summary.averageScore), 50)
    }

    /// Backfill markers are new fields on a long-lived persisted snapshot, so a
    /// file written before they existed has to decode rather than throw.
    func testTrendSnapshotDecodesWithoutBackfillMarkers() throws {
        var trends = HealthTrendSnapshot.empty
        trends.stressBackfillScannedThrough = day(2025, 1, 1)
        trends.stressBackfillComplete = true

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthTrendSnapshot.self, from: encoder.encode(trends))
        XCTAssertEqual(decoded.stressBackfillScannedThrough, trends.stressBackfillScannedThrough)
        XCTAssertTrue(decoded.stressBackfillComplete)

        var legacy = try JSONSerialization.jsonObject(
            with: encoder.encode(HealthTrendSnapshot.empty)
        ) as? [String: Any] ?? [:]
        legacy.removeValue(forKey: "stressBackfillScannedThrough")
        legacy.removeValue(forKey: "stressBackfillComplete")
        let decodedLegacy = try decoder.decode(
            HealthTrendSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertNil(decodedLegacy.stressBackfillScannedThrough)
        XCTAssertFalse(decodedLegacy.stressBackfillComplete)
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
        trends.stressBackfillScannedThrough = day(2025, 3, 10)
        trends.stressBackfillComplete = true

        let withHeart = summary.filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.heart]))
        XCTAssertNotNil(withHeart.stress)

        let withoutHeart = summary.filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.steps]))
        XCTAssertNil(withoutHeart.stress)

        let filteredTrends = trends.filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.steps]))
        XCTAssertTrue(filteredTrends.stress.isEmpty)
        XCTAssertTrue(filteredTrends.recordedStressDays.isEmpty)
        XCTAssertTrue(filteredTrends.stressRanges.isEmpty)
        // Re-enabling Heart restores the same context signature, so nothing else
        // resets these — if `filtered(by:)` left them set, `stressBackfillComplete`
        // would permanently block the walk from rescanning the history it just
        // dropped above.
        XCTAssertNil(filteredTrends.stressBackfillScannedThrough)
        XCTAssertFalse(filteredTrends.stressBackfillComplete)
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

    // MARK: - Activity minutes

    /// Masked windows are a display category, not a band: they must never land in
    /// `minutesByBand` (which would give the day a phantom Rest stretch) but they
    /// must be counted, so the breakdown's five rows account for the measured day.
    func testDaySummaryCountsActivityMinutesSeparatelyFromBands() {
        let dayStart = day(2025, 3, 10)
        let windows: [StressWindow] = (0..<6).map { index in
            let interval = DateInterval(
                start: dayStart.addingTimeInterval(Double(index) * 900),
                duration: 900
            )
            switch index {
            case 0, 1:
                return StressWindow(interval: interval, state: .scored(score: 20, hrOnly: false))
            case 2, 3, 4:
                return StressWindow(interval: interval, state: .activity)
            default:
                return StressWindow(interval: interval, state: .unscored)
            }
        }

        let summary = StressScoreCalculator.daySummary(windows: windows, date: dayStart)

        XCTAssertEqual(summary.activityMinutes, 45)
        XCTAssertEqual(summary.minutes(in: .rest), 30)
        XCTAssertEqual(summary.totalScoredMinutes, 30)
        XCTAssertEqual(summary.totalMeasuredMinutes, 75)
    }

    /// A record written before `activityMinutes` existed must decode as 0 rather
    /// than throwing, and a round trip must preserve the new field.
    func testStressDaySummaryDecodesLegacyRecordWithoutActivityMinutes() throws {
        let legacy = Data(#"{"date":761000000,"minutesByBand":{"rest":30},"scoredWindowCount":2,"hrvCoveredWindowCount":0}"#.utf8)
        let decoded = try JSONDecoder().decode(StressDaySummary.self, from: legacy)
        XCTAssertEqual(decoded.activityMinutes, 0)

        var updated = decoded
        updated.activityMinutes = 45
        let round = try JSONDecoder().decode(
            StressDaySummary.self,
            from: JSONEncoder().encode(updated)
        )
        XCTAssertEqual(round.activityMinutes, 45)
    }

    // MARK: - Intraday plot axis

    /// The plot's x domain is the real calendar day, so the 06/12/18 ticks are
    /// resolved through the calendar rather than pinned to 0.25/0.5/0.75. On a
    /// 23-hour spring-forward day every civil hour after the transition sits
    /// LATER in the day's fraction than it would on a 24-hour day.
    func testIntradayTimeMarksShiftOnSpringForwardDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let dayStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 3, day: 9))
        )
        let dayInterval = try XCTUnwrap(calendar.dateInterval(of: .day, for: dayStart))
        XCTAssertEqual(dayInterval.duration, 23 * 3_600)

        let marks = BodyStressIntradayPlot.timeMarks(for: dayInterval, calendar: calendar)
        XCTAssertEqual(marks.count, 4)
        XCTAssertEqual(marks[0].fraction, 0, accuracy: 0.0001)
        // 06:00 is 5 elapsed hours into a 23-hour day, not 6 into 24.
        XCTAssertEqual(marks[1].fraction, 5.0 / 23.0, accuracy: 0.0001)
        XCTAssertEqual(marks[2].fraction, 11.0 / 23.0, accuracy: 0.0001)
        XCTAssertEqual(marks[3].fraction, 17.0 / 23.0, accuracy: 0.0001)
        XCTAssertNotEqual(marks[1].fraction, 0.25, accuracy: 0.0001)
    }

    /// The 25-hour fall-back mirror image: every civil hour after the repeat sits
    /// EARLIER in the day's fraction. 01:00 happens twice, and the earlier one is
    /// the one the axis resolves.
    func testIntradayTimeMarksShiftOnFallBackDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let dayStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2025, month: 11, day: 2))
        )
        let dayInterval = try XCTUnwrap(calendar.dateInterval(of: .day, for: dayStart))
        XCTAssertEqual(dayInterval.duration, 25 * 3_600)

        let marks = BodyStressIntradayPlot.timeMarks(for: dayInterval, calendar: calendar)
        XCTAssertEqual(marks.count, 4)
        XCTAssertEqual(marks[0].fraction, 0, accuracy: 0.0001)
        XCTAssertEqual(marks[1].fraction, 7.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(marks[2].fraction, 13.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(marks[3].fraction, 19.0 / 25.0, accuracy: 0.0001)
    }

    /// Unscored stretches are literal gaps: they produce no mark at all, so the
    /// scrub snaps across them to the nearest drawn window instead of landing on
    /// a blank stretch. Activity windows DO become marks (the callout shows them
    /// with no score).
    func testIntradayMarksSkipUnscoredWindowsAndSpanTheFullDay() throws {
        let calendar = Calendar.bodyGregorian
        let dayStart = day(2025, 3, 10)
        let dayInterval = try XCTUnwrap(calendar.dateInterval(of: .day, for: dayStart))
        let windows: [StressWindow] = (0..<4).map { index in
            let interval = DateInterval(
                start: dayStart.addingTimeInterval(Double(index) * 900),
                duration: 900
            )
            switch index {
            case 0:
                return StressWindow(interval: interval, state: .scored(score: 60, hrOnly: false))
            case 1:
                return StressWindow(interval: interval, state: .unscored)
            default:
                return StressWindow(interval: interval, state: .activity)
            }
        }

        let marks = BodyStressIntradayPlot.marks(for: windows, in: dayInterval)

        XCTAssertEqual(marks.map(\.id), [0, 2, 3])
        XCTAssertEqual(marks[0].kind, .scored(score: 60, band: .medium))
        XCTAssertEqual(marks[1].kind, .activity)
        // Fractions are of the whole day, so an early-morning window sits at the
        // far left even though nothing later in the day has arrived yet.
        XCTAssertEqual(marks[0].xStart, 0, accuracy: 0.0001)
        XCTAssertEqual(marks[0].xEnd, 900.0 / 86_400.0, accuracy: 0.0001)
    }

    // MARK: - Day-switch morph pairing

    /// Every window scored, so each one becomes a track.
    private func scoredWindows(for dayInterval: DateInterval, calendar: Calendar, now: Date) -> [StressWindow] {
        StressScoreCalculator.windowIntervals(for: dayInterval.start, calendar: calendar, now: now)
            .map { StressWindow(interval: $0, state: .scored(score: 40, hrOnly: false)) }
    }

    private func side(
        for dayStart: Date,
        calendar: Calendar,
        now: Date
    ) throws -> (side: BodyStressPlotSide, windowCount: Int) {
        let dayInterval = try XCTUnwrap(calendar.dateInterval(of: .day, for: dayStart))
        let windows = scoredWindows(for: dayInterval, calendar: calendar, now: now)
        return (
            BodyStressPlotSide.make(
                windows: windows,
                dayInterval: dayInterval,
                contextIntervals: [],
                calendar: calendar
            ),
            windows.count
        )
    }

    private var losAngeles: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }

    /// Spring forward: the 23-hour day has no 02:00–02:45 slots at all. Pairing by
    /// civil time keeps 03:00 with 03:00 (an elapsed-index pairing would slide the
    /// whole rest of the day by four windows); the four missing slots simply fade.
    func testMorphPairsSpringForwardDayByCivilTime() throws {
        let calendar = losAngeles
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 20)))
        let normal = try side(for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 8))), calendar: calendar, now: now)
        let spring = try side(for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 9))), calendar: calendar, now: now)

        XCTAssertEqual(normal.windowCount, 96)
        XCTAssertEqual(spring.windowCount, 92)

        let pairs = BodyStressPlotSide.trackPairs(from: normal.side, to: spring.side)
        XCTAssertEqual(pairs.filter { $0.from != nil && $0.to != nil }.count, 92)
        XCTAssertEqual(pairs.filter { $0.from != nil && $0.to == nil }.count, 4)
        XCTAssertEqual(pairs.filter { $0.from == nil && $0.to != nil }.count, 0)

        // The four unpaired outgoing slots are exactly the hour that does not exist.
        let unpaired = pairs.compactMap { $0.to == nil ? $0.from?.key : nil }
        XCTAssertEqual(Set(unpaired.map(\.hour)), [2])
        XCTAssertEqual(Set(unpaired.map(\.minute)), [0, 15, 30, 45])

        // And 03:00 really did pair with 03:00, not with 02:00.
        let threeAM = pairs.first { $0.from?.key == BodyStressPlotSlotKey(hour: 3, minute: 0, occurrence: 0) }
        XCTAssertEqual(try XCTUnwrap(threeAM?.to?.key), BodyStressPlotSlotKey(hour: 3, minute: 0, occurrence: 0))
    }

    /// Fall back: 01:00–01:45 happen twice, so the 25-hour day carries four extra
    /// slots whose `occurrence` is 1. They fade in; nothing else is disturbed.
    func testMorphPairsFallBackDayByRepeatedHourOccurrence() throws {
        let calendar = losAngeles
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 20)))
        let fallBack = try side(for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 2))), calendar: calendar, now: now)
        let normal = try side(for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 11, day: 3))), calendar: calendar, now: now)

        XCTAssertEqual(fallBack.windowCount, 100)
        XCTAssertEqual(normal.windowCount, 96)

        let pairs = BodyStressPlotSide.trackPairs(from: fallBack.side, to: normal.side)
        XCTAssertEqual(pairs.filter { $0.from != nil && $0.to != nil }.count, 96)
        XCTAssertEqual(pairs.filter { $0.from != nil && $0.to == nil }.count, 4)

        let unpaired = pairs.compactMap { $0.to == nil ? $0.from?.key : nil }
        XCTAssertEqual(Set(unpaired.map(\.occurrence)), [1])
        XCTAssertEqual(Set(unpaired.map(\.hour)), [1])
    }

    /// Today is partial, so switching from a full past day pairs only the slots
    /// today has reached and fades the rest of the afternoon out.
    func testMorphPairsPartialTodayAgainstFullDay() throws {
        let calendar = losAngeles
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 10)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 10, hour: 10)))
        let partial = try side(for: today, calendar: calendar, now: now)
        let full = try side(for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 9))), calendar: calendar, now: now)

        XCTAssertEqual(partial.windowCount, 40)
        XCTAssertEqual(full.windowCount, 96)

        let pairs = BodyStressPlotSide.trackPairs(from: partial.side, to: full.side)
        XCTAssertEqual(pairs.filter { $0.from != nil && $0.to != nil }.count, 40)
        XCTAssertEqual(pairs.filter { $0.from == nil && $0.to != nil }.count, 56)
        XCTAssertEqual(pairs.filter { $0.from != nil && $0.to == nil }.count, 0)
    }

    /// The rebase's premise: the interpolated presentation IS a side, so a second
    /// tap can hand it to the next transition as its outgoing day. Halfway between
    /// two scores the merged track sits halfway.
    func testInterpolatedSideIsItselfARebasableSide() throws {
        let calendar = losAngeles
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 20)))
        let dayInterval = try XCTUnwrap(
            calendar.dateInterval(of: .day, for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 9))))
        )
        let intervals = StressScoreCalculator.windowIntervals(for: dayInterval.start, calendar: calendar, now: now)
        let low = intervals.map { StressWindow(interval: $0, state: .scored(score: 20, hrOnly: false)) }
        let high = intervals.map { StressWindow(interval: $0, state: .scored(score: 80, hrOnly: false)) }

        let from = BodyStressPlotSide.make(windows: low, dayInterval: dayInterval, contextIntervals: [], calendar: calendar)
        let to = BodyStressPlotSide.make(windows: high, dayInterval: dayInterval, contextIntervals: [], calendar: calendar)

        let midpoint = BodyStressPlotSide.interpolated(from: from, to: to, at: 0.5, reduceMotion: false)
        XCTAssertEqual(midpoint.tracks.count, from.tracks.count)
        XCTAssertEqual(try XCTUnwrap(midpoint.tracks.first).score, 50, accuracy: 0.0001)
        XCTAssertEqual(midpoint.emptiness, 0, accuracy: 0.0001)

        // Rebasing off it pairs cleanly — every slot still matches by key.
        let rebased = BodyStressPlotSide.trackPairs(from: midpoint, to: to)
        XCTAssertEqual(rebased.filter { $0.from != nil && $0.to != nil }.count, to.tracks.count)

        // Endpoints are exact.
        XCTAssertEqual(BodyStressPlotSide.interpolated(from: from, to: to, at: 0, reduceMotion: false), from)
        XCTAssertEqual(BodyStressPlotSide.interpolated(from: from, to: to, at: 1, reduceMotion: false), to)
    }

    /// A day with nothing to draw is not a different view — it is a side whose
    /// emptiness the plot fades its internal no-data overlay with.
    func testEmptyDaySideFadesRatherThanSwappingViews() throws {
        let calendar = losAngeles
        let dayInterval = try XCTUnwrap(
            calendar.dateInterval(of: .day, for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 9))))
        )
        let empty = BodyStressPlotSide.make(windows: [], dayInterval: dayInterval, contextIntervals: [], calendar: calendar)
        let scored = BodyStressPlotSide.make(
            windows: [StressWindow(interval: DateInterval(start: dayInterval.start, duration: 900), state: .scored(score: 40, hrOnly: false))],
            dayInterval: dayInterval,
            contextIntervals: [],
            calendar: calendar
        )

        XCTAssertEqual(empty.emptiness, 1, accuracy: 0.0001)
        XCTAssertEqual(scored.emptiness, 0, accuracy: 0.0001)

        let half = BodyStressPlotSide.interpolated(from: empty, to: scored, at: 0.5, reduceMotion: false)
        XCTAssertEqual(half.emptiness, 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(half.tracks.first).opacity, 0.5, accuracy: 0.0001)
    }

    /// Reduce Motion keeps the animation but drops the geometry morph: both days'
    /// marks stay at their own positions and simply crossfade.
    func testReducedMotionCrossfadesWithoutMovingGeometry() throws {
        let calendar = losAngeles
        let dayInterval = try XCTUnwrap(
            calendar.dateInterval(of: .day, for: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 9))))
        )
        let interval = DateInterval(start: dayInterval.start, duration: 900)
        let from = BodyStressPlotSide.make(
            windows: [StressWindow(interval: interval, state: .scored(score: 20, hrOnly: false))],
            dayInterval: dayInterval,
            contextIntervals: [],
            calendar: calendar
        )
        let to = BodyStressPlotSide.make(
            windows: [StressWindow(interval: interval, state: .scored(score: 80, hrOnly: false))],
            dayInterval: dayInterval,
            contextIntervals: [],
            calendar: calendar
        )

        let half = BodyStressPlotSide.interpolated(from: from, to: to, at: 0.5, reduceMotion: true)
        XCTAssertEqual(half.tracks.count, 2)
        XCTAssertEqual(half.tracks.map(\.score), [20, 80])
        XCTAssertEqual(half.tracks[0].opacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(half.tracks[1].opacity, 0.5, accuracy: 0.0001)
    }
}
