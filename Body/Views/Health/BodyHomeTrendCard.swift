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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                ForEach(cards) { card in
                    NavigationLink(value: HomeMetricRoute.trend(card.presentation.kind)) {
                        BodyHomeTrendCard(model: card, translucentFillOpacity: 0.09)
                            .matchedTransitionSource(id: HomeMetricRoute.trend(card.presentation.kind), in: zoomNamespace) {
                                $0.clipShape(.rect(cornerRadius: 28, style: .continuous))
                            }
                    }
                    .buttonStyle(.plain)
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

        var id: String {
            presentation.id
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
        /// The store's `healthTrends` generation, forwarded to the cache as a
        /// discriminator. Defaults to 0 for callers outside the Home page.
        generation: Int = 0,
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
                generation: generation,
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
        /// The store's `healthTrends` generation, forwarded to the cache as a
        /// discriminator. Defaults to 0 for callers outside the Home page.
        generation: Int = 0,
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
            generation: generation,
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
        /// The store's `healthTrends` generation, forwarded to the cache as a
        /// discriminator. Defaults to 0 for callers outside the Home page.
        generation: Int = 0,
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
            includesStable: includesStable,
            generation: generation
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

        switch trendKind {
        case .readiness:
            return Configuration(
                kind: .readiness,
                title: "Readiness",
                series: trends.series(for: .readiness),
                chartStyle: .line,
                symbolName: "bolt.heart.fill",
                symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                messageStyle: .average(subject: "your readiness score")
            )
        case .stress:
            return Configuration(
                kind: .stress,
                title: "Stress",
                series: trends.series(for: .stress),
                chartStyle: .line,
                symbolName: "brain.head.profile.fill",
                symbolColor: Color(red: 0.90, green: 0.35, blue: 0.75),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
                messageStyle: .average(subject: "your stress level")
            )
        case .heartRate:
            return Configuration(
                kind: .heartRate,
                title: "Heart Rate",
                series: trends.series(for: .heartRate),
                chartStyle: .line,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " BPM" },
                messageStyle: .average(subject: "your heart rate")
            )
        case .restingHeartRate:
            return Configuration(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                series: trends.series(for: .restingHeartRate),
                chartStyle: .line,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " BPM" },
                messageStyle: .average(subject: "your resting heart rate")
            )
        case .heartRateVariability:
            return Configuration(
                kind: .heartRateVariability,
                title: "HRV",
                series: trends.series(for: .heartRateVariability),
                chartStyle: .line,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " ms" },
                messageStyle: .average(subject: "your HRV")
            )
        case .cardioFitness:
            return Configuration(
                kind: .cardioFitness,
                title: "Cardio Fitness",
                series: trends.series(for: .cardioFitness),
                chartStyle: .line,
                symbolName: "arrow.up.heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " VO₂ max" },
                messageStyle: .average(subject: "your cardio fitness")
            )
        case .respiratoryRate:
            return Configuration(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                series: trends.series(for: .respiratoryRate),
                chartStyle: .line,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " br/min" },
                messageStyle: .average(subject: "your respiratory rate")
            )
        case .oxygenSaturation:
            return Configuration(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                series: trends.series(for: .oxygenSaturation),
                chartStyle: .line,
                symbolName: "drop.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                messageStyle: .average(subject: "your blood oxygen")
            )
        case .sleep:
            return Configuration(
                kind: .sleep,
                title: "Sleep",
                series: trends.series(for: .sleep),
                chartStyle: .line,
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
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
                chartStyle: .line,
                symbolName: "thermometer.medium",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + temperatureUnit },
                messageStyle: .average(subject: "your skin temperature")
            )
        case .steps:
            return Configuration(
                kind: .steps,
                title: "Steps",
                series: trends.series(for: .steps),
                chartStyle: .bar,
                symbolName: "figure.walk",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " steps" },
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
                chartStyle: .bar,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " " + energyUnit },
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
                chartStyle: .bar,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " " + energyUnit },
                messageStyle: .quantity(subject: "Your resting energy")
            )
        case .exerciseMinutes:
            return Configuration(
                kind: .exerciseMinutes,
                title: "Exercise Minutes",
                series: trends.series(for: .exerciseMinutes),
                chartStyle: .bar,
                symbolName: "figure.run",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " min" },
                messageStyle: .quantity(subject: "Your exercise minutes")
            )
        case .trainingLoad:
            return Configuration(
                kind: .trainingLoad,
                title: "Training Load",
                series: trends.series(for: .trainingLoad),
                chartStyle: .line,
                symbolName: "figure.strengthtraining.traditional",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 2) },
                messageStyle: .quantity(subject: "Your training load ratio")
            )
        case .timeInDaylight:
            return Configuration(
                kind: .timeInDaylight,
                title: "Time In Daylight",
                series: trends.series(for: .timeInDaylight),
                chartStyle: .bar,
                symbolName: "sun.max.fill",
                symbolColor: Color(red: 0.10, green: 0.58, blue: 1.00),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " min" },
                messageStyle: .quantity(subject: "Your time in daylight")
            )
        case .bodyMass:
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                weightUnitPreference: weightUnitPreference
            ).unit
            return Configuration(
                kind: .bodyMass,
                title: "Weight",
                series: trends.series(for: .bodyMass).mapValues {
                    BodyValueFormat.massValue(
                        kilograms: $0,
                        weightUnitPreference: weightUnitPreference
                    ).value
                },
                chartStyle: .line,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + massUnit },
                messageStyle: .average(subject: "your weight")
            )
        case .bodyFatPercentage:
            return Configuration(
                kind: .bodyFatPercentage,
                title: "Body Fat",
                series: trends.series(for: .bodyFatPercentage),
                chartStyle: .line,
                symbolName: "percent",
                symbolColor: Color(red: 1.00, green: 0.68, blue: 0.08),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "%" },
                messageStyle: .average(subject: "your body fat")
            )
        }
    }
}

