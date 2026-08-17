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
    /// Whether the workout carries at least one `HKWorkoutRoute` series sample. This is
    /// the cheap half of `workoutRouteData` — series metadata only, with none of the
    /// per-route location streaming — so the detail page can reserve the route hero's
    /// band before the GPS fixes arrive instead of jumping the content down when they
    /// land.
    ///
    /// Throws for the same reasons `workoutRouteData` does, so the caller can tell "no
    /// route" from "didn't finish reading" and never caches a false negative. (Note the
    /// `fetchWorkout` half wraps a raw `HKSampleQuery` in a continuation and does NOT
    /// honor `Task` cancellation; only the descriptor read below does. A denied read is
    /// opaque in HealthKit and surfaces as `false`, i.e. today's no-hero behavior.)
    func workoutHasRoute(workoutID: UUID) async throws -> Bool {
        guard let workout = try await fetchWorkout(id: workoutID) else {
            return false
        }

        let routeQuery = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [],
            limit: 1
        )
        return try await routeQuery.result(for: healthStore).isEmpty == false
    }

    /// Coordinates for the workout's route, downsampled for cheap polyline
    /// drawing, plus the elevation profile reduced from the same raw fixes
    /// (before the downsampling, so the profile keeps its peaks and dips).
    /// Returns empty coordinates only when the workout genuinely has no route. Any
    /// read FAILURE — a cancelled read (dismissed detail sheet), a locked-device
    /// error, or an XPC drop — is propagated so the caller can tell "no route"
    /// from "didn't finish reading" and not cache a false negative for a workout
    /// that actually has a route. (HealthKit read authorization is opaque, so a
    /// denied route still surfaces as an empty result, i.e. no hero.)
    func workoutRouteData(
        workoutID: UUID
    ) async throws -> (coordinates: [RouteCoordinate], elevationProfile: [WorkoutElevationSample]) {
        guard let workout = try await fetchWorkout(id: workoutID) else {
            return ([], [])
        }

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
        return (
            Self.routeCoordinates(from: locations),
            WorkoutRoute.elevationProfile(from: locations, workoutStart: workout.startDate)
        )
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
            let location = locations[index]
            let point = location.coordinate
            // CoreLocation flags a fix with no usable vertical solution by making
            // `verticalAccuracy` negative — its `altitude` is then meaningless, so
            // it reads as "missing" rather than as sea level.
            let altitude = (location.verticalAccuracy >= 0 && location.altitude.isFinite) ? location.altitude : nil
            return RouteCoordinate(
                latitude: point.latitude,
                longitude: point.longitude,
                speed: speed(at: index),
                altitude: altitude
            )
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
