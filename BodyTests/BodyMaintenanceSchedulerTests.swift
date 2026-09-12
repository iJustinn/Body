import XCTest
@testable import Body

@MainActor
final class BodyMaintenanceSchedulerTests: XCTestCase {
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var open = false
        func wait() async {
            if !open { await withCheckedContinuation { continuation = $0 } }
        }
        func release() { open = true; continuation?.resume(); continuation = nil }
    }

    func testReadyOwnersRotateWhileOriginalOwnerRemainsAlive() async {
        let scheduler = BodyMaintenanceScheduler(isEligible: { true })
        let gate = Gate()
        let began = expectation(description: "observer holds first unit")
        let queued = expectation(description: "other owners queued")
        queued.expectedFulfillmentCount = BodyMaintenanceScheduler.Owner.allCases.count
        var order: [BodyMaintenanceScheduler.Owner] = []
        let first = Task {
            await scheduler.run(.observer) { _ in
                order.append(.observer)
                began.fulfill()
                await gate.wait()
                return true
            }
        }
        await fulfillment(of: [began], timeout: 1)
        let tasks = BodyMaintenanceScheduler.Owner.allCases.map { owner in
            Task {
                queued.fulfill()
                return await scheduler.run(owner) { _ in order.append(owner); return true }
            }
        }
        await fulfillment(of: [queued], timeout: 1)
        await gate.release()
        _ = await first.value
        for task in tasks { let result = await task.value; XCTAssertTrue(result) }
        XCTAssertEqual(order, [.observer, .journal, .records, .stressInputs, .stressHistory, .ringHistory, .trendHistory, .observer])
        XCTAssertFalse(scheduler.hasActiveUnit)
    }

    func testRetirementRejectsLatePublishAndDoesNotAdmitReplacementUntilExit() async {
        var eligible = true
        let scheduler = BodyMaintenanceScheduler(isEligible: { eligible })
        let gate = Gate()
        let began = expectation(description: "quiet unit started")
        var oldToken: HealthDashboardPublicationToken?
        var latePublish = false
        var replacementStarted = false
        let first = Task {
            await scheduler.run(.observer) { token in
                oldToken = token
                began.fulfill()
                await gate.wait()
                latePublish = token.isValid
                return true
            }
        }
        await fulfillment(of: [began], timeout: 1)
        eligible = false
        scheduler.suspend()
        XCTAssertFalse(oldToken?.isValid ?? true)
        XCTAssertTrue(scheduler.hasActiveUnit)
        eligible = true
        let replacement = Task {
            await scheduler.run(.journal) { _ in replacementStarted = true; return true }
        }
        scheduler.resumeIfEligible()
        XCTAssertFalse(replacementStarted)
        await gate.release()
        let firstResult = await first.value
        let replacementResult = await replacement.value
        XCTAssertFalse(firstResult)
        XCTAssertTrue(replacementResult)
        XCTAssertFalse(latePublish)
    }

    func testCancelledQueuedOwnerNeverRunsOrConsumesNextTurn() async {
        var eligible = false
        let scheduler = BodyMaintenanceScheduler(isEligible: { eligible })
        let entered = expectation(description: "queued")
        var ran = false
        let task = Task {
            entered.fulfill()
            return await scheduler.run(.records) { _ in ran = true; return true }
        }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel()
        let result = await task.value
        eligible = true
        scheduler.resumeIfEligible()
        XCTAssertFalse(result)
        XCTAssertFalse(ran)
        XCTAssertFalse(scheduler.hasActiveUnit)
    }
}
