//
//  MetricWarningBackgroundEvaluator.swift
//  Body
//

import Foundation
import HealthKit
@preconcurrency import UserNotifications

/// Runs ONE headless metric-warning evaluation for the background refresh task:
/// reads the persisted warning settings, fetches today's warnings through a
/// fresh `HealthKitFetchEngine`, and posts at most one notification per kind per
/// day (the day-keyed `MetricWarningNotificationLedger` is the dedup record).
///
/// Ledger mutations are synchronous actor operations. Evaluations may suspend;
/// they must reload the ledger after delivery rather than save an older copy.
actor MetricWarningBackgroundEvaluator {
    typealias WarningResults = [MetricWarningKind: HealthKitFetchEngine.QueryOutcome<MetricWarningEvent>]

    struct Delivery {
        var authorization: @Sendable () async -> UNAuthorizationStatus
        var add: @Sendable (UNNotificationRequest) async throws -> Void
    }
    enum Outcome {
        /// Every requested kind resolved; anything past threshold was notified.
        case success
        /// Some kinds resolved and at least one notification was posted, but at
        /// least one kind was inconclusive.
        case partialFailure
        /// Admission stopped the pass without an observed failure (toggle off,
        /// no kinds, foreground active, or notifications not authorized).
        /// Earlier successful submissions stand. Reported as a successful task.
        case skipped
        /// At least one kind failed and nothing was posted, or evaluation timed out.
        case failure
    }

    /// The one instance both the background task and the foreground seeding go
    /// through, so every ledger read-modify-write is serialized by this actor.
    static let shared = MetricWarningBackgroundEvaluator(
        isForegroundActive: { BodyBackgroundRefreshScheduler.isAppForegroundActive }
    )

    /// Ceiling on the HealthKit work. BGAppRefresh gives ~30s wall-clock; leaving
    /// headroom for the notification add keeps the task from being killed.
    static let evaluationDeadline: Duration = .seconds(20)

    private let defaults: UserDefaults
    private let calendarContext: @Sendable () -> (calendar: Calendar, date: Date)
    private var calendar: Calendar { calendarContext().calendar }
    private let delivery: Delivery
    private let warningQuery: (@Sendable (Set<MetricWarningKind>) async -> WarningResults?)?
    private var evaluationInFlight = false
    private let isForegroundActive: @Sendable () async -> Bool
    /// Injected so the deadline behaviour can be exercised against a fake store
    /// whose reads never resume.
    private let healthStore: any BodyHealthQuerying

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar? = nil,
        notificationCenter: UNUserNotificationCenter = .current(),
        healthStore: any BodyHealthQuerying = HKHealthStore(),
        delivery: Delivery? = nil,
        warningQuery: (@Sendable (Set<MetricWarningKind>) async -> WarningResults?)? = nil,
        calendarContext: (@Sendable () -> (calendar: Calendar, date: Date))? = nil,
        isForegroundActive: @escaping @Sendable () async -> Bool
    ) {
        self.defaults = defaults
        self.calendarContext = calendarContext ?? { (calendar ?? .bodyGregorian, Date()) }
        self.delivery = delivery ?? Delivery(
            authorization: { await notificationCenter.notificationSettings().authorizationStatus },
            add: { try await notificationCenter.add($0) }
        )
        self.warningQuery = warningQuery
        self.healthStore = healthStore
        self.isForegroundActive = isForegroundActive
    }

    @discardableResult
    func evaluate() async -> Outcome {
        guard !evaluationInFlight, !Task.isCancelled else { return .skipped }
        evaluationInFlight = true
        defer { evaluationInFlight = false }
        let context = evaluationContext()
        let calendar = calendar
        guard defaults.bool(forKey: BodyAppearancePreference.metricWarningNotificationsKey) else {
            return .skipped
        }

        let selection = BodyMetricWarningSelection.storedValue(
            from: defaults.string(forKey: BodyAppearancePreference.metricWarningsKey) ?? ""
        )
        let kinds = selection.enabledKinds
        guard !kinds.isEmpty else {
            return .skipped
        }

        // The foreground pipeline owns detection while the app is on screen (and
        // seeds the ledger itself), so a background pass that lands then would
        // only race it.
        if await isForegroundActive() {
            return .skipped
        }

        // Post nothing and leave the ledger untouched when we couldn't deliver:
        // marking a kind notified here would suppress the real notification once
        // the user grants permission.
        switch await delivery.authorization() {
        case .authorized, .provisional:
            break
        default:
            return .skipped
        }

        guard !Task.isCancelled, context == evaluationContext() else { return .skipped }
        let fetched: WarningResults?
        if let warningQuery {
            fetched = await warningQuery(kinds)
        } else {
            fetched = await fetchWarnings(kinds: kinds)
        }
        guard let results = fetched else {
            return .failure
        }

        var postedCount = 0
        var failedCount = 0

        for kind in MetricWarningKind.allCases where kinds.contains(kind) {
            switch results[kind] {
            case .success(let event?):
                // Recheck after all suspension points, including authorization
                // and foreground state. No await between the last context check
                // and submission. Already-submitted requests are not recalled.
                let authorization = await delivery.authorization()
                let foreground = await isForegroundActive()
                guard !Task.isCancelled, !foreground,
                      authorization == .authorized || authorization == .provisional,
                      context == evaluationContext() else {
                    // Losing admission cannot erase failures already observed.
                    guard failedCount == 0 else {
                        return postedCount > 0 ? .partialFailure : .failure
                    }
                    return .skipped
                }
                let ledger = loadLedger()
                guard ledger.shouldNotify(kind: kind, event: event, calendar: calendar) else {
                    continue
                }
                guard await postNotification(for: event, calendar: calendar) else {
                    failedCount += 1
                    continue
                }
                // Ledger advances ONLY after the add succeeded, so a failed
                // delivery is retried by the next background pass.
                var latestLedger = loadLedger()
                // Foreground seeding may have advanced this kind during add.
                // Preserve that newer day as well as unrelated kinds.
                var delivered = MetricWarningNotificationLedger.defaultValue
                delivered.markNotified(kind: kind, on: event.startDate, calendar: calendar)
                if (latestLedger.lastNotifiedDayKeys[kind] ?? "") < (delivered.lastNotifiedDayKeys[kind] ?? "") {
                    latestLedger.markNotified(kind: kind, on: event.startDate, calendar: calendar)
                }
                saveLedger(latestLedger)
                postedCount += 1
            case .success:
                continue
            case .failure, .none:
                failedCount += 1
            }
        }

        guard failedCount == 0 else {
            return postedCount > 0 ? .partialFailure : .failure
        }
        return .success
    }

    /// Marks `kinds` as already seen today, so a background pass doesn't
    /// re-notify what the user just saw on screen. Used by the foreground
    /// refresh's ledger seeding.
    func seed(kinds: [MetricWarningKind: Date]) {
        guard !kinds.isEmpty else {
            return
        }

        var ledger = loadLedger()
        for (kind, date) in kinds {
            ledger.markNotified(kind: kind, on: date, calendar: calendar)
        }
        saveLedger(ledger)
    }

    // MARK: - Fetch

    /// Content-addressed settings revision, excluding the delivery ledger.
    /// Includes the app's standard settings as well as an injected suite; the
    /// headless engine itself receives thresholds captured from this evaluator.
    private func evaluationContext() -> [String] {
        let keys = [
            BodyAppearancePreference.metricWarningNotificationsKey,
            BodyAppearancePreference.metricWarningsKey,
            BodyAppearancePreference.metricWarningThresholdsKey,
            BodyAppearancePreference.healthPermissionSelectionKey,
            BodyAppearancePreference.healthDataSourceSelectionKey,
            BodyAppearancePreference.secondaryHealthDataSourceSelectionKey,
            BodyAppearancePreference.combinesHealthDataSourcesByNameKey,
            BodyAppearancePreference.customHealthSourceGroupsKey
        ]
        let (calendar, now) = calendarContext()
        return [String(describing: calendar.identifier), calendar.timeZone.identifier,
                String(calendar.startOfDay(for: now).timeIntervalSince1970)] + [defaults, UserDefaults.standard].flatMap { suite in
            keys.map { suite.object(forKey: $0).map { String(describing: $0) } ?? "<unset>" }
        }
    }

    /// `nil` when the evaluation overran `evaluationDeadline`, or the task was
    /// cancelled. Raced through `OneShotDeadlineRace` rather than run in a task
    /// group: cancellation is cooperative, so a group — and the old
    /// `await work.value` under a cancelling sleeper — would still wait on a
    /// HealthKit query that never resumes. The deadline now returns without the
    /// work, which is left cancelled and abandoned.
    /// Internal (not private) and with an injectable `deadline` so the
    /// deadline behaviour itself is testable against a store whose reads never
    /// resume; production always uses `evaluationDeadline`.
    func fetchWarnings(
        kinds: Set<MetricWarningKind>,
        deadline: Duration = MetricWarningBackgroundEvaluator.evaluationDeadline
    ) async -> [MetricWarningKind: HealthKitFetchEngine.QueryOutcome<MetricWarningEvent>]? {
        let engine = HealthKitFetchEngine(
            permission: BodyHealthPermissionSelection.load(defaults: defaults),
            healthDataSourceSelection: BodyHealthDataSourceSelection.load(defaults: defaults),
            secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection.load(defaults: defaults),
            combinesHealthDataSourcesByName: defaults.bool(
                forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey
            ),
            customHealthSourceGroups: HealthKitWorkoutStore.loadCustomHealthSourceGroups(defaults: defaults),
            healthStore: healthStore,
            capturedWarningThresholds: BodyMetricWarningThresholds.storedValue(
                from: defaults.string(forKey: BodyAppearancePreference.metricWarningThresholdsKey) ?? ""
            )
        )

        let calendar = calendar
        // Detached so the fetch does not sit on this actor's executor while it
        // awaits the engine actor.
        let work = Task.detached {
            await engine.fetchCurrentMetricWarnings(kinds: kinds, calendar: calendar, now: Date())
        }
        let outcome = await OneShotDeadlineRace.run(deadline: deadline) {
            await work.value
        }
        guard case .finished(let results) = outcome, !Task.isCancelled else {
            work.cancel()
            return nil
        }
        return results
    }

    // MARK: - Notification

    private func postNotification(for event: MetricWarningEvent, calendar: Calendar) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = Self.notificationTitle(for: event.kind)
        content.body = Self.notificationBody(for: event)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: event.kind, date: event.startDate, calendar: calendar),
            content: content,
            trigger: nil
        )

        do {
            try await delivery.add(request)
            return true
        } catch {
            return false
        }
    }

    /// Stable per kind per day, so a duplicate add can only ever replace the
    /// notification already on screen.
    static func notificationIdentifier(for kind: MetricWarningKind, date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let dayKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "warning.\(kind.rawValue).\(dayKey)"
    }

    private static func notificationTitle(for kind: MetricWarningKind) -> String {
        switch kind {
        case .lowHeartRate:
            return String(localized: "Low Heart Rate Warning")
        case .highHeartRate:
            return String(localized: "High Heart Rate Warning")
        case .lowBloodOxygen:
            return String(localized: "Low Blood Oxygen Warning")
        }
    }

    private static func notificationBody(for event: MetricWarningEvent) -> String {
        let threshold = Int(event.threshold.rounded())
        let value = Int(event.extremeValue.rounded())

        switch event.kind {
        case .lowHeartRate:
            return String(localized: "A periodic check found a heart rate of \(value) bpm today, below your \(threshold) bpm limit.")
        case .highHeartRate:
            return String(localized: "A periodic check found a heart rate of \(value) bpm today, above your \(threshold) bpm limit.")
        case .lowBloodOxygen:
            return String(localized: "A periodic check found a blood oxygen level of \(value)% today, below your \(threshold)% limit.")
        }
    }

    // MARK: - Ledger

    private func loadLedger() -> MetricWarningNotificationLedger {
        MetricWarningNotificationLedger.storedValue(
            from: defaults.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey) ?? ""
        )
    }

    private func saveLedger(_ ledger: MetricWarningNotificationLedger) {
        defaults.set(
            ledger.rawValue,
            forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey
        )
    }
}
