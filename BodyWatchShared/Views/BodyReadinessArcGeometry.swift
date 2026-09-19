//
//  BodyReadinessArcGeometry.swift
//  BodyWatchShared
//
//  Shared by the iOS `Body` target, the `BodyWatch` target, and the watch widget
//  extension: the watch home screen (`WatchReadinessHeroView`) and the Readiness
//  complication (`ReadinessComplicationView`) draw the same readiness hero from
//  this geometry, so they stay identical by construction. SwiftUI only: the
//  extension does not compile BodyMetricsKit, so `segmentOrder` (which names
//  `ReadinessStatus`) lives in `BodyWatchSnapshotKit/BodyReadinessArcGeometry+Status.swift`.
//  `heroWidth(pageWidth:)` is iOS-only and lives in `BodyReadinessStarHero.swift`.
//

import SwiftUI

/// Geometry for the Home readiness hero: five band segments that sit on an arc over the
/// score and flatten into a row pinned at the top as the page scrolls.
///
/// Only the two endpoint states are authored. `arcLayout` is the resting hero (a 200
/// degree sweep centered on the top of the circle) and `flatLayout` is the pinned row, and
/// both are built by the same allocator so a band owns the same share of the track in
/// either state. Everything between them is one family of layouts that unbends the arc
/// into the line: same allocator, same order, with the sweep angle closing toward zero. A
/// naive point-wise lerp between the two endpoint shapes was the first cut, but the arc's
/// end gaps point almost straight up while the flat gaps point sideways, so the lerp swings
/// adjacent bar ends through each other and the gaps collapse to a couple of points around
/// half-scroll. Unbending keeps every gap tangent to the track, so the separation the
/// design asks for holds at every frame instead of only at the ends.
///
/// Gaps reserve `barWidth + visualGap + morphMargin` of centerline. The bar width is in
/// there because the round caps push `barWidth / 2` past each endpoint, so only the rest is
/// visible space; the morph margin is the slack that covers the chord shortening and the
/// re-allocation that happen while the track is bending.
///
/// Band lengths follow each band's share of the 0...100 score range, except that a band
/// never draws shorter than `minimumSegmentLength`: at these track lengths the raw share of
/// the prime band (6 points of score) would be a dot smaller than the bar is wide. The
/// minimum is applied iteratively so the bands that stay above it keep their proportions to
/// each other.
enum BodyReadinessArcGeometry {
    /// Where the top of the arc's centerline sits, under the page's own top padding.
    /// The ring's size follows the width it is given, so everything else in the hero
    /// hangs off this inset and the radius rather than off fixed y values: on a wide
    /// phone the ring is wider *and* taller, and on a narrow one it shrinks without
    /// leaving a band of empty page above or below it.
    static let arcTopInset: CGFloat = 24
    /// The widest ring the hero draws. It bites on the largest iPhones, holding the arc
    /// a little short of the page width there, and keeps an iPad's much wider content
    /// column from handing the hero a ring the rest of the page can't live with.
    static let maxArcRadius: CGFloat = 162
    static let arcBarWidth: CGFloat = 28
    static let flatBarWidth: CGFloat = 18
    static let flatY: CGFloat = 26
    /// The pill's full length along the track. It is nearly as thick as the bar, so it is
    /// allowed to run into the bar's round caps by `dotDistance`'s inset rule.
    static let dotLength: CGFloat = 30
    static let visualGap: CGFloat = 6
    static let morphMargin: CGFloat = 4
    /// Scroll points (past the hero's resting position) that take the hero from the arc
    /// to the flat row. Sized so the summary card, 14 pt under the hero's frame, arrives
    /// the same 14 pt beneath the flat bar (whose bottom edge is at `flatY + flatBarWidth / 2`)
    /// as the cards keep between each other, at the moment the hero is released to scroll
    /// away with it.
    static func morphDistance(width: CGFloat) -> CGFloat {
        heroHeight(width: width) + 14 - (flatY + flatBarWidth / 2 + 14)
    }
    /// Scroll points until the big score number is fully faded.
    static let numberFadeDistance: CGFloat = 60
    static let textVisibleThreshold: Double = 0.1
    /// The score sits just above the circle's center line, inside the ring.
    static func numberCenterY(width: CGFloat) -> CGFloat {
        arcCenterY(width: width) - 12
    }
    /// Height of one warning badge's box.
    static let badgeRowHeight: CGFloat = 28
    /// Half the score's digits, measured from `numberCenterY`, and the space the row of
    /// warning signs keeps under them. The row hangs off the score rather than off the
    /// hero's bottom edge, so it clears the digits by the same amount at every ring size.
    static let numberHalfHeight: CGFloat = 27
    static let numberBadgeGap: CGFloat = 8
    static func badgeRowCenterY(width: CGFloat) -> CGFloat {
        numberCenterY(width: width) + numberHalfHeight + numberBadgeGap + badgeRowHeight / 2
    }
    static let sampleCount = 20
    /// Space kept between the held flat bar and the first card row: the grid spacing.
    static let heldGridGap: CGFloat = 14

