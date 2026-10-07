//
//  StressBandWatchTint.swift
//  BodyWatchSnapshotKit
//
//  Each Stress band's tint as the watch payload's `WatchMetricColor`, from the
//  same `StressBand.rgbComponents` the iPhone's Stress charts draw with, so the
//  watch card, gauge and week chart band match the phone. Lives here rather
//  than in BodyMetricsKit for the same reason as `ReadinessStatusWatchTint`:
//  `WatchMetricColor` is defined in BodyWatchShared.
//

import Foundation

extension StressBand {
    /// The band's tint as raw RGB.
    var watchTintComponents: WatchMetricColor {
        let rgb = rgbComponents
        return WatchMetricColor(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
