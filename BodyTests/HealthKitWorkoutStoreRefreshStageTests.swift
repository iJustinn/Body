//
//  HealthKitWorkoutStoreRefreshStageTests.swift
//  BodyTests
//

import SwiftUI
import XCTest
@testable import Body

/// The sync badge's stage signal: the store publishes a phase only while a
/// refresh is actually running, and every phase has badge copy.
final class HealthKitWorkoutStoreRefreshStageTests: XCTestCase {
    @MainActor
    func testRefreshStageIsNilWhileIdle() {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        XCTAssertNil(store.refreshStage)
    }

    /// Holding the slot marks the store refreshing without entering any phase,
    /// so the badge falls back to its default rather than showing a stale one.
    @MainActor
    func testHeldRefreshSlotLeavesTheStageNil() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        await store.withRefreshSlotHeld {
            XCTAssertTrue(store.isRefreshing)
            XCTAssertNil(store.refreshStage)
        }

        XCTAssertFalse(store.isRefreshing)
        XCTAssertNil(store.refreshStage)
    }

    /// Every case needs copy: a new stage without a badge string would render
    /// an empty capsule mid-refresh.
    func testEveryStageHasBadgeText() {
        let stages: [HealthKitWorkoutStore.RefreshStage] = [
            .authorizing, .fetching, .computing, .writingEffort, .finishing
        ]

        for stage in stages {
            XCTAssertNotEqual(stage.badgeText, "", "\(stage) has no badge text")
        }

        // Two phases sharing one string would make the badge look stuck.
        for (index, stage) in stages.enumerated() {
            for other in stages[(index + 1)...] {
                XCTAssertNotEqual(stage.badgeText, other.badgeText, "\(stage) and \(other) share badge text")
            }
        }

        // The common phase keeps the original badge copy, so an ordinary
        // refresh reads exactly as it did before stages existed.
        XCTAssertEqual(HealthKitWorkoutStore.RefreshStage.fetching.badgeText, "Loading data...")
    }
}
