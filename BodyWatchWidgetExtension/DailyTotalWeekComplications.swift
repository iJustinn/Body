//
//  DailyTotalWeekComplications.swift
//  BodyWatchWidgetExtension
//
//  Watch complications (accessoryRectangular only) for Steps, Active Energy
//  and Resting Energy, in the style of Weekly Workout Time: a header with the
//  week's total plus seven bars of daily totals, today rightmost. The bars are
//  `WatchWeekBarsView`, the same chart these metrics' detail pages draw. Free
//  (not Pro-gated), like the other bar complications. Reuses the existing
//  `WatchMetricProvider`/`WatchMetricEntry`, which already carries the whole
//  snapshot.
//

import SwiftUI
import WidgetKit

struct StepsWeekComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchStepsWeek", provider: WatchMetricProvider()) { entry in
            DailyTotalWeekComplicationView(metricKind: WatchMetricKindKey.steps, entry: entry)
                // Tapping the complication opens the Steps detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.steps))
        }
        .configurationDisplayName(String(localized: "Steps"))
        .description(String(localized: "This week's daily steps."))
        .supportedFamilies([.accessoryRectangular])
    }
}

struct ActiveEnergyWeekComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchActiveEnergyWeek", provider: WatchMetricProvider()) { entry in
            DailyTotalWeekComplicationView(metricKind: WatchMetricKindKey.activeEnergy, entry: entry)
                // Tapping the complication opens the Active Energy detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.activeEnergy))
        }
        .configurationDisplayName(String(localized: "Active Energy"))
        .description(String(localized: "This week's daily active energy."))
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RestingEnergyWeekComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchRestingEnergyWeek", provider: WatchMetricProvider()) { entry in
            DailyTotalWeekComplicationView(metricKind: WatchMetricKindKey.restingEnergy, entry: entry)
                // Tapping the complication opens the Resting Energy detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.restingEnergy))
        }
        .configurationDisplayName(String(localized: "Resting Energy"))
        .description(String(localized: "This week's daily resting energy."))
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct DailyTotalWeekComplicationView: View {
    let metricKind: String
    let entry: WatchMetricEntry

    private var metric: WatchMetric? { entry.snapshot.metric(forKind: metricKind) }

    /// Re-windowed to the entry's day (see `weeklyRewound`), so a snapshot
    /// from an earlier day never keeps yesterday as the rightmost bar. The
    /// gallery placeholder (`WatchMetricsSnapshot.placeholder`, generated at
    /// `.distantPast` with no `weeklyAsOf`) is drawn as is: rewinding it would
    /// shift its sample week out entirely and preview the empty state.
    private var weekly: [Double?] {
        guard let metric else { return Array(repeating: nil, count: 7) }
        if entry.snapshot.generatedAt == .distantPast {
            let week = Array((metric.weekly ?? []).suffix(7))
            return Array(repeating: nil, count: 7 - week.count) + week
        }
        return metric.weeklyRewound(from: entry.snapshot.generatedAt, to: entry.date)
    }

    var body: some View {
        Group {
            if let metric, weekly.contains(where: { $0 != nil }) {
                WatchWeekBarsView(
                    weekly: weekly,
                    today: entry.date,
                    tint: Color(WatchMetricKindKey.tint(forKind: metricKind)),
                    header: header(for: metric)
                )
            } else {
                Text("Open Body on iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    /// The week's total in one format key per kind (like "%lld MIN THIS
    /// WEEK") so the whole phrase, unit included, translates as a unit. The
    /// energy unit comes from `usesKilojoules`, not the metric's unit string,
    /// which the midnight clear blanks.
    private func header(for metric: WatchMetric) -> String {
        let total = weekly.compactMap { $0 }.reduce(0, +)
        let totalText = total.formatted(.number.precision(.fractionLength(0)))
        if metricKind == WatchMetricKindKey.steps {
            return String(localized: "\(totalText) STEPS THIS WEEK")
        }
        return metric.usesKilojoules == true
            ? String(localized: "\(totalText) KJ THIS WEEK")
            : String(localized: "\(totalText) KCAL THIS WEEK")
    }
}
