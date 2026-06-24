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

    func testHealthPermissionSelectionLimitsHealthKitReadTypes() throws {
        let readTypes = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.steps, .wristTemperature])
        )

        XCTAssertTrue(readTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))))
        XCTAssertTrue(readTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature))))
        XCTAssertFalse(readTypes.contains(HKObjectType.workoutType()))
        XCTAssertFalse(readTypes.contains(HKObjectType.activitySummaryType()))
        XCTAssertFalse(readTypes.contains(try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))))
        XCTAssertFalse(readTypes.contains(try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))))
    }

    func testHealthDashboardSnapshotStoreWritesCachedHomeDataToFileNotUserDefaults() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporaryHealthDashboardSnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let cachedSnapshot = try cachedHealthDashboardSnapshot()

        HealthDashboardSnapshotStore.save(cachedSnapshot, defaults: defaults, fileURL: fileURL)

        XCTAssertNil(defaults.data(forKey: HealthDashboardSnapshotStore.healthDashboardSnapshotKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: fileURL), cachedSnapshot)
    }

    func testHealthDashboardSnapshotStoreMigratesOlderUserDefaultsCacheToFile() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let fileURL = temporaryHealthDashboardSnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        let cachedSnapshot = try cachedHealthDashboardSnapshot()
        let legacySnapshot = LegacyHealthDashboardSnapshot(
            summary: cachedSnapshot.summary,
            trends: cachedSnapshot.trends
        )
        let data = try JSONEncoder().encode(legacySnapshot)

        defaults.set(data, forKey: HealthDashboardSnapshotStore.healthDashboardSnapshotKey)

        let loadedSnapshot = try XCTUnwrap(HealthDashboardSnapshotStore.load(defaults: defaults, fileURL: fileURL))
        XCTAssertEqual(loadedSnapshot.summary, legacySnapshot.summary)
        XCTAssertEqual(loadedSnapshot.trends, legacySnapshot.trends)
        XCTAssertEqual(loadedSnapshot.activityRingHistory, .empty)
        XCTAssertNil(defaults.data(forKey: HealthDashboardSnapshotStore.healthDashboardSnapshotKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDashboardAndWorkoutSnapshotStoresCanDeleteCachedFiles() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let dashboardFileURL = temporaryHealthDashboardSnapshotFileURL()
        let workoutFileURL = temporaryWorkoutSnapshotFileURL()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dashboardFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: workoutFileURL.deletingLastPathComponent())
        }
        let dashboardSnapshot = try cachedHealthDashboardSnapshot()
        let workoutSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [workout(day: 11, type: .running, duration: 2_100)],
            calendar: .bodyGregorian
        )

        HealthDashboardSnapshotStore.save(dashboardSnapshot, defaults: defaults, fileURL: dashboardFileURL)
        WorkoutSnapshotStore.save(workoutSnapshot, fileURL: workoutFileURL)

        XCTAssertTrue(HealthDashboardSnapshotStore.exists(fileURL: dashboardFileURL))
        XCTAssertTrue(WorkoutSnapshotStore.exists(fileURL: workoutFileURL))

        HealthDashboardSnapshotStore.delete(defaults: defaults, fileURL: dashboardFileURL)
        WorkoutSnapshotStore.delete(fileURL: workoutFileURL)

        XCTAssertFalse(HealthDashboardSnapshotStore.exists(fileURL: dashboardFileURL))
        XCTAssertFalse(WorkoutSnapshotStore.exists(fileURL: workoutFileURL))
    }

    @MainActor
    func testWorkoutStoreClearLocalCacheResetsInMemorySnapshotsAndStatus() throws {
        let calendar = Calendar.bodyGregorian
        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [workout(day: 11, type: .running, duration: 2_100)],
            calendar: calendar
        )
        let store = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: try cachedHealthDashboardSnapshot()
        )

        XCTAssertFalse(store.cacheStatus.isEmpty)
        XCTAssertEqual(store.cacheStatus.summaryText, "Cached")

        store.clearLocalCache(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16))))

        XCTAssertEqual(store.snapshot.workoutCount, 0)
        XCTAssertTrue(store.healthSummary.isEmpty)
        XCTAssertTrue(store.healthTrends.isEmpty)
        XCTAssertTrue(store.activityRingHistory.isEmpty)
        XCTAssertTrue(store.cacheStatus.isEmpty)
        XCTAssertEqual(store.cacheStatus.summaryText, "Empty")
        XCTAssertEqual(store.healthSyncStatusSummaryText, "Not Synced")
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

    func testActivityRingHistoryRemovesLoadedMonthsOlderThanEarliestDataKeepingGapMonths() throws {
        let calendar = Calendar.bodyGregorian
        let january5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)))
        let march8 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let history = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: january5, summary: summary),
                ActivityRingDaySummary(date: march8, summary: summary)
            ],
            loadedMonthKeys: [
                ActivityRingMonthKey(month: 11, year: 2025),
                ActivityRingMonthKey(month: 12, year: 2025),
                ActivityRingMonthKey(month: 1, year: 2026),
                ActivityRingMonthKey(month: 2, year: 2026),
                ActivityRingMonthKey(month: 3, year: 2026)
            ]
        )

        let repaired = history.removingLoadedMonthsOlderThanEarliestData(date: currentDate, calendar: calendar)

        XCTAssertEqual(repaired.days, history.days)
        XCTAssertEqual(repaired.loadedMonthKeys, [
            ActivityRingMonthKey(month: 1, year: 2026),
            ActivityRingMonthKey(month: 2, year: 2026),
            ActivityRingMonthKey(month: 3, year: 2026)
        ])
    }

    func testActivityRingHistoryRemovingOlderLoadedMonthsKeepsRecentWindowWhenNoData() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        let history = ActivityRingHistorySnapshot(
            days: [],
            loadedMonthKeys: [
                ActivityRingMonthKey(month: 1, year: 2026),
                ActivityRingMonthKey(month: 4, year: 2026),
                ActivityRingMonthKey(month: 6, year: 2026)
            ]
        )

        let repaired = history.removingLoadedMonthsOlderThanEarliestData(
            date: currentDate,
            calendar: calendar,
            keepingRecentMonthCount: 3
        )

        XCTAssertEqual(repaired.loadedMonthKeys, [
            ActivityRingMonthKey(month: 4, year: 2026),
            ActivityRingMonthKey(month: 6, year: 2026)
        ])
    }

    func testPreviousActivityRingMonthCandidatesWalksBackFromEarliestKnownKey() throws {
        let calendar = Calendar.bodyGregorian

        let candidates = HealthKitWorkoutStore.previousActivityRingMonthCandidates(
            loadedKeys: [
                ActivityRingMonthKey(month: 5, year: 2026),
                ActivityRingMonthKey(month: 4, year: 2026)
            ],
            exhaustedKeys: [ActivityRingMonthKey(month: 3, year: 2026)],
            limit: 3,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            ActivityRingMonthKey(month: 2, year: 2026),
            ActivityRingMonthKey(month: 1, year: 2026),
            ActivityRingMonthKey(month: 12, year: 2025)
        ])
    }

    func testPreviousActivityRingMonthCandidatesSeedsFromDateWhenNothingIsKnown() throws {
        let calendar = Calendar.bodyGregorian
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11)))

        let candidates = HealthKitWorkoutStore.previousActivityRingMonthCandidates(
            loadedKeys: [],
            exhaustedKeys: [],
            limit: 2,
            date: currentDate,
            calendar: calendar
        )

        XCTAssertEqual(candidates, [
            ActivityRingMonthKey(month: 5, year: 2026),
            ActivityRingMonthKey(month: 4, year: 2026)
        ])
    }

    func testActivityRingMonthKeysBetweenReturnsExclusiveRangeOldestFirst() {
        let calendar = Calendar.bodyGregorian

        let keys = HealthKitWorkoutStore.activityRingMonthKeys(
            after: ActivityRingMonthKey(month: 11, year: 2025),
            before: ActivityRingMonthKey(month: 3, year: 2026),
            calendar: calendar
        )

        XCTAssertEqual(keys, [
            ActivityRingMonthKey(month: 12, year: 2025),
            ActivityRingMonthKey(month: 1, year: 2026),
            ActivityRingMonthKey(month: 2, year: 2026)
        ])
    }

    func testActivityRingMonthKeysBetweenAdjacentOrInvertedMonthsIsEmpty() {
        let calendar = Calendar.bodyGregorian

        XCTAssertTrue(HealthKitWorkoutStore.activityRingMonthKeys(
            after: ActivityRingMonthKey(month: 4, year: 2026),
            before: ActivityRingMonthKey(month: 5, year: 2026),
            calendar: calendar
        ).isEmpty)

        XCTAssertTrue(HealthKitWorkoutStore.activityRingMonthKeys(
            after: ActivityRingMonthKey(month: 5, year: 2026),
            before: ActivityRingMonthKey(month: 1, year: 2026),
            calendar: calendar
        ).isEmpty)
    }

    func testActivityRingBackfillStartDateSpansTenYearsAndClampsToWatchEra() throws {
        let calendar = Calendar.bodyGregorian

        let recentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: recentDate, calendar: calendar),
            calendar.date(from: DateComponents(year: 2016, month: 6, day: 1))
        )

        let earlyDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 1, day: 15)))
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: earlyDate, calendar: calendar),
            calendar.date(from: DateComponents(year: 2014, month: 9, day: 1))
        )
    }

    func testActivityRingMonthKeySpanIsInclusiveOnBothEnds() throws {
        let calendar = Calendar.bodyGregorian
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 11, day: 20)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 2, day: 3)))

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingMonthKeySpan(from: start, to: end, calendar: calendar),
            [
                ActivityRingMonthKey(month: 11, year: 2024),
                ActivityRingMonthKey(month: 12, year: 2024),
                ActivityRingMonthKey(month: 1, year: 2025),
                ActivityRingMonthKey(month: 2, year: 2025)
            ]
        )

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingMonthKeySpan(from: end, to: end, calendar: calendar),
            [ActivityRingMonthKey(month: 2, year: 2025)]
        )

        XCTAssertTrue(HealthKitFetchEngine.activityRingMonthKeySpan(from: end, to: start, calendar: calendar).isEmpty)
    }

    func testActivityRingBackfillCompletedFlagPersistsAndClears() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(HealthDashboardSnapshotStore.loadActivityRingBackfillCompleted(defaults: defaults))

        HealthDashboardSnapshotStore.saveActivityRingBackfillCompleted(defaults: defaults)
        XCTAssertTrue(HealthDashboardSnapshotStore.loadActivityRingBackfillCompleted(defaults: defaults))

        HealthDashboardSnapshotStore.clearActivityRingBackfillCompleted(defaults: defaults)
        XCTAssertFalse(HealthDashboardSnapshotStore.loadActivityRingBackfillCompleted(defaults: defaults))
    }

    @MainActor
    func testNeedsInitialHealthDataLoadReflectsCacheAndRefreshState() throws {
        // The store reads the persisted refresh timestamp from standard
        // defaults at init; park it so a previous run on this host cannot
        // mask the fresh-install state.
        let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        defer {
            if let preservedRefreshDate {
                HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(preservedRefreshDate)
            }
        }

        let initialSnapshot = WorkoutMonthSnapshot.make(
            month: 5,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )

        let emptyStore = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: .empty
        )
        XCTAssertTrue(emptyStore.needsInitialHealthDataLoad)

        let cachedStore = HealthKitWorkoutStore(
            initialSnapshot: initialSnapshot,
            initialHealthDashboardSnapshot: try cachedHealthDashboardSnapshot()
        )
        XCTAssertFalse(cachedStore.needsInitialHealthDataLoad)
    }

    @MainActor
    func testPassiveLoadsStayIdleUntilFirstHealthDataLoad() async throws {
        let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        defer {
            if let preservedRefreshDate {
                HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(preservedRefreshDate)
            }
        }

        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty
        )
        XCTAssertTrue(store.needsInitialHealthDataLoad)

        let didLoad = await store.loadMonthIfNeeded(month: 4, year: 2026)
        XCTAssertFalse(didLoad)
        XCTAssertFalse(store.hasLoadedSnapshot(month: 4, year: 2026))

        await store.loadRecentWorkoutMonthsIfNeeded()
        XCTAssertTrue(store.loadingMonthKeys.isEmpty)

        await store.loadPreviousActivityRingMonthIfNeeded()
        XCTAssertTrue(store.activityRingHistory.isEmpty)
        XCTAssertTrue(store.loadingActivityRingMonthKeys.isEmpty)
    }

    @MainActor
    func testWorkoutStoreInitStripsStaleLoadedMonthsOlderThanEarliestData() throws {
        let calendar = Calendar.bodyGregorian
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let march2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)))
        let march3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3)))
        let currentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10)))
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let pollutedHistory = ActivityRingHistorySnapshot(
            days: [
                ActivityRingDaySummary(date: march2, summary: summary),
                ActivityRingDaySummary(date: march3, summary: summary)
            ],
            loadedMonthKeys: [
                ActivityRingMonthKey(month: 1, year: 2024),
                ActivityRingMonthKey(month: 2, year: 2024),
                marchKey
            ]
        )
        let dashboardSnapshot = HealthDashboardSnapshot(
            summary: .empty,
            trends: .empty,
            activityRingHistory: pollutedHistory
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

    func testSleepStageSegmentsShowSubMinuteAwakeSamplesByDefault() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4)))
        let subMinuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4, minute: 10)))
        let subMinuteAwakeEnd = subMinuteAwakeStart.addingTimeInterval(45)
        let minuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 5, minute: 20)))
        let minuteAwakeEnd = minuteAwakeStart.addingTimeInterval(60)

        let segments = HealthKitFetchEngine.sleepStageSegments(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: subMinuteAwakeStart, end: subMinuteAwakeEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: minuteAwakeStart, end: minuteAwakeEnd)
            ]
        )

        XCTAssertEqual(segments.map(\.stage), [SleepStage.core, .awake, .awake])
        XCTAssertEqual(segments[0].startDate, coreStart)
        XCTAssertEqual(segments[0].endDate, coreEnd)
        XCTAssertEqual(segments[1].startDate, subMinuteAwakeStart)
        XCTAssertEqual(segments[1].endDate, subMinuteAwakeEnd)
        XCTAssertEqual(segments[2].startDate, minuteAwakeStart)
        XCTAssertEqual(segments[2].endDate, minuteAwakeEnd)
    }

    func testSleepStageSegmentsCanHideSubMinuteAwakeSamples() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4)))
        let subMinuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4, minute: 10)))
        let subMinuteAwakeEnd = subMinuteAwakeStart.addingTimeInterval(45)
        let minuteAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 5, minute: 20)))
        let minuteAwakeEnd = minuteAwakeStart.addingTimeInterval(60)

        let segments = HealthKitFetchEngine.sleepStageSegments(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: subMinuteAwakeStart, end: subMinuteAwakeEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: minuteAwakeStart, end: minuteAwakeEnd)
            ],
            showsSubMinuteAwakeStages: false
        )

        XCTAssertEqual(segments.map(\.stage), [SleepStage.core, .awake])
        XCTAssertEqual(segments[0].startDate, coreStart)
        XCTAssertEqual(segments[0].endDate, coreEnd)
        XCTAssertEqual(segments[1].startDate, minuteAwakeStart)
        XCTAssertEqual(segments[1].endDate, minuteAwakeEnd)
    }

    func testSleepStageSegmentsPreserveUnspecifiedSamplesThatAddCoverage() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 3)))
        let unspecifiedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 2)))
        let unspecifiedEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 5)))

        let segments = HealthKitFetchEngine.sleepStageSegments(
            from: [
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
                HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleep.rawValue, start: unspecifiedStart, end: unspecifiedEnd)
            ]
        )

        XCTAssertEqual(segments.map(\.stage), [SleepStage.core, .core])
        XCTAssertEqual(segments[0].startDate, coreStart)
        XCTAssertEqual(segments[0].endDate, coreEnd)
        XCTAssertEqual(segments[1].startDate, coreEnd)
        XCTAssertEqual(segments[1].endDate, unspecifiedEnd)
    }

    func testIntradayFetchStartUsesWindowStartOrNextCachedSample() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let cachedSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 7)))
        let staleSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28, hour: 7)))

        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(
                after: HealthTrendSeries(points: [HealthTrendDataPoint(date: cachedSampleDate, value: 61)]),
                windowStart: windowStart
            ),
            cachedSampleDate.addingTimeInterval(0.001)
        )
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(
                after: HealthTrendSeries(points: [HealthTrendDataPoint(date: staleSampleDate, value: 61)]),
                windowStart: windowStart
            ),
            windowStart
        )
    }

    func testMergeIntradaySamplesDropsExpiredCacheAndAppendsIncomingSamples() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let expiredDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23)))
        let keptDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 1)))
        let incomingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 1)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: expiredDate, value: 59),
                HealthTrendDataPoint(date: keptDate, value: 61)
            ]),
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: incomingDate, value: 62)
            ]),
            windowStart: windowStart
        )

        XCTAssertEqual(merged.points.map(\.date), [keptDate, incomingDate])
        XCTAssertEqual(merged.points.map(\.value), [61, 62])
    }

    func testAverageVitalValuesPartitionsSamplesPerNightInterval() throws {
        let calendar = Calendar.bodyGregorian
        let night1Start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1)))
        let night1End = night1Start.addingTimeInterval(7 * 60 * 60)
        let night2Start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 0, minute: 30)))
        let night2End = night2Start.addingTimeInterval(7 * 60 * 60)
        let night3Start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 2)))
        let night3End = night3Start.addingTimeInterval(6 * 60 * 60)

        func instant(_ date: Date, _ value: Double) -> SleepVitalWindowSample {
            SleepVitalWindowSample(startDate: date, endDate: date, value: value)
        }

        let samples = [
            // Instantaneous sample at the exact night start counts.
            instant(night1Start, 60),
            instant(night1Start.addingTimeInterval(3_600), 64),
            // Spans the night-2 boundary: overlaps night 2 only.
            SleepVitalWindowSample(
                startDate: night2Start.addingTimeInterval(-1_800),
                endDate: night2Start.addingTimeInterval(1_800),
                value: 50
            ),
            instant(night2Start.addingTimeInterval(60), 54),
            // Instantaneous sample at the exact night end is excluded ([start, end)).
            instant(night2End, 99)
        ].sorted { $0.startDate < $1.startDate }

        let averages = HealthKitFetchEngine.averageVitalValues(
            samples: samples,
            intervals: [
                DateInterval(start: night1Start, end: night1End),
                DateInterval(start: night2Start, end: night2End),
                DateInterval(start: night3Start, end: night3End)
            ]
        )

        XCTAssertEqual(averages.count, 3)
        XCTAssertEqual(try XCTUnwrap(averages[0]), 62, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(averages[1]), 52, accuracy: 0.0001)
        XCTAssertNil(averages[2])
    }

    func testAverageVitalValuesReturnsNilsWhenNoSamples() {
        let now = Date()

        let averages = HealthKitFetchEngine.averageVitalValues(
            samples: [],
            intervals: [DateInterval(start: now, end: now.addingTimeInterval(3_600))]
        )

        XCTAssertEqual(averages, [nil])
    }

    func testEvictableMonthKeysDropOldestUnprotectedBeyondCap() {
        let keys = (1...6).map { BodyWorkoutMonthKey(month: $0, year: 2026) }

        let evicted = HealthKitWorkoutStore.evictableMonthKeys(
            loadOrder: keys,
            maximumCount: 4,
            protectedKeys: [keys[0]]
        )

        XCTAssertEqual(evicted, [keys[1], keys[2]])
        XCTAssertTrue(
            HealthKitWorkoutStore.evictableMonthKeys(
                loadOrder: keys,
                maximumCount: 6,
                protectedKeys: []
            ).isEmpty
        )
    }

    @MainActor
    func testWidgetReloadCoalescerCollapsesBurstsIntoOneReload() async {
        var reloadCount = 0
        let coalescer = BodyWidgetReloadCoalescer(debounceNanoseconds: 5_000_000) {
            reloadCount += 1
        }

        coalescer.requestReload()
        coalescer.requestReload()
        coalescer.requestReload()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(reloadCount, 1)

        coalescer.requestReload()
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(reloadCount, 2)
    }

    func testPartitionHeartRateSamplesMatchesPerWorkoutWindowFiltering() {
        let base = Date(timeIntervalSinceReferenceDate: 790_000_000)
        let samples = (0..<500).map { offset in
            WorkoutHeartRateSample(
                date: base.addingTimeInterval(Double(offset) * 90),
                beatsPerMinute: 80 + Double(offset % 40)
            )
        }
        let windows: [(id: UUID, startDate: Date, endDate: Date)] = [
            // Starts exactly on a sample date.
            (UUID(), base, base.addingTimeInterval(1_800)),
            // Overlaps the first window.
            (UUID(), base.addingTimeInterval(900), base.addingTimeInterval(2_700)),
            // Zero-length window matches nothing.
            (UUID(), base.addingTimeInterval(10_000), base.addingTimeInterval(10_000)),
            (UUID(), base.addingTimeInterval(20_000), base.addingTimeInterval(26_000)),
            // Extends past the last sample.
            (UUID(), base.addingTimeInterval(44_910), base.addingTimeInterval(60_000))
        ]

        let partitioned = HealthKitFetchEngine.partitionHeartRateSamples(samples, forWorkoutWindows: windows)

        XCTAssertEqual(partitioned.count, windows.count)
        for window in windows {
            let expected = samples.filter { $0.date >= window.startDate && $0.date < window.endDate }
            XCTAssertEqual(partitioned[window.id]?.map(\.date), expected.map(\.date))
            XCTAssertEqual(partitioned[window.id]?.map(\.beatsPerMinute), expected.map(\.beatsPerMinute))
        }
    }

    func testEffortFetchCandidateIDsSkipCachedAndConfirmedWorkouts() {
        let cached = UUID()
        let confirmed = UUID()
        let fresh = UUID()

        let candidates = HealthKitFetchEngine.effortFetchCandidateIDs(
            workoutIDs: [cached, confirmed, fresh],
            cachedEffortIDs: [cached],
            confirmedNoEffortIDs: [confirmed]
        )

        XCTAssertEqual(candidates, [fresh])
    }

    func testConfirmableNoEffortWorkoutIDsRequireAgeAndNoFoundScore() {
        let now = Date()
        let oldUnrated = UUID()
        let recentUnrated = UUID()
        let oldRated = UUID()
        let queried: [(id: UUID, endDate: Date)] = [
            (oldUnrated, now.addingTimeInterval(-49 * 60 * 60)),
            (recentUnrated, now.addingTimeInterval(-2 * 60 * 60)),
            (oldRated, now.addingTimeInterval(-72 * 60 * 60))
        ]

        let confirmed = HealthKitFetchEngine.confirmableNoEffortWorkoutIDs(
            queried: queried,
            foundIDs: [oldRated],
            now: now
        )

        XCTAssertEqual(confirmed, [oldUnrated])
    }

    func testHeartRateReuseEligibilityRequiresMatchingFinishedCachedWorkout() {
        let now = Date()
        let duration: TimeInterval = 3_600
        let finishedStart = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let recentStart = now.addingTimeInterval(-2 * 60 * 60)

        func cachedSummary(id: UUID, startDate: Date, samples: [WorkoutHeartRateSample]) -> WorkoutSummary {
            WorkoutSummary(
                id: id,
                type: .running,
                startDate: startDate,
                duration: duration,
                heartRateSamples: samples
            )
        }

        let sample = WorkoutHeartRateSample(date: finishedStart, beatsPerMinute: 140)
        let eligible = UUID()
        let dateMismatch = UUID()
        let emptySamples = UUID()
        let tooRecent = UUID()
        let uncached = UUID()

        let workouts: [(id: UUID, startDate: Date, duration: TimeInterval)] = [
            (eligible, finishedStart, duration),
            (dateMismatch, finishedStart, duration),
            (emptySamples, finishedStart, duration),
            (tooRecent, recentStart, duration),
            (uncached, finishedStart, duration)
        ]
        let cachedSummaries: [UUID: WorkoutSummary] = [
            eligible: cachedSummary(id: eligible, startDate: finishedStart, samples: [sample]),
            dateMismatch: cachedSummary(id: dateMismatch, startDate: finishedStart.addingTimeInterval(5), samples: [sample]),
            emptySamples: cachedSummary(id: emptySamples, startDate: finishedStart, samples: []),
            tooRecent: cachedSummary(id: tooRecent, startDate: recentStart, samples: [sample])
        ]

        let eligibleIDs = HealthKitFetchEngine.heartRateReuseEligibleWorkoutIDs(
            workouts: workouts,
            cachedSummaries: cachedSummaries,
            now: now
        )

        XCTAssertEqual(eligibleIDs, [eligible])
    }

    func testReusingHeartRateSummaryCopiesCachedHeartRateAndTakesFreshMetadata() throws {
        let calendar = Calendar.bodyGregorian
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8)))
        let end = start.addingTimeInterval(1_800)
        let workout = HKWorkout(activityType: .running, start: start, end: end)
        let cached = WorkoutSummary(
            id: workout.uuid,
            type: .cycling,
            startDate: start.addingTimeInterval(-60),
            duration: 999,
            averageHeartRateBeatsPerMinute: 142,
            heartRateSamples: [WorkoutHeartRateSample(date: start, beatsPerMinute: 140)],
            sourceName: "Cached Source"
        )

        let summary = HealthKitFetchEngine.summary(for: workout, reusingHeartRateFrom: cached, effortLevel: 7)

        XCTAssertEqual(summary.id, workout.uuid)
        XCTAssertEqual(summary.type, .running)
        XCTAssertEqual(summary.startDate, start)
        XCTAssertEqual(summary.duration, workout.duration)
        XCTAssertEqual(summary.averageHeartRateBeatsPerMinute, 142)
        XCTAssertEqual(summary.heartRateSamples, cached.heartRateSamples)
        XCTAssertEqual(summary.effortLevel, 7)
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

    private func temporaryHealthDashboardSnapshotFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("lastHealthDashboardSnapshot.json")
    }

    private func temporaryWorkoutSnapshotFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("currentMonthWorkoutSnapshot.json")
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

    private struct LegacyHealthDashboardSnapshot: Codable {
        var summary: HealthSummarySnapshot
        var trends: HealthTrendSnapshot
    }
}
