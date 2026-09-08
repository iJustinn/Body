//
//  WatchExerciseWeekChartView.swift
//  BodyWatch
//
//  The Weekly Workout Time complication's chart, drawn onto the Training Load
//  detail page below its value row: a header with the rolling 7-day total,
//  seven bars of daily workout minutes (today rightmost, nothing on a rest
//  day), and weekday letters underneath. Same shape and normalization as
//  `ExerciseWeekComplication` in `BodyWatchWidgetExtension`, which isn't
//  compiled into this target, so the drawing is mirrored here; the bars take
//  the page's tint (Training Load's orange) instead of the complication's blue. Display-only:
//  reads the `workoutMinutes` (or legacy `exerciseMinutes`) metric the iPhone
//  baked into the pushed snapshot.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchExerciseWeekChartView: View {
    /// Daily workout minutes, oldest first and `today` last, already
    /// re-windowed onto `today` (see `WatchMetric.weeklyRewound`).
    let weekly: [Double?]
    /// The day the last slot stands for; anchors the weekday letters.
    let today: Date
    /// Bar color: the page's kind tint.
    let tint: Color

    private static let barSpacing: CGFloat = 3

    private var totalMinutes: Int {
        Int(weekly.compactMap { $0 }.reduce(0, +).rounded())
    }

    private var weekMax: Double {
        weekly.compactMap { $0 }.max() ?? 0
    }

    private var weekdayDates: [Date] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: today)
        return (0..<weekly.count).map { offset in
            calendar.date(byAdding: .day, value: offset - (weekly.count - 1), to: endDay) ?? endDay
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            barsRow
                .frame(maxHeight: .infinity)
            weekdayRow
        }
    }

    private var header: some View {
        Text("\(totalMinutes) MIN THIS WEEK")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var barsRow: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: Self.barSpacing) {
                ForEach(0..<weekly.count, id: \.self) { index in
                    Group {
                        if let value = weekly[index], value > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .foregroundStyle(tint)
                                .frame(height: barHeight(for: value, in: proxy.size.height))
                        } else {
                            // A rest day draws nothing; the clear spacer keeps
                            // the column widths (and the weekday letters below)
                            // aligned.
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
                    .foregroundStyle(.white.opacity(0.7))
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

    /// Weekday letter for `date`, in the user's locale, with the
    /// complication's ASCII fallback.
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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        WatchExerciseWeekChartView(weekly: [32, 0, 58, nil, 45, 12, 27], today: Date(), tint: .orange)
            .frame(height: 86)
            .padding(.horizontal, 8)
    }
}
