//
//  WorkoutDetailTilesTests.swift
//  BodyTests
//
//  The workout-detail context tiles built from workout metadata (average METs)
//  plus the heart-rate recovery tile, and the hero line's temperature text
//  (which replaced the temperature tile). Humidity is hero-only — no tile.
//

import XCTest
@testable import Body

final class WorkoutDetailTilesTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func workout(
        temperatureCelsius: Double? = nil,
        humidityPercent: Double? = nil,
        condition: WorkoutWeatherCondition? = nil,
        averageMETs: Double? = nil,
        heartRateRecoveryBPM: Double? = nil
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
            weatherCondition: condition,
            averageMETs: averageMETs,
            heartRateRecoveryBPM: heartRateRecoveryBPM
        )
    }

    private func tiles(_ workout: WorkoutSummary) -> [WorkoutDetailMetric.Kind: String] {
        let presentation = WorkoutDetailPresentation(workout: workout, locale: locale)
        return Dictionary(uniqueKeysWithValues: presentation.detailMetrics.map { ($0.kind, $0.value) })
    }

    // MARK: - Hero-line temperature (no longer a tile)

    func testSubZeroHeroTemperatureKeepsItsSign() {
        XCTAssertEqual(
            BodyValueFormat.temperatureHeroText(celsius: -10, locale: locale, temperatureUnitPreference: .celsius),
            "-10°C"
        )
    }

    func testFreezingHeroTemperatureNeverReadsAsNegativeZero() {
        XCTAssertEqual(
            BodyValueFormat.temperatureHeroText(celsius: 0, locale: locale, temperatureUnitPreference: .celsius),
            "0°C"
        )
        // -0.4 rounds to negative zero, which would otherwise format as "-0".
        XCTAssertEqual(
            BodyValueFormat.temperatureHeroText(celsius: -0.4, locale: locale, temperatureUnitPreference: .celsius),
            "0°C"
        )
    }

    func testHeroTemperatureHonorsFahrenheitPreference() {
        XCTAssertEqual(
            BodyValueFormat.temperatureHeroText(celsius: 21.1, locale: locale, temperatureUnitPreference: .fahrenheit),
            "70°F"
        )
    }

    func testNonFiniteHeroTemperatureIsOmitted() {
        for celsius in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(
                BodyValueFormat.temperatureHeroText(celsius: celsius, locale: locale, temperatureUnitPreference: .celsius)
            )
        }
    }

    func testHeroTemperatureUsesLocalizedDigits() {
        let chinese = Locale(identifier: "zh_Hans_CN")
        XCTAssertEqual(
            BodyValueFormat.temperatureHeroText(celsius: 21, locale: chinese, temperatureUnitPreference: .celsius),
            "\(BodyValueFormat.numberText(21, decimals: 0, locale: chinese))°C"
        )

        // A locale that really does swap the digit glyphs, so the interpolation above
        // isn't just restating itself.
        let arabic = Locale(identifier: "ar")
        XCTAssertEqual(
            BodyValueFormat.temperatureHeroText(celsius: 21, locale: arabic, temperatureUnitPreference: .celsius),
            "\(BodyValueFormat.numberText(21, decimals: 0, locale: arabic))°C"
        )
    }

    // MARK: - Context tiles

    func testMETsTile() {
        let values = tiles(workout(humidityPercent: 68, averageMETs: 8.4))
        XCTAssertEqual(values[.averageMETs], "8.4 METs")
    }

    /// Humidity is shown on the hero's weather line only — a recorded reading
    /// must not come back as a Details tile.
    func testRecordedHumidityEmitsNoTile() {
        XCTAssertNil(tiles(workout(humidityPercent: 68))[.humidity])
    }

    func testAbsentAndNonFiniteValuesEmitNoTiles() {
        let empty = tiles(workout())
        XCTAssertNil(empty[.averageMETs])

        let nonFinite = tiles(workout(
            temperatureCelsius: .nan,
            humidityPercent: .infinity,
            averageMETs: .nan
        ))
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

    /// METs and HR recovery are comparable against the 30-day history — the tiles
    /// carry a badge like the performance ones.
    func testContextTilesExposeComparisonScalars() {
        let summary = workout(averageMETs: 8.4, heartRateRecoveryBPM: 32)

        XCTAssertEqual(WorkoutMetricComparisonBuilder.scalar(for: .averageMETs, from: summary), 8.4)
        XCTAssertEqual(WorkoutMetricComparisonBuilder.scalar(for: .heartRateRecovery, from: summary), 32)
    }

    // MARK: - Heart-rate recovery

    /// When the summary carries the recovery read from the workout's attached
    /// statistics, the tile comes straight out of the presentation — the detail
    /// sheet's lazy read is only the fallback.
    func testHeartRateRecoveryTileIsEmittedFromTheSummary() {
        let values = tiles(workout(heartRateRecoveryBPM: 32))

        XCTAssertEqual(values[.heartRateRecovery], BodyValueFormat.heartRateText(beatsPerMinute: 32, locale: locale))
        // Absent or non-positive readings leave the tile to the lazy path.
        XCTAssertNil(tiles(workout())[.heartRateRecovery])
        XCTAssertNil(tiles(workout(heartRateRecoveryBPM: 0))[.heartRateRecovery])
    }

    func testCodableRoundTripPreservesMetadataFields() throws {
        let summary = workout(
            temperatureCelsius: -3.5,
            humidityPercent: 68,
            condition: .partlyCloudy,
            averageMETs: 8.4,
            heartRateRecoveryBPM: 32
        )
        let decoded = try JSONDecoder().decode(
            WorkoutSummary.self,
            from: try JSONEncoder().encode(summary)
        )

        XCTAssertEqual(decoded.weatherTemperatureCelsius, -3.5)
        XCTAssertEqual(decoded.weatherHumidityPercent, 68)
        // Persisted by name, so the cached glyph survives a relaunch.
        XCTAssertEqual(decoded.weatherCondition, .partlyCloudy)
        XCTAssertEqual(decoded.averageMETs, 8.4)
        XCTAssertEqual(decoded.heartRateRecoveryBPM, 32)
    }

    /// Weather and METs are workout metadata, not Workout Metrics samples, so the
    /// opt-out that clears VO₂max/power/cadence leaves them alone — and recovery
    /// rides the Heart toggle, so it survives too.
    func testRemovingWorkoutMetricsPreservesMetadataFields() {
        let stripped = workout(
            temperatureCelsius: -3.5,
            humidityPercent: 68,
            condition: .partlyCloudy,
            averageMETs: 8.4,
            heartRateRecoveryBPM: 32
        ).removingWorkoutMetrics()

        XCTAssertEqual(stripped.weatherTemperatureCelsius, -3.5)
        XCTAssertEqual(stripped.weatherHumidityPercent, 68)
        XCTAssertEqual(stripped.weatherCondition, .partlyCloudy)
        XCTAssertEqual(stripped.averageMETs, 8.4)
        XCTAssertEqual(stripped.heartRateRecoveryBPM, 32)
    }

    // MARK: - Custom workout name

    func testCustomNameReplacesTheWorkoutTypeTitle() {
        let presentation = WorkoutDetailPresentation(
            workout: workout(),
            locale: locale,
            customName: "Morning Tempo"
        )

        XCTAssertEqual(presentation.title, "Morning Tempo")
    }

    func testBlankAndMissingCustomNamesFallBackToTheWorkoutType() {
        let summary = workout()

        XCTAssertEqual(
            WorkoutDetailPresentation(workout: summary, locale: locale, customName: "   ").title,
            summary.type.displayName
        )
        XCTAssertEqual(
            WorkoutDetailPresentation(workout: summary, locale: locale, customName: nil).title,
            summary.type.displayName
        )
    }

    func testLongCustomNameIsTrimmedAndCappedAtSixtyCharacters() {
        let raw = "  " + String(repeating: "a", count: 70) + "  "

        XCTAssertEqual(
            WorkoutDetailPresentation(workout: workout(), locale: locale, customName: raw).title,
            String(repeating: "a", count: 60)
        )
    }

    func testNormalizedCustomNameTrimsCapsAndRejectsBlanks() {
        XCTAssertEqual(WorkoutSummary.normalizedCustomName("  Easy Spin \n"), "Easy Spin")
        XCTAssertNil(WorkoutSummary.normalizedCustomName(nil))
        XCTAssertNil(WorkoutSummary.normalizedCustomName(" \n "))
        XCTAssertEqual(
            WorkoutSummary.normalizedCustomName(String(repeating: "b", count: 61))?.count,
            60
        )
    }

    // MARK: - Full-resolution heart-rate override

    /// The workout as the list has it: a stored average plus the ≤96-point summary
    /// samples the fetch baked in.
    private func heartRateWorkout() -> WorkoutSummary {
        WorkoutSummary(
            type: .running,
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            duration: 1_800,
            averageHeartRateBeatsPerMinute: 154,
            heartRateSamples: [
                WorkoutHeartRateSample(date: Date(timeIntervalSince1970: 1_770_000_000), beatsPerMinute: 120),
                WorkoutHeartRateSample(date: Date(timeIntervalSince1970: 1_770_000_600), beatsPerMinute: 150)
            ]
        )
    }

    private func fullResolutionSamples() -> [WorkoutHeartRateSample] {
        [
            WorkoutHeartRateSample(date: Date(timeIntervalSince1970: 1_770_000_900), beatsPerMinute: 170),
            WorkoutHeartRateSample(date: Date(timeIntervalSince1970: 1_770_000_300), beatsPerMinute: 130),
            WorkoutHeartRateSample(date: Date(timeIntervalSince1970: 1_770_000_600), beatsPerMinute: 150)
        ]
    }

    func testHeartRateOverrideReplacesTheSummarySamplesInDateOrder() {
        let presentation = WorkoutDetailPresentation(
            workout: heartRateWorkout(),
            locale: locale,
            heartRateSamplesOverride: fullResolutionSamples()
        )

        XCTAssertEqual(presentation.heartRateSamples.map(\.beatsPerMinute), [130, 150, 170])
        XCTAssertEqual(
            presentation.heartRateSamples.map(\.date),
            presentation.heartRateSamples.map(\.date).sorted()
        )
    }

    func testNilHeartRateOverrideKeepsTheSummarySamples() {
        let presentation = WorkoutDetailPresentation(
            workout: heartRateWorkout(),
            locale: locale,
            heartRateSamplesOverride: nil
        )

        XCTAssertEqual(presentation.heartRateSamples.map(\.beatsPerMinute), [120, 150])
    }

    func testEmptyHeartRateOverrideKeepsTheSummarySamples() {
        let presentation = WorkoutDetailPresentation(
            workout: heartRateWorkout(),
            locale: locale,
            heartRateSamplesOverride: []
        )

        XCTAssertEqual(presentation.heartRateSamples.map(\.beatsPerMinute), [120, 150])
    }

    /// The average tile stays on the workout's stored average, so densifying the chart
    /// can never make the number under it move.
    func testHeartRateOverrideLeavesTheAverageTextOnTheStoredAverage() {
        let workout = heartRateWorkout()
        let baseline = WorkoutDetailPresentation(workout: workout, locale: locale)
        let overridden = WorkoutDetailPresentation(
            workout: workout,
            locale: locale,
            heartRateSamplesOverride: fullResolutionSamples()
        )

        XCTAssertEqual(overridden.averageHeartRateText, baseline.averageHeartRateText)
        XCTAssertEqual(
            overridden.averageHeartRateText,
            BodyValueFormat.heartRateText(beatsPerMinute: 154, locale: locale)
        )
    }
}
