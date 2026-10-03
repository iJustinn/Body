//
//  WatchRecentHoursChartView.swift
//  BodyWatchShared
//
//  The intraday chart complications' drawing (accessoryRectangular): the
//  Stress page's "Last 12 hours" chart or the Heart Rate and HRV pages' "Last
//  8 hours" chart, compacted under one header line with the metric's name on
//  the left and its latest reading on the right. The window, hour labels,
//  line breaks, value range, marks and shading spans come from the geometry
//  the pages draw with (`WatchIntradayChartGeometry`,
//  `WatchStressChartGeometry`), so a complication never charts differently
//  from the page it opens; the colors and opacities are the pages' own, the
//  sizes cut down for a plot about half as tall. Only the data marks take
//  a tinted face's accent (`widgetAccentable`), so the ranges, shading and
//  grid behind them stay in the default group. When nothing falls inside the
//  window, a caption takes the plot's place. Every string arrives localized
//  from the widget, so this file holds no localizable literal, and no
//  `containerBackground` here; the widget adds its own.
//
//  Watch-only: not compiled into the iOS `Body` target. It lives here rather
//  than in the widget extension so `BodyWatchTests` can test and render it.
//

import SwiftUI
import WidgetKit

struct WatchRecentHoursChartView: View {
    /// What the plot draws.
    enum Content {
        /// Heart Rate or HRV: each 30 minute slot's range under a line through
        /// the slot averages, in the metric's tint.
        case readings([WatchIntradayBucket], tint: Color)
        /// Stress: the 15 minute windows over their sleep and workout shading,
        /// or nil when the snapshot carries no timeline.
        case stress(WatchStressTimeline?)
    }

    /// The metric's name, on the header's left.
    let title: String
    /// The latest reading, on the header's right ("--" without one).
    let reading: String
    let content: Content
    /// The window's end: the plot shows the chart's window ending in the
    /// current local half hour slot, aligned like the pages' charts.
    let now: Date
    /// The caption in the plot's place when nothing falls inside the window.
    let emptyText: String
    var calendar: Calendar = .current

    // MARK: - Layout

    private static let textFont = Font.system(size: 11, weight: .semibold, design: .rounded)
    /// The least space between the name and the reading on the header line.
    private static let headerGap: CGFloat = 6
    /// The row under the plot the hour labels sit in.
    private static let labelRowHeight: CGFloat = 10
    private static let labelFont = Font.system(size: 9, weight: .medium, design: .rounded)

    // MARK: - Readings: `WatchIntradayChartView`'s range style, slimmed

    /// Slots across the plot: the window plus the current slot.
    private static let slotCount = WatchIntradayWindow.length / WatchIntradayWindow.slotLength + 1
    private static let rangeColor = Color.white.opacity(0.28)
    private static let lineWidth: CGFloat = 1.5
    /// Solid rather than the page's ringed dots: on a tinted face every
    /// opaque fill renders as solid accent, so a ring around a black center
    /// would merge into one dot there anyway.
    private static let pointDiameter: CGFloat = 3
    private static let latestPointDiameter: CGFloat = 5

    // MARK: - Stress: `StressChartStyle`'s colors and opacities, sizes halved

    private static let sleepFillOpacity = 0.14
    /// White, not the workout's own color: the widget extension has no
    /// workout palette, and the plot has no room for the page's symbols.
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

