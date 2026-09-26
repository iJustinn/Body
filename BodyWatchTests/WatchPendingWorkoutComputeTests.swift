//
//  WatchPendingWorkoutComputeTests.swift
//  BodyWatchTests
//
//  Drives `WatchMetricsModel.recomputeIfStale` through a scripted
//  `WatchComputeEnvironment`, so the compute rules are exercised end to end
//  without HealthKit:
//
//  * A detected workout change bypasses the ordinary compute throttle, and it
//    stays pending until a compute has provably published readiness from it. A
//    run that merely started, that coalesced onto an older run, that failed an
//    input, or whose save failed consumes nothing.
//  * A background trigger (the workout observer, a pushed context, the hourly
//    wake) also runs an ORDINARY compute when the display is stale, under the
//    same 30 minute attempt throttle, and never raises an authorization sheet.
//  * The model keeps one background wake requested: an hour out, or pending
//    work's earlier retry, and a throttled trigger never postpones it.
//
//  Every model gets its own UserDefaults suite (`environment.defaults`), which
//  holds both the pending work record and the attempt stamp, so no test reads
//  or writes the host app's own defaults. The display starts from an explicit
//  `.empty` snapshot rather than whatever the host's snapshot cache holds.
//  Dates are fixed and in the past, and the injected clock (`Script.now`) is the
//  only clock the model consults, including the init time check that drops a
//  future dated attempt stamp.
//

import WatchConnectivity
import XCTest
@testable import BodyWatch

