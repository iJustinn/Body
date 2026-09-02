//
//  HealthKitWorkoutStorePersistenceTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStorePersistenceTests: XCTestCase {

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

    // MARK: - Detail cache retention (H-02, M-04)

    func testDetailCachesAreClearedOnlyWhenTheAuthorizationSheetWasShown() {
        XCTAssertTrue(HealthKitWorkoutStore.shouldClearDetailCaches(after: .authorized(didPrompt: true)))
        // A status re-check changed nothing readable, so cached routes, splits,
        // series and recovery stay put across every in-session refresh. A grant
        // changed outside Body is covered by the eager background clear instead.
        XCTAssertFalse(HealthKitWorkoutStore.shouldClearDetailCaches(after: .authorized(didPrompt: false)))
        XCTAssertFalse(HealthKitWorkoutStore.shouldClearDetailCaches(after: .promptDeferred))
    }

    func testEvictableWorkoutDetailIDsDropsTheOldestBeyondTheMaximum() {
        let ids = (0..<5).map { _ in UUID() }

        XCTAssertEqual(HealthKitWorkoutStore.evictableWorkoutDetailIDs(order: ids, maximum: 5), [])
        XCTAssertEqual(HealthKitWorkoutStore.evictableWorkoutDetailIDs(order: ids, maximum: 9), [])
        XCTAssertEqual(HealthKitWorkoutStore.evictableWorkoutDetailIDs(order: [], maximum: 3), [])
        XCTAssertEqual(
            HealthKitWorkoutStore.evictableWorkoutDetailIDs(order: ids, maximum: 3),
            Array(ids.prefix(2))
        )
    }

    func testTouchingAWorkoutDetailMovesItPastTheEvictionFront() {
        var order = (0..<4).map { _ in UUID() }
        let oldest = order[0]

        // Reopening the oldest workout moves it to the end, so the next
        // eviction takes the one after it instead.
        order.removeAll { $0 == oldest }
        order.append(oldest)

        XCTAssertEqual(order.last, oldest)
        XCTAssertEqual(
            HealthKitWorkoutStore.evictableWorkoutDetailIDs(order: order, maximum: 3),
            [order[0]]
        )
        XCTAssertNotEqual(order[0], oldest)
    }

    func testPermissionSelectionLoadAloneRunsNoMigration() throws {
        let suiteName = "BodyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("workouts,heart", forKey: BodyAppearancePreference.healthPermissionSelectionKey)

        let loaded = BodyHealthPermissionSelection.load(defaults: defaults)

        XCTAssertFalse(loaded.includes(.workoutMetrics))
        XCTAssertFalse(loaded.includes(.cardioFitness))
        XCTAssertFalse(defaults.bool(forKey: BodyAppearancePreference.healthPermissionExpandedMigratedKey))
        XCTAssertFalse(defaults.bool(forKey: BodyAppearancePreference.healthCardioFitnessMigratedKey))
    }
}
