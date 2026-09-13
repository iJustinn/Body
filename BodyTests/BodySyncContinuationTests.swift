import Observation
import XCTest
@testable import Body

@MainActor
final class BodySyncContinuationTests: XCTestCase {
    func testCoordinatorNoOpSettlesAfterDebounceWithoutStartingRefresh() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let wasForeground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            BodyAppRuntime.setForegroundActive(wasForeground)
            restore()
            try? FileManager.default.removeItem(at: directory)
        }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: []), engineHealthStore: FakeHealthStore(), workoutJournalFile: nil)
        let sleepStarted = expectation(description: "foreground debounce suspended")
        var resume: CheckedContinuation<Void, Never>?
        let coordinator = BodyHealthChangeCoordinator(store: store, file: directory.appendingPathComponent("dirty.json"),
            observing: FakeHealthObserver(), foregroundSleep: { _ in
                await withCheckedContinuation { continuation in
                    resume = continuation
                    sleepStarted.fulfill()
                }
            })
        await store.withRefreshSlotHeld {
            coordinator.contextDidChange()
            await fulfillment(of: [sleepStarted], timeout: 3)
        }
        XCTAssertFalse(store.isRefreshing)
        XCTAssertFalse(store.syncPresentation.pending.isEmpty)
        XCTAssertEqual(store.syncPresentation.phase, .syncing)
        let settled = expectation(description: "no-op admission releases observable token")
        withObservationTracking {
            _ = store.foregroundContinuationID
        } onChange: {
            settled.fulfill()
        }
        resume?.resume()
        await fulfillment(of: [settled], timeout: 3)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertTrue(store.syncPresentation.pending.isEmpty)
        XCTAssertNotNil(store.syncPresentation.nextDeadline)
        coordinator.enteredBackground()
    }

    func testBackgroundInvalidatesPendingAndOldCleanupCannotEraseNewSession() async {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let store = emptyHealthDataStore()
        var old: UUID!
        await store.withRefreshSlotHeld { old = store.queueForegroundContinuation() }
        store.cancelSyncPresentation()
        XCTAssertEqual(store.syncPresentation.phase, .hidden)
        await store.withRefreshSlotHeld {
            let current = store.queueForegroundContinuation()
            store.settleForegroundContinuation(old)
            XCTAssertEqual(store.foregroundContinuationID, current)
            XCTAssertEqual(store.syncPresentation.pending, [current])
            store.settleForegroundContinuation(current)
        }
    }
}
