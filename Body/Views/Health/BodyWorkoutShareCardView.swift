//
//  BodyWorkoutShareCardView.swift
//  Body
//
//  The share card, exported at `ImageRenderer.scale = 3` (1080 px on its short
//  side). Its shape is the user's `WorkoutShareAspectRatio` — 9:16, 16:9, 3:4,
//  4:3, or 1:1 — and on a landscape card the `WorkoutShareLandscapeArrangement`
//  decides whether route and metrics stack or sit side by side. No layout number
//  is written here: `WorkoutShareCardGeometry` derives every frame, scrim, and
//  anchor from those two inputs, so the card, the sheet's map region, the
//  transforms, and the render tests can't drift apart.
//  Purely value-driven and environment-independent: every color, size, and weight
//  is explicit so the rendered image looks identical no matter what environment
//  `ImageRenderer` runs it under. Three layouts: `.classic` (map background only)
//  mirrors the detail page — identity left, big distance + duration right, route
//  trace centered, metrics row along the bottom; `.centered` (gradient presets and
//  photos) drops the header for label-over-value blocks under (or beside) the trace;
//  `.routeless` (a workout with no GPS route) has no trace to show, so the workout
//  type's symbol stands in as the card's only identity above those same blocks.
//  On photo and video backgrounds the centered layout's info block (trace + metrics,
//  never the pinned branding) is repositionable and resizable: the placement arrives as
//  an `infoTransform` the sheet's gestures drive, and is `.identity` everywhere else.
//  A `.video` background draws nothing of its own — the card becomes a transparent
//  overlay the sheet holds over a player layer (preview) or composites onto every
//  frame of the exported MP4.
//

import SwiftUI
import UIKit

/// What fills the card behind the content. `.map` is a pre-composited route-map
/// snapshot, so the card skips its own Canvas trace for that case. `.video` draws
/// *nothing*: the moving frames come from a player layer the sheet puts under the
/// card in the preview, and from the video composition on export — either way the
/// card is the transparent overlay held over them, scrims and all.
enum WorkoutShareCardBackground {
    case preset(BodyWorkoutSharePreset)
    case photo(UIImage)
    case map(UIImage)
    case video
}

/// Which arrangement the card draws. Passed in rather than derived from `background`:
/// while the map snapshot loads, the sheet's background falls back to `.preset(.midnight)`,
/// and deriving from that would flash the centered layout before the map arrives.
enum WorkoutShareCardLayout {
    case classic
    case centered
    /// Explicit rather than "`.centered` with no route points": a route that projects
    /// to nothing (GPS jitter on a treadmill) still gets the plain centered stack, and
    /// only a workout with no route at all earns the type symbol above it.
    case routeless
}

struct BodyWorkoutShareCardView: View {
    let presentation: WorkoutDetailPresentation
    /// The classic layout's bottom row.
    let metrics: [WorkoutShareMetric]
    /// The centered layout's stack — a different selection (distance and time are
    /// blocks here, not header numbers), so both are passed in and the layout picks.
    let centeredMetrics: [WorkoutShareMetric]
    /// Already normalized to the unit square by `WorkoutShareRouteProjection`. `nil`
    /// collapses the trace into a metrics-only card.
    let routePoints: [CGPoint]?
    /// The route's elevation ribbon at rest (yaw 0), computed once by the sheet. Drawn
    /// instead of the flat trace when `dimension` is `.threeD`; `nil` falls back to it.
    let route3D: WorkoutRoute3DProjection.Projected3D?
    /// Already resolved through `WorkoutShareBackgroundPolicy.resolvedDimension` — the
    /// card never re-checks the Pro entitlement.
    let dimension: WorkoutShareRouteDimension
    /// Whether the route-less layout's type glyph is drawn. Every other layout ignores
    /// it — there's no glyph to hide once a trace or header carries the card's identity.
    let iconHidden: Bool
    let locality: String?
    let type: BodyWorkoutType
    let background: WorkoutShareCardBackground
    let layout: WorkoutShareCardLayout
    /// The card's shape. Already resolved through
    /// `WorkoutShareBackgroundPolicy.resolvedAspectRatio` — the card never re-checks
    /// the Pro entitlement.
    let aspectRatio: WorkoutShareAspectRatio
    /// Only read on a landscape card that draws a trace; every other shape ignores it.
    let arrangement: WorkoutShareLandscapeArrangement
    /// Where the centered layout's info block sits; `.identity` is its default slot.
    /// The classic layout ignores it.
    let infoTransform: WorkoutShareInfoTransform
    /// How the photo background is panned and zoomed. Only `.photo` reads it.
    let photoTransform: WorkoutSharePhotoTransform
    /// Type design for everything but the brand wordmark.
    let fontDesign: Font.Design
    /// The card-drawn trace's colour (2D polyline and 3D ribbon). The map background's
    /// composited route ignores it and keeps its pace colouring.
    let routeColor: Color

