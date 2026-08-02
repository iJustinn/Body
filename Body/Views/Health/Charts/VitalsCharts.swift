//
//  VitalsCharts.swift
//  Body
//

import Charts
import SwiftUI

enum BodyVitalsChartStyle {
    /// Blue for the personal typical band, red for anything outside it — the
    /// same two colors the sleep-vitals region dots and the home card use.
    static let typicalColor = Color(red: 0.25, green: 0.62, blue: 1.00)
    static let outlierColor = Color(red: 1.00, green: 0.24, blue: 0.20)
    static let typicalBandOpacity = 0.08
    /// Deviations are capped at ±2 (`VitalsCalculator.deviationCap`), so the
    /// scale keeps a little air above and below a maxed-out bar.
    static let yDomain: ClosedRange<Double> = -2.2...2.2
    static let typicalBoundaries: [Double] = [1, -1]
    /// Smallest span a bar may draw, so a bucket whose nights all landed on the
    /// same deviation still reads as a capsule instead of a hairline.
    static let minimumBarSpan = 0.12
    /// Colored segments meet at ±1; overlapping them slightly keeps the
    /// antialiased seam from showing as a gap.
    static let seamOverlap = 0.03
    /// Y positions of the trailing High/Typical/Low labels: the middle of each
    /// region in the fixed scale above.
    static let regionLabelValues: [Double] = [1.6, 0, -1.6]

    static func regionLabel(for value: Double) -> String {
        if value > 1 {
            return String(localized: "High")
        }

        if value < -1 {
            return String(localized: "Low")
        }

        return String(localized: "Typical")
    }
}

/// One drawn bar: the deviation span of the nights in a bucket, split at ±1 so
/// the part inside the typical band and the parts outside it can take different
/// colors.
struct BodyVitalsOutlierBarSegment: Identifiable {
    let id: String
    let lowerBound: Double
    let upperBound: Double
    let isOutlier: Bool
    /// Only the first segment of a bar carries the VoiceOver label; the rest are
    /// hidden so one bar reads as one element.
    let isLabelled: Bool

    var color: Color {
        isOutlier ? BodyVitalsChartStyle.outlierColor : BodyVitalsChartStyle.typicalColor
    }
}

/// The nights that fall in one chart bucket (1 day at week/month, 6 at six
/// months, 12 at year), reduced to what the bar and its callout need.
struct BodyVitalsOutlierBucket: Identifiable {
    let date: Date
    let endDate: Date
    let minDeviation: Double
    let maxDeviation: Double
    let regions: [SleepVitalRegion]
    let outlierKinds: [VitalKind]
    let outlierCount: Int

    var id: Date {
        date
    }

    var statusText: String {
        SleepVitalStatusTitle.text(for: regions)
    }

    init(date: Date, endDate: Date, nights: [VitalsNightAssessment]) {
        self.date = date
        self.endDate = endDate
        self.minDeviation = nights.map(\.minDeviation).min() ?? 0
        self.maxDeviation = nights.map(\.maxDeviation).max() ?? 0
        let regions = nights.flatMap(\.regions)
        self.regions = regions
        self.outlierCount = regions.filter { $0 != .typical }.count
        let outlierKinds = Set(nights.flatMap { night in
            night.measurements.filter { $0.region != .typical }.map(\.kind)
        })
        // Listed in `VitalKind.allCases` order so the callout reads the same way
        // as the breakdown rows below the hero.
        self.outlierKinds = VitalKind.allCases.filter { outlierKinds.contains($0) }
    }

    var segments: [BodyVitalsOutlierBarSegment] {
        let span = maxDeviation - minDeviation
        let padding = max((BodyVitalsChartStyle.minimumBarSpan - span) / 2, 0)
        let lowerBound = max(minDeviation - padding, BodyVitalsChartStyle.yDomain.lowerBound)
        let upperBound = min(maxDeviation + padding, BodyVitalsChartStyle.yDomain.upperBound)
        let overlap = BodyVitalsChartStyle.seamOverlap
        let identifier = "\(date.timeIntervalSinceReferenceDate)"

        var bounds: [(id: String, lowerBound: Double, upperBound: Double, isOutlier: Bool)] = []
        if lowerBound <= 1, upperBound >= -1 {
            bounds.append((
                id: "\(identifier)-typical",
                lowerBound: max(lowerBound, -1),
                upperBound: min(upperBound, 1),
                isOutlier: false
            ))
        }
        if lowerBound < -1 {
            bounds.append((
                id: "\(identifier)-low",
                lowerBound: lowerBound,
                upperBound: min(upperBound, -1 + overlap),
                isOutlier: true
            ))
        }
        if upperBound > 1 {
            bounds.append((
                id: "\(identifier)-high",
                lowerBound: max(lowerBound, 1 - overlap),
                upperBound: upperBound,
                isOutlier: true
            ))
        }

        return bounds.enumerated().map { index, bound in
            BodyVitalsOutlierBarSegment(
                id: bound.id,
                lowerBound: bound.lowerBound,
                upperBound: bound.upperBound,
                isOutlier: bound.isOutlier,
                isLabelled: index == 0
            )
        }
    }
}

