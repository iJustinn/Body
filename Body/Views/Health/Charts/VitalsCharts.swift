//
//  VitalsCharts.swift
//  Body
//

import Charts
import SwiftUI

enum BodyVitalsChartStyle {
    /// Blue for the personal typical band, dark purple above it, light pink
    /// below it — the same three colors the sleep-vitals region dots and the
    /// home card use. Kept as components because a SwiftUI `Color` can't be
    /// taken apart again, and the bar gradient has to blend between them.
    static let typicalRGB: (red: Double, green: Double, blue: Double) = (0.25, 0.62, 1.00)
    static let highRGB: (red: Double, green: Double, blue: Double) = (0.58, 0.20, 0.96)
    static let lowRGB: (red: Double, green: Double, blue: Double) = (1.00, 0.55, 0.75)
    static let typicalColor = Color(red: typicalRGB.red, green: typicalRGB.green, blue: typicalRGB.blue)
    static let highColor = Color(red: highRGB.red, green: highRGB.green, blue: highRGB.blue)
    static let lowColor = Color(red: lowRGB.red, green: lowRGB.green, blue: lowRGB.blue)
    static let typicalBandOpacity = 0.08
    /// The chart plots DISPLAY positions, not raw deviations: the typical band
    /// keeps full scale while everything past ±1 is compressed, so the band
    /// takes ~45% of the plot and the High/Low regions stay compact without
    /// giving up outlier granularity (deviations still cap at ±3 in the data).
    static let outlierCompression = 0.5
    /// Display scale: ±1 band at full size, the compressed ±3 deviation cap
    /// lands at ±2, and a little air keeps a maxed-out bar off the edge.
    static let yDomain: ClosedRange<Double> = -2.2...2.2
    static let typicalBoundaries: [Double] = [1, -1]

    /// Maps a raw deviation onto the compressed display scale above.
    static func displayPosition(forDeviation deviation: Double) -> Double {
        let magnitude = abs(deviation)
        guard magnitude > 1 else {
            return deviation
        }

        let compressed = 1 + (magnitude - 1) * outlierCompression
        return deviation < 0 ? -compressed : compressed
    }
    /// Approximate height the X axis (tick + weekday/month label) takes from the
    /// chart frame, used to convert the bar width into deviation units. A few
    /// points of error only nudges the smallest capsule off a perfect circle by
    /// a hair — invisible next to the squashed blobs it prevents.
    static let xAxisEstimatedHeight: CGFloat = 24

    /// Smallest span a bar may draw, in display units: the bar's own width, so
    /// a bucket whose nights all landed on the same deviation renders as a
    /// circle (the capsule's two end caps meeting) instead of a squat blob.
    static func minimumBarSpan(barWidth: CGFloat, chartHeight: CGFloat) -> Double {
        let plotHeight = max(chartHeight - xAxisEstimatedHeight, 1)
        let domainSpan = yDomain.upperBound - yDomain.lowerBound
        return Double(barWidth) * domainSpan / Double(plotHeight)
    }
    /// Where the blend out of blue finishes, in display units (deviation 1.4):
    /// a bar is fully purple (or pink) once it reaches this far past the
    /// typical band. Below the minimum overshoot, so the shortest stretched tip
    /// still lands on full color with a long, smooth ramp.
    static let outlierBlendEnd = 1.2
    /// An outlier bar's tip is stretched to reach at least this far past ±1 on
    /// the display scale, so a night that barely cleared the band still shows a
    /// readable colored tip instead of a sliver. Past the blend end above, so
    /// the tip always reaches full color.
    static let minimumOutlierOvershoot = 0.4
    /// Mixes two component triples; `amount` outside 0…1 clamps to an endpoint,
    /// so callers can hand over an unnormalized ratio.
    static func blend(
        _ from: (red: Double, green: Double, blue: Double),
        _ to: (red: Double, green: Double, blue: Double),
        amount: Double
    ) -> Color {
        let fraction = min(max(amount, 0), 1)
        return Color(
            red: from.red + (to.red - from.red) * fraction,
            green: from.green + (to.green - from.green) * fraction,
            blue: from.blue + (to.blue - from.blue) * fraction
        )
    }

    /// The bar color at one display position: solid blue inside the typical
    /// band, blending to purple (or pink) between ±1 and the blend end, solid
    /// past it. Anchored to the position itself, so the same height always
    /// reads the same color no matter which bar it belongs to.
    static func color(forPosition position: Double) -> Color {
        let magnitude = abs(position)
        let amount = (magnitude - 1) / (outlierBlendEnd - 1)
        return blend(typicalRGB, position < 0 ? lowRGB : highRGB, amount: amount)
    }

