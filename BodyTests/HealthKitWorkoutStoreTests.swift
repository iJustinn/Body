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

    /// A backfill walk may never claim a month newer than its own `walkEnd`.
    ///
    /// This one property is what all three shipped instances of this bug
    /// violated: a chunk claiming months out to the walk end instead of its own
    /// window, a resume re-claiming the checkpoint month, and an empty resumed
    /// walk claiming the RECENT months it never scanned. Each was a hand
    /// computed month set that reached past what was actually read, and because
    /// `replacingLoadedMonths` REPLACES every claimed month, each one deleted
    /// days that were already on disk.
    ///
    /// Asserted over every branch of the key computation rather than over one
    /// scenario, so a fourth instance fails here instead of being found by a
    /// user missing days from their calendar.
    func testBackfillNeverClaimsMonthsNewerThanTheWalkItPerformed() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23)))
        let resumeFrom = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let scannedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 5, day: 1)))
        let dayWithData = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 9)))

        let freshEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(
                date: today, resumeFrom: nil, calendar: calendar
            )
        )
        let resumedEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(
                date: today, resumeFrom: resumeFrom, calendar: calendar
            )
        )

        let cases: [(name: String, earliest: Date?, scanned: Date?, resume: Date?, walkEnd: Date)] = [
            ("fresh walk with data", dayWithData, scannedStart, nil, freshEnd),
            ("fresh walk with no data anywhere", nil, scannedStart, nil, freshEnd),
            ("fresh walk that landed nothing", nil, nil, nil, freshEnd),
            ("resumed walk with data", dayWithData, scannedStart, resumeFrom, resumedEnd),
            ("resumed walk that found no days", nil, scannedStart, resumeFrom, resumedEnd),
            ("resumed walk that landed nothing", nil, nil, resumeFrom, resumedEnd)
        ]

        for scenario in cases {
            let keys = HealthKitFetchEngine.activityRingBackfillLoadedMonthKeys(
                earliestDayWithData: scenario.earliest,
                oldestScannedStart: scenario.scanned,
                walkEnd: scenario.walkEnd,
                resumeFrom: scenario.resume,
                date: today,
                calendar: calendar
            )
            let endKey = ActivityRingMonthKey(date: scenario.walkEnd, calendar: calendar)
            let overreaching = keys.filter { ($0.year, $0.month) > (endKey.year, endKey.month) }
            XCTAssertTrue(
                overreaching.isEmpty,
                "\(scenario.name): claims \(overreaching.map { "\($0.year)-\($0.month)" }) newer than its walk end \(endKey.year)-\(endKey.month), so applying it would delete days it never read"
            )
        }
    }

    /// Walks the real backfill chunk boundaries and asserts no month is ever
    /// claimed by two chunks, and that together they cover the whole span.
    ///
    /// This is the invariant that makes a whole class of silent data loss
    /// unreachable. A landed chunk marks whole months as loaded, and
    /// `replacingLoadedMonths` REPLACES the days of every month an incoming
    /// chunk claims — so if two chunks ever shared a month, the older one
    /// would wipe days the newer one had already published, producing a
    /// plausible-looking calendar that is quietly missing data. An earlier cut
    /// of the chunk walk did exactly that. Month alignment is the only thing
    /// keeping the windows disjoint, so pin it here rather than trusting it.
    func testActivityRingBackfillChunksNeverShareAMonth() throws {
        let calendar = Calendar.bodyGregorian
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23)))
        let historyStart = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: end, calendar: calendar)
        )

        var monthsByChunk: [Set<ActivityRingMonthKey>] = []
        var chunkEnd = end
        // Bounded well above the ten year span so a non-terminating walk fails
        // here instead of hanging the suite.
        for _ in 0..<240 {
            let chunkStart = HealthKitFetchEngine.activityRingBackfillChunkStart(
                endingAt: chunkEnd,
                notBefore: historyStart,
                calendar: calendar
            )
            monthsByChunk.append(
                Set(HealthKitFetchEngine.activityRingMonthKeySpan(from: chunkStart, to: chunkEnd, calendar: calendar))
            )

            guard chunkStart > historyStart else {
                break
            }
            chunkEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: chunkStart))
        }

        XCTAssertGreaterThan(monthsByChunk.count, 1, "The ten year span must take more than one chunk")

        var seen: Set<ActivityRingMonthKey> = []
        for (index, months) in monthsByChunk.enumerated() {
            let overlap = seen.intersection(months)
            XCTAssertTrue(
                overlap.isEmpty,
                "Chunk \(index) re-claims month(s) \(overlap.sorted { ($0.year, $0.month) < ($1.year, $1.month) }) already loaded by an earlier chunk, so applying it would wipe days that chunk published"
            )
            seen.formUnion(months)
        }

        // Disjoint is only half the contract: the chunks must also leave no gap.
        XCTAssertEqual(
            seen,
            Set(HealthKitFetchEngine.activityRingMonthKeySpan(from: historyStart, to: end, calendar: calendar)),
            "The chunk walk must cover every month from the history start through today"
        )
    }

    func testActivityRingDaysClampDropsBoundaryDaysOutsideTheChunkWindow() throws {
        let calendar = Calendar.bodyGregorian
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        // A month aligned chunk, exactly what `activityRingBackfillChunkStart`
        // produces: February 1 through April 30.
        let chunkStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let chunkEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        let dayBefore = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let dayAfter = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let inWindow = try [
            DateComponents(year: 2026, month: 2, day: 1),
            DateComponents(year: 2026, month: 3, day: 14),
            DateComponents(year: 2026, month: 4, day: 30)
        ].map { try XCTUnwrap(calendar.date(from: $0)) }

        let fetched = ([dayBefore] + inWindow + [dayAfter]).map {
            ActivityRingDaySummary(date: $0, summary: summary)
        }
        let clamped = HealthKitFetchEngine.activityRingDays(
            fetched,
            from: chunkStart,
            through: chunkEnd,
            calendar: calendar
        )

        XCTAssertEqual(
            clamped.map(\.date),
            inWindow,
            "A components-predicated ring query can return boundary days outside the requested window; they must not enter the chunk"
        )

        // The claimed month span is derived from the oldest day, so an unclamped
        // boundary day is what lets a chunk claim a neighbouring chunk's month —
        // and `replacingLoadedMonths` REPLACES those months rather than merging.
        let clampedMonths = try HealthKitFetchEngine.activityRingMonthKeySpan(
            from: XCTUnwrap(clamped.first).date,
            to: chunkEnd,
            calendar: calendar
        )
        XCTAssertEqual(
            Set(clampedMonths),
            Set(HealthKitFetchEngine.activityRingMonthKeySpan(from: chunkStart, to: chunkEnd, calendar: calendar)),
            "The clamped chunk must claim exactly the months its own window covers"
        )
        XCTAssertFalse(
            clampedMonths.contains(ActivityRingMonthKey(month: 1, year: 2026)),
            "A January boundary day must not make a February chunk claim — and so wipe — January"
        )

        let unclampedMonths = HealthKitFetchEngine.activityRingMonthKeySpan(
            from: dayBefore,
            to: chunkEnd,
            calendar: calendar
        )
        XCTAssertTrue(
            unclampedMonths.contains(ActivityRingMonthKey(month: 1, year: 2026)),
            "Guard that the unclamped span really would have reached the neighbouring month"
        )
    }

    func testActivityRingDaysClampLeavesDaysAlreadyInsideTheWindowUnchanged() throws {
        let calendar = Calendar.bodyGregorian
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        let chunkStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let chunkEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: 30)))
        // A mid-day timestamp still belongs to its day: the window is compared
        // at day granularity, not instant granularity.
        let days = try [
            DateComponents(year: 2026, month: 2, day: 1, hour: 23, minute: 59),
            DateComponents(year: 2026, month: 3, day: 14),
            DateComponents(year: 2026, month: 4, day: 30, hour: 13)
        ].map { ActivityRingDaySummary(date: try XCTUnwrap(calendar.date(from: $0)), summary: summary) }

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingDays(
                days,
                from: chunkStart,
                through: chunkEnd,
                calendar: calendar
            ),
            days,
            "Clamping must be a no-op when every fetched day already falls inside the requested window"
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

    func testActivityRingBackfillStatePersistsEveryCaseAndClears() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults),
            .pending(resumeFrom: nil)
        )

        // The resume checkpoint round-trips, so an interrupted walk continues
        // instead of restarting at today.
        let resumeFrom = Date(timeIntervalSince1970: 1_700_000_000)
        HealthDashboardSnapshotStore.saveActivityRingBackfillState(.pending(resumeFrom: resumeFrom), defaults: defaults)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults),
            .pending(resumeFrom: resumeFrom)
        )

        let lastProbe = Date(timeIntervalSince1970: 1_710_000_000)
        HealthDashboardSnapshotStore.saveActivityRingBackfillState(.suppressed(lastProbe: lastProbe), defaults: defaults)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults),
            .suppressed(lastProbe: lastProbe)
        )

        HealthDashboardSnapshotStore.saveActivityRingBackfillState(.completed, defaults: defaults)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults), .completed)

        HealthDashboardSnapshotStore.clearActivityRingBackfillState(defaults: defaults)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults),
            .pending(resumeFrom: nil)
        )
    }

    func testActivityRingBackfillStateMigratesTheLegacyCompletedFlag() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        // An install that finished the ten-year scan under the old Boolean
        // marker must not be made to redo it.
        defaults.set(true, forKey: HealthDashboardSnapshotStore.activityRingBackfillCompletedKey)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults), .completed)

        // And moving off `.completed` clears the legacy key with it.
        HealthDashboardSnapshotStore.saveActivityRingBackfillState(.pending(resumeFrom: nil), defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: HealthDashboardSnapshotStore.activityRingBackfillCompletedKey))
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(defaults: defaults),
            .pending(resumeFrom: nil)
        )
    }

    func testActivityRingBackfillCompletesOnlyWhenTheWalkReachesHistoryStart() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let checkpoint = Date(timeIntervalSince1970: 1_700_000_000)

        // A partial chunk that carried days is NOT a finished ten-year history:
        // it keeps the walk pending, at the checkpoint it got to.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: nil),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: checkpoint,
                foundDays: true,
                now: now
            ),
            .pending(resumeFrom: checkpoint)
        )

        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: checkpoint),
                authorizationDenied: false,
                reachedHistoryStart: true,
                nextChunkEndDate: nil,
                foundDays: true,
                now: now
            ),
            .completed
        )

        // A failed walk reports no new checkpoint; the old one stands so the
        // retry doesn't start over at today.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: checkpoint),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: false,
                now: now
            ),
            .pending(resumeFrom: checkpoint)
        )

        // A finished backfill's recent-window reads don't un-finish it.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .completed,
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: true,
                now: now
            ),
            .completed
        )
    }

    func testDeniedActivityRingReadSuppressesBackfillUntilAReadFindsDaysAgain() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let checkpoint = Date(timeIntervalSince1970: 1_700_000_000)

        // Denial parks the heavy scan instead of clearing the marker, which used
        // to re-issue the whole ten-year query on every single refresh.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .pending(resumeFrom: checkpoint),
                authorizationDenied: true,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: false,
                now: now
            ),
            .suppressed(lastProbe: now)
        )

        // A cheap probe that still finds nothing leaves it parked…
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .suppressed(lastProbe: now),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: false,
                now: now
            ),
            .suppressed(lastProbe: now)
        )

        // …and one that comes back with days re-arms it.
        XCTAssertEqual(
            HealthKitWorkoutStore.nextActivityRingBackfillState(
                current: .suppressed(lastProbe: now),
                authorizationDenied: false,
                reachedHistoryStart: false,
                nextChunkEndDate: nil,
                foundDays: true,
                now: now
            ),
            .pending(resumeFrom: nil)
        )
    }

    @MainActor
    func testNeedsInitialHealthDataLoadReflectsCacheAndRefreshState() throws {
        // The store reads the persisted refresh timestamp and the first-load
        // completion flag from standard defaults at init; park both so a
        // previous run on this host cannot mask the fresh-install state.
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

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
    func testPartialRefreshClearsNeedsInitialHealthDataLoadWithoutArmingFreshnessTTL() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }

        let store = emptyHealthDataStore()
        XCTAssertTrue(store.needsInitialHealthDataLoad)

        // Denied read permissions make some leaves fail on every refresh; the
        // completed full refresh still counts as the first load.
        store.markRefreshSucceeded(date: Date(), refreshedVitals: true, hadQueryFailure: true)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)
        XCTAssertFalse(store.needsInitialHealthDataLoad)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasHealthDataToShow)
    }

    @MainActor
    func testNonVitalsRefreshLeavesInitialHealthDataLoadPending() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }

        let store = emptyHealthDataStore()
        store.markRefreshSucceeded(date: Date(), refreshedVitals: false)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
        XCTAssertTrue(store.needsInitialHealthDataLoad)
    }

    @MainActor
    func testInitialHealthDataLoadCompletionRestoresFromPersistence() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }

        emptyHealthDataStore().markRefreshSucceeded(date: Date(), refreshedVitals: true, hadQueryFailure: true)

        let relaunchedStore = emptyHealthDataStore()
        XCTAssertTrue(relaunchedStore.hasCompletedInitialHealthDataLoad)
        XCTAssertFalse(relaunchedStore.needsInitialHealthDataLoad)
    }

    @MainActor
    func testClearLocalCacheResetsInitialHealthDataLoadCompletion() async throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }

        let store = emptyHealthDataStore()
        store.markRefreshSucceeded(date: Date(), refreshedVitals: true, hadQueryFailure: true)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)

        await store.clearLocalCache()
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
        XCTAssertFalse(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted())
        XCTAssertTrue(store.needsInitialHealthDataLoad)
    }

    @MainActor
    func testInitialHealthDataLoadCompletedPersistenceRoundTrips() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "HealthDashboardSnapshotStoreTests.initialLoad"))
        defer { defaults.removePersistentDomain(forName: "HealthDashboardSnapshotStoreTests.initialLoad") }

        XCTAssertFalse(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted(defaults: defaults))
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted(defaults: defaults)
        XCTAssertTrue(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted(defaults: defaults))
        HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted(defaults: defaults)
        XCTAssertFalse(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted(defaults: defaults))
    }

    /// The store reads both first-load defaults from standard defaults at init;
    /// park them so a previous run on this host cannot mask the fresh-install
    /// state, and restore them from the returned closure.
    private func preserveInitialHealthLoadDefaults() -> () -> Void {
        let preservedRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        let preservedCompletion = HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
        return {
            if let preservedRefreshDate {
                HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(preservedRefreshDate)
            }
            if preservedCompletion {
                HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()
            } else {
                HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
            }
        }
    }

    @MainActor
    private func emptyHealthDataStore() -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty
        )
    }

    /// Ring chunks only apply while Activity Rings is on in Body's own
    /// selection, so a store used to drive them must say so explicitly rather
    /// than inherit whatever this host has stored.
    @MainActor
    private func activityRingsEnabledStore() -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.activityRings])
        )
    }

    private func activityRingChunk(
        days: [Date],
        loadedMonthKeys: [ActivityRingMonthKey]
    ) -> ActivityRingHistorySnapshot {
        let summary = ActivityRingSummary(
            move: ActivityRingMetric(value: 500, goal: 500),
            exercise: ActivityRingMetric(value: 30, goal: 30),
            stand: ActivityRingMetric(value: 12, goal: 12)
        )
        return ActivityRingHistorySnapshot(
            days: days.map { ActivityRingDaySummary(date: $0, summary: summary) },
            loadedMonthKeys: loadedMonthKeys
        )
    }

    /// One chunk shaped the way the newest-first backfill walk hands them over:
    /// only that chunk's days, plus the checkpoint to resume from. A `nil`
    /// checkpoint is the chunk that reached history start.
    private func activityRingBackfillChunk(
        days: [Date],
        loadedMonthKeys: [ActivityRingMonthKey],
        nextChunkEndDate: Date?
    ) -> ActivityRingHistoryFetchResult {
        ActivityRingHistoryFetchResult(
            history: activityRingChunk(days: days, loadedMonthKeys: loadedMonthKeys),
            hadQueryFailure: false,
            reachedHistoryStart: nextChunkEndDate == nil,
            nextChunkEndDate: nextChunkEndDate
        )
    }

    /// The backfill checkpoint lives in standard defaults; park it so a previous
    /// run on this host can't mask a fresh walk, and restore it afterwards.
    private func preserveActivityRingBackfillState() -> () -> Void {
        let preserved = HealthDashboardSnapshotStore.loadActivityRingBackfillState()
        HealthDashboardSnapshotStore.clearActivityRingBackfillState()
        return {
            HealthDashboardSnapshotStore.saveActivityRingBackfillState(preserved)
        }
    }

    /// Ring history now arrives in chunks AFTER the refresh has finished, so the
    /// chunks have to accumulate: a later, older chunk merges underneath the
    /// months already on screen instead of replacing them.
    @MainActor
    func testActivityRingHistoryChunksAccumulateThroughTheApplyFunnel() throws {
        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let january7 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 7)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                activityRingChunk(days: [march5], loadedMonthKeys: [marchKey]),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 1)

        // The newest-first walk hands back the older span second.
        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                activityRingChunk(days: [january7], loadedMonthKeys: [januaryKey, februaryKey]),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [january7, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [januaryKey, februaryKey, marchKey])
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 3)
    }

    @MainActor
    func testActivityRingHistoryChunkFromBeforeAClearCacheIsDropped() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)
        let chunk = activityRingChunk(days: [march5], loadedMonthKeys: [marchKey])

        XCTAssertTrue(store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0))

        // The walk was requested under the pre-wipe epoch, so its next chunk
        // must not resurrect the history the wipe just dropped.
        await store.clearLocalCache()
        XCTAssertFalse(store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0))
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 0)
    }

    /// The ten-year walk runs for minutes, so every chunk has to be on screen
    /// AND on disk the moment it lands — not accumulated and applied once at the
    /// end, which is what made the calendar appear in a single step.
    @MainActor
    func testActivityRingBackfillChunksLandAndCheckpointAsTheyArrive() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = emptyHealthDataStore()
        let january20 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 20)))
        let february10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let februaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let januaryKey = ActivityRingMonthKey(month: 1, year: 2026)
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        // Chunk one: the newest month is on screen and checkpointed while the
        // rest of the walk is still querying.
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [marchKey],
                    nextChunkEndDate: marchStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [marchKey])
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: marchStart)
        )

        // Chunk two merges underneath it and moves the checkpoint back with it.
        // It claims only the months its own window covered, so the merge cannot
        // replace the month chunk one already published.
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [february10],
                    loadedMonthKeys: [februaryKey],
                    nextChunkEndDate: februaryStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [february10, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [februaryKey, marchKey])
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: februaryStart)
        )

        // The chunk that reached history start carries no checkpoint of its own:
        // whether the walk `completed` is the terminal state's call, so this
        // must not rewrite the resume point to something bogus.
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [january20],
                    loadedMonthKeys: [januaryKey],
                    nextChunkEndDate: nil
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [january20, february10, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [januaryKey, februaryKey, marchKey])
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 3)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: februaryStart)
        )
    }

    /// A walk killed part way through (quit, cancellation) keeps what landed and
    /// resumes at that chunk's boundary. Applying only at the end threw every
    /// landed month away and restarted the whole scan at today.
    @MainActor
    func testInterruptedActivityRingBackfillKeepsLandedChunksAndResumesFromTheirBoundary() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = emptyHealthDataStore()
        let february10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let februaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [marchKey],
                    nextChunkEndDate: marchStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [february10],
                    loadedMonthKeys: [februaryKey],
                    nextChunkEndDate: februaryStart
                ),
                capturedEpoch: 0
            )
        )

        // …and the walk dies here, with older chunks still unqueried.
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [february10, march5])
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [februaryKey, marchKey])
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: februaryStart)
        )
        XCTAssertNotEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: nil)
        )
    }

    /// The refusal that stops the walk: once a Clear Cache has bumped the epoch,
    /// the chunk is dropped and the checkpoint stays at the wiped state rather
    /// than being pushed back to a resume point for history that no longer
    /// exists.
    @MainActor
    func testActivityRingBackfillChunkFromBeforeAClearCacheStopsTheWalk() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = emptyHealthDataStore()
        let february10 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10)))
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let februaryStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let marchStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let februaryKey = ActivityRingMonthKey(month: 2, year: 2026)
        let marchKey = ActivityRingMonthKey(month: 3, year: 2026)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [marchKey],
                    nextChunkEndDate: marchStart
                ),
                capturedEpoch: 0
            )
        )

        await store.clearLocalCache()

        XCTAssertFalse(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [february10],
                    loadedMonthKeys: [februaryKey],
                    nextChunkEndDate: februaryStart
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: nil)
        )
    }

    /// Ring history is out of the refresh's completion barrier: the refresh
    /// stamps success with no ring history at all, and chunks landing afterwards
    /// don't touch anything the refresh owns.
    @MainActor
    func testRefreshStampsSuccessWhileRingHistoryIsStillOutstanding() throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let refreshDate = Date(timeIntervalSince1970: 1_760_000_000)

        store.markRefreshSucceeded(
            date: refreshDate,
            refreshedVitals: true,
            publishesWatch: false,
            advancesSyncBadge: true
        )

        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDate)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)
        XCTAssertFalse(store.needsInitialHealthDataLoad)
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)

        let badgeCountAfterRefresh = store.syncBadgeSuccessCount
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                activityRingChunk(days: [march5], loadedMonthKeys: [ActivityRingMonthKey(month: 3, year: 2026)]),
                capturedEpoch: 0
            )
        )

        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march5])
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDate)
        XCTAssertEqual(store.syncBadgeSuccessCount, badgeCountAfterRefresh)
    }

    @MainActor
    func testRefreshWithinTheDeadlineCompletesAndStampsSuccess() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        let refreshDate = Date(timeIntervalSince1970: 1_760_000_000)

        let completed = await store.runRefreshWithDeadline(.seconds(30)) {
            store.markRefreshSucceeded(date: refreshDate, refreshedVitals: true, publishesWatch: false)
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDate)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)
        XCTAssertNil(store.healthDataNotice)
    }

    @MainActor
    func testRefreshDeadlineAbandonsTheBodyWithoutStampingSuccess() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        let lateFinisher = expectation(description: "abandoned refresh body finished")

        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            // The abandoned body keeps running and tries to finish the refresh
            // it no longer speaks for.
            store.markRefreshSucceeded(
                date: Date(),
                refreshedVitals: true,
                publishesWatch: false,
                advancesSyncBadge: true
            )
            lateFinisher.fulfill()
        }

        XCTAssertFalse(completed)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(
            store.healthDataNotice,
            String(localized: "Loading Apple Health data is taking longer than expected. Please try again.")
        )
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)

        await fulfillment(of: [lateFinisher], timeout: 5)

        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)
        XCTAssertFalse(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted())
    }

    /// A backfill checkpoint is EXCLUSIVE, so the resumed walk starts one day
    /// older and never re-claims the checkpoint's month. `replacingLoadedMonths`
    /// REPLACES every month an incoming chunk claims, so a resumed chunk that
    /// claimed August while carrying only August 1 would delete August 2 to 31
    /// from the cache.
    @MainActor
    func testResumedBackfillWalkStartsOlderThanTheCheckpointAndKeepsItsMonth() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let augustKey = ActivityRingMonthKey(month: 8, year: 2025)
        let julyKey = ActivityRingMonthKey(month: 7, year: 2025)
        let augustDays = try (1...31).map { day in
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 8, day: day)))
        }
        // What the engine hands back for a chunk covering August: month aligned,
        // checkpointed at its own `chunkStart`.
        let checkpoint = try XCTUnwrap(augustDays.first)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: augustDays,
                    loadedMonthKeys: [augustKey],
                    nextChunkEndDate: checkpoint
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.count, 31)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: checkpoint)
        )

        // The resumption converts that exclusive checkpoint to July 31…
        let resumedWalkEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(
                date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 15))),
                resumeFrom: checkpoint,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            resumedWalkEnd,
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 31)))
        )

        // …so the chunk it produces claims July, not August, and August survives.
        let july20 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 20)))
        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [july20],
                    loadedMonthKeys: [julyKey],
                    nextChunkEndDate: try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 7, day: 1)))
                ),
                capturedEpoch: 0
            )
        )

        let survivingAugustDays = store.activityRingHistory.days
            .filter { ActivityRingMonthKey(date: $0.date, calendar: calendar) == augustKey }
        XCTAssertEqual(survivingAugustDays.map(\.date), augustDays)
        XCTAssertEqual(store.activityRingHistory.loadedMonthKeys, [julyKey, augustKey])
    }

    /// A resumed walk that scans OLDER history and correctly finds nothing
    /// there must claim only the stretch it scanned. The recent-window fallback
    /// is for an account with no ring data anywhere; firing it here would claim
    /// months this walk never looked at, and `replacingLoadedMonths` REPLACES
    /// every claimed month — deleting the recent days the interrupted first run
    /// had already saved.
    @MainActor
    func testResumedBackfillFindingNoDaysKeepsTheRecentMonthsAlreadySaved() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let now = Date()
        // What the interrupted first run saved: the newest chunk, checkpointed
        // at its own month-aligned start.
        let recentDay = calendar.startOfDay(for: now)
        let recentKey = ActivityRingMonthKey(date: recentDay, calendar: calendar)
        let checkpoint = try XCTUnwrap(calendar.dateInterval(of: .month, for: recentDay)?.start)

        XCTAssertTrue(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [recentDay],
                    loadedMonthKeys: [recentKey],
                    nextChunkEndDate: checkpoint
                ),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [recentDay])

        // The resumed walk reads older history and lands chunks that hold no
        // ring days at all.
        let walkEnd = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(date: now, resumeFrom: checkpoint, calendar: calendar)
        )
        let historyStart = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: now, calendar: calendar)
        )
        let scannedStart = HealthKitFetchEngine.activityRingBackfillChunkStart(
            endingAt: walkEnd,
            notBefore: historyStart,
            calendar: calendar
        )
        let emptyWalkKeys = HealthKitFetchEngine.activityRingBackfillLoadedMonthKeys(
            earliestDayWithData: nil,
            oldestScannedStart: scannedStart,
            walkEnd: walkEnd,
            resumeFrom: checkpoint,
            date: now,
            calendar: calendar
        )

        // The recent-window fallback — what this used to resolve to — always
        // names the current month, so landing it would have replaced the month
        // holding `recentDay` with nothing.
        XCTAssertTrue(
            HealthKitFetchEngine.recentActivityRingMonthKeys(
                count: HealthKitWorkoutStore.recentChartMonthCount,
                from: now,
                calendar: calendar
            ).contains(recentKey)
        )
        XCTAssertFalse(emptyWalkKeys.contains(recentKey))
        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                ActivityRingHistorySnapshot(days: [], loadedMonthKeys: emptyWalkKeys),
                capturedEpoch: 0
            )
        )
        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [recentDay])
        XCTAssertTrue(store.activityRingHistory.loadedMonthKeys.contains(recentKey))
    }

    /// The same terminal decision on a FRESH walk still claims the recent
    /// window, so an account with no ring data anywhere renders empty grids.
    func testFreshBackfillFindingNoDaysStillClaimsTheRecentWindow() throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))
        let historyStart = try XCTUnwrap(
            HealthKitFetchEngine.activityRingBackfillStartDate(date: now, calendar: calendar)
        )

        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillLoadedMonthKeys(
                earliestDayWithData: nil,
                oldestScannedStart: HealthKitFetchEngine.activityRingBackfillChunkStart(
                    endingAt: now,
                    notBefore: historyStart,
                    calendar: calendar
                ),
                walkEnd: now,
                resumeFrom: nil,
                date: now,
                calendar: calendar
            ),
            HealthKitFetchEngine.recentActivityRingMonthKeys(
                count: HealthKitWorkoutStore.recentChartMonthCount,
                from: now,
                calendar: calendar
            )
        )
    }

    func testBackfillWalkEndResumesAtTodayWhenNoChunkEverLanded() throws {
        let calendar = Calendar.bodyGregorian
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 20)))

        // A fresh walk starts at today.
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(date: today, resumeFrom: nil, calendar: calendar),
            today
        )

        // A walk that landed nothing checkpoints at `end + 1 day`, so the same
        // exclusive conversion resumes at today rather than skipping a day.
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(
            HealthKitFetchEngine.activityRingBackfillWalkEnd(date: today, resumeFrom: tomorrow, calendar: calendar),
            today
        )
    }

    /// Switching Activity Rings off purges the cached history and the backfill
    /// progress, but the walk can already have a chunk in flight — cancellation
    /// cannot catch that one, so it is refused at the point of application.
    @MainActor
    func testActivityRingChunkIsRefusedAfterRingsAreSwitchedOff() throws {
        let restoreBackfillState = preserveActivityRingBackfillState()
        defer { restoreBackfillState() }

        let calendar = Calendar.bodyGregorian
        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 5,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: [.steps])
        )
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let march1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))

        XCTAssertFalse(
            store.landActivityRingBackfillChunk(
                activityRingBackfillChunk(
                    days: [march5],
                    loadedMonthKeys: [ActivityRingMonthKey(month: 3, year: 2026)],
                    nextChunkEndDate: march1
                ),
                capturedEpoch: 0
            )
        )

        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        XCTAssertEqual(store.cacheStatus.activityRingMonthCount, 0)
        // And the refused chunk must not push the reset progress back to a
        // checkpoint the user has opted out of.
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadActivityRingBackfillState(),
            .pending(resumeFrom: nil)
        )
    }

    /// The per-workout heart-rate reads are continuation based, so
    /// `fetchWorkouts` can return normally minutes after the deadline fired —
    /// long enough for a newer retry to have published the same months.
    @MainActor
    func testAbandonedRefreshCannotPublishMonthSnapshots() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        XCTAssertTrue(store.mayPublishMonthSnapshot(capturedEpoch: 0))

        let lateMonthWrite = expectation(description: "abandoned workout fetch returned")
        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            XCTAssertFalse(store.mayPublishMonthSnapshot(capturedEpoch: 0))
            lateMonthWrite.fulfill()
        }

        XCTAssertFalse(completed)
        await fulfillment(of: [lateMonthWrite], timeout: 5)
        // A newer refresh's own month writes are unaffected.
        XCTAssertTrue(store.mayPublishMonthSnapshot(capturedEpoch: 0))
    }

    /// Same deadline contract on the single-metric pull (the metric detail
    /// screen's own spinner), whose success stamp is the sync badge rather than
    /// the freshness TTL: `refreshHealthMetric` runs its fetch/publish half
    /// through the same wrapper, so a stuck metric query can't strand that
    /// spinner either.
    @MainActor
    func testMetricRefreshDeadlineAbandonsTheBodyWithoutStampingSuccess() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        let lateFinisher = expectation(description: "abandoned metric refresh body finished")

        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            store.markRefreshSucceeded(
                date: Date(),
                refreshedVitals: false,
                publishesWatch: false,
                advancesSyncBadge: true
            )
            lateFinisher.fulfill()
        }

        XCTAssertFalse(completed)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(
            store.healthDataNotice,
            String(localized: "Loading Apple Health data is taking longer than expected. Please try again.")
        )

        await fulfillment(of: [lateFinisher], timeout: 5)

        XCTAssertEqual(store.syncBadgeSuccessCount, 0)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
    }

    @MainActor
    func testRefreshCompletionWaiterResumesOnCancellationInsteadOfLeaking() async {
        let waiters = HealthKitWorkoutStore.RefreshCompletionWaiters()
        let parked = Task { @MainActor in await waiters.park() }

        var spins = 0
        while waiters.isEmpty, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertFalse(waiters.isEmpty)

        // Nothing but `finishRefresh` used to resume these, so a cancelled
        // waiter parked its continuation forever.
        parked.cancel()
        await parked.value
        XCTAssertTrue(waiters.isEmpty)

        // And the drain that follows must not resume the same waiter twice.
        waiters.resumeAll()
    }

    @MainActor
    func testRefreshCompletionWaitersResumeWhenTheRefreshFinishes() async {
        let waiters = HealthKitWorkoutStore.RefreshCompletionWaiters()
        let resumed = expectation(description: "waiter resumed")
        Task { @MainActor in
            await waiters.park()
            resumed.fulfill()
        }

        var spins = 0
        while waiters.isEmpty, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertFalse(waiters.isEmpty)

        waiters.resumeAll()
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertTrue(waiters.isEmpty)
    }

    @MainActor
    func testPassiveLoadsStayIdleUntilFirstHealthDataLoad() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

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

    @MainActor
    func testWidgetReloadCoalescerServesReloadRequestedDuringReload() async {
        var reloadCount = 0
        var coalescer: BodyWidgetReloadCoalescer?
        coalescer = BodyWidgetReloadCoalescer(debounceNanoseconds: 5_000_000) {
            reloadCount += 1
            if reloadCount == 1 {
                coalescer?.requestReload()
            }
        }

        coalescer?.requestReload()
        try? await Task.sleep(nanoseconds: 120_000_000)
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

    /// Only aged entries persist: the trailing window is re-queried every launch
    /// so a rating added right after a workout still converges, and anything past
    /// the 408-day training-load window is pruned so the file can't grow forever.
    func testPersistableEffortLedgerKeepsOnlyAgedEntriesInsideTheTrainingLoadWindow() {
        let now = Date()
        let aged = UUID()
        let agedUnrated = UUID()
        let recent = UUID()
        let expired = UUID()

        func range(daysAgo: Double) -> WorkoutEffortDateRange {
            let start = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)
            return WorkoutEffortDateRange(startDate: start, endDate: start.addingTimeInterval(3_600))
        }

        let ledger = HealthKitFetchEngine.persistableEffortLedger(
            effortLevels: [aged: 6, recent: 8, expired: 4],
            confirmedNoEffortIDs: [agedUnrated],
            dates: [
                aged: range(daysAgo: 30),
                agedUnrated: range(daysAgo: 45),
                recent: range(daysAgo: 1),
                expired: range(daysAgo: 500)
            ],
            now: now
        )

        XCTAssertEqual(Set(ledger.entries.keys), [aged, agedUnrated])
        XCTAssertEqual(ledger.entries[aged]?.effort, 6)
        // A confirmed absence is worth persisting too — it also skips a query.
        XCTAssertNil(ledger.entries[agedUnrated]?.effort)
    }

    /// Pull-to-refresh drops the displayed months plus the unconfirmable trailing
    /// window, and keeps the aged rest of the training-load window.
    func testScopedEffortClearCoversDisplayedMonthsAndTheTrailingWindow() {
        let calendar = Calendar.bodyGregorian
        let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 20, hour: 12))!
        let displayedMonth = UUID()
        let recent = UUID()
        let aged = UUID()

        func range(_ start: Date) -> WorkoutEffortDateRange {
            WorkoutEffortDateRange(startDate: start, endDate: start.addingTimeInterval(3_600))
        }

        let cleared = HealthKitFetchEngine.effortIDsClearedByScopedRefresh(
            dates: [
                displayedMonth: range(calendar.date(from: DateComponents(year: 2025, month: 5, day: 2))!),
                recent: range(now.addingTimeInterval(-3 * 60 * 60)),
                aged: range(calendar.date(from: DateComponents(year: 2025, month: 1, day: 9))!)
            ],
            // Deliberately omits the current month, so `recent` can only be
            // cleared by the trailing-window clause.
            monthKeys: [BodyWorkoutMonthKey(month: 5, year: 2025)],
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(cleared, [displayedMonth, recent])
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

    func testDetailMetricReuseRequiresAgedWorkoutWithNonNilCachedField() {
        let now = Date()
        let duration: TimeInterval = 3_600
        let agedStart = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let recentStart = now.addingTimeInterval(-2 * 60 * 60)

        func cachedSummary(id: UUID, startDate: Date, cadence: Double?) -> WorkoutSummary {
            WorkoutSummary(
                id: id,
                type: .running,
                startDate: startDate,
                duration: duration,
                averageStepCadenceSPM: cadence
            )
        }

        let reusable = UUID()
        // Cached before the field existed (or genuinely value-less) — both
        // decode as nil and must be re-queried, never reused.
        let nilField = UUID()
        let dateMismatch = UUID()
        let tooRecent = UUID()
        let uncached = UUID()

        let workouts: [(id: UUID, startDate: Date, duration: TimeInterval)] = [
            (reusable, agedStart, duration),
            (nilField, agedStart, duration),
            (dateMismatch, agedStart, duration),
            (tooRecent, recentStart, duration),
            (uncached, agedStart, duration)
        ]
        let cachedSummaries: [UUID: WorkoutSummary] = [
            reusable: cachedSummary(id: reusable, startDate: agedStart, cadence: 168),
            nilField: cachedSummary(id: nilField, startDate: agedStart, cadence: nil),
            dateMismatch: cachedSummary(id: dateMismatch, startDate: agedStart.addingTimeInterval(5), cadence: 170),
            tooRecent: cachedSummary(id: tooRecent, startDate: recentStart, cadence: 172)
        ]

        let reusableValues = HealthKitFetchEngine.reusableWorkoutDetailMetricValues(
            workouts: workouts,
            cachedSummaries: cachedSummaries,
            now: now,
            cachedValue: \.averageStepCadenceSPM
        )

        XCTAssertEqual(reusableValues, [reusable: 168])
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

    // MARK: - Permissions sheet access states

    @MainActor
    private func accessStateStore(
        ringHistory: ActivityRingHistorySnapshot,
        permissionSelection: BodyHealthPermissionSelection = .defaultValue
    ) -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 1,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: HealthDashboardSnapshot(
                summary: .empty,
                trends: .empty,
                activityRingHistory: ringHistory
            ),
            initialPermissionSelection: permissionSelection
        )
    }

    private func ringDay(month: Int, day: Int) throws -> ActivityRingDaySummary {
        let date = try XCTUnwrap(
            Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: month, day: day))
        )
        return ActivityRingDaySummary(
            date: date,
            summary: ActivityRingSummary(
                move: ActivityRingMetric(value: 500, goal: 500),
                exercise: ActivityRingMetric(value: 30, goal: 30),
                stand: ActivityRingMetric(value: 12, goal: 12)
            )
        )
    }

    /// Regression: the backfill deliberately retains `loadedMonthKeys` for months
    /// that hold no days. A presence check built on "did filtering change
    /// anything" saw those keys disappear and reported data where there is none.
    /// Asking the snapshot's own `isEmpty` counts days, which is the real question.
    @MainActor
    func testCoveredButEmptyRingMonthsReportNoDataRatherThanData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: ActivityRingHistorySnapshot(
                days: [],
                loadedMonthKeys: [
                    ActivityRingMonthKey(month: 1, year: 2026),
                    ActivityRingMonthKey(month: 2, year: 2026)
                ]
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.activityRings], .noData)
    }

    @MainActor
    func testRingDaysReportHasData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: ActivityRingHistorySnapshot(
                days: [try ringDay(month: 1, day: 5)],
                loadedMonthKeys: [ActivityRingMonthKey(month: 1, year: 2026)]
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.activityRings], .hasData)
    }

    /// Regression: `BodyDashboardFetchSelection` is built from the Home-card
    /// layout, not from permissions, and a metric it excludes is never queried at
    /// all. Hiding a card must not be reported as Apple Health withholding data.
    @MainActor
    func testHiddenDashboardCardsReportNotUsedByDashboardRatherThanNoData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(ringHistory: .empty)
        let noCards = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: []),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: noCards)
        XCTAssertEqual(states[.activityRings], .notUsedByDashboard)
        XCTAssertEqual(states[.heart], .notUsedByDashboard)
        XCTAssertEqual(states[.steps], .notUsedByDashboard)
    }

    /// A switch the user turned off must never be reported as missing data, even
    /// while the cache still holds values read before the opt out.
    @MainActor
    func testDisabledPermissionReportsOffEvenWithCachedData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: ActivityRingHistorySnapshot(days: [try ringDay(month: 1, day: 5)]),
            permissionSelection: BodyHealthPermissionSelection(
                enabledPermissions: Set(BodyHealthPermission.allCases).subtracting([.activityRings])
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.activityRings], .off)
    }

    /// Opening the Permissions sheet must be free: it reads published state only,
    /// so it can never kick off a HealthKit read or disturb refresh bookkeeping.
    @MainActor
    func testAccessStatesReadPublishedStateWithoutStartingWork() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(ringHistory: .empty)
        let refreshDateBefore = store.lastSuccessfulRefreshDate

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)

        XCTAssertEqual(states.count, BodyHealthPermission.allCases.count)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDateBefore)
    }

    /// Regression: readiness is derived, deliberately survives every permission
    /// filter, and is counted by both `isEmpty`s — so one cached readiness score
    /// made every category read "Body has data" even when that category was
    /// empty. The presence probe must strip readiness before asking.
    @MainActor
    func testCachedReadinessAloneDoesNotMakeCategoriesReportData() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        var summary = HealthSummarySnapshot.empty
        summary.readiness.score = 80
        var trends = HealthTrendSnapshot.empty
        trends.recordedReadiness = [
            RecordedReadinessEntry(date: Date(timeIntervalSince1970: 1_770_000_000), score: 80)
        ]

        let store = HealthKitWorkoutStore(
            initialSnapshot: WorkoutMonthSnapshot.make(
                month: 1,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            ),
            initialHealthDashboardSnapshot: HealthDashboardSnapshot(
                summary: summary,
                trends: trends,
                activityRingHistory: .empty
            )
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)
        XCTAssertEqual(states[.bloodOxygen], .noData)
        XCTAssertEqual(states[.activityRings], .noData)
        XCTAssertEqual(states[.heart], .noData)
        XCTAssertEqual(states[.sleep], .noData)
    }

    /// Stress-only layout, Heart on: sleep and HRV are fetched by the dashboard
    /// refresh itself (`.inputCapable`), and with Heart enabled the heart-gated
    /// Stress input loader also queries heart rate/steps/active energy — so all
    /// three report as used by the dashboard, not `.notUsedByDashboard`.
    @MainActor
    func testStressOnlyLayoutWithHeartOnMarksInputDependenciesDashboardUsed() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(ringHistory: .empty)
        let stressOnly = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: [.stress]),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: stressOnly)

        XCTAssertNotEqual(states[.heart], .notUsedByDashboard)
        XCTAssertNotEqual(states[.steps], .notUsedByDashboard)
        XCTAssertNotEqual(states[.energy], .notUsedByDashboard)
    }

    /// Stress-only layout, Heart off: the Stress input loader is heart-gated
    /// (`startStressInputLoadIfNeeded`), so with Heart off it never queries
    /// steps/energy — they must report `.notUsedByDashboard`, not a false
    /// "no data". Sleep is unaffected: it's one of the engine's own
    /// `.inputCapable` leaves, refresh-fetched regardless of Heart.
    @MainActor
    func testStressOnlyLayoutWithHeartOffLeavesStepsAndEnergyNotDashboardUsed() throws {
        let preserved = preserveInitialHealthLoadDefaults()
        defer { preserved() }
        HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()

        let store = accessStateStore(
            ringHistory: .empty,
            permissionSelection: BodyHealthPermissionSelection(
                enabledPermissions: Set(BodyHealthPermission.allCases).subtracting([.heart])
            )
        )
        let stressOnly = BodyDashboardFetchSelection(
            summaryCards: BodySummaryCardSelection(selectedCards: [.stress]),
            trendCards: BodyHomeTrendCardSelection(selectedCards: [])
        )

        let states = store.healthPermissionAccessStates(dashboardFetchSelection: stressOnly)

        XCTAssertEqual(states[.steps], .notUsedByDashboard)
        XCTAssertEqual(states[.energy], .notUsedByDashboard)
        XCTAssertNotEqual(states[.sleep], .notUsedByDashboard)
    }

    /// Every row must resolve to something. A missing entry would render a row
    /// with no footer at all, which reads as a layout bug rather than a state.
    @MainActor
    func testEveryPermissionResolvesToAState() throws {
        let store = accessStateStore(ringHistory: .empty)
        let states = store.healthPermissionAccessStates(dashboardFetchSelection: .defaultValue)

        for permission in BodyHealthPermission.allCases {
            XCTAssertNotNil(states[permission], "\(permission) has no access state")
        }
    }

    private struct LegacyHealthDashboardSnapshot: Codable {
        var summary: HealthSummarySnapshot
        var trends: HealthTrendSnapshot
    }

    // MARK: - isWorkoutDetailPersistable

    func testIsWorkoutDetailPersistableAllowsSettledOldMonthWorkout() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar.bodyGregorian
        let oldMonthWorkout = WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: now.addingTimeInterval(-90 * 24 * 60 * 60),
            duration: 3600
        )

        XCTAssertTrue(
            HealthKitWorkoutStore.isWorkoutDetailPersistable(workout: oldMonthWorkout, now: now, calendar: calendar)
        )
    }

    func testIsWorkoutDetailPersistableRejectsUnsettledWorkout() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = Calendar.bodyGregorian
        let unsettledWorkout = WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: now.addingTimeInterval(-3600),
            duration: 3600
        )

        XCTAssertFalse(
            HealthKitWorkoutStore.isWorkoutDetailPersistable(workout: unsettledWorkout, now: now, calendar: calendar)
        )
    }

    // MARK: - Weekly workout minutes (watch complication bars)

    private func weeklyWorkout(month: Int, day: Int, minutes: Double) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: month, day: day, hour: 8)) ?? Date(),
            duration: minutes * 60
        )
    }

    private func weeklyWorkoutMonthSnapshots(
        may: [WorkoutSummary],
        june: [WorkoutSummary]
    ) -> [BodyWorkoutMonthKey: WorkoutMonthSnapshot] {
        [
            BodyWorkoutMonthKey(month: 5, year: 2026): .make(month: 5, year: 2026, workouts: may, calendar: .bodyGregorian),
            BodyWorkoutMonthKey(month: 6, year: 2026): .make(month: 6, year: 2026, workouts: june, calendar: .bodyGregorian)
        ]
    }

    @MainActor
    func testWeeklyWorkoutMinutesSumsDurationsPerDayWithExplicitRestDayZeros() {
        // Window: May 28 … Jun 3, so it spans a month boundary the way a real
        // rolling week does for most of the month.
        let now = Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 21)) ?? Date()
        let snapshots = weeklyWorkoutMonthSnapshots(
            may: [
                // Outside the window: a workout on the day before it starts must
                // not leak into the first bar.
                weeklyWorkout(month: 5, day: 27, minutes: 90),
                // Two workouts on one day sum into that day's bar.
                weeklyWorkout(month: 5, day: 28, minutes: 30),
                weeklyWorkout(month: 5, day: 28, minutes: 45),
                weeklyWorkout(month: 5, day: 30, minutes: 60)
            ],
            june: [
                weeklyWorkout(month: 6, day: 2, minutes: 20),
                weeklyWorkout(month: 6, day: 3, minutes: 15)
            ]
        )

        let weekly = HealthKitWorkoutStore.weeklyWorkoutMinutes(from: snapshots, now: now)

        // Dense: a rest day is an explicit 0, never nil — a nil would make the
        // pushed metric blank, and the watch merge would refuse the week.
        XCTAssertEqual(weekly, [75, 0, 60, 0, 0, 20, 15])
    }

    @MainActor
    func testWeeklyWorkoutMinutesIsNilOnlyWhenNeitherSourceHasASpannedMonth() {
        let now = Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 21)) ?? Date()
        let juneOnly: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [
            BodyWorkoutMonthKey(month: 6, year: 2026): .make(
                month: 6,
                year: 2026,
                workouts: [weeklyWorkout(month: 6, day: 2, minutes: 20)],
                calendar: .bodyGregorian
            )
        ]

        // May is in neither source, so its four days are unknown rather than
        // empty: publishing them as zeros would show a falsely empty week.
        XCTAssertNil(HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, now: now))

        // The launch / passive-refresh shape: only the current month is in
        // memory, and the previous month comes from the persisted App Group
        // snapshot the caller hands in. The week must build from the pair,
        // because an omitted metric DELETES the watch's bars on a phone push.
        let persistedMay: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [
            BodyWorkoutMonthKey(month: 5, year: 2026): .make(
                month: 5,
                year: 2026,
                workouts: [weeklyWorkout(month: 5, day: 30, minutes: 60)],
                calendar: .bodyGregorian
            )
        ]
        XCTAssertEqual(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, fallback: persistedMay, now: now),
            [0, 0, 60, 0, 0, 20, 0]
        )

        // A fallback that doesn't cover the missing month changes nothing.
        let persistedApril: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [
            BodyWorkoutMonthKey(month: 4, year: 2026): .make(
                month: 4,
                year: 2026,
                workouts: [],
                calendar: .bodyGregorian
            )
        ]
        XCTAssertNil(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, fallback: persistedApril, now: now)
        )

        // In-memory wins where both sources carry the month: the persisted file
        // lags a refresh that already updated memory, so Jun 2 keeps its 20.
        var withStaleJune = persistedMay
        withStaleJune[BodyWorkoutMonthKey(month: 6, year: 2026)] = .make(
            month: 6,
            year: 2026,
            workouts: [],
            calendar: .bodyGregorian
        )
        XCTAssertEqual(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, fallback: withStaleJune, now: now),
            [0, 0, 60, 0, 0, 20, 0]
        )

        // Once the window sits entirely inside a loaded month, the week builds
        // with no fallback at all.
        let midMonth = Calendar.bodyGregorian.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 21)) ?? Date()
        XCTAssertEqual(
            HealthKitWorkoutStore.weeklyWorkoutMinutes(from: juneOnly, now: midMonth),
            [20, 0, 0, 0, 0, 0, 0]
        )
    }

    func testWorkoutsWeekCoverageDatePersistsIndependentlyOfTheRefreshSuccessDate() throws {
        // The weekly bars' watermark may only claim what a full-week-coverage
        // fetch earned. An early-month passive refresh persists a SUCCESS date
        // while fetching just the current month, so the two must not share a
        // key: reusing the success date would relaunch with a coverage claim
        // that lets a stale mixed-month week overwrite a newer watch-computed
        // one.
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let successDate = Date(timeIntervalSince1970: 1_780_000_000)
        HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(successDate, defaults: defaults)
        XCTAssertNil(HealthDashboardSnapshotStore.loadLastWorkoutsWeekCoverageDate(defaults: defaults))

        let coverageDate = successDate.addingTimeInterval(-3_600)
        HealthDashboardSnapshotStore.saveLastWorkoutsWeekCoverageDate(coverageDate, defaults: defaults)
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadLastWorkoutsWeekCoverageDate(defaults: defaults),
            coverageDate
        )
        // The sibling watermark is untouched by the coverage write.
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate(defaults: defaults),
            successDate
        )

        // Clear Cache drops the coverage claim without disturbing the other.
        HealthDashboardSnapshotStore.clearLastWorkoutsWeekCoverageDate(defaults: defaults)
        XCTAssertNil(HealthDashboardSnapshotStore.loadLastWorkoutsWeekCoverageDate(defaults: defaults))
        XCTAssertEqual(
            HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate(defaults: defaults),
            successDate
        )
    }
}
