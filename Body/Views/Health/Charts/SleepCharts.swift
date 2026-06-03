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
                AxisValueLabel {
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
                        Text(stage.displayName)
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
        axisValues(strideHours: 2, minimumCount: 4)
    }

    private func axisValues(strideHours: Int, minimumCount: Int) -> [Date] {
        let calendar = Calendar.bodyGregorian
        let lowerBound = chartXDomain.lowerBound
        let upperBound = chartXDomain.upperBound
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: lowerBound)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0

        var current = calendar.date(from: components) ?? lowerBound
        if current < lowerBound {
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? lowerBound
        }

        var values: [Date] = []
        while current <= upperBound {
            values.append(current)
            let next = calendar.date(byAdding: .hour, value: strideHours, to: current)
                ?? current.addingTimeInterval(TimeInterval(strideHours) * 60 * 60)
            guard next > current else {
                break
            }
            current = next
        }

        if values.count < minimumCount && strideHours > 1 {
            return axisValues(strideHours: 1, minimumCount: minimumCount)
        }

        return values
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
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
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
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
            return "Low"
        case .typical:
            return "Typical"
        case .high:
            return "High"
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

    private func regionLabel(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

