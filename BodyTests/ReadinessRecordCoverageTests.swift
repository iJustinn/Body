//
//  ReadinessRecordCoverageTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Coverage-aware freezing (H11): a frozen morning record is replaced same-day
/// only when a later score carries a strictly richer set of atomic inputs — HRV,
/// resting HR, sleep continuity, or an individual vital arriving late — even
/// though the coarse component kinds (`.autonomic`/`.sleep`/`.vitals`) stay
/// identical. Legacy records (no coverage) keep the original one-shot sleep
/// upgrade unchanged.
final class ReadinessRecordCoverageTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    private func scoreDay() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    }

    // MARK: - Late atomic-input arrival inside an unchanged component

    func testHRVArrivingUpgradesRecordWithinAutonomicComponent() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        // Autonomic component already present via resting HR; HRV absent.
        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.restingHeartRate = series(baseline: 58, today: 58, on: scoreDay)

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let before = try XCTUnwrap(frozen.trends.recordedReadiness.first)
        XCTAssertEqual(try XCTUnwrap(before.coverage), [.restingHeartRate, .trainingLoad])
        XCTAssertFalse(try XCTUnwrap(before.coverage).contains(.hrv))

        // HRV syncs later in the morning: same autonomic component, richer inputs.
        var withHRV = frozen
        withHRV.trends.heartRateVariability = series(baseline: 60, today: 60, on: scoreDay)
        let upgraded = withHRV.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )

        let after = try XCTUnwrap(upgraded.trends.recordedReadiness.first)
        XCTAssertEqual(upgraded.trends.recordedReadiness.count, 1)
        XCTAssertTrue(try XCTUnwrap(after.coverage).contains(.hrv), "HRV arrival must upgrade the record")
        XCTAssertTrue(try XCTUnwrap(after.coverage).isSuperset(of: [.restingHeartRate, .trainingLoad]))
    }

    func testSleepContinuityLateArrivalUpgrades() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        // Duration only — no stage breakdown yet, so continuity is absent.
        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(date: scoreDay, summary: SleepSummary(duration: 7.0 * 3_600))
        ])

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let before = try XCTUnwrap(frozen.trends.recordedReadiness.first)
        XCTAssertTrue(try XCTUnwrap(before.coverage).contains(.sleepDuration))
        XCTAssertFalse(try XCTUnwrap(before.coverage).contains(.sleepContinuity))

        // Stage breakdown syncs: continuity becomes measurable → strict superset.
        var withStages = frozen
        withStages.trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 7.0 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 7.0, awakeHours: 0.5)
                )
            )
        ])
        let upgraded = withStages.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        let after = try XCTUnwrap(upgraded.trends.recordedReadiness.first)
        XCTAssertEqual(upgraded.trends.recordedReadiness.count, 1)
        XCTAssertTrue(try XCTUnwrap(after.coverage).contains(.sleepContinuity), "continuity arrival upgrades")
    }

    // MARK: - No downgrade / no spurious rewrite

    func testNoDowngradeWhenInputDisappears() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.restingHeartRate = series(baseline: 58, today: 58, on: scoreDay)
        trends.heartRateVariability = series(baseline: 60, today: 60, on: scoreDay)

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let before = try XCTUnwrap(frozen.trends.recordedReadiness.first)
        XCTAssertTrue(try XCTUnwrap(before.coverage).contains(.hrv))

        // HRV drops out of a later recompute: a subset must not replace the record.
        var withoutHRV = frozen
        withoutHRV.trends.heartRateVariability = .empty
        let after = withoutHRV.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertEqual(after.trends.recordedReadiness.first, before, "a poorer read must never downgrade the record")
    }

    func testNoRewriteOnEqualCoverage() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.restingHeartRate = series(baseline: 58, today: 58, on: scoreDay)

        let base = HealthDashboardSnapshot(summary: .empty, trends: trends)
        let first = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
        )
        let firstRecord = try XCTUnwrap(first.trends.recordedReadiness.first)

        let second = first.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertEqual(second.trends.recordedReadiness.count, 1)
        XCTAssertEqual(second.trends.recordedReadiness.first, firstRecord, "equal coverage is idempotent")
    }

    func testNoRewriteAfterFreezeWindowCloses() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let before = try XCTUnwrap(frozen.trends.recordedReadiness.first)

        // Richer inputs arrive, but past the score day's end: window closed.
        var richer = frozen
        richer.trends.restingHeartRate = series(baseline: 58, today: 58, on: scoreDay)
        let after = richer.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(25 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertEqual(after.trends.recordedReadiness.first, before, "no rewrite after the freeze window closes")
    }

    // MARK: - Threaded `now` for the current-day sleep fallback (L15)

    /// Duration-only sleep with no `stageSnapshot.date` falls back to a
    /// same-day-as-`now` check, mirrored between `ReadinessScoreCalculator`
    /// (the live score) and `HealthDashboardSnapshot.currentDaySleepInput`
    /// (the frozen-record coverage). Both must resolve that fallback against
    /// the SAME threaded `now` — if the score used the threaded anchor while
    /// coverage still read a live `Date()`, they would silently disagree
    /// whenever the scored day isn't the real wall-clock day (exactly this
    /// fixed, non-`Date()` fixture).
    func testScoreAndCoverageAgreeOnCurrentDaySleepFallbackForHistoricalNow() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let now = scoreDay.addingTimeInterval(11 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])

        var summary = HealthSummarySnapshot.empty
        // Duration-only, no stageSnapshot.date — exercises the current-day
        // fallback rather than the day-matched history branch.
        summary.sleep = SleepSummary(duration: 7 * 3_600)

        let recalculated = HealthDashboardSnapshot(summary: summary, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: now, freezesRecordedReadiness: true
            )

        let scoreIncludesSleep = recalculated.summary.readiness.components.contains { $0.kind == .sleep }
        let record = try XCTUnwrap(recalculated.trends.recordedReadiness.first)
        let coverageIncludesSleep = try XCTUnwrap(record.coverage).contains(.sleepDuration)

        XCTAssertTrue(scoreIncludesSleep, "duration-only sleep must count when `now` falls on the scored day")
        XCTAssertEqual(scoreIncludesSleep, coverageIncludesSleep, "score and frozen coverage must agree on the current-day sleep fallback")
    }

    // MARK: - Legacy records

    func testLegacyRecordKeepsOneShotSleepUpgradeAndGainsCoverage() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 7.0 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 7.0, awakeHours: 0.3)
                )
            )
        ])
        // Legacy sleepless record: nil coverage, includedSleep == false.
        trends.recordedReadiness = [RecordedReadinessEntry(date: scoreDay, score: 42, includedSleep: false)]

        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let record = try XCTUnwrap(snapshot.trends.recordedReadiness.first)
        XCTAssertEqual(snapshot.trends.recordedReadiness.count, 1)
        XCTAssertEqual(record.includedSleep, true, "legacy one-shot sleep upgrade preserved")
        XCTAssertNotEqual(record.score, 42)
        XCTAssertTrue(try XCTUnwrap(record.coverage).contains(.sleepDuration), "upgraded legacy record carries real coverage")
    }

    func testLegacySleepInclusiveRecordNeverReplaced() throws {
        let scoreDay = try scoreDay()
        let wake = scoreDay.addingTimeInterval(7 * 3_600)

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.restingHeartRate = series(baseline: 58, today: 58, on: scoreDay)
        trends.heartRateVariability = series(baseline: 60, today: 60, on: scoreDay)
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 7.0 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 7.0, awakeHours: 0.3)
                )
            )
        ])
        // Legacy record already flagged sleep-inclusive: must never be replaced,
        // and its coverage must never be fabricated from `includedSleep`.
        let legacy = RecordedReadinessEntry(date: scoreDay, score: 50, includedSleep: true)
        trends.recordedReadiness = [legacy]

        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        XCTAssertEqual(snapshot.trends.recordedReadiness, [legacy])
        XCTAssertNil(snapshot.trends.recordedReadiness.first?.coverage)
    }

    // MARK: - Codable

    func testLegacyRecordDecodesWithNilCoverage() throws {
        let json = Data(#"{"date":0,"score":77,"includedSleep":false}"#.utf8)
        let decoded = try JSONDecoder().decode(RecordedReadinessEntry.self, from: json)
        XCTAssertNil(decoded.coverage)
        XCTAssertEqual(decoded.includedSleep, false)
        XCTAssertEqual(decoded.score, 77)
    }

    func testRecordWithCoverageSurvivesRoundTrip() throws {
        let scoreDay = try scoreDay()
        let entry = RecordedReadinessEntry(
            date: scoreDay,
            score: 80,
            includedSleep: true,
            coverage: [.hrv, .sleepDuration, .sleepContinuity]
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(RecordedReadinessEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(decoded.coverage, [.hrv, .sleepDuration, .sleepContinuity])
    }

    func testReadinessCoverageOptionSetCodableRoundTrip() throws {
        let coverage: ReadinessCoverage = [.restingHeartRate, .trainingLoad, .oxygenSaturation]
        let data = try JSONEncoder().encode(coverage)
        let decoded = try JSONDecoder().decode(ReadinessCoverage.self, from: data)
        XCTAssertEqual(decoded, coverage)
    }

    // MARK: - Helpers

    /// 28 prior days at `baseline` plus the scoring day at `today` — enough to
    /// satisfy the whole-day baseline minimum so an autonomic reading exists.
    private func series(baseline: Double, today: Double, on scoreDay: Date) -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []
        for offset in 1...28 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                continue
            }
            points.append(HealthTrendDataPoint(date: date, value: baseline))
        }
        points.append(HealthTrendDataPoint(date: scoreDay, value: today))
        return HealthTrendSeries(points: points)
    }

    private func stageSnapshot(
        on day: Date,
        asleepHours: Double,
        awakeHours: Double
    ) -> SleepStageSnapshot {
        let inBedStart = calendar.startOfDay(for: day).addingTimeInterval(3_600)
        let awakeEnd = inBedStart.addingTimeInterval(awakeHours * 3_600)
        let asleepEnd = awakeEnd.addingTimeInterval(asleepHours * 3_600)
        var segments: [SleepStageSegment] = []
        if awakeHours > 0 {
            segments.append(SleepStageSegment(stage: .awake, startDate: inBedStart, endDate: awakeEnd))
        }
        segments.append(SleepStageSegment(stage: .core, startDate: awakeEnd, endDate: asleepEnd))
        return SleepStageSnapshot(date: day, segments: segments)
    }
}
