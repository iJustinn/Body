import XCTest
import os
import HealthKit
@testable import Body

final class BodyObserverLedgerContextTests: XCTestCase {
    private func scope() -> HealthDashboardCacheScope {
        .init(primary: ["sleep": .init(request: "enabled|stages-included", members: ["A"])],
              secondary: ["sleep": .init(request: "comparison", members: ["B"])],
              aggregation: "gregorian|America/New_York|v1", sleepGoal: 28_800,
              summaryDayStart: Date(timeIntervalSince1970: 1_789_171_200))
    }

    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dirty.json")
    }

    private func writeLegacy(_ scope: HealthDashboardCacheScope, to file: URL) throws -> BodyHealthDirtyWorkStore.Envelope {
        let old = BodyHealthDirtyWorkStore.Envelope(schema: 1, revision: 7, entries: [
            "sleep": .init(generation: 7, context: scope.signature, currentPending: false, historyPending: true),
            "steps": .init(generation: 4, context: scope.signature, currentPending: false, historyPending: false)
        ])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: file, options: .atomic)
        return old
    }

    func testObserverIdentityExcludesDayAndComputeButRetainsFetchPreferences() {
        let old = scope()
        let observer = BodyHealthObserverContext(scope: old)
        var compute = old
        compute.summaryDayStart = old.summaryDayStart?.addingTimeInterval(20)
        compute.sleepGoal += 3_600
        compute.computeVersion += 1
        XCTAssertEqual(observer, BodyHealthObserverContext(scope: compute))
        XCTAssertNotEqual(old.signature, compute.signature)
        XCTAssertNil(BodyHealthObserverContext(signature: old.signature))
        XCTAssertNil(HealthDashboardCacheScope(signature: observer.signature))
        XCTAssertEqual(BodyHealthObserverContext(signature: observer.signature), observer)
        XCTAssertNil(BodyHealthObserverContext(signature: observer.signature.replacingOccurrences(of: "observer-v1:", with: "observer-v2:")))
        for change in 0..<5 {
            var next = old
            switch change {
            case 0: next.primary["sleep"]?.members = ["C"]
            case 1: next.primary["sleep"]?.members = nil
            case 2: next.secondary["sleep"]?.members = ["C"]
            case 3: next.aggregation = "gregorian|UTC|v1"
            default: next.primary["sleep"]?.request = "enabled|stages-excluded"
            }
            XCTAssertNotEqual(observer, BodyHealthObserverContext(scope: next))
        }
    }

    func testLegacyMigrationPreservesFlagsAndGenerationsAndRejectsOldReceipts() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let oldScope = scope()
        let old = try writeLegacy(oldScope, to: file)
        var today = oldScope
        today.summaryDayStart = oldScope.summaryDayStart?.addingTimeInterval(86_400)
        today.sleepGoal += 3_600
        let context = BodyHealthObserverContext(scope: today)
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: context)
        let migrated = await ledger.snapshot()
        XCTAssertEqual(migrated.schema, 2)
        XCTAssertNotEqual(migrated.resetID, old.resetID)
        XCTAssertEqual(migrated.revision, old.revision)
        for (kind, entry) in old.entries {
            XCTAssertEqual(migrated.entries[kind]?.generation, entry.generation)
            XCTAssertEqual(migrated.entries[kind]?.currentPending, entry.currentPending)
            XCTAssertEqual(migrated.entries[kind]?.historyPending, entry.historyPending)
            XCTAssertEqual(migrated.entries[kind]?.context, context.signature)
        }
        let durable = await ledger.flush()
        XCTAssertTrue(durable)
        let oldReceipt = BodyHealthDirtyWorkStore.Receipt(resetID: old.resetID, domain: "sleep", generation: 7,
                                                         context: BodyHealthObserverContext(scope: oldScope))
        let accepted = await ledger.acknowledge(oldReceipt, current: true, history: true)
        XCTAssertFalse(accepted)
        let bytes = try Data(contentsOf: file)
        let reload = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: context)
        let restarted = await reload.snapshot()
        XCTAssertEqual(restarted, migrated)
        _ = await reload.synchronize(domains: [.sleep, .steps], context: context)
        XCTAssertEqual(try Data(contentsOf: file), bytes, "Migration must not recur on every launch")
    }

    func testMigrationOnlyKeepsCleanFlagsForMatchingRecognizedProvenance() async throws {
        for corrupt in [false, true] {
            let file = file()
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            var old = try writeLegacy(scope(), to: file)
            if corrupt { old.entries["steps"]?.context = "unknown provenance" }
            else {
                var different = scope()
                different.primary["sleep"]?.members = ["different source"]
                old.entries["steps"]?.context = different.signature
            }
            try JSONEncoder().encode(old).write(to: file, options: .atomic)
            let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: .init(scope: scope()))
            _ = await ledger.flush()
            let migrated = await ledger.snapshot()
            XCTAssertEqual(migrated.entries["sleep"]?.generation, 7)
            XCTAssertEqual(migrated.entries["sleep"]?.currentPending, false)
            XCTAssertEqual(migrated.entries["sleep"]?.historyPending, true)
            XCTAssertEqual(migrated.entries["steps"]?.currentPending, true)
            XCTAssertEqual(migrated.entries["steps"]?.historyPending, true)
            XCTAssertGreaterThan(try XCTUnwrap(migrated.entries["steps"]?.generation), old.revision)
        }
    }

    func testFailedMigrationWriteCannotConsumeWorkAndRestartRetriesMigration() async throws {
        struct Failure: Error {}
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let old = try writeLegacy(scope(), to: file)
        let bytes = try Data(contentsOf: file)
        let context = BodyHealthObserverContext(scope: scope())
        let failed = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: context,
                                            write: { _, _ in throw Failure() })
        let flushed = await failed.flush()
        XCTAssertFalse(flushed)
        let value = await failed.receipt(for: .sleep)
        let accepted = await failed.acknowledge(try XCTUnwrap(value), current: true, history: true)
        XCTAssertFalse(accepted)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let restart = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: context)
        let durable = await restart.flush()
        XCTAssertTrue(durable)
        let migrated = await restart.snapshot()
        XCTAssertEqual(migrated.schema, 2)
        XCTAssertNotEqual(migrated.resetID, old.resetID)
        XCTAssertEqual(migrated.entries["sleep"]?.historyPending, true)
        XCTAssertEqual(migrated.entries["steps"]?.historyPending, false)
    }

    func testDiscoveryAndSourceABARejectPriorReceiptsAndConverge() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var unresolved = scope()
        unresolved.primary["sleep"]?.members = nil
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: .init(scope: unresolved))
        _ = await ledger.flush()
        let before = await ledger.receipt(for: .sleep)
        let resolved = BodyHealthObserverContext(scope: scope())
        _ = await ledger.synchronize(domains: [.sleep], context: resolved)
        let obsolete = await ledger.acknowledge(try XCTUnwrap(before), current: true, history: true)
        XCTAssertFalse(obsolete)
        let stable = await ledger.snapshot()
        _ = await ledger.synchronize(domains: [.sleep], context: resolved)
        let same = await ledger.snapshot()
        XCTAssertEqual(same, stable)
        let firstA = await ledger.receipt(for: .sleep)
        var other = scope()
        other.primary["sleep"]?.members = ["B"]
        _ = await ledger.synchronize(domains: [.sleep], context: .init(scope: other))
        _ = await ledger.synchronize(domains: [.sleep], context: resolved)
        let oldA = await ledger.acknowledge(try XCTUnwrap(firstA), current: true, history: true)
        XCTAssertFalse(oldA)
        let current = await ledger.receipt(for: .sleep)
        _ = await ledger.mark([.sleep], context: resolved)
        let superseded = await ledger.acknowledge(try XCTUnwrap(current), current: true, history: true)
        XCTAssertFalse(superseded)
        let newest = await ledger.receipt(for: .sleep)
        let repaired = await ledger.acknowledge(try XCTUnwrap(newest), current: true, history: true)
        XCTAssertTrue(repaired)
        _ = await ledger.synchronize(domains: [.sleep], context: resolved)
        let drained = await ledger.snapshot()
        XCTAssertTrue(drained.entries.values.allSatisfy { !$0.currentPending && !$0.historyPending })
    }

    func testAcknowledgmentRetriesTransientWriteButNeverClearsNewerOrUndurableWork() async throws {
        struct Failure: Error {}
        for (changedKind, persistent) in [(HealthMetricKind.steps, false), (.sleep, false), (.steps, true)] {
            let file = file()
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let writes = OSAllocatedUnfairLock(initialState: 0)
            let context = BodyHealthObserverContext(scope: scope())
            let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: context,
                write: { data, file in
                    let attempt = writes.withLock { $0 += 1; return $0 }
                    if attempt == 2 || (persistent && attempt >= 2) { throw Failure() }
                    try data.write(to: file, options: .atomic)
                })
            _ = await ledger.flush()
            let value = await ledger.receipt(for: .sleep)
            let receipt = try XCTUnwrap(value)
            let marked = await ledger.mark([changedKind], context: context)
            XCTAssertFalse(marked)
            let acknowledged = await ledger.acknowledge(receipt, current: true, history: true)
            XCTAssertEqual(acknowledged, changedKind == .steps && !persistent)
            XCTAssertEqual(writes.withLock { $0 }, acknowledged ? 4 : 3, "Only one recovery flush attempt")
            let state = await ledger.snapshot()
            XCTAssertEqual(state.entries[changedKind.rawValue]?.historyPending, true)
            let restart = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: context)
            let disk = await restart.snapshot()
            XCTAssertEqual(disk.entries["sleep"]?.historyPending, !acknowledged)
            XCTAssertEqual(disk.entries["steps"]?.historyPending, true)
        }
    }

    @MainActor
    func testUndurableLedgerSkipsObservedHealthReadsAndRetainsPendingWork() async throws {
        struct Failure: Error {}
        let restore = preserveInitialHealthLoadDefaults()
        defer { restore() }
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let health = FakeHealthStore()
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.steps]), engineHealthStore: health, workoutJournalFile: nil)
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.steps], context: store.currentObserverLedgerContext(),
                                            write: { _, _ in throw Failure() })
        let value = await ledger.receipt(for: .steps)
        let changed = await store.repairObservedMetrics([(.steps, try XCTUnwrap(value))], ledger: ledger)
        XCTAssertFalse(changed)
        XCTAssertTrue(health.leafRequests.isEmpty)
        XCTAssertTrue(health.executedQueries.isEmpty)
        XCTAssertFalse(store.isRefreshing)
        let pending = await ledger.snapshot()
        XCTAssertEqual(pending.entries["steps"]?.historyPending, true)
    }

    @MainActor
    func testObservedDiscoveryFencesOldPassAndStableNextPassDrainsReceipt() async throws {
        let restore = preserveInitialHealthLoadDefaults()
        let foreground = BodyAppRuntime.isForegroundActive
        BodyAppRuntime.setForegroundActive(true)
        defer { BodyAppRuntime.setForegroundActive(foreground); restore() }
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let health = FakeHealthStore()
        let resting = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .restingHeartRate))
        health.scriptSources(for: resting, .sources([]))
        let steps = try XCTUnwrap(HKObjectType.quantityType(forIdentifier: .stepCount))
        health.scriptSources(for: steps, .sources([]))
        health.scriptDailyQuantities(for: resting, values: [])
        health.scriptSamples(for: resting, .samples([]))
        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.heart, .steps]),
            initialHealthDataSourceSelection: .defaultValue, initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false, initialCustomHealthSourceGroups: [],
            engineHealthStore: health, workoutJournalFile: nil)
        let originalContext = store.currentObserverLedgerContext()
        let ledger = BodyHealthDirtyWorkStore(file: file, domains: [.restingHeartRate, .steps], context: originalContext)
        _ = await ledger.flush()
        let value = await ledger.receipt(for: .restingHeartRate)
        let original = try XCTUnwrap(value)
        let other = await ledger.receipt(for: .steps)
        let first = await store.repairObservedMetrics([(.restingHeartRate, original), (.steps, try XCTUnwrap(other))], ledger: ledger)
        XCTAssertFalse(first, "Discovery changes provenance and must retire the original fence")
        XCTAssertNotEqual(store.currentObserverLedgerContext(), originalContext)
        XCTAssertFalse(health.leafRequests.contains(.statisticsCollection(resting.identifier)))
        XCTAssertFalse(health.leafRequests.contains(.statisticsCollection(steps.identifier)), "Retired batch preparation must stop before metric reads")
        XCTAssertTrue(health.executedQueries.isEmpty)
        _ = await ledger.synchronize(domains: [.restingHeartRate, .steps], context: store.currentObserverLedgerContext())
        let rejected = await ledger.acknowledge(original, current: true, history: true)
        XCTAssertFalse(rejected)
        let next = await ledger.receipt(for: .restingHeartRate)
        let second = await store.repairObservedMetrics([(.restingHeartRate, try XCTUnwrap(next))], ledger: ledger)
        XCTAssertTrue(second, "Stable discovery must reach authoritative reads and durable acknowledgment")
        XCTAssertTrue(health.leafRequests.contains(.statisticsCollection(resting.identifier)))
        let drained = await ledger.snapshot()
        XCTAssertEqual(drained.entries["restingHeartRate"]?.currentPending, false)
        XCTAssertEqual(drained.entries["restingHeartRate"]?.historyPending, false)
        _ = await ledger.synchronize(domains: [.restingHeartRate, .steps], context: store.currentObserverLedgerContext())
        let stable = await ledger.snapshot()
        XCTAssertEqual(stable, drained)
    }
}
