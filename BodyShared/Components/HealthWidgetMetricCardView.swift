//
//  HealthWidgetMetricCardView.swift
//  Body
//
//  Small-widget content that mirrors the home screen's metric preview cards:
//  title (top-left), the recent-week trend chart (middle), the current value(s)
//  (bottom-left), and the metric icon (bottom-right). The chart reuses the
//  medium trend widget's plot so the line style matches. Self-contained
//  (BodyShared) so it renders inside the widget extension.
//

import SwiftUI

struct HealthWidgetMetricCardView: View {
    let metric: HealthWidgetMetric
    let trend: HealthWidgetMetricTrend?

    var body: some View {
        // The app writes a trend entry for every metric, so a nil check alone
        // would never show the empty state once a snapshot exists; route on
        // whether the metric actually has chartable data (matches the medium
        // trend widget's empty handling).
        if let trend, trend.hasAnyData {
            cardContent(trend: trend)
        } else {
            emptyState
        }
    }

    private func cardContent(trend: HealthWidgetMetricTrend) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title

            Spacer(minLength: 4)

            HealthWidgetTrendPlot(
                style: metric.chartStyle,
                points: trend.week.points,
                average: nil,
                color: metric.tintColor
            )
            .frame(maxWidth: .infinity)
            .frame(height: 36)

            Spacer(minLength: 4)

            HStack(alignment: .bottom, spacing: 8) {
                values(trend.displayValues)

                Spacer(minLength: 8)

                iconBadge
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var title: some View {
        Text(metric.title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func values(_ displayValues: [HealthWidgetDisplayValue]) -> some View {
        if displayValues.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(displayValues.enumerated()), id: \.offset) { _, displayValue in
                    valueRow(displayValue, valueFontSize: 26)
                }
            }
        } else {
            valueRow(displayValues.first ?? HealthWidgetDisplayValue(value: "--", unit: ""), valueFontSize: 30)
        }
    }

    private func valueRow(_ displayValue: HealthWidgetDisplayValue, valueFontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(displayValue.value)
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if !displayValue.unit.isEmpty {
                Text(displayValue.unit)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var iconBadge: some View {
        Image(systemName: metric.symbolName)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(metric.tintColor)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(metric.tintColor.opacity(0.16))
            )
            .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: metric.symbolName)
                .font(.system(size: 24, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(metric.tintColor.opacity(0.55))

            Text("No \(metric.title) data")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("Open Body to sync")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
