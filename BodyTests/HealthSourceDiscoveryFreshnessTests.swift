import XCTest
import HealthKit
@testable import Body

final class HealthSourceDiscoveryFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func engine(_ fake: FakeHealthStore, permissions: Set<BodyHealthPermission> = [.steps]) -> HealthKitFetchEngine {
        HealthKitFetchEngine(permission: .init(enabledPermissions: permissions), healthDataSourceSelection: .defaultValue,
                            secondaryHealthDataSourceSelection: .defaultValue, combinesHealthDataSourcesByName: false,
                            healthStore: fake)
    }

    func testForceDirtyExpiryAndClockRollbackRequeryWithUnchangedPreferences() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSources(for: type, .sources([]))
        let engine = engine(fake)
        let first = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now)
        XCTAssertNotNil(first)
        let cached = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now.addingTimeInterval(60))
        XCTAssertNil(cached)
        XCTAssertEqual(fake.leafRequests.count, 1)
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, force: true, now: now.addingTimeInterval(60))
        XCTAssertEqual(fake.leafRequests.count, 2)
        await engine.markHealthSourcesDirty(for: [.steps])
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now.addingTimeInterval(120))
        XCTAssertEqual(fake.leafRequests.count, 3)
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now.addingTimeInterval(120 + 86_400))
        XCTAssertEqual(fake.leafRequests.count, 4)
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now)
        XCTAssertEqual(fake.leafRequests.count, 5)
    }

    func testPartialFailurePreservesMapsAndRemainsDirty() async throws {
        let fake = FakeHealthStore()
        let steps = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        let oxygen = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .oxygenSaturation))
        fake.scriptSources(for: steps, .sources([]))
        fake.scriptSources(for: oxygen, .sources([]))
        let engine = engine(fake, permissions: [.steps, .bloodOxygen])
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now)
        let prior = await engine.cacheSourceIdentities()
        fake.scriptSources(for: oxygen, .failure(nil))
        let partial = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, force: true, now: now)
        XCTAssertNotNil(partial?[.steps])
        XCTAssertNil(partial?[.oxygenSaturation])
        let after = await engine.cacheSourceIdentities()
        XCTAssertEqual(prior, after)
        let dates = await engine.healthSourceDiscoveryDates
        XCTAssertNil(dates[.oxygenSaturation])
        let retry = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now)
        XCTAssertNotNil(retry)
        fake.scriptSources(for: oxygen, .sources([]))
        _ = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now)
        let expected = await engine.watchComputeExpectedSourceIDs()
        XCTAssertEqual(expected[HealthMetricKind.oxygenSaturation.rawValue], [], "known empty clears prior watch expectations")
    }

    func testDirtySignalDuringDiscoveryRejectsLateInstallAndRetries() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSources(for: type, .delay(.milliseconds(200), then: .sources([])))
        let engine = engine(fake)
        let task = Task { await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now) }
        for _ in 0..<100 where fake.leafRequests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(fake.leafRequests.isEmpty)
        await engine.markHealthSourcesDirty(for: [.steps])
        let result = await task.value
        XCTAssertNil(result)
        let identities = await engine.cacheSourceIdentities()
        XCTAssertTrue(identities.isEmpty)
        fake.scriptSources(for: type, .sources([]))
        let retry = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now)
        XCTAssertNotNil(retry)
    }

    func testFocusedDiscoveryAlsoExpiresAndCannotLatchFullDiscovery() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        fake.scriptSources(for: type, .sources([]))
        let engine = engine(fake)
        await engine.discoverHealthSources(for: [.steps], now: now)
        await engine.discoverHealthSources(for: [.steps], now: now.addingTimeInterval(60))
        XCTAssertEqual(fake.leafRequests.count, 1)
        await engine.discoverHealthSources(for: [.steps], now: now.addingTimeInterval(86_400))
        XCTAssertEqual(fake.leafRequests.count, 2)
        let full = await engine.fetchHealthDataSourceOptions(calendar: .bodyGregorian, now: now.addingTimeInterval(86_400))
        XCTAssertNotNil(full)
    }

    @MainActor
    func testObservedRepairAcceptsSourcesDiscoveredAfterItsAdmissionDate() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let fake = FakeHealthStore()
        let resting = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))
        fake.scriptSources(for: resting, .sources([]))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: fake, workoutJournalFile: nil)
        // Deliberately earlier than discovery's wall-clock default. A successful
        // discovery must not look like clock rollback to this same repair.
        fake.scriptStatistics(for: resting, .failure(nil))
        fake.scriptStatisticsCollection(for: resting, .failure(nil))
        fake.scriptSamples(for: resting, .failure(nil))
        await store.withRefreshSlotHeld {
            _ = await store.performHealthMetricRefresh(.restingHeartRate, date: self.now, calendar: .bodyGregorian, observed: true)
        }
        XCTAssertTrue(fake.leafRequests.contains(.statisticsCollection(resting.identifier)),
                      "Successful discovery must admit metric reads")
    }

    func testStableCombinedSelectionResolvesAddedAndRemovedMembers() {
        struct Source: Equatable { let bundle: String; let name: String }
        let a = Source(bundle: "app.a", name: "Tracker"), b = Source(bundle: "app.b", name: "Tracker")
        let selectedID = BodyHealthDataSourceOption.combinedSourceID(for: "Tracker")
        func map(_ sources: [Source]) -> [String: [Source]] {
            BodyHealthSourceResolver.sourceOptionsAndMap(
                from: sources, combinesSourcesByName: true, bundleIdentifier: { $0.bundle },
                identityName: { $0.name }, displayName: { $0.name }
            ).sourcesByID
        }
        XCTAssertEqual(map([a])[selectedID], [a])
        XCTAssertEqual(map([a, b])[selectedID], [a, b])
        XCTAssertEqual(map([b])[selectedID], [b])
        XCTAssertNil(map([])[selectedID])
    }

    @MainActor
    func testObservedBodyMeasurementsDiscoverSharedBasicsSourceBeforeReading() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        for kind in [HealthMetricKind.bodyMass, .bodyFatPercentage, .bodyMassIndex] {
            let fake = FakeHealthStore()
            let types = try [HKQuantityTypeIdentifier.bodyMass, .bodyFatPercentage, .bodyMassIndex].map {
                try XCTUnwrap(HKObjectType.quantityType(forIdentifier: $0))
            }
            for type in types {
                fake.scriptSources(for: type, .sources([]))
                fake.scriptSamples(for: type, .failure(nil))
                fake.scriptStatisticsCollection(for: type, .failure(nil))
            }
            let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
                initialPermissionSelection: .init(enabledPermissions: [.basics]),
                initialHealthDataSourceSelection: .init(selectedOptions: [.basics: .init(id: "source:scale", name: "Scale")]),
                initialSecondaryHealthDataSourceSelection: .defaultValue,
                initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
                engineHealthStore: fake, workoutJournalFile: nil)
            await store.withRefreshSlotHeld {
                _ = await store.performHealthMetricRefresh(kind, date: self.now, calendar: .bodyGregorian, observed: true)
            }
            for type in types {
                XCTAssertTrue(fake.leafRequests.contains(.sources(type.identifier)), "\(kind) needs the shared Basics source map")
            }
            let descriptor = try XCTUnwrap(HealthMetricQueryDescriptor.descriptor(for: kind))
            XCTAssertTrue(fake.leafRequests.contains(.samples(descriptor.quantityType.rawValue)),
                          "Resolved Basics selection must admit the body-measurement query")
        }
    }
}
