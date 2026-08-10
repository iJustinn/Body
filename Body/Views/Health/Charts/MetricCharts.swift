//
//  MetricCharts.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHealthMetricTrendChart: View {
    let title: String
    let chartStyle: BodyHealthMetricChartStyle
    let symbolColor: Color
    let selectedRange: BodyHealthTrendRange
    let valueFormatter: (Double) -> String
    let highlightedRange: BodyHealthMetricTrendHighlightedRange?
    let highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)?
    /// A live "current" value dotted at 80% opacity in the line color under the
    /// plotted point at `date` (Readiness: today's drained score under the
    /// frozen morning point). While no point is scrubbed, the highlighted
    /// status band follows this value instead of the latest plotted point.
    let currentValuePoint: (date: Date, value: Double)?
    let activeHighlightedValue: Binding<Double?>?
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?
    let isSleepDetail: Bool
    let baselineValue: Double?
    let baselineDeviationFormatter: ((Double) -> String)?
    let chartIdentity: String
    /// When true the chart blends into the sleep hero's gradient: the Y axis is
    /// hidden (Watch-style, label-free) while the X day labels stay. Default
    /// `false` keeps every other caller's chart unchanged.
    let immersive: Bool

    private let visibleCalendarPoints: [HealthTrendCalendarPoint]
    private let visibleFinitePoints: [HealthTrendCalendarPoint]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestVisibleCalendarDate: Date?
    private let placeholderBarYValue: Double

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        chartStyle: BodyHealthMetricChartStyle,
        symbolColor: Color,
        selectedRange: BodyHealthTrendRange,
        series: HealthTrendSeries,
        valueFormatter: @escaping (Double) -> String,
        highlightedRange: BodyHealthMetricTrendHighlightedRange? = nil,
        highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)? = nil,
        currentValuePoint: (date: Date, value: Double)? = nil,
        activeHighlightedValue: Binding<Double?>? = nil,
        floatingCallout: BodyChartFloatingCalloutState? = nil,
        isSleepDetail: Bool,
        baselineValue: Double? = nil,
        baselineDeviationFormatter: ((Double) -> String)? = nil,
        immersive: Bool = false,
        chartIdentity: String
    ) {
        self.title = title
        self.chartStyle = chartStyle
        self.symbolColor = symbolColor
        self.selectedRange = selectedRange
        self.valueFormatter = valueFormatter
        self.highlightedRange = highlightedRange
        self.highlightedRangeResolver = highlightedRangeResolver
        self.currentValuePoint = currentValuePoint
        self.activeHighlightedValue = activeHighlightedValue
        self.floatingCallout = floatingCallout
        self.isSleepDetail = isSleepDetail
        self.baselineValue = baselineValue
        self.baselineDeviationFormatter = baselineDeviationFormatter
        self.immersive = immersive
        self.chartIdentity = chartIdentity

        let calendarPoints: [HealthTrendCalendarPoint]
        switch chartStyle {
        case .line:
            calendarPoints = series.lineChartCalendarPoints(to: selectedRange)
        case .bar:
            calendarPoints = series.chartCalendarPoints(to: selectedRange)
        }
        self.visibleCalendarPoints = calendarPoints
        self.visibleFinitePoints = calendarPoints.filter { $0.value?.isFinite == true }

        let aggregatedValues = calendarPoints.compactMap(\.value).filter(\.isFinite)
        let fallbackValues = series.limited(to: selectedRange).points.map(\.value).filter(\.isFinite)
        let highlightedRangeValues = highlightedRange?.domainValues ?? []
        let baselineDomainValues = baselineValue.map { [$0] } ?? []
        let currentValueDomainValues = currentValuePoint.map { [$0.value] } ?? []
        let domainValues = (aggregatedValues.isEmpty ? fallbackValues : aggregatedValues)
            + highlightedRangeValues
            + baselineDomainValues
            + currentValueDomainValues
        let yDomain = Self.computeYDomain(from: domainValues, chartStyle: chartStyle)
        self.chartYDomain = yDomain

        let domainDates = series.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)

        self.latestVisibleCalendarDate = calendarPoints.last { $0.value?.isFinite == true }?.date

        let span = yDomain.upperBound - yDomain.lowerBound
        self.placeholderBarYValue = yDomain.lowerBound + max(span * 0.025, 0.025)
    }

    private var activeHighlightedRange: BodyHealthMetricTrendHighlightedRange? {
        guard let highlightedRangeResolver, let activeHighlightSourceValue else {
            return highlightedRange
        }

        return highlightedRangeResolver(activeHighlightSourceValue) ?? highlightedRange
    }

    // Idle (no scrub, no current-value dot) reports nil so the band falls back
    // to the caller's `highlightedRange`, built from the live summary value the
    // hero displays. It must NOT fall back to the last plotted point: that can
    // disagree with the live score (the plotted point is the frozen morning
    // value) and briefly showed the wrong band as "Current".
    private var activeHighlightSourceValue: Double? {
        selectedTrendPoint?.value ?? currentValuePoint?.value
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.chartBarWidth(forAvailableWidth: proxy.size.width)
            let displayedHighlightedRange = activeHighlightedRange

            Chart {
                if chartStyle == .bar, let selectedTrendPoint {
                    RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                if let baselineValue {
                    RuleMark(y: .value("Baseline", baselineValue))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [4, 4]))
                }

                ForEach(visibleCalendarPoints) { point in
                    if let value = point.value {
                        switch chartStyle {
                        case .line:
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(title, value)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(lineChartStrokeColor)
                            .lineStyle(StrokeStyle(lineWidth: lineChartStrokeWidth, lineCap: .round, lineJoin: .round))

                            if selectedRange.showsPointMarks {
                                if selectedRange.usesPreviewLineChartStyle {
                                    PointMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value(title, value)
                                    )
                                    .symbol {
                                        BodyLineChartPreviewPointSymbol(
                                            tintColor: symbolColor,
                                            isCurrent: isLatestVisiblePoint(point),
                                            pointDiameter: selectedRange.linePointDiameter,
                                            currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                        )
                                    }
                                } else {
                                    PointMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value(title, value)
                                    )
                                    .foregroundStyle(symbolColor)
                                    .symbolSize(28)
                                }
                            }
                        case .bar:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(title, value),
                                width: .fixed(chartBarWidth)
                            )
                            .foregroundStyle(symbolColor.gradient)
                            .cornerRadius(4)
                        }
                    } else if chartStyle == .bar {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(title, placeholderBarYValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.14))
                        .cornerRadius(4)
                    }
                }

                // Hidden while a scrub callout is up: the band follows the
                // scrubbed point then, and the dot would clutter the rule line.
                if chartStyle == .line, let currentValuePoint, selectedTrendPoint == nil {
                    PointMark(
                        x: .value("Date", currentValuePoint.date, unit: .day),
                        y: .value(title, currentValuePoint.value)
                    )
                    .symbol {
                        Circle()
                            .fill(symbolColor.opacity(0.8))
                            .frame(
                                width: selectedRange.lineCurrentPointDiameter,
                                height: selectedRange.lineCurrentPointDiameter
                            )
                    }
                }

                if let selectedTrendPoint, let selectedTrendValue = selectedTrendPoint.value {
                    RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                        .foregroundStyle(chartStyle == .bar ? Color.clear : Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            if floatingCallout == nil {
                                selectionAnnotation(for: selectedTrendPoint, value: selectedTrendValue)
                            }
                        }

                    if chartStyle == .line {
                        PointMark(
                            x: .value("Selected Date", selectedTrendPoint.date, unit: .day),
                            y: .value(title, selectedTrendValue)
                        )
                        .foregroundStyle(symbolColor)
                        .symbolSize(82)
                    }
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: chartYDomain)
            .chartBackground { chartProxy in
                GeometryReader { geo in
                    if let highlightedRange = displayedHighlightedRange,
                       let plotFrame = chartProxy.plotFrame {
                        let plotRect = geo[plotFrame]
                        let upperY = (chartProxy.position(forY: highlightedRange.upperPlotBound(in: chartYDomain)) ?? 0) + plotRect.minY
                        let lowerY = (chartProxy.position(forY: highlightedRange.lowerPlotBound(in: chartYDomain)) ?? 0) + plotRect.minY
                        let bandHeight = max(lowerY - upperY, 0)
                        let stripeHeightPx: CGFloat = max(plotRect.height * 0.006, 1.5)

                        Rectangle()
                            .fill(highlightedRange.color.opacity(0.12))
                            .frame(width: plotRect.width, height: bandHeight)
                            .offset(x: plotRect.minX, y: upperY)

                        Rectangle()
                            .fill(highlightedRange.color.opacity(0.72))
                            .frame(width: plotRect.width, height: stripeHeightPx)
                            .offset(x: plotRect.minX, y: upperY)

                        Rectangle()
                            .fill(highlightedRange.color.opacity(0.72))
                            .frame(width: plotRect.width, height: stripeHeightPx)
                            .offset(x: plotRect.minX, y: lowerY - stripeHeightPx)
                    }
                }
                // Band easing lives here, scoped to the background, NOT on the Chart:
                // a chart-wide keyed transaction would also animate mark removal, so the
                // current-value dot lingered ~0.55s after a scrub callout appeared.
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0),
                    value: highlightedRangeAnimationKey
                )
            }
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
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                syncActiveHighlightedValue()
            }
            .onChange(of: activeHighlightSourceValue) { _, _ in
                syncActiveHighlightedValue()
            }
            .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedTrendPoint?.date) {
                guard let point = selectedTrendPoint, let value = point.value else {
                    return AnyView(EmptyView())
                }
                return AnyView(selectionAnnotation(for: point, value: value))
            }
        }
    }

    private func selectionAnnotation(for selectedTrendPoint: HealthTrendCalendarPoint, value: Double) -> BodyChartSelectionAnnotation {
        BodyChartSelectionAnnotation(
            eyebrow: chartStyle == .bar ? barSelectionEyebrow : nil,
            values: selectionValues(for: value),
            date: selectedTrendPoint.date,
            dateText: bodyChartSelectionDateText(for: selectedTrendPoint)
        )
    }

    private var selectedTrendPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return visibleFinitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private var highlightedRangeAnimationKey: String {
        guard let range = activeHighlightedRange else { return "none" }
        let lower = range.lowerBound.map { String(format: "%.4f", $0) } ?? "nil"
        let upper = range.upperBound.map { String(format: "%.4f", $0) } ?? "nil"
        return "\(range.title)|\(lower)|\(upper)"
    }

    private func isLatestVisiblePoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == latestVisibleCalendarDate
    }

    private var lineChartStrokeColor: Color {
        selectedRange.usesMetricColorLineStroke ? symbolColor : BodyLineChartPreviewStyle.lineColor
    }

    private var lineChartStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private var barSelectionEyebrow: String {
        selectedRange.chartAggregationDayCount > 1 ? String(localized: "AVG") : String(localized: "TOTAL")
    }

    private func chartSelectionText(for value: Double) -> String {
        if isSleepDetail {
            return BodyValueFormat.sleepDurationText(for: value * 60 * 60)
        }

        return valueFormatter(value)
    }

    private func selectionValues(for value: Double) -> [BodyChartSelectionValue] {
        let primary = BodyChartSelectionValue(
            title: nil,
            value: chartSelectionText(for: value),
            color: symbolColor
        )

        guard let baselineValue, let baselineDeviationFormatter else {
            return [primary]
        }

        let deviation = value - baselineValue
        return [
            primary,
            BodyChartSelectionValue(
                title: String(localized: "Baseline"),
                value: baselineDeviationFormatter(deviation),
                color: Color.secondary.opacity(0.55)
            )
        ]
    }

    private func syncActiveHighlightedValue() {
        activeHighlightedValue?.wrappedValue = activeHighlightSourceValue
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

    static func computeYDomain(
        from values: [Double],
        chartStyle: BodyHealthMetricChartStyle
    ) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        if chartStyle == .bar {
            let padding = max(maximum * 0.12, 1)
            return 0...(maximum + padding)
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.12, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }
}