struct BodyHomeTrendBarLayout: Equatable {
    static let minimumBarWidth: CGFloat = 3
    static let preferredSpacing: CGFloat = 5

    let barWidth: CGFloat
    let spacing: CGFloat

    static func fitting(barCount: Int, availableWidth: CGFloat) -> BodyHomeTrendBarLayout {
        guard barCount > 0, availableWidth.isFinite, availableWidth > 0 else {
            return BodyHomeTrendBarLayout(barWidth: 0, spacing: 0)
        }

        guard barCount > 1 else {
            return BodyHomeTrendBarLayout(barWidth: availableWidth, spacing: 0)
        }

        let count = CGFloat(barCount)
        let gapCount = CGFloat(barCount - 1)
        let minimumBarsWidth = minimumBarWidth * count
        guard minimumBarsWidth < availableWidth else {
            return BodyHomeTrendBarLayout(barWidth: availableWidth / count, spacing: 0)
        }

        let spacing = min(preferredSpacing, (availableWidth - minimumBarsWidth) / gapCount)
        let barWidth = (availableWidth - spacing * gapCount) / count
        return BodyHomeTrendBarLayout(barWidth: barWidth, spacing: spacing)
    }
}

struct BodyHomeTrendComparisonChart: View {
    let presentation: BodyHomeTrendCardPresentation
    let color: Color

    private struct PlotEntry: Identifiable {
        let point: HealthTrendCalendarPoint
        let position: CGPoint
        let index: Int

        var id: Date {
            point.date
        }

        var hasValue: Bool {
            point.value?.isFinite == true
        }
    }

