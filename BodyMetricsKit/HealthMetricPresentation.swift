//
//  HealthMetricPresentation.swift
//  Body
//
//  The one table describing how a metric LOOKS: its SF Symbol, its tint, the
//  chart shape its series is drawn with, the unit preference its unit comes
//  from, and the two number formats it is written with.
//
//  The same tuple used to be spelled out independently in `HealthWidgetMetric`,
//  `BodyHomeTrendCardKind`, `BodyHomeTrendCardFactory.configuration(for:)`,
//  `HealthWidgetSnapshotBuilder` and `BodyHomeView.buildMetricCards` (see
//  issues-fable-51 A4), so a widget and the card it mirrors could drift apart
//  without a test noticing. `HealthMetricQueryDescriptor` is the same idea for
//  the query side.
//
//  Two number formats, not one: the Home summary card and the widget's
//  preview values write a metric differently from the trend card and the
//  widget's average text, and both spellings are shipped behaviour. HRV reads
//  "42.6 ms" on the summary card and "43 ms" on the trend card; heart rate is
//  "bpm" on one and "BPM" on the other; steps carry no unit on the summary
//  card and " steps" on the trend card; weight is written to two decimals on
//  the summary card and one on the trend card. Unifying them would be a
//  visible change, so the table keeps both contexts.
//
//  Titles are deliberately absent: they live in three localization tables and
//  moving the strings would break the Chinese catalog completeness test.
//
//  `.basics`, `.bodyMassIndex` and `.vitals` have no row, because neither the
//  trend cards nor the widget present them as a single value. `.readiness`,
//  `.stress`, `.sleep` and `.wristTemperature` have a row but no
//  `summaryFormat`: their summary cards write a score, a duration or a
//  baseline deviation rather than a plain number with a unit. `.cardioFitness`
//  has none either, because its summary card still spells out its own value
//  text and is not routed through this table yet; only the plain-number
//  cards built by `BodyHomeView.metric` and `energyMetric` read it.
//

import SwiftUI

/// The shape a metric's series is drawn with, on the trend card and in the widget.
enum HealthMetricChartStyle: Equatable, Sendable {
    case line
    case bar
}

struct HealthMetricPresentation: Sendable {
    /// The unit preference a metric's unit label is read from, for the metrics
    /// whose unit is not a fixed literal. Each site resolves the label itself,
    /// because the trend card and the widget read it through different
    /// `BodyValueFormat` entry points.
    enum UnitPreferenceKind: Equatable, Sendable {
        case temperature
        case energy
        case mass
    }

    /// How a metric's value is written in one context. Unit suffixes are plain
    /// literals, never `String(localized:)`: they are symbols and abbreviations
    /// the app ships untranslated everywhere it writes them today.
    struct NumberFormat: Equatable, Sendable {
        /// Fraction digits for `BodyValueFormat.numberText`.
        let decimals: Int
        /// The unit label, without a separator, or `nil` when the metric has no
        /// unit here or takes it from `unitPreference`.
        let unitSuffix: String?
        /// Whether a space goes between the number and the unit when the two are
        /// joined into one string. Percent signs sit tight against the number.
        let spacesUnit: Bool

        init(decimals: Int, unitSuffix: String? = nil, spacesUnit: Bool = true) {
            self.decimals = decimals
            self.unitSuffix = unitSuffix
            self.spacesUnit = spacesUnit
        }

        /// The number and its unit as one string. `unit` overrides `unitSuffix`
        /// for the metrics whose label comes from a unit preference.
        func text(_ value: Double, unit overrideUnit: String? = nil) -> String {
            let number = BodyValueFormat.numberText(value, decimals: decimals)
            guard let unit = overrideUnit ?? unitSuffix else { return number }
            return number + (spacesUnit ? " " : "") + unit
        }
    }

    let symbolName: String
    let tint: Color
    let chartStyle: HealthMetricChartStyle
    let unitPreference: UnitPreferenceKind?
    /// Home summary card and widget preview values.
    let summaryFormat: NumberFormat?
    /// Trend card value text and widget trend average text.
    let trendFormat: NumberFormat?

    private init(
        symbolName: String,
        tint: Color,
        chartStyle: HealthMetricChartStyle,
        unitPreference: UnitPreferenceKind? = nil,
        summaryFormat: NumberFormat? = nil,
        trendFormat: NumberFormat? = nil
    ) {
        self.symbolName = symbolName
        self.tint = tint
        self.chartStyle = chartStyle
        self.unitPreference = unitPreference
        self.summaryFormat = summaryFormat
        self.trendFormat = trendFormat
    }

    private static let heartTint = Color(red: 1.00, green: 0.25, blue: 0.45)
    private static let breathTint = Color(red: 0.00, green: 0.75, blue: 0.85)
    private static let moveTint = Color(red: 1.00, green: 0.38, blue: 0.12)

