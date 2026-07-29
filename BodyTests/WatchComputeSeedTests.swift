//
//  WatchComputeSeedTests.swift
//  BodyTests
//
//  Covers `WatchComputeSeed` (Phase 1b of the on-watch realtime compute plan):
//  round-trip encode/decode, lenient decode of a payload missing newer fields
//  (the schema-evolution discipline `WatchMetricsSnapshot` already follows),
//  the sleep-history trim's equivalence with the untrimmed history for the
//  still-relevant last-7-days window, and the compressed payload's size
//  budget.
//

import XCTest
@testable import Body

final class WatchComputeSeedTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    // MARK: - Fixture builders

    /// A single night with a configurable leading/trailing/interior awake
    /// segment threaded through a realistic multi-stage cycle (core/rem/deep),
    /// so the collapse in `SleepHistorySnapshot.watchComputeTrimmed` has real
    /// stage detail to discard.
    private func multiSegmentStageSnapshot(
        on day: Date,
        leadingAwakeMinutes: Double,
        trailingAwakeMinutes: Double,
        interiorAwakeMinutes: Double
    ) -> SleepStageSnapshot {
        var cursor = calendar.startOfDay(for: day).addingTimeInterval(23 * 3_600)
        var segments: [SleepStageSegment] = []
        func append(_ stage: SleepStage, minutes: Double) {
            guard minutes > 0 else { return }
            let end = cursor.addingTimeInterval(minutes * 60)
            segments.append(SleepStageSegment(stage: stage, startDate: cursor, endDate: end))
            cursor = end
        }
        append(.awake, minutes: leadingAwakeMinutes)
        append(.core, minutes: 90)
        append(.rem, minutes: 20)
        append(.deep, minutes: 40)
        append(.core, minutes: 60)
        append(.awake, minutes: interiorAwakeMinutes)
        append(.rem, minutes: 25)
        append(.core, minutes: 80)
        append(.deep, minutes: 30)
        append(.core, minutes: 50)
        append(.awake, minutes: trailingAwakeMinutes)
        return SleepStageSnapshot(date: day, segments: segments, timeZoneIdentifier: "America/New_York")
    }

    private func sleepDay(
        on day: Date,
        leadingAwakeMinutes: Double = 4,
        trailingAwakeMinutes: Double = 4,
        interiorAwakeMinutes: Double = 6
    ) -> SleepDaySummary {
        let stageSnapshot = multiSegmentStageSnapshot(
            on: day,
            leadingAwakeMinutes: leadingAwakeMinutes,
            trailingAwakeMinutes: trailingAwakeMinutes,
            interiorAwakeMinutes: interiorAwakeMinutes
        )
        let vitals = SleepVitalsSummary(
            heartRate: 58, heartRateVariability: 60, respiratoryRate: 14,
            oxygenSaturation: 97, wristTemperatureCelsius: 36.3
        )
        return SleepDaySummary(
            date: day,
            summary: SleepSummary(duration: stageSnapshot.mergedAsleepDuration, stageSnapshot: stageSnapshot, vitals: vitals)
        )
    }

    /// `nightCount` nights ending at `anchor` (age 0 = `anchor`'s own night).
    /// Ages 8–15 get distinct leading/trailing/interior awake placements so
    /// the trim boundary (`sleepSegmentDayCount == 15`) is exercised against
    /// real variety; every other night uses a fixed mixed pattern.
    private func sleepHistoryFixture(nightCount: Int, anchor: Date) -> SleepHistorySnapshot {
        let anchorDay = calendar.startOfDay(for: anchor)
        var days: [SleepDaySummary] = []
        for age in 0..<nightCount {
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { continue }
            switch age {
            case 8: days.append(sleepDay(on: day, leadingAwakeMinutes: 20, trailingAwakeMinutes: 0, interiorAwakeMinutes: 0))
            case 9: days.append(sleepDay(on: day, leadingAwakeMinutes: 0, trailingAwakeMinutes: 0, interiorAwakeMinutes: 0))
            case 10: days.append(sleepDay(on: day, leadingAwakeMinutes: 0, trailingAwakeMinutes: 20, interiorAwakeMinutes: 0))
            case 11: days.append(sleepDay(on: day, leadingAwakeMinutes: 0, trailingAwakeMinutes: 0, interiorAwakeMinutes: 0))
            case 12: days.append(sleepDay(on: day, leadingAwakeMinutes: 0, trailingAwakeMinutes: 0, interiorAwakeMinutes: 25))
            case 13: days.append(sleepDay(on: day, leadingAwakeMinutes: 15, trailingAwakeMinutes: 15, interiorAwakeMinutes: 0))
            case 14: days.append(sleepDay(on: day, leadingAwakeMinutes: 0, trailingAwakeMinutes: 0, interiorAwakeMinutes: 15))
            case 15: days.append(sleepDay(on: day, leadingAwakeMinutes: 10, trailingAwakeMinutes: 10, interiorAwakeMinutes: 10))
            default: days.append(sleepDay(on: day))
            }
        }
        return SleepHistorySnapshot(days: days)
    }

    private func dailySeriesFixture(dayCount: Int, anchor: Date, baseline: Double, amplitude: Double) -> HealthTrendSeries {
        let anchorDay = calendar.startOfDay(for: anchor)
        var points: [HealthTrendDataPoint] = []
        for age in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { continue }
            let value = baseline + amplitude * sin(Double(age) / 5)
            points.append(HealthTrendDataPoint(date: day, value: value))
        }
        return HealthTrendSeries(points: points)
    }

    private func recordedReadinessFixture(dayCount: Int, anchor: Date) -> [RecordedReadinessEntry] {
        let anchorDay = calendar.startOfDay(for: anchor)
        return (0..<dayCount).compactMap { age -> RecordedReadinessEntry? in
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { return nil }
            return RecordedReadinessEntry(date: day, score: 70 + (age % 20), includedSleep: true, coverage: .hrv)
        }
    }

    /// A realistic multi-week `HealthTrendSnapshot`: populated vitals/training
    /// load series plus a multi-segment, vitals-hydrated sleep history — used
    /// both for the trim-equivalence check and (once trimmed) the size test.
    private func trendsFixture(dayCount: Int, anchor: Date) -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.readiness = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 75, amplitude: 10)
        trends.sleep = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 7.4, amplitude: 0.6)
        trends.heartRate = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 64, amplitude: 6)
        trends.restingHeartRate = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 58, amplitude: 3)
        trends.heartRateVariability = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 55, amplitude: 8)
        trends.respiratoryRate = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 14, amplitude: 1)
        trends.oxygenSaturation = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 97, amplitude: 1)
        trends.trainingLoad = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 1.0, amplitude: 0.3)
        trends.wristTemperature = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 36.3, amplitude: 0.3)
        trends.sleepHistory = sleepHistoryFixture(nightCount: dayCount, anchor: anchor)
        trends.recordedReadiness = recordedReadinessFixture(dayCount: dayCount, anchor: anchor)
        trends.recordedReadinessContext = "fixture-context"
        return trends
    }

    private func settingsFixture() -> WatchComputeSettings {
        WatchComputeSettings(
            idealSleepDurationMinutes: 480,
            followsSystemUnits: true,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.celsius.rawValue,
            showSleepScore: true,
            showsSubMinuteAwakeSleepStages: true,
            showsLeadingTrailingAwakeSleepStages: true,
            healthDataSourceSelectionRaw: "all",
            combinesHealthDataSourcesByName: false,
            recentTimeZoneIdentifiersByDay: [
                "2026-05-15": "America/New_York",
                "2026-05-16": "America/New_York",
                "2026-05-17": "America/Los_Angeles"
            ]
        )
    }

    private func makeSeed(anchor: Date, dayCount: Int = 70) -> WatchComputeSeed {
        let trimmedTrends = trendsFixture(dayCount: dayCount, anchor: anchor).watchComputeTrimmed(anchor: anchor, calendar: calendar)
        let dailyLoads = (0..<408).map { index in Double(index % 14 == 0 ? 45 : (index % 3 == 0 ? 12 : 0)) }
        let startDay = calendar.date(byAdding: .day, value: -407, to: calendar.startOfDay(for: anchor)) ?? anchor
        return WatchComputeSeed(
            publishedAt: anchor,
            dataThrough: anchor,
            lastVitalsRefreshDate: anchor,
            summary: .placeholder,
            trends: trimmedTrends,
            seriesRanges: WatchMetricsSnapshotBuilder.seriesRanges(from: trimmedTrends),
            trainingLoadStartDay: startDay,
            trainingLoadDailyLoads: dailyLoads,
            settings: settingsFixture(),
            settingsSignature: "sig-abc123"
        )
    }

    // MARK: - Round trip

    func testEncodedCompressedRoundTripsExactly() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let seed = makeSeed(anchor: anchor)

        let compressed = try XCTUnwrap(seed.encodedCompressed())
        let decoded = try XCTUnwrap(WatchComputeSeed.decoded(from: compressed))

        XCTAssertEqual(decoded, seed)
    }

    // MARK: - Lenient decode (schema evolution)

    func testDecodingAPayloadMissingNewerFieldsFallsBackToSafeDefaults() throws {
        // Simulates an older/partial payload: only `schemaVersion` and
        // `publishedAt` present, everything else absent.
        let minimalJSON = """
        {"schemaVersion": 1, "publishedAt": "2026-05-17T08:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchComputeSeed.self, from: Data(minimalJSON.utf8))

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.dataThrough, .distantPast)
        XCTAssertNil(decoded.lastVitalsRefreshDate)
        XCTAssertEqual(decoded.summary, .empty)
        XCTAssertEqual(decoded.trends, .empty)
        XCTAssertTrue(decoded.seriesRanges.isEmpty)
        XCTAssertNil(decoded.trainingLoadStartDay)
        XCTAssertNil(decoded.trainingLoadDailyLoads)
        XCTAssertEqual(decoded.settingsSignature, "")
        // Settings fall back to sane defaults rather than throwing.
        XCTAssertEqual(decoded.settings.idealSleepDurationMinutes, BodySleepDurationGoal.defaultMinutes)
        XCTAssertTrue(decoded.settings.followsSystemUnits)
        XCTAssertNil(decoded.settings.recentTimeZoneIdentifiersByDay)
    }

    func testDecodingAnEmptyPayloadDoesNotThrow() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(try decoder.decode(WatchComputeSeed.self, from: Data("{}".utf8)))
    }

    // MARK: - Trim equivalence (fixed dataThrough anchor, scored across the following week)

    /// Nights 8–15 (the `sleepSegmentDayCount` collapse boundary) get a HUGE
    /// (4h) leading + trailing awake buffer, unlike `sleepHistoryFixture`'s
    /// tight 23:00–23:20 defaults used elsewhere in this file. Collapsing one
    /// of these nights (one `.core` segment spanning the whole
    /// `dateInterval`, edge to edge) swallows the buffer into the "asleep"
    /// span, snapping `sleepStartDate`/`sleepEndDate` back to within minutes
    /// of the tight default cluster the OTHER nights sit at — moving the
    /// sleep-consistency category from deep in its GRADED band (45–150 min
    /// deviation) to its FULL-CREDIT band (≤45 min). A buffer just large
    /// enough to individually cross that boundary isn't enough here: the
    /// 14-night circular-average baseline dilutes any one night's shift, so
    /// the buffer has to be large enough that even averaged across the whole
    /// baseline the swing still clears the graded band — a smaller buffer
    /// (originally ~75 min) diluted down to single-digit minutes of average
    /// shift and never moved the rounded score at all.
    private func consistencySleepHistoryFixture(nightCount: Int, anchor: Date) -> SleepHistorySnapshot {
        let anchorDay = calendar.startOfDay(for: anchor)
        var days: [SleepDaySummary] = []
        for age in 0..<nightCount {
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { continue }
            if (8...15).contains(age) {
                days.append(sleepDay(on: day, leadingAwakeMinutes: 240, trailingAwakeMinutes: 240, interiorAwakeMinutes: 0))
            } else {
                days.append(sleepDay(on: day))
            }
        }
        return SleepHistorySnapshot(days: days)
    }

    /// Replicates `SleepHistorySnapshot.watchComputeTrimmed`'s per-night
    /// collapse (one `.core` segment spanning the night's full
    /// `dateInterval`) for a SPECIFIC set of ages relative to `anchor` —
    /// simulating what a smaller `sleepSegmentDayCount` (e.g. 10, instead of
    /// the real 15) would ADDITIONALLY collapse, without touching the
    /// production constant.
    private func collapsingNights(
        _ history: SleepHistorySnapshot, atAges ages: Set<Int>, relativeTo anchor: Date
    ) -> SleepHistorySnapshot {
        let anchorDay = calendar.startOfDay(for: anchor)
        let collapsedDays = history.days.map { day -> SleepDaySummary in
            let dayStart = calendar.startOfDay(for: day.date)
            let age = calendar.dateComponents([.day], from: dayStart, to: anchorDay).day ?? 0
            guard ages.contains(age), let interval = day.summary.stageSnapshot.dateInterval else { return day }
            var collapsed = day
            collapsed.summary.stageSnapshot.segments = [
                SleepStageSegment(stage: .core, startDate: interval.start, endDate: interval.end)
            ]
            return collapsed
        }
        return SleepHistorySnapshot(days: collapsedDays)
    }

    /// Production trims the sleep history ONCE, at the seed's fixed
    /// `dataThrough` anchor (`HealthKitWorkoutStore.makeComputeSeed`) — never
    /// re-trimmed as `now` advances across the following week
    /// (`WatchComputeSeed.maxComputeAge`). The old version of this test
    /// re-trimmed at EVERY scoring day with a constant backward margin, which
    /// never exercises that fixed-anchor invariant, and used bedtime buffers
    /// too tight (23:00–23:20) for a full segment collapse to move the
    /// consistency score at all. This version trims once and scores
    /// `dataThrough + 0…7` days forward, PLUS a negative control proving the
    /// test can actually detect a too-small `sleepSegmentDayCount`.
    func testTrimmedSleepHistoryProducesIdenticalScoresWhenScoredUpToSevenDaysAfterDataThrough() throws {
        let dataThrough = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let dataThroughDay = calendar.startOfDay(for: dataThrough)

        var days = consistencySleepHistoryFixture(nightCount: 30, anchor: dataThrough).days
        // A night for each of the 7 days AFTER `dataThrough` too, so scoring
        // can walk forward across the seed's whole `maxComputeAge` validity
        // window (a real watch compute at `dataThrough + N` still needs
        // "tonight"'s own sleep to score against).
        for aheadOffset in 1...7 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: aheadOffset, to: dataThroughDay))
            days.append(sleepDay(on: day))
        }
        let fullHistory = SleepHistorySnapshot(days: days)

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = dailySeriesFixture(dayCount: 37, anchor: dataThrough, baseline: 55, amplitude: 5)
        trends.restingHeartRate = dailySeriesFixture(dayCount: 37, anchor: dataThrough, baseline: 58, amplitude: 2)
        trends.sleepHistory = fullHistory

        let healthSummary = HealthSummarySnapshot.empty

        // Trim ONCE, at the fixed `dataThrough` anchor.
        let trimmedHistory = fullHistory.watchComputeTrimmed(anchor: dataThrough, calendar: calendar)

        for aheadOffset in 0...7 {
            let scoringInstant = try XCTUnwrap(calendar.date(byAdding: .day, value: aheadOffset, to: dataThrough))
            let scoringDay = calendar.startOfDay(for: scoringInstant)

            var trimmedTrends = trends
            trimmedTrends.sleepHistory = trimmedHistory

            let fullReadiness = ReadinessScoreCalculator.summary(
                on: scoringDay, healthSummary: healthSummary, trends: trends,
                calendar: calendar, today: scoringInstant
            )
            let trimmedReadiness = ReadinessScoreCalculator.summary(
                on: scoringDay, healthSummary: healthSummary, trends: trimmedTrends,
                calendar: calendar, today: scoringInstant
            )
            XCTAssertEqual(trimmedReadiness.score, fullReadiness.score, "readiness score diverged \(aheadOffset) day(s) after dataThrough")

            let night = try XCTUnwrap(fullHistory.summary(on: scoringDay, calendar: calendar))
            let fullSleepScore = SleepScoreSummary(
                sleep: night.summary, recentSleepHistory: fullHistory, on: scoringDay, calendar: calendar
            )
            let trimmedSleepScore = SleepScoreSummary(
                sleep: night.summary, recentSleepHistory: trimmedHistory, on: scoringDay, calendar: calendar
            )
            XCTAssertEqual(trimmedSleepScore?.total, fullSleepScore?.total, "sleep score diverged \(aheadOffset) day(s) after dataThrough")
        }

        // MARK: Negative control — collapsing an IN-WINDOW night must move the score.
        //
        // Simulates what a too-small `sleepSegmentDayCount` (e.g. reverting
        // the real 15 to 10) would ADDITIONALLY collapse: nights aged 10–14
        // relative to `dataThrough` are still inside the 14-day
        // sleep-consistency baseline window when scoring AT `dataThrough`
        // itself, and — thanks to this fixture's now-substantial awake
        // buffers — collapsing them measurably shifts the circular-average
        // bedtime the consistency category compares "tonight" against.
        //
        // Sleep score ONLY, not readiness: `ReadinessScoreCalculator` reads
        // each history night's `vitals`/`duration` for its own baselines
        // (`overnightSeries`), never `.stageSnapshot.segments` — those fields
        // are untouched by the collapse (`watchComputeTrimmed`'s own
        // contract), so readiness is legitimately insensitive to
        // `sleepSegmentDayCount` and asserting otherwise would be as
        // meaningless as the equivalence loop's readiness check already is
        // for this specific boundary (confirmed empirically: collapsing
        // ages 10–14 does not move the readiness score at all). The Sleep
        // card's OWN score — which explicitly runs the consistency category
        // over `sleepStartDate`/`sleepEndDate` — is where a too-small
        // `sleepSegmentDayCount` would actually surface.
        let negativeControlHistory = collapsingNights(trimmedHistory, atAges: Set(10...14), relativeTo: dataThrough)

        let realTodayNight = try XCTUnwrap(fullHistory.summary(on: dataThroughDay, calendar: calendar))
        let realSleepScore = SleepScoreSummary(
            sleep: realTodayNight.summary, recentSleepHistory: trimmedHistory, on: dataThroughDay, calendar: calendar
        )
        let negativeControlSleepScore = SleepScoreSummary(
            sleep: realTodayNight.summary, recentSleepHistory: negativeControlHistory, on: dataThroughDay, calendar: calendar
        )
        XCTAssertNotEqual(
            negativeControlSleepScore?.total, realSleepScore?.total,
            "collapsing nights still inside the 14-day consistency window must move the sleep score — otherwise this suite could not detect a too-small sleepSegmentDayCount"
        )
    }

    func testWatchComputeTrimmedCollapsesNightsAtOrPastTheBoundaryOnly() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let fullHistory = sleepHistoryFixture(nightCount: 20, anchor: anchor)
        let trimmed = fullHistory.watchComputeTrimmed(anchor: anchor, calendar: calendar)

        for age in 0..<20 {
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -age, to: calendar.startOfDay(for: anchor)))
            let original = try XCTUnwrap(fullHistory.summary(on: day, calendar: calendar))
            let collapsed = try XCTUnwrap(trimmed.summary(on: day, calendar: calendar))

            // Untouched regardless of age.
            XCTAssertEqual(collapsed.summary.duration, original.summary.duration, "age \(age)")
            XCTAssertEqual(collapsed.summary.vitals, original.summary.vitals, "age \(age)")
            XCTAssertEqual(collapsed.summary.stageSnapshot.timeZoneIdentifier, original.summary.stageSnapshot.timeZoneIdentifier, "age \(age)")

            if age < WatchComputeSeed.sleepSegmentDayCount {
                XCTAssertEqual(collapsed.summary.stageSnapshot.segments, original.summary.stageSnapshot.segments, "age \(age) should stay full detail")
            } else {
                XCTAssertEqual(collapsed.summary.stageSnapshot.segments.count, 1, "age \(age) should collapse to one segment")
                XCTAssertFalse(collapsed.summary.stageSnapshot.hasDetailedStages, "age \(age) collapsed night must not claim detailed stages")
            }
        }
    }

    // MARK: - Size

    func testCompressedRealisticSeedFixtureStaysUnderFiftyKilobytes() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let seed = makeSeed(anchor: anchor, dayCount: WatchComputeSeed.trendDayCount)

        let compressed = try XCTUnwrap(seed.encodedCompressed())
        XCTAssertLessThan(compressed.count, 50_000, "compressed seed was \(compressed.count) bytes, expected under 50 KB")
    }
}
