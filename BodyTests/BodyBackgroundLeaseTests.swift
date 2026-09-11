import XCTest
@testable import Body

final class BodyBackgroundLeaseTests: XCTestCase {
    func testSaturatedBoundedPoolReturnsAtDeadlineWithoutLegacyWaiter() async {
        let pool = HealthKitQuerySemaphore(limit: 1, name: "test")
        XCTAssertTrue(pool.tryAcquire())
        let lease = BodyBackgroundLease(duration: .milliseconds(30))
        let admitted = await lease.run { await pool.acquireForCurrentTask() }
        XCTAssertFalse(admitted)
        pool.release()
        // The expired waiter must not take this newly released permit.
        XCTAssertTrue(pool.tryAcquire())
        pool.release()
    }

    func testCancellationWhileWaitingDoesNotLeakPermit() async {
        let pool = HealthKitQuerySemaphore(limit: 1, name: "test")
        XCTAssertTrue(pool.tryAcquire())
        let lease = BodyBackgroundLease()
        let entered = expectation(description: "entered bounded wait")
        let task = Task {
            await lease.run {
                entered.fulfill()
                return await pool.acquireForCurrentTask()
            }
        }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel()
        let admitted = await task.value
        XCTAssertFalse(admitted)
        pool.release()
        XCTAssertTrue(pool.tryAcquire())
        pool.release()
    }

    func testBoundedBindingSurvivesNestedHistoryWrapperAndExplicitDetachedBinding() async {
        let lease = BodyBackgroundLease()
        let result = await Task.detached {
            await lease.run {
                await withBackgroundQueryPool {
                    HealthKitQueryPool.current.profileName
                }
            }
        }.value
        XCTAssertEqual(result, "appRefresh")
        XCTAssertEqual(HealthKitQueryPool.current.profileName, "interactive")
    }

    func testLeaseInvalidatesQueuedPublicationWithoutMainActorHop() {
        let lease = BodyBackgroundLease()
        let publication = HealthDashboardPublicationToken(isCurrent: { lease.isValid })
        XCTAssertTrue(publication.isValid)
        lease.invalidate()
        XCTAssertFalse(publication.isValid)
    }

    @MainActor
    func testWarningAndDataAdmissionCannotOverlap() {
        BodyBackgroundAdmission.cancel()
        let first = BodyBackgroundAdmission.acquire(isForegroundActive: false)
        XCTAssertNotNil(first)
        XCTAssertNil(BodyBackgroundAdmission.acquire(isForegroundActive: false))
        first?.invalidate()
        XCTAssertNotNil(BodyBackgroundAdmission.acquire(isForegroundActive: false))
        BodyBackgroundAdmission.cancel()
    }

    func testBackgroundRegistrationIsIndependentAndHeadlessSafe() throws {
        let scheduler = try BodyTestSupport.sourceText(at: "Body/Services/BodyDataRefreshScheduler.swift")
        let app = try BodyTestSupport.sourceText(at: "Body/BodyApp.swift")
        let plist = try BodyTestSupport.sourceText(at: "Body/Info.plist")
        let entitlements = try BodyTestSupport.sourceText(at: "Body/Body.entitlements")
        XCTAssertTrue(plist.contains("com.zihengthedeveloper.Body.dataRefresh"))
        XCTAssertTrue(entitlements.contains("com.apple.developer.healthkit.background-delivery"))
        XCTAssertTrue(app.contains("BodyDataRefreshScheduler.registerTask()"))
        XCTAssertTrue(app.contains("guard scenePhase == .active else { return }"))
        XCTAssertFalse(scheduler.contains("metricWarningNotificationsKey"))
        XCTAssertFalse(scheduler.contains("cancelAllTaskRequests"))
        XCTAssertTrue(scheduler.contains("requests.contains(where:"))
        let warning = try BodyTestSupport.sourceText(at: "Body/Services/MetricWarningBackgroundEvaluator.swift")
        XCTAssertTrue(warning.contains("let work = Task.detached {\n            await lease.run"))
    }
    func testExpirationRacingCompletionFinishesOnceAndFencesPublication() async {
        let finished = expectation(description: "exactly one completion")
        finished.assertForOverFulfill = true
        let completion = BodyDataRefreshScheduler.Completion { _ in finished.fulfill() }
        let lease = BodyBackgroundLease()
        XCTAssertTrue(completion.install(lease))
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 { group.addTask { completion.finish(success: index % 2 == 0) } }
        }
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertFalse(lease.isValid)
        let late = BodyBackgroundLease()
        XCTAssertFalse(completion.install(late))
        XCTAssertFalse(late.isValid)
    }

    func testCancelledDeadlineRaceReturnsWithoutJoiningOperation() async {
        let started = expectation(description: "race started")
        let operation = Task {
            started.fulfill()
            return await OneShotDeadlineRace.run(deadline: .seconds(120)) {
                try? await Task.sleep(for: .milliseconds(200))
                return true
            }
        }
        await fulfillment(of: [started], timeout: 1)
        operation.cancel()
        let outcome = await operation.value
        guard case .timedOut = outcome else { return XCTFail("Cancellation must retire the race") }
    }

    func testNoChangeCompletionIsSuccessAndExpirationStillWins() async {
        let cleanDone = expectation(description: "clean no-op succeeds")
        let clean = BodyDataRefreshScheduler.Completion { success in
            XCTAssertTrue(success)
            cleanDone.fulfill()
        }
        clean.finish(outcome: .finished(false))
        let expiredDone = expectation(description: "expiration wins once")
        expiredDone.assertForOverFulfill = true
        let expired = BodyDataRefreshScheduler.Completion { success in
            XCTAssertFalse(success)
            expiredDone.fulfill()
        }
        expired.finish(success: false)
        expired.finish(outcome: .finished(false))
        let timeoutDone = expectation(description: "timeout fails")
        let timeout = BodyDataRefreshScheduler.Completion { success in
            XCTAssertFalse(success)
            timeoutDone.fulfill()
        }
        timeout.finish(outcome: .timedOut)
        await fulfillment(of: [cleanDone, expiredDone, timeoutDone], timeout: 1)
    }

    func testBothSceneStartupPathsHydrateBeforeSync() throws {
        let app = try BodyTestSupport.sourceText(at: "Body/BodyApp.swift")
        let taskStart = try XCTUnwrap(app.range(of: ".task(priority: .utility)"))
        let activation = try XCTUnwrap(app.range(of: ".onChange(of: scenePhase)"))
        let launch = String(app[taskStart.lowerBound..<activation.lowerBound])
        let hydrate = try XCTUnwrap(launch.range(of: "await workoutStore.hydratePersistedDaySamplesIfNeeded()"))
        let gate = try XCTUnwrap(launch.range(of: "guard scenePhase == .active"))
        XCTAssertLessThan(hydrate.lowerBound, gate.lowerBound)
        let resumed = String(app[activation.upperBound...])
        let resumeHydration = try XCTUnwrap(resumed.range(of: "await workoutStore.hydratePersistedDaySamplesIfNeeded()"))
        let sync = try XCTUnwrap(resumed.range(of: "await workoutStore.syncWhenAppBecomesActive()"))
        XCTAssertLessThan(resumeHydration.lowerBound, sync.lowerBound)
    }

}
