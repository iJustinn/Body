//
//  BodyLowHeartRateWarningCard.swift
//  Body
//

import Charts
import SwiftUI

/// Mirrors Apple's "Low Heart Rate" notification on the Heart Rate detail page:
/// the sentence names the episode's first sub-threshold reading, and the chart
/// shows the readings around it against the threshold rule.
struct BodyLowHeartRateWarningCard: View {
    let event: LowHeartRateEvent
    let samples: [HealthTrendDataPoint]
    let window: DateInterval
    let tint: Color
    var threshold: Double = LowHeartRateWarning.thresholdBPM

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("Low Heart Rate")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.yellow)

            Text(sentence)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !samples.isEmpty {
                chart
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private var sentence: String {
        String(localized: "Your heart rate fell below \(Int(threshold)) BPM starting at \(timeText(for: event.startDate)).")
    }

    private var chart: some View {
        Chart {
            ForEach(samples, id: \.date) { sample in
                LineMark(
                    x: .value("Time", sample.date),
                    y: .value("Heart Rate", sample.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(samples, id: \.date) { sample in
                PointMark(
                    x: .value("Time", sample.date),
                    y: .value("Heart Rate", sample.value)
                )
                .symbolSize(28)
                .foregroundStyle(sample.value < threshold ? Color.yellow : tint)
            }

            RuleMark(y: .value("Threshold", threshold))
                .foregroundStyle(.yellow)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text(String(localized: "\(Int(threshold)) BPM"))
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
                    if let bpm = value.as(Double.self) {
                        Text(bpm.formatted(.number.precision(.fractionLength(0))))
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
        let lower = min(30, (values.min() ?? threshold).rounded(.down) - 5)
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
