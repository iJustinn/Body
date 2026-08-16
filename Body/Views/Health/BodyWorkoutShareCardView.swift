//
//  BodyWorkoutShareCardView.swift
//  Body
//
//  The 360×640 pt share card, exported at `ImageRenderer.scale = 3` → 1080×1920 px.
//  Purely value-driven and environment-independent: every color, size, and weight
//  is explicit so the rendered image looks identical no matter what environment
//  `ImageRenderer` runs it under. Three layouts: `.classic` (map background only)
//  mirrors the detail page — identity left, big distance + duration right, route
//  trace centered, metrics row along the bottom; `.centered` (gradient presets and
//  photos) drops the header for a column of label-over-value blocks under the trace;
//  `.routeless` (a workout with no GPS route) has no trace to show, so the workout
//  type's symbol stands in as the card's only identity above that same column.
//  On photo backgrounds the centered layout's info block (trace + stack, never the
//  pinned branding) is repositionable and resizable: the placement arrives as an
//  `infoTransform` the sheet's gestures drive, and is `.identity` everywhere else.
//

import SwiftUI

/// What fills the card behind the content. `.map` is a pre-composited route-map
/// snapshot, so the card skips its own Canvas trace for that case.
enum WorkoutShareCardBackground {
    case preset(BodyWorkoutSharePreset)
    case photo(UIImage)
    case map(UIImage)
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
    let locality: String?
    let type: BodyWorkoutType
    let background: WorkoutShareCardBackground
    let layout: WorkoutShareCardLayout
    /// Where the centered layout's info block sits; `.identity` is its default slot.
    /// The classic layout ignores it.
    let infoTransform: WorkoutShareInfoTransform

    private static let cardSize = CGSize(width: 360, height: 640)

    /// The centered layout's route region, in card points. Internal so the render test
    /// derives its pixel sample area from the same numbers the card draws with.
    static let centeredRouteSize: CGFloat = 260
    static let centeredRouteCenter = CGPoint(x: 180, y: 170)

    /// Where the centered metric stack's midline sits when a trace is shown: below the
    /// route region (which ends at y 300) and clear of the pinned branding.
    private static let centeredMetricsCenterY: CGFloat = 440

    /// #0128F4 — the card's own route trace only; the map background's polyline keeps
    /// its pace coloring and the marker rings stay white.
    private static let routeColor = Color(red: 1 / 255, green: 40 / 255, blue: 244 / 255)

    /// `.routeless` never traces, whatever it's handed: making that a property of the
    /// layout (rather than of the caller passing `routePoints: nil`) also fixes
    /// `blockAnchor` at `.center`, which is the placement the glyph + stack want.
    private var showsTrace: Bool {
        if case .map = background { return false }
        return layout != .routeless && routePoints != nil
    }

