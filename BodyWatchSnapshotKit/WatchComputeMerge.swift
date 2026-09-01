//
//  WatchComputeMerge.swift
//  BodyWatchSnapshotKit
//
//  The freshest-wins-per-metric merge rules for the watch's displayed snapshot:
//  how a locally COMPUTED result folds into the phone-pushed snapshot
//  (`mergingComputed`), and how a phone push folds over locally-measured or
//  locally-computed values (`merging`). Both are pure statics over value types.
//
//  They live in this shared folder — not in `WatchMetricsModel` — because
//  `BodyWatch` is not linked into any test bundle the iOS scheme runs, and these
//  race/ordering rules are the part of the feature that MUST stay covered. The
//  watch model is the only caller; `BodyTests` mirrors the critical cases
//  (precedent: `BodyTests/WatchMetricHasValueTests`).
//

import Foundation

/// One completed on-watch compute, handed back to the model for merging.
///
/// `dataAsOf` is the anti-laundering contract: it carries, PER METRIC KIND, the
/// real watermark of the freshly-read data behind that kind (a HealthKit
/// sample's `endDate`, a computed night's end, the newest workout that moved
/// Training Load) — never `Date()`. A kind whose fetch failed, or whose value
/// was simply carried forward from the phone's seed, is ABSENT from the map and
/// is therefore never re-stamped as fresh and never adopted. Without that rule
/// a compute would launder the phone's own (possibly stale) numbers into
/// "measured just now" and permanently outrank later phone pushes.
struct WatchComputeResult {
    let snapshot: WatchMetricsSnapshot
    let dataAsOf: [String: Date]
    /// Kinds whose CHART data (weekly series + carried range) was freshly
    /// re-derived this run even though the headline value stayed seed-carried —
    /// today only Skin Temperature, whose headline is deliberately
    /// phone-sourced. `mergingComputed` adopts ONLY the chart fields for these,
    /// with no provenance claim; without this channel the freshly spliced trend
    /// could never reach the card (the headline deviation would silently
    /// become a whole-card deviation).
    let chartDataAsOf: [String: Date]
    /// The compute's INFORMATION CUTOFF — the instant its queries ran to. This
    /// is the value compared against a PHONE-derived metric's stamp (the
    /// phone's own stamps are refresh/query times, the same domain): an event
    /// watermark like a night's end must NOT be compared against them, or a
    /// night that ended before the phone's refresh but synced only to the
    /// watch would lose to the phone's blank card forever. Local-vs-local
    /// comparisons still use the per-kind event watermarks in `dataAsOf`.
    let coverage: Date
    /// The model's compute-generation token captured when this compute STARTED.
    /// The model refuses to merge a result whose generation no longer matches —
    /// a Clear-Cache reset, a seed replacement, or a permission change that
    /// landed mid-compute invalidates it (anti-resurrection).
    let generation: UInt64

    init(
        snapshot: WatchMetricsSnapshot,
        dataAsOf: [String: Date],
        chartDataAsOf: [String: Date] = [:],
        coverage: Date,
        generation: UInt64
    ) {
        self.snapshot = snapshot
        self.dataAsOf = dataAsOf
        self.chartDataAsOf = chartDataAsOf
        self.coverage = coverage
        self.generation = generation
    }
}

extension WatchMetric {
    /// This metric with every DISPLAY-deciding field taken from `other`, keeping
    /// its own identity (`kind`, `title`) and provenance stamps
    /// (`liveUpdatedAt`/`computedAt`, which the callers set explicitly).
    ///
    /// The full set matters: a metric's value, ring fill, score, status band,
    /// level bounds and tint are computed together and only make sense together.
    /// Copying just value/unit/fill — what the merge used to do — pairs a
    /// watch-computed Readiness score with the phone's older status band and
    /// tint, so the ring reads one status while the label reads another.
    func adoptingDisplayFields(from other: WatchMetric) -> WatchMetric {
        var adopted = self
        adopted.displayValue = other.displayValue
        adopted.unit = other.unit
        adopted.score = other.score
        adopted.fillFraction = other.fillFraction
        adopted.rawValue = other.rawValue
        adopted.rangeMin = other.rangeMin
        adopted.rangeMax = other.rangeMax
        adopted.levelMin = other.levelMin
        adopted.levelMax = other.levelMax
        adopted.tint = other.tint
        adopted.weekly = other.weekly
        adopted.statusBand = other.statusBand
        // Including nil: the candidate's "no drain" must clear a stale dot,
        // not let the replaced payload's drained value linger under the
        // adopted score.
        adopted.weeklyCurrentValue = other.weeklyCurrentValue
        // The event watermark describes the VALUE, so it travels with it —
        // keeping the old one would pair the adopted reading with the replaced
        // reading's measurement time.
        adopted.measuredAt = other.measuredAt
        return adopted
    }
}

