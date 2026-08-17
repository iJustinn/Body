//
//  WorkoutDetailTilesTests.swift
//  BodyTests
//
//  The workout-detail context tiles built from workout metadata (weather,
//  average METs) plus the separately loaded heart-rate recovery tile.
//

import XCTest
@testable import Body

final class WorkoutDetailTilesTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func workout(
        temperatureCelsius: Double? = nil,
        humidityPercent: Double? = nil,
        averageMETs: Double? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            duration: 1_800,
            activeEnergyKilocalories: 300,
            totalEnergyKilocalories: 340,
            sourceName: "Apple Watch",
            endDate: Date(timeIntervalSince1970: 1_770_001_800),
            weatherTemperatureCelsius: temperatureCelsius,
            weatherHumidityPercent: humidityPercent,
            averageMETs: averageMETs
        )
    }

    private func tiles(
        _ workout: WorkoutSummary,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference = .celsius
    ) -> [WorkoutDetailMetric.Kind: String] {
        let presentation = WorkoutDetailPresentation(
            workout: workout,
            locale: locale,
            temperatureUnitPreference: temperatureUnitPreference
        )
        return Dictionary(uniqueKeysWithValues: presentation.detailMetrics.map { ($0.kind, $0.value) })
    }

    func testSubZeroTemperatureTileKeepsItsSign() {
        XCTAssertEqual(tiles(workout(temperatureCelsius: -10))[.temperature], "-10 °C")
    }

    func testZeroTemperatureTileIsShown() {
        XCTAssertEqual(tiles(workout(temperatureCelsius: 0))[.temperature], "0 °C")
    }

    func testTemperatureTileHonorsFahrenheitPreference() {
        XCTAssertEqual(
            tiles(workout(temperatureCelsius: 21), temperatureUnitPreference: .fahrenheit)[.temperature],
            "70 °F"
        )
    }

    func testHumidityAndMETsTiles() {
        let values = tiles(workout(humidityPercent: 68, averageMETs: 8.4))
        XCTAssertEqual(values[.humidity], "68 %")
        XCTAssertEqual(values[.averageMETs], "8.4 METs")
    }

    func testAbsentAndNonFiniteValuesEmitNoTiles() {
        let empty = tiles(workout())
        XCTAssertNil(empty[.temperature])
        XCTAssertNil(empty[.humidity])
        XCTAssertNil(empty[.averageMETs])

        let nonFinite = tiles(workout(
            temperatureCelsius: .nan,
            humidityPercent: .infinity,
            averageMETs: .nan
        ))
        XCTAssertNil(nonFinite[.temperature])
        XCTAssertNil(nonFinite[.humidity])
        XCTAssertNil(nonFinite[.averageMETs])

        // Zero METs reads as "not recorded", like the other >0-gated tiles.
        XCTAssertNil(tiles(workout(averageMETs: 0))[.averageMETs])
    }

    func testHeartRateRecoveryMetricUsesTheHeartRateUnit() {
        let metric = WorkoutDetailPresentation.heartRateRecoveryMetric(bpm: 32, locale: locale)

        XCTAssertEqual(metric.kind, .heartRateRecovery)
        XCTAssertEqual(metric.title, "HR Recovery")
        XCTAssertEqual(metric.value, BodyValueFormat.heartRateText(beatsPerMinute: 32, locale: locale))
    }

    /// The four context tiles never carry a 30-day badge — there is no useful
    /// performance baseline for weather, METs, or a one-off recovery reading.
    func testContextTilesHaveNoComparisonScalar() {
        let summary = workout(temperatureCelsius: 21, humidityPercent: 68, averageMETs: 8.4)

        for kind in [WorkoutDetailMetric.Kind.temperature, .humidity, .averageMETs, .heartRateRecovery] {
            XCTAssertNil(WorkoutMetricComparisonBuilder.scalar(for: kind, from: summary))
        }
    }

    func testCodableRoundTripPreservesMetadataFields() throws {
        let summary = workout(temperatureCelsius: -3.5, humidityPercent: 68, averageMETs: 8.4)
        let decoded = try JSONDecoder().decode(
            WorkoutSummary.self,
            from: try JSONEncoder().encode(summary)
        )

        XCTAssertEqual(decoded.weatherTemperatureCelsius, -3.5)
        XCTAssertEqual(decoded.weatherHumidityPercent, 68)
        XCTAssertEqual(decoded.averageMETs, 8.4)
    }

    /// Weather and METs are workout metadata, not Workout Metrics samples, so the
    /// opt-out that clears VO₂max/power/cadence leaves them alone.
    func testRemovingWorkoutMetricsPreservesMetadataFields() {
        let stripped = workout(temperatureCelsius: -3.5, humidityPercent: 68, averageMETs: 8.4)
            .removingWorkoutMetrics()

        XCTAssertEqual(stripped.weatherTemperatureCelsius, -3.5)
        XCTAssertEqual(stripped.weatherHumidityPercent, 68)
        XCTAssertEqual(stripped.averageMETs, 8.4)
    }
}
