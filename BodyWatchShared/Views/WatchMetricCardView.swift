//
//  WatchMetricCardView.swift
//  BodyWatchShared
//
//  Watch dashboard card — the iOS `BodyHealthMetricCard` look adapted for the
//  watch (rounded card, title, value + unit, tinted SF Symbol bubble). No
//  `UIScreen` / Charts (iOS-only).
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchMetricCardView: View {
    let metric: WatchMetric

    private var color: Color { Color(WatchMetricKindKey.tint(forKind: metric.kind)) }

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

            Image(systemName: WatchMetricKindKey.symbolName(forKind: metric.kind))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color.opacity(0.18))
                )
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
