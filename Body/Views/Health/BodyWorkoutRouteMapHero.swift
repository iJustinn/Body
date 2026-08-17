//
//  BodyWorkoutRouteMapHero.swift
//  Body
//
//  Full-bleed static map hero at the top of the workout detail sheet. Renders a
//  one-shot `MKMapSnapshotter` image with the route polyline and start/end dots
//  drawn in — a true static image (no live `Map`), so it never fights the
//  sheet's scroll and carries no tile/gesture lifecycle. The city label overlays
//  the bottom-leading corner over a short scrim.
//
//  `BodyWorkoutRoutePlainHero` is the map-free alternative (Route Style › Plain):
//  the same route stroked in the workout's tint, with no tiles, pace shading, or
//  end markers. `BodyWorkoutRoute3DHero` (Route Style › 3D) draws that same trace
//  as an oblique elevation ribbon, falling back to the plain hero when the route
//  carries no altitude. Both map-free heroes frame the route through the shared
//  `BodyWorkoutRouteHeroFit`.
//

import SwiftUI
import MapKit
import UIKit

/// Wall-clock progressive reveal of a route hero: how much of the trace is drawn, 0 → 1.
/// Measured from an `epoch` each hero captures for itself rather than from a shared
/// reference date, so a hero always starts at the start of the line however late it
/// appears — the same reason `BodyPixelGridLoader` is driven this way. The map-free
/// heroes time from insertion, since they are inserted the moment the fixes resolve; the
/// map hero times from its snapshot instead, which is what its draw waits on.
enum BodyWorkoutRouteReveal {
    /// Long enough to read as drawing, short enough not to hold the page back.
    static let duration: TimeInterval = 1.1
    /// Beat before the line starts, keeping the draw clear of the workouts list's zoom
    /// navigation transition. Measured from the hero's own epoch, so it does not by
    /// itself clear the band's reservation slide.
    static let startDelay: TimeInterval = 0.2
    /// Slack past the end before a hero tears its `TimelineView` down. The teardown is
    /// driven by an independent sleep, which can otherwise fire before the timeline has
    /// rendered exactly 1 and leave a visible jump to the static drawing.
    static let settleMargin: TimeInterval = 0.05

    /// Total wall-clock life of the animation, including both cushions.
    static var totalDuration: TimeInterval { startDelay + duration + settleMargin }

    /// Cubic ease-out — the head leaves the start quickly and settles onto the finish, so
    /// a long route doesn't crawl through its last third. `CGFloat` rather than `Double`
    /// because it feeds `Path.trimmedPath(from:to:)` directly.
    static func fraction(at elapsed: TimeInterval) -> CGFloat {
        let active = elapsed - startDelay
        guard active > 0 else { return 0 }
        guard active < duration else { return 1 }
        let linear = active / duration
        let remaining = 1 - linear
        return CGFloat(1 - remaining * remaining * remaining)
    }

    /// `fraction` for a hero that started drawing at `epoch`, evaluated at `date`.
    static func fraction(epoch: Date, date: Date) -> CGFloat {
        fraction(at: date.timeIntervalSince(epoch))
    }
}

struct BodyWorkoutRouteMapHero: View {
    let route: WorkoutRoute
    let tint: Color
    /// Y the route's vertical center should land on, in hero space — which is screen
    /// space too, since the hero ignores the top safe area.
    let targetCenterY: CGFloat
    /// Top safe-area inset: the route must stay below the status bar / Dynamic Island
    /// even though the hero itself extends under them.
    let topInset: CGFloat
    /// Draws the route in over the map tiles when the hero appears. See
    /// `BodyWorkoutRoutePlainHero.drawsReveal` for why this is `var`, not `let`.
    var drawsReveal: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The finished hero: map tiles with the pace-colored route and its markers baked in.
    @State private var snapshot: UIImage?
    /// The same render with nothing drawn on it, shown under the reveal so the line can
    /// draw itself over real tiles instead of over black.
    @State private var tiles: UIImage?
    /// The route in hero space, taken from the snapshot's own `point(for:)` rather than
    /// re-derived from the requested `mapRect`. MapKit only promises to honor that rect
    /// "as closely as possible", so a hand-rolled projection could leave the drawn line
    /// visibly beside the baked one during the crossfade; going through the snapshot
    /// makes them identical by construction.
    @State private var routePoints: [CGPoint]?
    /// When the draw actually began. Unlike the map-free heroes — which are inserted at
    /// the moment their route resolves and can time from insertion — this one has to wait
    /// for the snapshotter, so timing from insertion would burn most or all of the
    /// animation before there was anything to draw.
    @State private var revealStartedAt: Date?
    @State private var revealFinished = false

