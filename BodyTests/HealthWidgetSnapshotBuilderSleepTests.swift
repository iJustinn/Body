//
//  HealthWidgetSnapshotBuilderSleepTests.swift
//  BodyTests
//
//  Verifies HealthWidgetSnapshotBuilder guards against carrying over a stale,
//  previously-completed night after midnight, before today's own sleep
//  session exists — mirroring the in-app Home/Sleep gating in
//  BodyMetricsKit/Sleep.swift (SleepSummary.asOf).
//

import XCTest
@testable import Body

final class HealthWidgetSnapshotBuilderSleepTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    /// Builds a widget snapshot for a sleep session dated `sleepDate`, as of
    /// `asOf` (defaulting to the same date — i.e. an unstaled build).
    private func makeSnapshot(sleepDate: Date, asOf: Date? = nil) -> HealthWidgetSnapshot {
        let stageSnapshot = SleepStageSnapshot(
            date: sleepDate,
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: sleepDate.addingTimeInterval(-8 * 3_600),
                    endDate: sleepDate
                )
            ]
        )
        let sleep = SleepSummary(duration: 8 * 3_600, stageSnapshot: stageSnapshot)
        let summary = HealthSummarySnapshot(
            activityRings: .empty,
            sleep: sleep,
            restingHeartRate: HealthMetricSummary(value: nil),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: nil),
            respiratoryRate: HealthMetricSummary(value: nil),
            oxygenSaturation: HealthMetricSummary(value: nil),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil)
        )

        return HealthWidgetSnapshotBuilder.make(
            trends: .empty,
            summary: summary,
            sleepStageSnapshot: stageSnapshot,
            temperatureUnitPreference: .celsius,
            energyUnitPreference: .kilojoules,
            weightUnitPreference: .kilograms,
            idealSleepDuration: BodySleepDurationGoal.defaultDuration,
            showSleepScore: true,
            primarySourceName: { _ in nil },
            date: asOf ?? sleepDate,
            calendar: calendar
        )
    }

    /// After midnight, before today's own sleep session exists, the widget
    /// must not carry over yesterday's completed night: sleep stages must be
    /// empty and the duration display value must fall back to "--".
    func testStaleYesterdaysNightProducesEmptySleep() throws {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let staleSnapshot = makeSnapshot(sleepDate: yesterday, asOf: today)

        XCTAssertTrue(staleSnapshot.sleep.isEmpty)
        XCTAssertNil(staleSnapshot.sleep.night)

        let sleepTrend = try XCTUnwrap(staleSnapshot.metricTrends.first { $0.metric == .sleep })
        XCTAssertEqual(sleepTrend.displayValues.last?.value, "--")
    }

    /// A same-day summary (stageSnapshot.date matches `date:`) passes through
    /// intact.
    func testSameDaySleepPassesThroughIntact() throws {
        let today = Date()
        let snapshot = makeSnapshot(sleepDate: today)

        XCTAssertFalse(snapshot.sleep.isEmpty)
        XCTAssertEqual(snapshot.sleep.night, calendar.startOfDay(for: today))

        let sleepTrend = try XCTUnwrap(snapshot.metricTrends.first { $0.metric == .sleep })
        XCTAssertNotEqual(sleepTrend.displayValues.last?.value, "--")
    }

    // MARK: - Load-time staleness (widget extension re-checks a persisted snapshot)

    /// `HealthWidgetSnapshotBuilder` only guards staleness when the phone
    /// rebuilds the snapshot. A snapshot persisted to the App Group before
    /// midnight is still valid at write time, so `sleep.night` and the
    /// `.sleep` display values pass through intact from `make()` — but the
    /// widget must catch that staleness again at load time using
    /// `sanitizingStaleSleep(asOf:)`.
    func testSanitizingStaleSleepBlanksYesterdaysNightAtLoadTime() throws {
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Built "as of" yesterday (i.e. still same-day at write time), so the
        // builder does not blank it — mirroring a snapshot persisted before
        // midnight that the widget only re-reads afterward.
        let persistedSnapshot = makeSnapshot(sleepDate: yesterday, asOf: yesterday)
        XCTAssertFalse(persistedSnapshot.sleep.isEmpty)
        XCTAssertNotNil(persistedSnapshot.sleep.night)

        let sanitized = persistedSnapshot.sanitizingStaleSleep(asOf: today, calendar: calendar)

        XCTAssertTrue(sanitized.sleep.isEmpty)
        XCTAssertNil(sanitized.sleep.night)
        let sleepTrend = try XCTUnwrap(sanitized.metricTrends.first { $0.metric == .sleep })
        for displayValue in sleepTrend.displayValues {
            XCTAssertEqual(displayValue.value, "--")
        }
    }

    /// A same-day snapshot passes through `sanitizingStaleSleep` unchanged.
    func testSanitizingStaleSleepPassesThroughSameDayNight() throws {
        let today = Date()
        let snapshot = makeSnapshot(sleepDate: today)

        let sanitized = snapshot.sanitizingStaleSleep(asOf: today, calendar: calendar)

        XCTAssertEqual(sanitized, snapshot)
    }

    /// A nil `night` (already-empty sleep) is treated as stale, consistent
    /// with `SleepSummary.matchesDay` never trusting a missing date.
    func testSleepStagesWithNilNightIsAlwaysStale() {
        XCTAssertTrue(HealthWidgetSleepStages.empty.isStale(asOf: Date(), calendar: calendar))
    }
}
