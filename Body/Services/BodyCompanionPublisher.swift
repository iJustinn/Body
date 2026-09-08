import Foundation
import OSLog

/// Everything the widget snapshot save and the watch snapshot publish read off
/// `HealthKitWorkoutStore`, captured synchronously on the main actor in one pass
/// so a queued build can never mix a value from one state with a value from the
/// next (M-08).
///
/// Every capture is a value type and the struct is `Sendable`, which is what
/// lets the publisher hand the whole thing to the persist queue and do the
/// remaining derivation (the weekly workout minutes, their persisted fallback,
/// the 14-day time-zone map) off the main actor.
///
/// Shaped as `Shared` plus a `Widget` that wraps it, rather than one flat
/// struct, because the two publishes read overlapping but unequal state: a
/// widget-only save (`saveHealthWidgetSnapshot` is called on its own from
/// several refresh paths) needs the widget-only extras, and the watch publish,
/// which renders none of them, must not pay for them.
struct BodyCompanionPublishInput: Sendable {
    /// What both snapshots render from: one summary, one trend set and the
    /// display preferences the widget and the watch format alike.
    struct Shared: Sendable {
        let trends: HealthTrendSnapshot
        let summary: HealthSummarySnapshot
        let temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference
        let idealSleepDuration: TimeInterval
        let showSleepScore: Bool
    }

    /// The widget snapshot's captures: the shared half plus what only the widget
    /// renders. Split from `Shared` so the watch publish pays for neither the
    /// energy and weight unit preferences, which nothing in the watch snapshot
    /// formats with, nor the sixteen `@MainActor` source lookups behind
    /// `primarySourceNames`.
    struct Widget: Sendable {
        let shared: Shared
        let energyUnitPreference: BodyValueFormat.EnergyUnitPreference
        let weightUnitPreference: BodyValueFormat.WeightUnitPreference
        /// Resolved on the main actor because `selectedHealthDataSourceOption(for:)`
        /// is `@MainActor`; the builder only needs the resulting names.
        let primarySourceNames: [HealthMetricKind: String]
    }

    let shared: Shared
    let epoch: Int
    let lastRefreshDate: Date?
    let permissionSelection: BodyHealthPermissionSelection
    let permissionRawValue: String
    let now: Date
    let workoutCalendar: Calendar
    let monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot]
    let captureSequence: UInt64
    let dataThrough: Date?
    let readinessComputeDate: Date?
    let trainingLoadComputeDate: Date?
    let workoutMinutesDataAsOf: Date
    let metricPullDates: [String: Date]
    let trainingLoadStartDay: Date?
    let trainingLoadDailyLoads: [Double]?
    let trainingLoadDataThrough: Date?
    let expectedSourceIDsByKind: [String: [String]]
    let followsSystemUnits: Bool
    let selectedTemperatureUnitRaw: String
    let showsSubMinuteAwakeStages: Bool
    let showsLeadingTrailingAwakeStages: Bool
    let healthDataSourceSelectionRaw: String
    let customHealthSourceGroupsRaw: String?
    let combinesByName: Bool
}

/// Builds and ships the two companion snapshots (the iOS widget's App Group
/// file and the paired watch's push) from a `BodyCompanionPublishInput` the
/// store captured on the main actor.
///
/// The point of the split is M-08: everything past the capture runs on
/// `HealthKitWorkoutStore.snapshotPersistQueue`, including the work that used to
/// sit on the main actor before the enqueue — the trailing week's workout
/// minutes, the persisted previous-month fallback that can cost a file decode,
/// and the 14-day time-zone map's `UserDefaults` read plus JSON decode. Only the
/// final `send` hops back, and only to re-check the cache epoch.
@MainActor
final class BodyCompanionPublisher {
    /// What the built watch snapshot is handed to. Injected only so the epoch
    /// gate above it can be tested without a paired-device session; production
    /// always uses the shared `WatchConnectivityPublisher`.
    typealias Send = @MainActor @Sendable (
        _ snapshot: WatchMetricsSnapshot,
        _ permissionRawValue: String,
        _ captureSequence: UInt64,
        _ computeSeedData: Data?,
        _ computeSeedSettingsSignature: String?
    ) -> Void

