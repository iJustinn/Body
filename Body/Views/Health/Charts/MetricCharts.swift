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
    /// When true the line plots each reading on its own day rather than
    /// averaging readings into the range's buckets — see
    /// `HealthMetricKind.usesSparseTrendReadings`. Line style only; `false`
    /// keeps every existing caller's chart unchanged.
    let usesSparseReadings: Bool
    /// Values the Y domain must cover regardless of what was plotted, so a
    /// reference frame stays on screen in every range (Cardio Fitness passes its
    /// four level boundaries, so the line's place among the levels reads the
    /// same way whichever range is selected). Empty leaves the domain to the data.
    let additionalDomainValues: [Double]
    /// Drops the Y axis's number labels while keeping its grid lines. For a
    /// metric read against named levels rather than against absolute numbers,
    /// the axis figures are noise.
    let hidesYAxisLabels: Bool

    private let visibleFinitePoints: [HealthTrendCalendarPoint]
    private let markEntries: [BodyHealthTrendMarkEntry]
    private let lineSegments: [BodyHealthTrendLineSegmentMark]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestVisibleCalendarDate: Date?
    private let currentValueRestingValue: Double?
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
        usesSparseReadings: Bool = false,
        additionalDomainValues: [Double] = [],
        hidesYAxisLabels: Bool = false,
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
        self.usesSparseReadings = usesSparseReadings
        self.additionalDomainValues = additionalDomainValues
        self.hidesYAxisLabels = hidesYAxisLabels
        self.chartIdentity = chartIdentity

        // Every range's points, not just the selected one: dates outside the
        // current range become invisible placeholder marks, so switching
        // ranges morphs shared dates in place and fades the rest instead of
        // replacing the whole mark set.
        var pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]] = [:]
        for range in BodyHealthTrendRange.allCases {
            switch chartStyle {
            case .line:
                // Sparse metrics keep each reading on its own day; bucketing
                // them would shift a point days away from when it was measured.
                // Either path still emits one entry per date, which is all the
                // range morph needs to match marks across a range switch.
                pointsByRange[range] = usesSparseReadings
                    ? series.sparseLineChartCalendarPoints(to: range)
                    : series.lineChartCalendarPoints(to: range)
            case .bar:
                pointsByRange[range] = series.chartCalendarPoints(to: range)
            }
        }
        let calendarPoints = pointsByRange[selectedRange] ?? []
        self.visibleFinitePoints = calendarPoints.filter { $0.value?.isFinite == true }
        let markEntries = Self.makeTrendMarkEntries(
            selectedRange: selectedRange,
            pointsByRange: pointsByRange
        )
        self.markEntries = markEntries
        self.currentValueRestingValue = Self.currentValueRestingValue(
            for: currentValuePoint,
            markEntries: markEntries
        )
        self.lineSegments = chartStyle == .line
            ? Self.makeTrendLineSegments(selectedRange: selectedRange, pointsByRange: pointsByRange)
            : []

        let aggregatedValues = calendarPoints.compactMap(\.value).filter(\.isFinite)
        let fallbackValues = series.limited(to: selectedRange).points.map(\.value).filter(\.isFinite)
        let highlightedRangeValues = highlightedRange?.domainValues ?? []
        let baselineDomainValues = baselineValue.map { [$0] } ?? []
        // Only where the dot is drawn: the caller now passes it for every range
        // so it can morph, and the off-week ranges must keep the domain they
        // had when they received nil.
        let currentValueDomainValues = selectedRange == .recentWeek
            ? (currentValuePoint.map { [$0.value] } ?? [])
            : []
        let domainValues = (aggregatedValues.isEmpty ? fallbackValues : aggregatedValues)
            + highlightedRangeValues
            + baselineDomainValues
            + currentValueDomainValues
            // Folded in alongside the data rather than replacing it, so a
            // reading outside the reference frame still can't be clipped.
            + additionalDomainValues.filter(\.isFinite)
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

    // Scrubbed point first; then the current-value dot, but only while it is
    // visible (the caller passes it for every range so it can morph — off the
    // week range it must not feed the band); otherwise the last plotted point
    // of the selected range, so the band tracks the line the user is looking
    // at. An empty chart reports nil so the band falls back to the caller's
    // `highlightedRange`.
    private var activeHighlightSourceValue: Double? {
        if let selectedTrendPoint {
            return selectedTrendPoint.value
        }
        if showsCurrentValueDot, let currentValuePoint {
            return currentValuePoint.value
        }
        return visibleFinitePoints.last?.value
    }

    /// The dot belongs to the week chart only. Other ranges keep it resident at
    /// opacity 0 — removing the mark pops it on a range switch.
    private var showsCurrentValuePoint: Bool {
        selectedRange == .recentWeek
    }

    /// Visible on the week chart while nothing is scrubbed. Otherwise the dot
    /// stays resident and parks on the start-of-day point — see
    /// `currentValueDotPlotValue`.
    private var showsCurrentValueDot: Bool {
        showsCurrentValuePoint && selectedTrendPoint == nil
    }

    /// Where the dot plots: its own live value while it shows, the start-of-day
    /// point it climbs back into while it does not.
    private var currentValueDotPlotValue: Double? {
        guard let currentValuePoint else {
            return nil
        }

        return showsCurrentValueDot ? currentValuePoint.value : currentValueRestingValue
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

                switch chartStyle {
                case .line:
                    // Per-pair segments instead of one LineMark run: Swift
                    // Charts cannot interpolate a single line whose vertex set
                    // changes across a range switch — unmatched vertices
                    // freeze, then pop. Paired segments that exist in both
                    // ranges stretch in place; the rest fade at opacity 0.
                    ForEach(lineSegments) { segment in
                        LineMark(
                            x: .value("Date", segment.startDate, unit: .day),
                            y: .value(title, segment.startValue),
                            series: .value("Segment", segment.id)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(lineChartStrokeColor)
                        .lineStyle(StrokeStyle(lineWidth: lineChartStrokeWidth, lineCap: .round, lineJoin: .round))
                        .opacity(segment.isPlaceholder ? 0 : 1)
                        .accessibilityHidden(segment.isPlaceholder)

                        LineMark(
                            x: .value("Date", segment.endDate, unit: .day),
                            y: .value(title, segment.endValue),
                            series: .value("Segment", segment.id)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(lineChartStrokeColor)
                        .lineStyle(StrokeStyle(lineWidth: lineChartStrokeWidth, lineCap: .round, lineJoin: .round))
                        .opacity(segment.isPlaceholder ? 0 : 1)
                        // Both endpoints, or VoiceOver still reads the second
                        // half of an invisible off-range segment.
                        .accessibilityHidden(segment.isPlaceholder)
                    }

                    if selectedRange.showsPointMarks {
                        ForEach(markEntries) { entry in
                            // `dotValue` also covers a selected-range day with
                            // no reading whose date carries another range's
                            // value: the dot stays resident but invisible, so
                            // selecting that range fades it in where it belongs
                            // instead of inserting it.
                            if let value = entry.dotValue {
                                if selectedRange.usesPreviewLineChartStyle {
                                    PointMark(
                                        x: .value("Date", entry.date, unit: .day),
                                        y: .value(title, value)
                                    )
                                    .symbol {
                                        BodyLineChartPreviewPointSymbol(
                                            tintColor: symbolColor,
                                            isCurrent: isLatestVisiblePoint(entry),
                                            pointDiameter: selectedRange.linePointDiameter,
                                            currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                        )
                                        // Inside the symbol view, not a mark modifier — Charts
                                        // does not apply mark opacity to custom `.symbol {}`
                                        // content, which would leave the placeholders visible.
                                        .opacity(entry.showsDot ? 1 : 0)
                                    }
                                    // Opacity is only visual: an off-range
                                    // placeholder would still be announced.
                                    .accessibilityHidden(!entry.showsDot)
                                } else {
                                    PointMark(
                                        x: .value("Date", entry.date, unit: .day),
                                        y: .value(title, value)
                                    )
                                    .foregroundStyle(symbolColor)
                                    .symbolSize(28)
                                    .opacity(entry.showsDot ? 1 : 0)
                                    .accessibilityHidden(!entry.showsDot)
                                }
                            }
                        }
                    }
                case .bar:
                    ForEach(markEntries) { entry in
                        if let value = entry.value {
                            BarMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, value),
                                width: .fixed(chartBarWidth)
                            )
                            .foregroundStyle(symbolColor.gradient)
                            .cornerRadius(4)
                            .opacity(entry.isPlaceholder ? 0 : 1)
                            .accessibilityHidden(entry.isPlaceholder)
                        } else {
                            BarMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, placeholderBarYValue),
                                width: .fixed(chartBarWidth)
                            )
                            .foregroundStyle(Color.secondary.opacity(0.14))
                            .cornerRadius(4)
                            .opacity(entry.isPlaceholder ? 0 : 1)
                            .accessibilityHidden(entry.isPlaceholder)
                        }
                    }
                }

                // Resident on every range and hidden by opacity, never removed:
                // dropping the mark off the week range pops it on a switch.
                // Hidden while a scrub callout is up — the band follows the
                // scrubbed point then, and the dot would clutter the rule line —
                // and hidden off the week range. Both hidden states park it on
                // the start-of-day point directly above it, so it climbs back
                // into that dot as it fades instead of blinking out where it
                // stood; the reverse plays when it comes back.
                if chartStyle == .line, let currentValuePoint, let plotValue = currentValueDotPlotValue {
                    PointMark(
                        x: .value("Date", currentValuePoint.date, unit: .day),
                        y: .value(title, plotValue)
                    )
                    .symbol {
                        Circle()
                            .fill(symbolColor.opacity(0.8))
                            .frame(
                                width: selectedRange.lineCurrentPointDiameter,
                                height: selectedRange.lineCurrentPointDiameter
                            )
                            // Inside the symbol view, not a mark modifier —
                            // Charts does not apply mark opacity to custom
                            // `.symbol {}` content.
                            .opacity(showsCurrentValueDot ? 1 : 0)
                    }
                    .accessibilityHidden(!showsCurrentValueDot)
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
                        if !hidesYAxisLabels {
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
            }
            .chartXSelection(value: $selectedDate)
            .simultaneousGesture(chartPressGesture)
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            // Keyed on the range ONLY: a broader key would also animate
            // scrub-mark removal (see the lingering-dot note on the band
            // animation above).
            .animation(reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0), value: selectedRange)
            // The current-value dot's park/unpark morph. Keyed on that flag
            // alone — a scrub's own marks (rule, callout, fat selection dot) are
            // inserted, and Charts pops insertions whether or not the
            // transaction is animated. Shorter than the range morph so the dot
            // is out of the callout's way promptly; on a range switch both keys
            // change and the inner range animation wins, keeping the dot on the
            // same curve as the marks it travels with.
            .animation(reduceMotion ? nil : .smooth(duration: 0.3, extraBounce: 0), value: showsCurrentValueDot)
            .onChange(of: selectedRange) {
                selectedDate = nil
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

    // Placeholders can never match: `latestVisibleCalendarDate` is a
    // current-range date, and placeholder entries are exactly the dates that
    // are not.
    private func isLatestVisiblePoint(_ entry: BodyHealthTrendMarkEntry) -> Bool {
        entry.date == latestVisibleCalendarDate
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

    /// One mark per distinct date across ALL ranges' calendar points. Dates
    /// outside the selected range become invisible placeholders carrying their
    /// owning range's value, so a range switch fades those marks in/out at
    /// their true geometry instead of popping them; shared dates (today ends
    /// every range) morph value-to-value. A date present in several ranges
    /// resolves to the selected range's point first, then in fixed
    /// `BodyHealthTrendRange.allCases` order (Week → Month → 6M → Year). A
    /// selected-range day with no reading keeps its slot but borrows another
    /// range's value as `offRangeValue`, so line style still has a dot to
    /// morph — see `BodyHealthTrendMarkEntry.dotValue`.
    /// Where the current-value dot parks while it is hidden: the dot plotted at
    /// its own date — today's start-of-day point on the week chart, the
    /// aggregated point that absorbed today on the longer ranges — so hiding it
    /// plays as a climb back into that dot rather than a blink. Falls back to
    /// the dot's own value, parking it in place, when its date carries no
    /// plotted point at all.
    static func currentValueRestingValue(
        for currentValuePoint: (date: Date, value: Double)?,
        markEntries: [BodyHealthTrendMarkEntry]
    ) -> Double? {
        guard let currentValuePoint else {
            return nil
        }

        return markEntries.first { $0.date == currentValuePoint.date }?.dotValue
            ?? currentValuePoint.value
    }

    static func makeTrendMarkEntries(
        selectedRange: BodyHealthTrendRange,
        pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]
    ) -> [BodyHealthTrendMarkEntry] {
        var entriesByDate: [Date: BodyHealthTrendMarkEntry] = [:]
        for point in pointsByRange[selectedRange] ?? [] {
            entriesByDate[point.date] = BodyHealthTrendMarkEntry(
                date: point.date,
                value: point.value,
                isPlaceholder: false
            )
        }
        for range in BodyHealthTrendRange.allCases where range != selectedRange {
            for point in pointsByRange[range] ?? [] {
                guard var entry = entriesByDate[point.date] else {
                    entriesByDate[point.date] = BodyHealthTrendMarkEntry(
                        date: point.date,
                        value: point.value,
                        isPlaceholder: true
                    )
                    continue
                }
                // The date is taken, but a day with no reading draws no dot —
                // common for today's still-incomplete data, which longer
                // ranges already aggregate. Borrow that range's value as
                // invisible dot geometry so the dot morphs in instead of
                // popping; the entry itself stays put, keeping its gray
                // no-data bar in bar style.
                guard entry.value == nil,
                      entry.offRangeValue == nil,
                      point.value?.isFinite == true else {
                    continue
                }
                entry.offRangeValue = point.value
                entriesByDate[point.date] = entry
            }
        }
        return entriesByDate.values.sorted { $0.date < $1.date }
    }

    /// The trend line split into one two-point series per consecutive-finite
    /// pair, keyed by the pair's start date. A Week pair d→d+1 and a
    /// compressed Month pair d→d+2 share id `seg-d`, so the segment stretches
    /// in place across the switch. Other ranges' pair starts with no
    /// selected-range counterpart collapse to zero-length placeholders at
    /// their own start point, fading where they stood. Ids dedupe with
    /// selected-range priority, then fixed `allCases` order.
    static func makeTrendLineSegments(
        selectedRange: BodyHealthTrendRange,
        pointsByRange: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]
    ) -> [BodyHealthTrendLineSegmentMark] {
        func finitePoints(for range: BodyHealthTrendRange) -> [HealthTrendCalendarPoint] {
            (pointsByRange[range] ?? []).filter { $0.value?.isFinite == true }
        }

        var segmentsByID: [String: BodyHealthTrendLineSegmentMark] = [:]
        let selectedFinite = finitePoints(for: selectedRange)
        for (start, end) in zip(selectedFinite, selectedFinite.dropFirst()) {
            guard let startValue = start.value, let endValue = end.value else {
                continue
            }
            let segment = BodyHealthTrendLineSegmentMark(
                startDate: start.date,
                startValue: startValue,
                endDate: end.date,
                endValue: endValue,
                isPlaceholder: false
            )
            segmentsByID[segment.id] = segment
        }

        for range in BodyHealthTrendRange.allCases where range != selectedRange {
            for start in finitePoints(for: range).dropLast() {
                guard let startValue = start.value else {
                    continue
                }
                let placeholder = BodyHealthTrendLineSegmentMark(
                    startDate: start.date,
                    startValue: startValue,
                    endDate: start.date,
                    endValue: startValue,
                    isPlaceholder: true
                )
                if segmentsByID[placeholder.id] == nil {
                    segmentsByID[placeholder.id] = placeholder
                }
            }
        }

        return segmentsByID.values.sorted { $0.startDate < $1.startDate }
    }
}