    var body: some View {
        // The domain and the average-line segments are derived once per pass and
        // handed down: they used to be recomputed inside `barHeight`, `yPosition`
        // and `averageLine`, so a card with 30 bars walked the point list dozens
        // of times per render.
        let domain = Self.domain(for: presentation)

        return GeometryReader { proxy in
            let entries = plotEntries(in: proxy.size, domain: domain)
            let segments = presentation.averageLineSegments(in: proxy.size.width)
            ZStack {
                switch presentation.chartStyle {
                case .line:
                    linePlot(entries: entries)
                case .bar:
                    barPlot(entries: entries, size: proxy.size, domain: domain)
                }

                averageLine(
                    value: presentation.baselineAverage,
                    in: proxy.size,
                    domain: domain,
                    color: Color.secondary.opacity(0.64),
                    xRange: segments.baseline
                )

                averageLine(
                    value: presentation.recentAverage,
                    in: proxy.size,
                    domain: domain,
                    color: color,
                    xRange: segments.recent
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func linePlot(entries: [PlotEntry]) -> some View {
        let valueEntries = entries.filter(\.hasValue)

        return ZStack {
            if valueEntries.count > 1 {
                Path { path in
                    path.move(to: valueEntries[0].position)
                    for entry in valueEntries.dropFirst() {
                        path.addLine(to: entry.position)
                    }
                }
                .stroke(
                    Color.secondary.opacity(0.28),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }

            ForEach(valueEntries) { entry in
                Circle()
                    .stroke(Color.secondary.opacity(0.34), lineWidth: 3)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
                    .frame(width: 8, height: 8)
                    .position(entry.position)
            }
        }
    }

    private func barPlot(entries: [PlotEntry], size: CGSize, domain: Domain) -> some View {
        let layout = BodyHomeTrendBarLayout.fitting(barCount: entries.count, availableWidth: size.width)

        return HStack(alignment: .bottom, spacing: layout.spacing) {
            ForEach(entries) { entry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor(for: entry))
                    .frame(
                        width: layout.barWidth,
                        height: Self.barHeight(for: entry.point.value, in: size.height, domain: domain)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func averageLine(
        value: Double,
        in size: CGSize,
        domain: Domain,
        color: Color,
        xRange: ClosedRange<CGFloat>
    ) -> some View {
        let y = Self.yPosition(for: value, in: size, domain: domain)

        return Path { path in
            path.move(to: CGPoint(x: xRange.lowerBound, y: y))
            path.addLine(to: CGPoint(x: xRange.upperBound, y: y))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: BodyHomeTrendCardPresentation.averageLineStrokeWidth,
                lineCap: .round
            )
        )
    }

    private func plotEntries(in size: CGSize, domain: Domain) -> [PlotEntry] {
        let points = presentation.displayCalendarPoints
        let denominator = max(CGFloat(points.count - 1), 1)
        return points.enumerated().map { index, point in
            let x = size.width * CGFloat(index) / denominator
            let y = Self.yPosition(for: point.value ?? domain.minimum, in: size, domain: domain)
            return PlotEntry(point: point, position: CGPoint(x: x, y: y), index: index)
        }
    }

    private func barColor(for entry: PlotEntry) -> Color {
        guard entry.hasValue else {
            return Color.secondary.opacity(0.10)
        }

        return entry.index >= presentation.displayRecentStartIndex
            ? color.opacity(0.42)
            : Color.secondary.opacity(0.28)
    }

    /// The chart's value domain, derived once per render from the visible points
    /// plus the two average lines. Static and input-only so it can be tested
    /// directly against degenerate series (all equal, a single point, none).
    struct Domain: Equatable {
        let minimum: Double
        let maximum: Double
    }

    static func domain(for presentation: BodyHomeTrendCardPresentation) -> Domain {
        domain(
            values: presentation.displayCalendarPoints.compactMap(\.value).filter(\.isFinite)
                + [presentation.baselineAverage, presentation.recentAverage],
            chartStyle: presentation.chartStyle
        )
    }

    static func domain(values: [Double], chartStyle: BodyHealthMetricChartStyle) -> Domain {
        let finite = values.filter(\.isFinite)
        let lowest = finite.min() ?? 0
        let highest = finite.max() ?? (finite.isEmpty ? 1 : lowest)
        let padding = max((highest - lowest) * 0.16, 1)
        // Bars are read against zero; a line chart pads both ends so a flat series
        // still draws inside the plot rather than along its edge.
        let minimum = chartStyle == .line ? max(0, lowest - padding) : 0
        return Domain(minimum: minimum, maximum: highest + padding)
    }

    static func barHeight(for value: Double?, in height: CGFloat, domain: Domain) -> CGFloat {
        guard let value, value.isFinite else {
            return max(height * 0.05, 4)
        }

        return max(height * CGFloat(normalized(value, in: domain)), 4)
    }

    static func yPosition(for value: Double, in size: CGSize, domain: Domain) -> CGFloat {
        size.height - (size.height * CGFloat(normalized(value, in: domain)))
    }

    private static func normalized(_ value: Double, in domain: Domain) -> Double {
        let range = max(domain.maximum - domain.minimum, 1)
        return min(max((value - domain.minimum) / range, 0), 1)
    }
}
