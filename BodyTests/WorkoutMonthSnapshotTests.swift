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

    func testHomeCardOrderRepairsStoredValues() {
        let order = BodyHomeCardKind.storedOrder(from: "sleep,sleep,activeEnergy,unknown")

        XCTAssertEqual(Array(order.prefix(2)), [.sleep, .activeEnergy])
        XCTAssertEqual(Set(order), Set(BodyHomeCardKind.defaultOrder))
        XCTAssertEqual(order.count, BodyHomeCardKind.defaultOrder.count)
        XCTAssertTrue(order.contains(.activityRings))
    }

    func testHomeCardOrderMovesCardsToDropDestination() {
        let order = BodyHomeCardKind.defaultOrder

        let movedDown = BodyHomeCardKind.reordered(order, moving: .sleep, to: .basics)
        XCTAssertEqual(Array(movedDown.prefix(3)), [.activityRings, .basics, .sleep])
        XCTAssertEqual(Set(movedDown), Set(order))
        XCTAssertEqual(movedDown.count, order.count)

        let movedUp = BodyHomeCardKind.reordered(order, moving: .activeEnergy, to: .sleep)
        XCTAssertEqual(Array(movedUp.prefix(3)), [.activityRings, .activeEnergy, .sleep])
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

    func testHealthTrendSeriesLimitsToRecentWeek() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 15)))
        let points = try (-39...0).enumerated().map { index, offset -> HealthTrendDataPoint in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: currentDate)))
            return HealthTrendDataPoint(date: date, value: Double(index))
        }
        let series = HealthTrendSeries(points: points)

        XCTAssertEqual(series.limited(to: .recentWeek, calendar: calendar, date: currentDate).points.map(\.value), [33, 34, 35, 36, 37, 38, 39])
        XCTAssertEqual(series.limited(to: .recentMonth, calendar: calendar, date: currentDate).points.map(\.value), Array(10...39).map(Double.init))
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
            ])
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
            bodyFat: .empty
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

    func testHealthMetricDetailHelpOnlyTargetsRequestedCards() {
        let helpedKinds = HealthMetricKind.allCases.filter { $0.detailHelpText != nil }

        XCTAssertEqual(
            helpedKinds,
            [
                .restingHeartRate,
                .heartRateVariability,
                .respiratoryRate,
                .oxygenSaturation,
                .activeEnergy,
                .restingEnergy
            ]
        )
        XCTAssertEqual(HealthMetricKind.restingHeartRate.detailHelpText?.title, "About Resting Heart Rate")
        XCTAssertEqual(HealthMetricKind.oxygenSaturation.detailHelpText?.title, "About Blood Oxygen")
        XCTAssertTrue(HealthMetricKind.activeEnergy.detailHelpText?.body.contains("movement") == true)
        XCTAssertNil(HealthMetricKind.sleep.detailHelpText)
        XCTAssertNil(HealthMetricKind.basics.detailHelpText)
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

    func testActivityRingCalendarPaginationGateAllowsOneLoadPerUserScroll() {
        var gate = ActivityRingCalendarPaginationGate()

        XCTAssertFalse(gate.consumeLoadIfNeeded(isOldestVisible: true))

        gate.recordUserScroll()
        XCTAssertFalse(gate.consumeLoadIfNeeded(isOldestVisible: false))
        XCTAssertTrue(gate.consumeLoadIfNeeded(isOldestVisible: true))
        XCTAssertFalse(gate.consumeLoadIfNeeded(isOldestVisible: true))

        gate.recordUserScroll()
        XCTAssertTrue(gate.consumeLoadIfNeeded(isOldestVisible: true))
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
