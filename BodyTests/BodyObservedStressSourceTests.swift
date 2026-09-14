import XCTest
import HealthKit
@testable import Body

@MainActor
final class BodyObservedStressSourceTests: XCTestCase {
    func testStressResolvesHRVBeforeReadingAndOnlyAcknowledgesSuccessfulSamples() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let health = FakeHealthStore()
        let hrv = try XCTUnwrap(HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        health.scriptSources(for: hrv, .sources([]))
        health.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        let ledger = BodyHealthDirtyWorkStore(file: directory.appendingPathComponent("dirty.json"),
                                             domains: [.stress], context: store.currentObserverLedgerContext())
        let original = await ledger.receipt(for: .stress)
        _ = await store.repairObservedMetrics([(.stress, try XCTUnwrap(original))], ledger: ledger)
        XCTAssertTrue(health.leafRequests.contains(.sources(hrv.identifier)))
        XCTAssertFalse(health.leafRequests.contains(.samples(HKSeriesType.heartbeat().identifier)),
                       "Source convergence retires the old context before its data can publish")
        _ = await ledger.synchronize(domains: [.stress], context: store.currentObserverLedgerContext())
        let settled = await ledger.receipt(for: .stress)
        health.scriptSamples(for: HKSeriesType.heartbeat(), .failure(nil))
        let failed = await store.repairObservedMetrics([(.stress, try XCTUnwrap(settled))], ledger: ledger)
        XCTAssertFalse(failed)
        let pending = await ledger.snapshot()
        XCTAssertEqual(pending.entries["stress"]?.historyPending, true)
        health.scriptSamples(for: HKSeriesType.heartbeat(), .samples([]))
        let changed = await store.repairObservedMetrics([(.stress, try XCTUnwrap(settled))], ledger: ledger)
        XCTAssertTrue(changed)
        XCTAssertTrue(health.leafRequests.contains(.samples(HKSeriesType.heartbeat().identifier)))
        let complete = await ledger.snapshot()
        XCTAssertEqual(complete.entries["stress"]?.historyPending, false)
    }
}
