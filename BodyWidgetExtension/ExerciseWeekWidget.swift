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
        ExerciseWeekEntry(date: Date(), points: Self.placeholderPoints, isPro: true)
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
        let calendar = Calendar.bodyGregorian
        let current = WorkoutSnapshotStore.load()
        let previous = WorkoutSnapshotStore.loadPrevious()
        let hasData = (current?.workoutCount ?? 0) > 0 || (previous?.workoutCount ?? 0) > 0

        let points: [HealthWidgetPoint]
        if !hasData && usePlaceholderWhenEmpty {
            points = Self.placeholderPoints
        } else {
            // Dense per-day points for the current + previous month (every
            // in-month day, including zero-duration ones) so re-windowing
            // below always finds a real (non-nil) point for a rest day
            // instead of padding it with nil.
            let allPoints = Self.points(from: current, calendar: calendar)
                + Self.points(from: previous, calendar: calendar)
            // Re-window at load time: the cache is only rewritten when the app
            // runs, so a cache from an earlier day must be re-aligned so the
            // rightmost bar is always today.
            points = HealthWidgetPoint.rewindingWeek(allPoints, to: now, calendar: calendar)
        }

        return ExerciseWeekEntry(
            date: now,
            points: points,
            // Preview/gallery shows the real widget; the live timeline respects the flag.
            isPro: usePlaceholderWhenEmpty || BodyProEntitlement.isUnlocked
        )
    }

    /// One point per day in `snapshot`'s month, minutes of total workout
    /// duration (0 for days with no workouts).
    private static func points(from snapshot: WorkoutMonthSnapshot?, calendar: Calendar) -> [HealthWidgetPoint] {
        guard let snapshot else { return [] }
        return snapshot.days.compactMap { day in
            guard let date = calendar.date(from: DateComponents(year: snapshot.year, month: snapshot.month, day: day.day)) else {
                return nil
            }
            return HealthWidgetPoint(date: date, value: day.totalDuration / 60)
        }
    }

    /// Sample week for the widget gallery preview, built locally (no App
    /// Group read, no HealthWidgetSnapshot dependency).
    private static let placeholderPoints: [HealthWidgetPoint] = {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        let sampleMinutes: [Double] = [30, 45, 0, 60, 25, 50, 40]
        return sampleMinutes.enumerated().map { offset, minutes in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
            return HealthWidgetPoint(date: date, value: minutes)
        }
    }()
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
    private static let calendar = Calendar.bodyGregorian

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
                Text(Self.weekdayLetter(for: point.date))
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

    /// Weekday letter for `date`, in the user's locale. Deliberately not
    /// `Calendar.bodyRotatedVeryShortWeekdaySymbols` (that rotates by
    /// `firstWeekday`, which is wrong for a rolling window that isn't a
    /// calendar week) and not locale-less `Calendar.bodyGregorian` symbols.
    /// Mirrors `WorkoutMonthSnapshot.swift`'s weekday-symbol pattern.
    private static func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.isEmpty ? fallback : symbols
        let index = calendar.component(.weekday, from: date) - 1
        guard source.indices.contains(index) else { return "" }
        return source[index]
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
