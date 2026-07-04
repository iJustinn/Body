//
//  WatchMetricsModel.swift
//  BodyWatch
//
//  Single source of truth on the watch: receives the iPhone's pushed snapshot
//  over WatchConnectivity, caches it for the complications, and runs the hybrid
//  live HR/HRV refresh when the pushed data is stale.
//

import Foundation
import SwiftUI
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
final class WatchMetricsModel: NSObject, ObservableObject {
    static let shared = WatchMetricsModel()

    @Published private(set) var snapshot: WatchMetricsSnapshot
    /// Metric kinds the user hid from the watch dashboard (a watch-local display
    /// preference — see the visibility section below).
    @Published private(set) var hiddenMetricKinds: Set<String>

    private let healthStore = WatchHealthStore()
    private var hasRequestedLiveAuthorization = false
    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    private override init() {
        snapshot = WatchMetricsSnapshotStore.load() ?? .empty
        hiddenMetricKinds = Self.loadHiddenMetricKinds()
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func onAppear() {
        if let stored = WatchMetricsSnapshotStore.load(), stored.generatedAt >= snapshot.generatedAt {
            snapshot = stored
        }
        Task { await refreshLiveMetricsIfStale() }
    }

    // MARK: - WatchConnectivity intake

    private func applyReceivedContext(_ context: [String: Any]) {
        // Permission selection — independent of snapshot freshness, so a
        // permission-only change (or a same-/older-generation snapshot) applies.
        // This also opens the live-read gate: the watch's HR/HRV path reads
        // HealthKit only after the phone's selection has synced at least once.
        if let rawSelection = context[BodyAppearancePreference.healthPermissionSelectionKey] as? String {
            adoptRemotePermissionSelection(rawSelection)
        }
        guard let data = context["snapshot"] as? Data,
              let received = WatchMetricsSnapshot.decoded(from: data),
              received.generatedAt > snapshot.generatedAt else { return }
        apply(merging(received))
    }

    /// Adopts the phone's health-permission selection (phone-authoritative,
    /// one-way, synced on every push). On a real change, reset the live-auth
    /// latch so a newly-enabled Heart type is re-requested on the next live
    /// HR/HRV refresh. Persisting also opens the live-read gate
    /// (`hasSyncedPermissionSelection`): until the phone's selection has synced
    /// at least once the watch must not read HealthKit, since
    /// `BodyHealthPermissionSelection.load()` would otherwise fall back to
    /// all-enabled and could read categories the user hid on the phone.
    private func adoptRemotePermissionSelection(_ rawValue: String) {
        let key = BodyAppearancePreference.healthPermissionSelectionKey
        guard UserDefaults.standard.string(forKey: key) != rawValue else { return }
        UserDefaults.standard.set(rawValue, forKey: key)
        hasRequestedLiveAuthorization = false
    }

    /// The live HR/HRV path reads HealthKit only after the phone's permission
    /// selection has synced at least once (see `adoptRemotePermissionSelection`).
    private static func hasSyncedPermissionSelection(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: BodyAppearancePreference.healthPermissionSelectionKey) != nil
    }

    /// Keep a locally-measured live reading (HR/HRV) over the incoming value
    /// when it's still the freshest — a workout-only phone refresh re-sends old
    /// vitals, which must not roll back a live reading.
    private func merging(_ received: WatchMetricsSnapshot) -> WatchMetricsSnapshot {
        let receivedVitalsDate = received.lastRefreshDate ?? .distantPast
        var merged = received
        merged.metrics = received.metrics.map { metric in
            guard let local = snapshot.metric(forKind: metric.kind) else { return metric }

            // Preserve a locally-measured live reading (HR/HRV) over the incoming
            // value when it's newer than the vitals the phone snapshot was built
            // from.
            if let liveUpdatedAt = local.liveUpdatedAt, liveUpdatedAt > receivedVitalsDate {
                var kept = metric
                kept.displayValue = local.displayValue
                kept.unit = local.unit
                kept.rawValue = local.rawValue
                kept.fillFraction = local.fillFraction
                kept.liveUpdatedAt = local.liveUpdatedAt
                return kept
            }

            // Don't downgrade a good local value when the incoming metric is
            // blank — for every metric EXCEPT readiness: a phone "--" for a
            // fetch-disabled card (BodyDashboardFetchSelection) is not an
            // authoritative clear, whereas readiness is always computed when
            // possible, so a phone readiness "--" means genuinely uncomputable
            // (e.g. Heart revoked) and must clear the stale score instead of
            // resurrecting it. (A revoked permission omits its metric entirely,
            // so readiness — the only always-present metric — is the sole case.)
            if metric.kind != WatchMetricKindKey.readiness, !metric.hasValue, local.hasValue {
                return local
            }

            return metric
        }
        return merged
    }

