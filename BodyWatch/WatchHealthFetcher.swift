//
//  WatchHealthFetcher.swift
//  BodyWatch
//
//  Standalone, watch-local assembly of the inputs the shared metric calculators
//  need, read from the watch's own HealthKit. Deliberately lean vs. the iOS
//  `HealthKitFetchEngine`: only the readiness-driving + displayed metrics, over a
//  short window, with no intraday day-samples and no source comparison — so it
//  fits a watchOS background budget.
//
//  Fidelity notes (watch values track the phone closely but aren't identical):
//   • Readiness hydrates per-night overnight sleep vitals (sleeping HR, HRV,
//     respiratory, blood oxygen, skin temperature) into `sleepHistory`, so its
//     baselines match the iPhone's overnight path; whole-day series stay the
//     fallback when a night lacks enough history. Sleep stage segmentation uses
//     a simpler per-sample mapping than the iPhone (no uncovered-interval fill),
//     and duration sums non-awake segments rather than merging overlaps, so
//     stage %/duration can differ slightly — the night *interval* still matches,
//     so the overnight vital averages line up.
//   • Training load uses workout duration with the calculator's default effort
//     (per-workout effort scores aren't fetched on-watch yet).
//   • Every fetch is gated by the synced permission selection, mirroring the
//     iPhone's `fetchIfPermitted`: a category disabled on the phone is never
//     read on the watch. (HealthKit read grants persist after a permission is
//     turned off, so scoping authorization alone would not be enough.)
//

import Foundation
import HealthKit

