import XCTest
import HealthKit
@testable import Body

/// A quiet repair that recomputes readiness from settled, validated inputs
/// stamps `readinessValidation` in the same durable save, so Siri can quote
/// when a readiness answer was last confirmed without a full refresh.
@MainActor
final class BodyReadinessValidationStampTests: XCTestCase {
    private struct Fixture {
        let store: HealthKitWorkoutStore
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

    private func withFixture(domains: Set<HealthMetricKind> = [.restingHeartRate],
                             _ body: (Fixture) async throws -> Void) async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let envelopeDirectory = try await isolateDashboardEnvelope()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let health = FakeHealthStore()
        let resting = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))
        health.scriptSources(for: resting, .sources([]))
        health.scriptDailyQuantities(for: resting, values: [])
        health.scriptSamples(for: resting, .samples([]))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let ledger = BodyHealthDirtyWorkStore(file: directory.appendingPathComponent("dirty.json"),
                                             domains: domains, context: store.currentObserverLedgerContext())
        let receipt = await ledger.receipt(for: .restingHeartRate)
        let initial = try XCTUnwrap(receipt)
        // Source convergence retires the first pass before any data read.
        _ = await store.repairObservedMetrics([(.restingHeartRate, initial)], ledger: ledger)
        _ = await ledger.synchronize(domains: domains, context: store.currentObserverLedgerContext())
        try await body(Fixture(store: store, ledger: ledger, envelopeDirectory: envelopeDirectory))
    }

    private func repairRestingHeartRate(_ fixture: Fixture) async throws -> Bool {
        let receipt = await fixture.ledger.receipt(for: .restingHeartRate)
        return await fixture.store.repairObservedMetrics([(.restingHeartRate, try XCTUnwrap(receipt))],
                                                         ledger: fixture.ledger)
    }

    private func persistedReadinessStamp() async -> HealthDashboardSnapshotStore.Freshness? {
        await Self.drainPersistQueue()
        return HealthDashboardSnapshotStore.loadWithContext()?.metadata.readinessValidation
    }

    func testSettledReadinessInputRepairPersistsTheReadinessStamp() async throws {
        try await withFixture { fixture in
            let before = Date()
            let changed = try await repairRestingHeartRate(fixture)
            XCTAssertTrue(changed)
            let persisted = await persistedReadinessStamp()
            let stamp = try XCTUnwrap(persisted)
            XCTAssertGreaterThanOrEqual(stamp.date, before.addingTimeInterval(-1))
            // Siri reads this stamp back through the bundle loader.
            XCTAssertEqual(BodySiriSnapshotBundle.loadCurrent().readinessValidatedAt, stamp.date)
        }
    }

    /// Sleep is a readiness input the ledger still has pending, so readiness
    /// is not settled after this repair and no stamp may be saved.
    func testUnsettledReadinessInputLeavesNoReadinessStamp() async throws {
        try await withFixture(domains: [.restingHeartRate, .sleep]) { fixture in
            let changed = try await repairRestingHeartRate(fixture)
            XCTAssertTrue(changed)
            XCTAssertTrue(fixture.store.observedMetricNeedsValidation(.sleep))
            let persisted = await persistedReadinessStamp()
            XCTAssertNil(persisted)
        }
    }
}
