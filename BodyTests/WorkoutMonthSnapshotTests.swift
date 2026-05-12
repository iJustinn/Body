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
            })
        )
        let recentWeek = basics.limited(to: .recentWeek, calendar: calendar, date: currentDate)

        XCTAssertEqual(HealthMetricKind.basics.id, "basics")
        XCTAssertEqual(recentWeek.weight.points.count, 7)
        XCTAssertEqual(recentWeek.bodyFat.points.count, 7)
        XCTAssertEqual(recentWeek.weight.points.first?.value, 153)
        XCTAssertEqual(recentWeek.bodyFat.points.last?.value, 12.9)
        XCTAssertFalse(recentWeek.isEmpty)
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

    func testSleepScoreUsesDurationREMAndDeepSleep() throws {
        let startDate = try XCTUnwrap(Calendar.bodyGregorian.date(
            from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)
        ))
        let snapshot = SleepStageSnapshot(
            date: Calendar.bodyGregorian.startOfDay(for: startDate),
            segments: [
                SleepStageSegment(
                    stage: .core,
                    startDate: startDate,
                    endDate: startDate.addingTimeInterval(5.25 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .rem,
                    startDate: startDate.addingTimeInterval(5.25 * 60 * 60),
                    endDate: startDate.addingTimeInterval(6.75 * 60 * 60)
                ),
                SleepStageSegment(
                    stage: .deep,
                    startDate: startDate.addingTimeInterval(6.75 * 60 * 60),
                    endDate: startDate.addingTimeInterval(8 * 60 * 60)
                )
            ]
        )
        let summary = SleepSummary(duration: 8 * 60 * 60, stageSnapshot: snapshot)
        let score = try XCTUnwrap(summary.score)

        XCTAssertEqual(score.total, 100)
        XCTAssertEqual(score.categories.map(\.kind), [.duration, .rem, .deep])
        XCTAssertEqual(score.categories.map(\.points), [50, 25, 25])
        XCTAssertEqual(snapshot.duration(for: .rem), 90 * 60)
        XCTAssertEqual(snapshot.duration(for: .deep), 75 * 60)
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
