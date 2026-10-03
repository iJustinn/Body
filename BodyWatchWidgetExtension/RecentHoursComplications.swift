//
//  RecentHoursComplications.swift
//  BodyWatchWidgetExtension
//
//  The intraday chart complications (accessoryRectangular only): Stress over
//  the last 12 hours, and Heart Rate and HRV over the last 8, the charts their
//  detail pages draw, compacted by `WatchRecentHoursChartView` under a header
//  that names the metric on the left and its latest reading on the right.
//  Stress draws the snapshot's `stressTimeline`, which the phone pushes or the
//  watch recomputes, under the Stress complication's own reading
//  (`latestStressReading(in:)`) and its band. Heart Rate and HRV draw the 30
//  minute slots the watch compute keeps in `heartCharts`, under the card's
//  value and unit. Each chart ends at its entry's date, and the provider adds
//  an entry at every local half hour across the chart's window
//  (`slidingWindow`), so the window slides without a reload. A window with
//  nothing in it shows "Nothing to chart yet" under the header, and the slot
//  shows "Open Body on iPhone" while the phone shares no such card. Free (not
//  Pro-gated), like the bar complications, and a tap opens the metric's page.
//  Kept apart from `StressComplication.swift`, whose source guards are scoped
//  to that file.
//

import SwiftUI
import WidgetKit

struct StressChartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchStressChart", provider: WatchMetricProvider(slidingWindow: WatchStressChartGeometry.windowLength)) { entry in
            RecentHoursComplicationView(metricKind: WatchMetricKindKey.stress, entry: entry)
                // Tapping the complication opens the Stress detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.stress))
        }
        .configurationDisplayName(String(localized: "Stress"))
        .description(String(localized: "Your stress over the last 12 hours."))
        .supportedFamilies([.accessoryRectangular])
    }
}

struct HeartRateChartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchHeartRateChart", provider: WatchMetricProvider(slidingWindow: WatchIntradayWindow.length)) { entry in
            RecentHoursComplicationView(metricKind: WatchMetricKindKey.heartRate, entry: entry)
                // Tapping the complication opens the Heart Rate detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.heartRate))
        }
        .configurationDisplayName(String(localized: "Heart Rate"))
        .description(String(localized: "Your heart rate over the last 8 hours."))
        .supportedFamilies([.accessoryRectangular])
    }
}

struct HRVChartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BodyWatchHRVChart", provider: WatchMetricProvider(slidingWindow: WatchIntradayWindow.length)) { entry in
            RecentHoursComplicationView(metricKind: WatchMetricKindKey.heartRateVariability, entry: entry)
                // Tapping the complication opens the HRV detail page.
                .widgetURL(WatchMetricDeepLink.url(forKind: WatchMetricKindKey.heartRateVariability))
        }
        .configurationDisplayName(String(localized: "HRV"))
        .description(String(localized: "Your heart rate variability over the last 8 hours."))
        .supportedFamilies([.accessoryRectangular])
    }
}

/// One intraday chart under its header, or the empty state while the phone
/// shares no such card (Stress, Heart Rate and HRV all come with the Heart
/// permission).
private struct RecentHoursComplicationView: View {
    let metricKind: String
    let entry: WatchMetricEntry

    private var metric: WatchMetric? { entry.snapshot.metric(forKind: metricKind) }
    private var isStress: Bool { metricKind == WatchMetricKindKey.stress }

    var body: some View {
        Group {
            if let metric {
                WatchRecentHoursChartView(
                    title: metric.title,
                    reading: reading(for: metric),
                    content: content,
                    now: now,
                    emptyText: String(localized: "Nothing to chart yet")
                )
            } else {
                Text("Open Body on iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    /// The header's reading. Stress: the Stress complication's reading (the
    /// latest scored window, until it is 12 hours old) with the band stamped
    /// on the timeline; a timeline from a build without the band shows the
    /// score alone, as the Stress row does. Heart Rate and HRV: the card's
    /// value and unit, which can differ from the chart's last 30 minute
    /// average, as on the page.
    private func reading(for metric: WatchMetric) -> String {
        if isStress {
            guard let reading = latestStressReading(in: entry) else { return "--" }
            guard let band = entry.snapshot.stressTimeline?.latestBand?.label else { return "\(reading.score)" }
            return "\(reading.score) \(band)"
        }
        guard metric.hasValue else { return "--" }
        return metric.unit.isEmpty ? metric.displayValue : "\(metric.displayValue) \(metric.unit)"
    }

    private var content: WatchRecentHoursChartView.Content {
        if isStress {
            return .stress(entry.snapshot.stressTimeline)
        }
        return .readings(
            entry.snapshot.heartCharts?[metricKind]?.buckets ?? [],
            tint: Color(WatchMetricKindKey.tint(forKind: metricKind))
        )
    }

    /// The chart's right edge: the entry's date, so the window slides with
    /// the timeline's half hour entries. The gallery placeholder (generated at
    /// `.distantPast`) carries sample data on fixed dates, so it is drawn up
    /// to the data's own end instead, as the Stress complication skips its
    /// age check for it; ending at today would preview the empty caption.
    private var now: Date {
        guard entry.snapshot.generatedAt == .distantPast else { return entry.date }
        let end = isStress ? entry.snapshot.stressTimeline?.end : entry.snapshot.heartCharts?[metricKind]?.window.end
        return end ?? entry.date
    }
}

#Preview("Stress", as: .accessoryRectangular) {
    StressChartComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Heart Rate", as: .accessoryRectangular) {
    HeartRateChartComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("HRV", as: .accessoryRectangular) {
    HRVChartComplication()
} timeline: {
    WatchMetricEntry(date: .now, snapshot: .placeholder)
    WatchMetricEntry(date: .now, snapshot: .empty)
}
