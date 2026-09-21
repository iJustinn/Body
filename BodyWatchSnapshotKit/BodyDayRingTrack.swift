import SwiftUI

/// Where the Day Ring's two bars sit. Both ride the Readiness Ring's own track layout,
/// so the arc, its pull stretch and its flatten into the pinned bar are the same motion.
enum BodyDayRingGeometry {
    private typealias Arc = BodyReadinessArcGeometry

    /// The dial and the activity bars share one bar, about 1.1 times the Readiness
    /// Ring's: the activities are laid over the dial they are timed against.
    static let outerBarWidth: CGFloat = Arc.arcBarWidth * 1.1
    static let innerBarWidth: CGFloat = outerBarWidth
    /// A span shorter than this along the ring draws as a bar this long instead: long
    /// enough that even the shortest activity holds its icon.
    static let minimumSegmentLength: CGFloat = outerBarWidth * 1.2
    /// Trimmed off each end where two spans touch, which leaves a hairline between them.
    static let adjacentInset: CGFloat = 0.75
    /// A bar carries its icon once it is this many bar widths long, the icon this share
    /// of the bar's width.
    static let iconMinimumLengthRatio: CGFloat = 1.1
    static let iconSizeRatio: CGFloat = 0.62
    /// How far the dial runs on past each midnight, as a share of the day, so the two
    /// midnight marks sit inside the bar rather than on its tips.
    static let dialOverrun: Double = 0.025
    /// Canvas room below the hero's height for that overrun and the bar's round tips,
    /// pulled open included; short of it the canvas cuts the ends off square.
    static let canvasOverhang: CGFloat = 96
    /// Canvas room past either side of the hero: midway through the flatten the ends
    /// swing out wider than the hero before they settle into the flat bar.
    static let canvasSideOverhang: CGFloat = 16

    /// The bottom of the flattened pair: the inner dial hangs below the track's
    /// centerline, so the pin holds the cards off this rather than off the Readiness
    /// Ring's single bar.
    static var flatBarBottom: CGFloat {
        let scale = Arc.flatBarWidth / Arc.arcBarWidth
        return Arc.flatY + (innerBarWidth / 2 - innerLaneOffset) * scale
    }

    /// Both ride the track's own centerline.
    static let outerLaneOffset: CGFloat = 0
    static let innerLaneOffset: CGFloat = 0
    /// An activity bar is this much thinner than the dial it lies on, as the Readiness
    /// Ring's pill is thinner than its band.
    static let segmentThicknessInset: CGFloat = 4
    /// How far the now line reaches past either edge of the bar.
    static let nowLineOverhang: CGFloat = 3
    static let nowLineWidth: CGFloat = 7

    /// The Readiness Ring's bubble: pulled, a bar draws out thinner, and squeezed on the
    /// rebound it presses fatter.
    static func barScale(stretch: CGFloat) -> CGFloat {
        stretch < 0 ? 1 - Arc.squeezeBarGrowth * stretch : 1 - Arc.stretchBarThinning * stretch
    }

    /// The other half of the bubble: longer when pulled, shorter when squeezed.
    static func lengthScale(stretch: CGFloat) -> Double {
        Double(stretch < 0 ? 1 + Arc.squeezeLengthShrink * stretch : 1 + Arc.stretchLengthGrowth * stretch)
    }

    static func clampedStretch(_ stretch: CGFloat) -> CGFloat {
        min(max(stretch, -Arc.maxSqueeze), Arc.maxPullStretch)
    }

    /// One state of the ring: the Readiness Ring's track for a scroll progress and pull
    /// stretch, with the day laid along its whole length.
    struct Track {
        let layout: BodyReadinessArcGeometry.Layout
        /// The share of the track at each end kept for the dial's run past midnight.
        /// Curved, the dial simply runs on past the track's ends; flat, the track already
        /// spans the hero's width, so the day moves in by the overrun instead and both
        /// midnight ticks stay inside the bar.
        var axisInset: Double = 0

        /// Where a day fraction sits along the track.
        func distance(fraction: Double) -> CGFloat {
            CGFloat(axisInset + fraction * (1 - 2 * axisInset)) * layout.trackLength
        }

        /// The day's own length along the track.
        var dayLength: CGFloat { CGFloat(1 - 2 * axisInset) * layout.trackLength }
        /// The bars and their lanes shrink with the track's own bar as it flattens.
        var scale: CGFloat { layout.barWidth / BodyReadinessArcGeometry.arcBarWidth }

