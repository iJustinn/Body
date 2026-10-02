//
//  WatchWeekBarsView.swift
//  BodyWatchShared
//
//  Seven bars of daily totals (today rightmost, nothing on an empty day) with
//  weekday letters underneath and an optional header line above: the drawing
//  of `ExerciseWeekComplication`, parameterized by tint, header and label
//  color. The Steps, Active Energy and Resting Energy detail pages draw it in
//  place of the week line, and their rectangular complications draw it with
//  the week's total as the header. No `containerBackground` here; the widget
//  adds its own.
//
//  Shared by the iOS `Body` target, the `BodyWatch` target, and the watch
//  widget extension, so it stays SwiftUI only: no WidgetKit, no
//  BodyMetricsKit, no watch-only API, and no `Color(WatchMetricColor)` (that
//  initializer lives in `WatchMetricRingView.swift`, which the iOS target
//  doesn't compile). Callers pass a ready `Color`.
//

import SwiftUI

struct WatchWeekBarsView: View {
    /// Daily totals, oldest first and `today` last, already re-windowed onto
    /// `today` (see `WatchMetric.weeklyRewound`).
    let weekly: [Double?]
    /// The day the last slot stands for; anchors the weekday letters.
    let today: Date
    /// Bar color: the metric's kind tint.
    let tint: Color
    /// Line above the bars (already localized), or nil for no header.
    var header: String? = nil
    /// Weekday letter color.
    var labelColor: Color = .secondary

    private static let barSpacing: CGFloat = 3

    private var weekMax: Double {
        weekly.compactMap { $0 }.max() ?? 0
    }

    /// Day for each positional `weekly` slot (oldest…today), anchored to
    /// `today`, which `weekly` is already re-windowed onto.
    private var weekdayDates: [Date] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: today)
        return (0..<weekly.count).map { offset in
            calendar.date(byAdding: .day, value: offset - (weekly.count - 1), to: endDay) ?? endDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let header {
                Text(header)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            barsRow
                .frame(maxHeight: .infinity)
            weekdayRow
        }
    }

    private var barsRow: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(0..<weekly.count, id: \.self) { index in
                    Group {
                        if let value = weekly[index], value > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .foregroundStyle(tint)
                                .frame(height: Self.barHeight(for: value, weekMax: weekMax, in: proxy.size.height))
                        } else {
                            // An empty day draws nothing; the clear spacer
                            // keeps the column widths (and the weekday letters
                            // below) aligned.
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
        let dates = weekdayDates
        return HStack(spacing: Self.barSpacing) {
            ForEach(0..<weekly.count, id: \.self) { index in
                Text(Self.weekdayLetter(for: dates[index]))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity)
            }
        }
        .textCase(.uppercase)
    }

    /// A bar's height in a row `height` tall: scaled to the week's largest
    /// day, never under 3 pt so a small day still shows.
    static func barHeight(for value: Double, weekMax: Double, in height: CGFloat) -> CGFloat {
        guard weekMax > 0 else { return 3 }
        let normalized = value / weekMax
        return max(height * CGFloat(normalized), 3)
    }

    /// Weekday letter for `date`, in the user's locale. `BodyMetricsKit` isn't
    /// compiled into the widget extension, so this mirrors (rather than
    /// reuses) `WorkoutMonthSnapshot.swift`'s `veryShortStandaloneWeekdaySymbols`
    /// pattern with the same ASCII fallback.
    static func weekdayLetter(for date: Date) -> String {
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
