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
    func fetchIntradayDaySamples(
        for kind: HealthMetricKind,
        calendar: Calendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries {
        switch kind {
        case .heartRate:
            return await fetchQuantitySampleSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate,
                startDate: startDate,
                endDate: endDate
            )
        case .restingHeartRate:
            return await fetchQuantitySampleSeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .restingHeartRate,
                startDate: startDate,
                endDate: endDate
            )
        case .heartRateVariability:
            return await fetchQuantitySampleSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability,
                startDate: startDate,
                endDate: endDate
            )
        case .respiratoryRate:
            return await fetchQuantitySampleSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .respiratoryRate,
                startDate: startDate,
                endDate: endDate
            )
        case .oxygenSaturation:
            return await fetchQuantitySampleSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue,
                startDate: startDate,
                endDate: endDate
            )
        case .activeEnergy:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy,
                startDate: startDate,
                endDate: endDate
            )
        case .steps:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps,
                startDate: startDate,
                endDate: endDate
            )
        default:
            return .empty
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
