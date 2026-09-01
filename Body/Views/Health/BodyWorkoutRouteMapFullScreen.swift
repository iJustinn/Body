//
//  BodyWorkoutRouteMapFullScreen.swift
//  Body
//
//  Full-screen interactive route map, presented when the static map hero on the
//  workout detail sheet is tapped (like Apple's Fitness app). Wraps a live
//  `MKMapView` so the whole route is pannable/zoomable, with the same pace
//  coloring as the hero, drawn as a run of short pace-colored `MKPolyline`
//  overlays. Route Style ▸ 3D Map (`is3D`) tilts that same map over realistic
//  elevation.
//

import SwiftUI
import MapKit

struct BodyWorkoutRouteMapFullScreen: View {
    let route: WorkoutRoute
    let tint: Color
    /// Route Style ▸ 3D Map: pitch the map over realistic elevation. Defaulted so the
    /// non-detail callers stay unchanged.
    var is3D: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The ZStack keeps its safe-area insets, so the X sits below the status
        // bar / Dynamic Island even though the map extends under them.
        ZStack(alignment: .topTrailing) {
            RouteMapView(route: route, tint: tint, is3D: is3D)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.trailing, 20)
            .accessibilityLabel("Close map")
        }
    }
}

/// Live `MKMapView` showing the whole route, styled like Fitness: a thin,
/// slightly translucent line, pace colored (red slow → green fast, matching the
/// hero snapshot) by splitting the route into short same-color `MKPolyline`
/// overlays, plus start (green) / end (red) dot annotations.
///
/// The pace coloring deliberately does not use `MKGradientPolylineRenderer`:
/// measured in a hosted map it strokes at roughly 2.3x its own `lineWidth`
/// with soft, smeared edges, so a 5 pt route came out as a blurry ~11 pt
/// ribbon at every zoom. `MKPolylineRenderer` honors `lineWidth` in screen
/// points exactly.
private struct RouteMapView: UIViewRepresentable {
    /// Fitness-like stroke: thin enough that out-and-back passes on one street
    /// stay two readable lines, translucent enough that they show through.
    static let lineWidth: CGFloat = 4.5
    static let lineOpacity: CGFloat = 0.85
    /// Upper bound on the pace-colored pieces the route is cut into. Bounds the
    /// overlay count on a long, noisy run while still reading as a smooth pace
    /// ramp; each piece takes the color of its own fixes' mean speed.
    static let maximumSegments = 200

