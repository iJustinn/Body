//
//  HealthMetricWidget.swift
//  BodyWidgetExtension
//
//  Small widget that mirrors a home screen metric preview card (title, current
//  value + unit, trend sparkline, icon) for a chosen metric. Metric and
//  background are chosen in the widget's edit screen.
//

import AppIntents
import SwiftUI
import WidgetKit

struct BodyMetricWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Metric"
    static var description = IntentDescription("Choose the metric and background.")

    @Parameter(title: "Metric", default: .readiness)
    var metric: BodyTrendMetricSelection?

    @Parameter(title: "Background")
    var background: BodyWidgetBackgroundSelection?

    init() {}

    init(metric: BodyTrendMetricSelection?, background: BodyWidgetBackgroundSelection?) {
        self.metric = metric
        self.background = background
    }
}

struct HealthMetricEntry: TimelineEntry {
    let date: Date
    let background: BodyWidgetBackgroundSelection
    let metric: HealthWidgetMetric
    let trend: HealthWidgetMetricTrend?
    let isPro: Bool
}

struct HealthMetricProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HealthMetricEntry {
        entry(snapshot: .placeholder, metric: .readiness, background: .system, isPro: true)
    }

    func snapshot(
        for configuration: BodyMetricWidgetConfigurationIntent,
        in context: Context
    ) async -> HealthMetricEntry {
        loadEntry(configuration: configuration, usePlaceholderWhenEmpty: context.isPreview)
    }

    func timeline(
        for configuration: BodyMetricWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<HealthMetricEntry> {
        let entry = loadEntry(configuration: configuration, usePlaceholderWhenEmpty: false)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(
        configuration: BodyMetricWidgetConfigurationIntent,
        usePlaceholderWhenEmpty: Bool
    ) -> HealthMetricEntry {
        let metric = (configuration.metric ?? .readiness).widgetMetric
        let loaded = HealthWidgetSnapshotStore.load()
        let snapshot = (loaded ?? (usePlaceholderWhenEmpty ? .placeholder : .empty))
            .sanitizingStaleSleep(asOf: Date())
        return entry(
            snapshot: snapshot,
            metric: metric,
            background: configuration.background ?? .system,
            // Preview/gallery (usePlaceholderWhenEmpty) shows the real widget so users
            // see what Body Pro unlocks; the live home-screen timeline respects the flag.
            isPro: usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked
        )
    }

    private func entry(
        snapshot: HealthWidgetSnapshot,
        metric: HealthWidgetMetric,
        background: BodyWidgetBackgroundSelection,
        isPro: Bool
    ) -> HealthMetricEntry {
        HealthMetricEntry(
            date: Date(),
            background: background,
            metric: metric,
            trend: snapshot.trend(for: metric),
            isPro: isPro
        )
    }
}

struct BodyHealthMetricWidget: Widget {
    let kind = "BodyHealthMetricWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BodyMetricWidgetConfigurationIntent.self,
            provider: HealthMetricProvider()
        ) { entry in
            Group {
                if entry.isPro {
                    HealthMetricWidgetView(entry: entry)
                } else {
                    BodyWidgetLockedView()
                }
            }
            .bodyWidgetBackground(entry.background)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("Health Metric")
        .description("View a metric's current value and recent trend.")
        .contentMarginsDisabled()
    }
}

private struct HealthMetricWidgetView: View {
    let entry: HealthMetricEntry

    var body: some View {
        HealthWidgetMetricCardView(
            metric: entry.metric,
            trend: entry.trend
        )
        .padding(.horizontal, 15)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
