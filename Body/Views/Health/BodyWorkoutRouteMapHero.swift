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

import SwiftUI
import MapKit
import UIKit

struct BodyWorkoutRouteMapHero: View {
    let route: WorkoutRoute
    let tint: Color

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
            .task(id: SnapshotInput(width: proxy.size.width.rounded(), height: proxy.size.height.rounded(), isDark: colorScheme == .dark)) {
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
        guard size.width > 0, route.coordinates.count >= 2 else {
            return
        }

        let coordinates = route.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        let options = MKMapSnapshotter.Options()
        options.region = Self.region(for: coordinates)
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

    /// Region bounding the whole route, padded so the line isn't flush to the
    /// edges, with a minimum span so a short loop isn't over-zoomed.
    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude, maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude, maxLon = coordinates[0].longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let latSpan = max(maxLat - minLat, 0.0016)
        let lonSpan = max(maxLon - minLon, 0.0016)

        // Bias the route toward the top of the map: a light margin above and a
        // generous one below (south). The empty map under the route gives a long,
        // natural fade into the black background instead of the route itself
        // fading out mid-line.
        let topLat = maxLat + latSpan * 0.25
        let bottomLat = minLat - latSpan * 0.5

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (topLat + bottomLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: topLat - bottomLat,
                longitudeDelta: lonSpan * 1.5
            )
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

/// `.task(id:)` key so the snapshot re-renders when the hero size or the
/// light/dark appearance changes.
private struct SnapshotInput: Equatable {
    let width: CGFloat
    let height: CGFloat
    let isDark: Bool
}
