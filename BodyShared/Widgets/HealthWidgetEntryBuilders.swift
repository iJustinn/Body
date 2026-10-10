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

/// Picks the card the large Trends widget shows.
enum TrendCardEntryBuilder {
    enum Resolution: Equatable {
        case card(HealthWidgetTrendCard)
        /// Nothing to show. `metric` is the pinned metric's raw value (`nil` for
        /// Top Trend); `isInTrends` says whether Home's Trends list includes it,
        /// since a metric hidden from Trends may never have its year fetched.
        case empty(metric: String?, isInTrends: Bool)
    }

    /// `pinnedMetric` is a `HealthMetricKind` raw value, or `nil` for Top Trend.
    ///
    /// Top Trend follows Home's collapsed Trends list: the first card in Home's
    /// order whose change is meaningful, which is the first card Home shows. When
    /// no selected trend changed, that list is empty, so the widget falls back to
    /// the first steady card, the first one "Show All Trends" shows. A pinned
    /// metric shows its card whether it changed or not, like its detail page.
    static func resolve(
        snapshot: HealthWidgetSnapshot?,
        pinnedMetric: String?,
        usePlaceholderWhenEmpty: Bool,
        isPro: Bool,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> (resolution: Resolution, isPro: Bool) {
        let resolved = resolveHealthWidgetSnapshot(
            snapshot: snapshot,
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            isPro: isPro,
            now: now,
            calendar: calendar
        ).snapshot
        if let pinnedMetric {
            if let card = resolved.trendCard(for: pinnedMetric) {
                return (.card(card), isPro)
            }
            // No order yet (no file, or one from before this widget) is unknown,
            // not turned off: the app just has not written the cards.
            let isInTrends = resolved.trendCardOrder?.contains(pinnedMetric) ?? true
            return (.empty(metric: pinnedMetric, isInTrends: isInTrends), isPro)
        }

        let ordered = (resolved.trendCardOrder ?? []).compactMap { resolved.trendCard(for: $0) }
        if let card = ordered.first(where: \.isMeaningful) ?? ordered.first {
            return (.card(card), isPro)
        }
        return (.empty(metric: nil, isInTrends: true), isPro)
    }
}
