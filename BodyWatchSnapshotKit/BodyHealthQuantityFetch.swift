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
enum BodyDailyQuantityAggregation {
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
    static func normalizedPercent(_ value: Double) -> Double {
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
        store: HKHealthStore,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HKQuantitySample?> {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    onFailure?(error)
                    continuation.resume(returning: .failure)
                    return
                }

                continuation.resume(
                    returning: .success(samples.compactMap({ $0 as? HKQuantitySample }).first)
                )
            }

            store.execute(query)
        }
    }

    /// One point per calendar day over `[start, end]`, from a statistics
    /// collection anchored at the window's `startOfDay` with a one-day
    /// interval. Days with no statistic are omitted (not zero-filled), and a
    /// non-finite value is dropped — `valueTransform` is the hook the SpO₂
    /// reads use to normalize a 0…1 fraction into a percentage before that
    /// finiteness check.
    static func dailyQuantitySeries(
        store: HKHealthStore,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        aggregation: BodyDailyQuantityAggregation,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        let anchor = calendar.startOfDay(for: start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: aggregation.statisticsOptions,
                anchorDate: anchor,
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    onFailure?(error)
                    continuation.resume(returning: .failure)
                    return
                }

                var points: [HealthTrendDataPoint] = []
                statisticsCollection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = aggregation.quantity(from: statistics) else {
                        return
                    }

                    let value = valueTransform(quantity.doubleValue(for: unit))
                    guard value.isFinite else {
                        return
                    }

                    points.append(
                        HealthTrendDataPoint(
                            date: calendar.startOfDay(for: statistics.startDate),
                            value: value
                        )
                    )
                }

                continuation.resume(returning: .success(HealthTrendSeries(points: points)))
            }

            store.execute(query)
        }
    }

    /// The latest day's value of `dailyQuantitySeries` — the summary tile for a
    /// metric whose headline is "the most recent day we have", not "the most
    /// recent sample". A window with no points at all is a genuine absence
    /// (`.success(nil)`), which clears the tile; only a query failure keeps it.
    static func dailyQuantitySummary(
        store: HKHealthStore,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        aggregation: BodyDailyQuantityAggregation,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 },
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
