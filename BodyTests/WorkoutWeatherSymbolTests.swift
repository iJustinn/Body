//
//  WorkoutWeatherSymbolTests.swift
//  BodyTests
//
//  `WorkoutSummary.weatherSymbolName` — the detail hero's weather glyph. The
//  recorded sky condition wins when the source wrote one; otherwise a
//  thermometer graded by the temperature, cut on the *rounded* Celsius so the
//  glyph can never disagree with the number rendered beside it.
//

import UIKit
import XCTest
@testable import Body

final class WorkoutWeatherSymbolTests: XCTestCase {
    private func workout(
        temperatureCelsius: Double? = nil,
        condition: WorkoutWeatherCondition? = nil
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: UUID(),
            type: .running,
            startDate: Date(timeIntervalSince1970: 1_770_000_000),
            duration: 1_800,
            sourceName: "Apple Watch",
            weatherTemperatureCelsius: temperatureCelsius,
            weatherCondition: condition
        )
    }

    private func symbol(_ celsius: Double?) -> String {
        workout(temperatureCelsius: celsius).weatherSymbolName
    }

    /// A recorded sky condition outranks the temperature — a clear day at -20°C
    /// still shows the sun, not the snowflake.
    func testRecordedConditionWinsOverTemperature() {
        XCTAssertEqual(
            workout(temperatureCelsius: -20, condition: .clear).weatherSymbolName,
            "sun.max.fill"
        )
        XCTAssertEqual(
            workout(temperatureCelsius: 35, condition: .snow).weatherSymbolName,
            "cloud.snow.fill"
        )
    }

    /// Both sides of every band edge. The edges sit on the rounded value, so
    /// 4.4 (rounds to 4) is still the cold band and 4.6 (rounds to 5) is not.
    func testTemperatureBandsAndBoundaries() {
        XCTAssertEqual(symbol(-18), "thermometer.snowflake")
        XCTAssertEqual(symbol(4.4), "thermometer.snowflake")
        XCTAssertEqual(symbol(4.6), "thermometer.low")
        XCTAssertEqual(symbol(13.4), "thermometer.low")
        XCTAssertEqual(symbol(13.6), "thermometer.medium")
        XCTAssertEqual(symbol(22.4), "thermometer.medium")
        XCTAssertEqual(symbol(22.6), "thermometer.high")
        XCTAssertEqual(symbol(27.4), "thermometer.high")
        XCTAssertEqual(symbol(27.6), "thermometer.sun.fill")
        XCTAssertEqual(symbol(41), "thermometer.sun.fill")
    }

    /// The regression this design exists to prevent: two workouts whose hero text
    /// renders to the same °C string must never draw different thermometers.
    /// Grading the raw value instead of the rounded one breaks this at every edge.
    func testSymbolAgreesWithTheRenderedTemperatureText() {
        let locale = Locale(identifier: "en_US")
        var symbolsByText: [String: String] = [:]

        for tenths in -400...500 {
            let celsius = Double(tenths) / 10
            guard let text = BodyValueFormat.temperatureHeroText(
                celsius: celsius,
                locale: locale,
                temperatureUnitPreference: .celsius
            ) else {
                continue
            }

            let symbol = self.symbol(celsius)
            if let existing = symbolsByText[text] {
                XCTAssertEqual(
                    existing,
                    symbol,
                    "\(text) drew both \(existing) and \(symbol) (at \(celsius)°C)"
                )
            } else {
                symbolsByText[text] = symbol
            }
        }

        // Sanity: the sweep actually exercised every band.
        XCTAssertEqual(Set(symbolsByText.values).count, 5)
    }

    /// Defensive defaults. Not reachable from the hero — the temperature pair is
    /// gated on `temperatureHeroText`, which returns nil for both cases — but the
    /// property is total, so an absent or garbage reading stays on the neutral glyph.
    func testMissingOrNonFiniteTemperatureFallsBackToNeutralThermometer() {
        XCTAssertEqual(symbol(nil), "thermometer.medium")
        XCTAssertEqual(symbol(.nan), "thermometer.medium")
        XCTAssertEqual(symbol(.infinity), "thermometer.medium")
        XCTAssertEqual(symbol(-.infinity), "thermometer.medium")
    }

    /// Every symbol either mapping can produce must actually resolve on this OS —
    /// the one realistic failure mode is a typo'd or withdrawn SF Symbol name,
    /// which renders as a blank space rather than crashing.
    func testEverySymbolNameResolves() {
        let thermometers = [
            "thermometer.snowflake",
            "thermometer.low",
            "thermometer.medium",
            "thermometer.high",
            "thermometer.sun.fill"
        ]

        for name in WorkoutWeatherCondition.allCases.map(\.symbolName) + thermometers {
            XCTAssertNotNil(UIImage(systemName: name), "\(name) does not resolve")
        }
    }
}
