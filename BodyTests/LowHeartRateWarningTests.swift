//
//  LowHeartRateWarningTests.swift
//  BodyTests
//
//  Covers the shared low heart rate detector (strict threshold, episode grouping,
//  chart window clamping) and the summary snapshot field the home badge reads,
//  including legacy snapshots written before the field existed.
//

import XCTest
@testable import Body

final class LowHeartRateWarningTests: XCTestCase {
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

    // MARK: - Detector

    func testEmptySeriesHasNoEvent() {
        XCTAssertNil(LowHeartRateWarning.detect(in: .empty, on: day(), calendar: calendar))
    }

    func testReadingsAtOrAboveThresholdHaveNoEvent() {
        let input = series([
            (time(6, 0), 41),
            (time(6, 5), 55),
            (time(6, 10), 40.0)
        ])

        XCTAssertNil(LowHeartRateWarning.detect(in: input, on: day(), calendar: calendar))
    }

    func testSingleLowSampleIsItsOwnEpisode() throws {
        let input = series([
            (time(6, 20), 62),
            (time(6, 25), 39),
            (time(6, 30), 58)
        ])

        let event = try XCTUnwrap(LowHeartRateWarning.detect(in: input, on: day(), calendar: calendar))
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 25))
        XCTAssertEqual(event.minimumBPM, 39)
        XCTAssertEqual(event.sampleCount, 1)
    }

    func testConsecutiveLowsWithinGapFormOneEpisode() throws {
        let input = series([
            (time(6, 25), 39),
            (time(6, 40), 36),
            (time(7, 0), 38),
            (time(7, 30), 37)
        ])

        let event = try XCTUnwrap(LowHeartRateWarning.detect(in: input, on: day(), calendar: calendar))
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(7, 30))
        XCTAssertEqual(event.minimumBPM, 36)
        XCTAssertEqual(event.sampleCount, 4)
    }

    func testIsolatedClustersHoursApartReportOnlyTheEarliestEpisode() throws {
        let input = series([
            (time(6, 25), 39),
            (time(6, 35), 38),
            (time(14, 0), 30),
            (time(14, 10), 31)
        ])

        let event = try XCTUnwrap(LowHeartRateWarning.detect(in: input, on: day(), calendar: calendar))
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 35))
        XCTAssertEqual(event.minimumBPM, 38)
        XCTAssertEqual(event.sampleCount, 2)
        XCTAssertLessThan(event.endDate, time(14, 0))
    }

    func testLowsOnOtherDaysAreIgnored() throws {
        let input = series([
            (time(23, 30, dayOffset: -1), 32),
            (time(9, 0), 38),
            (time(1, 0, dayOffset: 1), 31)
        ])

        let event = try XCTUnwrap(LowHeartRateWarning.detect(in: input, on: day(), calendar: calendar))
        XCTAssertEqual(event.startDate, time(9, 0))
        XCTAssertEqual(event.sampleCount, 1)
    }

    func testUnsortedSamplesStillYieldTheEarliestEpisode() throws {
        let input = series([
            (time(6, 40), 36),
            (time(6, 25), 39)
        ])

        let event = try XCTUnwrap(LowHeartRateWarning.detect(in: input, on: day(), calendar: calendar))
        XCTAssertEqual(event.startDate, time(6, 25))
        XCTAssertEqual(event.endDate, time(6, 40))
        XCTAssertEqual(event.sampleCount, 2)
    }

    // MARK: - Chart window

    func testChartWindowPadsBothSides() {
        let event = LowHeartRateEvent(
            startDate: time(6, 25),
            endDate: time(6, 35),
            minimumBPM: 38,
            sampleCount: 2
        )
        let dayInterval = calendar.dateInterval(of: .day, for: day())!

        let window = LowHeartRateWarning.chartWindow(for: event, clampedTo: dayInterval)
        XCTAssertEqual(window.start, time(6, 15))
        XCTAssertEqual(window.end, time(6, 45))
    }

    func testChartWindowClampsToTheDayBounds() {
        let dayInterval = calendar.dateInterval(of: .day, for: day())!
        let event = LowHeartRateEvent(
            startDate: dayInterval.start,
            endDate: dayInterval.end.addingTimeInterval(-60),
            minimumBPM: 30,
            sampleCount: 5
        )

        let window = LowHeartRateWarning.chartWindow(for: event, clampedTo: dayInterval)
        XCTAssertEqual(window.start, dayInterval.start)
        XCTAssertEqual(window.end, dayInterval.end)
        XCTAssertLessThan(window.start, window.end)
    }

    func testChartWindowFallsBackToTheDayWhenClampingDegenerates() {
        let dayInterval = calendar.dateInterval(of: .day, for: day())!
        let event = LowHeartRateEvent(
            startDate: dayInterval.end,
            endDate: dayInterval.end,
            minimumBPM: 35,
            sampleCount: 1
        )

        let window = LowHeartRateWarning.chartWindow(for: event, padding: 0, clampedTo: dayInterval)
        XCTAssertEqual(window, dayInterval)
    }

    // MARK: - Snapshot field

    private func snapshotWithEvent() -> HealthSummarySnapshot {
        var snapshot = HealthSummarySnapshot.placeholder
        snapshot.lowHeartRateEvent = LowHeartRateEvent(
            startDate: time(6, 25),
            endDate: time(6, 35),
            minimumBPM: 38,
            sampleCount: 2
        )
        return snapshot
    }

    func testSnapshotRoundTripsTheEvent() throws {
        let snapshot = snapshotWithEvent()
        let decoded = try JSONDecoder().decode(
            HealthSummarySnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded.lowHeartRateEvent, snapshot.lowHeartRateEvent)
    }

    func testSnapshotRoundTripsWithoutTheEvent() throws {
        let snapshot = HealthSummarySnapshot.placeholder
        let decoded = try JSONDecoder().decode(
            HealthSummarySnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertNil(decoded.lowHeartRateEvent)
    }

    func testLegacySnapshotWithoutTheKeyDecodesToNil() throws {
        let data = try JSONEncoder().encode(snapshotWithEvent())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: "lowHeartRateEvent"))

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: legacy)

        XCTAssertNil(decoded.lowHeartRateEvent)
        XCTAssertEqual(decoded.heartRate.value, HealthSummarySnapshot.placeholder.heartRate.value)
    }

    func testEventDoesNotMakeAnEmptySnapshotNonEmpty() {
        var snapshot = HealthSummarySnapshot.empty
        snapshot.lowHeartRateEvent = LowHeartRateEvent(
            startDate: time(6, 25),
            endDate: time(6, 25),
            minimumBPM: 38,
            sampleCount: 1
        )

        XCTAssertTrue(snapshot.isEmpty)
    }

    func testFilteringOutHeartClearsTheEvent() {
        let snapshot = snapshotWithEvent()
        let withoutHeart = BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)

        XCTAssertNil(snapshot.filtered(by: withoutHeart).lowHeartRateEvent)
        XCTAssertEqual(
            snapshot.filtered(by: .defaultValue).lowHeartRateEvent,
            snapshot.lowHeartRateEvent
        )
    }

    func testReplacingHeartRateCopiesTheEvent() {
        var stale = HealthSummarySnapshot.placeholder
        stale.lowHeartRateEvent = LowHeartRateEvent(
            startDate: time(3, 0),
            endDate: time(3, 0),
            minimumBPM: 30,
            sampleCount: 1
        )
        let refreshed = snapshotWithEvent()

        let merged = stale.replacingMetric(.heartRate, with: refreshed)
        XCTAssertEqual(merged.lowHeartRateEvent, refreshed.lowHeartRateEvent)

        var cleared = refreshed
        cleared.lowHeartRateEvent = nil
        XCTAssertNil(stale.replacingMetric(.heartRate, with: cleared).lowHeartRateEvent)
    }
}
