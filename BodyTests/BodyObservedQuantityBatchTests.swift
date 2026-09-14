import XCTest
import HealthKit
@testable import Body

@MainActor
final class BodyObservedQuantityBatchTests: XCTestCase {
    private actor ReadGate {
        private var open = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
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

    private struct Fixture {
        let store: HealthKitWorkoutStore
        let health: FakeHealthStore
        let ledger: BodyHealthDirtyWorkStore
        let file: URL
        let kinds: [HealthMetricKind] = [.restingHeartRate, .bodyMass, .bodyFatPercentage, .bodyMassIndex]
        let types: [HKQuantityType]
        func receipts() async throws -> [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] {
            var result: [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] = []
            for kind in kinds {
                let receipt = await ledger.receipt(for: kind)
                result.append((kind, try XCTUnwrap(receipt)))
            }
            return result
        }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("dirty.json")
        let health = FakeHealthStore()
        let types = try [HKQuantityTypeIdentifier.restingHeartRate, .bodyMass, .bodyFatPercentage, .bodyMassIndex].map {
            try XCTUnwrap(HKObjectType.quantityType(forIdentifier: $0))
        }
        for type in types {
            health.scriptSources(for: type, .sources([]))
            health.scriptSamples(for: type, .samples([]))
            health.scriptDailyQuantities(for: type, values: [])
        }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart, .basics]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let ledger = BodyHealthDirtyWorkStore(file: file,
            domains: [.restingHeartRate, .bodyMass, .bodyFatPercentage, .bodyMassIndex], context: store.currentObserverLedgerContext())
        let fixture = Fixture(store: store, health: health, ledger: ledger, file: file, types: types)
        let initial = try await fixture.receipts()
        let changed = await store.repairObservedMetrics(initial, ledger: ledger)
        XCTAssertFalse(changed, "Unresolved discovery must retire the initial fence before any reads")
        XCTAssertFalse(types.contains { health.leafRequests.contains(.samples($0.identifier)) })
        _ = await ledger.synchronize(domains: Set(fixture.kinds), context: store.currentObserverLedgerContext())
        try await body(fixture)
    }

