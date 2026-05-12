//
//  BodyHomeView.swift
//  Body
//

import Charts
import SwiftUI
import UniformTypeIdentifiers

struct BodyHomeView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.homeCardOrderKey) private var homeCardOrderRawValue = BodyHomeCardKind.defaultRawValue
    @State private var draggedHomeCard: BodyHomeCardKind?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        if let healthDataNotice = workoutStore.healthDataNotice {
                            BodyHealthNoticeBanner(message: healthDataNotice)
                        }

                        VStack(spacing: 14) {
                            ForEach(homeCardRows) { row in
                                HStack(spacing: 14) {
                                    ForEach(row.cards) { card in
                                        reorderableHomeCard(for: card)
                                            .frame(maxWidth: .infinity)
                                    }

                                    if row.slotCount < 2 {
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                        }
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: homeCardOrder)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await workoutStore.requestAuthorizationAndRefresh()
                }
            }
            .navigationDestination(for: HealthMetricKind.self) { kind in
                BodyHealthMetricDetailView(model: detailModel(for: kind))
            }
        }
    }

    private var homeCardOrder: [BodyHomeCardKind] {
        BodyHomeCardKind.storedOrder(from: homeCardOrderRawValue)
    }

    private var homeCardRows: [BodyHomeCardLayoutRow] {
        BodyHomeCardKind.layoutRows(from: homeCardOrder)
    }

    private var metricCards: [BodyHealthMetricCard.Model] {
        let summary = workoutStore.healthSummary

        return [
            sleepMetric(summary: summary),
            basicsMetric(summary: summary),
            metric(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            ),
            metric(
                kind: .heartRateVariability,
                title: "HRV",
                summary: summary.heartRateVariability,
                unit: "ms",
                decimals: 1,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            ),
            metric(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                unit: "%",
                decimals: 0,
                symbolName: "drop.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            ),
            metric(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                summary: summary.respiratoryRate,
                unit: "br/min",
                decimals: 0,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            ),
            metric(
                kind: .activeEnergy,
                title: "Active Energy",
                summary: summary.activeEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12)
            ),
            metric(
                kind: .restingEnergy,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42)
            )
        ]
    }

    private var selectedAccent: BodyAppAccent {
        BodyAppAccent.storedValue(from: selectedAccentRawValue)
    }

    private var selectedUnitPreference: BodyValueFormat.UnitPreference {
        BodyValueFormat.UnitPreference.storedValue(from: selectedUnitPreferenceRawValue)
    }

    private func metric(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        unit: String,
        decimals: Int,
        symbolName: String,
        symbolColor: Color
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor
        )
    }

    private func sleepMetric(summary: HealthSummarySnapshot) -> BodyHealthMetricCard.Model {
        let sleepScoreText = summary.sleep.score.map { "\($0.total)" } ?? "--"

        return BodyHealthMetricCard.Model(
            kind: .sleep,
            title: "Sleep",
            value: formattedSleepDuration(summary.sleep.duration),
            unit: "",
            symbolName: "bed.double.fill",
            symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
            accessoryMetrics: [
                BodyHealthMetricCard.Model.AccessoryMetric(title: "Score", value: sleepScoreText)
            ]
        )
    }

    private func basicsMetric(summary: HealthSummarySnapshot) -> BodyHealthMetricCard.Model {
        let weightDisplay = summary.bodyMass.value.map {
            BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference, decimals: 2)
        }
        let bodyFatText = summary.bodyFatPercentage.value.map {
            BodyValueFormat.numberText($0, decimals: 1) + "%"
        } ?? "--"

        return BodyHealthMetricCard.Model(
            kind: .basics,
            title: "Basics",
            value: weightDisplay?.value ?? "--",
            unit: weightDisplay?.unit ?? BodyValueFormat.massValue(
                kilograms: 0,
                unitPreference: selectedUnitPreference
            ).unit,
            symbolName: "person.crop.circle.fill",
            symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
            accessoryMetrics: [
                BodyHealthMetricCard.Model.AccessoryMetric(title: "Body Fat", value: bodyFatText)
            ]
        )
    }

    private func formattedSleepDuration(_ duration: TimeInterval?) -> String {
        duration.map { BodyValueFormat.sleepDurationText(for: $0) } ?? "--"
    }

    private func reorderableHomeCard(for card: BodyHomeCardKind) -> some View {
        homeCardView(for: card)
            .onDrag {
                draggedHomeCard = card
                return NSItemProvider(object: card.rawValue as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: BodyHomeCardDropDelegate(
                    destination: card,
                    draggedCard: $draggedHomeCard,
                    order: homeCardOrder,
                    saveOrder: saveHomeCardOrder
                )
            )
            .accessibilityAction(named: "Move earlier") {
                moveHomeCard(card, offset: -1)
            }
            .accessibilityAction(named: "Move later") {
                moveHomeCard(card, offset: 1)
            }
    }

    @ViewBuilder
    private func homeCardView(for card: BodyHomeCardKind) -> some View {
        switch card {
        case .activityRings:
            NavigationLink {
                BodyActivityRingsDetailView()
            } label: {
                BodyActivityRingsCard(summary: workoutStore.healthSummary.activityRings)
            }
            .buttonStyle(.plain)
        default:
            if let metricKind = card.healthMetricKind,
               let metric = metricCards.first(where: { $0.kind == metricKind }) {
                NavigationLink(value: metric.kind) {
                    BodyHealthMetricCard(metric: metric)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func saveHomeCardOrder(_ order: [BodyHomeCardKind]) {
        homeCardOrderRawValue = BodyHomeCardKind.rawValue(from: order)
    }

    private func moveHomeCard(_ card: BodyHomeCardKind, offset: Int) {
        var order = homeCardOrder
        guard let currentIndex = order.firstIndex(of: card) else {
            return
        }

        let destinationIndex = min(max(currentIndex + offset, 0), order.count - 1)
        guard currentIndex != destinationIndex else {
            return
        }

        order.remove(at: currentIndex)
        order.insert(card, at: destinationIndex)
        saveHomeCardOrder(order)
    }

    private func detailModel(for kind: HealthMetricKind) -> BodyHealthMetricDetailModel {
        let summary = workoutStore.healthSummary
        let trends = workoutStore.healthTrends

        switch kind {
        case .sleep:
            return BodyHealthMetricDetailModel(
                title: "Sleep",
                value: formattedSleepDuration(summary.sleep.duration),
                unit: "",
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
                series: trends.sleep,
                basicsTrend: nil,
                sleepStageSnapshot: summary.sleep.stageSnapshot,
                sleepScore: summary.sleep.score,
                sleepVitals: summary.sleep.vitals,
                sleepDuration: summary.sleep.duration,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "h" },
                secondaryValueFormatter: nil
            )
        case .basics:
            let display = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference, decimals: 2)
            }
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                unitPreference: selectedUnitPreference
            ).unit
            let bodyMassIndexText = summary.bodyMassIndex.value.map {
                "BMI " + BodyValueFormat.numberText($0, decimals: 1)
            }
            return BodyHealthMetricDetailModel(
                title: "Basics",
                value: display?.value ?? "--",
                unit: display?.unit ?? massUnit,
                symbolName: "person.crop.circle.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                series: .empty,
                basicsTrend: BasicsTrendSummary(
                    weight: trends.bodyMass.mapValues {
                        BodyValueFormat.massValue(kilograms: $0, unitPreference: selectedUnitPreference).value
                    },
                    bodyFat: trends.bodyFatPercentage
                ),
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + massUnit },
                secondaryValueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "%" },
                headerSecondaryText: bodyMassIndexText
            )
        case .restingHeartRate:
            return metricDetail(
                kind: kind,
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            )
        case .bodyMass:
            let display = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference)
            }
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                unitPreference: selectedUnitPreference
            ).unit
            return BodyHealthMetricDetailModel(
                title: "Weight",
                value: display?.value ?? "--",
                unit: display?.unit ?? massUnit,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                series: trends.bodyMass.mapValues {
                    BodyValueFormat.massValue(kilograms: $0, unitPreference: selectedUnitPreference).value
                },
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + massUnit },
                secondaryValueFormatter: nil
            )
        case .bodyFatPercentage:
            return metricDetail(
                kind: kind,
                title: "Body Fat",
                summary: summary.bodyFatPercentage,
                unit: "%",
                decimals: 1,
                symbolName: "percent",
                symbolColor: Color(red: 1.00, green: 0.68, blue: 0.08)
            )
        case .heartRateVariability:
            return metricDetail(
                kind: kind,
                title: "HRV",
                summary: summary.heartRateVariability,
                unit: "ms",
                decimals: 1,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45)
            )
        case .oxygenSaturation:
            return metricDetail(
                kind: kind,
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                unit: "%",
                decimals: 0,
                symbolName: "drop.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            )
        case .respiratoryRate:
            return metricDetail(
                kind: kind,
                title: "Respiratory Rate",
                summary: summary.respiratoryRate,
                unit: "br/min",
                decimals: 0,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85)
            )
        case .bodyMassIndex:
            return metricDetail(
                kind: kind,
                title: "BMI",
                summary: summary.bodyMassIndex,
                unit: "",
                decimals: 1,
                symbolName: "person.fill",
                symbolColor: selectedAccent.color
            )
        case .activeEnergy:
            return metricDetail(
                kind: kind,
                title: "Active Energy",
                summary: summary.activeEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar
            )
        case .restingEnergy:
            return metricDetail(
                kind: kind,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                chartStyle: .bar
            )
        }
    }

    private func metricDetail(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        unit: String,
        decimals: Int,
        symbolName: String,
        symbolColor: Color,
        chartStyle: BodyHealthMetricChartStyle = .line
    ) -> BodyHealthMetricDetailModel {
        let suffix = unit.isEmpty ? "" : " " + unit
        return BodyHealthMetricDetailModel(
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor,
            series: workoutStore.healthTrends.series(for: kind),
            basicsTrend: nil,
            sleepStageSnapshot: nil,
            sleepScore: nil,
            sleepVitals: nil,
            sleepDuration: nil,
            chartStyle: chartStyle,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: decimals) + suffix },
            secondaryValueFormatter: nil,
            helpText: kind.detailHelpText
        )
    }
}