enum WatchComputeMerge {
    // MARK: - Watch compute → displayed snapshot

    /// Folds an on-watch compute into the currently displayed snapshot.
    ///
    /// The phone's publication line is NEVER advanced: `generatedAt`,
    /// `publisherEpoch`, `revision`, `lastRefreshDate`, `source` and `isReset`
    /// all stay exactly as `current` carries them, so a later phone push still
    /// orders correctly through `supersedes` and a watch compute can't make
    /// itself look like a newer publish.
    ///
    /// Per metric kind, a computed value is adopted only when ALL of:
    /// 1. the kind is present in `dataAsOf` (it was genuinely re-read on the
    ///    watch — see `WatchComputeResult`);
    /// 2. it isn't blank while the displayed one has a value. On the watch a
    ///    blank means "this device has no local data for it", not an
    ///    authoritative clear — the deliberate asymmetry against the phone-push
    ///    rule below, where a blank readiness IS authoritative;
    /// 3. it is newer than what's on screen — compared WITHIN one watermark
    ///    domain. A locally-derived displayed metric (`liveUpdatedAt` set)
    ///    carries a local EVENT watermark, so the candidate's event watermark
    ///    (`dataAsOf`) compares against it directly. A PHONE-derived metric is
    ///    stamped with the phone's refresh/query time, so the compute's own
    ///    information cutoff (`coverage`) is what compares against it — an
    ///    event watermark would lose to a phone refresh that ran AFTER the
    ///    event but never saw it (a night that hadn't synced to the phone yet
    ///    would be rejected against the phone's blank card forever). A phone
    ///    push landing mid-compute still wins in both domains: its stamps are
    ///    newer than `coverage`.
    ///
    /// The adopted metric is stamped with the EVENT watermark (not `now`),
    /// which is what makes rule 3 composable across repeated computes and the
    /// live HR/HRV path. Kinds in `chartDataAsOf` additionally adopt ONLY
    /// their chart fields (weekly + carried range) under the coverage compare,
    /// with no provenance claim — the Skin Temperature deviation's trend
    /// channel. Never merges into a reset tombstone. The caller sanitizes.
    static func mergingComputed(
        _ result: WatchComputeResult,
        into current: WatchMetricsSnapshot
    ) -> WatchMetricsSnapshot {
        // A Clear-Cache tombstone must stay cleared: an in-flight compute that
        // started before the reset must never repopulate it (the generation
        // token is the primary guard; this is the belt-and-braces one).
        guard current.isReset != true else { return current }

        let computed = result.snapshot
        var merged = current
        var adoptedSleepMetric = false

        merged.metrics = current.metrics.map { metric in
            guard let candidate = computed.metric(forKind: metric.kind) else {
                return metric
            }
            guard let asOf = result.dataAsOf[metric.kind] else {
                // Chart-only channel: the headline stays exactly as displayed
                // (phone-sourced), but a freshly re-derived trend replaces the
                // chart when this compute's information cutoff is newer than
                // the displayed metric's stamp. No provenance stamps move — a
                // chart is not a measurement claim.
                if result.chartDataAsOf[metric.kind] != nil {
                    let displayedAsOf = metric.liveUpdatedAt
                        ?? metric.computedAt
                        ?? current.lastRefreshDate
                        ?? .distantPast
                    if result.coverage > displayedAsOf {
                        var adopted = metric
                        adopted.weekly = candidate.weekly
                        adopted.rangeMin = candidate.rangeMin
                        adopted.rangeMax = candidate.rangeMax
                        return adopted
                    }
                }
                return metric
            }
            if !candidate.hasValue, metric.hasValue {
                return metric
            }
            // Domain-matched freshness compare (rule 3 above).
            if let localEvent = metric.liveUpdatedAt {
                guard asOf > localEvent else { return metric }
            } else {
                let phoneAsOf = metric.computedAt
                    ?? current.lastRefreshDate
                    ?? .distantPast
                guard result.coverage > phoneAsOf else { return metric }
                // A NONBLANK phone card additionally requires the candidate's
                // EVENT to beat the displayed reading's own event watermark
                // (`measuredAt`, shipped by the builder for the sample-headline
                // vitals and sleep): under HealthKit replication lag the
                // phone's query time exceeds the event time of the older
                // sample it actually saw, and comparing against the query time
                // would reject a genuinely newer reading that synced only to
                // the watch — for sleep, pinning a partial night for the whole
                // day, since no newer sleep event arrives until tomorrow. A
                // payload without `measuredAt` falls back to the conservative
                // query-time compare: the refresh at `phoneAsOf` saw
                // everything synced by then, so an older watch event cannot
                // be proven newer information. A BLANK phone card has nothing
                // to roll back, so coverage alone decides — the offline case
                // where the event legitimately predates a refresh that missed
                // it.
                if metric.hasValue {
                    guard asOf > (metric.measuredAt ?? phoneAsOf) else { return metric }
                }
            }

            var adopted = metric.adoptingDisplayFields(from: candidate)
            adopted.liveUpdatedAt = asOf
            adopted.computedAt = asOf
            if metric.kind == WatchMetricKindKey.sleep {
                adoptedSleepMetric = true
            }
            return adopted
        }

        // Kinds the displayed snapshot doesn't carry yet (e.g. the phone's last
        // push predates a permission the user just re-enabled). Appended only
        // when the compute has a real watermark AND a real value — appending a
        // "--" card the phone never sent would be the blank-preserve rule
        // above inverted.
        let displayedKinds = Set(current.metrics.map(\.kind))
        for candidate in computed.metrics where !displayedKinds.contains(candidate.kind) {
            guard let asOf = result.dataAsOf[candidate.kind], candidate.hasValue else { continue }
            var appended = candidate
            appended.liveUpdatedAt = asOf
            appended.computedAt = asOf
            merged.metrics.append(appended)
            if candidate.kind == WatchMetricKindKey.sleep {
                adoptedSleepMetric = true
            }
        }

        // `sleepNight` describes the Sleep METRIC's night (it drives
        // `sanitized(asOf:)`) and `sleepStages` the segments of that same
        // night, so both may only move together with that metric — otherwise a
        // compute that didn't adopt sleep would re-date the phone's sleep card
        // to the watch's night (defeating the midnight guard) and draw the
        // watch's bar under the phone's duration.
        if adoptedSleepMetric {
            merged.sleepNight = computed.sleepNight
            merged.sleepStages = computed.sleepStages
        }
        return merged
    }