    let route: WorkoutRoute
    let tint: Color
    let is3D: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(tint: UIColor(tint), is3D: is3D)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        if is3D {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic)
        }

        let coordinates = route.coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        if let bounds = WorkoutRoutePaceColoring.speedColorBounds(for: route.coordinates),
           let segments = Self.paceSegments(for: route.coordinates, coordinates: coordinates, bounds: bounds) {
            mapView.addOverlays(segments)
        } else {
            // Same fallback semantics as the hero: not enough speed spread (or a
            // degenerate zero-length route) draws in a single tint.
            mapView.addOverlay(polyline)
        }

        if let start = coordinates.first, let end = coordinates.last {
            mapView.addAnnotation(RouteEndpointAnnotation(coordinate: start, color: .systemGreen))
            mapView.addAnnotation(RouteEndpointAnnotation(coordinate: end, color: .systemRed))
        }

        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 100, left: 50, bottom: 100, right: 50),
            animated: false
        )
        // The pitch is deliberately not applied here: the fit above only resolves at
        // layout time, so the camera this early is pre-fit and its distance would be
        // meaningless. The coordinator tilts once the first real region lands.
        return mapView
    }

    /// Cuts the route into at most `maximumSegments` contiguous pieces, each a
    /// polyline colored by its own fixes' mean speed. Consecutive pieces share a
    /// vertex so the line has no gaps at the seams. `nil` when there is nothing
    /// to draw, which falls back to the single tinted polyline.
    private static func paceSegments(
        for fixes: [RouteCoordinate],
        coordinates: [CLLocationCoordinate2D],
        bounds: (lo: Double, hi: Double)
    ) -> [PaceSegmentPolyline]? {
        guard coordinates.count >= 2 else {
            return nil
        }
        let segmentCount = min(maximumSegments, coordinates.count - 1)
        var segments: [PaceSegmentPolyline] = []
        for segment in 0..<segmentCount {
            let start = segment * (coordinates.count - 1) / segmentCount
            let end = (segment + 1) * (coordinates.count - 1) / segmentCount
            guard end > start else {
                continue
            }
            // Mean speed over the fixes this piece spans, so a single noisy fix
            // cannot flip a whole stretch of the line.
            let speeds = fixes[start...end].map(\.speed)
            let meanSpeed = speeds.reduce(0, +) / Double(speeds.count)
            let slice = Array(coordinates[start...end])
            let polyline = PaceSegmentPolyline(coordinates: slice, count: slice.count)
            polyline.color = WorkoutRoutePaceColoring
                .color(forSpeed: meanSpeed, bounds: bounds)
                .withAlphaComponent(lineOpacity)
            segments.append(polyline)
        }
        return segments.isEmpty ? nil : segments
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // The route is immutable for a presentation; the view is created fresh
        // each time the cover presents.
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        uiView.delegate = nil
        uiView.removeOverlays(uiView.overlays)
        uiView.removeAnnotations(uiView.annotations)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let tint: UIColor
        private let is3D: Bool
        /// One-shot latch: the tilt below itself changes the visible region, and after
        /// it lands the map belongs to the user's gestures.
        private var hasApplied3DPitch = false

        init(tint: UIColor, is3D: Bool) {
            self.tint = tint
            self.is3D = is3D
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard is3D, !hasApplied3DPitch else { return }
            hasApplied3DPitch = true

            // Tilt the camera the fit produced rather than building one: keeping its
            // resolved center and distance is what preserves the route framing, and
            // MapKit is the only thing that knows what distance the edge-padded fit
            // settled on.
            let camera = MKMapCamera(
                lookingAtCenter: mapView.camera.centerCoordinate,
                fromDistance: mapView.camera.centerCoordinateDistance,
                pitch: 60,
                heading: mapView.camera.heading
            )
            mapView.setCamera(camera, animated: true)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            let segment = polyline as? PaceSegmentPolyline
            // A pace segment carries its own color; anything else is the single
            // tinted fallback route.
            renderer.strokeColor = segment?.color ?? tint.withAlphaComponent(RouteMapView.lineOpacity)
            renderer.lineWidth = RouteMapView.lineWidth
            renderer.lineJoin = .round
            // Pace segments meet at a shared vertex, so round caps there would
            // stack two translucent discs and bead the line; butt caps butt
            // cleanly into the next segment. The single fallback route has real
            // ends, so it keeps round caps.
            renderer.lineCap = segment == nil ? .round : .butt
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let endpoint = annotation as? RouteEndpointAnnotation else {
                return nil
            }

            let identifier = "routeEndpoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: endpoint, reuseIdentifier: identifier)
            view.annotation = endpoint
            // Same proportions as the hero's drawn markers: colored dot in a
            // white ring.
            view.frame = CGRect(x: 0, y: 0, width: 17, height: 17)
            view.layer.cornerRadius = 8.5
            view.layer.backgroundColor = endpoint.color.cgColor
            view.layer.borderColor = UIColor.white.cgColor
            view.layer.borderWidth = 2.5
            return view
        }
    }
}

/// One pace-colored piece of the route, carrying the color its renderer strokes it in.
private final class PaceSegmentPolyline: MKPolyline {
    var color: UIColor = .white
}

/// Start/end dot annotation carrying its fill color.
private final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let color: UIColor

    init(coordinate: CLLocationCoordinate2D, color: UIColor) {
        self.coordinate = coordinate
        self.color = color
    }
}
