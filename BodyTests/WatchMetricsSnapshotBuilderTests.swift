//
//  WatchMetricsSnapshotBuilderTests.swift
//  BodyTests
//
//  Covers the Phase 1d additions to `WatchMetricsSnapshotBuilder`:
//  `seriesRangeOverride`'s union-with-local-series behavior, `perKindDataAsOf`
//  per-metric `computedAt` stamping, `seriesRanges(from:)`, and — critically —
//  that passing `nil` for both new parameters reproduces `makeSnapshot`'s
//  prior output exactly (the existing iOS call sites don't pass them yet).
//  Also covers the `sleepStages` payload the watch Sleep Stages complication
//  draws, the Sleep page's `sleepDebt`, and the Heart Rate / HRV week charts'
//  `weeklyRanges`.
//

import XCTest
@testable import Body

final class WatchMetricsSnapshotBuilderTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func series(_ values: [Double], endingAt anchor: Date) -> HealthTrendSeries {
        let anchorDay = calendar.startOfDay(for: anchor)
        return HealthTrendSeries(points: values.enumerated().map { offset, value in
            HealthTrendDataPoint(date: calendar.date(byAdding: .day, value: -(values.count - 1 - offset), to: anchorDay)!, value: value)
        })
    }

    private func fixture(anchor: Date) -> (summary: HealthSummarySnapshot, trends: HealthTrendSnapshot) {
        var trends = HealthTrendSnapshot.empty
        trends.heartRate = series([58, 60, 62, 64, 66], endingAt: anchor)
        trends.heartRateVariability = series([50, 52, 54, 56, 58], endingAt: anchor)
        trends.restingHeartRate = series([54, 55, 56, 57, 58], endingAt: anchor)
        trends.wristTemperature = series([36.0, 36.1, 36.2, 36.3, 36.4], endingAt: anchor)

        var summary = HealthSummarySnapshot.placeholder
        summary.heartRate = HealthMetricSummary(value: 66)
        summary.heartRateVariability = HealthMetricSummary(value: 58)
        summary.restingHeartRate = HealthMetricSummary(value: 58)
        summary.wristTemperature = HealthMetricSummary(value: 36.4)
        return (summary, trends)
    }

    private func makeSnapshot(
        anchor: Date,
        seriesRangeOverride: ((String) -> WatchSeriesRange?)? = nil,
        perKindDataAsOf: ((String) -> Date?)? = nil
    ) -> WatchMetricsSnapshot {
        let (summary, trends) = fixture(anchor: anchor)
        return WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary,
            trends: trends,
            lastRefreshDate: anchor,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: anchor,
            seriesRangeOverride: seriesRangeOverride,
            perKindDataAsOf: perKindDataAsOf
        )
    }

    // MARK: - Default nil ⇒ unchanged behavior

    func testNilOverridesReproduceTheSameSnapshotAsOmittingThem() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let (summary, trends) = fixture(anchor: anchor)

        let withoutNewParams = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary, trends: trends, lastRefreshDate: anchor,
            permissionSelection: .defaultValue, temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600, now: anchor
        )
        let withExplicitNils = makeSnapshot(anchor: anchor, seriesRangeOverride: nil, perKindDataAsOf: nil)

        XCTAssertEqual(withoutNewParams, withExplicitNils)
    }

    func testBuilderStampsMeasuredAtForSampleHeadlineVitalsOnly() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let measured = anchor.addingTimeInterval(-1_800)
        let (baseSummary, trends) = fixture(anchor: anchor)
        var summary = baseSummary
        summary.heartRate = HealthMetricSummary(value: 66, measuredAt: measured)

        let snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary, trends: trends, lastRefreshDate: anchor,
            permissionSelection: .defaultValue, temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600, now: anchor
        )

        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.heartRate)?.measuredAt, measured)
        XCTAssertNil(
            snapshot.metric(forKind: WatchMetricKindKey.heartRateVariability)?.measuredAt,
            "no sample timestamp in the summary ⇒ none on the metric"
        )
        XCTAssertNil(
            snapshot.metric(forKind: WatchMetricKindKey.readiness)?.measuredAt,
            "computed metrics carry no event watermark — computedAt is their honest stamp"
        )
    }

    // MARK: - seriesRangeOverride union

    func testSeriesRangeOverrideWidensBoundsBeyondLocalSeries() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        // Local heartRate series spans 58...66; the override widens it to 40...100.
        let snapshot = makeSnapshot(anchor: anchor, seriesRangeOverride: { kind in
            kind == WatchMetricKindKey.heartRate ? WatchSeriesRange(min: 40, max: 100) : nil
        })

        let heartRate = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(heartRate.rangeMin, 40)
        XCTAssertEqual(heartRate.rangeMax, 100)
        // The fill must be computed against the UNIONED bounds, not the local
        // 58...66 range: value 66 in 40...100 is (66-40)/(100-40) ≈ 0.4333, NOT
        // the local-bounds (66-58)/(66-58) = 1.0 a bug computing the fraction
        // before applying the override would produce.
        XCTAssertEqual(heartRate.fillFraction, (66.0 - 40.0) / (100.0 - 40.0), accuracy: 1e-9)
    }

    func testSeriesRangeOverrideNarrowerThanLocalSeriesDoesNotShrinkTheRange() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        // Override is NARROWER than the local 58...66 series — union must keep
        // the wider local bounds, never shrink below what local data already shows.
        let snapshot = makeSnapshot(anchor: anchor, seriesRangeOverride: { kind in
            kind == WatchMetricKindKey.heartRate ? WatchSeriesRange(min: 60, max: 62) : nil
        })

        let heartRate = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(heartRate.rangeMin, 58)
        XCTAssertEqual(heartRate.rangeMax, 66)
        // Fill must be computed against the (unchanged) local bounds, not the
        // narrower override — value 66 is the local series max, so a correct
        // union keeps the fraction at a full ring.
        XCTAssertEqual(heartRate.fillFraction, 1.0, accuracy: 1e-9)
    }

    func testSeriesRangeOverrideAppliesToWristTemperatureInTheRawCelsiusDomain() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        // Local wristTemperature series (Celsius) spans 36.0...36.4.
        let snapshot = makeSnapshot(anchor: anchor, seriesRangeOverride: { kind in
            kind == WatchMetricKindKey.wristTemperature ? WatchSeriesRange(min: 35.0, max: 36.4) : nil
        })

        let skinTemp = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.wristTemperature))
        XCTAssertEqual(skinTemp.rangeMin, 35.0)
        XCTAssertEqual(skinTemp.rangeMax, 36.4)
        // The fraction is computed in the same raw-Celsius domain as the range
        // (36.4 is both the local max and the union max, so a correct
        // implementation lands at a full ring here too).
        XCTAssertEqual(skinTemp.fillFraction, 1.0, accuracy: 1e-9)
    }

    // MARK: - seriesRanges(from:)

    func testSeriesRangesFromTrendsMatchesTheBuiltMetricsRanges() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let (_, trends) = fixture(anchor: anchor)

        let ranges = WatchMetricsSnapshotBuilder.seriesRanges(from: trends)

        XCTAssertEqual(ranges[WatchMetricKindKey.heartRate], WatchSeriesRange(min: 58, max: 66))
        XCTAssertEqual(ranges[WatchMetricKindKey.heartRateVariability], WatchSeriesRange(min: 50, max: 58))
        XCTAssertEqual(ranges[WatchMetricKindKey.restingHeartRate], WatchSeriesRange(min: 54, max: 58))
        XCTAssertEqual(ranges[WatchMetricKindKey.wristTemperature], WatchSeriesRange(min: 36.0, max: 36.4))
        // Readiness/Sleep/Training Load use fixed bounds, not series ranges.
        XCTAssertNil(ranges[WatchMetricKindKey.readiness])
        XCTAssertNil(ranges[WatchMetricKindKey.trainingLoad])
    }

    // MARK: - perKindDataAsOf stamping

    func testPerKindDataAsOfStampsOnlyTheProvidedKindsAndFallsBackToLastRefreshDate() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let heartRateStamp = try XCTUnwrap(calendar.date(byAdding: .minute, value: -5, to: anchor))

        let snapshot = makeSnapshot(anchor: anchor, perKindDataAsOf: { kind in
            kind == WatchMetricKindKey.heartRate ? heartRateStamp : nil
        })

        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.heartRate)?.computedAt, heartRateStamp)
        // Every other kind falls back to the uniform `lastRefreshDate` (== anchor here).
        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.heartRateVariability)?.computedAt, anchor)
        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.readiness)?.computedAt, anchor)
    }

    // MARK: - weeklyRanges (Heart Rate / HRV week chart capsules)

    /// Range points keyed by day offset from `anchor` (0 = today).
    private func ranges(_ byOffset: [Int: (low: Double, high: Double)], endingAt anchor: Date) -> HealthTrendRangeSeries {
        let anchorDay = calendar.startOfDay(for: anchor)
        return HealthTrendRangeSeries(points: byOffset.keys.sorted().map { offset in
            let range = byOffset[offset]!
            return HealthTrendRangeDataPoint(
                date: calendar.date(byAdding: .day, value: offset, to: anchorDay)!,
                lowValue: range.low,
                highValue: range.high,
                averageValue: (range.low + range.high) / 2
            )
        })
    }

    func testHeartRateAndHRVCarrySevenWeeklyRangeSlotsAlignedWithWeekly() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let (summary, baseTrends) = fixture(anchor: anchor)
        var trends = baseTrends
        trends.heartRateRanges = ranges([
            -9: (40, 140),  // before the week: never drawn
            -4: (50, 70),
            -3: (52, 72),
            // -2 has an average (62) but no range.
            -1: (.nan, 76), // a non-finite bound is no capsule
            0: (55, 80)
        ], endingAt: anchor)
        trends.heartRateVariabilityRanges = ranges([-6: (30, 70), 0: (40, 75)], endingAt: anchor)

        let snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary, trends: trends, lastRefreshDate: anchor,
            permissionSelection: .defaultValue, temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600, now: anchor
        )

        let heartRate = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(heartRate.weekly, [nil, nil, 58, 60, 62, 64, 66])
        XCTAssertEqual(heartRate.weeklyRanges, [
            nil, nil,
            WatchDayRange(low: 50, high: 70),
            WatchDayRange(low: 52, high: 72),
            nil,
            nil,
            WatchDayRange(low: 55, high: 80)
        ])
        XCTAssertEqual(
            snapshot.metric(forKind: WatchMetricKindKey.heartRateVariability)?.weeklyRanges,
            [WatchDayRange(low: 30, high: 70), nil, nil, nil, nil, nil, WatchDayRange(low: 40, high: 75)]
        )
        for kind in [
            WatchMetricKindKey.readiness, WatchMetricKindKey.sleep, WatchMetricKindKey.restingHeartRate,
            WatchMetricKindKey.trainingLoad, WatchMetricKindKey.wristTemperature
        ] {
            let metric = try XCTUnwrap(snapshot.metric(forKind: kind), kind)
            XCTAssertNil(metric.weeklyRanges, kind)
        }
    }

    func testWeeklyRangesAreNilWithoutARangeInTheWeek() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let empty = makeSnapshot(anchor: anchor)
        XCTAssertNil(empty.metric(forKind: WatchMetricKindKey.heartRate)?.weeklyRanges)
        XCTAssertNil(empty.metric(forKind: WatchMetricKindKey.heartRateVariability)?.weeklyRanges)

        // Only older days: seven nil slots would be the same as none.
        let (summary, baseTrends) = fixture(anchor: anchor)
        var trends = baseTrends
        trends.heartRateRanges = ranges([-8: (50, 70), -7: (52, 72)], endingAt: anchor)
        let stale = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary, trends: trends, lastRefreshDate: anchor,
            permissionSelection: .defaultValue, temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600, now: anchor
        )
        XCTAssertNil(stale.metric(forKind: WatchMetricKindKey.heartRate)?.weeklyRanges)
    }

    // MARK: - Sleep stages (watch Sleep Stages complication)

    private func moment(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour, minute: minute))!
    }

    /// A night dated `night` with a main session of 23:00 to 06:30 plus an
    /// afternoon nap outside it — the nap is exactly what `mainSession` filters.
    private func nightSummary(night: Date) -> SleepSummary {
        SleepSummary(
            duration: 7 * 3_600,
            stageSnapshot: SleepStageSnapshot(
                date: night,
                segments: [
                    SleepStageSegment(stage: .core, startDate: moment(day: 16, hour: 23), endDate: moment(day: 17, hour: 1)),
                    SleepStageSegment(stage: .deep, startDate: moment(day: 17, hour: 1), endDate: moment(day: 17, hour: 2)),
                    SleepStageSegment(stage: .rem, startDate: moment(day: 17, hour: 2), endDate: moment(day: 17, hour: 3)),
                    SleepStageSegment(stage: .core, startDate: moment(day: 17, hour: 3), endDate: moment(day: 17, hour: 6, minute: 30)),
                    SleepStageSegment(stage: .core, startDate: moment(day: 17, hour: 14), endDate: moment(day: 17, hour: 14, minute: 40))
                ],
                mainSessionInterval: DateInterval(
                    start: moment(day: 16, hour: 23),
                    end: moment(day: 17, hour: 6, minute: 30)
                )
            )
        )
    }

    private func sleepSnapshot(
        night: Date,
        now: Date,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue
    ) -> WatchMetricsSnapshot {
        var summary = HealthSummarySnapshot.placeholder
        summary.sleep = nightSummary(night: night)
        return WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary,
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: permissionSelection,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: now
        )
    }

    func testSleepStagesCarryTheMainSessionOnly() throws {
        let night = moment(day: 17, hour: 7)
        let stages = try XCTUnwrap(sleepSnapshot(night: night, now: moment(day: 17, hour: 18)).sleepStages)

        XCTAssertEqual(stages.map(\.stage), ["core", "deep", "rem", "core"], "the 14:00 nap is not part of the night")
        XCTAssertEqual(stages.first?.startDate, moment(day: 16, hour: 23))
        XCTAssertEqual(stages.last?.endDate, moment(day: 17, hour: 6, minute: 30))
        XCTAssertFalse(
            stages.contains { $0.startDate == moment(day: 17, hour: 14) },
            "naps stay out of the complication's bar, matching the iPhone Sleep Stages widget"
        )
    }

    func testSleepStagesAreAbsentWhenSleepIsNotAPermittedCategory() {
        let night = moment(day: 17, hour: 7)
        let snapshot = sleepSnapshot(
            night: night,
            now: moment(day: 17, hour: 18),
            permissionSelection: BodyHealthPermissionSelection.defaultValue.setting(.sleep, isEnabled: false)
        )

        XCTAssertNil(snapshot.sleepStages)
        XCTAssertNil(snapshot.metric(forKind: WatchMetricKindKey.sleep), "the whole category is omitted")
    }

    func testSleepStagesAreAbsentWhenTheNightIsNoLongerTodays() {
        // After midnight, before tonight's own session exists: `SleepSummary.asOf`
        // rejects the night, so no bar may ride along with the blanked card.
        let snapshot = sleepSnapshot(night: moment(day: 17, hour: 7), now: moment(day: 18, hour: 9))

        XCTAssertNil(snapshot.sleepStages)
        XCTAssertNil(snapshot.sleepNight)
        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.sleep)?.displayValue, "--")
    }

    // MARK: - Sleep Debt (watch Sleep page)

    /// 20 nights of 7h45m ending on `anchor`'s day: too few to learn a need,
    /// so each night needs the 8 hour goal and every compared night's full
    /// 14 night window is 3h30m short.
    private func sleepDebtHistory(anchor: Date) -> SleepHistorySnapshot {
        let anchorDay = calendar.startOfDay(for: anchor)
        return SleepHistorySnapshot(days: (0..<20).map { age in
            let day = calendar.date(byAdding: .day, value: -age, to: anchorDay)!
            return SleepDaySummary(
                date: day,
                summary: SleepSummary(duration: 7.75 * 3_600, stageSnapshot: SleepStageSnapshot(date: day, segments: []))
            )
        })
    }

    private func sleepDebtSnapshot(
        anchor: Date,
        includesSleepDebt: Bool = true,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue,
        perKindDataAsOf: ((String) -> Date?)? = nil
    ) -> WatchMetricsSnapshot {
        let history = sleepDebtHistory(anchor: anchor)
        var trends = HealthTrendSnapshot.empty
        trends.sleepHistory = history
        var summary = HealthSummarySnapshot.placeholder
        summary.sleep = history.days[0].summary
        return WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary,
            trends: trends,
            lastRefreshDate: anchor,
            permissionSelection: permissionSelection,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: anchor,
            perKindDataAsOf: perKindDataAsOf,
            includesSleepDebt: includesSleepDebt
        )
    }

    func testSleepDebtIsBuiltOnlyWhenAskedForAndSleepIsPermitted() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))

        XCTAssertNotNil(sleepDebtSnapshot(anchor: anchor).sleepDebt)
        XCTAssertNil(sleepDebtSnapshot(anchor: anchor, includesSleepDebt: false).sleepDebt)
        XCTAssertNil(
            sleepDebtSnapshot(
                anchor: anchor,
                permissionSelection: BodyHealthPermissionSelection.defaultValue.setting(.sleep, isEnabled: false)
            ).sleepDebt
        )
        // The default leaves it out, so existing callers pay nothing for it.
        XCTAssertNil(makeSnapshot(anchor: anchor).sleepDebt)
    }

    func testSleepDebtCarriesTheLastFourteenNightsOfTheSharedModel() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let history = sleepDebtHistory(anchor: anchor)
        let nightCount = SleepDebtChartModel.watchNightCount
        let model = SleepDebtChartModel.make(
            entries: SleepDebtChartModel.entries(
                sleepHistory: history,
                currentDaySummary: history.days[0].summary,
                trainingLoad: .empty,
                nightCount: nightCount,
                today: anchor,
                calendar: calendar
            ),
            sleepGoal: 8 * 3_600,
            nightCount: nightCount
        )

        let debt = try XCTUnwrap(sleepDebtSnapshot(anchor: anchor).sleepDebt)

        XCTAssertEqual(debt.nights.count, nightCount)
        XCTAssertEqual(debt.nights.map(\.day), model.nights.map(\.day))
        XCTAssertEqual(debt.nights.map(\.debt), model.nights.map(\.debtAfterNight))
        XCTAssertEqual(debt.nights.map(\.isRecorded), model.nights.map(\.isRecorded))
        XCTAssertEqual(debt.debt, model.debt)
        XCTAssertEqual(debt.nights.last?.day, calendar.startOfDay(for: anchor), "the nights end on the build day")
        XCTAssertEqual(try XCTUnwrap(debt.debt), 3.5 * 3_600, accuracy: 0.001)
        XCTAssertTrue(debt.hasChartableNight)
    }

    func testSleepDebtIsStampedWithTheNewerOfTheSleepAndTrainingLoadCutoffs() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 9)))
        let earlier = anchor.addingTimeInterval(-3_600)
        let later = anchor.addingTimeInterval(-600)
        let afterRefresh = anchor.addingTimeInterval(600)
        func computedAt(sleepAsOf: Date?, trainingLoadAsOf: Date?) -> Date? {
            sleepDebtSnapshot(anchor: anchor, perKindDataAsOf: { kind in
                switch kind {
                case WatchMetricKindKey.sleep: return sleepAsOf
                case WatchMetricKindKey.trainingLoad: return trainingLoadAsOf
                default: return nil
                }
            }).sleepDebt?.computedAt
        }

        XCTAssertEqual(sleepDebtSnapshot(anchor: anchor).sleepDebt?.computedAt, anchor, "no per kind stamps: the refresh date")
        XCTAssertEqual(computedAt(sleepAsOf: earlier, trainingLoadAsOf: later), later)
        XCTAssertEqual(computedAt(sleepAsOf: later, trainingLoadAsOf: earlier), later)
        // Sleep without its own stamp falls back to the refresh date, which a
        // newer Training Load stamp still beats.
        XCTAssertEqual(computedAt(sleepAsOf: nil, trainingLoadAsOf: earlier), anchor)
        XCTAssertEqual(computedAt(sleepAsOf: nil, trainingLoadAsOf: afterRefresh), afterRefresh)
    }
}

