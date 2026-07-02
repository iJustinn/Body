//
//  SleepCharts.swift
//  Body
//

import Charts

import SwiftUI

struct BodySleepStageChart: View {
    let snapshot: SleepStageSnapshot

    @State private var selectedStageDate: Date?
    @GestureState private var isSelectingStage = false

    var body: some View {
        Chart {
            ForEach(stageBridges) { bridge in
                RectangleMark(
                    xStart: .value("Bridge Start", bridge.startDate),
                    xEnd: .value("Bridge End", bridge.endDate),
                    yStart: .value("Bridge Y Start", bridge.yStart),
                    yEnd: .value("Bridge Y End", bridge.yEnd)
                )
                .foregroundStyle(bridgeGradient(for: bridge))
            }

            ForEach(snapshot.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segmentRenderStartDate(for: segment)),
                    xEnd: .value("End", segmentRenderEndDate(for: segment)),
                    yStart: .value("Stage Start", segment.stage.chartPosition - 0.32),
                    yEnd: .value("Stage End", segment.stage.chartPosition + 0.32)
                )
                .foregroundStyle(color(for: segment.stage))
            }

            if let selectedStageSegment {
                RuleMark(x: .value("Selected Segment", segmentMidpointDate(for: selectedStageSegment)))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        SleepStageSegmentIndicator(
                            stageName: selectedStageSegment.stage.displayName,
                            durationText: segmentDurationText(for: selectedStageSegment),
                            timeRangeText: segmentTimeRangeText(for: selectedStageSegment),
                            color: color(for: selectedStageSegment.stage)
                        )
                    }
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: 0.5...4.5)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel(anchor: xAxisLabelAnchor(for: value)) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: SleepStage.allCases.map(\.chartPosition)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let position = value.as(Double.self),
                       let stage = SleepStage.stage(at: position) {
                        Text(stage.axisLabel)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedStageDate)
        .simultaneousGesture(stageChartPressGesture)
    }

    private struct StageBridge: Identifiable {
        let id: String
        let startDate: Date
        let endDate: Date
        let yStart: Double
        let yEnd: Double
        let upperStage: SleepStage
        let lowerStage: SleepStage
    }

    private var stageBridges: [StageBridge] {
        let segments = snapshot.segments
        guard segments.count >= 2 else { return [] }

        var bridges: [StageBridge] = []
        for index in 0..<(segments.count - 1) {
            let current = segments[index]
            let next = segments[index + 1]
            guard current.stage != next.stage else { continue }

            let gapSeconds = next.startDate.timeIntervalSince(current.endDate)
            guard gapSeconds < 15 * 60 else { continue }

            let upperStage: SleepStage
            let lowerStage: SleepStage
            if current.stage.chartPosition > next.stage.chartPosition {
                upperStage = current.stage
                lowerStage = next.stage
            } else {
                upperStage = next.stage
                lowerStage = current.stage
            }

            let connectedStart = segmentDisplayEndDate(for: current)
            let connectedEnd = segmentDisplayStartDate(for: next)
            let bridgeStart = min(connectedStart, connectedEnd)
            let bridgeEnd = max(connectedStart, connectedEnd)

            let bridgeStageOverlap = 0.14
            let segmentHalfHeight = 0.32
            let yStart = lowerStage.chartPosition + segmentHalfHeight - bridgeStageOverlap
            let yEnd = upperStage.chartPosition - segmentHalfHeight + bridgeStageOverlap

            bridges.append(StageBridge(
                id: "bridge-\(current.id)-\(next.id)",
                startDate: bridgeStart,
                endDate: bridgeEnd,
                yStart: yStart,
                yEnd: yEnd,
                upperStage: upperStage,
                lowerStage: lowerStage
            ))
        }

        return bridges
    }

    private func bridgeGradient(for bridge: StageBridge) -> LinearGradient {
        LinearGradient(
            colors: [
                color(for: bridge.upperStage).opacity(0.92),
                color(for: bridge.lowerStage).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var selectedStageSegment: SleepStageSegment? {
        guard isSelectingStage, let selectedStageDate else {
            return nil
        }

        return segmentSelection(for: selectedStageDate)
    }

    private var stageChartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelectingStage) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedStageDate = nil
            }
    }

    private func segmentSelection(for date: Date) -> SleepStageSegment? {
        let visibleSegments = snapshot.segments.filter { segment in
            segmentRenderStartDate(for: segment) <= date && date <= segmentRenderEndDate(for: segment)
        }

        if let visibleSegment = visibleSegments.min(by: {
            segmentSelectionDistance(from: date, to: $0) < segmentSelectionDistance(from: date, to: $1)
        }) {
            return visibleSegment
        }

        let nearestSegment = snapshot.segments.min {
            segmentSelectionDistance(from: date, to: $0) < segmentSelectionDistance(from: date, to: $1)
        }

        guard let nearestSegment,
              segmentSelectionDistance(from: date, to: nearestSegment) <= 5 * 60 else {
            return nil
        }

        return nearestSegment
    }

    private func segmentSelectionDistance(from date: Date, to segment: SleepStageSegment) -> TimeInterval {
        if date < segment.startDate {
            return segment.startDate.timeIntervalSince(date)
        }

        if date > segment.endDate {
            return date.timeIntervalSince(segment.endDate)
        }

        return 0
    }

    private var segmentBridgeCoverWidth: TimeInterval {
        60
    }

    private func segmentDisplayStartDate(for segment: SleepStageSegment) -> Date {
        segment.startDate.addingTimeInterval(segmentSpacingInset(for: segment))
    }

    private func segmentDisplayEndDate(for segment: SleepStageSegment) -> Date {
        segment.endDate.addingTimeInterval(-segmentSpacingInset(for: segment))
    }

    private func segmentRenderStartDate(for segment: SleepStageSegment) -> Date {
        segmentDisplayStartDate(for: segment).addingTimeInterval(-segmentBridgeCoverWidth)
    }

    private func segmentRenderEndDate(for segment: SleepStageSegment) -> Date {
        segmentDisplayEndDate(for: segment).addingTimeInterval(segmentBridgeCoverWidth)
    }

    private func segmentSpacingInset(for segment: SleepStageSegment) -> TimeInterval {
        let duration = max(0, segment.endDate.timeIntervalSince(segment.startDate))
        guard duration > 90 else {
            return 0
        }

        return min(duration * 0.06, 35)
    }

    private func segmentMidpointDate(for segment: SleepStageSegment) -> Date {
        Date(timeIntervalSinceReferenceDate: (
            segment.startDate.timeIntervalSinceReferenceDate + segment.endDate.timeIntervalSinceReferenceDate
        ) / 2)
    }

    private func segmentDurationText(for segment: SleepStageSegment) -> String {
        BodyValueFormat.sleepDurationText(for: segment.endDate.timeIntervalSince(segment.startDate))
    }

    private func segmentTimeRangeText(for segment: SleepStageSegment) -> String {
        let startText = segmentTimeText(for: segment.startDate)
        let endText = segmentTimeText(for: segment.endDate)
        return "\(startText)-\(endText)"
    }

    private func segmentTimeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var chartXDomain: ClosedRange<Date> {
        let startDate = snapshot.segments.map(\.startDate).min() ?? Date()
        let endDate = snapshot.segments.map(\.endDate).max() ?? Date()
        let padding: TimeInterval = 15 * 60
        return startDate.addingTimeInterval(-padding)...endDate.addingTimeInterval(padding)
    }

    private var xAxisValues: [Date] {
        guard let startDate = snapshot.segments.map(\.startDate).min(),
              let endDate = snapshot.segments.map(\.endDate).max() else {
            return []
        }
        return [startDate, endDate]
    }

    private func xAxisLabelAnchor(for value: AxisValue) -> UnitPoint {
        guard let date = value.as(Date.self) else { return .top }
        if date == xAxisValues.first { return .topLeading }
        if date == xAxisValues.last { return .topTrailing }
        return .top
    }

    private func color(for stage: SleepStage) -> Color {
        stage.bodyChartColor
    }
}

