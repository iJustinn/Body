//
//  WorkoutMonthSnapshotTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
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

    func testPlaceholderUsesGeneratedDateMonthAndYear() throws {
        let calendar = Calendar.bodyGregorian
        let generatedAt = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 6, day: 18, hour: 9)))

        let snapshot = WorkoutMonthSnapshot.makePlaceholder(generatedAt: generatedAt, calendar: calendar)

        XCTAssertEqual(snapshot.month, 6)
        XCTAssertEqual(snapshot.year, 2027)
        XCTAssertEqual(snapshot.days.count, 30)
        let firstWorkout = try XCTUnwrap(snapshot.day(1)?.workouts.first)
        let components = calendar.dateComponents([.year, .month, .day], from: firstWorkout.startDate)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 1)
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

    func testWorkoutTypeBreakdownRowPresentationMovesWorkoutCountIntoTitle() {
        let presentation = WorkoutTypeBreakdownRowPresentation(
            entry: WorkoutTypeBreakdown(
                type: .strengthTraining,
                duration: 18_960,
                count: 5
            )
        )

        XCTAssertEqual(presentation.titleText, "Strength × 5")
        XCTAssertEqual(presentation.detailText, "5h 16m")
        XCTAssertFalse(presentation.detailText.contains("workout"))
    }

    func testWorkoutRowPresentationUsesActiveEnergyWhenWorkoutHasNoDistance() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 4, day: 29, hour: 14, minute: 6)
        ))
        let workout = WorkoutSummary(
            type: .strengthTraining,
            startDate: startDate,
            duration: 4_800,
            activeEnergyKilocalories: 530,
            distanceMeters: nil,
            sourceName: "Motra"
        )

        let presentation = BodyWorkoutRowPresentation(
            workout: workout,
            locale: Locale(identifier: "en_US_POSIX"),
            unitPreference: .metric
        )

        XCTAssertEqual(presentation.detailIconName, "flame.fill")
        XCTAssertEqual(presentation.detailText, "530 kcal")
        XCTAssertNil(presentation.trailingEnergyText)
    }

    func testWorkoutRowPresentationKeepsDistancePrimaryWhenAvailable() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 4, day: 30, hour: 20, minute: 27)
        ))
        let workout = WorkoutSummary(
            type: .walking,
            startDate: startDate,
            duration: 1_500,
            activeEnergyKilocalories: 77,
            distanceMeters: 1_400,
            sourceName: "Motra"
        )

        let presentation = BodyWorkoutRowPresentation(
            workout: workout,
            locale: Locale(identifier: "en_US_POSIX"),
            unitPreference: .metric
        )

        XCTAssertEqual(presentation.detailIconName, "map.fill")
        XCTAssertEqual(presentation.detailText, "1.4 km")
        XCTAssertEqual(presentation.trailingEnergyText, "77 kcal")
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

    func testBodyValueFormatMassDisplaySupportsPrecisionOverride() {
        let locale = Locale(identifier: "en_GB")

        XCTAssertEqual(
            BodyValueFormat.massDisplay(kilograms: 69.3, locale: locale, decimals: 2).value,
            "69.30"
        )
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

    func testBodyValueFormatSpecificUnitPreferencesConvertIndependently() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(
            BodyValueFormat.massDisplay(
                kilograms: 69.3,
                locale: locale,
                weightUnitPreference: .kilograms
            ).unit,
            "kg"
        )
        XCTAssertEqual(
            BodyValueFormat.distanceText(
                meters: 1_609.344,
                locale: locale,
                distanceUnitPreference: .kilometers
            ),
            "1.6 km"
        )
        XCTAssertEqual(
            BodyValueFormat.energyText(
                kilocalories: 100,
                locale: locale,
                energyUnitPreference: .kilojoules
            ),
            "418 kJ"
        )
        XCTAssertEqual(
            BodyValueFormat.temperatureDisplay(
                celsius: 36.5,
                locale: locale,
                temperatureUnitPreference: .celsius
            ).unit,
            "C"
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

    func testTrainingLoadCalculatorUsesDurationAndEffort() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 12, hour: 7)
        ))
        let hardWorkout = WorkoutSummary(
            type: .running,
            startDate: startDate,
            duration: 30 * 60,
            effortLevel: 7
        )
        let defaultEffortWorkout = WorkoutSummary(
            type: .walking,
            startDate: startDate,
            duration: 20 * 60
        )
        let cappedEffortWorkout = WorkoutSummary(
            type: .hiit,
            startDate: startDate,
            duration: 10 * 60,
            effortLevel: 12
        )
        let invalidWorkout = WorkoutSummary(
            type: .yoga,
            startDate: startDate,
            duration: 0,
            effortLevel: 8
        )

        XCTAssertEqual(try XCTUnwrap(TrainingLoadCalculator.load(for: hardWorkout)), 210, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TrainingLoadCalculator.load(for: defaultEffortWorkout)), 100, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(TrainingLoadCalculator.load(for: cappedEffortWorkout)), 100, accuracy: 0.001)
        XCTAssertNil(TrainingLoadCalculator.load(for: invalidWorkout))
    }

    func testTrainingLoadCalculatorBuildsTrainingLoadRatioSeries() throws {
        let calendar = Calendar.bodyGregorian
        let startDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 7)))
        let rampDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 18)))
        let steadyWorkouts = (0..<42).compactMap { offset -> WorkoutSummary? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else {
                return nil
            }

            return WorkoutSummary(
                type: .running,
                startDate: day,
                duration: 20 * 60,
                effortLevel: 5
            )
        }
        let workouts = steadyWorkouts + [
            WorkoutSummary(
                type: .cycling,
                startDate: rampDay,
                duration: 40 * 60,
                effortLevel: 5
            )
        ]

        let series = TrainingLoadCalculator.dailySeries(
            from: workouts,
            startDate: startDay,
            endDate: rampDay,
            calendar: calendar
        )
        let summary = TrainingLoadCalculator.summary(
            on: rampDay,
            from: workouts,
            startDate: startDay,
            calendar: calendar
        )

        XCTAssertEqual(series.points.count, 43)
        XCTAssertEqual(series.points[0].date, calendar.startOfDay(for: startDay))
        XCTAssertEqual(series.points[0].value, 1, accuracy: 0.001)
        XCTAssertEqual(series.points[41].value, 1, accuracy: 0.001)
        XCTAssertEqual(series.points[42].date, calendar.startOfDay(for: rampDay))
        XCTAssertEqual(series.points[42].value, 1.194, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(summary?.value), 1.194, accuracy: 0.001)
    }

    func testTrainingLoadIntervalClassifiesCurrentRatio() {
        XCTAssertEqual(TrainingLoadInterval.interval(for: 0.79), .stopTraining)
        XCTAssertEqual(TrainingLoadInterval.interval(for: 0.80), .optimal)
        XCTAssertEqual(TrainingLoadInterval.interval(for: 1.30), .optimal)
        XCTAssertEqual(TrainingLoadInterval.interval(for: 1.31), .mediumInjuryRisk)
        XCTAssertEqual(TrainingLoadInterval.interval(for: 1.50), .mediumInjuryRisk)
        XCTAssertEqual(TrainingLoadInterval.interval(for: 1.51), .highInjuryRisk)
        XCTAssertEqual(TrainingLoadInterval.stopTraining.title, "Resting")
        XCTAssertNil(TrainingLoadInterval.interval(for: nil))
        XCTAssertNil(TrainingLoadInterval.interval(for: Double.nan))
    }

    func testTrainingLoadIntervalBreakdownCountsFiniteDaysInSelectedRange() throws {
        let calendar = Calendar.bodyGregorian
        let endDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 14)))
        let points = [
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8))), value: 0.76),
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9))), value: 0.95),
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))), value: 1.18),
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11))), value: 1.34),
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12))), value: 1.62),
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13))), value: Double.nan),
            HealthTrendDataPoint(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))), value: 1.62)
        ]
        let series = HealthTrendSeries(points: points)

        let entries = TrainingLoadIntervalBreakdown.entries(
            for: series,
            range: .recentWeek,
            calendar: calendar,
            date: endDate
        )

        XCTAssertEqual(entries.map(\.interval), [.highInjuryRisk, .mediumInjuryRisk, .optimal, .stopTraining])
        XCTAssertEqual(entries.map(\.dayCount), [1, 1, 2, 1])
        XCTAssertEqual(entries.map(\.totalDayCount), [5, 5, 5, 5])
        let optimalEntry = try XCTUnwrap(entries.first { $0.interval == .optimal })
        XCTAssertEqual(optimalEntry.fractionOfTotal, 0.4, accuracy: 0.001)
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
        XCTAssertEqual(BodyAppearancePreference.defaultTrendRangeKey, "defaultTrendRange")
        XCTAssertEqual(BodyHealthTrendRange.defaultValue, .recentWeek)
        XCTAssertEqual(BodyHealthTrendRange.storedValue(from: "unknown"), .recentWeek)
        XCTAssertEqual(BodyHealthTrendRange.allCases, [.recentWeek, .recentMonth, .recentSixMonths, .recentYear])
        XCTAssertEqual(BodyHealthTrendRange.allCases.map(\.displayName), ["Week", "Month", "6 Months", "Year"])
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.selectionSubtitle, "6 months")
        XCTAssertEqual(BodyHealthTrendRange.recentYear.iconName, "calendar")
    }

    func testSleepDurationGoalDefaultsToEightHoursAndClampsStoredMinutes() {
        XCTAssertEqual(BodyAppearancePreference.sleepDurationGoalMinutesKey, "sleepDurationGoalMinutes")
        XCTAssertEqual(BodySleepDurationGoal.defaultMinutes, 8 * 60)
        XCTAssertEqual(BodySleepDurationGoal.storedMinutes(from: nil), 8 * 60)
        XCTAssertEqual(BodySleepDurationGoal.storedMinutes(from: 3 * 60), BodySleepDurationGoal.minimumMinutes)
        XCTAssertEqual(BodySleepDurationGoal.storedMinutes(from: 13 * 60), BodySleepDurationGoal.maximumMinutes)
        XCTAssertEqual(BodySleepDurationGoal.duration(from: 7 * 60), 7 * 60 * 60)
        XCTAssertEqual(BodySleepDurationGoal.displayText(for: 8 * 60), "8h")
    }

    func testReadinessStatusMapsScoresToBands() {
        XCTAssertEqual(ReadinessStatus.status(for: nil), .unavailable)
        XCTAssertEqual(ReadinessStatus.status(for: 100), .prime)
        XCTAssertEqual(ReadinessStatus.status(for: 95), .prime)
        XCTAssertEqual(ReadinessStatus.status(for: 94), .high)
        XCTAssertEqual(ReadinessStatus.status(for: 80), .high)
        XCTAssertEqual(ReadinessStatus.status(for: 79), .moderate)
        XCTAssertEqual(ReadinessStatus.status(for: 65), .moderate)
        XCTAssertEqual(ReadinessStatus.status(for: 64), .low)
        XCTAssertEqual(ReadinessStatus.status(for: 30), .low)
        XCTAssertEqual(ReadinessStatus.status(for: 29), .poor)
        XCTAssertEqual(ReadinessStatus.status(for: 0), .poor)
    }

    func testReadinessSummaryUnavailableIsCodable() throws {
        let summary = ReadinessSummary.unavailable
        let encoded = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(ReadinessSummary.self, from: encoded)

        XCTAssertEqual(decoded, summary)
        XCTAssertNil(decoded.score)
        XCTAssertEqual(decoded.status, .unavailable)
        XCTAssertEqual(decoded.confidence, .unavailable)
        XCTAssertTrue(decoded.components.isEmpty)
        XCTAssertTrue(decoded.drivers.isEmpty)
    }

    func testReadinessStatusExposesBoundsForChartBands() {
        XCTAssertNil(ReadinessStatus.poor.lowerBound)
        XCTAssertEqual(ReadinessStatus.poor.upperBound, 30)
        XCTAssertEqual(ReadinessStatus.low.lowerBound, 30)
        XCTAssertEqual(ReadinessStatus.low.upperBound, 65)
        XCTAssertEqual(ReadinessStatus.moderate.lowerBound, 65)
        XCTAssertEqual(ReadinessStatus.moderate.upperBound, 80)
        XCTAssertEqual(ReadinessStatus.high.lowerBound, 80)
        XCTAssertEqual(ReadinessStatus.high.upperBound, 95)
        XCTAssertEqual(ReadinessStatus.prime.lowerBound, 95)
        XCTAssertNil(ReadinessStatus.prime.upperBound)
    }

    func testReadinessStatusExposesExactRangeTextAndExplanation() {
        XCTAssertEqual(
            ReadinessStatus.displayOrder.map(\.scoreRangeText),
            ["95-100%", "80-94%", "65-79%", "30-64%", "0-29%"]
        )
        XCTAssertTrue(ReadinessStatus.prime.explanation.contains("Strong readiness"))
        XCTAssertTrue(ReadinessStatus.high.explanation.contains("Well prepared"))
        XCTAssertTrue(ReadinessStatus.moderate.explanation.contains("controlled"))
        XCTAssertTrue(ReadinessStatus.low.explanation.contains("easy"))
        XCTAssertTrue(ReadinessStatus.poor.explanation.contains("Rest"))
    }

    func testReadinessRobustBaselineUsesMedianAndMad() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let values = (1...20).compactMap { offset -> ReadinessScoreCalculator.DailyValue? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                return nil
            }

            return ReadinessScoreCalculator.DailyValue(date: date, value: offset == 1 ? 1_000 : 50)
        }

        let baseline = try XCTUnwrap(ReadinessScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 1,
            calendar: calendar
        ))

        XCTAssertEqual(baseline.validDayCount, 20)
        XCTAssertEqual(baseline.median, 50, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(baseline.spread, 1)
    }

    func testReadinessRobustBaselineReturnsNilWithTooFewDays() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let values = (1...13).compactMap { offset -> ReadinessScoreCalculator.DailyValue? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                return nil
            }

            return ReadinessScoreCalculator.DailyValue(date: date, value: 50)
        }

        XCTAssertNil(ReadinessScoreCalculator.robustBaseline(
            for: scoreDay,
            values: values,
            floor: 1,
            calendar: calendar
        ))
    }

    func testReadinessCalculatorScoresSevereAutonomicStressAsPoor() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 30,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 72,
            trainingLoadToday: 1.0,
            calendar: calendar
        )

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            calendar: calendar
        )

        XCTAssertNotNil(summary.score)
        XCTAssertLessThan(try XCTUnwrap(summary.score), 25)
        XCTAssertEqual(summary.status, .poor)
        XCTAssertTrue(summary.drivers.contains { $0.kind == .hrvBelowBaseline })
        XCTAssertTrue(summary.drivers.contains { $0.kind == .heartRateAboveBaseline })
    }

    func testReadinessCalculatorCanReachPrimeWithStrongSignals() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 70,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 50,
            trainingLoadToday: 0.65,
            calendar: calendar
        )

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            calendar: calendar
        )

        XCTAssertNotNil(summary.score)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(summary.score), 96)
        XCTAssertEqual(summary.status, .prime)
    }

    func testReadinessCalculatorDoesNotInflateBaselineDaysIntoPrime() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 55,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 58,
            trainingLoadToday: 1.0,
            calendar: calendar
        )

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            calendar: calendar
        )

        XCTAssertNotNil(summary.score)
        XCTAssertLessThan(try XCTUnwrap(summary.score), 85)
        XCTAssertNotEqual(summary.status, .prime)
    }

    func testReadinessCalculatorDoesNotTreatMissingMetricsAsZero() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: nil,
            hrvToday: nil,
            restingHeartRateBaseline: nil,
            restingHeartRateToday: nil,
            trainingLoadToday: 1.0,
            calendar: calendar
        )

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            calendar: calendar
        )

        XCTAssertNotNil(summary.score)
        XCTAssertFalse(summary.components.contains { $0.kind == .autonomic })
        XCTAssertNotEqual(summary.score, 0)
    }

    func testHealthDashboardSnapshotRecalculatesReadinessFromTrends() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 56,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 58,
            trainingLoadToday: 1.0,
            calendar: calendar
        )

        let dashboard = HealthDashboardSnapshot(
            summary: .empty,
            trends: trends
        ).recalculatingReadiness(on: scoreDay, calendar: calendar)

        XCTAssertNotNil(dashboard.summary.readiness.score)
        XCTAssertEqual(
            dashboard.trends.readiness.point(on: scoreDay)?.value,
            Double(try XCTUnwrap(dashboard.summary.readiness.score))
        )
    }

    func testHealthSummarySnapshotDecodesOldCacheWithoutReadiness() throws {
        let data = Data("""
        {
          "activityRings": {},
          "sleep": { "duration": null },
          "restingHeartRate": { "value": null },
          "bodyMass": { "value": null },
          "bodyFatPercentage": { "value": null },
          "heartRateVariability": { "value": null },
          "respiratoryRate": { "value": null },
          "oxygenSaturation": { "value": null },
          "bodyMassIndex": { "value": null },
          "activeEnergy": { "value": null },
          "restingEnergy": { "value": null }
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: data)

        XCTAssertEqual(decoded.readiness, .unavailable)
    }

    func testReadinessDailySeriesScoresEachScorableDay() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let startDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: scoreDay))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 56,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 58,
            trainingLoadToday: 1.0,
            calendar: calendar
        )

        let series = ReadinessScoreCalculator.dailySeries(
            healthSummary: .empty,
            trends: trends,
            startDate: startDate,
            endDate: scoreDay,
            calendar: calendar
        )

        XCTAssertEqual(series.points.count, 3)
        XCTAssertEqual(series.points.map(\.date), [startDate, try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: scoreDay)), scoreDay])
        XCTAssertTrue(series.points.allSatisfy { (0...100).contains($0.value) })
    }

    func testBodyHomeCardKindIncludesReadinessAfterActivityRings() throws {
        XCTAssertEqual(BodyHomeCardKind.readiness.healthMetricKind, .readiness)
        XCTAssertTrue(BodyHomeCardKind.defaultOrder.contains(.readiness))
        XCTAssertLessThan(
            try XCTUnwrap(BodyHomeCardKind.defaultOrder.firstIndex(of: .readiness)),
            try XCTUnwrap(BodyHomeCardKind.defaultOrder.firstIndex(of: .exerciseMinutes))
        )
        XCTAssertEqual(BodyHomeCardKind.readiness.title, "Readiness")
        XCTAssertTrue(BodyHomeCardKind.readiness.isBeta)
        XCTAssertEqual(BodyHomeCardKind.readiness.iconName, "bolt.heart.fill")
    }

    func testBodyHomeTrendCardKindIncludesReadiness() {
        XCTAssertEqual(BodyHomeTrendCardKind.readiness.metricKind, .readiness)
        XCTAssertTrue(BodyHomeTrendCardKind.defaultOrder.contains(.readiness))
        XCTAssertEqual(BodyHomeTrendCardKind.readiness.title, "Readiness")
    }

    func testReadinessCalculatorPenalizesHighTrainingLoad() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let trends = readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 55,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 58,
            trainingLoadToday: 1.62,
            calendar: calendar
        )

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: trends,
            calendar: calendar
        )

        XCTAssertTrue(summary.drivers.contains { $0.kind == .trainingLoadElevated })
        XCTAssertLessThan(try XCTUnwrap(summary.components.first { $0.kind == .training }?.score), 70)
    }

    func testReadinessCalculatorCreatesLowConfidenceForThinHistory() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))

        let summary = ReadinessScoreCalculator.summary(
            on: scoreDay,
            healthSummary: .empty,
            trends: .empty,
            calendar: calendar
        )

        XCTAssertNil(summary.score)
        XCTAssertEqual(summary.confidence, .unavailable)
    }

    func testReadinessIsNotSourceSelectable() {
        XCTAssertFalse(HealthMetricKind.readiness.supportsHealthDataSourceSelection)
        XCTAssertFalse(HealthMetricKind.readiness.supportsSecondaryHealthDataSourceSelection)
    }

    func testFilteringHeartPermissionLowersReadinessConfidenceInsteadOfRemovingReadinessCard() throws {
        let calendar = Calendar.bodyGregorian
        let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
        let dashboard = HealthDashboardSnapshot(
            summary: .empty,
            trends: readinessTrendSnapshot(
                scoreDay: scoreDay,
                hrvBaseline: 55,
                hrvToday: 30,
                restingHeartRateBaseline: 58,
                restingHeartRateToday: 72,
                trainingLoadToday: 1.0,
                calendar: calendar
            )
        )
        .filtered(by: BodyHealthPermissionSelection(enabledPermissions: [.workouts]))
        .recalculatingReadiness(on: scoreDay, calendar: calendar)

        XCTAssertNotEqual(dashboard.summary.readiness.confidence, ReadinessConfidence.high)
    }

    func testHealthTrendRangeShowsPointMarksOnLineRanges() {
        XCTAssertTrue(BodyHealthTrendRange.recentWeek.showsPointMarks)
        XCTAssertTrue(BodyHealthTrendRange.recentMonth.showsPointMarks)
        XCTAssertTrue(BodyHealthTrendRange.recentSixMonths.showsPointMarks)
        XCTAssertTrue(BodyHealthTrendRange.recentYear.showsPointMarks)
    }

    func testHealthTrendRangeUsesPreviewLineStyleForAllLineRanges() {
        XCTAssertTrue(BodyHealthTrendRange.recentWeek.usesPreviewLineChartStyle)
        XCTAssertTrue(BodyHealthTrendRange.recentMonth.usesPreviewLineChartStyle)
        XCTAssertTrue(BodyHealthTrendRange.recentSixMonths.usesPreviewLineChartStyle)
        XCTAssertTrue(BodyHealthTrendRange.recentYear.usesPreviewLineChartStyle)
    }

    func testHealthTrendRangeUsesMetricColorStrokeForAllRanges() {
        XCTAssertTrue(BodyHealthTrendRange.recentWeek.usesMetricColorLineStroke)
        XCTAssertTrue(BodyHealthTrendRange.recentMonth.usesMetricColorLineStroke)
        XCTAssertTrue(BodyHealthTrendRange.recentSixMonths.usesMetricColorLineStroke)
        XCTAssertTrue(BodyHealthTrendRange.recentYear.usesMetricColorLineStroke)
    }

    func testHealthTrendRangeUsesLargerLineDotsOnLineRanges() {
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.linePointDiameter, 8, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.lineCurrentPointDiameter, 10, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.linePointDiameter, 8, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.lineCurrentPointDiameter, 10, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.linePointDiameter, 8, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.lineCurrentPointDiameter, 10, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.linePointDiameter, 8, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.lineCurrentPointDiameter, 10, accuracy: 0.001)
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.linePointDiameter,
            BodyHealthTrendRange.recentMonth.linePointDiameter
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.lineCurrentPointDiameter,
            BodyHealthTrendRange.recentMonth.lineCurrentPointDiameter
        )
    }

    func testHealthTrendRangeUsesMonthLineWidthOnLongRanges() {
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.trendLineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.trendLineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.trendLineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.trendLineWidth, 3, accuracy: 0.001)
    }

    func testHealthTrendRangeWidensAggregatedBars() {
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.chartBarWidth, 32, accuracy: 0.001)
        XCTAssertGreaterThan(
            BodyHealthTrendRange.recentWeek.chartBarWidth,
            BodyHealthTrendRange.recentMonth.chartBarWidth
        )
        XCTAssertGreaterThan(
            BodyHealthTrendRange.recentSixMonths.chartBarWidth,
            BodyHealthTrendRange.recentMonth.chartBarWidth
        )
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.chartBarWidth, 8, accuracy: 0.001)
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.chartBarWidth,
            BodyHealthTrendRange.recentSixMonths.chartBarWidth,
            accuracy: 0.001
        )
    }

    func testHealthTrendRangeNarrowsHeartRateWeekRangeBars() {
        let availableWidth = CGFloat(390)

        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.heartRateRangeChartBarWidth(forAvailableWidth: availableWidth),
            24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentMonth.heartRateRangeChartBarWidth(forAvailableWidth: availableWidth),
            BodyHealthTrendRange.recentMonth.chartBarWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentSixMonths.heartRateRangeChartBarWidth(forAvailableWidth: availableWidth),
            BodyHealthTrendRange.recentSixMonths.chartBarWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.heartRateRangeChartBarWidth(forAvailableWidth: availableWidth),
            BodyHealthTrendRange.recentYear.chartBarWidth,
            accuracy: 0.001
        )
    }

    func testHealthTrendRangeNarrowsLongRangeBarsOnSmallChartWidths() {
        let smallChartWidth = CGFloat(325)
        let regularChartWidth = CGFloat(362)

        XCTAssertEqual(
            BodyHealthTrendRange.recentSixMonths.chartBarWidth(forAvailableWidth: smallChartWidth),
            5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.chartBarWidth(forAvailableWidth: smallChartWidth),
            5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentSixMonths.heartRateRangeChartBarWidth(forAvailableWidth: smallChartWidth),
            5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.heartRateRangeChartBarWidth(forAvailableWidth: smallChartWidth),
            5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentSixMonths.chartBarWidth(forAvailableWidth: regularChartWidth),
            BodyHealthTrendRange.recentSixMonths.chartBarWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.chartBarWidth(forAvailableWidth: regularChartWidth),
            BodyHealthTrendRange.recentYear.chartBarWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.chartBarWidth(forAvailableWidth: smallChartWidth),
            BodyHealthTrendRange.recentWeek.chartBarWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentMonth.chartBarWidth(forAvailableWidth: smallChartWidth),
            BodyHealthTrendRange.recentMonth.chartBarWidth,
            accuracy: 0.001
        )
    }

    func testHealthTrendRangeCapsLineChartPointsForExpandedRanges() {
        XCTAssertNil(BodyHealthTrendRange.recentWeek.lineChartMaximumPointCount)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.lineChartMaximumPointCount, 25)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.lineChartMaximumPointCount, 25)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.lineChartMaximumPointCount, 25)
        XCTAssertEqual(BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount, 20)
    }

    func testHealthTrendSeriesAveragesLongRangeChartBuckets() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let sixMonthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentSixMonths.dayCount - 1),
            to: currentDayStart
        ))
        let yearStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentYear.dayCount - 1),
            to: currentDayStart
        ))
        let sixMonthPoints = try (0..<12).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: sixMonthStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 1))
        }
        let yearPoints = try (0..<24).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: yearStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 1))
        }

        let sixMonthSeries = HealthTrendSeries(points: sixMonthPoints)
        let yearSeries = HealthTrendSeries(points: yearPoints)
        let sixMonthChartPoints = sixMonthSeries.chartCalendarPoints(
            to: .recentSixMonths,
            calendar: calendar,
            date: currentDate
        )
        let yearChartPoints = yearSeries.chartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(BodyHealthTrendRange.recentWeek.chartAggregationDayCount, 1)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.chartAggregationDayCount, 1)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.chartAggregationDayCount, 6)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.chartAggregationDayCount, 12)
        XCTAssertEqual(sixMonthChartPoints.count, 30)
        XCTAssertEqual(yearChartPoints.count, 30)
        XCTAssertEqual(sixMonthChartPoints.prefix(3).map(\.value), [3.5, 9.5, nil])
        XCTAssertEqual(yearChartPoints.prefix(3).map(\.value), [6.5, 18.5, nil])
        XCTAssertEqual(sixMonthChartPoints.first?.startDate, sixMonthStart)
        XCTAssertEqual(sixMonthChartPoints.first?.date, try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: sixMonthStart)))
        XCTAssertEqual(sixMonthChartPoints.first?.endDate, try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: sixMonthStart)))
        XCTAssertEqual(yearChartPoints.first?.startDate, yearStart)
        XCTAssertEqual(yearChartPoints.first?.date, try XCTUnwrap(calendar.date(byAdding: .day, value: 11, to: yearStart)))
        XCTAssertEqual(yearChartPoints.first?.endDate, try XCTUnwrap(calendar.date(byAdding: .day, value: 11, to: yearStart)))
        XCTAssertEqual(
            sixMonthSeries.chartSeries(to: .recentSixMonths, calendar: calendar, date: currentDate).points.map(\.value),
            [3.5, 9.5]
        )
        XCTAssertEqual(
            yearSeries.chartSeries(to: .recentYear, calendar: calendar, date: currentDate).points.map(\.value),
            [6.5, 18.5]
        )
    }

    func testAggregatedBarChartBucketsDropFinalPartialBucketAndUseBucketEndDates() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let yearStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentYear.dayCount - 1),
            to: currentDayStart
        ))
        let points = try (0..<BodyHealthTrendRange.recentYear.dayCount).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: yearStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 1))
        }

        let chartPoints = HealthTrendSeries(points: points).chartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: currentDate
        )
        let previousPoint = try XCTUnwrap(chartPoints.dropLast().last)
        let finalPoint = try XCTUnwrap(chartPoints.last)

        XCTAssertEqual(chartPoints.count, 30)
        XCTAssertEqual(finalPoint.date, finalPoint.endDate)
        XCTAssertEqual(finalPoint.date.timeIntervalSince(previousPoint.date), 12 * 24 * 60 * 60)
    }

    func testHeartRateRangeSeriesAggregatesDailyMinMaxBuckets() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let rangeStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentSixMonths.dayCount - 1),
            to: currentDayStart
        ))
        let day0 = rangeStart
        let day1 = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: rangeStart))
        let day6 = try XCTUnwrap(calendar.date(byAdding: .day, value: 6, to: rangeStart))
        let series = HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: day0, lowValue: 52, highValue: 118, averageValue: 72),
            HealthTrendRangeDataPoint(date: day1, lowValue: 48, highValue: 160, averageValue: 80),
            HealthTrendRangeDataPoint(date: day6, lowValue: 58, highValue: 140, averageValue: 90)
        ])

        let chartPoints = series.chartCalendarPoints(
            to: .recentSixMonths,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(chartPoints.count, 30)
        XCTAssertEqual(chartPoints[0].lowValue, 48)
        XCTAssertEqual(chartPoints[0].highValue, 160)
        XCTAssertEqual(chartPoints[0].averageValue, 76)
        XCTAssertEqual(chartPoints[0].startDate, day0)
        XCTAssertEqual(chartPoints[0].date, try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: rangeStart)))
        XCTAssertEqual(chartPoints[0].endDate, try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: rangeStart)))
        XCTAssertEqual(chartPoints[1].lowValue, 58)
        XCTAssertEqual(chartPoints[1].highValue, 140)
        XCTAssertEqual(chartPoints[1].averageValue, 90)
        XCTAssertNil(chartPoints.last?.lowValue)
    }

    func testAggregatedRangeChartBucketsDropFinalPartialBucketAndUseBucketEndDates() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let yearStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentYear.dayCount - 1),
            to: currentDayStart
        ))
        let points = try (0..<BodyHealthTrendRange.recentYear.dayCount).map { offset -> HealthTrendRangeDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: yearStart))
            return HealthTrendRangeDataPoint(
                date: date,
                lowValue: Double(offset + 1),
                highValue: Double(offset + 10),
                averageValue: Double(offset + 5)
            )
        }

        let chartPoints = HealthTrendRangeSeries(points: points).chartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: currentDate
        )
        let previousPoint = try XCTUnwrap(chartPoints.dropLast().last)
        let finalPoint = try XCTUnwrap(chartPoints.last)

        XCTAssertEqual(chartPoints.count, 30)
        XCTAssertEqual(finalPoint.date, finalPoint.endDate)
        XCTAssertEqual(finalPoint.date.timeIntervalSince(previousPoint.date), 12 * 24 * 60 * 60)
    }

    func testRangeChartYDomainRoundsRespiratoryBoundsToFiveStepEdges() {
        let domain = BodyHealthMetricRangeYDomain.respiratoryRate(from: [12.2, 18.1])
        XCTAssertEqual(domain.lowerBound, 10)
        XCTAssertEqual(domain.upperBound, 20)

        let exactLowerDomain = BodyHealthMetricRangeYDomain.respiratoryRate(from: [15, 23])
        XCTAssertEqual(exactLowerDomain.lowerBound, 10)
        XCTAssertEqual(exactLowerDomain.upperBound, 25)
    }

    func testRangeChartYDomainKeepsBloodOxygenMinimumUpperBound() {
        let domain = BodyHealthMetricRangeYDomain.bloodOxygen(from: [86, 99])
        XCTAssertEqual(domain.lowerBound, 85)
        XCTAssertEqual(domain.upperBound, 100)

        let elevatedDomain = BodyHealthMetricRangeYDomain.bloodOxygen(from: [91, 101.2])
        XCTAssertEqual(elevatedDomain.lowerBound, 90)
        XCTAssertEqual(elevatedDomain.upperBound, 105)
    }

    func testHealthTrendSeriesCompressesMonthLineChartToTwentyFiveStablePointsByDefault() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let monthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentMonth.dayCount - 1),
            to: currentDayStart
        ))
        let points = try (0..<BodyHealthTrendRange.recentMonth.dayCount).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monthStart))
            let value: Double
            switch offset {
            case 10:
                value = 120
            case 20:
                value = 80
            default:
                value = 100
            }
            return HealthTrendDataPoint(date: date, value: value)
        }
        let series = HealthTrendSeries(points: points)

        let standardChartPoints = series.chartCalendarPoints(
            to: .recentMonth,
            calendar: calendar,
            date: currentDate
        )
        let lineChartPoints = series.lineChartCalendarPoints(
            to: .recentMonth,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(standardChartPoints.count, BodyHealthTrendRange.recentMonth.dayCount)
        XCTAssertEqual(lineChartPoints.count, 25)
        XCTAssertEqual(lineChartPoints.compactMap(\.value).count, 25)

        let highChangeDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 10, to: monthStart))
        let lowChangeDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 20, to: monthStart))
        let highChangePoint = try XCTUnwrap(lineChartPoints.first { $0.value == 120 })
        let lowChangePoint = try XCTUnwrap(lineChartPoints.first { $0.value == 80 })
        XCTAssertEqual(highChangePoint.date, highChangeDate)
        XCTAssertEqual(lowChangePoint.date, lowChangeDate)
        XCTAssertFalse(highChangePoint.representsDateRange)
        XCTAssertFalse(lowChangePoint.representsDateRange)

        let compressedStablePoint = try XCTUnwrap(lineChartPoints.first { point in
            point.representsDateRange && abs((point.value ?? 0) - 100) < 0.001
        })
        XCTAssertLessThan(compressedStablePoint.startDate, compressedStablePoint.endDate)
    }

    func testHealthTrendSeriesCanUseBodyFatWeightTwentyPointLineChartCap() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 30, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let monthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentMonth.dayCount - 1),
            to: currentDayStart
        ))
        let points = try (0..<BodyHealthTrendRange.recentMonth.dayCount).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monthStart))
            return HealthTrendDataPoint(date: date, value: 100)
        }
        let series = HealthTrendSeries(points: points)

        let lineChartPoints = series.lineChartCalendarPoints(
            to: .recentMonth,
            calendar: calendar,
            date: currentDate,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )

        XCTAssertEqual(lineChartPoints.count, 20)
        XCTAssertEqual(lineChartPoints.compactMap(\.value).count, 20)
    }

    func testHealthTrendSeriesCompressesSixMonthAndYearLineChartsToTwentyFivePoints() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let sixMonthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentSixMonths.dayCount - 1),
            to: currentDayStart
        ))
        let yearStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentYear.dayCount - 1),
            to: currentDayStart
        ))
        let sixMonthPoints = try (0..<BodyHealthTrendRange.recentSixMonths.dayCount).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: sixMonthStart))
            return HealthTrendDataPoint(date: date, value: offset == 60 ? 120 : 100)
        }
        let yearPoints = try (0..<BodyHealthTrendRange.recentYear.dayCount).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: yearStart))
            return HealthTrendDataPoint(date: date, value: offset == 120 ? 80 : 100)
        }
        let sixMonthSeries = HealthTrendSeries(points: sixMonthPoints)
        let yearSeries = HealthTrendSeries(points: yearPoints)

        let sixMonthLineChartPoints = sixMonthSeries.lineChartCalendarPoints(
            to: .recentSixMonths,
            calendar: calendar,
            date: currentDate
        )
        let yearLineChartPoints = yearSeries.lineChartCalendarPoints(
            to: .recentYear,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(sixMonthSeries.chartCalendarPoints(to: .recentSixMonths, calendar: calendar, date: currentDate).count, 30)
        XCTAssertEqual(yearSeries.chartCalendarPoints(to: .recentYear, calendar: calendar, date: currentDate).count, 30)
        XCTAssertEqual(sixMonthLineChartPoints.count, 25)
        XCTAssertEqual(yearLineChartPoints.count, 25)
        XCTAssertNotNil(sixMonthLineChartPoints.first { point in
            abs((point.value ?? 0) - (620.0 / 6.0)) < 0.001
        })
        XCTAssertNotNil(yearLineChartPoints.first { point in
            abs((point.value ?? 0) - (1_180.0 / 12.0)) < 0.001
        })
    }

    func testHomeMetricCardPreviewUsesOnlyRecentFourDayPoints() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try [-10, -7, -6, -2, 0].map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 20))
        }
        let series = HealthTrendSeries(points: points)

        let previewPoints = BodyHomeMetricCardPreview.points(
            from: series,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(BodyHomeMetricCardPreview.previewDayCount, 4)
        XCTAssertEqual(previewPoints.map(\.value), [18, 20])
    }

    func testHomeMetricCardPreviewUsesCompactCountOnSmallScreens() {
        XCTAssertEqual(BodyHomeMetricCardPreview.compactPreviewDayCount, 3)
        XCTAssertEqual(BodyHomeMetricCardPreview.dayCount(forScreenWidth: 375), 3)
        XCTAssertEqual(BodyHomeMetricCardPreview.dayCount(forScreenWidth: 390), 4)
        XCTAssertEqual(BodyHomeMetricCardPreview.dayCount(forScreenWidth: Double.nan), 4)
    }

    func testHomeMetricCardPreviewCalendarPointsIncludeTodayWhenTodayHasData() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try [-10, -6, -2, 0].map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 20))
        }
        let series = HealthTrendSeries(points: points)

        let previewPoints = BodyHomeMetricCardPreview.calendarPoints(
            from: series,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(previewPoints.map(\.value), [nil, 18, nil, 20])
    }

    func testHomeMetricCardPreviewCalendarPointsCanUseCompactThreeDayWindow() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try [-10, -6, -2, 0].map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 20))
        }
        let series = HealthTrendSeries(points: points)

        let previewPoints = BodyHomeMetricCardPreview.calendarPoints(
            from: series,
            previewDayCount: BodyHomeMetricCardPreview.compactPreviewDayCount,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(previewPoints.map(\.value), [18, nil, 20])
    }

    func testHomeMetricCardPreviewCalendarPointsOmitTodayPlaceholderWhenTodayHasNoData() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try [-6, -2].map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            return HealthTrendDataPoint(date: date, value: Double(offset + 20))
        }
        let series = HealthTrendSeries(points: points)

        let previewPoints = BodyHomeMetricCardPreview.calendarPoints(
            from: series,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(previewPoints.map(\.value), [nil, nil, 18, nil])
        XCTAssertEqual(previewPoints.last?.date, try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: currentDayStart)))
    }

    func testHomeMetricCardRangePreviewCalendarPointsUseRecentFourDayRanges() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let may11 = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: currentDayStart))
        let may13 = currentDayStart
        let series = HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: may11, lowValue: 52, highValue: 118, averageValue: 78),
            HealthTrendRangeDataPoint(date: may13, lowValue: 58, highValue: 132, averageValue: 88)
        ])

        let previewPoints = BodyHomeMetricCardPreview.rangeCalendarPoints(
            from: series,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(previewPoints.map(\.lowValue), [nil, 52, nil, 58])
        XCTAssertEqual(previewPoints.map(\.highValue), [nil, 118, nil, 132])
        XCTAssertEqual(previewPoints.last?.date, may13)
    }

    func testHomeMetricCardRangePreviewCalendarPointsCanUseCompactThreeDayWindow() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 13, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let may11 = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: currentDayStart))
        let may13 = currentDayStart
        let series = HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: may11, lowValue: 52, highValue: 118, averageValue: 78),
            HealthTrendRangeDataPoint(date: may13, lowValue: 58, highValue: 132, averageValue: 88)
        ])

        let previewPoints = BodyHomeMetricCardPreview.rangeCalendarPoints(
            from: series,
            previewDayCount: BodyHomeMetricCardPreview.compactPreviewDayCount,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(previewPoints.map(\.lowValue), [52, nil, 58])
        XCTAssertEqual(previewPoints.map(\.highValue), [118, nil, 132])
        XCTAssertEqual(previewPoints.last?.date, may13)
    }

    func testHealthTrendSeriesBuildsDailyCalendarPlaceholdersForMissingDates() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let may7 = try XCTUnwrap(calendar.date(byAdding: .day, value: -4, to: currentDayStart))
        let may10 = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: currentDayStart))
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: may7.addingTimeInterval(9 * 60 * 60), value: 10),
            HealthTrendDataPoint(date: may10.addingTimeInterval(9 * 60 * 60), value: 20)
        ])

        let calendarPoints = series.calendarPoints(
            to: .recentWeek,
            calendar: calendar,
            date: currentDate
        )

        XCTAssertEqual(calendarPoints.count, 7)
        XCTAssertEqual(calendarPoints.map(\.value), [nil, nil, 10, nil, nil, 20, nil])
        XCTAssertEqual(calendarPoints.map(\.hasValue), [false, false, true, false, false, true, false])
        XCTAssertEqual(calendarPoints.first?.date, try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: currentDayStart)))
        XCTAssertEqual(calendarPoints.last?.date, currentDayStart)
    }

    func testHomeMetricCardPreviewStyleMatchesDetailChartStyle() {
        XCTAssertEqual(BodyHomeMetricCardPreview.Style.matching(chartStyle: .line), .line)
        XCTAssertEqual(BodyHomeMetricCardPreview.Style.matching(chartStyle: .bar), .bar)
        XCTAssertEqual(BodyHomeMetricCardPreview.Style.range, .range)
    }

    func testHomeMetricCardPreviewLineDotsUseCompactSizes() {
        XCTAssertEqual(BodyHomeMetricCardPreview.linePointDiameter, 6, accuracy: 0.001)
        XCTAssertEqual(BodyHomeMetricCardPreview.lineCurrentPointDiameter, 7, accuracy: 0.001)
    }

    func testHomeMetricCardPreviewWidthsUseSharedCompactSize() {
        XCTAssertEqual(BodyHomeMetricCardPreview.linePreviewWidth, 42, accuracy: 0.001)
        XCTAssertEqual(BodyHomeMetricCardPreview.barPreviewWidth, 42, accuracy: 0.001)
        XCTAssertEqual(BodyHomeMetricCardPreview.linePreviewWidth, BodyHomeMetricCardPreview.barPreviewWidth)
    }

    func testHomeTrendCardPresentationComparesRecentWeekAgainstPriorThreeWeeks() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try (-27...0).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            let value = offset < -6 ? 70.0 : 56.0
            return HealthTrendDataPoint(date: date, value: value)
        }

        let presentation = try XCTUnwrap(BodyHomeTrendCardPresentation.make(
            kind: .restingHeartRate,
            title: "Resting Heart Rate",
            series: HealthTrendSeries(points: points),
            chartStyle: .line,
            valueFormatter: { "\(Int($0.rounded())) BPM" },
            messageStyle: .average(subject: "your resting heart rate"),
            calendar: calendar,
            date: currentDate
        ))

        XCTAssertEqual(presentation.messageText, "On average, your resting heart rate decreased over the last 7 days.")
        XCTAssertEqual(presentation.baselineAverage, 70, accuracy: 0.001)
        XCTAssertEqual(presentation.recentAverage, 56, accuracy: 0.001)
        XCTAssertEqual(presentation.baselineAverageText, "70 BPM")
        XCTAssertEqual(presentation.recentAverageText, "56 BPM")
        XCTAssertEqual(presentation.baselinePeriodText, "21-day avg")
        XCTAssertEqual(presentation.recentPeriodText, "7-day avg")
        XCTAssertEqual(presentation.calendarPoints.count, 28)

        let averageLineSegments = presentation.averageLineSegments(in: 270)
        XCTAssertEqual(averageLineSegments.baseline.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.baseline.upperBound, 203, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.lowerBound, 207, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.upperBound, 270, accuracy: 0.001)
    }

    func testHomeTrendCardPresentationCanDetectLongerRecentTrendWindow() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try (-27...0).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            let value = offset < -22 ? 9_000.0 : 5_000.0
            return HealthTrendDataPoint(date: date, value: value)
        }

        let presentation = try XCTUnwrap(BodyHomeTrendCardPresentation.make(
            kind: .steps,
            title: "Steps",
            series: HealthTrendSeries(points: points),
            chartStyle: .bar,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
            messageStyle: .quantity(subject: "The number of steps you took per day"),
            calendar: calendar,
            date: currentDate
        ))

        XCTAssertEqual(presentation.messageText, "The number of steps you took per day was lower over the last 23 days.")
        XCTAssertEqual(presentation.baselineAverage, 9_000, accuracy: 0.001)
        XCTAssertEqual(presentation.recentAverage, 5_000, accuracy: 0.001)
        XCTAssertEqual(presentation.baselinePeriodText, "5-day avg")
        XCTAssertEqual(presentation.recentPeriodText, "23-day avg")

        let averageLineSegments = presentation.averageLineSegments(in: 270)
        XCTAssertEqual(averageLineSegments.baseline.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.baseline.upperBound, 43, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.lowerBound, 47, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.upperBound, 270, accuracy: 0.001)
    }

    func testHomeTrendBarLayoutFitsLongTrendInsideAvailableWidth() {
        let availableWidth: CGFloat = 320
        let barCount = BodyHomeTrendCardPresentation.maximumDisplayPointCount

        let layout = BodyHomeTrendBarLayout.fitting(barCount: barCount, availableWidth: availableWidth)
        let usedWidth = CGFloat(barCount) * layout.barWidth + CGFloat(barCount - 1) * layout.spacing

        XCTAssertLessThanOrEqual(usedWidth, availableWidth + 0.001)
        XCTAssertEqual(layout.barWidth, 3, accuracy: 0.001)
        XCTAssertLessThan(layout.spacing, 5)
    }

    func testHeartRateActivityAveragesUseSelectedDaySleepAndWorkoutIntervals() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28)))
        let sleepStart = day.addingTimeInterval(60 * 60)
        let sleepEnd = day.addingTimeInterval(3 * 60 * 60)
        let runStart = day.addingTimeInterval(7 * 60 * 60)
        let runEnd = day.addingTimeInterval(8 * 60 * 60)
        let strengthStart = day.addingTimeInterval(20 * 60 * 60)

        let sleep = SleepSummary(
            duration: sleepEnd.timeIntervalSince(sleepStart),
            stageSnapshot: SleepStageSnapshot(
                date: day,
                segments: [
                    SleepStageSegment(stage: .core, startDate: sleepStart, endDate: sleepEnd)
                ]
            )
        )
        let heartRateSeries = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: sleepStart.addingTimeInterval(15 * 60), value: 50),
            HealthTrendDataPoint(date: sleepStart.addingTimeInterval(45 * 60), value: 60),
            HealthTrendDataPoint(date: runStart.addingTimeInterval(10 * 60), value: 140),
            HealthTrendDataPoint(date: runStart.addingTimeInterval(40 * 60), value: 160),
            HealthTrendDataPoint(date: day.addingTimeInterval(12 * 60 * 60), value: 80)
        ])
        let workouts = [
            WorkoutSummary(
                type: .running,
                startDate: runStart,
                duration: runEnd.timeIntervalSince(runStart)
            ),
            WorkoutSummary(
                type: .strengthTraining,
                startDate: strengthStart,
                duration: 45 * 60,
                averageHeartRateBeatsPerMinute: 112
            )
        ]

        let rows = BodyMetricActivityAverages.makeHeartRate(
            day: day,
            heartRateSeries: heartRateSeries,
            sleepSummary: sleep,
            workouts: workouts,
            calendar: calendar
        )

        XCTAssertEqual(rows.map(\.title), ["Sleep", "Run", "Strength"])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].averageValue, 55, accuracy: 0.001)
        XCTAssertEqual(rows[1].averageValue, 150, accuracy: 0.001)
        XCTAssertEqual(rows[2].averageValue, 112, accuracy: 0.001)
        XCTAssertEqual(rows.map(\.activity), [.sleep, .workout(.running), .workout(.strengthTraining)])
        XCTAssertEqual(rows.map(\.startDate), [sleepStart, runStart, strengthStart])
    }

    func testHeartRateVariabilityActivityAveragesOnlyUseSelectedDaySleepInterval() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28)))
        let sleepStart = day.addingTimeInterval(60 * 60)
        let sleepEnd = day.addingTimeInterval(3 * 60 * 60)
        let workoutStart = day.addingTimeInterval(8 * 60 * 60)
        let sleep = SleepSummary(
            duration: sleepEnd.timeIntervalSince(sleepStart),
            stageSnapshot: SleepStageSnapshot(
                date: day,
                segments: [
                    SleepStageSegment(stage: .core, startDate: sleepStart, endDate: sleepEnd)
                ]
            ),
            vitals: SleepVitalsSummary(heartRateVariability: 44)
        )
        let hrvSeries = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: sleepStart.addingTimeInterval(10 * 60), value: 60),
            HealthTrendDataPoint(date: sleepStart.addingTimeInterval(30 * 60), value: 80),
            HealthTrendDataPoint(date: workoutStart.addingTimeInterval(10 * 60), value: 20)
        ])

        let rows = BodyMetricActivityAverages.makeSleepOnly(
            day: day,
            series: hrvSeries,
            sleepSummary: sleep,
            fallbackValue: sleep.vitals.heartRateVariability,
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].title, "Sleep")
        XCTAssertEqual(rows[0].activity, .sleep)
        XCTAssertEqual(rows[0].averageValue, 70, accuracy: 0.001)
        XCTAssertEqual(rows[0].startDate, sleepStart)
        XCTAssertEqual(rows[0].endDate, sleepEnd)
    }

    func testMetricDayContextBandTopStripeUsesFixedRelativeThickness() {
        let narrowDomain = 45.0...47.0
        let wideDomain = 0.0...300.0

        let narrowLowerBound = BodyHealthMetricDayContextBand.topStripeLowerBound(for: narrowDomain)
        let wideLowerBound = BodyHealthMetricDayContextBand.topStripeLowerBound(for: wideDomain)
        let narrowFraction = (narrowDomain.upperBound - narrowLowerBound) / (narrowDomain.upperBound - narrowDomain.lowerBound)
        let wideFraction = (wideDomain.upperBound - wideLowerBound) / (wideDomain.upperBound - wideDomain.lowerBound)

        XCTAssertEqual(narrowFraction, BodyHealthMetricDayContextBand.topStripeHeightRatio, accuracy: 0.0001)
        XCTAssertEqual(wideFraction, BodyHealthMetricDayContextBand.topStripeHeightRatio, accuracy: 0.0001)
        XCTAssertEqual(narrowFraction, wideFraction, accuracy: 0.0001)
    }

    func testHomeTrendCardPresentationKeepsAtLeastThreeDaysInEachTrendWindow() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try (-27...0).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            let value = offset > -3 ? 200.0 : 100.0
            return HealthTrendDataPoint(date: date, value: value)
        }

        let presentation = try XCTUnwrap(BodyHomeTrendCardPresentation.make(
            kind: .heartRateVariability,
            title: "HRV",
            series: HealthTrendSeries(points: points),
            chartStyle: .line,
            valueFormatter: { "\(Int($0.rounded())) ms" },
            messageStyle: .average(subject: "your HRV"),
            calendar: calendar,
            date: currentDate
        ))

        XCTAssertEqual(BodyHomeTrendCardPresentation.minimumTrendSegmentDayCount, 3)
        XCTAssertEqual(presentation.messageText, "On average, your HRV increased over the last 3 days.")
        XCTAssertEqual(presentation.baselinePeriodText, "25-day avg")
        XCTAssertEqual(presentation.recentPeriodText, "3-day avg")

        let averageLineSegments = presentation.averageLineSegments(in: 270)
        XCTAssertEqual(averageLineSegments.baseline.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.baseline.upperBound, 243, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.lowerBound, 247, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.upperBound, 270, accuracy: 0.001)
    }

    func testHomeTrendCardPresentationRequiresBaselineAndRecentHistory() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try (-6...0).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            return HealthTrendDataPoint(date: date, value: 56)
        }

        XCTAssertNil(BodyHomeTrendCardPresentation.make(
            kind: .steps,
            title: "Steps",
            series: HealthTrendSeries(points: points),
            chartStyle: .bar,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
            messageStyle: .quantity(subject: "The number of steps you took per day"),
            calendar: calendar,
            date: currentDate
        ))
    }

    func testHomeTrendCardPresentationCanIncludeStableTrendsForShowAll() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 28, hour: 12)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let points = try (-27...0).map { offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: currentDayStart))
            let value = offset < -6 ? 100.0 : 100.5
            return HealthTrendDataPoint(date: date, value: value)
        }

        let significantOnly = BodyHomeTrendCardPresentation.make(
            kind: .steps,
            title: "Steps",
            series: HealthTrendSeries(points: points),
            chartStyle: .bar,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
            messageStyle: .quantity(subject: "The number of steps you took per day"),
            calendar: calendar,
            date: currentDate
        )
        let showAllPresentation = try XCTUnwrap(BodyHomeTrendCardPresentation.make(
            kind: .steps,
            title: "Steps",
            series: HealthTrendSeries(points: points),
            chartStyle: .bar,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
            messageStyle: .quantity(subject: "The number of steps you took per day"),
            includesStable: true,
            calendar: calendar,
            date: currentDate
        ))

        XCTAssertNil(significantOnly)
        XCTAssertEqual(BodyHomeTrendCardPresentation.minimumRelativeChange, 0.01, accuracy: 0.001)
        XCTAssertEqual(showAllPresentation.messageText, "The number of steps you took per day stayed about the same over the last 7 days.")
    }

    func testHealthPermissionSelectionStoresEnabledPermissionsInDisplayOrder() {
        let selection = BodyHealthPermissionSelection(enabledPermissions: [.steps, .sleep, .wristTemperature])

        XCTAssertEqual(selection.rawValue, "sleep,wristTemperature,steps")
        XCTAssertTrue(selection.includes(.sleep))
        XCTAssertFalse(selection.includes(.heart))
        XCTAssertEqual(selection.setting(.heart, isEnabled: true).rawValue, "sleep,heart,wristTemperature,steps")
        XCTAssertEqual(selection.setting(.sleep, isEnabled: false).rawValue, "wristTemperature,steps")
        XCTAssertEqual(BodyHealthPermissionSelection.storedValue(from: "none").enabledPermissions, [])
        XCTAssertEqual(
            BodyHealthPermissionSelection.storedValue(from: "sleep,unknown,steps").enabledPermissions,
            [.sleep, .steps]
        )
        XCTAssertEqual(
            BodyHealthPermissionSelection.storedValue(from: "").enabledPermissions,
            BodyHealthPermissionSelection.defaultValue.enabledPermissions
        )
    }

    func testHealthDashboardSnapshotsFilterDisabledPermissions() {
        let date = Date(timeIntervalSince1970: 0)
        let selection = BodyHealthPermissionSelection(enabledPermissions: [.steps, .wristTemperature])
        let summary = HealthSummarySnapshot(
            activityRings: ActivityRingSummary(
                move: ActivityRingMetric(value: 100, goal: 500),
                exercise: ActivityRingMetric(value: 15, goal: 30),
                stand: ActivityRingMetric(value: 5, goal: 12)
            ),
            sleep: SleepSummary(
                duration: 7 * 60 * 60,
                vitals: SleepVitalsSummary(
                    heartRate: 58,
                    heartRateVariability: 40,
                    respiratoryRate: 14,
                    oxygenSaturation: 97,
                    wristTemperatureCelsius: 36.4
                )
            ),
            heartRate: HealthMetricSummary(value: 82),
            restingHeartRate: HealthMetricSummary(value: 61),
            bodyMass: HealthMetricSummary(value: 69.2),
            bodyFatPercentage: HealthMetricSummary(value: 13.1),
            heartRateVariability: HealthMetricSummary(value: 40),
            respiratoryRate: HealthMetricSummary(value: 14),
            oxygenSaturation: HealthMetricSummary(value: 97),
            bodyMassIndex: HealthMetricSummary(value: 22.1),
            activeEnergy: HealthMetricSummary(value: 520),
            restingEnergy: HealthMetricSummary(value: 1_700),
            exerciseMinutes: HealthMetricSummary(value: 32),
            trainingLoad: HealthMetricSummary(value: 1.08),
            wristTemperature: HealthMetricSummary(value: 36.4),
            timeInDaylight: HealthMetricSummary(value: 20),
            steps: HealthMetricSummary(value: 4_200)
        )
        let trends = HealthTrendSnapshot(
            sleep: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 7)]),
            heartRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 82)]),
            heartRateRanges: HealthTrendRangeSeries(points: [
                HealthTrendRangeDataPoint(date: date, lowValue: 52, highValue: 126, averageValue: 82)
            ]),
            restingHeartRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 61)]),
            bodyMass: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 69.2)]),
            bodyFatPercentage: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 13.1)]),
            heartRateVariability: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 40)]),
            heartRateVariabilityRanges: HealthTrendRangeSeries(points: [
                HealthTrendRangeDataPoint(date: date, lowValue: 28, highValue: 58, averageValue: 40)
            ]),
            respiratoryRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 14)]),
            respiratoryRateRanges: HealthTrendRangeSeries(points: [
                HealthTrendRangeDataPoint(date: date, lowValue: 12, highValue: 18, averageValue: 14)
            ]),
            oxygenSaturation: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 97)]),
            oxygenSaturationRanges: HealthTrendRangeSeries(points: [
                HealthTrendRangeDataPoint(date: date, lowValue: 94, highValue: 99, averageValue: 97)
            ]),
            bodyMassIndex: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 22.1)]),
            activeEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 520)]),
            restingEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 1_700)]),
            exerciseMinutes: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 32)]),
            trainingLoad: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 1.08)]),
            wristTemperature: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 36.4)]),
            timeInDaylight: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 20)]),
            steps: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 4_200)]),
            sleepHistory: SleepHistorySnapshot(days: [SleepDaySummary(date: date, summary: summary.sleep)])
        )

        let filteredSummary = summary.filtered(by: selection)
        let filteredTrends = trends.filtered(by: selection)

        XCTAssertTrue(filteredSummary.activityRings.isEmpty)
        XCTAssertNil(filteredSummary.sleep.duration)
        XCTAssertNil(filteredSummary.heartRate.value)
        XCTAssertNil(filteredSummary.restingHeartRate.value)
        XCTAssertNil(filteredSummary.bodyMass.value)
        XCTAssertNil(filteredSummary.exerciseMinutes.value)
        XCTAssertNil(filteredSummary.trainingLoad.value)
        XCTAssertEqual(filteredSummary.wristTemperature.value, 36.4)
        XCTAssertEqual(filteredSummary.steps.value, 4_200)
        XCTAssertTrue(filteredTrends.sleep.isEmpty)
        XCTAssertTrue(filteredTrends.heartRate.isEmpty)
        XCTAssertTrue(filteredTrends.heartRateRanges.isEmpty)
        XCTAssertEqual(trends.rangeSeries(for: .heartRateVariability).points.first?.highValue, 58)
        XCTAssertTrue(filteredTrends.heartRateVariabilityRanges.isEmpty)
        XCTAssertEqual(trends.rangeSeries(for: .oxygenSaturation).points.first?.lowValue, 94)
        XCTAssertTrue(filteredTrends.oxygenSaturationRanges.isEmpty)
        XCTAssertEqual(trends.rangeSeries(for: .respiratoryRate).points.first?.highValue, 18)
        XCTAssertTrue(filteredTrends.respiratoryRateRanges.isEmpty)
        XCTAssertTrue(filteredTrends.bodyMass.isEmpty)
        XCTAssertTrue(filteredTrends.exerciseMinutes.isEmpty)
        XCTAssertTrue(filteredTrends.trainingLoad.isEmpty)
        XCTAssertEqual(filteredTrends.wristTemperature.points.first?.value, 36.4)
        XCTAssertEqual(filteredTrends.steps.points.first?.value, 4_200)
    }

    func testHomeCardOrderRepairsStoredValues() {
        let order = BodyHomeCardKind.storedOrder(from: "sleep,sleep,activeEnergy,unknown")
        let migratedOrder = BodyHomeCardKind.storedOrder(from: "activityRings,exerciseMinutes,workoutDuration,timeInDaylight")

        XCTAssertEqual(Array(order.prefix(2)), [.sleep, .activeEnergy])
        XCTAssertEqual(Array(migratedOrder.prefix(5)), [
            .activityRings,
            .exerciseMinutes,
            .wristTemperature,
            .timeInDaylight,
            .sleep
        ])
        XCTAssertEqual(Set(order), Set(BodyHomeCardKind.defaultOrder))
        XCTAssertEqual(order.count, BodyHomeCardKind.defaultOrder.count)
        XCTAssertTrue(order.contains(.activityRings))
        XCTAssertTrue(order.contains(.exerciseMinutes))
        XCTAssertTrue(order.contains(.trainingLoad))
        XCTAssertTrue(order.contains(.wristTemperature))
        XCTAssertTrue(order.contains(.timeInDaylight))
        XCTAssertTrue(order.contains(.steps))
        XCTAssertTrue(order.contains(.heartRate))
        XCTAssertEqual(
            Array(BodyHomeCardKind.defaultOrder.prefix(6)),
            [.activityRings, .sleep, .basics, .heartRate, .heartRateVariability, .trainingLoad]
        )
        XCTAssertLessThan(
            BodyHomeCardKind.defaultOrder.firstIndex(of: .heartRate) ?? .max,
            BodyHomeCardKind.defaultOrder.firstIndex(of: .restingHeartRate) ?? .max
        )
    }

    func testHomeCardOrderMovesCardsToDropDestination() {
        let order = BodyHomeCardKind.defaultOrder

        let movedDown = BodyHomeCardKind.reordered(order, moving: .sleep, to: .basics)
        XCTAssertEqual(
            Array(movedDown.prefix(9)),
            [.activityRings, .basics, .sleep, .heartRate, .heartRateVariability, .trainingLoad, .readiness, .activeEnergy, .restingEnergy]
        )
        XCTAssertEqual(Set(movedDown), Set(order))
        XCTAssertEqual(movedDown.count, order.count)

        let movedUp = BodyHomeCardKind.reordered(order, moving: .activeEnergy, to: .sleep)
        XCTAssertEqual(
            Array(movedUp.prefix(9)),
            [.activityRings, .activeEnergy, .sleep, .basics, .heartRate, .heartRateVariability, .trainingLoad, .readiness, .restingEnergy]
        )
        XCTAssertEqual(Set(movedUp), Set(order))
        XCTAssertEqual(movedUp.count, order.count)
    }

    func testHomeCardLayoutRowsTreatActivityRingsAsTwoSlots() {
        let defaultRows = BodyHomeCardKind.layoutRows(from: [.activityRings, .sleep, .basics])

        XCTAssertEqual(defaultRows[0].cards, [.activityRings])
        XCTAssertEqual(defaultRows[0].slotCount, 2)
        XCTAssertEqual(defaultRows[1].cards, [.sleep, .basics])

        let reorderedRows = BodyHomeCardKind.layoutRows(from: [.sleep, .activityRings, .basics])
        XCTAssertEqual(reorderedRows[0].cards, [.sleep])
        XCTAssertEqual(reorderedRows[0].slotCount, 1)
        XCTAssertEqual(reorderedRows[1].cards, [.activityRings])
        XCTAssertEqual(reorderedRows[1].slotCount, 2)
    }

    func testSummaryCardSelectionStoresVisibleCardsWithoutChangingOrder() {
        let selection = BodySummaryCardSelection(selectedCards: [.activityRings, .sleep, .heartRate])

        XCTAssertEqual(selection.rawValue, "activityRings,sleep,heartRate")
        XCTAssertEqual(selection.enabledCount, 3)
        XCTAssertTrue(selection.includes(.activityRings))
        XCTAssertTrue(selection.includes(.sleep))
        XCTAssertFalse(selection.includes(.steps))
        XCTAssertEqual(
            selection.setting(.steps, isEnabled: true).rawValue,
            "activityRings,sleep,heartRate,steps"
        )
        XCTAssertEqual(
            selection.setting(.sleep, isEnabled: false).rawValue,
            "activityRings,heartRate"
        )

        XCTAssertEqual(
            BodySummaryCardSelection.storedValue(from: "activityRings,unknown,steps").rawValue,
            "activityRings,steps"
        )
        XCTAssertEqual(
            BodySummaryCardSelection.storedValue(from: "").rawValue,
            BodySummaryCardSelection.defaultRawValue
        )
        XCTAssertEqual(
            BodySummaryCardSelection.storedValue(from: "none").enabledCount,
            0
        )
    }

    func testHomeCardLayoutRowsCanHideSummaryCards() {
        let selection = BodySummaryCardSelection(selectedCards: [.activityRings, .sleep, .heartRate, .steps])
        let rows = BodyHomeCardKind.layoutRows(
            from: [.sleep, .activityRings, .steps, .heartRate],
            visibleIn: selection
        )

        XCTAssertEqual(rows.map(\.cards), [
            [.sleep],
            [.activityRings],
            [.steps, .heartRate]
        ])
    }

    func testHomeTrendCardSelectionStoresVisibleTrendsInDefaultOrder() {
        let selection = BodyHomeTrendCardSelection(selectedCards: [.steps, .heartRate, .sleep])

        XCTAssertEqual(BodyAppearancePreference.homeTrendCardSelectionKey, "homeTrendCardSelection")
        XCTAssertEqual(
            BodyHomeTrendCardKind.defaultOrder.map(\.metricKind),
            [
                .readiness,
                .heartRate,
                .restingHeartRate,
                .heartRateVariability,
                .respiratoryRate,
                .oxygenSaturation,
                .sleep,
                .wristTemperature,
                .steps,
                .activeEnergy,
                .restingEnergy,
                .exerciseMinutes,
                .trainingLoad,
                .timeInDaylight
            ]
        )
        XCTAssertEqual(selection.rawValue, "heartRate,sleep,steps")
        XCTAssertEqual(selection.enabledCount, 3)
        XCTAssertTrue(selection.includes(BodyHomeTrendCardKind.heartRate))
        XCTAssertTrue(selection.includes(BodyHomeTrendCardKind.steps))
        XCTAssertFalse(selection.includes(BodyHomeTrendCardKind.restingEnergy))
        XCTAssertEqual(
            selection.setting(BodyHomeTrendCardKind.restingEnergy, isEnabled: true).rawValue,
            "heartRate,sleep,steps,restingEnergy"
        )
        XCTAssertEqual(
            selection.setting(.sleep, isEnabled: false).rawValue,
            "heartRate,steps"
        )
        XCTAssertEqual(
            BodyHomeTrendCardSelection.storedValue(from: "heartRate,unknown,steps").rawValue,
            "heartRate,steps"
        )
        XCTAssertEqual(
            BodyHomeTrendCardSelection.storedValue(from: "").rawValue,
            BodyHomeTrendCardSelection.defaultRawValue
        )
        XCTAssertEqual(
            BodyHomeTrendCardSelection.storedValue(from: "none").enabledCount,
            0
        )
    }

    func testDashboardFetchSelectionIncludesVisibleSummaryAndTrendCards() {
        let selection = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: [.activityRings, .steps]),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [.sleep])
        )

        XCTAssertTrue(selection.includesActivityRings)
        XCTAssertTrue(selection.includes(.steps))
        XCTAssertTrue(selection.includes(.sleep))
        XCTAssertFalse(selection.includes(.heartRate))
        XCTAssertFalse(selection.includes(.activeEnergy))
    }

    func testDashboardFetchSelectionKeepsReadinessDependencies() {
        let selection = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: []),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [.readiness])
        )

        XCTAssertFalse(selection.includesActivityRings)
        XCTAssertTrue(selection.includes(.readiness))
        XCTAssertTrue(selection.includes(.sleep))
        XCTAssertTrue(selection.includes(.heartRateVariability))
        XCTAssertTrue(selection.includes(.restingHeartRate))
        XCTAssertTrue(selection.includes(.trainingLoad))
        XCTAssertTrue(selection.includes(.respiratoryRate))
        XCTAssertTrue(selection.includes(.oxygenSaturation))
        XCTAssertTrue(selection.includes(.wristTemperature))
        XCTAssertFalse(selection.includes(.heartRate))
        XCTAssertFalse(selection.includes(.steps))
    }

    func testHealthTrendSeriesLimitsToAvailableRanges() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let points = try (-399...0).enumerated().map { index, offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: currentDate)))
            return HealthTrendDataPoint(date: date, value: Double(index))
        }
        let series = HealthTrendSeries(points: points)

        XCTAssertEqual(series.limited(to: .recentWeek, calendar: calendar, date: currentDate).points.map(\.value), Array(393...399).map(Double.init))
        XCTAssertEqual(series.limited(to: .recentMonth, calendar: calendar, date: currentDate).points.map(\.value), Array(370...399).map(Double.init))
        XCTAssertEqual(series.limited(to: .recentSixMonths, calendar: calendar, date: currentDate).points.map(\.value), Array(217...399).map(Double.init))
        XCTAssertEqual(series.limited(to: .recentYear, calendar: calendar, date: currentDate).points.map(\.value), Array(35...399).map(Double.init))
    }

    func testBasicsTrendSummaryLimitsWeightAndBodyFatTogether() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let days = try (-9...0).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: currentDate)))
        }
        let basics = BasicsTrendSummary(
            weight: HealthTrendSeries(points: days.enumerated().map { index, date in
                HealthTrendDataPoint(date: date, value: 150 + Double(index))
            }),
            bodyFat: HealthTrendSeries(points: days.enumerated().map { index, date in
                HealthTrendDataPoint(date: date, value: 12 + Double(index) * 0.1)
            }),
            bodyMassIndex: HealthTrendSeries(points: days.enumerated().map { index, date in
                HealthTrendDataPoint(date: date, value: 21 + Double(index) * 0.05)
            })
        )
        let recentWeek = basics.limited(to: .recentWeek, calendar: calendar, date: currentDate)

        XCTAssertEqual(HealthMetricKind.basics.id, "basics")
        XCTAssertEqual(recentWeek.weight.points.count, 7)
        XCTAssertEqual(recentWeek.bodyFat.points.count, 7)
        XCTAssertEqual(recentWeek.bodyMassIndex.points.count, 7)
        XCTAssertEqual(recentWeek.weight.points.first?.value, 153)
        XCTAssertEqual(recentWeek.bodyFat.points.last?.value, 12.9)
        XCTAssertEqual(recentWeek.bodyMassIndex.points.last?.value, 21.45)
        XCTAssertFalse(recentWeek.isEmpty)
    }

    func testBasicsTrendSummaryExposesWeightAndBodyFatAveragesForLegend() throws {
        let date = try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let basics = BasicsTrendSummary(
            weight: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: date, value: 150),
                HealthTrendDataPoint(date: date.addingTimeInterval(86_400), value: 154)
            ]),
            bodyFat: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: date, value: 12.2),
                HealthTrendDataPoint(date: date.addingTimeInterval(86_400), value: 12.8)
            ]),
            bodyMassIndex: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: date, value: 21.3)
            ])
        )

        XCTAssertEqual(basics.weightAverage, 152)
        XCTAssertEqual(try XCTUnwrap(basics.bodyFatAverage), 12.5, accuracy: 0.001)
        XCTAssertNil(BasicsTrendSummary.empty.weightAverage)
        XCTAssertNil(BasicsTrendSummary.empty.bodyFatAverage)
    }

    func testBasicsTrendSummaryComputesMetricHalfSpreads() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let days = try (-8...0).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: currentDate)))
        }
        let basics = BasicsTrendSummary(
            weight: HealthTrendSeries(points: days.enumerated().map { index, date in
                HealthTrendDataPoint(date: date, value: 150 + Double(index))
            }),
            bodyFat: HealthTrendSeries(points: days.enumerated().map { index, date in
                HealthTrendDataPoint(date: date, value: 12 + Double(index) * 0.25)
            }),
            bodyMassIndex: HealthTrendSeries(points: days.enumerated().map { index, date in
                HealthTrendDataPoint(date: date, value: 21 + Double(index) * 0.1)
            })
        )

        let recentWeek = basics.limited(to: .recentWeek, calendar: calendar, date: currentDate)
        let recentMonth = basics.limited(to: .recentMonth, calendar: calendar, date: currentDate)

        XCTAssertEqual(recentWeek.weightHalfSpread, 3)
        XCTAssertEqual(recentWeek.bodyFatHalfSpread, 0.75)
        XCTAssertEqual(recentWeek.bodyMassIndexHalfSpread ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(recentMonth.weightHalfSpread, 4)
        XCTAssertEqual(recentMonth.bodyFatHalfSpread, 1)
        XCTAssertEqual(recentMonth.bodyMassIndexHalfSpread ?? 0, 0.4, accuracy: 0.001)
        XCTAssertNil(BasicsTrendSummary.empty.weightHalfSpread)
        XCTAssertNil(BasicsTrendSummary.empty.bodyFatHalfSpread)
        XCTAssertNil(BasicsTrendSummary.empty.bodyMassIndexHalfSpread)
    }

    func testHealthTrendSeriesFindsNearestPointForChartSelection() throws {
        let calendar = Calendar.bodyGregorian
        let days = try (9...11).map { day in
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: day)))
        }
        let series = HealthTrendSeries(points: days.enumerated().map { index, date in
            HealthTrendDataPoint(date: date, value: Double(index))
        })
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8)))

        XCTAssertEqual(series.nearestPoint(to: selectedDate)?.date, days[1])
        XCTAssertEqual(series.nearestPoint(to: selectedDate)?.value, 1)
        XCTAssertNil(HealthTrendSeries.empty.nearestPoint(to: selectedDate))
    }

    func testHealthTrendSeriesRequiresUserSelectionDateForChartSelection() throws {
        let calendar = Calendar.bodyGregorian
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: date, value: 69.25)
        ])

        XCTAssertNil(series.selectionPoint(for: nil))
        XCTAssertEqual(series.selectionPoint(for: date)?.value, 69.25)
    }

    func testHealthTrendSeriesFiltersPointsByCalendarDay() throws {
        let calendar = Calendar.bodyGregorian
        let previousDayPoint = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 23, minute: 50)))
        let selectedDayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let selectedMorningPoint = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7, minute: 15)))
        let selectedEveningPoint = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 22, minute: 5)))
        let nextDayPoint = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 0, minute: 10)))
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: nextDayPoint, value: 4),
            HealthTrendDataPoint(date: selectedEveningPoint, value: 3),
            HealthTrendDataPoint(date: previousDayPoint, value: 1),
            HealthTrendDataPoint(date: selectedMorningPoint, value: 2)
        ])

        let selectedDaySeries = series.points(on: selectedDayStart, calendar: calendar)

        XCTAssertEqual(selectedDaySeries.points.map(\.date), [selectedMorningPoint, selectedEveningPoint])
        XCTAssertEqual(selectedDaySeries.points.map(\.value), [2, 3])
    }

    func testHealthTrendSeriesAveragesFiniteTrendValues() {
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: Date(timeIntervalSinceReferenceDate: 1), value: 10),
            HealthTrendDataPoint(date: Date(timeIntervalSinceReferenceDate: 2), value: 20),
            HealthTrendDataPoint(date: Date(timeIntervalSinceReferenceDate: 3), value: .nan),
            HealthTrendDataPoint(date: Date(timeIntervalSinceReferenceDate: 4), value: .infinity)
        ])

        XCTAssertEqual(series.averageValue, 15)
        XCTAssertNil(HealthTrendSeries.empty.averageValue)
        XCTAssertNil(HealthTrendSeries(points: [
            HealthTrendDataPoint(date: Date(timeIntervalSinceReferenceDate: 5), value: .nan)
        ]).averageValue)
    }

    func testHealthTrendSeriesBuildsHourlyAverageBucketsWithRawSamples() throws {
        let calendar = Calendar.bodyGregorian
        let selectedDayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let firstHourStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7)))
        let firstSample = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7, minute: 5)))
        let secondSample = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7, minute: 40)))
        let secondHourStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 8)))
        let thirdSample = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 8, minute: 20)))
        let nextDaySample = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 0, minute: 5)))
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: secondSample, value: 66),
            HealthTrendDataPoint(date: firstSample, value: 60),
            HealthTrendDataPoint(date: nextDaySample, value: 100),
            HealthTrendDataPoint(date: thirdSample, value: 72)
        ])

        let buckets = series.hourlyAverageBuckets(on: selectedDayStart, calendar: calendar)

        XCTAssertEqual(buckets.map(\.hourStart), [firstHourStart, secondHourStart])
        XCTAssertEqual(buckets.map(\.averageValue), [63, 72])
        XCTAssertEqual(buckets[0].samples.map(\.date), [firstSample, secondSample])
        XCTAssertEqual(buckets[0].samples.map(\.value), [60, 66])
        XCTAssertEqual(buckets[0].plotDate, firstHourStart.addingTimeInterval(30 * 60))
    }

    func testHealthTrendHourlyBucketBreaksSamplesIntoTenMinuteWindows() throws {
        let calendar = Calendar.bodyGregorian
        let hourStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7)))
        let samples = try [
            (minute: 2, value: 60.0),
            (minute: 7, value: 66.0),
            (minute: 20, value: 72.0),
            (minute: 29, value: 78.0),
            (minute: 45, value: 90.0),
            (minute: 59, value: 96.0)
        ].map { sample -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: 5, day: 11, hour: 7, minute: sample.minute)
            ))
            return HealthTrendDataPoint(date: date, value: sample.value)
        }
        let bucket = HealthTrendHourlyBucket(hourStart: hourStart, averageValue: 69, samples: samples)

        let windows = bucket.sampleWindows()

        XCTAssertEqual(windows.map(\.startDate), [
            hourStart,
            hourStart.addingTimeInterval(20 * 60),
            hourStart.addingTimeInterval(40 * 60),
            hourStart.addingTimeInterval(50 * 60)
        ])
        XCTAssertEqual(windows.map(\.endDate), [
            hourStart.addingTimeInterval(10 * 60),
            hourStart.addingTimeInterval(30 * 60),
            hourStart.addingTimeInterval(50 * 60),
            hourStart.addingTimeInterval(60 * 60)
        ])
        XCTAssertEqual(windows.map(\.averageValue), [63, 75, 90, 96])
        XCTAssertEqual(windows.map { $0.samples.map(\.value) }, [[60, 66], [72, 78], [90], [96]])
    }

    func testHealthTrendSnapshotReturnsDaySeriesForVitalsDayView() throws {
        let date = Date(timeIntervalSince1970: 0)
        let heartRateSamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: date, value: 82)
        ])
        let restingHeartRateSamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: date, value: 61)
        ])
        let heartRateVariabilitySamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: date, value: 42)
        ])
        let respiratoryRateSamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: date, value: 14)
        ])
        let oxygenSaturationSamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: date, value: 98)
        ])
        let trends = HealthTrendSnapshot(
            sleep: .empty,
            heartRate: .empty,
            heartRateRanges: .empty,
            restingHeartRate: .empty,
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            heartRateDaySamples: heartRateSamples,
            restingHeartRateDaySamples: restingHeartRateSamples,
            heartRateVariabilityDaySamples: heartRateVariabilitySamples,
            respiratoryRateDaySamples: respiratoryRateSamples,
            oxygenSaturationDaySamples: oxygenSaturationSamples
        )

        XCTAssertEqual(trends.daySeries(for: .heartRate), heartRateSamples)
        XCTAssertEqual(trends.daySeries(for: .restingHeartRate), restingHeartRateSamples)
        XCTAssertEqual(trends.daySeries(for: .heartRateVariability), heartRateVariabilitySamples)
        XCTAssertEqual(trends.daySeries(for: .respiratoryRate), respiratoryRateSamples)
        XCTAssertEqual(trends.daySeries(for: .oxygenSaturation), oxygenSaturationSamples)
        XCTAssertTrue(trends.daySeries(for: .activeEnergy).isEmpty)
    }

    func testSleepHistoryDatePickerDatesEndWithToday() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 20)))

        let dates = SleepHistorySnapshot.datePickerDates(endingAt: today, dayCount: 7, calendar: calendar)

        XCTAssertEqual(dates.map { calendar.component(.day, from: $0) }, [10, 11, 12, 13, 14, 15, 16])
        XCTAssertEqual(dates.last, calendar.startOfDay(for: today))
    }

    func testSleepHistoryDatePickerDatesCanIncludeFuturePlaceholderDays() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 20)))

        let dates = SleepHistorySnapshot.datePickerDates(endingAt: today, dayCount: 7, futureDayCount: 1, calendar: calendar)

        XCTAssertEqual(dates.map { calendar.component(.day, from: $0) }, [10, 11, 12, 13, 14, 15, 16, 17])
        XCTAssertEqual(dates[dates.count - 2], calendar.startOfDay(for: today))
    }

    func testDateSliderTilePrimaryLabelUsesWeekdaysOnlyForMostRecentWeek() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 20)))
        let currentDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16)))
        let oldestRecentDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let olderCurrentMonthDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
        let olderPriorMonthDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))

        XCTAssertEqual(BodyDateSliderTileLabel.primaryText(for: currentDay, today: today, calendar: calendar), "Sat")
        XCTAssertEqual(BodyDateSliderTileLabel.primaryText(for: oldestRecentDay, today: today, calendar: calendar), "Sun")
        XCTAssertEqual(BodyDateSliderTileLabel.primaryText(for: olderCurrentMonthDay, today: today, calendar: calendar), "May")
        XCTAssertEqual(BodyDateSliderTileLabel.primaryText(for: olderPriorMonthDay, today: today, calendar: calendar), "Apr")
    }

    func testSleepHistoryFindsSummaryByCalendarDay() throws {
        let calendar = Calendar.bodyGregorian
        let dayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 14)))
        let summary = SleepSummary(duration: 7.5 * 3600)
        let history = SleepHistorySnapshot(days: [
            SleepDaySummary(date: dayStart, summary: summary)
        ])

        XCTAssertEqual(history.summary(on: selectedDate, calendar: calendar)?.summary.duration, summary.duration)
        XCTAssertNil(history.summary(on: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12))), calendar: calendar))
    }

    func testSleepHistoryResolvesHistoricalSummaryBeforeCurrentFallback() throws {
        let calendar = Calendar.bodyGregorian
        let historicalDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let currentDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let historicalSummary = SleepSummary(duration: 7 * 3600)
        let currentSummary = SleepSummary(duration: 8 * 3600)
        let history = SleepHistorySnapshot(days: [
            SleepDaySummary(date: historicalDay, summary: historicalSummary)
        ])

        XCTAssertEqual(
            history.summary(
                on: historicalDay,
                currentDaySummary: currentSummary,
                today: currentDay,
                calendar: calendar
            )?.duration,
            historicalSummary.duration
        )
        XCTAssertEqual(
            history.summary(
                on: currentDay,
                currentDaySummary: currentSummary,
                today: currentDay,
                calendar: calendar
            )?.duration,
            currentSummary.duration
        )
        XCTAssertNil(history.summary(
            on: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))),
            currentDaySummary: currentSummary,
            today: currentDay,
            calendar: calendar
        ))
    }

    func testSleepHistoryBuildsSortedDurationSeries() throws {
        let calendar = Calendar.bodyGregorian
        let earlier = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let later = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let history = SleepHistorySnapshot(days: [
            SleepDaySummary(date: later, summary: SleepSummary(duration: 8 * 3600)),
            SleepDaySummary(date: earlier, summary: SleepSummary(duration: 6.5 * 3600))
        ])

        XCTAssertEqual(history.durationSeries.points.map(\.date), [earlier, later])
        XCTAssertEqual(history.durationSeries.points.map(\.value), [6.5, 8])
    }

    func testHealthTrendSnapshotPreservesSecondarySleepHistoryForStageComparison() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let primaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 23)))
        let primaryEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7)))
        let secondaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 23, minute: 30)))
        let secondaryEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 6, minute: 30)))
        let primaryHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: day,
                summary: SleepSummary(
                    duration: 8 * 3_600,
                    stageSnapshot: SleepStageSnapshot(
                        date: day,
                        segments: [
                            SleepStageSegment(stage: .core, startDate: primaryStart, endDate: primaryEnd)
                        ]
                    )
                )
            )
        ])
        let secondaryHistory = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: day,
                summary: SleepSummary(
                    duration: 7 * 3_600,
                    stageSnapshot: SleepStageSnapshot(
                        date: day,
                        segments: [
                            SleepStageSegment(stage: .deep, startDate: secondaryStart, endDate: secondaryEnd)
                        ]
                    )
                )
            )
        ])
        let refreshed = HealthTrendSnapshot(
            sleep: primaryHistory.durationSeries,
            sleepSecondary: secondaryHistory.durationSeries,
            restingHeartRate: .empty,
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            sleepHistory: primaryHistory,
            sleepHistorySecondary: secondaryHistory
        )

        let replaced = HealthTrendSnapshot.empty.replacingMetric(.sleep, with: refreshed)

        XCTAssertEqual(replaced.sleepHistory.summary(on: day, calendar: calendar)?.summary.stageSnapshot, primaryHistory.days[0].summary.stageSnapshot)
        XCTAssertEqual(replaced.sleepHistorySecondary.summary(on: day, calendar: calendar)?.summary.stageSnapshot, secondaryHistory.days[0].summary.stageSnapshot)
        XCTAssertEqual(replaced.secondarySeries(for: .sleep), secondaryHistory.durationSeries)
    }

    func testBasicsTrendSummaryFindsNearestDateAcrossWeightAndBodyFat() throws {
        let calendar = Calendar.bodyGregorian
        let weightDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
        let bodyFatDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let nextWeightDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11)))
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 3)))
        let basics = BasicsTrendSummary(
            weight: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: weightDate, value: 152),
                HealthTrendDataPoint(date: nextWeightDate, value: 153)
            ]),
            bodyFat: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: bodyFatDate, value: 12.4)
            ]),
            bodyMassIndex: .empty
        )

        XCTAssertEqual(basics.nearestDate(to: selectedDate), bodyFatDate)
        XCTAssertNil(BasicsTrendSummary.empty.nearestDate(to: selectedDate))
    }

    func testBasicsTrendSummaryRequiresUserSelectionDateForChartSelection() throws {
        let calendar = Calendar.bodyGregorian
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let basics = BasicsTrendSummary(
            weight: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: date, value: 152)
            ]),
            bodyFat: .empty,
            bodyMassIndex: .empty
        )

        XCTAssertNil(basics.selectionDate(for: nil))
        XCTAssertEqual(basics.selectionDate(for: date), date)
    }

    func testHealthSummaryUsesRespiratoryRateAsHomeMetric() {
        let summary = HealthSummarySnapshot(
            activityRings: .empty,
            sleep: SleepSummary(duration: nil),
            restingHeartRate: HealthMetricSummary(value: nil),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: nil),
            respiratoryRate: HealthMetricSummary(value: 14),
            oxygenSaturation: HealthMetricSummary(value: nil),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil)
        )
        let trends = HealthTrendSnapshot(
            sleep: .empty,
            restingHeartRate: .empty,
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: Date(timeIntervalSince1970: 0), value: 14)
            ]),
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty
        )

        XCTAssertEqual(HealthMetricKind.respiratoryRate.id, "respiratoryRate")
        XCTAssertEqual(summary.respiratoryRate.value, 14)
        XCTAssertEqual(trends.series(for: .respiratoryRate).points.first?.value, 14)
        XCTAssertFalse(summary.isEmpty)
    }

    func testHealthSummaryUsesActivityMetricsAsHomeCards() {
        let date = Date(timeIntervalSince1970: 0)
        let summary = HealthSummarySnapshot(
            activityRings: .empty,
            sleep: SleepSummary(duration: nil),
            restingHeartRate: HealthMetricSummary(value: nil),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: nil),
            respiratoryRate: HealthMetricSummary(value: nil),
            oxygenSaturation: HealthMetricSummary(value: nil),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil),
            exerciseMinutes: HealthMetricSummary(value: 77),
            trainingLoad: HealthMetricSummary(value: 1.12),
            wristTemperature: HealthMetricSummary(value: 36.4),
            timeInDaylight: HealthMetricSummary(value: 32),
            steps: HealthMetricSummary(value: 1_212)
        )
        let trends = HealthTrendSnapshot(
            sleep: .empty,
            restingHeartRate: .empty,
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            exerciseMinutes: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 77)]),
            trainingLoad: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 1.12)]),
            wristTemperature: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 36.4)]),
            timeInDaylight: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 32)]),
            steps: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 1_212)])
        )

        XCTAssertEqual(HealthMetricKind.exerciseMinutes.id, "exerciseMinutes")
        XCTAssertEqual(HealthMetricKind.trainingLoad.id, "trainingLoad")
        XCTAssertEqual(HealthMetricKind.wristTemperature.id, "wristTemperature")
        XCTAssertEqual(HealthMetricKind.timeInDaylight.id, "timeInDaylight")
        XCTAssertEqual(HealthMetricKind.steps.id, "steps")
        XCTAssertEqual(summary.exerciseMinutes.value, 77)
        XCTAssertEqual(summary.trainingLoad.value, 1.12)
        XCTAssertEqual(summary.wristTemperature.value, 36.4)
        XCTAssertEqual(summary.timeInDaylight.value, 32)
        XCTAssertEqual(summary.steps.value, 1_212)
        XCTAssertEqual(trends.series(for: .exerciseMinutes).points.first?.value, 77)
        XCTAssertEqual(trends.series(for: .trainingLoad).points.first?.value, 1.12)
        XCTAssertEqual(trends.series(for: .wristTemperature).points.first?.value, 36.4)
        XCTAssertEqual(trends.series(for: .timeInDaylight).points.first?.value, 32)
        XCTAssertEqual(trends.series(for: .steps).points.first?.value, 1_212)
        XCTAssertFalse(summary.isEmpty)
    }

    func testHealthMetricDetailHelpCoversEveryDetailPage() {
        let helpedKinds = HealthMetricKind.allCases.filter { $0.detailHelpText != nil }

        XCTAssertEqual(helpedKinds, HealthMetricKind.allCases)
        XCTAssertEqual(HealthMetricKind.sleep.detailHelpText?.title, "About Sleep")
        XCTAssertEqual(HealthMetricKind.basics.detailHelpText?.title, "About Basics")
        XCTAssertEqual(HealthMetricKind.heartRate.detailHelpText?.title, "About Heart Rate")
        XCTAssertEqual(HealthMetricKind.restingHeartRate.detailHelpText?.title, "About Resting Heart Rate")
        XCTAssertEqual(HealthMetricKind.oxygenSaturation.detailHelpText?.title, "About Blood Oxygen")
        XCTAssertTrue(HealthMetricKind.activeEnergy.detailHelpText?.body.contains("movement") == true)
        XCTAssertEqual(HealthMetricKind.exerciseMinutes.detailHelpText?.title, "About Exercise Minutes")
        XCTAssertEqual(HealthMetricKind.trainingLoad.detailHelpText?.title, "About Training Load")
        XCTAssertTrue(HealthMetricKind.trainingLoad.detailHelpText?.body.contains("acute training load") == true)
        XCTAssertEqual(HealthMetricKind.wristTemperature.detailHelpText?.title, "About Wrist Temperature")
        XCTAssertEqual(HealthMetricKind.timeInDaylight.detailHelpText?.title, "About Time In Daylight")
        XCTAssertEqual(HealthMetricKind.steps.detailHelpText?.title, "About Steps")
    }

    func testHealthMetricDataSourceTargetsHomeCardDetailScreens() {
        let sourcedKinds = HealthMetricKind.allCases.filter { $0.detailDataSourceText != nil }

        XCTAssertEqual(
            sourcedKinds,
            [
                .readiness,
                .sleep,
                .basics,
                .heartRate,
                .restingHeartRate,
                .heartRateVariability,
                .respiratoryRate,
                .oxygenSaturation,
                .activeEnergy,
                .restingEnergy,
                .exerciseMinutes,
                .trainingLoad,
                .wristTemperature,
                .timeInDaylight,
                .steps
            ]
        )
        XCTAssertEqual(HealthMetricKind.readiness.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.sleep.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.basics.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.heartRate.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.restingHeartRate.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.oxygenSaturation.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.activeEnergy.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.trainingLoad.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.steps.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertNil(HealthMetricKind.bodyMass.detailDataSourceText)
        XCTAssertNil(HealthMetricKind.bodyMassIndex.detailDataSourceText)
    }

    func testHealthMetricSourceSelectionSupportsRequestedCardsOnly() {
        XCTAssertEqual(
            HealthMetricKind.sourceSelectableKinds,
            [
                .heartRate,
                .sleep,
                .basics,
                .heartRateVariability,
                .restingHeartRate,
                .respiratoryRate,
                .steps,
                .oxygenSaturation,
                .activeEnergy,
                .restingEnergy,
                .exerciseMinutes,
                .wristTemperature,
                .timeInDaylight
            ]
        )
        XCTAssertTrue(HealthMetricKind.heartRate.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.sleep.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.basics.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.heartRateVariability.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.restingHeartRate.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.respiratoryRate.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.steps.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.oxygenSaturation.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.activeEnergy.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.restingEnergy.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.exerciseMinutes.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.wristTemperature.supportsHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.timeInDaylight.supportsHealthDataSourceSelection)
        XCTAssertFalse(HealthMetricKind.trainingLoad.supportsHealthDataSourceSelection)
    }

    func testSourceComparableMetricsSupportSecondarySourceSelection() {
        let garmin = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")

        XCTAssertTrue(HealthMetricKind.sleep.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.heartRate.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.heartRateVariability.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.restingHeartRate.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.steps.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.oxygenSaturation.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.activeEnergy.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.restingEnergy.supportsSecondaryHealthDataSourceSelection)
        XCTAssertTrue(HealthMetricKind.exerciseMinutes.supportsSecondaryHealthDataSourceSelection)
        XCTAssertFalse(HealthMetricKind.respiratoryRate.supportsSecondaryHealthDataSourceSelection)
        XCTAssertEqual(
            BodyHealthSecondaryDataSourceSelection.defaultValue.option(for: .restingEnergy),
            .noComparison
        )

        let selection = BodyHealthSecondaryDataSourceSelection.defaultValue
            .setting(.sleep, option: garmin)
            .setting(.restingHeartRate, option: garmin)
            .setting(.activeEnergy, option: garmin)
            .setting(.oxygenSaturation, option: garmin)
            .setting(.restingEnergy, option: garmin)

        XCTAssertEqual(selection.option(for: .sleep), garmin)
        XCTAssertEqual(selection.option(for: .restingHeartRate), garmin)
        XCTAssertEqual(selection.option(for: .activeEnergy), garmin)
        XCTAssertEqual(selection.option(for: .oxygenSaturation), garmin)
        XCTAssertEqual(selection.option(for: .restingEnergy), garmin)

        let restoredSelection = BodyHealthSecondaryDataSourceSelection.storedValue(from: selection.rawValue)
        XCTAssertEqual(restoredSelection.option(for: .sleep), garmin)
        XCTAssertEqual(restoredSelection.option(for: .restingHeartRate), garmin)
        XCTAssertEqual(restoredSelection.option(for: .activeEnergy), garmin)
        XCTAssertEqual(restoredSelection.option(for: .oxygenSaturation), garmin)
        XCTAssertEqual(restoredSelection.option(for: .restingEnergy), garmin)
        XCTAssertEqual(
            restoredSelection.setting(.restingEnergy, option: .noComparison).option(for: .restingEnergy),
            .noComparison
        )
    }

    func testRestingEnergyComparisonBucketsUseHalfCountForExpandedRanges() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let monthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentMonth.dayCount - 1),
            to: currentDayStart
        ))
        let sixMonthStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentSixMonths.dayCount - 1),
            to: currentDayStart
        ))
        let yearStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentYear.dayCount - 1),
            to: currentDayStart
        ))

        let monthSeries = HealthTrendSeries(points: try (0..<BodyHealthTrendRange.recentMonth.dayCount).map { offset in
            HealthTrendDataPoint(
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: monthStart)),
                value: Double(offset)
            )
        })
        let sixMonthSeries = HealthTrendSeries(points: try (0..<BodyHealthTrendRange.recentSixMonths.dayCount).map { offset in
            HealthTrendDataPoint(
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: sixMonthStart)),
                value: Double(offset)
            )
        })
        let yearSeries = HealthTrendSeries(points: try (0..<BodyHealthTrendRange.recentYear.dayCount).map { offset in
            HealthTrendDataPoint(
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: yearStart)),
                value: Double(offset)
            )
        })

        XCTAssertEqual(BodyHealthTrendRange.recentWeek.sourceComparisonChartAggregationDayCount, 1)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.sourceComparisonChartAggregationDayCount, 2)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.sourceComparisonChartAggregationDayCount, 12)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.sourceComparisonChartAggregationDayCount, 24)
        XCTAssertEqual(
            monthSeries.sourceComparisonChartCalendarPoints(to: .recentMonth, calendar: calendar, date: currentDate).count,
            BodyHealthTrendRange.recentMonth.chartCalendarPointCount / 2
        )
        XCTAssertEqual(
            sixMonthSeries.sourceComparisonChartCalendarPoints(to: .recentSixMonths, calendar: calendar, date: currentDate).count,
            BodyHealthTrendRange.recentSixMonths.chartCalendarPointCount / 2
        )
        XCTAssertEqual(
            yearSeries.sourceComparisonChartCalendarPoints(to: .recentYear, calendar: calendar, date: currentDate).count,
            BodyHealthTrendRange.recentYear.chartCalendarPointCount / 2
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.sourceComparisonChartBarWidth(forAvailableWidth: 390),
            BodyHealthTrendRange.recentWeek.chartBarWidth(forAvailableWidth: 390) / 2 * 1.12
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentMonth.sourceComparisonChartBarWidth(forAvailableWidth: 390),
            BodyHealthTrendRange.recentMonth.chartBarWidth(forAvailableWidth: 390) * 1.12
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentSixMonths.sourceComparisonChartBarWidth(forAvailableWidth: 320),
            BodyHealthTrendRange.recentSixMonths.chartBarWidth(forAvailableWidth: 320) * 1.12
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.sourceComparisonChartBarWidth(forAvailableWidth: 430),
            BodyHealthTrendRange.recentYear.chartBarWidth(forAvailableWidth: 430) * 1.12
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.sourceComparisonChartDateOffset,
            24 * 60 * 60 * 0.16,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentMonth.sourceComparisonChartDateOffset,
            2 * 24 * 60 * 60 * 0.16,
            accuracy: 0.001
        )
    }

    func testHealthDataSourceSelectionPersistsPerMetricSourceOptions() throws {
        let appleWatch = BodyHealthDataSourceOption(id: "com.apple.Health", name: "Apple Watch")
        let oura = BodyHealthDataSourceOption(id: "com.ouraring.oura", name: "Oura")
        let whoop = BodyHealthDataSourceOption(id: "com.whoop", name: "WHOOP")

        let selection = BodyHealthDataSourceSelection.defaultValue
            .settingDefault(option: appleWatch)
            .setting(.heartRate, option: appleWatch)
            .setting(.sleep, option: oura)

        XCTAssertEqual(selection.defaultOption, appleWatch)
        XCTAssertEqual(selection.option(for: .heartRate), appleWatch)
        XCTAssertEqual(selection.option(for: .sleep), oura)
        XCTAssertEqual(selection.option(for: .steps), appleWatch)
        XCTAssertEqual(selection.option(for: .basics), appleWatch)
        XCTAssertFalse(selection.rawValue.isEmpty)

        let restoredSelection = BodyHealthDataSourceSelection.storedValue(from: selection.rawValue)
        XCTAssertEqual(restoredSelection.defaultOption, appleWatch)
        XCTAssertEqual(restoredSelection.option(for: .heartRate), appleWatch)
        XCTAssertEqual(restoredSelection.option(for: .sleep), oura)
        XCTAssertEqual(restoredSelection.option(for: .steps), appleWatch)
        XCTAssertEqual(restoredSelection.clearingOverride(for: .sleep).option(for: .sleep), appleWatch)
        XCTAssertEqual(
            selection
                .setting(.sleep, option: appleWatch)
                .settingDefault(option: whoop)
                .option(for: .sleep),
            whoop
        )

        let staleOverrideSelection = BodyHealthDataSourceSelection(
            defaultOption: appleWatch,
            selectedOptions: [.sleep: appleWatch]
        )
        XCTAssertEqual(staleOverrideSelection.settingDefault(option: whoop).option(for: .sleep), whoop)
    }

    func testSecondaryDataSourceSelectionUsesGlobalDefaultUntilMetricOverride() {
        let garmin = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")
        let oura = BodyHealthDataSourceOption(id: "com.ouraring.oura", name: "Oura")
        let whoop = BodyHealthDataSourceOption(id: "com.whoop", name: "WHOOP")

        let selection = BodyHealthSecondaryDataSourceSelection.defaultValue
            .settingDefault(option: garmin)
            .setting(.sleep, option: oura)

        XCTAssertEqual(selection.defaultOption, garmin)
        XCTAssertEqual(selection.option(for: .heartRate), garmin)
        XCTAssertEqual(selection.option(for: .sleep), oura)
        XCTAssertEqual(selection.option(for: .respiratoryRate), .noComparison)

        let restoredSelection = BodyHealthSecondaryDataSourceSelection.storedValue(from: selection.rawValue)
        XCTAssertEqual(restoredSelection.defaultOption, garmin)
        XCTAssertEqual(restoredSelection.option(for: .heartRate), garmin)
        XCTAssertEqual(restoredSelection.option(for: .sleep), oura)
        XCTAssertEqual(restoredSelection.clearingOverride(for: .sleep).option(for: .sleep), garmin)
        XCTAssertEqual(
            selection
                .setting(.sleep, option: garmin)
                .settingDefault(option: whoop)
                .option(for: .sleep),
            whoop
        )

        let staleOverrideSelection = BodyHealthSecondaryDataSourceSelection(
            defaultOption: garmin,
            selectedOptions: [.sleep: garmin]
        )
        XCTAssertEqual(staleOverrideSelection.settingDefault(option: whoop).option(for: .sleep), whoop)
    }

    func testCombinedHealthDataSourceOptionIdsUseNormalizedNames() {
        let firstID = BodyHealthDataSourceOption.combinedSourceID(for: " iWatch X ")
        let secondID = BodyHealthDataSourceOption.combinedSourceID(for: "iwatch x")
        let compactID = BodyHealthDataSourceOption.combinedSourceID(for: "iWatchX")
        let spacedIndividualID = BodyHealthDataSourceOption.individualSourceID(
            bundleIdentifier: "com.apple.Health",
            name: "iWatch X",
            disambiguatesBundleIdentifier: true
        )
        let compactIndividualID = BodyHealthDataSourceOption.individualSourceID(
            bundleIdentifier: "com.apple.Health",
            name: "iWatchX",
            disambiguatesBundleIdentifier: true
        )

        XCTAssertEqual(firstID, secondID)
        XCTAssertEqual(firstID, compactID)
        XCTAssertNotEqual(spacedIndividualID, compactIndividualID)
        XCTAssertEqual(
            BodyHealthDataSourceOption.individualSourceID(
                bundleIdentifier: "com.apple.Health",
                name: "iWatch X",
                disambiguatesBundleIdentifier: false
            ),
            "com.apple.Health"
        )
        XCTAssertNotEqual(
            BodyHealthDataSourceOption.individualSourceIdentityKey(
                bundleIdentifier: "com.apple.Health",
                name: "iWatch X"
            ),
            BodyHealthDataSourceOption.individualSourceIdentityKey(
                bundleIdentifier: "com.apple.Health",
                name: "iWatchX"
            )
        )
        XCTAssertEqual(BodyHealthDataSourceOption.normalizedSourceName(" iWatch X "), "iwatchx")
        XCTAssertEqual(BodyHealthDataSourceOption.normalizedSourceName("iWatchX"), "iwatchx")
        XCTAssertEqual(BodyHealthDataSourceOption.combinedSourceDisplayName(for: " iWatch X "), "iWatchX")
        XCTAssertNotEqual(
            BodyHealthDataSourceOption.combinedSourceID(for: "Mi Fit"),
            BodyHealthDataSourceOption.combinedSourceID(for: "MiFit")
        )
        XCTAssertTrue(BodyHealthDataSourceOption(id: firstID, name: "iWatchX").isCombinedSource)
        XCTAssertFalse(BodyHealthDataSourceOption(id: "com.apple.Health", name: "Apple Watch").isCombinedSource)
    }

    func testHealthSummaryReplacingMetricOnlyChangesRequestedFields() {
        var current = HealthSummarySnapshot.empty
        current.heartRate = HealthMetricSummary(value: 70)
        current.steps = HealthMetricSummary(value: 4_000)
        current.bodyMass = HealthMetricSummary(value: 80)
        current.bodyFatPercentage = HealthMetricSummary(value: 0.2)
        current.bodyMassIndex = HealthMetricSummary(value: 24)

        var refreshed = current
        refreshed.heartRate = HealthMetricSummary(value: 88)
        refreshed.steps = HealthMetricSummary(value: 9_000)
        refreshed.bodyMass = HealthMetricSummary(value: 78)
        refreshed.bodyFatPercentage = HealthMetricSummary(value: 0.18)
        refreshed.bodyMassIndex = HealthMetricSummary(value: 23)

        let heartOnly = current.replacingMetric(.heartRate, with: refreshed)
        XCTAssertEqual(heartOnly.heartRate.value, 88)
        XCTAssertEqual(heartOnly.steps.value, 4_000)
        XCTAssertEqual(heartOnly.bodyMass.value, 80)

        let basicsOnly = current.replacingMetric(.basics, with: refreshed)
        XCTAssertEqual(basicsOnly.heartRate.value, 70)
        XCTAssertEqual(basicsOnly.steps.value, 4_000)
        XCTAssertEqual(basicsOnly.bodyMass.value, 78)
        XCTAssertEqual(basicsOnly.bodyFatPercentage.value, 0.18)
        XCTAssertEqual(basicsOnly.bodyMassIndex.value, 23)
    }

    func testHealthTrendReplacingMetricOnlyChangesRequestedSeries() throws {
        let day = try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 16)))
        var current = HealthTrendSnapshot.empty
        current.heartRate = HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 70)])
        current.heartRateRanges = HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: day, lowValue: 60, highValue: 90, averageValue: 70)
        ])
        current.heartRateDaySamples = HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 72)])
        current.steps = HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 4_000)])

        var refreshed = current
        refreshed.heartRate = HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 88)])
        refreshed.heartRateRanges = HealthTrendRangeSeries(points: [
            HealthTrendRangeDataPoint(date: day, lowValue: 65, highValue: 110, averageValue: 88)
        ])
        refreshed.heartRateDaySamples = HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 91)])
        refreshed.steps = HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 9_000)])

        let heartOnly = current.replacingMetric(.heartRate, with: refreshed)
        XCTAssertEqual(heartOnly.heartRate.points.map(\.value), [88])
        XCTAssertEqual(heartOnly.heartRateRanges.points.map(\.averageValue), [88])
        XCTAssertEqual(heartOnly.heartRateDaySamples.points.map(\.value), [91])
        XCTAssertEqual(heartOnly.steps.points.map(\.value), [4_000])

        let stepsOnly = current.replacingMetric(.steps, with: refreshed)
        XCTAssertEqual(stepsOnly.heartRate.points.map(\.value), [70])
        XCTAssertEqual(stepsOnly.heartRateRanges.points.map(\.averageValue), [70])
        XCTAssertEqual(stepsOnly.heartRateDaySamples.points.map(\.value), [72])
        XCTAssertEqual(stepsOnly.steps.points.map(\.value), [9_000])
    }

    func testSleepScoreUsesStagePercentagesPressureAndVitals() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(5.2 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .rem,
                    startDate: startDate.addingTimeInterval(5.2 * 60 * 60),
                    endDate: startDate.addingTimeInterval(6.8 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .deep,
                    startDate: startDate.addingTimeInterval(6.8 * 60 * 60),
                    endDate: startDate.addingTimeInterval(8 * 60 * 60)
                )
            ]
        )
        let summary = SleepSummary(
            duration: 8 * 60 * 60,
            stageSnapshot: snapshot,
            vitals: SleepVitalsSummary(
                heartRate: 55,
                heartRateVariability: 72,
                respiratoryRate: 14,
                oxygenSaturation: 98,
                wristTemperatureCelsius: 36.4
            )
        )
        let score = try XCTUnwrap(summary.score)

        XCTAssertEqual(score.total, 94)
        XCTAssertEqual(score.categories.map(\.kind), [.duration, .continuity, .deep, .rem, .pressure, .vitals, .temperature])
        XCTAssertEqual(score.categories.map(\.points), [25, 20, 11, 9, 14, 10, 5])
        XCTAssertEqual(score.category(for: .deep)?.valueDescription, "15%")
        XCTAssertEqual(score.category(for: .rem)?.valueDescription, "20%")
        XCTAssertEqual(score.category(for: .pressure)?.valueDescription, "72 ms")
        XCTAssertEqual(snapshot.duration(for: .rem), 1.6 * 60 * 60, accuracy: 0.01)
        XCTAssertEqual(snapshot.duration(for: .deep), 1.2 * 60 * 60, accuracy: 0.01)
    }

    func testSleepScoreNormalizesToAvailableContributors() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(5.2 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .rem,
                    startDate: startDate.addingTimeInterval(5.2 * 60 * 60),
                    endDate: startDate.addingTimeInterval(6.8 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .deep,
                    startDate: startDate.addingTimeInterval(6.8 * 60 * 60),
                    endDate: startDate.addingTimeInterval(8 * 60 * 60)
                )
            ]
        )
        let score = try XCTUnwrap(SleepSummary(duration: 8 * 60 * 60, stageSnapshot: snapshot).score)

        XCTAssertEqual(score.total, 93)
        XCTAssertEqual(score.categories.map(\.kind), [.duration, .continuity, .deep, .rem])
        XCTAssertEqual(score.categories.map(\.points), [25, 20, 11, 9])
    }

    func testSleepScoreAmountUsesIdealSleepDurationGoal() throws {
        let sevenHourSummary = SleepSummary(duration: 7 * 60 * 60)
        let defaultGoalScore = try XCTUnwrap(SleepScoreSummary(sleep: sevenHourSummary))
        let customGoalScore = try XCTUnwrap(SleepScoreSummary(
            sleep: sevenHourSummary,
            idealSleepDuration: 7 * 60 * 60
        ))

        XCTAssertEqual(defaultGoalScore.category(for: .duration)?.points, 17)
        XCTAssertEqual(customGoalScore.category(for: .duration)?.points, 25)
        XCTAssertEqual(customGoalScore.category(for: .duration)?.valueDescription, "7h")
        XCTAssertEqual(customGoalScore.total, 100)
    }

    func testSleepScorePenalizesStartTimeDeviationFromRecentBaseline() throws {
        let calendar = Calendar.bodyGregorian
        let currentDay = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 15)
        ))
        let currentStart = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 15, hour: 2)
        ))
        let currentSummary = SleepSummary(
            duration: 8 * 60 * 60,
            stageSnapshot: SleepStageSnapshot(
                date: currentDay,
                segments: [
                    SleepStageSegment(
                        stage: .core,
                        startDate: currentStart,
                        endDate: currentStart.addingTimeInterval(8 * 60 * 60)
                    )
                ]
            )
        )
        let history = SleepHistorySnapshot(days: try (1...14).map { day -> SleepDaySummary in
            let sleepDay = try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: 5, day: day)
            ))
            let sleepStart = try XCTUnwrap(calendar.date(
                from: DateComponents(year: 2026, month: 5, day: day, hour: 23)
            ))

            return SleepDaySummary(
                date: sleepDay,
                summary: SleepSummary(
                    duration: 8 * 60 * 60,
                    stageSnapshot: SleepStageSnapshot(
                        date: sleepDay,
                        segments: [
                            SleepStageSegment(
                                stage: .core,
                                startDate: sleepStart,
                                endDate: sleepStart.addingTimeInterval(8 * 60 * 60)
                            )
                        ]
                    )
                )
            )
        })

        let score = try XCTUnwrap(SleepScoreSummary(
            sleep: currentSummary,
            recentSleepHistory: history,
            on: currentDay,
            calendar: calendar
        ))

        XCTAssertEqual(score.total, 82)
        XCTAssertEqual(score.categories.map(\.kind), [.duration, .continuity, .startTime])
        XCTAssertEqual(score.category(for: .startTime)?.points, 0)
        XCTAssertEqual(score.category(for: .startTime)?.maximumPoints, 10)
        XCTAssertEqual(score.category(for: .startTime)?.valueDescription, "3h off")
    }

    func testSleepScoreCommentSummarizesScoreBand() {
        XCTAssertEqual(SleepScoreSummary.comment(for: 95), "Excellent sleep readiness for this day.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 84), "Strong sleep with small room to improve.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 72), "Decent sleep, but key areas can improve.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 63), "Mixed sleep signals for this day.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 45), "Low sleep score; prioritize readiness tonight.")
    }

    func testSleepScorePenalizesLowDeepPercentageAndPressure() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(6.4 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .rem,
                    startDate: startDate.addingTimeInterval(6.4 * 60 * 60),
                    endDate: startDate.addingTimeInterval(7.4 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .deep,
                    startDate: startDate.addingTimeInterval(7.4 * 60 * 60),
                    endDate: startDate.addingTimeInterval(8 * 60 * 60)
                )
            ]
        )
        let summary = SleepSummary(
            duration: 8 * 60 * 60,
            stageSnapshot: snapshot,
            vitals: SleepVitalsSummary(heartRateVariability: 30)
        )
        let score = try XCTUnwrap(summary.score)

        XCTAssertEqual(score.category(for: .deep)?.points, 6)
        XCTAssertEqual(score.category(for: .deep)?.valueDescription, "8%")
        XCTAssertEqual(score.category(for: .pressure)?.points, 6)
        XCTAssertEqual(score.category(for: .pressure)?.valueDescription, "30 ms")
        XCTAssertLessThan(score.total, 100)
    }

    func testSleepScoreKeepsGoodButImperfectNightsBelowExcellent() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 1, minute: 30)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(4.75 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .awake,
                    startDate: startDate.addingTimeInterval(4.75 * 60 * 60),
                    endDate: startDate.addingTimeInterval(5.25 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .rem,
                    startDate: startDate.addingTimeInterval(5.25 * 60 * 60),
                    endDate: startDate.addingTimeInterval(6.6 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .deep,
                    startDate: startDate.addingTimeInterval(6.6 * 60 * 60),
                    endDate: startDate.addingTimeInterval(7.5 * 60 * 60)
                )
            ]
        )
        let summary = SleepSummary(
            duration: 7.5 * 60 * 60,
            stageSnapshot: snapshot,
            vitals: SleepVitalsSummary(
                heartRate: 55,
                heartRateVariability: 50,
                respiratoryRate: 14,
                oxygenSaturation: 97,
                wristTemperatureCelsius: 36.4
            )
        )
        let score = try XCTUnwrap(summary.score)

        XCTAssertLessThan(score.total, 90)
        XCTAssertEqual(score.category(for: .duration)?.points, 21)
        XCTAssertEqual(score.category(for: .continuity)?.points, 17)
        XCTAssertEqual(score.category(for: .pressure)?.points, 9)
    }

    func testSleepVitalsMakeSleepSummaryNonEmptyAndUseSleepWindow() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 2, minute: 30)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate.addingTimeInterval(30 * 60),
                    endDate: startDate.addingTimeInterval(90 * 60)
                ),
                SleepStageSegment(
                    stage: .rem,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(20 * 60)
                )
            ]
        )
        let summary = HealthSummarySnapshot(
            activityRings: .empty,
            sleep: SleepSummary(
                duration: nil,
                stageSnapshot: snapshot,
                vitals: SleepVitalsSummary(
                    heartRate: 58,
                    respiratoryRate: 14,
                    oxygenSaturation: 97,
                    wristTemperatureCelsius: 36.4
                )
            ),
            restingHeartRate: HealthMetricSummary(value: nil),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: nil),
            respiratoryRate: HealthMetricSummary(value: nil),
            oxygenSaturation: HealthMetricSummary(value: nil),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil)
        )

        XCTAssertEqual(snapshot.dateInterval?.start, startDate)
        XCTAssertEqual(snapshot.dateInterval?.end, startDate.addingTimeInterval(90 * 60))
        XCTAssertFalse(summary.sleep.vitals.isEmpty)
        XCTAssertFalse(summary.isEmpty)
    }

    func testSleepStagesMakeHealthSummaryNonEmptyWithoutDurationOrVitals() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(60 * 60)
                )
            ]
        )
        let summary = HealthSummarySnapshot(
            activityRings: .empty,
            sleep: SleepSummary(duration: nil, stageSnapshot: snapshot),
            restingHeartRate: HealthMetricSummary(value: nil),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: nil),
            respiratoryRate: HealthMetricSummary(value: nil),
            oxygenSaturation: HealthMetricSummary(value: nil),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil)
        )

        XCTAssertFalse(summary.sleep.stageSnapshot.isEmpty)
        XCTAssertFalse(summary.isEmpty)
    }

    func testWorkoutCalendarDaySelectionRequiresWorkoutsAndHandler() {
        let emptyDay = WorkoutDaySummary(dateKey: "2026-05-01", day: 1, workouts: [])
        let activeDay = WorkoutDaySummary(
            dateKey: "2026-05-02",
            day: 2,
            workouts: [workout(day: 2, type: .running, duration: 1_800)]
        )

        XCTAssertFalse(WorkoutCalendarDaySelection.isSelectable(emptyDay, hasSelectionHandler: true))
        XCTAssertFalse(WorkoutCalendarDaySelection.isSelectable(activeDay, hasSelectionHandler: false))
        XCTAssertTrue(WorkoutCalendarDaySelection.isSelectable(activeDay, hasSelectionHandler: true))
    }

    func testWorkoutCalendarCountMarkersMatchCountRepresentation() {
        let expectedSymbolsByCount = [
            0: [],
            1: ["star.fill"],
            2: ["star.fill", "star.fill"],
            3: ["moon.fill"],
            4: ["moon.fill", "star.fill"],
            5: ["moon.fill", "star.fill", "star.fill"],
            6: ["moon.fill", "moon.fill"],
            7: ["moon.fill", "moon.fill", "star.fill"],
            8: ["sun.max.fill"],
            9: ["sun.max.fill", "star.fill"],
            10: ["sun.max.fill", "star.fill", "star.fill"],
            11: ["sun.max.fill", "moon.fill"],
            12: ["sun.max.fill", "moon.fill", "star.fill"],
            13: ["flame.fill"],
            18: ["flame.fill"]
        ]

        for (count, expectedSymbols) in expectedSymbolsByCount {
            XCTAssertEqual(WorkoutCalendarCountMarker.symbolNames(for: count), expectedSymbols)
        }
    }

    func testWorkoutTypeFilterUsesPlainToggleSemantics() {
        var selectedTypes = Set(BodyWorkoutType.allCases)

        selectedTypes = BodyWorkoutFilterLogic.toggled(.running, in: selectedTypes)
        XCTAssertFalse(selectedTypes.contains(.running))
        XCTAssertEqual(selectedTypes.count, BodyWorkoutType.allCases.count - 1)

        selectedTypes = [.running]
        selectedTypes = BodyWorkoutFilterLogic.toggled(.running, in: selectedTypes)
        XCTAssertTrue(selectedTypes.isEmpty)

        selectedTypes = BodyWorkoutFilterLogic.toggled(.running, in: selectedTypes)
        XCTAssertEqual(selectedTypes, [.running])
    }

    func testWorkoutTypeFilterActiveStateUsesUniversalTypeSet() {
        XCTAssertFalse(BodyWorkoutFilterLogic.hasActiveFilters(selectedTypes: Set(BodyWorkoutType.allCases)))
        XCTAssertTrue(BodyWorkoutFilterLogic.hasActiveFilters(selectedTypes: [.running]))
        XCTAssertTrue(BodyWorkoutFilterLogic.hasActiveFilters(selectedTypes: []))
    }

    func testMonthYearPickerBuildsListRelativeToProvidedDate() throws {
        let calendar = Calendar.bodyGregorian
        let mayEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 23)))
        let juneStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        XCTAssertEqual(
            BodyMonthYearPicker.monthYearList(monthsToShow: 3, relativeTo: mayEnd, calendar: calendar),
            [
                BodyMonthYear(month: 3, year: 2026),
                BodyMonthYear(month: 4, year: 2026),
                BodyMonthYear(month: 5, year: 2026)
            ]
        )
        XCTAssertEqual(
            BodyMonthYearPicker.monthYearList(monthsToShow: 3, relativeTo: juneStart, calendar: calendar),
            [
                BodyMonthYear(month: 4, year: 2026),
                BodyMonthYear(month: 5, year: 2026),
                BodyMonthYear(month: 6, year: 2026)
            ]
        )
    }

    func testSleepVitalReferenceRangeClassifiesRegionsAndMarkerPosition() {
        let range = SleepVitalReferenceRange(typicalLowerBound: 7, typicalUpperBound: 9)

        XCTAssertEqual(range.region(for: 6.5), .low)
        XCTAssertEqual(range.region(for: 8), .typical)
        XCTAssertEqual(range.region(for: 9.5), .high)
        XCTAssertEqual(range.markerPosition(for: 8), 0.5, accuracy: 0.01)
        XCTAssertEqual(range.markerPosition(for: -10), 0)
        XCTAssertEqual(range.markerPosition(for: 30), 1)
    }

    func testSleepVitalStatusTitleCountsOutliers() {
        XCTAssertEqual(SleepVitalStatusTitle.text(for: [.typical, .typical]), "Typical")
        XCTAssertEqual(SleepVitalStatusTitle.text(for: [.low, .typical]), "1 Outlier")
        XCTAssertEqual(SleepVitalStatusTitle.text(for: [.low, .typical, .high]), "2 Outliers")
        XCTAssertEqual(SleepVitalStatusTitle.text(for: [.low, .high, .high]), "3 Outliers")
    }

    func testActivityRingSummaryCapsProgressAndMakesSnapshotNonEmpty() {
        let rings = ActivityRingSummary(
            move: ActivityRingMetric(value: 670, goal: 500),
            exercise: ActivityRingMetric(value: 76, goal: 40),
            stand: ActivityRingMetric(value: 8, goal: 10)
        )
        let summary = HealthSummarySnapshot(
            activityRings: rings,
            sleep: SleepSummary(duration: nil),
            restingHeartRate: HealthMetricSummary(value: nil),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: nil),
            respiratoryRate: HealthMetricSummary(value: nil),
            oxygenSaturation: HealthMetricSummary(value: nil),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil)
        )

        XCTAssertEqual(rings.move.progress, 1)
        XCTAssertEqual(rings.exercise.progress, 1)
        XCTAssertEqual(rings.stand.progress, 0.8)
        XCTAssertFalse(rings.isEmpty)
        XCTAssertFalse(summary.isEmpty)
    }

    func testActivityRingMetricKeepsCompletionProgressForOverGoalRingHead() {
        let metric = ActivityRingMetric(value: 670, goal: 500)

        XCTAssertEqual(metric.progress, 1)
        XCTAssertEqual(metric.completionProgress, 1.34, accuracy: 0.001)
        XCTAssertEqual(ActivityRingMetric(value: 8, goal: 10).completionProgress, 0.8, accuracy: 0.001)
        XCTAssertEqual(ActivityRingMetric(value: nil, goal: 10).completionProgress, 0)
    }

    func testActivityRingMetricHeadProgressAlwaysHasAVisiblePosition() {
        XCTAssertEqual(ActivityRingMetric(value: nil, goal: 10).headProgress, 0)
        XCTAssertEqual(ActivityRingMetric(value: 0, goal: 10).headProgress, 0)
        XCTAssertEqual(ActivityRingMetric(value: 8, goal: 10).headProgress, 0.8, accuracy: 0.001)
        XCTAssertEqual(ActivityRingMetric(value: 10, goal: 10).headProgress, 0, accuracy: 0.001)
        XCTAssertEqual(ActivityRingMetric(value: 13.4, goal: 10).headProgress, 0.34, accuracy: 0.001)
    }

    func testActivityRingMetricShowsFullStartMarkerOnlyAtZeroProgress() {
        XCTAssertTrue(ActivityRingMetric.empty.showsFullStartMarker)
        XCTAssertTrue(ActivityRingMetric(value: 0, goal: 10).showsFullStartMarker)
        XCTAssertTrue(ActivityRingMetric(value: -1, goal: 10).showsFullStartMarker)
        XCTAssertFalse(ActivityRingMetric(value: 0.1, goal: 10).showsFullStartMarker)
        XCTAssertFalse(ActivityRingMetric(value: 10, goal: 10).showsFullStartMarker)
    }

    func testActivityRingOuterAndInnerFencesDoNotOverlapRingEdges() {
        let geometry = BodyActivityRingGraphicGeometry.self
        let moveOuterEdge = geometry.ringOuterEdge(diameter: geometry.moveDiameter)
        let standInnerEdge = geometry.ringInnerEdge(diameter: geometry.standDiameter)
        let outerFenceInnerEdge = geometry.fenceInnerEdge(diameter: geometry.outerFenceDiameter)
        let innerFenceOuterEdge = geometry.fenceOuterEdge(diameter: geometry.innerFenceDiameter)

        XCTAssertGreaterThan(outerFenceInnerEdge, moveOuterEdge)
        XCTAssertLessThan(innerFenceOuterEdge, standInnerEdge)
        XCTAssertEqual(outerFenceInnerEdge - moveOuterEdge, geometry.fenceLineWidth / 2, accuracy: 0.001)
        XCTAssertEqual(standInnerEdge - innerFenceOuterEdge, geometry.fenceLineWidth / 2, accuracy: 0.001)
    }

    func testActivityRingCompletionStarScalesWithRingSize() {
        let geometry = BodyActivityRingCompletionStarGeometry.self

        XCTAssertEqual(geometry.fontSize(for: 34), 9, accuracy: 0.001)
        XCTAssertEqual(geometry.fontSize(for: 108), 28.588, accuracy: 0.001)
        XCTAssertEqual(geometry.offset(for: 34).width, 3, accuracy: 0.001)
        XCTAssertEqual(geometry.offset(for: 34).height, -4, accuracy: 0.001)
        XCTAssertEqual(geometry.offset(for: 108).width, 9.529, accuracy: 0.001)
        XCTAssertEqual(geometry.offset(for: 108).height, -12.706, accuracy: 0.001)
    }

    func testActivityRingCompletionStarStaysAboveRingsWhileFading() {
        XCTAssertGreaterThan(BodyActivityRingCompletionStarGeometry.foregroundZIndex, 0)
    }

    func testActivityRingSummaryCompletionRequiresAllThreeRings() {
        let complete = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let partial = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 20, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )

        XCTAssertTrue(complete.isCompleted)
        XCTAssertFalse(partial.isCompleted)
        XCTAssertFalse(ActivityRingSummary.empty.isCompleted)
    }

    func testActivityRingHistoryTracksLoadedEmptyMonthsWithoutDisplayingLeadingPlaceholders() throws {
        let calendar = Calendar.bodyGregorian
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let aprilKey = ActivityRingMonthKey(month: 4, year: 2026)
        let april2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 2)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 12)))
        let aprilSummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 110, goal: 500),
            exercise: ActivityRingMetric(value: 12, goal: 30),
            stand: ActivityRingMetric(value: 4, goal: 12)
        )
        let existingHistory = ActivityRingHistorySnapshot(
            days: [ActivityRingDaySummary(date: april2, summary: aprilSummary)],
            loadedMonthKeys: [aprilKey]
        )
        let emptyMarchHistory = ActivityRingHistorySnapshot(days: [], loadedMonthKeys: [marchKey])

        let mergedHistory = existingHistory.merging(emptyMarchHistory, calendar: calendar)
        let months = mergedHistory.calendarMonths(calendar: calendar, date: currentDate)

        XCTAssertEqual(mergedHistory.loadedMonthKeySet(calendar: calendar), [marchKey, aprilKey])
        XCTAssertEqual(months.map(\.id), ["2026-4"])
        XCTAssertEqual(months[0].days[1].summary, aprilSummary)
    }

    func testActivityRingHistoryFiltersFetchedBoundaryDaysToExplicitLoadedMonths() throws {
        let calendar = Calendar.bodyGregorian
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let january1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let february1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let januarySummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 400, goal: 500),
            exercise: ActivityRingMetric(value: 28, goal: 30),
            stand: ActivityRingMetric(value: 9, goal: 12)
        )
        let februarySummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let fetchedHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january1, summary: januarySummary),
                ActivityRingDaySummary(date: february1, summary: februarySummary)
            ],
            loadedMonthKeys: [januaryKey]
        )

        let filteredHistory = fetchedHistory.filteringDaysToLoadedMonths(calendar: calendar)

        XCTAssertEqual(filteredHistory.days, [
            ActivityRingDaySummary(date: january1, summary: januarySummary)
        ])
        XCTAssertEqual(filteredHistory.loadedMonthKeys, [januaryKey])
    }

    func testActivityRingHistoryReplacingLoadedMonthKeepsAdjacentMonthData() throws {
        let calendar = Calendar.bodyGregorian
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let january1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let february1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let february2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 2)))
        let januarySummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 400, goal: 500),
            exercise: ActivityRingMetric(value: 28, goal: 30),
            stand: ActivityRingMetric(value: 9, goal: 12)
        )
        let boundarySummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let retainedSummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 520, goal: 500),
            exercise: ActivityRingMetric(value: 31, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let existingHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: february2, summary: retainedSummary)
            ],
            loadedMonthKeys: [februaryKey]
        )
        let fetchedJanuaryHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january1, summary: januarySummary),
                ActivityRingDaySummary(date: february1, summary: boundarySummary)
            ],
            loadedMonthKeys: [januaryKey]
        )

        let replacedHistory = existingHistory.replacingLoadedMonths(with: fetchedJanuaryHistory, calendar: calendar)

        XCTAssertEqual(replacedHistory.days.map(\.date), [january1, february1, february2])
        XCTAssertEqual(replacedHistory.days.last?.summary, retainedSummary)
        XCTAssertEqual(replacedHistory.loadedMonthKeys, [januaryKey, februaryKey])
    }

    func testActivityRingHistoryRemovesLikelyBoundaryTruncatedLoadedMonths() throws {
        let calendar = Calendar.bodyGregorian
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let january1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let february1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let march2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let march3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let corruptedHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january1, summary: summary),
                ActivityRingDaySummary(date: february1, summary: summary),
                ActivityRingDaySummary(date: march2, summary: summary),
                ActivityRingDaySummary(date: march3, summary: summary)
            ],
            loadedMonthKeys: [januaryKey, februaryKey, marchKey]
        )

        let repairedHistory = corruptedHistory.removingLikelyBoundaryTruncatedLoadedMonths(
            date: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(repairedHistory.days.map(\.date), [march2, march3])
        XCTAssertEqual(repairedHistory.loadedMonthKeys, [marchKey])
    }

    func testActivityRingHistoryCalendarMonthsOnlyIncludesLoadedMonths() throws {
        let calendar = Calendar.bodyGregorian
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let mayKey = ActivityRingMonthKey(month: 5, year: 2026)
        let january1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        let march2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let may3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let history = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january1, summary: summary),
                ActivityRingDaySummary(date: march2, summary: summary),
                ActivityRingDaySummary(date: may3, summary: summary)
            ],
            loadedMonthKeys: [januaryKey, marchKey, mayKey]
        )

        let months = history.calendarMonths(calendar: calendar, date: currentDate)

        XCTAssertEqual(months.map(\.id), ["2026-1", "2026-3", "2026-5"])
    }

    func testActivityRingHistoryCalendarMonthsCanLimitToNewestLoadedMonths() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let loadedKeys = (1...5).map { ActivityRingMonthKey(month: $0, year: 2026) }
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let days = try (1...5).map { month -> ActivityRingDaySummary in
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: 1)))
            return ActivityRingDaySummary(date: date, summary: summary)
        }
        let history = ActivityRingHistorySnapshot(days: days, loadedMonthKeys: loadedKeys)

        let months = history.calendarMonths(
            calendar: calendar,
            date: currentDate,
            visibleLoadedMonthCount: 3
        )

        XCTAssertEqual(months.map(\.id), ["2026-3", "2026-4", "2026-5"])
    }

    func testActivityRingCalendarMonthCountsCompletedRingDays() throws {
        let calendar = Calendar.bodyGregorian
        let completedSummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let partialSummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 10, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let days = try (1...4).map { day in
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: day)))
        }
        let month = ActivityRingCalendarMonth(
            month: 5,
            year: 2026,
            days: [
                ActivityRingCalendarDay(date: days[0], summary: completedSummary, hasData: true, isFuture: false),
                ActivityRingCalendarDay(date: days[1], summary: partialSummary, hasData: true, isFuture: false),
                ActivityRingCalendarDay(date: days[2], summary: completedSummary, hasData: false, isFuture: false),
                ActivityRingCalendarDay(date: days[3], summary: completedSummary, hasData: true, isFuture: true)
            ]
        )

        XCTAssertEqual(month.completedRingCount, 1)
    }

    func testActivityRingHistoryBuildsCompleteCalendarMonths() throws {
        let calendar = Calendar.bodyGregorian
        let april2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 2)))
        let may3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3)))
        let may12 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12)))
        let aprilSummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 110, goal: 500),
            exercise: ActivityRingMetric(value: 12, goal: 30),
            stand: ActivityRingMetric(value: 4, goal: 12)
        )
        let maySummary = ActivityRingSummary(
            move: ActivityRingMetric(value: 670, goal: 500),
            exercise: ActivityRingMetric(value: 76, goal: 40),
            stand: ActivityRingMetric(value: 8, goal: 10)
        )
        let history = ActivityRingHistorySnapshot(days: [
            ActivityRingDaySummary(date: may3, summary: maySummary),
            ActivityRingDaySummary(date: april2, summary: aprilSummary)
        ])

        let months = history.calendarMonths(calendar: calendar, date: may12)

        XCTAssertEqual(months.map(\.id), ["2026-4", "2026-5"])
        XCTAssertEqual(months[0].days.count, 30)
        XCTAssertEqual(months[1].days.count, 31)
        XCTAssertFalse(months[0].days[0].hasData)
        XCTAssertTrue(months[0].days[0].summary.isEmpty)
        XCTAssertEqual(months[0].days[1].summary, aprilSummary)
        XCTAssertTrue(months[0].days[1].hasData)
        XCTAssertEqual(months[1].days[2].summary, maySummary)
        XCTAssertTrue(months[1].days[12].isFuture)
    }

    func testHealthMetricKindSupportedComparisonChartsCoversExpectedKinds() {
        XCTAssertEqual(HealthMetricKind.sleep.supportedComparisonCharts, [.line])
        XCTAssertEqual(HealthMetricKind.restingHeartRate.supportedComparisonCharts, [.line, .dayLine])
        XCTAssertEqual(HealthMetricKind.heartRate.supportedComparisonCharts, [.range, .rangeBandLine, .dayLine])
        XCTAssertEqual(HealthMetricKind.heartRateVariability.supportedComparisonCharts, [.range, .rangeBandLine, .dayLine])
        XCTAssertEqual(HealthMetricKind.oxygenSaturation.supportedComparisonCharts, [.range, .dayLine])
        XCTAssertEqual(HealthMetricKind.steps.supportedComparisonCharts, [.bar, .dayLine])
        XCTAssertEqual(HealthMetricKind.activeEnergy.supportedComparisonCharts, [.bar, .dayLine])
        XCTAssertEqual(HealthMetricKind.exerciseMinutes.supportedComparisonCharts, [.bar])
        XCTAssertEqual(HealthMetricKind.respiratoryRate.supportedComparisonCharts, [])
        XCTAssertEqual(HealthMetricKind.bodyMassIndex.supportedComparisonCharts, [])
    }

    func testBodyHealthSourceTrendIdIncludesRoleToAvoidForEachCollision() {
        let series = HealthTrendSeries.empty
        let primary = BodyHealthSourceTrend(role: .primary, sourceName: "Apple Watch", series: series)
        let secondary = BodyHealthSourceTrend(role: .secondary, sourceName: "Apple Watch", series: series)

        XCTAssertNotEqual(primary.id, secondary.id, "Identical sourceName must not collide across roles")
    }

    func testBodyHealthSourceTrendAverageValueComputesOverComparisonBuckets() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let currentDayStart = calendar.startOfDay(for: currentDate)
        let weekStart = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: -(BodyHealthTrendRange.recentWeek.dayCount - 1),
            to: currentDayStart
        ))

        let series = HealthTrendSeries(points: try (0..<BodyHealthTrendRange.recentWeek.dayCount).map { offset in
            HealthTrendDataPoint(
                date: try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: weekStart)),
                value: Double(offset + 1)
            )
        })

        let trend = BodyHealthSourceTrend(role: .primary, sourceName: "Apple Watch", series: series)
        let expectedAverage: Double = Double(1 + 2 + 3 + 4 + 5 + 6 + 7) / 7.0
        XCTAssertEqual(
            try XCTUnwrap(trend.averageValue(in: .recentWeek, calendar: calendar, date: currentDate)),
            expectedAverage,
            accuracy: 0.0001
        )

        let emptyTrend = BodyHealthSourceTrend(role: .primary, sourceName: "Apple Watch", series: .empty)
        XCTAssertNil(emptyTrend.averageValue(in: .recentWeek, calendar: calendar, date: currentDate))
    }

    func testSecondaryDataSourceSelectionSignatureIsDeterministicAndKeyOrderInvariant() {
        let garmin = BodyHealthDataSourceOption(id: "com.garmin.connect", name: "Garmin")
        let oura = BodyHealthDataSourceOption(id: "com.ouraring.oura", name: "Oura")
        let selectionA = BodyHealthSecondaryDataSourceSelection.defaultValue
            .setting(.sleep, option: oura)
            .setting(.heartRateVariability, option: garmin)
        let selectionB = BodyHealthSecondaryDataSourceSelection.defaultValue
            .setting(.heartRateVariability, option: garmin)
            .setting(.sleep, option: oura)

        XCTAssertEqual(selectionA.signature, selectionB.signature)
        XCTAssertNotEqual(selectionA.signature, BodyHealthSecondaryDataSourceSelection.defaultValue.signature)
        XCTAssertNotEqual(
            selectionA.signature,
            selectionA.setting(.sleep, option: .noComparison).signature
        )
    }

    func testHealthTrendSnapshotClearingSecondarySeriesPreservesPrimaryData() {
        var snapshot = HealthTrendSnapshot.empty
        let series = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: Date(timeIntervalSinceReferenceDate: 0), value: 100)
        ])
        snapshot.steps = series
        snapshot.stepsSecondary = series
        snapshot.activeEnergy = series
        snapshot.activeEnergySecondary = series
        snapshot.restingHeartRate = series
        snapshot.restingHeartRateSecondary = series

        let cleared = snapshot.clearingSecondarySeries()

        XCTAssertEqual(cleared.steps, series)
        XCTAssertEqual(cleared.activeEnergy, series)
        XCTAssertEqual(cleared.restingHeartRate, series)
        XCTAssertTrue(cleared.stepsSecondary.isEmpty)
        XCTAssertTrue(cleared.activeEnergySecondary.isEmpty)
        XCTAssertTrue(cleared.restingHeartRateSecondary.isEmpty)
    }

    func testSourceComparisonChartDateOffsetUsesNamedConstants() {
        let secondsPerDay: Double = 24 * 60 * 60
        let fraction = BodyHealthTrendRange.sourceComparisonBucketOffsetFraction
        let aggregationWeek = BodyHealthTrendRange.recentWeek.sourceComparisonChartAggregationDayCount
        let aggregationSixMonths = BodyHealthTrendRange.recentSixMonths.sourceComparisonChartAggregationDayCount
        let aggregationYear = BodyHealthTrendRange.recentYear.sourceComparisonChartAggregationDayCount

        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.sourceComparisonChartDateOffset,
            Double(aggregationWeek) * secondsPerDay * fraction,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentSixMonths.sourceComparisonChartDateOffset,
            Double(aggregationSixMonths) * secondsPerDay * fraction,
            accuracy: 0.001
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentYear.sourceComparisonChartDateOffset,
            Double(aggregationYear) * secondsPerDay * fraction,
            accuracy: 0.001
        )
    }

    func testBodyValueFormatFormatsSleepVitals() {
        XCTAssertEqual(
            BodyValueFormat.respiratoryRateText(breathsPerMinute: 14.2, locale: Locale(identifier: "en_US_POSIX")),
            "14 br/min"
        )
        XCTAssertEqual(
            BodyValueFormat.temperatureDisplay(
                celsius: 36.5,
                locale: Locale(identifier: "en_GB"),
                unitPreference: .metric
            ).unit,
            "C"
        )
        XCTAssertEqual(
            BodyValueFormat.temperatureDisplay(
                celsius: 36.5,
                locale: Locale(identifier: "en_US"),
                unitPreference: .imperial
            ).unit,
            "F"
        )
        XCTAssertEqual(
            BodyValueFormat.temperatureValue(
                celsius: 36.5,
                locale: Locale(identifier: "en_US"),
                unitPreference: .imperial
            ).value,
            97.7,
            accuracy: 0.01
        )
    }

    private func readinessTrendSnapshot(
        scoreDay: Date,
        hrvBaseline: Double?,
        hrvToday: Double?,
        restingHeartRateBaseline: Double?,
        restingHeartRateToday: Double?,
        trainingLoadToday: Double?,
        calendar: Calendar
    ) -> HealthTrendSnapshot {
        HealthTrendSnapshot(
            sleep: .empty,
            heartRate: .empty,
            restingHeartRate: readinessSeries(
                scoreDay: scoreDay,
                baseline: restingHeartRateBaseline,
                today: restingHeartRateToday,
                calendar: calendar
            ),
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: readinessSeries(
                scoreDay: scoreDay,
                baseline: hrvBaseline,
                today: hrvToday,
                calendar: calendar
            ),
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            trainingLoad: readinessSeries(
                scoreDay: scoreDay,
                baseline: trainingLoadToday,
                today: trainingLoadToday,
                calendar: calendar
            )
        )
    }

    private func readinessSeries(
        scoreDay: Date,
        baseline: Double?,
        today: Double?,
        calendar: Calendar
    ) -> HealthTrendSeries {
        var points: [HealthTrendDataPoint] = []
        if let baseline {
            for offset in 1...28 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                    continue
                }

                points.append(HealthTrendDataPoint(date: date, value: baseline))
            }
        }
        if let today {
            points.append(HealthTrendDataPoint(date: scoreDay, value: today))
        }
        return HealthTrendSeries(points: points)
    }

    func testMakeHeartRateMergesDuplicateWorkoutsWithSameTypeAndTimeRange() throws {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 31)))
        let walkStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 10, minute: 32))
        )
        let laterStart = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 31, hour: 12, minute: 5))
        )

        let duplicateWalk = WorkoutSummary(
            type: .walking,
            startDate: walkStart,
            duration: 14 * 60,
            averageHeartRateBeatsPerMinute: 135,
            sourceName: "Apple Watch"
        )
        let secondDuplicate = WorkoutSummary(
            type: .walking,
            startDate: walkStart,
            duration: 14 * 60,
            averageHeartRateBeatsPerMinute: 135,
            sourceName: "Apple Watch"
        )
        let distinctWalk = WorkoutSummary(
            type: .walking,
            startDate: laterStart,
            duration: 15 * 60,
            averageHeartRateBeatsPerMinute: 108,
            sourceName: "Strava"
        )

        let rows = BodyMetricActivityAverages.makeHeartRate(
            day: day,
            heartRateSeries: HealthTrendSeries(points: []),
            sleepSummary: nil,
            workouts: [duplicateWalk, secondDuplicate, distinctWalk],
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.startDate), [walkStart, laterStart])
        XCTAssertEqual(rows.first?.averageValue, 135)
        XCTAssertEqual(rows.map(\.source), ["Apple Watch", "Strava"])
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
