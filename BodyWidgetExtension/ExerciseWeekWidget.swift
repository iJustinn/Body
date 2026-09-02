//
//  ExerciseWeekWidget.swift
//  BodyWidgetExtension
//
//  iPhone lock screen widget (accessoryRectangular): a header total plus
//  seven bars for the rolling last 7 days of total workout time (summed
//  HKWorkout durations), today rightmost. No configuration, so this is a
//  plain StaticConfiguration (unlike the other widgets, which reuse
//  BodyWidgetConfigurationIntent for a background picker). Pro-gated,
//  matching the other Body widgets.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ExerciseWeekEntry: TimelineEntry {
    let date: Date
    let points: [HealthWidgetPoint]
    let isPro: Bool
}

struct ExerciseWeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExerciseWeekEntry {
        ExerciseWeekEntry(date: Date(), points: ExerciseWeekEntryBuilder.placeholderPoints(now: Date()), isPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ExerciseWeekEntry) -> Void) {
        completion(loadEntry(usePlaceholderWhenEmpty: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExerciseWeekEntry>) -> Void) {
        let entry = loadEntry(usePlaceholderWhenEmpty: false)
        let nextRefresh = Calendar.bodyGregorian.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry(usePlaceholderWhenEmpty: Bool) -> ExerciseWeekEntry {
        let now = Date()
        let points = ExerciseWeekEntryBuilder.points(
            current: WorkoutSnapshotStore.load(),
            previous: WorkoutSnapshotStore.loadPrevious(),
            usePlaceholderWhenEmpty: usePlaceholderWhenEmpty,
            now: now,
            calendar: .bodyGregorian
        )

        return ExerciseWeekEntry(
            date: now,
            points: points,
            // Preview/gallery shows the real widget; the live timeline respects the flag.
            isPro: usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked
        )
    }
}

// MARK: - Widget

struct BodyExerciseWeekWidget: Widget {
    let kind = "BodyExerciseWeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExerciseWeekProvider()) { entry in
            Group {
                if entry.isPro {
                    ExerciseWeekWidgetView(points: entry.points)
                } else {
                    ExerciseWeekLockedView()
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .supportedFamilies([.accessoryRectangular])
        .configurationDisplayName("Weekly Workout Time")
        .description("This week's daily workout minutes.")
        .contentMarginsDisabled()
    }
}

// MARK: - Unlocked view

private struct ExerciseWeekWidgetView: View {
    let points: [HealthWidgetPoint]

    private static let barSpacing: CGFloat = 3

    private var totalMinutes: Int {
        Int(points.compactMap(\.value).reduce(0, +).rounded())
    }

    private var weekMax: Double {
        points.compactMap(\.value).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            barsRow
                .frame(maxHeight: .infinity)
            weekdayRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        Text("\(totalMinutes) MIN THIS WEEK")
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var barsRow: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(points) { point in
                    Group {
                        if let value = point.value, value > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .foregroundStyle(.primary)
                                .frame(height: barHeight(for: value, in: proxy.size.height))
                        } else {
                            // A day with no exercise draws nothing; the clear
                            // spacer keeps the column widths (and the weekday
                            // labels below) aligned.
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(points) { point in
                Text(ExerciseWeekEntryBuilder.weekdayLetter(for: point.date, calendar: .bodyGregorian))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .textCase(.uppercase)
    }

    private func barHeight(for value: Double, in height: CGFloat) -> CGFloat {
        guard weekMax > 0 else { return 3 }
        let normalized = value / weekMax
        return max(height * CGFloat(normalized), 3)
    }
}

// MARK: - Locked view

/// Compact locked state sized for the accessory container (~72pt tall), too
/// small for the shared `BodyWidgetLockedView` (~87pt). No yellow: lock
/// screen widgets render in vibrant mode, which flattens tinted colors.
private struct ExerciseWeekLockedView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(String(localized: "Body Pro", table: "BodyShared"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
