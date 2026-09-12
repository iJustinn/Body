import XCTest
@testable import Body

@MainActor
final class BodyForegroundNotificationSchedulerTests: XCTestCase {
    func testRequestsWaitForEligibilityAndCoalesceWhileRunning() async {
        var eligible = false
        var evaluations = 0
        var resume: CheckedContinuation<Void, Never>?
        let first = expectation(description: "first evaluation")
        let second = expectation(description: "coalesced follow-up")
        let scheduler = BodyForegroundNotificationScheduler(isEligible: { eligible }) { _ in
            evaluations += 1
            if evaluations == 1 {
                await withCheckedContinuation { continuation in
                    resume = continuation
                    first.fulfill()
                }
            } else { second.fulfill() }
        }
        scheduler.request()
        XCTAssertEqual(evaluations, 0)
        eligible = true
        scheduler.request()
        await fulfillment(of: [first], timeout: 2)
        for _ in 0..<20 { scheduler.request() }
        XCTAssertEqual(evaluations, 1)
        resume?.resume()
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(evaluations, 2)
    }

    func testSuspensionImmediatelyRejectsLateSendAndRetainsNextRequest() async {
        var eligible = true
        var resume: CheckedContinuation<Void, Never>?
        var token: HealthDashboardPublicationToken?
        var evaluations = 0
        var sends = 0
        let first = expectation(description: "first read admitted")
        let second = expectation(description: "new read after preemption")
        let scheduler = BodyForegroundNotificationScheduler(isEligible: { eligible }) { authority in
            evaluations += 1
            if evaluations == 1 {
                token = authority
                await withCheckedContinuation { continuation in resume = continuation; first.fulfill() }
                if authority.isValid { sends += 1 }
            } else { second.fulfill() }
        }
        scheduler.request()
        await fulfillment(of: [first], timeout: 2)
        eligible = false
        scheduler.suspend()
        XCTAssertEqual(token?.isValid, false)
        eligible = true
        scheduler.request()
        XCTAssertEqual(evaluations, 1, "A suspended read cannot create another concurrent owner")
        resume?.resume()
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(sends, 0)
    }
}
