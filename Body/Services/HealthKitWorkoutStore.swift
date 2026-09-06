//
//  HealthKitWorkoutStore.swift
//  Body
//

import Foundation
import HealthKit
import Observation
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

@Observable
@MainActor
final class HealthKitWorkoutStore {
    nonisolated static let recentChartMonthCount = 3

    enum AuthorizationState: Equatable {
        case unknown
        case unavailable
        case authorized
        case denied
        case failed(String)
    }

    private(set) var authorizationState: AuthorizationState = .unknown
    private(set) var snapshot: WorkoutMonthSnapshot
    private(set) var monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot]
    /// Bumped on every `monthSnapshots` write, including subscript writes and
    /// `removeValue`. Views key their derived caches on it instead of
    /// re-deriving from the dictionary. Bumped explicitly by
    /// `setMonthSnapshots` / `mutateMonthSnapshots` rather than by a `didSet`,
    /// which the `@Observable` macro rewrites the property through: every write
    /// has to go through one of those two, or the memo keys freeze while the
    /// dictionary moves on.
    private(set) var monthSnapshotsGeneration = 0

    /// The only whole-dictionary writer of `monthSnapshots`.
    private func setMonthSnapshots(_ snapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot]) {
        monthSnapshots = snapshots
        monthSnapshotsGeneration &+= 1
        dashboardDataRevision &+= 1
    }

    /// The only in-place writer of `monthSnapshots` (subscript, `removeValue`).
    /// Mutates through the stored property rather than copying it out and back,
    /// so a month insert doesn't deep-copy every cached month.
    private func mutateMonthSnapshots(_ mutate: (inout [BodyWorkoutMonthKey: WorkoutMonthSnapshot]) -> Void) {
        mutate(&monthSnapshots)
        monthSnapshotsGeneration &+= 1
        dashboardDataRevision &+= 1
    }
    /// Session-scoped manual effort ratings the user just saved from the workout
    /// detail screen, keyed by workout UUID. The detail card prefers these over
    /// the cached snapshot value so an edit shows immediately; the snapshot's
    /// baked-in effort catches up on the next workout refresh.
    private(set) var workoutEffortOverrides: [UUID: Double] = [:]
    /// Workouts whose saved effort was an accepted suggestion (saved unchanged from
    /// the pre-filled estimate). `WorkoutEffortEstimator` excludes these from its
    /// calibration so it never learns from its own output; a manual re-rate removes
    /// the ID again. Device-local: persisted in `UserDefaults` as an ordered
    /// `[String]` capped at `suggestionAcceptedEffortIDsCap` (oldest dropped first).
    private(set) var suggestionAcceptedEffortWorkoutIDs: Set<UUID> =
        HealthKitWorkoutStore.loadSuggestionAcceptedEffortIDs()
    /// Device-local user renames keyed by HealthKit workout UUID. Persisted in
    /// `UserDefaults` as a `[String: String]` (UUID string → name); nothing is
    /// written back to HealthKit.
    private(set) var workoutCustomNames: [UUID: String]
    private(set) var healthSummary: HealthSummarySnapshot = .empty {
        didSet { dashboardDataRevision &+= 1 }
    }
    @ObservationIgnored private(set) var dashboardDataRevision = 0
    @ObservationIgnored private(set) var trendInputRevisions: [HealthTrendReconciliationLeaf: Int] = [:]
    /// Primary-source + permission signature captured when `healthSummary` was
    /// last published by a full dashboard refresh. A failed summary leaf reuses
    /// the cached value only while this still matches the current selection, so
    /// switching source/permission never resurrects stale other-source data.
    /// In-memory only (nil on cold start → conservative empty-on-failure).
    @ObservationIgnored
    private var healthSummaryPrimarySignature: String?
    @ObservationIgnored private var dashboardCacheScope: HealthDashboardCacheScope?
    @ObservationIgnored private var completedDashboardFreshness: HealthDashboardSnapshotStore.Freshness?
    private(set) var activityRingBackfillState: HealthDashboardSnapshotStore.ActivityRingBackfillState = .pending(resumeFrom: nil)
    @ObservationIgnored private var activityRingBackfillResumeDay: ActivityRingDaySummary.CalendarDay?
    @ObservationIgnored private var ringHistoricalRepair: HistoricalMonthRepairProgress?
    @ObservationIgnored private var activityRingHistoryRevision = 0
    @ObservationIgnored private var dashboardPublicationToken = HealthDashboardPublicationToken()
    @ObservationIgnored private var cacheSourceIdentities: [HealthMetricKind: [String: [String]]] = [:]
    @ObservationIgnored private var contextRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var contextRefreshGeneration = 0
    @ObservationIgnored private var needsContextRefresh = false
    @ObservationIgnored private var contextRefreshRequiresFetch = false
    @ObservationIgnored private var contextRefreshIsUserInitiated = false
    @ObservationIgnored private var pendingPermissionChangeCount = 0
    /// Controlled suspension/dispatch seams for real store integration tests.
    @ObservationIgnored var contextRefreshOverride: (@MainActor (BodyWorkoutRefreshIntent) async -> Void)?
    @ObservationIgnored var beforeDashboardComputeCommit: (@MainActor () async -> Void)?
    @ObservationIgnored var beforePermissionDiskStrip: (@MainActor () async -> Void)?
    @ObservationIgnored var beforePermissionSnapshotCommit: (@MainActor () async -> Void)?
    private(set) var healthTrends: HealthTrendSnapshot = .empty {
        didSet {
            dashboardDataRevision &+= 1
            for leaf in HealthTrendReconciliationLeaf.allCases where !leaf.hasSameValue(in: oldValue, and: healthTrends) {
                trendInputRevisions[leaf, default: 0] &+= 1
            }
        }
    }
    @ObservationIgnored private var authoritativeDaySampleSeries: Set<HealthDaySampleSeries> = []
    @ObservationIgnored private(set) var daySampleRevisions: [HealthDaySampleSeries: Int] = [:]
    private(set) var activityRingHistory: ActivityRingHistorySnapshot = .empty {
        didSet {
            pendingActivityRingRepairMonthKeys = activityRingHistory.pendingDayIdentityMonthKeys
            activityRingHistoryRevision &+= 1
            dashboardDataRevision &+= 1
        }
    }
    /// Derived in memory on every history replacement, never during a scroll read.
    private(set) var pendingActivityRingRepairMonthKeys: [ActivityRingMonthKey] = []
    private(set) var permissionSelection: BodyHealthPermissionSelection
    private(set) var healthDataSourceSelection: BodyHealthDataSourceSelection
    private(set) var secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection
    private(set) var combinesHealthDataSourcesByName: Bool
    /// User-created merged sources (Body Pro). Kept verbatim when the
    /// entitlement lapses — every read path neutralizes a `custom:` selection
    /// to All Sources instead, so re-subscribing restores the user's setup.
    private(set) var customHealthSourceGroups: [BodyCustomHealthSourceGroup]
    /// Every individual source discovered for ANY kind — the membership pool
    /// the custom-source editor picks from. Refreshed by
    /// `fetchHealthDataSourceOptions`, empty until discovery first runs.
    private(set) var discoveredIndividualHealthSources: [BodyDiscoveredHealthSource] = []
    private(set) var healthDataSourceOptionsByKind: [HealthMetricKind: [BodyHealthDataSourceOption]] = [:]
    /// Per kind, the custom group ids that registered a non-empty source bucket
    /// in the engine — mirrored here because the store's resolved-option
    /// accessors are synchronous while the engine is an actor. A kind is ABSENT
    /// (not empty) until its discovery succeeds, which the resolution below
    /// reads as "keep the selection" exactly like the engine does (H4).
    private var customSourceIDsWithDataByKind: [HealthMetricKind: Set<String>] = [:]
    private(set) var healthDataNotice: String?
    private(set) var isRefreshing = false
    /// Phase of the in-flight refresh, for the sync badge. `nil` while idle.
    enum RefreshStage: Hashable {
        case authorizing    // HealthKit authorization sheet may be up
        case fetching       // HealthKit queries (dashboard + workouts + auto-apply month loads)
        case computing      // readiness / stress recompute, training-load seed
        case writingEffort  // auto-apply is saving workout effort to HealthKit
        case finishing      // post-publish tail (watch/widget/persist, all synchronous)
    }
    private(set) var refreshStage: RefreshStage?

    /// Guarded by the refresh generation: an abandoned deadline body that lands
    /// late must not repaint the badge. (Outside `runRefreshWithDeadline` the
    /// guard is trivially true; that is fine, the slot was just claimed.)
    private func setRefreshStage(_ stage: RefreshStage) {
        guard isRefreshing, mayApplyRefreshResults else { return }
        refreshStage = stage
    }
    private(set) var lastSuccessfulRefreshDate: Date?
    /// Whether a full refresh has ever completed on this install, even a partial
    /// one. Separate from `lastSuccessfulRefreshDate` (which arms the freshness
    /// TTL and so requires a clean fetch): a user who denied some Health read
    /// permissions can hit a query failure on every refresh, and gating the
    /// first-launch overlay on the TTL stamp alone left them on "Try Again"
    /// forever.
    private(set) var hasCompletedInitialHealthDataLoad = false
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
    private(set) var syncBadgeSuccessCount = 0
    /// Date of the last refresh that re-fetched the dashboard vitals (not just
    /// workouts or ring history). Carried in the watch snapshot so the watch's
    /// staleness logic isn't reset by workout-only refreshes. Doubles as the
    /// phone→watch compute seed's `dataThrough` watermark (Phase 3 of the
    /// on-watch realtime compute plan) — it already advances ONLY when a full
    /// dashboard refresh lands cleanly, which is exactly the data-coverage
    /// guarantee `dataThrough` needs.
    @ObservationIgnored
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
    @ObservationIgnored
    private var lastReadinessComputeDate: Date?
    /// When the Training Load summary/series were last RE-DERIVED from a fresh
    /// workout fetch. Deliberately SEPARATE from `lastReadinessComputeDate`:
    /// the workout-only reapply path re-drains readiness but does NOT recompute
    /// Training Load (that only happens in the dashboard fetch, gated on the
    /// fetch selection's `.trainingLoad` bit) — advancing a joint watermark
    /// there would label a stale Training Load as freshly computed and let it
    /// overwrite a newer watch-computed value in the per-metric merge.
    @ObservationIgnored
    private var lastTrainingLoadComputeDate: Date?
    /// When the CURRENT month's workout snapshot was last rebuilt from a fresh
    /// fetch — the honest watermark for the weekly workout-minutes bars, which
    /// `publishWatchSnapshot` derives from `monthSnapshots`. Deliberately
    /// separate from `lastVitalsRefreshDate`: a workout-only refresh (effort
    /// edit, auto-apply, warm resume) rebuilds the week while the vitals
    /// watermark stands still, and stamping the bars with the old vitals date
    /// would let a watch-computed week beat the phone's genuinely newer one in
    /// `WatchComputeMerge.merging`'s per-metric compare. Advances only when a
    /// fetch covered EVERY month the trailing 7-day window touches: lazy pages
    /// of old months can't change the week, and early in a month a
    /// current-month-only fetch leaves the window's older days on a possibly
    /// stale persisted snapshot, so that combined week must not claim to be
    /// fresh. Persisted under its own key and restored from it at launch (never
    /// derived from `lastSuccessfulRefreshDate`, which an early-month passive
    /// refresh advances without covering the week), and NEVER unioned with the
    /// live vitals date when stamping.
    @ObservationIgnored
    private var lastWorkoutsRefreshDate: Date?
    /// Per-kind watermark for the OTHER watch metrics a single-metric detail
    /// pull can refresh (HR, HRV, resting HR, sleep, skin temp), keyed by
    /// `WatchMetricKindKey` string (== `HealthMetricKind.rawValue`, pinned by
    /// `ProjectConfigurationTests`). Without it a clean detail pull publishes
    /// the freshly fetched value under the OLD full-refresh stamp
    /// (`lastVitalsRefreshDate` deliberately doesn't advance on a
    /// `refreshedVitals: false` refresh), and a watch that computed that kind
    /// locally in between keeps its older value in the freshest-wins merge.
    @ObservationIgnored
    private var lastMetricPullDates: [String: Date] = [:]
    /// The phone's discovered source universe per compute kind (see
    /// `HealthKitFetchEngine.watchComputeExpectedSourceIDs`), cached at each
    /// source-options fetch and carried in the compute seed so the watch can
    /// validate an All-Sources read against it.
    @ObservationIgnored
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
    @ObservationIgnored
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
    private(set) var loadingMonthKeys: Set<BodyWorkoutMonthKey> = []
    @ObservationIgnored private var monthFetchRevisions: [BodyWorkoutMonthKey: Int] = [:]
    private(set) var loadingActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    private(set) var hasMoreActivityRingHistory = true
    var canLoadEarlierActivityRings: Bool {
        hasMoreActivityRingHistory || !pendingActivityRingRepairMonthKeys.isEmpty
    }

    /// Disk size of the three snapshot caches, refreshed off the main thread
    /// (`refreshCacheDiskSize`). `cacheStatus` reads this instead of running
    /// per-render `FileManager` stat calls on the main thread.
    private(set) var cacheDiskSizeBytes: Int64 = 0

    /// All-time personal-record contributions, hydrated from disk at init and
    /// folded forward as months load. Reads go through `personalRecords(for:)`,
    /// which stays empty until the baseline scan has covered the whole history.
    /// The lifecycle lives in `HealthKitWorkoutStore+Records.swift`; stored state
    /// has to sit here because a Swift extension can't declare it.
    private(set) var recordLedger = WorkoutRecordLedger()
    @ObservationIgnored private(set) var recordLedgerRevision = 0
    /// The baseline or rolling record repair. Retained so a Clear Cache can cancel it and
    /// await its exit before wiping the ledger it would otherwise re-persist.
    @ObservationIgnored
    var recordBackfillTask: Task<Void, Never>?

    /// The one-time Stress history walk. Same rationale as `recordBackfillTask`
    /// — its lifecycle lives in `HealthKitWorkoutStore+StressBackfill.swift`,
    /// but an extension can't declare stored state.
    @ObservationIgnored
    var stressBackfillTask: Task<Void, Never>?

    /// The in-flight post-refresh Stress input load, for the backfill's
    /// serialization: the two must not fetch and merge Stress state at once.
    var pendingStressInputLoadTask: Task<Void, Never>? { stressInputLoadTask }

    /// The live Stress record context, for the backfill's per-chunk guard —
    /// `stressRecordContextSignature()` itself stays private to this file.
    var currentStressRecordContextSignature: String { stressRecordContextSignature() }

    /// `recordLedger` is `private(set)` so nothing outside this type writes it;
    /// the records extension lives in another file, so it publishes through here.
    func publishRecordLedger(_ ledger: WorkoutRecordLedger) {
        guard ledger.schemaVersion != recordLedger.schemaVersion
            || ledger.contributions != recordLedger.contributions
            || ledger.scannedThrough != recordLedger.scannedThrough
            || ledger.baselineComplete != recordLedger.baselineComplete
            || ledger.historicalRepair != recordLedger.historicalRepair else { return }
        recordLedger = ledger
        recordLedgerRevision &+= 1
    }

    /// The current cache generation, for the records extension's epoch guard —
    /// `cacheEpoch` itself stays private to this file.
    var currentCacheEpoch: Int { cacheEpoch }

    /// Whether a Clear Cache is running, for the records extension's start guard.
    var isClearingLocalCache: Bool { isClearingCache }

    /// Months beyond this cap are evicted (least recently loaded first) so
    /// browsing years of history doesn't accumulate every month's workouts
    /// (with up to 96 heart-rate samples each) in memory for the app's
    /// lifetime. The current chart window and the displayed month never
    /// evict.
    nonisolated static let maximumCachedMonthSnapshots = 12

    /// Workouts beyond this cap have their per-workout detail caches (route,
    /// splits, series, recovery, energy equivalent) evicted least recently
    /// opened first, so a long browsing session doesn't pin every opened
    /// workout's dense payloads in memory. An evicted workout re-seeds from its
    /// persisted detail file on the next open rather than re-reading HealthKit.
    nonisolated static let maximumCachedWorkoutDetails = 24

    // Internal (not `private`) so `HealthKitWorkoutStore+Records.swift` can run
    // the baseline scan's queries through the same engine.
    @ObservationIgnored
    let engine: HealthKitFetchEngine
    @ObservationIgnored private let workoutJournalFile: URL?
    @ObservationIgnored private var workoutJournal: WorkoutJournalReconciler?
    @ObservationIgnored private var workoutJournalTask: Task<Void, Never>?
    @ObservationIgnored private var workoutJournalAdmission = HealthDashboardPublicationToken()
    /// Backing store for `workoutCustomNames` — injectable so tests can use an
    /// isolated suite.
    @ObservationIgnored
    private let customNameDefaults: UserDefaults
    /// The per-workout detail session caches (route, presence probe, splits,
    /// metric series, heart-rate recovery, heart-rate series, energy equivalent),
    /// their disk-hydration tasks and their LRU order. Owned here and read only
    /// by the loaders below; see `BodyWorkoutDetailCacheStore` for why it is not
    /// observed state.
    @ObservationIgnored
    private let detailCaches = BodyWorkoutDetailCacheStore()
    /// Set when Body enters the background. While it is set, detail opens skip
    /// the disk seed so the loaders read HealthKit live, because the persisted
    /// files hold positives captured under the previous grant and HealthKit read
    /// access can only change while Body isn't in the foreground (the Health app
    /// or Settings toggle), with no signal on return. Never cleared during the
    /// process: nothing short of a live per-workout read validates a persisted
    /// payload, and an authorized pass only means HealthKit has a decision on
    /// record, not that the route or series is still readable. So seeding stays
    /// off until the next launch, and each opened workout costs one live read
    /// whose result the in-memory caches hold for the rest of the session. The
    /// live loaders refresh the files as they go: a positive is re-persisted,
    /// and a confirmed absence deletes the workout's file.
    @ObservationIgnored
    private var bypassesPersistedDetailSeeding = false
    /// Tracked, not ignored: `comparisonContext(for:)` reads it from a detail
    /// sheet's body to decide whether a month is complete.
    private var loadedMonthKeys: Set<BodyWorkoutMonthKey> = []
    @ObservationIgnored
    private var monthLoadOrder: [BodyWorkoutMonthKey] = []
    private var loadedActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    /// Months probed for older ring history that came back with no data.
    /// Session-only: never refetched this session, never persisted; cleared
    /// whenever a refresh applies fresh dashboard ring history.
    @ObservationIgnored
    private(set) var exhaustedActivityRingMonthKeys: Set<ActivityRingMonthKey> = []
    @ObservationIgnored
    private var lastAppEntrySyncDate: Date?
    @ObservationIgnored
    private let refreshCompletionWaiters = RefreshCompletionWaiters()
    @ObservationIgnored
    private var monthLoadContinuations: [BodyWorkoutMonthKey: [CheckedContinuation<Void, Never>]] = [:]
    @ObservationIgnored
    private var persistedDaySamplesHydration: Task<HealthTrendDaySampleSnapshot?, Never>?
    /// The in-flight post-refresh Stress input load, so overlapping refreshes
    /// don't stack heartbeat-series scans.
    @ObservationIgnored
    private var stressInputLoadTask: Task<Void, Never>?
    /// The in-flight Radar-gated hourly step load, so overlapping refreshes
    /// don't stack step-bucket refetches.
    @ObservationIgnored
    private var bodyRadarStepLoadTask: Task<Void, Never>?
    /// The in-flight phase-2 full-window trend load, so overlapping refreshes
    /// don't stack year-long trend refetches.
    @ObservationIgnored
    private var fullTrendWindowLoadTask: Task<Void, Never>?
    /// The pending refetch a warning-threshold edit queued, so dragging the
    /// picker wheel across a dozen values leaves one refresh rather than twelve.
    @ObservationIgnored
    private var metricWarningThresholdRefreshTask: Task<Void, Never>?
    /// Builds and ships the widget and watch snapshots off the main actor, and
    /// owns the debounced republish task (see `republishCompanionSnapshots`).
    @ObservationIgnored
    private let companionPublisher = BodyCompanionPublisher()
    /// Retains the Body Pro entitlement observer so secondary-source gating (which this
    /// store resolves from `BodyProEntitlement`, not the SwiftUI environment) recomputes
    /// when the entitlement flips.
    @ObservationIgnored
    private var proEntitlementObserver: NSObjectProtocol?

    /// Bumped by the entitlement observer. `BodyProEntitlement.isUnlocked` is a
    /// static read that observation cannot see, so the three gating chokepoints
    /// (`selectedSecondaryHealthDataSourceOption`,
    /// `resolvedDefaultCustomHealthSourceOption`, `resolvedCustomHealthSourceOption`)
    /// and `isProUnlocked` read this counter first. That registers the dependency
    /// for every caller in a view `body`, so a flip re-renders exactly the views
    /// that resolve a source and nothing else.
    private(set) var proEntitlementGeneration = 0

    /// The entitlement, read so that a SwiftUI `body` re-runs when it flips.
    var isProUnlocked: Bool {
        _ = proEntitlementGeneration
        return BodyProEntitlement.isUnlocked
    }

    /// Tasks parked on "the in-flight refresh finished", keyed by a per-call ID
    /// rather than pushed onto a bare array: `finishRefresh` used to be the only
    /// thing that ever resumed them, so a waiter whose task was cancelled while
    /// parked leaked its continuation forever (nothing else drained the list).
    /// The ID lets the cancellation handler take back exactly its own waiter —
    /// and take it back exactly once, since resuming a continuation twice traps.
    ///
    /// Internal so the cancellation path is testable: `park()` only ever runs
    /// under a live refresh, which a test can't stage without HealthKit.
    @MainActor
    final class RefreshCompletionWaiters {
        private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]

        var isEmpty: Bool {
            continuations.isEmpty
        }

        func resumeAll() {
            let toResume = continuations
            continuations.removeAll()
            for continuation in toResume.values {
                continuation.resume()
            }
        }

        func park() async {
            let waiterID = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    continuations[waiterID] = continuation
                }
            } onCancel: {
                // `onCancel` runs on the cancelling thread, so it has to hop
                // back here to touch the map. That hop can only run once this
                // actor is free — i.e. after the registration above completed —
                // so a cancellation racing the park can't miss the waiter it
                // needs to take back. A nil `removeValue` means `resumeAll`
                // already drained it, and the resume must not happen twice.
                Task { @MainActor [weak self] in
                    guard let continuation = self?.continuations.removeValue(forKey: waiterID) else {
                        return
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func finishRefresh() {
        isRefreshing = false
        refreshStage = nil
        // Measurement only (RefreshOptimizationPlan-02 §6): logs the per-leaf
        // table, the refresh wall time, the HealthKit concurrency high-water
        // mark, and the effort candidate count. DEBUG-only inside, and it
        // clears the table so the next refresh starts from zero.
        BodyRefreshProfile.shared.dumpAndReset()
        refreshCompletionWaiters.resumeAll()
        scheduleWorkoutJournalIfNeeded()
        // Off the refresh path by construction: the refresh is already finished
        // and this only starts a detached, cancellable scan (see
        // `HealthKitWorkoutStore+Records.swift`).
        scheduleRecordBaselineBackfillIfNeeded()
        // Same slot, same rule — and it chains itself behind the record scan and
        // the Stress input load rather than racing them (see
        // `HealthKitWorkoutStore+StressBackfill.swift`).
        scheduleStressBackfillIfNeeded()
    }

    /// Internal so the Stress backfill extension can park on the same refresh
    /// barrier the intraday loads use before publishing a chunk.
    func awaitNextRefreshCompletion() async {
        guard isRefreshing, !Task.isCancelled else {
            return
        }
        await refreshCompletionWaiters.park()
    }

    /// Waits until no refresh holds the slot. Returns false if cancelled while waiting.
    /// Loops because `finishRefresh()` resumes every parked waiter and only the first
    /// to run can claim `isRefreshing`; a single park lets the others fall into the
    /// `guard !isRefreshing` in the refresh entry points and lose their refetch.
    ///
    /// Internal so the Stress backfill extension parks on the same barrier.
    func awaitRefreshSlotFree() async -> Bool {
        while isRefreshing {
            await awaitNextRefreshCompletion()
            if Task.isCancelled { return false }
        }
        return true
    }

    /// Test seam: holds the refresh slot for the duration of `body` exactly as the
    /// refresh entry points do, so waiter orchestration can be exercised without
    /// HealthKit.
    func withRefreshSlotHeld(_ body: @MainActor () async -> Void) async {
        isRefreshing = true
        defer { finishRefresh() }
        await body()
    }

    /// Hard ceiling on one user-facing refresh. Nothing in the app used to time
    /// out: a single HealthKit query that never returned kept `isRefreshing` —
    /// and the first-launch "Loading Health Data…" overlay — up until the user
    /// killed the app, and every relaunch repeated it. Generous on purpose: a
    /// legitimately large first load must be allowed to finish.
    nonisolated static let healthRefreshDeadline: Duration = .seconds(120)

    /// Generation of the newest user-facing refresh. Bumped when one is
    /// ABANDONED at `healthRefreshDeadline` — cancellation is cooperative, so
    /// the body keeps running and would otherwise publish, persist, stamp
    /// success, or clear a newer refresh's spinner long after the user was told
    /// the load timed out.
    @ObservationIgnored
    private var refreshGeneration = 0

    /// The generation the running refresh body was started under, carried down
    /// the task tree so every publish/persist/stamp point can check it without
    /// threading a parameter through the whole refresh call graph. `nil`
    /// outside a deadline-guarded refresh (lazy month/ring loads, single-metric
    /// pulls), which always may apply.
    @TaskLocal private static var runningRefreshGeneration: Int?

    /// A settings revision is independent of deadline abandonment and cache
    /// deletion. In particular, A → B → A must retire work started under A.
    @ObservationIgnored private var refreshInputRevision = 0
    @ObservationIgnored private var lastObservedRefreshInputs: RefreshInputs?
    @ObservationIgnored private let calendarContext: () -> (calendar: Calendar, date: Date)
    @TaskLocal private static var runningRefreshInputs: CapturedRefreshInputs?

    struct RefreshInputs: Equatable {
        let primary: String
        let secondary: String
        let permissions: String
        let combinesSources: Bool
        let groups: String
        let proUnlocked: Bool
        let subMinuteAwake: Bool
        let boundaryAwake: Bool
        let calendarIdentifier: String
        let timeZoneIdentifier: String
        let summaryDayStart: Date
        var idealSleepDuration: TimeInterval
        let fetchSelection: BodyDashboardFetchSelection
    }

    struct CapturedRefreshInputs: Equatable {
        let revision: Int
        let inputs: RefreshInputs
    }

    /// Canonical source IDs, not display names or JSON dictionary ordering.
    /// Also reads preferences changed outside this store, so a late result is
    /// rejected even before the corresponding settings callback gets its turn.
    func captureRefreshInputs(intent: BodyWorkoutRefreshIntent = .passiveResume) -> CapturedRefreshInputs {
        let (calendar, now) = calendarContext()
        let inputs = RefreshInputs(
            primary: healthDataSourceSelection.signature,
            secondary: secondaryHealthDataSourceSelection.signature,
            permissions: permissionSelection.rawValue,
            combinesSources: combinesHealthDataSourcesByName,
            groups: customSourceGroupsSignatureSuffix,
            proUnlocked: isProUnlocked,
            subMinuteAwake: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            boundaryAwake: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages(),
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier,
            summaryDayStart: calendar.startOfDay(for: now),
            idealSleepDuration: Self.storedIdealSleepDuration(),
            fetchSelection: BodyDashboardFetchSelection.load()
        )
        // Preserve the explicit settings action across coalesced edits. Passive
        // context detection must not downgrade a user-requested repair.
        if intent == .userInitiated, lastObservedRefreshInputs != inputs || needsContextRefresh {
            contextRefreshIsUserInitiated = true
        }
        if let previous = lastObservedRefreshInputs, previous != inputs {
            var previousFetchInputs = previous
            previousFetchInputs.idealSleepDuration = inputs.idealSleepDuration
            contextRefreshRequiresFetch = contextRefreshRequiresFetch || previousFetchInputs != inputs
            refreshInputRevision &+= 1
            dashboardPublicationToken.invalidate()
            dashboardPublicationToken = HealthDashboardPublicationToken()
            reconcileDashboardCacheScope()
            needsContextRefresh = true
            if contextRefreshRequiresFetch {
                lastSuccessfulRefreshDate = nil
                completedDashboardFreshness = nil
                HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
            }
            scheduleContextRefreshIfNeeded()
        }
        lastObservedRefreshInputs = inputs
        return CapturedRefreshInputs(revision: refreshInputRevision, inputs: inputs)
    }

    private func scheduleContextRefreshIfNeeded() {
        guard needsContextRefresh, contextRefreshTask == nil, pendingPermissionChangeCount == 0,
              !Task.isCancelled, !isClearingCache else { return }
        contextRefreshGeneration &+= 1
        let generation = contextRefreshGeneration
        contextRefreshTask = Task { @MainActor [weak self] in
            // One owner for a burst of settings edits, including edits arriving
            // while the old refresh is still releasing its slot.
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            defer {
                if self.contextRefreshGeneration == generation { self.contextRefreshTask = nil }
            }
            while self.needsContextRefresh, !Task.isCancelled {
                guard await self.awaitRefreshSlotFree() else { return }
                // A permission transaction can begin while this owner is
                // debouncing or waiting for an older refresh to finish.
                guard self.pendingPermissionChangeCount == 0 else { return }
                self.needsContextRefresh = false
                let intent: BodyWorkoutRefreshIntent = self.contextRefreshIsUserInitiated ? .userInitiated : .passiveResume
                self.contextRefreshIsUserInitiated = false
                let requiresFetch = self.contextRefreshRequiresFetch
                self.contextRefreshRequiresFetch = false
                if let operation = self.contextRefreshOverride {
                    await operation(intent)
                } else if !requiresFetch {
                    self.isRefreshing = true
                    await self.runRefreshWithDeadline {
                        if await self.updateHealthDashboardSnapshot(
                            summary: self.healthSummary, trends: self.healthTrends,
                            activityRingHistory: self.activityRingHistory,
                            recomputesStress: false, recomputesBodyRadar: false
                        ) {
                            self.publishWatchSnapshot()
                        }
                    }
                    self.finishRefresh()
                } else {
                    await self.requestAuthorizationAndRefresh(intent: intent)
                }
            }
        }
    }

    func mayApplyRefreshInputs(_ captured: CapturedRefreshInputs) -> Bool {
        captured == captureRefreshInputs()
    }

    /// Resource cleanup survives a settings change, but not deadline abandonment:
    /// the deadline owner releases the old anchor before a new refresh can start.
    private var ownsRefreshGeneration: Bool {
        Self.runningRefreshGeneration.map { $0 == refreshGeneration } ?? true
    }

    /// Whether the code running right now still speaks for the current refresh.
    private var mayApplyRefreshResults: Bool {
        let ownsInputs = Self.runningRefreshInputs.map { mayApplyRefreshInputs($0) } ?? true
        return ownsRefreshGeneration && ownsInputs
    }

    /// Runs one user-facing refresh `body` under `deadline` and ABANDONS it if
    /// it overruns, returning whether it finished in time.
    ///
    /// Deliberately an unstructured task rather than a `withThrowingTaskGroup`
    /// race: cancellation is cooperative, so a group would still sit waiting for
    /// a loser stuck inside a HealthKit query that never resumes — exactly the
    /// hang this guards against. The caller starts the clock only after the
    /// authorization sheet has returned, so user decision time is never counted.
    @discardableResult
    func runRefreshWithDeadline(
        _ deadline: Duration = HealthKitWorkoutStore.healthRefreshDeadline,
        body: @escaping @MainActor () async -> Void
    ) async -> Bool {
        let generation = refreshGeneration
        let inputs = captureRefreshInputs()
        let bodyTask = Task { @MainActor in
            await Self.$runningRefreshGeneration.withValue(generation) {
                await Self.$runningRefreshInputs.withValue(inputs) {
                    await body()
                }
            }
        }

        var timeoutTask: Task<Void, Never>?
        let completed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let waiter = RefreshDeadlineWaiter(continuation)
            Task { @MainActor in
                await bodyTask.value
                waiter.finish(completed: true)
            }
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: deadline, clock: ContinuousClock())
                waiter.finish(completed: false)
            }
        }
        timeoutTask?.cancel()

        guard !completed else {
            return true
        }

        // The abandoned body's stage must not linger on the badge while the
        // recovery below publishes and persists. Set directly, not through
        // `setRefreshStage`, because this is the recovery's own stage.
        refreshStage = .finishing
        // Retire the abandoned body's generation before it can run another
        // line, then ask it to stop (leaves that DO check cancellation exit
        // early; the stuck one is why the generation guard exists at all).
        refreshGeneration &+= 1
        bodyTask.cancel()
        healthDataNotice = String(localized: "Loading Apple Health data is taking longer than expected. Please try again.")
        // The abandoned body owns the engine's trend anchor (and the memoized
        // training-load fetch keyed off it) and its own reset is gated out now,
        // so release them here.
        await engine.setHealthTrendAnchorDate(nil)
        // Make whatever landed before the deadline durable, and only then let
        // the caller's `finishRefresh()` drop the spinner — a relaunch after a
        // timeout must not be back to zero.
        await persistPublishedDashboardSnapshot()
        // A workout month that already landed in `monthSnapshots` before the
        // deadline fired lives only in memory otherwise: the normal
        // `persistRecentMonthSnapshots` call further down the abandoned body
        // never runs once its generation is retired above. Persist it through
        // the same save path a completed refresh uses (every in-window month,
        // widget reload, detail-file prune) — no new HealthKit fetch,
        // just durability for what's already in memory.
        persistRecentMonthSnapshots(date: Date(), calendar: .bodyGregorian)
        publishWatchSnapshot()
        return false
    }

    /// One-shot resume for the deadline race: whichever of the refresh body and
    /// the deadline sleep finishes first resumes the waiter, and the other's
    /// call is a no-op (resuming a continuation twice traps). MainActor-isolated
    /// so the two racers can never both see an unresumed continuation.
    @MainActor
    private final class RefreshDeadlineWaiter {
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func finish(completed: Bool) {
            guard let continuation else {
                return
            }
            self.continuation = nil
            continuation.resume(returning: completed)
        }
    }

    /// Persists what the refresh had already published when the deadline fired.
    /// Goes through the same signature-aware save path as a normal refresh so
    /// the day-sample sidecar and the summary-context signature stay in step
    /// with the main file.
    private func persistPublishedDashboardSnapshot() async {
        let epoch = cacheEpoch
        // Hydrate compatible, unreconciled samples before capturing the save.
        // Successfully repaired empties are excluded from the memoized seed;
        // persistence independently preserves unqueried empty series.
        await hydratePersistedDaySamplesIfNeeded()
        // A Clear Cache landed while the sidecar loaded: don't write the state
        // it just wiped back to disk.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return
        }
        reconcileDashboardCacheScope()
        let inputs = captureRefreshInputs()
        let token = dashboardPublicationToken
        let snapshotToSave = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        // Read every signature in the same synchronous span as the snapshot
        // above. Taken after the `await` below they could describe a selection
        // the abandoned refresh never published, stamping the payload with a
        // signature that doesn't match it.
        let daySampleSignatures = currentDaySampleSignatures()
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let hydratedDaySamples = await persistedDaySamplesHydration?.value
        // Nothing landed at all, or the trends are still the empty placeholder
        // while a real sidecar sits on disk — either way the write can only
        // lose data.
        guard mayApplyRefreshInputs(inputs), token.isValid, !snapshotToSave.isEmpty,
              !healthTrends.isEmpty || (hydratedDaySamples?.isEmpty ?? true) else {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.snapshotPersistQueue.async {
                defer { continuation.resume() }
                guard token.isValid else { return }
                HealthDashboardSnapshotStore.saveWithOutcome(
                    snapshotToSave,
                    daySampleSignatures: daySampleSignatures,
                    summaryContextSignature: summaryContextSignature,
                    metadata: persistenceMetadata,
                    authoritativeDaySampleSeries: daySampleWriteIntent
                )
            }
        }
        await refreshCacheDiskSize()
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
        initialMonthSnapshots: [WorkoutMonthSnapshot] = WorkoutSnapshotStore.loadPersistedMonths(),
        initialHealthDashboardSnapshot: HealthDashboardSnapshot? = nil,
        initialSummaryContextSignature: String? = nil,
        initialPersistenceMetadata: HealthDashboardSnapshotStore.PersistenceMetadata = .init(),
        initialPermissionSelection: BodyHealthPermissionSelection = BodyHealthPermissionSelection.load(),
        initialHealthDataSourceSelection: BodyHealthDataSourceSelection = BodyHealthDataSourceSelection.load(),
        initialSecondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection = BodyHealthSecondaryDataSourceSelection.load(),
        initialCombinesHealthDataSourcesByName: Bool = UserDefaults.standard.bool(forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey),
        initialCustomHealthSourceGroups: [BodyCustomHealthSourceGroup] = HealthKitWorkoutStore.loadCustomHealthSourceGroups(),
        customNameDefaults: UserDefaults = .standard,
        engineHealthStore: (any BodyHealthQuerying)? = nil,
        workoutJournalFile: URL? = WorkoutChangeJournalStore.lifecycleEnabled ? WorkoutChangeJournalStore.defaultFile : nil,
        timeZoneLedger: BodyTimeZoneLedger? = nil,
        date: Date = Date(),
        calendarContext: @escaping () -> (calendar: Calendar, date: Date) = { (.bodyGregorian, Date()) }
    ) {
        self.calendarContext = calendarContext
        self.workoutJournalFile = workoutJournalFile
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
            customHealthSourceGroups: initialCustomHealthSourceGroups,
            healthStore: engineHealthStore ?? HKHealthStore(),
            timeZoneLedger: timeZoneLedger ?? BodyTimeZoneLedger()
        )
        // One decode, not two: the persisted envelope carries the snapshot and
        // the summary-context signature written beside it, but Swift evaluates
        // default arguments independently — a loader per default read and
        // decoded the largest cache twice on the main thread before the first
        // frame. Callers that inject a snapshot (tests, previews) pass the
        // signature alongside it.
        let loadedDashboard = initialHealthDashboardSnapshot.map {
            HealthDashboardSnapshotStore.LoadedSnapshot(
                snapshot: $0,
                summaryContextSignature: initialSummaryContextSignature,
                metadata: initialPersistenceMetadata
            )
        } ?? HealthDashboardSnapshotStore.loadOrEmptyWithContext()
        // Skip the readiness recompute at init: it's a per-day iteration over up
        // to ~365 trend points that would block the first frame. The cached
        // `summary.readiness` value was correct when written; the next refresh
        // recomputes it off the main thread.
        //
        // Exception: when frozen morning records exist but were captured under a
        // different readiness input context (source, permission, or grouping
        // changed while the app was closed, or the prior refresh failed before
        // re-saving), the persisted chart overlay is stale. The cache is still
        // published without a recompute here; dropping those records and
        // rebuilding the series under the current inputs is deferred to
        // `rebuildStaleReadinessOverlay` at the end of init, which runs off the
        // main actor and saves its result — so the fix stays durable without
        // depending on the next refresh succeeding, and without the first frame
        // paying for it.
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
        let initialTrends = loadedDashboard.snapshot.trends
        let hasStaleReadinessOverlay = !initialTrends.recordedReadiness.isEmpty
            && initialTrends.recordedReadinessContext != initialReadinessContext
        let filteredHealthDashboardSnapshot = loadedDashboard.snapshot
            .filteredWithoutReadinessRecompute(by: initialPermissionSelection)
        // Every persisted month is restored, so the permission sanitizing runs
        // per month rather than on one snapshot.
        let sanitizedMonthSnapshots: [WorkoutMonthSnapshot] = initialMonthSnapshots.map { persisted in
            guard initialPermissionSelection.includes(.workouts) else {
                return WorkoutMonthSnapshot.make(
                    month: persisted.month,
                    year: persisted.year,
                    workouts: [],
                    calendar: .bodyGregorian
                )
            }
            // The persisted snapshot can still carry permission-gated fields
            // (VO₂max/power/cadence/strokes under Workout Metrics, heart-rate
            // recovery under Heart), so strip them here too — otherwise they
            // reappear on launch before the next refresh rebuilds the summary.
            var sanitized = persisted
            if !initialPermissionSelection.includes(.workoutMetrics) {
                sanitized = sanitized.removingWorkoutMetrics()
            }
            if !initialPermissionSelection.includes(.heart) {
                sanitized = sanitized.removingHeartRateRecovery()
            }
            return sanitized
        }
        let startingMonthKey = BodyWorkoutMonthKey(date: date, calendar: .bodyGregorian)
        // An honest empty month when nothing was persisted for the current
        // month (fresh install, or a launch in a month no refresh has covered
        // yet), never a fabricated placeholder.
        let startingSnapshot = sanitizedMonthSnapshots.first {
            $0.month == startingMonthKey.month && $0.year == startingMonthKey.year
        } ?? .makeEmpty(generatedAt: date)
        // Same rationale one level down, for the per-workout detail files: a strip
        // enqueued on opt-out may never have run (app killed right after the
        // toggle), so reconcile what's at rest with the stored selection at launch.
        // Nothing to enqueue when every relevant permission is on — a launch
        // shouldn't pay a queue hop for a no-op.
        if !initialPermissionSelection.includes(.workouts)
            || !initialPermissionSelection.includes(.workoutMetrics)
            || !initialPermissionSelection.includes(.heart) {
            Self.snapshotPersistQueue.async {
                if !initialPermissionSelection.includes(.workouts) {
                    WorkoutDetailSnapshotStore.deleteAll()
                    // The record and effort ledgers are derived workout data, so
                    // they follow the detail files out on a Workouts opt-out.
                    // (Safe to delete the effort ledger from this queue at launch:
                    // the engine only reads it on its first effort fetch, which
                    // can't have run before init returns.)
                    WorkoutRecordLedgerStore.deleteAll()
                    WorkoutEffortLedgerStore.deleteAll()
                } else if !initialPermissionSelection.includes(.workoutMetrics) {
                    WorkoutDetailSnapshotStore.stripWorkoutMetricsPayloads()
                }
                if !initialPermissionSelection.includes(.heart) {
                    WorkoutDetailSnapshotStore.stripHeartRateRecovery()
                }
            }
        }
        snapshot = startingSnapshot
        // The one direct write: `setMonthSnapshots` is a method call, which `init`
        // can't make before every stored property is initialized. It is the initial
        // value rather than a write anyway, so there is no memo to invalidate and
        // `monthSnapshotsGeneration` stays at its own initial 0.
        monthSnapshots = [BodyWorkoutMonthKey: WorkoutMonthSnapshot](
            uniqueKeysWithValues: sanitizedMonthSnapshots.map {
                (BodyWorkoutMonthKey(month: $0.month, year: $0.year), $0)
            }
        )
        // Oldest first, matching `noteMonthSnapshotStored`'s append order, so
        // eviction drops the least recently touched seeded month first.
        // `loadedMonthKeys` is deliberately NOT seeded: it means "fetched from
        // HealthKit this session", which a disk restore is not.
        monthLoadOrder = Set(monthSnapshots.keys).sortedByDate
        // Seeds the color editor's known-workout-types census from the persisted
        // snapshots at launch; `refresh(monthKeys:calendar:)` keeps it current as
        // further months load.
        BodyWorkoutColorStore.mergeKnownWorkoutTypes(
            Set(sanitizedMonthSnapshots.flatMap { $0.days.flatMap(\.workouts) }.map(\.type))
        )
        healthSummary = filteredHealthDashboardSnapshot.summary
        // Restore the summary-reuse gate from the persisted envelope (H2a) so a
        // cold-start failed summary leaf can reuse the hydrated value only while
        // the current selection/prefs still match the ones it was saved under.
        healthSummaryPrimarySignature = loadedDashboard.summaryContextSignature
        dashboardCacheScope = HealthDashboardCacheScope(signature: loadedDashboard.summaryContextSignature)
        let storedSecondarySignature = loadedDashboard.metadata.secondarySelectionSignature
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
        // Initialization does not run the history property's observer.
        pendingActivityRingRepairMonthKeys = activityRingHistory.pendingDayIdentityMonthKeys
        loadedActivityRingMonthKeys = Set(activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))
        // Restore the persisted last-successful-refresh timestamp so the
        // cold-start sync path applies the same tiered TTL as a warm resume.
        completedDashboardFreshness = loadedDashboard.metadata.freshness
        lastSuccessfulRefreshDate = loadedDashboard.metadata.freshness?.date
        activityRingBackfillState = initialPermissionSelection.includes(.activityRings)
            && loadedDashboard.metadata.ringDayIdentityVersion == 1
            ? loadedDashboard.metadata.ringBackfill : .pending(resumeFrom: nil)
        activityRingBackfillResumeDay = loadedDashboard.metadata.ringBackfillResumeDay
        ringHistoricalRepair = initialPermissionSelection.includes(.activityRings)
            ? loadedDashboard.metadata.ringHistoricalRepair : nil
        hasCompletedInitialHealthDataLoad = HealthDashboardSnapshotStore.loadInitialHealthDataLoadCompleted()
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
        // The weekly workout-minutes watermark restores from its OWN key,
        // written only by a fetch that covered every month the trailing week
        // touches. Deriving it from `lastSuccessfulRefreshDate` would launder a
        // coverage claim an early-month passive refresh never earned, letting a
        // relaunch re-stamp a stale mixed-month week as fully refreshed.
        lastWorkoutsRefreshDate = HealthDashboardSnapshotStore.loadLastWorkoutsWeekCoverageDate()
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
        // Personal records hydrate before any view can read them; a missing or
        // schema-stale file yields a fresh ledger, which simply rescans.
        if initialPermissionSelection.includes(.workouts) {
            recordLedger = WorkoutRecordLedgerStore.load() ?? WorkoutRecordLedger()
        }
        Task { await self.refreshCacheDiskSize() }
        if hasStaleReadinessOverlay {
            rebuildStaleReadinessOverlay(
                idealSleepDuration: initialIdealSleepDuration,
                recordedReadinessContext: initialReadinessContext
            )
        }

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
            // The observer runs on `.main`, but the closure itself is not
            // main-actor isolated, so the tracked write is done under an explicit
            // assumption rather than deferred into the task below, which first
            // waits for the refresh slot and would lag the re-render.
            MainActor.assumeIsolated {
                self.proEntitlementGeneration &+= 1
                _ = self.captureRefreshInputs()
            }
            Task { @MainActor in
                await self.hydratePersistedDaySamplesIfNeeded()
                await self.invalidateMemoizedComparisonDaySamples()
                await self.persistContextChange()
            }
        }
        // Injected snapshots are authored under the injected selections. Disk
        // snapshots must prove their own provenance; legacy scalar signatures
        // cannot prove effective source membership or aggregation identity.
        if initialHealthDashboardSnapshot != nil, initialSummaryContextSignature == nil {
            dashboardCacheScope = currentDashboardCacheScope()
            healthSummaryPrimarySignature = dashboardCacheScope?.signature
        }
        reconcileDashboardCacheScope()
        _ = captureRefreshInputs()
        if completedDashboardFreshness?.contextSignature != dashboardFreshnessContextSignature() {
            completedDashboardFreshness = nil
            lastSuccessfulRefreshDate = nil
            lastVitalsRefreshDate = nil
        }
    }

    /// Rebuilds the persisted readiness overlay when the frozen morning records
    /// at rest were captured under a different input context (see the exception
    /// in `init`). Same shape as the refresh path's recompute: `Task.detached`
    /// off the main actor, `cacheEpoch` rechecked before anything is applied.
    /// The save at the end is what makes the drop durable, since init itself
    /// never writes the snapshot back.
    private func rebuildStaleReadinessOverlay(
        idealSleepDuration: TimeInterval,
        recordedReadinessContext: String
    ) {
        let inputs = captureRefreshInputs()
        Task {
            let epoch = self.cacheEpoch
            // A refresh can rebuild the overlay under the current inputs before
            // this task gets its turn; its result is the fresher one, so there
            // is nothing stale left to fix.
            guard self.mayApplyRefreshInputs(inputs),
                  self.healthTrends.recordedReadinessContext != recordedReadinessContext else {
                return
            }

            let permissionSelection = self.permissionSelection
            let rawSnapshot = HealthDashboardSnapshot(
                summary: self.healthSummary,
                trends: self.healthTrends,
                activityRingHistory: self.activityRingHistory
            )
            let filtered = await Task.detached(priority: .userInitiated) {
                let signpostState = BodyPerformanceSignposts.signposter.beginInterval("ReadinessRecompute")
                defer { BodyPerformanceSignposts.signposter.endInterval("ReadinessRecompute", signpostState) }
                return rawSnapshot.filtered(
                    by: permissionSelection,
                    idealSleepDuration: idealSleepDuration,
                    recordedReadinessContext: recordedReadinessContext
                )
            }.value

            // A Clear Cache that landed while the recompute ran must win, and so
            // must a refresh that rebuilt the overlay first: either way this
            // result is the stale one now.
            guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: self.cacheEpoch),
                  self.mayApplyRefreshInputs(inputs),
                  self.healthTrends.recordedReadinessContext != recordedReadinessContext else {
                return
            }

            self.healthSummary = filtered.summary
            self.healthTrends = filtered.trends
            await self.persistPublishedDashboardSnapshot()
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
        let journalFile = workoutJournalFile ?? WorkoutChangeJournalStore.defaultFile
        let size = await Task.detached(priority: .utility) {
            WorkoutSnapshotStore.totalDiskSizeBytes
                + HealthDashboardSnapshotStore.totalDiskSizeBytes
                + HealthWidgetSnapshotStore.totalDiskSizeBytes
                + WorkoutDetailSnapshotStore.totalDiskSizeBytes()
                + WorkoutRecordLedgerStore.totalDiskSizeBytes()
                + WorkoutEffortLedgerStore.totalDiskSizeBytes()
                + WorkoutChangeJournalStore.diskSizeBytes(file: journalFile)
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

        // Only when a prompt can actually appear; otherwise the badge keeps its
        // default `.fetching`.
        if intent == .userInitiated && authorizationState != .authorized {
            setRefreshStage(.authorizing)
        }

        do {
            guard try await requestHealthKitAuthorization(allowPrompt: intent == .userInitiated) else {
                return
            }
            // Clock starts here, after the authorization sheet has returned, so
            // the deadline never counts the user's decision time.
            await runRefreshWithDeadline { await self.refreshRecentMonths(intent: intent) }
        } catch {
            handleRefreshError(error)
        }
    }

    func refreshHealthMetric(_ kind: HealthMetricKind, date: Date = Date(), intent: BodyWorkoutRefreshIntent = .userInitiated) async {
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
        await hydratePersistedDaySamplesIfNeeded()
        await engine.setHealthTrendAnchorDate(date)

        let calendar = Calendar.bodyGregorian

        // Same rule as `requestAuthorizationAndRefresh`: only when a prompt can
        // actually appear.
        if intent == .userInitiated && authorizationState != .authorized {
            setRefreshStage(.authorizing)
        }

        do {
            guard try await requestHealthKitAuthorization(allowPrompt: intent == .userInitiated) else {
                // Match the anchor reset the normal exit runs below.
                await engine.setHealthTrendAnchorDate(nil)
                return
            }
        } catch {
            handleRefreshError(error)
            await engine.setHealthTrendAnchorDate(nil)
            return
        }

        // Clock starts here, after the authorization sheet has returned, so the
        // deadline never counts the user's decision time — same shape as the
        // other refresh entry points.
        await runRefreshWithDeadline {
            await self.performHealthMetricRefresh(kind, date: date, calendar: calendar, intent: intent)
        }
        await engine.setHealthTrendAnchorDate(nil)
    }

    /// The fetch/publish half of `refreshHealthMetric`, split out so it can run
    /// under `runRefreshWithDeadline` with the clock starting AFTER the
    /// authorization sheet rather than before it. Expects the caller to have set
    /// `isRefreshing` (and to call `finishRefresh()` when done), to have
    /// hydrated the day samples, set the trend anchor, and been granted
    /// authorization; the caller resets the anchor on every exit.
    func performHealthMetricRefresh(
        _ kind: HealthMetricKind,
        date: Date,
        calendar: Calendar,
        intent: BodyWorkoutRefreshIntent = .userInitiated
    ) async {
        if kind == .trainingLoad {
            // The detail pull is an explicit gesture on the metric whose window
            // IS the 408 days: drop the per-workout effort cache in full (memory
            // and persisted ledger) so a re-rated workout anywhere in the window
            // reconciles into the training-load fetch. The month-scoped clear
            // used by pull-to-refresh would miss exactly the older workouts this
            // pull exists to reconcile.
            await engine.clearWorkoutEffortCache()
        }
        setRefreshStage(.fetching)
        await fetchHealthDataSourceOptions(calendar: calendar, force: true)
        let inputs = captureRefreshInputs()
        let queryRevision = await engine.queryContextRevision
        guard mayApplyRefreshInputs(inputs), mayApplyRefreshResults else { return }
        let queryScope = currentDashboardCacheScope()
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
            idealSleepDuration: Self.storedIdealSleepDuration(),
            reconcilesRetainedIntradayWindow: intent == .userInitiated
        )
        // A pull abandoned at `healthRefreshDeadline` keeps running; nothing
        // below may publish, persist, or stamp watermarks for a load the user
        // was already told had timed out.
        guard !Task.isCancelled, mayApplyRefreshResults else { return }
        guard await engine.queryContextRevision == queryRevision,
              mayApplyRefreshInputs(inputs), queryScope == currentDashboardCacheScope(), mayApplyRefreshResults else {
            needsContextRefresh = true
            contextRefreshRequiresFetch = true
            scheduleContextRefreshIfNeeded()
            return
        }
        let nextSummary = healthSummary.replacingMetric(kind, with: metricFetch.snapshot.summary)
        // Passive day-sample fetches inside the engine are incremental: they merge
        // onto the `existing` cache captured above. The source mutators push the
        // new selection into the engine BEFORE they wait out this refresh (see
        // `updateSecondaryHealthDataSource`), so a switch landing mid-fetch would
        // have the engine query the NEW source and merge it onto the OLD source's
        // cached points — and `updateHealthDashboardSnapshot` would persist that
        // mixed series stamped with the NEW signature, which `scopedForHydration`
        // then accepts forever. Drop the fetched day samples in that case; the
        // mutator clears and refetches them right after this refresh releases.
        let acceptsDaySamples = currentDaySampleSignatures() == capturedDaySampleSignatures
        let fetchedTrends = acceptsDaySamples
            ? metricFetch.snapshot.trends
            : metricFetch.snapshot.trends.strippingDaySamples()
        let nextTrends = healthTrends.replacingMetric(kind, with: fetchedTrends)
        setRefreshStage(.computing)
        guard await updateHealthDashboardSnapshot(
            summary: nextSummary,
            trends: nextTrends,
            activityRingHistory: activityRingHistory,
            recomputesReadiness: Self.readinessInputMetricKinds.contains(kind),
            recomputesStress: Self.stressInputMetricKinds.contains(kind),
            recomputesBodyRadar: Self.bodyRadarInputMetricKinds.contains(kind),
            authoritativeDaySamples: acceptsDaySamples ? metricFetch.authoritativeDaySampleSeries : []
        ) else { return }
        guard mayApplyRefreshResults else { return }
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
                    guard mayApplyRefreshResults else { return }
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
    }

    /// Runs a post-write refresh for `kind`, first waiting for any in-flight
    /// refresh to finish. `refreshHealthMetric` bails out when `isRefreshing` is
    /// already set, so a measurement or effort saved during launch or
    /// pull-to-refresh would otherwise never flow into the dashboard until the
    /// next manual refresh.
    private func refreshAfterWrite(_ kind: HealthMetricKind) async {
        guard await awaitRefreshSlotFree() else { return }
        await engine.markHealthSourcesDirty(for: [kind])
        // A write already raised its own (share) permission sheet; this read-side
        // refresh must never stack a second one on top of it.
        await refreshHealthMetric(kind, intent: .passiveResume)
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

    @ObservationIgnored
    private var isAutoApplyingEffort = false
    /// True while `clearLocalCache` is wiping in-memory state and awaiting the
    /// engine cache clears + the on-disk deletion barrier. Guards re-entry so a
    /// second Clear tap can't interleave with an in-flight wipe.
    @ObservationIgnored
    private var isClearingCache = false
    /// Bumped by `clearLocalCache`. Every async path that can publish or persist
    /// after a suspension captures this before its first `await` and re-checks it
    /// before mutating published state or enqueuing a save; a mismatch means a
    /// cache clear landed mid-flight, so the path bails instead of resurrecting
    /// the wiped data (H7).
    @ObservationIgnored
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
    @ObservationIgnored
    private var autoAppliedWorkoutIDs: Set<UUID> = []
    /// Workouts found already rated by a fresh read at write time — cached so a rating
    /// that won't disappear isn't re-queried every refresh. Low-confidence (no-HR)
    /// workouts are deliberately *not* cached here: their HR can arrive late, so they
    /// stay eligible for re-estimation on later refreshes within the window.
    @ObservationIgnored
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
              defaults.object(forKey: BodyAppearancePreference.workoutEffortCardEnabledKey) as? Bool ?? true,
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
        // Subtract `loadedMonthKeys` (fetched this session), not `monthSnapshots`
        // membership: launch seeds the persisted months into memory, so a stale
        // seeded month would otherwise be scanned instead of refetched.
        let missingWindowKeys = Set(windowKeys).subtracting(loadedMonthKeys)
        if !missingWindowKeys.isEmpty {
            setRefreshStage(.fetching)
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
        // which is seeded from the persisted month files at launch.
        let comparisonKeys = Self.autoApplyComparisonMonthKeys(
            now: now,
            maxAge: Self.autoApplyMaxWorkoutAge,
            maxDuration: Self.autoApplyMaxComparisonWorkoutDuration,
            calendar: Calendar.bodyGregorian
        )
        let missingComparisonKeys = Set(comparisonKeys).subtracting(loadedMonthKeys)
        if !missingComparisonKeys.isEmpty {
            setRefreshStage(.fetching)
            try? await refresh(monthKeys: missingComparisonKeys, calendar: Calendar.bodyGregorian)
        }
        // Past every month load: what follows scores the candidates and writes
        // them back to HealthKit.
        setRefreshStage(.writingEffort)
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
                // Stop mid-batch if Auto-Apply (or either toggle above it —
                // suggestions, or the Effort card itself) was switched off, or the
                // running task was cancelled (Settings retains and cancels this
                // task on OFF/onDisappear).
                !Task.isCancelled
                    && UserDefaults.standard.bool(forKey: BodyAppearancePreference.autoApplyWorkoutEffortKey)
                    && (UserDefaults.standard.object(forKey: BodyAppearancePreference.workoutEffortCardEnabledKey) as? Bool ?? true)
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
    /// wait-first mirrors `refreshAfterWrite`; `awaitRefreshSlotFree` covers a fresh
    /// refresh claiming the slot between our resume and our claim.
    func autoApplyPredictedEffortNow() async {
        guard await awaitRefreshSlotFree() else { return }
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
        // Captured before the first suspension: a confirmed absence read while the
        // disk seed was bypassed is the signal that the stored file is stale.
        let revalidating = bypassesPersistedDetailSeeding
        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = detailCaches.routeCache[workout.id] {
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
            detailCaches.routeCache[workout.id] = .some(nil)
            // Route samples existed but carry no drawable line, so the presence probe's
            // "yes" was a false positive. Record the negative here as well or the detail
            // page would reserve its hero band again on every reopen.
            detailCaches.routePresenceCache[workout.id] = false
            if revalidating {
                discardPersistedWorkoutDetail(for: workout)
            }
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
        detailCaches.routeCache[workout.id] = .some(route)
        detailCaches.routePresenceCache[workout.id] = true
        if permissionSelection.includes(.workouts) {
            let dto = PersistedWorkoutRoute(model: route)
            persistWorkoutDetail(for: workout) { $0.route = dto }
        }
        return detailCaches.routeCache[workout.id] ?? nil
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
        let revalidating = bypassesPersistedDetailSeeding
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
        detailCaches.routePresenceCache[workout.id] = hasRoute
        if !hasRoute, revalidating {
            discardPersistedWorkoutDetail(for: workout)
        }
        return hasRoute ? .present : .absent
    }

    /// The session-cached route, without starting a read, so a reopened detail page
    /// paints its hero on the first frame instead of after a `.task` round trip.
    func cachedWorkoutRoute(for workout: WorkoutSummary) -> WorkoutRoute? {
        detailCaches.routeCache[workout.id] ?? nil
    }

    /// The presence a cached load or probe already settled, or `.unknown` when this
    /// workout hasn't been read this session. A settled route always wins over the
    /// probe cache, since only the load knows whether the fixes were drawable.
    func cachedWorkoutRoutePresence(for workout: WorkoutSummary) -> BodyWorkoutRoutePresence {
        if let cachedRoute = detailCaches.routeCache[workout.id] {
            return cachedRoute == nil ? .absent : .present
        }
        guard let probed = detailCaches.routePresenceCache[workout.id] else {
            return .unknown
        }
        return probed ? .present : .absent
    }

    /// Reverse-geocodes the cached route's "City, Region" label and folds it back
    /// into `BodyWorkoutDetailCacheStore.routeCache`, returning the route with `locality` resolved (or the
    /// coordinates-only route when the geocode yields nothing). No-op when the
    /// workout has no cached route or the label is already resolved. Safe to call
    /// as a follow-up after `loadWorkoutRoute` so the map renders on coordinates
    /// without blocking on the reverse geocode.
    func resolveWorkoutRouteLocality(for workout: WorkoutSummary) async -> WorkoutRoute? {
        guard case .some(.some(let route)) = detailCaches.routeCache[workout.id] else {
            // No cached entry, or a cached "no route" negative — nothing to geocode.
            return detailCaches.routeCache[workout.id] ?? nil
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
        detailCaches.routeCache[workout.id] = .some(resolved)
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

        let revalidating = bypassesPersistedDetailSeeding
        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = detailCaches.distanceSampleCache[workout.id] {
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
            detailCaches.distanceSampleCache[workout.id] = data
            // Splits carry per-split step cadence, so they're only persisted while
            // Workout Metrics is on: a cadence-less payload written with the toggle
            // off would satisfy the cache after a re-enable and never be re-read.
            // The downsample runs inside the persist queue — it can chew through
            // thousands of samples — and a nil result (an over-cap workout) leaves
            // any existing field alone rather than clearing it.
            if permissionSelection.includes(.workouts), permissionSelection.includes(.workoutMetrics) {
                persistWorkoutDetail(for: workout) {
                    $0.splitData = PersistedWorkoutSplitData.downsampled(from: data) ?? $0.splitData
                }
            }
        } else {
            // Cache a confirmed-empty read only for settled (>24h-old) workouts;
            // a recent one may still be syncing from the watch.
            let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))
            if Date().timeIntervalSince(endDate) > 24 * 60 * 60 {
                detailCaches.distanceSampleCache[workout.id] = data
                if revalidating {
                    discardPersistedWorkoutDetail(for: workout)
                }
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

        let revalidating = bypassesPersistedDetailSeeding
        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = detailCaches.metricSeriesCache[workout.id] {
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
            detailCaches.metricSeriesCache[workout.id] = data
            // Persist only a bundle that actually carries a series. A denied
            // Workout Metrics read surfaces as an empty (non-throwing) bundle, and
            // writing that would freeze the negative on disk past the session wipes.
            let carriesData = !data.distanceMeters.isEmpty
                || !data.steps.isEmpty
                || data.strideLengthMeters != nil
                || data.groundContactTimeMs != nil
                || data.verticalOscillationCm != nil
                || data.cyclingCadenceRPM != nil
                || data.powerWatts != nil
            if carriesData, permissionSelection.includes(.workoutMetrics) {
                let dto = PersistedWorkoutMetricSeries(model: data)
                persistWorkoutDetail(for: workout) { $0.metricSeries = dto }
            } else if !carriesData, revalidating {
                discardPersistedWorkoutDetail(for: workout)
            }
        }
        return data
    }

    /// Loads a workout's 1-minute heart-rate recovery for the detail tile, or nil
    /// when the Heart permission is off, no recovery reading exists, or the read
    /// failed. Not gated on pace style — every activity type can have one.
    func loadWorkoutHeartRateRecovery(for workout: WorkoutSummary) async -> Double? {
        let revalidating = bypassesPersistedDetailSeeding
        await hydrateWorkoutDetailIfNeeded(for: workout)
        if let cached = detailCaches.heartRateRecoveryCache[workout.id] {
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
            detailCaches.heartRateRecoveryCache[workout.id] = recovery
            // The confirmed-absent `nil` above stays session-only: a Heart read the
            // user has denied also answers nil, so persisting it would outlive the
            // permission change that a session cache can't survive.
            if let bpm = recovery, bpm > 0, permissionSelection.includes(.heart) {
                persistWorkoutDetail(for: workout) { $0.heartRateRecoveryBPM = bpm }
            } else if recovery == nil, revalidating {
                discardPersistedWorkoutDetail(for: workout)
            }
        }
        return recovery
    }

    /// Loads a workout's full-resolution heart-rate series for the detail sheet's
    /// chart and zones, or `nil` when the Heart permission is off or the read
    /// failed — a `nil` tells the caller to keep showing the summary's ≤96-point
    /// payload, and reopening the sheet retries. Cached per session; an empty read
    /// is cached only when the workout ended more than 24 h ago, so a still-syncing
    /// recent workout is re-read on reopen.
    func loadWorkoutHeartRateSeries(for workout: WorkoutSummary) async -> [WorkoutHeartRateSample]? {
        guard permissionSelection.includes(.heart) else {
            return nil
        }

        if let cached = detailCaches.heartRateSeriesCache[workout.id] {
            return cached
        }

        let epoch = cacheEpoch
        let samples: [WorkoutHeartRateSample]
        do {
            samples = try await engine.workoutHeartRateSamples(workoutID: workout.id)
        } catch {
            // Cancelled (sheet dismissed mid-read) or a read failure — don't cache
            // an empty as confirmed-absent; reopening retries.
            return nil
        }
        guard !Task.isCancelled else {
            return samples
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return samples
        }
        if !samples.isEmpty {
            detailCaches.heartRateSeriesCache[workout.id] = samples
        } else if Date().timeIntervalSince(workout.effectiveEndDate) > 24 * 60 * 60 {
            // Cache a confirmed-empty read only for settled (>24h-old) workouts;
            // a recent one may still be syncing from the watch.
            detailCaches.heartRateSeriesCache[workout.id] = samples
        }
        return samples
    }

    /// Returns the food-emoji breakdown of a workout's active-energy
    /// kilocalories for the "Equivalent" card, or nil when there is nothing
    /// meaningful to show (see `EnergyEquivalent.decompose`).
    ///
    /// Invalidation rule: the cached/persisted breakdown is reused iff its
    /// `kilocalories` matches the workout's current active energy AND its
    /// `hiddenFoods` matches `hiddenFoods` exactly AND it was computed under
    /// the same `prefersMoreItems` choice (older payloads without the flag
    /// read as false). `tuningVersion` is forensic metadata only and never
    /// invalidates — bumping it recomputes nothing on its own. A mismatch
    /// (kcal restated by HealthKit, or the user changed which foods are hidden
    /// or the representation style) recomputes and re-persists.
    func energyEquivalentEmojis(for workout: WorkoutSummary, hiddenFoods: Set<String>, prefersMoreItems: Bool, usesTotalEnergy: Bool) async -> [String]? {
        let revalidating = bypassesPersistedDetailSeeding
        await hydrateWorkoutDetailIfNeeded(for: workout)

        // The source-kcal choice needs no field of its own in the payload — a
        // switch between active and total shows up as a kilocalories mismatch.
        let sourceKilocalories = usesTotalEnergy
            ? (workout.totalEnergyKilocalories ?? workout.activeEnergyKilocalories)
            : workout.activeEnergyKilocalories

        if let cached = detailCaches.energyEquivalentCache[workout.id],
           cached.kilocalories == sourceKilocalories,
           Set(cached.hiddenFoods) == hiddenFoods,
           (cached.prefersMoreItems ?? false) == prefersMoreItems {
            return cached.emojis
        }

        guard let foods = EnergyEquivalent.decompose(
            kilocalories: sourceKilocalories,
            excluding: hiddenFoods,
            preferringMoreItems: prefersMoreItems
        ) else {
            if revalidating {
                discardPersistedWorkoutDetail(for: workout)
            }
            return nil
        }

        let emojis = foods.map { $0.emoji }
        let payload = PersistedEnergyEquivalent(
            tuningVersion: EnergyEquivalent.tuningVersion,
            kilocalories: sourceKilocalories ?? 0,
            hiddenFoods: hiddenFoods.sorted(),
            prefersMoreItems: prefersMoreItems,
            emojis: emojis
        )
        detailCaches.energyEquivalentCache[workout.id] = payload
        if permissionSelection.includes(.workouts) {
            persistWorkoutDetail(for: workout) { $0.energyEquivalent = payload }
        }
        return emojis
    }

    /// Seeds the per-workout detail session caches from the workout's persisted
    /// snapshot, so reopening a settled workout after a cold launch paints its map,
    /// charts and recovery tile without re-scanning HealthKit. Idempotent;
    /// concurrent callers share one file read and resume on the finished seed.
    ///
    /// Only *missing* entries are seeded — a value this session already read from
    /// HealthKit is always the fresher one. Nothing on disk is a negative (the store
    /// is written positive-only), so a seed can never pin a "no route" / "no
    /// recovery" answer.
    ///
    /// Skipped entirely while `bypassesPersistedDetailSeeding` is set, so every
    /// open after a background transition reads HealthKit live.
    private func hydrateWorkoutDetailIfNeeded(for workout: WorkoutSummary) async {
        detailCaches.touch(workout.id)
        // After a background transition the files hold positives captured under a
        // grant the user may have just revoked, and `permissionSelection` (the gate
        // every seed below rides) tracks only Body's own toggles, not a change made
        // in the Health app or Settings. Nothing short of a live read validates a
        // persisted payload, so seeding stays off for the rest of the process, not
        // just until the next refresh: skip the seed entirely so the loaders read
        // HealthKit live, re-persist whatever is still readable, and delete the
        // file for a detail Apple Health no longer returns. The files are used
        // again on the next launch.
        guard !bypassesPersistedDetailSeeding else {
            return
        }
        if let existing = detailCaches.detailHydrations[workout.id] {
            await existing.value
            return
        }

        let epoch = cacheEpoch
        // The stored task covers the read AND the seeding, so the early-return
        // above hands a second caller fully seeded caches. Seeding after an
        // awaited read outside the task instead would let that caller resume on
        // the read alone and miss every entry.
        let task = Task { @MainActor [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                WorkoutDetailSnapshotStore.load(workoutID: workout.id)
            }.value
            guard let self else {
                return
            }

            // A cache clear landed while the file read was in flight — the workout this
            // describes is gone, so don't re-seed the wiped caches (H7).
            guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: self.cacheEpoch) else {
                return
            }

            // Every seed is gated on the CURRENT selection, not the one the file was
            // written under: the at-rest strip is queued, so a file can outlive an
            // opt-out (app killed before the queue drained, or a hydration racing the
            // toggle). This gate is what guarantees stripped-permission data never
            // surfaces, whatever state the file is in.
            if let route = snapshot?.route,
               self.detailCaches.routeCache[workout.id] == nil,
               self.permissionSelection.includes(.workouts) {
                self.detailCaches.routeCache[workout.id] = .some(route.toModel())
                self.detailCaches.routePresenceCache[workout.id] = true
            }
            // A payload from before a series joined the bundle is ignored once: the
            // loader re-reads live and re-persists it at the current version.
            if let series = snapshot?.metricSeries,
               series.seriesVersion == PersistedWorkoutMetricSeries.currentSeriesVersion,
               self.detailCaches.metricSeriesCache[workout.id] == nil,
               self.permissionSelection.includes(.workoutMetrics) {
                self.detailCaches.metricSeriesCache[workout.id] = series.toModel()
            }
            if let splitDTO = snapshot?.splitData,
               self.detailCaches.distanceSampleCache[workout.id] == nil,
               self.permissionSelection.includes(.workouts),
               self.permissionSelection.includes(.workoutMetrics) {
                self.detailCaches.distanceSampleCache[workout.id] = splitDTO.toModel()
            }
            if let bpm = snapshot?.heartRateRecoveryBPM,
               self.detailCaches.heartRateRecoveryCache[workout.id] == nil,
               self.permissionSelection.includes(.heart) {
                self.detailCaches.heartRateRecoveryCache[workout.id] = .some(bpm)
            }
            // Energy equivalent derives from active-energy kilocalories, which rides
            // the Workouts permission like the route and split caches above.
            if let energyEquivalent = snapshot?.energyEquivalent,
               self.detailCaches.energyEquivalentCache[workout.id] == nil,
               self.permissionSelection.includes(.workouts) {
                self.detailCaches.energyEquivalentCache[workout.id] = energyEquivalent
            }
        }
        detailCaches.detailHydrations[workout.id] = task
        await task.value
    }

    /// The least-recently-touched ids to drop so at most `maximum` workouts keep
    /// their detail caches. `order` is ordered oldest-touched first.
    nonisolated static func evictableWorkoutDetailIDs(order: [UUID], maximum: Int) -> [UUID] {
        let excess = order.count - maximum
        guard excess > 0 else {
            return []
        }
        return Array(order.prefix(excess))
    }

    /// Whether a workout's details are worth keeping on disk: it has settled (the
    /// same >24 h rule the loaders admit results to the session caches under, so a
    /// still-syncing watch workout is never pinned). Not limited to the current or
    /// previous month: `WorkoutDetailSnapshotStore.prune(keeping:retainingRecentLimit:)`
    /// bounds on-disk growth by persist-recency, so an old-month detail is free to
    /// persist and simply ages out of the cap like any other file.
    nonisolated static func isWorkoutDetailPersistable(
        workout: WorkoutSummary,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        now.timeIntervalSince(workout.effectiveEndDate) > 24 * 60 * 60
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

    /// Removes the workout's on-disk detail snapshot, on the same persist queue
    /// as `persistWorkoutDetail`. Called when a live read that ran while disk
    /// seeding was bypassed confirms Apple Health no longer returns one of the
    /// stored details, so the file's remaining positives can't be trusted either.
    ///
    /// Dropping the whole file is intended: each other field is re-persisted by
    /// its own live loader through `persistWorkoutDetail` (which loads-or-creates
    /// the file), and everything in it is rebuildable from Apple Health. Ordering
    /// against a concurrent persist needs no coordination: the queue is serial, so
    /// either order leaves a correct file, holding either the fresh positive alone
    /// or nothing at all.
    private func discardPersistedWorkoutDetail(for workout: WorkoutSummary) {
        let workoutID = workout.id
        Self.snapshotPersistQueue.async {
            WorkoutDetailSnapshotStore.delete(workoutID: workoutID)
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
    }

    /// Estimated max heart rate (220 − age) from Apple Health, anchoring the
    /// workout-detail heart-rate zones. `nil` when no birth date is readable, so the
    /// caller falls back to the session's peak HR.
    func userMaxHeartRate() async -> Double? {
        await engine.userMaxHeartRate()
    }

    /// The single authorization gate every load path funnels through. Returns
    /// `false` when the read-permission sheet would have been needed but
    /// `allowPrompt` is off — the caller must then abort its whole load and
    /// leave the cache untouched, because unrequested reads look empty to
    /// HealthKit and would overwrite good data with nothing.
    ///
    /// The sheet therefore appears only on user-initiated actions
    /// (pull-to-refresh, the first-launch load, the Settings/onboarding
    /// toggles, a month-picker tap, a metric-detail pull, an effort/weight
    /// save). Passive foreground resumes, post-write refreshes and automatic
    /// preloads defer instead and keep showing cached data.
    private func requestHealthKitAuthorization(allowPrompt: Bool = true) async throws -> Bool {
        let outcome = try await engine.requestAuthorization(allowPrompt: allowPrompt)
        switch outcome {
        case .promptDeferred:
            return false
        case .authorized:
            break
        }

        // A pass that only re-checked a recorded decision changed nothing about
        // what is readable, so the per-workout caches stay — wiping them on every
        // load path made reopening a workout refetch its route, splits, series and
        // recovery after each refresh. The background transition invalidates the
        // in-memory caches on its own, eagerly, in `noteAppDidEnterBackground()`.

        guard Self.shouldClearDetailCaches(after: outcome) else {
            return true
        }

        // Safe to re-hydrate from disk right away: the files hold only positives,
        // so nothing they seed can contradict the fresh authorization.
        detailCaches.clearAll()
        return true
    }

    /// Whether an authorization pass changed what HealthKit will hand back and so
    /// invalidates the per-workout detail caches. Only a pass that actually
    /// presented the permission sheet can have flipped a read grant; a status
    /// re-check that found a recorded decision leaves every cached answer valid.
    /// A grant changed outside Body is handled separately, by the eager clear in
    /// `noteAppDidEnterBackground()`.
    nonisolated static func shouldClearDetailCaches(
        after outcome: HealthKitFetchEngine.AuthorizationOutcome
    ) -> Bool {
        switch outcome {
        case .promptDeferred:
            return false
        case .authorized(let didPrompt):
            return didPrompt
        }
    }

    /// Loads the intraday day-sample sidecar (split out of the launch-critical
    /// snapshot decode) off the main actor and merges it into any still-empty
    /// `*DaySamples` fields. Refresh and lazy-load entry points await this
    /// first so a snapshot save can never overwrite the sidecar with empty
    /// series before it has been read, and so the incremental intraday fetch
    /// sees the cached points. Idempotent; concurrent callers share one load.
    func hydratePersistedDaySamplesIfNeeded() async {
        reconcileDashboardCacheScope()
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

        reconcileDashboardCacheScope()
        // Scope the sidecar to the current selection before merging so a source
        // switch, combine-flag flip, now-off permission, or a comparison the
        // current selection resolves away can't resurrect stale intraday points
        // (H6). A legacy/v1 sidecar (no combine stamp) fails closed and is dropped
        // one-time.
        var scoped = daySamples.scopedForHydration(
            currentPrimarySignature: currentPrimarySelectionSignature(),
            currentSecondarySignature: currentSecondarySelectionSignature(),
            currentCombinesByName: combinesHealthDataSourcesByName,
            permission: permissionSelection,
            comparisonDisabledKinds: currentComparisonDisabledKinds(),
            currentPrimaryMetricScopes: currentDashboardCacheScope().rawSignatures(),
            currentSecondaryMetricScopes: currentDashboardCacheScope().rawSignatures(secondary: true)
        )
        // A memoized pre-repair sidecar must not resurrect successfully deleted
        // samples, even when the replacement write has not finished yet.
        scoped = excludingReconciledDaySamples(from: scoped)
        guard !scoped.isEmpty else {
            return
        }

        healthTrends = healthTrends.mergingMissingDaySamples(from: scoped)
    }

    func excludingReconciledDaySamples(from samples: HealthTrendDaySampleSnapshot) -> HealthTrendDaySampleSnapshot {
        var next = samples
        for series in authoritativeDaySampleSeries { next[keyPath: series.keyPath] = .empty }
        return next
    }

    private func recordAuthoritativeDaySamples(_ series: Set<HealthDaySampleSeries>) {
        guard !series.isEmpty else { return }
        authoritativeDaySampleSeries.formUnion(series)
        for field in series { daySampleRevisions[field, default: 0] &+= 1 }
    }

    /// Admit each raw field independently: another loader's Steps publication
    /// must not discard this load's HRV or oxygen result. Repeated repairs still
    /// advance their field revision even when write authority was already held.
    @discardableResult
    func publishDaySamples(
        from candidate: HealthTrendSnapshot,
        successfulSeries: Set<HealthDaySampleSeries>,
        capturedRevisions: [HealthDaySampleSeries: Int]
    ) -> Set<HealthDaySampleSeries> {
        let admitted = successfulSeries.filter {
            daySampleRevisions[$0, default: 0] == capturedRevisions[$0, default: 0]
        }
        var next = healthTrends
        for field in admitted { next[keyPath: field.trendKeyPath] = candidate[keyPath: field.trendKeyPath] }
        healthTrends = next
        recordAuthoritativeDaySamples(admitted)
        return admitted
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
        case .stress:
            // Stress reads four series plus the beat-to-beat scan and then
            // recomputes, so it has its own loader (with the same guards).
            // Share the refresh's in-flight load rather than starting a second
            // one: the two would fetch and merge the same state at once, and
            // the detail page has to observe the result before it returns.
            // `startStressInputLoad` rather than `startStressInputLoadIfNeeded`
            // because the dashboard-card gate the latter applies must not reach
            // a detail page the user opened explicitly.
            guard permissionSelection.includes(.heart) else { return }
            if stressInputLoadTask == nil { startStressInputLoad() }
            await stressInputLoadTask?.value
            return
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
            // Lazy day-chart fill: never worth a permission sheet.
            guard try await requestHealthKitAuthorization(allowPrompt: false) else {
                return
            }
        } catch {
            return
        }

        let calendar = Calendar.bodyGregorian
        let interval = HealthKitFetchEngine.intradayDaySampleInterval(calendar: calendar, anchor: nil)
        let cachedPrimary = healthTrends.daySeries(for: kind)
        let cachedSecondary = healthTrends.secondaryDaySeries(for: kind)
        let capturedDaySampleSignatures = currentDaySampleSignatures()
        let capturedDaySampleRevisions = daySampleRevisions
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
        //
        // This is a lazy day-chart fill behind a metric detail view, not part of
        // the refresh, so it spends the background budget.
        let primarySamples = await withBackgroundQueryPool {
            await engine.fetchIntradayDaySamples(
                for: kind,
                calendar: calendar,
                startDate: primaryFetchStart,
                endDate: interval.end
            )
        }
        let secondarySamples: HealthTrendSeries?
        if secondaryIsDisabled {
            secondarySamples = .empty
        } else {
            secondarySamples = await withBackgroundQueryPool {
                await engine.fetchSecondaryDaySamples(
                    for: kind,
                    calendar: calendar,
                    startDate: secondaryFetchStart,
                    endDate: interval.end
                )
            }
        }

        // A refresh may have started while the engine fetches above were
        // suspended. It captured `healthTrends` before these day samples existed
        // and will overwrite our write below when it completes — dropping the
        // just-loaded intraday series and persisting that regression. Wait for
        // any in-flight refresh (the helper loops over a fresh one claiming the
        // slot before we resume), then merge onto the now-current
        // `healthTrends`. There is no suspension point between the wait and the
        // write, so on the MainActor nothing can clobber it.
        guard await awaitRefreshSlotFree() else {
            return
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
        // mid-flight invalidations: the engine fetches and the refresh-slot
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
        // Make the lazily fetched series durable so the next launch renders the
        // day chart straight from the sidecar.
        var successfulSeries: Set<HealthDaySampleSeries> = []
        for series in HealthDaySampleSeries.allCases
        where series.kind == kind && series != .heartbeatRMSSDDaySamples {
            if series.isSecondary ? secondarySamples != nil : primarySamples != nil {
                successfulSeries.insert(series)
            }
        }
        guard !publishDaySamples(from: trends, successfulSeries: successfulSeries,
                                 capturedRevisions: capturedDaySampleRevisions).isEmpty else { return }
        persistDaySampleSidecar()
    }

    /// Post-refresh continuation for Stress. Two reasons it can't ride the
    /// refresh itself: the beat-to-beat scan is a fan-out of streaming queries
    /// that the 120 s refresh deadline must never wait on, and the intraday
    /// series Stress scores from are carried forward from cache by
    /// `fetchHealthTrends` rather than refetched. Fired, never awaited.
    ///
    /// Gated on the card actually being on screen somewhere: an invisible metric
    /// is not worth a heartbeat-series scan on every refresh.
    private func startStressInputLoadIfNeeded() {
        guard permissionSelection.includes(.heart),
              BodyDashboardFetchSelection.load().includes(.stress),
              stressInputLoadTask == nil else {
            return
        }

        startStressInputLoad()
    }

    /// Starts the Stress input load unconditionally. Split out of
    /// `startStressInputLoadIfNeeded` for the metric detail page, which loads
    /// Stress on demand and so must not inherit the dashboard-card gate; it
    /// applies its own permission and in-flight checks before calling this.
    private func startStressInputLoad() {
        stressInputLoadTask = Task { [weak self] in
            await self?.loadStressInputSamples()
            self?.stressInputLoadTask = nil
            // The history walk stands down while this load holds the slot, and
            // `finishRefresh` has long since run — so hand the slot over here.
            self?.scheduleStressBackfillIfNeeded()
        }
    }

    /// Fetches the intraday inputs Stress scores from — HR/HRV day samples, the
    /// coarse steps/active-energy movement mask, and the beat-to-beat RMSSD
    /// series — then recomputes. Every fetch is incremental against the cached
    /// series and bounded to the intraday day-sample window, so today's curve
    /// stays current without re-pulling a month of samples.
    private func loadStressInputSamples() async {
        let epoch = cacheEpoch
        await hydratePersistedDaySamplesIfNeeded()
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled,
              permissionSelection.includes(.heart),
              HKHealthStore.isHealthDataAvailable() else {
            return
        }

        do {
            // Background fill: never worth a permission sheet.
            guard try await requestHealthKitAuthorization(allowPrompt: false) else {
                return
            }
        } catch {
            return
        }

        let calendar = Calendar.bodyGregorian
        let interval = HealthKitFetchEngine.intradayDaySampleInterval(calendar: calendar, anchor: nil)
        let capturedDaySampleSignatures = currentDaySampleSignatures()
        let capturedDaySampleRevisions = daySampleRevisions

        var fetched: [HealthMetricKind: (samples: HealthTrendSeries, refetchStart: Date)] = [:]
        for kind in Self.stressIntradaySampleKinds
        where permissionSelection.includes(HealthKitFetchEngine.healthPermission(forMetric: kind)) {
            var fetchStart = HealthKitFetchEngine.incrementalFetchStart(
                after: healthTrends.daySeries(for: kind),
                windowStart: interval.start
            )
            // Hourly cumulative buckets overlap on their own day and the merge
            // has no bucket dedupe, so restart at that day's midnight.
            if kind == .steps || kind == .activeEnergy {
                fetchStart = max(interval.start, calendar.startOfDay(for: fetchStart))
            }
            guard fetchStart < interval.end else {
                continue
            }
            // A `nil` result is a failed query, not an empty day: skip the kind
            // and keep its cached series. Post-refresh continuation, so it
            // spends the background budget.
            guard let samples = await withBackgroundQueryPool({
                await engine.fetchIntradayDaySamples(
                    for: kind,
                    calendar: calendar,
                    startDate: fetchStart,
                    endDate: interval.end
                )
            }) else {
                continue
            }
            fetched[kind] = (samples, fetchStart)
        }

        let rmssdFetchStart = HealthKitFetchEngine.incrementalFetchStart(
            after: healthTrends.heartbeatRMSSDDaySamples,
            windowStart: interval.start
        )
        // The beat-to-beat scan is a fan-out of streaming queries the refresh
        // deliberately never waits on, so it is the other query the background
        // budget exists for.
        let rmssdSamples: HealthTrendSeries? = rmssdFetchStart < interval.end
            ? await withBackgroundQueryPool({
                await engine.fetchHeartbeatRMSSDSamples(startDate: rmssdFetchStart, endDate: interval.end)
            })
            : nil

        // Same hazard as `loadIntradayMetricSamplesIfNeeded`: a refresh that
        // started while the fetches were suspended captured `healthTrends`
        // before these samples existed and would overwrite the merge below.
        guard await awaitRefreshSlotFree() else {
            return
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              currentDaySampleSignatures() == capturedDaySampleSignatures else {
            return
        }

        var trends = healthTrends
        for (kind, result) in fetched {
            let merged = HealthKitFetchEngine.mergeIntradaySamples(
                existing: trends.daySeries(for: kind),
                incoming: result.samples,
                windowStart: interval.start,
                refetchStart: result.refetchStart
            )
            switch kind {
            case .heartRate:
                trends.heartRateDaySamples = merged
            case .heartRateVariability:
                trends.heartRateVariabilityDaySamples = merged
            case .steps:
                trends.stepsDaySamples = merged
            case .activeEnergy:
                trends.activeEnergyDaySamples = merged
            default:
                break
            }
        }
        if let rmssdSamples {
            trends.heartbeatRMSSDDaySamples = HealthKitFetchEngine.mergeIntradaySamples(
                existing: trends.heartbeatRMSSDDaySamples,
                incoming: rmssdSamples,
                windowStart: interval.start,
                refetchStart: rmssdFetchStart
            )
        }
        var successfulSeries = Set(HealthDaySampleSeries.allCases.filter {
            !$0.isSecondary && $0 != .heartbeatRMSSDDaySamples && fetched[$0.kind] != nil
        })
        if rmssdSamples != nil { successfulSeries.insert(.heartbeatRMSSDDaySamples) }
        guard !publishDaySamples(from: trends, successfulSeries: successfulSeries,
                                 capturedRevisions: capturedDaySampleRevisions).isEmpty else { return }
        persistDaySampleSidecar()
        await recomputeStress(on: Date(), calendar: calendar)
        await recomputeBodyRadar(on: Date(), calendar: calendar)
    }

    /// The Radar-gated twin of `startStressInputLoadIfNeeded`. Body Radar reads
    /// the hourly step buckets for its inactive-time signal, but the dashboard
    /// refresh only carries `stepsDaySamples` forward from cache — the Stress
    /// input load is what keeps them current, and that is gated on Heart plus
    /// the Stress card. With Stress hidden or Heart off, Radar would silently
    /// lose the signal, so load the step buckets on their own.
    ///
    /// Skipped whenever the Stress load is going to run: it already fetches
    /// `.steps` over the same window and recomputes Radar afterwards. Its own
    /// task rather than the Stress one, so the Stress detail page (which awaits
    /// `stressInputLoadTask`) never inherits a load that fetched no HR.
    private func startBodyRadarStepLoadIfNeeded() {
        guard bodyRadarStepLoadTask == nil,
              stressInputLoadTask == nil,
              computesBodyRadar,
              permissionSelection.includes(.steps) else {
            return
        }

        bodyRadarStepLoadTask = Task { [weak self] in
            await self?.loadBodyRadarStepSamples()
            self?.bodyRadarStepLoadTask = nil
        }
    }

    /// Steps-only slice of `loadStressInputSamples`, with the same window,
    /// incremental fetch, refresh-slot wait and epoch/signature guards.
    private func loadBodyRadarStepSamples() async {
        let epoch = cacheEpoch
        await hydratePersistedDaySamplesIfNeeded()
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled,
              permissionSelection.includes(.steps),
              HKHealthStore.isHealthDataAvailable() else {
            return
        }

        do {
            // Background fill: never worth a permission sheet.
            guard try await requestHealthKitAuthorization(allowPrompt: false) else {
                return
            }
        } catch {
            return
        }

        let calendar = Calendar.bodyGregorian
        let interval = HealthKitFetchEngine.intradayDaySampleInterval(calendar: calendar, anchor: nil)
        let capturedDaySampleSignatures = currentDaySampleSignatures()
        let capturedDaySampleRevisions = daySampleRevisions
        // Hourly cumulative buckets overlap on their own day and the merge has
        // no bucket dedupe, so restart at that day's midnight.
        let fetchStart = max(
            interval.start,
            calendar.startOfDay(
                for: HealthKitFetchEngine.incrementalFetchStart(
                    after: healthTrends.stepsDaySamples,
                    windowStart: interval.start
                )
            )
        )
        guard fetchStart < interval.end else {
            return
        }
        // A `nil` result is a failed query, not an empty day: keep the cached
        // series rather than merging an empty one over it.
        guard let samples = await withBackgroundQueryPool({
            await engine.fetchIntradayDaySamples(
                for: .steps,
                calendar: calendar,
                startDate: fetchStart,
                endDate: interval.end
            )
        }) else {
            return
        }

        guard await awaitRefreshSlotFree() else {
            return
        }
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              currentDaySampleSignatures() == capturedDaySampleSignatures else {
            return
        }

        var trends = healthTrends
        trends.stepsDaySamples = HealthKitFetchEngine.mergeIntradaySamples(
            existing: trends.stepsDaySamples,
            incoming: samples,
            windowStart: interval.start,
            refetchStart: fetchStart
        )
        guard !publishDaySamples(from: trends, successfulSeries: [.stepsDaySamples],
                                 capturedRevisions: capturedDaySampleRevisions).isEmpty else { return }
        persistDaySampleSidecar()
        await recomputeBodyRadar(on: Date(), calendar: calendar)
    }

    /// Phase 2 of the two-phase trend window (RefreshOptimizationPlan-02 P0-A).
    /// The refresh publishes a snapshot whose windowed leaves were queried over
    /// the user's own chart range and merged with the cached year; this refetches
    /// those leaves over the full year in the background, so a cached point that
    /// went stale (or was deleted) beyond the window still reconciles — just not
    /// on the refresh's clock. Fired, never awaited.
    private func startFullTrendWindowLoadIfNeeded(selection: BodyDashboardFetchSelection) {
        guard fullTrendWindowLoadTask == nil else {
            return
        }

        fullTrendWindowLoadTask = Task { [weak self] in
            await self?.loadFullTrendWindow(selection: selection)
            self?.fullTrendWindowLoadTask = nil
        }
    }

    private func loadFullTrendWindow(selection: BodyDashboardFetchSelection) async {
        let epoch = cacheEpoch
        // The refresh that fired this is still running; its own publish must
        // land first, and the fetch below must not spend interactive permits
        // alongside it.
        await awaitNextRefreshCompletion()
        guard !Task.isCancelled, HKHealthStore.isHealthDataAvailable() else {
            return
        }

        do {
            // Background fill: never worth a permission sheet.
            guard try await requestHealthKitAuthorization(allowPrompt: false) else {
                return
            }
        } catch {
            return
        }

        let calendar = Calendar.bodyGregorian
        reconcileDashboardCacheScope()
        let capturedSignature = currentPrimarySummarySignature()
        let capturedInputs = captureRefreshInputs()
        guard selection == capturedInputs.inputs.fetchSelection else { return }
        let queryRevision = await engine.queryContextRevision
        let capturedRevisions = trendInputRevisions
        let cachedTrends = healthTrends
        // `trendWindowDays: nil` — the whole year, no merge. Off the refresh
        // path, so it spends the background budget.
        let result = await withBackgroundQueryPool {
            await engine.fetchHealthTrends(
                calendar: calendar,
                cachedTrends: cachedTrends,
                selection: selection,
                trendWindowDays: nil
            )
        }

        // A refresh that started while the fetch was in flight owns the
        // dashboard: wait it out, then reject just the leaves whose input
        // revisions changed. A partial concurrent refresh must not let its
        // unchanged success timestamp admit an older value over a newer one.
        guard await awaitRefreshSlotFree() else {
            return
        }
        // Admit successful leaves independently; a failed comparison or sleep
        // vital cannot veto an unrelated primary repair.
        guard await engine.queryContextRevision == queryRevision,
              mayApplyRefreshInputs(capturedInputs),
              Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              currentPrimarySummarySignature() == capturedSignature else {
            return
        }

        // Atomic hand-off: the year-long series replace what phase 1 published,
        // and everything this fetch merely carried forward from the copy it
        // captured — day samples, Stress state, recorded readiness — stays as
        // the LIVE snapshot has it, because the Stress input load and the
        // history backfill mutate exactly those fields while this runs.
        healthTrends = Self.applyingFullWindowTrendSeries(from: result, to: healthTrends,
            capturedRevisions: capturedRevisions, currentRevisions: trendInputRevisions)
        if result.hadQueryFailure { completedDashboardFreshness = nil }
        let revision = dashboardDataRevision
        let committed = await updateHealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory,
            expectedDataRevision: revision
        )
        if !committed, mayApplyRefreshInputs(capturedInputs),
           Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) {
            // The scalar repairs are already admitted. Persist the LIVE state
            // if concurrent compute/input work superseded our derived copy.
            persistDashboardSnapshot()
        }
    }

    /// Copies the daily trend series phase 2 refetched onto the live snapshot.
    /// Deliberately leaf-by-leaf rather than wholesale: this is the set of
    /// rolling leaves `fetchHealthTrends` resolves, and every other field
    /// of a fetched snapshot is either carried forward from a now-stale captured
    /// copy or derived (Stress, readiness) by the recompute this feeds.
    static func applyingFullWindowTrendSeries(
        from result: HealthKitFetchEngine.HealthTrendFetchResult,
        to live: HealthTrendSnapshot,
        capturedRevisions: [HealthTrendReconciliationLeaf: Int],
        currentRevisions: [HealthTrendReconciliationLeaf: Int]
    ) -> HealthTrendSnapshot {
        var next = live
        for leaf in result.successfulLeaves
            where capturedRevisions[leaf, default: 0] == currentRevisions[leaf, default: 0] {
            leaf.copy(from: result.trends, to: &next, retainingFrom: result.retentionStart)
        }
        return next
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
        // Same rule as `requestAuthorizationAndRefresh`: only when a prompt can
        // actually appear.
        if intent == .userInitiated && authorizationState != .authorized {
            setRefreshStage(.authorizing)
        }

        let calendar = Calendar.bodyGregorian

        do {
            guard try await requestHealthKitAuthorization(allowPrompt: intent == .userInitiated) else {
                return
            }
            if intent == .userInitiated {
                // Scoped to the month being pulled, for the same reason as
                // `refreshRecentMonths`: this gesture reconciles the workouts on
                // screen, not the whole training-load window.
                await engine.clearWorkoutEffortCache(
                    scopedTo: [BodyWorkoutMonthKey(month: month, year: year)],
                    calendar: calendar
                )
            }
            // Clock starts after the authorization sheet, as above.
            await runRefreshWithDeadline {
                await self.refresh(
                    month: month,
                    year: year,
                    calendar: calendar,
                    updatesHealthSummary: false,
                    reusesCachedWorkoutHeartRate: intent == .passiveResume
                )
            }
        } catch {
            handleRefreshError(error)
        }
    }

    func updateHealthPermission(_ permission: BodyHealthPermission, isEnabled: Bool) async {
        let nextSelection = permissionSelection.setting(permission, isEnabled: isEnabled)
        guard nextSelection != permissionSelection else {
            return
        }

        pendingPermissionChangeCount += 1
        permissionSelection = nextSelection
        nextSelection.save()
        if permission == .workouts && !isEnabled {
            workoutJournalAdmission.invalidate()
            workoutJournalTask?.cancel()
        }
        contextRefreshIsUserInitiated = contextRefreshIsUserInitiated || isEnabled
        _ = captureRefreshInputs()
        // Once the selection changes, its privacy cleanup must finish even if
        // the Settings task is cancelled while waiting for the refresh slot.
        await Task { @MainActor in
            await self.finishHealthPermissionChange(permission, isEnabled: isEnabled)
        }.value
    }

    private func finishHealthPermissionChange(_ permission: BodyHealthPermission, isEnabled: Bool) async {
        defer {
            pendingPermissionChangeCount -= 1
            scheduleContextRefreshIfNeeded()
        }
        guard await awaitRefreshSlotFree() else { return }
        isRefreshing = true
        defer { finishRefresh() }
        // A later toggle may have changed the selection while this one waited.
        await engine.setPermissionSelection(permissionSelection)
        if permission == .workouts {
            detailCaches.clearAll()
        } else if permission == .heart {
            detailCaches.clearHeartScopedCaches()
        } else if permission == .workoutMetrics {
            detailCaches.clearWorkoutMetricsScopedCaches()
        }
        if !isEnabled {
            // The in-memory drop above leaves the persisted detail files intact, and
            // a hydration would seed them straight back. Strip the data at rest on
            // opt-out too, same rationale as `sanitizeWorkoutSnapshots`. Awaited on
            // the serial queue (like the clear-cache flow) so the opt-out only
            // completes once the strip has actually landed.
            // A Workouts opt-out wipes the record ledger too, so cancel the
            // baseline scan first — otherwise a suspended chunk re-persists the
            // ledger right after the delete.
            if permission == .workouts {
                await clearWorkoutJournal()
                await cancelRecordBaselineBackfill()
                publishRecordLedger(WorkoutRecordLedger())
                // The effort ledger is derived workout data too; the engine owns
                // both its memory copy and its file, and awaits the delete.
                await engine.clearWorkoutEffortCache()
            }
            await beforePermissionDiskStrip?()
            await withCheckedContinuation { continuation in
                Self.snapshotPersistQueue.async {
                    switch permission {
                    case .workouts:
                        WorkoutDetailSnapshotStore.deleteAll()
                        WorkoutRecordLedgerStore.deleteAll()
                    case .workoutMetrics:
                        WorkoutDetailSnapshotStore.stripWorkoutMetricsPayloads()
                    case .heart:
                        WorkoutDetailSnapshotStore.stripHeartRateRecovery()
                    default:
                        break
                    }
                    continuation.resume()
                }
            }
        }
        await applyPermissionSelectionToCachedData()

        if !isEnabled {
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
    ///
    /// Only the newest edit survives: each call cancels the pending one, so a
    /// wheel dragged across a dozen values queues a single refetch. Cancelling
    /// after the refetch has started is harmless, since `refreshHealthMetric`
    /// runs under the deadline runner and checks cancellation cooperatively.
    func metricWarningThresholdsDidChange(for metric: HealthMetricKind) {
        metricWarningThresholdRefreshTask?.cancel()
        metricWarningThresholdRefreshTask = Task { [weak self] in
            // `refreshHealthMetric` drops the call while a refresh is in flight;
            // wait it out like the source/permission mutators do.
            guard let self, await self.awaitRefreshSlotFree(), !Task.isCancelled else {
                return
            }
            await self.refreshHealthMetric(metric)
            // Only this task may clear the slot: a cancellation means a newer
            // edit already stored its own task here.
            if !Task.isCancelled {
                self.metricWarningThresholdRefreshTask = nil
            }
        }
    }

    /// Whether a warning-threshold edit still has a refetch queued.
    var hasPendingMetricWarningThresholdRefresh: Bool {
        metricWarningThresholdRefreshTask != nil
    }

    /// Records the warnings the user has just been shown on screen, so the
    /// background pass doesn't re-notify them later the same day.
    ///
    /// The store only sees the refresh's AGGREGATE `hadQueryFailure`, not the
    /// per-kind warning outcomes, so seeding is conservative: any leaf failure
    /// anywhere in the refresh means a published warning could be stale cache
    /// rather than a fresh read, and nothing is seeded. A missed seed only costs
    /// one duplicate notification; a wrong seed silences a real one.
    /// Fire-and-forget: the evaluator is an actor that can be busy inside its
    /// own (deadline-guarded) background pass, and the refresh must never park
    /// on it. The kinds are read on the main actor first so the detached task
    /// carries a value rather than reaching back into published state.
    private func seedMetricWarningNotificationLedger(hadQueryFailure: Bool, calendar: Calendar) {
        guard !hadQueryFailure else {
            return
        }

        let today = Date()
        let todaysEvents = healthSummary.metricWarnings.filter {
            calendar.isDate($0.startDate, inSameDayAs: today)
        }
        guard !todaysEvents.isEmpty else {
            return
        }

        let seedKinds = Dictionary(
            todaysEvents.map { ($0.kind, $0.startDate) },
            uniquingKeysWith: { first, _ in first }
        )
        Task.detached {
            await MetricWarningBackgroundEvaluator.shared.seed(kinds: seedKinds)
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
        // Read through `isProUnlocked` so every caller in a view `body` picks up the
        // observation dependency on the entitlement (see `proEntitlementGeneration`).
        guard isProUnlocked else {
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

        guard isProUnlocked,
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
        cacheSourceIdentities.removeAll()
        _ = captureRefreshInputs(intent: .userInitiated)
        await engine.setCombinesHealthDataSourcesByName(combines)

        await persistContextChange()
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
        _ = captureRefreshInputs(intent: .userInitiated)
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
        cacheSourceIdentities.removeAll()
        _ = captureRefreshInputs(intent: .userInitiated)
        await engine.setCustomHealthSourceGroups(groups)

        await persistContextChange()
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
        _ = captureRefreshInputs(intent: .userInitiated)
        await engine.setHealthDataSourceSelection(nextSelection)
        await engine.setSecondaryHealthDataSourceSelection(nextSecondarySelection)

        await persistContextChange()
    }

    /// Refetches the dashboard after a sleep-stage *display* preference changes
    /// (sub-minute / leading-trailing awake stages), which alters how sleep
    /// samples are grouped. Mirrors the source-change precedent: waits out any
    /// in-flight refresh first so the `isRefreshing` guard in
    /// `requestAuthorizationAndRefresh` doesn't silently drop the refetch (the
    /// bare `Task { requestAuthorizationAndRefresh() }` the Settings onChange used
    /// to fire was lost whenever it landed during a launch/resume refresh).
    func refetchAfterSleepDisplayPreferenceChange() async {
        _ = captureRefreshInputs(intent: .userInitiated)
        await persistContextChange()
    }

    func updateDefaultSecondaryHealthDataSource(option: BodyHealthDataSourceOption) async {
        let nextOption = option.id == healthDataSourceSelection.defaultOption.id ? .noComparison : option
        let nextSelection = secondaryHealthDataSourceSelection.settingDefault(option: nextOption)
        guard nextSelection != secondaryHealthDataSourceSelection else {
            return
        }

        secondaryHealthDataSourceSelection = nextSelection
        nextSelection.save()
        _ = captureRefreshInputs(intent: .userInitiated)
        await engine.setSecondaryHealthDataSourceSelection(nextSelection)

        await persistContextChange()
    }

    func updateHealthDataSource(for kind: HealthMetricKind, option: BodyHealthDataSourceOption) async {
        let nextSelection = healthDataSourceSelection.setting(kind, option: option)
        guard nextSelection != healthDataSourceSelection else {
            return
        }

        healthDataSourceSelection = nextSelection
        nextSelection.save()
        _ = captureRefreshInputs(intent: .userInitiated)
        await engine.setHealthDataSourceSelection(nextSelection)

        await persistContextChange()
    }

    func updateSecondaryHealthDataSource(for kind: HealthMetricKind, option: BodyHealthDataSourceOption) async {
        let nextSelection = secondaryHealthDataSourceSelection.setting(kind, option: option)
        guard nextSelection != secondaryHealthDataSourceSelection else {
            return
        }

        secondaryHealthDataSourceSelection = nextSelection
        nextSelection.save()
        _ = captureRefreshInputs(intent: .userInitiated)
        await engine.setSecondaryHealthDataSourceSelection(nextSelection)

        await persistContextChange()
    }

    private func persistContextChange() async {
        guard !Task.isCancelled else { return }
        await hydratePersistedDaySamplesIfNeeded()
        reconcileDashboardCacheScope()
        persistDaySampleSidecar()
        republishCompanionSnapshots()
        scheduleContextRefreshIfNeeded()
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
        reconcileDashboardCacheScope()
        let snapshotToSave = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
            )
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
        guard isProUnlocked,
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

    /// True until the app has been through its first Health load: no completed
    /// full refresh recorded by this or any prior session, no successful
    /// refresh timestamp, and nothing restored from the snapshot cache. The
    /// completion stamp is what releases a user whose denied read permissions
    /// make every refresh partial (and so never arm the TTL stamp) — without
    /// it they stay on "Try Again" forever. Presents the first-launch load
    /// overlay and keeps every
    /// passive load idle — the app-entry sync, the workout-month lazy loads,
    /// and older ring-history paging — so the first big load (including the
    /// ten-year activity-ring backfill) only runs when the user starts it
    /// from the overlay, a refresh gesture, or the Settings refresh button.
    var needsInitialHealthDataLoad: Bool {
        !hasCompletedInitialHealthDataLoad && lastSuccessfulRefreshDate == nil && !hasHealthDataToShow
    }

    /// Whether Health data actually landed: a non-empty dashboard. A completed
    /// first load that brought back nothing (denied or empty Health store)
    /// clears `needsInitialHealthDataLoad` — and may even arm the freshness
    /// TTL, since denials now read as clean absences — without making this
    /// true, so the onboarding outcome row can tell the two apart.
    var hasHealthDataToShow: Bool {
        !HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        ).isEmpty
    }

    /// The one-line status the Permissions sheet shows under each toggle.
    ///
    /// A pure read of already-published state: it dispatches no HealthKit query
    /// and starts no refresh, so opening the sheet costs nothing. The sheet
    /// evaluates this once when it appears rather than observing it, so the
    /// footers can't flicker while a refresh is in flight.
    func healthPermissionAccessStates(
        dashboardFetchSelection: BodyDashboardFetchSelection = .load()
    ) -> [BodyHealthPermission: BodyHealthPermissionAccessState] {
        let dashboard = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )

        return BodyHealthPermission.allCases.reduce(into: [:]) { states, permission in
            states[permission] = BodyHealthPermissionAccessState.resolve(
                permission: permission,
                selection: permissionSelection,
                isFetchedForDashboard: isFetchedForDashboard(permission, selection: dashboardFetchSelection),
                hasCompletedInitialLoad: hasCompletedInitialHealthDataLoad,
                isLoadInFlight: isHealthPermissionLoadInFlight(permission),
                presence: healthPermissionDataPresence(permission, in: dashboard)
            )
        }
    }

    /// The Stress-input kinds the dashboard refresh fetches itself (the engine's
    /// `.inputCapable` leaves), as opposed to the ones only the Stress input
    /// loader reads.
    private static let refreshFetchedStressInputKinds: Set<HealthMetricKind> = [
        .sleep,
        .heartRateVariability
    ]

    /// The categories the Stress input loader reads (HR/HRV day samples, the
    /// beat-to-beat series, and the coarse steps/energy movement mask).
    private static let stressInputLoadPermissions: Set<BodyHealthPermission> = [
        .heart,
        .steps,
        .energy
    ]

    /// Whether the current Home-card layout actually fetches this category.
    ///
    /// `BodyDashboardFetchSelection` is built from the selected Summary and Trend
    /// cards plus the starred metric, NOT from the permission selection, and a
    /// metric it excludes returns empty defaults without ever querying HealthKit.
    /// Absence there reflects the dashboard layout, not Apple Health, so a hidden
    /// card must never be reported as missing data.
    private func isFetchedForDashboard(
        _ permission: BodyHealthPermission,
        selection: BodyDashboardFetchSelection
    ) -> Bool {
        switch permission {
        case .activityRings:
            return selection.includesActivityRings
        case .workouts,
             .workoutMetrics,
             .dateOfBirth:
            // Fetched on the workout path, which the Home-card layout doesn't gate.
            return true
        default:
            return HealthMetricKind.allCases.contains {
                HealthKitFetchEngine.healthPermission(forMetric: $0) == permission
                    && isFetchedForDashboard($0, selection: selection)
            }
        }
    }

    /// A kind fetched only as a Stress input counts as fetched just when
    /// something will actually query it. The refresh itself still fetches the
    /// engine's `.inputCapable` leaves; the rest reach HealthKit only through
    /// the Stress input loader, which is heart-gated
    /// (`startStressInputLoadIfNeeded`) — with Heart off those are never read
    /// and the sheet must not claim they are.
    private func isFetchedForDashboard(
        _ kind: HealthMetricKind,
        selection: BodyDashboardFetchSelection
    ) -> Bool {
        if selection.includesFullPayload(kind) {
            return true
        }

        guard selection.isInputOnly(kind) else {
            return false
        }

        return Self.refreshFetchedStressInputKinds.contains(kind) || permissionSelection.includes(.heart)
    }

    /// Whether Body currently holds data for this category.
    private func healthPermissionDataPresence(
        _ permission: BodyHealthPermission,
        in dashboard: HealthDashboardSnapshot
    ) -> BodyHealthPermissionDataPresence {
        switch permission {
        case .dateOfBirth:
            // A characteristic read that anchors workout HR zones. It never lands
            // in the dashboard snapshot, so answering would need a fresh read.
            return .unobservable
        case .workouts:
            return monthSnapshots.values.contains { $0.workoutCount > 0 } ? .present : .absent
        case .workoutMetrics:
            // Not "read on demand": the monthly refresh eagerly fills these
            // summary fields when the permission is on, so they're real evidence.
            return hasCachedWorkoutMetrics ? .present : .absent
        default:
            // Filter the dashboard down to THIS permission, then ask the
            // snapshot's own `isEmpty`.
            //
            // Deliberately NOT a diff of filtered-with against filtered-without:
            // that measures "the filter changed something", which is a different
            // question and claims data where there is none. Ring
            // `loadedMonthKeys` survive months that hold no days, and
            // `cardioFitnessProfile` carries age and sex with no VO₂ max reading.
            // `isEmpty` already excludes exactly that metadata, and compares
            // against nil rather than by float equality, so NaN never arises.
            var onlyThisPermission = dashboard.filteredWithoutReadinessRecompute(
                by: BodyHealthPermissionSelection(enabledPermissions: [permission])
            )
            // Readiness is DERIVED and survives every permission filter (no
            // `filtered(by:)` branch clears it, on purpose — it's recomputed,
            // not category data), yet both `isEmpty`s count it. Left in, one
            // cached readiness score would make every category read as having
            // data. Strip it before asking.
            onlyThisPermission.summary.readiness = .unavailable
            onlyThisPermission.trends.readiness = .empty
            onlyThisPermission.trends.recordedReadiness = []
            return onlyThisPermission.isEmpty ? .absent : .present
        }
    }

    private var hasCachedWorkoutMetrics: Bool {
        monthSnapshots.values.contains { snapshot in
            snapshot.days.contains { day in
                day.workouts.contains { workout in
                    workout.averagePowerWatts != nil
                        || workout.averageStepCadenceSPM != nil
                        || workout.averageCyclingCadenceRPM != nil
                        || workout.swimmingStrokeCount != nil
                        || workout.cardioFitnessVO2Max != nil
                }
            }
        }
    }

    /// Ring history is started as a deliberately unjoined task that lands only
    /// after the refresh completes, so a status read taken right after a toggle
    /// would catch `.activityRings` empty and then sit on that until the sheet is
    /// reopened. Report it as still checking instead. Three signals feed this:
    /// `isRefreshing` (any in-flight refresh), `loadingActivityRingMonthKeys`
    /// (detail-page pagination), and `activityRingHistoryTask` (the unjoined
    /// background backfill, which can still be running after `isRefreshing`
    /// has already gone false).
    private func isHealthPermissionLoadInFlight(_ permission: BodyHealthPermission) -> Bool {
        if isRefreshing {
            return true
        }

        // Same shape for the Stress input loader: it also lands after the refresh
        // completes, so the categories it fills are still being checked rather
        // than missing.
        if stressInputLoadTask != nil, Self.stressInputLoadPermissions.contains(permission) {
            return true
        }

        guard permission == .activityRings else {
            return false
        }
        return !loadingActivityRingMonthKeys.isEmpty || activityRingHistoryTask != nil
    }

    /// Invalidates the per-workout detail caches the moment the app leaves the
    /// foreground, since HealthKit read access can only change while Body isn't
    /// in the foreground (the Health app or Settings toggle) and the SDK reports
    /// no signal for that change on return.
    ///
    /// The clear is eager rather than deferred to the next authorization pass
    /// because the detail loaders serve these caches directly and a resume can
    /// skip that pass entirely (debounced, refresh already running, initial load
    /// pending), which would keep showing a cached positive or a cached absence
    /// captured under the previous grant.
    @MainActor
    func noteAppDidEnterBackground() {
        detailCaches.clearAll()
        // Clearing memory isn't enough: the persisted detail files hold positives
        // written under the previous grant, so the disk seed stays bypassed until
        // an authorized pass has re-read HealthKit.
        bypassesPersistedDetailSeeding = true
    }

    func syncWhenAppBecomesActive(date: Date = Date()) async {
        defer { scheduleWorkoutJournalIfNeeded() }
        _ = captureRefreshInputs()
        if needsContextRefresh {
            scheduleContextRefreshIfNeeded()
            return
        }
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

        // The dashboard keeps its current-month scope. The visible Workouts
        // page separately revalidates expired chart/selected months; loaded
        // history is not treated as immutable.
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

    private var monthValidationContext: String {
        let calendar = Calendar.bodyGregorian
        return "month-v1|\(permissionSelection.rawValue)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
    }

    func hasFreshSnapshot(month: Int, year: Int, date: Date = Date()) -> Bool {
        let key = BodyWorkoutMonthKey(month: month, year: year)
        return loadedMonthKeys.contains(key)
            && monthSnapshots[key]?.isValidated(now: date, context: monthValidationContext) == true
    }

    /// Whether a month can be shown straight from cache while it refreshes in
    /// the background. Non-empty on purpose: `clearWorkoutSnapshots` leaves
    /// empty snapshots in memory and the opt-out path writes emptied files, so
    /// mere membership would navigate instantly to "No workouts" and then pop
    /// the workouts in once the fetch lands.
    func hasCachedWorkouts(month: Int, year: Int) -> Bool {
        (monthSnapshots[BodyWorkoutMonthKey(month: month, year: year)]?.workoutCount ?? 0) > 0
    }

    /// Workouts in the half-open 30 days before `workout` (excluding it) — same-type
    /// only by default, all types when `matchingTypeOnly` is false (the effort
    /// estimator prefers same-type but falls back across types) — read only from
    /// already-loaded snapshots. Pure — no fetch, no `Task` — so it is safe to call
    /// from a SwiftUI computed property. `isComplete` uses `loadedMonthKeys` (the true
    /// load signal), not `monthSnapshots` membership, which is seeded from the
    /// persisted month files at launch and left populated after `clearWorkoutSnapshots`.
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
            // Automatic preload behind the detail sheet: defer if it would prompt.
            await loadMonthIfNeeded(month: key.month, year: key.year, allowPrompt: false)
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
        guard !needsInitialHealthDataLoad else {
            return
        }
        guard await awaitRefreshSlotFree() else { return }

        let requestedKeys = Self.recentMonthKeys(
            count: Self.recentChartMonthCount,
            from: date,
            calendar: .bodyGregorian
        )
        let missingKeys = Set(requestedKeys.filter {
            !hasFreshSnapshot(month: $0.month, year: $0.year)
        }).subtracting(loadingMonthKeys)

        guard !missingKeys.isEmpty else {
            return
        }

        // The Workouts tab's own `.task` preload — never worth a sheet.
        await loadMonthKeysIfNeeded(missingKeys, allowPrompt: false)
    }

    @discardableResult
    func loadMonthIfNeeded(month: Int, year: Int, allowPrompt: Bool = true) async -> Bool {
        guard !needsInitialHealthDataLoad else {
            return false
        }

        let key = BodyWorkoutMonthKey(month: month, year: year)
        guard !hasFreshSnapshot(month: month, year: year) else {
            return true
        }

        await awaitNextRefreshCompletion()

        guard !hasFreshSnapshot(month: month, year: year) else {
            return true
        }

        await awaitMonthLoadCompletion(for: key)

        guard !hasFreshSnapshot(month: month, year: year) else {
            return true
        }

        await loadMonthKeysIfNeeded([key], allowPrompt: allowPrompt)
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

        let pendingRepairMonthKeys = pendingActivityRingRepairMonthKeys
        guard !Task.isCancelled, loadingActivityRingMonthKeys.isEmpty,
              hasMoreActivityRingHistory || !pendingRepairMonthKeys.isEmpty else {
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

        let repairCandidates = Array(pendingRepairMonthKeys.reversed().prefix(3))
        let candidates = repairCandidates.isEmpty ? Self.previousActivityRingMonthCandidates(
            loadedKeys: loadedActivityRingMonthKeys,
            exhaustedKeys: exhaustedActivityRingMonthKeys,
            limit: 3,
            date: date,
            calendar: calendar
        ) : repairCandidates
        guard !candidates.isEmpty else {
            return
        }

        do {
            // Scroll-driven pagination: defer rather than prompt.
            guard try await requestHealthKitAuthorization(allowPrompt: false) else {
                return
            }

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

                if !repairCandidates.isEmpty {
                    // Even an empty successful month is authoritative repair.
                    // Failed reads above cannot advance this coverage or retire
                    // archived values. At most three months per pagination pass.
                    guard applyActivityRingArchiveRepair(previousHistory, capturedEpoch: epoch, calendar: calendar) else { return }
                    mergedHistory = activityRingHistory
                    // Repair candidates need not be adjacent. They never enter
                    // the ordinary pagination gap accumulator or its merge.
                    continue
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
            let persistenceMetadata = currentDashboardPersistenceMetadata()
            let daySampleWriteIntent = authoritativeDaySampleSeries
            let token = dashboardPublicationToken
            Self.snapshotPersistQueue.async {
                guard token.isValid else { return }
                HealthDashboardSnapshotStore.saveWithOutcome(
                    snapshotToSave,
                    daySampleSignatures: daySampleSignatures,
                    summaryContextSignature: summaryContextSignature,
                    metadata: persistenceMetadata,
                    authoritativeDaySampleSeries: daySampleWriteIntent
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
            noteActivityRingHistoryExhausted()
            return nil
        case .failed:
            return nil
        }
    }

    func noteActivityRingHistoryExhausted() {
        hasMoreActivityRingHistory = false
    }

    var hasWorkoutJournalWork: Bool { workoutJournalTask != nil }

    /// Runs only after foreground publication. No observer/background delivery;
    /// query-derived refreshes remain authoritative while journal repair is pending.
    func scheduleWorkoutJournalIfNeeded() {
        guard let file = workoutJournalFile, workoutJournalTask == nil,
              recordBackfillTask == nil, !isRefreshing, !isClearingCache,
              !needsContextRefresh, pendingPermissionChangeCount == 0,
              permissionSelection.includes(.workouts), authorizationState == .authorized else { return }
        let admission = HealthDashboardPublicationToken()
        workoutJournalAdmission = admission
        workoutJournalTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.workoutJournalTask = nil
                self.scheduleRecordBaselineBackfillIfNeeded()
                self.scheduleStressBackfillIfNeeded()
            }
            let inputs = self.captureRefreshInputs()
            let epoch = self.cacheEpoch
            let engine = self.engine
            if self.workoutJournal == nil {
                let owner = await Task.detached(priority: .utility) {
                    WorkoutJournalReconciler(engine: engine, file: file)
                }.value
                guard admission.isValid, !Task.isCancelled, epoch == self.cacheEpoch,
                      self.mayApplyRefreshInputs(inputs) else { return }
                self.workoutJournal = owner
            }
            guard let owner = self.workoutJournal else { return }
            var journal = await owner.snapshot()
            // Finish durable repairs before draining another delta generation.
            // Full/periodic HealthKit queries remain active while repair is pending.
            if !journal.bootstrapComplete || (!journal.requiresFullRepair && journal.dirtyIntervals.isEmpty) {
                guard await owner.scan() == .caughtUp else { return }
                journal = await owner.snapshot()
            }
            guard journal.bootstrapComplete, journal.requiresFullRepair || !journal.dirtyIntervals.isEmpty,
                  admission.isValid, !Task.isCancelled, epoch == self.cacheEpoch,
                  self.mayApplyRefreshInputs(inputs), !self.isRefreshing, !self.isClearingCache else { return }
            self.isRefreshing = true
            _ = await self.runRefreshWithDeadline {
                await withBackgroundQueryPool {
                    await self.repairWorkoutJournal(journal, owner: owner, admission: admission)
                }
            }
            admission.invalidate()
            self.finishRefresh()
        }
    }

    // Internal for deterministic fake-store repair tests; lifecycle owns the slot.
    func repairWorkoutJournal(_ captured: WorkoutChangeJournal, owner: WorkoutJournalReconciler,
                                      admission: HealthDashboardPublicationToken) async {
        let inputs = captureRefreshInputs()
        let token = dashboardPublicationToken
        let calendar = Calendar.bodyGregorian
        let date = Date()
        var scope = currentDashboardCacheScope()
        scope.summaryDayStart = nil // Completed month repairs survive midnight.
        let context = HealthDashboardCacheScope.key(["journal-repair-v1", scope.signature, monthValidationContext])
        guard let plan = WorkoutJournalRepairPlan(journal: captured, retainedMonths: Set(monthSnapshots.keys),
                                                  date: date, calendar: calendar) else { return }
        var journal = captured
        var progress = journal.repairProgress?.context == context
            ? journal.repairProgress! : WorkoutJournalRepairProgress(context: context)
        func mayCommit() -> Bool {
            admission.isValid && token.isValid && !Task.isCancelled && mayApplyRefreshResults
                && mayApplyRefreshInputs(inputs)
        }
        guard mayCommit() else { return }
        // Known dirty data remains visible as cached data, but may not use its
        // old validation to skip a detail/month repair or publish a compute seed.
        lastSuccessfulRefreshDate = nil
        completedDashboardFreshness = nil
        lastVitalsRefreshDate = nil
        cachedComputeTrainingLoadSeed = nil
        mutateMonthSnapshots { snapshots in
            for key in plan.months where !progress.completedMonths.contains(WorkoutJournalRepairPlan.identity(key)) {
                guard let old = snapshots[key] else { continue }
                snapshots[key] = WorkoutMonthSnapshot(month: old.month, year: old.year,
                    generatedAt: old.generatedAt, days: old.days, schemaVersion: old.schemaVersion)
            }
        }
        persistDashboardSnapshot()
        if !progress.detailsInvalidated {
            // Fence older detail loads before clearing memory and draining disk
            // invalidations behind already queued detail saves.
            // New detail opens during that drain must not rehydrate the old file.
            // Reuse the same session-long live-read gate as a background resume.
            bypassesPersistedDetailSeeding = true
            cacheEpoch &+= 1
            detailCaches.clearAll()
            let ids: Set<UUID>? = journal.requiresFullRepair ? nil : Set(journal.dirtyIntervals.keys.compactMap(UUID.init(uuidString:)))
            let invalidated = await withCheckedContinuation { continuation in
                Self.snapshotPersistQueue.async {
                    guard token.isValid else { continuation.resume(returning: false); return }
                    continuation.resume(returning: WorkoutDetailSnapshotStore.invalidateForJournal(ids: ids))
                }
            }
            guard invalidated, mayCommit() else { return }
            progress.detailsInvalidated = true
            guard await owner.checkpointRepair(progress, generation: journal.generation,
                revision: journal.revision, admission: token), mayCommit() else { return }
            journal = await owner.snapshot()
        }
        if journal.requiresFullRepair && !progress.baselineInvalidated {
            // The old baseline cannot prove absence for an unmapped deletion.
            // Only the rebuildable record artifact is reset; month/history files
            // remain intact, and the existing baseline scan rebuilds the ledger.
            publishRecordLedger(WorkoutRecordLedger())
            guard await persistWorkoutJournalRecordLedger(), mayCommit() else { return }
            progress.baselineInvalidated = true
            guard await owner.checkpointRepair(progress, generation: journal.generation,
                revision: journal.revision, admission: token), mayCommit() else { return }
            journal = await owner.snapshot()
        }
        let pending = plan.months.filter { !progress.completedMonths.contains(WorkoutJournalRepairPlan.identity($0)) }
        let eligible = pending.filter { progress.mayAttemptMonth(WorkoutJournalRepairPlan.identity($0), at: date) }
        for key in eligible.prefix(3) {
            guard mayCommit() else { return }
            let identity = WorkoutJournalRepairPlan.identity(key)
            // Persist BEFORE fetching: a deadline/process exit still backs off,
            // but never marks the month complete or retires its dirty interval.
            progress.beginMonthAttempt(identity, at: Date())
            guard await owner.checkpointRepair(progress, generation: journal.generation,
                revision: journal.revision, admission: token), mayCommit() else { return }
            journal = await owner.snapshot()
            await engine.clearWorkoutEffortCache(scopedTo: [key], calendar: calendar, now: date)
            guard mayCommit() else { return }
            let started = Date()
            do { try await refresh(monthKeys: [key], calendar: calendar, reusesCachedWorkoutHeartRate: false) }
            catch {
                guard mayCommit() else { return }
                continue
            }
            guard mayCommit() else { return }
            guard let month = monthSnapshots[key], let validatedAt = month.validatedAt,
                  validatedAt >= started, validatedAt <= Date(), month.validationContext == monthValidationContext else { continue }
            // Both the month and its record fold must be durable before the
            // checkpoint can skip it after a crash. Bool save results alone
            // cannot distinguish unchanged bytes from a failed write.
            guard await persistWorkoutJournalMonth(month), mayCommit(),
                  await persistWorkoutJournalRecordLedger(), mayCommit() else { return }
            progress.completeMonth(identity)
            guard await owner.checkpointRepair(progress, generation: journal.generation,
                revision: journal.revision, admission: token), mayCommit() else { return }
            journal = await owner.snapshot()
        }
        guard mayCommit(), plan.months.allSatisfy({ progress.completedMonths.contains(WorkoutJournalRepairPlan.identity($0)) }),
              !journal.requiresFullRepair || recordLedger.baselineComplete else { return }
        // Existing query-derived dashboard/Training Load/readiness and watch-seed
        // paths remain the only authority. A caught-up anchor is never freshness.
        let refreshedAt = Date()
        await refreshRecentMonths(date: refreshedAt, intent: .passiveResume, forcesFullTrendWindow: true)
        guard mayCommit(), completedDashboardFreshness?.date == refreshedAt else { return }
        let durable = await withCheckedContinuation { continuation in
            persistDashboardSnapshot { continuation.resume(returning: $0) }
        }
        guard durable, mayCommit(), await persistWorkoutJournalRecordLedger(), mayCommit() else { return }
        _ = await owner.acknowledgeDurableRepair(generation: journal.generation, revision: journal.revision, admission: token)
    }

    func persistWorkoutJournalMonth(_ month: WorkoutMonthSnapshot) async -> Bool {
        let directory = Self.testSnapshotDirectoryURLOverride ?? WorkoutSnapshotStore.monthSnapshotsDirectoryURL
        let token = dashboardPublicationToken
        return await withCheckedContinuation { continuation in
            Self.snapshotPersistQueue.async {
                guard token.isValid else { continuation.resume(returning: false); return }
                let file = WorkoutSnapshotStore.fileURL(month: month.month, year: month.year, directoryURL: directory)
                WorkoutSnapshotStore.save(month, fileURL: file)
                let saved = WorkoutSnapshotStore.load(fileURL: file)
                continuation.resume(returning: saved?.month == month.month && saved?.year == month.year
                    && saved?.days == month.days && saved?.validatedAt == month.validatedAt
                    && saved?.validationContext == month.validationContext && saved?.schemaVersion == month.schemaVersion)
            }
        }
    }

    private func persistWorkoutJournalRecordLedger() async -> Bool {
        let ledger = recordLedger
        let revision = recordLedgerRevision
        let token = dashboardPublicationToken
        let durable = await withCheckedContinuation { continuation in
            Self.snapshotPersistQueue.async {
                guard token.isValid else { continuation.resume(returning: false); return }
                WorkoutRecordLedgerStore.save(ledger)
                let saved = WorkoutRecordLedgerStore.load()
                continuation.resume(returning: saved?.contributions == ledger.contributions
                    && saved?.baselineComplete == ledger.baselineComplete && saved?.scannedThrough == ledger.scannedThrough
                    && saved?.historicalRepair == ledger.historicalRepair && saved?.schemaVersion == ledger.schemaVersion)
            }
        }
        return durable && token.isValid && revision == recordLedgerRevision
    }

    /// Cancels without joining a possibly stuck query. The actor fences its page
    /// commits before deleting; the store token fences construction and repair.
    private func clearWorkoutJournal() async {
        workoutJournalAdmission.invalidate()
        workoutJournalTask?.cancel()
        if let owner = workoutJournal {
            do { try await owner.clear() }
            catch { healthDataNotice = String(localized: "Some cached workout changes could not be removed. Try clearing the cache again.") }
            workoutJournal = nil
        } else if let file = workoutJournalFile ?? WorkoutChangeJournalStore.defaultFile {
            // Also handles clear/opt-out before the first lazy construction.
            let removed = await Task.detached(priority: .utility) {
                do {
                    if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                    return true
                } catch { return false }
            }.value
            if !removed { healthDataNotice = String(localized: "Some cached workout changes could not be removed. Try clearing the cache again.") }
        }
    }

    func clearLocalCache(date: Date = Date()) async {
        // Don't clear on top of an in-flight refresh (which would resurrect what
        // we wipe) or a wipe already running.
        guard !isRefreshing, !isClearingCache else {
            return
        }
        isClearingCache = true
        defer { isClearingCache = false }
        contextRefreshGeneration &+= 1
        contextRefreshTask?.cancel()
        contextRefreshTask = nil
        needsContextRefresh = false
        contextRefreshRequiresFetch = false
        contextRefreshIsUserInitiated = false
        dashboardPublicationToken.invalidate()
        dashboardPublicationToken = HealthDashboardPublicationToken()
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
        setMonthSnapshots([key: emptySnapshot])
        // Per-workout detail caches keyed by workout UUID — the workouts they
        // describe are being wiped, so leaving them would serve routes, splits,
        // series and recovery for workouts the app no longer has (M73).
        detailCaches.clearAll()
        // The ledger describes workouts this clear is wiping; an emptied ledger
        // also re-arms the baseline scan for the next refresh.
        recordLedger = WorkoutRecordLedger()
        healthSummary = .empty
        // Drop the summary-reuse signature so a post-clear failed leaf resolves
        // to empty rather than reusing anything against the wiped summary.
        healthSummaryPrimarySignature = nil
        healthTrends = .empty
        activityRingHistory = .empty
        authoritativeDaySampleSeries.removeAll()
        for field in HealthDaySampleSeries.allCases { daySampleRevisions[field, default: 0] &+= 1 }
        loadedMonthKeys.removeAll()
        monthLoadOrder = [key]
        loadedActivityRingMonthKeys.removeAll()
        exhaustedActivityRingMonthKeys.removeAll()
        hasMoreActivityRingHistory = true
        loadingMonthKeys.removeAll()
        loadingActivityRingMonthKeys.removeAll()
        // The epoch bump above already stops the out-of-band ring load from
        // republishing; cancelling saves it from finishing a ten-year walk whose
        // result is now guaranteed to be dropped. The handle clears itself when
        // that task returns, so no new one starts on top of it.
        activityRingHistoryTask?.cancel()
        healthDataSourceOptionsByKind = [:]
        customSourceIDsWithDataByKind = [:]
        persistedDaySamplesHydration = nil
        lastSuccessfulRefreshDate = nil
        completedDashboardFreshness = nil
        activityRingBackfillState = .pending(resumeFrom: nil)
        ringHistoricalRepair = nil
        // A tombstoned install is back to first launch, so the load overlay
        // must present again.
        hasCompletedInitialHealthDataLoad = false
        HealthDashboardSnapshotStore.clearInitialHealthDataLoadCompleted()
        // Drop the compute-seed watermark + cached Training Load piece too — a
        // tombstoned install must not re-attach a stale seed (built from data
        // this clear just wiped) on the next publish. `dataThrough` (from
        // `lastVitalsRefreshDate`) is what gates whether `publishWatchSnapshot`
        // sends a seed at all, so this also makes the very next publish
        // correctly send none until a fresh full refresh lands.
        lastVitalsRefreshDate = nil
        lastReadinessComputeDate = nil
        lastTrainingLoadComputeDate = nil
        lastWorkoutsRefreshDate = nil
        HealthDashboardSnapshotStore.clearLastWorkoutsWeekCoverageDate()
        lastMetricPullDates = [:]
        cachedComputeTrainingLoadSeed = nil
        cachedExpectedSourceIDsByKind = [:]
        authorizationState = .unknown
        healthDataNotice = String(localized: "Local cache cleared. Refresh to load Apple Health data again.")
        // Drop the generated readiness comment too — it describes the summary
        // this clear just wiped, and would otherwise reappear on relaunch.
        ReadinessCommentCache.clear()

        // Cancel and AWAIT the baseline record scan before the file deletions
        // below. The epoch bump already stops it republishing, but the scan owns
        // a persist enqueue of its own — awaiting its exit is what guarantees no
        // ledger write is still queued behind the delete.
        await cancelRecordBaselineBackfill()
        // Same barrier for the Stress history walk: it owns a snapshot persist
        // enqueue of its own, which must not land behind the delete below.
        await cancelStressBackfill()
        await clearWorkoutJournal()

        // Await the engine cache clears (previously fire-and-forget) so a refresh
        // started right after this can't race a half-cleared source/effort cache.
        // The effort clear owns its persisted ledger and awaits that delete on
        // its own persist queue, so no queued effort save survives the wipe.
        await engine.clearSourceCache()
        await engine.clearWorkoutEffortCache()

        // Enqueue the file deletions on the serial persist queue so they land
        // AFTER any snapshot save already queued (FIFO), and await that barrier:
        // `isClearingCache` stays true — and the disk size / widget reload are
        // only recomputed — once the on-disk caches are actually gone, so an
        // earlier in-flight save can't resurrect a file after the wipe.
        let snapshotDirectoryURL = Self.testSnapshotDirectoryURLOverride ?? WorkoutSnapshotStore.monthSnapshotsDirectoryURL
        await withCheckedContinuation { continuation in
            Self.snapshotPersistQueue.async {
                WorkoutSnapshotStore.deleteAll(directoryURL: snapshotDirectoryURL)
                HealthDashboardSnapshotStore.delete()
                HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
                HealthDashboardSnapshotStore.clearWatchExpectedSourceIDs()
                HealthDashboardSnapshotStore.clearWatchTrainingLoadSeed()
                HealthDashboardSnapshotStore.clearActivityRingBackfillState()
                HealthWidgetSnapshotStore.delete()
                WorkoutDetailSnapshotStore.deleteAll()
                WorkoutRecordLedgerStore.deleteAll()
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
    func refreshRecentMonths(date: Date = Date(), intent: BodyWorkoutRefreshIntent = .userInitiated,
                             forcesFullTrendWindow: Bool = false) async {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("RefreshRecentMonths")
        defer { BodyPerformanceSignposts.signposter.endInterval("RefreshRecentMonths", signpostState) }
        // Measurement only (RefreshOptimizationPlan-02 §6): starts the per-leaf
        // table `finishRefresh()` dumps in DEBUG builds.
        BodyRefreshProfile.shared.beginRefresh()

        setRefreshStage(.fetching)
        await hydratePersistedDaySamplesIfNeeded()
        await engine.setHealthTrendAnchorDate(date)

        let calendar = Calendar.bodyGregorian
        // On a passive resume only the current month refreshes. But when the
        // current wake cycle reaches back into the prior month (an evening
        // workout carried past midnight on the 1st), also refresh that month so
        // the activity drain reads fresh prior-month workouts rather than stale,
        // un-refreshed ones.
        let wakeCycleSleepEnd = healthSummary.sleep.stageSnapshot.wakeCycleEnd
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

        // Explicit refreshes reconcile what the user is looking at: drop the
        // per-workout effort cache for the months this refresh is about to fetch
        // (plus anything too young to be confirmed), so a re-rated workout in a
        // displayed month re-queries. The aged entries for the rest of the
        // 408-day training-load window are kept — re-asking effort for ~300
        // immutable workouts is the bulk of a pull-to-refresh. A score edited in
        // Apple Fitness on an older workout converges when its month is
        // displayed, or via Clear Cache in Settings.
        if intent == .userInitiated {
            await engine.clearWorkoutEffortCache(scopedTo: Array(keys), calendar: calendar, now: date)
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

        // The dashboard publish, the readiness reapply, and the stress recompute
        // below each used to encode and write the whole snapshot; this path
        // defers all three to one write once the tail has settled. `persistEpoch`
        // keeps a Clear Cache that landed mid-refresh from being written back,
        // and a pass abandoned at the deadline persists what it had published
        // through `persistPublishedDashboardSnapshot` instead.
        let persistEpoch = cacheEpoch
        var publishedDashboard = false
        var completedFullRefresh = false

        do {
            // Source discovery must finish before any dashboard query — the
            // per-source predicate reads `healthSourcesByKind`, so racing it
            // would silently fetch all-source data for custom-source users.
            await fetchHealthDataSourceOptions(calendar: calendar, force: intent == .userInitiated)

            let (fetchedHealthSummary, fetchedHealthTrends, hadQueryFailure, fetchedPartialTrendWindow) =
                try await fetchDashboardSnapshotProgressively(
                    calendar: calendar,
                    selection: dashboardFetchSelection,
                    forcesFullTrendWindow: forcesFullTrendWindow
                )

            // Ring history is whatever the out-of-band ring load has published
            // so far; passing the live value keeps the save from dropping the
            // months already merged into it.
            // The stress recompute is skipped here and run once in the tail
            // below: its activity mask needs the workouts this fetch is still
            // racing, so the pass done here would be thrown away.
            guard await updateHealthDashboardSnapshot(
                summary: fetchedHealthSummary,
                trends: fetchedHealthTrends,
                activityRingHistory: activityRingHistory,
                recomputesStress: false,
                recomputesBodyRadar: false,
                persists: false
            ) else { throw CancellationError() }
            publishedDashboard = true

            // Join the workout fetch. Its success gates the freshness timestamp:
            // a workout failure must re-run the full refresh on the next
            // activation instead of being skipped by the 5-minute warm-resume
            // shortcut, so don't `markRefreshSucceeded` unless workouts landed.
            try await workoutRefresh
            // Everything past the join publishes, persists, or writes back to
            // HealthKit (`autoApplyPredictedEffortIfNeeded`). An abandoned
            // refresh's workout fetch can land here minutes late, so it stops
            // at the generation check instead.
            guard mayApplyRefreshResults else {
                throw CancellationError()
            }
            authorizationState = .authorized
            // Dashboard vitals + workouts have both just landed together (this
            // path always refreshes the dashboard) — the one point to refresh
            // the phone→watch compute seed's Training Load piece under the
            // SAME engine anchor date the dashboard fetch used. Gated on
            // `!hadQueryFailure` exactly like `lastVitalsRefreshDate` below, so
            // the two can't drift out of lockstep.
            setRefreshStage(.computing)
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
            seedMetricWarningNotificationLedger(hadQueryFailure: hadQueryFailure, calendar: calendar)
            persistRecentMonthSnapshots(date: date, calendar: calendar)
            await reapplyActivityReadinessAfterWorkouts(date: date, calendar: calendar, persists: false)
            // Same ordering fix, for Stress's activity mask.
            await recomputeStress(on: date, calendar: calendar, persists: false)
            await recomputeBodyRadar(on: date, calendar: calendar, persists: false)
            publishWatchSnapshot()
            startStressInputLoadIfNeeded()
            startBodyRadarStepLoadIfNeeded()
            // Phase 2 of the two-phase trend window, and only when phase 1
            // actually fetched a short one. Fired, never awaited: it parks on
            // this refresh finishing before it queries anything.
            if fetchedPartialTrendWindow {
                startFullTrendWindowLoadIfNeeded(selection: dashboardFetchSelection)
            }
            updateHealthDataNotice()
            // Workouts + dashboard have both committed here, so resting-HR / readiness
            // inputs are current for the estimator.
            await autoApplyPredictedEffortIfNeeded(monthKeys: Array(keys))
            setRefreshStage(.finishing)
            completedFullRefresh = !hadQueryFailure
        } catch {
            handleRefreshError(error)
        }
        // The single dashboard write for this pass, deferred from the publish
        // and the tail above. Runs on the failure path too — a workout fetch
        // that threw still leaves freshly published dashboard state that has to
        // become durable. Skipped when the publish never happened, when a newer
        // refresh (or the deadline) has taken over, or when a Clear Cache landed
        // mid-pass and this would write the wiped state back.
        if publishedDashboard,
           mayApplyRefreshResults,
           Self.mayApplyLoad(capturedEpoch: persistEpoch, currentEpoch: cacheEpoch) {
            if completedFullRefresh {
                stageCompletedDashboardFreshness(date: date)
            }
            persistDashboardSnapshot()
            saveHealthWidgetSnapshot()
        }
        // A body abandoned at the refresh deadline must not clear the anchor a
        // NEWER refresh has since set; that path resets it itself.
        if ownsRefreshGeneration {
            await engine.setHealthTrendAnchorDate(nil)
        }
    }

    /// Expects the caller to have set `isRefreshing` (and to call
    /// `finishRefresh()` when done) before the first suspension.
    func refresh(
        month: Int,
        year: Int,
        calendar: Calendar,
        updatesHealthSummary: Bool,
        reusesCachedWorkoutHeartRate: Bool = false
    ) async {
        let refreshDate = Date()
        // Hydrate on BOTH paths, not just the dashboard one. The warm
        // workout-only resume can still reach a snapshot save via
        // `reapplyActivityReadinessAfterWorkouts`, and hydration is still what
        // carries the current samples into that save: `save` now refuses to
        // replace a populated sidecar with an all-empty payload, but a
        // partially populated pre-hydration payload (some series still empty)
        // still overwrites those series on disk. So a relaunch inside the
        // 5-minute TTL that picked up a new workout could otherwise still
        // narrow the intraday cache instead of leaving it untouched.
        setRefreshStage(.fetching)
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
        var fetchedPartialTrendWindow = false
        let dashboardFetchSelection = BodyDashboardFetchSelection.load()
        do {
            if updatesHealthSummary {
                await fetchHealthDataSourceOptions(calendar: calendar, force: true)

                let (fetchedHealthSummary, fetchedHealthTrends, leafFailure, partialTrendWindow) =
                    try await fetchDashboardSnapshotProgressively(
                        calendar: calendar,
                        selection: dashboardFetchSelection
                    )
                hadQueryFailure = leafFailure
                fetchedPartialTrendWindow = partialTrendWindow

                // Live ring history, for the reason in `refreshRecentMonths`.
                guard await updateHealthDashboardSnapshot(
                    summary: fetchedHealthSummary,
                    trends: fetchedHealthTrends,
                    activityRingHistory: activityRingHistory
                ) else { throw CancellationError() }
            }
            try await workoutRefresh
            // Same deadline rule as `refreshRecentMonths`: nothing past the
            // join may publish, persist, or write back for an abandoned pass.
            guard mayApplyRefreshResults else {
                throw CancellationError()
            }
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
            persistRecentMonthSnapshots(date: refreshDate, calendar: calendar)
            setRefreshStage(.computing)
            await reapplyActivityReadinessAfterWorkouts(date: refreshDate, calendar: calendar)
            await recomputeStress(on: refreshDate, calendar: calendar)
            await recomputeBodyRadar(on: refreshDate, calendar: calendar)
            publishWatchSnapshot()
            startStressInputLoadIfNeeded()
            startBodyRadarStepLoadIfNeeded()
            // Phase 2 of the two-phase trend window, same rule as
            // `refreshRecentMonths`: only when phase 1 fetched a short one.
            if fetchedPartialTrendWindow {
                startFullTrendWindowLoadIfNeeded(selection: dashboardFetchSelection)
            }
            updateHealthDataNotice()
            // Auto-apply for the refreshed month on every path (dashboard refresh AND the
            // Workouts-tab / warm-resume `refreshWorkoutMonth`, which passes
            // `updatesHealthSummary == false`). The 1-48h window self-limits candidates to
            // recent workouts, so browsing an older month simply finds none.
            await autoApplyPredictedEffortIfNeeded(monthKeys: [key])
            setRefreshStage(.finishing)
            if updatesHealthSummary, !hadQueryFailure, mayApplyRefreshResults {
                stageCompletedDashboardFreshness(date: refreshDate)
                persistDashboardSnapshot()
            }
        } catch {
            handleRefreshError(error)
        }
        // Same deadline rule as `refreshRecentMonths`.
        if updatesHealthSummary, ownsRefreshGeneration {
            await engine.setHealthTrendAnchorDate(nil)
        }
    }

    /// Fetch the dashboard summary and trend snapshot concurrently and publish
    /// each bucket to observed state as soon as it completes. Users see
    /// metric values, then trend charts fill in progressively instead of one
    /// large update at the very end of the refresh.
    /// Readiness is preserved at its cached value during the stream — the final
    /// `updateHealthDashboardSnapshot` recomputes it once everything has landed.
    ///
    /// Ring HISTORY is deliberately not one of these children (see
    /// `startActivityRingHistoryLoadIfNeeded`); the Activity Rings card's today
    /// values ride the summary leaf, so nothing on screen waits for it.
    private func fetchDashboardSnapshotProgressively(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection,
        forcesFullTrendWindow: Bool = false
    ) async throws -> (
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        hadQueryFailure: Bool,
        fetchedPartialTrendWindow: Bool
    ) {
        reconcileDashboardCacheScope()
        let inputs = captureRefreshInputs()
        let queryRevision = await engine.queryContextRevision
        guard mayApplyRefreshInputs(inputs), mayApplyRefreshResults else { throw CancellationError() }
        let queryScope = currentDashboardCacheScope()
        let cachedTrendsAtStart = healthTrends
        var fetchedSummary = healthSummary
        var fetchedTrends = healthTrends
        // ORs every dashboard leaf's failure — summary and trends (primary +
        // secondary + sleep-vitals) — so any failed query withholds the
        // freshness TTL and the next resume retries (H2c). Ring history no
        // longer contributes: it runs outside this barrier, so a ring failure
        // must not withhold a TTL for data that did land.
        var hadQueryFailure = false

        startActivityRingHistoryLoadIfNeeded(calendar: calendar, selection: selection)

        // Reuse the cached summary for failed leaves only while the current
        // selection still matches the one it was published under; a source /
        // permission switch invalidates it so failure resolves to empty.
        let currentSignature = currentPrimarySummarySignature()
        let cachedSummaryForReuse: HealthSummarySnapshot? =
            healthSummaryPrimarySignature == currentSignature ? healthSummary : nil

        // Phase 1 of the two-phase trend window (RefreshOptimizationPlan-02
        // P0-A). The merge that keeps the windowed leaves full-span happens
        // inside `fetchHealthTrends` and splices in CACHED points, so it is only
        // sound while those cached points were fetched under the selection that
        // is current now — the same gate the summary reuse above uses, since
        // that signature is stamped on the same publish the trends ride. On a
        // mismatch (or a stored range that already spans the year) phase 1
        // fetches the full window and no phase 2 is needed.
        let trendWindowDays: Int? = !forcesFullTrendWindow && healthSummaryPrimarySignature == currentSignature
            ? HealthKitFetchEngine.phaseOneTrendWindowDays()
            : nil

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
                        selection: selection,
                        trendWindowDays: trendWindowDays
                    )
                )
            }

            for await unit in group {
                // A body abandoned at the refresh deadline keeps running; its
                // late units must not publish over a newer refresh's.
                guard await engine.queryContextRevision == queryRevision,
                      mayApplyRefreshInputs(inputs), queryScope == currentDashboardCacheScope(), mayApplyRefreshResults else {
                    continue
                }
                switch unit {
                case .summary(let result):
                    fetchedSummary = result.summary
                    hadQueryFailure = hadQueryFailure || result.hadQueryFailure
                    // Keep the cached `readiness`, `stress` AND `bodyRadar`
                    // visible during the progressive publish — the final
                    // filtered+recomputed snapshot overrides all three in
                    // `updateHealthDashboardSnapshot`. None is fetched (all are
                    // derived), so a fetched summary always carries them empty:
                    // publishing it as-is blanked the Stress card for the length
                    // of every refresh.
                    healthSummary = result.summary
                        .replacingMetric(.readiness, with: healthSummary)
                        .replacingMetric(.stress, with: healthSummary)
                        .replacingMetric(.bodyRadar, with: healthSummary)
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
                }
            }
        }

        guard !Task.isCancelled, mayApplyRefreshResults else { throw CancellationError() }
        guard await engine.queryContextRevision == queryRevision,
              mayApplyRefreshInputs(inputs), queryScope == currentDashboardCacheScope(), mayApplyRefreshResults else {
            needsContextRefresh = true
            contextRefreshRequiresFetch = true
            scheduleContextRefreshIfNeeded()
            throw CancellationError()
        }
        return (fetchedSummary, fetchedTrends, hadQueryFailure, trendWindowDays != nil)
    }

    /// The out-of-band activity-ring history load, and the one at a time
    /// guarantee for it.
    ///
    /// Ring history is NOT a child of `fetchDashboardSnapshotProgressively`'s
    /// task group: `for await unit in group` cannot return until every child has
    /// produced a unit, so the first-load ten-year backfill held the whole
    /// refresh — `isRefreshing`, the first-launch "Loading Health Data…"
    /// overlay, the snapshot save that only runs after the group, and the
    /// success stamps — hostage to a scan that can run for minutes or hang
    /// outright. Users who granted only a couple of Health types watched that
    /// spinner forever, and because nothing was ever persisted, every relaunch
    /// started from zero.
    // `internal`, not `private`: BodyTests sets this directly (via @testable
    // import) to simulate an in-flight background ring backfill deterministically,
    // without racing the real HealthKit-backed chunk walk.
    @ObservationIgnored
    var activityRingHistoryTask: Task<Void, Never>?

    private func startActivityRingHistoryLoadIfNeeded(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection,
        date: Date = Date()
    ) {
        // A refresh arriving while a chunk walk is still running joins it rather
        // than stacking a second ten-year scan on top.
        guard activityRingHistoryTask == nil else {
            return
        }

        let epoch = cacheEpoch
        activityRingHistoryTask = Task { @MainActor [weak self] in
            await self?.loadActivityRingHistory(
                calendar: calendar,
                selection: selection,
                epoch: epoch,
                date: date
            )
            await self?.repairOneHistoricalRingMonth(calendar: calendar, epoch: epoch, date: date)
            self?.activityRingHistoryTask = nil
        }
    }

    private func loadActivityRingHistory(
        calendar: Calendar,
        selection: BodyDashboardFetchSelection,
        epoch: Int,
        date: Date
    ) async {
        // Same reason the ring-pagination path hydrates first: the save below
        // rewrites the day-sample sidecar from `healthTrends`.
        await hydratePersistedDaySamplesIfNeeded()

        let backfillState: HealthDashboardSnapshotStore.ActivityRingBackfillState
        if case .pending(let checkpoint) = activityRingBackfillState {
            // The checkpoint is an exclusive calendar-day boundary, just like
            // the records. Never interpret a saved midnight in a new zone.
            backfillState = .pending(resumeFrom: checkpoint == nil ? nil : activityRingBackfillResumeDay?.date(in: calendar))
        } else {
            backfillState = activityRingBackfillState
        }
        let result: ActivityRingHistoryFetchResult
        switch backfillState {
        case .pending(let resumeFrom):
            // Resume where the last chunk walk stopped instead of restarting at
            // today; `nil` means nothing has been walked yet. The checkpoint is
            // EXCLUSIVE and goes in as `resumeFrom`, never as `date` — the
            // engine converts it (`activityRingBackfillWalkEnd`), and `date`
            // stays today so the ten-year span stays anchored. Every chunk
            // lands as it arrives rather than at the end of the walk — see
            // `landActivityRingBackfillChunk`.
            result = await engine.fetchDashboardActivityRingBackfillHistory(
                calendar: calendar,
                selection: selection,
                date: date,
                resumeFrom: resumeFrom
            ) { [weak self] chunk in
                await self?.landActivityRingBackfillChunk(
                    chunk,
                    capturedEpoch: epoch,
                    calendar: calendar
                ) ?? false
            }
        case .completed, .suppressed:
            // A suppressed (denied) backfill still runs the cheap recent-window
            // read — that read IS the probe that notices access came back.
            result = await engine.fetchDashboardActivityRingHistory(calendar: calendar, selection: selection)
        }

        // A Clear Cache landed while the walk ran — don't publish or persist
        // onto the wiped state.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
            return
        }
        // Rings were switched off in Body's own selection while the walk ran:
        // `applyPermissionSelectionToCachedData` has already purged the history
        // and reset the backfill progress, and neither may be written back by a
        // walk the user has opted out of.
        guard permissionSelection.includes(.activityRings) else {
            return
        }

        let nextBackfillState = Self.nextActivityRingBackfillState(
            current: backfillState,
            authorizationDenied: result.authorizationDenied,
            reachedHistoryStart: result.reachedHistoryStart,
            nextChunkEndDate: result.nextChunkEndDate,
            foundDays: !result.history.days.isEmpty,
            now: date
        )
        if result.authorizationDenied {
            // Access was revoked: every cached month is stale, not just the
            // refreshed window.
            activityRingHistory = .empty
            loadedActivityRingMonthKeys.removeAll()
            exhaustedActivityRingMonthKeys.removeAll()
        } else {
            // A union merge of what the chunks already published, so this is a
            // no-op for the backfill walk — except in the one case the chunks
            // can't express: a covered span with no ring data anywhere, which
            // resolves to the recent window's month keys so the calendar shows
            // empty grids instead of nothing.
            guard applyActivityRingHistoryChunk(result.history, capturedEpoch: epoch, calendar: calendar) else {
                return
            }
        }
        // `result.hadQueryFailure` is deliberately dropped: this load no longer
        // gates the refresh, so a transient ring failure must not withhold the
        // freshness TTL for summary/trend data that landed cleanly.
        activityRingBackfillState = nextBackfillState
        if case .pending(let checkpoint?) = nextBackfillState {
            activityRingBackfillResumeDay = .init(date: checkpoint, calendar: calendar)
        } else {
            activityRingBackfillResumeDay = nil
        }
        persistActivityRingHistory()
    }

    private func repairOneHistoricalRingMonth(calendar: Calendar, epoch: Int, date: Date) async {
        guard await awaitRefreshSlotFree() else { return }
        guard case .completed = activityRingBackfillState,
              !isRefreshing, !Task.isCancelled,
              permissionSelection.includes(.activityRings) else { return }
        let inputs = captureRefreshInputs()
        let revision = activityRingHistoryRevision
        let queryRevision = await engine.queryContextRevision
        let context = "rings-v1|\(inputs.inputs.permissions)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        guard let backfillFloor = HealthKitFetchEngine.activityRingBackfillStartDate(date: date, calendar: calendar) else { return }
        let retainedFloor = activityRingHistory.loadedMonthKeySet(calendar: calendar)
            .compactMap { $0.startDate(calendar: calendar) }.min() ?? backfillFloor
        let floor = min(retainedFloor, backfillFloor)
        guard let month = HistoricalMonthRepairProgress.candidate(after: ringHistoricalRepair, now: date,
            earliest: floor, context: context, calendar: calendar) else { return }
        let key = ActivityRingMonthKey(date: month, calendar: calendar)
        let chunk = await engine.fetchActivityRingHistory(monthKey: key, calendar: calendar)
        guard await engine.queryContextRevision == queryRevision,
              !Task.isCancelled, !isRefreshing, activityRingHistoryRevision == revision,
              mayApplyRefreshInputs(inputs),
              chunk.loadedMonthKeys.contains(key),
              applyActivityRingHistoryChunk(chunk, capturedEpoch: epoch, calendar: calendar,
                resetsPagination: false) else { return }
        ringHistoricalRepair = .completed(month: month, now: date, earliest: floor,
            context: context, calendar: calendar)
        persistActivityRingHistory()
    }

    /// Lands ONE chunk of a running backfill walk: applies it through the
    /// shared funnel, then queues the grown history and checkpoint together.
    /// The live walk need not wait for disk: a quit resumes the last committed
    /// envelope, never the newer in-memory checkpoint. Returns `false`
    /// once a Clear Cache has invalidated the epoch the walk started under, so
    /// the engine stops querying for a store that no longer wants the answer.
    ///
    /// Per chunk rather than once at the end is the whole point. The ten-year
    /// walk runs for minutes: applying only at the end made the ring calendar
    /// appear in a single step, and a quit mid-walk threw every landed month
    /// away and restarted at today, because no checkpoint had been written yet.
    ///
    /// Internal for the same reason as `applyActivityRingHistoryChunk`: this is
    /// the seam where a test can drive the chunked arrival the production walk
    /// produces.
    @discardableResult
    func landActivityRingBackfillChunk(
        _ chunk: ActivityRingHistoryFetchResult,
        capturedEpoch: Int,
        calendar: Calendar = .bodyGregorian
    ) -> Bool {
        guard applyActivityRingHistoryChunk(chunk.history, capturedEpoch: capturedEpoch, calendar: calendar) else {
            return false
        }
        // The chunk that reached history start carries no checkpoint: whether
        // the walk `completed` is the terminal state's call, so nothing here
        // can push a finished backfill back to pending.
        if let nextChunkEndDate = chunk.nextChunkEndDate {
            activityRingBackfillState = .pending(resumeFrom: nextChunkEndDate)
            activityRingBackfillResumeDay = .init(date: nextChunkEndDate, calendar: calendar)
        }
        persistActivityRingHistory()
        return true
    }

    /// Applies ONE landed chunk of ring history to the live store: the merge,
    /// the loaded-key sync, and the pagination reset, all under the cache-epoch
    /// guard. Returns whether it applied (a Clear Cache since `capturedEpoch`
    /// drops the chunk).
    ///
    /// Internal rather than private on purpose. Ring history now grows in
    /// several chunks that land AFTER the refresh has completed, and every other
    /// mutator of `activityRingHistory` is private, async into HealthKit, or
    /// `init` — so this is the only seam where that chunked arrival is
    /// observable. It is the same funnel the background load uses, guards
    /// included, so a test driving chunks through it exercises the production
    /// path rather than a parallel setter.
    @discardableResult
    func applyActivityRingHistoryChunk(
        _ chunk: ActivityRingHistorySnapshot,
        capturedEpoch: Int,
        calendar: Calendar = .bodyGregorian,
        resetsPagination: Bool = true
    ) -> Bool {
        // A Clear Cache landed since the chunk was requested — don't republish
        // onto the wiped history. Rings being switched off is the same story:
        // cancelling the walk can't help a chunk that is already mid-flight, so
        // the opt-out is enforced here, at the point of application.
        //
        // `mayApplyRefreshResults` for the same reason: a refresh abandoned at
        // the deadline can still return from a stuck ring query minutes later,
        // and its chunk must not overwrite what the retry has since published.
        // Outside a deadline-guarded refresh the task-local is nil and this is
        // always true, so the lazy pagination path is unaffected.
        guard Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: cacheEpoch),
              mayApplyRefreshResults,
              permissionSelection.includes(.activityRings) else {
            return false
        }

        // Merge instead of replace — replacing dropped any older months the
        // user had paged in (and the next save then persisted that loss).
        let mergedRings = activityRingHistory.replacingLoadedMonths(with: chunk, calendar: calendar)
        activityRingHistory = mergedRings
        loadedActivityRingMonthKeys = Set(mergedRings.loadedMonthKeySet(calendar: calendar))
        // Fresh ring data may include backfilled months; let older-month
        // pagination re-probe instead of staying pinned at a previously
        // detected history start.
        if resetsPagination {
            exhaustedActivityRingMonthKeys.removeAll()
            hasMoreActivityRingHistory = true
        }
        return true
    }

    /// Archive repair validates individual months, not a contiguous pagination
    /// gap. Keep the existing history-end decision and all prior empty probes.
    @discardableResult
    func applyActivityRingArchiveRepair(
        _ chunk: ActivityRingHistorySnapshot,
        capturedEpoch: Int,
        calendar: Calendar = .bodyGregorian
    ) -> Bool {
        guard !chunk.loadedMonthKeys.isEmpty else { return false }
        var repair = chunk
        if repair.days.isEmpty { repair.loadedMonthKeys = [] }
        guard applyActivityRingHistoryChunk(repair, capturedEpoch: capturedEpoch,
                                           calendar: calendar, resetsPagination: false) else { return false }
        if repair.days.isEmpty { exhaustedActivityRingMonthKeys.formUnion(chunk.loadedMonthKeys) }
        return true
    }

    /// Queues each ring chunk with its checkpoint, so a walk interrupted by a
    /// quit resumes from what's actually on disk. Same
    /// signature-carrying save as the older-month pagination path.
    private func persistActivityRingHistory() {
        let snapshotToSave = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
            )
        }
    }

    /// The persisted backfill state a ring fetch result moves to. Pure — and
    /// taking the result's fields rather than the result — so the tri-state
    /// rules are unit-testable without HealthKit.
    nonisolated static func nextActivityRingBackfillState(
        current: HealthDashboardSnapshotStore.ActivityRingBackfillState,
        authorizationDenied: Bool,
        reachedHistoryStart: Bool,
        nextChunkEndDate: Date?,
        foundDays: Bool,
        now: Date
    ) -> HealthDashboardSnapshotStore.ActivityRingBackfillState {
        if authorizationDenied {
            // Park the ten-year scan rather than re-issuing it on every refresh
            // for as long as the permission stays off.
            return .suppressed(lastProbe: now)
        }
        // Only a walk that covered the whole span is done. The old marker was
        // stamped as soon as ONE result carried month keys, which called a
        // single partial chunk a finished ten-year history.
        if reachedHistoryStart {
            return .completed
        }

        switch current {
        case .completed:
            return .completed
        case .suppressed:
            // A read that came back with days means access is back: re-arm the
            // backfill from the top (the suppressed stretch was wiped).
            return foundDays ? .pending(resumeFrom: nil) : current
        case .pending:
            // Keep the existing checkpoint when the walk reported no new one (a
            // failed fetch, or rings excluded from the selection), so a
            // transient error doesn't restart the walk at today.
            guard let nextChunkEndDate else {
                return current
            }
            return .pending(resumeFrom: nextChunkEndDate)
        }
    }

    /// Primary-source + permission signature the summary reuse is scoped to.
    /// Cheap to recompute; captured at publish and compared at the next fetch
    /// (and persisted with the snapshot for cold-start reuse, H2a). Includes the
    /// two sleep-stage display prefs and the combine flag because sleep-summary
    /// parsing depends on them (`+Sleep.swift`) — so a pref change while the app
    /// is closed conservatively invalidates the reuse instead of resurrecting a
    /// value parsed under different grouping.
    private func currentPrimarySummarySignature() -> String {
        currentDashboardCacheScope().signature
    }

    func currentDashboardCacheScope() -> HealthDashboardCacheScope {
        let (calendar, now) = calendarContext()
        let aggregation = HealthDashboardCacheScope.key([
            String(describing: calendar.identifier), calendar.timeZone.identifier, "aggregation-v1"
        ])
        func source(_ kind: HealthMetricKind, comparison: Bool) -> HealthDashboardCacheScope.Source {
            let descriptor = HealthMetricQueryDescriptor.descriptor(for: kind)
            let sourceKind = descriptor?.querySourceKind ?? kind
            var option = comparison
                ? secondaryHealthDataSourceSelection.option(for: sourceKind)
                : healthDataSourceSelection.option(for: sourceKind)
            if comparison && !isProUnlocked { option = .noComparison }
            if option.isCustomSource && !isProUnlocked { option = comparison ? .noComparison : .allSources }
            if descriptor != nil && descriptor?.querySourceKind == nil { option = comparison ? .noComparison : .allSources }
            let groupMembers = customHealthSourceGroups.first { $0.id == option.id }?.memberIdentityKeys ?? []
            var parts = [
                option.id, String(combinesHealthDataSourcesByName),
                String(permissionSelection.includes(HealthKitFetchEngine.healthPermission(forMetric: kind))),
                HealthDashboardCacheScope.key(groupMembers.sorted())
            ]
            if kind == .sleep {
                parts += [String(BodySleepStageDisplayPreference.showsSubMinuteAwakeStages()),
                          String(BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages())]
            }
            if kind == .trainingLoad {
                let resting = source(.restingHeartRate, comparison: false)
                parts += [String(permissionSelection.includes(.heart)), String(permissionSelection.includes(.dateOfBirth)),
                          resting.request, resting.members.map { HealthDashboardCacheScope.key($0) } ?? "unresolved"]
            }
            if kind == .cardioFitness {
                parts += [String(permissionSelection.includes(.dateOfBirth))]
            }
            // De-duplication of comparisons also depends on the primary option.
            if comparison { parts.append(healthDataSourceSelection.option(for: sourceKind).id) }
            let request = HealthDashboardCacheScope.key(parts)
            let previous = comparison ? dashboardCacheScope?.secondary[kind.rawValue] : dashboardCacheScope?.primary[kind.rawValue]
            let members: [String]?
            if option.isNoComparison {
                members = []
            } else if let bucket = cacheSourceIdentities[sourceKind] {
                var primaryOption = healthDataSourceSelection.option(for: sourceKind)
                if primaryOption.isCustomSource && !isProUnlocked { primaryOption = .allSources }
                let resolvedPrimaryID = bucket[primaryOption.id]?.isEmpty == false
                    ? primaryOption.id : BodyHealthDataSourceOption.allSources.id
                if comparison && option.id == resolvedPrimaryID {
                    members = []
                } else {
                    members = bucket[option.id] ?? (comparison ? [] : bucket[BodyHealthDataSourceOption.allSources.id])
                }
            } else if previous?.request == request {
                // Before discovery, retain the last proven identity for first
                // paint. Discovery must settle before dependent queries launch.
                members = previous?.members
            } else {
                members = nil
            }
            return .init(request: request, members: members)
        }
        let primary = Dictionary(uniqueKeysWithValues: HealthDashboardCacheScope.leafKinds.map { ($0.rawValue, source($0, comparison: false)) })
        let secondary = Dictionary(uniqueKeysWithValues: HealthDashboardCacheScope.leafKinds.map { ($0.rawValue, source($0, comparison: true)) })
        return HealthDashboardCacheScope(primary: primary, secondary: secondary, aggregation: aggregation,
                                         sleepGoal: Self.storedIdealSleepDuration(), summaryDayStart: calendar.startOfDay(for: now))
    }

    /// Synchronous normalization happens before a settings mutator's first
    /// await, and again after discovery. All subsequent captures therefore
    /// contain either compatible data or absence, never old-source fallback
    /// relabeled with a new context.
    private func reconcileDashboardCacheScope() {
        let scope = currentDashboardCacheScope()
        guard scope != dashboardCacheScope else { return }
        if scope.rawSignatures() != dashboardCacheScope?.rawSignatures()
            || scope.rawSignatures(secondary: true) != dashboardCacheScope?.rawSignatures(secondary: true) {
            for field in HealthDaySampleSeries.allCases { daySampleRevisions[field, default: 0] &+= 1 }
        }
        let fetchChanged = scope.primary != dashboardCacheScope?.primary
            || scope.secondary != dashboardCacheScope?.secondary
            || scope.aggregation != dashboardCacheScope?.aggregation
            || scope.summaryDayStart != dashboardCacheScope?.summaryDayStart
        dashboardPublicationToken.invalidate()
        dashboardPublicationToken = HealthDashboardPublicationToken()
        let next = scope.scoping(HealthDashboardSnapshot(
            summary: healthSummary, trends: healthTrends, activityRingHistory: activityRingHistory
        ), from: dashboardCacheScope).filteredWithoutReadinessRecompute(by: permissionSelection)
        healthSummary = next.summary
        healthTrends = next.trends
        activityRingHistory = next.activityRingHistory
        dashboardCacheScope = scope
        healthSummaryPrimarySignature = scope.signature
        lastReadinessComputeDate = nil
        guard fetchChanged else { return }
        // Old computed-input watermarks must not qualify a new-source watch
        // seed. A successful refresh will establish these again.
        lastVitalsRefreshDate = nil
        lastReadinessComputeDate = nil
        lastTrainingLoadComputeDate = nil
        lastMetricPullDates.removeAll()
        cachedComputeTrainingLoadSeed = nil
        HealthDashboardSnapshotStore.clearWatchTrainingLoadSeed()
        lastSuccessfulRefreshDate = nil
        HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
        completedDashboardFreshness = nil
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
            combinesHealthDataSourcesByName: combinesHealthDataSourcesByName,
            primaryMetricScopes: dashboardCacheScope?.rawSignatures(),
            secondaryMetricScopes: dashboardCacheScope?.rawSignatures(secondary: true)
        )
    }

    private enum DashboardFetchUnit {
        case summary(HealthKitFetchEngine.HealthSummaryFetchResult)
        case trends(HealthKitFetchEngine.HealthTrendFetchResult)
    }

    private func loadMonthKeysIfNeeded(_ keys: Set<BodyWorkoutMonthKey>, allowPrompt: Bool) async {
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

        let keysToLoad = Set(keys.filter {
            !hasFreshSnapshot(month: $0.month, year: $0.year)
        }).subtracting(loadingMonthKeys)

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
            guard try await requestHealthKitAuthorization(allowPrompt: allowPrompt) else {
                return
            }
            // Scroll- and navigation-driven month loads run outside
            // `isRefreshing` and nothing on the Home dashboard waits for them,
            // so they spend the background budget even though `refresh(monthKeys:)`
            // is the same fetch the refresh path uses.
            try await withBackgroundQueryPool {
                try await refresh(monthKeys: keysToLoad, calendar: .bodyGregorian)
            }
            guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch) else {
                return
            }
            authorizationState = .authorized
            // A month browsed into (months 4 to 6 of the window) is fetched only
            // here, so without this it would live in memory alone and the next
            // launch would be back to "Loading data..." for it.
            persistRecentMonthSnapshots(date: Date(), calendar: .bodyGregorian)
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
        let inputs = captureRefreshInputs()
        let context = monthValidationContext
        let validationDate = Date()
        for key in orderedKeys { monthFetchRevisions[key, default: 0] &+= 1 }
        let revisions = monthFetchRevisions
        let queryRevision = await engine.queryContextRevision
        var publishedMonthKeys: Set<BodyWorkoutMonthKey> = []
        try await withThrowingTaskGroup(
            of: (BodyWorkoutMonthKey, HealthKitFetchEngine.WorkoutSummariesFetchResult).self
        ) { group in
            for key in orderedKeys {
                // Always hand the engine the month's cached summaries so the
                // effort / HR failure fallback can reuse them — since launch
                // seeds every persisted month, months 4 to 6 of the window now
                // offer that fallback on their first fetch too; REUSE proper
                // (skipping the batched HR query, and the cadence/distance
                // query pools, for aged workouts) stays gated on
                // `allowsCachedWorkoutReuse` — passive resumes only, so every
                // user-initiated pull-to-refresh remains a full reconcile.
                let reusableSummariesByID: [UUID: WorkoutSummary]
                if let cachedDays = monthSnapshots[key]?.days {
                    reusableSummariesByID = Dictionary(
                        cachedDays.flatMap(\.workouts).map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                } else {
                    reusableSummariesByID = [:]
                }
                let allowsCachedWorkoutReuse = reusesCachedWorkoutHeartRate
                group.addTask {
                    let workouts = try await engine.fetchWorkoutsWithValidation(
                        month: key.month,
                        year: key.year,
                        calendar: calendar,
                        allowsCachedWorkoutReuse: allowsCachedWorkoutReuse,
                        reusableSummariesByID: reusableSummariesByID
                    )
                    return (key, workouts)
                }
            }

            // Publish each month's snapshot as it returns so the Workouts tab
            // populates progressively instead of waiting for the slowest month.
            for try await (key, result) in group {
                guard await engine.queryContextRevision == queryRevision,
                      mayPublishMonthSnapshot(capturedEpoch: epoch), mayApplyRefreshInputs(inputs),
                      monthFetchRevisions[key] == revisions[key] else {
                    continue
                }
                let workouts = result.workouts
                // Read here, per returned month, and not before the task group:
                // `fetchWorkouts` records the device's current zone as it starts,
                // so a reading taken before the group would predate the record
                // this very fetch wrote. Each workout then lands on the day it
                // happened in the zone the phone was in at that instant rather
                // than on the day today's zone would name. Instant-scoped, not
                // day-scoped: the day-scoped rule answers with the end-of-day
                // zone, which moves a travel-day workout and moves it back on the
                // return leg, and a changed `dateKey` persists through
                // `WorkoutSnapshotStore.save`.
                let timeZoneResolver = engine.timeZoneLedger.snapshot()
                mutateMonthSnapshots { snapshots in
                    var next = WorkoutMonthSnapshot.make(
                        month: key.month,
                        year: key.year,
                        workouts: workouts,
                        calendar: calendar,
                        timeZoneIdentifier: { timeZoneResolver.zoneIdentifier(at: $0) }
                    )
                    next.recordValidation(at: validationDate, context: context, previous: snapshots[key],
                        allDetailsValidated: !result.hasUnvalidatedDetails, hadQueryFailure: result.hadQueryFailure)
                    snapshots[key] = next
                }
                loadedMonthKeys.insert(key)
                publishedMonthKeys.insert(key)
                noteMonthSnapshotStored(key)
                // Keeps the color editor's known-workout-types census current as months
                // load; the merge itself is a no-op write when nothing new appears.
                BodyWorkoutColorStore.mergeKnownWorkoutTypes(Set(workouts.map(\.type)))
                // Fold the month into the record ledger here rather than at the
                // persist step: this is the one place every freshly fetched month
                // passes through, so retroactive imports, late-arriving distances
                // and deletions inside a loaded month all self-repair.
                foldMonthIntoRecordLedger(key: key, workouts: workouts, calendar: calendar,
                    unvalidatedRecordIDs: result.unvalidatedRecordIDs)
            }
        }
        // Every month requested has now landed (a throw above skips this).
        // The weekly workout-minutes watermark advances only when this fetch
        // covered EVERY month the trailing 7-day window touches: early in a
        // month a passive refresh fetches just the current month while the
        // window's older days come from a persisted previous-month snapshot
        // that may predate workouts recorded since — stamping that combined
        // week fresh would let it overwrite a newer watch-computed one in the
        // per-metric merge. (From the 7th onward the window sits inside the
        // current month, so a current-month-only fetch still advances it.)
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let weekWindowKeys = Set(
            [today, calendar.date(byAdding: .day, value: -6, to: today)]
                .compactMap { $0 }
                .map { BodyWorkoutMonthKey(date: $0, calendar: calendar) }
        )
        if await engine.queryContextRevision == queryRevision,
           weekWindowKeys.isSubset(of: publishedMonthKeys),
           mayApplyRefreshInputs(inputs),
           monthKeys.allSatisfy({ monthFetchRevisions[$0] == revisions[$0] }),
           mayPublishMonthSnapshot(capturedEpoch: epoch) {
            lastWorkoutsRefreshDate = now
            // Persisted under its own key so a relaunch restores the coverage
            // this fetch actually earned, rather than inheriting an
            // early-month success date that covered only the current month.
            HealthDashboardSnapshotStore.saveLastWorkoutsWeekCoverageDate(now)
        }
    }

    /// Whether a month snapshot produced by an in-flight load may still be
    /// published.
    ///
    /// Two ways it may not: a Clear Cache landed mid-load (only possible from
    /// the lazy, non-`isRefreshing` month loads), or the refresh this load
    /// belongs to was ABANDONED at `healthRefreshDeadline`. The per-workout
    /// heart-rate / VO₂ reads are continuation based, so `fetchWorkouts` can
    /// return normally minutes after the deadline fired — long enough for a
    /// newer retry to have published these same months.
    ///
    /// Internal so a test can drive the decision the progressive month writes
    /// actually make, rather than a copy of it.
    func mayPublishMonthSnapshot(capturedEpoch: Int) -> Bool {
        Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: cacheEpoch) && mayApplyRefreshResults
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
            mutateMonthSnapshots { $0.removeValue(forKey: evictedKey) }
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

    /// Metric kinds whose data feeds the Stress score. Refreshing one of them
    /// changes a Stress input, so the recompute has to re-run. Deliberately its
    /// own set rather than an addition to `readinessInputMetricKinds` — that set
    /// means "recompute Readiness", and the two metrics read different inputs.
    /// Resting heart rate is absent on purpose: Stress scores against the
    /// quiet-HR baseline it derives itself, not against daily RHR.
    nonisolated static let stressInputMetricKinds: Set<HealthMetricKind> = [
        .stress,
        .heartRate,
        .heartRateVariability,
        .sleep,
        .steps,
        .activeEnergy
    ]

    /// Permissions whose data feeds Stress. Toggling one changes the input set,
    /// so the recorded days — accumulated under the previous inputs, and
    /// carrying the baseline aggregates — are dropped and re-accumulate.
    nonisolated static let stressInputPermissions: Set<BodyHealthPermission> = [
        .heart,
        .sleep,
        .steps,
        .energy,
        .workouts
    ]

    /// Metric kinds whose data feeds Body Radar. Refreshing one of them changes
    /// a Radar input, so the recompute has to re-run. Its own set for the same
    /// reason `stressInputMetricKinds` is: the derived metrics overlap but read
    /// different inputs.
    nonisolated static let bodyRadarInputMetricKinds: Set<HealthMetricKind> = [
        .bodyRadar,
        .sleep,
        .steps
    ]

    /// The metric kinds whose SOURCE selection the Radar record context signs.
    /// A superset of `bodyRadarInputMetricKinds`: the sleep-vital queries Radar
    /// scores from follow the per-metric source selections for these four
    /// kinds, so switching one of them scores a different night and the frozen
    /// records have to drop. Kept separate from `bodyRadarInputMetricKinds`
    /// because that set also gates the per-metric recompute trigger, and a
    /// vitals-only pull does not change a Radar input on its own.
    nonisolated static let bodyRadarSignedSourceKinds: Set<HealthMetricKind> = bodyRadarInputMetricKinds.union([
        .heartRate,
        .heartRateVariability,
        .respiratoryRate,
        .wristTemperature
    ])

    /// Permissions whose data feeds Body Radar. Toggling one changes the input
    /// set, so the frozen nights recorded under the previous inputs are dropped
    /// and re-accumulate.
    nonisolated static let bodyRadarInputPermissions: Set<BodyHealthPermission> = [
        .sleep,
        .steps,
        .heart,
        .respiratory,
        .wristTemperature,
        .workouts
    ]

    /// The intraday day-sample series Stress scores from. The dashboard refresh
    /// carries these forward from cache without refetching, so the Stress loader
    /// is what keeps them (and therefore today's curve) current.
    nonisolated static let stressIntradaySampleKinds: [HealthMetricKind] = [
        .heartRate,
        .heartRateVariability,
        .steps,
        .activeEnergy
    ]

    @discardableResult
    func updateHealthDashboardSnapshot(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        activityRingHistory: ActivityRingHistorySnapshot,
        recomputesReadiness: Bool = true,
        recomputesStress: Bool = true,
        recomputesBodyRadar: Bool = true,
        persists: Bool = true,
        authoritativeDaySamples: Set<HealthDaySampleSeries> = [],
        expectedDataRevision: Int? = nil
    ) async -> Bool {
        let epoch = cacheEpoch
        let inputs = captureRefreshInputs()
        let scope = currentDashboardCacheScope()
        let calendar = Calendar.bodyGregorian
        let anchorDate = await engine.healthTrendAnchorDate ?? Date()
        guard mayApplyRefreshInputs(inputs), mayApplyRefreshResults,
              expectedDataRevision.map({ $0 == dashboardDataRevision && !isRefreshing }) ?? true else { return false }
        let permissionSelection = self.permissionSelection
        let idealSleepDuration = Self.storedIdealSleepDuration()
        // Stress is derived, never fetched, so a freshly fetched summary always
        // carries it empty (same reason `fetchDashboardSnapshotProgressively`
        // preserves it during the progressive publish). When this pass skips the
        // recompute — the full refresh runs it once after the workout join,
        // where the activity mask finally has workouts — carry the live values
        // in ahead of the filter, or the publish below (and anything the
        // abandonment path persists from it) blanks the Stress card until
        // `recomputeStress` lands. The trend side is already carried forward by
        // the engine's `cachedStress*` assembly.
        var carriedSummary = recomputesStress ? summary : summary.replacingMetric(.stress, with: healthSummary)
        // Body Radar is derived the same way, so it needs the same carry: a
        // fetched summary always arrives with it empty.
        if !recomputesBodyRadar {
            carriedSummary = carriedSummary.replacingMetric(.bodyRadar, with: healthSummary)
        }
        let rawSnapshot = HealthDashboardSnapshot(
            summary: carriedSummary,
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
        let sleepEnd = summary.sleep.stageSnapshot.wakeCycleEnd
        let wakeTime = Self.freezeWakeTime(sleepEnd: sleepEnd, scoringDay: anchorDate, now: now, calendar: calendar)
        let todaysWorkouts = currentWakeCycleWorkouts(now: now, sleepEnd: sleepEnd, calendar: calendar)
        let recordedReadinessContext = readinessRecordContextSignature()
        let recordedStressContext = stressRecordContextSignature()
        let stressWorkouts = stressWindowWorkouts(through: anchorDate, calendar: calendar)
        // Radar reuses the readiness freeze pair (`wakeTime` / `now`) above and
        // the stress window's workouts: its inactive-time signal is masked on any
        // day carrying one, over the same ~34-day span the step cache reaches.
        let computesBodyRadar = recomputesBodyRadar && self.computesBodyRadar
        let recordedBodyRadarContext = bodyRadarRecordContextSignature()
        let filteredSnapshot = await Task.detached(priority: .userInitiated) {
            let signpostState = BodyPerformanceSignposts.signposter.beginInterval("ReadinessRecompute")
            defer { BodyPerformanceSignposts.signposter.endInterval("ReadinessRecompute", signpostState) }
            var filtered = rawSnapshot.filteredWithoutReadinessRecompute(by: permissionSelection)
            if recomputesReadiness {
                filtered = filtered.recalculatingReadiness(
                    on: anchorDate,
                    idealSleepDuration: idealSleepDuration,
                    calendar: calendar,
                    todaysWorkouts: todaysWorkouts,
                    wakeTime: wakeTime,
                    now: now,
                    freezesRecordedReadiness: recomputesReadiness,
                    recordedReadinessContext: recordedReadinessContext
                )
            }
            if recomputesStress {
                filtered = filtered.recalculatingStress(
                    on: anchorDate,
                    workouts: stressWorkouts,
                    calendar: calendar,
                    now: now,
                    recordedStressContext: recordedStressContext
                )
            }
            if computesBodyRadar {
                filtered = filtered.recalculatingBodyRadar(
                    on: anchorDate,
                    workouts: stressWorkouts,
                    calendar: calendar,
                    now: now,
                    wakeTime: wakeTime,
                    recordedBodyRadarContext: recordedBodyRadarContext
                )
            }
            return filtered
        }.value

        if let beforeDashboardComputeCommit { await beforeDashboardComputeCommit() }
        // A Clear Cache that landed while the off-actor recompute ran must win:
        // don't publish or persist the recomputed snapshot onto the wiped state.
        // A refresh abandoned at `healthRefreshDeadline` loses the same way: its
        // late snapshot must not overwrite a newer refresh's.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              expectedDataRevision.map({ $0 == dashboardDataRevision && !isRefreshing }) ?? true,
              mayApplyRefreshInputs(inputs), scope == currentDashboardCacheScope(), mayApplyRefreshResults else {
            return false
        }

        let nextActivityRingHistory = self.activityRingHistory.replacingLoadedMonths(
            with: filteredSnapshot.activityRingHistory,
            calendar: calendar
        )
        healthSummary = filteredSnapshot.summary
        // Scope the summary reuse to the selection this snapshot reflects.
        healthSummaryPrimarySignature = scope.signature
        healthTrends = filteredSnapshot.trends
        recordAuthoritativeDaySamples(authoritativeDaySamples)
        self.activityRingHistory = nextActivityRingHistory
        loadedActivityRingMonthKeys = Set(nextActivityRingHistory.loadedMonthKeySet(calendar: calendar))
        // Fresh dashboard data may include backfilled months; let older-month
        // pagination re-probe (at most a few cheap queries) instead of staying
        // pinned at a previously detected history start.
        exhaustedActivityRingMonthKeys.removeAll()
        hasMoreActivityRingHistory = true

        // `persists: false` defers this to the caller's single end-of-refresh
        // write (see `refreshRecentMonths`); the state published above is what
        // that write encodes.
        guard persists else {
            return true
        }
        persistDashboardSnapshot()
        saveHealthWidgetSnapshot()
        return true
    }

    /// Only a settled full-refresh tail may offer a new cold-start watermark.
    /// `markRefreshSucceeded` updates live state earlier, before compute awaits;
    /// abandonment and intermediate saves must not persist that newer claim.
    func stageCompletedDashboardFreshness(date: Date) {
        guard mayApplyRefreshResults, lastSuccessfulRefreshDate == date else { return }
        completedDashboardFreshness = .init(
            date: date,
            contextSignature: dashboardFreshnessContextSignature()
        )
    }

    private func dashboardFreshnessContextSignature() -> String {
        let selection = BodyDashboardFetchSelection.load()
        let tiers = HealthMetricKind.allCases.sorted { $0.rawValue < $1.rawValue }.map {
            "\($0.rawValue):\(selection.includes($0)):\(selection.includesFullPayload($0))"
        }
        return HealthDashboardCacheScope.key(
            [currentDashboardCacheScope().signature, String(selection.includesActivityRings)] + tiers
        )
    }

    /// Captured in the same synchronous span as each payload, before queueing.
    /// A failed write leaves the candidate in memory so another save can retry
    /// without fetching again; only metadata decoded from disk is durable.
    func currentDashboardPersistenceMetadata() -> HealthDashboardSnapshotStore.PersistenceMetadata {
        HealthDashboardSnapshotStore.PersistenceMetadata(
            ringBackfill: permissionSelection.includes(.activityRings)
                ? activityRingBackfillState : .pending(resumeFrom: nil),
            secondarySelectionSignature: currentSecondarySelectionSignature(),
            freshness: completedDashboardFreshness?.contextSignature == dashboardFreshnessContextSignature()
                ? completedDashboardFreshness : nil,
            ringBackfillResumeDay: {
                guard permissionSelection.includes(.activityRings),
                      case .pending(.some) = activityRingBackfillState else { return nil }
                return activityRingBackfillResumeDay
            }(),
            ringHistoricalRepair: permissionSelection.includes(.activityRings) ? ringHistoricalRepair : nil
        )
    }

    /// Encodes and writes the live dashboard snapshot (summary + trends + ring
    /// history) plus the signatures that gate its reuse. Split out of
    /// `updateHealthDashboardSnapshot` so the full refresh can coalesce that
    /// publish, the readiness reapply, and the stress recompute into ONE write
    /// after the tail settles instead of three full encodes per pass.
    private func persistDashboardSnapshot(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard mayApplyRefreshResults else { completion?(false); return }
        reconcileDashboardCacheScope()
        let snapshotToSave = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        // Persist the summary-context signature stamped at publish time so a
        // cold start can gate the summary reuse (H2a). Rides inside the
        // snapshot, so it saves atomically with the data on every path.
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { completion?(false); return }
            let outcome = HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
            )
            completion?(outcome.main.isDurable && outcome.sidecar.isDurable)
            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
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

    /// Workouts across the whole window Stress scans, not just the current wake
    /// cycle: they are the fine activity mask, and every scanned day needs one.
    /// A day wider than the scan so a session that started before its first
    /// midnight still masks that day's opening windows.
    private func stressWindowWorkouts(through date: Date, calendar: Calendar) -> [WorkoutSummary] {
        let scoreDay = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -35, to: scoreDay) ?? scoreDay
        return monthSnapshots.values
            .flatMap(\.days)
            .flatMap(\.workouts)
            .filter { $0.startDate >= start }
    }

    /// Intraday Stress windows for one calendar day, for the detail day view.
    /// Read-only — scores against the live cached snapshot without persisting
    /// anything, using the same wide workout window (fine activity mask) the
    /// background recompute scans.
    func stressWindows(for day: Date, calendar: Calendar = .bodyGregorian) -> [StressWindow] {
        guard permissionSelection.includes(.heart) else {
            return []
        }

        return HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        ).stressWindows(
            for: day,
            workouts: stressWindowWorkouts(through: Date(), calendar: calendar),
            calendar: calendar,
            now: Date()
        )
    }

    /// Re-derives Stress from the currently cached snapshot and persists it when
    /// it moved. Used after the workout join — the dashboard recompute runs
    /// before workouts are available (they fetch concurrently), so a fresh,
    /// edited, or deleted workout would otherwise leave the activity mask
    /// wrong — and after the post-refresh intraday/RMSSD load.
    ///
    /// Async because the scoring itself — ~34 days × up to ~100 fifteen-minute
    /// windows — is the second-heaviest per-refresh CPU spike after the readiness
    /// recompute, and it used to run synchronously on the main actor inside the
    /// refresh deadline. Callers still AWAIT it: an unawaited detached recompute
    /// could publish over newer state (a landed input load, a backfill chunk, a
    /// later refresh) and persist that rollback, and neither the refresh
    /// generation nor the cache epoch can tell two ordinary recomputes apart.
    private func recomputeStress(on date: Date, calendar: Calendar, persists: Bool = true) async {
        guard permissionSelection.includes(.heart) else {
            return
        }

        let epoch = cacheEpoch
        let inputs = captureRefreshInputs()
        let scope = currentDashboardCacheScope()
        let now = Date()
        let captured = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let workouts = stressWindowWorkouts(through: date, calendar: calendar)
        let recordedStressContext = stressRecordContextSignature()
        let recomputed = await Task.detached(priority: .userInitiated) {
            captured.recalculatingStress(
                on: date,
                workouts: workouts,
                calendar: calendar,
                now: now,
                recordedStressContext: recordedStressContext
            )
        }.value

        // Same rule as `updateHealthDashboardSnapshot`: a Clear Cache that landed
        // while the off-actor scoring ran must win, and a refresh abandoned at
        // `healthRefreshDeadline` must not publish over a newer one's state.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              mayApplyRefreshInputs(inputs), scope == currentDashboardCacheScope(), mayApplyRefreshResults else {
            return
        }

        // A backfill chunk can publish during the off-actor hop (only outside a
        // refresh — the walk parks while one runs, but the input loader's call
        // happens after). Its recorded days and markers are newer than what this
        // pass computed from the capture; merging ours would roll the chunk back
        // and persist the rollback. Stand down instead — the chunk's own publish
        // already rebuilt the stress trend, and the next recompute reconciles.
        guard healthTrends.recordedStressDays == captured.trends.recordedStressDays,
              healthTrends.stressBackfillScannedThrough == captured.trends.stressBackfillScannedThrough,
              healthTrends.stressBackfillComplete == captured.trends.stressBackfillComplete else {
            return
        }

        // Merge only the stress-owned fields into the CURRENT live snapshot. The
        // captured one is stale by whatever published during the hop — the
        // intraday day samples the input loader merges, a dashboard leaf, a ring
        // month — so republishing it wholesale would roll those back and then
        // persist the rollback.
        var summary = healthSummary
        summary.stress = recomputed.summary.stress
        summary.stressCurrentScore = recomputed.summary.stressCurrentScore
        var trends = healthTrends
        trends.stress = recomputed.trends.stress
        trends.stressRanges = recomputed.trends.stressRanges
        trends.recordedStressDays = recomputed.trends.recordedStressDays
        trends.recordedStressContext = recomputed.trends.recordedStressContext
        trends.stressBackfillScannedThrough = recomputed.trends.stressBackfillScannedThrough
        trends.stressBackfillComplete = recomputed.trends.stressBackfillComplete

        let stressChanged = summary.stress != healthSummary.stress
            || summary.stressCurrentScore != healthSummary.stressCurrentScore
            || trends.stress != healthTrends.stress
            || trends.recordedStressDays != healthTrends.recordedStressDays
        healthSummary = summary
        healthTrends = trends
        // `persists: false` defers to the caller's single end-of-refresh write,
        // which encodes the state just published above.
        guard stressChanged, persists else {
            return
        }

        let snapshotToSave = HealthDashboardSnapshot(
            summary: summary,
            trends: trends,
            activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        // Carry the current summary-context signature so this save doesn't
        // clobber the persisted one back to nil (H2a), as in the readiness
        // reapply below.
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
            )
        }
    }

    /// The Body Radar twin of `recomputeStress`, run at the same points and for
    /// the same reason: the dashboard recompute happens before the workouts its
    /// inactive-time mask needs are available, and the step day samples the
    /// signal reads land with the post-refresh input load.
    ///
    /// Its own permission guard (`.sleep`, not `.heart`) and its own selection
    /// gate, so a layout without the card pays nothing.
    private func recomputeBodyRadar(on date: Date, calendar: Calendar, persists: Bool = true) async {
        guard computesBodyRadar else {
            return
        }

        let epoch = cacheEpoch
        let inputs = captureRefreshInputs()
        let scope = currentDashboardCacheScope()
        let now = Date()
        let captured = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        )
        let wakeTime = Self.freezeWakeTime(
            sleepEnd: captured.summary.sleep.stageSnapshot.wakeCycleEnd,
            scoringDay: date,
            now: now,
            calendar: calendar
        )
        let workouts = stressWindowWorkouts(through: date, calendar: calendar)
        let recordedBodyRadarContext = bodyRadarRecordContextSignature()
        let recomputed = await Task.detached(priority: .userInitiated) {
            captured.recalculatingBodyRadar(
                on: date,
                workouts: workouts,
                calendar: calendar,
                now: now,
                wakeTime: wakeTime,
                recordedBodyRadarContext: recordedBodyRadarContext
            )
        }.value

        // Same rule as `recomputeStress`: a Clear Cache or an abandoned refresh
        // that landed while the off-actor scoring ran must win.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              mayApplyRefreshInputs(inputs), scope == currentDashboardCacheScope(), mayApplyRefreshResults else {
            return
        }

        // Merge only the Radar-owned fields into the CURRENT live snapshot, for
        // the reason spelled out in `recomputeStress`.
        var summary = healthSummary
        summary.bodyRadar = recomputed.summary.bodyRadar
        var trends = healthTrends
        trends.recordedBodyRadar = recomputed.trends.recordedBodyRadar
        trends.recordedBodyRadarContext = recomputed.trends.recordedBodyRadarContext

        let changed = summary.bodyRadar != healthSummary.bodyRadar
            || trends.recordedBodyRadar != healthTrends.recordedBodyRadar
        healthSummary = summary
        healthTrends = trends
        guard changed, persists else {
            return
        }

        let snapshotToSave = HealthDashboardSnapshot(
            summary: summary,
            trends: trends,
            activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
            )
        }
    }

    /// Publishes one chunk of the Stress history backfill: the scored days
    /// upserted into `recordedStressDays`, both stress series rebuilt from the
    /// result, and the walk marker advanced — one publish, one persist, so a
    /// kill between chunks can never leave the marker ahead of the records it
    /// claims to describe. Called only from
    /// `HealthKitWorkoutStore+StressBackfill.swift`, which owns the guards.
    func applyStressBackfillChunk(
        summaries: [StressDaySummary],
        scannedThrough: Date,
        complete: Bool,
        calendar: Calendar
    ) {
        let updated = HealthDashboardSnapshot(
            summary: healthSummary,
            trends: healthTrends,
            activityRingHistory: activityRingHistory
        ).mergingStressBackfillChunk(
            summaries,
            scannedThrough: scannedThrough,
            complete: complete,
            on: Date(),
            calendar: calendar
        )
        healthTrends = updated.trends

        let daySampleSignatures = currentDaySampleSignatures()
        // Same reason as `recomputeStress`: carry the current summary-context
        // signature so this save doesn't clobber the persisted one back to nil.
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                updated,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
            )
        }
    }

    /// After the workout fetch lands, re-apply the activity drain + morning freeze
    /// to the live readiness using the now-complete workout snapshots, without a
    /// full series rebuild. The dashboard recompute earlier in a refresh runs
    /// before workouts are available (they fetch concurrently), so this catches
    /// today's just-finished session.
    private func reapplyActivityReadinessAfterWorkouts(date: Date, calendar: Calendar, persists: Bool = true) async {
        guard permissionSelection.includes(.workouts) else {
            return
        }
        let now = Date()
        let sleepEnd = healthSummary.sleep.stageSnapshot.wakeCycleEnd
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
        // `persists: false` defers to the caller's single end-of-refresh write
        // (and its widget push), which encodes the state just published above.
        guard readinessChanged, persists else {
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
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
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
        // A refresh abandoned at `healthRefreshDeadline` keeps running: it must
        // not stamp success — the freshness TTL, the first-load completion, the
        // badge — for a load the user was already told had timed out.
        guard mayApplyRefreshResults else {
            return
        }
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
        // A completed full refresh means the user has been through the first
        // load — even a partial one (denied read permissions make some leaves
        // fail on EVERY refresh) or one that found nothing. Deliberately not
        // gated on `hadQueryFailure`/`ranQueries`, and never stamped from
        // `handleRefreshError`, so a thrown refresh still re-presents the
        // first-launch overlay with Try Again.
        if refreshedVitals, !hasCompletedInitialHealthDataLoad {
            hasCompletedInitialHealthDataLoad = true
            HealthDashboardSnapshotStore.saveInitialHealthDataLoadCompleted()
        }
        if refreshedVitals, !hadQueryFailure {
            lastSuccessfulRefreshDate = date
            // Live success is immediate. Only the settled dashboard tail may
            // attach this date to an atomic persisted envelope.
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
        guard includesWorkouts, fetchesTrainingLoad, !hadQueryFailure, mayApplyRefreshResults else {
            return
        }
        let inputs = captureRefreshInputs()
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
        guard mayApplyRefreshInputs(inputs), mayApplyRefreshResults else { return }
        setCachedComputeTrainingLoadSeed(startDay: seed.startDay, loads: seed.loads, through: date)
    }

    /// Rebuilds and republishes both companion snapshots (iOS widget + watch)
    /// from the currently-published health summary/trends. For preference
    /// changes that only affect formatting (units, sleep goal, show-sleep-
    /// score) a full refetch is unnecessary — a rebuild from what's already
    /// published is enough. Skipped while a cache clear is in flight so it
    /// can't resurrect state the clear is wiping.
    ///
    /// Debounced by 300 ms, because a held stepper or a dragged slider fires one
    /// `onChange` per tick and each rebuild encodes both snapshots and reloads
    /// the widget timelines. Known trade: a preference change followed within
    /// 300 ms by app suspension publishes on the next refresh instead. The task
    /// lives on the publisher, which this store owns, so dismissing the settings
    /// view does not drop it.
    func republishCompanionSnapshots() {
        _ = captureRefreshInputs()
        companionPublisher.scheduleRepublish { [weak self] in
            guard let self, !self.isClearingCache else { return }
            // One shared capture for both publishes: the summary, trends and
            // display preferences they render from are the same reads, and this
            // rebuild is exactly where they are guaranteed not to change in
            // between (no `await` separates the two calls).
            let shared = self.makeSharedPublishInput()
            self.saveHealthWidgetSnapshot(shared: shared)
            self.publishWatchSnapshot(shared: shared)
        }
    }

    /// The trailing week's workout minutes (oldest → today, 7 slots) for the
    /// watch's weekly workout complication, summed from the month snapshots'
    /// per-day totals — a workout counts toward the day it started, in the zone
    /// it started in (the month snapshot resolved that day through the device
    /// time-zone ledger when it was built). Every day in the window carries an
    /// explicit value (`0` for a rest day) so the watch's merge reads the week as
    /// real data instead of a blank.
    ///
    /// `fallback` covers months `monthSnapshots` doesn't hold: on launch only
    /// the current month is restored into memory and passive refreshes fetch
    /// only the current month, so for the first six days of a month the window
    /// reaches into a month the in-memory map can't answer for. Returns `nil`
    /// only when a month the window spans is in NEITHER source, so a
    /// genuinely-unknown month can't publish a falsely empty week.
    nonisolated static func weeklyWorkoutMinutes(
        from monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot],
        fallback: [BodyWorkoutMonthKey: WorkoutMonthSnapshot] = [:],
        now: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [Double?]? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: today) else {
            return nil
        }

        var minutes: [Double?] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: windowStart) else {
                return nil
            }
            let key = BodyWorkoutMonthKey(date: day, calendar: calendar)
            guard let snapshot = monthSnapshots[key] ?? fallback[key] else {
                return nil
            }
            let dayNumber = calendar.component(.day, from: day)
            minutes.append((snapshot.day(dayNumber)?.totalDuration ?? 0) / 60)
        }
        return minutes
    }

    /// The persisted previous-month snapshot in `weeklyWorkoutMinutes`'s input
    /// shape, read ONLY when the trailing week reaches into a month
    /// `monthSnapshots` doesn't carry. Launch now seeds the persisted months
    /// into memory, so that gap is narrow: an evicted month, or a month whose
    /// file exists while memory lost it. Every refresh from the seventh of the
    /// month onward, and every refresh that already loaded the previous month,
    /// skips the disk entirely. It's the same App Group data the iOS widget
    /// reads, and `WorkoutSnapshotStore.load` memoizes the decode by file
    /// identity, so a repeated publish pays a `stat` rather than a decode.
    ///
    /// Dropping the week is not benign: `WatchComputeMerge.merging` maps over
    /// the RECEIVED metrics, so a push that omits `workoutMinutes` deletes the
    /// complication's bars instead of leaving them alone (and an older watch
    /// binary can't repair that locally). The remaining `nil` corner — a fresh
    /// install with no persisted previous month, during the first six days of a
    /// month — is the honest one: there is genuinely no data for those days.
    ///
    /// Keyed by the snapshot's own month/year, which is self-validating: a
    /// stale file (holding a month older than the window needs) simply fails to
    /// match the missing key and changes nothing.
    // Internal (not `private`) so `BodyCompanionPublisher` can run it off the
    // main actor, inside the persist queue block, where its file decode belongs.
    nonisolated static func persistedWeeklyWorkoutFallback(
        for monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot],
        now: Date,
        calendar: Calendar
    ) -> [BodyWorkoutMonthKey: WorkoutMonthSnapshot] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: today) else {
            return [:]
        }
        let windowKeys = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: windowStart)
                .map { BodyWorkoutMonthKey(date: $0, calendar: calendar) }
        }
        guard windowKeys.contains(where: { monthSnapshots[$0] == nil }),
              let previous = WorkoutSnapshotStore.loadPrevious() else {
            return [:]
        }
        return [BodyWorkoutMonthKey(month: previous.month, year: previous.year): previous]
    }

    /// Pushes the latest metrics to the paired Apple Watch. Best-effort: the
    /// build is pure and `send` never blocks the refresh. Publishing from the
    /// common funnel (including workout-only paths) keeps the watch's values
    /// current, but `lastRefreshDate` carries the last *vitals* refresh — a
    /// workout-only refresh must not look fresh to the watch, or it would
    /// suppress the watch's own stale-triggered live HR/HRV refresh.
    func publishWatchSnapshot() {
        publishWatchSnapshot(shared: makeSharedPublishInput())
    }

    /// The publish, from a `Shared` capture the caller already took. Exists for
    /// `republishCompanionSnapshots`, which saves the widget snapshot from the
    /// same capture: taking it twice would read the store twice for one rebuild.
    private func publishWatchSnapshot(shared: BodyCompanionPublishInput.Shared) {
        guard mayApplyRefreshResults else { return }
        let inputs = captureRefreshInputs()
        let token = dashboardPublicationToken
        companionPublisher.publishWatchSnapshot(
            makeCompanionPublishInput(shared: shared),
            isEpochCurrent: { [weak self] capturedEpoch in
                guard let self else {
                    return false
                }
                return Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: self.cacheEpoch)
                    && self.mayApplyRefreshInputs(inputs) && token.isValid
            }
        )
    }

    /// Captures, synchronously on the main actor, exactly what the watch
    /// snapshot build and send read off this store beyond `shared` (which the
    /// caller captured, also synchronously, immediately before). There is no
    /// `await` anywhere in that span, so the capture sequence allocated below
    /// equals capture order (see `WatchConnectivityPublisher`) and a queued
    /// build can't ship a newer permission selection than the summary it was
    /// paired with.
    ///
    /// Everything derived FROM these captures (the weekly workout minutes and
    /// their persisted fallback, the 14-day time-zone map, the seed encode) runs
    /// on the persist queue inside `BodyCompanionPublisher` (M-08).
    func makeCompanionPublishInput(
        shared: BodyCompanionPublishInput.Shared
    ) -> BodyCompanionPublishInput {
        // Phase 3 compute-seed capture, alongside the display-snapshot inputs
        // so both ship from the same consistent state. `summary`/`trends` are
        // read LIVE (same as the display snapshot) — they're already the
        // store's best current data whether this publish came from a full
        // refresh or a settings-only republish (permission / preference changes
        // refilter them in place without a new fetch), so no separate "carried"
        // copy is needed. Only `dataThrough` and the Training Load piece are
        // genuinely frozen between full refreshes: `lastVitalsRefreshDate`
        // already advances ONLY on a clean full refresh (never on a republish),
        // and `cachedComputeTrainingLoadSeed` is kept in lockstep with it
        // (`updateCachedComputeTrainingLoadSeedIfNeeded`) — so a settings-only
        // republish reaching this same code path automatically carries both
        // forward unchanged, satisfying "never advance `dataThrough` on
        // publication" without extra bookkeeping. `nil` `dataThrough` (no full
        // refresh yet this session) sends no seed.
        let dataThrough = lastVitalsRefreshDate
        // Body Pro gate for the seed: the watch has no entitlement concept, so
        // a lapsed subscription has to ship the All-Sources view the phone now
        // renders — otherwise the watch keeps filtering by a group the phone
        // stopped applying, and the two disagree indefinitely. The definitions
        // are withheld, never erased; the entitlement observer republishes on a
        // flip and the changed `src[…]`/`groups[…]` signature re-seeds.
        let isProUnlocked = BodyProEntitlement.isUnlocked
        let trainingLoadSeed = cachedComputeTrainingLoadSeed
        return BodyCompanionPublishInput(
            shared: shared,
            epoch: cacheEpoch,
            lastRefreshDate: lastVitalsRefreshDate,
            permissionSelection: permissionSelection,
            permissionRawValue: BodyHealthPermissionSelection.load().rawValue,
            now: Date(),
            workoutCalendar: .bodyGregorian,
            monthSnapshots: monthSnapshots,
            // Allocate the capture sequence at this main-actor capture point so
            // its order equals capture order (see `WatchConnectivityPublisher`).
            captureSequence: WatchConnectivityPublisher.shared.nextCaptureSequence(),
            dataThrough: dataThrough,
            // Honest per-kind watermarks, SPLIT because they genuinely differ: a
            // workout-only refresh re-drains readiness but never recomputes
            // Training Load. Readiness `max`es with the vitals date so a full
            // refresh whose Workouts permission is off (no
            // `reapplyActivityReadinessAfterWorkouts`) still stamps it at least
            // as fresh as the vitals it was computed from. Training Load stays
            // nil until it is actually recomputed — the builder then falls back
            // to the uniform vitals stamp (the pre-split legacy behavior for a
            // value that has no fresher provenance).
            readinessComputeDate: [lastVitalsRefreshDate, lastReadinessComputeDate]
                .compactMap { $0 }
                .max(),
            trainingLoadComputeDate: lastTrainingLoadComputeDate,
            // Coverage only, never the vitals date: a full passive refresh early
            // in a month advances `lastVitalsRefreshDate` while fetching just
            // the current month, and stamping the mixed current/persisted-
            // previous week with that fresh date would let it overwrite a newer
            // watch-computed week carrying month-end workouts the phone hasn't
            // refetched.
            //
            // UNKNOWN coverage is stamped `.distantPast` rather than left nil:
            // nil means "no per-kind stamp" to the builder, which then falls
            // back to that same vitals date. An install upgrading into this
            // build has no persisted coverage yet, so until its first
            // full-coverage refresh the week must lose every freshness compare —
            // the watch's own computed bars win, and a watch with none still
            // displays the pushed week.
            workoutMinutesDataAsOf: lastWorkoutsRefreshDate ?? .distantPast,
            metricPullDates: lastMetricPullDates,
            trainingLoadStartDay: trainingLoadSeed?.startDay,
            trainingLoadDailyLoads: trainingLoadSeed?.loads,
            trainingLoadDataThrough: trainingLoadSeed?.through,
            expectedSourceIDsByKind: cachedExpectedSourceIDsByKind,
            followsSystemUnits: UserDefaults.standard.object(
                forKey: BodyAppearancePreference.followsSystemUnitsKey
            ) as? Bool ?? true,
            selectedTemperatureUnitRaw: UserDefaults.standard.string(
                forKey: BodyAppearancePreference.selectedTemperatureUnitKey
            ) ?? BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue,
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages(),
            healthDataSourceSelectionRaw: isProUnlocked
                ? healthDataSourceSelection.rawValue
                : Self.selectionNeutralizingCustomSources(healthDataSourceSelection).rawValue,
            customHealthSourceGroupsRaw: isProUnlocked && !customHealthSourceGroups.isEmpty
                ? BodyCustomHealthSourceGroupStore.rawValue(from: customHealthSourceGroups)
                : nil,
            combinesByName: combinesHealthDataSourcesByName
        )
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
        // One reading of the ledger for all fourteen days, not one per day.
        let resolver = ledger.snapshot()
        var map: [String: String] = [:]
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchorDay),
                  let identifier = resolver.zoneIdentifier(on: day) else {
                continue
            }
            map[dayFormatter.string(from: day)] = identifier
        }
        return map
    }

    /// Builds the slim widget snapshot from the current trends, sleep stages,
    /// source selection, and unit preferences, then writes it to the App Group
    /// so the trend + sleep-stage widgets can render. Reads run on the main
    /// actor; the build + disk write happen off-actor.
    private func saveHealthWidgetSnapshot() {
        saveHealthWidgetSnapshot(shared: makeSharedPublishInput())
    }

    /// The save, from a `Shared` capture the caller already took (see
    /// `publishWatchSnapshot(shared:)`).
    private func saveHealthWidgetSnapshot(shared: BodyCompanionPublishInput.Shared) {
        let token = dashboardPublicationToken
        companionPublisher.saveWidgetSnapshot(makeWidgetPublishInput(shared: shared), isCurrent: { token.isValid })
    }

    /// Captures, synchronously on the main actor, what BOTH companion snapshots
    /// render from: the widget snapshot and the watch snapshot read the same
    /// summary, trends and display preferences.
    func makeSharedPublishInput() -> BodyCompanionPublishInput.Shared {
        _ = captureRefreshInputs()
        reconcileDashboardCacheScope()
        return BodyCompanionPublishInput.Shared(
            trends: healthTrends,
            summary: healthSummary,
            temperatureUnitPreference: HealthWidgetSnapshotBuilder.storedTemperatureUnitPreference(),
            idealSleepDuration: Self.storedIdealSleepDuration(),
            showSleepScore: HealthWidgetSnapshotBuilder.storedShowSleepScore()
        )
    }

    /// Adds the widget-only captures to a `Shared` one: the energy and weight
    /// unit preferences, and the per-metric primary source names.
    /// `selectedHealthDataSourceOption(for:)` is `@MainActor`, so the names are
    /// resolved here and the builder off-actor only reads the resulting map.
    /// Kept off `Shared` so the watch publish, which renders none of the three,
    /// does not run those sixteen lookups on the main actor.
    private func makeWidgetPublishInput(
        shared: BodyCompanionPublishInput.Shared
    ) -> BodyCompanionPublishInput.Widget {
        var primarySourceNames: [HealthMetricKind: String] = [:]
        for metric in HealthWidgetMetric.allCases {
            let kind = metric.healthMetricKind
            primarySourceNames[kind] = selectedHealthDataSourceOption(for: metric.sourceSelectionKind).name
        }

        return BodyCompanionPublishInput.Widget(
            shared: shared,
            energyUnitPreference: HealthWidgetSnapshotBuilder.storedEnergyUnitPreference(),
            weightUnitPreference: HealthWidgetSnapshotBuilder.storedWeightUnitPreference(),
            primarySourceNames: primarySourceNames
        )
    }

    /// Serializes dashboard and widget disk writes so an earlier (pre-drain) save
    /// can never land after a later (post-drain) one and leave disk or widget
    /// state stale. Enqueue order on the main actor is the write order (FIFO).
    // Internal (not `private`) so the records extension's ledger writes land on
    // the same serial queue — the Clear Cache barrier relies on that FIFO order.
    static let snapshotPersistQueue = DispatchQueue(label: "com.body.snapshotPersist", qos: .utility)

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

    /// The Stress counterpart of `readinessRecordContextSignature`: which Stress
    /// permissions are enabled, the primary source per Stress input kind, and
    /// whether same-name sources are combined. The recorded days are tagged with
    /// it and dropped when it changes, because they carry baseline aggregates
    /// derived under the old inputs. The sleep-duration goal is deliberately
    /// absent (Stress uses only the sleep WINDOW), the awake-stage prefs are not
    /// (they move the parsed main session).
    nonisolated static func stressRecordContextSignature(
        permissionSelection: BodyHealthPermissionSelection,
        healthDataSourceSelection: BodyHealthDataSourceSelection,
        combinesHealthDataSourcesByName: Bool,
        showsSubMinuteAwakeStages: Bool,
        showsLeadingTrailingAwakeStages: Bool,
        customSourceGroupsSignatureSuffix: String = ""
    ) -> String {
        let permissions = stressInputPermissions
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue):\(permissionSelection.includes($0) ? "1" : "0")" }
            .joined(separator: ",")
        let sources = stressInputMetricKinds
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue):\(healthDataSourceSelection.option(for: $0).id)" }
            .joined(separator: ",")
        let awakeFlags = "a[\(showsSubMinuteAwakeStages ? "1" : "0")];l[\(showsLeadingTrailingAwakeStages ? "1" : "0")]"
        return "p[\(permissions)];s[\(sources)];c[\(combinesHealthDataSourcesByName ? "1" : "0")];\(awakeFlags)"
            + customSourceGroupsSignatureSuffix
    }

    /// The Body Radar counterpart of `stressRecordContextSignature`: which Radar
    /// permissions are enabled and the primary source per signed Radar kind. The
    /// frozen nights are tagged with it and dropped when it changes, because a
    /// different input set scores a different night.
    nonisolated static func bodyRadarRecordContextSignature(
        permissionSelection: BodyHealthPermissionSelection,
        healthDataSourceSelection: BodyHealthDataSourceSelection,
        combinesHealthDataSourcesByName: Bool,
        showsSubMinuteAwakeStages: Bool,
        showsLeadingTrailingAwakeStages: Bool,
        customSourceGroupsSignatureSuffix: String = ""
    ) -> String {
        let permissions = bodyRadarInputPermissions
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue):\(permissionSelection.includes($0) ? "1" : "0")" }
            .joined(separator: ",")
        let sources = bodyRadarSignedSourceKinds
            .sorted { $0.rawValue < $1.rawValue }
            .map { "\($0.rawValue):\(healthDataSourceSelection.option(for: $0).id)" }
            .joined(separator: ",")
        let awakeFlags = "a[\(showsSubMinuteAwakeStages ? "1" : "0")];l[\(showsLeadingTrailingAwakeStages ? "1" : "0")]"
        return "p[\(permissions)];s[\(sources)];c[\(combinesHealthDataSourcesByName ? "1" : "0")];\(awakeFlags)"
            + customSourceGroupsSignatureSuffix
    }

    private func bodyRadarRecordContextSignature() -> String {
        Self.bodyRadarRecordContextSignature(
            permissionSelection: permissionSelection,
            healthDataSourceSelection: healthDataSourceSelection,
            combinesHealthDataSourcesByName: combinesHealthDataSourcesByName,
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages(),
            customSourceGroupsSignatureSuffix: customSourceGroupsSignatureSuffix
        )
    }

    /// Body Radar is scored only when the Sleep permission is on AND the layout
    /// actually shows the card: an off card must not pay for the recompute, and
    /// without Sleep there is nothing to score.
    private var computesBodyRadar: Bool {
        permissionSelection.includes(.sleep)
            && BodyDashboardFetchSelection.load().includes(.bodyRadar)
    }

    private func stressRecordContextSignature() -> String {
        Self.stressRecordContextSignature(
            permissionSelection: permissionSelection,
            healthDataSourceSelection: healthDataSourceSelection,
            combinesHealthDataSourcesByName: combinesHealthDataSourcesByName,
            showsSubMinuteAwakeStages: BodySleepStageDisplayPreference.showsSubMinuteAwakeStages(),
            showsLeadingTrailingAwakeStages: BodySleepStageDisplayPreference.showsLeadingTrailingAwakeStages(),
            customSourceGroupsSignatureSuffix: customSourceGroupsSignatureSuffix
        )
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
        let inputs = captureRefreshInputs()
        // A toggle can change the Stress record context, and the recompute at
        // the end of this drops the recorded days it invalidates. Stop the
        // history walk first, so a chunk scored under the OLD inputs can't land
        // on top of the freshly dropped records.
        await cancelStressBackfill()
        // The permission transaction owns the refresh slot through filtering
        // and persistence. Keep the epoch fence as well as input admission.
        let epoch = cacheEpoch
        await hydratePersistedDaySamplesIfNeeded()
        guard mayApplyRefreshInputs(inputs) else { return }
        let scope = currentDashboardCacheScope()
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

        await beforePermissionSnapshotCommit?()
        // A cache clear landed mid-filter — don't republish/persist the filtered
        // snapshot onto the wiped state.
        guard Self.mayApplyLoad(capturedEpoch: epoch, currentEpoch: cacheEpoch),
              mayApplyRefreshInputs(inputs), scope == currentDashboardCacheScope() else {
            return
        }

        healthSummary = filteredSnapshot.summary
        // Re-scope the summary reuse to the now-applied permission selection.
        healthSummaryPrimarySignature = currentPrimarySummarySignature()
        healthTrends = filteredSnapshot.trends
        activityRingHistory = filteredSnapshot.activityRingHistory
        loadedActivityRingMonthKeys = Set(filteredSnapshot.activityRingHistory.loadedMonthKeySet(calendar: .bodyGregorian))
        // `filtered(by:)` recomputes readiness but not stress, so re-derive it
        // here too: a toggle changes the stress record context, and the recorded
        // days it invalidates must drop now rather than at the next refresh.
        await recomputeStress(on: Date(), calendar: .bodyGregorian)
        await recomputeBodyRadar(on: Date(), calendar: .bodyGregorian)
        guard mayApplyRefreshInputs(inputs), scope == currentDashboardCacheScope() else { return }

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
            // Stop the in-flight walk from querying more months for a user who
            // just opted out. Cancellation alone isn't enough — a chunk can be
            // mid-flight already — so `applyActivityRingHistoryChunk` and
            // `loadActivityRingHistory` refuse to apply anything while rings
            // are off.
            activityRingHistoryTask?.cancel()
            // The filtered save below purges the cached ring history, so the
            // backfill progress must fall with it — otherwise re-enabling rings
            // resumes recent-months-only fetches and the ten-year history never
            // rebuilds.
            activityRingBackfillState = .pending(resumeFrom: nil)
            ringHistoricalRepair = nil
        } else if case .suppressed = activityRingBackfillState {
            // Rings are back on in Body's own selection, so the denial that
            // parked the backfill may be gone: re-arm it and let the next ring
            // load find out.
            activityRingBackfillState = .pending(resumeFrom: nil)
            ringHistoricalRepair = nil
        }

        let snapshotToSave = HealthDashboardSnapshot(
            summary: healthSummary, trends: healthTrends, activityRingHistory: activityRingHistory
        )
        let daySampleSignatures = currentDaySampleSignatures()
        let summaryContextSignature = healthSummaryPrimarySignature
        let persistenceMetadata = currentDashboardPersistenceMetadata()
        let daySampleWriteIntent = authoritativeDaySampleSeries
        let token = dashboardPublicationToken
        Self.snapshotPersistQueue.async {
            guard token.isValid else { return }
            HealthDashboardSnapshotStore.saveWithOutcome(
                snapshotToSave,
                daySampleSignatures: daySampleSignatures,
                summaryContextSignature: summaryContextSignature,
                metadata: persistenceMetadata,
                authoritativeDaySampleSeries: daySampleWriteIntent
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
        mutateMonthSnapshots { snapshots in
            snapshots = snapshots.mapValues { monthSnapshot in
                WorkoutMonthSnapshot.make(
                    month: monthSnapshot.month,
                    year: monthSnapshot.year,
                    workouts: [],
                    calendar: calendar
                )
            }
            snapshots[BodyWorkoutMonthKey(month: emptySnapshot.month, year: emptySnapshot.year)] = emptySnapshot
        }
        loadedMonthKeys.removeAll()
        monthLoadOrder.removeAll()

        // The in-memory clear above leaves the App Group JSON untouched, but the
        // widget re-reads it via `loadCurrentOrPreviousIfEmpty()` and the app
        // re-reads it on cold start — so rewrite every persisted month file
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
            let widgetReloadNeeded = WorkoutSnapshotStore.mapPersistedMonths { emptied($0) }
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
    /// stripped fields drop. `calendar` is threaded through for identity but the
    /// strip itself maps each day's workouts in place, so a time-zone change
    /// between fetch and opt-out never reassigns a near-midnight workout to a
    /// different day (and drops it) the way regrouping by `dateKey` would.
    private func sanitizeWorkoutSnapshots(
        calendar: Calendar = .bodyGregorian,
        _ transform: @escaping @Sendable (WorkoutMonthSnapshot, Calendar) -> WorkoutMonthSnapshot
    ) {
        snapshot = transform(snapshot, calendar)
        setMonthSnapshots(monthSnapshots.mapValues { transform($0, calendar) })

        // The in-memory strip above leaves the App Group JSON untouched, but the
        // widget reads it via `loadCurrentOrPreviousIfEmpty()` and the app
        // re-reads it on cold start — so rewrite every persisted month file
        // stripped too. This clears the data at rest on opt-out instead of
        // waiting for the next refresh to overwrite the month files.
        // Route through the persist queue so this load-modify-write can't
        // interleave with a concurrent refresh save and resurrect the stripped
        // metrics, and request the widget reload only after the rewrite lands
        // (otherwise the widget can rebuild from the un-stripped file first).
        Self.snapshotPersistQueue.async {
            let widgetReloadNeeded = WorkoutSnapshotStore.mapPersistedMonths { transform($0, calendar) }
            if widgetReloadNeeded {
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }
        }
    }

    // Test-only override for the directory `persistRecentMonthSnapshots` saves
    // its month files into (and, one level up from it, the legacy pair it
    // deletes and the files the prune keep-set reads back). nil (the default,
    // and the only value any production call site ever sees) means "use the real
    // App Group location". BodyTests sets this because the unsigned test target
    // has no App Group container (`WorkoutSnapshotStore.sharedContainerURL` is
    // nil there), so asserting persistence needs a real, test-owned directory.
    static var testSnapshotDirectoryURLOverride: URL?

    /// Writes every in-window month currently in memory to disk, then reconciles
    /// what's at rest: the legacy two-file cache goes, out-of-window month files
    /// are pruned, and the per-workout detail files are trimmed to what the
    /// persisted months still reference.
    private func persistRecentMonthSnapshots(date: Date, calendar: Calendar) {
        let currentKey = BodyWorkoutMonthKey(date: date, calendar: calendar)
        guard let currentSnapshot = monthSnapshots[currentKey] else {
            return
        }

        snapshot = currentSnapshot
        // Captured on the main actor: the queue block below must not touch
        // `monthSnapshots`.
        let windowKeys = Self.recentMonthKeys(
            count: WorkoutSnapshotStore.persistedMonthCount,
            from: date,
            calendar: calendar
        )
        let snapshotsToSave = windowKeys.compactMap { monthSnapshots[$0] }
        let directoryURL = Self.testSnapshotDirectoryURLOverride ?? WorkoutSnapshotStore.monthSnapshotsDirectoryURL
        let previousMonthKey = calendar.date(byAdding: .month, value: -1, to: date)
            .map { BodyWorkoutMonthKey(date: $0, calendar: calendar) }

        // Route through the shared persist queue (not a bare `Task.detached`) so
        // two successive refreshes' month saves keep FIFO enqueue order — an
        // earlier save must never land after a later one and stale the widget.
        Self.snapshotPersistQueue.async {
            var widgetReloadNeeded = false
            for monthSnapshot in snapshotsToSave {
                let fileURL = WorkoutSnapshotStore.fileURL(
                    month: monthSnapshot.month,
                    year: monthSnapshot.year,
                    directoryURL: directoryURL
                )
                if WorkoutSnapshotStore.save(monthSnapshot, fileURL: fileURL) {
                    widgetReloadNeeded = true
                }
            }
            // Only once the month-keyed writes have landed: until then the
            // legacy pair is the only copy a widget or the watch fallback can
            // read after an update from an older build.
            WorkoutSnapshotStore.deleteLegacyFiles(directoryURL: directoryURL)

            // Drop detail files for workouts the persisted months no longer
            // carry. The keep-set is read back from the ON-DISK month files, not
            // from `monthSnapshots`: months seeded at launch can be evicted from
            // memory while their files stay, so an in-memory keep-set would
            // delete their details. For the same reason, a missing file means
            // "unknown", not "empty" — skip the prune entirely rather than guess.
            if let previousMonthKey,
               let current = WorkoutSnapshotStore.load(
                   month: currentKey.month,
                   year: currentKey.year,
                   directoryURL: directoryURL
               ),
               current.workoutCount > 0,
               WorkoutSnapshotStore.load(
                   month: previousMonthKey.month,
                   year: previousMonthKey.year,
                   directoryURL: directoryURL
               ) != nil {
                var keeping: Set<UUID> = []
                for month in WorkoutSnapshotStore.loadPersistedMonths(
                    now: date,
                    calendar: calendar,
                    directoryURL: directoryURL
                ) {
                    for day in month.days {
                        for workout in day.workouts {
                            keeping.insert(workout.id)
                        }
                    }
                }
                WorkoutDetailSnapshotStore.prune(keeping: keeping)
            }

            WorkoutSnapshotStore.pruneOutsideWindow(
                now: date,
                calendar: calendar,
                directoryURL: directoryURL
            )

            if widgetReloadNeeded {
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }

            Task { @MainActor in await self.refreshCacheDiskSize() }
        }
    }

    private func updateHealthDataNotice() {
        // An abandoned (deadline-expired) refresh must not clear the timeout
        // notice that deadline just set, nor speak for a newer refresh.
        guard mayApplyRefreshResults else {
            return
        }

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
        // Same for an abandoned refresh's late failure — the deadline already
        // told the user what happened.
        guard mayApplyRefreshResults else { return }
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


    private func fetchHealthDataSourceOptions(calendar: Calendar, force: Bool = false) async {
        let signpostState = BodyPerformanceSignposts.signposter.beginInterval("SourceOptions")
        defer { BodyPerformanceSignposts.signposter.endInterval("SourceOptions", signpostState) }
        let inputs = captureRefreshInputs()
        let nextOptionsByKind = await engine.fetchHealthDataSourceOptions(calendar: calendar, force: force)
        let revision = await engine.queryContextRevision
        let identities = await engine.cacheSourceIdentities()
        let expected = await engine.watchComputeExpectedSourceIDs()
        let individual = await engine.discoveredIndividualHealthSources()
        let custom = await engine.customHealthSourceIDsWithData()
        guard await engine.queryContextRevision == revision, mayApplyRefreshInputs(inputs) else { return }
        cacheSourceIdentities = identities
        reconcileDashboardCacheScope()
        if let nextOptionsByKind {
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
                expected
            ) { _, next in next }
            HealthDashboardSnapshotStore.saveWatchExpectedSourceIDs(cachedExpectedSourceIDsByKind)
        }

        // OUTSIDE the `if let`: the engine returns nil once its permission
        // signature is latched, and both of these must still populate on that
        // path — the membership pool for the editor, and the per-kind custom
        // bucket map the synchronous resolved-option accessors read.
        discoveredIndividualHealthSources = individual
        customSourceIDsWithDataByKind = custom
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
