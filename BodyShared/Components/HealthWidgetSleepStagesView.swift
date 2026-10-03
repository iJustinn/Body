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

    /// `BodySleepStageChart`'s constants, so the widget connects neighbouring
    /// stages with the same thin gradient connectors as the in-app chart.
    private static let segmentHalfHeight = 0.32
    private static let bridgeStageOverlap = 0.14
    private static let bridgeCoverWidth: TimeInterval = 60
    private static let bridgeMaxGap: TimeInterval = 15 * 60

    private var chart: some View {
        Chart {
            ForEach(bridges) { bridge in
                RectangleMark(
                    xStart: .value("Bridge Start", bridge.startDate),
                    xEnd: .value("Bridge End", bridge.endDate),
                    yStart: .value("Bridge Y Start", bridge.yStart),
                    yEnd: .value("Bridge Y End", bridge.yEnd)
                )
                .foregroundStyle(LinearGradient(
                    colors: [
                        stageStyle(bridge.upperStage).opacity(0.92),
                        stageStyle(bridge.lowerStage).opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }

            ForEach(sleep.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", renderStartDate(for: segment)),
                    xEnd: .value("End", renderEndDate(for: segment)),
                    yStart: .value("Stage Start", segment.stage.chartPosition - Self.segmentHalfHeight),
                    yEnd: .value("Stage End", segment.stage.chartPosition + Self.segmentHalfHeight)
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

    private struct Bridge: Identifiable {
        let id: String
        let startDate: Date
        let endDate: Date
        let yStart: Double
        let yEnd: Double
        let upperStage: HealthWidgetSleepStage
        let lowerStage: HealthWidgetSleepStage
    }

    /// A gradient connector between each pair of neighbouring segments on
    /// different rows, unless a real gap (15 min or more) separates them.
    private var bridges: [Bridge] {
        let segments = sleep.segments.sorted { $0.startDate < $1.startDate }
        guard segments.count >= 2 else { return [] }
        return zip(segments, segments.dropFirst()).compactMap { current, next in
            guard current.stage != next.stage,
                  next.startDate.timeIntervalSince(current.endDate) < Self.bridgeMaxGap else {
                return nil
            }
            let upper = current.stage.chartPosition > next.stage.chartPosition ? current.stage : next.stage
            let lower = upper == current.stage ? next.stage : current.stage
            let connectedStart = displayEndDate(for: current)
            let connectedEnd = displayStartDate(for: next)
            return Bridge(
                id: "bridge-\(current.id)-\(next.id)",
                startDate: min(connectedStart, connectedEnd),
                endDate: max(connectedStart, connectedEnd),
                yStart: lower.chartPosition + Self.segmentHalfHeight - Self.bridgeStageOverlap,
                yEnd: upper.chartPosition - Self.segmentHalfHeight + Self.bridgeStageOverlap,
                upperStage: upper,
                lowerStage: lower
            )
        }
    }

    private func displayStartDate(for segment: HealthWidgetSleepSegment) -> Date {
        segment.startDate.addingTimeInterval(spacingInset(for: segment))
    }

    private func displayEndDate(for segment: HealthWidgetSleepSegment) -> Date {
        segment.endDate.addingTimeInterval(-spacingInset(for: segment))
    }

    /// Segments overhang their display span by the bridge cover so the
    /// connector never shows through a segment's end, clamped to the
    /// unpadded domain so the first and last bars stay flush with the
    /// start and end labels.
    private func renderStartDate(for segment: HealthWidgetSleepSegment) -> Date {
        max(displayStartDate(for: segment).addingTimeInterval(-Self.bridgeCoverWidth), chartXDomain.lowerBound)
    }

    private func renderEndDate(for segment: HealthWidgetSleepSegment) -> Date {
        min(displayEndDate(for: segment).addingTimeInterval(Self.bridgeCoverWidth), chartXDomain.upperBound)
    }

    private func spacingInset(for segment: HealthWidgetSleepSegment) -> TimeInterval {
        let duration = segment.duration
        guard duration > 90 else { return 0 }
        return min(duration * 0.06, 35)
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
