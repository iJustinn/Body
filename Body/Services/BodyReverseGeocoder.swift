//
//  BodyReverseGeocoder.swift
//  Body
//
//  Best-effort "City, Region" label for a workout route, used by the detail map
//  hero. Stateless and failure-tolerant: any error or `CLGeocoder` throttle just
//  yields `nil` and the map renders without a label. Callers cache the result
//  (see `BodyWorkoutDetailCacheStore.routeCache`) so a route is geocoded at most once
//  per session.
//

import Foundation
import CoreLocation

enum BodyReverseGeocoder {
    /// Reverse-geocodes the route's midpoint (more representative than the start
    /// for point-to-point routes) into a short locality label, or `nil`.
    static func locality(for coordinates: [RouteCoordinate]) async -> String? {
        guard !coordinates.isEmpty else {
            return nil
        }

        let midpoint = coordinates[coordinates.count / 2]
        let location = CLLocation(latitude: midpoint.latitude, longitude: midpoint.longitude)

        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }

        return format(placemark)
    }

    /// US → "City, ST" (e.g. "New York, NY"); elsewhere → "City, Country", since
    /// `administrativeArea` is only a short state code in the US. Falls back to
    /// the city alone, then any named place / region / country.
    private static func format(_ placemark: CLPlacemark) -> String? {
        guard let city = placemark.locality ?? placemark.subAdministrativeArea else {
            return placemark.name ?? placemark.administrativeArea ?? placemark.country
        }

        if placemark.isoCountryCode == "US", let region = placemark.administrativeArea {
            return "\(city), \(region)"
        }
        if let country = placemark.country {
            return "\(city), \(country)"
        }
        return city
    }
}
