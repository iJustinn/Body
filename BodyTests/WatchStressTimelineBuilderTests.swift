//
//  WatchStressTimelineBuilderTests.swift
//  BodyTests
//
//  The Stress page's "Last 8 hours" chart (`WatchStressTimelineBuilder`): the
//  slots must be the iPhone Day View's own windows (`stressWindows(for:)`),
//  placed on one continuous 15 minute grid across midnight and DST, with the
//  sleep and workout shading clipped to the span.
//

import XCTest
@testable import Body

final class WatchStressTimelineBuilderTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    /// Two heart rate samples 6 minutes apart in each window from `start`, just
    /// past the minimum coverage rule, so every window has a median. Windows
    /// are counted in absolute 15 minute steps, the grid's own rule.
    private func heartRateSamples(from start: Date, windows: Range<Int>, value: Double) -> [HealthTrendDataPoint] {
        windows.flatMap { index -> [HealthTrendDataPoint] in
            let windowStart = start.addingTimeInterval(Double(index) * 900)
            return [
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(60), value: value),
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(420), value: value)
            ]
        }
    }

    /// Calibrated quiet heart rate baselines: 20 recorded days before `day`.
    private func recordedBaselineDays(before day: Date) -> [StressDaySummary] {
        (1...20).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: day)).map {
                StressDaySummary(date: $0, averageScore: 30, scoredWindowCount: 40, quietHRMedian: 60)
            }
        }
        .sorted { $0.date < $1.date }
    }

    private func dashboard(
        heartRate: [HealthTrendDataPoint],
        baselinesBefore day: Date?,
        summary: HealthSummarySnapshot = .empty,
        sleepHistory: SleepHistorySnapshot = SleepHistorySnapshot(days: [])
    ) -> HealthDashboardSnapshot {
        var trends = HealthTrendSnapshot.empty
        trends.heartRateDaySamples = HealthTrendSeries(points: heartRate)
        trends.recordedStressDays = day.map(recordedBaselineDays(before:)) ?? []
        trends.sleepHistory = sleepHistory
        return HealthDashboardSnapshot(summary: summary, trends: trends)
    }

    /// The slot a window lands in must say exactly what the Day View's window
    /// says: the rounded score, -1 for activity, nil for unscored.
    private func expectedSlot(_ window: StressWindow) -> Int? {
        switch window.state {
        case let .scored(score, _): return Int(score.rounded())
        case .activity: return WatchStressTimeline.activityMarker
        case .unscored: return nil
        }
    }

    // MARK: - Grid

    func testSlotsRunOnOneGridAcrossMidnight() throws {
        let yesterday = try date(2025, 3, 19)
        let today = try date(2025, 3, 20)
        let now = try date(2025, 3, 20, 2, 7)
        // 17:30 yesterday through 02:00 today, all calm except the last hour.
        let heartRate = heartRateSamples(from: yesterday, windows: 70..<96, value: 62)
            + heartRateSamples(from: today, windows: 0..<4, value: 64)
            + heartRateSamples(from: today, windows: 4..<8, value: 95)
        let snapshot = dashboard(heartRate: heartRate, baselinesBefore: yesterday)

        let timeline = try XCTUnwrap(WatchStressTimelineBuilder.make(
            dashboard: snapshot, workouts: [], now: now, calendar: calendar, computedAt: now
        ))

        // The first window overlapping `now - 9h` (17:07) is 17:00's.
        XCTAssertEqual(timeline.start, yesterday.addingTimeInterval(68 * 900))
        XCTAssertEqual(timeline.end, now)
        XCTAssertEqual(timeline.computedAt, now)
        // 17:00 to midnight is 28 slots, so today's first window is slot 28.
        XCTAssertEqual(timeline.interval(at: 28).start, today)
        XCTAssertEqual(timeline.slot(at: 0), .none, "17:00 has no readings")
        XCTAssertEqual(timeline.slot(at: 1), .none)

        let windows = (snapshot.stressWindows(for: yesterday, calendar: calendar, now: now)
            + snapshot.stressWindows(for: today, calendar: calendar, now: now))
            .filter { $0.interval.end > now.addingTimeInterval(-9 * 3_600) }
        XCTAssertEqual(windows.first?.interval.start, timeline.start)
        for (index, window) in windows.enumerated() {
            XCTAssertEqual(timeline.interval(at: index).start, window.interval.start, "slot \(index)")
            XCTAssertEqual(index < timeline.slots.count ? timeline.slots[index] : nil, expectedSlot(window), "slot \(index)")
        }
        XCTAssertNotNil(timeline.slots[27], "23:45 yesterday")
        XCTAssertNotNil(timeline.slots[28], "midnight")
        // The last scored window is 01:45; the partial 02:00 one has no
        // readings yet, and a trailing gap isn't shipped.
        XCTAssertEqual(timeline.slots.count, 36)
        guard case .scored(let lateScore) = timeline.slot(at: 35), case .scored(let calmScore) = timeline.slot(at: 30) else {
            return XCTFail("the last hour and the one before it must both score")
        }
        XCTAssertGreaterThan(lateScore, calmScore)
    }

    /// Spring forward: today's 02:00 never happens, so today's windows sit
    /// 15 absolute minutes apart straight through 01:45 EST to 03:00 EDT, and
    /// so do the slots.
    func testSlotsStayContinuousOverSpringForward() throws {
        let yesterday = try date(2025, 3, 8)
        let today = try date(2025, 3, 9)
        let now = try date(2025, 3, 9, 5, 7)
        // `now - 9h` is 19:07 EST yesterday. 19:00 yesterday to midnight, then
        // midnight to 05:00 EDT (4 absolute hours).
        let heartRate = heartRateSamples(from: yesterday, windows: 76..<96, value: 62)
            + heartRateSamples(from: today, windows: 0..<16, value: 62)
        let snapshot = dashboard(heartRate: heartRate, baselinesBefore: yesterday)

        let timeline = try XCTUnwrap(WatchStressTimelineBuilder.make(
            dashboard: snapshot, workouts: [], now: now, calendar: calendar, computedAt: nil
        ))

        XCTAssertEqual(timeline.start, yesterday.addingTimeInterval(76 * 900))
        XCTAssertEqual(timeline.slots.count, 36)
        XCTAssertTrue(timeline.slots.allSatisfy { $0 != nil }, "no hole at the skipped hour")
        XCTAssertEqual(timeline.interval(at: 20).start, today)
        XCTAssertEqual(calendar.component(.hour, from: timeline.interval(at: 27).start), 1)
        XCTAssertEqual(calendar.component(.hour, from: timeline.interval(at: 28).start), 3, "02:00 is skipped")
        XCTAssertEqual(timeline.interval(at: 35).end, try date(2025, 3, 9, 5, 0))
    }

    /// Fall back: today has 100 windows and 01:00 to 02:00 happens twice; the
    /// slots keep counting absolute time through both.
    func testSlotsStayContinuousOverFallBack() throws {
        let today = try date(2025, 11, 2)
        let now = try date(2025, 11, 2, 6, 7)
        // Midnight EDT through 06:00 EST: 7 absolute hours, 28 windows.
        let heartRate = heartRateSamples(from: today, windows: 0..<28, value: 62)
        let snapshot = dashboard(heartRate: heartRate, baselinesBefore: today)

        let timeline = try XCTUnwrap(WatchStressTimelineBuilder.make(
            dashboard: snapshot, workouts: [], now: now, calendar: calendar, computedAt: nil
        ))

        // `now - 9h` is 22:07 EDT yesterday, which had no readings, so its
        // day never enters the scan and the timeline opens at midnight.
        XCTAssertEqual(timeline.start, today)
        XCTAssertEqual(timeline.slots.count, 28)
        XCTAssertTrue(timeline.slots.allSatisfy { $0 != nil })
        XCTAssertEqual(timeline.interval(at: 27).end, try date(2025, 11, 2, 6, 0))
    }

    // MARK: - Slot values

    func testActivityIsMinusOneAndUnscoredIsNil() throws {
        let day = try date(2025, 3, 20)
        let now = try date(2025, 3, 20, 14, 7)
        // 06:00 to 14:00, with one window (10:00) holding a single reading.
        var heartRate = heartRateSamples(from: day, windows: 24..<40, value: 70)
            + heartRateSamples(from: day, windows: 41..<56, value: 70)
        heartRate.append(HealthTrendDataPoint(date: day.addingTimeInterval(40 * 900 + 60), value: 70))
        // 12:00 to 12:30, masked through 13:00 by the recovery tail.
        let workoutStart = day.addingTimeInterval(12 * 3_600)
        let workout = WorkoutSummary(
            type: .running, startDate: workoutStart, duration: 30 * 60,
            endDate: workoutStart.addingTimeInterval(30 * 60)
        )
        let snapshot = dashboard(heartRate: heartRate, baselinesBefore: day)

        let timeline = try XCTUnwrap(WatchStressTimelineBuilder.make(
            dashboard: snapshot, workouts: [workout], now: now, calendar: calendar, computedAt: nil
        ))

        // `now - 9h` is 05:07, so the timeline opens on 05:00's window (20).
        XCTAssertEqual(timeline.start, day.addingTimeInterval(20 * 900))
        func slot(atWindow window: Int) -> WatchStressTimeline.Slot { timeline.slot(at: window - 20) }
        XCTAssertEqual(slot(atWindow: 23), .none, "no readings before 06:00")
        XCTAssertEqual(slot(atWindow: 40), .none, "one reading is a gap, never a zero")
        for window in 48..<52 {
            XCTAssertEqual(slot(atWindow: window), .activity, "window \(window)")
        }
        guard case .scored = slot(atWindow: 39), case .scored = slot(atWindow: 52) else {
            return XCTFail("the windows either side are scored")
        }

        let windows = snapshot.stressWindows(for: day, workouts: [workout], calendar: calendar, now: now)
            .filter { $0.interval.start >= timeline.start }
        for (index, window) in windows.enumerated() where index < timeline.slots.count {
            XCTAssertEqual(timeline.slots[index], expectedSlot(window), "slot \(index)")
        }
        XCTAssertEqual(timeline.slots.filter { $0 == WatchStressTimeline.activityMarker }.count, 4)
    }

    /// The latest window is still running: it ends at `now`, not 15 minutes
    /// after its start.
    func testTheLatestPartialSlotEndsAtNow() throws {
        let day = try date(2025, 3, 20)
        let now = try date(2025, 3, 20, 14, 7)
        // 13:00 through the partial 14:00 window (readings 14:00:30, 14:06:30).
        let heartRate = heartRateSamples(from: day, windows: 52..<56, value: 70)
            + [
                HealthTrendDataPoint(date: day.addingTimeInterval(56 * 900 + 30), value: 70),
                HealthTrendDataPoint(date: day.addingTimeInterval(56 * 900 + 390), value: 70)
            ]
        let snapshot = dashboard(heartRate: heartRate, baselinesBefore: day)

        let timeline = try XCTUnwrap(WatchStressTimelineBuilder.make(
            dashboard: snapshot, workouts: [], now: now, calendar: calendar, computedAt: nil
        ))

        let last = timeline.slots.count - 1
        guard case .scored = timeline.slot(at: last) else {
            return XCTFail("the running window is scored")
        }
        XCTAssertEqual(timeline.interval(at: last).start, day.addingTimeInterval(56 * 900))
        XCTAssertEqual(timeline.interval(at: last).end, now)
    }

    func testNilWithoutAnyMark() throws {
        let day = try date(2025, 3, 20)
        let now = try date(2025, 3, 20, 14, 7)

        XCTAssertNil(WatchStressTimelineBuilder.make(
            dashboard: dashboard(heartRate: [], baselinesBefore: day),
            workouts: [], now: now, calendar: calendar, computedAt: now
        ), "no readings at all")
        // Readings, but no calibrated baseline yet: every window is unscored,
        // a workout's included.
        let workoutStart = day.addingTimeInterval(12 * 3_600)
        XCTAssertNil(WatchStressTimelineBuilder.make(
            dashboard: dashboard(heartRate: heartRateSamples(from: day, windows: 24..<56, value: 70), baselinesBefore: nil),
            workouts: [WorkoutSummary(type: .running, startDate: workoutStart, duration: 1_800, endDate: workoutStart.addingTimeInterval(1_800))],
            now: now, calendar: calendar, computedAt: now
        ), "uncalibrated")
        // Readings that all predate the span.
        XCTAssertNil(WatchStressTimelineBuilder.make(
            dashboard: dashboard(heartRate: heartRateSamples(from: day, windows: 0..<16, value: 70), baselinesBefore: day),
            workouts: [], now: now, calendar: calendar, computedAt: now
        ), "nothing in the last 9 hours")
    }

    // MARK: - Context

    /// The night's main session, a nap and a workout, clipped to the span and
    /// sorted, from the same sources as the Day View: the sleep history, or
    /// today's live summary when the history has no entry for today yet.
    func testContextBandsAreClippedToTheSpanAndSorted() throws {
        let day = try date(2025, 3, 20)
        let now = try date(2025, 3, 20, 14, 7)
        let spanStart = now.addingTimeInterval(-9 * 3_600)
        let mainStart = day.addingTimeInterval(-3_600)
        let mainEnd = day.addingTimeInterval(7 * 3_600)
        let napStart = day.addingTimeInterval(13 * 3_600)
        let napEnd = napStart.addingTimeInterval(40 * 60)
        let night = SleepStageSnapshot(
            date: day,
            segments: [
                SleepStageSegment(stage: .core, startDate: mainStart, endDate: mainEnd),
                SleepStageSegment(stage: .core, startDate: napStart, endDate: napEnd)
            ],
            mainSessionInterval: DateInterval(start: mainStart, end: mainEnd)
        )
        let sleep = SleepSummary(duration: 8.6 * 3_600, stageSnapshot: night)
        let workoutStart = day.addingTimeInterval(12 * 3_600)
        let workouts = [
            WorkoutSummary(type: .cycling, startDate: workoutStart, duration: 1_500, endDate: workoutStart.addingTimeInterval(30 * 60)),
            // Before the span: never shaded.
            WorkoutSummary(type: .running, startDate: day.addingTimeInterval(3 * 3_600), duration: 1_800)
        ]
        let heartRate = heartRateSamples(from: day, windows: 24..<56, value: 70)
        var summary = HealthSummarySnapshot.empty
        summary.sleep = sleep
        let fromHistory = dashboard(
            heartRate: heartRate,
            baselinesBefore: day,
            sleepHistory: SleepHistorySnapshot(days: [SleepDaySummary(date: day, summary: sleep)])
        )
        let fromSummary = dashboard(heartRate: heartRate, baselinesBefore: day, summary: summary)

        let expected = [
            WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: spanStart, end: mainEnd),
            WatchStressContextBand(
                kind: WatchStressContextBand.workoutKind,
                start: workoutStart,
                end: workoutStart.addingTimeInterval(30 * 60),
                workoutType: BodyWorkoutType.cycling.rawValue
            ),
            WatchStressContextBand(kind: WatchStressContextBand.napKind, start: napStart, end: napEnd)
        ]
        for (name, snapshot) in [("history", fromHistory), ("live summary", fromSummary)] {
            let timeline = try XCTUnwrap(WatchStressTimelineBuilder.make(
                dashboard: snapshot, workouts: workouts, now: now, calendar: calendar, computedAt: nil
            ), name)
            XCTAssertEqual(timeline.context, expected, name)
        }
    }
}