    /// SwiftUI's y grows downward, so -90 degrees is the top of the circle. The sweep runs
    /// from -190 to 10: poor at the left, prime at the right, centered on the top.
    static let arcStartAngle = Angle.degrees(-190), arcEndAngle = Angle.degrees(10)

    /// Half-open score ranges over 0..<101, in `segmentOrder`.
    static let bandScoreRanges: [Range<Int>] = [0..<30, 30..<65, 65..<80, 80..<95, 95..<101]

    /// Total score points the bands cover, used for each band's share of the track.
    private static let scoreSpan: CGFloat = 101

    private static var sweepRadians: CGFloat {
        CGFloat(arcEndAngle.radians - arcStartAngle.radians)
    }

    static func segmentIndex(forScore score: Int) -> Int {
        let clamped = min(max(score, 0), 100)
        return bandScoreRanges.firstIndex { $0.contains(clamped) } ?? bandScoreRanges.count - 1
    }

    /// Parameters of the pill's underdamped slide. Kept here so the overshoot the spring
    /// produces can be worked out from the same numbers that drive it.
    static let pillSpringMass: Double = 1
    static let pillSpringStiffness: Double = 55
    static let pillSpringDamping: Double = 10

    /// How far past its target the pill's spring first swings, as a share of the distance
    /// it travelled: the first-overshoot ratio of the underdamped spring above, which also
    /// bounds every later swing back.
    static var pillSpringOvershootRatio: Double {
        let ratio = pillSpringDamping / (2 * (pillSpringStiffness * pillSpringMass).squareRoot())
        guard ratio < 1 else { return 0 }
        return exp(-ratio * .pi / (1 - ratio * ratio).squareRoot())
    }

    /// How the pill should travel from `from` to `to`, so that no frame of the move shows
    /// a band other than the one it started in or the one it lands in.
    enum PillMove: Equatable {
        /// The plain underdamped spring: every swing stays inside the target's band.
        case bounce
        /// A landing at the far edge of its band (the edge it would leave through if it
        /// overshot): ease in with no overshoot at all.
        case settle
        /// A landing at the near edge of its band (the edge it enters through, where any
        /// swing back would cross into the band it came from): rush past the target to
        /// `overshoot`, still inside the band, then ease back to the target.
        case overshootThenReturn(overshoot: Double)
    }

    /// Farthest the rush of an `overshootThenReturn` move carries past its target.
    static let pillMaxDeliberateOvershoot: Double = 8

