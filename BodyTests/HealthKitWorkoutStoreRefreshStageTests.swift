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

    /// A pull during a regular refresh leaves it alone; only a repair or other work
    /// holding the slot gets the badge's busy notice.
    @MainActor
    func testPullWhileBusyNotifiesOnlyForNonRefreshWork() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        store.noteRefreshRequestedWhileBusy()
        XCTAssertNil(store.refreshBusyNoticeID)

        await store.withRefreshSlotHeld(regularRefresh: true) {
            store.noteRefreshRequestedWhileBusy()
            XCTAssertNil(store.refreshBusyNoticeID)
        }
        XCTAssertFalse(store.isRegularRefresh)

        await store.withRefreshSlotHeld {
            store.noteRefreshRequestedWhileBusy()
            XCTAssertNotNil(store.refreshBusyNoticeID)
        }
        // Dismissed the moment the blocking work ends, so the completion confirmation or
        // the next refresh is never hidden behind it.
        XCTAssertNil(store.refreshBusyNoticeID)
    }

    /// Every case needs copy: a new stage without a badge string would render
    /// an empty capsule mid-refresh.
    func testEveryStageHasBadgeText() {
        let stages: [HealthKitWorkoutStore.RefreshStage] = [
            .authorizing, .fetching, .syncing, .updatingHealth, .updatingRings,
            .computing(.readiness), .computing(.stress), .computing(.trainingLoad), .computing(.bodyRadar),
            .writingEffort, .finishing
        ]

        for stage in stages + HealthMetricKind.allCases.map({ .updating($0) }) {
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
