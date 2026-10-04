//
//  WatchWarningFoldApplyTests.swift
//  BodyTests
//
//  The store's half of the iPhone end of the warning fold sync
//  (`HealthKitWorkoutStore.applyWatchWarningFolds`): it applies the watch's
//  records to the dismissed set and its stamps, and calls the completion (the
//  `sendMessage` reply) exactly once on every path: at once when nothing was
//  accepted or there is nothing to publish yet, else after the direct publish
//  is handed off. The queued copy passes no completion. Each test applies into
//  its own `UserDefaults` suite, so the app's own fold state is never touched;
//  the publish itself still reads the standard defaults, as it does in the app.
//

import XCTest
@testable import Body

@MainActor
final class WatchWarningFoldApplyTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    /// Puts back the first load flag `markRefreshSucceeded` writes to the
    /// standard defaults.
    private var restoreInitialHealthLoad: (() -> Void)?

    override func setUpWithError() throws {
        suiteName = "WatchWarningFoldApplyTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        restoreInitialHealthLoad = preserveInitialHealthLoadDefaults()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        restoreInitialHealthLoad?()
        restoreInitialHealthLoad = nil
        super.tearDown()
    }

    /// A store with no refresh yet, or, with `refreshed`, one whose clean full
    /// refresh just landed: that sets the last vitals refresh, which arms the
    /// publish (Sync Baseline's guard).
    private func makeStore(refreshed: Bool = false) -> HealthKitWorkoutStore {
        let store = HealthKitWorkoutStore(
            initialMonthSnapshots: [],
            initialHealthDashboardSnapshot: .empty,
            initialPermissionSelection: .init(enabledPermissions: [.basics]),
            initialHealthDataSourceSelection: .defaultValue,
            initialSecondaryHealthDataSourceSelection: .defaultValue,
            initialCombinesHealthDataSourcesByName: false,
            initialCustomHealthSourceGroups: [],
            engineHealthStore: FakeHealthStore(),
            workoutJournalFile: nil
        )
        if refreshed {
            store.markRefreshSucceeded(date: Date(), refreshedVitals: true, publishesWatch: false)
        }
        return store
    }

    /// Today's High Heart Rate entry: `applying` keeps only entries inside the
    /// 60 day retention window of the real now, so the day can't be a literal.
    private var todayKey: String {
        let components = Calendar.bodyGregorian.dateComponents([.year, .month, .day], from: Date())
        return String(format: "highHeartRate@%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func record(isFolded: Bool = true, secondsAgo: TimeInterval = 60) -> WatchWarningFoldSync.Record {
        WatchWarningFoldSync.Record(
            key: todayKey,
            isFolded: isFolded,
            changedAt: WatchWarningFoldSync.stamp(now: Date().addingTimeInterval(-secondsAgo), after: nil)
        )
    }

    private var dismissedRaw: String? {
        defaults.string(forKey: BodyAppearancePreference.dismissedMetricWarningsKey)
    }

    private var foldDates: [String: Date] {
        BodyMetricWarningFoldDates.load(defaults: defaults)
    }

    /// Counts completion calls; the store calls it on the main actor.
    private final class Counter: @unchecked Sendable {
        var count = 0
    }

    /// The record the phone already holds (a duplicate delivery, a tie) and an
    /// older one: each completes exactly once, at once, and writes nothing.
    func testATieOrAnOlderRecordCompletesOnceAndChangesNothing() {
        let store = makeStore(refreshed: true)
        let held = record()
        XCTAssertTrue(BodyMetricWarningFoldDates.applying([held], defaults: defaults))
        let dismissedBefore = dismissedRaw
        let datesBefore = foldDates

        for stale in [held, WatchWarningFoldSync.Record(key: held.key, isFolded: false, changedAt: held.changedAt.addingTimeInterval(-1))] {
            let counter = Counter()
            store.applyWatchWarningFolds([stale], defaults: defaults) { counter.count += 1 }

            XCTAssertEqual(counter.count, 1)
            XCTAssertEqual(dismissedRaw, dismissedBefore)
            XCTAssertEqual(foldDates, datesBefore)
        }
    }

    /// Nothing refreshed or restored yet: the fold still lands, and the
    /// completion runs once, at once, with no publish to wait for.
    func testAnAcceptedRecordWithoutARefreshAppliesAndCompletesAtOnce() {
        let store = makeStore()
        let folded = record()
        let counter = Counter()

        store.applyWatchWarningFolds([folded], defaults: defaults) { counter.count += 1 }

        XCTAssertEqual(counter.count, 1)
        XCTAssertTrue(BodyDismissedMetricWarnings.storedValue(from: dismissedRaw ?? "").entries.contains(folded.key))
        XCTAssertEqual(foldDates[folded.key], folded.changedAt)
    }

    /// After a refresh the store publishes directly: the completion
    /// waits for the publish hand off (not called synchronously) and then runs
    /// exactly once.
    func testAnAcceptedRecordCompletesOnceAfterThePublishHandOff() async {
        let store = makeStore(refreshed: true)
        let folded = record()
        let counter = Counter()
        let completed = expectation(description: "completion")

        store.applyWatchWarningFolds([folded], defaults: defaults) {
            counter.count += 1
            completed.fulfill()
        }

        XCTAssertEqual(counter.count, 0, "the completion ran before the publish was handed off")
        XCTAssertTrue(BodyDismissedMetricWarnings.storedValue(from: dismissedRaw ?? "").entries.contains(folded.key))
        await fulfillment(of: [completed], timeout: 10)
        XCTAssertEqual(counter.count, 1)
    }

    /// The queued copy (no completion) applies the same way; the republish it
    /// schedules is the debounced one.
    func testANilCompletionApplies() {
        let store = makeStore(refreshed: true)
        let unfolded = record(isFolded: false)

        store.applyWatchWarningFolds([unfolded], defaults: defaults, completion: nil)
        XCTAssertEqual(foldDates[unfolded.key], unfolded.changedAt)
        XCTAssertFalse(BodyDismissedMetricWarnings.storedValue(from: dismissedRaw ?? "").entries.contains(unfolded.key))

        makeStore().applyWatchWarningFolds([record(secondsAgo: 0)], defaults: defaults, completion: nil)
        XCTAssertTrue(BodyDismissedMetricWarnings.storedValue(from: dismissedRaw ?? "").entries.contains(unfolded.key))
    }
}
