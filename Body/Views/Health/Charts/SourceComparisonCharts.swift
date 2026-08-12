//
//  SourceComparisonCharts.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHealthSourceLegendItem: Identifiable {
    let role: BodyHealthSourceRole
    let sourceName: String
    let averageValue: Double?
    let color: Color

    var id: BodyHealthSourceRole { role }
}

struct BodyHealthSourceLegend: View {
    let items: [BodyHealthSourceLegendItem]
    let valueFormatter: (Double) -> String

    private var isMultiSource: Bool {
        items.count > 1
    }

    var body: some View {
        if isMultiSource {
            VStack(alignment: .trailing, spacing: 7) {
                ForEach(items) { item in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 9, height: 9)

                        Text("\(item.sourceName) Avg \(averageText(for: item.averageValue))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
            }
            .frame(maxWidth: 180, alignment: .trailing)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.lastTextBaseline]
            }
        } else if let item = items.first {
            Text("Avg \(averageText(for: item.averageValue))")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func averageText(for value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return valueFormatter(value)
    }
}

struct BodyHealthSourceComparisonLineChart: View {
    let title: String
    let comparison: BodyHealthSourceComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let isSleepDetail: Bool
    let immersive: Bool
    let chartIdentity: String
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let lineSegments: [BodyHealthSourceComparisonLineSegmentMark]
    private let dotEntries: [BodyHealthSourceComparisonLineEntry]
    private let finiteEntries: [BodyHealthSourceComparisonLineEntry]
    private let primaryPointsByDate: [Date: BodyHealthSourceComparisonLineEntry]
    private let secondaryPointsByDate: [Date: BodyHealthSourceComparisonLineEntry]
    private let latestPrimaryDate: Date?
    private let latestSecondaryDate: Date?
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        comparison: BodyHealthSourceComparisonTrend,
        selectedRange: BodyHealthTrendRange,
        primaryColor: Color,
        secondaryColor: Color,
        valueFormatter: @escaping (Double) -> String,
        isSleepDetail: Bool,
        immersive: Bool = false,
        chartIdentity: String,
        floatingCallout: BodyChartFloatingCalloutState? = nil
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.isSleepDetail = isSleepDetail
        self.immersive = immersive
        self.chartIdentity = chartIdentity
        self.floatingCallout = floatingCallout

