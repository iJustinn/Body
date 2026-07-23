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

struct BodyReadinessStatusBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    var calendar: Calendar = .bodyGregorian
    var date: Date = Date()

    private var entries: [ReadinessStatusBreakdownEntry] {
        ReadinessStatusBreakdown.entries(
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
            Text("Days by Status")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if totalDayCount == 0 {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(entries) { entry in
                        statusDistributionRow(entry)
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

            Text("No Readiness yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func statusDistributionRow(_ entry: ReadinessStatusBreakdownEntry) -> some View {
        GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDayCount > 0 ? Double(entry.dayCount) / Double(maxDayCount) : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                dayCountBar(entry)
                    .frame(width: barWidth, height: rowHeight)

                statusDetails(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func dayCountBar(_ entry: ReadinessStatusBreakdownEntry) -> some View {
        ZStack(alignment: .leading) {
            // Same glass-chip recipe as the Workouts type-breakdown bars: flat
            // translucent fill plus a thin white rim, no gradient or sheen.
            BodyGlassChip(
                color: BodyReadinessStatusPresentation.color(for: entry.status),
                cornerRadius: barCornerRadius,
                fillOpacity: entry.dayCount == 0 ? 0.18 : 0.85
            )

            Text(dayCountText(for: entry.dayCount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(entry.dayCount == 0 ? 0.42 : 0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
        }
    }

    private func statusDetails(_ entry: ReadinessStatusBreakdownEntry) -> some View {
        HStack(spacing: 9) {
            Image(systemName: entry.status.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BodyReadinessStatusPresentation.color(for: entry.status))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status.title)
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

    private func percentageText(for entry: ReadinessStatusBreakdownEntry) -> String {
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

