//
//  SleepSummaryAsOfTests.swift
//  BodyTests
//
//  Locks `SleepSummary.asOf` — the guard that stops a stale, already-completed
//  night from being displayed as "today's" sleep after midnight, before
//  tonight's session has ended (the Home Sleep card and Sleep detail hero
//  otherwise kept echoing yesterday's session onto the new calendar day).
//

import XCTest
@testable import Body

final class SleepSummaryAsOfTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: 7))!
    }

    private func summary(dated date: Date?) -> SleepSummary {
        SleepSummary(
            duration: 6 * 3600,
            stageSnapshot: SleepStageSnapshot(
                date: date,
                segments: [SleepStageSegment(stage: .core, startDate: day(1), endDate: day(1))]
            ),
            vitals: .empty
        )
    }

    func testAsOfReturnsSelfWhenStageSnapshotDateMatchesToday() {
        let today = day(4)
        let sleep = summary(dated: today)

        XCTAssertEqual(sleep.asOf(today, calendar: calendar), sleep)
    }

    func testAsOfReturnsNilForAPriorNightCarriedIntoTheNewDay() {
        // The exact repro: a session dated the 3rd should not be handed back
        // as "today's" sleep once the calendar has rolled to the 4th.
        let staleSleep = summary(dated: day(3))

        XCTAssertNil(staleSleep.asOf(day(4), calendar: calendar))
    }

    func testAsOfReturnsNilForAnEmptySummary() {
        let empty = SleepSummary(duration: nil)

        XCTAssertNil(empty.asOf(day(4), calendar: calendar))
    }

    func testAsOfReturnsNilWhenStageSnapshotDateIsNilEvenWithContent() {
        // Stricter than the leniency `ReadinessScoreCalculator` uses for a
        // missing date — real HealthKit-derived summaries always carry a
        // stage-snapshot date, so treating a missing one as untrustworthy is
        // the safer default here.
        let undated = summary(dated: nil)

        XCTAssertNil(undated.asOf(day(4), calendar: calendar))
    }
}
