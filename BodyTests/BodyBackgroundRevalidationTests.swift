import XCTest
import HealthKit
@testable import Body

@MainActor
final class BodyBackgroundRevalidationTests: XCTestCase {
    private struct Fixture {
        let store: HealthKitWorkoutStore
        let health: FakeHealthStore
        let observer: FakeHealthObserver
        let coordinator: BodyHealthChangeCoordinator
        let file: URL
        let baseline: BodyHealthDirtyWorkStore.Envelope
        let types: [HKQuantityType]

        func savedLedger() throws -> BodyHealthDirtyWorkStore.Envelope {
            try JSONDecoder().decode(BodyHealthDirtyWorkStore.Envelope.self, from: Data(contentsOf: file))
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
        let kinds: [HealthMetricKind] = [.bodyFatPercentage, .bodyMass, .bodyMassIndex]
        let types = try [HKQuantityTypeIdentifier.bodyFatPercentage, .bodyMass, .bodyMassIndex].map {
            try XCTUnwrap(HKObjectType.quantityType(forIdentifier: $0))
        }
        for type in types {
            health.scriptSources(for: type, .sources([]))
            health.scriptSamples(for: type, .samples([]))
            health.scriptDailyQuantities(for: type, values: [])
        }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.basics]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: Set(kinds), context: store.currentObserverLedgerContext())
        var receipts: [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] = []
        for kind in kinds {
            let receipt = await ledger.receipt(for: kind)
            receipts.append((kind, try XCTUnwrap(receipt)))
        }
        // Resolve source discovery before seeding a clean, stale ledger. A genuine
        // source-context transition is intentionally still a repair obligation.
        _ = await store.repairObservedMetrics(receipts, ledger: ledger)
        _ = await ledger.synchronize(domains: Set(kinds), context: store.currentObserverLedgerContext())
        for kind in kinds {
            let receipt = await ledger.receipt(for: kind)
            let acknowledged = await ledger.acknowledge(try XCTUnwrap(receipt), current: true, history: true)
            XCTAssertTrue(acknowledged)
            XCTAssertTrue(store.observedMetricNeedsValidation(kind))
        }
        let baseline = await ledger.snapshot()
        let observer = FakeHealthObserver()
        let coordinator = BodyHealthChangeCoordinator(store: store, file: file, observing: observer,
                                                       suppressesInitialDelivery: { false })
        BodyAppRuntime.setForegroundActive(false)
        await coordinator.configure()
        let fixture = Fixture(store: store, health: health, observer: observer, coordinator: coordinator,
                              file: file, baseline: baseline, types: types)
        XCTAssertEqual(try fixture.savedLedger(), baseline)
        try await body(fixture)
    }

    func testSuccessfulFallbackReadsAndPersistsWithoutCreatingRepairWork() async throws {
        try await withFixture { fixture in
            let changed = await fixture.coordinator.runBackground(lease: BodyBackgroundLease())
            XCTAssertTrue(changed)
            XCTAssertTrue(fixture.types.allSatisfy { fixture.health.leafRequests.contains(.samples($0.identifier)) })
            XCTAssertFalse(fixture.store.observedMetricNeedsValidation(.bodyMass))
            XCTAssertEqual(try fixture.savedLedger(), fixture.baseline)
            let reload = BodyHealthDirtyWorkStore(file: fixture.file,
                domains: [.bodyFatPercentage, .bodyMass, .bodyMassIndex], context: fixture.store.currentObserverLedgerContext())
            let restarted = await reload.snapshot()
            XCTAssertEqual(restarted, fixture.baseline)
        }
    }

    func testAutomaticEffortWritePersistsRepairWithoutObserverOrVisibleRefresh() async throws {
        try await withFixture { fixture in
            await fixture.coordinator.captureAutomaticEffortWrite()
            let first = try fixture.savedLedger()
            XCTAssertEqual(first.entries["trainingLoad"]?.currentPending, true)
            XCTAssertEqual(first.entries["trainingLoad"]?.historyPending, true)
            await fixture.coordinator.captureAutomaticEffortWrite()
            let second = try fixture.savedLedger()
            XCTAssertGreaterThan(try XCTUnwrap(second.entries["trainingLoad"]?.generation),
                                 try XCTUnwrap(first.entries["trainingLoad"]?.generation))
            XCTAssertFalse(fixture.store.isRefreshing)
            XCTAssertEqual(fixture.health.authorizationCalls.prompts, 0)
        }
    }

    func testHistoryOnlyActivationReturnsWhileQuietReadIsBlocked() async throws {
        try await withFixture { fixture in
            var envelope = fixture.baseline
            envelope.entries["bodyMass"]?.historyPending = true
            try JSONEncoder().encode(envelope).write(to: fixture.file, options: .atomic)
            let coordinator = BodyHealthChangeCoordinator(store: fixture.store, file: fixture.file,
                observing: FakeHealthObserver(), suppressesInitialDelivery: { true })
            fixture.store.healthChangeCoordinator = coordinator
            fixture.store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false)
            BodyAppRuntime.setForegroundActive(true)
            let started = expectation(description: "quiet history read")
            let gate = AsyncGate()
            let mass = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .bodyMass))
            fixture.health.scriptSamples(for: mass, .gated({ started.fulfill(); await gate.wait() }, then: .samples([])))
            await fixture.store.syncWhenAppBecomesActive()
            XCTAssertFalse(fixture.store.isRefreshing)
            await fulfillment(of: [started], timeout: 2)
            XCTAssertTrue(try fixture.savedLedger().entries["bodyMass"]?.historyPending == true)
            coordinator.enteredBackground()
            await gate.release()
            fixture.store.healthChangeCoordinator = nil
        }
    }

    private actor AsyncGate {
        private var open = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { if !open { await withCheckedContinuation { continuation = $0 } } }
        func release() { open = true; continuation?.resume(); continuation = nil }
    }

    func testRepeatedDeferredFallbackDoesNotCreateForegroundHistory() async throws {
        try await withFixture { fixture in
            fixture.health.scriptAuthorizationStatus(.shouldRequest)
            for _ in 0..<2 {
                let changed = await fixture.coordinator.runBackground(lease: BodyBackgroundLease())
                XCTAssertFalse(changed)
                XCTAssertEqual(try fixture.savedLedger(), fixture.baseline)
            }
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.bodyMass))
            XCTAssertEqual(fixture.health.authorizationCalls.prompts, 0)
        }
    }

    func testFailedFallbackRemainsEligibleWithoutCreatingRepairWork() async throws {
        try await withFixture { fixture in
            for type in fixture.types { fixture.health.scriptSamples(for: type, .failure(nil)) }
            let changed = await fixture.coordinator.runBackground(lease: BodyBackgroundLease())
            XCTAssertFalse(changed)
            XCTAssertEqual(try fixture.savedLedger(), fixture.baseline)
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.bodyMass))
        }
    }

    func testDeliveryDuringFallbackCannotBeAcknowledgedByPeriodicRead() async throws {
        try await withFixture { fixture in
            let observerID = try XCTUnwrap(fixture.observer.registrations.first {
                $0.value.type == fixture.types[0]
            }?.key)
            let observer = fixture.observer
            fixture.health.scriptSamples(for: fixture.types[0], .gated({
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        observer.fire(observerID) { continuation.resume() }
                    }
                }
            }, then: .samples([])))
            _ = await fixture.coordinator.runBackground(lease: BodyBackgroundLease())
            let after = try fixture.savedLedger()
            let entry = try XCTUnwrap(after.entries[HealthMetricKind.bodyFatPercentage.rawValue])
            XCTAssertTrue(entry.currentPending)
            XCTAssertTrue(entry.historyPending)
            XCTAssertGreaterThan(entry.generation, fixture.baseline.entries[HealthMetricKind.bodyFatPercentage.rawValue]!.generation)
            XCTAssertEqual(after.entries[HealthMetricKind.bodyMass.rawValue], fixture.baseline.entries[HealthMetricKind.bodyMass.rawValue])
        }
    }

    func testExpiredLeaseDuringReadLeavesNoSyntheticRepairs() async throws {
        try await withFixture { fixture in
            let lease = BodyBackgroundLease()
            fixture.health.scriptSamples(for: fixture.types[0], .gated({ lease.invalidate() }, then: .samples([])))
            let changed = await fixture.coordinator.runBackground(lease: lease)
            XCTAssertFalse(changed)
            XCTAssertEqual(try fixture.savedLedger(), fixture.baseline)
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.bodyFatPercentage))
        }
    }

    func testBackgroundRepairCompletesRealHistoryObligationDurably() async throws {
        try await withFixture { fixture in
            let id = try XCTUnwrap(fixture.observer.registrations.first { $0.value.type == fixture.types[0] }?.key)
            let captured = expectation(description: "delivery durably captured")
            fixture.observer.fire(id) { captured.fulfill() }
            await fulfillment(of: [captured], timeout: 2)
            let changed = await fixture.coordinator.runBackground(lease: BodyBackgroundLease())
            XCTAssertTrue(changed)
            let after = try fixture.savedLedger()
            XCTAssertEqual(after.entries[HealthMetricKind.bodyFatPercentage.rawValue]?.currentPending, false)
            XCTAssertEqual(after.entries[HealthMetricKind.bodyFatPercentage.rawValue]?.historyPending, false)
            XCTAssertEqual(after.entries[HealthMetricKind.bodyMass.rawValue], fixture.baseline.entries[HealthMetricKind.bodyMass.rawValue])
            let reload = BodyHealthDirtyWorkStore(file: fixture.file,
                domains: [.bodyFatPercentage, .bodyMass, .bodyMassIndex], context: fixture.store.currentObserverLedgerContext())
            let restarted = await reload.snapshot()
            XCTAssertEqual(restarted, after)
            // A later periodic opportunity must not manufacture new history.
            _ = await fixture.coordinator.runBackground(lease: BodyBackgroundLease())
            XCTAssertEqual(try fixture.savedLedger(), after)
        }
    }

    func testHistoryOnlyBackgroundRepairCompletesFirstDomainBeforeNextExpires() async throws {
        try await withFixture { fixture in
            let ledger = BodyHealthDirtyWorkStore(file: fixture.file,
                domains: [.bodyFatPercentage, .bodyMass, .bodyMassIndex], context: fixture.store.currentObserverLedgerContext())
            for kind in [HealthMetricKind.bodyFatPercentage, .bodyMass] {
                _ = await ledger.mark([kind], context: fixture.store.currentObserverLedgerContext())
                let receipt = await ledger.receipt(for: kind)
                _ = await ledger.acknowledge(try XCTUnwrap(receipt), current: true, history: false)
            }
            let lease = BodyBackgroundLease()
            let first = await fixture.store.repairObservedHistory(.bodyFatPercentage, ledger: ledger, lease: lease)
            XCTAssertTrue(first)
            fixture.health.scriptSamples(for: fixture.types[1], .gated({ lease.invalidate() }, then: .samples([])))
            let second = await fixture.store.repairObservedHistory(.bodyMass, ledger: ledger, lease: lease)
            XCTAssertFalse(second)
            let saved = try fixture.savedLedger()
            XCTAssertEqual(saved.entries["bodyFatPercentage"]?.historyPending, false)
            XCTAssertEqual(saved.entries["bodyMass"]?.historyPending, true)
            XCTAssertFalse(fixture.store.isRefreshing)
        }
    }

    func testForegroundTakeoverDuringDerivedCommitKeepsHistoryPending() async throws {
        try await withFixture { fixture in
            let ledger = BodyHealthDirtyWorkStore(file: fixture.file,
                domains: [.bodyFatPercentage, .bodyMass, .bodyMassIndex], context: fixture.store.currentObserverLedgerContext())
            _ = await ledger.mark([.bodyMass], context: fixture.store.currentObserverLedgerContext())
            let receipt = await ledger.receipt(for: .bodyMass)
            _ = await ledger.acknowledge(try XCTUnwrap(receipt), current: true, history: false)
            fixture.store.beforeDashboardComputeCommit = {
                BodyAppRuntime.setForegroundActive(true)
                fixture.store.retireBackgroundRefresh()
            }
            defer { fixture.store.beforeDashboardComputeCommit = nil }
            let changed = await fixture.store.repairObservedHistory(.bodyMass, ledger: ledger, lease: BodyBackgroundLease())
            XCTAssertFalse(changed)
            XCTAssertEqual(try fixture.savedLedger().entries["bodyMass"]?.historyPending, true)
            XCTAssertFalse(fixture.store.isRefreshing)
        }
    }
}
