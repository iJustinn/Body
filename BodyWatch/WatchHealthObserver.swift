//
//  WatchHealthObserver.swift
//  BodyWatch
//
//  HealthKit-triggered standalone recompute: observes the sample types that
//  move the scores (HRV, resting HR, sleep, workouts) and recomputes when new
//  data arrives — including in the background via `enableBackgroundDelivery`.
//  Requires the `com.apple.developer.healthkit.background-delivery` entitlement
//  (device only; confirm the capability is offerable for the watch target).
//

import Foundation
import HealthKit
import os

@MainActor
final class WatchHealthObserver {
    static let shared = WatchHealthObserver()

    private let store = HKHealthStore()
    private var queries: [HKObserverQuery] = []
    private var isObserving = false
    // `nonisolated` so the background-queue HealthKit completion closures can log
    // without hopping to the main actor (`Logger` is Sendable).
    private nonisolated let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchObserver")

    /// Only the sample types whose category is enabled in the synced permission
    /// selection — HealthKit read grants persist after a category is hidden, so
    /// a fixed list would keep waking the watch on data the user disabled.
    private var observedTypes: [HKSampleType] {
        let selection = BodyHealthPermissionSelection.load()
        var types: [HKSampleType] = []
        if selection.includes(.heart) {
            types.append(contentsOf: [
                HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
                HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
            ].compactMap { $0 })
        }
        if selection.includes(.sleep), let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.append(sleep)
        }
        if selection.includes(.workouts) {
            types.append(HKObjectType.workoutType())
        }
        return types
    }

    /// Registers observers + background delivery for the score-moving sample
    /// types. Authorizes FIRST: on a fresh install this can run before
    /// authorization is granted, and `enableBackgroundDelivery` would then fail
    /// silently while `isObserving` latched true — blocking every retry. The
    /// `sleepAnalysis` observer is what carries overnight vitals (a new night
    /// triggers a full re-fetch), so these four readiness drivers cover the
    /// overnight inputs; the scheduled refresh backstops the whole-day series.
    func startIfEnabled() async {
        guard WatchStandaloneCompute.isEnabled(),
              WatchStandaloneCompute.hasSyncedPermissionSelection(),
              HKHealthStore.isHealthDataAvailable(),
              !isObserving else { return }

        let read = BodyHealthReadTypes.watchReadObjectTypes(for: BodyHealthPermissionSelection.load())
        if !read.isEmpty {
            try? await store.requestAuthorization(toShare: [], read: read)
        }

        // Re-check after the auth await: a toggle-off (or a concurrent start)
        // during the prompt must not leave observers running on a disabled
        // feature or double-register.
        guard WatchStandaloneCompute.isEnabled(), !isObserving else { return }

        let types = observedTypes
        // Nothing enabled to observe → don't latch; a later re-enable routes
        // through adoptRemotePermissionSelection (stop + startIfEnabled) and
        // re-evaluates the set.
        guard !types.isEmpty else { return }
        isObserving = true

        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, error in
                if let error {
                    self?.logger.error("Observer error: \(error.localizedDescription, privacy: .public)")
                    completionHandler()
                    return
                }
                // Bounded recompute, then signal HealthKit we're done so it keeps
                // delivering. The recompute is intentionally cheap (short windows,
                // no intraday samples) to fit the background budget.
                Task { @MainActor in
                    await WatchMetricsModel.shared.recomputeStandalone()
                    completionHandler()
                }
            }
            store.execute(query)
            queries.append(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { [weak self] _, error in
                if let error {
                    self?.logger.error("enableBackgroundDelivery failed for \(type.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func stop() {
        for query in queries {
            store.stop(query)
        }
        queries.removeAll()
        store.disableAllBackgroundDelivery { _, _ in }
        isObserving = false
    }
}