    private var isRevealing: Bool { drawsReveal && !reduceMotion && !revealFinished }

    /// Whether the finished, route-baked image is the one on screen. Both the tiles and
    /// the composited image animate against this single value: keying the fade on
    /// `snapshot != nil` alone would fire while the composite was still hidden behind the
    /// reveal, and the later handover would then pop with no animation at all.
    private var showsComposited: Bool { snapshot != nil && !isRevealing }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                mapLayer(size: proxy.size)
                // Subtle top scrim keeps the sheet's drag indicator legible over
                // light map tiles.
                LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0)], startPoint: .top, endPoint: .center)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frame(height: 64)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .mask {
                // Dissolve the map's lower edge into the pure-black background so it
                // melts into the page rather than ending on a line. A cubic alpha
                // ramp (fully opaque at the top with zero slope, fading to clear at
                // the bottom) has no onset seam, and because it reveals the uniform
                // black background — not darkened map detail — any residual
                // softness is imperceptible.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black.opacity(0.909), location: 0.45),
                        .init(color: .black.opacity(0.762), location: 0.62),
                        .init(color: .black.opacity(0.578), location: 0.75),
                        .init(color: .black.opacity(0.364), location: 0.86),
                        .init(color: .black.opacity(0.143), location: 0.95),
                        .init(color: .black.opacity(0.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .task(id: SnapshotInput(width: proxy.size.width.rounded(), height: proxy.size.height.rounded(), centerY: targetCenterY.rounded(), topInset: topInset.rounded(), isDark: colorScheme == .dark)) {
                await renderSnapshot(size: proxy.size)
            }
        }
        .clipped()
    }

    private func mapLayer(size: CGSize) -> some View {
        // Fade the map in once the snapshot finishes rendering (its ~0.5–1s
        // natural load time), instead of popping in instantly. While the reveal runs,
        // the bare tiles stand in and the line draws itself over them; the composited
        // image — same tiles, pace-colored route and markers baked in — crossfades over
        // the top at the end, landing on identical pixels.
        ZStack {
            image(tiles, size: size)
                .opacity(tiles == nil ? 0 : 1)

            image(snapshot, size: size)
                .opacity(showsComposited ? 1 : 0)

            if isRevealing, let routePoints, let revealStartedAt {
                TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                    revealOverlay(
                        points: routePoints,
                        fraction: BodyWorkoutRouteReveal.fraction(epoch: revealStartedAt, date: timeline.date)
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: tiles != nil)
        .animation(.easeInOut(duration: 0.5), value: showsComposited)
        .task(id: revealStartedAt) {
            guard revealStartedAt != nil else { return }
            try? await Task.sleep(for: .seconds(BodyWorkoutRouteReveal.totalDuration))
            revealFinished = true
            // The composited image covers the bare tiles from here on, and each is a
            // full-size render — don't hold both for the life of the page.
            tiles = nil
        }
    }

    private func image(_ image: UIImage?, size: CGSize) -> some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
    }

    /// The route drawn up to `fraction` of its length, in a flat tint — the pace coloring
    /// belongs to the composited snapshot that replaces this.
    private func revealOverlay(points: [CGPoint], fraction: CGFloat) -> some View {
        Canvas { context, _ in
            guard points.count >= 2 else { return }
            var path = Path()
            path.addLines(points)
            context.stroke(
                fraction >= 1 ? path : path.trimmedPath(from: 0, to: fraction),
                with: .color(tint),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }
        .allowsHitTesting(false)
    }

    @MainActor
    private func renderSnapshot(size: CGSize) async {
        guard size.width > 0, size.height > 0, route.coordinates.count >= 2 else {
            return
        }

        let coordinates = route.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        let options = MKMapSnapshotter.Options()
        options.mapRect = Self.mapRect(for: coordinates, size: size, targetCenterY: targetCenterY, topInset: topInset)
        options.size = size
        options.scale = displayScale
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

        guard let result = try? await MKMapSnapshotter(options: options).start() else {
            return
        }

        // Publish the bare tiles and the snapshot's own coordinate mapping first: the
        // reveal draws its line over real map detail, in exactly the place the baked
        // route will occupy, without re-deriving the projection. The clock starts here
        // rather than at insertion — the snapshotter is what the draw was waiting on.
        if drawsReveal, !reduceMotion, revealStartedAt == nil {
            routePoints = coordinates.map(result.point(for:))
            tiles = result.image
            revealStartedAt = Date()
        }

        let image = Self.draw(route: route.coordinates, on: result, fallbackTint: UIColor(tint))
        // The view-level `.animation(value:)` on `mapLayer` drives the fade-in.
        snapshot = image
    }

    /// The old region framing's 0.0016° minimum span, restated as a map-point width
    /// (the projection's x axis is linear in longitude) so a short loop isn't
    /// over-zoomed.
    private static let minimumSpanMapPoints = MKMapSize.world.width * 0.0016 / 360

    /// Mercator rect bounding the whole route, padded horizontally, aspect-matched to
    /// the snapshot size, and offset so the route's vertical center lands on
    /// `targetCenterY`. Built in map points rather than as an `MKCoordinateRegion`:
    /// the region conversion re-symmetrizes the rect in degrees around its center
    /// latitude, which away from the equator both slides the route off the target
    /// fraction and breaks the aspect match, re-triggering the snapshotter's own fit.
    private static func mapRect(
        for coordinates: [CLLocationCoordinate2D],
        size: CGSize,
        targetCenterY: CGFloat,
        topInset: CGFloat
    ) -> MKMapRect {
        let first = MKMapPoint(coordinates[0])
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        var width = max(maxX - minX, minimumSpanMapPoints) * 1.5
        var height = width * Double(size.height / size.width)

        // Fraction of the rect the route's center maps to, kept off the edges so a
        // stray measurement can't collapse the frame.
        let fraction = min(max(Double(targetCenterY / size.height), 0.05), 0.95)
        // Centering leaves the smaller of the two sides — down to the safe area
        // above, to the hero's bottom edge below — usable on both halves of the
        // route; zoom out (uniformly, so the aspect holds) until the route uses at
        // most 80% of it, keeping the line clear of the Dynamic Island.
        let usablePixels = 2 * min(targetCenterY - topInset, size.height - targetCenterY)
        let usableHeight = height * Double(usablePixels / size.height) * 0.8
        if usableHeight > 0, maxY - minY > usableHeight {
            let zoomOut = (maxY - minY) / usableHeight
            width *= zoomOut
            height *= zoomOut
        }

        return MKMapRect(
            x: (minX + maxX) / 2 - width / 2,
            y: (minY + maxY) / 2 - height * fraction,
            width: width,
            height: height
        )
    }

    /// Draws the route onto the map snapshot — colored by pace (red slow → green
    /// fast) when the fixes carry enough speed spread, otherwise a single tint —
    /// plus start (green) / end (red) markers. Returns the composited image.
    /// Internal so the share card's map background reuses the same compositing.
    ///
    /// - Parameter lift: Unit lift per fix (`WorkoutRoute3DProjection.liftUnits`), which
    ///   raises the route off the roads as a 2.5D ribbon: the ground trace stays on the
    ///   map, the coloured line stands straight up above it. `nil` — or a count that
    ///   doesn't match the route — draws the flat route.
    static func draw(
        route: [RouteCoordinate],
        on snapshot: MKMapSnapshotter.Snapshot,
        fallbackTint: UIColor,
        lift: [Double]? = nil
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size, format: format)

        return renderer.image { context in
            snapshot.image.draw(at: .zero)

            let points = route.map {
                snapshot.point(for: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            guard let first = points.first, let last = points.last, points.count >= 2 else {
                return
            }

            let cgContext = context.cgContext
            cgContext.setLineWidth(4)
            cgContext.setLineJoin(.round)
            cgContext.setLineCap(.round)

            if let lift, lift.count == points.count {
                drawRibbon(base: points, lift: lift, route: route, fallbackTint: fallbackTint, in: cgContext)
                return
            }

            if let bounds = WorkoutRoutePaceColoring.speedColorBounds(for: route) {
                // One short stroke per segment so the line shades smoothly by pace.
                for index in 0..<(points.count - 1) {
                    let segmentSpeed = (route[index].speed + route[index + 1].speed) / 2
                    cgContext.setStrokeColor(WorkoutRoutePaceColoring.color(forSpeed: segmentSpeed, bounds: bounds).cgColor)
                    cgContext.move(to: points[index])
                    cgContext.addLine(to: points[index + 1])
                    cgContext.strokePath()
                }
            } else {
                cgContext.setStrokeColor(fallbackTint.cgColor)
                cgContext.move(to: first)
                for point in points.dropFirst() {
                    cgContext.addLine(to: point)
                }
                cgContext.strokePath()
            }

            drawMarker(at: first, color: .systemGreen, in: cgContext)
            drawMarker(at: last, color: .systemRed, in: cgContext)
        }
    }

    /// The 2.5D ribbon over the map: the route's own snapshot points are the ground,
    /// and each one's lifted twin stands `lift × span` points straight above it.
    ///
    /// `span` is the ground trace's own bounding box in snapshot points, matching the
    /// unit the projection's lift is expressed in (fractions of the route's ground
    /// span). Mercator's north-south stretch is treated as negligible at the scale a
    /// single workout's route covers, the same approximation the route projection makes.
    private static func drawRibbon(
        base: [CGPoint],
        lift: [Double],
        route: [RouteCoordinate],
        fallbackTint: UIColor,
        in context: CGContext
    ) {
        let xs = base.map(\.x)
        let ys = base.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return
        }
        let span = max(maxX - minX, maxY - minY)
        let top = base.enumerated().map { index, point in
            CGPoint(x: point.x, y: point.y - CGFloat(lift[index]) * span)
        }

        context.setLineWidth(2)
        context.setStrokeColor(fallbackTint.withAlphaComponent(wallGroundOpacity).cgColor)
        context.move(to: base[0])
        for point in base.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        let wallGradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                fallbackTint.withAlphaComponent(wallTopOpacity).cgColor,
                fallbackTint.withAlphaComponent(wallBottomOpacity).cgColor
            ] as CFArray,
            locations: [0, 1]
        )
        let speedBounds = WorkoutRoutePaceColoring.speedColorBounds(for: route)
        context.setLineWidth(4)

        // Painter's algorithm, as the 3D hero does it: back to front by ground depth,
        // each wall immediately followed by its own top-line segment.
        let order = (0..<(base.count - 1)).sorted { base[$0].y + base[$0 + 1].y < base[$1].y + base[$1 + 1].y }
        for index in order {
            if let wallGradient {
                context.saveGState()
                context.beginPath()
                context.addLines(between: [top[index], top[index + 1], base[index + 1], base[index], top[index]])
                context.closePath()
                context.clip()
                context.drawLinearGradient(
                    wallGradient,
                    start: CGPoint(x: (top[index].x + top[index + 1].x) / 2, y: (top[index].y + top[index + 1].y) / 2),
                    end: CGPoint(x: (base[index].x + base[index + 1].x) / 2, y: (base[index].y + base[index + 1].y) / 2),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
                context.restoreGState()
            }

            if let speedBounds {
                let segmentSpeed = (route[index].speed + route[index + 1].speed) / 2
                context.setStrokeColor(WorkoutRoutePaceColoring.color(forSpeed: segmentSpeed, bounds: speedBounds).cgColor)
            } else {
                context.setStrokeColor(fallbackTint.cgColor)
            }
            context.move(to: top[index])
            context.addLine(to: top[index + 1])
            context.strokePath()
        }

        // The markers belong to the lifted line, which is the route the eye follows.
        drawMarker(at: top[0], color: .systemGreen, in: context)
        drawMarker(at: top[top.count - 1], color: .systemRed, in: context)
    }

    /// The ribbon's shading, matching `BodyWorkoutRoute3DHero`'s.
    private static let wallGroundOpacity: CGFloat = 0.35
    private static let wallTopOpacity: CGFloat = 0.34
    private static let wallBottomOpacity: CGFloat = 0.04

    private static func drawMarker(at point: CGPoint, color: UIColor, in context: CGContext) {
        let radius: CGFloat = 6
        let inner = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: inner.insetBy(dx: -2.5, dy: -2.5))
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: inner)
    }
}

