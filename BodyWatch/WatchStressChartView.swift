//
//  WatchStressChartView.swift
//  BodyWatch
//
//  The "Last 8 hours" chart on the Stress detail page, drawn onto the page
//  below its value row. It shares the Heart Rate and HRV charts' header,
//  window (`WatchIntradayWindow`) and even hour labels, and draws the iPhone
//  Day View's Stress plot (`BodyStressIntradayRenderPlot` in
//  Body/Views/Health/Charts/StressChart.swift, iOS only) in the same order:
//  sleep and workout shading with a symbol above each band, the dashed band
//  grid with no value labels, then per 15 minute window a faint column under
//  a capsule in the band color, or a gray floor stub for a window masked as
//  movement. An unscored window is a gap. Every constant comes from
//  `StressChartStyle` and `StressBand.rgbComponents`, so the two can't drift.
//  Display-only: no selection or scrubbing. Reads the snapshot's
//  `stressTimeline`, which the phone pushes or the watch recomputes.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchStressChartView: View {
    let timeline: WatchStressTimeline
    /// The window's end: the chart shows the 8 hours before the current half
    /// hour slot, like the Heart Rate and HRV charts.
    let now: Date
    /// Workout shading colors, the phone's custom colors included.
    let palette: BodyWorkoutColorPalette

    /// The row above the plot the band symbols sit in.
    private static let symbolRowHeight: CGFloat = 12
    private static let symbolSize: CGFloat = 11
    /// The row below the plot the hour labels sit in.
    private static let labelRowHeight: CGFloat = 14

    /// One window drawn on the chart: its span as fractions of the domain,
    /// clamped to it, and what it shows (never `.none`, which is a gap).
    struct Mark: Equatable {
        let xStart: Double
        let xEnd: Double
        let slot: WatchStressTimeline.Slot
    }

    /// One shaded stretch clipped to the domain, as fractions of it.
    struct ContextSpan: Equatable {
        let xStart: Double
        let xEnd: Double
        let band: WatchStressContextBand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Last 8 hours")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Canvas { context, size in
                let domain = Self.domain(endingAt: now)
                let plotRect = CGRect(
                    x: 0,
                    y: Self.symbolRowHeight,
                    width: size.width,
                    height: max(0, size.height - Self.symbolRowHeight - Self.labelRowHeight)
                )
                drawContextBands(Self.contextSpans(in: timeline, domain: domain), in: plotRect, context: &context)
                drawGrid(in: plotRect, context: &context)
                drawMarks(Self.marks(in: timeline, domain: domain), in: plotRect, context: &context)
                drawHourLabels(Self.ticks(endingAt: now), domain: domain, in: plotRect, context: &context)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Last 8 hours"))
    }

    // MARK: - Drawing

    /// The phone's context bands: a translucent fill, a full color top stripe,
    /// and a bold symbol centered above the band, kept whole at the plot's
    /// edges (a band clipped at the window's start would otherwise draw half
    /// a symbol).
    private func drawContextBands(_ spans: [ContextSpan], in plotRect: CGRect, context: inout GraphicsContext) {
        let stripeHeight = max(
            CGFloat(StressChartStyle.topStripeMinimumHeight),
            plotRect.height * CGFloat(StressChartStyle.topStripeHeightRatio)
        )
        for span in spans {
            guard let style = style(for: span.band) else { continue }
            let leading = plotRect.minX + plotRect.width * CGFloat(span.xStart)
            let width = plotRect.width * CGFloat(span.xEnd - span.xStart)

            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: plotRect.height)),
                with: .color(style.color.opacity(style.fillOpacity))
            )
            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: stripeHeight)),
                with: .color(style.color)
            )

            let symbol = context.resolve(
                Text(Image(systemName: style.symbolName))
                    .font(.system(size: Self.symbolSize, weight: .bold))
                    .foregroundStyle(style.color)
            )
            let halfWidth = symbol.measure(in: plotRect.size).width / 2
            let center = leading + width / 2
            context.draw(
                symbol,
                at: CGPoint(
                    x: min(max(center, plotRect.minX + halfWidth), max(plotRect.minX + halfWidth, plotRect.maxX - halfWidth)),
                    y: plotRect.minY - Self.symbolRowHeight / 2
                )
            )
        }
    }

    /// The band's color, fill and symbol, or nil for a kind this build
    /// doesn't know (a newer phone could push one).
    private func style(for band: WatchStressContextBand) -> (color: Color, fillOpacity: Double, symbolName: String)? {
        let sleepColor = Color(
            red: StressChartStyle.sleepRGB.red,
            green: StressChartStyle.sleepRGB.green,
            blue: StressChartStyle.sleepRGB.blue
        )
        switch band.kind {
        case WatchStressContextBand.sleepKind:
            return (sleepColor, StressChartStyle.sleepFillOpacity, "bed.double.fill")
        case WatchStressContextBand.napKind:
            return (sleepColor, StressChartStyle.sleepFillOpacity, "moon.zzz.fill")
        case WatchStressContextBand.workoutKind:
            let type = band.workoutType.flatMap(BodyWorkoutType.init(rawValue:)) ?? .other
            return (palette.color(for: type), StressChartStyle.workoutFillOpacity, type.symbolName)
        default:
            return nil
        }
    }

    /// Dashed gridlines at the band quarters, with no value labels. The
    /// phone draws them in `Color.secondary`; on the watch's black that
    /// reads too dim, so white at the same opacity.
    private func drawGrid(in plotRect: CGRect, context: inout GraphicsContext) {
        var grid = Path()
        for fraction in StressChartStyle.gridFractions {
            let y = Self.y(forScore: fraction * 100, in: plotRect)
            grid.move(to: CGPoint(x: plotRect.minX, y: y))
            grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(
            grid,
            with: .color(Color.white.opacity(StressChartStyle.gridOpacity)),
            style: StrokeStyle(
                lineWidth: CGFloat(StressChartStyle.gridLineWidth),
                dash: StressChartStyle.gridDash.map { CGFloat($0) }
            )
        )
    }

    /// A scored window: a faint column from the score to the floor under a
    /// capsule centered on the score, both in the band color. An activity
    /// window: a gray stub on the floor.
    private func drawMarks(_ marks: [Mark], in plotRect: CGRect, context: inout GraphicsContext) {
        for mark in marks {
            let span = Self.markSpan(xStart: mark.xStart, xEnd: mark.xEnd, in: plotRect)
            switch mark.slot {
            case let .scored(score):
                let rgb = StressBand.band(for: score).rgbComponents
                let color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                let valueY = Self.y(forScore: Double(score), in: plotRect)
                context.fill(
                    Path(
                        roundedRect: CGRect(x: span.x, y: valueY, width: span.width, height: max(0, plotRect.maxY - valueY)),
                        cornerRadius: min(CGFloat(StressChartStyle.columnCornerRadius), span.width / 2)
                    ),
                    with: .color(color.opacity(StressChartStyle.columnOpacity))
                )
                let capsuleHeight = CGFloat(StressChartStyle.capsuleHeight)
                context.fill(
                    Path(
                        roundedRect: CGRect(x: span.x, y: valueY - capsuleHeight / 2, width: span.width, height: capsuleHeight),
                        cornerRadius: span.width / 2
                    ),
                    with: .color(color)
                )
            case .activity:
                let stubHeight = CGFloat(StressChartStyle.activityStubHeight)
                context.fill(
                    Path(
                        roundedRect: CGRect(x: span.x, y: plotRect.maxY - stubHeight, width: span.width, height: stubHeight),
                        cornerRadius: span.width / 2
                    ),
                    with: .color(Color.white.opacity(StressChartStyle.activityOpacity))
                )
            case .none:
                continue
            }
        }
    }

    /// The Heart Rate chart's hour labels, centered under their hour.
    private func drawHourLabels(_ ticks: [Date], domain: ClosedRange<Date>, in plotRect: CGRect, context: inout GraphicsContext) {
        for tick in ticks {
            context.draw(
                context.resolve(
                    Text(tick.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                ),
                at: CGPoint(
                    x: plotRect.minX + plotRect.width * CGFloat(Self.fraction(for: tick, in: domain)),
                    y: plotRect.maxY + Self.labelRowHeight / 2
                )
            )
        }
    }

    // MARK: - Geometry

    /// The x domain: the Heart Rate and HRV charts' window ending at `now`,
    /// from its oldest slot's start through the current slot's end.
    static func domain(endingAt now: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let window = WatchIntradayWindow.endingAt(now, calendar: calendar)
        return window.start...window.plotEnd
    }

    /// The Heart Rate and HRV charts' hour labels for the same window.
    static func ticks(endingAt now: Date, calendar: Calendar = .current) -> [Date] {
        WatchIntradayChartView.hourTicks(in: domain(endingAt: now, calendar: calendar), calendar: calendar)
    }

    /// Where `date` falls across the domain, clamped to 0...1.
    static func fraction(for date: Date, in domain: ClosedRange<Date>) -> Double {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(domain.lowerBound) / span))
    }

    /// The scored and activity windows that overlap the domain, oldest first,
    /// clipped to it. Unscored windows are gaps, so they never appear, and a
    /// window cut to nothing at the timeline's `end` is skipped.
    static func marks(in timeline: WatchStressTimeline, domain: ClosedRange<Date>) -> [Mark] {
        timeline.slots.indices.compactMap { index -> Mark? in
            let slot = timeline.slot(at: index)
            if case .none = slot { return nil }
            let interval = timeline.interval(at: index)
            guard interval.duration > 0,
                  interval.end > domain.lowerBound,
                  interval.start < domain.upperBound else { return nil }
            return Mark(
                xStart: fraction(for: interval.start, in: domain),
                xEnd: fraction(for: interval.end, in: domain),
                slot: slot
            )
        }
    }

    /// The context bands that overlap the domain, clipped to it.
    static func contextSpans(in timeline: WatchStressTimeline, domain: ClosedRange<Date>) -> [ContextSpan] {
        timeline.context.compactMap { band -> ContextSpan? in
            let xStart = fraction(for: band.start, in: domain)
            let xEnd = fraction(for: band.end, in: domain)
            guard xEnd > xStart else { return nil }
            return ContextSpan(xStart: xStart, xEnd: xEnd, band: band)
        }
    }

    /// Whether the window ending at `now` has anything to draw: the Stress
    /// page shows the chart, and scrolls, only then.
    static func hasVisibleMarks(_ timeline: WatchStressTimeline, endingAt now: Date, calendar: Calendar = .current) -> Bool {
        !marks(in: timeline, domain: domain(endingAt: now, calendar: calendar)).isEmpty
    }

    /// A score's height in the plot: 0 on the floor, 100 at the top, clamped.
    static func y(forScore score: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.maxY - plotRect.height * CGFloat(min(1, max(0, score / 100)))
    }

    /// A window's mark across the plot, inset on each side so neighbors don't
    /// touch, but never narrower than `StressChartStyle.markMinimumWidth`.
    static func markSpan(xStart: Double, xEnd: Double, in plotRect: CGRect) -> (x: CGFloat, width: CGFloat) {
        let inset = CGFloat(StressChartStyle.markHorizontalInset)
        let leading = plotRect.minX + plotRect.width * CGFloat(xStart) + inset
        let trailing = plotRect.minX + plotRect.width * CGFloat(xEnd) - inset
        return (leading, max(CGFloat(StressChartStyle.markMinimumWidth), trailing - leading))
    }
}

