//
//  WatchComplicationView.swift
//  BodyWatchWidgetExtension
//
//  Renders a single metric as the magenta ring (accessoryCircular) or a ring +
//  label row (accessoryRectangular). Score-style metrics (Readiness, Sleep)
//  show their 0–100 score in the center; the rest show their value.
//

import SwiftUI
import WidgetKit

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let metricKind: String
    let entry: WatchMetricEntry

    private var metric: WatchMetric? { entry.snapshot.metric(forKind: metricKind) }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    private func ringValue(_ metric: WatchMetric) -> String {
        if let score = metric.score { return "\(score)" }
        return metric.displayValue
    }

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let metric {
                WatchMetricRingView(
                    fillFraction: metric.fillFraction,
                    value: ringValue(metric),
                    unit: "",
                    symbolName: WatchMetricKindKey.symbolName(forKind: metric.kind),
                    tint: WatchMetricKindKey.tint(forKind: metric.kind),
                    showsUnit: false,
                    showsGlyph: false
                )
                .padding(1)
            } else {
                Image(systemName: "applewatch")
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder private var rectangular: some View {
        HStack(spacing: 8) {
            if let metric {
                WatchMetricRingView(
                    fillFraction: metric.fillFraction,
                    value: ringValue(metric),
                    unit: "",
                    symbolName: WatchMetricKindKey.symbolName(forKind: metric.kind),
                    tint: WatchMetricKindKey.tint(forKind: metric.kind),
                    showsUnit: false,
                    showsGlyph: false
                )
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(metric.title)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(metric.displayValue)
                            .font(.title3)
                            .bold()
                        if !metric.unit.isEmpty {
                            Text(metric.unit)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("Open Body on iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}
