//
//  BodySiriAnswerBuilderTests.swift
//  BodyTests
//
//  Covers the pure answer builder behind Body's Siri intents: which snapshot
//  each answer reads, when it is available, stale, partial or unavailable, and
//  what it says.
//

import XCTest
@testable import Body

final class BodySiriAnswerBuilderTests: XCTestCase {

    private let calendar = Calendar.bodyGregorian

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    // MARK: - Fixtures

    private func dashboard(
        readiness: ReadinessSummary = .unavailable,
        warnings: [MetricWarningEvent] = []
    ) -> HealthDashboardSnapshot {
        var summary = HealthSummarySnapshot.empty
        summary.readiness = readiness
        summary.metricWarnings = warnings
        return HealthDashboardSnapshot(summary: summary, trends: .empty)
    }

    private func readinessSummary(
        score: Int?,
        status: ReadinessStatus,
        drivers: [ReadinessDriver] = []
    ) -> ReadinessSummary {
        ReadinessSummary(
            score: score,
            status: status,
            confidence: .high,
            components: [
                ReadinessComponent(kind: .sleep, score: 80, weight: 1, message: ""),
                ReadinessComponent(kind: .autonomic, score: 80, weight: 1, message: "")
            ],
            drivers: drivers
        )
    }

    private func widget(
        generatedDate: Date,
        trends: [HealthWidgetMetricTrend],
        sleepNight: Date? = nil
    ) -> HealthWidgetSnapshot {
        HealthWidgetSnapshot(
            generatedDate: generatedDate,
            metricTrends: trends,
            sleep: HealthWidgetSleepStages(
                night: sleepNight,
                sourceName: "Apple Watch",
                segments: sleepNight == nil
                    ? []
                    : [
                        HealthWidgetSleepSegment(
                            stage: .core,
                            startDate: sleepNight!,
                            endDate: sleepNight!.addingTimeInterval(3_600)
                        )
                    ]
            )
        )
    }

    private func trend(
        _ metric: HealthWidgetMetric,
        _ displayValues: [HealthWidgetDisplayValue]
    ) -> HealthWidgetMetricTrend {
        HealthWidgetMetricTrend(
            metric: metric,
            primarySourceName: nil,
            week: .empty,
            month: .empty,
            displayValues: displayValues
        )
    }

    // MARK: - Empty caches