    // MARK: - Phone push → displayed snapshot

    /// Keeps a locally-measured (live HR/HRV) or locally-computed reading over
    /// the incoming one when it is still the freshest — a workout-only phone
    /// refresh re-sends old vitals, which must not roll back a fresher local
    /// value.
    ///
    /// Freshness is compared PER METRIC: the incoming metric's own `computedAt`
    /// when it carries one, else the snapshot-level `lastRefreshDate`. The
    /// builder can stamp honest per-kind watermarks (`perKindDataAsOf`), so a
    /// publish whose Training Load is fresh but whose vitals are hours old must
    /// not present one uniform timestamp for both.
    ///
    /// HOW MUCH is preserved depends on where the local value came from: a
    /// watch-COMPUTED metric keeps its whole display set (see
    /// `isWatchComputed`), while a live-only HR/HRV reading keeps just its
    /// value, unit and ring fill and takes everything else — weekly series,
    /// ranges, bands, tint — from the incoming push.
    ///
    /// `treatingBlanksAsAuthoritative` is the compute-settings-change mode: the
    /// push announcing a settings change (e.g. a switched primary Health
    /// source) was built under the NEW configuration, so a blank card in it
    /// means "the new configuration produces no value" — an authoritative
    /// clear, not a fetch-disabled placeholder. The ordinary blank-preserve
    /// rule would resurrect the OLD configuration's value behind it (and every
    /// later blank watch compute preserves a displayed value, so it would
    /// never clear).
    static func merging(
        _ received: WatchMetricsSnapshot,
        over current: WatchMetricsSnapshot,
        treatingBlanksAsAuthoritative: Bool = false
    ) -> WatchMetricsSnapshot {
        var merged = received
        var keptLocalSleepMetric = false
        merged.metrics = received.metrics.map { metric in
            guard let local = current.metric(forKind: metric.kind) else { return metric }

            // Event-to-event when the incoming metric ships its measurement
            // time: a push whose QUERY ran after the local reading was taken
            // can still carry an OLDER sample (HealthKit replication lag), and
            // the query-time compare would overwrite the genuinely newer local
            // measurement with it. Metrics without `measuredAt` (Readiness,
            // Training Load, legacy payloads) keep the query-time compare —
            // for computed metrics that IS the honest watermark.
            let receivedAsOf = metric.measuredAt
                ?? metric.computedAt
                ?? received.lastRefreshDate
                ?? .distantPast
            if let liveUpdatedAt = local.liveUpdatedAt, liveUpdatedAt > receivedAsOf {
                if metric.kind == WatchMetricKindKey.sleep { keptLocalSleepMetric = true }
                if isWatchComputed(local) {
                    // A watch COMPUTE produced every display field together:
                    // its Readiness / Training Load score, band, level bounds,
                    // tint, weekly series and ranges are all derived from the
                    // same spliced history, and mixing them with the incoming
                    // metric's would render an incoherent card (a ring in one
                    // status, a label in another).
                    var kept = metric.adoptingDisplayFields(from: local)
                    kept.liveUpdatedAt = local.liveUpdatedAt
                    kept.computedAt = local.computedAt
                    return kept
                }
                // Live-only local reading (the cheap HR/HRV path): only the
                // VALUE and its ring fill are locally derived. `weekly`,
                // `rangeMin`/`rangeMax`, `levelMin`/`levelMax`, `tint` and
                // `statusBand` on the local metric are just the PREVIOUS push's
                // — adopting them would discard the incoming push's newer
                // weekly series and ranges. Keep exactly the legacy subset.
                var kept = metric
                kept.displayValue = local.displayValue
                kept.unit = local.unit
                kept.rawValue = local.rawValue
                kept.fillFraction = local.fillFraction
                kept.liveUpdatedAt = local.liveUpdatedAt
                // The kept VALUE is the local reading, so its event watermark
                // comes along — leaving the incoming metric's would pair the
                // live reading with the pushed sample's measurement time.
                kept.measuredAt = local.measuredAt
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
            if !treatingBlanksAsAuthoritative,
               metric.kind != WatchMetricKindKey.readiness, !metric.hasValue, local.hasValue {
                if metric.kind == WatchMetricKindKey.sleep { keptLocalSleepMetric = true }
                return local
            }

            return metric
        }

        // `sleepNight` and `sleepStages` describe the Sleep METRIC's reading —
        // the night the midnight guard judges and the segments the complication
        // draws — so they stay with whichever side's card survived above.
        // Leaving the incoming ones behind a preserved local reading would date
        // that reading to a night it doesn't describe, and when the push's own
        // night is nil (a phone that had no trusted night to publish)
        // `sanitized(asOf:)` would then blank the very value the preserve rule
        // just kept.
        if keptLocalSleepMetric {
            merged.sleepNight = current.sleepNight
            merged.sleepStages = current.sleepStages
        }
        return merged
    }

    /// Whether a locally-held metric came from an on-watch COMPUTE rather than
    /// the cheap live HR/HRV read. `mergingComputed` stamps both provenance
    /// dates from the same `dataAsOf` watermark, so `computedAt == liveUpdatedAt`
    /// is the compute's signature; the live path (`WatchMetricsModel.updating`)
    /// only ever moves `liveUpdatedAt`, leaving `computedAt` at the phone's own
    /// (older) stamp.
    private static func isWatchComputed(_ metric: WatchMetric) -> Bool {
        guard let computedAt = metric.computedAt, let liveUpdatedAt = metric.liveUpdatedAt else {
            return false
        }
        return computedAt == liveUpdatedAt
    }

    /// Drops the local-provenance timestamps from every locally-derived metric
    /// (watch-computed AND live-read), so the next phone push wins the
    /// per-metric freshness compare regardless of watermark order. For a
    /// permission-selection change this is the only safe move: everything the
    /// watch derived locally was derived under the OLD selection — a readiness
    /// score still carrying Heart's contribution after Heart was disabled, a
    /// live HR read from a now-hidden category — and the disable push that
    /// announces the change was built before the watch's last compute, so its
    /// per-kind watermarks are typically OLDER and timestamp comparison alone
    /// would preserve exactly the values that must go. Display fields are left
    /// in place; the push resolving in the same intake replaces them.
    static func strippingLocalProvenance(
        from snapshot: WatchMetricsSnapshot
    ) -> WatchMetricsSnapshot {
        var stripped = snapshot
        stripped.metrics = snapshot.metrics.map { metric in
            guard metric.liveUpdatedAt != nil else { return metric }
            var cleared = metric
            cleared.liveUpdatedAt = nil
            // Only the compute's own stamp is a local claim; a live-read metric
            // keeps the phone's original `computedAt`.
            if isWatchComputed(metric) {
                cleared.computedAt = nil
            }
            return cleared
        }
        return stripped
    }
}
