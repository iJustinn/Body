import XCTest
import HealthKit
@testable import Body

/// The Stress leaf reads raw RMSSD day samples, and a durable read stamps
/// `.stress` like every other observed kind, so a background wake inside the
/// 30 minute window skips it and derived history can settle behind it.
@MainActor
final class BodyStressValidationStampTests: XCTestCase {
    /// The store's injected calendar. Flipped once, from inside a gated read,
    /// to change the dashboard scope between the fetch and the save.
    private final class CalendarBox: @unchecked Sendable {
        var calendar = Calendar.bodyGregorian
        private var flipped = false

        @MainActor func flipZoneOnce() {
            guard !flipped else { return }
            flipped = true
            let zone = calendar.timeZone.identifier == "Pacific/Kiritimati" ? "Pacific/Pago_Pago" : "Pacific/Kiritimati"
            calendar.timeZone = TimeZone(identifier: zone)!
        }

        @MainActor func restore() { calendar = .bodyGregorian }
    }

    private struct Fixture {
        let store: HealthKitWorkoutStore
        let health: FakeHealthStore
        let ledger: BodyHealthDirtyWorkStore
        let envelopeDirectory: URL
    }

    private static func drainPersistQueue() async {
        let queue = HealthKitWorkoutStore.snapshotPersistQueue
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    /// The store saves the dashboard envelope at its real location. Park the
    /// host's copy and restore it afterwards.
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

    private func withFixture(domains: Set<HealthMetricKind> = [.stress], calendar box: CalendarBox = CalendarBox(),
                             _ body: (Fixture) async throws -> Void) async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let envelopeDirectory = try await isolateDashboardEnvelope()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let health = FakeHealthStore()
        let hrv = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        health.scriptSources(for: hrv, .sources([]))
        health.scriptSamples(for: hrv, .samples([]))
        health.scriptDailyQuantities(for: hrv, values: [])
        health.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))
        // No Recovery HRV, so Stress falls through to the heartbeat scan.
        if let recoveryHRV = HealthKitFetchEngine.recoveryHRVIdentifier.flatMap(HKQuantityType.quantityType(forIdentifier:)) {
            health.scriptSamples(for: recoveryHRV, .samples([]))
        }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil,
            calendarContext: { (box.calendar, Date()) })
        store.contextRefreshOverride = { _ in }
        let ledger = BodyHealthDirtyWorkStore(file: directory.appendingPathComponent("dirty.json"),
                                             domains: domains, context: store.currentObserverLedgerContext())
        var initial: [(HealthMetricKind, BodyHealthDirtyWorkStore.Receipt)] = []
        for kind in domains.sorted(by: { $0.rawValue < $1.rawValue }) {
            let receipt = await ledger.receipt(for: kind)
            initial.append((kind, try XCTUnwrap(receipt)))
        }
        // Source convergence retires the first pass before any data read.
        _ = await store.repairObservedMetrics(initial, ledger: ledger)
        _ = await ledger.synchronize(domains: domains, context: store.currentObserverLedgerContext())
        try await body(Fixture(store: store, health: health, ledger: ledger, envelopeDirectory: envelopeDirectory))
    }

    private func readStress(_ fixture: Fixture) async throws -> Bool {
        let receipt = await fixture.ledger.receipt(for: .stress)
        return await fixture.store.repairObservedMetrics([(.stress, try XCTUnwrap(receipt))], ledger: fixture.ledger)
    }

    private func persistedStressStamp() async -> HealthDashboardSnapshotStore.Freshness? {
        await Self.drainPersistQueue()
        return HealthDashboardSnapshotStore.loadWithContext()?.metadata.observedMetricValidation?[HealthMetricKind.stress.rawValue]
    }

    func testSuccessfulHeartbeatReadStampsStressForThirtyMinutesAndPersistsIt() async throws {
        try await withFixture { fixture in
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.stress))
            let changed = try await readStress(fixture)
            XCTAssertTrue(changed)
            // The envelope a relaunch restores carries the stamp under the current scope.
            let persisted = await persistedStressStamp()
            let stamp = try XCTUnwrap(persisted)
            XCTAssertEqual(stamp.contextSignature, fixture.store.currentDashboardCacheScope().signature)
            let interval = BodyHealthObservationPolicy.fallbackInterval
            XCTAssertFalse(fixture.store.observedMetricNeedsValidation(.stress, date: stamp.date))
            XCTAssertFalse(fixture.store.observedMetricNeedsValidation(.stress, date: stamp.date.addingTimeInterval(interval - 1)),
                           "just inside the 30 minute window")
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.stress, date: stamp.date.addingTimeInterval(interval)),
                          "stale at the 30 minute boundary")
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.stress, date: stamp.date.addingTimeInterval(3_600)),
                          "an hourly wake still revalidates Stress")
        }
    }

    func testFailedEnvelopeSaveLeavesNoStressStamp() async throws {
        try await withFixture { fixture in
            // A regular file where the envelope directory belongs makes the write fail.
            await Self.drainPersistQueue()
            try? FileManager.default.removeItem(at: fixture.envelopeDirectory)
            try FileManager.default.createDirectory(at: fixture.envelopeDirectory.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data().write(to: fixture.envelopeDirectory)
            let changed = try await readStress(fixture)
            XCTAssertFalse(changed)
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.stress))
            let pending = await fixture.ledger.snapshot()
            XCTAssertEqual(pending.entries["stress"]?.historyPending, true)
        }
    }

    func testScopeChangeBetweenFetchAndSaveLeavesNoStressStamp() async throws {
        let box = CalendarBox()
        try await withFixture(calendar: box) { fixture in
            // Every scope dimension a test can reach also feeds the refresh inputs, so
            // the inputs fence right after the fetch rejects this read first, before
            // anything is mutated. The contract checked here is only that no stamp
            // survives a scope change between fetch and save.
            fixture.health.scriptSamples(for: HKSeriesType.heartbeat(), .gated({
                await box.flipZoneOnce()
            }, then: .samples([])))
            let changed = try await readStress(fixture)
            XCTAssertFalse(changed)
            let stamp = await persistedStressStamp()
            XCTAssertNil(stamp)
            // Back in the scope the read started under, no stamp may validate it.
            box.restore()
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.stress))
        }
    }

    /// Derived history completion requires every stress input dependency in the
    /// ledger to be current and validated. Stress is its own dependency, and
    /// before the stamp existed a background history read of it could never
    /// settle: the read succeeded, then `completeObservedHistory` saw an
    /// unvalidated `.stress` and kept the obligation. (An HRV candidate would
    /// show the same gate, but the fake store cannot answer the HRV metric's
    /// statistics reads, so Stress is the candidate here.)
    func testBackgroundStressHistoryCompletesOnceItsOwnReadStampsIt() async throws {
        try await withFixture { fixture in
            let store = fixture.store
            let ledger = fixture.ledger
            // Current work done, history still owed: what a background wake finds.
            let receipt = await ledger.receipt(for: .stress)
            _ = await ledger.acknowledge(try XCTUnwrap(receipt), current: true, history: false)
            XCTAssertTrue(store.observedMetricNeedsValidation(.stress), "Never read, so never validated")

            BodyAppRuntime.setForegroundActive(false)
            let completed = await store.repairObservedHistory(.stress, ledger: ledger, lease: BodyBackgroundLease())
            XCTAssertTrue(completed, "The durable raw read stamps Stress, so its derived history settles behind it")
            XCTAssertFalse(store.observedMetricNeedsValidation(.stress))
            let persisted = await persistedStressStamp()
            XCTAssertNotNil(persisted, "A background stamp is durable too")
            let settled = await ledger.snapshot()
            XCTAssertEqual(settled.entries["stress"]?.historyPending, false)
            XCTAssertEqual(settled.entries["stress"]?.currentPending, false)
            XCTAssertFalse(store.isRefreshing)
        }
    }
}
