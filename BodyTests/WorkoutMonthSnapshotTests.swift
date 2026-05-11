//
//  WorkoutMonthSnapshotTests.swift
//  BodyTests
//

import XCTest
@testable import Body

final class WorkoutMonthSnapshotTests: XCTestCase {
    func testMonthSnapshotBuildsSundayFirstCalendarDays() throws {
        let workouts = [
            workout(day: 6, type: .walking, duration: 3_000),
            workout(day: 6, type: .running, duration: 2_400),
            workout(day: 9, type: .strengthTraining, duration: 3_600)
        ]

        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: workouts, calendar: .bodyGregorian)

        XCTAssertEqual(snapshot.days.count, 31)
        XCTAssertEqual(snapshot.leadingBlankDayCount, 5)
        XCTAssertEqual(snapshot.activeDayCount, 2)
        XCTAssertEqual(snapshot.workoutCount, 3)
        XCTAssertEqual(snapshot.day(6)?.workoutCount, 2)
        XCTAssertEqual(snapshot.day(6)?.primaryWorkoutType, .walking)
        XCTAssertEqual(snapshot.day(9)?.primaryWorkoutType, .strengthTraining)
    }

    func testSnapshotStoreRoundTripsCurrentMonthSnapshot() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let snapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [workout(day: 3, type: .cycling, duration: 4_200)],
            calendar: .bodyGregorian
        )

        WorkoutSnapshotStore.save(snapshot, defaults: defaults)

        XCTAssertEqual(WorkoutSnapshotStore.load(defaults: defaults), snapshot)
    }

    func testWorkoutTypeBreakdownSortsByTotalDuration() throws {
        let workouts = [
            workout(day: 1, type: .running, duration: 1_800),
            workout(day: 2, type: .walking, duration: 3_000),
            workout(day: 3, type: .running, duration: 1_500),
            workout(day: 4, type: .strengthTraining, duration: 2_400)
        ]

        let snapshot = WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: workouts, calendar: .bodyGregorian)
        let breakdown = snapshot.workoutTypeBreakdown

        XCTAssertEqual(breakdown.map(\.type), [.running, .walking, .strengthTraining])
        XCTAssertEqual(breakdown.first?.duration, 3_300)
        XCTAssertEqual(breakdown.first?.count, 2)
    }

    func testBodyValueFormatUsesImperialUnitsForUSLocale() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(BodyValueFormat.massDisplay(kilograms: 69.3, locale: locale).unit, "lb")
        XCTAssertEqual(BodyValueFormat.distanceText(meters: 1_609.344, locale: locale), "1.0 mi")
    }

    func testBodyValueFormatUsesMetricUnitsOutsideUSLocale() {
        let locale = Locale(identifier: "en_GB")

        XCTAssertEqual(BodyValueFormat.massDisplay(kilograms: 69.3, locale: locale).unit, "kg")
        XCTAssertEqual(BodyValueFormat.distanceText(meters: 1_000, locale: locale), "1.0 km")
    }

    func testBodyValueFormatUnitPreferenceOverridesLocale() {
        let usLocale = Locale(identifier: "en_US")
        let metricLocale = Locale(identifier: "en_GB")

        XCTAssertEqual(
            BodyValueFormat.massDisplay(
                kilograms: 69.3,
                locale: usLocale,
                unitPreference: .metric
            ).unit,
            "kg"
        )
        XCTAssertEqual(
            BodyValueFormat.distanceText(
                meters: 1_609.344,
                locale: metricLocale,
                unitPreference: .imperial
            ),
            "1.0 mi"
        )
    }

    func testHealthTrendRangeDefaultsToRecentWeek() {
        XCTAssertEqual(BodyHealthTrendRange.defaultValue, .recentWeek)
        XCTAssertEqual(BodyHealthTrendRange.storedValue(from: "unknown"), .recentWeek)
    }

    func testHealthTrendSeriesLimitsToRecentWeek() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let points = try (-29...0).enumerated().map { index, offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: currentDate)))
            return HealthTrendDataPoint(date: date, value: Double(index))
        }
        let series = HealthTrendSeries(points: points)

        XCTAssertEqual(series.limited(to: .recentWeek, calendar: calendar, date: currentDate).points.map(\.value), [23, 24, 25, 26, 27, 28, 29])
        XCTAssertEqual(series.limited(to: .recentMonth, calendar: calendar, date: currentDate), series)
    }

    private func workout(day: Int, type: BodyWorkoutType, duration: TimeInterval) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", day))") ?? UUID(),
            type: type,
            startDate: Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: day, hour: 8)) ?? Date(),
            duration: duration,
            activeEnergyKilocalories: 100,
            distanceMeters: 1_000,
            sourceName: "Tests"
        )
    }
}
