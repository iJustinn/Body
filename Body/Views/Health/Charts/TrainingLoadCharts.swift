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

struct BodyTrainingLoadIntervalBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    var calendar: Calendar = .bodyGregorian
    var date: Date = Date()

    private var entries: [TrainingLoadIntervalBreakdownEntry] {
        TrainingLoadIntervalBreakdown.entries(
            for: series,
            range: selectedRange,
            calendar: calendar,
            date: date
        )
    }

    private var totalDayCount: Int {
        entries.first?.totalDayCount ?? 0
    }

    private var maxDayCount: Int {
        entries.map(\.dayCount).max() ?? 0
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
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(entries) { entry in
                        intervalDistributionRow(entry)
                    }
                }
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

    private func intervalDistributionRow(_ entry: TrainingLoadIntervalBreakdownEntry) -> some View {
        GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDayCount > 0 ? Double(entry.dayCount) / Double(maxDayCount) : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                dayCountBar(entry)
                    .frame(width: barWidth, height: rowHeight)

                intervalDetails(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func dayCountBar(_ entry: TrainingLoadIntervalBreakdownEntry) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                .fill(
                    BodyTrainingLoadIntervalPresentation
                        .color(for: entry.interval)
                        .opacity(entry.dayCount == 0 ? 0.18 : 1)
                )

            Text(dayCountText(for: entry.dayCount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(entry.dayCount == 0 ? 0.42 : 0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
        }
    }

    private func intervalDetails(_ entry: TrainingLoadIntervalBreakdownEntry) -> some View {
        HStack(spacing: 9) {
            Image(systemName: entry.interval.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BodyTrainingLoadIntervalPresentation.color(for: entry.interval))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.interval.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("\(dayText(for: entry.dayCount)) • \(percentageText(for: entry))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
    }

    private func dayCountText(for dayCount: Int) -> String {
        "\(dayCount)d"
    }

    private func dayText(for dayCount: Int) -> String {
        dayCount == 1 ? String(localized: "1 day") : String(localized: "\(dayCount) days")
    }

    private func percentageText(for entry: TrainingLoadIntervalBreakdownEntry) -> String {
        guard entry.totalDayCount > 0 else { return "0%" }

        let percentage = Int((entry.fractionOfTotal * 100).rounded())
        return "\(percentage)%"
    }

    private func maximumBarWidth(for availableWidth: CGFloat) -> CGFloat {
        max(92, availableWidth - detailReserveWidth(for: availableWidth))
    }

    private func detailReserveWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 130), 172)
    }

    private var minimumBarWidth: CGFloat {
        92
    }

    private var rowHeight: CGFloat {
        50
    }

    private var rowSpacing: CGFloat {
        12
    }

    private var rowHorizontalSpacing: CGFloat {
        12
    }

    private var barCornerRadius: CGFloat {
        16
    }
}

