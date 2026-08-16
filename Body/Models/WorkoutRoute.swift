//
//  WorkoutRoute.swift
//  Body
//
//  GPS route for a workout, read from HealthKit's `HKWorkoutRoute` and rendered
//  as the static map hero on the workout detail sheet. App-owned value types so
//  the off-main `HealthKitFetchEngine` actor never hands `CLLocationCoordinate2D`
//  (which is neither `Sendable` nor `Equatable`) across its boundary; the map
//  layer converts to `CLLocationCoordinate2D` only at draw time.
//

import Foundation

struct RouteCoordinate: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    /// Resolved moving speed at this fix in metres per second, used to color the
    /// route by pace. `0` when it couldn't be determined.
    let speed: Double
    /// Altitude at this fix in metres, used by the 3D route hero. `nil` when the
    /// fix carried no valid vertical reading.
    let altitude: Double?

    init(latitude: Double, longitude: Double, speed: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.altitude = altitude
    }
}

struct WorkoutRoute: Sendable, Equatable {
    let coordinates: [RouteCoordinate]
    let locality: String?
}