struct BodyHealthMetricDayContextInterval: Identifiable, Equatable {
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
    /// Index within this interval's (kind, title) group, assigned by
    /// `BodyHealthMetricDayChart.assigningOrdinals(to:)`. Defaults to 0 so
    /// callers keep building intervals without one.
    var ordinal: Int = 0

    var id: String {
        "\(kind)-\(title)-\(ordinal)"
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
    private let lineSegments: [BodyHealthMetricDayLineSegmentMark]
    private let pointMarkEntries: [BodyHealthMetricDayChartEntry]
    private let finiteEntries: [BodyHealthMetricDayChartEntry]
    private let primaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let secondaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestBucketDate: Date?
    private let latestSecondaryBucketDate: Date?
    private let dayStart: Date

    /// Also drawn by `BodyMetricWarningCard`, so a warning's readings match the
    /// Day View chart they sit under.
    static let pointDiameter: CGFloat = 8
    static let currentPointDiameter: CGFloat = 10
    private static let segmentGapThreshold: TimeInterval = 4 * 60 * 60
    /// Jan 1 2001 — a day with no DST transition anywhere. Every mark plots
    /// into this fixed day (see `normalizedPlotDate(for:dayStart:)`) so the x
    /// domain never moves across day switches.
    private static let referenceDayStart = Calendar.bodyGregorian.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    init(
        series: HealthTrendSeries,
        secondarySeries: HealthTrendSeries = .empty,
        // Whether a second source is being compared at all, which an empty
        // `secondarySeries` cannot say: it reads the same whether no second
        // source is picked or the picked one is simply silent today. Only the
        // second case wants placeholder marks to fade the previous day's line
        // and dots out.
        hasConfiguredSecondary: Bool = false,
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
        self.contextIntervals = Self.assigningOrdinals(to: contextIntervals)
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
        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: day)
        self.dayStart = dayStart
        let configuredRoles: Set<BodyHealthSourceRole> = hasConfiguredSecondary ? [.primary, .secondary] : [.primary]
        self.lineSegments = Self.makeLineSegments(
            from: allEntries,
            dayStart: dayStart,
            configuredRoles: configuredRoles
        )
        let visibleDots = collapsesUnchangedPoints
            ? Self.collapsingUnchangedRunPoints(allEntries)
            : allEntries
        self.pointMarkEntries = Self.addingPlaceholderDots(
            to: visibleDots,
            fullEntries: allEntries,
            dayStart: dayStart,
            configuredRoles: configuredRoles
        )
        self.finiteEntries = allEntries.filter { $0.averageValue.isFinite }
        self.primaryEntriesByDate = Dictionary(uniqueKeysWithValues: primaryEntries.map { ($0.plotDate, $0) })
        self.secondaryEntriesByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.map { ($0.plotDate, $0) })
        self.chartYDomain = Self.computeYDomain(
            from: buckets + secondaryBuckets,
            rangeEntries: rangeEntries
        )

