//
//  ExerciseWeekComplication.swift
//  BodyWatchWidgetExtension
//
//  Watch complication (accessoryRectangular only): a header total plus seven
//  bars for the last 7 days of Apple Exercise Minutes, today rightmost. Free
//  (not Pro-gated), unlike the matching iPhone lock screen widget. Reuses the
//  existing `WatchMetricProvider`/`WatchMetricEntry`, which already carries
//  the whole snapshot.
//

import SwiftUI
import WidgetKit

struct ExerciseWeekComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchExerciseWeek", provider: WatchMetricProvider()) { entry in
            ExerciseWeekComplicationView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Exercise Minutes"))
        .description(String(localized: "This week's daily exercise minutes."))
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct ExerciseWeekComplicationView: View {
    let entry: WatchMetricEntry

    private static let barSpacing: CGFloat = 3
    private static let barColor = Color(red: 1.0/255.0, green: 47.0/255.0, blue: 167.0/255.0)

    private var weekly: [Double?] {
        // Re-windowed to the entry's day (see `weeklyRewound`): the cache is
        // only rewritten when the phone pushes (on-watch compute preserves
        // this metric), so a snapshot from an earlier day must not keep
        // yesterday as the rightmost bar.
        let metric = entry.snapshot.metric(forKind: WatchMetricKindKey.exerciseMinutes)
        return metric?.weeklyRewound(from: entry.snapshot.generatedAt, to: entry.date)
            ?? Array(repeating: nil, count: 7)
    }

    private var totalMinutes: Int {
        Int(weekly.compactMap { $0 }.reduce(0, +).rounded())
    }

    private var weekMax: Double {
        weekly.compactMap { $0 }.max() ?? 0
    }

    /// Day for each positional `weekly` slot (oldest…today). Anchored to
    /// `entry.date` — `weekly` above is re-windowed to that same day, so the
    /// labels stay honest even when the cached snapshot predates today. (Not
    /// `lastRefreshDate`: that is the last *vitals* refresh and can be older
    /// than the snapshot's build time, WatchMetricsSnapshotBuilder.swift:145.)
    private var weekdayDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        return (0..<7).map { offset in
            calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            barsRow
                .frame(maxHeight: .infinity)
            weekdayRow
        }
        .containerBackground(.clear, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)

            Text("\(totalMinutes) MIN THIS WEEK")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var barsRow: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(0..<weekly.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .foregroundStyle(Self.barColor)
                        .opacity((weekly[index] ?? 0) > 0 ? 1 : 0.3)
                        .frame(height: barHeight(for: weekly[index], in: proxy.size.height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var weekdayRow: some View {
        let dates = weekdayDates
        return HStack(spacing: Self.barSpacing) {
            ForEach(0..<weekly.count, id: \.self) { index in
                Text(Self.weekdayLetter(for: dates[index]))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .textCase(.uppercase)
    }

    private func barHeight(for value: Double?, in height: CGFloat) -> CGFloat {
        guard let value, value > 0, weekMax > 0 else { return 3 }
        let normalized = value / weekMax
        return max(height * CGFloat(normalized), 3)
    }

    /// Weekday letter for `date`, in the user's locale. `BodyMetricsKit` isn't
    /// compiled into this target, so this mirrors (rather than reuses)
    /// `WorkoutMonthSnapshot.swift`'s `veryShortStandaloneWeekdaySymbols`
    /// pattern with the same ASCII fallback.
    private static func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.count == 7 ? symbols : fallback
        let index = Calendar.current.component(.weekday, from: date) - 1
        guard source.indices.contains(index) else { return "" }
        return source[index]
    }
}
