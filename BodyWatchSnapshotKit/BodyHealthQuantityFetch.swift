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

    /// Every sample of a quantity type matching `predicate`, one point per
    /// sample dated at its `endDate`, ascending: the intraday day-sample shape
    /// behind the Day View charts and Stress (heart rate, SDNN, Recovery HRV).
    /// No limit, so the predicate's window is the only bound. A non-finite
    /// value after `valueTransform` is dropped.
    static func quantitySampleSeries(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        unit: HKUnit,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        switch await store.samples(
            BodySampleRequest(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            )
        ) {
        case .failure(let error):
            onFailure?(error)
            return .failure
        case .cancelled:
            return .failure
        case .success(let samples):
            let points = samples.compactMap { sample -> HealthTrendDataPoint? in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                let value = valueTransform(quantitySample.quantity.doubleValue(for: unit))
                guard value.isFinite else { return nil }
                return HealthTrendDataPoint(date: quantitySample.endDate, value: value)
            }
            return .success(HealthTrendSeries(points: points))
        }
    }

    /// One point per hour over `[start, end]`, from a one-hour cumulative-sum
    /// collection anchored at the hour containing `start`: the intraday shape
    /// of steps and active energy, and Stress's movement mask. Each point is
    /// dated at its hour's start. An hour with no sum, a non-finite value or a
    /// value at or below zero is omitted, so an idle hour reads as absent
    /// rather than as a zero bar.
    static func hourlyCumulativeSeries(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        var intervalComponents = DateComponents()
        intervalComponents.hour = 1
        let anchor = calendar.dateInterval(of: .hour, for: start)?.start ?? start

        switch await store.cumulativeQuantities(
            BodyStatisticsCollectionRequest(
                quantityType: quantityType,
                predicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: intervalComponents
            ), from: start, to: end
        ) {
        case .failure(let error):
            onFailure?(error)
            return .failure
        case .cancelled:
            return .failure
        case .success(let sums):
            var points: [HealthTrendDataPoint] = []
            for dated in sums {
                let value = valueTransform(dated.quantity.doubleValue(for: unit))
                guard value.isFinite, value > 0 else {
                    continue
                }

                points.append(HealthTrendDataPoint(date: dated.date, value: value))
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

    /// One min/max point per calendar day over `[start, end]`, the daily range
    /// series behind the Heart Rate and HRV week charts' capsules: the same
    /// one-day collection (anchored at the window's `startOfDay`, average + min
    /// + max) the iOS engine's `fetchDailyQuantityAverageAndRangeSeries` runs,
    /// with its exact point rule. A day gets a point only when its average,
    /// minimum AND maximum are all present and finite after `valueTransform`,
    /// dated to the day's start, with the average as `averageValue`. Anything
    /// looser would let the watch draw a capsule the phone's chart never shows.
    static func dailyQuantityRangeSeries(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendRangeSeries> {
        let anchor = calendar.startOfDay(for: start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        switch await store.dailyQuantityRanges(
            BodyStatisticsCollectionRequest(
                quantityType: quantityType,
                predicate: predicate,
                options: [.discreteAverage, .discreteMin, .discreteMax],
                anchorDate: anchor,
                intervalComponents: intervalComponents
            ), from: start, to: end
        ) {
        case .failure(let error):
            onFailure?(error)
            return .failure
        case .cancelled:
            return .failure
        case .success(let ranges):
            var points: [HealthTrendRangeDataPoint] = []
            for dated in ranges {
                guard let minimum = dated.minimum,
                      let maximum = dated.maximum,
                      let average = dated.average else {
                    continue
                }

                let low = valueTransform(minimum.doubleValue(for: unit))
                let high = valueTransform(maximum.doubleValue(for: unit))
                let averageValue = valueTransform(average.doubleValue(for: unit))
                guard low.isFinite, high.isFinite, averageValue.isFinite else {
                    continue
                }

                points.append(
                    HealthTrendRangeDataPoint(
                        date: calendar.startOfDay(for: dated.date),
                        lowValue: low,
                        highValue: high,
                        averageValue: averageValue
                    )
                )
            }

            return .success(HealthTrendRangeSeries(points: points))
        }
    }
}
