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
    let isPro: Bool
    /// Raw `BodyWorkoutColorOverrides` string read from the App Group at entry-load
    /// time. Carried on the entry (rather than resolved once here) so the widget
    /// views build the same `BodyWorkoutColorPalette` the app would for this data.
    let workoutColorsRawValue: String
}

struct WorkoutCalendarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WorkoutCalendarEntry {
        WorkoutCalendarEntry(
            date: Date(),
            background: .system,
            snapshot: .placeholder,
            isPro: true,
            workoutColorsRawValue: ""
        )
    }

    func snapshot(
        for configuration: BodyWidgetConfigurationIntent,
        in context: Context
    ) async -> WorkoutCalendarEntry {
        loadEntry(
            configuration: configuration,
            usePlaceholderWhenEmpty: context.isPreview,
            isPro: context.isPreview || BodyProEntitlement.isUnlocked,
            now: Date()
        )
    }

    func timeline(
        for configuration: BodyWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<WorkoutCalendarEntry> {
        let now = Date()
        let calendar = Calendar.bodyGregorian
        let entry = loadEntry(configuration: configuration, usePlaceholderWhenEmpty: false, isPro: BodyProEntitlement.isUnlocked, now: now)
        let built = WorkoutCalendarEntryBuilder.timeline(
            snapshot: entry.snapshot,
            isPro: entry.isPro,
            now: now,
            calendar: calendar
        )

        let entries = built.entries.map { step in
            WorkoutCalendarEntry(
                date: step.date,
                background: entry.background,
                snapshot: step.snapshot,
                isPro: step.isPro,
                workoutColorsRawValue: entry.workoutColorsRawValue
            )
        }
        return Timeline(entries: entries, policy: .after(built.reloadAfter))
    }

    private func loadEntry(
        configuration: BodyWidgetConfigurationIntent,
        usePlaceholderWhenEmpty: Bool,
        isPro: Bool,
        now: Date
    ) -> WorkoutCalendarEntry {
        WorkoutCalendarEntry(
            date: now,
            background: configuration.background ?? .system,
            snapshot: WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty(usePlaceholderWhenEmpty: usePlaceholderWhenEmpty, now: now),
            isPro: isPro,
            workoutColorsRawValue: BodyWorkoutColorStore.rawOverrides
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
            Group {
                if entry.isPro {
                    WorkoutCalendarWidgetView(entry: entry)
                } else {
                    BodyWidgetLockedView()
                }
            }
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
            Group {
                if entry.isPro {
                    WorkoutTypeBreakdownWidgetView(entry: entry)
                } else {
                    BodyWidgetLockedView()
                }
            }
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

    private var palette: BodyWorkoutColorPalette {
        BodyWorkoutColorPalette(rawOverrides: entry.workoutColorsRawValue, isProUnlocked: entry.isPro)
    }

    var body: some View {
        WorkoutCalendarView(
            snapshot: entry.snapshot,
            palette: palette,
            style: .widgetLarge,
            referenceDate: entry.date
        )
        .padding(14)
    }
}

private struct WorkoutTypeBreakdownWidgetView: View {
    let entry: WorkoutCalendarEntry

    @Environment(\.widgetFamily) private var family

    private var palette: BodyWorkoutColorPalette {
        BodyWorkoutColorPalette(rawOverrides: entry.workoutColorsRawValue, isProUnlocked: entry.isPro)
    }

    var body: some View {
        WorkoutTypeBreakdownView(
            snapshot: entry.snapshot,
            palette: palette,
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
