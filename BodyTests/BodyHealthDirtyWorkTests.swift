import XCTest
@testable import Body

final class BodyHealthDirtyWorkTests: XCTestCase {
    private func observerContext(_ name: String) -> BodyHealthObserverContext {
        .init(scope: .init(primary: ["sleep": .init(request: name, members: [name])],
                           secondary: [:], aggregation: "UTC", sleepGoal: 28_800))
    }

    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dirty.json")
    }

    func testCurrentCoverageCannotEraseUnknownHistoricalMutationAfterReload() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: observerContext("A"))
        let captured = await store.flush()
        XCTAssertTrue(captured)
        let optionalReceipt = await store.receipt(for: .sleep)
        let receipt = try XCTUnwrap(optionalReceipt)
        let ack = await store.acknowledge(receipt, current: true, history: false)
        XCTAssertTrue(ack)
        let reloaded = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: observerContext("A"))
        let state = await reloaded.snapshot()
        XCTAssertEqual(state.entries["sleep"]?.currentPending, false)
        XCTAssertEqual(state.entries["sleep"]?.historyPending, true)
        let history = await reloaded.acknowledge(receipt, current: false, history: true)
        XCTAssertTrue(history)
        let final = await reloaded.snapshot()
        XCTAssertEqual(final.entries["sleep"]?.historyPending, false)
    }

    func testNewEventResetAndContextEachRejectStaleAcknowledgment() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: observerContext("A"))
        _ = await store.flush()
        let first = await store.receipt(for: .sleep)
        let receipt = try XCTUnwrap(first)
        _ = await store.mark([.sleep], context: observerContext("A"))
        let stale = await store.acknowledge(receipt, current: true, history: true)
        XCTAssertFalse(stale)
        let second = await store.receipt(for: .sleep)
        let secondReceipt = try XCTUnwrap(second)
        _ = await store.reset(domains: [.sleep], context: observerContext("A"))
        let reset = await store.acknowledge(secondReceipt, current: true, history: true)
        XCTAssertFalse(reset)
        let third = await store.receipt(for: .sleep)
        let thirdReceipt = try XCTUnwrap(third)
        _ = await store.mark([.sleep], context: observerContext("B"))
        let context = await store.acknowledge(thirdReceipt, current: true, history: true)
        XCTAssertFalse(context)
        let final = await store.snapshot()
        XCTAssertEqual(final.entries["sleep"]?.context, self.observerContext("B").signature)
        XCTAssertEqual(final.entries["sleep"]?.currentPending, true)
    }

    func testFailedCaptureCannotBeAcknowledgedAndCorruptReloadIsConservative() async throws {
        struct Failure: Error {}
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.heartRate], context: observerContext("A"), write: { _, _ in throw Failure() })
        let captured = await store.mark([.heartRate], context: observerContext("A"))
        XCTAssertFalse(captured)
        let receiptValue = await store.receipt(for: .heartRate)
        let receipt = try XCTUnwrap(receiptValue)
        let ack = await store.acknowledge(receipt, current: true, history: true)
        XCTAssertFalse(ack)
        try Data("invalid".utf8).write(to: file)
        let reloaded = BodyHealthDirtyWorkStore(file: file, domains: [.heartRate, .sleep], context: observerContext("B"))
        let state = await reloaded.snapshot()
        XCTAssertTrue(state.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
        XCTAssertEqual(Set(state.entries.keys), ["heartRate", "sleep"])
        XCTAssertNotEqual(state.resetID, receipt.resetID)
    }

    func testFailedAcknowledgmentLeavesDurablePendingWorkAndOtherDomainsIntact() async throws {
        struct Failure: Error {}
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let original = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: observerContext("A"))
        _ = await original.flush()
        let failing = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: observerContext("A"), write: { _, _ in throw Failure() })
        let value = await failing.receipt(for: .sleep)
        let receipt = try XCTUnwrap(value)
        let ack = await failing.acknowledge(receipt, current: true, history: true)
        XCTAssertFalse(ack)
        let reload = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: observerContext("A"))
        let state = await reload.snapshot()
        XCTAssertTrue(state.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
    }

    func testCleanUnchangedReloadStaysCleanButChangedSelectionInvalidates() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: observerContext("A"))
        _ = await store.flush()
        let value = await store.receipt(for: .sleep)
        _ = await store.acknowledge(try XCTUnwrap(value), current: true, history: true)
        let same = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: observerContext("A"))
        let sameState = await same.snapshot()
        XCTAssertEqual(sameState.entries["sleep"]?.currentPending, false)
        let changed = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: observerContext("B"))
        let changedState = await changed.snapshot()
        XCTAssertTrue(changedState.entries.values.allSatisfy { $0.currentPending && $0.historyPending && $0.context == observerContext("B").signature })
    }
    func testSynchronizingSameScopePreservesReceiptsAndRemovesDisabledDomains() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: observerContext("A"))
        _ = await store.flush()
        let first = await store.receipt(for: .sleep)
        _ = await store.synchronize(domains: [.sleep], context: observerContext("A"))
        let next = await store.receipt(for: .sleep)
        let state = await store.snapshot()
        XCTAssertEqual(first, next)
        XCTAssertNil(state.entries["steps"])
        _ = await store.synchronize(domains: [.sleep], context: observerContext("B"))
        let changed = await store.receipt(for: .sleep)
        XCTAssertNotEqual(first, changed)
    }

    func testDayAndComputeChangesPreserveCleanHistoryButFetchChangesInvalidate() async throws {
        let sources = ["sleep": HealthDashboardCacheScope.Source(request: "sleep", members: ["A"])]
        let original = HealthDashboardCacheScope(primary: sources, secondary: [:], aggregation: "UTC",
            sleepGoal: 28_800, summaryDayStart: Date(timeIntervalSince1970: 1_789_171_200))
        var day = original
        day.summaryDayStart = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: original.summaryDayStart!)
        var goal = original
        goal.sleepGoal += 3_600
        var source = original
        source.primary["sleep"]?.members = ["B"]
        var permission = original
        permission.primary["sleep"]?.request = "disabled"
        var zone = original
        zone.aggregation = "America/New_York"
        var unresolved = original
        unresolved.primary["sleep"]?.members = nil

        let cases = [("day", original, day), ("compute", original, goal),
                     ("source", original, source), ("permission", original, permission),
                     ("timezone", original, zone), ("discovery", unresolved, original)]
        let domains: Set<HealthMetricKind> = [.sleep, .steps, .heartRate]
        for (reason, before, after) in cases {
            let file = file()
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let store = BodyHealthDirtyWorkStore(file: file, domains: domains, context: .init(scope: before))
            _ = await store.flush()
            for kind in domains {
                let value = await store.receipt(for: kind)
                let acknowledged = await store.acknowledge(try XCTUnwrap(value), current: true, history: true)
                XCTAssertTrue(acknowledged, reason)
            }
            let clean = await store.snapshot()
            _ = await store.synchronize(domains: domains, context: .init(scope: before))
            let unchanged = await store.snapshot()
            XCTAssertEqual(unchanged, clean, reason)
            let sameReload = BodyHealthDirtyWorkStore(file: file, domains: domains, context: .init(scope: before))
            let same = await sameReload.snapshot()
            XCTAssertEqual(same, clean, reason)

            // Retain an independent day-A file for the cold-load path.
            let saved = try Data(contentsOf: file)
            _ = await store.synchronize(domains: domains, context: .init(scope: after))
            let warm = await store.snapshot()
            XCTAssertEqual(warm.entries.count, domains.count)
            let fetchChanged = !["day", "compute"].contains(reason)
            if fetchChanged {
                XCTAssertTrue(warm.entries.values.allSatisfy {
                    $0.currentPending && $0.historyPending && $0.generation > clean.revision
                }, reason)
            } else {
                XCTAssertEqual(warm, clean, reason)
            }
            try saved.write(to: file, options: .atomic)
            let coldStore = BodyHealthDirtyWorkStore(file: file, domains: domains, context: .init(scope: after))
            let cold = await coldStore.snapshot()
            XCTAssertEqual(cold.entries.count, domains.count)
            XCTAssertEqual(cold, warm, reason)
        }
    }

    func testPendingDeliverySurvivesDayAndGoalChangesWithoutReplacingReceipt() async throws {
        let original = HealthDashboardCacheScope(primary: [:], secondary: [:], aggregation: "UTC",
            sleepGoal: 28_800, summaryDayStart: Date(timeIntervalSince1970: 1_789_171_200))
        var day = original
        day.summaryDayStart = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: original.summaryDayStart!)
        var goal = original
        goal.sleepGoal += 3_600
        for next in [day, goal] {
            let file = file()
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: .init(scope: original))
            _ = await store.mark([.sleep], context: .init(scope: original))
            let value = await store.receipt(for: .sleep)
            let receipt = try XCTUnwrap(value)
            _ = await store.synchronize(domains: [.sleep], context: .init(scope: next))
            let sameReceipt = await store.receipt(for: .sleep)
            XCTAssertEqual(sameReceipt, receipt)
            let reload = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: .init(scope: next))
            let pending = await reload.snapshot()
            XCTAssertEqual(pending.entries["sleep"]?.currentPending, true)
            XCTAssertEqual(pending.entries["sleep"]?.historyPending, true)
            XCTAssertEqual(try XCTUnwrap(pending.entries["sleep"]?.generation), receipt.generation)
        }
    }

    // MARK: Deferred sleep

    private func settle(_ store: BodyHealthDirtyWorkStore, _ kinds: [HealthMetricKind]) async throws {
        for kind in kinds {
            let value = await store.receipt(for: kind)
            let acknowledged = await store.acknowledge(try XCTUnwrap(value), current: true, history: true)
            XCTAssertTrue(acknowledged)
        }
    }

    func testDeferredSleepIsDurableFencedAndKeepsItsFirstDeferralAcrossReload() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let context = observerContext("A")
        let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.heartRate, .sleep], context: context)
        try await settle(store, [.heartRate, .sleep])
        let durable = await store.mark([.heartRate, .sleep], deferring: [.sleep], context: context, now: first)
        XCTAssertTrue(durable)
        let marked = await store.snapshot()
        let sleep = try XCTUnwrap(marked.entries["sleep"])
        XCTAssertEqual(sleep.deferredAt, first)
        XCTAssertTrue(sleep.currentPending)
        XCTAssertTrue(sleep.historyPending)
        XCTAssertEqual(sleep.generation, marked.revision)
        XCTAssertEqual(marked.entries["heartRate"]?.currentPending, true)
        XCTAssertNil(marked.entries["heartRate"]?.deferredAt)
        _ = await store.mark([.heartRate, .sleep], deferring: [.sleep], context: context, now: first.addingTimeInterval(3_600))
        let again = await store.snapshot()
        XCTAssertEqual(again.entries["sleep"]?.deferredAt, first, "the limit counts from the first deferral")
        XCTAssertGreaterThan(try XCTUnwrap(again.entries["sleep"]?.generation), sleep.generation)
        let reloaded = BodyHealthDirtyWorkStore(file: file, domains: [.heartRate, .sleep], context: context)
        let restored = await reloaded.snapshot()
        XCTAssertEqual(restored, again)
    }

    func testDeferralOnPendingEntryOnlyBumpsGenerationAndRejectsTheInFlightAcknowledgment() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let context = observerContext("A")
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: context)
        let value = await store.receipt(for: .sleep)
        let inFlight = try XCTUnwrap(value)
        // History settled, current still pending: the deferral keeps both flags.
        let history = await store.acknowledge(inFlight, current: false, history: true)
        XCTAssertTrue(history)
        _ = await store.mark([.sleep], deferring: [.sleep], context: context)
        let snapshot = await store.snapshot()
        let entry = try XCTUnwrap(snapshot.entries["sleep"])
        XCTAssertNil(entry.deferredAt, "sleep already pending is read anyway")
        XCTAssertTrue(entry.currentPending)
        XCTAssertFalse(entry.historyPending)
        XCTAssertGreaterThan(entry.generation, inFlight.generation)
        let stale = await store.acknowledge(inFlight, current: true, history: true)
        XCTAssertFalse(stale)
        let after = await store.snapshot()
        XCTAssertEqual(after.entries["sleep"], entry)
    }

    func testCleanReadCannotAcknowledgeADeferralThatLandsDuringIt() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let context = observerContext("A")
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: context)
        try await settle(store, [.sleep])
        // A read that started on the clean entry holds at most its settled generation.
        let value = await store.receipt(for: .sleep)
        let inFlight = try XCTUnwrap(value)
        _ = await store.mark([.sleep], deferring: [.sleep], context: context)
        let rejected = await store.acknowledge(inFlight, current: true, history: true)
        XCTAssertFalse(rejected)
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.entries["sleep"]?.currentPending, true)
        XCTAssertNotNil(snapshot.entries["sleep"]?.deferredAt)
    }

    func testNormalMarkClearsDeferralAndSettledEntryStartsANewLimit() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let context = observerContext("A")
        let first = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let later = first.addingTimeInterval(2 * 86_400)
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: context)
        try await settle(store, [.sleep])
        _ = await store.mark([.sleep], deferring: [.sleep], context: context, now: first)
        _ = await store.mark([.sleep], context: context)
        let cleared = await store.snapshot()
        XCTAssertNil(cleared.entries["sleep"]?.deferredAt)
        XCTAssertEqual(cleared.entries["sleep"]?.currentPending, true)
        try await settle(store, [.sleep])
        _ = await store.mark([.sleep], deferring: [.sleep], context: context, now: first)
        // Current coverage alone leaves the history obligation deferred.
        let value = await store.receipt(for: .sleep)
        let currentOnly = await store.acknowledge(try XCTUnwrap(value), current: true, history: false)
        XCTAssertTrue(currentOnly)
        let historyOnly = await store.snapshot()
        XCTAssertEqual(historyOnly.entries["sleep"]?.deferredAt, first)
        try await settle(store, [.sleep])
        let settled = await store.snapshot()
        XCTAssertNil(settled.entries["sleep"]?.deferredAt)
        _ = await store.mark([.sleep], deferring: [.sleep], context: context, now: later)
        let restarted = await store.snapshot()
        XCTAssertEqual(restarted.entries["sleep"]?.deferredAt, later)
    }

    func testEnvelopeWithoutDeferredAtDecodesAndUndeferredEntriesOmitTheKey() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let context = observerContext("A")
        let legacy: [String: Any] = [
            "schema": 2, "resetID": UUID().uuidString, "revision": 3,
            "entries": ["sleep": ["generation": 3, "context": context.signature,
                                  "currentPending": true, "historyPending": false]]
        ]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: context)
        let snapshot = await store.snapshot()
        let entry = try XCTUnwrap(snapshot.entries["sleep"])
        XCTAssertEqual(entry.generation, 3)
        XCTAssertTrue(entry.currentPending)
        XCTAssertFalse(entry.historyPending)
        XCTAssertNil(entry.deferredAt)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("deferredAt"))
    }

}
