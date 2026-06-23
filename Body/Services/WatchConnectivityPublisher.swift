//
//  WatchConnectivityPublisher.swift
//  Body
//
//  Pushes the latest `WatchMetricsSnapshot` to the paired Apple Watch via
//  `WCSession.updateApplicationContext` — latest-state semantics, delivered in
//  the background and persisted so the watch (and its complications) can read
//  the last value even after a relaunch. Best-effort: never blocks or perturbs
//  the refresh pipeline.
//

import Foundation
import WatchConnectivity
import os

@MainActor
final class WatchConnectivityPublisher: NSObject {
    static let shared = WatchConnectivityPublisher()

    private let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchConnectivity")
    private var pending: WatchMetricsSnapshot?
    private var pendingPreference: (enabled: Bool, revision: Int)?

    private override init() {
        super.init()
    }

    /// Installs the delegate + activates the session at launch so the watch→phone toggle
    /// receiver is present and any queued `transferUserInfo` drains on the next launch,
    /// instead of waiting for the first phone-side `send`.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    /// Sends the snapshot, activating the session lazily on first use. If the
    /// session isn't activated yet the snapshot is queued and flushed from
    /// `activationDidCompleteWith`.
    func send(_ snapshot: WatchMetricsSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        if session.delegate == nil {
            session.delegate = self
        }
        guard session.activationState == .activated else {
            pending = snapshot
            if session.activationState == .notActivated {
                session.activate()
            }
            return
        }

        guard let data = snapshot.encoded() else {
            logger.error("Watch snapshot encode failed.")
            return
        }

        do {
            // Piggyback phone-owned state the watch needs for standalone compute
            // as sibling keys in the SAME context as "snapshot" (a separate
            // context write would drop "snapshot"). Permission + unit/goal/score
            // prefs are one-way phone-authoritative; the standalone toggle is
            // bidirectional and carries a revision (the watch applies it
            // last-writer-wins). Temperature is the phone's RESOLVED unit
            // (followsSystem forced off) so the watch doesn't re-resolve against
            // its own — possibly different — locale.
            let defaults = UserDefaults.standard
            try session.updateApplicationContext([
                "snapshot": data,
                BodyAppearancePreference.healthPermissionSelectionKey: BodyHealthPermissionSelection.load().rawValue,
                BodyAppearancePreference.sleepDurationGoalMinutesKey: BodySleepDurationGoal.storedMinutes(from: defaults.object(forKey: BodyAppearancePreference.sleepDurationGoalMinutesKey) as? Int),
                BodyAppearancePreference.followsSystemUnitsKey: false,
                BodyAppearancePreference.selectedTemperatureUnitKey: HealthWidgetSnapshotBuilder.storedTemperatureUnitPreference().rawValue,
                BodyAppearancePreference.showSleepScoreKey: HealthWidgetSnapshotBuilder.storedShowSleepScore(),
                BodyAppearancePreference.showsSubMinuteAwakeSleepStagesKey: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
                StandaloneComputePreference.messageKey: StandaloneComputePreference.isEnabled(),
                StandaloneComputePreference.revisionMessageKey: StandaloneComputePreference.revision()
            ])
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            pending = snapshot
        }
    }

    /// Sends the standalone-compute toggle to the watch (queued; delivered when
    /// the session activates). Carries a revision so the watch applies it
    /// last-writer-wins.
    func sendStandalonePreference(enabled: Bool, revision: Int) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        guard session.activationState == .activated else {
            // `transferUserInfo` requires an activated session; queue and flush
            // from `activationDidCompleteWith` (a bare send here is dropped).
            pendingPreference = (enabled, revision)
            if session.activationState == .notActivated { session.activate() }
            return
        }
        session.transferUserInfo([
            StandaloneComputePreference.messageKey: enabled,
            StandaloneComputePreference.revisionMessageKey: revision
        ])
        // Also refresh the latest application context so a watch that misses the
        // transfer (or re-pairs) repairs to the current toggle instead of the
        // stale revision left in the last context. Merge onto the last-sent
        // context to keep the snapshot + sibling prefs.
        var context = session.applicationContext
        context[StandaloneComputePreference.messageKey] = enabled
        context[StandaloneComputePreference.revisionMessageKey] = revision
        do {
            try session.updateApplicationContext(context)
        } catch {
            logger.error("updateApplicationContext (toggle) failed: \(error.localizedDescription, privacy: .public)")
            // Mirror the snapshot path: queue for the next activation flush.
            pendingPreference = (enabled, revision)
        }
    }
}

extension WatchConnectivityPublisher: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let pending = self.pending {
                self.pending = nil
                self.send(pending)
            }
            // Clear before re-sending so there's no double-send window.
            if let pendingPreference = self.pendingPreference {
                self.pendingPreference = nil
                self.sendStandalonePreference(enabled: pendingPreference.enabled, revision: pendingPreference.revision)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let parsed = StandaloneComputePreference.parse(userInfo) else { return }
        Task { @MainActor in
            StandaloneComputePreference.applyRemote(enabled: parsed.enabled, revision: parsed.revision)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch keeps receiving context.
        WCSession.default.activate()
    }
}
