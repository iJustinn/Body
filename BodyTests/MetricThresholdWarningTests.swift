//
//  MetricThresholdWarningTests.swift
//  BodyTests
//
//  Covers the shared metric threshold detector (strict thresholds, workout
//  exclusion, episode grouping, chart window clamping) and the summary snapshot
//  field the home badge reads, including legacy snapshots written before it.
//

import XCTest
@testable import Body

final class MetricThresholdWarningTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func day() -> Date {
        calendar.date(from: DateComponents(year: 2025, month: 3, day: 14, hour: 12))!
    }

    private func time(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2025, month: 3, day: 14, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: dayOffset, to: base)!
    }

    private func series(_ samples: [(Date, Double)]) -> HealthTrendSeries {
        HealthTrendSeries(points: samples.map { HealthTrendDataPoint(date: $0.0, value: $0.1) })
    }

    // MARK: - Kinds

    func testKindsForMetric() {
        XCTAssertEqual(MetricThresholdWarning.kinds(for: .heartRate), [.lowHeartRate, .highHeartRate])
        XCTAssertEqual(MetricThresholdWarning.kinds(for: .oxygenSaturation), [.lowBloodOxygen])
        XCTAssertTrue(MetricThresholdWarning.kinds(for: .steps).isEmpty)
    }

    func testKindThresholds() {
        XCTAssertEqual(MetricWarningKind.lowHeartRate.defaultThreshold, 40)
        XCTAssertEqual(MetricWarningKind.highHeartRate.defaultThreshold, 120)
        XCTAssertEqual(MetricWarningKind.lowBloodOxygen.defaultThreshold, 90)
        XCTAssertFalse(MetricWarningKind.lowHeartRate.isAbove)
        XCTAssertTrue(MetricWarningKind.highHeartRate.isAbove)
        XCTAssertTrue(MetricWarningKind.highHeartRate.excludesWorkouts)
        XCTAssertFalse(MetricWarningKind.lowBloodOxygen.excludesWorkouts)
    }

    func testKindThresholdRangesContainTheirDefaults() {
        for kind in MetricWarningKind.allCases {
            XCTAssertTrue(
                kind.thresholdRange.contains(Int(kind.defaultThreshold)),
                "\(kind.rawValue) default sits outside its picker range"
            )
            XCTAssertEqual(kind.thresholdStep, 1)
        }

        XCTAssertEqual(MetricWarningKind.lowHeartRate.thresholdRange, 30...60)
        XCTAssertEqual(MetricWarningKind.highHeartRate.thresholdRange, 100...200)
        XCTAssertEqual(MetricWarningKind.lowBloodOxygen.thresholdRange, 80...95)
        XCTAssertEqual(MetricWarningKind.highHeartRate.unitLabelKey, "bpm")
        XCTAssertEqual(MetricWarningKind.lowBloodOxygen.unitLabelKey, "%")
    }

    // MARK: - Custom thresholds

    func testCustomThresholdDecidesWhichReadingsWarn() throws {
        let input = series([
            (time(8, 0), 118),
            (time(8, 10), 125)
        ])

        XCTAssertNil(
            MetricThresholdWarning.detect(
                .highHeartRate,
                in: input,
                on: day(),
                calendar: calendar,
                threshold: 130
            )
        )

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(
                .highHeartRate,
                in: input,
                on: day(),
                calendar: calendar,
                threshold: 110
            )
        )
        XCTAssertEqual(event.sampleCount, 2)
        XCTAssertEqual(event.extremeValue, 125)
        XCTAssertEqual(event.threshold, 110)
    }

    func testEventWithoutAnExplicitThresholdUsesTheKindDefault() {
        let warning = event(.lowBloodOxygen, start: time(10, 0), end: time(10, 0), extremeValue: 86, sampleCount: 1)
        XCTAssertEqual(warning.threshold, MetricWarningKind.lowBloodOxygen.defaultThreshold)
    }

    func testEventDecodesTheKindDefaultWhenTheStoredThresholdIsMissing() throws {
        let legacy = try XCTUnwrap(
            """
            {
                "kind": "highHeartRate",
                "startDate": 0,
                "endDate": 60,
                "extremeValue": 150,
                "sampleCount": 2
            }
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(MetricWarningEvent.self, from: legacy)
        XCTAssertEqual(decoded.threshold, MetricWarningKind.highHeartRate.defaultThreshold)
        XCTAssertEqual(decoded.extremeValue, 150)
    }

    func testEventRoundTripsACustomThreshold() throws {
        let warning = MetricWarningEvent(
            kind: .highHeartRate,
            startDate: time(8, 0),
            endDate: time(8, 10),
            extremeValue: 150,
            sampleCount: 2,
            threshold: 133
        )

        let decoded = try JSONDecoder().decode(
            MetricWarningEvent.self,
            from: JSONEncoder().encode(warning)
        )
        XCTAssertEqual(decoded, warning)
        XCTAssertEqual(decoded.threshold, 133)
    }

    // MARK: - Low heart rate detector

    func testEmptySeriesHasNoEvent() {
        XCTAssertNil(MetricThresholdWarning.detect(.lowHeartRate, in: .empty, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold))
    }

    func testReadingsAtOrAboveThresholdHaveNoEvent() {
        let input = series([
            (time(6, 0), 41),
            (time(6, 5), 55),
            (time(6, 10), 40.0)
        ])

        XCTAssertNil(MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold))
    }

    func testSingleLowSampleIsItsOwnEpisode() throws {
        let input = series([
            (time(6, 20), 62),
            (time(6, 25), 39),
            (time(6, 30), 58)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.kind, .lowHeartRate)
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 25))
        XCTAssertEqual(event.extremeValue, 39)
        XCTAssertEqual(event.sampleCount, 1)
    }

    func testConsecutiveLowsWithinGapFormOneEpisode() throws {
        let input = series([
            (time(6, 25), 39),
            (time(6, 40), 36),
            (time(7, 0), 38),
            (time(7, 30), 37)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(7, 30))
        XCTAssertEqual(event.extremeValue, 36)
        XCTAssertEqual(event.sampleCount, 4)
    }

    func testIsolatedClustersHoursApartReportOnlyTheEarliestEpisode() throws {
        let input = series([
            (time(6, 25), 39),
            (time(6, 35), 38),
            (time(14, 0), 30),
            (time(14, 10), 31)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 35))
        XCTAssertEqual(event.extremeValue, 38)
        XCTAssertEqual(event.sampleCount, 2)
        XCTAssertLessThan(event.endDate, time(14, 0))
    }

    func testLowsOnOtherDaysAreIgnored() throws {
        let input = series([
            (time(23, 30, dayOffset: -1), 32),
            (time(9, 0), 38),
            (time(1, 0, dayOffset: 1), 31)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.startDate, time(9, 0))
        XCTAssertEqual(event.sampleCount, 1)
    }

    func testUnsortedSamplesStillYieldTheEarliestEpisode() throws {
        let input = series([
            (time(6, 40), 36),
            (time(6, 25), 39)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 40))
        XCTAssertEqual(event.sampleCount, 2)
    }

    func testIdenticalPointsFromMultipleSourcesCountOnce() throws {
        let input = series([
            (time(6, 25), 39),
            (time(6, 25), 39),
            (time(6, 40), 36)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.sampleCount, 2)
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 40))
    }

    // MARK: - High heart rate detector

    func testHighHeartRateNeedsStrictlyAboveThreshold() {
        let input = series([
            (time(8, 0), 119),
            (time(8, 5), 120.0)
        ])

        XCTAssertNil(MetricThresholdWarning.detect(.highHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.highHeartRate.defaultThreshold))
    }

    func testHighHeartRateReportsTheMaximumOfTheEpisode() throws {
        let input = series([
            (time(8, 0), 121),
            (time(8, 10), 134),
            (time(8, 20), 125)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.highHeartRate, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.highHeartRate.defaultThreshold)
        )
        XCTAssertEqual(event.kind, .highHeartRate)
        XCTAssertEqual(event.startDate, time(8, 0))
        XCTAssertEqual(event.endDate, time(8, 20))
        XCTAssertEqual(event.extremeValue, 134)
        XCTAssertEqual(event.sampleCount, 3)
    }

    func testWorkoutIntervalsExcludeSamplesInsideThem() throws {
        let workout = DateInterval(start: time(8, 0), end: time(9, 0))
        let insideOnly = series([(time(8, 30), 150)])

        XCTAssertNil(
            MetricThresholdWarning.detect(
                .highHeartRate,
                in: insideOnly,
                on: day(),
                calendar: calendar,
                threshold: MetricWarningKind.highHeartRate.defaultThreshold,
                excluding: [workout]
            )
        )

        let mixed = series([
            (time(8, 30), 150),
            (time(9, 30), 130)
        ])
        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(
                .highHeartRate,
                in: mixed,
                on: day(),
                calendar: calendar,
                threshold: MetricWarningKind.highHeartRate.defaultThreshold,
                excluding: [workout]
            )
        )
        XCTAssertEqual(event.startDate, time(9, 30))
        XCTAssertEqual(event.extremeValue, 130)
        XCTAssertEqual(event.sampleCount, 1)
    }

    func testSampleAtTheWorkoutEndBoundaryIsExcluded() {
        // `DateInterval.contains` is inclusive of the end, so a reading stamped
        // exactly at the workout's end still belongs to the workout.
        let workout = DateInterval(start: time(8, 0), end: time(9, 0))
        let input = series([(time(9, 0), 150)])

        XCTAssertNil(
            MetricThresholdWarning.detect(
                .highHeartRate,
                in: input,
                on: day(),
                calendar: calendar,
                threshold: MetricWarningKind.highHeartRate.defaultThreshold,
                excluding: [workout]
            )
        )
    }

    // MARK: - Blood oxygen detector

    func testBloodOxygenNeedsStrictlyBelowThreshold() {
        let input = series([
            (time(10, 0), 97),
            (time(10, 30), 90.0)
        ])

        XCTAssertNil(MetricThresholdWarning.detect(.lowBloodOxygen, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowBloodOxygen.defaultThreshold))
    }

    func testBloodOxygenReportsTheMinimumOfTheEpisode() throws {
        let input = series([
            (time(10, 0), 89),
            (time(10, 20), 86)
        ])

        let event = try XCTUnwrap(
            MetricThresholdWarning.detect(.lowBloodOxygen, in: input, on: day(), calendar: calendar, threshold: MetricWarningKind.lowBloodOxygen.defaultThreshold)
        )
        XCTAssertEqual(event.kind, .lowBloodOxygen)
        XCTAssertEqual(event.extremeValue, 86)
        XCTAssertEqual(event.sampleCount, 2)
    }

    // MARK: - Chart window

    private func event(
        _ kind: MetricWarningKind = .lowHeartRate,
        start: Date,
        end: Date,
        extremeValue: Double,
        sampleCount: Int
    ) -> MetricWarningEvent {
        MetricWarningEvent(
            kind: kind,
            startDate: start,
            endDate: end,
            extremeValue: extremeValue,
            sampleCount: sampleCount
        )
    }

    func testChartWindowPadsBothSides() {
        let warning = event(start: time(6, 25), end: time(6, 35), extremeValue: 38, sampleCount: 2)
        let dayInterval = calendar.dateInterval(of: .day, for: day())!

        let window = MetricThresholdWarning.chartWindow(for: warning, clampedTo: dayInterval)
        XCTAssertEqual(window.start, time(6, 15))
        XCTAssertEqual(window.end, time(6, 45))
    }

    func testChartWindowClampsToTheDayBounds() {
        let dayInterval = calendar.dateInterval(of: .day, for: day())!
        let warning = event(
            start: dayInterval.start,
            end: dayInterval.end.addingTimeInterval(-60),
            extremeValue: 30,
            sampleCount: 5
        )

        let window = MetricThresholdWarning.chartWindow(for: warning, clampedTo: dayInterval)
        XCTAssertEqual(window.start, dayInterval.start)
        XCTAssertEqual(window.end, dayInterval.end)
        XCTAssertLessThan(window.start, window.end)
    }

    func testChartWindowFallsBackToTheDayWhenClampingDegenerates() {
        let dayInterval = calendar.dateInterval(of: .day, for: day())!
        let warning = event(
            start: dayInterval.end,
            end: dayInterval.end,
            extremeValue: 35,
            sampleCount: 1
        )

        let window = MetricThresholdWarning.chartWindow(for: warning, padding: 0, clampedTo: dayInterval)
        XCTAssertEqual(window, dayInterval)
    }

    // MARK: - Snapshot warnings

    private var lowHeartRateWarning: MetricWarningEvent {
        event(.lowHeartRate, start: time(6, 25), end: time(6, 35), extremeValue: 38, sampleCount: 2)
    }

    private var highHeartRateWarning: MetricWarningEvent {
        event(.highHeartRate, start: time(8, 0), end: time(8, 10), extremeValue: 134, sampleCount: 2)
    }

    private var lowBloodOxygenWarning: MetricWarningEvent {
        event(.lowBloodOxygen, start: time(10, 0), end: time(10, 20), extremeValue: 86, sampleCount: 2)
    }

    private func snapshotWithWarnings() -> HealthSummarySnapshot {
        var snapshot = HealthSummarySnapshot.placeholder
        snapshot.metricWarnings = [lowHeartRateWarning, highHeartRateWarning, lowBloodOxygenWarning]
        return snapshot
    }

    func testWarningLookupByKind() {
        let snapshot = snapshotWithWarnings()

        XCTAssertEqual(snapshot.warning(.highHeartRate), highHeartRateWarning)
        XCTAssertNil(HealthSummarySnapshot.placeholder.warning(.highHeartRate))
    }

    func testSnapshotRoundTripsTheWarnings() throws {
        let snapshot = snapshotWithWarnings()
        let decoded = try JSONDecoder().decode(
            HealthSummarySnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.metricWarnings, snapshot.metricWarnings)
    }

    func testSnapshotRoundTripsWithoutWarnings() throws {
        let decoded = try JSONDecoder().decode(
            HealthSummarySnapshot.self,
            from: JSONEncoder().encode(HealthSummarySnapshot.placeholder)
        )

        XCTAssertTrue(decoded.metricWarnings.isEmpty)
    }

    func testLegacySnapshotWithTheLowHeartRateKeyConverts() throws {
        var object = try snapshotObject(from: snapshotWithWarnings())
        object.removeValue(forKey: "metricWarnings")
        object["lowHeartRateEvent"] = [
            "startDate": time(6, 25).timeIntervalSinceReferenceDate,
            "endDate": time(6, 35).timeIntervalSinceReferenceDate,
            "minimumBPM": 38,
            "sampleCount": 2
        ]

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: legacy)

        XCTAssertEqual(decoded.metricWarnings, [lowHeartRateWarning])
        XCTAssertEqual(decoded.heartRate.value, HealthSummarySnapshot.placeholder.heartRate.value)
    }

    func testLegacySnapshotWithNeitherKeyDecodesToNoWarnings() throws {
        var object = try snapshotObject(from: snapshotWithWarnings())
        XCTAssertNotNil(object.removeValue(forKey: "metricWarnings"))

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: legacy)

        XCTAssertTrue(decoded.metricWarnings.isEmpty)
    }

    private func snapshotObject(from snapshot: HealthSummarySnapshot) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testWarningsDoNotMakeAnEmptySnapshotNonEmpty() {
        var snapshot = HealthSummarySnapshot.empty
        snapshot.metricWarnings = [lowHeartRateWarning]

        XCTAssertTrue(snapshot.isEmpty)
    }

    func testFilteringOutHeartClearsOnlyTheHeartRateWarnings() {
        let snapshot = snapshotWithWarnings()
        let withoutHeart = BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)

        XCTAssertEqual(snapshot.filtered(by: withoutHeart).metricWarnings, [lowBloodOxygenWarning])
        XCTAssertEqual(snapshot.filtered(by: .defaultValue).metricWarnings, snapshot.metricWarnings)
    }

    func testFilteringOutBloodOxygenClearsOnlyThatWarning() {
        let snapshot = snapshotWithWarnings()
        let withoutBloodOxygen = BodyHealthPermissionSelection.defaultValue.setting(.bloodOxygen, isEnabled: false)

        XCTAssertEqual(
            snapshot.filtered(by: withoutBloodOxygen).metricWarnings,
            [lowHeartRateWarning, highHeartRateWarning]
        )
    }

    func testFilteringOutWorkoutsClearsOnlyWorkoutDependentWarnings() {
        let snapshot = snapshotWithWarnings()
        let withoutWorkouts = BodyHealthPermissionSelection.defaultValue.setting(.workouts, isEnabled: false)

        // Without workout coverage the "outside workouts" high heart rate warning
        // can't be trusted, so it drops; the others ride their own permissions.
        XCTAssertEqual(
            snapshot.filtered(by: withoutWorkouts).metricWarnings,
            [lowHeartRateWarning, lowBloodOxygenWarning]
        )
    }

    func testWorkoutExclusionIntervalAddsRecoveryGrace() {
        let start = time(15, 0)
        let end = time(16, 0)
        let interval = MetricThresholdWarning.workoutExclusionInterval(start: start, end: end)

        XCTAssertEqual(interval.start, start)
        XCTAssertEqual(interval.end, end.addingTimeInterval(MetricThresholdWarning.workoutRecoveryGrace))
        // Cool-down readings right after the workout are still masked.
        XCTAssertNil(
            MetricThresholdWarning.detect(
                .highHeartRate,
                inSamples: [HealthTrendDataPoint(date: time(16, 20), value: 140)],
                threshold: 120,
                excluding: [interval]
            )
        )
        XCTAssertNotNil(
            MetricThresholdWarning.detect(
                .highHeartRate,
                inSamples: [HealthTrendDataPoint(date: time(16, 45), value: 140)],
                threshold: 120,
                excluding: [interval]
            )
        )
    }

    func testWorkoutEffectiveEndDatePrefersHealthKitEndOverDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // A paused run: 30 min of active duration but it really ended 45 min later.
        let paused = WorkoutSummary(type: .running, startDate: start, duration: 30 * 60, endDate: start.addingTimeInterval(45 * 60))
        XCTAssertEqual(paused.effectiveEndDate, start.addingTimeInterval(45 * 60))

        let legacy = WorkoutSummary(type: .running, startDate: start, duration: 30 * 60)
        XCTAssertEqual(legacy.effectiveEndDate, start.addingTimeInterval(30 * 60))
    }

    func testReplacingHeartRateReplacesOnlyTheHeartRateWarnings() {
        var stale = HealthSummarySnapshot.placeholder
        stale.metricWarnings = [
            event(.lowHeartRate, start: time(3, 0), end: time(3, 0), extremeValue: 30, sampleCount: 1),
            lowBloodOxygenWarning
        ]
        var refreshed = HealthSummarySnapshot.placeholder
        refreshed.metricWarnings = [lowHeartRateWarning, highHeartRateWarning]

        let merged = stale.replacingMetric(.heartRate, with: refreshed)
        XCTAssertEqual(merged.warning(.lowHeartRate), lowHeartRateWarning)
        XCTAssertEqual(merged.warning(.highHeartRate), highHeartRateWarning)
        XCTAssertEqual(merged.warning(.lowBloodOxygen), lowBloodOxygenWarning)

        let cleared = stale.replacingMetric(.heartRate, with: HealthSummarySnapshot.placeholder)
        XCTAssertEqual(cleared.metricWarnings, [lowBloodOxygenWarning])
    }

    func testReplacingBloodOxygenReplacesOnlyThatWarning() {
        var stale = HealthSummarySnapshot.placeholder
        stale.metricWarnings = [lowHeartRateWarning]
        var refreshed = HealthSummarySnapshot.placeholder
        refreshed.metricWarnings = [lowBloodOxygenWarning]

        let merged = stale.replacingMetric(.oxygenSaturation, with: refreshed)
        XCTAssertEqual(merged.metricWarnings, [lowHeartRateWarning, lowBloodOxygenWarning])
    }

    func testReplacingWarningsForAMetricLeavesOthersAlone() {
        var snapshot = HealthSummarySnapshot.placeholder
        snapshot.metricWarnings = [lowHeartRateWarning, lowBloodOxygenWarning]

        let replaced = snapshot.replacingWarnings(for: .heartRate, with: [highHeartRateWarning])
        XCTAssertEqual(replaced.metricWarnings, [lowBloodOxygenWarning, highHeartRateWarning])
    }
}
