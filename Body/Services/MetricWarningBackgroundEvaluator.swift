//
//  MetricWarningBackgroundEvaluator.swift
//  Body
//

import Foundation
import HealthKit
import UserNotifications

/// Runs ONE headless metric-warning evaluation for the background refresh task:
/// reads the persisted warning settings, fetches today's warnings through a
/// fresh `HealthKitFetchEngine`, and posts at most one notification per kind per
/// day (the day-keyed `MetricWarningNotificationLedger` is the dedup record).
///
/// An actor so the ledger's read-modify-write can never interleave with the
/// foreground seeding path or a second background pass.
actor MetricWarningBackgroundEvaluator {
    enum Outcome {
        /// Every requested kind resolved; anything past threshold was notified.
        case success
        /// Some kinds resolved and at least one notification was posted, but at
        /// least one kind was inconclusive.
        case partialFailure
        /// Nothing was attempted (toggle off, no kinds, app foreground-active,
        /// notifications not authorized). Reported as a *successful* task run:
        /// there was no work, not a failed attempt.
        case skipped
        /// Nothing usable came back — every kind was inconclusive, or the
        /// evaluation timed out.
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
    private let calendar: Calendar
    private let notificationCenter: UNUserNotificationCenter
    private let isForegroundActive: @Sendable () async -> Bool
    /// Injected so the deadline behaviour can be exercised against a fake store
    /// whose reads never resume.
    private let healthStore: any BodyHealthQuerying

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .bodyGregorian,
        notificationCenter: UNUserNotificationCenter = .current(),
        healthStore: any BodyHealthQuerying = HKHealthStore(),
        isForegroundActive: @escaping @Sendable () async -> Bool
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        self.healthStore = healthStore
        self.isForegroundActive = isForegroundActive
    }

    @discardableResult
    func evaluate() async -> Outcome {
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
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        default:
            return .skipped
        }

        guard let results = await fetchWarnings(kinds: kinds) else {
            return .failure
        }

        var postedCount = 0
        var failedCount = 0
        var ledger = loadLedger()

        for kind in MetricWarningKind.allCases where kinds.contains(kind) {
            switch results[kind] {
            case .success(let event?):
                guard ledger.shouldNotify(kind: kind, event: event, calendar: calendar) else {
                    continue
                }
                guard await postNotification(for: event) else {
                    failedCount += 1
                    continue
                }
                // Ledger advances ONLY after the add succeeded, so a failed
                // delivery is retried by the next background pass.
                ledger.markNotified(kind: kind, on: event.startDate, calendar: calendar)
                saveLedger(ledger)
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
            permission: BodyHealthPermissionSelection.load(),
            healthDataSourceSelection: BodyHealthDataSourceSelection.load(),
            secondaryHealthDataSourceSelection: BodyHealthSecondaryDataSourceSelection.load(),
            combinesHealthDataSourcesByName: defaults.bool(
                forKey: BodyAppearancePreference.combinesHealthDataSourcesByNameKey
            ),
            customHealthSourceGroups: HealthKitWorkoutStore.loadCustomHealthSourceGroups(defaults: defaults),
            healthStore: healthStore
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

    private func postNotification(for event: MetricWarningEvent) async -> Bool {
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
            try await notificationCenter.add(request)
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
