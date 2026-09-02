//
//  HealthKitWorkoutStoreTimeoutTests.swift
//  BodyTests
//

import HealthKit
import XCTest
@testable import Body

final class HealthKitWorkoutStoreTimeoutTests: XCTestCase {

    /// Ring history is out of the refresh's completion barrier: the refresh
    /// stamps success with no ring history at all, and chunks landing afterwards
    /// don't touch anything the refresh owns.
    @MainActor
    func testRefreshStampsSuccessWhileRingHistoryIsStillOutstanding() throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let refreshDate = Date(timeIntervalSince1970: 1_760_000_000)

        store.markRefreshSucceeded(
            date: refreshDate,
            refreshedVitals: true,
            publishesWatch: false,
            advancesSyncBadge: true
        )

        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDate)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)
        XCTAssertFalse(store.needsInitialHealthDataLoad)
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)

        let badgeCountAfterRefresh = store.syncBadgeSuccessCount
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        XCTAssertTrue(
            store.applyActivityRingHistoryChunk(
                activityRingChunk(days: [march5], loadedMonthKeys: [ActivityRingMonthKey(month: 3, year: 2026)]),
                capturedEpoch: 0
            )
        )

        XCTAssertEqual(store.activityRingHistory.days.map(\.date), [march5])
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDate)
        XCTAssertEqual(store.syncBadgeSuccessCount, badgeCountAfterRefresh)
    }

    @MainActor
    func testRefreshWithinTheDeadlineCompletesAndStampsSuccess() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        let refreshDate = Date(timeIntervalSince1970: 1_760_000_000)

        let completed = await store.runRefreshWithDeadline(.seconds(30)) {
            store.markRefreshSucceeded(date: refreshDate, refreshedVitals: true, publishesWatch: false)
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(store.lastSuccessfulRefreshDate, refreshDate)
        XCTAssertTrue(store.hasCompletedInitialHealthDataLoad)
        XCTAssertNil(store.healthDataNotice)
    }

    @MainActor
    func testRefreshDeadlineAbandonsTheBodyWithoutStampingSuccess() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        let lateFinisher = expectation(description: "abandoned refresh body finished")

        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            // The abandoned body keeps running and tries to finish the refresh
            // it no longer speaks for.
            store.markRefreshSucceeded(
                date: Date(),
                refreshedVitals: true,
                publishesWatch: false,
                advancesSyncBadge: true
            )
            lateFinisher.fulfill()
        }

        XCTAssertFalse(completed)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(
            store.healthDataNotice,
            String(localized: "Loading Apple Health data is taking longer than expected. Please try again.")
        )
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)

        await fulfillment(of: [lateFinisher], timeout: 5)

        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
        XCTAssertEqual(store.syncBadgeSuccessCount, 0)
        XCTAssertFalse(HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted())
    }

    /// The per-workout heart-rate reads are continuation based, so
    /// `fetchWorkouts` can return normally minutes after the deadline fired —
    /// long enough for a newer retry to have published the same months.
    @MainActor
    func testAbandonedRefreshCannotPublishMonthSnapshots() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        XCTAssertTrue(store.mayPublishMonthSnapshot(capturedEpoch: 0))

        let lateMonthWrite = expectation(description: "abandoned workout fetch returned")
        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            XCTAssertFalse(store.mayPublishMonthSnapshot(capturedEpoch: 0))
            lateMonthWrite.fulfill()
        }

        XCTAssertFalse(completed)
        await fulfillment(of: [lateMonthWrite], timeout: 5)
        // A newer refresh's own month writes are unaffected.
        XCTAssertTrue(store.mayPublishMonthSnapshot(capturedEpoch: 0))
    }

    /// Same deadline contract on the single-metric pull (the metric detail
    /// screen's own spinner), whose success stamp is the sync badge rather than
    /// the freshness TTL: `refreshHealthMetric` runs its fetch/publish half
    /// through the same wrapper, so a stuck metric query can't strand that
    /// spinner either.
    @MainActor
    func testMetricRefreshDeadlineAbandonsTheBodyWithoutStampingSuccess() async {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let store = emptyHealthDataStore()
        let lateFinisher = expectation(description: "abandoned metric refresh body finished")

        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            store.markRefreshSucceeded(
                date: Date(),
                refreshedVitals: false,
                publishesWatch: false,
                advancesSyncBadge: true
            )
            lateFinisher.fulfill()
        }

        XCTAssertFalse(completed)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertEqual(
            store.healthDataNotice,
            String(localized: "Loading Apple Health data is taking longer than expected. Please try again.")
        )

        await fulfillment(of: [lateFinisher], timeout: 5)

        XCTAssertEqual(store.syncBadgeSuccessCount, 0)
        XCTAssertNil(store.lastSuccessfulRefreshDate)
        XCTAssertFalse(store.hasCompletedInitialHealthDataLoad)
    }

    @MainActor
    func testRefreshCompletionWaiterResumesOnCancellationInsteadOfLeaking() async {
        let waiters = HealthKitWorkoutStore.RefreshCompletionWaiters()
        let parked = Task { @MainActor in await waiters.park() }

        var spins = 0
        while waiters.isEmpty, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertFalse(waiters.isEmpty)

        // Nothing but `finishRefresh` used to resume these, so a cancelled
        // waiter parked its continuation forever.
        parked.cancel()
        await parked.value
        XCTAssertTrue(waiters.isEmpty)

        // And the drain that follows must not resume the same waiter twice.
        waiters.resumeAll()
    }

    @MainActor
    func testRefreshCompletionWaitersResumeWhenTheRefreshFinishes() async {
        let waiters = HealthKitWorkoutStore.RefreshCompletionWaiters()
        let resumed = expectation(description: "waiter resumed")
        Task { @MainActor in
            await waiters.park()
            resumed.fulfill()
        }

        var spins = 0
        while waiters.isEmpty, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertFalse(waiters.isEmpty)

        waiters.resumeAll()
        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertTrue(waiters.isEmpty)
    }

    /// `finishRefresh` resumes every parked waiter at once, so a single park is
    /// not enough: only the first waiter to run can claim the slot, and the
    /// others used to fall straight into the `guard !isRefreshing` in the
    /// refresh entry points and lose their refetch. The helper loops instead.
    @MainActor
    func testRefreshSlotWaitersAllResumeAfterTheSlotIsReleased() async {
        let store = emptyHealthDataStore()

        var first = false
        var second = false
        await store.withRefreshSlotHeld {
            let a = Task { @MainActor in await store.awaitRefreshSlotFree() }
            let b = Task { @MainActor in await store.awaitRefreshSlotFree() }

            // Both are parked on the held slot, so neither has resumed yet.
            var spins = 0
            while spins < 100 {
                await Task.yield()
                spins += 1
            }
            XCTAssertTrue(store.isRefreshing)

            Task { @MainActor in
                first = await a.value
                second = await b.value
            }
        }

        var spins = 0
        while !(first && second), spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertFalse(store.isRefreshing)
    }

    /// A waiter cancelled while parked must report the slot was never won, so
    /// its caller stands down instead of refetching on a dead task.
    @MainActor
    func testCancelledRefreshSlotWaiterReturnsFalseWithoutWaitingForTheSlot() async {
        let store = emptyHealthDataStore()
        let resumed = expectation(description: "cancelled waiter resumed")
        var wonSlot = true

        await store.withRefreshSlotHeld {
            let waiter = Task { @MainActor in
                wonSlot = await store.awaitRefreshSlotFree()
                resumed.fulfill()
            }

            var spins = 0
            while spins < 100 {
                await Task.yield()
                spins += 1
            }
            waiter.cancel()
            await waiter.value
        }

        await fulfillment(of: [resumed], timeout: 5)
        XCTAssertFalse(wonSlot)
    }

    /// The threshold picker fires one change per wheel tick. Each edit must
    /// replace the pending refetch rather than stack another one behind the
    /// running refresh.
    @MainActor
    func testRepeatedWarningThresholdEditsLeaveOneQueuedRefresh() async {
        let store = emptyHealthDataStore()
        XCTAssertFalse(store.hasPendingMetricWarningThresholdRefresh)

        await store.withRefreshSlotHeld {
            store.metricWarningThresholdsDidChange(for: .heartRate)
            XCTAssertTrue(store.hasPendingMetricWarningThresholdRefresh)
            // The second edit cancels the first, so one refetch stays parked on
            // the held slot rather than two.
            store.metricWarningThresholdsDidChange(for: .heartRate)
            XCTAssertTrue(store.hasPendingMetricWarningThresholdRefresh)

            var spins = 0
            while spins < 200 {
                await Task.yield()
                spins += 1
            }
            XCTAssertTrue(store.isRefreshing)
            // Neither edit refetched behind the held slot, and the second's task
            // is the only one still holding the handle.
            XCTAssertEqual(store.syncBadgeSuccessCount, 0)
            XCTAssertTrue(store.hasPendingMetricWarningThresholdRefresh)
        }
    }

    /// Ring history now arrives in chunks that can land long after the refresh
    /// that asked for them was abandoned at its deadline. The chunk must be
    /// refused then, exactly as a month snapshot is, or a stuck query's answer
    /// overwrites what the retry has since published.
    @MainActor
    func testAbandonedRefreshCannotApplyActivityRingHistoryChunk() async throws {
        let restoreDefaults = preserveInitialHealthLoadDefaults()
        defer { restoreDefaults() }

        let calendar = Calendar.bodyGregorian
        let store = activityRingsEnabledStore()
        let march5 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5)))
        let chunk = activityRingChunk(
            days: [march5],
            loadedMonthKeys: [ActivityRingMonthKey(month: 3, year: 2026)]
        )

        let lateChunk = expectation(description: "abandoned ring walk returned")
        let completed = await store.runRefreshWithDeadline(.milliseconds(50)) {
            try? await Task.sleep(for: .seconds(30))
            XCTAssertFalse(store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0))
            lateChunk.fulfill()
        }

        XCTAssertFalse(completed)
        await fulfillment(of: [lateChunk], timeout: 5)
        XCTAssertTrue(store.activityRingHistory.days.isEmpty)
        // The lazy pagination path runs outside a deadline-guarded refresh, so
        // the new guard leaves it alone.
        XCTAssertTrue(store.applyActivityRingHistoryChunk(chunk, capturedEpoch: 0))
    }
}
