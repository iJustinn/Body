//
//  WorkoutShareCardTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
import UIKit
@testable import Body

final class WorkoutShareCardTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func workout(
        type: BodyWorkoutType,
        duration: TimeInterval = 1800,
        distance: Double? = nil,
        activeEnergy: Double? = nil,
        avgHR: Double? = nil,
        elevation: Double? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            type: type,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration,
            activeEnergyKilocalories: activeEnergy,
            distanceMeters: distance,
            averageHeartRateBeatsPerMinute: avgHR,
            elevationAscendedMeters: elevation
        )
    }

    private func presentation(
        for workout: WorkoutSummary,
        comparisonWorkouts: [WorkoutSummary]? = nil
    ) -> WorkoutDetailPresentation {
        WorkoutDetailPresentation(
            workout: workout,
            locale: enUS,
            unitPreference: .metric,
            comparisonWorkouts: comparisonWorkouts
        )
    }

    private func tile(_ kind: WorkoutDetailMetric.Kind, in presentation: WorkoutDetailPresentation) -> WorkoutDetailMetric? {
        presentation.detailMetrics.first { $0.kind == kind }
    }

    // MARK: - Metrics: per-type selection

    func testRunningRowIsPaceThenHeartRate() throws {
        let run = workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145)
        let presentation = presentation(for: run)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .running)
        let paceTile = try XCTUnwrap(tile(.pace, in: presentation))

        // Distance and duration render in the header (hero corner); energy is not
        // part of the card. The bottom-left row is the per-type extras only.
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].title, paceTile.title)
        XCTAssertEqual(metrics[0].value, paceTile.value)
        XCTAssertEqual(metrics[1].value, presentation.averageHeartRateText)
        XCTAssertFalse(metrics.contains { $0.value == presentation.durationClockText })
        XCTAssertFalse(metrics.contains { $0.value == presentation.activeEnergyText })
    }

    func testCyclingUsesAvgSpeed() {
        let ride = workout(type: .cycling, distance: 20_000, activeEnergy: 500)
        let presentation = presentation(for: ride)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .cycling)
        let speedTile = tile(.speed, in: presentation)

        XCTAssertNotNil(speedTile)
        XCTAssertTrue(metrics.contains { $0.title == speedTile?.title && $0.value == speedTile?.value })
    }

    func testDownhillSkiingIncludesElevation() throws {
        let ski = workout(type: .downhillSkiing, distance: 8000, activeEnergy: 400, elevation: 650)
        let presentation = presentation(for: ski)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .downhillSkiing)
        let elevationTile = try XCTUnwrap(tile(.elevation, in: presentation))

        XCTAssertTrue(metrics.contains { $0.title == elevationTile.title && $0.value == elevationTile.value })

        // Distance is promoted to the hero corner (snow sports promote it) and downhill
        // skiing has no pace/speed tile, so elevation leads the row.
        XCTAssertEqual(metrics.map(\.title), [elevationTile.title])
    }

    func testSwimmingUsesSwimPace() {
        let swim = workout(type: .swimming, duration: 2400, distance: 1500)
        let presentation = presentation(for: swim)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .swimming)
        let swimPaceTile = tile(.swimPace, in: presentation)

        XCTAssertNotNil(swimPaceTile)
        XCTAssertTrue(metrics.contains { $0.title == swimPaceTile?.title && $0.value == swimPaceTile?.value })
    }

    func testElevationNotIncludedForRunningOrCycling() throws {
        let run = presentation(for: workout(type: .running, distance: 5000, elevation: 300))
        let ride = presentation(for: workout(type: .cycling, distance: 20_000, elevation: 300))

        // The presentation itself DOES carry an elevation tile (elevation isn't gated by
        // type there) — the share builder is what must exclude it for these types.
        let runElevationTitle = try XCTUnwrap(tile(.elevation, in: run)).title
        let rideElevationTitle = try XCTUnwrap(tile(.elevation, in: ride)).title

        XCTAssertFalse(WorkoutShareMetricsBuilder.metrics(for: run, type: .running).contains { $0.title == runElevationTitle })
        XCTAssertFalse(WorkoutShareMetricsBuilder.metrics(for: ride, type: .cycling).contains { $0.title == rideElevationTitle })
    }

    func testHeroDistanceExcludedFromRowWhenPromoted() throws {
        let run = workout(type: .running, distance: 5000)
        let presentation = presentation(for: run)

        let heroValue = try XCTUnwrap(presentation.heroDistanceValue)
        let heroUnit = try XCTUnwrap(presentation.heroDistanceUnit)
        XCTAssertNil(tile(.distance, in: presentation))

        // The hero corner (fed by heroDistanceValue/Unit directly) owns distance;
        // the row must not duplicate it.
        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .running)
        XCTAssertFalse(metrics.contains { $0.value == "\(heroValue) \(heroUnit)" })
        XCTAssertFalse(metrics.contains { $0.title == String(localized: "Distance") })
    }

    func testDistanceTileUsedAsFallbackWhenNotPromoted() throws {
        // Rowing has no pace style and isn't a snow-sports type, so distance stays a
        // Details tile instead of being promoted to the hero header.
        let row = workout(type: .rowing, distance: 3000, activeEnergy: 250)
        let presentation = presentation(for: row)

        XCTAssertNil(presentation.heroDistanceValue)
        let distanceTile = try XCTUnwrap(tile(.distance, in: presentation))

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .rowing)
        XCTAssertEqual(metrics[0].title, distanceTile.title)
        XCTAssertEqual(metrics[0].value, distanceTile.value)
    }

    func testNilEnergyAndHeartRateProduceNoEmptyEntries() {
        let row = workout(type: .rowing, duration: 1200, distance: 3000)
        let presentation = presentation(for: row)
        XCTAssertNil(presentation.activeEnergyText)
        XCTAssertNil(presentation.averageHeartRateText)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .rowing)

        XCTAssertLessThanOrEqual(metrics.count, 3)
        XCTAssertFalse(metrics.contains { $0.title.isEmpty || $0.value.isEmpty })
        // Rowing doesn't promote distance, so the distance tile carries the row.
        XCTAssertTrue(metrics.contains { $0.value == presentation.distanceText })
    }

    func testAverageHeartRateAppearsWhenPresent() {
        let row = workout(type: .rowing, distance: 3000, avgHR: 130)
        let presentation = presentation(for: row)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .rowing)

        XCTAssertTrue(metrics.contains { $0.value == presentation.averageHeartRateText })
    }

    func testZeroDistanceStrengthTrainingRowHasNoDistanceOrPace() {
        let lift = workout(type: .strengthTraining, duration: 2700, distance: 0, activeEnergy: 200)
        let presentation = presentation(for: lift)

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .strengthTraining)

        // No rate/elevation/HR fixture data → an empty row; duration still shows on
        // the card via the header's durationClockText, which the row never carries.
        XCTAssertFalse(metrics.contains { $0.title == String(localized: "Distance") })
        XCTAssertFalse(metrics.contains { $0.value == presentation.durationClockText })
        XCTAssertTrue(metrics.isEmpty)
    }

    func testComparisonDataNeverAffectsSelectionOrLeaksIntoMetrics() {
        let current = workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145)
        let priors = (0..<5).map { _ in workout(type: .running, distance: 4800, activeEnergy: 300, avgHR: 140) }

        let withComparison = presentation(for: current, comparisonWorkouts: priors)
        let withoutComparison = presentation(for: current)

        // Sanity check: this fixture actually produces comparison badges, so the
        // "never copied" assertion below is meaningful rather than vacuous.
        XCTAssertTrue(withComparison.detailMetrics.contains { $0.comparison != nil })

        let metricsWithComparison = WorkoutShareMetricsBuilder.metrics(for: withComparison, type: .running)
        let metricsWithoutComparison = WorkoutShareMetricsBuilder.metrics(for: withoutComparison, type: .running)

        XCTAssertEqual(metricsWithComparison, metricsWithoutComparison)
    }

    // MARK: - Projection

    func testAntimeridianRouteUnwrapsWithoutInvertingOrder() throws {
        // A path moving eastward just across the antimeridian: 179.8° → 179.95° → -179.9°
        // (which is really 180.1° once unwrapped). Naive min/max longitude would treat
        // this as a ~360° span and scramble the ordering.
        let coordinates = [
            RouteCoordinate(latitude: 0, longitude: 179.8, speed: 0),
            RouteCoordinate(latitude: 0, longitude: 179.95, speed: 0),
            RouteCoordinate(latitude: 0, longitude: -179.9, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(points[1].x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(points[2].x, 1.0, accuracy: 1e-6)
        XCTAssertLessThan(points[0].x, points[1].x)
        XCTAssertLessThan(points[1].x, points[2].x)
    }

    func testVerticalOnlyRouteCentersXAtHalf() throws {
        let coordinates = [
            RouteCoordinate(latitude: 10.0, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 10.01, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 10.02, longitude: 20, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))

        XCTAssertTrue(points.allSatisfy { abs($0.x - 0.5) < 1e-9 })
    }

    func testHorizontalOnlyRouteCentersYAtHalf() throws {
        let coordinates = [
            RouteCoordinate(latitude: 10, longitude: 20.0, speed: 0),
            RouteCoordinate(latitude: 10, longitude: 20.01, speed: 0),
            RouteCoordinate(latitude: 10, longitude: 20.02, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))

        XCTAssertTrue(points.allSatisfy { abs($0.y - 0.5) < 1e-9 })
    }

    func testHighLatitudeRouteIsHorizontallyCompressedVsEquator() throws {
        // Same lat/lon deltas (2° lat, 1° lon) at the equator vs. near the pole — the
        // cos(latitude) correction should shrink the high-latitude route's x-spread.
        let equatorCoordinates = [
            RouteCoordinate(latitude: -1, longitude: -0.5, speed: 0),
            RouteCoordinate(latitude: 1, longitude: 0.5, speed: 0)
        ]
        let highLatitudeCoordinates = [
            RouteCoordinate(latitude: 69, longitude: -0.5, speed: 0),
            RouteCoordinate(latitude: 71, longitude: 0.5, speed: 0)
        ]

        let equatorPoints = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: equatorCoordinates))
        let highLatitudePoints = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: highLatitudeCoordinates))

        let equatorSpread = abs(equatorPoints[1].x - equatorPoints[0].x)
        let highLatitudeSpread = abs(highLatitudePoints[1].x - highLatitudePoints[0].x)

        XCTAssertLessThan(highLatitudeSpread, equatorSpread)
    }

    func testIdenticalPointsReturnNil() {
        let coordinates = [
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 10, longitude: 20, speed: 3)
        ]

        XCTAssertNil(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
    }

    func testGPSNoiseScaleRouteReturnsNil() {
        // A stationary "route" whose fixes differ only by ordinary GPS jitter
        // (~1–2 m ≈ 1e-5°) must fall back to a metrics-only card, not blow the
        // noise up into a full-size trace.
        let coordinates = (0..<20).map { index in
            RouteCoordinate(
                latitude: 10 + Double(index % 3) * 1e-5,
                longitude: 20 + Double(index % 4) * 1e-5,
                speed: 0
            )
        }

        XCTAssertNil(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
    }

    func testFewerThanTwoPointsReturnNil() {
        XCTAssertNil(WorkoutShareRouteProjection.normalizedPoints(for: []))
        XCTAssertNil(WorkoutShareRouteProjection.normalizedPoints(for: [RouteCoordinate(latitude: 1, longitude: 1, speed: 0)]))
    }

    func testNonFiniteCoordinatesAreDropped() throws {
        let coordinates = [
            RouteCoordinate(latitude: .nan, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 10, longitude: .infinity, speed: 0),
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 11, longitude: 21, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
        XCTAssertEqual(points.count, 2)
    }

    func testNonFiniteCoordinatesDroppedBelowMinimumReturnNil() {
        let coordinates = [
            RouteCoordinate(latitude: .nan, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0)
        ]

        XCTAssertNil(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
    }

    func testExactlyTwoValidPointsAreValid() throws {
        let coordinates = [
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 11, longitude: 21, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
        XCTAssertEqual(points.count, 2)
    }

    func testRouteIsNorthUpMaxLatitudeHasMinimumY() throws {
        let coordinates = [
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 15, longitude: 20.5, speed: 0),
            RouteCoordinate(latitude: 8, longitude: 19.5, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
        let minY = try XCTUnwrap(points.map(\.y).min())

        // Index 1 has the highest latitude (15°) and should sit highest on the card.
        XCTAssertEqual(points[1].y, minY, accuracy: 1e-9)
    }

    func testClosedLoopWorks() throws {
        let coordinates = [
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0),
            RouteCoordinate(latitude: 10.5, longitude: 20.5, speed: 0),
            RouteCoordinate(latitude: 10, longitude: 20, speed: 0)
        ]

        let points = try XCTUnwrap(WorkoutShareRouteProjection.normalizedPoints(for: coordinates))
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0], points[2])
    }

    // MARK: - Preset / Pro photo policy

    func testStoredRoundTripsEveryPresetCase() {
        for preset in BodyWorkoutSharePreset.allCases {
            XCTAssertEqual(BodyWorkoutSharePreset.stored(rawValue: preset.rawValue), preset)
        }
    }

    func testStoredFallsBackToMidnightForNilOrGarbage() {
        XCTAssertEqual(BodyWorkoutSharePreset.stored(rawValue: nil), .midnight)
        XCTAssertEqual(BodyWorkoutSharePreset.stored(rawValue: "not-a-real-preset"), .midnight)
        XCTAssertEqual(BodyWorkoutSharePreset.stored(rawValue: ""), .midnight)
    }

    func testResolvedPhotoReturnsNilForNonProEvenWithAPhoto() {
        let photo = UIImage()
        XCTAssertNil(WorkoutShareBackgroundPolicy.resolvedPhoto(photo, isProUnlocked: false))
    }

    func testResolvedPhotoReturnsThePhotoForPro() {
        let photo = UIImage()
        XCTAssertTrue(WorkoutShareBackgroundPolicy.resolvedPhoto(photo, isProUnlocked: true) === photo)
    }

    func testResolvedPhotoWithNilPhotoReturnsNilRegardlessOfEntitlement() {
        XCTAssertNil(WorkoutShareBackgroundPolicy.resolvedPhoto(nil, isProUnlocked: true))
        XCTAssertNil(WorkoutShareBackgroundPolicy.resolvedPhoto(nil, isProUnlocked: false))
    }
}
