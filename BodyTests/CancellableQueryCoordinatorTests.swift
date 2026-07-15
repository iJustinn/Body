//
//  CancellableQueryCoordinatorTests.swift
//  BodyTests
//
//  Exercises the lock-protected state machine behind
//  `HealthKitFetchEngine.runCancellableQuery` (M15). The round-2 fix left a window
//  between `install` unlocking and calling `execute` where a cancel saw
//  `.pendingWithQuery`, called `stop` on a query that had not run yet (a no-op), and
//  then `install` executed the query anyway — so the HK work leaked. These tests pin
//  the executing/deferred-stop phases: on every cancellation path the query is
//  stopped exactly once and the continuation resumes exactly once. (Exactly-once
//  resume is enforced by `CheckedContinuation` — a double resume traps and a missing
//  resume hangs, so each test completing with the asserted value is itself the
//  resume-count check.)
//

import XCTest
import HealthKit
@testable import Body

final class CancellableQueryCoordinatorTests: XCTestCase {
    private let cancelledValue = -1
    private let successValue = 42

    // MARK: - Scenario 1: cancel before install

    func testCancelBeforeInstallResumesWithCancelledValueWithoutTouchingHealthKit() async {
        let recorder = QueryCallRecorder()
        let coordinator = CancellableQueryCoordinator<Int>(
            execute: { _ in recorder.recordExecute() },
            stop: { _ in recorder.recordStop() }
        )

        var makeQueryCalled = false
        coordinator.cancel(cancelledValue: cancelledValue)

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            coordinator.install(continuation: continuation, cancelledValue: cancelledValue) { _ in
                makeQueryCalled = true
                return Self.makeDummyQuery()
            }
        }

