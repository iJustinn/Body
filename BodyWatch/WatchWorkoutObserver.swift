//
//  WatchWorkoutObserver.swift
//  BodyWatch
//
//  The one HealthKit observer the watch app runs: workouts and their effort
//  scores, with background delivery, so a workout recorded on the watch can
//  reach readiness and the complications without the app being opened.
//
//  This is BEST EFFORT. watchOS delivers most types at most hourly and bills
//  the wake to the app's background refresh budget, whatever frequency is
//  requested, so nothing here promises a latency. The prompt path is the
//  foreground one (`WatchMetricsModel.recomputeIfStale`).
//
//  Battery: the earlier standalone attempt failed on repeated FULL COMPUTES,
//  not on wakes as such. A wake here costs two anchored queries
//  (`WatchWorkoutChangeTracker`); a compute follows only for a real change,
//  inside `WatchPendingRecomputePolicy`'s attempt budget.
//
//  Every entry point (launch, a finished authorization request, a permission
//  change) goes through `reconcile()`, which runs one pass at a time. That
//  also serializes the one time legacy `disableAllBackgroundDelivery` cleanup
//  ahead of the registration it would otherwise wipe out.
//

import Foundation
import HealthKit

/// The HealthKit half of the observer, behind a seam so the registration
/// ordering can be tested without a health store.
protocol WatchWorkoutObserverBackend: Sendable {
    func disableAllBackgroundDelivery() async -> Bool
    func startObserving(onChange: @escaping @Sendable () async -> Void) async
    func stopObserving() async
}

actor WatchWorkoutObserver {
    static let legacyCleanupKey = "didDisableStandaloneBackgroundDelivery"

    private let backend: any WatchWorkoutObserverBackend
    private let defaults: UserDefaults
    /// Whether the observer should be running right now. Re-read after every
    /// suspension, so a permission change that lands while a registration is
    /// pending resolves to the final state.
    private let isWanted: @Sendable () async -> Bool
    private let onChange: @Sendable () async -> Void

    private var isObserving = false
    private var lastPass: Task<Void, Never>?

    init(
        backend: any WatchWorkoutObserverBackend,
        defaults: UserDefaults = .standard,
        isWanted: @escaping @Sendable () async -> Bool,
        onChange: @escaping @Sendable () async -> Void
    ) {
        self.backend = backend
        self.defaults = defaults
        self.isWanted = isWanted
        self.onChange = onChange
    }

    /// Brings the registration in line with the wanted state. Passes run
    /// strictly one after another, in call order.
    func reconcile() async {
        let previous = lastPass
        let pass = Task {
            await previous?.value
            await self.runPass()
        }
        lastPass = pass
        await pass.value
    }

    private func runPass() async {
        // Installs upgraded from the first standalone build may still hold its
        // background delivery registrations. `disableAllBackgroundDelivery`
        // would take this observer's registration with it, so it runs here,
        // first, and latches only on success so a failure retries next launch.
        if !defaults.bool(forKey: Self.legacyCleanupKey) {
            if await backend.disableAllBackgroundDelivery() {
                defaults.set(true, forKey: Self.legacyCleanupKey)
            }
            // The cleanup wiped any registration this process had made.
            isObserving = false
        }

        // Bounded: each round re-reads the wanted state after its own await.
        for _ in 0..<3 {
            let wanted = await isWanted()
            guard wanted != isObserving else { return }
            if wanted {
                await backend.startObserving(onChange: onChange)
            } else {
                await backend.stopObserving()
            }
            isObserving = wanted
        }
    }

    /// Runs `work` for one observer callback and calls HealthKit's completion
    /// handler exactly once on every path. HealthKit backs off delivery for an
    /// app that leaves callbacks uncompleted, and completing twice is an error.
    nonisolated static func handleUpdate(
        error: Error?,
        work: @escaping @Sendable () async -> Void,
        completion: @escaping () -> Void
    ) {
        guard error == nil else {
            completion()
            return
        }
        // HealthKit's completion handler isn't annotated `Sendable`; it is
        // called once, from this one task.
        nonisolated(unsafe) let completion = completion
        Task {
            await work()
            completion()
        }
    }
}

/// The real HealthKit backend.
actor WatchHealthKitWorkoutObserverBackend: WatchWorkoutObserverBackend {
    private let store = HKHealthStore()
    private var query: HKObserverQuery?

    func disableAllBackgroundDelivery() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return await withCheckedContinuation { continuation in
            store.disableAllBackgroundDelivery { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func startObserving(onChange: @escaping @Sendable () async -> Void) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = WatchWorkoutChangeTracker.trackedTypes
        if query == nil {
            let observer = HKObserverQuery(
                queryDescriptors: types.map { HKQueryDescriptor(sampleType: $0, predicate: nil) }
            ) { _, _, completion, error in
                WatchWorkoutObserver.handleUpdate(error: error, work: onChange, completion: completion)
            }
            store.execute(observer)
            query = observer
        }
        // Re-enabled even for a live query: a retried legacy cleanup wipes the
        // delivery registration without touching the query itself.
        for type in types {
            // `.immediate` is a request, not a guarantee (see the file header).
            try? await store.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
    }

    func stopObserving() async {
        guard let query else { return }
        store.stop(query)
        self.query = nil
        for type in WatchWorkoutChangeTracker.trackedTypes {
            try? await store.disableBackgroundDelivery(for: type)
        }
    }
}
