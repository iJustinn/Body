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

struct BodyHealthCacheStatus: Equatable {
    let hasHealthDashboardData: Bool
    let workoutMonthCount: Int
    let workoutCount: Int
    let activityRingMonthCount: Int
    let diskSizeBytes: Int64

    var isEmpty: Bool {
        !hasHealthDashboardData && workoutMonthCount == 0 && activityRingMonthCount == 0
    }

    var summaryText: String {
        isEmpty ? "Empty" : "Cached"
    }

    var detailLines: [String] {
        [
            hasHealthDashboardData
                ? "Health summary, trend, or Activity Ring data is available in the local dashboard cache."
                : "Health dashboard cache is empty.",
            "\(workoutMonthCount) workout \(monthWord(for: workoutMonthCount)) cached with \(workoutCount) \(workoutWord(for: workoutCount)).",
            "\(activityRingMonthCount) Activity Ring \(monthWord(for: activityRingMonthCount)) cached.",
            "On-disk size: \(formattedDiskSize)."
        ]
    }

    var formattedDiskSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: diskSizeBytes)
    }

    private func monthWord(for count: Int) -> String {
        count == 1 ? "month" : "months"
    }

    private func workoutWord(for count: Int) -> String {
        count == 1 ? "workout" : "workouts"
    }
}

@MainActor
final class HealthKitWorkoutStore: ObservableObject {
    nonisolated static let recentChartMonthCount = 3

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
    @Published private(set) var healthDataSourceSelection: BodyHealthDataSourceSelection
    @Published private(set) var secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection
    @Published private(set) var healthDataSourceOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
    @Published private(set) var healthDataNotice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSuccessfulRefreshDate: Date?
    @Published private(set) var loadingMonthKeys: Set<BodyWorkoutMonthKey> = []
    @Published private(set) var loadingActivityRingMonthKeys: Set<ActivityRingMonthKey> = []

    private let engine: HealthKitFetchEngine
    private var loadedMonthKeys: Set<BodyWorkoutMonthKey> = []
    private var loadedActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    private var lastAppEntrySyncDate: Date?
    private var refreshCompletionContinuations: [CheckedContinuation<Void, Never>] = []

    private func finishRefresh() {
        isRefreshing = false
        let toResume = refreshCompletionContinuations
        refreshCompletionContinuations.removeAll()
        for continuation in toResume {
            continuation.resume()
        }
    }

    private func awaitNextRefreshCompletion() async {
        guard isRefreshing, !Task.isCancelled else {
            return
        }
        await withCheckedContinuation { continuation in
            refreshCompletionContinuations.append(continuation)
        }
    }

