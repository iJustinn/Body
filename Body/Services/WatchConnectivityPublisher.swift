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
    // The snapshot plus the permission value AND capture sequence it was queued
    // with, held for the activation-retry resend so the retry ships the paired
    // (not a newer) value and re-enters `send` with its ORIGINAL sequence — a
    // fresh sequence would let the retry outrank a newer publish.
    private var pending: (snapshot: WatchMetricsSnapshot, permissionRawValue: String?, captureSequence: UInt64)?
    // Publisher-owned monotonic capture counter. Allocated by the store at its
    // main-actor capture point (`nextCaptureSequence()`) so sequence order equals
    // capture order, and living on this process-wide singleton so it survives a
    // store re-creation. `lastQueued…` is the highest sequence that has passed
    // the drop gate.
    private var captureSequenceCounter: UInt64 = 0
    private var lastQueuedCaptureSequence: UInt64 = 0
    private let revisionAllocator = WatchRevisionAllocator()

    private override init() {
        super.init()
    }

    /// The next monotonic capture sequence, advanced on each call. The store
    /// requests one at the point it captures a snapshot (where `now` is stamped)
    /// so the sequence orders publishes by CAPTURE order — clock-immune, unlike
    /// the wall-clock `generatedAt`. Process-local: never encoded in the payload
    /// (the watch orders on `publisherEpoch`/`revision` instead), so it can't skew
    /// across the phone/watch boundary.
    func nextCaptureSequence() -> UInt64 {
        captureSequenceCounter += 1
        return captureSequenceCounter
    }

    /// The pure send-gate decision, factored out so it's unit-testable without a
    /// live `WCSession`: a snapshot may be queued only when its capture sequence
    /// is at least the highest already queued. `>=` (not `>`) lets the
    /// activation-retry resend its ORIGINAL sequence. Ordering rides on the
    /// monotonic capture sequence, never the wall clock (M5) — so this takes no
    /// `generatedAt`: a newer clock can't rescue a lower sequence, and a backward
    /// clock can't suppress an advancing one.
    nonisolated static func shouldQueue(captureSequence: UInt64, afterLastQueued lastQueued: UInt64) -> Bool {
        captureSequence >= lastQueued
    }

    /// Installs the delegate + activates the session at launch so the latest
    /// application context is ready and the first snapshot push doesn't have to
    /// queue for activation.
    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    /// Sends the snapshot, activating the session lazily on first use. If the
    /// session isn't activated yet the snapshot is queued and flushed from
    /// `activationDidCompleteWith`. `captureSequence` is the publisher-owned
    /// monotonic sequence the store allocated at capture time (see
    /// `nextCaptureSequence()`); it orders publishes independently of the device
    /// clock.
    func send(_ snapshot: WatchMetricsSnapshot, permissionRawValue: String?, captureSequence: UInt64) {
        guard WCSession.isSupported() else { return }
        // Drop a snapshot whose off-actor build lost the FIFO race with a newer
        // one already queued. Ordering rides on the publisher-owned monotonic
        // capture sequence (allocated at the store's main-actor capture point, in
        // capture order) rather than the wall clock — so a device-clock rollback
        // can't suppress every later publish the way a `generatedAt` gate would.
        // (The watch-side ordering still rides on `publisherEpoch`/`revision`.)
        // `>=` (not `>`) lets the pending activation-retry resend the same
        // snapshot with its original sequence.
        guard Self.shouldQueue(captureSequence: captureSequence, afterLastQueued: lastQueuedCaptureSequence) else { return }
        lastQueuedCaptureSequence = captureSequence

        // Stamp the monotonic (epoch, revision) pair the watch uses to order
        // snapshots without trusting the device clock — but only for a fresh
        // build. The activation-retry resend already carries its pair (epoch set)
        // and must ship unchanged so it doesn't outrank itself on the watch.
        let outgoing = snapshot.publisherEpoch == nil
            ? revisionAllocator.stamped(snapshot)
            : snapshot

        let session = WCSession.default

        if session.delegate == nil {
            session.delegate = self
        }
        guard session.activationState == .activated else {
            pending = (outgoing, permissionRawValue, captureSequence)
            if session.activationState == .notActivated {
                session.activate()
            }
            return
        }

        guard let data = outgoing.encoded() else {
            logger.error("Watch snapshot encode failed.")
            return
        }

        do {
            // Push the snapshot plus the phone's health-permission selection as
            // sibling keys in the SAME context (a separate context write would
            // drop "snapshot"). The watch needs the selection to gate its live
            // HR/HRV reads; every displayed value is already baked into the
            // snapshot by the phone. The selection is captured alongside the
            // snapshot so a queued build can't pair with a newer selection. A nil
            // selection (e.g. a Clear-Cache reset) omits the key rather than
            // clearing the last-synced one.
            var context: [String: Any] = ["snapshot": data]
            if let permissionRawValue {
                context[BodyAppearancePreference.healthPermissionSelectionKey] = permissionRawValue
            }
            try session.updateApplicationContext(context)
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            pending = (outgoing, permissionRawValue, captureSequence)
        }
    }
}

/// Phone-side allocator for the `(publisherEpoch, revision)` pair the watch uses
/// to order snapshots without trusting the device clock (see
/// `WatchMetricsSnapshot.supersedes`). The epoch is a UUID minted once per install
/// and persisted; the revision is a monotonic counter advanced on every publish.
/// Both live in phone `UserDefaults`, so they survive relaunch and the epoch is
/// regenerated only when defaults are cleared — a reinstall / data reset, which is
/// exactly when the watch should treat an incoming snapshot as a fresh install.
struct WatchRevisionAllocator {
    private let defaults: UserDefaults
    private static let epochKey = "watchPublisherEpoch"
    private static let revisionKey = "watchPublisherRevision"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// This install's epoch, minting + persisting one on first use.
    func epoch() -> String {
        if let existing = defaults.string(forKey: Self.epochKey) { return existing }
        let epoch = UUID().uuidString
        defaults.set(epoch, forKey: Self.epochKey)
        return epoch
    }

    /// The next monotonic revision, advancing + persisting the counter. Starts at
    /// 1 (a never-published install reads 0 from the missing default).
    func nextRevision() -> UInt64 {
        let next = defaults.integer(forKey: Self.revisionKey) + 1
        defaults.set(next, forKey: Self.revisionKey)
        return UInt64(next)
    }

    /// A freshly-built snapshot stamped with this install's epoch and the next
    /// monotonic revision. Call once per publish.
    func stamped(_ snapshot: WatchMetricsSnapshot) -> WatchMetricsSnapshot {
        var stamped = snapshot
        stamped.publisherEpoch = epoch()
        stamped.revision = nextRevision()
        return stamped
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
                // Resend with the ORIGINAL capture sequence so the retry can't
                // outrank a publish that arrived while activation was pending.
                self.send(
                    pending.snapshot,
                    permissionRawValue: pending.permissionRawValue,
                    captureSequence: pending.captureSequence
                )
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a newly paired watch keeps receiving context.
        WCSession.default.activate()
    }
}
