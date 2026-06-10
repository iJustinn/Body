//
//  HealthKitFetchEngine+Sleep.swift
//  Body
//

import Foundation
import HealthKit

// Sleep summary, daily history, and per-sleep-day vitals hydration.
// Split out of `HealthKitFetchEngine.swift` to keep the main file focused on
// orchestration and shared helpers. These actor methods call into shared
// predicate / interval / permission helpers that live on the main engine
// file with internal access so this extension can reach them.
extension HealthKitFetchEngine {
    func fetchSleepSummary(calendar: Calendar) async -> SleepSummary? {
        guard permissionSelection.includes(.sleep) else {
            return nil
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -14, to: endDate) ?? endDate.addingTimeInterval(-1_209_600)
        let predicate = combinedPredicate(startDate: startDate, endDate: endDate, sourceKind: .sleep)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let summary: SleepSummary? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let sleepSamples = (samples as? [HKCategorySample] ?? [])
                    .filter(Self.isSleepTimelineSample)
                let samplesByDay = Dictionary(grouping: sleepSamples) {
                    calendar.startOfDay(for: $0.endDate)
                }

                let summaries = samplesByDay.compactMap { day, daySamples -> SleepSummary? in
                    Self.sleepSummary(from: daySamples, date: day)
                }

                continuation.resume(
                    returning: summaries.max { lhs, rhs in
                        (lhs.stageSnapshot.date ?? .distantPast) < (rhs.stageSnapshot.date ?? .distantPast)
                    }
                )
            }