@MainActor
final class WatchPendingWorkoutComputeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
    private var hour: TimeInterval { WatchMetricsModel.backgroundRefreshInterval }
    private var spacing: TimeInterval { WatchPendingRecomputePolicy.minimumSpacing }
    private let attemptStampKey = "watchLastComputeAttemptDate"

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

    /// Parks a compute until the test opens it, so a caller can observe the
    /// model while the compute is still suspended.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var parked = false

        var isParked: Bool { lock.withLock { parked } }

        func park() async {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    parked = true
                }
            }
        }

        func open() {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume()
        }
    }

    private final class Script: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var permission = BodyHealthPermissionSelection.defaultValue
        var authorizationSettled = true
        var saveSucceeds = true
        /// One entry per compute call: whether readiness is stamped, and an
        /// optional coverage override (a run this caller coalesced onto).
        var computes: [(stamped: Bool, coverage: Date?)] = []
        /// When set, every compute parks on it before producing its result.
        var gate: Gate?
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

    /// A fresh, isolated defaults suite, removed at teardown.
    private func makeDefaults() -> UserDefaults {
        let suite = "WatchPendingWorkoutComputeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// A model over `defaults` (a new suite when nil), showing an empty
    /// snapshot. `persisted` is reset after the empty snapshot is applied, so it
    /// only counts compute saves.
    private func makeModel(
        script: Script = Script(),
        tracker: Tracker = Tracker(),
        defaults: UserDefaults? = nil
    ) -> (WatchMetricsModel, Script, Tracker) {
        let environment = WatchComputeEnvironment(
            isEligible: { true },
            loadPermission: { script.permission },
            isAuthorizationSettled: { _ in script.authorizationSettled },
            requestAuthorization: { _ in script.authorizationRequests += 1 },
            compute: { _, generation, now in
                if let gate = script.gate { await gate.park() }
                return script.compute(generation: generation, now: now)
            },
            changeTracker: tracker,
            scheduleBackgroundRefresh: { script.scheduledRefreshes.append($0) },
            defaults: defaults ?? makeDefaults(),
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
        model.applyForTesting(.empty)
        script.persisted = 0
        return (model, script, tracker)
    }

    /// Polls the main actor until `condition` holds or the timeout passes.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Ordinary background compute

    func testBackgroundTriggerWithStaleDisplayRunsAnOrdinaryCompute() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [false]
        script.computes = [(stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)

        XCTAssertEqual(tracker.detectCalls, 1)
        XCTAssertEqual(script.computeCalls, [t0], "a stale display is worth a compute on a background wake too")
        XCTAssertEqual(script.persisted, 1)
        XCTAssertEqual(model.pendingWorkForTesting, WatchPendingReadinessWork())
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])
        XCTAssertFalse(model.hasPendingRetryTimerForTesting)
    }

    func testThrottledBackgroundTriggerDoesNotPostponeTheOutstandingWake() async {
        let (model, script, _) = makeModel()
        script.computes = [(stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])

        // A push ten minutes later: inside the attempt throttle, so no compute,
        // and the wake already requested for t0 + 1h must not move to t0 + 70m.
        script.now = at(600)
        await model.recomputeIfStale(trigger: .background)
        await model.recomputeIfStale()
        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])
    }

    func testOrdinaryNilResultStillSchedulesAndStaysThrottled() async {
        let (model, script, _) = makeModel()
        script.computes = []

        // Foreground, so the only scheduling is the nil result exit.
        await model.recomputeIfStale()
        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])

        script.now = at(600)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [t0], "a run that produced nothing still counts as the attempt")
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])

        script.now = at(WatchMetricsSnapshot.staleInterval + 1)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [t0, at(WatchMetricsSnapshot.staleInterval + 1)])
    }

    func testForegroundAndBackgroundTriggersAtTheSameInstantMakeOneOrdinaryAttempt() async {
        let (model, script, _) = makeModel()
        script.computes = [(stamped: true, coverage: nil), (stamped: true, coverage: nil)]

        async let foreground: Void = model.recomputeIfStale()
        async let background: Void = model.recomputeIfStale(trigger: .background)
        _ = await (foreground, background)

        XCTAssertEqual(script.computeCalls, [t0], "the attempt stamp is set before either trigger suspends on the compute")
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])
    }

    // MARK: - Detection and consumption

    func testDetectedChangeComputesAndIsConsumedOncePublished() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = [(stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)

        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(tracker.commits, 1, "the cursor advances only after the change was recorded as pending")
        XCTAssertEqual(model.pendingWorkForTesting, WatchPendingReadinessWork())
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)], "consumed work leaves only the hourly wake")
        XCTAssertFalse(model.hasPendingRetryTimerForTesting)
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
        // The hourly wake armed at the start of the trigger, then pulled in to
        // the pending work's five minute retry.
        XCTAssertEqual(script.scheduledRefreshes, [at(hour), at(spacing)])
        XCTAssertTrue(model.hasPendingRetryTimerForTesting)

        // Too early: no compute, and the retry already requested stands.
        script.now = at(60)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls.count, 1)
        XCTAssertEqual(script.scheduledRefreshes, [at(hour), at(spacing)])
        XCTAssertTrue(model.hasPendingRetryTimerForTesting)

        // The input recovered by the time the spacing has passed. Consuming the
        // work swaps the retry for the next hourly wake and disarms the timer.
        script.now = at(spacing)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls.count, 2)
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
        XCTAssertEqual(script.scheduledRefreshes, [at(hour), at(spacing), at(spacing + hour)])
        XCTAssertFalse(model.hasPendingRetryTimerForTesting)
    }

    func testComputeThatProducedNothingKeepsTheWorkPending() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = []

        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(model.pendingWorkForTesting.pendingSince, t0)
        XCTAssertEqual(script.scheduledRefreshes, [at(hour), at(spacing)])
    }

    func testFailedSaveDoesNotConsumeTheChange() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = [(stamped: true, coverage: nil), (stamped: true, coverage: nil)]
        script.saveSucceeds = false

        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(model.pendingWorkForTesting.pendingSince, t0, "the complications never saw this value")

        script.saveSucceeds = true
        script.now = at(spacing)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
        XCTAssertEqual(script.persisted, 1)
    }

    func testRetryBudgetStopsBypassingTheThrottle() async {
        let (model, script, tracker) = makeModel()
        tracker.detections = [true]
        script.computes = Array(repeating: (stamped: false, coverage: nil), count: WatchPendingRecomputePolicy.maximumAttempts)
            + [(stamped: true, coverage: nil)]

        // Through minute 40: the six bypass attempts (minutes 0 to 25), then
        // nothing, because the last attempt's stamp still throttles.
        for index in 0..<(WatchPendingRecomputePolicy.maximumAttempts + 3) {
            script.now = at(Double(index) * spacing)
            await model.recomputeIfStale(trigger: .background)
        }
        XCTAssertEqual(script.computeCalls.count, WatchPendingRecomputePolicy.maximumAttempts)
        XCTAssertNotNil(model.pendingWorkForTesting.pendingSince, "left for an ordinary compute to consume")
        XCTAssertFalse(model.hasPendingRetryTimerForTesting, "an exhausted budget arms no retry")

        // Minute 54: still inside 30 minutes of the minute 25 attempt.
        script.now = at(54 * 60)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls.count, WatchPendingRecomputePolicy.maximumAttempts)

        // Minute 56: the throttle has lapsed, so an ordinary background compute
        // runs and, having published readiness, consumes the work.
        script.now = at(56 * 60)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls.count, WatchPendingRecomputePolicy.maximumAttempts + 1)
        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
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
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)], "the hourly wake is armed before the authorization check")
    }

    func testUnsettledAuthorizationSkipsComputeButKeepsTheHourlyWake() async {
        let (model, script, tracker) = makeModel()
        script.authorizationSettled = false
        script.computes = [(stamped: true, coverage: nil)]

        await model.recomputeIfStale(trigger: .background)
        XCTAssertTrue(script.computeCalls.isEmpty)
        XCTAssertEqual(script.authorizationRequests, 0)
        XCTAssertEqual(tracker.detectCalls, 0)
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])

        // Settled by a later foreground open: the next wake computes, since the
        // skipped one never stamped an attempt.
        script.authorizationSettled = true
        script.now = at(60)
        await model.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [at(60)])
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)])
    }

    func testIneligibleWatchNeitherReadsNorSchedules() async {
        let script = Script()
        let tracker = Tracker()
        let environment = WatchComputeEnvironment(
            isEligible: { false },
            loadPermission: { script.permission },
            isAuthorizationSettled: { _ in script.authorizationSettled },
            requestAuthorization: { _ in script.authorizationRequests += 1 },
            compute: { _, generation, now in script.compute(generation: generation, now: now) },
            changeTracker: tracker,
            scheduleBackgroundRefresh: { script.scheduledRefreshes.append($0) },
            defaults: makeDefaults(),
            now: { script.now }
        )
        let model = WatchMetricsModel(persistSnapshot: { _ in true }, reloadTimelines: {}, environment: environment)
        model.applyForTesting(.empty)

        await model.recomputeIfStale(trigger: .background)
        await model.recomputeIfStale()

        XCTAssertEqual(tracker.detectCalls, 0)
        XCTAssertTrue(script.computeCalls.isEmpty)
        XCTAssertEqual(script.authorizationRequests, 0)
        XCTAssertTrue(script.scheduledRefreshes.isEmpty, "no seed yet: the push that delivers one schedules")
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
        script.now = at(spacing)
        await model.recomputeIfStale(trigger: .background)

        XCTAssertNil(model.pendingWorkForTesting.pendingSince)
        XCTAssertEqual(tracker.detectCalls, 1)
        XCTAssertEqual(script.computeCalls.count, 1)
        XCTAssertFalse(model.hasPendingRetryTimerForTesting, "cleared work disarms its retry timer")
    }

    // MARK: - Relaunch and persistence

    func testPendingWorkSurvivesARelaunch() async {
        let script = Script()
        let tracker = Tracker()
        let defaults = makeDefaults()

        tracker.detections = [true]
        script.computes = [(stamped: false, coverage: nil)]
        let (first, _, _) = makeModel(script: script, tracker: tracker, defaults: defaults)
        await first.recomputeIfStale(trigger: .background)

        let (relaunched, _, _) = makeModel(script: script, tracker: tracker, defaults: defaults)
        XCTAssertEqual(relaunched.pendingWorkForTesting, first.pendingWorkForTesting)
        XCTAssertEqual(relaunched.pendingWorkForTesting.attempts, 1)
    }

    func testAttemptStampSurvivesARelaunchOnTheSameSuite() async {
        let script = Script()
        let defaults = makeDefaults()
        script.computes = [(stamped: true, coverage: nil), (stamped: true, coverage: nil)]

        let (first, _, _) = makeModel(script: script, defaults: defaults)
        await first.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(defaults.object(forKey: attemptStampKey) as? Double, t0.timeIntervalSinceReferenceDate)

        // Evicted and relaunched ten minutes later: the stamp still throttles.
        script.now = at(600)
        let (relaunched, _, _) = makeModel(script: script, defaults: defaults)
        await relaunched.recomputeIfStale(trigger: .background)
        await relaunched.recomputeIfStale()
        XCTAssertEqual(script.computeCalls, [t0], "eviction must not bypass the attempt throttle")
    }

    func testAttemptStampDoesNotLeakIntoAnotherSuite() async {
        let script = Script()
        script.computes = [(stamped: true, coverage: nil), (stamped: true, coverage: nil)]

        let (first, _, _) = makeModel(script: script)
        await first.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [t0])

        script.now = at(600)
        let (other, _, _) = makeModel(script: script)
        await other.recomputeIfStale(trigger: .background)
        XCTAssertEqual(script.computeCalls, [t0, at(600)])
        XCTAssertNotEqual(
            UserDefaults.standard.object(forKey: attemptStampKey) as? Double,
            t0.timeIntervalSinceReferenceDate,
            "the app's own defaults never receive a test's stamp"
        )
    }

    /// Judged by the INJECTED clock: `t0 + 10m` is in the past by the real
    /// clock, so a check against `Date()` would restore it and the trigger at
    /// `t0 + 15m` would be throttled.
    func testFutureAttemptStampIsDroppedOnInit() async {
        let script = Script()
        let defaults = makeDefaults()
        defaults.set(at(600).timeIntervalSinceReferenceDate, forKey: attemptStampKey)
        script.computes = [(stamped: true, coverage: nil)]

        let (model, _, _) = makeModel(script: script, defaults: defaults)
        script.now = at(900)
        await model.recomputeIfStale(trigger: .background)

        XCTAssertEqual(script.computeCalls, [at(900)], "a stamp from the future is not restored")
    }

    // MARK: - Push lifetime

    func testDrainRequiresNoQueuedContextNoPushComputeAndADrainedSession() {
        XCTAssertTrue(WatchMetricsModel.isDrained(contextsInFlight: 0, pushComputesInFlight: 0, sessionDrained: true))
        XCTAssertFalse(WatchMetricsModel.isDrained(contextsInFlight: 1, pushComputesInFlight: 0, sessionDrained: true))
        XCTAssertFalse(
            WatchMetricsModel.isDrained(contextsInFlight: 0, pushComputesInFlight: 1, sessionDrained: true),
            "a push triggered compute still running holds the background task"
        )
        XCTAssertFalse(WatchMetricsModel.isDrained(contextsInFlight: 0, pushComputesInFlight: 0, sessionDrained: false))
        XCTAssertFalse(WatchMetricsModel.isDrained(contextsInFlight: 2, pushComputesInFlight: 3, sessionDrained: false))
    }

    /// An empty context keeps the prior seed and snapshot, so the only effect
    /// of the push is the background compute it starts.
    func testPushTriggeredComputeIsCountedUntilItReturns() async {
        let (model, script, _) = makeModel()
        let gate = Gate()
        script.gate = gate
        script.computes = [(stamped: true, coverage: nil)]
        XCTAssertEqual(model.pushComputesInFlightForTesting, 0)

        model.session(WCSession.default, didReceiveApplicationContext: [:])
        await waitUntil { gate.isParked }
        XCTAssertTrue(gate.isParked, "the push started a compute")
        XCTAssertEqual(
            model.pushComputesInFlightForTesting, 1,
            "the intake has drained, but the compute the push woke the app for has not returned"
        )

        gate.open()
        await waitUntil { model.pushComputesInFlightForTesting == 0 }
        XCTAssertEqual(model.pushComputesInFlightForTesting, 0)
        XCTAssertEqual(script.computeCalls, [t0])
        XCTAssertEqual(script.persisted, 1)
        XCTAssertEqual(script.scheduledRefreshes, [at(hour)], "the push armed the hourly wake")
    }
}
