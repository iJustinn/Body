//
//  SleepCharts.swift
//  Body
//

import Charts

import SwiftUI

struct BodySleepStageChart: View {
    let snapshot: SleepStageSnapshot
    /// Explicit axis tick spans (the Nap Stages card passes each nap's span so
    /// every nap gets its start and end labeled); nil keeps the default single
    /// pair of ticks at the first segment start and last segment end.
    var axisMarkIntervals: [DateInterval]? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedStageDate: Date?
    @GestureState private var isSelectingStage = false
    /// Lags `snapshot` while the date-switch choreography runs: the old night
    /// stays rendered through the collapse, swaps mid-flight while flattened,
    /// and the new night renders through the expansion. `nil` until the first
    /// switch (render falls back to the `snapshot` prop).
    @State private var displayedSnapshot: SleepStageSnapshot?
    @State private var displayedAxisMarkIntervals: [DateInterval]?
    /// While `true`, every stage segment sits on the Core row at opacity 0 and
    /// the flat Core-colored band carries the whole visual.
    @State private var isFlattened = false
    /// Invalidates in-flight choreography completions when a newer date switch
    /// supersedes them.
    @State private var transitionGeneration = 0

    var body: some View {
        Chart {
            // The choreography's base: a single Core-row band spanning the
            // night. Segments dissolve into it on collapse and the new
            // segments grow back out of it. One stable mark, always at the
            // same place — the plot space is fractional, so it never travels.
            if let nightSpan = Self.nightSpan(of: renderSnapshot) {
                // Padded by the bridge-cover overhang so no Core-colored
                // segment pokes past the band while flattened.
                RectangleMark(
                    xStart: .value("Flatten Start", normalizedDate(nightSpan.lowerBound.addingTimeInterval(-segmentBridgeCoverWidth))),
                    xEnd: .value("Flatten End", normalizedDate(nightSpan.upperBound.addingTimeInterval(segmentBridgeCoverWidth))),
                    yStart: .value("Flatten Y Start", Self.flattenedYRange.lowerBound),
                    yEnd: .value("Flatten Y End", Self.flattenedYRange.upperBound)
                )
                .foregroundStyle(color(for: .core))
                .opacity(isFlattened ? 1 : 0)
                // Purely a transition prop — never part of the reading.
                .accessibilityHidden(true)
            }

            // Bridges and segments stay fully opaque through the choreography:
            // they shrink onto the Core row while their colors blend into the
            // Core tint, so by the swap everything is Core-on-Core and the
            // mid-flight snapshot change (old marks out, new marks in) is
            // invisible against the band.
            ForEach(stageBridges) { bridge in
                RectangleMark(
                    xStart: .value("Bridge Start", normalizedDate(bridge.startDate)),
                    xEnd: .value("Bridge End", normalizedDate(bridge.endDate)),
                    yStart: .value("Bridge Y Start", isFlattened ? Self.flattenedYRange.lowerBound : bridge.yStart),
                    yEnd: .value("Bridge Y End", isFlattened ? Self.flattenedYRange.upperBound : bridge.yEnd)
                )
                .foregroundStyle(bridgeGradient(for: bridge))
            }

            ForEach(renderSnapshot.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", normalizedDate(segmentRenderStartDate(for: segment))),
                    xEnd: .value("End", normalizedDate(segmentRenderEndDate(for: segment))),
                    yStart: .value("Stage Start", Self.segmentYRange(for: segment.stage, isFlattened: isFlattened).lowerBound),
                    yEnd: .value("Stage End", Self.segmentYRange(for: segment.stage, isFlattened: isFlattened).upperBound)
                )
                .foregroundStyle(color(for: isFlattened ? .core : segment.stage))
            }

            if let selectedStageSegment {
                RuleMark(x: .value("Selected Segment", normalizedDate(segmentMidpointDate(for: selectedStageSegment))))
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
                    if let date = value.as(Date.self), let text = axisTimeText(forNormalized: date) {
                        // The tick sits at a fixed fraction of the plot, so the
                        // label keeps its identity across a date switch and its
                        // digits roll over in place instead of sliding — the
                        // same numeric transition the metric values use.
                        Text(text)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: text)
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
        // Scoped like the day chart's morph animations: the detail view wraps
        // this chart in a `.transaction { animation = nil }`, so the phases
        // animate via these value-keyed modifiers, not ambient transactions.
        // Collapse + expand together take `Self.transitionDuration`, matching
        // the numeric flip the times and the card's duration run. Only the
        // flatten flag is animated: the night itself swaps instantly while
        // flat, so the incoming marks are born on the Core row.
        .animation(reduceMotion ? nil : .easeInOut(duration: Self.phaseDuration), value: isFlattened)
        .onAppear {
            // Seed the lagging copy while it still holds this night: by the
            // time `onChange` runs, `snapshot` is already the incoming one, so
            // an unseeded chart would have no outgoing night to collapse and
            // the first date switch would pop.
            if displayedSnapshot == nil {
                displayedSnapshot = snapshot
                displayedAxisMarkIntervals = axisMarkIntervals
            }
        }
        .onChange(of: snapshot) { oldSnapshot, newSnapshot in
            transition(from: oldSnapshot, to: newSnapshot, axisMarkIntervals: axisMarkIntervals)
        }
    }

    /// The night currently rendered — see `displayedSnapshot`.
    private var renderSnapshot: SleepStageSnapshot {
        displayedSnapshot ?? snapshot
    }

    private var renderAxisMarkIntervals: [DateInterval]? {
        displayedSnapshot == nil ? axisMarkIntervals : displayedAxisMarkIntervals
    }

    /// The date-switch choreography: every segment sinks onto the Core row and
    /// dissolves into the flat band, the band alone travels to the new night's
    /// span, then the new segments grow out of it back to their stage rows.
    private func transition(
        from oldSnapshot: SleepStageSnapshot,
        to newSnapshot: SleepStageSnapshot,
        axisMarkIntervals newIntervals: [DateInterval]?
    ) {
        transitionGeneration += 1
        let generation = transitionGeneration
        selectedStageDate = nil

        // Covers a snapshot that changed before `onAppear` seeded the lagging
        // copy — the outgoing night is what the collapse animates from, and
        // it is already gone from `snapshot` by now.
        if displayedSnapshot == nil {
            displayedSnapshot = oldSnapshot
        }

        guard !reduceMotion,
              !renderSnapshot.segments.isEmpty,
              !newSnapshot.segments.isEmpty else {
            displayedSnapshot = newSnapshot
            displayedAxisMarkIntervals = newIntervals
            isFlattened = false
            return
        }

        isFlattened = true
        // Sequenced by wall clock rather than animation completions so the
        // call site's transaction override cannot collapse the phases into
        // one; the scoped `.animation(value:)` modifiers drive each phase.
        // The night swaps at the midpoint, while everything is flat and
        // Core-colored, so the change of data itself is never visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.phaseDuration) {
            guard generation == transitionGeneration else { return }

            // Instantly, and still flattened: segment and bridge ids change
            // with the night, so the incoming marks have to be born on the
            // Core row. Animating this swap, or clearing `isFlattened` in the
            // same update, would instead insert them on their stage rows —
            // which Swift Charts pops rather than grows.
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                displayedSnapshot = newSnapshot
                displayedAxisMarkIntervals = newIntervals
            }

            // One frame later, so that flattened render actually commits
            // before the expansion releases the new night to its stage rows.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.swapSettleDelay) {
                guard generation == transitionGeneration else { return }
                isFlattened = false
            }
        }
    }

    /// Collapse, a frame to publish the incoming night flattened, then expand —
    /// together the length of the numeric flip the times and the card's
    /// duration text run, so the segments finish settling exactly as the
    /// digits stop rolling.
    static let transitionDuration: TimeInterval = 0.4
    static let swapSettleDelay: TimeInterval = 1.0 / 60
    static var phaseDuration: TimeInterval { (transitionDuration - swapSettleDelay) / 2 }

    /// A segment's y-extent: its own stage row, or the Core row while the
    /// choreography has the chart flattened.
    static func segmentYRange(for stage: SleepStage, isFlattened: Bool) -> ClosedRange<Double> {
        let center = isFlattened ? SleepStage.core.chartPosition : stage.chartPosition
        return (center - 0.32)...(center + 0.32)
    }

    static var flattenedYRange: ClosedRange<Double> {
        segmentYRange(for: .core, isFlattened: true)
    }

    // MARK: - Fractional plot space

    /// Every night is plotted as a fraction of its own bed-to-wake span on
    /// this fixed window, so the x domain never changes: a date switch resizes
    /// the segments where they stand instead of sliding the night sideways,
    /// and the start/end ticks keep their identity so their labels can roll
    /// their digits over rather than travel. The reference instant and span
    /// are arbitrary — only the fractions are ever read.
    static let plotReferenceStart = Date(timeIntervalSinceReferenceDate: 0)
    static let plotSpan: TimeInterval = 3_600
    /// Breathing room on both ends, as a fraction of the span — about the 15
    /// minutes the old absolute-date domain padded a typical night by.
    static let plotPaddingFraction = 0.033

    static func normalizedPlotDate(for date: Date, nightSpan: ClosedRange<Date>?) -> Date {
        guard let nightSpan else {
            return plotReferenceStart
        }

        let duration = nightSpan.upperBound.timeIntervalSince(nightSpan.lowerBound)
        guard duration > 0 else {
            return plotReferenceStart
        }

        let fraction = date.timeIntervalSince(nightSpan.lowerBound) / duration
        return plotReferenceStart.addingTimeInterval(fraction * plotSpan)
    }

    /// Inverse of `normalizedPlotDate` — the chart's own selection and its
    /// axis labels speak in plot space and have to read back real clock times.
    static func realDate(forNormalized normalized: Date, nightSpan: ClosedRange<Date>?) -> Date? {
        guard let nightSpan else {
            return nil
        }

        let duration = nightSpan.upperBound.timeIntervalSince(nightSpan.lowerBound)
        guard duration > 0 else {
            return nil
        }

        let fraction = normalized.timeIntervalSince(plotReferenceStart) / plotSpan
        return nightSpan.lowerBound.addingTimeInterval(fraction * duration)
    }

    private func normalizedDate(_ date: Date) -> Date {
        Self.normalizedPlotDate(for: date, nightSpan: Self.nightSpan(of: renderSnapshot))
    }

    /// First segment start through last segment end, or nil with no segments.
    static func nightSpan(of snapshot: SleepStageSnapshot) -> ClosedRange<Date>? {
        guard let start = snapshot.segments.map(\.startDate).min(),
              let end = snapshot.segments.map(\.endDate).max(),
              start <= end else {
            return nil
        }
        return start...end
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
        let segments = renderSnapshot.segments
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
        // Flattened, both stops read Core so the connector's color blends into
        // the band in step with its geometry collapsing onto the Core row.
        LinearGradient(
            colors: [
                color(for: isFlattened ? .core : bridge.upperStage).opacity(0.92),
                color(for: isFlattened ? .core : bridge.lowerStage).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var selectedStageSegment: SleepStageSegment? {
        guard isSelectingStage, let selectedStageDate else {
            return nil
        }

        // The scrub reports a plot-space date; segments are matched in real time.
        guard let realDate = Self.realDate(
            forNormalized: selectedStageDate,
            nightSpan: Self.nightSpan(of: renderSnapshot)
        ) else {
            return nil
        }

        return segmentSelection(for: realDate)
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
        let visibleSegments = renderSnapshot.segments.filter { segment in
            segmentRenderStartDate(for: segment) <= date && date <= segmentRenderEndDate(for: segment)
        }

        if let visibleSegment = visibleSegments.min(by: {
            segmentSelectionDistance(from: date, to: $0) < segmentSelectionDistance(from: date, to: $1)
        }) {
            return visibleSegment
        }

        let nearestSegment = renderSnapshot.segments.min {
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

    /// Constant: the night is scaled into it rather than it being fitted to
    /// the night, which is what keeps marks from sliding on a date switch.
    private var chartXDomain: ClosedRange<Date> {
        let padding = Self.plotSpan * Self.plotPaddingFraction
        let lowerBound = Self.plotReferenceStart.addingTimeInterval(-padding)
        let upperBound = Self.plotReferenceStart.addingTimeInterval(Self.plotSpan + padding)
        return lowerBound...upperBound
    }

    private var xAxisValues: [Date] {
        realAxisValues.map { normalizedDate($0) }
    }

    private var realAxisValues: [Date] {
        if let renderAxisMarkIntervals, !renderAxisMarkIntervals.isEmpty {
            return renderAxisMarkIntervals.flatMap { [$0.start, $0.end] }.sorted()
        }
        guard let startDate = renderSnapshot.segments.map(\.startDate).min(),
              let endDate = renderSnapshot.segments.map(\.endDate).max() else {
            return []
        }
        return [startDate, endDate]
    }

    /// The clock time a plot-space tick stands for. The single-span chart's
    /// two ticks sit at fixed fractions, so they read the INCOMING night —
    /// their digits start rolling as the collapse begins, in step with the
    /// card's duration text, rather than waiting for the mid-flight swap. The
    /// naps chart's ticks move with its data, so those stay on the rendered
    /// night to keep each label paired with the nap under it.
    private func axisTimeText(forNormalized normalized: Date) -> String? {
        let labelSnapshot = renderAxisMarkIntervals == nil ? snapshot : renderSnapshot
        guard let date = Self.realDate(
            forNormalized: normalized,
            nightSpan: Self.nightSpan(of: labelSnapshot) ?? Self.nightSpan(of: renderSnapshot)
        ) else {
            return nil
        }

        return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func xAxisLabelAnchor(for value: AxisValue) -> UnitPoint {
        guard let date = value.as(Date.self) else { return .top }
        if date == xAxisValues.first { return .topLeading }
        if date == xAxisValues.last { return .topTrailing }
        // Interior span boundaries anchor away from their own span — a start
        // label extends left into the gap and an end label extends right — so a
        // short nap's pair of labels doesn't pile up inside its narrow span.
        if let renderAxisMarkIntervals {
            if renderAxisMarkIntervals.contains(where: { normalizedDate($0.start) == date }) { return .topTrailing }
            if renderAxisMarkIntervals.contains(where: { normalizedDate($0.end) == date }) { return .topLeading }
        }
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
            Divider()
            restorativeRow
            legend
        }
    }

    private var restorativeRow: some View {
        let restorativeDuration = snapshot.restorativeDuration
        let fraction = totalDuration > 0 ? restorativeDuration / totalDuration : 0

        return HStack(spacing: columnSpacing) {
            Text(String(localized: "sleep.bar.restorative", defaultValue: "Restorative"))
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: stageLabelWidth, alignment: .leading)

            track(fraction: fraction, color: restorativeChartColor, range: restorativeOptimalRange)
                .frame(maxWidth: .infinity)
                .frame(height: trackHeight)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .frame(width: percentColumnWidth, alignment: .trailing)

            Text(BodyValueFormat.durationText(for: restorativeDuration))
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: durationColumnWidth, alignment: .trailing)
        }
    }

    private var header: some View {
        HStack(spacing: columnSpacing) {
            Text("Stage")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: stageLabelWidth, alignment: .leading)
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
            Text(stage.barChartLabel)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: stageLabelWidth, alignment: .leading)

            track(fraction: fraction, color: stage.bodyChartColor, range: stage.optimalPercentageRange)
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

    private func track(fraction: Double, color: Color, range: ClosedRange<Double>) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let bandWidth = max(0, CGFloat(range.upperBound - range.lowerBound) * width)
            let bandOffset = CGFloat(range.lowerBound) * width
            let fillWidth = CGFloat(min(1, max(0, fraction))) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: barHeight)

                Capsule()
                    .fill(color)
                    .frame(width: fillWidth, height: barHeight)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: fraction)

                optimalBand
                    .frame(width: bandWidth, height: trackHeight)
                    .offset(x: bandOffset)
            }
            .frame(height: trackHeight)
        }
    }

    /// Deep + REM combined. Its optimal band is the sum of the Deep and REM
    /// reference ranges (≈ 33–48% of time in bed).
    private var restorativeOptimalRange: ClosedRange<Double> {
        let deep = SleepStage.deep.optimalPercentageRange
        let rem = SleepStage.rem.optimalPercentageRange
        return (deep.lowerBound + rem.lowerBound)...(deep.upperBound + rem.upperBound)
    }

    private let restorativeChartColor = Color(red: 0.45, green: 0.42, blue: 0.95)

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
    private let gutterLabelHeight: CGFloat = 14

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
                .position(x: plotWidth + gutterWidth / 2, y: gutterLabelY(forLineY: lineY, plotHeight: plotHeight))
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
            .position(x: plotWidth + gutterWidth / 2, y: gutterLabelY(forLineY: lineY, plotHeight: plotHeight))
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

                    // Bare day number: the locale-formatted day field appends a
                    // suffix in some languages (e.g. "30日"), which crowds the
                    // 14 columns.
                    Text(Calendar.bodyGregorian.component(.day, from: day).formatted(.number.grouping(.never)))
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

    /// Keeps a gutter time label fully inside the plot: the rasterized layer
    /// clips at its bounds, so a line sitting on the top or bottom edge would
    /// otherwise have its centered label cut in half.
    private func gutterLabelY(forLineY lineY: CGFloat, plotHeight: CGFloat) -> CGFloat {
        guard plotHeight > gutterLabelHeight else {
            return plotHeight / 2
        }

        let inset = gutterLabelHeight / 2
        return min(max(lineY, inset), plotHeight - inset)
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
            return BodyVitalsChartStyle.typicalColor
        case .high:
            return BodyVitalsChartStyle.highColor
        case .low:
            return BodyVitalsChartStyle.lowColor
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Marker geometry and color inputs per dot: when the day picker lands on
    /// another night the dots glide to their new positions and cross-fade color
    /// instead of snapping.
    private struct DotAnimationKey: Equatable {
        let position: Double
        let region: SleepVitalRegion
    }

    private var animationKey: [DotAnimationKey] {
        rows.map { DotAnimationKey(position: $0.markerPosition, region: $0.region) }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    let outlierBand = height * BodyHealthDetailChartLayout.sleepVitalsOutlierBandFraction
                    path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                    path.move(to: CGPoint(x: 0, y: outlierBand))
                    path.addLine(to: CGPoint(x: width, y: outlierBand))
                    path.move(to: CGPoint(x: 0, y: height - outlierBand))
                    path.addLine(to: CGPoint(x: width, y: height - outlierBand))
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
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0),
                value: animationKey
            )
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard !rows.isEmpty else {
            return width / 2
        }

        return width * (CGFloat(index) + 0.5) / CGFloat(rows.count)
    }

    private func yPosition(for row: SleepVitalDisplayRow, height: CGFloat) -> CGFloat {
        height * (1 - displayPosition(for: row.markerPosition))
    }

    /// `markerPosition` splits its 0…1 scale into equal thirds, but the plot
    /// draws High and Low shorter than the typical band — so each third is
    /// remapped onto the band it is actually drawn in before becoming a Y
    /// offset, keeping a dot in the same relative spot within its region.
    private func displayPosition(for markerPosition: Double) -> CGFloat {
        let outlier = BodyHealthDetailChartLayout.sleepVitalsOutlierBandFraction
        let typical = 1 - 2 * outlier
        let position = CGFloat(min(max(markerPosition, 0), 1))

        if position < 1.0 / 3 {
            return position * 3 * outlier
        }

        if position < 2.0 / 3 {
            return outlier + (position - 1.0 / 3) * 3 * typical
        }

        return outlier + typical + (position - 2.0 / 3) * 3 * outlier
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
            .frame(width: 15, height: 15)
            .overlay(
                Circle()
                    .stroke(row.region.dotColor, lineWidth: 4)
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
        // Weighted rather than three equal slices, so each word stays centered
        // on the shorter High/Low bands the plot now draws.
        GeometryReader { proxy in
            let outlierBand = proxy.size.height * BodyHealthDetailChartLayout.sleepVitalsOutlierBandFraction

            VStack(spacing: 0) {
                regionLabel("High", height: outlierBand)
                regionLabel("Typical", height: proxy.size.height - outlierBand * 2)
                regionLabel("Low", height: outlierBand)
            }
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundColor(Color.secondary.opacity(0.62))
    }

    private func regionLabel(_ title: LocalizedStringKey, height: CGFloat) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .center)
    }
}