        let primaryPoints = comparison.primary.series.lineChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.lineChartCalendarPoints(to: selectedRange)
        let primaryEntries = primaryPoints.map {
            BodyHealthSourceComparisonLineEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: $0
            )
        }
        let secondaryEntries = secondaryPoints.map {
            BodyHealthSourceComparisonLineEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: $0
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        self.finiteEntries = allEntries.filter { $0.value?.isFinite == true }
        // Union of every range's dates: off-range dates render as invisible
        // placeholders at their own range's geometry, so a range switch morphs
        // marks in place instead of popping them.
        let otherRangeEntries = BodyHealthTrendRange.allCases
            .filter { $0 != selectedRange }
            .map { Self.lineEntries(comparison: comparison, range: $0) }
        self.lineSegments = Self.unionLineSegments(currentEntries: allEntries, otherRangeEntries: otherRangeEntries)
        self.dotEntries = Self.unionDotEntries(currentEntries: allEntries, otherRangeEntries: otherRangeEntries)
        self.primaryPointsByDate = Dictionary(uniqueKeysWithValues: primaryEntries.compactMap { entry in
            entry.value?.isFinite == true ? (entry.date, entry) : nil
        })
        self.secondaryPointsByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.compactMap { entry in
            entry.value?.isFinite == true ? (entry.date, entry) : nil
        })
        self.latestPrimaryDate = primaryEntries.last { $0.value?.isFinite == true }?.date
        self.latestSecondaryDate = secondaryEntries.last { $0.value?.isFinite == true }?.date
        let domainDates = primaryEntries.map(\.date) + secondaryEntries.map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)
        self.chartYDomain = BodyHealthMetricTrendChart.computeYDomain(
            from: allEntries.compactMap(\.value).filter(\.isFinite),
            chartStyle: .line
        )
    }

    var body: some View {
        Chart {
            // One two-point series per consecutive pair instead of one run per
            // source: a single line whose vertex set changes across a range
            // switch freezes, then pops. Shared pair ids morph in place; the
            // rest fade at opacity 0.
            ForEach(lineSegments) { segment in
                LineMark(
                    x: .value("Date", segment.startDate, unit: .day),
                    y: .value(title, segment.startValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor(for: segment.sourceRole))
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)

                LineMark(
                    x: .value("Date", segment.endDate, unit: .day),
                    y: .value(title, segment.endValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor(for: segment.sourceRole))
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)
            }

            if selectedRange.showsPointMarks {
                ForEach(dotEntries) { entry in
                    if let value = entry.value {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, value)
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: color(for: entry),
                                    isCurrent: isLatestPoint(entry),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                                // Inside the symbol view — Charts does not apply
                                // mark opacity to custom `.symbol {}` content.
                                .opacity(entry.isPlaceholder ? 0 : 1)
                            }
                            // Opacity is only visual: an off-range placeholder
                            // would still be announced.
                            .accessibilityHidden(entry.isPlaceholder)
                        } else {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, value)
                            )
                            .foregroundStyle(color(for: entry))
                            .symbolSize(28)
                            .opacity(entry.isPlaceholder ? 0 : 1)
                            .accessibilityHidden(entry.isPlaceholder)
                        }
                    }
                }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected Date", selectedPoint.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        if floatingCallout == nil {
                            selectionAnnotation(for: selectedPoint)
                        }
                    }

                ForEach(selectedValuesEntries(for: selectedPoint.date)) { entry in
                    if let value = entry.value {
                        PointMark(
                            x: .value("Selected Date", entry.date, unit: .day),
                            y: .value(title, value)
                        )
                        .foregroundStyle(color(for: entry))
                        .symbolSize(82)
                    }
                }
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: chartYDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: selectedRange.axisStrideDayCount)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(selectedRange.axisLabel(for: date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            if !immersive {
                AxisMarks(position: .leading, values: .automatic(desiredCount: BodyHealthDetailChartLayout.yAxisLabelCount)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisTick()
                        .foregroundStyle(Color.secondary.opacity(0.28))
                    AxisValueLabel {
                        if let yValue = value.as(Double.self) {
                            Text(valueFormatter(yValue))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
        .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedPoint?.date) {
            guard let selectedPoint else {
                return AnyView(EmptyView())
            }
            return AnyView(selectionAnnotation(for: selectedPoint))
        }
        .id(chartIdentity)
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        // Keyed on the range ONLY: a broader key would also animate
        // scrub-mark removal.
        .animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)
        .onChange(of: selectedRange) {
            selectedDate = nil
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func selectionAnnotation(for selectedPoint: BodyHealthSourceComparisonLineEntry) -> BodyChartSelectionAnnotation {
        BodyChartSelectionAnnotation(
            eyebrow: nil,
            values: selectedValues(for: selectedPoint.date),
            date: selectedPoint.date,
            dateText: bodyChartSelectionDateText(for: selectedPoint.point)
        )
    }

    private var selectedPoint: BodyHealthSourceComparisonLineEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private func selectedValuesEntries(for date: Date) -> [BodyHealthSourceComparisonLineEntry] {
        [primaryPointsByDate[date], secondaryPointsByDate[date]].compactMap { $0 }
    }

    private func selectedValues(for date: Date) -> [BodyChartSelectionValue] {
        selectedValuesEntries(for: date).compactMap { entry in
            guard let value = entry.value else {
                return nil
            }

            return BodyChartSelectionValue(
                title: entry.sourceName,
                value: chartSelectionText(for: value),
                color: color(for: entry)
            )
        }
    }

    private func chartSelectionText(for value: Double) -> String {
        if isSleepDetail {
            return BodyValueFormat.sleepDurationText(for: value * 60 * 60)
        }

        return valueFormatter(value)
    }

    private func isLatestPoint(_ entry: BodyHealthSourceComparisonLineEntry) -> Bool {
        entry.sourceRole == .primary
            ? entry.date == latestPrimaryDate
            : entry.date == latestSecondaryDate
    }

    private func color(for entry: BodyHealthSourceComparisonLineEntry) -> Color {
        color(for: entry.sourceRole)
    }

    private func color(for role: BodyHealthSourceRole) -> Color {
        role == .primary ? primaryColor : secondaryColor
    }

    private func lineStrokeColor(for role: BodyHealthSourceRole) -> Color {
        selectedRange.usesMetricColorLineStroke ? color(for: role) : color(for: role).opacity(0.72)
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private var chartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelecting) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedDate = nil
            }
    }

    /// Both sources' entries at `range`'s own compressed line points, used to
    /// seed placeholder geometry for off-range dates.
    static func lineEntries(
        comparison: BodyHealthSourceComparisonTrend,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [BodyHealthSourceComparisonLineEntry] {
        let primaryEntries = comparison.primary.series
            .lineChartCalendarPoints(to: range, calendar: calendar, date: date)
            .map {
                BodyHealthSourceComparisonLineEntry(
                    sourceName: comparison.primary.sourceName,
                    sourceRole: .primary,
                    point: $0
                )
            }
        let secondaryEntries = comparison.secondary.series
            .lineChartCalendarPoints(to: range, calendar: calendar, date: date)
            .map {
                BodyHealthSourceComparisonLineEntry(
                    sourceName: comparison.secondary.sourceName,
                    sourceRole: .secondary,
                    point: $0
                )
            }
        return primaryEntries + secondaryEntries
    }

    /// One segment per consecutive pair of a source's finite entries.
    /// Placeholder segments collapse onto their own start point.
    static func lineSegments(
        from entries: [BodyHealthSourceComparisonLineEntry],
        isPlaceholder: Bool
    ) -> [BodyHealthSourceComparisonLineSegmentMark] {
        let entriesByRole = Dictionary(
            grouping: entries.filter { $0.value?.isFinite == true },
            by: \.sourceRole
        )
        return entriesByRole.keys.sorted { $0.rawValue < $1.rawValue }.flatMap { role -> [BodyHealthSourceComparisonLineSegmentMark] in
            let sorted = (entriesByRole[role] ?? []).sorted { $0.date < $1.date }
            return zip(sorted, sorted.dropFirst()).compactMap { start, end in
                guard let startValue = start.value, let endValue = end.value else {
                    return nil
                }

                return BodyHealthSourceComparisonLineSegmentMark(
                    sourceRole: role,
                    startDate: start.date,
                    startValue: startValue,
                    endDate: isPlaceholder ? start.date : end.date,
                    endValue: isPlaceholder ? startValue : endValue,
                    isPlaceholder: isPlaceholder
                )
            }
        }
    }

    /// The current range's per-source pairs, plus every other range's pairs
    /// whose id has no current counterpart as invisible zero-length
    /// placeholders — a segment appearing there on another range grows out of
    /// its own start point instead of popping in.
    static func unionLineSegments(
        currentEntries: [BodyHealthSourceComparisonLineEntry],
        otherRangeEntries: [[BodyHealthSourceComparisonLineEntry]]
    ) -> [BodyHealthSourceComparisonLineSegmentMark] {
        var segments = lineSegments(from: currentEntries, isPlaceholder: false)
        var claimedIDs = Set(segments.map(\.id))
        for entries in otherRangeEntries {
            for segment in lineSegments(from: entries, isPlaceholder: true)
            where !claimedIDs.contains(segment.id) {
                claimedIDs.insert(segment.id)
                segments.append(segment)
            }
        }
        return segments
    }

    /// The current range's entries verbatim, plus every other range's finite
    /// entries whose role-date id has no current counterpart as invisible
    /// placeholders at their own value. A current entry with no reading draws
    /// no dot, so it yields its id instead of suppressing that placeholder.
    static func unionDotEntries(
        currentEntries: [BodyHealthSourceComparisonLineEntry],
        otherRangeEntries: [[BodyHealthSourceComparisonLineEntry]]
    ) -> [BodyHealthSourceComparisonLineEntry] {
        bodyUnionMorphEntries(
            current: currentEntries,
            otherRanges: otherRangeEntries,
            isDrawn: { $0.value?.isFinite == true },
            placeholder: { entry in
                var placeholder = entry
                placeholder.isPlaceholder = true
                return placeholder
            }
        )
    }
}

struct BodyHealthSourceComparisonLineEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendCalendarPoint
    var isPlaceholder: Bool = false

    var id: String {
        "\(sourceRole.rawValue)-\(point.date.timeIntervalSinceReferenceDate)"
    }

    var date: Date {
        point.date
    }

    var value: Double? {
        point.value
    }
}

/// One straight stretch of a source's comparison line (or its invisible
/// zero-length placeholder), keyed by source role + pair start date so the
/// mark keeps its identity across range switches — see
/// `BodyHealthSourceComparisonLineChart.unionLineSegments`.
struct BodyHealthSourceComparisonLineSegmentMark: Identifiable {
    let sourceRole: BodyHealthSourceRole
    let startDate: Date
    let startValue: Double
    let endDate: Date
    let endValue: Double
    var isPlaceholder: Bool = false

    var id: String {
        "\(sourceRole.rawValue)-seg-\(startDate.timeIntervalSinceReferenceDate)"
    }
}

struct BodyHealthSourceComparisonBarChart: View {
    let title: String
    let comparison: BodyHealthSourceComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let immersive: Bool
    let chartIdentity: String
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let entries: [BodyHealthSourceComparisonBarEntry]
    private let finiteEntries: [BodyHealthSourceComparisonBarEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        comparison: BodyHealthSourceComparisonTrend,
        selectedRange: BodyHealthTrendRange,
        primaryColor: Color,
        secondaryColor: Color,
        valueFormatter: @escaping (Double) -> String,
        immersive: Bool = false,
        chartIdentity: String,
        floatingCallout: BodyChartFloatingCalloutState? = nil
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.immersive = immersive
        self.chartIdentity = chartIdentity
        self.floatingCallout = floatingCallout

        let primaryPoints = comparison.primary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let dateOffset = selectedRange.sourceComparisonChartDateOffset
        // For Week, `point.date` is the day start (the midnight gridline), so the raw
        // ±offset pair straddles it and the primary bar lands in the previous day's
        // column. Shift the Week pair fully into the day's own column. Aggregated ranges
        // keep `point.date` (the bucket end, which never aligns with the weekly/monthly
        // gridlines) and read fine as-is.
        let pairShift: TimeInterval = selectedRange.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift - dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift + dateOffset)
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        // Union of every range's buckets: off-range bucket dates render as
        // invisible placeholders at their own range's aggregated geometry and
        // pair offsets, so a range switch morphs bars instead of popping them.
        // Scrubbing and domains stay on the current range's entries.
        self.entries = Self.unionBarEntries(
            currentEntries: allEntries,
            otherRangeEntries: BodyHealthTrendRange.allCases
                .filter { $0 != selectedRange }
                .map { Self.barEntries(comparison: comparison, range: $0) }
        )
        self.finiteEntries = allEntries.filter { $0.value?.isFinite == true }

        let domainDates = allEntries.map(\.chartDate)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive, immersivePairedBars: true, pairedBarComparison: true)
        self.chartYDomain = BodyHealthMetricTrendChart.computeYDomain(
            from: finiteEntries.compactMap(\.value),
            chartStyle: .bar
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.sourceComparisonChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(entries) { entry in
                    if let value = entry.value {
                        BarMark(
                            x: .value("Date", entry.chartDate),
                            y: .value(title, value),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(color(for: entry).gradient)
                        .cornerRadius(4)
                        .opacity(entry.isPlaceholder ? 0 : 1)
                        .accessibilityHidden(entry.isPlaceholder)
                    }
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            if floatingCallout == nil {
                                selectionAnnotation(for: selectedPoint)
                            }
                        }
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: chartYDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: selectedRange.axisStrideDayCount)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisTick()
                        .foregroundStyle(Color.secondary.opacity(0.28))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(selectedRange.axisLabel(for: date))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                if !immersive {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: BodyHealthDetailChartLayout.yAxisLabelCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel {
                            if let yValue = value.as(Double.self) {
                                Text(valueFormatter(yValue))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .simultaneousGesture(chartPressGesture)
            // Paired bars select an exact offset timestamp, not a `.day`-unit mark.
            .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedPoint?.chartDate, centersOnDayInterval: false) {
                guard let selectedPoint else {
                    return AnyView(EmptyView())
                }
                return AnyView(selectionAnnotation(for: selectedPoint))
            }
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            // Keyed on the range ONLY: a broader key would also animate
            // scrub-mark removal.
            .animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)
            .onChange(of: selectedRange) {
                selectedDate = nil
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private func selectionAnnotation(for selectedPoint: BodyHealthSourceComparisonBarEntry) -> BodyChartSelectionAnnotation {
        BodyChartSelectionAnnotation(
            eyebrow: selectedRange.sourceComparisonChartAggregationDayCount > 1 ? String(localized: "AVG") : String(localized: "TOTAL"),
            values: selectedValues(for: selectedPoint),
            date: selectedPoint.date,
            dateText: bodyChartSelectionDateText(for: selectedPoint.point)
        )
    }

    private var selectedPoint: BodyHealthSourceComparisonBarEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.chartDate.timeIntervalSince(selectedDate)) < abs(second.chartDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectedValues(for selectedPoint: BodyHealthSourceComparisonBarEntry) -> [BodyChartSelectionValue] {
        entries
            // Placeholders excluded: another range's bucket can share this
            // date, and its value must never reach the callout.
            .filter { !$0.isPlaceholder && $0.date == selectedPoint.date && $0.value?.isFinite == true }
            .sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }
            .compactMap { entry -> BodyChartSelectionValue? in
                guard let value = entry.value else {
                    return nil
                }

                return BodyChartSelectionValue(
                    title: entry.sourceName,
                    value: valueFormatter(value),
                    color: color(for: entry)
                )
            }
    }

    private func color(for entry: BodyHealthSourceComparisonBarEntry) -> Color {
        entry.sourceRole == .primary ? primaryColor : secondaryColor
    }

    private var chartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelecting) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedDate = nil
            }
    }

    /// Both sources' entries at `range`'s own doubled-bucket aggregation and
    /// per-source pair offsets (mirroring the init's current-range math), used
    /// to seed placeholder geometry for off-range bucket dates.
    static func barEntries(
        comparison: BodyHealthSourceComparisonTrend,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [BodyHealthSourceComparisonBarEntry] {
        let primaryPoints = comparison.primary.series
            .sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: date)
        let secondaryPoints = comparison.secondary.series
            .sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: date)
        let dateOffset = range.sourceComparisonChartDateOffset
        let pairShift: TimeInterval = range.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift - dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift + dateOffset)
            )
        }
        return primaryEntries + secondaryEntries
    }

    /// The current range's entries verbatim, plus every other range's finite
    /// entries whose role-date id has no current counterpart as invisible
    /// placeholders at their own range's geometry. A current entry with no
    /// reading draws no bar, so it yields its id to a valued off-range bucket.
    static func unionBarEntries(
        currentEntries: [BodyHealthSourceComparisonBarEntry],
        otherRangeEntries: [[BodyHealthSourceComparisonBarEntry]]
    ) -> [BodyHealthSourceComparisonBarEntry] {
        bodyUnionMorphEntries(
            current: currentEntries,
            otherRanges: otherRangeEntries,
            isDrawn: { $0.value?.isFinite == true },
            placeholder: { entry in
                var placeholder = entry
                placeholder.isPlaceholder = true
                return placeholder
            }
        )
    }
}

struct BodyHealthSourceComparisonBarEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendCalendarPoint
    let chartDate: Date
    var isPlaceholder: Bool = false

    var id: String {
        "\(sourceRole.rawValue)-\(point.date.timeIntervalSinceReferenceDate)"
    }

    var date: Date {
        point.date
    }

    var value: Double? {
        point.value
    }
}

struct BodyHealthSourceComparisonRangeChart: View {
    let title: String
    let comparison: BodyHealthSourceRangeComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let immersive: Bool
    let chartIdentity: String
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let entries: [BodyHealthSourceComparisonRangeEntry]
    private let finiteEntries: [BodyHealthSourceComparisonRangeEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        comparison: BodyHealthSourceRangeComparisonTrend,
        selectedRange: BodyHealthTrendRange,
        primaryColor: Color,
        secondaryColor: Color,
        valueFormatter: @escaping (Double) -> String,
        yDomain: (([Double]) -> ClosedRange<Double>)? = nil,
        immersive: Bool = false,
        chartIdentity: String,
        floatingCallout: BodyChartFloatingCalloutState? = nil
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.immersive = immersive
        self.chartIdentity = chartIdentity
        self.floatingCallout = floatingCallout

        let primaryPoints = comparison.primary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let dateOffset = selectedRange.sourceComparisonChartDateOffset
        // For Week, `point.date` is the day start (the midnight gridline), so the raw
        // ±offset pair straddles it and the primary bar lands in the previous day's
        // column. Shift the Week pair fully into the day's own column. Aggregated ranges
        // keep `point.date` (the bucket end, which never aligns with the weekly/monthly
        // gridlines) and read fine as-is.
        let pairShift: TimeInterval = selectedRange.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift - dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift + dateOffset)
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        // Union of every range's buckets: off-range bucket dates render as
        // invisible placeholders at their own range's aggregated geometry and
        // pair offsets, so a range switch morphs bars instead of popping them.
        // Scrubbing and domains stay on the current range's entries.
        self.entries = Self.unionRangeEntries(
            currentEntries: allEntries,
            otherRangeEntries: BodyHealthTrendRange.allCases
                .filter { $0 != selectedRange }
                .map { Self.rangeEntries(comparison: comparison, range: $0) }
        )
        self.finiteEntries = allEntries.filter(\.hasValue)

