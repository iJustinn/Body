//
//  HealthKitWorkoutStore.swift
//  Body
//

import Foundation
import HealthKit
import WidgetKit

struct BodyWorkoutMonthKey: Hashable {
    let month: Int
    let year: Int

    init(month: Int, year: Int) {
        self.month = month
        self.year = year
    }

    init(date: Date, calendar: Calendar = .bodyGregorian) {
        self.month = calendar.component(.month, from: date)
        self.year = calendar.component(.year, from: date)
    }
}

@MainActor
final class HealthKitWorkoutStore: ObservableObject {
    static let recentChartMonthCount = 3

    enum AuthorizationState: Equatable {
        case unknown
        case unavailable
        case authorized
        case denied
        case failed(String)
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var snapshot: WorkoutMonthSnapshot
    @Published private(set) var monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot]
    @Published private(set) var healthSummary: HealthSummarySnapshot = .empty
    @Published private(set) var healthDataNotice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadingMonthKeys: Set<BodyWorkoutMonthKey> = []

    private let healthStore = HKHealthStore()
    private var loadedMonthKeys: Set<BodyWorkoutMonthKey> = []
    private var lastAppEntrySyncDate: Date?

    init(initialSnapshot: WorkoutMonthSnapshot = WorkoutSnapshotStore.loadOrPlaceholder()) {
        snapshot = initialSnapshot
        monthSnapshots = [
            BodyWorkoutMonthKey(month: initialSnapshot.month, year: initialSnapshot.year): initialSnapshot
        ]
    }

    func requestAuthorizationAndRefresh() async {
        guard !isRefreshing else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        do {
            try await requestAuthorization()
            await refreshRecentMonths()
        } catch {
            handleRefreshError(error)
        }
    }

    func syncWhenAppBecomesActive(date: Date = Date()) async {
        guard !isRefreshing else {
            return
        }

        if let lastAppEntrySyncDate, date.timeIntervalSince(lastAppEntrySyncDate) < 60 {
            return
        }

        lastAppEntrySyncDate = date
        await requestAuthorizationAndRefresh()
    }

    func snapshot(month: Int, year: Int) -> WorkoutMonthSnapshot {
        let key = BodyWorkoutMonthKey(month: month, year: year)
        if let snapshot = monthSnapshots[key] {
            return snapshot
        }

        return WorkoutMonthSnapshot.make(month: month, year: year, workouts: [], calendar: .bodyGregorian)
    }

    func hasLoadedSnapshot(month: Int, year: Int) -> Bool {
        loadedMonthKeys.contains(BodyWorkoutMonthKey(month: month, year: year))
    }

    func isLoadingSnapshot(month: Int, year: Int) -> Bool {
        loadingMonthKeys.contains(BodyWorkoutMonthKey(month: month, year: year))
    }

    func loadRecentWorkoutMonthsIfNeeded(date: Date = Date()) async {
        guard !isRefreshing else {
            return
        }

        let requestedKeys = Self.recentMonthKeys(
            count: Self.recentChartMonthCount,
            from: date,
            calendar: .bodyGregorian
        )
        let missingKeys = requestedKeys
            .subtracting(loadedMonthKeys)
            .subtracting(loadingMonthKeys)

        guard !missingKeys.isEmpty else {
            return
        }

        await loadMonthKeysIfNeeded(missingKeys)
    }

    @discardableResult
    func loadMonthIfNeeded(month: Int, year: Int) async -> Bool {
        let key = BodyWorkoutMonthKey(month: month, year: year)
        guard !loadedMonthKeys.contains(key) else {
            return true
        }

        while isRefreshing, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard !loadedMonthKeys.contains(key) else {
            return true
        }

        while loadingMonthKeys.contains(key), !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard !loadedMonthKeys.contains(key) else {
            return true
        }

        await loadMonthKeysIfNeeded([key])
        return loadedMonthKeys.contains(key)
    }

