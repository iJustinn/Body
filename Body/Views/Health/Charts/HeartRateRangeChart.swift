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
    let immersive: Bool
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let secondaryRangePoints: [HealthTrendRangeCalendarPoint]
    private let barEntries: [BodyHeartRateRangeBarEntry]
    private let averageEntries: [BodyHeartRateRangeAverageEntry]
    private let lineSegments: [BodyHeartRateRangeLineSegmentMark]
    private let dotEntries: [BodyHeartRateRangeAverageEntry]
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
        primarySourceName: String = String(localized: "Primary"),
        secondarySourceName: String? = nil,
        symbolColor: Color,
        secondaryColor: Color = Color(red: 0.58, green: 0.36, blue: 0.98),
        valueFormatter: @escaping (Double) -> String,
        showsAverageLineOverlay: Bool = false,
        immersive: Bool = false,
        yDomain: (([Double]) -> ClosedRange<Double>)? = nil,
        floatingCallout: BodyChartFloatingCalloutState? = nil,
        primaryPointsByRange: [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]]? = nil,
        secondaryPointsByRange: [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]]? = nil
    ) {
        self.title = title
        self.selectedRange = selectedRange
        self.symbolColor = symbolColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.showsAverageLineOverlay = showsAverageLineOverlay
        self.immersive = immersive
        self.floatingCallout = floatingCallout
        self.primarySourceName = primarySourceName
        self.secondarySourceName = secondarySourceName

        // The host passes each range's buckets in from a cache that survives a
        // re-render; the inline fallback keeps previews and one-off callers
        // working.
        let primaryPointsByRange = primaryPointsByRange ?? Self.makePointsByRange(for: rangeSeries)
        let secondaryPointsByRange = secondaryRangeSeries.map { series in
            secondaryPointsByRange ?? Self.makePointsByRange(for: series)
        } ?? [:]
        let points = primaryPointsByRange[selectedRange] ?? []
        let secondaryPoints = secondaryPointsByRange[selectedRange] ?? []
        self.secondaryRangePoints = secondaryPoints
        self.finiteRangePoints = points.filter(\.hasValue)
        self.latestPrimaryAveragePointDate = points.last { point in
            point.averageValue?.isFinite == true
        }?.date
        self.latestSecondaryAveragePointDate = secondaryPoints.last { point in
            point.averageValue?.isFinite == true
        }?.date
        let averageEntries = Self.averageEntries(
            primaryPoints: points,
            secondaryPoints: secondaryPoints,
            primarySourceName: primarySourceName,
            secondarySourceName: secondarySourceName
        )
        self.averageEntries = averageEntries
        // Every range's buckets, not just the selected one: dates outside the
        // current range render as invisible placeholders carrying their own
        // range's geometry, so a range switch morphs shared marks in place and
        // fades the rest instead of inserting/removing marks (which Swift
        // Charts pops).
        let otherRanges = BodyHealthTrendRange.allCases.filter { $0 != selectedRange }
        let otherPrimaryPoints = otherRanges.map { primaryPointsByRange[$0] ?? [] }
        let otherAverageEntries = zip(
            otherPrimaryPoints,
            otherRanges.map { secondaryPointsByRange[$0] ?? [] }
        ).map { primary, secondary in
            Self.averageEntries(
                primaryPoints: primary,
                secondaryPoints: secondary,
                primarySourceName: primarySourceName,
                secondarySourceName: secondarySourceName
            )
        }
        self.barEntries = Self.unionBarEntries(
            currentPoints: points,
            otherRangePoints: otherPrimaryPoints
        )
        self.lineSegments = Self.unionAverageLineSegments(
            currentEntries: averageEntries,
            otherRangeEntries: otherAverageEntries
        )
        self.dotEntries = Self.unionAverageDotEntries(
            currentEntries: averageEntries,
            otherRangeEntries: otherAverageEntries
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
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)
    }

    /// Each range's aggregated buckets for `series`.
    static func makePointsByRange(
        for series: HealthTrendRangeSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]] {
        var pointsByRange: [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]] = [:]
        for range in BodyHealthTrendRange.allCases {
            pointsByRange[range] = series.chartCalendarPoints(to: range, calendar: calendar, date: date)
        }
        return pointsByRange
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

                ForEach(barEntries) { entry in
                    if let lowValue = entry.point.lowValue, let highValue = entry.point.highValue {
                        // Both forms exist for every bucket and only opacity
                        // picks between them: a low == high bucket needs the
                        // dot and every other needs the bar, and letting a
                        // range switch change WHICH mark the date has
                        // removes/inserts it, which Swift Charts pops. The
                        // zero-height bar under a dot stays at opacity 0.
                        PointMark(
                            x: .value("Date", entry.point.date, unit: .day),
                            y: .value(title, lowValue)
                        )
                        .symbolSize(bodyRangeChartPointSymbolSize(forBarWidth: chartBarWidth))
                        .foregroundStyle(rangeBarColor)
                        .opacity(!entry.isPlaceholder && lowValue == highValue ? 1 : 0)
                        // Opacity is only visual: without this the hidden twin
                        // and every off-range placeholder still get announced.
                        .accessibilityHidden(entry.isPlaceholder || lowValue != highValue)

                        BarMark(
                            x: .value("Date", entry.point.date, unit: .day),
                            yStart: .value("Low \(title)", lowValue),
                            yEnd: .value("High \(title)", highValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(rangeBarColor)
                        .cornerRadius(chartBarWidth / 2)
                        .opacity(!entry.isPlaceholder && lowValue != highValue ? 1 : 0)
                        .accessibilityHidden(entry.isPlaceholder || lowValue == highValue)
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
                            if floatingCallout == nil {
                                selectionAnnotation(for: selectedRangePoint, lowValue: lowValue, highValue: highValue)
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
            .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedRangePoint?.date) {
                guard let point = selectedRangePoint,
                      let lowValue = point.lowValue,
                      let highValue = point.highValue else {
                    return AnyView(EmptyView())
                }
                return AnyView(selectionAnnotation(for: point, lowValue: lowValue, highValue: highValue))
            }
            // Stable across range switches: a per-range id would replace the
            // chart instead of updating it, popping every mark rather than
            // letting them morph.
            .id("heart-rate-range")
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

    @ChartContentBuilder
    private var averageLineOverlay: some ChartContent {
        if showsAverageLineOverlay {
            // One two-point series per consecutive-average pair instead of one
            // run per source: Swift Charts cannot interpolate a single line
            // whose vertex set changes across a range switch — vertices with
            // no counterpart freeze until the animation ends, then pop. Pair
            // marks shared across ranges morph in place; the rest fade.
            ForEach(lineSegments) { segment in
                LineMark(
                    x: .value("Date", segment.startDate, unit: .day),
                    y: .value("Average \(title)", segment.startValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: segment.sourceRole))
                .lineStyle(StrokeStyle(lineWidth: BodyLineChartPreviewStyle.lineWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)

                LineMark(
                    x: .value("Date", segment.endDate, unit: .day),
                    y: .value("Average \(title)", segment.endValue),
                    series: .value("Segment", segment.id)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: segment.sourceRole))
                .lineStyle(StrokeStyle(lineWidth: BodyLineChartPreviewStyle.lineWidth, lineCap: .round, lineJoin: .round))
                .opacity(segment.isPlaceholder ? 0 : 1)
                .accessibilityHidden(segment.isPlaceholder)
            }

            if selectedRange.showsPointMarks {
                ForEach(dotEntries) { entry in
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
                            // Inside the symbol view, not a mark modifier —
                            // Charts does not apply mark opacity to custom
                            // `.symbol {}` content, which would leave the
                            // placeholders visible.
                            .opacity(entry.isPlaceholder ? 0 : 1)
                        }
                        .accessibilityHidden(entry.isPlaceholder)
                    } else {
                        PointMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Average \(title)", entry.value)
                        )
                        .foregroundStyle(color(for: entry))
                        .symbolSize(28)
                        .opacity(entry.isPlaceholder ? 0 : 1)
                        .accessibilityHidden(entry.isPlaceholder)
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

    private func selectionAnnotation(
        for selectedRangePoint: HealthTrendRangeCalendarPoint,
        lowValue: Double,
        highValue: Double
    ) -> BodyChartSelectionAnnotation {
        BodyChartSelectionAnnotation(
            eyebrow: String(localized: "RANGE"),
            values: selectedValues(for: selectedRangePoint, lowValue: lowValue, highValue: highValue),
            date: selectedRangePoint.date,
            dateText: bodyChartSelectionDateText(for: selectedRangePoint)
        )
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
                title: String(localized: "chart.legendRange", defaultValue: "Range"),
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
        color(for: entry.sourceRole)
    }

    private func color(for role: BodyHealthSourceRole) -> Color {
        role == .primary ? symbolColor : secondaryColor
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
                value: value,
                spanStartDate: point.startDate,
                spanEndDate: point.endDate
            )
        }
        let secondaryEntries = secondaryPoints.compactMap { point -> BodyHeartRateRangeAverageEntry? in
            guard let value = point.averageValue, value.isFinite else {
                return nil
            }

            return BodyHeartRateRangeAverageEntry(
                sourceName: secondarySourceName ?? String(localized: "Secondary"),
                sourceRole: .secondary,
                date: point.date,
                value: value,
                spanStartDate: point.startDate,
                spanEndDate: point.endDate
            )
        }

        return primaryEntries + secondaryEntries
    }

    /// The current range's bars verbatim, plus every other range's valued
    /// buckets as invisible placeholders carrying their own range's geometry.
    /// Dates are claimed with current-range priority so ids stay unique — but
    /// only by a bucket that actually draws: an empty day yields its date to a
    /// valued off-range bucket, which then morphs rather than popping in.
    static func unionBarEntries(
        currentPoints: [HealthTrendRangeCalendarPoint],
        otherRangePoints: [[HealthTrendRangeCalendarPoint]]
    ) -> [BodyHeartRateRangeBarEntry] {
        bodyUnionMorphEntries(
            current: currentPoints.map { BodyHeartRateRangeBarEntry(point: $0, isPlaceholder: false) },
            otherRanges: otherRangePoints.map { points in
                points.map { BodyHeartRateRangeBarEntry(point: $0, isPlaceholder: false) }
            },
            isDrawn: { $0.point.hasValue },
            placeholder: { BodyHeartRateRangeBarEntry(point: $0.point, isPlaceholder: true) }
        )
    }

    /// The current range's average-line pairs, plus every other range's pairs
    /// whose id has no current counterpart as invisible zero-length
    /// placeholders — a segment appearing there on another range grows out of
    /// its own start point instead of popping in.
    static func unionAverageLineSegments(
        currentEntries: [BodyHeartRateRangeAverageEntry],
        otherRangeEntries: [[BodyHeartRateRangeAverageEntry]]
    ) -> [BodyHeartRateRangeLineSegmentMark] {
        var segments = averageLineSegments(from: currentEntries, isPlaceholder: false)
        var claimedIDs = Set(segments.map(\.id))
        for entries in otherRangeEntries {
            for segment in averageLineSegments(from: entries, isPlaceholder: true)
            where !claimedIDs.contains(segment.id) {
                claimedIDs.insert(segment.id)
                segments.append(segment)
            }
        }
        return segments
    }

    /// One segment per ADJACENT pair of a source's (already finite) average
    /// entries. Placeholder segments collapse onto their own start point.
    ///
    /// A pair straddling a bucket with no average draws nothing, so the average
    /// line breaks at the gap instead of running straight across it.
    static func averageLineSegments(
        from entries: [BodyHeartRateRangeAverageEntry],
        isPlaceholder: Bool
    ) -> [BodyHeartRateRangeLineSegmentMark] {
        let entriesByRole = Dictionary(grouping: entries, by: \.sourceRole)
        return entriesByRole.keys.sorted { $0.rawValue < $1.rawValue }.flatMap { role -> [BodyHeartRateRangeLineSegmentMark] in
            let sorted = (entriesByRole[role] ?? []).sorted { $0.date < $1.date }
            return zip(sorted, sorted.dropFirst()).compactMap { start, end -> BodyHeartRateRangeLineSegmentMark? in
                guard bodyTrendChartPointsAreAdjacent(
                    earlierSpanEnd: start.spanEndDate,
                    laterSpanStart: end.spanStartDate
                ) else {
                    return nil
                }

                return BodyHeartRateRangeLineSegmentMark(
                    sourceRole: role,
                    startDate: start.date,
                    startValue: start.value,
                    endDate: isPlaceholder ? start.date : end.date,
                    endValue: isPlaceholder ? start.value : end.value,
                    isPlaceholder: isPlaceholder
                )
            }
        }
    }

    /// The current range's average dots verbatim, plus every other range's
    /// dots whose role-date id has no current counterpart as invisible
    /// placeholders at their own value.
    static func unionAverageDotEntries(
        currentEntries: [BodyHeartRateRangeAverageEntry],
        otherRangeEntries: [[BodyHeartRateRangeAverageEntry]]
    ) -> [BodyHeartRateRangeAverageEntry] {
        var entries = currentEntries
        var claimedIDs = Set(entries.map(\.id))
        for rangeEntries in otherRangeEntries {
            for entry in rangeEntries where !claimedIDs.contains(entry.id) {
                claimedIDs.insert(entry.id)
                var placeholder = entry
                placeholder.isPlaceholder = true
                entries.append(placeholder)
            }
        }
        return entries
    }
}

struct BodyHeartRateRangeAverageEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let date: Date
    let value: Double
    /// The days this average covers: the plotted day on Week/Month, the bucket
    /// on 6M/Year. `averageLineSegments` joins two entries only when the spans
    /// touch, so a bucket with no reading breaks the line.
    let spanStartDate: Date
    let spanEndDate: Date
    var isPlaceholder: Bool = false

    init(
        sourceName: String,
        sourceRole: BodyHealthSourceRole,
        date: Date,
        value: Double,
        spanStartDate: Date? = nil,
        spanEndDate: Date? = nil,
        isPlaceholder: Bool = false
    ) {
        self.sourceName = sourceName
        self.sourceRole = sourceRole
        self.date = date
        self.value = value
        self.spanStartDate = spanStartDate ?? date
        self.spanEndDate = spanEndDate ?? date
        self.isPlaceholder = isPlaceholder
    }

    var id: String {
        "\(sourceRole.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}

/// One range bucket's min-max bar (or its invisible off-range placeholder),
/// keyed by bucket date so the mark keeps its identity across range switches —
/// see `BodyHeartRateRangeTrendChart.unionBarEntries`.
struct BodyHeartRateRangeBarEntry: Identifiable {
    let point: HealthTrendRangeCalendarPoint
    let isPlaceholder: Bool

    var id: Date {
        point.date
    }
}

/// One straight stretch of the average line (or its invisible zero-length
/// placeholder), keyed by source role + pair start date so the mark keeps its
/// identity across range switches — see
/// `BodyHeartRateRangeTrendChart.unionAverageLineSegments`.
struct BodyHeartRateRangeLineSegmentMark: Identifiable {
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
