//
//  BodySleepSessionizerTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class BodySleepSessionizerTests: XCTestCase {
    private let calendar = Calendar.bodyGregorian

    // MARK: Helpers

    private func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour, minute: minute))
        )
    }

    private func sleepType() throws -> HKCategoryType {
        try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
    }

    private func sample(
        _ value: HKCategoryValueSleepAnalysis,
        from start: Date,
        to end: Date,
        type: HKCategoryType
    ) -> HKCategorySample {
        HKCategorySample(type: type, value: value.rawValue, start: start, end: end)
    }

    // MARK: Cross-midnight continuity

    func testCrossMidnightNightIsOneSessionOnWakeDay() throws {
        let type = try sleepType()
        // 23:00 on day 10 through 07:00 on day 11 — a single continuous night.
        let bedtime = try date(day: 10, hour: 23)
        let firstWake = try date(day: 11, hour: 2)
        let remEnd = try date(day: 11, hour: 4)
        let wake = try date(day: 11, hour: 7)
        let samples = [
            sample(.asleepCore, from: bedtime, to: firstWake, type: type),
            sample(.asleepREM, from: firstWake, to: remEnd, type: type),
            sample(.asleepCore, from: remEnd, to: wake, type: type)
        ]

        let sessions = BodySleepSessionizer.sessions(from: samples)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.start, bedtime)
        XCTAssertEqual(sessions.first?.end, wake)

        let byWakeDay = BodySleepSessionizer.sessionsByWakeDay(from: samples, calendar: calendar)
        let day10Start = calendar.startOfDay(for: bedtime)
        let day11Start = calendar.startOfDay(for: wake)
        XCTAssertEqual(Set(byWakeDay.keys), [day11Start])
        // The whole night is attributed to the wake day; the prior calendar day
        // gets no spurious partial-night entry.
        XCTAssertNil(byWakeDay[day10Start])
        XCTAssertEqual(byWakeDay[day11Start]?.count, 1)
    }

    // MARK: Pre-midnight-ending night stays on its own wake day

    func testNightEndingBeforeMidnightStaysOnThatCalendarDay() throws {
        let type = try sleepType()
        // Evening sleep 21:00 -> 23:30 on day 10, then a separate night 03:00 ->
        // 06:00 on day 11. Gap of 3.5h exceeds the 2h session gap.
        let eveningStart = try date(day: 10, hour: 21)
        let eveningEnd = try date(day: 10, hour: 23, minute: 30)
        let nightStart = try date(day: 11, hour: 3)
        let nightEnd = try date(day: 11, hour: 6)
        let samples = [
            sample(.asleepCore, from: eveningStart, to: eveningEnd, type: type),
            sample(.asleepCore, from: nightStart, to: nightEnd, type: type)
        ]

        let sessions = BodySleepSessionizer.sessions(from: samples)
        XCTAssertEqual(sessions.count, 2)

        let byWakeDay = BodySleepSessionizer.sessionsByWakeDay(from: samples, calendar: calendar)
        let day10Start = calendar.startOfDay(for: eveningStart)
        let day11Start = calendar.startOfDay(for: nightEnd)
        XCTAssertEqual(Set(byWakeDay.keys), [day10Start, day11Start])
        XCTAssertEqual(byWakeDay[day10Start]?.first?.end, eveningEnd)
        XCTAssertEqual(byWakeDay[day11Start]?.first?.end, nightEnd)
    }

    // MARK: Nap + night — two sessions, main session bounds the vitals window

    func testNapAndNightOnSameWakeDayKeepNightOnlyVitalsWindow() throws {
        let type = try sleepType()
        // Main night 23:00 (day 10) -> 07:00 (day 11), then an afternoon nap
        // 14:00 -> 15:00 (day 11). Both end on day 11 (the wake day).
        let nightStart = try date(day: 10, hour: 23)
        let nightEnd = try date(day: 11, hour: 7)
        let napStart = try date(day: 11, hour: 14)
        let napEnd = try date(day: 11, hour: 15)
        let samples = [
            sample(.asleepCore, from: nightStart, to: nightEnd, type: type),
            sample(.asleepCore, from: napStart, to: napEnd, type: type)
        ]

        let byWakeDay = BodySleepSessionizer.sessionsByWakeDay(from: samples, calendar: calendar)
        let day11Start = calendar.startOfDay(for: nightEnd)
        let sessions = try XCTUnwrap(byWakeDay[day11Start])
        XCTAssertEqual(sessions.count, 2)

        // Naps preserved: the wake day's merged sample set still contains both.
        XCTAssertEqual(sessions.flatMap(\.samples).count, 2)

        // Vitals window is the main (longest asleep) session — the 8h night, not
        // the ~16h span from the night's start to the nap's end.
        let mainSession = try XCTUnwrap(BodySleepSessionizer.mainSession(in: sessions))
        let mainInterval = try XCTUnwrap(mainSession.interval)
        XCTAssertEqual(mainInterval.start, nightStart)
        XCTAssertEqual(mainInterval.end, nightEnd)
        XCTAssertEqual(mainInterval.duration, 8 * 3_600)
    }

    // MARK: 2h gap boundary

    func testTwoHourGapMergesIntoOneSession() throws {
        let type = try sleepType()
        let firstStart = try date(day: 10, hour: 0)
        let firstEnd = try date(day: 10, hour: 2)
        let secondStart = try date(day: 10, hour: 4) // exactly 2h after firstEnd
        let secondEnd = try date(day: 10, hour: 6)
        let samples = [
            sample(.asleepCore, from: firstStart, to: firstEnd, type: type),
            sample(.asleepCore, from: secondStart, to: secondEnd, type: type)
        ]

        let sessions = BodySleepSessionizer.sessions(from: samples)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.start, firstStart)
        XCTAssertEqual(sessions.first?.end, secondEnd)
    }

    func testGapBeyondTwoHoursSplitsIntoTwoSessions() throws {
        let type = try sleepType()
        let firstStart = try date(day: 10, hour: 0)
        let firstEnd = try date(day: 10, hour: 2)
        let secondStart = try date(day: 10, hour: 4).addingTimeInterval(1) // 2h + 1s
        let secondEnd = try date(day: 10, hour: 6)
        let samples = [
            sample(.asleepCore, from: firstStart, to: firstEnd, type: type),
            sample(.asleepCore, from: secondStart, to: secondEnd, type: type)
        ]

        let sessions = BodySleepSessionizer.sessions(from: samples)
        XCTAssertEqual(sessions.count, 2)
    }

    // MARK: Multi-source overlap

    func testOverlappingMultiSourceSamplesFormOneSessionWithMergedDuration() throws {
        let type = try sleepType()
        // One source writes an aggregate asleep block; another writes overlapping
        // detailed stages inside it. They must collapse to a single session and
        // the asleep duration must not double-count the overlap.
        let aggregateStart = try date(day: 10, hour: 23)
        let aggregateEnd = try date(day: 11, hour: 6)
        let coreStart = try date(day: 10, hour: 23, minute: 15)
        let coreEnd = try date(day: 11, hour: 2)
        let remEnd = try date(day: 11, hour: 5, minute: 30)
        let samples = [
            sample(.asleepUnspecified, from: aggregateStart, to: aggregateEnd, type: type),
            sample(.asleepCore, from: coreStart, to: coreEnd, type: type),
            sample(.asleepREM, from: coreEnd, to: remEnd, type: type)
        ]

        let sessions = BodySleepSessionizer.sessions(from: samples)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.start, aggregateStart)
        XCTAssertEqual(sessions.first?.end, aggregateEnd)
        // Union of all asleep intervals is 23:00 -> 06:00 = 7h, not the sum of
        // the overlapping samples.
        XCTAssertEqual(sessions.first?.asleepDuration, 7 * 3_600)
    }

    // MARK: 21:00 -> 06:30 sleeper — vitals window ~9.5h, not ~24h

    func testEveningSleeperVitalsWindowIsNightNotWholeDay() throws {
        let type = try sleepType()
        // Night 21:00 (day 10) -> 06:30 (day 11) = 9.5h, plus a late-evening nap
        // 19:00 -> 20:00 on day 11 so the whole-day span is ~23h.
        let nightStart = try date(day: 10, hour: 21)
        let nightEnd = try date(day: 11, hour: 6, minute: 30)
        let napStart = try date(day: 11, hour: 19)
        let napEnd = try date(day: 11, hour: 20)
        let samples = [
            sample(.asleepCore, from: nightStart, to: nightEnd, type: type),
            sample(.asleepCore, from: napStart, to: napEnd, type: type)
        ]

        let byWakeDay = BodySleepSessionizer.sessionsByWakeDay(from: samples, calendar: calendar)
        let day11Start = calendar.startOfDay(for: nightEnd)
        let sessions = try XCTUnwrap(byWakeDay[day11Start])
        XCTAssertEqual(sessions.count, 2)

        let mainSession = try XCTUnwrap(BodySleepSessionizer.mainSession(in: sessions))
        let mainInterval = try XCTUnwrap(mainSession.interval)
        // Vitals window is the 9.5h night, not the ~23h whole-day span.
        XCTAssertEqual(mainInterval.duration, 9.5 * 3_600)
        XCTAssertEqual(napEnd.timeIntervalSince(nightStart), 23 * 3_600)
    }

    // MARK: Parser stamps the sessionizer's main-session window on the snapshot

    /// The interval `BodySleepSessionizer` would report for `samples`.
    private func expectedMainInterval(for samples: [HKCategorySample]) throws -> DateInterval {
        try XCTUnwrap(
            BodySleepSessionizer.mainSession(
                in: BodySleepSessionizer.sessions(from: samples)
            )?.interval
        )
    }

    func testSleepSummaryStampsSessionizerMainIntervalForNightPlusNap() throws {
        let type = try sleepType()
        // Night 23:00 (day 10) -> 07:00 (day 11), then a nap starting 3h later so
        // it lands in its own session under the 2h gap rule.
        let nightStart = try date(day: 10, hour: 23)
        let remStart = try date(day: 11, hour: 3)
        let nightEnd = try date(day: 11, hour: 7)
        let napStart = try date(day: 11, hour: 10)
        let napEnd = try date(day: 11, hour: 11)
        let samples = [
            sample(.asleepCore, from: nightStart, to: remStart, type: type),
            sample(.asleepREM, from: remStart, to: nightEnd, type: type),
            sample(.asleepCore, from: napStart, to: napEnd, type: type)
        ]

        let summary = try XCTUnwrap(BodySleepSampleParser.sleepSummary(
            from: samples,
            date: calendar.startOfDay(for: nightEnd)
        ))

        let expected = try expectedMainInterval(for: samples)
        XCTAssertEqual(summary.stageSnapshot.mainSessionInterval, expected)
        XCTAssertEqual(expected, DateInterval(start: nightStart, end: nightEnd))
        // The nap stays on the wake-day timeline; only the main-session view drops it.
        XCTAssertEqual(summary.stageSnapshot.segments.count, 3)
        XCTAssertEqual(summary.stageSnapshot.mainSession.segments.count, 2)
        XCTAssertEqual(summary.stageSnapshot.mainSession.sleepEndDate, nightEnd)
    }

    func testMainSessionIntervalComesFromRawSamplesNotTheStageTimeline() throws {
        let type = try sleepType()
        // A 30s awake blip sits 1h55m after the night and 1h4m before the later
        // block, so under the 2h rule the raw samples chain into ONE session. With
        // `showsSubMinuteAwakeStages: false` that blip never reaches the stage
        // timeline, so regrouping the parsed segments would split the night off at
        // the resulting 3h gap. The stamped interval must follow the raw samples.
        let nightStart = try date(day: 10, hour: 23)
        let nightEnd = try date(day: 11, hour: 7)
        let blipStart = try date(day: 11, hour: 8, minute: 55)
        let laterStart = try date(day: 11, hour: 10)
        let laterEnd = try date(day: 11, hour: 12)
        let samples = [
            sample(.asleepCore, from: nightStart, to: nightEnd, type: type),
            sample(.awake, from: blipStart, to: blipStart.addingTimeInterval(30), type: type),
            sample(.asleepCore, from: laterStart, to: laterEnd, type: type)
        ]

        let summary = try XCTUnwrap(BodySleepSampleParser.sleepSummary(
            from: samples,
            date: calendar.startOfDay(for: laterEnd),
            showsSubMinuteAwakeStages: false
        ))

        let expected = try expectedMainInterval(for: samples)
        XCTAssertEqual(summary.stageSnapshot.mainSessionInterval, expected)
        XCTAssertEqual(expected, DateInterval(start: nightStart, end: laterEnd))

        // Canary: the blip really is absent from the timeline, and sessionizing
        // what's left would have produced a different (shorter) window.
        XCTAssertFalse(summary.stageSnapshot.segments.contains { $0.stage == .awake })
        let withoutBlip = samples.filter { $0.value != HKCategoryValueSleepAnalysis.awake.rawValue }
        let regrouped = BodySleepSessionizer.sessions(from: withoutBlip)
        XCTAssertEqual(regrouped.count, 2)
        XCTAssertEqual(
            BodySleepSessionizer.mainSession(in: regrouped)?.interval,
            DateInterval(start: nightStart, end: nightEnd)
        )
    }

    func testMainSessionIntervalMatchesSessionizerForOverlappingMultiSourceNight() throws {
        let type = try sleepType()
        // An aggregate `asleep` block plus overlapping detailed stages inside it
        // (the multi-source shape), plus an afternoon nap on the same wake day.
        let aggregateStart = try date(day: 10, hour: 23)
        let aggregateEnd = try date(day: 11, hour: 6)
        let coreStart = try date(day: 10, hour: 23, minute: 15)
        let coreEnd = try date(day: 11, hour: 2)
        let remEnd = try date(day: 11, hour: 5, minute: 30)
        let napStart = try date(day: 11, hour: 14)
        let napEnd = try date(day: 11, hour: 15)
        let samples = [
            sample(.asleepUnspecified, from: aggregateStart, to: aggregateEnd, type: type),
            sample(.asleepCore, from: coreStart, to: coreEnd, type: type),
            sample(.asleepREM, from: coreEnd, to: remEnd, type: type),
            sample(.asleepCore, from: napStart, to: napEnd, type: type)
        ]

        let summary = try XCTUnwrap(BodySleepSampleParser.sleepSummary(
            from: samples,
            date: calendar.startOfDay(for: aggregateEnd)
        ))

        let expected = try expectedMainInterval(for: samples)
        XCTAssertEqual(summary.stageSnapshot.mainSessionInterval, expected)
        XCTAssertEqual(expected, DateInterval(start: aggregateStart, end: aggregateEnd))
        XCTAssertEqual(summary.stageSnapshot.mainSession.sleepEndDate, aggregateEnd)
        XCTAssertEqual(summary.stageSnapshot.sleepEndDate, napEnd)
    }
}
