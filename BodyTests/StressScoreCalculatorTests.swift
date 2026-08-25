//
//  StressScoreCalculatorTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class StressScoreCalculatorTests: XCTestCase {
    // MARK: - Fixtures

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 0, minute: 0)) ?? Date()
    }

    /// Two heart-rate samples 6 minutes apart in each window — just past the
    /// minimum-coverage rule.
    private func heartRateSamples(
        dayStart: Date,
        windowRange: Range<Int>,
        value: Double
    ) -> [HealthTrendDataPoint] {
        windowRange.flatMap { index -> [HealthTrendDataPoint] in
            let start = dayStart.addingTimeInterval(Double(index) * 900)
            return [
                HealthTrendDataPoint(date: start.addingTimeInterval(60), value: value),
                HealthTrendDataPoint(date: start.addingTimeInterval(420), value: value)
            ]
        }
    }

    private func dailyValues(
        endingBefore scoringDay: Date,
        dayCount: Int,
        value: Double
    ) -> [ReadinessScoreCalculator.DailyValue] {
        (1...max(1, dayCount)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoringDay) else {
                return nil
            }

            return ReadinessScoreCalculator.DailyValue(date: date, value: value)
        }
    }

    private func dailyPoints(
        endingBefore scoringDay: Date,
        dayCount: Int,
        value: Double
    ) -> [HealthTrendDataPoint] {
        dailyValues(endingBefore: scoringDay, dayCount: dayCount, value: value)
            .map { HealthTrendDataPoint(date: $0.date, value: $0.value) }
    }

    /// Quiet HR baseline: median 70, spread pinned to the 3 bpm floor (constant history).
    /// SDNN baseline: median 50, spread pinned to the 5-unit floor.
    private func makeBaselines(
        scoringDay: Date,
        quietHeartRateDayCount: Int = 30,
        sdnnDayCount: Int = 30,
        rmssdDayCount: Int = 0
    ) -> StressBaselines {
        StressScoreCalculator.baselines(
            for: scoringDay,
            quietHeartRateDailyMedians: dailyValues(
                endingBefore: scoringDay,
                dayCount: quietHeartRateDayCount,
                value: 70
            ),
            sdnnSamples: sdnnDayCount > 0
                ? dailyPoints(endingBefore: scoringDay, dayCount: sdnnDayCount, value: 50)
                : [],
            rmssdSamples: rmssdDayCount > 0
                ? dailyPoints(endingBefore: scoringDay, dayCount: rmssdDayCount, value: 40)
                : [],
            calendar: calendar
        )
    }

    private func heartRateScore(_ z: Double) -> Double {
        100 / (1 + exp(-StressScoreCalculator.Tuning.heartRateLogisticSteepness
            * (z - StressScoreCalculator.Tuning.heartRateLogisticMidpoint)))
    }

    // MARK: - Grid

    func testNormalDayProduces96Windows() {
        let scoringDay = day(2024, 5, 15)
        let intervals = StressScoreCalculator.windowIntervals(
            for: scoringDay,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(intervals.count, 96)
        XCTAssertEqual(intervals.first?.start, scoringDay)
    }

    func testSpringForwardDayProduces92Windows() {
        let intervals = StressScoreCalculator.windowIntervals(
            for: day(2024, 3, 10),
            calendar: calendar,
            now: day(2024, 3, 20)
        )

        XCTAssertEqual(intervals.count, 92)
    }

    func testFallBackDayProduces100Windows() {
        let intervals = StressScoreCalculator.windowIntervals(
            for: day(2024, 11, 3),
            calendar: calendar,
            now: day(2024, 11, 10)
        )

        XCTAssertEqual(intervals.count, 100)
    }

    /// A sample exactly at next midnight belongs to the next day, so a past day's grid
    /// stops one second short of it.
    func testPastDayGridEndsJustInsideMidnight() throws {
        let scoringDay = day(2024, 5, 15)
        let dayEnd = try XCTUnwrap(calendar.dateInterval(of: .day, for: scoringDay)?.end)
        let intervals = StressScoreCalculator.windowIntervals(
            for: scoringDay,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(intervals.last?.end, dayEnd - 1)
    }

    func testTodayGridClampsAtNow() {
        let scoringDay = day(2024, 5, 15)
        let now = scoringDay.addingTimeInterval(3 * 3600 + 10 * 60)
        let intervals = StressScoreCalculator.windowIntervals(for: scoringDay, calendar: calendar, now: now)

        XCTAssertEqual(intervals.count, 13)
        XCTAssertEqual(intervals.last?.end, now)
    }

    // MARK: - Masking

    func testWorkoutOverlapAndTailAreMasked() {
        let scoringDay = day(2024, 5, 15)
        let workoutStart = scoringDay.addingTimeInterval(10 * 3600)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 70),
            workoutIntervals: [
                DateInterval(start: workoutStart, end: workoutStart.addingTimeInterval(3600))
            ]
        )
        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: makeBaselines(scoringDay: scoringDay),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        // 10:00-11:00 is the workout, 11:00-11:30 the recovery tail; 11:30 is clear again.
        XCTAssertTrue(windows[39].isScored)
        XCTAssertEqual(windows[40].state, .activity)
        XCTAssertEqual(windows[43].state, .activity)
        XCTAssertEqual(windows[45].state, .activity)
        XCTAssertNotEqual(windows[46].state, .activity)
    }

    func testWorkoutIntervalsUseEffectiveEndDate() {
        let start = day(2024, 5, 15).addingTimeInterval(10 * 3600)
        let paused = makeWorkout(start: start, duration: 1800, endDate: start.addingTimeInterval(3600))
        let legacy = makeWorkout(start: start, duration: 1800, endDate: nil)

        let intervals = StressDayInput.workoutIntervals(for: [paused, legacy])

        XCTAssertEqual(intervals[0].end, start.addingTimeInterval(3600))
        XCTAssertEqual(intervals[1].end, start.addingTimeInterval(1800))
    }

    func testStepAndEnergyDensityMaskWindows() {
        let scoringDay = day(2024, 5, 15)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 70),
            hourlySteps: [
                HealthTrendDataPoint(date: scoringDay.addingTimeInterval(10 * 3600), value: 900),
                HealthTrendDataPoint(date: scoringDay.addingTimeInterval(12 * 3600), value: 100)
            ],
            hourlyActiveEnergy: [
                HealthTrendDataPoint(date: scoringDay.addingTimeInterval(14 * 3600), value: 80)
            ]
        )
        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: makeBaselines(scoringDay: scoringDay),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(windows[40].state, .activity)
        XCTAssertEqual(windows[43].state, .activity)
        XCTAssertNotEqual(windows[48].state, .activity)
        XCTAssertEqual(windows[56].state, .activity)
    }

    func testMaskedWindowsAreExcludedFromTheDailyAverage() {
        let scoringDay = day(2024, 5, 15)
        let workoutStart = scoringDay.addingTimeInterval(10 * 3600)
        var samples = heartRateSamples(dayStart: scoringDay, windowRange: 0..<40, value: 70)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 40..<44, value: 150)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: samples,
            workoutIntervals: [
                DateInterval(start: workoutStart, end: workoutStart.addingTimeInterval(3600))
            ]
        )
        let baselines = makeBaselines(scoringDay: scoringDay)
        let summary = StressScoreCalculator.daySummary(
            for: input,
            baselines: baselines,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(summary.scoredWindowCount, 40)
        XCTAssertEqual(summary.band, .rest)
    }

    // MARK: - Scoring

    func testBaselineHeartRateScoresRest() throws {
        let scoringDay = day(2024, 5, 15)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 70)
        )
        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: makeBaselines(scoringDay: scoringDay, sdnnDayCount: 0),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        let score = try XCTUnwrap(windows[40].score)
        XCTAssertEqual(score, heartRateScore(0), accuracy: 0.0001)
        XCTAssertEqual(windows[40].band, .rest)
    }

    func testThreeSpreadsAboveBaselineScoresHigh() throws {
        let scoringDay = day(2024, 5, 15)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 79)
        )
        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: makeBaselines(scoringDay: scoringDay, sdnnDayCount: 0),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        let score = try XCTUnwrap(windows[40].score)
        XCTAssertEqual(score, heartRateScore(3), accuracy: 0.0001)
        XCTAssertEqual(windows[40].band, .high)
    }

    func testHeartRateOnlyWindowsAreFlagged() {
        let scoringDay = day(2024, 5, 15)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 70)
        )
        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: makeBaselines(scoringDay: scoringDay),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertTrue(windows.allSatisfy { $0.isHROnly })
        let summary = StressScoreCalculator.daySummary(windows: windows, date: scoringDay)
        XCTAssertEqual(summary.hrvCoveredWindowCount, 0)
    }

    func testDepressedHRVRaisesTheWindowScore() throws {
        let scoringDay = day(2024, 5, 15)
        let windowStart = scoringDay.addingTimeInterval(40 * 900)

        func score(sdnn: Double) throws -> Double {
            let input = StressDayInput(
                date: scoringDay,
                heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 79),
                sdnnSamples: [
                    HealthTrendDataPoint(date: windowStart.addingTimeInterval(450), value: sdnn)
                ]
            )
            let windows = StressScoreCalculator.windows(
                for: input,
                baselines: makeBaselines(scoringDay: scoringDay),
                calendar: calendar,
                now: day(2024, 5, 20)
            )
            XCTAssertFalse(windows[40].isHROnly)

            return try XCTUnwrap(windows[40].score)
        }

        let typical = try score(sdnn: 50)
        let depressed = try score(sdnn: 30)

        XCTAssertGreaterThan(depressed, typical)
        // A typical HRV reading pulls an elevated-HR window down toward Rest-like HRV.
        XCTAssertLessThan(typical, heartRateScore(3))
    }

    func testHRVInfluenceDecaysToZeroAtTheReachEdge() throws {
        let scoringDay = day(2024, 5, 15)
        let windowMidpoint = scoringDay.addingTimeInterval(40 * 900 + 450)

        func score(offset: TimeInterval) throws -> StressWindow {
            let input = StressDayInput(
                date: scoringDay,
                heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 79),
                sdnnSamples: [
                    HealthTrendDataPoint(date: windowMidpoint.addingTimeInterval(offset), value: 30)
                ]
            )

            return StressScoreCalculator.windows(
                for: input,
                baselines: makeBaselines(scoringDay: scoringDay),
                calendar: calendar,
                now: day(2024, 5, 20)
            )[40]
        }

        let near = try score(offset: 0)
        let edge = try score(offset: StressScoreCalculator.Tuning.hrvReach)
        let justInside = try score(offset: StressScoreCalculator.Tuning.hrvReach - 1)

        XCTAssertFalse(near.isHROnly)
        XCTAssertTrue(edge.isHROnly)
        XCTAssertEqual(try XCTUnwrap(edge.score), heartRateScore(3), accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(justInside.score), heartRateScore(3), accuracy: 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(near.score), try XCTUnwrap(justInside.score))
    }

    // MARK: - Gaps & calibration

    func testWindowsWithoutEnoughHeartRateCoverageAreUnscored() {
        let scoringDay = day(2024, 5, 15)
        let sparseStart = scoringDay.addingTimeInterval(41 * 900)
        var samples = heartRateSamples(dayStart: scoringDay, windowRange: 40..<41, value: 70)
        // One stray sample.
        samples.append(HealthTrendDataPoint(date: sparseStart.addingTimeInterval(60), value: 70))
        // Two samples only 4 minutes apart.
        samples.append(HealthTrendDataPoint(date: sparseStart.addingTimeInterval(900 + 60), value: 70))
        samples.append(HealthTrendDataPoint(date: sparseStart.addingTimeInterval(900 + 300 - 1), value: 70))

        let windows = StressScoreCalculator.windows(
            for: StressDayInput(date: scoringDay, heartRateSamples: samples),
            baselines: makeBaselines(scoringDay: scoringDay),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertTrue(windows[40].isScored)
        XCTAssertEqual(windows[41].state, .unscored)
        XCTAssertEqual(windows[42].state, .unscored)
        XCTAssertEqual(windows[0].state, .unscored)
    }

    func testDayWithNothingScoredHasNoAverage() {
        let scoringDay = day(2024, 5, 15)
        let summary = StressScoreCalculator.daySummary(
            for: StressDayInput(date: scoringDay),
            baselines: makeBaselines(scoringDay: scoringDay),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertNil(summary.averageScore)
        XCTAssertNil(summary.band)
        XCTAssertEqual(summary.scoredWindowCount, 0)
        XCTAssertEqual(summary.totalScoredMinutes, 0)
        XCTAssertNil(summary.minScore)
        XCTAssertNil(summary.maxScore)
    }

    /// A quiet, uneventful stretch followed by an acute stressor spreads the
    /// scored windows across a real range, so min/max must differ from the
    /// average and bracket every scored window's own score.
    func testDaySummaryMinMaxBracketTheScoredWindows() throws {
        let scoringDay = day(2024, 5, 15)
        let baselines = makeBaselines(scoringDay: scoringDay, sdnnDayCount: 0)
        var samples = heartRateSamples(dayStart: scoringDay, windowRange: 0..<40, value: 70)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 40..<96, value: 79)
        let windows = StressScoreCalculator.windows(
            for: StressDayInput(date: scoringDay, heartRateSamples: samples),
            baselines: baselines,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        let summary = StressScoreCalculator.daySummary(windows: windows, date: scoringDay)

        let scoredScores = windows.compactMap(\.score)
        let expectedMin = try XCTUnwrap(scoredScores.min())
        let expectedMax = try XCTUnwrap(scoredScores.max())
        XCTAssertLessThan(expectedMin, expectedMax, "the two heart-rate levels must produce distinct scores")
        XCTAssertEqual(summary.minScore, Int(expectedMin.rounded()))
        XCTAssertEqual(summary.maxScore, Int(expectedMax.rounded()))
        let minScore = try XCTUnwrap(summary.minScore)
        let maxScore = try XCTUnwrap(summary.maxScore)
        XCTAssertLessThanOrEqual(minScore, try XCTUnwrap(summary.averageScore))
        XCTAssertGreaterThanOrEqual(maxScore, try XCTUnwrap(summary.averageScore))
    }

    func testUncalibratedQuietHeartRateBaselineLeavesEveryWindowUnscored() {
        let scoringDay = day(2024, 5, 15)
        let baselines = makeBaselines(scoringDay: scoringDay, quietHeartRateDayCount: 13)
        XCTAssertFalse(baselines.isCalibrated)

        let workoutStart = scoringDay.addingTimeInterval(10 * 3600)
        let windows = StressScoreCalculator.windows(
            for: StressDayInput(
                date: scoringDay,
                heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 70),
                workoutIntervals: [DateInterval(start: workoutStart, end: workoutStart.addingTimeInterval(3600))]
            ),
            baselines: baselines,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(windows.count, 96)
        XCTAssertTrue(windows.allSatisfy { $0.state == .unscored })
    }

    // MARK: - Per-window HRV kind selection

    func testRMSSDIsPreferredPerWindowWithSDNNFallback() throws {
        let scoringDay = day(2024, 5, 15)
        let rmssdWindowMidpoint = scoringDay.addingTimeInterval(20 * 900 + 450)
        let sdnnWindowMidpoint = scoringDay.addingTimeInterval(60 * 900 + 450)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 79),
            sdnnSamples: [HealthTrendDataPoint(date: sdnnWindowMidpoint, value: 50)],
            rmssdSamples: [HealthTrendDataPoint(date: rmssdWindowMidpoint, value: 20)]
        )
        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: makeBaselines(scoringDay: scoringDay, rmssdDayCount: 30),
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        // The RMSSD window reads a depressed value (raises the score); the far-away SDNN
        // window still gets its own typical-HRV blend (lowers it).
        XCTAssertFalse(windows[20].isHROnly)
        XCTAssertFalse(windows[60].isHROnly)
        XCTAssertGreaterThan(try XCTUnwrap(windows[20].score), try XCTUnwrap(windows[60].score))
        // A lone RMSSD sample must not discard the day's SDNN coverage: each sample covers
        // the two windows on either side of its own, so both reaches survive.
        XCTAssertEqual(StressScoreCalculator.daySummary(windows: windows, date: scoringDay)
            .hrvCoveredWindowCount, 10)
    }

    func testUncalibratedRMSSDBaselineFallsBackToSDNNInsteadOfCalibrating() throws {
        let scoringDay = day(2024, 5, 15)
        let midpoint = scoringDay.addingTimeInterval(40 * 900 + 450)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: heartRateSamples(dayStart: scoringDay, windowRange: 0..<96, value: 79),
            sdnnSamples: [HealthTrendDataPoint(date: midpoint, value: 50)],
            rmssdSamples: [HealthTrendDataPoint(date: midpoint, value: 10)]
        )
        // Only 5 distinct RMSSD days: that kind is not calibrated yet.
        let baselines = makeBaselines(scoringDay: scoringDay, rmssdDayCount: 5)
        XCTAssertTrue(baselines.isCalibrated)
        XCTAssertNil(baselines.baseline(for: .rmssd))
        XCTAssertNotNil(baselines.baseline(for: .sdnn))

        let windows = StressScoreCalculator.windows(
            for: input,
            baselines: baselines,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        let sdnnOnlyInput = StressDayInput(
            date: scoringDay,
            heartRateSamples: input.heartRateSamples,
            sdnnSamples: input.sdnnSamples
        )
        let sdnnOnlyWindows = StressScoreCalculator.windows(
            for: sdnnOnlyInput,
            baselines: baselines,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertFalse(windows[40].isHROnly)
        XCTAssertEqual(try XCTUnwrap(windows[40].score), try XCTUnwrap(sdnnOnlyWindows[40].score), accuracy: 0.0001)
    }

    // MARK: - Baseline construction

    func testBaselinesNeedFourteenDistinctDaysNotFourteenSamples() {
        let scoringDay = day(2024, 5, 15)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: scoringDay) ?? scoringDay
        let denseSingleDay = (0..<200).map { index in
            HealthTrendDataPoint(date: previousDay.addingTimeInterval(Double(index) * 60), value: 50)
        }
        let denseQuietHeartRate = (0..<200).map { index in
            ReadinessScoreCalculator.DailyValue(
                date: previousDay.addingTimeInterval(Double(index) * 60),
                value: 70
            )
        }

        let baselines = StressScoreCalculator.baselines(
            for: scoringDay,
            quietHeartRateDailyMedians: denseQuietHeartRate,
            sdnnSamples: denseSingleDay,
            rmssdSamples: [],
            calendar: calendar
        )

        XCTAssertNil(baselines.quietHeartRate)
        XCTAssertNil(baselines.baseline(for: .sdnn))
        XCTAssertFalse(baselines.isCalibrated)
    }

    func testDailyMediansReduceEachDayToOneValue() throws {
        let scoringDay = day(2024, 5, 15)
        let points = [
            HealthTrendDataPoint(date: scoringDay.addingTimeInterval(3600), value: 10),
            HealthTrendDataPoint(date: scoringDay.addingTimeInterval(7200), value: 20),
            HealthTrendDataPoint(date: scoringDay.addingTimeInterval(10_800), value: 90),
            HealthTrendDataPoint(date: scoringDay.addingTimeInterval(-3600), value: 5)
        ]

        let medians = StressScoreCalculator.dailyMedians(of: points, calendar: calendar)

        XCTAssertEqual(medians.count, 2)
        XCTAssertEqual(medians[0].value, 5)
        XCTAssertEqual(medians[1].value, 20)
        XCTAssertEqual(medians[1].date, scoringDay)
    }

    func testQuietHeartRateDailyMedianExcludesMaskedAndSleepWindows() throws {
        let scoringDay = day(2024, 5, 15)
        // Asleep 00:00-06:00 at 50 bpm, awake at 70, workout 10:00-11:00 at 150.
        var samples = heartRateSamples(dayStart: scoringDay, windowRange: 0..<24, value: 50)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 24..<40, value: 70)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 40..<44, value: 150)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 44..<96, value: 70)
        let workoutStart = scoringDay.addingTimeInterval(10 * 3600)
        let input = StressDayInput(
            date: scoringDay,
            heartRateSamples: samples,
            workoutIntervals: [DateInterval(start: workoutStart, end: workoutStart.addingTimeInterval(3600))],
            sleepInterval: DateInterval(start: scoringDay, end: scoringDay.addingTimeInterval(6 * 3600))
        )

        let median = try XCTUnwrap(
            StressScoreCalculator.quietHeartRateDailyMedian(
                for: input,
                calendar: calendar,
                now: day(2024, 5, 20)
            )
        )

        XCTAssertEqual(median, 70, accuracy: 0.0001)
    }

    // MARK: - Daily series

    func testDailySeriesOverlaysComputedDaysOnRecordedDays() throws {
        let today = day(2024, 5, 15)
        let recordedDay = day(2024, 5, 10)
        let context = StressDailySeriesContext(
            quietHeartRateDailyMedians: dailyValues(endingBefore: today, dayCount: 40, value: 70),
            sdnnSamples: [],
            rmssdSamples: [],
            calendar: calendar
        )
        let recorded = [
            StressDaySummary(date: recordedDay, averageScore: 44),
            StressDaySummary(date: today, averageScore: 99),
            StressDaySummary(date: day(2024, 5, 12), averageScore: nil)
        ]
        let computed = [
            StressDayInput(
                date: today,
                heartRateSamples: heartRateSamples(dayStart: today, windowRange: 0..<96, value: 70)
            )
        ]

        let series = StressScoreCalculator.dailySeries(
            recorded: recorded,
            computedWindowDays: computed,
            context: context,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(series.points.count, 2)
        XCTAssertEqual(series.points[0].date, recordedDay)
        XCTAssertEqual(series.points[0].value, 44)
        XCTAssertEqual(series.points[1].date, today)
        // The freshly computed day wins over the recorded 99.
        XCTAssertEqual(series.points[1].value, Double(Int(heartRateScore(0).rounded())))
    }

    /// The baselines are per-series work, not per-day work: `dailySeries` must go through
    /// the shared context instead of rebuilding it inside the day loop.
    func testDailySeriesUsesCachedBaselineContext() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("BodyMetricsKit/StressScoreCalculator.swift"),
            encoding: .utf8
        )
        let summariesStart = try XCTUnwrap(source.range(of: "static func daySummaries(")?.lowerBound)
        let seriesStart = try XCTUnwrap(source.range(of: "static func dailySeries(")?.lowerBound)
        let baselinesMark = try XCTUnwrap(source.range(of: "// MARK: - Baselines")?.lowerBound)
        let summariesBlock = String(source[summariesStart..<seriesStart])
        let seriesBlock = String(source[seriesStart..<baselinesMark])

        XCTAssertTrue(source.contains("struct StressDailySeriesContext"))
        XCTAssertTrue(summariesBlock.contains("context.baselines(for:"))
        XCTAssertFalse(summariesBlock.contains("StressDailySeriesContext("))
        XCTAssertTrue(seriesBlock.contains("context: context"))
        XCTAssertFalse(seriesBlock.contains("StressDailySeriesContext("))
    }

    // MARK: - Persistence

    func testDaySummaryRoundTripsThroughCodable() throws {
        let summary = StressDaySummary(
            date: day(2024, 5, 15),
            averageScore: 42,
            minutesByBand: [.rest: 300, .low: 120, .medium: 45, .high: 15],
            scoredWindowCount: 32,
            hrvCoveredWindowCount: 8,
            quietHRMedian: 71.5,
            rmssdDailyMedian: 38.25,
            minScore: 18,
            maxScore: 79
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(StressDaySummary.self, from: data)

        XCTAssertEqual(decoded, summary)
        XCTAssertEqual(decoded.minutes(in: .rest), 300)
        XCTAssertEqual(decoded.totalScoredMinutes, 480)
        XCTAssertEqual(decoded.minScore, 18)
        XCTAssertEqual(decoded.maxScore, 79)
    }

    /// A snapshot written before `minScore`/`maxScore` existed decodes with
    /// `nil` rather than failing (both fields are `decodeIfPresent`).
    func testDaySummaryDecodesLegacyPayloadWithoutMinMax() throws {
        // Simulates a pre-min/max payload by stripping those two keys from a
        // freshly encoded value, rather than hand-writing the Date's own
        // Codable representation.
        let summary = StressDaySummary(
            date: day(2024, 5, 15),
            averageScore: 42,
            scoredWindowCount: 32,
            hrvCoveredWindowCount: 8,
            minScore: 18,
            maxScore: 79
        )
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any]
        )
        object["minScore"] = nil
        object["maxScore"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(StressDaySummary.self, from: legacyData)

        XCTAssertNil(decoded.minScore)
        XCTAssertNil(decoded.maxScore)
        XCTAssertEqual(decoded.averageScore, 42)
    }

    /// `minutesByBand` is a `[StressBand: Int]`, and `StressBand` isn't
    /// `CodingKeyRepresentable`, so a synthesized Codable would encode it as a
    /// hash-ordered flat array that differs byte-for-byte between encodes of the
    /// same value — defeating the snapshot store's save-if-changed byte compare.
    /// `StressDaySummary` encodes it as a keyed dictionary instead so
    /// `.sortedKeys` output formatting stabilizes the order.
    func testDaySummaryEncodingIsByteStableAcrossEncodes() throws {
        let summary = StressDaySummary(
            date: day(2024, 5, 15),
            averageScore: 42,
            minutesByBand: [.rest: 300, .low: 120, .medium: 45, .high: 15],
            scoredWindowCount: 32,
            hrvCoveredWindowCount: 8,
            quietHRMedian: 71.5,
            rmssdDailyMedian: 38.25,
            minScore: 18,
            maxScore: 79
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(summary)
        let second = try encoder.encode(summary)
        XCTAssertEqual(first, second)
    }

    // MARK: - Calibration fixtures

    /// The sensitivity harness for `k`, `z0` and the spread floor: canonical scenarios
    /// must land in the bands a user would recognize.
    func testCanonicalScenariosLandInExpectedBands() throws {
        let scoringDay = day(2024, 5, 15)
        let baselines = makeBaselines(scoringDay: scoringDay, sdnnDayCount: 0)
        let workoutStart = scoringDay.addingTimeInterval(10 * 3600)

        // 00:00-06:00 asleep at 55 bpm, 08:00-09:00 desk work at 73, 09:00-10:00 an acute
        // stressor at 80.5, a workout 10:00-11:00 and its 30-minute tail.
        var samples = heartRateSamples(dayStart: scoringDay, windowRange: 0..<24, value: 55)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 32..<36, value: 73)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 36..<40, value: 80.5)
        samples += heartRateSamples(dayStart: scoringDay, windowRange: 40..<48, value: 120)

        let windows = StressScoreCalculator.windows(
            for: StressDayInput(
                date: scoringDay,
                heartRateSamples: samples,
                workoutIntervals: [
                    DateInterval(start: workoutStart, end: workoutStart.addingTimeInterval(3600))
                ],
                sleepInterval: DateInterval(start: scoringDay, end: scoringDay.addingTimeInterval(6 * 3600))
            ),
            baselines: baselines,
            calendar: calendar,
            now: day(2024, 5, 20)
        )

        XCTAssertEqual(windows[10].band, .rest, "sleeping")
        XCTAssertEqual(windows[33].band, .low, "desk work")
        XCTAssertEqual(windows[38].band, .high, "acute stressor")
        XCTAssertEqual(windows[41].state, .activity, "workout")
        XCTAssertEqual(windows[45].state, .activity, "post-workout tail")
    }

    // MARK: - RMSSD math

    private func alternatingIntervals(count: Int) -> [StressRMSSD.RRInterval] {
        (0..<count).map { index in
            StressRMSSD.RRInterval(seconds: index.isMultiple(of: 2) ? 0.900 : 0.850)
        }
    }

    func testRMSSDFromAlternatingIntervals() throws {
        let rmssd = try XCTUnwrap(
            StressRMSSD.rmssdMilliseconds(intervals: alternatingIntervals(count: 40))
        )

        XCTAssertEqual(rmssd, 50, accuracy: 0.0001)
    }

    func testRMSSDRejectsOutOfBoundsIntervals() throws {
        var intervals = alternatingIntervals(count: 40)
        intervals[20] = StressRMSSD.RRInterval(seconds: 0.100)
        intervals[30] = StressRMSSD.RRInterval(seconds: 2.500)

        let rmssd = try XCTUnwrap(StressRMSSD.rmssdMilliseconds(intervals: intervals))

        XCTAssertEqual(rmssd, 50, accuracy: 0.0001)
    }

    func testRMSSDRejectsIntervalsDeviatingFromTheRunningMedian() throws {
        var intervals = alternatingIntervals(count: 40)
        // In range, but 70 % above the running median — a missed beat, not a real RR.
        intervals[20] = StressRMSSD.RRInterval(seconds: 1.500)

        let rmssd = try XCTUnwrap(StressRMSSD.rmssdMilliseconds(intervals: intervals))

        XCTAssertEqual(rmssd, 50, accuracy: 0.0001)
    }

    func testRMSSDSkipsPairsAcrossAGap() {
        var intervals = alternatingIntervals(count: 32)
        intervals[10].precededByGap = true
        intervals[20].precededByGap = true

        // 31 successive pairs minus the 2 spanning gaps leaves 29 — one short of the floor.
        XCTAssertNil(StressRMSSD.rmssdMilliseconds(intervals: intervals))
        XCTAssertNotNil(StressRMSSD.rmssdMilliseconds(intervals: alternatingIntervals(count: 32)))
    }

    func testRMSSDNeedsThirtyValidDifferences() {
        XCTAssertNil(StressRMSSD.rmssdMilliseconds(intervals: alternatingIntervals(count: 30)))
        XCTAssertNotNil(StressRMSSD.rmssdMilliseconds(intervals: alternatingIntervals(count: 31)))
        XCTAssertNil(StressRMSSD.rmssdMilliseconds(intervals: []))
    }

    // MARK: - Helpers

    private func makeWorkout(start: Date, duration: TimeInterval, endDate: Date?) -> WorkoutSummary {
        WorkoutSummary(type: .running, startDate: start, duration: duration, endDate: endDate)
    }
}
