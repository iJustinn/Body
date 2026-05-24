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

    /// Start date for an incremental sample fetch — the millisecond after the
    /// latest cached point, clamped to the start of the trend window. Returns
    /// `windowStart` when the cache is empty (first-ever load).
    nonisolated static func incrementalFetchStart(after cached: HealthTrendSeries, windowStart: Date) -> Date {
        guard let lastDate = cached.points.last?.date else {
            return windowStart
        }
        let next = lastDate.addingTimeInterval(0.001)
        return max(next, windowStart)
    }

    /// Merge an incremental sample fetch into the existing cache. Drops any
    /// existing points older than the current trend window and appends the
    /// newer points. Both inputs are assumed already sorted ascending by date
    /// and non-overlapping (`incrementalFetchStart` enforces the boundary).
    nonisolated static func mergeIntradaySamples(
        existing: HealthTrendSeries,
        incoming: HealthTrendSeries,
        windowStart: Date
    ) -> HealthTrendSeries {
        let trimmed = existing.points.drop(while: { $0.date < windowStart })
        if incoming.points.isEmpty {
            return trimmed.count == existing.points.count
                ? existing
                : HealthTrendSeries(points: Array(trimmed))
        }
        return HealthTrendSeries(points: Array(trimmed) + incoming.points)
    }
}
