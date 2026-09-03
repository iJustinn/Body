//
//  HealthKitFetchEngine+IntradaySamples.swift
//  Body
//

import Foundation
import HealthKit

// Lazy-loaded intraday samples used by the per-metric detail view's hourly
// chart. These are skipped by `fetchHealthTrends` (too expensive for the
// Home dashboard) and fetched on demand from the consuming view's `.task`.
// The two `nonisolated static` helpers (`incrementalFetchStart` and
// `mergeIntradaySamples`) implement the incremental-merge boundary the
// store uses when calling `fetchIntradayDaySamples` with a non-empty cache.
extension HealthKitFetchEngine {
    /// Returns `nil` when the underlying sample query fails (device locked,
    /// store unavailable, XPC drop, or an unresolved source selection) so the
    /// store keeps the cached day-sample series instead of blanking it; a
    /// successful empty result still replaces it.
    func fetchIntradayDaySamples(
        for kind: HealthMetricKind,
        calendar: Calendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries? {
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              let shape = descriptor.intradayDaySamples else {
            return .empty
        }

        switch shape {
        case .sampleSeries:
            return await fetchQuantitySampleSeries(
                for: descriptor.quantityType,
                unit: descriptor.unit,
                calendar: calendar,
                sourceKind: descriptor.sourceKind,
                valueTransform: descriptor.valueTransform,
                startDate: startDate,
                endDate: endDate
            )
        case .hourlyCumulative:
            return await fetchHourlyCumulativeQuantitySeries(
                for: descriptor.quantityType,
                unit: descriptor.unit,
                calendar: calendar,
                sourceKind: descriptor.sourceKind,
                valueTransform: descriptor.valueTransform,
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    /// Trailing overlap re-fetched on every incremental refresh. HealthKit
    /// arrival order is not time order — the Watch syncs in lagging batches and
    /// third-party sources backfill hours later — so a pure "newest cached
    /// point + epsilon" cursor permanently loses any sample that lands with an
    /// older timestamp after a newer one is already cached. Re-fetching this
    /// window on each refresh lets those late arrivals (and deletions) reconcile.
    /// 48h covers realistic Watch/third-party sync lag; older-than-48h late
    /// arrivals are rare enough to accept.
    nonisolated static let incrementalOverlapWindow: TimeInterval = 48 * 60 * 60

    /// Start date for an incremental sample fetch. Anchored on the latest cached
    /// point minus `incrementalOverlapWindow` (so backfilled samples timestamped
    /// up to the overlap earlier than the newest cached point are re-fetched),
    /// clamped to the start of the trend window. The anchor is the cached point's
    /// date — not wall-clock now — because the newest cached point may itself be
    /// stale. Returns `windowStart` when the cache is empty (first-ever load).
    /// The returned value is the authoritative-refetch boundary that must be
    /// passed to `mergeIntradaySamples(refetchStart:)`.
    nonisolated static func incrementalFetchStart(after cached: HealthTrendSeries, windowStart: Date) -> Date {
        guard let lastDate = cached.points.last?.date else {
            return windowStart
        }
        let overlapStart = lastDate.addingTimeInterval(-incrementalOverlapWindow)
        return max(overlapStart, windowStart)
    }

    /// Merge an incremental sample fetch into the existing cache. The `incoming`
    /// series is the authoritative copy of everything HealthKit currently holds
    /// in `[refetchStart, windowEnd]` (including late arrivals AND reflecting
    /// deletions), so cached points at or after `refetchStart` are REPLACED by
    /// it — never concatenated (which would duplicate) or preserved (which would
    /// resurrect deleted samples). Cached points older than the trend window
    /// (`< windowStart`) are dropped; cached points in `[windowStart,
    /// refetchStart)` are kept as-is. Both inputs are assumed already sorted
    /// ascending by date; `refetchStart` must be the same boundary passed to the
    /// fetch (`incrementalFetchStart`) so the fetch and replace windows align.
    nonisolated static func mergeIntradaySamples(
        existing: HealthTrendSeries,
        incoming: HealthTrendSeries,
        windowStart: Date,
        refetchStart: Date
    ) -> HealthTrendSeries {
        let retained = existing.points.filter { $0.date >= windowStart && $0.date < refetchStart }
        if incoming.points.isEmpty, retained.count == existing.points.count {
            return existing
        }
        return HealthTrendSeries(points: retained + incoming.points)
    }
}
