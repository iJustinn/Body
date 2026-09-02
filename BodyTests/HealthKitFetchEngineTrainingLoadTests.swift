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
    private func makeEngine() -> HealthKitFetchEngine {
        HealthKitFetchEngine(
            permission: .defaultValue,
            healthDataSourceSelection: .defaultValue,
            secondaryHealthDataSourceSelection: .defaultValue,
            combinesHealthDataSourcesByName: false
        )
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