extension WatchStressTimeline {
    /// A deterministic timeline ending at `now` for previews and the watch
    /// page screenshots: about 9 hours of windows from a quarter hour of local
    /// time, so the first hour falls before the chart's window. The night's
    /// end under the sleep shading, a calm desk stretch, a stressor, 45
    /// minutes off the wrist, a run masked as movement under its workout
    /// shading, and the latest window cut at `now`.
    static func preview(now: Date = Date(), calendar: Calendar = .current) -> WatchStressTimeline {
        let earliest = now.addingTimeInterval(-9 * 60 * 60)
        let hourStart = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        let quarters = (max(0, earliest.timeIntervalSince(hourStart)) / slotLength).rounded(.down)
        let start = hourStart.addingTimeInterval(quarters * slotLength)
        let slotCount = max(1, Int((now.timeIntervalSince(start) / slotLength).rounded(.up)))

        let a = activityMarker
        let pattern: [Int?] = [
            // Asleep: the night's end.
            14, 11, 9, 12, 16, 13, 18, 21,
            // Awake, then the desk.
            nil, 33, 29, 36, 41, 38, 31, 44, 39,
            // A stressor.
            58, 71, 82, 66,
            // Settling down, then off the wrist.
            44, 38, nil, nil, nil,
            // Back at the desk.
            34, 29, 36,
            // A run, masked as movement.
            a, a, a, a,
            // Recovering, up to `now`.
            57, 46, 41, 37
        ]
        let slots = (0..<slotCount).map { pattern.indices.contains($0) ? pattern[$0] : 35 }

        func at(_ slot: Int, minutes: Double = 0) -> Date {
            start.addingTimeInterval(Double(slot) * slotLength + minutes * 60)
        }
        let context = [
            WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: at(-28), end: at(8, minutes: -4)),
            WatchStressContextBand(
                kind: WatchStressContextBand.workoutKind,
                start: at(29, minutes: 2),
                end: at(33, minutes: -2),
                workoutType: BodyWorkoutType.running.rawValue
            )
        ].filter { $0.start < now }

        return WatchStressTimeline(start: start, end: now, slots: slots, context: context, computedAt: now)
    }
}

#Preview {
    let now = Date()
    return ZStack {
        Color.black.ignoresSafeArea()
        WatchStressChartView(timeline: .preview(now: now), now: now, palette: .builtIn)
            .frame(height: 86)
            .padding(.horizontal, 8)
    }
}
