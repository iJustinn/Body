//
//  HealthKitFetchEngine+Route.swift
//  Body
//
//  Reads a workout's GPS route (`HKWorkoutRoute`) for the detail map hero. Uses
//  the iOS 17 async query descriptors: they terminate themselves and honor
//  `Task` cancellation, so a dismissed sheet stops the read with no manual
//  `stopQuery`. The route is mapped to app-owned `RouteCoordinate`s before
//  crossing back to the `@MainActor` store.
//

import Foundation
import HealthKit
import CoreLocation

extension HealthKitFetchEngine {
    /// Coordinates for the workout's route, downsampled for cheap polyline
    /// drawing. Returns `[]` when the workout has no route, the route can't be
    /// read, or access is denied — HealthKit read authorization is opaque, so
    /// absent and denied are indistinguishable and both simply yield no hero.
    func workoutRouteCoordinates(workoutID: UUID) async -> [RouteCoordinate] {
        guard let workout = await fetchWorkout(id: workoutID) else {
            return []
        }

        do {
            let routeQuery = HKSampleQueryDescriptor(
                predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
            )
            let routes = try await routeQuery.result(for: healthStore)

            var locations: [CLLocation] = []
            for route in routes {
                let locationQuery = HKWorkoutRouteQueryDescriptor(route)
                for try await location in locationQuery.results(for: healthStore) {
                    locations.append(location)
                }
            }
            return Self.routeCoordinates(from: locations)
        } catch {
            return []
        }
    }

    /// Strides the raw fixes (often ~1/sec) down to at most `maxRoutePoints`,
    /// always keeping the final fix so the end marker lands on the true finish.
    /// Below the cap the points pass through unchanged. Each kept fix carries a
    /// resolved moving speed (device-reported, else derived from the next fix) so
    /// the map can color the route by pace.
    private static func routeCoordinates(
        from locations: [CLLocation],
        maxRoutePoints: Int = 400
    ) -> [RouteCoordinate] {
        guard !locations.isEmpty else {
            return []
        }

        func speed(at index: Int) -> Double {
            let reported = locations[index].speed
            if reported >= 0 {
                return reported
            }
            // CLLocation.speed is -1 when unknown — derive it geometrically from
            // the gap to the next fix so the coloring is source-agnostic.
            guard index + 1 < locations.count else {
                return index > 0 ? max(locations[index - 1].speed, 0) : 0
            }
            let dt = locations[index + 1].timestamp.timeIntervalSince(locations[index].timestamp)
            guard dt > 0 else {
                return 0
            }
            return max(locations[index + 1].distance(from: locations[index]) / dt, 0)
        }

        func coordinate(at index: Int) -> RouteCoordinate {
            let point = locations[index].coordinate
            return RouteCoordinate(latitude: point.latitude, longitude: point.longitude, speed: speed(at: index))
        }

        guard locations.count > maxRoutePoints else {
            return locations.indices.map(coordinate)
        }

        let step = Int((Double(locations.count) / Double(maxRoutePoints)).rounded(.up))
        var sampled: [RouteCoordinate] = []
        sampled.reserveCapacity(maxRoutePoints + 1)
        var index = 0
        while index < locations.count {
            sampled.append(coordinate(at: index))
            index += step
        }
        let lastIndex = locations.count - 1
        if sampled.last?.latitude != locations[lastIndex].coordinate.latitude
            || sampled.last?.longitude != locations[lastIndex].coordinate.longitude {
            sampled.append(coordinate(at: lastIndex))
        }
        return sampled
    }
}
