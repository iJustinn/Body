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

struct BodyWorkoutRouteMapHero: View {
    let route: WorkoutRoute
    let tint: Color
    /// Y the route's vertical center should land on, in hero space — which is screen
    /// space too, since the hero ignores the top safe area.
    let targetCenterY: CGFloat
    /// Top safe-area inset: the route must stay below the status bar / Dynamic Island
    /// even though the hero itself extends under them.
    let topInset: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: UIImage?

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
        // natural load time), instead of popping in instantly.
        Group {
            if let snapshot {
                Image(uiImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
        }
        .opacity(snapshot == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.5), value: snapshot != nil)
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
    static func draw(
        route: [RouteCoordinate],
        on snapshot: MKMapSnapshotter.Snapshot,
        fallbackTint: UIColor
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

    var body: some View {
        // Project once per layout pass rather than per `Canvas` redraw: routes carry
        // thousands of fixes.
        let points = WorkoutShareRouteProjection.normalizedPoints(for: route.coordinates)
        return Canvas { context, size in
            // A degenerate (treadmill-jitter) route projects to nil — then the page is
            // just the backdrop, like a routeless workout.
            guard let points, let path = Self.path(for: points, in: size, targetCenterY: targetCenterY, topInset: topInset) else {
                return
            }

            context.stroke(
                path,
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
                ribbon(projected)
            } else {
                // A route with no usable altitude has no ribbon to draw — the fallback
                // lives here so the detail sheet never branches on the route's data.
                BodyWorkoutRoutePlainHero(route: route, tint: tint, targetCenterY: targetCenterY, topInset: topInset)
            }
        }
    }

    private func ribbon(_ projected: WorkoutRoute3DProjection.Projected3D) -> some View {
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
            let count = projected.top.count
            let top = projected.top.map(place)
            let base = projected.base.map(place)

            var groundPath = Path()
            groundPath.addLines(base)
            context.stroke(groundPath, with: .color(tint.opacity(Self.groundOpacity)), style: StrokeStyle(lineWidth: 2))

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
                        Gradient(colors: [tint.opacity(Self.wallTopOpacity), tint.opacity(Self.wallBottomOpacity)]),
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
        .accessibilityHidden(true)
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
