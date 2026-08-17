//
//  WorkoutShareCardTests.swift
//  BodyTests
//

import XCTest
import CoreGraphics
import SwiftUI
import UIKit
@testable import Body

final class WorkoutShareCardTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    /// The default share card, and the widest landscape one — the two shapes the
    /// transform clamps have to behave differently on.
    private let portraitCard = CGSize(width: 360, height: 640)
    private let landscapeCard = CGSize(width: 640, height: 360)

    private func geometry(
        _ ratio: WorkoutShareAspectRatio,
        layout: WorkoutShareCardLayout = .centered,
        arrangement: WorkoutShareLandscapeArrangement = .stacked
    ) -> WorkoutShareCardGeometry {
        WorkoutShareCardGeometry(aspectRatio: ratio, layout: layout, arrangement: arrangement)
    }

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
        comparisonWorkouts: [WorkoutSummary]? = nil,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference = .kilocalories
    ) -> WorkoutDetailPresentation {
        WorkoutDetailPresentation(
            workout: workout,
            locale: enUS,
            unitPreference: .metric,
            energyUnitPreference: energyUnitPreference,
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

        XCTAssertLessThanOrEqual(metrics.count, 2)
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

    func testRowCapsAtTwoMetricsAndDropsHeartRate() throws {
        // Hiking is the fixture that actually produces three candidates: it's
        // `.distancePace` (pace tile), it promotes distance to the hero corner (so the
        // distance-fallback candidate is skipped), and it's elevation-eligible — so
        // pace + elevation + avg HR all qualify and the cap has to drop the last one.
        let hike = workout(type: .hiking, duration: 5400, distance: 9000, activeEnergy: 600, avgHR: 128, elevation: 540)
        let presentation = presentation(for: hike)

        let paceTile = try XCTUnwrap(tile(.pace, in: presentation))
        let elevationTile = try XCTUnwrap(tile(.elevation, in: presentation))
        // Sanity check: HR really is a candidate here, so "dropped" below isn't vacuous.
        let heartRateText = try XCTUnwrap(presentation.averageHeartRateText)
        XCTAssertNotNil(tile(.avgHeartRate, in: presentation))

        let metrics = WorkoutShareMetricsBuilder.metrics(for: presentation, type: .hiking)

        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics.map(\.title), [paceTile.title, elevationTile.title])
        XCTAssertEqual(metrics.map(\.value), [paceTile.value, elevationTile.value])
        XCTAssertFalse(metrics.contains { $0.value == heartRateText })
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

    func testCalculatingStandInsNeverLeakIntoMetrics() {
        // The share sheet is handed the detail's own presentation, so the "0%" stand-ins
        // shown while the 30-day history loads travel there too. They must be as invisible
        // to the share card as a measured badge is.
        let current = workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145)
        let priors = (0..<5).map { _ in workout(type: .running, distance: 4800, activeEnergy: 300, avgHR: 140) }

        let calculating = WorkoutDetailPresentation(
            workout: current,
            locale: enUS,
            unitPreference: .metric,
            comparisonWorkouts: priors,
            comparisonDataComplete: false,
            comparisonLoadSettled: false
        )

        XCTAssertEqual(calculating.comparisonAvailability, .calculating)
        XCTAssertTrue(calculating.detailMetrics.contains { $0.comparison?.badgeText == "0%" })
        XCTAssertEqual(
            WorkoutShareMetricsBuilder.metrics(for: calculating, type: .running),
            WorkoutShareMetricsBuilder.metrics(for: presentation(for: current), type: .running)
        )
    }

    // MARK: - Metrics: centered layout

    func testCenteredRunningIsDistancePaceTime() throws {
        let run = workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145)
        let presentation = presentation(for: run)

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .running)
        let heroValue = try XCTUnwrap(presentation.heroDistanceValue)
        let heroUnit = try XCTUnwrap(presentation.heroDistanceUnit)
        let paceTile = try XCTUnwrap(tile(.pace, in: presentation))

        XCTAssertEqual(
            metrics.map(\.title),
            [String(localized: "Distance"), String(localized: "Pace"), String(localized: "Time")]
        )
        XCTAssertEqual(
            metrics.map(\.value),
            ["\(heroValue) \(heroUnit)", paceTile.value, presentation.durationClockText]
        )
        // The three leaders fill every slot, so avg HR never reaches the stack.
        XCTAssertFalse(metrics.contains { $0.value == presentation.averageHeartRateText })
    }

    func testCenteredCyclingLabelsTheRateSpeed() throws {
        let ride = workout(type: .cycling, distance: 20_000, activeEnergy: 500)
        let presentation = presentation(for: ride)

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .cycling)
        let speedTile = try XCTUnwrap(tile(.speed, in: presentation))

        // The tile's own title is "Avg Speed"; the centered layout wants the short label
        // with the same value.
        XCTAssertNotEqual(speedTile.title, String(localized: "Speed"))
        XCTAssertEqual(metrics[1].title, String(localized: "Speed"))
        XCTAssertEqual(metrics[1].value, speedTile.value)
    }

    func testCenteredSwimmingLabelsTheRatePace() throws {
        let swim = workout(type: .swimming, duration: 2400, distance: 1500)
        let presentation = presentation(for: swim)

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .swimming)
        let swimPaceTile = try XCTUnwrap(tile(.swimPace, in: presentation))

        XCTAssertEqual(metrics[1].title, String(localized: "Pace"))
        XCTAssertEqual(metrics[1].value, swimPaceTile.value)
    }

    func testCenteredDownhillSkiingFillsTheRateSlotWithElevation() throws {
        let ski = workout(type: .downhillSkiing, distance: 8000, activeEnergy: 400, avgHR: 130, elevation: 650)
        let presentation = presentation(for: ski)

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .downhillSkiing)
        let elevationTile = try XCTUnwrap(tile(.elevation, in: presentation))

        // No pace/speed tile for this type, so the leaders only fill two slots and
        // elevation takes the third — ahead of the avg HR this fixture also carries.
        XCTAssertEqual(
            metrics.map(\.title),
            [String(localized: "Distance"), String(localized: "Time"), elevationTile.title]
        )
        XCTAssertEqual(metrics[2].value, elevationTile.value)
        XCTAssertFalse(metrics.contains { $0.value == presentation.averageHeartRateText })
    }

    func testCenteredDistancelessStrengthTrainingKeepsTimeAndFillsWithHeartRate() throws {
        let lift = workout(type: .strengthTraining, duration: 2700, activeEnergy: 200, avgHR: 122)
        let presentation = presentation(for: lift)

        XCTAssertNil(presentation.heroDistanceValue)
        XCTAssertNil(tile(.distance, in: presentation))
        let heartRateText = try XCTUnwrap(presentation.averageHeartRateText)

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .strengthTraining)

        // Missing distance and rate must collapse, not leave placeholder blocks.
        XCTAssertFalse(metrics.contains { $0.title.isEmpty || $0.value.isEmpty })
        XCTAssertEqual(metrics.map(\.value), [presentation.durationClockText, heartRateText])
    }

    func testCenteredNeverExceedsThreeMetrics() {
        // Hiking is the fixture with the most candidates: distance, pace, time,
        // elevation, and avg HR all qualify.
        let hike = workout(type: .hiking, duration: 5400, distance: 9000, activeEnergy: 600, avgHR: 128, elevation: 540)
        let presentation = presentation(for: hike)

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .hiking)

        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(
            metrics.map(\.title),
            [String(localized: "Distance"), String(localized: "Pace"), String(localized: "Time")]
        )
    }

    func testCenteredUsesDistanceTileWhenNotPromoted() throws {
        // Rowing keeps distance as a Details tile instead of promoting it to the hero.
        let row = workout(type: .rowing, distance: 3000, activeEnergy: 250)
        let presentation = presentation(for: row)

        XCTAssertNil(presentation.heroDistanceValue)
        let distanceTile = try XCTUnwrap(tile(.distance, in: presentation))

        let metrics = WorkoutShareMetricsBuilder.centeredMetrics(for: presentation, type: .rowing)

        XCTAssertEqual(metrics[0].title, distanceTile.title)
        XCTAssertEqual(metrics[0].value, distanceTile.value)
    }

    // MARK: - Metrics: routeless

    func testRoutelessStrengthTrainingIsTimeEnergyHeartRate() throws {
        let lift = workout(type: .strengthTraining, duration: 2700, activeEnergy: 200, avgHR: 122)
        let presentation = presentation(for: lift)

        let energyTile = try XCTUnwrap(tile(.activeEnergy, in: presentation))
        let heartRateTile = try XCTUnwrap(tile(.avgHeartRate, in: presentation))

        let metrics = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: .strengthTraining)

        XCTAssertEqual(
            metrics.map(\.title),
            [String(localized: "Time"), energyTile.title, heartRateTile.title]
        )
        XCTAssertEqual(
            metrics.map(\.value),
            [presentation.durationClockText, energyTile.value, heartRateTile.value]
        )
    }

    func testRoutelessRunningIsDistancePaceTimeAndDropsEnergyAndHeartRate() throws {
        let run = workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145)
        let presentation = presentation(for: run)

        let heroValue = try XCTUnwrap(presentation.heroDistanceValue)
        let heroUnit = try XCTUnwrap(presentation.heroDistanceUnit)
        let paceTile = try XCTUnwrap(tile(.pace, in: presentation))
        let energyTile = try XCTUnwrap(tile(.activeEnergy, in: presentation))
        let heartRateText = try XCTUnwrap(presentation.averageHeartRateText)

        let metrics = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: .running)

        // Three slots, same as the centered card: the leaders fill them all, so the
        // energy this layout also offers never reaches the stack here.
        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(
            metrics.map(\.title),
            [String(localized: "Distance"), String(localized: "Pace"), String(localized: "Time")]
        )
        XCTAssertEqual(
            metrics.map(\.value),
            ["\(heroValue) \(heroUnit)", paceTile.value, presentation.durationClockText]
        )
        XCTAssertFalse(metrics.contains { $0.title == energyTile.title })
        XCTAssertFalse(metrics.contains { $0.value == heartRateText })
    }

    func testRoutelessWithNilEnergyOmitsEnergyMetricAndNeverShowsNoData() {
        let lift = workout(type: .strengthTraining, duration: 2700, avgHR: 122)
        let presentation = presentation(for: lift)
        XCTAssertNil(presentation.activeEnergyText)

        let metrics = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: .strengthTraining)

        XCTAssertFalse(metrics.contains { $0.title == "Active kcal" })
        XCTAssertFalse(metrics.contains { $0.value.contains("No Data") })
    }

    func testRoutelessCapsAtThreeMetricsAndDropsElevationAndHeartRate() throws {
        // Downhill skiing with everything recorded: distance (hero), no pace/speed
        // candidate, time, energy, elevation, and avg HR all qualify — so the cap has
        // to drop the last two even though they're real candidates.
        let ski = workout(type: .downhillSkiing, distance: 8000, activeEnergy: 400, avgHR: 130, elevation: 650)
        let presentation = presentation(for: ski)

        let heroValue = try XCTUnwrap(presentation.heroDistanceValue)
        let heroUnit = try XCTUnwrap(presentation.heroDistanceUnit)
        let energyTile = try XCTUnwrap(tile(.activeEnergy, in: presentation))
        let elevationTile = try XCTUnwrap(tile(.elevation, in: presentation))
        let heartRateText = try XCTUnwrap(presentation.averageHeartRateText)
        XCTAssertNotNil(tile(.avgHeartRate, in: presentation))

        let metrics = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: .downhillSkiing)

        XCTAssertEqual(metrics.count, 3)
        XCTAssertEqual(
            metrics.map(\.title),
            [String(localized: "Distance"), String(localized: "Time"), energyTile.title]
        )
        XCTAssertEqual(metrics[0].value, "\(heroValue) \(heroUnit)")
        XCTAssertEqual(metrics[2].value, energyTile.value)
        XCTAssertFalse(metrics.contains { $0.title == elevationTile.title })
        XCTAssertFalse(metrics.contains { $0.value == heartRateText })
    }

    func testRoutelessEnergyTitleMatchesTheActiveEnergyTile() throws {
        let lift = workout(type: .strengthTraining, duration: 2700, activeEnergy: 200)
        let presentation = presentation(for: lift)

        let energyTile = try XCTUnwrap(tile(.activeEnergy, in: presentation))
        let metrics = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: .strengthTraining)

        XCTAssertTrue(metrics.contains { $0.title == energyTile.title })
    }

    func testRoutelessEnergyUsesKilojoulesTitleAndValueWhenPreferred() throws {
        let lift = workout(type: .strengthTraining, duration: 2700, activeEnergy: 200)
        let presentation = presentation(for: lift, energyUnitPreference: .kilojoules)

        let energyTile = try XCTUnwrap(tile(.activeEnergy, in: presentation))
        XCTAssertEqual(energyTile.title, "Active kJ")

        let metrics = WorkoutShareMetricsBuilder.routelessMetrics(for: presentation, type: .strengthTraining)
        let energyMetric = try XCTUnwrap(metrics.first { $0.title == energyTile.title })

        XCTAssertEqual(energyMetric.title, "Active kJ")
        XCTAssertEqual(energyMetric.value, energyTile.value)
        XCTAssertTrue(energyMetric.value.contains("kJ"))
    }

    // MARK: - Metrics: pickable pool

    /// Every `WorkoutDetailMetric.Kind`, spelled out: `Kind` isn't `CaseIterable`, so a
    /// new case has to be added here (and to `key(for:)`) by hand.
    private let allMetricKinds: [WorkoutDetailMetric.Kind] = [
        .activeEnergy, .totalEnergy, .avgHeartRate, .maxHeartRate, .distance,
        .pace, .speed, .swimPace, .elevation, .stepCadence, .cyclingCadence,
        .power, .cardioFitness, .strokeCount, .humidity, .averageMETs, .heartRateRecovery
    ]

    func testMetricKeysAreUniqueAcrossEveryKind() {
        let keys = allMetricKinds.map { WorkoutShareMetricOption.key(for: $0) }

        XCTAssertEqual(Set(keys).count, allMetricKinds.count, "Two Kinds share a stored id: \(keys)")
        XCTAssertFalse(keys.contains { $0.isEmpty })
        // The two synthetic ids must not collide with a tile's id either.
        XCTAssertFalse(keys.contains(WorkoutShareMetricOption.timeID))
        XCTAssertEqual(WorkoutShareMetricOption.key(for: .distance), WorkoutShareMetricOption.distanceID)
    }

    func testAvailableMetricsLeadWithDistanceRateThenTime() throws {
        let run = workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145)
        let presentation = presentation(for: run)

        let options = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: .running)

        // Distance, the type's rate, and time lead; the remaining Details tiles follow
        // in Details order. Total energy is a "No Data" tile for this fixture and drops.
        XCTAssertEqual(options.map(\.id), ["distance", "pace", "time", "activeEnergy", "avgHeartRate"])

        let heroValue = try XCTUnwrap(presentation.heroDistanceValue)
        let heroUnit = try XCTUnwrap(presentation.heroDistanceUnit)
        let paceTile = try XCTUnwrap(tile(.pace, in: presentation))
        XCTAssertEqual(options[0].value, "\(heroValue) \(heroUnit)")
        XCTAssertEqual(options[0].tileTitle, String(localized: "Distance"))
        XCTAssertEqual(options[1].tileTitle, paceTile.title)
        XCTAssertEqual(options[2].value, presentation.durationClockText)
        XCTAssertNil(options[2].kind)
    }

    func testAvailableMetricsNeverDuplicateDistanceOrTheRateTile() {
        let row = workout(type: .rowing, distance: 3000, activeEnergy: 250)
        let promoted = presentation(for: workout(type: .running, distance: 5000, activeEnergy: 320))
        let tileBased = presentation(for: row)

        for (presentation, type) in [(promoted, BodyWorkoutType.running), (tileBased, .rowing)] {
            let options = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: type)
            XCTAssertEqual(options.filter { $0.id == "distance" }.count, 1)
            XCTAssertEqual(options.map(\.id).count, Set(options.map(\.id)).count)
        }

        // The rate tile is placed up front, so the Details pass must skip it.
        let ride = presentation(for: workout(type: .cycling, distance: 20_000, activeEnergy: 500))
        let rideOptions = WorkoutShareMetricsBuilder.availableMetrics(for: ride, type: .cycling)
        XCTAssertEqual(rideOptions.filter { $0.id == "speed" }.count, 1)
        XCTAssertEqual(rideOptions.map(\.id), ["distance", "speed", "time", "activeEnergy"])
    }

    func testAvailableMetricsDropTheNoDataTiles() {
        let lift = workout(type: .strengthTraining, duration: 2700)
        let presentation = presentation(for: lift)

        // Details still renders these three, reading "No Data" — the card never may.
        XCTAssertNotNil(tile(.activeEnergy, in: presentation))
        XCTAssertNotNil(tile(.totalEnergy, in: presentation))
        XCTAssertNotNil(tile(.avgHeartRate, in: presentation))

        let options = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: .strengthTraining)

        XCTAssertEqual(options.map(\.id), ["time"])
        XCTAssertFalse(options.contains { $0.value.contains("No Data") })
    }

    func testAvailableMetricsKeepElevationForTypesThatDontClimb() throws {
        // The pool is what Details shows; elevation eligibility only decides defaults.
        let run = workout(type: .running, distance: 5000, elevation: 300)
        let presentation = presentation(for: run)
        let elevationTile = try XCTUnwrap(tile(.elevation, in: presentation))

        let options = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: .running)
        let elevation = try XCTUnwrap(options.first { $0.id == "elevation" })

        XCTAssertEqual(elevation.tileTitle, elevationTile.title)
        XCTAssertFalse(
            WorkoutShareMetricsBuilder.defaultMetricIDs(for: presentation, type: .running, hasRoute: true)
                .contains("elevation")
        )
    }

    func testMetricOptionProjectionsRelabelOnlyTheRate() throws {
        let ride = presentation(for: workout(type: .cycling, distance: 20_000, activeEnergy: 500))
        let options = WorkoutShareMetricsBuilder.availableMetrics(for: ride, type: .cycling)
        let speed = try XCTUnwrap(options.first { $0.id == "speed" })
        let energy = try XCTUnwrap(options.first { $0.id == "activeEnergy" })
        let speedTile = try XCTUnwrap(tile(.speed, in: ride))

        XCTAssertEqual(speed.classicMetric, WorkoutShareMetric(title: speedTile.title, value: speedTile.value))
        XCTAssertEqual(speed.centeredMetric, WorkoutShareMetric(title: String(localized: "Speed"), value: speedTile.value))
        XCTAssertEqual(energy.classicMetric, energy.centeredMetric)

        let swim = presentation(for: workout(type: .swimming, duration: 2400, distance: 1500))
        let swimOptions = WorkoutShareMetricsBuilder.availableMetrics(for: swim, type: .swimming)
        let swimPace = try XCTUnwrap(swimOptions.first { $0.id == "swimPace" })
        XCTAssertEqual(swimPace.centeredMetric.title, String(localized: "Pace"))
    }

    // MARK: - Metrics: defaults

    func testDefaultMetricIDsReproduceTheAutomaticSelections() {
        let run = presentation(for: workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145))
        let walk = presentation(for: workout(type: .walking, duration: 3600, distance: 5000, activeEnergy: 200, avgHR: 110))
        let ride = presentation(for: workout(type: .cycling, distance: 20_000, activeEnergy: 500))
        let ski = presentation(for: workout(type: .downhillSkiing, distance: 8000, activeEnergy: 400, avgHR: 130, elevation: 650))
        let lift = presentation(for: workout(type: .strengthTraining, duration: 2700, activeEnergy: 200, avgHR: 122))

        func routed(_ presentation: WorkoutDetailPresentation, _ type: BodyWorkoutType) -> [String] {
            WorkoutShareMetricsBuilder.defaultMetricIDs(for: presentation, type: type, hasRoute: true)
        }
        func routeless(_ presentation: WorkoutDetailPresentation, _ type: BodyWorkoutType) -> [String] {
            WorkoutShareMetricsBuilder.defaultMetricIDs(for: presentation, type: type, hasRoute: false)
        }

        XCTAssertEqual(routed(run, .running), ["distance", "pace", "time"])
        XCTAssertEqual(routed(walk, .walking), ["distance", "pace", "time"])
        XCTAssertEqual(routed(ride, .cycling), ["distance", "speed", "time"])
        // No rate tile for downhill skiing, so elevation takes the freed slot.
        XCTAssertEqual(routed(ski, .downhillSkiing), ["distance", "time", "elevation"])
        XCTAssertEqual(routed(lift, .strengthTraining), ["time", "avgHeartRate"])

        // The route-less card offers active energy, but is capped at three like the rest.
        XCTAssertEqual(routeless(run, .running), ["distance", "pace", "time"])
        XCTAssertEqual(routeless(ski, .downhillSkiing), ["distance", "time", "activeEnergy"])
        XCTAssertEqual(routeless(lift, .strengthTraining), ["time", "activeEnergy", "avgHeartRate"])
    }

    func testDefaultMetricIDsDriveTheAutomaticStacks() {
        let hike = presentation(for: workout(type: .hiking, duration: 5400, distance: 9000, activeEnergy: 600, avgHR: 128, elevation: 540))
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: hike, type: .hiking)
        let defaults = WorkoutShareMetricsBuilder.defaultMetricIDs(for: hike, type: .hiking, hasRoute: true)

        XCTAssertEqual(
            WorkoutShareMetricsBuilder.centeredMetrics(for: hike, type: .hiking),
            defaults.compactMap { id in available.first { $0.id == id }?.centeredMetric }
        )
    }

    // MARK: - Metrics: stored selection

    func testStoredSelectionRoundTripsPerWorkoutType() {
        let runOnly = WorkoutShareMetricSelection.storing(["pace", "time"], for: .running, into: nil)

        XCTAssertEqual(WorkoutShareMetricSelection.stored(json: runOnly, type: .running), ["pace", "time"])
        XCTAssertNil(WorkoutShareMetricSelection.stored(json: runOnly, type: .cycling))

        let both = WorkoutShareMetricSelection.storing(["speed"], for: .cycling, into: runOnly)
        XCTAssertEqual(WorkoutShareMetricSelection.stored(json: both, type: .running), ["pace", "time"])
        XCTAssertEqual(WorkoutShareMetricSelection.stored(json: both, type: .cycling), ["speed"])

        let replaced = WorkoutShareMetricSelection.storing(["distance"], for: .running, into: both)
        XCTAssertEqual(WorkoutShareMetricSelection.stored(json: replaced, type: .running), ["distance"])
        XCTAssertEqual(WorkoutShareMetricSelection.stored(json: replaced, type: .cycling), ["speed"])
    }

    func testStoredSelectionTreatsMissingOrMalformedBlobsAsNoPreference() {
        XCTAssertNil(WorkoutShareMetricSelection.stored(json: nil, type: .running))
        XCTAssertNil(WorkoutShareMetricSelection.stored(json: "", type: .running))
        XCTAssertNil(WorkoutShareMetricSelection.stored(json: "{not json", type: .running))
        XCTAssertNil(WorkoutShareMetricSelection.stored(json: "{\"running\": \"pace\"}", type: .running))
        XCTAssertNil(WorkoutShareMetricSelection.stored(json: "{\"running\": []}", type: .running))

        // Writing over an unreadable blob starts fresh instead of failing the write.
        let recovered = WorkoutShareMetricSelection.storing(["pace"], for: .running, into: "{not json")
        XCTAssertEqual(WorkoutShareMetricSelection.stored(json: recovered, type: .running), ["pace"])
    }

    func testResolvedSelectionIntersectsWithWhatTheWorkoutHas() {
        let run = presentation(for: workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145))
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: run, type: .running)
        let defaults = WorkoutShareMetricsBuilder.defaultMetricIDs(for: run, type: .running, hasRoute: true)

        // Stored in tap order, and half of it isn't in this workout: the survivors come
        // back in pool order, deduped and capped.
        XCTAssertEqual(
            WorkoutShareMetricSelection.resolved(
                stored: ["avgHeartRate", "elevation", "pace", "avgHeartRate"],
                available: available,
                defaults: defaults
            ),
            ["pace", "avgHeartRate"]
        )
        XCTAssertEqual(
            WorkoutShareMetricSelection.resolved(
                stored: ["avgHeartRate", "activeEnergy", "time", "distance", "pace"],
                available: available,
                defaults: defaults
            ),
            ["distance", "pace", "time"]
        )
        // Nothing stored, or nothing that survives, falls back to the automatic pick.
        XCTAssertEqual(WorkoutShareMetricSelection.resolved(stored: nil, available: available, defaults: defaults), defaults)
        XCTAssertEqual(
            WorkoutShareMetricSelection.resolved(stored: ["elevation", "power"], available: available, defaults: defaults),
            defaults
        )
    }

    func testTogglingRespectsTheOneToThreeBoundsAndPoolOrder() {
        let run = presentation(for: workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145))
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: run, type: .running)
        let defaults = WorkoutShareMetricsBuilder.defaultMetricIDs(for: run, type: .running, hasRoute: true)

        // First edit starts from the resolved defaults: unticking one leaves the rest.
        XCTAssertEqual(
            WorkoutShareMetricSelection.toggling("time", in: defaults, available: available),
            ["distance", "pace"]
        )
        // Adding comes back in pool order, not tap order.
        XCTAssertEqual(
            WorkoutShareMetricSelection.toggling("distance", in: ["avgHeartRate"], available: available),
            ["distance", "avgHeartRate"]
        )
        // Already three picked: another tap is a no-op.
        XCTAssertEqual(
            WorkoutShareMetricSelection.toggling("avgHeartRate", in: defaults, available: available),
            defaults
        )
        // The last one standing can't be removed.
        XCTAssertEqual(WorkoutShareMetricSelection.toggling("pace", in: ["pace"], available: available), ["pace"])
        // An id this workout doesn't have can't be added.
        XCTAssertEqual(WorkoutShareMetricSelection.toggling("elevation", in: ["pace"], available: available), ["pace"])
    }

    func testResolvedMetricIDsFallBackToDefaultsWithoutPro() {
        let picked = ["pace", "avgHeartRate"]
        let defaults = ["distance", "pace", "time"]

        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedMetricIDs(picked, defaults: defaults, isProUnlocked: true),
            picked
        )
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedMetricIDs(picked, defaults: defaults, isProUnlocked: false),
            defaults
        )
    }

    // MARK: - Metrics: classic row from a selection

    func testClassicRowMetricsFromDefaultsMatchTheAutomaticRow() {
        let fixtures: [(WorkoutSummary, BodyWorkoutType)] = [
            (workout(type: .running, distance: 5000, activeEnergy: 320, avgHR: 145), .running),
            (workout(type: .cycling, distance: 20_000, activeEnergy: 500), .cycling),
            (workout(type: .downhillSkiing, distance: 8000, activeEnergy: 400, elevation: 650), .downhillSkiing),
            (workout(type: .hiking, duration: 5400, distance: 9000, activeEnergy: 600, avgHR: 128, elevation: 540), .hiking),
            (workout(type: .rowing, distance: 3000, activeEnergy: 250), .rowing),
            (workout(type: .strengthTraining, duration: 2700, distance: 0, activeEnergy: 200), .strengthTraining)
        ]

        for (summary, type) in fixtures {
            let presentation = presentation(for: summary)
            let row = WorkoutShareMetricsBuilder.classicRowMetrics(
                selectedIDs: WorkoutShareMetricsBuilder.defaultMetricIDs(for: presentation, type: type, hasRoute: true),
                available: WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: type),
                presentation: presentation,
                type: type
            )
            XCTAssertEqual(row, WorkoutShareMetricsBuilder.metrics(for: presentation, type: type), "\(type)")
            XCTAssertLessThanOrEqual(row.count, 2, "\(type)")
        }
    }

    func testClassicRowMetricsDropTheHeaderMetricsAndCapAtTwo() throws {
        let ski = workout(type: .downhillSkiing, distance: 8000, activeEnergy: 400, avgHR: 130, elevation: 650)
        let presentation = presentation(for: ski)
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: .downhillSkiing)
        let elevationTile = try XCTUnwrap(tile(.elevation, in: presentation))
        let heartRateTile = try XCTUnwrap(tile(.avgHeartRate, in: presentation))
        XCTAssertNotNil(presentation.heroDistanceValue)

        // "pace" isn't available on this workout and drops; distance and time are the
        // header's, so the row is the two remaining picks.
        let row = WorkoutShareMetricsBuilder.classicRowMetrics(
            selectedIDs: ["distance", "time", "pace", "elevation", "avgHeartRate"],
            available: available,
            presentation: presentation,
            type: .downhillSkiing
        )

        XCTAssertEqual(row.map(\.title), [elevationTile.title, heartRateTile.title])
        XCTAssertEqual(row.map(\.value), [elevationTile.value, heartRateTile.value])
    }

    func testClassicRowMetricsKeepDistanceWhenTheHeaderHasNone() throws {
        let row = workout(type: .rowing, distance: 3000, activeEnergy: 250, avgHR: 130)
        let presentation = presentation(for: row)
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: .rowing)
        let distanceTile = try XCTUnwrap(tile(.distance, in: presentation))
        XCTAssertNil(presentation.heroDistanceValue)

        let metrics = WorkoutShareMetricsBuilder.classicRowMetrics(
            selectedIDs: ["distance", "time"],
            available: available,
            presentation: presentation,
            type: .rowing
        )

        // Distance survives (no hero corner to carry it), time never does, and the
        // freed slot is backfilled with the row's classic extra.
        XCTAssertEqual(metrics.map(\.title), [distanceTile.title, String(localized: "Avg Heart Rate")])
    }

    func testClassicRowMetricsBackfillOnlyUpToTwo() throws {
        let hike = workout(type: .hiking, duration: 5400, distance: 9000, activeEnergy: 600, avgHR: 128, elevation: 540)
        let presentation = presentation(for: hike)
        let available = WorkoutShareMetricsBuilder.availableMetrics(for: presentation, type: .hiking)
        let energyTile = try XCTUnwrap(tile(.activeEnergy, in: presentation))
        let paceTile = try XCTUnwrap(tile(.pace, in: presentation))

        // One explicit pick survives the header rule, so exactly one backfill joins it.
        let metrics = WorkoutShareMetricsBuilder.classicRowMetrics(
            selectedIDs: ["distance", "activeEnergy"],
            available: available,
            presentation: presentation,
            type: .hiking
        )

        XCTAssertEqual(metrics.map(\.title), [energyTile.title, paceTile.title])
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

    // MARK: - Background choice / Pro photo policy

    func testStoredRoundTripsEveryBackgroundChoice() {
        for preset in BodyWorkoutSharePreset.allCases {
            let choice = BodyWorkoutShareBackgroundChoice.preset(preset)
            XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: choice.rawValue, hasRoute: true), choice)
        }

        // The map is a choice of its own, not a preset — it has to survive the same
        // round trip through @AppStorage that the gradients do.
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.map.rawValue, "map")
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: "map", hasRoute: true), .map)
    }

    func testStoredFallsBackToMidnightForNilOrGarbage() {
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: nil, hasRoute: true), .preset(.midnight))
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: "", hasRoute: true), .preset(.midnight))
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: "not-a-real-preset", hasRoute: true), .preset(.midnight))
        // "ocean" is a retired preset: a stored value from an old build is now unknown
        // and must resolve to the Midnight default rather than crashing or mapping.
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: "ocean", hasRoute: true), .preset(.midnight))
        // The map only ever comes back from an explicit pick, never as a fallback.
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: "map", hasRoute: true), .map)
    }

    func testStoredMapWithoutARouteFallsBackToMidnightForTheSession() {
        // A route-less workout can never see the map background: a stored "map" from an
        // earlier routed share resolves to Midnight for this session without rewriting
        // the key, so the next routed share still opens on the map.
        XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: "map", hasRoute: false), .preset(.midnight))
    }

    func testStoredPresetsAreUnaffectedByHasRoute() {
        for preset in BodyWorkoutSharePreset.allCases {
            let choice = BodyWorkoutShareBackgroundChoice.preset(preset)
            XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: choice.rawValue, hasRoute: true), choice)
            XCTAssertEqual(BodyWorkoutShareBackgroundChoice.stored(rawValue: choice.rawValue, hasRoute: false), choice)
        }
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

    // MARK: - Route dimension

    func testStoredDimensionRoundTripsEveryCase() {
        for dimension in WorkoutShareRouteDimension.allCases {
            XCTAssertEqual(WorkoutShareRouteDimension.stored(rawValue: dimension.rawValue), dimension)
        }
        XCTAssertEqual(WorkoutShareRouteDimension.twoD.rawValue, "2d")
        XCTAssertEqual(WorkoutShareRouteDimension.threeD.rawValue, "3d")
    }

    func testStoredDimensionFallsBackToTwoDForNilOrGarbage() {
        XCTAssertEqual(WorkoutShareRouteDimension.stored(rawValue: nil), .twoD)
        XCTAssertEqual(WorkoutShareRouteDimension.stored(rawValue: ""), .twoD)
        XCTAssertEqual(WorkoutShareRouteDimension.stored(rawValue: "4d"), .twoD)
    }

    func testResolvedDimensionNeedsBothProAndAltitude() {
        // The full truth table: 3D survives only the top-right corner of it.
        for isPro in [true, false] {
            for isAvailable in [true, false] {
                XCTAssertEqual(
                    WorkoutShareBackgroundPolicy.resolvedDimension(.threeD, isProUnlocked: isPro, isThreeDAvailable: isAvailable),
                    isPro && isAvailable ? .threeD : .twoD,
                    "3D resolved wrongly for pro=\(isPro) available=\(isAvailable)"
                )
                // 2D never becomes 3D, whatever the entitlement or the route.
                XCTAssertEqual(
                    WorkoutShareBackgroundPolicy.resolvedDimension(.twoD, isProUnlocked: isPro, isThreeDAvailable: isAvailable),
                    .twoD
                )
            }
        }
    }

    // MARK: - Font choice

    func testStoredFontRoundTripsEveryCaseAndFallsBackToRounded() {
        for choice in WorkoutShareFontChoice.allCases {
            XCTAssertEqual(WorkoutShareFontChoice.stored(rawValue: choice.rawValue), choice)
        }
        XCTAssertEqual(WorkoutShareFontChoice.stored(rawValue: nil), .rounded)
        XCTAssertEqual(WorkoutShareFontChoice.stored(rawValue: "comic"), .rounded)
    }

    func testFontChoiceDesigns() {
        XCTAssertEqual(WorkoutShareFontChoice.rounded.design, .rounded)
        XCTAssertEqual(WorkoutShareFontChoice.standard.design, .default)
        XCTAssertEqual(WorkoutShareFontChoice.serif.design, .serif)
        XCTAssertEqual(WorkoutShareFontChoice.monospaced.design, .monospaced)
    }

    // MARK: - Route colour choice

    func testStoredRouteColorRoundTripsEveryCaseAndFallsBackToBodyBlue() {
        for choice in WorkoutShareRouteColorChoice.allCases {
            XCTAssertEqual(WorkoutShareRouteColorChoice.stored(rawValue: choice.rawValue), choice)
        }
        XCTAssertEqual(WorkoutShareRouteColorChoice.stored(rawValue: nil), .bodyBlue)
        XCTAssertEqual(WorkoutShareRouteColorChoice.stored(rawValue: "chartreuse"), .bodyBlue)
    }

    func testBodyBlueIsTheCardsDefaultTraceColor() {
        let tint = Color.red
        XCTAssertEqual(WorkoutShareRouteColorChoice.bodyBlue.color(tint: tint), Color(red: 1 / 255, green: 40 / 255, blue: 244 / 255))
        XCTAssertEqual(WorkoutShareRouteColorChoice.bodyBlue.color(tint: tint), BodyWorkoutShareCardView.defaultRouteColor)
        // The one option that isn't a fixed colour follows the workout's own tint.
        XCTAssertEqual(WorkoutShareRouteColorChoice.workoutTint.color(tint: tint), tint)
        XCTAssertEqual(WorkoutShareRouteColorChoice.black.color(tint: tint), .black)
    }

    // MARK: - Photo transform

    func testPhotoIdentityTransformClampsToItself() {
        // A photo with the card's own aspect ratio has no overhang at scale 1, so there
        // is nowhere for the offset to travel.
        XCTAssertEqual(
            WorkoutSharePhotoTransform.identity.clamped(imageSize: CGSize(width: 360, height: 640), cardSize: portraitCard),
            .identity
        )
    }

    func testCardAspectPhotoAtScaleOneCannotMove() {
        let clamped = WorkoutSharePhotoTransform(offset: CGSize(width: 50, height: 50), scale: 1)
            .clamped(imageSize: CGSize(width: 720, height: 1_280), cardSize: portraitCard)

        XCTAssertEqual(clamped.offset, .zero)
        XCTAssertEqual(clamped.scale, 1)
    }

    func testLandscapePhotoSlidesHorizontallyAtScaleOne() {
        // A 2:1 photo filling the 360×640 card is 1280 pt wide, so it overhangs by
        // (1280 − 360)/2 = 460 pt on each side — and only on that axis.
        let clamped = WorkoutSharePhotoTransform(offset: CGSize(width: 900, height: 900), scale: 1)
            .clamped(imageSize: CGSize(width: 1_000, height: 500), cardSize: portraitCard)

        XCTAssertEqual(clamped.offset.width, 460, accuracy: 1e-6)
        XCTAssertEqual(clamped.offset.height, 0)
    }

    func testPortraitPhotoAtScaleTwoBoundsBothAxes() {
        // Card-aspect photo at scale 2: 720×1280 over a 360×640 card → 180/320 of slack.
        let far = WorkoutSharePhotoTransform(offset: CGSize(width: 900, height: 900), scale: 2)
            .clamped(imageSize: CGSize(width: 360, height: 640), cardSize: portraitCard)

        XCTAssertEqual(far.offset.width, 180, accuracy: 1e-6)
        XCTAssertEqual(far.offset.height, 320, accuracy: 1e-6)

        let near = WorkoutSharePhotoTransform(offset: CGSize(width: -900, height: -900), scale: 2)
            .clamped(imageSize: CGSize(width: 360, height: 640), cardSize: portraitCard)

        XCTAssertEqual(near.offset.width, -180, accuracy: 1e-6)
        XCTAssertEqual(near.offset.height, -320, accuracy: 1e-6)
    }

    func testPhotoScaleClampsToItsRange() {
        let size = CGSize(width: 360, height: 640)

        XCTAssertEqual(WorkoutSharePhotoTransform(offset: .zero, scale: 9).clamped(imageSize: size, cardSize: portraitCard).scale, 4)
        // Never below 1: the photo has to keep covering the card.
        XCTAssertEqual(WorkoutSharePhotoTransform(offset: .zero, scale: 0.2).clamped(imageSize: size, cardSize: portraitCard).scale, 1)
    }

    func testNonFinitePhotoComponentsClampToTheIdentityComponent() {
        let size = CGSize(width: 360, height: 640)
        let badWidth = WorkoutSharePhotoTransform(offset: CGSize(width: CGFloat.nan, height: 100), scale: 2).clamped(imageSize: size, cardSize: portraitCard)

        XCTAssertEqual(badWidth.offset.width, 0)
        XCTAssertEqual(badWidth.offset.height, 100)
        XCTAssertEqual(badWidth.scale, 2)

        let badScale = WorkoutSharePhotoTransform(offset: CGSize(width: 20, height: CGFloat.infinity), scale: CGFloat.nan).clamped(imageSize: size, cardSize: portraitCard)

        XCTAssertEqual(badScale.offset.width, 0, "A scale that reset to 1 leaves a card-aspect photo no slack")
        XCTAssertEqual(badScale.offset.height, 0)
        XCTAssertEqual(badScale.scale, 1)
    }

    func testDegenerateImageSizeZeroesTheOffsetAndOnlyClampsTheScale() {
        for size in [CGSize(width: 0, height: 640), CGSize(width: 360, height: -1), CGSize(width: CGFloat.nan, height: 640)] {
            let clamped = WorkoutSharePhotoTransform(offset: CGSize(width: 100, height: 100), scale: 9).clamped(imageSize: size, cardSize: portraitCard)
            XCTAssertEqual(clamped.offset, CGSize.zero, "Degenerate image size \(size) should leave no offset")
            XCTAssertEqual(clamped.scale, 4)
        }
    }

    // MARK: - Info block transform

    func testIdentityTransformClampsToItself() {
        XCTAssertEqual(WorkoutShareInfoTransform.identity.clamped(cardSize: portraitCard), .identity)
    }

    func testInRangeTransformPassesThroughUnchanged() {
        let transform = WorkoutShareInfoTransform(offset: CGSize(width: 40, height: -120), scale: 1.2)

        XCTAssertEqual(transform.clamped(cardSize: portraitCard), transform)
    }

    func testOutOfRangeOffsetAndScaleClampToTheBoundsOnBothSides() {
        let far = WorkoutShareInfoTransform(offset: CGSize(width: 900, height: 900), scale: 8).clamped(cardSize: portraitCard)

        XCTAssertEqual(far.offset.width, 180)
        XCTAssertEqual(far.offset.height, 320)
        XCTAssertEqual(far.scale, WorkoutShareInfoTransform.scaleRange.upperBound)

        let near = WorkoutShareInfoTransform(offset: CGSize(width: -900, height: -900), scale: 0.01).clamped(cardSize: portraitCard)

        XCTAssertEqual(near.offset.width, -180)
        XCTAssertEqual(near.offset.height, -320)
        XCTAssertEqual(near.scale, WorkoutShareInfoTransform.scaleRange.lowerBound)
    }

    func testNonFiniteComponentsClampToTheIdentityComponent() {
        // A NaN/infinite gesture value has no meaningful side to pin to, so each bad
        // component resets on its own while the good ones survive.
        let badWidth = WorkoutShareInfoTransform(offset: CGSize(width: CGFloat.nan, height: 60), scale: 1.1).clamped(cardSize: portraitCard)

        XCTAssertEqual(badWidth.offset.width, 0)
        XCTAssertEqual(badWidth.offset.height, 60)
        XCTAssertEqual(badWidth.scale, 1.1)

        let badHeightAndScale = WorkoutShareInfoTransform(
            offset: CGSize(width: 20, height: CGFloat.infinity),
            scale: .nan
        ).clamped(cardSize: portraitCard)

        XCTAssertEqual(badHeightAndScale.offset.width, 20)
        XCTAssertEqual(badHeightAndScale.offset.height, 0)
        XCTAssertEqual(badHeightAndScale.scale, 1)
    }

    // MARK: - Aspect ratio

    func testStoredAspectRatioRoundTripsEveryCaseAndFallsBackTo9x16() {
        for ratio in WorkoutShareAspectRatio.allCases {
            XCTAssertEqual(WorkoutShareAspectRatio.stored(rawValue: ratio.rawValue), ratio)
        }
        XCTAssertEqual(WorkoutShareAspectRatio.stored(rawValue: nil), .portrait9x16)
        XCTAssertEqual(WorkoutShareAspectRatio.stored(rawValue: ""), .portrait9x16)
        XCTAssertEqual(WorkoutShareAspectRatio.stored(rawValue: "21:9"), .portrait9x16)
    }

    func testAspectRatioSizesAreTenEightyOnTheShortSideAtThreeX() {
        XCTAssertEqual(WorkoutShareAspectRatio.portrait9x16.cardSize, CGSize(width: 360, height: 640))
        XCTAssertEqual(WorkoutShareAspectRatio.landscape16x9.cardSize, CGSize(width: 640, height: 360))
        XCTAssertEqual(WorkoutShareAspectRatio.portrait4x5.cardSize, CGSize(width: 360, height: 450))
        XCTAssertEqual(WorkoutShareAspectRatio.landscape5x4.cardSize, CGSize(width: 450, height: 360))
        XCTAssertEqual(WorkoutShareAspectRatio.square.cardSize, CGSize(width: 360, height: 360))

        for ratio in WorkoutShareAspectRatio.allCases {
            XCTAssertEqual(min(ratio.cardSize.width, ratio.cardSize.height) * 3, 1_080, "\(ratio.rawValue) exports off-size")
        }
    }

    func testAspectRatioLandscapeProGatingAndLabels() {
        XCTAssertEqual(WorkoutShareAspectRatio.allCases.filter(\.isLandscape), [.landscape16x9, .landscape5x4])
        // Only the original vertical card is free.
        XCTAssertEqual(WorkoutShareAspectRatio.allCases.filter { !$0.isProGated }, [.portrait9x16])

        for ratio in WorkoutShareAspectRatio.allCases {
            XCTAssertEqual(ratio.ratioLabel, ratio.rawValue)
            XCTAssertFalse(ratio.localizedName.isEmpty)
        }
        XCTAssertEqual(WorkoutShareAspectRatio.square.ratioLabel, "1:1")
    }

    func testResolvedAspectRatioGatesEverythingButNineBySixteen() {
        for ratio in WorkoutShareAspectRatio.allCases {
            XCTAssertEqual(
                WorkoutShareBackgroundPolicy.resolvedAspectRatio(ratio, isProUnlocked: true),
                ratio,
                "Pro should keep \(ratio.rawValue)"
            )
            XCTAssertEqual(
                WorkoutShareBackgroundPolicy.resolvedAspectRatio(ratio, isProUnlocked: false),
                ratio.isProGated ? .portrait9x16 : ratio,
                "Non-Pro resolved \(ratio.rawValue) wrongly"
            )
        }
    }

    func testProLapseFallsBackForTheSessionWithoutRewritingTheStoredRatio() {
        // The stored raw string is the user's pick; only the *active* ratio falls back,
        // so resubscribing restores 16:9 without the user re-picking it.
        let stored = "16:9"
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedAspectRatio(.stored(rawValue: stored), isProUnlocked: false),
            .portrait9x16
        )
        XCTAssertEqual(WorkoutShareAspectRatio.stored(rawValue: stored), .landscape16x9)
        XCTAssertEqual(
            WorkoutShareBackgroundPolicy.resolvedAspectRatio(.stored(rawValue: stored), isProUnlocked: true),
            .landscape16x9
        )
        XCTAssertEqual(stored, "16:9")
    }

    // MARK: - Landscape arrangement

    func testStoredArrangementRoundTripsEveryCaseAndFallsBackToStacked() {
        for arrangement in WorkoutShareLandscapeArrangement.allCases {
            XCTAssertEqual(WorkoutShareLandscapeArrangement.stored(rawValue: arrangement.rawValue), arrangement)
        }
        XCTAssertEqual(WorkoutShareLandscapeArrangement.stored(rawValue: nil), .stacked)
        XCTAssertEqual(WorkoutShareLandscapeArrangement.stored(rawValue: ""), .stacked)
        XCTAssertEqual(WorkoutShareLandscapeArrangement.stored(rawValue: "diagonal"), .stacked)
    }

    func testArrangementSymbolsMatchTheirSplit() {
        XCTAssertEqual(WorkoutShareLandscapeArrangement.stacked.symbolName, "rectangle.split.1x2")
        XCTAssertEqual(WorkoutShareLandscapeArrangement.sideBySide.symbolName, "rectangle.split.2x1")
        for arrangement in WorkoutShareLandscapeArrangement.allCases {
            XCTAssertFalse(arrangement.localizedName.isEmpty)
        }
    }

    // MARK: - Card geometry

    func testNineBySixteenGeometryReproducesTheOriginalCardConstants() {
        let geo = geometry(.portrait9x16)

        XCTAssertEqual(geo.size, portraitCard)
        XCTAssertEqual(geo.centeredMode, .column)
        XCTAssertEqual(geo.centeredRouteRect.width, 260)
        XCTAssertEqual(geo.centeredRouteRect.height, 260)
        XCTAssertEqual(CGPoint(x: geo.centeredRouteRect.midX, y: geo.centeredRouteRect.midY), CGPoint(x: 180, y: 170))
        XCTAssertEqual(geo.centeredMetricsTopY, 330)
        XCTAssertEqual(geo.metricsFrame, CGRect(x: 24, y: 330, width: 312, height: 310))
        XCTAssertEqual(geo.metricsAxis, .vertical)
        XCTAssertEqual(geo.blockAnchor.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(geo.blockAnchor.y, 305 / 640, accuracy: 1e-9)
        XCTAssertEqual(WorkoutShareCardGeometry.routeInset, 12)
        XCTAssertEqual(WorkoutShareCardGeometry.brandingBottomPadding, 26)

        // The classic layout's 324 square centred at (180, 375).
        XCTAssertEqual(geo.classicRouteRect.width, 324, accuracy: 1e-9)
        XCTAssertEqual(geo.classicRouteRect.height, 324, accuracy: 1e-9)
        XCTAssertEqual(geo.classicRouteRect.midX, 180, accuracy: 1e-9)
        XCTAssertEqual(geo.classicRouteRect.midY, 375, accuracy: 1e-9)

        XCTAssertEqual(geo.topScrimHeight(isMap: true), 280, accuracy: 1e-9)
        XCTAssertEqual(geo.bottomScrimHeight(isMap: true), 210, accuracy: 1e-9)
        XCTAssertEqual(geo.topScrimHeight(isMap: false), 170, accuracy: 1e-9)
        XCTAssertEqual(geo.bottomScrimHeight(isMap: false), 160, accuracy: 1e-9)
        XCTAssertEqual(geo.mapBand.top, 280, accuracy: 1e-9)
        XCTAssertEqual(geo.mapBand.bottom, 430, accuracy: 1e-9)

        XCTAssertEqual(geo.maximumInfoOffset, CGSize(width: 180, height: 320))
    }

    func testBlockAnchorIsCenteredWithoutATrace() {
        // The route-less card is glyph + stack, which want to pinch about the middle.
        for ratio in WorkoutShareAspectRatio.allCases {
            XCTAssertEqual(geometry(ratio).blockAnchor(showsTrace: false), .center)
        }
    }

    func testCenteredModeDependsOnRatioAndOnlyThenOnArrangement() {
        for arrangement in WorkoutShareLandscapeArrangement.allCases {
            // Portrait/square never split side by side, whatever is stored.
            XCTAssertEqual(geometry(.portrait9x16, arrangement: arrangement).centeredMode, .column)
            XCTAssertEqual(geometry(.portrait4x5, arrangement: arrangement).centeredMode, .routeOverRow)
            XCTAssertEqual(geometry(.square, arrangement: arrangement).centeredMode, .routeOverRow)
        }
        XCTAssertEqual(geometry(.landscape16x9, arrangement: .stacked).centeredMode, .routeOverRow)
        XCTAssertEqual(geometry(.landscape5x4, arrangement: .stacked).centeredMode, .routeOverRow)
        XCTAssertEqual(geometry(.landscape16x9, arrangement: .sideBySide).centeredMode, .sideBySide)
        XCTAssertEqual(geometry(.landscape5x4, arrangement: .sideBySide).centeredMode, .sideBySide)
    }

    func testCenteredRouteSidePerRatio() {
        // 4:5 is tall enough for the full 260; the 360-tall cards shrink to fit the
        // metric row and the branding under the square.
        XCTAssertEqual(geometry(.portrait4x5).centeredRouteRect.width, 260, accuracy: 1e-9)
        XCTAssertEqual(geometry(.square).centeredRouteRect.width, 182, accuracy: 1e-9)
        XCTAssertEqual(geometry(.landscape16x9, arrangement: .stacked).centeredRouteRect.width, 182, accuracy: 1e-9)
        XCTAssertEqual(geometry(.landscape5x4, arrangement: .stacked).centeredRouteRect.width, 182, accuracy: 1e-9)

        // Side by side trades height for the free half-width — but 5:4's half is
        // narrower than its height, so the midline is what limits it.
        XCTAssertEqual(geometry(.landscape16x9, arrangement: .sideBySide).centeredRouteRect.width, 280, accuracy: 1e-9)
        XCTAssertEqual(geometry(.landscape5x4, arrangement: .sideBySide).centeredRouteRect.width, 201, accuracy: 1e-9)
    }

    func testSideBySideRouteNeverCrossesTheMidline() {
        for ratio in [WorkoutShareAspectRatio.landscape16x9, .landscape5x4] {
            let geo = geometry(ratio, arrangement: .sideBySide)
            XCTAssertLessThanOrEqual(geo.centeredRouteRect.maxX, geo.size.width / 2)
            // ...and the metrics stay in the other half.
            XCTAssertGreaterThanOrEqual(geo.metricsFrame.minX, geo.size.width / 2)
            XCTAssertEqual(geo.metricsAxis, .vertical)
        }
    }

    func testRouteOverRowMetricsSitAboveTheBrandingZone() {
        for ratio in [WorkoutShareAspectRatio.portrait4x5, .square, .landscape16x9, .landscape5x4] {
            let geo = geometry(ratio, arrangement: .stacked)
            XCTAssertEqual(geo.centeredMode, .routeOverRow)
            XCTAssertEqual(geo.metricsAxis, .horizontal)
            XCTAssertEqual(geo.metricsFrame.height, 68, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(
                geo.metricsFrame.maxY,
                geo.size.height - 56,
                "\(ratio.rawValue)'s metric row runs into the branding"
            )
            // The row starts below the route's ink, not on top of it.
            XCTAssertGreaterThan(geo.metricsFrame.minY, geo.centeredRouteRect.maxY - WorkoutShareCardGeometry.routeInset)
        }
    }

    func testEveryRatioKeepsItsCenteredBlockInsideTheCard() {
        for ratio in WorkoutShareAspectRatio.allCases {
            for arrangement in WorkoutShareLandscapeArrangement.allCases {
                let geo = geometry(ratio, arrangement: arrangement)
                let card = CGRect(origin: .zero, size: geo.size)
                XCTAssertTrue(
                    card.contains(geo.centeredRouteRect),
                    "\(ratio.rawValue)/\(arrangement.rawValue) route \(geo.centeredRouteRect) escapes \(geo.size)"
                )
                XCTAssertTrue(
                    card.union(geo.metricsFrame) == card,
                    "\(ratio.rawValue)/\(arrangement.rawValue) metrics \(geo.metricsFrame) escape \(geo.size)"
                )
                XCTAssertTrue(card.contains(geo.classicRouteRect), "\(ratio.rawValue) classic route escapes the card")
                XCTAssertGreaterThan(geo.centeredRouteRect.width, 0)

                let anchor = geo.blockAnchor
                XCTAssertTrue((0...1).contains(anchor.x) && (0...1).contains(anchor.y))
            }
        }
    }

    func testMapBandFractionsScaleWithTheCardHeight() {
        for ratio in WorkoutShareAspectRatio.allCases {
            let geo = geometry(ratio)
            XCTAssertEqual(geo.topScrimHeight(isMap: true), geo.size.height * 280 / 640, accuracy: 1e-9)
            XCTAssertEqual(geo.mapBand.top, geo.topScrimHeight(isMap: true), accuracy: 1e-9)
            XCTAssertEqual(geo.mapBand.bottom, geo.size.height - geo.bottomScrimHeight(isMap: true), accuracy: 1e-9)
            XCTAssertGreaterThan(geo.mapBand.bottom, geo.mapBand.top, "\(ratio.rawValue) has no clear map band")
            // The preset scrims are always the shallower pair.
            XCTAssertLessThan(geo.topScrimHeight(isMap: false), geo.topScrimHeight(isMap: true))
            XCTAssertEqual(geo.maximumInfoOffset, CGSize(width: geo.size.width / 2, height: geo.size.height / 2))
        }
    }

    func testRoutelessRowsWrapOnlyOnTheNarrowCards() {
        for ratio in WorkoutShareAspectRatio.allCases {
            let geo = geometry(ratio, layout: .routeless)
            // Four metric blocks need ~140 pt each; only 450/640-wide cards fit a line.
            XCTAssertEqual(geo.routelessWrapsMetricRows, geo.size.width < 400, "\(ratio.rawValue) wrapped wrongly")
            XCTAssertEqual(geo.routelessMetricsAxis, ratio == .portrait9x16 ? .vertical : .horizontal)
        }
        XCTAssertTrue(geometry(.square, layout: .routeless).routelessWrapsMetricRows)
        XCTAssertFalse(geometry(.landscape5x4, layout: .routeless).routelessWrapsMetricRows)
    }

    // MARK: - Transforms on a landscape card

    func testInfoOffsetBoundsFollowTheLandscapeCard() {
        let far = WorkoutShareInfoTransform(offset: CGSize(width: 900, height: 900), scale: 1)
            .clamped(cardSize: landscapeCard)

        XCTAssertEqual(far.offset.width, 320)
        XCTAssertEqual(far.offset.height, 180)
    }

    func testCardAspectPhotoCannotMoveOnTheLandscapeCard() {
        let clamped = WorkoutSharePhotoTransform(offset: CGSize(width: 90, height: 90), scale: 1)
            .clamped(imageSize: CGSize(width: 1_280, height: 720), cardSize: landscapeCard)

        XCTAssertEqual(clamped.offset, .zero)
    }

    func testPortraitPhotoSlidesVerticallyOnTheLandscapeCard() {
        // A 9:16 photo filling the 640×360 card is 640 / 0.5625 = 1137.78 pt tall, so
        // it overhangs by (1137.78 − 360)/2 on each side — and only on that axis.
        let clamped = WorkoutSharePhotoTransform(offset: CGSize(width: 900, height: 900), scale: 1)
            .clamped(imageSize: CGSize(width: 360, height: 640), cardSize: landscapeCard)

        XCTAssertEqual(clamped.offset.width, 0)
        XCTAssertEqual(clamped.offset.height, (640 / (360.0 / 640) - 360) / 2, accuracy: 1e-6)
        XCTAssertEqual(clamped.offset.height, 388.888_9, accuracy: 1e-3)
    }
}