    var body: some View {
        ZStack {
            backgroundLayer
            scrims
            switch layout {
            case .classic:
                if showsTrace {
                    // Pinned to the same geometry as the map background's route: a
                    // 300×300 pt drawing rect (2× the scrims' clear band) centered at
                    // y 375, so the trace sits identically on every background. The
                    // square rect keeps the projection's aspect ratio undistorted;
                    // the 324 pt frame leaves the 12 pt inset for the stroke.
                    routeHero
                        .frame(width: 324, height: 324)
                        .position(x: Self.cardSize.width / 2, y: 375)
                }
                content
            case .centered, .routeless:
                centeredContent
            }
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipped()
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch background {
        case .preset(let preset):
            preset.gradient(tint: type.color)
        case .photo(let image), .map(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                .clipped()
        }
    }

    /// Unconditional top + bottom scrims so white text stays legible over any photo
    /// or map tiles, including a near-white tint. Map tiles carry bright labels and
    /// roads right behind the text, so they get taller, darker shades.
    private var scrims: some View {
        let isMap: Bool
        if case .map = background { isMap = true } else { isMap = false }

        return VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(isMap ? 0.85 : 0.45), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: isMap ? 280 : 170)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(isMap ? 0.85 : 0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: isMap ? 210 : 160)
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
        .padding(.bottom, 26)
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
                Text(presentation.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let locality {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(locality)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.7))
                }

                Text("\(presentation.dateTitle) - \(presentation.timeRangeText)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var headerNumbers: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let heroValue = presentation.heroDistanceValue, let heroUnit = presentation.heroDistanceUnit {
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(heroValue)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(heroUnit)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Text("Distance")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            VStack(alignment: .trailing, spacing: 1) {
                Text(presentation.durationClockText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Duration")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Route trace

    /// SwiftUI `Canvas` polyline of the route in `routeColor`, through the centered,
    /// inset rect so the ~5 pt stroke never clips. No start/end markers — only the
    /// map background's composited route carries those.
    private var routeHero: some View {
        Canvas { context, size in
            guard let routePoints, routePoints.count >= 2 else { return }

            let inset: CGFloat = 12
            let rect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )
            let mapped = routePoints.map { point in
                CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            }

            var path = Path()
            path.move(to: mapped[0])
            for point in mapped.dropFirst() {
                path.addLine(to: point)
            }

            var strokeContext = context
            strokeContext.addFilter(.shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5))
            strokeContext.stroke(
                path,
                with: .color(Self.routeColor),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Bottom bar (metrics leading, branding trailing)

    private var bottomBar: some View {
        HStack(alignment: .bottom, spacing: 24) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.value)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(metric.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
            // verbatim: brand wordmark, never localized — and never extracted
            // into the catalog (an empty auto-extracted "Body" entry would trip
            // the catalog-completeness guard).
            Text(verbatim: "Body")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Centered layout (gradient presets)

    /// Fixed regions rather than a flowing stack: the card is exactly 640 pt, so the
    /// route, the metric stack, and the branding each own an absolute slot and no
    /// metric count can push the wordmark off the bottom.
    private var centeredContent: some View {
        ZStack(alignment: .bottom) {
            // Trace and stack move and resize together as one block; the branding
            // stays pinned to the card's bottom whatever the transform is.
            ZStack {
                if layout == .routeless {
                    // Glyph and stack are one flowing block, not two absolute slots:
                    // the metric count varies from one to four here, and the pair
                    // stays visually centered together at any of them.
                    VStack(spacing: 28) {
                        typeGlyph
                        centeredMetricsStack
                    }
                    .frame(width: Self.cardSize.width - 48)
                    .position(x: Self.cardSize.width / 2, y: Self.cardSize.height / 2)
                } else {
                    if showsTrace {
                        routeHero
                            .frame(width: Self.centeredRouteSize, height: Self.centeredRouteSize)
                            .position(Self.centeredRouteCenter)
                            .accessibilityHidden(true)
                    }

                    centeredMetricsStack
                        .frame(width: Self.cardSize.width - 48)
                        // Traceless cards have nothing above the stack, so it centers in the
                        // whole card — the same fallback the classic layout's metrics take.
                        .position(
                            x: Self.cardSize.width / 2,
                            y: showsTrace ? Self.centeredMetricsCenterY : Self.cardSize.height / 2
                        )
                }
            }
            // Explicitly card-sized so the `.position` calls above keep resolving
            // against the full card once the block is scaled and offset.
            .frame(width: Self.cardSize.width, height: Self.cardSize.height)
            // Offset after scale, so a drag stays 1:1 with card points at any zoom.
            .scaleEffect(infoTransform.scale, anchor: blockAnchor)
            .offset(infoTransform.offset)

            branding
                .padding(.bottom, 26)
        }
    }

    /// The block's own visual center — midway between the route region and the metric
    /// stack — rather than the card's. Pinching around the card center would push the
    /// trace off the top, since the block sits above the midline when a trace is shown.
    private var blockAnchor: UnitPoint {
        guard showsTrace else { return .center }
        let blockCenterY = (Self.centeredRouteCenter.y + Self.centeredMetricsCenterY) / 2
        return UnitPoint(x: 0.5, y: blockCenterY / Self.cardSize.height)
    }

    /// The route-less card's only identity — no chip, no title, no date — so it keeps
    /// its accessibility label rather than being decorative like the classic layout's
    /// chip (which sits beside the workout's title anyway).
    private var typeGlyph: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: 56, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
            .accessibilityLabel(Text(type.displayName))
    }

    private var centeredMetricsStack: some View {
        VStack(spacing: 20) {
            ForEach(Array(centeredMetrics.enumerated()), id: \.offset) { _, metric in
                VStack(spacing: 2) {
                    Text(metric.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    Text(metric.value)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        .multilineTextAlignment(.center)
        // The route trace's shadow, so the stack stays legible when the block is
        // dragged into a bright photo area the scrims don't reach.
        .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 1.5)
    }
}

/// Shared preview fixture: an 8.2 km run with a looping route.
private func previewCard(
    layout: WorkoutShareCardLayout,
    withRoute: Bool,
    infoTransform: WorkoutShareInfoTransform = .identity
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
            speed: 3
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
        locality: "Cupertino",
        type: .running,
        background: .preset(.midnight),
        layout: layout,
        infoTransform: infoTransform
    )
    .frame(width: 360, height: 640)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}

#Preview("Centered - route") {
    previewCard(layout: .centered, withRoute: true)
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
