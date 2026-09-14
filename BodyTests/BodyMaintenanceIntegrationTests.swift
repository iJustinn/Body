import XCTest
import HealthKit
@testable import Body

@MainActor
final class BodyMaintenanceIntegrationTests: XCTestCase {
    private actor Gate {
        private var open = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async { if !open { await withCheckedContinuation { continuation = $0 } } }
        func release() { open = true; continuation?.resume(); continuation = nil }
    }

    func testAutomaticJournalAndQueuedRecordOwnerDoNotHoldForegroundRefresh() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let health = FakeHealthStore()
        health.scriptSamples(for: HKObjectType.workoutType(), .samples([]))
        let began = expectation(description: "automatic journal page admitted")
        let gate = Gate()
        health.pauseWorkoutChanges {
            XCTAssertEqual(HealthKitQueryPool.current, .background)
            began.fulfill()
            await gate.wait()
        }
        health.scriptWorkoutChanges([.success(.init(workouts: [], deletedIDs: [], anchor: Data([1])))])
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.workouts]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: directory.appendingPathComponent("journal.json"))
        store.contextRefreshOverride = { _ in }
        await store.requestAuthorizationAndRefresh(intent: .passiveResume)
        await fulfillment(of: [began], timeout: 3)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.refreshStage)
        let badge = store.syncBadgeSuccessCount
        await store.withRefreshSlotHeld { XCTAssertTrue(store.isRefreshing) }
        // Queued cancellation must clear the real retained record handle even
        // though its operation body was never entered.
        await store.cancelRecordBaselineBackfill()
        XCTAssertNil(store.recordBackfillTask)
        XCTAssertEqual(store.syncBadgeSuccessCount, badge)
        BodyAppRuntime.setForegroundActive(false)
        store.retireBackgroundRefresh()
        await gate.release()
        await store.awaitRetiredMaintenanceCompletion()
        await store.cancelRecordBaselineBackfill()
    }
}
