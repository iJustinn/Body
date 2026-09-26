import XCTest
import HealthKit
@testable import Body

/// The repair-only continuation after a refresh (`startFollowupRepair`): a delivery
/// during the refresh and the refresh's leftovers coalesce into one silent repair
/// that never re-enters the resume gate, so a refresh that cannot stamp freshness
/// cannot schedule another full refresh by itself.
///
/// Every body mass read records who made it. A foreground repair pass is counted by
/// its publication fence, so reads are counted per pass rather than per query.
/// Unless a test says otherwise the first load is not complete, which keeps quiet
/// maintenance and the resume gate inert: the only way work continues is the follow-up.
@MainActor
final class BodyFollowupRepairTests: XCTestCase {
    @MainActor
    private final class ReadLog {
        struct Read {
            let background: Bool
            let silent: Bool
            let regular: Bool
            /// Retained so a later pass's fence can never reuse this one's identity.
            let pass: HealthDashboardPublicationToken?
        }
        private(set) var reads: [Read] = []
        /// Runs once, inside the first foreground silent read, before it resolves.
        var onFirstSilentRead: (@MainActor @Sendable () async -> Void)?

        /// Distinct foreground repair passes that read body mass.
        var silentPasses: Int {
            Set(reads.filter { !$0.background && $0.silent }.compactMap { $0.pass.map(ObjectIdentifier.init) }).count
        }
        var regularReads: Int { reads.filter { !$0.background && $0.regular }.count }
        var backgroundReads: Int { reads.filter(\.background).count }

        func record(_ read: Read) -> (@MainActor @Sendable () async -> Void)? {
            reads.append(read)
            guard read.silent, !read.background, let hook = onFirstSilentRead else { return nil }
            onFirstSilentRead = nil
            return hook
        }
    }

    @MainActor
    private final class Counter {
        var value = 0
    }

    @MainActor
    private struct Fixture {
        let store: HealthKitWorkoutStore
        let health: FakeHealthStore
        let observer: FakeHealthObserver
        let coordinator: BodyHealthChangeCoordinator
        let directory: URL
        let file: URL
        let mass: HKQuantityType
        let log: ReadLog
        let debounces: Counter

        func savedLedger() throws -> BodyHealthDirtyWorkStore.Envelope {
            try JSONDecoder().decode(BodyHealthDirtyWorkStore.Envelope.self, from: Data(contentsOf: file))
        }

        func massPending() throws -> Bool {
            try XCTUnwrap(savedLedger().entries[HealthMetricKind.bodyMass.rawValue]).currentPending
        }

        func massRegistration() throws -> UUID {
            try XCTUnwrap(observer.registrations.first { $0.value.type == mass }?.key)
        }

        /// Stands in for a full dashboard refresh: it takes receipts at the start and
        /// acknowledges its coverage at the end exactly as `refreshRecentMonths` does,
        /// then finishes through the real `finishRefresh`.
        func fullRefresh(covering kinds: Set<HealthMetricKind>, repairsLeftovers: Bool = true,
                         beforeAcknowledging: () -> Void = {}) async {
            await store.withRefreshSlotHeld(regularRefresh: true) {
                let receipts = await coordinator.captureReceipts()
                beforeAcknowledging()
                await coordinator.acknowledgeCoverage(receipts, kinds: kinds, history: false,
                                                      repairsLeftovers: repairsLeftovers && store.isRefreshing)
            }
        }
    }

    private func recording(_ log: ReadLog, store: HealthKitWorkoutStore,
                           then result: FakeHealthStore.Script) -> FakeHealthStore.Script {
        .gated({ [weak store] in
            let background = HealthKitQueryPool.current == .background
            let hook = await MainActor.run { () -> (@MainActor @Sendable () async -> Void)? in
                guard let store else { return nil }
                return log.record(.init(background: background, silent: store.isSilentRefresh,
                                        regular: store.isRegularRefresh,
                                        pass: store.maintenancePublicationToken))
            }
            await hook?()
        }, then: result)
    }

    private func withFixture(pending: Set<HealthMetricKind> = [], massFails: Bool = false,
                             initialLoadCompleted: Bool = false,
                             _ body: (Fixture) async throws -> Void) async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        if initialLoadCompleted { HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted() }
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
        // Same clean baseline as `BodyBackgroundRevalidationTests`: resolve source
        // discovery, then acknowledge every domain.
        let setup = BodyHealthDirtyWorkStore(file: file, domains: Set(kinds), context: store.currentObserverLedgerContext())
        var receipts: [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] = []
        for kind in kinds {
            let receipt = await setup.receipt(for: kind)
            receipts.append((kind, try XCTUnwrap(receipt)))
        }
        _ = await store.repairObservedMetrics(receipts, ledger: setup)
        _ = await setup.synchronize(domains: Set(kinds), context: store.currentObserverLedgerContext())
        for kind in kinds {
            let receipt = await setup.receipt(for: kind)
            let acknowledged = await setup.acknowledge(try XCTUnwrap(receipt), current: true, history: true)
            XCTAssertTrue(acknowledged)
        }
        // Obligations left by an earlier session; no delivery in this one.
        if !pending.isEmpty { _ = await setup.mark(pending, context: store.currentObserverLedgerContext()) }

