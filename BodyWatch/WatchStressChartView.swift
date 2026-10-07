//
//  WatchStressChartView.swift
//  BodyWatch
//
//  The "Last 12 hours" chart on the Stress detail page, drawn onto the page
//  below its value row. It shares the Heart Rate and HRV charts' header
//  style, half hour aligned window (`WatchIntradayWindow`, opened 12 hours
//  back instead of their 8) and even hour labels, and draws the iPhone
//  Day View's Stress plot (`BodyStressIntradayRenderPlot` in
//  Body/Views/Health/Charts/StressChart.swift, iOS only) in the same order:
//  sleep and workout shading with a symbol above each band, the dashed band
//  grid with no value labels, then per 15 minute window a faint column under
//  a capsule in the band color, or a gray floor stub for a window masked as
//  movement. An unscored window is a gap. Every constant comes from
//  `StressChartStyle` and `StressBand.rgbComponents`, so the two can't drift,
//  and the window, marks and shading spans from `WatchStressChartGeometry`,
//  which the Stress chart complication shares.
//  Display-only: no selection or scrubbing. Reads the snapshot's
//  `stressTimeline`, which the phone pushes or the watch recomputes.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchStressChartView: View {
    let timeline: WatchStressTimeline
    /// The window's end: the chart shows the `windowLength` before the
    /// current half hour slot, aligned like the Heart Rate and HRV charts.
    let now: Date
    /// Workout shading colors, the phone's custom colors included.
    let palette: BodyWorkoutColorPalette

    /// The row above the plot the band symbols sit in.
    private static let symbolRowHeight: CGFloat = 12
    private static let symbolSize: CGFloat = 11
    /// The row below the plot the hour labels sit in.
    private static let labelRowHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Last 12 hours")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Canvas { context, size in
                let domain = WatchStressChartGeometry.domain(endingAt: now)
                let plotRect = CGRect(
                    x: 0,
                    y: Self.symbolRowHeight,
                    width: size.width,
                    height: max(0, size.height - Self.symbolRowHeight - Self.labelRowHeight)
                )
                drawContextBands(WatchStressChartGeometry.contextSpans(in: timeline, domain: domain), in: plotRect, context: &context)
                drawGrid(in: plotRect, context: &context)
                drawMarks(WatchStressChartGeometry.marks(in: timeline, domain: domain), in: plotRect, context: &context)
                drawHourLabels(WatchStressChartGeometry.ticks(endingAt: now), domain: domain, in: plotRect, context: &context)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Last 12 hours"))
    }

    // MARK: - Drawing

    /// The phone's context bands: a translucent fill, a full color top stripe,
    /// and a bold symbol centered above the band, kept whole at the plot's
    /// edges (a band clipped at the window's start would otherwise draw half
    /// a symbol).
    private func drawContextBands(_ spans: [WatchStressChartGeometry.ContextSpan], in plotRect: CGRect, context: inout GraphicsContext) {
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
            let y = WatchStressChartGeometry.y(forScore: fraction * 100, in: plotRect)
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
    private func drawMarks(_ marks: [WatchStressChartGeometry.Mark], in plotRect: CGRect, context: inout GraphicsContext) {
        for mark in marks {
            let span = WatchStressChartGeometry.markSpan(
                xStart: mark.xStart,
                xEnd: mark.xEnd,
                in: plotRect,
                inset: CGFloat(StressChartStyle.markHorizontalInset),
                minimumWidth: CGFloat(StressChartStyle.markMinimumWidth)
            )
            switch mark.slot {
            case let .scored(score):
                let rgb = StressBand.band(for: score).rgbComponents
                let color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                let valueY = WatchStressChartGeometry.y(forScore: Double(score), in: plotRect)
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
                    x: plotRect.minX + plotRect.width * CGFloat(WatchIntradayChartGeometry.fraction(for: tick, in: domain)),
                    y: plotRect.maxY + Self.labelRowHeight / 2
                )
            )
        }
    }
}

extension WatchStressTimeline {
    /// A deterministic timeline ending at `now` for previews and the watch
    /// page screenshots: about 13 hours of windows from a quarter hour of local
    /// time, so the first hour falls before the chart's window. The night's
    /// second half under the sleep shading, a calm desk stretch, a stressor, 45
    /// minutes off the wrist, a run masked as movement under its workout
    /// shading, and the latest window cut at `now`.
    static func preview(now: Date = Date(), calendar: Calendar = .current) -> WatchStressTimeline {
        let earliest = now.addingTimeInterval(-13 * 60 * 60)
        let hourStart = calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest
        let quarters = (max(0, earliest.timeIntervalSince(hourStart)) / slotLength).rounded(.down)
        let start = hourStart.addingTimeInterval(quarters * slotLength)
        let slotCount = max(1, Int((now.timeIntervalSince(start) / slotLength).rounded(.up)))

        let a = activityMarker
        let pattern: [Int?] = [
            // Asleep: the night's second half.
            12, 10, 9, 8, 11, 9, 7, 10, 13, 11, 9, 8, 10, 12, 9, 11,
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
            WatchStressContextBand(kind: WatchStressContextBand.sleepKind, start: at(-12), end: at(24, minutes: -4)),
            WatchStressContextBand(
                kind: WatchStressContextBand.workoutKind,
                start: at(45, minutes: 2),
                end: at(49, minutes: -2),
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
            .frame(height: 130)
            .padding(.horizontal, 8)
    }
}