// MARK: - Stress (watch Stress page)

extension WatchMetricsSnapshotBuilderTests {
    private func stressSnapshot(
        anchor: Date,
        stress: StressDaySummary?,
        currentScore: Int? = nil,
        stressSeries: HealthTrendSeries = .empty,
        stressRanges: HealthTrendRangeSeries = .empty,
        permission: BodyHealthPermissionSelection = .init(enabledPermissions: [.heart]),
        stressTimeline: WatchStressTimeline? = nil,
        workoutColorOverrides: String? = nil
    ) -> WatchMetricsSnapshot {
        let (baseSummary, baseTrends) = fixture(anchor: anchor)
        var summary = baseSummary
        summary.stress = stress
        summary.stressCurrentScore = currentScore
        var trends = baseTrends
        trends.stress = stressSeries
        trends.stressRanges = stressRanges
        return WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary, trends: trends, lastRefreshDate: anchor,
            permissionSelection: permission, temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600, now: anchor,
            stressTimeline: stressTimeline,
            workoutColorOverrides: workoutColorOverrides
        )
    }

    /// The headline is today's average, the iPhone card's number; the band
    /// follows the latest reading while it is current.
    func testStressShowsTodaysAverageWithTheCurrentReadingsBand() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 15)))
        let today = StressDaySummary(date: calendar.startOfDay(for: anchor), averageScore: 42)

        let snapshot = stressSnapshot(anchor: anchor, stress: today, currentScore: 80)

        let stress = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertEqual(stress.title, String(localized: "Stress", table: "BodyWatchSnapshotKit"))
        XCTAssertEqual(stress.displayValue, "42")
        XCTAssertEqual(stress.unit, "")
        XCTAssertEqual(stress.score, 42)
        XCTAssertEqual(stress.rawValue, 42)
        XCTAssertEqual(stress.fillFraction, 0.42, accuracy: 1e-9)
        XCTAssertEqual(stress.rangeMin, 0)
        XCTAssertEqual(stress.rangeMax, 100)
        XCTAssertEqual(stress.levelMin, 76)
        XCTAssertEqual(stress.levelMax, 100)
        XCTAssertEqual(stress.tint, StressBand.high.watchTintComponents)
        XCTAssertEqual(stress.statusBand, WatchStatusBand(min: 75.5, max: nil, label: StressBand.high.title))
        XCTAssertNil(stress.measuredAt, "a computed metric: computedAt is its stamp")
        XCTAssertEqual(stress.computedAt, anchor)

        // No current reading (an hour without one, or a decoded summary): the
        // band is the average's.
        let averaged = try XCTUnwrap(stressSnapshot(anchor: anchor, stress: today).metric(forKind: WatchMetricKindKey.stress))
        XCTAssertEqual(averaged.displayValue, "42")
        XCTAssertEqual(averaged.levelMin, 26)
        XCTAssertEqual(averaged.levelMax, 50)
        XCTAssertEqual(averaged.tint, StressBand.low.watchTintComponents)
        XCTAssertEqual(averaged.statusBand, WatchStatusBand(min: 25.5, max: 50.5, label: StressBand.low.title))
    }

    /// A rollup that isn't today's (the summary outlived midnight) and no
    /// rollup at all both read "--" with no band, and the week still ships,
    /// stamped with the day it was built on.
    func testStressIsBlankUnlessTheRollupIsTodays() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 0, minute: 20)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: anchor)))

        for (name, rollup) in [
            ("yesterday's", StressDaySummary(date: yesterday, averageScore: 55)),
            ("none", nil),
            ("unscored today", StressDaySummary(date: calendar.startOfDay(for: anchor)))
        ] as [(String, StressDaySummary?)] {
            let snapshot = stressSnapshot(
                anchor: anchor, stress: rollup, currentScore: 60,
                stressSeries: series([40, 55], endingAt: yesterday)
            )
            let stress = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress), name)
            XCTAssertEqual(stress.displayValue, "--", name)
            XCTAssertFalse(stress.hasValue, name)
            XCTAssertNil(stress.score, name)
            XCTAssertEqual(stress.fillFraction, 0, name)
            XCTAssertNil(stress.levelMin, name)
            XCTAssertNil(stress.levelMax, name)
            XCTAssertNil(stress.tint, name)
            XCTAssertNil(stress.statusBand, name)
            XCTAssertEqual(stress.weekly, [nil, nil, nil, nil, 40, 55, nil], name)
            XCTAssertEqual(stress.weeklyAsOf, anchor, "\(name): the sanitize rule reads it")
        }
    }

    func testStressRidesTheHeartPermission() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 15)))
        let today = StressDaySummary(date: calendar.startOfDay(for: anchor), averageScore: 42)

        XCTAssertNotNil(stressSnapshot(anchor: anchor, stress: today, permission: .defaultValue).metric(forKind: WatchMetricKindKey.stress))
        let withoutHeart = stressSnapshot(
            anchor: anchor, stress: today,
            permission: BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)
        )
        XCTAssertNil(withoutHeart.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertNil(withoutHeart.metric(forKind: WatchMetricKindKey.heartRate))
    }

    /// The week chart: the daily averages and, under them, each day's min to
    /// max range, windowed alike.
    func testStressCarriesItsWeekAndDailyRanges() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 15)))
        let today = StressDaySummary(date: calendar.startOfDay(for: anchor), averageScore: 42)

        let snapshot = stressSnapshot(
            anchor: anchor, stress: today,
            stressSeries: series([70, 30, 35, 40, 45, 50, 55, 42], endingAt: anchor),
            stressRanges: ranges([-7: (5, 95), -1: (20, 70), 0: (10, 90)], endingAt: anchor)
        )

        let stress = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertEqual(stress.weekly, [30, 35, 40, 45, 50, 55, 42])
        XCTAssertEqual(stress.weeklyRanges, [
            nil, nil, nil, nil, nil,
            WatchDayRange(low: 20, high: 70),
            WatchDayRange(low: 10, high: 90)
        ])
        XCTAssertEqual(stress.weeklyAsOf, anchor)
    }

    func testStressTimelineAndWorkoutColorsAreStampedAsPassed() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 15)))
        let timeline = WatchStressTimeline(
            start: anchor.addingTimeInterval(-3_600),
            end: anchor,
            slots: [20, nil, WatchStressTimeline.activityMarker, 64],
            context: [WatchStressContextBand(kind: WatchStressContextBand.workoutKind, start: anchor.addingTimeInterval(-1_800), end: anchor.addingTimeInterval(-900), workoutType: "running")],
            computedAt: anchor
        )

        let snapshot = stressSnapshot(anchor: anchor, stress: nil, stressTimeline: timeline, workoutColorOverrides: "running:335BB0")
        XCTAssertEqual(snapshot.stressTimeline, timeline)
        XCTAssertEqual(snapshot.workoutColorOverrides, "running:335BB0")

        let omitted = stressSnapshot(anchor: anchor, stress: nil)
        XCTAssertNil(omitted.stressTimeline)
        XCTAssertNil(omitted.workoutColorOverrides)
    }

    // MARK: Display-time midnight guard

    /// A cached snapshot that outlives midnight must not headline yesterday's
    /// average as today's: `sanitized` clears it to the blank card the builder
    /// would emit, keeping the week, and leaves a same-day snapshot alone.
    func testSanitizeClearsAStressAverageBuiltOnAnEarlierDay() throws {
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 22)))
        let sameDay = anchor.addingTimeInterval(3_600)
        let afterMidnight = anchor.addingTimeInterval(2.5 * 3_600)
        let snapshot = stressSnapshot(
            anchor: anchor,
            stress: StressDaySummary(date: calendar.startOfDay(for: anchor), averageScore: 42),
            stressSeries: series([40, 42], endingAt: anchor)
        )
        let built = try XCTUnwrap(snapshot.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertTrue(built.hasValue)

        XCTAssertEqual(snapshot.sanitized(asOf: sameDay), snapshot, "still today: untouched")

        let sanitized = snapshot.sanitized(asOf: afterMidnight)
        let stress = try XCTUnwrap(sanitized.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertEqual(stress.displayValue, "--")
        XCTAssertFalse(stress.hasValue)
        XCTAssertNil(stress.score)
        XCTAssertNil(stress.statusBand)
        XCTAssertNil(stress.tint)
        XCTAssertNil(stress.levelMin)
        XCTAssertNil(stress.levelMax)
        XCTAssertEqual(stress.weekly, built.weekly, "the week stays for the chart")
        XCTAssertEqual(stress.weeklyAsOf, built.weeklyAsOf)
        XCTAssertEqual(
            sanitized.metric(forKind: WatchMetricKindKey.heartRate),
            snapshot.metric(forKind: WatchMetricKindKey.heartRate),
            "an independent rule: no other card moves"
        )
        XCTAssertEqual(sanitized.sanitized(asOf: afterMidnight), sanitized, "idempotent")

        // An unknown day reads as not today, like `sleepNight`.
        var unknownDay = snapshot
        unknownDay.metrics = snapshot.metrics.map { metric in
            var copy = metric
            if metric.kind == WatchMetricKindKey.stress { copy.weeklyAsOf = nil }
            return copy
        }
        XCTAssertEqual(unknownDay.sanitized(asOf: sameDay).metric(forKind: WatchMetricKindKey.stress)?.displayValue, "--")
    }
}