private struct BodyHomeCardDropDelegate: DropDelegate {
    let destination: BodyHomeCardKind
    @Binding var draggedCard: BodyHomeCardKind?
    let order: [BodyHomeCardKind]
    let saveOrder: ([BodyHomeCardKind]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedCard, draggedCard != destination else {
            return
        }

        let reordered = BodyHomeCardKind.reordered(order, moving: draggedCard, to: destination)
        guard BodyHomeCardKind.rawValue(from: reordered) != BodyHomeCardKind.rawValue(from: order) else {
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            saveOrder(reordered)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedCard = nil
        return true
    }
}

private enum BodyHealthMetricChartStyle {
    case line
    case bar
}

private struct BodyHealthMetricDetailModel {
    let title: String
    let value: String
    let unit: String
    let symbolName: String
    let symbolColor: Color
    let series: HealthTrendSeries
    let basicsTrend: BasicsTrendSummary?
    let sleepStageSnapshot: SleepStageSnapshot?
    let sleepScore: SleepScoreSummary?
    let sleepVitals: SleepVitalsSummary?
    let sleepDuration: TimeInterval?
    let chartStyle: BodyHealthMetricChartStyle
    let valueFormatter: (Double) -> String
    let secondaryValueFormatter: ((Double) -> String)?
    let headerSecondaryText: String?
    let helpText: HealthMetricDetailHelpText?

    init(
        title: String,
        value: String,
        unit: String,
        symbolName: String,
        symbolColor: Color,
        series: HealthTrendSeries,
        basicsTrend: BasicsTrendSummary?,
        sleepStageSnapshot: SleepStageSnapshot?,
        sleepScore: SleepScoreSummary?,
        sleepVitals: SleepVitalsSummary?,
        sleepDuration: TimeInterval?,
        chartStyle: BodyHealthMetricChartStyle,
        valueFormatter: @escaping (Double) -> String,
        secondaryValueFormatter: ((Double) -> String)?,
        headerSecondaryText: String? = nil,
        helpText: HealthMetricDetailHelpText? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.symbolName = symbolName
        self.symbolColor = symbolColor
        self.series = series
        self.basicsTrend = basicsTrend
        self.sleepStageSnapshot = sleepStageSnapshot
        self.sleepScore = sleepScore
        self.sleepVitals = sleepVitals
        self.sleepDuration = sleepDuration
        self.chartStyle = chartStyle
        self.valueFormatter = valueFormatter
        self.secondaryValueFormatter = secondaryValueFormatter
        self.headerSecondaryText = headerSecondaryText
        self.helpText = helpText
    }
}

private struct BodyHealthMetricDetailView: View {
    let model: BodyHealthMetricDetailModel
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue
    @State private var selectedTrendRange = BodyHealthTrendRange.defaultValue
    @State private var selectedTrendDate: Date?
    @GestureState private var isSelectingTrend = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if isSleepDetail {
                    sleepSupplementCards
                    BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                    trendCard
                } else {
                    BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                    trendCard
                    sleepSupplementCards
                }
                helpTextCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedUnitPreference: BodyValueFormat.UnitPreference {
        BodyValueFormat.UnitPreference.storedValue(from: selectedUnitPreferenceRawValue)
    }

    private var isSleepDetail: Bool {
        model.title == "Sleep"
    }

