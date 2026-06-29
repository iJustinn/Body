//
//  BodyProEntitlementTests.swift
//  BodyTests
//

import XCTest
@testable import Body

/// Runtime coverage for the shared Body Pro entitlement cache — the App Group flag the
/// widget process and the non-SwiftUI stores (`HealthKitWorkoutStore`,
/// `HealthKitFetchEngine`) read synchronously. The StoreKit purchase flow itself needs
/// StoreKitTest + a running store, but persistence and the value-guarded change
/// notification are plain UserDefaults logic and run here in the hosted test target.
final class BodyProEntitlementTests: XCTestCase {
    private var originalValue = false

    override func setUpWithError() throws {
        // The host app (Body.app) carries the App Group entitlement, so the shared suite
        // is the real container here. Skip cleanly if some other harness lacks it rather
        // than failing on an environment issue.
        try XCTSkipUnless(
            UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier) != nil,
            "App Group suite unavailable in this test host"
        )
        originalValue = BodyProEntitlement.isUnlocked
    }

    override func tearDown() {
        // Restore whatever the device/simulator had so a test run never flips real Pro state.
        BodyProEntitlement.setUnlocked(originalValue)
        super.tearDown()
    }

    func testSetUnlockedPersistsToSharedAppGroupSuite() throws {
        BodyProEntitlement.setUnlocked(false)
        XCTAssertFalse(BodyProEntitlement.isUnlocked)

        BodyProEntitlement.setUnlocked(true)
        XCTAssertTrue(BodyProEntitlement.isUnlocked)

        // Prove it landed in the App Group container the widget process reads — not a
        // per-instance cache: a freshly resolved suite sees the same value. The key
        // mirrors `BodyProEntitlement.unlockedKey` (private), so this also pins it.
        let freshSuite = UserDefaults(suiteName: WorkoutSnapshotStore.appGroupIdentifier)
        XCTAssertEqual(freshSuite?.bool(forKey: "bodyProUnlocked"), true)

        BodyProEntitlement.setUnlocked(false)
        XCTAssertFalse(BodyProEntitlement.isUnlocked)
    }

    func testSetUnlockedPostsNotificationOnlyOnChange() {
        BodyProEntitlement.setUnlocked(false)

        var postCount = 0
        let token = NotificationCenter.default.addObserver(
            forName: BodyProEntitlement.didChangeNotification,
            object: nil,
            queue: nil
        ) { _ in postCount += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        BodyProEntitlement.setUnlocked(true)   // false → true: changes, posts once
        BodyProEntitlement.setUnlocked(true)   // true → true: no change, stays silent
        XCTAssertEqual(postCount, 1)

        BodyProEntitlement.setUnlocked(false)  // true → false: changes, posts again
        XCTAssertEqual(postCount, 2)
    }
}
