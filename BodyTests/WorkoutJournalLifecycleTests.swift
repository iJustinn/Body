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
    /// non-durable `.preserved`, and restore it afterwards.
    @discardableResult @MainActor
    private func isolateDashboardEnvelope() async throws -> URL {
        let directory = try XCTUnwrap(HealthDashboardSnapshotStore.snapshotFileURL).deletingLastPathComponent()
        let parked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await Self.drainPersistQueue()
        let existed = FileManager.default.fileExists(atPath: directory.path)
        if existed { try FileManager.default.moveItem(at: directory, to: parked) }
        addTeardownBlock {
            await Self.drainPersistQueue()
            try? FileManager.default.removeItem(at: directory)
            if existed { try? FileManager.default.moveItem(at: parked, to: directory) }
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
        let dashboard = try await isolateDashboardEnvelope()
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
    func testContextReplacementAndNewDeltaEachClearFreshnessOnceMore() async throws {
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

        await stampFreshness(store, secondsAgo: 60)
        var delta = current
        delta.apply(additions: [addedWorkout()], deletedIDs: [], nextAnchor: Data([2]))
        XCTAssertNil(delta.repairProgress)
        XCTAssertNotEqual(WorkoutChangeJournalStore.save(delta, file: fixture.file), .failed)
        let reopened = WorkoutJournalReconciler(engine: store.engine, file: fixture.file)
        let loaded = await reopened.snapshot()
        await store.repairWorkoutJournal(loaded, owner: reopened, admission: HealthDashboardPublicationToken())
        XCTAssertNil(store.lastSuccessfulRefreshDate, "A new workout delta restarts the repair and clears once more")
        let cleared = await persistedFreshnessDate()
        XCTAssertNil(cleared)
        let restarted = await reopened.snapshot()
        XCTAssertEqual(restarted.repairProgress?.freshnessInvalidated, true)
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
    func testFinalDashboardStepBacksOffLikeAMonthUntilANewDelta() async throws {
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

        var delta = thirdAttempt
        delta.apply(additions: [addedWorkout()], deletedIDs: [], nextAnchor: Data([2]))
        XCTAssertNil(delta.repairProgress, "A new delta restarts the final step's ladder")
    }
}
