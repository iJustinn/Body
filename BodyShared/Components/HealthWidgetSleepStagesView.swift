//
//  HealthWidgetSleepStagesView.swift
//  Body
//
//  Medium-widget content that charts the most recent night's sleep stages for
//  the primary source. Mirrors the in-app hypnogram (BodySleepStageChart) but
//  without interaction, and adds a compact stage-duration legend.
//

import Charts
import SwiftUI

struct HealthWidgetSleepStagesView: View {
    let sleep: HealthWidgetSleepStages

    private var hasData: Bool {
        !sleep.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if hasData {
                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                legend
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HealthWidgetSleepStage.core.color)
                .accessibilityHidden(true)

            Text("Sleep Stages")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(HealthWidgetSleepStage.core.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 6)

            if hasData {
                Text(BodyValueFormat.sleepDurationText(for: sleep.asleepDuration))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(sleep.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.startDate),
                    xEnd: .value("End", segment.endDate),
                    yStart: .value("Stage Start", segment.stage.chartPosition - 0.32),
                    yEnd: .value("Stage End", segment.stage.chartPosition + 0.32)
                )
                .foregroundStyle(segment.stage.color)
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: 0.5...4.5)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.16))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: HealthWidgetSleepStage.allCases.map(\.chartPosition)) { value in
                AxisValueLabel {
                    if let position = value.as(Double.self),
                       let stage = HealthWidgetSleepStage.stage(at: position) {
                        Text(stage.displayName)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(legendStages, id: \.self) { stage in
                HStack(spacing: 4) {
                    Circle()
                        .fill(stage.color)
                        .frame(width: 7, height: 7)

                    Text(stage.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)

                    Text(BodyValueFormat.sleepDurationText(for: sleep.duration(for: stage)))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Show the detailed stages when available; otherwise fall back to the
    /// stages that actually have time recorded (e.g. iPhone-only "asleep").
    private var legendStages: [HealthWidgetSleepStage] {
        if sleep.hasDetailedStages {
            return [.deep, .core, .rem, .awake]
        }
        return HealthWidgetSleepStage.allCases.filter { sleep.duration(for: $0) > 0 }
    }

    private var chartXDomain: ClosedRange<Date> {
        let start = sleep.segments.map(\.startDate).min() ?? Date()
        let end = sleep.segments.map(\.endDate).max() ?? Date()
        let padding: TimeInterval = 10 * 60
        guard end > start else {
            return start...start.addingTimeInterval(3_600)
        }
        return start.addingTimeInterval(-padding)...end.addingTimeInterval(padding)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 24, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HealthWidgetSleepStage.core.color.opacity(0.55))

            Text("No sleep data")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)

            Text("Open Body to sync")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
