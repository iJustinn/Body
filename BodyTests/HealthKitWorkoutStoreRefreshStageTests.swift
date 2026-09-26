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

    /// A pull during a regular refresh leaves it alone apart from showing its badge at
    /// once; only a repair or other work holding the slot gets the badge's busy notice.
    @MainActor
    func testPullWhileBusyNotifiesOnlyForNonRefreshWork() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        store.noteRefreshRequestedWhileBusy()
        XCTAssertNil(store.refreshBusyNoticeID)

        await store.withRefreshSlotHeld(regularRefresh: true) {
            XCTAssertFalse(store.syncPresentation.isRevealed)
            store.noteRefreshRequestedWhileBusy()
            XCTAssertNil(store.refreshBusyNoticeID)
            XCTAssertTrue(store.syncPresentation.isRevealed)
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

    /// A refresh the user asks for shows the badge at once; only automatic work waits
    /// out the reveal delay. With no permissions the month refresh sends no queries.
    @MainActor
    func testUserRefreshRevealsTheBadgeAtOnce() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: []), engineHealthStore: FakeHealthStore(), workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        XCTAssertFalse(store.syncPresentation.isRevealed)
        await store.refreshWorkoutMonth(month: 5, year: 2026)
        XCTAssertTrue(store.syncPresentation.isRevealed)
    }

    /// The quick return's current month check is silent: it begins no badge session.
    @MainActor
    func testPassiveResumeWorkoutRefreshAloneNeverReveals() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = HealthKitWorkoutStore(initialMonthSnapshots: [], initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: []), engineHealthStore: FakeHealthStore(), workoutJournalFile: nil)
        store.contextRefreshOverride = { _ in }
        await store.refreshWorkoutMonth(month: 5, year: 2026, intent: .passiveResume)
        XCTAssertFalse(store.syncPresentation.isRevealed)
        XCTAssertEqual(store.syncPresentation.phase, .hidden)
        XCTAssertNil(store.syncPresentation.sessionID)
        XCTAssertFalse(store.isSilentRefresh)
    }

    /// A pull during a silent passive workout refresh gives it a session and shows it at
    /// once. The seam holds the slot with the same flags `refreshWorkoutMonth` sets.
    @MainActor
    func testPullDuringSilentPassiveWorkoutRefreshReveals() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        await store.withRefreshSlotHeld(regularRefresh: true, silent: true) {
            XCTAssertNil(store.syncPresentation.passID)
            XCTAssertFalse(store.showsRefreshActivity)
            store.noteRefreshRequestedWhileBusy()
            XCTAssertNil(store.refreshBusyNoticeID)
            XCTAssertNotNil(store.syncPresentation.passID)
            XCTAssertEqual(store.syncPresentation.phase, .syncing)
            XCTAssertTrue(store.syncPresentation.isRevealed)
            XCTAssertTrue(store.showsRefreshActivity)
        }
        XCTAssertFalse(store.isSilentRefresh)
    }

    /// A pull during a silent repair still gets the busy notice, and begins no session.
    @MainActor
    func testPullDuringSilentRepairStillShowsBusyNotice() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        await store.withRefreshSlotHeld(silent: true) {
            XCTAssertTrue(store.isSilentRefresh)
            store.noteRefreshRequestedWhileBusy()
            XCTAssertNotNil(store.refreshBusyNoticeID)
            XCTAssertNil(store.syncPresentation.passID)
            XCTAssertEqual(store.syncPresentation.phase, .hidden)
            XCTAssertFalse(store.syncPresentation.isRevealed)
        }
        XCTAssertNil(store.refreshBusyNoticeID)
        XCTAssertFalse(store.isSilentRefresh)
    }

    /// Refresh activity cues follow the badge: silent work shows them only once it
    /// owns a pass, which it gets by joining a session already on screen.
    @MainActor
    func testShowsRefreshActivityFollowsTheBadge() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        XCTAssertFalse(store.showsRefreshActivity)
        await store.withRefreshSlotHeld {
            XCTAssertTrue(store.showsRefreshActivity)
        }
        await store.withRefreshSlotHeld(silent: true) {
            XCTAssertTrue(store.isRefreshing)
            XCTAssertFalse(store.showsRefreshActivity)
        }

        var token: UUID?
        await store.withRefreshSlotHeld(regularRefresh: true) {
            store.noteRefreshRequestedWhileBusy()
            token = store.queueForegroundContinuation()
        }
        XCTAssertEqual(store.syncPresentation.phase, .syncing)
        XCTAssertTrue(store.syncPresentation.isRevealed)
        let session = store.syncPresentation.sessionID
        await store.withRefreshSlotHeld(silent: true) {
            XCTAssertEqual(store.syncPresentation.sessionID, session)
            XCTAssertNotNil(store.syncPresentation.passID)
            XCTAssertTrue(store.showsRefreshActivity)
        }
        XCTAssertFalse(store.showsRefreshActivity)
        if let token { store.settleForegroundContinuation(token) }
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
