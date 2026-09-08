import HealthKit
import XCTest
import os
@testable import Body

final class WorkoutJournalReconcilerTests: XCTestCase {
    private actor Gate {
        private var waiter: CheckedContinuation<Void, Never>?
        private var released = false
        func wait() async {
            guard !released else { return }
            await withCheckedContinuation { waiter = $0 }
        }
        func release() { released = true; waiter?.resume(); waiter = nil }
    }
    private let scope = WorkoutJournalScope(installationID: UUID(), lowerBound: Date(timeIntervalSince1970: 0), predicateVersion: 1)
    private func engine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        .init(permission: .init(enabledPermissions: [.workouts]), healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
            healthStore: fake, effortLedgerDirectoryURL: nil)
    }
    private func anchor(_ value: Int) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: HKQueryAnchor(fromValue: value), requiringSecureCoding: true)
    }
    private func workout() -> HKWorkout {
        .init(activityType: .running, start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 160))
    }

    func testPagedBootstrapReloadDeletionAndStaleAcknowledgment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json"), fake = FakeHealthStore(), workout = workout()
        let a = try anchor(1), b = try anchor(2)
        fake.scriptWorkoutChanges([.success(.init(workouts: [workout], deletedIDs: [], anchor: a))])
        let first = WorkoutJournalReconciler(engine: engine(fake), file: file, scope: scope)
        let partial = await first.scan(maxPages: 1)
        XCTAssertEqual(partial, .morePending)
        let pending = await first.snapshot()
        XCTAssertFalse(pending.bootstrapComplete)
        let earlyAck = await first.acknowledgeDurableRepair(generation: pending.generation, revision: pending.revision)
        XCTAssertFalse(earlyAck)
        let resumed = WorkoutJournalReconciler(engine: engine(fake), file: file, scope: scope)
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [], anchor: a))])
        let drained = await resumed.scan()
        XCTAssertEqual(drained, .caughtUp)
        XCTAssertEqual(fake.workoutChangeRequests.last?.anchor, a)
        XCTAssertTrue(fake.workoutChangeRequests.allSatisfy { $0.lowerBound == scope.lowerBound && $0.limit == 500 })
        let before = await resumed.snapshot()
        XCTAssertNotNil(before.entries[workout.uuid.uuidString])
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [workout.uuid], anchor: b))])
        let deleted = await resumed.scan(maxPages: 1)
        XCTAssertEqual(deleted, .morePending)
        let stale = await resumed.acknowledgeDurableRepair(generation: before.generation, revision: before.revision)
        XCTAssertFalse(stale)
        let after = await resumed.snapshot()
        XCTAssertNil(after.entries[workout.uuid.uuidString])
        XCTAssertNotNil(after.dirtyIntervals[workout.uuid.uuidString])
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), after)
        let ack = await resumed.acknowledgeDurableRepair(generation: after.generation, revision: after.revision)
        XCTAssertTrue(ack)
        let clean = try XCTUnwrap(WorkoutChangeJournalStore.load(file: file))
        XCTAssertTrue(clean.dirtyIntervals.isEmpty)
        XCTAssertFalse(clean.requiresFullRepair)
    }

    func testFailureAndTimeoutDoNotAdvanceAnchorAndOverlapIsBusy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json"), fake = FakeHealthStore()
        let owner = WorkoutJournalReconciler(engine: engine(fake), file: file, scope: scope)
        fake.scriptWorkoutChanges([.failure(nil)])
        let failed = await owner.scan()
        XCTAssertEqual(failed, .failed)
        let before = await owner.snapshot()
        let scan = Task { await owner.scan(deadline: .milliseconds(150)) }
        for _ in 0..<100 where fake.workoutChangeRequests.count < 2 { try await Task.sleep(for: .milliseconds(1)) }
        let overlap = await owner.scan()
        XCTAssertEqual(overlap, .busy)
        let timedOut = await scan.value
        XCTAssertEqual(timedOut, .timedOut)
        let after = await owner.snapshot()
        XCTAssertEqual(after, before)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), before)
    }

    func testRestartAndClearFenceSuspendedReadsAndInvalidAnchorBootstraps() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("journal.json"), fake = FakeHealthStore()
        let owner = WorkoutJournalReconciler(engine: engine(fake), file: file, scope: scope)
        let task = Task { await owner.scan(deadline: .milliseconds(150)) }
        for _ in 0..<100 where fake.workoutChangeRequests.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
        try await owner.clear()
        let cleared = await task.value
        XCTAssertEqual(cleared, .superseded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        fake.scriptWorkoutChanges([.failure(BodyWorkoutAnchorError.invalidArchive)])
        let old = await owner.snapshot()
        let invalid = await owner.scan()
        XCTAssertEqual(invalid, .morePending)
        let new = await owner.snapshot()
        XCTAssertNotEqual(old.generation, new.generation)
        XCTAssertNil(new.anchor)
        XCTAssertTrue(new.requiresFullRepair)
    }

    func testLateSuccessfulPageCannotCrossContextChangeOrClear() async throws {
        for clear in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fake = FakeHealthStore(), engine = engine(fake), gate = Gate()
            let file = directory.appendingPathComponent("journal.json")
            let owner = WorkoutJournalReconciler(engine: engine, file: file, scope: scope)
            let entered = expectation(description: "anchored page suspended")
            fake.scriptWorkoutChanges([.success(.init(workouts: [workout()], deletedIDs: [], anchor: try anchor(1)))])
            fake.pauseWorkoutChanges { entered.fulfill(); await gate.wait() }
            let task = Task { await owner.scan(maxPages: 1) }
            await fulfillment(of: [entered], timeout: 2)
            if clear { try await owner.clear() }
            else { await engine.setPermissionSelection(.init(enabledPermissions: [])) }
            await gate.release()
            let result = await task.value
            fake.pauseWorkoutChanges(using: nil)
            XCTAssertEqual(result, .superseded)
            let snapshot = await owner.snapshot()
            XCTAssertNil(snapshot.anchor)
            XCTAssertTrue(snapshot.entries.isEmpty)
            if clear { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
        }
    }

    func testPageAndAcknowledgmentWriteFailuresRetainDurablePendingWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = FakeHealthStore(), file = directory.appendingPathComponent("journal.json")
        let fail = OSAllocatedUnfairLock(initialState: false)
        let owner = WorkoutJournalReconciler(engine: engine(fake), file: file, scope: scope) { data, url in
            if fail.withLock({ $0 }) { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        }
        let a = try anchor(1), b = try anchor(2)
        fake.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [], anchor: a))])
        let initial = await owner.scan()
        XCTAssertEqual(initial, .caughtUp)
        let old = await owner.snapshot()
        XCTAssertTrue(old.requiresFullRepair, "Empty bootstrap is not proof of authorized, repaired dependencies")
        fail.withLock { $0 = true }
        let page = BodyWorkoutChanges(workouts: [workout()], deletedIDs: [], anchor: b)
        fake.scriptWorkoutChanges([.success(page)])
        let failed = await owner.scan(maxPages: 1)
        XCTAssertEqual(failed, .failed)
        let unchanged = await owner.snapshot()
        XCTAssertEqual(unchanged, old)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), old)
        fail.withLock { $0 = false }
        fake.scriptWorkoutChanges([.success(page)])
        let retried = await owner.scan(maxPages: 1)
        XCTAssertEqual(retried, .morePending)
        let pending = await owner.snapshot()
        fail.withLock { $0 = true }
        let checkpoint = await owner.checkpointRepair(.init(context: "current"),
            generation: pending.generation, revision: pending.revision)
        XCTAssertFalse(checkpoint)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), pending)
        let ack = await owner.acknowledgeDurableRepair(generation: pending.generation, revision: pending.revision)
        XCTAssertFalse(ack)
        XCTAssertEqual(WorkoutChangeJournalStore.load(file: file), pending)
        XCTAssertEqual(fake.workoutChangeRequests.suffix(2).map(\.anchor), [a, a])
    }
}
