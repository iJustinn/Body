//
//  WorkoutCalendarWidget.swift
//  BodyWidgetExtension
//

import AppIntents
import SwiftUI
import WidgetKit

enum BodyWidgetBackgroundSelection: String, AppEnum, Codable, CaseIterable {
    case system
    case black
    case white

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Background")

    static var caseDisplayRepresentations: [BodyWidgetBackgroundSelection: DisplayRepresentation] = [
        .system: "System",
        .black: "Black",
        .white: "White"
    ]
}

struct BodyWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget Appearance"
    static var description = IntentDescription("Choose the widget background.")

    @Parameter(title: "Background")
    var background: BodyWidgetBackgroundSelection?

    init() {}

    init(background: BodyWidgetBackgroundSelection?) {
        self.background = background
    }
}

struct WorkoutCalendarEntry: TimelineEntry {
    let date: Date
    let background: BodyWidgetBackgroundSelection
    let snapshot: WorkoutMonthSnapshot
}

struct WorkoutCalendarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WorkoutCalendarEntry {
        WorkoutCalendarEntry(
            date: Date(),
            background: .system,
            snapshot: .placeholder
        )
    }

    func snapshot(
        for configuration: BodyWidgetConfigurationIntent,
        in context: Context
    ) async -> WorkoutCalendarEntry {
        loadEntry(configuration: configuration)
    }

    func timeline(
        for configuration: BodyWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<WorkoutCalendarEntry> {
        let entry = loadEntry(configuration: configuration)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date.addingTimeInterval(1_800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadEntry(configuration: BodyWidgetConfigurationIntent) -> WorkoutCalendarEntry {
        WorkoutCalendarEntry(
            date: Date(),
            background: configuration.background ?? .system,
            snapshot: WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty()
        )
    }
}

struct BodyWorkoutCalendarWidget: Widget {
    let kind = "BodyWorkoutCalendarWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BodyWidgetConfigurationIntent.self,
            provider: WorkoutCalendarProvider()
        ) { entry in
            WorkoutCalendarWidgetView(entry: entry)
                .bodyWidgetBackground(entry.background)
        }
        .supportedFamilies([.systemLarge])
        .configurationDisplayName("Workout Calendar")
        .description("View this month's workout days.")
        .contentMarginsDisabled()
    }
}

struct BodyWorkoutTypeBreakdownWidget: Widget {
    let kind = "BodyWorkoutTypeBreakdownWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: BodyWidgetConfigurationIntent.self,
            provider: WorkoutCalendarProvider()
        ) { entry in
            WorkoutTypeBreakdownWidgetView(entry: entry)
                .bodyWidgetBackground(entry.background)
        }
        .supportedFamilies([.systemMedium, .systemLarge])
        .configurationDisplayName("Workout Types")
        .description("View this month's workout time by type.")
        .contentMarginsDisabled()
    }
}

private struct WorkoutCalendarWidgetView: View {
    let entry: WorkoutCalendarEntry

    var body: some View {
        WorkoutCalendarView(
            snapshot: entry.snapshot,
            style: .widgetLarge,
            referenceDate: entry.date
        )
        .padding(14)
    }
}

private struct WorkoutTypeBreakdownWidgetView: View {
    let entry: WorkoutCalendarEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        WorkoutTypeBreakdownView(
            snapshot: entry.snapshot,
            style: family == .systemMedium ? .widgetMedium : .widgetLarge
        )
        .padding(family == .systemMedium ? 12 : 14)
    }
}

extension View {
    @ViewBuilder
    func bodyWidgetBackground(_ background: BodyWidgetBackgroundSelection) -> some View {
        switch background {
        case .system:
            self.containerBackground(.widgetBackground, for: .widget)
        case .black:
            self
                .environment(\.colorScheme, .dark)
                .containerBackground(Color.black, for: .widget)
        case .white:
            self
                .environment(\.colorScheme, .light)
                .containerBackground(Color.white, for: .widget)
        }
    }
}
