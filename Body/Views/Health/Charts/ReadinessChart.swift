//
//  ReadinessChart.swift
//  Body
//

import Charts
import SwiftUI

enum BodyReadinessStatusPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let value, value.isFinite else {
            return nil
        }

        let status = ReadinessStatus.status(for: Int(value.rounded()))
        guard status != .unavailable else {
            return nil
        }

        return BodyHealthMetricTrendHighlightedRange(
            title: status.title,
            lowerBound: status.lowerBound,
            upperBound: status.upperBound,
            color: color(for: status)
        )
    }

    static func color(for status: ReadinessStatus) -> Color {
        guard let rgb = status.watchTintComponents else {
            return Color.secondary
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// The week chart's "current readiness" dot: today's live drained score,
    /// when same-day activity visibly lowered it below today's plotted
    /// (pre-drain) point. nil when nothing drained today, the drop is
    /// display-clamped to zero, or today has no plotted point to hang the dot
    /// under. Reads the same `lineChartCalendarPoints` the chart plots from so
    /// the dot's x/y align with the line exactly.
    static func currentTrendDot(
        readiness: ReadinessSummary?,
        series: HealthTrendSeries,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> (date: Date, value: Double)? {
        guard let readiness,
              readiness.activityDrainMorningScore != nil,
              let score = readiness.score else {
            return nil
        }

        let today = calendar.startOfDay(for: now)
        guard let todayPoint = series
            .lineChartCalendarPoints(to: .recentWeek, calendar: calendar, date: now)
            .last(where: { $0.value?.isFinite == true && calendar.isDate($0.date, inSameDayAs: today) }),
            let todayValue = todayPoint.value,
            Double(score) < todayValue else {
            return nil
        }

        return (todayPoint.date, Double(score))
    }
}

private extension ReadinessStatus {
    var symbolName: String {
        switch self {
        case .prime:
            return "sparkles"
        case .high:
            return "checkmark.circle.fill"
        case .moderate:
            return "circle.fill"
        case .low:
            return "exclamationmark.circle.fill"
        case .poor:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "questionmark.circle.fill"
        }
    }
}

extension ReadinessStatusBreakdownEntry: BodyBandBreakdownEntry {
    var tintColor: Color {
        BodyReadinessStatusPresentation.color(for: status)
    }

    var symbolName: String {
        status.symbolName
    }

    var title: String {
        status.title
    }
}

struct BodyReadinessStatusBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    var calendar: Calendar = .bodyGregorian
    let date: Date
    private let entries: [ReadinessStatusBreakdownEntry]

    init(series: HealthTrendSeries, selectedRange: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date) {
        self.series = series
        self.selectedRange = selectedRange
        self.calendar = calendar
        self.date = date
        self.entries = ReadinessStatusBreakdown.entries(
            for: series,
            range: selectedRange,
            calendar: calendar,
            date: date
        )
    }

    private var totalDayCount: Int {
        entries.first?.totalDayCount ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days by Status")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if totalDayCount == 0 {
                emptyState
            } else {
                BodyMetricBandBreakdownChart(entries: entries)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.45))

            Text("No Readiness yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

