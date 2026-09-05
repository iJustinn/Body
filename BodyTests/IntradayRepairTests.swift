import HealthKit
import XCTest
@testable import Body

final class IntradayRepairTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_500_000)

    private func series(_ age: TimeInterval = 7 * 86400, value: Double = 16) -> HealthTrendSeries {
        .init(points: [.init(date: now.addingTimeInterval(-age), value: value), .init(date: now, value: value)])
    }

    private func engine(_ fake: FakeHealthStore) -> HealthKitFetchEngine {
        HealthKitFetchEngine(permission: .init(enabledPermissions: [.respiratory]),
            healthDataSourceSelection: .defaultValue, secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false, healthStore: fake)
    }

    func testExplicitEmptyRepairDeletesBeyondOverlapWhilePassiveKeepsOlderSamples() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .respiratoryRate))
        fake.scriptSamples(for: type, .samples([]))
        fake.scriptSources(for: type, .sources([]))
        fake.scriptStatisticsCollection(for: type, .failure(nil))
        fake.scriptStatistics(for: type, .failure(nil))
        let engine = engine(fake)
        await engine.setHealthTrendAnchorDate(now)
        var existing = HealthDashboardSnapshot.empty
        existing.trends.respiratoryRateDaySamples = series()
        let passive = await engine.fetchHealthDashboardSnapshot(for: .respiratoryRate, calendar: .bodyGregorian, existing: existing)
        XCTAssertEqual(passive.snapshot.trends.respiratoryRateDaySamples.points, [existing.trends.respiratoryRateDaySamples.points[0]])
        let repair = await engine.fetchHealthDashboardSnapshot(for: .respiratoryRate, calendar: .bodyGregorian,
            existing: existing, reconcilesRetainedIntradayWindow: true)
        XCTAssertTrue(repair.snapshot.trends.respiratoryRateDaySamples.isEmpty)
        XCTAssertTrue(repair.authoritativeDaySampleSeries.contains(.respiratoryRateDaySamples))
        XCTAssertTrue(repair.hadQueryFailure, "An unrelated daily failure must not erase raw repair success")
    }

    func testFailedRepairRetainsCacheWithoutAuthoritativeWriteIntent() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .respiratoryRate))
        fake.scriptSamples(for: type, .failure(nil))
        fake.scriptSources(for: type, .sources([]))
        fake.scriptStatisticsCollection(for: type, .failure(nil))
        fake.scriptStatistics(for: type, .failure(nil))
        let engine = engine(fake)
        await engine.setHealthTrendAnchorDate(now)
        var existing = HealthDashboardSnapshot.empty
        existing.trends.respiratoryRateDaySamples = series()
        let result = await engine.fetchHealthDashboardSnapshot(for: .respiratoryRate, calendar: .bodyGregorian,
            existing: existing, reconcilesRetainedIntradayWindow: true)
        XCTAssertEqual(result.snapshot.trends.respiratoryRateDaySamples, existing.trends.respiratoryRateDaySamples)
        XCTAssertFalse(result.authoritativeDaySampleSeries.contains(.respiratoryRateDaySamples))
        XCTAssertTrue(result.hadQueryFailure)
    }

    func testLateWriteReplacesRetainedWindowWithoutKeepingDeletedSample() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .respiratoryRate))
        let date = now.addingTimeInterval(-10 * 86400)
        let sample = HKQuantitySample(type: type, quantity: .init(unit: .count().unitDivided(by: .minute()), doubleValue: 18), start: date, end: date)
        fake.scriptSamples(for: type, .samples([sample]))
        fake.scriptSources(for: type, .sources([]))
        fake.scriptStatisticsCollection(for: type, .failure(nil))
        fake.scriptStatistics(for: type, .failure(nil))
        let engine = engine(fake)
        await engine.setHealthTrendAnchorDate(now)
        var existing = HealthDashboardSnapshot.empty
        existing.trends.respiratoryRateDaySamples = series()
        let result = await engine.fetchHealthDashboardSnapshot(for: .respiratoryRate, calendar: .bodyGregorian,
            existing: existing, reconcilesRetainedIntradayWindow: true)
        XCTAssertEqual(result.snapshot.trends.respiratoryRateDaySamples.points.map(\.date), [date])
        XCTAssertEqual(result.snapshot.trends.respiratoryRateDaySamples.points.map(\.value), [18])
    }

    func testAuthoritativeEmptyPersistsWithoutErasingUnqueriedSeriesAndRetriesFailedWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntradayRepair.\(UUID().uuidString)")
        let file = directory.appendingPathComponent("dashboard.json")
        let name = "IntradayRepair.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        var initial = HealthDashboardSnapshot.empty
        initial.trends.respiratoryRateDaySamples = series()
        initial.trends.heartRateDaySamples = series(value: 60)
        XCTAssertTrue(HealthDashboardSnapshotStore.saveWithOutcome(initial, metadata: .init(), defaults: defaults, fileURL: file).sidecar.isDurable)
        var io = HealthDashboardSnapshotStore.PersistenceIO()
        io.write = { _, _ in throw NSError(domain: "RepairFailure", code: 1) }
        let failed = HealthDashboardSnapshotStore.saveWithOutcome(.empty, metadata: .init(),
            authoritativeDaySampleSeries: [.respiratoryRateDaySamples], defaults: defaults, fileURL: file, io: io)
        XCTAssertEqual(failed.sidecar, .failed)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadDaySamples(fileURL: file)?.respiratoryRateDaySamples, initial.trends.respiratoryRateDaySamples)
        let repaired = HealthDashboardSnapshotStore.saveWithOutcome(.empty, metadata: .init(),
            authoritativeDaySampleSeries: [.respiratoryRateDaySamples], defaults: defaults, fileURL: file)
        XCTAssertEqual(repaired.sidecar, .written)
        let reloaded = try XCTUnwrap(HealthDashboardSnapshotStore.loadDaySamples(fileURL: file))
        XCTAssertTrue(reloaded.respiratoryRateDaySamples.isEmpty)
        XCTAssertEqual(reloaded.heartRateDaySamples, initial.trends.heartRateDaySamples)
        let unqueried = HealthDashboardSnapshotStore.saveWithOutcome(.empty, metadata: .init(), defaults: defaults, fileURL: file)
        XCTAssertEqual(unqueried.sidecar, .preserved)
        XCTAssertEqual(HealthDashboardSnapshotStore.loadDaySamples(fileURL: file), reloaded)
    }

    func testCancelledIntradayReadDoesNotReturnAuthoritativeEmpty() async throws {
        let fake = FakeHealthStore()
        let type = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .respiratoryRate))
        fake.scriptSamples(for: type, .never)
        let engine = engine(fake)
        let task = Task { await engine.fetchIntradayDaySamples(for: .respiratoryRate, calendar: .bodyGregorian) }
        for _ in 0..<100 where fake.leafRequests.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(fake.leafRequests.contains(.samples(type.identifier)))
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    @MainActor
    func testOnlyAdmittedRepairMasksMemoizedHydrationAndAdvancesRawRevision() async {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = now
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart, .respiratory]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore(), calendarContext: { (calendar, now) })
        store.contextRefreshOverride = { _ in }
        var old = HealthTrendSnapshot.empty
        old.respiratoryRateDaySamples = series()
        old.heartRateDaySamples = series(value: 60)
        let memo = HealthTrendDaySampleSnapshot(trends: old)
        let revision = store.daySampleRevisions[.respiratoryRateDaySamples, default: 0]
        let accepted = await store.updateHealthDashboardSnapshot(summary: .empty, trends: .empty, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false,
            authoritativeDaySamples: [.respiratoryRateDaySamples])
        XCTAssertTrue(accepted)
        XCTAssertGreaterThan(store.daySampleRevisions[.respiratoryRateDaySamples, default: 0], revision, "An earlier lazy read must not overwrite this repair")
        XCTAssertTrue(store.excludingReconciledDaySamples(from: memo).respiratoryRateDaySamples.isEmpty)
        XCTAssertEqual(store.excludingReconciledDaySamples(from: memo).heartRateDaySamples, old.heartRateDaySamples)
        store.beforeDashboardComputeCommit = { calendar.timeZone = TimeZone(secondsFromGMT: 3600)! }
        let rejected = await store.updateHealthDashboardSnapshot(summary: .empty, trends: .empty, activityRingHistory: .empty,
            recomputesReadiness: false, recomputesStress: false, recomputesBodyRadar: false, persists: false,
            authoritativeDaySamples: [.heartRateDaySamples])
        XCTAssertFalse(rejected)
        XCTAssertEqual(store.excludingReconciledDaySamples(from: memo).heartRateDaySamples, old.heartRateDaySamples)
    }

    @MainActor
    func testConcurrentSamplePublicationsRejectOnlyCollidingSeriesIncludingRepeatRepairs() {
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart, .respiratory]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore())
        let captured = store.daySampleRevisions
        var stress = HealthTrendSnapshot.empty
        stress.stepsDaySamples = series(value: 100)
        stress.heartRateDaySamples = series(value: 60)
        XCTAssertEqual(store.publishDaySamples(from: stress,
            successfulSeries: [.stepsDaySamples, .heartRateDaySamples], capturedRevisions: captured),
            [.stepsDaySamples, .heartRateDaySamples])
        var oxygen = HealthTrendSnapshot.empty
        oxygen.oxygenSaturationDaySamples = series(value: 98)
        XCTAssertEqual(store.publishDaySamples(from: oxygen,
            successfulSeries: [.oxygenSaturationDaySamples], capturedRevisions: captured), [.oxygenSaturationDaySamples])
        XCTAssertEqual(store.healthTrends.heartRateDaySamples, stress.heartRateDaySamples)
        XCTAssertEqual(store.healthTrends.oxygenSaturationDaySamples, oxygen.oxygenSaturationDaySamples)

        // Radar won Steps; a multi-field stress result must still publish HRV.
        var partial = HealthTrendSnapshot.empty
        partial.stepsDaySamples = series(value: 10)
        partial.heartRateVariabilityDaySamples = series(value: 45)
        XCTAssertEqual(store.publishDaySamples(from: partial,
            successfulSeries: [.stepsDaySamples, .heartRateVariabilityDaySamples], capturedRevisions: captured),
            [.heartRateVariabilityDaySamples])
        XCTAssertEqual(store.healthTrends.stepsDaySamples, stress.stepsDaySamples)
        XCTAssertEqual(store.healthTrends.heartRateVariabilityDaySamples, partial.heartRateVariabilityDaySamples)

        // Authority already exists, but a later empty repair still fences old work.
        let beforeRepeat = store.daySampleRevisions
        XCTAssertEqual(store.publishDaySamples(from: .empty,
            successfulSeries: [.stepsDaySamples], capturedRevisions: beforeRepeat), [.stepsDaySamples])
        XCTAssertTrue(store.publishDaySamples(from: partial,
            successfulSeries: [.stepsDaySamples], capturedRevisions: beforeRepeat).isEmpty)
        XCTAssertTrue(store.healthTrends.stepsDaySamples.isEmpty)
    }

    func testSidecarPreservationDecodesOnlyWhenNeededAndReadsOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IntradayIO.\(UUID().uuidString)")
        let file = directory.appendingPathComponent("dashboard.json")
        let name = "IntradayIO.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: name) }
        var snapshot = HealthDashboardSnapshot.empty
        snapshot.trends.heartRateDaySamples = series(value: 60)
        _ = HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(), defaults: defaults, fileURL: file)
        var reads = 0
        var decodes = 0
        var io = HealthDashboardSnapshotStore.PersistenceIO()
        io.read = { url in
            if url == HealthDashboardSnapshotStore.daySamplesFileURL(alongside: file) { reads += 1 }
            return try Data(contentsOf: url)
        }
        io.decodeDaySamples = { data in
            decodes += 1
            return try JSONDecoder().decode(HealthTrendDaySampleSnapshot.self, from: data)
        }
        let fullAuthority = HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(),
            authoritativeDaySampleSeries: Set(HealthDaySampleSeries.allCases), defaults: defaults, fileURL: file, io: io)
        XCTAssertEqual(fullAuthority.sidecar, .unchanged)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(decodes, 0)
        reads = 0
        let unloaded = HealthDashboardSnapshotStore.saveWithOutcome(.empty, metadata: .init(),
            defaults: defaults, fileURL: file, io: io)
        XCTAssertEqual(unloaded.sidecar, .preserved)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(decodes, 1)
        reads = 0
        decodes = 0
        snapshot.trends.oxygenSaturationDaySamples = series(value: 98)
        snapshot.trends.heartRateDaySamples = .empty
        let partial = HealthDashboardSnapshotStore.saveWithOutcome(snapshot, metadata: .init(),
            defaults: defaults, fileURL: file, io: io)
        XCTAssertEqual(partial.sidecar, .written)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(decodes, 1)
        XCTAssertFalse(try XCTUnwrap(HealthDashboardSnapshotStore.loadDaySamples(fileURL: file)).heartRateDaySamples.isEmpty)
    }
}
