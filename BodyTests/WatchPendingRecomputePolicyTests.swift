//
//  WatchPendingRecomputePolicyTests.swift
//  BodyTests
//
//  Locks the rule that a detected workout change is never acknowledged just
//  because a compute STARTED (`WatchPendingRecomputePolicy`): it is consumed
//  only by a compute whose queries ran after the detection, that published
//  readiness, and whose result reached disk. Until then it keeps a small retry
//  budget outside the ordinary compute throttle.
//

import XCTest
@testable import Body

final class WatchPendingRecomputePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private typealias Policy = WatchPendingRecomputePolicy

    func testNothingPendingIsIdle() {
        XCTAssertEqual(Policy.decision(WatchPendingReadinessWork(), now: t0), .idle)
    }

    func testFreshDetectionRunsImmediately() {
        let work = Policy.detecting(WatchPendingReadinessWork(), at: t0)
        XCTAssertEqual(work.pendingSince, t0)
        XCTAssertEqual(Policy.decision(work, now: t0), .runNow)
    }

    func testAttemptSpacesTheNextOneOut() {
        var work = Policy.detecting(WatchPendingReadinessWork(), at: t0)
        work = Policy.attempting(work, at: t0)
        XCTAssertEqual(Policy.decision(work, now: at(60)), .retryAt(at(Policy.minimumSpacing)))
        XCTAssertEqual(Policy.decision(work, now: at(Policy.minimumSpacing)), .runNow)
    }

    func testFutureDatedAttemptDoesNotParkTheWork() {
        var work = Policy.detecting(WatchPendingReadinessWork(), at: t0)
        work = Policy.attempting(work, at: at(3_600))
        XCTAssertEqual(Policy.decision(work, now: t0), .runNow, "a clock rollback must not read as a recent attempt")
    }

    func testBudgetExhaustsAndANewDetectionRestoresIt() {
        var work = Policy.detecting(WatchPendingReadinessWork(), at: t0)
        for index in 0..<Policy.maximumAttempts {
            work = Policy.attempting(work, at: at(Double(index) * Policy.minimumSpacing))
        }
        let later = at(Double(Policy.maximumAttempts) * Policy.minimumSpacing)
        XCTAssertEqual(Policy.decision(work, now: later), .exhausted)
        XCTAssertNotNil(work.pendingSince, "exhausted work is still pending for an ordinary compute to consume")

        work = Policy.detecting(work, at: later)
        XCTAssertEqual(Policy.decision(work, now: later), .runNow)
        XCTAssertEqual(work.attempts, 0)
    }

    func testAttemptWithNothingPendingIsNotCounted() {
        XCTAssertEqual(Policy.attempting(WatchPendingReadinessWork(), at: t0), WatchPendingReadinessWork())
    }

    // MARK: - Consumption

    func testConsumedOnlyByAPublishedPersistedComputeThatCoversTheDetection() {
        let work = Policy.attempting(Policy.detecting(WatchPendingReadinessWork(), at: at(10)), at: at(10))

        // Delayed save: the compute's queries ran to 10:00:05, the workout
        // became readable at 10:00:10.
        XCTAssertEqual(
            Policy.consuming(work, coverage: at(5), publishedReadiness: true, persisted: true), work,
            "a compute that predates the detection can't have seen the change"
        )
        // One failed readiness input: readiness is left unstamped.
        XCTAssertEqual(Policy.consuming(work, coverage: at(10), publishedReadiness: false, persisted: true), work)
        // The save failed.
        XCTAssertEqual(Policy.consuming(work, coverage: at(10), publishedReadiness: true, persisted: false), work)

        XCTAssertEqual(
            Policy.consuming(work, coverage: at(10), publishedReadiness: true, persisted: true),
            WatchPendingReadinessWork()
        )
    }

    func testChangeDetectedDuringAnInFlightComputeOutlivesThatCompute() {
        var work = Policy.attempting(Policy.detecting(WatchPendingReadinessWork(), at: at(0)), at: at(0))
        // A second workout change lands while that compute is still running.
        work = Policy.detecting(work, at: at(3))
        work = Policy.consuming(work, coverage: at(0), publishedReadiness: true, persisted: true)
        XCTAssertEqual(work.pendingSince, at(3))
        XCTAssertEqual(Policy.decision(work, now: at(4)), .runNow)
    }
}
