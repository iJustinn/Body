//
//  HealthKitFetchEngineTrainingLoadTests.swift
//  BodyTests
//
//  The shared training-load workout fetch is memoized on the engine for the
//  duration of a refresh (H5). Two invariants: a cancelled caller cancels the
//  shared fetch instead of parking on it forever, and a thrown result is not
//  memoized for the rest of the refresh. The leaf goes through
//  `runCancellableQuery`, whose cancelled-before-install branch resumes without
//  calling `execute`, so this runs on the unsigned test host.
//

import XCTest
@testable import Body

final class HealthKitFetchEngineTrainingLoadTests: XCTestCase {
    private func makeEngine(healthStore: any BodyHealthQuerying = FakeHealthStore()) -> HealthKitFetchEngine {
        HealthKitFetchEngine(
            permission: .defaultValue,
            healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false,
            healthStore: healthStore
        )
    }

    /// The previous test cancels BEFORE the leaf runs, so it never proves the
    /// in-flight case. `FakeHealthStore` records the query and never resumes it
    /// — exactly a HealthKit read that never answers — so cancelling a caller
    /// that is already parked on the workout query must still come back
    /// promptly rather than pinning the refresh until relaunch.
    func testCancellingACallerParkedOnAnUnansweredWorkoutQueryReturnsPromptly() async {
        let engine = makeEngine()
        await engine.setHealthTrendAnchorDate(Date())
        let window = await engine.trainingLoadWorkoutsWindow(calendar: .bodyGregorian)

        let caller = Task { () -> Result<[WorkoutSummary], Error> in
            do {
                return .success(try await engine.sharedTrainingLoadWorkouts(window: window))
            } catch {
                return .failure(error)
            }
        }
        // Let the caller reach the (never-answering) query first.
        try? await Task.sleep(for: .milliseconds(100))
        let cancelledAt = Date()
        caller.cancel()

        switch await caller.value {
        case .failure:
            XCTAssertLessThan(
                Date().timeIntervalSince(cancelledAt),
                1,
                "a cancelled caller must not wait on a query that never answers"
            )
        case .success(let workouts):
            XCTFail("Expected the cancelled fetch to throw, got \(workouts.count) workouts")
        }
    }

    func testCancelledCallerCancelsTheSharedFetchAndDoesNotMemoizeTheFailure() async {
        let engine = makeEngine()
        await engine.setHealthTrendAnchorDate(Date())
        let window = await engine.trainingLoadWorkoutsWindow(calendar: .bodyGregorian)

        let caller = Task { () -> Result<[WorkoutSummary], Error> in
            // Deterministic: enter the fetch only once cancellation is visible,
            // so the leaf takes its cancelled path rather than racing the flag.
            while !Task.isCancelled {
                await Task.yield()
            }
            do {
                return .success(try await engine.sharedTrainingLoadWorkouts(window: window))
            } catch {
                return .failure(error)
            }
        }
        caller.cancel()

        switch await caller.value {
        case .failure:
            break
        case .success(let workouts):
            XCTFail("Expected the cancelled fetch to throw, got \(workouts.count) workouts")
        }

        // A failure must not be replayed to every later caller in this refresh.
        let memoizedTask = await engine.sharedTrainingLoadWorkoutsTask
        XCTAssertNil(memoizedTask)
        let memoizedWindow = await engine.sharedTrainingLoadWorkoutsWindow
        XCTAssertNil(memoizedWindow)
    }

    func testSettingTheAnchorDateClearsTheMemoizedFetch() async {
        let engine = makeEngine()
        await engine.setHealthTrendAnchorDate(Date())
        await engine.setHealthTrendAnchorDate(nil)

        let memoizedTask = await engine.sharedTrainingLoadWorkoutsTask
        XCTAssertNil(memoizedTask)
        let memoizedWindow = await engine.sharedTrainingLoadWorkoutsWindow
        XCTAssertNil(memoizedWindow)
    }
}
