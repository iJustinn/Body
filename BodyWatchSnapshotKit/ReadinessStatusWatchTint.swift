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
