//
//  HealthWidgetTrendChartView.swift
//  Body
//
//  Medium-widget content that charts a single metric's weekly/monthly trend.
//  Draws the primary source and, when a secondary source is selected in the
//  app, overlays it for comparison. Self-contained (BodyShared) so it renders
//  inside the widget extension.
//

import SwiftUI

/// The secondary-source overlay color, matching the in-app comparison charts.
private let healthWidgetSecondaryColor = Color(red: 0.58, green: 0.36, blue: 0.98)

struct HealthWidgetTrendChartView: View {
    let metric: HealthWidgetMetric
    let range: HealthWidgetTrendRange
    let trend: HealthWidgetMetricTrend?

    private var rangeTrend: HealthWidgetRangeTrend? {
        trend?.rangeTrend(for: range)
    }

    private var hasData: Bool {
        (rangeTrend?.primary.isEmpty == false)
    }

    private var hasSecondary: Bool {
        guard let secondary = rangeTrend?.secondary else { return false }
        return !secondary.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if hasData, let rangeTrend {
                HealthWidgetTrendPlot(
                    style: metric.chartStyle,
                    primary: rangeTrend.primary.points,
                    secondary: hasSecondary ? rangeTrend.secondary?.points : nil,
                    primaryColor: metric.tintColor,
                    secondaryColor: healthWidgetSecondaryColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer(rangeTrend: rangeTrend)
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

    private func footer(rangeTrend: HealthWidgetRangeTrend) -> some View {
        HStack(alignment: .bottom) {
            averageColumn(
                value: rangeTrend.primary.averageText,
                source: trend?.primarySourceName,
                color: metric.tintColor,
                alignment: .leading
            )

            if hasSecondary {
                Spacer(minLength: 10)
                averageColumn(
                    value: rangeTrend.secondary?.averageText,
                    source: trend?.secondarySourceName,
                    color: healthWidgetSecondaryColor,
                    alignment: .trailing
                )
            }
        }
    }

    @ViewBuilder
    private func averageColumn(
        value: String?,
        source: String?,
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(value ?? "--")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(sourceCaption(source))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(
            maxWidth: .infinity,
            alignment: alignment == .leading ? .leading : .trailing
        )
    }

    private func sourceCaption(_ source: String?) -> String {
        if let source, !source.isEmpty {
            return source
        }
        return "\(range.chartTitle) avg"
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 24, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metric.tintColor.opacity(0.55))

            Text("No \(metric.title) data")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Open Body to sync")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plot

private struct HealthWidgetTrendPlot: View {
    let style: HealthWidgetChartStyle
    let primary: [HealthWidgetPoint]
    let secondary: [HealthWidgetPoint]?
    let primaryColor: Color
    let secondaryColor: Color

    var body: some View {
        GeometryReader { proxy in
            let domain = valueDomain
            ZStack {
                switch style {
                case .line:
                    linePath(for: primary, in: proxy.size, domain: domain)
                        .stroke(
                            primaryColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                case .bar:
                    barPlot(for: primary, in: proxy.size, domain: domain)
                }

                if let secondary {
                    linePath(for: secondary, in: proxy.size, domain: domain)
                        .stroke(
                            secondaryColor.opacity(0.9),
                            style: StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: style == .bar ? [4, 3] : []
                            )
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Shared value domain across both series so they're visually comparable.
    private var valueDomain: ClosedRange<Double> {
        let values = (primary + (secondary ?? []))
            .compactMap(\.value)
            .filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            return (minimum - 1)...(maximum + 1)
        }

        // For bars, anchor the baseline at zero so heights read correctly.
        if style == .bar {
            return 0...(maximum + (maximum - 0) * 0.08)
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
        Path { path in
            var started = false
            for (index, point) in points.enumerated() {
                guard let value = point.value, value.isFinite else {
                    continue
                }
                let position = CGPoint(
                    x: xPosition(index: index, count: points.count, width: size.width),
                    y: yPosition(for: value, in: size.height, domain: domain)
                )
                if started {
                    path.addLine(to: position)
                } else {
                    path.move(to: position)
                    started = true
                }
            }
        }
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
                    .fill(point.value == nil ? Color.secondary.opacity(0.12) : primaryColor.opacity(0.85))
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
