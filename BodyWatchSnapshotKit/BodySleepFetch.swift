//
//  BodySleepFetch.swift
//  BodyWatchSnapshotKit
//
//  The sleep query + assembly leaves shared by Body and BodyWatch: the sleep
//  timeline sample query, the per-wake-day grouping that feeds both the sleep
//  card and sleep history, and the batched nocturnal-vitals window query with
//  its per-night averaging. The iOS `HealthKitFetchEngine` keeps the
//  permission gates, source resolution, cache merging and `QueryOutcome`
//  plumbing and calls in here; the watch's later on-device compute runs the
//  same leaves so a night is sessionized, dated and averaged identically on
//  both devices (a hand-forked watch sleep fetch is what produced the 26-hour
//  night in the first standalone-compute attempt).
//

import Foundation
import HealthKit

/// One transformed quantity sample inside the batched sleep-vitals window.
struct SleepVitalWindowSample: Equatable {
    let startDate: Date
    let endDate: Date
    let value: Double

    init(startDate: Date, endDate: Date, value: Double) {
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
    }
}

/// A wake day's merged `SleepDaySummary` (all sessions ending that day) paired
/// with the main night's span, which bounds that day's nocturnal-vitals window.
struct SleepDayGrouping {
    let day: SleepDaySummary
    let mainSessionInterval: DateInterval?

    init(day: SleepDaySummary, mainSessionInterval: DateInterval?) {
        self.day = day
        self.mainSessionInterval = mainSessionInterval
    }
}

enum BodySleepFetch {
    /// The sleep timeline samples in a window, already filtered to the stages
    /// that make up a night (`isSleepTimelineSample` drops `inBed` and other
    /// non-timeline categories, which would otherwise double-count the night).
    /// `sort` is the caller's: the summary path reads newest-first, the history
    /// path oldest-first.
    static func sleepSamples(
        store: HKHealthStore,
        predicate: NSPredicate?,
        sort: NSSortDescriptor,
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<[HKCategorySample]> {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return .success([])
        }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    onFailure?(error)
                    continuation.resume(returning: .failure)
                    return
                }

