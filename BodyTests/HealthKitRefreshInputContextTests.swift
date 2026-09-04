import HealthKit
import XCTest
@testable import Body

final class HealthKitRefreshInputContextTests: XCTestCase {
    @MainActor
    func testUnchangedInputsRemainAdmissible() {
        let store = makeStore()
        let captured = store.captureRefreshInputs()
        XCTAssertTrue(store.mayApplyRefreshInputs(captured))
        XCTAssertEqual(captured, store.captureRefreshInputs())
    }

    @MainActor
    func testSourceDisplayNameDoesNotChangeInputIdentity() {
        let first = makeStore(source: BodyHealthDataSourceOption(id: "source:test", name: "Before"))
        let renamed = makeStore(source: BodyHealthDataSourceOption(id: "source:test", name: "After"))
        XCTAssertEqual(first.captureRefreshInputs(), renamed.captureRefreshInputs())
    }

    @MainActor
    func testCancelledSourceEditsStillRetireAnABARefresh() async {
        let savedSelection = BodyHealthDataSourceSelection.load()
        defer { savedSelection.save() }
        let sourceA = BodyHealthDataSourceOption(id: "source:A", name: "A")
        let sourceB = BodyHealthDataSourceOption(id: "source:B", name: "B")
        let store = makeStore(source: sourceA)
        let captured = store.captureRefreshInputs()

        // Cancellation suppresses the corrective refresh, not the synchronous
        // settings mutation. Both edits must still advance the admission fence.
        let toB = Task { await store.updateHealthDataSource(for: .heartRate, option: sourceB) }
        toB.cancel()
        await toB.value
        XCTAssertFalse(store.mayApplyRefreshInputs(captured))

        let toA = Task { await store.updateHealthDataSource(for: .heartRate, option: sourceA) }
        toA.cancel()
        await toA.value
        let current = store.captureRefreshInputs()
        XCTAssertEqual(captured.inputs, current.inputs)
        XCTAssertGreaterThan(current.revision, captured.revision)
        XCTAssertFalse(store.mayApplyRefreshInputs(captured))
    }

    @MainActor
    func testSleepGoalChangeRejectsFetchedResultWithoutAdvancingFreshness() async throws {
        let restoreLoadDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreLoadDefaults() }
        let defaults = UserDefaults.standard
        let key = BodyAppearancePreference.sleepDurationGoalMinutesKey
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        defaults.set(480, forKey: key)

        let store = makeStore()
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN))
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 60),
            start: Date(),
            end: Date()
        )
        fake.scriptSamples(for: type, .samples([sample]))
        let completed = await store.runRefreshWithDeadline(.seconds(5)) {
            let fetched = await BodyHealthQuantityFetch.latestQuantitySample(
                store: fake, quantityType: type, predicate: nil, onFailure: { _ in }
            )
            XCTAssertTrue(fetched.isSuccess)
            // Settings can run at this boundary between a completed HealthKit
            // read and its publication. The old request still owns the deadline
            // generation, but no longer owns the compute inputs.
            defaults.set(540, forKey: key)
            store.markRefreshSucceeded(
                date: Date(), refreshedVitals: true, publishesWatch: false,
                advancesSyncBadge: true
            )
        }

        XCTAssertTrue(completed, "An input change is not a deadline failure")
        XCTAssertEqual(fake.leafRequests, [.samples(type.identifier)])
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)
        XCTAssertFalse(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted())

        // A fresh request under the new goal can commit normally.
        let refreshedAt = Date()
        await store.runRefreshWithDeadline(.seconds(5)) {
            store.markRefreshSucceeded(date: refreshedAt, refreshedVitals: true, publishesWatch: false)
        }
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshedAt)
    }

    @MainActor
    private func makeStore(source: BodyHealthDataSourceOption = .allSources) -> HealthKitWorkoutStore {
        HealthKitWorkoutStore(
            initialMonthSnapshots: [],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: BodyHealthPermissionSelection(enabledPermissions: []),
            initialHealthDataSourceSelection: BodyHealthDataSourceSelection(
                selectedOptions: [.heartRate: source]
            ),
            initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false,
            initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore()
        )
    }
}
