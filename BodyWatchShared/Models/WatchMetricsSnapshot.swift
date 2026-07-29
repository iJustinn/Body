//
//  WatchMetricsSnapshot.swift
//  BodyWatchShared
//
//  Compact metrics payload computed on the iPhone, pushed to the watch over
//  WatchConnectivity, and cached for the watch app + complications. Kept
//  deliberately small (formatted strings + a precomputed 0...1 ring fill) so
//  it fits comfortably in `updateApplicationContext`.
//
//  This file is the ONLY member of `BodyWatchShared` compiled into the iOS
//  `Body` target (it just needs to build + encode the snapshot), so it must
//  stay free of SwiftUI / watch-only dependencies.
//

import Foundation
import os

struct WatchMetricColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

/// Status band to highlight behind a metric's recent-week chart (Readiness,
/// Training Load) — the value range of TODAY's status, mirroring the iPhone
/// trend chart's highlighted range. A `nil` bound is open-ended (the band fills
/// to that chart edge); the band's color rides on `WatchMetric.tint`.
struct WatchStatusBand: Codable, Equatable {
    var min: Double?
    var max: Double?
    /// Status level name shown beside the value on the detail page (e.g.
    /// "Optimal"). Optional so older snapshots still decode.
    var label: String? = nil
}

/// String keys matching `HealthMetricKind.rawValue` on the iOS side, plus the
/// per-kind look (tint + SF Symbol) shared by the watch app, the complications,
/// and the iOS snapshot builder — one source of truth so the sides can't drift.
/// `ProjectConfigurationTests` pins these against the iOS widget enum.
enum WatchMetricKindKey {
    static let readiness = "readiness"
    static let sleep = "sleep"
    static let heartRate = "heartRate"
    static let heartRateVariability = "heartRateVariability"
    static let restingHeartRate = "restingHeartRate"
    static let trainingLoad = "trainingLoad"
    static let wristTemperature = "wristTemperature"

    /// Dashboard ordering — Training Load leads. The watch complications are
    /// independent widgets and don't read this.
    static let displayOrder: [String] = [
        trainingLoad, readiness, sleep, heartRate,
        heartRateVariability, restingHeartRate, wristTemperature
    ]

    /// Card/ring tints mirroring the iOS dashboard (`HealthWidgetMetric.tintColor`).
    static func tint(forKind kind: String) -> WatchMetricColor {
        switch kind {
        case readiness: return WatchMetricColor(red: 0.12, green: 0.68, blue: 0.55)
        case sleep: return WatchMetricColor(red: 0.20, green: 0.72, blue: 1.00)
        case heartRate, heartRateVariability, restingHeartRate:
            return WatchMetricColor(red: 1.00, green: 0.25, blue: 0.45)
        case trainingLoad: return WatchMetricColor(red: 1.00, green: 0.38, blue: 0.12)
        case wristTemperature: return WatchMetricColor(red: 0.00, green: 0.75, blue: 0.85)
        default: return WatchMetricColor(red: 0.55, green: 0.55, blue: 0.60)
        }
    }

    /// SF Symbols mirroring the iOS dashboard (`HealthWidgetMetric.symbolName`).
    static func symbolName(forKind kind: String) -> String {
        switch kind {
        case readiness: return "bolt.heart.fill"
        case sleep: return "bed.double.fill"
        case heartRate, restingHeartRate: return "heart.fill"
        case heartRateVariability: return "waveform.path.ecg"
        case trainingLoad: return "figure.strengthtraining.traditional"
        case wristTemperature: return "thermometer.medium"
        default: return "heart.text.square"
        }
    }

    /// How old a locally-measured live reading (or the accepted HealthKit
    /// sample) may be before the watch treats that metric as stale. Evaluated
    /// PER KIND: heart rate moves minute-to-minute (30 min), HRV is a slow
    /// overnight metric (4h). A single shared window would either thrash HR or
    /// instantly re-stale a freshly-accepted multi-hour-old HRV, wedging the
    /// live-read loop. Used by both `WatchHealthStore` (sample acceptance) and
    /// `WatchMetricsModel.isStale`. Kinds without a live path fall back to the
    /// snapshot-level stale interval.
    static func liveFreshnessLimit(forKind kind: String) -> TimeInterval {
        switch kind {
        case heartRate: return 30 * 60
        case heartRateVariability: return 4 * 60 * 60
        default: return WatchMetricsSnapshot.staleInterval
        }
    }
}

/// Deep-link scheme shared by the watch complications (`widgetURL`) and the
/// watch app (`onOpenURL`), so tapping a metric complication opens that metric's
/// detail page directly instead of the dashboard.
enum WatchMetricDeepLink {
    static let scheme = "body"
    static let host = "metric"

