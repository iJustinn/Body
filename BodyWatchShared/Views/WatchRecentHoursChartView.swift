//
//  WatchRecentHoursChartView.swift
//  BodyWatchShared
//
//  The intraday chart complications' drawing (accessoryRectangular): the
//  Stress page's "Last 12 hours" chart or the Heart Rate, HRV and Blood
//  Oxygen pages' "Last 8 hours" chart, compacted to fill the slot with no
//  header: the metric's name and latest reading are only spoken by
//  VoiceOver. A value axis runs down the left like the pages' (Stress 0, 50
//  and 100 on its band grid, the others round values over faint gridlines,
//  never past Blood Oxygen's 100%), small even hour labels sit along the
//  bottom, and while a sleep, nap or workout band is in the Stress window a
//  row above the plot carries each band's symbol. The
//  window, hour labels, line breaks, value range, marks and shading spans
//  come from the geometry the pages draw with (`WatchIntradayChartGeometry`,
//  `WatchStressChartGeometry`), so a complication never charts differently
//  from the page it opens; the colors, opacities and symbols are the pages'
//  own, workouts in the phone's workout colors (`palette`), the sizes cut
//  down for a plot about half as tall. Only the data marks take a tinted
//  face's accent (`widgetAccentable`), so the ranges, shading, grid, symbols
//  and labels around them stay in the default group. When nothing falls
//  inside the window, a caption takes the plot's place. Every string arrives
//  localized from the widget, so this file holds no localizable literal, and
//  no `containerBackground` here; the widget adds its own.
//
//  Watch-only: not compiled into the iOS `Body` target. It lives here rather
//  than in the widget extension so `BodyWatchTests` can test and render it.
//  The widget extension compiles `BodyWorkoutType` and
//  `BodyWorkoutColorPalette` from BodyMetricsKit for the workout symbols and
//  colors.
//

import SwiftUI
import WidgetKit

struct WatchRecentHoursChartView: View {
    /// What the plot draws.
    enum Content {
        /// Heart Rate, HRV or Blood Oxygen: each 30 minute slot's range under
        /// a line through the slot averages, in the metric's tint.
        case readings([WatchIntradayBucket], tint: Color)
        /// Stress: the 15 minute windows over their sleep and workout shading,
        /// or nil when the snapshot carries no timeline.
        case stress(WatchStressTimeline?)
    }

    /// The metric's name, VoiceOver's label.
    let title: String
    /// The latest reading ("--" without one), VoiceOver's value while the
    /// window has a plot.
    let reading: String
    let content: Content
    /// The window's end: the plot shows the chart's window ending in the
    /// current local half hour slot, aligned like the pages' charts.
    let now: Date
    /// The caption in the plot's place when nothing falls inside the window.
    let emptyText: String
    /// The most `.readings` values can reach (Blood Oxygen's 100%,
    /// `WatchMetricKindKey.valueCeiling`), or nil: no axis label past it.
    var valueCeiling: Double? = nil
    var calendar: Calendar = .current
    /// Workout shading and symbol colors, the phone's custom colors included.
    var palette: BodyWorkoutColorPalette = .builtIn

    // MARK: - Layout

    private static let textFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    /// The hour labels and the value axis's labels.
    private static let axisFont = Font.system(size: 7, weight: .medium, design: .rounded)
    /// The row along the bottom the hour labels sit in.
    static let hourRowHeight: CGFloat = 8
    /// The row over the Stress plot its band symbols sit in, reserved only
    /// while a band is in the window.
    static let iconRowHeight: CGFloat = 7
    private static let iconFont = Font.system(size: 6.5, weight: .bold)
    /// The space between the value labels and the plot.
    private static let axisGap: CGFloat = 2
    /// About half a value label's digits: the least the plot keeps clear
    /// above its top line and below its bottom one, so a label centered on
    /// either is drawn whole.
    static let axisLabelHalfHeight: CGFloat = 3
    /// The Stress axis labels: every other dashed gridline.
    static let stressAxisScores = [0, 50, 100]

    // MARK: - Readings: `WatchIntradayChartView`'s range style, slimmed

