//
//  ReadinessStatusWatchTint.swift
//  BodyWatchSnapshotKit
//
//  Raw RGB for each readiness status band, shared by the iOS readiness UI and
//  the watch snapshot builder so the watch ring / complication matches the iOS
//  status color exactly. Lives in BodyWatchSnapshotKit (Body + BodyWatch) rather
//  than BodyMetricsKit because it returns `WatchMetricColor` (defined in
//  BodyWatchShared, which the widget extensions don't compile).
//

import Foundation

extension ReadinessStatus {
    /// Status-band tint as raw RGB. `nil` for `.unavailable` (the watch then
    /// falls back to the metric kind's default tint).
    var watchTintComponents: WatchMetricColor? {
        switch self {
        case .prime:
            return WatchMetricColor(red: 0.84, green: 0.08, blue: 0.92)
        case .high:
            return WatchMetricColor(red: 0.20, green: 0.74, blue: 1.00)
        case .moderate:
            return WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20)
        case .low:
            return WatchMetricColor(red: 1.00, green: 0.75, blue: 0.15)
        case .poor:
            return WatchMetricColor(red: 1.00, green: 0.25, blue: 0.12)
        case .unavailable:
            return nil
        }
    }
}

extension TrainingLoadInterval {
    /// Status-band tint as raw RGB, mirroring `BodyTrainingLoadIntervalPresentation`
    /// on iOS so the watch corner gauge matches the iOS training-load colors.
    var watchTintComponents: WatchMetricColor {
        switch self {
        case .stopTraining:
            return WatchMetricColor(red: 0.00, green: 0.88, blue: 0.82)
        case .optimal:
            return WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20)
        case .mediumInjuryRisk:
            return WatchMetricColor(red: 1.00, green: 0.46, blue: 0.10)
        case .highInjuryRisk:
            return WatchMetricColor(red: 1.00, green: 0.17, blue: 0.16)
        }
    }

    /// Corner-gauge [min, max] for this band, closing the open ends: Resting
    /// starts at 0; High Injury Risk caps at 2.0 (matching the full-range fill).
    var watchGaugeBounds: (min: Double, max: Double) {
        (min: lowerBound ?? 0, max: upperBound ?? 2.0)
    }
}
