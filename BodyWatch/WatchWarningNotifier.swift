//
//  WatchWarningNotifier.swift
//  BodyWatch
//
//  The watch's own threshold warning notifications. After each compute merge
//  (`WatchMetricsModel.recomputeIfStale`) it looks at the warnings this
//  watch's compute checked itself (`WatchMetricsSnapshot.warningChecks`) and
//  notifies the new ones while the phone's warning notifications are on, at
//  most once per kind per day across both devices: it skips a kind the
//  phone's ledger holds for today (`WatchWarningSettings.notifiedDays`),
//  keeps its own ledger of the kinds it notified, and tells the phone of
//  each one (`WatchWarningNotificationSync`) so the phone skips it too. A
//  notification carries the phone's identifier, title and body, so the two
//  read the same and two posts made moments apart show as one.
//
//  In the foreground a due warning is already on screen, so it is only
//  marked and reported, the phone's rule for what it shows on screen. In the
//  background it is posted when the watch's notification permission allows
//  it, and only a successful post is marked and reported. The permission is
//  asked for when the app becomes active, never from the background.
//

import Foundation
import os
@preconcurrency import UserNotifications
import WatchConnectivity
import WatchKit

@MainActor
final class WatchWarningNotifier {
    static let shared = WatchWarningNotifier()

    /// The notification center calls, injected so tests post nothing.
    struct Delivery {
        var authorizationStatus: @Sendable () async -> UNAuthorizationStatus
        var add: @Sendable (UNNotificationRequest) async throws -> Void
        var requestAuthorization: @Sendable () async -> Void

