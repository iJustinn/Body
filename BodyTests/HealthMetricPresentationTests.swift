//
//  HealthMetricPresentationTests.swift
//  BodyTests
//
//  A4: symbol, tint, chart shape and number formats used to be spelled out
//  independently in the widget metric, the trend card kind, the trend card
//  factory, the widget snapshot builder and Home's summary cards. They now all
//  read `HealthMetricPresentation`, so these tests pin two things: every kind
//  those five sites present has a row, and each row still writes what it wrote
//  before the table existed. The expected values below are hand written, not
//  read back from the table, so a future edit to a format is deliberate.
//

import XCTest
import SwiftUI
@testable import Body

final class HealthMetricPresentationTests: XCTestCase {
    private typealias Format = HealthMetricPresentation.NumberFormat

    // MARK: - Coverage

    func testEveryWidgetMetricHasAPresentationRow() {
        for metric in HealthWidgetMetric.allCases {
            XCTAssertNotNil(
                HealthMetricPresentation.presentation(for: metric.healthMetricKind),
                metric.rawValue
            )
        }
    }

    func testEveryTrendCardKindHasAPresentationRow() {
        for kind in BodyHomeTrendCardKind.allCases {
            XCTAssertNotNil(HealthMetricPresentation.presentation(for: kind.metricKind), kind.rawValue)
        }
    }

    /// The kinds with no row are the ones no card and no widget presents as a
    /// single value: `.basics` fans out to three measurements, `.vitals` is a
    /// group of overnight readings, `.bodyMassIndex` has no card of its own, and
    /// `.bodyRadar` reads as a word state rather than a number.
    func testKindsWithoutAPresentationRowAreTheExpectedFour() {
        let missing = HealthMetricKind.allCases.filter {
            HealthMetricPresentation.presentation(for: $0) == nil
        }
        XCTAssertEqual(Set(missing), [.basics, .vitals, .bodyMassIndex, .bodyRadar])
    }

    /// The two accessors that used to hold their own switch statements now read
    /// the table, so a kind whose row went missing would fall back silently.
    func testTrendCardKindStylingMatchesTheTable() {
        for kind in BodyHomeTrendCardKind.allCases {
            let presentation = HealthMetricPresentation.presentation(for: kind.metricKind)
            XCTAssertEqual(kind.iconName, presentation?.symbolName, kind.rawValue)
            XCTAssertNotEqual(kind.iconName, "questionmark.circle", kind.rawValue)
            XCTAssertEqual(
                UIColor(kind.tintColor).cgColor.components ?? [],
                UIColor(presentation?.tint ?? .clear).cgColor.components ?? [],
                kind.rawValue
            )
        }
    }

    /// The widget metric's symbol, tint and chart shape read the same table, and
    /// its own two-case chart style maps line to line and bar to bar.
    func testWidgetMetricStylingMatchesTheTable() {
        for metric in HealthWidgetMetric.allCases {
            let presentation = HealthMetricPresentation.presentation(for: metric.healthMetricKind)
            XCTAssertEqual(metric.symbolName, presentation?.symbolName, metric.rawValue)
            XCTAssertEqual(
                UIColor(metric.tintColor).cgColor.components ?? [],
                UIColor(presentation?.tint ?? .clear).cgColor.components ?? [],
                metric.rawValue
            )
            XCTAssertEqual(metric.chartStyle == .bar, presentation?.chartStyle == .bar, metric.rawValue)
        }
    }

    // MARK: - Pinned table

    private struct ExpectedRow {
        let symbolName: String
        let chartStyle: HealthMetricChartStyle
        let unitPreference: HealthMetricPresentation.UnitPreferenceKind?
        let summaryFormat: Format?
        let trendFormat: Format?
    }

