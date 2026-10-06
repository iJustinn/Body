//
//  MetricWarningDayKey.swift
//  BodyMetricsKit
//
//  The one place a threshold warning's day is spelled: the "yyyy-MM-dd" day
//  text, the fold key built on it ("highHeartRate@2026-10-05", the iPhone's
//  `dismissedMetricWarnings` entry and the unit of the watch fold sync), and
//  the notification identifier ("warning.highHeartRate.2026-10-05", stable per
//  kind per day). Shared by the iPhone and the watch, so a warning the watch
//  detects itself folds, syncs and notifies under the same strings as one the
//  iPhone detected.
//

import Foundation

enum MetricWarningDayKey {
    /// `date`'s day in `calendar` as "yyyy-MM-dd", which sorts
    /// chronologically as text.
    static func dayText(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// The fold key of the `kind` warning whose episode started at `startDate`.
    static func foldKey(kind: MetricWarningKind, startDate: Date, calendar: Calendar) -> String {
        "\(kind.rawValue)@\(dayText(for: startDate, calendar: calendar))"
    }

    /// The identifier of the `kind` warning notification for `date`'s day, so a
    /// repeated post (or one from the other device) replaces rather than stacks.
    static func notificationIdentifier(kind: MetricWarningKind, date: Date, calendar: Calendar) -> String {
        "warning.\(kind.rawValue).\(dayText(for: date, calendar: calendar))"
    }
}
