//
//  HealthKitWorkoutStoreTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStoreTests: XCTestCase {
    @MainActor
    func testWorkoutStoreKeepsRecentChartWindowToThreeMonths() {
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )
        let store = HealthKitWorkoutStore(initialSnapshot: initialSnapshot)

        XCTAssertEqual(HealthKitWorkoutStore.recentChartMonthCount, 3)
        XCTAssertEqual(store.snapshot(month: 5, year: 2026), initialSnapshot)

        let unloadedSnapshot = store.snapshot(month: 4, year: 2026)
        XCTAssertEqual(unloadedSnapshot.month, 4)
        XCTAssertEqual(unloadedSnapshot.year, 2026)
        XCTAssertEqual(unloadedSnapshot.workoutCount, 0)
        XCTAssertFalse(store.hasLoadedSnapshot(month: 4, year: 2026))
    }

    @MainActor
    func testWorkoutStoreStartsWithCachedHealthDashboardSnapshot() throws {
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )
        let cachedSnapshot = try cachedHealthDashboardSnapshot()

        let store = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: cachedSnapshot
        )

        XCTAssertEqual(store.healthSummary, cachedSnapshot.summary)
        XCTAssertEqual(store.healthTrends, cachedSnapshot.trends)
        XCTAssertEqual(store.activityRingHistory, cachedSnapshot.activityRingHistory)
    }

    func testHealthDashboardSnapshotStoreRoundTripsCachedHomeData() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cachedSnapshot = try cachedHealthDashboardSnapshot()

        HealthDashboardSnapshotStore.save(cachedSnapshot, defaults: defaults)

        XCTAssertEqual(HealthDashboardSnapshotStore.load(defaults: defaults), cachedSnapshot)
    }

    func testHealthDashboardSnapshotStoreLoadsOlderCacheWithoutActivityRingHistory() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let cachedSnapshot = try cachedHealthDashboardSnapshot()
        let legacySnapshot = LegacyHealthDashboardSnapshot(
            summary: cachedSnapshot.summary,
            trends: cachedSnapshot.trends
        )
        let data = try JSONEncoder().encode(legacySnapshot)

        defaults.set(data, forKey: HealthDashboardSnapshotStore.healthDashboardSnapshotKey)

        let loadedSnapshot = try XCTUnwrap(HealthDashboardSnapshotStore.load(defaults: defaults))
        XCTAssertEqual(loadedSnapshot.summary, legacySnapshot.summary)
        XCTAssertEqual(loadedSnapshot.trends, legacySnapshot.trends)
        XCTAssertEqual(loadedSnapshot.activityRingHistory, .empty)
    }

    @MainActor
    func testWorkoutStoreRepairsCachedBoundaryTruncatedActivityRingHistory() throws {
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
        let dashboardSnapshot = HealthDashboardSnapshot(
            summary: .empty,
            trends: .empty,
            activityRingHistory: corruptedHistory
        )
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 4,
            year: 2026,
            workouts: [],
            calendar: calendar
        )

        let store = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: dashboardSnapshot,
            date: currentDate
        )

        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march2, march3])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
    }

    func testHealthKitWorkoutTypeMappingPreservesSpecificActivities() {
        let mappings: [(HKWorkoutActivityType, BodyWorkoutType)] = [
            (.running, .running),
            (.walking, .walking),
            (.traditionalStrengthTraining, .strengthTraining),
            (.functionalStrengthTraining, .functionalStrengthTraining),
            (.pickleball, .pickleball),
            (.pilates, .pilates),
            (.elliptical, .elliptical),
            (.rowing, .rowing),
            (.soccer, .soccer),
            (.tennis, .tennis),
            (.cooldown, .cooldown),
            (.swimBikeRun, .swimBikeRun),
            (.underwaterDiving, .underwaterDiving)
        ]

        for (activityType, bodyType) in mappings {
            XCTAssertEqual(HealthKitWorkoutStore.workoutType(for: activityType), bodyType)
        }
    }

    func testUnknownHealthKitWorkoutTypeFallsBackToOther() throws {
        let unknownActivityType = try XCTUnwrap(HKWorkoutActivityType(rawValue: 81))
        XCTAssertEqual(HealthKitWorkoutStore.workoutType(for: unknownActivityType), .other)
    }

    func testMergedSleepDurationDoesNotDoubleCountOverlaps() throws {
        let calendar = Calendar.bodyGregorian
        let firstStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
        let firstEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 5)))
        let secondStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 3)))
        let secondEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 7)))
        let thirdStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8)))
        let thirdEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 9, minute: 30)))

        let duration = HealthKitWorkoutStore.mergedSleepDuration(
            intervals: [
                (start: secondStart, end: secondEnd),
                (start: firstStart, end: firstEnd),
                (start: thirdStart, end: thirdEnd)
            ]
        )

        XCTAssertEqual(duration, 27_000)
    }

    func testSleepDurationTextDoesNotRoundDownPartialMinutes() {
        let sevenHoursTwentyMinutesOneSecond: TimeInterval = (7 * 3_600) + (20 * 60) + 1

        XCTAssertEqual(
            BodyValueFormat.sleepDurationText(for: sevenHoursTwentyMinutesOneSecond),
            "7h 21m"
        )
    }

    func testSleepDurationExcludesAwakeStageSamples() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5)))
        let awakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5)))
        let awakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5, minute: 15)))
        let remStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5, minute: 15)))
        let remEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7)))

        let duration = HealthKitWorkoutStore.sleepDuration(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: awakeStart, end: awakeEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: remStart, end: remEnd)
            ]
        )

        XCTAssertEqual(duration, 17_100)
    }

    private func cachedHealthDashboardSnapshot() throws -> HealthDashboardSnapshot {
        let calendar = Calendar.bodyGregorian
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let sleepStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
        let sleepEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 8)))
        let summary = HealthSummarySnapshot(
            activityRings: ActivityRingSummary(
                move: ActivityRingMetric(value: 450, goal: 600),
                exercise: ActivityRingMetric(value: 45, goal: 30),
                stand: ActivityRingMetric(value: 9, goal: 12)
            ),
            sleep: SleepSummary(
                duration: 7 * 60 * 60,
                stageSnapshot: SleepStageSnapshot(
                    date: day,
                    segments: [
                        SleepStageSegment(stage: .core, startDate: sleepStart, endDate: sleepEnd)
                    ]
                ),
                vitals: SleepVitalsSummary(
                    heartRate: 58,
                    heartRateVariability: 62,
                    respiratoryRate: 14,
                    oxygenSaturation: 97,
                    wristTemperatureCelsius: 36.4
                )
            ),
            restingHeartRate: HealthMetricSummary(value: 61),
            bodyMass: HealthMetricSummary(value: 69.25),
            bodyFatPercentage: HealthMetricSummary(value: 13.2),
            heartRateVariability: HealthMetricSummary(value: 42),
            respiratoryRate: HealthMetricSummary(value: 14),
            oxygenSaturation: HealthMetricSummary(value: 98),
            bodyMassIndex: HealthMetricSummary(value: 22.1),
            activeEnergy: HealthMetricSummary(value: 530),
            restingEnergy: HealthMetricSummary(value: 1_720)
        )
        let trends = HealthTrendSnapshot(
            sleep: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 7)]),
            restingHeartRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 61)]),
            bodyMass: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 69.25)]),
            bodyFatPercentage: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 13.2)]),
            heartRateVariability: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 42)]),
            respiratoryRate: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 14)]),
            oxygenSaturation: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 98)]),
            bodyMassIndex: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 22.1)]),
            activeEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 530)]),
            restingEnergy: HealthTrendSeries(points: [HealthTrendDataPoint(date: day, value: 1_720)])
        )

        let activityRingHistory = ActivityRingHistorySnapshot(days: [
            ActivityRingDaySummary(date: day, summary: summary.activityRings)
        ])

        return HealthDashboardSnapshot(
            summary: summary,
            trends: trends,
            activityRingHistory: activityRingHistory
        )
    }

    private struct LegacyHealthDashboardSnapshot: Codable {
        var summary: HealthSummarySnapshot
        var trends: HealthTrendSnapshot
    }
}
