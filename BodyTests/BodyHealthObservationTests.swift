import XCTest
import HealthKit
@testable import Body

final class BodyHealthObservationTests: XCTestCase {
    @MainActor
    func testNotificationOnlyHeartbeatWakeDoesNotEnqueueStressHistoryRepair() throws {
        let hidden = BodyDashboardFetchSelection(summaryCards: .init(selectedCards: []), trendCards: .init(selectedCards: []))
        let registrations = BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.heart]), selection: hidden,
            includesCompanionConsumers: true, includesNotificationConsumers: true)
        let heartbeat = try XCTUnwrap(registrations.first { $0.type == HKSeriesType.heartbeat() })
        XCTAssertFalse(heartbeat.metrics.contains(.stress))
        XCTAssertEqual(heartbeat.frequency, .hourly)
    }

    @MainActor
    func testAppHolderCreatesOneStoreForUIAndHandlers() {
        var count = 0
        let runtime = BodyAppRuntime {
            count += 1
            return HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
                                         initialPermissionSelection: .init(enabledPermissions: []),
                                         workoutJournalFile: nil)
        }
        let ui = runtime.workoutStore
        let handler = runtime.workoutStore
        XCTAssertTrue(ui === handler)
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testNeutralLifecycleCanStayInactiveWithoutConstructingSharedRuntime() {
        let previous = BodyAppRuntime.isForegroundActive
        defer { BodyAppRuntime.setForegroundActive(previous) }
        BodyAppRuntime.setForegroundActive(false)
        XCTAssertFalse(BodyAppRuntime.isForegroundActive)
        BodyAppRuntime.setForegroundActive(true)
        XCTAssertTrue(BodyAppRuntime.isForegroundActive)
    }

    func testPolicyUsesReadSetAndEventFrequencyWithoutRequestingExtraPermissions() throws {
        let selected = BodyDashboardFetchSelection.defaultValue
        let empty = BodyHealthObservationPolicy.registrations(permissions: .init(enabledPermissions: []), selection: selected)
        XCTAssertTrue(empty.isEmpty)
        let permissions = BodyHealthPermissionSelection(enabledPermissions: [.workouts, .sleep, .heart])
        let entries = BodyHealthObservationPolicy.registrations(permissions: permissions, selection: selected)
        XCTAssertEqual(Set(entries.map { $0.type.identifier }).count, entries.count)
        let workout = try XCTUnwrap(entries.first { $0.scansWorkouts })
        XCTAssertEqual(workout.type, HKObjectType.workoutType())
        XCTAssertEqual(workout.frequency, .immediate)
        XCTAssertTrue(workout.metrics.isEmpty, "workouts keep their existing journal")
        XCTAssertTrue(entries.allSatisfy { BodyHealthReadTypes.readObjectTypes(for: permissions).contains($0.type) })
        let sleep = try XCTUnwrap(entries.first { $0.type == HKObjectType.categoryType(forIdentifier: .sleepAnalysis) })
        XCTAssertEqual(sleep.frequency, .immediate)
        XCTAssertTrue(entries.filter { $0.type is HKQuantityType }.allSatisfy { $0.frequency == .hourly })
        XCTAssertEqual(BodyHealthObservationPolicy.fallbackInterval, 1_800)
    }

    func testCompletionIsOneShotUnderConcurrentErrorAndShutdown() async {
        let completed = expectation(description: "completed once")
        completed.assertForOverFulfill = true
        let delivery = BodyHealthObserverDelivery(failed: true) { completed.fulfill() }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { delivery.complete() } }
        }
        await fulfillment(of: [completed], timeout: 1)
    }

    @MainActor
    func testCapturePrecedesCompletionAndEnableFailureRetriesWithoutDuplicateQuery() async throws {
        let fake = FakeHealthObserver()
        fake.enableResults = [false, true]
        var captures: [(String, Bool)] = []
        let coordinator = BodyHealthChangeObserver(observer: fake) { type, failed in
            captures.append((type, failed))
        }
        let registrations = BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts)
        await coordinator.configure(registrations)
        await coordinator.configure(registrations)
        XCTAssertEqual(fake.registrations.count, 1)
        XCTAssertEqual(fake.enables.count, 2)
        let id = try XCTUnwrap(fake.registrations.keys.first)
        let done = expectation(description: "delivery finished")
        fake.fire(id, failed: true) { done.fulfill() }
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(captures.count, 1)
        XCTAssertTrue(captures[0].1)
        await coordinator.configure([])
        XCTAssertEqual(fake.stopped, [id])
        let late = expectation(description: "late callback still acknowledged")
        fake.fire(id) { late.fulfill() }
        await fulfillment(of: [late], timeout: 1)
        XCTAssertEqual(captures.count, 1)
    }

    @MainActor
    func testDisableDuringSuspendedEnableIsReconciledAndOldDeliveryCannotHitReregisteredType() async throws {
        let fake = FakeHealthObserver()
        var captures = 0
        let coordinator = BodyHealthChangeObserver(observer: fake) { _, _ in captures += 1 }
        let registrations = BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts)
        fake.beforeEnable = { await coordinator.configure([]) }
        await coordinator.configure(registrations)
        XCTAssertEqual(fake.disables.count, 1)
        XCTAssertEqual(fake.stopped.count, 1)
        let old = try XCTUnwrap(fake.stopped.first)
        fake.beforeEnable = nil
        await coordinator.configure(registrations)
        let done = expectation(description: "old registration completed")
        fake.fire(old) { done.fulfill() }
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(captures, 0)
    }

    @MainActor
    func testFailedDisableRetriesOnNextLifecycleOpportunity() async {
        let fake = FakeHealthObserver()
        fake.disableResults = [false, true]
        let coordinator = BodyHealthChangeObserver(observer: fake) { _, _ in }
        await coordinator.configure(BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts))
        await coordinator.configure([])
        await coordinator.configure([])
        XCTAssertEqual(fake.disables.count, 2)
        XCTAssertEqual(fake.stopped.count, 1)
    }

    @MainActor
    func testReentrantIdenticalConfigurationDoesNotSpinOnEnableFailure() async {
        let fake = FakeHealthObserver()
        fake.enableResults = [false]
        let coordinator = BodyHealthChangeObserver(observer: fake) { _, _ in }
        let registrations = BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts)
        fake.beforeEnable = { await coordinator.configure(registrations) }
        await coordinator.configure(registrations)
        XCTAssertEqual(fake.enables.count, 1)
        await coordinator.configure(registrations)
        XCTAssertEqual(fake.enables.count, 2)
        XCTAssertEqual(fake.registrations.count, 1)
    }

    func testBackgroundEligibilityNeverPromptsAndDoesNotInterpretReadDenial() async {
        let fake = FakeHealthStore()
        let engine = HealthKitFetchEngine(permission: .init(enabledPermissions: [.workouts]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake, effortLedgerDirectoryURL: nil)
        for status in [HKAuthorizationRequestStatus.shouldRequest, .unknown, .unnecessary] {
            fake.scriptAuthorizationStatus(status)
            let result = await engine.backgroundReadEligibility(healthDataAvailable: true, protectedDataAvailable: true)
            XCTAssertEqual(result, status == .unnecessary ? .eligible : .deferred)
        }
        let reads = fake.authorizationCalls.statusReads
        let locked = await engine.backgroundReadEligibility(healthDataAvailable: true, protectedDataAvailable: false)
        XCTAssertEqual(locked, .deferred)
        let unavailable = await engine.backgroundReadEligibility(healthDataAvailable: false, protectedDataAvailable: true)
        XCTAssertEqual(unavailable, .unavailable)
        XCTAssertEqual(fake.authorizationCalls.statusReads, reads)
        XCTAssertEqual(fake.authorizationCalls.prompts, 0)
    }
    @MainActor
    func testAppObserverCapturesWorkoutDurablyWithoutHeadlessQueriesOrSpinner() async throws {
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(false)
        defer { BodyAppRuntime.setForegroundActive(foreground) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = directory.appendingPathComponent("journal.json")
        let health = FakeHealthStore()
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]),
            engineHealthStore: health, workoutJournalFile: journal)
        let fake = FakeHealthObserver()
        let coordinator = BodyHealthChangeCoordinator(store: store,
            file: directory.appendingPathComponent("dirty.json"), observing: fake, suppressesInitialDelivery: { false })
        await coordinator.configure()
        let identifier = try XCTUnwrap(fake.registrations.first { $0.value.type == HKObjectType.workoutType() }?.key)
        let completed = expectation(description: "captured and completed")
        fake.fire(identifier) { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertNotNil(WorkoutChangeJournalStore.load(file: journal)?.pendingObservation)
        XCTAssertTrue(health.leafRequests.isEmpty)
        XCTAssertTrue(health.executedQueries.isEmpty)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.refreshStage)
    }

    @MainActor
    func testBackgroundAdmissionDoesNotWaitForOrStealForegroundSlot() async {
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: []), workoutJournalFile: nil)
        await store.withRefreshSlotHeld {
            let admitted = await store.awaitRefreshSlotFree(background: true)
            XCTAssertFalse(admitted)
            XCTAssertTrue(store.isRefreshing)
        }
        let admitted = await store.awaitRefreshSlotFree(background: true)
        XCTAssertTrue(admitted)
    }

    func testHiddenPhoneMetricRemainsObservedForCompanionPayload() {
        let hidden = BodyDashboardFetchSelection(summaryCards: .init(selectedCards: []),
                                                 trendCards: .init(selectedCards: []))
        let permissions = BodyHealthPermissionSelection(enabledPermissions: [.steps])
        XCTAssertTrue(BodyHealthObservationPolicy.registrations(permissions: permissions, selection: hidden).isEmpty)
        let companion = BodyHealthObservationPolicy.registrations(permissions: permissions, selection: hidden,
                                                                  includesCompanionConsumers: true)
        XCTAssertEqual(companion.count, 1)
        XCTAssertEqual(companion.first?.metrics, [.steps])
        XCTAssertEqual(companion.first?.type.identifier, HKQuantityTypeIdentifier.stepCount.rawValue)
    }

    @MainActor
    func testForegroundInitializationIsCompletedWithoutDirtyingAndReregistrationResetsIt() async throws {
        let fake = FakeHealthObserver()
        var captures = 0
        let observer = BodyHealthChangeObserver(observer: fake, suppressesInitialDelivery: { true }) { _, _ in
            captures += 1
        }
        let registrations = BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts)
        await observer.configure(registrations)
        let firstID = try XCTUnwrap(fake.registrations.keys.first)
        let initial = expectation(description: "initial completed")
        fake.fire(firstID) { initial.fulfill() }
        await fulfillment(of: [initial], timeout: 1)
        XCTAssertEqual(captures, 0)
        await observer.configure(registrations)
        let change = expectation(description: "mutation completed")
        fake.fire(firstID) { change.fulfill() }
        await fulfillment(of: [change], timeout: 1)
        XCTAssertEqual(captures, 1)
        await observer.configure([])
        await observer.configure(registrations)
        let secondID = try XCTUnwrap(fake.registrations.keys.first { $0 != firstID })
        let restarted = expectation(description: "new registration initialization completed")
        fake.fire(secondID) { restarted.fulfill() }
        await fulfillment(of: [restarted], timeout: 1)
        XCTAssertEqual(captures, 1)
    }

    @MainActor
    func testFirstBackgroundDeliveryAndInitializationErrorAreCaptured() async throws {
        for suppress in [false, true] {
            let fake = FakeHealthObserver()
            var captured = false
            let observer = BodyHealthChangeObserver(observer: fake, suppressesInitialDelivery: { suppress }) { _, _ in
                captured = true
            }
            await observer.configure(BodyHealthObservationPolicy.registrations(
                permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts))
            let id = try XCTUnwrap(fake.registrations.keys.first)
            let completed = expectation(description: "first delivery retained")
            fake.fire(id, failed: suppress) { completed.fulfill() }
            await fulfillment(of: [completed], timeout: 1)
            XCTAssertTrue(captured)
        }
    }

    @MainActor
    func testDirtyAdmissionPreservesSuccessfulRefreshHistory() throws {
        let initialKey = HealthDashboardSnapshotStore.initialHealthDataLoadCompletedKey
        let initialValue = UserDefaults.standard.object(forKey: initialKey)
        defer { UserDefaults.standard.set(initialValue, forKey: initialKey) }
        let prior = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        defer {
            if let prior { HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(prior) }
            else { HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate() }
        }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: []), workoutJournalFile: nil)
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        store.markRefreshSucceeded(date: date, refreshedVitals: true, publishesWatch: false)
        store.stageCompletedDashboardFreshness(date: date)
        HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(date)
        let metadata = store.currentDashboardPersistenceMetadata()
        XCTAssertNotNil(metadata.freshness)
        store.invalidateObservedHealthChanges()
        XCTAssertEqual(store.lastSuccessfulRefreshDate, date)
        XCTAssertEqual(store.currentDashboardPersistenceMetadata().freshness, metadata.freshness)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate(), date)
        store.observedRepairDidSettle(pending: false)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, date)
    }

    @MainActor
    func testBackgroundRegistrationKeepsFirstDeliveryAfterForegroundActivation() async throws {
        let fake = FakeHealthObserver()
        var foreground = false
        var captures = 0
        let observer = BodyHealthChangeObserver(observer: fake, suppressesInitialDelivery: { foreground }) { _, _ in
            captures += 1
        }
        await observer.configure(BodyHealthObservationPolicy.registrations(
            permissions: .init(enabledPermissions: [.workouts]), selection: .defaultValue).filter(\.scansWorkouts))
        foreground = true
        let completed = expectation(description: "background wake retained across activation")
        fake.fire(try XCTUnwrap(fake.registrations.keys.first)) { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(captures, 1)
    }

    // MARK: Deferred sleep

    func testSleepWindowVitalsAreTheMainSessionVitalsOnly() {
        XCTAssertEqual(BodyHealthObservationPolicy.sleepWindowVitals, [
            HKQuantityTypeIdentifier.heartRate.rawValue, HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
            HKQuantityTypeIdentifier.respiratoryRate.rawValue, HKQuantityTypeIdentifier.oxygenSaturation.rawValue
        ])
        XCTAssertFalse(BodyHealthObservationPolicy.sleepWindowVitals.contains(HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue))
        XCTAssertEqual(BodyHealthObservationPolicy.sleepVitalsWindow, 6 * 3_600)
        XCTAssertEqual(BodyHealthObservationPolicy.sleepDeferralLimit, 24 * 3_600)
    }

    func testSleepOffPolicyDropsSleepDomainAndSynchronizeRemovesIt() async throws {
        let on = BodyHealthObservationPolicy.registrations(permissions: .init(enabledPermissions: [.heart, .sleep]),
            selection: .defaultValue, includesCompanionConsumers: true)
        let off = BodyHealthObservationPolicy.registrations(permissions: .init(enabledPermissions: [.heart]),
            selection: .defaultValue, includesCompanionConsumers: true)
        let heartRate = HKQuantityTypeIdentifier.heartRate.rawValue
        XCTAssertEqual(on.first { $0.type.identifier == heartRate }?.metrics.contains(.sleep), true)
        XCTAssertEqual(off.first { $0.type.identifier == heartRate }?.metrics, [.heartRate])
        XCTAssertTrue(off.allSatisfy { !$0.metrics.contains(.sleep) })
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dirty.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let context = BodyHealthObserverContext(scope: .init(primary: [:], secondary: [:], aggregation: "UTC", sleepGoal: 28_800))
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: Set(on.flatMap(\.metrics)), context: context)
        let before = await ledger.snapshot()
        XCTAssertNotNil(before.entries["sleep"])
        _ = await ledger.synchronize(domains: Set(off.flatMap(\.metrics)), context: context)
        let after = await ledger.snapshot()
        XCTAssertNil(after.entries["sleep"])
        XCTAssertNotNil(after.entries["heartRate"])
    }

    /// A background store and coordinator over a clean ledger, so a deferral is
    /// not folded into the first launch's pending work.
    @MainActor
    private func withSleepFixture(
        summary: HealthSummarySnapshot = .empty, permissions: Set<BodyHealthPermission> = [.heart, .sleep],
        _ body: (HealthKitWorkoutStore, BodyHealthChangeCoordinator, FakeHealthObserver, URL) async throws -> Void
    ) async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            BodyAppRuntime.setForegroundActive(foreground)
            restore()
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("dirty.json")
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [],
            initialHealthDashboardSnapshot: HealthDashboardSnapshot(summary: summary, trends: .empty, activityRingHistory: .empty),
            initialPermissionSelection: .init(enabledPermissions: permissions),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore(), workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let domains = Set(BodyHealthObservationPolicy.registrations(permissions: store.permissionSelection,
            selection: .load(), includesCompanionConsumers: true).flatMap(\.metrics))
        let seed = BodyHealthDirtyWorkStore(file: file, domains: domains, context: store.currentObserverLedgerContext())
        for kind in domains {
            let receipt = await seed.receipt(for: kind)
            let acknowledged = await seed.acknowledge(try XCTUnwrap(receipt), current: true, history: true)
            XCTAssertTrue(acknowledged)
        }
        let observer = FakeHealthObserver()
        let coordinator = BodyHealthChangeCoordinator(store: store, file: file, observing: observer,
                                                       suppressesInitialDelivery: { false })
        await coordinator.configure()
        try await body(store, coordinator, observer, file)
    }

    @MainActor
    private func deliver(_ identifier: HKQuantityTypeIdentifier, failed: Bool = false,
                         to observer: FakeHealthObserver) async throws {
        let id = try XCTUnwrap(observer.registrations.first { $0.value.type.identifier == identifier.rawValue }?.key)
        let captured = expectation(description: "\(identifier.rawValue) captured")
        observer.fire(id, failed: failed) { captured.fulfill() }
        await fulfillment(of: [captured], timeout: 3)
    }

    private func savedLedger(_ file: URL) throws -> BodyHealthDirtyWorkStore.Envelope {
        try JSONDecoder().decode(BodyHealthDirtyWorkStore.Envelope.self, from: Data(contentsOf: file))
    }

    @MainActor
    func testDaytimeHeartRateDefersSleepAndActivationSkipsItUntilAFullRefreshSettlesIt() async throws {
        try await withSleepFixture { store, coordinator, observer, file in
            XCTAssertFalse(store.sleepVitalsWindowIsOpen(), "no known night")
            try await deliver(.heartRate, to: observer)
            let saved = try savedLedger(file)
            XCTAssertEqual(saved.entries["heartRate"]?.currentPending, true)
            XCTAssertNil(saved.entries["heartRate"]?.deferredAt)
            let sleep = try XCTUnwrap(saved.entries["sleep"])
            XCTAssertTrue(sleep.currentPending)
            XCTAssertTrue(sleep.historyPending)
            XCTAssertNotNil(sleep.deferredAt)
            let receipts = await coordinator.captureReceipts()
            XCTAssertTrue(receipts.contains { $0.domain == "sleep" }, "a full refresh reads sleep anyway")
            // With heart rate settled, the deferred sleep is not pending work.
            await coordinator.acknowledgeCoverage(receipts, kinds: [.heartRate], history: true)
            store.invalidateObservedHealthChanges()
            await coordinator.prepareActivation()
            XCTAssertFalse(store.hasObservedHealthChanges)
            XCTAssertEqual(try savedLedger(file).entries["sleep"]?.deferredAt, sleep.deferredAt)
            await coordinator.acknowledgeCoverage(receipts, kinds: [.sleep], history: true)
            let settled = try XCTUnwrap(try savedLedger(file).entries["sleep"])
            XCTAssertFalse(settled.currentPending)
            XCTAssertNil(settled.deferredAt)
        }
    }

    @MainActor
    func testFailedDeliveryAndWristTemperatureMarkSleepNormallyAndPendingSleepOnlyGetsANewGeneration() async throws {
        try await withSleepFixture(permissions: [.heart, .sleep, .wristTemperature]) { _, _, observer, file in
            try await deliver(.heartRate, to: observer)
            XCTAssertNotNil(try savedLedger(file).entries["sleep"]?.deferredAt)
            try await deliver(.appleSleepingWristTemperature, to: observer)
            let wrist = try XCTUnwrap(try savedLedger(file).entries["sleep"])
            XCTAssertNil(wrist.deferredAt, "a nightly type reads sleep now")
            XCTAssertTrue(wrist.currentPending)
            try await deliver(.heartRate, to: observer)
            let bumped = try XCTUnwrap(try savedLedger(file).entries["sleep"])
            XCTAssertNil(bumped.deferredAt, "sleep already pending is read with this batch")
            XCTAssertGreaterThan(bumped.generation, wrist.generation)
        }
        try await withSleepFixture { _, _, observer, file in
            try await deliver(.heartRate, failed: true, to: observer)
            let failed = try XCTUnwrap(try savedLedger(file).entries["sleep"])
            XCTAssertNil(failed.deferredAt, "a failed delivery never defers")
            XCTAssertTrue(failed.currentPending)
        }
    }

    @MainActor
    func testHeartRateInsideTheNightWindowMarksSleepNormally() async throws {
        try await withSleepFixture(summary: sleepNightSummary(endingAgo: 3_600)) { store, _, observer, file in
            XCTAssertTrue(store.sleepVitalsWindowIsOpen())
            try await deliver(.heartRate, to: observer)
            let sleep = try XCTUnwrap(try savedLedger(file).entries["sleep"])
            XCTAssertTrue(sleep.currentPending)
            XCTAssertNil(sleep.deferredAt)
        }
    }

    @MainActor
    func testReadInFlightOnACleanLedgerCannotConsumeADeferralAndTheNewNightMakesItWork() async throws {
        try await withSleepFixture { store, coordinator, observer, file in
            // A full read starts on the clean ledger: it has no sleep receipt.
            let inFlight = await coordinator.captureReceipts()
            XCTAssertFalse(inFlight.contains { $0.domain == "sleep" })
            try await deliver(.heartRate, to: observer)
            await coordinator.acknowledgeCoverage(inFlight, kinds: [.heartRate, .sleep], history: true)
            let deferred = try XCTUnwrap(try savedLedger(file).entries["sleep"])
            XCTAssertTrue(deferred.currentPending)
            XCTAssertNotNil(deferred.deferredAt)
            let heartRate = await coordinator.captureReceipts()
            await coordinator.acknowledgeCoverage(heartRate, kinds: [.heartRate], history: true)
            XCTAssertFalse(store.hasObservedHealthChanges)
            // That read publishes the new night: the window opens and the deferral is ordinary work.
            let published = await store.updateHealthDashboardSnapshot(summary: sleepNightSummary(endingAgo: 3_600),
                trends: .empty, activityRingHistory: .empty, recomputesReadiness: false, recomputesStress: false,
                recomputesBodyRadar: false, persists: false)
            XCTAssertTrue(published)
            XCTAssertTrue(store.sleepVitalsWindowIsOpen())
            await coordinator.prepareActivation()
            XCTAssertTrue(store.hasObservedHealthChanges)
        }
    }

}
