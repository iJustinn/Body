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

    // MARK: - Readiness current-value dot (`weeklyCurrentValue`)

    private func snapshot(readiness: ReadinessSummary, now: Date) -> WatchMetricsSnapshot {
        var summary = HealthSummarySnapshot.placeholder
        summary.readiness = readiness
        return WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary,
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: now
        )
    }

    func testDrainedReadinessCarriesWeeklyCurrentValue() {
        let drained = ReadinessSummary(
            score: 72,
            status: ReadinessStatus.status(for: 72),
            confidence: .high,
            components: [],
            drivers: [],
            activityDrainMorningScore: 80
        )

        let readiness = snapshot(readiness: drained, now: day(4))
            .metric(forKind: WatchMetricKindKey.readiness)
        XCTAssertEqual(readiness?.weeklyCurrentValue, 72)
    }

    func testUndrainedReadinessOmitsWeeklyCurrentValue() {
        let undrained = ReadinessSummary(
            score: 80,
            status: ReadinessStatus.status(for: 80),
            confidence: .high,
            components: [],
            drivers: []
        )

        let readiness = snapshot(readiness: undrained, now: day(4))
            .metric(forKind: WatchMetricKindKey.readiness)
        XCTAssertEqual(readiness?.rawValue, 80)
        XCTAssertNil(readiness?.weeklyCurrentValue)
    }

    // MARK: - Weekly Workout Time (complication-only kind)

    private func workoutSnapshot(
        weeklyMinutes: [Double?]?,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue
    ) -> WatchMetricsSnapshot {
        WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: .placeholder,
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: permissionSelection,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: day(7),
            workoutWeeklyMinutes: weeklyMinutes
        )
    }

    func testWorkoutMinutesMetricCarriesTheSevenWeeklyValuesItWasGiven() {
        // The builder never fetches: the week is summed by the caller from the
        // workouts it already holds, and a rest day rides as an explicit `0`.
        let week: [Double?] = [10, 20, 0, 40, 50, 0, 70]
        let metric = workoutSnapshot(weeklyMinutes: week)
            .metric(forKind: WatchMetricKindKey.workoutMinutes)

        // The complication draws one bar per weekly slot, so a short or missing
        // array silently changes the chart's shape.
        XCTAssertEqual(metric?.weekly?.count, 7)
        XCTAssertEqual(metric?.weekly, week)
        // Today is the last slot, and matches the headline value.
        XCTAssertEqual(metric?.displayValue, "70")
    }

    func testWorkoutMinutesMetricIsOmittedWhenTheWorkoutsPermissionIsOff() {
        let selection = BodyHealthPermissionSelection.defaultValue
            .setting(.workouts, isEnabled: false)

        XCTAssertNil(
            workoutSnapshot(weeklyMinutes: [10, 20, 0, 40, 50, 0, 70], permissionSelection: selection)
                .metric(forKind: WatchMetricKindKey.workoutMinutes)
        )
    }

    func testWorkoutMinutesMetricIsOmittedWhenNoWeekWasSupplied() {
        // A caller that hasn't loaded the week (a month snapshot still missing,
        // or a failed watch-local workout query) passes nil rather than a
        // fabricated week of rest days, and the metric stays out of the
        // snapshot so the complication keeps the bars it already has.
        XCTAssertNil(
            workoutSnapshot(weeklyMinutes: nil)
                .metric(forKind: WatchMetricKindKey.workoutMinutes)
        )
    }

    func testWorkoutMinutesShipsALegacyCompatibilityCopyWithTheSameWeek() {
        // Version skew: an older watch binary's complication queries only the
        // legacy `exerciseMinutes` kind, and a phone push replaces the watch's
        // metric set — so the builder publishes the same week under both kinds
        // until the watch app catches up.
        let week: [Double?] = [10, 20, 0, 40, 50, 0, 70]
        let snapshot = workoutSnapshot(weeklyMinutes: week)
        let legacy = snapshot.metric(forKind: WatchMetricKindKey.exerciseMinutes)

        XCTAssertEqual(legacy?.weekly, week)
        XCTAssertEqual(legacy?.displayValue, "70")
        // Both copies vanish together with the week (and with the permission).
        XCTAssertNil(
            workoutSnapshot(weeklyMinutes: nil)
                .metric(forKind: WatchMetricKindKey.exerciseMinutes)
        )
    }

    func testAnExplicitWorkoutWatermarkIsNotReplacedByTheVitalsDate() {
        // The phone stamps `.distantPast` when it can't prove the week's month
        // coverage (an install upgrading into this build, before its first
        // full-coverage refresh). That claim has to survive: falling back to
        // the uniform vitals date here would present an unverified mixed-month
        // week as freshly refreshed and let it overwrite newer watch-computed
        // bars.
        let vitalsDate = day(7)
        let snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: .placeholder,
            trends: .empty,
            lastRefreshDate: vitalsDate,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: 8 * 3_600,
            now: vitalsDate,
            workoutWeeklyMinutes: [10, 20, 0, 40, 50, 0, 70],
            perKindDataAsOf: { kind in
                switch kind {
                case WatchMetricKindKey.workoutMinutes, WatchMetricKindKey.exerciseMinutes:
                    return .distantPast
                default:
                    return nil
                }
            }
        )

        XCTAssertEqual(
            snapshot.metric(forKind: WatchMetricKindKey.workoutMinutes)?.computedAt,
            .distantPast
        )
        // The legacy compatibility copy carries the same unverified week, so it
        // must not outrank a local compute either.
        XCTAssertEqual(
            snapshot.metric(forKind: WatchMetricKindKey.exerciseMinutes)?.computedAt,
            .distantPast
        )
        // Kinds that returned nil still take the uniform vitals stamp.
        XCTAssertEqual(
            snapshot.metric(forKind: WatchMetricKindKey.trainingLoad)?.computedAt,
            vitalsDate
        )
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

    // MARK: - Skin Temp `usesFahrenheit` (L-38)

    private func snapshot(
        wristTemperatureCelsius celsius: Double,
        pref: BodyValueFormat.TemperatureUnitPreference
    ) -> WatchMetricsSnapshot {
        var summary = HealthSummarySnapshot.placeholder
        summary.wristTemperature = HealthMetricSummary(value: celsius)
        return WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: summary,
            trends: .empty,
            lastRefreshDate: nil,
            permissionSelection: .defaultValue,
            temperatureUnitPreference: pref,
            idealSleepDuration: 8 * 3_600,
            now: day(4)
        )
    }

    func testSkinTempUsesFahrenheitTrueUnderFahrenheitPreference() {
        let snapshot = snapshot(wristTemperatureCelsius: 34.1, pref: .fahrenheit)
        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.wristTemperature)?.usesFahrenheit, true)
    }

    func testSkinTempUsesFahrenheitFalseUnderCelsiusPreference() {
        let snapshot = snapshot(wristTemperatureCelsius: 34.1, pref: .celsius)
        XCTAssertEqual(snapshot.metric(forKind: WatchMetricKindKey.wristTemperature)?.usesFahrenheit, false)
    }

    func testOtherMetricsLeaveUsesFahrenheitNil() {
        let snapshot = snapshot(wristTemperatureCelsius: 34.1, pref: .fahrenheit)
        XCTAssertNil(snapshot.metric(forKind: WatchMetricKindKey.sleep)?.usesFahrenheit)
    }
}