    private func apply(_ newSnapshot: WatchMetricsSnapshot) {
        snapshot = newSnapshot
        if WatchMetricsSnapshotStore.save(newSnapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Dashboard metric visibility (watch-local)

    private static let hiddenMetricKindsKey = "watchHiddenMetricKinds"

    /// Whether a metric kind is shown on the watch dashboard. Visibility is a
    /// watch-local display preference and never touches the pushed snapshot, so a
    /// hidden metric stays in `snapshot` and can be turned back on.
    func isMetricVisible(_ kind: String) -> Bool {
        !hiddenMetricKinds.contains(kind)
    }

    func setMetric(_ kind: String, visible: Bool) {
        if visible {
            hiddenMetricKinds.remove(kind)
        } else {
            hiddenMetricKinds.insert(kind)
        }
        UserDefaults.standard.set(
            hiddenMetricKinds.sorted().joined(separator: ","),
            forKey: Self.hiddenMetricKindsKey
        )
    }

    private static func loadHiddenMetricKinds(defaults: UserDefaults = .standard) -> Set<String> {
        guard let raw = defaults.string(forKey: hiddenMetricKindsKey), !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").map(String.init))
    }

    // MARK: - Hybrid live refresh

    private var isStale: Bool {
        // The live path refreshes HR/HRV, so staleness tracks THOSE metrics'
        // freshness (their `liveUpdatedAt`, else the value's `computedAt`) rather
        // than the snapshot-level `lastRefreshDate`: a phone push can carry an
        // older HR/HRV under a fresh snapshot timestamp, and a snapshot-level
        // check would then suppress this refresh while the vitals on screen are
        // stale.
        let liveFreshness = [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability]
            .compactMap { snapshot.metric(forKind: $0) }
            .compactMap { $0.liveUpdatedAt ?? $0.computedAt }
            .min()
        guard let freshness = liveFreshness ?? snapshot.lastRefreshDate else { return true }
        return Date().timeIntervalSince(freshness) > WatchMetricsSnapshot.staleInterval
    }

    /// Manual dashboard refresh (top-left button): force a live HR/HRV reading
    /// so the tap always lands, even when the snapshot hasn't crossed the stale
    /// window yet. Readiness / Sleep / Training Load come from the iPhone push.
    func refresh() async {
        await refreshLiveMetrics(force: true)
    }

    /// When the pushed snapshot is stale, refresh the watch-measurable metrics
    /// (HR, HRV) directly and recompute their fill against the carried range.
    func refreshLiveMetricsIfStale() async {
        await refreshLiveMetrics(force: false)
    }

    private func refreshLiveMetrics(force: Bool) async {
        // Gate on sync + Heart: the live path reads HR/HRV directly, and
        // HealthKit read grants persist, so a synced watch with Heart disabled
        // (or an unsynced watch defaulting to all-enabled) would otherwise read
        // data the user hid on the phone.
        guard Self.hasSyncedPermissionSelection(),
              BodyHealthPermissionSelection.load().includes(.heart),
              force || isStale, !snapshot.metrics.isEmpty else { return }

        if !hasRequestedLiveAuthorization {
            hasRequestedLiveAuthorization = true
            await healthStore.requestLiveAuthorization()
        }

        async let heartRateReading = healthStore.latestHeartRate()
        async let hrvReading = healthStore.latestHRV()
        let (heartRate, hrv) = await (heartRateReading, hrvReading)
        guard heartRate != nil || hrv != nil else { return }

        var metrics = snapshot.metrics
        if let heartRate {
            metrics = updating(metrics, kind: WatchMetricKindKey.heartRate, value: heartRate, decimals: 0, unit: "bpm")
        }
        if let hrv {
            metrics = updating(metrics, kind: WatchMetricKindKey.heartRateVariability, value: hrv, decimals: 0, unit: "ms")
        }

        // Don't advance `generatedAt` on a local live refresh: a newer phone
        // snapshot (higher generatedAt) must still win so Readiness / Sleep /
        // Training Load aren't frozen behind a watch-only HR/HRV update.
        var updated = snapshot
        updated.metrics = metrics
        apply(updated)
    }

    private func updating(_ metrics: [WatchMetric], kind: String, value: Double, decimals: Int, unit: String) -> [WatchMetric] {
        guard let index = metrics.firstIndex(where: { $0.kind == kind }) else { return metrics }
        var result = metrics
        var metric = result[index]
        metric.displayValue = WatchValueFormat.number(value, decimals: decimals)
        metric.unit = unit
        metric.rawValue = value
        metric.fillFraction = WatchRingFill.fraction(of: value, min: metric.rangeMin, max: metric.rangeMax)
        metric.liveUpdatedAt = Date()
        result[index] = metric
        return result
    }

    // MARK: - WatchConnectivity background tasks

    /// Holds a WatchConnectivity background-refresh task open until the session
    /// has delivered its pending content, then completes it. Completing it
    /// immediately (the old `handle` default) let watchOS suspend before
    /// `didReceiveApplicationContext`/`didReceiveUserInfo` fired, so a phone push
    /// to a closed watch was missed until the app was next opened. The expiration
    /// handler is the watchOS budget backstop — every background task must be
    /// completed even if the session never reports the content drained.
    func handleConnectivityBackgroundTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        task.expirationHandler = { [weak self, weak task] in
            Task { @MainActor in
                guard let task else { return }
                self?.finishConnectivityTask(task)
            }
        }
        pendingConnectivityTasks.append(task)
        completePendingConnectivityTasksIfDrained()
    }

    /// Completes held WC tasks once the session is activated and has drained all
    /// pending content. Re-invoked from each WC delegate callback so the tasks
    /// end as soon as delivery finishes.
    private func completePendingConnectivityTasksIfDrained() {
        guard !pendingConnectivityTasks.isEmpty else { return }
        if WCSession.isSupported() {
            let session = WCSession.default
            guard session.activationState == .activated, !session.hasContentPending else { return }
        }
        finishAllConnectivityTasks()
    }

    private func finishConnectivityTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        guard let index = pendingConnectivityTasks.firstIndex(where: { $0 === task }) else { return }
        pendingConnectivityTasks.remove(at: index)
        task.setTaskCompletedWithSnapshot(false)
    }

    private func finishAllConnectivityTasks() {
        pendingConnectivityTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        pendingConnectivityTasks.removeAll()
    }
}

extension WatchMetricsModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Cold start: `receivedApplicationContext` is only populated once
        // activation completes, so adopt a context delivered while the app
        // wasn't running here rather than inline after `activate()`.
        Task { @MainActor in
            guard activationState == .activated else {
                // Activation didn't succeed — complete any held WC tasks so they
                // don't strand (every background task must be completed).
                self.finishAllConnectivityTasks()
                return
            }
            self.applyReceivedContext(WCSession.default.receivedApplicationContext)
            self.completePendingConnectivityTasksIfDrained()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyReceivedContext(applicationContext)
            self.completePendingConnectivityTasksIfDrained()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // The phone no longer sends userInfo, but any delivered payload still
        // counts as content, so a held WC background task must complete.
        Task { @MainActor in
            self.completePendingConnectivityTasksIfDrained()
        }
    }
}
