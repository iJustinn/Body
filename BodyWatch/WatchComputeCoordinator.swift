//
//  WatchComputeCoordinator.swift
//  BodyWatch
//
//  Drives the standalone watch recompute: read the watch's own HealthKit via
//  `WatchHealthFetcher`, run the shared calculators (readiness, sleep, training
//  load), cache the assembled dashboard, and produce the compact
//  `WatchMetricsSnapshot` the app + complications render. Concurrent callers
//  (a scheduled refresh and a HealthKit observer firing at once) coalesce onto a
//  single in-flight recompute.
//

import Foundation

actor WatchComputeCoordinator {
    static let shared = WatchComputeCoordinator()

    private let fetcher: WatchHealthFetcher
    private var inFlight: Task<WatchMetricsSnapshot?, Never>?

    init(fetcher: WatchHealthFetcher = WatchHealthFetcher()) {
        self.fetcher = fetcher
    }

    /// Full standalone recompute → cached dashboard + a fresh `WatchMetricsSnapshot`.
    /// Returns `nil` only if the fetch yields nothing usable.
    func recompute(now: Date = Date()) async -> WatchMetricsSnapshot? {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<WatchMetricsSnapshot?, Never> { [self] in
            await performRecompute(now: now)
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    /// Clears the fetcher's effort cache. Called when a `workoutEffortScore`
    /// observer fires so the recompute it triggers re-resolves training load
    /// instead of reusing a now-stale cached effort.
    func invalidateEffortCache() async {
        await fetcher.invalidateEffortCache()
    }

    private func performRecompute(now: Date) async -> WatchMetricsSnapshot? {
        let calendar = Calendar.bodyGregorian
        let permission = BodyHealthPermissionSelection.load(defaults: .standard)
        let idealSleepDuration = Self.idealSleepDuration()

        let assembled = await fetcher.assembleDashboard(permission: permission, calendar: calendar, now: now)
        let dashboard = assembled
            .filteredWithoutReadinessRecompute(by: permission)
            .recalculatingReadiness(on: now, idealSleepDuration: idealSleepDuration, calendar: calendar)

        let showSleepScore = UserDefaults.standard.object(forKey: BodyAppearancePreference.showSleepScoreKey) as? Bool ?? true
        var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: dashboard.summary,
            trends: dashboard.trends,
            lastRefreshDate: now,
            permissionSelection: permission,
            temperatureUnitPreference: WatchUnitPreference.temperature(),
            idealSleepDuration: idealSleepDuration,
            showSleepScore: showSleepScore,
            now: now
        )
        snapshot.source = "watch"

        // No authorized/usable samples → every metric is a `--` placeholder. Returning the
        // stamped snapshot would advance `generatedAt` and reject a still-pending,
        // data-bearing (but older) phone push. Honor the documented "nil when nothing
        // usable" contract so the prior snapshot — and its timestamp — stand.
        guard snapshot.metrics.contains(where: { $0.hasValue }) else { return nil }

        WatchDashboardSnapshotStore.save(dashboard)
        return snapshot
    }

    static func idealSleepDuration(defaults: UserDefaults = .standard) -> TimeInterval {
        let storedMinutes = defaults.object(forKey: BodyAppearancePreference.sleepDurationGoalMinutesKey) as? Int
        return BodySleepDurationGoal.duration(from: BodySleepDurationGoal.storedMinutes(from: storedMinutes))
    }
}

/// The standalone-compute toggle, synced from the phone (default OFF). When OFF
/// the watch reverts to display + live HR/HRV only — no recompute, no observers,
/// no scheduled background refresh.
enum WatchStandaloneCompute {
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        StandaloneComputePreference.isEnabled(defaults)
    }

    /// The watch reads HealthKit only after the phone's permission selection has
    /// synced at least once. Until then `BodyHealthPermissionSelection.load()`
    /// falls back to all-enabled and could read categories hidden on the phone;
    /// the first received context saves the key (opening the gate) and starts
    /// the machinery via `adoptRemotePermissionSelection`.
    static func hasSyncedPermissionSelection(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: BodyAppearancePreference.healthPermissionSelectionKey) != nil
    }
}

/// Watch-local unit resolution mirroring the iOS `storedTemperatureUnitPreference`
/// (the iOS resolver lives in a Body-only file). The synced value is written to
/// the watch's own `UserDefaults` by the settings sync; absent that, follow the
/// system locale.
enum WatchUnitPreference {
    static func temperature(defaults: UserDefaults = .standard) -> BodyValueFormat.TemperatureUnitPreference {
        let followsSystem = defaults.object(forKey: BodyAppearancePreference.followsSystemUnitsKey) as? Bool ?? true
        if followsSystem {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }
        let rawValue = defaults.string(forKey: BodyAppearancePreference.selectedTemperatureUnitKey)
            ?? BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: rawValue)
    }
}
