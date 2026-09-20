import SwiftUI

/// Where the Day Ring's two bars sit. Both ride the Readiness Ring's own track layout,
/// so the arc, its pull stretch and its flatten into the pinned bar are the same motion.
enum BodyDayRingGeometry {
    private typealias Arc = BodyReadinessArcGeometry

    /// The activity bar is the thick one and the dial the thin one; together with the
    /// gap they are about 1.5 times the Readiness Ring's bar.
    static let outerBarWidth: CGFloat = Arc.arcBarWidth * 0.9
    static let innerBarWidth: CGFloat = Arc.arcBarWidth * 0.5
    static let barGap: CGFloat = 3
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
    static let canvasOverhang: CGFloat = 24

    /// The bottom of the flattened pair: the inner dial hangs below the track's
    /// centerline, so the pin holds the cards off this rather than off the Readiness
    /// Ring's single bar.
    static var flatBarBottom: CGFloat {
        let scale = Arc.flatBarWidth / Arc.arcBarWidth
        return Arc.flatY + (innerBarWidth / 2 - innerLaneOffset) * scale
    }

    /// The outer bar's center, out from the track's centerline: its outer edge lands on
    /// the Readiness Ring's outer edge, so the hero keeps that footprint.
    static let outerLaneOffset: CGFloat = Arc.arcBarWidth / 2 - outerBarWidth / 2
    static let innerLaneOffset: CGFloat = outerLaneOffset - outerBarWidth / 2 - barGap - innerBarWidth / 2

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
        /// The bars and their lanes shrink with the track's own bar as it flattens.
        var scale: CGFloat { layout.barWidth / BodyReadinessArcGeometry.arcBarWidth }

