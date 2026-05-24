//
//  BasicsCharts.swift
//  Body
//

import Charts
import SwiftUI

struct BodyBasicsTrendChart: View {
    let selectedRange: BodyHealthTrendRange
    let weightColor: Color
    let bodyFatColor: Color
    let weightFormatter: (Double) -> String
    let bodyFatFormatter: (Double) -> String

    private let weightCalendarPoints: [HealthTrendCalendarPoint]
    private let bodyFatCalendarPoints: [HealthTrendCalendarPoint]
    private let weightDomain: ClosedRange<Double>
    private let bodyFatDomain: ClosedRange<Double>
    private let chartXDomain: ClosedRange<Date>
    private let weightLatestCalendarDate: Date?
    private let bodyFatLatestCalendarDate: Date?
    private let weightFinitePointsByDate: [Date: HealthTrendCalendarPoint]
    private let bodyFatFinitePointsByDate: [Date: HealthTrendCalendarPoint]
    private let combinedFinitePoints: [HealthTrendCalendarPoint]

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let axisTickValues = [0.0, 0.25, 0.5, 0.75, 1.0]
    private let normalizedYDomain = 0.0...1.1

    init(
        trend: BasicsTrendSummary,
        selectedRange: BodyHealthTrendRange,
        weightColor: Color,
        bodyFatColor: Color,
        weightFormatter: @escaping (Double) -> String,
        bodyFatFormatter: @escaping (Double) -> String
    ) {
        self.selectedRange = selectedRange
        self.weightColor = weightColor
        self.bodyFatColor = bodyFatColor
        self.weightFormatter = weightFormatter
        self.bodyFatFormatter = bodyFatFormatter

        let weightPoints = trend.weight.lineChartCalendarPoints(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
        let bodyFatPoints = trend.bodyFat.lineChartCalendarPoints(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
        self.weightCalendarPoints = weightPoints
        self.bodyFatCalendarPoints = bodyFatPoints
        self.weightDomain = Self.paddedDomain(from: weightPoints)
        self.bodyFatDomain = Self.paddedDomain(from: bodyFatPoints)

        let domainDates = trend.weight.calendarPoints(to: selectedRange).map(\.date)
            + trend.bodyFat.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)

        self.weightLatestCalendarDate = weightPoints.last { $0.value?.isFinite == true }?.date
        self.bodyFatLatestCalendarDate = bodyFatPoints.last { $0.value?.isFinite == true }?.date

        var weightLookup: [Date: HealthTrendCalendarPoint] = [:]
        weightLookup.reserveCapacity(weightPoints.count)
        var bodyFatLookup: [Date: HealthTrendCalendarPoint] = [:]
        bodyFatLookup.reserveCapacity(bodyFatPoints.count)
        var combinedFinite: [HealthTrendCalendarPoint] = []
        combinedFinite.reserveCapacity(weightPoints.count + bodyFatPoints.count)
        for point in weightPoints where point.value?.isFinite == true {
            weightLookup[point.date] = point
            combinedFinite.append(point)
        }
        for point in bodyFatPoints where point.value?.isFinite == true {
            bodyFatLookup[point.date] = point
            combinedFinite.append(point)
        }
        self.weightFinitePointsByDate = weightLookup
        self.bodyFatFinitePointsByDate = bodyFatLookup
        self.combinedFinitePoints = combinedFinite
    }

    var body: some View {
        Chart {
            ForEach(weightCalendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", normalized(value, in: weightDomain)),
                        series: .value("Metric", "Weight")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(lineStrokeColor(for: weightColor))
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Weight", normalized(value, in: weightDomain))
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: weightColor,
                                    isCurrent: isLatestWeightPoint(point),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Weight", normalized(value, in: weightDomain))
                            )
                            .foregroundStyle(weightColor)
                            .symbolSize(28)
                        }
                    }
                }
            }

            ForEach(bodyFatCalendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Body Fat", normalized(value, in: bodyFatDomain)),
                        series: .value("Metric", "Body Fat")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(lineStrokeColor(for: bodyFatColor))
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Body Fat", normalized(value, in: bodyFatDomain))
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: bodyFatColor,
                                    isCurrent: isLatestBodyFatPoint(point),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Body Fat", normalized(value, in: bodyFatDomain))
                            )
                            .foregroundStyle(bodyFatColor)
                            .symbolSize(28)
                        }
                    }
                }
            }

            if let selectedTrendDate {
                RuleMark(x: .value("Selected Date", selectedTrendDate, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        BodyChartSelectionAnnotation(
                            eyebrow: nil,
                            values: selectionValues(for: selectedTrendDate),
                            date: selectedTrendDate,
                            dateText: selectedTrendDateText
                        )
                    }

                if let selectedWeightPoint = weightFinitePointsByDate[selectedTrendDate],
                   let selectedWeightValue = selectedWeightPoint.value {
                    PointMark(
                        x: .value("Selected Weight Date", selectedWeightPoint.date, unit: .day),
                        y: .value("Weight", normalized(selectedWeightValue, in: weightDomain))
                    )
                    .foregroundStyle(weightColor)
                    .symbolSize(82)
                }

                if let selectedBodyFatPoint = bodyFatFinitePointsByDate[selectedTrendDate],
                   let selectedBodyFatValue = selectedBodyFatPoint.value {
                    PointMark(
                        x: .value("Selected Body Fat Date", selectedBodyFatPoint.date, unit: .day),
                        y: .value("Body Fat", normalized(selectedBodyFatValue, in: bodyFatDomain))
                    )
                    .foregroundStyle(bodyFatColor)
                    .symbolSize(82)
                }
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: normalizedYDomain)
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
            AxisMarks(position: .leading, values: axisTickValues) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(weightColor.opacity(0.55))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(weightFormatter(denormalizedValue(for: yValue, in: weightDomain)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }

            AxisMarks(position: .trailing, values: axisTickValues) { value in
                AxisTick()
                    .foregroundStyle(bodyFatColor.opacity(0.55))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(bodyFatFormatter(denormalizedValue(for: yValue, in: bodyFatDomain)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
        .id(selectedRange.rawValue)
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedTrendDate: Date? {
        selectedTrendPoint?.date
    }

    private var selectedTrendPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return combinedFinitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedTrendDateText: String? {
        selectedTrendPoint.flatMap { point in
            bodyChartSelectionDateText(for: point)
        }
    }

    private func isLatestWeightPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == weightLatestCalendarDate
    }

    private func isLatestBodyFatPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == bodyFatLatestCalendarDate
    }

    private func lineStrokeColor(for color: Color) -> Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private static func paddedDomain(from points: [HealthTrendCalendarPoint]) -> ClosedRange<Double> {
        let finiteValues = points.compactMap(\.value).filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.05, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private func normalized(_ value: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else {
            return 0
        }

        return min(max((value - domain.lowerBound) / span, 0), 1)
    }

    private func denormalizedValue(for normalizedValue: Double, in domain: ClosedRange<Double>) -> Double {
        domain.lowerBound + (domain.upperBound - domain.lowerBound) * normalizedValue
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

    private func selectionValues(for date: Date) -> [BodyChartSelectionValue] {
        var values: [BodyChartSelectionValue] = []

        if let point = bodyFatFinitePointsByDate[date], let value = point.value {
            values.append(BodyChartSelectionValue(
                title: "Body Fat",
                value: bodyFatFormatter(value),
                color: bodyFatColor
            ))
        }

        if let point = weightFinitePointsByDate[date], let value = point.value {
            values.append(BodyChartSelectionValue(
                title: "Weight",
                value: weightFormatter(value),
                color: weightColor
            ))
        }

        return values
    }
}


struct BodyBasicsBodyMassIndexTrendChart: View {
    let selectedRange: BodyHealthTrendRange
    let color: Color
    let valueFormatter: (Double) -> String

    private let calendarPoints: [HealthTrendCalendarPoint]
    private let finitePoints: [HealthTrendCalendarPoint]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestCalendarDate: Date?

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        series: HealthTrendSeries,
        selectedRange: BodyHealthTrendRange,
        color: Color,
        valueFormatter: @escaping (Double) -> String
    ) {
        self.selectedRange = selectedRange
        self.color = color
        self.valueFormatter = valueFormatter

        let points = series.lineChartCalendarPoints(to: selectedRange)
        self.calendarPoints = points
        self.finitePoints = points.filter { $0.value?.isFinite == true }
        self.chartYDomain = Self.computeYDomain(from: points)

        let domainDates = series.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)

        self.latestCalendarDate = points.last { $0.value?.isFinite == true }?.date
    }

    var body: some View {
        Chart {
            ForEach(calendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("BMI", value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(lineStrokeColor)
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("BMI", value)
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: color,
                                    isCurrent: isLatestPoint(point),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("BMI", value)
                            )
                            .foregroundStyle(color)
                            .symbolSize(28)
                        }
                    }
                }
            }

            if let selectedPoint, let selectedValue = selectedPoint.value {
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
                            values: [
                                BodyChartSelectionValue(
                                    title: nil,
                                    value: valueFormatter(selectedValue),
                                    color: color
                                )
                            ],
                            date: selectedPoint.date,
                            dateText: bodyChartSelectionDateText(for: selectedPoint)
                        )
                    }

                PointMark(
                    x: .value("Selected Date", selectedPoint.date, unit: .day),
                    y: .value("BMI", selectedValue)
                )
                .foregroundStyle(color)
                .symbolSize(82)
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
        .id(selectedRange.rawValue)
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private func isLatestPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == latestCalendarDate
    }

    private var lineStrokeColor: Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
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

    private static func computeYDomain(from points: [HealthTrendCalendarPoint]) -> ClosedRange<Double> {
        let values = points.compactMap(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.05, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }
}
