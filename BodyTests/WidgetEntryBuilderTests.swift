//
//  WidgetEntryBuilderTests.swift
//  BodyTests
//
//  Covers the widget entry builders in BodyShared/Widgets, which the widget
//  providers call to decide what a timeline entry contains. The providers
//  themselves live in BodyWidgetExtension (not compiled into any test target),
//  so this is where the month rollover, the Pro gate, the stale-sleep
//  sanitization and the rolling exercise week are actually exercised.
//

import XCTest
@testable import Body

final class WidgetEntryBuilderTests: XCTestCase {

    // MARK: - Workout calendar rollover

    /// Europe/London, where DST began on 2026-03-29: a month boundary computed
    /// in UTC (or with a fixed 24h step) would land an hour off.
    private var londonCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func londonDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        londonCalendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        )!
    }

    private func monthSnapshot(month: Int, year: Int, generatedAt: Date, calendar: Calendar) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot.make(
            month: month,
            year: year,
            workouts: [
                WorkoutSummary(
                    type: .running,
                    startDate: calendar.date(from: DateComponents(year: year, month: month, day: 2, hour: 9))!,
                    duration: 1_800
                )
            ],
            calendar: calendar,
            generatedAt: generatedAt
        )
    }

    func testMonthRolloverEntryLandsExactlyAtTheNextMonthStartInLondon() throws {
        let calendar = londonCalendar
        let now = londonDate(2026, 3, 31, 23, 59, 30)
        let snapshot = monthSnapshot(month: 3, year: 2026, generatedAt: now, calendar: calendar)

        let built = WorkoutCalendarEntryBuilder.timeline(snapshot: snapshot, isPro: true, now: now, calendar: calendar)

        XCTAssertEqual(built.entries.count, 2)
        XCTAssertEqual(built.entries[0].date, now)
        XCTAssertEqual(built.entries[0].snapshot, snapshot)

        let aprilStart = londonDate(2026, 4, 1, 0, 0, 0)
        XCTAssertEqual(built.entries[1].date, aprilStart)
        XCTAssertEqual(built.entries[1].snapshot.month, 4)
        XCTAssertEqual(built.entries[1].snapshot.year, 2026)
        XCTAssertEqual(built.entries[1].snapshot.workoutCount, 0, "The new month starts empty, not carrying March's workouts.")
        XCTAssertEqual(built.reloadAfter, now.addingTimeInterval(30 * 60))
    }

    /// Thirty seconds into April the rollover entry is May's, not another
    /// April 1 entry: the boundary already passed, so re-showing it would
    /// re-blank the month the widget just started filling.
    func testJustAfterTheBoundaryTheRolloverEntryIsTheFollowingMonth() {
        let calendar = londonCalendar
        let now = londonDate(2026, 4, 1, 0, 0, 30)
        let snapshot = monthSnapshot(month: 4, year: 2026, generatedAt: now, calendar: calendar)

        let built = WorkoutCalendarEntryBuilder.timeline(snapshot: snapshot, isPro: true, now: now, calendar: calendar)

        XCTAssertEqual(built.entries.count, 2)
        XCTAssertNotEqual(built.entries[1].date, londonDate(2026, 4, 1, 0, 0, 0))
        XCTAssertEqual(built.entries[1].date, londonDate(2026, 5, 1, 0, 0, 0))
        XCTAssertEqual(built.entries[1].snapshot.month, 5)
    }

    func testProGateAppliesToEveryWorkoutCalendarEntry() {
        let calendar = londonCalendar
        let now = londonDate(2026, 3, 31, 23, 59, 30)
        let snapshot = monthSnapshot(month: 3, year: 2026, generatedAt: now, calendar: calendar)

        for isPro in [true, false] {
            let built = WorkoutCalendarEntryBuilder.timeline(snapshot: snapshot, isPro: isPro, now: now, calendar: calendar)
            XCTAssertEqual(built.entries.count, 2)
            XCTAssertEqual(built.entries.map(\.isPro), [isPro, isPro])
        }
    }

    // MARK: - Stale sleep sanitization

    private let calendar = Calendar.bodyGregorian

    /// A snapshot holding a completed night dated `night`, with the `.sleep`
    /// metric's display value filled in (mirroring the fixture shape in
    /// `HealthWidgetSnapshotBuilderSleepTests`).
    private func sleepSnapshot(night: Date) -> HealthWidgetSnapshot {
        let nightStart = calendar.startOfDay(for: night)
        let sleep = HealthWidgetSleepStages(
            night: nightStart,
            sourceName: "Apple Watch",
            segments: [
                HealthWidgetSleepSegment(
                    stage: .core,
                    startDate: nightStart.addingTimeInterval(-2 * 3_600),
                    endDate: nightStart.addingTimeInterval(6 * 3_600)
                )
            ]
        )
        let trend = HealthWidgetMetricTrend(
            metric: .sleep,
            primarySourceName: "Apple Watch",
            week: HealthWidgetTrendSeries(points: [], averageText: "7h 30m", latestText: "7h 32m"),
            month: HealthWidgetTrendSeries(points: [], averageText: "7h 30m", latestText: "7h 32m"),
            displayValues: [HealthWidgetDisplayValue(value: "7h 32m", unit: "")]
        )
        return HealthWidgetSnapshot(generatedDate: nightStart, metricTrends: [trend], sleep: sleep)
    }

    private func assertSanitizesStaleSleep(
        _ resolve: (HealthWidgetSnapshot?, Bool, Bool, Date) -> (snapshot: HealthWidgetSnapshot, isPro: Bool),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let today = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let stale = sleepSnapshot(night: yesterday)

        let sanitized = resolve(stale, false, true, today).snapshot
        XCTAssertTrue(sanitized.sleep.isEmpty, "Yesterday's completed night must not survive into today's entry.", file: file, line: line)
        XCTAssertNil(sanitized.sleep.night, file: file, line: line)
        XCTAssertEqual(sanitized.trend(for: .sleep)?.displayValues.first?.value, "--", file: file, line: line)

        let fresh = resolve(sleepSnapshot(night: today), false, true, today).snapshot
        XCTAssertFalse(fresh.sleep.isEmpty, "Tonight's own night passes through intact.", file: file, line: line)

        // No cache: the live timeline gets the honest empty snapshot, the
        // gallery preview the placeholder.
        XCTAssertTrue(resolve(nil, false, true, today).snapshot.isEmpty, file: file, line: line)
        XCTAssertFalse(resolve(nil, true, true, today).snapshot.isEmpty, file: file, line: line)

        // The Pro gate rides through untouched, on both branches.
        XCTAssertTrue(resolve(stale, false, true, today).isPro, file: file, line: line)
        XCTAssertFalse(resolve(stale, false, false, today).isPro, file: file, line: line)
    }

    func testHealthMetricBuilderSanitizesStaleSleepAndCarriesTheProGate() {
        assertSanitizesStaleSleep { snapshot, usePlaceholder, isPro, now in
            HealthMetricEntryBuilder.resolve(
                snapshot: snapshot,
                usePlaceholderWhenEmpty: usePlaceholder,
                isPro: isPro,
                now: now,
                calendar: calendar
            )
        }
    }

    func testHealthTrendBuilderSanitizesStaleSleepAndCarriesTheProGate() {
        assertSanitizesStaleSleep { snapshot, usePlaceholder, isPro, now in
            HealthTrendEntryBuilder.resolve(
                snapshot: snapshot,
                usePlaceholderWhenEmpty: usePlaceholder,
                isPro: isPro,
                now: now,
                calendar: calendar
            )
        }
    }

    func testSleepStagesBuilderSanitizesStaleSleepAndCarriesTheProGate() {
        assertSanitizesStaleSleep { snapshot, usePlaceholder, isPro, now in
            SleepStagesEntryBuilder.resolve(
                snapshot: snapshot,
                usePlaceholderWhenEmpty: usePlaceholder,
                isPro: isPro,
                now: now,
                calendar: calendar
            )
        }
    }

    // MARK: - Exercise week

    private func workoutMonth(month: Int, year: Int, minutesByDay: [Int: Double]) -> WorkoutMonthSnapshot {
        let workouts = minutesByDay.map { day, minutes in
            WorkoutSummary(
                type: .running,
                startDate: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!,
                duration: minutes * 60
            )
        }
        return WorkoutMonthSnapshot.make(month: month, year: year, workouts: workouts, calendar: calendar)
    }

    /// Mirrors `HealthWidgetPointRewindingWeekTests`: a cache written on an
    /// earlier day still ends on today once the builder re-windows it.
    func testExerciseWeekPointsEndOnTodayWithPerDayMinutes() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 21))!
        let current = workoutMonth(month: 6, year: 2026, minutesByDay: [8: 30, 10: 45])
        let previous = workoutMonth(month: 5, year: 2026, minutesByDay: [31: 20])

        let points = ExerciseWeekEntryBuilder.points(
            current: current,
            previous: previous,
            usePlaceholderWhenEmpty: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points.last?.date, calendar.startOfDay(for: now))
        XCTAssertEqual(points.first?.date, calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!)
        // June 4...10, with a real 0 for every rest day inside the month.
        XCTAssertEqual(points.map(\.value), [0, 0, 0, 0, 30, 0, 45])
    }

    func testExerciseWeekFallsBackToPlaceholderOnlyForAnEmptyPreview() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 21))!
        let empty = workoutMonth(month: 6, year: 2026, minutesByDay: [:])

        let preview = ExerciseWeekEntryBuilder.points(
            current: empty,
            previous: nil,
            usePlaceholderWhenEmpty: true,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(preview.map(\.value), [30, 45, 0, 60, 25, 50, 40])
        XCTAssertEqual(preview.last?.date, calendar.startOfDay(for: now))

        let live = ExerciseWeekEntryBuilder.points(
            current: empty,
            previous: nil,
            usePlaceholderWhenEmpty: false,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(live.map(\.value), [0, 0, 0, 0, 0, 0, 0], "A real all-zero month is not a preview.")
    }

    func testWeekdayLetterUsesThePassedCalendar() {
        // 2026-06-10 is a Wednesday.
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 12))!
        let formatter = DateFormatter()
        formatter.locale = .current
        let expected = (formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"])[3]

        XCTAssertEqual(ExerciseWeekEntryBuilder.weekdayLetter(for: wednesday, calendar: calendar), expected)
    }
}
