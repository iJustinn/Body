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
//  draws.
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
}
