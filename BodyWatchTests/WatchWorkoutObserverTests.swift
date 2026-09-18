//
//  WatchWorkoutObserverTests.swift
//  BodyWatchTests
//
//  Locks the registration ordering of the background workout observer
//  (`WatchWorkoutObserver`) through its backend seam: the one time legacy
//  `disableAllBackgroundDelivery` cleanup always runs BEFORE a registration it
//  would otherwise wipe out, concurrent entry points run one pass at a time, a
//  permission change that lands mid registration resolves to the final state,
//  and an observer callback completes exactly once on every path.
//
//  Delivery itself (latency, cold background launch) can only be verified on a
//  physical watch; see TestPlan.md.
//

import XCTest
@testable import BodyWatch

final class WatchWorkoutObserverTests: XCTestCase {
    private actor Backend: WatchWorkoutObserverBackend {
        private(set) var events: [String] = []
        private var cleanupSucceeds = true
        private var onStart: (@Sendable () async -> Void)?

        func setCleanupSucceeds(_ value: Bool) { cleanupSucceeds = value }
        func setOnStart(_ work: @escaping @Sendable () async -> Void) { onStart = work }

        func disableAllBackgroundDelivery() async -> Bool {
            events.append("cleanup")
            // Yield, so a second entry point gets the chance to interleave.
            await Task.yield()
            return cleanupSucceeds
        }

        func startObserving(onChange: @escaping @Sendable () async -> Void) async {
            events.append("start")
            await onStart?()
        }

        func stopObserving() async {
            events.append("stop")
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(_ value: Bool) { self.value = value }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "WatchWorkoutObserverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeObserver(
        backend: Backend,
        defaults: UserDefaults,
        wanted: Flag
    ) -> WatchWorkoutObserver {
        WatchWorkoutObserver(backend: backend, defaults: defaults, isWanted: { wanted.get() }, onChange: {})
    }

    // MARK: - Registration

    func testLegacyCleanupRunsOnceAndBeforeRegistration() async {
        let backend = Backend()
        let defaults = makeDefaults()
        let observer = makeObserver(backend: backend, defaults: defaults, wanted: Flag(true))

        await observer.reconcile()
        await observer.reconcile()

        let events = await backend.events
        XCTAssertEqual(events, ["cleanup", "start"])
        XCTAssertTrue(defaults.bool(forKey: WatchWorkoutObserver.legacyCleanupKey))
    }

    /// A relaunch of an already configured install: the latch is set, so the
    /// observer is simply executing again, with no cleanup and no prompt.
    func testColdLaunchOfAConfiguredInstallRegistersStraightAway() async {
        let backend = Backend()
        let defaults = makeDefaults()
        defaults.set(true, forKey: WatchWorkoutObserver.legacyCleanupKey)

        await makeObserver(backend: backend, defaults: defaults, wanted: Flag(true)).reconcile()

        let events = await backend.events
        XCTAssertEqual(events, ["start"])
    }

    func testNothingIsRegisteredWhileAuthorizationIsStillNeeded() async {
        let backend = Backend()
        let defaults = makeDefaults()
        defaults.set(true, forKey: WatchWorkoutObserver.legacyCleanupKey)
        let wanted = Flag(false)
        let observer = makeObserver(backend: backend, defaults: defaults, wanted: wanted)

        await observer.reconcile()
        var events = await backend.events
        XCTAssertEqual(events, [])

        // The first foreground authorization request finished.
        wanted.set(true)
        await observer.reconcile()
        events = await backend.events
        XCTAssertEqual(events, ["start"])
    }

    func testFailedLegacyCleanupRetriesAndReRegisters() async {
        let backend = Backend()
        await backend.setCleanupSucceeds(false)
        let defaults = makeDefaults()
        let observer = makeObserver(backend: backend, defaults: defaults, wanted: Flag(true))

        await observer.reconcile()
        XCTAssertFalse(defaults.bool(forKey: WatchWorkoutObserver.legacyCleanupKey))

        await backend.setCleanupSucceeds(true)
        await observer.reconcile()

        let events = await backend.events
        XCTAssertEqual(
            events, ["cleanup", "start", "cleanup", "start"],
            "a retried cleanup wipes the delivery registration, so it is made again"
        )
    }

    func testConcurrentEntryPointsRunOnePassAtATime() async {
        let backend = Backend()
        let defaults = makeDefaults()
        let observer = makeObserver(backend: backend, defaults: defaults, wanted: Flag(true))

        // Launch, a finished authorization request and a permission sync can
        // all land within the same second.
        async let first: Void = observer.reconcile()
        async let second: Void = observer.reconcile()
        async let third: Void = observer.reconcile()
        _ = await (first, second, third)

        let events = await backend.events
        XCTAssertEqual(events, ["cleanup", "start"], "the cleanup can never land after a registration")
    }

    func testPermissionChangeDuringRegistrationResolvesToTheFinalState() async {
        let backend = Backend()
        let defaults = makeDefaults()
        defaults.set(true, forKey: WatchWorkoutObserver.legacyCleanupKey)
        let wanted = Flag(true)
        // Workouts is turned off on the phone while the registration is in flight.
        await backend.setOnStart { wanted.set(false) }

        await makeObserver(backend: backend, defaults: defaults, wanted: wanted).reconcile()

        let events = await backend.events
        XCTAssertEqual(events, ["start", "stop"])
    }

    func testTurningWorkoutsOffStopsTheObserver() async {
        let backend = Backend()
        let defaults = makeDefaults()
        defaults.set(true, forKey: WatchWorkoutObserver.legacyCleanupKey)
        let wanted = Flag(true)
        let observer = makeObserver(backend: backend, defaults: defaults, wanted: wanted)

        await observer.reconcile()
        wanted.set(false)
        await observer.reconcile()
        await observer.reconcile()

        let events = await backend.events
        XCTAssertEqual(events, ["start", "stop"])
    }

    // MARK: - Callback completion

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    func testCallbackCompletesExactlyOnceAfterItsWork() async {
        let completions = Counter()
        let work = Counter()
        let done = expectation(description: "completion")

        WatchWorkoutObserver.handleUpdate(
            error: nil,
            work: {
                XCTAssertEqual(completions.value, 0, "HealthKit is told only once the work is finished")
                work.increment()
            },
            completion: {
                completions.increment()
                done.fulfill()
            }
        )
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(work.value, 1)
        XCTAssertEqual(completions.value, 1)
    }

    func testCallbackWithAnErrorCompletesWithoutRunningTheWork() {
        let completions = Counter()
        let work = Counter()

        WatchWorkoutObserver.handleUpdate(
            error: NSError(domain: "HKErrorDomain", code: 1),
            work: { work.increment() },
            completion: { completions.increment() }
        )

        XCTAssertEqual(completions.value, 1)
        XCTAssertEqual(work.value, 0)
    }

    func testDuplicateCallbacksEachCompleteOnce() async {
        let completions = Counter()
        let done = expectation(description: "completions")
        done.expectedFulfillmentCount = 3

        for _ in 0..<3 {
            WatchWorkoutObserver.handleUpdate(error: nil, work: {}, completion: {
                completions.increment()
                done.fulfill()
            })
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(completions.value, 3)
    }
}
