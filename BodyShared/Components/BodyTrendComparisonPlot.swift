//
//  BodyTrendComparisonPlot.swift
//  BodyShared
//
//  The Trends card's comparison chart, drawn from plain values so the Home card
//  (`BodyHomeTrendComparisonChart`) and the large Trends widget share one
//  implementation: the window's days as gray dots on a gray line (or bars, the
//  recent ones tinted), a gray line at the baseline average under the earlier days
//  and a tinted line at the recent average under the later ones.
//

import SwiftUI

struct BodyTrendComparisonPlot: View {
    static let averageLineStrokeWidth: CGFloat = 4

    let values: [Double?]
    /// The last index of the baseline segment; the recent segment starts after it.
    let baselineEndIndex: Int
    let baselineAverage: Double
    let recentAverage: Double
    let chartStyle: HealthMetricChartStyle
    let color: Color
    /// Fills each dot's center. `nil` punches the line out under each dot instead,
    /// so a widget's dot shows whichever background the user picked (the medium
    /// trend widget's technique, `HealthWidgetTrendPlot`).
    var dotFill: Color?

    private struct PlotEntry: Identifiable {
        let value: Double?
        let position: CGPoint
        let index: Int

        var id: Int {
            index
        }

        var hasValue: Bool {
            value?.isFinite == true
        }
    }

    private var recentStartIndex: Int {
        Self.recentStartIndex(baselineEndIndex: baselineEndIndex, pointCount: values.count)
    }

