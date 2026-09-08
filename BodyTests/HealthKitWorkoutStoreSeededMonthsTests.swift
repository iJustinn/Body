//
//  HealthKitWorkoutStoreSeededMonthsTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

/// Launch restores the persisted 6-month window into memory, and a refresh
/// writes that window back out. These cases cover the seeding half (what lands
/// in `monthSnapshots`, and what deliberately does not land in
/// `loadedMonthKeys`) and the persist half (every in-window month written, the
/// legacy pair deleted, out-of-window files pruned, Clear Cache emptying the
/// directory).
final class HealthKitWorkoutStoreSeededMonthsTests: XCTestCase {

    // MARK: - Init seeding

    @MainActor
    func testInitSeedsEveryPersistedMonthWithoutMarkingThemLoaded() throws {
        let calendar = Calendar.bodyGregorian
        let now = Date()
        let months = try windowMonths(count: WorkoutSnapshotStore.persistedMonthCount, now: now, calendar: calendar)
        let seeded = months.map { month in
            WorkoutMonthSnapshot.make(
                month: month.month,
                year: month.year,
                workouts: [workout(in: month, calendar: calendar)],
                calendar: calendar
            )
        }

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: seeded,
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue,
            engineHealthStore: FakeHealthStore(),
            date: now
        )

        for month in months {
            XCTAssertEqual(
                store.snapshot(month: month.month, year: month.year).workoutCount,
                1,
                "Every persisted month has to be restored into memory, not just the current one."
            )
            XCTAssertFalse(
                store.hasLoadedSnapshot(month: month.month, year: month.year),
                "A disk restore is not a HealthKit fetch: `loadedMonthKeys` must stay empty at launch."
            )
        }

