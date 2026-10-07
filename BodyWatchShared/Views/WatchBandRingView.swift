//
//  WatchBandRingView.swift
//  BodyWatchShared
//
//  The banded complication ring: a status scale's bands bent around a circle
//  (a 300 degree ring, open at the bottom, lowest band at the lower left round
//  to the highest at the lower right), the active band tinted, a pill marking
//  the score within it, and the score in the middle. The Readiness
//  complication draws the home hero's five bands with it
//  (`BodyReadinessArcGeometry.bandScoreRanges`), the Stress bands complication
//  Stress's four (`WatchStressBands.scoreRanges`).
//
//  Watch-only: not compiled into the iOS `Body` target. It lives here rather
//  than in the widget extension so `BodyWatchTests` can test and render it.
//

import SwiftUI
import WidgetKit

struct WatchBandRingView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    /// Half-open score ranges over 0..<101, lowest band first.
    let bandScoreRanges: [Range<Int>]
    let score: Int?
    /// The active band's color.
    let tint: Color
    /// The score's size as a share of the ring's side, from
    /// `complicationRingFontScale`, as for `WatchMetricRingView`.
    let valueFontScale: Double
    /// Shown in the middle when there is no score; nil shows the watch glyph.
    var emptyText: String? = nil

    /// SwiftUI's y grows downward, so 90 degrees is the bottom of the circle.
    /// Wider than `WatchMetricRingView`'s 270 degrees: five bands and four gaps
    /// need the extra track, and no glyph sits in the opening.
    static let startAngle = Angle.degrees(120), sweep = Angle.degrees(300)
    /// Visible space between two bands' round caps.
    private static let visualGap: CGFloat = 1.5
    /// Every band gets this much centerline (plus its caps) before the rest of
    /// the ring is shared out by score range, so Readiness Prime's 6 points
    /// still read as a band rather than a dot.
    private static let minimumBandLength: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // Same stroke and value scale as `WatchMetricRingView`, so a banded
            // ring sits level with the other metrics' rings on a face.
            let lineWidth = max(side * 0.16, 4)
            let radius = (side - lineWidth) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let bands = Self.bandAngles(bandScoreRanges, radius: radius, lineWidth: lineWidth)
            let activeIndex = score.map { Self.segmentIndex(forScore: $0, in: bandScoreRanges) }

            ZStack {
                ForEach(bands.indices, id: \.self) { index in
                    let isActive = activeIndex == index
                    Path { path in
                        path.addArc(center: center, radius: radius, startAngle: bands[index].lowerBound, endAngle: bands[index].upperBound, clockwise: false)
                    }
                    .stroke(
                        isActive ? tint.opacity(renderingMode == .fullColor ? 0.45 : 0.55) : Color.primary.opacity(0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .widgetAccentable(isActive)
                }

                if let score, let activeIndex, bands.indices.contains(activeIndex) {
                    let angle = Self.pillAngle(score: score, band: bands[activeIndex], range: bandScoreRanges[activeIndex])
                    Circle()
                        .fill(tint)
                        .frame(width: lineWidth - 2, height: lineWidth - 2)
                        .position(
                            x: center.x + radius * CGFloat(cos(angle.radians)),
                            y: center.y + radius * CGFloat(sin(angle.radians))
                        )
                        .widgetAccentable()
                }

                if let text = score.map({ "\($0)" }) ?? emptyText {
                    Text(verbatim: text)
                        .font(.system(size: side * valueFontScale, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .frame(width: side - 2 * lineWidth - 4)
                } else {
                    Image(systemName: "applewatch")
                        .font(.system(size: side * 0.3))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The band holding `score`, clamped to 0...100: the same rule as
    /// `BodyReadinessArcGeometry.segmentIndex(forScore:)`.
    static func segmentIndex(forScore score: Int, in ranges: [Range<Int>]) -> Int {
        let clamped = min(max(score, 0), 100)
        return ranges.firstIndex { $0.contains(clamped) } ?? ranges.count - 1
    }

    /// Each band's centerline span, in `ranges` order. Round caps extend half
    /// a line width past each end, so a gap reserves a full line width on top
    /// of the visible space.
    static func bandAngles(_ ranges: [Range<Int>], radius: CGFloat, lineWidth: CGFloat) -> [ClosedRange<Angle>] {
        guard radius > 0, !ranges.isEmpty else { return [] }
        let gap = (lineWidth + visualGap) / radius
        // The ring's own end caps take half a line width each.
        let usable = max(CGFloat(sweep.radians) - lineWidth / radius - gap * CGFloat(ranges.count - 1), 0)
        let minimum = min(minimumBandLength / radius, usable / CGFloat(ranges.count))
        let shared = usable - minimum * CGFloat(ranges.count)
        let span = CGFloat(ranges.reduce(0) { $0 + $1.count })

        var cursor = CGFloat(startAngle.radians) + lineWidth / 2 / radius
        return ranges.map { range in
            let length = minimum + shared * CGFloat(range.count) / span
            defer { cursor += length + gap }
            return Angle.radians(Double(cursor))...Angle.radians(Double(cursor + length))
        }
    }

    /// The score's position within its band, as `Layout.dotDistance(score:)`
    /// places the Readiness hero's pill.
    static func pillAngle(score: Int, band: ClosedRange<Angle>, range: Range<Int>) -> Angle {
        let clamped = min(max(score, range.lowerBound), range.upperBound - 1)
        let fraction = range.count > 1 ? Double(clamped - range.lowerBound) / Double(range.count - 1) : 0.5
        return band.lowerBound + (band.upperBound - band.lowerBound) * fraction
    }
}
