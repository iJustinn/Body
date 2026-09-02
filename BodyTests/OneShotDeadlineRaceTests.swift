//
//  OneShotDeadlineRaceTests.swift
//  BodyTests
//
//  `OneShotDeadlineRace` is what keeps the background warning evaluation from
//  wedging (H3): the deadline must return WITHOUT awaiting work that never
//  finishes. Exactly-once resume is enforced by `CheckedContinuation` — a double
//  resume traps — so every case completing is itself the resume-count check.
//

import XCTest
@testable import Body

final class OneShotDeadlineRaceTests: XCTestCase {
    /// Generous upper bound: the assertion is "the caller came back long before
    /// the work would have", not a latency measurement.
    private let generousUpperBound: Duration = .seconds(5)

    func testWorkThatNeverFinishesTimesOut() async {
        let clock = ContinuousClock()
        let start = clock.now

        let outcome = await OneShotDeadlineRace.run(deadline: .milliseconds(150)) {
            // Stands in for a HealthKit query that never calls back. Left
            // running: the point of the race is that nobody waits for it.
            try? await Task.sleep(for: .seconds(30))
            return 1
        }
        let elapsed = clock.now - start

        switch outcome {
        case .timedOut:
            break
        case .finished(let value):
            XCTFail("Expected a timeout, got \(value)")
        }
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(150))
        XCTAssertLessThan(elapsed, generousUpperBound)
    }

    func testWorkThatFinishesFirstReturnsItsValue() async {
        let clock = ContinuousClock()
        let start = clock.now

        let outcome = await OneShotDeadlineRace.run(deadline: .seconds(30)) { 42 }
        let elapsed = clock.now - start

        switch outcome {
        case .finished(let value):
            XCTAssertEqual(value, 42)
        case .timedOut:
            XCTFail("Expected the work to win the race")
        }
        XCTAssertLessThan(elapsed, generousUpperBound)
    }

    /// The sleeper is cancelled by the winner, and its `try?`-swallowed wake
    /// must not resume a continuation that already fired.
    func testLosingSleeperDoesNotResumeAgain() async {
        let outcome = await OneShotDeadlineRace.run(deadline: .milliseconds(50)) { 7 }

        switch outcome {
        case .finished(let value):
            XCTAssertEqual(value, 7)
        case .timedOut:
            XCTFail("Expected the work to win the race")
        }

        // Well past the deadline: a second resume would have trapped by now.
        try? await Task.sleep(for: .milliseconds(300))
    }
}
