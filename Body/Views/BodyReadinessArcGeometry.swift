//
//  BodyReadinessArcGeometry.swift
//  Body
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
    static let heroHeight: CGFloat = 226
    static let arcCenterY: CGFloat = 164
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
    static let morphDistance: CGFloat = heroHeight + 14 - (flatY + flatBarWidth / 2 + 14)
    /// Scroll points until the big score number is fully faded.
    static let numberFadeDistance: CGFloat = 60
    static let textVisibleThreshold: Double = 0.1
    /// The score sits inside the ring, on the circle's center line.
    static let numberCenterY: CGFloat = 152
    static let badgeRowCenterY: CGFloat = 204
    static let sampleCount = 20
    /// Space kept between the held flat bar and the first card row: the grid spacing.
    static let heldGridGap: CGFloat = 14

    /// SwiftUI's y grows downward, so -90 degrees is the top of the circle. The sweep runs
    /// from -190 to 10: poor at the left, prime at the right, centered on the top.
    static let arcStartAngle = Angle.degrees(-190), arcEndAngle = Angle.degrees(10)

    static let segmentOrder: [ReadinessStatus] = [.poor, .low, .moderate, .high, .prime]

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

    static func arcRadius(width: CGFloat) -> CGFloat {
        min(width / 2 - arcBarWidth / 2 - 8, 140)
    }

    static func flatInset(width: CGFloat) -> CGFloat {
        flatBarWidth / 2 + 4
    }

    static func barWidth(progress: Double) -> CGFloat {
        lerp(arcBarWidth, flatBarWidth, CGFloat(clamped01(progress)))
    }

    static func textOpacity(progress: Double) -> Double {
        let faded = progress * Double(morphDistance) / Double(numberFadeDistance)
        return 1 - min(max(faded, 0), 1)
    }

    static func isTextVisible(progress: Double) -> Bool {
        textOpacity(progress: progress) > textVisibleThreshold
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
        let barWidth: CGFloat

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
            let inset = max(BodyReadinessArcGeometry.dotLength / 2 - barWidth / 2 + 3, 2)
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
    static func layout(progress: Double, width: CGFloat) -> Layout {
        let amount = CGFloat(clamped01(progress))
        let radius = arcRadius(width: width)
        let arcLength = radius * sweepRadians
        let flatLength = max(width - 2 * flatInset(width: width), 0)
        let sweep = sweepRadians * (1 - amount)
        let trackLength = fittedTrackLength(arcLength: arcLength, flatLength: flatLength, sweep: sweep, amount: amount)
        let bar = lerp(arcBarWidth, flatBarWidth, amount)
        let gap = bar + visualGap + morphMargin

        let lengths = allocateSegmentLengths(trackLength: trackLength, gap: gap, barWidth: bar)

        var spans: [ClosedRange<CGFloat>] = []
        var cursor: CGFloat = 0
        for length in lengths {
            spans.append(cursor...(cursor + length))
            cursor += length + gap
        }

        let curveRadius: CGFloat? = sweep > 1e-9 ? trackLength / sweep : nil
        let centerX = width / 2
        let topY = lerp(arcCenterY - radius, flatY, amount)

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
            barWidth: bar,
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
        layout.outline(segmentIndex: index, lineWidth: layout.barWidth)
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