    static func url(forKind kind: String) -> URL? {
        URL(string: "\(scheme)://\(host)/\(kind)")
    }

    static func kind(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let kind = url.lastPathComponent
        return kind.isEmpty || kind == "/" ? nil : kind
    }
}

struct WatchMetric: Codable, Equatable, Identifiable {
    /// `HealthMetricKind.rawValue` from the iOS app. That enum is iOS-target
    /// bound, so the shared payload carries the raw string instead.
    var kind: String
    var title: String
    /// Primary value shown on the watch card (e.g. "62", "7h 32m", "99").
    var displayValue: String
    var unit: String
    /// 0...100 score for score-style metrics (Readiness, Sleep). The ring shows
    /// this number when present; otherwise it shows `displayValue`.
    var score: Int?
    /// 0...1 ring fill, precomputed on the iPhone. (The SF Symbol is derived
    /// from `kind` via `WatchMetricKindKey`; the tint usually is too, unless a
    /// score-dependent one is carried in `tint` — see `resolvedTint`.)
    var fillFraction: Double
    /// Current numeric value + recent-range bounds so the watch can recompute
    /// the fill for live-refreshed metrics (HR/HRV) without the iPhone.
    var rawValue: Double?
    var rangeMin: Double?
    var rangeMax: Double?
    /// For banded metrics (Readiness, Training Load): the min/max of the value's
    /// CURRENT status band, so the watch corner gauge spans just that band (e.g.
    /// High 80–94) instead of the full range. nil for unbanded metrics; the band
    /// color rides on `tint`.
    var levelMin: Double? = nil
    var levelMax: Double? = nil
    /// Set on the watch when this metric was refreshed from watch-local
    /// HealthKit; never set by the iPhone builder. Lets the watch keep a live
    /// reading that's fresher than the vitals a later phone push carries.
    var liveUpdatedAt: Date? = nil

    /// When this metric's underlying data was computed/measured (set by the
    /// snapshot builder). Provenance alongside `WatchMetricsSnapshot.source`.
    var computedAt: Date? = nil

    /// When the reading behind `displayValue` was actually MEASURED (a latest
    /// sample's `endDate`; the sleep night's end) — the value's event
    /// watermark, distinct from `computedAt`, which for a phone publish is the
    /// refresh/query time. The merge compares nonblank measurements
    /// event-to-event through this: under HealthKit replication lag the
    /// phone's query time exceeds the event time of the (older) sample it
    /// actually saw, and comparing against it would both reject a genuinely
    /// newer watch reading and let a later push overwrite one. Stamped by the
    /// shared builder for HR / Resting HR / HRV / Sleep; nil for computed
    /// metrics (Readiness, Training Load), whose `computedAt` is the honest
    /// watermark, and for payloads from before this field.
    var measuredAt: Date? = nil

    /// Tint that can't be derived from `kind` alone — Readiness carries its
    /// status-band color here. `nil` ⇒ fall back to the kind's static tint.
    var tint: WatchMetricColor? = nil

    /// Last 7 daily values (oldest → today; `nil` for a day with no reading), in
    /// the same unit as `displayValue`, feeding the watch metric-detail
    /// sparkline. Optional/defaulted per the schema-evolution note below so an
    /// older phone (omits it) or older watch (ignores it) still decodes.
    var weekly: [Double?]? = nil

    /// Status band to highlight behind the recent-week chart for banded metrics
    /// (Readiness, Training Load) — TODAY's status range, in the same unit as
    /// `weekly`. `nil` for unbanded metrics. See `WatchStatusBand`.
    var statusBand: WatchStatusBand? = nil

    var id: String { kind }

    /// Whether this metric carries a real reading (vs. a `--` placeholder). Used
    /// by the watch merge so an empty value never overwrites a good one. The
    /// sleep metric can have a real duration `displayValue` with no `rawValue`
    /// (its score hidden by the phone's "Show Sleep Score" toggle), so the
    /// placeholder `displayValue` — not just a nil `rawValue` — defines "no value."
    var hasValue: Bool { rawValue != nil || displayValue != "--" }

    /// The tint to render: the carried dynamic `tint`, else the kind default.
    var resolvedTint: WatchMetricColor { tint ?? WatchMetricKindKey.tint(forKind: kind) }