    /// Slots across the plot: the window plus the current slot.
    private static let slotCount = WatchIntradayWindow.length / WatchIntradayWindow.slotLength + 1
    private static let rangeColor = Color.white.opacity(0.28)
    private static let lineWidth: CGFloat = 1.5
    /// Solid rather than the page's ringed dots: on a tinted face every
    /// opaque fill renders as solid accent, so a ring around a black center
    /// would merge into one dot there anyway.
    private static let pointDiameter: CGFloat = 4
    private static let latestPointDiameter: CGFloat = 6
    /// The page's value gridlines (`AxisGridLine` at white 0.18).
    private static let valueGridColor = Color.white.opacity(0.18)

    // MARK: - Stress: `StressChartStyle`'s colors and opacities, sizes halved

    private static let sleepFillOpacity = 0.14
    private static let workoutFillOpacity = 0.10
    private static let stripeHeight: CGFloat = 1
    private static let gridOpacity = 0.26
    private static let gridLineWidth: CGFloat = 0.5
    private static let gridDash: [CGFloat] = [2, 2]
    private static let columnOpacity = 0.10
    private static let columnCornerRadius: CGFloat = 1
    private static let capsuleHeight: CGFloat = 3
    private static let activityStubHeight: CGFloat = 3
    private static let activityOpacity = 0.45
    private static let markInset: CGFloat = 0.5
    private static let markMinimumWidth: CGFloat = 1.5
    /// The context band kinds this build shades and labels with a symbol; a
    /// newer phone could push another, which draws nothing.
    private static let drawnContextKinds: Set<String> = [
        WatchStressContextBand.sleepKind,
        WatchStressContextBand.napKind,
        WatchStressContextBand.workoutKind
    ]