    func testNoSnapshotsGivesUnavailableAnswersWithTheOpenBodyWording() {
        let bundle = BodySiriSnapshotBundle(now: date(2026, 9, 17, 9, 0))

        for answer in [
            BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.metric(.heartRateVariability, bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.warnings(bundle: bundle, calendar: calendar)
        ] {
            XCTAssertEqual(answer.availability, .unavailable)
            XCTAssertFalse(answer.hasValue)
            XCTAssertNil(answer.valueText)
            XCTAssertTrue(answer.spoken.contains("Open Body"))
        }
    }

    // MARK: - Readiness

    func testReadinessSpeaksScoreStatusAndHeroExplanation() {
        let now = date(2026, 9, 17, 9, 0)
        var summary = readinessSummary(score: 82, status: .high)
        summary.activityDrainMorningScore = 91
        summary.activityDrainPoints = 9
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(readiness: summary),
            dashboardAsOf: date(2026, 9, 17, 8, 0),
            now: now
        )

        let answer = BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.valueText, "82")
        XCTAssertEqual(answer.unit, BodySiriAnswerBuilder.readinessUnit)
        XCTAssertTrue(answer.spoken.contains("82"))
        XCTAssertTrue(answer.spoken.contains(ReadinessStatus.high.title))
        XCTAssertTrue(answer.spoken.contains(summary.heroExplanation))
        XCTAssertFalse(answer.spoken.contains("as of"))
    }

    func testReadinessOlderThanSixHoursOnTheSameDayIsStaleAndSaysAsOf() {
        let now = date(2026, 9, 17, 18, 0)
        let asOf = date(2026, 9, 17, 7, 12)
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(readiness: readinessSummary(score: 82, status: .high)),
            dashboardAsOf: asOf,
            now: now
        )

        let answer = BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .stale)
        XCTAssertTrue(answer.hasValue)
        XCTAssertEqual(answer.asOf, asOf)
        XCTAssertTrue(answer.spoken.contains("as of"))
    }

    func testReadinessFromAnotherDayIsUnavailable() {
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(readiness: readinessSummary(score: 82, status: .high)),
            dashboardAsOf: date(2026, 9, 16, 8, 0),
            now: date(2026, 9, 17, 9, 0)
        )

        XCTAssertEqual(
            BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar).availability,
            .unavailable
        )
    }

    func testReadinessWithoutAScoreIsUnavailable() {
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(readiness: readinessSummary(score: nil, status: .unavailable)),
            dashboardAsOf: date(2026, 9, 17, 8, 0),
            now: date(2026, 9, 17, 9, 0)
        )

        XCTAssertEqual(
            BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar).availability,
            .unavailable
        )
    }

    func testFreshWidgetWithAnOldDashboardAnswersMetricsButNotReadiness() {
        let now = date(2026, 9, 17, 9, 0)
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(readiness: readinessSummary(score: 82, status: .high)),
            dashboardAsOf: date(2026, 9, 15, 8, 0),
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [trend(.heartRateVariability, [HealthWidgetDisplayValue(value: "45", unit: "ms")])]
            ),
            now: now
        )

        XCTAssertEqual(
            BodySiriAnswerBuilder.metric(.heartRateVariability, bundle: bundle, calendar: calendar).availability,
            .available
        )
        XCTAssertEqual(
            BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar).availability,
            .unavailable
        )
    }

    func testReadinessMetricCaseDelegatesToTheReadinessAnswer() {
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(readiness: readinessSummary(score: 82, status: .high)),
            dashboardAsOf: date(2026, 9, 17, 8, 0),
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [trend(.readiness, [HealthWidgetDisplayValue(value: "70", unit: "%")])]
            ),
            now: date(2026, 9, 17, 9, 0)
        )

        XCTAssertEqual(
            BodySiriAnswerBuilder.metric(.readiness, bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar)
        )
    }

    // MARK: - Metrics

    func testHeartRateVariabilityReadsTheDisplayValue() {
        let bundle = BodySiriSnapshotBundle(
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [trend(.heartRateVariability, [HealthWidgetDisplayValue(value: "45", unit: "ms")])]
            ),
            now: date(2026, 9, 17, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.metric(.heartRateVariability, bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.valueText, "45")
        XCTAssertEqual(answer.unit, "ms")
        XCTAssertTrue(answer.spoken.contains("45 ms"))
    }

    func testMissingTrendAndPlaceholderValueAreUnavailable() {
        let now = date(2026, 9, 17, 9, 0)
        let missing = BodySiriSnapshotBundle(
            widget: widget(generatedDate: date(2026, 9, 17, 8, 30), trends: []),
            now: now
        )
        let placeholder = BodySiriSnapshotBundle(
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [trend(.restingHeartRate, [HealthWidgetDisplayValue(value: "--", unit: "")])]
            ),
            now: now
        )

        XCTAssertEqual(
            BodySiriAnswerBuilder.metric(.heartRateVariability, bundle: missing, calendar: calendar).availability,
            .unavailable
        )
        XCTAssertEqual(
            BodySiriAnswerBuilder.metric(.restingHeartRate, bundle: placeholder, calendar: calendar).availability,
            .unavailable
        )
    }

    func testAMetricFromLastNightIsStaleAndSleepIsSanitized() {
        let now = date(2026, 9, 17, 0, 10)
        let generated = date(2026, 9, 16, 23, 50)
        let bundle = BodySiriSnapshotBundle(
            widget: widget(
                generatedDate: generated,
                trends: [
                    trend(.heartRateVariability, [HealthWidgetDisplayValue(value: "45", unit: "ms")]),
                    trend(
                        .sleep,
                        [
                            HealthWidgetDisplayValue(value: "82", unit: "pts"),
                            HealthWidgetDisplayValue(value: "7h 12m", unit: "")
                        ]
                    )
                ],
                sleepNight: date(2026, 9, 16)
            ),
            now: now
        )

        let hrv = BodySiriAnswerBuilder.metric(.heartRateVariability, bundle: bundle, calendar: calendar)
        XCTAssertEqual(hrv.availability, .stale)
        XCTAssertEqual(hrv.asOf, generated)
        XCTAssertTrue(hrv.spoken.contains("snapshot taken"))

        let sleep = BodySiriAnswerBuilder.metric(.sleep, bundle: bundle, calendar: calendar)
        XCTAssertEqual(sleep.availability, .unavailable)
        XCTAssertNil(sleep.valueText)
    }

    func testSleepSpeaksBothDisplayValues() {
        let night = date(2026, 9, 17)
        let bundle = BodySiriSnapshotBundle(
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [
                    trend(
                        .sleep,
                        [
                            HealthWidgetDisplayValue(value: "82", unit: "pts"),
                            HealthWidgetDisplayValue(value: "7h 12m", unit: "")
                        ]
                    )
                ],
                sleepNight: night
            ),
            now: date(2026, 9, 17, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.metric(.sleep, bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.valueText, "82")
        XCTAssertTrue(answer.spoken.contains("82 pts"))
        XCTAssertTrue(answer.spoken.contains("7h 12m"))
    }

    func testSkinTemperatureSpeaksDeviationAndActual() {
        let bundle = BodySiriSnapshotBundle(
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [
                    trend(
                        .wristTemperature,
                        [
                            HealthWidgetDisplayValue(value: "+0.3", unit: "°C"),
                            HealthWidgetDisplayValue(value: "36.7", unit: "°C")
                        ]
                    )
                ]
            ),
            now: date(2026, 9, 17, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.metric(.wristTemperature, bundle: bundle, calendar: calendar)

        XCTAssertTrue(answer.spoken.contains("+0.3 °C"))
        XCTAssertTrue(answer.spoken.contains("36.7 °C"))
    }

    // MARK: - Warnings

    func testWarningsWithTodaysDashboardAndNoEventsIsAvailableAndEmpty() {
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(),
            dashboardAsOf: date(2026, 9, 17, 8, 0),
            now: date(2026, 9, 17, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.warnings(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertTrue(answer.items.isEmpty)
        XCTAssertTrue(answer.spoken.contains("No warnings in Body's cached data"))
    }

    func testWarningEndingTodayIsNamedAndYesterdaysIsExcluded() {
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(
                warnings: [
                    MetricWarningEvent(
                        kind: .highRespiratoryRate,
                        startDate: date(2026, 9, 17, 3, 0),
                        endDate: date(2026, 9, 17, 3, 30),
                        extremeValue: 24,
                        sampleCount: 4
                    ),
                    MetricWarningEvent(
                        kind: .lowBloodOxygen,
                        startDate: date(2026, 9, 16, 2, 0),
                        endDate: date(2026, 9, 16, 2, 30),
                        extremeValue: 88,
                        sampleCount: 3
                    )
                ]
            ),
            dashboardAsOf: date(2026, 9, 17, 8, 0),
            now: date(2026, 9, 17, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.warnings(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.items, ["High Respiratory Rate"])
        XCTAssertEqual(answer.count, 1)
        XCTAssertTrue(answer.spoken.contains("High Respiratory Rate"))
        XCTAssertFalse(answer.spoken.contains("Low Blood Oxygen"))
    }

    func testWarningsWithoutATodayDashboardAreUnavailable() {
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(),
            dashboardAsOf: date(2026, 9, 16, 8, 0),
            now: date(2026, 9, 17, 9, 0)
        )

        XCTAssertEqual(
            BodySiriAnswerBuilder.warnings(bundle: bundle, calendar: calendar).availability,
            .unavailable
        )
    }

    // MARK: - Workouts

    /// Sunday 2026-11-29 through Saturday 2026-12-05: the week spans two months.
    private var monthSpanningNow: Date { date(2026, 12, 2, 9, 0) }

    private func monthSnapshot(
        month: Int,
        year: Int,
        workouts: [WorkoutSummary],
        generatedAt: Date
    ) -> WorkoutMonthSnapshot {
        WorkoutMonthSnapshot.make(
            month: month,
            year: year,
            workouts: workouts,
            calendar: calendar,
            generatedAt: generatedAt
        )
    }

    func testWorkoutsAcrossAMonthBoundaryCountAndSumBothMonths() {
        let now = monthSpanningNow
        let bundle = BodySiriSnapshotBundle(
            currentMonthWorkouts: monthSnapshot(
                month: 12,
                year: 2026,
                workouts: [
                    WorkoutSummary(type: .running, startDate: date(2026, 12, 1, 7, 0), duration: 1_800),
                    WorkoutSummary(type: .cycling, startDate: date(2026, 12, 2, 7, 0), duration: 2_400)
                ],
                generatedAt: date(2026, 12, 2, 8, 0)
            ),
            previousMonthWorkouts: monthSnapshot(
                month: 11,
                year: 2026,
                workouts: [
                    WorkoutSummary(type: .running, startDate: date(2026, 11, 29, 7, 0), duration: 3_600)
                ],
                generatedAt: date(2026, 12, 1, 8, 0)
            ),
            now: now
        )

        let answer = BodySiriAnswerBuilder.recentWorkouts(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.count, 3)
        XCTAssertEqual(answer.valueText, "3")
        XCTAssertEqual(answer.items, ["Run", "Ride"])
        XCTAssertTrue(answer.spoken.contains("3"))
        // 30 + 40 + 60 minutes.
        XCTAssertTrue(answer.spoken.contains("2 hours"))
        XCTAssertTrue(answer.spoken.contains("10 minutes"))
    }

    func testWorkoutsWithAMissingSpannedMonthArePartial() {
        let bundle = BodySiriSnapshotBundle(
            currentMonthWorkouts: monthSnapshot(
                month: 12,
                year: 2026,
                workouts: [
                    WorkoutSummary(type: .running, startDate: date(2026, 12, 1, 7, 0), duration: 1_800)
                ],
                generatedAt: date(2026, 12, 2, 8, 0)
            ),
            now: monthSpanningNow
        )

        let answer = BodySiriAnswerBuilder.recentWorkouts(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .partial)
        XCTAssertNil(answer.valueText)
        XCTAssertNil(answer.count)
        XCTAssertFalse(answer.hasValue)
        XCTAssertTrue(answer.spoken.contains("only part of this week's workouts"))
    }

    func testAnEmptyWeekWithBothMonthsCachedIsAvailableWithZero() {
        let bundle = BodySiriSnapshotBundle(
            currentMonthWorkouts: monthSnapshot(
                month: 12,
                year: 2026,
                workouts: [],
                generatedAt: date(2026, 12, 2, 8, 0)
            ),
            previousMonthWorkouts: monthSnapshot(
                month: 11,
                year: 2026,
                workouts: [],
                generatedAt: date(2026, 12, 1, 8, 0)
            ),
            now: monthSpanningNow
        )

        let answer = BodySiriAnswerBuilder.recentWorkouts(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.count, 0)
        XCTAssertEqual(answer.valueText, "0")
        XCTAssertTrue(answer.spoken.contains("No workouts logged in Body this week yet."))
    }

    /// Wednesday 2026-09-30: the week runs into October, which has no
    /// snapshot yet. Coverage only has to reach today.
    func testAWeekRunningIntoNextMonthOnlyNeedsCoverageThroughToday() {
        let bundle = BodySiriSnapshotBundle(
            currentMonthWorkouts: monthSnapshot(
                month: 9,
                year: 2026,
                workouts: [
                    WorkoutSummary(type: .running, startDate: date(2026, 9, 28, 7, 0), duration: 1_800),
                    WorkoutSummary(type: .cycling, startDate: date(2026, 9, 30, 7, 0), duration: 2_400)
                ],
                generatedAt: date(2026, 9, 30, 8, 0)
            ),
            now: date(2026, 9, 30, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.recentWorkouts(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.count, 2)
    }

    func testASingleMonthWeekOnlyNeedsTheCurrentMonth() {
        let bundle = BodySiriSnapshotBundle(
            currentMonthWorkouts: monthSnapshot(
                month: 9,
                year: 2026,
                workouts: [
                    WorkoutSummary(type: .running, startDate: date(2026, 9, 15, 7, 0), duration: 1_800)
                ],
                generatedAt: date(2026, 9, 17, 8, 0)
            ),
            now: date(2026, 9, 17, 9, 0)
        )

        let answer = BodySiriAnswerBuilder.recentWorkouts(bundle: bundle, calendar: calendar)

        XCTAssertEqual(answer.availability, .available)
        XCTAssertEqual(answer.count, 1)
    }

    // MARK: - Mapping

    func testEveryMetricMapsToAWidgetMetricAndATitle() {
        let mapped = Set(BodySiriMetric.allCases.map(\.widgetMetric))
        XCTAssertEqual(mapped.count, BodySiriMetric.allCases.count)

        for metric in BodySiriMetric.allCases {
            XCTAssertEqual(metric.title, metric.widgetMetric.title)
            XCTAssertFalse(metric.title.isEmpty)
        }
    }

    // MARK: - Copy

    func testAnswersNeverUseDashesAsPunctuation() {
        let now = date(2026, 9, 17, 18, 0)
        let bundle = BodySiriSnapshotBundle(
            dashboard: dashboard(
                readiness: readinessSummary(score: 82, status: .high),
                warnings: [
                    MetricWarningEvent(
                        kind: .highHeartRate,
                        startDate: date(2026, 9, 17, 3, 0),
                        endDate: date(2026, 9, 17, 3, 30),
                        extremeValue: 140,
                        sampleCount: 5
                    )
                ]
            ),
            dashboardAsOf: date(2026, 9, 17, 7, 12),
            widget: widget(
                generatedDate: date(2026, 9, 17, 8, 30),
                trends: [trend(.heartRateVariability, [HealthWidgetDisplayValue(value: "45", unit: "ms")])]
            ),
            currentMonthWorkouts: monthSnapshot(
                month: 9,
                year: 2026,
                workouts: [
                    WorkoutSummary(type: .running, startDate: date(2026, 9, 15, 7, 0), duration: 1_800)
                ],
                generatedAt: date(2026, 9, 17, 8, 0)
            ),
            now: now
        )

        let answers = [
            BodySiriAnswerBuilder.readiness(bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.metric(.heartRateVariability, bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.warnings(bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.recentWorkouts(bundle: bundle, calendar: calendar),
            BodySiriAnswerBuilder.unavailableAnswer(title: "Readiness")
        ]

        for answer in answers {
            for text in [answer.spoken, answer.supporting] {
                XCTAssertFalse(text.contains("—"), text)
                XCTAssertFalse(text.contains(" - "), text)
            }
        }
    }
}
