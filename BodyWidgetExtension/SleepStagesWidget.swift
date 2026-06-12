//
//  SleepStagesWidget.swift
//  BodyWidgetExtension
//
//  Medium widget that charts the most recent night's sleep stages for the
//  primary source selected in the app. Background is chosen in the widget's
//  edit screen (reusing BodyWidgetConfigurationIntent).
//

import AppIntents
import SwiftUI
import WidgetKit

struct SleepStagesEntry: TimelineEntry {
    let date: Date
    let background: BodyWidgetBackgroundSelection
    let sleep: HealthWidgetSleepStages
}

struct SleepStagesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SleepStagesEntry {
        SleepStagesEntry(date: Date(), background: .system, sleep: HealthWidgetSnapshot.placeholder.sleep)
    }

    func snapshot(
        for configuration: BodyWidgetConfigurationIntent,
        in context: Context
    ) async -> SleepStagesEntry {
        loadEntry(configuration: configuration, usePlaceholderWhenEmpty: context.isPreview)
    }

    func timeline(
        for configuration: BodyWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<SleepStagesEntry> {
        let entry = loadEntry(configuration: configuration, usePlaceholderWhenEmpty: false)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(
        configuration: BodyWidgetConfigurationIntent,
        usePlaceholderWhenEmpty: Bool
    ) -> SleepStagesEntry {
        let loaded = HealthWidgetSnapshotStore.load()
        let snapshot = loaded ?? (usePlaceholderWhenEmpty ? .placeholder : .empty)
        return SleepStagesEntry(
            date: Date(),
            background: configuration.background ?? .system,
            sleep: snapshot.sleep
        )
    }
}

struct BodySleepStagesWidget: Widget {
    let kind = "BodySleepStagesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BodyWidgetConfigurationIntent.self,
            provider: SleepStagesProvider()
        ) { entry in
            SleepStagesWidgetView(entry: entry)
                .bodyWidgetBackground(entry.background)
        }
        .supportedFamilies([.systemMedium])
        .configurationDisplayName("Sleep Stages")
        .description("View last night's sleep stages.")
        .contentMarginsDisabled()
    }
}

private struct SleepStagesWidgetView: View {
    let entry: SleepStagesEntry

    var body: some View {
        HealthWidgetSleepStagesView(sleep: entry.sleep)
            .padding(14)
    }
}
