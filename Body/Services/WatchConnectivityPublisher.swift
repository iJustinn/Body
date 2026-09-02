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
    // The snapshot plus the permission value, capture sequence, AND compute
    // seed it was queued with, held for the activation-retry resend so the
    // retry ships the paired (not a newer) value and re-enters `send` with its
    // ORIGINAL sequence — a fresh sequence would let the retry outrank a newer
    // publish.
    private var pending: (
        snapshot: WatchMetricsSnapshot,
        permissionRawValue: String?,
        captureSequence: UInt64,
        computeSeedData: Data?,
        computeSeedSettingsSignature: String?
    )?
    /// Whole-context serialized-size budget for the WatchConnectivity push
    /// (display snapshot + permission key + compute seed, together) —
    /// `updateApplicationContext` has no documented ceiling, so this stays
    /// comfortably under the empirically safe range. The compute seed is the
    /// large, optional piece, so it's what gets dropped when the total would
    /// exceed this; the always-required display snapshot still ships.
    nonisolated static let contextSizeBudgetBytes = 60_000
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

    /// The pure whole-context budget decision, factored out so it's
    /// unit-testable without a live `WCSession`: the compute seed is included
    /// only when the total context size (display snapshot + permission key +
    /// seed) fits the budget. The always-required display snapshot is never
    /// the thing dropped — only the optional seed is at risk, so a caller that
    /// finds this `false` simply omits the seed key and sends the rest
    /// unchanged.
    nonisolated static func shouldIncludeComputeSeed(
        snapshotSize: Int,
        permissionSize: Int,
        seedSize: Int,
        budget: Int = contextSizeBudgetBytes
    ) -> Bool {
        snapshotSize + permissionSize + seedSize <= budget
    }

    /// The two context dictionaries a send may use: `primary` (with the seed,
    /// when one was supplied and fit the budget) and `fallback` (the same
    /// context minus the seed, used only for the size-driven retry below).
    /// Pure + static so the exact key set of both shapes is unit-testable
    /// without a live `WCSession`.
    nonisolated static func contexts(
        snapshotData: Data,
        permissionRawValue: String?,
        seedData: Data?,
        seedSettingsSignature: String?
    ) -> (primary: [String: Any], fallback: [String: Any]) {
        // Push the snapshot plus the phone's health-permission selection as
        // sibling keys in the SAME context (a separate context write would
        // drop "snapshot"). The watch needs the selection to gate its live
        // HR/HRV reads; every displayed value is already baked into the
        // snapshot by the phone. A nil selection (e.g. a Clear-Cache reset)
        // omits the key rather than clearing the last-synced one.
        var fallback: [String: Any] = ["snapshot": snapshotData]
        if let permissionRawValue {
            fallback[BodyAppearancePreference.healthPermissionSelectionKey] = permissionRawValue
        }
        // The settings signature rides in BOTH shapes — its whole purpose is to
        // survive the seed blob being dropped for size, so the watch can still
        // detect that its stored seed was built under superseded settings.
        if let seedSettingsSignature {
            fallback[WatchComputeSeed.applicationContextSettingsSignatureKey] = seedSettingsSignature
        }
        var primary = fallback
        if let seedData {
            primary[WatchComputeSeed.applicationContextKey] = seedData
        }
        return (primary, fallback)
    }

    /// Whether a failed `updateApplicationContext` is plausibly SIZE-driven and
    /// therefore worth retrying without the compute seed.
    ///
    /// Only `WCError.payloadTooLarge` qualifies. Every other failure
    /// (`sessionNotActivated`, `deliveryFailed`, `notReachable`, …) is
    /// transient or unrelated to the payload, and treating it as size-driven
    /// would permanently strip the seed from the pending activation resend —
    /// the watch would then never receive a seed on exactly the paths where the
    /// first attempt raced activation.
    nonisolated static func isSeedSizeFailure(_ error: Error) -> Bool {
        (error as? WCError)?.code == .payloadTooLarge
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
    /// clock. `computeSeedData` (Phase 3 of the on-watch realtime compute plan)
    /// is the compressed `WatchComputeSeed` payload, or `nil` to send none
    /// (cold start / reset tombstone / encode failure).
    /// `computeSeedSettingsSignature` is the seed's tiny settings hash, sent
    /// even when the blob itself is nil/dropped (see
    /// `WatchComputeSeed.applicationContextSettingsSignatureKey`).
    func send(
        _ snapshot: WatchMetricsSnapshot,
        permissionRawValue: String?,
        captureSequence: UInt64,
        computeSeedData: Data? = nil,
        computeSeedSettingsSignature: String? = nil
    ) {
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
            pending = (outgoing, permissionRawValue, captureSequence, computeSeedData, computeSeedSettingsSignature)
            if session.activationState == .notActivated {
                session.activate()
            }
            return
        }

        guard let data = outgoing.encoded() else {
            logger.error("Watch snapshot encode failed.")
            return
        }

        // Budget the WHOLE context, not just the seed: an oversized seed on
        // top of an otherwise-fine snapshot must not risk the always-required
        // display push. The seed is the large, optional piece, so it's what
        // gets dropped.
        var seedToSend = computeSeedData
        if let seed = seedToSend,
           !Self.shouldIncludeComputeSeed(
               snapshotSize: data.count,
               permissionSize: permissionRawValue?.utf8.count ?? 0,
               seedSize: seed.count
           ) {
            logger.error("Compute seed dropped: whole-context size exceeded the \(Self.contextSizeBudgetBytes, privacy: .public)-byte budget.")
            seedToSend = nil
        }
        // The selection is captured alongside the snapshot so a queued build
        // can't pair with a newer selection.
        let contexts = Self.contexts(
            snapshotData: data,
            permissionRawValue: permissionRawValue,
            seedData: seedToSend,
            seedSettingsSignature: computeSeedSettingsSignature
        )

        do {
            try session.updateApplicationContext(contexts.primary)
        } catch {
            logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
            // Retry without the seed ONLY for a genuinely size-driven failure.
            // Any other error is transient/unrelated, and dropping the seed for
            // it would also null it out of `pending` below — permanently
            // starving the watch of a seed on, say, a
            // `sessionNotActivated` race that the activation resend is meant to
            // recover from.
            guard seedToSend != nil, Self.isSeedSizeFailure(error) else {
                pending = (outgoing, permissionRawValue, captureSequence, computeSeedData, computeSeedSettingsSignature)
                return
            }
            do {
                try session.updateApplicationContext(contexts.fallback)
                return
            } catch {
                logger.error("updateApplicationContext retry without compute seed also failed: \(error.localizedDescription, privacy: .public)")
            }
            // The seed is what made this context too large — the resend must
            // not carry it back in. The SIGNATURE stays: it is what lets the
            // watch invalidate a stored seed built under superseded settings.
            pending = (outgoing, permissionRawValue, captureSequence, nil, computeSeedSettingsSignature)
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
        guard activationState == .activated, error == nil else {
            let nsError = error as NSError?
            logger.error(
                "WCSession activation incomplete: state \(activationState.rawValue, privacy: .public) error \(nsError?.domain ?? "none", privacy: .public) \(nsError?.code ?? 0, privacy: .public)"
            )
            // `pending` stays queued for the next successful activation.
            return
        }

        Task { @MainActor in
            if let pending = self.pending {
                self.pending = nil
                // Resend with the ORIGINAL capture sequence so the retry can't
                // outrank a publish that arrived while activation was pending.
                self.send(
                    pending.snapshot,
                    permissionRawValue: pending.permissionRawValue,
                    captureSequence: pending.captureSequence,
                    computeSeedData: pending.computeSeedData,
                    computeSeedSettingsSignature: pending.computeSeedSettingsSignature
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
