//
//  StressComplication.swift
//  BodyWatchWidgetExtension
//
//  The Stress complication: the latest Stress reading for up to 12 hours,
//  where the card falls back to the day's average once its current reading
//  is an hour old. It draws the circular ring and the rectangular row of the other
//  metric complications (`WatchComplicationView`), filled to the score out of
//  100 in the Stress pink of the Stress page, and the row names the reading's
//  band over the title. The reading is the latest scored window of the Stress
//  page's chart (`WatchStressTimeline.latestReading(asOf:)`), so it reads "--"
//  once that window is 12 hours old. Its band name comes stamped on the
//  timeline, since this target has no `StressBand`. The corner family curves
//  the same reading along the bezel over a 0 to 100 gauge in the same pink
//  (`complicationCornerGauge`), never the card's value or band, and reads "--"
//  over an empty gauge once the reading is 12 hours old, as the ring does.
//
//  The Stress bands complication (circular only) shows the same reading on
//  Stress's four bands, drawn like the Readiness bands (`WatchBandRingView`):
//  the reading's band in its own color, from `WatchStressBands`.
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
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}

/// The same reading on Stress's four bands, drawn like the Readiness bands.
struct StressBandsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchStressBands", provider: WatchMetricProvider()) { entry in
            StressBandsComplicationView(entry: entry)
                // Tapping the complication opens the Stress detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.stress))
        }
        .configurationDisplayName(String(localized: "Stress"))
        .description(String(localized: "Your latest stress reading and its level."))
        .supportedFamilies([.accessoryCircular])
    }
}

/// The reading every Stress complication shows: the ring, the bands, and the
/// Stress chart's spoken reading (`RecentHoursComplications.swift`). The gallery
/// placeholder (generated at `.distantPast`) carries a sample timeline on
/// fixed dates, so it is drawn without the age check, which would otherwise
/// preview the blank state.
func latestStressReading(in entry: WatchMetricEntry) -> (score: Int, end: Date)? {
    let timeline = entry.snapshot.stressTimeline
    return entry.snapshot.generatedAt == .distantPast
        ? timeline?.latestScoredWindow
        : timeline?.latestReading(asOf: entry.date)
}

private struct StressComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchMetricEntry

    /// Present while the phone shares Stress (the Heart permission). Without
    /// it the slot shows the empty state, like the other metric complications.
    private var metric: WatchMetric? { entry.snapshot.metric(forKind: WatchMetricKindKey.stress) }
    private var timeline: WatchStressTimeline? { entry.snapshot.stressTimeline }

    private var reading: (score: Int, end: Date)? { latestStressReading(in: entry) }

    private var ringText: String { reading.map { "\($0.score)" } ?? "--" }
    private var fillFraction: Double { reading.map { Double($0.score) / 100 } ?? 0 }
    /// The Stress page's theme color whatever the band, like the card's symbol.
    private let tint = WatchMetricKindKey.tint(forKind: WatchMetricKindKey.stress)

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCorner:
            corner
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

    /// The ring's reading and fill on the corner's 0 to 100 gauge.
    @ViewBuilder private var corner: some View {
        if metric != nil {
            complicationCornerGauge(value: ringText, fill: fillFraction, min: "0", max: "100", tint: Color(tint))
                .containerBackground(.clear, for: .widget)
        } else {
            Image(systemName: "applewatch")
                .foregroundStyle(.secondary)
                .containerBackground(.clear, for: .widget)
        }
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

/// Stress's bands round the ring (`WatchBandRingView`), the reading's band
/// tinted in its own color with the pill at the score. A Stress metric with no
/// reading reads "--" like the Stress ring; no Stress metric shows the watch
/// glyph, like the Readiness bands without a score.
private struct StressBandsComplicationView: View {
    let entry: WatchMetricEntry

    private var hasMetric: Bool { entry.snapshot.metric(forKind: WatchMetricKindKey.stress) != nil }
    private var score: Int? { hasMetric ? latestStressReading(in: entry)?.score : nil }
    private var text: String { score.map { "\($0)" } ?? "--" }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            WatchBandRingView(
                bandScoreRanges: WatchStressBands.scoreRanges,
                score: score,
                tint: Color(WatchStressBands.tint(forScore: score ?? 0)),
                valueFontScale: complicationRingFontScale(for: text, base: ComplicationRingFontScale.circular.base, compact: ComplicationRingFontScale.circular.compact),
                emptyText: hasMetric ? text : nil
            )
            .padding(1)
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

#Preview("Corner", as: .accessoryCorner) {
    StressComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Bands", as: .accessoryCircular) {
    StressBandsComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}
