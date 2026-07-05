//
//  WatchMetricsSnapshotBuilderTests.swift
//  BodyWatchTests
//
//  Locks the watch snapshot's Sleep metric to `SleepSummary.asOf` — after
//  midnight, before tonight's own sleep session exists, the builder must not
//  carry yesterday's completed night onto the watch as "today's" sleep (see
//  `BodyTests/SleepSummaryAsOfTests` for the underlying guard).
//

import XCTest
@testable import BodyWatch

final class WatchMetricsSnapshotBuilderTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: 7))!
    }

    private func summary(sleepDated date: Date?) -> HealthSummarySnapshot {
        var summary = HealthSummarySnapshot.placeholder
        summary.sleep = SleepSummary(
            duration: 6 * 3_600,
            stageSnapshot: SleepStageSnapshot(
                date: date,
                segments: [SleepStageSegment(stage: .core, startDate: day(1), endDate: day(1))]
            ),
            vitals: .empty
        )
        return summary
    }

    private func sleepMetric(in snapshot: WatchMetricsSnapshot) -> WatchMetric? {
        snapshot.metric(forKind: WatchMetricKindKey.sleep)
    }

    private func snapshot(now: Date, sleepDated date: Date?) -> WatchMetricsSnapshot {
        WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary(sleepDated: date),
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: now
        )
    }

    func testSleepMetricIsEmptyWhenSnapshotSleepIsAPriorNightCarriedIntoTheNewDay() {
        let today = day(4)
        let healthSummary = summary(sleepDated: day(3))

        let snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: healthSummary,
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: today
        )

        let sleep = sleepMetric(in: snapshot)
        XCTAssertEqual(sleep?.displayValue, "--")
        XCTAssertNil(sleep?.score)
        XCTAssertNil(sleep?.rawValue)
    }

    func testSleepMetricPassesThroughWhenSnapshotSleepMatchesToday() {
        let today = day(4)
        let healthSummary = summary(sleepDated: today)

        let snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: healthSummary,
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: today
        )

        let sleep = sleepMetric(in: snapshot)
        XCTAssertNotEqual(sleep?.displayValue, "--")
    }

    // MARK: - Display-time gating (`sanitized`)
    //
    // The build-time guard above only runs when the phone rebuilds. A snapshot
    // pushed before midnight lives on in the watch's App Group cache, so the
    // watch app + complications re-gate it at load via `sanitized(asOf:)`.

    func testSanitizeBlanksSleepWhenPersistedNightIsAPriorDay() {
        // Built with a real night on day 3, then displayed on day 4.
        let sanitized = snapshot(now: day(3), sleepDated: day(3)).sanitized(asOf: day(4))

        let sleep = sleepMetric(in: sanitized)
        XCTAssertEqual(sleep?.displayValue, "--")
        XCTAssertNil(sleep?.score)
        XCTAssertNil(sleep?.rawValue)
    }

    func testSanitizeKeepsSleepWhenPersistedNightIsToday() {
        let built = snapshot(now: day(4), sleepDated: day(4))
        let sanitized = built.sanitized(asOf: day(4))

        XCTAssertEqual(sleepMetric(in: sanitized), sleepMetric(in: built))
        XCTAssertNotEqual(sleepMetric(in: sanitized)?.displayValue, "--")
    }

    func testSanitizeBlanksSleepWhenLegacySnapshotHasNoNight() {
        // A snapshot built before `sleepNight` existed (or by an older phone)
        // decodes with a nil night: we can't verify it belongs to today, so it's
        // blanked — corrected on the next phone push, at most one sync away.
        var legacy = snapshot(now: day(4), sleepDated: day(4))
        legacy.sleepNight = nil

        let sanitized = legacy.sanitized(asOf: day(4))
        let sleep = sleepMetric(in: sanitized)
        XCTAssertEqual(sleep?.displayValue, "--")
        XCTAssertNil(sleep?.score)
        XCTAssertNil(sleep?.rawValue)
    }
}
