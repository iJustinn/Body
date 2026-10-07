//
//  WatchStressBands.swift
//  BodyWatchShared
//
//  `StressBand`'s four bands for the watch widget extension, which compiles
//  BodyWatchShared but not BodyMetricsKit: the score ranges and colors the
//  Stress bands complication draws. `ProjectConfigurationTests` pins both to
//  `StressBand` so the two can't drift.
//

import Foundation

enum WatchStressBands {
    /// Half-open score ranges over 0..<101 in `StressBand.displayOrder`:
    /// Peace, Relaxed, Engaged, Stressed (`StressBand.band(for:)`).
    static let scoreRanges: [Range<Int>] = [0..<26, 26..<51, 51..<76, 76..<101]

    /// Each band's color, `StressBand.rgbComponents`, in the same order.
    static let tints: [WatchMetricColor] = [
        WatchMetricColor(red: 0.20, green: 0.70, blue: 0.95),
        WatchMetricColor(red: 0.20, green: 0.80, blue: 0.45),
        WatchMetricColor(red: 1.00, green: 0.72, blue: 0.15),
        WatchMetricColor(red: 1.00, green: 0.30, blue: 0.20)
    ]

    /// The color of the band holding `score`, clamped to 0...100.
    static func tint(forScore score: Int) -> WatchMetricColor {
        let clamped = min(max(score, 0), 100)
        return tints[scoreRanges.firstIndex { $0.contains(clamped) } ?? tints.count - 1]
    }
}