        let log = ReadLog()
        let mass = types[1]
        health.scriptSamples(for: mass, recording(log, store: store, then: massFails ? .failure(nil) : .samples([])))
        let debounces = Counter()
        let observer = FakeHealthObserver()
        let coordinator = BodyHealthChangeCoordinator(store: store, file: file, observing: observer,
            suppressesInitialDelivery: { false }, foregroundSleep: { _ in debounces.value += 1 })
        store.healthChangeCoordinator = coordinator
        await coordinator.configure()
        let fixture = Fixture(store: store, health: health, observer: observer, coordinator: coordinator,
                              directory: directory, file: file, mass: mass, log: log, debounces: debounces)
        var failure: Error?
        do { try await body(fixture) } catch { failure = error }
        BodyAppRuntime.setForegroundActive(false)
        coordinator.enteredBackground()
        await store.awaitRetiredMaintenanceCompletion()
        store.healthChangeCoordinator = nil
        if let failure { throw failure }
    }

    /// Delivers a body mass change through the observer and waits until it is captured.
    private func deliver(_ fixture: Fixture) async throws {
        let id = try fixture.massRegistration()
        let captured = expectation(description: "delivery captured")
        fixture.observer.fire(id) { captured.fulfill() }
        await fulfillment(of: [captured], timeout: 3)
    }

    /// Waits until the slot is free and no continuation token is left. Every follow-up
    /// queues its token before the one it replaces settles, so an empty set means no
    /// further work was queued. Call it only once a token is known to be queued.
    private func waitUntilSettled(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<1_000 {
            if !fixture.store.isRefreshing, fixture.store.syncPresentation.pending.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The follow-up never settled", file: file, line: line)
    }

    /// The review's counterexample: a delivery drives a full refresh through the real
    /// debounce and resume gate. The refresh fails a leaf, so no freshness stamp lands
    /// and the delivered kind stays pending. Its finish runs exactly one repair, and no
    /// second full refresh starts without a new delivery.
    func testFailedFullRefreshFromADeliveryRunsOneRepairAndNoSecondRefresh() async throws {
        try await withFixture(massFails: true, initialLoadCompleted: true) { fixture in
            try await deliver(fixture)
            try await waitUntilSettled(fixture)
            XCTAssertEqual(fixture.debounces.value, 1, "Only the delivery went through the resume gate")
            XCTAssertGreaterThan(fixture.log.regularReads, 0, "The delivery ran a full refresh")
            XCTAssertEqual(fixture.store.fullRefreshCompletionCount, 1)
            XCTAssertNil(fixture.store.lastSuccessfulRefreshDate)
            XCTAssertEqual(fixture.log.silentPasses, 1)
            XCTAssertTrue(try fixture.massPending(), "Failed work stays pending for the next opportunity")
        }
    }

    /// A launch refresh leaves work it cannot claim with no delivery in flight: one
    /// repair settles it, and that repair's own finish starts nothing more.
    func testLeftoversAloneRunOneRepairThatSettlesThem() async throws {
        try await withFixture(pending: [.bodyMass]) { fixture in
            await fixture.fullRefresh(covering: [.bodyFatPercentage, .bodyMassIndex])
            XCTAssertEqual(fixture.store.syncPresentation.pending.count, 1, "One follow-up, queued before the session could settle")
            try await waitUntilSettled(fixture)
            XCTAssertEqual(fixture.log.silentPasses, 1)
            XCTAssertFalse(try fixture.massPending())
            XCTAssertEqual(fixture.debounces.value, 0)
            XCTAssertEqual(fixture.log.regularReads, 0)
        }
    }

    /// Without `repairsLeftovers` nothing is queued; with it, nothing is queued when
    /// the refresh claimed everything.
    func testNoFollowupWithoutLeftoverRepairOrWithoutLeftovers() async throws {
        try await withFixture(pending: [.bodyMass]) { fixture in
            await fixture.fullRefresh(covering: [], repairsLeftovers: false)
            XCTAssertTrue(fixture.store.syncPresentation.pending.isEmpty)
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(fixture.log.silentPasses, 0)
            XCTAssertTrue(try fixture.massPending())

            await fixture.fullRefresh(covering: [.bodyMass])
            XCTAssertFalse(try fixture.massPending())
            XCTAssertTrue(fixture.store.syncPresentation.pending.isEmpty)
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(fixture.log.silentPasses, 0)
            XCTAssertEqual(fixture.debounces.value, 0)
        }
    }

    /// A pending ring change alone is a leftover too. The fake cannot answer the ring
    /// read, so this checks that exactly one follow-up is queued and then stops it
    /// before admission instead of running the read.
    func testRingOnlyLeftoversQueueOneFollowup() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.activityRings]), engineHealthStore: FakeHealthStore(),
            workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let coordinator = BodyHealthChangeCoordinator(store: store, file: directory.appendingPathComponent("dirty.json"),
            observing: FakeHealthObserver(), suppressesInitialDelivery: { false })
        store.healthChangeCoordinator = coordinator
        defer { store.healthChangeCoordinator = nil }
        await coordinator.configure()
        await store.captureRingObservation()
        XCTAssertTrue(store.needsObservedRingRepair)
        await store.withRefreshSlotHeld(regularRefresh: true) {
            await coordinator.acknowledgeCoverage([], kinds: [], history: false, repairsLeftovers: store.isRefreshing)
        }
        XCTAssertEqual(store.syncPresentation.pending.count, 1)
        XCTAssertEqual(store.syncPresentation.phase, .syncing)
        BodyAppRuntime.setForegroundActive(false)
        for _ in 0..<100 where !store.syncPresentation.pending.isEmpty { await Task.yield() }
        XCTAssertTrue(store.syncPresentation.pending.isEmpty)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertTrue(store.needsObservedRingRepair)
    }

    /// A delivery while the follow-up reads: its newer generation rejects the old
    /// acknowledgement, the follow-up starts exactly one more, and then all is quiet.
    func testDeliveryDuringFollowupRunsOneMoreThenQuiet() async throws {
        try await withFixture(pending: [.bodyMass]) { fixture in
            let observer = fixture.observer
            let id = try fixture.massRegistration()
            fixture.log.onFirstSilentRead = {
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        observer.fire(id) { continuation.resume() }
                    }
                }
            }
            let before = try XCTUnwrap(fixture.savedLedger().entries[HealthMetricKind.bodyMass.rawValue]).generation
            await fixture.fullRefresh(covering: [])
            try await waitUntilSettled(fixture)
            XCTAssertNil(fixture.log.onFirstSilentRead, "The delivery landed during the follow-up")
            XCTAssertEqual(fixture.log.silentPasses, 2)
            let after = try XCTUnwrap(fixture.savedLedger().entries[HealthMetricKind.bodyMass.rawValue])
            XCTAssertGreaterThan(after.generation, before)
            XCTAssertFalse(after.currentPending)
            XCTAssertEqual(fixture.debounces.value, 1)
        }
    }

    /// Backgrounding before the follow-up is admitted runs nothing and keeps the
    /// request; the next opportunity (another refresh finishing) repairs.
    func testBackgroundBeforeAdmissionKeepsTheRequestForLater() async throws {
        try await withFixture(pending: [.bodyMass]) { fixture in
            await fixture.fullRefresh(covering: [])
            XCTAssertEqual(fixture.store.syncPresentation.pending.count, 1)
            BodyAppRuntime.setForegroundActive(false)
            fixture.coordinator.enteredBackground()
            for _ in 0..<50 { await Task.yield() }
            XCTAssertEqual(fixture.log.silentPasses, 0)
            XCTAssertTrue(try fixture.massPending())

            BodyAppRuntime.setForegroundActive(true)
            // Leftovers were cleared on backgrounding, so only the kept request can
            // start this follow-up.
            await fixture.store.withRefreshSlotHeld {}
            XCTAssertEqual(fixture.store.syncPresentation.pending.count, 1)
            try await waitUntilSettled(fixture)
            XCTAssertEqual(fixture.log.silentPasses, 1)
            XCTAssertFalse(try fixture.massPending())
            XCTAssertEqual(fixture.debounces.value, 0)
        }
    }

    /// A ledger write failure at the refresh's acknowledgement keeps the kind pending
    /// and arms the follow-up; that follow-up, failing the same way, runs once.
    func testLedgerWriteFailureAtAcknowledgementRunsTheFollowupOnce() async throws {
        try await withFixture(pending: [.bodyMass]) { fixture in
            let directory = fixture.directory.path
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }
            await fixture.fullRefresh(covering: [.bodyMass]) {
                try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
            }
            XCTAssertEqual(fixture.store.syncPresentation.pending.count, 1)
            try await waitUntilSettled(fixture)
            XCTAssertEqual(fixture.log.silentPasses, 1)
            XCTAssertTrue(try fixture.massPending())
            XCTAssertEqual(fixture.debounces.value, 0)
        }
    }

    /// A delivery before the refresh finished plus the refresh's own leftovers make one
    /// follow-up and one foreground pass, with no quiet or full refresh reads besides.
    func testDeliveryAndLeftoversCoalesceIntoOneRepair() async throws {
        try await withFixture { fixture in
            try await deliver(fixture)
            try await waitUntilSettled(fixture)
            XCTAssertTrue(try fixture.massPending())
            XCTAssertEqual(fixture.log.reads.count, 0, "The resume gate stays inert before the first load")

            await fixture.fullRefresh(covering: [])
            XCTAssertEqual(fixture.store.syncPresentation.pending.count, 1)
            try await waitUntilSettled(fixture)
            XCTAssertEqual(fixture.log.silentPasses, 1)
            XCTAssertEqual(fixture.log.backgroundReads, 0)
            XCTAssertEqual(fixture.log.regularReads, 0)
            XCTAssertTrue(fixture.log.reads.allSatisfy(\.silent))
            XCTAssertFalse(try fixture.massPending())
            XCTAssertEqual(fixture.debounces.value, 1)
        }
    }
}
