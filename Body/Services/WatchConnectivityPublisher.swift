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

    private override init() {
        super.init()
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
            try session.updateApplicationContext(["snapshot": data])
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            pending = snapshot
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
            guard let pending = self.pending else { return }
            self.pending = nil
            self.send(pending)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch keeps receiving context.
        WCSession.default.activate()
    }
}
