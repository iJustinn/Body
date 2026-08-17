//
//  WorkoutElevationProfileTests.swift
//  BodyTests
//
//  Covers the elevation profile pipeline: the extrema-preserving reduction of a
//  route's raw fixes, and the presentation that turns those samples into the
//  Elevation card's geometry and strings.
//

import CoreLocation
import XCTest
@testable import Body

final class WorkoutElevationProfileTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let locale = Locale(identifier: "en_US")

    // MARK: - Reduction

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

    // MARK: - Smoothing

    func testMedianSmoothingRemovesSingleSpike() {
        let smoothed = WorkoutElevationProfilePresentation.medianSmoothed([10, 10, 10, 400, 10, 10, 10])

        XCTAssertEqual(smoothed, [10, 10, 10, 10, 10, 10, 10])
    }

    // MARK: - Presentation

    /// Ten samples of ±1 m barometric jitter around 100 m, then a real 10 m step.
    private var jitterThenStepProfile: [WorkoutElevationSample] {
        let noisy = (0..<10).map { index in
            WorkoutElevationSample(offset: Double(index) * 10, meters: index.isMultiple(of: 2) ? 100 : 101)
        }
        let step = (10..<20).map { index in
            WorkoutElevationSample(offset: Double(index) * 10, meters: 110)
        }
        return noisy + step
    }

    private func presentation(
        profile: [WorkoutElevationSample],
        duration: TimeInterval = 200,
        ascentMeters: Double? = nil,
        unit: BodyValueFormat.DistanceUnitPreference = .kilometers
    ) -> WorkoutElevationProfilePresentation? {
        WorkoutElevationProfilePresentation(
            profile: profile,
            workoutDuration: duration,
            ascentMeters: ascentMeters,
            distanceUnitPreference: unit,
            locale: locale
        )
    }

    func testAscentIgnoresJitterBelowHysteresis() throws {
        let presentation = try XCTUnwrap(presentation(profile: jitterThenStepProfile))

        // Only the 10 m step counts; the ±1 m jitter never clears the 3 m gate.
        XCTAssertEqual(presentation.ascentText, "10")
        XCTAssertEqual(presentation.maxElevationText, "110")
        XCTAssertEqual(presentation.unitText, "m")
        XCTAssertEqual(presentation.ascentCaption, "Ascent")
        XCTAssertEqual(presentation.maxCaption, "Max Elevation")
        XCTAssertEqual(presentation.title, "Elevation")
    }

    func testSummaryAscentWinsOverTheComputedTotal() throws {
        let presentation = try XCTUnwrap(presentation(profile: jitterThenStepProfile, ascentMeters: 137))

        XCTAssertEqual(presentation.ascentText, "137")
    }

    func testNonFiniteSummaryAscentFallsBackToTheProfile() throws {
        let presentation = try XCTUnwrap(presentation(profile: jitterThenStepProfile, ascentMeters: .nan))

        XCTAssertEqual(presentation.ascentText, "10")
    }

    func testAxisBracketsTheClimbOnRoundTicks() throws {
        let presentation = try XCTUnwrap(presentation(profile: jitterThenStepProfile))

        // 100…110 m padded by max(0.25, 1) = 1 → 99…111, snapped outward on the
        // 5 m grid to 95…115 (finer rungs would need more than six intervals).
        XCTAssertEqual(presentation.axisRange.lowerBound, 95, accuracy: 0.0001)
        XCTAssertEqual(presentation.axisRange.upperBound, 115, accuracy: 0.0001)
        XCTAssertEqual(presentation.yAxisLabels, ["95", "100", "105", "110", "115"])
        XCTAssertEqual(presentation.yAxisFractions.first, 0)
        XCTAssertEqual(presentation.yAxisFractions.last, 1)
        // The route now uses three quarters of the plot instead of half of it.
        XCTAssertEqual(try XCTUnwrap(presentation.points.first?.yFraction), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(presentation.points.last?.yFraction), 0.75, accuracy: 0.0001)
    }

    func testBelowSeaLevelIsNotClampedToZero() throws {
        let dip = (0..<10).map { WorkoutElevationSample(offset: Double($0) * 10, meters: -12) }
            + (10..<20).map { WorkoutElevationSample(offset: Double($0) * 10, meters: -4) }
        let presentation = try XCTUnwrap(presentation(profile: dip))

        // −12…−4 m padded by max(0.25, 0.8) = 0.8 → −12.8…−3.2, which 2 m ticks
        // (the finest rung fitting in six intervals) snap outward to −14…−2.
        XCTAssertEqual(presentation.axisRange.lowerBound, -14, accuracy: 0.0001)
        XCTAssertEqual(presentation.axisRange.upperBound, -2, accuracy: 0.0001)
    }

    func testImperialPreferenceConvertsToFeet() throws {
        let presentation = try XCTUnwrap(presentation(profile: jitterThenStepProfile, unit: .miles))

        XCTAssertEqual(presentation.unitText, "ft")
        XCTAssertEqual(presentation.ascentText, "33")
        XCTAssertEqual(presentation.maxElevationText, "361")
        // 328…361 ft padded by max(1, 3.3) = 3.3 → 324.8…364.2, which 8 ft ticks
        // (the finest rung fitting in six intervals) snap outward to 320…368.
        XCTAssertEqual(presentation.axisRange.lowerBound, 320, accuracy: 0.0001)
        XCTAssertEqual(presentation.axisRange.upperBound, 368, accuracy: 0.0001)
        XCTAssertEqual(presentation.yAxisLabels.first, "320")
        XCTAssertEqual(presentation.yAxisLabels.last, "368")
    }

    func testPointsAreClampedFractionsOfTheWorkoutTimeline() throws {
        // The last sample sits past the workout's end (route kept recording).
        var profile = jitterThenStepProfile
        profile.append(WorkoutElevationSample(offset: 260, meters: 110))
        let presentation = try XCTUnwrap(presentation(profile: profile, duration: 200))

        XCTAssertEqual(presentation.points.last?.xFraction, 1)
        XCTAssertEqual(presentation.points.map(\.xFraction), presentation.points.map(\.xFraction).sorted())
        XCTAssertEqual(presentation.timeMarks.map(\.label), ["00:00:00", "00:01:40", "00:03:20"])
    }

    func testHiddenWithTooFewSamples() {
        XCTAssertNil(presentation(profile: Array(jitterThenStepProfile.prefix(9))))
    }

    func testHiddenWhenTheRouteIsFlat() {
        let flat = (0..<20).map { WorkoutElevationSample(offset: Double($0) * 10, meters: 100) }

        XCTAssertNil(presentation(profile: flat))
    }

    func testHiddenWithoutADuration() {
        XCTAssertNil(presentation(profile: jitterThenStepProfile, duration: 0))
    }
}
