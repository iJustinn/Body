//
//  WatchPendingWorkoutComputeTests.swift
//  BodyWatchTests
//
//  Drives `WatchMetricsModel.recomputeIfStale` through a scripted
//  `WatchComputeEnvironment`, so the workout-change rules are exercised end to
//  end without HealthKit: a detected change bypasses the ordinary compute
//  throttle, and it stays pending until a compute has provably published
//  readiness from it. A run that merely started, that coalesced onto an older
//  run, that failed an input, or whose save failed consumes nothing.
//
//  Dates are fixed and in the past: the model persists its attempt stamp in the
//  host app's real UserDefaults, and a past date can never park it.
//

import XCTest
@testable import BodyWatch

@MainActor
final class WatchPendingWorkoutComputeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - Scripted environment

    private final class Tracker: WatchWorkoutChangeDetecting, @unchecked Sendable {
        var detections: [Bool] = []
        private(set) var detectCalls = 0
        private(set) var commits = 0

        func detectChanges(now: Date) async -> Bool {
            detectCalls += 1
            return detections.isEmpty ? false : detections.removeFirst()
        }

        func commitDetectedChanges() async { commits += 1 }
    }

    private final class Script: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var permission = BodyHealthPermissionSelection.defaultValue
        var authorizationSettled = true
        var saveSucceeds = true
        /// One entry per compute call: whether readiness is stamped, and an
        /// optional coverage override (a run this caller coalesced onto).
        var computes: [(stamped: Bool, coverage: Date?)] = []
        private(set) var computeCalls: [Date] = []
        var authorizationRequests = 0
        var scheduledRefreshes: [Date] = []
        var persisted = 0

        func compute(generation: UInt64, now: Date) -> WatchComputeResult? {
            computeCalls.append(now)
            guard !computes.isEmpty else { return nil }
            let next = computes.removeFirst()
            let coverage = next.coverage ?? now
            var metric = WatchMetric(
                kind: WatchMetricKindKey.readiness,
                title: "Readiness",
                displayValue: "\(60 + computeCalls.count)",
                unit: "%",
                score: 60 + computeCalls.count,
                fillFraction: 0.6,
                rawValue: Double(60 + computeCalls.count)
            )
            metric.computedAt = coverage
            return WatchComputeResult(
                snapshot: WatchMetricsSnapshot(
                    generatedAt: coverage, lastRefreshDate: coverage, metrics: [metric], source: "watch"
                ),
                dataAsOf: next.stamped ? [WatchMetricKindKey.readiness: coverage] : [:],
                coverage: coverage,
                generation: generation
            )
        }
    }

    private func makeModel() -> (WatchMetricsModel, Script, Tracker) {
        let script = Script()
        let tracker = Tracker()
        let suite = "WatchPendingWorkoutComputeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let environment = WatchComputeEnvironment(
            isEligible: { true },
            loadPermission: { script.permission },
            isAuthorizationSettled: { _ in script.authorizationSettled },
            requestAuthorization: { _ in script.authorizationRequests += 1 },
            compute: { _, generation, now in script.compute(generation: generation, now: now) },
            changeTracker: tracker,
            scheduleBackgroundRefresh: { script.scheduledRefreshes.append($0) },
            defaults: defaults,
            now: { script.now }
        )
        let model = WatchMetricsModel(
            persistSnapshot: { _ in
                guard script.saveSucceeds else { return false }
                script.persisted += 1
                return true
            },
            reloadTimelines: {},
            environment: environment
        )
        return (model, script, tracker)
    }

    // MARK: - Detection and consumption

    func testBackgroundTriggerWithNoChangeNeverComputes() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [false]
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(tracker.detectCalls, 1)
        XCTAssertTrue(script.computeCalls.isEmpty, "a background wake is only ever worth a compute for a real change")
    }

    func testDetectedChangeComputesAndIsConsumedOncePublished() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = [(stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)

        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(tracker.commits, 1, "the cursor advances only after the change was recorded as pending")
        XCTAssertEqual(model.pendingWorkForTesting, WatchPendingReadinessWork())
        XCTAssertTrue(script.scheduledRefreshes.isEmpty)
    }

    /// A workout ends at 10:00:00, a foreground compute starts at 10:00:05
    /// before the workout is readable, and its save lands at 10:00:10.
    func testWorkoutSavedAfterAComputeStartedStillGetsItsOwnCompute() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [false, true]
        script.computes = [(stamped: true, coverage: nil), (stamped: true, coverage: nil)]

        script.now = at(5)
        await model.recomputeIfStale(force: true)
        XCTAssertEqual(script.computeCalls, [at(5)])

        script.now = at(10)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [at(5), at(10)], "the earlier attempt must not have used the workout up")
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
    }

    /// The coordinator coalesces same-generation callers, so a trigger can be
    /// handed the result of a run that started before the change was detected.
    func testResultOfAnOlderInFlightRunDoesNotConsumeTheChange() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.now = at(10)
        script.computes = [(stamped: true, coverage: at(5)), (stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)

        XCTAssertEqual(script.computeCalls.count, 2, "reruns instead of waiting out the retry spacing")
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
    }

    func testFailedReadinessInputKeepsTheWorkPendingAndRetriesOnSchedule() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = [(stamped: false, coverage: nil), (stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(model.pendingWorkForTesting.pendingSince, t0)
        XCTAssertEqual(model.pendingWorkForTesting.attempts, 1)
        XCTAssertEqual(script.scheduledRefreshes, [at(WatchPendingRecomputePolicy.minimumSpacing)])

        // Too early: no compute, the retry is simply re-requested.
        script.now = at(60)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls.count, 1)

        // The input recovered by the time the spacing has passed.
        script.now = at(WatchPendingRecomputePolicy.minimumSpacing)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls.count, 2)
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
    }

    func testComputeThatProducedNothingKeepsTheWorkPending() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = []

        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(model.pendingWorkForTesting.pendingSince, t0)
        XCTAssertEqual(script.scheduledRefreshes.count, 1)
    }

    func testFailedSaveDoesNotConsumeTheChange() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = [(stamped: true, coverage: nil), (stamped: true, coverage: nil)]
        script.saveSucceeds = false

        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(model.pendingWorkForTesting.pendingSince, t0, "the complications never saw this value")

        script.saveSucceeds = true
        script.now = at(WatchPendingRecomputePolicy.minimumSpacing)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
        XCTAssertEqual(script.persisted, 1)
    }

    func testRetryBudgetStopsBypassingTheThrottle() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = Array(repeating: (stamped: false, coverage: nil), count: 20)

        for index in 0..<(WatchPendingRecomputePolicy.maximumAttempts + 3) {
            script.now = at(Double(index) * WatchPendingRecomputePolicy.minimumSpacing)
            await model.recomputeIfStale(trigger: .background)
        }
        XCTAssertEqual(script.computeCalls.count, WatchPendingRecomputePolicy.maximumAttempts)
        XCTAssertNotNil(model.pendingWorkForTesting.pendingSince, "left for an ordinary compute to consume")
    }

    // MARK: - Gates

    func testBackgroundTriggerNeverPromptsForAuthorization() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.authorizationSettled = false

        await model.recomputeIfStale(trigger: .background)

        XCTAssertEqual(script.authorizationRequests, 0)
        XCTAssertEqual(tracker.detectCalls, 0)
        XCTAssertTrue(script.computeCalls.isEmpty)
    }

    func testWorkoutsNotPermittedClearsPendingWorkAndSkipsTheTracker() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = [(stamped: false, coverage: nil)]
        await model.recomputeIfStale(trigger: .background)
        XCTAssertNotNil(model.pendingWorkForTesting.pendingSince)

        var permissions = BodyHealthPermissionSelection.defaultValue.enabledPermissions
        permissions.remove(.workouts)
        script.permission = BodyHealthPermissionSelection(enabledPermissions: permissions)
        script.now = at(WatchPendingRecomputePolicy.minimumSpacing)
        await model.recomputeIfStale(trigger: .background)

        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
        XCTAssertEqual(tracker.detectCalls, 1)
        XCTAssertEqual(script.computeCalls.count, 1)
    }

    func testPendingWorkSurvivesARelaunch() async {
        let script = Script()
        let tracker = Tracker()
        let suite = "WatchPendingWorkoutComputeTests.relaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        func environment() -> WatchComputeEnvironment {
            WatchComputeEnvironment(
                isEligible: { true },
                loadPermission: { script.permission },
                isAuthorizationSettled: { _ in true },
                requestAuthorization: { _ in },
                compute: { _, generation, now in script.compute(generation: generation, now: now) },
                changeTracker: tracker,
                scheduleBackgroundRefresh: { _ in },
                defaults: defaults,
                now: { script.now }
            )
        }

        tracker.detections = [true]
        script.computes = [(stamped: false, coverage: nil)]
        let first = WatchMetricsModel(persistSnapshot: { _ in true }, reloadTimelines: {}, environment: environment())
        await first.recomputeIfStale(trigger: .background)

        let relaunched = WatchMetricsModel(persistSnapshot: { _ in true }, reloadTimelines: {}, environment: environment())
        XCTAssertEqual(relaunched.pendingWorkForTesting, first.pendingWorkForTesting)
        XCTAssertEqual(relaunched.pendingWorkForTesting.attempts, 1)
    }
}
