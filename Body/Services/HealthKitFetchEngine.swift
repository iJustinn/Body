//
//  HealthKitFetchEngine.swift
//  Body
//

import Foundation
import HealthKit
import os

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
    var customHealthSourceGroups: [BodyCustomHealthSourceGroup]

    var healthSourcesByKind: [HealthMetricKind: [String: [HKSource]]] = [:]
    var fetchedHealthDataSourcePermissionRawValue: String?

    var anchorDate: Date?

    /// Shared workout fetch for the training-load summary AND the training-load
    /// trend series. Both consume the same workout window; running them
    /// as independent HK queries (one per orchestrator) duplicates the round-trip
    /// and the per-workout effort fan-out. Memoized by window so simultaneous
    /// callers within a refresh share a single in-flight fetch.
    var sharedTrainingLoadWorkoutsTask: Task<[WorkoutSummary], Error>?
    var sharedTrainingLoadWorkoutsWindow: TrainingLoadWorkoutsWindow?

    /// Process-lifetime cache for the per-workout effort-score fan-out
    /// (`fetchEffortLevels`): effort needs one relationship-predicate query per
    /// workout, and both the training-load fetch and the month
    /// refreshes re-walk the same historical workouts every refresh. Found
    /// scores are trusted for the process; workouts confirmed score-less are
    /// only skipped once they ended over
    /// `BodyWorkoutEffortFetcher.effortConfirmationAge` ago (ratings land right
    /// after a workout). User-initiated refreshes clear both via
    /// `clearWorkoutEffortCache()` so a re-rated workout reconciles on any
    /// pull-to-refresh; a cold launch always starts clean. Entries for
    /// deleted workouts are just unused (bounded by workouts seen per process).
    var effortLevelsByWorkoutID: [UUID: Double] = [:]
    var confirmedNoEffortWorkoutIDs: Set<UUID> = []

    nonisolated static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "HealthKitFetchEngine"
    )

    /// A HealthKit query callback fired with no result (`errorDatabaseInaccessible`
    /// on a locked device, `errorHealthDataUnavailable`, or a transient XPC drop).
    /// The trend fetch helpers resume with `nil` in that case so the assembly
    /// layer keeps the previously cached series instead of blanking it, and this
    /// records the failure. No health values are logged.
    nonisolated static func logTrendQueryFailure(_ context: String, error: Error?) {
        logger.error(
            "HealthKit trend query failed (\(context, privacy: .public)); keeping cached series. \(error?.localizedDescription ?? "no error object", privacy: .public)"
        )
    }

    /// Resolves a freshly fetched trend series against the cached one. A `nil`
    /// `fetched` means the HealthKit query itself failed (device locked, store
    /// unavailable, XPC drop) rather than genuinely returning no data, so the
    /// previously cached series is kept. A non-nil `fetched` — including an
    /// intentionally empty series produced when a permission is toggled off —
    /// replaces the cache.
    nonisolated static func resolvedTrendSeries<Series>(
        fetched: Series?,
        cached: Series
    ) -> Series {
        fetched ?? cached
    }

    /// Outcome of a single summary-leaf query. Distinguishes a query FAILURE
    /// (device locked, store unavailable, XPC drop — resolver keeps the cached
    /// value) from a genuine absence (`.success(nil)` — no samples, permission
    /// off, or selection off — resolver clears the tile). Mirrors the trend
    /// convention (`resolvedTrendSeries`) without a `Value??` double-optional.
    enum QueryOutcome<Value> {
        case success(Value?)
        case failure

        var isFailure: Bool {
            if case .failure = self { return true }
            return false
        }

        /// The successfully fetched value (`nil` for confirmed-absent or failure).
        var successValue: Value? {
            switch self {
            case .success(let value):
                return value
            case .failure:
                return nil
            }
        }

        /// The successfully fetched value, or `fallback` for confirmed-absent /
        /// failure. Used where a leaf feeds a best-effort aggregate that cannot
        /// keep a per-item cache (e.g. sleep-history nocturnal vitals).
        func valueOr(_ fallback: Value) -> Value {
            successValue ?? fallback
        }
    }

    /// Resolves a freshly fetched summary leaf against the cached value. A
    /// `.failure` means the HealthKit query itself failed rather than genuinely
    /// returning no data, so the previously cached value is kept. A `.success`
    /// — including an intentionally absent value produced when a permission or
    /// source selection is toggled off — replaces the cache. Mirrors
    /// `resolvedTrendSeries`.
    nonisolated static func resolvedSummaryValue<Value>(
        fetched: QueryOutcome<Value>,
        cached: Value?
    ) -> Value? {
        switch fetched {
        case .success(let value):
            return value
        case .failure:
            return cached
        }
    }

    /// Result of `fetchHealthSummary`: the resolved snapshot plus whether any
    /// leaf query failed. When a leaf failed the store still publishes/persists
    /// the resolved (cache-preserving) snapshot but skips advancing the
    /// freshness TTL, so the next resume retries instead of trusting a partial
    /// result as 5-minutes-fresh.
    struct HealthSummaryFetchResult {
        let summary: HealthSummarySnapshot
        let hadQueryFailure: Bool
    }

    /// Result of the single-metric `fetchHealthDashboardSnapshot`: the resolved
    /// dashboard snapshot plus whether ANY leaf query the metric ran failed (as
    /// opposed to a genuine `.success(nil)`/empty absent value) — summary,
    /// trend, secondary, day-sample, or sleep-history. A failed query keeps the
    /// cached value, so a metric-detail pull that errored must not be treated by
    /// the caller as a genuine refresh — otherwise the sync badge would falsely
    /// confirm "Health data updated". `ranQueries` reports whether the fetch
    /// actually dispatched at least one HealthKit query: a metric whose
    /// permission is disabled early-returns the cached snapshot without querying,
    /// and the caller must not let that no-op advance the sync badge either.
    struct HealthDashboardMetricFetchResult {
        let snapshot: HealthDashboardSnapshot
        let hadQueryFailure: Bool
        let ranQueries: Bool
    }

    /// Result of `fetchHealthTrends`: the resolved trend snapshot plus whether
    /// ANY trend leaf query failed — primary series (nil from
    /// `resolvedTrendSeries`), secondary series (resolved against the cached
    /// secondary value), or a nocturnal sleep-vital query. Mirrors
    /// `HealthSummaryFetchResult`: the store still publishes/persists the
    /// resolved (cache-preserving) snapshot but ORs this bit with the summary's
    /// and the ring-history bits before deciding whether to advance the
    /// freshness TTL, so any failed leaf makes the next resume retry.
    struct HealthTrendFetchResult {
        let trends: HealthTrendSnapshot
        let hadQueryFailure: Bool
    }

    struct TrainingLoadWorkoutsWindow: Equatable {
        let start: Date
        let end: Date
    }

    static let trainingLoadSummaryDayCount = TrainingLoadCalculator.summaryWindowDayCount

    init(
        permission: BodyHealthPermissionSelection,
        healthDataSourceSelection: BodyHealthDataSourceSelection,
        secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection,
        combinesHealthDataSourcesByName: Bool,
        customHealthSourceGroups: [BodyCustomHealthSourceGroup] = []
    ) {
        self.permissionSelection = permission
        self.healthDataSourceSelection = healthDataSourceSelection
        self.secondaryHealthDataSourceSelection = secondaryHealthDataSourceSelection
        self.combinesHealthDataSourcesByName = combinesHealthDataSourcesByName
        self.customHealthSourceGroups = customHealthSourceGroups
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

    func setCustomHealthSourceGroups(_ groups: [BodyCustomHealthSourceGroup]) {
        // Compared by CANONICAL signature, not by value: only ids and
        // membership decide which buckets get registered, so a pure rename must
        // not clear the discovery cache — nothing refetches after a rename, and
        // an emptied cache would leave every source selection unresolved (leaf
        // queries skipping with failure semantics, H4) until the next refresh.
        let previousSignature = BodyCustomHealthSourceGroupStore.canonicalSignature(for: customHealthSourceGroups)
        customHealthSourceGroups = groups
        guard previousSignature != BodyCustomHealthSourceGroupStore.canonicalSignature(for: groups) else {
            return
        }

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

    /// Age + biological sex — the two inputs the cardio fitness level bands are
    /// indexed by — read from the Apple Health characteristics.
    ///
    /// Returns a `QueryOutcome` rather than a bare optional so a transient
    /// characteristic-read error keeps the CACHED profile instead of
    /// unclassifying the user: an unclassified reading hides the level band and
    /// the card headline, which would be a visible regression for a failure that
    /// resolves itself on the next refresh. `.success(nil)` is a confirmed
    /// absence — permission off, no value on file, or a sex the norms have no
    /// table for — and does clear it.
    func cardioFitnessProfile(asOf now: Date = Date()) -> QueryOutcome<CardioFitnessProfile> {
        guard permissionSelection.includes(.cardioFitness) else {
            return .success(nil)
        }

        let birthComponents: DateComponents
        let biologicalSex: HKBiologicalSex
        do {
            birthComponents = try healthStore.dateOfBirthComponents()
            biologicalSex = try healthStore.biologicalSex().biologicalSex
        } catch let error as HKError where error.code == .errorNoData {
            // A characteristic the user never entered is a confirmed absence, not
            // a failure — reporting `.failure` here would withhold the freshness
            // TTL on every refresh forever for anyone who left it blank.
            return .success(nil)
        } catch {
            return .failure
        }

        // `.notSet` / `.other` (and any future case) stay unclassified: the norms
        // are published as two tables, and guessing one would be worse than
        // showing no level at all.
        let sex: CardioFitnessSex
        switch biologicalSex {
        case .female:
            sex = .female
        case .male:
            sex = .male
        case .notSet, .other:
            return .success(nil)
        @unknown default:
            return .success(nil)
        }

        guard let birthDate = Calendar.current.date(from: birthComponents),
              let age = Calendar.current.dateComponents([.year], from: birthDate, to: now).year,
              (1...120).contains(age) else {
            return .success(nil)
        }
        return .success(CardioFitnessProfile(ageYears: age, sex: sex))
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
        case .vitals:
            return .sleep
        case .cardioFitness:
            return .cardioFitness
        }
    }

    /// Kind → permission category. The mapping itself lives in the shared
    /// `BodyHealthSourceResolver` (Body + BodyWatch) so the watch's own compute
    /// gates each kind exactly as the phone does.
    func healthPermission(forSourceKind kind: HealthMetricKind) -> BodyHealthPermission {
        BodyHealthSourceResolver.permission(forSourceKind: kind)
    }

    private func healthSampleType(forSourceKind kind: HealthMetricKind) -> HKSampleType? {
        healthSampleTypes(forSourceKind: kind).first
    }

    /// Kind → the sample types source discovery fans over. Shared with the
    /// watch via `BodyHealthSourceResolver` so both sides discover — and
    /// therefore key — the same sources for a kind.
    func healthSampleTypes(forSourceKind kind: HealthMetricKind) -> [HKSampleType] {
        BodyHealthSourceResolver.sourceSampleTypes(for: kind)
    }

    // MARK: - Predicates

    /// The decision logic lives in the shared `BodyHealthSourceResolver` (Body +
    /// BodyWatch); this alias keeps the engine's own spelling of the result type.
    typealias SourceQueryResolution = BodyHealthSourceQueryResolution

    /// Resolves this metric's selected source against the sources discovered on
    /// the actor (`healthSourcesByKind`). iOS passes `strictWhenMissing: false`:
    /// a selection whose id is absent from a SUCCESSFUL discovery means the
    /// source is genuinely gone, so the query widens to all sources. (The watch
    /// passes `true` — see `BodyHealthSourceResolver.resolution`.) An absent
    /// bucket still means discovery never succeeded this process, which stays
    /// `.unresolved` so leaves skip with failure semantics (H4).
    func sourceQueryResolution(
        for kind: HealthMetricKind,
        option explicitOption: BodyHealthDataSourceOption? = nil
    ) -> SourceQueryResolution {
        let option = explicitOption ?? healthDataSourceSelection.option(for: kind)
        // Body Pro gate at the fetch chokepoint, mirroring the secondary gate in
        // `selectedSecondaryHealthDataSourceOption`: a lapsed subscription keeps
        // the user-created group definition but every query widens back to all
        // sources, so the filtering stops without the selection being erased.
        guard !option.isCustomSource || BodyProEntitlement.isUnlocked else {
            return .allSources
        }

        return BodyHealthSourceResolver.resolution(
            option: option,
            discovered: healthSourcesByKind[kind],
            strictWhenMissing: false
        )
    }

    /// Whether a metric's source selection is unresolved — a specific source is
    /// chosen but discovery has not succeeded for this kind this process. Leaf
    /// fetches consult this to skip the query with failure semantics (keeping
    /// the cache) instead of querying all sources through a nil predicate.
    func sourceSelectionUnresolved(
        for kind: HealthMetricKind,
        option explicitOption: BodyHealthDataSourceOption? = nil
    ) -> Bool {
        if case .unresolved = sourceQueryResolution(for: kind, option: explicitOption) {
            return true
        }
        return false
    }

    private func sourcePredicate(for kind: HealthMetricKind) -> NSPredicate? {
        sourcePredicate(for: kind, option: nil)
    }

    private func sourcePredicate(
        for kind: HealthMetricKind,
        option explicitOption: BodyHealthDataSourceOption? = nil
    ) -> NSPredicate? {
        if case .predicate(let predicate) = sourceQueryResolution(for: kind, option: explicitOption) {
            return predicate
        }
        return nil
    }

    /// The window + source predicate a leaf query runs with. The combining
    /// itself lives in the shared `BodyHealthSourceResolver` so the watch builds
    /// identical predicates; the engine resolves the source side from its actor
    /// state first.
    func combinedPredicate(
        startDate: Date? = nil,
        endDate: Date? = nil,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil
    ) -> NSPredicate? {
        var resolvedSourcePredicate: NSPredicate?
        if let sourceKind {
            if let sourceOption {
                resolvedSourcePredicate = sourcePredicate(for: sourceKind, option: sourceOption)
            } else {
                resolvedSourcePredicate = sourcePredicate(for: sourceKind)
            }
        }

        return BodyHealthSourceResolver.combinedPredicate(
            startDate: startDate,
            endDate: endDate,
            sourcePredicate: resolvedSourcePredicate
        )
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

    /// Window for lazy-loaded intraday raw/hourly samples (the per-metric
    /// detail chart). Unlike the 365-day daily trend charts, the intraday
    /// picker is only reachable across the recent-month window
    /// (`BodyHealthMetricDetailView` uses `BodyHealthTrendRange.recentMonth`),
    /// so fetching raw samples over the full trend window pulls tens of
    /// thousands of samples the UI never shows. Cover the recent-month reach
    /// plus a two-day margin for the 48h incremental overlap; daily trend
    /// charts are unaffected (they use `recentHealthTrendInterval`).
    func intradayDaySampleInterval(calendar: Calendar, date: Date = Date()) -> (start: Date, end: Date) {
        Self.intradayDaySampleInterval(calendar: calendar, anchor: anchorDate, date: date)
    }

    nonisolated static func intradayDaySampleInterval(
        calendar: Calendar,
        anchor: Date?,
        date: Date = Date()
    ) -> (start: Date, end: Date) {
        let anchorOrDate = anchor ?? date
        let end = anchorOrDate
        let currentDayStart = calendar.startOfDay(for: anchorOrDate)
        let oldestPastOffset = BodyHealthTrendRange.recentMonth.dayCount + 2
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
        let option = healthDataSourceSelection.option(for: kind)
        // Same Body Pro gate as `sourceQueryResolution`, so the option this
        // reports (secondary de-duplication, day-sample signatures) matches what
        // the queries actually ran with while the subscription is lapsed.
        guard !option.isCustomSource || BodyProEntitlement.isUnlocked else {
            return .allSources
        }

        return resolvedHealthDataSourceOption(option, for: kind)
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

    /// nil `discoveredNonemptyIDs` = discovery unresolved for this kind → keep the
    /// stored option so leaf queries skip with failure semantics via
    /// `sourceSelectionUnresolved` (H4). Discovered-but-absent (or empty bucket) →
    /// `absentFallback` (`.allSources` / `.noComparison`).
    nonisolated static func resolvedSourceOption(
        _ option: BodyHealthDataSourceOption,
        discoveredNonemptyIDs: Set<String>?,
        absentFallback: BodyHealthDataSourceOption
    ) -> BodyHealthDataSourceOption {
        guard let ids = discoveredNonemptyIDs else {
            return option
        }
        guard ids.contains(option.id) else {
            return absentFallback
        }
        return option
    }

    /// IDs whose `[HKSource]` bucket is non-empty for this kind, mirroring
    /// `sourceQueryResolution`'s `!sources.isEmpty` rule. Absent
    /// `healthSourcesByKind[kind]` (discovery unresolved this process) yields nil.
    private func discoveredNonemptyHealthSourceIDs(for kind: HealthMetricKind) -> Set<String>? {
        healthSourcesByKind[kind].map { bucket in
            Set(bucket.filter { !$0.value.isEmpty }.keys)
        }
    }

    /// Per kind, the user-created group ids that registered a non-empty bucket —
    /// the store caches this so its synchronous render-time resolution collapses
    /// a member-less group to All Sources exactly where a query would. A kind
    /// whose discovery has not succeeded is ABSENT rather than empty, matching
    /// the nil-bucket "keep the stored option" contract above.
    func customHealthSourceIDsWithData() -> [HealthMetricKind: Set<String>] {
        let groupIDs = Set(customHealthSourceGroups.map(\.id))
        var result: [HealthMetricKind: Set<String>] = [:]
        for kind in healthSourcesByKind.keys {
            guard let discoveredIDs = discoveredNonemptyHealthSourceIDs(for: kind) else {
                continue
            }
            result[kind] = groupIDs.intersection(discoveredIDs)
        }
        return result
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

        // Discovery hasn't populated this kind yet (nil bucket) — keep the stored
        // selection so leaf queries skip with failure semantics (H4) rather than
        // collapsing to All Sources. Only a discovered-and-absent source falls back.
        return Self.resolvedSourceOption(
            option,
            discoveredNonemptyIDs: discoveredNonemptyHealthSourceIDs(for: kind),
            absentFallback: .allSources
        )
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

        // Discovery hasn't populated this kind yet — keep the stored secondary
        // selection so leaf queries skip with failure semantics (H4) instead of
        // collapsing to No Comparison. Only a discovered-and-absent source falls back.
        return Self.resolvedSourceOption(
            option,
            discoveredNonemptyIDs: discoveredNonemptyHealthSourceIDs(for: kind),
            absentFallback: .noComparison
        )
    }

    // MARK: - Quantity / sample helpers

    /// How a day's samples collapse into that day's value. Defined in the
    /// shared `BodyDailyQuantityAggregation` (Body + BodyWatch) so both sides
    /// run the same statistics options + statistic read-back; aliased here for
    /// the engine's existing call sites.
    typealias DailyQuantityAggregation = BodyDailyQuantityAggregation

    func fetchDailyQuantitySeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendSeries? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind, option: sourceOption) {
            return nil
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )

        // `nil` on failure keeps the caller's cached series (see
        // `resolvedTrendSeries`); the statistics-collection query itself lives
        // in the shared `BodyHealthQuantityFetch`.
        switch await BodyHealthQuantityFetch.dailyQuantitySeries(
            store: healthStore,
            quantityType: quantityType,
            predicate: predicate,
            aggregation: aggregation,
            unit: unit,
            start: interval.start,
            end: interval.end,
            calendar: calendar,
            valueTransform: valueTransform,
            onFailure: { Self.logTrendQueryFailure(identifier.rawValue, error: $0) }
        ) {
        case .failure:
            return nil
        case .success(let series):
            return series
        }
    }

    func fetchDailyQuantityRangeSeries(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        sourceOption: BodyHealthDataSourceOption? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> HealthTrendRangeSeries? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }
        // Unresolved source selection: `nil` (a query failure) so the caller keeps
        // the cached series rather than silently querying all sources, matching
        // the primary `fetchDailyQuantitySeries` convention.
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind, option: sourceOption) {
            return nil
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

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: nil)
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
    ) async -> (HealthTrendSeries, HealthTrendRangeSeries)? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return (.empty, .empty)
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind, option: sourceOption) {
            return nil
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

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: nil)
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
    ) async -> QueryOutcome<HealthMetricSummary> {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind) {
            return .failure
        }

        let predicate = combinedPredicate(startDate: startDate, endDate: endDate, sourceKind: sourceKind)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: .failure)
                    return
                }
                let quantitySamples = samples.compactMap { $0 as? HKQuantitySample }
                guard let value = Self.dailyQuantityValue(
                    from: quantitySamples,
                    unit: unit,
                    aggregation: aggregation,
                    valueTransform: valueTransform
                ) else {
                    continuation.resume(returning: .success(nil))
                    return
                }

                continuation.resume(returning: .success(HealthMetricSummary(value: value)))
            }

            healthStore.execute(query)
        }
    }

    /// The most recent DAY's value over the trend window (not the most recent
    /// sample) — the headline for metrics whose card reads a daily aggregate.
    private func dailyQuantitySummary(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        aggregation: DailyQuantityAggregation,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> QueryOutcome<HealthMetricSummary> {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind) {
            return .failure
        }

        let interval = recentHealthTrendInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: interval.start,
            endDate: interval.end,
            sourceKind: sourceKind
        )

        switch await BodyHealthQuantityFetch.dailyQuantitySummary(
            store: healthStore,
            quantityType: quantityType,
            predicate: predicate,
            aggregation: aggregation,
            unit: unit,
            start: interval.start,
            end: interval.end,
            calendar: calendar,
            valueTransform: valueTransform,
            onFailure: { Self.logTrendQueryFailure(identifier.rawValue, error: $0) }
        ) {
        case .failure:
            return .failure
        case .success(let summary):
            return .success(summary)
        }
    }

    private func dailyCumulativeQuantitySummary(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        calendar: Calendar,
        sourceKind: HealthMetricKind? = nil,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) async -> QueryOutcome<HealthMetricSummary> {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind) {
            return .failure
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

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: .failure)
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

                continuation.resume(returning: .success(latestValue.map { HealthMetricSummary(value: $0) }))
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
    ) async -> HealthTrendSeries? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind, option: sourceOption) {
            return nil
        }

        let interval = intradayDaySampleInterval(calendar: calendar)
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

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: nil)
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
    ) async -> HealthTrendSeries? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind, option: sourceOption) {
            return nil
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

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: nil)
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
    ) async -> QueryOutcome<HealthMetricSummary> {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind) {
            return .failure
        }

        // No date predicate: the newest sample counts however old it is. The
        // shared leaf returns the sample itself so callers that need the real
        // reading time (the watch stamps freshness from it) can use it.
        let predicate = combinedPredicate(sourceKind: sourceKind)

        switch await BodyHealthQuantityFetch.latestQuantitySample(
            store: healthStore,
            quantityType: quantityType,
            predicate: predicate,
            onFailure: { Self.logTrendQueryFailure(identifier.rawValue, error: $0) }
        ) {
        case .failure:
            return .failure
        case .success(let sample):
            guard let sample else {
                return .success(nil)
            }
            let value = sample.quantity.doubleValue(for: unit)
            return .success(HealthMetricSummary(value: valueTransform(value), measuredAt: sample.endDate))
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
    ) async -> HealthTrendSeries? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .empty
        }
        if let sourceKind, sourceSelectionUnresolved(for: sourceKind, option: sourceOption) {
            return nil
        }

        let interval = intradayDaySampleInterval(calendar: calendar)
        let predicate = combinedPredicate(
            startDate: startDate ?? interval.start,
            endDate: endDate ?? interval.end,
            sourceKind: sourceKind,
            sourceOption: sourceOption
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        // Cancellation (dismissed detail view, superseded refresh) stops the
        // in-flight query and resumes with `nil` — the same as a query failure —
        // so the store keeps the cached intraday series rather than merging a
        // partial one. See `runCancellableQuery`.
        return await runCancellableQuery(cancelledValue: nil) { resume in
            HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    resume(nil)
                    return
                }
                let points = samples.compactMap { sample -> HealthTrendDataPoint? in
                    guard let quantitySample = sample as? HKQuantitySample else {
                        return nil
                    }
                    let value = valueTransform(quantitySample.quantity.doubleValue(for: unit))
                    guard value.isFinite else {
                        return nil
                    }

                    return HealthTrendDataPoint(date: quantitySample.endDate, value: value)
                }

                resume(HealthTrendSeries(points: points))
            }
        }
    }

    /// Today's earliest past-threshold episode for one warning kind, backing the
    /// Home card's warning badge. A dedicated cheap query — for heart rate
    /// HealthKit filters on the threshold itself — so Home never waits for the
    /// lazily loaded intraday samples. Sample dates match the intraday series
    /// (`endDate`). `intervals` are dropped from detection (today's workouts for
    /// the high heart rate kind).
    /// The limit today's detection runs against: the user's Settings override,
    /// else the default (zone 3's lower bound for high heart rate). Read straight
    /// from `UserDefaults.standard` — the suite the app's `@AppStorage` uses — so
    /// the engine doesn't need the value pushed in on every change.
    private func warningThreshold(for kind: MetricWarningKind) -> Double {
        let rawValue = UserDefaults.standard
            .string(forKey: BodyAppearancePreference.metricWarningThresholdsKey) ?? ""
        return BodyMetricWarningThresholds.storedValue(from: rawValue)
            .threshold(
                for: kind,
                maxHeartRate: kind == .highHeartRate ? userMaxHeartRate() : nil
            )
    }

    private func fetchTodayMetricWarning(
        _ kind: MetricWarningKind,
        calendar: Calendar,
        excluding intervals: [DateInterval] = []
    ) async -> QueryOutcome<MetricWarningEvent> {
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        let valueTransform: @Sendable (Double) -> Double
        switch kind.metric {
        case .heartRate:
            identifier = .heartRate
            unit = HKUnit.count().unitDivided(by: .minute())
            valueTransform = { $0 }
        case .oxygenSaturation:
            identifier = .oxygenSaturation
            unit = .percent()
            valueTransform = { Self.normalizedPercentDisplayValue($0) }
        default:
            return .success(nil)
        }
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }
        if sourceSelectionUnresolved(for: kind.metric) {
            return .failure
        }

        let thresholdValue = warningThreshold(for: kind)
        let now = anchorDate ?? Date()
        let windowPredicate = combinedPredicate(
            startDate: calendar.startOfDay(for: now),
            endDate: now,
            sourceKind: kind.metric
        )
        // Heart rate is dense (thousands of samples a day), so HealthKit does the
        // threshold filtering. Blood oxygen is sparse AND stored either as a 0–1
        // fraction or as 0–100 depending on the source, so a native-unit
        // threshold predicate would silently miss whole sources: fetch the day
        // and normalise (`valueTransform`) before comparing.
        let thresholdPredicate: NSPredicate? = kind.metric == .heartRate
            ? HKQuery.predicateForQuantitySamples(
                with: kind.isAbove ? .greaterThan : .lessThan,
                quantity: HKQuantity(unit: unit, doubleValue: thresholdValue)
            )
            : nil
        let predicate: NSPredicate?
        switch (windowPredicate, thresholdPredicate) {
        case (let window?, let threshold?):
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, threshold])
        case (let window?, nil):
            predicate = window
        case (nil, let threshold):
            predicate = threshold
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        // Cancellation resumes with `.failure`, like a query failure, so the
        // resolver keeps the cached event instead of clearing the badge from a
        // partial result. See `runCancellableQuery`.
        return await runCancellableQuery(cancelledValue: .failure) { resume in
            HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    resume(.failure)
                    return
                }
                let points = samples.compactMap { sample -> HealthTrendDataPoint? in
                    guard let quantitySample = sample as? HKQuantitySample else {
                        return nil
                    }
                    let value = valueTransform(quantitySample.quantity.doubleValue(for: unit))
                    guard value.isFinite else {
                        return nil
                    }

                    return HealthTrendDataPoint(date: quantitySample.endDate, value: value)
                }

                // Nothing past the threshold → `.success(nil)`, which clears a
                // stale cached event rather than keeping yesterday's badge.
                resume(.success(MetricThresholdWarning.detect(
                    kind,
                    inSamples: points,
                    threshold: thresholdValue,
                    excluding: intervals
                )))
            }
        }
    }

    /// High heart rate only counts readings taken while inactive, so it needs an
    /// authoritative list of today's workouts: an unreadable workout list fails
    /// the warning (keeping the cached one) rather than detecting as if the user
    /// had been at rest all day.
    private func fetchTodayHighHeartRateWarning(calendar: Calendar) async -> QueryOutcome<MetricWarningEvent> {
        // Workouts are never source-selectable (see `BodyWorkoutFetch`), so the
        // permission is the only gate. With it off there is no workout coverage
        // to exclude against, so the warning is skipped — and cleared — rather
        // than failing the whole refresh over an intentionally disabled input.
        guard permissionSelection.includes(.workouts) else {
            return .success(nil)
        }

        switch await fetchTodayWorkoutIntervals(calendar: calendar) {
        case .failure:
            return .failure
        case .success(let intervals):
            return await fetchTodayMetricWarning(.highHeartRate, calendar: calendar, excluding: intervals ?? [])
        }
    }

    /// Today's workout intervals, for excluding in-workout readings from a
    /// warning. `workoutPredicate` is strict-start, so the query reaches back a
    /// day and keeps whatever overlaps today — an overnight session that began
    /// yesterday still masks this morning's readings.
    private func fetchTodayWorkoutIntervals(calendar: Calendar) async -> QueryOutcome<[DateInterval]> {
        let now = anchorDate ?? Date()
        let startOfToday = calendar.startOfDay(for: now)
        let predicate = BodyWorkoutFetch.workoutPredicate(
            start: startOfToday.addingTimeInterval(-86_400),
            end: now
        )
        let sort = BodyWorkoutFetch.startDateAscendingSort

        // Cancellation resumes with `.failure` so the warning that depends on
        // this list is failed too. See `runCancellableQuery`.
        return await runCancellableQuery(cancelledValue: .failure) { resume in
            HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let workouts = samples as? [HKWorkout] else {
                    Self.logTrendQueryFailure(HKObjectType.workoutType().identifier, error: error)
                    resume(.failure)
                    return
                }
                let intervals = workouts.compactMap { workout -> DateInterval? in
                    guard workout.startDate < now,
                          workout.endDate > startOfToday,
                          workout.startDate <= workout.endDate else {
                        return nil
                    }
                    return MetricThresholdWarning.workoutExclusionInterval(start: workout.startDate, end: workout.endDate)
                }

                resume(.success(intervals))
            }
        }
    }

    // MARK: - Cancellable queries

    /// Runs an `HKQuery` built by `makeQuery` under Task cancellation. `makeQuery`
    /// receives a `resume` closure it must call exactly once from the query's
    /// callback; on cancellation the in-flight query is stopped and `cancelledValue`
    /// is resumed instead. Both call sites build the query INSIDE the continuation,
    /// so cancellation can land before the query is installed — a lock-protected
    /// state machine installs the query only if cancellation hasn't already fired,
    /// resumes exactly once, and drops a late HealthKit callback.
    func runCancellableQuery<Value>(
        cancelledValue: @Sendable @autoclosure @escaping () -> Value,
        makeQuery: (@escaping (Value) -> Void) -> HKQuery
    ) async -> Value {
        let coordinator = CancellableQueryCoordinator<Value>(
            execute: { [healthStore] in healthStore.execute($0) },
            stop: { [healthStore] in healthStore.stop($0) }
        )
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                coordinator.install(
                    continuation: continuation,
                    cancelledValue: cancelledValue(),
                    makeQuery: makeQuery
                )
            }
        } onCancel: {
            coordinator.cancel(cancelledValue: cancelledValue())
        }
    }

    // MARK: - Workouts

    func fetchWorkouts(
        month: Int,
        year: Int,
        calendar: Calendar,
        allowsHeartRateReuse: Bool = false,
        reusableSummariesByID: [UUID: WorkoutSummary] = [:]
    ) async throws -> [WorkoutSummary] {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return try await fetchWorkoutSummaries(
            startDate: start,
            endDate: end,
            includesHeartRateSamples: true,
            allowsHeartRateReuse: allowsHeartRateReuse,
            reusableSummariesByID: reusableSummariesByID
        )
    }

    func fetchWorkoutSummaries(
        startDate: Date,
        endDate: Date,
        includesHeartRateSamples: Bool,
        includesDetailMetrics: Bool = true,
        allowsHeartRateReuse: Bool = false,
        reusableSummariesByID: [UUID: WorkoutSummary] = [:]
    ) async throws -> [WorkoutSummary] {
        // Window + ordering come from the shared `BodyWorkoutFetch` so the
        // watch's delta fetch covers exactly the same workouts (the mapping
        // below shares `BodyWorkoutFetch.summary(for:)` with it too).
        let predicate = BodyWorkoutFetch.workoutPredicate(start: startDate, end: endDate)
        let sort = BodyWorkoutFetch.startDateAscendingSort

        // Cancellation (superseded refresh, dismissed month) stops the in-flight
        // query and throws `CancellationError`, so the caller (and training load)
        // treats it as a failure and keeps its cache rather than blanking the
        // month. See `runCancellableQuery`.
        let workoutsResult: Result<[HKWorkout], Error> = await runCancellableQuery(
            cancelledValue: .failure(CancellationError())
        ) { resume in
            HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    resume(.failure(error))
                    return
                }

                resume(.success(samples as? [HKWorkout] ?? []))
            }
        }
        let workouts = try workoutsResult.get()

        guard !workouts.isEmpty else {
            return []
        }

        // Finished workouts whose HR payload was already fetched this session
        // skip the batched HR query — passive resumes only (`allowsHeartRateReuse`;
        // user-initiated paths pass `false`, so every pull-to-refresh remains a
        // full HR reconcile). `reusableSummariesByID` is now always supplied (the
        // effort/HR failure fallback below reads it), so the HR-reuse skip gates
        // on the explicit flag rather than the map being non-empty. The workout
        // list above is always fetched fresh.
        let reusedHeartRateIDs: Set<UUID>
        if includesHeartRateSamples,
           allowsHeartRateReuse,
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
        // way HR samples can). A `nil` HR result means the batched query failed
        // (device locked, XPC drop) — distinct from an empty result — so the
        // assembly can reuse each workout's cached payload instead of blanking.
        async let heartRateSamplesByWorkoutID: [UUID: [WorkoutHeartRateSample]]? = {
            guard includesHeartRateSamples, !workoutsNeedingHeartRate.isEmpty else {
                return [UUID: [WorkoutHeartRateSample]]()
            }
            // Permission-off yields an empty (non-nil) map — never a failure — so
            // the HR-batch-failure reuse below only triggers on a real error.
            return await fetchIfPermitted(.heart, default: [UUID: [WorkoutHeartRateSample]]()) {
                await fetchHeartRateSamples(forWorkouts: workoutsNeedingHeartRate)
            }
        }()
        async let fetchedEffortLevels = fetchEffortLevels(forWorkouts: workouts)
        // Cardio Fitness + foot cadence are only consumed by the workout detail
        // card, so callers that don't surface them (training load) pass
        // `includesDetailMetrics: false` to skip these reads entirely — otherwise
        // the training-load window would pay a per-workout step query it
        // never reads. When they DO run, they cover *every* workout (like effort
        // levels above), NOT just the non-reused `workoutsNeedingHeartRate` set:
        // only the expensive HR-sample payload keeps the passive-resume reuse
        // skip. A workout cached before these fields existed decodes their values
        // as nil, so gating them on the HR skip would leave a reused workout
        // permanently missing them until a user-initiated refresh; fetching for
        // all workouts backfills those on the next passive resume. The reuse
        // branch below no longer resurrects a cached detail field on a
        // permission-gated read: a permission-off read yields a genuine
        // `nil`/empty (see `fetchIfPermitted` below), not a failure, and
        // `includesWorkoutMetrics` nils the fields in the summary constructor.
        // VO₂max returns `nil` on a query FAILURE (like the HR batch); cadence and
        // distance return the per-workout `failedIDs` set. A `.workoutMetrics`-off
        // (or `.workouts`-off) selection yields a genuine empty, never a failure.
        async let cardioFitnessByWorkoutID: [UUID: Double]? = {
            guard includesDetailMetrics else { return [:] }
            return await fetchIfPermitted(.workoutMetrics, default: [:]) {
                await fetchCardioFitness(forWorkouts: workouts)
            }
        }()
        async let stepCadenceByWorkoutID: (values: [UUID: Double], failedIDs: Set<UUID>) = {
            guard includesDetailMetrics else { return (values: [:], failedIDs: []) }
            return await fetchIfPermitted(.workoutMetrics, default: (values: [:], failedIDs: [])) {
                await fetchStepCadence(forWorkouts: workouts)
            }
        }()
        async let workoutDistanceByWorkoutID: (values: [UUID: Double], failedIDs: Set<UUID>) = {
            guard includesDetailMetrics else { return (values: [:], failedIDs: []) }
            return await fetchIfPermitted(.workouts, default: (values: [:], failedIDs: [])) {
                await fetchWorkoutDistances(forWorkouts: workouts)
            }
        }()

        let resolvedHeartRateSamples = await heartRateSamplesByWorkoutID
        let (resolvedEffortLevels, failedEffortIDs) = await fetchedEffortLevels
        let resolvedCardioFitness = await cardioFitnessByWorkoutID
        let (resolvedStepCadence, failedStepCadenceIDs) = await stepCadenceByWorkoutID
        let (resolvedWorkoutDistance, failedWorkoutDistanceIDs) = await workoutDistanceByWorkoutID
        let includesWorkoutMetrics = permissionSelection.includes(.workoutMetrics)
        // Heart-rate recovery comes from the workout's attached statistics (no extra
        // query), but it's heart data — so it rides the Heart toggle like the samples.
        let includesHeartMetrics = permissionSelection.includes(.heart)
        // The batched HR query failed (not empty) — reuse cached payloads below.
        let heartRateBatchFailed = includesHeartRateSamples && resolvedHeartRateSamples == nil
        // The whole VO₂max query failed — reuse each workout's cached value below.
        let cardioFitnessFailed = resolvedCardioFitness == nil

        var summaries: [WorkoutSummary] = []
        summaries.reserveCapacity(workouts.count)
        for workout in workouts {
            let cachedSummary = reusableSummariesByID[workout.uuid]
            let effortLevel = Self.resolvedWorkoutEffortLevel(
                fetchedEffort: resolvedEffortLevels[workout.uuid],
                workoutFailed: failedEffortIDs.contains(workout.uuid),
                cachedEffort: cachedSummary?.effortLevel
            )
            // Stored as `true` only when unresolved, else `nil` (never `false`), so
            // a resolved workout stays byte-identical to a legacy snapshot that
            // predates the field and the M10 dedupe only re-saves on a real flip.
            let effortUnresolved: Bool? = Self.resolvedWorkoutEffortUnresolved(
                fetchedEffort: resolvedEffortLevels[workout.uuid],
                workoutFailed: failedEffortIDs.contains(workout.uuid),
                cachedEffort: cachedSummary?.effortLevel
            ) ? true : nil
            // On a query FAILURE for a detail metric, reuse the workout's cached
            // value instead of blanking the field; a successful absence clears it —
            // including in the reuse branch below, which must not resurrect a
            // confirmed-absent field from the cached summary (H12).
            let resolvedVO2 = Self.resolvedWorkoutDetailMetric(
                fetched: resolvedCardioFitness?[workout.uuid],
                failed: cardioFitnessFailed,
                cached: cachedSummary?.cardioFitnessVO2Max
            )
            let resolvedCadence = Self.resolvedWorkoutDetailMetric(
                fetched: resolvedStepCadence[workout.uuid],
                failed: failedStepCadenceIDs.contains(workout.uuid),
                cached: cachedSummary?.averageStepCadenceSPM
            )
            let resolvedDistance = Self.resolvedWorkoutDetailMetric(
                fetched: resolvedWorkoutDistance[workout.uuid],
                failed: failedWorkoutDistanceIDs.contains(workout.uuid),
                cached: cachedSummary?.distanceMeters
            )

            if let cached = cachedSummary,
               reusedHeartRateIDs.contains(workout.uuid) || heartRateBatchFailed {
                summaries.append(
                    BodyWorkoutFetch.summary(
                        for: workout,
                        reusingHeartRateFrom: cached,
                        effortLevel: effortLevel,
                        effortUnresolved: effortUnresolved,
                        cardioFitnessVO2Max: resolvedVO2,
                        averageStepCadenceSPM: resolvedCadence,
                        resolvedDistanceMeters: resolvedDistance,
                        includesWorkoutMetrics: includesWorkoutMetrics,
                        includesHeartMetrics: includesHeartMetrics
                    )
                )
            } else {
                summaries.append(
                    BodyWorkoutFetch.summary(
                        for: workout,
                        heartRateSamples: resolvedHeartRateSamples?[workout.uuid] ?? [],
                        effortLevel: effortLevel,
                        effortUnresolved: effortUnresolved,
                        cardioFitnessVO2Max: resolvedVO2,
                        averageStepCadenceSPM: resolvedCadence,
                        resolvedDistanceMeters: resolvedDistance,
                        includesWorkoutMetrics: includesWorkoutMetrics,
                        includesHeartMetrics: includesHeartMetrics
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
    /// Returns `nil` when the batched heart-rate query itself fails (device
    /// locked, store unavailable) rather than genuinely returning no samples,
    /// so the assembly reuses each workout's cached HR payload instead of
    /// blanking it.
    private func fetchHeartRateSamples(forWorkouts workouts: [HKWorkout]) async -> [UUID: [WorkoutHeartRateSample]]? {
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

        let samples: [HKQuantitySample]? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples else {
                    Self.logTrendQueryFailure("workoutHeartRate", error: error)
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: samples.compactMap { $0 as? HKQuantitySample })
            }

            healthStore.execute(query)
        }

        guard let samples else {
            return nil
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
    /// (`BodyWorkoutEffortFetcher.effortConfirmationAge`) that a rating is no
    /// longer expected — these are confirmed score-less and skipped for the
    /// rest of the process.
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
                .filter { !foundIDs.contains($0.id) && now.timeIntervalSince($0.endDate) > BodyWorkoutEffortFetcher.effortConfirmationAge }
                .map(\.id)
        )
    }

    /// Effort score for a workout, applying the H12 failure fallback: use the
    /// freshly fetched score; on an effort-query FAILURE for a workout with no
    /// fetched score, reuse the cached summary's score so a transient failure
    /// doesn't reset a rated workout to the default. Failed with no prior keeps
    /// `nil` (the default rating), avoiding series holes.
    nonisolated static func resolvedWorkoutEffortLevel(
        fetchedEffort: Double?,
        workoutFailed: Bool,
        cachedEffort: Double?
    ) -> Double? {
        if let fetchedEffort {
            return fetchedEffort
        }
        return workoutFailed ? cachedEffort : nil
    }

    /// Whether a workout's effort is *unresolved* (H12): the effort query FAILED
    /// for a workout with neither a fetched score nor a cached score, so its
    /// `effortLevel` is neither a real rating nor a trustworthy default.
    /// `TrainingLoadCalculator.load` excludes unresolved workouts rather than
    /// counting them as the default effort. A failure that falls back to a cached
    /// score is resolved; a genuine no-score (query succeeded) is unrated, not
    /// unresolved, and keeps the intentional default.
    nonisolated static func resolvedWorkoutEffortUnresolved(
        fetchedEffort: Double?,
        workoutFailed: Bool,
        cachedEffort: Double?
    ) -> Bool {
        fetchedEffort == nil && workoutFailed && cachedEffort == nil
    }

    /// Detail metric (VO₂max, step cadence, distance) for a workout, applying
    /// the H12 failure fallback: on a query FAILURE, reuse the cached value;
    /// on success, use the fetched value — including `nil`, which is a
    /// CONFIRMED absence and must clear the field rather than fall back to a
    /// stale cached value.
    nonisolated static func resolvedWorkoutDetailMetric(
        fetched: Double?,
        failed: Bool,
        cached: Double?
    ) -> Double? {
        failed ? cached : fetched
    }

    private func fetchEffortLevels(
        forWorkouts workouts: [HKWorkout]
    ) async -> (levels: [UUID: Double], failedIDs: Set<UUID>) {
        guard !workouts.isEmpty else {
            return ([:], [])
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
        let (fetched, completedIDs, failedIDs) = await withTaskGroup(
            of: (UUID, BodyWorkoutEffortOutcome).self,
            returning: ([UUID: Double], Set<UUID>, Set<UUID>).self
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
            var failed: Set<UUID> = []
            for await (id, outcome) in group {
                switch outcome {
                case .found(let effort):
                    results[id] = effort
                    completed.insert(id)
                case .noSavedEffort:
                    completed.insert(id)
                case .failed:
                    failed.insert(id)
                }
                if nextIndex < candidates.count {
                    let workout = candidates[nextIndex]
                    group.addTask {
                        (workout.uuid, await self.fetchSavedEffortLevel(for: workout))
                    }
                    nextIndex += 1
                }
            }
            return (results, completed, failed)
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
        // Failed candidates that ended up with a process-cached score (a prior
        // refresh found one) are no longer "failed with no data" — drop them so
        // the assembly only reuses the cached summary for genuinely missing IDs.
        return (levels: results, failedIDs: failedIDs.subtracting(results.keys))
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
    /// Returns `nil` when the sample query itself FAILED (device locked, XPC
    /// drop) — distinct from an empty map — so the assembly reuses each workout's
    /// cached VO₂max instead of blanking it (like `fetchHeartRateSamples`).
    private func fetchCardioFitness(forWorkouts workouts: [HKWorkout]) async -> [UUID: Double]? {
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

        let samplesOutcome: QueryOutcome<[HKQuantitySample]> = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: vo2MaxType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample] else {
                    Self.logTrendQueryFailure(HKQuantityTypeIdentifier.vo2Max.rawValue, error: error)
                    continuation.resume(returning: .failure)
                    return
                }
                continuation.resume(returning: .success(samples))
            }
            healthStore.execute(query)
        }

        let samples: [HKQuantitySample]
        switch samplesOutcome {
        case .failure:
            return nil
        case .success(let value):
            samples = value ?? []
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
    private func fetchStepCadence(
        forWorkouts workouts: [HKWorkout]
    ) async -> (values: [UUID: Double], failedIDs: Set<UUID>) {
        let eligible = workouts.filter {
            HealthKitWorkoutStore.workoutType(for: $0.workoutActivityType).supportsStepCadence
                && $0.duration > 0
        }
        guard !eligible.isEmpty,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return (values: [:], failedIDs: [])
        }

        let maxConcurrentQueries = 12
        return await withTaskGroup(
            of: (UUID, QueryOutcome<Double>).self,
            returning: (values: [UUID: Double], failedIDs: Set<UUID>).self
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
            var failed: Set<UUID> = []
            for await (id, outcome) in group {
                switch outcome {
                case .success(let cadence):
                    if let cadence {
                        results[id] = cadence
                    }
                case .failure:
                    failed.insert(id)
                }
                if nextIndex < eligible.count {
                    let workout = eligible[nextIndex]
                    group.addTask {
                        (workout.uuid, await self.stepCadence(for: workout, stepType: stepType))
                    }
                    nextIndex += 1
                }
            }
            return (values: results, failedIDs: failed)
        }
    }

    /// Steps associated with `workout` (cumulative-sum statistics over the
    /// workout's own samples, deduplicated across sources by HealthKit) divided
    /// by its duration in minutes. `.success(nil)` when no steps are attributed;
    /// `.failure` when the statistics query itself failed (so the assembly reuses
    /// the cached cadence instead of blanking it).
    private func stepCadence(for workout: HKWorkout, stepType: HKQuantityType) async -> QueryOutcome<Double> {
        let minutes = workout.duration / 60
        guard minutes > 0 else { return .success(nil) }

        let totalStepsOutcome: QueryOutcome<Double> = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .cumulativeSum
            ) { _, statistics, error in
                guard let statistics else {
                    Self.logTrendQueryFailure(HKQuantityTypeIdentifier.stepCount.rawValue, error: error)
                    continuation.resume(returning: .failure)
                    return
                }
                continuation.resume(returning: .success(statistics.sumQuantity()?.doubleValue(for: .count())))
            }
            healthStore.execute(query)
        }

        switch totalStepsOutcome {
        case .failure:
            return .failure
        case .success(let totalSteps):
            guard let totalSteps, totalSteps > 0 else { return .success(nil) }
            return .success(totalSteps / minutes)
        }
    }

    /// Total distance (m) per distance-tracking workout that lacks the legacy
    /// `totalDistance` aggregate. Like step cadence, distance can live only in the
    /// workout's *associated* samples (not `HKWorkout.statistics(for:)`), so it's
    /// read per workout via `predicateForObjects(from:)` + `.cumulativeSum`,
    /// source-deduplicated by HealthKit. One query per workout, bounded concurrency.
    private func fetchWorkoutDistances(
        forWorkouts workouts: [HKWorkout]
    ) async -> (values: [UUID: Double], failedIDs: Set<UUID>) {
        let eligible = workouts.filter {
            $0.totalDistance == nil
                && BodyWorkoutFetch.distanceQuantityTypeIdentifier(
                    for: HealthKitWorkoutStore.workoutType(for: $0.workoutActivityType)
                ) != nil
        }
        guard !eligible.isEmpty else { return (values: [:], failedIDs: []) }

        let maxConcurrentQueries = 12
        return await withTaskGroup(
            of: (UUID, QueryOutcome<Double>).self,
            returning: (values: [UUID: Double], failedIDs: Set<UUID>).self
        ) { group in
            var nextIndex = 0
            while nextIndex < min(maxConcurrentQueries, eligible.count) {
                let workout = eligible[nextIndex]
                group.addTask { (workout.uuid, await self.workoutDistanceMeters(for: workout)) }
                nextIndex += 1
            }

            var results: [UUID: Double] = [:]
            var failed: Set<UUID> = []
            for await (id, outcome) in group {
                switch outcome {
                case .success(let distance):
                    if let distance {
                        results[id] = distance
                    }
                case .failure:
                    failed.insert(id)
                }
                if nextIndex < eligible.count {
                    let workout = eligible[nextIndex]
                    group.addTask { (workout.uuid, await self.workoutDistanceMeters(for: workout)) }
                    nextIndex += 1
                }
            }
            return (values: results, failedIDs: failed)
        }
    }

    /// Distance (m) attributed to `workout`'s own samples — cumulative-sum over the
    /// activity's distance type. `.success(nil)` when no distance is attributed;
    /// `.failure` when the statistics query itself failed (so the assembly reuses
    /// the cached distance instead of blanking it).
    private func workoutDistanceMeters(for workout: HKWorkout) async -> QueryOutcome<Double> {
        let type = HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType)
        guard let identifier = BodyWorkoutFetch.distanceQuantityTypeIdentifier(for: type),
              let distanceType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return .success(nil)
        }

        let metersOutcome: QueryOutcome<Double> = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .cumulativeSum
            ) { _, statistics, error in
                guard let statistics else {
                    Self.logTrendQueryFailure(identifier.rawValue, error: error)
                    continuation.resume(returning: .failure)
                    return
                }
                continuation.resume(returning: .success(statistics.sumQuantity()?.doubleValue(for: .meter())))
            }
            healthStore.execute(query)
        }

        switch metersOutcome {
        case .failure:
            return .failure
        case .success(let meters):
            guard let meters, meters > 0 else { return .success(nil) }
            return .success(meters)
        }
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
        selection: BodyDashboardFetchSelection = .defaultValue,
        cachedSummary: HealthSummarySnapshot? = nil
    ) async -> HealthSummaryFetchResult {
        async let activityRings: QueryOutcome<ActivityRingSummary> = fetchDashboardActivityRingsIfNeeded(selection: selection, default: .success(nil)) {
            await fetchActivityRingSummary(calendar: calendar)
        }
        async let sleep: QueryOutcome<SleepSummary> = fetchDashboardMetricIfNeeded(.sleep, selection: selection, default: .success(nil)) {
            await fetchSleepSummary(calendar: calendar)
        }
        async let heartRate: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.heartRate, selection: selection, default: .success(nil)) {
            await latestQuantity(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .heartRate
            )
        }
        async let lowHeartRateWarning: QueryOutcome<MetricWarningEvent> = fetchDashboardMetricIfNeeded(.heartRate, selection: selection, default: .success(nil)) {
            await fetchTodayMetricWarning(.lowHeartRate, calendar: calendar)
        }
        async let highHeartRateWarning: QueryOutcome<MetricWarningEvent> = fetchDashboardMetricIfNeeded(.heartRate, selection: selection, default: .success(nil)) {
            await fetchTodayHighHeartRateWarning(calendar: calendar)
        }
        async let restingHeartRate: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.restingHeartRate, selection: selection, default: .success(nil)) {
            await latestQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .restingHeartRate
            )
        }
        async let bodyMass: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.bodyMass, selection: selection, default: .success(nil)) {
            await latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), sourceKind: .basics)
        }
        async let bodyFatPercentage: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.bodyFatPercentage, selection: selection, default: .success(nil)) {
            await latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let heartRateVariability: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.heartRateVariability, selection: selection, default: .success(nil)) {
            await latestQuantity(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                sourceKind: .heartRateVariability
            )
        }
        async let respiratoryRate: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.respiratoryRate, selection: selection, default: .success(nil)) {
            await latestQuantity(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .respiratoryRate
            )
        }
        async let oxygenSaturation: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.oxygenSaturation, selection: selection, default: .success(nil)) {
            await latestQuantity(
                for: .oxygenSaturation,
                unit: .percent(),
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let lowBloodOxygenWarning: QueryOutcome<MetricWarningEvent> = fetchDashboardMetricIfNeeded(.oxygenSaturation, selection: selection, default: .success(nil)) {
            await fetchTodayMetricWarning(.lowBloodOxygen, calendar: calendar)
        }
        async let bodyMassIndex: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.bodyMassIndex, selection: selection, default: .success(nil)) {
            await latestQuantity(for: .bodyMassIndex, unit: .count(), sourceKind: .basics)
        }
        async let activeEnergy: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.activeEnergy, selection: selection, default: .success(nil)) {
            await dailyCumulativeQuantitySummary(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
        }
        async let restingEnergy: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.restingEnergy, selection: selection, default: .success(nil)) {
            await dailyCumulativeQuantitySummary(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
        }
        async let exerciseMinutes: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.exerciseMinutes, selection: selection, default: .success(nil)) {
            await dailyCumulativeQuantitySummary(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
        }
        async let trainingLoad: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.trainingLoad, selection: selection, default: .success(nil)) {
            await fetchTrainingLoadSummary(calendar: calendar)
        }
        async let wristTemperature: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.wristTemperature, selection: selection, default: .success(nil)) {
            await dailyQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )
        }
        async let timeInDaylight: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.timeInDaylight, selection: selection, default: .success(nil)) {
            await dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )
        }
        async let steps: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.steps, selection: selection, default: .success(nil)) {
            await dailyCumulativeQuantitySummary(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
        }
        async let cardioFitness: QueryOutcome<HealthMetricSummary> = fetchDashboardMetricIfNeeded(.cardioFitness, selection: selection, default: .success(nil)) {
            // `latestQuantity`, not a daily summary: Apple Watch writes one VO₂max
            // estimate every few days at best, so the newest reading is the current
            // value however old it is — a day-scoped summary would read empty most
            // days. No `sourceKind:` either; cardio fitness is deliberately not
            // source-selectable.
            await latestQuantity(for: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
        }
        async let cardioFitnessProfileOutcome: QueryOutcome<CardioFitnessProfile> = fetchDashboardMetricIfNeeded(.cardioFitness, selection: selection, default: .success(nil)) {
            await cardioFitnessProfile()
        }

        // Resolve each leaf against the cached value: a `.failure` keeps the
        // cached field (only when the store passed `cachedSummary`, i.e. the
        // primary-source + permission signature still matches), a `.success`
        // — including a confirmed-absent / off value — replaces it. If ANY
        // leaf failed, the store skips advancing the freshness TTL so the next
        // resume retries instead of trusting a partial result.
        var anyLeafFailed = false
        func resolve<Value>(_ outcome: QueryOutcome<Value>, _ cached: Value?) -> Value? {
            if outcome.isFailure {
                anyLeafFailed = true
            }
            return Self.resolvedSummaryValue(fetched: outcome, cached: cached)
        }

        let resolvedActivityRings = resolve(await activityRings, cachedSummary?.activityRings)
        let resolvedSleep = resolve(await sleep, cachedSummary?.sleep)
        let resolvedHeartRate = resolve(await heartRate, cachedSummary?.heartRate)
        let resolvedHeartRateLowWarning = resolve(await lowHeartRateWarning, cachedSummary?.warning(.lowHeartRate))
        let resolvedHeartRateHighWarning = resolve(await highHeartRateWarning, cachedSummary?.warning(.highHeartRate))
        let resolvedBloodOxygenLowWarning = resolve(await lowBloodOxygenWarning, cachedSummary?.warning(.lowBloodOxygen))
        let resolvedRestingHeartRate = resolve(await restingHeartRate, cachedSummary?.restingHeartRate)
        let resolvedBodyMass = resolve(await bodyMass, cachedSummary?.bodyMass)
        let resolvedBodyFatPercentage = resolve(await bodyFatPercentage, cachedSummary?.bodyFatPercentage)
        let resolvedHeartRateVariability = resolve(await heartRateVariability, cachedSummary?.heartRateVariability)
        let resolvedRespiratoryRate = resolve(await respiratoryRate, cachedSummary?.respiratoryRate)
        let resolvedOxygenSaturation = resolve(await oxygenSaturation, cachedSummary?.oxygenSaturation)
        let resolvedBodyMassIndex = resolve(await bodyMassIndex, cachedSummary?.bodyMassIndex)
        let resolvedActiveEnergy = resolve(await activeEnergy, cachedSummary?.activeEnergy)
        let resolvedRestingEnergy = resolve(await restingEnergy, cachedSummary?.restingEnergy)
        let resolvedExerciseMinutes = resolve(await exerciseMinutes, cachedSummary?.exerciseMinutes)
        let resolvedTrainingLoad = resolve(await trainingLoad, cachedSummary?.trainingLoad)
        let resolvedWristTemperature = resolve(await wristTemperature, cachedSummary?.wristTemperature)
        let resolvedTimeInDaylight = resolve(await timeInDaylight, cachedSummary?.timeInDaylight)
        let resolvedSteps = resolve(await steps, cachedSummary?.steps)
        let resolvedCardioFitness = resolve(await cardioFitness, cachedSummary?.cardioFitness)
        let resolvedCardioFitnessProfile = resolve(await cardioFitnessProfileOutcome, cachedSummary?.cardioFitnessProfile)

        let snapshot = HealthSummarySnapshot(
            activityRings: resolvedActivityRings ?? HealthSummarySnapshot.empty.activityRings,
            sleep: resolvedSleep ?? HealthSummarySnapshot.empty.sleep,
            heartRate: resolvedHeartRate ?? HealthSummarySnapshot.empty.heartRate,
            restingHeartRate: resolvedRestingHeartRate ?? HealthSummarySnapshot.empty.restingHeartRate,
            bodyMass: resolvedBodyMass ?? HealthSummarySnapshot.empty.bodyMass,
            bodyFatPercentage: resolvedBodyFatPercentage ?? HealthSummarySnapshot.empty.bodyFatPercentage,
            heartRateVariability: resolvedHeartRateVariability ?? HealthSummarySnapshot.empty.heartRateVariability,
            respiratoryRate: resolvedRespiratoryRate ?? HealthSummarySnapshot.empty.respiratoryRate,
            oxygenSaturation: resolvedOxygenSaturation ?? HealthSummarySnapshot.empty.oxygenSaturation,
            bodyMassIndex: resolvedBodyMassIndex ?? HealthSummarySnapshot.empty.bodyMassIndex,
            activeEnergy: resolvedActiveEnergy ?? HealthSummarySnapshot.empty.activeEnergy,
            restingEnergy: resolvedRestingEnergy ?? HealthSummarySnapshot.empty.restingEnergy,
            exerciseMinutes: resolvedExerciseMinutes ?? HealthSummarySnapshot.empty.exerciseMinutes,
            trainingLoad: resolvedTrainingLoad ?? HealthSummarySnapshot.empty.trainingLoad,
            wristTemperature: resolvedWristTemperature ?? HealthSummarySnapshot.empty.wristTemperature,
            timeInDaylight: resolvedTimeInDaylight ?? HealthSummarySnapshot.empty.timeInDaylight,
            steps: resolvedSteps ?? HealthSummarySnapshot.empty.steps,
            cardioFitness: resolvedCardioFitness ?? HealthSummarySnapshot.empty.cardioFitness,
            cardioFitnessProfile: resolvedCardioFitnessProfile,
            metricWarnings: [
                resolvedHeartRateLowWarning,
                resolvedHeartRateHighWarning,
                resolvedBloodOxygenLowWarning
            ].compactMap { $0 }
        )
        return HealthSummaryFetchResult(summary: snapshot, hadQueryFailure: anyLeafFailed)
    }

    func fetchHealthTrends(
        calendar: Calendar,
        cachedTrends: HealthTrendSnapshot,
        selection: BodyDashboardFetchSelection = .defaultValue
    ) async -> HealthTrendFetchResult {
        // Preserve any intraday daySamples that have already been lazy-loaded for
        // the metric detail views — fetching them is expensive (~50k HR samples)
        // and they are not displayed on the Home dashboard.
        let cachedHeartRateDaySamples = cachedTrends.heartRateDaySamples
        let cachedHeartRateDaySamplesSecondary = cachedTrends.heartRateDaySamplesSecondary
        let cachedHeartRateVariabilityDaySamples = cachedTrends.heartRateVariabilityDaySamples
        let cachedHeartRateVariabilityDaySamplesSecondary = cachedTrends.heartRateVariabilityDaySamplesSecondary
        let cachedRespiratoryRateDaySamples = cachedTrends.respiratoryRateDaySamples
        let cachedOxygenSaturationDaySamples = cachedTrends.oxygenSaturationDaySamples
        let cachedOxygenSaturationDaySamplesSecondary = cachedTrends.oxygenSaturationDaySamplesSecondary
        let cachedActiveEnergyDaySamples = cachedTrends.activeEnergyDaySamples
        let cachedActiveEnergyDaySamplesSecondary = cachedTrends.activeEnergyDaySamplesSecondary
        let cachedStepsDaySamples = cachedTrends.stepsDaySamples
        let cachedStepsDaySamplesSecondary = cachedTrends.stepsDaySamplesSecondary

        async let sleepHistory: SleepHistoryFetchResult = fetchDashboardMetricIfNeeded(.sleep, selection: selection, default: .empty) {
            await fetchDailySleepHistory(calendar: calendar, cachedSleepHistory: cachedTrends.sleepHistory)
        }
        async let sleepHistorySecondary: SleepHistorySnapshot? = fetchSecondaryDashboardMetricIfNeeded(
            for: .sleep,
            selection: selection,
            permission: .sleep,
            default: SleepHistorySnapshot.empty
        ) {
            await fetchSecondarySleepHistory(calendar: calendar)
        }
        async let restingHeartRate: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.restingHeartRate, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate
            )
        }
        async let restingHeartRateSecondary: HealthTrendSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .restingHeartRate,
            selection: selection,
            permission: .heart,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .restingHeartRate, calendar: calendar)
        }
        async let heartRatePair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDashboardMetricIfNeeded(
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
        async let heartRateRangesSecondary: HealthTrendRangeSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .heartRate,
            selection: selection,
            permission: .heart,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .heartRate, calendar: calendar)
        }
        async let bodyMass: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.bodyMass, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )
        }
        async let bodyFatPercentage: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.bodyFatPercentage, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
        }
        async let heartRateVariabilityPair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDashboardMetricIfNeeded(
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
        async let heartRateVariabilityRangesSecondary: HealthTrendRangeSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .heartRateVariability,
            selection: selection,
            permission: .heart,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .heartRateVariability, calendar: calendar)
        }
        async let respiratoryRatePair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDashboardMetricIfNeeded(
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
        async let oxygenSaturationPair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDashboardMetricIfNeeded(
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
        async let oxygenSaturationRangesSecondary: HealthTrendRangeSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .oxygenSaturation,
            selection: selection,
            permission: .bloodOxygen,
            default: HealthTrendRangeSeries.empty
        ) {
            await fetchSecondaryRangeTrend(for: .oxygenSaturation, calendar: calendar)
        }
        async let bodyMassIndex: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.bodyMassIndex, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )
        }
        async let activeEnergy: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.activeEnergy, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
        }
        async let activeEnergySecondary: HealthTrendSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .activeEnergy,
            selection: selection,
            permission: .energy,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .activeEnergy, calendar: calendar)
        }
        async let restingEnergy: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.restingEnergy, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
        }
        async let restingEnergySecondary: HealthTrendSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .restingEnergy,
            selection: selection,
            permission: .energy,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .restingEnergy, calendar: calendar)
        }
        async let exerciseMinutes: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.exerciseMinutes, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
        }
        async let exerciseMinutesSecondary: HealthTrendSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .exerciseMinutes,
            selection: selection,
            permission: .exerciseMinutes,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .exerciseMinutes, calendar: calendar)
        }
        async let trainingLoad: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.trainingLoad, selection: selection, default: HealthTrendSeries.empty) {
            await fetchTrainingLoadSeries(calendar: calendar)
        }
        async let wristTemperature: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.wristTemperature, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyQuantitySeries(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )
        }
        async let timeInDaylight: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.timeInDaylight, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )
        }
        async let steps: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.steps, selection: selection, default: HealthTrendSeries.empty) {
            await fetchDailyCumulativeQuantitySeries(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
        }
        async let stepsSecondary: HealthTrendSeries? = fetchSecondaryDashboardMetricIfNeeded(
            for: .steps,
            selection: selection,
            permission: .steps,
            default: HealthTrendSeries.empty
        ) {
            await fetchSecondaryTrend(for: .steps, calendar: calendar)
        }
        async let cardioFitness: HealthTrendSeries? = fetchDashboardMetricIfNeeded(.cardioFitness, selection: selection, default: HealthTrendSeries.empty) {
            // `.latest` per day, and no `sourceKind:` (not source-selectable). The
            // series is genuinely sparse — only days carrying a reading come back —
            // which the chart path is built for.
            await fetchDailyQuantitySeries(
                for: .vo2Max,
                unit: HKUnit(from: "ml/kg*min"),
                aggregation: .latest,
                calendar: calendar
            )
        }

        // Resolve every leaf against its cached value and record whether ANY
        // leaf query failed. A `nil` fetched value means the HealthKit query
        // failed (device locked, store unavailable, XPC drop) rather than
        // returning no data, so keep the cached series instead of blanking it and
        // flag the failure. A non-nil value — including the intentionally empty
        // series produced by a permission or comparison toggle-off — replaces the
        // cache. Secondary leaves resolve against their own cached secondary
        // value, same rule as primaries. The store ORs `hadQueryFailure` with the
        // summary and ring-history bits before advancing the freshness TTL.
        var hadQueryFailure = false
        func resolved<Series>(_ fetched: Series?, cached: Series) -> Series {
            if fetched == nil {
                hadQueryFailure = true
            }
            return fetched ?? cached
        }

        let sleepHistoryResult = await sleepHistory
        // A non-nil sleep history can still carry a failed nocturnal vital (merged
        // from cache in `hydrateSleepVitals`); withhold the TTL for that too.
        if sleepHistoryResult.vitalsHadFailure {
            hadQueryFailure = true
        }
        let fetchedSleepHistory = resolved(sleepHistoryResult.history, cached: cachedTrends.sleepHistory)
        let fetchedSleepHistorySecondary = resolved(await sleepHistorySecondary, cached: cachedTrends.sleepHistorySecondary)
        let fetchedHeartRatePair = await heartRatePair
        let fetchedHeartRate = resolved(fetchedHeartRatePair?.0, cached: cachedTrends.heartRate)
        let fetchedHeartRateRanges = resolved(fetchedHeartRatePair?.1, cached: cachedTrends.heartRateRanges)
        let fetchedHeartRateVariabilityPair = await heartRateVariabilityPair
        let fetchedHeartRateVariability = resolved(fetchedHeartRateVariabilityPair?.0, cached: cachedTrends.heartRateVariability)
        let fetchedHeartRateVariabilityRanges = resolved(fetchedHeartRateVariabilityPair?.1, cached: cachedTrends.heartRateVariabilityRanges)
        let fetchedRespiratoryRatePair = await respiratoryRatePair
        let fetchedRespiratoryRate = resolved(fetchedRespiratoryRatePair?.0, cached: cachedTrends.respiratoryRate)
        let fetchedRespiratoryRateRanges = resolved(fetchedRespiratoryRatePair?.1, cached: cachedTrends.respiratoryRateRanges)
        let fetchedOxygenSaturationPair = await oxygenSaturationPair
        let fetchedOxygenSaturation = resolved(fetchedOxygenSaturationPair?.0, cached: cachedTrends.oxygenSaturation)
        let fetchedOxygenSaturationRanges = resolved(fetchedOxygenSaturationPair?.1, cached: cachedTrends.oxygenSaturationRanges)
        let trends = HealthTrendSnapshot(
            sleep: fetchedSleepHistory.durationSeries,
            sleepSecondary: fetchedSleepHistorySecondary.durationSeries,
            heartRate: fetchedHeartRate,
            heartRateRanges: fetchedHeartRateRanges,
            heartRateRangesSecondary: resolved(await heartRateRangesSecondary, cached: cachedTrends.heartRateRangesSecondary),
            restingHeartRate: resolved(await restingHeartRate, cached: cachedTrends.restingHeartRate),
            restingHeartRateSecondary: resolved(await restingHeartRateSecondary, cached: cachedTrends.restingHeartRateSecondary),
            bodyMass: resolved(await bodyMass, cached: cachedTrends.bodyMass),
            bodyFatPercentage: resolved(await bodyFatPercentage, cached: cachedTrends.bodyFatPercentage),
            heartRateVariability: fetchedHeartRateVariability,
            heartRateVariabilityRanges: fetchedHeartRateVariabilityRanges,
            heartRateVariabilityRangesSecondary: resolved(await heartRateVariabilityRangesSecondary, cached: cachedTrends.heartRateVariabilityRangesSecondary),
            respiratoryRate: fetchedRespiratoryRate,
            respiratoryRateRanges: fetchedRespiratoryRateRanges,
            oxygenSaturation: fetchedOxygenSaturation,
            oxygenSaturationRanges: fetchedOxygenSaturationRanges,
            oxygenSaturationRangesSecondary: resolved(await oxygenSaturationRangesSecondary, cached: cachedTrends.oxygenSaturationRangesSecondary),
            bodyMassIndex: resolved(await bodyMassIndex, cached: cachedTrends.bodyMassIndex),
            activeEnergy: resolved(await activeEnergy, cached: cachedTrends.activeEnergy),
            activeEnergySecondary: resolved(await activeEnergySecondary, cached: cachedTrends.activeEnergySecondary),
            restingEnergy: resolved(await restingEnergy, cached: cachedTrends.restingEnergy),
            restingEnergySecondary: resolved(await restingEnergySecondary, cached: cachedTrends.restingEnergySecondary),
            exerciseMinutes: resolved(await exerciseMinutes, cached: cachedTrends.exerciseMinutes),
            exerciseMinutesSecondary: resolved(await exerciseMinutesSecondary, cached: cachedTrends.exerciseMinutesSecondary),
            trainingLoad: resolved(await trainingLoad, cached: cachedTrends.trainingLoad),
            wristTemperature: resolved(await wristTemperature, cached: cachedTrends.wristTemperature),
            timeInDaylight: resolved(await timeInDaylight, cached: cachedTrends.timeInDaylight),
            steps: resolved(await steps, cached: cachedTrends.steps),
            stepsSecondary: resolved(await stepsSecondary, cached: cachedTrends.stepsSecondary),
            cardioFitness: resolved(await cardioFitness, cached: cachedTrends.cardioFitness),
            sleepHistory: fetchedSleepHistory,
            sleepHistorySecondary: fetchedSleepHistorySecondary,
            heartRateDaySamples: cachedHeartRateDaySamples,
            heartRateDaySamplesSecondary: cachedHeartRateDaySamplesSecondary,
            // Resting heart rate has no day view, so its intraday fields are never
            // fetched and are published empty (flushing any legacy persisted samples).
            restingHeartRateDaySamples: .empty,
            restingHeartRateDaySamplesSecondary: .empty,
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
        return HealthTrendFetchResult(trends: trends, hadQueryFailure: hadQueryFailure)
    }

    /// Incremental day-sample refetch for the per-metric detail refresh:
    /// only asks HealthKit for samples newer than the cached series, then
    /// merges (mirroring `HealthKitWorkoutStore.loadIntradayMetricSamplesIfNeeded`)
    /// instead of re-shipping the full trend window of raw samples.
    /// `fetchIncrementalSecondaryDaySamples` does the same for the comparison
    /// source; the mid-refresh source-switch hazard that used to force a full
    /// secondary refetch is handled by the day-sample signature guard in
    /// `HealthKitWorkoutStore.refreshHealthMetric`, which discards fetched day
    /// samples outright when the selection changed while this was in flight.
    private func fetchIncrementalPrimaryDaySamples(
        for kind: HealthMetricKind,
        cached: HealthTrendSeries,
        calendar: Calendar
    ) async -> HealthTrendSeries? {
        let interval = intradayDaySampleInterval(calendar: calendar)
        let fetchStart = Self.incrementalFetchStart(after: cached, windowStart: interval.start)
        guard fetchStart < interval.end else {
            return Self.mergeIntradaySamples(
                existing: cached,
                incoming: .empty,
                windowStart: interval.start,
                refetchStart: fetchStart
            )
        }

        // A failed sample query returns nil — surface it (rather than silently
        // returning `cached`) so the caller folds the failure into
        // `hadQueryFailure` while still keeping the cached series via
        // `resolvedTrend`.
        guard let incoming = await fetchIntradayDaySamples(
            for: kind,
            calendar: calendar,
            startDate: fetchStart,
            endDate: interval.end
        ) else {
            return nil
        }
        return Self.mergeIntradaySamples(
            existing: cached,
            incoming: incoming,
            windowStart: interval.start,
            refetchStart: fetchStart
        )
    }

    /// The comparison-source counterpart of `fetchIncrementalPrimaryDaySamples`.
    /// Only for the sample-based kinds — the hourly cumulative kinds
    /// (`.activeEnergy`, `.steps`) still refetch their full window because the
    /// current hour's bucket overlaps and `mergeIntradaySamples` has no bucket
    /// dedupe, matching the `usesHourlyBuckets` branch in
    /// `HealthKitWorkoutStore.loadIntradayMetricSamplesIfNeeded`.
    private func fetchIncrementalSecondaryDaySamples(
        for kind: HealthMetricKind,
        cached: HealthTrendSeries,
        calendar: Calendar
    ) async -> HealthTrendSeries? {
        // A no-comparison selection (the Pro gate, an unresolved source, or the
        // primary-collapse rule in `selectedSecondaryHealthDataSourceOption`) has
        // to REPLACE the cached series, not merge into it: `mergeIntradaySamples`
        // retains every cached point older than `refetchStart`, so merging an
        // authoritative `.empty` at the 48h boundary would keep the old source's
        // points on the chart forever.
        guard !selectedSecondaryHealthDataSourceOption(for: kind).isNoComparison else {
            return .empty
        }

        let interval = intradayDaySampleInterval(calendar: calendar)
        let fetchStart = Self.incrementalFetchStart(after: cached, windowStart: interval.start)
        guard fetchStart < interval.end else {
            return Self.mergeIntradaySamples(
                existing: cached,
                incoming: .empty,
                windowStart: interval.start,
                refetchStart: fetchStart
            )
        }

        // A failed sample query returns nil — surface it (rather than silently
        // returning `cached`) so the caller folds the failure into
        // `hadQueryFailure` while still keeping the cached series via
        // `resolvedTrend`.
        guard let incoming = await fetchSecondaryDaySamples(
            for: kind,
            calendar: calendar,
            startDate: fetchStart,
            endDate: interval.end
        ) else {
            return nil
        }
        return Self.mergeIntradaySamples(
            existing: cached,
            incoming: incoming,
            windowStart: interval.start,
            refetchStart: fetchStart
        )
    }

    func fetchHealthDashboardSnapshot(
        for kind: HealthMetricKind,
        calendar: Calendar,
        existing: HealthDashboardSnapshot,
        idealSleepDuration: TimeInterval = BodySleepDurationGoal.defaultDuration
    ) async -> HealthDashboardMetricFetchResult {
        var summary = HealthSummarySnapshot.empty
        var trends = HealthTrendSnapshot.empty
        // Records whether the metric's summary leaf query failed (vs. a genuine
        // `.success(nil)` absent value), so the caller can distinguish a real
        // fetch from a cache-preserving no-op. Mirrors the per-leaf tracking in
        // `fetchHealthSummary`.
        var hadQueryFailure = false
        func resolvedDashboardSummary<Value>(fetched outcome: QueryOutcome<Value>, cached: Value?) -> Value? {
            if outcome.isFailure { hadQueryFailure = true }
            return Self.resolvedSummaryValue(fetched: outcome, cached: cached)
        }
        // Mirrors the per-leaf `resolved` in `fetchHealthTrends`: a `nil` fetched
        // trend / secondary / day-sample / sleep-history leaf means the HealthKit
        // query failed (keep the cached series) rather than a genuine empty
        // result, so fold it into `hadQueryFailure` too — not just the summary
        // leaf. Otherwise a failed trend or day-sample query while the
        // latest-value summary succeeds would let the caller confirm "Health data
        // updated" after cached trend data was retained.
        func resolvedTrend<Series>(_ fetched: Series?, cached: Series) -> Series {
            if fetched == nil { hadQueryFailure = true }
            return fetched ?? cached
        }

        if kind == .readiness {
            let baseSnapshot = existing
            let anchor = anchorDate ?? Date()
            let recomputed = await Task.detached(priority: .userInitiated) {
                baseSnapshot.recalculatingReadiness(
                    on: anchor,
                    idealSleepDuration: idealSleepDuration,
                    calendar: calendar
                )
            }.value
            // A pure recompute from the cached snapshot — no HealthKit query runs,
            // so it must not advance the sync badge ("Health data updated").
            return HealthDashboardMetricFetchResult(snapshot: recomputed, hadQueryFailure: false, ranQueries: false)
        }

        guard permissionSelection.includes(Self.healthPermission(forMetric: kind)) else {
            // Permission disabled: cached snapshot returned without querying, so
            // this no-op must not advance the sync badge.
            return HealthDashboardMetricFetchResult(
                snapshot: HealthDashboardSnapshot(summary: summary, trends: trends),
                hadQueryFailure: false,
                ranQueries: false
            )
        }

        switch kind {
        case .readiness:
            break
        case .sleep, .vitals:
            async let sleepSummary = fetchSleepSummary(calendar: calendar)
            async let sleepHistory = fetchDailySleepHistory(calendar: calendar, cachedSleepHistory: existing.trends.sleepHistory)
            async let sleepHistorySecondary = fetchSecondarySleepHistory(calendar: calendar)
            // A failed sleep query keeps the cached history (which feeds
            // readiness) rather than blanking it; a successful empty result
            // still replaces it. See `resolvedTrendSeries`.
            let sleepHistoryResult = await sleepHistory
            // A non-nil history can still carry a failed nocturnal vital merged
            // from cache; fold that in too, mirroring `fetchHealthTrends`.
            if sleepHistoryResult.vitalsHadFailure { hadQueryFailure = true }
            let fetchedSleepHistory = resolvedTrend(sleepHistoryResult.history, cached: existing.trends.sleepHistory)
            let fetchedSleepHistorySecondary = resolvedTrend(await sleepHistorySecondary, cached: existing.trends.sleepHistorySecondary)

            summary.sleep = resolvedDashboardSummary(fetched: await sleepSummary, cached: existing.summary.sleep) ?? HealthSummarySnapshot.empty.sleep
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
            async let bodyMassTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )
            async let bodyFatPercentageTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyMassIndexTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )

            summary.bodyMass = resolvedDashboardSummary(fetched: await bodyMass, cached: existing.summary.bodyMass) ?? HealthSummarySnapshot.empty.bodyMass
            summary.bodyFatPercentage = resolvedDashboardSummary(fetched: await bodyFatPercentage, cached: existing.summary.bodyFatPercentage) ?? HealthSummarySnapshot.empty.bodyFatPercentage
            summary.bodyMassIndex = resolvedDashboardSummary(fetched: await bodyMassIndex, cached: existing.summary.bodyMassIndex) ?? HealthSummarySnapshot.empty.bodyMassIndex
            trends.bodyMass = resolvedTrend(await bodyMassTrend, cached: existing.trends.bodyMass)
            trends.bodyFatPercentage = resolvedTrend(await bodyFatPercentageTrend, cached: existing.trends.bodyFatPercentage)
            trends.bodyMassIndex = resolvedTrend(await bodyMassIndexTrend, cached: existing.trends.bodyMassIndex)
        case .heartRate:
            async let heartRate = latestQuantity(
                for: .heartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .heartRate
            )
            async let lowHeartRateWarning = fetchTodayMetricWarning(.lowHeartRate, calendar: calendar)
            async let highHeartRateWarning = fetchTodayHighHeartRateWarning(calendar: calendar)
            async let heartRatePair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDailyQuantityAverageAndRangeSeries(
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
            async let heartRateDaySamplesSecondary = fetchIncrementalSecondaryDaySamples(
                for: .heartRate,
                cached: existing.trends.heartRateDaySamplesSecondary,
                calendar: calendar
            )

            summary.heartRate = resolvedDashboardSummary(fetched: await heartRate, cached: existing.summary.heartRate) ?? HealthSummarySnapshot.empty.heartRate
            summary = summary.replacingWarnings(
                for: .heartRate,
                with: [
                    resolvedDashboardSummary(fetched: await lowHeartRateWarning, cached: existing.summary.warning(.lowHeartRate)),
                    resolvedDashboardSummary(fetched: await highHeartRateWarning, cached: existing.summary.warning(.highHeartRate))
                ].compactMap { $0 }
            )
            let fetchedHeartRatePair = await heartRatePair
            trends.heartRate = resolvedTrend(fetchedHeartRatePair?.0, cached: existing.trends.heartRate)
            trends.heartRateRanges = resolvedTrend(fetchedHeartRatePair?.1, cached: existing.trends.heartRateRanges)
            trends.heartRateRangesSecondary = resolvedTrend(await heartRateRangesSecondary, cached: existing.trends.heartRateRangesSecondary)
            trends.heartRateDaySamples = resolvedTrend(await heartRateDaySamples, cached: existing.trends.heartRateDaySamples)
            trends.heartRateDaySamplesSecondary = resolvedTrend(await heartRateDaySamplesSecondary, cached: existing.trends.heartRateDaySamplesSecondary)
        case .restingHeartRate:
            async let restingHeartRate = latestQuantity(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .restingHeartRate
            )
            async let restingHeartRateTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .restingHeartRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .restingHeartRate
            )
            async let restingHeartRateSecondaryTrend = fetchSecondaryTrend(for: .restingHeartRate, calendar: calendar)
            // No intraday fetch: resting heart rate has no day view
            // (`supportsMetricDayView` / `HealthMetricKind.dayViewKinds` both
            // exclude it — HealthKit records one RHR value per day, so an hourly
            // chart would be a single dot). The `restingHeartRateDaySamples*`
            // fields stay on the snapshot for decode back-compat and are left
            // empty so any previously persisted samples flush out of the sidecar.

            summary.restingHeartRate = resolvedDashboardSummary(fetched: await restingHeartRate, cached: existing.summary.restingHeartRate) ?? HealthSummarySnapshot.empty.restingHeartRate
            trends.restingHeartRate = resolvedTrend(await restingHeartRateTrend, cached: existing.trends.restingHeartRate)
            trends.restingHeartRateSecondary = resolvedTrend(await restingHeartRateSecondaryTrend, cached: existing.trends.restingHeartRateSecondary)
        case .bodyMass:
            async let bodyMass = latestQuantity(for: .bodyMass, unit: .gramUnit(with: .kilo), sourceKind: .basics)
            async let bodyMassTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .bodyMass,
                unit: .gramUnit(with: .kilo),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )

            summary.bodyMass = resolvedDashboardSummary(fetched: await bodyMass, cached: existing.summary.bodyMass) ?? HealthSummarySnapshot.empty.bodyMass
            trends.bodyMass = resolvedTrend(await bodyMassTrend, cached: existing.trends.bodyMass)
        case .bodyFatPercentage:
            async let bodyFatPercentage = latestQuantity(
                for: .bodyFatPercentage,
                unit: .percent(),
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let bodyFatPercentageTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .bodyFatPercentage,
                unit: .percent(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics,
                valueTransform: Self.normalizedPercentDisplayValue
            )

            summary.bodyFatPercentage = resolvedDashboardSummary(fetched: await bodyFatPercentage, cached: existing.summary.bodyFatPercentage) ?? HealthSummarySnapshot.empty.bodyFatPercentage
            trends.bodyFatPercentage = resolvedTrend(await bodyFatPercentageTrend, cached: existing.trends.bodyFatPercentage)
        case .heartRateVariability:
            async let heartRateVariability = latestQuantity(
                for: .heartRateVariabilitySDNN,
                unit: .secondUnit(with: .milli),
                sourceKind: .heartRateVariability
            )
            async let heartRateVariabilityPair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDailyQuantityAverageAndRangeSeries(
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
            async let heartRateVariabilityDaySamplesSecondary = fetchIncrementalSecondaryDaySamples(
                for: .heartRateVariability,
                cached: existing.trends.heartRateVariabilityDaySamplesSecondary,
                calendar: calendar
            )

            summary.heartRateVariability = resolvedDashboardSummary(fetched: await heartRateVariability, cached: existing.summary.heartRateVariability) ?? HealthSummarySnapshot.empty.heartRateVariability
            let fetchedHeartRateVariabilityPair = await heartRateVariabilityPair
            trends.heartRateVariability = resolvedTrend(fetchedHeartRateVariabilityPair?.0, cached: existing.trends.heartRateVariability)
            trends.heartRateVariabilityRanges = resolvedTrend(fetchedHeartRateVariabilityPair?.1, cached: existing.trends.heartRateVariabilityRanges)
            trends.heartRateVariabilityRangesSecondary = resolvedTrend(await heartRateVariabilityRangesSecondary, cached: existing.trends.heartRateVariabilityRangesSecondary)
            trends.heartRateVariabilityDaySamples = resolvedTrend(await heartRateVariabilityDaySamples, cached: existing.trends.heartRateVariabilityDaySamples)
            trends.heartRateVariabilityDaySamplesSecondary = resolvedTrend(await heartRateVariabilityDaySamplesSecondary, cached: existing.trends.heartRateVariabilityDaySamplesSecondary)
        case .respiratoryRate:
            async let respiratoryRate = latestQuantity(
                for: .respiratoryRate,
                unit: HKUnit.count().unitDivided(by: .minute()),
                sourceKind: .respiratoryRate
            )
            async let respiratoryRatePair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDailyQuantityAverageAndRangeSeries(
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

            summary.respiratoryRate = resolvedDashboardSummary(fetched: await respiratoryRate, cached: existing.summary.respiratoryRate) ?? HealthSummarySnapshot.empty.respiratoryRate
            let fetchedRespiratoryRatePair = await respiratoryRatePair
            trends.respiratoryRate = resolvedTrend(fetchedRespiratoryRatePair?.0, cached: existing.trends.respiratoryRate)
            trends.respiratoryRateRanges = resolvedTrend(fetchedRespiratoryRatePair?.1, cached: existing.trends.respiratoryRateRanges)
            trends.respiratoryRateDaySamples = resolvedTrend(await respiratoryRateDaySamples, cached: existing.trends.respiratoryRateDaySamples)
        case .oxygenSaturation:
            async let oxygenSaturation = latestQuantity(
                for: .oxygenSaturation,
                unit: .percent(),
                sourceKind: .oxygenSaturation,
                valueTransform: Self.normalizedPercentDisplayValue
            )
            async let lowBloodOxygenWarning = fetchTodayMetricWarning(.lowBloodOxygen, calendar: calendar)
            async let oxygenSaturationPair: (HealthTrendSeries, HealthTrendRangeSeries)? = fetchDailyQuantityAverageAndRangeSeries(
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
            async let oxygenSaturationDaySamplesSecondary = fetchIncrementalSecondaryDaySamples(
                for: .oxygenSaturation,
                cached: existing.trends.oxygenSaturationDaySamplesSecondary,
                calendar: calendar
            )

            summary.oxygenSaturation = resolvedDashboardSummary(fetched: await oxygenSaturation, cached: existing.summary.oxygenSaturation) ?? HealthSummarySnapshot.empty.oxygenSaturation
            summary = summary.replacingWarnings(
                for: .oxygenSaturation,
                with: [
                    resolvedDashboardSummary(fetched: await lowBloodOxygenWarning, cached: existing.summary.warning(.lowBloodOxygen))
                ].compactMap { $0 }
            )
            let fetchedOxygenSaturationPair = await oxygenSaturationPair
            trends.oxygenSaturation = resolvedTrend(fetchedOxygenSaturationPair?.0, cached: existing.trends.oxygenSaturation)
            trends.oxygenSaturationRanges = resolvedTrend(fetchedOxygenSaturationPair?.1, cached: existing.trends.oxygenSaturationRanges)
            trends.oxygenSaturationRangesSecondary = resolvedTrend(await oxygenSaturationRangesSecondary, cached: existing.trends.oxygenSaturationRangesSecondary)
            trends.oxygenSaturationDaySamples = resolvedTrend(await oxygenSaturationDaySamples, cached: existing.trends.oxygenSaturationDaySamples)
            trends.oxygenSaturationDaySamplesSecondary = resolvedTrend(await oxygenSaturationDaySamplesSecondary, cached: existing.trends.oxygenSaturationDaySamplesSecondary)
        case .bodyMassIndex:
            async let bodyMassIndex = latestQuantity(for: .bodyMassIndex, unit: .count(), sourceKind: .basics)
            async let bodyMassIndexTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .bodyMassIndex,
                unit: .count(),
                aggregation: .latest,
                calendar: calendar,
                sourceKind: .basics
            )

            summary.bodyMassIndex = resolvedDashboardSummary(fetched: await bodyMassIndex, cached: existing.summary.bodyMassIndex) ?? HealthSummarySnapshot.empty.bodyMassIndex
            trends.bodyMassIndex = resolvedTrend(await bodyMassIndexTrend, cached: existing.trends.bodyMassIndex)
        case .activeEnergy:
            async let activeEnergy = dailyCumulativeQuantitySummary(
                for: .activeEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .activeEnergy
            )
            async let activeEnergyTrend: HealthTrendSeries? = fetchDailyCumulativeQuantitySeries(
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
            // Hourly cumulative buckets: full window, not incremental (the current
            // hour's bucket overlaps and the merge can't dedupe it). Same reason the
            // primary above uses `fetchHourlyCumulativeQuantitySeries` directly.
            async let activeEnergyDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .activeEnergy,
                calendar: calendar
            )

            summary.activeEnergy = resolvedDashboardSummary(fetched: await activeEnergy, cached: existing.summary.activeEnergy) ?? HealthSummarySnapshot.empty.activeEnergy
            trends.activeEnergy = resolvedTrend(await activeEnergyTrend, cached: existing.trends.activeEnergy)
            trends.activeEnergySecondary = resolvedTrend(await activeEnergySecondaryTrend, cached: existing.trends.activeEnergySecondary)
            trends.activeEnergyDaySamples = resolvedTrend(await activeEnergyDaySamples, cached: existing.trends.activeEnergyDaySamples)
            trends.activeEnergyDaySamplesSecondary = resolvedTrend(await activeEnergyDaySamplesSecondary, cached: existing.trends.activeEnergyDaySamplesSecondary)
        case .restingEnergy:
            async let restingEnergy = dailyCumulativeQuantitySummary(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
            async let restingEnergyTrend: HealthTrendSeries? = fetchDailyCumulativeQuantitySeries(
                for: .basalEnergyBurned,
                unit: .kilocalorie(),
                calendar: calendar,
                sourceKind: .restingEnergy
            )
            async let restingEnergySecondaryTrend = fetchSecondaryTrend(for: .restingEnergy, calendar: calendar)

            summary.restingEnergy = resolvedDashboardSummary(fetched: await restingEnergy, cached: existing.summary.restingEnergy) ?? HealthSummarySnapshot.empty.restingEnergy
            trends.restingEnergy = resolvedTrend(await restingEnergyTrend, cached: existing.trends.restingEnergy)
            trends.restingEnergySecondary = resolvedTrend(await restingEnergySecondaryTrend, cached: existing.trends.restingEnergySecondary)
        case .exerciseMinutes:
            async let exerciseMinutes = dailyCumulativeQuantitySummary(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
            async let exerciseMinutesTrend: HealthTrendSeries? = fetchDailyCumulativeQuantitySeries(
                for: .appleExerciseTime,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .exerciseMinutes
            )
            async let exerciseMinutesSecondaryTrend = fetchSecondaryTrend(for: .exerciseMinutes, calendar: calendar)

            summary.exerciseMinutes = resolvedDashboardSummary(fetched: await exerciseMinutes, cached: existing.summary.exerciseMinutes) ?? HealthSummarySnapshot.empty.exerciseMinutes
            trends.exerciseMinutes = resolvedTrend(await exerciseMinutesTrend, cached: existing.trends.exerciseMinutes)
            trends.exerciseMinutesSecondary = resolvedTrend(await exerciseMinutesSecondaryTrend, cached: existing.trends.exerciseMinutesSecondary)
        case .trainingLoad:
            async let trainingLoad = fetchTrainingLoadSummary(calendar: calendar)
            async let trainingLoadTrend = fetchTrainingLoadSeries(calendar: calendar)

            summary.trainingLoad = resolvedDashboardSummary(fetched: await trainingLoad, cached: existing.summary.trainingLoad) ?? HealthSummarySnapshot.empty.trainingLoad
            trends.trainingLoad = resolvedTrend(await trainingLoadTrend, cached: existing.trends.trainingLoad)
        case .wristTemperature:
            async let wristTemperature = dailyQuantitySummary(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )
            async let wristTemperatureTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .appleSleepingWristTemperature,
                unit: .degreeCelsius(),
                aggregation: .average,
                calendar: calendar,
                sourceKind: .wristTemperature
            )

            summary.wristTemperature = resolvedDashboardSummary(fetched: await wristTemperature, cached: existing.summary.wristTemperature) ?? HealthSummarySnapshot.empty.wristTemperature
            trends.wristTemperature = resolvedTrend(await wristTemperatureTrend, cached: existing.trends.wristTemperature)
        case .timeInDaylight:
            async let timeInDaylight = dailyCumulativeQuantitySummary(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )
            async let timeInDaylightTrend: HealthTrendSeries? = fetchDailyCumulativeQuantitySeries(
                for: .timeInDaylight,
                unit: .minute(),
                calendar: calendar,
                sourceKind: .timeInDaylight
            )

            summary.timeInDaylight = resolvedDashboardSummary(fetched: await timeInDaylight, cached: existing.summary.timeInDaylight) ?? HealthSummarySnapshot.empty.timeInDaylight
            trends.timeInDaylight = resolvedTrend(await timeInDaylightTrend, cached: existing.trends.timeInDaylight)
        case .steps:
            async let steps = dailyCumulativeQuantitySummary(
                for: .stepCount,
                unit: .count(),
                calendar: calendar,
                sourceKind: .steps
            )
            async let stepsTrend: HealthTrendSeries? = fetchDailyCumulativeQuantitySeries(
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
            // Hourly cumulative buckets: full window, not incremental (see
            // `.activeEnergy` above).
            async let stepsDaySamplesSecondary = fetchSecondaryDaySamples(
                for: .steps,
                calendar: calendar
            )

            summary.steps = resolvedDashboardSummary(fetched: await steps, cached: existing.summary.steps) ?? HealthSummarySnapshot.empty.steps
            trends.steps = resolvedTrend(await stepsTrend, cached: existing.trends.steps)
            trends.stepsSecondary = resolvedTrend(await stepsSecondaryTrend, cached: existing.trends.stepsSecondary)
            trends.stepsDaySamples = resolvedTrend(await stepsDaySamples, cached: existing.trends.stepsDaySamples)
            trends.stepsDaySamplesSecondary = resolvedTrend(await stepsDaySamplesSecondary, cached: existing.trends.stepsDaySamplesSecondary)
        case .cardioFitness:
            // Latest reading (however old) + the sparse daily series, same shapes
            // as the dashboard leaves. The demographics ride along so the level
            // band can classify from a single-metric refresh too.
            async let cardioFitness = latestQuantity(for: .vo2Max, unit: HKUnit(from: "ml/kg*min"))
            async let cardioFitnessTrend: HealthTrendSeries? = fetchDailyQuantitySeries(
                for: .vo2Max,
                unit: HKUnit(from: "ml/kg*min"),
                aggregation: .latest,
                calendar: calendar
            )

            summary.cardioFitness = resolvedDashboardSummary(fetched: await cardioFitness, cached: existing.summary.cardioFitness) ?? HealthSummarySnapshot.empty.cardioFitness
            summary.cardioFitnessProfile = resolvedDashboardSummary(
                fetched: cardioFitnessProfile(),
                cached: existing.summary.cardioFitnessProfile
            )
            trends.cardioFitness = resolvedTrend(await cardioFitnessTrend, cached: existing.trends.cardioFitness)
        }

        return HealthDashboardMetricFetchResult(
            snapshot: HealthDashboardSnapshot(summary: summary, trends: trends),
            hadQueryFailure: hadQueryFailure,
            ranQueries: true
        )
    }

    // Static, pure-function helpers (sleep stage parsing, ring summary mapping,
    // workout downsampling, etc.) live in `HealthKitFetchEngine+SampleParsers.swift`.
}

/// Lock-protected state machine backing `HealthKitFetchEngine.runCancellableQuery`.
/// The query is built inside the continuation, so cancellation can arrive before
/// installation; the states below make installation, completion, and cancellation
/// mutually exclusive and resume the continuation exactly once. Because the lock is
/// never held across `execute`/`stop`, `install` runs the query through an
/// `.executing` phase and re-checks the state once `execute` returns: a cancel that
/// slips into the unlock→execute window flips to `.cancelledAwaitingStop` and defers
/// the single `stop` to that re-check, so the just-executed query is stopped exactly
/// once and never leaks (M15). HK callbacks fire off the actor, so all state
/// transitions take the lock. `@unchecked Sendable` is sound because every access is
/// lock-guarded.
final class CancellableQueryCoordinator<Value>: @unchecked Sendable {
    private enum State {
        case pendingNoQuery
        case executing(HKQuery)
        case pendingWithQuery(HKQuery)
        case cancelledAwaitingStop(HKQuery)
        case cancelled
        case completed
    }

    private let lock = NSLock()
    private let execute: @Sendable (HKQuery) -> Void
    private let stop: @Sendable (HKQuery) -> Void
    private var state: State = .pendingNoQuery
    private var continuation: CheckedContinuation<Value, Never>?

    init(
        execute: @escaping @Sendable (HKQuery) -> Void,
        stop: @escaping @Sendable (HKQuery) -> Void
    ) {
        self.execute = execute
        self.stop = stop
    }

    /// Builds and executes the query unless cancellation already fired, in which
    /// case it resumes immediately with `cancelledValue` and never touches HK. While
    /// `execute` runs the lock is released and the state is `.executing`; the re-check
    /// afterwards either arms the normal `.pendingWithQuery` state or, if cancel
    /// slipped into that window, issues the single deferred `stop`.
    func install(
        continuation: CheckedContinuation<Value, Never>,
        cancelledValue: Value,
        makeQuery: (@escaping (Value) -> Void) -> HKQuery
    ) {
        lock.lock()
        switch state {
        case .cancelled:
            state = .completed
            lock.unlock()
            continuation.resume(returning: cancelledValue)
        case .pendingNoQuery:
            self.continuation = continuation
            let query = makeQuery { [weak self] value in
                self?.complete(value)
            }
            state = .executing(query)
            lock.unlock()
            execute(query)
            lock.lock()
            switch state {
            case .executing:
                // Neither cancel nor the HK callback fired during `execute`; arm the
                // normal path so a later cancel stops the query itself.
                state = .pendingWithQuery(query)
                lock.unlock()
            case .cancelledAwaitingStop:
                // Cancel landed in the unlock→execute window and already resumed the
                // continuation; issue the single deferred stop for the executed query.
                state = .cancelled
                lock.unlock()
                stop(query)
            case .completed:
                // The HK callback won the race while `.executing`; already resumed.
                lock.unlock()
            case .pendingNoQuery, .pendingWithQuery, .cancelled:
                // Unreachable: only `cancel`/`complete` transition out of `.executing`.
                lock.unlock()
            }
        case .executing, .pendingWithQuery, .cancelledAwaitingStop, .completed:
            // `install` runs exactly once; these are unreachable.
            lock.unlock()
        }
    }

    private func complete(_ value: Value) {
        lock.lock()
        switch state {
        case .executing, .pendingWithQuery:
            state = .completed
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        case .pendingNoQuery, .cancelledAwaitingStop, .cancelled, .completed:
            // Already cancelled or completed — drop the late HK callback.
            lock.unlock()
        }
    }

    func cancel(cancelledValue: Value) {
        lock.lock()
        switch state {
        case .pendingNoQuery:
            // Continuation not yet installed; mark cancelled so `install` resumes
            // immediately without ever running the query.
            state = .cancelled
            lock.unlock()
        case .executing(let query):
            // Cancel raced into the unlock→execute window: resume now but leave the
            // stop to `install`'s re-check, which owns the just-executed query.
            let continuation = self.continuation
            self.continuation = nil
            state = .cancelledAwaitingStop(query)
            lock.unlock()
            continuation?.resume(returning: cancelledValue)
        case .pendingWithQuery(let query):
            state = .cancelled
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            stop(query)
            continuation?.resume(returning: cancelledValue)
        case .cancelledAwaitingStop, .cancelled, .completed:
            lock.unlock()
        }
    }
}
