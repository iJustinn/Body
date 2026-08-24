//
//  ReadinessComputeSupportTests.swift
//  BodyTests
//
//  Locks the pure wake-cycle statics extracted out of `HealthKitWorkoutStore`
//  in Phase 1 of the on-watch compute plan — `HealthKitWorkoutStore.freezeWakeTime`/
//  `.wakeCycleStart` already have dedicated coverage in
//  `ActivityReadinessImpactTests` (which this refactor keeps passing unchanged,
//  since the store now just delegates); this file covers the new shared surface
//  the watch will call directly: `ReadinessComputeSupport.wakeCycleWorkouts`, plus
//  a same-module regression check that the store's delegating statics still agree.
//

import XCTest
@testable import Body

final class ReadinessComputeSupportTests: XCTestCase {
    private func workout(_ start: Date, minutes: Double = 30) -> WorkoutSummary {
        WorkoutSummary(type: .running, startDate: start, duration: minutes * 60)
    }

    /// Direct expected-value assertions rather than `HealthKitWorkoutStore.freezeWakeTime`
    /// == `ReadinessComputeSupport.freezeWakeTime` (a tautology once the store
    /// just forwards to the shared static — it would still pass if BOTH sides
    /// were wrong the same way). Every branch: valid same-day wake, a
    /// future-relative-to-`now` wake, a wake on the wrong day, and no wake at all.
    func testFreezeWakeTimeReturnsSleepEndOnlyWhenValidForTheScoringDay() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let now = day.addingTimeInterval(11 * 3_600) // 11:00

        // Valid: sleep ended today, before `now`.
        let sameDayWake = day.addingTimeInterval(7 * 3_600) // 07:00
        XCTAssertEqual(
            ReadinessComputeSupport.freezeWakeTime(sleepEnd: sameDayWake, scoringDay: day, now: now, calendar: calendar),
            sameDayWake
        )

        // Invalid: sleep end is in the FUTURE relative to `now`.
        let futureWake = now.addingTimeInterval(3_600)
        XCTAssertNil(
            ReadinessComputeSupport.freezeWakeTime(sleepEnd: futureWake, scoringDay: day, now: now, calendar: calendar)
        )

        // Invalid: sleep ended on a DIFFERENT day than the scoring day.
        let yesterdayWake = day.addingTimeInterval(-2 * 3_600) // yesterday 22:00
        XCTAssertNil(
            ReadinessComputeSupport.freezeWakeTime(sleepEnd: yesterdayWake, scoringDay: day, now: now, calendar: calendar)
        )