    static let all: [HealthMetricKind: HealthMetricPresentation] = [
        .readiness: HealthMetricPresentation(
            symbolName: "bolt.heart.fill",
            tint: Color(red: 0.12, green: 0.68, blue: 0.55),
            chartStyle: .line,
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "%", spacesUnit: false)
        ),
        .stress: HealthMetricPresentation(
            symbolName: "brain.head.profile.fill",
            tint: Color(red: 0.90, green: 0.35, blue: 0.75),
            chartStyle: .line,
            trendFormat: NumberFormat(decimals: 0)
        ),
        .heartRate: HealthMetricPresentation(
            symbolName: "heart.fill",
            tint: heartTint,
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 0, unitSuffix: "bpm"),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "BPM")
        ),
        .restingHeartRate: HealthMetricPresentation(
            symbolName: "heart.fill",
            tint: heartTint,
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 0, unitSuffix: "bpm"),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "BPM")
        ),
        .heartRateVariability: HealthMetricPresentation(
            symbolName: "waveform.path.ecg",
            tint: heartTint,
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 1, unitSuffix: "ms"),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "ms")
        ),
        .cardioFitness: HealthMetricPresentation(
            symbolName: "arrow.up.heart.fill",
            tint: heartTint,
            chartStyle: .line,
            trendFormat: NumberFormat(decimals: 1, unitSuffix: "VO₂ max")
        ),
        .respiratoryRate: HealthMetricPresentation(
            symbolName: "lungs.fill",
            tint: breathTint,
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 0, unitSuffix: "br/min"),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "br/min")
        ),
        .oxygenSaturation: HealthMetricPresentation(
            symbolName: "drop.fill",
            tint: breathTint,
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 0, unitSuffix: "%", spacesUnit: false),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "%", spacesUnit: false)
        ),
        .sleep: HealthMetricPresentation(
            symbolName: "bed.double.fill",
            tint: Color(red: 0.20, green: 0.72, blue: 1.00),
            chartStyle: .line
        ),
        .wristTemperature: HealthMetricPresentation(
            symbolName: "thermometer.medium",
            tint: breathTint,
            chartStyle: .line,
            unitPreference: .temperature,
            trendFormat: NumberFormat(decimals: 1)
        ),
        .steps: HealthMetricPresentation(
            symbolName: "figure.walk",
            tint: moveTint,
            chartStyle: .bar,
            summaryFormat: NumberFormat(decimals: 0),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "steps")
        ),
        .activeEnergy: HealthMetricPresentation(
            symbolName: "flame.fill",
            tint: moveTint,
            chartStyle: .bar,
            unitPreference: .energy,
            summaryFormat: NumberFormat(decimals: 0),
            trendFormat: NumberFormat(decimals: 0)
        ),
        .restingEnergy: HealthMetricPresentation(
            symbolName: "leaf.fill",
            tint: Color(red: 0.14, green: 0.72, blue: 0.42),
            chartStyle: .bar,
            unitPreference: .energy,
            summaryFormat: NumberFormat(decimals: 0),
            trendFormat: NumberFormat(decimals: 0)
        ),
        .exerciseMinutes: HealthMetricPresentation(
            symbolName: "figure.run",
            tint: moveTint,
            chartStyle: .bar,
            summaryFormat: NumberFormat(decimals: 0),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "min")
        ),
        .trainingLoad: HealthMetricPresentation(
            symbolName: "figure.strengthtraining.traditional",
            tint: moveTint,
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 2),
            trendFormat: NumberFormat(decimals: 2)
        ),
        .timeInDaylight: HealthMetricPresentation(
            symbolName: "sun.max.fill",
            tint: Color(red: 0.10, green: 0.58, blue: 1.00),
            chartStyle: .bar,
            summaryFormat: NumberFormat(decimals: 0, unitSuffix: "min"),
            trendFormat: NumberFormat(decimals: 0, unitSuffix: "min")
        ),
        .bodyMass: HealthMetricPresentation(
            symbolName: "scalemass.fill",
            tint: Color(red: 0.50, green: 0.34, blue: 1.00),
            chartStyle: .line,
            unitPreference: .mass,
            summaryFormat: NumberFormat(decimals: 2),
            trendFormat: NumberFormat(decimals: 1)
        ),
        .bodyFatPercentage: HealthMetricPresentation(
            symbolName: "percent",
            tint: Color(red: 1.00, green: 0.68, blue: 0.08),
            chartStyle: .line,
            summaryFormat: NumberFormat(decimals: 1, unitSuffix: "%", spacesUnit: false),
            trendFormat: NumberFormat(decimals: 1, unitSuffix: "%", spacesUnit: false)
        )
    ]

    static func presentation(for kind: HealthMetricKind) -> HealthMetricPresentation? {
        all[kind]
    }
}