        func point(fraction: Double, offset: CGFloat) -> CGPoint {
            // Not clamped: the dial runs a little past either midnight along the same bend.
            let distance = CGFloat(fraction) * layout.trackLength
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
        func segmentPath(range: ClosedRange<Double>, stretch: CGFloat = 0, samples: Int = 32) -> Path {
            guard layout.trackLength > 0 else { return Path() }
            let bar = BodyDayRingGeometry.outerBarWidth * scale * BodyDayRingGeometry.barScale(stretch: stretch)
            let middle = (range.lowerBound + range.upperBound) / 2
            let half = (range.upperBound - range.lowerBound) / 2 * BodyDayRingGeometry.lengthScale(stretch: stretch)
            let corner = min(bar / 2, CGFloat(half) * layout.trackLength)
            let lane = BodyDayRingGeometry.outerLaneOffset * scale
            let startDistance = CGFloat(middle - half) * layout.trackLength + corner
            let endDistance = CGFloat(middle + half) * layout.trackLength - corner
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
        Track(layout: Arc.layout(progress: progress, width: width, stretch: stretch, trailingStretch: trailingStretch))
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

/// The Day Ring star hero: an inner 24 hour dial with hour ticks and a thick line at now, an
/// outer bar that only draws the day's sleep and workouts, and the share of the day
/// that has passed in the middle.
struct BodyDayRingHero: View {
    private typealias Geometry = BodyDayRingGeometry

    let sleepSegments: [SleepStageSegment]
    /// Any superset of the day's workouts; the timeline keeps the ones that overlap it.
    let workouts: [WorkoutSummary]
    let width: CGFloat
    /// Whether the caption shows under the number (Settings > Home Hero > Day Caption).
    var showsCaption = true
    var mainSleepInterval: DateInterval?
    /// Warning signs mirrored from the Home cards, drawn under the number as on the
    /// Readiness Ring. Drawing only: the host overlays the tap targets.
    var warningBadges: [BodyReadinessHeroWarningBadge] = []
    /// 0 = the full ring with the number, 1 = the flat bar pinned under the status bar,
    /// the Readiness Ring's scroll morph.
    var progress: Double = 0
    /// Points the page has been pulled down past rest. As on the Readiness Ring, the hero
    /// holds its place on screen while the ring is dragged open, then bounces home.
    var pull: CGFloat = 0
    /// Previews and render tests only: freezes the clock.
    var previewDate: Date?

    @Environment(\.workoutColorPalette) private var workoutColorPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The Readiness Ring's stretch pair: `stretch` follows the pull and springs back on
    /// release, `trailingStretch` lags it at the ring's ends so the bounce ripples outward.
    @State private var stretch: CGFloat = 0
    @State private var trailingStretch: CGFloat = 0
    @State private var isStretchReleasing = false
    /// Off until the hero is on screen, so the now line sweeps in from midnight and the
    /// number counts up from zero, as the Readiness Ring's pill and score do.
    @State private var hasAppeared = false

    var body: some View {
        // One clock for the whole hero: the day, ticks, spans, marker, number and the
        // spoken summary all come from the same `now`, so they roll over together.
        TimelineView(.everyMinute) { context in
            let timeline = DayRingTimeline.make(
                now: previewDate ?? context.date,
                calendar: .bodyGregorian,
                sleepSegments: sleepSegments,
                mainSleepInterval: mainSleepInterval,
                workouts: workouts
            )
            // A frozen preview has no appearance to wait for.
            let isSettled = hasAppeared || reduceMotion || previewDate != nil
            let nowFraction = isSettled ? timeline.nowFraction : 0
            let percent = isSettled ? timeline.percentPassed : 0
            ZStack(alignment: .topLeading) {
                trackView(.dial, timeline: timeline, nowFraction: nowFraction)
                    // Each minute's step, and the sweep in, glide rather than jump.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: nowFraction)

                // Every activity bar is its own layer, so one that arrives fades in
                // instead of popping onto the ring.
                let spans = isSettled ? Array(timeline.spans.enumerated()) : []
                ZStack(alignment: .topLeading) {
                    ForEach(spans, id: \.element.fadeID) { index, _ in
                        trackView(.span(index), timeline: timeline, nowFraction: nowFraction)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: spans.map(\.element.fadeID))

                let textOpacity = BodyReadinessArcGeometry.textOpacity(progress: min(max(progress, 0), 1), width: width)
                ZStack(alignment: .topLeading) {
                    centerText(percent: percent)
                }
                .frame(width: width, height: BodyReadinessArcGeometry.heroHeight(width: width), alignment: .topLeading)
                .opacity(textOpacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: textBlockLayout)

                BodyHeroWarningBadgeRow(badges: warningBadges, opacity: textOpacity)
                    .position(x: width / 2, y: BodyReadinessArcGeometry.badgeRowCenterY(width: width))
            }
            .offset(y: -pull)
            .frame(width: width, height: BodyReadinessArcGeometry.heroHeight(width: width), alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(timeline))
        }
        .onAppear {
            hasAppeared = true
        }
        .onChange(of: pull) { oldPull, newPull in
            followPull(from: oldPull, to: newPull)
        }
    }

    private func trackView(_ layer: BodyDayRingTrackView.Layer, timeline: DayRingTimeline, nowFraction: Double) -> some View {
        BodyDayRingTrackView(
            layer: layer,
            timeline: timeline,
            nowFraction: nowFraction,
            progress: min(max(progress, 0), 1),
            width: width,
            stretch: stretch,
            trailingStretch: trailingStretch,
            sleepColor: BodyHomeCardKind.sleep.tintColor,
            workoutColor: { workoutColorPalette.color(for: $0) }
        )
    }

    /// The Readiness Ring's `followPull`: the ring follows the finger while the pull
    /// grows, and the first frame it shrinks a bouncy spring carries it home on its own.
    /// Reduce Motion leaves the ring unstretched.
    private func followPull(from oldPull: CGFloat, to newPull: CGFloat) {
        guard !reduceMotion else { return }
        if newPull > oldPull {
            isStretchReleasing = false
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                stretch = BodyReadinessArcGeometry.pullStretch(pull: newPull)
                trailingStretch = stretch
            }
        } else if !isStretchReleasing {
            isStretchReleasing = true
            let spring = Animation.interpolatingSpring(mass: 1, stiffness: 220, damping: 7)
            withAnimation(spring) {
                stretch = 0
            }
            withAnimation(spring.delay(BodyReadinessArcGeometry.rippleDelay)) {
                trailingStretch = 0
            }
        }
        if newPull <= 0 {
            isStretchReleasing = false
        }
    }

    // MARK: - Center text (the Readiness Ring's score block and its rules)

    private static let captionHeight: CGFloat = 18
    private static let captionGap: CGFloat = 4
    /// How far the number and caption drop while no warning badge is showing, so the
    /// block doesn't float over an empty badge row: 40% of a badge's height.
    private static let noBadgeDrop: CGFloat = BodyReadinessArcGeometry.badgeRowHeight * 0.4

    /// What the block's position depends on. A change glides it to its new place.
    private struct TextBlockLayout: Equatable {
        let showsCaption: Bool
        let hasBadges: Bool
    }

    private var textBlockLayout: TextBlockLayout {
        // Badges only move the block while the caption shows.
        TextBlockLayout(showsCaption: showsCaption, hasBadges: showsCaption && !warningBadges.isEmpty)
    }

    /// Without the caption the number keeps its centered place whether or not badges
    /// show; only the number and caption block lifts for the caption and drops without
    /// badges, exactly as the Readiness Ring's score and level do.
    private var numberCenterY: CGFloat {
        let centered = BodyReadinessArcGeometry.numberCenterY(width: width)
        guard showsCaption else { return centered }
        return centered - Self.captionHeight - Self.captionGap + (warningBadges.isEmpty ? Self.noBadgeDrop : 0)
    }

    @ViewBuilder
    private func centerText(percent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(percent)")
                .font(.system(size: 66, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(percent)))
                .lineLimit(1)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: percent)

            Text("%")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .opacity(0.9)
        }
        .fixedSize()
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .position(x: width / 2 + 6, y: numberCenterY)

        if showsCaption {
            Text("Today passed")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
                .position(
                    x: width / 2,
                    y: numberCenterY + BodyReadinessArcGeometry.numberHalfHeight + Self.captionGap + Self.captionHeight / 2
                )
                .transition(.opacity)
        }
    }

    private func accessibilityLabel(_ timeline: DayRingTimeline) -> String {
        let sleepText = BodyValueFormat.durationText(for: timeline.sleepDuration)
        return String(
            localized: "Day Ring, \(timeline.percentPassed) percent of the day passed, \(sleepText) asleep, \(timeline.workoutCount) workouts"
        )
    }
}

/// The dial and the activity bars, drawn from an animatable stretch pair so the release
/// spring's bounce reaches the canvas.
private struct BodyDayRingTrackView: View, Animatable {
    private typealias Geometry = BodyDayRingGeometry