extension SleepStage {
    var bodyChartColor: Color {
        switch self {
        case .awake:
            return Color(red: 1.00, green: 0.31, blue: 0.22)
        case .rem:
            return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .core:
            return Color(red: 0.24, green: 0.56, blue: 1.00)
        case .deep:
            return Color(red: 0.25, green: 0.25, blue: 0.82)
        }
    }

    /// Display-only "healthy night" reference band, as a fraction of total time in
    /// bed (all four stages). Independent of the sleep-score grading, which judges
    /// Deep/REM one-sided against asleep time.
    var optimalPercentageRange: ClosedRange<Double> {
        switch self {
        case .awake:
            return 0.00...0.05
        case .rem:
            return 0.20...0.25
        case .core:
            return 0.45...0.55
        case .deep:
            return 0.13...0.23
        }
    }
}

/// Per-stage breakdown bars with each stage's percentage of total time in bed, its
/// duration, and an overlaid optimal-range band. Shown in place of the duration
/// summary on the Sleep Stages card when the user taps to switch views.
struct BodySleepStageOptimalRangeChart: View {
    let snapshot: SleepStageSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stageLabelWidth: CGFloat = 52
    private let percentColumnWidth: CGFloat = 44
    private let durationColumnWidth: CGFloat = 68
    private let columnSpacing: CGFloat = 12
    private let trackHeight: CGFloat = 22
    private let barHeight: CGFloat = 14

