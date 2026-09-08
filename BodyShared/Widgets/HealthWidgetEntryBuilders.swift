//
//  HealthWidgetEntryBuilders.swift
//  BodyShared
//
//  Resolves the snapshot each health widget provider renders: the
//  placeholder/empty fallback for a missing cache, the stale-sleep
//  sanitization for the current instant, and the Pro gate. Kept out of
//  `BodyWidgetExtension` (which isn't compiled into any test target) so the
//  logic is testable; the providers only map the result onto their entry type.
//

import Foundation

/// Shared resolution for the three snapshot-backed widget providers. The named
/// per-provider builders below forward to it so each provider keeps its own
/// call site while the behavior stays in one place.
private func resolveHealthWidgetSnapshot(
    snapshot: HealthWidgetSnapshot?,
    usePlaceholderWhenEmpty: Bool,
    isPro: Bool,
    now: Date,
    calendar: Calendar
) -> (snapshot: HealthWidgetSnapshot, isPro: Bool) {
    let resolved = (snapshot ?? (usePlaceholderWhenEmpty ? .placeholder : .empty))
        .sanitizingStaleSleep(asOf: now, calendar: calendar)
    return (resolved, isPro)
}

enum HealthMetricEntryBuilder {
    static func resolve(
        snapshot: HealthWidgetSnapshot?,
        usePlaceholderWhenEmpty: Bool,
        isPro: Bool,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> (snapshot: HealthWidgetSnapshot, isPro: Bool) {
        resolveHealthWidgetSnapshot(
            snapshot: snapshot,
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            isPro: isPro,
            now: now,
            calendar: calendar
        )
    }
}

enum HealthTrendEntryBuilder {
    static func resolve(
        snapshot: HealthWidgetSnapshot?,
        usePlaceholderWhenEmpty: Bool,
        isPro: Bool,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> (snapshot: HealthWidgetSnapshot, isPro: Bool) {
        resolveHealthWidgetSnapshot(
            snapshot: snapshot,
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            isPro: isPro,
            now: now,
            calendar: calendar
        )
    }
}

enum SleepStagesEntryBuilder {
    static func resolve(
        snapshot: HealthWidgetSnapshot?,
        usePlaceholderWhenEmpty: Bool,
        isPro: Bool,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> (snapshot: HealthWidgetSnapshot, isPro: Bool) {
        resolveHealthWidgetSnapshot(
            snapshot: snapshot,
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            isPro: isPro,
            now: now,
            calendar: calendar
        )
    }
}