actor WatchHealthFetcher {
    private let store: HKHealthStore

    /// ~90 days: covers the 56-day readiness baseline + 3-day recent exclusion
    /// + margin while staying cheap for a background fetch.
    static let trendWindowDays = 90
    /// ~120 days covers the 42-day chronic training-load EWA with margin.
    static let workoutWindowDays = 120

    private let bpm = HKUnit.count().unitDivided(by: .minute())

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    /// Builds a `HealthDashboardSnapshot` with the readiness inputs + display
    /// vitals populated, gated by `permission`. Readiness itself is computed by
    /// the caller via `recalculatingReadiness`.
    func assembleDashboard(
        permission: BodyHealthPermissionSelection,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) async -> HealthDashboardSnapshot {
        let days = Self.trendWindowDays
        let heart = permission.includes(.heart)

        async let hrv = dailyAverageSeries(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), permitted: heart, days: days, calendar: calendar, now: now)
        async let rhr = dailyAverageSeries(.restingHeartRate, unit: bpm, permitted: heart, days: days, calendar: calendar, now: now)
        async let hr = dailyAverageSeries(.heartRate, unit: bpm, permitted: heart, days: days, calendar: calendar, now: now)
        async let respiratory = dailyAverageSeries(.respiratoryRate, unit: bpm, permitted: permission.includes(.respiratory), days: days, calendar: calendar, now: now)
        async let oxygen = dailyAverageSeries(.oxygenSaturation, unit: .percent(), permitted: permission.includes(.bloodOxygen), transform: Self.normalizedPercent, days: days, calendar: calendar, now: now)
        async let temperature = dailyAverageSeries(.appleSleepingWristTemperature, unit: .degreeCelsius(), permitted: permission.includes(.wristTemperature), days: days, calendar: calendar, now: now)
        async let sleep = sleepHistory(permission: permission, days: days, calendar: calendar, now: now)
        async let training = trainingLoad(permitted: permission.includes(.workouts), calendar: calendar, now: now)

        let hrvSeries = await hrv
        let rhrSeries = await rhr
        let hrSeries = await hr
        let respiratorySeries = await respiratory
        let oxygenSeries = await oxygen
        let temperatureSeries = await temperature
        let (latestSleep, sleepHistorySnapshot) = await sleep
        let (trainingSummary, trainingSeries) = await training

        var trends = HealthTrendSnapshot.empty
        trends.heartRateVariability = hrvSeries
        trends.restingHeartRate = rhrSeries
        trends.heartRate = hrSeries
        trends.respiratoryRate = respiratorySeries
        trends.oxygenSaturation = oxygenSeries
        trends.wristTemperature = temperatureSeries
        trends.trainingLoad = trainingSeries
        trends.sleepHistory = sleepHistorySnapshot

        var summary = HealthSummarySnapshot.empty
        summary.heartRateVariability = HealthMetricSummary(value: hrvSeries.points.last?.value)
        summary.restingHeartRate = HealthMetricSummary(value: rhrSeries.points.last?.value)
        summary.heartRate = HealthMetricSummary(value: hrSeries.points.last?.value)
        summary.respiratoryRate = HealthMetricSummary(value: respiratorySeries.points.last?.value)
        summary.oxygenSaturation = HealthMetricSummary(value: oxygenSeries.points.last?.value)
        summary.wristTemperature = HealthMetricSummary(value: temperatureSeries.points.last?.value)
        summary.trainingLoad = trainingSummary ?? HealthMetricSummary(value: trainingSeries.points.last?.value)
        summary.sleep = latestSleep ?? SleepSummary(duration: nil)

        return HealthDashboardSnapshot(summary: summary, trends: trends)
    }

    /// Matches the iPhone's `normalizedPercentDisplayValue`: HealthKit returns
    /// blood oxygen as a fraction (e.g. 0.97) while the rest of the app scores it
    /// on a 0–100 scale, so values at or below 1 are scaled up. Scaling is linear,
    /// so applying it to a daily/overnight average equals the iPhone (which
    /// transforms the aggregate for daily trends and per sample for sleep vitals).
    private static func normalizedPercent(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    // MARK: - Daily quantity series

    /// Daily whole-day average series via `HKStatisticsCollectionQuery`, mirroring
    /// the iOS engine's `fetchDailyQuantitySeries(.average)` so values align.
    /// Returns `.empty` when the category isn't permitted.
    private func dailyAverageSeries(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        permitted: Bool,
        transform: ((Double) -> Double)? = nil,
        days: Int,
        calendar: Calendar,
        now: Date
    ) async -> HealthTrendSeries {
        guard permitted, let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return .empty }

        let dayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let start = calendar.date(byAdding: .day, value: -days, to: dayStart) ?? dayStart
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: intervalComponents
            )
            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: .empty)
                    return
                }
                var points: [HealthTrendDataPoint] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.averageQuantity() else { return }
                    let rawValue = quantity.doubleValue(for: unit)
                    let value = transform?(rawValue) ?? rawValue
                    guard value.isFinite else { return }
                    points.append(
                        HealthTrendDataPoint(date: calendar.startOfDay(for: statistics.startDate), value: value)
                    )
                }
                continuation.resume(returning: HealthTrendSeries(points: points))
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    /// Per-night sleep summaries over the trend window with overnight vitals
    /// hydrated, plus the most recent night as the current `SleepSummary`.
    /// Mirrors the iPhone: group sleep samples by the calendar day they end on
    /// (the wake day), then average each permitted vital over each night's
    /// interval. Returns `(nil, .empty)` when sleep isn't permitted.
    private func sleepHistory(
        permission: BodyHealthPermissionSelection,
        days: Int,
        calendar: Calendar,
        now: Date
    ) async -> (latest: SleepSummary?, history: SleepHistorySnapshot) {
        guard permission.includes(.sleep),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return (nil, .empty)
        }

        let dayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -days, to: dayStart) ?? dayStart
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return (nil, .empty) }

        // Attribute each sample to the calendar day it ends on, matching the
        // iPhone's per-night grouping; `stageSnapshot.date` is that wake day so
        // readiness recognizes the current night.
        let samplesByNight = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.endDate) }
        var nights: [SleepDaySummary] = samplesByNight.compactMap { night, nightSamples in
            let segments: [SleepStageSegment] = nightSamples.compactMap { sample in
                guard let stage = Self.sleepStage(for: sample.value) else { return nil }
                return SleepStageSegment(stage: stage, startDate: sample.startDate, endDate: sample.endDate)
            }
            guard !segments.isEmpty else { return nil }

            let snapshot = SleepStageSnapshot(date: night, segments: segments)
            // Merge overlapping asleep samples into their union, matching the
            // iPhone's `mergedSleepDuration`. A raw segment sum double-counts
            // overlapping multi-source/aggregate samples (inflated 26h nights).
            let asleepDuration = snapshot.mergedAsleepDuration
            guard asleepDuration > 0 else { return nil }

            return SleepDaySummary(
                date: night,
                summary: SleepSummary(duration: asleepDuration, stageSnapshot: snapshot, vitals: .empty)
            )
        }
        .sorted { $0.date < $1.date }
        guard !nights.isEmpty else { return (nil, .empty) }

        // Hydrate overnight vitals: one batched query per permitted vital over
        // every night's interval, averaged per night (mirrors the iPhone's
        // `fetchSleepVitals(forIntervals:)`).
        let indexed = nights.enumerated().compactMap { index, day in
            day.summary.stageSnapshot.dateInterval.map { (index: index, interval: $0) }
        }
        if !indexed.isEmpty {
            let intervals = indexed.map(\.interval)
            async let heartRates = sleepVitalAverages(.heartRate, unit: bpm, permitted: permission.includes(.heart), intervals: intervals)
            async let heartRateVariabilities = sleepVitalAverages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), permitted: permission.includes(.heart), intervals: intervals)
            async let respiratoryRates = sleepVitalAverages(.respiratoryRate, unit: bpm, permitted: permission.includes(.respiratory), intervals: intervals)
            async let oxygenSaturations = sleepVitalAverages(.oxygenSaturation, unit: .percent(), permitted: permission.includes(.bloodOxygen), transform: Self.normalizedPercent, intervals: intervals)
            async let wristTemperatures = sleepVitalAverages(.appleSleepingWristTemperature, unit: .degreeCelsius(), permitted: permission.includes(.wristTemperature), intervals: intervals)

            let heartRateValues = await heartRates
            let hrvValues = await heartRateVariabilities
            let respiratoryValues = await respiratoryRates
            let oxygenValues = await oxygenSaturations
            let temperatureValues = await wristTemperatures

            for (offset, entry) in indexed.enumerated() {
                nights[entry.index].summary.vitals = SleepVitalsSummary(
                    heartRate: heartRateValues[offset],
                    heartRateVariability: hrvValues[offset],
                    respiratoryRate: respiratoryValues[offset],
                    oxygenSaturation: oxygenValues[offset],
                    wristTemperatureCelsius: temperatureValues[offset]
                )
            }
        }

        return (nights.last?.summary, SleepHistorySnapshot(days: nights))
    }

    private static func sleepStage(for rawValue: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: rawValue) {
        case .asleepREM: return .rem
        case .asleepDeep: return .deep
        // `.asleep` is the legacy aggregate value (older watchOS / third-party
        // apps); fold it in with unspecified so those nights aren't dropped and
        // the night interval still spans every asleep sample.
        case .asleep, .asleepCore, .asleepUnspecified: return .core
        case .awake: return .awake
        default: return nil // .inBed and anything unknown aren't stages
        }
    }

    /// One transformed quantity sample inside the batched sleep-vitals window.
    private struct VitalSample {
        let startDate: Date
        let endDate: Date
        let value: Double
    }

    /// Average each night's samples for one vital. One batched `HKSampleQuery`
    /// over the union of night intervals, partitioned per night in memory.
    /// Returns all-`nil` when the vital isn't permitted.
    private func sleepVitalAverages(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        permitted: Bool,
        transform: ((Double) -> Double)? = nil,
        intervals: [DateInterval]
    ) async -> [Double?] {
        guard permitted,
              !intervals.isEmpty,
              let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return [Double?](repeating: nil, count: intervals.count)
        }

        let intervalPredicates = intervals.map {
            HKQuery.predicateForSamples(withStart: $0.start, end: $0.end, options: [])
        }
        let predicate: NSPredicate = intervalPredicates.count == 1
            ? intervalPredicates[0]
            : NSCompoundPredicate(orPredicateWithSubpredicates: intervalPredicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [VitalSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                let mapped = (results as? [HKQuantitySample] ?? []).compactMap { sample -> VitalSample? in
                    let rawValue = sample.quantity.doubleValue(for: unit)
                    let value = transform?(rawValue) ?? rawValue
                    guard value.isFinite else { return nil }
                    return VitalSample(startDate: sample.startDate, endDate: sample.endDate, value: value)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }

        return Self.averagePerNight(samples: samples, intervals: intervals)
    }

    /// Per-interval averages, matching the iPhone's `averageVitalValues` overlap
    /// rule (`HealthKitFetchEngine+Sleep.swift`): a sample is considered only
    /// while `startDate < interval.end`; an instantaneous sample (start == end)
    /// counts when its instant is at or after the interval start, an interval
    /// sample counts when its end is past the interval start.
    private static func averagePerNight(samples: [VitalSample], intervals: [DateInterval]) -> [Double?] {
        guard !samples.isEmpty else {
            return [Double?](repeating: nil, count: intervals.count)
        }

        return intervals.map { interval in
            var sum = 0.0
            var count = 0
            for sample in samples where sample.startDate < interval.end {
                let overlaps = sample.startDate == sample.endDate
                    ? sample.startDate >= interval.start
                    : sample.endDate > interval.start
                if overlaps {
                    sum += sample.value
                    count += 1
                }
            }
            return count > 0 ? sum / Double(count) : nil
        }
    }

    // MARK: - Training load

    /// Workout-derived training load. Uses the shared `TrainingLoadCalculator`
    /// with workout duration; per-workout effort scores aren't fetched on-watch
    /// yet, so the calculator's default effort applies. Returns empty when
    /// workouts aren't permitted.
    private func trainingLoad(permitted: Bool, calendar: Calendar, now: Date) async -> (HealthMetricSummary?, HealthTrendSeries) {
        guard permitted else { return (nil, .empty) }

        let dayStart = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let start = calendar.date(byAdding: .day, value: -Self.workoutWindowDays, to: dayStart) ?? dayStart
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let workouts: [WorkoutSummary] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                let summaries = (results as? [HKWorkout])?.map { workout in
                    WorkoutSummary(
                        id: workout.uuid,
                        type: .other,
                        startDate: workout.startDate,
                        duration: workout.duration,
                        effortLevel: nil,
                        sourceName: workout.sourceRevision.source.name
                    )
                } ?? []
                continuation.resume(returning: summaries)
            }
            store.execute(query)
        }

        guard !workouts.isEmpty else { return (nil, .empty) }
        let summary = TrainingLoadCalculator.summary(on: now, from: workouts, startDate: start, calendar: calendar)
        let series = TrainingLoadCalculator.dailySeries(from: workouts, startDate: start, endDate: now, calendar: calendar)
        return (summary, series)
    }
}
