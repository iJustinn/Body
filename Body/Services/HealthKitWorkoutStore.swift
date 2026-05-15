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
    @Published private(set) var healthTrends: HealthTrendSnapshot = .empty
    @Published private(set) var activityRingHistory: ActivityRingHistorySnapshot = .empty
    @Published private(set) var permissionSelection: BodyHealthPermissionSelection
    @Published private(set) var healthDataNotice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadingMonthKeys: Set<BodyWorkoutMonthKey> = []
    @Published private(set) var loadingActivityRingMonthKeys: Set<ActivityRingMonthKey> = []

    private let healthStore = HKHealthStore()
    private var loadedMonthKeys: Set<BodyWorkoutMonthKey> = []
    private var loadedActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    private var lastAppEntrySyncDate: Date?

    init(
        initialSnapshot: WorkoutMonthSnapshot = WorkoutSnapshotStore.loadOrPlaceholder(),
        initialHealthDashboardSnapshot: HealthDashboardSnapshot = HealthDashboardSnapshotStore.loadOrEmpty(),
        initialPermissionSelection: BodyHealthPermissionSelection = BodyHealthPermissionSelection.load(),
        date: Date = Date()
    ) {
        permissionSelection = initialPermissionSelection
        let filteredHealthDashboardSnapshot = initialHealthDashboardSnapshot.filtered(by: initialPermissionSelection)
        let startingSnapshot = initialPermissionSelection.includes(.workouts)
            ? initialSnapshot
            : WorkoutMonthSnapshot.make(
                month: initialSnapshot.month,
                year: initialSnapshot.year,
                workouts: [],
                calendar: .bodyGregorian
            )
        snapshot = startingSnapshot
        monthSnapshots = [
            BodyWorkoutMonthKey(month: startingSnapshot.month, year: startingSnapshot.year): startingSnapshot
        ]
        healthSummary = filteredHealthDashboardSnapshot.summary
        healthTrends = filteredHealthDashboardSnapshot.trends
        activityRingHistory = filteredHealthDashboardSnapshot.activityRingHistory.removingLikelyBoundaryTruncatedLoadedMonths(
            date: date,
            calendar: .bodyGregorian
        )
        loadedActivityRingMonthKeys = Set(activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))
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

    func updateHealthPermission(_ permission: BodyHealthPermission, isEnabled: Bool) async {
        let nextSelection = permissionSelection.setting(permission, isEnabled: isEnabled)
        guard nextSelection != permissionSelection else {
            return
        }

        permissionSelection = nextSelection
        nextSelection.save()
        applyPermissionSelectionToCachedData()

        if isEnabled {
            await requestAuthorizationAndRefresh()
        } else {
            updateHealthDataNotice()
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

    func loadPreviousActivityRingMonthIfNeeded(date: Date = Date()) async {
        while isRefreshing, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        guard permissionSelection.includes(.activityRings) else {
            activityRingHistory = .empty
            loadedActivityRingMonthKeys.removeAll()
            return
        }

        guard !Task.isCancelled, loadingActivityRingMonthKeys.isEmpty else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        let calendar = Calendar.bodyGregorian
        if loadedActivityRingMonthKeys.isEmpty {
            loadedActivityRingMonthKeys = Set(activityRingHistory.loadedMonthKeySet(calendar: calendar))
        }

        let loadedKeys = loadedActivityRingMonthKeys.isEmpty
            ? [ActivityRingMonthKey(date: date, calendar: calendar)]
            : loadedActivityRingMonthKeys.sortedByDate
        guard
            let earliestLoadedMonth = loadedKeys.first,
            let earliestMonthStart = earliestLoadedMonth.startDate(calendar: calendar),
            let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: earliestMonthStart)
        else {
            return
        }

        let previousMonthKey = ActivityRingMonthKey(date: previousMonthDate, calendar: calendar)
        guard !loadedActivityRingMonthKeys.contains(previousMonthKey) else {
            return
        }

        loadingActivityRingMonthKeys.insert(previousMonthKey)
        defer { loadingActivityRingMonthKeys.remove(previousMonthKey) }

        do {
            try await requestAuthorization()
            let previousHistory = await fetchActivityRingHistory(monthKey: previousMonthKey, calendar: calendar)
            guard !previousHistory.loadedMonthKeys.isEmpty else {
                return
            }

            let nextHistory = activityRingHistory.replacingLoadedMonths(with: previousHistory, calendar: calendar)
            activityRingHistory = nextHistory
            loadedActivityRingMonthKeys = Set(nextHistory.loadedMonthKeySet(calendar: calendar))
            HealthDashboardSnapshotStore.save(
                HealthDashboardSnapshot(
                    summary: healthSummary,
                    trends: healthTrends,
                    activityRingHistory: nextHistory
                )
            )
            authorizationState = .authorized
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
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
            if permissionSelection.includes(.workouts) {
                try await refresh(monthKeys: keys, calendar: calendar)
            } else {
                clearWorkoutSnapshots(calendar: calendar)
            }
            async let nextHealthSummary = fetchHealthSummary(calendar: calendar)
            async let nextHealthTrends = fetchHealthTrends(calendar: calendar)
            async let nextActivityRingHistory = fetchActivityRingHistory(calendar: calendar)
            let fetchedHealthSummary = await nextHealthSummary
            let fetchedHealthTrends = await nextHealthTrends
            let fetchedActivityRingHistory = await nextActivityRingHistory
            updateHealthDashboardSnapshot(
                summary: fetchedHealthSummary,
                trends: fetchedHealthTrends,
                activityRingHistory: fetchedActivityRingHistory
            )
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
            if permissionSelection.includes(.workouts) {
                try await refresh(monthKeys: [key], calendar: calendar)
            } else {
                clearWorkoutSnapshots(calendar: calendar)
            }
            if updatesHealthSummary {
                async let nextHealthSummary = fetchHealthSummary(calendar: calendar)
                async let nextHealthTrends = fetchHealthTrends(calendar: calendar)
                async let nextActivityRingHistory = fetchActivityRingHistory(calendar: calendar)
                let fetchedHealthSummary = await nextHealthSummary
                let fetchedHealthTrends = await nextHealthTrends
                let fetchedActivityRingHistory = await nextActivityRingHistory
                updateHealthDashboardSnapshot(
                    summary: fetchedHealthSummary,
                    trends: fetchedHealthTrends,
                    activityRingHistory: fetchedActivityRingHistory
                )
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

        guard permissionSelection.includes(.workouts) else {
            clearWorkoutSnapshots()
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

    private func updateHealthDashboardSnapshot(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        activityRingHistory: ActivityRingHistorySnapshot
    ) {
        let calendar = Calendar.bodyGregorian
        let filteredSnapshot = HealthDashboardSnapshot(
            summary: summary,
            trends: trends,
            activityRingHistory: activityRingHistory
        )
        .filtered(by: permissionSelection)
        let nextActivityRingHistory = self.activityRingHistory.replacingLoadedMonths(
            with: filteredSnapshot.activityRingHistory,
            calendar: calendar
        )
        healthSummary = filteredSnapshot.summary
        healthTrends = filteredSnapshot.trends
        self.activityRingHistory = nextActivityRingHistory
        loadedActivityRingMonthKeys = Set(nextActivityRingHistory.loadedMonthKeySet(calendar: calendar))
        HealthDashboardSnapshotStore.save(
            HealthDashboardSnapshot(
                summary: filteredSnapshot.summary,
                trends: filteredSnapshot.trends,
                activityRingHistory: nextActivityRingHistory
            )
        )
    }

    private func applyPermissionSelectionToCachedData() {
        let filteredSnapshot = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        .filtered(by: permissionSelection)

        healthSummary = filteredSnapshot.summary
        healthTrends = filteredSnapshot.trends
        activityRingHistory = filteredSnapshot.activityRingHistory
        loadedActivityRingMonthKeys = Set(filteredSnapshot.activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))

        if !permissionSelection.includes(.workouts) {
            clearWorkoutSnapshots()
        }

        HealthDashboardSnapshotStore.save(filteredSnapshot)
    }

    private func clearWorkoutSnapshots(calendar: Calendar = .bodyGregorian) {
        let emptySnapshot = WorkoutMonthSnapshot.make(
            month: snapshot.month,
            year: snapshot.year,
            workouts: [],
            calendar: calendar
        )
        snapshot = emptySnapshot
        monthSnapshots = monthSnapshots.mapValues { monthSnapshot in
            WorkoutMonthSnapshot.make(
                month: monthSnapshot.month,
                year: monthSnapshot.year,
                workouts: [],
                calendar: calendar
            )
        }
        monthSnapshots[BodyWorkoutMonthKey(month: emptySnapshot.month, year: emptySnapshot.year)] = emptySnapshot
        loadedMonthKeys.removeAll()
        WidgetCenter.shared.reloadAllTimelines()
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
        guard !permissionSelection.enabledPermissions.isEmpty else {
            healthDataNotice = "All Apple Health data permissions are turned off in Settings."
            return
        }

        guard snapshot.workoutCount == 0, healthSummary.isEmpty, activityRingHistory.isEmpty else {
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
        .sortedByDate
    }

    private func requestAuthorization() async throws {
        let requestedTypes = Self.readObjectTypes(for: permissionSelection)
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

    nonisolated static func readObjectTypes(
        for selection: BodyHealthPermissionSelection = .defaultValue
    ) -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        if selection.includes(.activityRings) {
            types.insert(HKObjectType.activitySummaryType())
        }
        if selection.includes(.workouts) {
            types.insert(HKObjectType.workoutType())
            if let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) {
                types.insert(effortType)
            }
        }

        var quantityIdentifiers: [HKQuantityTypeIdentifier] = []
        if selection.includes(.heart) {
            quantityIdentifiers += [
                .restingHeartRate,
                .heartRate,
                .heartRateVariabilitySDNN
            ]
        }
        if selection.includes(.basics) {
            quantityIdentifiers += [
                .bodyMass,
                .bodyFatPercentage,
                .bodyMassIndex
            ]
        }
        if selection.includes(.respiratory) {
            quantityIdentifiers.append(.respiratoryRate)
        }
        if selection.includes(.bloodOxygen) {
            quantityIdentifiers.append(.oxygenSaturation)
        }
        if selection.includes(.energy) {
            quantityIdentifiers += [
                .activeEnergyBurned,
                .basalEnergyBurned
            ]
        }
        if selection.includes(.exerciseMinutes) {
            quantityIdentifiers.append(.appleExerciseTime)
        }
        if selection.includes(.wristTemperature) {
            quantityIdentifiers.append(.appleSleepingWristTemperature)
        }
        if selection.includes(.timeInDaylight) {
            quantityIdentifiers.append(.timeInDaylight)
        }
        if selection.includes(.steps) {
            quantityIdentifiers.append(.stepCount)
        }

        quantityIdentifiers
            .compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { types.insert($0) }

        if selection.includes(.sleep),
           let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        return types
    }

    private func fetchWorkouts(month: Int, year: Int, calendar: Calendar) async throws -> [WorkoutSummary] {
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

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)

        for workout in workouts {
            let heartRateSamples: [WorkoutHeartRateSample]
            if includesHeartRateSamples {
                heartRateSamples = await fetchIfPermitted(.heart, default: []) {
                    await fetchHeartRateSamples(for: workout)
                }
            } else {
                heartRateSamples = []
            }
            async let effortLevel = fetchSavedEffortLevel(for: workout)
            summaries.append(
                await Self.summary(
                    for: workout,
                    heartRateSamples: heartRateSamples,
                    effortLevel: effortLevel
                )
            )
        }

        return summaries
    }

    private func fetchHeartRateSamples(for workout: HKWorkout) async -> [WorkoutHeartRateSample] {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: [.strictStartDate]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let heartRateSamples = (samples as? [HKQuantitySample] ?? []).compactMap { sample -> WorkoutHeartRateSample? in
                    let beatsPerMinute = sample.quantity.doubleValue(for: heartRateUnit)
                    guard beatsPerMinute.isFinite, beatsPerMinute > 0 else {
                        return nil
                    }

                    return WorkoutHeartRateSample(
                        date: sample.startDate,
                        beatsPerMinute: beatsPerMinute
                    )
                }

                continuation.resume(returning: heartRateSamples)
            }

            healthStore.execute(query)
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

    private func fetchHealthSummary(calendar: Calendar) async -> HealthSummarySnapshot {
        async let activityRings = fetchIfPermitted(.activityRings, default: ActivityRingSummary.empty) {
            await fetchActivityRingSummary(calendar: calendar)
        }
        async let sleep: SleepSummary? = fetchIfPermitted(.sleep, default: nil) {
            await fetchSleepSummary(calendar: calendar)
        }
        async let heartRate: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await latestQuantity(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute())
            )
        }
        async let restingHeartRate: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await latestQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute())
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
                unit: .secondUnit(with: .milli)
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
                calendar: calendar
            )
        }
        async let restingEnergy: HealthMetricSummary? = fetchIfPermitted(.energy, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar
            )
        }
        async let exerciseMinutes: HealthMetricSummary? = fetchIfPermitted(.exerciseMinutes, default: nil) {
            await dailyCumulativeQuantitySummary(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar
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
                calendar: calendar
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

    private func fetchTrainingLoadSummary(calendar: Calendar) async -> HealthMetricSummary? {
        let date = Date()
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let interval = recentHealthTrendInterval(calendar: calendar, date: date)

        do {
            let workouts = try await fetchWorkoutSummaries(
                startDate: interval.start,
                endDate: dayEnd,
                includesHeartRateSamples: false
            )
            return TrainingLoadCalculator.summary(
                on: date,
                from: workouts,
                startDate: interval.start,
                calendar: calendar
            )
        } catch {
            return nil
        }
    }

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

    private func fetchActivityRingHistory(calendar: Calendar, date: Date = Date()) async -> ActivityRingHistorySnapshot {
        guard permissionSelection.includes(.activityRings) else {
            return .empty
        }

        let interval = activityRingHistoryInterval(calendar: calendar, date: date)
        let loadedMonthKeys = Self.recentActivityRingMonthKeys(
            count: Self.recentChartMonthCount,
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

    private func fetchActivityRingHistory(
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

    private func fetchHealthTrends(calendar: Calendar) async -> HealthTrendSnapshot {
        async let sleepHistory = fetchIfPermitted(.sleep, default: SleepHistorySnapshot.empty) {
            await fetchDailySleepHistory(calendar: calendar)
        }
        async let restingHeartRate = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar
            )
        }
        async let heartRate = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar
            )
        }
        async let heartRateRanges = fetchIfPermitted(.heart, default: HealthTrendRangeSeries.empty) {
            await fetchDailyQuantityRangeSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )
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
        async let heartRateVariability = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                aggregation: .average,
                calendar: calendar
            )
        }
        async let respiratoryRate = fetchIfPermitted(.respiratory, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar
            )
        }
        async let oxygenSaturation = fetchIfPermitted(.bloodOxygen, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .oxygenSaturation,
                unit: .percent(),
                aggregation: .average,
                calendar: calendar,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let restingHeartRateDaySamples = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchQuantitySampleSeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )
        }
        async let heartRateDaySamples = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchQuantitySampleSeries(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )
        }
        async let heartRateVariabilityDaySamples = fetchIfPermitted(.heart, default: HealthTrendSeries.empty) {
            await fetchQuantitySampleSeries(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                calendar: calendar
            )
        }
        async let respiratoryRateDaySamples = fetchIfPermitted(.respiratory, default: HealthTrendSeries.empty) {
            await fetchQuantitySampleSeries(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                calendar: calendar
            )
        }
        async let oxygenSaturationDaySamples = fetchIfPermitted(.bloodOxygen, default: HealthTrendSeries.empty) {
            await fetchQuantitySampleSeries(
                for: .oxygenSaturation,
                unit: .percent(),
                calendar: calendar,
                valueTransform: Self.normalizedPercentDisplayValue
            )
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
                calendar: calendar
            )
        }
        async let restingEnergy = fetchIfPermitted(.energy, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar
            )
        }
        async let exerciseMinutes = fetchIfPermitted(.exerciseMinutes, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar
            )
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
                calendar: calendar
            )
        }

        let fetchedSleepHistory = await sleepHistory
        return await HealthTrendSnapshot(
            sleep: fetchedSleepHistory.durationSeries,
            heartRate: heartRate,
            heartRateRanges: heartRateRanges,
            restingHeartRate: restingHeartRate,
            bodyMass: bodyMass,
            bodyFatPercentage: bodyFatPercentage,
            heartRateVariability: heartRateVariability,
            respiratoryRate: respiratoryRate,
            oxygenSaturation: oxygenSaturation,
            bodyMassIndex: bodyMassIndex,
            activeEnergy: activeEnergy,
            restingEnergy: restingEnergy,
            exerciseMinutes: exerciseMinutes,
            trainingLoad: trainingLoad,
            wristTemperature: wristTemperature,
            timeInDaylight: timeInDaylight,
            steps: steps,
            sleepHistory: fetchedSleepHistory,
            heartRateDaySamples: heartRateDaySamples,
            restingHeartRateDaySamples: restingHeartRateDaySamples,
            heartRateVariabilityDaySamples: heartRateVariabilityDaySamples,
            respiratoryRateDaySamples: respiratoryRateDaySamples,
            oxygenSaturationDaySamples: oxygenSaturationDaySamples
        )
    }

    private func fetchTrainingLoadSeries(calendar: Calendar) async -> HealthTrendSeries {
        let interval = recentHealthTrendInterval(calendar: calendar)

        do {
            let workouts = try await fetchWorkoutSummaries(
                startDate: interval.start,
                endDate: interval.end,
                includesHeartRateSamples: false
            )
            return TrainingLoadCalculator.dailySeries(
                from: workouts,
                startDate: interval.start,
                endDate: interval.end,
                calendar: calendar
            )
        } catch {
            return .empty
        }
    }

    private enum DailyQuantityAggregation {
        case average
        case latest
    }

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

    private func fetchDailyQuantitySeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let quantitySamples = samples as? [HKQuantitySample] ?? []
                let samplesByDay = Dictionary(grouping: quantitySamples) {
                    calendar.startOfDay(for: $0.endDate)
                }

                let points = samplesByDay.compactMap { day, daySamples -> HealthTrendDataPoint? in
                    guard let value = Self.dailyQuantityValue(
                        from: daySamples,
                        unit: unit,
                        aggregation: aggregation,
                        valueTransform: valueTransform
                    ) else {
                        return nil
                    }

                    return HealthTrendDataPoint(date: day, value: value)
                }
                .sorted { $0.date < $1.date }

                continuation.resume(returning: HealthTrendSeries(points: points))
            }

            healthStore.execute(query)
        }
    }

    private func fetchDailyQuantityRangeSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendRangeSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let quantitySamples = samples as? [HKQuantitySample] ?? []
                let samplesByDay = Dictionary(grouping: quantitySamples) {
                    calendar.startOfDay(for: $0.endDate)
                }

                let points = samplesByDay.compactMap { day, daySamples -> HealthTrendRangeDataPoint? in
                    guard let range = Self.dailyQuantityRangeValue(
                        from: daySamples,
                        unit: unit,
                        valueTransform: valueTransform
                    ) else {
                        return nil
                    }

                    return HealthTrendRangeDataPoint(
                        date: day,
                        lowValue: range.low,
                        highValue: range.high,
                        averageValue: range.average
                    )
                }
                .sorted { $0.date < $1.date }

                continuation.resume(returning: HealthTrendRangeSeries(points: points))
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
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
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
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        let series = await fetchDailyQuantitySeries(
            for: identifier,
            unit: unit,
            aggregation: aggregation,
            calendar: calendar,
            valueTransform: valueTransform
        )

        guard let latestPoint = series.points.last else {
            return nil
        }

        return HealthMetricSummary(value: latestPoint.value)
    }

    private func fetchQuantitySampleSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
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

    private func fetchSleepVitals(startDate: Date, endDate: Date) async -> SleepVitalsSummary {
        async let heartRate: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await sleepQuantitySummary(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average
            )
        }
        async let heartRateVariability: HealthMetricSummary? = fetchIfPermitted(.heart, default: nil) {
            await sleepQuantitySummary(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                startDate: startDate,
                endDate: endDate,
                aggregation: .average
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

    private func fetchDailyCumulativeQuantitySeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendSeries {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
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

    private func dailyCumulativeQuantitySummary(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthMetricSummary? {
        let series = await fetchDailyCumulativeQuantitySeries(
            for: identifier,
            unit: unit,
            calendar: calendar,
            valueTransform: valueTransform
        )

        guard let latestPoint = series.points.last else {
            return nil
        }

        return HealthMetricSummary(value: latestPoint.value)
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
        guard permissionSelection.includes(.sleep) else {
            return nil
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -14, to: endDate) ?? endDate.addingTimeInterval(-1_209_600)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
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

    private func fetchDailySleepHistory(calendar: Calendar) async -> SleepHistorySnapshot {
        guard permissionSelection.includes(.sleep) else {
            return .empty
        }

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return .empty
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
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

        var hydratedDays: [SleepDaySummary] = []
        for var day in days {
            if let interval = day.summary.stageSnapshot.dateInterval {
                day.summary.vitals = await fetchSleepVitals(
                    startDate: interval.start,
                    endDate: interval.end
                )
            }
            hydratedDays.append(day)
        }

        return SleepHistorySnapshot(days: hydratedDays)
    }

    private func recentHealthTrendInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
        let end = date
        let currentDayStart = calendar.startOfDay(for: date)
        let oldestPastOffset = BodyHealthTrendRange.maximumDayCount - 1
        let start = calendar.date(byAdding: .day, value: -oldestPastOffset, to: currentDayStart)
            ?? end.addingTimeInterval(-TimeInterval(oldestPastOffset) * 86_400)
        return (start, end)
    }

    private func activityRingHistoryInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
        let currentDayStart = calendar.startOfDay(for: date)
        let currentMonthStart = calendar.dateInterval(of: .month, for: currentDayStart)?.start ?? currentDayStart
        let start = calendar.date(byAdding: .month, value: -(Self.recentChartMonthCount - 1), to: currentMonthStart)
            ?? currentMonthStart
        return (start, currentDayStart)
    }

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

    nonisolated private static func normalizedPercentDisplayValue(_ value: Double) -> Double {
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

    nonisolated private static func dailyQuantityRangeValue(
        from samples: [HKQuantitySample],
        unit: HKUnit,
        valueTransform: (Double) -> Double
    ) -> (low: Double, high: Double, average: Double)? {
        let values = samples
            .map { valueTransform($0.quantity.doubleValue(for: unit)) }
            .filter(\.isFinite)

        guard let low = values.min(), let high = values.max() else {
            return nil
        }

        let average = values.reduce(0, +) / Double(values.count)
        return (low, high, average)
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

    nonisolated static func sleepDuration(from samples: [HKCategorySample]) -> TimeInterval {
        mergedSleepDuration(
            intervals: samples
                .filter(Self.isAsleep)
                .map { ($0.startDate, $0.endDate) }
        )
    }

    nonisolated private static func sleepSummary(from samples: [HKCategorySample], date: Date) -> SleepSummary? {
        let duration = sleepDuration(from: samples)
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

    nonisolated private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
        }
    }

    nonisolated private static func isSleepTimelineSample(_ sample: HKCategorySample) -> Bool {
        isAsleep(sample) || sleepStage(for: sample, includeUnspecified: false) == .awake
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
            type: workoutType(for: workout.workoutActivityType),
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

private extension Set where Element == ActivityRingMonthKey {
    var sortedByDate: [ActivityRingMonthKey] {
        Array(self).sortedByDate
    }
}

private extension Array where Element == ActivityRingMonthKey {
    var sortedByDate: [ActivityRingMonthKey] {
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