/// Map-free route hero: the route stroked in the workout's tint over the sheet's
/// tinted backdrop. Deliberately plainer than the map hero — no pace coloring and
/// no start/end markers — so the trace reads as a single shape.
struct BodyWorkoutRoutePlainHero: View {
    let route: WorkoutRoute
    let tint: Color
    /// Y the route's vertical center should land on; see `BodyWorkoutRouteMapHero`.
    let targetCenterY: CGFloat
    /// Top safe-area inset; see `BodyWorkoutRouteMapHero`.
    let topInset: CGFloat
    /// Draws the trace in from start to finish when the hero appears. `var` with a
    /// default rather than `let`: a `let` with a default value is left out of the
    /// synthesized memberwise initializer, so existing call sites could not opt in.
    var drawsReveal: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Captured when this hero is inserted, so the draw always starts at the start of
    /// the line no matter when the route resolved.
    @State private var epoch = Date()
    @State private var revealFinished = false

    private var isRevealing: Bool { drawsReveal && !reduceMotion && !revealFinished }

    var body: some View {
        // Project once per layout pass rather than per `Canvas` redraw: routes carry
        // thousands of fixes.
        let points = WorkoutShareRouteProjection.normalizedPoints(for: route.coordinates)
        return Group {
            if isRevealing {
                TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                    canvas(points: points, fraction: BodyWorkoutRouteReveal.fraction(epoch: epoch, date: timeline.date))
                }
            } else {
                canvas(points: points, fraction: 1)
            }
        }
        .task {
            guard drawsReveal, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(BodyWorkoutRouteReveal.totalDuration))
            revealFinished = true
        }
    }

    /// The trace drawn up to `fraction` of its length. At 1 this is byte-for-byte the
    /// steady-state drawing, so tearing the timeline down is invisible.
    private func canvas(points: [CGPoint]?, fraction: CGFloat) -> some View {
        Canvas { context, size in
            // A degenerate (treadmill-jitter) route projects to nil — then the page is
            // just the backdrop, like a routeless workout.
            guard let points, let path = Self.path(for: points, in: size, targetCenterY: targetCenterY, topInset: topInset) else {
                return
            }

            context.stroke(
                fraction >= 1 ? path : path.trimmedPath(from: 0, to: fraction),
                with: .color(tint),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// The fitted trace as a single open path.
    private static func path(for points: [CGPoint], in size: CGSize, targetCenterY: CGFloat, topInset: CGFloat) -> Path? {
        guard let fitted = BodyWorkoutRouteHeroFit.fittedPoints(points, in: size, targetCenterY: targetCenterY, topInset: topInset),
              let first = fitted.first else {
            return nil
        }

        var path = Path()
        path.move(to: first)
        for point in fitted.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

/// Shared framing for the map-free heroes: maps a unit-square projection into hero
/// space so the plain trace and the 3D ribbon sit in exactly the same place.
/// Internal rather than private so the fit can be unit-tested.
enum BodyWorkoutRouteHeroFit {
    /// Side inset so the stroke never runs into the screen edges.
    private static let sidePadding: CGFloat = 24
    /// Smallest gap kept between the route's top edge and the safe area above it.
    private static let topMargin: CGFloat = 12
    /// Drawn at 90% of the fitted size: just enough inset that the trace reads as a
    /// composed figure around the same center rather than a full-bleed edge-to-edge fill.
    private static let sizeFactor: CGFloat = 0.9

    /// `points` mapped into hero space by `transform(fitting:)`.
    static func fittedPoints(_ points: [CGPoint], in size: CGSize, targetCenterY: CGFloat, topInset: CGFloat) -> [CGPoint]? {
        guard let fit = transform(fitting: points, in: size, targetCenterY: targetCenterY, topInset: topInset) else {
            return nil
        }
        return points.map { point in
            CGPoint(x: fit.offset.x + point.x * fit.scale, y: fit.offset.y + point.y * fit.scale)
        }
    }

    /// The affine mapping (uniform scale then translate) that frames `points`:
    /// aspect-preserving fit to the padded width, height capped so the route clears the
    /// content below it, and the points' bounding box centered on `targetCenterY`.
    /// Exposed separately from `fittedPoints` so the 3D hero can frame one pose of the
    /// ribbon — its rest pose — and then draw a different, turned one through the same
    /// mapping.
    static func transform(
        fitting points: [CGPoint],
        in size: CGSize,
        targetCenterY: CGFloat,
        topInset: CGFloat
    ) -> (scale: CGFloat, offset: CGPoint)? {
        guard points.count >= 2, size.width > 0 else {
            return nil
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        let availableWidth = size.width - sidePadding * 2
        // Centered on `targetCenterY`, the route can only grow to twice the space
        // above it before it would run under the status bar / Dynamic Island.
        let availableHeight = 2 * (targetCenterY - topInset - topMargin)
        guard availableWidth > 0, availableHeight > 0 else {
            return nil
        }

        // One axis can be flat — a due-north route has no width — so scale on whichever
        // axes have extent.
        let widthScale = maxX > minX ? availableWidth / (maxX - minX) : .infinity
        let heightScale = maxY > minY ? availableHeight / (maxY - minY) : .infinity
        let scale = min(widthScale, heightScale) * sizeFactor
        guard scale.isFinite, scale > 0 else {
            return nil
        }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        return (
            scale,
            CGPoint(x: size.width / 2 - centerX * scale, y: targetCenterY - centerY * scale)
        )
    }
}

/// Map-free route hero drawn as an oblique elevation ribbon (Route Style › 3D): the
/// lifted route line in the workout's tint, translucent walls dropping to a faint
/// ground trace. Purely decorative — no markers, pace coloring, or labels — and it
/// falls back to the plain trace when the route carries no usable altitude. The
/// route turns with the sheet's horizontal swipe (`yawState`).
struct BodyWorkoutRoute3DHero: View {
    let route: WorkoutRoute
    let tint: Color
    /// Y the route's vertical center should land on; see `BodyWorkoutRouteMapHero`.
    let targetCenterY: CGFloat
    /// Top safe-area inset; see `BodyWorkoutRouteMapHero`.
    let topInset: CGFloat
    /// Live rotation of the route about its own centre. Read here rather than passed
    /// as a plain angle so a drag frame re-renders this hero alone, not the whole
    /// detail sheet. The plain fallback below ignores it — a flat trace has no
    /// third axis to turn about.
    let yawState: BodyWorkoutRouteYawState
    /// Draws the ribbon in from start to finish when the hero appears. See
    /// `BodyWorkoutRoutePlainHero.drawsReveal` for why this is `var`, not `let`.
    var drawsReveal: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var epoch = Date()
    @State private var revealFinished = false

    private var isRevealing: Bool { drawsReveal && !reduceMotion && !revealFinished }

    /// Faint trace of where the route ran on the ground, under the ribbon.
    private static let groundOpacity = 0.35
    /// Walls between the ground trace and the lifted line fade from the line down to
    /// the ground, so the ribbon reads as a lit edge with a shaded drop rather than a
    /// solid slab — and stays readable where the route folds back over itself.
    private static let wallTopOpacity = 0.34
    private static let wallBottomOpacity = 0.04

    var body: some View {
        // Project once per layout pass rather than per `Canvas` redraw: routes carry
        // thousands of fixes.
        let projected = WorkoutRoute3DProjection.projected(for: route.coordinates, yaw: yawState.yaw + yawState.drag)
        return Group {
            if let projected {
                if isRevealing {
                    TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                        ribbon(projected, revealed: BodyWorkoutRouteReveal.fraction(epoch: epoch, date: timeline.date))
                    }
                } else {
                    ribbon(projected, revealed: 1)
                }
            } else {
                // A route with no usable altitude has no ribbon to draw — the fallback
                // lives here so the detail sheet never branches on the route's data. It
                // carries the reveal too, or a 3D-style route without altitude would be
                // the one page that still popped its route in fully formed.
                BodyWorkoutRoutePlainHero(
                    route: route,
                    tint: tint,
                    targetCenterY: targetCenterY,
                    topInset: topInset,
                    drawsReveal: drawsReveal
                )
            }
        }
        .task {
            guard drawsReveal, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(BodyWorkoutRouteReveal.totalDuration))
            revealFinished = true
        }
    }

    private func ribbon(_ projected: WorkoutRoute3DProjection.Projected3D, revealed: CGFloat) -> some View {
        Canvas { context, size in
            // Fit the lifted line and the ground trace as one shape: two separate
            // fits would scale and center them independently and shear the walls.
            // The fit is taken from the route's rest pose, so turning it neither
            // resizes nor re-centres the ribbon — a route swung end-on can reach past
            // the hero band, which the frame clips.
            guard let fit = BodyWorkoutRouteHeroFit.transform(
                fitting: projected.fitReference,
                in: size,
                targetCenterY: targetCenterY,
                topInset: topInset
            ) else {
                return
            }
            let place = { (point: CGPoint) in
                CGPoint(x: fit.offset.x + point.x * fit.scale, y: fit.offset.y + point.y * fit.scale)
            }
            Self.drawRibbon(
                top: projected.top.map(place),
                base: projected.base.map(place),
                tint: tint,
                revealed: revealed,
                in: &context
            )
        }
        .accessibilityHidden(true)
    }

    /// Paints one ribbon — faint ground trace, then the walls and lifted line
    /// interleaved back to front — into an already-fitted pair of polylines. Internal
    /// so the share card draws its centered 3D route with exactly this painter.
    static func drawRibbon(
        top: [CGPoint],
        base: [CGPoint],
        tint: Color,
        revealed: CGFloat = 1,
        in context: inout GraphicsContext
    ) {
        // `trim` can't drive this reveal: the walls below are painted back to front by
        // ground depth, not in route order, so trimming the composed path would grow the
        // ribbon from whichever end happens to be farthest away. Cut the polylines in
        // route order first, then let the depth sort run over what's left.
        let (top, base) = Self.revealed(top: top, base: base, fraction: revealed)
        let count = min(top.count, base.count)
        guard count >= 2 else { return }

        var groundPath = Path()
        groundPath.addLines(base)
        context.stroke(groundPath, with: .color(tint.opacity(groundOpacity)), style: StrokeStyle(lineWidth: 2))

        // Painter's algorithm: draw the segments back to front by their ground
        // depth, so on a route that crosses itself the nearer wall covers the
        // farther line instead of the draw order deciding at random.
        let order = (0..<(count - 1)).sorted { base[$0].y + base[$0 + 1].y < base[$1].y + base[$1 + 1].y }
        for index in order {
            var wall = Path()
            wall.addLines([top[index], top[index + 1], base[index + 1], base[index]])
            wall.closeSubpath()
            // Gradient endpoints at the segment's own top and ground midpoints, so
            // every wall shades over its full drop whatever its height.
            let topMid = CGPoint(x: (top[index].x + top[index + 1].x) / 2, y: (top[index].y + top[index + 1].y) / 2)
            let baseMid = CGPoint(x: (base[index].x + base[index + 1].x) / 2, y: (base[index].y + base[index + 1].y) / 2)
            context.fill(
                wall,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(wallTopOpacity), tint.opacity(wallBottomOpacity)]),
                    startPoint: topMid,
                    endPoint: baseMid
                )
            )

            var segment = Path()
            segment.addLines([top[index], top[index + 1]])
            context.stroke(
                segment,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// The first `fraction` of the ribbon, in route order, measured by **cumulative
    /// length along the lifted line** rather than by point index. The fixes are
    /// downsampled by a fixed stride over time, so equal-index segments are not equal
    /// length: an index-based cut would race the head across a long straight and crawl it
    /// through a dense cluster, and would visibly disagree with the Plain and Map heroes,
    /// which get arc-length pacing free from `Path.trimmedPath`.
    ///
    /// `base` is cut at the same index and interpolated by the same amount, so the two
    /// arrays stay equal-length and no wall is ever built from mismatched ends.
    /// Internal so the pacing can be unit-tested.
    static func revealed(top: [CGPoint], base: [CGPoint], fraction: CGFloat) -> (top: [CGPoint], base: [CGPoint]) {
        let count = min(top.count, base.count)
        guard count >= 2, fraction < 1 else {
            return (Array(top.prefix(count)), Array(base.prefix(count)))
        }
        // Nothing drawn yet — the painter bails on fewer than two points, which is what
        // holds the ribbon off screen through the reveal's opening beat.
        guard fraction > 0 else {
            return ([], [])
        }

        var lengths: [CGFloat] = []
        lengths.reserveCapacity(count - 1)
        var total: CGFloat = 0
        for index in 0..<(count - 1) {
            let dx = top[index + 1].x - top[index].x
            let dy = top[index + 1].y - top[index].y
            let length = (dx * dx + dy * dy).squareRoot()
            lengths.append(length)
            total += length
        }
        // A route projected end-on can collapse to zero length; fall back to showing it
        // whole rather than dividing by zero.
        guard total > 0 else {
            return (Array(top.prefix(count)), Array(base.prefix(count)))
        }

        let target = total * fraction
        var travelled: CGFloat = 0
        for index in 0..<(count - 1) {
            let length = lengths[index]
            guard travelled + length >= target else {
                travelled += length
                continue
            }
            // Interpolate the head inside this segment so the ribbon grows smoothly
            // rather than one whole segment at a time.
            let t = length > 0 ? (target - travelled) / length : 0
            func interpolate(_ points: [CGPoint]) -> CGPoint {
                CGPoint(
                    x: points[index].x + (points[index + 1].x - points[index].x) * t,
                    y: points[index].y + (points[index + 1].y - points[index].y) * t
                )
            }
            // Always keep at least two points so the ribbon has a segment to draw.
            let kept = max(index + 1, 1)
            return (
                Array(top.prefix(kept)) + [interpolate(top)],
                Array(base.prefix(kept)) + [interpolate(base)]
            )
        }
        return (Array(top.prefix(count)), Array(base.prefix(count)))
    }
}

/// Stand-in for the route hero while the fixes load, shown when Route Style ▸ Draw Route
/// is off: the band is already reserved, so this fills it with a sweeping tinted block
/// rather than leaving it empty until the route crossfades in.
///
/// Driven from wall-clock time through `TimelineView` rather than an `onAppear`-started
/// repeating animation, for the same reason `BodyPixelGridLoader` is — this view is
/// conditionally inserted, and an animation started on appearance is lost when it is.
struct BodyWorkoutRouteHeroShimmer: View {
    let tint: Color
    /// Y the shimmer's center should land on, matching the route's own framing so the
    /// placeholder occupies the band the trace will.
    let targetCenterY: CGFloat
    let topInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var epoch = Date()

    /// One sweep of the highlight across the block.
    private static let sweepDuration: TimeInterval = 1.4
    private static let sidePadding: CGFloat = 24
    private static let blockHeight: CGFloat = 180
    private static let cornerRadius: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let width = max(size.width - Self.sidePadding * 2, 0)
            let height = min(Self.blockHeight, max(2 * (targetCenterY - topInset - 12), 0))
            let rect = CGRect(
                x: Self.sidePadding,
                y: max(targetCenterY - height / 2, topInset),
                width: width,
                height: height
            )

            if reduceMotion {
                block(in: rect, phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(epoch)
                    block(in: rect, phase: elapsed.truncatingRemainder(dividingBy: Self.sweepDuration) / Self.sweepDuration)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The tinted block with a diagonal highlight at `phase` (0…1) of its travel.
    private func block(in rect: CGRect, phase: Double) -> some View {
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            let shape = Path(roundedRect: rect, cornerRadius: Self.cornerRadius, style: .continuous)
            context.fill(shape, with: .color(tint.opacity(0.16)))

            guard !reduceMotion else { return }
            // Travel from fully off the leading edge to fully off the trailing one, so
            // the highlight enters and leaves rather than appearing mid-block.
            let travel = rect.width * 2
            let x = rect.minX - rect.width / 2 + travel * phase
            context.drawLayer { layer in
                layer.clip(to: shape)
                layer.fill(
                    Path(CGRect(x: x, y: rect.minY, width: rect.width / 2, height: rect.height)),
                    with: .linearGradient(
                        Gradient(colors: [
                            tint.opacity(0),
                            tint.opacity(0.22),
                            tint.opacity(0)
                        ]),
                        startPoint: CGPoint(x: x, y: rect.midY),
                        endPoint: CGPoint(x: x + rect.width / 2, y: rect.midY)
                    )
                )
            }
        }
    }
}

/// Pace coloring shared by the static hero snapshot and the full-screen map.
enum WorkoutRoutePaceColoring {
    /// Robust [lo, hi] speed range (10th–90th percentile of moving fixes) used to
    /// normalize the pace coloring, or `nil` when there isn't enough spread to be
    /// meaningful — then the route draws in a single tint.
    static func speedColorBounds(for route: [RouteCoordinate]) -> (lo: Double, hi: Double)? {
        let speeds = route.map(\.speed).filter { $0 > 0 }.sorted()
        guard speeds.count >= 4 else {
            return nil
        }
        let lo = speeds[Int(Double(speeds.count - 1) * 0.1)]
        let hi = speeds[Int(Double(speeds.count - 1) * 0.9)]
        guard hi - lo > 0.3 else {
            return nil
        }
        return (lo, hi)
    }

    /// Maps a segment speed to a hue from red (slow) through yellow to green (fast).
    static func color(forSpeed speed: Double, bounds: (lo: Double, hi: Double)) -> UIColor {
        let fraction = min(max((speed - bounds.lo) / (bounds.hi - bounds.lo), 0), 1)
        return UIColor(hue: CGFloat(fraction) * 0.33, saturation: 0.9, brightness: 0.95, alpha: 1)
    }
}

/// `.task(id:)` key so the snapshot re-renders when the hero size, the route's
/// target center, or the light/dark appearance changes.
private struct SnapshotInput: Equatable {
    let width: CGFloat
    let height: CGFloat
    let centerY: CGFloat
    let topInset: CGFloat
    let isDark: Bool
}