/// Apple-Vitals-style hero chart: one bar per bucket spanning that bucket's
/// deviation range, drawn against the personal typical band. Blue inside the
/// band, red outside it — the height of the red tells you how far a night ran
/// from your own normal, not from a population reference.
struct BodyVitalsOutlierTrendChart: View {
    let selectedRange: BodyHealthTrendRange
    let immersive: Bool
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let buckets: [BodyVitalsOutlierBucket]
    private let chartXDomain: ClosedRange<Date>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        nights: [VitalsNightAssessment],
        selectedRange: BodyHealthTrendRange,
        immersive: Bool = false,
        floatingCallout: BodyChartFloatingCalloutState? = nil,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) {
        self.selectedRange = selectedRange
        self.immersive = immersive
        self.floatingCallout = floatingCallout

        let domainDates = Self.dayGrid(for: selectedRange, calendar: calendar, date: date)
        self.buckets = Self.buckets(from: nights, days: domainDates, selectedRange: selectedRange, calendar: calendar)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange, immersive: immersive)
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.heartRateRangeChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                RectangleMark(
                    xStart: .value("Typical Band Start", chartXDomain.lowerBound),
                    xEnd: .value("Typical Band End", chartXDomain.upperBound),
                    yStart: .value("Typical Lower Bound", -1),
                    yEnd: .value("Typical Upper Bound", 1)
                )
                .foregroundStyle(BodyVitalsChartStyle.typicalColor.opacity(BodyVitalsChartStyle.typicalBandOpacity))

                ForEach(BodyVitalsChartStyle.typicalBoundaries, id: \.self) { boundary in
                    RuleMark(y: .value("Typical Boundary", boundary))
                        .foregroundStyle(Color.secondary.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }

                if let selectedBucket {
                    RuleMark(x: .value("Selected Date", selectedBucket.endDate, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(buckets) { bucket in
                    ForEach(bucket.segments) { segment in
                        BarMark(
                            // Aggregated buckets plot at their END day, like
                            // `HealthTrendRangeCalendarPoint` heroes, so the
                            // newest bar lands on the domain edge instead of a
                            // bucket-width short of it.
                            x: .value("Date", bucket.endDate, unit: .day),
                            yStart: .value("Low Deviation", segment.lowerBound),
                            yEnd: .value("High Deviation", segment.upperBound),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(segment.color)
                        .cornerRadius(chartBarWidth / 2)
                        .accessibilityLabel(segment.isLabelled ? accessibilityLabel(for: bucket) : "")
                        .accessibilityHidden(!segment.isLabelled)
                    }
                }

                if let selectedBucket {
                    RuleMark(x: .value("Selected Date", selectedBucket.endDate, unit: .day))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            if floatingCallout == nil {
                                selectionAnnotation(for: selectedBucket)
                            }
                        }
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: BodyVitalsChartStyle.yDomain)
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
                // The scale is a deviation, not a readable number, so the Y axis
                // carries the region words instead — same type as
                // `BodySleepVitalRegionLabels` on the last-night scatter. They stay
                // visible in the immersive hero (where sibling charts hide their
                // numeric axis): without them the bars have no reference at all.
                AxisMarks(position: .trailing, values: BodyVitalsChartStyle.regionLabelValues) { value in
                    AxisValueLabel {
                        if let yValue = value.as(Double.self) {
                            Text(BodyVitalsChartStyle.regionLabel(for: yValue))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.secondary.opacity(0.62))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .simultaneousGesture(chartPressGesture)
            .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedBucket?.date) {
                guard let bucket = selectedBucket else {
                    return AnyView(EmptyView())
                }
                return AnyView(selectionAnnotation(for: bucket))
            }
            .accessibilityLabel(Text("Vitals outlier trend"))
            .id("vitals-outliers-\(selectedRange.rawValue)")
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var selectedBucket: BodyVitalsOutlierBucket? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return buckets.min { first, second in
            abs(first.endDate.timeIntervalSince(selectedDate)) < abs(second.endDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectionAnnotation(for bucket: BodyVitalsOutlierBucket) -> BodyVitalsSelectionAnnotation {
        BodyVitalsSelectionAnnotation(bucket: bucket, dateText: dateText(for: bucket))
    }

    private func accessibilityLabel(for bucket: BodyVitalsOutlierBucket) -> String {
        "\(dateText(for: bucket)), \(bucket.statusText)"
    }

    private func dateText(for bucket: BodyVitalsOutlierBucket) -> String {
        bodyChartSelectionDateText(startDate: bucket.date, endDate: bucket.endDate)
            ?? bucket.date.formatted(.dateTime.month(.abbreviated).day().year())
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

    static func dayGrid(
        for selectedRange: BodyHealthTrendRange,
        calendar: Calendar,
        date: Date
    ) -> [Date] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(selectedRange.dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        return (0..<selectedRange.dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDate)
        }
    }

    static func buckets(
        from nights: [VitalsNightAssessment],
        days: [Date],
        selectedRange: BodyHealthTrendRange,
        calendar: Calendar
    ) -> [BodyVitalsOutlierBucket] {
        let nightsByDay = Dictionary(grouping: nights) { calendar.startOfDay(for: $0.date) }
        let aggregationDayCount = selectedRange.chartAggregationDayCount

        // Days run oldest → newest ending today, so bucket from the newest day
        // backwards — the same anchoring the aggregated trend series use, so a
        // leftover partial bucket falls on the oldest end instead of dropping
        // the most recent night.
        var ranges: [Range<Int>] = []
        var endIndex = days.count
        while endIndex > 0 {
            let startIndex = max(endIndex - aggregationDayCount, 0)
            ranges.append(startIndex..<endIndex)
            endIndex = startIndex
        }
        ranges.reverse()

        if let firstRange = ranges.first,
           firstRange.count < aggregationDayCount,
           ranges.count > 1 {
            ranges.removeFirst()
        }

        return ranges.compactMap { range in
            let bucketDays = days[range]
            guard let bucketStart = bucketDays.first, let bucketEnd = bucketDays.last else {
                return nil
            }

            let bucketNights = bucketDays.flatMap { nightsByDay[$0] ?? [] }
            guard !bucketNights.isEmpty else {
                return nil
            }

            return BodyVitalsOutlierBucket(date: bucketStart, endDate: bucketEnd, nights: bucketNights)
        }
    }
}

/// Scrub callout for the vitals hero: the bucket's status, the vitals that ran
/// outside their typical range, and the day (or day span) it covers.
struct BodyVitalsSelectionAnnotation: View {
    let bucket: BodyVitalsOutlierBucket
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(bucket.statusText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            ForEach(bucket.outlierKinds) { kind in
                HStack(spacing: 7) {
                    Circle()
                        .fill(BodyVitalsChartStyle.outlierColor)
                        .frame(width: 8, height: 8)

                    Text(kind.displayName)
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            Text(dateText)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .bodyChartSelectionAnnotationBackground()
    }
}

/// One vital in the last-night breakdown: tinted icon tile, name, the reading in
/// its own unit, and where it landed against that vital's personal range.
struct BodyVitalRowView: View {
    let row: SleepVitalDisplayRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(row.tintColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(row.tintColor.opacity(0.14))
                )
                .accessibilityHidden(true)

            Text(row.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(row.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if !row.unit.isEmpty {
                    Text(row.unit)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            BodyVitalRegionChip(region: row.region)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

struct BodyVitalRegionChip: View {
    let region: SleepVitalRegion

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.14))
            )
    }

    private var title: String {
        switch region {
        case .low:
            return String(localized: "Low")
        case .typical:
            return String(localized: "Typical")
        case .high:
            return String(localized: "High")
        }
    }

    private var color: Color {
        region == .typical ? BodyVitalsChartStyle.typicalColor : BodyVitalsChartStyle.outlierColor
    }
}
