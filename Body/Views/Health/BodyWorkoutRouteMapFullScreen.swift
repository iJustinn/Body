//
//  BodyWorkoutRouteMapFullScreen.swift
//  Body
//
//  Full-screen interactive route map, presented when the static map hero on the
//  workout detail sheet is tapped (like Apple's Fitness app). Wraps a live
//  `MKMapView` so the whole route is pannable/zoomable, with the same pace
//  coloring as the hero via a single `MKGradientPolylineRenderer` overlay.
//

import SwiftUI
import MapKit

struct BodyWorkoutRouteMapFullScreen: View {
    let route: WorkoutRoute
    let tint: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // The ZStack keeps its safe-area insets, so the X sits below the status
        // bar / Dynamic Island even though the map extends under them.
        ZStack(alignment: .topTrailing) {
            RouteMapView(route: route, tint: tint)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(route: route, tint: UIColor(tint))
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll

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

        init(route: WorkoutRoute, tint: UIColor) {
            self.route = route
            self.tint = tint
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
