//
//  ReadinessScoreCalculatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class ReadinessScoreCalculatorTests: XCTestCase {

    // MARK: - Status Bands

    func testReadinessStatusUsesRequestedScoreBands() {
        XCTAssertEqual(ReadinessStatus.status(for: 100), .prime)
        XCTAssertEqual(ReadinessStatus.status(for: 95), .prime)
        XCTAssertEqual(ReadinessStatus.status(for: 94), .high)
        XCTAssertEqual(ReadinessStatus.status(for: 80), .high)
        XCTAssertEqual(ReadinessStatus.status(for: 79), .moderate)
        XCTAssertEqual(ReadinessStatus.status(for: 65), .moderate)
        XCTAssertEqual(ReadinessStatus.status(for: 64), .low)
        XCTAssertEqual(ReadinessStatus.status(for: 30), .low)
        XCTAssertEqual(ReadinessStatus.status(for: 29), .poor)
        XCTAssertEqual(ReadinessStatus.status(for: 0), .poor)
    }

    func testReadinessStatusRangeTextMatchesRequestedScoreBands() {
        XCTAssertEqual(ReadinessStatus.prime.scoreRangeText, "95-100%")
        XCTAssertEqual(ReadinessStatus.high.scoreRangeText, "80-94%")
        XCTAssertEqual(ReadinessStatus.moderate.scoreRangeText, "65-79%")
        XCTAssertEqual(ReadinessStatus.low.scoreRangeText, "30-64%")
        XCTAssertEqual(ReadinessStatus.poor.scoreRangeText, "0-29%")
    }

    // MARK: - Sleep Goal (C1 regression)

    /// Regression for C1: the sleep component must honor the caller's
    /// `idealSleepDuration` rather than `BodySleepDurationGoal.defaultDuration`.
    /// A user with a 6-hour goal who slept exactly 6 hours should NOT see a
    /// "below goal" driver, even though 6 hours is well below the 8-hour
    /// hardcoded default the calculator previously used.
    func testSleepComponentHonorsShorterUserGoal() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let sixHours: TimeInterval = 6 * 60 * 60
        let trends = trendsWithSleepDuration(sixHours, on: scoreDay, calendar: calendar)

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: sixHours,
            calendar: calendar
        )

        let sleep = try XCTUnwrap(summary.components.first { $0.kind == .sleep })
        XCTAssertNotNil(sleep.score)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sleep.score), 75)
        XCTAssertFalse(summary.drivers.contains { $0.kind == .sleepDurationBelowGoal })
    }

    /// Same fixture, but using the default 8-hour goal: the user only slept
    /// 6 hours, which is 0.75 of the goal — should drop into the
    /// "below goal" branch and yield a noticeably lower sleep score.
    func testSleepComponentPenalizesSameDurationAgainstLongerGoal() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let sixHours: TimeInterval = 6 * 60 * 60
        let eightHours: TimeInterval = 8 * 60 * 60
        let trends = trendsWithSleepDuration(sixHours, on: scoreDay, calendar: calendar)

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: eightHours,
            calendar: calendar
        )

        let sleep = try XCTUnwrap(summary.components.first { $0.kind == .sleep })
        XCTAssertNotNil(sleep.score)
        XCTAssertLessThan(try XCTUnwrap(sleep.score), 75)
        XCTAssertTrue(summary.drivers.contains { $0.kind == .sleepDurationBelowGoal })
    }

    /// Direct sanity check that the goal parameter actually changes the score
    /// for identical sleep input — guards against future regressions where
    /// the parameter is accepted but silently dropped on the way down.
    func testSleepComponentScoreDiffersWhenOnlyGoalChanges() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let sixHours: TimeInterval = 6 * 60 * 60
        let trends = trendsWithSleepDuration(sixHours, on: scoreDay, calendar: calendar)

        let lenientGoal = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: 6 * 60 * 60,
            calendar: calendar
        )
        let strictGoal = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            idealSleepDuration: 9 * 60 * 60,
            calendar: calendar
        )

        let lenientSleepScore = try XCTUnwrap(lenientGoal.components.first { $0.kind == .sleep }?.score)
        let strictSleepScore = try XCTUnwrap(strictGoal.components.first { $0.kind == .sleep }?.score)
        XCTAssertGreaterThan(lenientSleepScore, strictSleepScore)
    }

    /// `dailySeries` recomputes readiness for every day in the window. It must
    /// thread the configured sleep goal through to each call rather than
    /// silently using the default.
    func testDailySeriesForwardsSleepGoalToEachDay() throws {
        let calendar = Calendar.bodyGregorian
        let endDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let startDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: endDay))
        let sixHours: TimeInterval = 6 * 60 * 60
        let trends = trendsWithSleepDurationForEachDay(
            sixHours,
            startDay: startDay,
            endDay: endDay,
            calendar: calendar
        )

        let lenient = ReadinessScoreCalculator.dailySeries(
            healthSummary: .empty,
            trends: trends,
            startDate: startDay,
            endDate: endDay,
            idealSleepDuration: 6 * 60 * 60,
            calendar: calendar
        )
        let strict = ReadinessScoreCalculator.dailySeries(
            healthSummary: .empty,
            trends: trends,
            startDate: startDay,
            endDate: endDay,
            idealSleepDuration: 9 * 60 * 60,
            calendar: calendar
        )

        XCTAssertEqual(lenient.points.count, 3)
        XCTAssertEqual(strict.points.count, 3)
        for index in 0..<3 {
            XCTAssertGreaterThan(
                lenient.points[index].value,
                strict.points[index].value,
                "Day \(index) readiness score should be higher when the configured goal is shorter"
            )
        }
    }

    // MARK: - Robust Baseline

    func testRobustBaselineReturnsNilBelowMinimumDays() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let values = dailyValues(
            constants: Array(repeating: 50.0, count: ReadinessScoreCalculator.minimumBaselineDayCount - 1),
            endingDayBefore: scoreDay,
            calendar: calendar
        )

        XCTAssertNil(ReadinessScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 0.1,
            calendar: calendar
        ))
    }

    func testRobustBaselineComputesMedianFromPriorWindow() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let values = dailyValues(
            constants: Array(repeating: 60.0, count: 20),
            endingDayBefore: scoreDay,
            calendar: calendar
        )

        let baseline = try XCTUnwrap(ReadinessScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 0.1,
            calendar: calendar
        ))

        XCTAssertEqual(baseline.median, 60, accuracy: 0.0001)
        XCTAssertEqual(baseline.spread, 0.1, accuracy: 0.0001, "constant input → MAD is 0 → spread should be floored")
        XCTAssertEqual(baseline.validDayCount, 20)
    }

    func testRobustBaselineExcludesScoringDayAndFuture() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        var values = dailyValues(
            constants: Array(repeating: 60.0, count: 20),
            endingDayBefore: scoreDay,
            calendar: calendar
        )
        // An extreme outlier ON the scoring day must not pull the baseline.
        values.append(ReadinessScoreCalculator.DailyValue(date: scoreDay, value: 9_999))

        let baseline = try XCTUnwrap(ReadinessScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 0.1,
            calendar: calendar
        ))

        XCTAssertEqual(baseline.median, 60, accuracy: 0.0001)
        XCTAssertEqual(baseline.validDayCount, 20)
    }

    // MARK: - Robust Z-Score

    func testRobustZScoreFormula() {
        let baseline = ReadinessScoreCalculator.Baseline(median: 60, spread: 5, validDayCount: 20)
        XCTAssertEqual(ReadinessScoreCalculator.robustZScore(value: 65, baseline: baseline), 1.0, accuracy: 0.0001)
        XCTAssertEqual(ReadinessScoreCalculator.robustZScore(value: 50, baseline: baseline), -2.0, accuracy: 0.0001)
    }

    func testRobustZScoreReturnsZeroForZeroSpread() {
        let baseline = ReadinessScoreCalculator.Baseline(median: 60, spread: 0, validDayCount: 20)
        XCTAssertEqual(ReadinessScoreCalculator.robustZScore(value: 99, baseline: baseline), 0)
    }

    func testRobustZScoreReturnsZeroForNonFiniteValue() {
        let baseline = ReadinessScoreCalculator.Baseline(median: 60, spread: 5, validDayCount: 20)
        XCTAssertEqual(ReadinessScoreCalculator.robustZScore(value: .nan, baseline: baseline), 0)
        XCTAssertEqual(ReadinessScoreCalculator.robustZScore(value: .infinity, baseline: baseline), 0)
    }

    // MARK: - Summary aggregation

    func testSummaryReturnsUnavailableWithNoSignals() {
        let summary = ReadinessScoreCalculator.summary(
            on: Date(),
            healthSummary: .empty,
            trends: .empty
        )

        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.status, .unavailable)
        XCTAssertEqual(summary.confidence, .unavailable)
    }

    // MARK: - Recovery-Anchored Scoring (WHOOP recalibration)

    /// Regression fixture from the May 30 – Jun 11 2026 Apple Health export
    /// (whole-day fallback path, no overnight vitals). Crash days the data
    /// can see must drop into the Low band or below, strong days must stay
    /// High, and the score range must be wide — the old weighted average
    /// compressed this exact window into 76–95.
    func testExportRegressionCrashDaysScoreLowAndTopDaysScoreHigh() throws {
        let calendar = Calendar.bodyGregorian
        let fixture = try exportFixture(calendar: calendar)

        var scores: [String: Int] = [:]
        for (name, day) in fixture.daysByName {
            scores[name] = ReadinessScoreCalculator.summary(
                on: day,
                healthSummary: .empty,
                trends: fixture.trends,
                calendar: calendar
            ).score
        }

        for crashDay in ["Jun01", "Jun02", "Jun04"] {
            let score = try XCTUnwrap(scores[crashDay], "\(crashDay) should be scorable")
            XCTAssertLessThanOrEqual(score, 45, "\(crashDay) was a physiological crash day")
            XCTAssertLessThanOrEqual(score, 64, "\(crashDay) must read Low band or worse")
        }
        for strongDay in ["Jun07", "Jun08"] {
            let score = try XCTUnwrap(scores[strongDay], "\(strongDay) should be scorable")
            XCTAssertGreaterThanOrEqual(score, 80, "\(strongDay) was a strong recovery day")
        }

        let allScores = Array(scores.values)
        let width = try XCTUnwrap(allScores.max()) - XCTUnwrap(allScores.min())
        XCTAssertGreaterThanOrEqual(width, 45, "scores must not compress into a narrow band")
    }

    /// When ≥14 nights of overnight vitals exist, the autonomic core must
    /// score the overnight values, not the whole-day averages.
    func testOvernightVitalsPreferredOverWholeDaySeries() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        let wholeDayOnly = autonomicTrends(
            on: scoreDay,
            overnightNights: 0,
            overnightHRVToday: nil,
            calendar: calendar
        )
        let overnightCrashed = autonomicTrends(
            on: scoreDay,
            overnightNights: 20,
            overnightHRVToday: 30,
            calendar: calendar
        )

        let wholeDayScore = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: wholeDayOnly, calendar: calendar
        ).score)
        let overnightScore = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: overnightCrashed, calendar: calendar
        ).score)

        XCTAssertLessThan(
            overnightScore,
            wholeDayScore,
            "crashed overnight HRV must drive the score even when whole-day HRV looks typical"
        )
    }

    /// H2 regression: disabling Heart must strip the cached per-night HR/HRV
    /// vitals inside `sleepHistory`, not just the whole-day trend series —
    /// otherwise `ReadinessScoreCalculator`'s overnight-preferred path keeps
    /// scoring vitals the user turned off.
    func testFilteringHeartPermissionStripsSleepHistoryVitals() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let heartDisabled = BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)

        let overnightCrashed = autonomicTrends(
            on: scoreDay,
            overnightNights: 20,
            overnightHRVToday: 30,
            calendar: calendar
        )

        let filtered = overnightCrashed.filtered(by: heartDisabled)

        XCTAssertFalse(overnightCrashed.sleepHistory.days.isEmpty)
        XCTAssertTrue(filtered.sleepHistory.days.allSatisfy { day in
            day.summary.vitals.heartRate == nil && day.summary.vitals.heartRateVariability == nil
        })
        // Sleep itself is governed by `.sleep`, not `.heart` — duration must survive.
        XCTAssertTrue(filtered.sleepHistory.days.allSatisfy { $0.summary.duration == 7.9 * 3_600 })

        let normalOvernight = autonomicTrends(
            on: scoreDay,
            overnightNights: 20,
            overnightHRVToday: 60,
            calendar: calendar
        ).filtered(by: heartDisabled)

        let crashedScore = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: filtered, calendar: calendar
        ).score)
        let normalScore = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: normalOvernight, calendar: calendar
        ).score)

        XCTAssertEqual(
            crashedScore,
            normalScore,
            "once Heart is disabled, crashed overnight HRV must no longer influence the score"
        )
    }

    /// Fewer than 14 overnight nights → the metric is not overnight-qualified
    /// and scoring must match the whole-day-only behavior exactly.
    func testSparseOvernightHistoryFallsBackToWholeDay() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        let wholeDayOnly = autonomicTrends(
            on: scoreDay,
            overnightNights: 0,
            overnightHRVToday: nil,
            calendar: calendar
        )
        let sparseOvernight = autonomicTrends(
            on: scoreDay,
            overnightNights: 5,
            overnightHRVToday: 30,
            calendar: calendar
        )

        let wholeDayScore = ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: wholeDayOnly, calendar: calendar
        ).score
        let sparseScore = ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: sparseOvernight, calendar: calendar
        ).score

        XCTAssertEqual(sparseScore, wholeDayScore, "sparse overnight history must not change the source")
    }

    /// An overnight-qualified metric with no value on the scoring day is
    /// absent for that day — it must NOT fall back to the whole-day value
    /// against the overnight baseline. Two variants that differ only in the
    /// scoring-day whole-day HRV must therefore score identically.
    func testMissingTodayOvernightValueDoesNotFallBackToWholeDay() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        let highWholeDayToday = autonomicTrends(
            on: scoreDay,
            overnightNights: 20,
            overnightHRVToday: nil,
            wholeDayHRVToday: 95,
            calendar: calendar
        )
        let lowWholeDayToday = autonomicTrends(
            on: scoreDay,
            overnightNights: 20,
            overnightHRVToday: nil,
            wholeDayHRVToday: 25,
            calendar: calendar
        )

        XCTAssertEqual(
            ReadinessScoreCalculator.summary(
                on: scoreDay, healthSummary: .empty, trends: highWholeDayToday, calendar: calendar
            ).score,
            ReadinessScoreCalculator.summary(
                on: scoreDay, healthSummary: .empty, trends: lowWholeDayToday, calendar: calendar
            ).score,
            "whole-day HRV must be ignored on days the overnight-qualified value is missing"
        )
    }

    /// The multiplicative redesign must not let great sleep rescue a crashed
    /// autonomic core — the exact dilution failure of the weighted average.
    func testCrashedAutonomicCannotBeRescuedByPerfectSleep() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        var trends = HealthTrendSnapshot.empty
        // Realistic HRV variance (±10 around 60) keeps the robust spread off
        // the MAD floor, modelling a moderate crash rather than a floor-tight
        // outlier the old severe-limiter would already catch.
        trends.heartRateVariability = variedSeries(
            baseline: 60,
            offsets: [-10, -5, 5, 10, 0],
            today: 50,
            on: scoreDay,
            calendar: calendar
        )
        trends.restingHeartRate = constantSeries(baseline: 58, today: 62, on: scoreDay, calendar: calendar)
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 8 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 8, awakeHours: 0, calendar: calendar)
                )
            )
        ])

        let score = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar
        ).score)

        XCTAssertLessThanOrEqual(score, 30, "perfect sleep must not dilute a crashed autonomic core")
    }

    /// Extreme vitals anomalies must keep forcing a Poor-band score even with
    /// a neutral autonomic core (replacement for the old severe limiter).
    func testSevereVitalsAnomalyCapsScoreAtPoor() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = constantSeries(baseline: 60, today: 60, on: scoreDay, calendar: calendar)
        trends.restingHeartRate = constantSeries(baseline: 58, today: 58, on: scoreDay, calendar: calendar)
        trends.wristTemperature = constantSeries(baseline: 35.7, today: 36.5, on: scoreDay, calendar: calendar)

        let score = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar
        ).score)

        XCTAssertLessThanOrEqual(score, 25, "a severe temperature anomaly must cap readiness at Poor")
        XCTAssertTrue(
            ReadinessScoreCalculator.summary(
                on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar
            ).drivers.contains { $0.kind == .wristTemperatureAboveBaseline }
        )
    }

    /// Duration-only nights (no stage snapshot) must score sleep on duration
    /// alone instead of treating the missing continuity as zero.
    func testDurationOnlySleepUsesDurationProgressAlone() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = constantSeries(baseline: 60, today: 60, on: scoreDay, calendar: calendar)
        trends.restingHeartRate = constantSeries(baseline: 58, today: 58, on: scoreDay, calendar: calendar)
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(date: scoreDay, summary: SleepSummary(duration: 7.9 * 3_600))
        ])

        let score = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar
        ).score)

        XCTAssertGreaterThanOrEqual(score, 68, "a near-goal duration-only night must not be hidden-penalized")
    }

    /// A day with every metric at its own baseline and decent sleep should
    /// land in the Moderate band — typical is no longer inflated to High.
    func testTypicalDayLandsInModerateBand() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = constantSeries(baseline: 60, today: 60, on: scoreDay, calendar: calendar)
        trends.restingHeartRate = constantSeries(baseline: 58, today: 58, on: scoreDay, calendar: calendar)
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 7.6 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 7.6, awakeHours: 0.3, calendar: calendar)
                )
            )
        ])

        let score = try XCTUnwrap(ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar
        ).score)

        XCTAssertTrue((65...79).contains(score), "typical day scored \(score), expected Moderate band")
    }

    /// Without any autonomic data the core is neutral-filled, so confidence
    /// must be capped at .low no matter how rich the other components are.
    func testNeutralAutonomicCoreCapsConfidenceAtLow() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        var trends = HealthTrendSnapshot.empty
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        var sleepDays: [SleepDaySummary] = []
        for offset in 0...30 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                continue
            }
            sleepDays.append(SleepDaySummary(date: date, summary: SleepSummary(duration: 7.9 * 3_600)))
        }
        trends.sleepHistory = SleepHistorySnapshot(days: sleepDays)

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar
        )

        XCTAssertNotNil(summary.score)
        XCTAssertEqual(summary.confidence, .low, "neutral autonomic core must cap confidence at low")
    }

    // MARK: - Activity drain + frozen morning record

    func testActivityDrainLowersLiveScoreButNotHistoryToday() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        let undrained = try XCTUnwrap(
            ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar).score
        )

        let workout = WorkoutSummary(
            type: .running,
            startDate: scoreDay.addingTimeInterval(12 * 3_600),
            duration: 3_600,
            effortLevel: 9
        )
        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(on: scoreDay, calendar: calendar, todaysWorkouts: [workout])

        let live = try XCTUnwrap(snapshot.summary.readiness.score)
        XCTAssertLessThan(live, undrained, "live tile should drop after a hard workout")
        let todayHistory = try XCTUnwrap(snapshot.trends.readiness.point(on: scoreDay)?.value)
        XCTAssertEqual(Int(todayHistory), undrained, "history today point must stay at the undrained morning value")
    }

    // MARK: - Low-end display softening (draining call-site: raw-before-clamp + cap)

    private func readinessSummary(score: Int?) -> ReadinessSummary {
        ReadinessSummary(
            score: score,
            status: ReadinessStatus.status(for: score ?? 0),
            confidence: .low,
            components: [],
            drivers: []
        )
    }

    private func drainWorkout(minutes: Double, effort: Double, type: BodyWorkoutType = .running) -> WorkoutSummary {
        WorkoutSummary(
            type: type,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: minutes * 60,
            effortLevel: effort
        )
    }

    func testDrainingSoftensRawZeroToFivePercent() {
        // A workout whose (rounded) drain equals the baseline pushes the raw score to 0.
        let run = drainWorkout(minutes: 60, effort: 9)
        let drain = Int(ActivityReadinessImpact.drainPoints(workouts: [run]).rounded())
        XCTAssertGreaterThanOrEqual(drain, 5, "fixture must drain enough for the floor to apply")
        let drained = HealthDashboardSnapshot.draining(readinessSummary(score: drain), with: [run])
        XCTAssertEqual(drained.score, 5, "raw 0 should show the 5% floor, not 0")
    }

    func testDrainingEasesOnePointBelowFloor() {
        // Baseline set 5 below the drain → raw −5 → one point below the floor.
        let run = drainWorkout(minutes: 60, effort: 9)
        let drain = Int(ActivityReadinessImpact.drainPoints(workouts: [run]).rounded())
        let drained = HealthDashboardSnapshot.draining(readinessSummary(score: drain - 5), with: [run])
        XCTAssertEqual(drained.score, 4, "raw −5 should ease one point below the 5% floor")
    }

    func testDrainingNeverLiftsAnAlreadyLowBaseline() {
        // The bug the adversarial review caught: a tiny drain on a 4% baseline must NOT
        // raise the shown score to the 5% floor (that would read as a workout *raising*
        // readiness). The cap holds it at the undrained baseline.
        let walk = drainWorkout(minutes: 8, effort: 2, type: .walking)
        XCTAssertGreaterThanOrEqual(
            ActivityReadinessImpact.drainPoints(workouts: [walk]), 0.5,
            "fixture must clear the drain gate"
        )
        let drained = HealthDashboardSnapshot.draining(readinessSummary(score: 4), with: [walk])
        XCTAssertEqual(drained.score, 4, "drain must never push the displayed score above the baseline")
    }

    func testDrainingShowsZeroOnlyAtDeepDeficit() {
        // Baseline 20 with the drain capped at 45 → raw −25 → displayed 0.
        let heavy = (0..<5).map { _ in drainWorkout(minutes: 180, effort: 10) }
        XCTAssertEqual(
            ActivityReadinessImpact.drainPoints(workouts: heavy),
            ActivityReadinessImpact.totalDrainCap, accuracy: 0.0001
        )
        let drained = HealthDashboardSnapshot.draining(readinessSummary(score: 20), with: heavy)
        XCTAssertEqual(drained.score, 0)
    }

    func testDrainAppliesWithoutFreezing() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        let undrained = try XCTUnwrap(
            ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar).score
        )

        let workout = WorkoutSummary(
            type: .running,
            startDate: scoreDay.addingTimeInterval(12 * 3_600),
            duration: 3_600,
            effortLevel: 9
        )
        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay,
                calendar: calendar,
                todaysWorkouts: [workout],
                freezesRecordedReadiness: false
            )

        XCTAssertLessThan(try XCTUnwrap(snapshot.summary.readiness.score), undrained)
        XCTAssertTrue(snapshot.trends.recordedReadiness.isEmpty, "freeze:false must not write a record")
    }

    func testFreezeIsIdempotentWithinWindow() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let base = HealthDashboardSnapshot(summary: .empty, trends: moderateDayTrends(on: scoreDay, calendar: calendar))

        let first = base.recalculatingReadiness(
            on: scoreDay,
            calendar: calendar,
            wakeTime: wake,
            now: scoreDay.addingTimeInterval(11 * 3_600),
            freezesRecordedReadiness: true
        )
        XCTAssertEqual(first.trends.recordedReadiness.count, 1)
        let frozen = try XCTUnwrap(first.trends.recordedReadiness.first?.score)

        let second = first.recalculatingReadiness(
            on: scoreDay,
            calendar: calendar,
            wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600),
            freezesRecordedReadiness: true
        )
        XCTAssertEqual(second.trends.recordedReadiness.count, 1, "freeze must be idempotent")
        XCTAssertEqual(second.trends.recordedReadiness.first?.score, frozen)
    }

    func testFreezeWindowAndTenAMFallback() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let base = HealthDashboardSnapshot(summary: .empty, trends: moderateDayTrends(on: scoreDay, calendar: calendar))

        // Wake unknown → fallback freeze at 10:00 local. Before 10:00: no record.
        let early = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: nil,
            now: scoreDay.addingTimeInterval(9 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertTrue(early.trends.recordedReadiness.isEmpty, "no freeze before the 10:00 fallback")

        // After 10:00, within the day: record written.
        let onTime = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: nil,
            now: scoreDay.addingTimeInterval(10 * 3_600 + 1_800), freezesRecordedReadiness: true
        )
        XCTAssertEqual(onTime.trends.recordedReadiness.count, 1, "freeze at/after the 10:00 fallback")

        // Past end of the day: no record (never freeze a stale late value).
        let late = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: nil,
            now: scoreDay.addingTimeInterval(25 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertTrue(late.trends.recordedReadiness.isEmpty, "no freeze after the freeze window closes")
    }

    func testFrozenValueImmuneToLaterMorningInputChange() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let frozenSnapshot = HealthDashboardSnapshot(summary: .empty, trends: moderateDayTrends(on: scoreDay, calendar: calendar))
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let frozen = try XCTUnwrap(frozenSnapshot.trends.recordedReadiness.first?.score)

        // Crash today's HRV, then recompute: the record and the chart's today
        // point must stay pinned to the frozen morning value.
        var mutated = frozenSnapshot
        mutated.trends.heartRateVariability = constantSeries(baseline: 60, today: 15, on: scoreDay, calendar: calendar)
        let after = mutated.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )

        XCTAssertEqual(after.trends.recordedReadiness.first?.score, frozen, "frozen record must not move")
        XCTAssertEqual(Int(try XCTUnwrap(after.trends.readiness.point(on: scoreDay)?.value)), frozen, "chart pinned to frozen value")
    }

    func testChartPrefersFrozenRecordReplacedInPlace() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        var trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        trends.recordedReadiness = [RecordedReadinessEntry(date: scoreDay, score: 42)]

        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(on: scoreDay, calendar: calendar)

        let sameDayPoints = snapshot.trends.readiness.points.filter { calendar.isDate($0.date, inSameDayAs: scoreDay) }
        XCTAssertEqual(sameDayPoints.count, 1, "overlay must replace in place, not append a duplicate")
        XCTAssertEqual(snapshot.trends.readiness.point(on: scoreDay)?.value, 42)
    }

    func testOverlayDoesNotInsertPhantomPointForUncomputedDay() throws {
        let calendar = Calendar.bodyGregorian
        let dayA = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let dayB = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: dayA))
        let series = HealthTrendSeries(points: [HealthTrendDataPoint(date: dayA, value: 70)])

        // A record for a day with no computed point must NOT be inserted — so a
        // stale frozen value can't leak back when readiness is uncomputable.
        let overlaid = series.applyingRecordedOverrides(
            [RecordedReadinessEntry(date: dayB, score: 88)],
            calendar: calendar
        )
        XCTAssertNil(overlaid.point(on: dayB))
        XCTAssertEqual(overlaid.point(on: dayA)?.value, 70)
    }

    func testNoFreezePathDoesNotMutateRecord() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        var trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        trends.recordedReadiness = [RecordedReadinessEntry(date: scoreDay, score: 50)]

        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: false
            )
        XCTAssertEqual(snapshot.trends.recordedReadiness, [RecordedReadinessEntry(date: scoreDay, score: 50)])
    }

    func testRecordContextChangeDropsFrozenRecordsAndRestamps() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        var trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        trends.recordedReadiness = [RecordedReadinessEntry(date: scoreDay, score: 50)]
        trends.recordedReadinessContext = "old-context"
        let base = HealthDashboardSnapshot(summary: .empty, trends: trends)
        let now = scoreDay.addingTimeInterval(11 * 3_600)

        // A changed input context drops the stale records and re-stamps the signature.
        let changed = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, now: now,
            freezesRecordedReadiness: false, recordedReadinessContext: "new-context"
        )
        XCTAssertTrue(changed.trends.recordedReadiness.isEmpty)
        XCTAssertEqual(changed.trends.recordedReadinessContext, "new-context")

        // The same context preserves the records.
        let same = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, now: now,
            freezesRecordedReadiness: false, recordedReadinessContext: "old-context"
        )
        XCTAssertEqual(same.trends.recordedReadiness, [RecordedReadinessEntry(date: scoreDay, score: 50)])

        // A nil context (the caller asserts nothing) leaves records and signature untouched.
        let untouched = base.recalculatingReadiness(
            on: scoreDay, calendar: calendar, now: now,
            freezesRecordedReadiness: false, recordedReadinessContext: nil
        )
        XCTAssertEqual(untouched.trends.recordedReadiness, [RecordedReadinessEntry(date: scoreDay, score: 50)])
        XCTAssertEqual(untouched.trends.recordedReadinessContext, "old-context")
    }

    func testLiveScoreFlooredAtZeroUnderHeavyDrain() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = constantSeries(baseline: 65, today: 15, on: scoreDay, calendar: calendar)
        trends.restingHeartRate = constantSeries(baseline: 52, today: 85, on: scoreDay, calendar: calendar)
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.6)])
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 4.0 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 4.0, awakeHours: 1.0, calendar: calendar)
                )
            )
        ])
        let undrained = try XCTUnwrap(
            ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar).score
        )

        let huge = WorkoutSummary(type: .hiit, startDate: scoreDay.addingTimeInterval(12 * 3_600), duration: 600 * 60, effortLevel: 10)
        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(on: scoreDay, calendar: calendar, todaysWorkouts: [huge, huge, huge])

        let live = try XCTUnwrap(snapshot.summary.readiness.score)
        XCTAssertGreaterThanOrEqual(live, 0, "live score must never go negative")
        XCTAssertLessThanOrEqual(live, undrained)
    }

    func testRecordedReadinessSurvivesCodableRoundTrip() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let dayBefore = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: scoreDay))
        let twoDaysBefore = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: scoreDay))
        var trends = HealthTrendSnapshot.empty
        trends.recordedReadiness = [
            RecordedReadinessEntry(date: scoreDay, score: 77, includedSleep: true),
            RecordedReadinessEntry(date: dayBefore, score: 55, includedSleep: false),
            RecordedReadinessEntry(date: twoDaysBefore, score: 60, includedSleep: nil)
        ]

        let data = try JSONEncoder().encode(trends)
        let decoded = try JSONDecoder().decode(HealthTrendSnapshot.self, from: data)
        XCTAssertEqual(decoded.recordedReadiness, trends.recordedReadiness)
    }

    func testSleeplessMorningRecordUpgradesOnceWhenSleepArrives() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let sleepTrends = moderateDayTrends(on: scoreDay, calendar: calendar)
        var sleeplessTrends = sleepTrends
        sleeplessTrends.sleepHistory = SleepHistorySnapshot(days: [])

        // Freeze before today's sleep synced → record tagged includedSleep == false.
        let frozen = HealthDashboardSnapshot(summary: .empty, trends: sleeplessTrends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let sleeplessRecord = try XCTUnwrap(frozen.trends.recordedReadiness.first)
        XCTAssertEqual(sleeplessRecord.includedSleep, false)

        // A short, fragmented night syncs — clearly lower than the sleepless score.
        var sleepArrivedTrends = sleeplessTrends
        sleepArrivedTrends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 4.0 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 4.0, awakeHours: 1.0, calendar: calendar)
                )
            )
        ])

        // Sleep syncs; recompute swaps in the sleep-inclusive score, once.
        var withSleep = frozen
        withSleep.trends.sleepHistory = sleepArrivedTrends.sleepHistory
        let upgraded = withSleep.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        let expected = try XCTUnwrap(
            ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: sleepArrivedTrends, calendar: calendar).score
        )
        let record = try XCTUnwrap(upgraded.trends.recordedReadiness.first)
        XCTAssertEqual(upgraded.trends.recordedReadiness.count, 1)
        XCTAssertEqual(record.includedSleep, true)
        XCTAssertEqual(record.score, expected)
        XCTAssertNotEqual(record.score, sleeplessRecord.score, "sleep-inclusive score replaces the sleepless one")
    }

    func testUpgradedRecordImmuneToFurtherRecomputes() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let sleepTrends = moderateDayTrends(on: scoreDay, calendar: calendar)
        var sleeplessTrends = sleepTrends
        sleeplessTrends.sleepHistory = SleepHistorySnapshot(days: [])

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: sleeplessTrends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        var withSleep = frozen
        withSleep.trends.sleepHistory = sleepTrends.sleepHistory
        let upgraded = withSleep.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        let upgradedRecord = try XCTUnwrap(upgraded.trends.recordedReadiness.first)
        XCTAssertEqual(upgradedRecord.includedSleep, true)

        // Crash today's HRV and recompute again: the upgraded record must not move.
        var mutated = upgraded
        mutated.trends.heartRateVariability = constantSeries(baseline: 60, today: 15, on: scoreDay, calendar: calendar)
        let after = mutated.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(13 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertEqual(after.trends.recordedReadiness.count, 1)
        XCTAssertEqual(after.trends.recordedReadiness.first, upgradedRecord, "upgraded record is immune to later recomputes")
    }

    func testRecordFrozenWithSleepIsNeverReplaced() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let trends = moderateDayTrends(on: scoreDay, calendar: calendar)

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let record = try XCTUnwrap(frozen.trends.recordedReadiness.first)
        XCTAssertEqual(record.includedSleep, true, "frozen with today's sleep present")

        // A later recompute — sleep still present — must never replace it.
        var mutated = frozen
        mutated.trends.heartRateVariability = constantSeries(baseline: 60, today: 15, on: scoreDay, calendar: calendar)
        let after = mutated.recalculatingReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        XCTAssertEqual(after.trends.recordedReadiness.first, record, "a sleep-inclusive record is never replaced")
    }

    func testLegacyNilFlagRecordUpgradesWhenSleepArrives() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        var trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        // Legacy record persisted before the flag existed → includedSleep nil.
        trends.recordedReadiness = [RecordedReadinessEntry(date: scoreDay, score: 42, includedSleep: nil)]

        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        let expected = try XCTUnwrap(
            ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: moderateDayTrends(on: scoreDay, calendar: calendar), calendar: calendar).score
        )
        let record = try XCTUnwrap(snapshot.trends.recordedReadiness.first)
        XCTAssertEqual(snapshot.trends.recordedReadiness.count, 1)
        XCTAssertEqual(record.includedSleep, true)
        XCTAssertEqual(record.score, expected)
        XCTAssertNotEqual(record.score, 42, "legacy nil-flag record is replaced by the sleep-inclusive score")
    }

    func testUpgradeBlockedOutsideScoreDayWindow() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        var trends = moderateDayTrends(on: scoreDay, calendar: calendar)
        let sleepless = RecordedReadinessEntry(date: scoreDay, score: 42, includedSleep: false)
        trends.recordedReadiness = [sleepless]

        // Sleep is present now, but the recompute runs past the score day's end,
        // so the freeze window is closed and the record must not be rewritten.
        let snapshot = HealthDashboardSnapshot(summary: .empty, trends: trends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(25 * 3_600), freezesRecordedReadiness: true
            )
        XCTAssertEqual(snapshot.trends.recordedReadiness, [sleepless])
    }

    func testLegacyRecordedReadinessJSONDecodesWithNilFlag() throws {
        // A record persisted before the includedSleep flag existed omits the key.
        let json = Data(#"{"date":0,"score":77}"#.utf8)
        let decoded = try JSONDecoder().decode(RecordedReadinessEntry.self, from: json)
        XCTAssertNil(decoded.includedSleep)
        XCTAssertEqual(decoded.score, 77)
        XCTAssertEqual(decoded.date, Date(timeIntervalSinceReferenceDate: 0))
    }

    func testReapplyingActivityReadinessUpgradesSleeplessRecord() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let wake = scoreDay.addingTimeInterval(7 * 3_600)
        let sleepTrends = moderateDayTrends(on: scoreDay, calendar: calendar)
        var sleeplessTrends = sleepTrends
        sleeplessTrends.sleepHistory = SleepHistorySnapshot(days: [])

        let frozen = HealthDashboardSnapshot(summary: .empty, trends: sleeplessTrends)
            .recalculatingReadiness(
                on: scoreDay, calendar: calendar, wakeTime: wake,
                now: scoreDay.addingTimeInterval(11 * 3_600), freezesRecordedReadiness: true
            )
        XCTAssertEqual(frozen.trends.recordedReadiness.first?.includedSleep, false)

        var withSleep = frozen
        withSleep.trends.sleepHistory = sleepTrends.sleepHistory
        let upgraded = withSleep.reapplyingActivityReadiness(
            on: scoreDay, calendar: calendar, wakeTime: wake,
            now: scoreDay.addingTimeInterval(12 * 3_600), freezesRecordedReadiness: true
        )
        let expected = try XCTUnwrap(
            ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: sleepTrends, calendar: calendar).score
        )
        let record = try XCTUnwrap(upgraded.trends.recordedReadiness.first)
        XCTAssertEqual(upgraded.trends.recordedReadiness.count, 1)
        XCTAssertEqual(record.includedSleep, true)
        XCTAssertEqual(record.score, expected)
    }

    func testReplacingReadinessMetricPreservesRecordedReadiness() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        var trends = HealthTrendSnapshot.empty
        trends.recordedReadiness = [RecordedReadinessEntry(date: scoreDay, score: 77)]

        let replaced = trends.replacingMetric(.readiness, with: .empty)
        XCTAssertEqual(replaced.recordedReadiness, trends.recordedReadiness, "carry-forward foundation: replacingMetric keeps the record")
    }

    private func moderateDayTrends(on scoreDay: Date, calendar: Calendar) -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = constantSeries(baseline: 60, today: 60, on: scoreDay, calendar: calendar)
        trends.restingHeartRate = constantSeries(baseline: 58, today: 58, on: scoreDay, calendar: calendar)
        trends.trainingLoad = HealthTrendSeries(points: [HealthTrendDataPoint(date: scoreDay, value: 1.0)])
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: scoreDay,
                summary: SleepSummary(
                    duration: 7.6 * 3_600,
                    stageSnapshot: stageSnapshot(on: scoreDay, asleepHours: 7.6, awakeHours: 0.3, calendar: calendar)
                )
            )
        ])
        return trends
    }

    // MARK: - Helpers

    private func trendsWithSleepDuration(
        _ duration: TimeInterval,
        on date: Date,
        calendar: Calendar
    ) -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.sleepHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(date: date, summary: SleepSummary(duration: duration))
        ])
        return trends
    }

    private func trendsWithSleepDurationForEachDay(
        _ duration: TimeInterval,
        startDay: Date,
        endDay: Date,
        calendar: Calendar
    ) -> HealthTrendSnapshot {
        var days: [SleepDaySummary] = []
        var day = calendar.startOfDay(for: startDay)
        let lastDay = calendar.startOfDay(for: endDay)
        while day <= lastDay {
            days.append(SleepDaySummary(date: day, summary: SleepSummary(duration: duration)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = next
        }
        var trends = HealthTrendSnapshot.empty
        trends.sleepHistory = SleepHistorySnapshot(days: days)
        return trends
    }

    private func dailyValues(
        constants: [Double],
        endingDayBefore scoreDay: Date,
        calendar: Calendar
    ) -> [ReadinessScoreCalculator.DailyValue] {
        constants.enumerated().compactMap { offset, value in
            // Place values starting one day before scoreDay, going back in time.
            // This guarantees they fall inside the 56-day pre-window.
            guard let date = calendar.date(byAdding: .day, value: -(offset + 1), to: scoreDay) else {
                return nil
            }

            return ReadinessScoreCalculator.DailyValue(date: date, value: value)
        }
    }

    /// 28 prior days at `baseline` plus the scoring day at `today`.
    private func constantSeries(
        baseline: Double,
        today: Double,
        on scoreDay: Date,
        calendar: Calendar
    ) -> HealthTrendSeries {
        variedSeries(baseline: baseline, offsets: [0], today: today, on: scoreDay, calendar: calendar)
    }

    /// 28 prior days cycling `baseline + offsets[i % count]` plus the scoring
    /// day at `today`.
    private func variedSeries(
        baseline: Double,
        offsets: [Double],
        today: Double,
        on scoreDay: Date,
        calendar: Calendar
    ) -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []
        for offset in 1...28 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                continue
            }
            points.append(HealthTrendDataPoint(date: date, value: baseline + offsets[(offset - 1) % offsets.count]))
        }
        points.append(HealthTrendDataPoint(date: scoreDay, value: today))
        return HealthTrendSeries(points: points)
    }

    /// One awake segment followed by one asleep segment so that the snapshot
    /// interval spans `asleepHours + awakeHours` with the given awake total.
    private func stageSnapshot(
        on day: Date,
        asleepHours: Double,
        awakeHours: Double,
        calendar: Calendar
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

    /// Whole-day HRV/HR at steady baselines, plus `overnightNights` prior
    /// nights of overnight vitals (HRV 60, HR 58) and an optional overnight
    /// HRV for the scoring day. `overnightHRVToday == nil` leaves the scoring
    /// night without an HRV reading (overnight HR still present).
    private func autonomicTrends(
        on scoreDay: Date,
        overnightNights: Int,
        overnightHRVToday: Double?,
        wholeDayHRVToday: Double = 62,
        calendar: Calendar
    ) -> HealthTrendSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = constantSeries(
            baseline: 62,
            today: wholeDayHRVToday,
            on: scoreDay,
            calendar: calendar
        )
        trends.restingHeartRate = constantSeries(baseline: 58, today: 58, on: scoreDay, calendar: calendar)

        // Sleep nights are always present so every variant scores the same
        // sleep component; only the vitals hydration differs.
        var days: [SleepDaySummary] = []
        for offset in 1...21 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                continue
            }
            let vitals = offset <= overnightNights
                ? SleepVitalsSummary(heartRate: 58, heartRateVariability: 60)
                : SleepVitalsSummary.empty
            days.append(SleepDaySummary(
                date: date,
                summary: SleepSummary(duration: 7.9 * 3_600, vitals: vitals)
            ))
        }
        let todayVitals = overnightNights > 0
            ? SleepVitalsSummary(heartRate: 58, heartRateVariability: overnightHRVToday)
            : SleepVitalsSummary.empty
        days.append(SleepDaySummary(
            date: scoreDay,
            summary: SleepSummary(duration: 7.9 * 3_600, vitals: todayVitals)
        ))
        trends.sleepHistory = SleepHistorySnapshot(days: days)
        return trends
    }

    private struct ExportFixture {
        var trends: HealthTrendSnapshot
        var daysByName: [String: Date]
    }

    /// The May 30 – Jun 11 2026 Apple Health export preceded by 45 synthetic
    /// days with realistic variance (constant fixtures would collapse the
    /// robust spread to the MAD floor and dodge the production failure mode).
    private func exportFixture(calendar: Calendar) throws -> ExportFixture {
        let may30 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30)))

        // (name, hrv, rhr, respRate, spo2, wristTemp, asleepH, awakeH, acwr)
        let exportDays: [(String, Double, Double, Double, Double, Double?, Double, Double, Double)] = [
            ("May30", 61.94, 53.25, 14.95, 97.66, 35.51, 7.57, 0.15, 0.79),
            ("May31", 84.05, 86.09, 15.51, 97.20, 35.81, 7.64, 0.18, 0.89),
            ("Jun01", 45.33, 64.58, 16.14, 97.74, 35.41, 8.12, 0.04, 1.21),
            ("Jun02", 25.88, 65.11, 14.91, 96.21, 35.91, 7.77, 0.44, 1.09),
            ("Jun03", 94.35, 71.93, 14.81, 96.87, 35.73, 7.58, 0.11, 1.20),
            ("Jun04", 34.26, 68.87, 14.86, 97.41, 35.71, 7.69, 0.30, 0.94),
            ("Jun05", 52.03, 66.23, 15.34, 97.15, 35.58, 7.27, 0.39, 1.02),
            ("Jun06", 65.51, 65.77, 15.41, 96.76, 35.76, 7.77, 0.73, 0.97),
            ("Jun07", 87.01, 56.00, 15.25, 96.65, nil, 9.38, 0.60, 1.22),
            ("Jun08", 95.59, 52.00, 15.17, 96.96, 35.80, 7.76, 0.48, 0.96),
            ("Jun09", 51.36, 61.00, 15.20, 97.55, 35.91, 9.15, 0.46, 0.75),
            ("Jun10", 49.19, 60.00, 15.13, 97.20, 35.63, 7.99, 0.46, 1.04),
            ("Jun11", 89.40, 64.00, 15.25, 96.60, 35.82, 7.83, 0.74, 0.95)
        ]

        // Variance matched to the real export window (whole-day HRV MAD ≈ 22
        // → robust spread ≈ 33 ms). Tighter synthetic baselines would let the
        // old severe-limiter catch the crash days and hide the compression
        // failure this fixture exists to reproduce.
        let hrvOffsets = [-35.0, -22, 22, 35, 0]
        let heartRateOffsets = [-6.0, -3, 3, 6, 0]
        let respiratoryOffsets = [-0.5, -0.25, 0.25, 0.5, 0]
        let oxygenOffsets = [-0.6, -0.3, 0.3, 0.6, 0]
        let temperatureOffsets = [-0.2, -0.1, 0.1, 0.2, 0]
        let sleepOffsets = [-0.4, 0.4, 0, -0.2, 0.2]

        var hrv: [HealthTrendDataPoint] = []
        var heartRate: [HealthTrendDataPoint] = []
        var respiratory: [HealthTrendDataPoint] = []
        var oxygen: [HealthTrendDataPoint] = []
        var temperature: [HealthTrendDataPoint] = []
        var trainingLoad: [HealthTrendDataPoint] = []
        var sleepDays: [SleepDaySummary] = []

        for index in 0..<45 {
            guard let date = calendar.date(byAdding: .day, value: index - 45, to: may30) else {
                continue
            }
            hrv.append(HealthTrendDataPoint(date: date, value: 62 + hrvOffsets[index % 5]))
            heartRate.append(HealthTrendDataPoint(date: date, value: 60 + heartRateOffsets[index % 5]))
            respiratory.append(HealthTrendDataPoint(date: date, value: 15.2 + respiratoryOffsets[index % 5]))
            oxygen.append(HealthTrendDataPoint(date: date, value: 97.2 + oxygenOffsets[index % 5]))
            temperature.append(HealthTrendDataPoint(date: date, value: 35.7 + temperatureOffsets[index % 5]))
            trainingLoad.append(HealthTrendDataPoint(date: date, value: 1.0))
            sleepDays.append(SleepDaySummary(
                date: date,
                summary: SleepSummary(duration: (7.9 + sleepOffsets[index % 5]) * 3_600)
            ))
        }

        var daysByName: [String: Date] = [:]
        for (offset, day) in exportDays.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: offset, to: may30) else {
                continue
            }
            daysByName[day.0] = date
            hrv.append(HealthTrendDataPoint(date: date, value: day.1))
            heartRate.append(HealthTrendDataPoint(date: date, value: day.2))
            respiratory.append(HealthTrendDataPoint(date: date, value: day.3))
            oxygen.append(HealthTrendDataPoint(date: date, value: day.4))
            if let wristTemperature = day.5 {
                temperature.append(HealthTrendDataPoint(date: date, value: wristTemperature))
            }
            trainingLoad.append(HealthTrendDataPoint(date: date, value: day.8))
            sleepDays.append(SleepDaySummary(
                date: date,
                summary: SleepSummary(
                    duration: day.6 * 3_600,
                    stageSnapshot: stageSnapshot(
                        on: date,
                        asleepHours: day.6,
                        awakeHours: day.7,
                        calendar: calendar
                    )
                )
            ))
        }

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = HealthTrendSeries(points: hrv)
        trends.restingHeartRate = HealthTrendSeries(points: heartRate)
        trends.respiratoryRate = HealthTrendSeries(points: respiratory)
        trends.oxygenSaturation = HealthTrendSeries(points: oxygen)
        trends.wristTemperature = HealthTrendSeries(points: temperature)
        trends.trainingLoad = HealthTrendSeries(points: trainingLoad)
        trends.sleepHistory = SleepHistorySnapshot(days: sleepDays)
        return ExportFixture(trends: trends, daysByName: daysByName)
    }
}