    /// What one canvas draws: the dial with its ticks and now line, or one activity bar.
    enum Layer {
        case dial
        case span(Int)
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
            draw(in: &graphics)
        }
        // Room below the hero's own height for the dial's overrun past midnight.
        .frame(width: width, height: BodyReadinessArcGeometry.heroHeight(width: width) + Geometry.canvasOverhang, alignment: .topLeading)
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
        }
    }

    private func drawDial(on track: Geometry.Track, in graphics: inout GraphicsContext) {
        // The dial is one bar, so it breathes with the middle's stretch.
        let dialBar = Geometry.innerBarWidth * track.scale * Geometry.barScale(stretch: Geometry.clampedStretch(stretch))
        let dialLane = Geometry.innerLaneOffset

        // The dial runs on a little past either midnight; that overrun and its round
        // caps are decoration, not part of the time axis.
        // Flat, the track already spans the hero's width, so the overrun folds away with
        // the morph instead of running off the hero's ends.
        let overrun = Geometry.dialOverrun * (1 - progress)
        let dial = track.line(from: -overrun, to: 1 + overrun, offset: dialLane)
            .strokedPath(StrokeStyle(lineWidth: dialBar, lineCap: .round, lineJoin: .round))
        drawGlass(dial, fill: Color.primary.opacity(0.10), in: &graphics)

        // The next midnight closes the dial with the same mark the first one opens it with.
        let ticks = timeline.hourTicks + [DayRingTimeline.HourTick(hour: 0, fraction: 1)]
        for tick in ticks where tick.hour % 3 == 0 {
            let isMajor = tick.hour % 6 == 0
            graphics.stroke(
                track.mark(fraction: tick.fraction, offset: dialLane, reach: dialBar / track.scale * (isMajor ? 0.32 : 0.18)),
                with: .color(Color.primary.opacity(isMajor ? 0.7 : 0.4)),
                style: StrokeStyle(lineWidth: isMajor ? 2 : 1.5, lineCap: .round)
            )
        }

        // Now is a line across the dial, thicker than any tick and the full bar tall.
        graphics.stroke(
            track.mark(fraction: nowFraction, offset: dialLane, reach: dialBar / track.scale / 2),
            with: .color(.primary),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
    }

    private func drawSpan(at index: Int, on track: Geometry.Track, in graphics: inout GraphicsContext) {
        guard timeline.spans.indices.contains(index) else { return }
        let span = timeline.spans[index]
        do {
            let range = Geometry.drawnRange(
                for: span,
                previous: index > 0 ? timeline.spans[index - 1] : nil,
                next: index + 1 < timeline.spans.count ? timeline.spans[index + 1] : nil,
                trackLength: track.layout.trackLength
            )
            let segment = track.segmentPath(range: range, stretch: stretch(at: (range.lowerBound + range.upperBound) / 2))
            drawGlass(segment, fill: color(for: span.activity).opacity(0.34), in: &graphics)

            // Names the bar with its icon wherever the bar is long enough to hold one.
            let bar = Geometry.outerBarWidth * track.scale
            let length = CGFloat(range.upperBound - range.lowerBound) * track.layout.trackLength
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
                let tangent = track.layout.tangent(atDistance: CGFloat(middleFraction) * track.layout.trackLength)
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
    private func drawGlass(_ shape: Path, fill: Color, in graphics: inout GraphicsContext) {
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
        graphics.stroke(shape, with: .color(Color.primary.opacity(0.15)), lineWidth: 1)
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
