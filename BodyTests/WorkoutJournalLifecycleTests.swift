import HealthKit
import XCTest
@testable import Body

final class WorkoutJournalLifecycleTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func engine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        .init(permission: .init(enabledPermissions: [.workouts]), healthDataSourceSelection: .defaultValue,
              secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
              healthStore: fake, effortLedgerDirectoryURL: nil)
    }

    @MainActor
    func testEnabledDefaultDoesNotQueryBeforeAuthorization() async {
        XCTAssertTrue(WorkoutChangeJournalStore.lifecycleEnabled)
        let fake = FakeHealthStore()
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake)
        store.scheduleWorkoutJournalIfNeeded()
        await Task.yield()
        XCTAssertFalse(store.hasWorkoutJournalWork)
        XCTAssertTrue(fake.workoutChangeRequests.isEmpty)
    }

    @MainActor
    func testExplicitlyDisabledLifecycleDoesNotConstructOrQueryJournal() async {
        let fake = FakeHealthStore()
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake,
            workoutJournalFile: nil)
        store.scheduleWorkoutJournalIfNeeded()
        await Task.yield()
        XCTAssertFalse(store.hasWorkoutJournalWork)
        XCTAssertTrue(fake.workoutChangeRequests.isEmpty)
    }

    func testInstallationPredicateAndRepairCheckpointSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json")
        let fake = FakeHealthStore(), date = Date(timeIntervalSince1970: 1_700_000_000)
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [], anchor: Data([1])))])
        let first = WorkoutJournalReconciler(engine: engine(fake), file: file, date: date)
        let result = await first.scan()
        XCTAssertEqual(result, .caughtUp)
        let pending = await first.snapshot()
        var progress = WorkoutJournalRepairProgress(context: "source A|UTC|v1")
        progress.completedMonths = ["2023:10"]
        let saved = await first.checkpointRepair(progress, generation: pending.generation, revision: pending.revision)
        XCTAssertTrue(saved)
        let reopened = WorkoutJournalReconciler(engine: engine(fake), file: file, date: date.addingTimeInterval(86_400))
        let loaded = await reopened.snapshot()
        XCTAssertEqual(loaded.scope, pending.scope, "A new launch must not move the anchored predicate")
        XCTAssertEqual(loaded.repairProgress, progress)
        XCTAssertTrue(loaded.requiresFullRepair, "A month checkpoint is not final acknowledgment")
        let stale = await reopened.checkpointRepair(progress, generation: pending.generation, revision: pending.revision)
        XCTAssertFalse(stale)
        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(excluded.isExcludedFromBackup, true)
    }

    func testContextAdmissionAndNewDeltaRetireRepairProgress() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = FakeHealthStore(), file = directory.appendingPathComponent("journal.json")
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [], anchor: Data([1])))])
        let owner = WorkoutJournalReconciler(engine: engine(fake), file: file)
        _ = await owner.scan()
        let before = await owner.snapshot()
        let token = HealthDashboardPublicationToken()
        token.invalidate()
        let progress = WorkoutJournalRepairProgress(context: "old source")
        let rejected = await owner.checkpointRepair(progress, generation: before.generation,
            revision: before.revision, admission: token)
        let ack = await owner.acknowledgeDurableRepair(generation: before.generation,
            revision: before.revision, admission: token)
        XCTAssertFalse(rejected)
        XCTAssertFalse(ack)
        let unchanged = await owner.snapshot()
        XCTAssertEqual(before, unchanged)
        _ = await owner.checkpointRepair(progress, generation: before.generation, revision: before.revision)
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [UUID()], anchor: Data([2])))])
        _ = await owner.scan(maxPages: 1)
        let dirty = await owner.snapshot()
        XCTAssertNil(dirty.repairProgress)
        XCTAssertTrue(dirty.requiresFullRepair)
    }

    func testMovedIntervalsAndUnknownDeletionRepairCoverage() throws {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: start, predicateVersion: 1))
        journal.requiresFullRepair = false
        journal.dirtyIntervals[UUID().uuidString] = DateInterval(start: start, end: end)
        let known = try XCTUnwrap(WorkoutJournalRepairPlan(journal: journal, retainedMonths: [], date: end, calendar: calendar))
        XCTAssertEqual(known.months.map(WorkoutJournalRepairPlan.identity), ["2026:1", "2026:2", "2026:3"])
        journal.requiresFullRepair = true
        let old = BodyWorkoutMonthKey(month: 1, year: 2020)
        let unknown = try XCTUnwrap(WorkoutJournalRepairPlan(journal: journal, retainedMonths: [old], date: end, calendar: calendar))
        XCTAssertTrue(unknown.months.contains(old))
        XCTAssertTrue(unknown.months.contains(.init(date: end.addingTimeInterval(-408 * 86_400), calendar: calendar)))
    }

    func testDetailInvalidationIsScopedAndUnknownDeletionClearsOnlyDetailArtifact() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let details = directory.appendingPathComponent("details")
        let first = WorkoutDetailSnapshot(workoutID: UUID(), heartRateRecoveryBPM: 10)
        let second = WorkoutDetailSnapshot(workoutID: UUID(), heartRateRecoveryBPM: 20)
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(first, directoryURL: details))
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(second, directoryURL: details))
        let file = directory.appendingPathComponent("journal.json")
        let journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: Date(), predicateVersion: 1))
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: file), .failed)
        XCTAssertGreaterThan(WorkoutChangeJournalStore.diskSizeBytes(file: file), 0)
        XCTAssertTrue(WorkoutDetailSnapshotStore.invalidateForJournal(ids: [first.workoutID], directoryURL: details))
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: first.workoutID, directoryURL: details))
        XCTAssertEqual(WorkoutDetailSnapshotStore.load(workoutID: second.workoutID, directoryURL: details), second)
        XCTAssertTrue(WorkoutDetailSnapshotStore.invalidateForJournal(ids: nil, directoryURL: details))
        XCTAssertFalse(FileManager.default.fileExists(atPath: details.path))
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), journal)
        XCTAssertFalse(WorkoutDetailSnapshotStore.invalidateForJournal(ids: nil, directoryURL: nil))
    }

    @MainActor
    func testMonthDurabilityDistinguishesUnchangedFromFailedWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldOverride = HealthKitWorkoutStore.testSnapshotDirectoryURLOverride
        defer {
            HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = oldOverride
            try? FileManager.default.removeItem(at: directory)
        }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: []), engineHealthStore: FakeHealthStore())
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directory
        let month = WorkoutMonthSnapshot.make(month: 1, year: 2026, workouts: [], calendar: calendar)
        let first = await store.persistWorkoutJournalMonth(month)
        let unchanged = await store.persistWorkoutJournalMonth(month)
        XCTAssertTrue(first)
        XCTAssertTrue(unchanged)
        // A regular file cannot be used as the snapshot directory.
        let file = try XCTUnwrap(WorkoutSnapshotStore.fileURL(month: 1, year: 2026, directoryURL: directory))
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = file
        let failed = await store.persistWorkoutJournalMonth(month)
        XCTAssertFalse(failed)
    }

    @MainActor
    func testSuccessfulEmptyMonthsRepairThreeAtATimeAndCheckpointDurably() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let priorLedger = WorkoutRecordLedgerStore.load()
        let oldOverride = HealthKitWorkoutStore.testSnapshotDirectoryURLOverride
        let persistQueue = HealthKitWorkoutStore.snapshotPersistQueue
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directory.appendingPathComponent("months")
        addTeardownBlock {
            await withCheckedContinuation { continuation in
                persistQueue.async {
                    if let priorLedger { WorkoutRecordLedgerStore.save(priorLedger) }
                    else { WorkoutRecordLedgerStore.deleteAll() }
                    continuation.resume()
                }
            }
            await MainActor.run { HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = oldOverride }
            try? FileManager.default.removeItem(at: directory)
        }
        let fake = FakeHealthStore()
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([]))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake)
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let end = calendar.date(from: DateComponents(year: 2024, month: 4, day: 15))!
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: start, predicateVersion: 1))
        journal.staging = nil
        journal.requiresFullRepair = false
        journal.dirtyIntervals[UUID().uuidString] = DateInterval(start: start, end: end)
        let file = directory.appendingPathComponent("journal.json")
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: file), .failed)
        let owner = WorkoutJournalReconciler(engine: store.engine, file: file)
        let completed = await store.runRefreshWithDeadline(.seconds(3)) {
            await store.repairWorkoutJournal(journal, owner: owner, admission: HealthDashboardPublicationToken())
        }
        XCTAssertTrue(completed)
        let saved = try XCTUnwrap(WorkoutChangeJournalStore.load(file: file))
        XCTAssertEqual(saved.repairProgress?.completedMonths, ["2024:1", "2024:2", "2024:3"])
        XCTAssertFalse(saved.dirtyIntervals.isEmpty, "Three months cannot acknowledge a four-month obligation")
        XCTAssertEqual(fake.leafRequests.filter { $0 == .samples(HKObjectType.workoutType().identifier) }.count, 3)
        for month in 1...3 {
            let snapshot = try XCTUnwrap(WorkoutSnapshotStore.load(month: month, year: 2024,
                directoryURL: directory.appendingPathComponent("months")))
            XCTAssertEqual(snapshot.workoutCount, 0)
            XCTAssertNotNil(snapshot.validatedAt, "A successful empty month is authoritative repair")
        }
        let reopened = WorkoutJournalReconciler(engine: store.engine, file: file)
        let loaded = await reopened.snapshot()
        XCTAssertEqual(loaded.repairProgress, saved.repairProgress)
    }

    @MainActor
    func testInvalidatedLifecycleRepairDoesNotFetchOrAcknowledge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = FakeHealthStore()
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [], anchor: Data([1])))])
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake)
        let owner = WorkoutJournalReconciler(engine: store.engine, file: directory.appendingPathComponent("journal.json"))
        _ = await owner.scan()
        let before = await owner.snapshot()
        let token = HealthDashboardPublicationToken()
        token.invalidate()
        await store.repairWorkoutJournal(before, owner: owner, admission: token)
        let after = await owner.snapshot()
        XCTAssertEqual(after, before)
        XCTAssertTrue(fake.leafRequests.isEmpty)
    }

    func testMonthRetryPolicyCapsDelayAndDecodesLegacyProgress() throws {
        let legacy = Data(#"{"context":"same","completedMonths":[],"baselineInvalidated":false,"detailsInvalidated":true}"#.utf8)
        var progress = try JSONDecoder().decode(WorkoutJournalRepairProgress.self, from: legacy)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(progress.mayAttemptMonth("2026:1", at: date))
        for delay in [300.0, 1_800, 7_200, 21_600, 21_600] {
            progress.beginMonthAttempt("2026:1", at: date)
            XCTAssertFalse(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(delay - 1)))
            XCTAssertTrue(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(delay)))
            XCTAssertTrue(progress.mayAttemptMonth("2026:2", at: date))
            XCTAssertTrue(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(-1)))
            progress = try JSONDecoder().decode(WorkoutJournalRepairProgress.self,
                from: JSONEncoder().encode(progress))
        }
        XCTAssertEqual(progress.monthAttempts?["2026:1"]?.count, 4)
        XCTAssertTrue(progress.completedMonths.isEmpty)
        progress.completeMonth("2026:1")
        XCTAssertNil(progress.monthAttempts)
        XCTAssertFalse(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(86_400)))
    }

    @MainActor
    func testFailedMonthsBackOffAcrossRelaunchWithoutBlockingLaterMonths() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldOverride = HealthKitWorkoutStore.testSnapshotDirectoryURLOverride
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directory.appendingPathComponent("months")
        defer {
            HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = oldOverride
            try? FileManager.default.removeItem(at: directory)
        }
        let fake = FakeHealthStore()
        fake.scriptSamples(for: HKObjectType.workoutType(), .failure(nil))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake)
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let end = calendar.date(from: DateComponents(year: 2024, month: 4, day: 15))!
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: start, predicateVersion: 1))
        journal.staging = nil
        journal.requiresFullRepair = false
        journal.dirtyIntervals[UUID().uuidString] = DateInterval(start: start, end: end)
        let file = directory.appendingPathComponent("journal.json")
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: file), .failed)
        let owner = WorkoutJournalReconciler(engine: store.engine, file: file)
        await store.repairWorkoutJournal(journal, owner: owner, admission: HealthDashboardPublicationToken())
        let first = await owner.snapshot()
        XCTAssertEqual(first.repairProgress?.monthAttempts?.count, 3)
        XCTAssertEqual(first.repairProgress?.completedMonths, [])
        XCTAssertEqual(first.dirtyIntervals, journal.dirtyIntervals)
        XCTAssertEqual(fake.leafRequests.filter { $0 == .samples(HKObjectType.workoutType().identifier) }.count, 3)
        let reopened = WorkoutJournalReconciler(engine: store.engine, file: file)
        let loaded = await reopened.snapshot()
        await store.repairWorkoutJournal(loaded, owner: reopened, admission: HealthDashboardPublicationToken())
        let second = await reopened.snapshot()
        XCTAssertEqual(second.repairProgress?.monthAttempts?.count, 4, "Later months must not starve behind failed months")
        XCTAssertEqual(fake.leafRequests.filter { $0 == .samples(HKObjectType.workoutType().identifier) }.count, 4)
        await store.repairWorkoutJournal(second, owner: reopened, admission: HealthDashboardPublicationToken())
        let third = await reopened.snapshot()
        XCTAssertEqual(third, second, "A foreground refresh within the cooldown must not retry or acknowledge")
        XCTAssertEqual(fake.leafRequests.filter { $0 == .samples(HKObjectType.workoutType().identifier) }.count, 4)
    }
}
