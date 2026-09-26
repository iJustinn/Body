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
    private static func drainPersistQueue() async {
        let queue = HealthKitWorkoutStore.snapshotPersistQueue
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    /// The store saves the dashboard envelope at its real location. Park the
    /// host's copy so a populated day-sample sidecar cannot turn a save into a
    /// non-durable `.preserved`, and restore it afterwards. Repairs also write
    /// the record ledger and remove detail files at their real locations, so
    /// those are parked and restored the same way.
    @discardableResult @MainActor
    private func isolateDashboardEnvelope(includingRepairArtifacts: Bool = false) async throws -> URL {
        let directory = try XCTUnwrap(HealthDashboardSnapshotStore.snapshotFileURL).deletingLastPathComponent()
        var directories = [directory]
        if includingRepairArtifacts {
            directories.append(try XCTUnwrap(WorkoutRecordLedgerStore.defaultDirectoryURL))
            directories.append(try XCTUnwrap(WorkoutDetailSnapshotStore.defaultDirectoryURL))
        }
        await Self.drainPersistQueue()
        let manager = FileManager.default
        let parking = directories.map { original in
            (original: original, parked: manager.temporaryDirectory.appendingPathComponent(UUID().uuidString),
             existed: manager.fileExists(atPath: original.path))
        }
        // Registered before any move, and never deletes a host copy that was not parked.
        addTeardownBlock {
            await Self.drainPersistQueue()
            for (original, parked, existed) in parking {
                if existed {
                    guard FileManager.default.fileExists(atPath: parked.path) else { continue }
                    try? FileManager.default.removeItem(at: original)
                    try? FileManager.default.moveItem(at: parked, to: original)
                } else {
                    try? FileManager.default.removeItem(at: original)
                }
            }
        }
        for (original, parked, existed) in parking where existed {
            try manager.moveItem(at: original, to: parked)
        }
        return directory
    }

    @MainActor
    private func persistedFreshnessDate() async -> Date? {
        await Self.drainPersistQueue()
        return HealthDashboardSnapshotStore.loadWithContext()?.metadata.freshness?.date
    }

    /// A settled dashboard tail: live success, the staged watermark, then a
    /// durable envelope that carries it.
    @discardableResult @MainActor
    private func stampFreshness(_ store: HealthKitWorkoutStore, secondsAgo: TimeInterval) async -> Date {
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - secondsAgo)
        store.markRefreshSucceeded(date: date, refreshedVitals: true, publishesWatch: false)
        store.stageCompletedDashboardFreshness(date: date)
        let durable = await store.persistDashboardSnapshotDurably()
        XCTAssertTrue(durable)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, date)
        let persisted = await persistedFreshnessDate()
        XCTAssertEqual(persisted, date)
        return date
    }

    /// One dirty month whose workout read fails, so every pass backs off
    /// before the final dashboard step. Returns the dashboard directory too.
    @MainActor
    private func makeDirtyRepairFixture() async throws
        -> (store: HealthKitWorkoutStore, fake: FakeHealthStore, journal: WorkoutChangeJournal, file: URL, dashboard: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldOverride = HealthKitWorkoutStore.testSnapshotDirectoryURLOverride
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directory.appendingPathComponent("months")
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        addTeardownBlock {
            await MainActor.run { HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = oldOverride }
            restoreDefaults()
            try? FileManager.default.removeItem(at: directory)
        }
        // A reopened month may now complete and write the record ledger or drop
        // a detail file, so those real locations are parked too.
        let dashboard = try await isolateDashboardEnvelope(includingRepairArtifacts: true)
        let fake = FakeHealthStore()
        fake.scriptSamples(for: HKObjectType.workoutType(), .failure(nil))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake)
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2024, month: 1, day: 20))!
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: start, predicateVersion: 1))
        journal.staging = nil
        journal.requiresFullRepair = false
        journal.dirtyIntervals[UUID().uuidString] = DateInterval(start: start, end: end)
        let file = directory.appendingPathComponent("journal.json")
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: file), .failed)
        return (store, fake, journal, file, dashboard)
    }

    private func addedWorkout() -> WorkoutJournalEntry {
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 12, hour: 8))!
        return WorkoutJournalEntry(id: UUID(), start: start, end: start.addingTimeInterval(1_800),
            activityType: 37, duration: 1_800, sourceBundleIdentifier: "com.example.test")
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
        try await isolateDashboardEnvelope()
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
        XCTAssertNil(progress.freshnessInvalidated, "Legacy progress never claims a durable freshness invalidation")
        XCTAssertNil(progress.finalAttempt)
        XCTAssertNil(progress.uncovered, "An envelope without the key has nothing waiting to reopen")
        let build5 = Data(#"{"context":"same","completedMonths":["2026:1"],"baselineInvalidated":true,"detailsInvalidated":true,"freshnessInvalidated":true,"finalAttempt":{"count":2,"startedAt":0}}"#.utf8)
        let resumed = try JSONDecoder().decode(WorkoutJournalRepairProgress.self, from: build5)
        XCTAssertNil(resumed.uncovered)
        XCTAssertEqual(resumed.finalAttempt?.count, 2)
        XCTAssertTrue(progress.mayAttemptMonth("2026:1", at: date))
        XCTAssertTrue(progress.mayAttemptFinalStep(at: date))
        for delay in [300.0, 1_800, 7_200, 21_600, 21_600] {
            progress.beginMonthAttempt("2026:1", at: date)
            progress.beginFinalStepAttempt(at: date)
            XCTAssertFalse(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(delay - 1)))
            XCTAssertTrue(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(delay)))
            XCTAssertTrue(progress.mayAttemptMonth("2026:2", at: date))
            XCTAssertTrue(progress.mayAttemptMonth("2026:1", at: date.addingTimeInterval(-1)))
            XCTAssertFalse(progress.mayAttemptFinalStep(at: date.addingTimeInterval(delay - 1)))
            XCTAssertTrue(progress.mayAttemptFinalStep(at: date.addingTimeInterval(delay)))
            XCTAssertTrue(progress.mayAttemptFinalStep(at: date.addingTimeInterval(-1)), "Clock rollback must not strand the final step")
            progress = try JSONDecoder().decode(WorkoutJournalRepairProgress.self,
                from: JSONEncoder().encode(progress))
        }
        XCTAssertEqual(progress.monthAttempts?["2026:1"]?.count, 4)
        XCTAssertEqual(progress.finalAttempt?.count, 4)
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
        try await isolateDashboardEnvelope()
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

    // MARK: - Resume freshness and the final dashboard step

    @MainActor
    func testCleanOrUnbootstrappedJournalLeavesFreshnessMonthsAndFileUntouched() async throws {
        let fixture = try await makeDirtyRepairFixture()
        let store = fixture.store
        let stamp = await stampFreshness(store, secondsAgo: 60)
        var clean = fixture.journal
        clean.dirtyIntervals = [:]
        var unbootstrapped = fixture.journal
        unbootstrapped.staging = [:]
        unbootstrapped.requiresFullRepair = true
        for journal in [clean, unbootstrapped] {
            XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: fixture.file), .failed)
            let owner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
            let captured = await owner.snapshot()
            let bytes = try Data(contentsOf: fixture.file)
            let generation = store.monthSnapshotsGeneration
            let completed = await store.runRefreshWithDeadline(.seconds(5)) {
                await store.repairWorkoutJournal(captured, owner: owner, admission: HealthDashboardPublicationToken())
            }
            XCTAssertTrue(completed)
            XCTAssertEqual(store.lastSuccessfulRefreshDate, stamp)
            XCTAssertEqual(store.currentDashboardPersistenceMetadata().freshness?.date, stamp)
            let persisted = await persistedFreshnessDate()
            XCTAssertEqual(persisted, stamp)
            XCTAssertEqual(store.monthSnapshotsGeneration, generation, "No month may be unvalidated or republished")
            XCTAssertEqual(try Data(contentsOf: fixture.file), bytes)
            let after = await owner.snapshot()
            XCTAssertEqual(after, captured)
            XCTAssertTrue(fixture.fake.leafRequests.isEmpty)
        }
    }

    @MainActor
    func testDirtyRepairClearsFreshnessOnceAndKeepsARestampedEnvelopeAcrossOwners() async throws {
        let fixture = try await makeDirtyRepairFixture()
        let store = fixture.store
        await stampFreshness(store, secondsAgo: 120)
        let owner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        await store.repairWorkoutJournal(fixture.journal, owner: owner, admission: HealthDashboardPublicationToken())
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertNil(store.currentDashboardPersistenceMetadata().freshness)
        let cleared = await persistedFreshnessDate()
        XCTAssertNil(cleared, "The invalidation reaches the envelope before it is checkpointed")
        let first = await owner.snapshot()
        XCTAssertEqual(first.repairProgress?.freshnessInvalidated, true)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: fixture.file)?.repairProgress?.freshnessInvalidated, true)
        XCTAssertEqual(first.repairProgress?.monthAttempts?.count, 1)

        let restamped = await stampFreshness(store, secondsAgo: 60)
        await store.repairWorkoutJournal(first, owner: owner, admission: HealthDashboardPublicationToken())
        XCTAssertEqual(store.lastSuccessfulRefreshDate, restamped)
        let kept = await persistedFreshnessDate()
        XCTAssertEqual(kept, restamped)
        let second = await owner.snapshot()
        XCTAssertEqual(second, first, "A pass inside the month cooldown checkpoints nothing new")

        let reopened = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        let loaded = await reopened.snapshot()
        XCTAssertEqual(loaded.repairProgress?.freshnessInvalidated, true)
        await store.repairWorkoutJournal(loaded, owner: reopened, admission: HealthDashboardPublicationToken())
        XCTAssertEqual(store.lastSuccessfulRefreshDate, restamped)
        let relaunched = await persistedFreshnessDate()
        XCTAssertEqual(relaunched, restamped)
        XCTAssertEqual(fixture.fake.leafRequests.filter { $0 == .samples(HKObjectType.workoutType().identifier) }.count, 1)
    }

    @MainActor
    func testFailedDashboardSaveOrCheckpointLeavesTheFreshnessFlagUnset() async throws {
        let fixture = try await makeDirtyRepairFixture()
        let store = fixture.store
        let manager = FileManager.default
        await stampFreshness(store, secondsAgo: 180)
        // A regular file where the envelope's directory belongs fails the save.
        await Self.drainPersistQueue()
        try manager.removeItem(at: fixture.dashboard)
        XCTAssertTrue(manager.createFile(atPath: fixture.dashboard.path, contents: Data()))
        let owner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        await store.repairWorkoutJournal(fixture.journal, owner: owner, admission: HealthDashboardPublicationToken())
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        let unsaved = await owner.snapshot()
        XCTAssertNil(unsaved.repairProgress, "A failed dashboard save must not claim the invalidation")
        XCTAssertTrue(fixture.fake.leafRequests.isEmpty)
        await Self.drainPersistQueue()
        try manager.removeItem(at: fixture.dashboard)

        await stampFreshness(store, secondsAgo: 120)
        let failing = WorkoutJournalReconciler(engine: store.engine, file: fixture.file,
            write: { _, _ in throw CocoaError(.fileWriteUnknown) })
        let failingJournal = await failing.snapshot()
        await store.repairWorkoutJournal(failingJournal, owner: failing, admission: HealthDashboardPublicationToken())
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        let durablyCleared = await persistedFreshnessDate()
        XCTAssertNil(durablyCleared)
        XCTAssertNil(WorkoutChangeJournalStore.load(file: fixture.file)?.repairProgress,
                     "A failed checkpoint leaves the flag unset")
        XCTAssertTrue(fixture.fake.leafRequests.isEmpty)

        await stampFreshness(store, secondsAgo: 60)
        let working = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        let loaded = await working.snapshot()
        await store.repairWorkoutJournal(loaded, owner: working, admission: HealthDashboardPublicationToken())
        XCTAssertNil(store.lastSuccessfulRefreshDate, "An unset flag clears the restamped freshness again")
        let saved = await working.snapshot()
        XCTAssertEqual(saved.repairProgress?.freshnessInvalidated, true)
    }

    @MainActor
    func testContextReplacementClearsFreshnessOnceMoreButAKnownDeltaDoesNot() async throws {
        let fixture = try await makeDirtyRepairFixture()
        let store = fixture.store
        let owner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        var stale = WorkoutJournalRepairProgress(context: "old source")
        stale.freshnessInvalidated = true
        let checkpointed = await owner.checkpointRepair(stale, generation: fixture.journal.generation,
            revision: fixture.journal.revision)
        XCTAssertTrue(checkpointed)
        await stampFreshness(store, secondsAgo: 120)
        let replaced = await owner.snapshot()
        await store.repairWorkoutJournal(replaced, owner: owner, admission: HealthDashboardPublicationToken())
        XCTAssertNil(store.lastSuccessfulRefreshDate, "Another context's flag is not this repair's invalidation")
        let current = await owner.snapshot()
        XCTAssertNotEqual(current.repairProgress?.context, "old source")
        XCTAssertEqual(current.repairProgress?.freshnessInvalidated, true)

        let restamped = await stampFreshness(store, secondsAgo: 60)
        var delta = current
        let added = addedWorkout()
        delta.apply(additions: [added], deletedIDs: [], nextAnchor: Data([2]))
        XCTAssertEqual(delta.repairProgress?.context, current.repairProgress?.context, "A known delta keeps the progress")
        XCTAssertNotNil(delta.repairProgress?.uncovered?[added.id.uuidString])
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(delta, file: fixture.file), .failed)
        let reopened = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        let loaded = await reopened.snapshot()
        await store.repairWorkoutJournal(loaded, owner: reopened, admission: HealthDashboardPublicationToken())
        XCTAssertEqual(store.lastSuccessfulRefreshDate, restamped, "A known workout delta does not clear the freshness again")
        let kept = await persistedFreshnessDate()
        XCTAssertEqual(kept, restamped)
        let resumed = await reopened.snapshot()
        XCTAssertEqual(resumed.repairProgress?.context, current.repairProgress?.context)
        XCTAssertEqual(resumed.repairProgress?.freshnessInvalidated, true)
        XCTAssertNil(resumed.repairProgress?.uncovered, "The pass consumed the mark once the detail file was invalidated")
    }

    /// Stands in for a process exit right after the final step's attempt is
    /// durable: the pass loses admission before it can fetch.
    private final class FinalStepInterruption: @unchecked Sendable {
        private let lock = NSLock()
        private var token = HealthDashboardPublicationToken()

        func admission() -> HealthDashboardPublicationToken {
            lock.lock(); defer { lock.unlock() }
            token = HealthDashboardPublicationToken()
            return token
        }

        func interruptIfFinalStep(_ data: Data) {
            guard (try? JSONDecoder().decode(WorkoutChangeJournal.self, from: data))?.repairProgress?.finalAttempt != nil else { return }
            lock.lock(); defer { lock.unlock() }
            token.invalidate()
        }
    }

    @MainActor
    func testFinalDashboardStepBacksOffLikeAMonthUntilAScannedDeltaResetsItThroughThePass() async throws {
        let fixture = try await makeDirtyRepairFixture()
        let store = fixture.store
        let interruption = FinalStepInterruption()
        let owner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file, write: { data, url in
            try data.write(to: url, options: .atomic)
            interruption.interruptIfFinalStep(data)
        })
        func pass() async {
            let journal = await owner.snapshot()
            await store.repairWorkoutJournal(journal, owner: owner, admission: interruption.admission())
        }
        func rewindFinalAttempt(by seconds: TimeInterval) async throws {
            let current = await owner.snapshot()
            var progress = try XCTUnwrap(current.repairProgress)
            progress.finalAttempt?.startedAt = Date().addingTimeInterval(-seconds)
            let saved = await owner.checkpointRepair(progress, generation: current.generation, revision: current.revision)
            XCTAssertTrue(saved)
        }
        // The first pass records this context's progress; completing its one
        // month lets the next pass reach the final step.
        await pass()
        let first = await owner.snapshot()
        var progress = try XCTUnwrap(first.repairProgress)
        let months = try XCTUnwrap(progress.monthAttempts?.keys)
        XCTAssertEqual(months.count, 1)
        progress.completedMonths = Set(months)
        progress.monthAttempts = nil
        let completed = await owner.checkpointRepair(progress, generation: first.generation, revision: first.revision)
        XCTAssertTrue(completed)
        let reads = fixture.fake.leafRequests.count

        await pass()
        let attempted = await owner.snapshot()
        XCTAssertEqual(attempted.repairProgress?.finalAttempt?.count, 1, "The attempt is durable before the fetch")
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: fixture.file)?.repairProgress?.finalAttempt?.count, 1)
        XCTAssertEqual(attempted.dirtyIntervals, fixture.journal.dirtyIntervals, "An unfinished final step never acknowledges")
        await pass()
        let withinFiveMinutes = await owner.snapshot()
        XCTAssertEqual(withinFiveMinutes, attempted, "Within five minutes the final step does not run again")

        try await rewindFinalAttempt(by: 300)
        await pass()
        let secondAttempt = await owner.snapshot()
        XCTAssertEqual(secondAttempt.repairProgress?.finalAttempt?.count, 2)
        try await rewindFinalAttempt(by: 300)
        let beforeThirtyMinutes = await owner.snapshot()
        await pass()
        let withinThirtyMinutes = await owner.snapshot()
        XCTAssertEqual(withinThirtyMinutes, beforeThirtyMinutes, "The second retry waits thirty minutes")
        try await rewindFinalAttempt(by: 1_800)
        await pass()
        let thirdAttempt = await owner.snapshot()
        XCTAssertEqual(thirdAttempt.repairProgress?.finalAttempt?.count, 3)
        XCTAssertEqual(fixture.fake.leafRequests.count, reads, "A pass that lost admission after its checkpoint never fetches")

        // A scanned addition keeps the progress, ladder included, until the next
        // pass reopens its month; completing that month again reaches the final
        // step at once instead of waiting out the two hour rung.
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 12, hour: 8))!
        let workout = makeTestWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1_800), metadata: nil)
        fixture.fake.scriptWorkoutChanges([.success(.init(workouts: [workout], deletedIDs: [], anchor: Data([2])))])
        let scan = await owner.scan(maxPages: 1)
        XCTAssertEqual(scan, .morePending)
        let scanned = await owner.snapshot()
        XCTAssertEqual(scanned.repairProgress?.finalAttempt?.count, 3, "The delta itself does not rewrite the ladder")
        XCTAssertNotNil(scanned.repairProgress?.uncovered?[workout.uuid.uuidString])
        fixture.fake.scriptSamples(for: HKObjectType.workoutType(), .samples([]))
        let monthReads = fixture.fake.leafRequests.count
        await pass()
        let reset = await owner.snapshot()
        XCTAssertEqual(reset.repairProgress?.finalAttempt?.count, 1, "The reopening pass restarts the ladder and attempts the final step")
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: fixture.file)?.repairProgress?.finalAttempt?.count, 1)
        XCTAssertEqual(reset.repairProgress?.completedMonths, Set(months))
        XCTAssertNil(reset.repairProgress?.uncovered)
        XCTAssertEqual(fixture.fake.leafRequests.count, monthReads + 1,
                       "Only the reopened month is read; the interrupted final step never fetches")
        XCTAssertEqual(fixture.fake.leafRequests.last, .samples(HKObjectType.workoutType().identifier))
    }

    func testCapacityOverflowRetiresRepairProgress() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json")
        let lowerBound = Date(timeIntervalSince1970: 1_700_000_000)
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(), lowerBound: lowerBound, predicateVersion: 1))
        journal.staging = nil
        journal.requiresFullRepair = false
        let old = DateInterval(start: lowerBound, duration: 60)
        for _ in 0..<10_000 { journal.dirtyIntervals[UUID().uuidString] = old }
        journal.repairProgress = WorkoutJournalRepairProgress(context: "same", completedMonths: ["2023:11"])
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: file), .failed)
        let fake = FakeHealthStore()
        let start = lowerBound.addingTimeInterval(3_600)
        let workout = makeTestWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1_800), metadata: nil)
        fake.scriptWorkoutChanges([.success(.init(workouts: [workout], deletedIDs: [], anchor: Data([1])))])
        let owner = WorkoutJournalReconciler(engine: engine(fake), file: file)
        let result = await owner.scan(maxPages: 1)
        XCTAssertEqual(result, .morePending)
        let overflowed = await owner.snapshot()
        XCTAssertTrue(overflowed.dirtyIntervals.isEmpty)
        XCTAssertTrue(overflowed.requiresFullRepair)
        XCTAssertNil(overflowed.repairProgress, "Overflow drops the marks with the intervals, so the progress goes too")
    }

    // MARK: - A workout during a full repair reopens only what it touched

    private struct FullRepairFixture {
        let store: HealthKitWorkoutStore
        let fake: FakeHealthStore
        let directory: URL
        let file: URL
        let january: WorkoutJournalEntry
        let march: WorkoutJournalEntry
        let ledger: WorkoutRecordLedger
        let progress: WorkoutJournalRepairProgress

        var workoutReads: Int {
            fake.leafRequests.filter { $0 == .samples(HKObjectType.workoutType().identifier) }.count
        }
    }

    private func workoutEntry(id: UUID = UUID(), month: Int, day: Int, activityType: UInt = 37) -> WorkoutJournalEntry {
        let start = calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: 8))!
        return WorkoutJournalEntry(id: id, start: start, end: start.addingTimeInterval(1_800),
            activityType: activityType, duration: 1_800, sourceBundleIdentifier: "com.example.test")
    }

    private func moved(_ entry: WorkoutJournalEntry, month: Int, day: Int) -> WorkoutJournalEntry {
        workoutEntry(id: entry.id, month: month, day: day, activityType: entry.activityType)
    }

    /// Same id and interval, different fields: `dirtyIntervals` cannot see it.
    private func relabelled(_ entry: WorkoutJournalEntry, activityType: UInt) -> WorkoutJournalEntry {
        WorkoutJournalEntry(id: entry.id, start: entry.start, end: entry.end, activityType: activityType,
            duration: entry.duration, sourceBundleIdentifier: entry.sourceBundleIdentifier)
    }

    /// A full repair waiting on its records baseline, with this context's
    /// freshness, detail and ledger invalidations done; 2024:1 and 2024:3
    /// completed; every other planned month backing off, so only reopened months
    /// are eligible; and a record ledger and detail file for both workouts at
    /// their real, parked locations. The envelope written by this build carries
    /// no `uncovered` key, exactly like a build 5 progress.
    @MainActor
    private func makeFullRepairFixture() async throws -> FullRepairFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldOverride = HealthKitWorkoutStore.testSnapshotDirectoryURLOverride
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = directory.appendingPathComponent("months")
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        let coverage = HealthDashboardSnapshotStore.loadLastWorkoutsWeekCoverageDate()
        addTeardownBlock {
            await MainActor.run { HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = oldOverride }
            restoreDefaults()
            if let coverage { HealthDashboardSnapshotStore.saveLastWorkoutsWeekCoverageDate(coverage) }
            else { HealthDashboardSnapshotStore.clearLastWorkoutsWeekCoverageDate() }
            try? FileManager.default.removeItem(at: directory)
        }
        try await isolateDashboardEnvelope(includingRepairArtifacts: true)
        let fake = FakeHealthStore()
        fake.scriptSamples(for: HKObjectType.workoutType(), .failure(nil))
        let file = directory.appendingPathComponent("journal.json")
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]), engineHealthStore: fake,
            workoutJournalFile: file)
        store.contextRefreshOverride = { _ in }
        let january = workoutEntry(month: 1, day: 12), march = workoutEntry(month: 3, day: 12)
        var journal = WorkoutChangeJournal(scope: .init(installationID: UUID(),
            lowerBound: calendar.date(from: DateComponents(year: 2023, month: 12, day: 1))!, predicateVersion: 1))
        journal.staging = nil
        journal.requiresFullRepair = true
        for entry in [january, march] {
            journal.entries[entry.id.uuidString] = entry
            journal.dirtyIntervals[entry.id.uuidString] = DateInterval(start: entry.start, end: entry.end)
        }
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(journal, file: file), .failed)
        // This context's first pass does what a full repair does once: clears the
        // freshness, the detail files and the ledger. Its month read fails.
        let setup = WorkoutJournalReconciler(engine: store.engine, file: file)
        await store.repairWorkoutJournal(journal, owner: setup, admission: HealthDashboardPublicationToken(), maximumMonths: 1)
        let started = await setup.snapshot()
        var progress = try XCTUnwrap(started.repairProgress)
        XCTAssertEqual(progress.freshnessInvalidated, true)
        XCTAssertTrue(progress.detailsInvalidated)
        XCTAssertTrue(progress.baselineInvalidated)
        let plan = try XCTUnwrap(WorkoutJournalRepairPlan(journal: started, retainedMonths: Set(store.monthSnapshots.keys),
                                                          date: Date(), calendar: .bodyGregorian))
        progress.completedMonths = ["2024:1", "2024:3"]
        progress.monthAttempts = nil
        for key in plan.months where !progress.completedMonths.contains(WorkoutJournalRepairPlan.identity(key)) {
            progress.beginMonthAttempt(WorkoutJournalRepairPlan.identity(key), at: Date())
        }
        let checkpointed = await setup.checkpointRepair(progress, generation: started.generation, revision: started.revision)
        XCTAssertTrue(checkpointed)
        var ledger = WorkoutRecordLedger()
        ledger.upsert([
            WorkoutSummary(id: january.id, type: .running, startDate: january.start, duration: 1_800, distanceMeters: 5_000),
            WorkoutSummary(id: march.id, type: .running, startDate: march.start, duration: 1_800, distanceMeters: 6_000),
        ])
        ledger.scannedThrough = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))
        store.publishRecordLedger(ledger)
        let seeded = await store.persistWorkoutJournalRecordLedger()
        XCTAssertTrue(seeded)
        XCTAssertNotNil(store.recordLedger.contributions[january.id])
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(WorkoutDetailSnapshot(workoutID: january.id, heartRateRecoveryBPM: 10)))
        XCTAssertTrue(WorkoutDetailSnapshotStore.save(WorkoutDetailSnapshot(workoutID: march.id, heartRateRecoveryBPM: 20)))
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([]))
        return FullRepairFixture(store: store, fake: fake, directory: directory, file: file, january: january,
                                 march: march, ledger: store.recordLedger, progress: progress)
    }

    /// One pass through a fresh owner, as after a relaunch.
    @MainActor @discardableResult
    private func repairPass(_ fixture: FullRepairFixture, maximumMonths: Int = 1,
                            write: (@Sendable (Data, URL) throws -> Void)? = nil,
                            admission: HealthDashboardPublicationToken = HealthDashboardPublicationToken()) async -> Bool {
        let owner = write.map { WorkoutJournalReconciler(engine: fixture.store.engine, file: fixture.file, write: $0) }
            ?? WorkoutJournalReconciler(engine: fixture.store.engine, file: fixture.file)
        let journal = await owner.snapshot()
        return await fixture.store.repairWorkoutJournal(journal, owner: owner, admission: admission,
                                                        maximumMonths: maximumMonths)
    }

    /// Commits a delta the way a scan page does: `apply`, then one atomic save.
    @discardableResult
    private func commitDelta(_ fixture: FullRepairFixture, additions: [WorkoutJournalEntry] = [],
                             deletedIDs: [UUID] = [], anchor: UInt8) throws
        -> (before: WorkoutChangeJournal, after: WorkoutChangeJournal) {
        let before = try XCTUnwrap(WorkoutChangeJournalStore.load(file: fixture.file))
        var after = before
        after.apply(additions: additions, deletedIDs: deletedIDs, nextAnchor: Data([anchor]))
        XCTAssertEqual(WorkoutChangeJournalStore.save(after, file: fixture.file), .written)
        return (before, after)
    }

    private func savedProgress(_ fixture: FullRepairFixture) throws -> WorkoutJournalRepairProgress {
        try XCTUnwrap(WorkoutChangeJournalStore.load(file: fixture.file)?.repairProgress)
    }

    /// Reaches the quiet maintenance preconditions without a badge: after a
    /// stamped freshness has completed the first load, a silent month refresh
    /// confirms authorization. The month is inside the plan's window, so it is
    /// already backing off.
    @MainActor
    private func authorizeQuietMaintenance(_ fixture: FullRepairFixture) async {
        let month = BodyWorkoutMonthKey(date: Date().addingTimeInterval(-200 * 86_400), calendar: .bodyGregorian)
        await fixture.store.refreshWorkoutMonth(month: month.month, year: month.year, intent: .passiveResume)
        XCTAssertTrue(fixture.store.authorizationState == .authorized)
        XCTAssertFalse(fixture.store.needsInitialHealthDataLoad)
    }

    /// Runs the foreground journal lifecycle to its end. Callers keep the app in
    /// the background otherwise, so no other quiet owner runs between steps.
    @MainActor
    private func runJournalLifecycle(_ store: HealthKitWorkoutStore) async throws {
        // Let work a finished refresh queued (an observer follow-up) see the
        // background state first, so it stands down instead of joining in.
        await Task.yield()
        BodyAppRuntime.setForegroundActive(true)
        store.scheduleWorkoutJournalIfNeeded()
        XCTAssertTrue(store.hasWorkoutJournalWork, "The foreground lifecycle admits a journal run")
        for _ in 0..<1_000 where store.hasWorkoutJournalWork { try await Task.sleep(for: .milliseconds(10)) }
        BodyAppRuntime.setForegroundActive(false)
        XCTAssertFalse(store.hasWorkoutJournalWork, "The journal run finishes")
        // Its exit offers the records owner; join that so it cannot overlap the next step.
        await store.cancelRecordBaselineBackfill()
    }

    @MainActor
    func testKnownDeletionDuringAFullRepairReopensItsMonthAndKeepsFreshnessAndBaseline() async throws {
        let fixture = try await makeFullRepairFixture()
        let store = fixture.store
        let stamp = await stampFreshness(store, secondsAgo: 60)
        let before = try XCTUnwrap(WorkoutChangeJournalStore.load(file: fixture.file))
        fixture.fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [fixture.january.id], anchor: Data([2])))])
        let scanner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        let result = await scanner.scan(maxPages: 1)
        XCTAssertEqual(result, .morePending)
        let scanned = await scanner.snapshot()
        XCTAssertEqual(scanned.dirtyIntervals, before.dirtyIntervals, "Deleting a repaired workout leaves the dirty set equal")
        XCTAssertEqual(scanned.repairProgress?.completedMonths, ["2024:1", "2024:3"], "The delta alone reopens nothing")
        XCTAssertEqual(scanned.repairProgress?.uncovered,
                       [fixture.january.id.uuidString: DateInterval(start: fixture.january.start, end: fixture.january.end)])
        let reads = fixture.workoutReads

        let repaired = await repairPass(fixture)
        XCTAssertTrue(repaired)
        XCTAssertEqual(fixture.workoutReads, reads + 1, "Only the reopened month is read")
        XCTAssertTrue(store.hasFreshSnapshot(month: 1, year: 2024))
        let progress = try savedProgress(fixture)
        XCTAssertEqual(progress.context, fixture.progress.context)
        XCTAssertEqual(progress.completedMonths, ["2024:1", "2024:3"])
        XCTAssertNil(progress.uncovered)
        XCTAssertNil(progress.finalAttempt)
        XCTAssertEqual(progress.freshnessInvalidated, true)
        XCTAssertTrue(progress.detailsInvalidated)
        XCTAssertTrue(progress.baselineInvalidated)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, stamp, "A known delta never clears the freshness again")
        let persisted = await persistedFreshnessDate()
        XCTAssertEqual(persisted, stamp)
        let ledger = try XCTUnwrap(WorkoutRecordLedgerStore.load())
        XCTAssertNil(ledger.contributions[fixture.january.id], "The refetched month folds the deletion out")
        XCTAssertNotNil(ledger.contributions[fixture.march.id])
        XCTAssertEqual(ledger.scannedThrough, fixture.ledger.scannedThrough, "The records baseline is not restarted")
        XCTAssertFalse(ledger.baselineComplete)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: fixture.january.id))
        XCTAssertEqual(WorkoutDetailSnapshotStore.load(workoutID: fixture.march.id)?.heartRateRecoveryBPM, 20,
                       "Only the changed workout's detail file is removed")
    }

    @MainActor
    func testSameIntervalEditReopensItsMonthAndDropsOnlyItsDetailFile() async throws {
        let fixture = try await makeFullRepairFixture()
        let stamp = await stampFreshness(fixture.store, secondsAgo: 60)
        let delta = try commitDelta(fixture, additions: [relabelled(fixture.january, activityType: 52)], anchor: 2)
        XCTAssertEqual(delta.after.dirtyIntervals, delta.before.dirtyIntervals)
        XCTAssertNotNil(delta.after.repairProgress?.uncovered?[fixture.january.id.uuidString])
        let reads = fixture.workoutReads
        let repaired = await repairPass(fixture)
        XCTAssertTrue(repaired)
        XCTAssertEqual(fixture.workoutReads, reads + 1)
        XCTAssertTrue(fixture.store.hasFreshSnapshot(month: 1, year: 2024))
        let progress = try savedProgress(fixture)
        XCTAssertEqual(progress.completedMonths, ["2024:1", "2024:3"])
        XCTAssertNil(progress.uncovered)
        XCTAssertEqual(fixture.store.lastSuccessfulRefreshDate, stamp)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: fixture.january.id))
        XCTAssertEqual(WorkoutDetailSnapshotStore.load(workoutID: fixture.march.id)?.heartRateRecoveryBPM, 20)
    }

    @MainActor
    func testMovedWorkoutReopensItsWholeBoundsAndASecondMoveInsideThemReopensAgain() async throws {
        let fixture = try await makeFullRepairFixture()
        try commitDelta(fixture, additions: [moved(fixture.january, month: 3, day: 20)], anchor: 2)
        var reads = fixture.workoutReads
        let first = await repairPass(fixture, maximumMonths: 3)
        XCTAssertTrue(first)
        XCTAssertEqual(fixture.workoutReads, reads + 3, "A January to March move also covers February")
        for month in 1...3 {
            XCTAssertTrue(fixture.store.hasFreshSnapshot(month: month, year: 2024), "2024:\(month)")
        }
        XCTAssertTrue(try savedProgress(fixture).completedMonths.isSuperset(of: ["2024:1", "2024:2", "2024:3"]))

        let delta = try commitDelta(fixture, additions: [moved(fixture.january, month: 2, day: 10)], anchor: 3)
        XCTAssertEqual(delta.after.dirtyIntervals, delta.before.dirtyIntervals, "The second move stays inside the covered bounds")
        reads = fixture.workoutReads
        let second = await repairPass(fixture, maximumMonths: 3)
        XCTAssertTrue(second)
        XCTAssertEqual(fixture.workoutReads, reads + 2, "February and March reopen again")
        XCTAssertNil(try savedProgress(fixture).uncovered)
    }

    @MainActor
    func testUnknownDeletionStillStartsAFreshProgressThatClearsFreshnessAndTheLedger() async throws {
        let fixture = try await makeFullRepairFixture()
        let store = fixture.store
        await stampFreshness(store, secondsAgo: 60)
        fixture.fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [UUID()], anchor: Data([2])))])
        let scanner = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        _ = await scanner.scan(maxPages: 1)
        let scanned = await scanner.snapshot()
        XCTAssertNil(scanned.repairProgress)
        XCTAssertTrue(scanned.requiresFullRepair)
        await repairPass(fixture)
        XCTAssertNil(store.lastSuccessfulRefreshDate, "A fresh progress clears the freshness once")
        let persisted = await persistedFreshnessDate()
        XCTAssertNil(persisted)
        let progress = try savedProgress(fixture)
        XCTAssertEqual(progress.freshnessInvalidated, true)
        XCTAssertTrue(progress.baselineInvalidated)
        XCTAssertTrue(progress.detailsInvalidated)
        XCTAssertFalse(progress.completedMonths.contains("2024:3"), "Nothing completed before the reset is trusted")
        let ledger = try XCTUnwrap(WorkoutRecordLedgerStore.load())
        XCTAssertTrue(ledger.contributions.isEmpty, "The unmapped deletion wipes the ledger")
        XCTAssertNil(ledger.scannedThrough)
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: fixture.march.id))
    }

    @MainActor
    func testInterruptedPassStripsTheReopenedMonthAndReopensAgainNextTime() async throws {
        let fixture = try await makeFullRepairFixture()
        let store = fixture.store
        try commitDelta(fixture, additions: [relabelled(fixture.january, activityType: 52)], anchor: 2)
        let settled = await repairPass(fixture)
        XCTAssertTrue(settled)
        XCTAssertTrue(store.hasFreshSnapshot(month: 1, year: 2024))

        try commitDelta(fixture, additions: [relabelled(fixture.january, activityType: 13)], anchor: 3)
        let beforeInterruption = try Data(contentsOf: fixture.file)
        // Admission is lost at the first journal write after reopening, the
        // details checkpoint, and that write never lands.
        let admission = HealthDashboardPublicationToken()
        let reads = fixture.workoutReads
        let interrupted = await repairPass(fixture, write: { _, _ in
            admission.invalidate()
            throw CocoaError(.fileWriteUnknown)
        }, admission: admission)
        XCTAssertFalse(interrupted)
        XCTAssertFalse(store.hasFreshSnapshot(month: 1, year: 2024), "The reopened month lost its validation before any suspension")
        XCTAssertNil(store.monthSnapshots[BodyWorkoutMonthKey(month: 1, year: 2024)]?.validatedAt)
        XCTAssertEqual(fixture.workoutReads, reads)
        XCTAssertEqual(try Data(contentsOf: fixture.file), beforeInterruption)
        let durable = try savedProgress(fixture)
        XCTAssertNotNil(durable.uncovered?[fixture.january.id.uuidString], "The mark stays until the details checkpoint lands")
        XCTAssertTrue(durable.completedMonths.contains("2024:1"), "The reopening itself was never durable")

        let resumed = await repairPass(fixture)
        XCTAssertTrue(resumed)
        XCTAssertEqual(fixture.workoutReads, reads + 1)
        XCTAssertTrue(store.hasFreshSnapshot(month: 1, year: 2024))
        XCTAssertNil(try savedProgress(fixture).uncovered)
    }

    @MainActor
    func testTwoReopenedMonthsRepairOneUnitAtATimeWhileTheOtherStaysUnvalidated() async throws {
        let fixture = try await makeFullRepairFixture()
        let store = fixture.store
        try commitDelta(fixture, additions: [relabelled(fixture.january, activityType: 52),
                                             relabelled(fixture.march, activityType: 52)], anchor: 2)
        let both = await repairPass(fixture, maximumMonths: 3)
        XCTAssertTrue(both)
        XCTAssertTrue(store.hasFreshSnapshot(month: 1, year: 2024))
        XCTAssertTrue(store.hasFreshSnapshot(month: 3, year: 2024))

        try commitDelta(fixture, additions: [relabelled(fixture.january, activityType: 13),
                                             relabelled(fixture.march, activityType: 13)], anchor: 3)
        let first = await repairPass(fixture, maximumMonths: 1)
        XCTAssertTrue(first)
        XCTAssertTrue(store.hasFreshSnapshot(month: 1, year: 2024))
        XCTAssertFalse(store.hasFreshSnapshot(month: 3, year: 2024), "The second reopened month is not fresh after the first unit")
        let partial = try savedProgress(fixture)
        XCTAssertTrue(partial.completedMonths.contains("2024:1"))
        XCTAssertFalse(partial.completedMonths.contains("2024:3"))
        XCTAssertNil(partial.uncovered, "Completion, not the mark, now carries the remaining month")

        let second = await repairPass(fixture, maximumMonths: 1)
        XCTAssertTrue(second)
        XCTAssertTrue(store.hasFreshSnapshot(month: 3, year: 2024))
        XCTAssertTrue(try savedProgress(fixture).completedMonths.isSuperset(of: ["2024:1", "2024:3"]))
    }

    @MainActor
    func testLifecycleRepairsAReopenedMonthThenTheNextPendingMonthAndStopsOnBackoff() async throws {
        let fixture = try await makeFullRepairFixture()
        let store = fixture.store
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(false)
        defer { BodyAppRuntime.setForegroundActive(foreground) }
        let stamp = await stampFreshness(store, secondsAgo: 60)
        await authorizeQuietMaintenance(fixture)
        // 2024:1 is completed and reopened by an edit; 2024:3 is pending and
        // eligible; every other month backs off.
        var journal = try XCTUnwrap(WorkoutChangeJournalStore.load(file: fixture.file))
        journal.repairProgress?.completedMonths.remove("2024:3")
        journal.apply(additions: [relabelled(fixture.january, activityType: 52)], deletedIDs: [], nextAnchor: Data([2]))
        XCTAssertEqual(journal.repairProgress?.completedMonths, ["2024:1"])
        XCTAssertEqual(WorkoutChangeJournalStore.save(journal, file: fixture.file), .written)

        try await runJournalLifecycle(store)
        let progress = try savedProgress(fixture)
        XCTAssertTrue(progress.completedMonths.isSuperset(of: ["2024:1", "2024:3"]),
                      "Completing the reopened month keeps the loop going to the pending one")
        XCTAssertNil(progress.uncovered)
        XCTAssertEqual(progress.context, fixture.progress.context)
        XCTAssertTrue(store.hasFreshSnapshot(month: 1, year: 2024))
        XCTAssertTrue(store.hasFreshSnapshot(month: 3, year: 2024))
        XCTAssertEqual(store.lastSuccessfulRefreshDate, stamp, "The resumed progress does not clear the freshness")

        let settled = try Data(contentsOf: fixture.file)
        try await runJournalLifecycle(store)
        XCTAssertEqual(try Data(contentsOf: fixture.file), settled, "A backoff-only run checkpoints nothing and stops")
    }

    @MainActor
    func testBuild5ProgressResumesWithNothingReopenedAndAfterReloadStillReopensOnADelta() async throws {
        let fixture = try await makeFullRepairFixture()
        let stamp = await stampFreshness(fixture.store, secondsAgo: 60)
        let legacy = try Data(contentsOf: fixture.file)
        XCTAssertFalse(String(decoding: legacy, as: UTF8.self).contains("uncovered"), "A build 5 envelope has no mark")
        var reads = fixture.workoutReads
        let idle = await repairPass(fixture, maximumMonths: 3)
        XCTAssertFalse(idle, "Nothing was reopened, so nothing completes")
        XCTAssertEqual(fixture.workoutReads, reads)
        XCTAssertEqual(try Data(contentsOf: fixture.file), legacy)
        XCTAssertEqual(fixture.store.lastSuccessfulRefreshDate, stamp)

        let reloaded = WorkoutJournalReconciler(engine: fixture.store.engine, file: fixture.file)
        let loaded = await reloaded.snapshot()
        XCTAssertEqual(loaded.repairProgress, fixture.progress)
        try commitDelta(fixture, additions: [relabelled(fixture.march, activityType: 52)], anchor: 2)
        reads = fixture.workoutReads
        let reopened = await repairPass(fixture, maximumMonths: 3)
        XCTAssertTrue(reopened)
        XCTAssertEqual(fixture.workoutReads, reads + 1)
        XCTAssertTrue(fixture.store.hasFreshSnapshot(month: 3, year: 2024))
        XCTAssertEqual(fixture.store.lastSuccessfulRefreshDate, stamp)
    }

    @MainActor
    func testBuild5ProgressWithAScannedAdditionBeforeItsFirstRepairReopensThatMonth() async throws {
        let fixture = try await makeFullRepairFixture()
        let start = calendar.date(from: DateComponents(year: 2024, month: 3, day: 15, hour: 8))!
        let workout = makeTestWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1_800), metadata: nil)
        fixture.fake.scriptWorkoutChanges([.success(.init(workouts: [workout], deletedIDs: [], anchor: Data([2])))])
        let scanner = WorkoutJournalReconciler(engine: fixture.store.engine, file: fixture.file)
        let result = await scanner.scan(maxPages: 1)
        XCTAssertEqual(result, .morePending)
        XCTAssertNotNil(try savedProgress(fixture).uncovered?[workout.uuid.uuidString])
        let reads = fixture.workoutReads
        let repaired = await repairPass(fixture)
        XCTAssertTrue(repaired)
        XCTAssertEqual(fixture.workoutReads, reads + 1)
        XCTAssertTrue(fixture.store.hasFreshSnapshot(month: 3, year: 2024))
        XCTAssertNil(try savedProgress(fixture).uncovered)
    }

    /// `activationBranch` is a DEBUG local that only reaches the log, so the
    /// branches are asserted through their effects: `skip` reads nothing,
    /// `workoutOnly` re-reads the current month (and, being workout only, never
    /// restamps the dashboard freshness).
    @MainActor
    func testWorkoutOnlyDeliveryKeepsFreshnessSkipsQuickReturnsAndIsSeenOnceScanned() async throws {
        let fixture = try await makeFullRepairFixture()
        let store = fixture.store
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(false)
        defer { BodyAppRuntime.setForegroundActive(foreground) }
        let refreshed = await stampFreshness(store, secondsAgo: 60)
        // A new observer ledger starts every domain pending (Training Load rides
        // the effort score type Workouts reads), so acknowledge them first: the
        // only change in this test is the workout delivery.
        let dirtyFile = fixture.directory.appendingPathComponent("dirty.json")
        let domains = Set(BodyHealthObservationPolicy.registrations(permissions: store.permissionSelection,
            selection: .load(), includesCompanionConsumers: true).flatMap(\.metrics))
        let setupLedger = BodyHealthDirtyWorkStore(file: dirtyFile, domains: domains, context: store.currentObserverLedgerContext())
        for kind in domains {
            let receipt = await setupLedger.receipt(for: kind)
            let acknowledged = await setupLedger.acknowledge(try XCTUnwrap(receipt), current: true, history: true)
            XCTAssertTrue(acknowledged)
        }
        let observer = FakeHealthObserver()
        let coordinator = BodyHealthChangeCoordinator(store: store, file: dirtyFile,
                                                       observing: observer, suppressesInitialDelivery: { false })
        await coordinator.configure()
        store.healthChangeCoordinator = coordinator
        defer { store.healthChangeCoordinator = nil }
        let current = BodyWorkoutMonthKey(date: Date(), calendar: .bodyGregorian)
        let entry = Date()

        // Inside the freshness window with nothing pending, a return re-reads the
        // current month and records the entry for the debounce.
        var reads = fixture.workoutReads
        await store.syncWhenAppBecomesActive(date: entry)
        XCTAssertFalse(store.hasObservedHealthChanges)
        XCTAssertEqual(fixture.workoutReads, reads + 1)
        XCTAssertTrue(store.hasFreshSnapshot(month: current.month, year: current.year))
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshed)

        // A workout-only delivery records a scan request, not observed metric work.
        let workoutType = HKObjectType.workoutType().identifier
        let registration = try XCTUnwrap(observer.registrations.first { $0.value.type.identifier == workoutType }?.key)
        let delivered = expectation(description: "workout delivery captured")
        observer.fire(registration) { delivered.fulfill() }
        await fulfillment(of: [delivered], timeout: 5)
        XCTAssertNotNil(WorkoutChangeJournalStore.load(file: fixture.file)?.pendingObservation)

        // Within five minutes of the last entry the return skips.
        reads = fixture.workoutReads
        await store.syncWhenAppBecomesActive(date: entry.addingTimeInterval(60))
        XCTAssertFalse(store.hasObservedHealthChanges, "A workout-only delivery does not bypass the debounce")
        XCTAssertEqual(fixture.workoutReads, reads, "A quick return reads nothing")
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshed)

        // Unscanned, the delta is invisible to the repair: the foreground
        // lifecycle never scans while a repair is dirty.
        try await runJournalLifecycle(store)
        let unscanned = try XCTUnwrap(WorkoutChangeJournalStore.load(file: fixture.file))
        XCTAssertNotNil(unscanned.pendingObservation)
        XCTAssertNil(unscanned.repairProgress?.uncovered)
        XCTAssertEqual(unscanned.repairProgress?.completedMonths, fixture.progress.completedMonths)
        XCTAssertFalse(store.hasFreshSnapshot(month: 3, year: 2024))
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshed)

        // A background wake scans the delta, a known deletion of the March workout.
        fixture.fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [fixture.march.id], anchor: Data([2])))])
        await store.scanObservedWorkouts(lease: BodyBackgroundLease(), scanOnly: true)
        XCTAssertNotNil(try savedProgress(fixture).uncovered?[fixture.march.id.uuidString])

        // After five minutes with nothing pending, the current month again, silently.
        reads = fixture.workoutReads
        await store.syncWhenAppBecomesActive(date: entry.addingTimeInterval(301))
        XCTAssertEqual(fixture.workoutReads, reads + 1)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshed)

        // The next lifecycle unit reopens and refetches the scanned month and
        // keeps the freshness; the final step stays behind the baseline.
        try await runJournalLifecycle(store)
        let progress = try savedProgress(fixture)
        XCTAssertNil(progress.uncovered)
        XCTAssertTrue(progress.completedMonths.contains("2024:3"))
        XCTAssertNil(progress.finalAttempt)
        XCTAssertTrue(store.hasFreshSnapshot(month: 3, year: 2024), "The scanned month was reopened and refetched")
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshed, "Reopening never clears the kept freshness")
        XCTAssertNil(WorkoutDetailSnapshotStore.load(workoutID: fixture.march.id))
    }
}