    /// #0128F4 — `WorkoutShareRouteColorChoice.bodyBlue`, the default trace colour.
    static let defaultRouteColor = Color(red: 1 / 255, green: 40 / 255, blue: 244 / 255)

    /// Every frame the card draws with. A value type derived from the three inputs
    /// above, so recomputing it per access is cheaper than caching it.
    private var geometry: WorkoutShareCardGeometry {
        WorkoutShareCardGeometry(
            aspectRatio: aspectRatio,
            layout: layout,
            arrangement: arrangement,
            metricCount: centeredMetrics.count
        )
    }

    /// `.routeless` never traces, whatever it's handed: making that a property of the
    /// layout (rather than of the caller passing `routePoints: nil`) also fixes
    /// `blockAnchor` at `.center`, which is the placement the glyph + stack want.
    private var showsTrace: Bool {
        if case .map = background { return false }
        return layout != .routeless && routePoints != nil
    }

    /// The ribbon to draw instead of the flat trace, or `nil` when this card traces
    /// flat — 2D was picked, or the route carries no usable altitude.
    private var ribbon: WorkoutRoute3DProjection.Projected3D? {
        guard showsTrace, dimension == .threeD else { return nil }
        return route3D
    }

    var body: some View {
        let size = geometry.size
        ZStack {
            backgroundLayer
            scrims
            switch layout {
            case .classic:
                if showsTrace {
                    // Pinned to the same geometry as the map background's route —
                    // `classicRouteRect` is sized off the scrims' clear band — so the
                    // trace sits identically on every background. The square rect keeps
                    // the projection's aspect ratio undistorted; the route inset inside
                    // it leaves room for the stroke.
                    routeHero(bottomAnchored: false)
                        .frame(width: geometry.classicRouteRect.width, height: geometry.classicRouteRect.height)
                        .position(x: geometry.classicRouteRect.midX, y: geometry.classicRouteRect.midY)
                }
                content
            case .centered, .routeless:
                centeredContent
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        let size = geometry.size
        switch background {
        case .preset(let preset):
            preset.gradient(tint: type.color)
        case .photo(let image):
            // Scale then offset, then clip: the fill's overhang beyond the card must
            // survive until after the transform, because the clamp lets the photo pan
            // exactly by that overhang — clipping it first would leave a bare strip.
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .scaleEffect(photoTransform.scale, anchor: .center)
                .offset(photoTransform.offset)
                .frame(width: size.width, height: size.height)
                .clipped()
        case .map(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        case .video:
            // Deliberately empty, sized so the ZStack still gets the card's frame from
            // its background layer. `ImageRenderer.isOpaque` is false, so the rendered
            // overlay keeps this transparency and the clip shows through it.
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

    /// Unconditional top + bottom scrims so white text stays legible over any photo
    /// or map tiles, including a near-white tint. Map tiles carry bright labels and
    /// roads right behind the text, so they get taller, darker shades. The heights are
    /// fractions of the card's height, so a short landscape card isn't swallowed.
    private var scrims: some View {
        let isMap: Bool
        if case .map = background { isMap = true } else { isMap = false }

        return VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(isMap ? 0.85 : 0.45), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: geometry.topScrimHeight(isMap: isMap))

            Spacer(minLength: 0)

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(isMap ? 0.85 : 0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: geometry.bottomScrimHeight(isMap: isMap))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 12)
            bottomBar
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, WorkoutShareCardGeometry.brandingBottomPadding)
    }

    // MARK: - Header (mirrors the detail page's top arrangement)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            headerIdentity
            Spacer(minLength: 8)
            headerNumbers
        }
    }

