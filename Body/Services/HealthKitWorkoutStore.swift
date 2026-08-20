//
//  HealthKitWorkoutStore.swift
//  Body
//

import Foundation
import HealthKit
import WidgetKit
import os

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
    /// Device-local user renames keyed by HealthKit workout UUID. Persisted in
    /// `UserDefaults` as a `[String: String]` (UUID string → name); nothing is
    /// written back to HealthKit.
    @Published private(set) var workoutCustomNames: [UUID: String]
    @Published private(set) var healthSummary: HealthSummarySnapshot = .empty
    /// Primary-source + permission signature captured when `healthSummary` was
    /// last published by a full dashboard refresh. A failed summary leaf reuses
    /// the cached value only while this still matches the current selection, so
    /// switching source/permission never resurrects stale other-source data.
    /// In-memory only (nil on cold start → conservative empty-on-failure).
    private var healthSummaryPrimarySignature: String?
    @Published private(set) var healthTrends: HealthTrendSnapshot = .empty
    @Published private(set) var activityRingHistory: ActivityRingHistorySnapshot = .empty
    @Published private(set) var permissionSelection: BodyHealthPermissionSelection
    @Published private(set) var healthDataSourceSelection: BodyHealthDataSourceSelection
    @Published private(set) var secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection
    @Published private(set) var combinesHealthDataSourcesByName: Bool
    /// User-created merged sources (Body Pro). Kept verbatim when the
    /// entitlement lapses — every read path neutralizes a `custom:` selection
    /// to All Sources instead, so re-subscribing restores the user's setup.
    @Published private(set) var customHealthSourceGroups: [BodyCustomHealthSourceGroup]
    /// Every individual source discovered for ANY kind — the membership pool
    /// the custom-source editor picks from. Refreshed by
    /// `fetchHealthDataSourceOptions`, empty until discovery first runs.
    @Published private(set) var discoveredIndividualHealthSources: [BodyDiscoveredHealthSource] = []
    @Published private(set) var healthDataSourceOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
    /// Per kind, the custom group ids that registered a non-empty source bucket
    /// in the engine — mirrored here because the store's resolved-option
    /// accessors are synchronous while the engine is an actor. A kind is ABSENT
    /// (not empty) until its discovery succeeds, which the resolution below
    /// reads as "keep the selection" exactly like the engine does (H4).
    private var customSourceIDsWithDataByKind: [HealthMetricKind: Set<String>] = [:]
    @Published private(set) var healthDataNotice: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSuccessfulRefreshDate: Date?
    /// Count of user-visible refreshes — the three paths that set `isRefreshing`
    /// (foreground/vitals, workout month, single metric) — that completed with a
    /// genuine fetch (no query failure, and at least one HealthKit query actually
    /// ran). Advances only via `markRefreshSucceeded(advancesSyncBadge: true)`
    /// when its `ranQueries` gate holds; lazy month/ring history loads run
    /// WITHOUT `isRefreshing` and never touch it, and a permission-disabled
    /// metric or workout-month pull that queried nothing doesn't advance it
    /// either. The sync badge
    /// captures this when syncing starts and, on the falling edge, confirms
    /// "Health data updated" only if it advanced — so a failed refresh, or a
    /// background page-in that lands during one, can't make it falsely confirm.
    @Published private(set) var syncBadgeSuccessCount = 0
    /// Date of the last refresh that re-fetched the dashboard vitals (not just
    /// workouts or ring history). Carried in the watch snapshot so the watch's
    /// staleness logic isn't reset by workout-only refreshes. Doubles as the
    /// phone→watch compute seed's `dataThrough` watermark (Phase 3 of the
    /// on-watch realtime compute plan) — it already advances ONLY when a full
    /// dashboard refresh lands cleanly, which is exactly the data-coverage
    /// guarantee `dataThrough` needs.
    private var lastVitalsRefreshDate: Date?
    /// When readiness was last RE-DERIVED from freshly-fetched inputs. Distinct
    /// from `lastVitalsRefreshDate`, which advances only on a clean full
    /// dashboard refresh: a workout-only refresh (`refreshWorkoutMonth`, warm
    /// resume) re-runs the workout fetch and
    /// `reapplyActivityReadinessAfterWorkouts`, genuinely moving readiness
    /// while the vitals watermark stands still. The watch stamps readiness from
    /// THIS date (`publishWatchSnapshot`'s `perKindDataAsOf`), so a
    /// workout-only push's fresher readiness isn't presented under a stale
    /// timestamp and beaten by an older watch-computed value in
    /// `WatchComputeMerge.merging`'s per-metric compare.
    private var lastReadinessComputeDate: Date?
    /// When the Training Load summary/series were last RE-DERIVED from a fresh
    /// workout fetch. Deliberately SEPARATE from `lastReadinessComputeDate`:
    /// the workout-only reapply path re-drains readiness but does NOT recompute
    /// Training Load (that only happens in the dashboard fetch, gated on the
    /// fetch selection's `.trainingLoad` bit) — advancing a joint watermark
    /// there would label a stale Training Load as freshly computed and let it
    /// overwrite a newer watch-computed value in the per-metric merge.
    private var lastTrainingLoadComputeDate: Date?
    /// Per-kind watermark for the OTHER watch metrics a single-metric detail
    /// pull can refresh (HR, HRV, resting HR, sleep, skin temp), keyed by
    /// `WatchMetricKindKey` string (== `HealthMetricKind.rawValue`, pinned by
    /// `ProjectConfigurationTests`). Without it a clean detail pull publishes
    /// the freshly fetched value under the OLD full-refresh stamp
    /// (`lastVitalsRefreshDate` deliberately doesn't advance on a
    /// `refreshedVitals: false` refresh), and a watch that computed that kind
    /// locally in between keeps its older value in the freshest-wins merge.
    private var lastMetricPullDates: [String: Date] = [:]
    /// The phone's discovered source universe per compute kind (see
    /// `HealthKitFetchEngine.watchComputeExpectedSourceIDs`), cached at each
    /// source-options fetch and carried in the compute seed so the watch can
    /// validate an All-Sources read against it.
    private var cachedExpectedSourceIDsByKind: [String: [String]] = [:]
    /// Dense day-indexed Training Load loads for the phone→watch compute seed,
    /// refreshed alongside a clean full dashboard refresh whose fetch selection
    /// included Training Load (see `updateCachedComputeTrainingLoadSeedIfNeeded`)
    /// and after a Training Load detail pull / effort-edit refresh. `nil` until
    /// the first such refresh this session (or if Workouts is disabled);
    /// `publishWatchSnapshot` simply omits Training Load from the seed while
    /// nil — `dataThrough` (from `lastVitalsRefreshDate`, not this property)
    /// is what gates whether a seed is sent at all (cold start).
    ///
    /// `through` is the loads' own data-coverage watermark, carried in the seed
    /// (`WatchComputeSeed.trainingLoadDataThrough`) because it can lag the
    /// seed's overall `dataThrough`: a full refresh with the Training Load and
    /// Readiness cards hidden advances `dataThrough` but deliberately skips the
    /// load rebuild (cost gate). The watch refuses to replay loads whose
    /// coverage no longer reaches its delta window — otherwise the uncovered
    /// days would be silently zero-filled as fabricated rest days.
    private var cachedComputeTrainingLoadSeed: (startDay: Date, loads: [Double], through: Date)?

    /// Sole writer of a POPULATED `cachedComputeTrainingLoadSeed`: persists the
    /// same value (`HealthDashboardSnapshotStore`) so a relaunch — whose
    /// restored `dataThrough` lets a workout-only publish ship a seed before
    /// any full Training Load refresh has run — carries the loads forward
    /// instead of replacing the watch's complete seed with one missing them.
    private func setCachedComputeTrainingLoadSeed(startDay: Date, loads: [Double], through: Date) {
        cachedComputeTrainingLoadSeed = (startDay: startDay, loads: loads, through: through)
        HealthDashboardSnapshotStore.saveWatchTrainingLoadSeed(startDay: startDay, loads: loads, through: through)
    }
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
    /// Backing store for `workoutCustomNames` — injectable so tests can use an
    /// isolated suite.
    private let customNameDefaults: UserDefaults
    /// Session cache of resolved workout routes keyed by workout UUID. A cached
    /// `.some(nil)` means "confirmed no readable route", so non-route workouts
    /// aren't re-queried and the city label isn't re-geocoded when a detail
    /// sheet is reopened. HealthKit read access is opaque, so authorization gates
    /// clear the cache before any stale positive or negative route result sticks.
    private var routeCache: [UUID: WorkoutRoute?] = [:]
    /// Session cache of the cheap `HKWorkoutRoute` presence probe, keyed by workout
    /// UUID. Separate from `routeCache` because the probe can answer "yes" long before
    /// the coordinates exist, and kept consistent with it: the `< 2 coordinates` branch
    /// of the load writes `false` here too, so a workout whose route samples exist but
    /// yield no drawable line never reserves the detail hero's band a second time.
    /// Cleared wherever `routeCache` is, for the same opaque-authorization reason.
    private var routePresenceCache: [UUID: Bool] = [:]
    /// Session cache of a workout's raw distance samples keyed by UUID, feeding the
    /// detail Splits section. Empty results are cached only for workouts that ended
    /// more than 24 h ago; recent workouts may still be syncing from the watch, so
    /// their empty reads are retried on the next sheet open.
    private var distanceSampleCache: [UUID: WorkoutSplitData] = [:]
    /// Session cache of a workout's per-bucket series inputs (pace/speed, cadence,
    /// stride length, running form) keyed by UUID, feeding the detail chart cards.
    /// Cached only for workouts that ended more than 24 h ago (a recent workout may
    /// still be syncing its samples from the watch, and caching now would pin the
    /// cards to a partial result for the rest of the session), plus: a bundle with a
    /// failed metric
    /// read is never cached, so a transient error can't hide a card all session.
    ///
    /// The 24 h settle rule is stricter than the splits cache's "cache anything
    /// non-empty" because this is a MULTI-FAMILY bundle: cadence can be synced while
    /// stride length isn't, so a successful read can still be partial without any
    /// query failing. A single-result read like splits has no such half-state — it's
    /// either there or empty — so it only needs the settle rule for the empty case.
    private var metricSeriesCache: [UUID: WorkoutMetricSeriesData] = [:]
    /// Session cache of a workout's 1-minute heart-rate recovery keyed by UUID,
    /// feeding the detail tile. A confirmed absence (`nil`) is cached too, but —
    /// same settle rule as above — only for workouts that ended more than 24 h ago:
    /// the watch writes the recovery sample a minute after the workout ends, so a
    /// just-finished workout must be re-read on the next sheet open.
    private var heartRateRecoveryCache: [UUID: Double?] = [:]
    /// In-flight (or finished) disk hydrations of the persisted per-workout detail
    /// snapshot, keyed by workout UUID. A task map rather than a "done" flag Set
    /// because the detail sheet fires the route probe, the route load, the series
    /// load and the recovery load concurrently: a flag written only on completion
    /// would let three of them hydrate in parallel, and a flag written up front
    /// would let them skip past a hydration that hasn't read the file yet. Awaiting
    /// the shared task gives every entry point the seeded caches exactly once.
    private var detailHydrations: [UUID: Task<WorkoutDetailSnapshot?, Never>] = [:]
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
        initialSnapshot: WorkoutMonthSnapshot = WorkoutSnapshotStore.loadOrEmpty(),
        initialHealthDashboardSnapshot: HealthDashboardSnapshot = HealthDashboardSnapshotStore.loadOrEmpty(),
        initialSummaryContextSignature: String? = HealthDashboardSnapshotStore.loadSummaryContextSignature(),
        initialPermissionSelection: BodyHealthPermissionSelection = BodyHealthPermissionSelection.load(),
        initialHealthDataSourceSelection: BodyHealthDataSourceSelection = BodyHealthDataSourceSelection.load(),
        initialSecondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection = BodyHealthSecondaryDataSourceSelection.load(),
        initialCombinesHealthDataSourcesByName: Bool = UserDefaults.standard.bool(forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey),
        initialCustomHealthSourceGroups: [BodyCustomHealthSourceGroup] = HealthKitWorkoutStore.loadCustomHealthSourceGroups(),
        customNameDefaults: UserDefaults = .standard,
        date: Date = Date()
    ) {
        self.customNameDefaults = customNameDefaults
        workoutCustomNames = Self.loadWorkoutCustomNames(from: customNameDefaults)
        permissionSelection = initialPermissionSelection
        healthDataSourceSelection = initialHealthDataSourceSelection
        secondaryHealthDataSourceSelection = initialSecondaryHealthDataSourceSelection
        combinesHealthDataSourcesByName = initialCombinesHealthDataSourcesByName
        customHealthSourceGroups = initialCustomHealthSourceGroups
        // Composed from the loaded groups rather than the instance helper: the
        // three signature consumers below run before `self` is fully
        // initialized. `customSourceGroupsSignatureSuffix(for:)` is the one
        // composition point, so the strings stay byte-identical.
        let initialCustomSourceGroupsSuffix = Self.customSourceGroupsSignatureSuffix(for: initialCustomHealthSourceGroups)
        engine = HealthKitFetchEngine(
            permission: initialPermissionSelection,
            healthDataSourceSelection: initialHealthDataSourceSelection,
            secondaryHealthDataSourceSelection: initialSecondaryHealthDataSourceSelection,
            combinesHealthDataSourcesByName: initialCombinesHealthDataSourcesByName,
            customHealthSourceGroups: initialCustomHealthSourceGroups
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
            idealSleepDuration: initialIdealSleepDuration,
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages(),
            customSourceGroupsSignatureSuffix: initialCustomSourceGroupsSuffix
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
        } else {
            // The persisted snapshot can still carry permission-gated fields
            // (VO₂max/power/cadence/strokes under Workout Metrics, heart-rate
            // recovery under Heart), so strip them here too — otherwise they
            // reappear on launch before the next refresh rebuilds the summary.
            var sanitized = initialSnapshot
            if !initialPermissionSelection.includes(.workoutMetrics) {
                sanitized = sanitized.removingWorkoutMetrics()
            }
            if !initialPermissionSelection.includes(.heart) {
                sanitized = sanitized.removingHeartRateRecovery()
            }
            startingSnapshot = sanitized
        }
        snapshot = startingSnapshot
        monthSnapshots = [
            BodyWorkoutMonthKey(month: startingSnapshot.month, year: startingSnapshot.year): startingSnapshot
        ]
        healthSummary = filteredHealthDashboardSnapshot.summary
        // Restore the summary-reuse gate from the persisted envelope (H2a) so a
        // cold-start failed summary leaf can reuse the hydrated value only while
        // the current selection/prefs still match the ones it was saved under.
        healthSummaryPrimarySignature = initialSummaryContextSignature
        let storedSecondarySignature = HealthDashboardSnapshotStore.loadSecondarySelectionSignature()
        if storedSecondarySignature != initialSecondaryHealthDataSourceSelection.signature + initialCustomSourceGroupsSuffix {
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
        // Restore the compute seed's data watermark from the SAME persisted
        // value: it was written only when a clean full refresh landed — the
        // exact condition under which `lastVitalsRefreshDate` itself advances
        // (`nextLastVitalsRefreshDate`), so the two are equal at every persist
        // point. Without this, a relaunch inside the 5-minute TTL performs only
        // a workout refresh, `dataThrough` stays nil, and a settings-only
        // republish ships NO seed and NO settings signature — leaving the
        // watch recomputing with an obsolete sleep goal / unit / score setting
        // until the next full refresh happens to run. The restored dashboard
        // summary/trends this seed would be built from were persisted by that
        // same refresh, so the coverage claim stays honest.
        lastVitalsRefreshDate = lastSuccessfulRefreshDate
        // Restore the seed's expected-source coverage with the same lifetime:
        // the restored `dataThrough` above lets a publish attach a seed BEFORE
        // this session runs source discovery, and a seed carrying no
        // expected-source lists licenses the watch's unfiltered All-Sources
        // reads — silently reopening the incomplete-source-subset divergence
        // the coverage check exists to prevent.
        cachedExpectedSourceIDsByKind = HealthDashboardSnapshotStore.loadWatchExpectedSourceIDs()
        // And the seed's Training Load piece: without it, a workout-only
        // publish inside the refresh TTL ships a seed whose Training Load
        // arrays are nil — replacing the watch's complete seed with one it
        // can't recompute Training Load from, indefinitely if the phone's
        // Training Load / Readiness cards are hidden (the rebuild is
        // cost-gated on the dashboard actually fetching Training Load). The
        // persisted `through` keeps the watch's coverage gate honest.
        cachedComputeTrainingLoadSeed = HealthDashboardSnapshotStore.loadWatchTrainingLoadSeed()
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
            Task { @MainActor in
                // An entitlement flip has to invalidate, not just refetch: the full
                // refresh re-ships the cached day samples verbatim rather than
                // re-querying them, so the previous comparison series would survive
                // on the trend and day charts.
                //
                // Wait out any in-flight refresh first — clearing ahead of it would
                // be undone, and the refetch below would bounce off
                // `requestAuthorizationAndRefresh`'s `isRefreshing` guard. Then
                // hydrate BEFORE clearing so the sidecar's primary scope is restored
                // and its payload is memoized, because the clear has to reach that
                // memo too (see `invalidateMemoizedComparisonDaySamples`).
                await self.awaitNextRefreshCompletion()
                await self.hydratePersistedDaySamplesIfNeeded()
                self.healthTrends = self.healthTrends.clearingSecondarySeries()
                await self.invalidateMemoizedComparisonDaySamples()
                self.persistDaySampleSidecar()
                // Comparison day samples are deliberately NOT refetched here — they
                // stay lazy (a single kind is ~50k raw samples). Leaving the cache
                // genuinely empty is what makes
                // `loadIntradayMetricSamplesIfNeeded` pull the full window instead
                // of incrementally topping up pre-flip points. A metric detail that
                // is already on screen when the flip lands re-runs that loader
                // itself: its `.task` is keyed on entitlement, because the paywall
                // is a sheet over that view and never unmounts it.
                await self.requestAuthorizationAndRefresh()
            }
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
                + WorkoutDetailSnapshotStore.totalDiskSizeBytes()
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
                // training-load fetch.
                await engine.clearWorkoutEffortCache()
            }
            await fetchHealthDataSourceOptions(calendar: calendar)
            let existing = HealthDashboardSnapshot(
                summary: healthSummary,
                trends: healthTrends,
                activityRingHistory: activityRingHistory
            )
            let capturedDaySampleSignatures = currentDaySampleSignatures()
            let metricFetch = await engine.fetchHealthDashboardSnapshot(
                for: kind,
                calendar: calendar,
                existing: existing,
                idealSleepDuration: Self.storedIdealSleepDuration()
            )
            let nextSummary = healthSummary.replacingMetric(kind, with: metricFetch.snapshot.summary)
            // The day-sample fetches inside the engine are incremental: they merge
            // onto the `existing` cache captured above. The source mutators push the
            // new selection into the engine BEFORE they wait out this refresh (see
            // `updateSecondaryHealthDataSource`), so a switch landing mid-fetch would
            // have the engine query the NEW source and merge it onto the OLD source's
            // cached points — and `updateHealthDashboardSnapshot` would persist that
            // mixed series stamped with the NEW signature, which `scopedForHydration`
            // then accepts forever. Drop the fetched day samples in that case; the
            // mutator clears and refetches them right after this refresh releases.
            let fetchedTrends = currentDaySampleSignatures() == capturedDaySampleSignatures
                ? metricFetch.snapshot.trends
                : metricFetch.snapshot.trends.strippingDaySamples()
            let nextTrends = healthTrends.replacingMetric(kind, with: fetchedTrends)
            await updateHealthDashboardSnapshot(
                summary: nextSummary,
                trends: nextTrends,
                activityRingHistory: activityRingHistory,
                recomputesReadiness: Self.readinessInputMetricKinds.contains(kind)
            )
            authorizationState = .authorized
            if !metricFetch.hadQueryFailure, metricFetch.ranQueries {
                // A clean metric-only pull genuinely re-derived readiness (any
                // readiness-input kind triggers the recompute above) and — for
                // Training Load — the trend/summary themselves. Advance the
                // watch watermarks BEFORE `markRefreshSucceeded` publishes, or
                // the freshly recomputed phone result ships under the OLD
                // stamps and a watch compute that ran since would beat it.
                // (`ranQueries` false means the permission is off and nothing
                // was actually re-derived — nothing to re-stamp.)
                if Self.readinessInputMetricKinds.contains(kind) {
                    lastReadinessComputeDate = date
                }
                // A watch-displayed vitals kind pulled directly gets its own
                // per-kind stamp too, so the freshly fetched value doesn't
                // publish under the stale full-refresh date and lose to an
                // older watch-computed value in the per-metric merge.
                if Self.watchVitalsPullKinds.contains(kind) {
                    lastMetricPullDates[kind.rawValue] = date
                }
                if kind == .trainingLoad {
                    lastTrainingLoadComputeDate = date
                    // The effort-edit path (`refreshAfterWrite(.trainingLoad)`)
                    // lands here too: rebuild the seeded daily loads from the
                    // fetch this pull just memoized, so the watch replays the
                    // post-edit efforts instead of the pre-edit array.
                    if let seed = await engine.trainingLoadDailyLoadSeed(calendar: calendar) {
                        setCachedComputeTrainingLoadSeed(startDay: seed.startDay, loads: seed.loads, through: date)
                    }
                }
            }
            // A metric pull whose query failed preserved the cached values
            // (nothing fetched), so pass the real outcome — the badge must not
            // confirm "updated" on a failed fetch. `ranQueries` is false when the
            // metric's permission is disabled (or a readiness recompute), so a
            // pull that never queried HealthKit doesn't confirm either.
            markRefreshSucceeded(
                date: date,
                refreshedVitals: false,
                hadQueryFailure: metricFetch.hadQueryFailure,
                advancesSyncBadge: true,
                ranQueries: metricFetch.ranQueries
            )
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

    // MARK: - Custom workout names

    nonisolated static let workoutCustomNamesKey = "workoutCustomNames"

    nonisolated static func loadWorkoutCustomNames(from defaults: UserDefaults) -> [UUID: String] {
        let stored = defaults.dictionary(forKey: workoutCustomNamesKey) as? [String: String] ?? [:]
        return stored.reduce(into: [UUID: String]()) { result, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            result[id] = entry.value
        }
    }

    /// Renames a workout for this device only. A nil or blank name clears the
    /// rename so the workout falls back to its type's display name.
    func setCustomName(_ name: String?, workoutID: UUID) {
        var stored = customNameDefaults.dictionary(forKey: Self.workoutCustomNamesKey) as? [String: String] ?? [:]
        if let normalized = WorkoutSummary.normalizedCustomName(name) {
            stored[workoutID.uuidString] = normalized
        } else {
            stored.removeValue(forKey: workoutID.uuidString)
        }
        customNameDefaults.set(stored, forKey: Self.workoutCustomNamesKey)
        workoutCustomNames = Self.loadWorkoutCustomNames(from: customNameDefaults)
    }

    // MARK: - Auto-apply predicted effort

    /// Presents the workout-effort write-permission sheet at the point of intent (when
    /// the user turns Auto-Apply on), then reports whether write access ended up
    /// authorized so the toggle can reset itself on denial instead of appearing on while
    /// refreshes silently fail. (Share authorization, unlike read, is reportable.)
    @discardableResult
    func requestWorkoutEffortWriteAuthorization() async -> Bool {
        try? await engine.requestWorkoutEffortWriteAuthorization()
        return await engine.isWorkoutEffortWriteAuthorized()
    }

    /// Everything the effort estimator needs, read synchronously from already-published
    /// store state — no fetches. Shared by the workout detail view (which passes its
    /// resolved max HR) and the auto-apply pass (which resolves max HR once per batch).
    func effortEstimateInput(for workout: WorkoutSummary, maxHeartRate: Double?) -> WorkoutEffortEstimator.Input {
        let context = comparisonContext(for: workout, matchingTypeOnly: false)
        let calendar = Calendar.bodyGregorian
        let workoutDay = calendar.startOfDay(for: workout.startDate)
        return WorkoutEffortEstimator.Input(
            workout: workout,
            userMaxHeartRate: maxHeartRate,
            restingHeartRate: healthTrends.restingHeartRate
                .latestValue(onOrBefore: workout.startDate, maxAgeDays: 45)
                ?? healthSummary.restingHeartRate.value,
            priorWorkouts: context.priorWorkouts,
            priorRatingOverrides: workoutEffortOverrides,
            suggestionAcceptedWorkoutIDs: suggestionAcceptedEffortWorkoutIDs,
            isHistoryComplete: context.isComplete,
            morningReadiness: healthTrends.recordedReadiness
                .first { calendar.startOfDay(for: $0.date) == workoutDay }?
                .score
        )
    }

    private var isAutoApplyingEffort = false
    /// True while `clearLocalCache` is wiping in-memory state and awaiting the
    /// engine cache clears + the on-disk deletion barrier. Guards re-entry so a
    /// second Clear tap can't interleave with an in-flight wipe.
    private var isClearingCache = false
    /// Bumped by `clearLocalCache`. Every async path that can publish or persist
    /// after a suspension captures this before its first `await` and re-checks it
    /// before mutating published state or enqueuing a save; a mismatch means a
    /// cache clear landed mid-flight, so the path bails instead of resurrecting
    /// the wiped data (H7).
    private var cacheEpoch = 0

    /// Whether an in-flight async load may still apply its result: true only
    /// while no `clearLocalCache` has bumped `cacheEpoch` since the load captured
    /// it. A mismatch means the load's data was wiped mid-flight and must not be
    /// republished or re-persisted (H7). Pure so the skip decision is unit-tested
    /// without driving the store's concurrency.
    nonisolated static func mayApplyLoad(capturedEpoch: Int, currentEpoch: Int) -> Bool {
        capturedEpoch == currentEpoch
    }
    /// Workouts auto-applied this session — excluded so a session that keeps the
    /// engine's score-less cache warm can't re-write them.
    private var autoAppliedWorkoutIDs: Set<UUID> = []
    /// Workouts found already rated by a fresh read at write time — cached so a rating
    /// that won't disappear isn't re-queried every refresh. Low-confidence (no-HR)
    /// workouts are deliberately *not* cached here: their HR can arrive late, so they
    /// stay eligible for re-estimation on later refreshes within the window.
    private var autoApplySkippedWorkoutIDs: Set<UUID> = []
    /// Cap on effort *writes* per refresh (not candidates examined), so a burst of
    /// no-HR skips can't starve older heart-rate-eligible workouts.
    private static let maxAutoAppliedEffortPerRefresh = 25
    /// Bound the per-refresh candidate scan.
    private static let maxAutoApplyEffortExamined = 200
    /// Auto-apply eligibility window, measured from a workout's end time. Body waits at
    /// least this long so a rating from the Apple Watch can sync first...
    private static let autoApplyMinWorkoutAge: TimeInterval = 60 * 60          // 1 hour
    /// ...and never touches anything older than this, so auto-apply only fills workouts
    /// that ended within the last two days.
    private static let autoApplyMaxWorkoutAge: TimeInterval = 48 * 60 * 60     // 48 hours
    /// Longest workout duration the comparison-month preload accounts for. Eligibility
    /// bounds a workout's END time, but its 30-day comparison window anchors at its
    /// START (end − duration), so the preload span must reach a plausible longest
    /// duration further back. Anything longer stays history-incomplete and is skipped
    /// as pathological.
    private static let autoApplyMaxComparisonWorkoutDuration: TimeInterval = 24 * 60 * 60  // 1 day

    /// The workout-month keys the auto-apply window (`now - maxAge` … `now`) can span:
    /// always the current month, plus the prior month when the window reaches back before
    /// this month began. Auto-apply derives its scan keys from this — independent of which
    /// months a given refresh happened to fetch — so a workout from the last days of the
    /// prior month still gets filled early in a new month (e.g. a June 30 workout on July
    /// 1) instead of being missed until a cross-month refresh. `maxAge` is a parameter (as
    /// in `autoApplyEligibleWorkouts`) so this stays a pure, nonisolated helper.
    nonisolated static func autoApplyWindowMonthKeys(now: Date, maxAge: TimeInterval, calendar: Calendar) -> [BodyWorkoutMonthKey] {
        var keys = [BodyWorkoutMonthKey(
            month: calendar.component(.month, from: now),
            year: calendar.component(.year, from: now)
        )]
        let windowStart = now.addingTimeInterval(-maxAge)
        if !calendar.isDate(windowStart, equalTo: now, toGranularity: .month) {
            keys.append(BodyWorkoutMonthKey(
                month: calendar.component(.month, from: windowStart),
                year: calendar.component(.year, from: windowStart)
            ))
        }
        return keys
    }

    /// The workout-month keys any auto-apply candidate's 30-day comparison window can
    /// reach: every month touched by the span `[now - (maxAge + maxDuration + 30 days), now]`.
    /// A candidate ENDS within `maxAge` of now, but `comparisonContext` reads the 30 days
    /// before its START — up to `maxDuration` earlier than its end — so the oldest month a
    /// comparison can touch is `maxAge + maxDuration + 30 days` back. The estimator only
    /// calibrates when every one of a candidate's comparison months is in
    /// `loadedMonthKeys`; loading this whole span up front means candidates normally
    /// reach complete history and are scored with the same calibrated number the detail
    /// view settles on. With `maxAge` = 48h and `maxDuration` = 1 day the span is
    /// 33 days → 2-3 keys.
    ///
    /// Deliberately a fixed span, not a per-candidate union: a pathological workout
    /// duration (beyond `maxDuration`) would let a single candidate's window reach back
    /// arbitrarily far, and unioning those could exceed the 12-month snapshot cache
    /// (`maximumCachedMonthSnapshots`) and thrash it. Such candidates instead stay
    /// history-incomplete, so the estimator's low-confidence gate skips them rather than
    /// dragging every month into memory. Walks month starts like the private
    /// `comparisonMonthKeys(for:calendar:)`. `maxAge`/`maxDuration` are parameters (as in
    /// `autoApplyEligibleWorkouts`) so this stays a pure, nonisolated helper.
    nonisolated static func autoApplyComparisonMonthKeys(now: Date, maxAge: TimeInterval, maxDuration: TimeInterval, calendar: Calendar) -> [BodyWorkoutMonthKey] {
        // The 30-day portion must be calendar days (like `comparisonMonthKeys`), not a
        // fixed interval: across a fall DST transition a fixed 30 * 24h lands an hour
        // short of the candidate's real window start and can drop its oldest month.
        let earliestStart = now.addingTimeInterval(-maxAge - maxDuration)
        guard let spanStart = calendar.date(byAdding: .day, value: -30, to: earliestStart),
              var cursor = calendar.dateInterval(of: .month, for: spanStart)?.start,
              let endMonthStart = calendar.dateInterval(of: .month, for: now)?.start else {
            return [BodyWorkoutMonthKey(date: now, calendar: calendar)]
        }

        var keys: [BodyWorkoutMonthKey] = []
        while cursor <= endMonthStart {
            keys.append(BodyWorkoutMonthKey(date: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }

    /// Pure selection rule for auto-apply, factored out for unit testing: unrated
    /// workouts (`effortLevel == nil`) whose end time (`startDate + duration`) falls in
    /// the `[minAge, maxAge]` window and that aren't excluded by session state, returned
    /// newest first.
    nonisolated static func autoApplyEligibleWorkouts(
        _ workouts: [WorkoutSummary],
        now: Date,
        minAge: TimeInterval,
        maxAge: TimeInterval,
        overriddenIDs: Set<UUID>,
        appliedIDs: Set<UUID>,
        skippedIDs: Set<UUID>
    ) -> [WorkoutSummary] {
        workouts
            .filter { workout in
                guard workout.effortLevel == nil else { return false }
                let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))
                let age = now.timeIntervalSince(endDate)
                let id = workout.id
                return age >= minAge
                    && age <= maxAge
                    && !overriddenIDs.contains(id)
                    && !appliedIDs.contains(id)
                    && !skippedIDs.contains(id)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    /// One eligible workout paired with its precomputed effort score, or a `nil` score
    /// when there's no usable (medium/high-confidence heart-rate) estimate — so it's
    /// skipped without consuming the write budget.
    struct AutoApplyEffortCandidate {
        let workoutID: UUID
        let score: Int?
    }

    /// The HealthKit write side effects the auto-apply loop performs, injected so the
    /// loop's branch handling can run against a fake in tests instead of the live engine.
    struct AutoApplyEffortWriter {
        let write: (UUID, Double) async throws -> HealthKitFetchEngine.AutoApplyEffortOutcome
        let isWriteAuthorized: () async -> Bool
    }

    /// What the auto-apply write loop decided, returned as plain data for the caller to
    /// apply to store state (so the loop itself stays pure of store/engine state).
    struct AutoApplyEffortLoopResult: Equatable {
        var writtenScores: [UUID: Double] = [:]
        var appliedIDs: Set<UUID> = []
        var alreadyRatedIDs: Set<UUID> = []
        var writeAuthRevoked = false
    }

    /// Runs the effort-write loop over precomputed `candidates`, writing at most
    /// `maxWrites` predictions through `writer`. `shouldContinue` is checked before
    /// each candidate (Auto-Apply still on and the task not cancelled), so flipping
    /// the toggle off mid-batch stops the remaining writes instead of finishing the
    /// pass. Candidates with a `nil` score are skipped without consuming the budget;
    /// `.alreadyRated` is recorded so it isn't retried; `.unresolved` is left for a
    /// later refresh; and a save failure stops the batch, flagging `writeAuthRevoked`
    /// when write access is no longer authorized. All side effects go through
    /// `writer`, so every branch is unit-testable without a live engine or a
    /// constructed store.
    @MainActor
    static func runAutoApplyEffortLoop(
        candidates: [AutoApplyEffortCandidate],
        maxWrites: Int,
        writer: AutoApplyEffortWriter,
        shouldContinue: () -> Bool = { true }
    ) async -> AutoApplyEffortLoopResult {
        var result = AutoApplyEffortLoopResult()
        for candidate in candidates {
            guard shouldContinue() else {
                break
            }
            if result.appliedIDs.count >= maxWrites {
                break
            }
            guard let score = candidate.score else {
                continue
            }
            do {
                switch try await writer.write(candidate.workoutID, Double(score)) {
                case .written:
                    result.writtenScores[candidate.workoutID] = Double(score)
                    result.appliedIDs.insert(candidate.workoutID)
                case .alreadyRated:
                    result.alreadyRatedIDs.insert(candidate.workoutID)
                case .unresolved:
                    break
                }
            } catch {
                if await !writer.isWriteAuthorized() {
                    result.writeAuthRevoked = true
                }
                break
            }
        }
        return result
    }

    /// When the opt-in Auto-Apply setting is on, writes Body's predicted effort to
    /// unrated workouts that ended between `autoApplyMinWorkoutAge` (1h) and
    /// `autoApplyMaxWorkoutAge` (48h) ago: the 1h floor gives an Apple Watch rating time
    /// to sync first, and the 48h ceiling means older history is never touched. The
    /// authoritative "still unrated?" check is a fresh read at write time
    /// (`engine.autoApplyWorkoutEffort`), so a rating that landed since the last refresh
    /// is never overwritten. Only medium/high-confidence (heart-rate-based) estimates are
    /// written; each is marked as an accepted suggestion so the estimator never trains on
    /// its own output. Runs from the primary foreground refreshes after the dashboard
    /// snapshot has committed, so resting-HR / readiness inputs are current.
    func autoApplyPredictedEffortIfNeeded(monthKeys: [BodyWorkoutMonthKey]) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: BodyAppearancePreference.autoApplyWorkoutEffortKey),
              defaults.object(forKey: BodyAppearancePreference.showWorkoutEffortSuggestionsKey) as? Bool ?? true,
              permissionSelection.includes(.workouts),
              !isAutoApplyingEffort else {
            return
        }
        // No write-auth gate here: the write path only ever calls `HKHealthStore.save`,
        // which never shows the permission sheet (that's requested once, at opt-in). If
        // write access isn't granted the save simply fails and the batch stops via its
        // `catch` — so we never block or prompt from a refresh.
        isAutoApplyingEffort = true
        defer { isAutoApplyingEffort = false }

        let now = Date()
        // Always scan the months the 48h window spans (not just the months this refresh
        // fetched), so a pass that only touched the current month still fills a
        // prior-month workout that's inside the window early in a new month.
        let windowKeys = Self.autoApplyWindowMonthKeys(now: now, maxAge: Self.autoApplyMaxWorkoutAge, calendar: Calendar.bodyGregorian)
        let scanKeys = Set(monthKeys).union(windowKeys)
        // The window's months must be in memory to be scanned. A fresh-dashboard resume
        // (current month only) or the immediate opt-in pass may not have the prior month
        // loaded, so fetch any absent window month before scanning — otherwise a workout
        // in it (e.g. Jun 30 on Jul 1) is invisible here and ages out of the 48h window.
        let missingWindowKeys = Set(windowKeys).filter { monthSnapshots[$0] == nil }
        if !missingWindowKeys.isEmpty {
            try? await refresh(monthKeys: missingWindowKeys, calendar: Calendar.bodyGregorian)
        }
        var allWorkouts: [WorkoutSummary] = []
        for key in scanKeys {
            guard let snapshot = monthSnapshots[key] else { continue }
            for day in snapshot.days {
                allWorkouts.append(contentsOf: day.workouts)
            }
        }
        let eligible = Self.autoApplyEligibleWorkouts(
            allWorkouts,
            now: now,
            minAge: Self.autoApplyMinWorkoutAge,
            maxAge: Self.autoApplyMaxWorkoutAge,
            overriddenIDs: Set(workoutEffortOverrides.keys),
            appliedIDs: autoAppliedWorkoutIDs,
            skippedIDs: autoApplySkippedWorkoutIDs
        )
        guard !eligible.isEmpty else {
            return
        }
        // Load the months every candidate's 30-day comparison window can reach. The
        // estimator only calibrates when all of a candidate's comparison months are in
        // `loadedMonthKeys` (the completeness signal `comparisonContext` checks), so a
        // cold launch mid-month would otherwise score with incomplete history and write
        // an uncalibrated number — after which the workout is marked rated and excluded
        // forever. Loading here means candidates are scored with the same calibrated
        // number the detail view settles on. Use `refresh(monthKeys:calendar:)` directly
        // (as the window-month load above does), not `loadMonthIfNeeded` /
        // `ensureComparisonMonthsLoaded`: those await refresh completion, which would
        // deadlock because this pass runs while the caller owns `isRefreshing`. Subtract
        // `loadedMonthKeys` (the completeness signal), not `monthSnapshots` membership,
        // which is seeded with a placeholder at launch.
        let comparisonKeys = Self.autoApplyComparisonMonthKeys(
            now: now,
            maxAge: Self.autoApplyMaxWorkoutAge,
            maxDuration: Self.autoApplyMaxComparisonWorkoutDuration,
            calendar: Calendar.bodyGregorian
        )
        let missingComparisonKeys = Set(comparisonKeys).subtracting(loadedMonthKeys)
        if !missingComparisonKeys.isEmpty {
            try? await refresh(monthKeys: missingComparisonKeys, calendar: Calendar.bodyGregorian)
        }
        let maxHeartRate = await userMaxHeartRate()
        // Precompute each candidate's score up front. Estimates read only prior
        // (older) workouts, and candidates are processed newest-first, so an in-batch
        // write never feeds a later estimate — precomputing is equivalent to estimating
        // lazily but keeps the write loop pure and testable. A low-confidence estimate
        // yields a nil score: it's skipped without consuming the write budget and,
        // crucially, not cached, so it stays eligible for a later qualifying refresh
        // within the 48h window. That now covers two cases: a no-HR workout (HR can
        // arrive late) and an incomplete-history one (e.g. the comparison-month load
        // above failed transiently) — neither writes a stale score, both retry later.
        let candidates: [AutoApplyEffortCandidate] = eligible
            .prefix(Self.maxAutoApplyEffortExamined)
            .map { workout in
                let input = effortEstimateInput(for: workout, maxHeartRate: maxHeartRate)
                let estimate = WorkoutEffortEstimator.estimate(for: input)
                let score = estimate.flatMap { $0.confidence == .low ? nil : $0.score }
                return AutoApplyEffortCandidate(workoutID: workout.id, score: score)
            }

        let writer = AutoApplyEffortWriter(
            write: { [engine] workoutID, score in
                try await engine.autoApplyWorkoutEffort(workoutID: workoutID, score: score)
            },
            isWriteAuthorized: { [engine] in
                await engine.isWorkoutEffortWriteAuthorized()
            }
        )
        let result = await Self.runAutoApplyEffortLoop(
            candidates: candidates,
            maxWrites: Self.maxAutoAppliedEffortPerRefresh,
            writer: writer,
            shouldContinue: {
                // Stop mid-batch if Auto-Apply (or its parent suggestions
                // toggle) was switched off, or the running task was cancelled
                // (Settings retains and cancels this task on OFF/onDisappear).
                !Task.isCancelled
                    && UserDefaults.standard.bool(forKey: BodyAppearancePreference.autoApplyWorkoutEffortKey)
                    && (UserDefaults.standard.object(forKey: BodyAppearancePreference.showWorkoutEffortSuggestionsKey) as? Bool ?? true)
            }
        )

        for (workoutID, score) in result.writtenScores {
            workoutEffortOverrides[workoutID] = score
            setEffortSuggestionAccepted(true, workoutID: workoutID)
        }
        autoAppliedWorkoutIDs.formUnion(result.appliedIDs)
        autoApplySkippedWorkoutIDs.formUnion(result.alreadyRatedIDs) // rated since last refresh; don't retry
        if result.writeAuthRevoked {
            // A save failed because write access was revoked (turned off in Settings
            // after opt-in). Switch Auto-Apply off so the persisted toggle reflects
            // reality instead of silently failing every refresh; a transient HealthKit
            // error leaves it on and retryable on the next refresh.
            UserDefaults.standard.set(false, forKey: BodyAppearancePreference.autoApplyWorkoutEffortKey)
        }
        if !result.appliedIDs.isEmpty {
            Task { await refreshAfterWrite(.trainingLoad) }
        }
    }

    /// Runs an auto-apply pass over the recent window right away — used when the user
    /// flips Auto-Apply on, so eligible recent (1-48h) workouts fill immediately instead
    /// of waiting for the next foreground refresh. The batch derives and loads the
    /// window's month keys itself (current + prior near a boundary), so no keys are
    /// needed here. Unlike the two in-refresh call sites, this Settings entry point isn't
    /// already inside a refresh, so it claims the slot itself: wait out any in-flight
    /// refresh, then own `isRefreshing` for the pass. That makes refresh ownership an
    /// invariant of `autoApplyPredictedEffortIfNeeded` — its internal `refresh(monthKeys:)`
    /// calls can't interleave with a concurrently starting real refresh, and every other
    /// entry point (all `guard !isRefreshing`) stays out while the pass runs. The
    /// wait-first mirrors `refreshAfterWrite`; the while-loop covers a fresh refresh
    /// claiming the slot between our resume and our claim (as in
    /// `loadIntradayMetricSamplesIfNeeded`).
    func autoApplyPredictedEffortNow() async {
        while isRefreshing {
            await awaitNextRefreshCompletion()
            guard !Task.isCancelled else { return }
        }
        isRefreshing = true
        defer { finishRefresh() }
        await autoApplyPredictedEffortIfNeeded(monthKeys: [])
    }

    /// Loads the GPS route for a workout's detail map hero as soon as its
    /// coordinates resolve (with `locality` still nil), caching the result, then
    /// folds in the reverse-geocoded city label via `resolveWorkoutRouteLocality`
    /// before returning. `nil` when the workout has no readable route. Cached per
    /// session (including the no-route result); a read cancelled by a dismissed
    /// sheet is never cached, so reopening retries instead of being served a
    /// false "no route".
    func loadWorkoutRoute(for workout: WorkoutSummary) async -> WorkoutRoute? {
        guard await loadWorkoutRouteCoordinates(for: workout) != nil else {
            return nil
        }
        return await resolveWorkoutRouteLocality(for: workout)
    }

    /// The fixes-only stage of the route load: returns as soon as the coordinates
    /// resolve, with `locality` still nil, so the detail hero can start drawing without
    /// waiting on the reverse geocode's network round trip.
    /// `resolveWorkoutRouteLocality` is the follow-up that folds the city label in, and
    /// `loadWorkoutRoute` above is simply the two stages back to back.
    ///
    /// Caching matches `loadWorkoutRoute`'s original contract exactly: a confirmed
    /// no-route is cached, a cancelled or failed read is not.
    func loadWorkoutRouteCoordinates(for workout: WorkoutSummary) async -> WorkoutRoute? {
        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = routeCache[workout.id] {
            return cached
        }

        let epoch = cacheEpoch
        let routeData: (coordinates: [RouteCoordinate], elevationProfile: [WorkoutElevationSample])
        do {
            routeData = try await engine.workoutRouteData(workoutID: workout.id)
        } catch {
            // Cancelled (sheet dismissed mid-read) or a read failure — don't
            // cache a negative; reopening retries.
            return nil
        }
        guard !Task.isCancelled else {
            return nil
        }
        // A cache clear landed while the read was suspended — the workout this
        // describes is gone, so don't re-seed the wiped cache (H7).
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return nil
        }
        guard routeData.coordinates.count >= 2 else {
            routeCache[workout.id] = .some(nil)
            // Route samples existed but carry no drawable line, so the presence probe's
            // "yes" was a false positive. Record the negative here as well or the detail
            // page would reserve its hero band again on every reopen.
            routePresenceCache[workout.id] = false
            return nil
        }

        // Cache the coordinates immediately (locality nil) so the map hero is
        // available the moment GPS resolves; the city label is a follow-up that
        // folds back into the cache. The detail sheet awaits this stage on its own to
        // render the route without blocking on the geocode.
        let route = WorkoutRoute(
            coordinates: routeData.coordinates,
            locality: nil,
            elevationProfile: routeData.elevationProfile
        )
        routeCache[workout.id] = .some(route)
        routePresenceCache[workout.id] = true
        if permissionSelection.includes(.workouts) {
            let dto = PersistedWorkoutRoute(model: route)
            persistWorkoutDetail(for: workout) { $0.route = dto }
        }
        return routeCache[workout.id] ?? nil
    }

    /// Whether the workout has a GPS route, answered from the cheap series-metadata
    /// probe long before `loadWorkoutRoute` finishes streaming its fixes — the signal
    /// the detail page reserves its hero band on.
    ///
    /// Resolved from the settled route cache first (so a `< 2 coordinates` workout is
    /// never reported present a second time), then the probe cache, then HealthKit. A
    /// failed or cancelled probe answers `.unknown` and is never cached, so the page
    /// simply behaves as it did before the probe existed and reopening retries.
    func workoutRoutePresence(for workout: WorkoutSummary) async -> BodyWorkoutRoutePresence {
        await hydrateWorkoutDetailIfNeeded(for: workout)
        let cached = cachedWorkoutRoutePresence(for: workout)
        guard cached == .unknown else {
            return cached
        }

        let epoch = cacheEpoch
        let hasRoute: Bool
        do {
            hasRoute = try await engine.workoutHasRoute(workoutID: workout.id)
        } catch {
            return .unknown
        }
        guard !Task.isCancelled else {
            return .unknown
        }
        // The full load can settle while this probe is suspended. Re-read the caches
        // rather than trusting the pre-await answer: the load's `< 2 coordinates` branch
        // writes a negative that a stale `true` here would overwrite.
        let settled = cachedWorkoutRoutePresence(for: workout)
        guard settled == .unknown else {
            return settled
        }
        // Same H7 guard as the loads: a cache clear mid-probe must not leave a
        // presence answer behind for a workout that was just wiped.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return .unknown
        }
        routePresenceCache[workout.id] = hasRoute
        return hasRoute ? .present : .absent
    }

    /// The session-cached route, without starting a read, so a reopened detail page
    /// paints its hero on the first frame instead of after a `.task` round trip.
    func cachedWorkoutRoute(for workout: WorkoutSummary) -> WorkoutRoute? {
        routeCache[workout.id] ?? nil
    }

    /// The presence a cached load or probe already settled, or `.unknown` when this
    /// workout hasn't been read this session. A settled route always wins over the
    /// probe cache, since only the load knows whether the fixes were drawable.
    func cachedWorkoutRoutePresence(for workout: WorkoutSummary) -> BodyWorkoutRoutePresence {
        if let cachedRoute = routeCache[workout.id] {
            return cachedRoute == nil ? .absent : .present
        }
        guard let probed = routePresenceCache[workout.id] else {
            return .unknown
        }
        return probed ? .present : .absent
    }

    /// Reverse-geocodes the cached route's "City, Region" label and folds it back
    /// into `routeCache`, returning the route with `locality` resolved (or the
    /// coordinates-only route when the geocode yields nothing). No-op when the
    /// workout has no cached route or the label is already resolved. Safe to call
    /// as a follow-up after `loadWorkoutRoute` so the map renders on coordinates
    /// without blocking on the reverse geocode.
    func resolveWorkoutRouteLocality(for workout: WorkoutSummary) async -> WorkoutRoute? {
        guard case .some(.some(let route)) = routeCache[workout.id] else {
            // No cached entry, or a cached "no route" negative — nothing to geocode.
            return routeCache[workout.id] ?? nil
        }
        guard route.locality == nil else {
            return route
        }

        let epoch = cacheEpoch
        let locality = await BodyReverseGeocoder.locality(for: route.coordinates)
        guard let locality else {
            return route
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return route
        }
        let resolved = WorkoutRoute(
            coordinates: route.coordinates,
            locality: locality,
            elevationProfile: route.elevationProfile
        )
        routeCache[workout.id] = .some(resolved)
        // Persist the localized route over the coordinates-only one written by the
        // load: the label costs a CLGeocoder round trip that a later cold open
        // would otherwise repeat.
        if permissionSelection.includes(.workouts) {
            let dto = PersistedWorkoutRoute(model: resolved)
            persistWorkoutDetail(for: workout) { $0.route = dto }
        }
        return resolved
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

        let epoch = cacheEpoch
        let data: WorkoutSplitData
        do {
            data = try await engine.workoutSplitData(workoutID: workout.id)
        } catch {
            // Cancelled (sheet dismissed mid-read) or a read failure — don't
            // cache an empty as confirmed-absent; reopening retries.
            return .empty
        }
        guard !Task.isCancelled else {
            return data
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return data
        }
        if !data.distanceSamples.isEmpty {
            distanceSampleCache[workout.id] = data
        } else {
            // Cache a confirmed-empty read only for settled (>24h-old) workouts;
            // a recent one may still be syncing from the watch.
            let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))
            if Date().timeIntervalSince(endDate) > 24 * 60 * 60 {
                distanceSampleCache[workout.id] = data
            }
        }
        return data
    }

    /// Loads a workout's per-bucket series inputs for the detail chart cards, or
    /// `.empty` when the activity has no distance pace/speed or the read failed.
    /// Cached per session only once the workout has settled (ended more than 24 h
    /// ago) and every metric read succeeded — a recent workout may still be syncing
    /// samples from the watch, and a partially failed bundle must not be pinned for
    /// the rest of the session.
    func loadWorkoutMetricSeriesData(for workout: WorkoutSummary) async -> WorkoutMetricSeriesData {
        let paceStyle = workout.type.paceStyle
        guard paceStyle == .distancePace || paceStyle == .speed else {
            return .empty
        }

        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = metricSeriesCache[workout.id] {
            return cached
        }

        let epoch = cacheEpoch
        let data: WorkoutMetricSeriesData
        do {
            data = try await engine.workoutMetricSeriesData(workoutID: workout.id)
        } catch {
            // Cancelled (sheet dismissed mid-read) or a read failure — don't
            // cache an empty as confirmed-absent; reopening retries.
            return .empty
        }
        guard !Task.isCancelled else {
            return data
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return data
        }
        if Date().timeIntervalSince(workout.effectiveEndDate) > 24 * 60 * 60, !data.hadReadFailure {
            metricSeriesCache[workout.id] = data
            // Persist only a bundle that actually carries a series. A denied
            // Workout Metrics read surfaces as an empty (non-throwing) bundle, and
            // writing that would freeze the negative on disk past the session wipes.
            let carriesData = !data.distanceMeters.isEmpty
                || !data.steps.isEmpty
                || data.strideLengthMeters != nil
                || data.groundContactTimeMs != nil
                || data.verticalOscillationCm != nil
                || data.cyclingCadenceRPM != nil
            if carriesData, permissionSelection.includes(.workoutMetrics) {
                let dto = PersistedWorkoutMetricSeries(model: data)
                persistWorkoutDetail(for: workout) { $0.metricSeries = dto }
            }
        }
        return data
    }

    /// Loads a workout's 1-minute heart-rate recovery for the detail tile, or nil
    /// when the Heart permission is off, no recovery reading exists, or the read
    /// failed. Not gated on pace style — every activity type can have one.
    func loadWorkoutHeartRateRecovery(for workout: WorkoutSummary) async -> Double? {
        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = heartRateRecoveryCache[workout.id] {
            return cached
        }

        let epoch = cacheEpoch
        let recovery: Double?
        do {
            recovery = try await engine.workoutHeartRateRecovery(workoutID: workout.id)
        } catch {
            // Cancelled (sheet dismissed mid-read) or a read failure — don't cache
            // a nil as confirmed-absent; reopening retries.
            return nil
        }
        guard !Task.isCancelled else {
            return recovery
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return recovery
        }
        if Date().timeIntervalSince(workout.effectiveEndDate) > 24 * 60 * 60 {
            heartRateRecoveryCache[workout.id] = recovery
            // The confirmed-absent `nil` above stays session-only: a Heart read the
            // user has denied also answers nil, so persisting it would outlive the
            // permission change that a session cache can't survive.
            if let bpm = recovery, bpm > 0, permissionSelection.includes(.heart) {
                persistWorkoutDetail(for: workout) { $0.heartRateRecoveryBPM = bpm }
            }
        }
        return recovery
    }

    /// Seeds the per-workout detail session caches from the workout's persisted
    /// snapshot, so reopening a settled workout after a cold launch paints its map,
    /// charts and recovery tile without re-scanning HealthKit. Idempotent;
    /// concurrent callers share one file read.
    ///
    /// Only *missing* entries are seeded — a value this session already read from
    /// HealthKit is always the fresher one. Nothing on disk is a negative (the store
    /// is written positive-only), so a seed can never pin a "no route" / "no
    /// recovery" answer.
    private func hydrateWorkoutDetailIfNeeded(for workout: WorkoutSummary) async {
        if let existing = detailHydrations[workout.id] {
            _ = await existing.value
            return
        }

        let epoch = cacheEpoch
        let task = Task.detached(priority: .userInitiated) {
            WorkoutDetailSnapshotStore.load(workoutID: workout.id)
        }
        detailHydrations[workout.id] = task
        let snapshot = await task.value

        // A cache clear landed while the file read was in flight — the workout this
        // describes is gone, so don't re-seed the wiped caches (H7).
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return
        }

        if let route = snapshot?.route, routeCache[workout.id] == nil {
            routeCache[workout.id] = .some(route.toModel())
            routePresenceCache[workout.id] = true
        }
        if let series = snapshot?.metricSeries, metricSeriesCache[workout.id] == nil {
            metricSeriesCache[workout.id] = series.toModel()
        }
        if let bpm = snapshot?.heartRateRecoveryBPM, heartRateRecoveryCache[workout.id] == nil {
            heartRateRecoveryCache[workout.id] = .some(bpm)
        }
    }

    /// Whether a workout's details are worth keeping on disk: it has settled (the
    /// same >24 h rule the loaders admit results to the session caches under, so a
    /// still-syncing watch workout is never pinned), and it falls inside the two
    /// months the persisted workout list itself covers — details for a workout the
    /// list can't show would only be pruned again.
    nonisolated static func isWorkoutDetailPersistable(
        workout: WorkoutSummary,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard now.timeIntervalSince(workout.effectiveEndDate) > 24 * 60 * 60 else {
            return false
        }

        let currentKey = BodyWorkoutMonthKey(date: now, calendar: calendar)
        let workoutKey = BodyWorkoutMonthKey(date: workout.startDate, calendar: calendar)
        if workoutKey == currentKey {
            return true
        }
        guard let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: now) else {
            return false
        }
        return workoutKey == BodyWorkoutMonthKey(date: previousMonthStart, calendar: calendar)
    }

    /// Read-modify-writes the workout's on-disk detail snapshot through `mutate`,
    /// on the shared persist queue so the store (which carries no lock of its own)
    /// only ever sees one mutation at a time. `mutate` must capture DTOs built on
    /// the main actor — nothing else here is Sendable.
    private func persistWorkoutDetail(
        for workout: WorkoutSummary,
        mutate: @escaping @Sendable (inout WorkoutDetailSnapshot) -> Void
    ) {
        guard Self.isWorkoutDetailPersistable(
            workout: workout,
            now: Date(),
            calendar: .bodyGregorian
        ) else {
            return
        }

        let workoutID = workout.id
        Self.snapshotPersistQueue.async {
            var snapshot = WorkoutDetailSnapshotStore.load(workoutID: workoutID)
                ?? WorkoutDetailSnapshot(workoutID: workoutID)
            mutate(&snapshot)
            guard !snapshot.isEmpty, WorkoutDetailSnapshotStore.save(snapshot) else {
                return
            }
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
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
        routePresenceCache.removeAll()
        distanceSampleCache.removeAll()
        metricSeriesCache.removeAll()
        heartRateRecoveryCache.removeAll()
        // Safe to re-hydrate from disk right away: the files hold only positives,
        // so nothing they seed can contradict the fresh authorization.
        detailHydrations = [:]
    }

    /// Loads the intraday day-sample sidecar (split out of the launch-critical
    /// snapshot decode) off the main actor and merges it into any still-empty
    /// `*DaySamples` fields. Refresh and lazy-load entry points await this
    /// first so a snapshot save can never overwrite the sidecar with empty
    /// series before it has been read, and so the incremental intraday fetch
    /// sees the cached points. Idempotent; concurrent callers share one load.
    func hydratePersistedDaySamplesIfNeeded() async {
        let epoch = cacheEpoch
        if persistedDaySamplesHydration == nil {
            persistedDaySamplesHydration = Task.detached(priority: .userInitiated) {
                HealthDashboardSnapshotStore.loadDaySamples()
            }
        }

        guard let daySamples = await persistedDaySamplesHydration?.value, !daySamples.isEmpty else {
            return
        }
        // A cache clear landed while the sidecar loaded — don't merge the wiped
        // day samples back onto the now-empty trends.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return
        }

        // Scope the sidecar to the current selection before merging so a source
        // switch, combine-flag flip, now-off permission, or a comparison the
        // current selection resolves away can't resurrect stale intraday points
        // (H6). A legacy/v1 sidecar (no combine stamp) fails closed and is dropped
        // one-time.
        let scoped = daySamples.scopedForHydration(
            currentPrimarySignature: currentPrimarySelectionSignature(),
            currentSecondarySignature: currentSecondarySelectionSignature(),
            currentCombinesByName: combinesHealthDataSourcesByName,
            permission: permissionSelection,
            comparisonDisabledKinds: currentComparisonDisabledKinds()
        )
        guard !scoped.isEmpty else {
            return
        }

        healthTrends = healthTrends.mergingMissingDaySamples(from: scoped)
    }

    /// Strips the comparison series from the session's memoized sidecar load after
    /// the caller has cleared them from `healthTrends`.
    ///
    /// `hydratePersistedDaySamplesIfNeeded` reads the sidecar ONCE per session and
    /// reuses the resulting task's value, so a clear that only touches
    /// `healthTrends` and the file is undone by the very next hydration — which the
    /// entitlement handler's own corrective refresh performs. The live comparison
    /// gate in `scopedForHydration` masks this while the comparison stays resolved
    /// away, but a lapse → unlock inside one session reopens it and the unchanged
    /// selection signatures then accept the pre-lapse payload.
    ///
    /// Re-points the memo instead of clearing it: `nil` would make the next
    /// hydration re-read the file, which can beat the caller's asynchronous
    /// `persistDaySampleSidecar()` write and restore exactly what was cleared. The
    /// primary scope is preserved so a later hydration still works.
    private func invalidateMemoizedComparisonDaySamples() async {
        guard let loaded = await persistedDaySamplesHydration?.value else {
            return
        }
        let stripped: HealthTrendDaySampleSnapshot? = loaded.strippingSecondaryDaySamples()
        persistedDaySamplesHydration = Task { stripped }
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
        // `.restingHeartRate` is deliberately absent: it has no day view
        // (`HealthMetricKind.dayViewKinds`), so its intraday samples were fetched
        // and persisted but never rendered.
        case .heartRate, .heartRateVariability, .respiratoryRate, .oxygenSaturation:
            usesHourlyBuckets = false
        case .activeEnergy, .steps:
            usesHourlyBuckets = true
        default:
            return
        }

        let epoch = cacheEpoch
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
        let interval = HealthKitFetchEngine.intradayDaySampleInterval(calendar: calendar, anchor: nil)
        let cachedPrimary = healthTrends.daySeries(for: kind)
        let cachedSecondary = healthTrends.secondaryDaySeries(for: kind)
        let capturedDaySampleSignatures = currentDaySampleSignatures()
        // No comparison source selected (or the Pro gate / primary-collapse rule
        // resolved it away). The fetch below short-circuits to an authoritative
        // `.empty`, which must REPLACE the cached series — but `mergeIntradaySamples`
        // retains everything before `refetchStart`, so an incremental boundary here
        // would strand the previous source's points on the chart. Treat the whole
        // window as authoritative so the empty result clears it.
        let secondaryIsDisabled = selectedSecondaryHealthDataSourceOption(for: kind).isNoComparison

        let primaryFetchStart: Date
        let secondaryFetchStart: Date
        if usesHourlyBuckets {
            // Hourly cumulative buckets overlap on the current hour, so the
            // incremental merge can't dedupe them — always refetch the full window.
            primaryFetchStart = interval.start
            secondaryFetchStart = interval.start
        } else {
            primaryFetchStart = HealthKitFetchEngine.incrementalFetchStart(after: cachedPrimary, windowStart: interval.start)
            secondaryFetchStart = secondaryIsDisabled
                ? interval.start
                : HealthKitFetchEngine.incrementalFetchStart(after: cachedSecondary, windowStart: interval.start)

            // Cache already extends to the window end — nothing to add. A disabled
            // comparison never satisfies the window-end test (its refetch start is
            // pinned to `interval.start` above), so test what it actually needs:
            // that the series it has to clear is already clear.
            let secondarySatisfied = secondaryIsDisabled
                ? cachedSecondary.isEmpty
                : secondaryFetchStart >= interval.end
            if primaryFetchStart >= interval.end, secondarySatisfied {
                return
            }
        }

        // A `nil` result means the sample query failed (device locked, XPC drop,
        // unresolved source) — keep the cached series; a successful empty result
        // still replaces it.
        let primarySamples = await engine.fetchIntradayDaySamples(
            for: kind,
            calendar: calendar,
            startDate: primaryFetchStart,
            endDate: interval.end
        )
        let secondarySamples: HealthTrendSeries?
        if secondaryIsDisabled {
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

        // Both queries failed — nothing to merge, keep every cached series.
        if primarySamples == nil, secondarySamples == nil {
            return
        }

        let mergedPrimary: HealthTrendSeries
        let mergedSecondary: HealthTrendSeries
        if usesHourlyBuckets {
            mergedPrimary = primarySamples ?? healthTrends.daySeries(for: kind)
            mergedSecondary = secondarySamples ?? healthTrends.secondaryDaySeries(for: kind)
        } else {
            if let primarySamples {
                mergedPrimary = HealthKitFetchEngine.mergeIntradaySamples(
                    existing: healthTrends.daySeries(for: kind),
                    incoming: primarySamples,
                    windowStart: interval.start,
                    refetchStart: primaryFetchStart
                )
            } else {
                mergedPrimary = healthTrends.daySeries(for: kind)
            }
            if let secondarySamples {
                mergedSecondary = HealthKitFetchEngine.mergeIntradaySamples(
                    existing: healthTrends.secondaryDaySeries(for: kind),
                    incoming: secondarySamples,
                    windowStart: interval.start,
                    refetchStart: secondaryFetchStart
                )
            } else {
                mergedSecondary = healthTrends.secondaryDaySeries(for: kind)
            }
        }

        var trends = healthTrends
        switch kind {
        case .heartRate:
            trends.heartRateDaySamples = mergedPrimary
            trends.heartRateDaySamplesSecondary = mergedSecondary
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
        // A cache clear landed while the intraday samples fetched — don't merge
        // them back onto the wiped trends. The signature check covers the other
        // mid-flight invalidations: the engine fetches and the `while isRefreshing`
        // wait above can straddle a source switch, combine flip, or permission
        // change, all of which strip the day samples. Merging old-source samples
        // onto the freshly stripped trends would stamp them into the sidecar under
        // the NEW selection's signature, which `scopedForHydration` then accepts
        // forever — and nothing self-heals, because the incremental fetch
        // early-returns once the cache covers the window.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              currentDaySampleSignatures() == capturedDaySampleSignatures else {
            return
        }
        healthTrends = trends
        // Make the lazily fetched series durable so the next launch renders the
        // day chart straight from the sidecar.
        persistDaySampleSidecar()
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
            routePresenceCache.removeAll()
            distanceSampleCache.removeAll()
                metricSeriesCache.removeAll()
            heartRateRecoveryCache.removeAll()
            detailHydrations = [:]
        } else if permission == .heart {
            // Heart-rate recovery rides the Heart toggle; drop it rather than
            // serving a toggle change a result read under the old selection.
            heartRateRecoveryCache.removeAll()
            detailHydrations = [:]
        } else if permission == .workoutMetrics {
            // Cached split data carries per-split step cadence, and stride length is
            // gated the same way — both ride on the Workout Metrics permission, so
            // drop them rather than serving a toggle change stale results from a
            // read taken under the previous selection.
            distanceSampleCache.removeAll()
                metricSeriesCache.removeAll()
            detailHydrations = [:]
        }
        if !isEnabled {
            // The in-memory drop above leaves the persisted detail files intact, and
            // a hydration would seed them straight back. Strip the data at rest on
            // opt-out too, same rationale as `sanitizeWorkoutSnapshots`.
            Self.snapshotPersistQueue.async {
                switch permission {
                case .workouts:
                    WorkoutDetailSnapshotStore.deleteAll()
                case .workoutMetrics:
                    WorkoutDetailSnapshotStore.stripMetricSeries()
                case .heart:
                    WorkoutDetailSnapshotStore.stripHeartRateRecovery()
                default:
                    break
                }
            }
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

    /// A custom warning threshold changes what counts as an episode, so today's
    /// cached warning for that metric is stale as soon as Settings writes the new
    /// value. The engine reads the stored thresholds itself, so refetching the
    /// metric is all that's needed. Fire-and-forget so the picker stays responsive.
    func metricWarningThresholdsDidChange(for metric: HealthMetricKind) {
        Task { [weak self] in
            // `refreshHealthMetric` drops the call while a refresh is in flight;
            // wait it out like the source/permission mutators do.
            await self?.awaitNextRefreshCompletion()
            guard !Task.isCancelled else {
                return
            }
            await self?.refreshHealthMetric(metric)
        }
    }

    func healthDataSourceOptions(for kind: HealthMetricKind) -> [BodyHealthDataSourceOption] {
        guard kind.supportsHealthDataSourceSelection else {
            return []
        }

        return [BodyHealthDataSourceOption.allSources]
            + (healthDataSourceOptionsByKind[kind] ?? [])
            + customHealthSourceGroups.map(\.option)
    }

    func secondaryHealthDataSourceOptions(for kind: HealthMetricKind) -> [BodyHealthDataSourceOption] {
        guard kind.supportsSecondaryHealthDataSourceSelection else {
            return []
        }

        let storedPrimaryOption = healthDataSourceSelection.option(for: kind)
        // A locked (or member-less) custom primary REPORTS as All Sources, so
        // filtering on the effective option alone would drop All Sources from
        // the comparison list while still offering the group itself. Excluding
        // the stored custom id instead keeps the list honest; the
        // same-as-primary case is neutralized by
        // `selectedSecondaryHealthDataSourceOption` regardless.
        let excludedOptionID = storedPrimaryOption.isCustomSource
            ? storedPrimaryOption.id
            : selectedHealthDataSourceOption(for: kind).id
        let candidates = [BodyHealthDataSourceOption.allSources]
            + (healthDataSourceOptionsByKind[kind] ?? [])
            + customHealthSourceGroups.map(\.option)
        let filtered = candidates.filter { $0.id != excludedOptionID }
        return [BodyHealthDataSourceOption.noComparison] + filtered
    }

    func healthDataSourceDefaultOptions() -> [BodyHealthDataSourceOption] {
        includeSelectedSourceOptionIfNeeded(
            selectedHealthDataSourceOption: healthDataSourceSelection.defaultOption,
            in: [BodyHealthDataSourceOption.allSources]
                + uniqueHealthDataSourceOptions(for: HealthMetricKind.sourceSelectableKinds)
                + customHealthSourceGroups.map(\.option)
        )
    }

    func secondaryHealthDataSourceDefaultOptions() -> [BodyHealthDataSourceOption] {
        let primaryOption = healthDataSourceSelection.defaultOption
        let candidates = [BodyHealthDataSourceOption.allSources]
            + uniqueHealthDataSourceOptions(for: HealthMetricKind.sourceSelectableKinds.filter(\.supportsSecondaryHealthDataSourceSelection))
            + customHealthSourceGroups.map(\.option)
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
        resolvedDefaultCustomHealthSourceOption(
            healthDataSourceSelection.defaultOption,
            absentFallback: .allSources
        )
    }

    var defaultSecondaryHealthDataSourceOption: BodyHealthDataSourceOption {
        resolvedDefaultCustomHealthSourceOption(
            secondaryHealthDataSourceSelection.defaultOption,
            absentFallback: .noComparison
        )
    }

    /// The Settings default rows read these two raw (no per-kind discovery to
    /// resolve against), so the Body Pro gate and the live group name have to be
    /// applied here as well: a lapsed subscription must show the effective All
    /// Sources / No Comparison, and a renamed group must show its current name
    /// without the selection — and every signature built from it — being
    /// rewritten.
    private func resolvedDefaultCustomHealthSourceOption(
        _ option: BodyHealthDataSourceOption,
        absentFallback: BodyHealthDataSourceOption
    ) -> BodyHealthDataSourceOption {
        guard option.isCustomSource else {
            return option
        }

        guard BodyProEntitlement.isUnlocked,
              let group = customHealthSourceGroups.first(where: { $0.id == option.id }) else {
            return absentFallback
        }

        return group.option
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

        // Combining changes how every per-source series is merged, so drop all
        // cached intraday day samples and persist the invalidation before the
        // corrective refetch (H6a).
        healthTrends = healthTrends.strippingDaySamples()
        persistDaySampleSidecar()

        await requestAuthorizationAndRefresh()
    }

    nonisolated static func loadCustomHealthSourceGroups(
        defaults: UserDefaults = .standard
    ) -> [BodyCustomHealthSourceGroup] {
        BodyCustomHealthSourceGroupStore.groups(
            from: defaults.string(forKey: BodyAppearancePreference.customHealthSourceGroupsKey) ?? ""
        )
    }

    nonisolated private static func saveCustomHealthSourceGroups(
        _ groups: [BodyCustomHealthSourceGroup],
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            BodyCustomHealthSourceGroupStore.rawValue(from: groups),
            forKey: BodyAppearancePreference.customHealthSourceGroupsKey
        )
    }

    func addCustomHealthSourceGroup(
        name: String,
        memberIdentityKeys: [String],
        iconSystemName: String? = nil
    ) async {
        guard customHealthSourceGroups.count < BodyCustomHealthSourceGroupStore.maximumGroupCount else {
            return
        }

        let group = BodyCustomHealthSourceGroup.custom(
            name: name,
            memberIdentityKeys: memberIdentityKeys,
            iconSystemName: iconSystemName
        )
        await applyCustomHealthSourceGroups(customHealthSourceGroups + [group])
    }

    /// The icon a custom source renders with, resolved live by group id (never
    /// persisted into a selection, exactly like the display name) and validated
    /// against the picker vocabulary so an unknown symbol falls back to the
    /// default instead of rendering a blank image.
    func customHealthSourceIconName(for optionID: String) -> String {
        let iconName = customHealthSourceGroups.first { $0.id == optionID }?.iconSystemName
        guard let iconName, BodyHealthSourceIcon.selectableSymbolNames.contains(iconName) else {
            return BodyHealthSourceIcon.customSourceDefaultSymbolName
        }
        return iconName
    }

    func updateCustomHealthSourceGroupMembers(id: String, memberIdentityKeys: [String]) async {
        guard let index = customHealthSourceGroups.firstIndex(where: { $0.id == id }) else {
            return
        }

        var nextGroups = customHealthSourceGroups
        // Rebuilt through the initializer rather than mutated in place, so the
        // members go through the same sort/dedupe every other entry point does.
        nextGroups[index] = BodyCustomHealthSourceGroup(
            id: id,
            name: nextGroups[index].name,
            memberIdentityKeys: memberIdentityKeys,
            iconSystemName: nextGroups[index].iconSystemName
        )
        guard nextGroups != customHealthSourceGroups else {
            return
        }

        await applyCustomHealthSourceGroups(nextGroups)
    }

    /// The display attributes — name and icon — change nothing a query, a cache,
    /// or the watch resolves against (the canonical group signature excludes
    /// both), so this deliberately skips the invalidation sequence — no refetch,
    /// no stripped day samples. The selection is NOT rewritten either: names and
    /// icons resolve live through the store's resolved-option accessors, while a
    /// stored copy would leak into `rawValue`-based signatures and churn every
    /// cache on a cosmetic edit.
    func updateCustomHealthSourceGroupDisplay(id: String, name: String, iconSystemName: String?) async {
        guard let index = customHealthSourceGroups.firstIndex(where: { $0.id == id }) else {
            return
        }

        var nextGroups = customHealthSourceGroups
        nextGroups[index] = BodyCustomHealthSourceGroup(
            id: id,
            name: name,
            memberIdentityKeys: nextGroups[index].memberIdentityKeys,
            iconSystemName: iconSystemName
        )
        guard nextGroups != customHealthSourceGroups else {
            return
        }

        customHealthSourceGroups = nextGroups
        Self.saveCustomHealthSourceGroups(nextGroups)
        await engine.setCustomHealthSourceGroups(nextGroups)
        publishWatchSnapshot()
    }

    func deleteCustomHealthSourceGroup(id: String) async {
        guard customHealthSourceGroups.contains(where: { $0.id == id }) else {
            return
        }

        // Eager selection cleanup, constructing both selections directly:
        // `settingDefault` / `clearingOverride` also drop unrelated overrides
        // that merely share an id with the old default, which is not what a
        // deletion means. A left-behind `custom:` id would otherwise resolve to
        // All Sources forever with no way to see or change it.
        let nextSelection = BodyHealthDataSourceSelection(
            defaultOption: healthDataSourceSelection.defaultOption.id == id
                ? .allSources
                : healthDataSourceSelection.defaultOption,
            selectedOptions: healthDataSourceSelection.selectedOptions.filter { $0.value.id != id }
        )
        let nextSecondarySelection = BodyHealthSecondaryDataSourceSelection(
            defaultOption: secondaryHealthDataSourceSelection.defaultOption.id == id
                ? .noComparison
                : secondaryHealthDataSourceSelection.defaultOption,
            selectedOptions: secondaryHealthDataSourceSelection.selectedOptions.filter { $0.value.id != id }
        )
        healthDataSourceSelection = nextSelection
        secondaryHealthDataSourceSelection = nextSecondarySelection
        nextSelection.save()
        nextSecondarySelection.save()
        await engine.setHealthDataSourceSelection(nextSelection)
        await engine.setSecondaryHealthDataSourceSelection(nextSecondarySelection)

        await applyCustomHealthSourceGroups(customHealthSourceGroups.filter { $0.id != id })
    }

    /// Persist → engine → refetch options → the same invalidation sequence the
    /// combine-flag toggle runs: membership decides which sources every series
    /// merged, so the cached intraday day samples are dropped and that
    /// invalidation persisted BEFORE the corrective refetch (H6a).
    private func applyCustomHealthSourceGroups(_ groups: [BodyCustomHealthSourceGroup]) async {
        customHealthSourceGroups = groups
        Self.saveCustomHealthSourceGroups(groups)
        await engine.setCustomHealthSourceGroups(groups)
        await fetchHealthDataSourceOptions(calendar: .bodyGregorian)

        // Wait out any in-flight refresh so the `isRefreshing` guard in
        // `requestAuthorizationAndRefresh` doesn't silently drop this refetch
        // (matches the secondary-source variants).
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled else {
            return
        }

        healthTrends = healthTrends.strippingDaySamples()
        persistDaySampleSidecar()

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

        // The default source (and possibly the secondary, reset above) changed —
        // drop all cached intraday day samples and persist the invalidation
        // before the corrective refetch (H6a).
        healthTrends = healthTrends.strippingDaySamples()
        persistDaySampleSidecar()

        await requestAuthorizationAndRefresh()
    }

    /// Refetches the dashboard after a sleep-stage *display* preference changes
    /// (sub-minute / leading-trailing awake stages), which alters how sleep
    /// samples are grouped. Mirrors the source-change precedent: waits out any
    /// in-flight refresh first so the `isRefreshing` guard in
    /// `requestAuthorizationAndRefresh` doesn't silently drop the refetch (the
    /// bare `Task { requestAuthorizationAndRefresh() }` the Settings onChange used
    /// to fire was lost whenever it landed during a launch/resume refresh).
    func refetchAfterSleepDisplayPreferenceChange() async {
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

        // The secondary source changed — clear the cached comparison series
        // (incl. secondary day samples) and persist the invalidation before the
        // corrective refetch (H6a).
        healthTrends = healthTrends.clearingSecondarySeries()
        persistDaySampleSidecar()

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

        // Only this metric's source changed — drop just its primary intraday
        // series (leave the other charts intact) and persist the invalidation
        // before the corrective refetch (H6a).
        healthTrends = healthTrends.strippingPrimaryDaySamples(for: kind)
        persistDaySampleSidecar()

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

        // The secondary source changed — clear the cached comparison series
        // (incl. secondary day samples) and persist the invalidation before the
        // corrective refetch (H6a).
        healthTrends = healthTrends.clearingSecondarySeries()
        persistDaySampleSidecar()

        await refreshHealthMetric(kind)
    }

    /// Persists the current in-memory dashboard snapshot + day-sample sidecar
    /// outside a dashboard refresh, for the two paths that change day samples on
    /// their own: a source/combine-change strip (H6a) must be DURABLE — if the
    /// corrective refresh errors, cancels, or the app is killed before it lands,
    /// the poisoned sidecar would otherwise survive on disk and re-hydrate, so
    /// the stripped-empty series overwrite it; and a lazily fetched intraday
    /// series must be durable too, so the next launch renders the metric detail
    /// Day View instantly from cache instead of waiting on HealthKit. Mirrors the
    /// save block in `updateHealthDashboardSnapshot`.
    private func persistDaySampleSidecar() {
        let snapshotToSave = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        let secondarySignature = currentSecondarySelectionSignature()
        let summaryContextSignature = healthSummaryPrimarySignature
        Self.snapshotPersistQueue.async {
            HealthDashboardSnapshotStore.save(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature
            )
            HealthDashboardSnapshotStore.saveSecondarySelectionSignature(secondarySignature)
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
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

        guard !option.isCustomSource else {
            return resolvedCustomHealthSourceOption(option, for: kind, absentFallback: .allSources)
        }

        // Discovery hasn't populated this kind yet (cold start / mid-clear) —
        // keep the stored selection rather than collapsing it to All Sources
        // (H4); the map fills in once source discovery completes. Only an option
        // genuinely absent from a DISCOVERED list falls back to All Sources.
        guard let options = healthDataSourceOptionsByKind[kind] else {
            return option
        }
        guard options.contains(where: { $0.id == option.id }) else {
            return .allSources
        }

        return option
    }

    /// A `custom:` selection resolves against the GROUP list, not the per-kind
    /// discovered options: a group exists whether or not this kind happened to
    /// discover any of its members, and it reports the group's CURRENT name so a
    /// rename shows everywhere without rewriting (and re-signing) the selection.
    ///
    /// It collapses to `absentFallback` in exactly two cases: Body Pro is locked
    /// (mirroring the fetch gate in `HealthKitFetchEngine.sourceQueryResolution`,
    /// so the row matches the widened query), or discovery HAS run for this kind
    /// and registered no bucket for the group — the engine's lenient resolution
    /// widened to all sources there, and the row must say so.
    private func resolvedCustomHealthSourceOption(
        _ option: BodyHealthDataSourceOption,
        for kind: HealthMetricKind,
        absentFallback: BodyHealthDataSourceOption
    ) -> BodyHealthDataSourceOption {
        guard BodyProEntitlement.isUnlocked,
              let group = customHealthSourceGroups.first(where: { $0.id == option.id }) else {
            return absentFallback
        }

        guard let customIDsWithData = customSourceIDsWithDataByKind[kind] else {
            return group.option
        }

        return customIDsWithData.contains(option.id) ? group.option : absentFallback
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

        guard !option.isCustomSource else {
            return resolvedCustomHealthSourceOption(option, for: kind, absentFallback: .noComparison)
        }

        // Discovery hasn't populated this kind yet — keep the stored secondary
        // selection instead of collapsing it to No Comparison (H4). Only an
        // option genuinely absent from a discovered list falls back.
        guard let options = healthDataSourceOptionsByKind[kind] else {
            return option
        }
        guard options.contains(where: { $0.id == option.id }) else {
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

        // Both the debounce and freshness checks treat a negative elapsed (device
        // clock moved backward since the stamp) as stale, not fresh — otherwise a
        // backward clock jump could suppress resumes indefinitely (debounce) or
        // pin the warm workout-only path (freshness) instead of a full refresh.
        if let lastAppEntrySyncDate,
           Self.isWithinFreshInterval(date.timeIntervalSince(lastAppEntrySyncDate), limit: Self.shortResumeDebounceInterval) {
            return
        }

        lastAppEntrySyncDate = date

        if let lastSuccessfulRefreshDate,
           Self.isWithinFreshInterval(date.timeIntervalSince(lastSuccessfulRefreshDate), limit: Self.dashboardFreshnessInterval),
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

    /// A resume interval counts as "fresh" (skip a resume / take the warm
    /// workout-only path) only when `elapsed` is non-negative and under `limit`.
    /// A negative elapsed — the device clock moved backward since the stamp —
    /// counts as stale (L1), so a backward jump can't wedge the resume logic.
    nonisolated static func isWithinFreshInterval(_ elapsed: TimeInterval, limit: TimeInterval) -> Bool {
        elapsed >= 0 && elapsed < limit
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

        let epoch = cacheEpoch
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
                // A cache clear landed during the fetch — bail before the merge
                // below (`mergeOlderActivityRingHistory` publishes in-memory) so
                // the paged-in month can't resurrect onto the wiped history.
                guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
                    return
                }
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
            // A cache clear landed while older ring months fetched — don't
            // publish or persist the paged-in history onto the wiped state.
            guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
                return
            }

            let snapshotToSave = HealthDashboardSnapshot(
                summary: healthSummary,
                trends: healthTrends,
                activityRingHistory: mergedHistory
            )
            let daySampleSignatures = currentDaySampleSignatures()
            // Carry the current summary-context signature so this ring-pagination
            // save doesn't clobber the persisted one back to nil (H2a).
            let summaryContextSignature = healthSummaryPrimarySignature
            Self.snapshotPersistQueue.async {
                HealthDashboardSnapshotStore.save(
                    snapshotToSave,
                    daySampleSignatures: daySampleSignatures,
                    summaryContextSignature: summaryContextSignature
                )
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
        let epoch = cacheEpoch
        loadingActivityRingMonthKeys.insert(earliestProbed)
        defer { loadingActivityRingMonthKeys.remove(earliestProbed) }

        let outcome = await engine.probeOlderActivityRingHistory(before: earliestProbed, calendar: calendar)
        // A cache clear landed during the probe — don't publish (via merge) or
        // mutate pagination state onto the wiped history.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return nil
        }
        switch outcome {
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

    func clearLocalCache(date: Date = Date()) async {
        // Don't clear on top of an in-flight refresh (which would resurrect what
        // we wipe) or a wipe already running.
        guard !isRefreshing, !isClearingCache else {
            return
        }
        isClearingCache = true
        defer { isClearingCache = false }
        // Invalidate every in-flight load: a resurrection-capable path that
        // resumes after this sees the bumped epoch and bails before re-publishing
        // or re-persisting the data we're about to wipe.
        cacheEpoch += 1

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

        // Wipe in-memory state up front — before the first suspension — so
        // nothing reads a stale cache while the engine clears and the on-disk
        // deletions run, and so `needsInitialHealthDataLoad` flips immediately
        // (idling the passive load paths).
        snapshot = emptySnapshot
        monthSnapshots = [key: emptySnapshot]
        // Per-workout detail caches keyed by workout UUID — the workouts they
        // describe are being wiped, so leaving them would serve routes, splits,
        // series and recovery for workouts the app no longer has (M73).
        routeCache.removeAll()
        routePresenceCache.removeAll()
        distanceSampleCache.removeAll()
        metricSeriesCache.removeAll()
        heartRateRecoveryCache.removeAll()
        detailHydrations = [:]
        healthSummary = .empty
        // Drop the summary-reuse signature so a post-clear failed leaf resolves
        // to empty rather than reusing anything against the wiped summary.
        healthSummaryPrimarySignature = nil
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
        customSourceIDsWithDataByKind = [:]
        persistedDaySamplesHydration = nil
        lastSuccessfulRefreshDate = nil
        // Drop the compute-seed watermark + cached Training Load piece too — a
        // tombstoned install must not re-attach a stale seed (built from data
        // this clear just wiped) on the next publish. `dataThrough` (from
        // `lastVitalsRefreshDate`) is what gates whether `publishWatchSnapshot`
        // sends a seed at all, so this also makes the very next publish
        // correctly send none until a fresh full refresh lands.
        lastVitalsRefreshDate = nil
        lastReadinessComputeDate = nil
        lastTrainingLoadComputeDate = nil
        lastMetricPullDates = [:]
        cachedComputeTrainingLoadSeed = nil
        cachedExpectedSourceIDsByKind = [:]
        authorizationState = .unknown
        healthDataNotice = String(localized: "Local cache cleared. Refresh to load Apple Health data again.")
        // Drop the generated readiness comment too — it describes the summary
        // this clear just wiped, and would otherwise reappear on relaunch.
        ReadinessCommentCache.clear()

        // Await the engine cache clears (previously fire-and-forget) so a refresh
        // started right after this can't race a half-cleared source/effort cache.
        await engine.clearSourceCache()
        await engine.clearWorkoutEffortCache()

        // Enqueue the file deletions on the serial persist queue so they land
        // AFTER any snapshot save already queued (FIFO), and await that barrier:
        // `isClearingCache` stays true — and the disk size / widget reload are
        // only recomputed — once the on-disk caches are actually gone, so an
        // earlier in-flight save can't resurrect a file after the wipe.
        await withCheckedContinuation { continuation in
            Self.snapshotPersistQueue.async {
                WorkoutSnapshotStore.delete()
                WorkoutSnapshotStore.deletePrevious()
                HealthDashboardSnapshotStore.delete()
                HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
                HealthDashboardSnapshotStore.clearWatchExpectedSourceIDs()
                HealthDashboardSnapshotStore.clearWatchTrainingLoadSeed()
                HealthDashboardSnapshotStore.clearActivityRingBackfillCompleted()
                HealthWidgetSnapshotStore.delete()
                WorkoutDetailSnapshotStore.deleteAll()
                continuation.resume()
            }
        }
        cacheDiskSizeBytes = 0
        BodyWidgetReloadCoalescer.shared.requestReload()

        // Blank the paired Watch too: a data-free reset tombstone the watch
        // ADOPTS (instead of blank-preserve merging), so cleared metrics don't
        // linger on the watch face / complications (H7). Sent directly — not via
        // the now-epoch-gated `publishWatchSnapshot` — with `publisherEpoch: nil`
        // so `send` stamps a fresh (epoch, revision) that supersedes prior pushes.
        // A nil permission omits the key, leaving the watch's last-synced
        // selection (unchanged by a cache clear) intact.
        let reset = WatchMetricsSnapshot(
            generatedAt: Date(),
            lastRefreshDate: nil,
            metrics: [],
            isReset: true
        )
        WatchConnectivityPublisher.shared.send(
            reset,
            permissionRawValue: nil,
            captureSequence: WatchConnectivityPublisher.shared.nextCaptureSequence(),
            computeSeedData: nil
        )
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
        // Early in a new month the 48h auto-apply window still reaches into the prior
        // month, so refresh it too when Auto-Apply is on — otherwise that month's
        // snapshot stays stale/absent and a workout from its last days (e.g. Jun 30 on
        // Jul 1) is never scanned and can age out of the window before a manual refresh.
        let autoApplyNeedsPriorMonth = UserDefaults.standard.bool(forKey: BodyAppearancePreference.autoApplyWorkoutEffortKey)
            && Self.autoApplyWindowMonthKeys(now: date, maxAge: Self.autoApplyMaxWorkoutAge, calendar: calendar).count > 1
        let monthCount: Int
        if intent == .passiveResume {
            monthCount = (wakeCycleCrossesMonth || autoApplyNeedsPriorMonth) ? 2 : 1
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
        // edited workouts re-query (this also makes the dashboard's
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

            let (fetchedHealthSummary, fetchedHealthTrends, fetchedActivityRingHistory, hadQueryFailure) =
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
            // Dashboard vitals + workouts have both just landed together (this
            // path always refreshes the dashboard) — the one point to refresh
            // the phone→watch compute seed's Training Load piece under the
            // SAME engine anchor date the dashboard fetch used. Gated on
            // `!hadQueryFailure` exactly like `lastVitalsRefreshDate` below, so
            // the two can't drift out of lockstep.
            await updateCachedComputeTrainingLoadSeedIfNeeded(
                date: date,
                calendar: calendar,
                includesWorkouts: includesWorkouts,
                fetchesTrainingLoad: dashboardFetchSelection.includes(.trainingLoad),
                hadQueryFailure: hadQueryFailure
            )
            // When the permission selection enables no readable types (all off,
            // or only dependent toggles like .dateOfBirth/.workoutMetrics left),
            // source discovery has no kinds, the dashboard fetch returns
            // defaults, and the workout refresh returns immediately — no
            // HealthKit query ran, so the badge must not confirm "Health data
            // updated" for this no-op.
            markRefreshSucceeded(date: date, refreshedVitals: true, publishesWatch: false, hadQueryFailure: hadQueryFailure, advancesSyncBadge: true, ranQueries: permissionSelectionCanRunQueries)
            updateCurrentMonthSnapshot(date: date, calendar: calendar)
            await reapplyActivityReadinessAfterWorkouts(date: date, calendar: calendar)
            publishWatchSnapshot()
            updateHealthDataNotice()
            // Workouts + dashboard have both committed here, so resting-HR / readiness
            // inputs are current for the estimator.
            await autoApplyPredictedEffortIfNeeded(monthKeys: Array(keys))
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
        // Hydrate on BOTH paths, not just the dashboard one. The warm
        // workout-only resume can still reach a snapshot save via
        // `reapplyActivityReadinessAfterWorkouts`, and every
        // `HealthDashboardSnapshotStore.save` rewrites the day-sample sidecar from
        // the passed trends — an empty payload overwrites an existing file. So a
        // relaunch inside the 5-minute TTL that picked up a new workout used to
        // wipe the intraday cache off disk instead of merely not showing it.
        await hydratePersistedDaySamplesIfNeeded()
        if updatesHealthSummary {
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

        var hadQueryFailure = false
        let dashboardFetchSelection = BodyDashboardFetchSelection.load()
        do {
            if updatesHealthSummary {
                await fetchHealthDataSourceOptions(calendar: calendar)

                let (fetchedHealthSummary, fetchedHealthTrends, fetchedActivityRingHistory, leafFailure) =
                    await fetchDashboardSnapshotProgressively(
                        calendar: calendar,
                        selection: dashboardFetchSelection
                    )
                hadQueryFailure = leafFailure

                await updateHealthDashboardSnapshot(
                    summary: fetchedHealthSummary,
                    trends: fetchedHealthTrends,
                    activityRingHistory: fetchedActivityRingHistory
                )
            }
            try await workoutRefresh
            authorizationState = .authorized
            // Only when this call actually refreshed the dashboard (mirrors
            // `refreshedVitals: updatesHealthSummary` below) have summary,
            // trends, and workouts all just landed together under the same
            // engine anchor date — the point to refresh the phone→watch
            // compute seed's Training Load piece. `refreshWorkoutMonth`
            // (`updatesHealthSummary == false`) skips this, leaving the seed
            // as of the last full refresh.
            if updatesHealthSummary {
                await updateCachedComputeTrainingLoadSeedIfNeeded(
                    date: refreshDate,
                    calendar: calendar,
                    includesWorkouts: includesWorkouts,
                    fetchesTrainingLoad: dashboardFetchSelection.includes(.trainingLoad),
                    hadQueryFailure: hadQueryFailure
                )
            }
            // A query ran if the dashboard fetch executed (`updatesHealthSummary`)
            // or the workout fetch did (`includesWorkouts`). When both are off —
            // e.g. `refreshWorkoutMonth` with Workouts permission disabled — no
            // query ran, so the badge must not confirm "Health data updated".
            // Same no-readable-types guard as the recent-months path: a
            // summary-updating refresh whose selection enables no read types
            // dispatches no queries either.
            let ranQueries = (updatesHealthSummary || includesWorkouts) && permissionSelectionCanRunQueries
            markRefreshSucceeded(date: refreshDate, refreshedVitals: updatesHealthSummary, publishesWatch: false, hadQueryFailure: hadQueryFailure, advancesSyncBadge: true, ranQueries: ranQueries)
            updateCurrentMonthSnapshot(date: refreshDate, calendar: calendar)
            await reapplyActivityReadinessAfterWorkouts(date: refreshDate, calendar: calendar)
            publishWatchSnapshot()
            updateHealthDataNotice()
            // Auto-apply for the refreshed month on every path (dashboard refresh AND the
            // Workouts-tab / warm-resume `refreshWorkoutMonth`, which passes
            // `updatesHealthSummary == false`). The 1-48h window self-limits candidates to
            // recent workouts, so browsing an older month simply finds none.
            await autoApplyPredictedEffortIfNeeded(monthKeys: [key])
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
        activityRingHistory: ActivityRingHistorySnapshot,
        hadQueryFailure: Bool
    ) {
        let cachedTrendsAtStart = healthTrends
        var fetchedSummary = healthSummary
        var fetchedTrends = healthTrends
        var fetchedActivityRingHistory = activityRingHistory
        // ORs every dashboard leaf's failure — summary, trends (primary +
        // secondary + sleep-vitals), and ring history/backfill — so any failed
        // query withholds the freshness TTL and the next resume retries (H2c).
        var hadQueryFailure = false
        let needsActivityRingBackfill = !HealthDashboardSnapshotStore.loadActivityRingBackfillCompleted()

        // Reuse the cached summary for failed leaves only while the current
        // selection still matches the one it was published under; a source /
        // permission switch invalidates it so failure resolves to empty.
        let currentSignature = currentPrimarySummarySignature()
        let cachedSummaryForReuse: HealthSummarySnapshot? =
            healthSummaryPrimarySignature == currentSignature ? healthSummary : nil

        let engine = self.engine
        await withTaskGroup(of: DashboardFetchUnit.self) { group in
            group.addTask {
                let signpostState = BodyPerformanceSignposts.signposter.beginInterval("DashboardSummary")
                defer { BodyPerformanceSignposts.signposter.endInterval("DashboardSummary", signpostState) }
                return .summary(
                    await engine.fetchHealthSummary(
                        calendar: calendar,
                        selection: selection,
                        cachedSummary: cachedSummaryForReuse
                    )
                )
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
                case .summary(let result):
                    fetchedSummary = result.summary
                    hadQueryFailure = hadQueryFailure || result.hadQueryFailure
                    // Keep the cached `readiness` visible during the progressive
                    // publish — the final filtered+recomputed snapshot overrides
                    // it in `updateHealthDashboardSnapshot`.
                    healthSummary = result.summary.replacingMetric(.readiness, with: healthSummary)
                case .trends(let result):
                    hadQueryFailure = hadQueryFailure || result.hadQueryFailure
                    let t = result.trends
                    fetchedTrends = t
                    // `fetchHealthTrends` does not populate `.readiness` (it gets
                    // recomputed in `updateHealthDashboardSnapshot`). Preserve
                    // the cached series so the Readiness preview chart can
                    // animate from old values to new instead of dropping to
                    // empty and reappearing.
                    healthTrends = t.replacingMetric(.readiness, with: healthTrends)
                case .rings(let result):
                    hadQueryFailure = hadQueryFailure || result.hadQueryFailure
                    let r = result.history
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

        return (fetchedSummary, fetchedTrends, fetchedActivityRingHistory, hadQueryFailure)
    }

    /// Primary-source + permission signature the summary reuse is scoped to.
    /// Cheap to recompute; captured at publish and compared at the next fetch
    /// (and persisted with the snapshot for cold-start reuse, H2a). Includes the
    /// two sleep-stage display prefs and the combine flag because sleep-summary
    /// parsing depends on them (`+Sleep.swift`) — so a pref change while the app
    /// is closed conservatively invalidates the reuse instead of resurrecting a
    /// value parsed under different grouping.
    private func currentPrimarySummarySignature() -> String {
        let showsSubMinuteAwake = BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()
        let showsLeadingTrailingAwake = BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()
        return "\(healthDataSourceSelection.rawValue)|\(permissionSelection.rawValue)|\(combinesHealthDataSourcesByName)|\(showsSubMinuteAwake)|\(showsLeadingTrailingAwake)" + customSourceGroupsSignatureSuffix
    }

    /// What a custom group's MEMBERSHIP adds to every cache signature. Empty
    /// when there are no groups, so a user who never made one signs exactly the
    /// bytes they signed before this feature existed — no cache is dropped and
    /// no seed re-ships on upgrade. Names are excluded (the canonical signature
    /// omits them), so a rename changes nothing either.
    nonisolated static func customSourceGroupsSignatureSuffix(
        for groups: [BodyCustomHealthSourceGroup]
    ) -> String {
        guard !groups.isEmpty else {
            return ""
        }

        return "|groups=\(BodyCustomHealthSourceGroupStore.canonicalSignature(for: groups))"
    }

    private var customSourceGroupsSignatureSuffix: String {
        Self.customSourceGroupsSignatureSuffix(for: customHealthSourceGroups)
    }

    /// The selection signatures every cache write AND every cache read must use
    /// — a selection's own `.signature` says nothing about what the `custom:`
    /// ids in it currently RESOLVE to, so a membership edit has to invalidate
    /// through here. Reading and writing through the same two helpers is what
    /// keeps the day-sample sidecar hydratable across a launch (a mismatch
    /// silently drops the Day View cache every time).
    private func currentPrimarySelectionSignature() -> String {
        healthDataSourceSelection.signature + customSourceGroupsSignatureSuffix
    }

    private func currentSecondarySelectionSignature() -> String {
        secondaryHealthDataSourceSelection.signature + customSourceGroupsSignatureSuffix
    }

    /// The source + permission signatures the day-sample sidecar is being
    /// written under. Single capture point (Codex MAJOR 8): EVERY sidecar-
    /// writing save reads this on the main actor before dispatching to the
    /// persist queue, so all four write paths stamp the same complete set and
    /// hydration can reject a sidecar captured under a now-different selection
    /// instead of merging stale other-source intraday points (H6).
    /// Kinds whose comparison series the CURRENT selection resolves away — Body Pro
    /// locked, an unresolvable secondary source, or a primary source changed to
    /// match the secondary. None of these alter the stored secondary selection, so
    /// they leave `currentSecondarySelectionSignature()` unchanged and the sidecar's
    /// captured stamps can't express them; hydration has to read them live.
    private func currentComparisonDisabledKinds() -> Set<HealthMetricKind> {
        let kinds = HealthMetricKind.sourceSelectableKinds
            .filter(\.supportsSecondaryHealthDataSourceSelection)
            .filter { selectedSecondaryHealthDataSourceOption(for: $0).isNoComparison }
        return Set(kinds)
    }

    private func currentDaySampleSignatures() -> HealthTrendDaySampleSignatures {
        HealthTrendDaySampleSignatures(
            primarySelectionSignature: currentPrimarySelectionSignature(),
            secondarySelectionSignature: currentSecondarySelectionSignature(),
            permissionSignature: permissionSelection.rawValue,
            combinesHealthDataSourcesByName: combinesHealthDataSourcesByName
        )
    }

    private enum DashboardFetchUnit {
        case summary(HealthKitFetchEngine.HealthSummaryFetchResult)
        case trends(HealthKitFetchEngine.HealthTrendFetchResult)
        case rings(ActivityRingHistoryFetchResult)
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

        // This lazy month load runs without `isRefreshing`, so a Clear Cache can
        // land during its fetch. Capture the epoch and bail on the post-fetch
        // publish if it did (the fetch itself is epoch-guarded in `refresh`).
        let epoch = cacheEpoch
        loadingMonthKeys.formUnion(keysToLoad)
        defer {
            loadingMonthKeys.subtract(keysToLoad)
            finishMonthLoad(for: keysToLoad)
        }

        do {
            try await requestHealthKitAuthorization()
            try await refresh(monthKeys: keysToLoad, calendar: .bodyGregorian)
            guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
                return
            }
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

        // Captured before the fetch so a Clear Cache that lands mid-load (only
        // possible from the lazy, non-`isRefreshing` month loads) can't resurrect
        // a wiped month via the progressive writes below. Under `isRefreshing`
        // paths the epoch can't change, so this guard is a no-op there.
        let epoch = cacheEpoch
        let engine = self.engine
        try await withThrowingTaskGroup(
            of: (BodyWorkoutMonthKey, [WorkoutSummary]).self
        ) { group in
            for key in orderedKeys {
                // Always hand the engine the month's cached summaries so the
                // effort / HR failure fallback can reuse them; HR-payload REUSE
                // (skipping the batched HR query for aged workouts) stays gated
                // on `allowsHeartRateReuse` — passive resumes only, so every
                // user-initiated pull-to-refresh remains a full HR reconcile.
                let reusableSummariesByID: [UUID: WorkoutSummary]
                if let cachedDays = monthSnapshots[key]?.days {
                    reusableSummariesByID = Dictionary(
                        cachedDays.flatMap(\.workouts).map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                } else {
                    reusableSummariesByID = [:]
                }
                let allowsHeartRateReuse = reusesCachedWorkoutHeartRate
                group.addTask {
                    let workouts = try await engine.fetchWorkouts(
                        month: key.month,
                        year: key.year,
                        calendar: calendar,
                        allowsHeartRateReuse: allowsHeartRateReuse,
                        reusableSummariesByID: reusableSummariesByID
                    )
                    return (key, workouts)
                }
            }

            // Publish each month's snapshot as it returns so the Workouts tab
            // populates progressively instead of waiting for the slowest month.
            for try await (key, workouts) in group {
                // A cache clear landed mid-load — drop the remaining month writes
                // instead of resurrecting them onto the wiped snapshots.
                guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
                    continue
                }
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
    /// The single-metric-pull kinds that map onto a watch card and therefore
    /// need their own `perKindDataAsOf` stamp (`lastMetricPullDates`).
    /// Readiness and Training Load carry their dedicated watermarks instead;
    /// the raw values match `WatchMetricKindKey` (pinned by
    /// `ProjectConfigurationTests`).
    nonisolated static let watchVitalsPullKinds: Set<HealthMetricKind> = [
        .heartRate,
        .heartRateVariability,
        .restingHeartRate,
        .sleep,
        .wristTemperature
    ]

    nonisolated static let readinessInputMetricKinds: Set<HealthMetricKind> = [
        .readiness,
        .sleep,
        .restingHeartRate,
        .heartRateVariability,
        .respiratoryRate,
        .oxygenSaturation,
        .trainingLoad,
        .wristTemperature,
        .vitals
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
        let epoch = cacheEpoch
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

        // A Clear Cache that landed while the off-actor recompute ran must win:
        // don't publish or persist the recomputed snapshot onto the wiped state.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return
        }

        let nextActivityRingHistory = self.activityRingHistory.replacingLoadedMonths(
            with: filteredSnapshot.activityRingHistory,
            calendar: calendar
        )
        healthSummary = filteredSnapshot.summary
        // Scope the summary reuse to the selection this snapshot reflects.
        healthSummaryPrimarySignature = currentPrimarySummarySignature()
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
        let secondarySignature = currentSecondarySelectionSignature()
        let daySampleSignatures = currentDaySampleSignatures()
        // Persist the summary-context signature just stamped above so a cold
        // start can gate the summary reuse (H2a). Rides inside the snapshot, so
        // it saves atomically with the data on every path.
        let summaryContextSignature = healthSummaryPrimarySignature
        Self.snapshotPersistQueue.async {
            HealthDashboardSnapshotStore.save(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature
            )
            HealthDashboardSnapshotStore.saveSecondarySelectionSignature(secondarySignature)
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
        saveHealthWidgetSnapshot()
    }

    /// Wake time valid for freezing the scoring day's morning record. Delegates to
    /// the shared pure static (`ReadinessComputeSupport`) so the watch's on-device
    /// compute reuses the identical math; kept here under the same name/signature
    /// for existing call sites and tests.
    nonisolated static func freezeWakeTime(
        sleepEnd: Date?,
        scoringDay: Date,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        ReadinessComputeSupport.freezeWakeTime(sleepEnd: sleepEnd, scoringDay: scoringDay, now: now, calendar: calendar)
    }

    /// Start of the current wake cycle for the activity-drain window. Delegates to
    /// the shared pure static (`ReadinessComputeSupport`); kept here under the same
    /// name/signature for existing call sites and tests.
    nonisolated static func wakeCycleStart(now: Date, sleepEnd: Date?, calendar: Calendar) -> Date {
        ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: sleepEnd, calendar: calendar)
    }

    /// Workouts done since the start of the current wake cycle, up to `now`.
    /// These drive the same-day readiness drain. Keeps the month-cache read
    /// (impure); the window filter itself is the shared pure
    /// `ReadinessComputeSupport.wakeCycleWorkouts`.
    private func currentWakeCycleWorkouts(
        now: Date,
        sleepEnd: Date?,
        calendar: Calendar
    ) -> [WorkoutSummary] {
        let allWorkouts = monthSnapshots.values
            .flatMap(\.days)
            .flatMap(\.workouts)
        return ReadinessComputeSupport.wakeCycleWorkouts(
            from: allWorkouts,
            now: now,
            sleepEnd: sleepEnd,
            calendar: calendar
        )
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
        // Readiness is being re-derived (drain + morning freeze) from workouts
        // that just landed — the watch's readiness watermark. This is the only
        // place it advances on a WORKOUT-ONLY refresh, where
        // `lastVitalsRefreshDate` deliberately stands still. Training Load's
        // watermark does NOT advance here: this reapply never recomputes the
        // Training Load summary/series, so stamping it fresh would be a lie.
        lastReadinessComputeDate = date

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
        let daySampleSignatures = currentDaySampleSignatures()
        // Carry the current summary-context signature so the readiness-reapply
        // save doesn't clobber the persisted one back to nil (H2a). Readiness
        // isn't part of the signature, so it still describes `updated.summary`.
        let summaryContextSignature = healthSummaryPrimarySignature
        Self.snapshotPersistQueue.async {
            HealthDashboardSnapshotStore.save(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature
            )
        }
        saveHealthWidgetSnapshot()
    }

    /// The next `lastVitalsRefreshDate` — the compute seed's `dataThrough`
    /// watermark (C4) — for a refresh outcome. Advances only on a clean full
    /// vitals refresh (`refreshedVitals && !hadQueryFailure`); every other
    /// call (a settings-only republish passes `refreshedVitals: false`, a
    /// leaf query failure passes `hadQueryFailure: true`) returns `current`
    /// unchanged, so publishing more often — or a partial refresh — never
    /// looks like fresher data to the watch. Pure so this is directly
    /// unit-testable without a store instance.
    nonisolated static func nextLastVitalsRefreshDate(
        current: Date?,
        date: Date,
        refreshedVitals: Bool,
        hadQueryFailure: Bool
    ) -> Date? {
        guard refreshedVitals, !hadQueryFailure else { return current }
        return date
    }

    /// Internal (not private) so tests can assert the TTL gating below without
    /// a HealthKit round trip.
    func markRefreshSucceeded(
        date: Date,
        refreshedVitals: Bool,
        publishesWatch: Bool = true,
        hadQueryFailure: Bool = false,
        advancesSyncBadge: Bool = false,
        ranQueries: Bool = true
    ) {
        // Only a user-visible refresh (one of the three paths that hold
        // `isRefreshing`) that genuinely fetched — no query failure, and at
        // least one HealthKit query actually ran — advances the sync-badge
        // signal. Lazy month/ring history loads run WITHOUT `isRefreshing` and
        // pass `advancesSyncBadge == false`, so a background page-in can never
        // make the badge confirm a refresh the user is watching (which may
        // itself be failing). `ranQueries == false` covers pulls that skipped
        // every query — a metric or workout month whose permission is disabled —
        // so a no-op pull can't announce "Health data updated" either. See
        // `BodyHealthSyncBadge`.
        if advancesSyncBadge, !hadQueryFailure, ranQueries {
            syncBadgeSuccessCount += 1
        }
        // `lastSuccessfulRefreshDate` arms the 5-minute dashboard-freshness TTL
        // (`syncWhenAppBecomesActive`, and the cold-start path that restores the
        // persisted value), so only refreshes that actually refetched the
        // dashboard vitals may set it. Lazy history loads (month paging, older
        // ring months), single-metric refreshes, and workout-only warm resumes
        // must not re-arm it — otherwise paging history or resuming repeatedly
        // keeps the TTL fresh and the vitals refresh is skipped indefinitely.
        // Those paths keep their own throttling (`lastAppEntrySyncDate`,
        // `loadedMonthKeys`/`loadingMonthKeys`), which this does not feed.
        // A `hadQueryFailure` refresh still published its resolved (cache-
        // preserving) snapshot, but at least one dashboard leaf query (summary,
        // trends, or ring history) failed — don't arm the freshness TTL, so the
        // next resume retries the partial result instead of trusting it as
        // 5-minutes-fresh.
        // The compute seed's `dataThrough` watermark: pure so the "settings-only
        // republish carries it forward, a clean full refresh advances it" rule
        // is unit-testable without a store instance (see
        // `HealthKitWorkoutStoreComputeSeedTests`).
        lastVitalsRefreshDate = Self.nextLastVitalsRefreshDate(
            current: lastVitalsRefreshDate, date: date, refreshedVitals: refreshedVitals, hadQueryFailure: hadQueryFailure
        )
        if refreshedVitals, !hadQueryFailure {
            lastSuccessfulRefreshDate = date
            HealthDashboardSnapshotStore.saveLastSuccessfulRefreshDate(date)
            // A clean full refresh re-derived readiness from this fetch too, so
            // its watch watermark advances with it. (The workout-only paths
            // advance it on their own, from
            // `reapplyActivityReadinessAfterWorkouts`; Training Load's own
            // watermark advances from `updateCachedComputeTrainingLoadSeedIfNeeded`,
            // which knows whether the fetch selection actually recomputed it.)
            lastReadinessComputeDate = date
        }
        // The full-refresh paths suppress this and publish once after the
        // post-workout reapply, so the watch ships the drained value rather than
        // the pre-drain one. Other callers (single-metric, warm resume) publish
        // here because no reapply follows.
        if publishesWatch {
            publishWatchSnapshot()
        }
    }

    /// Refreshes `cachedComputeTrainingLoadSeed` — the phone→watch compute
    /// seed's Training Load piece — from the engine's memoized workout window,
    /// called ONLY from the two full-refresh call sites at the point
    /// dashboard vitals and workouts have both just landed. Gated on
    /// `!hadQueryFailure` so it advances in lockstep with `lastVitalsRefreshDate`
    /// (the seed's `dataThrough`): a refresh with a leaf failure updates
    /// neither, so the two can never describe different data-coverage points.
    /// Also gated on `includesWorkouts` (no workout data to compute from when
    /// disabled), on `fetchesTrainingLoad`, and on the engine call succeeding —
    /// any of those guards leaves the previous cache untouched rather than
    /// blanking it, mirroring `fetchTrainingLoadSeries`'s keep-stale-on-failure
    /// convention.
    ///
    /// `fetchesTrainingLoad` is the dashboard fetch selection's own
    /// `.trainingLoad` bit, and it is a COST gate, not a correctness one: the
    /// engine accessor reuses the memoized `sharedTrainingLoadWorkouts` window,
    /// but only the dashboard's own Training Load fetch ever warms that memo.
    /// For a user who has hidden both the Training Load and Readiness cards the
    /// memo is cold on every refresh, so calling in anyway would run a fresh
    /// ~408-day `fetchWorkoutSummaries` plus a per-workout effort fan-out —
    /// with the effort cache cleared on user-initiated refreshes — purely to
    /// populate a seed field. The watch keeps the last cached seed value
    /// instead.
    private func updateCachedComputeTrainingLoadSeedIfNeeded(
        date: Date,
        calendar: Calendar,
        includesWorkouts: Bool,
        fetchesTrainingLoad: Bool,
        hadQueryFailure: Bool
    ) async {
        guard includesWorkouts, fetchesTrainingLoad, !hadQueryFailure else {
            return
        }
        // The guard above certifies the dashboard fetch just recomputed the
        // Training Load summary/series cleanly — the honest place to advance
        // TL's watch watermark. Deliberately BEFORE the engine-seed guard
        // below: the seed accessor reuses the memoized workout window and can
        // fail independently of the summary fetch, and a failed seed refresh
        // doesn't make the just-recomputed summary any less fresh.
        lastTrainingLoadComputeDate = date
        guard let seed = await engine.trainingLoadDailyLoadSeed(calendar: calendar) else {
            return
        }
        setCachedComputeTrainingLoadSeed(startDay: seed.startDay, loads: seed.loads, through: date)
    }

    /// Rebuilds and republishes both companion snapshots (iOS widget + watch)
    /// from the currently-published health summary/trends. For preference
    /// changes that only affect formatting (units, sleep goal, show-sleep-
    /// score) a full refetch is unnecessary — a rebuild from what's already
    /// published is enough. Skipped while a cache clear is in flight so it
    /// can't resurrect state the clear is wiping.
    func republishCompanionSnapshots() {
        guard !isClearingCache else { return }
        saveHealthWidgetSnapshot()
        publishWatchSnapshot()
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
        // — mirroring `saveHealthWidgetSnapshot`. Send ordering rides on the
        // monotonic capture sequence allocated here (clock-immune, M5) rather than
        // `now`, and the permission value is paired at capture time so a queued
        // build can't ship a newer selection.
        let epoch = cacheEpoch
        let summary = healthSummary
        let trends = healthTrends
        let lastRefreshDate = lastVitalsRefreshDate
        let permissionSelection = permissionSelection
        let temperatureUnitPreference = HealthWidgetSnapshotBuilder.storedTemperatureUnitPreference()
        let idealSleepDuration = Self.storedIdealSleepDuration()
        let showSleepScore = HealthWidgetSnapshotBuilder.storedShowSleepScore()
        let now = Date()
        // Allocate the capture sequence at this main-actor capture point so its
        // order equals capture order (see `WatchConnectivityPublisher`).
        let captureSequence = WatchConnectivityPublisher.shared.nextCaptureSequence()
        let permissionRawValue = BodyHealthPermissionSelection.load().rawValue

        // Phase 3 compute-seed capture, alongside the display-snapshot inputs
        // above so both ship from the same consistent state. `summary`/
        // `trends` are read LIVE (same as the display snapshot) — they're
        // already the store's best current data whether this publish came
        // from a full refresh or a settings-only republish (permission /
        // preference changes refilter them in place without a new fetch), so
        // no separate "carried" copy is needed. Only `dataThrough` and the
        // Training Load piece are genuinely frozen between full refreshes:
        // `lastVitalsRefreshDate` already advances ONLY on a clean full
        // refresh (never on a republish), and `cachedComputeTrainingLoadSeed`
        // is kept in lockstep with it (`updateCachedComputeTrainingLoadSeedIfNeeded`)
        // — so a settings-only republish reaching this same code path
        // automatically carries both forward unchanged, satisfying "never
        // advance `dataThrough` on publication" without extra bookkeeping.
        // `nil` `dataThrough` (no full refresh yet this session) sends no seed.
        let dataThrough = lastVitalsRefreshDate
        // Honest per-kind watermarks, SPLIT because they genuinely differ: a
        // workout-only refresh re-drains readiness but never recomputes
        // Training Load. Readiness `max`es with the vitals date so a full
        // refresh whose Workouts permission is off (no
        // `reapplyActivityReadinessAfterWorkouts`) still stamps it at least as
        // fresh as the vitals it was computed from. Training Load stays nil
        // until it is actually recomputed — the builder then falls back to the
        // uniform vitals stamp (the pre-split legacy behavior for a value that
        // has no fresher provenance).
        let readinessComputeDate = [lastVitalsRefreshDate, lastReadinessComputeDate]
            .compactMap { $0 }
            .max()
        let trainingLoadComputeDate = lastTrainingLoadComputeDate
        let metricPullDates = lastMetricPullDates
        let trainingLoadSeed = cachedComputeTrainingLoadSeed
        let expectedSourceIDsByKind = cachedExpectedSourceIDsByKind
        let followsSystemUnits = UserDefaults.standard.object(
            forKey: BodyAppearancePreference.followsSystemUnitsKey
        ) as? Bool ?? true
        let selectedTemperatureUnitRaw = UserDefaults.standard.string(
            forKey: BodyAppearancePreference.selectedTemperatureUnitKey
        ) ?? BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
        let showsSubMinuteAwakeStages = BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()
        let showsLeadingTrailingAwakeStages = BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages()
        // Body Pro gate for the seed: the watch has no entitlement concept, so
        // a lapsed subscription has to ship the All-Sources view the phone now
        // renders — otherwise the watch keeps filtering by a group the phone
        // stopped applying, and the two disagree indefinitely. The definitions
        // are withheld, never erased; the entitlement observer republishes on a
        // flip and the changed `src[…]`/`groups[…]` signature re-seeds.
        let isProUnlocked = BodyProEntitlement.isUnlocked
        let healthDataSourceSelectionRaw = isProUnlocked
            ? healthDataSourceSelection.rawValue
            : Self.selectionNeutralizingCustomSources(healthDataSourceSelection).rawValue
        let customHealthSourceGroupsRaw = isProUnlocked && !customHealthSourceGroups.isEmpty
            ? BodyCustomHealthSourceGroupStore.rawValue(from: customHealthSourceGroups)
            : nil
        let combinesByName = combinesHealthDataSourcesByName
        // Only the seed needs the 14-day time-zone map, and building it costs 14
        // `UserDefaults` reads + `JSONDecoder` allocations on the main actor —
        // so build it only when a seed will actually be assembled below.
        let recentTimeZoneIdentifiersByDay = dataThrough == nil
            ? [:]
            : Self.recentTimeZoneIdentifiersByDay(now: now)

        Self.snapshotPersistQueue.async {
            var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
                summary: summary,
                trends: trends,
                lastRefreshDate: lastRefreshDate,
                permissionSelection: permissionSelection,
                temperatureUnitPreference: temperatureUnitPreference,
                idealSleepDuration: idealSleepDuration,
                showSleepScore: showSleepScore,
                now: now,
                // Readiness and Training Load carry their own watermarks: a
                // workout-only refresh re-drains readiness (only) while
                // `lastRefreshDate` (the VITALS watermark) deliberately stands
                // still. Stamping uniformly would present genuinely fresh
                // readiness as stale — or, joint-stamping both, present a NOT
                // recomputed Training Load as fresh. Either way the watch's
                // per-metric compare then picks the wrong side. Every other
                // kind (and a never-recomputed Training Load) falls through to
                // the uniform vitals date.
                perKindDataAsOf: { kind in
                    switch kind {
                    case WatchMetricKindKey.readiness:
                        return readinessComputeDate
                    case WatchMetricKindKey.trainingLoad:
                        return trainingLoadComputeDate
                    default:
                        // A single-metric detail pull refreshes one vitals kind
                        // without advancing the full-refresh date — take the
                        // newer of the two so the pulled value doesn't ship
                        // under a stale stamp.
                        return [lastRefreshDate, metricPullDates[kind]]
                            .compactMap { $0 }
                            .max()
                    }
                }
            )
            snapshot.source = "phone"

            // Build the compute seed off-actor too (trend trimming + zlib
            // compression are the expensive parts). `nil` when no full
            // refresh has landed yet this session, or when the encoded
            // payload alone blows its size budget (the watch just keeps
            // whatever seed it already has).
            var computeSeedData: Data?
            var computeSeedSettingsSignature: String?
            if let dataThrough {
                let settings = WatchComputeSettings(
                    idealSleepDurationMinutes: Int((idealSleepDuration / 60).rounded()),
                    followsSystemUnits: followsSystemUnits,
                    selectedTemperatureUnitRaw: selectedTemperatureUnitRaw,
                    showSleepScore: showSleepScore,
                    showsSubMinuteAwakeSleepStages: showsSubMinuteAwakeStages,
                    showsLeadingTrailingAwakeSleepStages: showsLeadingTrailingAwakeStages,
                    healthDataSourceSelectionRaw: healthDataSourceSelectionRaw,
                    combinesHealthDataSourcesByName: combinesByName,
                    customHealthSourceGroupsRaw: customHealthSourceGroupsRaw,
                    recentTimeZoneIdentifiersByDay: recentTimeZoneIdentifiersByDay
                )
                let seed = Self.makeComputeSeed(
                    summary: summary,
                    trends: trends,
                    dataThrough: dataThrough,
                    lastVitalsRefreshDate: lastRefreshDate,
                    trainingLoadStartDay: trainingLoadSeed?.startDay,
                    trainingLoadDailyLoads: trainingLoadSeed?.loads,
                    trainingLoadDataThrough: trainingLoadSeed?.through,
                    expectedSourceIDsByKind: expectedSourceIDsByKind.isEmpty ? nil : expectedSourceIDsByKind,
                    settings: settings,
                    publishedAt: now
                )
                // The signature ships even when the blob below is dropped for
                // size or fails to encode — it's what lets the watch notice
                // its STORED seed was built under settings the phone has since
                // changed, and invalidate it instead of computing with a stale
                // configuration.
                computeSeedSettingsSignature = seed.settingsSignature
                if let encoded = seed.encodedCompressed() {
                    if encoded.count <= Self.computeSeedSizeBudgetBytes {
                        computeSeedData = encoded
                    } else {
                        Self.computeSeedLogger.error(
                            "Compute seed dropped: encoded size \(encoded.count, privacy: .public) bytes exceeded the \(Self.computeSeedSizeBudgetBytes, privacy: .public)-byte budget."
                        )
                    }
                } else {
                    Self.computeSeedLogger.error("Compute seed encode failed.")
                }
            }

            Task { @MainActor in
                // A Clear Cache that bumped the epoch after this snapshot was
                // captured must win — don't ship pre-clear metrics onto the wiped
                // state (H7). The reset send in `clearLocalCache` blanks the watch.
                guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: self.cacheEpoch) else {
                    return
                }
                WatchConnectivityPublisher.shared.send(
                    snapshot,
                    permissionRawValue: permissionRawValue,
                    captureSequence: captureSequence,
                    computeSeedData: computeSeedData,
                    computeSeedSettingsSignature: computeSeedSettingsSignature
                )
            }
        }
    }

    /// Pure assembly of the phone→watch compute seed (Phase 3) from
    /// already-captured inputs — no store/actor access, so it runs off-actor
    /// in `publishWatchSnapshot` and is directly unit-testable. Trims `trends`
    /// to the compute-relevant window ending at `dataThrough` (the seed's data
    /// watermark, NOT `publishedAt`).
    ///
    /// `seriesRanges` is derived from the FULL, untrimmed `trends` — the same
    /// series the phone's own snapshot draws its `rangeMin`/`rangeMax` from —
    /// so the watch's range union reproduces the PHONE's displayed bounds. From
    /// the trimmed 70-day slice it could not: a user whose yearly HR/HRV/RHR/
    /// skin-temp extreme is older than the trim window would see the watch's
    /// ring fill and chart bounds diverge from the phone's, and nothing in the
    /// watch's own short delta could ever recover the missing extreme.
    nonisolated static func makeComputeSeed(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        dataThrough: Date,
        lastVitalsRefreshDate: Date?,
        trainingLoadStartDay: Date?,
        trainingLoadDailyLoads: [Double]?,
        trainingLoadDataThrough: Date?,
        expectedSourceIDsByKind: [String: [String]]?,
        settings: WatchComputeSettings,
        publishedAt: Date
    ) -> WatchComputeSeed {
        let trimmedTrends = trends.watchComputeTrimmed(anchor: dataThrough, calendar: .bodyGregorian)
        return WatchComputeSeed(
            publishedAt: publishedAt,
            dataThrough: dataThrough,
            lastVitalsRefreshDate: lastVitalsRefreshDate,
            summary: summary,
            trends: trimmedTrends,
            seriesRanges: WatchMetricsSnapshotBuilder.seriesRanges(from: trends),
            trainingLoadStartDay: trainingLoadStartDay,
            trainingLoadDailyLoads: trainingLoadDailyLoads,
            trainingLoadDataThrough: trainingLoadDataThrough,
            expectedSourceIDsByKind: expectedSourceIDsByKind,
            settings: settings,
            settingsSignature: Self.computeSettingsSignature(settings)
        )
    }

    /// Stable hash of the compute-relevant settings (mirrors
    /// `readinessRecordContextSignature`'s "join distinguishing fields into one
    /// string" style): same inputs → same signature, so the watch can detect
    /// "did anything that changes the math change?" without a field-by-field
    /// compare. `recentTimeZoneIdentifiersByDay` is deliberately excluded —
    /// it's data (and changes daily regardless of user intent), not a setting.
    nonisolated static func computeSettingsSignature(_ settings: WatchComputeSettings) -> String {
        // Groups extend the signature ONLY when the seed actually carries some,
        // so every pre-feature (and group-less) seed signs byte-identically and
        // the watch doesn't discard its stored seed on upgrade. Signed in the
        // canonical form for the same reason `src[…]` is: names and JSON key
        // order must not move the signature.
        let customGroups = BodyCustomHealthSourceGroupStore.groups(from: settings.customHealthSourceGroupsRaw ?? "")
        let customGroupsFragment = customGroups.isEmpty
            ? ""
            : ";groups[\(BodyCustomHealthSourceGroupStore.canonicalSignature(for: customGroups))]"
        return "d[\(settings.idealSleepDurationMinutes)]" +
            ";u[\(settings.followsSystemUnits ? "1" : "0")]" +
            ";t[\(settings.selectedTemperatureUnitRaw)]" +
            ";sc[\(settings.showSleepScore ? "1" : "0")]" +
            ";sub[\(settings.showsSubMinuteAwakeSleepStages ? "1" : "0")]" +
            ";lead[\(settings.showsLeadingTrailingAwakeSleepStages ? "1" : "0")]" +
            // Sign the selection's CANONICAL (sorted) form, never the raw JSON:
            // `JSONEncoder` dictionary key order can change between phone
            // processes, and a signature that flips on relaunch makes the
            // watch treat an ordinary republish as a settings change — strip
            // fresher local provenance and fall back to older phone values.
            ";src[\(BodyHealthDataSourceSelection.storedValue(from: settings.healthDataSourceSelectionRaw).canonicalSignature)]" +
            ";comb[\(settings.combinesHealthDataSourcesByName ? "1" : "0")]" +
            customGroupsFragment
    }

    /// The primary selection as a Pro-locked watch must see it: every `custom:`
    /// pick mapped to All Sources. Built directly rather than through
    /// `settingDefault`, whose same-id filtering would also drop unrelated
    /// per-kind overrides.
    nonisolated static func selectionNeutralizingCustomSources(
        _ selection: BodyHealthDataSourceSelection
    ) -> BodyHealthDataSourceSelection {
        BodyHealthDataSourceSelection(
            defaultOption: selection.defaultOption.isCustomSource ? .allSources : selection.defaultOption,
            selectedOptions: selection.selectedOptions.mapValues { option in
                option.isCustomSource ? BodyHealthDataSourceOption.allSources : option
            }
        )
    }

    /// Last-14-day time zone map for `WatchComputeSettings.recentTimeZoneIdentifiersByDay`,
    /// keyed by ISO day string ("yyyy-MM-dd") — never `[Date: String]`, whose
    /// JSON encoding is a nondeterministic unkeyed array. Lets the watch's
    /// sleep assembly resolve a recent night's time zone the same way the
    /// phone's `BodyTimeZoneLedger` does, falling back to
    /// `TimeZone.current.identifier` for a day the ledger has no record for
    /// (Phase 4). Days the ledger can't resolve are simply omitted.
    nonisolated static func recentTimeZoneIdentifiersByDay(
        now: Date,
        calendar: Calendar = .bodyGregorian,
        ledger: BodyTimeZoneLedger = BodyTimeZoneLedger()
    ) -> [String: String] {
        let dayFormatter = BodyDateFormatterCache.formatter(
            dateFormat: "yyyy-MM-dd",
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: calendar.timeZone
        )
        let anchorDay = calendar.startOfDay(for: now)
        var map: [String: String] = [:]
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchorDay),
                  let identifier = ledger.zoneIdentifier(on: day) else {
                continue
            }
            map[dayFormatter.string(from: day)] = identifier
        }
        return map
    }

    /// Size budget for the compute seed alone (before the display snapshot and
    /// permission key are added on top) — the `WatchComputeSeedTests` size test
    /// pins a realistic 70-day fixture comfortably under this. Separate from
    /// `WatchConnectivityPublisher`'s whole-context budget, which accounts for
    /// the other context keys too.
    nonisolated private static let computeSeedSizeBudgetBytes = 50_000

    nonisolated private static let computeSeedLogger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchComputeSeed")

    /// Builds the slim widget snapshot from the current trends, sleep stages,
    /// source selection, and unit preferences, then writes it to the App Group
    /// so the trend + sleep-stage widgets can render. Reads run on the main
    /// actor; the build + disk write happen off-actor.
    private func saveHealthWidgetSnapshot() {
        let trends = healthTrends
        let summary = healthSummary
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
        idealSleepDuration: TimeInterval,
        showsSubMinuteAwakeStages: Bool,
        showsLeadingTrailingAwakeStages: Bool,
        // A `custom:` source id says nothing about what it RESOLVES to, so the
        // group membership has to ride along or a membership edit would leave
        // the frozen morning records tagged as still-current. Defaults to the
        // empty suffix: no groups ⇒ byte-identical to every record already
        // frozen on disk.
        customSourceGroupsSignatureSuffix: String = ""
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
        // Sleep-stage display prefs change the parsed segments, and thus the
        // readiness sleep-continuity input (awake duration / sleep window), so
        // toggling either must drop and recompute the frozen morning records too.
        let awakeFlags = "a[\(showsSubMinuteAwakeStages ? "1" : "0")];l[\(showsLeadingTrailingAwakeStages ? "1" : "0")]"
        return "p[\(permissions)];s[\(sources)];c[\(combinesHealthDataSourcesByName ? "1" : "0")];g[\(sleepGoalMinutes)];\(awakeFlags)" + customSourceGroupsSignatureSuffix
    }

    private func readinessRecordContextSignature() -> String {
        Self.readinessRecordContextSignature(
            permissionSelection: permissionSelection,
            healthDataSourceSelection: healthDataSourceSelection,
            combinesHealthDataSourcesByName: combinesHealthDataSourcesByName,
            idealSleepDuration: Self.storedIdealSleepDuration(),
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages(),
            customSourceGroupsSignatureSuffix: customSourceGroupsSignatureSuffix
        )
    }

    private func applyPermissionSelectionToCachedData() async {
        // Runs without `isRefreshing` (from a permission toggle), so a Clear
        // Cache can land during the sidecar load / off-actor filter below.
        let epoch = cacheEpoch
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

        // A cache clear landed mid-filter — don't republish/persist the filtered
        // snapshot onto the wiped state.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return
        }

        healthSummary = filteredSnapshot.summary
        // Re-scope the summary reuse to the now-applied permission selection.
        healthSummaryPrimarySignature = currentPrimarySummarySignature()
        healthTrends = filteredSnapshot.trends
        activityRingHistory = filteredSnapshot.activityRingHistory
        loadedActivityRingMonthKeys = Set(filteredSnapshot.activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))

        if !permissionSelection.includes(.workouts) {
            clearWorkoutSnapshots()
        } else {
            if !permissionSelection.includes(.workoutMetrics) {
                sanitizeWorkoutSnapshots(calendar: .bodyGregorian) { $0.removingWorkoutMetrics(calendar: $1) }
            }
            if !permissionSelection.includes(.heart) {
                // Heart-rate recovery is a summary field read under the Heart
                // permission; strip it the same way so the tile (and its share
                // option) drop immediately instead of after the next refetch.
                sanitizeWorkoutSnapshots(calendar: .bodyGregorian) { $0.removingHeartRateRecovery(calendar: $1) }
            }
        }

        if !permissionSelection.includes(.activityRings) {
            // The filtered save below purges the cached ring history, so the
            // one-shot backfill marker must fall with it — otherwise
            // re-enabling rings resumes recent-months-only fetches and the
            // ten-year history never rebuilds.
            HealthDashboardSnapshotStore.clearActivityRingBackfillCompleted()
        }

        let daySampleSignatures = currentDaySampleSignatures()
        let summaryContextSignature = healthSummaryPrimarySignature
        Self.snapshotPersistQueue.async {
            HealthDashboardSnapshotStore.save(
                filteredSnapshot,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature
            )
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
        // `sanitizeWorkoutSnapshots`. Preserving each file's month
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

    /// Applies a permission-driven strip (`removingWorkoutMetrics` when the user
    /// disables `.workoutMetrics`, `removingHeartRateRecovery` for `.heart`) to every
    /// cached summary, so already-fetched values stop surfacing in workout detail
    /// without a refetch. Mirrors `clearWorkoutSnapshots` (in-memory rebuild + widget
    /// reload); loaded month keys are kept since the months stay loaded — only the
    /// stripped fields drop.
    private func sanitizeWorkoutSnapshots(
        calendar: Calendar = .bodyGregorian,
        _ transform: @escaping @Sendable (WorkoutMonthSnapshot, Calendar) -> WorkoutMonthSnapshot
    ) {
        snapshot = transform(snapshot, calendar)
        monthSnapshots = monthSnapshots.mapValues { transform($0, calendar) }

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
               WorkoutSnapshotStore.save(transform(current, calendar)) {
                widgetReloadNeeded = true
            }
            if let previous = WorkoutSnapshotStore.loadPrevious(),
               WorkoutSnapshotStore.savePrevious(transform(previous, calendar)) {
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

            // Drop detail files for workouts the persisted list no longer carries.
            // The keep-set is read back from the two ON-DISK month files, not from
            // `monthSnapshots`: the previous month isn't seeded into memory at
            // launch, so an in-memory keep-set would delete every previous-month
            // detail on the first refresh. For the same reason, a missing file means
            // "unknown", not "empty" — skip the prune entirely rather than guess.
            if let current = WorkoutSnapshotStore.load(),
               current.workoutCount > 0,
               let previous = WorkoutSnapshotStore.loadPrevious() {
                var keeping: Set<UUID> = []
                for month in [current, previous] {
                    for day in month.days {
                        for workout in day.workouts {
                            keeping.insert(workout.id)
                        }
                    }
                }
                WorkoutDetailSnapshotStore.prune(keeping: keeping)
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
        // A cancelled refresh is not a failure: keep cached data and the current
        // authorization state, and don't surface a health-data notice.
        if error is CancellationError { return }
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

    /// True when the current permission selection yields at least one readable
    /// HealthKit type — the precise "can a refresh dispatch any data query"
    /// signal for the sync badge. A merely nonempty `enabledPermissions` is not
    /// enough: dependent-only permissions (`.dateOfBirth`, `.workoutMetrics`
    /// without their `.heart`/`.workouts` parents) enable no read types.
    private var permissionSelectionCanRunQueries: Bool {
        !Self.readObjectTypes(for: permissionSelection).isEmpty
    }


    private func fetchHealthDataSourceOptions(calendar: Calendar) async {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("SourceOptions")
        defer { BodyPerformanceSignposts.signposter.endInterval("SourceOptions", signpostState) }

        if let nextOptionsByKind = await engine.fetchHealthDataSourceOptions(calendar: calendar) {
            // Per-kind merge: the engine returns only successfully discovered
            // kinds, so a kind whose source query failed keeps its previously
            // published options instead of being cleared.
            healthDataSourceOptionsByKind.merge(nextOptionsByKind) { _, next in next }
            // Refresh the compute seed's expected-source lists from the same
            // discovery (same per-kind keep-prior semantics), and persist them:
            // `lastVitalsRefreshDate` is restored across relaunches, so the
            // seed this coverage guards can be published before discovery has
            // run in the new session.
            cachedExpectedSourceIDsByKind.merge(
                await engine.watchComputeExpectedSourceIDs()
            ) { _, next in next }
            HealthDashboardSnapshotStore.saveWatchExpectedSourceIDs(cachedExpectedSourceIDsByKind)
        }

        // OUTSIDE the `if let`: the engine returns nil once its permission
        // signature is latched, and both of these must still populate on that
        // path — the membership pool for the editor, and the per-kind custom
        // bucket map the synchronous resolved-option accessors read.
        discoveredIndividualHealthSources = await engine.discoveredIndividualHealthSources()
        customSourceIDsWithDataByKind = await engine.customHealthSourceIDsWithData()
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


    /// Forwards to the shared `BodyWorkoutFetch` (Body + BodyWatch) so the watch
    /// maps HealthKit activity types to `BodyWorkoutType` exactly as iOS does.
    /// Signature kept for existing callers + tests.
    nonisolated static func workoutType(for activityType: HKWorkoutActivityType) -> BodyWorkoutType {
        BodyWorkoutFetch.workoutType(for: activityType)
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