        func point(fraction: Double, offset: CGFloat) -> CGPoint {
            // Not clamped: the dial runs a little past either midnight along the same bend.
            let distance = distance(fraction: fraction)
            let center = layout.point(atDistance: distance)
            let normal = layout.normal(atDistance: distance)
            return CGPoint(x: center.x + normal.dx * offset * scale, y: center.y + normal.dy * offset * scale)
        }

        /// A lane's centerline between two day fractions.
        func line(from start: Double, to end: Double, offset: CGFloat, samples: Int = 48) -> Path {
            var path = Path()
            path.addLines((0..<samples).map { step in
                point(fraction: start + (end - start) * Double(step) / Double(samples - 1), offset: offset)
            })
            return path
        }

        /// A mark across a lane, `reach` either side of its centerline.
        func mark(fraction: Double, offset: CGFloat, reach: CGFloat) -> Path {
            var path = Path()
            path.move(to: point(fraction: fraction, offset: offset - reach))
            path.addLine(to: point(fraction: fraction, offset: offset + reach))
            return path
        }

        /// An activity bar with rounded tips like the Readiness Ring's bands, but with
        /// the tips inside its true times rather than added past them as round caps,
        /// which at this bar width would put most of an hour on each end. Returned as a
        /// one outline, so the glass fill and its rim are painted once.
        func segmentPath(range: ClosedRange<Double>, stretch: CGFloat = 0, thicknessInset: CGFloat = 0, samples: Int = 32) -> Path {
            guard layout.trackLength > 0 else { return Path() }
            let bar = (BodyDayRingGeometry.outerBarWidth - thicknessInset) * scale * BodyDayRingGeometry.barScale(stretch: stretch)
            let middle = (range.lowerBound + range.upperBound) / 2
            let half = (range.upperBound - range.lowerBound) / 2 * BodyDayRingGeometry.lengthScale(stretch: stretch)
            let corner = min(bar / 2, CGFloat(half) * dayLength)
            let lane = BodyDayRingGeometry.outerLaneOffset * scale
            let startDistance = distance(fraction: middle - half) + corner
            let endDistance = distance(fraction: middle + half) - corner
            let flat = bar / 2 - corner
            var points: [CGPoint] = []

            func place(_ distance: CGFloat, along: CGFloat, out: CGFloat) -> CGPoint {
                let center = layout.point(atDistance: distance)
                let tangent = layout.tangent(atDistance: distance)
                let normal = layout.normal(atDistance: distance)
                return CGPoint(
                    x: center.x + tangent.dx * along + normal.dx * (lane + out),
                    y: center.y + tangent.dy * along + normal.dy * (lane + out)
                )
            }

            // A quarter turn of radius `corner`, in the track's own frame at `distance`.
            func turn(at distance: CGFloat, out: CGFloat, from startAngle: CGFloat) {
                for step in 0...8 {
                    let angle = startAngle - CGFloat(step) / 8 * .pi / 2
                    points.append(place(distance, along: cos(angle) * corner, out: out + sin(angle) * corner))
                }
            }

            func edge(out: CGFloat, reversed: Bool) {
                for step in 0..<samples {
                    let share = CGFloat(step) / CGFloat(samples - 1)
                    let distance = reversed
                        ? endDistance - share * (endDistance - startDistance)
                        : startDistance + share * (endDistance - startDistance)
                    points.append(place(distance, along: 0, out: out))
                }
            }

            // Outer edge, round the far tip, inner edge back, round the near tip. One
            // simple polygon, as the Readiness Ring's bands are, so translucent glass
            // never paints over itself.
            edge(out: bar / 2, reversed: false)
            turn(at: endDistance, out: flat, from: .pi / 2)
            turn(at: endDistance, out: -flat, from: 0)
            edge(out: -bar / 2, reversed: true)
            turn(at: startDistance, out: -flat, from: -.pi / 2)
            turn(at: startDistance, out: flat, from: .pi)

            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }
    }

    static func track(progress: Double = 0, width: CGFloat, stretch: CGFloat = 0, trailingStretch: CGFloat? = nil) -> Track {
        Track(
            layout: Arc.layout(progress: progress, width: width, stretch: stretch, trailingStretch: trailingStretch),
            axisInset: dialOverrun * min(max(progress, 0), 1)
        )
    }