        self.chartXDomain = Self.referenceDayStart...Self.referenceDayStart.addingTimeInterval(86_400)
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
                    xStart: .value("\(interval.title) Start", normalizedDate(interval.startDate)),
                    xEnd: .value("\(interval.title) End", normalizedDate(interval.endDate)),
                    yStart: .value("Context Minimum", chartYDomain.lowerBound),
                    yEnd: .value("Context Maximum", chartYDomain.upperBound)
                )
                .foregroundStyle(interval.color.opacity(interval.kind == .sleep ? 0.14 : 0.10))

                RectangleMark(
                    xStart: .value("\(interval.title) Top Start", normalizedDate(interval.startDate)),
                    xEnd: .value("\(interval.title) Top End", normalizedDate(interval.endDate)),
                    yStart: .value("Context Top Start", contextTopLineLowerBound),
                    yEnd: .value("Context Top End", chartYDomain.upperBound)
                )
                .foregroundStyle(interval.color)

                PointMark(
                    x: .value("\(interval.title) Label", normalizedDate(interval.midpointDate)),
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
                        x: .value("Time", normalizedDate(entry.plotDate)),
                        y: .value(title, entry.lowValue)
                    )
                    .symbolSize(bodyRangeChartPointSymbolSize(forBarWidth: rangeBarWidth))
                    .foregroundStyle(Self.rangeBarColor)
                } else {
                    BarMark(
                        x: .value("Time", normalizedDate(entry.plotDate)),
                        yStart: .value("Low \(title)", entry.lowValue),
                        yEnd: .value("High \(title)", entry.highValue),
                        width: .fixed(rangeBarWidth)
                    )
                    .foregroundStyle(Self.rangeBarColor)
                    .cornerRadius(rangeBarWidth / 2)
                }
            }

            ForEach(lineSegments) { segment in
                LineMark(
                    x: .value("Time", normalizedDate(segment.startPlotDate)),
                    y: .value(title, segment.startValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: segment.sourceRole))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)

                LineMark(
                    x: .value("Time", normalizedDate(segment.endPlotDate)),
                    y: .value(title, segment.endValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: segment.sourceRole))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)
            }

            ForEach(pointMarkEntries) { entry in
                PointMark(
                    x: .value("Time", normalizedDate(entry.plotDate)),
                    y: .value(title, entry.averageValue)
                )
                .symbol {
                    BodyLineChartPreviewPointSymbol(
                        tintColor: color(for: entry),
                        isCurrent: isLatestEntry(entry),
                        pointDiameter: Self.pointDiameter,
                        currentPointDiameter: Self.currentPointDiameter
                    )
                    // Inside the symbol view, not a mark modifier — Charts
                    // does not apply mark opacity to custom `.symbol {}`
                    // content, which would leave the placeholders visible.
                    .opacity(entry.isPlaceholder ? 0 : 1)
                }
                // Opacity is only visual: the hour-filling placeholders would
                // otherwise be announced as real readings.
                .accessibilityHidden(entry.isPlaceholder)
            }

            if let selectedBucket {
                RuleMark(x: .value("Selected Time", normalizedDate(selectedBucket.plotDate)))
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
                        x: .value("Selected Time", normalizedDate(entry.plotDate)),
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

        // The chart selection reports a reference-day date; map it back onto
        // the real day before comparing against the entries' real plot dates.
        let realSelectedDate = dayStart.addingTimeInterval(selectedDate.timeIntervalSince(Self.referenceDayStart))
        return finiteEntries.min { first, second in
            abs(first.plotDate.timeIntervalSince(realSelectedDate)) < abs(second.plotDate.timeIntervalSince(realSelectedDate))
        }
    }

    private func normalizedDate(_ date: Date) -> Date {
        Self.normalizedPlotDate(for: date, dayStart: dayStart)
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
        color(for: entry.sourceRole)
    }

    private func color(for role: BodyHealthSourceRole) -> Color {
        role == .primary ? color : secondaryColor
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

    /// The selected day's time-of-day offsets, replotted onto the fixed
    /// reference day. The constant x-domain is what lets marks morph in place
    /// across day switches — plotting real dates shifts both the values and
    /// the domain by 24h, which Swift Charts animates as a horizontal slide.
    /// The clamp pins a DST long day's spill past hour 24 to the domain edge.
    static func normalizedPlotDate(for date: Date, dayStart: Date) -> Date {
        referenceDayStart.addingTimeInterval(
            min(max(date.timeIntervalSince(dayStart), 0), 86_400)
        )
    }

    /// Day-stable identity for the context highlight areas: the ordinal is
    /// the interval's index within its (kind, title) group of the start-sorted
    /// array, so a same-type highlight (Sleep↔Sleep, Run↔Run) keeps its id
    /// across day switches and morphs — shrinks or extends in place — while
    /// unmatched types exit/enter with a fade.
    static func assigningOrdinals(
        to intervals: [BodyHealthMetricDayContextInterval]
    ) -> [BodyHealthMetricDayContextInterval] {
        var counts: [String: Int] = [:]
        return intervals.map { interval in
            let key = "\(interval.kind)-\(interval.title)"
            let ordinal = counts[key, default: 0]
            counts[key] = ordinal + 1
            var assigned = interval
            assigned.ordinal = ordinal
            return assigned
        }
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

    /// The hourly-average line, split into one two-point series per
    /// consecutive-reading pair (same ≥4h gap rule as `segmentIndices`), keyed
    /// by the pair's starting hour. Swift Charts cannot interpolate a single
    /// line whose vertex set changes across a day switch — vertices with no
    /// counterpart freeze until the animation ends, then pop. Pair marks that
    /// exist on both days morph in place; hours without a pair carry an
    /// invisible zero-length placeholder (at the hour's own reading if it has
    /// one, else the nearest hour's) so a vanishing stretch of line fades out
    /// where it stood instead of freezing. A source in `configuredRoles` with
    /// no readings today is all placeholders, pinned to the other source's
    /// line, so the line it drew on the previous day fades out too.
    static func makeLineSegments(
        from entries: [BodyHealthMetricDayChartEntry],
        dayStart: Date,
        configuredRoles: Set<BodyHealthSourceRole> = [.primary]
    ) -> [BodyHealthMetricDayLineSegmentMark] {
        let entriesByRole = Dictionary(grouping: entries, by: \.sourceRole)
        let hours = hourIndices(forDayStartingAt: dayStart)
        let anchors = anchorEntriesByHour(in: entries)
        let anchorHours = anchors.keys.sorted()

        return configuredRoles.union(entriesByRole.keys).sorted { $0.rawValue < $1.rawValue }.flatMap { role -> [BodyHealthMetricDayLineSegmentMark] in
            let finite = (entriesByRole[role] ?? [])
                .filter { $0.averageValue.isFinite }
                .sorted { $0.plotDate < $1.plotDate }
            guard !finite.isEmpty else {
                // Nothing of this source's own to fade through, so its hours
                // ride the other source's line — the ids stay in the chart and
                // animate to opacity 0 instead of being dropped and popped.
                return hours.compactMap { hour -> BodyHealthMetricDayLineSegmentMark? in
                    guard let source = anchorEntry(
                        forHour: hour,
                        in: anchors,
                        sortedHours: anchorHours
                    ) else {
                        return nil
                    }
                    let plotDate = dayStart.addingTimeInterval(TimeInterval(hour) * 3_600 + 1_800)
                    return BodyHealthMetricDayLineSegmentMark(
                        sourceRole: role,
                        hourIndex: hour,
                        startPlotDate: plotDate,
                        startValue: source.averageValue,
                        endPlotDate: plotDate,
                        endValue: source.averageValue,
                        isPlaceholder: true
                    )
                }
            }

            var segments: [BodyHealthMetricDayLineSegmentMark] = []
            var pairStartHours = Set<Int>()
            for (start, end) in zip(finite, finite.dropFirst())
            where end.plotDate.timeIntervalSince(start.plotDate) < segmentGapThreshold {
                let hour = start.bucket.hourStart.bodyHourOfDayIndex
                pairStartHours.insert(hour)
                segments.append(
                    BodyHealthMetricDayLineSegmentMark(
                        sourceRole: role,
                        hourIndex: hour,
                        startPlotDate: start.plotDate,
                        startValue: start.averageValue,
                        endPlotDate: end.plotDate,
                        endValue: end.averageValue
                    )
                )
            }

            let finiteByHour = Dictionary(
                finite.map { ($0.bucket.hourStart.bodyHourOfDayIndex, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let finiteHours = finiteByHour.keys.sorted()
            let placeholders = hours
                .filter { !pairStartHours.contains($0) }
                .compactMap { hour -> BodyHealthMetricDayLineSegmentMark? in
                    guard let source = anchorEntry(
                        forHour: hour,
                        in: finiteByHour,
                        sortedHours: finiteHours
                    ) else {
                        return nil
                    }
                    let plotDate = finiteByHour[hour]?.plotDate
                        ?? dayStart.addingTimeInterval(TimeInterval(hour) * 3_600 + 1_800)
                    return BodyHealthMetricDayLineSegmentMark(
                        sourceRole: role,
                        hourIndex: hour,
                        startPlotDate: plotDate,
                        startValue: source.averageValue,
                        endPlotDate: plotDate,
                        endValue: source.averageValue,
                        isPlaceholder: true
                    )
                }
            return segments + placeholders
        }
    }

    /// Every hour of the day carries a dot mark so a cross-day switch animates
    /// opacity instead of inserting or removing marks — Swift Charts pops
    /// those rather than fading them. Hours without a visible dot get an
    /// invisible placeholder pinned at that hour's own value (a collapsed flat
    /// run) or the nearest hour's value, so a dot with no counterpart on the
    /// other day fades in or out in place. A source in `configuredRoles` with
    /// no readings today borrows the other source's values instead, so its
    /// dots fade out where they stood rather than being dropped from the chart
    /// (Swift Charts freezes those, then pops them). With no readings anywhere
    /// there is nothing to fade through and no placeholder is made.
    static func addingPlaceholderDots(
        to visibleEntries: [BodyHealthMetricDayChartEntry],
        fullEntries: [BodyHealthMetricDayChartEntry],
        dayStart: Date,
        configuredRoles: Set<BodyHealthSourceRole> = [.primary]
    ) -> [BodyHealthMetricDayChartEntry] {
        let visibleByRole = Dictionary(grouping: visibleEntries, by: \.sourceRole)
        let fullByRole = Dictionary(grouping: fullEntries, by: \.sourceRole)
        let hours = hourIndices(forDayStartingAt: dayStart)
        let anchors = anchorEntriesByHour(in: fullEntries)

        return configuredRoles.union(fullByRole.keys).sorted { $0.rawValue < $1.rawValue }.flatMap { role -> [BodyHealthMetricDayChartEntry] in
            let visible = visibleByRole[role] ?? []
            let ownFiniteByHour = Dictionary(
                (fullByRole[role] ?? [])
                    .filter { $0.averageValue.isFinite }
                    .map { ($0.bucket.hourStart.bodyHourOfDayIndex, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let finiteByHour = ownFiniteByHour.isEmpty ? anchors : ownFiniteByHour
            guard !finiteByHour.isEmpty else {
                return visible
            }

            let visibleHours = Set(visible.map { $0.bucket.hourStart.bodyHourOfDayIndex })
            let finiteHours = finiteByHour.keys.sorted()
            let placeholders = hours
                .filter { !visibleHours.contains($0) }
                .compactMap { hour -> BodyHealthMetricDayChartEntry? in
                    // A collapsed-away hour fades at its own value; a truly
                    // empty hour borrows the nearest hour's (earlier on ties).
                    guard let source = anchorEntry(
                        forHour: hour,
                        in: finiteByHour,
                        sortedHours: finiteHours
                    ) else {
                        return nil
                    }
                    return BodyHealthMetricDayChartEntry(
                        sourceName: source.sourceName,
                        sourceRole: role,
                        bucket: HealthTrendHourlyBucket(
                            hourStart: dayStart.addingTimeInterval(TimeInterval(hour) * 3_600),
                            averageValue: source.averageValue,
                            samples: []
                        ),
                        segmentIndex: 0,
                        isPlaceholder: true
                    )
                }
            return visible + placeholders
        }
    }

    /// The day's hour indices, taken from the real calendar day so a DST
    /// transition day carries its own 23 or 25 marks — the same elapsed-hour
    /// count the marks' `bodyHourOfDayIndex` keys are built on.
    private static func hourIndices(forDayStartingAt dayStart: Date) -> Range<Int> {
        let nextDayStart = Calendar.bodyGregorian.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let hourCount = Int((nextDayStart.timeIntervalSince(dayStart) / 3_600).rounded())
        return 0..<max(hourCount, 1)
    }

    /// Every role's readings keyed by hour, which is what a configured source
    /// with nothing of its own to plot today pins its placeholders to. Sorted
    /// by role so the anchor for an hour both sources read is stable.
    private static func anchorEntriesByHour(
        in entries: [BodyHealthMetricDayChartEntry]
    ) -> [Int: BodyHealthMetricDayChartEntry] {
        Dictionary(
            entries
                .filter { $0.averageValue.isFinite }
                .sorted { ($0.sourceRole.rawValue, $0.plotDate) < ($1.sourceRole.rawValue, $1.plotDate) }
                .map { ($0.bucket.hourStart.bodyHourOfDayIndex, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// The reading a placeholder at `hour` fades through: that hour's own, or
    /// the nearest hour's (earlier on ties).
    private static func anchorEntry(
        forHour hour: Int,
        in entriesByHour: [Int: BodyHealthMetricDayChartEntry],
        sortedHours: [Int]
    ) -> BodyHealthMetricDayChartEntry? {
        if let own = entriesByHour[hour] {
            return own
        }

        let nearestHour = sortedHours.min { (abs($0 - hour), $0) < (abs($1 - hour), $1) }
        return nearestHour.flatMap { entriesByHour[$0] }
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

/// One Week/Month/6M/Year chart mark (bar or dot), or its invisible
/// cross-range placeholder — see
/// `BodyHealthMetricTrendChart.makeTrendMarkEntries`.
struct BodyHealthTrendMarkEntry: Identifiable {
    let date: Date
    /// Nil marks a selected-range day with no data (the gray placeholder bar
    /// in bar style; no dot in line style).
    let value: Double?
    /// Another range's reading on this same date, kept only when `value` is
    /// nil. Bar style ignores it and keeps drawing its gray no-data bar; line
    /// style plots it invisibly so the dot exists before that range is
    /// selected — see `dotValue`.
    var offRangeValue: Double?
    /// `true` when `date` exists only in another range's points; the entry
    /// carries that range's own value and renders at opacity 0, so the mark
    /// fades at its true geometry across a range switch instead of popping.
    let isPlaceholder: Bool

    var id: Date {
        date
    }

    /// Where line style plots this entry's dot, visible or not.
    var dotValue: Double? {
        value ?? offRangeValue
    }

    /// A dot is drawn only for a reading the selected range actually has;
    /// everything else is resident geometry at opacity 0.
    var showsDot: Bool {
        !isPlaceholder && value != nil
    }
}

/// One straight stretch of the trend line (or its collapsed placeholder),
/// keyed by start date so a segment keeps its identity across range
/// switches — see `BodyHealthMetricTrendChart.makeTrendLineSegments`.
struct BodyHealthTrendLineSegmentMark: Identifiable {
    let startDate: Date
    let startValue: Double
    let endDate: Date
    let endValue: Double
    let isPlaceholder: Bool

    var id: String {
        "seg-\(startDate.timeIntervalSinceReferenceDate)"
    }
}

/// One straight stretch of the hourly-average line (or its invisible
/// placeholder), keyed by starting hour so the mark keeps its identity across
/// day switches — see `BodyHealthMetricDayChart.makeLineSegments`.
struct BodyHealthMetricDayLineSegmentMark: Identifiable {
    let sourceRole: BodyHealthSourceRole
    let hourIndex: Int
    let startPlotDate: Date
    let startValue: Double
    let endPlotDate: Date
    let endValue: Double
    var isPlaceholder = false

    var id: String {
        "\(sourceRole.rawValue)-seg-\(hourIndex)"
    }
}

struct BodyHealthMetricDayChartEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let bucket: HealthTrendHourlyBucket
    let segmentIndex: Int
    /// `true` for the invisible hour-filling dots added by
    /// `BodyHealthMetricDayChart.addingPlaceholderDots` — rendered at opacity 0
    /// so a real dot on another day fades through them instead of popping.
    var isPlaceholder = false

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

/// Merges the other ranges' marks into the selected range's marks so a range
/// switch morphs instead of inserting and removing marks: an off-range mark
/// whose id has no drawn counterpart here joins as an invisible placeholder at
/// its own geometry, first range in `allCases` order winning a shared id.
///
/// A current entry that draws nothing — a day with no reading — does not claim
/// its id; it hands its slot to an off-range valued entry, which then fades in
/// place when that range is selected. Substituting rather than appending keeps
/// ids unique, and current entries keep their order ahead of the placeholders.
func bodyUnionMorphEntries<Entry: Identifiable>(
    current: [Entry],
    otherRanges: [[Entry]],
    isDrawn: (Entry) -> Bool,
    placeholder: (Entry) -> Entry
) -> [Entry] {
    let emptyCurrentIDs = Set(current.filter { !isDrawn($0) }.map(\.id))
    var claimedIDs = Set(current.map(\.id)).subtracting(emptyCurrentIDs)
    var substitutions: [Entry.ID: Entry] = [:]
    var appended: [Entry] = []

    for entries in otherRanges {
        for entry in entries where isDrawn(entry) && !claimedIDs.contains(entry.id) {
            claimedIDs.insert(entry.id)
            if emptyCurrentIDs.contains(entry.id) {
                substitutions[entry.id] = placeholder(entry)
            } else {
                appended.append(placeholder(entry))
            }
        }
    }

    return current.map { substitutions[$0.id] ?? $0 } + appended
}