    static func pillMove(from: Double, to: Double) -> PillMove {
        let distance = abs(to - from)
        guard distance > 0 else { return .bounce }
        let swing = distance * pillSpringOvershootRatio
        let range = bandScoreRanges[segmentIndex(forScore: Int(to.rounded(.down)))]
        let lower = Double(range.lowerBound)
        // The top of a band is exclusive, so the pill may go no further than just under it.
        let upper = Double(range.upperBound) - 0.001
        let movingUp = to > from
        // Room past the target before the far edge, and before the near edge behind it.
        let roomAhead = movingUp ? upper - to : to - lower
        let roomBehind = movingUp ? to - lower : upper - to

        if swing <= roomAhead && swing <= roomBehind {
            return .bounce
        }
        if swing > roomAhead {
            return .settle
        }
        let overshoot = min(swing, roomAhead * 0.6, pillMaxDeliberateOvershoot)
        guard overshoot > 0.5 else { return .settle }
        return .overshootThenReturn(overshoot: movingUp ? to + overshoot : to - overshoot)
    }

    /// The stretch at a full pull, 0...1: the input `layout(progress:width:stretch:)` takes.
    static let maxPullStretch: CGFloat = 1
    /// Pull distance at which the stretch is a little over half way to `maxPullStretch`.
    static let pullStretchDistance: CGFloat = 110
    /// At full stretch each gap widens by this share of itself. The bands keep their
    /// resting lengths and the ring its radius, so the extra track length opens the
    /// sweep and the ends swing further down the sides.
    static let stretchGapGrowth: CGFloat = 1.0
    /// The deepest squeeze, as a negative stretch. The release spring swings past rest
    /// into it, which is what makes the bands bounce like bubbles on the way home.
    static let maxSqueeze: CGFloat = 0.6
    /// At a squeeze of 1 each band is this share thicker and this share shorter.
    static let squeezeBarGrowth: CGFloat = 0.8
    static let squeezeLengthShrink: CGFloat = 0.5
    /// At a stretch of 1 each band is drawn out like pulled rubber: this share thinner
    /// and this share longer. The squeeze is the other half of the same wobble.
    static let stretchBarThinning: CGFloat = 0.25
    static let stretchLengthGrowth: CGFloat = 0.15
    /// How long the ring's ends trail its middle on the release, so the bounce runs
    /// outward along the ring as a ripple instead of every band moving as one.
    static let rippleDelay: TimeInterval = 0.07

    /// How far the ring is stretched for a pull-down of `pull` points past rest: grows
    /// quickly at first, then eases toward `maxPullStretch` like a rubber band.
    static func pullStretch(pull: CGFloat) -> CGFloat {
        guard pull > 0 else { return 0 }
        return maxPullStretch * (1 - exp(-pull / pullStretchDistance))
    }

    static func arcRadius(width: CGFloat) -> CGFloat {
        max(0, min(width / 2 - arcBarWidth / 2 - 8, maxArcRadius))
    }

    /// Center of the circle the arc is drawn on, in the hero's own coordinates.
    static func arcCenterY(width: CGFloat) -> CGFloat {
        arcTopInset + arcRadius(width: width)
    }

    /// The hero's height: where the arc's end caps stop drawing, or the bottom of the
    /// warning row when the ring is small enough that the row reaches past them. Nothing
    /// else is reserved, so the comment under the hero sits the grid spacing away from
    /// the bars rather than from a band of empty space.
    static func heroHeight(width: CGFloat) -> CGFloat {
        let radius = arcRadius(width: width)
        let arcBottom = arcCenterY(width: width) + radius * CGFloat(sin(arcEndAngle.radians)) + arcBarWidth / 2
        return max(arcBottom, badgeRowCenterY(width: width) + badgeRowHeight / 2)
    }

    /// How far the page's readiness glow reaches, as a share of the ring's radius: a
    /// quarter again past the bars, so the color spreads a little beyond the ring
    /// without washing the first card row below the comment.
    static let glowRadiusRatio: CGFloat = 1.25

    static func glowRadius(width: CGFloat) -> CGFloat {
        arcRadius(width: width) * glowRadiusRatio
    }

    static func flatInset(width: CGFloat) -> CGFloat {
        flatBarWidth / 2 + 4
    }

    static func barWidth(progress: Double) -> CGFloat {
        lerp(arcBarWidth, flatBarWidth, CGFloat(clamped01(progress)))
    }