        XCTAssertEqual(result, cancelledValue)
        XCTAssertFalse(makeQueryCalled, "install must never build the query once cancel landed first")
        XCTAssertEqual(recorder.executeCount, 0)
        XCTAssertEqual(recorder.stopCount, 0)
    }

    // MARK: - Scenario 2: cancel in the pre-execute window

    func testCancelDuringExecuteWindowStopsQueryExactlyOnce() async {
        let recorder = QueryCallRecorder()
        let executingReached = DispatchSemaphore(value: 0)
        let cancelDone = DispatchSemaphore(value: 0)

        let coordinator = CancellableQueryCoordinator<Int>(
            execute: { _ in
                // Blocks inside install with the lock released and state `.executing`,
                // holding the unlock→execute window open until the test's cancel lands.
                recorder.recordExecute()
                executingReached.signal()
                cancelDone.wait()
            },
            stop: { _ in recorder.recordStop() }
        )

        // Fire cancel from a real background thread (not the cooperative pool, which the
        // blocking execute above occupies) while the window is held open.
        DispatchQueue.global().async { [cancelledValue] in
            executingReached.wait()
            coordinator.cancel(cancelledValue: cancelledValue)
            // cancel deferred the stop to install's re-check — nothing stopped yet.
            recorder.snapshotStopCountAtCancel()
            cancelDone.signal()
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            coordinator.install(continuation: continuation, cancelledValue: cancelledValue) { _ in
                Self.makeDummyQuery()
            }
        }

        XCTAssertEqual(result, cancelledValue, "cancel in the window resumes with the cancelled value")
        XCTAssertEqual(recorder.stopCountAtCancel, 0, "cancel must not stop the query inline; the stop is deferred")
        XCTAssertEqual(recorder.executeCount, 1)
        XCTAssertEqual(recorder.stopCount, 1, "install's re-check issues the single deferred stop")
    }

    // MARK: - Scenario 3: cancel after execute (normal path)

    func testCancelAfterExecuteStopsQueryOnceViaPendingWithQueryPath() async {
        let recorder = QueryCallRecorder()
        let coordinator = CancellableQueryCoordinator<Int>(
            execute: { _ in recorder.recordExecute() },   // non-blocking: install reaches `.pendingWithQuery`
            stop: { _ in recorder.recordStop() }
        )

        // Cancel only after install has fully returned (state `.pendingWithQuery`), so
        // it takes the ordinary path and stops the query itself.
        let installReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { [cancelledValue] in
            installReturned.wait()
            coordinator.cancel(cancelledValue: cancelledValue)
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            coordinator.install(continuation: continuation, cancelledValue: cancelledValue) { _ in
                Self.makeDummyQuery()
            }
            installReturned.signal()
        }

        XCTAssertEqual(result, cancelledValue)
        XCTAssertEqual(recorder.executeCount, 1)
        XCTAssertEqual(recorder.stopCount, 1, "the `.pendingWithQuery` cancel stops the query exactly once")
    }

    // MARK: - Scenario 4: HK result races cancel while executing

    func testCompleteWhileExecutingResumesOnceAndIgnoresLaterCancelAndLateCallback() async {
        let recorder = QueryCallRecorder()
        let completion = QueryCompletionBox()
        let successValue = self.successValue

        let coordinator = CancellableQueryCoordinator<Int>(
            execute: { _ in
                // HK wins the race: deliver a result while still `.executing`, before
                // execute returns.
                recorder.recordExecute()
                completion.invoke(successValue)
            },
            stop: { _ in recorder.recordStop() }
        )

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            coordinator.install(continuation: continuation, cancelledValue: cancelledValue) { callback in
                completion.set(callback)
                return Self.makeDummyQuery()
            }
        }

        XCTAssertEqual(result, successValue, "the HK result must win and resume the continuation")

        // A cancel after completion is a no-op — nothing gets stopped.
        coordinator.cancel(cancelledValue: cancelledValue)
        XCTAssertEqual(recorder.stopCount, 0)

        // A late second HK callback is dropped: no double resume (which would trap).
        completion.invoke(successValue)

        XCTAssertEqual(recorder.executeCount, 1)
    }

    // MARK: - Helpers

    /// A query that is constructible without an `HKHealthStore`; the coordinator only
    /// hands it to the injected execute/stop closures, so it never touches HealthKit.
    private static func makeDummyQuery() -> HKQuery {
        HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: nil,
            limit: 1,
            sortDescriptors: nil
        ) { _, _, _ in }
    }
}

/// Lock-guarded counters for the injected execute/stop closures. `@unchecked
/// Sendable` because every field is accessed under `lock`, mirroring the coordinator.
private final class QueryCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var executeCountValue = 0
    private var stopCountValue = 0
    private var observedStopCountAtCancel: Int?

    func recordExecute() {
        lock.lock(); executeCountValue += 1; lock.unlock()
    }

    func recordStop() {
        lock.lock(); stopCountValue += 1; lock.unlock()
    }

    /// Snapshots the stop count at the instant `cancel` returned, so a test can assert
    /// the stop was deferred to install's re-check rather than issued inline.
    func snapshotStopCountAtCancel() {
        lock.lock(); observedStopCountAtCancel = stopCountValue; lock.unlock()
    }

    var executeCount: Int {
        lock.lock(); defer { lock.unlock() }; return executeCountValue
    }

    var stopCount: Int {
        lock.lock(); defer { lock.unlock() }; return stopCountValue
    }

    var stopCountAtCancel: Int? {
        lock.lock(); defer { lock.unlock() }; return observedStopCountAtCancel
    }
}

/// Captures the completion callback the coordinator passes to `makeQuery`, so a test
/// can invoke it to simulate an HK result callback (scenario 4).
private final class QueryCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: ((Int) -> Void)?

    func set(_ callback: @escaping (Int) -> Void) {
        lock.lock(); self.callback = callback; lock.unlock()
    }

    func invoke(_ value: Int) {
        lock.lock(); let callback = self.callback; lock.unlock()
        callback?(value)
    }
}
