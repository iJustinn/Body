//
//  BodyHomeView.swift
//  Body
//

import Charts
import SwiftUI
import UniformTypeIdentifiers

private let bodyChartSelectionOverflowResolution = AnnotationOverflowResolution(
    x: .fit(to: .chart),
    y: .disabled
)

private let bodyHealthDetailChartLeadingDatePadding: TimeInterval = 2 * 60 * 60
private let bodyHealthDetailChartTrailingDatePadding: TimeInterval = 36 * 60 * 60

private func bodyHealthDetailChartXDomain(for dates: [Date]) -> ClosedRange<Date> {
    guard let startDate = dates.min(), let endDate = dates.max() else {
        let now = Date()
        return now.addingTimeInterval(-bodyHealthDetailChartLeadingDatePadding)...now.addingTimeInterval(bodyHealthDetailChartTrailingDatePadding)
    }

    return startDate.addingTimeInterval(-bodyHealthDetailChartLeadingDatePadding)...endDate.addingTimeInterval(bodyHealthDetailChartTrailingDatePadding)
}

private func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String? {
    guard point.representsDateRange else {
        return nil
    }

    let calendar = Calendar.bodyGregorian
    let startDate = point.startDate
    let endDate = point.endDate
    guard !calendar.isDate(startDate, inSameDayAs: endDate) else {
        return nil
    }

    let startMonth = startDate.formatted(.dateTime.month(.abbreviated))
    let startDay = startDate.formatted(.dateTime.day())
    let startYear = startDate.formatted(.dateTime.year())
    let endMonth = endDate.formatted(.dateTime.month(.abbreviated))
    let endDay = endDate.formatted(.dateTime.day())
    let endYear = endDate.formatted(.dateTime.year())
    let sameYear = calendar.component(.year, from: startDate) == calendar.component(.year, from: endDate)
    let sameMonth = sameYear && calendar.component(.month, from: startDate) == calendar.component(.month, from: endDate)

    if sameMonth {
        return "\(startMonth) \(startDay)-\(endDay), \(endYear)"
    }

    if sameYear {
        return "\(startMonth) \(startDay)-\(endMonth) \(endDay), \(endYear)"
    }

    return "\(startMonth) \(startDay), \(startYear)-\(endMonth) \(endDay), \(endYear)"
}

private extension Array where Element == HealthTrendCalendarPoint {
    func nearestFinitePoint(to date: Date?) -> HealthTrendCalendarPoint? {
        guard let date else {
            return nil
        }

        return filter { point in
            point.value?.isFinite == true
        }
        .min { first, second in
            abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
        }
    }

    func finitePoint(on date: Date) -> HealthTrendCalendarPoint? {
        first { point in
            point.date == date && point.value?.isFinite == true
        }
    }
}

struct BodyHomeView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.homeCardOrderKey) private var homeCardOrderRawValue = BodyHomeCardKind.defaultRawValue
    @State private var draggedHomeCard: BodyHomeCardKind?
    @State private var showsAllHomeTrends = false

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

                        homeTrendsSection
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

    @ViewBuilder
    private var homeTrendsSection: some View {
        let visibleTrendCards = visibleHomeTrendCards

        if !visibleTrendCards.isEmpty {
            BodyHomeSectionDivider()
                .padding(.top, 8)

            BodyHomeTrendsSection(
                cards: visibleTrendCards,
                canToggleAll: canToggleAllHomeTrends,
                showsAllTrends: showsAllHomeTrends,
                toggleAll: toggleAllHomeTrends
            )
            .padding(.top, 8)
        }
    }

    private var metricCards: [BodyHealthMetricCard.Model] {
        let summary = workoutStore.healthSummary
        let trends = workoutStore.healthTrends

        return [
            metric(
                kind: .exerciseMinutes,
                title: "Exercise Minutes",
                summary: summary.exerciseMinutes,
                unit: "",
                decimals: 0,
                symbolName: "figure.run",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar,
                chartPreview: trends.series(for: .exerciseMinutes)
            ),
            wristTemperatureMetric(
                summary: summary,
                chartPreview: trends.series(for: .wristTemperature)
            ),
            metric(
                kind: .timeInDaylight,
                title: "Time In Daylight",
                summary: summary.timeInDaylight,
                unit: "min",
                decimals: 0,
                symbolName: "plus",
                symbolColor: Color(red: 0.10, green: 0.58, blue: 1.00),
                chartStyle: .bar,
                chartPreview: trends.series(for: .timeInDaylight)
            ),
            metric(
                kind: .steps,
                title: "Steps",
                summary: summary.steps,
                unit: "",
                decimals: 0,
                symbolName: "figure.walk",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar,
                chartPreview: trends.series(for: .steps)
            ),
            sleepMetric(summary: summary, chartPreview: trends.series(for: .sleep)),
            basicsMetric(summary: summary, chartPreview: trends.series(for: .bodyMass)),
            metric(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                chartPreview: trends.series(for: .restingHeartRate)
            ),
            metric(
                kind: .heartRateVariability,
                title: "HRV",
                summary: summary.heartRateVariability,
                unit: "ms",
                decimals: 1,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                chartPreview: trends.series(for: .heartRateVariability)
            ),
            metric(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                unit: "%",
                decimals: 0,
                symbolName: "drop.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                chartPreview: trends.series(for: .oxygenSaturation)
            ),
            metric(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                summary: summary.respiratoryRate,
                unit: "br/min",
                decimals: 0,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                chartPreview: trends.series(for: .respiratoryRate)
            ),
            metric(
                kind: .activeEnergy,
                title: "Active Energy",
                summary: summary.activeEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar,
                chartPreview: trends.series(for: .activeEnergy)
            ),
            metric(
                kind: .restingEnergy,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                unit: "kcal",
                decimals: 0,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                chartStyle: .bar,
                chartPreview: trends.series(for: .restingEnergy)
            )
        ]
    }

    private var visibleHomeTrendCards: [BodyHomeTrendCard.Model] {
        if showsAllHomeTrends {
            return allHomeTrendCards
        }

        return Array(significantHomeTrendCards.prefix(4))
    }

    private var canToggleAllHomeTrends: Bool {
        showsAllHomeTrends || allHomeTrendCards.count > visibleHomeTrendCards.count
    }

    private var significantHomeTrendCards: [BodyHomeTrendCard.Model] {
        makeHomeTrendCards(includesStable: false)
    }

    private var allHomeTrendCards: [BodyHomeTrendCard.Model] {
        makeHomeTrendCards(includesStable: true)
    }

    private func makeHomeTrendCards(includesStable: Bool) -> [BodyHomeTrendCard.Model] {
        let trends = workoutStore.healthTrends
        let temperatureUnit = BodyValueFormat.temperatureDisplay(
            celsius: 0,
            unitPreference: selectedUnitPreference
        ).unit
        let cards = [
            homeTrendCard(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                series: trends.series(for: .restingHeartRate),
                chartStyle: .line,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " BPM" },
                messageStyle: .average(subject: "your resting heart rate"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .heartRateVariability,
                title: "HRV",
                series: trends.series(for: .heartRateVariability),
                chartStyle: .line,
                symbolName: "waveform.path.ecg",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " ms" },
                messageStyle: .average(subject: "your HRV"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                series: trends.series(for: .respiratoryRate),
                chartStyle: .line,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " br/min" },
                messageStyle: .average(subject: "your respiratory rate"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                series: trends.series(for: .oxygenSaturation),
                chartStyle: .line,
                symbolName: "drop.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                messageStyle: .average(subject: "your blood oxygen"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .sleep,
                title: "Sleep",
                series: trends.series(for: .sleep),
                chartStyle: .line,
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
                valueFormatter: { BodyValueFormat.sleepDurationText(for: $0 * 60 * 60) },
                messageStyle: .average(subject: "your sleep duration"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .wristTemperature,
                title: "Wrist Temperature",
                series: trends.series(for: .wristTemperature).mapValues {
                    BodyValueFormat.temperatureValue(
                        celsius: $0,
                        unitPreference: selectedUnitPreference
                    ).value
                },
                chartStyle: .line,
                symbolName: "thermometer.medium",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + temperatureUnit },
                messageStyle: .average(subject: "your wrist temperature"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .steps,
                title: "Steps",
                series: trends.series(for: .steps),
                chartStyle: .bar,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " steps" },
                messageStyle: .quantity(subject: "The number of steps you took per day"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .activeEnergy,
                title: "Active Energy",
                series: trends.series(for: .activeEnergy),
                chartStyle: .bar,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " kcal" },
                messageStyle: .quantity(subject: "Your active energy"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .restingEnergy,
                title: "Resting Energy",
                series: trends.series(for: .restingEnergy),
                chartStyle: .bar,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " kcal" },
                messageStyle: .quantity(subject: "Your resting energy"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .exerciseMinutes,
                title: "Exercise Minutes",
                series: trends.series(for: .exerciseMinutes),
                chartStyle: .bar,
                symbolName: "figure.run",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " min" },
                messageStyle: .quantity(subject: "Your exercise minutes"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .timeInDaylight,
                title: "Time In Daylight",
                series: trends.series(for: .timeInDaylight),
                chartStyle: .bar,
                symbolName: "plus",
                symbolColor: Color(red: 0.10, green: 0.58, blue: 1.00),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " min" },
                messageStyle: .quantity(subject: "Your time in daylight"),
                includesStable: includesStable
            )
        ]
        .compactMap { $0 }

        return cards
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
        symbolColor: Color,
        chartStyle: BodyHealthMetricChartStyle = .line,
        chartPreview: HealthTrendSeries? = nil
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor,
            chartPreviewStyle: BodyHomeMetricCardPreview.Style.matching(chartStyle: chartStyle),
            chartPreview: chartPreview
        )
    }

    private func wristTemperatureMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let display = summary.wristTemperature.value.map {
            BodyValueFormat.temperatureDisplay(celsius: $0, unitPreference: selectedUnitPreference)
        }

        return BodyHealthMetricCard.Model(
            kind: .wristTemperature,
            title: "Wrist Temp",
            value: display?.value ?? "--",
            unit: display?.unit ?? BodyValueFormat.temperatureDisplay(
                celsius: 0,
                unitPreference: selectedUnitPreference
            ).unit,
            symbolName: "thermometer.medium",
            symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
            chartPreviewStyle: .line,
            chartPreview: chartPreview
        )
    }

    private func sleepMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let sleepScoreDisplay = summary.sleep.score.map {
            BodyMetricDisplayValue(title: "Score", value: "\($0.total)", unit: "PTS")
        } ?? BodyMetricDisplayValue(title: "Score", value: "--", unit: "")

        return BodyHealthMetricCard.Model(
            kind: .sleep,
            title: "Sleep",
            value: formattedSleepDuration(summary.sleep.duration),
            unit: "",
            symbolName: "bed.double.fill",
            symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
            prominentMetrics: [
                sleepScoreDisplay,
                BodyMetricDisplayValue(
                    title: "Duration",
                    value: formattedSleepDuration(summary.sleep.duration),
                    unit: ""
                )
            ],
            chartPreview: chartPreview
        )
    }

    private func basicsMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let weightDisplay = summary.bodyMass.value.map {
            BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference, decimals: 2)
        }
        let bodyFatDisplay = summary.bodyFatPercentage.value.map {
            BodyMetricDisplayValue(
                title: "Body Fat",
                value: BodyValueFormat.numberText($0, decimals: 1),
                unit: "%"
            )
        } ?? BodyMetricDisplayValue(title: "Body Fat", value: "--", unit: "")

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
            prominentMetrics: [
                bodyFatDisplay,
                BodyMetricDisplayValue(
                    title: "Weight",
                    value: weightDisplay?.value ?? "--",
                    unit: weightDisplay?.unit ?? BodyValueFormat.massValue(
                        kilograms: 0,
                        unitPreference: selectedUnitPreference
                    ).unit
                )
            ],
            chartPreview: chartPreview
        )
    }

    private func homeTrendCard(
        kind: HealthMetricKind,
        title: String,
        series: HealthTrendSeries,
        chartStyle: BodyHealthMetricChartStyle,
        symbolName: String,
        symbolColor: Color,
        valueFormatter: @escaping (Double) -> String,
        messageStyle: BodyHomeTrendMessageStyle,
        includesStable: Bool
    ) -> BodyHomeTrendCard.Model? {
        guard let presentation = BodyHomeTrendCardPresentation.make(
            kind: kind,
            title: title,
            series: series,
            chartStyle: chartStyle,
            valueFormatter: valueFormatter,
            messageStyle: messageStyle,
            includesStable: includesStable
        ) else {
            return nil
        }

        return BodyHomeTrendCard.Model(
            presentation: presentation,
            symbolName: symbolName,
            symbolColor: symbolColor
        )
    }

    private func toggleAllHomeTrends() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            showsAllHomeTrends.toggle()
        }
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
        case .exerciseMinutes:
            return metricDetail(
                kind: kind,
                title: "Exercise Minutes",
                summary: summary.exerciseMinutes,
                unit: "min",
                decimals: 0,
                symbolName: "figure.run",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar
            )
        case .wristTemperature:
            let display = summary.wristTemperature.value.map {
                BodyValueFormat.temperatureDisplay(celsius: $0, unitPreference: selectedUnitPreference)
            }
            let temperatureUnit = BodyValueFormat.temperatureDisplay(
                celsius: 0,
                unitPreference: selectedUnitPreference
            ).unit
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Wrist Temperature",
                value: display?.value ?? "--",
                unit: display?.unit ?? temperatureUnit,
                symbolName: "thermometer.medium",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                series: trends.wristTemperature.mapValues {
                    BodyValueFormat.temperatureValue(
                        celsius: $0,
                        unitPreference: selectedUnitPreference
                    ).value
                },
                daySeries: .empty,
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + temperatureUnit },
                secondaryValueFormatter: nil,
                dataSourceText: kind.detailDataSourceText
            )
        case .timeInDaylight:
            return metricDetail(
                kind: kind,
                title: "Time In Daylight",
                summary: summary.timeInDaylight,
                unit: "min",
                decimals: 0,
                symbolName: "plus",
                symbolColor: Color(red: 0.10, green: 0.58, blue: 1.00),
                chartStyle: .bar
            )
        case .steps:
            return metricDetail(
                kind: kind,
                title: "Steps",
                summary: summary.steps,
                unit: "steps",
                decimals: 0,
                symbolName: "figure.walk",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar
            )
        case .sleep:
            return BodyHealthMetricDetailModel(
                kind: kind,
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
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "h" },
                secondaryValueFormatter: nil,
                dataSourceText: kind.detailDataSourceText
            )
        case .basics:
            let display = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(kilograms: $0, unitPreference: selectedUnitPreference, decimals: 2)
            }
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                unitPreference: selectedUnitPreference
            ).unit
            let bodyFatDisplay = summary.bodyFatPercentage.value.map {
                BodyMetricDisplayValue(
                    title: "Body Fat",
                    value: BodyValueFormat.numberText($0, decimals: 1),
                    unit: "%"
                )
            } ?? BodyMetricDisplayValue(title: "Body Fat", value: "--", unit: "")
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Basics",
                value: display?.value ?? "--",
                unit: display?.unit ?? massUnit,
                symbolName: "person.crop.circle.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                series: .empty,
                daySeries: .empty,
                basicsTrend: BasicsTrendSummary(
                    weight: trends.bodyMass.mapValues {
                        BodyValueFormat.massValue(kilograms: $0, unitPreference: selectedUnitPreference).value
                    },
                    bodyFat: trends.bodyFatPercentage,
                    bodyMassIndex: trends.bodyMassIndex
                ),
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + " " + massUnit },
                secondaryValueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "%" },
                headerMetrics: [
                    bodyFatDisplay,
                    BodyMetricDisplayValue(
                        title: "Weight",
                        value: display?.value ?? "--",
                        unit: display?.unit ?? massUnit
                    )
                ],
                dataSourceText: kind.detailDataSourceText
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
                kind: kind,
                title: "Weight",
                value: display?.value ?? "--",
                unit: display?.unit ?? massUnit,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                series: trends.bodyMass.mapValues {
                    BodyValueFormat.massValue(kilograms: $0, unitPreference: selectedUnitPreference).value
                },
                daySeries: .empty,
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
            kind: kind,
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor,
            series: workoutStore.healthTrends.series(for: kind),
            daySeries: workoutStore.healthTrends.daySeries(for: kind),
            basicsTrend: nil,
            sleepStageSnapshot: nil,
            sleepScore: nil,
            sleepVitals: nil,
            sleepDuration: nil,
            chartStyle: chartStyle,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: decimals) + suffix },
            secondaryValueFormatter: nil,
            helpText: kind.detailHelpText,
            dataSourceText: kind.detailDataSourceText
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

