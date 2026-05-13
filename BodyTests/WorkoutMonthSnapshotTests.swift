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
        XCTAssertEqual(BodyHealthTrendRange.allCases, [.recentWeek, .recentMonth, .recentSixMonths, .recentYear])
        XCTAssertEqual(BodyHealthTrendRange.allCases.map(\.displayName), ["Week", "Month", "6 Months", "Year"])
    }

    func testHealthTrendRangeOnlyShowsPointMarksOnShortRanges() {
        XCTAssertTrue(BodyHealthTrendRange.recentWeek.showsPointMarks)
        XCTAssertTrue(BodyHealthTrendRange.recentMonth.showsPointMarks)
        XCTAssertFalse(BodyHealthTrendRange.recentSixMonths.showsPointMarks)
        XCTAssertFalse(BodyHealthTrendRange.recentYear.showsPointMarks)
    }

    func testHealthTrendRangeUsesPreviewLineStyleOnlyOnShortRanges() {
        XCTAssertTrue(BodyHealthTrendRange.recentWeek.usesPreviewLineChartStyle)
        XCTAssertTrue(BodyHealthTrendRange.recentMonth.usesPreviewLineChartStyle)
        XCTAssertFalse(BodyHealthTrendRange.recentSixMonths.usesPreviewLineChartStyle)
        XCTAssertFalse(BodyHealthTrendRange.recentYear.usesPreviewLineChartStyle)
    }

    func testHealthTrendRangeUsesMetricColorStrokeForAllRanges() {
        XCTAssertTrue(BodyHealthTrendRange.recentWeek.usesMetricColorLineStroke)
        XCTAssertTrue(BodyHealthTrendRange.recentMonth.usesMetricColorLineStroke)
        XCTAssertTrue(BodyHealthTrendRange.recentSixMonths.usesMetricColorLineStroke)
        XCTAssertTrue(BodyHealthTrendRange.recentYear.usesMetricColorLineStroke)
    }

    func testHealthTrendRangeUsesLargerLineDotsOnShortRanges() {
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.linePointDiameter, 8, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.lineCurrentPointDiameter, 10, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.linePointDiameter, 8, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.lineCurrentPointDiameter, 10, accuracy: 0.001)
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.linePointDiameter,
            BodyHealthTrendRange.recentMonth.linePointDiameter
        )
        XCTAssertEqual(
            BodyHealthTrendRange.recentWeek.lineCurrentPointDiameter,
            BodyHealthTrendRange.recentMonth.lineCurrentPointDiameter
        )
    }

    func testHealthTrendRangeUsesThinnerLinesOnLongRanges() {
        XCTAssertEqual(BodyHealthTrendRange.recentWeek.trendLineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentMonth.trendLineWidth, 3, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentSixMonths.trendLineWidth, 2.25, accuracy: 0.001)
        XCTAssertEqual(BodyHealthTrendRange.recentYear.trendLineWidth, 2, accuracy: 0.001)
        XCTAssertLessThan(
            BodyHealthTrendRange.recentYear.trendLineWidth,
            BodyHealthTrendRange.recentSixMonths.trendLineWidth
        )
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
        XCTAssertEqual(averageLineSegments.baseline.upperBound, 200, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.lowerBound, 210, accuracy: 0.001)
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
        XCTAssertEqual(averageLineSegments.baseline.upperBound, 40, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.lowerBound, 50, accuracy: 0.001)
        XCTAssertEqual(averageLineSegments.recent.upperBound, 270, accuracy: 0.001)
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
            wristTemperature: HealthMetricSummary(value: 36.4),
            timeInDaylight: HealthMetricSummary(value: 20),
            steps: HealthMetricSummary(value: 4_200)
        )
        let trends = HealthTrendSnapshot(
            sleep: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 7)]),
            restingHeartRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 61)]),
            bodyMass: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 69.2)]),
            bodyFatPercentage: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 13.1)]),
            heartRateVariability: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 40)]),
            respiratoryRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 14)]),
            oxygenSaturation: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 97)]),
            bodyMassIndex: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 22.1)]),
            activeEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 520)]),
            restingEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 1_700)]),
            exerciseMinutes: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 32)]),
            wristTemperature: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 36.4)]),
            timeInDaylight: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 20)]),
            steps: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 4_200)]),
            sleepHistory: SleepHistorySnapshot(days: [SleepDaySummary(date: date, summary: summary.sleep)])
        )

        let filteredSummary = summary.filtered(by: selection)
        let filteredTrends = trends.filtered(by: selection)

        XCTAssertTrue(filteredSummary.activityRings.isEmpty)
        XCTAssertNil(filteredSummary.sleep.duration)
        XCTAssertNil(filteredSummary.restingHeartRate.value)
        XCTAssertNil(filteredSummary.bodyMass.value)
        XCTAssertNil(filteredSummary.exerciseMinutes.value)
        XCTAssertEqual(filteredSummary.wristTemperature.value, 36.4)
        XCTAssertEqual(filteredSummary.steps.value, 4_200)
        XCTAssertTrue(filteredTrends.sleep.isEmpty)
        XCTAssertTrue(filteredTrends.bodyMass.isEmpty)
        XCTAssertTrue(filteredTrends.exerciseMinutes.isEmpty)
        XCTAssertEqual(filteredTrends.wristTemperature.points.first?.value, 36.4)
        XCTAssertEqual(filteredTrends.steps.points.first?.value, 4_200)
    }

    func testHomeCardOrderRepairsStoredValues() {
        let order = BodyHomeCardKind.storedOrder(from: "sleep,sleep,activeEnergy,unknown")
        let migratedOrder = BodyHomeCardKind.storedOrder(from: "activityRings,exerciseMinutes,workoutDuration,timeInDaylight")

        XCTAssertEqual(Array(order.prefix(2)), [.sleep, .activeEnergy])
        XCTAssertEqual(Array(migratedOrder.prefix(4)), [.activityRings, .exerciseMinutes, .wristTemperature, .timeInDaylight])
        XCTAssertEqual(Set(order), Set(BodyHomeCardKind.defaultOrder))
        XCTAssertEqual(order.count, BodyHomeCardKind.defaultOrder.count)
        XCTAssertTrue(order.contains(.activityRings))
        XCTAssertTrue(order.contains(.exerciseMinutes))
        XCTAssertTrue(order.contains(.wristTemperature))
        XCTAssertTrue(order.contains(.timeInDaylight))
        XCTAssertTrue(order.contains(.steps))
        XCTAssertEqual(
            Array(BodyHomeCardKind.defaultOrder.prefix(5)),
            [.activityRings, .exerciseMinutes, .wristTemperature, .timeInDaylight, .steps]
        )
    }

    func testHomeCardOrderMovesCardsToDropDestination() {
        let order = BodyHomeCardKind.defaultOrder

        let movedDown = BodyHomeCardKind.reordered(order, moving: .sleep, to: .basics)
        XCTAssertEqual(
            Array(movedDown.prefix(7)),
            [.activityRings, .exerciseMinutes, .wristTemperature, .timeInDaylight, .steps, .basics, .sleep]
        )
        XCTAssertEqual(Set(movedDown), Set(order))
        XCTAssertEqual(movedDown.count, order.count)

        let movedUp = BodyHomeCardKind.reordered(order, moving: .activeEnergy, to: .sleep)
        XCTAssertEqual(
            Array(movedUp.prefix(7)),
            [.activityRings, .exerciseMinutes, .wristTemperature, .timeInDaylight, .steps, .activeEnergy, .sleep]
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

    func testHealthTrendSnapshotReturnsDaySeriesForVitalsDayView() throws {
        let date = Date(timeIntervalSince1970: 0)
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
            restingHeartRate: .empty,
            bodyMass: .empty,
            bodyFatPercentage: .empty,
            heartRateVariability: .empty,
            respiratoryRate: .empty,
            oxygenSaturation: .empty,
            bodyMassIndex: .empty,
            activeEnergy: .empty,
            restingEnergy: .empty,
            restingHeartRateDaySamples: restingHeartRateSamples,
            heartRateVariabilityDaySamples: heartRateVariabilitySamples,
            respiratoryRateDaySamples: respiratoryRateSamples,
            oxygenSaturationDaySamples: oxygenSaturationSamples
        )

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
            wristTemperature: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 36.4)]),
            timeInDaylight: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 32)]),
            steps: HealthTrendSeries(points: [HealthTrendDataPoint(date: date, value: 1_212)])
        )

        XCTAssertEqual(HealthMetricKind.exerciseMinutes.id, "exerciseMinutes")
        XCTAssertEqual(HealthMetricKind.wristTemperature.id, "wristTemperature")
        XCTAssertEqual(HealthMetricKind.timeInDaylight.id, "timeInDaylight")
        XCTAssertEqual(HealthMetricKind.steps.id, "steps")
        XCTAssertEqual(summary.exerciseMinutes.value, 77)
        XCTAssertEqual(summary.wristTemperature.value, 36.4)
        XCTAssertEqual(summary.timeInDaylight.value, 32)
        XCTAssertEqual(summary.steps.value, 1_212)
        XCTAssertEqual(trends.series(for: .exerciseMinutes).points.first?.value, 77)
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
        XCTAssertEqual(HealthMetricKind.restingHeartRate.detailHelpText?.title, "About Resting Heart Rate")
        XCTAssertEqual(HealthMetricKind.oxygenSaturation.detailHelpText?.title, "About Blood Oxygen")
        XCTAssertTrue(HealthMetricKind.activeEnergy.detailHelpText?.body.contains("movement") == true)
        XCTAssertEqual(HealthMetricKind.exerciseMinutes.detailHelpText?.title, "About Exercise Minutes")
        XCTAssertEqual(HealthMetricKind.wristTemperature.detailHelpText?.title, "About Wrist Temperature")
        XCTAssertEqual(HealthMetricKind.timeInDaylight.detailHelpText?.title, "About Time In Daylight")
        XCTAssertEqual(HealthMetricKind.steps.detailHelpText?.title, "About Steps")
    }

    func testHealthMetricDataSourceTargetsHomeCardDetailScreens() {
        let sourcedKinds = HealthMetricKind.allCases.filter { $0.detailDataSourceText != nil }

        XCTAssertEqual(
            sourcedKinds,
            [
                .sleep,
                .basics,
                .restingHeartRate,
                .heartRateVariability,
                .respiratoryRate,
                .oxygenSaturation,
                .activeEnergy,
                .restingEnergy,
                .exerciseMinutes,
                .wristTemperature,
                .timeInDaylight,
                .steps
            ]
        )
        XCTAssertEqual(HealthMetricKind.sleep.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.basics.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.restingHeartRate.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.oxygenSaturation.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.activeEnergy.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertEqual(HealthMetricKind.steps.detailDataSourceText?.sourceText, "Apple Health")
        XCTAssertNil(HealthMetricKind.bodyMass.detailDataSourceText)
        XCTAssertNil(HealthMetricKind.bodyMassIndex.detailDataSourceText)
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

    func testSleepScoreCommentSummarizesScoreBand() {
        XCTAssertEqual(SleepScoreSummary.comment(for: 95), "Excellent sleep recovery for this day.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 84), "Strong sleep with small room to improve.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 72), "Decent sleep, but key areas can improve.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 63), "Mixed sleep signals for this day.")
        XCTAssertEqual(SleepScoreSummary.comment(for: 45), "Low sleep score; prioritize recovery tonight.")
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
