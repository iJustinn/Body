//
//  HealthKitWorkoutStore.swift
//  Body
//

import Foundation
import HealthKit
import WidgetKit

/// How a refresh was triggered, which decides how much workout data is
/// re-fetched eagerly and whether the engine's per-workout caches (effort
/// scores, finished workouts' heart-rate payloads) may be reused.
enum BodyWorkoutRefreshIntent {
    /// Automatic warm resume: current month only, per-workout caches reused.
    case passiveResume
    /// Explicit gesture (pull-to-refresh, Settings, first load): full recent
    /// window, per-workout caches cleared and bypassed so re-rated efforts and
    /// edited workouts reconcile.
    case userInitiated
}

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

/// The recent same-type history used to build a workout's 30-day metric comparisons.
/// `isComplete` is false while any spanned month is still loading, so the UI can
/// distinguish "loading" from genuinely sparse history.
struct WorkoutComparisonContext {
    let priorWorkouts: [WorkoutSummary]
    let isComplete: Bool
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
        guard !isEmpty else { return String(localized: "Empty") }
        // `diskSizeBytes` is refreshed off the main actor (`refreshCacheDiskSize`), so it's
        // still 0 in the window between a non-empty cache loading and that stat landing.
        // Show the generic "Cached" until then rather than a misleading "Zero KB".
        return diskSizeBytes > 0 ? formattedDiskSize : String(localized: "Cached")
    }

    var detailLines: [String] {
        [
            hasHealthDashboardData
                ? String(localized: "Health summary, trend, or Activity Ring data is available in the local dashboard cache.")
                : String(localized: "Health dashboard cache is empty."),
            String(localized: "\(workoutMonthCount) workout \(monthWord(for: workoutMonthCount)) cached with \(workoutCount) \(workoutWord(for: workoutCount))."),
            String(localized: "\(activityRingMonthCount) Activity Ring \(monthWord(for: activityRingMonthCount)) cached."),
            String(localized: "On-disk size: \(formattedDiskSize).")
        ]
    }

    var formattedDiskSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: diskSizeBytes)
    }

    private func monthWord(for count: Int) -> String {
        count == 1 ? String(localized: "month") : String(localized: "months")
    }

    private func workoutWord(for count: Int) -> String {
        count == 1 ? String(localized: "workout") : String(localized: "workouts")
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
    /// Session-scoped manual effort ratings the user just saved from the workout
    /// detail screen, keyed by workout UUID. The detail card prefers these over
    /// the cached snapshot value so an edit shows immediately; the snapshot's
    /// baked-in effort catches up on the next workout refresh.
    @Published private(set) var workoutEffortOverrides: [UUID: Double] = [:]
    /// Workouts whose saved effort was an accepted suggestion (saved unchanged from
    /// the pre-filled estimate). `WorkoutEffortEstimator` excludes these from its
    /// calibration so it never learns from its own output; a manual re-rate removes
    /// the ID again. Device-local: persisted in `UserDefaults` as an ordered
    /// `[String]` capped at `suggestionAcceptedEffortIDsCap` (oldest dropped first).
    @Published private(set) var suggestionAcceptedEffortWorkoutIDs: Set<UUID> =
        HealthKitWorkoutStore.loadSuggestionAcceptedEffortIDs()
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
    /// Date of the last refresh that re-fetched the dashboard vitals (not just
    /// workouts or ring history). Carried in the watch snapshot so the watch's
    /// staleness logic isn't reset by workout-only refreshes.
    private var lastVitalsRefreshDate: Date?
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
    /// Session cache of resolved workout routes keyed by workout UUID. A cached
    /// `.some(nil)` means "confirmed no readable route", so non-route workouts
    /// aren't re-queried and the city label isn't re-geocoded when a detail
    /// sheet is reopened. HealthKit read access is opaque, so authorization gates
    /// clear the cache before any stale positive or negative route result sticks.
    private var routeCache: [UUID: WorkoutRoute?] = [:]
    /// Session cache of a workout's raw distance samples keyed by UUID, feeding the
    /// detail Splits section. Empty results are cached only for workouts that ended
    /// more than 24 h ago; recent workouts may still be syncing from the watch, so
    /// their empty reads are retried on the next sheet open.
    private var distanceSampleCache: [UUID: WorkoutSplitData] = [:]
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
    /// Retains the Body Pro entitlement observer so secondary-source gating (which this
    /// store resolves from `BodyProEntitlement`, not the SwiftUI environment) recomputes
    /// when the entitlement flips.
    private var proEntitlementObserver: NSObjectProtocol?

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
        initialSnapshot: WorkoutMonthSnapshot = WorkoutSnapshotStore.loadOrPlaceholder(),
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
        // Skip the readiness recompute at init: it's a per-day iteration over up
        // to ~365 trend points that would block the first frame. The cached
        // `summary.readiness` value was correct when written; the next refresh
        // recomputes it off the main thread.
        //
        // Exception: when frozen morning records exist but were captured under a
        // different readiness input context (source, permission, or grouping
        // changed while the app was closed, or the prior refresh failed before
        // re-saving), the persisted chart overlay is stale. Recompute once here so
        // the records are dropped and the series rebuilt under the current inputs,
        // durably and without depending on the next refresh succeeding.
        let initialIdealSleepDuration = Self.storedIdealSleepDuration()
        let initialReadinessContext = Self.readinessRecordContextSignature(
            permissionSelection: initialPermissionSelection,
            healthDataSourceSelection: initialHealthDataSourceSelection,
            combinesHealthDataSourcesByName: initialCombinesHealthDataSourcesByName,
            idealSleepDuration: initialIdealSleepDuration
        )
        let initialTrends = initialHealthDashboardSnapshot.trends
        let hasStaleReadinessOverlay = !initialTrends.recordedReadiness.isEmpty
            && initialTrends.recordedReadinessContext != initialReadinessContext
        let filteredHealthDashboardSnapshot = hasStaleReadinessOverlay
            ? initialHealthDashboardSnapshot.filtered(
                by: initialPermissionSelection,
                idealSleepDuration: initialIdealSleepDuration,
                recordedReadinessContext: initialReadinessContext
            )
            : initialHealthDashboardSnapshot.filteredWithoutReadinessRecompute(by: initialPermissionSelection)
        let startingSnapshot: WorkoutMonthSnapshot
        if !initialPermissionSelection.includes(.workouts) {
            startingSnapshot = WorkoutMonthSnapshot.make(
                month: initialSnapshot.month,
                year: initialSnapshot.year,
                workouts: [],
                calendar: .bodyGregorian
            )
        } else if !initialPermissionSelection.includes(.workoutMetrics) {
            // The persisted snapshot can still carry VO₂max/power/cadence/stroke
            // data, so strip it here too — otherwise it reappears on launch
            // before the next refresh rebuilds the metrics-gated summary.
            startingSnapshot = initialSnapshot.removingWorkoutMetrics()
        } else {
            startingSnapshot = initialSnapshot
        }
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

        // When Body Pro unlocks (or is revoked/refunded), re-fetch so the secondary-source
        // comparison — gated deep in this store and the fetch engine, beyond SwiftUI's
        // reach — recomputes for the now-current entitlement. `setUnlocked` only posts on
        // an actual flip, so this never fires on a steady-state launch.
        proEntitlementObserver = NotificationCenter.default.addObserver(
            forName: BodyProEntitlement.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            Task { await self.requestAuthorizationAndRefresh() }
        }
    }

    var healthSyncStatusSummaryText: String {
        if isRefreshing {
            return String(localized: "Refreshing")
        }

        switch authorizationState {
        case .unknown:
            return lastSuccessfulRefreshDate == nil ? String(localized: "Not Synced") : healthSyncStatusLastRefreshText
        case .unavailable:
            return String(localized: "Unavailable")
        case .authorized:
            return healthSyncStatusLastRefreshText
        case .denied:
            return String(localized: "Denied")
        case .failed:
            return String(localized: "Failed")
        }
    }

    var healthSyncStatusLastRefreshText: String {
        guard let date = lastSuccessfulRefreshDate else {
            return String(localized: "Not yet refreshed")
        }

        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    var healthSyncStatusDetailText: String {
        if isRefreshing {
            return String(localized: "Body is refreshing Apple Health data now.")
        }

        switch authorizationState {
        case .unknown:
            return lastSuccessfulRefreshDate == nil
                ? String(localized: "Body has not completed a HealthKit refresh in this app session.")
                : String(localized: "Body has cached Health data from a previous refresh.")
        case .unavailable:
            return String(localized: "Apple Health is not available on this device.")
        case .authorized:
            return String(localized: "Body can read the Health data permissions enabled below.")
        case .denied:
            return String(localized: "Health access was denied. Review Body's permissions in Apple Health or iOS Settings.")
        case .failed(let message):
            return String(localized: "The last refresh failed: \(message)")
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

    /// `intent` decides the eager workout window (full chart window when user
    /// initiated, current month on a passive resume — past months are
    /// effectively immutable and the Workouts tab lazy-loads the rest on
    /// demand) and the per-workout cache policy (cleared + bypassed when user
    /// initiated so edits reconcile; reused on passive resumes).
    func requestAuthorizationAndRefresh(intent: BodyWorkoutRefreshIntent = .userInitiated) async {
        guard !isRefreshing else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = String(localized: "Apple Health is not available on this device.")
            return
        }

        // Claim the refresh slot before the first suspension — otherwise a
        // second entry point arriving during the authorization round-trip
        // passes the `isRefreshing` guard and starts a concurrent refresh.
        isRefreshing = true
        defer { finishRefresh() }

        do {
            try await requestHealthKitAuthorization()
            await refreshRecentMonths(intent: intent)
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
            healthDataNotice = String(localized: "Apple Health is not available on this device.")
            return
        }

        isRefreshing = true
        await hydratePersistedDaySamplesIfNeeded()
        await engine.setHealthTrendAnchorDate(date)
        defer { finishRefresh() }

        let calendar = Calendar.bodyGregorian

        do {
            try await requestHealthKitAuthorization()
            if kind == .trainingLoad {
                // The detail pull is an explicit gesture: drop the per-workout
                // effort cache so a re-rated workout reconciles into the
                // 180-day training-load fetch.
                await engine.clearWorkoutEffortCache()
            }
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
            markRefreshSucceeded(date: date, refreshedVitals: false)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
        await engine.setHealthTrendAnchorDate(nil)
    }

    /// Runs a post-write refresh for `kind`, first waiting for any in-flight
    /// refresh to finish. `refreshHealthMetric` bails out when `isRefreshing` is
    /// already set, so a measurement or effort saved during launch or
    /// pull-to-refresh would otherwise never flow into the dashboard until the
    /// next manual refresh.
    private func refreshAfterWrite(_ kind: HealthMetricKind) async {
        await awaitNextRefreshCompletion()
        await refreshHealthMetric(kind)
    }

    /// Writes a manually-entered weight and/or body-fat measurement to Apple
    /// Health, then refreshes the Basics metric so the new sample flows through
    /// the existing read pipeline into `healthSummary`/`healthTrends` and the
    /// Basics card and detail charts update. `weightKilograms` is already in kg;
    /// `bodyFatPercent` is a 0–100 percentage (converted to a fraction on save).
    /// Throws if the user denies write access or HealthKit rejects the save, so
    /// the entry sheet can surface the failure.
    func saveBodyComposition(weightKilograms: Double?, bodyFatPercent: Double?, date: Date) async throws {
        try await engine.requestBodyCompositionWriteAuthorization()
        try await engine.saveBodyComposition(
            weightKilograms: weightKilograms,
            bodyFatPercent: bodyFatPercent,
            date: date
        )
        await refreshAfterWrite(.basics)
    }

    /// Saves a manual workout-effort rating (1–10) to Apple Health, reflects it
    /// immediately on the workout detail card via `workoutEffortOverrides`, then
    /// recomputes Training Load (which effort feeds) in the background so the
    /// trend — and the Apple Watch snapshot pushed on refresh success — pick up
    /// the change. Throws if the user denies write access or the save fails.
    func saveWorkoutEffort(workoutID: UUID, score: Double) async throws {
        try await engine.requestWorkoutEffortWriteAuthorization()
        try await engine.saveWorkoutEffort(workoutID: workoutID, score: score)
        workoutEffortOverrides[workoutID] = score
        Task { await refreshAfterWrite(.trainingLoad) }
    }

    nonisolated private static let suggestionAcceptedEffortIDsKey = "workoutEffortSuggestionAcceptedIDs"
    nonisolated private static let suggestionAcceptedEffortIDsCap = 300

    nonisolated private static func loadSuggestionAcceptedEffortIDs() -> Set<UUID> {
        let stored = UserDefaults.standard.stringArray(forKey: suggestionAcceptedEffortIDsKey) ?? []
        return Set(stored.compactMap(UUID.init(uuidString:)))
    }

    /// Records whether a workout's saved effort was an accepted suggestion (saved
    /// unchanged from the pre-filled estimate). Call on every effort save: `true`
    /// marks the rating as machine-derived, any other save clears the mark so the
    /// rating counts as genuine again.
    func setEffortSuggestionAccepted(_ accepted: Bool, workoutID: UUID) {
        var stored = UserDefaults.standard.stringArray(forKey: Self.suggestionAcceptedEffortIDsKey) ?? []
        let idString = workoutID.uuidString
        stored.removeAll { $0 == idString }
        if accepted {
            stored.append(idString)
            if stored.count > Self.suggestionAcceptedEffortIDsCap {
                stored.removeFirst(stored.count - Self.suggestionAcceptedEffortIDsCap)
            }
        }
        UserDefaults.standard.set(stored, forKey: Self.suggestionAcceptedEffortIDsKey)
        suggestionAcceptedEffortWorkoutIDs = Set(stored.compactMap(UUID.init(uuidString:)))
    }

    /// Loads the GPS route + city label for a workout's detail map hero, or `nil`
    /// when the workout has no readable route. Cached per session (including the
    /// no-route result), so it's safe to call on every detail-sheet open.
    func loadWorkoutRoute(for workout: WorkoutSummary) async -> WorkoutRoute? {
        if let cached = routeCache[workout.id] {
            return cached
        }

        let coordinates = await engine.workoutRouteCoordinates(workoutID: workout.id)
        guard coordinates.count >= 2 else {
            routeCache[workout.id] = .some(nil)
            return nil
        }

        let locality = await BodyReverseGeocoder.locality(for: coordinates)
        let route = WorkoutRoute(coordinates: coordinates, locality: locality)
        routeCache[workout.id] = .some(route)
        return route
    }

    /// Loads a workout's raw distance samples and recorded split segments for the
    /// detail Splits section, or `.empty` when the activity isn't pace/speed-tracked
    /// or has no usable distance data. Cached per session; an empty read is cached
    /// only when the workout ended more than 24 h ago, so a still-syncing recent
    /// workout is retried on reopen.
    func loadWorkoutSplitData(for workout: WorkoutSummary) async -> WorkoutSplitData {
        guard workout.type.paceStyle == .distancePace || workout.type.paceStyle == .speed else {
            return .empty
        }

        if let cached = distanceSampleCache[workout.id] {
            return cached
        }

        let data = await engine.workoutSplitData(workoutID: workout.id)
        if !data.distanceSamples.isEmpty {
            distanceSampleCache[workout.id] = data
        } else {
            let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))
            if Date().timeIntervalSince(endDate) > 24 * 60 * 60 {
                distanceSampleCache[workout.id] = data
            }
        }
        return data
    }

    /// Estimated max heart rate (220 − age) from Apple Health, anchoring the
    /// workout-detail heart-rate zones. `nil` when no birth date is readable, so the
    /// caller falls back to the session's peak HR.
    func userMaxHeartRate() async -> Double? {
        await engine.userMaxHeartRate()
    }

    private func requestHealthKitAuthorization() async throws {
        try await engine.requestAuthorization()
        routeCache.removeAll()
        distanceSampleCache.removeAll()
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
            try await requestHealthKitAuthorization()
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

        // A refresh may have started while the engine fetches above were
        // suspended. It captured `healthTrends` before these day samples existed
        // and will overwrite our write below when it completes — dropping the
        // just-loaded intraday series and persisting that regression. Wait for
        // any in-flight refresh (the loop covers a fresh one claiming the slot
        // before we resume), then merge onto the now-current `healthTrends`.
        // There is no suspension point between the loop exit and the write, so
        // on the MainActor nothing can clobber it.
        while isRefreshing {
            await awaitNextRefreshCompletion()
            guard !Task.isCancelled else {
                return
            }
        }

        let mergedPrimary: HealthTrendSeries
        let mergedSecondary: HealthTrendSeries
        if usesHourlyBuckets {
            mergedPrimary = primarySamples
            mergedSecondary = secondarySamples
        } else {
            mergedPrimary = HealthKitFetchEngine.mergeIntradaySamples(
                existing: healthTrends.daySeries(for: kind),
                incoming: primarySamples,
                windowStart: interval.start,
                refetchStart: primaryFetchStart
            )
            mergedSecondary = HealthKitFetchEngine.mergeIntradaySamples(
                existing: healthTrends.secondaryDaySeries(for: kind),
                incoming: secondarySamples,
                windowStart: interval.start,
                refetchStart: secondaryFetchStart
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

    func refreshWorkoutMonth(month: Int, year: Int, intent: BodyWorkoutRefreshIntent = .userInitiated) async {
        guard !isRefreshing else {
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            healthDataNotice = String(localized: "Apple Health is not available on this device.")
            return
        }

        isRefreshing = true
        defer { finishRefresh() }

        let calendar = Calendar.bodyGregorian

        do {
            try await requestHealthKitAuthorization()
            if intent == .userInitiated {
                await engine.clearWorkoutEffortCache()
            }
            await refresh(
                month: month,
                year: year,
                calendar: calendar,
                updatesHealthSummary: false,
                reusesCachedWorkoutHeartRate: intent == .passiveResume
            )
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
        if permission == .workouts {
            routeCache.removeAll()
            distanceSampleCache.removeAll()
        } else if permission == .workoutMetrics {
            // Cached split data carries per-split step cadence, which rides on the
            // Workout Metrics permission — drop it so a toggle change isn't served
            // stale cadence from a read taken under the previous selection.
            distanceSampleCache.removeAll()
        }
        await applyPermissionSelectionToCachedData()

        if isEnabled {
            // A refresh may be in flight (resume/pull-to-refresh); its
            // `isRefreshing` guard would otherwise silently drop this refetch,
            // leaving old-permission data on screen. Mirror the secondary-source
            // variants: wait it out, then refetch under the new selection.
            await awaitNextRefreshCompletion()
            guard !Task.isCancelled else {
                return
            }
            await requestAuthorizationAndRefresh()
        } else {
            updateHealthDataNotice()
            // The enable branch republishes via the refresh funnel; the disable
            // branch otherwise wouldn't, so the watch would keep showing the
            // hidden category (and its live HR/HRV path could keep reading it).
            // healthSummary/healthTrends were just filtered by
            // applyPermissionSelectionToCachedData(), and the synced selection
            // rides the push's context.
            publishWatchSnapshot()
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
        // Secondary-source comparison is a Body Pro feature. Collapsing to .noComparison
        // here neutralizes every comparison renderer (bars, range bars, line, title) that
        // reads this single chokepoint, even if a selection was persisted while Pro.
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

        // Wait out any in-flight refresh so the `isRefreshing` guard in
        // `requestAuthorizationAndRefresh` doesn't silently drop this refetch
        // (matches the secondary-source variants).
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled else {
            return
        }

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

        // Wait out any in-flight refresh so the `isRefreshing` guard in
        // `requestAuthorizationAndRefresh` doesn't silently drop this refetch
        // (matches the secondary-source variants).
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled else {
            return
        }

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

        // Wait out any in-flight refresh so the `isRefreshing` guard in
        // `requestAuthorizationAndRefresh` doesn't silently drop this refetch
        // (matches the secondary-source variants).
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled else {
            return
        }

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

    /// True until the app has any Health data to show: no successful refresh
    /// recorded by this or any prior session, and nothing restored from the
    /// snapshot cache. Presents the first-launch load overlay and keeps every
    /// passive load idle — the app-entry sync, the workout-month lazy loads,
    /// and older ring-history paging — so the first big load (including the
    /// ten-year activity-ring backfill) only runs when the user starts it
    /// from the overlay, a refresh gesture, or the Settings refresh button.
    var needsInitialHealthDataLoad: Bool {
        lastSuccessfulRefreshDate == nil && HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        ).isEmpty
    }

    func syncWhenAppBecomesActive(date: Date = Date()) async {
        guard !isRefreshing, !needsInitialHealthDataLoad else {
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
            await refreshWorkoutMonth(month: month, year: year, intent: .passiveResume)
            return
        }

        // Stale (>5 min) automatic resume: refresh the dashboard, but only
        // re-fetch the current month of workouts — past months are effectively
        // immutable and the Workouts tab lazy-loads them on demand, so
        // re-pulling the full window on every warm resume is wasted work.
        await requestAuthorizationAndRefresh(intent: .passiveResume)
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

    /// Workouts in the half-open 30 days before `workout` (excluding it) — same-type
    /// only by default, all types when `matchingTypeOnly` is false (the effort
    /// estimator prefers same-type but falls back across types) — read only from
    /// already-loaded snapshots. Pure — no fetch, no `Task` — so it is safe to call
    /// from a SwiftUI computed property. `isComplete` uses `loadedMonthKeys` (the true
    /// load signal), not `monthSnapshots` membership, which is seeded with a
    /// placeholder at launch and left populated after `clearWorkoutSnapshots`.
    func comparisonContext(for workout: WorkoutSummary, matchingTypeOnly: Bool = true) -> WorkoutComparisonContext {
        let calendar = Calendar.bodyGregorian
        guard let windowStart = calendar.date(byAdding: .day, value: -30, to: workout.startDate) else {
            return WorkoutComparisonContext(priorWorkouts: [], isComplete: false)
        }

        let keys = comparisonMonthKeys(for: workout, calendar: calendar)
        let isComplete = keys.allSatisfy { loadedMonthKeys.contains($0) }

        let priors = keys
            .compactMap { monthSnapshots[$0] }
            .flatMap { $0.days }
            .flatMap { $0.workouts }
            .filter { prior in
                (!matchingTypeOnly || prior.type == workout.type)
                    && prior.id != workout.id
                    && prior.startDate >= windowStart
                    && prior.startDate < workout.startDate
            }

        return WorkoutComparisonContext(priorWorkouts: priors, isComplete: isComplete)
    }

    /// Loads any month the 30-day comparison window overlaps that isn't cached yet.
    /// Call from `.task(id:)`, never from the synchronous `comparisonContext`.
    func ensureComparisonMonthsLoaded(for workout: WorkoutSummary) async {
        let keys = comparisonMonthKeys(for: workout, calendar: .bodyGregorian)
        for key in keys where !loadedMonthKeys.contains(key) {
            await loadMonthIfNeeded(month: key.month, year: key.year)
        }
    }

    /// Every month key the `[start - 30d, start)` window touches — up to 3 (a workout
    /// early in a month reaches back across two prior months).
    private func comparisonMonthKeys(for workout: WorkoutSummary, calendar: Calendar) -> [BodyWorkoutMonthKey] {
        guard let windowStart = calendar.date(byAdding: .day, value: -30, to: workout.startDate),
              var cursor = calendar.dateInterval(of: .month, for: windowStart)?.start,
              let endMonthStart = calendar.dateInterval(of: .month, for: workout.startDate)?.start else {
            return [BodyWorkoutMonthKey(date: workout.startDate, calendar: calendar)]
        }

        var keys: [BodyWorkoutMonthKey] = []
        while cursor <= endMonthStart {
            keys.append(BodyWorkoutMonthKey(date: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    func loadRecentWorkoutMonthsIfNeeded(date: Date = Date()) async {
        guard !isRefreshing, !needsInitialHealthDataLoad else {
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
        guard !needsInitialHealthDataLoad else {
            return false
        }

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
        guard !needsInitialHealthDataLoad else {
            return
        }

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
            healthDataNotice = String(localized: "Apple Health is not available on this device.")
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
            try await requestHealthKitAuthorization()

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
            Self.snapshotPersistQueue.async {
                HealthDashboardSnapshotStore.save(snapshotToSave)
            }
            authorizationState = .authorized
            markRefreshSucceeded(date: Date(), refreshedVitals: false)
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
            healthDataNotice = String(localized: "Apple Health is not available on this device.")
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
        // Fire-and-forget is safe here: a cache wipe flips
        // `needsInitialHealthDataLoad`, so the next refresh must come through
        // the overlay's user-initiated path, which clears the effort cache
        // again before fetching.
        Task { [engine] in
            await engine.clearSourceCache()
            await engine.clearWorkoutEffortCache()
        }
        persistedDaySamplesHydration = nil
        lastSuccessfulRefreshDate = nil
        authorizationState = .unknown
        healthDataNotice = String(localized: "Local cache cleared. Refresh to load Apple Health data again.")

        WorkoutSnapshotStore.delete()
        WorkoutSnapshotStore.deletePrevious()
        HealthDashboardSnapshotStore.delete()
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        HealthDashboardSnapshotStore.clearActivityRingBackfillCompleted()
        HealthWidgetSnapshotStore.delete()
        cacheDiskSizeBytes = 0
        BodyWidgetReloadCoalescer.shared.requestReload()
    }

    /// Expects the caller to have set `isRefreshing` (and to call
    /// `finishRefresh()` when done) before the first suspension.
    private func refreshRecentMonths(date: Date = Date(), intent: BodyWorkoutRefreshIntent = .userInitiated) async {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("RefreshRecentMonths")
        defer { BodyPerformanceSignposts.signposter.endInterval("RefreshRecentMonths", signpostState) }

        await hydratePersistedDaySamplesIfNeeded()
        await engine.setHealthTrendAnchorDate(date)

        let calendar = Calendar.bodyGregorian
        // On a passive resume only the current month refreshes. But when the
        // current wake cycle reaches back into the prior month (an evening
        // workout carried past midnight on the 1st), also refresh that month so
        // the activity drain reads fresh prior-month workouts rather than stale,
        // un-refreshed ones.
        let wakeCycleSleepEnd = healthSummary.sleep.stageSnapshot.dateInterval?.end
        let wakeCycleStart = Self.wakeCycleStart(now: date, sleepEnd: wakeCycleSleepEnd, calendar: calendar)
        let wakeCycleCrossesMonth = !calendar.isDate(wakeCycleStart, equalTo: date, toGranularity: .month)
        let monthCount: Int
        if intent == .passiveResume {
            monthCount = wakeCycleCrossesMonth ? 2 : 1
        } else {
            monthCount = Self.recentChartMonthCount
        }
        let keys = Self.recentMonthKeys(count: monthCount, from: date, calendar: calendar)
        let dashboardFetchSelection = BodyDashboardFetchSelection.load()
        let includesWorkouts = permissionSelection.includes(.workouts)
        if !includesWorkouts {
            clearWorkoutSnapshots(calendar: calendar)
        }

        // Explicit refreshes reconcile everything: drop the per-workout
        // effort/HR caches before any fetch starts so re-rated efforts and
        // edited workouts re-query (this also makes the dashboard's 180-day
        // training-load fetch re-ask effort for its whole window).
        if intent == .userInitiated {
            await engine.clearWorkoutEffortCache()
        }

        // Fetch the Workouts-tab months concurrently with source discovery and
        // the dashboard below, so the visible Home dashboard no longer waits
        // behind months of workout HR/effort fan-out. Workout queries are
        // date-only and don't read the source map, so they're independent.
        async let workoutRefresh: Void = {
            guard includesWorkouts else { return }
            try await self.refresh(
                monthKeys: keys,
                calendar: calendar,
                reusesCachedWorkoutHeartRate: intent == .passiveResume
            )
        }()

        do {
            // Source discovery must finish before any dashboard query — the
            // per-source predicate reads `healthSourcesByKind`, so racing it
            // would silently fetch all-source data for custom-source users.
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

            // Join the workout fetch. Its success gates the freshness timestamp:
            // a workout failure must re-run the full refresh on the next
            // activation instead of being skipped by the 5-minute warm-resume
            // shortcut, so don't `markRefreshSucceeded` unless workouts landed.
            try await workoutRefresh
            authorizationState = .authorized
            markRefreshSucceeded(date: date, refreshedVitals: true, publishesWatch: false)
            updateCurrentMonthSnapshot(date: date, calendar: calendar)
            await reapplyActivityReadinessAfterWorkouts(date: date, calendar: calendar)
            publishWatchSnapshot()
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
        await engine.setHealthTrendAnchorDate(nil)
    }

    /// Expects the caller to have set `isRefreshing` (and to call
    /// `finishRefresh()` when done) before the first suspension.
    private func refresh(
        month: Int,
        year: Int,
        calendar: Calendar,
        updatesHealthSummary: Bool,
        reusesCachedWorkoutHeartRate: Bool = false
    ) async {
        let refreshDate = Date()
        if updatesHealthSummary {
            await hydratePersistedDaySamplesIfNeeded()
            await engine.setHealthTrendAnchorDate(refreshDate)
        }

        let key = BodyWorkoutMonthKey(month: month, year: year)
        let includesWorkouts = permissionSelection.includes(.workouts)
        if !includesWorkouts {
            clearWorkoutSnapshots(calendar: calendar)
        }

        // Overlap the workout fetch with the dashboard fetch when one runs (the
        // `updatesHealthSummary == false` warm path has no dashboard, so this
        // just awaits the single month). See `refreshRecentMonths` for rationale.
        async let workoutRefresh: Void = {
            guard includesWorkouts else { return }
            try await self.refresh(
                monthKeys: [key],
                calendar: calendar,
                reusesCachedWorkoutHeartRate: reusesCachedWorkoutHeartRate
            )
        }()

        do {
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
            try await workoutRefresh
            authorizationState = .authorized
            markRefreshSucceeded(date: refreshDate, refreshedVitals: updatesHealthSummary, publishesWatch: false)
            updateCurrentMonthSnapshot(date: refreshDate, calendar: calendar)
            await reapplyActivityReadinessAfterWorkouts(date: refreshDate, calendar: calendar)
            publishWatchSnapshot()
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
        let needsActivityRingBackfill = !HealthDashboardSnapshotStore.loadActivityRingBackfillCompleted()

        let engine = self.engine
        await withTaskGroup(of: DashboardFetchUnit.self) { group in
            group.addTask {
                let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardSummary")
                defer { BodyPerformanceSignposts.signposter.endInterval("DashboardSummary", signpostState) }
                return .summary(await engine.fetchHealthSummary(calendar: calendar, selection: selection))
            }
            group.addTask {
                let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardTrends")
                defer { BodyPerformanceSignposts.signposter.endInterval("DashboardTrends", signpostState) }
                return .trends(
                    await engine.fetchHealthTrends(
                        calendar: calendar,
                        cachedTrends: cachedTrendsAtStart,
                        selection: selection
                    )
                )
            }
            group.addTask {
                let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardRings")
                defer { BodyPerformanceSignposts.signposter.endInterval("DashboardRings", signpostState) }
                if needsActivityRingBackfill {
                    return .rings(
                        await engine.fetchDashboardActivityRingBackfillHistory(calendar: calendar, selection: selection)
                    )
                }
                return .rings(await engine.fetchDashboardActivityRingHistory(calendar: calendar, selection: selection))
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
                    if needsActivityRingBackfill, !r.loadedMonthKeys.isEmpty {
                        // Success always echoes month keys; an empty result
                        // means the fetch errored or rings are excluded, so
                        // the backfill stays pending for a later refresh.
                        HealthDashboardSnapshotStore.saveActivityRingBackfillCompleted()
                    }
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
            healthDataNotice = String(localized: "Apple Health is not available on this device.")
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
            try await requestHealthKitAuthorization()
            try await refresh(monthKeys: keysToLoad, calendar: .bodyGregorian)
            authorizationState = .authorized
            markRefreshSucceeded(date: Date(), refreshedVitals: false)
            updateHealthDataNotice()
        } catch {
            handleRefreshError(error)
        }
    }

    private func refresh(
        monthKeys: Set<BodyWorkoutMonthKey>,
        calendar: Calendar,
        reusesCachedWorkoutHeartRate: Bool = false
    ) async throws {
        let orderedKeys = monthKeys.sortedByDate
        guard !orderedKeys.isEmpty else {
            return
        }

        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("WorkoutMonths")
        defer { BodyPerformanceSignposts.signposter.endInterval("WorkoutMonths", signpostState) }

        let engine = self.engine
        try await withThrowingTaskGroup(
            of: (BodyWorkoutMonthKey, [WorkoutSummary]).self
        ) { group in
            for key in orderedKeys {
                // Passive resumes hand the engine the month's cached summaries
                // so finished workouts' HR payloads can be reused (eligibility
                // is decided per workout in the engine); user-initiated paths
                // pass nothing and re-fetch HR for the whole month.
                let reusableSummariesByID: [UUID: WorkoutSummary]
                if reusesCachedWorkoutHeartRate, let cachedDays = monthSnapshots[key]?.days {
                    reusableSummariesByID = Dictionary(
                        cachedDays.flatMap(\.workouts).map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                } else {
                    reusableSummariesByID = [:]
                }
                group.addTask {
                    let workouts = try await engine.fetchWorkouts(
                        month: key.month,
                        year: key.year,
                        calendar: calendar,
                        reusableSummariesByID: reusableSummariesByID
                    )
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

    /// Permissions whose data feeds the Readiness score. Toggling one changes the
    /// readiness input set, so the frozen morning records — captured under the
    /// previous inputs — are dropped (they would otherwise keep overriding the
    /// recomputed history); fresh records re-accumulate from the next morning.
    nonisolated static let readinessInputPermissions: Set<BodyHealthPermission> = [
        .sleep,
        .heart,
        .bloodOxygen,
        .respiratory,
        .workouts,
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
        let now = Date()
        let sleepEnd = summary.sleep.stageSnapshot.dateInterval?.end
        let wakeTime = Self.freezeWakeTime(sleepEnd: sleepEnd, scoringDay: anchorDate, now: now, calendar: calendar)
        let todaysWorkouts = currentWakeCycleWorkouts(now: now, sleepEnd: sleepEnd, calendar: calendar)
        let recordedReadinessContext = readinessRecordContextSignature()
        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            let signpostState = BodyPerformanceSignposts.signposter.beginInterval("ReadinessRecompute")
            defer { BodyPerformanceSignposts.signposter.endInterval("ReadinessRecompute", signpostState) }
            let filtered = rawSnapshot.filteredWithoutReadinessRecompute(by: permissionSelection)
            guard recomputesReadiness else {
                return filtered
            }
            return filtered.recalculatingReadiness(
                on: anchorDate,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar,
                todaysWorkouts: todaysWorkouts,
                wakeTime: wakeTime,
                now: now,
                freezesRecordedReadiness: recomputesReadiness,
                recordedReadinessContext: recordedReadinessContext
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
        Self.snapshotPersistQueue.async {
            HealthDashboardSnapshotStore.save(snapshotToSave)
            HealthDashboardSnapshotStore.saveSecondarySelectionSignature(secondarySignature)
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
        saveHealthWidgetSnapshot()
    }

    /// A wake (sleep-end) older than this is treated as stale/missing — the drain
    /// window falls back to midnight so a days-old sleep summary can't span days.
    nonisolated static let maxWakeCycleSeconds: TimeInterval = 24 * 3_600

    /// Wake time valid for freezing the scoring day's morning record: the sleep
    /// session must have ended on the scoring day and not in the future. Otherwise
    /// `nil`, so the freeze uses its 10:00-local fallback — a stale multi-day-old
    /// sleep end must not anchor the freeze before that fallback.
    nonisolated static func freezeWakeTime(
        sleepEnd: Date?,
        scoringDay: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        guard let sleepEnd, sleepEnd <= now, calendar.isDate(sleepEnd, inSameDayAs: scoringDay) else {
            return nil
        }
        return sleepEnd
    }

    /// Start of the current wake cycle for the activity-drain window: the most
    /// recent sleep end when it is recent enough (so an evening workout's drain
    /// survives past midnight), otherwise midnight — so a stale multi-day-old
    /// sleep end can't make the window span days.
    nonisolated static func wakeCycleStart(now: Date, sleepEnd: Date?, calendar: Calendar) -> Date {
        if let sleepEnd, sleepEnd <= now, now.timeIntervalSince(sleepEnd) <= maxWakeCycleSeconds {
            return sleepEnd
        }
        return calendar.startOfDay(for: now)
    }

    /// Workouts done since the start of the current wake cycle, up to `now`.
    /// These drive the same-day readiness drain.
    private func currentWakeCycleWorkouts(
        now: Date,
        sleepEnd: Date?,
        calendar: Calendar
    ) -> [WorkoutSummary] {
        let cycleStart = Self.wakeCycleStart(now: now, sleepEnd: sleepEnd, calendar: calendar)
        return monthSnapshots.values
            .flatMap(\.days)
            .flatMap(\.workouts)
            .filter { $0.startDate >= cycleStart && $0.startDate <= now }
    }

    /// After the workout fetch lands, re-apply the activity drain + morning freeze
    /// to the live readiness using the now-complete workout snapshots, without a
    /// full series rebuild. The dashboard recompute earlier in a refresh runs
    /// before workouts are available (they fetch concurrently), so this catches
    /// today's just-finished session.
    private func reapplyActivityReadinessAfterWorkouts(date: Date, calendar: Calendar) async {
        guard permissionSelection.includes(.workouts) else {
            return
        }
        let now = Date()
        let sleepEnd = healthSummary.sleep.stageSnapshot.dateInterval?.end
        let wakeTime = Self.freezeWakeTime(sleepEnd: sleepEnd, scoringDay: date, now: now, calendar: calendar)
        // Reapply even with no current-cycle workouts: the main recompute may have
        // drained from stale workout snapshots (e.g. a workout was deleted), so the
        // empty list must flow through to let the score rebound.
        let todaysWorkouts = currentWakeCycleWorkouts(now: now, sleepEnd: sleepEnd, calendar: calendar)

        let updated = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        ).reapplyingActivityReadiness(
            on: date,
            idealSleepDuration: Self.storedIdealSleepDuration(),
            calendar: calendar,
            todaysWorkouts: todaysWorkouts,
            wakeTime: wakeTime,
            now: now,
            freezesRecordedReadiness: true,
            recordedReadinessContext: readinessRecordContextSignature()
        )
        // Only persist when the reapply actually moved the readiness the widget
        // shows (or recorded a new morning freeze). On a normal refresh with no
        // current-cycle workout the value is unchanged and the preceding refresh
        // publish already shipped this state, so skip the duplicate save and
        // widget push. The watch publishes once from the caller after this
        // returns, so it ships the post-drain value rather than a stale one.
        let readinessChanged = updated.summary.readiness != healthSummary.readiness
            || updated.trends.readiness != healthTrends.readiness
            || updated.trends.recordedReadiness != healthTrends.recordedReadiness
        healthSummary = updated.summary
        healthTrends = updated.trends
        guard readinessChanged else {
            return
        }

        let snapshotToSave = HealthDashboardSnapshot(
            summary: updated.summary,
            trends: updated.trends,
            activityRingHistory: activityRingHistory
        )
        Self.snapshotPersistQueue.async {
            HealthDashboardSnapshotStore.save(snapshotToSave)
        }
        saveHealthWidgetSnapshot()
    }

    /// Internal (not private) so tests can assert the TTL gating below without
    /// a HealthKit round trip.
    func markRefreshSucceeded(date: Date, refreshedVitals: Bool, publishesWatch: Bool = true) {
        // `lastSuccessfulRefreshDate` arms the 5-minute dashboard-freshness TTL
        // (`syncWhenAppBecomesActive`, and the cold-start path that restores the
        // persisted value), so only refreshes that actually refetched the
        // dashboard vitals may set it. Lazy history loads (month paging, older
        // ring months), single-metric refreshes, and workout-only warm resumes
        // must not re-arm it — otherwise paging history or resuming repeatedly
        // keeps the TTL fresh and the vitals refresh is skipped indefinitely.
        // Those paths keep their own throttling (`lastAppEntrySyncDate`,
        // `loadedMonthKeys`/`loadingMonthKeys`), which this does not feed.
        if refreshedVitals {
            lastSuccessfulRefreshDate = date
            HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(date)
            lastVitalsRefreshDate = date
        }
        // The full-refresh paths suppress this and publish once after the
        // post-workout reapply, so the watch ships the drained value rather than
        // the pre-drain one. Other callers (single-metric, warm resume) publish
        // here because no reapply follows.
        if publishesWatch {
            publishWatchSnapshot()
        }
    }

    /// Pushes the latest metrics to the paired Apple Watch. Best-effort: the
    /// build is pure and `send` never blocks the refresh. Publishing from the
    /// common funnel (including workout-only paths) keeps the watch's values
    /// current, but `lastRefreshDate` carries the last *vitals* refresh — a
    /// workout-only refresh must not look fresh to the watch, or it would
    /// suppress the watch's own stale-triggered live HR/HRV refresh.
    func publishWatchSnapshot() {
        // Capture on the main actor exactly what the builder + send read today,
        // then build off-actor on the serial persist queue and hop back to `send`
        // — mirroring `saveHealthWidgetSnapshot`. `now` stamps `generatedAt` at
        // capture time so the queue's FIFO order is the send order, and the
        // permission value is paired at capture time so a queued build can't ship
        // a newer selection.
        let summary = healthSummary
        let trends = healthTrends
        let lastRefreshDate = lastVitalsRefreshDate
        let permissionSelection = permissionSelection
        let temperatureUnitPreference = HealthWidgetSnapshotBuilder.storedTemperatureUnitPreference()
        let idealSleepDuration = Self.storedIdealSleepDuration()
        let showSleepScore = HealthWidgetSnapshotBuilder.storedShowSleepScore()
        let now = Date()
        let permissionRawValue = BodyHealthPermissionSelection.load().rawValue

        Self.snapshotPersistQueue.async {
            var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
                summary: summary,
                trends: trends,
                lastRefreshDate: lastRefreshDate,
                permissionSelection: permissionSelection,
                temperatureUnitPreference: temperatureUnitPreference,
                idealSleepDuration: idealSleepDuration,
                showSleepScore: showSleepScore,
                now: now
            )
            snapshot.source = "phone"
            Task { @MainActor in
                WatchConnectivityPublisher.shared.send(snapshot, permissionRawValue: permissionRawValue)
            }
        }
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

        Self.snapshotPersistQueue.async {
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
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }
        }
    }

    /// Serializes dashboard and widget disk writes so an earlier (pre-drain) save
    /// can never land after a later (post-drain) one and leave disk or widget
    /// state stale. Enqueue order on the main actor is the write order (FIFO).
    private static let snapshotPersistQueue = DispatchQueue(label: "com.body.snapshotPersist", qos: .utility)

    /// Signature of the readiness input context: which readiness permissions are
    /// enabled, the primary source chosen for each readiness input kind, and
    /// whether same-name sources are combined. Frozen morning records are tagged
    /// with this; when it changes the records are dropped so a recompute under
    /// the new inputs is authoritative (see `recalculatingReadiness`). All three
    /// inputs persist independently of the snapshot, so a change is still
    /// detected after a failed refresh or a relaunch.
    nonisolated static func readinessRecordContextSignature(
        permissionSelection: BodyHealthPermissionSelection,
        healthDataSourceSelection: BodyHealthDataSourceSelection,
        combinesHealthDataSourcesByName: Bool,
        idealSleepDuration: TimeInterval
    ) -> String {
        let permissions = readinessInputPermissions
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue):\(permissionSelection.includes($0) ? "1" : "0")" }
            .joined(separator: ",")
        let sources = readinessInputMetricKinds
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue):\(healthDataSourceSelection.option(for: $0).id)" }
            .joined(separator: ",")
        // The sleep-duration goal feeds the readiness sleep factor, so a goal
        // change makes the frozen morning records stale. Encode the effective
        // (clamped) goal minutes so changing it drops and recomputes them.
        let sleepGoalMinutes = Int((idealSleepDuration / 60).rounded())
        return "p[\(permissions)];s[\(sources)];c[\(combinesHealthDataSourcesByName ? "1" : "0")];g[\(sleepGoalMinutes)]"
    }

    private func readinessRecordContextSignature() -> String {
        Self.readinessRecordContextSignature(
            permissionSelection: permissionSelection,
            healthDataSourceSelection: healthDataSourceSelection,
            combinesHealthDataSourcesByName: combinesHealthDataSourcesByName,
            idealSleepDuration: Self.storedIdealSleepDuration()
        )
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
        let recordedReadinessContext = readinessRecordContextSignature()

        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            rawSnapshot.filtered(
                by: permissionSelection,
                idealSleepDuration: idealSleepDuration,
                recordedReadinessContext: recordedReadinessContext
            )
        }.value

        healthSummary = filteredSnapshot.summary
        healthTrends = filteredSnapshot.trends
        activityRingHistory = filteredSnapshot.activityRingHistory
        loadedActivityRingMonthKeys = Set(filteredSnapshot.activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))

        if !permissionSelection.includes(.workouts) {
            clearWorkoutSnapshots()
        } else if !permissionSelection.includes(.workoutMetrics) {
            sanitizeWorkoutMetricsSnapshots()
        }

        if !permissionSelection.includes(.activityRings) {
            // The filtered save below purges the cached ring history, so the
            // one-shot backfill marker must fall with it — otherwise
            // re-enabling rings resumes recent-months-only fetches and the
            // ten-year history never rebuilds.
            HealthDashboardSnapshotStore.clearActivityRingBackfillCompleted()
        }

        Self.snapshotPersistQueue.async {
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

        // The in-memory clear above leaves the App Group JSON untouched, but the
        // widget re-reads it via `loadCurrentOrPreviousIfEmpty()` and the app
        // re-reads it on cold start — so rewrite both persisted month files
        // emptied too. This clears the workout data at rest on opt-out instead
        // of leaving it for the widget to re-render, mirroring
        // `sanitizeWorkoutMetricsSnapshots`. Preserving each file's month
        // identity and `generatedAt` keeps the rewrite change-deduped, so the
        // repeated clears on refresh paths while the permission stays off don't
        // rewrite disk or reload widgets again. Route through the persist queue
        // so this load-modify-write can't interleave with a concurrent refresh
        // save, and request the widget reload only after the wipe lands
        // (a pre-wipe reload would rebuild the widget from the un-wiped file).
        Self.snapshotPersistQueue.async {
            func emptied(_ snapshot: WorkoutMonthSnapshot) -> WorkoutMonthSnapshot {
                WorkoutMonthSnapshot.make(
                    month: snapshot.month,
                    year: snapshot.year,
                    workouts: [],
                    calendar: calendar,
                    generatedAt: snapshot.generatedAt
                )
            }
            var widgetReloadNeeded = false
            if let current = WorkoutSnapshotStore.load(),
               WorkoutSnapshotStore.save(emptied(current)) {
                widgetReloadNeeded = true
            }
            if let previous = WorkoutSnapshotStore.loadPrevious(),
               WorkoutSnapshotStore.savePrevious(emptied(previous)) {
                widgetReloadNeeded = true
            }
            if widgetReloadNeeded {
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }
        }
    }

    /// Strips the Workout Metrics detail fields (VO₂max, power, both cadences, swim
    /// strokes) from every cached summary when the user disables `.workoutMetrics`,
    /// so already-fetched values stop surfacing in workout detail without a refetch.
    /// Mirrors `clearWorkoutSnapshots` (in-memory rebuild + widget reload); loaded
    /// month keys are kept since the months stay loaded — only the metrics drop.
    private func sanitizeWorkoutMetricsSnapshots(calendar: Calendar = .bodyGregorian) {
        snapshot = snapshot.removingWorkoutMetrics(calendar: calendar)
        monthSnapshots = monthSnapshots.mapValues { $0.removingWorkoutMetrics(calendar: calendar) }

        // The in-memory strip above leaves the App Group JSON untouched, but the
        // widget reads it via `loadCurrentOrPreviousIfEmpty()` and the app
        // re-reads it on cold start — so rewrite both persisted month files
        // stripped too. This clears the data at rest on opt-out instead of
        // waiting for the next refresh to overwrite the current-month file.
        // Route through the persist queue so this load-modify-write can't
        // interleave with a concurrent refresh save and resurrect the stripped
        // metrics, and request the widget reload only after the rewrite lands
        // (otherwise the widget can rebuild from the un-stripped file first).
        Self.snapshotPersistQueue.async {
            var widgetReloadNeeded = false
            if let current = WorkoutSnapshotStore.load(),
               WorkoutSnapshotStore.save(current.removingWorkoutMetrics(calendar: calendar)) {
                widgetReloadNeeded = true
            }
            if let previous = WorkoutSnapshotStore.loadPrevious(),
               WorkoutSnapshotStore.savePrevious(previous.removingWorkoutMetrics(calendar: calendar)) {
                widgetReloadNeeded = true
            }
            if widgetReloadNeeded {
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }
        }
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

        // Route through the shared persist queue (not a bare `Task.detached`) so
        // two successive refreshes' month saves keep FIFO enqueue order — an
        // earlier save must never land after a later one and stale the widget.
        Self.snapshotPersistQueue.async {
            var widgetReloadNeeded = WorkoutSnapshotStore.save(snapshotToSave)
            if let previousSnapshotToSave,
               WorkoutSnapshotStore.savePrevious(previousSnapshotToSave) {
                widgetReloadNeeded = true
            }
            if widgetReloadNeeded {
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
    }

    private func updateHealthDataNotice() {
        guard !permissionSelection.enabledPermissions.isEmpty else {
            healthDataNotice = String(localized: "All Apple Health data permissions are turned off in Settings.")
            return
        }

        guard snapshot.workoutCount == 0, healthSummary.isEmpty, activityRingHistory.isEmpty else {
            healthDataNotice = nil
            return
        }

        healthDataNotice = String(localized: "No Apple Health data was found. If you expected data, check Body's permissions in the Health app.")
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
        BodyHealthReadTypes.readObjectTypes(for: selection)
    }


    private func fetchHealthDataSourceOptions(calendar: Calendar) async {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("SourceOptions")
        defer { BodyPerformanceSignposts.signposter.endInterval("SourceOptions", signpostState) }

        if let nextOptionsByKind = await engine.fetchHealthDataSourceOptions(calendar: calendar) {
            healthDataSourceOptionsByKind = nextOptionsByKind
        }
    }


    // Forward to the shared `BodySleepSampleParser` (Body + BodyWatch) so the
    // watch and iOS compute sleep duration identically. Signatures kept for
    // existing callers + tests.
    nonisolated static func mergedSleepDuration(intervals: [(start: Date, end: Date)]) -> TimeInterval {
        BodySleepSampleParser.mergedSleepDuration(intervals: intervals)
    }

    nonisolated static func sleepDuration(from samples: [HKCategorySample]) -> TimeInterval {
        BodySleepSampleParser.sleepDuration(from: samples)
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
    case workoutNotFound
    case workoutEffortUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return String(localized: "Apple Health access was not granted.")
        case .authorizationStatusUnknown:
            return String(localized: "Apple Health access could not be confirmed.")
        case .workoutNotFound:
            return String(localized: "That workout could not be found in Apple Health.")
        case .workoutEffortUnavailable:
            return String(localized: "Workout effort isn't available on this device.")
        }
    }
}