    /// The day fractions a span is drawn between: its true extent, a hairline short of
    /// a touching neighbor, or the minimum glyph centered on it and kept on the dial.
    static func drawnRange(
        for span: DayRingTimeline.Span,
        previous: DayRingTimeline.Span?,
        next: DayRingTimeline.Span?,
        trackLength: CGFloat
    ) -> ClosedRange<Double> {
        guard trackLength > 0 else { return span.start...span.end }
        let inset = Double(adjacentInset / trackLength)
        let minimum = Double(minimumSegmentLength / trackLength)

        var start = span.start + (previous?.end == span.start ? inset : 0)
        var end = span.end - (next?.start == span.end ? inset : 0)
        if end - start < minimum {
            let center = (span.start + span.end) / 2
            let middle = min(max(center, minimum / 2), 1 - minimum / 2)
            // A glyph never grows past the halfway point to a neighbor, so two short
            // events close together stay two marks.
            start = max(middle - minimum / 2, previous.map { ($0.end + span.start) / 2 + inset / 2 } ?? 0)
            end = min(middle + minimum / 2, next.map { (span.end + $0.start) / 2 - inset / 2 } ?? 1)
        }
        return start...end
    }
}

extension DayRingTimeline.Span {
    /// Tells one activity bar from another across redraws, so a new one can fade in.
    var fadeID: String { "\(activity)|\(start)" }
}

extension DayRingDayPart {
    /// The page glow behind the Day Ring: sunrise gold, midday sky, late sun, night indigo.
    var glowColor: Color {
        switch self {
        case .morning:
            return Color(red: 1.00, green: 0.78, blue: 0.35)
        case .noon:
            return Color(red: 0.35, green: 0.75, blue: 1.00)
        case .afternoon:
            return Color(red: 1.00, green: 0.55, blue: 0.25)
        case .night:
            return Color(red: 0.40, green: 0.38, blue: 0.95)
        }
    }
}

/// The dial and the activity bars, drawn from an animatable stretch pair so the release
/// spring's bounce reaches the canvas.
struct BodyDayRingTrackView: View, Animatable {
    private typealias Geometry = BodyDayRingGeometry

    /// What one canvas draws: the dial with its ticks and now line, or one activity bar.
    enum Layer {
        case dial
        case span(Int)
        /// The now line, over the activity bars.
        case now
    }

    let layer: Layer
    let timeline: DayRingTimeline
    /// Where the now line is drawn. Animatable, so it glides to each new minute.
    var nowFraction: Double
    let progress: Double
    let width: CGFloat
    var stretch: CGFloat
    var trailingStretch: CGFloat
    let sleepColor: Color
    let workoutColor: (BodyWorkoutType) -> Color

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, Double> {
        get { AnimatablePair(AnimatablePair(stretch, trailingStretch), nowFraction) }
        set {
            stretch = newValue.first.first
            trailingStretch = newValue.first.second
            nowFraction = newValue.second
        }
    }

    var body: some View {
        Canvas { graphics, _ in
            var graphics = graphics
            graphics.translateBy(x: Geometry.canvasSideOverhang, y: 0)
            draw(in: &graphics)
        }
        // Room below the hero's own height for the dial's overrun past midnight.
        .frame(
            width: width + 2 * Geometry.canvasSideOverhang,
            height: BodyReadinessArcGeometry.heroHeight(width: width) + Geometry.canvasOverhang,
            alignment: .topLeading
        )
        .offset(x: -Geometry.canvasSideOverhang)
        // The overhang lies over the first card row; it must never take its taps.
        .allowsHitTesting(false)
    }

    /// The stretch at a point of the day: the middle leads and the ends trail.
    private func stretch(at fraction: Double) -> CGFloat {
        let fromMiddle = CGFloat(min(abs(fraction - 0.5) * 2, 1))
        return Geometry.clampedStretch(stretch + (trailingStretch - stretch) * fromMiddle)
    }

    private func draw(in graphics: inout GraphicsContext) {
        let track = Geometry.track(progress: progress, width: width, stretch: stretch, trailingStretch: trailingStretch)
        switch layer {
        case .dial:
            drawDial(on: track, in: &graphics)
        case .span(let index):
            drawSpan(at: index, on: track, in: &graphics)
        case .now:
            // Now is a line across the bar, thicker than any tick and a little taller than the bar.
            let bar = Geometry.innerBarWidth * Geometry.barScale(stretch: Geometry.clampedStretch(stretch))
            // A glass capsule like the bars it crosses: translucent fill, highlight, rim.
            let pointer = track.mark(fraction: nowFraction, offset: Geometry.innerLaneOffset, reach: bar / 2 + Geometry.nowLineOverhang)
                .strokedPath(StrokeStyle(lineWidth: Geometry.nowLineWidth, lineCap: .round))
            drawGlass(pointer, fill: Color.primary.opacity(0.45), rim: Color.primary.opacity(0.55), in: &graphics)
        }
    }