            healthStore.execute(query)
        }

        guard var summary, let interval = summary.stageSnapshot.dateInterval else {
            return summary
        }

        summary.vitals = await fetchSleepVitals(
            startDate: interval.start,
            endDate: interval.end
        )
        return summary
    }

    func fetchDailySleepHistory(
        calendar: Calendar,
        sourceOption: BodyHealthDataSourceOption? = nil,
        hydrateVitals: Bool = true
    ) async -> SleepHistorySnapshot {
        guard permissionSelection.includes(.sleep) else {
            return .empty
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: .sleep,
            sourceOption: sourceOption
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let days: [SleepDaySummary] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let sleepSamples = (samples as? [HKCategorySample] ?? [])
                    .filter(Self.isSleepTimelineSample)
                let samplesByDay = Dictionary(grouping: sleepSamples) {
                    calendar.startOfDay(for: $0.endDate)
                }

                let days = samplesByDay.compactMap { day, daySamples -> SleepDaySummary? in
                    guard let summary = Self.sleepSummary(from: daySamples, date: day) else {
                        return nil
                    }

                    return SleepDaySummary(date: day, summary: summary)
                }
                .sorted { $0.date < $1.date }

                continuation.resume(returning: days)
            }

            healthStore.execute(query)
        }

        guard hydrateVitals else {
            return SleepHistorySnapshot(days: days)
        }

        // Hydrate sleep vitals with one OR-compound query per vital type,
        // partitioned per night in memory. The prior per-day fan-out issued
        // up to ~365 days × 5 HK queries per full refresh; this issues
        // exactly 5 regardless of day count, with the same per-night
        // predicates so only in-night samples cross the HK IPC boundary.
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("SleepVitalsHydration")
        let hydratedDays = await hydrateSleepVitals(for: days)
        BodyPerformanceSignposts.signposter.endInterval("SleepVitalsHydration", signpostState)

        return SleepHistorySnapshot(days: hydratedDays)
    }

    private func hydrateSleepVitals(for days: [SleepDaySummary]) async -> [SleepDaySummary] {
        let indexedIntervals = days.enumerated().compactMap { index, day in
            day.summary.stageSnapshot.dateInterval.map { (index: index, interval: $0) }
        }
        guard !indexedIntervals.isEmpty else {
            return days
        }

        let vitals = await fetchSleepVitals(forIntervals: indexedIntervals.map(\.interval))
        var hydrated = days
        for (offset, entry) in indexedIntervals.enumerated() where offset < vitals.count {
            hydrated[entry.index].summary.vitals = vitals[offset]
        }
        return hydrated
    }

    /// One sample query per vital type covering every night interval (via an
    /// OR-compound of the per-night predicates), averaged per night with
    /// `averageVitalValues`. Matches the per-interval queries it replaces:
    /// same predicates, units, and per-sample value transforms.
    func fetchSleepVitals(forIntervals intervals: [DateInterval]) async -> [SleepVitalsSummary] {
        guard !intervals.isEmpty else {
            return []
        }

        let emptyValues = [Double?](repeating: nil, count: intervals.count)
        async let heartRates = fetchIfPermitted(.heart, default: emptyValues) {
            Self.averageVitalValues(
                samples: await self.fetchVitalSamples(
                    for: .heartRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    sourceKind: .heartRate,
                    intervals: intervals
                ),
                intervals: intervals
            )
        }
        async let heartRateVariabilities = fetchIfPermitted(.heart, default: emptyValues) {
            Self.averageVitalValues(
                samples: await self.fetchVitalSamples(
                    for: .heartRateVariabilitySDNN,
                    unit: .secondUnit(with: .milli),
                    sourceKind: .heartRateVariability,
                    intervals: intervals
                ),
                intervals: intervals
            )
        }
        async let respiratoryRates = fetchIfPermitted(.respiratory, default: emptyValues) {
            Self.averageVitalValues(
                samples: await self.fetchVitalSamples(
                    for: .respiratoryRate,
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    sourceKind: .respiratoryRate,
                    intervals: intervals
                ),
                intervals: intervals
            )
        }
        async let oxygenSaturations = fetchIfPermitted(.bloodOxygen, default: emptyValues) {
            Self.averageVitalValues(
                samples: await self.fetchVitalSamples(
                    for: .oxygenSaturation,
                    unit: .percent(),
                    sourceKind: .oxygenSaturation,
                    intervals: intervals,
                    valueTransform: Self.normalizedPercentDisplayValue
                ),
                intervals: intervals
            )
        }
        async let wristTemperatures = fetchIfPermitted(.wristTemperature, default: emptyValues) {
            Self.averageVitalValues(
                samples: await self.fetchVitalSamples(
                    for: .appleSleepingWristTemperature,
                    unit: .degreeCelsius(),
                    sourceKind: .wristTemperature,
                    intervals: intervals
                ),
                intervals: intervals
            )
        }

        let resolved = await (
            heartRates,
            heartRateVariabilities,
            respiratoryRates,
            oxygenSaturations,
            wristTemperatures
        )
        return intervals.indices.map { index in
            SleepVitalsSummary(
                heartRate: resolved.0[index],
                heartRateVariability: resolved.1[index],
                respiratoryRate: resolved.2[index],
                oxygenSaturation: resolved.3[index],
                wristTemperatureCelsius: resolved.4[index]
            )
        }
    }

    /// All samples for one vital across the night intervals, sorted ascending
    /// by start date, with the per-sample value transform already applied
    /// (matching `dailyQuantityValue`, which transforms before averaging).
    private func fetchVitalSamples(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind?,
        intervals: [DateInterval],
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> [SleepVitalWindowSample] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let intervalPredicates = intervals.map { interval in
            HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        }
        var predicates: [NSPredicate] = [
            intervalPredicates.count == 1
                ? intervalPredicates[0]
                : NSCompoundPredicate(orPredicateWithSubpredicates: intervalPredicates)
        ]
        if let sourceKind, let sourcePredicate = combinedPredicate(sourceKind: sourceKind) {
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
            ) { _, samples, _ in
                let windowSamples = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> SleepVitalWindowSample? in
                    let value = valueTransform(sample.quantity.doubleValue(for: unit))
                    guard value.isFinite else {
                        return nil
                    }
                    return SleepVitalWindowSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        value: value
                    )
                }
                continuation.resume(returning: windowSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchSleepVitals(startDate: Date, endDate: Date) async -> SleepVitalsSummary {
        async let heartRate: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await sleepQuantitySummary(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .heartRate
            )
        }
        async let heartRateVariability: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await sleepQuantitySummary(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .heartRateVariability
            )
        }
        async let respiratoryRate: HealthMetricSummary? = fetchIfPermitted(.respiratory, default: nil) {
            await sleepQuantitySummary(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .respiratoryRate
            )
        }
        async let oxygenSaturation: HealthMetricSummary? = fetchIfPermitted(.bloodOxygen, default: nil) {
            await sleepQuantitySummary(
                for: .oxygenSaturation,
                unit: .percent(),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let wristTemperature: HealthMetricSummary? = fetchIfPermitted(.wristTemperature, default: nil) {
            await sleepQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average,
                sourceKind: .wristTemperature
            )
        }

        return await SleepVitalsSummary(
            heartRate: heartRate?.value,
            heartRateVariability: heartRateVariability?.value,
            respiratoryRate: respiratoryRate?.value,
            oxygenSaturation: oxygenSaturation?.value,
            wristTemperatureCelsius: wristTemperature?.value
        )
    }

    /// Per-interval averages from window-wide samples. A sample counts toward
    /// an interval when it overlaps it as `HKQuery.predicateForSamples` would
    /// (`[start, end)`, with instantaneous samples at the exact interval start
    /// included), so the batched query + in-memory partition matches the
    /// per-night queries it replaces. `samples` must be sorted ascending by
    /// `startDate`; `intervals` ascending and non-overlapping (nights).
    nonisolated static func averageVitalValues(
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

/// One transformed quantity sample inside the batched sleep-vitals window.
struct SleepVitalWindowSample: Equatable {
    let startDate: Date
    let endDate: Date
    let value: Double
}