                continuation.resume(
                    returning: .success(
                        (samples as? [HKCategorySample] ?? [])
                            .filter(BodySleepSampleParser.isSleepTimelineSample)
                    )
                )
            }

            store.execute(query)
        }
    }

    /// Groups sleep timeline samples into per-wake-day summaries. Each wake day
    /// merges every session that ends that day (naps preserved alongside the
    /// night), while `mainSessionInterval` carries the main night's span so the
    /// nocturnal-vitals window stays bounded to the night. Sorted ascending by
    /// wake day so per-night vital intervals stay ascending/non-overlapping.
    ///
    /// Sleep samples from an Apple Watch carry no `HKMetadataKeyTimeZone`, so
    /// the parser leaves the zone nil and `timeZoneIdentifier` back-fills it for
    /// the wake day — iOS passes its `BodyTimeZoneLedger`, the watch its seeded
    /// day → zone map. Timezone-aware scoring needs it to recognize a travel
    /// night instead of always reading the night in the current zone.
    static func sleepDayGroupings(
        from sleepSamples: [HKCategorySample],
        calendar: Calendar,
        showsSubMinuteAwakeStages: Bool,
        showsLeadingTrailingAwakeStages: Bool,
        timeZoneIdentifier: (Date) -> String?
    ) -> [SleepDayGrouping] {
        BodySleepSessionizer.sessionsByWakeDay(from: sleepSamples, calendar: calendar)
            .compactMap { wakeDay, sessions -> SleepDayGrouping? in
                guard let summary = sleepSummary(
                    from: sessions.flatMap(\.samples),
                    date: wakeDay,
                    showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
                    showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages,
                    timeZoneIdentifier: timeZoneIdentifier
                ) else {
                    return nil
                }

                return SleepDayGrouping(
                    day: SleepDaySummary(date: wakeDay, summary: summary),
                    mainSessionInterval: BodySleepSessionizer.mainSession(in: sessions)?.interval
                )
            }
            .sorted { $0.day.date < $1.day.date }
    }

    /// One night's summary: the shared parser's result with its time zone
    /// back-filled from `timeZoneIdentifier` when the samples carried none.
    static func sleepSummary(
        from samples: [HKCategorySample],
        date: Date,
        showsSubMinuteAwakeStages: Bool = true,
        showsLeadingTrailingAwakeStages: Bool = true,
        timeZoneIdentifier: (Date) -> String?
    ) -> SleepSummary? {
        guard var summary = BodySleepSampleParser.sleepSummary(
            from: samples,
            date: date,
            showsSubMinuteAwakeStages: showsSubMinuteAwakeStages,
            showsLeadingTrailingAwakeStages: showsLeadingTrailingAwakeStages
        ) else {
            return nil
        }

        if summary.stageSnapshot.timeZoneIdentifier == nil,
           let zoneIdentifier = timeZoneIdentifier(date) {
            summary.stageSnapshot.timeZoneIdentifier = zoneIdentifier
        }
        return summary
    }

    /// All samples for one vital across a batch of night intervals, in ONE
    /// query (an OR-compound of the per-night predicates, optionally ANDed with
    /// the metric's source predicate), sorted ascending by start date, with the
    /// per-sample value transform already applied — matching `dailyQuantityValue`,
    /// which transforms before averaging. Batching keeps a full-history sleep
    /// refresh at one query per vital instead of one per night.
    static func vitalWindowSamples(
        store: HKHealthStore,
        quantityType: HKQuantityType,
        intervals: [DateInterval],
        sourcePredicate: NSPredicate?,
        unit: HKUnit,
        valueTransform: @escaping (Double) -> Double = { $0 },
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<[SleepVitalWindowSample]> {
        let intervalPredicates = intervals.map { interval in
            HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        }
        var predicates: [NSPredicate] = [
            intervalPredicates.count == 1
                ? intervalPredicates[0]
                : NSCompoundPredicate(orPredicateWithSubpredicates: intervalPredicates)
        ]
        if let sourcePredicate {
            predicates.append(sourcePredicate)
        }
        let predicate = predicates.count == 1
            ? predicates[0]
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    onFailure?(error)
                    continuation.resume(returning: .failure)
                    return
                }
                let windowSamples = samples.compactMap { sample -> SleepVitalWindowSample? in
                    guard let quantitySample = sample as? HKQuantitySample else {
                        return nil
                    }
                    let value = valueTransform(quantitySample.quantity.doubleValue(for: unit))
                    guard value.isFinite else {
                        return nil
                    }
                    return SleepVitalWindowSample(
                        startDate: quantitySample.startDate,
                        endDate: quantitySample.endDate,
                        value: value
                    )
                }
                continuation.resume(returning: .success(windowSamples))
            }

            store.execute(query)
        }
    }

    /// Per-interval averages from window-wide samples. A sample counts toward
    /// an interval when it overlaps it as `HKQuery.predicateForSamples` would
    /// (`[start, end)`, with instantaneous samples at the exact interval start
    /// included), so the batched query + in-memory partition matches the
    /// per-night queries it replaces. `samples` must be sorted ascending by
    /// `startDate`; `intervals` ascending and non-overlapping (nights).
    static func averageVitalValues(
        samples: [SleepVitalWindowSample],
        intervals: [DateInterval]
    ) -> [Double?] {
        guard !samples.isEmpty else {
            return [Double?](repeating: nil, count: intervals.count)
        }

        var base = 0
        return intervals.map { interval in
            // Samples fully before this interval can't match any later
            // interval either; advance the shared base past them once.
            while base < samples.count,
                  samples[base].startDate < interval.start,
                  samples[base].endDate <= interval.start {
                base += 1
            }

            var sum = 0.0
            var count = 0
            var index = base
            while index < samples.count, samples[index].startDate < interval.end {
                let sample = samples[index]
                let overlaps = sample.startDate == sample.endDate
                    ? sample.startDate >= interval.start
                    : sample.endDate > interval.start
                if overlaps {
                    sum += sample.value
                    count += 1
                }
                index += 1
            }
            return count > 0 ? sum / Double(count) : nil
        }
    }
}
