//
//  BodyMetricWarningCard.swift
//  Body
//

import Charts
import SwiftUI

/// Mirrors Apple's threshold notifications (Low/High Heart Rate, Low Blood
/// Oxygen) on the metric detail page: the sentence names the episode's first
/// past-threshold reading, and the chart shows the readings around it against
/// the threshold rule.
struct BodyMetricWarningCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let event: MetricWarningEvent
    let samples: [HealthTrendDataPoint]
    let window: DateInterval
    let tint: Color

    /// The limit this episode was detected against — the user's custom threshold
    /// when they set one, so the sentence and the rule match what fired.
    private var threshold: Double {
        event.threshold
    }

    /// Matches the detail page's Day View chart transition.
    private var chartTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                title
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.yellow)

            Text(sentence)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if event.kind.excludesWorkouts {
                Text("If you were working out, this warning will disappear once the workout is logged.")
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !samples.isEmpty {
                chart
                    // Scoped like the Day View chart: only sample changes animate,
                    // so the marks glide instead of snapping when the day (or the
                    // threshold) moves, and the outer transaction keeps inherited
                    // scroll/date-picker animations out.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0), value: samples)
                    .transition(chartTransition)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    @ViewBuilder
    private var title: some View {
        switch event.kind {
        case .lowHeartRate:
            Text("Low Heart Rate")
        case .highHeartRate:
            Text("High Heart Rate")
        case .lowBloodOxygen:
            Text("Low Blood Oxygen")
        }
    }

    private var sentence: String {
        let time = timeText(for: event.startDate)
        switch event.kind {
        case .lowHeartRate:
            return String(localized: "Your heart rate fell below \(Int(threshold)) BPM starting at \(time).")
        case .highHeartRate:
            return String(localized: "Your heart rate rose above \(Int(threshold)) BPM starting at \(time).")
        case .lowBloodOxygen:
            return String(localized: "Your blood oxygen fell below \(Int(threshold))% starting at \(time).")
        }
    }

    private var ruleLabel: String {
        switch event.kind {
        case .lowHeartRate, .highHeartRate:
            return String(localized: "\(Int(threshold)) BPM")
        case .lowBloodOxygen:
            return String(localized: "\(Int(threshold))%")
        }
    }

    private var valueLabel: LocalizedStringKey {
        switch event.kind {
        case .lowHeartRate, .highHeartRate:
            return "Heart Rate"
        case .lowBloodOxygen:
            return "Blood Oxygen"
        }
    }

    private func isPastThreshold(_ value: Double) -> Bool {
        event.kind.isAbove ? value > threshold : value < threshold
    }

    private var chart: some View {
        // Sources can stamp two readings at the same instant, so the marks are
        // keyed by position rather than by date.
        let indexedSamples = Array(samples.enumerated())

        return Chart {
            ForEach(indexedSamples, id: \.offset) { _, sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value(valueLabel, sample.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(indexedSamples, id: \.offset) { _, sample in
                PointMark(
                    x: .value("Time", sample.date),
                    y: .value(valueLabel, sample.value)
                )
                .symbolSize(28)
                .foregroundStyle(isPastThreshold(sample.value) ? Color.yellow : tint)
            }

            RuleMark(y: .value("Threshold", threshold))
                .foregroundStyle(.yellow)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                // Label on the right: above the rule for "below" kinds (the low
                // readings sit under it), below the rule for "above" kinds.
                .annotation(position: event.kind.isAbove ? .bottom : .top, alignment: .trailing) {
                    Text(ruleLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
        }
        .chartXScale(domain: window.start...window.end)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    // A mark on the trailing domain edge would have its label
                    // truncated by the plot bounds, so it goes unlabelled.
                    if let date = value.as(Date.self), isInteriorAxisDate(date) {
                        Text(timeText(for: date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let metricValue = value.as(Double.self) {
                        Text(metricValue.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .frame(height: 120)
    }

    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.value).filter(\.isFinite)
        let lower = (min(values.min() ?? threshold, threshold)).rounded(.down) - 5
        let upper = max(values.max() ?? threshold, threshold) + 5
        return lower...max(upper, lower + 1)
    }

    private func isInteriorAxisDate(_ date: Date) -> Bool {
        date < window.end.addingTimeInterval(-window.duration * 0.08)
    }

    private func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
