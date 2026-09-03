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

        /// The cardio fitness level the newest reading landed in, for the levels
        /// preview. `Equatable` so the preview's animation has something to
        /// compare — without it the ring would jump between rows.
        struct LevelEntry: Equatable {
            var level: CardioFitnessLevel
            /// 0…1 *within this level's own row*, 1 at the top of the row (the
            /// level's upper bound). 0.5 when the band is open-ended and there
            /// is no span to place the reading in.
            var position: Double
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
        let levelPreviewEntry: LevelEntry?
        let warningSymbolName: String?

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
            levelPreviewEntry: LevelEntry? = nil,
            warningSymbolName: String? = nil,
            previewDayCount: Int = BodyHomeMetricCardPreview.previewDayCount
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
            self.levelPreviewEntry = levelPreviewEntry
            self.warningSymbolName = warningSymbolName
            // Preview points are derived once per model — the preview view
            // used to regroup the full trend series in chained computed
            // properties on every render of every card.
            // The dots preview keeps drawing its three regions while the night's
            // vitals are pending, so the card doesn't lose the chart and get it
            // back — it fills the skeleton in place. The levels preview does the
            // same while the reading is unclassified: four gray rows, no ring.
            // Both keep drawing once nothing is coming either, so a card that
            // learns its category is empty settles in place instead of dropping
            // its preview and lurching the grid.
            hasChartPreview = chartPreview != nil
                || chartRangePreview != nil
                || !previewDotEntries.isEmpty
                || chartPreviewStyle == .dots
                || chartPreviewStyle == .levels
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

        /// Cards whose headline is a status word rather than a number: Vitals'
        /// "Typical"/"Below Average" and Stress's band word ("Rest"/"Low"/…).
        var usesWordValue: Bool {
            kind == .vitals || kind == .stress
        }
    }

    /// What a mini preview is actually showing. Emptiness alone can't tell
    /// "still loading" from "nothing to load": someone who granted Body two or
    /// three Health categories has nothing in flight for the rest, and reading
    /// empty as pending left those cards wearing a skeleton that never filled —
    /// a dashboard that looks like it is loading forever.
    enum PreviewPhase: Equatable {
        /// Entries to draw. Renders the same while a refresh runs, so a card
        /// with history never drops back to a skeleton mid-refresh.
        case data
        /// Nothing yet, but a refresh is in flight — today's skeleton, which
        /// fills in place when the reading lands.
        case pending
        /// Nothing, and nothing on the way: the category is off or empty, or
        /// the reading can't be classified. A calm empty shape, not a skeleton.
        case unavailable

        /// Not `private`: `BodyTests` exercises this truth table directly.
        static func resolved(for metric: Model, isRefreshing: Bool) -> PreviewPhase {
            let hasEntries: Bool
            switch metric.chartPreviewStyle {
            case .dots:
                hasEntries = !metric.previewDotEntries.isEmpty
            case .levels:
                hasEntries = metric.levelPreviewEntry != nil
            case .line, .bar, .range:
                // These previews plot whatever points they were handed and have
                // never faked a skeleton for the missing ones, so there is no
                // waiting state for them to be caught in.
                hasEntries = true
            }

            if hasEntries {
                return .data
            }

            return isRefreshing ? .pending : .unavailable
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let metric: Model
    /// Whether a health refresh is in flight. It is the only thing that
    /// separates a pending preview from an unavailable one, so the card takes
    /// it rather than guessing from emptiness.
    var isRefreshing: Bool = false
    /// The width of the container the card is laid out in, measured by the host
    /// rather than read from `UIScreen`: under Split View and Stage Manager the
    /// screen is wider than the page, and the card sized its preview for a screen
    /// it did not have. Zero (the default outside the Home grid) draws the
    /// compact preview.
    var containerWidth: CGFloat = 0

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

                warningBadge

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

                warningBadge

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(metric.prominentMetrics) { display in
                        displayValueRow(display, valueFontSize: valueFontSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            visualStack
        }
    }

    @ViewBuilder
    private var warningBadge: some View {
        // Sits between two spacers so it centres in the gap between the title
        // and the value instead of hugging the title. Wrapped in a ZStack so the
        // glyph's insertion/removal is a real transition (fade in AND out) rather
        // than an instant swap; keyed on the symbol name so only that change
        // animates, not the card's frequent re-renders.
        ZStack {
            if let warningSymbolName = metric.warningSymbolName {
                Image(systemName: warningSymbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Low Heart Rate"))
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: metric.warningSymbolName)
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
                    levelPreviewEntry: metric.levelPreviewEntry,
                    tintColor: metric.symbolColor,
                    style: metric.chartPreviewStyle,
                    phase: PreviewPhase.resolved(for: metric, isRefreshing: isRefreshing),
                    containerWidth: containerWidth
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
            width: BodyHomeMetricCardPreview.previewWidth(for: metric.chartPreviewStyle, screenWidth: containerWidth),
            alignment: .bottomTrailing
        )
        .padding(.bottom, 4)
    }

    // Word values run longer than digits, so vitals and cardio fitness set them
    // a touch smaller than the numeric cards.
    private var valueFontSize: CGFloat {
        metric.usesWordValue ? 22 : 23
    }

    private var valueRow: some View {
        displayValueRow(
            BodyMetricDisplayValue(title: metric.title, value: metric.value, unit: metric.unit),
            valueFontSize: valueFontSize
        )
    }

    private func displayValueRow(_ display: BodyMetricDisplayValue, valueFontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Group {
                // Word values ("Typical", "2 Outliers", "Below Average") must not
                // get the numeric text treatment digits rely on.
                if metric.usesWordValue {
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
    let levelPreviewEntry: BodyHealthMetricCard.Model.LevelEntry?
    let tintColor: Color
    let style: BodyHomeMetricCardPreview.Style
    let phase: BodyHealthMetricCard.PreviewPhase
    /// See `BodyHealthMetricCard.containerWidth`.
    let containerWidth: CGFloat
    /// Whether the preview has already drawn real data. Days without a value sit
    /// on the baseline and skeleton entries rest mid-band, so the first refresh
    /// that fills a cached or empty preview would otherwise animate every bar,
    /// point, ring and level up from where the placeholder was. The first data
    /// frame lands without motion; later refreshes, where values genuinely move,
    /// keep the refresh animation.
    @State private var hasShownData = false

    init(
        calendarPoints: [HealthTrendCalendarPoint],
        rangeCalendarPoints: [HealthTrendRangeCalendarPoint] = [],
        dotEntries: [BodyHealthMetricCard.Model.DotEntry] = [],
        levelPreviewEntry: BodyHealthMetricCard.Model.LevelEntry? = nil,
        tintColor: Color,
        style: BodyHomeMetricCardPreview.Style,
        phase: BodyHealthMetricCard.PreviewPhase = .data,
        containerWidth: CGFloat = 0
    ) {
        self.calendarPoints = calendarPoints
        self.rangeCalendarPoints = rangeCalendarPoints
        self.dotEntries = dotEntries
        self.levelPreviewEntry = levelPreviewEntry
        self.tintColor = tintColor
        self.style = style
        self.phase = phase
        self.containerWidth = containerWidth
    }

    private var refreshAnimation: Animation? {
        reduceMotion || !hasShownData ? nil : .smooth(duration: 0.45, extraBounce: 0)
    }

    /// True once any preview style has something real to draw.
    private var hasData: Bool {
        switch style {
        case .line, .bar:
            return !values.isEmpty
        case .range:
            return lastRangeValueIndex != nil
        case .dots:
            return phase == .data && !dotEntries.isEmpty
        case .levels:
            return phase == .data && levelPreviewEntry != nil
        }
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
            case .levels:
                levelsPreview
            }
        }
        .frame(width: previewWidth, height: previewHeight, alignment: .bottomTrailing)
        .accessibilityHidden(true)
        .onChange(of: hasData, initial: true) { _, hasData in
            if hasData {
                hasShownData = true
            }
        }
    }

    private var previewWidth: CGFloat {
        BodyHomeMetricCardPreview.previewWidth(for: style, screenWidth: containerWidth)
    }

    private var previewHeight: CGFloat {
        BodyHomeMetricCardPreview.previewHeight(forScreenWidth: containerWidth)
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

    /// One ring in the dots preview. A `nil` region is the waiting-for-data
    /// skeleton: the ring reads gray and rests in the middle of the band until
    /// the night's assessment lands.
    private struct PreviewDot: Equatable {
        var position: Double
        var region: SleepVitalRegion?
    }

    /// One skeleton ring per vital, so the pending card shows the same number of
    /// rings the assessed one will.
    private static let placeholderDotCount = VitalKind.allCases.count

    private var previewDots: [PreviewDot] {
        switch phase {
        case .data:
            return dotEntries.map { PreviewDot(position: $0.position, region: $0.region) }
        case .pending:
            return Array(
                repeating: PreviewDot(position: 0.5, region: nil),
                count: Self.placeholderDotCount
            )
        case .unavailable:
            // No rings at all: the skeleton ones promise readings that are
            // coming, and with Sleep off or empty and no refresh running none
            // are. The three regions stay, so the card keeps its height and
            // reads as a metric with no data rather than one still loading.
            return []
        }
    }

    private var isAwaitingDots: Bool {
        phase != .data
    }

    /// Health's Vitals preview: three stacked rounded regions — high, the
    /// typical band, low — and one dark-centered ring per vital resting in the
    /// region its reading landed in. The regions share the preview's height by
    /// where the rings are, so the space goes where the data is: rings in all
    /// three splits it evenly, rings in two share it while the empty region
    /// stays at its minimum, and rings in one region give it the tall slot.
    /// Before the night's vitals are in, the same three regions render dimmed
    /// at equal height with gray rings resting in the middle; when the
    /// assessment arrives the band takes its color, the regions morph to their
    /// new proportions, and each ring glides to the region it belongs in — one
    /// motion, since every height here is a function of `dotEntries`. Once
    /// there is nothing left to wait for the gray rings go and the three dimmed
    /// regions stay on their own: the card keeps its height without claiming a
    /// reading is on its way.
    private var dotsPreview: some View {
        GeometryReader { proxy in
            let dots = previewDots
            let layout = DotPreviewLayout(size: proxy.size, occupied: occupiedRegions(for: dots))

            ZStack {
                RoundedRectangle(cornerRadius: layout.cornerRadius(for: .high), style: .continuous)
                    .fill(Color.secondary.opacity(isAwaitingDots ? 0.24 : 0.42))
                    .frame(width: proxy.size.width, height: layout.height(for: .high))
                    .position(x: proxy.size.width / 2, y: layout.centerY(for: .high))

                RoundedRectangle(cornerRadius: layout.cornerRadius(for: .typical), style: .continuous)
                    .fill(bandColor)
                    .frame(width: proxy.size.width, height: layout.height(for: .typical))
                    .position(x: proxy.size.width / 2, y: layout.centerY(for: .typical))

                RoundedRectangle(cornerRadius: layout.cornerRadius(for: .low), style: .continuous)
                    .fill(Color.secondary.opacity(isAwaitingDots ? 0.24 : 0.42))
                    .frame(width: proxy.size.width, height: layout.height(for: .low))
                    .position(x: proxy.size.width / 2, y: layout.centerY(for: .low))

                ForEach(Array(dots.enumerated()), id: \.offset) { index, dot in
                    Circle()
                        .fill(Color.black.opacity(0.62))
                        .overlay(
                            Circle()
                                .strokeBorder(dotColor(for: dot), lineWidth: layout.dotStroke)
                        )
                        .frame(width: layout.dotDiameter, height: layout.dotDiameter)
                        .position(
                            x: dotX(at: index, in: proxy.size, count: dots.count),
                            y: layout.dotY(for: dot.position)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // With nothing coming the regions drop from the skeleton's wash to
            // the fainter one a missing point gets in the bar and range
            // previews (0.24 × 0.58 ≈ 0.14, the levels preview's empty rows),
            // so neither empty preview reads as a skeleton about to fill.
            .opacity(phase == .unavailable ? 0.58 : 1)
            .animation(refreshAnimation, value: dotEntries)
            // A refresh that lands with nothing takes the skeleton rings away
            // without touching `dotEntries`, so that change needs its own key
            // or the rings pop out instead of fading.
            .animation(refreshAnimation, value: phase)
        }
    }

    /// Region geometry for the dots preview: high region, gap, typical band,
    /// gap, low region. How the three split the drawable height depends on how
    /// many of them hold rings — an even three-way split, an even split between
    /// two with the empty region held at its minimum, or one region at its
    /// maximum with the other two at minimum. The three heights always sum to
    /// the drawable height, so the preview's fixed frame stays exactly filled
    /// while the regions morph between cases.
    ///
    /// Not `private`: `BodyTests` exercises this height math directly.
    struct DotPreviewLayout {
        /// Height a region with no rings keeps, and the share of the plot the
        /// gaps between regions take.
        static let minRegionFraction: CGFloat = 0.17
        static let gapFraction: CGFloat = 0.045

        let gap: CGFloat
        let minRegionHeight: CGFloat
        let maxRegionHeight: CGFloat
        let dotDiameter: CGFloat
        let dotStroke: CGFloat
        private let highHeight: CGFloat
        private let typicalHeight: CGFloat
        private let lowHeight: CGFloat

        init(size: CGSize, occupied: Set<SleepVitalRegion>) {
            gap = min(max(size.height * Self.gapFraction, 1.5), size.height / 8)
            let available = max(size.height - 2 * gap, 1)
            // Clamping the minimum to a third is what keeps the three heights
            // summing to `available` in every case, however small the preview is.
            let minimum = min(max(size.height * Self.minRegionFraction, 4), available / 3)
            let maximum = available - 2 * minimum
            minRegionHeight = minimum
            maxRegionHeight = maximum

            func regionHeight(_ region: SleepVitalRegion, occupiedHeight: CGFloat) -> CGFloat {
                occupied.contains(region) ? occupiedHeight : minimum
            }

            switch occupied.count {
            case 1:
                highHeight = regionHeight(.high, occupiedHeight: maximum)
                typicalHeight = regionHeight(.typical, occupiedHeight: maximum)
                lowHeight = regionHeight(.low, occupiedHeight: maximum)
            case 2:
                let shared = (available - minimum) / 2
                highHeight = regionHeight(.high, occupiedHeight: shared)
                typicalHeight = regionHeight(.typical, occupiedHeight: shared)
                lowHeight = regionHeight(.low, occupiedHeight: shared)
            default:
                // Rings in all three regions, or none at all while the night is
                // still pending — both split the height evenly.
                let third = available / 3
                highHeight = third
                typicalHeight = third
                lowHeight = third
            }

            // Ring size stays fixed across every case so the rings glide rather
            // than resize while the regions morph. `maximum` is the constant
            // reference the typical band used to supply, and the minimum region
            // height caps it so a ring can never outgrow the thinnest region.
            dotDiameter = min(max(min(maximum * 0.32, size.width * 0.16), 5), minimum)
            dotStroke = max(dotDiameter * 0.26, 2)
        }

        /// Which region a dot position lands in. Used both to place a ring and
        /// to decide which regions are occupied, so the layout can never grow a
        /// region the rings don't actually land in.
        static func regionSlot(for position: Double) -> SleepVitalRegion {
            let clamped = min(max(position, 0), 1)

            if clamped > 2.0 / 3.0 {
                return .high
            }

            if clamped < 1.0 / 3.0 {
                return .low
            }

            return .typical
        }

        func height(for region: SleepVitalRegion) -> CGFloat {
            switch region {
            case .high:
                return highHeight
            case .typical:
                return typicalHeight
            case .low:
                return lowHeight
            }
        }

        func topY(for region: SleepVitalRegion) -> CGFloat {
            switch region {
            case .high:
                return 0
            case .typical:
                return highHeight + gap
            case .low:
                return highHeight + gap + typicalHeight + gap
            }
        }

        func centerY(for region: SleepVitalRegion) -> CGFloat {
            topY(for: region) + height(for: region) / 2
        }

        func cornerRadius(for region: SleepVitalRegion) -> CGFloat {
            max(height(for: region) * 0.14, 3)
        }

        /// `markerPosition` maps the typical band to [1/3, 2/3]; that middle
        /// third stretches over the typical region and the outer thirds collapse
        /// onto the high and low regions, mirroring the drawn shapes.
        func dotY(for position: Double) -> CGFloat {
            let clamped = min(max(position, 0), 1)
            let region = Self.regionSlot(for: clamped)

            guard region == .typical else {
                return centerY(for: region)
            }

            let halfDot = dotDiameter / 2
            let bandTopY = topY(for: .typical)
            let bandFraction = (2.0 / 3.0 - clamped) * 3
            let minY = bandTopY + halfDot + 0.5
            let maxY = bandTopY + typicalHeight - halfDot - 0.5
            return min(max(bandTopY + typicalHeight * CGFloat(bandFraction), minY), maxY)
        }
    }

    /// Which regions currently hold a ring. Read from the dot positions rather
    /// than `DotEntry.region` so the grown region and the drawn ring can never
    /// disagree. Empty whenever there is no assessment — pending or not — which
    /// the layout reads as an even three-way split.
    private func occupiedRegions(for dots: [PreviewDot]) -> Set<SleepVitalRegion> {
        guard !isAwaitingDots else {
            return []
        }

        return Set(dots.map { DotPreviewLayout.regionSlot(for: $0.position) })
    }

    private func dotX(at index: Int, in size: CGSize, count: Int) -> CGFloat {
        size.width * (CGFloat(index) + 0.5) / CGFloat(max(count, 1))
    }

    private var bandColor: Color {
        isAwaitingDots ? Color.secondary.opacity(0.24) : Color(red: 0.21, green: 0.30, blue: 0.45)
    }

    private func dotColor(for dot: PreviewDot) -> Color {
        switch dot.region {
        case .typical:
            return BodyVitalsChartStyle.typicalColor
        case .high:
            return BodyVitalsChartStyle.highColor
        case .low:
            return BodyVitalsChartStyle.lowColor
        case nil:
            return Color.secondary.opacity(0.45)
        }
    }

    /// Health's Cardio Fitness preview: the four fitness levels as equal stacked
    /// rows — high at the top, low at the bottom — with the row the newest VO₂
    /// max reading landed in taking that level's color and holding one
    /// dark-centered ring at the reading's place inside that row. While the
    /// reading is unclassified — no VO₂ max yet, or an age the norms don't cover
    /// — the same four rows render dimmed with no ring, so the card shows the
    /// shape of the metric rather than an empty corner; how dimmed depends on
    /// whether a refresh could still classify it. Row heights are fixed,
    /// unlike the dots preview: there is only ever one reading, so growing its
    /// row would make the card lurch every time the level changed. That leaves
    /// the tint and the ring as the only things that move when a reading lands.
    private var levelsPreview: some View {
        GeometryReader { proxy in
            let layout = LevelPreviewLayout(size: proxy.size)

            ZStack {
                ForEach(CardioFitnessLevel.displayOrder, id: \.self) { level in
                    RoundedRectangle(cornerRadius: layout.cornerRadius(for: level), style: .continuous)
                        .fill(levelRowColor(for: level))
                        .frame(width: proxy.size.width, height: layout.height(for: level))
                        .position(x: proxy.size.width / 2, y: layout.centerY(for: level))
                }

                if let entry = levelPreviewEntry {
                    Circle()
                        .fill(Color.black.opacity(0.62))
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    BodyCardioFitnessLevelPresentation.color(for: entry.level),
                                    lineWidth: layout.ringStroke
                                )
                        )
                        .frame(width: layout.ringDiameter, height: layout.ringDiameter)
                        .position(
                            x: proxy.size.width / 2,
                            y: layout.ringY(for: entry.level, position: entry.position)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(refreshAnimation, value: levelPreviewEntry)
            // The rows settling from the skeleton wash to the empty one is a
            // phase change, not an entry change, so it needs its own key.
            .animation(refreshAnimation, value: phase)
        }
    }

    private func levelRowColor(for level: CardioFitnessLevel) -> Color {
        guard let entry = levelPreviewEntry else {
            // The dots preview's dimmed skeleton while a refresh could still
            // bring the reading in, and the fainter wash a missing point gets in
            // the bar and range previews once it can't: no VO₂ max to classify,
            // or a reading the norms have no band for. Nothing is coming, so the
            // rows must stop looking like a skeleton about to fill.
            return Color.secondary.opacity(phase == .pending ? 0.24 : 0.14)
        }

        // The occupied row is a muted wash of its level color, not the full
        // tint: the ring sits inside it, and the dots preview gets its ring
        // legible the same way — a dark, desaturated band under a fully
        // saturated ring. A full-strength row would swallow the ring, which is
        // the only thing marking where in the level the reading falls.
        return level == entry.level
            ? BodyCardioFitnessLevelPresentation.color(for: level).opacity(0.42)
            : Color.secondary.opacity(0.42)
    }

    /// Row geometry for the levels preview: four equal rows separated by three
    /// gaps, highest level first. The four heights plus the three gaps always
    /// sum to the drawable height, so the preview's fixed frame stays exactly
    /// filled at any size.
    ///
    /// Not `private`: `BodyTests` exercises this height math directly.
    struct LevelPreviewLayout {
        /// Share of the preview's height each gap between rows takes.
        static let gapFraction: CGFloat = 0.045

        static var rowCount: Int {
            CardioFitnessLevel.displayOrder.count
        }

        let gap: CGFloat
        let rowHeight: CGFloat
        let ringDiameter: CGFloat
        let ringStroke: CGFloat

        init(size: CGSize) {
            let height = max(size.height, 0)
            let rows = CGFloat(Self.rowCount)
            // Capping a gap at half a row's even share is what keeps the rows and
            // gaps summing to the drawable height however small the preview is:
            // the three gaps can never claim more than half of it.
            gap = min(max(height * Self.gapFraction, 1.5), height / (2 * (rows - 1)))
            rowHeight = (height - gap * (rows - 1)) / rows
            // The ring keeps one size across every level so it glides rather than
            // resizes as it moves rows, and a row's height is the hard cap so it
            // can never outgrow the row it rests in.
            ringDiameter = min(max(min(rowHeight * 0.72, size.width * 0.16), 5), rowHeight)
            ringStroke = max(ringDiameter * 0.26, 2)
        }

        /// Every row is the same height — the level is taken so callers read the
        /// same way the dots preview's do.
        func height(for level: CardioFitnessLevel) -> CGFloat {
            rowHeight
        }

        func topY(for level: CardioFitnessLevel) -> CGFloat {
            CGFloat(Self.rowIndex(of: level)) * (rowHeight + gap)
        }

        func centerY(for level: CardioFitnessLevel) -> CGFloat {
            topY(for: level) + rowHeight / 2
        }

        func cornerRadius(for level: CardioFitnessLevel) -> CGFloat {
            max(height(for: level) * 0.14, 3)
        }

        /// Where the ring rests inside its own row: `position` 1 is the top of
        /// the row (the level's upper bound), 0 the bottom, matching the
        /// highest-first stacking. The ring stays a half-diameter clear of both
        /// row edges so it never bleeds into a neighbouring level.
        func ringY(for level: CardioFitnessLevel, position: Double) -> CGFloat {
            let clamped = min(max(position, 0), 1)
            let top = topY(for: level)
            let halfRing = ringDiameter / 2
            let minY = top + halfRing + 0.5
            let maxY = top + rowHeight - halfRing - 0.5

            guard minY <= maxY else {
                // At very small preview sizes the ring fills its row outright,
                // so there is no travel left to spend.
                return centerY(for: level)
            }

            return min(max(top + rowHeight * CGFloat(1 - clamped), minY), maxY)
        }

        private static func rowIndex(of level: CardioFitnessLevel) -> Int {
            CardioFitnessLevel.displayOrder.firstIndex(of: level) ?? 0
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

    /// Pads the shorter operand so a polyline can interpolate against one with a
    /// different point count.
    ///
    /// An empty vector keeps zero padding: `.zero` IS the empty vector, and
    /// `VectorArithmetic` requires `.zero + v == v`, so padding it with anything
    /// else would make insert and remove transitions draw nothing. A non-empty
    /// vector repeats its last POINT instead of zeros: zero padding used to drag
    /// the extra vertices to the origin, so growing a preview by a day swept a
    /// line across the corner of the card. Repeating the last point parks them on
    /// the final vertex, which is inside the polyline's own bounding box.
    private static func padded(_ values: [Double], to count: Int) -> [Double] {
        guard values.count < count else { return values }
        guard values.count >= 2 else {
            return values + Array(repeating: 0, count: count - values.count)
        }

        var padded = values
        let lastPoint = Array(values.suffix(2))
        while padded.count < count {
            padded.append(lastPoint[padded.count % 2])
        }
        return padded
    }
}