enum BodyHomeMetricCardPreview {
    static let previewDayCount = 4
    static let linePreviewWidth: CGFloat = 42
    static let barPreviewWidth: CGFloat = 42
    static let linePointDiameter: CGFloat = 6
    static let lineCurrentPointDiameter: CGFloat = 7

    enum Style: Equatable {
        case line
        case bar

        static func matching(chartStyle: BodyHealthMetricChartStyle) -> Style {
            switch chartStyle {
            case .line:
                return .line
            case .bar:
                return .bar
            }
        }
    }

    static func points(
        from series: HealthTrendSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendDataPoint] {
        let bounds = previewDateBounds(for: series, calendar: calendar, date: date)

        return series.points
            .filter { point in
                point.date >= bounds.startDate && point.date < bounds.endDate
            }
            .sorted { $0.date < $1.date }
    }

    static func calendarPoints(
        from series: HealthTrendSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendCalendarPoint] {
        let bounds = previewDateBounds(for: series, calendar: calendar, date: date)
        let pointsByDay = Dictionary(grouping: points(from: series, calendar: calendar, date: date)) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<previewDayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: bounds.startDate) else {
                return nil
            }

            let value = pointsByDay[day]?.last?.value
            return HealthTrendCalendarPoint(
                date: day,
                value: value?.isFinite == true ? value : nil
            )
        }
    }

    private static func previewDateBounds(
        for series: HealthTrendSeries,
        calendar: Calendar,
        date: Date
    ) -> (startDate: Date, endDate: Date) {
        let currentDayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let hasCurrentDayValue = series.points.contains { point in
            point.date >= currentDayStart && point.date < nextDayStart && point.value.isFinite
        }
        let endDate = hasCurrentDayValue ? nextDayStart : currentDayStart
        let startDate = calendar.date(byAdding: .day, value: -previewDayCount, to: endDate)
            ?? currentDayStart

        return (startDate, endDate)
    }
}

enum BodyHomeTrendMessageStyle {
    case average(subject: String)
    case quantity(subject: String)

    func text(direction: BodyHomeTrendDirection, recentDayCount: Int) -> String {
        switch self {
        case .average(let subject):
            return "On average, \(subject) \(direction.averagePhrase) over the last \(recentDayCount) days."
        case .quantity(let subject):
            return "\(subject) \(direction.quantityPhrase) over the last \(recentDayCount) days."
        }
    }
}

enum BodyHomeTrendDirection {
    case increased
    case decreased
    case stable

    var averagePhrase: String {
        switch self {
        case .increased:
            return "increased"
        case .decreased:
            return "decreased"
        case .stable:
            return "stayed about the same"
        }
    }

    var quantityPhrase: String {
        switch self {
        case .increased:
            return "was higher"
        case .decreased:
            return "was lower"
        case .stable:
            return "stayed about the same"
        }
    }
}

struct BodyHomeTrendCardPresentation: Identifiable {
    static let comparisonDayCount = 28
    static let preferredRecentDayCount = 7
    static let minimumTrendSegmentDayCount = 3
    static let minimumRelativeChange = 0.01
    static let minimumAbsoluteChange = 0.01

    let kind: HealthMetricKind
    let title: String
    let messageText: String
    let baselineAverage: Double
    let recentAverage: Double
    let baselineAverageText: String
    let recentAverageText: String
    let baselinePeriodText: String
    let recentPeriodText: String
    let chartStyle: BodyHealthMetricChartStyle
    let calendarPoints: [HealthTrendCalendarPoint]
    let baselineDayCount: Int
    let recentDayCount: Int

    var id: String {
        kind.id
    }

    var recentStartIndex: Int {
        baselineDayCount
    }

