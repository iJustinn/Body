//
//  HealthWidgetTrendCardView.swift
//  BodyShared
//
//  Large-widget content that mirrors one Home Trends card (`BodyHomeTrendCard`):
//  the metric header, the app's trend sentence, the comparison chart and the two
//  averages. Self-contained (BodyShared) so it renders inside the widget extension.
//

import SwiftUI
import WidgetKit

struct HealthWidgetTrendCardView: View {
    let resolution: TrendCardEntryBuilder.Resolution
    /// The pinned metric's name, for the header of its empty state.
    var pinnedTitle: String?

    /// The metric tint, for the header and the Gradient background.
    static func tint(for resolution: TrendCardEntryBuilder.Resolution) -> Color? {
        presentation(for: resolution.metric)?.tint
    }

    private static func presentation(for metric: String?) -> HealthMetricPresentation? {
        metric.flatMap(HealthMetricKind.init(rawValue:)).flatMap(HealthMetricPresentation.presentation(for:))
    }

    private var tint: Color {
        Self.tint(for: resolution) ?? .secondary
    }

    private var symbolName: String {
        Self.presentation(for: resolution.metric)?.symbolName ?? "chart.line.uptrend.xyaxis"
    }

    var body: some View {
        switch resolution {
        case .card(let card):
            cardContent(card)
        case .empty(let metric, let isInTrends):
            emptyContent(isPinned: metric != nil, isInTrends: isInTrends)
        }
    }

    private func cardContent(_ card: HealthWidgetTrendCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: card.title)

            Text(card.messageText)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            BodyTrendComparisonPlot(
                values: card.values,
                baselineEndIndex: card.baselineEndIndex,
                baselineAverage: card.baselineAverage,
                recentAverage: card.recentAverage,
                chartStyle: card.chartStyle == .bar ? .bar : .line,
                color: tint
            )
            // The dots straddle the plot's edges; keep them off the divider and labels.
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            averages(card)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel(for: card)))
    }

    private func accessibilityLabel(for card: HealthWidgetTrendCard) -> String {
        [
            card.title + ".",
            card.messageText,
            "\(card.baselineAverageText) \(card.baselinePeriodText),",
            "\(card.recentAverageText) \(card.recentPeriodText)"
        ].joined(separator: " ")
    }

    private func header(title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .widgetAccentable()
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .widgetAccentable()

            Spacer(minLength: 0)
        }
    }

    private func averages(_ card: HealthWidgetTrendCard) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                averageText(card.baselineAverageText, size: 17)
                averageText(card.baselinePeriodText, size: 14)
            }
            .foregroundColor(.secondary)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                averageText(card.recentAverageText, size: 17)
                averageText(card.recentPeriodText, size: 14)
            }
            .foregroundColor(tint)
            .widgetAccentable()
        }
    }

    private func averageText(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func emptyContent(isPinned: Bool, isInTrends: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPinned, let pinnedTitle {
                header(title: pinnedTitle)
            }

            VStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 28, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint.opacity(0.55))
                    .accessibilityHidden(true)

                Text(isPinned
                    ? String(localized: "Not enough data yet", table: "BodyShared")
                    : String(localized: "No trends yet", table: "BodyShared"))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // A metric hidden from Home's trends may never have its year fetched.
                Text(isInTrends
                    ? String(localized: "Open Body to sync", table: "BodyShared")
                    : String(localized: "Open Body and turn it on in Settings › Trend Cards", table: "BodyShared"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension TrendCardEntryBuilder.Resolution {
    /// The `HealthMetricKind` raw value this resolution is about, if any.
    var metric: String? {
        switch self {
        case .card(let card): return card.metric
        case .empty(let metric, _): return metric
        }
    }
}