    init(
        initialSnapshot: WorkoutMonthSnapshot = WorkoutSnapshotStore.loadOrPlaceholder(),
        initialHealthDashboardSnapshot: HealthDashboardSnapshot = HealthDashboardSnapshotStore.loadOrEmpty(),
        initialPermissionSelection: BodyHealthPermissionSelection = BodyHealthPermissionSelection.load(),
        initialHealthDataSourceSelection: BodyHealthDataSourceSelection = BodyHealthDataSourceSelection.load(),
        initialSecondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection = BodyHealthSecondaryDataSourceSelection.load(),
        date: Date = Date()
    ) {
        permissionSelection = initialPermissionSelection
        healthDataSourceSelection = initialHealthDataSourceSelection
        secondaryHealthDataSourceSelection = initialSecondaryHealthDataSourceSelection
        engine = HealthKitFetchEngine(
            permission: initialPermissionSelection,
            healthDataSourceSelection: initialHealthDataSourceSelection,
            secondaryHealthDataSourceSelection: initialSecondaryHealthDataSourceSelection
        )
        // Skip the recovery recompute at init — it's a per-day iteration over
        // up to ~365 trend points that would block the first frame. The cached
        // `summary.recovery` value was correct when written; the next refresh
        // recomputes it off the main thread.
        let filteredHealthDashboardSnapshot = initialHealthDashboardSnapshot.filteredWithoutRecoveryRecompute(by: initialPermissionSelection)
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
        let storedSecondarySignature = HealthDashboardSnapshotStore.loadSecondarySelectionSignature()
        if storedSecondarySignature != initialSecondaryHealthDataSourceSelection.signature {
            healthTrends = filteredHealthDashboardSnapshot.trends.clearingSecondarySeries()
        } else {
            healthTrends = filteredHealthDashboardSnapshot.trends
        }
        activityRingHistory = filteredHealthDashboardSnapshot.activityRingHistory.removingLikelyBoundaryTruncatedLoadedMonths(
            date: date,
            calendar: .bodyGregorian
        )
        loadedActivityRingMonthKeys = Set(activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))
    }

    var healthSyncStatusSummaryText: String {
        if isRefreshing {
            return "Refreshing"
        }

        switch authorizationState {
        case .unknown:
            return lastSuccessfulRefreshDate == nil ? "Not Synced" : healthSyncStatusLastRefreshText
        case .unavailable:
            return "Unavailable"
        case .authorized:
            return healthSyncStatusLastRefreshText
        case .denied:
            return "Denied"
        case .failed:
            return "Failed"
        }
    }

    var healthSyncStatusLastRefreshText: String {
        guard let date = lastSuccessfulRefreshDate else {
            return "Not yet refreshed"
        }

        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    var healthSyncStatusDetailText: String {
        if isRefreshing {
            return "Body is refreshing Apple Health data now."
        }

        switch authorizationState {
        case .unknown:
            return lastSuccessfulRefreshDate == nil
                ? "Body has not completed a HealthKit refresh in this app session."
                : "Body has cached Health data from a previous refresh."
        case .unavailable:
            return "Apple Health is not available on this device."
        case .authorized:
            return "Body can read the Health data permissions enabled below."
        case .denied:
            return "Health access was denied. Review Body's permissions in Apple Health or iOS Settings."
        case .failed(let message):
            return "The last refresh failed: \(message)"
        }
    }

    var cacheStatus: BodyHealthCacheStatus {
        let workoutSnapshotsWithData = monthSnapshots.values.filter { $0.workoutCount > 0 }
        let dashboardSnapshot = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )

        return BodyHealthCacheStatus(
            hasHealthDashboardData: !dashboardSnapshot.isEmpty,
            workoutMonthCount: workoutSnapshotsWithData.count,
            workoutCount: workoutSnapshotsWithData.reduce(0) { $0 + $1.workoutCount },
            activityRingMonthCount: loadedActivityRingMonthKeys.count,
            diskSizeBytes: WorkoutSnapshotStore.totalDiskSizeBytes + HealthDashboardSnapshotStore.totalDiskSizeBytes
        )
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
            try await engine.requestAuthorization()
            await refreshRecentMonths()
        } catch {
            handleRefreshError(error)
        }
    }

    func refreshHealthMetric(_ kind: HealthMetricKind, date: Date = Date()) async {
        guard !isRefreshing else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        isRefreshing = true
        await engine.setHealthTrendAnchorDate(date)
        defer { finishRefresh() }

        let calendar = Calendar.bodyGregorian

        do {
            try await engine.requestAuthorization()
            await fetchHealthDataSourceOptions(calendar: calendar)
            let existing = HealthDashboardSnapshot(
                summary: healthSummary,
                trends: healthTrends,
                activityRingHistory: activityRingHistory
            )
            let metricSnapshot = await engine.fetchHealthDashboardSnapshot(for: kind, calendar: calendar, existing: existing)
            let nextSummary = healthSummary.replacingMetric(kind, with: metricSnapshot.summary)
            let nextTrends = healthTrends.replacingMetric(kind, with: metricSnapshot.trends)
            await updateHealthDashboardSnapshot(
                summary: nextSummary,
                trends: nextTrends,
                activityRingHistory: activityRingHistory
            )
            authorizationState = .authorized
            markRefreshSucceeded(date: date)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
        await engine.setHealthTrendAnchorDate(nil)
    }

    /// Lazy-loads the intraday day-sample series used by the metric detail view's
    /// hourly chart. These are not displayed on the Home dashboard and are skipped
    /// by `fetchHealthTrends`; we fetch them on demand when the user navigates into
    /// a metric detail. Safe to call multiple times.
    ///
    /// The fetch is incremental: we look at the most recent cached point and
    /// only ask HealthKit for samples newer than that, then merge with the
    /// existing cache (trimmed to the trailing trend window). On a first-ever
    /// load the cache is empty and we fetch the full window.
    func loadIntradayMetricSamplesIfNeeded(_ kind: HealthMetricKind) async {
        switch kind {
        case .heartRate, .restingHeartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation:
            break
        default:
            return
        }

        await awaitNextRefreshCompletion()
        guard !Task.isCancelled else {
            return
        }

        let permission = HealthKitFetchEngine.healthPermission(forMetric: kind)
        guard permissionSelection.includes(permission) else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            return
        }

        do {
            try await engine.requestAuthorization()
        } catch {
            return
        }

        let calendar = Calendar.bodyGregorian
        let interval = HealthKitFetchEngine.recentHealthTrendInterval(calendar: calendar, anchor: nil)
        let cachedPrimary = healthTrends.daySeries(for: kind)
        let cachedSecondary = healthTrends.secondaryDaySeries(for: kind)

        let primaryFetchStart = HealthKitFetchEngine.incrementalFetchStart(after: cachedPrimary, windowStart: interval.start)
        let secondaryFetchStart = HealthKitFetchEngine.incrementalFetchStart(after: cachedSecondary, windowStart: interval.start)

        // Cache already extends to the window end — nothing to add.
        if primaryFetchStart >= interval.end, secondaryFetchStart >= interval.end {
            return
        }

        let primarySamples = await engine.fetchIntradayDaySamples(
            for: kind,
            calendar: calendar,
            startDate: primaryFetchStart,
            endDate: interval.end
        )
        let secondarySamples: HealthTrendSeries
        if secondaryHealthDataSourceSelection.option(for: kind).isNoComparison
            || !permissionSelection.includes(permission) {
            secondarySamples = .empty
        } else {
            secondarySamples = await engine.fetchSecondaryDaySamples(
                for: kind,
                calendar: calendar,
                startDate: secondaryFetchStart,
                endDate: interval.end
            )
        }

        let mergedPrimary = HealthKitFetchEngine.mergeIntradaySamples(
            existing: cachedPrimary,
            incoming: primarySamples,
            windowStart: interval.start
        )
        let mergedSecondary = HealthKitFetchEngine.mergeIntradaySamples(
            existing: cachedSecondary,
            incoming: secondarySamples,
            windowStart: interval.start
        )

        var trends = healthTrends
        switch kind {
        case .heartRate:
            trends.heartRateDaySamples = mergedPrimary
            trends.heartRateDaySamplesSecondary = mergedSecondary
        case .restingHeartRate:
            trends.restingHeartRateDaySamples = mergedPrimary
            trends.restingHeartRateDaySamplesSecondary = mergedSecondary
        case .heartRateVariability:
            trends.heartRateVariabilityDaySamples = mergedPrimary
            trends.heartRateVariabilityDaySamplesSecondary = mergedSecondary
        case .respiratoryRate:
            trends.respiratoryRateDaySamples = mergedPrimary
        case .oxygenSaturation:
            trends.oxygenSaturationDaySamples = mergedPrimary
            trends.oxygenSaturationDaySamplesSecondary = mergedSecondary
        default:
            return
        }
        healthTrends = trends
    }

    func refreshWorkoutMonth(month: Int, year: Int) async {
        guard !isRefreshing else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        let calendar = Calendar.bodyGregorian

        do {
            try await engine.requestAuthorization()
            await refresh(month: month, year: year, calendar: calendar, updatesHealthSummary: false)
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
        await engine.setPermissionSelection(nextSelection)
        await applyPermissionSelectionToCachedData()

        if isEnabled {
            await requestAuthorizationAndRefresh()
        } else {
            updateHealthDataNotice()
        }
    }

    func healthDataSourceOptions(for kind: HealthMetricKind) -> [BodyHealthDataSourceOption] {
        guard kind.supportsHealthDataSourceSelection else {
            return []
        }

        return [BodyHealthDataSourceOption.allSources] + (healthDataSourceOptionsByKind[kind] ?? [])
    }

    func secondaryHealthDataSourceOptions(for kind: HealthMetricKind) -> [BodyHealthDataSourceOption] {
        guard kind.supportsSecondaryHealthDataSourceSelection else {
            return []
        }

        let primaryOption = selectedHealthDataSourceOption(for: kind)
        let candidates = [BodyHealthDataSourceOption.allSources] + (healthDataSourceOptionsByKind[kind] ?? [])
        let filtered = candidates.filter { $0.id != primaryOption.id }
        return [BodyHealthDataSourceOption.noComparison] + filtered
    }

    func selectedHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        healthDataSourceSelection.option(for: kind)
    }

    func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        secondaryHealthDataSourceSelection.option(for: kind)
    }

    func updateHealthDataSource(for kind: HealthMetricKind, option: BodyHealthDataSourceOption) async {
        let nextSelection = healthDataSourceSelection.setting(kind, option: option)
        guard nextSelection != healthDataSourceSelection else {
            return
        }

        healthDataSourceSelection = nextSelection
        nextSelection.save()
        await engine.setHealthDataSourceSelection(nextSelection)
        await requestAuthorizationAndRefresh()
    }

    func updateSecondaryHealthDataSource(for kind: HealthMetricKind, option: BodyHealthDataSourceOption) async {
        let nextSelection = secondaryHealthDataSourceSelection.setting(kind, option: option)
        guard nextSelection != secondaryHealthDataSourceSelection else {
            return
        }

        secondaryHealthDataSourceSelection = nextSelection
        nextSelection.save()
        await engine.setSecondaryHealthDataSourceSelection(nextSelection)

        await awaitNextRefreshCompletion()

        guard !Task.isCancelled else {
            return
        }

        await refreshHealthMetric(kind)
    }

    func sourceComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceComparisonTrend? {
        guard kind.usesSourceComparisonBarChart else {
            return nil
        }

        return makeSourceComparisonTrend(
            for: kind,
            primarySeries: healthTrends.series(for: kind),
            secondarySeries: healthTrends.secondarySeries(for: kind)
        )
    }

    func sourceRangeComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceRangeComparisonTrend? {
        guard kind.usesSourceComparisonRangeChart else {
            return nil
        }

        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return nil
        }

        return BodyHealthSourceRangeComparisonTrend(
            primary: BodyHealthSourceRangeTrend(
                role: .primary,
                sourceName: selectedHealthDataSourceOption(for: kind).name,
                series: healthTrends.rangeSeries(for: kind)
            ),
            secondary: BodyHealthSourceRangeTrend(
                role: .secondary,
                sourceName: secondaryOption.name,
                series: healthTrends.secondaryRangeSeries(for: kind)
            )
        )
    }

    func sourceLineComparisonTrend(for kind: HealthMetricKind) -> BodyHealthSourceComparisonTrend? {
        guard kind.usesSourceComparisonLineChart else {
            return nil
        }

        return makeSourceComparisonTrend(
            for: kind,
            primarySeries: healthTrends.series(for: kind),
            secondarySeries: healthTrends.secondarySeries(for: kind)
        )
    }

    private func makeSourceComparisonTrend(
        for kind: HealthMetricKind,
        primarySeries: HealthTrendSeries,
        secondarySeries: HealthTrendSeries
    ) -> BodyHealthSourceComparisonTrend? {
        let secondaryOption = selectedSecondaryHealthDataSourceOption(for: kind)
        guard !secondaryOption.isNoComparison else {
            return nil
        }

        return BodyHealthSourceComparisonTrend(
            primary: BodyHealthSourceTrend(
                role: .primary,
                sourceName: selectedHealthDataSourceOption(for: kind).name,
                series: primarySeries
            ),
            secondary: BodyHealthSourceTrend(
                role: .secondary,
                sourceName: secondaryOption.name,
                series: secondarySeries
            )
        )
    }

    func awaitRefreshCompletion(minimumDurationFrom start: Date? = nil) async {
        await awaitNextRefreshCompletion()

        guard let start, !Task.isCancelled else {
            return
        }

        let minimumSeconds: TimeInterval = 0.6
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimumSeconds {
            let remaining = UInt64((minimumSeconds - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: remaining)
        }
    }

    func syncWhenAppBecomesActive(date: Date = Date()) async {
        guard !isRefreshing else {
            return
        }

        if let lastAppEntrySyncDate, date.timeIntervalSince(lastAppEntrySyncDate) < Self.shortResumeDebounceInterval {
            return
        }

        lastAppEntrySyncDate = date

        if let lastSuccessfulRefreshDate,
           date.timeIntervalSince(lastSuccessfulRefreshDate) < Self.dashboardFreshnessInterval,
           permissionSelection.includes(.workouts) {
            let calendar = Calendar.bodyGregorian
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            await refreshWorkoutMonth(month: month, year: year)
            return
        }

        await requestAuthorizationAndRefresh()
    }

    private static let shortResumeDebounceInterval: TimeInterval = 60
    private static let dashboardFreshnessInterval: TimeInterval = 300

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

        await awaitNextRefreshCompletion()

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
        await awaitNextRefreshCompletion()

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
            try await engine.requestAuthorization()
            let previousHistory = await engine.fetchActivityRingHistory(monthKey: previousMonthKey, calendar: calendar)
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
            markRefreshSucceeded(date: Date())
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

    func clearLocalCache(date: Date = Date()) {
        let calendar = Calendar.bodyGregorian
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let key = BodyWorkoutMonthKey(month: month, year: year)
        let emptySnapshot = WorkoutMonthSnapshot.make(
            month: month,
            year: year,
            workouts: [],
            calendar: calendar
        )

        snapshot = emptySnapshot
        monthSnapshots = [key: emptySnapshot]
        healthSummary = .empty
        healthTrends = .empty
        activityRingHistory = .empty
        loadedMonthKeys.removeAll()
        loadedActivityRingMonthKeys.removeAll()
        loadingMonthKeys.removeAll()
        loadingActivityRingMonthKeys.removeAll()
        healthDataSourceOptionsByKind = [:]
        Task { [engine] in await engine.clearSourceCache() }
        lastSuccessfulRefreshDate = nil
        authorizationState = .unknown
        healthDataNotice = "Local cache cleared. Refresh to load Apple Health data again."

        WorkoutSnapshotStore.delete()
        WorkoutSnapshotStore.deletePrevious()
        HealthDashboardSnapshotStore.delete()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshRecentMonths(date: Date = Date()) async {
        isRefreshing = true
        await engine.setHealthTrendAnchorDate(date)
        defer { finishRefresh() }

        let calendar = Calendar.bodyGregorian
        let keys = Self.recentMonthKeys(count: Self.recentChartMonthCount, from: date, calendar: calendar)

        do {
            if permissionSelection.includes(.workouts) {
                try await refresh(monthKeys: keys, calendar: calendar)
            } else {
                clearWorkoutSnapshots(calendar: calendar)
            }
            await fetchHealthDataSourceOptions(calendar: calendar)
            let cachedTrends = healthTrends
            async let nextHealthSummary = engine.fetchHealthSummary(calendar: calendar)
            async let nextHealthTrends = engine.fetchHealthTrends(calendar: calendar, cachedTrends: cachedTrends)
            async let nextActivityRingHistory = engine.fetchActivityRingHistory(calendar: calendar)
            let fetchedHealthSummary = await nextHealthSummary
            let fetchedHealthTrends = await nextHealthTrends
            let fetchedActivityRingHistory = await nextActivityRingHistory
            await updateHealthDashboardSnapshot(
                summary: fetchedHealthSummary,
                trends: fetchedHealthTrends,
                activityRingHistory: fetchedActivityRingHistory
            )
            authorizationState = .authorized
            markRefreshSucceeded(date: date)
            updateCurrentMonthSnapshot(date: date, calendar: calendar)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
        await engine.setHealthTrendAnchorDate(nil)
    }

    private func refresh(month: Int, year: Int, calendar: Calendar, updatesHealthSummary: Bool) async {
        isRefreshing = true
        let refreshDate = Date()
        if updatesHealthSummary {
            await engine.setHealthTrendAnchorDate(refreshDate)
        }
        defer { finishRefresh() }

        let key = BodyWorkoutMonthKey(month: month, year: year)

        do {
            if permissionSelection.includes(.workouts) {
                try await refresh(monthKeys: [key], calendar: calendar)
            } else {
                clearWorkoutSnapshots(calendar: calendar)
            }
            if updatesHealthSummary {
                await fetchHealthDataSourceOptions(calendar: calendar)
                let cachedTrends = healthTrends
                async let nextHealthSummary = engine.fetchHealthSummary(calendar: calendar)
                async let nextHealthTrends = engine.fetchHealthTrends(calendar: calendar, cachedTrends: cachedTrends)
                async let nextActivityRingHistory = engine.fetchActivityRingHistory(calendar: calendar)
                let fetchedHealthSummary = await nextHealthSummary
                let fetchedHealthTrends = await nextHealthTrends
                let fetchedActivityRingHistory = await nextActivityRingHistory
                await updateHealthDashboardSnapshot(
                    summary: fetchedHealthSummary,
                    trends: fetchedHealthTrends,
                    activityRingHistory: fetchedActivityRingHistory
                )
            }
            authorizationState = .authorized
            markRefreshSucceeded(date: refreshDate)
            updateCurrentMonthSnapshot(date: refreshDate, calendar: calendar)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
        if updatesHealthSummary {
            await engine.setHealthTrendAnchorDate(nil)
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
            try await engine.requestAuthorization()
            try await refresh(monthKeys: keysToLoad, calendar: .bodyGregorian)
            authorizationState = .authorized
            markRefreshSucceeded(date: Date())
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
    }

    private func refresh(monthKeys: Set<BodyWorkoutMonthKey>, calendar: Calendar) async throws {
        let orderedKeys = monthKeys.sortedByDate
        guard !orderedKeys.isEmpty else {
            return
        }

        let engine = self.engine
        let results = try await withThrowingTaskGroup(
            of: (BodyWorkoutMonthKey, [WorkoutSummary]).self
        ) { group -> [BodyWorkoutMonthKey: [WorkoutSummary]] in
            for key in orderedKeys {
                group.addTask {
                    let workouts = try await engine.fetchWorkouts(month: key.month, year: key.year, calendar: calendar)
                    return (key, workouts)
                }
            }

            var fetched: [BodyWorkoutMonthKey: [WorkoutSummary]] = [:]
            for try await (key, workouts) in group {
                fetched[key] = workouts
            }
            return fetched
        }

        for key in orderedKeys {
            let workouts = results[key] ?? []
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
    ) async {
        let calendar = Calendar.bodyGregorian
        let anchorDate = await engine.healthTrendAnchorDate ?? Date()
        let permissionSelection = self.permissionSelection
        let rawSnapshot = HealthDashboardSnapshot(
            summary: summary,
            trends: trends,
            activityRingHistory: activityRingHistory
        )

        // Filter + recovery recompute are the heaviest per-refresh CPU spike
        // (the recovery `dailySeries` iterates up to ~365 days × multi-metric
        // baselines). Run them off the main actor.
        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            rawSnapshot
                .filtered(by: permissionSelection)
                .recalculatingRecovery(on: anchorDate, calendar: calendar)
        }.value

        let nextActivityRingHistory = self.activityRingHistory.replacingLoadedMonths(
            with: filteredSnapshot.activityRingHistory,
            calendar: calendar
        )
        healthSummary = filteredSnapshot.summary
        healthTrends = filteredSnapshot.trends
        self.activityRingHistory = nextActivityRingHistory
        loadedActivityRingMonthKeys = Set(nextActivityRingHistory.loadedMonthKeySet(calendar: calendar))

        let snapshotToSave = HealthDashboardSnapshot(
            summary: filteredSnapshot.summary,
            trends: filteredSnapshot.trends,
            activityRingHistory: nextActivityRingHistory
        )
        let secondarySignature = secondaryHealthDataSourceSelection.signature
        Task.detached(priority: .utility) {
            HealthDashboardSnapshotStore.save(snapshotToSave)
            HealthDashboardSnapshotStore.saveSecondarySelectionSignature(secondarySignature)
        }
    }

    private func markRefreshSucceeded(date: Date) {
        lastSuccessfulRefreshDate = date
    }

    private func applyPermissionSelectionToCachedData() async {
        let rawSnapshot = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let permissionSelection = self.permissionSelection

        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            rawSnapshot.filtered(by: permissionSelection)
        }.value

        healthSummary = filteredSnapshot.summary
        healthTrends = filteredSnapshot.trends
        activityRingHistory = filteredSnapshot.activityRingHistory
        loadedActivityRingMonthKeys = Set(filteredSnapshot.activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))

        if !permissionSelection.includes(.workouts) {
            clearWorkoutSnapshots()
        }

        Task.detached(priority: .utility) {
            HealthDashboardSnapshotStore.save(filteredSnapshot)
        }
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
        let snapshotToSave = currentSnapshot
        let previousSnapshotToSave: WorkoutMonthSnapshot? = {
            guard let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: date) else {
                return nil
            }
            let previousKey = BodyWorkoutMonthKey(date: previousMonthStart, calendar: calendar)
            return monthSnapshots[previousKey]
        }()

        Task.detached(priority: .utility) {
            var widgetReloadNeeded = WorkoutSnapshotStore.save(snapshotToSave)
            if let previousSnapshotToSave,
               WorkoutSnapshotStore.savePrevious(previousSnapshotToSave) {
                widgetReloadNeeded = true
            }
            if widgetReloadNeeded {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
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


    private func fetchHealthDataSourceOptions(calendar: Calendar) async {
        if let nextOptionsByKind = await engine.fetchHealthDataSourceOptions(calendar: calendar) {
            healthDataSourceOptionsByKind = nextOptionsByKind
        }
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

    nonisolated private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleep, .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        default:
            return false
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

enum HealthKitWorkoutError: LocalizedError {
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