    static func make(
        kind: HealthMetricKind,
        title: String,
        series: HealthTrendSeries,
        chartStyle: BodyHealthMetricChartStyle,
        valueFormatter: (Double) -> String,
        messageStyle: BodyHomeTrendMessageStyle,
        includesStable: Bool = false,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> BodyHomeTrendCardPresentation? {
        let calendarPoints = comparisonCalendarPoints(from: series, calendar: calendar, date: date)
        guard let comparisonWindow = bestComparisonWindow(in: calendarPoints, includesStable: includesStable) else {
            return nil
        }

        let direction: BodyHomeTrendDirection
        if comparisonWindow.isMeaningful == false {
            direction = .stable
        } else {
            direction = comparisonWindow.absoluteChange > 0 ? .increased : .decreased
        }
        return BodyHomeTrendCardPresentation(
            kind: kind,
            title: title,
            messageText: messageStyle.text(direction: direction, recentDayCount: comparisonWindow.recentDayCount),
            baselineAverage: comparisonWindow.baselineAverage,
            recentAverage: comparisonWindow.recentAverage,
            baselineAverageText: valueFormatter(comparisonWindow.baselineAverage),
            recentAverageText: valueFormatter(comparisonWindow.recentAverage),
            baselinePeriodText: "\(comparisonWindow.baselineDayCount)-day avg",
            recentPeriodText: "\(comparisonWindow.recentDayCount)-day avg",
            chartStyle: chartStyle,
            calendarPoints: calendarPoints,
            baselineDayCount: comparisonWindow.baselineDayCount,
            recentDayCount: comparisonWindow.recentDayCount
        )
    }

    func averageLineSegments(in width: CGFloat) -> (baseline: ClosedRange<CGFloat>, recent: ClosedRange<CGFloat>) {
        let lastPointIndex = max(calendarPoints.count - 1, 0)
        let baselineEndIndex = min(max(baselineDayCount - 1, 0), lastPointIndex)
        let recentStartIndex = min(max(baselineDayCount, 0), lastPointIndex)
        let denominator = max(CGFloat(lastPointIndex), 1)

        func xPosition(for index: Int) -> CGFloat {
            width * CGFloat(index) / denominator
        }

        return (
            baseline: xPosition(for: 0)...xPosition(for: baselineEndIndex),
            recent: xPosition(for: recentStartIndex)...xPosition(for: lastPointIndex)
        )
    }

    private static func bestComparisonWindow(
        in calendarPoints: [HealthTrendCalendarPoint],
        includesStable: Bool
    ) -> ComparisonWindow? {
        let maximumBaselineDayCount = Self.comparisonDayCount - Self.minimumTrendSegmentDayCount
        let candidates: [ComparisonWindow] = (Self.minimumTrendSegmentDayCount...maximumBaselineDayCount).compactMap { baselineDayCount -> ComparisonWindow? in
            let recentDayCount = Self.comparisonDayCount - baselineDayCount
            let baselinePoints = Array(calendarPoints.prefix(baselineDayCount))
            let recentPoints = Array(calendarPoints.suffix(recentDayCount))
            let baselineValues = finiteValues(from: baselinePoints)
            let recentValues = finiteValues(from: recentPoints)

            guard baselineValues.count >= Self.minimumTrendSegmentDayCount,
                  recentValues.count >= Self.minimumTrendSegmentDayCount else {
                return nil
            }

            let baselineAverage = average(baselineValues)
            let recentAverage = average(recentValues)
            let absoluteChange = recentAverage - baselineAverage
            let minimumMeaningfulChange = max(
                abs(baselineAverage) * Self.minimumRelativeChange,
                Self.minimumAbsoluteChange
            )

            return ComparisonWindow(
                baselineDayCount: baselineDayCount,
                recentDayCount: recentDayCount,
                baselineValueCount: baselineValues.count,
                recentValueCount: recentValues.count,
                baselineAverage: baselineAverage,
                recentAverage: recentAverage,
                absoluteChange: absoluteChange,
                minimumMeaningfulChange: minimumMeaningfulChange
            )
        }
        let eligibleCandidates = includesStable
            ? candidates
            : candidates.filter { $0.isMeaningful }

        return eligibleCandidates.max { lhs, rhs in
            isBetterComparisonWindow(rhs, than: lhs)
        }
    }

    private static func isBetterComparisonWindow(_ lhs: ComparisonWindow, than rhs: ComparisonWindow) -> Bool {
        if lhs.isMeaningful != rhs.isMeaningful {
            return lhs.isMeaningful
        }

        let scoreDelta = lhs.score - rhs.score
        if abs(scoreDelta) > 0.000001 {
            return scoreDelta > 0
        }

        let lhsRecentDistance = abs(lhs.recentDayCount - Self.preferredRecentDayCount)
        let rhsRecentDistance = abs(rhs.recentDayCount - Self.preferredRecentDayCount)
        if lhsRecentDistance != rhsRecentDistance {
            return lhsRecentDistance < rhsRecentDistance
        }

        if lhs.valueCount != rhs.valueCount {
            return lhs.valueCount > rhs.valueCount
        }

        return lhs.recentDayCount < rhs.recentDayCount
    }

    private static func comparisonCalendarPoints(
        from series: HealthTrendSeries,
        calendar: Calendar,
        date: Date
    ) -> [HealthTrendCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let totalDayCount = Self.comparisonDayCount
        let startDate = calendar.date(byAdding: .day, value: -(totalDayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: series.points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<totalDayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else {
                return nil
            }

            let value = pointsByDay[day]?
                .sorted { $0.date < $1.date }
                .last?
                .value
            return HealthTrendCalendarPoint(
                date: day,
                value: value?.isFinite == true ? value : nil
            )
        }
    }

    private static func finiteValues(from points: [HealthTrendCalendarPoint]) -> [Double] {
        points.compactMap(\.value).filter(\.isFinite)
    }

    private static func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private struct ComparisonWindow {
        let baselineDayCount: Int
        let recentDayCount: Int
        let baselineValueCount: Int
        let recentValueCount: Int
        let baselineAverage: Double
        let recentAverage: Double
        let absoluteChange: Double
        let minimumMeaningfulChange: Double

        var isMeaningful: Bool {
            abs(absoluteChange) >= minimumMeaningfulChange
        }

        var score: Double {
            abs(absoluteChange) / max(minimumMeaningfulChange, .ulpOfOne)
        }

        var valueCount: Int {
            baselineValueCount + recentValueCount
        }
    }
}

private enum BodyLineChartPreviewStyle {
    static let lineWidth: CGFloat = 4
    static let lineColor = Color.secondary.opacity(0.28)
    static let pointStrokeColor = Color.secondary.opacity(0.28)
    static let pointStrokeWidth: CGFloat = 2
}

private struct BodyLineChartPreviewPointSymbol: View {
    let tintColor: Color
    let isCurrent: Bool
    let pointDiameter: CGFloat
    let currentPointDiameter: CGFloat

    var body: some View {
        let diameter = isCurrent
            ? currentPointDiameter
            : pointDiameter

        Circle()
            .fill(isCurrent ? tintColor : Color(.secondarySystemBackground))
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .stroke(
                        tintColor,
                        lineWidth: BodyLineChartPreviewStyle.pointStrokeWidth
                    )
            )
    }
}

enum BodyHealthMetricChartStyle {
    case line
    case bar
}

private enum BodyHealthDetailChartLayout {
    static let standardHeight: CGFloat = 220
    static let sleepVitalsHeight: CGFloat = 248
    static let sleepVitalsPlotHeight: CGFloat = 188
    static let sleepVitalsIconAxisHeight: CGFloat = 28
    static let yAxisLabelCount = 4
}

private enum BodySleepScoreDetailsSheetLayout {
    static let sheetHeight: CGFloat = 640
}

private struct BodyMetricDisplayValue: Identifiable {
    let title: String
    let value: String
    let unit: String

    var id: String {
        title
    }
}

private struct BodyHealthMetricDetailModel {
    let kind: HealthMetricKind
    let title: String
    let value: String
    let unit: String
    let symbolName: String
    let symbolColor: Color
    let series: HealthTrendSeries
    let daySeries: HealthTrendSeries
    let basicsTrend: BasicsTrendSummary?
    let sleepStageSnapshot: SleepStageSnapshot?
    let sleepScore: SleepScoreSummary?
    let sleepVitals: SleepVitalsSummary?
    let sleepDuration: TimeInterval?
    let sleepHistory: SleepHistorySnapshot
    let chartStyle: BodyHealthMetricChartStyle
    let valueFormatter: (Double) -> String
    let secondaryValueFormatter: ((Double) -> String)?
    let headerMetrics: [BodyMetricDisplayValue]
    let headerSecondaryText: String?
    let helpText: HealthMetricDetailHelpText?
    let dataSourceText: HealthMetricDetailDataSourceText?

    init(
        kind: HealthMetricKind,
        title: String,
        value: String,
        unit: String,
        symbolName: String,
        symbolColor: Color,
        series: HealthTrendSeries,
        daySeries: HealthTrendSeries = .empty,
        basicsTrend: BasicsTrendSummary?,
        sleepStageSnapshot: SleepStageSnapshot?,
        sleepScore: SleepScoreSummary?,
        sleepVitals: SleepVitalsSummary?,
        sleepDuration: TimeInterval?,
        sleepHistory: SleepHistorySnapshot = .empty,
        chartStyle: BodyHealthMetricChartStyle,
        valueFormatter: @escaping (Double) -> String,
        secondaryValueFormatter: ((Double) -> String)?,
        headerMetrics: [BodyMetricDisplayValue] = [],
        headerSecondaryText: String? = nil,
        helpText: HealthMetricDetailHelpText? = nil,
        dataSourceText: HealthMetricDetailDataSourceText? = nil
    ) {
        self.kind = kind
        self.title = title
        self.value = value
        self.unit = unit
        self.symbolName = symbolName
        self.symbolColor = symbolColor
        self.series = series
        self.daySeries = daySeries
        self.basicsTrend = basicsTrend
        self.sleepStageSnapshot = sleepStageSnapshot
        self.sleepScore = sleepScore
        self.sleepVitals = sleepVitals
        self.sleepDuration = sleepDuration
        self.sleepHistory = sleepHistory
        self.chartStyle = chartStyle
        self.valueFormatter = valueFormatter
        self.secondaryValueFormatter = secondaryValueFormatter
        self.headerMetrics = headerMetrics
        self.headerSecondaryText = headerSecondaryText
        self.helpText = helpText ?? kind.detailHelpText
        self.dataSourceText = dataSourceText
    }
}

private enum BodyMetricDetailDatePicker {
    case sleep
    case metric
}

private struct BodyHealthMetricDetailView: View {
    let model: BodyHealthMetricDetailModel
    @AppStorage(BodyAppearancePreference.selectedUnitPreferenceKey) private var selectedUnitPreferenceRawValue = BodyValueFormat.UnitPreference.defaultValue.rawValue
    @State private var selectedTrendRange = BodyHealthTrendRange.defaultValue
    @State private var selectedTrendDate: Date?
    @State private var selectedSleepDate: Date?
    @State private var selectedMetricDate: Date?
    @State private var selectedSleepScoreDetails: SleepScoreDetailsSelection?
    @GestureState private var isSelectingTrend = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if isSleepDetail {
                    BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                    trendCard
                    sleepDatePicker
                    selectedSleepCards
                    aboutSleepScoreCard
                    dataSourceFooter
                } else {
                    BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                    if isBasicsDetail {
                        basicsRangeCard
                    }
                    trendCard
                    if isBasicsDetail {
                        bodyMassIndexTrendCard
                    }
                    if supportsMetricDayView {
                        metricDatePicker
                        metricDayChartCard
                    }
                    helpTextCard
                    dataSourceFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSleepScoreDetails) { selection in
            SleepScoreDetailsSheet(selection: selection, accentColor: model.symbolColor)
                .presentationDetents([.height(BodySleepScoreDetailsSheetLayout.sheetHeight), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(.systemBackground))
        }
    }

