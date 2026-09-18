//
//  WatchComplicationView.swift
//  BodyWatchWidgetExtension
//
//  Renders a single metric as the magenta ring (accessoryCircular), a ring +
//  label row (accessoryRectangular), or a curved bezel gauge (accessoryCorner).
//  Score-style metrics (Readiness, Sleep) show their 0–100 score in the center;
//  the rest show their value. Readiness uses this view only for its corner
//  gauge; its circular and rectangular families are `ReadinessComplicationView`.
//

import Foundation
import SwiftUI
import WidgetKit

/// Value font scale for text inside a complication ring. Two digits keep the
/// base scale; from three digits up ("100", "1.05", "93.4") the text steps down
/// so it clears the ring instead of leaning on `minimumScaleFactor`.
func complicationRingFontScale(for text: String, base: Double) -> Double {
    text.filter(\.isNumber).count >= 3 ? base * 0.85 : base
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let metricKind: String
    let entry: WatchMetricEntry

    private var metric: WatchMetric? { entry.snapshot.metric(forKind: metricKind) }

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

    private func ringValue(_ metric: WatchMetric) -> String {
        if let score = metric.score { return "\(score)" }
        return metric.displayValue
    }

    /// Text inside the ring. A Training Load under 1 drops its leading zero
    /// ("0.85" reads ".85") so the two digits that matter get the ring's width;
    /// the rectangular row and the corner keep the full value.
    private func ringText(_ metric: WatchMetric) -> String {
        let value = ringValue(metric)
        guard metric.kind == WatchMetricKindKey.trainingLoad,
              value.count > 2, value.first == "0",
              let separator = value.dropFirst().first, !separator.isNumber
        else { return value }
        return String(value.dropFirst())
    }

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let metric {
                WatchMetricRingView(
                    fillFraction: metric.fillFraction,
                    value: ringText(metric),
                    unit: "",
                    symbolName: WatchMetricKindKey.symbolName(forKind: metric.kind),
                    tint: metric.resolvedTint,
                    showsUnit: false,
                    showsGlyph: true,
                    valueFontScale: complicationRingFontScale(for: ringText(metric), base: 0.30)
                )
                .padding(1)
            } else {
                Image(systemName: "applewatch")
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder private var corner: some View {
        if let metric {
            cornerGauge(metric)
                .containerBackground(.clear, for: .widget)
        } else {
            Image(systemName: "applewatch")
                .foregroundStyle(.secondary)
                .containerBackground(.clear, for: .widget)
        }
    }

    private func cornerGauge(_ metric: WatchMetric) -> some View {
        let gauge = cornerGaugeModel(metric)
        return Text(ringValue(metric))
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .widgetCurvesContent()   // curve the value along the bezel (watchOS 10+), like Weather
            .widgetLabel {
                Gauge(value: gauge.fill) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                } minimumValueLabel: {
                    Text(gauge.min)
                } maximumValueLabel: {
                    Text(gauge.max)
                }
                .tint(Color(metric.resolvedTint))
            }
    }

    /// Corner-gauge fill + end labels. Readiness and Training Load span their
    /// CURRENT status band (carried as levelMin/levelMax) — the ends show that
    /// band's range and the fill is the value's position within it (tint is the
    /// band color via resolvedTint). Other metrics keep the precomputed
    /// fillFraction with the recent-range labels.
    private func cornerGaugeModel(_ metric: WatchMetric) -> (fill: Double, min: String, max: String) {
        if let low = metric.levelMin, let high = metric.levelMax, high > low, let value = metric.rawValue {
            let rawFill = (value - low) / (high - low)
            let fill = rawFill.isFinite ? min(max(rawFill, 0), 1) : 0
            return (fill, levelLabel(low, kind: metric.kind), levelLabel(high, kind: metric.kind))
        }
        let ends = gaugeEndLabels(metric)
        let fallbackFill = metric.fillFraction.isFinite ? min(max(metric.fillFraction, 0), 1) : 0
        return (fallbackFill, ends?.min ?? "", ends?.max ?? "")
    }

    private func levelLabel(_ value: Double, kind: String) -> String {
        if kind == WatchMetricKindKey.readiness { return "\(Int(value.rounded()))" }
        return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// Display-ready labels for the gauge's two ends, oriented to the fill
    /// direction so the dot reads correctly between them. Score/ratio metrics
    /// use their fixed band (0…100 / 0…2); HR, HRV, and Skin Temp use the recent
    /// range the snapshot carries (nil when there's no series → no labels).
    /// Resting HR's fill is inverted on the iPhone (low = good = full), so its
    /// ends are swapped here to match. The carried temperature range is Celsius,
    /// so convert to the displayed unit.
    private func gaugeEndLabels(_ metric: WatchMetric) -> (min: String, max: String)? {
        guard let low = metric.rangeMin, let high = metric.rangeMax, high > low else { return nil }
        let isTemp = metric.kind == WatchMetricKindKey.wristTemperature
        // `usesFahrenheit` is stamped by the builder; the unit-string sniff is
        // only the fallback for a snapshot from a phone build without it.
        let toFahrenheit = isTemp && (metric.usesFahrenheit ?? metric.unit.contains("F"))
        func label(_ value: Double) -> String {
            let shown = toFahrenheit ? value * 9 / 5 + 32 : value
            return "\(Int(shown.rounded()))"
        }
        if metric.kind == WatchMetricKindKey.restingHeartRate {
            return (min: label(high), max: label(low))   // inverted fill → swap ends
        }
        return (min: label(low), max: label(high))
    }

    @ViewBuilder private var rectangular: some View {
        HStack(spacing: 8) {
            if let metric {
                WatchMetricRingView(
                    fillFraction: metric.fillFraction,
                    value: ringText(metric),
                    unit: "",
                    symbolName: WatchMetricKindKey.symbolName(forKind: metric.kind),
                    tint: metric.resolvedTint,
                    showsUnit: false,
                    showsGlyph: false,
                    valueFontScale: complicationRingFontScale(for: ringText(metric), base: 0.40)
                )
                .frame(width: 46, height: 46)
                // The ring is open at the bottom, so its drawn part sits high
                // in its frame; nudge it down to center what is visible.
                .offset(y: 2)

                // Both lines the same size, the reading over the title. A
                // banded metric (Training Load) names its level, since the ring
                // already shows the number; the rest show value and unit.
                VStack(alignment: .leading, spacing: 1) {
                    if let level = metric.statusBand?.label {
                        Text(level)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(metric.displayValue)
                                .font(.headline)
                            if !metric.unit.isEmpty {
                                Text(metric.unit)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                    }
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
        .rectangularComplicationBorder()
        .containerBackground(.clear, for: .widget)
    }
}
