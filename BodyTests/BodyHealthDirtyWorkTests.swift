import XCTest
@testable import Body

final class BodyHealthDirtyWorkTests: XCTestCase {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dirty.json")
    }

    func testCurrentCoverageCannotEraseUnknownHistoricalMutationAfterReload() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: "A")
        let captured = await store.flush()
        XCTAssertTrue(captured)
        let optionalReceipt = await store.receipt(for: .sleep)
        let receipt = try XCTUnwrap(optionalReceipt)
        let ack = await store.acknowledge(receipt, current: true, history: false)
        XCTAssertTrue(ack)
        let reloaded = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: "A")
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
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: "A")
        _ = await store.flush()
        let first = await store.receipt(for: .sleep)
        let receipt = try XCTUnwrap(first)
        _ = await store.mark([.sleep], context: "A")
        let stale = await store.acknowledge(receipt, current: true, history: true)
        XCTAssertFalse(stale)
        let second = await store.receipt(for: .sleep)
        let secondReceipt = try XCTUnwrap(second)
        _ = await store.reset(domains: [.sleep], context: "A")
        let reset = await store.acknowledge(secondReceipt, current: true, history: true)
        XCTAssertFalse(reset)
        let third = await store.receipt(for: .sleep)
        let thirdReceipt = try XCTUnwrap(third)
        _ = await store.mark([.sleep], context: "B")
        let context = await store.acknowledge(thirdReceipt, current: true, history: true)
        XCTAssertFalse(context)
        let final = await store.snapshot()
        XCTAssertEqual(final.entries["sleep"]?.context, "B")
        XCTAssertEqual(final.entries["sleep"]?.currentPending, true)
    }

    func testFailedCaptureCannotBeAcknowledgedAndCorruptReloadIsConservative() async throws {
        struct Failure: Error {}
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.heartRate], context: "A", write: { _, _ in throw Failure() })
        let captured = await store.mark([.heartRate], context: "A")
        XCTAssertFalse(captured)
        let receiptValue = await store.receipt(for: .heartRate)
        let receipt = try XCTUnwrap(receiptValue)
        let ack = await store.acknowledge(receipt, current: true, history: true)
        XCTAssertFalse(ack)
        try Data("invalid".utf8).write(to: file)
        let reloaded = BodyHealthDirtyWorkStore(file: file, domains: [.heartRate, .sleep], context: "B")
        let state = await reloaded.snapshot()
        XCTAssertTrue(state.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
        XCTAssertEqual(Set(state.entries.keys), ["heartRate", "sleep"])
        XCTAssertNotEqual(state.resetID, receipt.resetID)
    }

    func testFailedAcknowledgmentLeavesDurablePendingWorkAndOtherDomainsIntact() async throws {
        struct Failure: Error {}
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let original = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: "A")
        _ = await original.flush()
        let failing = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: "A", write: { _, _ in throw Failure() })
        let value = await failing.receipt(for: .sleep)
        let receipt = try XCTUnwrap(value)
        let ack = await failing.acknowledge(receipt, current: true, history: true)
        XCTAssertFalse(ack)
        let reload = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: "A")
        let state = await reload.snapshot()
        XCTAssertTrue(state.entries.values.allSatisfy { $0.currentPending && $0.historyPending })
    }

    func testCleanUnchangedReloadStaysCleanButChangedSelectionInvalidates() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: "A")
        _ = await store.flush()
        let value = await store.receipt(for: .sleep)
        _ = await store.acknowledge(try XCTUnwrap(value), current: true, history: true)
        let same = BodyHealthDirtyWorkStore(file: file, domains: [.sleep], context: "A")
        let sameState = await same.snapshot()
        XCTAssertEqual(sameState.entries["sleep"]?.currentPending, false)
        let changed = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: "B")
        let changedState = await changed.snapshot()
        XCTAssertTrue(changedState.entries.values.allSatisfy { $0.currentPending && $0.historyPending && $0.context == "B" })
    }
    func testSynchronizingSameScopePreservesReceiptsAndRemovesDisabledDomains() async throws {
        let file = file()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = BodyHealthDirtyWorkStore(file: file, domains: [.sleep, .steps], context: "A")
        _ = await store.flush()
        let first = await store.receipt(for: .sleep)
        _ = await store.synchronize(domains: [.sleep], context: "A")
        let next = await store.receipt(for: .sleep)
        let state = await store.snapshot()
        XCTAssertEqual(first, next)
        XCTAssertNil(state.entries["steps"])
        _ = await store.synchronize(domains: [.sleep], context: "B")
        let changed = await store.receipt(for: .sleep)
        XCTAssertNotEqual(first, changed)
    }

}
