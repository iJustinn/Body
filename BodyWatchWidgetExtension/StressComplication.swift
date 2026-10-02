//
//  StressComplication.swift
//  BodyWatchWidgetExtension
//
//  The Stress complication: the latest Stress reading, not the card's daily
//  average. It draws the circular ring and the rectangular row of the other
//  metric complications (`WatchComplicationView`), filled to the score out of
//  100 in the Stress pink of the Stress page, and the row names the reading's
//  band over the title. The reading is the latest scored window of the Stress
//  page's chart (`WatchStressTimeline.latestReading(asOf:)`), so it reads "--"
//  once that window is 12 hours old. Its band name comes stamped on the
//  timeline, since this target has no `StressBand`. No corner gauge.
//

import SwiftUI
import WidgetKit

struct StressComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchStress", provider: WatchMetricProvider()) { entry in
            StressComplicationView(entry: entry)
                // Tapping the complication opens the Stress detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.stress))
        }
        .configurationDisplayName(String(localized: "Stress"))
        .description(String(localized: "Your latest stress reading."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct StressComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchMetricEntry

    /// Present while the phone shares Stress (the Heart permission). Without
    /// it the slot shows the empty state, like the other metric complications.
    private var metric: WatchMetric? { entry.snapshot.metric(forKind: WatchMetricKindKey.stress) }
    private var timeline: WatchStressTimeline? { entry.snapshot.stressTimeline }

    /// The gallery placeholder (generated at `.distantPast`) carries a sample
    /// timeline on fixed dates, so it is drawn without the age check, which
    /// would otherwise preview the blank state.
    private var reading: (score: Int, end: Date)? {
        entry.snapshot.generatedAt == .distantPast
            ? timeline?.latestScoredWindow
            : timeline?.latestReading(asOf: entry.date)
    }

    private var ringText: String { reading.map { "\($0.score)" } ?? "--" }
    private var fillFraction: Double { reading.map { Double($0.score) / 100 } ?? 0 }
    /// The Stress page's theme color whatever the band, like the card's symbol.
    private let tint = WatchMetricKindKey.tint(forKind: WatchMetricKindKey.stress)

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        default:
            circular
        }
    }

    private func ring(showsGlyph: Bool, fontScale: (base: Double, compact: Double)) -> some View {
        WatchMetricRingView(
            fillFraction: fillFraction,
            value: ringText,
            unit: "",
            symbolName: WatchMetricKindKey.symbolName(forKind: WatchMetricKindKey.stress),
            tint: tint,
            showsUnit: false,
            showsGlyph: showsGlyph,
            valueFontScale: complicationRingFontScale(for: ringText, base: fontScale.base, compact: fontScale.compact)
        )
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if metric != nil {
                ring(showsGlyph: true, fontScale: ComplicationRingFontScale.circular)
                    .padding(1)
            } else {
                Image(systemName: "applewatch")
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            if let metric {
                ring(showsGlyph: false, fontScale: ComplicationRingFontScale.rectangular)
                    .frame(width: 46, height: 46)
                    // The ring is open at the bottom, so its drawn part sits
                    // high in its frame; nudge it down to center what is visible.
                    .offset(y: 2)

                // The ring already shows the score, so the row names its band
                // over the title, like the other banded metrics. A timeline
                // from a build without the band shows the score instead.
                VStack(alignment: .leading, spacing: 1) {
                    Text(reading == nil ? ringText : timeline?.latestBand?.label ?? ringText)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(metric.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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

#Preview("Circular", as: .accessoryCircular) {
    StressComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    StressComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}
