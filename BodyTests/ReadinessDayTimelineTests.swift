//
//  ReadinessDayTimelineTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class ReadinessDayTimelineTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian
    private let fixedStart = Date(timeIntervalSince1970: 1_700_000_000)

    private var dayInterval: DateInterval {
        let dayStart = calendar.startOfDay(for: fixedStart)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return DateInterval(start: dayStart, end: nextDayStart)
    }

    private var pastNow: Date {
        dayInterval.end.addingTimeInterval(86_400)
    }

    private func workout(
        _ type: BodyWorkoutType,
        startOffsetMinutes: Double,
        minutes: Double,
        effort: Double? = nil,
        sourceName: String = "Apple Health"
    ) -> WorkoutSummary {
        WorkoutSummary(
            type: type,
            startDate: dayInterval.start.addingTimeInterval(startOffsetMinutes * 60),
            duration: minutes * 60,
            effortLevel: effort,
            sourceName: sourceName
        )
    }

    private func readiness(score: Int) -> ReadinessSummary {
        ReadinessSummary(
            score: score,
            status: ReadinessStatus.status(for: score),
            confidence: .high,
            components: [],
            drivers: []
        )
    }

    // MARK: - Flat day

    func testNoWorkoutsProducesFlatSeriesAtMorningScore() {
        let timeline = ReadinessDayTimeline.make(
            morningScore: 82,
            workouts: [],
            dayInterval: dayInterval,
            now: pastNow
        )

        XCTAssertTrue(timeline.impacts.isEmpty)
        let series = timeline.sampledSeries(dayStart: dayInterval.start)
        XCTAssertFalse(series.isEmpty)
        XCTAssertTrue(series.points.allSatisfy { $0.value == 82 })
    }

    func testSubHalfPointTotalDrainStaysFlat() {
        // Mirrors `HealthDashboardSnapshot.draining`'s `drain >= 0.5` guard.
        let light = workout(.walking, startOffsetMinutes: 600, minutes: 1, effort: 1)
        XCTAssertLessThan(ActivityReadinessImpact.perWorkoutDrain(light), 0.5)

        let timeline = ReadinessDayTimeline.make(
            morningScore: 82,
            workouts: [light],
            dayInterval: dayInterval,
            now: pastNow
        )

        XCTAssertEqual(timeline.displayedScore(at: dayInterval.end - 1), 82)
    }

    // MARK: - Single workout

    func testSingleWorkoutRampsMonotonicallyToDrainedScore() {
        let run = workout(.running, startOffsetMinutes: 600, minutes: 60, effort: 8)
        let timeline = ReadinessDayTimeline.make(
            morningScore: 80,
            workouts: [run],
            dayInterval: dayInterval,
            now: pastNow
        )

        let runStart = run.startDate
        let runEnd = run.startDate.addingTimeInterval(run.duration)
        XCTAssertEqual(timeline.displayedScore(at: dayInterval.start), 80)
        XCTAssertEqual(timeline.displayedScore(at: runStart), 80)

        let expectedDrop = Int(ActivityReadinessImpact.perWorkoutDrain(run).rounded())
        XCTAssertEqual(timeline.displayedScore(at: runEnd), 80 - expectedDrop)
        XCTAssertEqual(timeline.displayedScore(at: dayInterval.end - 1), 80 - expectedDrop)

        // Monotone non-increasing across the ramp.
        var previousScore = Int.max
        for minute in stride(from: 0.0, through: 60.0, by: 5.0) {
            let score = timeline.displayedScore(at: runStart.addingTimeInterval(minute * 60))
            XCTAssertLessThanOrEqual(score, previousScore)
            previousScore = score
        }
    }

    // MARK: - Parity with the live tile computation

    func testEndOfDayMatchesDrainingForSameInputs() {
        let workouts = [
            workout(.running, startOffsetMinutes: 480, minutes: 45, effort: 7),
            workout(.strengthTraining, startOffsetMinutes: 1_020, minutes: 50, effort: 8)
        ]
        let morning = readiness(score: 76)
        let drained = HealthDashboardSnapshot.draining(morning, with: workouts)

        let timeline = ReadinessDayTimeline.make(
            morningScore: 76,
            workouts: workouts,
            dayInterval: dayInterval,
            now: pastNow
        )

        XCTAssertEqual(timeline.displayedScore(at: dayInterval.end - 1), drained.score)
    }

    func testEndOfDayMatchesDrainingWhenDisplayFloorClamps() {
        let hard = workout(.running, startOffsetMinutes: 600, minutes: 120, effort: 10)
        let morning = readiness(score: 12)
        let drained = HealthDashboardSnapshot.draining(morning, with: [hard])

        let timeline = ReadinessDayTimeline.make(
            morningScore: 12,
            workouts: [hard],
            dayInterval: dayInterval,
            now: pastNow
        )

        XCTAssertEqual(timeline.displayedScore(at: dayInterval.end - 1), drained.score)
    }

    // MARK: - Total cap

    func testTotalDrainCapClampsCumulativeAndReducesLaterMarginals() throws {
        let workouts = [
            workout(.running, startOffsetMinutes: 420, minutes: 90, effort: 10),
            workout(.running, startOffsetMinutes: 720, minutes: 90, effort: 10),
            workout(.running, startOffsetMinutes: 1_020, minutes: 90, effort: 10)
        ]
        let rawTotal = workouts.reduce(0.0) { $0 + ActivityReadinessImpact.perWorkoutDrain($1) }
        XCTAssertGreaterThan(rawTotal, ActivityReadinessImpact.totalDrainCap)

        let timeline = ReadinessDayTimeline.make(
            morningScore: 95,
            workouts: workouts,
            dayInterval: dayInterval,
            now: pastNow
        )

        let marginalTotal = timeline.impacts.reduce(0.0) { $0 + $1.drainPoints }
        XCTAssertEqual(marginalTotal, ActivityReadinessImpact.totalDrainCap, accuracy: 0.0001)
        let lastImpact = try XCTUnwrap(timeline.impacts.last)
        let lastRawDrain = ActivityReadinessImpact.perWorkoutDrain(workouts[2])
        XCTAssertLessThan(lastImpact.drainPoints, lastRawDrain)
    }

    // MARK: - Bounds

    func testScoresNeverExceedMorningScoreNorDropBelowSoftenedFloor() {
        let hard = workout(.running, startOffsetMinutes: 300, minutes: 120, effort: 10)
        let timeline = ReadinessDayTimeline.make(
            morningScore: 10,
            workouts: [hard],
            dayInterval: dayInterval,
            now: pastNow
        )

        for point in timeline.sampledSeries(dayStart: dayInterval.start).points {
            XCTAssertLessThanOrEqual(point.value, 10)
            XCTAssertGreaterThanOrEqual(point.value, 0)
        }
    }

    // MARK: - Series domain

    func testMidnightSpanningWorkoutIsClippedToDay() throws {
        // Starts 30 minutes before next midnight, runs 60 minutes.
        let spanning = workout(.running, startOffsetMinutes: 24 * 60 - 30, minutes: 60, effort: 8)
        let timeline = ReadinessDayTimeline.make(
            morningScore: 80,
            workouts: [spanning],
            dayInterval: dayInterval,
            now: pastNow
        )

        let impact = try XCTUnwrap(timeline.impacts.first)
        XCTAssertEqual(impact.startDate, spanning.startDate)
        XCTAssertEqual(impact.endDate, dayInterval.end)
        // Drain magnitude still reflects the whole workout.
        XCTAssertEqual(impact.drainPoints, ActivityReadinessImpact.perWorkoutDrain(spanning), accuracy: 0.0001)
    }

    func testPastDaySamplesEndStrictlyBeforeNextMidnightAndAreUnique() throws {
        let timeline = ReadinessDayTimeline.make(
            morningScore: 82,
            workouts: [workout(.running, startOffsetMinutes: 600, minutes: 45, effort: 7)],
            dayInterval: dayInterval,
            now: pastNow
        )

        let dates = timeline.sampledSeries(dayStart: dayInterval.start).points.map(\.date)
        XCTAssertEqual(dates.first, dayInterval.start)
        XCTAssertLessThan(try XCTUnwrap(dates.last), dayInterval.end)
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testTodaySamplesEndAtNow() {
        let now = dayInterval.start.addingTimeInterval(14 * 60 * 60 + 7 * 60)
        let timeline = ReadinessDayTimeline.make(
            morningScore: 82,
            workouts: [],
            dayInterval: dayInterval,
            now: now
        )

        XCTAssertEqual(timeline.seriesEnd, now)
        XCTAssertEqual(timeline.sampledSeries(dayStart: dayInterval.start).points.last?.date, now)
    }

    // MARK: - Impact rows

    func testMakeReadinessImpactFiltersSubPointRowsAndNegatesValues() throws {
        let hard = workout(.running, startOffsetMinutes: 600, minutes: 60, effort: 8, sourceName: "Watch")
        let negligible = workout(.walking, startOffsetMinutes: 800, minutes: 1, effort: 1)
        XCTAssertLessThan(ActivityReadinessImpact.perWorkoutDrain(negligible), 0.5)

        let timeline = ReadinessDayTimeline.make(
            morningScore: 80,
            workouts: [hard, negligible],
            dayInterval: dayInterval,
            now: pastNow
        )
        let rows = BodyMetricActivityAverages.makeReadinessImpact(timeline: timeline)

        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.activity, .workout(.running))
        XCTAssertEqual(row.averageValue, Double(-Int(ActivityReadinessImpact.perWorkoutDrain(hard).rounded())))
        XCTAssertEqual(row.source, "Watch")
    }

    // MARK: - Carry-in (pre-day wake-cycle workout)

    func testCarryInPreDayWorkoutDrainsFromFirstSample() {
        // Ended before dayInterval.start (e.g. a late-wake wake cycle carried
        // over from yesterday), plus a normal workout today.
        let carryIn = workout(.running, startOffsetMinutes: -120, minutes: 60, effort: 8)
        let today = workout(.strengthTraining, startOffsetMinutes: 600, minutes: 45, effort: 7)
        let morning = readiness(score: 76)

        let firstSampleExpected = HealthDashboardSnapshot.draining(morning, with: [carryIn]).score
        let endOfDayExpected = HealthDashboardSnapshot.draining(morning, with: [carryIn, today]).score

        let timeline = ReadinessDayTimeline.make(
            morningScore: 76,
            workouts: [carryIn, today],
            dayInterval: dayInterval,
            now: pastNow
        )

        XCTAssertEqual(timeline.displayedScore(at: dayInterval.start), firstSampleExpected)
        XCTAssertEqual(timeline.displayedScore(at: dayInterval.end - 1), endOfDayExpected)
    }

    // MARK: - Morning-score selection

    func testMorningScorePrefersLiveScoreForToday() {
        let live = readiness(score: 60)
        var withDrain = live
        withDrain.activityDrainMorningScore = 68

        let result = ReadinessDayTimeline.morningScore(
            isToday: true,
            liveReadiness: withDrain,
            recordedScore: 55,
            trendValue: 50
        )

        XCTAssertEqual(result, 68)
    }

    func testMorningScoreUsesLiveScoreWhenDrainIsBelowHalfPoint() {
        // `activityDrainMorningScore` is only set once drain >= 0.5; below that
        // `score` itself is the undrained value.
        let live = readiness(score: 60)

        let result = ReadinessDayTimeline.morningScore(
            isToday: true,
            liveReadiness: live,
            recordedScore: 55,
            trendValue: 50
        )

        XCTAssertEqual(result, 60)
    }

    func testMorningScoreFallsBackToRecordedWhenTodaysLiveScoreIsNil() {
        var live = readiness(score: 60)
        live.score = nil

        let result = ReadinessDayTimeline.morningScore(
            isToday: true,
            liveReadiness: live,
            recordedScore: 55,
            trendValue: 50
        )

        XCTAssertEqual(result, 55)
    }

    func testMorningScorePrefersRecordedOverLiveForPastDay() {
        let live = readiness(score: 60)

        let result = ReadinessDayTimeline.morningScore(
            isToday: false,
            liveReadiness: live,
            recordedScore: 55,
            trendValue: 50
        )

        XCTAssertEqual(result, 55)
    }
}
