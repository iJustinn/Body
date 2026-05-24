//
//  BodyHomeTrendCard.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHomeSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct BodyHomeTrendsSection: View {
    let cards: [BodyHomeTrendCard.Model]
    let canToggleAll: Bool
    let showsAllTrends: Bool
    let toggleAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                ForEach(cards) { card in
                    NavigationLink(value: card.presentation.kind) {
                        BodyHomeTrendCard(model: card)
                    }
                    .buttonStyle(.plain)
                }
            }

            if canToggleAll {
                Button(action: toggleAll) {
                    Text(showsAllTrends ? "Show Fewer Trends" : "Show All Trends")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BodyHomeTrendCard: View {
    struct Model: Identifiable {
        let presentation: BodyHomeTrendCardPresentation
        let symbolName: String
        let symbolColor: Color

        var id: String {
            presentation.id
        }
    }

    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Text(model.presentation.messageText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            VStack(spacing: 8) {
                BodyHomeTrendComparisonChart(
                    presentation: model.presentation,
                    color: model.symbolColor
                )
                .frame(height: 128)

                averageLabels
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(cornerRadius: 28)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.symbolColor)
                .accessibilityHidden(true)

            Text(model.presentation.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(model.symbolColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.secondary.opacity(0.55))
                .accessibilityHidden(true)
        }
    }

    private var averageLabels: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.presentation.baselineAverageText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(model.presentation.baselinePeriodText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(model.presentation.recentAverageText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(model.symbolColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(model.presentation.recentPeriodText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(model.symbolColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }
}

struct BodyHomeTrendComparisonChart: View {
    let presentation: BodyHomeTrendCardPresentation
    let color: Color

    private struct PlotEntry: Identifiable {
        let point: HealthTrendCalendarPoint
        let position: CGPoint
        let index: Int

        var id: Date {
            point.date
        }

        var hasValue: Bool {
            point.value?.isFinite == true
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let entries = plotEntries(in: proxy.size)
            ZStack {
                switch presentation.chartStyle {
                case .line:
                    linePlot(entries: entries)
                case .bar:
                    barPlot(entries: entries, size: proxy.size)
                }

                averageLine(
                    value: presentation.baselineAverage,
                    in: proxy.size,
                    color: Color.secondary.opacity(0.64),
                    xRange: presentation.averageLineSegments(in: proxy.size.width).baseline
                )

                averageLine(
                    value: presentation.recentAverage,
                    in: proxy.size,
                    color: color,
                    xRange: presentation.averageLineSegments(in: proxy.size.width).recent
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func linePlot(entries: [PlotEntry]) -> some View {
        let valueEntries = entries.filter(\.hasValue)

        return ZStack {
            if valueEntries.count > 1 {
                Path { path in
                    path.move(to: valueEntries[0].position)
                    for entry in valueEntries.dropFirst() {
                        path.addLine(to: entry.position)
                    }
                }
                .stroke(
                    Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }

            ForEach(valueEntries) { entry in
                Circle()
                    .stroke(Color.secondary.opacity(0.34), lineWidth: 3)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                    .frame(width: 8, height: 8)
                    .position(entry.position)
            }
        }
    }

    private func barPlot(entries: [PlotEntry], size: CGSize) -> some View {
        let barWidth = max((size.width - CGFloat(max(entries.count - 1, 0)) * 5) / CGFloat(max(entries.count, 1)), 3)

        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(entries) { entry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor(for: entry))
                    .frame(width: barWidth, height: barHeight(for: entry.point.value, in: size.height))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func averageLine(value: Double, in size: CGSize, color: Color, xRange: ClosedRange<CGFloat>) -> some View {
        let y = yPosition(for: value, in: size)

        return Path { path in
            path.move(to: CGPoint(x: xRange.lowerBound, y: y))
            path.addLine(to: CGPoint(x: xRange.upperBound, y: y))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: BodyHomeTrendCardPresentation.averageLineStrokeWidth,
                lineCap: .round
            )
        )
    }

    private func plotEntries(in size: CGSize) -> [PlotEntry] {
        let points = presentation.displayCalendarPoints
        let denominator = max(CGFloat(points.count - 1), 1)
        return points.enumerated().map { index, point in
            let x = size.width * CGFloat(index) / denominator
            let y = yPosition(for: point.value ?? chartMinimum, in: size)
            return PlotEntry(point: point, position: CGPoint(x: x, y: y), index: index)
        }
    }

    private func barColor(for entry: PlotEntry) -> Color {
        guard entry.hasValue else {
            return Color.secondary.opacity(0.10)
        }

        return entry.index >= presentation.displayRecentStartIndex
            ? color.opacity(0.42)
            : Color.secondary.opacity(0.28)
    }

    private func barHeight(for value: Double?, in height: CGFloat) -> CGFloat {
        guard let value, value.isFinite else {
            return max(height * 0.05, 4)
        }

        let range = max(chartMaximum - chartMinimum, 1)
        let normalized = min(max((value - chartMinimum) / range, 0), 1)
        return max(height * CGFloat(normalized), 4)
    }

    private func yPosition(for value: Double, in size: CGSize) -> CGFloat {
        let range = max(chartMaximum - chartMinimum, 1)
        let normalized = min(max((value - chartMinimum) / range, 0), 1)
        return size.height - (size.height * CGFloat(normalized))
    }

    private var chartValues: [Double] {
        presentation.displayCalendarPoints.compactMap(\.value).filter(\.isFinite)
            + [presentation.baselineAverage, presentation.recentAverage]
    }

    private var chartMinimum: Double {
        let minimum = chartValues.min() ?? 0
        guard presentation.chartStyle == .line else {
            return 0
        }

        let maximum = chartValues.max() ?? minimum
        let padding = max((maximum - minimum) * 0.16, 1)
        return max(0, minimum - padding)
    }

    private var chartMaximum: Double {
        let maximum = chartValues.max() ?? 1
        let minimum = chartValues.min() ?? maximum
        let padding = max((maximum - minimum) * 0.16, 1)
        return maximum + padding
    }
}