struct BodyHealthMetricDayContextInterval: Identifiable {
    enum Kind {
        case sleep
        case workout
    }

    let kind: Kind
    let startDate: Date
    let endDate: Date
    let title: String
    let symbolName: String
    let color: Color

    var id: String {
        "\(kind)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)-\(title)"
    }

    var midpointDate: Date {
        startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2)
    }
}

enum BodyHealthMetricDayContextBand {
    static let topStripeHeightRatio = 0.006

    static func topStripeLowerBound(for yDomain: ClosedRange<Double>) -> Double {
        let span = yDomain.upperBound - yDomain.lowerBound
        guard span.isFinite, span > 0 else {
            return yDomain.upperBound
        }

        return yDomain.upperBound - span * topStripeHeightRatio
    }
}

extension HealthTrendSeries {
    func hourlyAverage(on day: Date) -> Double? {
        let values = hourlyAverageBuckets(on: day).map(\.averageValue).filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct BodyHealthMetricDayChart: View {
    let day: Date
    let title: String
    let color: Color
    let secondaryColor: Color
    let primarySourceName: String
    let secondarySourceName: String
    let valueFormatter: (Double) -> String
    let contextIntervals: [BodyHealthMetricDayContextInterval]
    let aggregationLabel: String
    let includesSampleBreakdown: Bool

    private let hourlyBuckets: [HealthTrendHourlyBucket]
    private let secondaryHourlyBuckets: [HealthTrendHourlyBucket]
    private let rangeEntries: [BodyHealthMetricDayRangeEntry]
    private let entries: [BodyHealthMetricDayChartEntry]
    private let pointMarkEntries: [BodyHealthMetricDayChartEntry]
    private let finiteEntries: [BodyHealthMetricDayChartEntry]
    private let primaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let secondaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestBucketDate: Date?
    private let latestSecondaryBucketDate: Date?

    private static let pointDiameter: CGFloat = 8
    private static let currentPointDiameter: CGFloat = 10
    private static let segmentGapThreshold: TimeInterval = 4 * 60 * 60

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    init(
        series: HealthTrendSeries,
        secondarySeries: HealthTrendSeries = .empty,
        day: Date,
        title: String,
        color: Color,
        secondaryColor: Color = Color(red: 0.58, green: 0.36, blue: 0.98),
        primarySourceName: String = String(localized: "Primary"),
        secondarySourceName: String = String(localized: "Secondary"),
        valueFormatter: @escaping (Double) -> String,
        contextIntervals: [BodyHealthMetricDayContextInterval] = [],
        aggregationLabel: String = String(localized: "HOURLY AVG"),
        includesSampleBreakdown: Bool = true,
        collapsesUnchangedPoints: Bool = false,
        showsHourlyRangeBars: Bool = false
    ) {
        self.day = day
        self.title = title
        self.color = color
        self.secondaryColor = secondaryColor
        self.primarySourceName = primarySourceName
        self.secondarySourceName = secondarySourceName
        self.valueFormatter = valueFormatter
        self.contextIntervals = contextIntervals
        self.aggregationLabel = aggregationLabel
        self.includesSampleBreakdown = includesSampleBreakdown

        let buckets = series.hourlyAverageBuckets(on: day)
        let secondaryBuckets = secondarySeries.hourlyAverageBuckets(on: day)
        self.hourlyBuckets = buckets
        self.secondaryHourlyBuckets = secondaryBuckets
        // Primary-source bars only, matching the Week/Month/6M/Year range chart:
        // the compared source contributes its line, not a second set of bars.
        let rangeEntries = showsHourlyRangeBars ? Self.makeRangeEntries(from: buckets) : []
        self.rangeEntries = rangeEntries
        self.latestBucketDate = buckets.last?.plotDate
        self.latestSecondaryBucketDate = secondaryBuckets.last?.plotDate
        let primaryEntries = Self.makeEntries(
            from: buckets,
            sourceName: primarySourceName,
            sourceRole: .primary
        )
        let secondaryEntries = Self.makeEntries(
            from: secondaryBuckets,
            sourceName: secondarySourceName,
            sourceRole: .secondary
        )
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.pointMarkEntries = collapsesUnchangedPoints
            ? Self.collapsingUnchangedRunPoints(allEntries)
            : allEntries
        self.finiteEntries = allEntries.filter { $0.averageValue.isFinite }
        self.primaryEntriesByDate = Dictionary(uniqueKeysWithValues: primaryEntries.map { ($0.plotDate, $0) })
        self.secondaryEntriesByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.map { ($0.plotDate, $0) })
        self.chartYDomain = Self.computeYDomain(
            from: buckets + secondaryBuckets,
            rangeEntries: rangeEntries
        )

        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: day)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        self.chartXDomain = dayStart...nextDayStart
    }