    private var totalDuration: TimeInterval {
        SleepStage.allCases.reduce(0) { $0 + snapshot.duration(for: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ForEach(SleepStage.allCases) { stage in
                row(for: stage)
            }
            legend
        }
    }

    private var header: some View {
        HStack(spacing: columnSpacing) {
            Text("Stage")
                .frame(width: stageLabelWidth, alignment: .leading)
            Spacer(minLength: 0)
            Text("Pct.")
                .frame(width: percentColumnWidth, alignment: .trailing)
            Text("Duration")
                .frame(width: durationColumnWidth, alignment: .trailing)
        }
        .font(.system(.caption, design: .rounded))
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
    }

    private func row(for stage: SleepStage) -> some View {
        let stageDuration = snapshot.duration(for: stage)
        let fraction = totalDuration > 0 ? stageDuration / totalDuration : 0

        return HStack(spacing: columnSpacing) {
            Text(stage.displayName)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .frame(width: stageLabelWidth, alignment: .leading)

            track(for: stage, fraction: fraction)
                .frame(maxWidth: .infinity)
                .frame(height: trackHeight)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .frame(width: percentColumnWidth, alignment: .trailing)

            Text(BodyValueFormat.durationText(for: stageDuration))
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: durationColumnWidth, alignment: .trailing)
        }
    }

    private func track(for stage: SleepStage, fraction: Double) -> some View {
        let range = stage.optimalPercentageRange

        return GeometryReader { proxy in
            let width = proxy.size.width
            let bandWidth = max(0, CGFloat(range.upperBound - range.lowerBound) * width)
            let bandOffset = CGFloat(range.lowerBound) * width
            let fillWidth = CGFloat(min(1, max(0, fraction))) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: barHeight)

                Capsule()
                    .fill(stage.bodyChartColor)
                    .frame(width: fillWidth, height: barHeight)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: fraction)

