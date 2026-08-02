//
//  BodyHealthMetricCard.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHealthMetricCard: View {
    struct Model: Identifiable {
        /// One vital plotted in the mini dots preview.
        struct DotEntry: Equatable {
            /// 0…1, from `SleepVitalReferenceRange.markerPosition`.
            var position: Double
            var region: SleepVitalRegion
        }

        let kind: HealthMetricKind
        let title: String
        let value: String
        let unit: String
        let symbolName: String
        let symbolColor: Color
        let prominentMetrics: [BodyMetricDisplayValue]
        let chartPreviewStyle: BodyHomeMetricCardPreview.Style
        let hasChartPreview: Bool
        let previewCalendarPoints: [HealthTrendCalendarPoint]
        let previewRangeCalendarPoints: [HealthTrendRangeCalendarPoint]
        let previewDotEntries: [DotEntry]

        init(
            kind: HealthMetricKind,
            title: String,
            value: String,
            unit: String,
            symbolName: String,
            symbolColor: Color,
            prominentMetrics: [BodyMetricDisplayValue] = [],
            chartPreviewStyle: BodyHomeMetricCardPreview.Style = .line,
            chartPreview: HealthTrendSeries? = nil,
            chartRangePreview: HealthTrendRangeSeries? = nil,
            previewDotEntries: [DotEntry] = [],
            previewDayCount: Int = BodyHomeMetricCardPreview.dayCount(forScreenWidth: UIScreen.main.bounds.width)
        ) {
            self.kind = kind
            self.title = title
            self.value = value
            self.unit = unit
            self.symbolName = symbolName
            self.symbolColor = symbolColor
            self.prominentMetrics = prominentMetrics
            self.chartPreviewStyle = chartPreviewStyle
            self.previewDotEntries = previewDotEntries
            // Preview points are derived once per model — the preview view
            // used to regroup the full trend series in chained computed
            // properties on every render of every card.
            hasChartPreview = chartPreview != nil || chartRangePreview != nil || !previewDotEntries.isEmpty
            previewCalendarPoints = chartPreview.map {
                BodyHomeMetricCardPreview.calendarPoints(from: $0, previewDayCount: previewDayCount)
            } ?? []
            previewRangeCalendarPoints = chartRangePreview.map {
                BodyHomeMetricCardPreview.rangeCalendarPoints(from: $0, previewDayCount: previewDayCount)
            } ?? []
        }

        var id: String {
            kind.id
        }
    }

    let metric: Model

    var body: some View {
        cardContent
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .bodyCardBackground(cornerRadius: 28, translucent: true, translucentFillOpacity: 0.09)
    }

    @ViewBuilder
    private var cardContent: some View {
        if !metric.prominentMetrics.isEmpty {
            prominentContent
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                titleLabel

                Spacer(minLength: 0)

                valueRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            visualStack
        }
    }

    private var prominentContent: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                titleLabel

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(metric.prominentMetrics) { display in
                        displayValueRow(display, valueFontSize: 26)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            visualStack
        }
    }

    private var titleLabel: some View {
        Text(String(localized: String.LocalizationValue(metric.title)))
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var visualStack: some View {
        VStack(alignment: .trailing, spacing: 20) {
            if metric.hasChartPreview {
                BodyHealthMetricCardTrendPreview(
                    calendarPoints: metric.previewCalendarPoints,
                    rangeCalendarPoints: metric.previewRangeCalendarPoints,
                    dotEntries: metric.previewDotEntries,
                    tintColor: metric.symbolColor,
                    style: metric.chartPreviewStyle
                )
            }

            Image(systemName: metric.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(metric.symbolColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(metric.symbolColor.opacity(0.16))
                )
                .accessibilityHidden(true)
        }
        .frame(
            width: BodyHomeMetricCardPreview.previewWidth(for: metric.chartPreviewStyle, screenWidth: UIScreen.main.bounds.width),
            alignment: .bottomTrailing
        )
        .padding(.bottom, 4)
    }

    private var valueRow: some View {
        displayValueRow(
            BodyMetricDisplayValue(title: metric.title, value: metric.value, unit: metric.unit),
            // Word values run longer than digits, so vitals sets them a touch
            // smaller than the numeric cards.
            valueFontSize: metric.kind == .vitals ? 28 : 30
        )
    }

    private func displayValueRow(_ display: BodyMetricDisplayValue, valueFontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Group {
                // Word values ("Typical", "2 Outliers") must not get the
                // numeric text treatment digits rely on.
                if metric.kind == .vitals {
                    BodyMetricStatusValueText(text: display.value, fontSize: valueFontSize)
                } else {
                    BodyAnimatedMetricValueText(
                        value: display.value,
                        fontSize: valueFontSize,
                        color: .primary,
                        minimumScaleFactor: 0.60
                    )
                }
            }
                .layoutPriority(1)

            if !display.unit.isEmpty {
                Text(display.unit)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
            }
        }
        .layoutPriority(1)
    }
}

struct BodyHealthMetricCardTrendPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Precomputed by `BodyHealthMetricCard.Model` so re-renders don't regroup
    // the full trend series.
    let calendarPoints: [HealthTrendCalendarPoint]
    let rangeCalendarPoints: [HealthTrendRangeCalendarPoint]
    let dotEntries: [BodyHealthMetricCard.Model.DotEntry]
    let tintColor: Color
    let style: BodyHomeMetricCardPreview.Style

    init(
        calendarPoints: [HealthTrendCalendarPoint],
        rangeCalendarPoints: [HealthTrendRangeCalendarPoint] = [],
        dotEntries: [BodyHealthMetricCard.Model.DotEntry] = [],
        tintColor: Color,
        style: BodyHomeMetricCardPreview.Style
    ) {
        self.calendarPoints = calendarPoints
        self.rangeCalendarPoints = rangeCalendarPoints
        self.dotEntries = dotEntries
        self.tintColor = tintColor
        self.style = style
    }

    private var refreshAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0)
    }

    private struct LinePlotEntry: Identifiable {
        let point: HealthTrendCalendarPoint
        let position: CGPoint
        let index: Int

        var id: Date {
            point.date
        }

        var hasValue: Bool {
            point.value?.isFinite == true
        }
    }

    private var values: [Double] {
        calendarPoints.compactMap(\.value).filter(\.isFinite)
    }

    private var maximumValue: Double {
        max(values.max() ?? 0, 1)
    }

    private var lastValueIndex: Int? {
        calendarPoints.lastIndex { point in
            point.value?.isFinite == true
        }
    }

    private var rangeValues: [Double] {
        rangeCalendarPoints.flatMap { point -> [Double] in
            guard let lowValue = point.lowValue,
                  let highValue = point.highValue,
                  lowValue.isFinite,
                  highValue.isFinite else {
                return []
            }

            return [lowValue, highValue]
        }
    }

    private var lastRangeValueIndex: Int? {
        rangeCalendarPoints.lastIndex { point in
            point.hasValue
        }
    }

    var body: some View {
        Group {
            switch style {
            case .line:
                linePreview
            case .bar:
                barPreview
            case .range:
                rangePreview
            case .dots:
                dotsPreview
            }
        }
        .frame(width: previewWidth, height: previewHeight, alignment: .bottomTrailing)
        .accessibilityHidden(true)
    }

    private var previewWidth: CGFloat {
        BodyHomeMetricCardPreview.previewWidth(for: style, screenWidth: UIScreen.main.bounds.width)
    }

    private var previewHeight: CGFloat {
        BodyHomeMetricCardPreview.previewHeight(forScreenWidth: UIScreen.main.bounds.width)
    }

    private var barPreview: some View {
        let heights = calendarPoints.map { barHeight(for: $0.value) }

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(calendarPoints.enumerated()), id: \.offset) { index, point in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor(for: point, at: index))
                    .frame(width: 5, height: heights[index])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(refreshAnimation, value: heights)
        .animation(refreshAnimation, value: lastValueIndex ?? -1)
    }

    private var rangePreview: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(rangeCalendarPoints.enumerated()), id: \.offset) { index, point in
                    rangeBar(for: point, at: index, in: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .animation(refreshAnimation, value: rangeAnimationKey)
            .animation(refreshAnimation, value: lastRangeValueIndex ?? -1)
        }
    }

    private var rangeAnimationKey: [RangePointKey] {
        rangeCalendarPoints.map { point in
            RangePointKey(
                low: point.lowValue.flatMap { $0.isFinite ? $0 : nil },
                high: point.highValue.flatMap { $0.isFinite ? $0 : nil }
            )
        }
    }

    private struct RangePointKey: Equatable {
        let low: Double?
        let high: Double?
    }

    private var linePreview: some View {
        GeometryReader { proxy in
            let plotEntries = linePlotEntries(in: proxy.size)
            let valueEntries = plotEntries.filter(\.hasValue)
            let linePositions = valueEntries.map(\.position)

            ZStack {
                if linePositions.count > 1 {
                    AnimatablePolyline(points: linePositions)
                        .stroke(
                            Color.secondary.opacity(0.28),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }

                ForEach(Array(plotEntries.enumerated()), id: \.offset) { _, entry in
                    if entry.hasValue {
                        let isCurrent = entry.index == (lastValueIndex ?? -1)
                        let diameter = isCurrent
                            ? BodyHomeMetricCardPreview.lineCurrentPointDiameter
                            : BodyHomeMetricCardPreview.linePointDiameter

                        Circle()
                            .fill(isCurrent ? tintColor : Color(.secondarySystemBackground))
                            .frame(width: diameter, height: diameter)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isCurrent ? tintColor : Color.secondary.opacity(0.28),
                                        lineWidth: 2
                                    )
                            )
                            .position(entry.position)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.20))
                            .frame(width: 4, height: 4)
                            .position(entry.position)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(refreshAnimation, value: plotEntries.map(\.position))
            .animation(refreshAnimation, value: lastValueIndex ?? -1)
        }
    }

    private func barColor(for point: HealthTrendCalendarPoint, at index: Int) -> Color {
        guard point.value?.isFinite == true else {
            return Color.secondary.opacity(0.14)
        }

        return index == (lastValueIndex ?? -1) ? tintColor : Color.secondary.opacity(0.24)
    }

    private func barHeight(for value: Double?) -> CGFloat {
        guard let value, value.isFinite, value > 0 else {
            return 5
        }

        return max(6, CGFloat(value / maximumValue) * 42)
    }

    private func rangeBar(for point: HealthTrendRangeCalendarPoint, at index: Int, in size: CGSize) -> some View {
        let frame = rangeBarFrame(for: point, in: size)

        return ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(rangeBarColor(for: point, at: index))
                .frame(width: 5, height: frame.height)
                .offset(y: -frame.bottomOffset)
        }
        .frame(width: 5, height: size.height, alignment: .bottom)
    }

    private func rangeBarFrame(for point: HealthTrendRangeCalendarPoint, in size: CGSize) -> (height: CGFloat, bottomOffset: CGFloat) {
        guard let lowValue = point.lowValue,
              let highValue = point.highValue,
              lowValue.isFinite,
              highValue.isFinite else {
            return (5, 0)
        }

        let minimum = rangeValues.min() ?? lowValue
        let maximum = rangeValues.max() ?? highValue
        let valueRange = max(maximum - minimum, 1)
        let plotHeight = max(size.height - 4, 1)
        let normalizedLow = (min(lowValue, highValue) - minimum) / valueRange
        let normalizedHigh = (max(lowValue, highValue) - minimum) / valueRange
        let bottomOffset = CGFloat(max(normalizedLow, 0)) * plotHeight
        let height = max(6, CGFloat(max(normalizedHigh - normalizedLow, 0)) * plotHeight)
        return (height, bottomOffset)
    }

    private func rangeBarColor(for point: HealthTrendRangeCalendarPoint, at index: Int) -> Color {
        guard point.hasValue else {
            return Color.secondary.opacity(0.14)
        }

        return index == (lastRangeValueIndex ?? -1) ? tintColor : Color.secondary.opacity(0.24)
    }

    private func linePlotEntries(in size: CGSize) -> [LinePlotEntry] {
        guard !calendarPoints.isEmpty else {
            return []
        }

        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let valueRange = maximum - minimum
        let horizontalInset: CGFloat = 5
        let verticalInset: CGFloat = 5
        let plotWidth = max(size.width - horizontalInset * 2, 1)
        let plotHeight = max(size.height - verticalInset * 2, 1)
        let denominator = max(CGFloat(calendarPoints.count - 1), 1)

        return calendarPoints.enumerated().map { index, point in
            let x = horizontalInset + plotWidth * CGFloat(index) / denominator
            let normalizedValue: Double
            if let value = point.value, value.isFinite {
                normalizedValue = valueRange == 0 ? 0.5 : (value - minimum) / valueRange
            } else {
                normalizedValue = 0
            }
            let y = verticalInset + plotHeight * (1 - CGFloat(normalizedValue))
            return LinePlotEntry(
                point: point,
                position: CGPoint(x: x, y: y),
                index: index
            )
        }
    }

    /// Health's Vitals preview, drawn the way Apple draws it: a thick gray
    /// capsule for the high region, a filled blue rounded band for the typical
    /// region, another gray capsule for the low region, and one dark-centered
    /// ring per vital — typical rings sit inside the band, outlier rings land
    /// on the gray bar they escaped to.
    private var dotsPreview: some View {
        GeometryReader { proxy in
            let layout = DotPreviewLayout(size: proxy.size)

            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.42))
                    .frame(width: proxy.size.width, height: layout.barHeight)
                    .position(x: proxy.size.width / 2, y: layout.topBarCenterY)

                RoundedRectangle(cornerRadius: layout.bandCornerRadius, style: .continuous)
                    .fill(Color(red: 0.21, green: 0.30, blue: 0.45))
                    .frame(width: proxy.size.width, height: layout.bandHeight)
                    .position(x: proxy.size.width / 2, y: layout.bandCenterY)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.42))
                    .frame(width: proxy.size.width, height: layout.barHeight)
                    .position(x: proxy.size.width / 2, y: layout.bottomBarCenterY)

                ForEach(Array(dotEntries.enumerated()), id: \.offset) { index, entry in
                    Circle()
                        .fill(Color.black.opacity(0.62))
                        .overlay(
                            Circle()
                                .strokeBorder(dotColor(for: entry), lineWidth: layout.dotStroke)
                        )
                        .frame(width: layout.dotDiameter, height: layout.dotDiameter)
                        .position(
                            x: dotX(at: index, in: proxy.size),
                            y: layout.dotY(for: entry.position)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(refreshAnimation, value: dotEntries)
        }
    }

    /// Region geometry for the dots preview: gray bar, gap, blue band, gap,
    /// gray bar — proportioned like the Health app's card.
    private struct DotPreviewLayout {
        let barHeight: CGFloat
        let gap: CGFloat
        let bandHeight: CGFloat
        let bandTopY: CGFloat
        let dotDiameter: CGFloat
        let dotStroke: CGFloat
        private let height: CGFloat

        init(size: CGSize) {
            height = size.height
            barHeight = max(size.height * 0.17, 4)
            gap = max(size.height * 0.045, 1.5)
            bandHeight = max(size.height - 2 * (barHeight + gap), 8)
            bandTopY = barHeight + gap
            dotDiameter = max(min(bandHeight * 0.32, size.width * 0.16), 5)
            dotStroke = max(dotDiameter * 0.26, 2)
        }

        var bandCornerRadius: CGFloat {
            max(bandHeight * 0.14, 3)
        }

        var topBarCenterY: CGFloat {
            barHeight / 2
        }

        var bandCenterY: CGFloat {
            bandTopY + bandHeight / 2
        }

        var bottomBarCenterY: CGFloat {
            height - barHeight / 2
        }

        /// `markerPosition` maps the typical band to [1/3, 2/3]; that middle
        /// third stretches over the blue band and the outer thirds collapse
        /// onto their gray bars, mirroring the regions of the drawn shapes.
        func dotY(for position: Double) -> CGFloat {
            let clamped = min(max(position, 0), 1)
            let halfDot = dotDiameter / 2

            if clamped > 2.0 / 3.0 {
                return topBarCenterY
            }

            if clamped < 1.0 / 3.0 {
                return bottomBarCenterY
            }

            let bandFraction = (2.0 / 3.0 - clamped) * 3
            let minY = bandTopY + halfDot + 0.5
            let maxY = bandTopY + bandHeight - halfDot - 0.5
            return min(max(bandTopY + bandHeight * CGFloat(bandFraction), minY), maxY)
        }
    }

    private func dotX(at index: Int, in size: CGSize) -> CGFloat {
        size.width * (CGFloat(index) + 0.5) / CGFloat(max(dotEntries.count, 1))
    }

    private func dotColor(for entry: BodyHealthMetricCard.Model.DotEntry) -> Color {
        switch entry.region {
        case .typical:
            return BodyVitalsChartStyle.typicalColor
        case .high:
            return BodyVitalsChartStyle.highColor
        case .low:
            return BodyVitalsChartStyle.lowColor
        }
    }
}

struct AnimatablePolyline: Shape {
    var points: [CGPoint]

    var animatableData: AnimatableVector {
        get { AnimatableVector(points: points) }
        set { points = newValue.points }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

struct AnimatableVector: VectorArithmetic {
    static var zero: AnimatableVector { AnimatableVector(values: []) }

    var values: [Double]

    init(values: [Double]) {
        self.values = values
    }

    init(points: [CGPoint]) {
        self.values = points.flatMap { [Double($0.x), Double($0.y)] }
    }

    var points: [CGPoint] {
        let count = values.count / 2
        return (0..<count).map { i in
            CGPoint(x: values[i * 2], y: values[i * 2 + 1])
        }
    }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(values: zip(padded(lhs.values, to: rhs.values.count),
                                     padded(rhs.values, to: lhs.values.count)).map(+))
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(values: zip(padded(lhs.values, to: rhs.values.count),
                                     padded(rhs.values, to: lhs.values.count)).map(-))
    }

    mutating func scale(by rhs: Double) {
        for i in values.indices {
            values[i] *= rhs
        }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func padded(_ values: [Double], to count: Int) -> [Double] {
        guard values.count < count else { return values }
        return values + Array(repeating: 0, count: count - values.count)
    }
}