        // Fallback branch: no sleep end at all.
        XCTAssertNil(
            ReadinessComputeSupport.freezeWakeTime(sleepEnd: nil, scoringDay: day, now: now, calendar: calendar)
        )
    }

    /// Direct expected-value assertions rather than a store/shared-static
    /// delegation check (see the comment above). Recent wake, stale (>24h) wake,
    /// no wake, and a wake that's in the future relative to `now` (also falls
    /// back — the guard requires `sleepEnd <= now`).
    func testWakeCycleStartReturnsSleepEndOnlyWhenRecentOtherwiseMidnight() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let now = day.addingTimeInterval(11 * 3_600) // 11:00

        // Recent wake (a few hours ago): returned exactly.
        let recentWake = now.addingTimeInterval(-4 * 3_600)
        XCTAssertEqual(
            ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: recentWake, calendar: calendar),
            recentWake
        )

        // Stale wake (more than `maxWakeCycleSeconds`, 24h, ago): falls back to
        // midnight of `now`.
        let staleWake = now.addingTimeInterval(-30 * 3_600)
        XCTAssertEqual(
            ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: staleWake, calendar: calendar),
            calendar.startOfDay(for: now)
        )

        // No wake at all: midnight of `now`.
        XCTAssertEqual(
            ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: nil, calendar: calendar),
            calendar.startOfDay(for: now)
        )

        // A "wake" in the future relative to `now`: also falls back.
        let futureWake = now.addingTimeInterval(3_600)
        XCTAssertEqual(
            ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: futureWake, calendar: calendar),
            calendar.startOfDay(for: now)
        )
    }

    func testWakeCycleWorkoutsKeepsOnlyThoseFromCycleStartThroughNow() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let now = day.addingTimeInterval(11 * 3_600) // 11:00
        let wake = day.addingTimeInterval(7 * 3_600) // 07:00 — recent, so cycleStart == wake

        let before = workout(wake.addingTimeInterval(-3_600)) // 06:00 — before wake
        let atWake = workout(wake) // exactly at wake
        let midCycle = workout(day.addingTimeInterval(9 * 3_600)) // 09:00
        let future = workout(now.addingTimeInterval(3_600)) // 12:00 — after `now`

        let kept = ReadinessComputeSupport.wakeCycleWorkouts(
            from: [before, atWake, midCycle, future],
            now: now,
            sleepEnd: wake,
            calendar: calendar
        )

        XCTAssertEqual(Set(kept.map(\.id)), Set([atWake.id, midCycle.id]))
    }

    func testWakeCycleWorkoutsFallsBackToMidnightWhenSleepEndIsStaleOrMissing() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let now = day.addingTimeInterval(2 * 3_600) // 02:00
        let staleWake = now.addingTimeInterval(-30 * 3_600) // ~30h ago — rejected

        let beforeMidnight = workout(day.addingTimeInterval(-3_600)) // yesterday 23:00
        let afterMidnight = workout(day.addingTimeInterval(3_600)) // today 01:00

        let keptWithStaleWake = ReadinessComputeSupport.wakeCycleWorkouts(
            from: [beforeMidnight, afterMidnight],
            now: now,
            sleepEnd: staleWake,
            calendar: calendar
        )
        XCTAssertEqual(keptWithStaleWake.map(\.id), [afterMidnight.id])

        let keptWithNoWake = ReadinessComputeSupport.wakeCycleWorkouts(
            from: [beforeMidnight, afterMidnight],
            now: now,
            sleepEnd: nil,
            calendar: calendar
        )
        XCTAssertEqual(keptWithNoWake.map(\.id), [afterMidnight.id])
    }

    /// Regression for the nap-day activity-drain bug (3% shown as 32%): an
    /// afternoon nap must NOT reset the wake cycle and drop the morning's
    /// workouts from the drain. `dateInterval?.end` (the whole day's last
    /// asleep moment, i.e. the nap's end) used to be passed as `sleepEnd`
    /// here; `wakeCycleEnd` (the first sleep session's end) is the fix.
    func testWakeCycleWorkoutsUsesFirstSleepSessionEndNotNapEnd() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let night = SleepStageSegment(
            stage: .core,
            startDate: day.addingTimeInterval(-1 * 3_600), // yesterday 23:00
            endDate: day.addingTimeInterval(7 * 3_600) // 07:00
        )
        let nap = SleepStageSegment(
            stage: .core,
            startDate: day.addingTimeInterval(17 * 3_600), // 17:00
            endDate: day.addingTimeInterval(17.5 * 3_600) // 17:30
        )
        let snapshot = SleepStageSnapshot(
            date: day,
            segments: [night, nap],
            mainSessionInterval: DateInterval(start: night.startDate, end: night.endDate)
        )

        let now = day.addingTimeInterval(18 * 3_600) // 18:00
        let morningWorkouts = [
            workout(day.addingTimeInterval(7.5 * 3_600)), // 07:30
            workout(day.addingTimeInterval(8.5 * 3_600)), // 08:30
            workout(day.addingTimeInterval(9.5 * 3_600)) // 09:30
        ]

        // Fixed behavior: anchored on the first sleep session's end, all three
        // morning workouts stay in the drain.
        let kept = ReadinessComputeSupport.wakeCycleWorkouts(
            from: morningWorkouts,
            now: now,
            sleepEnd: snapshot.wakeCycleEnd,
            calendar: calendar
        )
        XCTAssertEqual(Set(kept.map(\.id)), Set(morningWorkouts.map(\.id)))

        // The bug this replaces: anchoring on the whole day's last asleep
        // moment (the nap's end) drops every morning workout, since the wake
        // cycle then only reaches back to 17:30.
        let keptWithOldBug = ReadinessComputeSupport.wakeCycleWorkouts(
            from: morningWorkouts,
            now: now,
            sleepEnd: snapshot.dateInterval?.end,
            calendar: calendar
        )
        XCTAssertTrue(keptWithOldBug.isEmpty)
    }

    /// Companion to the drain regression above: the morning freeze anchors on
    /// the same first-sleep-session end, not the nap.
    func testFreezeWakeTimeUsesFirstSleepSessionEndNotNapEnd() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let night = SleepStageSegment(
            stage: .core,
            startDate: day.addingTimeInterval(-1 * 3_600), // yesterday 23:00
            endDate: day.addingTimeInterval(7 * 3_600) // 07:00
        )
        let nap = SleepStageSegment(
            stage: .core,
            startDate: day.addingTimeInterval(17 * 3_600), // 17:00
            endDate: day.addingTimeInterval(17.5 * 3_600) // 17:30
        )
        let snapshot = SleepStageSnapshot(
            date: day,
            segments: [night, nap],
            mainSessionInterval: DateInterval(start: night.startDate, end: night.endDate)
        )

        let now = day.addingTimeInterval(18 * 3_600) // 18:00
        XCTAssertEqual(
            ReadinessComputeSupport.freezeWakeTime(
                sleepEnd: snapshot.wakeCycleEnd, scoringDay: day, now: now, calendar: calendar
            ),
            day.addingTimeInterval(7 * 3_600)
        )
    }
}
