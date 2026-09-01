//
//  BodyWorkoutRouteMapHero.swift
//  Body
//
//  Full-bleed static map hero at the top of the workout detail sheet. Renders a
//  one-shot `MKMapSnapshotter` image with the route polyline and start/end dots
//  drawn in — a true static image (no live `Map`), so it never fights the
//  sheet's scroll and carries no tile/gesture lifecycle. The city label overlays
//  the bottom-leading corner over a short scrim. Route Style ▸ 3D Map renders the
//  same hero from a pitched camera over realistic elevation (`is3D`), framed by
//  measurement onto the box the 3D Plain ribbon occupies so the two styles put the
//  route at the same size and place.
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
    /// Route Style ▸ 3D Map: snapshot a pitched camera over realistic elevation instead
    /// of the flat, vertically anchored map rect.
    var is3D: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    // No progressive draw here: the map styles bake their pace-colored route into the
    // snapshot, so Route Style ▸ Draw Route is offered only for the map-free styles.
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
            // Both framings consume the anchor measurements now — the 3D camera is
            // corrected onto the 3D Plain ribbon's box — so a re-measured centerY has to
            // re-render. Rounded, so a sub-pixel remeasure doesn't re-run the (much
            // slower) elevation snapshot for no visual change.
            .task(id: SnapshotInput(width: proxy.size.width.rounded(), height: proxy.size.height.rounded(), centerY: targetCenterY.rounded(), topInset: topInset.rounded(), isDark: colorScheme == .dark, is3D: is3D)) {
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

        // 3D Map carries the 3D Plain ribbon over the tiles: the same lifted,
        // elevation-extruded route the map-free hero draws. The lift is needed before
        // the snapshot too, since the framing pass measures the ribbon it will draw.
        let lift = is3D ? WorkoutRoute3DProjection.liftUnits(for: route.coordinates) : nil

        let result: MKMapSnapshotter.Snapshot
        if is3D {
            guard let framed = await framedSnapshot(coordinates: coordinates, size: size, lift: lift) else {
                return
            }
            result = framed
        } else {
            let options = snapshotOptions(size: size)
            options.mapRect = Self.mapRect(for: coordinates, size: size, targetCenterY: targetCenterY, topInset: topInset)
            guard let flat = try? await MKMapSnapshotter(options: options).start() else {
                return
            }
            // A superseded `.task(id:)` render (e.g. a later anchor measurement) must not
            // overwrite this snapshot with a stale framing after the fact.
            guard !Task.isCancelled else { return }
            result = flat
        }

        // The composited ribbon: the same lifted,
        // elevation-extruded route the map-free hero draws — a single-color line, no
        // pace shading, no start/end dots — standing on the pitched terrain. White
        // rather than the workout tint, so every route reads the same against the
        // map's own colors. Without usable altitude `liftUnits` is nil and the flat
        // white trace draws instead, mirroring 3D Plain's own fallback.
        let image = Self.draw(route: route.coordinates, on: result, fallbackTint: is3D ? .white : UIColor(tint), lift: lift, usesPaceColoring: !is3D, drawsMarkers: !is3D)
        // The view-level `.animation(value:)` on `mapLayer` drives the fade-in.
        snapshot = image
    }

    /// The snapshotter options both framings share.
    private func snapshotOptions(size: CGSize) -> MKMapSnapshotter.Options {
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = displayScale
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        return options
    }

    /// The 3D snapshot, framed so its ribbon lands on the box the 3D Plain hero would
    /// draw for the same route at rest.
    ///
    /// `camera` and `mapRect` are mutually exclusive, so the pitched path can't be
    /// framed by a rect the way the flat one is, and MapKit's pitched projection over
    /// realistic elevation isn't analytically predictable: the same camera distance
    /// yields a different on-screen size depending on the terrain under the route. So
    /// the framing is measured rather than derived. A first snapshot from the route's
    /// own bounding-box camera is projected back through `snapshot.point(for:)`, the
    /// ribbon it would draw is measured, and the camera is corrected (distance for
    /// size, look-at point for position) before re-snapshotting. One correction lands
    /// within a couple of points on ordinary routes; a second is taken only when it
    /// doesn't, and the pass count is capped so a pathological route can't spin.
    @MainActor
    private func framedSnapshot(coordinates: [CLLocationCoordinate2D], size: CGSize, lift: [Double]?) async -> MKMapSnapshotter.Snapshot? {
        let target = targetRibbonBox(size: size)
        let groundMapBox = Self.mapPointBounds(of: coordinates)
        var center = Self.center(of: coordinates)
        var distance = Self.cameraDistance(for: coordinates)
        var latest: MKMapSnapshotter.Snapshot?

        for pass in 0..<Self.maximumFramingPasses {
            let options = snapshotOptions(size: size)
            options.camera = MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 60, heading: 0)
            // On the configuration, not `options.pointOfInterestFilter`: that legacy
            // property is ignored once a preferred configuration is set.
            let configuration = MKStandardMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = configuration

            guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
                return latest
            }
            // A superseded `.task(id:)` render (e.g. a later anchor measurement) must not
            // overwrite the snapshot with a stale framing after the fact.
            guard !Task.isCancelled else { return nil }
            latest = snapshot

            guard pass < Self.maximumFramingPasses - 1,
                  let target,
                  case let base = coordinates.map({ snapshot.point(for: $0) }),
                  let measured = Self.ribbonBounds(base: base, lift: lift),
                  let ground = Self.bounds(of: base),
                  let correction = Self.correctedFraming(
                      measured: measured,
                      target: target,
                      screenCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                      distance: distance,
                      centerMapPoint: MKMapPoint(center),
                      groundMapSize: groundMapBox.size,
                      groundScreenSize: ground.size,
                      minimumDistance: Self.minimumCameraDistance
                  ) else {
                return latest
            }

            distance = correction.distance
            center = correction.center.coordinate
        }

        return latest
    }

    /// Box the 3D Plain hero would draw this route into at rest, in hero space: the
    /// target both the size and the position of the 3D Map ribbon are corrected onto.
    /// `nil` when the route can't be framed at all (a degenerate trace, or no room
    /// under the safe area), which leaves the camera at its uncorrected framing.
    private func targetRibbonBox(size: CGSize) -> CGRect? {
        // The same choice 3D Plain makes: the elevation ribbon when the route carries
        // altitude, otherwise the flat trace its own fallback hero draws.
        let reference = WorkoutRoute3DProjection.projected(for: route.coordinates)?.fitReference
            ?? WorkoutShareRouteProjection.normalizedPoints(for: route.coordinates)
        guard let reference,
              let fitted = BodyWorkoutRouteHeroFit.fittedPoints(reference, in: size, targetCenterY: targetCenterY, topInset: topInset) else {
            return nil
        }
        return Self.bounds(of: fitted)
    }

    /// Most snapshots one 3D hero render may take: the first framing pass plus up to
    /// two corrections. Elevation snapshots are slow, so the cap matters.
    private static let maximumFramingPasses = 3
    /// Framing residual, in points, small enough to stop correcting at.
    private static let framingTolerance: CGFloat = 2

    /// Axis-aligned bounds of a point cloud.
    private static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var rect = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    /// Bounds of the ribbon `draw(route:on:...)` would paint from these ground points —
    /// the ground trace together with its lifted twin, or the ground trace alone when
    /// there is no usable lift, matching that painter's own fallback.
    private static func ribbonBounds(base: [CGPoint], lift: [Double]?) -> CGRect? {
        guard let ground = bounds(of: base) else { return nil }
        guard let lift, lift.count == base.count else { return ground }
        return bounds(of: base + liftedTop(base: base, lift: lift, in: ground))
    }

    /// Map-point bounds of a coordinate list.
    private static func mapPointBounds(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) { rect, coordinate in
            rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
    }

    /// Camera that puts `measured` onto `target`: the distance scaled by whichever axis
    /// binds (so the ribbon fits inside the plain hero's box, touching it on that axis),
    /// then the look-at point shifted to cancel what is left of the centre offset.
    ///
    /// Screen scale moves as the inverse of camera distance, about the look-at point at
    /// the snapshot's centre, so the rescale is predicted first and the *residual*
    /// offset converted into a look-at shift. The conversion uses the local screen-per-
    /// map-point rate measured on the pass just taken, scaled by the same factor. Note
    /// the sign: moving the look-at point east or south moves the content left or up.
    ///
    /// `nil` once the framing is within tolerance, which is what stops the loop.
    /// Internal so the correction maths can be unit-tested without a snapshotter.
    static func correctedFraming(
        measured: CGRect,
        target: CGRect,
        screenCenter: CGPoint,
        distance: CLLocationDistance,
        centerMapPoint: MKMapPoint,
        groundMapSize: MKMapSize,
        groundScreenSize: CGSize,
        minimumDistance: CLLocationDistance
    ) -> (distance: CLLocationDistance, center: MKMapPoint)? {
        guard target.width > 0, target.height > 0, distance > 0 else { return nil }

        let widthRatio = measured.width / target.width
        let heightRatio = measured.height / target.height
        let ratio = Double(max(widthRatio, heightRatio))
        guard ratio.isFinite, ratio > 0 else { return nil }

        let corrected = max(distance * ratio, minimumDistance)
        // Screen scale changes by this factor about the look-at point.
        let scale = CGFloat(distance / corrected)

        // Where the measured centre lands once the distance change is applied.
        let predicted = CGPoint(
            x: screenCenter.x + (measured.midX - screenCenter.x) * scale,
            y: screenCenter.y + (measured.midY - screenCenter.y) * scale
        )
        let residual = CGPoint(x: target.midX - predicted.x, y: target.midY - predicted.y)

        // Already there: the size is within a hair and the centre within tolerance.
        if abs(ratio - 1) < 0.01, abs(residual.x) < framingTolerance, abs(residual.y) < framingTolerance {
            return nil
        }

        // Screen points per map point on each axis, after the distance change.
        let horizontalRate = groundMapSize.width > 0 ? Double(groundScreenSize.width) / groundMapSize.width * Double(scale) : 0
        let verticalRate = groundMapSize.height > 0 ? Double(groundScreenSize.height) / groundMapSize.height * Double(scale) : 0

        var center = centerMapPoint
        if horizontalRate > 0 {
            center.x -= Double(residual.x) / horizontalRate
        }
        if verticalRate > 0 {
            center.y -= Double(residual.y) / verticalRate
        }
        guard center.x.isFinite, center.y.isFinite else { return nil }
        return (corrected, center)
    }

    /// The old region framing's 0.0016° minimum span, restated as a map-point width
    /// (the projection's x axis is linear in longitude) so a short loop isn't
    /// over-zoomed.
    private static let minimumSpanMapPoints = MKMapSize.world.width * 0.0016 / 360

    /// Midpoint of the route's bounding box, the point the 3D camera opens looking at.
    private static func center(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2,
            longitude: ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        )
    }

    /// Opening camera distance for the 3D framing: the route's larger ground span with
    /// enough headroom that a pitched view still holds both ends. Only the starting
    /// estimate, `framedSnapshot` corrects it onto the 3D Plain box from there. The
    /// floor keeps a treadmill-short loop from putting the camera inside the buildings.
    ///
    /// MapKit clamps pitch toward 0 as the distance grows, so long routes render
    /// progressively flatter — accepted rather than capped, since capping would crop
    /// the route.
    private static func cameraDistance(for coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else {
            return minimumCameraDistance
        }

        let vertical = CLLocation(latitude: minLatitude, longitude: minLongitude)
            .distance(from: CLLocation(latitude: maxLatitude, longitude: minLongitude))
        let horizontal = CLLocation(latitude: minLatitude, longitude: minLongitude)
            .distance(from: CLLocation(latitude: minLatitude, longitude: maxLongitude))
        return max(max(vertical, horizontal) * 2.2, minimumCameraDistance)
    }

    /// Closest the 3D camera is allowed to sit, so a near-stationary route still reads
    /// as a map rather than a wall of one building. When this floor binds the ribbon
    /// can't be shrunk to the target box, and is centred on it at whatever size it is.
    private static let minimumCameraDistance: CLLocationDistance = 400

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
    /// - Parameter usesPaceColoring: `false` strokes the whole line in `fallbackTint`
    ///   the way the 3D Plain hero does, whatever the route's speed spread. The 3D Map
    ///   hero passes it so its ribbon reads as that style's tinted line; the share card
    ///   keeps the default pace shading.
    /// - Parameter drawsMarkers: `false` omits the green start / red end dots — the 3D
    ///   Map hero, matching 3D Plain's marker-free line.
    static func draw(
        route: [RouteCoordinate],
        on snapshot: MKMapSnapshotter.Snapshot,
        fallbackTint: UIColor,
        lift: [Double]? = nil,
        usesPaceColoring: Bool = true,
        drawsMarkers: Bool = true
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
                drawRibbon(base: points, lift: lift, route: route, fallbackTint: fallbackTint, usesPaceColoring: usesPaceColoring, drawsMarkers: drawsMarkers, in: cgContext)
                return
            }

            if usesPaceColoring, let bounds = WorkoutRoutePaceColoring.speedColorBounds(for: route) {
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

            if drawsMarkers {
                drawMarker(at: first, color: .systemGreen, in: cgContext)
                drawMarker(at: last, color: .systemRed, in: cgContext)
            }
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
        usesPaceColoring: Bool,
        drawsMarkers: Bool,
        in context: CGContext
    ) {
        guard let ground = bounds(of: base) else {
            return
        }
        let top = liftedTop(base: base, lift: lift, in: ground)

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
        let speedBounds = usesPaceColoring ? WorkoutRoutePaceColoring.speedColorBounds(for: route) : nil
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
        if drawsMarkers {
            drawMarker(at: top[0], color: .systemGreen, in: context)
            drawMarker(at: top[top.count - 1], color: .systemRed, in: context)
        }
    }

    /// Each ground point's lifted twin, standing `lift × span` points straight above it.
    /// Shared by the painter and by the framing pass that measures what it will paint.
    private static func liftedTop(base: [CGPoint], lift: [Double], in ground: CGRect) -> [CGPoint] {
        let span = max(ground.width, ground.height)
        return base.enumerated().map { index, point in
            CGPoint(x: point.x, y: point.y - CGFloat(lift[index]) * span)
        }
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
/// target center, the light/dark appearance, or the 2D/3D framing changes.
private struct SnapshotInput: Equatable {
    let width: CGFloat
    let height: CGFloat
    let centerY: CGFloat
    let topInset: CGFloat
    let isDark: Bool
    let is3D: Bool
}
