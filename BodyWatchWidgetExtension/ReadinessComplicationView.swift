//
//  ReadinessComplicationView.swift
//  BodyWatchWidgetExtension
//
//  The Readiness complication: the home readiness hero at complication size.
//  Five band segments, the active band tinted with the status color, a pill
//  marking the score, and the score in the middle.
//
//  The hero's bands are bent around a circle (a 300 degree ring, open at the
//  bottom, with thicker bands than the hero's 200 degree arc) so they fill a
//  round slot rather than floating in it: alone in accessoryCircular, beside
//  the title row in accessoryRectangular. The band ranges and the pill's
//  position within a band come from `BodyReadinessArcGeometry`, the same
//  geometry as `WatchReadinessHeroView`.
//  The corner family keeps the curved bezel gauge from `WatchComplicationView`,
//  because a corner's bezel content must be a system Gauge.
//

import SwiftUI
import WidgetKit

struct ReadinessComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchMetricEntry

    private var metric: WatchMetric? { entry.snapshot.metric(forKind: WatchMetricKindKey.readiness) }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryCorner:
            WatchComplicationView(metricKind: WatchMetricKindKey.readiness, entry: entry)
        default:
            circular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            ReadinessComplicationRing(score: metric?.score, tint: tint, valueFontScale: 0.30)
                .padding(1)
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            ReadinessComplicationRing(score: metric?.score, tint: tint)
                .frame(width: 46, height: 46)
                // The ring is open at the bottom, so its drawn part sits high
                // in its frame; nudge it down to center what is visible.
                .offset(y: 1)

            if let metric {
                VStack(alignment: .leading, spacing: 1) {
                    // The ring already shows the score, so the row leads with
                    // the level. A snapshot from an older phone build carries
                    // no label; fall back to the value.
                    if let level = metric.statusBand?.label {
                        Text(level)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(metric.displayValue + metric.unit)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(metric.title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } else {
                Text("Open Body on iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .rectangularComplicationBorder()
        .containerBackground(.clear, for: .widget)
    }

    private var tint: Color {
        Color(metric?.resolvedTint ?? WatchMetricKindKey.tint(forKind: WatchMetricKindKey.readiness))
    }
}

/// The hero's bands bent around a circle: a 300 degree ring, open at
/// the bottom, poor at the lower left round to prime at the lower right.
private struct ReadinessComplicationRing: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let score: Int?
    let tint: Color
    var valueFontScale: Double = 0.40

    private typealias Geometry = BodyReadinessArcGeometry

    /// SwiftUI's y grows downward, so 90 degrees is the bottom of the circle.
    /// Wider than `WatchMetricRingView`'s 270 degrees: five bands and four gaps
    /// need the extra track, and no glyph sits in the opening.
    private static let startAngle = Angle.degrees(120), sweep = Angle.degrees(300)
    /// Visible space between two bands' round caps.
    private static let visualGap: CGFloat = 1.5
    /// Every band gets this much centerline (plus its caps) before the rest of
    /// the ring is shared out by score range, so Prime's 6 points still read as
    /// a band rather than a dot.
    private static let minimumBandLength: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            // Same stroke and value scale as `WatchMetricRingView`, so the
            // Readiness ring sits level with the other metrics' rings on a face.
            let lineWidth = max(side * 0.16, 4)
            let radius = (side - lineWidth) / 2
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let bands = Self.bandAngles(radius: radius, lineWidth: lineWidth)
            let activeIndex = score.map { Geometry.segmentIndex(forScore: $0) }

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

                if let score, let activeIndex {
                    let angle = Self.pillAngle(score: score, band: bands[activeIndex], index: activeIndex)
                    Circle()
                        .fill(tint)
                        .frame(width: lineWidth - 2, height: lineWidth - 2)
                        .position(
                            x: center.x + radius * CGFloat(cos(angle.radians)),
                            y: center.y + radius * CGFloat(sin(angle.radians))
                        )
                        .widgetAccentable()
                }

                if let score {
                    Text(verbatim: "\(score)")
                        .font(.system(size: side * complicationRingFontScale(for: "\(score)", base: valueFontScale), weight: .bold, design: .rounded))
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

    /// Each band's centerline span, in `Geometry.bandScoreRanges` order. Round
    /// caps extend half a line width past each end, so a gap reserves a full
    /// line width on top of the visible space.
    private static func bandAngles(radius: CGFloat, lineWidth: CGFloat) -> [ClosedRange<Angle>] {
        guard radius > 0 else { return [] }
        let ranges = Geometry.bandScoreRanges
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
    /// places the hero's pill.
    private static func pillAngle(score: Int, band: ClosedRange<Angle>, index: Int) -> Angle {
        let range = Geometry.bandScoreRanges[index]
        let clamped = min(max(score, range.lowerBound), range.upperBound - 1)
        let fraction = range.count > 1 ? Double(clamped - range.lowerBound) / Double(range.count - 1) : 0.5
        return band.lowerBound + (band.upperBound - band.lowerBound) * fraction
    }
}

/// The gallery placeholder with Readiness at `score`, for the previews.
private func previewEntry(score: Int, level: String, red: Double, green: Double, blue: Double) -> WatchMetricEntry {
    var snapshot = WatchMetricsSnapshot.placeholder
    if let index = snapshot.metrics.firstIndex(where: { $0.kind == WatchMetricKindKey.readiness }) {
        snapshot.metrics[index].score = score
        snapshot.metrics[index].displayValue = "\(score)"
        snapshot.metrics[index].tint = WatchMetricColor(red: red, green: green, blue: blue)
        snapshot.metrics[index].statusBand?.label = level
    }
    return WatchMetricEntry(date: .now, snapshot: snapshot)
}

#Preview("Circular", as: .accessoryCircular) {
    ReadinessComplication()
} timeline: {
    previewEntry(score: 78, level: "Moderate", red: 0.10, green: 0.82, blue: 0.20)
    previewEntry(score: 97, level: "Prime", red: 0.84, green: 0.08, blue: 0.92)
    previewEntry(score: 86, level: "High", red: 0.20, green: 0.74, blue: 1.00)
    previewEntry(score: 52, level: "Low", red: 1.00, green: 0.75, blue: 0.15)
    previewEntry(score: 21, level: "Poor", red: 1.00, green: 0.25, blue: 0.12)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    ReadinessComplication()
} timeline: {
    previewEntry(score: 78, level: "Moderate", red: 0.10, green: 0.82, blue: 0.20)
    previewEntry(score: 97, level: "Prime", red: 0.84, green: 0.08, blue: 0.92)
    previewEntry(score: 86, level: "High", red: 0.20, green: 0.74, blue: 1.00)
    previewEntry(score: 52, level: "Low", red: 1.00, green: 0.75, blue: 0.15)
    previewEntry(score: 21, level: "Poor", red: 1.00, green: 0.25, blue: 0.12)
    WatchMetricEntry(date: .now, snapshot: .empty)
}

#Preview("Corner", as: .accessoryCorner) {
    ReadinessComplication()
} timeline: {
    previewEntry(score: 78, level: "Moderate", red: 0.10, green: 0.82, blue: 0.20)
    previewEntry(score: 97, level: "Prime", red: 0.84, green: 0.08, blue: 0.92)
    previewEntry(score: 86, level: "High", red: 0.20, green: 0.74, blue: 1.00)
    previewEntry(score: 52, level: "Low", red: 1.00, green: 0.75, blue: 0.15)
    previewEntry(score: 21, level: "Poor", red: 1.00, green: 0.25, blue: 0.12)
    WatchMetricEntry(date: .now, snapshot: .empty)
}
