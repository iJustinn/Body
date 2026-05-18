//
//  HealthKitFetchEngine.swift
//  Body
//

import Foundation
import HealthKit

/// Off-main-actor engine that owns all HealthKit fetching for `HealthKitWorkoutStore`.
///
/// The store remains a `@MainActor` view-model with `@Published` state. It
/// delegates every `HKHealthStore` query, predicate, and aggregation here so
/// the store body itself stays focused on presentation glue.
actor HealthKitFetchEngine {
    private let healthStore = HKHealthStore()

    private var permissionSelection: BodyHealthPermissionSelection
    private var healthDataSourceSelection: BodyHealthDataSourceSelection
    private var secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection

    private var healthSourcesByKind: [HealthMetricKind: [String: HKSource]] = [:]
    private var fetchedHealthDataSourcePermissionRawValue: String?

    private var anchorDate: Date?

    /// Shared workout fetch for the training-load summary AND the training-load
    /// trend series. Both consume the same 180-day workout window; running them
    /// as independent HK queries (one per orchestrator) duplicates the round-trip
    /// and the per-workout effort fan-out. Memoized by window so simultaneous
    /// callers within a refresh share a single in-flight fetch.
    private var sharedTrainingLoadWorkoutsTask: Task<[WorkoutSummary], Error>?
    private var sharedTrainingLoadWorkoutsWindow: TrainingLoadWorkoutsWindow?

    private struct TrainingLoadWorkoutsWindow: Equatable {
        let start: Date
        let end: Date
    }

    private static let trainingLoadSummaryDayCount = 180

    init(
        permission: BodyHealthPermissionSelection,
        healthDataSourceSelection: BodyHealthDataSourceSelection,
        secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection
    ) {
        self.permissionSelection = permission
        self.healthDataSourceSelection = healthDataSourceSelection
        self.secondaryHealthDataSourceSelection = secondaryHealthDataSourceSelection
    }

    // MARK: - Selection setters

    func setPermissionSelection(_ selection: BodyHealthPermissionSelection) {
        permissionSelection = selection
    }

    func setHealthDataSourceSelection(_ selection: BodyHealthDataSourceSelection) {
        healthDataSourceSelection = selection
    }

    func setSecondaryHealthDataSourceSelection(_ selection: BodyHealthSecondaryDataSourceSelection) {
        secondaryHealthDataSourceSelection = selection
    }

    func setHealthTrendAnchorDate(_ date: Date?) {
        anchorDate = date
        // The shared training-load fetch is keyed by the anchor-derived window;
        // crossing a refresh boundary should always re-fetch.
        sharedTrainingLoadWorkoutsTask = nil
        sharedTrainingLoadWorkoutsWindow = nil
    }

    var healthTrendAnchorDate: Date? {
        anchorDate
    }

    func clearSourceCache() {
        healthSourcesByKind = [:]
        fetchedHealthDataSourcePermissionRawValue = nil
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        let requestedTypes = HealthKitWorkoutStore.readObjectTypes(for: permissionSelection)
        guard !requestedTypes.isEmpty else {
            return
        }

        let status = try await authorizationRequestStatus(readTypes: requestedTypes)
        guard status != .unnecessary else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: requestedTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitWorkoutError.authorizationDenied)
                }
            }
        }

        let updatedStatus = try await authorizationRequestStatus(readTypes: requestedTypes)
        switch updatedStatus {
        case .unnecessary:
            return
        case .shouldRequest:
            throw HealthKitWorkoutError.authorizationDenied
        case .unknown:
            throw HealthKitWorkoutError.authorizationStatusUnknown
        @unknown default:
            throw HealthKitWorkoutError.authorizationStatusUnknown
        }
    }

    private func authorizationRequestStatus(readTypes: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        try await healthStore.statusForAuthorizationRequest(toShare: Set<HKSampleType>(), read: readTypes)
    }

    // MARK: - Permission / source mappers

    nonisolated static func healthPermission(forMetric kind: HealthMetricKind) -> BodyHealthPermission {
        switch kind {
        case .recovery:
            return .heart
        case .sleep:
            return .sleep
        case .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex:
            return .basics
        case .heartRate,
             .restingHeartRate,
             .heartRateVariability:
            return .heart
        case .respiratoryRate:
            return .respiratory
        case .oxygenSaturation:
            return .bloodOxygen
        case .activeEnergy,
             .restingEnergy:
            return .energy
        case .exerciseMinutes:
            return .exerciseMinutes
        case .trainingLoad:
            return .workouts
        case .wristTemperature:
            return .wristTemperature
        case .timeInDaylight:
            return .timeInDaylight
        case .steps:
            return .steps
        }
    }

    private func healthPermission(forSourceKind kind: HealthMetricKind) -> BodyHealthPermission {
        switch kind {
        case .sleep:
            return .sleep
        case .steps:
            return .steps
        case .heartRate,
             .restingHeartRate,
             .heartRateVariability:
            return .heart
        case .oxygenSaturation:
            return .bloodOxygen
        case .activeEnergy,
             .restingEnergy:
            return .energy
        case .exerciseMinutes:
            return .exerciseMinutes
        default:
            return .heart
        }
    }

    private func healthSampleType(forSourceKind kind: HealthMetricKind) -> HKSampleType? {
        switch kind {
        case .sleep:
            return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .heartRate:
            return HKObjectType.quantityType(forIdentifier: .heartRate)
        case .restingHeartRate:
            return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .heartRateVariability:
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .steps:
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case .oxygenSaturation:
            return HKObjectType.quantityType(forIdentifier: .oxygenSaturation)
        case .activeEnergy:
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        case .restingEnergy:
            return HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)
        case .exerciseMinutes:
            return HKObjectType.quantityType(forIdentifier: .appleExerciseTime)
        default:
            return nil
        }
    }

    // MARK: - Predicates

    private func sourcePredicate(for kind: HealthMetricKind) -> NSPredicate? {
        sourcePredicate(for: kind, option: nil)
    }

    private func sourcePredicate(
        for kind: HealthMetricKind,
        option explicitOption: BodyHealthDataSourceOption? = nil
    ) -> NSPredicate? {
        let option = explicitOption ?? healthDataSourceSelection.option(for: kind)
        guard !option.isAllSources,
              !option.isNoComparison,
              let source = healthSourcesByKind[kind]?[option.id] else {
            return nil
        }

        return HKQuery.predicateForObjects(from: Set([source]))
    }

    private func combinedPredicate(
        startDate: Date? = nil,
        endDate: Date? = nil,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil
    ) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        if startDate != nil || endDate != nil {
            predicates.append(HKQuery.predicateForSamples(withStart: startDate, end: endDate))
        }

        if let sourceKind {
            let sourcePredicate: NSPredicate?
            if let sourceOption {
                sourcePredicate = self.sourcePredicate(for: sourceKind, option: sourceOption)
            } else {
                sourcePredicate = self.sourcePredicate(for: sourceKind)
            }
            if let sourcePredicate {
                predicates.append(sourcePredicate)
            }
        }

        switch predicates.count {
        case 0:
            return nil
        case 1:
            return predicates[0]
        default:
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
    }

    // MARK: - Intervals

    private func recentHealthTrendInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
        Self.recentHealthTrendInterval(calendar: calendar, anchor: anchorDate, date: date)
    }

    nonisolated static func recentHealthTrendInterval(
        calendar: Calendar,
        anchor: Date?,
        date: Date = Date()
    ) -> (start: Date, end: Date) {
        let anchorOrDate = anchor ?? date
        let end = anchorOrDate
        let currentDayStart = calendar.startOfDay(for: anchorOrDate)
        let oldestPastOffset = BodyHealthTrendRange.maximumDayCount - 1
        let start = calendar.date(byAdding: .day, value: -oldestPastOffset, to: currentDayStart)
            ?? end.addingTimeInterval(-TimeInterval(oldestPastOffset) * 86_400)
        return (start, end)
    }

    private func activityRingHistoryInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
        let currentDayStart = calendar.startOfDay(for: date)
        let currentMonthStart = calendar.dateInterval(of: .month, for: currentDayStart)?.start ?? currentDayStart
        let start = calendar.date(byAdding: .month, value: -(HealthKitWorkoutStore.recentChartMonthCount - 1), to: currentMonthStart)
            ?? currentMonthStart
        return (start, currentDayStart)
    }

    // MARK: - Generic permission helpers

    private func fetchIfPermitted<Value>(
        _ permission: BodyHealthPermission,
        default defaultValue: Value,
        operation: () async -> Value
    ) async -> Value {
        guard permissionSelection.includes(permission) else {
            return defaultValue
        }

        return await operation()
    }

    private func fetchSecondaryIfEnabled<Value>(
        for kind: HealthMetricKind,
        permission: BodyHealthPermission,
        default defaultValue: Value,
        operation: () async -> Value
    ) async -> Value {
        guard !secondaryHealthDataSourceSelection.option(for: kind).isNoComparison else {
            return defaultValue
        }

        return await fetchIfPermitted(permission, default: defaultValue, operation: operation)
    }

    private func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        secondaryHealthDataSourceSelection.option(for: kind)
    }

    // MARK: - Quantity / sample helpers

    enum DailyQuantityAggregation {
        case average
        case latest
    }

    private func fetchDailyQuantitySeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )

        let options: HKStatisticsOptions
        switch aggregation {
        case .average:
            options = .discreteAverage
        case .latest:
            options = .mostRecent
        }

        let anchor = calendar.startOfDay(for: interval.start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, _ in
                guard let statisticsCollection else {
                    continuation.resume(returning: .empty)
                    return
                }

                var points: [HealthTrendDataPoint] = []
                statisticsCollection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    let quantity: HKQuantity?
                    switch aggregation {
                    case .average:
                        quantity = statistics.averageQuantity()
                    case .latest:
                        quantity = statistics.mostRecentQuantity()
                    }

                    guard let quantity else {
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

                continuation.resume(returning: HealthTrendSeries(points: points))
            }

            healthStore.execute(query)
        }
    }

    private func fetchDailyQuantityRangeSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendRangeSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )

        let anchor = calendar.startOfDay(for: interval.start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: [.discreteMin, .discreteMax, .discreteAverage],
                anchorDate: anchor,
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, _ in
                guard let statisticsCollection else {
                    continuation.resume(returning: .empty)
                    return
                }

                var points: [HealthTrendRangeDataPoint] = []
                statisticsCollection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    guard let minQuantity = statistics.minimumQuantity(),
                          let maxQuantity = statistics.maximumQuantity(),
                          let averageQuantity = statistics.averageQuantity() else {
                        return
                    }

                    let low = valueTransform(minQuantity.doubleValue(for: unit))
                    let high = valueTransform(maxQuantity.doubleValue(for: unit))
                    let average = valueTransform(averageQuantity.doubleValue(for: unit))
                    guard low.isFinite, high.isFinite, average.isFinite else {
                        return
                    }

                    points.append(
                        HealthTrendRangeDataPoint(
                            date: calendar.startOfDay(for: statistics.startDate),
                            lowValue: low,
                            highValue: high,
                            averageValue: average
                        )
                    )
                }

                continuation.resume(returning: HealthTrendRangeSeries(points: points))
            }

            healthStore.execute(query)
        }
    }

    private func fetchDailyQuantityAverageAndRangeSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> (HealthTrendSeries, HealthTrendRangeSeries) {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return (.empty, .empty)
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )

        let anchor = calendar.startOfDay(for: interval.start)
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMin, .discreteMax],
                anchorDate: anchor,
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, _ in
                guard let statisticsCollection else {
                    continuation.resume(returning: (.empty, .empty))
                    return
                }

                var averagePoints: [HealthTrendDataPoint] = []
                var rangePoints: [HealthTrendRangeDataPoint] = []
                statisticsCollection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    let day = calendar.startOfDay(for: statistics.startDate)
                    if let averageQuantity = statistics.averageQuantity() {
                        let average = valueTransform(averageQuantity.doubleValue(for: unit))
                        if average.isFinite {
                            averagePoints.append(HealthTrendDataPoint(date: day, value: average))

                            if let minQuantity = statistics.minimumQuantity(),
                               let maxQuantity = statistics.maximumQuantity() {
                                let low = valueTransform(minQuantity.doubleValue(for: unit))
                                let high = valueTransform(maxQuantity.doubleValue(for: unit))
                                if low.isFinite, high.isFinite {
                                    rangePoints.append(
                                        HealthTrendRangeDataPoint(
                                            date: day,
                                            lowValue: low,
                                            highValue: high,
                                            averageValue: average
                                        )
                                    )
                                }
                            }
                        }
                    }
                }

                continuation.resume(returning: (HealthTrendSeries(points: averagePoints), HealthTrendRangeSeries(points: rangePoints)))
            }

            healthStore.execute(query)
        }
    }

    private func sleepQuantitySummary(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        aggregation: DailyQuantityAggregation,
        sourceKind: HealthMetricKind? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = combinedPredicate(startDate: startDate, endDate: endDate, sourceKind: sourceKind)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let quantitySamples = samples as? [HKQuantitySample] ?? []
                guard let value = Self.dailyQuantityValue(
                    from: quantitySamples,
                    unit: unit,
                    aggregation: aggregation,
                    valueTransform: valueTransform
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: HealthMetricSummary(value: value))
            }

            healthStore.execute(query)
        }
    }

    private func dailyQuantitySummary(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        let series = await fetchDailyQuantitySeries(
            for: identifier,
            unit: unit,
            aggregation: aggregation,
            calendar: calendar,
            sourceKind: sourceKind,
            valueTransform: valueTransform
        )

        guard let latestPoint = series.points.last else {
            return nil
        }

        return HealthMetricSummary(value: latestPoint.value)
    }

    private func dailyCumulativeQuantitySummary(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let intervalStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let intervalEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let predicate = combinedPredicate(
            startDate: intervalStart,
            endDate: intervalEnd,
            sourceKind: sourceKind
        )
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: intervalStart,
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, _ in
                guard let statisticsCollection else {
                    continuation.resume(returning: nil)
                    return
                }

                var latestValue: Double?
                statisticsCollection.enumerateStatistics(from: intervalStart, to: intervalEnd) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else {
                        return
                    }

                    let value = valueTransform(quantity.doubleValue(for: unit))
                    if value.isFinite {
                        latestValue = value
                    }
                }

                continuation.resume(returning: latestValue.map(HealthMetricSummary.init(value:)))
            }

            healthStore.execute(query)
        }
    }

    private func fetchHourlyCumulativeQuantitySeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 },
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let effectiveStart = startDate ?? interval.start
        let effectiveEnd = endDate ?? interval.end
        let predicate = combinedPredicate(
            startDate: effectiveStart,
            endDate: effectiveEnd,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )
        var intervalComponents = DateComponents()
        intervalComponents.hour = 1
        let anchorDate = calendar.dateInterval(of: .hour, for: effectiveStart)?.start ?? effectiveStart

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, _ in
                guard let statisticsCollection else {
                    continuation.resume(returning: .empty)
                    return
                }

                var points: [HealthTrendDataPoint] = []
                statisticsCollection.enumerateStatistics(from: effectiveStart, to: effectiveEnd) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else {
                        return
                    }

                    let value = valueTransform(quantity.doubleValue(for: unit))
                    guard value.isFinite, value > 0 else {
                        return
                    }

                    points.append(
                        HealthTrendDataPoint(
                            date: statistics.startDate,
                            value: value
                        )
                    )
                }

                continuation.resume(returning: HealthTrendSeries(points: points))
            }

            healthStore.execute(query)
        }
    }

    private func fetchDailyCumulativeQuantitySeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )
        var intervalComponents = DateComponents()
        intervalComponents.day = 1

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: calendar.startOfDay(for: interval.start),
                intervalComponents: intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, _ in
                guard let statisticsCollection else {
                    continuation.resume(returning: .empty)
                    return
                }

                var points: [HealthTrendDataPoint] = []
                statisticsCollection.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else {
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

                continuation.resume(returning: HealthTrendSeries(points: points))
            }

            healthStore.execute(query)
        }
    }

    private func latestQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        sourceKind: HealthMetricKind? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let predicate = combinedPredicate(sourceKind: sourceKind)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let quantitySamples = samples as? [HKQuantitySample] ?? []

                guard let sample = quantitySamples.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(
                    returning: HealthMetricSummary(
                        value: valueTransform(value)
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    private func fetchQuantitySampleSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 },
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: startDate ?? interval.start,
            endDate: endDate ?? interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let points = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> HealthTrendDataPoint? in
                    let value = valueTransform(sample.quantity.doubleValue(for: unit))
                    guard value.isFinite else {
                        return nil
                    }

                    return HealthTrendDataPoint(date: sample.endDate, value: value)
                }

                continuation.resume(returning: HealthTrendSeries(points: points))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Workouts

    func fetchWorkouts(month: Int, year: Int, calendar: Calendar) async throws -> [WorkoutSummary] {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return try await fetchWorkoutSummaries(
            startDate: start,
            endDate: end,
            includesHeartRateSamples: true
        )
    }

    private func fetchWorkoutSummaries(
        startDate: Date,
        endDate: Date,
        includesHeartRateSamples: Bool
    ) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }

            healthStore.execute(query)
        }

        guard !workouts.isEmpty else {
            return []
        }

        // Fan-out per-workout HK work: HR samples in a single batched query,
        // effort levels in parallel (HKWorkoutEffortScore is queried via a
        // per-workout relationship predicate, so it cannot be batched the same
        // way HR samples can).
        async let heartRateSamplesByWorkoutID: [UUID: [WorkoutHeartRateSample]] = {
            guard includesHeartRateSamples else {
                return [:]
            }
            return await fetchIfPermitted(.heart, default: [:]) {
                await fetchHeartRateSamples(forWorkouts: workouts)
            }
        }()
        async let effortLevelsByWorkoutID = fetchEffortLevels(forWorkouts: workouts)

        let resolvedHeartRateSamples = await heartRateSamplesByWorkoutID
        let resolvedEffortLevels = await effortLevelsByWorkoutID

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)
        for workout in workouts {
            summaries.append(
                Self.summary(
                    for: workout,
                    heartRateSamples: resolvedHeartRateSamples[workout.uuid] ?? [],
                    effortLevel: resolvedEffortLevels[workout.uuid]
                )
            )
        }

        return summaries
    }

    /// Single HK query for the union of all workout time ranges; samples are
    /// partitioned per workout in-memory afterward. Replaces the prior O(workouts)
    /// sequential `HKSampleQuery` round-trips inside `fetchWorkoutSummaries`.
    private func fetchHeartRateSamples(forWorkouts workouts: [HKWorkout]) async -> [UUID: [WorkoutHeartRateSample]] {
        guard !workouts.isEmpty,
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return [:]
        }

        let workoutPredicates = workouts.map { workout in
            HKQuery.predicateForSamples(
                withStart: workout.startDate,
                end: workout.endDate,
                options: [.strictStartDate]
            )
        }
        let predicate: NSPredicate = workoutPredicates.count == 1
            ? workoutPredicates[0]
            : NSCompoundPredicate(orPredicateWithSubpredicates: workoutPredicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }

            healthStore.execute(query)
        }

        var samplesByWorkoutID: [UUID: [WorkoutHeartRateSample]] = [:]
        samplesByWorkoutID.reserveCapacity(workouts.count)
        for workout in workouts {
            let workoutStart = workout.startDate
            let workoutEnd = workout.endDate
            var workoutSamples: [WorkoutHeartRateSample] = []
            for sample in samples {
                let sampleDate = sample.startDate
                if sampleDate < workoutStart {
                    continue
                }
                if sampleDate >= workoutEnd {
                    // Samples are sorted ascending; we're past this workout's window.
                    break
                }
                let beatsPerMinute = sample.quantity.doubleValue(for: heartRateUnit)
                guard beatsPerMinute.isFinite, beatsPerMinute > 0 else {
                    continue
                }
                workoutSamples.append(
                    WorkoutHeartRateSample(
                        date: sampleDate,
                        beatsPerMinute: beatsPerMinute
                    )
                )
            }
            samplesByWorkoutID[workout.uuid] = workoutSamples
        }
        return samplesByWorkoutID
    }

    private func fetchEffortLevels(forWorkouts workouts: [HKWorkout]) async -> [UUID: Double] {
        guard !workouts.isEmpty else {
            return [:]
        }

        return await withTaskGroup(
            of: (UUID, Double?).self,
            returning: [UUID: Double].self
        ) { group in
            for workout in workouts {
                group.addTask {
                    let effort = await self.fetchSavedEffortLevel(for: workout)
                    return (workout.uuid, effort)
                }
            }

            var results: [UUID: Double] = [:]
            for await (id, effort) in group {
                if let effort {
                    results[id] = effort
                }
            }
            return results
        }
    }

    private func fetchSavedEffortLevel(for workout: HKWorkout) async -> Double? {
        guard let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) else {
            return nil
        }

        let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: effortType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let effort = (samples as? [HKQuantitySample] ?? [])
                    .first?
                    .quantity
                    .doubleValue(for: .appleEffortScore())

                continuation.resume(returning: effort?.isFinite == true ? effort : nil)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Sleep

    private func fetchSleepSummary(calendar: Calendar) async -> SleepSummary? {
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

    private func fetchDailySleepHistory(
        calendar: Calendar,
        sourceOption: BodyHealthDataSourceOption? = nil
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

    private func fetchSleepVitals(startDate: Date, endDate: Date) async -> SleepVitalsSummary {
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
                aggregation: .average
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
                aggregation: .average
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
    private static func hydrateSleepVitalsInParallel(
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

    // MARK: - Training load

    private func trainingLoadWorkoutsWindow(calendar: Calendar) -> TrainingLoadWorkoutsWindow {
        let anchor = anchorDate ?? Date()
        let dayStart = calendar.startOfDay(for: anchor)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -Self.trainingLoadSummaryDayCount, to: dayStart)
            ?? dayStart.addingTimeInterval(-TimeInterval(Self.trainingLoadSummaryDayCount) * 86_400)
        return TrainingLoadWorkoutsWindow(start: start, end: dayEnd)
    }

    /// Fetches (or reuses an in-flight fetch of) the 180-day training-load
    /// workout window. Concurrent callers within the same refresh await the
    /// same `Task`; the memo is invalidated whenever the trend anchor date is
    /// (re)set on the engine.
    private func sharedTrainingLoadWorkouts(
        window: TrainingLoadWorkoutsWindow
    ) async throws -> [WorkoutSummary] {
        if let task = sharedTrainingLoadWorkoutsTask,
           sharedTrainingLoadWorkoutsWindow == window {
            return try await task.value
        }

        let task = Task<[WorkoutSummary], Error> { [self] in
            try await fetchWorkoutSummaries(
                startDate: window.start,
                endDate: window.end,
                includesHeartRateSamples: false
            )
        }
        sharedTrainingLoadWorkoutsTask = task
        sharedTrainingLoadWorkoutsWindow = window
        return try await task.value
    }

    private func fetchTrainingLoadSummary(calendar: Calendar) async -> HealthMetricSummary? {
        let date = anchorDate ?? Date()
        let window = trainingLoadWorkoutsWindow(calendar: calendar)

        do {
            let workouts = try await sharedTrainingLoadWorkouts(window: window)
            return TrainingLoadCalculator.summary(
                on: date,
                from: workouts,
                startDate: window.start,
                calendar: calendar
            )
        } catch {
            return nil
        }
    }

    private func fetchTrainingLoadSeries(calendar: Calendar) async -> HealthTrendSeries {
        let end = anchorDate ?? Date()
        let window = trainingLoadWorkoutsWindow(calendar: calendar)

        do {
            let workouts = try await sharedTrainingLoadWorkouts(window: window)
            return TrainingLoadCalculator.dailySeries(
                from: workouts,
                startDate: window.start,
                endDate: end,
                calendar: calendar
            )
        } catch {
            return .empty
        }
    }

    // MARK: - Activity rings

    private func fetchActivityRingSummary(calendar: Calendar, date: Date = Date()) async -> ActivityRingSummary {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let dateComponents = Self.activityDateComponents(for: date, calendar: calendar)

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)

        do {
            guard let summary = try await descriptor.result(for: healthStore).first else {
                return .empty
            }

            return Self.activityRingSummary(from: summary)
        } catch {
            return .empty
        }
    }

    func fetchActivityRingHistory(calendar: Calendar, date: Date = Date()) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let interval = activityRingHistoryInterval(calendar: calendar, date: date)
        let loadedMonthKeys = Self.recentActivityRingMonthKeys(
            count: HealthKitWorkoutStore.recentChartMonthCount,
            from: date,
            calendar: calendar
        )
        return await fetchActivityRingHistory(
            start: interval.start,
            end: interval.end,
            loadedMonthKeys: loadedMonthKeys,
            calendar: calendar
        )
    }

    func fetchActivityRingHistory(
        monthKey: ActivityRingMonthKey,
        calendar: Calendar
    ) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        guard
            let start = monthKey.startDate(calendar: calendar),
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start),
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonthStart)
        else {
            return ActivityRingHistorySnapshot(days: [], loadedMonthKeys: [monthKey])
        }

        return await fetchActivityRingHistory(
            start: start,
            end: end,
            loadedMonthKeys: [monthKey],
            calendar: calendar
        )
    }

    private func fetchActivityRingHistory(
        start: Date,
        end: Date,
        loadedMonthKeys: [ActivityRingMonthKey],
        calendar: Calendar
    ) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let startComponents = Self.activityDateComponents(for: start, calendar: calendar)
        let endComponents = Self.activityDateComponents(for: end, calendar: calendar)
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)

        do {
            let summaries = try await descriptor.result(for: healthStore)
            let days = summaries.compactMap { summary -> ActivityRingDaySummary? in
                let components = summary.dateComponents(for: calendar)
                guard let date = calendar.date(from: components) else {
                    return nil
                }

                return ActivityRingDaySummary(
                    date: calendar.startOfDay(for: date),
                    summary: Self.activityRingSummary(from: summary)
                )
            }
            .sorted { $0.date < $1.date }

            return ActivityRingHistorySnapshot(days: days, loadedMonthKeys: loadedMonthKeys)
                .filteringDaysToLoadedMonths(calendar: calendar)
        } catch {
            return .empty
        }
    }

    private static func recentActivityRingMonthKeys(
        count: Int,
        from date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start else {
            return [ActivityRingMonthKey(date: date, calendar: calendar)]
        }

        return (0..<max(count, 1)).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                return nil
            }

            return ActivityRingMonthKey(date: monthDate, calendar: calendar)
        }
        .sorted { lhs, rhs in
            if lhs.year == rhs.year {
                return lhs.month < rhs.month
            }
            return lhs.year < rhs.year
        }
    }

    // MARK: - Source options

    func fetchHealthDataSourceOptions(calendar: Calendar) async -> [HealthMetricKind: [BodyHealthDataSourceOption]]? {
        let permissionRawValue = permissionSelection.rawValue
        if fetchedHealthDataSourcePermissionRawValue == permissionRawValue,
           !healthSourcesByKind.isEmpty {
            return nil
        }

        var nextOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
        var nextSourcesByKind: [HealthMetricKind: [String: HKSource]] = [:]

        for kind in HealthMetricKind.sourceSelectableKinds {
            guard permissionSelection.includes(healthPermission(forSourceKind: kind)),
                  let sampleType = healthSampleType(forSourceKind: kind) else {
                continue
            }

            let sources = await fetchHealthDataSources(for: sampleType)
            let sortedSources = sources.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            var options: [BodyHealthDataSourceOption] = []
            var sourcesByID: [String: HKSource] = [:]
            for source in sortedSources where sourcesByID[source.bundleIdentifier] == nil {
                let option = BodyHealthDataSourceOption(
                    id: source.bundleIdentifier,
                    name: source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Unknown Source"
                        : source.name
                )
                options.append(option)
                sourcesByID[option.id] = source
            }

            nextOptionsByKind[kind] = options
            nextSourcesByKind[kind] = sourcesByID
        }

        healthSourcesByKind = nextSourcesByKind
        fetchedHealthDataSourcePermissionRawValue = permissionRawValue
        return nextOptionsByKind
    }

    private func fetchHealthDataSources(for sampleType: HKSampleType) async -> [HKSource] {
        await withCheckedContinuation { continuation in
            let query = HKSourceQuery(
                sampleType: sampleType,
                samplePredicate: nil
            ) { _, sources, _ in
                continuation.resume(returning: Array(sources ?? []))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Secondary helpers

    private func fetchSecondaryTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendSeries {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        switch kind {
        case .sleep:
            return await fetchDailySleepHistory(
                calendar: calendar,
                sourceOption: secondaryOption
            ).durationSeries
        case .restingHeartRate:
            return await fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate,
                sourceOption: secondaryOption
            )
        case .activeEnergy:
            return await fetchDailyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy,
                sourceOption: secondaryOption
            )
        case .restingEnergy:
            return await fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy,
                sourceOption: secondaryOption
            )
        case .exerciseMinutes:
            return await fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes,
                sourceOption: secondaryOption
            )
        case .steps:
            return await fetchDailyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps,
                sourceOption: secondaryOption
            )
        case .basics,
             .recovery,
             .heartRate,
             .bodyMass,
             .bodyFatPercentage,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation,
             .bodyMassIndex,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
            return .empty
        }
    }

    func fetchSecondaryDaySamples(
        for kind: HealthMetricKind,
        calendar: Calendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        switch kind {
        case .heartRate:
            return await fetchQuantitySampleSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .restingHeartRate:
            return await fetchQuantitySampleSeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .restingHeartRate,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .heartRateVariability:
            return await fetchQuantitySampleSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .oxygenSaturation:
            return await fetchQuantitySampleSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                sourceOption: secondaryOption,
                valueTransform: Self.normalizedPercentDisplayValue,
                startDate: startDate,
                endDate: endDate
            )
        case .activeEnergy:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .sleep,
             .recovery,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return .empty
        }
    }

    private func fetchSecondaryRangeTrend(for kind: HealthMetricKind, calendar: Calendar) async -> HealthTrendRangeSeries {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return .empty
        }

        switch kind {
        case .heartRate:
            return await fetchDailyQuantityRangeSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate,
                sourceOption: secondaryOption
            )
        case .heartRateVariability:
            return await fetchDailyQuantityRangeSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability,
                sourceOption: secondaryOption
            )
        case .oxygenSaturation:
            return await fetchDailyQuantityRangeSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                sourceOption: secondaryOption,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        case .sleep,
             .recovery,
             .basics,
             .restingHeartRate,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return .empty
        }
    }

    // MARK: - Intraday samples

    func fetchIntradayDaySamples(
        for kind: HealthMetricKind,
        calendar: Calendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> HealthTrendSeries {
        switch kind {
        case .heartRate:
            return await fetchQuantitySampleSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate,
                startDate: startDate,
                endDate: endDate
            )
        case .restingHeartRate:
            return await fetchQuantitySampleSeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .restingHeartRate,
                startDate: startDate,
                endDate: endDate
            )
        case .heartRateVariability:
            return await fetchQuantitySampleSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability,
                startDate: startDate,
                endDate: endDate
            )
        case .respiratoryRate:
            return await fetchQuantitySampleSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                startDate: startDate,
                endDate: endDate
            )
        case .oxygenSaturation:
            return await fetchQuantitySampleSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue,
                startDate: startDate,
                endDate: endDate
            )
        case .activeEnergy:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy,
                startDate: startDate,
                endDate: endDate
            )
        default:
            return .empty
        }
    }

    /// Start date for an incremental sample fetch — the millisecond after the
    /// latest cached point, clamped to the start of the trend window. Returns
    /// `windowStart` when the cache is empty (first-ever load).
    nonisolated static func incrementalFetchStart(after cached: HealthTrendSeries, windowStart: Date) -> Date {
        guard let lastDate = cached.points.last?.date else {
            return windowStart
        }
        let next = lastDate.addingTimeInterval(0.001)
        return max(next, windowStart)
    }

    /// Merge an incremental sample fetch into the existing cache. Drops any
    /// existing points older than the current trend window and appends the
    /// newer points. Both inputs are assumed already sorted ascending by date
    /// and non-overlapping (`incrementalFetchStart` enforces the boundary).
    nonisolated static func mergeIntradaySamples(
        existing: HealthTrendSeries,
        incoming: HealthTrendSeries,
        windowStart: Date
    ) -> HealthTrendSeries {
        let trimmed = existing.points.drop(while: { $0.date < windowStart })
        if incoming.points.isEmpty {
            return trimmed.count == existing.points.count
                ? existing
                : HealthTrendSeries(points: Array(trimmed))
        }
        return HealthTrendSeries(points: Array(trimmed) + incoming.points)
    }

    // MARK: - Orchestrators

    func fetchHealthSummary(calendar: Calendar) async -> HealthSummarySnapshot {
        async let activityRings = fetchIfPermitted(.activityRings, default: ActivityRingSummary.empty) {
            await fetchActivityRingSummary(calendar: calendar)
        }
        async let sleep: SleepSummary? = fetchIfPermitted(.sleep, default: nil) {
            await fetchSleepSummary(calendar: calendar)
        }
        async let heartRate: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await latestQuantity(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .heartRate
            )
        }
        async let restingHeartRate: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await latestQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .restingHeartRate
            )
        }
        async let bodyMass: HealthMetricSummary? = fetchIfPermitted(.basics, default: nil) {
            await latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
        }
        async let bodyFatPercentage: HealthMetricSummary? = fetchIfPermitted(.basics, default: nil) {
            await latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let heartRateVariability: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await latestQuantity(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                sourceKind: .heartRateVariability
            )
        }
        async let respiratoryRate: HealthMetricSummary? = fetchIfPermitted(.respiratory, default: nil) {
            await latestQuantity(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute())
            )
        }
        async let oxygenSaturation: HealthMetricSummary? = fetchIfPermitted(.bloodOxygen, default: nil) {
            await latestQuantity(
                for: .oxygenSaturation,
                unit: .percent(),
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let bodyMassIndex: HealthMetricSummary? = fetchIfPermitted(.basics, default: nil) {
            await latestQuantity(for: .bodyMassIndex, unit: .count())
        }
        async let activeEnergy: HealthMetricSummary? = fetchIfPermitted(.energy, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
        }
        async let restingEnergy: HealthMetricSummary? = fetchIfPermitted(.energy, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
        }
        async let exerciseMinutes: HealthMetricSummary? = fetchIfPermitted(.exerciseMinutes, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
        }
        async let trainingLoad: HealthMetricSummary? = fetchIfPermitted(.workouts, default: nil) {
            await fetchTrainingLoadSummary(calendar: calendar)
        }
        async let wristTemperature: HealthMetricSummary? = fetchIfPermitted(.wristTemperature, default: nil) {
            await dailyQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar
            )
        }
        async let timeInDaylight: HealthMetricSummary? = fetchIfPermitted(.timeInDaylight, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar
            )
        }
        async let steps: HealthMetricSummary? = fetchIfPermitted(.steps, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
        }

        return await HealthSummarySnapshot(
            activityRings: activityRings,
            sleep: sleep ?? HealthSummarySnapshot.empty.sleep,
            heartRate: heartRate ?? HealthSummarySnapshot.empty.heartRate,
            restingHeartRate: restingHeartRate ?? HealthSummarySnapshot.empty.restingHeartRate,
            bodyMass: bodyMass ?? HealthSummarySnapshot.empty.bodyMass,
            bodyFatPercentage: bodyFatPercentage ?? HealthSummarySnapshot.empty.bodyFatPercentage,
            heartRateVariability: heartRateVariability ?? HealthSummarySnapshot.empty.heartRateVariability,
            respiratoryRate: respiratoryRate ?? HealthSummarySnapshot.empty.respiratoryRate,
            oxygenSaturation: oxygenSaturation ?? HealthSummarySnapshot.empty.oxygenSaturation,
            bodyMassIndex: bodyMassIndex ?? HealthSummarySnapshot.empty.bodyMassIndex,
            activeEnergy: activeEnergy ?? HealthSummarySnapshot.empty.activeEnergy,
            restingEnergy: restingEnergy ?? HealthSummarySnapshot.empty.restingEnergy,
            exerciseMinutes: exerciseMinutes ?? HealthSummarySnapshot.empty.exerciseMinutes,
            trainingLoad: trainingLoad ?? HealthSummarySnapshot.empty.trainingLoad,
            wristTemperature: wristTemperature ?? HealthSummarySnapshot.empty.wristTemperature,
            timeInDaylight: timeInDaylight ?? HealthSummarySnapshot.empty.timeInDaylight,
            steps: steps ?? HealthSummarySnapshot.empty.steps
        )
    }

    func fetchHealthTrends(calendar: Calendar, cachedTrends: HealthTrendSnapshot) async -> HealthTrendSnapshot {
        // Preserve any intraday daySamples that have already been lazy-loaded for
        // the metric detail views — fetching them is expensive (~50k HR samples)
        // and they are not displayed on the Home dashboard.
        let cachedHeartRateDaySamples = cachedTrends.heartRateDaySamples
        let cachedHeartRateDaySamplesSecondary = cachedTrends.heartRateDaySamplesSecondary
        let cachedRestingHeartRateDaySamples = cachedTrends.restingHeartRateDaySamples
        let cachedRestingHeartRateDaySamplesSecondary = cachedTrends.restingHeartRateDaySamplesSecondary
        let cachedHeartRateVariabilityDaySamples = cachedTrends.heartRateVariabilityDaySamples
        let cachedHeartRateVariabilityDaySamplesSecondary = cachedTrends.heartRateVariabilityDaySamplesSecondary
        let cachedRespiratoryRateDaySamples = cachedTrends.respiratoryRateDaySamples
        let cachedOxygenSaturationDaySamples = cachedTrends.oxygenSaturationDaySamples
        let cachedOxygenSaturationDaySamplesSecondary = cachedTrends.oxygenSaturationDaySamplesSecondary
        let cachedActiveEnergyDaySamples = cachedTrends.activeEnergyDaySamples
        let cachedActiveEnergyDaySamplesSecondary = cachedTrends.activeEnergyDaySamplesSecondary

        async let sleepHistory = fetchIfPermitted(.sleep, default: SleepHistorySnapshot.empty) {
            await fetchDailySleepHistory(calendar: calendar)
        }
        async let sleepSecondary = fetchSecondaryIfEnabled(for: .sleep, permission: .sleep, default: HealthTrendSeries.empty) {
            await fetchSecondaryTrend(for: .sleep, calendar: calendar)
        }
        async let restingHeartRate = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate
            )
        }
        async let restingHeartRateSecondary = fetchSecondaryIfEnabled(for: .restingHeartRate, permission: .heart, default: HealthTrendSeries.empty) {
            await fetchSecondaryTrend(for: .restingHeartRate, calendar: calendar)
        }
        async let heartRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchIfPermitted(
            .heart,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate
            )
        }
        async let heartRateRangesSecondary = fetchSecondaryIfEnabled(for: .heartRate, permission: .heart, default: HealthTrendRangeSeries.empty) {
            await fetchSecondaryRangeTrend(for: .heartRate, calendar: calendar)
        }
        async let bodyMass = fetchIfPermitted(.basics, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar
            )
        }
        async let bodyFatPercentage = fetchIfPermitted(.basics, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let heartRateVariabilityPair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchIfPermitted(
            .heart,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability
            )
        }
        async let heartRateVariabilityRangesSecondary = fetchSecondaryIfEnabled(for: .heartRateVariability, permission: .heart, default: HealthTrendRangeSeries.empty) {
            await fetchSecondaryRangeTrend(for: .heartRateVariability, calendar: calendar)
        }
        async let respiratoryRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchIfPermitted(
            .respiratory,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )
        }
        async let oxygenSaturationPair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchIfPermitted(
            .bloodOxygen,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let oxygenSaturationRangesSecondary = fetchSecondaryIfEnabled(
            for: .oxygenSaturation,
            permission: .bloodOxygen,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .oxygenSaturation, calendar: calendar)
        }
        async let bodyMassIndex = fetchIfPermitted(.basics, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar
            )
        }
        async let activeEnergy = fetchIfPermitted(.energy, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
        }
        async let activeEnergySecondary = fetchSecondaryIfEnabled(for: .activeEnergy, permission: .energy, default: HealthTrendSeries.empty) {
            await fetchSecondaryTrend(for: .activeEnergy, calendar: calendar)
        }
        async let restingEnergy = fetchIfPermitted(.energy, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
        }
        async let restingEnergySecondary = fetchSecondaryIfEnabled(for: .restingEnergy, permission: .energy, default: HealthTrendSeries.empty) {
            await fetchSecondaryTrend(for: .restingEnergy, calendar: calendar)
        }
        async let exerciseMinutes = fetchIfPermitted(.exerciseMinutes, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
        }
        async let exerciseMinutesSecondary = fetchSecondaryIfEnabled(for: .exerciseMinutes, permission: .exerciseMinutes, default: HealthTrendSeries.empty) {
            await fetchSecondaryTrend(for: .exerciseMinutes, calendar: calendar)
        }
        async let trainingLoad = fetchIfPermitted(.workouts, default: HealthTrendSeries.empty) {
            await fetchTrainingLoadSeries(calendar: calendar)
        }
        async let wristTemperature = fetchIfPermitted(.wristTemperature, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar
            )
        }
        async let timeInDaylight = fetchIfPermitted(.timeInDaylight, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar
            )
        }
        async let steps = fetchIfPermitted(.steps, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
        }
        async let stepsSecondary = fetchSecondaryIfEnabled(for: .steps, permission: .steps, default: HealthTrendSeries.empty) {
            await fetchSecondaryTrend(for: .steps, calendar: calendar)
        }

        let fetchedSleepHistory = await sleepHistory
        let (fetchedHeartRate, fetchedHeartRateRanges) = await heartRatePair
        let (fetchedHeartRateVariability, fetchedHeartRateVariabilityRanges) = await heartRateVariabilityPair
        let (fetchedRespiratoryRate, fetchedRespiratoryRateRanges) = await respiratoryRatePair
        let (fetchedOxygenSaturation, fetchedOxygenSaturationRanges) = await oxygenSaturationPair
        return await HealthTrendSnapshot(
            sleep: fetchedSleepHistory.durationSeries,
            sleepSecondary: sleepSecondary,
            heartRate: fetchedHeartRate,
            heartRateRanges: fetchedHeartRateRanges,
            heartRateRangesSecondary: heartRateRangesSecondary,
            restingHeartRate: restingHeartRate,
            restingHeartRateSecondary: restingHeartRateSecondary,
            bodyMass: bodyMass,
            bodyFatPercentage: bodyFatPercentage,
            heartRateVariability: fetchedHeartRateVariability,
            heartRateVariabilityRanges: fetchedHeartRateVariabilityRanges,
            heartRateVariabilityRangesSecondary: heartRateVariabilityRangesSecondary,
            respiratoryRate: fetchedRespiratoryRate,
            respiratoryRateRanges: fetchedRespiratoryRateRanges,
            oxygenSaturation: fetchedOxygenSaturation,
            oxygenSaturationRanges: fetchedOxygenSaturationRanges,
            oxygenSaturationRangesSecondary: oxygenSaturationRangesSecondary,
            bodyMassIndex: bodyMassIndex,
            activeEnergy: activeEnergy,
            activeEnergySecondary: activeEnergySecondary,
            restingEnergy: restingEnergy,
            restingEnergySecondary: restingEnergySecondary,
            exerciseMinutes: exerciseMinutes,
            exerciseMinutesSecondary: exerciseMinutesSecondary,
            trainingLoad: trainingLoad,
            wristTemperature: wristTemperature,
            timeInDaylight: timeInDaylight,
            steps: steps,
            stepsSecondary: stepsSecondary,
            sleepHistory: fetchedSleepHistory,
            heartRateDaySamples: cachedHeartRateDaySamples,
            heartRateDaySamplesSecondary: cachedHeartRateDaySamplesSecondary,
            restingHeartRateDaySamples: cachedRestingHeartRateDaySamples,
            restingHeartRateDaySamplesSecondary: cachedRestingHeartRateDaySamplesSecondary,
            heartRateVariabilityDaySamples: cachedHeartRateVariabilityDaySamples,
            heartRateVariabilityDaySamplesSecondary: cachedHeartRateVariabilityDaySamplesSecondary,
            respiratoryRateDaySamples: cachedRespiratoryRateDaySamples,
            oxygenSaturationDaySamples: cachedOxygenSaturationDaySamples,
            oxygenSaturationDaySamplesSecondary: cachedOxygenSaturationDaySamplesSecondary,
            activeEnergyDaySamples: cachedActiveEnergyDaySamples,
            activeEnergyDaySamplesSecondary: cachedActiveEnergyDaySamplesSecondary
        )
    }

    func fetchHealthDashboardSnapshot(
        for kind: HealthMetricKind,
        calendar: Calendar,
        existing: HealthDashboardSnapshot
    ) async -> HealthDashboardSnapshot {
        var summary = HealthSummarySnapshot.empty
        var trends = HealthTrendSnapshot.empty

        if kind == .recovery {
            let baseSnapshot = existing
            let anchor = anchorDate ?? Date()
            return await Task.detached(priority: .userInitiated) {
                baseSnapshot.recalculatingRecovery(on: anchor, calendar: calendar)
            }.value
        }

        guard permissionSelection.includes(Self.healthPermission(forMetric: kind)) else {
            return HealthDashboardSnapshot(summary: summary, trends: trends)
        }

        switch kind {
        case .recovery:
            break
        case .sleep:
            async let sleepSummary = fetchSleepSummary(calendar: calendar)
            async let sleepHistory = fetchDailySleepHistory(calendar: calendar)
            async let sleepSecondaryTrend = fetchSecondaryTrend(for: .sleep, calendar: calendar)
            let fetchedSleepHistory = await sleepHistory

            summary.sleep = await sleepSummary ?? HealthSummarySnapshot.empty.sleep
            trends.sleep = fetchedSleepHistory.durationSeries
            trends.sleepSecondary = await sleepSecondaryTrend
            trends.sleepHistory = fetchedSleepHistory
        case .basics:
            async let bodyMass = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
            async let bodyFatPercentage = latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyMassIndex = latestQuantity(for: .bodyMassIndex, unit: .count())
            async let bodyMassTrend = fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar
            )
            async let bodyFatPercentageTrend = fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyMassIndexTrend = fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar
            )

            summary.bodyMass = await bodyMass ?? HealthSummarySnapshot.empty.bodyMass
            summary.bodyFatPercentage = await bodyFatPercentage ?? HealthSummarySnapshot.empty.bodyFatPercentage
            summary.bodyMassIndex = await bodyMassIndex ?? HealthSummarySnapshot.empty.bodyMassIndex
            trends.bodyMass = await bodyMassTrend
            trends.bodyFatPercentage = await bodyFatPercentageTrend
            trends.bodyMassIndex = await bodyMassIndexTrend
        case .heartRate:
            async let heartRate = latestQuantity(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .heartRate
            )
            async let heartRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDailyQuantityAverageAndRangeSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate
            )
            async let heartRateRangesSecondary = fetchSecondaryRangeTrend(for: .heartRate, calendar: calendar)
            async let heartRateDaySamples = fetchQuantitySampleSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate
            )
            async let heartRateDaySamplesSecondary = fetchSecondaryDaySamples(for: .heartRate, calendar: calendar)

            summary.heartRate = await heartRate ?? HealthSummarySnapshot.empty.heartRate
            let (fetchedHeartRateTrend, fetchedHeartRateRanges) = await heartRatePair
            trends.heartRate = fetchedHeartRateTrend
            trends.heartRateRanges = fetchedHeartRateRanges
            trends.heartRateRangesSecondary = await heartRateRangesSecondary
            trends.heartRateDaySamples = await heartRateDaySamples
            trends.heartRateDaySamplesSecondary = await heartRateDaySamplesSecondary
        case .restingHeartRate:
            async let restingHeartRate = latestQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .restingHeartRate
            )
            async let restingHeartRateTrend = fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate
            )
            async let restingHeartRateSecondaryTrend = fetchSecondaryTrend(for: .restingHeartRate, calendar: calendar)
            async let restingHeartRateDaySamples = fetchQuantitySampleSeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .restingHeartRate
            )
            async let restingHeartRateDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .restingHeartRate,
                calendar: calendar
            )

            summary.restingHeartRate = await restingHeartRate ?? HealthSummarySnapshot.empty.restingHeartRate
            trends.restingHeartRate = await restingHeartRateTrend
            trends.restingHeartRateSecondary = await restingHeartRateSecondaryTrend
            trends.restingHeartRateDaySamples = await restingHeartRateDaySamples
            trends.restingHeartRateDaySamplesSecondary = await restingHeartRateDaySamplesSecondary
        case .bodyMass:
            async let bodyMass = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
            async let bodyMassTrend = fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar
            )

            summary.bodyMass = await bodyMass ?? HealthSummarySnapshot.empty.bodyMass
            trends.bodyMass = await bodyMassTrend
        case .bodyFatPercentage:
            async let bodyFatPercentage = latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyFatPercentageTrend = fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                valueTransform: Self.normalizedPercentDisplayValue
            )

            summary.bodyFatPercentage = await bodyFatPercentage ?? HealthSummarySnapshot.empty.bodyFatPercentage
            trends.bodyFatPercentage = await bodyFatPercentageTrend
        case .heartRateVariability:
            async let heartRateVariability = latestQuantity(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                sourceKind: .heartRateVariability
            )
            async let heartRateVariabilityPair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDailyQuantityAverageAndRangeSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability
            )
            async let heartRateVariabilityRangesSecondary = fetchSecondaryRangeTrend(
                for: .heartRateVariability,
                calendar: calendar
            )
            async let heartRateVariabilityDaySamples = fetchQuantitySampleSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability
            )
            async let heartRateVariabilityDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .heartRateVariability,
                calendar: calendar
            )

            summary.heartRateVariability = await heartRateVariability ?? HealthSummarySnapshot.empty.heartRateVariability
            let (fetchedHeartRateVariabilityTrend, fetchedHeartRateVariabilityRanges) = await heartRateVariabilityPair
            trends.heartRateVariability = fetchedHeartRateVariabilityTrend
            trends.heartRateVariabilityRanges = fetchedHeartRateVariabilityRanges
            trends.heartRateVariabilityRangesSecondary = await heartRateVariabilityRangesSecondary
            trends.heartRateVariabilityDaySamples = await heartRateVariabilityDaySamples
            trends.heartRateVariabilityDaySamplesSecondary = await heartRateVariabilityDaySamplesSecondary
        case .respiratoryRate:
            async let respiratoryRate = latestQuantity(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute())
            )
            async let respiratoryRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDailyQuantityAverageAndRangeSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )
            async let respiratoryRateDaySamples = fetchQuantitySampleSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )

            summary.respiratoryRate = await respiratoryRate ?? HealthSummarySnapshot.empty.respiratoryRate
            let (fetchedRespiratoryRateTrend, fetchedRespiratoryRateRanges) = await respiratoryRatePair
            trends.respiratoryRate = fetchedRespiratoryRateTrend
            trends.respiratoryRateRanges = fetchedRespiratoryRateRanges
            trends.respiratoryRateDaySamples = await respiratoryRateDaySamples
        case .oxygenSaturation:
            async let oxygenSaturation = latestQuantity(
                for: .oxygenSaturation,
                unit: .percent(),
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let oxygenSaturationPair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDailyQuantityAverageAndRangeSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let oxygenSaturationRangesSecondary = fetchSecondaryRangeTrend(
                for: .oxygenSaturation,
                calendar: calendar
            )
            async let oxygenSaturationDaySamples = fetchQuantitySampleSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let oxygenSaturationDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .oxygenSaturation,
                calendar: calendar
            )

            summary.oxygenSaturation = await oxygenSaturation ?? HealthSummarySnapshot.empty.oxygenSaturation
            let (fetchedOxygenSaturationTrend, fetchedOxygenSaturationRanges) = await oxygenSaturationPair
            trends.oxygenSaturation = fetchedOxygenSaturationTrend
            trends.oxygenSaturationRanges = fetchedOxygenSaturationRanges
            trends.oxygenSaturationRangesSecondary = await oxygenSaturationRangesSecondary
            trends.oxygenSaturationDaySamples = await oxygenSaturationDaySamples
            trends.oxygenSaturationDaySamplesSecondary = await oxygenSaturationDaySamplesSecondary
        case .bodyMassIndex:
            async let bodyMassIndex = latestQuantity(for: .bodyMassIndex, unit: .count())
            async let bodyMassIndexTrend = fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar
            )

            summary.bodyMassIndex = await bodyMassIndex ?? HealthSummarySnapshot.empty.bodyMassIndex
            trends.bodyMassIndex = await bodyMassIndexTrend
        case .activeEnergy:
            async let activeEnergy = dailyCumulativeQuantitySummary(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
            async let activeEnergyTrend = fetchDailyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
            async let activeEnergySecondaryTrend = fetchSecondaryTrend(for: .activeEnergy, calendar: calendar)
            async let activeEnergyDaySamples = fetchHourlyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
            async let activeEnergyDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .activeEnergy,
                calendar: calendar
            )

            summary.activeEnergy = await activeEnergy ?? HealthSummarySnapshot.empty.activeEnergy
            trends.activeEnergy = await activeEnergyTrend
            trends.activeEnergySecondary = await activeEnergySecondaryTrend
            trends.activeEnergyDaySamples = await activeEnergyDaySamples
            trends.activeEnergyDaySamplesSecondary = await activeEnergyDaySamplesSecondary
        case .restingEnergy:
            async let restingEnergy = dailyCumulativeQuantitySummary(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
            async let restingEnergyTrend = fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
            async let restingEnergySecondaryTrend = fetchSecondaryTrend(for: .restingEnergy, calendar: calendar)

            summary.restingEnergy = await restingEnergy ?? HealthSummarySnapshot.empty.restingEnergy
            trends.restingEnergy = await restingEnergyTrend
            trends.restingEnergySecondary = await restingEnergySecondaryTrend
        case .exerciseMinutes:
            async let exerciseMinutes = dailyCumulativeQuantitySummary(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
            async let exerciseMinutesTrend = fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
            async let exerciseMinutesSecondaryTrend = fetchSecondaryTrend(for: .exerciseMinutes, calendar: calendar)

            summary.exerciseMinutes = await exerciseMinutes ?? HealthSummarySnapshot.empty.exerciseMinutes
            trends.exerciseMinutes = await exerciseMinutesTrend
            trends.exerciseMinutesSecondary = await exerciseMinutesSecondaryTrend
        case .trainingLoad:
            async let trainingLoad = fetchTrainingLoadSummary(calendar: calendar)
            async let trainingLoadTrend = fetchTrainingLoadSeries(calendar: calendar)

            summary.trainingLoad = await trainingLoad ?? HealthSummarySnapshot.empty.trainingLoad
            trends.trainingLoad = await trainingLoadTrend
        case .wristTemperature:
            async let wristTemperature = dailyQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar
            )
            async let wristTemperatureTrend = fetchDailyQuantitySeries(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar
            )

            summary.wristTemperature = await wristTemperature ?? HealthSummarySnapshot.empty.wristTemperature
            trends.wristTemperature = await wristTemperatureTrend
        case .timeInDaylight:
            async let timeInDaylight = dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar
            )
            async let timeInDaylightTrend = fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar
            )

            summary.timeInDaylight = await timeInDaylight ?? HealthSummarySnapshot.empty.timeInDaylight
            trends.timeInDaylight = await timeInDaylightTrend
        case .steps:
            async let steps = dailyCumulativeQuantitySummary(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
            async let stepsTrend = fetchDailyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
            async let stepsSecondaryTrend = fetchSecondaryTrend(for: .steps, calendar: calendar)

            summary.steps = await steps ?? HealthSummarySnapshot.empty.steps
            trends.steps = await stepsTrend
            trends.stepsSecondary = await stepsSecondaryTrend
        }

        return HealthDashboardSnapshot(summary: summary, trends: trends)
    }

    // MARK: - Static helpers (nonisolated)

    nonisolated private static func activityDateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        var components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        components.calendar = calendar
        return components
    }

    nonisolated private static func activityRingSummary(from summary: HKActivitySummary) -> ActivityRingSummary {
        ActivityRingSummary(
            move: ActivityRingMetric(
                value: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                goal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
            ),
            exercise: ActivityRingMetric(
                value: summary.appleExerciseTime.doubleValue(for: .minute()),
                goal: summary.appleExerciseTimeGoal.doubleValue(for: .minute())
            ),
            stand: ActivityRingMetric(
                value: summary.appleStandHours.doubleValue(for: .count()),
                goal: summary.appleStandHoursGoal.doubleValue(for: .count())
            )
        )
    }

    nonisolated static func normalizedPercentDisplayValue(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    nonisolated private static func dailyQuantityValue(
        from samples: [HKQuantitySample],
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        valueTransform: (Double) -> Double
    ) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }

        switch aggregation {
        case .average:
            let values = samples
                .map { valueTransform($0.quantity.doubleValue(for: unit)) }
                .filter(\.isFinite)

            guard !values.isEmpty else {
                return nil
            }

            return values.reduce(0, +) / Double(values.count)
        case .latest:
            guard let sample = samples.max(by: { $0.endDate < $1.endDate }) else {
                return nil
            }

            let value = valueTransform(sample.quantity.doubleValue(for: unit))
            return value.isFinite ? value : nil
        }
    }

    nonisolated private static func sleepSummary(from samples: [HKCategorySample], date: Date) -> SleepSummary? {
        let duration = HealthKitWorkoutStore.sleepDuration(from: samples)
        guard duration > 0 else {
            return nil
        }

        return SleepSummary(
            duration: duration,
            stageSnapshot: SleepStageSnapshot(
                date: date,
                segments: sleepStageSegments(from: samples)
            )
        )
    }

    nonisolated private static func isSleepTimelineSample(_ sample: HKCategorySample) -> Bool {
        isAsleep(sample) || sleepStage(for: sample, includeUnspecified: false) == .awake
    }

    nonisolated private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    nonisolated private static func sleepStageSegments(from samples: [HKCategorySample]) -> [SleepStageSegment] {
        let hasDetailedSleepStages = samples.contains { sample in
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .asleepCore, .asleepDeep, .asleepREM:
                return true
            default:
                return false
            }
        }

        return samples.compactMap { sample -> SleepStageSegment? in
            guard let stage = sleepStage(for: sample, includeUnspecified: !hasDetailedSleepStages) else {
                return nil
            }

            return SleepStageSegment(
                stage: stage,
                startDate: sample.startDate,
                endDate: sample.endDate
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    nonisolated private static func sleepStage(for sample: HKCategorySample, includeUnspecified: Bool) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .awake:
            return .awake
        case .asleepREM:
            return .rem
        case .asleepCore:
            return .core
        case .asleepDeep:
            return .deep
        case .asleep, .asleepUnspecified:
            return includeUnspecified ? .core : nil
        default:
            return nil
        }
    }

    nonisolated private static func summary(
        for workout: HKWorkout,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        effortLevel: Double? = nil
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        let averageHeartRate = averageHeartRate(from: heartRateSamples)

        return WorkoutSummary(
            id: workout.uuid,
            type: HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType),
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
            averageHeartRateBeatsPerMinute: averageHeartRate,
            effortLevel: effortLevel,
            heartRateSamples: downsampleHeartRateSamples(heartRateSamples),
            sourceName: workout.sourceRevision.source.name
        )
    }

    nonisolated private static func activeEnergyKilocalories(for workout: HKWorkout) -> Double? {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        return workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    nonisolated private static func totalEnergyKilocalories(for workout: HKWorkout) -> Double? {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        guard let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
              let basalEnergy = workout.statistics(for: basalEnergyType)?
              .sumQuantity()?
              .doubleValue(for: .kilocalorie()) else {
            return activeEnergy
        }

        return (activeEnergy ?? 0) + basalEnergy
    }

    nonisolated private static func averageHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        let values = samples.map(\.beatsPerMinute).filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated private static func downsampleHeartRateSamples(
        _ samples: [WorkoutHeartRateSample],
        maximumCount: Int = 96
    ) -> [WorkoutHeartRateSample] {
        let sortedSamples = samples.sorted { $0.date < $1.date }
        guard sortedSamples.count > maximumCount, maximumCount > 1 else {
            return sortedSamples
        }

        let stride = Double(sortedSamples.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            sortedSamples[Int((Double(index) * stride).rounded())]
        }
    }
}