        let domainDates = allEntries.map(\.chartDate)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive, immersivePairedBars: true)
        let domainValues = allEntries.flatMap { entry -> [Double] in
            guard let low = entry.lowValue, let high = entry.highValue else {
                return []
            }

            return [low, high]
        }
        self.chartYDomain = yDomain?(domainValues) ?? Self.computeYDomain(from: domainValues)
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.sourceComparisonRangeChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(entries) { entry in
                    if let lowValue = entry.lowValue, let highValue = entry.highValue {
                        // Both forms exist for every entry and only opacity
                        // picks between them: a low == high entry needs the dot
                        // and every other needs the bar, and letting a range
                        // switch change WHICH mark the entry has
                        // removes/inserts it, which Swift Charts pops. The
                        // zero-height bar under a dot stays at opacity 0.
                        PointMark(
                            x: .value("Date", entry.chartDate),
                            y: .value(title, lowValue)
                        )
                        .symbolSize(bodyRangeChartPointSymbolSize(forBarWidth: chartBarWidth))
                        .foregroundStyle(color(for: entry).gradient)
                        .opacity(!entry.isPlaceholder && lowValue == highValue ? 1 : 0)
                        // Both forms exist for every entry, so the hidden twin
                        // and the placeholders must stay out of VoiceOver.
                        .accessibilityHidden(entry.isPlaceholder || lowValue != highValue)

                        BarMark(
                            x: .value("Date", entry.chartDate),
                            yStart: .value("Low \(title)", lowValue),
                            yEnd: .value("High \(title)", highValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(color(for: entry).gradient)
                        .cornerRadius(chartBarWidth / 2)
                        .opacity(!entry.isPlaceholder && lowValue != highValue ? 1 : 0)
                        .accessibilityHidden(entry.isPlaceholder || lowValue == highValue)
                    }
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            if floatingCallout == nil {
                                selectionAnnotation(for: selectedPoint)
                            }
                        }
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: chartYDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: selectedRange.axisStrideDayCount)) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisTick()
                        .foregroundStyle(Color.secondary.opacity(0.28))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(selectedRange.axisLabel(for: date))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                if !immersive {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: BodyHealthDetailChartLayout.yAxisLabelCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel {
                            if let yValue = value.as(Double.self) {
                                Text(valueFormatter(yValue))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .simultaneousGesture(chartPressGesture)
            // Paired bars select an exact offset timestamp, not a `.day`-unit mark.
            .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedPoint?.chartDate, centersOnDayInterval: false) {
                guard let selectedPoint else {
                    return AnyView(EmptyView())
                }
                return AnyView(selectionAnnotation(for: selectedPoint))
            }
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            // Keyed on the range alone so scrub-driven mark changes stay
            // un-animated; the inner keyed animation still runs under the
            // transaction override below.
            .animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)
            .onChange(of: selectedRange) {
                selectedDate = nil
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private func selectionAnnotation(for selectedPoint: BodyHealthSourceComparisonRangeEntry) -> BodyChartSelectionAnnotation {
        BodyChartSelectionAnnotation(
            eyebrow: String(localized: "RANGE"),
            values: selectedValues(for: selectedPoint),
            date: selectedPoint.date,
            dateText: bodyChartSelectionDateText(for: selectedPoint.point)
        )
    }

    private var selectedPoint: BodyHealthSourceComparisonRangeEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.chartDate.timeIntervalSince(selectedDate)) < abs(second.chartDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectedValues(for selectedPoint: BodyHealthSourceComparisonRangeEntry) -> [BodyChartSelectionValue] {
        entries
            // Placeholders excluded: another range's bucket can share this
            // date, and its values must never reach the callout.
            .filter { !$0.isPlaceholder && $0.date == selectedPoint.date && $0.hasValue }
            .sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }
            .compactMap { entry -> BodyChartSelectionValue? in
                guard let lowValue = entry.lowValue,
                      let highValue = entry.highValue else {
                    return nil
                }

                return BodyChartSelectionValue(
                    title: entry.sourceName,
                    value: "\(valueFormatter(lowValue))-\(valueFormatter(highValue))",
                    color: color(for: entry)
                )
            }
    }

    private func color(for entry: BodyHealthSourceComparisonRangeEntry) -> Color {
        entry.sourceRole == .primary ? primaryColor : secondaryColor
    }

    private var chartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelecting) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedDate = nil
            }
    }

    private static func computeYDomain(from values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let maximum = finiteValues.max() else {
            return 0...200
        }

        let upper = max(ceil((maximum + max(maximum * 0.12, 10)) / 10) * 10, 120)
        return 0...upper
    }

    /// One range's paired entries, carrying that range's own aggregation and
    /// pair offsets so a placeholder sits exactly where the mark would sit if
    /// the range were selected.
    static func rangeEntries(
        comparison: BodyHealthSourceRangeComparisonTrend,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [BodyHealthSourceComparisonRangeEntry] {
        let primaryPoints = comparison.primary.series
            .sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: date)
        let secondaryPoints = comparison.secondary.series
            .sourceComparisonChartCalendarPoints(to: range, calendar: calendar, date: date)
        let dateOffset = range.sourceComparisonChartDateOffset
        let pairShift: TimeInterval = range.sourceComparisonChartAggregationDayCount == 1 ? dateOffset * 2 : 0
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift - dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(pairShift + dateOffset)
            )
        }
        return primaryEntries + secondaryEntries
    }

    /// The current range's entries verbatim, plus every other range's valued
    /// entries whose role-date id has no current counterpart as invisible
    /// placeholders at their own range's geometry. A current entry with no
    /// reading draws neither bar nor dot, so it yields its id to a valued
    /// off-range bucket instead of suppressing it.
    static func unionRangeEntries(
        currentEntries: [BodyHealthSourceComparisonRangeEntry],
        otherRangeEntries: [[BodyHealthSourceComparisonRangeEntry]]
    ) -> [BodyHealthSourceComparisonRangeEntry] {
        bodyUnionMorphEntries(
            current: currentEntries,
            otherRanges: otherRangeEntries,
            isDrawn: \.hasValue,
            placeholder: { entry in
                var placeholder = entry
                placeholder.isPlaceholder = true
                return placeholder
            }
        )
    }
}

struct BodyHealthSourceComparisonRangeEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendRangeCalendarPoint
    let chartDate: Date
    /// Off-range bucket rendered invisibly so a range switch morphs instead of
    /// inserting/removing marks — see `unionRangeEntries`.
    var isPlaceholder: Bool = false

    var id: String {
        "\(sourceRole.rawValue)-\(point.date.timeIntervalSinceReferenceDate)"
    }

    var date: Date {
        point.date
    }

    var lowValue: Double? {
        point.lowValue
    }

    var highValue: Double? {
        point.highValue
    }

    var hasValue: Bool {
        point.hasValue
    }
}