                optimalBand
                    .frame(width: bandWidth, height: trackHeight)
                    .offset(x: bandOffset)
            }
            .frame(height: trackHeight)
        }
    }

    private var optimalBand: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
            )
    }

    private var legend: some View {
        HStack(spacing: 8) {
            optimalBand
                .frame(width: 22, height: 14)

            Text("Optimal Range")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)

            Text("Percent of time in bed")
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct BodySleepConsistencyChart: View {
    let model: SleepConsistencyChartModel
    let selectedDay: Date
    let onSelectDay: (Date) -> Void

    private let gutterWidth: CGFloat = 50
    private let dayLabelHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - gutterWidth, 1)
                let plotHeight = proxy.size.height

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        gridLines(plotWidth: plotWidth, plotHeight: plotHeight)
                        averageLines(plotWidth: plotWidth, plotHeight: plotHeight)
                        nightBars(plotWidth: plotWidth, plotHeight: plotHeight)
                    }
                    .drawingGroup()

                    dayTapTargets(plotWidth: plotWidth, plotHeight: plotHeight)
                }
            }

            dayLabels
                .frame(height: dayLabelHeight)
                .padding(.trailing, gutterWidth)
        }
    }

    @ViewBuilder
    private func gridLines(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        ForEach(model.gridHourOffsets, id: \.self) { offset in
            let lineY = y(forOffsetHours: offset, plotHeight: plotHeight)

            horizontalLine(at: lineY, width: plotWidth)
                .stroke(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            Text(timeText(forOffsetHours: offset))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.secondary)
                .position(x: plotWidth + gutterWidth / 2, y: lineY)
        }
    }

    @ViewBuilder
    private func averageLines(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        if let averageBed = model.averageBedOffsetHours {
            averageLine(offsetHours: averageBed, plotWidth: plotWidth, plotHeight: plotHeight, dash: [])
        }

        if let averageWake = model.averageWakeOffsetHours {
            averageLine(offsetHours: averageWake, plotWidth: plotWidth, plotHeight: plotHeight, dash: [4, 5])
        }
    }

    @ViewBuilder
    private func averageLine(
        offsetHours: Double,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        dash: [CGFloat]
    ) -> some View {
        let lineY = y(forOffsetHours: offsetHours, plotHeight: plotHeight)

        horizontalLine(at: lineY, width: plotWidth)
            .stroke(Color.primary.opacity(0.62), style: StrokeStyle(lineWidth: 1.5, dash: dash))

        Text(timeText(forOffsetHours: offsetHours))
            .font(.system(.caption2, design: .rounded))
            .fontWeight(.bold)
            .foregroundStyle(Color.primary)
            .position(x: plotWidth + gutterWidth / 2, y: lineY)
    }

    @ViewBuilder
    private func nightBars(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        let columnWidth = plotWidth / CGFloat(max(model.days.count, 1))
        let barWidth = min(columnWidth * 0.55, 18)

        ForEach(model.nights) { night in
            if let index = dayIndices[night.day] {
                ForEach(night.spans) { span in
                    let topY = y(forOffsetHours: span.startOffsetHours, plotHeight: plotHeight)
                    let bottomY = y(forOffsetHours: span.endOffsetHours, plotHeight: plotHeight)
                    let isCut = span.isCutAtStart || span.isCutAtEnd
                    let height = max(bottomY - topY, isCut ? 2 : barWidth)

                    SleepConsistencyNightBar(
                        span: span,
                        width: barWidth,
                        height: height
                    )
                    .position(
                        x: columnWidth * (CGFloat(index) + 0.5),
                        y: barCenterY(for: span, topY: topY, bottomY: bottomY, height: height)
                    )
                }
            }
        }
    }

    // Cut spans stay pinned to the wrap boundary even when inflated to the
    // minimum height; centering would push them past the plot edge.
    private func barCenterY(
        for span: SleepConsistencyNightSpan,
        topY: CGFloat,
        bottomY: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        if span.isCutAtEnd {
            return bottomY - height / 2
        }

        if span.isCutAtStart {
            return topY + height / 2
        }

        return (topY + bottomY) / 2
    }

    @ViewBuilder
    private func dayTapTargets(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        let columnWidth = plotWidth / CGFloat(max(model.days.count, 1))

        ForEach(model.days, id: \.self) { day in
            if let index = dayIndices[day] {
                Color.clear
                    .frame(width: columnWidth, height: plotHeight)
                    .contentShape(Rectangle())
                    .position(x: columnWidth * (CGFloat(index) + 0.5), y: plotHeight / 2)
                    .onTapGesture {
                        onSelectDay(day)
                    }
                    .accessibilityLabel(accessibilityLabel(for: day))
                    .accessibilityAddTraits(isSelected(day) ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var dayLabels: some View {
        HStack(spacing: 0) {
            ForEach(model.days, id: \.self) { day in
                let selected = isSelected(day)

                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: selected ? .heavy : .semibold, design: .rounded))

                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 12, weight: selected ? .heavy : .semibold, design: .rounded))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectDay(day)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var dayIndices: [Date: Int] {
        Dictionary(uniqueKeysWithValues: model.days.enumerated().map { ($1, $0) })
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.bodyGregorian.isDate(day, inSameDayAs: selectedDay)
    }

    private func y(forOffsetHours offset: Double, plotHeight: CGFloat) -> CGFloat {
        let domain = model.yDomainHours
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else {
            return 0
        }

        return CGFloat((offset - domain.lowerBound) / span) * plotHeight
    }

    private func horizontalLine(at lineY: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: lineY))
        path.addLine(to: CGPoint(x: width, y: lineY))
        return path
    }

    private func timeText(forOffsetHours offset: Double) -> String {
        guard let referenceDay = model.days.last,
              let date = SleepConsistencyChartModel.clockDate(forOffsetHours: offset, on: referenceDay) else {
            return ""
        }

        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func accessibilityLabel(for day: Date) -> String {
        let dayText = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard let night = model.nights.first(where: { $0.day == day }) else {
            return String(localized: "\(dayText): no sleep data")
        }

        let bedText = timeText(forOffsetHours: night.bedOffsetHours)
        let wakeText = timeText(forOffsetHours: night.wakeOffsetHours)
        return String(localized: "\(dayText): asleep \(bedText) to \(wakeText)")
    }
}

private struct SleepConsistencyNightBar: View {
    let span: SleepConsistencyNightSpan
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            barShape
                .fill(SleepStage.core.bodyChartColor)

            ForEach(span.slices) { slice in
                Rectangle()
                    .fill(slice.stage.bodyChartColor)
                    .frame(width: width, height: sliceHeight(for: slice))
                    .offset(y: sliceTop(for: slice))
            }
        }
        .frame(width: width, height: height)
        .clipShape(barShape)
        .accessibilityHidden(true)
    }

    // Capsule ends except where the bar is cut by the 18:00 wrap boundary,
    // which sits flat on the plot edge.
    private var barShape: UnevenRoundedRectangle {
        let radius = min(width, height) / 2
        let topRadius = span.isCutAtStart ? 0 : radius
        let bottomRadius = span.isCutAtEnd ? 0 : radius

        return UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
    }

    private var spanHours: Double {
        max(span.endOffsetHours - span.startOffsetHours, 0.001)
    }

    private func sliceTop(for slice: SleepConsistencyNightSlice) -> CGFloat {
        CGFloat((slice.startOffsetHours - span.startOffsetHours) / spanHours) * height
    }

    private func sliceHeight(for slice: SleepConsistencyNightSlice) -> CGFloat {
        CGFloat((slice.endOffsetHours - slice.startOffsetHours) / spanHours) * height
    }
}