    @ViewBuilder
    private var sleepSupplementCards: some View {
        if let sleepScore = model.sleepScore {
            sleepScoreCard(sleepScore)
        }
        if let sleepStageSnapshot = model.sleepStageSnapshot {
            sleepStageCard(sleepStageSnapshot)
        }
        if let sleepVitals = model.sleepVitals {
            sleepVitalsCard(sleepVitals, duration: model.sleepDuration)
        }
    }

    @ViewBuilder
    private var helpTextCard: some View {
        if let helpText = model.helpText {
            VStack(alignment: .leading, spacing: 10) {
                Text(helpText.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(helpText.body)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bodyCardBackground()
        }
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: model.symbolName)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.symbolColor)
                .frame(width: 58, height: 58)
                .background(model.symbolColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text("Current")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.value)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if !model.unit.isEmpty {
                        Text(model.unit)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                if let headerSecondaryText = model.headerSecondaryText {
                    Text(headerSecondaryText)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 94)
        .bodyCardBackground()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedTrendRange.chartTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if model.title == "Basics" {
                    BodyBasicsTrendLegend(
                        weightColor: model.symbolColor,
                        bodyFatColor: basicsBodyFatColor
                    )
                } else if let averageSleepText {
                    Text("Avg \(averageSleepText)")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if let visibleBasicsTrend {
                if visibleBasicsTrend.isEmpty {
                    Text("No recent data")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    BodyBasicsTrendChart(
                        trend: visibleBasicsTrend,
                        selectedRange: selectedTrendRange,
                        weightColor: model.symbolColor,
                        bodyFatColor: basicsBodyFatColor,
                        weightFormatter: model.valueFormatter,
                        bodyFatFormatter: model.secondaryValueFormatter ?? {
                            BodyValueFormat.numberText($0, decimals: 1) + "%"
                        }
                    )
                    .frame(height: 278)
                }
            } else if visibleSeries.isEmpty {
                Text("No recent data")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart {
                    if model.chartStyle == .bar, let selectedTrendPoint {
                        RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                            .foregroundStyle(Color.secondary.opacity(0.48))
                            .lineStyle(StrokeStyle(lineWidth: 1.4))
                    }

                    ForEach(visibleSeries.points) { point in
                        switch model.chartStyle {
                        case .line:
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(model.title, point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(model.symbolColor)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(model.title, point.value)
                            )
                            .foregroundStyle(model.symbolColor)
                            .symbolSize(28)
                        case .bar:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(model.title, point.value)
                            )
                            .foregroundStyle(model.symbolColor.gradient)
                            .cornerRadius(4)
                        }
                    }

                    if let selectedTrendPoint {
                        RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                            .foregroundStyle(model.chartStyle == .bar ? Color.clear : Color.secondary.opacity(0.48))
                            .lineStyle(StrokeStyle(lineWidth: 1.4))
                            .annotation(position: .top, spacing: 8) {
                                BodyChartSelectionAnnotation(
                                    eyebrow: model.chartStyle == .bar ? "TOTAL" : nil,
                                    values: [
                                        BodyChartSelectionValue(
                                            title: nil,
                                            value: chartSelectionText(for: selectedTrendPoint.value),
                                            color: model.symbolColor
                                        )
                                    ],
                                    date: selectedTrendPoint.date
                                )
                            }

                        if model.chartStyle == .line {
                            PointMark(
                                x: .value("Selected Date", selectedTrendPoint.date, unit: .day),
                                y: .value(model.title, selectedTrendPoint.value)
                            )
                            .foregroundStyle(model.symbolColor)
                            .symbolSize(82)
                        }
                    }
                }
                .chartXScale(domain: chartXDomain)
                .chartYScale(domain: chartYDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: selectedTrendRange.axisStrideDayCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(selectedTrendRange.axisLabel(for: date))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisTick()
                            .foregroundStyle(Color.secondary.opacity(0.28))
                        AxisValueLabel {
                            if let yValue = value.as(Double.self) {
                                Text(model.valueFormatter(yValue))
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedTrendDate)
                .simultaneousGesture(trendChartPressGesture)
                .frame(height: 260)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepScoreCard(_ score: SleepScoreSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep Score")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(score.total)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("/100")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 12) {
                ForEach(score.categories) { category in
                    sleepScoreBar(category)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepScoreBar(_ category: SleepScoreCategory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(category.kind.displayName)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                Text("\(category.points)/\(category.maximumPoints)")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))

                    Capsule()
                        .fill(sleepScoreColor(for: category.kind).gradient)
                        .frame(width: proxy.size.width * category.progress)
                }
            }
            .frame(height: 9)
        }
    }

    private func sleepStageCard(_ snapshot: SleepStageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Stages")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if let date = snapshot.date {
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }

            if snapshot.isEmpty {
                Text("No sleep stages today")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodySleepStageChart(snapshot: snapshot)
                    .frame(height: 260)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepVitalsCard(_ vitals: SleepVitalsSummary, duration: TimeInterval?) -> some View {
        let rows = sleepVitalRows(for: vitals, duration: duration)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Vitals")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12)

                if !rows.isEmpty {
                    Text(sleepVitalStatusTitle(for: rows))
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if rows.isEmpty {
                Text("No sleep vitals today")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                BodySleepVitalsRegionChart(rows: rows)
                    .frame(height: 292)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepVitalRows(for vitals: SleepVitalsSummary, duration: TimeInterval?) -> [SleepVitalDisplayRow] {
        var rows: [SleepVitalDisplayRow] = []

        if let heartRate = vitals.heartRate {
            rows.append(SleepVitalDisplayRow(
                title: "Heart Rate",
                value: BodyValueFormat.numberText(heartRate.rounded(), decimals: 0),
                unit: "BPM",
                symbolName: "heart.fill",
                tintColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                numericValue: heartRate,
                referenceRange: SleepVitalReferenceRange(typicalLowerBound: 40, typicalUpperBound: 70)
            ))
        }

        if let respiratoryRate = vitals.respiratoryRate {
            rows.append(SleepVitalDisplayRow(
                title: "Respiratory",
                value: BodyValueFormat.numberText(respiratoryRate.rounded(), decimals: 0),
                unit: "br/min",
                symbolName: "lungs.fill",
                tintColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                numericValue: respiratoryRate,
                referenceRange: SleepVitalReferenceRange(typicalLowerBound: 12, typicalUpperBound: 20)
            ))
        }

        if let wristTemperatureCelsius = vitals.wristTemperatureCelsius {
            let display = BodyValueFormat.temperatureDisplay(
                celsius: wristTemperatureCelsius,
                unitPreference: selectedUnitPreference
            )
            rows.append(SleepVitalDisplayRow(
                title: "Wrist Temp",
                value: display.value,
                unit: display.unit,
                symbolName: "thermometer.medium",
                tintColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                numericValue: wristTemperatureCelsius,
                referenceRange: SleepVitalReferenceRange(typicalLowerBound: 35.8, typicalUpperBound: 37.2)
            ))
        }

        if let oxygenSaturation = vitals.oxygenSaturation {
            rows.append(SleepVitalDisplayRow(
                title: "Blood Oxygen",
                value: BodyValueFormat.numberText(oxygenSaturation.rounded(), decimals: 0),
                unit: "%",
                symbolName: "drop.fill",
                tintColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                numericValue: oxygenSaturation,
                referenceRange: SleepVitalReferenceRange(typicalLowerBound: 95, typicalUpperBound: 100)
            ))
        }

        if let duration {
            rows.append(SleepVitalDisplayRow(
                title: "Sleep Duration",
                value: BodyValueFormat.sleepDurationText(for: duration),
                unit: "",
                symbolName: "bed.double.fill",
                tintColor: model.symbolColor,
                numericValue: duration / 3_600,
                referenceRange: SleepVitalReferenceRange(typicalLowerBound: 7, typicalUpperBound: 9)
            ))
        }

        return rows
    }

    private func sleepVitalStatusTitle(for rows: [SleepVitalDisplayRow]) -> String {
        SleepVitalStatusTitle.text(for: rows.map(\.region))
    }

    private var visibleSeries: HealthTrendSeries {
        model.series.limited(to: selectedTrendRange)
    }

    private var selectedTrendPoint: HealthTrendDataPoint? {
        guard isSelectingTrend else {
            return nil
        }

        return visibleSeries.selectionPoint(for: selectedTrendDate)
    }

    private var visibleBasicsTrend: BasicsTrendSummary? {
        model.basicsTrend?.limited(to: selectedTrendRange)
    }

    private var basicsBodyFatColor: Color {
        Color(red: 1.00, green: 0.68, blue: 0.08)
    }

    private var averageSleepText: String? {
        guard model.title == "Sleep", !visibleSeries.isEmpty else {
            return nil
        }

        let averageHours = visibleSeries.points.reduce(0) { $0 + $1.value } / Double(visibleSeries.points.count)
        return BodyValueFormat.sleepDurationText(for: averageHours * 60 * 60)
    }

    private func sleepScoreColor(for kind: SleepScoreCategory.Kind) -> Color {
        switch kind {
        case .duration:
            return model.symbolColor
        case .rem:
            return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .deep:
            return Color(red: 0.25, green: 0.25, blue: 0.82)
        }
    }

    private var trendChartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelectingTrend) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedTrendDate = nil
            }
    }

    private func chartSelectionText(for value: Double) -> String {
        if isSleepDetail {
            return BodyValueFormat.sleepDurationText(for: value * 60 * 60)
        }

        return model.valueFormatter(value)
    }

    private var chartXDomain: ClosedRange<Date> {
        let dates = visibleSeries.points.map(\.date)
        let leadingPadding: TimeInterval = 6 * 60 * 60
        let trailingPadding: TimeInterval = 18 * 60 * 60

        guard let startDate = dates.min(), let endDate = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-leadingPadding)...now.addingTimeInterval(trailingPadding)
        }

        return startDate.addingTimeInterval(-leadingPadding)...endDate.addingTimeInterval(trailingPadding)
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = visibleSeries.points.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        if model.chartStyle == .bar {
            let padding = max(maximum * 0.12, 1)
            return 0...(maximum + padding)
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.12, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }
}

private struct BodyHealthTrendRangeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedRange: BodyHealthTrendRange

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BodyHealthTrendRange.allCases) { range in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedRange = range
                    }
                } label: {
                    Text(range.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(selectedRange == range ? .accentColor : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .bodyTrendRangeTabBackground(
                            isSelected: selectedRange == range,
                            colorScheme: colorScheme
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BodyBasicsTrendLegend: View {
    let weightColor: Color
    let bodyFatColor: Color

    var body: some View {
        HStack(spacing: 12) {
            legendItem(title: "Weight", color: weightColor)
            legendItem(title: "Body Fat", color: bodyFatColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
    }
}

private struct BodyChartSelectionValue: Identifiable {
    let title: String?
    let value: String
    let color: Color

    var id: String {
        "\(title ?? "")-\(value)"
    }
}

private struct BodyChartSelectionAnnotation: View {
    let eyebrow: String?
    let values: [BodyChartSelectionValue]
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if values.count == 1, let value = values.first {
                Text(value.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            } else {
                ForEach(values) { value in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(value.color)
                            .frame(width: 7, height: 7)

                        if let title = value.title {
                            Text(title)
                                .foregroundColor(.secondary)
                        }

                        Text(value.value)
                            .foregroundColor(.primary)
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }

            Text(date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
    }
}

private struct BodyBasicsTrendChart: View {
    let trend: BasicsTrendSummary
    let selectedRange: BodyHealthTrendRange
    let weightColor: Color
    let bodyFatColor: Color
    let weightFormatter: (Double) -> String
    let bodyFatFormatter: (Double) -> String

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    private let axisTickValues = [0.0, 0.25, 0.5, 0.75, 1.0]

    var body: some View {
        Chart {
            ForEach(trend.weight.points) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Weight", normalized(point.value, in: weightDomain)),
                    series: .value("Metric", "Weight")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(weightColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Weight", normalized(point.value, in: weightDomain))
                )
                .foregroundStyle(weightColor)
                .symbolSize(28)
            }

            ForEach(trend.bodyFat.points) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Body Fat", normalized(point.value, in: bodyFatDomain)),
                    series: .value("Metric", "Body Fat")
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(bodyFatColor)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Body Fat", normalized(point.value, in: bodyFatDomain))
                )
                .foregroundStyle(bodyFatColor)
                .symbolSize(28)
            }

            if let selectedTrendDate {
                RuleMark(x: .value("Selected Date", selectedTrendDate, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(position: .top, spacing: 8) {
                        BodyChartSelectionAnnotation(
                            eyebrow: nil,
                            values: selectionValues(for: selectedTrendDate),
                            date: selectedTrendDate
                        )
                    }

                if let selectedWeightPoint = trend.weight.point(on: selectedTrendDate) {
                    PointMark(
                        x: .value("Selected Weight Date", selectedWeightPoint.date, unit: .day),
                        y: .value("Weight", normalized(selectedWeightPoint.value, in: weightDomain))
                    )
                    .foregroundStyle(weightColor)
                    .symbolSize(82)
                }

                if let selectedBodyFatPoint = trend.bodyFat.point(on: selectedTrendDate) {
                    PointMark(
                        x: .value("Selected Body Fat Date", selectedBodyFatPoint.date, unit: .day),
                        y: .value("Body Fat", normalized(selectedBodyFatPoint.value, in: bodyFatDomain))
                    )
                    .foregroundStyle(bodyFatColor)
                    .symbolSize(82)
                }
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: 0...1)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: selectedRange.axisStrideDayCount)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(selectedRange.axisLabel(for: date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: axisTickValues) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(weightColor.opacity(0.55))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(weightFormatter(denormalizedValue(for: yValue, in: weightDomain)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }

            AxisMarks(position: .trailing, values: axisTickValues) { value in
                AxisTick()
                    .foregroundStyle(bodyFatColor.opacity(0.55))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(bodyFatFormatter(denormalizedValue(for: yValue, in: bodyFatDomain)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
    }

    private var selectedTrendDate: Date? {
        guard isSelecting else {
            return nil
        }

        return trend.selectionDate(for: selectedDate)
    }

    private var chartXDomain: ClosedRange<Date> {
        let dates = trend.weight.points.map(\.date) + trend.bodyFat.points.map(\.date)
        let leadingPadding: TimeInterval = 6 * 60 * 60
        let trailingPadding: TimeInterval = 18 * 60 * 60

        guard let startDate = dates.min(), let endDate = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-leadingPadding)...now.addingTimeInterval(trailingPadding)
        }

        return startDate.addingTimeInterval(-leadingPadding)...endDate.addingTimeInterval(trailingPadding)
    }

    private var weightDomain: ClosedRange<Double> {
        paddedDomain(values: trend.weight.points.map(\.value))
    }

    private var bodyFatDomain: ClosedRange<Double> {
        paddedDomain(values: trend.bodyFat.points.map(\.value))
    }

    private func paddedDomain(values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.05, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
    }

    private func normalized(_ value: Double, in domain: ClosedRange<Double>) -> Double {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else {
            return 0
        }

        return min(max((value - domain.lowerBound) / span, 0), 1)
    }

    private func denormalizedValue(for normalizedValue: Double, in domain: ClosedRange<Double>) -> Double {
        domain.lowerBound + (domain.upperBound - domain.lowerBound) * normalizedValue
    }

    private var chartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelecting) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedDate = nil
            }
    }

    private func selectionValues(for date: Date) -> [BodyChartSelectionValue] {
        var values: [BodyChartSelectionValue] = []

        if let selectedWeightPoint = trend.weight.point(on: date) {
            values.append(BodyChartSelectionValue(
                title: "Weight",
                value: weightFormatter(selectedWeightPoint.value),
                color: weightColor
            ))
        }

        if let selectedBodyFatPoint = trend.bodyFat.point(on: date) {
            values.append(BodyChartSelectionValue(
                title: "Body Fat",
                value: bodyFatFormatter(selectedBodyFatPoint.value),
                color: bodyFatColor
            ))
        }

        return values
    }
}

private struct BodySleepStageChart: View {
    let snapshot: SleepStageSnapshot

    var body: some View {
        Chart {
            ForEach(stageTransitions) { transition in
                RectangleMark(
                    xStart: .value("Transition Start", transition.startDate),
                    xEnd: .value("Transition End", transition.endDate),
                    yStart: .value("Transition Stage Start", transition.lowerStagePosition),
                    yEnd: .value("Transition Stage End", transition.upperStagePosition)
                )
                .foregroundStyle(color(for: transition.tintStage).opacity(0.20))
                .cornerRadius(7)
            }

            ForEach(snapshot.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.startDate),
                    xEnd: .value("End", segment.endDate),
                    yStart: .value("Stage Start", segment.stage.chartPosition - 0.32),
                    yEnd: .value("Stage End", segment.stage.chartPosition + 0.32)
                )
                .foregroundStyle(color(for: segment.stage).gradient)
                .cornerRadius(6)
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: 0.5...4.5)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: SleepStage.allCases.map(\.chartPosition)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let position = value.as(Double.self),
                       let stage = SleepStage.stage(at: position) {
                        Text(stage.displayName)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private var stageTransitions: [SleepStageTransition] {
        let sortedSegments = snapshot.segments.sorted { $0.startDate < $1.startDate }
        let maximumConnectedGap: TimeInterval = 8 * 60
        let halfConnectorWidth: TimeInterval = 2 * 60
        let connectorStageInset = 0.28

        return zip(sortedSegments, sortedSegments.dropFirst()).compactMap { previous, next in
            guard previous.stage != next.stage else {
                return nil
            }

            let gap = next.startDate.timeIntervalSince(previous.endDate)
            guard abs(gap) <= maximumConnectedGap else {
                return nil
            }

            let boundaryStart = min(previous.endDate, next.startDate).addingTimeInterval(-halfConnectorWidth)
            let boundaryEnd = max(previous.endDate, next.startDate).addingTimeInterval(halfConnectorWidth)
            let tintStage = next.stage == .awake ? previous.stage : next.stage

            return SleepStageTransition(
                id: "\(previous.id)-\(next.id)",
                startDate: boundaryStart,
                endDate: boundaryEnd,
                lowerStagePosition: min(previous.stage.chartPosition, next.stage.chartPosition) + connectorStageInset,
                upperStagePosition: max(previous.stage.chartPosition, next.stage.chartPosition) - connectorStageInset,
                tintStage: tintStage
            )
        }
    }

    private var chartXDomain: ClosedRange<Date> {
        let startDate = snapshot.segments.map(\.startDate).min() ?? Date()
        let endDate = snapshot.segments.map(\.endDate).max() ?? Date()
        let padding: TimeInterval = 15 * 60
        return startDate.addingTimeInterval(-padding)...endDate.addingTimeInterval(padding)
    }

    private var xAxisValues: [Date] {
        axisValues(strideHours: 2, minimumCount: 4)
    }

    private func axisValues(strideHours: Int, minimumCount: Int) -> [Date] {
        let calendar = Calendar.current
        let lowerBound = chartXDomain.lowerBound
        let upperBound = chartXDomain.upperBound
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: lowerBound)
        components.minute = 0
        components.second = 0
        components.nanosecond = 0

        var current = calendar.date(from: components) ?? lowerBound
        if current < lowerBound {
            current = calendar.date(byAdding: .hour, value: 1, to: current) ?? lowerBound
        }

        var values: [Date] = []
        while current <= upperBound {
            values.append(current)
            let next = calendar.date(byAdding: .hour, value: strideHours, to: current)
                ?? current.addingTimeInterval(TimeInterval(strideHours) * 60 * 60)
            guard next > current else {
                break
            }
            current = next
        }

        if values.count < minimumCount && strideHours > 1 {
            return axisValues(strideHours: 1, minimumCount: minimumCount)
        }

        return values
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake:
            return Color(red: 1.00, green: 0.31, blue: 0.22)
        case .rem:
            return Color(red: 0.42, green: 0.80, blue: 1.00)
        case .core:
            return Color(red: 0.24, green: 0.56, blue: 1.00)
        case .deep:
            return Color(red: 0.25, green: 0.25, blue: 0.82)
        }
    }
}

private struct SleepStageTransition: Identifiable {
    let id: String
    let startDate: Date
    let endDate: Date
    let lowerStagePosition: Double
    let upperStagePosition: Double
    let tintStage: SleepStage
}

private struct SleepVitalDisplayRow: Identifiable {
    let title: String
    let value: String
    let unit: String
    let symbolName: String
    let tintColor: Color
    let numericValue: Double
    let referenceRange: SleepVitalReferenceRange

    var id: String {
        title
    }

    var region: SleepVitalRegion {
        referenceRange.region(for: numericValue)
    }

    var markerPosition: Double {
        referenceRange.markerPosition(for: numericValue)
    }
}

private extension SleepVitalRegion {
    var dotColor: Color {
        switch self {
        case .typical:
            return Color(red: 0.25, green: 0.62, blue: 1.00)
        case .low, .high:
            return Color(red: 1.00, green: 0.24, blue: 0.20)
        }
    }
}

private struct BodySleepVitalsRegionChart: View {
    let rows: [SleepVitalDisplayRow]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 12) {
                BodySleepVitalsRegionPlot(rows: rows)
                    .frame(height: 224)

                BodySleepVitalsIconAxis(rows: rows)
                    .frame(height: 28)
            }

            BodySleepVitalRegionLabels()
                .frame(width: 56, height: 224)
        }
    }
}

private struct BodySleepVitalsRegionPlot: View {
    let rows: [SleepVitalDisplayRow]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    path.addRect(CGRect(x: 0, y: 0, width: width, height: height))
                    path.move(to: CGPoint(x: 0, y: height / 3))
                    path.addLine(to: CGPoint(x: width, y: height / 3))
                    path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                    path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
                }
                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)

                ForEach(1..<max(rows.count, 1), id: \.self) { index in
                    Path { path in
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(rows.count, 1))
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    .stroke(
                        Color.secondary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
                }

                ForEach(rows.indices, id: \.self) { index in
                    BodySleepVitalRegionDot(row: rows[index])
                        .position(
                            x: xPosition(for: index, width: proxy.size.width),
                            y: yPosition(for: rows[index], height: proxy.size.height)
                        )
                }
            }
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard !rows.isEmpty else {
            return width / 2
        }

        return width * (CGFloat(index) + 0.5) / CGFloat(rows.count)
    }

    private func yPosition(for row: SleepVitalDisplayRow, height: CGFloat) -> CGFloat {
        height * CGFloat(1 - row.markerPosition)
    }
}

private struct BodySleepVitalsIconAxis: View {
    let rows: [SleepVitalDisplayRow]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(1..<max(rows.count, 1), id: \.self) { index in
                    Path { path in
                        let x = proxy.size.width * CGFloat(index) / CGFloat(max(rows.count, 1))
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    .stroke(
                        Color.secondary.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 5])
                    )
                }

