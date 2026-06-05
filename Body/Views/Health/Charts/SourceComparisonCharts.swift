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
    let chartIdentity: String

    private let entries: [BodyHealthSourceComparisonLineEntry]
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
        chartIdentity: String
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.isSleepDetail = isSleepDetail
        self.chartIdentity = chartIdentity

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
        self.entries = allEntries
        self.finiteEntries = allEntries.filter { $0.value?.isFinite == true }
        self.primaryPointsByDate = Dictionary(uniqueKeysWithValues: primaryEntries.compactMap { entry in
            entry.value?.isFinite == true ? (entry.date, entry) : nil
        })
        self.secondaryPointsByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.compactMap { entry in
            entry.value?.isFinite == true ? (entry.date, entry) : nil
        })
        self.latestPrimaryDate = primaryEntries.last { $0.value?.isFinite == true }?.date
        self.latestSecondaryDate = secondaryEntries.last { $0.value?.isFinite == true }?.date
        let domainDates = primaryEntries.map(\.date) + secondaryEntries.map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
        self.chartYDomain = BodyHealthMetricTrendChart.computeYDomain(
            from: allEntries.compactMap(\.value).filter(\.isFinite),
            chartStyle: .line
        )
    }

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                if let value = entry.value {
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value(title, value),
                        series: .value("Source", entry.sourceRole.rawValue)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(lineStrokeColor(for: entry))
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
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
                            }
                        } else {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, value)
                            )
                            .foregroundStyle(color(for: entry))
                            .symbolSize(28)
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
                        BodyChartSelectionAnnotation(
                            eyebrow: nil,
                            values: selectedValues(for: selectedPoint.date),
                            date: selectedPoint.date,
                            dateText: bodyChartSelectionDateText(for: selectedPoint.point)
                        )
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
        .id(chartIdentity)
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
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
        entry.sourceRole == .primary ? primaryColor : secondaryColor
    }

    private func lineStrokeColor(for entry: BodyHealthSourceComparisonLineEntry) -> Color {
        selectedRange.usesMetricColorLineStroke ? color(for: entry) : color(for: entry).opacity(0.72)
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
}

struct BodyHealthSourceComparisonLineEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendCalendarPoint

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

struct BodyHealthSourceComparisonBarChart: View {
    let title: String
    let comparison: BodyHealthSourceComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let chartIdentity: String

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
        chartIdentity: String
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.chartIdentity = chartIdentity

        let primaryPoints = comparison.primary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let dateOffset = selectedRange.sourceComparisonChartDateOffset
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(-dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(dateOffset)
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter { $0.value?.isFinite == true }

        let domainDates = allEntries.map(\.chartDate)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
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
                            BodyChartSelectionAnnotation(
                                eyebrow: selectedRange.sourceComparisonChartAggregationDayCount > 1 ? "AVG" : "TOTAL",
                                values: selectedValues(for: selectedPoint),
                                date: selectedPoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedPoint.point)
                            )
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
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
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
            .filter { $0.date == selectedPoint.date && $0.value?.isFinite == true }
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
}

struct BodyHealthSourceComparisonBarEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendCalendarPoint
    let chartDate: Date

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
    let chartIdentity: String

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
        chartIdentity: String
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.chartIdentity = chartIdentity

        let primaryPoints = comparison.primary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let dateOffset = selectedRange.sourceComparisonChartDateOffset
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(-dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(dateOffset)
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter(\.hasValue)

        let domainDates = allEntries.map(\.chartDate)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
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
                        if lowValue == highValue {
                            PointMark(
                                x: .value("Date", entry.chartDate),
                                y: .value(title, lowValue)
                            )
                            .symbolSize(bodyRangeChartPointSymbolSize(forBarWidth: chartBarWidth))
                            .foregroundStyle(color(for: entry).gradient)
                        } else {
                            BarMark(
                                x: .value("Date", entry.chartDate),
                                yStart: .value("Low \(title)", lowValue),
                                yEnd: .value("High \(title)", highValue),
                                width: .fixed(chartBarWidth)
                            )
                            .foregroundStyle(color(for: entry).gradient)
                            .cornerRadius(chartBarWidth / 2)
                        }
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
                            BodyChartSelectionAnnotation(
                                eyebrow: "RANGE",
                                values: selectedValues(for: selectedPoint),
                                date: selectedPoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedPoint.point)
                            )
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
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
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
            .filter { $0.date == selectedPoint.date && $0.hasValue }
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
}

struct BodyHealthSourceComparisonRangeEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendRangeCalendarPoint
    let chartDate: Date

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