struct SleepStageSegmentIndicator: View {
    let stageName: String
    let durationText: String
    let timeRangeText: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(stageName)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(durationText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(timeRangeText)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .bodyChartSelectionAnnotationBackground()
    }
}

struct SleepVitalDisplayRow: Identifiable {
    let title: String
    let value: String
    let unit: String
    let symbolName: String
    let tintColor: Color
    let numericValue: Double
    let referenceRange: SleepVitalReferenceRange

    var id: String {
        title
    }

    var region: SleepVitalRegion {
        referenceRange.region(for: numericValue)
    }

    var markerPosition: Double {
        referenceRange.markerPosition(for: numericValue)
    }
}

private extension SleepVitalRegion {
    var dotColor: Color {
        switch self {
        case .typical:
            return Color(red: 0.25, green: 0.62, blue: 1.00)
        case .low, .high:
            return Color(red: 1.00, green: 0.24, blue: 0.20)
        }
    }
}

struct BodySleepVitalsRegionChart: View {
    let rows: [SleepVitalDisplayRow]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 12) {
                BodySleepVitalsRegionPlot(rows: rows)
                    .frame(height: BodyHealthDetailChartLayout.sleepVitalsPlotHeight)

                BodySleepVitalsIconAxis(rows: rows)
                    .frame(height: BodyHealthDetailChartLayout.sleepVitalsIconAxisHeight)
            }

            BodySleepVitalRegionLabels()
                .frame(width: 56, height: BodyHealthDetailChartLayout.sleepVitalsPlotHeight)
        }
    }
}

