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
//  Fidelity notes (watch inputs match the phone given the same HealthKit data,
//  at the default all-sources setting):
//   • Readiness hydrates per-night overnight sleep vitals (sleeping HR, HRV,
//     respiratory, blood oxygen, skin temperature) into `sleepHistory`, so its
//     baselines match the iPhone's overnight path; whole-day series stay the
//     fallback when a night lacks enough history. Sleep stages + duration come
//     from the shared `BodySleepSampleParser` (same uncovered-interval fill and
//     sub-minute-awake preference the iPhone uses).
//   • Training load fetches each workout's real `workoutEffortScore` (shared
//     `BodyWorkoutEffortFetcher`) over the same window the phone uses.
//   • Every fetch is gated by the synced permission selection, mirroring the
//     iPhone's `fetchIfPermitted`: a category disabled on the phone is never
//     read on the watch. (HealthKit read grants persist after a permission is
//     turned off, so scoping authorization alone would not be enough.)
//   • Residual: the watch reads all sources; if the user picks a non-default
//     primary/secondary source for a metric on the phone, values can differ.
//

import Foundation
import HealthKit

actor WatchHealthFetcher {
    private let store: HKHealthStore

    /// ~90 days: covers the 56-day readiness baseline + 3-day recent exclusion
    /// + margin while staying cheap for a background fetch.
    static let trendWindowDays = 90
    /// Matches the iPhone's training-load look-back so both seed the acute/
    /// chronic EWA from the same start → identical ratios.
    static let workoutWindowDays = TrainingLoadCalculator.summaryWindowDayCount

    /// A score-less workout is only confirmed (and skipped for the rest of the
    /// process) once it ended this long ago — ratings land right after a
    /// workout, so a recent unrated workout stays retryable and a rating that
    /// syncs in later is still picked up on the next recompute. Mirrors the
    /// iPhone's `HealthKitFetchEngine.effortConfirmationAge`.
    private static let effortConfirmationAge: TimeInterval = 48 * 60 * 60

    private let bpm = HKUnit.count().unitDivided(by: .minute())

    /// Per-process effort cache: a later recompute reuses efforts an earlier one
    /// resolved (foreground + coalesced observer fires share the long-lived
    /// `WatchComputeCoordinator`), so a background refresh only queries workouts
    /// it hasn't seen. Effort for past workouts rarely changes; the bounded
    /// fan-out backstops a cold launch.
    private var effortByWorkoutID: [UUID: Double] = [:]
    private var confirmedNoEffortWorkoutIDs: Set<UUID> = []

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
            // Build the night via the shared parser so the watch and iPhone
            // produce identical stages + merged asleep duration (uncovered-
            // interval fill, sub-minute-awake preference). Vitals hydrated below.
            guard let summary = BodySleepSampleParser.sleepSummary(
                from: nightSamples,
                date: night,
                showsSubMinuteAwakeStages: BodyAppearancePreference.showsSubMinuteAwakeSleepStages()
            ) else { return nil }

            return SleepDaySummary(date: night, summary: summary)
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

        let hkWorkouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        guard !hkWorkouts.isEmpty else { return (nil, .empty) }

        // Resolve each workout's real effort so the watch's training load matches
        // the iPhone (the calculator otherwise defaults effort to 5.0).
        let effortByID = await resolveEffortLevels(for: hkWorkouts)
        let workouts = hkWorkouts.map { workout in
            WorkoutSummary(
                id: workout.uuid,
                type: .other,
                startDate: workout.startDate,
                duration: workout.duration,
                effortLevel: effortByID[workout.uuid],
                sourceName: workout.sourceRevision.source.name
            )
        }

        let summary = TrainingLoadCalculator.summary(on: now, from: workouts, startDate: start, calendar: calendar)
        let series = TrainingLoadCalculator.dailySeries(from: workouts, startDate: start, endDate: now, calendar: calendar)
        return (summary, series)
    }

    /// Per-workout `workoutEffortScore`, cached per process. Queries only the
    /// workouts not already resolved (or confirmed score-less), bounded to a
    /// handful of concurrent relationship queries — mirroring the iPhone's
    /// `fetchEffortLevels`. Effort can't be folded into one OR-compound query.
    private func resolveEffortLevels(for workouts: [HKWorkout]) async -> [UUID: Double] {
        let candidates = workouts.filter {
            effortByWorkoutID[$0.uuid] == nil && !confirmedNoEffortWorkoutIDs.contains($0.uuid)
        }

        if !candidates.isEmpty {
            let maxConcurrentQueries = 12
            let outcomes = await withTaskGroup(
                of: (UUID, BodyWorkoutEffortOutcome).self,
                returning: [(UUID, BodyWorkoutEffortOutcome)].self
            ) { group in
                var nextIndex = 0
                while nextIndex < min(maxConcurrentQueries, candidates.count) {
                    let workout = candidates[nextIndex]
                    group.addTask { (workout.uuid, await self.savedEffortOutcome(for: workout)) }
                    nextIndex += 1
                }

                var collected: [(UUID, BodyWorkoutEffortOutcome)] = []
                for await result in group {
                    collected.append(result)
                    if nextIndex < candidates.count {
                        let workout = candidates[nextIndex]
                        group.addTask { (workout.uuid, await self.savedEffortOutcome(for: workout)) }
                        nextIndex += 1
                    }
                }
                return collected
            }

            // End dates for the age gate below (mirrors the iPhone): only a
            // workout that ended over `effortConfirmationAge` ago is confirmed
            // score-less. A recent unrated workout stays unconfirmed so the next
            // recompute re-queries it — otherwise a rating that syncs in later,
            // without the `workoutEffortScore` observer firing, would be ignored
            // and watch Training Load would diverge from the phone.
            let now = Date()
            let endDateByID = Dictionary(
                candidates.map { ($0.uuid, $0.endDate) },
                uniquingKeysWith: { first, _ in first }
            )

            for (id, outcome) in outcomes {
                switch outcome {
                case .found(let effort):
                    effortByWorkoutID[id] = effort
                case .noSavedEffort:
                    if let endDate = endDateByID[id],
                       now.timeIntervalSince(endDate) > Self.effortConfirmationAge {
                        confirmedNoEffortWorkoutIDs.insert(id)
                    }
                case .failed:
                    break
                }
            }
        }

        return workouts.reduce(into: [UUID: Double]()) { result, workout in
            if let effort = effortByWorkoutID[workout.uuid] {
                result[workout.uuid] = effort
            }
        }
    }

    /// Actor-isolated wrapper so the task-group closures stay `Sendable` (capture
    /// `self` + the workout, like the iPhone) instead of the `HKHealthStore`.
    private func savedEffortOutcome(for workout: HKWorkout) async -> BodyWorkoutEffortOutcome {
        await BodyWorkoutEffortFetcher.savedEffortOutcome(for: workout, store: store)
    }

    /// Drops the per-process effort cache so the next recompute re-queries every
    /// workout's effort. Called when the `workoutEffortScore` observer fires — an
    /// effort was added/changed/removed and we don't know which workout, so the
    /// cache must not keep serving the stale (or defaulted) value.
    func invalidateEffortCache() {
        effortByWorkoutID.removeAll()
        confirmedNoEffortWorkoutIDs.removeAll()
    }
}
