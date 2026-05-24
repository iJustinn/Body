//
//  HeartRateRangeChart.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHeartRateRangeTrendChart: View {
    let title: String
    let selectedRange: BodyHealthTrendRange
    let symbolColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let showsAverageLineOverlay: Bool

    private let rangePoints: [HealthTrendRangeCalendarPoint]
    private let secondaryRangePoints: [HealthTrendRangeCalendarPoint]
    private let averageEntries: [BodyHeartRateRangeAverageEntry]
    private let finiteRangePoints: [HealthTrendRangeCalendarPoint]
    private let latestPrimaryAveragePointDate: Date?
    private let latestSecondaryAveragePointDate: Date?
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let primarySourceName: String
    private let secondarySourceName: String?

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        selectedRange: BodyHealthTrendRange,
        rangeSeries: HealthTrendRangeSeries,
        secondaryRangeSeries: HealthTrendRangeSeries? = nil,
        primarySourceName: String = "Primary",
        secondarySourceName: String? = nil,
        symbolColor: Color,
        secondaryColor: Color = Color(red: 0.58, green: 0.36, blue: 0.98),
        valueFormatter: @escaping (Double) -> String,
        showsAverageLineOverlay: Bool = false,
        yDomain: (([Double]) -> ClosedRange<Double>)? = nil
    ) {
        self.title = title
        self.selectedRange = selectedRange
        self.symbolColor = symbolColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.showsAverageLineOverlay = showsAverageLineOverlay
        self.primarySourceName = primarySourceName
        self.secondarySourceName = secondarySourceName

        let points = rangeSeries.chartCalendarPoints(to: selectedRange)
        let secondaryPoints = secondaryRangeSeries?.chartCalendarPoints(to: selectedRange) ?? []
        self.rangePoints = points
        self.secondaryRangePoints = secondaryPoints
        self.finiteRangePoints = points.filter(\.hasValue)
        self.latestPrimaryAveragePointDate = points.last { point in
            point.averageValue?.isFinite == true
        }?.date
        self.latestSecondaryAveragePointDate = secondaryPoints.last { point in
            point.averageValue?.isFinite == true
        }?.date
        self.averageEntries = Self.averageEntries(
            primaryPoints: points,
            secondaryPoints: secondaryPoints,
            primarySourceName: primarySourceName,
            secondarySourceName: secondarySourceName
        )
        let domainValues = (points + secondaryPoints).flatMap { point -> [Double] in
            guard let low = point.lowValue, let high = point.highValue else {
                return []
            }

            return [low, high]
        }
        self.chartYDomain = yDomain?(domainValues) ?? Self.computeYDomain(from: domainValues)
        let domainDates = rangeSeries.calendarPoints(to: selectedRange).map(\.date)
            + (secondaryRangeSeries?.calendarPoints(to: selectedRange).map(\.date) ?? [])
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.heartRateRangeChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                if let selectedRangePoint {
                    RuleMark(x: .value("Selected Date", selectedRangePoint.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(rangePoints) { point in
                    if let lowValue = point.lowValue, let highValue = point.highValue {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            yStart: .value("Low \(title)", lowValue),
                            yEnd: .value("High \(title)", highValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(rangeBarColor)
                        .cornerRadius(chartBarWidth / 2)
                    }
                }

                averageLineOverlay

                if let selectedRangePoint,
                   let lowValue = selectedRangePoint.lowValue,
                   let highValue = selectedRangePoint.highValue {
                    RuleMark(x: .value("Selected Date", selectedRangePoint.date, unit: .day))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            BodyChartSelectionAnnotation(
                                eyebrow: "RANGE",
                                values: selectedValues(for: selectedRangePoint, lowValue: lowValue, highValue: highValue),
                                date: selectedRangePoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedRangePoint)
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
            .id("heart-rate-range-\(selectedRange.rawValue)")
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    @ChartContentBuilder
    private var averageLineOverlay: some ChartContent {
        if showsAverageLineOverlay {
            ForEach(averageEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Average \(title)", entry.value),
                    series: .value("Source", entry.sourceRole.rawValue)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: entry))
                .lineStyle(StrokeStyle(lineWidth: BodyLineChartPreviewStyle.lineWidth, lineCap: .round, lineJoin: .round))

                if selectedRange.showsPointMarks {
                    if selectedRange.usesPreviewLineChartStyle {
                        PointMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Average \(title)", entry.value)
                        )
                        .symbol {
                            BodyLineChartPreviewPointSymbol(
                                tintColor: color(for: entry),
                                isCurrent: isLatestAverageEntry(entry),
                                pointDiameter: selectedRange.linePointDiameter,
                                currentPointDiameter: selectedRange.lineCurrentPointDiameter
                            )
                        }
                    } else {
                        PointMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Average \(title)", entry.value)
                        )
                        .foregroundStyle(color(for: entry))
                        .symbolSize(28)
                    }
                }
            }

            if let selectedRangePoint {
                ForEach(selectedAverageEntries(for: selectedRangePoint.date)) { entry in
                    PointMark(
                        x: .value("Selected Date", entry.date, unit: .day),
                        y: .value("Average \(title)", entry.value)
                    )
                    .foregroundStyle(color(for: entry))
                    .symbolSize(82)
                }
            }
        }
    }

    private func selectedAverageEntries(for date: Date) -> [BodyHeartRateRangeAverageEntry] {
        averageEntries.filter { $0.date == date }
    }

    private var selectedRangePoint: HealthTrendRangeCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteRangePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private var rangeBarColor: Color {
        showsAverageLineOverlay ? Color.secondary.opacity(0.24) : symbolColor
    }

    private func selectedValues(
        for point: HealthTrendRangeCalendarPoint,
        lowValue: Double,
        highValue: Double
    ) -> [BodyChartSelectionValue] {
        guard !secondaryRangePoints.isEmpty else {
            return [
                BodyChartSelectionValue(
                    title: nil,
                    value: "\(valueFormatter(lowValue))-\(valueFormatter(highValue))",
                    color: symbolColor
                )
            ]
        }

        var values = [
            BodyChartSelectionValue(
                title: "Range",
                value: "\(valueFormatter(lowValue))-\(valueFormatter(highValue))",
                color: Color.secondary
            )
        ]

        values.append(contentsOf: averageEntries
            .filter { $0.date == point.date }
            .sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }
            .map { entry in
                BodyChartSelectionValue(
                    title: entry.sourceName,
                    value: valueFormatter(entry.value),
                    color: color(for: entry)
                )
            })

        return values
    }

    private func isLatestAverageEntry(_ entry: BodyHeartRateRangeAverageEntry) -> Bool {
        entry.sourceRole == .primary
            ? entry.date == latestPrimaryAveragePointDate
            : entry.date == latestSecondaryAveragePointDate
    }

    private func color(for entry: BodyHeartRateRangeAverageEntry) -> Color {
        entry.sourceRole == .primary ? symbolColor : secondaryColor
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

    private static func averageEntries(
        primaryPoints: [HealthTrendRangeCalendarPoint],
        secondaryPoints: [HealthTrendRangeCalendarPoint],
        primarySourceName: String,
        secondarySourceName: String?
    ) -> [BodyHeartRateRangeAverageEntry] {
        let primaryEntries = primaryPoints.compactMap { point -> BodyHeartRateRangeAverageEntry? in
            guard let value = point.averageValue, value.isFinite else {
                return nil
            }

            return BodyHeartRateRangeAverageEntry(
                sourceName: primarySourceName,
                sourceRole: .primary,
                date: point.date,
                value: value
            )
        }
        let secondaryEntries = secondaryPoints.compactMap { point -> BodyHeartRateRangeAverageEntry? in
            guard let value = point.averageValue, value.isFinite else {
                return nil
            }

            return BodyHeartRateRangeAverageEntry(
                sourceName: secondarySourceName ?? "Secondary",
                sourceRole: .secondary,
                date: point.date,
                value: value
            )
        }

        return primaryEntries + secondaryEntries
    }
}

struct BodyHeartRateRangeAverageEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let date: Date
    let value: Double

    var id: String {
        "\(sourceRole.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}