    var body: some View {
        let domain = Self.domain(for: content, endingAt: now, calendar: calendar)
        let hasPlot = Self.hasPlot(content, endingAt: now, calendar: calendar)
        Group {
            if hasPlot {
                plot(domain: domain)
            } else {
                Text(emptyText)
                    .font(Self.textFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Nothing on screen names the chart, so VoiceOver reads the name
        // with the latest reading, or with the caption it shows instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(hasPlot ? reading : emptyText)
    }

    /// Everything around the data (the axis and hour labels, the symbols,
    /// ranges, shading, grid and columns) and the data marks in front, on
    /// separate canvases so only the marks take the accent. Both lay out the
    /// same plot rect, from the same measured axis labels.
    private func plot(domain: ClosedRange<Date>) -> some View {
        let values = axisValues(domain: domain)
        let hasIconRow = Self.hasIconRow(content, domain: domain)
        return ZStack {
            Canvas { context, size in
                let labels = values.map { axisLabel($0, context: context) }
                let plotRect = layoutPlot(in: size, labels: labels, hasIconRow: hasIconRow)
                switch content {
                case let .readings(buckets, _):
                    let valueDomain = Self.valueDomain(for: buckets, in: domain, ceiling: valueCeiling)
                    drawValueGrid(values, valueDomain: valueDomain, in: plotRect, context: &context)
                    drawRanges(
                        Self.visibleBuckets(buckets, in: domain),
                        values: valueDomain,
                        domain: domain,
                        in: plotRect,
                        context: &context
                    )
                case let .stress(timeline):
                    if let timeline {
                        drawStressContext(timeline, domain: domain, in: plotRect, context: &context)
                    }
                }
                for (value, label) in zip(values, labels) {
                    context.draw(label, at: CGPoint(x: plotRect.minX - Self.axisGap, y: axisY(for: value, domain: domain, in: plotRect)), anchor: .trailing)
                }
                drawHourLabels(domain: domain, in: plotRect, canvasHeight: size.height, context: &context)
            }
            Canvas { context, size in
                let labels = values.map { axisLabel($0, context: context) }
                let plotRect = layoutPlot(in: size, labels: labels, hasIconRow: hasIconRow)
                switch content {
                case let .readings(buckets, tint):
                    drawReadings(
                        Self.visibleBuckets(buckets, in: domain),
                        tint: tint,
                        values: Self.valueDomain(for: buckets, in: domain, ceiling: valueCeiling),
                        domain: domain,
                        in: plotRect,
                        context: &context
                    )
                case let .stress(timeline):
                    guard let timeline else { return }
                    drawStressMarks(
                        WatchStressChartGeometry.marks(in: timeline, domain: domain),
                        in: plotRect,
                        context: &context
                    )
                }
            }
            .widgetAccentable()
        }
    }

    // MARK: - Axes

    /// The values the axis labels: Stress's fixed scores, or the round
    /// values inside the Heart Rate, HRV or Blood Oxygen value range.
    private func axisValues(domain: ClosedRange<Date>) -> [Double] {
        switch content {
        case let .readings(buckets, _):
            return WatchIntradayChartGeometry.valueTicks(in: Self.valueDomain(for: buckets, in: domain, ceiling: valueCeiling))
        case .stress:
            return Self.stressAxisScores.map(Double.init)
        }
    }

    private func axisLabel(_ value: Double, context: GraphicsContext) -> GraphicsContext.ResolvedText {
        context.resolve(
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(Self.axisFont)
                .foregroundStyle(.secondary)
        )
    }

    private func axisY(for value: Double, domain: ClosedRange<Date>, in plotRect: CGRect) -> CGFloat {
        switch content {
        case let .readings(buckets, _):
            return Self.y(for: value, in: Self.valueDomain(for: buckets, in: domain, ceiling: valueCeiling), plotRect: plotRect)
        case .stress:
            return WatchStressChartGeometry.y(forScore: value, in: plotRect)
        }
    }

    /// The plot right of the widest axis label, from this canvas's own
    /// measure, so both canvases agree.
    private func layoutPlot(in size: CGSize, labels: [GraphicsContext.ResolvedText], hasIconRow: Bool) -> CGRect {
        let widest = labels.map { $0.measure(in: size).width }.max()
        let markHalfHeight: CGFloat
        switch content {
        case .readings: markHalfHeight = Self.latestPointDiameter / 2
        case .stress: markHalfHeight = Self.capsuleHeight / 2
        }
        return Self.plotRect(
            in: size,
            axisWidth: widest.map { $0 + Self.axisGap } ?? 0,
            hasIconRow: hasIconRow,
            markHalfHeight: markHalfHeight
        )
    }

    /// The pages' even local hours along the bottom, centered under their
    /// hour. In the calendar's time zone, so a label always names the hour its
    /// tick was placed on. Hidden from VoiceOver, which reads the name and
    /// reading.
    private func drawHourLabels(domain: ClosedRange<Date>, in plotRect: CGRect, canvasHeight: CGFloat, context: inout GraphicsContext) {
        let format = Date.FormatStyle(timeZone: calendar.timeZone).hour(.twoDigits(amPM: .omitted))
        for tick in WatchIntradayChartGeometry.hourTicks(in: domain, calendar: calendar) {
            context.draw(
                context.resolve(
                    Text(tick.formatted(format))
                        .font(Self.axisFont)
                        .foregroundStyle(.secondary)
                ),
                at: CGPoint(x: Self.x(for: tick, in: domain, plotRect: plotRect), y: canvasHeight),
                anchor: .bottom
            )
        }
    }

    // MARK: - Drawing: readings

    /// A faint line across the plot at each labeled value.
    private func drawValueGrid(_ values: [Double], valueDomain: ClosedRange<Double>, in plotRect: CGRect, context: inout GraphicsContext) {
        var grid = Path()
        for value in values {
            let y = Self.y(for: value, in: valueDomain, plotRect: plotRect)
            grid.move(to: CGPoint(x: plotRect.minX, y: y))
            grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(grid, with: .color(Self.valueGridColor), lineWidth: Self.gridLineWidth)
    }

    /// Each slot's min to max range as a faint capsule across the slot's
    /// middle, or a dot of the capsule's width for a single reading.
    private func drawRanges(_ buckets: [WatchIntradayBucket], values: ClosedRange<Double>, domain: ClosedRange<Date>, in plotRect: CGRect, context: inout GraphicsContext) {
        let width = Self.capsuleWidth(forPlotWidth: plotRect.width)
        for bucket in buckets {
            let x = Self.x(for: bucket.midpoint, in: domain, plotRect: plotRect)
            if bucket.minimum < bucket.maximum {
                let top = Self.y(for: bucket.maximum, in: values, plotRect: plotRect)
                let bottom = Self.y(for: bucket.minimum, in: values, plotRect: plotRect)
                let rect = CGRect(x: x - width / 2, y: top, width: width, height: bottom - top)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2),
                    with: .color(Self.rangeColor)
                )
            } else {
                let y = Self.y(for: bucket.average, in: values, plotRect: plotRect)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - width / 2, y: y - width / 2, width: width, height: width)),
                    with: .color(Self.rangeColor)
                )
            }
        }
    }

    /// The tinted line through the slot averages, broken where an hour or
    /// more has no readings, and a dot on every average, the latest larger.
    private func drawReadings(_ buckets: [WatchIntradayBucket], tint: Color, values: ClosedRange<Double>, domain: ClosedRange<Date>, in plotRect: CGRect, context: inout GraphicsContext) {
        func point(_ bucket: WatchIntradayBucket) -> CGPoint {
            CGPoint(
                x: Self.x(for: bucket.midpoint, in: domain, plotRect: plotRect),
                y: Self.y(for: bucket.average, in: values, plotRect: plotRect)
            )
        }

        for run in WatchIntradayChartGeometry.lineRuns(buckets) where run.count > 1 {
            var line = Path()
            line.addLines(run.map(point))
            context.stroke(
                line,
                with: .color(tint),
                style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }

        let latestStart = buckets.map(\.start).max()
        for bucket in buckets {
            let diameter = bucket.start == latestStart ? Self.latestPointDiameter : Self.pointDiameter
            let center = point(bucket)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)),
                with: .color(tint)
            )
        }
    }

    // MARK: - Drawing: Stress

    /// Everything behind the capsules, in the page's order: the sleep and
    /// workout shading with a stripe along its top and its symbol in the row
    /// above, the dashed band grid, and per window a faint column from the
    /// score to the floor in the band color, or the floor stub of a window
    /// masked as movement.
    private func drawStressContext(_ timeline: WatchStressTimeline, domain: ClosedRange<Date>, in plotRect: CGRect, context: inout GraphicsContext) {
        for span in WatchStressChartGeometry.contextSpans(in: timeline, domain: domain) {
            guard let style = style(for: span.band) else { continue }
            let leading = plotRect.minX + plotRect.width * CGFloat(span.xStart)
            let width = plotRect.width * CGFloat(span.xEnd - span.xStart)
            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: plotRect.height)),
                with: .color(style.color.opacity(style.fillOpacity))
            )
            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: Self.stripeHeight)),
                with: .color(style.color)
            )

            // Centered over the band, kept whole inside the plot's edges (a
            // band clipped at the window's start would otherwise draw half a
            // symbol), as on the page.
            let symbol = context.resolve(
                Text(Image(systemName: style.symbolName))
                    .font(Self.iconFont)
                    .foregroundStyle(style.color)
            )
            let halfWidth = symbol.measure(in: plotRect.size).width / 2
            let center = leading + width / 2
            context.draw(
                symbol,
                at: CGPoint(
                    x: min(max(center, plotRect.minX + halfWidth), max(plotRect.minX + halfWidth, plotRect.maxX - halfWidth)),
                    y: Self.iconRowHeight / 2
                )
            )
        }

        var grid = Path()
        for fraction in WatchStressChartGeometry.gridFractions {
            let y = WatchStressChartGeometry.y(forScore: fraction * 100, in: plotRect)
            grid.move(to: CGPoint(x: plotRect.minX, y: y))
            grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(
            grid,
            with: .color(Color.white.opacity(Self.gridOpacity)),
            style: StrokeStyle(lineWidth: Self.gridLineWidth, dash: Self.gridDash)
        )

        for mark in WatchStressChartGeometry.marks(in: timeline, domain: domain) {
            let span = Self.markSpan(mark, in: plotRect)
            switch mark.slot {
            case let .scored(score):
                let valueY = WatchStressChartGeometry.y(forScore: Double(score), in: plotRect)
                context.fill(
                    Path(
                        roundedRect: CGRect(x: span.x, y: valueY, width: span.width, height: max(0, plotRect.maxY - valueY)),
                        cornerRadius: min(Self.columnCornerRadius, span.width / 2)
                    ),
                    with: .color(Color(WatchStressBands.tint(forScore: score)).opacity(Self.columnOpacity))
                )
            case .activity:
                context.fill(
                    Path(
                        roundedRect: CGRect(x: span.x, y: plotRect.maxY - Self.activityStubHeight, width: span.width, height: Self.activityStubHeight),
                        cornerRadius: min(span.width, Self.activityStubHeight) / 2
                    ),
                    with: .color(Color.white.opacity(Self.activityOpacity))
                )
            case .none:
                continue
            }
        }
    }

    /// Each scored window's capsule, centered on its score in the band color.
    private func drawStressMarks(_ marks: [WatchStressChartGeometry.Mark], in plotRect: CGRect, context: inout GraphicsContext) {
        for mark in marks {
            guard case let .scored(score) = mark.slot else { continue }
            let span = Self.markSpan(mark, in: plotRect)
            let valueY = WatchStressChartGeometry.y(forScore: Double(score), in: plotRect)
            context.fill(
                Path(
                    roundedRect: CGRect(x: span.x, y: valueY - Self.capsuleHeight / 2, width: span.width, height: Self.capsuleHeight),
                    cornerRadius: min(span.width, Self.capsuleHeight) / 2
                ),
                with: .color(Color(WatchStressBands.tint(forScore: score)))
            )
        }
    }

    /// A context band's color, fill opacity and symbol, the page's
    /// (`WatchStressChartView.style(for:)`), or nil for a kind this build
    /// doesn't know. Sleep and naps in the Sleep blue the page shades them
    /// with (`StressChartStyle.sleepRGB`), a workout in its palette color
    /// under its type's symbol, each with a full color stripe.
    private func style(for band: WatchStressContextBand) -> (color: Color, fillOpacity: Double, symbolName: String)? {
        let sleep = Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.sleep))
        switch band.kind {
        case WatchStressContextBand.sleepKind:
            return (sleep, Self.sleepFillOpacity, "bed.double.fill")
        case WatchStressContextBand.napKind:
            return (sleep, Self.sleepFillOpacity, "moon.zzz.fill")
        case WatchStressContextBand.workoutKind:
            let type = band.workoutType.flatMap(BodyWorkoutType.init(rawValue:)) ?? .other
            return (palette.color(for: type), Self.workoutFillOpacity, type.symbolName)
        default:
            return nil
        }
    }

    private static func markSpan(_ mark: WatchStressChartGeometry.Mark, in plotRect: CGRect) -> (x: CGFloat, width: CGFloat) {
        WatchStressChartGeometry.markSpan(
            xStart: mark.xStart,
            xEnd: mark.xEnd,
            in: plotRect,
            inset: markInset,
            minimumWidth: markMinimumWidth
        )
    }

    // MARK: - Geometry

    /// The plot inside a canvas: right of the axis labels (`axisWidth`, their
    /// width and gap), under the icon row when there is one, over the hour
    /// row, and inset top and bottom by half its largest mark (the latest
    /// reading's dot, a Stress capsule) or half a label, whichever is more,
    /// so a mark at either end of the range and a label centered on the top
    /// or bottom line are both drawn whole.
    static func plotRect(in size: CGSize, axisWidth: CGFloat, hasIconRow: Bool, markHalfHeight: CGFloat) -> CGRect {
        let inset = max(markHalfHeight, axisLabelHalfHeight)
        let top = (hasIconRow ? iconRowHeight : 0) + inset
        return CGRect(
            x: axisWidth,
            y: top,
            width: max(0, size.width - axisWidth),
            height: max(0, size.height - hourRowHeight - inset - top)
        )
    }

    private static func x(for date: Date, in domain: ClosedRange<Date>, plotRect: CGRect) -> CGFloat {
        plotRect.minX + plotRect.width * CGFloat(WatchIntradayChartGeometry.fraction(for: date, in: domain))
    }

    private static func y(for value: Double, in values: ClosedRange<Double>, plotRect: CGRect) -> CGFloat {
        let span = values.upperBound - values.lowerBound
        let fraction = span > 0 ? (value - values.lowerBound) / span : 0.5
        return plotRect.maxY - plotRect.height * CGFloat(min(1, max(0, fraction)))
    }

    /// The x domain: the page's window ending at `now`, from its oldest
    /// slot's start through the current slot's end. 8 hours back for Heart
    /// Rate and HRV, Stress's 12 (`WatchStressChartGeometry.domain`).
    static func domain(for content: Content, endingAt now: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        switch content {
        case .readings:
            let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
            return window.start...window.plotEnd
        case .stress:
            return WatchStressChartGeometry.domain(endingAt: now, calendar: calendar)
        }
    }

    /// The slots that start inside the domain. The chart was read when the
    /// watch last computed, so as the entries slide its window on, the oldest
    /// slots leave on the left and the current one stays until it does.
    static func visibleBuckets(_ buckets: [WatchIntradayBucket], in domain: ClosedRange<Date>) -> [WatchIntradayBucket] {
        buckets.filter { $0.start >= domain.lowerBound && $0.start < domain.upperBound }
    }

    /// The Heart Rate, HRV or Blood Oxygen value range over the visible slots
    /// only, so a spike that has slid out of the window no longer flattens
    /// the rest: exactly their lowest to highest reading, so the chart spans
    /// the plot top to bottom. The pages pad theirs by 16% each way
    /// (`WatchIntradayChartGeometry.rangeDomain`), room this small plot can't
    /// spare; the plot's own inset keeps the marks on its edges whole. A
    /// window of one repeated value takes the pages' range, so its line sits
    /// mid plot, capped like the pages' at `ceiling` (Blood Oxygen's 100%),
    /// so a lone 100% reads no 101 or 102; the exact range never passes a
    /// reading, so it needs no cap.
    static func valueDomain(for buckets: [WatchIntradayBucket], in domain: ClosedRange<Date>, ceiling: Double? = nil) -> ClosedRange<Double> {
        let visible = visibleBuckets(buckets, in: domain)
        let values = visible.flatMap { [$0.minimum, $0.maximum] }.filter(\.isFinite)
        guard let lowest = values.min(), let highest = values.max(), lowest < highest else {
            return WatchIntradayChartGeometry.rangeDomain(for: visible, ceiling: ceiling)
        }
        return lowest...highest
    }

    /// Whether the window ending at `now` has anything to draw: a slot that
    /// starts in it, or a scored or activity window that overlaps it. Without
    /// one the caption takes the plot's place.
    static func hasPlot(_ content: Content, endingAt now: Date, calendar: Calendar = .current) -> Bool {
        let domain = domain(for: content, endingAt: now, calendar: calendar)
        switch content {
        case let .readings(buckets, _):
            return !visibleBuckets(buckets, in: domain).isEmpty
        case let .stress(timeline):
            guard let timeline else { return false }
            return !WatchStressChartGeometry.marks(in: timeline, domain: domain).isEmpty
        }
    }

    /// Whether the plot reserves the icon row: only Stress, and only while a
    /// sleep, nap or workout band overlaps the window, so the plot keeps its
    /// full height otherwise.
    static func hasIconRow(_ content: Content, domain: ClosedRange<Date>) -> Bool {
        guard case let .stress(timeline?) = content else { return false }
        return WatchStressChartGeometry.contextSpans(in: timeline, domain: domain)
            .contains { drawnContextKinds.contains($0.band.kind) }
    }

    /// About 55% of one slot's share of the plot, kept between 1.5 and 6
    /// points: the page's capsule (62%, 2 to 8 points), slimmed with the rest
    /// of the complication's marks.
    static func capsuleWidth(forPlotWidth width: CGFloat) -> CGFloat {
        min(max(width / slotCount * 0.55, 1.5), 6)
    }
}
