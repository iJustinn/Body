//
//  MetricWarningNotificationLedger.swift
//  BodyMetricsKit
//

import Foundation

/// Tracks, per `MetricWarningKind`, the calendar day a warning notification
/// was last posted (or otherwise seen), so background refreshes never post
/// more than one notification per kind per day. Day is keyed by a
/// "yyyy-MM-dd" string rather than a `Date`, so the value is stable across
/// encode/decode and unambiguous regardless of time-of-day.
struct MetricWarningNotificationLedger: Equatable {
    static let defaultValue = MetricWarningNotificationLedger(lastNotifiedDayKeys: [:])

    /// The Settings/UserDefaults key this ledger round-trips through. Kept
    /// here rather than in `BodyAppearancePreference` (BodyHealthSelections.swift),
    /// which owns the app's other persisted keys but wasn't a required home
    /// for this one.
    static let metricWarningNotificationLedgerKey = "metricWarningNotificationLedger"

    var lastNotifiedDayKeys: [MetricWarningKind: String]

    /// True iff no notification has been recorded for this kind on the day
    /// the event started.
    func shouldNotify(kind: MetricWarningKind, event: MetricWarningEvent, calendar: Calendar) -> Bool {
        lastNotifiedDayKeys[kind] != Self.dayKey(for: event.startDate, calendar: calendar)
    }

    /// Records that a notification for `kind` was posted (or seen) on `date`'s day.
    mutating func markNotified(kind: MetricWarningKind, on date: Date, calendar: Calendar) {
        lastNotifiedDayKeys[kind] = Self.dayKey(for: date, calendar: calendar)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    var rawValue: String {
        guard !lastNotifiedDayKeys.isEmpty else {
            return ""
        }

        let object = Dictionary(uniqueKeysWithValues: lastNotifiedDayKeys.map { ($0.key.rawValue, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(object),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string
    }

    static func storedValue(from rawValue: String) -> MetricWarningNotificationLedger {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let data = trimmedValue.data(using: .utf8),
              let object = try? JSONDecoder().decode([String: String].self, from: data) else {
            return defaultValue
        }

        var lastNotifiedDayKeys: [MetricWarningKind: String] = [:]
        for (key, value) in object {
            guard let kind = MetricWarningKind(rawValue: key) else {
                continue
            }
            lastNotifiedDayKeys[kind] = value
        }

        return MetricWarningNotificationLedger(lastNotifiedDayKeys: lastNotifiedDayKeys)
    }
}
