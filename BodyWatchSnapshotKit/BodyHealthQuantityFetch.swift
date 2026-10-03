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

/// The bucket an intraday cumulative series (steps, active energy) sums into.
///
/// It carries both the interval and the anchor, because the two only make sense
/// together: the Day View's hourly bars start on the hour, while Stress's movement
/// mask needs every bucket to be exactly one of its 15 minute windows, which the
/// grid builds from the day's midnight.
enum BodyIntradayBucket: Equatable, Sendable {
    /// The Day View's hourly bars, anchored at the hour holding `start`.
    case hour
    /// Stress's movement mask, anchored at `start`'s midnight so each bucket is one window.
    case quarterHour

    func anchor(for start: Date, calendar: Calendar) -> Date {
        switch self {
        case .hour:
            return calendar.dateInterval(of: .hour, for: start)?.start ?? start
        case .quarterHour:
            return calendar.startOfDay(for: start)
        }
    }

    var intervalComponents: DateComponents {
        switch self {
        case .hour:
            return DateComponents(hour: 1)
        case .quarterHour:
            return DateComponents(minute: 15)
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

    /// One point per `bucket` over `[start, end]`, from a cumulative-sum
    /// collection anchored by the bucket: hourly for the intraday shape of
    /// steps and active energy, 15 minutes from midnight for Stress's movement
    /// mask. Each point is dated at its bucket's start. A bucket with no sum, a
    /// non-finite value or a value at or below zero is omitted, so an idle
    /// bucket reads as absent rather than as a zero bar.
    static func intradayCumulativeSeries(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        unit: HKUnit,
        bucket: BodyIntradayBucket,
        start: Date,
        end: Date,
        calendar: Calendar,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<HealthTrendSeries> {
        switch await store.cumulativeQuantities(
            BodyStatisticsCollectionRequest(
                quantityType: quantityType,
                predicate: predicate,
                options: .cumulativeSum,
                anchorDate: bucket.anchor(for: start, calendar: calendar),
                intervalComponents: bucket.intervalComponents
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

    /// One point per calendar day over `[start, end]`, from a one-day
    /// cumulative-sum collection anchored at the window's `startOfDay`: the
    /// daily-total shape of steps, active energy and resting energy, read on
    /// the watch for the week behind their cards and 7 day bars. Each point is
    /// dated at its day's start. A day with no sum or a non-finite value is
    /// omitted and a finite zero is kept, exactly as the phone's
    /// `fetchDailyCumulativeQuantitySeries` does, so the watch's week and
    /// today's total read the same as the iPhone's for the same samples
    /// (unlike `intradayCumulativeSeries`, whose idle buckets are absent by
    /// design).
    ///
    /// Resting energy (`.basalEnergyBurned`) applies that engine's
    /// scale-estimate rule: the samples of
    /// `BodyRestingEnergyEstimates.minimumKilocalories` or more under the
    /// caller's predicate are read on their own and folded per source and day
    /// (`BodyRestingEnergyEstimates.fold`), the collection sums only the
    /// smaller ones, and each day's estimate total is added back before
    /// `valueTransform`, so a day holding only an estimate still gets a point
    /// (carrying the repeated estimates as `records`, like the phone's). When
    /// that sample read fails the plain sum is used, as on the phone.
    static func dailyCumulativeSeries(
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
        let anchor = calendar.startOfDay(for: start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        var estimates: RestingEnergyEstimates?
        if quantityType.identifier == HKQuantityTypeIdentifier.basalEnergyBurned.rawValue {
            switch await restingEnergyEstimates(
                store: store,
                quantityType: quantityType,
                predicate: predicate,
                unit: unit,
                calendar: calendar
            ) {
            case .cancelled:
                // The run is being torn down: the collection below would only
                // be cancelled too.
                return .failure
            case .failed:
                estimates = nil
            case .read(let read):
                estimates = read
            }
        }

        switch await store.cumulativeQuantities(
            BodyStatisticsCollectionRequest(
                quantityType: quantityType,
                predicate: estimates?.sumPredicate ?? predicate,
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
            var sumsByDay: [Date: Double] = [:]
            for dated in sums {
                sumsByDay[calendar.startOfDay(for: dated.date)] = dated.quantity.doubleValue(for: unit)
            }

            // A day holding only an estimate has no sum to enumerate.
            let days = Set(sumsByDay.keys).union(estimates?.days.keys.map { $0 } ?? [])
            let points = days.sorted().compactMap { day -> HealthTrendDataPoint? in
                let estimate = estimates?.days[day]
                let value = valueTransform((sumsByDay[day] ?? 0) + (estimate?.total ?? 0))
                guard value.isFinite else {
                    return nil
                }
                let records = estimate?.records ?? []
                return HealthTrendDataPoint(date: day, value: value, records: records.isEmpty ? nil : records)
            }

            return .success(HealthTrendSeries(points: points))
        }
    }

    /// The large resting energy samples `dailyCumulativeSeries` adds back per
    /// day, and the predicate its collection sums the rest under.
    private struct RestingEnergyEstimates {
        /// The caller's predicate AND below the estimate threshold: everything
        /// but the large samples `days` accounts for.
        let sumPredicate: NSPredicate
        let days: [Date: BodyRestingEnergyEstimates.Day]
    }

    private enum RestingEnergyEstimatesRead {
        case read(RestingEnergyEstimates)
        case failed
        case cancelled
    }

    /// The phone engine's `dailyEstimates(for:...)` query through the store
    /// seam: the samples at or above the threshold under the caller's
    /// predicate (window and source), folded by the shared
    /// `BodyRestingEnergyEstimates.fold`.
    private static func restingEnergyEstimates(
        store: any BodyHealthQuerying,
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        unit: HKUnit,
        calendar: Calendar
    ) async -> RestingEnergyEstimatesRead {
        let threshold = HKQuantity(unit: .kilocalorie(), doubleValue: BodyRestingEnergyEstimates.minimumKilocalories)
        func bounded(_ comparison: NSComparisonPredicate.Operator) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate, HKQuery.predicateForQuantitySamples(with: comparison, quantity: threshold)
            ].compactMap { $0 })
        }

        switch await store.samples(
            BodySampleRequest(
                sampleType: quantityType,
                predicate: bounded(.greaterThanOrEqualTo),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: []
            )
        ) {
        case .failure:
            return .failed
        case .cancelled:
            return .cancelled
        case .success(let samples):
            let estimateSamples = samples.compactMap { sample -> BodyRestingEnergyEstimates.Sample? in
                guard let quantitySample = sample as? HKQuantitySample else { return nil }
                return BodyRestingEnergyEstimates.Sample(
                    start: quantitySample.startDate,
                    end: quantitySample.endDate,
                    source: quantitySample.sourceRevision.source.bundleIdentifier,
                    value: quantitySample.quantity.doubleValue(for: unit)
                )
            }
            return .read(RestingEnergyEstimates(
                sumPredicate: bounded(.lessThan),
                days: BodyRestingEnergyEstimates.fold(samples: estimateSamples, calendar: calendar)
            ))
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
