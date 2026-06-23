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

    private let healthStore = WatchHealthStore()
    private var hasRequestedLiveAuthorization = false
    private var hasRequestedStandaloneAuthorization = false
    private var pendingPreference: (enabled: Bool, revision: Int)?
    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    private override init() {
        snapshot = WatchMetricsSnapshotStore.load() ?? .empty
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
        // Mirror phone-owned compute preferences into the watch's own defaults
        // (independent of snapshot freshness) so the next standalone recompute
        // uses the same inputs as the phone.
        adoptRemoteComputeSettings(context)

        // Standalone toggle: latest-state repair for a watch that missed the
        // transferUserInfo (or re-paired). Apply before the permission adopt so
        // an incoming `off` short-circuits the permission reconcile's heavy work.
        if let parsed = StandaloneComputePreference.parse(context),
           StandaloneComputePreference.applyRemote(enabled: parsed.enabled, revision: parsed.revision, preferIncomingOnTie: true) {
            reconcileStandalone(enabled: parsed.enabled)
        }

        // Permission selection — independent of snapshot freshness, so a
        // permission-only change (or a same-/older-generation snapshot) applies.
        if let rawSelection = context[BodyAppearancePreference.healthPermissionSelectionKey] as? String {
            adoptRemotePermissionSelection(rawSelection)
        }
        guard let data = context["snapshot"] as? Data,
              let received = WatchMetricsSnapshot.decoded(from: data),
              received.generatedAt > snapshot.generatedAt else { return }
        apply(merging(received, preserveMissing: false))
    }

    /// Write-through phone-owned compute preferences (sleep goal, temperature
    /// unit, sleep-score visibility, sub-minute awake stages) into the watch's
    /// own defaults. No reconcile needed — the next standalone recompute reads
    /// them, and the phone snapshot pushed alongside already shows correct values.
    private func adoptRemoteComputeSettings(_ context: [String: Any]) {
        let defaults = UserDefaults.standard
        if let minutes = context[BodyAppearancePreference.sleepDurationGoalMinutesKey] as? Int {
            defaults.set(minutes, forKey: BodyAppearancePreference.sleepDurationGoalMinutesKey)
        }
        if let followsSystem = context[BodyAppearancePreference.followsSystemUnitsKey] as? Bool {
            defaults.set(followsSystem, forKey: BodyAppearancePreference.followsSystemUnitsKey)
        }
        if let unit = context[BodyAppearancePreference.selectedTemperatureUnitKey] as? String {
            defaults.set(unit, forKey: BodyAppearancePreference.selectedTemperatureUnitKey)
        }
        if let showSleepScore = context[BodyAppearancePreference.showSleepScoreKey] as? Bool {
            defaults.set(showSleepScore, forKey: BodyAppearancePreference.showSleepScoreKey)
        }
        if let showsSubMinuteAwake = context[BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey] as? Bool {
            defaults.set(showsSubMinuteAwake, forKey: BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey)
        }
    }

    /// Adopts the phone's health-permission selection (phone-authoritative,
    /// one-way, synced on every push). On a real change: re-request
    /// authorization — the auth latches would otherwise skip newly-enabled
    /// types — and, when standalone compute is on, restart
    /// the observers and recompute so the change lands without a relaunch.
    /// Persisting alone covers the standalone-off case: the phone pushes a
    /// freshly-filtered snapshot alongside this.
    private func adoptRemotePermissionSelection(_ rawValue: String) {
        let key = BodyAppearancePreference.healthPermissionSelectionKey
        guard UserDefaults.standard.string(forKey: key) != rawValue else { return }
        UserDefaults.standard.set(rawValue, forKey: key)

        hasRequestedLiveAuthorization = false
        hasRequestedStandaloneAuthorization = false
        guard WatchStandaloneCompute.isEnabled() else { return }
        // Arm closed-app refresh now that the permission selection has synced —
        // a foregrounded first sync followed by a kill (no background transition)
        // would otherwise leave it unscheduled.
        WatchBackgroundScheduler.scheduleNextRefreshIfEnabled()
        WatchHealthObserver.shared.stop()
        Task {
            // Effort edits made while the observer was stopped (or under the
            // prior permission set) weren't seen, so the effort cache may be
            // stale — drop it before this recompute re-resolves training load.
            await WatchComputeCoordinator.shared.invalidateEffortCache()
            await recomputeStandalone()
            await WatchHealthObserver.shared.startIfEnabled()
        }
    }

    /// Keep locally-measured metrics (live HR/HRV) over the incoming value when
    /// they're still the freshest reading — a workout-only phone refresh re-sends
    /// old vitals, and a watch recompute returns daily-average HR/HRV, neither of
    /// which must roll back a live reading.
    private func merging(_ received: WatchMetricsSnapshot, preserveMissing: Bool) -> WatchMetricsSnapshot {
        let receivedVitalsDate = received.lastRefreshDate ?? .distantPast
        let now = Date()
        var merged = received
        merged.metrics = received.metrics.map { metric in
            guard let local = snapshot.metric(forKind: metric.kind) else { return metric }

            // Preserve a locally-measured live reading (HR/HRV) over the
            // incoming value. On a phone push, keep it when it's newer than the
            // vitals the phone snapshot was built from. On a watch recompute
            // (`preserveMissing`), HR/HRV come back as daily AVERAGES stamped
            // `now` — which would always outrank a live reading by timestamp —
            // so keep a still-fresh live reading (within the stale window)
            // instead of regressing the card to a daily average.
            if let liveUpdatedAt = local.liveUpdatedAt {
                let liveWins = preserveMissing
                    ? now.timeIntervalSince(liveUpdatedAt) < WatchMetricsSnapshot.staleInterval
                    : liveUpdatedAt > receivedVitalsDate
                if liveWins {
                    var kept = metric
                    kept.displayValue = local.displayValue
                    kept.unit = local.unit
                    kept.rawValue = local.rawValue
                    kept.fillFraction = local.fillFraction
                    kept.liveUpdatedAt = local.liveUpdatedAt
                    return kept
                }
            }

            // Don't downgrade a good local value when the incoming metric is
            // blank. Always applies to a watch recompute (`preserveMissing`) —
            // the watch's own gaps must not blank good phone data. For a phone
            // push it applies to every metric EXCEPT readiness: a phone "--"
            // for a fetch-disabled card (BodyDashboardFetchSelection) is not an
            // authoritative clear, whereas readiness is always computed when
            // possible, so a phone readiness "--" means genuinely uncomputable
            // (e.g. Heart revoked) and must clear the stale score instead of
            // resurrecting it. (A revoked permission omits its metric entirely,
            // so readiness — the only always-present metric — is the sole case.)
            let keepWhenBlank = preserveMissing || metric.kind != WatchMetricKindKey.readiness
            if keepWhenBlank, !metric.hasValue, local.hasValue {
                return local
            }

            return metric
        }
        return merged
    }

    private func apply(_ newSnapshot: WatchMetricsSnapshot) {
        snapshot = newSnapshot
        WatchMetricsSnapshotStore.save(newSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Hybrid live refresh

    private var isStale: Bool {
        // The live path refreshes HR/HRV, so staleness tracks THOSE metrics'
        // freshness — a standalone recompute that preserves an old HR/HRV (no
        // auth / no samples) advances the snapshot's `lastRefreshDate` but not
        // the preserved metric's own `computedAt`, so a snapshot-level check
        // would let a stale reading masquerade as fresh and suppress this
        // refresh indefinitely under repeated recomputes.
        let liveFreshness = [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability]
            .compactMap { snapshot.metric(forKind: $0) }
            .compactMap { $0.liveUpdatedAt ?? $0.computedAt }
            .min()
        guard let freshness = liveFreshness ?? snapshot.lastRefreshDate else { return true }
        return Date().timeIntervalSince(freshness) > WatchMetricsSnapshot.staleInterval
    }

    /// Manual dashboard refresh (top-left button): recompute on-watch metrics
    /// — a no-op unless standalone compute is on and the permission selection
    /// has synced — then force a live HR/HRV reading so the tap always lands,
    /// even when the snapshot hasn't crossed the stale window yet.
    func refresh() async {
        await recomputeStandalone()
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
        guard WatchStandaloneCompute.hasSyncedPermissionSelection(),
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

    // MARK: - Standalone compute

    /// Runs the full on-watch recompute (when the toggle is enabled) from the
    /// watch's own HealthKit and applies the result. Invoked on foreground, by
    /// the scheduled background refresh, and by the HealthKit observers.
    func recomputeStandalone() async {
        guard WatchStandaloneCompute.isEnabled(),
              WatchStandaloneCompute.hasSyncedPermissionSelection() else { return }
        if !hasRequestedStandaloneAuthorization {
            hasRequestedStandaloneAuthorization = true
            await healthStore.requestAuthorization()
        }
        guard let computed = await WatchComputeCoordinator.shared.recompute() else { return }
        // The toggle may have flipped off while the recompute was in flight;
        // don't let a late watch result stomp the phone snapshot.
        guard WatchStandaloneCompute.isEnabled() else { return }
        applyComputed(computed)
    }

    private func applyComputed(_ computed: WatchMetricsSnapshot) {
        // The freshly computed snapshot supersedes anything older; a newer phone
        // push (higher generatedAt) still wins on its next delivery. Merge so a
        // metric the watch couldn't compute keeps its prior value and a fresher
        // live HR/HRV reading is preserved.
        guard computed.generatedAt >= snapshot.generatedAt else { return }
        apply(merging(computed, preserveMissing: true))
    }

    // MARK: - Standalone toggle sync

    func sendStandalonePreference(enabled: Bool, revision: Int) {
        let session = WCSession.default
        // Mirror the phone publisher: ensure the delegate is set so
        // `activationDidCompleteWith` fires (and flushes the queue) even when
        // this is the first WatchConnectivity call, before `activate()`.
        if session.delegate == nil { session.delegate = self }
        guard session.activationState == .activated else {
            // `transferUserInfo` needs an activated session; queue and flush
            // from `activationDidCompleteWith`. A bare send here is dropped, and
            // since the local revision was already bumped, the phone's older
            // contexts would then be ignored — leaving the devices out of sync.
            pendingPreference = (enabled, revision)
            if session.activationState == .notActivated { session.activate() }
            return
        }
        session.transferUserInfo([
            StandaloneComputePreference.messageKey: enabled,
            StandaloneComputePreference.revisionMessageKey: revision
        ])
    }

    /// Brings the background machinery in line with the toggle: start observers +
    /// scheduling and recompute once when on; tear them down when off.
    func reconcileStandalone(enabled: Bool) {
        if enabled {
            WatchBackgroundScheduler.scheduleNextRefreshIfEnabled()
            // Recompute first (it authorizes), then start observers — observer
            // setup also authorizes, so this keeps the prompt single and ordered.
            Task {
                // Effort edits made while compute was off weren't observed, so the
                // effort cache may be stale — drop it before the first recompute.
                await WatchComputeCoordinator.shared.invalidateEffortCache()
                await recomputeStandalone()
                await WatchHealthObserver.shared.startIfEnabled()
            }
        } else {
            WatchHealthObserver.shared.stop()
        }
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
            // Flush a toggle queued before activation (clear first so a re-send
            // that re-checks activation can't double-send).
            if let pendingPreference = self.pendingPreference {
                self.pendingPreference = nil
                self.sendStandalonePreference(enabled: pendingPreference.enabled, revision: pendingPreference.revision)
            }
            self.applyReceivedContext(WCSession.default.receivedApplicationContext)
            self.completePendingConnectivityTasksIfDrained()

            // Cold-launch standalone recompute, AFTER adopting the phone's context so it
            // reads synced settings and its fresh `generatedAt` legitimately supersedes —
            // instead of racing `activate()` and rejecting the just-applied phone snapshot.
            // `onChange(of: scenePhase)` misses the initial `.active` and the HK observer
            // only fires on NEW samples, so this is the reliable initial-launch trigger.
            // Self-gates to a no-op pre-sync / when disabled.
            Task { await self.recomputeStandalone() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyReceivedContext(applicationContext)
            self.completePendingConnectivityTasksIfDrained()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            if let parsed = StandaloneComputePreference.parse(userInfo),
               StandaloneComputePreference.applyRemote(enabled: parsed.enabled, revision: parsed.revision, preferIncomingOnTie: true) {
                self.reconcileStandalone(enabled: parsed.enabled)
            }
            // Drain regardless: even an unparseable/stale userInfo is delivered
            // content, so the held WC task must still complete.
            self.completePendingConnectivityTasksIfDrained()
        }
    }
}
