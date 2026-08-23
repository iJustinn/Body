//
//  HealthKitAuthorizationDenialTests.swift
//  BodyTests
//
//  Denial-vs-failure classification for HealthKit errors. Characteristic reads
//  and activity-summary descriptors THROW when a read permission is off, and
//  that denial is a confirmed absence: it must not be treated as a query
//  failure, which would withhold the freshness TTL and leave the first-launch
//  overlay up forever.
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitAuthorizationDenialTests: XCTestCase {
    private func hkError(_ code: HKError.Code) -> Error {
        NSError(domain: HKErrorDomain, code: code.rawValue)
    }

    func testAuthorizationDeniedIsDenial() {
        XCTAssertTrue(HealthKitFetchEngine.isAuthorizationDenial(hkError(.errorAuthorizationDenied)))
    }

    func testAuthorizationNotDeterminedIsDenial() {
        XCTAssertTrue(HealthKitFetchEngine.isAuthorizationDenial(hkError(.errorAuthorizationNotDetermined)))
    }

    func testNoDataIsNotDenial() {
        XCTAssertFalse(HealthKitFetchEngine.isAuthorizationDenial(hkError(.errorNoData)))
    }

    func testDatabaseInaccessibleIsNotDenial() {
        XCTAssertFalse(HealthKitFetchEngine.isAuthorizationDenial(hkError(.errorDatabaseInaccessible)))
    }

    func testGenericErrorIsNotDenial() {
        let error = NSError(domain: "com.zihengthedeveloper.Body.test", code: HKError.Code.errorAuthorizationDenied.rawValue)
        XCTAssertFalse(HealthKitFetchEngine.isAuthorizationDenial(error))
    }
}
