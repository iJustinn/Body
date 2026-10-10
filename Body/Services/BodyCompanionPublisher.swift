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
        /// Shared since the watch gained Active Energy and Resting Energy,
        /// which its snapshot formats in this unit as the widget does.
        let energyUnitPreference: BodyValueFormat.EnergyUnitPreference
        let idealSleepDuration: TimeInterval
        let showSleepScore: Bool
    }

    /// The widget snapshot's captures: the shared half plus what only the widget
    /// renders. Split from `Shared` so the watch publish pays for neither the
    /// weight unit preference, which nothing in the watch snapshot formats
    /// with, nor the sixteen `@MainActor` source lookups behind
    /// `primarySourceNames`.
    struct Widget: Sendable {
        let shared: Shared
        let weightUnitPreference: BodyValueFormat.WeightUnitPreference
        /// Resolved on the main actor because `selectedHealthDataSourceOption(for:)`
        /// is `@MainActor`; the builder only needs the resulting names.
        let primarySourceNames: [HealthMetricKind: String]
        /// The trend kinds Home's Trends list shows, in Home's order, which the
        /// large Trends widget's Top Trend follows.
        let trendCardOrder: [BodyHomeTrendCardKind]
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
    /// The iPhone's ratings for the recent workouts, keyed by workout UUID
    /// (`WatchComputeSeed.trainingLoadEffortHints`).
    let trainingLoadEffortHints: [String: Double]?
    let expectedSourceIDsByKind: [String: [String]]
    let followsSystemUnits: Bool
    let selectedTemperatureUnitRaw: String
    let showsSubMinuteAwakeStages: Bool
    let showsLeadingTrailingAwakeStages: Bool
    let readinessHeroShowsLevel: Bool
    /// Body Pro unlocked and the Summary Cards Sleep Debt toggle on: the watch
    /// Sleep page shows the debt only while this is true.
    let showsSleepDebt: Bool
    let homeHeroRaw: String
    let dayRingShowsCaption: Bool
    /// The Warnings selection's raw value (`BodyMetricWarningSelection`):
    /// only the kinds turned on there reach the watch, as on the phone.
    let metricWarningSelectionRaw: String
    /// The Warnings sheet's Show on Home Hero switch, which both watch heroes
    /// follow for their badge row.
    let metricWarningsOnHero: Bool
    /// The folded warnings' raw value (`BodyDismissedMetricWarnings`), so
    /// each watch warning card starts folded or unfolded as the phone's does.
    let dismissedMetricWarningsRaw: String
    /// When each fold entry last changed (`BodyMetricWarningFoldDates`), sent
    /// with its warning so the watch can tell whether its own fold record is
    /// newer than the phone's state (`WatchWarningFoldSync`).
    let metricWarningFoldDates: [String: Date]
    /// The custom warning limits' raw value (`BodyMetricWarningThresholds`),
    /// which the watch checks its own warnings against.
    let metricWarningThresholdsRaw: String
    /// The max heart rate the High Heart Rate default was last resolved with
    /// (`BodyAppearancePreference.warningMaxHeartRateKey`): nil when nothing
    /// has resolved it yet, `.some(nil)` when it resolved without a birth date
    /// (the 120 bpm fallback).
    let warningMaxHeartRate: Double??
    /// The master and Warnings notification switches both on: the watch
    /// notifies its own warnings only then.
    let metricWarningNotificationsEnabled: Bool
    /// The warning notification ledger's raw value
    /// (`MetricWarningNotificationLedger`), so the watch skips a kind the phone
    /// already notified that day.
    let metricWarningNotificationLedgerRaw: String
    let workoutColorPalette: BodyWorkoutColorPalette
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
        isCurrent: @escaping @Sendable () -> Bool = { true },
        completion: @escaping @Sendable () -> Void = {}
    ) {
        HealthKitWorkoutStore.snapshotPersistQueue.async {
            guard isCurrent() else { completion(); return }
            let snapshot = HealthWidgetSnapshotBuilder.make(
                trends: input.shared.trends,
                summary: input.shared.summary,
                temperatureUnitPreference: input.shared.temperatureUnitPreference,
                energyUnitPreference: input.shared.energyUnitPreference,
                weightUnitPreference: input.weightUnitPreference,
                idealSleepDuration: input.shared.idealSleepDuration,
                showSleepScore: input.shared.showSleepScore,
                primarySourceName: { input.primarySourceNames[$0] },
                trendCardOrder: input.trendCardOrder
            )
            let changed = isCurrent() && HealthWidgetSnapshotStore.save(snapshot)
            Task { @MainActor in
                if changed, isCurrent() { BodyWidgetReloadCoalescer.shared.requestReload() }
                // Unconditional: dashboard-only changes such as warnings never
                // touch the widget file. Detached so it can never delay
                // `completion()`, and so the load stays off the main actor.
                Task.detached(priority: .utility) {
                    await BodySiriIndexCoordinator.shared.requestReindex()
                }
                completion()
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
        isEpochCurrent: @escaping @MainActor @Sendable (Int) -> Bool,
        completion: @escaping @MainActor @Sendable () -> Void = {}
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
            // Readiness and Training Load carry their own watermarks: a
            // workout-only refresh re-drains readiness (only) while
            // `lastRefreshDate` (the VITALS watermark) deliberately stands
            // still. Stamping uniformly would present genuinely fresh
            // readiness as stale — or, joint-stamping both, present a NOT
            // recomputed Training Load as fresh. Either way the watch's
            // per-metric compare then picks the wrong side. Every other
            // kind (and a never-recomputed Training Load) falls through to
            // the uniform vitals date.
            func dataAsOf(forKind kind: String) -> Date? {
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
            // The Stress page's "Last 12 hours", built here off the main actor
            // because it rescans the stress window. Over the store's LIVE
            // summary and trends: only they still carry the intraday day
            // samples, which the persisted dashboard and the seed both strip.
            // The workouts are the store's whole stress window, the same mask
            // its Day View and recompute score with, since every scanned day's
            // quiet heart rate feeds today's baseline. Stamped with the Stress
            // card's own watermark, so the watch merges the two consistently.
            let stressTimeline: WatchStressTimeline? = input.permissionSelection.includes(.heart)
                ? WatchStressTimelineBuilder.make(
                    dashboard: HealthDashboardSnapshot(summary: input.shared.summary, trends: input.shared.trends),
                    workouts: HealthKitWorkoutStore.stressWindowWorkouts(
                        in: input.monthSnapshots,
                        through: input.now,
                        calendar: .bodyGregorian
                    ),
                    now: input.now,
                    calendar: .bodyGregorian,
                    computedAt: dataAsOf(forKind: WatchMetricKindKey.stress) ?? input.lastRefreshDate
                )
                : nil
            var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
                summary: input.shared.summary,
                trends: input.shared.trends,
                lastRefreshDate: input.lastRefreshDate,
                permissionSelection: input.permissionSelection,
                temperatureUnitPreference: input.shared.temperatureUnitPreference,
                energyUnitPreference: input.shared.energyUnitPreference,
                idealSleepDuration: input.shared.idealSleepDuration,
                showSleepScore: input.shared.showSleepScore,
                now: input.now,
                workoutWeeklyMinutes: workoutWeeklyMinutes,
                perKindDataAsOf: dataAsOf(forKind:),
                includesSleepDebt: input.showsSleepDebt,
                stressTimeline: stressTimeline,
                // The palette resolved for Body Pro: empty without it, so the
                // watch draws the built-in colors the phone does.
                workoutColorOverrides: BodyWorkoutColorOverrides.rawValue(from: input.workoutColorPalette.overrides)
            )
            snapshot.source = "phone"
            snapshot.readinessHeroShowsLevel = input.readinessHeroShowsLevel
            snapshot.showsSleepDebt = input.showsSleepDebt
            snapshot.homeHero = input.homeHeroRaw
            snapshot.dayRingShowsCaption = input.dayRingShowsCaption
            snapshot.heroShowsWarnings = input.metricWarningsOnHero
            snapshot.metricWarnings = Self.watchMetricWarnings(
                summary: input.shared.summary,
                selectionRaw: input.metricWarningSelectionRaw,
                dismissedRaw: input.dismissedMetricWarningsRaw,
                foldDates: input.metricWarningFoldDates,
                cardKinds: Set(snapshot.metrics.map(\.kind)),
                now: input.now
            )
            snapshot.warningSettings = Self.watchWarningSettings(
                selectionRaw: input.metricWarningSelectionRaw,
                thresholdsRaw: input.metricWarningThresholdsRaw,
                maxHeartRate: input.warningMaxHeartRate,
                notificationsEnabled: input.metricWarningNotificationsEnabled,
                ledgerRaw: input.metricWarningNotificationLedgerRaw
            )
            if input.homeHeroRaw == BodyStarMetric.dayRing.rawValue {
                // Yesterday through tomorrow: the watch keeps what overlaps the day
                // its own clock is on, so a snapshot that outlives midnight still draws.
                let window = DateInterval(start: input.now.addingTimeInterval(-86_400), end: input.now.addingTimeInterval(86_400))
                snapshot.dayRingWorkouts = input.monthSnapshots.values.flatMap(\.days).flatMap(\.workouts)
                    .filter { $0.startDate < window.end && $0.effectiveEndDate > window.start }
                    .map {
                        WatchDayRingWorkout(
                            id: $0.id.uuidString,
                            type: $0.type.rawValue,
                            startDate: $0.startDate,
                            endDate: $0.effectiveEndDate,
                            colorHex: input.workoutColorPalette.resolvedHex(for: $0.type)
                        )
                    }
            }

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
                    // Nil for kilocalories, the watch's own default, so a
                    // kilocalorie user's seed signs as it did before the energy
                    // cards and only a kilojoule user re-seeds once.
                    selectedEnergyUnitRaw: input.shared.energyUnitPreference == .kilojoules
                        ? BodyValueFormat.EnergyUnitPreference.kilojoules.rawValue
                        : nil,
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
                    trainingLoadEffortHints: input.trainingLoadEffortHints,
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
                defer { completion() }
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

    /// Today's threshold warnings as the watch draws them: its hero badges,
    /// card glyphs and detail page warning cards.
    ///
    /// Walks `MetricWarningKind.allCases`, so the warnings ship in the phone's
    /// kind order, and keeps a kind only when:
    /// * it is turned on in the Warnings selection;
    /// * `summary` carries an episode for it that started on `now`'s day (the
    ///   watch drops a warning after midnight anyway, so an older one would
    ///   only cost bytes);
    /// * its metric has a card in the built snapshot (`cardKinds`). Blood
    ///   Oxygen and Respiratory Rate have no watch card, so they never ship,
    ///   and a card the builder left out for a permission that's off takes
    ///   its warnings with it.
    ///
    /// `summary` is `input.shared.summary`, the same permission filtered
    /// summary Home reads, so the watch shows exactly the warnings Home
    /// flags. Each warning carries its fold key (the phone's
    /// `dismissedMetricWarnings` entry, built in one place by
    /// `BodyDismissedMetricWarnings.entryKey(for:)`), whether that entry is
    /// folded, and the entry's stamp, which the watch compares its own fold
    /// records against. Nil when nothing qualifies, which the snapshot reads
    /// as no warnings.
    nonisolated static func watchMetricWarnings(
        summary: HealthSummarySnapshot,
        selectionRaw: String,
        dismissedRaw: String,
        foldDates: [String: Date],
        cardKinds: Set<String>,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [WatchMetricWarning]? {
        let selection = BodyMetricWarningSelection.storedValue(from: selectionRaw)
        let dismissed = BodyDismissedMetricWarnings.storedValue(from: dismissedRaw)
        let warnings = MetricWarningKind.allCases.compactMap { kind -> WatchMetricWarning? in
            guard selection.includes(kind),
                  let event = summary.warning(kind),
                  calendar.isDate(event.startDate, inSameDayAs: now),
                  cardKinds.contains(kind.metric.rawValue) else {
                return nil
            }
            let foldKey = BodyDismissedMetricWarnings.entryKey(for: event, calendar: calendar)
            return WatchMetricWarning(
                kind: kind.rawValue,
                startDate: event.startDate,
                threshold: event.threshold,
                foldKey: foldKey,
                isFolded: dismissed.contains(event, calendar: calendar),
                foldChangedAt: foldDates[foldKey]
            )
        }
        return warnings.isEmpty ? nil : warnings
    }

    /// The phone's warning settings the watch checks and notifies its own
    /// warnings under, for the kinds with a watch card (Low and High Heart
    /// Rate, High Skin Temperature), walked in `MetricWarningKind.allCases`
    /// order:
    /// * `thresholds`: each kind's effective limit, the user's override or the
    ///   default. High Heart Rate's default follows the birth date, which only
    ///   the engine's Heart Rate read resolves, so while `maxHeartRate` is nil
    ///   (never resolved) and there is no override its limit is left out
    ///   rather than sent as the 120 bpm fallback. `.some(nil)` (resolved, no
    ///   birth date) is that fallback.
    /// * `enabledKinds`: those turned on in the Warnings selection, in kind
    ///   order, so the watch's equality early out never sees a reordered list
    ///   as a change.
    /// * `notifies`: the master and Warnings notification switches.
    /// * `notifiedDays`: the notification ledger's day for each of them.
    nonisolated static func watchWarningSettings(
        selectionRaw: String,
        thresholdsRaw: String,
        maxHeartRate: Double??,
        notificationsEnabled: Bool,
        ledgerRaw: String
    ) -> WatchWarningSettings {
        let kinds = MetricWarningKind.allCases.filter { [.heartRate, .wristTemperature].contains($0.metric) }
        let selection = BodyMetricWarningSelection.storedValue(from: selectionRaw)
        let overrides = BodyMetricWarningThresholds.storedValue(from: thresholdsRaw)
        let ledger = MetricWarningNotificationLedger.storedValue(from: ledgerRaw)
        var thresholds: [String: Double] = [:]
        var notifiedDays: [String: String] = [:]
        for kind in kinds {
            if let day = ledger.lastNotifiedDayKeys[kind] {
                notifiedDays[kind.rawValue] = day
            }
            if let resolvedMaxHeartRate = maxHeartRate {
                thresholds[kind.rawValue] = overrides.threshold(for: kind, maxHeartRate: resolvedMaxHeartRate)
            } else if kind != .highHeartRate || overrides.override(for: kind) != nil {
                // Never resolved, which only High Heart Rate's default needs.
                thresholds[kind.rawValue] = overrides.threshold(for: kind)
            }
        }
        return WatchWarningSettings(
            thresholds: thresholds,
            enabledKinds: kinds.filter(selection.includes).map(\.rawValue),
            notifies: notificationsEnabled,
            notifiedDays: notifiedDays
        )
    }

    /// Size budget for the compute seed alone (before the display snapshot and
    /// permission key are added on top) — the `WatchComputeSeedTests` size test
    /// pins a realistic fixture (70 days of trends, 86 nights of sleep history)
    /// comfortably under this. Separate from
    /// `WatchConnectivityPublisher`'s whole-context budget, which accounts for
    /// the other context keys too.
    nonisolated private static let computeSeedSizeBudgetBytes = 50_000

    nonisolated private static let computeSeedLogger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchComputeSeed")
}