    static func textOpacity(progress: Double, width: CGFloat) -> Double {
        let faded = progress * Double(morphDistance(width: width)) / Double(numberFadeDistance)
        return 1 - min(max(faded, 0), 1)
    }

    static func isTextVisible(progress: Double, width: CGFloat) -> Bool {
        textOpacity(progress: progress, width: width) > textVisibleThreshold
    }

    static func minimumSegmentLength(barWidth: CGFloat) -> CGFloat {
        barWidth + 8
    }

    /// One state of the track: the five band polylines plus the parameters needed to put
    /// the dot anywhere along it.
    struct Layout {
        /// 5 segments of `sampleCount` centerline points each, in `segmentOrder`.
        let segments: [[CGPoint]]
        /// Centerline length of each segment in points.
        let segmentLengths: [CGFloat]
        /// Where each segment starts and ends, in points from the track start.
        let segmentSpans: [ClosedRange<CGFloat>]
        let trackLength: CGFloat
        /// The bar width at rest for this progress; each band's own is `segmentBarWidths`.
        let barWidth: CGFloat
        /// Each band's width, which leaves `barWidth` only while the ring wobbles.
        let segmentBarWidths: [CGFloat]

        let centerX: CGFloat
        /// y of the track's midpoint, which is its highest point while it is curved.
        let topY: CGFloat
        /// Radius of the bend, nil once the track is straight.
        let curveRadius: CGFloat?

        /// Point on the track centerline at `distance` points from the track start.
        func point(atDistance distance: CGFloat) -> CGPoint {
            BodyReadinessArcGeometry.point(
                atDistance: distance,
                trackLength: trackLength,
                centerX: centerX,
                topY: topY,
                curveRadius: curveRadius
            )
        }

        /// Unit tangent at `distance`, for rotating the dot to the track.
        func tangent(atDistance distance: CGFloat) -> CGVector {
            guard let radius = curveRadius else {
                return CGVector(dx: 1, dy: 0)
            }
            let angle = (distance - trackLength / 2) / radius
            return CGVector(dx: cos(angle), dy: sin(angle))
        }

        /// Unit normal at `distance` (the tangent turned a quarter turn), pointing away
        /// from the bend's center while the track is curved.
        func normal(atDistance distance: CGFloat) -> CGVector {
            let tangent = tangent(atDistance: distance)
            return CGVector(dx: tangent.dy, dy: -tangent.dx)
        }

        /// The closed outline of one band drawn `lineWidth` thick with round caps: the
        /// outer edge, a semicircular cap, the inner edge back, and the other cap, all
        /// sampled along the track. A single simple polygon, so a translucent fill has no
        /// overlapping join geometry to double-paint the way a stroked polyline does.
        func outline(segmentIndex index: Int, lineWidth: CGFloat, samples: Int = 24) -> Path {
            let span = segmentSpans[index]
            let half = lineWidth / 2
            var points: [CGPoint] = []

            func edge(offset: CGFloat, reversed: Bool) {
                for step in 0..<samples {
                    let fraction = samples > 1 ? CGFloat(step) / CGFloat(samples - 1) : 0
                    let distance = reversed
                        ? span.upperBound - fraction * (span.upperBound - span.lowerBound)
                        : span.lowerBound + fraction * (span.upperBound - span.lowerBound)
                    let center = point(atDistance: distance)
                    let normal = normal(atDistance: distance)
                    points.append(CGPoint(x: center.x + normal.dx * offset, y: center.y + normal.dy * offset))
                }
            }

            func cap(atDistance distance: CGFloat, forward: Bool) {
                let center = point(atDistance: distance)
                let tangent = tangent(atDistance: distance)
                let base = atan2(tangent.dy, tangent.dx)
                let capSamples = 12
                for step in 0...capSamples {
                    let fraction = CGFloat(step) / CGFloat(capSamples)
                    // From the outer normal, around the end, to the inner normal.
                    let angle = forward
                        ? base - .pi / 2 + fraction * .pi
                        : base + .pi / 2 + fraction * .pi
                    points.append(CGPoint(x: center.x + cos(angle) * half, y: center.y + sin(angle) * half))
                }
            }

            edge(offset: half, reversed: false)
            cap(atDistance: span.upperBound, forward: true)
            edge(offset: -half, reversed: true)
            cap(atDistance: span.lowerBound, forward: false)

            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            return path
        }

