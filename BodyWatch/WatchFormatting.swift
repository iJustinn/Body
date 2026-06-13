//
//  WatchFormatting.swift
//  BodyWatch
//
//  Tiny watch-side helpers for the live HR/HRV refresh path. (The iPhone owns
//  all canonical formatting via `BodyValueFormat`; this is only used to format
//  the value the watch reads directly from HealthKit.)
//

import Foundation

enum WatchValueFormat {
    static func number(_ value: Double, decimals: Int) -> String {
        // Locale-aware, matching the phone's `BodyValueFormat.numberText`.
        value.formatted(.number.precision(.fractionLength(max(decimals, 0))))
    }
}

enum WatchRingFill {
    /// Recompute a 0...1 ring fill for a freshly-read value against the range
    /// the iPhone carried in the snapshot. Falls back to a half-full ring.
    static func fraction(of value: Double, min lower: Double?, max upper: Double?) -> Double {
        guard let lower, let upper, upper > lower else { return 0.5 }
        return Swift.min(Swift.max((value - lower) / (upper - lower), 0), 1)
    }
}
