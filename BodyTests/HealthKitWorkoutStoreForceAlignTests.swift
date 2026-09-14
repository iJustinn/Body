import XCTest
@testable import Body

@MainActor
final class HealthKitWorkoutStoreForceAlignTests: XCTestCase {
    func testForceAlignClearsEveryPerMetricOverrideAndKeepsDefaults() async {
        let savedPrimary = BodyHealthDataSourceSelection.load()
        let savedSecondary = BodyHealthSecondaryDataSourceSelection.load()
        defer {
            savedPrimary.save()
            savedSecondary.save()
        }

        let watch = BodyHealthDataSourceOption(id: "watch", name: "Watch")
        let strap = BodyHealthDataSourceOption(id: "strap", name: "Strap")
        let phone = BodyHealthDataSourceOption(id: "phone", name: "Phone")
        let primary = BodyHealthDataSourceSelection(defaultOption: watch, selectedOptions: [.heartRate: strap, .sleep: phone])
        let secondary = BodyHealthSecondaryDataSourceSelection(defaultOption: strap, selectedOptions: [.heartRate: phone])
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.basics]),
            initialHealthDataSourceSelection: primary, initialSecondaryHealthDataSourceSelection: secondary,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore(), workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }

        await store.alignHealthDataSourcesToDefaults()

        XCTAssertEqual(store.healthDataSourceSelection.defaultOption, watch)
        XCTAssertTrue(store.healthDataSourceSelection.selectedOptions.isEmpty)
        XCTAssertEqual(store.healthDataSourceSelection.option(for: .heartRate), watch)
        XCTAssertEqual(store.secondaryHealthDataSourceSelection.defaultOption, strap)
        XCTAssertTrue(store.secondaryHealthDataSourceSelection.selectedOptions.isEmpty)
        XCTAssertEqual(store.secondaryHealthDataSourceSelection.option(for: .heartRate), strap)
        XCTAssertTrue(BodyHealthDataSourceSelection.load().selectedOptions.isEmpty)
        XCTAssertTrue(BodyHealthSecondaryDataSourceSelection.load().selectedOptions.isEmpty)
    }
}