        /// Distance along the track for a score, kept far enough inside the ends of the
        /// band the score belongs to that the pill's rounded end stays within the bar's
        /// round cap (the cap reaches `barWidth / 2` past the endpoint) and never laps
        /// into a gap.
        func dotDistance(score: Double) -> CGFloat {
            let clamped = min(max(score, 0), 100)
            let index = BodyReadinessArcGeometry.segmentIndex(forScore: Int(clamped.rounded(.down)))
            let range = BodyReadinessArcGeometry.bandScoreRanges[index]
            let lower = Double(range.lowerBound)
            let upper = Double(range.upperBound)
            let fraction = upper > lower ? (clamped - lower) / (upper - lower) : 0
            let span = segmentSpans[index]
            let raw = span.lowerBound + CGFloat(fraction) * (span.upperBound - span.lowerBound)
            let inset = max(BodyReadinessArcGeometry.dotLength / 2 - segmentBarWidths[index] / 2 + 3, 2)
            let low = span.lowerBound + inset
            let high = span.upperBound - inset
            guard high > low else {
                return (span.lowerBound + span.upperBound) / 2
            }
            return min(max(raw, low), high)
        }
    }

    /// The hero at rest: the 200 degree arc of `arcRadius` around (width / 2, `arcCenterY`).
    static func arcLayout(width: CGFloat) -> Layout {
        layout(progress: 0, width: width)
    }

    /// The pinned row: a straight track at `flatY`, inset by `flatInset` at both ends.
    static func flatLayout(width: CGFloat) -> Layout {
        layout(progress: 1, width: width)
    }

