//
//  StressDayNightSplitTests.swift
//  BodyTests
//
//  The Stress page's Day and Night card: Day is every window that is not sleep,
//  Night is the main session that ended that morning, read whole across midnight.
//

import XCTest
@testable import Body

final class StressDayNightSplitTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
    }

    private var previousDay: Date {
        calendar.date(byAdding: .day, value: -1, to: day)!
    }

    /// A past day's split: `now` is the week after.
    private var later: Date {
        calendar.date(byAdding: .day, value: 7, to: day)!
    }

    private func time(_ hour: Int, _ minute: Int, on base: Date? = nil) -> Date {
        calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base ?? day)!
    }

    private func index(_ hour: Int, _ minute: Int) -> Int {
        hour * 4 + minute / 15
    }

    /// A full 96 window day: scored where `scores` says, movement in `activity`,
    /// unscored everywhere else.
    private func windows(
        on dayStart: Date,
        scores: [Int: Double],
        activity: Set<Int> = []
    ) -> [StressWindow] {
        (0..<96).map { index in
            let interval = DateInterval(start: dayStart.addingTimeInterval(Double(index) * 900), duration: 900)
            if activity.contains(index) {
                return StressWindow(interval: interval, state: .activity)
            }
            if let score = scores[index] {
                return StressWindow(interval: interval, state: .scored(score: score, hrOnly: true))
            }
            return StressWindow(interval: interval, state: .unscored)
        }
    }

    private func scores(_ range: Range<Int>, _ value: Double) -> [Int: Double] {
        Dictionary(uniqueKeysWithValues: range.map { ($0, value) })
    }

    // MARK: - Where the line falls

    func testNightRunsAcrossMidnightAndDayIsEverythingElse() throws {
        let night = DateInterval(start: time(23, 30, on: previousDay), end: time(7, 10))
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [
                previousDay: windows(on: previousDay, scores: scores(index(22, 0)..<96, 3)),
                day: windows(on: day, scores: scores(0..<index(7, 15), 3).merging(scores(index(7, 15)..<96, 40)) { $1 })
            ],
            night: night,
            now: later,
            calendar: calendar
        )

        let nightPeriod = try XCTUnwrap(split.night)
        // 23:30 and 23:45 the day before, then 00:00 through the 07:00 window the
        // wake lands in.
        XCTAssertEqual(nightPeriod.scoredWindowCount, 2 + index(7, 15))
        XCTAssertEqual(nightPeriod.interval, night)
        XCTAssertEqual(nightPeriod.averageScore, 3)

        XCTAssertEqual(split.day.scoredWindowCount, 96 - index(7, 15))
        XCTAssertEqual(split.day.averageScore, 40)
        XCTAssertEqual(split.day.interval, DateInterval(start: time(7, 10), end: time(24, 0)))
        XCTAssertEqual(split.daySpan, .toMidnight(start: time(7, 10)))
        XCTAssertFalse(split.isToday)
    }

    func testTonightsSleepBeforeMidnightIsNotDay() {
        let tonight = DateInterval(start: time(22, 40), end: time(6, 30, on: calendar.date(byAdding: .day, value: 1, to: day)!))
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: scores(index(8, 0)..<96, 30))],
            night: DateInterval(start: time(23, 0, on: previousDay), end: time(7, 0)),
            tonight: tonight,
            now: later,
            calendar: calendar
        )

        // 08:00 up to the 22:30 window that tonight's 22:40 bedtime touches.
        XCTAssertEqual(split.day.scoredWindowCount, index(22, 30) - index(8, 0))
        XCTAssertEqual(split.day.interval.end, tonight.start)
        XCTAssertEqual(split.daySpan, .range(start: time(7, 0), end: tonight.start))
    }

    func testANapLeavesDayWithoutJoiningNight() throws {
        let nap = DateInterval(start: time(13, 0), end: time(13, 40))
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: scores(0..<96, 20))],
            night: DateInterval(start: time(0, 0), end: time(6, 0)),
            naps: [nap],
            now: later,
            calendar: calendar
        )

        XCTAssertEqual(split.day.scoredWindowCount, 96 - index(6, 0) - 3)
        XCTAssertEqual(try XCTUnwrap(split.night).scoredWindowCount, index(6, 0))
        // The Day span is still wake to bedtime; the nap is only left out of it.
        XCTAssertEqual(split.day.interval, DateInterval(start: time(6, 0), end: time(24, 0)))
    }

    func testWithNoSleepRecordedTheWholeDayIsDay() {
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: scores(0..<96, 30))],
            night: nil,
            now: later,
            calendar: calendar
        )

        XCTAssertNil(split.night)
        XCTAssertFalse(split.nightHasEnoughData)
        XCTAssertEqual(split.day.scoredWindowCount, 96)
        XCTAssertEqual(split.day.interval, DateInterval(start: day, end: time(24, 0)))
        XCTAssertEqual(split.daySpan, .allDay)
    }

    func testTodaysDayRunsToNow() {
        let now = time(15, 40)
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: scores(index(8, 0)..<index(15, 30), 30))],
            night: DateInterval(start: time(23, 38, on: previousDay), end: time(7, 12)),
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(split.isToday)
        XCTAssertEqual(split.day.interval, DateInterval(start: time(7, 12), end: now))
        XCTAssertEqual(split.daySpan, .toNow(start: time(7, 12)))
    }

    // MARK: - What each side reads

    func testNightSharesPeaceAndCountsRestlessTimeInOneStretch() throws {
        var nightScores = scores(0..<index(7, 0), 3)
        nightScores[index(3, 15)] = 31
        nightScores[index(3, 30)] = 34
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: nightScores)],
            night: DateInterval(start: time(0, 0), end: time(7, 0)),
            now: later,
            calendar: calendar
        )

        let night = try XCTUnwrap(split.night)
        XCTAssertTrue(split.nightHasEnoughData)
        XCTAssertEqual(night.restlessMinutes, 30)
        XCTAssertEqual(night.restlessStart, time(3, 15))
        // 26 of 28 windows in Peace.
        XCTAssertEqual(night.peaceShare, 93)
        XCTAssertEqual(night.minutesByBand[.low], 30)
        XCTAssertEqual(night.peak, StressDayNightSplit.Peak(score: 34, start: time(3, 30)))
    }

    func testTwoRestlessStretchesCarryNoSingleTime() throws {
        var nightScores = scores(0..<index(7, 0), 3)
        nightScores[index(1, 40)] = 40
        // An unscored gap between two restless windows ends the stretch.
        nightScores[index(4, 0)] = 33
        nightScores.removeValue(forKey: index(4, 15))
        nightScores[index(4, 30)] = 36
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: nightScores)],
            night: DateInterval(start: time(0, 0), end: time(7, 0)),
            now: later,
            calendar: calendar
        )

        let night = try XCTUnwrap(split.night)
        XCTAssertEqual(night.restlessMinutes, 45)
        XCTAssertNil(night.restlessStart)
    }

    func testARestlessStretchCarriesOnAcrossMidnight() throws {
        var lastNight = scores(index(23, 0)..<96, 3)
        lastNight[95] = 30
        var thisMorning = scores(0..<index(6, 0), 3)
        thisMorning[0] = 32
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [
                previousDay: windows(on: previousDay, scores: lastNight),
                day: windows(on: day, scores: thisMorning)
            ],
            night: DateInterval(start: time(23, 0, on: previousDay), end: time(6, 0)),
            now: later,
            calendar: calendar
        )

        let night = try XCTUnwrap(split.night)
        XCTAssertEqual(night.restlessMinutes, 30)
        XCTAssertEqual(night.restlessStart, time(23, 45, on: previousDay))
    }

    func testANightBelowTheScoredFloorHasNotEnoughData() {
        let floor = StressDayNightSplit.minimumNightScoredWindowCount
        func split(scoredNightWindows: Int) -> StressDayNightSplit {
            StressDayNightSplit.make(
                day: day,
                windowsByDay: [day: windows(on: day, scores: scores(0..<scoredNightWindows, 3))],
                night: DateInterval(start: time(0, 0), end: time(7, 0)),
                now: later,
                calendar: calendar
            )
        }

        XCTAssertFalse(split(scoredNightWindows: floor - 1).nightHasEnoughData)
        XCTAssertTrue(split(scoredNightWindows: floor).nightHasEnoughData)
    }

    func testDayPeakIsTheEarliestHighestWindowAndMovementIsCountedApart() throws {
        var dayScores = scores(index(8, 0)..<index(18, 0), 30)
        dayScores[index(13, 30)] = 81
        dayScores[index(15, 0)] = 80.6
        let split = StressDayNightSplit.make(
            day: day,
            windowsByDay: [day: windows(on: day, scores: dayScores, activity: [index(12, 15), index(12, 30)])],
            night: DateInterval(start: time(0, 0), end: time(7, 0)),
            now: later,
            calendar: calendar
        )

        XCTAssertEqual(split.day.peak, StressDayNightSplit.Peak(score: 81, start: time(13, 30)))
        XCTAssertEqual(split.day.activityMinutes, 30)
        XCTAssertEqual(split.day.minutesByBand[.high], 30)
    }

    // MARK: - The bar

    func testBarSegmentsLeaveAGapAfterEveryDrawnSegmentButTheLast() {
        let frames = BodyStressDayNightBar.segmentFrames(minutes: [10, 0, 10, 0, 0], width: 100, gap: 2)

        XCTAssertEqual(frames.map { $0.x }, [0, 50, 50, 100, 100])
        XCTAssertEqual(frames.map { $0.width }, [48, 0, 50, 0, 0])
        XCTAssertEqual(
            BodyStressDayNightBar.segmentFrames(minutes: [0, 0], width: 100, gap: 2).map { $0.width },
            [0, 0]
        )
    }
}
