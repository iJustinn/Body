//
//  BodyHomeTrendCard.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHomeSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

struct BodyHomeTrendsSection: View {
    let cards: [BodyHomeTrendCard.Model]
    let canToggleAll: Bool
    let showsAllTrends: Bool
    let toggleAll: () -> Void
    /// Shared with `BodyHomeView` so each trend card is a zoom source for its detail push.
    let zoomNamespace: Namespace.ID
    /// Set on a foldable's inner screen: cards hand their route to Home's left pane
    /// instead of pushing.
    var onSelect: ((HomeMetricRoute) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                ForEach(cards) { card in
                    BodyHomeRouteLink(route: .trend(card.presentation.kind), onSelect: onSelect) {
                        BodyHomeTrendCard(model: card, translucentFillOpacity: 0.09)
                            .matchedTransitionSource(id: HomeMetricRoute.trend(card.presentation.kind), in: zoomNamespace) {
                                $0.clipShape(.rect(cornerRadius: 28, style: .continuous))
                            }
                    }
                    .buttonStyle(.plain)
                    .bodyCardTapHaptics()
                }
            }

            if canToggleAll {
                Button(action: toggleAll) {
                    Text(showsAllTrends ? "Show Fewer Trends" : "Show All Trends")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BodyHomeTrendCard: View {
    struct Model: Identifiable {
        let presentation: BodyHomeTrendCardPresentation
        let symbolName: String
        let symbolColor: Color

        /// Namespaces the trend card's identity away from the grid card of the same
        /// metric. Both live in Home's single ScrollView, and `BodyHomeCardKind` and
        /// `HealthMetricKind` share raw values ("heartRate", "oxygenSaturation"), so
        /// an un-prefixed id made `scrollTo` ambiguous: a readiness-hero warning
        /// badge could scroll to the trend card at the bottom of the page while the
        /// glow lit the grid card off-screen above it.
        static let scrollIDPrefix = "trend-"

        var id: String {
            Self.scrollIDPrefix + presentation.id
        }
    }

    let model: Model
    let showsNavigationIndicator: Bool
    let translucent: Bool
    let translucentFillOpacity: Double

    init(model: Model, showsNavigationIndicator: Bool = true, translucent: Bool = true, translucentFillOpacity: Double = 0.06) {
        self.model = model
        self.showsNavigationIndicator = showsNavigationIndicator
        self.translucent = translucent
        self.translucentFillOpacity = translucentFillOpacity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Text(model.presentation.messageText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider()
                .overlay(Color.secondary.opacity(0.18))

            VStack(spacing: 8) {
                BodyHomeTrendComparisonChart(
                    presentation: model.presentation,
                    color: model.symbolColor
                )
                .frame(height: 128)

                averageLabels
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(cornerRadius: 28, translucent: translucent, translucentFillOpacity: translucentFillOpacity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.symbolColor)
                .accessibilityHidden(true)

            Text(String(localized: String.LocalizationValue(model.presentation.title)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(model.symbolColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 8)

            if showsNavigationIndicator {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
    }

    private var averageLabels: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.presentation.baselineAverageText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(model.presentation.baselinePeriodText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(model.presentation.recentAverageText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(model.symbolColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(model.presentation.recentPeriodText)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(model.symbolColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }
}

@MainActor
enum BodyHomeTrendCardFactory {
    private struct Configuration {
        let kind: HealthMetricKind
        let title: String
        let series: HealthTrendSeries
        let chartStyle: BodyHealthMetricChartStyle
        let symbolName: String
        let symbolColor: Color
        let valueFormatter: (Double) -> String
        let messageStyle: BodyHomeTrendMessageStyle
    }

    static func cards(
        trends: HealthTrendSnapshot,
        selection: BodyHomeTrendCardSelection? = nil,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference,
        includesStable: Bool,
        cache: BodyHomeTrendComputationCache
    ) -> [BodyHomeTrendCard.Model] {
        BodyHomeTrendCardKind.defaultOrder.compactMap { trendKind in
            if let selection, selection.includes(trendKind) == false {
                return nil
            }

            return card(
                for: trendKind,
                trends: trends,
                temperatureUnitPreference: temperatureUnitPreference,
                energyUnitPreference: energyUnitPreference,
                weightUnitPreference: weightUnitPreference,
                includesStable: includesStable,
                cache: cache
            )
        }
    }

    static func card(
        for metricKind: HealthMetricKind,
        trends: HealthTrendSnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference,
        includesStable: Bool,
        cache: BodyHomeTrendComputationCache
    ) -> BodyHomeTrendCard.Model? {
        guard let trendKind = BodyHomeTrendCardKind(metricKind: metricKind) else {
            return nil
        }

        return card(
            for: trendKind,
            trends: trends,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference,
            includesStable: includesStable,
            cache: cache
        )
    }

    private static func card(
        for trendKind: BodyHomeTrendCardKind,
        trends: HealthTrendSnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference,
        includesStable: Bool,
        cache: BodyHomeTrendComputationCache
    ) -> BodyHomeTrendCard.Model? {
        let configuration = configuration(
            for: trendKind,
            trends: trends,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        )
        guard let result = cache.result(
            for: configuration.kind,
            series: configuration.series,
            includesStable: includesStable
        ) else {
            return nil
        }

        let presentation = BodyHomeTrendCardPresentation.make(
            from: result,
            kind: configuration.kind,
            title: configuration.title,
            chartStyle: configuration.chartStyle,
            valueFormatter: configuration.valueFormatter,
            messageStyle: configuration.messageStyle
        )

        return BodyHomeTrendCard.Model(
            presentation: presentation,
            symbolName: configuration.symbolName,
            symbolColor: configuration.symbolColor
        )
    }

    /// Formats a raw value the same way this card's chart labels do, without
    /// building a full card. Used to keep the widget's number formatting in
    /// parity with Home's, since both must agree on how a metric reads.
    static func formattedValue(
        _ value: Double,
        for kind: BodyHomeTrendCardKind,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> String {
        configuration(
            for: kind,
            trends: .empty,
            temperatureUnitPreference: temperatureUnitPreference,
            energyUnitPreference: energyUnitPreference,
            weightUnitPreference: weightUnitPreference
        ).valueFormatter(value)
    }

    private static func configuration(
        for trendKind: BodyHomeTrendCardKind,
        trends: HealthTrendSnapshot,
        temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference,
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        weightUnitPreference: BodyValueFormat.WeightUnitPreference
    ) -> Configuration {
        let temperatureUnit = BodyValueFormat.temperatureDisplay(
            celsius: 0,
            temperatureUnitPreference: temperatureUnitPreference
        ).unit
        let energyUnit = energyUnitPreference.unitLabel
        let massUnit = BodyValueFormat.massValue(
            kilograms: 0,
            weightUnitPreference: weightUnitPreference
        ).unit

        // Symbol, tint, chart shape and value text come from the shared metric
        // table, so a card cannot drift from the Home summary card above it or
        // from the widget that mirrors it. Only the title, the series and the
        // message sentence are per-card. Every kind has a row, so the
        // formatter's fallback is unreachable (`HealthMetricPresentationTests`).
        let presentation = trendKind.presentation
        let symbolName = trendKind.iconName
        let symbolColor = trendKind.tintColor
        let chartStyle: BodyHealthMetricChartStyle = presentation?.chartStyle == .bar ? .bar : .line
        let preferenceUnit: String? = {
            switch presentation.flatMap({ $0.unitPreference }) {
            case .temperature:
                return temperatureUnit
            case .energy:
                return energyUnit
            case .mass:
                return massUnit
            case nil:
                return nil
            }
        }()
        let valueFormatter: (Double) -> String = { value in
            guard let format = presentation?.trendFormat else {
                return BodyValueFormat.numberText(value, decimals: 0)
            }
            return format.text(value, unit: preferenceUnit)
        }

        switch trendKind {
        case .readiness:
            return Configuration(
                kind: .readiness,
                title: "Readiness",
                series: trends.series(for: .readiness),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your readiness score")
            )
        case .stress:
            return Configuration(
                kind: .stress,
                title: "Stress",
                series: trends.series(for: .stress),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your stress level")
            )
        case .heartRate:
            return Configuration(
                kind: .heartRate,
                title: "Heart Rate",
                series: trends.series(for: .heartRate),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your heart rate")
            )
        case .restingHeartRate:
            return Configuration(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                series: trends.series(for: .restingHeartRate),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your resting heart rate")
            )
        case .heartRateVariability:
            return Configuration(
                kind: .heartRateVariability,
                title: "HRV",
                series: trends.series(for: .heartRateVariability),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your HRV")
            )
        case .cardioFitness:
            return Configuration(
                kind: .cardioFitness,
                title: "Cardio Fitness",
                series: trends.series(for: .cardioFitness),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your cardio fitness")
            )
        case .respiratoryRate:
            return Configuration(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                series: trends.series(for: .respiratoryRate),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your respiratory rate")
            )
        case .oxygenSaturation:
            return Configuration(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                series: trends.series(for: .oxygenSaturation),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your blood oxygen")
            )
        case .sleep:
            return Configuration(
                kind: .sleep,
                title: "Sleep",
                series: trends.series(for: .sleep),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: { BodyValueFormat.sleepDurationText(for: $0 * 60 * 60) },
                messageStyle: .average(subject: "your sleep duration")
            )
        case .wristTemperature:
            return Configuration(
                kind: .wristTemperature,
                title: "Skin Temperature",
                series: trends.series(for: .wristTemperature).mapValues {
                    BodyValueFormat.temperatureValue(
                        celsius: $0,
                        temperatureUnitPreference: temperatureUnitPreference
                    ).value
                },
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your skin temperature")
            )
        case .steps:
            return Configuration(
                kind: .steps,
                title: "Steps",
                series: trends.series(for: .steps),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .quantity(subject: "The number of steps you took per day")
            )
        case .activeEnergy:
            return Configuration(
                kind: .activeEnergy,
                title: "Active Energy",
                series: trends.series(for: .activeEnergy).mapValues {
                    BodyValueFormat.energyValue(
                        kilocalories: $0,
                        energyUnitPreference: energyUnitPreference
                    ).value
                },
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .quantity(subject: "Your active energy")
            )
        case .restingEnergy:
            return Configuration(
                kind: .restingEnergy,
                title: "Resting Energy",
                series: trends.series(for: .restingEnergy).mapValues {
                    BodyValueFormat.energyValue(
                        kilocalories: $0,
                        energyUnitPreference: energyUnitPreference
                    ).value
                },
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .quantity(subject: "Your resting energy")
            )
        case .exerciseMinutes:
            return Configuration(
                kind: .exerciseMinutes,
                title: "Exercise Minutes",
                series: trends.series(for: .exerciseMinutes),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .quantity(subject: "Your exercise minutes")
            )
        case .trainingLoad:
            return Configuration(
                kind: .trainingLoad,
                title: "Training Load",
                series: trends.series(for: .trainingLoad),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .quantity(subject: "Your training load ratio")
            )
        case .timeInDaylight:
            return Configuration(
                kind: .timeInDaylight,
                title: "Time In Daylight",
                series: trends.series(for: .timeInDaylight),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .quantity(subject: "Your time in daylight")
            )
        case .bodyMass:
            return Configuration(
                kind: .bodyMass,
                title: "Weight",
                series: trends.series(for: .bodyMass).mapValues {
                    BodyValueFormat.massValue(
                        kilograms: $0,
                        weightUnitPreference: weightUnitPreference
                    ).value
                },
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your weight")
            )
        case .bodyFatPercentage:
            return Configuration(
                kind: .bodyFatPercentage,
                title: "Body Fat",
                series: trends.series(for: .bodyFatPercentage),
                chartStyle: chartStyle,
                symbolName: symbolName,
                symbolColor: symbolColor,
                valueFormatter: valueFormatter,
                messageStyle: .average(subject: "your body fat")
            )
        }
    }
}

/// The Home card's chart: the shared `BodyTrendComparisonPlot`, fed from the
/// card's presentation, with the dots filled in the card's own background color.
struct BodyHomeTrendComparisonChart: View {
    typealias Domain = BodyTrendComparisonPlot.Domain

    let presentation: BodyHomeTrendCardPresentation
    let color: Color

    var body: some View {
        BodyTrendComparisonPlot(
            values: presentation.displayCalendarPoints.map(\.value),
            baselineEndIndex: presentation.displayBaselineEndIndex,
            baselineAverage: presentation.baselineAverage,
            recentAverage: presentation.recentAverage,
            chartStyle: presentation.chartStyle.sharedStyle,
            color: color,
            dotFill: Color(.secondarySystemBackground)
        )
    }

    static func domain(values: [Double], chartStyle: BodyHealthMetricChartStyle) -> Domain {
        BodyTrendComparisonPlot.domain(values: values, chartStyle: chartStyle.sharedStyle)
    }

    static func barHeight(for value: Double?, in height: CGFloat, domain: Domain) -> CGFloat {
        BodyTrendComparisonPlot.barHeight(for: value, in: height, domain: domain)
    }

    static func yPosition(for value: Double, in size: CGSize, domain: Domain) -> CGFloat {
        BodyTrendComparisonPlot.yPosition(for: value, in: size, domain: domain)
    }
}

extension BodyHealthMetricChartStyle {
    var sharedStyle: HealthMetricChartStyle {
        switch self {
        case .line: return .line
        case .bar: return .bar
        }
    }
}