    private func waitForFirstBatch(_ fixture: Fixture) async throws {
        for _ in 0..<200 {
            if fixture.types.prefix(3).allSatisfy({ fixture.health.leafRequests.contains(.samples($0.identifier)) }) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Three quantity reads must start before any gated read completes")
    }

    func testBackgroundHistoryWaitsForCurrentDerivedDependencies() async throws {
        try await withFixture { fixture in
            BodyAppRuntime.setForegroundActive(false)
            let receipt = await fixture.ledger.receipt(for: .restingHeartRate)
            _ = await fixture.ledger.acknowledge(try XCTUnwrap(receipt), current: true, history: false)
            _ = await fixture.ledger.mark([.heartRateVariability], context: fixture.store.currentObserverLedgerContext())
            let blocked = await fixture.store.repairObservedHistory(.restingHeartRate, ledger: fixture.ledger,
                lease: BodyBackgroundLease())
            XCTAssertFalse(blocked)
            let pending = await fixture.ledger.snapshot()
            XCTAssertEqual(pending.entries["restingHeartRate"]?.historyPending, true)
            let dependency = await fixture.ledger.receipt(for: .heartRateVariability)
            _ = await fixture.ledger.acknowledge(try XCTUnwrap(dependency), current: true, history: true)
            let unvalidated = await fixture.store.repairObservedHistory(.restingHeartRate, ledger: fixture.ledger,
                lease: BodyBackgroundLease())
            XCTAssertFalse(unvalidated, "Clearing a receipt cannot substitute for a successful dependency read")
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.heartRateVariability))
            let settled = await fixture.ledger.snapshot()
            XCTAssertEqual(settled.entries["restingHeartRate"]?.historyPending, true)
            XCTAssertFalse(fixture.store.isRefreshing)
        }
    }

    func testThreeReadsOverlapAndFourthWaitsForOrderedCommits() async throws {
        try await withFixture { fixture in
            let gate = ReadGate()
            for type in fixture.types { fixture.health.scriptSamples(for: type, .gated({ await gate.wait() }, then: .samples([]))) }
            let receipts = try await fixture.receipts()
            let task = Task { await fixture.store.repairObservedMetrics(receipts, ledger: fixture.ledger) }
            try await waitForFirstBatch(fixture)
            XCTAssertEqual(fixture.store.refreshStage, .updatingHealth)
            XCTAssertEqual(fixture.store.syncPresentation.stage, .updatingHealth)
            XCTAssertFalse(fixture.health.leafRequests.contains(.samples(fixture.types[3].identifier)))
            let before = await fixture.ledger.snapshot()
            XCTAssertTrue(before.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
            await gate.release()
            let changed = await task.value
            XCTAssertTrue(changed)
            XCTAssertTrue(fixture.store.syncPresentation.didPublish)
            XCTAssertFalse(fixture.store.syncPresentation.hadFailure)
            let after = await fixture.ledger.snapshot()
            XCTAssertTrue(after.entries.values.allSatisfy { !$0.currentPending && !$0.historyPending })
            XCTAssertTrue(fixture.health.leafRequests.contains(.samples(fixture.types[3].identifier)))
            let reload = BodyHealthDirtyWorkStore(file: fixture.file, domains: Set(fixture.kinds), context: fixture.store.currentObserverLedgerContext())
            let disk = await reload.snapshot()
            XCTAssertEqual(disk, after)
        }
    }

    func testQuietRepairDoesNotOwnBadgeAndForegroundPreemptsBeforeReadCompletes() async throws {
        try await withFixture { fixture in
            fixture.store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false)
            let gate = ReadGate()
            let admitted = expectation(description: "quiet read started")
            fixture.health.scriptSamples(for: fixture.types[1], .gated({
                XCTAssertEqual(HealthKitQueryPool.current, .background)
                admitted.fulfill()
                await gate.wait()
            }, then: .samples([])))
            let receipts = try await fixture.receipts()
            let quiet = Task { await fixture.store.repairObservedMetricsQuietly([receipts[1]], ledger: fixture.ledger) }
            await fulfillment(of: [admitted], timeout: 2)
            XCTAssertFalse(fixture.store.isRefreshing)
            XCTAssertNil(fixture.store.refreshStage)
            await fixture.store.withRefreshSlotHeld {
                XCTAssertTrue(fixture.store.isRefreshing)
                let replacement = await fixture.store.repairObservedMetricsQuietly([receipts[1]], ledger: fixture.ledger)
                XCTAssertFalse(replacement)
            }
            // The foreground owner completed while the old query still waits.
            await gate.release()
            let changed = await quiet.value
            XCTAssertFalse(changed)
            let after = await fixture.ledger.snapshot()
            XCTAssertEqual(after.entries["bodyMass"]?.historyPending, true)
            XCTAssertFalse(fixture.store.isRefreshing)
        }
    }

    func testQuietRepairPersistsOneDomainWithoutStartingVisibleRefresh() async throws {
        try await withFixture { fixture in
            fixture.store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false)
            let receipts = try await fixture.receipts()
            let changed = await fixture.store.repairObservedMetricsQuietly([receipts[1]], ledger: fixture.ledger)
            XCTAssertTrue(changed)
            XCTAssertFalse(fixture.store.isRefreshing)
            XCTAssertNil(fixture.store.refreshStage)
            let after = await fixture.ledger.snapshot()
            XCTAssertEqual(after.entries["bodyMass"]?.historyPending, false)
            XCTAssertEqual(after.entries["bodyFatPercentage"]?.historyPending, true)
        }
    }

    func testPreemptionAfterRawSaveLeavesHistoryPendingUntilDerivedSave() async throws {
        try await withFixture { fixture in
            fixture.store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false)
            var computes = 0
            fixture.store.beforeDashboardComputeCommit = {
                computes += 1
                if computes == 2 { fixture.store.retireBackgroundRefresh() }
            }
            defer { fixture.store.beforeDashboardComputeCommit = nil }
            let receipts = try await fixture.receipts()
            let changed = await fixture.store.repairObservedMetricsQuietly([receipts[1]], ledger: fixture.ledger)
            XCTAssertFalse(changed)
            let after = await fixture.ledger.snapshot()
            XCTAssertEqual(after.entries["bodyMass"]?.currentPending, false)
            XCTAssertEqual(after.entries["bodyMass"]?.historyPending, true)
        }
    }

    func testNewDeliveryDuringParallelReadsSurvivesWhileOtherReceiptsDrain() async throws {
        try await withFixture { fixture in
            let gate = ReadGate()
            for type in fixture.types { fixture.health.scriptSamples(for: type, .gated({ await gate.wait() }, then: .samples([]))) }
            let receipts = try await fixture.receipts()
            let task = Task { await fixture.store.repairObservedMetrics(receipts, ledger: fixture.ledger) }
            try await waitForFirstBatch(fixture)
            _ = await fixture.ledger.mark([.restingHeartRate], context: fixture.store.currentObserverLedgerContext())
            await gate.release()
            _ = await task.value
            let after = await fixture.ledger.snapshot()
            XCTAssertEqual(after.entries["restingHeartRate"]?.historyPending, true)
            for kind in fixture.kinds.dropFirst() { XCTAssertEqual(after.entries[kind.rawValue]?.historyPending, false) }
        }
    }

    func testFailedReadKeepsOnlyItsReceiptPending() async throws {
        try await withFixture { fixture in
            fixture.health.scriptSamples(for: fixture.types[1], .failure(nil))
            let receipts = try await fixture.receipts()
            _ = await fixture.store.repairObservedMetrics(receipts, ledger: fixture.ledger)
            XCTAssertTrue(fixture.store.syncPresentation.didPublish)
            XCTAssertTrue(fixture.store.syncPresentation.hadFailure)
            let after = await fixture.ledger.snapshot()
            for kind in fixture.kinds {
                XCTAssertEqual(after.entries[kind.rawValue]?.historyPending, kind == .bodyMass)
            }
        }
    }

    func testFailedSharedSourceDoesNotPreventIndependentSourceFromDraining() async throws {
        try await withFixture { fixture in
            fixture.health.scriptSources(for: fixture.types[1], .failure(nil))
            let receipts = try await fixture.receipts()
            _ = await fixture.store.repairObservedMetrics(receipts, ledger: fixture.ledger)
            let after = await fixture.ledger.snapshot()
            XCTAssertEqual(after.entries["restingHeartRate"]?.historyPending, false)
            for kind in fixture.kinds.dropFirst() { XCTAssertEqual(after.entries[kind.rawValue]?.historyPending, true) }
            XCTAssertFalse(fixture.health.leafRequests.contains(.samples(fixture.types[1].identifier)))
        }
    }

    func testCancellationRejectsLateBatchResultsAndDoesNotStartFourthMetric() async throws {
        try await withFixture { fixture in
            let gate = ReadGate()
            for type in fixture.types { fixture.health.scriptSamples(for: type, .gated({ await gate.wait() }, then: .samples([]))) }
            let receipts = try await fixture.receipts()
            let task = Task { await fixture.store.repairObservedMetrics(receipts, ledger: fixture.ledger) }
            try await waitForFirstBatch(fixture)
            task.cancel()
            let changed = await task.value
            XCTAssertFalse(changed)
            await gate.release()
            // Drain cooperative children after the owner has abandoned its fence.
            try await Task.sleep(for: .milliseconds(50))
            let after = await fixture.ledger.snapshot()
            XCTAssertTrue(after.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
            XCTAssertFalse(fixture.health.leafRequests.contains(.samples(fixture.types[3].identifier)))
            XCTAssertFalse(fixture.store.isRefreshing)
        }
    }

    func testSourceABAWhileReadsAreSuspendedRejectsEveryOldResult() async throws {
        let savedSelection = BodyHealthDataSourceSelection.load()
        defer { savedSelection.save() }
        try await withFixture { fixture in
            let gate = ReadGate()
            for type in fixture.types { fixture.health.scriptSamples(for: type, .gated({ await gate.wait() }, then: .samples([]))) }
            let receipts = try await fixture.receipts()
            let task = Task { await fixture.store.repairObservedMetrics(receipts, ledger: fixture.ledger) }
            try await waitForFirstBatch(fixture)
            let toB = Task { await fixture.store.updateHealthDataSource(for: .basics, option: .init(id: "source:B", name: "B")) }
            toB.cancel()
            await toB.value
            let toA = Task { await fixture.store.updateHealthDataSource(for: .basics, option: .allSources) }
            toA.cancel()
            await toA.value
            await gate.release()
            _ = await task.value
            let after = await fixture.ledger.snapshot()
            XCTAssertTrue(after.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
            XCTAssertFalse(fixture.health.leafRequests.contains(.samples(fixture.types[3].identifier)))
        }
    }
}