    /// The track partway through the morph. The sweep closes toward zero while the track
    /// length and the bar width move to their flat values, so progress 0 and progress 1 are
    /// exactly `arcLayout` and `flatLayout`.
    /// `stretch` (0...1) is the pull-down stretch: the bands keep their resting lengths
    /// and the ring its radius while every gap widens, so the track gets longer, its
    /// sweep opens and the ends drop further down the sides, with the top of the track
    /// held where it is, and the bands draw out a little thinner and longer. A negative
    /// stretch (down to `-maxSqueeze`) is the rebound's squeeze: the bands get shorter
    /// and fatter and the sweep closes a little. The morph never runs with a stretch (a pull only happens at
    /// rest), so the two are simply composed.
    /// `trailingStretch` is the stretch at the ring's ends when it differs from the
    /// middle's: each band takes its own value between the two by how far it sits from
    /// the middle, so a delayed trailing spring ripples the bounce outward.
    static func layout(
        progress: Double,
        width: CGFloat,
        stretch: CGFloat = 0,
        trailingStretch: CGFloat? = nil
    ) -> Layout {
        let amount = CGFloat(clamped01(progress))
        let radius = arcRadius(width: width)
        let arcLength = radius * sweepRadians
        let flatLength = max(width - 2 * flatInset(width: width), 0)
        let restSweep = sweepRadians * (1 - amount)
        let restLength = fittedTrackLength(arcLength: arcLength, flatLength: flatLength, sweep: restSweep, amount: amount)
        let restBar = lerp(arcBarWidth, flatBarWidth, amount)
        let restGap = restBar + visualGap + morphMargin

        let restLengths = allocateSegmentLengths(trackLength: restLength, gap: restGap, barWidth: restBar)
        let count = restLengths.count

        // Each band is a bubble: pulled, it draws out thinner and longer; squeezed on
        // the rebound, it presses shorter and fatter.
        let middle = CGFloat(count - 1) / 2
        let stretches = (0..<count).map { index -> CGFloat in
            let fromMiddle = middle > 0 ? abs(CGFloat(index) - middle) / middle : 0
            let value = lerp(stretch, trailingStretch ?? stretch, fromMiddle)
            return min(max(value, -maxSqueeze), maxPullStretch)
        }
        let bars = stretches.map { value in
            restBar * (value < 0 ? 1 - squeezeBarGrowth * value : 1 - stretchBarThinning * value)
        }
        let lengths = zip(restLengths, stretches).map { length, value in
            length * (value < 0 ? 1 + squeezeLengthShrink * value : 1 + stretchLengthGrowth * value)
        }
        // A gap opens with the pull and follows its two bands' caps, so a fatter or
        // thinner band never closes or opens the space you can see between them.
        let gaps = (0..<max(count - 1, 0)).map { index -> CGFloat in
            let pull = max((stretches[index] + stretches[index + 1]) / 2, 0)
            let caps = (bars[index] + bars[index + 1]) / 2 - restBar
            return restGap * (1 + stretchGapGrowth * pull) + caps
        }
        let trackLength = lengths.reduce(0, +) + gaps.reduce(0, +)
        // Same bend radius as at rest, so the longer track sweeps further round it.
        let sweep = restSweep > 1e-9 ? trackLength / (restLength / restSweep) : 0

        var spans: [ClosedRange<CGFloat>] = []
        var cursor: CGFloat = 0
        for (index, length) in lengths.enumerated() {
            spans.append(cursor...(cursor + length))
            cursor += length + (index < gaps.count ? gaps[index] : 0)
        }

        let curveRadius: CGFloat? = sweep > 1e-9 ? trackLength / sweep : nil
        let centerX = width / 2
        // The arc's top stays at its inset whatever the radius, so the stretch grows the
        // ring downward and outward from its top rather than lifting it off the page.
        let topY = lerp(arcTopInset, flatY, amount)

        let segments = spans.map { span in
            (0..<sampleCount).map { step -> CGPoint in
                let fraction = sampleCount > 1 ? CGFloat(step) / CGFloat(sampleCount - 1) : 0
                let distance = span.lowerBound + fraction * (span.upperBound - span.lowerBound)
                return point(
                    atDistance: distance,
                    trackLength: trackLength,
                    centerX: centerX,
                    topY: topY,
                    curveRadius: curveRadius
                )
            }
        }

        return Layout(
            segments: segments,
            segmentLengths: lengths,
            segmentSpans: spans,
            trackLength: trackLength,
            barWidth: restBar,
            segmentBarWidths: bars,
            centerX: centerX,
            topY: topY,
            curveRadius: curveRadius
        )
    }

    /// The track length at a given bend. On phone widths, where the arc is longer than
    /// the flat bar, the track keeps its full arc length while it unbends, so the bars
    /// only straighten, and once its end to end width has opened out to the flat bar's
    /// width it holds that width and shortens instead, reaching `flatLength` exactly as
    /// the bend closes. The bars therefore never reach past where the flat bar will sit,
    /// which a plain length lerp did. On wide layouts the flat bar is the longer of the
    /// two, a bent track never spans more than its own length, so the length just lerps.
    private static func fittedTrackLength(arcLength: CGFloat, flatLength: CGFloat, sweep: CGFloat, amount: CGFloat) -> CGFloat {
        guard arcLength > flatLength else { return lerp(arcLength, flatLength, amount) }
        guard sweep > 1e-9 else { return flatLength }
        // A track of length L bent through `sweep` spans 2L sin(sweep / 2) / sweep.
        let lengthSpanningFlat = flatLength * sweep / (2 * sin(sweep / 2))
        return min(arcLength, lengthSpanningFlat)
    }

    /// Shared by `Layout.point(atDistance:)` and by the sampling that builds it: the track
    /// is a circular arc of `curveRadius` through (centerX, topY), or the straight line
    /// through it once the bend has opened all the way out.
    private static func point(
        atDistance distance: CGFloat,
        trackLength: CGFloat,
        centerX: CGFloat,
        topY: CGFloat,
        curveRadius: CGFloat?
    ) -> CGPoint {
        let offset = distance - trackLength / 2
        guard let radius = curveRadius else {
            return CGPoint(x: centerX + offset, y: topY)
        }
        let angle = offset / radius
        return CGPoint(
            x: centerX + radius * sin(angle),
            y: topY + radius * (1 - cos(angle))
        )
    }

