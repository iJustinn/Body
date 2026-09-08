//
//  HealthKitFetchEngine+Secondary.swift
//  Body
//

import Foundation
import HealthKit

// Secondary-source fetch dispatchers. When the user has chosen a "compare
// to" source for a metric in Settings > Data > Source (or per-metric in a
// detail page), these methods route the per-metric kind to the right HK
// query shape for the *secondary* series. The primary series uses the
// orchestrators in `HealthKitFetchEngine.swift`.
extension HealthKitFetchEngine {
    /// Returns `nil` when the underlying secondary query FAILS (device locked,
    /// store unavailable, unresolved secondary selection) so the trend assembly
    /// keeps the cached secondary series; a no-comparison selection or an
    /// unsupported metric returns an intentional `.empty` that clears it.
    func fetchSecondaryTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendSeries? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        // Sleep is the one comparison series that is not a quantity query.
        if kind == .sleep {
            return await fetchSecondarySleepHistory(calendar: calendar)?.durationSeries
        }
        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              descriptor.secondaryTrend else {
            return .empty
        }

        switch descriptor.trend {
        case .daily(let aggregation):
            return await fetchDailyQuantitySeries(
                for: descriptor.quantityType,
                unit: descriptor.unit,
                aggregation: aggregation,
                calendar: calendar,
                sourceKind: descriptor.sourceKind,
                sourceOption: secondaryOption,
                valueTransform: descriptor.valueTransform
            )
        case .dailyCumulative:
            return await fetchDailyCumulativeQuantitySeries(
                for: descriptor.quantityType,
                unit: descriptor.unit,
                calendar: calendar,
                sourceKind: descriptor.sourceKind,
                sourceOption: secondaryOption,
                valueTransform: descriptor.valueTransform
            )
        case .averageAndRange:
            // No kind carries both a comparison average series and a range one;
            // the range kinds are served by `fetchSecondaryRangeTrend`.
            return .empty
        }
    }

    /// Returns `nil` when the grouping query FAILS so the assembly keeps the
    /// cached secondary sleep history; no-comparison returns an intentional
    /// `.empty`. Never hydrates vitals (the comparison series only needs duration).
    func fetchSecondarySleepHistory(calendar: Calendar) async -> SleepHistorySnapshot? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: .sleep)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        return await fetchDailySleepHistory(
            calendar: calendar,
            sourceOption: secondaryOption,
            hydrateVitals: false
        ).history
    }

    /// Returns `nil` when the underlying sample query fails (device locked,
    /// store unavailable, or an unresolved secondary source selection) so the
    /// store keeps the cached secondary day-sample series instead of blanking
    /// it; a successful empty result still replaces it.
    func fetchSecondaryDaySamples(
        for kind: HealthMetricKind,
        calendar: Calendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              let shape = descriptor.secondaryDaySamples else {
            return .empty
        }

        switch shape {
        case .sampleSeries:
            return await fetchQuantitySampleSeries(
                for: descriptor.quantityType,
                unit: descriptor.unit,
                calendar: calendar,
                sourceKind: descriptor.sourceKind,
                sourceOption: secondaryOption,
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
                sourceOption: secondaryOption,
                valueTransform: descriptor.valueTransform,
                startDate: startDate,
                endDate: endDate
            )
        }
    }

    /// Returns `nil` when the underlying range query FAILS (device locked, store
    /// unavailable, unresolved secondary selection) so the assembly keeps the
    /// cached secondary range series; a no-comparison selection or an unsupported
    /// metric returns an intentional `.empty` that clears it.
    func fetchSecondaryRangeTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendRangeSeries? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        guard let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind),
              descriptor.secondaryRangeTrend else {
            return .empty
        }

        return await fetchDailyQuantityRangeSeries(
            for: descriptor.quantityType,
            unit: descriptor.unit,
            calendar: calendar,
            sourceKind: descriptor.sourceKind,
            sourceOption: secondaryOption,
            valueTransform: descriptor.valueTransform
        )
    }
}
