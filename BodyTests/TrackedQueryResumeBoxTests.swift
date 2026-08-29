//
//  TrackedQueryResumeBoxTests.swift
//  BodyTests
//
//  Exercises the one-shot resume guard behind
//  `HealthKitFetchEngine.trackedHealthQuery` (RefreshOptimizationPlan-02 P0-C
//  follow-up). The wrapper used to hold a budget permit across a continuation
//  only the HealthKit callback could resume, so a callback that never arrived
//  kept the permit until relaunch. The box makes cancellation resume the
//  continuation instead, and the late callback a no-op. (Exactly-once resume is
//  enforced by `CheckedContinuation` — a double resume traps and a missing
//  resume hangs, so each test completing with the asserted value is itself the
//  resume-count check.)
//

import XCTest
@testable import Body

final class TrackedQueryResumeBoxTests: XCTestCase {
    private let cancelledValue = -1
    private let successValue = 42

    func testCancelBeforeInstallResumesWithCancelledValueWithoutRunningTheBody() async {
        let box = TrackedQueryResumeBox<Int>()
        box.cancel(cancelledValue: cancelledValue)

        var bodyRan = false
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { _ in
                bodyRan = true
            }
        }

        XCTAssertEqual(result, cancelledValue)
        XCTAssertFalse(bodyRan, "install must never launch the query once cancel landed first")
    }

    func testCallbackResumesWithTheFetchedValue() async {
        let box = TrackedQueryResumeBox<Int>()

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                resume(self.successValue)
            }
        }

        XCTAssertEqual(result, successValue)
    }

    /// The leak this fix targets: the query is in flight and its callback never
    /// arrives. Cancellation must resume anyway, so the caller returns and the
    /// permit goes back to the budget.
    func testCancelWhileInFlightResumesWithCancelledValue() async {
        let box = TrackedQueryResumeBox<Int>()
        var capturedResume: ((Int) -> Void)?

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                capturedResume = resume
            }
            box.cancel(cancelledValue: cancelledValue)
        }

        XCTAssertEqual(result, cancelledValue)
        XCTAssertNotNil(capturedResume, "the body must have run and armed a callback")
    }

    /// The other half of the same scenario: the abandoned query keeps running on
    /// `healthd`, so its callback still fires later and must be dropped rather
    /// than resuming an already-resumed continuation.
    func testLateCallbackAfterCancelIsDropped() async {
        let box = TrackedQueryResumeBox<Int>()
        var capturedResume: ((Int) -> Void)?

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                capturedResume = resume
            }
            box.cancel(cancelledValue: cancelledValue)
        }
        // Would trap on a double resume if the guard let it through.
        capturedResume?(successValue)

        XCTAssertEqual(result, cancelledValue)
    }

    /// Cancellation arriving after the query already completed must be inert.
    func testCancelAfterCompletionIsIgnored() async {
        let box = TrackedQueryResumeBox<Int>()

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                resume(self.successValue)
            }
        }
        box.cancel(cancelledValue: cancelledValue)

        XCTAssertEqual(result, successValue)
    }

    // MARK: - The external wrapper's unstructured-body shape

    /// `trackedExternalHealthQuery` can't interrupt the watch module's own
    /// continuation, so it runs the body as an unstructured task and resumes
    /// through the box. This reproduces that shape with a body that never
    /// finishes: cancellation must still resume with the cancelled value, which
    /// is what lets the wrapper's `defer` hand the permit back.
    func testUnstructuredBodyThatNeverFinishesStillResumesOnCancel() async {
        let box = TrackedQueryResumeBox<Int>()
        let started = expectation(description: "body started")

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                Task {
                    started.fulfill()
                    // Never calls `resume` — the stalled HealthKit callback.
                    _ = resume
                }
            }
            box.cancel(cancelledValue: cancelledValue)
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertEqual(result, cancelledValue)
    }

    /// The orphaned task finishing after cancellation must be inert rather than
    /// resuming an already-resumed continuation.
    func testOrphanedBodyFinishingAfterCancelIsDropped() async {
        let box = TrackedQueryResumeBox<Int>()
        let finished = expectation(description: "orphan finished")
        let gate = AsyncGate()

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                Task {
                    await gate.wait()
                    // Would trap on a double resume if the guard let it through.
                    resume(self.successValue)
                    finished.fulfill()
                }
            }
            box.cancel(cancelledValue: cancelledValue)
        }
        await gate.open()
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(result, cancelledValue)
    }

    /// A HealthKit callback that fires twice (or a callback racing a retry) must
    /// resume exactly once.
    func testSecondCallbackIsDropped() async {
        let box = TrackedQueryResumeBox<Int>()
        var capturedResume: ((Int) -> Void)?

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            box.install(continuation: continuation, cancelledValue: cancelledValue) { resume in
                capturedResume = resume
                resume(self.successValue)
            }
        }
        capturedResume?(successValue)

        XCTAssertEqual(result, successValue)
    }
}

/// One-shot gate so a test can hold an orphaned task open until it has asserted
/// on the cancellation path.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let resumed = waiters
        waiters = []
        for continuation in resumed {
            continuation.resume()
        }
    }
}