    private let send: Send

    /// The pending debounced companion republish (see `scheduleRepublish`).
    private var republishTask: Task<Void, Never>?

    init(send: @escaping Send = { snapshot, permissionRawValue, captureSequence, computeSeedData, signature in
        WatchConnectivityPublisher.shared.send(
            snapshot,
            permissionRawValue: permissionRawValue,
            captureSequence: captureSequence,
            computeSeedData: computeSeedData,
            computeSeedSettingsSignature: signature
        )
    }) {
        self.send = send
    }

    /// Debounces a companion rebuild by 300 ms, because a held stepper or a
    /// dragged slider fires one `onChange` per tick and each rebuild encodes
    /// both snapshots and reloads the widget timelines. Known trade: a
    /// preference change followed within 300 ms by app suspension publishes on
    /// the next refresh instead. The task lives on the publisher, which the
    /// store owns, so dismissing the settings view does not drop it.
    ///
    /// `rebuild` is the store's main-actor capture-and-publish pass; it runs
    /// only if the debounce window survived.
    func scheduleRepublish(_ rebuild: @escaping @MainActor () -> Void) {
        republishTask?.cancel()
        republishTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rebuild()
        }
    }

    /// Builds the slim widget snapshot from the captured trends, sleep stages,
    /// source names and unit preferences, then writes it to the App Group so the
    /// trend + sleep-stage widgets can render. The build + disk write happen
    /// off-actor.
    func saveWidgetSnapshot(
        _ input: BodyCompanionPublishInput.Widget,
        isCurrent: @escaping @Sendable () -> Bool = { true }
    ) {
        HealthKitWorkoutStore.snapshotPersistQueue.async {
            guard isCurrent() else { return }
            let snapshot = HealthWidgetSnapshotBuilder.make(
                trends: input.shared.trends,
                summary: input.shared.summary,
                temperatureUnitPreference: input.shared.temperatureUnitPreference,
                energyUnitPreference: input.energyUnitPreference,
                weightUnitPreference: input.weightUnitPreference,
                idealSleepDuration: input.shared.idealSleepDuration,
                showSleepScore: input.shared.showSleepScore,
                primarySourceName: { input.primarySourceNames[$0] }
            )
            if isCurrent(), HealthWidgetSnapshotStore.save(snapshot) {
                Task { await BodyWidgetReloadCoalescer.shared.requestReload() }
            }
        }
    }

    /// Pushes the latest metrics to the paired Apple Watch. Best-effort: the
    /// build is pure and `send` never blocks the refresh. Publishing from the
    /// common funnel (including workout-only paths) keeps the watch's values
    /// current, but `lastRefreshDate` carries the last *vitals* refresh — a
    /// workout-only refresh must not look fresh to the watch, or it would
    /// suppress the watch's own stale-triggered live HR/HRV refresh.
    ///
    /// `isEpochCurrent` is the store's cache-epoch check, re-run on the main
    /// actor right before the send: a Clear Cache that bumped the epoch after
    /// the capture must win, so pre-clear metrics are never shipped onto the
    /// wiped state (H7).
    func publishWatchSnapshot(
        _ input: BodyCompanionPublishInput,
        isEpochCurrent: @escaping @MainActor @Sendable (Int) -> Bool
    ) {
        let send = self.send
        HealthKitWorkoutStore.snapshotPersistQueue.async {
            // The weekly workout complication's bars, read off the month
            // snapshots every regular refresh already rebuilds — no extra
            // HealthKit query. Early in a month the trailing week reaches into a
            // month only the persisted App Group file holds, so it fills those
            // days rather than the metric being dropped (see
            // `persistedWeeklyWorkoutFallback`). Derived here rather than at the
            // capture point because the fallback can cost a file decode (M-08).
            let workoutWeeklyMinutes = HealthKitWorkoutStore.weeklyWorkoutMinutes(
                from: input.monthSnapshots,
                fallback: HealthKitWorkoutStore.persistedWeeklyWorkoutFallback(
                    for: input.monthSnapshots,
                    now: input.now,
                    calendar: input.workoutCalendar
                ),
                now: input.now,
                calendar: input.workoutCalendar
            )
            var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
                summary: input.shared.summary,
                trends: input.shared.trends,
                lastRefreshDate: input.lastRefreshDate,
                permissionSelection: input.permissionSelection,
                temperatureUnitPreference: input.shared.temperatureUnitPreference,
                idealSleepDuration: input.shared.idealSleepDuration,
                showSleepScore: input.shared.showSleepScore,
                now: input.now,
                workoutWeeklyMinutes: workoutWeeklyMinutes,
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
                        return input.readinessComputeDate
                    case WatchMetricKindKey.trainingLoad:
                        return input.trainingLoadComputeDate
                    case WatchMetricKindKey.workoutMinutes,
                         // The legacy compatibility copy carries the same week,
                         // so it ships under the same watermark.
                         WatchMetricKindKey.exerciseMinutes:
                        return input.workoutMinutesDataAsOf
                    default:
                        // A single-metric detail pull refreshes one vitals kind
                        // without advancing the full-refresh date — take the
                        // newer of the two so the pulled value doesn't ship
                        // under a stale stamp.
                        return [input.lastRefreshDate, input.metricPullDates[kind]]
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
            if let dataThrough = input.dataThrough {
                // Only the seed needs the 14-day time-zone map, and building it
                // costs a `UserDefaults` read, a `JSONDecoder` pass and fourteen
                // day boundary computations, so build it only when a seed will
                // actually be assembled — and here, off the main actor (M-08).
                let settings = WatchComputeSettings(
                    idealSleepDurationMinutes: Int((input.shared.idealSleepDuration / 60).rounded()),
                    followsSystemUnits: input.followsSystemUnits,
                    selectedTemperatureUnitRaw: input.selectedTemperatureUnitRaw,
                    showSleepScore: input.shared.showSleepScore,
                    showsSubMinuteAwakeSleepStages: input.showsSubMinuteAwakeStages,
                    showsLeadingTrailingAwakeSleepStages: input.showsLeadingTrailingAwakeStages,
                    healthDataSourceSelectionRaw: input.healthDataSourceSelectionRaw,
                    combinesHealthDataSourcesByName: input.combinesByName,
                    customHealthSourceGroupsRaw: input.customHealthSourceGroupsRaw,
                    recentTimeZoneIdentifiersByDay: HealthKitWorkoutStore.recentTimeZoneIdentifiersByDay(now: input.now)
                )
                let seed = HealthKitWorkoutStore.makeComputeSeed(
                    summary: input.shared.summary,
                    trends: input.shared.trends,
                    dataThrough: dataThrough,
                    lastVitalsRefreshDate: input.lastRefreshDate,
                    trainingLoadStartDay: input.trainingLoadStartDay,
                    trainingLoadDailyLoads: input.trainingLoadDailyLoads,
                    trainingLoadDataThrough: input.trainingLoadDataThrough,
                    expectedSourceIDsByKind: input.expectedSourceIDsByKind.isEmpty ? nil : input.expectedSourceIDsByKind,
                    settings: settings,
                    publishedAt: input.now
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

            let epoch = input.epoch
            let permissionRawValue = input.permissionRawValue
            let captureSequence = input.captureSequence
            Task { @MainActor in
                // A Clear Cache that bumped the epoch after this snapshot was
                // captured must win — don't ship pre-clear metrics onto the wiped
                // state (H7). The reset send in `clearLocalCache` blanks the watch.
                guard isEpochCurrent(epoch) else {
                    return
                }
                send(
                    snapshot,
                    permissionRawValue,
                    captureSequence,
                    computeSeedData,
                    computeSeedSettingsSignature
                )
            }
        }
    }

    /// Size budget for the compute seed alone (before the display snapshot and
    /// permission key are added on top) — the `WatchComputeSeedTests` size test
    /// pins a realistic 70-day fixture comfortably under this. Separate from
    /// `WatchConnectivityPublisher`'s whole-context budget, which accounts for
    /// the other context keys too.
    nonisolated private static let computeSeedSizeBudgetBytes = 50_000

    nonisolated private static let computeSeedLogger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchComputeSeed")
}