        static let live = Delivery(
            authorizationStatus: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
            add: { try await UNUserNotificationCenter.current().add($0) },
            requestAuthorization: {
                do {
                    _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                } catch {
                    WatchWarningNotifier.logger.error(
                        "Notification permission request failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        )
    }

    /// Reports notified warnings to the phone; injected so tests can see what
    /// would be sent without a live `WCSession`.
    typealias Send = @MainActor ([WatchWarningNotificationSync.Record]) -> Void

    private let delivery: Delivery
    private let send: Send
    /// Holds the watch's own notification ledger.
    private let defaults: UserDefaults
    private let isForeground: @MainActor () -> Bool
    /// Set while a background pass awaits the notification center, so a
    /// second pass meanwhile (two triggers can merge the same compute) can't
    /// post the same warning again. The skipped pass loses nothing: the next
    /// compute finds anything the first one left.
    private var isPosting = false

    private nonisolated static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchWarningNotifier")

    init(
        delivery: Delivery = .live,
        send: @escaping Send = { WatchWarningNotifier.sendToPhone($0) },
        defaults: UserDefaults = .standard,
        isForeground: @escaping @MainActor () -> Bool = { WKApplication.shared().applicationState == .active }
    ) {
        self.delivery = delivery
        self.send = send
        self.defaults = defaults
        self.isForeground = isForeground
    }

    /// The warnings to notify now, one event per check that passes every
    /// rule: an episode that started on `now`'s day, of a kind turned on in
    /// the phone's Warnings and checked against the limit the phone holds now,
    /// not starting inside one of `spans` or the 30 minutes after it (High
    /// Heart Rate), with the phone's warning notifications on, and notified
    /// today by neither the phone (`settings.notifiedDays`) nor this watch
    /// (`watchLedger`).
    ///
    /// High Heart Rate also waits until its episode has been over for the
    /// workout recovery grace (`MetricThresholdWarning.workoutRecoveryGrace`).
    /// A workout still being recorded keeps the episode going and isn't
    /// saved yet, so no span covers it; once the workout ends it is normally
    /// saved within that time, and the next compute then leaves its readings
    /// out, so the workout doesn't alert. A workout left running, or a lull
    /// below the limit longer than that inside one, still can.
    static func due(
        checks: [WatchWarningCheck]?,
        settings: WatchWarningSettings?,
        spans: [WatchWorkoutSpan]?,
        watchLedger: MetricWarningNotificationLedger,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [MetricWarningEvent] {
        guard let settings, settings.notifies else { return [] }
        let today = MetricWarningDayKey.dayText(for: now, calendar: calendar)
        return (checks ?? []).compactMap { check in
            guard let kind = MetricWarningKind(rawValue: check.kind),
                  let episode = check.episode,
                  calendar.isDate(episode.startDate, inSameDayAs: now),
                  settings.enabledKinds.contains(check.kind),
                  settings.thresholds[check.kind] == check.threshold,
                  !WatchMetricWarnings.startsInsideWorkout(kind: kind, startDate: episode.startDate, spans: spans),
                  settings.notifiedDays[check.kind] != today else { return nil }
            if kind.excludesWorkouts,
               now.timeIntervalSince(episode.endDate) < MetricThresholdWarning.workoutRecoveryGrace {
                return nil
            }
            let event = MetricWarningEvent(
                kind: kind,
                startDate: episode.startDate,
                endDate: episode.endDate,
                extremeValue: episode.extremeValue,
                sampleCount: 1,
                threshold: check.threshold
            )
            return watchLedger.shouldNotify(kind: kind, event: event, calendar: calendar) ? event : nil
        }
    }

    /// Notifies the warnings due in `snapshot` (see `due`). In the
    /// foreground they are only marked in the watch's ledger and reported to
    /// the phone. In the background each is posted when notifications are
    /// authorized, and marked and reported only once its post succeeded, so
    /// a failed one is tried again on the next compute.
    func process(_ snapshot: WatchMetricsSnapshot, now: Date) async {
        guard !isPosting else { return }
        let calendar = Calendar.bodyGregorian
        let events = Self.due(
            checks: snapshot.warningChecks,
            settings: snapshot.warningSettings,
            spans: snapshot.workoutSpans,
            watchLedger: loadLedger(),
            now: now,
            calendar: calendar
        )
        guard !events.isEmpty else { return }

        if isForeground() {
            events.forEach { markNotified($0, calendar: calendar) }
            send(events.map(Self.record(for:)))
            Self.logger.info(
                "Warnings shown in the foreground: \(events.map(\.kind.rawValue).joined(separator: ", "), privacy: .public)"
            )
            return
        }

        isPosting = true
        defer { isPosting = false }
        switch await delivery.authorizationStatus() {
        case .authorized, .provisional:
            break
        default:
            Self.logger.info("Warnings not notified: notifications aren't authorized")
            return
        }

        // A skin temperature reads in the Skin Temp card's unit; nil (an
        // older phone) reads as Celsius.
        let usesFahrenheit = snapshot.metric(forKind: WatchMetricKindKey.wristTemperature)?.usesFahrenheit ?? false
        var notified: [WatchWarningNotificationSync.Record] = []
        for event in events {
            guard await post(event, usesFahrenheit: usesFahrenheit, calendar: calendar) else { continue }
            markNotified(event, calendar: calendar)
            notified.append(Self.record(for: event))
        }
        guard !notified.isEmpty else { return }
        send(notified)
        Self.logger.info("Warnings notified: \(notified.map(\.kind).joined(separator: ", "), privacy: .public)")
    }

    /// Asks for notification permission while the phone's warning
    /// notifications are on and the watch has never asked. Called when the
    /// app becomes active only: the request shows a prompt.
    func requestAuthorizationIfNeeded(settings: WatchWarningSettings?) async {
        guard settings?.notifies == true else { return }
        guard await delivery.authorizationStatus() == .notDetermined else { return }
        await delivery.requestAuthorization()
    }

    /// Sends records to the phone the way `WatchWarningFoldStore.sendToPhone`
    /// sends folds: always `transferUserInfo`, which is queued and survives
    /// either side being suspended, and also `sendMessage` while the phone is
    /// reachable, which wakes the iPhone app so it hears at once. Before the
    /// session has activated nothing is sent, and the phone may then notify
    /// the same kind itself.
    static func sendToPhone(_ records: [WatchWarningNotificationSync.Record]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            Self.logger.info("Warning notification not reported: the session isn't activated")
            return
        }
        guard let payload = WatchWarningNotificationSync.payload(for: records) else {
            Self.logger.error("Warning notification not reported: the records didn't encode")
            return
        }

        let session = WCSession.default
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: { _ in },
                errorHandler: { error in
                    Self.logger.error("Warning notification message failed: \(error.localizedDescription, privacy: .public)")
                }
            )
        }
    }

    /// Posts `event` under the phone's identifier, title and body. False when
    /// the notification center refused it.
    private func post(_ event: MetricWarningEvent, usesFahrenheit: Bool, calendar: Calendar) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = MetricWarningNotificationContent.title(for: event.kind)
        content.body = MetricWarningNotificationContent.body(
            for: event,
            temperatureUnitPreference: usesFahrenheit ? .fahrenheit : .celsius
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: MetricWarningDayKey.notificationIdentifier(kind: event.kind, date: event.startDate, calendar: calendar),
            content: content,
            trigger: nil
        )

        do {
            try await delivery.add(request)
            return true
        } catch {
            Self.logger.error("Warning notification failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func record(for event: MetricWarningEvent) -> WatchWarningNotificationSync.Record {
        WatchWarningNotificationSync.Record(kind: event.kind.rawValue, startDate: event.startDate)
    }

    // MARK: - Ledger

    /// Reloaded before each mark, so a kind marked during an await is kept.
    private func markNotified(_ event: MetricWarningEvent, calendar: Calendar) {
        var ledger = loadLedger()
        ledger.markNotified(kind: event.kind, on: event.startDate, calendar: calendar)
        defaults.set(ledger.rawValue, forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey)
    }

    private func loadLedger() -> MetricWarningNotificationLedger {
        MetricWarningNotificationLedger.storedValue(
            from: defaults.string(forKey: MetricWarningNotificationLedger.metricWarningNotificationLedgerKey) ?? ""
        )
    }
}
