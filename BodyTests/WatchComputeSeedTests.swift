//
//  WatchComputeSeedTests.swift
//  BodyTests
//
//  Covers `WatchComputeSeed` (Phase 1b of the on-watch realtime compute plan):
//  round-trip encode/decode, lenient decode of a payload missing newer fields
//  (the schema-evolution discipline `WatchMetricsSnapshot` already follows),
//  the sleep-history trim's equivalence with the untrimmed history for the
//  still-relevant last-7-days window, the sleep history's wider window for
//  the watch's Sleep Debt, the HR / HRV range series' one week window, the
//  compressed payload's size budget, and the
//  whole WatchConnectivity push's budget.
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

    /// A day's min/max capsule around each of `series`' daily averages.
    private func rangeSeriesFixture(around series: HealthTrendSeries, spread: Double) -> HealthTrendRangeSeries {
        HealthTrendRangeSeries(points: series.points.map { point in
            HealthTrendRangeDataPoint(
                date: point.date,
                lowValue: point.value - spread / 2,
                highValue: point.value + spread / 2,
                averageValue: point.value
            )
        })
    }

    private func recordedReadinessFixture(dayCount: Int, anchor: Date) -> [RecordedReadinessEntry] {
        let anchorDay = calendar.startOfDay(for: anchor)
        return (0..<dayCount).compactMap { age -> RecordedReadinessEntry? in
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { return nil }
            return RecordedReadinessEntry(date: day, score: 70 + (age % 20), includedSleep: true, coverage: .hrv)
        }
    }

    /// A day's Stress record as the phone persists it: every field set, with
    /// the medians at full double precision like real ones.
    private func recordedStressFixture(dayCount: Int, anchor: Date) -> [StressDaySummary] {
        let anchorDay = calendar.startOfDay(for: anchor)
        return (0..<dayCount).compactMap { age -> StressDaySummary? in
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { return nil }
            let average = 25 + (age * 13) % 50
            return StressDaySummary(
                date: day,
                averageScore: average,
                minutesByBand: [.rest: 120 + age % 7 * 15, .low: 300 - age % 5 * 15, .medium: 90 + age % 3 * 15, .high: age % 4 * 15],
                scoredWindowCount: 52 + age % 11,
                hrvCoveredWindowCount: 14 + age % 9,
                quietHRMedian: Double(58 + age % 6) + (age % 2 == 0 ? 0.5 : 0),
                rmssdDailyMedian: 36 + 7 * sin(Double(age) / 3.7),
                minScore: max(average - 22 - age % 5, 0),
                maxScore: min(average + 31 + age % 7, 100),
                activityMinutes: 30 + age % 4 * 15
            )
        }
        .sorted { $0.date < $1.date }
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
        trends.heartRateRanges = rangeSeriesFixture(around: trends.heartRate, spread: 40)
        trends.heartRateVariabilityRanges = rangeSeriesFixture(around: trends.heartRateVariability, spread: 30)
        trends.respiratoryRate = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 14, amplitude: 1)
        trends.oxygenSaturation = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 97, amplitude: 1)
        trends.trainingLoad = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 1.0, amplitude: 0.3)
        trends.wristTemperature = dailySeriesFixture(dayCount: dayCount, anchor: anchor, baseline: 36.3, amplitude: 0.3)
        trends.sleepHistory = sleepHistoryFixture(nightCount: dayCount, anchor: anchor)
        trends.recordedReadiness = recordedReadinessFixture(dayCount: dayCount, anchor: anchor)
        trends.recordedReadinessContext = "fixture-context"
        trends.recordedStressDays = recordedStressFixture(dayCount: dayCount, anchor: anchor)
        trends.recordedStressContext = "fixture-stress-context"
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

        // `publishedAt` is deliberately not transported (see `encode(to:)`), so
        // it decodes to the missing-field fallback rather than the seed's stamp.
        XCTAssertEqual(decoded.publishedAt, .distantPast)
        var expected = seed
        expected.publishedAt = .distantPast
        XCTAssertEqual(decoded, expected)
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

    /// `selectedEnergyUnitRaw` is left out of the encoding when nil (the
    /// kilocalorie case the phone sends), so a kilocalorie seed's bytes, and
    /// with them its on-disk identity, are what they were before the energy
    /// cards; a kilojoule raw round-trips.
    func testEnergyUnitRawIsOmittedWhenNilAndRoundTripsOtherwise() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let kilocalories = makeSeed(anchor: anchor)
        XCTAssertNil(kilocalories.settings.selectedEnergyUnitRaw)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(kilocalories.settings)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("selectedEnergyUnitRaw"))

        var settings = kilocalories.settings
        settings.selectedEnergyUnitRaw = BodyValueFormat.EnergyUnitPreference.kilojoules.rawValue
        // An explicit preference, like the phone's `storedEnergyUnitPreference`,
        // reads the raw only when the units don't follow the system.
        settings.followsSystemUnits = false
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WatchComputeSettings.self, from: try encoder.encode(settings))
        XCTAssertEqual(decoded.selectedEnergyUnitRaw, "kilojoules")
        XCTAssertEqual(WatchComputeAssembly.energyUnitPreference(for: decoded), .kilojoules)
        XCTAssertEqual(WatchComputeAssembly.energyUnitPreference(for: kilocalories.settings), .kilocalories)
        var explicitKilocalories = settings
        explicitKilocalories.selectedEnergyUnitRaw = nil
        XCTAssertEqual(WatchComputeAssembly.energyUnitPreference(for: explicitKilocalories), .kilocalories, "nil raw is kilocalories")
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

        var days = consistencySleepHistoryFixture(nightCount: 365, anchor: dataThrough).days
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
        XCTAssertEqual(trimmedHistory.days.count, WatchComputeSeed.sleepHistoryDayCount + 7)

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

    // MARK: - Sleep history window (watch Sleep Debt)

    func testSleepHistoryKeepsWhatTheWatchSleepDebtReadsWhileEveryOtherTrendStaysAtSeventyDays() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let anchorDay = calendar.startOfDay(for: anchor)
        let trimmed = trendsFixture(dayCount: 365, anchor: anchor).watchComputeTrimmed(anchor: anchor, calendar: calendar)

        XCTAssertEqual(WatchComputeSeed.sleepHistoryDayCount, 86)
        XCTAssertEqual(
            WatchComputeSeed.sleepHistoryDayCount,
            SleepDebtChartModel.historyDayCount(nightCount: SleepDebtChartModel.watchNightCount)
        )
        let ages = trimmed.sleepHistory.days.map { day in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: day.date), to: anchorDay).day ?? -1
        }
        XCTAssertEqual(trimmed.sleepHistory.days.count, WatchComputeSeed.sleepHistoryDayCount)
        XCTAssertEqual(ages.min(), 0)
        XCTAssertEqual(ages.max(), 85, "a night 85 days old is kept; 86 and older are dropped")

        // Every other series keeps the 70 day window, `trends.sleep` (a
        // readiness source series, whose length sets the readiness walk) too.
        let series: [(name: String, series: HealthTrendSeries)] = [
            ("sleep", trimmed.sleep),
            ("readiness", trimmed.readiness),
            ("heartRate", trimmed.heartRate),
            ("restingHeartRate", trimmed.restingHeartRate),
            ("heartRateVariability", trimmed.heartRateVariability),
            ("respiratoryRate", trimmed.respiratoryRate),
            ("oxygenSaturation", trimmed.oxygenSaturation),
            ("trainingLoad", trimmed.trainingLoad),
            ("wristTemperature", trimmed.wristTemperature)
        ]
        for (name, trend) in series {
            XCTAssertEqual(trend.points.count, WatchComputeSeed.trendDayCount, name)
        }
        XCTAssertEqual(trimmed.recordedReadiness.count, WatchComputeSeed.trendDayCount)
    }

    // MARK: - Recorded Stress days (the watch's Stress baselines)

    /// The watch holds about a week of HealthKit, so its Stress baselines (the
    /// 56 days before each scored day) and week come from these records: whole,
    /// for the last 60 days ending at the anchor, with their context.
    func testRecordedStressDaysKeepSixtyWholeDaysEndingAtTheAnchor() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let anchorDay = calendar.startOfDay(for: anchor)
        var full = trendsFixture(dayCount: 365, anchor: anchor)
        // A record past the anchor isn't the seed's: the seed is as of `dataThrough`.
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: anchorDay))
        full.recordedStressDays.append(StressDaySummary(date: tomorrow, averageScore: 50))

        let trimmed = full.watchComputeTrimmed(anchor: anchor, calendar: calendar)

        XCTAssertEqual(WatchComputeSeed.stressRecordDayCount, 60)
        XCTAssertGreaterThan(WatchComputeSeed.stressRecordDayCount, ReadinessScoreCalculator.baselineDayCount)
        XCTAssertEqual(trimmed.recordedStressDays.count, WatchComputeSeed.stressRecordDayCount)
        let ages = trimmed.recordedStressDays.map { entry in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.date), to: anchorDay).day ?? -1
        }
        XCTAssertEqual(ages.min(), 0)
        XCTAssertEqual(ages.max(), 59, "a day 59 days old is kept; 60 and older are dropped")
        XCTAssertEqual(
            trimmed.recordedStressDays,
            Array(full.recordedStressDays.filter { $0.date <= anchorDay }.suffix(WatchComputeSeed.stressRecordDayCount)),
            "whole records, not slimmed"
        )
        XCTAssertEqual(trimmed.recordedStressContext, "fixture-stress-context")
        // The series are rebuilt from the records on the watch, never shipped.
        XCTAssertTrue(trimmed.stress.points.isEmpty)
        XCTAssertTrue(trimmed.stressRanges.points.isEmpty)
        XCTAssertTrue(trimmed.heartRateDaySamples.points.isEmpty)
    }

    // MARK: - Range series window (HR / HRV week chart capsules)

    /// The capsules ride the seed for one week only: the builder reads them
    /// through `.recentWeek`, and the delta re-reads the days after the seed.
    func testHeartRateRangesKeepExactlyTheLastSevenDays() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let anchorDay = calendar.startOfDay(for: anchor)
        let full = trendsFixture(dayCount: 365, anchor: anchor)
        let trimmed = full.watchComputeTrimmed(anchor: anchor, calendar: calendar)

        let ranges: [(name: String, full: HealthTrendRangeSeries, trimmed: HealthTrendRangeSeries)] = [
            ("heartRateRanges", full.heartRateRanges, trimmed.heartRateRanges),
            ("heartRateVariabilityRanges", full.heartRateVariabilityRanges, trimmed.heartRateVariabilityRanges)
        ]
        for (name, fullSeries, trimmedSeries) in ranges {
            XCTAssertEqual(fullSeries.points.count, 365, name)
            XCTAssertEqual(trimmedSeries.points.count, BodyHealthTrendRange.recentWeek.dayCount, name)
            let ages = trimmedSeries.points.map { point in
                calendar.dateComponents([.day], from: calendar.startOfDay(for: point.date), to: anchorDay).day ?? -1
            }
            XCTAssertEqual(ages.min(), 0, name)
            XCTAssertEqual(ages.max(), 6, "\(name): a day 6 days old is kept; 7 and older are dropped")
            XCTAssertEqual(trimmedSeries, fullSeries.limited(to: .recentWeek, calendar: calendar, date: anchor), name)
        }
    }

    /// The trim happens once, at `dataThrough`, and the watch computes from
    /// the seed for up to a week after: across that week its Sleep Debt must
    /// read the same nights (day, stored duration, sleep HRV) from the trimmed
    /// history as from the phone's full one, collapsed nights included.
    func testTrimmedSleepHistoryFeedsTheWatchSleepDebtWhatTheFullHistoryDoes() throws {
        let dataThrough = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let dataThroughDay = calendar.startOfDay(for: dataThrough)
        let fullHistory = sleepHistoryFixture(nightCount: 365, anchor: dataThrough)
        let trimmedHistory = fullHistory.watchComputeTrimmed(anchor: dataThrough, calendar: calendar)

        func inputs(_ history: SleepHistorySnapshot, today: Date) -> SleepDebtChartModel.Inputs {
            SleepDebtChartModel.inputs(
                sleepHistory: history,
                currentDaySummary: nil,
                trainingLoad: .empty,
                nightCount: SleepDebtChartModel.watchNightCount,
                today: today,
                calendar: calendar
            )
        }

        for aheadOffset in 0...7 {
            let today = try XCTUnwrap(calendar.date(byAdding: .day, value: aheadOffset, to: dataThrough))
            XCTAssertEqual(
                inputs(trimmedHistory, today: today),
                inputs(fullHistory, today: today),
                "\(aheadOffset) day(s) after dataThrough"
            )
        }

        // Negative control: the old 70 day trim drops nights the debt reads.
        let seventyDayHistory = SleepHistorySnapshot(days: trimmedHistory.days.filter { day in
            let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: day.date), to: dataThroughDay).day ?? 0
            return age < WatchComputeSeed.trendDayCount
        })
        XCTAssertNotEqual(inputs(seventyDayHistory, today: dataThrough), inputs(fullHistory, today: dataThrough))
    }

    // MARK: - Size

    func testCompressedRealisticSeedFixtureStaysUnderFiftyKilobytes() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let seed = makeSeed(anchor: anchor, dayCount: 365)
        XCTAssertEqual(seed.trends.sleepHistory.days.count, WatchComputeSeed.sleepHistoryDayCount)

        let compressed = try XCTUnwrap(seed.encodedCompressed())
        XCTAssertLessThan(compressed.count, 50_000, "compressed seed was \(compressed.count) bytes, expected under 50 KB")
    }

    /// The publisher budgets the WHOLE application context (display snapshot,
    /// permission key and seed together) and silently drops the seed past it,
    /// which stops every watch compute. So the seed is measured with a
    /// realistic display snapshot on top: Sleep Debt, Day Ring workouts, a 15
    /// segment night and every metric's week, sized the way `send` sizes them
    /// (the snapshot as uncompressed JSON). Keeps 5 KB of headroom, below
    /// which the seed's oldest nights should shed their collapsed segment.
    func testWholePushWithTheRealisticSeedFitsTheContextBudget() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 8)))
        let seed = makeSeed(anchor: anchor, dayCount: 365)
        let seedSize = try XCTUnwrap(seed.encodedCompressed()).count

        var trends = trendsFixture(dayCount: 365, anchor: anchor)
        var summary = HealthSummarySnapshot.placeholder
        summary.sleep = try XCTUnwrap(trends.sleepHistory.summary(on: anchor, calendar: calendar)).summary
        // Stress with its week and daily ranges, and a full "Last 12 hours".
        summary.stress = trends.recordedStressDays.last
        summary.stressCurrentScore = 64
        trends.stress = HealthTrendSeries(points: trends.recordedStressDays.compactMap { entry in
            entry.averageScore.map { HealthTrendDataPoint(date: entry.date, value: Double($0)) }
        })
        trends.stressRanges = HealthTrendRangeSeries(points: trends.recordedStressDays.compactMap { entry in
            guard let low = entry.minScore, let high = entry.maxScore else { return nil }
            return HealthTrendRangeDataPoint(
                date: entry.date, lowValue: Double(low), highValue: Double(high),
                averageValue: entry.averageScore.map(Double.init)
            )
        })
        let timelineSlotCount = Int(WatchStressTimelineBuilder.span / WatchStressTimeline.slotLength) + 1
        let timelineStart = anchor.addingTimeInterval(-WatchStressTimelineBuilder.span)
        let stressTimeline = WatchStressTimeline(
            start: timelineStart,
            end: anchor,
            slots: (0..<timelineSlotCount).map { index -> Int? in
                switch index % 12 {
                case 5: return nil
                case 9, 10: return WatchStressTimeline.activityMarker
                default: return 12 + (index * 17) % 85
                }
            },
            context: [
                WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: timelineStart, end: timelineStart.addingTimeInterval(3 * 3_600)),
                WatchStressContextBand(kind: WatchStressContextBand.workoutKind, start: anchor.addingTimeInterval(-4 * 3_600), end: anchor.addingTimeInterval(-3 * 3_600), workoutType: "running"),
                WatchStressContextBand(kind: WatchStressContextBand.napKind, start: anchor.addingTimeInterval(-3_600), end: anchor.addingTimeInterval(-1_800))
            ],
            computedAt: anchor
        )
        var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary,
            trends: trends,
            lastRefreshDate: anchor,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: anchor,
            workoutWeeklyMinutes: [30, 0, 45, 22, 0, 38, 15],
            seriesRangeOverride: { seed.seriesRanges[$0] },
            includesSleepDebt: true,
            stressTimeline: stressTimeline,
            workoutColorOverrides: "cycling:EE9D58,hiking:2E8B57,running:335BB0,swimming:1E90FF,yoga:9370DB"
        )
        snapshot.source = "phone"
        snapshot.showsSleepDebt = true
        snapshot.readinessHeroShowsLevel = true
        snapshot.homeHero = "dayRing"
        snapshot.dayRingShowsCaption = true
        snapshot.dayRingWorkouts = (0..<4).map { index in
            let start = anchor.addingTimeInterval(Double(index * 5 - 20) * 3_600)
            return WatchDayRingWorkout(
                id: UUID().uuidString,
                type: "running",
                startDate: start,
                endDate: start.addingTimeInterval(45 * 60),
                colorHex: 0xFF5A1F
            )
        }
        snapshot.sleepStages = WatchMetricsSnapshot.placeholder.sleepStages
        snapshot.publisherEpoch = UUID().uuidString
        snapshot.revision = 12_345
        XCTAssertEqual(snapshot.sleepStages?.count, 15)
        XCTAssertEqual(snapshot.sleepDebt?.nights.count, SleepDebtChartModel.watchNightCount)
        let stress = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertTrue(stress.hasValue)
        XCTAssertNotNil(stress.statusBand)
        XCTAssertEqual(stress.weeklyRanges?.compactMap { $0 }.count, 7)
        XCTAssertEqual(snapshot.stressTimeline?.slots.count, timelineSlotCount)
        XCTAssertEqual(seed.trends.recordedStressDays.count, WatchComputeSeed.stressRecordDayCount)

        let snapshotSize = try XCTUnwrap(snapshot.encoded()).count
        let permissionSize = BodyHealthPermissionSelection.defaultRawValue.utf8.count
        let total = snapshotSize + permissionSize + seedSize
        let budget = WatchConnectivityPublisher.contextSizeBudgetBytes
        let headroom = budget - total
        let sizes = "snapshot \(snapshotSize) + permission \(permissionSize) + seed \(seedSize) = \(total) bytes"
        print("Watch push budget: \(sizes), headroom \(headroom) of \(budget)")

        XCTAssertTrue(
            WatchConnectivityPublisher.shouldIncludeComputeSeed(
                snapshotSize: snapshotSize,
                permissionSize: permissionSize,
                seedSize: seedSize
            ),
            "the whole push is \(sizes), \(-headroom) bytes over the \(budget) byte budget"
        )
        XCTAssertGreaterThanOrEqual(headroom, 5_000, "\(sizes) leaves \(headroom) bytes of the \(budget) byte budget")
    }
}
