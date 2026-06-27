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
    let activeHighlightedValue: Binding<Double?>?
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
        activeHighlightedValue: Binding<Double?>? = nil,
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
        self.activeHighlightedValue = activeHighlightedValue
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
        let domainValues = (aggregatedValues.isEmpty ? fallbackValues : aggregatedValues)
            + highlightedRangeValues
            + baselineDomainValues
        let yDomain = Self.computeYDomain(from: domainValues, chartStyle: chartStyle)
        self.chartYDomain = yDomain

        let domainDates = series.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)

        self.latestVisibleCalendarDate = calendarPoints.last { $0.value?.isFinite == true }?.date

        let span = yDomain.upperBound - yDomain.lowerBound
        self.placeholderBarYValue = yDomain.lowerBound + max(span * 0.025, 0.025)
    }

    private var activeHighlightedRange: BodyHealthMetricTrendHighlightedRange? {
        guard let highlightedRangeResolver, let activeHighlightSourcePoint else {
            return highlightedRange
        }

        return highlightedRangeResolver(activeHighlightSourcePoint.value) ?? highlightedRange
    }

    private var activeHighlightSourcePoint: HealthTrendCalendarPoint? {
        selectedTrendPoint ?? latestVisibleTrendPoint
    }

    private var activeHighlightSourceValue: Double? {
        activeHighlightSourcePoint?.value
    }

    private var latestVisibleTrendPoint: HealthTrendCalendarPoint? {
        visibleFinitePoints.last
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

                if let selectedTrendPoint, let selectedTrendValue = selectedTrendPoint.value {
                    RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                        .foregroundStyle(chartStyle == .bar ? Color.clear : Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            BodyChartSelectionAnnotation(
                                eyebrow: chartStyle == .bar ? barSelectionEyebrow : nil,
                                values: selectionValues(for: selectedTrendValue),
                                date: selectedTrendPoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedTrendPoint)
                            )
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
            .transaction(value: highlightedRangeAnimationKey) { transaction in
                transaction.animation = reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                syncActiveHighlightedValue()
            }
            .onChange(of: activeHighlightSourceValue) { _, _ in
                syncActiveHighlightedValue()
            }
        }
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
        selectedRange.chartAggregationDayCount > 1 ? "AVG" : "TOTAL"
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
                title: "Baseline",
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
    private let entries: [BodyHealthMetricDayChartEntry]
    private let finiteEntries: [BodyHealthMetricDayChartEntry]
    private let primaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let secondaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestBucketDate: Date?
    private let latestSecondaryBucketDate: Date?

    private static let pointDiameter: CGFloat = 8
    private static let currentPointDiameter: CGFloat = 10

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    init(
        series: HealthTrendSeries,
        secondarySeries: HealthTrendSeries = .empty,
        day: Date,
        title: String,
        color: Color,
        secondaryColor: Color = Color(red: 0.58, green: 0.36, blue: 0.98),
        primarySourceName: String = "Primary",
        secondarySourceName: String = "Secondary",
        valueFormatter: @escaping (Double) -> String,
        contextIntervals: [BodyHealthMetricDayContextInterval] = [],
        aggregationLabel: String = "HOURLY AVG",
        includesSampleBreakdown: Bool = true
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
        self.latestBucketDate = buckets.last?.plotDate
        self.latestSecondaryBucketDate = secondaryBuckets.last?.plotDate
        let primaryEntries = buckets.map {
            BodyHealthMetricDayChartEntry(sourceName: primarySourceName, sourceRole: .primary, bucket: $0)
        }
        let secondaryEntries = secondaryBuckets.map {
            BodyHealthMetricDayChartEntry(sourceName: secondarySourceName, sourceRole: .secondary, bucket: $0)
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter { $0.averageValue.isFinite }
        self.primaryEntriesByDate = Dictionary(uniqueKeysWithValues: primaryEntries.map { ($0.plotDate, $0) })
        self.secondaryEntriesByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.map { ($0.plotDate, $0) })
        self.chartYDomain = Self.computeYDomain(from: buckets + secondaryBuckets)

        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: day)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        self.chartXDomain = dayStart...nextDayStart
    }

    var body: some View {
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

            ForEach(entries) { entry in
                LineMark(
                    x: .value("Time", entry.plotDate),
                    y: .value(title, entry.averageValue),
                    series: .value("Source", entry.sourceRole.rawValue)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: entry))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

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

    private static func computeYDomain(from buckets: [HealthTrendHourlyBucket]) -> ClosedRange<Double> {
        let values = buckets.map(\.averageValue).filter(\.isFinite)
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
}

struct BodyHealthMetricDayChartEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let bucket: HealthTrendHourlyBucket

    var id: String {
        "\(sourceRole.rawValue)-\(bucket.id)"
    }

    var plotDate: Date {
        bucket.plotDate
    }

    var averageValue: Double {
        bucket.averageValue
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