    /// Gradient stops for one bar, running top (`upperBound`) to bottom
    /// (`lowerBound`). Stops land on the blend boundaries that fall inside the
    /// bar plus the bar's own ends, so a bar entirely inside the typical band
    /// comes out solid blue.
    static func barGradientStops(lowerBound: Double, upperBound: Double) -> [Gradient.Stop] {
        let span = upperBound - lowerBound
        guard span > 0 else {
            return [Gradient.Stop(color: color(forPosition: upperBound), location: 0)]
        }

        // Descending, so positions come out non-decreasing.
        let boundaries = [outlierBlendEnd, 1, -1, -outlierBlendEnd].filter {
            $0 > lowerBound && $0 < upperBound
        }

        var location: CGFloat = 0
        return ([upperBound] + boundaries + [lowerBound]).map { position in
            location = max(location, min(max(CGFloat((upperBound - position) / span), 0), 1))
            return Gradient.Stop(color: color(forPosition: position), location: location)
        }
    }
}

/// One vital that ran outside its typical range in a bucket, with the side it
/// ran to so the callout dot can take the matching color.
struct BodyVitalsOutlierKind: Identifiable {
    let kind: VitalKind
    let region: SleepVitalRegion

    var id: VitalKind {
        kind
    }

    var color: Color {
        region == .high ? BodyVitalsChartStyle.highColor : BodyVitalsChartStyle.lowColor
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
    let outlierKinds: [BodyVitalsOutlierKind]
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
        var outlierRegions: [VitalKind: SleepVitalRegion] = [:]
        for measurement in nights.flatMap(\.measurements) where measurement.region != .typical {
            if outlierRegions[measurement.kind] == nil {
                outlierRegions[measurement.kind] = measurement.region
            }
        }
        // Listed in `VitalKind.allCases` order so the callout reads the same way
        // as the breakdown rows below the hero.
        self.outlierKinds = VitalKind.allCases.compactMap { kind in
            outlierRegions[kind].map { BodyVitalsOutlierKind(kind: kind, region: $0) }
        }
    }

    /// The drawn span of the bar on the compressed display scale: the bucket's
    /// deviation range mapped through `displayPosition`, widened to the given
    /// minimum span (the bar's own width in display units, so the smallest mark
    /// is a circle) and stretched to the minimum overshoot when an outlier
    /// barely cleared the band. The domain clamps only bind when the circle
    /// padding runs past the scale's edge — the compressed deviation cap (±2 on
    /// the display scale) itself sits inside the ±2.2 domain.
    func barBounds(minimumSpan: Double) -> (lowerBound: Double, upperBound: Double) {
        let displayMin = BodyVitalsChartStyle.displayPosition(forDeviation: minDeviation)
        let displayMax = BodyVitalsChartStyle.displayPosition(forDeviation: maxDeviation)
        let span = displayMax - displayMin
        let padding = max((minimumSpan - span) / 2, 0)
        var lowerBound = max(displayMin - padding, BodyVitalsChartStyle.yDomain.lowerBound)
        var upperBound = min(displayMax + padding, BodyVitalsChartStyle.yDomain.upperBound)
        if displayMax > 1 {
            upperBound = max(upperBound, 1 + BodyVitalsChartStyle.minimumOutlierOvershoot)
        }
        if displayMin < -1 {
            lowerBound = min(lowerBound, -1 - BodyVitalsChartStyle.minimumOutlierOvershoot)
        }
        return (lowerBound: lowerBound, upperBound: upperBound)
    }
}

/// Apple-Vitals-style hero chart: one bar per bucket spanning that bucket's
/// deviation range, drawn against the personal typical band. Blue inside the
/// band, fading to purple above it and pink below it — how far the color has
/// turned tells you how far a night ran from your own normal, not from a
/// population reference.
struct BodyVitalsOutlierTrendChart: View {
    let selectedRange: BodyHealthTrendRange
    let immersive: Bool
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    private let buckets: [BodyVitalsOutlierBucket]
    private let barEntries: [BodyVitalsOutlierBarEntry]
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
        let buckets = Self.buckets(from: nights, days: domainDates, selectedRange: selectedRange, calendar: calendar)
        self.buckets = buckets
        // Every range's buckets, not just the selected one: end dates outside
        // the current range render as invisible placeholders carrying their
        // own range's geometry, so a range switch morphs shared marks in place
        // and fades the rest instead of inserting/removing marks (which Swift
        // Charts pops).
        let otherRanges = BodyHealthTrendRange.allCases.filter { $0 != selectedRange }
        self.barEntries = Self.unionBarEntries(
            currentBuckets: buckets,
            otherRangeBuckets: otherRanges.map { range in
                Self.buckets(
                    from: nights,
                    days: Self.dayGrid(for: range, calendar: calendar, date: date),
                    selectedRange: range,
                    calendar: calendar
                )
            }
        )
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