    private var headerIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: type.symbolName)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                // White symbol on a stronger tint chip: the detail page's tinted-symbol
                // treatment disappears against the card's dark/photo backgrounds.
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(type.color.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                // Bounded rather than free-growing: a long title on a landscape card
                // would otherwise push the header past its (shorter) scrim.
                Text(presentation.title)
                    .font(.system(size: 24, weight: .bold, design: fontDesign))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if let locality {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(locality)
                            .font(.system(size: 14, weight: .medium, design: fontDesign))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }

                Text("\(presentation.dateTitle) - \(presentation.timeRangeText)")
                    .font(.system(size: 14, weight: .medium, design: fontDesign))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    private var headerNumbers: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let heroValue = presentation.heroDistanceValue, let heroUnit = presentation.heroDistanceUnit {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(heroValue)
                            .font(.system(size: 40, weight: .bold, design: fontDesign))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(heroUnit)
                            .font(.system(size: 17, weight: .semibold, design: fontDesign))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Text("Distance")
                        .font(.system(size: 12, weight: .semibold, design: fontDesign))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(presentation.durationClockText)
                    .font(.system(size: 40, weight: .bold, design: fontDesign))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Duration")
                    .font(.system(size: 12, weight: .semibold, design: fontDesign))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Route trace

    /// SwiftUI `Canvas` drawing of the route in `routeColor` — the flat polyline, or the
    /// oblique elevation ribbon in 3D — through the centered, inset rect so the stroke
    /// never clips. No start/end markers: only the map background's composited route
    /// carries those.
    ///
    /// - Parameter bottomAnchored: Translates the finished drawing so its lowest point
    ///   lands on the rect's bottom edge. The centered layout draws that way so the gap
    ///   to the metrics below is the same for a tall route and a wide one (and so the
    ///   3D ribbon's lifted line rises into free space); the classic layout keeps the
    ///   trace centered on the map's own geometry.
    private func routeHero(bottomAnchored: Bool) -> some View {
        WorkoutShareRouteTrace(
            routePoints: routePoints,
            ribbon: ribbon,
            routeColor: routeColor,
            bottomAnchored: bottomAnchored
        )
    }

    // MARK: - Bottom bar (metrics leading, branding trailing)

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 24) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.value)
                        .font(.system(size: 21, weight: .bold, design: fontDesign))
                        .foregroundColor(.white)
                    Text(metric.title)
                        .font(.system(size: 10, weight: .semibold, design: fontDesign))
                        .foregroundColor(.white.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }

            Spacer(minLength: 12)

            branding
        }
    }

    /// Shared by both layouts so the wordmark can't drift between them.
    private var branding: some View {
        HStack(spacing: 6) {
            Image("BodyIcon01")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            // verbatim: brand wordmark, never localized — and never extracted
            // into the catalog (an empty auto-extracted "Body" entry would trip
            // the catalog-completeness guard).
            Text(verbatim: "Body")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Centered layout (gradient presets and photos)

    /// Fixed regions rather than a flowing stack: the card's height is known, so the
    /// route, the metrics, and the branding each own an absolute slot from
    /// `WorkoutShareCardGeometry` and no metric count can push the wordmark off the
    /// bottom.
    private var centeredContent: some View {
        let size = geometry.size
        return ZStack(alignment: .bottom) {
            // Trace and metrics move and resize together as one block; the branding
            // stays pinned to the card's bottom whatever the transform is.
            infoBlock
                // Explicitly card-sized so the `.position` calls inside keep resolving
                // against the full card once the block is scaled and offset.
                .frame(width: size.width, height: size.height)
                // Offset after scale, so a drag stays 1:1 with card points at any zoom.
                .scaleEffect(infoTransform.scale, anchor: geometry.blockAnchor(showsTrace: showsTrace))
                .offset(infoTransform.offset)

            branding
                .padding(.bottom, WorkoutShareCardGeometry.brandingBottomPadding)
        }
    }

    @ViewBuilder
    private var infoBlock: some View {
        ZStack {
            if layout == .routeless {
                routelessBlock
            } else if showsTrace {
                tracedBlock
            } else {
                // Traceless cards have nothing above the metrics, so the stack centers
                // in the space the branding leaves — the same fallback the classic
                // layout's metrics take.
                Group {
                    if usesMetricGrid {
                        metricGrid
                    } else {
                        centeredMetricsStack
                    }
                }
                .frame(width: geometry.size.width - 48)
                .position(x: geometry.size.width / 2, y: metricsOnlyCenterY)
            }
        }
    }

    /// Route + metrics, laid out the way this card's shape (and, on landscape, the
    /// user's arrangement) asks for.
    @ViewBuilder
    private var tracedBlock: some View {
        let metricsRect = geometry.metricsFrame
        switch geometry.centeredMode {
        case .column:
            routeRegion
            // Top-anchored rather than centered: the route above ends on a fixed
            // edge, so pinning the stack's top edge is what keeps the gap between
            // them constant no matter how many metrics the stack carries.
            VStack(spacing: 0) {
                if usesMetricGrid {
                    metricGrid
                } else {
                    centeredMetricsStack
                }
                Spacer(minLength: 0)
            }
            .frame(width: metricsRect.width, height: metricsRect.height)
            .position(x: metricsRect.midX, y: metricsRect.midY)
        case .routeOverRow:
            routeRegion
            // A short card can't afford a column under the trace, so the blocks go
            // wide in a single row sized to sit clear of the branding — or, at four
            // and five, in the rows the geometry wrapped them into.
            Group {
                if usesMetricGrid {
                    metricGrid
                } else {
                    centeredMetricsRow
                }
            }
            .frame(width: metricsRect.width, height: metricsRect.height)
            .position(x: metricsRect.midX, y: metricsRect.midY)
        case .sideBySide:
            routeRegion
            Group {
                if usesMetricGrid {
                    metricGrid
                } else {
                    centeredMetricsStack
                }
            }
            .frame(width: metricsRect.width, height: metricsRect.height)
            .position(x: metricsRect.midX, y: metricsRect.midY)
        }
    }

    /// The centered layout's trace, bottom-anchored inside its geometry rect.
    private var routeRegion: some View {
        let rect = geometry.centeredRouteRect
        return routeHero(bottomAnchored: true)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityHidden(true)
    }

    /// Glyph and metrics are one flowing block, not two absolute slots: the metric
    /// count varies from one to five here, and the pair stays visually centered
    /// together at any of them.
    ///
    /// A hidden glyph leaves the block as the card's only VoiceOver identity — no
    /// chip, no title — so the block itself carries `type.displayName` then. Shown,
    /// the glyph keeps its own label and the block adds nothing, so there's no
    /// duplicate.
    @ViewBuilder
    private var routelessBlock: some View {
        let block = VStack(spacing: 20) {
            if !iconHidden {
                typeGlyph
            }
            routelessMetrics
        }
        .frame(width: geometry.size.width - 48)
        .position(x: geometry.size.width / 2, y: routelessCenterY)

        if iconHidden {
            block.accessibilityLabel(Text(type.displayName))
        } else {
            block
        }
    }

    @ViewBuilder
    private var routelessMetrics: some View {
        if usesMetricGrid {
            metricGrid
        } else if geometry.routelessMetricsAxis == .vertical {
            centeredMetricsStack
        } else if geometry.metricRowSizes.count > 1 {
            // Three blocks won't read on one line of a 360 pt card, so they wrap into
            // rows of two — which centers the odd one under the pair.
            VStack(spacing: 20) {
                ForEach(Array(stride(from: 0, to: centeredMetrics.count, by: 2)), id: \.self) { start in
                    metricsRow(Array(centeredMetrics[start..<min(start + 2, centeredMetrics.count)]))
                }
            }
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
        } else {
            centeredMetricsRow
        }
    }

    /// Where a block with no trace above it centers. The original column keeps the
    /// card's own centre; every other shape centers in the space above the branding,
    /// which is a real constraint on a 360 pt-tall card.
    private var routelessCenterY: CGFloat {
        geometry.routelessMetricsAxis == .vertical
            ? geometry.size.height / 2
            : (geometry.size.height - Self.brandingZoneHeight) / 2
    }

    private var metricsOnlyCenterY: CGFloat {
        geometry.centeredMode == .column
            ? geometry.size.height / 2
            : (geometry.size.height - Self.brandingZoneHeight) / 2
    }

    /// Branding baseline + wordmark height + breathing room — the strip at the bottom
    /// of the card nothing else may enter.
    private static let brandingZoneHeight: CGFloat = WorkoutShareCardGeometry.brandingZoneHeight

    /// The route-less card's only identity — no chip, no title, no date — so it keeps
    /// its accessibility label rather than being decorative like the classic layout's
    /// chip (which sits beside the workout's title anyway).
    private var typeGlyph: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: 30, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
            .accessibilityLabel(Text(type.displayName))
    }

    private var centeredMetricsStack: some View {
        VStack(spacing: 20) {
            ForEach(Array(centeredMetrics.enumerated()), id: \.offset) { _, metric in
                metricBlock(metric)
            }
        }
        .multilineTextAlignment(.center)
        // The route trace's shadow, so the metrics stay legible when the block is
        // dragged into a bright photo area the scrims don't reach.
        .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
    }

    /// The same blocks the stack draws, laid out along the card's width — what a card
    /// too short for a column uses instead.
    private var centeredMetricsRow: some View {
        metricsRow(centeredMetrics)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
    }

    private func metricsRow(_ items: [WorkoutShareMetric]) -> some View {
        HStack(spacing: 24) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, metric in
                // A row splits the card's width between up to three 40 pt values, so a
                // long one (a pace, "412 kcal") needs to shrink further than the
                // stack's floor allows before it would rather truncate.
                metricBlock(metric, minimumScale: 0.45)
            }
        }
    }

    /// One to three blocks keep the stack or the single row they have always had; only
    /// a four- or five-metric pick takes the wrapped grid.
    private var usesMetricGrid: Bool {
        centeredMetrics.count > WorkoutShareMetricSelection.defaultCount
    }

    /// The blocks in the rows `WorkoutShareCardGeometry.metricRowSizes` wrapped them
    /// into — and, on the short cards, in the compact type that keeps those rows clear
    /// of the branding.
    private var metricGrid: some View {
        let style = geometry.metricBlockStyle
        let valueSize = gridValueSize
        return VStack(spacing: style.rowGap) {
            ForEach(Array(metricGridRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 24) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, metric in
                        metricBlock(metric, style: style, valueSize: valueSize, minimumScale: 0.45)
                            // Equal columns, and a row height that stays the geometry's
                            // whatever size the values landed at.
                            .frame(maxWidth: .infinity)
                            .frame(height: style.rowHeight)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
    }

    /// One value size for the whole grid, not one per block: `minimumScaleFactor`
    /// shrinks each text on its own, so a three-wide row would land smaller than the
    /// two-wide row under it. The widest value is measured against the narrowest
    /// column, and every block takes that size (never above the style's own, never
    /// below its 0.45 floor — the per-text scale stays as the backstop).
    private var gridValueSize: CGFloat {
        let style = geometry.metricBlockStyle
        let columns = CGFloat(geometry.metricRowSizes.max() ?? 1)
        let rowWidth = layout == .centered && showsTrace ? geometry.metricsFrame.width : geometry.size.width - 48
        let columnWidth = (rowWidth - 24 * (columns - 1)) / columns
        let widest = centeredMetrics
            .map { Self.measuredWidth($0.value, size: style.valueSize, design: fontDesign) }
            .max() ?? 0
        guard widest > columnWidth, widest > 0 else { return style.valueSize }
        return max(style.valueSize * 0.45, style.valueSize * columnWidth / widest)
    }

    /// Width of `text` in the card's bold value face — the same system design the
    /// SwiftUI font uses, so the fit is measured in the face that's drawn.
    private static func measuredWidth(_ text: String, size: CGFloat, design: Font.Design) -> CGFloat {
        let systemDesign: UIFontDescriptor.SystemDesign
        switch design {
        case .rounded: systemDesign = .rounded
        case .serif: systemDesign = .serif
        case .monospaced: systemDesign = .monospaced
        default: systemDesign = .default
        }
        var descriptor = UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor
        if let designed = descriptor.withDesign(systemDesign) { descriptor = designed }
        let font = UIFont(descriptor: descriptor, size: size)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private var metricGridRows: [[WorkoutShareMetric]] {
        var rows: [[WorkoutShareMetric]] = []
        var start = 0
        for size in geometry.metricRowSizes where start < centeredMetrics.count {
            let end = min(start + size, centeredMetrics.count)
            rows.append(Array(centeredMetrics[start..<end]))
            start = end
        }
        return rows
    }

    private func metricBlock(
        _ metric: WorkoutShareMetric,
        style: WorkoutShareCardGeometry.MetricBlockStyle = .regular,
        valueSize: CGFloat? = nil,
        minimumScale: CGFloat = 0.6
    ) -> some View {
        VStack(spacing: 2) {
            Text(metric.title)
                .font(.system(size: style.labelSize, weight: .semibold, design: fontDesign))
                .foregroundColor(.white.opacity(0.7))
            Text(metric.value)
                .font(.system(size: valueSize ?? style.valueSize, weight: .bold, design: fontDesign))
                .foregroundColor(.white)
        }
        .lineLimit(1)
        .minimumScaleFactor(minimumScale)
    }
}

/// The route trace both share exports paint: the flat polyline, or the oblique
/// elevation ribbon in 3D, drawn through the centered, inset rect of whatever frame
/// it's given so the stroke never clips. No start/end markers — only the map
/// background's composited route carries those.
///
/// Its own view rather than a method on the card, because the long image draws the
/// same trace from a completely different layout; two Canvases with the same
/// projection maths in them would be one bug fix away from disagreeing.
struct WorkoutShareRouteTrace: View {
    /// Already normalized to the unit square by `WorkoutShareRouteProjection`.
    let routePoints: [CGPoint]?
    /// Drawn instead of the flat polyline when non-nil — already gated on the resolved
    /// dimension by the caller.
    let ribbon: WorkoutRoute3DProjection.Projected3D?
    let routeColor: Color
    /// Translates the finished drawing so its lowest point lands on the rect's bottom
    /// edge, so the gap to whatever sits below is the same for a tall route and a wide
    /// one (and the 3D ribbon's lifted line rises into free space). The classic layout
    /// keeps the trace centered on the map's own geometry instead.
    let bottomAnchored: Bool

    var body: some View {
        Canvas { context, size in
            let inset = WorkoutShareCardGeometry.routeInset
            let rect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )

            if let ribbon {
                let top = Self.mapped(ribbon.top, in: rect)
                let base = Self.mapped(ribbon.base, in: rect)
                // The ground trace is the ribbon's lowest line by construction, so it
                // alone decides the anchor.
                let shift = bottomAnchored ? Self.bottomAnchorShift(for: base, in: rect) : 0
                BodyWorkoutRoute3DHero.drawRibbon(
                    top: Self.shifted(top, by: shift),
                    base: Self.shifted(base, by: shift),
                    tint: routeColor,
                    in: &context
                )
                return
            }

            guard let routePoints, routePoints.count >= 2 else { return }
            let mapped = Self.mapped(routePoints, in: rect)
            let shift = bottomAnchored ? Self.bottomAnchorShift(for: mapped, in: rect) : 0

            var path = Path()
            path.addLines(Self.shifted(mapped, by: shift))

            var strokeContext = context
            strokeContext.addFilter(.shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5))
            strokeContext.stroke(
                path,
                with: .color(routeColor),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Projection space (unit square for the flat trace, the ribbon's own camera space
    /// for 3D) into the drawing rect. The rect is square, so one scale serves both axes
    /// and neither drawing is distorted.
    private static func mapped(_ points: [CGPoint], in rect: CGRect) -> [CGPoint] {
        points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
    }

    private static func shifted(_ points: [CGPoint], by shift: CGFloat) -> [CGPoint] {
        shift == 0 ? points : points.map { CGPoint(x: $0.x, y: $0.y + shift) }
    }

    private static func bottomAnchorShift(for points: [CGPoint], in rect: CGRect) -> CGFloat {
        guard let lowest = points.map(\.y).max() else { return 0 }
        return rect.maxY - lowest
    }
}

/// Shared preview fixture: an 8.2 km run with a looping route.
private func previewCard(
    layout: WorkoutShareCardLayout,
    withRoute: Bool,
    infoTransform: WorkoutShareInfoTransform = .identity,
    dimension: WorkoutShareRouteDimension = .twoD,
    aspectRatio: WorkoutShareAspectRatio = .portrait9x16,
    arrangement: WorkoutShareLandscapeArrangement = .stacked
) -> some View {
    let workout = WorkoutSummary(
        type: .running,
        startDate: Date(timeIntervalSince1970: 1_700_000_000),
        duration: 1_920,
        activeEnergyKilocalories: 412,
        distanceMeters: 8_200,
        averageHeartRateBeatsPerMinute: 154
    )
    let presentation = WorkoutDetailPresentation(workout: workout, locale: Locale(identifier: "en_US"))
    let coordinates: [RouteCoordinate] = (0..<40).map { index in
        let t = Double(index) / 39
        return RouteCoordinate(
            latitude: 37.3230 + 0.010 * sin(t * .pi * 2),
            longitude: -122.0322 + 0.012 * t,
            speed: 3,
            altitude: 40 + 160 * t
        )
    }
    let isRouteless = layout == .routeless
    return BodyWorkoutShareCardView(
        presentation: presentation,
        // The route-less card never draws the classic row, and takes its own,
        // longer selection for the block stack — the sheet feeds it the same way.
        metrics: isRouteless ? [] : WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type),
        centeredMetrics: isRouteless
            ? WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: workout.type)
            : WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: workout.type),
        routePoints: withRoute ? WorkoutShareRouteProjection.normalizedPoints(for: coordinates) : nil,
        route3D: withRoute ? WorkoutRoute3DProjection.projected(for: coordinates) : nil,
        dimension: dimension,
        iconHidden: false,
        locality: "Cupertino",
        type: .running,
        background: .preset(.midnight),
        layout: layout,
        aspectRatio: aspectRatio,
        arrangement: arrangement,
        infoTransform: infoTransform,
        photoTransform: .identity,
        fontDesign: .rounded,
        routeColor: BodyWorkoutShareCardView.defaultRouteColor
    )
    .frame(width: aspectRatio.cardSize.width, height: aspectRatio.cardSize.height)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}

#Preview("Centered - route") {
    previewCard(layout: .centered, withRoute: true)
}

