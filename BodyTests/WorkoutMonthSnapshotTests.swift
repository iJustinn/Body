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

    func testSnapshotStoreRoundTripsCurrentMonthSnapshotFromFileURL() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("snapshot.json")
        let snapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [workout(day: 11, type: .running, duration: 2_100)],
            calendar: .bodyGregorian
        )

        WorkoutSnapshotStore.save(snapshot, fileURL: fileURL)

        XCTAssertEqual(WorkoutSnapshotStore.load(fileURL: fileURL), snapshot)
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

    func testBodyValueFormatSystemPreferenceUsesLocaleMeasurementOverride() {
        let usMetricLocale = Locale(identifier: "en_US@measure=metric")

        XCTAssertEqual(
            BodyValueFormat.massDisplay(kilograms: 69.3, locale: usMetricLocale).unit,
            "kg"
        )
        XCTAssertEqual(
            BodyValueFormat.distanceText(meters: 1_000, locale: usMetricLocale),
            "1.0 km"
        )
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

    func testWorkoutDetailPresentationFormatsWorkoutMetrics() throws {
        let calendar = Calendar.bodyGregorian
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let startDate = try XCTUnwrap(calendar.date(
            from: DateComponents(timeZone: timeZone, year: 2026, month: 5, day: 11, hour: 15, minute: 57, second: 21)
        ))
        let workout = WorkoutSummary(
            type: .strengthTraining,
            startDate: startDate,
            duration: 3_639,
            activeEnergyKilocalories: 416,
            totalEnergyKilocalories: 482,
            distanceMeters: 1_000,
            averageHeartRateBeatsPerMinute: 122,
            effortLevel: 7,
            heartRateSamples: [
                WorkoutHeartRateSample(date: startDate, beatsPerMinute: 102),
                WorkoutHeartRateSample(date: startDate.addingTimeInterval(60), beatsPerMinute: 122),
                WorkoutHeartRateSample(date: startDate.addingTimeInterval(120), beatsPerMinute: 146)
            ],
            sourceName: "Motra"
        )

        let presentation = WorkoutDetailPresentation(
            workout: workout,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            unitPreference: .metric
        )

        XCTAssertEqual(presentation.title, "Strength")
        XCTAssertEqual(presentation.dateTitle, "Mon, May 11")
        XCTAssertEqual(presentation.timeRangeText, "15:57-16:58")
        XCTAssertEqual(presentation.durationClockText, "1:00:39")
        XCTAssertEqual(presentation.activeEnergyText, "416 kcal")
        XCTAssertEqual(presentation.totalEnergyText, "482 kcal")
        XCTAssertEqual(presentation.averageHeartRateText, "122 BPM")
        XCTAssertEqual(presentation.distanceText, "1.0 km")
        XCTAssertEqual(presentation.effortText, "7 Hard")
        XCTAssertEqual(presentation.effortPresentation?.intensity, .hard)
        XCTAssertEqual(presentation.effortPresentation?.segmentFills, [1, 1, 1, 0.5, 0])
        XCTAssertEqual(presentation.heartRateSamples.map(\.beatsPerMinute), [102, 122, 146])
        XCTAssertEqual(presentation.sourceText, "Motra")
        XCTAssertEqual(presentation.detailMetrics.map(\.title), ["Active Kcal", "Total Kcal", "Avg Heart Rate", "Distance"])
    }

    func testWorkoutEffortPresentationMapsScoresToAppleStyleBars() throws {
        let locale = Locale(identifier: "en_US_POSIX")

        let easy = try XCTUnwrap(WorkoutEffortPresentation(score: 2, locale: locale))
        XCTAssertEqual(easy.valueText, "2")
        XCTAssertEqual(easy.descriptor, "Easy")
        XCTAssertEqual(easy.intensity, .easy)
        XCTAssertEqual(easy.segmentFills, [1, 0, 0, 0, 0])

        let hard = try XCTUnwrap(WorkoutEffortPresentation(score: 7, locale: locale))
        XCTAssertEqual(hard.valueText, "7")
        XCTAssertEqual(hard.descriptor, "Hard")
        XCTAssertEqual(hard.intensity, .hard)
        XCTAssertEqual(hard.segmentFills, [1, 1, 1, 0.5, 0])

        let allOut = try XCTUnwrap(WorkoutEffortPresentation(score: 10, locale: locale))
        XCTAssertEqual(allOut.valueText, "10")
        XCTAssertEqual(allOut.descriptor, "All Out")
        XCTAssertEqual(allOut.intensity, .allOut)
        XCTAssertEqual(allOut.segmentFills, [1, 1, 1, 1, 1])
    }

    func testWorkoutDetailPresentationOmitsDistanceMetricWhenDistanceDoesNotExist() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 15, minute: 57)
        ))
        let workout = WorkoutSummary(
            type: .strengthTraining,
            startDate: startDate,
            duration: 3_600,
            activeEnergyKilocalories: 416,
            totalEnergyKilocalories: 482,
            distanceMeters: nil,
            averageHeartRateBeatsPerMinute: 122,
            sourceName: "Motra"
        )

        let presentation = WorkoutDetailPresentation(
            workout: workout,
            locale: Locale(identifier: "en_US_POSIX"),
            unitPreference: .metric
        )

        XCTAssertEqual(presentation.detailMetrics.map(\.title), ["Active Kcal", "Total Kcal", "Avg Heart Rate"])
        XCTAssertNil(presentation.distanceText)
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