                ForEach(rows.indices, id: \.self) { index in
                    Image(systemName: rows[index].symbolName)
                        .font(.system(size: 18, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.secondary.opacity(0.58))
                        .frame(width: 32, height: 28)
                        .position(
                            x: xPosition(for: index, width: proxy.size.width),
                            y: proxy.size.height / 2
                        )
                        .accessibilityLabel("\(rows[index].title): \(rows[index].value) \(rows[index].unit)")
                }
            }
        }
    }

    private func xPosition(for index: Int, width: CGFloat) -> CGFloat {
        guard !rows.isEmpty else {
            return width / 2
        }

        return width * (CGFloat(index) + 0.5) / CGFloat(rows.count)
    }
}

private struct BodySleepVitalRegionDot: View {
    let row: SleepVitalDisplayRow

    var body: some View {
        Circle()
            .fill(Color(.systemGroupedBackground))
            .frame(width: 19, height: 19)
            .overlay(
                Circle()
                    .stroke(row.region.dotColor, lineWidth: 5)
            )
            .shadow(color: row.region.dotColor.opacity(row.region == .typical ? 0 : 0.26), radius: 5)
            .accessibilityLabel("\(row.title): \(row.value) \(row.unit), \(accessibilityRegion)")
    }

    private var accessibilityRegion: String {
        switch row.region {
        case .low:
            return "Low"
        case .typical:
            return "Typical"
        case .high:
            return "High"
        }
    }
}