    func refreshCurrentMonth(date: Date = Date()) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        let calendar = Calendar.bodyGregorian
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        await refresh(month: month, year: year, calendar: calendar, updatesHealthSummary: true)
    }

    private func refreshRecentMonths(date: Date = Date()) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let calendar = Calendar.bodyGregorian
        let keys = Self.recentMonthKeys(count: Self.recentChartMonthCount, from: date, calendar: calendar)

        do {
            try await refresh(monthKeys: keys, calendar: calendar)
            let nextHealthSummary = await fetchHealthSummary(calendar: calendar)
            healthSummary = nextHealthSummary
            authorizationState = .authorized
            updateCurrentMonthSnapshot(date: date, calendar: calendar)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
    }

    private func refresh(month: Int, year: Int, calendar: Calendar, updatesHealthSummary: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let key = BodyWorkoutMonthKey(month: month, year: year)

        do {
            try await refresh(monthKeys: [key], calendar: calendar)
            if updatesHealthSummary {
                healthSummary = await fetchHealthSummary(calendar: calendar)
            }
            authorizationState = .authorized
            updateCurrentMonthSnapshot(date: Date(), calendar: calendar)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
    }

    private func loadMonthKeysIfNeeded(_ keys: Set<BodyWorkoutMonthKey>) async {
        guard !keys.isEmpty else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        let keysToLoad = keys
            .subtracting(loadedMonthKeys)
            .subtracting(loadingMonthKeys)

        guard !keysToLoad.isEmpty else {
            return
        }

        loadingMonthKeys.formUnion(keysToLoad)
        defer { loadingMonthKeys.subtract(keysToLoad) }

        do {
            try await requestAuthorization()
            try await refresh(monthKeys: keysToLoad, calendar: .bodyGregorian)
            authorizationState = .authorized
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
    }

    private func refresh(monthKeys: Set<BodyWorkoutMonthKey>, calendar: Calendar) async throws {
        for key in monthKeys.sortedByDate {
            let workouts = try await fetchWorkouts(month: key.month, year: key.year, calendar: calendar)
            monthSnapshots[key] = WorkoutMonthSnapshot.make(
                month: key.month,
                year: key.year,
                workouts: workouts,
                calendar: calendar
            )
            loadedMonthKeys.insert(key)
        }
    }

    private func updateCurrentMonthSnapshot(date: Date, calendar: Calendar) {
        let currentKey = BodyWorkoutMonthKey(date: date, calendar: calendar)
        guard let currentSnapshot = monthSnapshots[currentKey] else {
            return
        }

        snapshot = currentSnapshot
        WorkoutSnapshotStore.save(currentSnapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateHealthDataNotice() {
        guard snapshot.workoutCount == 0, healthSummary.isEmpty else {
            healthDataNotice = nil
            return
        }

        healthDataNotice = "No Apple Health data was found. If you expected data, check Body's permissions in the Health app."
    }

    private func handleRefreshError(_ error: Error) {
        if case HealthKitWorkoutError.authorizationDenied = error {
            authorizationState = .denied
        } else {
            authorizationState = .failed(error.localizedDescription)
        }
        healthDataNotice = error.localizedDescription
    }

    private static func recentMonthKeys(
        count: Int,
        from date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> Set<BodyWorkoutMonthKey> {
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: date)?.start else {
            return [BodyWorkoutMonthKey(date: date, calendar: calendar)]
        }

        return Set((0..<max(count, 1)).compactMap { offset in
            guard let monthDate = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else {
                return nil
            }

            return BodyWorkoutMonthKey(date: monthDate, calendar: calendar)
        })
    }

    private func requestAuthorization() async throws {
        let requestedTypes = Self.readObjectTypes()
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

    nonisolated private static func readObjectTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]

        [
            HKQuantityTypeIdentifier.restingHeartRate,
            .bodyMass,
            .bodyFatPercentage,
            .heartRateVariabilitySDNN,
            .oxygenSaturation,
            .vo2Max,
            .bodyMassIndex
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { types.insert($0) }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        return types
    }

    private func fetchWorkouts(month: Int, year: Int, calendar: Calendar) async throws -> [WorkoutSummary] {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
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

                let workouts = (samples as? [HKWorkout] ?? []).map(Self.summary)
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    private func fetchHealthSummary(calendar: Calendar) async -> HealthSummarySnapshot {
        async let sleep = fetchSleepSummary(calendar: calendar)
        async let restingHeartRate = latestQuantity(
            for: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let bodyMass = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo))
        async let bodyFatPercentage = latestQuantity(
            for: .bodyFatPercentage,
            unit: .percent(),
            valueTransform: Self.normalizedPercentDisplayValue
        )
        async let heartRateVariability = latestQuantity(
            for: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli)
        )
        async let oxygenSaturation = latestQuantity(
            for: .oxygenSaturation,
            unit: .percent(),
            valueTransform: Self.normalizedPercentDisplayValue
        )
        async let vo2Max = latestQuantity(for: .vo2Max, unit: Self.vo2MaxUnit)
        async let bodyMassIndex = latestQuantity(for: .bodyMassIndex, unit: .count())

        return await HealthSummarySnapshot(
            sleep: sleep ?? HealthSummarySnapshot.empty.sleep,
            restingHeartRate: restingHeartRate ?? HealthSummarySnapshot.empty.restingHeartRate,
            bodyMass: bodyMass ?? HealthSummarySnapshot.empty.bodyMass,
            bodyFatPercentage: bodyFatPercentage ?? HealthSummarySnapshot.empty.bodyFatPercentage,
            heartRateVariability: heartRateVariability ?? HealthSummarySnapshot.empty.heartRateVariability,
            oxygenSaturation: oxygenSaturation ?? HealthSummarySnapshot.empty.oxygenSaturation,
            vo2Max: vo2Max ?? HealthSummarySnapshot.empty.vo2Max,
            bodyMassIndex: bodyMassIndex ?? HealthSummarySnapshot.empty.bodyMassIndex
        )
    }

    private func latestQuantity(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
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

    private func fetchSleepSummary(calendar: Calendar) async -> SleepSummary? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -14, to: endDate) ?? endDate.addingTimeInterval(-1_209_600)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let sleepSamples = (samples as? [HKCategorySample] ?? [])
                    .filter(Self.isAsleep)

                guard let latestEndDate = sleepSamples.map(\.endDate).max() else {
                    continuation.resume(returning: nil)
                    return
                }

                let sessionStartLimit = calendar.date(byAdding: .hour, value: -18, to: latestEndDate)
                    ?? latestEndDate.addingTimeInterval(-64_800)
                let sessionSamples = sleepSamples.filter {
                    $0.startDate >= sessionStartLimit && $0.endDate <= latestEndDate
                }

                guard !sessionSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let duration = Self.mergedSleepDuration(
                    intervals: sessionSamples.map { ($0.startDate, $0.endDate) }
                )
                continuation.resume(
                    returning: SleepSummary(
                        duration: duration
                    )
                )
            }

            healthStore.execute(query)
        }
    }

    nonisolated private static var vo2MaxUnit: HKUnit {
        HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    }

    nonisolated private static func normalizedPercentDisplayValue(_ value: Double) -> Double {
        value <= 1 ? value * 100 : value
    }

    nonisolated static func mergedSleepDuration(intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sortedIntervals = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        guard var current = sortedIntervals.first else {
            return 0
        }

        var duration: TimeInterval = 0

        for interval in sortedIntervals.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                duration += current.end.timeIntervalSince(current.start)
                current = interval
            }
        }

        duration += current.end.timeIntervalSince(current.start)
        return duration
    }

    nonisolated private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    nonisolated private static func summary(for workout: HKWorkout) -> WorkoutSummary {
        WorkoutSummary(
            id: workout.uuid,
            type: workoutType(for: workout.workoutActivityType),
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergyKilocalories(for: workout),
            distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
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

    nonisolated static func workoutType(for activityType: HKWorkoutActivityType) -> BodyWorkoutType {
        switch activityType.rawValue {
        case 1:
            return .americanFootball
        case 2:
            return .archery
        case 3:
            return .australianFootball
        case 4:
            return .badminton
        case 5:
            return .baseball
        case 6:
            return .basketball
        case 7:
            return .bowling
        case 8:
            return .boxing
        case 9:
            return .climbing
        case 10:
            return .cricket
        case 11:
            return .crossTraining
        case 12:
            return .curling
        case 13:
            return .cycling
        case 14:
            return .dance
        case 15:
            return .danceInspiredTraining
        case 16:
            return .elliptical
        case 17:
            return .equestrianSports
        case 18:
            return .fencing
        case 19:
            return .fishing
        case 20:
            return .functionalStrengthTraining
        case 21:
            return .golf
        case 22:
            return .gymnastics
        case 23:
            return .handball
        case 24:
            return .hiking
        case 25:
            return .hockey
        case 26:
            return .hunting
        case 27:
            return .lacrosse
        case 28:
            return .martialArts
        case 29:
            return .mindAndBody
        case 30:
            return .mixedMetabolicCardioTraining
        case 31:
            return .paddleSports
        case 32:
            return .play
        case 33:
            return .preparationAndRecovery
        case 34:
            return .racquetball
        case 35:
            return .rowing
        case 36:
            return .rugby
        case 37:
            return .running
        case 38:
            return .sailing
        case 39:
            return .skatingSports
        case 40:
            return .snowSports
        case 41:
            return .soccer
        case 42:
            return .softball
        case 43:
            return .squash
        case 44:
            return .stairClimbing
        case 45:
            return .surfingSports
        case 46:
            return .swimming
        case 47:
            return .tableTennis
        case 48:
            return .tennis
        case 49:
            return .trackAndField
        case 50:
            return .strengthTraining
        case 51:
            return .volleyball
        case 52:
            return .walking
        case 53:
            return .waterFitness
        case 54:
            return .waterPolo
        case 55:
            return .waterSports
        case 56:
            return .wrestling
        case 57:
            return .yoga
        case 58:
            return .barre
        case 59:
            return .coreTraining
        case 60:
            return .crossCountrySkiing
        case 61:
            return .downhillSkiing
        case 62:
            return .flexibility
        case 63:
            return .hiit
        case 64:
            return .jumpRope
        case 65:
            return .kickboxing
        case 66:
            return .pilates
        case 67:
            return .snowboarding
        case 68:
            return .stairs
        case 69:
            return .stepTraining
        case 70:
            return .wheelchairWalkPace
        case 71:
            return .wheelchairRunPace
        case 72:
            return .taiChi
        case 73:
            return .mixedCardio
        case 74:
            return .handCycling
        case 75:
            return .discSports
        case 76:
            return .fitnessGaming
        case 77:
            return .cardioDance
        case 78:
            return .socialDance
        case 79:
            return .pickleball
        case 80:
            return .cooldown
        case 82:
            return .swimBikeRun
        case 83:
            return .transition
        case 84:
            return .underwaterDiving
        default:
            return .other
        }
    }
}

private extension Set where Element == BodyWorkoutMonthKey {
    var sortedByDate: [BodyWorkoutMonthKey] {
        sorted {
            if $0.year == $1.year {
                return $0.month < $1.month
            }

            return $0.year < $1.year
        }
    }
}

private enum HealthKitWorkoutError: LocalizedError {
    case authorizationDenied
    case authorizationStatusUnknown

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Apple Health access was not granted."
        case .authorizationStatusUnknown:
            return "Apple Health access could not be confirmed."
        }
    }
}
