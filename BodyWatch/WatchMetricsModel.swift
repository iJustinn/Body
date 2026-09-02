//
//  WatchMetricsModel.swift
//  BodyWatch
//
//  Single source of truth on the watch: receives the iPhone's pushed snapshot
//  over WatchConnectivity, caches it for the complications, runs the hybrid
//  live HR/HRV refresh, and drives the on-device metric compute
//  (`WatchComputeCoordinator`) from the phone's compute seed so the watch keeps
//  working when the iPhone isn't around.
//
//  Three pieces of state make the compute safe against races:
//  * the persisted seed (`WatchComputeSeedStore`), taken from every push that
//    carries one — independently of whether that push's snapshot supersedes;
//  * the compute GENERATION token, bumped whenever the compute's inputs are
//    invalidated (seed replaced or cleared, permission selection changed, reset
//    tombstone). A result whose generation no longer matches is discarded;
//  * the merge rules themselves, which live in the shared
//    `WatchComputeMerge` so they can be unit-tested from both test bundles.
//

import Foundation
import os
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
    private let computeCoordinator = WatchComputeCoordinator()
    private var hasRequestedLiveAuthorization = false
    /// The in-flight (or completed) broader compute-authorization request, held
    /// as a Task rather than a `Bool` latch so every compute path AWAITS it.
    /// A plain latch was set before its own `await` and therefore raced:
    /// `onAppear` and scene-active fire within a second of each other, the
    /// second caller found the latch already set and went straight into a
    /// compute that was still UNAUTHORIZED — and the first coalesced onto that
    /// same empty run. Cleared when the phone's permission selection changes so
    /// a newly-enabled category is re-requested.
    private var computeAuthorizationTask: Task<Void, Never>?
    /// Anti-resurrection token. Captured when a compute starts and re-checked
    /// before its result is merged, so a Clear-Cache reset, a replaced seed, or
    /// a permission change that lands mid-compute discards the in-flight result
    /// instead of letting it repopulate what was just invalidated.
    private var computeGeneration: UInt64 = 0
    /// When the last compute produced a usable result — half of the recompute
    /// staleness gate (the other half is the displayed data's own age).
    private var lastComputeDate: Date?
    /// When a non-forced compute was last STARTED, successful or not. This is
    /// the battery backstop: some visible metrics can never be freshened by a
    /// compute (an adopted sleep metric is stamped with the night's END, so it
    /// reads "stale" all day), which made the any-visible-metric-stale scan
    /// effectively always true and ran a full ~20-query compute on every single
    /// app open — the failure mode that killed the June 2026 attempt. A
    /// non-forced run now also has to be `staleInterval` past the last ATTEMPT.
    /// The manual refresh button (`force`) ignores this entirely.
    ///
    /// PERSISTED (UserDefaults): watchOS routinely evicts and relaunches the
    /// app well inside the 30-minute window, and an in-memory-only timestamp
    /// would reset to nil on every relaunch — turning process eviction into a
    /// bypass of the battery backstop it exists to be.
    private var lastComputeAttemptDate: Date? {
        didSet {
            if let lastComputeAttemptDate {
                UserDefaults.standard.set(
                    lastComputeAttemptDate.timeIntervalSinceReferenceDate,
                    forKey: Self.lastComputeAttemptDateKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastComputeAttemptDateKey)
            }
        }
    }
    private static let lastComputeAttemptDateKey = "watchLastComputeAttemptDate"
    private var pendingConnectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    /// Background tasks already completed, by identity. `setTaskCompletedWithSnapshot`
    /// must be called exactly once per task, and the expiration handler now
    /// completes synchronously off the main thread while the main-actor finish
    /// paths may be completing the same task, so the once-only rule needs a lock
    /// rather than the `pendingConnectivityTasks` array alone (M-36).
    private nonisolated let completedConnectivityTaskIDs = OSAllocatedUnfairLock<Set<ObjectIdentifier>>(initialState: [])

    /// The last snapshot that actually reached disk, so `apply` can skip a
    /// republish + timeline reload for an unchanged push, and retry a save that
    /// failed. Raw, never sanitized: it has to compare against what `apply` is
    /// asked to persist.
    private var lastPersistedSnapshot: WatchMetricsSnapshot?
    private let persistSnapshot: (WatchMetricsSnapshot) -> Bool
    private let reloadTimelines: () -> Void

    /// Received WatchConnectivity contexts, consumed one at a time in delivery
    /// order by the single consumer started in `init` (M-37). Unbounded
    /// buffering on purpose: a dropping policy would silently lose a push.
    private nonisolated let contextContinuation: AsyncStream<[String: Any]>.Continuation
    /// Contexts yielded into the stream but not yet consumed. Kept under a lock
    /// rather than on the main actor so the increment happens at yield time and
    /// can never trail the consumer's decrement, which would let a background
    /// task complete with a push still queued.
    private nonisolated let contextsInFlight = OSAllocatedUnfairLock<Int>(initialState: 0)

    init(
        persistSnapshot: @escaping (WatchMetricsSnapshot) -> Bool = { WatchMetricsSnapshotStore.save($0) },
        reloadTimelines: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.persistSnapshot = persistSnapshot
        self.reloadTimelines = reloadTimelines
        // Runs before the first `BodyHealthPermissionSelection.load()` on this
        // process: `load` is a pure read, so the migrations have to happen here.
        BodyHealthPermissionSelection.migrateIfNeeded()
        let stored = WatchMetricsSnapshotStore.load()
        lastPersistedSnapshot = stored
        snapshot = (stored ?? .empty).sanitized()
        hiddenMetricKinds = Self.loadHiddenMetricKinds()
        if UserDefaults.standard.object(forKey: Self.lastComputeAttemptDateKey) != nil {
            let persisted = Date(
                timeIntervalSinceReferenceDate: UserDefaults.standard.double(forKey: Self.lastComputeAttemptDateKey)
            )
            // Reject a future-dated stamp (clock rollback, or a bad persisted
            // value) rather than restoring it: `isFreshLocalDate` treats a
            // future date as stale anyway, but leaving it in place here would
            // still park a stale-but-not-yet-recomputed attempt across a
            // relaunch until the clock caught up to it.
            if persisted <= Date() {
                lastComputeAttemptDate = persisted
            }
        }
        let (stream, continuation) = AsyncStream.makeStream(of: [String: Any].self)
        contextContinuation = continuation
        super.init()
        Task { @MainActor [weak self] in
            for await context in stream {
                guard let self else { return }
                await self.applyReceivedContext(context)
                self.contextsInFlight.withLock { $0 -= 1 }
                self.completePendingConnectivityTasksIfDrained()
            }
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func onAppear() {
        // `supersedes`, not a bare `generatedAt` compare: the stored snapshot
        // must not roll back a newer publish line that is already on screen.
        // A cached snapshot can also outlive midnight, so re-gate its Sleep
        // metric at display time (mirrors the phone's build-time
        // `SleepSummary.asOf`) — but only publish when something changed.
        if let stored = WatchMetricsSnapshotStore.load(), stored.supersedes(snapshot) {
            lastPersistedSnapshot = stored
            snapshot = stored.sanitized()
        } else if snapshot.sanitized() != snapshot {
            snapshot = snapshot.sanitized()
        }
        Task {
            // Compute first: it refreshes HR/HRV from real samples too, so a
            // successful run leaves them fresh and the live path below
            // short-circuits on its own per-kind staleness check.
            await recomputeIfStale()
            await refreshLiveMetricsIfStale()
        }
    }

    // MARK: - WatchConnectivity intake

    /// Hands a received context to the single intake consumer. `nonisolated` so
    /// the WC delegate can enqueue without a hop: the in-flight count is bumped
    /// under the lock BEFORE the yield, so a background task can never be
    /// completed in the window between delivery and consumption.
    private nonisolated func enqueueReceivedContext(_ context: [String: Any]) {
        contextsInFlight.withLock { $0 += 1 }
        contextContinuation.yield(context)
    }

    private func applyReceivedContext(_ context: [String: Any]) async {
        // Permission selection — independent of snapshot freshness, so a
        // permission-only change (or a same-/older-generation snapshot) applies.
        // This also opens the live-read gate: the watch's HR/HRV path reads
        // HealthKit only after the phone's selection has synced at least once.
        if let rawSelection = context[BodyAppearancePreference.healthPermissionSelectionKey] as? String {
            adoptRemotePermissionSelection(rawSelection)
        }

        // Everything the payload decides, resolved in ONE call off the main
        // actor: the seed is zlib-compressed JSON over ~70 days of trends, and
        // decoding it (plus the store's read/compare/write) on every push — and
        // again on every activation replay — is far too much work to do while
        // the UI is waiting.
        //
        // Ordering across pushes is the intake stream's job (see
        // `contextContinuation`): this method runs once per context, to
        // completion, in delivery order. The held
        // `WKWatchConnectivityRefreshBackgroundTask` is completed only once the
        // stream has drained, so a closed-watch push can't be dropped with its
        // background task already "completed" — the exact failure the
        // task-holding machinery exists to prevent.
        let current = snapshot
        let (resolution, seedChanged, settingsChanged) = await withCheckedContinuation { continuation in
            Self.contextIntakeQueue.async {
                let resolution = Self.resolution(for: context, over: current)
                // Read the PRIOR stored signature before `persist` overwrites
                // it: a changed compute-settings signature (source selection,
                // sleep goal, display flags, …) means everything the watch
                // derived locally was derived under a superseded configuration
                // — `finishReceivedContext` must strip that provenance, exactly
                // as the permission-change path does.
                let priorSignature = WatchComputeSeedStore.load()?.settingsSignature
                let seedChanged = Self.persist(resolution.seedIntake)
                let settingsChanged = Self.settingsChanged(
                    intake: resolution.seedIntake,
                    priorSignature: priorSignature,
                    seedChanged: seedChanged
                )
                continuation.resume(returning: (resolution, seedChanged, settingsChanged))
            }
        }
        finishReceivedContext(resolution, seedChanged: seedChanged, settingsChanged: settingsChanged)
    }

    /// Whether this intake switched the COMPUTE SETTINGS the stored seed was
    /// built under — distinct from an ordinary data refresh of the seed.
    /// `nonisolated` + pure over its inputs (the store read happens at the call
    /// site) so it's testable.
    nonisolated static func settingsChanged(
        intake: WatchComputeSeedIntake,
        priorSignature: String?,
        seedChanged: Bool
    ) -> Bool {
        switch intake {
        case .replace(_, let seed):
            // Only a change BETWEEN two known signatures counts: with no prior
            // seed there was no old configuration for local values to have
            // been derived under.
            guard let priorSignature else { return false }
            return seed.settingsSignature != priorSignature
        case .clearIfSettingsMismatch:
            // The persist cleared the stored seed precisely because its
            // signature no longer matched the phone's.
            return seedChanged
        case .clear, .keepPrior:
            // A reset tombstone replaces the whole snapshot outright (nothing
            // local survives to strip), and keep-prior changed nothing.
            return false
        }
    }

    /// Off the main actor so the seed decode + file I/O never blocks the UI
    /// (see `applyReceivedContext`). Receive order is guaranteed upstream by the
    /// single-consumer intake stream, not by this queue.
    private static let contextIntakeQueue = DispatchQueue(
        label: "com.zihengthedeveloper.Body.watchContextIntake"
    )

    /// The main-actor tail of `applyReceivedContext`: the only things that
    /// touch model state.
    private func finishReceivedContext(
        _ resolution: ReceivedContextResolution,
        seedChanged: Bool,
        settingsChanged: Bool
    ) {
        // Bump on a real byte change or a clear: a compute already in flight
        // holds its own decoded copy of the seed, and the generation is the only
        // thing that stops its result landing on top of what just replaced it.
        if seedChanged {
            bumpComputeGeneration()
        }

        guard settingsChanged else {
            guard let resolved = resolution.resolvedSnapshot else { return }
            // The resolve ran against the snapshot as of dispatch. Re-check it
            // against the live one: a push that landed while this one was
            // decoding must not be rolled back by an out-of-order hop back.
            // (Unchanged state always passes — `resolved` carries the received
            // publish line, which already superseded it.)
            guard resolved.supersedes(snapshot) else { return }
            apply(resolved)
            return
        }

        // The compute settings this push announces supersede the ones every
        // locally-derived value on screen was computed under (e.g. a switched
        // primary Health source: the old source's data must not survive behind
        // fresh local stamps, or a blank card from the new source could never
        // clear it). Strip the local provenance FIRST, then resolve the
        // received snapshot against the stripped state — the off-main resolve
        // already ran against the unstripped snapshot and may have preserved
        // exactly the values that must go. `strippingLocalProvenance` only
        // clears per-metric liveUpdatedAt/computedAt, so `supersedes` against
        // `stripped` equals `supersedes` against `snapshot`.
        let stripped = WatchComputeMerge.strippingLocalProvenance(from: snapshot)
        // Blanks in this push are authoritative: it was built under the new
        // compute settings, so a "--" card here means the new configuration
        // produces no value — the ordinary blank-preserve rule would keep the
        // old configuration's value behind it forever (later blank watch
        // computes never displace a displayed value).
        //
        // When the push does not supersede what is already on screen, `adopt`
        // applies nothing and the strip is skipped. The new signature has
        // already been persisted, so no later push will strip either; that is
        // accepted, because the newer on-screen snapshot was itself produced
        // under the newer settings.
        guard let received = resolution.received else {
            apply(stripped)
            return
        }
        adopt(received, over: stripped, treatingBlanksAsAuthoritative: true)
    }

    /// The only route from a received push to `snapshot` (S-09); `resolvedSnapshot`
    /// carries the `supersedes` ordering check and the reset-tombstone rule.
    private func adopt(
        _ received: WatchMetricsSnapshot,
        over base: WatchMetricsSnapshot,
        treatingBlanksAsAuthoritative: Bool
    ) {
        guard let resolved = Self.resolvedSnapshot(
            applying: received,
            over: base,
            treatingBlanksAsAuthoritative: treatingBlanksAsAuthoritative
        ) else { return }
        apply(resolved)
    }

    /// Everything a received context decides, in one value. Bundling the two is
    /// the point: seed intake runs INDEPENDENTLY of whether the snapshot
    /// supersedes (a permission-only or same-revision push can still carry a
    /// fresher seed, and dropping it there would leave the compute permanently
    /// seedless), and when the two were merely adjacent statements that
    /// independence was only positional — a refactor that returned early on a
    /// non-superseding snapshot would silently take the seed with it.
    struct ReceivedContextResolution {
        let seedIntake: WatchComputeSeedIntake
        /// The snapshot to persist, or `nil` when the received one doesn't
        /// supersede `current` (or the context carried none).
        let resolvedSnapshot: WatchMetricsSnapshot?
        /// The decoded incoming snapshot itself, kept so the settings-change
        /// path can RE-resolve it against a provenance-stripped current — the
        /// `resolvedSnapshot` above was merged against the unstripped one.
        let received: WatchMetricsSnapshot?
    }

    /// Pure + `nonisolated` so the whole intake decision can be made off the
    /// main actor (and unit-tested without WatchConnectivity or the stores).
    nonisolated static func resolution(
        for context: [String: Any],
        over current: WatchMetricsSnapshot
    ) -> ReceivedContextResolution {
        let received = (context["snapshot"] as? Data).flatMap(WatchMetricsSnapshot.decoded(from:))
        return ReceivedContextResolution(
            seedIntake: seedIntake(from: context, isReset: received?.isReset == true),
            resolvedSnapshot: received.flatMap { resolvedSnapshot(applying: $0, over: current) },
            received: received
        )
    }

    /// Carries out a seed-intake decision against the store. Returns whether the
    /// stored seed actually CHANGED — the signal to bump the compute generation.
    /// A clear always counts (an in-flight compute holds its own copy); a
    /// replace counts only on a real byte change, so the phone's identical
    /// republish on every settings-only publish doesn't discard a running
    /// compute. `nonisolated` — it only touches the file-backed store.
    nonisolated private static func persist(_ intake: WatchComputeSeedIntake) -> Bool {
        switch intake {
        case .clear:
            WatchComputeSeedStore.clear()
            return true
        case .replace(let seedData, let seed):
            return WatchComputeSeedStore.save(seedData, decoded: seed)
        case .keepPrior:
            return false
        case .clearIfSettingsMismatch(let signature):
            // Signature-only push (the blob was dropped for size): a stored
            // seed built under DIFFERENT compute settings is stale
            // configuration, not just stale data — computing from it would
            // apply the old source selection / sleep goal / display flags and
            // merge those results over the new phone values. No seed at all
            // (compute disabled until a fitting blob arrives) is the safe
            // state. A matching signature keeps the seed: its data may be
            // older than this push, but `dataThrough` already handles that.
            guard let stored = WatchComputeSeedStore.load(), stored.settingsSignature != signature else {
                return false
            }
            WatchComputeSeedStore.clear()
            return true
        }
    }

    /// What a received context asks the seed store to do. Pure so the intake
    /// rules (schema check, corrupt-keeps-prior, tombstone-clears) are testable
    /// without WatchConnectivity.
    enum WatchComputeSeedIntake: Equatable {
        /// Nothing usable arrived — keep whatever seed is already stored. A
        /// corrupt or wrong-schema payload lands here rather than wiping a good
        /// seed on the strength of a bad push.
        case keepPrior
        case replace(Data, WatchComputeSeed)
        /// A reset tombstone: the phone cleared its data, so the seed must go.
        case clear
        /// The push carried the phone's current compute-settings SIGNATURE but
        /// no seed blob (the publisher drops an over-budget blob while keeping
        /// this tiny sibling key). A stored seed whose own signature differs
        /// was built under settings the phone has since changed — computing
        /// from it would merge old-configuration results over the new phone
        /// values, so it must be invalidated rather than kept.
        case clearIfSettingsMismatch(String)
    }

    nonisolated static func seedIntake(
        from context: [String: Any],
        isReset: Bool
    ) -> WatchComputeSeedIntake {
        // The phone never attaches a seed to a reset tombstone, and even if a
        // future build did, a clear must win.
        if isReset { return .clear }
        guard let data = context[WatchComputeSeed.applicationContextKey] as? Data else {
            // No blob, but the signature sibling still announces the phone's
            // current compute settings — enough to detect a stale stored seed.
            if let signature = context[WatchComputeSeed.applicationContextSettingsSignatureKey] as? String {
                return .clearIfSettingsMismatch(signature)
            }
            return .keepPrior
        }
        guard let seed = WatchComputeSeed.decoded(from: data),
              seed.schemaVersion == WatchComputeSeed.currentSchemaVersion else {
            return .keepPrior
        }
        // Carry the seed decoded here so nothing downstream repeats the zlib
        // decompress plus JSON parse of ~70 days of trends (M-34).
        return .replace(data, seed)
    }

    /// Invalidates every in-flight compute. Wrapping arithmetic because the
    /// value is only ever compared for equality — an (impossible in practice)
    /// overflow must not trap.
    private func bumpComputeGeneration() {
        computeGeneration &+= 1
    }

    /// The snapshot to persist for `received` arriving over `current`, or `nil`
    /// when `received` doesn't supersede (no change). Pure so the reset-vs-merge
    /// routing and the blank/live-preserve merge are unit-testable without the
    /// WatchConnectivity + store singletons.
    ///
    /// A Clear-Cache reset (`isReset == true`) is handled BEFORE the merge: the
    /// tombstone REPLACES the current snapshot outright — the blank-preserve rule
    /// in `merging(_:over:)` would otherwise resurrect the stale local values it
    /// cleared. The tombstone keeps its own `publisherEpoch`/`revision`, so once
    /// persisted a delayed lower-revision same-epoch push can't bring the data
    /// back (the caller persists it via `WatchMetricsSnapshotStore.save`, never a
    /// delete, so that ordering also survives a watch restart). A normal push
    /// takes the unchanged merge path. `nonisolated` since it only reads its
    /// arguments — no main-actor state.
    nonisolated static func resolvedSnapshot(
        applying received: WatchMetricsSnapshot,
        over current: WatchMetricsSnapshot,
        treatingBlanksAsAuthoritative: Bool = false
    ) -> WatchMetricsSnapshot? {
        guard received.supersedes(current) else { return nil }
        if received.isReset == true { return received }
        return WatchComputeMerge.merging(
            received,
            over: current,
            treatingBlanksAsAuthoritative: treatingBlanksAsAuthoritative
        )
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
        // A changed selection changes which categories the compute may read, so
        // re-request authorization on the next run and invalidate any compute
        // already running under the old selection.
        computeAuthorizationTask = nil
        bumpComputeGeneration()
        // Every locally-derived value on screen was derived under the OLD
        // selection (a readiness score may still carry a now-disabled
        // category's contribution), and the disable push announcing this change
        // typically carries OLDER per-kind watermarks than the watch's last
        // compute — timestamp comparison alone would preserve exactly what must
        // go. Strip the local provenance so the push resolving in this same
        // intake wins every per-metric compare.
        apply(WatchComputeMerge.strippingLocalProvenance(from: snapshot))
    }

    /// The live HR/HRV path reads HealthKit only after the phone's permission
    /// selection has synced at least once (see `adoptRemotePermissionSelection`).
    private static func hasSyncedPermissionSelection(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: BodyAppearancePreference.healthPermissionSelectionKey) != nil
    }

    /// Persists the RAW snapshot (sanitization is a display-time guard; the
    /// complication provider and `onAppear` sanitize at read, see L-36) and
    /// shows the sanitized value. Early-outs against the last snapshot that
    /// actually reached disk, so a failed save is retried on the next call and
    /// an unchanged push does not republish or reload the complications.
    ///
    /// Known limit: the merge base is still the sanitized in-memory `snapshot`,
    /// so a metric cleared at display time can still be persisted through a
    /// later merge. This phase only stops the direct write of sanitized output.
    private func apply(_ raw: WatchMetricsSnapshot) {
        let display = raw.sanitized()
        if display != snapshot { snapshot = display }
        guard raw != lastPersistedSnapshot else { return }
        if persistSnapshot(raw) {
            lastPersistedSnapshot = raw
            reloadTimelines()
        }
    }

    /// Test seam for `apply`: every production caller is private and reaches it
    /// only through an async HealthKit or WatchConnectivity path, so there is no
    /// deterministic way to exercise the persist early-out and the failed-save
    /// retry from outside.
    func applyForTesting(_ raw: WatchMetricsSnapshot) {
        apply(raw)
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
        let now = Date()
        let liveMetrics = [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability]
            .compactMap { snapshot.metric(forKind: $0) }
        guard !liveMetrics.isEmpty else {
            // No watch-measurable metric present: fall back to snapshot freshness.
            guard let lastRefresh = snapshot.lastRefreshDate else { return true }
            return !Self.isFreshPhoneDate(lastRefresh, limit: WatchMetricsSnapshot.staleInterval, now: now)
        }
        // Evaluate each live metric independently against its per-kind freshness
        // limit (HR 30 min, HRV 4h). A single shared window would either thrash
        // HR or, having just accepted a multi-hour-old HRV sample, instantly
        // re-stale it and wedge the live-read loop.
        return liveMetrics.contains { metric in
            guard let measuredAt = metric.liveUpdatedAt ?? metric.computedAt else { return true }
            return !Self.isFreshPhoneDate(measuredAt, limit: WatchMetricKindKey.liveFreshnessLimit(forKind: metric.kind), now: now)
        }
    }

    /// Manual dashboard refresh (top-left button): force BOTH the on-device
    /// compute (Readiness / Sleep / Training Load / vitals, from the phone's
    /// seed plus a fresh HealthKit delta) and a live HR/HRV reading, so the tap
    /// always lands even when nothing has crossed a staleness window yet.
    /// Sequenced, not parallel: the compute's HR/HRV come from the same samples
    /// the live read would take, and running it first means the live read only
    /// ever confirms or improves on them.
    func refresh() async {
        await recomputeIfStale(force: true)
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

        // Source parity (H1): once the phone has synced a specific source
        // selection, the live reads run behind the same strict-resolved
        // predicate the compute uses. An unresolvable selection skips the read
        // (`.skip`) rather than widening to every source.
        let sourceReads = await healthStore.liveSourceReads(permission: BodyHealthPermissionSelection.load())
        async let heartRateReading = healthStore.latestHeartRate(source: sourceReads.heartRate)
        async let hrvReading = healthStore.latestHRV(source: sourceReads.heartRateVariability)
        let (heartRate, hrv) = await (heartRateReading, hrvReading)
        guard heartRate != nil || hrv != nil else { return }

        var metrics = snapshot.metrics
        if let heartRate {
            metrics = updating(metrics, kind: WatchMetricKindKey.heartRate, value: heartRate.value, measuredAt: heartRate.measuredAt, decimals: 0, unit: "bpm")
        }
        if let hrv {
            metrics = updating(metrics, kind: WatchMetricKindKey.heartRateVariability, value: hrv.value, measuredAt: hrv.measuredAt, decimals: 0, unit: "ms")
        }

        // Don't advance `generatedAt` on a local live refresh: a newer phone
        // snapshot (higher generatedAt) must still win so Readiness / Sleep /
        // Training Load aren't frozen behind a watch-only HR/HRV update.
        var updated = snapshot
        updated.metrics = metrics
        apply(updated)
    }

    private func updating(_ metrics: [WatchMetric], kind: String, value: Double, measuredAt: Date, decimals: Int, unit: String) -> [WatchMetric] {
        guard let index = metrics.firstIndex(where: { $0.kind == kind }) else { return metrics }
        var result = metrics
        var metric = result[index]
        metric.displayValue = WatchValueFormat.number(value, decimals: decimals)
        metric.unit = unit
        metric.rawValue = value
        metric.fillFraction = WatchRingFill.fraction(of: value, min: metric.rangeMin, max: metric.rangeMax)
        // Stamp the sample's own measurement time (not `Date()`): the per-kind
        // staleness check must see the reading's true age, so an accepted
        // multi-hour-old HRV sample isn't treated as if it were just measured.
        // `measuredAt` moves with it — the displayed value's event watermark
        // must describe THIS reading, not the phone value it replaced.
        metric.liveUpdatedAt = measuredAt
        metric.measuredAt = measuredAt
        result[index] = metric
        return result
    }

    // MARK: - On-device compute

    /// Runs an on-device compute when it would change anything on screen, and
    /// merges the result.
    ///
    /// The gate is DISPLAYED-DATA staleness (H6), never the phone's push
    /// recency: gating on `lastRefreshDate` would suppress the compute exactly
    /// when the phone had just pushed — which is when the watch is least likely
    /// to need it, but also the state a watch sitting next to a busy phone is in
    /// most of the day. Instead: any visible metric older than its own
    /// freshness limit, or no successful compute inside the snapshot stale
    /// window — rate-limited by the last ATTEMPT so an unfixably-stale metric
    /// can't turn every app open into a full compute (see `isComputeStale`).
    func recomputeIfStale(force: Bool = false) async {
        // Same gate as the live path: until the phone's selection has synced at
        // least once, `BodyHealthPermissionSelection.load()` would fall back to
        // all-enabled and could read categories the user hid on the phone.
        guard Self.hasSyncedPermissionSelection(), WatchComputeSeedStore.hasStoredSeed() else { return }
        let now = Date()
        guard force || isComputeStale(now: now) else { return }
        if !force {
            // Record the ATTEMPT before the first suspension, so the next
            // trigger inside the stale window is refused whether or not this one
            // produces a mergeable result.
            lastComputeAttemptDate = now
        }

        let permission = BodyHealthPermissionSelection.load()
        // Every path awaits the SAME authorization request (see
        // `computeAuthorizationTask`); a second trigger arriving mid-request
        // must not start computing before HealthKit has granted the broader
        // read set.
        await awaitComputeAuthorization(for: permission)

        let generation = computeGeneration
        guard let result = await computeCoordinator.recompute(
            permission: permission,
            generation: generation,
            now: now
        ) else { return }

        // Re-verify AFTER the await: a reset tombstone, a replaced seed, or a
        // permission change that landed while the compute ran invalidates it.
        guard Self.mayMerge(result, generation: computeGeneration, into: snapshot) else {
            // A generation-mismatched result means this run computed from
            // inputs that were replaced mid-flight — the run "didn't count".
            // Release the attempt throttle so the next trigger can compute
            // under the NEW generation instead of sitting out the 30-minute
            // rate limit with a fresh seed on disk.
            if result.generation != computeGeneration {
                lastComputeAttemptDate = nil
            }
            return
        }

        lastComputeDate = Date()
        apply(WatchComputeMerge.mergingComputed(result, into: snapshot))
    }

    /// Awaits the broader compute-read authorization, requesting it once and
    /// sharing that one request with every concurrent caller. The task is stored
    /// BEFORE the first suspension (this is the main actor, so the check and the
    /// store can't interleave), which is what makes a second caller await the
    /// request instead of skipping it.
    private func awaitComputeAuthorization(for permission: BodyHealthPermissionSelection) async {
        if let computeAuthorizationTask {
            await computeAuthorizationTask.value
            return
        }
        let task = Task { [healthStore] in
            await healthStore.requestComputeAuthorization(for: permission)
        }
        computeAuthorizationTask = task
        await task.value
    }

    /// Whether a finished compute may still be merged. Pure so the
    /// anti-resurrection rule is testable without the HealthKit round trip:
    /// the generation must not have moved while the compute ran, and a
    /// Clear-Cache tombstone is never repopulated.
    nonisolated static func mayMerge(
        _ result: WatchComputeResult,
        generation: UInt64,
        into current: WatchMetricsSnapshot
    ) -> Bool {
        result.generation == generation && current.isReset != true
    }

    /// Freshness helpers behind every staleness gate below, split by which
    /// clock stamped the date being checked:
    ///
    /// * WATCH-LOCAL dates (`lastComputeAttemptDate`, `lastComputeDate`) are
    ///   set by THIS device's own `Date()`, so a future value can only mean a
    ///   clock rollback or a corrupt persisted stamp — never ordinary skew.
    ///   Reject it outright, or it reads as permanently fresh and parks
    ///   recomputation forever.
    /// * PHONE-STAMPED dates (`lastRefreshDate`, `computedAt`/`liveUpdatedAt`
    ///   as pushed by `WatchMetricsSnapshotBuilder`) are set by the PHONE's
    ///   clock, so ordinary phone/watch clock skew puts them a little in the
    ///   future from the watch's point of view. Tolerate up to `staleInterval`
    ///   ahead — the same skew allowance `WatchComputeCoordinator` uses for
    ///   `seed.dataThrough` — so ordinary skew doesn't masquerade as staleness
    ///   and re-trigger the ~20-query compute-on-every-open regression these
    ///   gates exist to prevent (see `isComputeStale` below).
    nonisolated static func isFreshLocalDate(_ date: Date, limit: TimeInterval, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(date)
        return elapsed >= 0 && elapsed <= limit
    }

    nonisolated static func isFreshPhoneDate(_ date: Date, limit: TimeInterval, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(date)
        return elapsed >= -WatchMetricsSnapshot.staleInterval && elapsed <= limit
    }

    private func isComputeStale(now: Date) -> Bool {
        // Weekly Workout Time IS stamped in `dataAsOf`, but only while Workouts
        // is permitted (see `WatchComputeCoordinator.dataAsOf`); without that
        // permission a compute can never freshen it, so scanning it would make
        // this gate permanently true.
        Self.isComputeStale(
            snapshot: snapshot,
            lastComputeAttemptDate: lastComputeAttemptDate,
            lastComputeDate: lastComputeDate,
            scansWorkoutMinutes: BodyHealthPermissionSelection.load().includes(.workouts),
            isMetricVisible: { self.isMetricVisible($0) },
            now: now
        )
    }

    /// Whether an on-device compute would be worth running now.
    ///
    /// A compute is ~20 HealthKit round trips, so the visible-staleness scan
    /// alone is not a sufficient gate: it can be permanently true (see
    /// `lastComputeAttemptDate`). Both halves must agree — something on screen
    /// is stale AND the last attempt is itself outside the stale window.
    ///
    /// An EMPTY snapshot is stale too (a compute is the only way to populate
    /// it), but it is checked BELOW the attempt throttle: a watch that can
    /// never fill the snapshot — HealthKit denied, no readable data — would
    /// otherwise run a full compute on every single app open (H-09). At most
    /// one attempt per `staleInterval` either way.
    ///
    /// `nonisolated static` + pure over its inputs so the gate is testable
    /// without the stores and the HealthKit round trip.
    nonisolated static func isComputeStale(
        snapshot: WatchMetricsSnapshot,
        lastComputeAttemptDate: Date?,
        lastComputeDate: Date?,
        scansWorkoutMinutes: Bool,
        isMetricVisible: (String) -> Bool,
        now: Date
    ) -> Bool {
        // A compute that just ran can't have changed anything a compute would
        // change. Rate-limits the whole gate below, including the always-stale
        // cases it can't do anything about.
        if let lastComputeAttemptDate,
           isFreshLocalDate(lastComputeAttemptDate, limit: WatchMetricsSnapshot.staleInterval, now: now) {
            return false
        }

        // Nothing on screen yet: a compute is the only way to populate it.
        guard !snapshot.metrics.isEmpty else { return true }

        let visibleMetrics = snapshot.metrics.filter {
            // Skin Temp is deliberately absent from the compute's `dataAsOf`
            // (its headline is the seeded daily summary — the watch refetches
            // only the trend series behind readiness), so a compute can never
            // freshen it. Scanning it would make this gate permanently true.
            isMetricVisible($0.kind)
                && $0.kind != WatchMetricKindKey.wristTemperature
                && (scansWorkoutMinutes || $0.kind != WatchMetricKindKey.workoutMinutes)
                // The legacy `exerciseMinutes` compatibility copy (published
                // for not-yet-updated watch binaries) is never stamped by a
                // compute, so scanning it would make this gate permanently
                // true.
                && $0.kind != WatchMetricKindKey.exerciseMinutes
        }
        let anyVisibleMetricStale = visibleMetrics.contains { metric in
            guard let measuredAt = metric.liveUpdatedAt ?? metric.computedAt else { return true }
            return !isFreshPhoneDate(measuredAt, limit: WatchMetricKindKey.liveFreshnessLimit(forKind: metric.kind), now: now)
        }
        if anyVisibleMetricStale { return true }

        // Nothing visibly stale, but the compute itself hasn't produced a result
        // recently (or at all this launch) — re-run so a watch left open keeps up.
        guard let lastComputeDate else { return true }
        return !isFreshLocalDate(lastComputeDate, limit: WatchMetricsSnapshot.staleInterval, now: now)
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
        // WatchKit can hand the same task over more than once; a duplicate entry
        // would be completed twice.
        guard !pendingConnectivityTasks.contains(where: { $0 === task }) else { return }
        task.expirationHandler = { [weak self] in
            // Complete SYNCHRONOUSLY, off the main thread: watchOS is asking for
            // the task back right now, and hopping to the main actor first can
            // miss that window. The bookkeeping hop follows.
            self?.completeOnce(task)
            Task { @MainActor in self?.removePendingConnectivityTask(task) }
        }
        pendingConnectivityTasks.append(task)
        completePendingConnectivityTasksIfDrained()
    }

    /// Completes a background task at most once, whichever path gets there
    /// first (the expiration handler off the main thread, or the drained/finish
    /// paths on the main actor).
    private nonisolated func completeOnce(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        let isFirst = completedConnectivityTaskIDs.withLock { ids in
            ids.insert(ObjectIdentifier(task)).inserted
        }
        guard isFirst else { return }
        task.setTaskCompletedWithSnapshot(false)
    }

    /// Drops a task from the pending array and forgets its completion record
    /// (the identity is only meaningful while WatchKit holds the object).
    private func removePendingConnectivityTask(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        guard let index = pendingConnectivityTasks.firstIndex(where: { $0 === task }) else { return }
        pendingConnectivityTasks.remove(at: index)
        completedConnectivityTaskIDs.withLock { _ = $0.remove(ObjectIdentifier(task)) }
    }

    /// Completes held WC tasks once the session is activated and has drained all
    /// pending content. Re-invoked from each WC delegate callback so the tasks
    /// end as soon as delivery finishes.
    private func completePendingConnectivityTasksIfDrained() {
        guard !pendingConnectivityTasks.isEmpty else { return }
        // A context sitting unconsumed in the intake stream is undelivered work:
        // completing here would let watchOS suspend the app before it ran.
        guard contextsInFlight.withLock({ $0 }) == 0 else { return }
        if WCSession.isSupported() {
            let session = WCSession.default
            guard session.activationState == .activated, !session.hasContentPending else { return }
        }
        finishAllConnectivityTasks()
    }

    private func finishAllConnectivityTasks() {
        let tasks = pendingConnectivityTasks
        pendingConnectivityTasks.removeAll()
        tasks.forEach { task in
            completeOnce(task)
            completedConnectivityTaskIDs.withLock { _ = $0.remove(ObjectIdentifier(task)) }
        }
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
            // Queue the intake: any held WC background task stays open until
            // the stream has drained (the seed persisted and the snapshot
            // applied), or watchOS can suspend the app mid-intake and drop the
            // push.
            self.enqueueReceivedContext(WCSession.default.receivedApplicationContext)
            self.completePendingConnectivityTasksIfDrained()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Straight onto the intake stream, no per-push task: back-to-back pushes
        // are then consumed in delivery order rather than racing (M-37).
        enqueueReceivedContext(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // The phone no longer sends userInfo, but any delivered payload still
        // counts as content, so a held WC background task must complete.
        Task { @MainActor in
            self.completePendingConnectivityTasksIfDrained()
        }
    }
}
