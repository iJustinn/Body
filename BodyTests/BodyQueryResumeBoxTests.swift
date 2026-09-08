//
//  BodyQueryResumeBoxTests.swift
//  BodyTests
//
//  Exercises the lock-protected one-shot resume backing every leaf read on the
//  `BodyHealthQuerying` conformance (H4/M35). This is where "the in-flight
//  query is stopped exactly once" is proven.
//  `stop` is injected rather than a real `HKHealthStore`, so these tests never
//  call `HKHealthStore.execute`/`.stop`, which are not exercisable on an
//  unsigned test host. Mirrors `CancellableQueryCoordinatorTests`' style for
//  the engine's analogous `CancellableQueryCoordinator`. (Exactly-once resume
//  is enforced by `CheckedContinuation` itself: a double resume traps and a
//  missing resume hangs, so each test completing with the asserted value is
//  itself the resume-count check.)
//

import XCTest
import HealthKit
@testable import Body

final class BodyQueryResumeBoxTests: XCTestCase {
    // MARK: - Cancel before install

    func testCancelBeforeInstallResumesNilWithoutExecutingBody() async {
        let recorder = StopCallRecorder()
        let box = BodyQueryResumeBox<[HKSource]?>(stop: { _ in recorder.recordStop() })

        var bodyCalled = false
        box.cancel(cancelledValue: nil)

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[HKSource]?, Never>) in
            box.install(continuation: continuation, cancelledValue: nil) { _ in
                bodyCalled = true
                return Self.makeDummyQuery()
            }
        }

        XCTAssertNil(result)
        XCTAssertFalse(bodyCalled, "install must never build the query once cancel landed first")
        XCTAssertEqual(recorder.stopCount, 0)
    }

    // MARK: - Cancel after install

    func testCancelAfterInstallResumesNilAndStopsTheQuery() async {
        let recorder = StopCallRecorder()
        let box = BodyQueryResumeBox<[HKSource]?>(stop: { _ in recorder.recordStop() })

        // Cancel only after `install` has fully returned (the query already
        // stashed), so it takes the ordinary path and stops it itself.
        let installReturned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            installReturned.wait()
            box.cancel(cancelledValue: nil)
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[HKSource]?, Never>) in
            box.install(continuation: continuation, cancelledValue: nil) { _ in
                Self.makeDummyQuery()
            }
            installReturned.signal()
        }

        XCTAssertNil(result)
        XCTAssertEqual(recorder.stopCount, 1)

        // A second cancel is a no-op: no double resume (which would trap) and
        // no second stop.
        box.cancel(cancelledValue: nil)
        XCTAssertEqual(recorder.stopCount, 1)
    }

    // MARK: - Normal resume, then a later cancel

    func testResumeThenCancelDoesNotResumeTwice() async {
        let recorder = StopCallRecorder()
        let box = BodyQueryResumeBox<[HKSource]?>(stop: { _ in recorder.recordStop() })
        let discoveredSources: [HKSource]? = []

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<[HKSource]?, Never>) in
            box.install(continuation: continuation, cancelledValue: nil) { resume in
                let query = Self.makeDummyQuery()
                resume(discoveredSources)
                return query
            }
        }

        XCTAssertEqual(result?.count, 0, "the real result must win over a later cancel")

        // A cancel after the query already resumed must be a no-op: no double
        // resume (which would trap) and no stop for a query that already
        // finished.
        box.cancel(cancelledValue: nil)
        XCTAssertEqual(recorder.stopCount, 0)
    }

    // MARK: - Helpers

    /// A query constructible without an `HKHealthStore`; the box only hands it
    /// to the injected `stop` closure, so it never touches HealthKit.
    private static func makeDummyQuery() -> HKQuery {
        HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: nil,
            limit: 1,
            sortDescriptors: nil
        ) { _, _, _ in }
    }
}

/// Lock-guarded counter for the injected `stop` closure. `@unchecked Sendable`
/// because the field is accessed under `lock`, mirroring the box under test.
private final class StopCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stopCountValue = 0

    func recordStop() {
        lock.lock(); stopCountValue += 1; lock.unlock()
    }

    var stopCount: Int {
        lock.lock(); defer { lock.unlock() }; return stopCountValue
    }
}
