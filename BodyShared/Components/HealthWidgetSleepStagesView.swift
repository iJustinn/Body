//
//  HealthWidgetSleepStagesView.swift
//  Body
//
//  Medium-widget content that charts today's sleep stages for the primary
//  source, once available (empty until today's own sleep session is
//  recorded — a prior night's stages are never carried over). Mirrors the
//  in-app hypnogram (BodySleepStageChart) but without interaction, and adds a
//  compact stage-duration legend.
//

import Charts
import SwiftUI
import WidgetKit

struct HealthWidgetSleepStagesView: View {
    let sleep: HealthWidgetSleepStages

    @Environment(\.widgetRenderingMode) private var renderingMode

    /// The Home Screen's Clear and Tinted appearances keep only each view's
    /// opacity, so every stage would draw the same flat color; give each stage
    /// its own opacity there instead (legend dots match the bars).
    private func stageStyle(_ stage: HealthWidgetSleepStage) -> Color {
        guard renderingMode == .accented else { return stage.color }
        switch stage {
        case .deep: return stage.color
        case .core: return stage.color.opacity(0.7)
        case .rem: return stage.color.opacity(0.45)
        case .awake: return stage.color.opacity(0.3)
        }
    }

    private var hasData: Bool {
        !sleep.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if hasData {
                chart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                timeAxis

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
                .widgetAccentable()
                .accessibilityHidden(true)

            Text(String(localized: "Sleep Stages", table: "BodyShared"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(HealthWidgetSleepStage.core.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()

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
                .foregroundStyle(stageStyle(segment.stage))
            }
        }
        .widgetAccentable()
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: 0.5...4.5)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    /// Start and wake times rendered manually (leading/trailing) so the end
    /// time stays inside the widget instead of being clipped by a centered
    /// chart axis label at the right edge.
    private var timeAxis: some View {
        HStack(spacing: 8) {
            if let start = sleep.segments.map(\.startDate).min() {
                Text(timeText(start))
            }

            Spacer(minLength: 8)

            if let end = sleep.segments.map(\.endDate).max() {
                Text(timeText(end))
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundColor(.secondary)
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(legendStages, id: \.self) { stage in
                HStack(spacing: 4) {
                    Circle()
                        .fill(stageStyle(stage))
                        .frame(width: 7, height: 7)
                        .widgetAccentable()

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
        guard end > start else {
            return start...start.addingTimeInterval(3_600)
        }
        // No padding: the hypnogram spans the full width so the manually
        // rendered start/end labels line up with the data edges.
        return start...end
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 24, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HealthWidgetSleepStage.core.color.opacity(0.55))

            Text(String(localized: "No sleep data yet", table: "BodyShared"))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)

            Text(String(localized: "Syncs after tonight's sleep", table: "BodyShared"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
