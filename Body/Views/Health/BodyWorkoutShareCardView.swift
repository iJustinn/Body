//
//  BodyWorkoutShareCardView.swift
//  Body
//
//  The 360×640 pt share card, exported at `ImageRenderer.scale = 3` → 1080×1920 px.
//  Purely value-driven and environment-independent: every color, size, and weight
//  is explicit so the rendered image looks identical no matter what environment
//  `ImageRenderer` runs it under. Header mirrors the detail page arrangement
//  (identity left, big distance + duration right); the route trace is the center
//  hero except on a map background, where the map itself carries the route.
//

import SwiftUI

/// What fills the card behind the content. `.map` is a pre-composited route-map
/// snapshot, so the card skips its own Canvas trace for that case.
enum WorkoutShareCardBackground {
    case preset(BodyWorkoutSharePreset)
    case photo(UIImage)
    case map(UIImage)
}

struct BodyWorkoutShareCardView: View {
    let presentation: WorkoutDetailPresentation
    let metrics: [WorkoutShareMetric]
    /// Already normalized to the unit square by `WorkoutShareRouteProjection`. `nil`
    /// collapses the trace into a metrics-only card.
    let routePoints: [CGPoint]?
    let locality: String?
    let type: BodyWorkoutType
    let background: WorkoutShareCardBackground

    private static let cardSize = CGSize(width: 360, height: 640)

    private var showsTrace: Bool {
        if case .map = background { return false }
        return routePoints != nil
    }

    var body: some View {
        ZStack {
            backgroundLayer
            scrims
            if showsTrace {
                // Pinned to the same geometry as the map background's route: a
                // 300×300 pt drawing rect (2× the scrims' clear band) centered at
                // y 375, so the trace sits identically on every background. The
                // square rect keeps the projection's aspect ratio undistorted;
                // the 324 pt frame leaves the 12 pt inset for stroke + markers.
                routeHero
                    .frame(width: 324, height: 324)
                    .position(x: Self.cardSize.width / 2, y: 375)
            }
            content
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

    /// SwiftUI `Canvas` polyline of the route through the centered, inset rect so the
    /// ~5 pt stroke and endpoint dots never clip. Green start / red end ringed dots
    /// mirror `BodyWorkoutRouteMapHero.drawMarker` proportions.
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
                with: .color(.white),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

            drawMarker(at: mapped[0], color: Color(.systemGreen), in: context)
            drawMarker(at: mapped[mapped.count - 1], color: Color(.systemRed), in: context)
        }
    }

    private func drawMarker(at point: CGPoint, color: Color, in context: GraphicsContext) {
        let ringRadius: CGFloat = 7.5
        let dotRadius: CGFloat = 5
        let ring = CGRect(
            x: point.x - ringRadius,
            y: point.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        )
        let dot = CGRect(
            x: point.x - dotRadius,
            y: point.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        context.fill(Path(ellipseIn: ring), with: .color(.white))
        context.fill(Path(ellipseIn: dot), with: .color(color))
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

            HStack(spacing: 6) {
                Image("BodyIcon01")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                // verbatim: brand wordmark, never localized — and never extracted
                // into the catalog (an empty auto-extracted "Body" entry would trip
                // the catalog-completeness guard).
                Text(verbatim: "Body")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

#Preview {
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
    return BodyWorkoutShareCardView(
        presentation: presentation,
        metrics: WorkoutShareMetricsBuilder.metrics(for: presentation, type: workout.type),
        routePoints: WorkoutShareRouteProjection.normalizedPoints(for: coordinates),
        locality: "Cupertino",
        type: .running,
        background: .preset(.midnight)
    )
    .frame(width: 360, height: 640)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
}
