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
    let immersive: Bool
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let weightMarkEntries: [BodyHealthTrendMarkEntry]
    private let bodyFatMarkEntries: [BodyHealthTrendMarkEntry]
    private let weightLineSegments: [BodyHealthTrendLineSegmentMark]
    private let bodyFatLineSegments: [BodyHealthTrendLineSegmentMark]
    private let weightDomain: ClosedRange<Double>
    private let bodyFatDomain: ClosedRange<Double>
    private let chartXDomain: ClosedRange<Date>
    private let weightLatestCalendarDate: Date?
    private let bodyFatLatestCalendarDate: Date?
    private let weightFinitePointsByDate: [Date: HealthTrendCalendarPoint]
    private let bodyFatFinitePointsByDate: [Date: HealthTrendCalendarPoint]
    private let combinedFinitePoints: [HealthTrendCalendarPoint]
    private let weightSamples: HealthTrendSeries
    private let bodyFatSamples: HealthTrendSeries

    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let axisTickValues = [0.0, 0.25, 0.5, 0.75, 1.0]
    private let normalizedYDomain = 0.0...1.1

    init(
        trend: BasicsTrendSummary,
        selectedRange: BodyHealthTrendRange,
        weightColor: Color,
        bodyFatColor: Color,
        weightFormatter: @escaping (Double) -> String,
        bodyFatFormatter: @escaping (Double) -> String,
        immersive: Bool = false,
        floatingCallout: BodyChartFloatingCalloutState? = nil,
        weightPointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]? = nil,
        bodyFatPointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]? = nil
    ) {
        self.selectedRange = selectedRange
        self.weightColor = weightColor
        self.bodyFatColor = bodyFatColor
        self.weightFormatter = weightFormatter
        self.bodyFatFormatter = bodyFatFormatter
        self.immersive = immersive
        self.floatingCallout = floatingCallout
        self.weightSamples = trend.weightSamples
        self.bodyFatSamples = trend.bodyFatSamples

        // Every range's points, not just the selected one: dates outside the
        // current range stay resident as invisible placeholder marks, so a
        // range switch morphs the shared dates in place and fades the rest
        // instead of replacing the whole chart. The host passes them in from a
        // cache that survives a re-render; the inline fallback keeps previews
        // and one-off callers working.
        let weightPointsByRange = weightPointsByRange ?? Self.makePointsByRange(for: trend.weight)
        let bodyFatPointsByRange = bodyFatPointsByRange ?? Self.makePointsByRange(for: trend.bodyFat)
        let weightPoints = weightPointsByRange[selectedRange] ?? []
        let bodyFatPoints = bodyFatPointsByRange[selectedRange] ?? []
        self.weightMarkEntries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: selectedRange,
            pointsByRange: weightPointsByRange
        )
        self.bodyFatMarkEntries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: selectedRange,
            pointsByRange: bodyFatPointsByRange
        )
        self.weightLineSegments = BodyHealthMetricTrendChart.makeTrendLineSegments(
            selectedRange: selectedRange,
            pointsByRange: weightPointsByRange
        )
        self.bodyFatLineSegments = BodyHealthMetricTrendChart.makeTrendLineSegments(
            selectedRange: selectedRange,
            pointsByRange: bodyFatPointsByRange
        )
        // Every range's values, not just the selected one: a per-range domain
        // re-scales the axis on a range switch, so the same reading lands at a
        // different height and the morph reads as the data moving.
        self.weightDomain = Self.paddedDomain(from: weightPointsByRange.values.flatMap { $0 })
        self.bodyFatDomain = Self.paddedDomain(from: bodyFatPointsByRange.values.flatMap { $0 })

        let domainDates = trend.weight.calendarPoints(to: selectedRange).map(\.date)
            + trend.bodyFat.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)

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
            // Per-pair segments instead of one LineMark run per metric: Swift
            // Charts cannot interpolate a single line whose vertex set changes
            // across a range switch — unmatched vertices freeze, then pop.
            // Segment ids are namespaced by metric, or the two lines would
            // share a series key on a shared date and join into one stroke.
            ForEach(weightLineSegments) { segment in
                LineMark(
                    x: .value("Date", segment.startDate, unit: .day),
                    y: .value("Weight", normalized(segment.startValue, in: weightDomain)),
                    series: .value("Segment", "weight-\(segment.id)")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor(for: weightColor))
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)

                LineMark(
                    x: .value("Date", segment.endDate, unit: .day),
                    y: .value("Weight", normalized(segment.endValue, in: weightDomain)),
                    series: .value("Segment", "weight-\(segment.id)")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor(for: weightColor))
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                // Both endpoints, or VoiceOver still reads the second half of
                // an invisible off-range segment.
                .accessibilityHidden(segment.isPlaceholder)
            }

            if selectedRange.showsPointMarks {
                ForEach(weightMarkEntries) { entry in
                    if let value = entry.dotValue {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("Weight", normalized(value, in: weightDomain))
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: weightColor,
                                    isCurrent: isLatestWeightEntry(entry),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                                // Inside the symbol view, not a mark modifier — Charts
                                // does not apply mark opacity to custom `.symbol {}`
                                // content, which would leave the placeholders visible.
                                .opacity(entry.showsDot ? 1 : 0)
                            }
                            // Opacity is only visual: an off-range placeholder
                            // would still be announced.
                            .accessibilityHidden(!entry.showsDot)
                        } else {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("Weight", normalized(value, in: weightDomain))
                            )
                            .foregroundStyle(weightColor)
                            .symbolSize(28)
                            .opacity(entry.showsDot ? 1 : 0)
                            .accessibilityHidden(!entry.showsDot)
                        }
                    }
                }
            }

            ForEach(bodyFatLineSegments) { segment in
                LineMark(
                    x: .value("Date", segment.startDate, unit: .day),
                    y: .value("Body Fat", normalized(segment.startValue, in: bodyFatDomain)),
                    series: .value("Segment", "body-fat-\(segment.id)")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor(for: bodyFatColor))
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)

                LineMark(
                    x: .value("Date", segment.endDate, unit: .day),
                    y: .value("Body Fat", normalized(segment.endValue, in: bodyFatDomain)),
                    series: .value("Segment", "body-fat-\(segment.id)")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor(for: bodyFatColor))
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)
            }

            if selectedRange.showsPointMarks {
                ForEach(bodyFatMarkEntries) { entry in
                    if let value = entry.dotValue {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("Body Fat", normalized(value, in: bodyFatDomain))
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: bodyFatColor,
                                    isCurrent: isLatestBodyFatEntry(entry),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                                .opacity(entry.showsDot ? 1 : 0)
                            }
                            .accessibilityHidden(!entry.showsDot)
                        } else {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("Body Fat", normalized(value, in: bodyFatDomain))
                            )
                            .foregroundStyle(bodyFatColor)
                            .symbolSize(28)
                            .opacity(entry.showsDot ? 1 : 0)
                            .accessibilityHidden(!entry.showsDot)
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
                        if floatingCallout == nil {
                            selectionAnnotation(for: selectedTrendDate)
                        }
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
            if !immersive {
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
        }
        .bodyChartHoldToScrub($selectedDate)
        .bodyChartScrubHaptics(selection: selectedTrendDate)
        .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedTrendDate) {
            guard let selectedTrendDate else {
                return AnyView(EmptyView())
            }
            return AnyView(selectionAnnotation(for: selectedTrendDate))
        }
        // Stable across range switches: a per-range id would replace the chart
        // instead of updating it, popping every mark rather than letting them
        // morph.
        .id("basics-weight-body-fat")
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        // Keyed on the range ONLY: a broader key would also animate scrub-mark
        // removal.
        .animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)
        .onChange(of: selectedRange) {
            selectedDate = nil
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedTrendDate: Date? {
        selectedTrendPoint?.date
    }

    private func selectionAnnotation(for date: Date) -> BodyChartSelectionAnnotation {
        let breakdown = selectionBreakdown(for: date)
        return BodyChartSelectionAnnotation(
            eyebrow: breakdown.isEmpty ? nil : String(localized: "DAILY AVG"),
            values: selectionValues(for: date),
            date: date,
            dateText: selectedTrendDateText,
            breakdown: breakdown
        )
    }

    private var selectedTrendPoint: HealthTrendCalendarPoint? {
        guard let selectedDate else {
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

    private func isLatestWeightEntry(_ entry: BodyHealthTrendMarkEntry) -> Bool {
        entry.date == weightLatestCalendarDate
    }

    private func isLatestBodyFatEntry(_ entry: BodyHealthTrendMarkEntry) -> Bool {
        entry.date == bodyFatLatestCalendarDate
    }

    private func lineStrokeColor(for color: Color) -> Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    /// Each range's compressed weight/body-fat points. Both series share the
    /// Basics-specific point cap, so the two calls only differ by series.
    static func makePointsByRange(
        for series: HealthTrendSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [BodyHealthTrendRange: [HealthTrendCalendarPoint]] {
        var pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]] = [:]
        for range in BodyHealthTrendRange.allCases {
            pointsByRange[range] = series.lineChartCalendarPoints(
                to: range,
                calendar: calendar,
                date: date,
                maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
            )
        }
        return pointsByRange
    }

    private static func paddedDomain(from points: [HealthTrendCalendarPoint]) -> ClosedRange<Double> {
        let finiteValues = points.compactMap(\.value).filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.05, 1)
            let lower = max(0, minimum - padding)
            return lower...max(maximum + padding, lower + 1)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        let lower = max(0, minimum - padding)
        return lower...max(maximum + padding, lower + 1)
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

    private func selectionValues(for date: Date) -> [BodyChartSelectionValue] {
        var values: [BodyChartSelectionValue] = []

        if let point = bodyFatFinitePointsByDate[date], let value = point.value {
            values.append(BodyChartSelectionValue(
                title: String(localized: "Body Fat"),
                value: bodyFatFormatter(value),
                color: bodyFatColor
            ))
        }

        if let point = weightFinitePointsByDate[date], let value = point.value {
            values.append(BodyChartSelectionValue(
                title: String(localized: "Weight"),
                value: weightFormatter(value),
                color: weightColor
            ))
        }

        return values
    }

    /// The day's individual records under its averages, titled by their time
    /// and in time order. A body fat and a weight record taken in the same
    /// minute (one weigh-in on a smart scale) share a row, two dots and
    /// "fat, weight", to keep the callout short.
    /// Only for a single-day point where a measure has more than one record: a
    /// lone record IS the average, and a 6 Months/Year bucket would list dozens.
    private func selectionBreakdown(for date: Date) -> [BodyChartSelectionValue] {
        let calendar = Calendar.bodyGregorian
        func records(in samples: HealthTrendSeries, for point: HealthTrendCalendarPoint?) -> [HealthTrendDataPoint] {
            guard let point, calendar.isDate(point.startDate, inSameDayAs: point.endDate) else {
                return []
            }
            return samples.points.filter { calendar.isDate($0.date, inSameDayAs: point.date) }
        }
        let bodyFatRecords = records(in: bodyFatSamples, for: bodyFatFinitePointsByDate[date])
        let weightRecords = records(in: weightSamples, for: weightFinitePointsByDate[date])
        guard bodyFatRecords.count > 1 || weightRecords.count > 1 else {
            return []
        }

        func minute(_ date: Date) -> Date {
            calendar.dateInterval(of: .minute, for: date)?.start ?? date
        }
        var style = Date.FormatStyle().hour().minute()
        style.timeZone = calendar.timeZone
        var unpairedWeights = weightRecords
        var rows: [(date: Date, value: BodyChartSelectionValue)] = []
        for bodyFat in bodyFatRecords {
            let time = bodyFat.date.formatted(style)
            if let index = unpairedWeights.firstIndex(where: { minute($0.date) == minute(bodyFat.date) }) {
                let weight = unpairedWeights.remove(at: index)
                rows.append((bodyFat.date, BodyChartSelectionValue(
                    title: time,
                    value: bodyFatFormatter(bodyFat.value) + ", " + weightFormatter(weight.value),
                    color: bodyFatColor,
                    secondaryColor: weightColor
                )))
            } else {
                rows.append((bodyFat.date, BodyChartSelectionValue(title: time, value: bodyFatFormatter(bodyFat.value), color: bodyFatColor)))
            }
        }
        for weight in unpairedWeights {
            rows.append((weight.date, BodyChartSelectionValue(title: weight.date.formatted(style), value: weightFormatter(weight.value), color: weightColor)))
        }
        return rows.sorted { $0.date < $1.date }.map(\.value)
    }
}


struct BodyBasicsBodyMassIndexTrendChart: View {
    let selectedRange: BodyHealthTrendRange
    let color: Color
    let valueFormatter: (Double) -> String

    private let markEntries: [BodyHealthTrendMarkEntry]
    private let lineSegments: [BodyHealthTrendLineSegmentMark]
    private let finitePoints: [HealthTrendCalendarPoint]
    private let samples: HealthTrendSeries
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestCalendarDate: Date?

    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        series: HealthTrendSeries,
        samples: HealthTrendSeries = .empty,
        selectedRange: BodyHealthTrendRange,
        color: Color,
        valueFormatter: @escaping (Double) -> String,
        pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]? = nil
    ) {
        self.selectedRange = selectedRange
        self.color = color
        self.valueFormatter = valueFormatter
        self.samples = samples

        // Every range's points, not just the selected one: dates outside the
        // current range stay resident as invisible placeholder marks, so a
        // range switch morphs the shared dates in place and fades the rest
        // instead of replacing the whole chart.
        let pointsByRange = pointsByRange ?? Self.makePointsByRange(for: series)
        let points = pointsByRange[selectedRange] ?? []
        self.markEntries = BodyHealthMetricTrendChart.makeTrendMarkEntries(
            selectedRange: selectedRange,
            pointsByRange: pointsByRange
        )
        self.lineSegments = BodyHealthMetricTrendChart.makeTrendLineSegments(
            selectedRange: selectedRange,
            pointsByRange: pointsByRange
        )
        self.finitePoints = points.filter { $0.value?.isFinite == true }
        self.chartYDomain = Self.computeYDomain(from: points)

        let domainDates = series.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: false)

        self.latestCalendarDate = points.last { $0.value?.isFinite == true }?.date
    }

    var body: some View {
        Chart {
            // Per-pair segments instead of one LineMark run: Swift Charts
            // cannot interpolate a single line whose vertex set changes across
            // a range switch — unmatched vertices freeze, then pop. Paired
            // segments that exist in both ranges stretch in place; the rest
            // fade at opacity 0.
            ForEach(lineSegments) { segment in
                LineMark(
                    x: .value("Date", segment.startDate, unit: .day),
                    y: .value("BMI", segment.startValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor)
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)

                LineMark(
                    x: .value("Date", segment.endDate, unit: .day),
                    y: .value("BMI", segment.endValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(lineStrokeColor)
                .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                // Both endpoints, or VoiceOver still reads the second half of
                // an invisible off-range segment.
                .accessibilityHidden(segment.isPlaceholder)
            }

            if selectedRange.showsPointMarks {
                ForEach(markEntries) { entry in
                    if let value = entry.dotValue {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("BMI", value)
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: color,
                                    isCurrent: isLatestEntry(entry),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                                // Inside the symbol view, not a mark modifier — Charts
                                // does not apply mark opacity to custom `.symbol {}`
                                // content, which would leave the placeholders visible.
                                .opacity(entry.showsDot ? 1 : 0)
                            }
                            // Opacity is only visual: an off-range placeholder
                            // would still be announced.
                            .accessibilityHidden(!entry.showsDot)
                        } else {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value("BMI", value)
                            )
                            .foregroundStyle(color)
                            .symbolSize(28)
                            .opacity(entry.showsDot ? 1 : 0)
                            .accessibilityHidden(!entry.showsDot)
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
                        selectionAnnotation(for: selectedPoint, value: selectedValue)
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
        .bodyChartHoldToScrub($selectedDate)
        .bodyChartScrubHaptics(selection: selectedPoint?.date)
        // Stable across range switches: a per-range id would replace the chart
        // instead of updating it, popping every mark rather than letting them
        // morph.
        .id("basics-body-mass-index")
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        // Keyed on the range ONLY: a broader key would also animate scrub-mark
        // removal.
        .animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)
        .onChange(of: selectedRange) {
            selectedDate = nil
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedPoint: HealthTrendCalendarPoint? {
        guard let selectedDate else {
            return nil
        }

        return finitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private func isLatestEntry(_ entry: BodyHealthTrendMarkEntry) -> Bool {
        entry.date == latestCalendarDate
    }

    private var lineStrokeColor: Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private func selectionAnnotation(for selectedPoint: HealthTrendCalendarPoint, value: Double) -> BodyChartSelectionAnnotation {
        let breakdown = selectionBreakdown(for: selectedPoint)
        return BodyChartSelectionAnnotation(
            eyebrow: breakdown.isEmpty ? nil : String(localized: "DAILY AVG"),
            values: [
                BodyChartSelectionValue(
                    title: nil,
                    value: valueFormatter(value),
                    color: color
                )
            ],
            date: selectedPoint.date,
            dateText: bodyChartSelectionDateText(for: selectedPoint),
            breakdown: breakdown
        )
    }

    /// The day's individual records under its average, like the Weight and Body
    /// Fat chart's: only for a single-day point with more than one record.
    private func selectionBreakdown(for point: HealthTrendCalendarPoint) -> [BodyChartSelectionValue] {
        let calendar = Calendar.bodyGregorian
        guard calendar.isDate(point.startDate, inSameDayAs: point.endDate) else {
            return []
        }
        let records = samples.points.filter { calendar.isDate($0.date, inSameDayAs: point.date) }
        guard records.count > 1 else {
            return []
        }
        var style = Date.FormatStyle().hour().minute()
        style.timeZone = calendar.timeZone
        return records.map {
            BodyChartSelectionValue(title: $0.date.formatted(style), value: valueFormatter($0.value), color: color)
        }
    }

    /// Each range's BMI points.
    static func makePointsByRange(
        for series: HealthTrendSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [BodyHealthTrendRange: [HealthTrendCalendarPoint]] {
        var pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]] = [:]
        for range in BodyHealthTrendRange.allCases {
            pointsByRange[range] = series.lineChartCalendarPoints(to: range, calendar: calendar, date: date)
        }
        return pointsByRange
    }

    private static func computeYDomain(from points: [HealthTrendCalendarPoint]) -> ClosedRange<Double> {
        let values = points.compactMap(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.05, 1)
            let lower = max(0, minimum - padding)
            return lower...max(maximum + padding, lower + 1)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        let lower = max(0, minimum - padding)
        return lower...max(maximum + padding, lower + 1)
    }
}

/// Every weight and body fat sample scattered by the time of day it was taken,
/// over the selected range, showing when in the day the user tends to measure.
/// One plot, two Y axes (weight leading, body fat trailing): each measure is
/// normalized into its own whole-number domain, like `BodyBasicsTrendChart`.
struct BodyBasicsTimeOfDayChart: View {
    let weightSamples: HealthTrendSeries
    let bodyFatSamples: HealthTrendSeries
    let weightColor: Color
    let bodyFatColor: Color
    let weightFormatter: (Double) -> String
    let bodyFatFormatter: (Double) -> String
    var calendar: Calendar = .bodyGregorian

    @State private var selectedHour: Double?

    private struct Dot: Identifiable {
        let date: Date
        let isWeight: Bool
        let hour: Double
        let value: Double
        let plotValue: Double

        var id: String {
            "\(isWeight)-\(date.timeIntervalSinceReferenceDate)"
        }
    }

    /// Thirds, so the four ticks of a domain whose span is a multiple of 3
    /// all land on whole numbers.
    private let axisTickValues = [0.0, 1.0 / 3, 2.0 / 3, 1.0]

    var body: some View {
        let weightDomain = Self.wholeNumberDomain(for: weightSamples)
        let bodyFatDomain = Self.wholeNumberDomain(for: bodyFatSamples)
        let dots = dots(from: bodyFatSamples, isWeight: false, domain: bodyFatDomain)
            + dots(from: weightSamples, isWeight: true, domain: weightDomain)
        // Nearest in time of day, like the date scrub on the trend charts, plus
        // the other measure's record from the same minute (one weigh-in).
        let nearest = selectedHour.flatMap { hour in
            dots.min { abs($0.hour - hour) < abs($1.hour - hour) }
        }
        let selectedDots = nearest.map { nearest in
            dots.filter { $0.id == nearest.id || ($0.isWeight != nearest.isWeight && minute($0.date) == minute(nearest.date)) }
        } ?? []

        Chart {
            ForEach(dots) { dot in
                PointMark(
                    x: .value("Time of Day", dot.hour),
                    y: .value("Value", dot.plotValue)
                )
                .foregroundStyle((dot.isWeight ? weightColor : bodyFatColor).opacity(0.55))
                .symbolSize(28)
            }

            if let nearest {
                RuleMark(x: .value("Selected Time", nearest.hour))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        BodyChartSelectionAnnotation(
                            eyebrow: nil,
                            values: selectedDots.map { dot in
                                BodyChartSelectionValue(
                                    title: dot.isWeight ? String(localized: "Weight") : String(localized: "Body Fat"),
                                    value: dot.isWeight ? weightFormatter(dot.value) : bodyFatFormatter(dot.value),
                                    color: dot.isWeight ? weightColor : bodyFatColor
                                )
                            },
                            date: nearest.date,
                            dateText: dateText(nearest.date)
                        )
                    }

                ForEach(selectedDots) { dot in
                    PointMark(
                        x: .value("Selected Time", dot.hour),
                        y: .value("Value", dot.plotValue)
                    )
                    .foregroundStyle(dot.isWeight ? weightColor : bodyFatColor)
                    .symbolSize(82)
                }
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: -0.08...1.08)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let hour = value.as(Double.self) {
                        Text(hourLabel(hour))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            if let weightDomain {
                AxisMarks(position: .leading, values: axisTickValues) { value in
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.18))
                    AxisTick()
                        .foregroundStyle(weightColor.opacity(0.55))
                    AxisValueLabel {
                        if let yValue = value.as(Double.self) {
                            axisLabel(yValue, in: weightDomain)
                        }
                    }
                }
            }

            if let bodyFatDomain {
                AxisMarks(position: .trailing, values: axisTickValues) { value in
                    if weightDomain == nil {
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                    }
                    AxisTick()
                        .foregroundStyle(bodyFatColor.opacity(0.55))
                    AxisValueLabel {
                        if let yValue = value.as(Double.self) {
                            axisLabel(yValue, in: bodyFatDomain)
                        }
                    }
                }
            }
        }
        .bodyChartHoldToScrub($selectedHour, isEnabled: !dots.isEmpty)
        .bodyChartScrubHaptics(selection: nearest?.id)
    }

    /// Whole numbers only, no unit: the legend above the plot names each side.
    private func axisLabel(_ normalizedValue: Double, in domain: ClosedRange<Double>) -> some View {
        let value = domain.lowerBound + (domain.upperBound - domain.lowerBound) * normalizedValue
        return Text(BodyValueFormat.numberText(value.rounded(), decimals: 0))
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.secondary)
    }

    private func dots(from samples: HealthTrendSeries, isWeight: Bool, domain: ClosedRange<Double>?) -> [Dot] {
        guard let domain else {
            return []
        }
        return samples.points.filter(\.value.isFinite).map { point in
            let parts = calendar.dateComponents([.hour, .minute], from: point.date)
            return Dot(
                date: point.date,
                isWeight: isWeight,
                hour: Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60,
                value: point.value,
                plotValue: (point.value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
            )
        }
    }

    private func minute(_ date: Date) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }

    private func dateText(_ date: Date) -> String {
        var style = Date.FormatStyle().month(.abbreviated).day().year().hour().minute()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    private func hourLabel(_ hour: Double) -> String {
        let date = calendar.date(bySettingHour: Int(hour) % 24, minute: 0, second: 0, of: Date()) ?? Date()
        var style = Date.FormatStyle().hour()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// Whole-number bounds around the samples whose span is a multiple of 3,
    /// so every `axisTickValues` tick reads as a whole number. `nil` when empty.
    static func wholeNumberDomain(for samples: HealthTrendSeries) -> ClosedRange<Double>? {
        let values = samples.points.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return nil
        }
        let lower = minimum.rounded(.down)
        let span = max(((maximum - lower) / 3).rounded(.up) * 3, 3)
        return lower...(lower + span)
    }
}