    var body: some View {
        // The domain and the average-line segments are derived once per pass and
        // handed down: they used to be recomputed inside `barHeight`, `yPosition`
        // and `averageLine`, so a card with 30 bars walked the point list dozens
        // of times per render.
        let domain = Self.domain(
            values: values.compactMap { $0 } + [baselineAverage, recentAverage],
            chartStyle: chartStyle
        )

        return GeometryReader { proxy in
            let entries = plotEntries(in: proxy.size, domain: domain)
            let segments = Self.averageLineSegments(
                pointCount: values.count,
                baselineEndIndex: baselineEndIndex,
                width: proxy.size.width
            )
            ZStack {
                switch chartStyle {
                case .line:
                    linePlot(entries: entries)
                case .bar:
                    barPlot(entries: entries, size: proxy.size, domain: domain)
                }

                averageLine(
                    value: baselineAverage,
                    in: proxy.size,
                    domain: domain,
                    color: Color.secondary.opacity(0.64),
                    xRange: segments.baseline
                )

                averageLine(
                    value: recentAverage,
                    in: proxy.size,
                    domain: domain,
                    color: color,
                    xRange: segments.recent
                )
                // The recent average takes the tint in the Home Screen's Tinted appearance.
                .widgetAccentable()
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

            if dotFill == nil {
                ForEach(valueEntries) { entry in
                    Circle()
                        .frame(width: 8, height: 8)
                        .position(entry.position)
                        .blendMode(.destinationOut)
                }
            }

            ForEach(valueEntries) { entry in
                Circle()
                    .stroke(Color.secondary.opacity(0.34), lineWidth: 3)
                    .background(Circle().fill(dotFill ?? .clear))
                    .frame(width: 8, height: 8)
                    .position(entry.position)
            }
        }
        .compositingGroup()
    }

    private func barPlot(entries: [PlotEntry], size: CGSize, domain: Domain) -> some View {
        let layout = BodyHomeTrendBarLayout.fitting(barCount: entries.count, availableWidth: size.width)

        return HStack(alignment: .bottom, spacing: layout.spacing) {
            ForEach(entries) { entry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor(for: entry))
                    .frame(
                        width: layout.barWidth,
                        height: Self.barHeight(for: entry.value, in: size.height, domain: domain)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func averageLine(
        value: Double,
        in size: CGSize,
        domain: Domain,
        color: Color,
        xRange: ClosedRange<CGFloat>
    ) -> some View {
        let y = Self.yPosition(for: value, in: size, domain: domain)

        return Path { path in
            path.move(to: CGPoint(x: xRange.lowerBound, y: y))
            path.addLine(to: CGPoint(x: xRange.upperBound, y: y))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: Self.averageLineStrokeWidth,
                lineCap: .round
            )
        )
    }

    private func plotEntries(in size: CGSize, domain: Domain) -> [PlotEntry] {
        let denominator = max(CGFloat(values.count - 1), 1)
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / denominator
            let y = Self.yPosition(for: value ?? domain.minimum, in: size, domain: domain)
            return PlotEntry(value: value, position: CGPoint(x: x, y: y), index: index)
        }
    }

    private func barColor(for entry: PlotEntry) -> Color {
        guard entry.hasValue else {
            return Color.secondary.opacity(0.10)
        }

        return entry.index >= recentStartIndex
            ? color.opacity(0.42)
            : Color.secondary.opacity(0.28)
    }

    static func recentStartIndex(baselineEndIndex: Int, pointCount: Int) -> Int {
        min(baselineEndIndex + 1, max(pointCount - 1, 0))
    }

    /// Where the two average lines run: the baseline line from the first point to
    /// the last baseline point, the recent line from the first recent point to the
    /// last, each reaching half a bucket toward the other so they meet near the split.
    static func averageLineSegments(
        pointCount: Int,
        baselineEndIndex: Int,
        width: CGFloat
    ) -> (baseline: ClosedRange<CGFloat>, recent: ClosedRange<CGFloat>) {
        let lastPointIndex = max(pointCount - 1, 0)
        let clampedBaselineEndIndex = min(max(baselineEndIndex, 0), lastPointIndex)
        let recentStartIndex = min(max(baselineEndIndex + 1, 0), lastPointIndex)
        let denominator = max(CGFloat(lastPointIndex), 1)
        let halfBucketWidth = width / denominator / 2
        let segmentExtension = max(halfBucketWidth - averageLineStrokeWidth / 2, 0)

        func xPosition(for index: Int) -> CGFloat {
            width * CGFloat(index) / denominator
        }

        return (
            baseline: xPosition(for: 0)...min(width, xPosition(for: clampedBaselineEndIndex) + segmentExtension),
            recent: max(0, xPosition(for: recentStartIndex) - segmentExtension)...xPosition(for: lastPointIndex)
        )
    }

    /// The chart's value domain, derived once per render from the visible points
    /// plus the two average lines. Static and input-only so it can be tested
    /// directly against degenerate series (all equal, a single point, none).
    struct Domain: Equatable {
        let minimum: Double
        let maximum: Double
    }

    static func domain(values: [Double], chartStyle: HealthMetricChartStyle) -> Domain {
        let finite = values.filter(\.isFinite)
        let lowest = finite.min() ?? 0
        let highest = finite.max() ?? (finite.isEmpty ? 1 : lowest)
        let padding = max((highest - lowest) * 0.16, 1)
        // Bars are read against zero; a line chart pads both ends so a flat series
        // still draws inside the plot rather than along its edge.
        let minimum = chartStyle == .line ? max(0, lowest - padding) : 0
        return Domain(minimum: minimum, maximum: highest + padding)
    }

    static func barHeight(for value: Double?, in height: CGFloat, domain: Domain) -> CGFloat {
        guard let value, value.isFinite else {
            return max(height * 0.05, 4)
        }

        return max(height * CGFloat(normalized(value, in: domain)), 4)
    }

    static func yPosition(for value: Double, in size: CGSize, domain: Domain) -> CGFloat {
        size.height - (size.height * CGFloat(normalized(value, in: domain)))
    }

    private static func normalized(_ value: Double, in domain: Domain) -> Double {
        let range = max(domain.maximum - domain.minimum, 1)
        return min(max((value - domain.minimum) / range, 0), 1)
    }
}

struct BodyHomeTrendBarLayout: Equatable {
    static let minimumBarWidth: CGFloat = 3
    static let preferredSpacing: CGFloat = 5

    let barWidth: CGFloat
    let spacing: CGFloat

    static func fitting(barCount: Int, availableWidth: CGFloat) -> BodyHomeTrendBarLayout {
        guard barCount > 0, availableWidth.isFinite, availableWidth > 0 else {
            return BodyHomeTrendBarLayout(barWidth: 0, spacing: 0)
        }

        guard barCount > 1 else {
            return BodyHomeTrendBarLayout(barWidth: availableWidth, spacing: 0)
        }

        let count = CGFloat(barCount)
        let gapCount = CGFloat(barCount - 1)
        let minimumBarsWidth = minimumBarWidth * count
        guard minimumBarsWidth < availableWidth else {
            return BodyHomeTrendBarLayout(barWidth: availableWidth / count, spacing: 0)
        }

        let spacing = min(preferredSpacing, (availableWidth - minimumBarsWidth) / gapCount)
        let barWidth = (availableWidth - spacing * gapCount) / count
        return BodyHomeTrendBarLayout(barWidth: barWidth, spacing: spacing)
    }
}
