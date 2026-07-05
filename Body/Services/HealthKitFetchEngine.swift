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
    // Stored properties are declared `internal` (default access) so peer
    // extension files in this module (HealthKitFetchEngine+Sleep.swift,
    // HealthKitFetchEngine+TrainingLoad.swift, etc.) can reach them.
    // Because the actor is isolated, callers outside the actor still need
    // an `await` to read or write, so the broader visibility doesn't
    // change the threading model.
    let healthStore = HKHealthStore()

    var permissionSelection: BodyHealthPermissionSelection
    var healthDataSourceSelection: BodyHealthDataSourceSelection
    var secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection
    var combinesHealthDataSourcesByName: Bool

    var healthSourcesByKind: [HealthMetricKind: [String: [HKSource]]] = [:]
    var fetchedHealthDataSourcePermissionRawValue: String?

    var anchorDate: Date?

    /// Shared workout fetch for the training-load summary AND the training-load
    /// trend series. Both consume the same 180-day workout window; running them
    /// as independent HK queries (one per orchestrator) duplicates the round-trip
    /// and the per-workout effort fan-out. Memoized by window so simultaneous
    /// callers within a refresh share a single in-flight fetch.
    var sharedTrainingLoadWorkoutsTask: Task<[WorkoutSummary], Error>?
    var sharedTrainingLoadWorkoutsWindow: TrainingLoadWorkoutsWindow?

    /// Process-lifetime cache for the per-workout effort-score fan-out
    /// (`fetchEffortLevels`): effort needs one relationship-predicate query per
    /// workout, and both the 180-day training-load fetch and the month
    /// refreshes re-walk the same historical workouts every refresh. Found
    /// scores are trusted for the process; workouts confirmed score-less are
    /// only skipped once they ended over `effortConfirmationAge` ago (ratings
    /// land right after a workout). User-initiated refreshes clear both via
    /// `clearWorkoutEffortCache()` so a re-rated workout reconciles on any
    /// pull-to-refresh; a cold launch always starts clean. Entries for
    /// deleted workouts are just unused (bounded by workouts seen per process).
    var effortLevelsByWorkoutID: [UUID: Double] = [:]
    var confirmedNoEffortWorkoutIDs: Set<UUID> = []

    nonisolated static let effortConfirmationAge: TimeInterval = 48 * 60 * 60

    struct TrainingLoadWorkoutsWindow: Equatable {
        let start: Date
        let end: Date
    }

    static let trainingLoadSummaryDayCount = TrainingLoadCalculator.summaryWindowDayCount

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

    func clearWorkoutEffortCache() {
        effortLevelsByWorkoutID = [:]
        confirmedNoEffortWorkoutIDs = []
    }

    /// Estimated max heart rate (220 − age) from the user's Apple Health birth date,
    /// used to anchor the workout heart-rate zones. Returns nil when the birth date is
    /// unavailable or unauthorized, so the caller can fall back to the session peak.
    func userMaxHeartRate(asOf now: Date = Date()) -> Double? {
        guard permissionSelection.includes(.heart) && permissionSelection.includes(.dateOfBirth) else {
            return nil
        }
        guard let components = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components),
              let age = Calendar.current.dateComponents([.year], from: birthDate, to: now).year,
              (1...120).contains(age) else {
            return nil
        }
        return 220 - Double(age)
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

    func healthPermission(forSourceKind kind: HealthMetricKind) -> BodyHealthPermission {
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

    func healthSampleTypes(forSourceKind kind: HealthMetricKind) -> [HKSampleType] {
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

    func activityRingHistoryInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
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

    private func fetchDashboardMetricIfNeeded<Value>(
        _ kind: HealthMetricKind,
        selection: BodyDashboardFetchSelection,
        default defaultValue: Value,
        operation: () async -> Value
    ) async -> Value {
        guard selection.includes(kind) else {
            return defaultValue
        }

        return await fetchIfPermitted(
            Self.healthPermission(forMetric: kind),
            default: defaultValue,
            operation: operation
        )
    }

    private func fetchDashboardActivityRingsIfNeeded<Value>(
        selection: BodyDashboardFetchSelection,
        default defaultValue: Value,
        operation: () async -> Value
    ) async -> Value {
        guard selection.includesActivityRings else {
            return defaultValue
        }

        return await fetchIfPermitted(
            .activityRings,
            default: defaultValue,
            operation: operation
        )
    }

    private func fetchSecondaryDashboardMetricIfNeeded<Value>(
        for kind: HealthMetricKind,
        selection: BodyDashboardFetchSelection,
        permission: BodyHealthPermission,
        default defaultValue: Value,
        operation: () async -> Value
    ) async -> Value {
        guard selection.includes(kind) else {
            return defaultValue
        }

        return await fetchSecondaryIfEnabled(
            for: kind,
            permission: permission,
            default: defaultValue,
            operation: operation
        )
    }

    func selectedHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        resolvedHealthDataSourceOption(healthDataSourceSelection.option(for: kind), for: kind)
    }

    func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        // Body Pro gate at the fetch chokepoint: every secondary fetch (trend, range,
        // day samples, sleep history) guards on `.isNoComparison`, so non-Pro never
        // fetches a secondary series that the render gate would only hide afterward.
        guard BodyProEntitlement.isUnlocked else {
            return .noComparison
        }

        let option = resolvedSecondaryHealthDataSourceOption(
            secondaryHealthDataSourceSelection.option(for: kind),
            for: kind
        )
        guard option.id != selectedHealthDataSourceOption(for: kind).id else {
            return .noComparison
        }

        return option
    }

    func resolvedHealthDataSourceOption(
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

    func resolvedSecondaryHealthDataSourceOption(
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

    func fetchDailyQuantitySeries(
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

    func fetchDailyQuantityRangeSeries(
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

        // Today's bucket only: a day with no samples yet reports nil so the
        // card shows its empty state instead of yesterday's full-day total
        // under a "Current" label.
        let now = Date()
        let intervalStart = calendar.startOfDay(for: now)
        let intervalEnd = calendar.date(byAdding: .day, value: 1, to: intervalStart) ?? now
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

    func fetchHourlyCumulativeQuantitySeries(
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

    func fetchDailyCumulativeQuantitySeries(
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

    func fetchQuantitySampleSeries(
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

    func fetchWorkouts(
        month: Int,
        year: Int,
        calendar: Calendar,
        reusableSummariesByID: [UUID: WorkoutSummary] = [:]
    ) async throws -> [WorkoutSummary] {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return try await fetchWorkoutSummaries(
            startDate: start,
            endDate: end,
            includesHeartRateSamples: true,
            reusableSummariesByID: reusableSummariesByID
        )
    }

    func fetchWorkoutSummaries(
        startDate: Date,
        endDate: Date,
        includesHeartRateSamples: Bool,
        includesDetailMetrics: Bool = true,
        reusableSummariesByID: [UUID: WorkoutSummary] = [:]
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

        // Finished workouts whose HR payload was already fetched this session
        // skip the batched HR query — passive resumes only (user-initiated
        // paths pass an empty reuse map, so every pull-to-refresh remains a
        // full HR reconcile). The workout list above is always fetched fresh.
        let reusedHeartRateIDs: Set<UUID>
        if includesHeartRateSamples,
           !reusableSummariesByID.isEmpty,
           permissionSelection.includes(.heart) {
            reusedHeartRateIDs = Self.heartRateReuseEligibleWorkoutIDs(
                workouts: workouts.map { (id: $0.uuid, startDate: $0.startDate, duration: $0.duration) },
                cachedSummaries: reusableSummariesByID,
                now: Date()
            )
        } else {
            reusedHeartRateIDs = []
        }
        let workoutsNeedingHeartRate = workouts.filter { !reusedHeartRateIDs.contains($0.uuid) }

        // Fan-out per-workout HK work: HR samples in a single batched query,
        // effort levels in parallel (HKWorkoutEffortScore is queried via a
        // per-workout relationship predicate, so it cannot be batched the same
        // way HR samples can).
        async let heartRateSamplesByWorkoutID: [UUID: [WorkoutHeartRateSample]] = {
            guard includesHeartRateSamples, !workoutsNeedingHeartRate.isEmpty else {
                return [:]
            }
            return await fetchIfPermitted(.heart, default: [:]) {
                await fetchHeartRateSamples(forWorkouts: workoutsNeedingHeartRate)
            }
        }()
        async let fetchedEffortLevels = fetchEffortLevels(forWorkouts: workouts)
        // Cardio Fitness + foot cadence are only consumed by the workout detail
        // card, so callers that don't surface them (training load) pass
        // `includesDetailMetrics: false` to skip these reads entirely — otherwise
        // the 180-day training-load window would pay a per-workout step query it
        // never reads. When they DO run, they cover *every* workout (like effort
        // levels above), NOT just the non-reused `workoutsNeedingHeartRate` set:
        // only the expensive HR-sample payload keeps the passive-resume reuse
        // skip. A workout cached before these fields existed decodes their values
        // as nil, so gating them on the HR skip would leave a reused workout
        // permanently missing them until a user-initiated refresh; fetching for
        // all workouts backfills those on the next passive resume. The reuse
        // branch below still falls back to the cached value if the read is
        // permission-gated.
        async let cardioFitnessByWorkoutID: [UUID: Double] = {
            guard includesDetailMetrics else { return [:] }
            return await fetchIfPermitted(.workoutMetrics, default: [:]) {
                await fetchCardioFitness(forWorkouts: workouts)
            }
        }()
        async let stepCadenceByWorkoutID: [UUID: Double] = {
            guard includesDetailMetrics else { return [:] }
            return await fetchIfPermitted(.workoutMetrics, default: [:]) {
                await fetchStepCadence(forWorkouts: workouts)
            }
        }()
        async let workoutDistanceByWorkoutID: [UUID: Double] = {
            guard includesDetailMetrics else { return [:] }
            return await fetchIfPermitted(.workouts, default: [:]) {
                await fetchWorkoutDistances(forWorkouts: workouts)
            }
        }()

        let resolvedHeartRateSamples = await heartRateSamplesByWorkoutID
        let resolvedEffortLevels = await fetchedEffortLevels
        let resolvedCardioFitness = await cardioFitnessByWorkoutID
        let resolvedStepCadence = await stepCadenceByWorkoutID
        let resolvedWorkoutDistance = await workoutDistanceByWorkoutID
        let includesWorkoutMetrics = permissionSelection.includes(.workoutMetrics)

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)
        for workout in workouts {
            if reusedHeartRateIDs.contains(workout.uuid),
               let cached = reusableSummariesByID[workout.uuid] {
                summaries.append(
                    Self.summary(
                        for: workout,
                        reusingHeartRateFrom: cached,
                        effortLevel: resolvedEffortLevels[workout.uuid],
                        cardioFitnessVO2Max: resolvedCardioFitness[workout.uuid] ?? cached.cardioFitnessVO2Max,
                        averageStepCadenceSPM: resolvedStepCadence[workout.uuid] ?? cached.averageStepCadenceSPM,
                        resolvedDistanceMeters: resolvedWorkoutDistance[workout.uuid],
                        includesWorkoutMetrics: includesWorkoutMetrics
                    )
                )
            } else {
                summaries.append(
                    Self.summary(
                        for: workout,
                        heartRateSamples: resolvedHeartRateSamples[workout.uuid] ?? [],
                        effortLevel: resolvedEffortLevels[workout.uuid],
                        cardioFitnessVO2Max: resolvedCardioFitness[workout.uuid],
                        averageStepCadenceSPM: resolvedStepCadence[workout.uuid],
                        resolvedDistanceMeters: resolvedWorkoutDistance[workout.uuid],
                        includesWorkoutMetrics: includesWorkoutMetrics
                    )
                )
            }
        }

        return summaries
    }

    nonisolated static let heartRateReuseMinimumAge: TimeInterval = 24 * 60 * 60

    /// How close the cached samples' first/last dates must sit to the workout's
    /// start/end for the payload to count as complete. A payload cached during a
    /// partial Watch sync can be non-empty yet missing the opening minutes (the
    /// warm-up ramp), and would otherwise be reused forever once the workout ages
    /// past `heartRateReuseMinimumAge`. Watch workouts sample HR every few
    /// seconds, so a complete payload starts within seconds of the workout;
    /// sparse payloads (phone-only, third-party) simply re-fetch each load.
    nonisolated static let heartRateReuseCoverageTolerance: TimeInterval = 30

    /// Workouts whose cached heart-rate payload can be reused on a passive
    /// resume. All conditions must hold: identity + dates match the fresh
    /// `HKWorkout` (small tolerance against float drift; an edited workout
    /// falls out), the cached samples are non-empty and cover the workout window
    /// edge-to-edge within `heartRateReuseCoverageTolerance` (a payload cached
    /// mid-sync that misses the opening ramp re-fetches), and the workout ended
    /// over `heartRateReuseMinimumAge` ago — by then a partial Watch sync has
    /// resolved, so the re-fetched payload is complete and immutable.
    nonisolated static func heartRateReuseEligibleWorkoutIDs(
        workouts: [(id: UUID, startDate: Date, duration: TimeInterval)],
        cachedSummaries: [UUID: WorkoutSummary],
        now: Date,
        dateTolerance: TimeInterval = 1
    ) -> Set<UUID> {
        var eligible: Set<UUID> = []
        for workout in workouts {
            let endDate = workout.startDate.addingTimeInterval(workout.duration)
            guard let cached = cachedSummaries[workout.id],
                  abs(cached.startDate.timeIntervalSince(workout.startDate)) <= dateTolerance,
                  abs(cached.duration - workout.duration) <= dateTolerance,
                  let samples = cached.heartRateSamples, !samples.isEmpty,
                  let firstSampleDate = samples.map(\.date).min(),
                  let lastSampleDate = samples.map(\.date).max(),
                  firstSampleDate.timeIntervalSince(workout.startDate) <= heartRateReuseCoverageTolerance,
                  endDate.timeIntervalSince(lastSampleDate) <= heartRateReuseCoverageTolerance,
                  now.timeIntervalSince(endDate) > heartRateReuseMinimumAge else {
                continue
            }
            eligible.insert(workout.id)
        }
        return eligible
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

        let heartRateSamples = samples.compactMap { sample -> WorkoutHeartRateSample? in
            let beatsPerMinute = sample.quantity.doubleValue(for: heartRateUnit)
            guard beatsPerMinute.isFinite, beatsPerMinute > 0 else {
                return nil
            }
            return WorkoutHeartRateSample(date: sample.startDate, beatsPerMinute: beatsPerMinute)
        }
        return Self.partitionHeartRateSamples(
            heartRateSamples,
            forWorkoutWindows: workouts.map { (id: $0.uuid, startDate: $0.startDate, endDate: $0.endDate) }
        )
    }

    /// Assigns window-query heart-rate samples to each workout's
    /// `[startDate, endDate)` window. `samples` must be sorted ascending by
    /// date. Binary-searches each workout's first sample instead of
    /// rescanning the month's samples per workout (the prior restart-per-
    /// workout scan was O(workouts × samples)); overlapping workouts simply
    /// match the same samples.
    nonisolated static func partitionHeartRateSamples(
        _ samples: [WorkoutHeartRateSample],
        forWorkoutWindows windows: [(id: UUID, startDate: Date, endDate: Date)]
    ) -> [UUID: [WorkoutHeartRateSample]] {
        var samplesByWorkoutID: [UUID: [WorkoutHeartRateSample]] = [:]
        samplesByWorkoutID.reserveCapacity(windows.count)

        for window in windows {
            var index = firstSampleIndex(in: samples, atOrAfter: window.startDate)
            var workoutSamples: [WorkoutHeartRateSample] = []
            while index < samples.count, samples[index].date < window.endDate {
                workoutSamples.append(samples[index])
                index += 1
            }
            samplesByWorkoutID[window.id] = workoutSamples
        }
        return samplesByWorkoutID
    }

    /// First index whose sample date is at or after `date` (samples sorted
    /// ascending by date).
    nonisolated private static func firstSampleIndex(
        in samples: [WorkoutHeartRateSample],
        atOrAfter date: Date
    ) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].date < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Workout IDs that still need an effort-score query: anything without a
    /// cached score and not confirmed score-less. (The age policy applies on
    /// the confirmation side — see `confirmableNoEffortWorkoutIDs`.)
    nonisolated static func effortFetchCandidateIDs(
        workoutIDs: [UUID],
        cachedEffortIDs: Set<UUID>,
        confirmedNoEffortIDs: Set<UUID>
    ) -> Set<UUID> {
        Set(workoutIDs).subtracting(cachedEffortIDs).subtracting(confirmedNoEffortIDs)
    }

    /// Queried workouts that came back score-less and are old enough
    /// (`effortConfirmationAge`) that a rating is no longer expected — these
    /// are confirmed score-less and skipped for the rest of the process.
    /// Recent unrated workouts stay unconfirmed so the next refresh re-asks.
    /// `queried` must contain only workouts whose effort query **completed
    /// successfully** — an errored query proves nothing and must stay
    /// retryable on the next refresh.
    nonisolated static func confirmableNoEffortWorkoutIDs(
        queried: [(id: UUID, endDate: Date)],
        foundIDs: Set<UUID>,
        now: Date
    ) -> Set<UUID> {
        Set(
            queried
                .filter { !foundIDs.contains($0.id) && now.timeIntervalSince($0.endDate) > effortConfirmationAge }
                .map(\.id)
        )
    }

    private func fetchEffortLevels(forWorkouts workouts: [HKWorkout]) async -> [UUID: Double] {
        guard !workouts.isEmpty else {
            return [:]
        }

        let candidateIDs = Self.effortFetchCandidateIDs(
            workoutIDs: workouts.map(\.uuid),
            cachedEffortIDs: Set(effortLevelsByWorkoutID.keys),
            confirmedNoEffortIDs: confirmedNoEffortWorkoutIDs
        )
        let candidates = workouts.filter { candidateIDs.contains($0.uuid) }

        // HKWorkoutEffortScore needs one relationship-predicate query per
        // workout, so it can't be folded into a single OR-compound query the
        // way heart-rate samples are. Pump the task group with bounded
        // concurrency instead of one in-flight HK query per workout in the
        // month (multiple months refresh concurrently on top of this).
        let maxConcurrentQueries = 12
        let (fetched, completedIDs) = await withTaskGroup(
            of: (UUID, BodyWorkoutEffortOutcome).self,
            returning: ([UUID: Double], Set<UUID>).self
        ) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrentQueries, candidates.count) {
                let workout = candidates[nextIndex]
                group.addTask {
                    (workout.uuid, await self.fetchSavedEffortLevel(for: workout))
                }
                nextIndex += 1
            }

            var results: [UUID: Double] = [:]
            var completed: Set<UUID> = []
            for await (id, outcome) in group {
                switch outcome {
                case .found(let effort):
                    results[id] = effort
                    completed.insert(id)
                case .noSavedEffort:
                    completed.insert(id)
                case .failed:
                    break
                }
                if nextIndex < candidates.count {
                    let workout = candidates[nextIndex]
                    group.addTask {
                        (workout.uuid, await self.fetchSavedEffortLevel(for: workout))
                    }
                    nextIndex += 1
                }
            }
            return (results, completed)
        }

        // Single post-gather cache mutation: no mid-stream writes a concurrent
        // refresh could observe half-applied. Only successfully completed
        // queries can confirm a workout score-less — an errored query stays
        // uncached so the next refresh retries it.
        effortLevelsByWorkoutID.merge(fetched) { _, fresh in fresh }
        confirmedNoEffortWorkoutIDs.formUnion(
            Self.confirmableNoEffortWorkoutIDs(
                queried: candidates
                    .filter { completedIDs.contains($0.uuid) }
                    .map { (id: $0.uuid, endDate: $0.endDate) },
                foundIDs: Set(fetched.keys),
                now: Date()
            )
        )

        var results: [UUID: Double] = [:]
        results.reserveCapacity(workouts.count)
        for workout in workouts {
            if let effort = effortLevelsByWorkoutID[workout.uuid] {
                results[workout.uuid] = effort
            }
        }
        return results
    }

    private func fetchSavedEffortLevel(for workout: HKWorkout) async -> BodyWorkoutEffortOutcome {
        await BodyWorkoutEffortFetcher.savedEffortOutcome(for: workout, store: healthStore)
    }

    /// Cardio Fitness (VO₂max) per eligible workout. VO₂max is recorded
    /// standalone — not on the workout — so this matches a sample to the workout
    /// that produced it: an eligible type (`supportsCardioFitness`) that is NOT
    /// indoor, with a sample timestamped inside the workout's own window (plus a
    /// short grace for the post-workout write). There is deliberately no
    /// multi-day lookback — an indoor or reading-less workout shows nothing
    /// rather than inheriting an earlier outdoor workout's stale VO₂max.
    private func fetchCardioFitness(forWorkouts workouts: [HKWorkout]) async -> [UUID: Double] {
        let eligible = workouts.filter {
            HealthKitWorkoutStore.workoutType(for: $0.workoutActivityType).supportsCardioFitness
                && !Self.isIndoorWorkout($0)
        }
        guard !eligible.isEmpty,
              let vo2MaxType = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            return [:]
        }

        // Apple timestamps the VO₂max estimate within the workout it came from;
        // the grace only covers a slightly-delayed write and is far smaller than
        // the gap between separate workouts, so no reading bleeds across them.
        let writeGrace: TimeInterval = 5 * 60
        let rangeStart = eligible.map(\.startDate).min() ?? Date()
        let rangeEnd = (eligible.map(\.endDate).max() ?? Date()).addingTimeInterval(writeGrace)
        let predicate = HKQuery.predicateForSamples(withStart: rangeStart, end: rangeEnd, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let unit = HKUnit(from: "ml/kg*min")

        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: vo2MaxType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }

        guard !samples.isEmpty else { return [:] }
        let readings = samples.map { (endDate: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }

        var results: [UUID: Double] = [:]
        for workout in eligible {
            let windowEnd = workout.endDate.addingTimeInterval(writeGrace)
            // Ascending by end date; `last` is the reading this workout produced,
            // bounded to its own span so an older workout's value never carries.
            if let match = readings.last(where: { $0.endDate >= workout.startDate && $0.endDate <= windowEnd }),
               match.value.isFinite, match.value > 0 {
                results[workout.uuid] = match.value
            }
        }
        return results
    }

    /// Whether a workout is flagged indoor (`HKMetadataKeyIndoorWorkout`). Absent
    /// metadata is treated as outdoor — Apple only estimates VO₂max outdoors.
    nonisolated static func isIndoorWorkout(_ workout: HKWorkout) -> Bool {
        (workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue ?? false
    }

    /// Average foot cadence (steps/min) per eligible workout. `.stepCount` is not
    /// reliably exposed via `HKWorkout.statistics(for:)`, and a plain time-window
    /// sample query is wrong: it double-counts overlapping iPhone/Watch step
    /// samples and sweeps in non-workout steps that fall in the same window. So
    /// steps are read per workout, scoped to the workout's *own* samples via
    /// `predicateForObjects(from:)` and summed with `.cumulativeSum` (HealthKit's
    /// source-deduplicated aggregation), then divided by the workout's minutes.
    /// One relationship-scoped query per workout — pooled with bounded
    /// concurrency, like effort scores (months refresh concurrently on top).
    private func fetchStepCadence(forWorkouts workouts: [HKWorkout]) async -> [UUID: Double] {
        let eligible = workouts.filter {
            HealthKitWorkoutStore.workoutType(for: $0.workoutActivityType).supportsStepCadence
                && $0.duration > 0
        }
        guard !eligible.isEmpty,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return [:]
        }

        let maxConcurrentQueries = 12
        return await withTaskGroup(
            of: (UUID, Double?).self,
            returning: [UUID: Double].self
        ) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrentQueries, eligible.count) {
                let workout = eligible[nextIndex]
                group.addTask {
                    (workout.uuid, await self.stepCadence(for: workout, stepType: stepType))
                }
                nextIndex += 1
            }

            var results: [UUID: Double] = [:]
            for await (id, cadence) in group {
                if let cadence {
                    results[id] = cadence
                }
                if nextIndex < eligible.count {
                    let workout = eligible[nextIndex]
                    group.addTask {
                        (workout.uuid, await self.stepCadence(for: workout, stepType: stepType))
                    }
                    nextIndex += 1
                }
            }
            return results
        }
    }

    /// Steps associated with `workout` (cumulative-sum statistics over the
    /// workout's own samples, deduplicated across sources by HealthKit) divided
    /// by its duration in minutes. Returns nil when no steps are attributed.
    private func stepCadence(for workout: HKWorkout, stepType: HKQuantityType) async -> Double? {
        let minutes = workout.duration / 60
        guard minutes > 0 else { return nil }

        let totalSteps: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            healthStore.execute(query)
        }

        guard let totalSteps, totalSteps > 0 else { return nil }
        return totalSteps / minutes
    }

    /// Total distance (m) per distance-tracking workout that lacks the legacy
    /// `totalDistance` aggregate. Like step cadence, distance can live only in the
    /// workout's *associated* samples (not `HKWorkout.statistics(for:)`), so it's
    /// read per workout via `predicateForObjects(from:)` + `.cumulativeSum`,
    /// source-deduplicated by HealthKit. One query per workout, bounded concurrency.
    private func fetchWorkoutDistances(forWorkouts workouts: [HKWorkout]) async -> [UUID: Double] {
        let eligible = workouts.filter {
            $0.totalDistance == nil
                && HealthKitFetchEngine.distanceQuantityTypeIdentifier(
                    for: HealthKitWorkoutStore.workoutType(for: $0.workoutActivityType)
                ) != nil
        }
        guard !eligible.isEmpty else { return [:] }

        let maxConcurrentQueries = 12
        return await withTaskGroup(
            of: (UUID, Double?).self,
            returning: [UUID: Double].self
        ) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrentQueries, eligible.count) {
                let workout = eligible[nextIndex]
                group.addTask { (workout.uuid, await self.workoutDistanceMeters(for: workout)) }
                nextIndex += 1
            }

            var results: [UUID: Double] = [:]
            for await (id, distance) in group {
                if let distance {
                    results[id] = distance
                }
                if nextIndex < eligible.count {
                    let workout = eligible[nextIndex]
                    group.addTask { (workout.uuid, await self.workoutDistanceMeters(for: workout)) }
                    nextIndex += 1
                }
            }
            return results
        }
    }

    /// Distance (m) attributed to `workout`'s own samples — cumulative-sum over the
    /// activity's distance type. Returns nil when no distance is attributed.
    private func workoutDistanceMeters(for workout: HKWorkout) async -> Double? {
        let type = HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType)
        guard let identifier = HealthKitFetchEngine.distanceQuantityTypeIdentifier(for: type),
              let distanceType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let meters: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .meter()))
            }
            healthStore.execute(query)
        }

        guard let meters, meters > 0 else { return nil }
        return meters
    }

    // Sleep summary + history + per-day vitals hydration live in
    // `HealthKitFetchEngine+Sleep.swift`.

    // Training-load summary + trend series live in
    // `HealthKitFetchEngine+TrainingLoad.swift`.

    // Activity Rings summary + history live in
    // `HealthKitFetchEngine+ActivityRings.swift`.

    // Source-option discovery + the per-metric source map live in
    // `HealthKitFetchEngine+SourceOptions.swift`.

    // Secondary-source trend / day-sample / range dispatchers live in
    // `HealthKitFetchEngine+Secondary.swift`.

    // Intraday sample fetches + incremental merge helpers live in
    // `HealthKitFetchEngine+IntradaySamples.swift`.

    // MARK: - Orchestrators

    func fetchHealthSummary(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection = .defaultValue
    ) async -> HealthSummarySnapshot {
        async let activityRings = fetchDashboardActivityRingsIfNeeded(selection: selection, default: ActivityRingSummary.empty) {
            await fetchActivityRingSummary(calendar: calendar)
        }
        async let sleep: SleepSummary? = fetchDashboardMetricIfNeeded(.sleep, selection: selection, default: nil) {
            await fetchSleepSummary(calendar: calendar)
        }
        async let heartRate: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.heartRate, selection: selection, default: nil) {
            await latestQuantity(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .heartRate
            )
        }
        async let restingHeartRate: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.restingHeartRate, selection: selection, default: nil) {
            await latestQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .restingHeartRate
            )
        }
        async let bodyMass: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.bodyMass, selection: selection, default: nil) {
            await latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), sourceKind: .basics)
        }
        async let bodyFatPercentage: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.bodyFatPercentage, selection: selection, default: nil) {
            await latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let heartRateVariability: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.heartRateVariability, selection: selection, default: nil) {
            await latestQuantity(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                sourceKind: .heartRateVariability
            )
        }
        async let respiratoryRate: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.respiratoryRate, selection: selection, default: nil) {
            await latestQuantity(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .respiratoryRate
            )
        }
        async let oxygenSaturation: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.oxygenSaturation, selection: selection, default: nil) {
            await latestQuantity(
                for: .oxygenSaturation,
                unit: .percent(),
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let bodyMassIndex: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.bodyMassIndex, selection: selection, default: nil) {
            await latestQuantity(for: .bodyMassIndex, unit: .count(), sourceKind: .basics)
        }
        async let activeEnergy: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.activeEnergy, selection: selection, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
        }
        async let restingEnergy: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.restingEnergy, selection: selection, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
        }
        async let exerciseMinutes: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.exerciseMinutes, selection: selection, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
        }
        async let trainingLoad: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.trainingLoad, selection: selection, default: nil) {
            await fetchTrainingLoadSummary(calendar: calendar)
        }
        async let wristTemperature: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.wristTemperature, selection: selection, default: nil) {
            await dailyQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )
        }
        async let timeInDaylight: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.timeInDaylight, selection: selection, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )
        }
        async let steps: HealthMetricSummary? = fetchDashboardMetricIfNeeded(.steps, selection: selection, default: nil) {
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

    func fetchHealthTrends(
        calendar: Calendar,
        cachedTrends: HealthTrendSnapshot,
        selection: BodyDashboardFetchSelection = .defaultValue
    ) async -> HealthTrendSnapshot {
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

        async let sleepHistory = fetchDashboardMetricIfNeeded(.sleep, selection: selection, default: SleepHistorySnapshot.empty) {
            await fetchDailySleepHistory(calendar: calendar)
        }
        async let sleepHistorySecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .sleep,
            selection: selection,
            permission: .sleep,
            default: SleepHistorySnapshot.empty
        ) {
            await fetchSecondarySleepHistory(calendar: calendar)
        }
        async let restingHeartRate = fetchDashboardMetricIfNeeded(.restingHeartRate, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate
            )
        }
        async let restingHeartRateSecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .restingHeartRate,
            selection: selection,
            permission: .heart,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .restingHeartRate, calendar: calendar)
        }
        async let heartRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDashboardMetricIfNeeded(
            .heartRate,
            selection: selection,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .heartRate
            )
        }
        async let heartRateRangesSecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .heartRate,
            selection: selection,
            permission: .heart,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .heartRate, calendar: calendar)
        }
        async let bodyMass = fetchDashboardMetricIfNeeded(.bodyMass, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )
        }
        async let bodyFatPercentage = fetchDashboardMetricIfNeeded(.bodyFatPercentage, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let heartRateVariabilityPair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDashboardMetricIfNeeded(
            .heartRateVariability,
            selection: selection,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar,
                sourceKind: .heartRateVariability
            )
        }
        async let heartRateVariabilityRangesSecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .heartRateVariability,
            selection: selection,
            permission: .heart,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .heartRateVariability, calendar: calendar)
        }
        async let respiratoryRatePair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDashboardMetricIfNeeded(
            .respiratoryRate,
            selection: selection,
            default: (HealthTrendSeries.empty, HealthTrendRangeSeries.empty)
        ) {
            await fetchDailyQuantityAverageAndRangeSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar,
                sourceKind: .respiratoryRate
            )
        }
        async let oxygenSaturationPair: (HealthTrendSeries, HealthTrendRangeSeries) = fetchDashboardMetricIfNeeded(
            .oxygenSaturation,
            selection: selection,
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
        async let oxygenSaturationRangesSecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .oxygenSaturation,
            selection: selection,
            permission: .bloodOxygen,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .oxygenSaturation, calendar: calendar)
        }
        async let bodyMassIndex = fetchDashboardMetricIfNeeded(.bodyMassIndex, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )
        }
        async let activeEnergy = fetchDashboardMetricIfNeeded(.activeEnergy, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
        }
        async let activeEnergySecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .activeEnergy,
            selection: selection,
            permission: .energy,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .activeEnergy, calendar: calendar)
        }
        async let restingEnergy = fetchDashboardMetricIfNeeded(.restingEnergy, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
        }
        async let restingEnergySecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .restingEnergy,
            selection: selection,
            permission: .energy,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .restingEnergy, calendar: calendar)
        }
        async let exerciseMinutes = fetchDashboardMetricIfNeeded(.exerciseMinutes, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
        }
        async let exerciseMinutesSecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .exerciseMinutes,
            selection: selection,
            permission: .exerciseMinutes,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .exerciseMinutes, calendar: calendar)
        }
        async let trainingLoad = fetchDashboardMetricIfNeeded(.trainingLoad, selection: selection, default: HealthTrendSeries.empty) {
            await fetchTrainingLoadSeries(calendar: calendar)
        }
        async let wristTemperature = fetchDashboardMetricIfNeeded(.wristTemperature, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )
        }
        async let timeInDaylight = fetchDashboardMetricIfNeeded(.timeInDaylight, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )
        }
        async let steps = fetchDashboardMetricIfNeeded(.steps, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
        }
        async let stepsSecondary = fetchSecondaryDashboardMetricIfNeeded(
            for: .steps,
            selection: selection,
            permission: .steps,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .steps, calendar: calendar)
        }

        let fetchedSleepHistory = await sleepHistory
        let fetchedSleepHistorySecondary = await sleepHistorySecondary
        let (fetchedHeartRate, fetchedHeartRateRanges) = await heartRatePair
        let (fetchedHeartRateVariability, fetchedHeartRateVariabilityRanges) = await heartRateVariabilityPair
        let (fetchedRespiratoryRate, fetchedRespiratoryRateRanges) = await respiratoryRatePair
        let (fetchedOxygenSaturation, fetchedOxygenSaturationRanges) = await oxygenSaturationPair
        return await HealthTrendSnapshot(
            sleep: fetchedSleepHistory.durationSeries,
            sleepSecondary: fetchedSleepHistorySecondary.durationSeries,
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
            sleepHistorySecondary: fetchedSleepHistorySecondary,
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
            stepsDaySamplesSecondary: cachedStepsDaySamplesSecondary,
            recordedReadiness: cachedTrends.recordedReadiness,
            recordedReadinessContext: cachedTrends.recordedReadinessContext
        )
    }

    /// Incremental day-sample refetch for the per-metric detail refresh:
    /// only asks HealthKit for samples newer than the cached series, then
    /// merges (mirroring `HealthKitWorkoutStore.loadIntradayMetricSamplesIfNeeded`)
    /// instead of re-shipping the full trend window of raw samples.
    /// Secondary-source day samples still refetch fully — the comparison
    /// source can change between refreshes, and an incremental merge would
    /// extend the old source's samples instead of replacing them.
    private func fetchIncrementalPrimaryDaySamples(
        for kind: HealthMetricKind,
        cached: HealthTrendSeries,
        calendar: Calendar
    ) async -> HealthTrendSeries {
        let interval = recentHealthTrendInterval(calendar: calendar)
        let fetchStart = Self.incrementalFetchStart(after: cached, windowStart: interval.start)
        guard fetchStart < interval.end else {
            return Self.mergeIntradaySamples(existing: cached, incoming: .empty, windowStart: interval.start)
        }

        let incoming = await fetchIntradayDaySamples(
            for: kind,
            calendar: calendar,
            startDate: fetchStart,
            endDate: interval.end
        )
        return Self.mergeIntradaySamples(existing: cached, incoming: incoming, windowStart: interval.start)
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
            async let sleepHistorySecondary = fetchSecondarySleepHistory(calendar: calendar)
            let fetchedSleepHistory = await sleepHistory
            let fetchedSleepHistorySecondary = await sleepHistorySecondary

            summary.sleep = await sleepSummary ?? HealthSummarySnapshot.empty.sleep
            trends.sleep = fetchedSleepHistory.durationSeries
            trends.sleepSecondary = fetchedSleepHistorySecondary.durationSeries
            trends.sleepHistory = fetchedSleepHistory
            trends.sleepHistorySecondary = fetchedSleepHistorySecondary
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
            async let heartRateDaySamples = fetchIncrementalPrimaryDaySamples(
                for: .heartRate,
                cached: existing.trends.heartRateDaySamples,
                calendar: calendar
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
            async let restingHeartRateDaySamples = fetchIncrementalPrimaryDaySamples(
                for: .restingHeartRate,
                cached: existing.trends.restingHeartRateDaySamples,
                calendar: calendar
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
            async let heartRateVariabilityDaySamples = fetchIncrementalPrimaryDaySamples(
                for: .heartRateVariability,
                cached: existing.trends.heartRateVariabilityDaySamples,
                calendar: calendar
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
            async let respiratoryRateDaySamples = fetchIncrementalPrimaryDaySamples(
                for: .respiratoryRate,
                cached: existing.trends.respiratoryRateDaySamples,
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
            async let oxygenSaturationDaySamples = fetchIncrementalPrimaryDaySamples(
                for: .oxygenSaturation,
                cached: existing.trends.oxygenSaturationDaySamples,
                calendar: calendar
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