    /// This metric with its reading cleared to the builder's empty state
    /// ("--", no score/fill/value), keeping identity + chart context (kind,
    /// title, weekly, ranges). Reuses the file's existing "--" sentinel (see
    /// `hasValue`) so it matches the value the snapshot builder emits for a
    /// metric it has no reading for. Used by `WatchMetricsSnapshot.sanitized`.
    func cleared() -> WatchMetric {
        var metric = self
        metric.displayValue = "--"
        metric.unit = ""
        metric.score = nil
        metric.fillFraction = 0
        metric.rawValue = nil
        metric.liveUpdatedAt = nil
        metric.measuredAt = nil
        return metric
    }
}

/// Schema evolution: the phone and watch can run different builds, so any new
/// field here (or on `WatchMetric`) must be optional or defaulted — a required
/// field would make older watches silently reject the whole payload.
struct WatchMetricsSnapshot: Codable, Equatable {
    var generatedAt: Date
    var lastRefreshDate: Date?
    var metrics: [WatchMetric]
    /// Which device produced this snapshot: "phone" for an iPhone publish,
    /// "watch" for one the watch computed on-device from the phone's compute
    /// seed. Provenance only — the merge decides by per-metric recency and
    /// value presence, and a watch compute never advances the phone's
    /// `(publisherEpoch, revision)` line, so the displayed snapshot keeps the
    /// phone's `source` even after adopting watch-computed metrics.
    var source: String? = nil
    /// The calendar day the carried Sleep metric belongs to (the sleep
    /// session's day), stamped by the snapshot builder. Lets the watch re-check
    /// at DISPLAY time — via `sanitized(asOf:)` — that a persisted snapshot's
    /// Sleep still belongs to today; the phone's build-time `SleepSummary.asOf`
    /// guard can't cover a snapshot that outlives midnight in the App Group
    /// cache. Optional so snapshots from before this field decode (nil ⇒
    /// unknown, treated as not-today by `sanitized`).
    var sleepNight: Date? = nil

    /// Identifies the phone install that produced this snapshot: a UUID
    /// persisted in phone UserDefaults, regenerated on reinstall / data reset.
    /// Together with `revision` it lets the watch order snapshots WITHOUT
    /// trusting the device clock — a rollback can't make a stale payload outrank
    /// a newer one (see `supersedes`). Optional so a legacy payload (no epoch,
    /// from an older phone) still decodes and falls back to the `generatedAt`
    /// rule.
    var publisherEpoch: String? = nil
    /// Monotonic counter WITHIN `publisherEpoch`, persisted and advanced on the
    /// phone each time it publishes. Authoritative over `generatedAt` when the
    /// epochs match, so it survives a clock rollback. Optional/defaulted for
    /// schema evolution; a watch-local live HR/HRV refresh never advances it.
    var revision: UInt64? = nil

    /// Set by the phone's Clear-Cache path: this is a reset tombstone — empty
    /// metrics that the watch must ADOPT (replacing its snapshot) rather than
    /// blank-preserve merge, so cleared data doesn't linger. It still rides the
    /// normal `(publisherEpoch, revision)` ordering (`supersedes`), so a stale
    /// lower-revision push can't resurrect the data it cleared, and the watch
    /// persists it as a tombstone to keep that ordering across a restart.
    /// Optional so phone/watch version skew still decodes (an older watch just
    /// merges the empty-metrics payload, which clears it anyway).
    var isReset: Bool? = nil

    /// Pushed data older than this is stale: the watch app live-refreshes
    /// HR/HRV past it, and the complication timeline re-checks on the same
    /// cadence.
    static let staleInterval: TimeInterval = 30 * 60

    static let empty = WatchMetricsSnapshot(
        generatedAt: .distantPast,
        lastRefreshDate: nil,
        metrics: []
    )