    /// Sample points of the five segments at this point in the morph.
    static func segmentPoints(progress: Double, width: CGFloat) -> [[CGPoint]] {
        layout(progress: progress, width: width).segments
    }

    /// Center of the dot pill for the presented score, which animates, so the score is a
    /// Double and the band comes from its floor.
    static func dotCenter(score: Double, progress: Double, width: CGFloat) -> CGPoint {
        let layout = layout(progress: progress, width: width)
        return layout.point(atDistance: layout.dotDistance(score: score))
    }

    /// Tangent angle at the dot, for `rotationEffect` on the dot capsule.
    static func dotAngle(score: Double, progress: Double, width: CGFloat) -> Angle {
        let layout = layout(progress: progress, width: width)
        let tangent = layout.tangent(atDistance: layout.dotDistance(score: score))
        return Angle.radians(atan2(Double(tangent.dy), Double(tangent.dx)))
    }

    /// Shares the centerline left over by the gaps across the bands by score share, with
    /// any band that would fall under `minimumSegmentLength` pinned to the minimum and the
    /// rest re-shared, repeated until nothing else drops. If even five minimums and the
    /// gaps do not fit, every band takes an equal cut of what is there so the track still
    /// fits the width it was given.
    private static func allocateSegmentLengths(
        trackLength: CGFloat,
        gap: CGFloat,
        barWidth: CGFloat
    ) -> [CGFloat] {
        let count = bandScoreRanges.count
        let shares = bandScoreRanges.map { CGFloat($0.count) / scoreSpan }
        let available = max(trackLength - gap * CGFloat(count - 1), 0)
        let minimum = minimumSegmentLength(barWidth: barWidth)

        guard minimum * CGFloat(count) <= available else {
            return Array(repeating: available / CGFloat(count), count: count)
        }

        var lengths = [CGFloat](repeating: 0, count: count)
        var pinned = [Bool](repeating: false, count: count)
        while true {
            let pinnedCount = pinned.filter { $0 }.count
            let remaining = available - minimum * CGFloat(pinnedCount)
            let openShare = zip(shares, pinned).reduce(CGFloat(0)) { $1.1 ? $0 : $0 + $1.0 }
            var dropped = false
            for index in 0..<count where !pinned[index] {
                lengths[index] = openShare > 0 ? remaining * shares[index] / openShare : minimum
                if lengths[index] < minimum {
                    pinned[index] = true
                    dropped = true
                }
            }
            for index in 0..<count where pinned[index] {
                lengths[index] = minimum
            }
            if !dropped {
                return lengths
            }
        }
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ amount: CGFloat) -> CGFloat {
        (1 - amount) * from + amount * to
    }

    private static func clamped01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// One band as its closed outline at the current bar width. Not animatable on purpose:
/// the morph is driven by scroll progress, which already produces every intermediate
/// shape, so letting SwiftUI interpolate the path as well would fight it.
struct BodyReadinessSegmentShape: Shape {
    let layout: BodyReadinessArcGeometry.Layout
    let index: Int

    func path(in rect: CGRect) -> Path {
        layout.outline(segmentIndex: index, lineWidth: layout.segmentBarWidths[index])
    }
}

/// The hero's tap target: every band widened to at least a finger, plus the score text when
/// it is still on screen, so the whole hero answers to one gesture without the gaps between
/// the bands punching holes in it.
struct BodyReadinessHeroHitShape: Shape {
    let layout: BodyReadinessArcGeometry.Layout
    let lineWidth: CGFloat
    let textRect: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in layout.segments.indices {
            path.addPath(layout.outline(segmentIndex: index, lineWidth: lineWidth, samples: 8))
        }
        if let textRect {
            path.addRect(textRect)
        }
        return path
    }
}
