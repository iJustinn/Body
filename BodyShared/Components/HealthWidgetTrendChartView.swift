//
//  HealthWidgetTrendChartView.swift
//  Body
//
//  Medium-widget content that charts a single metric's weekly/monthly trend
//  for the primary source, with a dashed reference line at the range average
//  and the average value shown at the bottom-right. Self-contained (BodyShared)
//  so it renders inside the widget extension.
//

import SwiftUI

struct HealthWidgetTrendChartView: View {
    let metric: HealthWidgetMetric
    let range: HealthWidgetTrendRange
    let trend: HealthWidgetMetricTrend?

    private var series: HealthWidgetTrendSeries? {
        trend?.series(for: range)
    }

    private var hasData: Bool {
        series?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if hasData, let series {
                HealthWidgetTrendPlot(
                    style: metric.chartStyle,
                    points: series.points,
                    average: series.average,
                    color: metric.tintColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer(series: series)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metric.tintColor)
                .accessibilityHidden(true)

            Text(metric.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(metric.tintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 6)

            Text(range.displayName)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.secondary.opacity(0.14))
                )
        }
    }

    private func footer(series: HealthWidgetTrendSeries) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let source = trend?.primarySourceName, !source.isEmpty {
                Text(source)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 4)

            // Snapshots cached by older builds predate `latestText`; omit the label
            // rather than showing "Latest --" until the app rewrites the cache.
            if let latestText = series.latestText {
                valueLabel(String(localized: "Latest", table: "BodyShared"), value: latestText)
            }
            if let averageText = series.averageText {
                valueLabel(String(localized: "Avg", table: "BodyShared"), value: averageText)
            }
        }
    }

    private func valueLabel(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(.primary)

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 24, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metric.tintColor.opacity(0.55))

            Text(String(localized: "No \(metric.title) data", table: "BodyShared"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text(String(localized: "Open Body to sync", table: "BodyShared"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plot

/// Line/bar plot with a dashed average reference line. Shared by the medium
/// trend widget and the small metric widget so their chart style matches.
struct HealthWidgetTrendPlot: View {
    let style: HealthWidgetChartStyle
    let points: [HealthWidgetPoint]
    let average: Double?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let domain = valueDomain
            ZStack {
                switch style {
                case .line:
                    linePath(for: points, in: proxy.size, domain: domain)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                case .bar:
                    barPlot(for: points, in: proxy.size, domain: domain)
                }

                if let average, average.isFinite {
                    averageLine(value: average, in: proxy.size, domain: domain)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func averageLine(value: Double, in size: CGSize, domain: ClosedRange<Double>) -> some View {
        let y = yPosition(for: value, in: size.height, domain: domain)
        return Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        .stroke(
            color.opacity(0.8),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])
        )
    }

    private var valueDomain: ClosedRange<Double> {
        let values = points.compactMap(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            return (minimum - 1)...(maximum + 1)
        }

        // For bars, anchor the baseline at zero so heights read correctly.
        if style == .bar {
            return 0...(maximum + maximum * 0.08)
        }

        let padding = (maximum - minimum) * 0.16
        return (minimum - padding)...(maximum + padding)
    }

    private func xPosition(index: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return width * CGFloat(index) / CGFloat(count - 1)
    }

    private func yPosition(for value: Double, in height: CGFloat, domain: ClosedRange<Double>) -> CGFloat {
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)
        let normalized = min(max((value - domain.lowerBound) / span, 0), 1)
        return height - height * CGFloat(normalized)
    }

    private func linePath(
        for points: [HealthWidgetPoint],
        in size: CGSize,
        domain: ClosedRange<Double>
    ) -> Path {
        let positions: [CGPoint?] = points.enumerated().map { index, point in
            guard let value = point.value, value.isFinite else {
                return nil
            }
            return CGPoint(
                x: xPosition(index: index, count: points.count, width: size.width),
                y: yPosition(for: value, in: size.height, domain: domain)
            )
        }

        return Path { path in
            for run in contiguousRuns(positions) where run.count > 1 {
                path.move(to: run[0])
                for point in run.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
    }

    /// Runs of consecutive non-nil positions, split on each nil (missing-data)
    /// gap — a straight line across a gap would misleadingly imply interpolated
    /// data (precedent: `WatchSparklineView.contiguousRuns`).
    private func contiguousRuns(_ points: [CGPoint?]) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in points {
            if let point {
                current.append(point)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private func barPlot(
        for points: [HealthWidgetPoint],
        in size: CGSize,
        domain: ClosedRange<Double>
    ) -> some View {
        let count = points.count
        let spacing = barSpacing(count: count, width: size.width)
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let barWidth = count > 0 ? max((size.width - totalSpacing) / CGFloat(count), 1) : 1

        return HStack(alignment: .bottom, spacing: spacing) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(point.value == nil ? Color.secondary.opacity(0.12) : color.opacity(0.85))
                    .frame(
                        width: barWidth,
                        height: barHeight(for: point.value, in: size.height, domain: domain)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func barSpacing(count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        // Thinner gaps as the bar count grows (week vs. month).
        return min(4, max(1.5, width / CGFloat(count) * 0.22))
    }

    private func barHeight(for value: Double?, in height: CGFloat, domain: ClosedRange<Double>) -> CGFloat {
        guard let value, value.isFinite else {
            return max(height * 0.04, 3)
        }
        let span = max(domain.upperBound - domain.lowerBound, 0.0001)
        let normalized = min(max((value - domain.lowerBound) / span, 0), 1)
        return max(height * CGFloat(normalized), 3)
    }
}