    private var selectedUnitPreference: BodyValueFormat.UnitPreference {
        BodyValueFormat.UnitPreference.storedValue(from: selectedUnitPreferenceRawValue)
    }

    private var isSleepDetail: Bool {
        model.kind == .sleep
    }

    private var isBasicsDetail: Bool {
        model.kind == .basics
    }

    private var trendHeaderAlignment: VerticalAlignment {
        isBasicsDetail ? .top : .firstTextBaseline
    }

    private var supportsMetricDayView: Bool {
        switch model.kind {
        case .restingHeartRate,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation:
            return true
        case .sleep,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .wristTemperature,
             .timeInDaylight,
             .steps:
            return false
        }
    }

    private var selectedSleepDay: Date {
        let calendar = Calendar.bodyGregorian
        return calendar.startOfDay(for: selectedSleepDate ?? Date())
    }

    private var selectedMetricDay: Date {
        let calendar = Calendar.bodyGregorian
        return calendar.startOfDay(for: selectedMetricDate ?? Date())
    }

    private var recentDatePickerDates: [Date] {
        SleepHistorySnapshot.datePickerDates(dayCount: BodyHealthTrendRange.recentMonth.dayCount, futureDayCount: 1)
    }

    private var selectedMetricDaySeries: HealthTrendSeries {
        model.daySeries.points(on: selectedMetricDay)
    }

    private var selectedSleepSummary: SleepSummary? {
        if let summary = model.sleepHistory.summary(on: selectedSleepDay)?.summary {
            return summary
        }

        guard Calendar.bodyGregorian.isDate(selectedSleepDay, inSameDayAs: Date()) else {
            return nil
        }

        return currentSleepSummary
    }

    private var currentSleepSummary: SleepSummary? {
        let stageSnapshot = model.sleepStageSnapshot ?? SleepStageSnapshot(date: selectedSleepDay, segments: [])
        guard model.sleepDuration != nil || !stageSnapshot.isEmpty || model.sleepVitals?.isEmpty == false else {
            return nil
        }

        return SleepSummary(
            duration: model.sleepDuration,
            stageSnapshot: stageSnapshot,
            vitals: model.sleepVitals ?? .empty
        )
    }

    private var selectedSleepStageSnapshot: SleepStageSnapshot {
        selectedSleepSummary?.stageSnapshot ?? SleepStageSnapshot(date: selectedSleepDay, segments: [])
    }

