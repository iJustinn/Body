//
//  HealthKitAuthorizationCoordinatorTests.swift
//  BodyTests
//
//  `HealthKitAuthorizationCoordinator` gives every HealthKit permission-sheet
//  transaction a single FIFO lane, since `requestAuthorization` bridges
//  through a continuation that releases the actor mid-transaction. These
//  tests cover the coordinator's own guarantees in isolation (FIFO ordering,
//  a throwing op not wedging the lane, `isBusy` bookkeeping, and value
//  passthrough) without touching HealthKit itself.
//

import XCTest
@testable import Body

final class HealthKitAuthorizationCoordinatorTests: XCTestCase {

    // MARK: - FIFO ordering

    func testSecondRunWaitsForFirstToFinish() async throws {
        let coordinator = HealthKitAuthorizationCoordinator()
        let log = EventLog()
        let gate = Gate()

        let firstTask = Task {
            try await coordinator.run {
                await log.append("first-start")
                await gate.wait()
                await log.append("first-end")
            }
        }

        // Ensure the first operation is actually running (and blocked on the
        // gate) before enqueueing the second, so ordering isn't accidental.
        await log.waitUntil(count: 1)

        let secondTask = Task {
            try await coordinator.run {
                await log.append("second-start")
            }
        }

        // Give the second task a chance to run if it were (incorrectly) not
        // serialized behind the first.
        try await Task.sleep(nanoseconds: 50_000_000)
        let eventsBeforeRelease = await log.events
        XCTAssertEqual(eventsBeforeRelease, ["first-start"])

        await gate.open()
        _ = try await firstTask.value
        _ = try await secondTask.value

        let finalEvents = await log.events
        XCTAssertEqual(finalEvents, ["first-start", "first-end", "second-start"])
    }

    // MARK: - Throwing op doesn't block the lane

    func testThrowingOperationDoesNotBlockSubsequentRuns() async throws {
        let coordinator = HealthKitAuthorizationCoordinator()

        struct TestFailure: Error {}

        do {
            _ = try await coordinator.run {
                throw TestFailure()
            }
            XCTFail("Expected the operation to throw")
        } catch is TestFailure {
            // expected
        }

        let value = try await coordinator.run { 42 }
        XCTAssertEqual(value, 42)
    }

    // MARK: - isBusy bookkeeping

    func testIsBusyReflectsInFlightOperation() async throws {
        let coordinator = HealthKitAuthorizationCoordinator()
        let gate = Gate()
        let started = EventLog()

        let isBusyBefore = await coordinator.isBusy
        XCTAssertFalse(isBusyBefore)

        let task = Task {
            try await coordinator.run {
                await started.append("started")
                await gate.wait()
            }
        }

        await started.waitUntil(count: 1)
        let isBusyDuring = await coordinator.isBusy
        XCTAssertTrue(isBusyDuring)
        let countDuring = await coordinator.inFlightCount
        XCTAssertEqual(countDuring, 1)

        await gate.open()
        try await task.value

        let isBusyAfter = await coordinator.isBusy
        XCTAssertFalse(isBusyAfter)
        let countAfter = await coordinator.inFlightCount
        XCTAssertEqual(countAfter, 0)
    }

    // MARK: - Value passthrough

    func testRunReturnsTheOperationsValue() async throws {
        let coordinator = HealthKitAuthorizationCoordinator()
        let value = try await coordinator.run { "authorized" }
        XCTAssertEqual(value, "authorized")
    }

    // MARK: - Cancellation

    /// A caller that cancels while waiting behind a slow predecessor must
    /// never run its own operation, and the lane must still serve the next
    /// enqueued caller once the slow predecessor finishes.
    func testCancellingAWaitingCallerSkipsItsOperationAndLaneContinues() async throws {
        let coordinator = HealthKitAuthorizationCoordinator()
        let log = EventLog()
        let gate = Gate()

        let firstTask = Task {
            try await coordinator.run {
                await log.append("first-start")
                await gate.wait()
                await log.append("first-end")
            }
        }

        await log.waitUntil(count: 1)

        let secondTask = Task {
            try await coordinator.run {
                await log.append("second-start")
            }
        }

        // Give the second operation a moment to enqueue behind the first
        // before it is cancelled and before a third is enqueued behind it.
        try await Task.sleep(nanoseconds: 20_000_000)
        secondTask.cancel()

        let thirdTask = Task {
            try await coordinator.run {
                await log.append("third-start")
            }
        }

        await gate.open()
        _ = try await firstTask.value

        do {
            try await secondTask.value
            XCTFail("Expected the cancelled operation to throw")
        } catch is CancellationError {
            // expected
        }

        try await thirdTask.value

        let finalEvents = await log.events
        XCTAssertEqual(finalEvents, ["first-start", "first-end", "third-start"])

        let isBusyAfter = await coordinator.isBusy
        XCTAssertFalse(isBusyAfter)
    }
}

// MARK: - Test helpers

/// Actor-isolated ordered event log with a deterministic "wait until N events"
/// hook, so tests don't rely on sleeps as their only synchronization.
private actor EventLog {
    private(set) var events: [String] = []
    private var continuations: [(Int, CheckedContinuation<Void, Never>)] = []

    func append(_ event: String) {
        events.append(event)
        let count = events.count
        continuations.removeAll { waiting in
            if waiting.0 <= count {
                waiting.1.resume()
                return true
            }
            return false
        }
    }

    func waitUntil(count target: Int) async {
        if events.count >= target {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append((target, continuation))
        }
    }
}

/// A single-use async gate a test can hold closed to keep an operation
/// suspended, then open to release it deterministically.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
