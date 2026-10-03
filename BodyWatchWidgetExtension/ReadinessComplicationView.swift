//
//  ReadinessComplicationView.swift
//  BodyWatchWidgetExtension
//
//  The Readiness complication: the home readiness hero at complication size.
//  Five band segments, the active band tinted with the status color, a pill
//  marking the score, and the score in the middle.
//
//  The hero's bands are bent around a circle (a 300 degree ring, open at the
//  bottom, with thicker bands than the hero's 200 degree arc) so they fill a
//  round slot rather than floating in it: alone in accessoryCircular, beside
//  the title row in accessoryRectangular. `WatchBandRingView` draws the ring,
//  as it does the Stress bands complication's; the band ranges come from
//  `BodyReadinessArcGeometry`, the same geometry as `WatchReadinessHeroView`.
//  The corner family keeps the curved bezel gauge from `WatchComplicationView`,
//  because a corner's bezel content must be a system Gauge.
//

import SwiftUI
import WidgetKit

struct ReadinessComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchMetricEntry

    private var metric: WatchMetric? { entry.snapshot.metric(forKind: WatchMetricKindKey.readiness) }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCorner:
            WatchComplicationView(metricKind: WatchMetricKindKey.readiness, entry: entry)
        default:
            circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            WatchBandRingView(bandScoreRanges: BodyReadinessArcGeometry.bandScoreRanges, score: metric?.score, tint: tint, valueFontScale: valueFontScale(ComplicationRingFontScale.circular))
                .padding(1)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            WatchBandRingView(bandScoreRanges: BodyReadinessArcGeometry.bandScoreRanges, score: metric?.score, tint: tint, valueFontScale: valueFontScale(ComplicationRingFontScale.rectangular))
                .frame(width: 46, height: 46)
                // The ring is open at the bottom, so its drawn part sits high
                // in its frame; nudge it down to center what is visible.
                .offset(y: 1)

            if let metric {
                VStack(alignment: .leading, spacing: 1) {
                    // The ring already shows the score, so the row leads with
                    // the level. A snapshot from an older phone build carries
                    // no label; fall back to the value.
                    if let level = metric.statusBand?.label {
                        Text(level)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(metric.displayValue + metric.unit)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(metric.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text("Open Body on iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var tint: Color {
        Color(metric?.resolvedTint ?? WatchMetricKindKey.tint(forKind: WatchMetricKindKey.readiness))
    }

    /// The score's size in the ring, a step down from three digits up.
    private func valueFontScale(_ scale: (base: Double, compact: Double)) -> Double {
        complicationRingFontScale(for: metric?.score.map { "\($0)" } ?? "", base: scale.base, compact: scale.compact)
    }
}

/// The gallery placeholder with Readiness at `score`, for the previews.
private func previewEntry(score: Int, level: String, red: Double, green: Double, blue: Double) -> WatchMetricEntry {
    var snapshot = WatchMetricsSnapshot.placeholder
    if let index = snapshot.metrics.firstIndex(where: { $0.kind == WatchMetricKindKey.readiness }) {
        snapshot.metrics[index].score = score
        snapshot.metrics[index].displayValue = "\(score)"
        snapshot.metrics[index].tint = WatchMetricColor(red: red, green: green, blue: blue)
        snapshot.metrics[index].statusBand?.label = level
    }
    return WatchMetricEntry(date: .now, snapshot: snapshot)
}

#Preview("Circular", as: .accessoryCircular) {
    ReadinessComplication()
} timeline: {
    previewEntry(score: 78, level: "Moderate", red: 0.10, green: 0.82, blue: 0.20)
    previewEntry(score: 97, level: "Prime", red: 0.84, green: 0.08, blue: 0.92)
    previewEntry(score: 86, level: "High", red: 0.20, green: 0.74, blue: 1.00)
    previewEntry(score: 52, level: "Low", red: 1.00, green: 0.75, blue: 0.15)
    previewEntry(score: 21, level: "Poor", red: 1.00, green: 0.25, blue: 0.12)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ReadinessComplication()
} timeline: {
    previewEntry(score: 78, level: "Moderate", red: 0.10, green: 0.82, blue: 0.20)
    previewEntry(score: 97, level: "Prime", red: 0.84, green: 0.08, blue: 0.92)
    previewEntry(score: 86, level: "High", red: 0.20, green: 0.74, blue: 1.00)
    previewEntry(score: 52, level: "Low", red: 1.00, green: 0.75, blue: 0.15)
    previewEntry(score: 21, level: "Poor", red: 1.00, green: 0.25, blue: 0.12)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Corner", as: .accessoryCorner) {
    ReadinessComplication()
} timeline: {
    previewEntry(score: 78, level: "Moderate", red: 0.10, green: 0.82, blue: 0.20)
    previewEntry(score: 97, level: "Prime", red: 0.84, green: 0.08, blue: 0.92)
    previewEntry(score: 86, level: "High", red: 0.20, green: 0.74, blue: 1.00)
    previewEntry(score: 52, level: "Low", red: 1.00, green: 0.75, blue: 0.15)
    previewEntry(score: 21, level: "Poor", red: 1.00, green: 0.25, blue: 0.12)
    WatchMetricEntry(date: .now, snapshot: .empty)
}
