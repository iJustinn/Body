//
//  BodyProEntitlementTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Runtime coverage for the shared Body Pro entitlement cache — the App Group flag the
/// widget process and the non-SwiftUI stores (`HealthKitWorkoutStore`,
/// `HealthKitFetchEngine`) read synchronously. The suite-explicit overloads let these run
/// against a throwaway suite, so they never depend on the host's App Group container and
/// never flip real Pro state.
final class BodyProEntitlementTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "BodyTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSetUnlockedPersistsToTheGivenSuite() throws {
        BodyProEntitlement.setUnlocked(false, defaults: defaults)
        XCTAssertFalse(BodyProEntitlement.isUnlocked(defaults: defaults))

        BodyProEntitlement.setUnlocked(true, defaults: defaults)
        XCTAssertTrue(BodyProEntitlement.isUnlocked(defaults: defaults))

        // Prove it landed in the suite another process would read — not a per-instance
        // cache: a freshly resolved suite sees the same value. The key mirrors
        // `BodyProEntitlement.unlockedKey` (private), so this also pins it.
        let freshSuite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(freshSuite.bool(forKey: "bodyProUnlocked"), true)

        BodyProEntitlement.setUnlocked(false, defaults: defaults)
        XCTAssertFalse(BodyProEntitlement.isUnlocked(defaults: defaults))
    }

    func testSetUnlockedPostsNotificationOnlyOnChange() {
        BodyProEntitlement.setUnlocked(false, defaults: defaults)

        var postCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: BodyProEntitlement.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in postCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        BodyProEntitlement.setUnlocked(true, defaults: defaults)   // false → true: changes, posts once
        BodyProEntitlement.setUnlocked(true, defaults: defaults)   // true → true: no change, stays silent
        XCTAssertEqual(postCount, 1)

        BodyProEntitlement.setUnlocked(false, defaults: defaults)  // true → false: changes, posts again
        XCTAssertEqual(postCount, 2)
    }
}