    var body: some View {
        GeometryReader { proxy in
            chart(rangeBarWidth: Self.rangeBarWidth(forAvailableWidth: proxy.size.width))
        }
    }

    private func chart(rangeBarWidth: CGFloat) -> some View {
        Chart {
            ForEach(contextIntervals) { interval in
                RectangleMark(
                    xStart: .value("\(interval.title) Start", interval.startDate),
                    xEnd: .value("\(interval.title) End", interval.endDate),
                    yStart: .value("Context Minimum", chartYDomain.lowerBound),
                    yEnd: .value("Context Maximum", chartYDomain.upperBound)
                )
                .foregroundStyle(interval.color.opacity(interval.kind == .sleep ? 0.14 : 0.10))

                RectangleMark(
                    xStart: .value("\(interval.title) Top Start", interval.startDate),
                    xEnd: .value("\(interval.title) Top End", interval.endDate),
                    yStart: .value("Context Top Start", contextTopLineLowerBound),
                    yEnd: .value("Context Top End", chartYDomain.upperBound)
                )
                .foregroundStyle(interval.color)

                PointMark(
                    x: .value("\(interval.title) Label", interval.midpointDate),
                    y: .value("Context Label", chartYDomain.upperBound)
                )
                .foregroundStyle(Color.clear)
                .annotation(position: .top, spacing: 3, overflowResolution: bodyChartSelectionOverflowResolution) {
                    Image(systemName: interval.symbolName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(interval.color)
                        .accessibilityHidden(true)
                }
            }

            // Behind the line: each hour's min-max, in the same translucent gray
            // the Week/Month/6M/Year range chart uses under its average line.
            ForEach(rangeEntries) { entry in
                if entry.lowValue == entry.highValue {
                    PointMark(
                        x: .value("Time", entry.plotDate),
                        y: .value(title, entry.lowValue)
                    )
                    .symbolSize(bodyRangeChartPointSymbolSize(forBarWidth: rangeBarWidth))
                    .foregroundStyle(Self.rangeBarColor)
                } else {
                    BarMark(
                        x: .value("Time", entry.plotDate),
                        yStart: .value("Low \(title)", entry.lowValue),
                        yEnd: .value("High \(title)", entry.highValue),
                        width: .fixed(rangeBarWidth)
                    )
                    .foregroundStyle(Self.rangeBarColor)
                    .cornerRadius(rangeBarWidth / 2)
                }
            }

            ForEach(entries) { entry in
                LineMark(
                    x: .value("Time", entry.plotDate),
                    y: .value(title, entry.averageValue),
                    series: .value("Segment", entry.seriesKey)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: entry))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(pointMarkEntries) { entry in
                PointMark(
                    x: .value("Time", entry.plotDate),
                    y: .value(title, entry.averageValue)
                )
                .symbol {
                    BodyLineChartPreviewPointSymbol(
                        tintColor: color(for: entry),
                        isCurrent: isLatestEntry(entry),
                        pointDiameter: Self.pointDiameter,
                        currentPointDiameter: Self.currentPointDiameter
                    )
                }
            }

            if let selectedBucket {
                RuleMark(x: .value("Selected Time", selectedBucket.plotDate))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        BodyHealthMetricDayAnnotation(
                            bucket: selectedBucket.bucket,
                            values: selectedValues(for: selectedBucket.plotDate),
                            valueFormatter: valueFormatter,
                            aggregationLabel: aggregationLabel,
                            includesSampleBreakdown: includesSampleBreakdown
                        )
                    }

                ForEach(selectedEntries(for: selectedBucket.plotDate)) { entry in
                    PointMark(
                        x: .value("Selected Time", entry.plotDate),
                        y: .value(title, entry.averageValue)
                    )
                    .foregroundStyle(color(for: entry))
                    .symbolSize(82)
                }
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: chartYDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
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
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
    }

    private var selectedBucket: BodyHealthMetricDayChartEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.plotDate.timeIntervalSince(selectedDate)) < abs(second.plotDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectedEntries(for date: Date) -> [BodyHealthMetricDayChartEntry] {
        [primaryEntriesByDate[date], secondaryEntriesByDate[date]].compactMap { $0 }
    }

    private func selectedValues(for date: Date) -> [BodyChartSelectionValue] {
        let showsSourceName = !secondaryHourlyBuckets.isEmpty
        return selectedEntries(for: date).map { entry in
            BodyChartSelectionValue(
                title: showsSourceName ? entry.sourceName : nil,
                value: valueFormatter(entry.averageValue),
                color: color(for: entry)
            )
        }
    }

    private func isLatestEntry(_ entry: BodyHealthMetricDayChartEntry) -> Bool {
        entry.sourceRole == .primary
            ? entry.plotDate == latestBucketDate
            : entry.plotDate == latestSecondaryBucketDate
    }

    private func color(for entry: BodyHealthMetricDayChartEntry) -> Color {
        entry.sourceRole == .primary ? color : secondaryColor
    }

    /// Same translucent gray `BodyHeartRateRangeTrendChart` fills its bars with
    /// while an average line runs over them.
    private static let rangeBarColor = Color.secondary.opacity(0.24)

    private var contextTopLineLowerBound: Double {
        BodyHealthMetricDayContextBand.topStripeLowerBound(for: chartYDomain)
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

    private static func computeYDomain(
        from buckets: [HealthTrendHourlyBucket],
        rangeEntries: [BodyHealthMetricDayRangeEntry] = []
    ) -> ClosedRange<Double> {
        // The bars reach each hour's extremes, so they have to be inside the
        // domain or they clip at the plot edges.
        let values = (buckets.map(\.averageValue)
            + rangeEntries.flatMap { [$0.lowValue, $0.highValue] })
            .filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.02, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.16, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    static func segmentIndices(
        forSortedPlotDates dates: [Date],
        gapThreshold: TimeInterval = segmentGapThreshold
    ) -> [Int] {
        var indices: [Int] = []
        indices.reserveCapacity(dates.count)
        var current = 0
        for (offset, date) in dates.enumerated() {
            if offset > 0, date.timeIntervalSince(dates[offset - 1]) >= gapThreshold {
                current += 1
            }
            indices.append(current)
        }
        return indices
    }

    /// Keeps only the informative dots when a series holds flat runs: within
    /// each line segment, an interior entry is dropped when both neighbors
    /// share its value, so an unchanged stretch shows just its start and end
    /// dots. The line itself still spans every entry.
    static func collapsingUnchangedRunPoints(
        _ entries: [BodyHealthMetricDayChartEntry]
    ) -> [BodyHealthMetricDayChartEntry] {
        var keptIDs = Set<String>()
        for group in Dictionary(grouping: entries, by: \.seriesKey).values {
            let sorted = group.sorted { $0.plotDate < $1.plotDate }
            for (index, entry) in sorted.enumerated() {
                let matchesPrevious = index > 0 && sorted[index - 1].averageValue == entry.averageValue
                let matchesNext = index < sorted.count - 1 && sorted[index + 1].averageValue == entry.averageValue
                if !(matchesPrevious && matchesNext) {
                    keptIDs.insert(entry.id)
                }
            }
        }
        return entries.filter { keptIDs.contains($0.id) }
    }

    /// Low/high of every sample inside each hour — the intraday twin of the
    /// range chart's per-day min/max bar.
    static func makeRangeEntries(from buckets: [HealthTrendHourlyBucket]) -> [BodyHealthMetricDayRangeEntry] {
        buckets.compactMap { bucket in
            let values = bucket.samples.map(\.value).filter(\.isFinite)
            guard let lowValue = values.min(), let highValue = values.max() else {
                return nil
            }

            return BodyHealthMetricDayRangeEntry(
                hourStart: bucket.hourStart,
                plotDate: bucket.plotDate,
                lowValue: lowValue,
                highValue: highValue
            )
        }
    }

    /// Bar width for the 24 hourly slots, using the same slot-to-bar ratio the
    /// Month range chart uses (7pt bars across ~30 slots).
    static func rangeBarWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        let slotWidth = availableWidth / 24
        return min(max(slotWidth * 0.62, 4), 14)
    }

    private static func makeEntries(
        from buckets: [HealthTrendHourlyBucket],
        sourceName: String,
        sourceRole: BodyHealthSourceRole
    ) -> [BodyHealthMetricDayChartEntry] {
        let indices = segmentIndices(forSortedPlotDates: buckets.map(\.plotDate))
        return zip(buckets, indices).map { bucket, index in
            BodyHealthMetricDayChartEntry(
                sourceName: sourceName,
                sourceRole: sourceRole,
                bucket: bucket,
                segmentIndex: index
            )
        }
    }
}

/// One hour's low/high, drawn as the transparent gray range bar behind the
/// hourly-average line.
struct BodyHealthMetricDayRangeEntry: Identifiable {
    let hourStart: Date
    let plotDate: Date
    let lowValue: Double
    let highValue: Double

    var id: Int {
        hourStart.bodyHourOfDayIndex
    }
}

struct BodyHealthMetricDayChartEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let bucket: HealthTrendHourlyBucket
    let segmentIndex: Int

    var id: String {
        "\(sourceRole.rawValue)-\(bucket.hourStart.bodyHourOfDayIndex)"
    }

    var seriesKey: String {
        "\(sourceRole.rawValue)-\(segmentIndex)"
    }

    var plotDate: Date {
        bucket.plotDate
    }

    var averageValue: Double {
        bucket.averageValue
    }
}

private extension Date {
    /// Hours since this date's own midnight. Day-chart marks use this as their
    /// identity instead of the absolute hour timestamp so a mark keeps its
    /// identity across days — moving the day picker morphs each dot to the new
    /// day's value (like the sleep Vitals plot) rather than replacing it.
    /// Elapsed hours, not the clock hour, which repeats on DST fall-back days.
    var bodyHourOfDayIndex: Int {
        Int(timeIntervalSince(Calendar.bodyGregorian.startOfDay(for: self)) / 3600)
    }
}

struct BodyHealthMetricDayAnnotation: View {
    let bucket: HealthTrendHourlyBucket
    let values: [BodyChartSelectionValue]
    let valueFormatter: (Double) -> String
    let aggregationLabel: String
    let includesSampleBreakdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(aggregationLabel)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)

            ForEach(values) { value in
                HStack(spacing: 7) {
                    Circle()
                        .fill(value.color)
                        .frame(width: 8, height: 8)

                    if let title = value.title {
                        Text(title)
                            .foregroundColor(.secondary)
                    }

                    Text(value.value)
                        .foregroundColor(.primary)
                }
                .font(.system(size: values.count == 1 ? 20 : 16, weight: .bold, design: .rounded))
            }

            Text(hourRangeText)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if includesSampleBreakdown, !sampleWindows.isEmpty {
                Divider()
                    .padding(.vertical, 1)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sampleWindows) { window in
                        HStack(spacing: 10) {
                            Text(windowRangeText(for: window))
                                .foregroundColor(.secondary)

                            Text(valueFormatter(window.averageValue))
                                .foregroundColor(.primary)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .bodyChartSelectionAnnotationBackground()
    }

    private var sampleWindows: [HealthTrendHourlySampleWindow] {
        bucket.sampleWindows()
    }

    private var hourRangeText: String {
        let hourEnd = bucket.hourStart.addingTimeInterval(60 * 60)
        return "\(timeText(for: bucket.hourStart))-\(timeText(for: hourEnd))"
    }

    private func windowRangeText(for window: HealthTrendHourlySampleWindow) -> String {
        "\(timeText(for: window.startDate))-\(timeText(for: window.endDate))"
    }

    private func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
