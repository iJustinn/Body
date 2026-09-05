//
//  BodyHealthQuantityFetch.swift
//  BodyWatchSnapshotKit
//
//  The HealthKit quantity query leaves shared by Body and BodyWatch: given a
//  store, a quantity type and a prebuilt predicate, run the query and shape the
//  result. The iOS `HealthKitFetchEngine` keeps everything around them (actor
//  state, permission gates, source resolution, predicate assembly, caching) and
//  calls in here for the query itself, so the watch's later delta re-query runs
//  literally the same code rather than a hand-forked copy that drifts.
//
//  Every core returns `WatchFetchOutcome` (see `WatchDeltaSplicer.swift`) so a
//  query FAILURE stays distinguishable from a genuine absence — the same
//  distinction the engine's `QueryOutcome` carries, and the reason a locked
//  device keeps cached values instead of blanking a card.
//

import Foundation
import HealthKit

/// How a day's samples collapse into that day's single value.
///
/// Shared (rather than nested in the engine) because it decides both the
/// `HKStatisticsOptions` the collection query runs with and which statistic is
/// read back out — a pair the watch must match exactly for its spliced points
/// to be comparable with the phone's.
enum BodyDailyQuantityAggregation: Equatable {
    case average
    case latest

    var statisticsOptions: HKStatisticsOptions {
        switch self {
        case .average:
            return .discreteAverage
        case .latest:
            return .mostRecent
        }
    }

    func quantity(from statistics: HKStatistics) -> HKQuantity? {
        switch self {
        case .average:
            return statistics.averageQuantity()
        case .latest:
            return statistics.mostRecentQuantity()
        }
    }
}

enum BodyHealthQuantityFetch {
    /// The `valueTransform` the percentage reads (SpO₂, body fat) run with:
    /// HealthKit's `.percent()` unit yields a 0…1 fraction for most sources but
    /// some write 0…100 directly, so anything at-or-below 1 is scaled up. Shared
    /// so the watch's delta re-query normalizes identically — an unnormalized
    /// SpO₂ point would splice a 0.97 into a series of 97s.
    @Sendable static func normalizedPercent(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    /// The newest sample of a quantity type matching `predicate`: the query
    /// sorts by end date descending and takes one. The WINDOW is the caller's —
    /// both the phone's `latestQuantity` and the watch's `latestSample` bound it
    /// to the daily trend window so a "latest reading" tile can never outrun its
    /// own chart. Passing a predicate with no date range searches all history.
    ///
    /// Returns the sample itself (not just its value) so callers can stamp
    /// freshness from the sample's real `endDate` instead of inventing one.
    static func latestQuantitySample(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HKQuantitySample?> {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        switch await store.samples(
            BodySampleRequest(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            )
        ) {
        case .failure(let error):
            onFailure?(error)
            return .failure
        case .cancelled:
            return .failure
        case .success(let samples):
            return .success(samples.compactMap({ $0 as? HKQuantitySample }).first)
        }
    }

    /// The newest BEAT of a quantity type matching `predicate`, read via a
    /// discrete-most-recent statistics query instead of a sample query. Some
    /// kinds (heart rate during a workout) are stored as `HKQuantitySeries`
    /// samples, and a plain `HKSampleQuery` returns one aggregated entry per
    /// series blob rather than the individual readings inside it; a
    /// statistics query resolves the series at datum granularity in one round
    /// trip, so this is the "live HR" read `latestQuantitySample` cannot do.
    ///
    /// Returns the quantity and its `mostRecentQuantityDateInterval().end`
    /// (not a sample, since a statistics query has none) so callers can stamp
    /// freshness the same way `latestQuantitySample` callers do.
    static func mostRecentQuantity(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<(quantity: HKQuantity, endDate: Date)?> {
        switch await store.statistics(
            BodyStatisticsRequest(
                quantityType: quantityType,
                predicate: predicate,
                options: .mostRecent
            )
        ) {
        case .failure(let error):
            onFailure?(error)
            return .failure
        case .cancelled:
            return .failure
        case .success(let statistics):
            guard let quantity = statistics.mostRecentQuantity(),
                  let endDate = statistics.mostRecentQuantityDateInterval()?.end else {
                return .success(nil)
            }

            return .success((quantity: quantity, endDate: endDate))
        }
    }

    /// One point per calendar day over `[start, end]`, from a statistics
    /// collection anchored at the window's `startOfDay` with a one-day
    /// interval. Days with no statistic are omitted (not zero-filled), and a
    /// non-finite value is dropped — `valueTransform` is the hook the SpO₂
    /// reads use to normalize a 0…1 fraction into a percentage before that
    /// finiteness check.
    static func dailyQuantitySeries(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        aggregation: BodyDailyQuantityAggregation,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        let anchor = calendar.startOfDay(for: start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        switch await store.dailyQuantities(
            BodyStatisticsCollectionRequest(
                quantityType: quantityType,
                predicate: predicate,
                options: aggregation.statisticsOptions,
                anchorDate: anchor,
                intervalComponents: intervalComponents
            ), aggregation: aggregation, from: start, to: end
        ) {
        case .failure(let error):
            onFailure?(error)
            return .failure
        case .cancelled:
            return .failure
        case .success(let quantities):
            var points: [HealthTrendDataPoint] = []
            for dated in quantities {
                let value = valueTransform(dated.quantity.doubleValue(for: unit))
                guard value.isFinite else {
                    continue
                }

                points.append(
                    HealthTrendDataPoint(
                        date: calendar.startOfDay(for: dated.date),
                        value: value
                    )
                )
            }

            return .success(HealthTrendSeries(points: points))
        }
    }

    /// The latest day's value of `dailyQuantitySeries` — the summary tile for a
    /// metric whose headline is "the most recent day we have", not "the most
    /// recent sample". A window with no points at all is a genuine absence
    /// (`.success(nil)`), which clears the tile; only a query failure keeps it.
    static func dailyQuantitySummary(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        aggregation: BodyDailyQuantityAggregation,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthMetricSummary?> {
        let series = await dailyQuantitySeries(
            store: store,
            quantityType: quantityType,
            predicate: predicate,
            aggregation: aggregation,
            unit: unit,
            start: start,
            end: end,
            calendar: calendar,
            valueTransform: valueTransform,
            onFailure: onFailure
        )

        switch series {
        case .failure:
            return .failure
        case .success(let series):
            guard let latestPoint = series.points.last else {
                return .success(nil)
            }
            return .success(HealthMetricSummary(value: latestPoint.value))
        }
    }
}