struct BodySleepVitalsRegionPlot: View {
    let rows: [SleepVitalDisplayRow]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                    path.move(to: CGPoint(x: 0, y: height / 3))
                    path.addLine(to: CGPoint(x: width, y: height / 3))
                    path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                    path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
                }
                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)

                ForEach(1..<max(rows.count, 1), id: \.self) { index in
                    Path { path in
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(rows.count, 1))
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    .stroke(
                        Color.secondary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
                }

                ForEach(rows.indices, id: \.self) { index in
                    BodySleepVitalRegionDot(row: rows[index])
                        .position(
                            x: xPosition(for: index, width: proxy.size.width),
                            y: yPosition(for: rows[index], height: proxy.size.height)
                        )
                }
            }
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard !rows.isEmpty else {
            return width / 2
        }

        return width * (CGFloat(index) + 0.5) / CGFloat(rows.count)
    }

    private func yPosition(for row: SleepVitalDisplayRow, height: CGFloat) -> CGFloat {
        height * CGFloat(1 - row.markerPosition)
    }
}

struct BodySleepVitalsIconAxis: View {
    let rows: [SleepVitalDisplayRow]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(1..<max(rows.count, 1), id: \.self) { index in
                    Path { path in
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(rows.count, 1))
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    .stroke(
                        Color.secondary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
                }

                ForEach(rows.indices, id: \.self) { index in
                    Image(systemName: rows[index].symbolName)
                        .font(.system(size: 18, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.secondary.opacity(0.58))
                        .frame(width: 32, height: 28)
                        .position(
                            x: xPosition(for: index, width: proxy.size.width),
                            y: proxy.size.height / 2
                        )
                        .accessibilityLabel("\(rows[index].title): \(rows[index].value) \(rows[index].unit)")
                }
            }
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard !rows.isEmpty else {
            return width / 2
        }

        return width * (CGFloat(index) + 0.5) / CGFloat(rows.count)
    }
}

struct BodySleepVitalRegionDot: View {
    let row: SleepVitalDisplayRow

    var body: some View {
        Circle()
            .fill(Color(.systemGroupedBackground))
            .frame(width: 19, height: 19)
            .overlay(
                Circle()
                    .stroke(row.region.dotColor, lineWidth: 5)
            )
            .shadow(color: row.region.dotColor.opacity(row.region == .typical ? 0 : 0.26), radius: 5)
            .accessibilityLabel("\(row.title): \(row.value) \(row.unit), \(accessibilityRegion)")
    }

    private var accessibilityRegion: String {
        switch row.region {
        case .low:
            return String(localized: "Low")
        case .typical:
            return String(localized: "Typical")
        case .high:
            return String(localized: "High")
        }
    }
}

struct BodySleepVitalRegionLabels: View {
    var body: some View {
        VStack(spacing: 0) {
            regionLabel("High")
            regionLabel("Typical")
            regionLabel("Low")
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundColor(Color.secondary.opacity(0.62))
    }

    private func regionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