        // The current month is the one that also becomes the published snapshot.
        let current = try XCTUnwrap(months.first)
        XCTAssertEqual(store.snapshot.month, current.month)
        XCTAssertEqual(store.snapshot.year, current.year)
        XCTAssertEqual(store.snapshot.workoutCount, 1)
    }

    @MainActor
    func testInitPublishesAnEmptyCurrentMonthWhenNoMonthFileCoversIt() throws {
        let calendar = Calendar.bodyGregorian
        let now = Date()
        let months = try windowMonths(count: 2, now: now, calendar: calendar)
        let previous = try XCTUnwrap(months.last)

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [
                WorkoutMonthSnapshot.make(
                    month: previous.month,
                    year: previous.year,
                    workouts: [workout(in: previous, calendar: calendar)],
                    calendar: calendar
                )
            ],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue,
            engineHealthStore: FakeHealthStore(),
            date: now
        )

        let current = try XCTUnwrap(months.first)
        XCTAssertEqual(store.snapshot.month, current.month)
        XCTAssertEqual(store.snapshot.year, current.year)
        XCTAssertEqual(store.snapshot.workoutCount, 0)
        XCTAssertEqual(store.snapshot(month: previous.month, year: previous.year).workoutCount, 1)
    }

    /// `monthLoadOrder` is private and only observable through eviction, which
    /// needs a HealthKit fetch this target can't drive, so the seed order is
    /// pinned at the source instead: oldest first, matching
    /// `noteMonthSnapshotStored`'s append order, so the least recently touched
    /// seeded month is the first evicted.
    func testInitSeedsMonthLoadOrderOldestFirst() throws {
        let storeSource = try BodyTestSupport.sourceText(at: "Body/Services/HealthKitWorkoutStore.swift")
        XCTAssertTrue(storeSource.contains("monthLoadOrder = Set(monthSnapshots.keys).sortedByDate"))
    }

    // MARK: - hasCachedWorkouts

    @MainActor
    func testHasCachedWorkoutsIsFalseForASeededButEmptyMonth() throws {
        let calendar = Calendar.bodyGregorian
        let now = Date()
        let months = try windowMonths(count: 2, now: now, calendar: calendar)
        let current = try XCTUnwrap(months.first)
        let previous = try XCTUnwrap(months.last)

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [
                WorkoutMonthSnapshot.make(
                    month: current.month,
                    year: current.year,
                    workouts: [workout(in: current, calendar: calendar)],
                    calendar: calendar
                ),
                WorkoutMonthSnapshot.make(
                    month: previous.month,
                    year: previous.year,
                    workouts: [],
                    calendar: calendar
                )
            ],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue,
            engineHealthStore: FakeHealthStore(),
            date: now
        )

        XCTAssertTrue(store.hasCachedWorkouts(month: current.month, year: current.year))
        XCTAssertFalse(
            store.hasCachedWorkouts(month: previous.month, year: previous.year),
            "An empty seeded month must not navigate instantly to \"No workouts\" and then pop workouts in."
        )
        // A month with no file at all is not cached either.
        XCTAssertFalse(store.hasCachedWorkouts(month: 1, year: 1999))
    }

    // MARK: - Persisting the window

    @MainActor
    func testPersistWritesEveryWindowMonthDeletesLegacyFilesAndPrunesOldOnes() async throws {
        let calendar = Calendar.bodyGregorian
        let now = Date()
        let directoryURL = temporaryMonthSnapshotDirectoryURL()
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directoryURL
        addTeardownBlock {
            HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = nil
            try? FileManager.default.removeItem(at: directoryURL.deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let months = try windowMonths(count: WorkoutSnapshotStore.persistedMonthCount, now: now, calendar: calendar)
        let seeded = months.map { month in
            WorkoutMonthSnapshot.make(
                month: month.month,
                year: month.year,
                workouts: [workout(in: month, calendar: calendar)],
                calendar: calendar
            )
        }

        // A pre-6-month cache from an older build, plus a month file that has
        // aged out of the window.
        let legacyCurrentURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent(WorkoutSnapshotStore.currentMonthSnapshotFileName)
        let legacyPreviousURL = directoryURL.deletingLastPathComponent()
            .appendingPathComponent(WorkoutSnapshotStore.previousMonthSnapshotFileName)
        XCTAssertTrue(WorkoutSnapshotStore.save(try XCTUnwrap(seeded.first), fileURL: legacyCurrentURL))
        XCTAssertTrue(WorkoutSnapshotStore.save(try XCTUnwrap(seeded.dropFirst().first), fileURL: legacyPreviousURL))

        let expiredMonth = try XCTUnwrap(
            windowMonths(count: WorkoutSnapshotStore.persistedMonthCount + 4, now: now, calendar: calendar).last
        )
        let expiredURL = try XCTUnwrap(
            WorkoutSnapshotStore.fileURL(month: expiredMonth.month, year: expiredMonth.year, directoryURL: directoryURL)
        )
        XCTAssertTrue(
            WorkoutSnapshotStore.save(
                WorkoutMonthSnapshot.make(
                    month: expiredMonth.month,
                    year: expiredMonth.year,
                    workouts: [],
                    calendar: calendar
                ),
                fileURL: expiredURL
            )
        )

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: seeded,
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue,
            engineHealthStore: FakeHealthStore(),
            date: now
        )

        // The refresh-deadline timeout branch is the persist path this target
        // can drive without HealthKit.
        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(60))
        }
        XCTAssertFalse(completed)

        // The prune is the last disk step of the persist block, so its effect is
        // the barrier for everything above it.
        _ = try await waitForCondition(timeout: .seconds(10)) {
            FileManager.default.fileExists(atPath: expiredURL.path) ? nil : true
        }

        for month in months {
            let persisted = WorkoutSnapshotStore.load(
                month: month.month,
                year: month.year,
                directoryURL: directoryURL
            )
            XCTAssertEqual(
                persisted?.workoutCount,
                1,
                "Every in-window month held in memory has to be written, not just the current one."
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCurrentURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyPreviousURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: expiredURL.path),
            "A month file outside the persisted window has to be pruned."
        )
    }

    @MainActor
    func testClearLocalCacheEmptiesTheMonthSnapshotDirectory() async throws {
        let calendar = Calendar.bodyGregorian
        let now = Date()
        let directoryURL = temporaryMonthSnapshotDirectoryURL()
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directoryURL
        addTeardownBlock {
            HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = nil
            try? FileManager.default.removeItem(at: directoryURL.deletingLastPathComponent())
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let months = try windowMonths(count: 3, now: now, calendar: calendar)
        for month in months {
            XCTAssertTrue(
                WorkoutSnapshotStore.save(
                    WorkoutMonthSnapshot.make(
                        month: month.month,
                        year: month.year,
                        workouts: [workout(in: month, calendar: calendar)],
                        calendar: calendar
                    ),
                    fileURL: WorkoutSnapshotStore.fileURL(
                        month: month.month,
                        year: month.year,
                        directoryURL: directoryURL
                    )
                )
            )
        }

        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .defaultValue,
            engineHealthStore: FakeHealthStore(),
            date: now
        )

        await store.clearLocalCache(date: now)

        for month in months {
            XCTAssertNil(
                WorkoutSnapshotStore.load(month: month.month, year: month.year, directoryURL: directoryURL),
                "Clear Cache has to remove every month file, not only the current one."
            )
        }
        XCTAssertEqual(WorkoutSnapshotStore.diskSizeBytes(directoryURL: directoryURL), 0)
    }

    // MARK: - Helpers

    private func windowMonths(
        count: Int,
        now: Date,
        calendar: Calendar
    ) throws -> [(month: Int, year: Int)] {
        try (0..<count).map { offset in
            let anchor = try XCTUnwrap(calendar.date(byAdding: .month, value: -offset, to: now))
            return (calendar.component(.month, from: anchor), calendar.component(.year, from: anchor))
        }
    }

    private func workout(in month: (month: Int, year: Int), calendar: Calendar) -> WorkoutSummary {
        let start = calendar.date(
            from: DateComponents(year: month.year, month: month.month, day: 2, hour: 9)
        ) ?? Date()
        return WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: start,
            duration: 1_800,
            activeEnergyKilocalories: 200,
            distanceMeters: 3_000,
            sourceName: "Tests"
        )
    }

    private func temporaryMonthSnapshotDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BodyTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(WorkoutSnapshotStore.monthSnapshotsDirectoryName, isDirectory: true)
    }

    /// Polls `probe` until it returns a non-nil value or `timeout` elapses, for
    /// asserting on work handed off to the persist queue.
    private func waitForCondition<T>(
        timeout: Duration,
        probe: @escaping () -> T?
    ) async throws -> T? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let value = probe() {
                return value
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return probe()
    }
}
