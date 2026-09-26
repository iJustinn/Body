//
//  WatchComputeEnvironment.swift
//  BodyWatch
//
//  Everything `WatchMetricsModel`'s compute path touches outside its own
//  state, as one injectable value: the stores it checks, HealthKit
//  authorization, the compute itself, the workout change cursor and the
//  background refresh scheduler. `.live` is what the app runs; tests swap in
//  deterministic closures so the pending work rules (a workout saved mid
//  compute, a failed input, a failed save) are exercised without HealthKit.
//

import Foundation
import os
import WatchKit

struct WatchComputeEnvironment {
    /// The phone's permission selection has synced and a compute seed exists.
    var isEligible: @MainActor () -> Bool
    var loadPermission: @MainActor () -> BodyHealthPermissionSelection
    /// Whether the compute read set was already put to the user (see
    /// `WatchHealthStore.isComputeAuthorizationSettled`).
    var isAuthorizationSettled: @Sendable (BodyHealthPermissionSelection) async -> Bool
    var requestAuthorization: @Sendable (BodyHealthPermissionSelection) async -> Void
    var compute: @Sendable (_ permission: BodyHealthPermissionSelection, _ generation: UInt64, _ now: Date) async -> WatchComputeResult?
    var changeTracker: any WatchWorkoutChangeDetecting
    /// Asks watchOS for a background refresh near the given date. Best effort.
    var scheduleBackgroundRefresh: @MainActor (Date) -> Void
    /// Where the pending work record and the last compute attempt stamp are
    /// kept, so a test's isolated suite never touches the app's own defaults.
    var defaults: UserDefaults
    var now: () -> Date

    @MainActor
    static func live(
        healthStore: WatchHealthStore,
        coordinator: WatchComputeCoordinator,
        isEligible: @escaping @MainActor () -> Bool
    ) -> WatchComputeEnvironment {
        WatchComputeEnvironment(
            isEligible: isEligible,
            loadPermission: { BodyHealthPermissionSelection.load() },
            isAuthorizationSettled: { await healthStore.isComputeAuthorizationSettled(for: $0) },
            requestAuthorization: { await healthStore.requestComputeAuthorization(for: $0) },
            compute: { permission, generation, now in
                await coordinator.recompute(permission: permission, generation: generation, now: now)
            },
            changeTracker: WatchWorkoutChangeTracker(),
            scheduleBackgroundRefresh: { date in
                WKApplication.shared().scheduleBackgroundRefresh(
                    withPreferredDate: date, userInfo: nil
                ) { error in
                    // Tells a registration failure apart from watchOS simply
                    // deferring the wake.
                    guard let error else { return }
                    Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchBackgroundRefresh")
                        .error("Background refresh scheduling failed: \(error.localizedDescription, privacy: .public)")
                }
            },
            defaults: .standard,
            now: { Date() }
        )
    }
}
