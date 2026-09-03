//
//  WatchSleepStagesChartView.swift
//  BodyWatch
//
//  The night's sleep stages for the Sleep detail page: the iPhone hypnogram
//  (`BodySleepStageChart`) drawn straight onto the page's tinted background,
//  with no card. Same four stage rows, stage colors, gapped segments, and
//  gradient connectors between neighbouring stages; a stage letter on the
//  leading axis per row and the night's bed and wake times on the bottom
//  axis. Display-only: no scrubbing and no date-switch choreography, since the
//  watch shows one night, the main session the snapshot's `sleepStages`
//  carries (naps excluded, like the Sleep Stages complication).
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import Charts
import SwiftUI

struct WatchSleepStagesChartView: View {
    let segments: [SleepStageSegment]

    /// `BodySleepStageChart`'s constants, so the two charts render the same
    /// night the same way.
    private static let segmentHalfHeight = 0.32
    private static let bridgeStageOverlap = 0.14
    private static let bridgeCoverWidth: TimeInterval = 60
    private static let bridgeMaxGap: TimeInterval = 15 * 60
    private static let paddingFraction = 0.033

    init(segments: [SleepStageSegment]) {
        self.segments = segments.sorted { $0.startDate < $1.startDate }
    }

    /// The snapshot's raw segments as typed stages, dropping any stage name
    /// this build doesn't know (a newer phone could push one).
    static func segments(from raw: [WatchSleepStageSegment]) -> [SleepStageSegment] {
        raw.compactMap { segment in
            guard let stage = SleepStage(rawValue: segment.stage), segment.endDate > segment.startDate else {
                return nil
            }
            return SleepStageSegment(stage: stage, startDate: segment.startDate, endDate: segment.endDate)
        }
    }

    var body: some View {
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
                        Self.color(for: bridge.upperStage).opacity(0.92),
                        Self.color(for: bridge.lowerStage).opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }

            ForEach(segments) { segment in
                RectangleMark(
                    xStart: .value("Start", renderStartDate(for: segment)),
                    xEnd: .value("End", renderEndDate(for: segment)),
                    yStart: .value("Stage Start", segment.stage.chartPosition - Self.segmentHalfHeight),
                    yEnd: .value("Stage End", segment.stage.chartPosition + Self.segmentHalfHeight)
                )
                .foregroundStyle(Self.color(for: segment.stage))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0.5...4.5)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.18))
                AxisTick()
                    .foregroundStyle(.white.opacity(0.28))
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: SleepStage.allCases.map(\.chartPosition)) { value in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.18))
                AxisTick()
                    .foregroundStyle(.white.opacity(0.28))
                AxisValueLabel {
                    if let position = value.as(Double.self), let stage = SleepStage.stage(at: position) {
                        Text(stage.axisLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .accessibilityLabel(String(localized: "Sleep stages"))
    }

    /// Mirrors `SleepStage.bodyChartColor` (Body/Views/Health/Charts/SleepCharts.swift),
    /// which is iOS-only; the Sleep Stages complication carries the same four
    /// literals for the same reason.
    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: return Color(red: 1.00, green: 0.31, blue: 0.22)
        case .rem: return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .core: return Color(red: 0.24, green: 0.56, blue: 1.00)
        case .deep: return Color(red: 0.25, green: 0.25, blue: 0.82)
        }
    }

    // MARK: - Geometry

    private var nightSpan: ClosedRange<Date>? {
        guard let start = segments.map(\.startDate).min(),
              let end = segments.map(\.endDate).max(),
              end > start else {
            return nil
        }
        return start...end
    }

    private var xDomain: ClosedRange<Date> {
        guard let nightSpan else {
            let now = Date()
            return now...now.addingTimeInterval(3_600)
        }
        let padding = nightSpan.upperBound.timeIntervalSince(nightSpan.lowerBound) * Self.paddingFraction
        return nightSpan.lowerBound.addingTimeInterval(-padding)...nightSpan.upperBound.addingTimeInterval(padding)
    }

    private var axisDates: [Date] {
        guard let nightSpan else { return [] }
        return [nightSpan.lowerBound, nightSpan.upperBound]
    }

    private struct Bridge: Identifiable {
        let id: String
        let startDate: Date
        let endDate: Date
        let yStart: Double
        let yEnd: Double
        let upperStage: SleepStage
        let lowerStage: SleepStage
    }

    /// A gradient connector between each pair of neighbouring segments on
    /// different rows, unless a real gap (15 min or more) separates them.
    private var bridges: [Bridge] {
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

    private func displayStartDate(for segment: SleepStageSegment) -> Date {
        segment.startDate.addingTimeInterval(spacingInset(for: segment))
    }

    private func displayEndDate(for segment: SleepStageSegment) -> Date {
        segment.endDate.addingTimeInterval(-spacingInset(for: segment))
    }

    /// Segments overhang their display span by the bridge cover so the
    /// connector never shows through a segment's end.
    private func renderStartDate(for segment: SleepStageSegment) -> Date {
        displayStartDate(for: segment).addingTimeInterval(-Self.bridgeCoverWidth)
    }

    private func renderEndDate(for segment: SleepStageSegment) -> Date {
        displayEndDate(for: segment).addingTimeInterval(Self.bridgeCoverWidth)
    }

    private func spacingInset(for segment: SleepStageSegment) -> TimeInterval {
        let duration = max(0, segment.endDate.timeIntervalSince(segment.startDate))
        guard duration > 90 else { return 0 }
        return min(duration * 0.06, 35)
    }
}