    @ViewBuilder
    private var selectedSleepCards: some View {
        if let sleepScore = selectedSleepSummary?.score {
            sleepScoreCard(sleepScore)
        } else {
            unavailableSleepScoreCard
        }

        sleepStageCard(selectedSleepStageSnapshot)
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

    @ViewBuilder
    private var dataSourceFooter: some View {
        if let dataSourceText = model.dataSourceText {
            HStack(spacing: 7) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(model.symbolColor)

                Text(dataSourceText.sourceText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            .padding(.bottom, 4)
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

            headerValues
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 94)
        .bodyCardBackground()
    }

    @ViewBuilder
    private var headerValues: some View {
        if model.headerMetrics.isEmpty {
            VStack(alignment: .trailing, spacing: 3) {
                headerValueRow(BodyMetricDisplayValue(title: model.title, value: model.value, unit: model.unit))

                if let headerSecondaryText = model.headerSecondaryText {
                    Text(headerSecondaryText)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(model.headerMetrics) { display in
                    headerValueRow(display)
                }
            }
        }
    }

    private func headerValueRow(_ display: BodyMetricDisplayValue) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(display.value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if !display.unit.isEmpty {
                Text(display.unit)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: trendHeaderAlignment) {
                Text(selectedTrendRange.chartTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if model.kind == .basics {
                    BodyBasicsTrendLegend(
                        weightColor: model.symbolColor,
                        bodyFatColor: basicsBodyFatColor,
                        weightAverageText: basicsWeightAverageText,
                        bodyFatAverageText: basicsBodyFatAverageText
                    )
                } else if let averageTrendText {
                    averageHeaderText(averageTrendText)
                }
            }

            if let visibleBasicsTrend {
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
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            } else {
                GeometryReader { proxy in
                    let chartBarWidth = selectedTrendRange.chartBarWidth(forAvailableWidth: proxy.size.width)

                    Chart {
                        if model.chartStyle == .bar, let selectedTrendPoint {
                            RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                                .foregroundStyle(Color.secondary.opacity(0.48))
                                .lineStyle(StrokeStyle(lineWidth: 1.4))
                        }

                        ForEach(visibleCalendarPoints) { point in
                            if let value = point.value {
                                switch model.chartStyle {
                                case .line:
                                    LineMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value(model.title, value)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(lineChartStrokeColor)
                                    .lineStyle(StrokeStyle(lineWidth: lineChartStrokeWidth, lineCap: .round, lineJoin: .round))

                                    if selectedTrendRange.showsPointMarks {
                                        if selectedTrendRange.usesPreviewLineChartStyle {
                                            PointMark(
                                                x: .value("Date", point.date, unit: .day),
                                                y: .value(model.title, value)
                                            )
                                            .symbol {
                                                BodyLineChartPreviewPointSymbol(
                                                    tintColor: model.symbolColor,
                                                    isCurrent: isLatestVisiblePoint(point),
                                                    pointDiameter: selectedTrendRange.linePointDiameter,
                                                    currentPointDiameter: selectedTrendRange.lineCurrentPointDiameter
                                                )
                                            }
                                        } else {
                                            PointMark(
                                                x: .value("Date", point.date, unit: .day),
                                                y: .value(model.title, value)
                                            )
                                            .foregroundStyle(model.symbolColor)
                                            .symbolSize(28)
                                        }
                                    }
                                case .bar:
                                    BarMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value(model.title, value),
                                        width: .fixed(chartBarWidth)
                                    )
                                    .foregroundStyle(model.symbolColor.gradient)
                                    .cornerRadius(4)
                                }
                            } else if model.chartStyle == .bar {
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value(model.title, placeholderBarYValue),
                                    width: .fixed(chartBarWidth)
                                )
                                .foregroundStyle(Color.secondary.opacity(0.14))
                                .cornerRadius(4)
                            }
                        }

                        if let selectedTrendPoint, let selectedTrendValue = selectedTrendPoint.value {
                            RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                                .foregroundStyle(model.chartStyle == .bar ? Color.clear : Color.secondary.opacity(0.48))
                                .lineStyle(StrokeStyle(lineWidth: 1.4))
                                .annotation(
                                    position: .top,
                                    spacing: 8,
                                    overflowResolution: bodyChartSelectionOverflowResolution
                                ) {
                                    BodyChartSelectionAnnotation(
                                        eyebrow: model.chartStyle == .bar ? barSelectionEyebrow : nil,
                                        values: [
                                            BodyChartSelectionValue(
                                                title: nil,
                                                value: chartSelectionText(for: selectedTrendValue),
                                                color: model.symbolColor
                                            )
                                        ],
                                        date: selectedTrendPoint.date,
                                        dateText: bodyChartSelectionDateText(for: selectedTrendPoint)
                                    )
                                }

                            if model.chartStyle == .line {
                                PointMark(
                                    x: .value("Selected Date", selectedTrendPoint.date, unit: .day),
                                    y: .value(model.title, selectedTrendValue)
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
                        AxisMarks(position: .leading, values: .automatic(desiredCount: BodyHealthDetailChartLayout.yAxisLabelCount)) { value in
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
                    .id(trendChartIdentity)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private var basicsRangeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Difference Range")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(alignment: .top, spacing: 12) {
                ForEach(basicsRangeMetrics) { metric in
                    VStack(alignment: .center, spacing: 5) {
                        Text(metric.title)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(metric.value)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .layoutPriority(1)

                            if !metric.unit.isEmpty {
                                Text(metric.unit)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private var bodyMassIndexTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("BMI")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if let bodyMassIndexAverageText {
                    averageHeaderText(bodyMassIndexAverageText)
                }
            }

            BodyBasicsBodyMassIndexTrendChart(
                series: visibleBodyMassIndexTrend,
                selectedRange: selectedTrendRange,
                color: basicsBodyMassIndexColor,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) }
            )
            .frame(height: BodyHealthDetailChartLayout.standardHeight)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private var sleepDatePicker: some View {
        datePicker(.sleep)
    }

    private var metricDatePicker: some View {
        datePicker(.metric)
    }

    private func datePicker(_ picker: BodyMetricDetailDatePicker) -> some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentDatePickerDates, id: \.self) { date in
                            dateTile(for: date, picker: picker)
                                .id(date)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                }

                sleepDateSliderEdgeShade
                    .allowsHitTesting(false)
            }
            .background(sleepDateSliderBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task(id: recentDatePickerDates.last) {
                let calendar = Calendar.bodyGregorian
                let today = calendar.startOfDay(for: Date())
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

                setInitialDateIfNeeded(today, for: picker)

                await Task.yield()
                proxy.scrollTo(tomorrow, anchor: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDayChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Day View")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            if selectedMetricDaySeries.isEmpty {
                Text("No data for this day")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodyHealthMetricDayChart(
                    series: selectedMetricDaySeries,
                    day: selectedMetricDay,
                    title: model.title,
                    color: model.symbolColor,
                    valueFormatter: model.valueFormatter
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func dateTile(for date: Date, picker: BodyMetricDetailDatePicker) -> some View {
        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let isSelected = calendar.isDate(dayStart, inSameDayAs: selectedDay(for: picker))
        let isFuture = dayStart > today

        return Button {
            guard !isFuture else {
                return
            }

            selectDate(dayStart, for: picker)
        } label: {
            VStack(spacing: 6) {
                Text(dayStart.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(dayStart.formatted(.dateTime.day()))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(isFuture ? Color.white.opacity(0.34) : .white)
            .frame(width: 58, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFuture ? sleepDateTileBackground.opacity(0.62) : sleepDateTileBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? dateSliderSelectionColor : Color.white.opacity(isFuture ? 0.08 : 0.16),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityHint(isFuture ? "Future date is not selectable" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectedDay(for picker: BodyMetricDetailDatePicker) -> Date {
        switch picker {
        case .sleep:
            return selectedSleepDay
        case .metric:
            return selectedMetricDay
        }
    }

    private func selectDate(_ date: Date, for picker: BodyMetricDetailDatePicker) {
        switch picker {
        case .sleep:
            selectedSleepDate = date
        case .metric:
            selectedMetricDate = date
        }
    }

    private func setInitialDateIfNeeded(_ date: Date, for picker: BodyMetricDetailDatePicker) {
        switch picker {
        case .sleep:
            if selectedSleepDate == nil {
                selectedSleepDate = date
            }
        case .metric:
            if selectedMetricDate == nil {
                selectedMetricDate = date
            }
        }
    }

    private var sleepDateSliderEdgeShade: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [sleepDateSliderBackground, sleepDateSliderBackground.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [sleepDateSliderBackground.opacity(0), sleepDateSliderBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
        }
    }

    private var dateSliderSelectionColor: Color {
        Color.accentColor
    }

    private var sleepDateSliderBackground: Color {
        Color(red: 0.02, green: 0.02, blue: 0.025)
    }

    private var sleepDateTileBackground: Color {
        Color(red: 0.07, green: 0.07, blue: 0.08)
    }

    private func sleepScoreCard(_ score: SleepScoreSummary) -> some View {
        Button {
            selectedSleepScoreDetails = SleepScoreDetailsSelection(date: selectedSleepDay, score: score)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sleep Score")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(score.comment)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 7) {
                        Text("\(score.total)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.64)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(model.symbolColor)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bodyCardBackground()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows detailed sleep score scoring")
    }

    private var unavailableSleepScoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Score")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                Text("--/100")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text("No sleep score for this day")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepStageCard(_ snapshot: SleepStageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Stages")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            if snapshot.isEmpty {
                Text("No sleep stages for this day")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodySleepStageChart(snapshot: snapshot)
                    .id(sleepStageChartIdentity(for: snapshot))
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .frame(height: BodyHealthDetailChartLayout.standardHeight)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepStageChartIdentity(for snapshot: SleepStageSnapshot) -> String {
        let dateIdentity = snapshot.date.map { String($0.timeIntervalSinceReferenceDate) } ?? "no-date"
        let segmentIdentity = snapshot.segments.map(\.id).joined(separator: "|")
        return "\(dateIdentity)-\(segmentIdentity)"
    }

    private var aboutSleepScoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About Sleep Score")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Body scores each night from the data available for that sleep window: amount, continuity, deep and REM share, pressure from sleep HRV, sleep vitals, and wrist temperature. Missing sensors are skipped instead of counted as zero.")
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                    .frame(height: BodyHealthDetailChartLayout.sleepVitalsHeight)
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

        if let heartRateVariability = vitals.heartRateVariability {
            rows.append(SleepVitalDisplayRow(
                title: "Pressure",
                value: BodyValueFormat.numberText(heartRateVariability.rounded(), decimals: 0),
                unit: "ms HRV",
                symbolName: "waveform.path.ecg",
                tintColor: Color(red: 0.58, green: 0.42, blue: 0.95),
                numericValue: heartRateVariability,
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

    private var visibleChartSeries: HealthTrendSeries {
        switch model.chartStyle {
        case .line:
            return model.series.lineChartSeries(to: selectedTrendRange)
        case .bar:
            return model.series.chartSeries(to: selectedTrendRange)
        }
    }

    private var visibleCalendarPoints: [HealthTrendCalendarPoint] {
        switch model.chartStyle {
        case .line:
            return model.series.lineChartCalendarPoints(to: selectedTrendRange)
        case .bar:
            return model.series.chartCalendarPoints(to: selectedTrendRange)
        }
    }

    private var chartDomainCalendarPoints: [HealthTrendCalendarPoint] {
        model.series.calendarPoints(to: selectedTrendRange)
    }

    private var trendChartIdentity: String {
        "\(model.kind.rawValue)-\(selectedTrendRange.rawValue)"
    }

    private var latestVisibleCalendarDate: Date? {
        visibleCalendarPoints.last(where: { $0.value?.isFinite == true })?.date
    }

    private func isLatestVisiblePoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == latestVisibleCalendarDate
    }

    private var selectedTrendPoint: HealthTrendCalendarPoint? {
        guard isSelectingTrend else {
            return nil
        }

        return visibleCalendarPoints.nearestFinitePoint(to: selectedTrendDate)
    }

    private var visibleBasicsTrend: BasicsTrendSummary? {
        model.basicsTrend?.limited(to: selectedTrendRange)
    }

    private var visibleBodyMassIndexTrend: HealthTrendSeries {
        visibleBasicsTrend?.bodyMassIndex ?? .empty
    }

    private var basicsRangeMetrics: [BodyMetricDisplayValue] {
        [
            BodyMetricDisplayValue(
                title: "Body Fat",
                value: halfSpreadText(visibleBasicsTrend?.bodyFatHalfSpread),
                unit: visibleBasicsTrend?.bodyFatHalfSpread == nil ? "" : "%"
            ),
            BodyMetricDisplayValue(
                title: "Weight",
                value: halfSpreadText(visibleBasicsTrend?.weightHalfSpread),
                unit: visibleBasicsTrend?.weightHalfSpread == nil ? "" : model.unit
            ),
            BodyMetricDisplayValue(
                title: "BMI",
                value: halfSpreadText(visibleBasicsTrend?.bodyMassIndexHalfSpread),
                unit: ""
            )
        ]
    }

    private func halfSpreadText(_ halfSpread: Double?) -> String {
        guard let halfSpread else {
            return "--"
        }

        return "±" + BodyValueFormat.numberText(halfSpread, decimals: 1)
    }

    private var basicsBodyFatColor: Color {
        Color(red: 1.00, green: 0.68, blue: 0.08)
    }

    private var basicsBodyMassIndexColor: Color {
        Color(red: 0.00, green: 0.62, blue: 0.70)
    }

    private var averageTrendText: String? {
        guard let averageValue = visibleSeries.averageValue else {
            return nil
        }

        if model.kind == .sleep {
            return BodyValueFormat.sleepDurationText(for: averageValue * 60 * 60)
        }

        return model.valueFormatter(averageValue)
    }

    private var bodyMassIndexAverageText: String? {
        visibleBodyMassIndexTrend.averageValue.map {
            BodyValueFormat.numberText($0, decimals: 1)
        }
    }

    private var basicsWeightAverageText: String? {
        visibleBasicsTrend?.weightAverage.map(model.valueFormatter)
    }

    private var basicsBodyFatAverageText: String? {
        visibleBasicsTrend?.bodyFatAverage.map {
            (model.secondaryValueFormatter ?? { BodyValueFormat.numberText($0, decimals: 1) + "%" })($0)
        }
    }

    private func averageHeaderText(_ text: String) -> some View {
        Text("Avg \(text)")
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
        let dates = chartDomainCalendarPoints.map(\.date)
        return bodyHealthDetailChartXDomain(for: dates)
    }

    private var placeholderBarYValue: Double {
        let span = chartYDomain.upperBound - chartYDomain.lowerBound
        return chartYDomain.lowerBound + max(span * 0.025, 0.025)
    }

    private var lineChartStrokeColor: Color {
        selectedTrendRange.usesMetricColorLineStroke ? model.symbolColor : BodyLineChartPreviewStyle.lineColor
    }

    private var lineChartStrokeWidth: CGFloat {
        selectedTrendRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedTrendRange.trendLineWidth
    }

    private var barSelectionEyebrow: String {
        selectedTrendRange.chartAggregationDayCount > 1 ? "AVG" : "TOTAL"
    }

    private var chartYDomain: ClosedRange<Double> {
        let chartValues = visibleChartSeries.points.map(\.value).filter(\.isFinite)
        let values = chartValues.isEmpty
            ? visibleSeries.points.map(\.value).filter(\.isFinite)
            : chartValues
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

private struct SleepScoreDetailsSelection: Identifiable {
    let date: Date
    let score: SleepScoreSummary

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)-\(score.total)"
    }
}

private struct SleepScoreDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selection: SleepScoreDetailsSelection
    let accentColor: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detailed Scoring")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(selection.score.categories) { category in
                                BodySleepScoreCategoryRow(
                                    category: category,
                                    color: bodySleepScoreColor(for: category.kind, accentColor: accentColor)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Sleep Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .frame(width: 58, height: 58)
                .background(accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(selection.score.total)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    Text("/100")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(selection.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(selection.score.comment)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BodySleepScoreCategoryRow: View {
    let category: SleepScoreCategory
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(category.kind.displayName)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    if let valueDescription = category.valueDescription {
                        Text(valueDescription)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }

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
                        .fill(color.gradient)
                        .frame(width: proxy.size.width * category.progress)
                }
            }
            .frame(height: 9)
        }
    }
}

private func bodySleepScoreColor(for kind: SleepScoreCategory.Kind, accentColor: Color) -> Color {
    switch kind {
    case .duration:
        return accentColor
    case .continuity:
        return Color(red: 0.14, green: 0.72, blue: 0.42)
    case .rem:
        return Color(red: 0.42, green: 0.80, blue: 1.00)
    case .deep:
        return Color(red: 0.25, green: 0.25, blue: 0.82)
    case .pressure:
        return Color(red: 0.58, green: 0.42, blue: 0.95)
    case .vitals:
        return Color(red: 1.00, green: 0.25, blue: 0.45)
    case .temperature:
        return Color(red: 1.00, green: 0.57, blue: 0.24)
    }
}

private struct BodyHomeSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.22))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

private struct BodyHomeTrendsSection: View {
    let cards: [BodyHomeTrendCard.Model]
    let canToggleAll: Bool
    let showsAllTrends: Bool
    let toggleAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                ForEach(cards) { card in
                    NavigationLink(value: card.presentation.kind) {
                        BodyHomeTrendCard(model: card)
                    }
                    .buttonStyle(.plain)
                }
            }

            if canToggleAll {
                Button(action: toggleAll) {
                    Text(showsAllTrends ? "Show Fewer Trends" : "Show All Trends")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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

private struct BodyHomeTrendCard: View {
    struct Model: Identifiable {
        let presentation: BodyHomeTrendCardPresentation
        let symbolName: String
        let symbolColor: Color

        var id: String {
            presentation.id
        }
    }

    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Text(model.presentation.messageText)
                .font(.system(size: 18, weight: .bold, design: .rounded))
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
        .bodyCardBackground(cornerRadius: 28)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.symbolColor)
                .accessibilityHidden(true)

            Text(model.presentation.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(model.symbolColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.secondary.opacity(0.55))
                .accessibilityHidden(true)
        }
    }

    private var averageLabels: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.presentation.baselineAverageText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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

private struct BodyHomeTrendComparisonChart: View {
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
        GeometryReader { proxy in
            let entries = plotEntries(in: proxy.size)
            ZStack {
                switch presentation.chartStyle {
                case .line:
                    linePlot(entries: entries)
                case .bar:
                    barPlot(entries: entries, size: proxy.size)
                }

                averageLine(
                    value: presentation.baselineAverage,
                    in: proxy.size,
                    color: Color.secondary.opacity(0.64),
                    xRange: presentation.averageLineSegments(in: proxy.size.width).baseline
                )

                averageLine(
                    value: presentation.recentAverage,
                    in: proxy.size,
                    color: color,
                    xRange: presentation.averageLineSegments(in: proxy.size.width).recent
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

    private func barPlot(entries: [PlotEntry], size: CGSize) -> some View {
        let barWidth = max((size.width - CGFloat(max(entries.count - 1, 0)) * 5) / CGFloat(max(entries.count, 1)), 3)

        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(entries) { entry in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor(for: entry))
                    .frame(width: barWidth, height: barHeight(for: entry.point.value, in: size.height))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func averageLine(value: Double, in size: CGSize, color: Color, xRange: ClosedRange<CGFloat>) -> some View {
        let y = yPosition(for: value, in: size)

        return Path { path in
            path.move(to: CGPoint(x: xRange.lowerBound, y: y))
            path.addLine(to: CGPoint(x: xRange.upperBound, y: y))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    private func plotEntries(in size: CGSize) -> [PlotEntry] {
        let points = presentation.calendarPoints
        let denominator = max(CGFloat(points.count - 1), 1)
        return points.enumerated().map { index, point in
            let x = size.width * CGFloat(index) / denominator
            let y = yPosition(for: point.value ?? chartMinimum, in: size)
            return PlotEntry(point: point, position: CGPoint(x: x, y: y), index: index)
        }
    }

    private func barColor(for entry: PlotEntry) -> Color {
        guard entry.hasValue else {
            return Color.secondary.opacity(0.10)
        }

        return entry.index >= presentation.recentStartIndex
            ? color.opacity(0.42)
            : Color.secondary.opacity(0.28)
    }

    private func barHeight(for value: Double?, in height: CGFloat) -> CGFloat {
        guard let value, value.isFinite else {
            return max(height * 0.05, 4)
        }

        let range = max(chartMaximum - chartMinimum, 1)
        let normalized = min(max((value - chartMinimum) / range, 0), 1)
        return max(height * CGFloat(normalized), 4)
    }

    private func yPosition(for value: Double, in size: CGSize) -> CGFloat {
        let range = max(chartMaximum - chartMinimum, 1)
        let normalized = min(max((value - chartMinimum) / range, 0), 1)
        return size.height - (size.height * CGFloat(normalized))
    }

    private var chartValues: [Double] {
        presentation.calendarPoints.compactMap(\.value).filter(\.isFinite)
            + [presentation.baselineAverage, presentation.recentAverage]
    }

    private var chartMinimum: Double {
        let minimum = chartValues.min() ?? 0
        guard presentation.chartStyle == .line else {
            return 0
        }

        let maximum = chartValues.max() ?? minimum
        let padding = max((maximum - minimum) * 0.16, 1)
        return max(0, minimum - padding)
    }

    private var chartMaximum: Double {
        let maximum = chartValues.max() ?? 1
        let minimum = chartValues.min() ?? maximum
        let padding = max((maximum - minimum) * 0.16, 1)
        return maximum + padding
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
    let weightAverageText: String?
    let bodyFatAverageText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            legendItem(title: "Body Fat", valueText: bodyFatAverageText, color: bodyFatColor)
            legendItem(title: "Weight", valueText: weightAverageText, color: weightColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }

    private func legendItem(title: String, valueText: String?, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if let valueText {
                Text("Avg \(valueText)")
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
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
    var dateText: String? = nil

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
                    HStack(spacing: 7) {
                        Circle()
                            .fill(value.color)
                            .frame(width: 8, height: 8)

                        if let title = value.title {
                            Text(title)
                                .foregroundColor(.secondary)
                        }

                        Text(value.value)
                            .foregroundColor(.primary)
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }

            Text(dateText ?? date.formatted(.dateTime.month(.abbreviated).day().year()))
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

private struct BodyHealthMetricDayChart: View {
    let series: HealthTrendSeries
    let day: Date
    let title: String
    let color: Color
    let valueFormatter: (Double) -> String

    private static let pointDiameter: CGFloat = 8
    private static let currentPointDiameter: CGFloat = 10

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    var body: some View {
        Chart {
            ForEach(hourlyBuckets) { bucket in
                LineMark(
                    x: .value("Time", bucket.plotDate),
                    y: .value(title, bucket.averageValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Time", bucket.plotDate),
                    y: .value(title, bucket.averageValue)
                )
                .symbol {
                    BodyLineChartPreviewPointSymbol(
                        tintColor: color,
                        isCurrent: isLatestBucket(bucket),
                        pointDiameter: Self.pointDiameter,
                        currentPointDiameter: Self.currentPointDiameter
                    )
                }
            }

            if let selectedBucket {
                RuleMark(x: .value("Selected Time", selectedBucket.plotDate))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        BodyHealthMetricDayAnnotation(
                            bucket: selectedBucket,
                            color: color,
                            valueFormatter: valueFormatter
                        )
                    }

                PointMark(
                    x: .value("Selected Time", selectedBucket.plotDate),
                    y: .value(title, selectedBucket.averageValue)
                )
                .foregroundStyle(color)
                .symbolSize(82)
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: chartYDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: BodyHealthDetailChartLayout.yAxisLabelCount)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(valueFormatter(yValue))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
    }

    private var hourlyBuckets: [HealthTrendHourlyBucket] {
        series.hourlyAverageBuckets(on: day)
    }

    private var selectedBucket: HealthTrendHourlyBucket? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return hourlyBuckets.min { first, second in
            abs(first.plotDate.timeIntervalSince(selectedDate)) < abs(second.plotDate.timeIntervalSince(selectedDate))
        }
    }

    private var latestBucketDate: Date? {
        hourlyBuckets.last?.plotDate
    }

    private func isLatestBucket(_ bucket: HealthTrendHourlyBucket) -> Bool {
        bucket.plotDate == latestBucketDate
    }

    private var chartXDomain: ClosedRange<Date> {
        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: day)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        return dayStart...nextDayStart
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = hourlyBuckets.map(\.averageValue).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.02, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.16, 1)
        return max(0, minimum - padding)...(maximum + padding)
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
}

private struct BodyHealthMetricDayAnnotation: View {
    let bucket: HealthTrendHourlyBucket
    let color: Color
    let valueFormatter: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text("HOURLY AVG")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(valueFormatter(bucket.averageValue))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(hourRangeText)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if bucket.samples.count > 1 {
                Divider()
                    .padding(.vertical, 1)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(bucket.samples.enumerated()), id: \.offset) { _, sample in
                        HStack(spacing: 10) {
                            Text(timeText(for: sample.date))
                                .foregroundColor(.secondary)

                            Text(valueFormatter(sample.value))
                                .foregroundColor(.primary)
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
    }

    private var hourRangeText: String {
        let endDate = bucket.hourStart.addingTimeInterval(59 * 60 + 59)
        return "\(timeText(for: bucket.hourStart))-\(timeText(for: endDate))"
    }

    private func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private struct BodyBasicsBodyMassIndexTrendChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    let color: Color
    let valueFormatter: (Double) -> String

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    var body: some View {
        Chart {
            ForEach(calendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("BMI", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineStrokeColor)
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("BMI", value)
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: color,
                                    isCurrent: isLatestPoint(point),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("BMI", value)
                            )
                            .foregroundStyle(color)
                            .symbolSize(28)
                        }
                    }
                }
            }

            if let selectedPoint, let selectedValue = selectedPoint.value {
                RuleMark(x: .value("Selected Date", selectedPoint.date, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        BodyChartSelectionAnnotation(
                            eyebrow: nil,
                            values: [
                                BodyChartSelectionValue(
                                    title: nil,
                                    value: valueFormatter(selectedValue),
                                    color: color
                                )
                            ],
                            date: selectedPoint.date,
                            dateText: bodyChartSelectionDateText(for: selectedPoint)
                        )
                    }

                PointMark(
                    x: .value("Selected Date", selectedPoint.date, unit: .day),
                    y: .value("BMI", selectedValue)
                )
                .foregroundStyle(color)
                .symbolSize(82)
            }
        }
        .chartXScale(domain: chartXDomain)
        .chartYScale(domain: chartYDomain)
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
            AxisMarks(position: .leading, values: .automatic(desiredCount: BodyHealthDetailChartLayout.yAxisLabelCount)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(valueFormatter(yValue))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
        .id(selectedRange.rawValue)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedPoint: HealthTrendCalendarPoint? {
        guard isSelecting else {
            return nil
        }

        return calendarPoints.nearestFinitePoint(to: selectedDate)
    }

    private var chartSeries: HealthTrendSeries {
        series.lineChartSeries(to: selectedRange)
    }

    private var calendarPoints: [HealthTrendCalendarPoint] {
        series.lineChartCalendarPoints(to: selectedRange)
    }

    private var chartDomainCalendarPoints: [HealthTrendCalendarPoint] {
        series.calendarPoints(to: selectedRange)
    }

    private var latestCalendarDate: Date? {
        calendarPoints.last(where: { $0.value?.isFinite == true })?.date
    }

    private func isLatestPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == latestCalendarDate
    }

    private var chartXDomain: ClosedRange<Date> {
        let dates = chartDomainCalendarPoints.map(\.date)
        return bodyHealthDetailChartXDomain(for: dates)
    }

    private var lineStrokeColor: Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = chartSeries.points.map(\.value).filter(\.isFinite)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        guard minimum != maximum else {
            let padding = max(abs(minimum) * 0.05, 1)
            return max(0, minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return max(0, minimum - padding)...(maximum + padding)
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
            ForEach(weightCalendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", normalized(value, in: weightDomain)),
                        series: .value("Metric", "Weight")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineStrokeColor(for: weightColor))
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Weight", normalized(value, in: weightDomain))
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: weightColor,
                                    isCurrent: isLatestWeightPoint(point),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Weight", normalized(value, in: weightDomain))
                            )
                            .foregroundStyle(weightColor)
                            .symbolSize(28)
                        }
                    }
                }
            }

            ForEach(bodyFatCalendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Body Fat", normalized(value, in: bodyFatDomain)),
                        series: .value("Metric", "Body Fat")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(lineStrokeColor(for: bodyFatColor))
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Body Fat", normalized(value, in: bodyFatDomain))
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: bodyFatColor,
                                    isCurrent: isLatestBodyFatPoint(point),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Body Fat", normalized(value, in: bodyFatDomain))
                            )
                            .foregroundStyle(bodyFatColor)
                            .symbolSize(28)
                        }
                    }
                }
            }

            if let selectedTrendDate {
                RuleMark(x: .value("Selected Date", selectedTrendDate, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        BodyChartSelectionAnnotation(
                            eyebrow: nil,
                            values: selectionValues(for: selectedTrendDate),
                            date: selectedTrendDate,
                            dateText: selectedTrendDateText
                        )
                    }

                if let selectedWeightPoint = weightCalendarPoints.finitePoint(on: selectedTrendDate),
                   let selectedWeightValue = selectedWeightPoint.value {
                    PointMark(
                        x: .value("Selected Weight Date", selectedWeightPoint.date, unit: .day),
                        y: .value("Weight", normalized(selectedWeightValue, in: weightDomain))
                    )
                    .foregroundStyle(weightColor)
                    .symbolSize(82)
                }

                if let selectedBodyFatPoint = bodyFatCalendarPoints.finitePoint(on: selectedTrendDate),
                   let selectedBodyFatValue = selectedBodyFatPoint.value {
                    PointMark(
                        x: .value("Selected Body Fat Date", selectedBodyFatPoint.date, unit: .day),
                        y: .value("Body Fat", normalized(selectedBodyFatValue, in: bodyFatDomain))
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
        .id(selectedRange.rawValue)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedTrendDate: Date? {
        selectedTrendPoint?.date
    }

    private var selectedTrendPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return (weightCalendarPoints + bodyFatCalendarPoints).nearestFinitePoint(to: selectedDate)
    }

    private var selectedTrendDateText: String? {
        selectedTrendPoint.flatMap { point in
            bodyChartSelectionDateText(for: point)
        }
    }

    private var weightChartSeries: HealthTrendSeries {
        trend.weight.lineChartSeries(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
    }

    private var bodyFatChartSeries: HealthTrendSeries {
        trend.bodyFat.lineChartSeries(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
    }

    private var weightCalendarPoints: [HealthTrendCalendarPoint] {
        trend.weight.lineChartCalendarPoints(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
    }

    private var bodyFatCalendarPoints: [HealthTrendCalendarPoint] {
        trend.bodyFat.lineChartCalendarPoints(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
    }

    private var chartDomainCalendarPoints: [HealthTrendCalendarPoint] {
        trend.weight.calendarPoints(to: selectedRange) + trend.bodyFat.calendarPoints(to: selectedRange)
    }

    private var weightLatestCalendarDate: Date? {
        weightCalendarPoints.last(where: { $0.value?.isFinite == true })?.date
    }

    private var bodyFatLatestCalendarDate: Date? {
        bodyFatCalendarPoints.last(where: { $0.value?.isFinite == true })?.date
    }

    private func isLatestWeightPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == weightLatestCalendarDate
    }

    private func isLatestBodyFatPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == bodyFatLatestCalendarDate
    }

    private var chartXDomain: ClosedRange<Date> {
        let dates = chartDomainCalendarPoints.map(\.date)
        return bodyHealthDetailChartXDomain(for: dates)
    }

    private var weightDomain: ClosedRange<Double> {
        paddedDomain(values: weightChartSeries.points.map(\.value))
    }

    private var bodyFatDomain: ClosedRange<Double> {
        paddedDomain(values: bodyFatChartSeries.points.map(\.value))
    }

    private func lineStrokeColor(for color: Color) -> Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
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

        if let selectedBodyFatPoint = bodyFatCalendarPoints.finitePoint(on: date),
           let selectedBodyFatValue = selectedBodyFatPoint.value {
            values.append(BodyChartSelectionValue(
                title: "Body Fat",
                value: bodyFatFormatter(selectedBodyFatValue),
                color: bodyFatColor
            ))
        }

        if let selectedWeightPoint = weightCalendarPoints.finitePoint(on: date),
           let selectedWeightValue = selectedWeightPoint.value {
            values.append(BodyChartSelectionValue(
                title: "Weight",
                value: weightFormatter(selectedWeightValue),
                color: weightColor
            ))
        }

        return values
    }
}

private struct BodySleepStageChart: View {
    let snapshot: SleepStageSnapshot

    @State private var selectedStageDate: Date?
    @GestureState private var isSelectingStage = false

    var body: some View {
        Chart {
            ForEach(stageBridges) { bridge in
                RectangleMark(
                    xStart: .value("Bridge Start", bridge.startDate),
                    xEnd: .value("Bridge End", bridge.endDate),
                    yStart: .value("Bridge Y Start", bridge.yStart),
                    yEnd: .value("Bridge Y End", bridge.yEnd)
                )
                .foregroundStyle(bridgeGradient(for: bridge))
            }

            ForEach(snapshot.segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segmentRenderStartDate(for: segment)),
                    xEnd: .value("End", segmentRenderEndDate(for: segment)),
                    yStart: .value("Stage Start", segment.stage.chartPosition - 0.32),
                    yEnd: .value("Stage End", segment.stage.chartPosition + 0.32)
                )
                .foregroundStyle(color(for: segment.stage))
            }

            if let selectedStageSegment {
                RuleMark(x: .value("Selected Segment", segmentMidpointDate(for: selectedStageSegment)))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        SleepStageSegmentIndicator(
                            stageName: selectedStageSegment.stage.displayName,
                            durationText: segmentDurationText(for: selectedStageSegment),
                            timeRangeText: segmentTimeRangeText(for: selectedStageSegment),
                            color: color(for: selectedStageSegment.stage)
                        )
                    }
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
        .chartXSelection(value: $selectedStageDate)
        .simultaneousGesture(stageChartPressGesture)
    }

    private struct StageBridge: Identifiable {
        let id: String
        let startDate: Date
        let endDate: Date
        let yStart: Double
        let yEnd: Double
        let upperStage: SleepStage
        let lowerStage: SleepStage
    }

    private var stageBridges: [StageBridge] {
        let segments = snapshot.segments
        guard segments.count >= 2 else { return [] }

        var bridges: [StageBridge] = []
        for index in 0..<(segments.count - 1) {
            let current = segments[index]
            let next = segments[index + 1]
            guard current.stage != next.stage else { continue }

            let gapSeconds = next.startDate.timeIntervalSince(current.endDate)
            guard gapSeconds < 15 * 60 else { continue }

            let upperStage: SleepStage
            let lowerStage: SleepStage
            if current.stage.chartPosition > next.stage.chartPosition {
                upperStage = current.stage
                lowerStage = next.stage
            } else {
                upperStage = next.stage
                lowerStage = current.stage
            }

            let connectedStart = segmentDisplayEndDate(for: current)
            let connectedEnd = segmentDisplayStartDate(for: next)
            let bridgeStart = min(connectedStart, connectedEnd)
            let bridgeEnd = max(connectedStart, connectedEnd)

            let bridgeStageOverlap = 0.14
            let segmentHalfHeight = 0.32
            let yStart = lowerStage.chartPosition + segmentHalfHeight - bridgeStageOverlap
            let yEnd = upperStage.chartPosition - segmentHalfHeight + bridgeStageOverlap

            bridges.append(StageBridge(
                id: "bridge-\(current.id)-\(next.id)",
                startDate: bridgeStart,
                endDate: bridgeEnd,
                yStart: yStart,
                yEnd: yEnd,
                upperStage: upperStage,
                lowerStage: lowerStage
            ))
        }

        return bridges
    }

    private func bridgeGradient(for bridge: StageBridge) -> LinearGradient {
        LinearGradient(
            colors: [
                color(for: bridge.upperStage).opacity(0.92),
                color(for: bridge.lowerStage).opacity(0.92)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var selectedStageSegment: SleepStageSegment? {
        guard isSelectingStage, let selectedStageDate else {
            return nil
        }

        return segmentSelection(for: selectedStageDate)
    }

    private var stageChartPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isSelectingStage) { _, isSelecting, _ in
                isSelecting = true
            }
            .onEnded { _ in
                selectedStageDate = nil
            }
    }

    private func segmentSelection(for date: Date) -> SleepStageSegment? {
        let visibleSegments = snapshot.segments.filter { segment in
            segmentRenderStartDate(for: segment) <= date && date <= segmentRenderEndDate(for: segment)
        }

        if let visibleSegment = visibleSegments.min(by: {
            segmentSelectionDistance(from: date, to: $0) < segmentSelectionDistance(from: date, to: $1)
        }) {
            return visibleSegment
        }

        let nearestSegment = snapshot.segments.min {
            segmentSelectionDistance(from: date, to: $0) < segmentSelectionDistance(from: date, to: $1)
        }

        guard let nearestSegment,
              segmentSelectionDistance(from: date, to: nearestSegment) <= 5 * 60 else {
            return nil
        }

        return nearestSegment
    }

    private func segmentSelectionDistance(from date: Date, to segment: SleepStageSegment) -> TimeInterval {
        if date < segment.startDate {
            return segment.startDate.timeIntervalSince(date)
        }

        if date > segment.endDate {
            return date.timeIntervalSince(segment.endDate)
        }

        return 0
    }

    private var segmentBridgeCoverWidth: TimeInterval {
        60
    }

    private func segmentDisplayStartDate(for segment: SleepStageSegment) -> Date {
        segment.startDate.addingTimeInterval(segmentSpacingInset(for: segment))
    }

    private func segmentDisplayEndDate(for segment: SleepStageSegment) -> Date {
        segment.endDate.addingTimeInterval(-segmentSpacingInset(for: segment))
    }

    private func segmentRenderStartDate(for segment: SleepStageSegment) -> Date {
        segmentDisplayStartDate(for: segment).addingTimeInterval(-segmentBridgeCoverWidth)
    }

    private func segmentRenderEndDate(for segment: SleepStageSegment) -> Date {
        segmentDisplayEndDate(for: segment).addingTimeInterval(segmentBridgeCoverWidth)
    }

    private func segmentSpacingInset(for segment: SleepStageSegment) -> TimeInterval {
        let duration = max(0, segment.endDate.timeIntervalSince(segment.startDate))
        guard duration > 90 else {
            return 0
        }

        return min(duration * 0.06, 35)
    }

    private func segmentMidpointDate(for segment: SleepStageSegment) -> Date {
        Date(timeIntervalSinceReferenceDate: (
            segment.startDate.timeIntervalSinceReferenceDate + segment.endDate.timeIntervalSinceReferenceDate
        ) / 2)
    }

    private func segmentDurationText(for segment: SleepStageSegment) -> String {
        BodyValueFormat.sleepDurationText(for: segment.endDate.timeIntervalSince(segment.startDate))
    }

    private func segmentTimeRangeText(for segment: SleepStageSegment) -> String {
        let startText = segmentTimeText(for: segment.startDate)
        let endText = segmentTimeText(for: segment.endDate)
        return "\(startText)-\(endText)"
    }

    private func segmentTimeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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
        let calendar = Calendar.bodyGregorian
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

private struct SleepStageSegmentIndicator: View {
    let stageName: String
    let durationText: String
    let timeRangeText: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(stageName)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(durationText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text(timeRangeText)
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
                    .frame(height: BodyHealthDetailChartLayout.sleepVitalsPlotHeight)

                BodySleepVitalsIconAxis(rows: rows)
                    .frame(height: BodyHealthDetailChartLayout.sleepVitalsIconAxisHeight)
            }

            BodySleepVitalRegionLabels()
                .frame(width: 56, height: BodyHealthDetailChartLayout.sleepVitalsPlotHeight)
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

enum BodyActivityRingCompletionStarGeometry {
    static let referenceRingSize: CGFloat = 34
    static let referenceFontSize: CGFloat = 9
    static let referenceOffset = CGSize(width: 3, height: -4)
    static let referenceShadowRadius: CGFloat = 1
    static let referenceShadowYOffset: CGFloat = 0.5

    static func scale(for ringSize: CGFloat) -> CGFloat {
        max(ringSize, 0) / referenceRingSize
    }

    static func fontSize(for ringSize: CGFloat) -> CGFloat {
        referenceFontSize * scale(for: ringSize)
    }

    static func offset(for ringSize: CGFloat) -> CGSize {
        let scale = scale(for: ringSize)
        return CGSize(
            width: referenceOffset.width * scale,
            height: referenceOffset.height * scale
        )
    }

    static func shadowRadius(for ringSize: CGFloat) -> CGFloat {
        referenceShadowRadius * scale(for: ringSize)
    }

    static func shadowYOffset(for ringSize: CGFloat) -> CGFloat {
        referenceShadowYOffset * scale(for: ringSize)
    }
}

private struct BodyActivityRingCompletionStar: View {
    let ringSize: CGFloat

    var body: some View {
        let geometry = BodyActivityRingCompletionStarGeometry.self
        let starOffset = geometry.offset(for: ringSize)

        Image(systemName: "star.fill")
            .font(.system(size: geometry.fontSize(for: ringSize), weight: .heavy, design: .rounded))
            .foregroundColor(Color(red: 1.00, green: 0.78, blue: 0.12))
            .shadow(
                color: .black.opacity(0.22),
                radius: geometry.shadowRadius(for: ringSize),
                y: geometry.shadowYOffset(for: ringSize)
            )
            .offset(x: starOffset.width, y: starOffset.height)
            .accessibilityHidden(true)
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
                Task { @MainActor in
                    // Let initial LazyVStack layout settle before pagination can react to onAppear.
                    await Task.yield()
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
        calendar.bodyRotatedVeryShortWeekdaySymbols()
    }

    private func leadingBlankCount(for month: ActivityRingCalendarMonth) -> Int {
        guard let firstDate = month.days.first?.date else {
            return 0
        }

        return calendar.leadingBlankDayCount(for: firstDate)
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
                    BodyActivityRingCompletionStar(ringSize: 34)
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

    private let ringSize: CGFloat = 108
    private let moveColor = BodyActivityRingPalette.move
    private let exerciseColor = BodyActivityRingPalette.exercise
    private let standColor = BodyActivityRingPalette.stand

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity Rings")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                ZStack(alignment: .topTrailing) {
                    BodyActivityRingGraphic(
                        summary: summary,
                        moveColor: moveColor,
                        exerciseColor: exerciseColor,
                        standColor: standColor
                    )
                    .frame(width: ringSize, height: ringSize)

                    if summary.isCompleted {
                        BodyActivityRingCompletionStar(ringSize: ringSize)
                    }
                }
                .frame(width: ringSize, height: ringSize)
                .padding(.leading, 12)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                .foregroundColor(.accentColor)
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
        let kind: HealthMetricKind
        let title: String
        let value: String
        let unit: String
        let symbolName: String
        let symbolColor: Color
        let prominentMetrics: [BodyMetricDisplayValue]
        let chartPreviewStyle: BodyHomeMetricCardPreview.Style
        let chartPreview: HealthTrendSeries?

        init(
            kind: HealthMetricKind,
            title: String,
            value: String,
            unit: String,
            symbolName: String,
            symbolColor: Color,
            prominentMetrics: [BodyMetricDisplayValue] = [],
            chartPreviewStyle: BodyHomeMetricCardPreview.Style = .line,
            chartPreview: HealthTrendSeries? = nil
        ) {
            self.kind = kind
            self.title = title
            self.value = value
            self.unit = unit
            self.symbolName = symbolName
            self.symbolColor = symbolColor
            self.prominentMetrics = prominentMetrics
            self.chartPreviewStyle = chartPreviewStyle
            self.chartPreview = chartPreview
        }

        var id: String {
            kind.id
        }
    }

    let metric: Model

    var body: some View {
        cardContent
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .bodyCardBackground(cornerRadius: 28)
    }

    @ViewBuilder
    private var cardContent: some View {
        if !metric.prominentMetrics.isEmpty {
            prominentContent
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                titleLabel

                Spacer(minLength: 0)

                valueRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            visualStack
        }
    }

    private var prominentContent: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                titleLabel

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(metric.prominentMetrics) { display in
                        displayValueRow(display, valueFontSize: 26)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            visualStack
        }
    }

    private var titleLabel: some View {
        Text(metric.title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var visualStack: some View {
        VStack(alignment: .trailing, spacing: 20) {
            if let chartPreview = metric.chartPreview {
                BodyHealthMetricCardTrendPreview(
                    series: chartPreview,
                    tintColor: metric.symbolColor,
                    style: metric.chartPreviewStyle
                )
            }

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
        .frame(width: BodyHomeMetricCardPreview.barPreviewWidth, alignment: .bottomTrailing)
        .padding(.bottom, 4)
    }

    private var valueRow: some View {
        displayValueRow(
            BodyMetricDisplayValue(title: metric.title, value: metric.value, unit: metric.unit),
            valueFontSize: 30
        )
    }

    private func displayValueRow(_ display: BodyMetricDisplayValue, valueFontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(display.value)
                .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
                .layoutPriority(1)

            if !display.unit.isEmpty {
                Text(display.unit)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
            }
        }
        .layoutPriority(1)
    }
}

private struct BodyHealthMetricCardTrendPreview: View {
    let series: HealthTrendSeries
    let tintColor: Color
    let style: BodyHomeMetricCardPreview.Style

    private struct LinePlotEntry: Identifiable {
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

    private var calendarPoints: [HealthTrendCalendarPoint] {
        BodyHomeMetricCardPreview.calendarPoints(from: series)
    }

    private var values: [Double] {
        calendarPoints.compactMap(\.value).filter(\.isFinite)
    }

    private var maximumValue: Double {
        max(values.max() ?? 0, 1)
    }

    private var lastValueIndex: Int? {
        calendarPoints.lastIndex { point in
            point.value?.isFinite == true
        }
    }

    var body: some View {
        Group {
            switch style {
            case .line:
                linePreview
            case .bar:
                barPreview
            }
        }
        .frame(width: previewWidth, height: 42, alignment: .bottomTrailing)
        .accessibilityHidden(true)
    }

    private var previewWidth: CGFloat {
        switch style {
        case .line:
            return BodyHomeMetricCardPreview.linePreviewWidth
        case .bar:
            return BodyHomeMetricCardPreview.barPreviewWidth
        }
    }

    private var barPreview: some View {
        let indexedPoints = Array(calendarPoints.enumerated())

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(indexedPoints, id: \.element.id) { index, point in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor(for: point, at: index))
                    .frame(width: 5, height: barHeight(for: point.value))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var linePreview: some View {
        GeometryReader { proxy in
            let plotEntries = linePlotEntries(in: proxy.size)
            let valueEntries = plotEntries.filter(\.hasValue)

            ZStack {
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

                ForEach(plotEntries) { entry in
                    if entry.hasValue {
                        let isCurrent = entry.index == (lastValueIndex ?? -1)
                        let diameter = isCurrent
                            ? BodyHomeMetricCardPreview.lineCurrentPointDiameter
                            : BodyHomeMetricCardPreview.linePointDiameter

                        Circle()
                            .fill(isCurrent ? tintColor : Color(.secondarySystemBackground))
                            .frame(width: diameter, height: diameter)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isCurrent ? tintColor : Color.secondary.opacity(0.28),
                                        lineWidth: 2
                                    )
                            )
                            .position(entry.position)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.20))
                            .frame(width: 4, height: 4)
                            .position(entry.position)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barColor(for point: HealthTrendCalendarPoint, at index: Int) -> Color {
        guard point.value?.isFinite == true else {
            return Color.secondary.opacity(0.14)
        }

        return index == (lastValueIndex ?? -1) ? tintColor : Color.secondary.opacity(0.24)
    }

    private func barHeight(for value: Double?) -> CGFloat {
        guard let value, value.isFinite, value > 0 else {
            return 5
        }

        return max(6, CGFloat(value / maximumValue) * 42)
    }

    private func linePlotEntries(in size: CGSize) -> [LinePlotEntry] {
        guard !calendarPoints.isEmpty else {
            return []
        }

        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let valueRange = maximum - minimum
        let horizontalInset: CGFloat = 5
        let verticalInset: CGFloat = 5
        let plotWidth = max(size.width - horizontalInset * 2, 1)
        let plotHeight = max(size.height - verticalInset * 2, 1)
        let denominator = max(CGFloat(calendarPoints.count - 1), 1)

        return calendarPoints.enumerated().map { index, point in
            let x = horizontalInset + plotWidth * CGFloat(index) / denominator
            let normalizedValue: Double
            if let value = point.value, value.isFinite {
                normalizedValue = valueRange == 0 ? 0.5 : (value - minimum) / valueRange
            } else {
                normalizedValue = 0
            }
            let y = verticalInset + plotHeight * (1 - CGFloat(normalizedValue))
            return LinePlotEntry(
                point: point,
                position: CGPoint(x: x, y: y),
                index: index
            )
        }
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
