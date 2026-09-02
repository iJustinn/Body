//
//  TrainingLoadCharts.swift
//  Body
//

import Charts
import SwiftUI

enum BodyTrainingLoadIntervalPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let interval = TrainingLoadInterval.interval(for: value) else {
            return nil
        }

        return BodyHealthMetricTrendHighlightedRange(
            title: interval.title,
            lowerBound: interval.lowerBound,
            upperBound: interval.upperBound,
            color: color(for: interval)
        )
    }

    static func color(for interval: TrainingLoadInterval) -> Color {
        switch interval {
        case .stopTraining:
            return Color(red: 0.00, green: 0.88, blue: 0.82)
        case .optimal:
            return Color(red: 0.10, green: 0.82, blue: 0.20)
        case .mediumInjuryRisk:
            return Color(red: 1.00, green: 0.46, blue: 0.10)
        case .highInjuryRisk:
            return Color(red: 1.00, green: 0.17, blue: 0.16)
        }
    }
}

private extension TrainingLoadInterval {
    var symbolName: String {
        switch self {
        case .stopTraining:
            return "pause.circle.fill"
        case .optimal:
            return "checkmark.circle.fill"
        case .mediumInjuryRisk:
            return "exclamationmark.circle.fill"
        case .highInjuryRisk:
            return "exclamationmark.triangle.fill"
        }
    }
}

extension TrainingLoadIntervalBreakdownEntry: BodyBandBreakdownEntry {
    var tintColor: Color {
        BodyTrainingLoadIntervalPresentation.color(for: interval)
    }

    var symbolName: String {
        interval.symbolName
    }

    var title: String {
        interval.title
    }
}

struct BodyTrainingLoadIntervalBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    var calendar: Calendar = .bodyGregorian
    let date: Date
    private let entries: [TrainingLoadIntervalBreakdownEntry]

    init(series: HealthTrendSeries, selectedRange: BodyHealthTrendRange, calendar: Calendar = .bodyGregorian, date: Date) {
        self.series = series
        self.selectedRange = selectedRange
        self.calendar = calendar
        self.date = date
        self.entries = TrainingLoadIntervalBreakdown.entries(
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
            Text("Days by Interval")
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

            Text("No Training Load yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