    var body: some View {
        let domain = Self.domain(for: content, endingAt: now, calendar: calendar)
        VStack(alignment: .leading, spacing: 2) {
            header
            if Self.hasPlot(content, endingAt: now, calendar: calendar) {
                plot(domain: domain)
                    .frame(maxHeight: .infinity)
                hourLabels(domain: domain)
                    .frame(height: Self.labelRowHeight)
            } else {
                Text(emptyText)
                    .font(Self.textFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The name and the reading on one line, pushed apart; a translation too
    /// long for that stacks them instead, so neither is cut.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title)
                    .fixedSize()
                Spacer(minLength: Self.headerGap)
                Text(reading)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                Text(reading)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .font(Self.textFont)
        .foregroundStyle(.primary)
        .textCase(.uppercase)
    }

    /// The context behind (ranges, shading, grid, columns) and the data marks
    /// in front, on separate canvases so only the marks take the accent.
    private func plot(domain: ClosedRange<Date>) -> some View {
        ZStack {
            Canvas { context, size in
                switch content {
                case let .readings(buckets, _):
                    drawRanges(
                        Self.visibleBuckets(buckets, in: domain),
                        values: Self.valueDomain(for: buckets, in: domain),
                        domain: domain,
                        in: Self.plotRect(in: size, inset: Self.latestPointDiameter / 2),
                        context: &context
                    )
                case let .stress(timeline):
                    guard let timeline else { return }
                    drawStressContext(
                        timeline,
                        domain: domain,
                        in: Self.plotRect(in: size, inset: Self.capsuleHeight / 2),
                        context: &context
                    )
                }
            }
            Canvas { context, size in
                switch content {
                case let .readings(buckets, tint):
                    drawReadings(
                        Self.visibleBuckets(buckets, in: domain),
                        tint: tint,
                        values: Self.valueDomain(for: buckets, in: domain),
                        domain: domain,
                        in: Self.plotRect(in: size, inset: Self.latestPointDiameter / 2),
                        context: &context
                    )
                case let .stress(timeline):
                    guard let timeline else { return }
                    drawStressMarks(
                        WatchStressChartGeometry.marks(in: timeline, domain: domain),
                        in: Self.plotRect(in: size, inset: Self.capsuleHeight / 2),
                        context: &context
                    )
                }
            }
            .widgetAccentable()
        }
    }

    /// The pages' even local hours, centered under their hour. In the
    /// calendar's time zone, so a label always names the hour its tick was
    /// placed on. Hidden from VoiceOver, which reads the header.
    private func hourLabels(domain: ClosedRange<Date>) -> some View {
        let ticks = WatchIntradayChartGeometry.hourTicks(in: domain, calendar: calendar)
        let format = Date.FormatStyle(timeZone: calendar.timeZone).hour(.twoDigits(amPM: .omitted))
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.self) { tick in
                    Text(tick.formatted(format))
                        .font(Self.labelFont)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(
                            x: proxy.size.width * CGFloat(WatchIntradayChartGeometry.fraction(for: tick, in: domain)),
                            y: proxy.size.height / 2
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Drawing: readings

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
    /// workout shading with a stripe along its top, the dashed band grid, and
    /// per window a faint column from the score to the floor in the band
    /// color, or the floor stub of a window masked as movement.
    private func drawStressContext(_ timeline: WatchStressTimeline, domain: ClosedRange<Date>, in plotRect: CGRect, context: inout GraphicsContext) {
        for span in WatchStressChartGeometry.contextSpans(in: timeline, domain: domain) {
            guard let shading = Self.shading(for: span.band) else { continue }
            let leading = plotRect.minX + plotRect.width * CGFloat(span.xStart)
            let width = plotRect.width * CGFloat(span.xEnd - span.xStart)
            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: plotRect.height)),
                with: .color(shading.fill)
            )
            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: Self.stripeHeight)),
                with: .color(shading.stripe)
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

    /// A context band's fill and top stripe, or nil for a kind this build
    /// doesn't know (a newer phone could push one). Sleep and naps in the
    /// Sleep blue the page shades them with (`StressChartStyle.sleepRGB`), a
    /// full color stripe like the page's. Workouts in white, their stripe as
    /// bright as the activity stubs under them, since a full white stripe
    /// would outshine every mark.
    private static func shading(for band: WatchStressContextBand) -> (fill: Color, stripe: Color)? {
        switch band.kind {
        case WatchStressContextBand.sleepKind, WatchStressContextBand.napKind:
            let sleep = Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.sleep))
            return (sleep.opacity(sleepFillOpacity), sleep)
        case WatchStressContextBand.workoutKind:
            return (Color.white.opacity(workoutFillOpacity), Color.white.opacity(activityOpacity))
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

    /// The plot inside a canvas, inset top and bottom by half its largest
    /// mark (the latest reading's dot, a Stress capsule), so a mark at either
    /// end of the range is drawn whole.
    private static func plotRect(in size: CGSize, inset: CGFloat) -> CGRect {
        CGRect(x: 0, y: inset, width: size.width, height: max(0, size.height - 2 * inset))
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

    /// The Heart Rate and HRV value range (`WatchIntradayChartGeometry.rangeDomain`)
    /// over the visible slots only, so a spike that has slid out of the
    /// window no longer flattens the rest.
    static func valueDomain(for buckets: [WatchIntradayBucket], in domain: ClosedRange<Date>) -> ClosedRange<Double> {
        WatchIntradayChartGeometry.rangeDomain(for: visibleBuckets(buckets, in: domain))
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

    /// About 55% of one slot's share of the plot, kept between 1.5 and 6
    /// points: the page's capsule (62%, 2 to 8 points), slimmed with the rest
    /// of the complication's marks.
    static func capsuleWidth(forPlotWidth width: CGFloat) -> CGFloat {
        min(max(width / slotCount * 0.55, 1.5), 6)
    }
}