    /// Representative sample data for the complication gallery — never shown
    /// on a configured complication (real timelines read the cached store).
    static let placeholder = WatchMetricsSnapshot(
        generatedAt: .distantPast,
        lastRefreshDate: nil,
        metrics: [
            WatchMetric(kind: WatchMetricKindKey.readiness, title: String(localized: "Readiness", table: "BodyWatchShared"), displayValue: "78", unit: "%", score: 78, fillFraction: 0.78, rawValue: 78, rangeMin: 0, rangeMax: 100, levelMin: 65, levelMax: 79, tint: WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20)),
            WatchMetric(kind: WatchMetricKindKey.sleep, title: String(localized: "Sleep", table: "BodyWatchShared"), displayValue: "7h 32m", unit: "", score: 85, fillFraction: 0.85, rawValue: 85, rangeMin: 0, rangeMax: 100),
            WatchMetric(kind: WatchMetricKindKey.heartRate, title: String(localized: "Heart Rate", table: "BodyWatchShared"), displayValue: "62", unit: "bpm", score: nil, fillFraction: 0.45, rawValue: 62, rangeMin: 54, rangeMax: 72),
            WatchMetric(kind: WatchMetricKindKey.heartRateVariability, title: String(localized: "HRV", table: "BodyWatchShared"), displayValue: "48", unit: "ms", score: nil, fillFraction: 0.60, rawValue: 48, rangeMin: 30, rangeMax: 60),
            WatchMetric(kind: WatchMetricKindKey.restingHeartRate, title: String(localized: "Resting HR", table: "BodyWatchShared"), displayValue: "56", unit: "bpm", score: nil, fillFraction: 0.70, rawValue: 56, rangeMin: 52, rangeMax: 64),
            WatchMetric(kind: WatchMetricKindKey.trainingLoad, title: String(localized: "Training Load", table: "BodyWatchShared"), displayValue: "1.05", unit: "", score: nil, fillFraction: 0.53, rawValue: 1.05, rangeMin: 0, rangeMax: 2, levelMin: 0.8, levelMax: 1.3, tint: WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20)),
            WatchMetric(kind: WatchMetricKindKey.wristTemperature, title: String(localized: "Skin Temp", table: "BodyWatchShared"), displayValue: "93.4", unit: "°F", score: nil, fillFraction: 0.50, rawValue: 34.1, rangeMin: 33.8, rangeMax: 34.4)
        ]
    )

    func metric(forKind kind: String) -> WatchMetric? {
        metrics.first { $0.kind == kind }
    }

    /// Whether this snapshot should replace `other` on the watch — the ordering
    /// that survives a device-clock rollback. When both carry the same
    /// `publisherEpoch`, the monotonic `revision` is authoritative (a rolled-back
    /// clock can't let an older payload's `generatedAt` outrank a newer one);
    /// equal revisions tie-break on `generatedAt`. A different or unknown epoch
    /// means a reinstall/reset produced this payload, so accept it and adopt its
    /// epoch (reinstall wins). When neither side carries an epoch (a legacy
    /// payload), fall back to the plain `generatedAt` rule.
    func supersedes(_ other: WatchMetricsSnapshot) -> Bool {
        switch (publisherEpoch, other.publisherEpoch) {
        case let (epoch?, otherEpoch?) where epoch == otherEpoch:
            let revision = revision ?? 0
            let otherRevision = other.revision ?? 0
            return revision == otherRevision
                ? generatedAt > other.generatedAt
                : revision > otherRevision
        case (nil, nil):
            return generatedAt > other.generatedAt
        default:
            return true
        }
    }

    /// Metrics in dashboard display order, skipping any kind absent from this
    /// snapshot. Shared by the watch dashboard and its settings list.
    var orderedMetrics: [WatchMetric] {
        WatchMetricKindKey.displayOrder.compactMap { metric(forKind: $0) }
    }

    /// Display-time staleness guard mirroring the phone's build-time
    /// `SleepSummary.asOf`: a persisted snapshot (App Group cache) can outlive
    /// midnight, so re-check that its carried Sleep metric still belongs to
    /// `now`'s day. When `sleepNight` is a prior day — or unknown (nil, e.g. a
    /// snapshot built before this field existed, or by an older phone) — the
    /// Sleep metric is cleared to the builder's "--"/nil-score empty state so
    /// the watch app and complications never show yesterday's sleep as today's.
    /// A blanked legacy snapshot is corrected on the next phone push (at most
    /// one sync away), which we prefer over presenting a night we can't verify.
    func sanitized(asOf now: Date = Date()) -> WatchMetricsSnapshot {
        // Sleep is the only date-bound metric; nothing to do if it's absent or
        // still belongs to today.
        guard metric(forKind: WatchMetricKindKey.sleep) != nil,
              !isSleepNightCurrent(asOf: now) else { return self }
        var copy = self
        copy.metrics = metrics.map { $0.kind == WatchMetricKindKey.sleep ? $0.cleared() : $0 }
        return copy
    }

    private func isSleepNightCurrent(asOf now: Date) -> Bool {
        guard let sleepNight else { return false }
        // Same day-boundary convention as `SleepSummary.asOf` (Gregorian, local
        // time zone). `Calendar.bodyGregorian` isn't linked into the watch
        // widget target, but it only differs by `firstWeekday`, which doesn't
        // affect `isDate(_:inSameDayAs:)`.
        return Calendar(identifier: .gregorian).isDate(sleepNight, inSameDayAs: now)
    }
}

extension WatchMetricsSnapshot {
    /// Deterministic encoding (sorted keys) so the WatchConnectivity payload and
    /// the on-watch cache dedupe byte-for-byte.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    static func decoded(from data: Data) -> WatchMetricsSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WatchMetricsSnapshot.self, from: data)
        } catch {
            Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchSnapshot")
                .error("Snapshot decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