                ForEach(barEntries) { entry in
                    // Padding a spread-less bucket to exactly the bar's width in
                    // deviation units makes the capsule's end caps meet: the
                    // smallest mark renders as a circle, not a squat blob.
                    let bounds = entry.bucket.barBounds(
                        minimumSpan: BodyVitalsChartStyle.minimumBarSpan(
                            barWidth: chartBarWidth,
                            chartHeight: proxy.size.height
                        )
                    )

                    BarMark(
                        // Aggregated buckets plot at their END day, like
                        // `HealthTrendRangeCalendarPoint` heroes, so the
                        // newest bar lands on the domain edge instead of a
                        // bucket-width short of it.
                        x: .value("Date", entry.bucket.endDate, unit: .day),
                        yStart: .value("Low Deviation", bounds.lowerBound),
                        yEnd: .value("High Deviation", bounds.upperBound),
                        width: .fixed(chartBarWidth)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            stops: BodyVitalsChartStyle.barGradientStops(
                                lowerBound: bounds.lowerBound,
                                upperBound: bounds.upperBound
                            ),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(chartBarWidth / 2)
                    .opacity(entry.isPlaceholder ? 0 : 1)
                    .accessibilityLabel(accessibilityLabel(for: entry.bucket))
                    // Invisible off-range placeholders must stay out of the
                    // VoiceOver rotor.
                    .accessibilityHidden(entry.isPlaceholder)
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
            // The scale is a deviation, not a readable number: the bars and the
            // highlighted typical band carry the reference on their own, so no
            // Y axis is drawn at all.
            .chartYAxis(.hidden)
            .chartXSelection(value: $selectedDate)
            .simultaneousGesture(chartPressGesture)
            .bodyFloatingCalloutReporter(floatingCallout, selectionDate: selectedBucket?.date) {
                guard let bucket = selectedBucket else {
                    return AnyView(EmptyView())
                }
                return AnyView(selectionAnnotation(for: bucket))
            }
            .accessibilityLabel(Text("Vitals outlier trend"))
            // Stable across range switches: a per-range id would replace the
            // chart instead of updating it, popping every mark rather than
            // letting them morph.
            .id("vitals-outliers")
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

    /// The current range's buckets verbatim, plus every other range's buckets
    /// as invisible placeholders carrying their own range's geometry. End
    /// dates (the plotted x) are claimed with current-range priority so ids
    /// stay unique.
    static func unionBarEntries(
        currentBuckets: [BodyVitalsOutlierBucket],
        otherRangeBuckets: [[BodyVitalsOutlierBucket]]
    ) -> [BodyVitalsOutlierBarEntry] {
        var entries = currentBuckets.map { bucket in
            BodyVitalsOutlierBarEntry(bucket: bucket, isPlaceholder: false)
        }
        var claimedEndDates = Set(currentBuckets.map(\.endDate))
        for rangeBuckets in otherRangeBuckets {
            for bucket in rangeBuckets where !claimedEndDates.contains(bucket.endDate) {
                claimedEndDates.insert(bucket.endDate)
                entries.append(BodyVitalsOutlierBarEntry(bucket: bucket, isPlaceholder: true))
            }
        }
        return entries
    }
}

/// One bucket's deviation bar (or its invisible off-range placeholder), keyed
/// by bucket END date — the plotted x — so the mark keeps its identity across
/// range switches; see `BodyVitalsOutlierTrendChart.unionBarEntries`.
struct BodyVitalsOutlierBarEntry: Identifiable {
    let bucket: BodyVitalsOutlierBucket
    let isPlaceholder: Bool

    var id: Date {
        bucket.endDate
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

            ForEach(bucket.outlierKinds) { outlier in
                HStack(spacing: 7) {
                    Circle()
                        .fill(outlier.color)
                        .frame(width: 8, height: 8)

                    Text(outlier.kind.displayName)
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

/// One vital in the night's breakdown: white icon tile, name, and the reading
/// in its own unit. Where it landed against that vital's personal range is left
/// to the plot above the rows.
struct BodyVitalRowView: View {
    let row: SleepVitalDisplayRow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                // Keep the solid glyph legible on grouped backgrounds in both
                // appearances; hierarchical rendering would blur its secondary layers.
                .foregroundStyle(vitalIconColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(vitalIconTileColor)
                )
                .accessibilityHidden(true)

            Text(row.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // The shared numeric text flips digits when the day picker moves
                // between nights; an outlier reading takes its region color, so
                // the number itself flags the vital that ran high or low, and
                // the color cross-fades on the same switch.
                BodyAnimatedMetricValueText(
                    value: row.value,
                    fontSize: 20,
                    color: valueColor,
                    minimumScaleFactor: 0.72
                )
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0),
                    value: row.region
                )

                if !row.unit.isEmpty {
                    Text(row.unit)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        // The region only shows in the plot above now, so VoiceOver reads it
        // from here instead of from a chip in the row.
        .accessibilityValue(regionTitle)
    }

    private var vitalIconColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var vitalIconTileColor: Color {
        vitalIconColor.opacity(0.14)
    }

    private var valueColor: Color {
        switch row.region {
        case .low:
            return BodyVitalsChartStyle.lowColor
        case .typical:
            return .primary
        case .high:
            return BodyVitalsChartStyle.highColor
        }
    }

    private var regionTitle: String {
        switch row.region {
        case .low:
            return String(localized: "Low")
        case .typical:
            return String(localized: "Typical")
        case .high:
            return String(localized: "High")
        }
    }
}
