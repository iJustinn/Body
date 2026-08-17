//
//  WorkoutRouteTests.swift
//  BodyTests
//
//  Covers the route's own reduction of raw GPS fixes into the altitude samples
//  the Elevation card is built from.
//

import CoreLocation
import XCTest
@testable import Body

final class WorkoutRouteTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func location(
        secondsFromStart: TimeInterval,
        altitude: Double,
        verticalAccuracy: Double = 4
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.33, longitude: -122.03),
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: verticalAccuracy,
            timestamp: start.addingTimeInterval(secondsFromStart)
        )
    }

    func testReductionKeepsBucketExtremes() {
        // 100 fixes, one per second, with a spike and a dip that a striding
        // downsample would very likely skip.
        var locations = (0..<100).map { location(secondsFromStart: Double($0), altitude: 50) }
        locations[23] = location(secondsFromStart: 23, altitude: -8)
        locations[57] = location(secondsFromStart: 57, altitude: 210)

        let profile = WorkoutRoute.elevationProfile(from: locations, workoutStart: start, maxBuckets: 10)

        XCTAssertLessThanOrEqual(profile.count, 20)
        XCTAssertTrue(profile.contains(WorkoutElevationSample(offset: 23, meters: -8)))
        XCTAssertTrue(profile.contains(WorkoutElevationSample(offset: 57, meters: 210)))
        XCTAssertEqual(profile.map(\.offset), profile.map(\.offset).sorted())
    }

    func testReductionDropsFixesWithoutUsableVerticalAccuracy() {
        var locations = (0..<40).map { location(secondsFromStart: Double($0), altitude: 100) }
        // No vertical solution at all, and a solution too coarse to trust.
        locations[10] = location(secondsFromStart: 10, altitude: 900, verticalAccuracy: -1)
        locations[20] = location(secondsFromStart: 20, altitude: 800, verticalAccuracy: 40)

        let profile = WorkoutRoute.elevationProfile(from: locations, workoutStart: start, maxBuckets: 40)

        XCTAssertFalse(profile.contains { $0.meters > 100 })
        XCTAssertEqual(profile.count, 38)
    }

    func testReductionOffsetsAreRelativeToWorkoutStart() {
        // The route's first fix lands 30 s after the workout began.
        let locations = (0..<20).map { location(secondsFromStart: 30 + Double($0), altitude: 100 + Double($0)) }

        let profile = WorkoutRoute.elevationProfile(from: locations, workoutStart: start, maxBuckets: 20)

        XCTAssertEqual(profile.first?.offset, 30)
        XCTAssertEqual(profile.last?.offset, 49)
    }

    func testReductionWithoutUsableAltitudesIsEmpty() {
        let locations = (0..<20).map { location(secondsFromStart: Double($0), altitude: 100, verticalAccuracy: -1) }

        XCTAssertTrue(WorkoutRoute.elevationProfile(from: locations, workoutStart: start).isEmpty)
    }
}
