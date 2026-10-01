import HealthKit
import XCTest
@testable import Body

final class WorkoutRecordValidationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEngine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        HealthKitFetchEngine(permission: .init(enabledPermissions: [.workouts]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake, effortLedgerDirectoryURL: nil)
    }

    func testDistanceFailureRetainsContributionAndCheckpointThenEmptyAndRetryRepair() async throws {
        let workout = makeTestWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800), metadata: nil)
        let distanceType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning))
        let effortType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .workoutEffortScore))
        let fake = FakeHealthStore()
        let engine = makeEngine(fake)
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        fake.scriptSamples(for: effortType, .failure(nil))
        fake.scriptStatistics(for: distanceType, .failure(nil))

        var ledger = WorkoutRecordLedger()
        ledger.upsert(WorkoutSummary(id: workout.uuid, type: .running, startDate: start,
            duration: 1800, distanceMeters: 5000))
        ledger.scannedThrough = start
        let failed = try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false)
        XCTAssertEqual(failed.workouts.count, 1, "Display membership survives a detail failure")
        XCTAssertEqual(failed.unvalidatedRecordIDs, [workout.uuid])
        ledger.reconcile(workouts: failed.workouts, start: start, end: start.addingTimeInterval(3600),
            unvalidatedRecordIDs: failed.unvalidatedRecordIDs)
        XCTAssertEqual(ledger.contributions[workout.uuid]?.values[.distance], 5000)
        XCTAssertFalse(ledger.applyValidatedBaselineChunk(workouts: failed.workouts,
            scannedThrough: start.addingTimeInterval(3600), unvalidatedRecordIDs: failed.unvalidatedRecordIDs))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RecordValidation.\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger, directoryURL: directory))
        ledger = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directory))
        XCTAssertEqual(ledger.scannedThrough, start)
        XCTAssertEqual(ledger.contributions[workout.uuid]?.values[.distance], 5000)

        fake.scriptCumulativeQuantity(for: distanceType, quantity: nil)
        let empty = try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false)
        XCTAssertTrue(empty.unvalidatedRecordIDs.isEmpty, "An effort failure is not a record-input failure")
        XCTAssertTrue(ledger.applyValidatedBaselineChunk(workouts: empty.workouts,
            scannedThrough: start.addingTimeInterval(3600), unvalidatedRecordIDs: empty.unvalidatedRecordIDs))
        XCTAssertNil(ledger.contributions[workout.uuid]?.values[.distance])
        XCTAssertTrue(WorkoutRecordLedgerStore.save(ledger, directoryURL: directory))
        ledger = try XCTUnwrap(WorkoutRecordLedgerStore.load(directoryURL: directory))
        XCTAssertNil(ledger.contributions[workout.uuid]?.values[.distance])
        XCTAssertEqual(ledger.scannedThrough, start.addingTimeInterval(3600))

        fake.scriptCumulativeQuantity(for: distanceType, quantity: .init(unit: .meter(), doubleValue: 6000))
        let retry = try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false)
        ledger.reconcile(workouts: retry.workouts, start: start, end: start.addingTimeInterval(3600),
            unvalidatedRecordIDs: retry.unvalidatedRecordIDs)
        XCTAssertEqual(ledger.contributions[workout.uuid]?.values[.distance], 6000)
    }

    func testRecordBaselineChunkEndAddsOneQuarterAndClampsToEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
        }
        func chunkEnd(_ cursor: Date, _ end: Date) -> Date {
            HealthKitWorkoutStore.recordBaselineChunkEnd(after: cursor, end: end, calendar: calendar)
        }
        let end = try date(2026, 9, 26, 12)
        XCTAssertEqual(chunkEnd(try date(2025, 1, 1), end), try date(2025, 4, 1), "cursor plus three months")
        XCTAssertEqual(chunkEnd(try date(2025, 2, 17, 9), end), try date(2025, 5, 17, 9),
                       "a mid-month cursor keeps its day and time")
        XCTAssertEqual(chunkEnd(try date(2026, 6, 26, 12), end), end, "lands exactly on the end")
        XCTAssertEqual(chunkEnd(try date(2026, 8, 3), end), end, "clamps to the end")

        // A non-quarter-aligned walk ends with one short chunk.
        var cursor = try date(2025, 2, 17, 9)
        var ends: [Date] = []
        while cursor < end {
            let next = chunkEnd(cursor, end)
            XCTAssertGreaterThan(next, cursor)
            ends.append(next)
            cursor = next
        }
        XCTAssertEqual(ends, [try date(2025, 5, 17, 9), try date(2025, 8, 17, 9), try date(2025, 11, 17, 9),
                              try date(2026, 2, 17, 9), try date(2026, 5, 17, 9), try date(2026, 8, 17, 9), end])
    }

    /// Lets the first workout read through and holds every later one until released.
    private actor ChunkGate {
        private var entries = 0
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        /// True for the first caller only.
        func enter() -> Bool {
            entries += 1
            return entries == 1
        }
        func wait() async {
            guard !open else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func release() {
            open = true
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    @MainActor
    private static func drainPersistQueue() async {
        let queue = HealthKitWorkoutStore.snapshotPersistQueue
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    /// Parks the host's copy of a real on-disk directory the store writes to and
    /// restores it afterwards, like `WorkoutJournalLifecycleTests.isolateDashboardEnvelope`.
    @MainActor
    private func park(_ directory: URL) async throws {
        let parked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        await Self.drainPersistQueue()
        let existed = FileManager.default.fileExists(atPath: directory.path)
        if existed { try FileManager.default.moveItem(at: directory, to: parked) }
        addTeardownBlock {
            await Self.drainPersistQueue()
            try? FileManager.default.removeItem(at: directory)
            if existed { try? FileManager.default.moveItem(at: parked, to: directory) }
        }
    }

    @MainActor
    func testBaselineScanCommitsEachQuarterAndKeepsTheCursorWhenInterrupted() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        let months = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let oldMonthsOverride = HealthKitWorkoutStore.testSnapshotDirectoryURLOverride
        HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = months
        let gate = ChunkGate()
        addTeardownBlock {
            await gate.release()
            await MainActor.run {
                HealthKitWorkoutStore.testRecordBaselineEarliestWorkoutOverride = nil
                HealthKitWorkoutStore.testSnapshotDirectoryURLOverride = oldMonthsOverride
                BodyAppRuntime.setForegroundActive(foreground)
            }
            restoreDefaults()
            try? FileManager.default.removeItem(at: months)
        }
        try await park(try XCTUnwrap(WorkoutRecordLedgerStore.defaultDirectoryURL))
        try await park(try XCTUnwrap(HealthDashboardSnapshotStore.snapshotFileURL).deletingLastPathComponent())

        let calendar = Calendar.bodyGregorian
        let earliest = try XCTUnwrap(calendar.date(byAdding: .year, value: -2, to: Date()))
        let firstCursor = try XCTUnwrap(calendar.date(byAdding: .month, value: 3, to: earliest))
        let workoutStart = earliest.addingTimeInterval(86_400)
        let workout = makeTestWorkout(activityType: .running, start: workoutStart,
                                      end: workoutStart.addingTimeInterval(1800), metadata: nil)
        let distanceType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning))
        let effortType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .workoutEffortScore))
        let health = FakeHealthStore()
        health.scriptSamples(for: HKObjectType.workoutType(), .samples([]))
        health.scriptSamples(for: effortType, .samples([]))
        health.scriptCumulativeQuantity(for: distanceType, quantity: .init(unit: .meter(), doubleValue: 5000))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        // A finished refresh confirms authorization and completes the initial load.
        // The scan it may start waits on the unanswerable floor query; retire it.
        await store.requestAuthorizationAndRefresh(intent: .passiveResume)
        await store.cancelRecordBaselineBackfill()
        XCTAssertNil(store.recordBackfillTask)
        XCTAssertEqual(store.authorizationState, .authorized)
        XCTAssertTrue(store.mayStartQuietMaintenance)
        XCTAssertNil(store.recordLedger.scannedThrough)

        HealthKitWorkoutStore.testRecordBaselineEarliestWorkoutOverride = earliest
        let secondChunk = expectation(description: "second chunk read started")
        // A chunk issues more than one workout-type read (the list, then its
        // enrichment), so counting reads cannot find the chunk boundary. The
        // chunk list read carries a deterministic strict-start date predicate;
        // only the second quarter's is gated, every other read passes.
        let secondCursor = HealthKitWorkoutStore.recordBaselineChunkEnd(after: firstCursor, end: .distantFuture,
                                                                        calendar: calendar)
        let secondChunkPredicate = HKQuery.predicateForSamples(withStart: firstCursor, end: secondCursor,
                                                               options: [.strictStartDate])
        health.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        health.scriptSamples(for: HKObjectType.workoutType(), matching: secondChunkPredicate, .gated({
            // One-shot: a retried read after the release must not fulfill again.
            if await gate.enter() { secondChunk.fulfill() }
            await gate.wait()
        }, then: .samples([])))
        store.scheduleRecordBaselineBackfillIfNeeded()
        let task = try XCTUnwrap(store.recordBackfillTask)
        await fulfillment(of: [secondChunk], timeout: 5)

        // The first quarter committed durably before the second read began.
        await Self.drainPersistQueue()
        let committed = try XCTUnwrap(WorkoutRecordLedgerStore.load())
        XCTAssertEqual(committed.scannedThrough, firstCursor)
        XCTAssertFalse(committed.baselineComplete)
        XCTAssertNotNil(committed.contributions[workout.uuid])

        // Interrupt the second quarter: cancel, then let its held read return.
        task.cancel()
        // The scheduler forwards cancellation through a main actor hop; let it land
        // before the held read returns.
        await Task.yield()
        await gate.release()
        await store.cancelRecordBaselineBackfill()
        XCTAssertNil(store.recordBackfillTask)
        await Self.drainPersistQueue()
        let interrupted = try XCTUnwrap(WorkoutRecordLedgerStore.load())
        XCTAssertEqual(interrupted.scannedThrough, firstCursor)
        XCTAssertFalse(interrupted.baselineComplete)
        XCTAssertEqual(store.recordLedger.scannedThrough, firstCursor)
    }

    func testMembershipDeletionIsLimitedToSuccessfulCoveredInterval() {
        let inside = WorkoutSummary(id: UUID(), type: .running, startDate: start, duration: 1800, distanceMeters: 5000)
        let outside = WorkoutSummary(id: UUID(), type: .running, startDate: start.addingTimeInterval(-86400),
            duration: 1800, distanceMeters: 6000)
        var ledger = WorkoutRecordLedger()
        ledger.upsert([inside, outside])
        ledger.reconcile(workouts: [], start: start, end: start.addingTimeInterval(3600), unvalidatedRecordIDs: [])
        XCTAssertNil(ledger.contributions[inside.id])
        XCTAssertNotNil(ledger.contributions[outside.id])
    }

    func testCancelledDistanceReadCannotValidateChunk() async throws {
        let workout = makeTestWorkout(activityType: .running, start: start, end: start.addingTimeInterval(1800), metadata: nil)
        let distanceType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning))
        let effortType = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .workoutEffortScore))
        let fake = FakeHealthStore()
        fake.scriptSamples(for: HKObjectType.workoutType(), .samples([workout]))
        fake.scriptSamples(for: effortType, .samples([]))
        fake.scriptStatistics(for: distanceType, .never)
        let engine = makeEngine(fake)
        let start = start
        let task = Task { try await engine.fetchWorkoutSummariesWithValidation(startDate: start,
            endDate: start.addingTimeInterval(3600), includesHeartRateSamples: false) }
        for _ in 0..<100 where !fake.leafRequests.contains(.statistics(distanceType.identifier)) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(fake.leafRequests.contains(.statistics(distanceType.identifier)))
        task.cancel()
        let result = try await task.value
        XCTAssertEqual(result.unvalidatedRecordIDs, [workout.uuid])
    }
}
