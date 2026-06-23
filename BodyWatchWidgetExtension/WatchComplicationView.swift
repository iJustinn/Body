//
//  WatchComplicationView.swift
//  BodyWatchWidgetExtension
//
//  Renders a single metric as the magenta ring (accessoryCircular), a ring +
//  label row (accessoryRectangular), or a curved bezel gauge (accessoryCorner).
//  Score-style metrics (Readiness, Sleep) show their 0–100 score in the center;
//  the rest show their value.
//

import Foundation
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

    @ViewBuilder private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let metric {
                WatchMetricRingView(
                    fillFraction: metric.fillFraction,
                    value: ringValue(metric),
                    unit: "",
                    symbolName: WatchMetricKindKey.symbolName(forKind: metric.kind),
                    tint: metric.resolvedTint,
                    showsUnit: false,
                    showsGlyph: true,
                    valueFontScale: 0.35
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
            let fill = min(max((value - low) / (high - low), 0), 1)
            return (fill, levelLabel(low, kind: metric.kind), levelLabel(high, kind: metric.kind))
        }
        let ends = gaugeEndLabels(metric)
        return (metric.fillFraction, ends?.min ?? "", ends?.max ?? "")
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
        let toFahrenheit = isTemp && metric.unit.contains("F")
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
                    value: ringValue(metric),
                    unit: "",
                    symbolName: WatchMetricKindKey.symbolName(forKind: metric.kind),
                    tint: metric.resolvedTint,
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
