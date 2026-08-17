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
import CoreLocation

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

/// One altitude reading on the workout's timeline, feeding the elevation
/// profile chart. `offset` is seconds from the workout's start date.
struct WorkoutElevationSample: Sendable, Equatable {
    let offset: TimeInterval
    let meters: Double
}

/// What the workout detail page knows about a workout's GPS route while it loads.
/// `.unknown` until the cheap `HKWorkoutRoute` presence probe answers — and after a
/// probe that failed or was denied, since HealthKit read authorization is opaque and a
/// reservation made on a false positive would have to collapse again. Only `.present`
/// reserves the hero band, so the page never moves on a guess.
enum BodyWorkoutRoutePresence: Sendable, Equatable {
    case unknown
    case present
    case absent

    /// True when the page lays out with the route hero's band above the content.
    var reservesHero: Bool { self == .present }
}

struct WorkoutRoute: Sendable, Equatable {
    let coordinates: [RouteCoordinate]
    let locality: String?
    /// Altitude over time, reduced from the raw fixes before the polyline
    /// downsampling so peaks and dips survive. Empty when the route carried no
    /// usable vertical readings.
    var elevationProfile: [WorkoutElevationSample] = []
}

extension WorkoutRoute {
    /// Altitude readings usable for a profile: a vertical solution the device is
    /// confident about (`verticalAccuracy` is negative when there is none, and a
    /// coarse one is worse than no line at all).
    private static let usableVerticalAccuracy: ClosedRange<Double> = 0...25

    /// Reduces raw fixes (often ~1/sec) to at most `maxBuckets * 2` altitude
    /// samples by splitting the fixes' time span into equal buckets and keeping
    /// each bucket's lowest and highest fix. Extrema-preserving: striding would
    /// flatten a summit that falls between two kept fixes.
    ///
    /// Offsets are relative to `workoutStart`, so a route that starts recording
    /// after the workout does keeps its true position on the timeline.
    static func elevationProfile(
        from locations: [CLLocation],
        workoutStart: Date,
        maxBuckets: Int = 200
    ) -> [WorkoutElevationSample] {
        let usable = locations.filter {
            $0.altitude.isFinite && usableVerticalAccuracy.contains($0.verticalAccuracy)
        }
        guard let first = usable.first, let last = usable.last else { return [] }

        func sample(_ location: CLLocation) -> WorkoutElevationSample {
            WorkoutElevationSample(
                offset: location.timestamp.timeIntervalSince(workoutStart),
                meters: location.altitude
            )
        }

        let span = last.timestamp.timeIntervalSince(first.timestamp)
        guard span > 0, maxBuckets > 0 else {
            return [sample(first)]
        }

        var lowest: [Int: CLLocation] = [:]
        var highest: [Int: CLLocation] = [:]
        for location in usable {
            let elapsed = location.timestamp.timeIntervalSince(first.timestamp)
            let bucket = min(maxBuckets - 1, max(0, Int(elapsed / span * Double(maxBuckets))))
            if let current = lowest[bucket] {
                if location.altitude < current.altitude { lowest[bucket] = location }
            } else {
                lowest[bucket] = location
            }
            if let current = highest[bucket] {
                if location.altitude > current.altitude { highest[bucket] = location }
            } else {
                highest[bucket] = location
            }
        }

        var samples: [WorkoutElevationSample] = []
        samples.reserveCapacity(lowest.count * 2)
        for bucket in lowest.keys.sorted() {
            guard let low = lowest[bucket], let high = highest[bucket] else { continue }
            let pair = low.timestamp <= high.timestamp ? [low, high] : [high, low]
            for location in pair where samples.last != sample(location) {
                samples.append(sample(location))
            }
        }
        return samples
    }
}
