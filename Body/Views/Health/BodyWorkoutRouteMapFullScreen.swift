//
//  BodyWorkoutRouteMapFullScreen.swift
//  Body
//
//  Full-screen interactive route map, presented when the static map hero on the
//  workout detail sheet is tapped (like Apple's Fitness app). Wraps a live
//  `MKMapView` so the whole route is pannable/zoomable, with the same pace
//  coloring as the hero via a single `MKGradientPolylineRenderer` overlay. Route
//  Style ▸ 3D Map (`is3D`) tilts that same map over realistic elevation.
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

/// Live `MKMapView` showing the whole route. One `MKPolyline` overlay rendered
/// with a distance-keyed pace gradient (red slow → green fast, matching the
/// hero snapshot), plus start (green) / end (red) dot annotations.
private struct RouteMapView: UIViewRepresentable {
    let route: WorkoutRoute
    let tint: Color
    let is3D: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(route: route, tint: UIColor(tint), is3D: is3D)
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
        mapView.addOverlay(polyline)

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
        private let route: WorkoutRoute
        private let tint: UIColor
        private let is3D: Bool
        /// One-shot latch: the tilt below itself changes the visible region, and after
        /// it lands the map belongs to the user's gestures.
        private var hasApplied3DPitch = false

        init(route: WorkoutRoute, tint: UIColor, is3D: Bool) {
            self.route = route
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

            if let bounds = WorkoutRoutePaceColoring.speedColorBounds(for: route.coordinates),
               let stops = Self.gradientStops(for: route.coordinates, on: polyline, bounds: bounds) {
                let renderer = MKGradientPolylineRenderer(polyline: polyline)
                renderer.setColors(stops.colors, locations: stops.locations)
                renderer.lineWidth = 5
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }

            // Same fallback semantics as the hero: not enough speed spread (or a
            // degenerate zero-length route) draws in a single tint.
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = tint
            renderer.lineWidth = 5
            renderer.lineJoin = .round
            renderer.lineCap = .round
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

        /// Pace gradient stops keyed by MapKit's own unit-distance locations
        /// along the polyline. Duplicate fixes yield equal adjacent fractions,
        /// which the gradient renderer rejects, so only strictly increasing
        /// locations are kept; `nil` (→ plain tint) when fewer than two survive,
        /// e.g. when every fix sits on the same spot.
        private static func gradientStops(
            for coordinates: [RouteCoordinate],
            on polyline: MKPolyline,
            bounds: (lo: Double, hi: Double)
        ) -> (colors: [UIColor], locations: [CGFloat])? {
            var colors: [UIColor] = []
            var locations: [CGFloat] = []
            for index in 0..<polyline.pointCount {
                let location = polyline.location(atPointIndex: index)
                guard location.isFinite, location > (locations.last ?? -1) else {
                    continue
                }
                colors.append(WorkoutRoutePaceColoring.color(forSpeed: coordinates[index].speed, bounds: bounds))
                locations.append(location)
            }
            guard locations.count >= 2 else {
                return nil
            }
            return (colors, locations)
        }
    }
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
