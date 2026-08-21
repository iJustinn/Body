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

    func testWorkoutMetricsPermissionGatesDetailReadTypes() throws {
        let vo2Max = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .vo2Max))
        let runningPower = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningPower))
        let cyclingPower = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .cyclingPower))
        let cyclingCadence = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .cyclingCadence))
        let swimStrokes = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount))
        let strideLength = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningStrideLength))
        let groundContact = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningGroundContactTime))
        let verticalOscillation = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation))
        let distance = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning))

        // Workouts + Workout Metrics: detail metrics requested; distance (core) also present.
        let both = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts, .workoutMetrics])
        )
        XCTAssertTrue(both.contains(vo2Max))
        XCTAssertTrue(both.contains(runningPower))
        XCTAssertTrue(both.contains(cyclingPower))
        XCTAssertTrue(both.contains(cyclingCadence))
        XCTAssertTrue(both.contains(swimStrokes))
        XCTAssertTrue(both.contains(strideLength))
        XCTAssertTrue(both.contains(groundContact))
        XCTAssertTrue(both.contains(verticalOscillation))
        XCTAssertTrue(both.contains(distance))
        XCTAssertTrue(both.contains(HKObjectType.workoutType()))

        // Workouts alone: distance + workout type stay; the detail metrics drop.
        let workoutsOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts])
        )
        XCTAssertTrue(workoutsOnly.contains(distance))
        XCTAssertTrue(workoutsOnly.contains(HKObjectType.workoutType()))
        XCTAssertFalse(workoutsOnly.contains(vo2Max))
        XCTAssertFalse(workoutsOnly.contains(runningPower))
        XCTAssertFalse(workoutsOnly.contains(cyclingPower))
        XCTAssertFalse(workoutsOnly.contains(swimStrokes))
        XCTAssertFalse(workoutsOnly.contains(strideLength))
        XCTAssertFalse(workoutsOnly.contains(groundContact))
        XCTAssertFalse(workoutsOnly.contains(verticalOscillation))

        // Workout Metrics without Workouts: nothing requested (AND-gate).
        let metricsOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workoutMetrics])
        )
        XCTAssertFalse(metricsOnly.contains(vo2Max))
        XCTAssertFalse(metricsOnly.contains(distance))
    }

    /// Heart-rate recovery feeds a workout-detail tile but is heart data, so it
    /// rides the Heart toggle rather than Workouts/Workout Metrics.
    func testHeartPermissionGatesHeartRateRecoveryReadType() throws {
        let recovery = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateRecoveryOneMinute))

        XCTAssertTrue(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart])
        ).contains(recovery))

        XCTAssertFalse(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts, .workoutMetrics])
        ).contains(recovery))
    }

    func testDateOfBirthPermissionGatesCharacteristicReadType() throws {
        let dateOfBirth = try XCTUnwrap(HKObjectType.characteristicType(forIdentifier: .dateOfBirth))

        let both = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart, .dateOfBirth])
        )
        XCTAssertTrue(both.contains(dateOfBirth))

        // Heart alone (no Date of Birth) and Date of Birth alone (no Heart): not requested.
        let heartOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.heart])
        )
        XCTAssertFalse(heartOnly.contains(dateOfBirth))

        let dateOfBirthOnly = HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.dateOfBirth])
        )
        XCTAssertFalse(dateOfBirthOnly.contains(dateOfBirth))
    }

    /// Pins the sync badge's "can this refresh dispatch any query" oracle:
    /// dependent-only selections (child toggles without their parents) yield an
    /// EMPTY read set, so `ranQueries` must be false and the badge must not
    /// confirm "Health data updated" for such a refresh.
    func testDependentOnlyPermissionSelectionsYieldNoReadTypes() {
        XCTAssertTrue(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.dateOfBirth, .workoutMetrics])
        ).isEmpty)
        XCTAssertTrue(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [])
        ).isEmpty)
        XCTAssertFalse(HealthKitWorkoutStore.readObjectTypes(
            for: BodyHealthPermissionSelection(enabledPermissions: [.workouts, .workoutMetrics])
        ).isEmpty)
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

    func testHealthDashboardSnapshotStorePersistsWatchExpectedSourceIDsAcrossRelaunch() throws {
        // The compute seed's `dataThrough` watermark is restored across
        // relaunches, so the expected-source coverage it guards must survive
        // with it — a relaunch publish that shipped a seed with NO expected
        // lists would license the watch's unfiltered All-Sources reads.
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(HealthDashboardSnapshotStore.loadWatchExpectedSourceIDs(defaults: defaults), [:])

        let idsByKind = [
            "heartRate": ["source:bundle=com.apple.health|name=apple watch"],
            "sleep": [
                "source:bundle=com.apple.health|name=apple watch",
                "source:bundle=com.example.tracker|name=tracker"
            ]
        ]
        HealthDashboardSnapshotStore.saveWatchExpectedSourceIDs(idsByKind, defaults: defaults)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadWatchExpectedSourceIDs(defaults: defaults), idsByKind)

        HealthDashboardSnapshotStore.clearWatchExpectedSourceIDs(defaults: defaults)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadWatchExpectedSourceIDs(defaults: defaults), [:])
    }

    func testHealthDashboardSnapshotStorePersistsWatchTrainingLoadSeedAcrossRelaunch() throws {
        // Same relaunch story as the expected-source lists: the seed's
        // `dataThrough` is restored, so a workout-only publish would otherwise
        // replace the watch's complete seed with one carrying no Training Load
        // arrays — unrecoverable while the phone's TL/Readiness cards are
        // hidden (the rebuild is cost-gated on the dashboard fetching TL).
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(HealthDashboardSnapshotStore.loadWatchTrainingLoadSeed(defaults: defaults))

        let startDay = Date(timeIntervalSince1970: 1_700_000_000)
        let through = Date(timeIntervalSince1970: 1_700_500_000)
        let loads: [Double] = [0, 12.5, 0, 88.25]
        HealthDashboardSnapshotStore.saveWatchTrainingLoadSeed(
            startDay: startDay, loads: loads, through: through, defaults: defaults
        )
        let restored = try XCTUnwrap(HealthDashboardSnapshotStore.loadWatchTrainingLoadSeed(defaults: defaults))
        XCTAssertEqual(restored.startDay, startDay)
        XCTAssertEqual(restored.loads, loads)
        XCTAssertEqual(restored.through, through)

        HealthDashboardSnapshotStore.clearWatchTrainingLoadSeed(defaults: defaults)
        XCTAssertNil(HealthDashboardSnapshotStore.loadWatchTrainingLoadSeed(defaults: defaults))
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
    func testWorkoutStoreClearLocalCacheResetsInMemorySnapshotsAndStatus() async throws {
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

        await store.clearLocalCache(date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 16))))

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

    /// A lazy-load-style success (`refreshedVitals: false` — month paging, older
    /// ring history, single-metric or workout-only refreshes) must not arm the
    /// dashboard-freshness TTL, in memory or in the persisted timestamp;
    /// otherwise paging history keeps the TTL fresh and warm resumes skip the
    /// vitals refresh indefinitely. Only a vitals-refreshing success arms it.
    @MainActor
    func testMarkRefreshSucceededOnlyArmsFreshnessTTLWhenVitalsRefreshed() throws {
        let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        defer {
            HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
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
        XCTAssertNil(store.lastSuccessfulRefreshDate)

        let lazyLoadDate = Date(timeIntervalSince1970: 1_700_000_000)
        store.markRefreshSucceeded(date: lazyLoadDate, refreshedVitals: false, publishesWatch: false)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertNil(HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate())

        let vitalsRefreshDate = Date(timeIntervalSince1970: 1_700_000_100)
        store.markRefreshSucceeded(date: vitalsRefreshDate, refreshedVitals: true, publishesWatch: false)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, vitalsRefreshDate)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate(), vitalsRefreshDate)
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

    func testSleepSummaryReadsTimeZoneFromMainSleepSession() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let mainStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let mainEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14, minute: 30)))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                // A short nap from another source with a different zone must not win.
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: napStart,
                    end: napEnd,
                    metadata: [HKMetadataKeyTimeZone: "America/New_York"]
                ),
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: mainStart,
                    end: mainEnd,
                    metadata: [HKMetadataKeyTimeZone: "Europe/London"]
                )
            ],
            date: day
        ))

        XCTAssertEqual(summary.stageSnapshot.timeZoneIdentifier, "Europe/London")
    }

    func testSleepSummaryTimeZoneIgnoresNapSampleLongerThanEachMainStageSample() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let mainStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 16)))

        // The main night is split into hour-long stage samples, each individually
        // shorter than the single two-hour nap sample from another zone; the
        // night's aggregated main session must still supply the zone.
        var samples = (0..<8).map { hour in
            HKCategorySample(
                type: sleepType,
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: mainStart.addingTimeInterval(TimeInterval(hour) * 3_600),
                end: mainStart.addingTimeInterval(TimeInterval(hour + 1) * 3_600),
                metadata: [HKMetadataKeyTimeZone: "Europe/London"]
            )
        }
        samples.append(HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: napStart,
            end: napEnd,
            metadata: [HKMetadataKeyTimeZone: "America/New_York"]
        ))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(from: samples, date: day))

        XCTAssertEqual(summary.stageSnapshot.timeZoneIdentifier, "Europe/London")
    }

    func testSleepSummaryTimeZoneStaysNilWhenOnlyNapCarriesMetadata() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let mainStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let mainEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))
        let napStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 14)))
        let napEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 16)))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: mainStart,
                    end: mainEnd
                ),
                // A zone known only for the nap must not label the main night.
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: napStart,
                    end: napEnd,
                    metadata: [HKMetadataKeyTimeZone: "America/New_York"]
                )
            ],
            date: day
        ))

        XCTAssertNil(summary.stageSnapshot.timeZoneIdentifier)
    }

    func testSleepSummaryLeavesTimeZoneNilWithoutMetadata() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: start,
                    end: end
                )
            ],
            date: day
        ))

        XCTAssertNil(summary.stageSnapshot.timeZoneIdentifier)
    }

    func testSleepSummaryFillsTimeZoneFromLedgerWhenMetadataMissing() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 23)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 7)))

        // Inject an ephemeral ledger recording that the device was in New York
        // before this night, then parse samples with no zone metadata (as Apple
        // Watch sleep does): the forwarder back-fills the ledger's zone for the
        // wake day so timezone-aware scoring can still place the night.
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let ledgerDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let previousLedger = HealthKitFetchEngine.timeZoneLedger
        defer {
            HealthKitFetchEngine.timeZoneLedger = previousLedger
            ledgerDefaults.removePersistentDomain(forName: suiteName)
        }
        let ledger = BodyTimeZoneLedger(defaults: ledgerDefaults)
        ledger.recordCurrentZone(
            now: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))),
            zone: try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        )
        HealthKitFetchEngine.timeZoneLedger = ledger

        let summary = try XCTUnwrap(HealthKitFetchEngine.sleepSummary(
            from: [
                HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: start,
                    end: end
                )
            ],
            date: day
        ))

        XCTAssertEqual(summary.stageSnapshot.timeZoneIdentifier, "America/New_York")
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

    func testSleepStageSegmentsTrimLeadingAndTrailingAwakeWhenEnabled() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let leadingAwakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 0)))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 2)))
        let interiorAwakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 2, minute: 30)))
        let remEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 4)))
        let trailingAwakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 5)))

        let samples = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: leadingAwakeStart, end: coreStart),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: coreEnd, end: interiorAwakeEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: interiorAwakeEnd, end: remEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: remEnd, end: trailingAwakeEnd)
        ]

        // Default keeps the leading/trailing awake blocks.
        let untrimmed = HealthKitFetchEngine.sleepStageSegments(from: samples)
        XCTAssertEqual(untrimmed.map(\.stage), [SleepStage.awake, .core, .awake, .rem, .awake])

        // Enabled: leading + trailing awake dropped, interior awake preserved.
        let trimmed = HealthKitFetchEngine.sleepStageSegments(from: samples, showsLeadingTrailingAwakeStages: false)
        XCTAssertEqual(trimmed.map(\.stage), [SleepStage.core, .awake, .rem])
        XCTAssertEqual(trimmed.first?.startDate, coreStart)
        XCTAssertEqual(trimmed.last?.endDate, remEnd)
    }

    func testSleepStageSegmentsTrimClampsOverlappingTrailingAwake() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let coreStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 1)))
        let coreEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 5)))
        // Awake starts before the sleep window ends but runs past it, so it is not
        // the last segment by start date — the naive drop-last-run would miss it.
        let awakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 4, minute: 30)))
        let awakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 6)))

        let samples = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: coreStart, end: coreEnd),
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: awakeStart, end: awakeEnd)
        ]

        let trimmed = HealthKitFetchEngine.sleepStageSegments(from: samples, showsLeadingTrailingAwakeStages: false)
        // The overlapping awake is clamped to the sleep window end, so the timeline
        // never extends past real sleep.
        XCTAssertEqual(trimmed.last?.stage, .awake)
        XCTAssertEqual(trimmed.last?.endDate, coreEnd)
        XCTAssertEqual(trimmed.map(\.endDate).max(), coreEnd)
    }

    func testSleepStageSegmentsTrimReturnsEmptyForAwakeOnlyNight() throws {
        let calendar = Calendar.bodyGregorian
        let sleepType = try XCTUnwrap(HKObjectType.categoryType(forIdentifier: .sleepAnalysis))
        let awakeStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 2)))
        let awakeEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 3)))
        let samples = [
            HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: awakeStart, end: awakeEnd)
        ]

        XCTAssertTrue(HealthKitFetchEngine.sleepStageSegments(from: samples, showsLeadingTrailingAwakeStages: false).isEmpty)
        // Default (shows leading/trailing awake) leaves the awake segment untouched.
        XCTAssertEqual(HealthKitFetchEngine.sleepStageSegments(from: samples).map(\.stage), [SleepStage.awake])
    }

    func testReadinessRecordSignatureChangesWithSleepStagePreferences() {
        func signature(showsSubMinuteAwake: Bool, showsLeadingTrailingAwake: Bool) -> String {
            HealthKitWorkoutStore.readinessRecordContextSignature(
                permissionSelection: .defaultValue,
                healthDataSourceSelection: .defaultValue,
                combinesHealthDataSourcesByName: false,
                idealSleepDuration: 8 * 60 * 60,
                showsSubMinuteAwakeStages: showsSubMinuteAwake,
                showsLeadingTrailingAwakeStages: showsLeadingTrailingAwake
            )
        }

        let base = signature(showsSubMinuteAwake: true, showsLeadingTrailingAwake: true)
        // Toggling either sleep-stage parser preference must change the signature so
        // frozen morning readiness records are invalidated and recomputed.
        XCTAssertNotEqual(base, signature(showsSubMinuteAwake: true, showsLeadingTrailingAwake: false))
        XCTAssertNotEqual(base, signature(showsSubMinuteAwake: false, showsLeadingTrailingAwake: true))
    }

    func testIntradayFetchStartBacksUpByOverlapWindow() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        // Newest cached point is well inside the window; backing up 48h stays
        // inside the window, so the overlap anchor wins.
        let cachedSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 7)))
        // Newest cached point is close to the window start; backing up 48h would
        // fall before it, so the fetch clamps to windowStart.
        let nearStartSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 7)))

        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(
                after: HealthTrendSeries(points: [HealthTrendDataPoint(date: cachedSampleDate, value: 61)]),
                windowStart: windowStart
            ),
            cachedSampleDate.addingTimeInterval(-HealthKitFetchEngine.incrementalOverlapWindow)
        )
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(
                after: HealthTrendSeries(points: [HealthTrendDataPoint(date: nearStartSampleDate, value: 61)]),
                windowStart: windowStart
            ),
            windowStart
        )
    }

    func testMergeIntradaySamplesDropsExpiredCacheAndReplacesRefetchWindow() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let expiredDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30, hour: 23)))
        let keptDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 1)))
        // Refetch window opens at day 2; the incoming series is authoritative from there.
        let refetchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2)))
        let incomingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 1)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: expiredDate, value: 59),
                HealthTrendDataPoint(date: keptDate, value: 61)
            ]),
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: incomingDate, value: 62)
            ]),
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        XCTAssertEqual(merged.points.map(\.date), [keptDate, incomingDate])
        XCTAssertEqual(merged.points.map(\.value), [61, 62])
    }

    func testMergeIntradaySamplesReconcilesBackfilledSampleInsideOverlap() throws {
        // Regression for H1: a sample timestamped earlier than the newest cached
        // point arrives late (Watch batch sync / third-party backfill). Because
        // the refetch window covers its timestamp, the authoritative `incoming`
        // series carries both the backfilled point and the previously-cached one,
        // and the merge yields them in order with no duplication.
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let refetchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 6)))
        let cachedNewest = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 8)))
        let backfilledDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 7)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: cachedNewest, value: 70)
            ]),
            // Refetch returns the whole overlap window: the late backfill plus the
            // already-cached point (HealthKit hands back everything it now holds).
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: backfilledDate, value: 55),
                HealthTrendDataPoint(date: cachedNewest, value: 70)
            ]),
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        XCTAssertEqual(merged.points.map(\.date), [backfilledDate, cachedNewest])
        XCTAssertEqual(merged.points.map(\.value), [55, 70])
    }

    // MARK: - M7: HealthKit query failure vs empty result

    func testResolvedTrendSeriesKeepsCacheWhenFetchFailed() throws {
        // A `nil` fetched value models a failed HealthKit query (device locked,
        // store unavailable, XPC drop) — the cached series must survive rather
        // than being blanked.
        let cached = HealthTrendSeries(points: [
            HealthTrendDataPoint(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 5))),
                value: 61
            )
        ])

        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: nil, cached: cached),
            cached
        )
    }

    func testResolvedTrendSeriesReplacesCacheOnSuccessEvenWhenEmpty() throws {
        // A non-nil fetched value replaces the cache — including a genuinely
        // empty successful result and the intentionally empty series produced
        // when a permission is toggled off (both are "authoritative empty",
        // distinct from a failed query's `nil`).
        let cached = HealthTrendSeries(points: [
            HealthTrendDataPoint(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 5))),
                value: 61
            )
        ])
        let fresh = HealthTrendSeries(points: [
            HealthTrendDataPoint(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 6))),
                value: 64
            )
        ])

        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: fresh, cached: cached),
            fresh
        )
        // Permission-off / authoritative-empty clears the cache.
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: .empty, cached: cached),
            .empty
        )
    }

    func testResolvedTrendSeriesAppliesToSleepHistorySnapshot() throws {
        // The same merge protects the sleep history that feeds readiness: a
        // failed sleep query keeps the cached nights; a successful empty result
        // clears them.
        let cached = SleepHistorySnapshot(days: [
            SleepDaySummary(
                date: try XCTUnwrap(Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 5, day: 5))),
                summary: SleepSummary(duration: 7 * 3_600)
            )
        ])

        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: SleepHistorySnapshot?.none, cached: cached),
            cached
        )
        XCTAssertEqual(
            HealthKitFetchEngine.resolvedTrendSeries(fetched: SleepHistorySnapshot.empty, cached: cached),
            .empty
        )
    }

    func testMergeIntradaySamplesRefetchStartNeverPrecedesWindowStart() throws {
        // When the cache's newest point sits within the overlap window of
        // windowStart, incrementalFetchStart clamps refetchStart to windowStart,
        // so the whole cached series is authoritative-replaced by the refetch.
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let cachedSampleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))
        let refetchStart = HealthKitFetchEngine.incrementalFetchStart(
            after: HealthTrendSeries(points: [HealthTrendDataPoint(date: cachedSampleDate, value: 61)]),
            windowStart: windowStart
        )
        XCTAssertEqual(refetchStart, windowStart)

        let incomingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))
        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: cachedSampleDate, value: 61)
            ]),
            incoming: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: incomingDate, value: 63)
            ]),
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        // No point kept before refetchStart (== windowStart); refetch replaces all.
        XCTAssertEqual(merged.points.map(\.date), [incomingDate])
        XCTAssertEqual(merged.points.map(\.value), [63])
    }

    func testMergeIntradaySamplesEmptyIncomingDeletesOnlyInsideRefetchWindow() throws {
        // Empty incoming with a real refetch window means HealthKit now holds
        // nothing in [refetchStart, end] — the samples there were deleted, so
        // dropping them is correct. Points before refetchStart are untouched.
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let keptDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 2, hour: 1)))
        let refetchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        let deletedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 7)))

        let merged = HealthKitFetchEngine.mergeIntradaySamples(
            existing: HealthTrendSeries(points: [
                HealthTrendDataPoint(date: keptDate, value: 61),
                HealthTrendDataPoint(date: deletedDate, value: 62)
            ]),
            incoming: .empty,
            windowStart: windowStart,
            refetchStart: refetchStart
        )

        XCTAssertEqual(merged.points.map(\.date), [keptDate])
        XCTAssertEqual(merged.points.map(\.value), [61])
    }

    /// A comparison source that resolved to No Comparison (Body Pro lapsed, or the
    /// primary source was changed to match the secondary and collapsed it) fetches an
    /// authoritative EMPTY, which has to clear the cached series. Anchoring the
    /// refetch boundary on the newest cached point instead leaves every point older
    /// than the 48h overlap on the chart, so the comparison line keeps drawing after
    /// it should have vanished. Both halves are asserted: the boundary that works and
    /// the boundary that silently strands the stale points.
    func testDisabledSecondaryClearsCacheOnlyWhenRefetchStartsAtWindowStart() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let staleDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 9)))
        let recentDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 9)))
        let cached = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: staleDate, value: 58),
            HealthTrendDataPoint(date: recentDate, value: 61)
        ])

        // What the store now does for a disabled comparison: the whole window is
        // authoritative, so the empty result wipes the series.
        let cleared = HealthKitFetchEngine.mergeIntradaySamples(
            existing: cached,
            incoming: .empty,
            windowStart: windowStart,
            refetchStart: windowStart
        )
        XCTAssertTrue(cleared.isEmpty)

        // The incremental boundary — correct for an ENABLED comparison, wrong for a
        // disabled one, because it preserves everything before the overlap.
        let incrementalStart = HealthKitFetchEngine.incrementalFetchStart(after: cached, windowStart: windowStart)
        let stranded = HealthKitFetchEngine.mergeIntradaySamples(
            existing: cached,
            incoming: .empty,
            windowStart: windowStart,
            refetchStart: incrementalStart
        )
        XCTAssertEqual(stranded.points.map(\.date), [staleDate])
    }

    /// Clearing the comparison cache is what makes the next detail-view visit pull a
    /// FULL window rather than incrementally topping up pre-lapse points: an empty
    /// cache has no anchor, so `incrementalFetchStart` falls back to `windowStart`.
    /// This is why the entitlement handler invalidates instead of eagerly refetching
    /// — the lazy path already does the right thing once the cache is genuinely
    /// empty, and a comparison kind is ~50k raw samples to fetch eagerly.
    func testClearedComparisonCacheRefetchesFullWindowOnNextVisit() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let preLapse = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 6)))
        let staleCache = HealthTrendSeries(points: [HealthTrendDataPoint(date: preLapse, value: 57)])

        // Left in place, the pre-lapse points anchor the refetch 48h back and every
        // older point is silently trusted forever.
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: staleCache, windowStart: windowStart),
            preLapse.addingTimeInterval(-HealthKitFetchEngine.incrementalOverlapWindow)
        )
        // Cleared, the next visit re-reads the whole window from HealthKit.
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
    }

    /// The secondary day-sample fetch is now incremental too, so it must land on the
    /// same 48h boundary the primary uses — a comparison cache and a primary cache
    /// with the same newest point refetch the same window.
    func testSecondaryIncrementalFetchStartMatchesPrimary() throws {
        let calendar = Calendar.bodyGregorian
        let windowStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let newest = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 6)))
        let series = HealthTrendSeries(points: [HealthTrendDataPoint(date: newest, value: 55)])

        let fetchStart = HealthKitFetchEngine.incrementalFetchStart(after: series, windowStart: windowStart)

        XCTAssertEqual(fetchStart, newest.addingTimeInterval(-HealthKitFetchEngine.incrementalOverlapWindow))
        // An empty comparison cache (first load, or just-cleared after a source
        // switch) still pulls the full window.
        XCTAssertEqual(
            HealthKitFetchEngine.incrementalFetchStart(after: .empty, windowStart: windowStart),
            windowStart
        )
    }

    /// The Step-2 guard in `refreshHealthMetric` keys off `HealthTrendDaySampleSignatures`,
    /// so a secondary-source switch or a combine-flag flip mid-fetch has to register
    /// as a mismatch — otherwise a mixed-source merge gets published and persisted.
    func testDaySampleSignaturesDifferForSecondaryAndCombineChanges() {
        let base = HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-a",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: false
        )

        XCTAssertNotEqual(base, HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-b",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: false
        ))
        XCTAssertNotEqual(base, HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-a",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: true
        ))
        XCTAssertEqual(base, HealthTrendDaySampleSignatures(
            primarySelectionSignature: "primary-a",
            secondarySelectionSignature: "secondary-a",
            permissionSignature: "perm-a",
            combinesHealthDataSourcesByName: false
        ))
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

        let averages = BodySleepFetch.averageVitalValues(
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

        let averages = BodySleepFetch.averageVitalValues(
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

        // Samples covering the workout window edge-to-edge (complete payload) vs
        // a payload cached during a partial Watch sync that misses the opening
        // ramp (first sample 10 minutes in) — the latter must re-fetch.
        let coveringSamples = [
            WorkoutHeartRateSample(date: finishedStart, beatsPerMinute: 140),
            WorkoutHeartRateSample(date: finishedStart.addingTimeInterval(duration), beatsPerMinute: 150)
        ]
        let lateStartSamples = [
            WorkoutHeartRateSample(date: finishedStart.addingTimeInterval(600), beatsPerMinute: 160),
            WorkoutHeartRateSample(date: finishedStart.addingTimeInterval(duration), beatsPerMinute: 150)
        ]
        let eligible = UUID()
        let dateMismatch = UUID()
        let emptySamples = UUID()
        let missingRamp = UUID()
        let tooRecent = UUID()
        let uncached = UUID()

        let workouts: [(id: UUID, startDate: Date, duration: TimeInterval)] = [
            (eligible, finishedStart, duration),
            (dateMismatch, finishedStart, duration),
            (emptySamples, finishedStart, duration),
            (missingRamp, finishedStart, duration),
            (tooRecent, recentStart, duration),
            (uncached, finishedStart, duration)
        ]
        let cachedSummaries: [UUID: WorkoutSummary] = [
            eligible: cachedSummary(id: eligible, startDate: finishedStart, samples: coveringSamples),
            dateMismatch: cachedSummary(id: dateMismatch, startDate: finishedStart.addingTimeInterval(5), samples: coveringSamples),
            emptySamples: cachedSummary(id: emptySamples, startDate: finishedStart, samples: []),
            missingRamp: cachedSummary(id: missingRamp, startDate: finishedStart, samples: lateStartSamples),
            tooRecent: cachedSummary(id: tooRecent, startDate: recentStart, samples: coveringSamples)
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

        let summary = BodyWorkoutFetch.summary(for: workout, reusingHeartRateFrom: cached, effortLevel: 7)

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

    // MARK: - Auto-apply effort eligibility

    func testAutoApplyEligibleWorkoutsRespectsWindowAndExclusions() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hour: TimeInterval = 3600
        func workout(id: UUID = UUID(), endedHoursAgo: Double, effort: Double? = nil) -> WorkoutSummary {
            let start = now.addingTimeInterval(-(endedHoursAgo * hour) - hour)
            return WorkoutSummary(id: id, type: .running, startDate: start, duration: hour, effortLevel: effort)
        }
        let inWindow = workout(endedHoursAgo: 3)            // unrated, 3h old -> eligible
        let tooNew = workout(endedHoursAgo: 0.5)            // 30 min old -> excluded (< 1h)
        let tooOld = workout(endedHoursAgo: 60)             // 60h old -> excluded (> 48h)
        let rated = workout(endedHoursAgo: 3, effort: 6)    // already rated -> excluded
        let overriddenID = UUID(), appliedID = UUID(), skippedID = UUID()
        let overridden = workout(id: overriddenID, endedHoursAgo: 3)
        let applied = workout(id: appliedID, endedHoursAgo: 3)
        let skipped = workout(id: skippedID, endedHoursAgo: 3)

        let result = HealthKitWorkoutStore.autoApplyEligibleWorkouts(
            [tooOld, inWindow, tooNew, rated, overridden, applied, skipped],
            now: now,
            minAge: hour,
            maxAge: 48 * hour,
            overriddenIDs: [overriddenID],
            appliedIDs: [appliedID],
            skippedIDs: [skippedID]
        )
        XCTAssertEqual(result.map(\.id), [inWindow.id])
    }

    func testAutoApplyEligibleWorkoutsIncludesWindowBoundariesNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hour: TimeInterval = 3600
        func workout(endedHoursAgo: Double) -> WorkoutSummary {
            WorkoutSummary(
                type: .running,
                startDate: now.addingTimeInterval(-(endedHoursAgo * hour) - hour),
                duration: hour
            )
        }
        let exactlyOneHour = workout(endedHoursAgo: 1)   // age == minAge -> included (inclusive)
        let middle = workout(endedHoursAgo: 10)
        let exactly48Hours = workout(endedHoursAgo: 48)  // age == maxAge -> included (inclusive)

        let result = HealthKitWorkoutStore.autoApplyEligibleWorkouts(
            [exactly48Hours, exactlyOneHour, middle],
            now: now,
            minAge: hour,
            maxAge: 48 * hour,
            overriddenIDs: [],
            appliedIDs: [],
            skippedIDs: []
        )
        XCTAssertEqual(result.map(\.id), [exactlyOneHour.id, middle.id, exactly48Hours.id])
    }

    func testAutoApplyWindowMonthKeysSpansPriorMonthNearBoundary() throws {
        let calendar = Calendar.bodyGregorian

        // Mid-month: the 48h window stays inside the current month -> current month only.
        let midMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyWindowMonthKeys(now: midMonth, maxAge: 48 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 7, year: 2026)]
        )

        // Early in the month: now - 48h falls in the prior month -> both months.
        let earlyMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 9)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyWindowMonthKeys(now: earlyMonth, maxAge: 48 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 7, year: 2026), BodyWorkoutMonthKey(month: 6, year: 2026)]
        )

        // Across a year boundary: January 1 reaches back into the prior December.
        let newYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 6)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyWindowMonthKeys(now: newYear, maxAge: 48 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 1, year: 2026), BodyWorkoutMonthKey(month: 12, year: 2025)]
        )
    }

    func testAutoApplyComparisonMonthKeysSpanTheComparisonReach() throws {
        let calendar = Calendar.bodyGregorian

        // Mid-month (Jul 24): the span [now - 33d, now] reaches back to Jun 21, so the
        // oldest candidate's 30-day comparison window touches only June and July.
        let midMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 12)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: midMonth, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [BodyWorkoutMonthKey(month: 6, year: 2026), BodyWorkoutMonthKey(month: 7, year: 2026)]
        )

        // Early in the month (Jul 2): the span reaches back to May 30, spanning three
        // months — a candidate near the start of July can compare against May.
        let earlyMonth = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 9)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: earlyMonth, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [
                BodyWorkoutMonthKey(month: 5, year: 2026),
                BodyWorkoutMonthKey(month: 6, year: 2026),
                BodyWorkoutMonthKey(month: 7, year: 2026)
            ]
        )

        // Month boundary (Aug 1): the span reaches back to Jun 29, so June, July, and
        // August are all touched.
        let boundary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 6)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: boundary, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [
                BodyWorkoutMonthKey(month: 6, year: 2026),
                BodyWorkoutMonthKey(month: 7, year: 2026),
                BodyWorkoutMonthKey(month: 8, year: 2026)
            ]
        )

        // The duration allowance matters near the cutoff: at Aug 2 01:00, a two-hour
        // workout ending Jul 31 01:00 (age 48h, still eligible) STARTED Jul 30 23:00,
        // so its comparison window opens Jun 30 23:00 — June must be in the span even
        // though `now - (48h + 30d)` alone (Jul 1 01:00) would miss it.
        let nearCutoff = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 1)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: nearCutoff, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar),
            [
                BodyWorkoutMonthKey(month: 6, year: 2026),
                BodyWorkoutMonthKey(month: 7, year: 2026),
                BodyWorkoutMonthKey(month: 8, year: 2026)
            ]
        )

        // The 30-day portion is calendar days, so a fall DST transition (Nov 1 2026 in
        // New York adds an hour) can't shave the span short: at Dec 3 23:30 the earliest
        // candidate start is Nov 30 23:30, and 30 calendar days before that is
        // Oct 31 23:30 — October must be included, where a fixed 30 * 24h subtraction
        // would land at Nov 1 00:30 and drop it.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let acrossFallDST = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 12, day: 3, hour: 23, minute: 30)))
        XCTAssertEqual(
            HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: acrossFallDST, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: newYork),
            [
                BodyWorkoutMonthKey(month: 10, year: 2026),
                BodyWorkoutMonthKey(month: 11, year: 2026),
                BodyWorkoutMonthKey(month: 12, year: 2026)
            ]
        )
    }

    func testAutoApplyComparisonMonthKeysAlwaysConsecutiveTwoOrThreeEndingAtNow() throws {
        let calendar = Calendar.bodyGregorian

        // Sweep a variety of dates across a year (mid-month and near both edges, plus a
        // year boundary): the count is always 2 or 3, the keys are consecutive months,
        // and the last key is always `now`'s own month.
        let samples: [DateComponents] = [
            DateComponents(year: 2026, month: 1, day: 1, hour: 3),
            DateComponents(year: 2026, month: 1, day: 15, hour: 10),
            DateComponents(year: 2026, month: 2, day: 2, hour: 8),
            DateComponents(year: 2026, month: 2, day: 28, hour: 20),
            DateComponents(year: 2026, month: 3, day: 1, hour: 1),
            DateComponents(year: 2026, month: 4, day: 30, hour: 23),
            DateComponents(year: 2026, month: 5, day: 3, hour: 6),
            DateComponents(year: 2026, month: 6, day: 20, hour: 14),
            DateComponents(year: 2026, month: 7, day: 24, hour: 12),
            DateComponents(year: 2026, month: 8, day: 1, hour: 0),
            DateComponents(year: 2026, month: 9, day: 15, hour: 11),
            DateComponents(year: 2026, month: 10, day: 31, hour: 22),
            DateComponents(year: 2026, month: 11, day: 2, hour: 5),
            DateComponents(year: 2026, month: 12, day: 31, hour: 18)
        ]

        for components in samples {
            let now = try XCTUnwrap(calendar.date(from: components))
            let keys = HealthKitWorkoutStore.autoApplyComparisonMonthKeys(now: now, maxAge: 48 * 3600, maxDuration: 24 * 3600, calendar: calendar)

            XCTAssertTrue((2...3).contains(keys.count), "unexpected count \(keys.count) for \(components)")

            // Consecutive months, oldest first, each one month after the previous.
            for (previous, current) in zip(keys, keys.dropFirst()) {
                let previousStart = try XCTUnwrap(calendar.date(from: DateComponents(year: previous.year, month: previous.month)))
                let expectedNext = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: previousStart))
                XCTAssertEqual(BodyWorkoutMonthKey(date: expectedNext, calendar: calendar), current, "non-consecutive keys for \(components)")
            }

            // Ends at `now`'s month.
            XCTAssertEqual(keys.last, BodyWorkoutMonthKey(date: now, calendar: calendar), "last key isn't now's month for \(components)")
        }
    }

    // MARK: - Auto-apply effort write loop

    private enum FakeWriteError: Error { case saveFailed }

    /// Scripts the injected write path so `runAutoApplyEffortLoop`'s branch handling can
    /// be exercised without a live HealthKit engine.
    @MainActor
    private final class FakeAutoApplyWriter {
        enum Behavior {
            case outcome(HealthKitFetchEngine.AutoApplyEffortOutcome)
            case failure
        }
        var script: [UUID: Behavior] = [:]
        var authorizedAfterFailure = true
        private(set) var writeCalls: [UUID] = []
        private(set) var authChecks = 0

        func makeWriter() -> HealthKitWorkoutStore.AutoApplyEffortWriter {
            HealthKitWorkoutStore.AutoApplyEffortWriter(
                write: { id, _ in
                    self.writeCalls.append(id)
                    switch self.script[id] {
                    case .outcome(let outcome): return outcome
                    case .failure: throw FakeWriteError.saveFailed
                    case .none: return .unresolved
                    }
                },
                isWriteAuthorized: {
                    self.authChecks += 1
                    return self.authorizedAfterFailure
                }
            )
        }
    }

    @MainActor
    func testAutoApplyLoopRecordsEachWriteOutcomeAndSkipsNilScores() async {
        let written = UUID(), rated = UUID(), unresolved = UUID(), noEstimate = UUID()
        let fake = FakeAutoApplyWriter()
        fake.script = [
            written: .outcome(.written),
            rated: .outcome(.alreadyRated),
            unresolved: .outcome(.unresolved)
        ]
        let candidates = [
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: written, score: 7),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: rated, score: 5),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: unresolved, score: 6),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: noEstimate, score: nil)
        ]

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: fake.makeWriter()
        )

        XCTAssertEqual(result.writtenScores, [written: 7])
        XCTAssertEqual(result.appliedIDs, [written])
        XCTAssertEqual(result.alreadyRatedIDs, [rated])
        XCTAssertFalse(result.writeAuthRevoked)
        // The nil-score candidate is skipped before any write is attempted.
        XCTAssertEqual(fake.writeCalls, [written, rated, unresolved])
    }

    @MainActor
    func testAutoApplyLoopCapCountsWritesSoNoHRSkipsDontStarveOlderWorkouts() async {
        // Newest candidates have no usable estimate (nil score); older ones do. Skips
        // must not consume the write budget, so both HR-eligible workouts still get
        // written under a cap of 2.
        let newestNoHR = UUID(), secondNoHR = UUID(), olderA = UUID(), olderB = UUID()
        let fake = FakeAutoApplyWriter()
        fake.script = [olderA: .outcome(.written), olderB: .outcome(.written)]
        let candidates = [
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: newestNoHR, score: nil),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: secondNoHR, score: nil),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: olderA, score: 8),
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: olderB, score: 4)
        ]

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 2,
            writer: fake.makeWriter()
        )

        XCTAssertEqual(result.appliedIDs, [olderA, olderB])
        XCTAssertEqual(fake.writeCalls, [olderA, olderB])
    }

    @MainActor
    func testAutoApplyLoopStopsAtWriteCap() async {
        let first = UUID(), second = UUID(), third = UUID()
        let fake = FakeAutoApplyWriter()
        fake.script = [
            first: .outcome(.written),
            second: .outcome(.written),
            third: .outcome(.written)
        ]
        let candidates = [first, second, third].map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 5)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 2,
            writer: fake.makeWriter()
        )

        XCTAssertEqual(result.appliedIDs.count, 2)
        // The third candidate is never written: the cap check breaks before it.
        XCTAssertEqual(fake.writeCalls, [first, second])
        XCTAssertNil(result.writtenScores[third])
    }

    @MainActor
    func testAutoApplyLoopDisablesToggleWhenWriteAuthRevoked() async {
        let written = UUID(), failed = UUID(), afterFailure = UUID()
        let fake = FakeAutoApplyWriter()
        fake.authorizedAfterFailure = false // access revoked after opt-in
        fake.script = [
            written: .outcome(.written),
            failed: .failure,
            afterFailure: .outcome(.written)
        ]
        let candidates = [written, failed, afterFailure].map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 6)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: fake.makeWriter()
        )

        XCTAssertTrue(result.writeAuthRevoked)
        XCTAssertEqual(result.appliedIDs, [written])
        // The batch stops at the failure; the candidate after it is never attempted.
        XCTAssertEqual(fake.writeCalls, [written, failed])
        XCTAssertEqual(fake.authChecks, 1)
    }

    @MainActor
    func testAutoApplyLoopKeepsToggleOnForTransientWriteFailure() async {
        let written = UUID(), failed = UUID(), afterFailure = UUID()
        let fake = FakeAutoApplyWriter()
        fake.authorizedAfterFailure = true // still authorized -> transient error
        fake.script = [
            written: .outcome(.written),
            failed: .failure,
            afterFailure: .outcome(.written)
        ]
        let candidates = [written, failed, afterFailure].map {
            HealthKitWorkoutStore.AutoApplyEffortCandidate(workoutID: $0, score: 6)
        }

        let result = await HealthKitWorkoutStore.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: 25,
            writer: fake.makeWriter()
        )

        XCTAssertFalse(result.writeAuthRevoked)
        XCTAssertEqual(result.appliedIDs, [written])
        XCTAssertEqual(fake.writeCalls, [written, failed])
        XCTAssertEqual(fake.authChecks, 1)
    }

    // MARK: - Sync-badge success signal

    @MainActor
    func testSyncBadgeSignalAdvancesOnlyForUserVisibleGenuineSuccess() {
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A lazy month/ring load reaches success WITHOUT `isRefreshing`
        // (advancesSyncBadge defaults false) — it must not move the badge signal.
        store.markRefreshSucceeded(date: Date(), refreshedVitals: false, publishesWatch: false)
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A user-visible refresh whose queries failed (cached values preserved)
        // is not a genuine fetch — still no advance.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: true,
            publishesWatch: false,
            hadQueryFailure: true,
            advancesSyncBadge: true
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A user-visible refresh that genuinely fetched advances the signal.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: false,
            publishesWatch: false,
            hadQueryFailure: false,
            advancesSyncBadge: true
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 1)
    }

    @MainActor
    func testSyncBadgeSignalDoesNotAdvanceWhenNoQueryRan() {
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // A user-visible pull that dispatched no HealthKit query (a metric or
        // workout month whose permission is disabled, or a readiness recompute)
        // preserved the cached values and must not confirm "Health data updated"
        // — even with `advancesSyncBadge: true` and no query failure.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: false,
            publishesWatch: false,
            hadQueryFailure: false,
            advancesSyncBadge: true,
            ranQueries: false
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)

        // The same path that actually queried advances the signal.
        store.markRefreshSucceeded(
            date: Date(),
            refreshedVitals: false,
            publishesWatch: false,
            hadQueryFailure: false,
            advancesSyncBadge: true,
            ranQueries: true
        )
        XCTAssertEqual(store.syncBadgeSuccessCount, 1)
    }

    @MainActor
    func testFreshnessTTLGateUnchangedByBadgeSignalChange() {
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian)
        )
        XCTAssertNil(store.lastSuccessfulRefreshDate)

        // Vitals refresh with a leaf failure must NOT arm the freshness TTL.
        store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false, hadQueryFailure: true, advancesSyncBadge: true)
        XCTAssertNil(store.lastSuccessfulRefreshDate)

        // Clean vitals refresh arms it.
        let date = Date()
        store.markRefreshSucceeded(date: date, refreshedVitals: true, publishesWatch: false, hadQueryFailure: false, advancesSyncBadge: true)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, date)
    }

    // MARK: - Custom workout names

    @MainActor
    private func customNameStore(defaults: UserDefaults) -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(month: 5, year: 2026, workouts: [], calendar: .bodyGregorian),
            customNameDefaults: defaults
        )
    }

    @MainActor
    func testCustomWorkoutNameSetAndClear() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = customNameStore(defaults: defaults)
        let workoutID = UUID()

        XCTAssertNil(store.workoutCustomNames[workoutID])

        store.setCustomName("Morning Tempo", workoutID: workoutID)
        XCTAssertEqual(store.workoutCustomNames[workoutID], "Morning Tempo")

        // Whitespace-only reads as "no name" and removes the stored rename.
        store.setCustomName("   ", workoutID: workoutID)
        XCTAssertNil(store.workoutCustomNames[workoutID])
        XCTAssertNil(
            (defaults.dictionary(forKey: HealthKitWorkoutStore.workoutCustomNamesKey) as? [String: String])?[workoutID.uuidString]
        )
    }

    @MainActor
    func testCustomWorkoutNameSurvivesRelaunch() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workoutID = UUID()

        customNameStore(defaults: defaults).setCustomName("Easy Spin", workoutID: workoutID)

        XCTAssertEqual(customNameStore(defaults: defaults).workoutCustomNames[workoutID], "Easy Spin")
    }

    @MainActor
    func testCustomWorkoutNameIsTrimmedAndCapped() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = customNameStore(defaults: defaults)
        let workoutID = UUID()

        store.setCustomName("  " + String(repeating: "a", count: 70) + "  ", workoutID: workoutID)

        XCTAssertEqual(store.workoutCustomNames[workoutID], String(repeating: "a", count: 60))
    }

    private struct LegacyHealthDashboardSnapshot: Codable {
        var summary: HealthSummarySnapshot
        var trends: HealthTrendSnapshot
    }
}
