//
//  BandBreakdownChart.swift
//  Body
//

import SwiftUI

/// One row of a "days by band" breakdown: how many days fell into a band
/// (a Training Load interval, a Cardio Fitness level, a Readiness status),
/// plus what it takes to draw that row.
protocol BodyBandBreakdownEntry: Identifiable {
    var dayCount: Int { get }
    var totalDayCount: Int { get }
    var fractionOfTotal: Double { get }
    var tintColor: Color { get }
    var symbolName: String { get }
    var title: String { get }
}

/// Shared row layout for the Training Load, Cardio Fitness, and Readiness
/// breakdown charts: one row per band with a day-count bar sized relative to
/// the busiest band, plus a symbol, title and day/percentage caption.
struct BodyMetricBandBreakdownChart<Entry: BodyBandBreakdownEntry>: View {
    let entries: [Entry]

    private var maxDayCount: Int {
        entries.map(\.dayCount).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(entries) { entry in
                distributionRow(entry)
            }
        }
    }

    private func distributionRow(_ entry: Entry) -> some View {
        GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDayCount > 0 ? Double(entry.dayCount) / Double(maxDayCount) : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                dayCountBar(entry)
                    .frame(width: barWidth, height: rowHeight)

                details(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func dayCountBar(_ entry: Entry) -> some View {
        ZStack(alignment: .leading) {
            // Same glass-chip recipe as the Workouts type-breakdown bars: flat
            // translucent fill plus a thin white rim, no gradient or sheen.
            BodyGlassChip(
                color: entry.tintColor,
                cornerRadius: barCornerRadius,
                fillOpacity: entry.dayCount == 0 ? 0.18 : 0.85
            )

            Text(dayCountText(for: entry.dayCount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(entry.dayCount == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.black.opacity(0.82)))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
        }
    }

    private func details(_ entry: Entry) -> some View {
        HStack(spacing: 9) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entry.tintColor)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
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
        String(localized: "chart.dayCount.short", defaultValue: "\(dayCount)d", comment: "Short day-count chip, like 7d")
    }

    private func dayText(for dayCount: Int) -> String {
        dayCount == 1 ? String(localized: "1 day") : String(localized: "\(dayCount) days")
    }

    private func percentageText(for entry: Entry) -> String {
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