    /// The values every site wrote before the table existed. Skin temperature,
    /// weight and the two energy metrics carry no fixed unit suffix: their unit
    /// label is read from a unit preference at each call site.
    private let expected: [HealthMetricKind: ExpectedRow] = [
        .readiness: ExpectedRow(
            symbolName: "bolt.heart.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: nil,
            trendFormat: Format(decimals: 0, unitSuffix: "%", spacesUnit: false)
        ),
        .stress: ExpectedRow(
            symbolName: "brain.head.profile.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: nil,
            trendFormat: Format(decimals: 0)
        ),
        .heartRate: ExpectedRow(
            symbolName: "heart.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0, unitSuffix: "bpm"),
            trendFormat: Format(decimals: 0, unitSuffix: "BPM")
        ),
        .restingHeartRate: ExpectedRow(
            symbolName: "heart.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0, unitSuffix: "bpm"),
            trendFormat: Format(decimals: 0, unitSuffix: "BPM")
        ),
        .heartRateVariability: ExpectedRow(
            symbolName: "waveform.path.ecg",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 1, unitSuffix: "ms"),
            trendFormat: Format(decimals: 0, unitSuffix: "ms")
        ),
        .cardioFitness: ExpectedRow(
            symbolName: "arrow.up.heart.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: nil,
            trendFormat: Format(decimals: 1, unitSuffix: "VO₂ max")
        ),
        .respiratoryRate: ExpectedRow(
            symbolName: "lungs.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0, unitSuffix: "br/min"),
            trendFormat: Format(decimals: 0, unitSuffix: "br/min")
        ),
        .oxygenSaturation: ExpectedRow(
            symbolName: "drop.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0, unitSuffix: "%", spacesUnit: false),
            trendFormat: Format(decimals: 0, unitSuffix: "%", spacesUnit: false)
        ),
        .sleep: ExpectedRow(
            symbolName: "bed.double.fill",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: nil,
            trendFormat: nil
        ),
        .wristTemperature: ExpectedRow(
            symbolName: "thermometer.medium",
            chartStyle: .line,
            unitPreference: .temperature,
            summaryFormat: nil,
            trendFormat: Format(decimals: 1)
        ),
        .steps: ExpectedRow(
            symbolName: "figure.walk",
            chartStyle: .bar,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0),
            trendFormat: Format(decimals: 0, unitSuffix: "steps")
        ),
        .activeEnergy: ExpectedRow(
            symbolName: "flame.fill",
            chartStyle: .bar,
            unitPreference: .energy,
            summaryFormat: Format(decimals: 0),
            trendFormat: Format(decimals: 0)
        ),
        .restingEnergy: ExpectedRow(
            symbolName: "leaf.fill",
            chartStyle: .bar,
            unitPreference: .energy,
            summaryFormat: Format(decimals: 0),
            trendFormat: Format(decimals: 0)
        ),
        .exerciseMinutes: ExpectedRow(
            symbolName: "figure.run",
            chartStyle: .bar,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0),
            trendFormat: Format(decimals: 0, unitSuffix: "min")
        ),
        .trainingLoad: ExpectedRow(
            symbolName: "figure.strengthtraining.traditional",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 2),
            trendFormat: Format(decimals: 2)
        ),
        .timeInDaylight: ExpectedRow(
            symbolName: "sun.max.fill",
            chartStyle: .bar,
            unitPreference: nil,
            summaryFormat: Format(decimals: 0, unitSuffix: "min"),
            trendFormat: Format(decimals: 0, unitSuffix: "min")
        ),
        .bodyMass: ExpectedRow(
            symbolName: "scalemass.fill",
            chartStyle: .line,
            unitPreference: .mass,
            summaryFormat: Format(decimals: 2),
            trendFormat: Format(decimals: 1)
        ),
        .bodyFatPercentage: ExpectedRow(
            symbolName: "percent",
            chartStyle: .line,
            unitPreference: nil,
            summaryFormat: Format(decimals: 1, unitSuffix: "%", spacesUnit: false),
            trendFormat: Format(decimals: 1, unitSuffix: "%", spacesUnit: false)
        )
    ]

    func testPresentationTableMatchesPinnedValues() {
        XCTAssertEqual(Set(expected.keys), Set(HealthMetricPresentation.all.keys))

        for (kind, row) in expected {
            guard let presentation = HealthMetricPresentation.presentation(for: kind) else {
                XCTFail("no presentation for \(kind.rawValue)")
                continue
            }
            XCTAssertEqual(presentation.symbolName, row.symbolName, kind.rawValue)
            XCTAssertEqual(presentation.chartStyle, row.chartStyle, kind.rawValue)
            XCTAssertEqual(presentation.unitPreference, row.unitPreference, kind.rawValue)
            XCTAssertEqual(presentation.summaryFormat, row.summaryFormat, kind.rawValue)
            XCTAssertEqual(presentation.trendFormat, row.trendFormat, kind.rawValue)
        }
    }

    /// The tints the watch complications and the widget both key off, pinned as
    /// sRGB components (`ProjectConfigurationTests` compares the watch table
    /// against these same values at runtime).
    func testTintsMatchPinnedComponents() {
        let expectedTints: [HealthMetricKind: [Double]] = [
            .readiness: [0.12, 0.68, 0.55],
            .stress: [0.90, 0.35, 0.75],
            .heartRate: [1.00, 0.25, 0.45],
            .restingHeartRate: [1.00, 0.25, 0.45],
            .heartRateVariability: [1.00, 0.25, 0.45],
            .cardioFitness: [1.00, 0.25, 0.45],
            .respiratoryRate: [0.00, 0.75, 0.85],
            .oxygenSaturation: [0.00, 0.75, 0.85],
            .wristTemperature: [0.00, 0.75, 0.85],
            .sleep: [0.20, 0.72, 1.00],
            .steps: [1.00, 0.38, 0.12],
            .activeEnergy: [1.00, 0.38, 0.12],
            .exerciseMinutes: [1.00, 0.38, 0.12],
            .trainingLoad: [1.00, 0.38, 0.12],
            .restingEnergy: [0.14, 0.72, 0.42],
            .timeInDaylight: [0.10, 0.58, 1.00],
            .bodyMass: [0.50, 0.34, 1.00],
            .bodyFatPercentage: [1.00, 0.68, 0.08]
        ]

        for (kind, components) in expectedTints {
            guard let tint = HealthMetricPresentation.presentation(for: kind)?.tint else {
                XCTFail("no presentation for \(kind.rawValue)")
                continue
            }
            let actual = UIColor(tint).cgColor.components ?? []
            XCTAssertGreaterThanOrEqual(actual.count, 3, kind.rawValue)
            for index in 0..<3 {
                XCTAssertEqual(Double(actual[index]), components[index], accuracy: 0.001, kind.rawValue)
            }
        }
    }

    // MARK: - Joined text

    func testNumberFormatJoinsUnitsTheWayEachContextDid() {
        XCTAssertEqual(Format(decimals: 0, unitSuffix: "BPM").text(42.567), "43 BPM")
        XCTAssertEqual(Format(decimals: 0, unitSuffix: "%", spacesUnit: false).text(42.567), "43%")
        XCTAssertEqual(Format(decimals: 2).text(42.567), "42.57")
        XCTAssertEqual(Format(decimals: 1).text(42.567, unit: "kg"), "42.6 kg")
    }
}
