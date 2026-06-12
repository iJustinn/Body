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
    @Published private(set) var combinesHealthDataSourcesByName: Bool
    @Published private(set) var healthDataSourceOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
    @Published private(set) var healthDataNotice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSuccessfulRefreshDate: Date?
    @Published private(set) var loadingMonthKeys: Set<BodyWorkoutMonthKey> = []
    @Published private(set) var loadingActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    @Published private(set) var hasMoreActivityRingHistory = true

    /// Disk size of the three snapshot caches, refreshed off the main thread
    /// (`refreshCacheDiskSize`). `cacheStatus` reads this instead of running
    /// per-render `FileManager` stat calls on the main thread.
    @Published private(set) var cacheDiskSizeBytes: Int64 = 0

    /// Months beyond this cap are evicted (least recently loaded first) so
    /// browsing years of history doesn't accumulate every month's workouts
    /// (with up to 96 heart-rate samples each) in memory for the app's
    /// lifetime. The current chart window and the displayed month never
    /// evict.
    nonisolated static let maximumCachedMonthSnapshots = 12

    private let engine: HealthKitFetchEngine
    private var loadedMonthKeys: Set<BodyWorkoutMonthKey> = []
    private var monthLoadOrder: [BodyWorkoutMonthKey] = []
    private var loadedActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    /// Months probed for older ring history that came back with no data.
    /// Session-only: never refetched this session, never persisted; cleared
    /// whenever a refresh applies fresh dashboard ring history.
    private var exhaustedActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    private var lastAppEntrySyncDate: Date?
    private var refreshCompletionContinuations: [CheckedContinuation<Void, Never>] = []
    private var monthLoadContinuations: [BodyWorkoutMonthKey: [CheckedContinuation<Void, Never>]] = [:]
    private var persistedDaySamplesHydration: Task<HealthTrendDaySampleSnapshot?, Never>?

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

    /// Drains the per-month continuation list for each key after the in-flight
    /// `loadMonthKeysIfNeeded` releases the `loadingMonthKeys` lock. Callers
    /// that registered via `awaitMonthLoadCompletion(for:)` resume here.
    private func finishMonthLoad(for keys: Set<BodyWorkoutMonthKey>) {
        for key in keys {
            guard let toResume = monthLoadContinuations.removeValue(forKey: key) else {
                continue
            }
            for continuation in toResume {
                continuation.resume()
            }
        }
    }

    private func awaitMonthLoadCompletion(for key: BodyWorkoutMonthKey) async {
        guard loadingMonthKeys.contains(key), !Task.isCancelled else {
            return
        }
        await withCheckedContinuation { continuation in
            monthLoadContinuations[key, default: []].append(continuation)
        }
    }

    init(
        initialSnapshot: WorkoutMonthSnapshot = WorkoutSnapshotStore.loadOrSeedPlaceholder(),
        initialHealthDashboardSnapshot: HealthDashboardSnapshot = HealthDashboardSnapshotStore.loadOrEmpty(),
        initialPermissionSelection: BodyHealthPermissionSelection = BodyHealthPermissionSelection.load(),
        initialHealthDataSourceSelection: BodyHealthDataSourceSelection = BodyHealthDataSourceSelection.load(),
        initialSecondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection = BodyHealthSecondaryDataSourceSelection.load(),
        initialCombinesHealthDataSourcesByName: Bool = UserDefaults.standard.bool(forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey),
        date: Date = Date()
    ) {
        permissionSelection = initialPermissionSelection
        healthDataSourceSelection = initialHealthDataSourceSelection
        secondaryHealthDataSourceSelection = initialSecondaryHealthDataSourceSelection
        combinesHealthDataSourcesByName = initialCombinesHealthDataSourcesByName
        engine = HealthKitFetchEngine(
            permission: initialPermissionSelection,
            healthDataSourceSelection: initialHealthDataSourceSelection,
            secondaryHealthDataSourceSelection: initialSecondaryHealthDataSourceSelection,
            combinesHealthDataSourcesByName: initialCombinesHealthDataSourcesByName
        )
        // Skip the readiness recompute at init — it's a per-day iteration over
        // up to ~365 trend points that would block the first frame. The cached
        // `summary.readiness` value was correct when written; the next refresh
        // recomputes it off the main thread.
        let filteredHealthDashboardSnapshot = initialHealthDashboardSnapshot.filteredWithoutReadinessRecompute(by: initialPermissionSelection)
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
        activityRingHistory = filteredHealthDashboardSnapshot.activityRingHistory
            .removingLikelyBoundaryTruncatedLoadedMonths(
                date: date,
                calendar: .bodyGregorian
            )
            .removingLoadedMonthsOlderThanEarliestData(
                date: date,
                calendar: .bodyGregorian,
                keepingRecentMonthCount: Self.recentChartMonthCount
            )
        loadedActivityRingMonthKeys = Set(activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))
        // Restore the persisted last-successful-refresh timestamp so the
        // cold-start sync path applies the same tiered TTL as a warm resume.
        lastSuccessfulRefreshDate = HealthDashboardSnapshotStore.loadLastSuccessfulRefreshDate()
        Task { await self.refreshCacheDiskSize() }
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
            diskSizeBytes: cacheDiskSizeBytes
        )
    }

    /// Re-stats the snapshot cache files off the main thread and publishes
    /// the total for the Settings cache row. Called after launch and after
    /// each detached snapshot save.
    func refreshCacheDiskSize() async {
        let size = await Task.detached(priority: .utility) {
            WorkoutSnapshotStore.totalDiskSizeBytes
                + HealthDashboardSnapshotStore.totalDiskSizeBytes
                + HealthWidgetSnapshotStore.totalDiskSizeBytes
        }.value
        cacheDiskSizeBytes = size
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

        // Claim the refresh slot before the first suspension — otherwise a
        // second entry point arriving during the authorization round-trip
        // passes the `isRefreshing` guard and starts a concurrent refresh.
        isRefreshing = true
        defer { finishRefresh() }

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
        await hydratePersistedDaySamplesIfNeeded()
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
            let metricSnapshot = await engine.fetchHealthDashboardSnapshot(
                for: kind,
                calendar: calendar,
                existing: existing,
                idealSleepDuration: Self.storedIdealSleepDuration()
            )
            let nextSummary = healthSummary.replacingMetric(kind, with: metricSnapshot.summary)
            let nextTrends = healthTrends.replacingMetric(kind, with: metricSnapshot.trends)
            await updateHealthDashboardSnapshot(
                summary: nextSummary,
                trends: nextTrends,
                activityRingHistory: activityRingHistory,
                recomputesReadiness: Self.readinessInputMetricKinds.contains(kind)
            )
            authorizationState = .authorized
            markRefreshSucceeded(date: date)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
        await engine.setHealthTrendAnchorDate(nil)
    }

    /// Loads the intraday day-sample sidecar (split out of the launch-critical
    /// snapshot decode) off the main actor and merges it into any still-empty
    /// `*DaySamples` fields. Refresh and lazy-load entry points await this
    /// first so a snapshot save can never overwrite the sidecar with empty
    /// series before it has been read, and so the incremental intraday fetch
    /// sees the cached points. Idempotent; concurrent callers share one load.
    func hydratePersistedDaySamplesIfNeeded() async {
        if persistedDaySamplesHydration == nil {
            persistedDaySamplesHydration = Task.detached(priority: .utility) {
                HealthDashboardSnapshotStore.loadDaySamples()
            }
        }

        guard let daySamples = await persistedDaySamplesHydration?.value, !daySamples.isEmpty else {
            return
        }

        healthTrends = healthTrends.mergingMissingDaySamples(from: daySamples)
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
        let usesHourlyBuckets: Bool
        switch kind {
        case .heartRate, .restingHeartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation:
            usesHourlyBuckets = false
        case .activeEnergy, .steps:
            usesHourlyBuckets = true
        default:
            return
        }

        await hydratePersistedDaySamplesIfNeeded()
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

        let primaryFetchStart: Date
        let secondaryFetchStart: Date
        if usesHourlyBuckets {
            // Hourly cumulative buckets overlap on the current hour, so the
            // incremental merge can't dedupe them — always refetch the full window.
            primaryFetchStart = interval.start
            secondaryFetchStart = interval.start
        } else {
            primaryFetchStart = HealthKitFetchEngine.incrementalFetchStart(after: cachedPrimary, windowStart: interval.start)
            secondaryFetchStart = HealthKitFetchEngine.incrementalFetchStart(after: cachedSecondary, windowStart: interval.start)

            // Cache already extends to the window end — nothing to add.
            if primaryFetchStart >= interval.end, secondaryFetchStart >= interval.end {
                return
            }
        }

        let primarySamples = await engine.fetchIntradayDaySamples(
            for: kind,
            calendar: calendar,
            startDate: primaryFetchStart,
            endDate: interval.end
        )
        let secondarySamples: HealthTrendSeries
        if selectedSecondaryHealthDataSourceOption(for: kind).isNoComparison
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

        let mergedPrimary: HealthTrendSeries
        let mergedSecondary: HealthTrendSeries
        if usesHourlyBuckets {
            mergedPrimary = primarySamples
            mergedSecondary = secondarySamples
        } else {
            mergedPrimary = HealthKitFetchEngine.mergeIntradaySamples(
                existing: cachedPrimary,
                incoming: primarySamples,
                windowStart: interval.start
            )
            mergedSecondary = HealthKitFetchEngine.mergeIntradaySamples(
                existing: cachedSecondary,
                incoming: secondarySamples,
                windowStart: interval.start
            )
        }

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
        case .activeEnergy:
            trends.activeEnergyDaySamples = mergedPrimary
            trends.activeEnergyDaySamplesSecondary = mergedSecondary
        case .steps:
            trends.stepsDaySamples = mergedPrimary
            trends.stepsDaySamplesSecondary = mergedSecondary
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

        isRefreshing = true
        defer { finishRefresh() }

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

    func healthDataSourceDefaultOptions() -> [BodyHealthDataSourceOption] {
        includeSelectedSourceOptionIfNeeded(
            selectedHealthDataSourceOption: healthDataSourceSelection.defaultOption,
            in: [BodyHealthDataSourceOption.allSources] + uniqueHealthDataSourceOptions(for: HealthMetricKind.sourceSelectableKinds)
        )
    }

    func secondaryHealthDataSourceDefaultOptions() -> [BodyHealthDataSourceOption] {
        let primaryOption = healthDataSourceSelection.defaultOption
        let candidates = [BodyHealthDataSourceOption.allSources]
            + uniqueHealthDataSourceOptions(for: HealthMetricKind.sourceSelectableKinds.filter(\.supportsSecondaryHealthDataSourceSelection))
        let filteredCandidates = candidates.filter { $0.id != primaryOption.id }
        guard secondaryHealthDataSourceSelection.defaultOption.id != primaryOption.id else {
            return [BodyHealthDataSourceOption.noComparison] + filteredCandidates
        }
        return includeSelectedSourceOptionIfNeeded(
            selectedHealthDataSourceOption: secondaryHealthDataSourceSelection.defaultOption,
            in: [BodyHealthDataSourceOption.noComparison] + filteredCandidates
        )
    }

    func selectedHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        resolvedHealthDataSourceOption(healthDataSourceSelection.option(for: kind), for: kind)
    }

    func selectedSecondaryHealthDataSourceOption(for kind: HealthMetricKind) -> BodyHealthDataSourceOption {
        let option = resolvedSecondaryHealthDataSourceOption(
            secondaryHealthDataSourceSelection.option(for: kind),
            for: kind
        )
        guard option.id != selectedHealthDataSourceOption(for: kind).id else {
            return .noComparison
        }

        return option
    }

    var defaultHealthDataSourceOption: BodyHealthDataSourceOption {
        healthDataSourceSelection.defaultOption
    }

    var defaultSecondaryHealthDataSourceOption: BodyHealthDataSourceOption {
        secondaryHealthDataSourceSelection.defaultOption
    }

    func updateCombinesHealthDataSourcesByName(_ combines: Bool) async {
        guard combinesHealthDataSourcesByName != combines else {
            return
        }

        combinesHealthDataSourcesByName = combines
        UserDefaults.standard.set(combines, forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey)
        await engine.setCombinesHealthDataSourcesByName(combines)
        await fetchHealthDataSourceOptions(calendar: .bodyGregorian)
        await requestAuthorizationAndRefresh()
    }

    func updateDefaultHealthDataSource(option: BodyHealthDataSourceOption) async {
        let nextSelection = healthDataSourceSelection.settingDefault(option: option)
        guard nextSelection != healthDataSourceSelection else {
            return
        }

        let nextSecondarySelection = secondaryHealthDataSourceSelection.defaultOption.id == nextSelection.defaultOption.id
            ? secondaryHealthDataSourceSelection.settingDefault(option: .noComparison)
            : secondaryHealthDataSourceSelection
        healthDataSourceSelection = nextSelection
        secondaryHealthDataSourceSelection = nextSecondarySelection
        nextSelection.save()
        nextSecondarySelection.save()
        await engine.setHealthDataSourceSelection(nextSelection)
        await engine.setSecondaryHealthDataSourceSelection(nextSecondarySelection)
        await requestAuthorizationAndRefresh()
    }

    func updateDefaultSecondaryHealthDataSource(option: BodyHealthDataSourceOption) async {
        let nextOption = option.id == healthDataSourceSelection.defaultOption.id ? .noComparison : option
        let nextSelection = secondaryHealthDataSourceSelection.settingDefault(option: nextOption)
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

        await requestAuthorizationAndRefresh()
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

    private func uniqueHealthDataSourceOptions(
        for kinds: [HealthMetricKind]
    ) -> [BodyHealthDataSourceOption] {
        var optionsByID: [String: BodyHealthDataSourceOption] = [:]
        for kind in kinds {
            for option in healthDataSourceOptionsByKind[kind] ?? []
            where !option.isAllSources && !option.isNoComparison {
                optionsByID[option.id] = optionsByID[option.id] ?? option
            }
        }

        return optionsByID.values.sorted { lhs, rhs in
            if lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedSame {
                return lhs.id < rhs.id
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func includeSelectedSourceOptionIfNeeded(
        selectedHealthDataSourceOption selectedOption: BodyHealthDataSourceOption,
        in options: [BodyHealthDataSourceOption]
    ) -> [BodyHealthDataSourceOption] {
        guard !options.contains(where: { $0.id == selectedOption.id }) else {
            return options
        }

        return options + [selectedOption]
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

        guard healthDataSourceOptionsByKind[kind]?.contains(where: { $0.id == option.id }) == true else {
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

        guard healthDataSourceOptionsByKind[kind]?.contains(where: { $0.id == option.id }) == true else {
            return .noComparison
        }

        return option
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

        await awaitMonthLoadCompletion(for: key)

        guard !loadedMonthKeys.contains(key) else {
            return true
        }

        await loadMonthKeysIfNeeded([key])
        return loadedMonthKeys.contains(key)
    }

    /// Consecutive previous months to probe for older ring history, walking
    /// back past months already loaded or already probed empty this session.
    /// Seeds from `date`'s month when nothing is loaded yet, matching the
    /// single-month walk this replaces.
    nonisolated static func previousActivityRingMonthCandidates(
        loadedKeys: Set<ActivityRingMonthKey>,
        exhaustedKeys: Set<ActivityRingMonthKey>,
        limit: Int,
        date: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        let knownKeys = loadedKeys.union(exhaustedKeys)
        let referenceKey = knownKeys.sortedByDate.first ?? ActivityRingMonthKey(date: date, calendar: calendar)
        guard var monthStart = referenceKey.startDate(calendar: calendar) else {
            return []
        }

        var candidates: [ActivityRingMonthKey] = []
        while candidates.count < limit {
            guard let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart) else {
                break
            }

            monthStart = previousMonthStart
            let key = ActivityRingMonthKey(date: previousMonthStart, calendar: calendar)
            if !knownKeys.contains(key) {
                candidates.append(key)
            }
        }

        return candidates
    }

    /// Month keys strictly between two months, oldest first. Used to record
    /// a confirmed-empty gap (no-watch stretch) as loaded so the calendar
    /// stays continuous and the gap is never refetched.
    nonisolated static func activityRingMonthKeys(
        after startKey: ActivityRingMonthKey,
        before endKey: ActivityRingMonthKey,
        calendar: Calendar = .bodyGregorian
    ) -> [ActivityRingMonthKey] {
        guard
            let startDate = startKey.startDate(calendar: calendar),
            let endDate = endKey.startDate(calendar: calendar)
        else {
            return []
        }

        var keys: [ActivityRingMonthKey] = []
        var cursor = startDate
        while let next = calendar.date(byAdding: .month, value: 1, to: cursor), next < endDate {
            keys.append(ActivityRingMonthKey(date: next, calendar: calendar))
            cursor = next
        }

        return keys
    }

    func loadPreviousActivityRingMonthIfNeeded(date: Date = Date()) async {
        await hydratePersistedDaySamplesIfNeeded()
        await awaitNextRefreshCompletion()

        guard permissionSelection.includes(.activityRings) else {
            activityRingHistory = .empty
            loadedActivityRingMonthKeys.removeAll()
            exhaustedActivityRingMonthKeys.removeAll()
            hasMoreActivityRingHistory = false
            return
        }

        guard !Task.isCancelled, loadingActivityRingMonthKeys.isEmpty, hasMoreActivityRingHistory else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            hasMoreActivityRingHistory = false
            return
        }

        let calendar = Calendar.bodyGregorian
        if loadedActivityRingMonthKeys.isEmpty {
            loadedActivityRingMonthKeys = Set(activityRingHistory.loadedMonthKeySet(calendar: calendar))
        }

        let candidates = Self.previousActivityRingMonthCandidates(
            loadedKeys: loadedActivityRingMonthKeys,
            exhaustedKeys: exhaustedActivityRingMonthKeys,
            limit: 3,
            date: date,
            calendar: calendar
        )
        guard !candidates.isEmpty else {
            return
        }

        do {
            try await engine.requestAuthorization()

            var mergedHistory: ActivityRingHistorySnapshot?
            var emptyProbedKeys: [ActivityRingMonthKey] = []
            for candidate in candidates {
                loadingActivityRingMonthKeys.insert(candidate)
                defer { loadingActivityRingMonthKeys.remove(candidate) }

                let previousHistory = await engine.fetchActivityRingHistory(monthKey: candidate, calendar: calendar)
                guard !previousHistory.loadedMonthKeys.isEmpty else {
                    // The fetch errored (success always echoes the month key);
                    // bail without marking the month exhausted or ending
                    // pagination so a later scroll can retry.
                    return
                }

                guard !previousHistory.days.isEmpty else {
                    exhaustedActivityRingMonthKeys.insert(candidate)
                    emptyProbedKeys.append(candidate)
                    continue
                }

                // Confirmed-empty months above this data month persist with
                // it so the calendar stays continuous (gap months render as
                // empty grids) and they are never refetched.
                mergedHistory = mergeOlderActivityRingHistory(
                    previousHistory,
                    gapKeys: emptyProbedKeys,
                    calendar: calendar
                )
                break
            }

            if mergedHistory == nil, let earliestProbed = candidates.last {
                // The whole batch was empty. Scan once for the next older
                // month with data: jump a long no-watch gap in one gesture,
                // or detect the true start of history exactly.
                mergedHistory = await jumpActivityRingHistoryGap(
                    before: earliestProbed,
                    date: date,
                    calendar: calendar
                )
            }

            guard let mergedHistory else {
                return
            }

            let snapshotToSave = HealthDashboardSnapshot(
                summary: healthSummary,
                trends: healthTrends,
                activityRingHistory: mergedHistory
            )
            Task.detached(priority: .utility) {
                HealthDashboardSnapshotStore.save(snapshotToSave)
            }
            authorizationState = .authorized
            markRefreshSucceeded(date: Date())
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
    }

    /// Merges one older month (plus any confirmed-empty gap months above it)
    /// into the live history, re-read at call time — a concurrent refresh may
    /// have published while a fetch was suspended.
    private func mergeOlderActivityRingHistory(
        _ olderHistory: ActivityRingHistorySnapshot,
        gapKeys: [ActivityRingMonthKey],
        calendar: Calendar
    ) -> ActivityRingHistorySnapshot {
        let gapFilledHistory = ActivityRingHistorySnapshot(
            days: olderHistory.days,
            loadedMonthKeys: olderHistory.loadedMonthKeys + gapKeys
        )
        let nextHistory = activityRingHistory.replacingLoadedMonths(with: gapFilledHistory, calendar: calendar)
        activityRingHistory = nextHistory
        loadedActivityRingMonthKeys = Set(nextHistory.loadedMonthKeySet(calendar: calendar))
        return nextHistory
    }

    /// Wide-scan fallback when a probe batch is all empty. Merges the most
    /// recent older month that has data (recording everything between it and
    /// the loaded history as a confirmed-empty gap), marks the exact end of
    /// history when nothing older exists, and leaves pagination retryable on
    /// transient errors.
    private func jumpActivityRingHistoryGap(
        before earliestProbed: ActivityRingMonthKey,
        date: Date,
        calendar: Calendar
    ) async -> ActivityRingHistorySnapshot? {
        loadingActivityRingMonthKeys.insert(earliestProbed)
        defer { loadingActivityRingMonthKeys.remove(earliestProbed) }

        switch await engine.probeOlderActivityRingHistory(before: earliestProbed, calendar: calendar) {
        case .found(let olderMonth):
            guard let foundKey = olderMonth.loadedMonthKeys.first else {
                return nil
            }

            let earliestLoaded = loadedActivityRingMonthKeys.sortedByDate.first
                ?? ActivityRingMonthKey(date: date, calendar: calendar)
            let gapKeys = Self.activityRingMonthKeys(
                after: foundKey,
                before: earliestLoaded,
                calendar: calendar
            )
            return mergeOlderActivityRingHistory(olderMonth, gapKeys: gapKeys, calendar: calendar)
        case .noOlderData:
            hasMoreActivityRingHistory = false
            return nil
        case .failed:
            return nil
        }
    }

    func refreshCurrentMonth(date: Date = Date()) async {
        guard !isRefreshing else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = "Apple Health is not available on this device."
            return
        }

        isRefreshing = true
        defer { finishRefresh() }

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
        monthLoadOrder = [key]
        loadedActivityRingMonthKeys.removeAll()
        exhaustedActivityRingMonthKeys.removeAll()
        hasMoreActivityRingHistory = true
        loadingMonthKeys.removeAll()
        loadingActivityRingMonthKeys.removeAll()
        healthDataSourceOptionsByKind = [:]
        Task { [engine] in await engine.clearSourceCache() }
        persistedDaySamplesHydration = nil
        lastSuccessfulRefreshDate = nil
        authorizationState = .unknown
        healthDataNotice = "Local cache cleared. Refresh to load Apple Health data again."

        WorkoutSnapshotStore.delete()
        WorkoutSnapshotStore.deletePrevious()
        HealthDashboardSnapshotStore.delete()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        HealthWidgetSnapshotStore.delete()
        cacheDiskSizeBytes = 0
        BodyWidgetReloadCoalescer.shared.requestReload()
    }

    /// Expects the caller to have set `isRefreshing` (and to call
    /// `finishRefresh()` when done) before the first suspension.
    private func refreshRecentMonths(date: Date = Date()) async {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("RefreshRecentMonths")
        defer { BodyPerformanceSignposts.signposter.endInterval("RefreshRecentMonths", signpostState) }

        await hydratePersistedDaySamplesIfNeeded()
        await engine.setHealthTrendAnchorDate(date)

        let calendar = Calendar.bodyGregorian
        let keys = Self.recentMonthKeys(count: Self.recentChartMonthCount, from: date, calendar: calendar)
        let dashboardFetchSelection = BodyDashboardFetchSelection.load()

        do {
            if permissionSelection.includes(.workouts) {
                try await refresh(monthKeys: keys, calendar: calendar)
            } else {
                clearWorkoutSnapshots(calendar: calendar)
            }
            await fetchHealthDataSourceOptions(calendar: calendar)

            let (fetchedHealthSummary, fetchedHealthTrends, fetchedActivityRingHistory) =
                await fetchDashboardSnapshotProgressively(
                    calendar: calendar,
                    selection: dashboardFetchSelection
                )

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

    /// Expects the caller to have set `isRefreshing` (and to call
    /// `finishRefresh()` when done) before the first suspension.
    private func refresh(month: Int, year: Int, calendar: Calendar, updatesHealthSummary: Bool) async {
        let refreshDate = Date()
        if updatesHealthSummary {
            await hydratePersistedDaySamplesIfNeeded()
            await engine.setHealthTrendAnchorDate(refreshDate)
        }

        let key = BodyWorkoutMonthKey(month: month, year: year)

        do {
            if permissionSelection.includes(.workouts) {
                try await refresh(monthKeys: [key], calendar: calendar)
            } else {
                clearWorkoutSnapshots(calendar: calendar)
            }
            if updatesHealthSummary {
                let dashboardFetchSelection = BodyDashboardFetchSelection.load()
                await fetchHealthDataSourceOptions(calendar: calendar)

                let (fetchedHealthSummary, fetchedHealthTrends, fetchedActivityRingHistory) =
                    await fetchDashboardSnapshotProgressively(
                        calendar: calendar,
                        selection: dashboardFetchSelection
                    )

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

    /// Fetch the dashboard summary, trend snapshot, and activity-ring history
    /// concurrently and publish each bucket to `@Published` state as soon as it
    /// completes. Users see metric values, ring values, then trend charts fill in
    /// progressively instead of one large update at the very end of the refresh.
    /// Readiness is preserved at its cached value during the stream — the final
    /// `updateHealthDashboardSnapshot` recomputes it once everything has landed.
    private func fetchDashboardSnapshotProgressively(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection
    ) async -> (
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        activityRingHistory: ActivityRingHistorySnapshot
    ) {
        let cachedTrendsAtStart = healthTrends
        var fetchedSummary = healthSummary
        var fetchedTrends = healthTrends
        var fetchedActivityRingHistory = activityRingHistory

        let engine = self.engine
        await withTaskGroup(of: DashboardFetchUnit.self) { group in
            group.addTask {
                .summary(await engine.fetchHealthSummary(calendar: calendar, selection: selection))
            }
            group.addTask {
                .trends(
                    await engine.fetchHealthTrends(
                        calendar: calendar,
                        cachedTrends: cachedTrendsAtStart,
                        selection: selection
                    )
                )
            }
            group.addTask {
                .rings(await engine.fetchDashboardActivityRingHistory(calendar: calendar, selection: selection))
            }

            for await unit in group {
                switch unit {
                case .summary(let s):
                    fetchedSummary = s
                    // Keep the cached `readiness` visible during the progressive
                    // publish — the final filtered+recomputed snapshot overrides
                    // it in `updateHealthDashboardSnapshot`.
                    healthSummary = s.replacingMetric(.readiness, with: healthSummary)
                case .trends(let t):
                    fetchedTrends = t
                    // `fetchHealthTrends` does not populate `.readiness` (it gets
                    // recomputed in `updateHealthDashboardSnapshot`). Preserve
                    // the cached series so the Readiness preview chart can
                    // animate from old values to new instead of dropping to
                    // empty and reappearing.
                    healthTrends = t.replacingMetric(.readiness, with: healthTrends)
                case .rings(let r):
                    // Merge instead of replace — replacing dropped any older
                    // months the user had paged in (and the refresh's final
                    // save then persisted that loss).
                    let mergedRings = activityRingHistory.replacingLoadedMonths(with: r, calendar: calendar)
                    fetchedActivityRingHistory = mergedRings
                    activityRingHistory = mergedRings
                    loadedActivityRingMonthKeys = Set(mergedRings.loadedMonthKeySet(calendar: calendar))
                }
            }
        }

        return (fetchedSummary, fetchedTrends, fetchedActivityRingHistory)
    }

    private enum DashboardFetchUnit {
        case summary(HealthSummarySnapshot)
        case trends(HealthTrendSnapshot)
        case rings(ActivityRingHistorySnapshot)
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
        defer {
            loadingMonthKeys.subtract(keysToLoad)
            finishMonthLoad(for: keysToLoad)
        }

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
        try await withThrowingTaskGroup(
            of: (BodyWorkoutMonthKey, [WorkoutSummary]).self
        ) { group in
            for key in orderedKeys {
                group.addTask {
                    let workouts = try await engine.fetchWorkouts(month: key.month, year: key.year, calendar: calendar)
                    return (key, workouts)
                }
            }

            // Publish each month's snapshot as it returns so the Workouts tab
            // populates progressively instead of waiting for the slowest month.
            for try await (key, workouts) in group {
                monthSnapshots[key] = WorkoutMonthSnapshot.make(
                    month: key.month,
                    year: key.year,
                    workouts: workouts,
                    calendar: calendar
                )
                loadedMonthKeys.insert(key)
                noteMonthSnapshotStored(key)
            }
        }
    }

    private func noteMonthSnapshotStored(_ key: BodyWorkoutMonthKey, date: Date = Date()) {
        monthLoadOrder.removeAll { $0 == key }
        monthLoadOrder.append(key)

        let protectedKeys = Self.recentMonthKeys(
            count: Self.recentChartMonthCount,
            from: date,
            calendar: .bodyGregorian
        ).union([BodyWorkoutMonthKey(month: snapshot.month, year: snapshot.year)])
        for evictedKey in Self.evictableMonthKeys(
            loadOrder: monthLoadOrder,
            maximumCount: Self.maximumCachedMonthSnapshots,
            protectedKeys: protectedKeys
        ) {
            monthLoadOrder.removeAll { $0 == evictedKey }
            monthSnapshots.removeValue(forKey: evictedKey)
            loadedMonthKeys.remove(evictedKey)
        }
    }

    /// The least-recently-loaded keys to drop so at most `maximumCount`
    /// months stay cached, never evicting `protectedKeys`. `loadOrder` is
    /// ordered oldest-load first.
    nonisolated static func evictableMonthKeys(
        loadOrder: [BodyWorkoutMonthKey],
        maximumCount: Int,
        protectedKeys: Set<BodyWorkoutMonthKey>
    ) -> [BodyWorkoutMonthKey] {
        var excess = loadOrder.count - maximumCount
        guard excess > 0 else {
            return []
        }

        var evictable: [BodyWorkoutMonthKey] = []
        for key in loadOrder where excess > 0 {
            guard !protectedKeys.contains(key) else {
                continue
            }
            evictable.append(key)
            excess -= 1
        }
        return evictable
    }

    /// Metric kinds whose data feeds the Readiness score (the
    /// `ReadinessScoreCalculator` components and
    /// `HealthTrendSnapshot.readinessSourceSeries`). Refreshing any other
    /// single metric skips the per-day readiness recompute — its inputs
    /// cannot have changed.
    nonisolated static let readinessInputMetricKinds: Set<HealthMetricKind> = [
        .readiness,
        .sleep,
        .restingHeartRate,
        .heartRateVariability,
        .respiratoryRate,
        .oxygenSaturation,
        .trainingLoad,
        .wristTemperature
    ]

    private func updateHealthDashboardSnapshot(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        activityRingHistory: ActivityRingHistorySnapshot,
        recomputesReadiness: Bool = true
    ) async {
        let calendar = Calendar.bodyGregorian
        let anchorDate = await engine.healthTrendAnchorDate ?? Date()
        let permissionSelection = self.permissionSelection
        let idealSleepDuration = Self.storedIdealSleepDuration()
        let rawSnapshot = HealthDashboardSnapshot(
            summary: summary,
            trends: trends,
            activityRingHistory: activityRingHistory
        )

        // Filter + readiness recompute are the heaviest per-refresh CPU spike
        // (the readiness `dailySeries` iterates up to ~365 days × multi-metric
        // baselines). Run them off the main actor, recompute at most once
        // (`filtered(by:)` would chain its own recompute ahead of the anchored
        // one), and skip entirely when the refreshed metric cannot change any
        // readiness input.
        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            let filtered = rawSnapshot.filteredWithoutReadinessRecompute(by: permissionSelection)
            guard recomputesReadiness else {
                return filtered
            }
            return filtered.recalculatingReadiness(
                on: anchorDate,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar
            )
        }.value

        let nextActivityRingHistory = self.activityRingHistory.replacingLoadedMonths(
            with: filteredSnapshot.activityRingHistory,
            calendar: calendar
        )
        healthSummary = filteredSnapshot.summary
        healthTrends = filteredSnapshot.trends
        self.activityRingHistory = nextActivityRingHistory
        loadedActivityRingMonthKeys = Set(nextActivityRingHistory.loadedMonthKeySet(calendar: calendar))
        // Fresh dashboard data may include backfilled months; let older-month
        // pagination re-probe (at most a few cheap queries) instead of staying
        // pinned at a previously detected history start.
        exhaustedActivityRingMonthKeys.removeAll()
        hasMoreActivityRingHistory = true

        let snapshotToSave = HealthDashboardSnapshot(
            summary: filteredSnapshot.summary,
            trends: filteredSnapshot.trends,
            activityRingHistory: nextActivityRingHistory
        )
        let secondarySignature = secondaryHealthDataSourceSelection.signature
        Task.detached(priority: .utility) {
            HealthDashboardSnapshotStore.save(snapshotToSave)
            HealthDashboardSnapshotStore.saveSecondarySelectionSignature(secondarySignature)
            await self.refreshCacheDiskSize()
        }
        saveHealthWidgetSnapshot()
    }

    private func markRefreshSucceeded(date: Date) {
        lastSuccessfulRefreshDate = date
        HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(date)
    }

    /// Builds the slim widget snapshot from the current trends, sleep stages,
    /// source selection, and unit preferences, then writes it to the App Group
    /// so the trend + sleep-stage widgets can render. Reads run on the main
    /// actor; the build + disk write happen off-actor.
    private func saveHealthWidgetSnapshot() {
        let trends = healthTrends
        let summary = healthSummary
        let sleepStageSnapshot = summary.sleep.stageSnapshot
        let temperatureUnitPreference = HealthWidgetSnapshotBuilder.storedTemperatureUnitPreference()
        let energyUnitPreference = HealthWidgetSnapshotBuilder.storedEnergyUnitPreference()
        let weightUnitPreference = HealthWidgetSnapshotBuilder.storedWeightUnitPreference()
        let idealSleepDuration = Self.storedIdealSleepDuration()
        let showSleepScore = HealthWidgetSnapshotBuilder.storedShowSleepScore()

        var primarySourceNames: [HealthMetricKind: String] = [:]
        for metric in HealthWidgetMetric.allCases {
            let kind = metric.healthMetricKind
            primarySourceNames[kind] = selectedHealthDataSourceOption(for: metric.sourceSelectionKind).name
        }

        Task.detached(priority: .utility) {
            let snapshot = HealthWidgetSnapshotBuilder.make(
                trends: trends,
                summary: summary,
                sleepStageSnapshot: sleepStageSnapshot,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                weightUnitPreference: weightUnitPreference,
                idealSleepDuration: idealSleepDuration,
                showSleepScore: showSleepScore,
                primarySourceName: { primarySourceNames[$0] }
            )
            if HealthWidgetSnapshotStore.save(snapshot) {
                await BodyWidgetReloadCoalescer.shared.requestReload()
            }
        }
    }

    private func applyPermissionSelectionToCachedData() async {
        await hydratePersistedDaySamplesIfNeeded()
        let rawSnapshot = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let permissionSelection = self.permissionSelection
        let idealSleepDuration = Self.storedIdealSleepDuration()

        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            rawSnapshot.filtered(by: permissionSelection, idealSleepDuration: idealSleepDuration)
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
        saveHealthWidgetSnapshot()
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
        monthLoadOrder.removeAll()
        BodyWidgetReloadCoalescer.shared.requestReload()
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
                await BodyWidgetReloadCoalescer.shared.requestReload()
            }
            await self.refreshCacheDiskSize()
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

    nonisolated static func storedIdealSleepDuration(
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        // `@AppStorage` writes the raw `Int` (minutes) for this key, but
        // `BodySettingsView` may never have been opened — in which case the
        // value is absent and `integer(forKey:)` returns 0. Treat 0 as
        // "unset" and fall back to the default goal.
        let storedMinutes = defaults.integer(forKey: BodyAppearancePreference.sleepDurationGoalMinutesKey)
        guard storedMinutes > 0 else {
            return BodySleepDurationGoal.defaultDuration
        }
        return BodySleepDurationGoal.duration(from: storedMinutes)
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
            return .preparationAndReadiness
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
