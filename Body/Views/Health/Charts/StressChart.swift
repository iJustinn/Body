//
//  StressChart.swift
//  Body
//

import Charts
import SwiftUI

/// The Stress counterpart of `BodyReadinessStatusPresentation`: band colors and
/// the trend chart's highlighted range for whichever band today's score falls in.
enum BodyStressBandPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let value, value.isFinite else {
            return nil
        }

        let band = StressBand.band(for: value)
        return BodyHealthMetricTrendHighlightedRange(
            title: band.title,
            lowerBound: band.lowerBound,
            upperBound: band.upperBound,
            color: color(for: band)
        )
    }

    /// Cool-to-warm progression distinct from the readiness/training-load band
    /// palettes: calm blue at Rest through red at High.
    static func color(for band: StressBand) -> Color {
        switch band {
        case .rest:
            return Color(red: 0.20, green: 0.70, blue: 0.95)
        case .low:
            return Color(red: 0.20, green: 0.80, blue: 0.45)
        case .medium:
            return Color(red: 1.00, green: 0.72, blue: 0.15)
        case .high:
            return Color(red: 1.00, green: 0.30, blue: 0.20)
        }
    }
}

/// Intraday Stress chart: one bar per 15-minute window, colored by band.
/// `.unscored` windows are omitted entirely (a real gap in the day, not a
/// zero); `.activity` windows draw as a short muted marker at the chart floor
/// since movement masks the window rather than scoring it.
struct BodyStressIntradayChart: View {
    let windows: [StressWindow]

    private static let activityMarkerHeight: Double = 6

    var body: some View {
        Chart {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                if let score = window.score {
                    BarMark(
                        xStart: .value("Start", window.interval.start),
                        xEnd: .value("End", window.interval.end),
                        y: .value("Score", score)
                    )
                    .foregroundStyle(BodyStressBandPresentation.color(for: StressBand.band(for: score)))
                    .cornerRadius(2)
                } else if window.state == .activity {
                    BarMark(
                        xStart: .value("Start", window.interval.start),
                        xEnd: .value("End", window.interval.end),
                        y: .value("Score", Self.activityMarkerHeight)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.28))
                    .cornerRadius(1)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartLegend(.hidden)
        .accessibilityHidden(windows.isEmpty)
    }
}

/// Time-in-band breakdown for one day's Stress score, modeled visually on
/// `BodyReadinessStatusBreakdownChart` but sourced from a single
/// `StressDaySummary` instead of aggregating status days across a range.
struct BodyStressBandBreakdownChart: View {
    let summary: StressDaySummary?

    private var totalMinutes: Int {
        summary?.totalScoredMinutes ?? 0
    }

    private var maxMinutes: Int {
        guard let summary else { return 0 }
        return StressBand.displayOrder.map(summary.minutes(in:)).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time by Band")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if totalMinutes == 0 {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(StressBand.displayOrder, id: \.self) { band in
                        bandRow(band)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.45))

            Text("No Stress yet today")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func bandRow(_ band: StressBand) -> some View {
        let minutes = summary?.minutes(in: band) ?? 0

        return GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxMinutes > 0 ? Double(minutes) / Double(maxMinutes) : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                minutesBar(band: band, minutes: minutes)
                    .frame(width: barWidth, height: rowHeight)

                bandDetails(band: band, minutes: minutes)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func minutesBar(band: StressBand, minutes: Int) -> some View {
        ZStack(alignment: .leading) {
            BodyGlassChip(
                color: BodyStressBandPresentation.color(for: band),
                cornerRadius: barCornerRadius,
                fillOpacity: minutes == 0 ? 0.18 : 0.85
            )

            Text(minutesText(for: minutes))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(minutes == 0 ? 0.42 : 0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
        }
    }

    private func bandDetails(band: StressBand, minutes: Int) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(BodyStressBandPresentation.color(for: band))
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(band.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(percentageText(for: minutes))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
    }

    private func minutesText(for minutes: Int) -> String {
        "\(minutes)m"
    }

    private func percentageText(for minutes: Int) -> String {
        guard totalMinutes > 0 else { return "0%" }

        let percentage = Int((Double(minutes) / Double(totalMinutes) * 100).rounded())
        return "\(percentage)%"
    }

    private func maximumBarWidth(for availableWidth: CGFloat) -> CGFloat {
        max(92, availableWidth - detailReserveWidth(for: availableWidth))
    }

    private func detailReserveWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 130), 172)
    }

    private var minimumBarWidth: CGFloat { 92 }
    private var rowHeight: CGFloat { 50 }
    private var rowSpacing: CGFloat { 12 }
    private var rowHorizontalSpacing: CGFloat { 12 }
    private var barCornerRadius: CGFloat { 16 }
}
