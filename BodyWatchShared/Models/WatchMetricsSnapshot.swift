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

    /// Dashboard / complication ordering.
    static let displayOrder: [String] = [
        readiness, sleep, heartRate, heartRateVariability,
        restingHeartRate, trainingLoad, wristTemperature
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
    /// Set on the watch when this metric was refreshed from watch-local
    /// HealthKit; never set by the iPhone builder. Lets the watch keep a live
    /// reading that's fresher than the vitals a later phone push carries.
    var liveUpdatedAt: Date? = nil

    /// When this metric's underlying data was computed/measured (set by the
    /// snapshot builder). Provenance alongside `WatchMetricsSnapshot.source`.
    var computedAt: Date? = nil

    /// Tint that can't be derived from `kind` alone — Readiness carries its
    /// status-band color here. `nil` ⇒ fall back to the kind's static tint.
    var tint: WatchMetricColor? = nil

    var id: String { kind }

    /// Whether this metric carries a real reading (vs. a `--` placeholder). Used
    /// by the watch merge so an empty value never overwrites a good one. The
    /// sleep metric can have a real duration `displayValue` with no `rawValue`
    /// (its score hidden by the phone's "Show Sleep Score" toggle), so the
    /// placeholder `displayValue` — not just a nil `rawValue` — defines "no value."
    var hasValue: Bool { rawValue != nil || displayValue != "--" }

    /// The tint to render: the carried dynamic `tint`, else the kind default.
    var resolvedTint: WatchMetricColor { tint ?? WatchMetricKindKey.tint(forKind: kind) }
}

/// Schema evolution: the phone and watch can run different builds, so any new
/// field here (or on `WatchMetric`) must be optional or defaulted — a required
/// field would make older watches silently reject the whole payload.
struct WatchMetricsSnapshot: Codable, Equatable {
    var generatedAt: Date
    var lastRefreshDate: Date?
    var metrics: [WatchMetric]
    /// "phone" or "watch" — which device produced this snapshot. Provenance for
    /// telemetry/debug; the merge decides by recency + value presence.
    var source: String? = nil

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
            WatchMetric(kind: WatchMetricKindKey.readiness, title: "Readiness", displayValue: "78", unit: "%", score: 78, fillFraction: 0.78, rawValue: 78, rangeMin: 0, rangeMax: 100),
            WatchMetric(kind: WatchMetricKindKey.sleep, title: "Sleep", displayValue: "7h 32m", unit: "", score: 85, fillFraction: 0.85, rawValue: 85, rangeMin: 0, rangeMax: 100),
            WatchMetric(kind: WatchMetricKindKey.heartRate, title: "Heart Rate", displayValue: "62", unit: "bpm", score: nil, fillFraction: 0.45, rawValue: 62, rangeMin: 54, rangeMax: 72),
            WatchMetric(kind: WatchMetricKindKey.heartRateVariability, title: "HRV", displayValue: "48", unit: "ms", score: nil, fillFraction: 0.60, rawValue: 48, rangeMin: 30, rangeMax: 60),
            WatchMetric(kind: WatchMetricKindKey.restingHeartRate, title: "Resting HR", displayValue: "56", unit: "bpm", score: nil, fillFraction: 0.70, rawValue: 56, rangeMin: 52, rangeMax: 64),
            WatchMetric(kind: WatchMetricKindKey.trainingLoad, title: "Training Load", displayValue: "1.05", unit: "", score: nil, fillFraction: 0.53, rawValue: 1.05, rangeMin: 0, rangeMax: 2),
            WatchMetric(kind: WatchMetricKindKey.wristTemperature, title: "Skin Temp", displayValue: "93.4", unit: "°F", score: nil, fillFraction: 0.50, rawValue: 34.1, rangeMin: 33.8, rangeMax: 34.4)
        ]
    )

    func metric(forKind kind: String) -> WatchMetric? {
        metrics.first { $0.kind == kind }
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
