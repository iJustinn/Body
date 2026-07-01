//
//  HealthTrendWidget.swift
//  BodyWidgetExtension
//
//  Medium widget that charts a chosen metric's weekly/monthly trend for the
//  primary source. The metric, range, and background are chosen in the
//  widget's edit screen.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration enums

enum BodyTrendMetricSelection: String, AppEnum, Codable, CaseIterable {
    case readiness
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case oxygenSaturation
    case sleep
    case wristTemperature
    case steps
    case activeEnergy
    case restingEnergy
    case exerciseMinutes
    case trainingLoad
    case timeInDaylight
    case bodyMass
    case bodyFatPercentage

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")

    static var caseDisplayRepresentations: [BodyTrendMetricSelection: DisplayRepresentation] = [
        .readiness: "Readiness",
        .heartRate: "Heart Rate",
        .restingHeartRate: "Resting Heart Rate",
        .heartRateVariability: "HRV",
        .respiratoryRate: "Respiratory Rate",
        .oxygenSaturation: "Blood Oxygen",
        .sleep: "Sleep",
        .wristTemperature: "Skin Temperature",
        .steps: "Steps",
        .activeEnergy: "Active Energy",
        .restingEnergy: "Resting Energy",
        .exerciseMinutes: "Exercise Minutes",
        .trainingLoad: "Training Load",
        .timeInDaylight: "Time In Daylight",
        .bodyMass: "Weight",
        .bodyFatPercentage: "Body Fat"
    ]

    var widgetMetric: HealthWidgetMetric {
        HealthWidgetMetric(rawValue: rawValue) ?? .readiness
    }
}

enum BodyTrendRangeSelection: String, AppEnum, Codable, CaseIterable {
    case week
    case month

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Range")

    static var caseDisplayRepresentations: [BodyTrendRangeSelection: DisplayRepresentation] = [
        .week: "Week",
        .month: "Month"
    ]

    var widgetRange: HealthWidgetTrendRange {
        switch self {
        case .week: return .week
        case .month: return .month
        }
    }
}

// MARK: - Intent

struct BodyTrendWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Trend"
    static var description = IntentDescription("Choose the metric, range, and background.")

    @Parameter(title: "Metric", default: .readiness)
    var metric: BodyTrendMetricSelection?

    @Parameter(title: "Range", default: .week)
    var range: BodyTrendRangeSelection?

    @Parameter(title: "Background")
    var background: BodyWidgetBackgroundSelection?

    init() {}

    init(
        metric: BodyTrendMetricSelection?,
        range: BodyTrendRangeSelection?,
        background: BodyWidgetBackgroundSelection?
    ) {
        self.metric = metric
        self.range = range
        self.background = background
    }
}

// MARK: - Timeline

struct HealthTrendEntry: TimelineEntry {
    let date: Date
    let background: BodyWidgetBackgroundSelection
    let metric: HealthWidgetMetric
    let range: HealthWidgetTrendRange
    let trend: HealthWidgetMetricTrend?
    let isPro: Bool
}

struct HealthTrendProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HealthTrendEntry {
        entry(snapshot: .placeholder, metric: .readiness, range: .week, background: .system, isPro: true)
    }

    func snapshot(
        for configuration: BodyTrendWidgetConfigurationIntent,
        in context: Context
    ) async -> HealthTrendEntry {
        loadEntry(configuration: configuration, usePlaceholderWhenEmpty: context.isPreview)
    }

    func timeline(
        for configuration: BodyTrendWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<HealthTrendEntry> {
        let entry = loadEntry(configuration: configuration, usePlaceholderWhenEmpty: false)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(
        configuration: BodyTrendWidgetConfigurationIntent,
        usePlaceholderWhenEmpty: Bool
    ) -> HealthTrendEntry {
        let metric = (configuration.metric ?? .readiness).widgetMetric
        let range = (configuration.range ?? .week).widgetRange
        let loaded = HealthWidgetSnapshotStore.load()
        let snapshot = loaded ?? (usePlaceholderWhenEmpty ? .placeholder : .empty)
        return entry(
            snapshot: snapshot,
            metric: metric,
            range: range,
            background: configuration.background ?? .system,
            // Preview/gallery shows the real widget; the live timeline respects the flag.
            isPro: usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked
        )
    }

    private func entry(
        snapshot: HealthWidgetSnapshot,
        metric: HealthWidgetMetric,
        range: HealthWidgetTrendRange,
        background: BodyWidgetBackgroundSelection,
        isPro: Bool
    ) -> HealthTrendEntry {
        HealthTrendEntry(
            date: Date(),
            background: background,
            metric: metric,
            range: range,
            trend: snapshot.trend(for: metric),
            isPro: isPro
        )
    }
}

// MARK: - Widget

struct BodyHealthTrendWidget: Widget {
    let kind = "BodyHealthTrendWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BodyTrendWidgetConfigurationIntent.self,
            provider: HealthTrendProvider()
        ) { entry in
            Group {
                if entry.isPro {
                    HealthTrendWidgetView(entry: entry)
                } else {
                    BodyWidgetLockedView()
                }
            }
            .bodyWidgetBackground(entry.background)
        }
        .supportedFamilies([.systemMedium])
        .configurationDisplayName("Health Trend")
        .description("Chart a metric's weekly or monthly trend.")
        .contentMarginsDisabled()
    }
}

private struct HealthTrendWidgetView: View {
    let entry: HealthTrendEntry

    var body: some View {
        HealthWidgetTrendChartView(
            metric: entry.metric,
            range: entry.range,
            trend: entry.trend
        )
        .padding(14)
    }
}
