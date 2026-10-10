//
//  TrendCardWidget.swift
//  BodyWidgetExtension
//
//  Large widget that shows one of Home's Trends cards: by default the top trend
//  Home shows, or a metric pinned in the widget's edit screen. The app builds the
//  cards into the widget snapshot (`HealthWidgetSnapshotBuilder.trendCards`).
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration enums

/// Top Trend, or one of Home's trend cards. Raw values are `HealthMetricKind` raw
/// values, which the snapshot's cards are keyed by.
enum BodyTrendCardMetricSelection: String, AppEnum, Codable, CaseIterable {
    case top
    case readiness
    case stress
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case cardioFitness
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

    static var caseDisplayRepresentations: [BodyTrendCardMetricSelection: DisplayRepresentation] = [
        .top: "Top Trend",
        .readiness: "Readiness",
        .stress: "Stress",
        .heartRate: "Heart Rate",
        .restingHeartRate: "Resting Heart Rate",
        .heartRateVariability: "HRV",
        .cardioFitness: "Cardio Fitness",
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

    /// The pinned metric's `HealthMetricKind` raw value, `nil` for Top Trend.
    var pinnedMetric: String? {
        self == .top ? nil : rawValue
    }

    var title: String {
        Self.caseDisplayRepresentations[self].map { String(localized: $0.title) } ?? rawValue
    }
}

// MARK: - Intent

struct BodyTrendCardWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Trends"
    static var description = IntentDescription("Choose the trend and background.")

    @Parameter(title: "Metric", default: .top)
    var metric: BodyTrendCardMetricSelection?

    @Parameter(title: "Background")
    var background: BodyWidgetBackgroundSelection?

    init() {}

    init(metric: BodyTrendCardMetricSelection?, background: BodyWidgetBackgroundSelection?) {
        self.metric = metric
        self.background = background
    }
}

// MARK: - Timeline

struct TrendCardEntry: TimelineEntry {
    let date: Date
    let background: BodyWidgetBackgroundSelection
    let selection: BodyTrendCardMetricSelection
    let resolution: TrendCardEntryBuilder.Resolution
    let isPro: Bool
}

struct TrendCardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TrendCardEntry {
        entry(
            snapshot: .placeholder,
            selection: .top,
            background: .system,
            usePlaceholderWhenEmpty: true,
            isPro: true
        )
    }

    func snapshot(
        for configuration: BodyTrendCardWidgetConfigurationIntent,
        in context: Context
    ) async -> TrendCardEntry {
        loadEntry(configuration: configuration, usePlaceholderWhenEmpty: context.isPreview)
    }

    func timeline(
        for configuration: BodyTrendCardWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<TrendCardEntry> {
        let entry = loadEntry(configuration: configuration, usePlaceholderWhenEmpty: false)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(
        configuration: BodyTrendCardWidgetConfigurationIntent,
        usePlaceholderWhenEmpty: Bool
    ) -> TrendCardEntry {
        entry(
            snapshot: HealthWidgetSnapshotStore.load(),
            selection: configuration.metric ?? .top,
            background: configuration.background ?? .system,
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            // Preview/gallery shows the real widget; the live timeline respects the flag.
            isPro: usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked
        )
    }

    private func entry(
        snapshot: HealthWidgetSnapshot?,
        selection: BodyTrendCardMetricSelection,
        background: BodyWidgetBackgroundSelection,
        usePlaceholderWhenEmpty: Bool,
        isPro: Bool
    ) -> TrendCardEntry {
        let now = Date()
        let resolved = TrendCardEntryBuilder.resolve(
            snapshot: snapshot,
            pinnedMetric: selection.pinnedMetric,
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            isPro: isPro,
            now: now
        )
        return TrendCardEntry(
            date: now,
            background: background,
            selection: selection,
            resolution: resolved.resolution,
            isPro: resolved.isPro
        )
    }
}

// MARK: - Widget

struct BodyTrendCardWidget: Widget {
    let kind = "BodyTrendCardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BodyTrendCardWidgetConfigurationIntent.self,
            provider: TrendCardProvider()
        ) { entry in
            Group {
                if entry.isPro {
                    HealthWidgetTrendCardView(
                        resolution: entry.resolution,
                        pinnedTitle: entry.selection.pinnedMetric == nil ? nil : entry.selection.title
                    )
                    .padding(16)
                } else {
                    BodyWidgetLockedView()
                }
            }
            .bodyWidgetBackground(entry.background, tint: HealthWidgetTrendCardView.tint(for: entry.resolution))
        }
        .supportedFamilies([.systemLarge])
        .configurationDisplayName("Trends")
        .description("Show your top trend from Summary, or pin one metric.")
        .contentMarginsDisabled()
    }
}
