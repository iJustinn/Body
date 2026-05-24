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

        // Hydrate sleep vitals per-day in parallel. The previous serial loop
        // could fire up to ~365 days × 5 sub-queries sequentially; with the
        // sleep window now bounded by the trend interval, that's the largest
        // single source of cold-launch latency. Bound concurrency so we don't
        // flood HK with thousands of in-flight queries.
        let hydratedDays = await Self.hydrateSleepVitalsInParallel(
            days: days,
            maxConcurrentDays: 16,
            hydrate: { interval in
                await self.fetchSleepVitals(
                    startDate: interval.start,
                    endDate: interval.end
                )
            }
        )

        return SleepHistorySnapshot(days: hydratedDays)
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

    /// Run `hydrate` on every day with a sleep interval in parallel, with at most
    /// `maxConcurrentDays` queries in flight. Each day internally fans out to 5
    /// vitals queries, so the effective HK concurrency ceiling is roughly
    /// `maxConcurrentDays × 5`. Returned days are sorted by date ascending to
    /// match the prior serial-loop ordering.
    static func hydrateSleepVitalsInParallel(
        days: [SleepDaySummary],
        maxConcurrentDays: Int,
        hydrate: @escaping @Sendable (DateInterval) async -> SleepVitalsSummary
    ) async -> [SleepDaySummary] {
        guard !days.isEmpty else {
            return []
        }

        let limit = max(1, maxConcurrentDays)
        return await withTaskGroup(
            of: (Int, SleepDaySummary).self,
            returning: [SleepDaySummary].self
        ) { group in
            var nextIndex = 0
            let initialBatch = min(limit, days.count)
            while nextIndex < initialBatch {
                let index = nextIndex
                let day = days[index]
                group.addTask {
                    var hydrated = day
                    if let interval = hydrated.summary.stageSnapshot.dateInterval {
                        hydrated.summary.vitals = await hydrate(interval)
                    }
                    return (index, hydrated)
                }
                nextIndex += 1
            }

            var results: [(Int, SleepDaySummary)] = []
            results.reserveCapacity(days.count)
            for await pair in group {
                results.append(pair)
                if nextIndex < days.count {
                    let index = nextIndex
                    let day = days[index]
                    group.addTask {
                        var hydrated = day
                        if let interval = hydrated.summary.stageSnapshot.dateInterval {
                            hydrated.summary.vitals = await hydrate(interval)
                        }
                        return (index, hydrated)
                    }
                    nextIndex += 1
                }
            }

            return results
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }
}
