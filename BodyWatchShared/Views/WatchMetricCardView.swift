//
//  WatchMetricCardView.swift
//  BodyWatchShared
//
//  Watch dashboard card — the iOS `BodyHealthMetricCard` look adapted for the
//  watch (rounded card, title, value + unit, tinted SF Symbol bubble). No
//  `UIScreen` / Charts (iOS-only).
//
//  While the metric has a warning today that isn't folded, a yellow warning
//  triangle sits just left of the symbol bubble, as on the iPhone card. The
//  card stays plain data: the watch app hands it the warning titles, and the
//  complications (the widget extension compiles this file too) never do.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchMetricCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let metric: WatchMetric
    /// Non nil draws the warning glyph left of the symbol bubble, and is what
    /// VoiceOver speaks for it. The watch app passes the card's unfolded
    /// warning titles, list formatted; complications leave it nil, and a card
    /// without it lays out exactly as one without a warning always has.
    var warningAccessibilityLabel: String? = nil

    private var color: Color { Color(Self.symbolTint(for: metric)) }

    /// The symbol bubble's color: the carried status color, except Stress,
    /// whose iPhone card keeps the fixed Stress pink whatever the band (the
    /// band color stays on its detail page's status label).
    static func symbolTint(for metric: WatchMetric) -> WatchMetricColor {
        metric.kind == WatchMetricKindKey.stress
            ? WatchMetricKindKey.tint(forKind: metric.kind)
            : metric.resolvedTint
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.displayValue)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // The glyph and the bubble share a row, so the glyph is centered on
            // the bubble. The empty ZStack takes no width, so a card without a
            // warning keeps the bubble exactly where it was.
            HStack(spacing: 0) {
                ZStack {
                    if let label = warningAccessibilityLabel {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                            .padding(.trailing, 6)
                            .accessibilityLabel(Text(verbatim: label))
                            .transition(.opacity)
                    }
                }
                // The iPhone card badge's fade, so a warning arriving or being
                // folded reads the same on both.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: warningAccessibilityLabel)

                Image(systemName: WatchMetricKindKey.symbolName(forKind: metric.kind))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(color.opacity(0.18))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }
}
