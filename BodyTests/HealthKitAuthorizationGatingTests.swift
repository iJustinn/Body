//
//  HealthKitAuthorizationGatingTests.swift
//  BodyTests
//
//  Workout-effort *write* permission gating: `.sharingAuthorized` skips the
//  sheet, `.sharingDenied` fails immediately without one, and
//  `.notDetermined` requests one. Covers the pure decision function only —
//  the HealthKit request/verify round trip is exercised by the manual flows
//  in TestPlan.md.
//

import XCTest
import HealthKit
@testable import Body

final class HealthKitAuthorizationGatingTests: XCTestCase {
    func testEffortWriteDecisionForSharingAuthorized() {
        XCTAssertEqual(
            HealthKitFetchEngine.effortWriteDecision(for: .sharingAuthorized),
            .authorized
        )
    }

    func testEffortWriteDecisionForSharingDenied() {
        XCTAssertEqual(
            HealthKitFetchEngine.effortWriteDecision(for: .sharingDenied),
            .denied
        )
    }

    func testEffortWriteDecisionForNotDetermined() {
        XCTAssertEqual(
            HealthKitFetchEngine.effortWriteDecision(for: .notDetermined),
            .prompt
        )
    }
}
