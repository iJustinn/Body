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
    private var combinesHealthDataSourcesByName: Bool

    private var healthSourcesByKind: [HealthMetricKind: [String: [HKSource]]] = [:]
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
        secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection,
        combinesHealthDataSourcesByName: Bool
    ) {
        self.permissionSelection = permission
        self.healthDataSourceSelection = healthDataSourceSelection
        self.secondaryHealthDataSourceSelection = secondaryHealthDataSourceSelection
        self.combinesHealthDataSourcesByName = combinesHealthDataSourcesByName
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

    func setCombinesHealthDataSourcesByName(_ combines: Bool) {
        guard combinesHealthDataSourcesByName != combines else {
            return
        }

        combinesHealthDataSourcesByName = combines
        clearSourceCache()
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
        case .readiness:
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
        case .basics:
            return .basics
        case .steps:
            return .steps
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
        case .wristTemperature:
            return .wristTemperature
        case .timeInDaylight:
            return .timeInDaylight
        default:
            return .heart
        }
    }

    private func healthSampleType(forSourceKind kind: HealthMetricKind) -> HKSampleType? {
        healthSampleTypes(forSourceKind: kind).first
    }

    private func healthSampleTypes(forSourceKind kind: HealthMetricKind) -> [HKSampleType] {
        switch kind {
        case .sleep:
            return [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)].compactMap { $0 }
        case .basics:
            return [
                HKObjectType.quantityType(forIdentifier: .bodyMass),
                HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
                HKObjectType.quantityType(forIdentifier: .bodyMassIndex)
            ].compactMap { $0 }
        case .heartRate:
            return [HKObjectType.quantityType(forIdentifier: .heartRate)].compactMap { $0 }
        case .restingHeartRate:
            return [HKObjectType.quantityType(forIdentifier: .restingHeartRate)].compactMap { $0 }
        case .heartRateVariability:
            return [HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)].compactMap { $0 }
        case .respiratoryRate:
            return [HKObjectType.quantityType(forIdentifier: .respiratoryRate)].compactMap { $0 }
        case .steps:
            return [HKObjectType.quantityType(forIdentifier: .stepCount)].compactMap { $0 }
        case .oxygenSaturation:
            return [HKObjectType.quantityType(forIdentifier: .oxygenSaturation)].compactMap { $0 }
        case .activeEnergy:
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)].compactMap { $0 }
        case .restingEnergy:
            return [HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)].compactMap { $0 }
        case .exerciseMinutes:
            return [HKObjectType.quantityType(forIdentifier: .appleExerciseTime)].compactMap { $0 }
        case .wristTemperature:
            return [HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)].compactMap { $0 }
        case .timeInDaylight:
            return [HKObjectType.quantityType(forIdentifier: .timeInDaylight)].compactMap { $0 }
        default:
            return []
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
              let sources = healthSourcesByKind[kind]?[option.id],
              !sources.isEmpty else {
            return nil
        }

        guard sources.count > 1 else {
            return sources.first.map { source in
                HKQuery.predicateForObjects(from: source)
            }
        }

        let sourcePredicates = sources.map { source in
            HKQuery.predicateForObjects(from: source)
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: sourcePredicates)
    }

    func combinedPredicate(
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

    func recentHealthTrendInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
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

    func fetchIfPermitted<Value>(
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
        guard !selectedSecondaryHealthDataSourceOption(for: kind).isNoComparison else {
            return defaultValue
        }

        return await fetchIfPermitted(permission, default: defaultValue, operation: operation)
    }

    private func selectedHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        resolvedHealthDataSourceOption(healthDataSourceSelection.option(for: kind), for: kind)
    }

    private func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        let option = resolvedSecondaryHealthDataSourceOption(
            secondaryHealthDataSourceSelection.option(for: kind),
            for: kind
        )
        guard option.id != selectedHealthDataSourceOption(for: kind).id else {
            return .noComparison
        }

        return option
    }

    private func resolvedHealthDataSourceOption(
        _ option: BodyHealthDataSourceOption,
        for kind: HealthMetricKind
    ) -> BodyHealthDataSourceOption {
        guard kind.supportsHealthDataSourceSelection,
              !option.isAllSources,
              !option.isNoComparison else {
            return option.isNoComparison ? .allSources : option
        }

        guard healthSourcesByKind[kind]?[option.id]?.isEmpty == false else {
            return .allSources
        }

        return option
    }

    private func resolvedSecondaryHealthDataSourceOption(
        _ option: BodyHealthDataSourceOption,
        for kind: HealthMetricKind
    ) -> BodyHealthDataSourceOption {
        guard kind.supportsSecondaryHealthDataSourceSelection,
              !option.isNoComparison else {
            return .noComparison
        }

        guard !option.isAllSources else {
            return option
        }

        guard healthSourcesByKind[kind]?[option.id]?.isEmpty == false else {
            return .noComparison
        }

        return option
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

    func sleepQuantitySummary(
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

    // Sleep summary + history + per-day vitals hydration live in
    // `HealthKitFetchEngine+Sleep.swift`.

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
        var nextSourcesByKind: [HealthMetricKind: [String: [HKSource]]] = [:]

        for kind in HealthMetricKind.sourceSelectableKinds {
            guard permissionSelection.includes(healthPermission(forSourceKind: kind)),
                  !healthSampleTypes(forSourceKind: kind).isEmpty else {
                continue
            }

            let sources = await fetchHealthDataSources(for: healthSampleTypes(forSourceKind: kind))
            let (options, sourcesByID) = sourceOptionsAndMap(from: sources)

            nextOptionsByKind[kind] = options
            nextSourcesByKind[kind] = sourcesByID
        }

        healthSourcesByKind = nextSourcesByKind
        fetchedHealthDataSourcePermissionRawValue = permissionRawValue
        return nextOptionsByKind
    }

    private func sourceOptionsAndMap(
        from sources: [HKSource]
    ) -> (options: [BodyHealthDataSourceOption], sourcesByID: [String: [HKSource]]) {
        let sortedSources = sources.sorted { lhs, rhs in
            let lhsName = displayName(for: lhs)
            let rhsName = displayName(for: rhs)
            if lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        var sourcesByID: [String: [HKSource]] = [:]
        let duplicateNameBundleIdentifiers = Set(
            Dictionary(grouping: sortedSources, by: \.bundleIdentifier)
                .compactMap { bundleIdentifier, sources in
                    let sourceNameKeys = Set(sources.map { source in
                        BodyHealthDataSourceOption.individualSourceIdentityKey(
                            bundleIdentifier: source.bundleIdentifier,
                            name: displayName(for: source)
                        )
                    })
                    return sourceNameKeys.count > 1 ? bundleIdentifier : nil
                }
        )
        for source in sortedSources {
            let sourceID = BodyHealthDataSourceOption.individualSourceID(
                bundleIdentifier: source.bundleIdentifier,
                name: displayName(for: source),
                disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(source.bundleIdentifier)
            )
            sourcesByID[sourceID, default: []].append(source)
        }

        let groupedSources = Dictionary(grouping: sortedSources) { source in
            BodyHealthDataSourceOption.normalizedSourceName(displayName(for: source))
        }
        for group in groupedSources.values where group.count > 1 {
            let displayName = displayName(for: group[0])
            sourcesByID[BodyHealthDataSourceOption.combinedSourceID(for: displayName)] = group
        }

        let options: [BodyHealthDataSourceOption]
        if combinesHealthDataSourcesByName {
            options = groupedSources.values.map { group in
                let displayName = displayName(for: group[0])
                let optionID = group.count > 1
                    ? BodyHealthDataSourceOption.combinedSourceID(for: displayName)
                    : BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: group[0].bundleIdentifier,
                        name: displayName,
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(group[0].bundleIdentifier)
                    )
                return BodyHealthDataSourceOption(
                    id: optionID,
                    name: BodyHealthDataSourceOption.combinedSourceDisplayName(for: displayName)
                )
            }
        } else {
            options = sortedSources.map { source in
                let displayName = displayName(for: source)
                return BodyHealthDataSourceOption(
                    id: BodyHealthDataSourceOption.individualSourceID(
                        bundleIdentifier: source.bundleIdentifier,
                        name: displayName,
                        disambiguatesBundleIdentifier: duplicateNameBundleIdentifiers.contains(source.bundleIdentifier)
                    ),
                    name: displayName
                )
            }
        }

        return (
            options.sorted { lhs, rhs in
                if lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame {
                    return lhs.id < rhs.id
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            },
            sourcesByID
        )
    }

    private func displayName(for source: HKSource) -> String {
        let trimmedName = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Unknown Source" : trimmedName
    }

    private func fetchHealthDataSources(for sampleTypes: [HKSampleType]) async -> [HKSource] {
        var sourcesByIdentifier: [String: HKSource] = [:]
        for sampleType in sampleTypes {
            let sources = await fetchHealthDataSources(for: sampleType)
            for source in sources {
                let sourceKey = BodyHealthDataSourceOption.individualSourceIdentityKey(
                    bundleIdentifier: source.bundleIdentifier,
                    name: displayName(for: source)
                )
                if sourcesByIdentifier[sourceKey] == nil {
                    sourcesByIdentifier[sourceKey] = source
                }
            }
        }
        return Array(sourcesByIdentifier.values)
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
             .readiness,
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
        case .steps:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps,
                sourceOption: secondaryOption,
                startDate: startDate,
                endDate: endDate
            )
        case .sleep,
             .readiness,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .respiratoryRate,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
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
             .readiness,
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
                sourceKind: .respiratoryRate,
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
        case .steps:
            return await fetchHourlyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps,
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
            await latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), sourceKind: .basics)
        }
        async let bodyFatPercentage: HealthMetricSummary? = fetchIfPermitted(.basics, default: nil) {
            await latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                sourceKind: .basics,
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
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .respiratoryRate
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
            await latestQuantity(for: .bodyMassIndex, unit: .count(), sourceKind: .basics)
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
                calendar: calendar,
                sourceKind: .wristTemperature
            )
        }
        async let timeInDaylight: HealthMetricSummary? = fetchIfPermitted(.timeInDaylight, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
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
        let cachedStepsDaySamples = cachedTrends.stepsDaySamples
        let cachedStepsDaySamplesSecondary = cachedTrends.stepsDaySamplesSecondary

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
                calendar: calendar,
                sourceKind: .basics
            )
        }
        async let bodyFatPercentage = fetchIfPermitted(.basics, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
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
                calendar: calendar,
                sourceKind: .respiratoryRate
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
                calendar: calendar,
                sourceKind: .basics
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
                calendar: calendar,
                sourceKind: .wristTemperature
            )
        }
        async let timeInDaylight = fetchIfPermitted(.timeInDaylight, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
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
            activeEnergyDaySamplesSecondary: cachedActiveEnergyDaySamplesSecondary,
            stepsDaySamples: cachedStepsDaySamples,
            stepsDaySamplesSecondary: cachedStepsDaySamplesSecondary
        )
    }

    func fetchHealthDashboardSnapshot(
        for kind: HealthMetricKind,
        calendar: Calendar,
        existing: HealthDashboardSnapshot,
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration
    ) async -> HealthDashboardSnapshot {
        var summary = HealthSummarySnapshot.empty
        var trends = HealthTrendSnapshot.empty

        if kind == .readiness {
            let baseSnapshot = existing
            let anchor = anchorDate ?? Date()
            return await Task.detached(priority: .userInitiated) {
                baseSnapshot.recalculatingReadiness(
                    on: anchor,
                    idealSleepDuration: idealSleepDuration,
                    calendar: calendar
                )
            }.value
        }

        guard permissionSelection.includes(Self.healthPermission(forMetric: kind)) else {
            return HealthDashboardSnapshot(summary: summary, trends: trends)
        }

        switch kind {
        case .readiness:
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
            async let bodyMass = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), sourceKind: .basics)
            async let bodyFatPercentage = latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyMassIndex = latestQuantity(for: .bodyMassIndex, unit: .count(), sourceKind: .basics)
            async let bodyMassTrend = fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )
            async let bodyFatPercentageTrend = fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyMassIndexTrend = fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
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
            async let bodyMass = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), sourceKind: .basics)
            async let bodyMassTrend = fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )

            summary.bodyMass = await bodyMass ?? HealthSummarySnapshot.empty.bodyMass
            trends.bodyMass = await bodyMassTrend
        case .bodyFatPercentage:
            async let bodyFatPercentage = latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyFatPercentageTrend = fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
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
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .respiratoryRate
            )
            async let respiratoryRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDailyQuantityAverageAndRangeSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .respiratoryRate
            )
            async let respiratoryRateDaySamples = fetchQuantitySampleSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .respiratoryRate
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
            async let bodyMassIndex = latestQuantity(for: .bodyMassIndex, unit: .count(), sourceKind: .basics)
            async let bodyMassIndexTrend = fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
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
                calendar: calendar,
                sourceKind: .wristTemperature
            )
            async let wristTemperatureTrend = fetchDailyQuantitySeries(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )

            summary.wristTemperature = await wristTemperature ?? HealthSummarySnapshot.empty.wristTemperature
            trends.wristTemperature = await wristTemperatureTrend
        case .timeInDaylight:
            async let timeInDaylight = dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )
            async let timeInDaylightTrend = fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
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
            async let stepsDaySamples = fetchHourlyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
            async let stepsDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .steps,
                calendar: calendar
            )

            summary.steps = await steps ?? HealthSummarySnapshot.empty.steps
            trends.steps = await stepsTrend
            trends.stepsSecondary = await stepsSecondaryTrend
            trends.stepsDaySamples = await stepsDaySamples
            trends.stepsDaySamplesSecondary = await stepsDaySamplesSecondary
        }

        return HealthDashboardSnapshot(summary: summary, trends: trends)
    }

    // Static, pure-function helpers (sleep stage parsing, ring summary mapping,
    // workout downsampling, etc.) live in `HealthKitFetchEngine+SampleParsers.swift`.
}