    private func drawDial(on track: Geometry.Track, in graphics: inout GraphicsContext) {
        // The dial is one bar, so it breathes with the middle's stretch.
        let dialBar = Geometry.innerBarWidth * track.scale * Geometry.barScale(stretch: Geometry.clampedStretch(stretch))
        let dialLane = Geometry.innerLaneOffset

        // The dial runs on a little past either midnight; that overrun and its round
        // caps are decoration, not part of the time axis.
        // In day fractions: curved it runs past the track's ends, flat it fills the ends the
        // day has moved in from, and between the two it does some of each.
        let overrun = Geometry.dialOverrun / (1 - 2 * track.axisInset)
        // One outline, like the activity bars, so the rim never traces a stroke's facets.
        let dial = track.segmentPath(range: -overrun...(1 + overrun), stretch: Geometry.clampedStretch(stretch), samples: 96)
        drawGlass(dial, fill: Color.primary.opacity(0.10), in: &graphics)

        // The next midnight closes the dial with the same mark the first one opens it with.
        let ticks = timeline.hourTicks + [DayRingTimeline.HourTick(hour: 0, fraction: 1)]
        for tick in ticks where tick.hour % 3 == 0 {
            let isMajor = tick.hour % 6 == 0
            // Every tick is centered across the bar, the key hours the longer ones.
            let reach = dialBar / track.scale * (isMajor ? 0.3 : 0.18)
            graphics.stroke(
                track.mark(fraction: tick.fraction, offset: dialLane, reach: reach),
                with: .color(Color.primary.opacity(isMajor ? 0.7 : 0.4)),
                style: StrokeStyle(lineWidth: isMajor ? 2 : 1.5, lineCap: .round)
            )
        }
    }

    private func drawSpan(at index: Int, on track: Geometry.Track, in graphics: inout GraphicsContext) {
        guard timeline.spans.indices.contains(index) else { return }
        let span = timeline.spans[index]
        do {
            let range = Geometry.drawnRange(
                for: span,
                previous: index > 0 ? timeline.spans[index - 1] : nil,
                next: index + 1 < timeline.spans.count ? timeline.spans[index + 1] : nil,
                trackLength: track.dayLength
            )
            let segment = track.segmentPath(
                range: range,
                stretch: stretch(at: (range.lowerBound + range.upperBound) / 2),
                thicknessInset: Geometry.segmentThicknessInset
            )
            drawGlass(segment, fill: color(for: span.activity).opacity(0.34), in: &graphics)

            // Names the bar with its icon wherever the bar is long enough to hold one.
            let bar = Geometry.outerBarWidth * track.scale
            let length = CGFloat(range.upperBound - range.lowerBound) * track.dayLength
            if length >= bar * Geometry.iconMinimumLengthRatio {
                var icon = graphics.resolve(
                    Image(systemName: symbolName(for: span.activity))
                        .symbolRenderingMode(.monochrome)
                )
                // White on every bar; the bar's tint already names the activity's color.
                icon.shading = .color(.white)
                let side = bar * Geometry.iconSizeRatio
                let middleFraction = (range.lowerBound + range.upperBound) / 2
                let middle = track.point(fraction: middleFraction, offset: Geometry.outerLaneOffset)
                let tangent = track.layout.tangent(atDistance: track.distance(fraction: middleFraction))
                let size = icon.size
                let fit = side / max(size.width, size.height, 1)
                // Stands on the ring, its top pointing outward, rather than straight up
                // the page; flattened, that is upright again.
                var turned = graphics
                turned.translateBy(x: middle.x, y: middle.y)
                turned.rotate(by: .radians(Double(atan2(tangent.dy, tangent.dx))))
                turned.draw(icon, in: CGRect(
                    x: -size.width * fit / 2,
                    y: -size.height * fit / 2,
                    width: size.width * fit,
                    height: size.height * fit
                ))
            }
        }
    }

    /// The Readiness Ring's band look: a translucent fill, a soft top highlight that
    /// fades as the ring flattens over the cards, and a one point rim.
    private func drawGlass(_ shape: Path, fill: Color, rim: Color = Color.primary.opacity(0.15), in graphics: inout GraphicsContext) {
        graphics.fill(shape, with: .color(fill))
        let bounds = shape.boundingRect
        var highlight = graphics
        highlight.clip(to: shape)
        highlight.fill(
            Path(bounds),
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.18 * (1 - progress)), .clear]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            )
        )
        graphics.stroke(shape, with: .color(rim), lineWidth: 1)
    }

    private func symbolName(for activity: DayRingTimeline.Activity) -> String {
        switch activity {
        case .sleep:
            return "bed.double.fill"
        case .workout(let type):
            return type.symbolName
        }
    }


    private func color(for activity: DayRingTimeline.Activity) -> Color {
        switch activity {
        case .sleep:
            return sleepColor
        case .workout(let type):
            return workoutColor(type)
        }
    }
}
