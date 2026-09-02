//
//  WidgetFormatterParityTests.swift
//  BodyTests
//
//  M-23: the widget builds its own trend-average strings independently of
//  Home's BodyHomeTrendCardFactory. These two formatters must read the same
//  way for a viewer moving between the widget and the app; this test pins
//  that they agree for a fixed value per metric.
//

import XCTest
@testable import Body

final class WidgetFormatterParityTests: XCTestCase {
    private let temperatureUnitPreference = BodyValueFormat.TemperatureUnitPreference.celsius
    private let energyUnitPreference = BodyValueFormat.EnergyUnitPreference.kilocalories
    private let weightUnitPreference = BodyValueFormat.WeightUnitPreference.kilograms

    /// Every `HealthWidgetMetric` maps to a `BodyHomeTrendCardKind` today
    /// (see HealthWidgetSnapshotBuilder.swift:19-35 and
    /// BodyHomeTrendCard.swift's BodyHomeTrendCardKind). Pinned here so a
    /// future widget metric without a Home card is a visible test failure
    /// rather than a silently skipped parity check.
    func testEveryWidgetMetricHasACardMapping() {
        let unmapped = HealthWidgetMetric.allCases.filter {
            BodyHomeTrendCardKind(metricKind: $0.healthMetricKind) == nil
        }
        XCTAssertEqual(unmapped, [])
    }

    @MainActor
    func testFormattedValueParityAcrossWidgetMetrics() {
        let fixedValue = 42.0

        for metric in HealthWidgetMetric.allCases {
            guard let cardKind = BodyHomeTrendCardKind(metricKind: metric.healthMetricKind) else {
                XCTFail("\(metric) has no BodyHomeTrendCardKind mapping")
                continue
            }

            let homeText = BodyHomeTrendCardFactory.formattedValue(
                fixedValue,
                for: cardKind,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                weightUnitPreference: weightUnitPreference
            )
            let widget = HealthWidgetSnapshotBuilder.formattedValue(
                fixedValue,
                for: metric,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                weightUnitPreference: weightUnitPreference
            )
            // The widget renders value and unit as separate display values, so
            // the join spacing is a layout choice, not a formatting one: compare
            // the digits and unit with whitespace removed on both sides.
            let widgetText = (widget.value + (widget.unit ?? "")).replacingOccurrences(of: " ", with: "")
            let homeCompact = homeText.replacingOccurrences(of: " ", with: "")

            XCTAssertEqual(homeCompact, widgetText, "mismatch for \(metric.rawValue)")
        }
    }
}