#Preview("Centered - 3D") {
    previewCard(layout: .centered, withRoute: true, dimension: .threeD)
}

#Preview("Centered - moved") {
    previewCard(
        layout: .centered,
        withRoute: true,
        infoTransform: WorkoutShareInfoTransform(offset: CGSize(width: 60, height: 120), scale: 0.8)
    )
}

#Preview("Centered - no route") {
    previewCard(layout: .centered, withRoute: false)
}

#Preview("Routeless") {
    previewCard(layout: .routeless, withRoute: false)
}

#Preview("Classic") {
    previewCard(layout: .classic, withRoute: true)
}

#Preview("16:9 stacked") {
    previewCard(layout: .centered, withRoute: true, aspectRatio: .landscape16x9, arrangement: .stacked)
}

#Preview("16:9 side by side") {
    previewCard(layout: .centered, withRoute: true, aspectRatio: .landscape16x9, arrangement: .sideBySide)
}

#Preview("1:1") {
    previewCard(layout: .centered, withRoute: true, aspectRatio: .square)
}

#Preview("3:4") {
    previewCard(layout: .centered, withRoute: true, aspectRatio: .portrait3x4)
}

#Preview("16:9 routeless") {
    previewCard(layout: .routeless, withRoute: false, aspectRatio: .landscape16x9)
}