private struct BodySleepVitalRegionLabels: View {
    var body: some View {
        VStack(spacing: 0) {
            regionLabel("High")
            regionLabel("Typical")
            regionLabel("Low")
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundColor(Color.secondary.opacity(0.62))
    }

    private func regionLabel(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private enum BodyActivityRingPalette {
    static let move = Color(red: 1.00, green: 0.12, blue: 0.36)
    static let exercise = Color(red: 0.48, green: 1.00, blue: 0.00)
    static let stand = Color(red: 0.16, green: 0.92, blue: 0.96)
}

enum BodyActivityRingGraphicGeometry {
    static let ringLineWidth: CGFloat = 12.5
    static let fenceLineWidth: CGFloat = 2.5
    static let edgeFenceGap: CGFloat = fenceLineWidth / 2
    static let moveDiameter: CGFloat = 102
    static let exerciseDiameter: CGFloat = 72
    static let standDiameter: CGFloat = 42
    static let moveExerciseFenceDiameter: CGFloat = 87
    static let exerciseStandFenceDiameter: CGFloat = 57
    static let outerFenceDiameter: CGFloat = ringOuterEdge(diameter: moveDiameter) + edgeFenceGap + fenceLineWidth
    static let innerFenceDiameter: CGFloat = ringInnerEdge(diameter: standDiameter) - edgeFenceGap - fenceLineWidth

    static func ringOuterEdge(diameter: CGFloat) -> CGFloat {
        diameter + ringLineWidth
    }

    static func ringInnerEdge(diameter: CGFloat) -> CGFloat {
        diameter - ringLineWidth
    }

    static func fenceOuterEdge(diameter: CGFloat) -> CGFloat {
        diameter + fenceLineWidth
    }

    static func fenceInnerEdge(diameter: CGFloat) -> CGFloat {
        diameter - fenceLineWidth
    }
}

private struct BodyActivityRingsDetailView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @State private var canLoadOlderMonths = false
    @State private var isDraggingCalendar = false
    @State private var paginationGate = ActivityRingCalendarPaginationGate()
    @State private var visibleCalendarMonthCount = HealthKitWorkoutStore.recentChartMonthCount
    @State private var visibleMonthIDs: Set<String> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let calendar = Calendar.bodyGregorian

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 46) {
                    ForEach(calendarMonths) { month in
                        monthSection(month)
                            .id(month.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { _ in
                        guard !isDraggingCalendar else {
                            return
                        }

                        isDraggingCalendar = true
                        paginationGate.recordUserScroll()
                        loadPreviousVisibleMonthIfNeeded()
                    }
                    .onEnded { _ in
                        isDraggingCalendar = false
                    }
            )
            .onAppear {
                if let currentMonthID = calendarMonths.last?.id {
                    proxy.scrollTo(currentMonthID, anchor: .bottom)
                }
                DispatchQueue.main.async {
                    canLoadOlderMonths = true
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Activity Rings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var calendarMonths: [ActivityRingCalendarMonth] {
        displayHistory.calendarMonths(
            calendar: calendar,
            visibleLoadedMonthCount: visibleCalendarMonthCount
        )
    }

    private var allCalendarMonths: [ActivityRingCalendarMonth] {
        displayHistory.calendarMonths(calendar: calendar)
    }

    private var displayHistory: ActivityRingHistorySnapshot {
        let history = workoutStore.activityRingHistory
        guard history.days.isEmpty, history.loadedMonthKeys.isEmpty else {
            return history
        }

        let currentSummary = workoutStore.healthSummary.activityRings
        guard !currentSummary.isEmpty else {
            return .empty
        }

        return ActivityRingHistorySnapshot(days: [
            ActivityRingDaySummary(date: Date(), summary: currentSummary)
        ])
    }

    private func monthSection(_ month: ActivityRingCalendarMonth) -> some View {
        VStack(spacing: 13) {
            VStack(spacing: 4) {
                Text(monthTitle(for: month))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))

                    Text("x \(month.completedRingCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundColor(.secondary)
                .accessibilityLabel("\(month.completedRingCount) completed days")
            }
            .frame(maxWidth: .infinity)

            weekdayHeader

            LazyVGrid(columns: columns, spacing: 13) {
                ForEach(0..<leadingBlankCount(for: month), id: \.self) { _ in
                    Color.clear
                        .frame(height: 48)
                        .accessibilityHidden(true)
                }

                ForEach(month.days) { day in
                    BodyActivityRingCalendarDayCell(day: day)
                }
            }
        }
        .onAppear {
            visibleMonthIDs.insert(month.id)
            loadPreviousMonthIfNeeded(for: month)
        }
        .onDisappear {
            visibleMonthIDs.remove(month.id)
        }
    }

    private var weekdayHeader: some View {
        let symbols = weekdaySymbols

        return HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = DateFormatter().veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.isEmpty ? fallback : symbols
        let startIndex = max(0, calendar.firstWeekday - 1)
        return Array(source[startIndex...]) + Array(source[..<startIndex])
    }

    private func leadingBlankCount(for month: ActivityRingCalendarMonth) -> Int {
        guard let firstDate = month.days.first?.date else {
            return 0
        }

        let weekday = calendar.component(.weekday, from: firstDate)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func monthTitle(for month: ActivityRingCalendarMonth) -> String {
        guard let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else {
            return ""
        }

        return date.formatted(.dateTime.month(.abbreviated))
    }

    private func loadPreviousMonthIfNeeded(for month: ActivityRingCalendarMonth) {
        guard canLoadOlderMonths, month.id == calendarMonths.first?.id else {
            return
        }

        loadPreviousVisibleMonthIfNeeded()
    }

    private func loadPreviousVisibleMonthIfNeeded() {
        guard
            canLoadOlderMonths,
            let oldestMonthID = calendarMonths.first?.id,
            visibleMonthIDs.contains(oldestMonthID),
            paginationGate.consumeLoadIfNeeded(isOldestVisible: true)
        else {
            return
        }

        if allCalendarMonths.count > calendarMonths.count {
            visibleCalendarMonthCount += 1
            return
        }

        Task {
            await workoutStore.loadPreviousActivityRingMonthIfNeeded()
            visibleCalendarMonthCount += 1
        }
    }
}

private struct BodyActivityRingCalendarDayCell: View {
    let day: ActivityRingCalendarDay

    var body: some View {
        VStack(spacing: 5) {
            Text(dayNumberText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(day.isFuture ? Color.secondary.opacity(0.45) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            ZStack(alignment: .topTrailing) {
                BodyScaledActivityRingGraphic(summary: day.summary, size: 34)
                    .opacity(ringOpacity)

                if showsCompletionStar {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(red: 1.00, green: 0.78, blue: 0.12))
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                        .offset(x: 3, y: -4)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 38, height: 34)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var dayNumberText: String {
        "\(Calendar.bodyGregorian.component(.day, from: day.date))"
    }

    private var ringOpacity: Double {
        if day.isFuture {
            return 0.18
        }

        return 1
    }

    private var showsCompletionStar: Bool {
        day.hasData && !day.isFuture && day.summary.isCompleted
    }

    private var accessibilityLabel: String {
        let dateText = day.date.formatted(.dateTime.month(.wide).day())
        guard day.hasData else {
            return "\(dateText), no activity ring data"
        }

        let completionText = day.summary.isCompleted ? ", completed" : ""
        return "\(dateText)\(completionText), Move \(metricText(day.summary.move)), Exercise \(metricText(day.summary.exercise)), Stand \(metricText(day.summary.stand))"
    }

    private func metricText(_ metric: ActivityRingMetric) -> String {
        guard let value = metric.value, let goal = metric.goal else {
            return "no data"
        }

        return "\(Int(value.rounded())) of \(Int(goal.rounded()))"
    }
}

private struct BodyScaledActivityRingGraphic: View {
    let summary: ActivityRingSummary
    let size: CGFloat

    var body: some View {
        BodyActivityRingGraphic(
            summary: summary,
            moveColor: BodyActivityRingPalette.move,
            exerciseColor: BodyActivityRingPalette.exercise,
            standColor: BodyActivityRingPalette.stand
        )
        .frame(width: 108, height: 108)
        .scaleEffect(size / 108)
        .frame(width: size, height: size)
    }
}

private struct BodyActivityRingsCard: View {
    let summary: ActivityRingSummary

    private let moveColor = BodyActivityRingPalette.move
    private let exerciseColor = BodyActivityRingPalette.exercise
    private let standColor = BodyActivityRingPalette.stand

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity Rings")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                BodyActivityRingGraphic(
                    summary: summary,
                    moveColor: moveColor,
                    exerciseColor: exerciseColor,
                    standColor: standColor
                )
                .frame(width: 108, height: 108)
                .padding(.leading, 12)
                .accessibilityHidden(true)
            }
            .frame(width: 138, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                BodyActivityRingMetricRow(
                    title: "Move",
                    metric: summary.move,
                    unit: "KCAL",
                    color: moveColor
                )
                BodyActivityRingMetricRow(
                    title: "Exercise",
                    metric: summary.exercise,
                    unit: "MIN",
                    color: exerciseColor
                )
                BodyActivityRingMetricRow(
                    title: "Stand",
                    metric: summary.stand,
                    unit: "HRS",
                    color: standColor
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .bodyCardBackground(cornerRadius: 28)
    }
}

private struct BodyActivityRingMetricRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let metric: ActivityRingMetric
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valueText)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(metricTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(unit)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(metricTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) \(valueText) \(unit)")
        }
    }

    private var valueText: String {
        guard let value = metric.value, let goal = metric.goal else {
            return "--/--"
        }

        return "\(roundedText(value))/\(roundedText(goal))"
    }

    private func roundedText(_ value: Double) -> String {
        BodyValueFormat.numberText(value.rounded(), decimals: 0)
    }

    private var metricTextColor: Color {
        colorScheme == .light ? Color.black : color
    }
}

private struct BodyActivityRingGraphic: View {
    let summary: ActivityRingSummary
    let moveColor: Color
    let exerciseColor: Color
    let standColor: Color

    var body: some View {
        let geometry = BodyActivityRingGraphicGeometry.self
        let fenceColor = Color.black

        ZStack {
            BodyActivityRingFence(diameter: geometry.moveExerciseFenceDiameter, color: fenceColor)
            BodyActivityRingFence(diameter: geometry.exerciseStandFenceDiameter, color: fenceColor)

            BodyActivityRingArc(
                progress: summary.move.completionProgress,
                headProgress: summary.move.headProgress,
                showsFullStartMarker: summary.move.showsFullStartMarker,
                color: moveColor,
                lineWidth: geometry.ringLineWidth
            )
                .frame(width: geometry.moveDiameter, height: geometry.moveDiameter)
            BodyActivityRingArc(
                progress: summary.exercise.completionProgress,
                headProgress: summary.exercise.headProgress,
                showsFullStartMarker: summary.exercise.showsFullStartMarker,
                color: exerciseColor,
                lineWidth: geometry.ringLineWidth
            )
                .frame(width: geometry.exerciseDiameter, height: geometry.exerciseDiameter)
            BodyActivityRingArc(
                progress: summary.stand.completionProgress,
                headProgress: summary.stand.headProgress,
                showsFullStartMarker: summary.stand.showsFullStartMarker,
                color: standColor,
                lineWidth: geometry.ringLineWidth
            )
                .frame(width: geometry.standDiameter, height: geometry.standDiameter)

            BodyActivityRingFence(diameter: geometry.outerFenceDiameter, color: fenceColor)
            BodyActivityRingFence(diameter: geometry.innerFenceDiameter, color: fenceColor)
        }
    }
}

private struct BodyActivityRingFence: View {
    let diameter: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .stroke(color, lineWidth: BodyActivityRingGraphicGeometry.fenceLineWidth)
            .frame(width: diameter, height: diameter)
    }
}

private struct BodyActivityRingArc: View {
    let progress: Double
    let headProgress: Double
    let showsFullStartMarker: Bool
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = diameter / 2

            ZStack {
                Circle()
                    .stroke(
                        color.opacity(0.18),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                if clampedProgress >= 0.995 {
                    Circle()
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                } else {
                    Circle()
                        .trim(from: 0, to: clampedProgress)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                if showsFullStartMarker {
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth, height: lineWidth)
                        .offset(
                            x: headOffsetX(progress: normalizedHeadProgress, radius: radius),
                            y: headOffsetY(progress: normalizedHeadProgress, radius: radius)
                        )
                }

                BodyActivityRingHead(color: color)
                    .frame(width: lineWidth, height: lineWidth)
                    .rotationEffect(.degrees(normalizedHeadProgress * 360))
                    .offset(
                        x: headOffsetX(progress: normalizedHeadProgress, radius: radius),
                        y: headOffsetY(progress: normalizedHeadProgress, radius: radius)
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var clampedProgress: Double {
        min(normalizedProgress, 1)
    }

    private var normalizedProgress: Double {
        guard progress.isFinite else {
            return 0
        }

        return max(progress, 0)
    }

    private var normalizedHeadProgress: Double {
        guard headProgress.isFinite else {
            return 0
        }

        return min(max(headProgress, 0), 1)
    }

    private func headOffsetX(progress: Double, radius: CGFloat) -> CGFloat {
        CGFloat(sin(progress * 2 * .pi)) * radius
    }

    private func headOffsetY(progress: Double, radius: CGFloat) -> CGFloat {
        -CGFloat(cos(progress * 2 * .pi)) * radius
    }
}

private struct BodyActivityRingHead: View {
    let color: Color

    var body: some View {
        ZStack {
            BodyActivityRingHeadFill()
                .fill(color)

            BodyActivityRingHeadEdge()
                .stroke(
                    Color.black.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
        }
    }
}

private struct BodyActivityRingHeadFill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct BodyActivityRingHeadEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        return path
    }
}

private struct BodyHealthNoticeBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.blue)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(cornerRadius: 22)
    }
}

private struct BodyHealthMetricCard: View {
    struct Model: Identifiable {
        struct AccessoryMetric: Identifiable {
            let title: String
            let value: String

            var id: String {
                title
            }
        }

        let kind: HealthMetricKind
        let title: String
        let value: String
        let unit: String
        let symbolName: String
        let symbolColor: Color
        let accessoryMetrics: [AccessoryMetric]

        init(
            kind: HealthMetricKind,
            title: String,
            value: String,
            unit: String,
            symbolName: String,
            symbolColor: Color,
            accessoryMetrics: [AccessoryMetric] = []
        ) {
            self.kind = kind
            self.title = title
            self.value = value
            self.unit = unit
            self.symbolName = symbolName
            self.symbolColor = symbolColor
            self.accessoryMetrics = accessoryMetrics
        }

        var id: String {
            kind.id
        }
    }

    let metric: Model

    var body: some View {
        cardContent
            .padding(.horizontal, 18)
            .padding(.vertical, metric.accessoryMetrics.isEmpty ? 18 : 15)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .bodyCardBackground(cornerRadius: 28)
    }

    @ViewBuilder
    private var cardContent: some View {
        if metric.accessoryMetrics.isEmpty {
            regularContent
        } else {
            accessoryContent
        }
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            Spacer(minLength: 0)

            valueRow
        }
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            accessoryMetricStrip
            valueRow
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(metric.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Image(systemName: metric.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(metric.symbolColor)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(metric.symbolColor.opacity(0.16))
                )
                .accessibilityHidden(true)
        }
    }

    private var accessoryMetricStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ForEach(metric.accessoryMetrics) { accessory in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(accessory.title)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(accessory.value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(metric.value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .layoutPriority(1)

            if !metric.unit.isEmpty {
                Text(metric.unit)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
            }
        }
        .layoutPriority(1)
    }
}

struct BodyCardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground))
                    .shadow(
                        color: Color.black.opacity(colorScheme == .light ? 0.07 : 0),
                        radius: 14,
                        x: 0,
                        y: 6
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .light ? 0.04 : 0), lineWidth: 1)
            )
    }
}

extension View {
    func bodyCardBackground(cornerRadius: CGFloat = 30) -> some View {
        modifier(BodyCardBackgroundModifier(cornerRadius: cornerRadius))
    }

    func bodyTrendRangeTabBackground(isSelected: Bool, colorScheme: ColorScheme) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(colorScheme == .light ? 0.12 : 0.22)
                        : (colorScheme == .light ? Color(.systemBackground) : Color(.secondarySystemBackground))
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .light ? 0.045 : 0),
                    radius: 8,
                    x: 0,
                    y: 3
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(colorScheme == .light ? 0.05 : 0),
                    lineWidth: 1
                )
        )
    }
}
