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
private let bodyHealthDetailChartMinimumTrailingDatePadding: TimeInterval = 36 * 60 * 60

private func bodyHealthDetailChartTrailingDatePadding(for selectedRange: BodyHealthTrendRange) -> TimeInterval {
    let rangeScaledPadding = Double(selectedRange.axisStrideDayCount) * 24 * 60 * 60 * 0.55
    return max(bodyHealthDetailChartMinimumTrailingDatePadding, rangeScaledPadding)
}

private func bodyHealthDetailChartXDomain(for dates: [Date], selectedRange: BodyHealthTrendRange) -> ClosedRange<Date> {
    let trailingDatePadding = bodyHealthDetailChartTrailingDatePadding(for: selectedRange)

    guard let startDate = dates.min(), let endDate = dates.max() else {
        let now = Date()
        return now.addingTimeInterval(-bodyHealthDetailChartLeadingDatePadding)...now.addingTimeInterval(trailingDatePadding)
    }

    return startDate.addingTimeInterval(-bodyHealthDetailChartLeadingDatePadding)...endDate.addingTimeInterval(trailingDatePadding)
}

enum BodyHealthMetricRangeYDomain {
    static func bloodOxygen(from values: [Double]) -> ClosedRange<Double> {
        fiveStepDomain(from: values, defaultDomain: 90...100, minimumUpperBound: 100)
    }

    static func respiratoryRate(from values: [Double]) -> ClosedRange<Double> {
        fiveStepDomain(from: values, defaultDomain: 10...25)
    }

    private static func fiveStepDomain(
        from values: [Double],
        defaultDomain: ClosedRange<Double>,
        minimumUpperBound: Double? = nil
    ) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let minimum = finiteValues.min(), let maximum = finiteValues.max() else {
            return defaultDomain
        }

        let lower = max(0, ceil(minimum / 5) * 5 - 5)
        let roundedUpper = ceil(maximum / 5) * 5
        let upper = minimumUpperBound.map { max(roundedUpper, $0) } ?? roundedUpper
        guard lower < upper else {
            return lower...max(upper, lower + 5)
        }

        return lower...upper
    }
}

private func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String? {
    bodyChartSelectionDateText(startDate: point.startDate, endDate: point.endDate)
}

private func bodyChartSelectionDateText(for point: HealthTrendRangeCalendarPoint) -> String? {
    bodyChartSelectionDateText(startDate: point.startDate, endDate: point.endDate)
}

private func wristTemperatureBaseline(from series: HealthTrendSeries) -> Double {
    let points = series.lineChartCalendarPoints(to: .recentYear)
    let finiteValues = points.compactMap(\.value).filter(\.isFinite)
    guard !finiteValues.isEmpty else {
        return 0
    }

    return finiteValues.reduce(0, +) / Double(finiteValues.count)
}

private func wristTemperatureBaselineDeviationDisplay(
    currentCelsius: Double?,
    series: HealthTrendSeries
) -> BodyMetricDisplayValue {
    let points = series.lineChartCalendarPoints(to: .recentYear)
    let finiteValues = points.compactMap(\.value).filter(\.isFinite)
    guard
        !finiteValues.isEmpty,
        let current = currentCelsius,
        current.isFinite
    else {
        return BodyMetricDisplayValue(title: "Baseline", value: "--", unit: "")
    }

    let baseline = finiteValues.reduce(0, +) / Double(finiteValues.count)
    let diff = current - baseline
    let magnitude = BodyValueFormat.numberText(abs(diff), decimals: 1)
    let formattedValue: String
    if diff > 0.05 {
        formattedValue = "+\(magnitude)"
    } else if diff < -0.05 {
        formattedValue = "−\(magnitude)"
    } else {
        formattedValue = magnitude
    }

    return BodyMetricDisplayValue(title: "Baseline", value: formattedValue, unit: "C")
}

private func bodyChartSelectionDateText(startDate: Date, endDate: Date) -> String? {
    let calendar = Calendar.bodyGregorian
    guard startDate != endDate else {
        return nil
    }
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

struct BodyDataLoadingOverlay: View {
    var message: String = "Loading data..."

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.regular)
                    .tint(.white)

                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.18))
            )
            .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 8)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct BodyPullToRefreshLoadingOverlayModifier: ViewModifier {
    let isPresented: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                BodyDataLoadingOverlay()
                    .allowsHitTesting(true)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresented)
    }
}

extension View {
    func bodyPullToRefreshLoadingOverlay(isPresented: Bool) -> some View {
        modifier(BodyPullToRefreshLoadingOverlayModifier(isPresented: isPresented))
    }
}

struct BodyHomeView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedWeightUnitKey) private var selectedWeightUnitRawValue = BodyValueFormat.WeightUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true
    @AppStorage(BodyAppearancePreference.homeCardOrderKey) private var homeCardOrderRawValue = BodyHomeCardKind.defaultRawValue
    @AppStorage(BodyAppearancePreference.summaryCardSelectionKey) private var summaryCardSelectionRawValue = BodySummaryCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.defaultTrendRangeKey) private var defaultTrendRangeRawValue = BodyHealthTrendRange.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey) private var homeTrendCardSelectionRawValue = BodyHomeTrendCardSelection.defaultRawValue
    @State private var draggedHomeCard: BodyHomeCardKind?
    @State private var showsAllHomeTrends = false
    @State private var isPullRefreshing = false
    @StateObject private var trendComputationCache = BodyHomeTrendComputationCache()

    var body: some View {
        let metricCardLookup = metricCardsByKind

        return NavigationStack {
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
                                        reorderableHomeCard(for: card, lookup: metricCardLookup)
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
                    let started = Date()
                    isPullRefreshing = true
                    await workoutStore.requestAuthorizationAndRefresh()
                    await workoutStore.awaitRefreshCompletion(minimumDurationFrom: started)
                    isPullRefreshing = false
                }
            }
            .bodyPullToRefreshLoadingOverlay(isPresented: isPullRefreshing)
            .navigationDestination(for: HealthMetricKind.self) { kind in
                BodyHealthMetricDetailView(
                    model: detailModel(for: kind),
                    initialTrendRange: defaultTrendRange
                )
            }
        }
    }

    private var homeCardOrder: [BodyHomeCardKind] {
        BodyHomeCardKind.storedOrder(from: homeCardOrderRawValue)
    }

    private var homeCardRows: [BodyHomeCardLayoutRow] {
        BodyHomeCardKind.layoutRows(from: homeCardOrder, visibleIn: summaryCardSelection)
    }

    private var summaryCardSelection: BodySummaryCardSelection {
        BodySummaryCardSelection.storedValue(from: summaryCardSelectionRawValue)
    }

    private var defaultTrendRange: BodyHealthTrendRange {
        BodyHealthTrendRange.storedValue(from: defaultTrendRangeRawValue)
    }

    private var sleepDurationGoal: TimeInterval {
        BodySleepDurationGoal.duration(from: sleepDurationGoalMinutes)
    }

    private var homeTrendCardSelection: BodyHomeTrendCardSelection {
        BodyHomeTrendCardSelection.storedValue(from: homeTrendCardSelectionRawValue)
    }

    @ViewBuilder
    private var homeTrendsSection: some View {
        let allCards = allHomeTrendCards
        let significantCards = showsAllHomeTrends ? allCards : significantHomeTrendCards
        let visibleTrendCards = showsAllHomeTrends ? allCards : Array(significantCards.prefix(4))
        let canToggleAll = showsAllHomeTrends || allCards.count > visibleTrendCards.count

        if !visibleTrendCards.isEmpty {
            BodyHomeSectionDivider()
                .padding(.top, 8)

            BodyHomeTrendsSection(
                cards: visibleTrendCards,
                canToggleAll: canToggleAll,
                showsAllTrends: showsAllHomeTrends,
                toggleAll: toggleAllHomeTrends
            )
            .padding(.top, 8)
        }
    }

    private var metricCardsByKind: [HealthMetricKind: BodyHealthMetricCard.Model] {
        Dictionary(uniqueKeysWithValues: metricCards.map { ($0.kind, $0) })
    }

    private var metricCards: [BodyHealthMetricCard.Model] {
        let summary = workoutStore.healthSummary
        let trends = workoutStore.healthTrends

        return [
            recoveryMetric(
                summary: summary.recovery,
                chartPreview: trends.series(for: .recovery)
            ),
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
            metric(
                kind: .trainingLoad,
                title: "Training Load",
                summary: summary.trainingLoad,
                unit: "",
                decimals: 2,
                symbolName: "figure.strengthtraining.traditional",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .line,
                chartPreview: trends.series(for: .trainingLoad)
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
            sleepMetric(
                summary: summary,
                sleepHistory: trends.sleepHistory,
                chartPreview: trends.series(for: .sleep)
            ),
            basicsMetric(summary: summary, chartPreview: trends.series(for: .bodyMass)),
            metric(
                kind: .heartRate,
                title: "Heart Rate",
                summary: summary.heartRate,
                unit: "bpm",
                decimals: 0,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                chartPreview: trends.series(for: .heartRate)
            ),
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
                chartPreviewStyle: .range,
                chartRangePreview: trends.rangeSeries(for: .oxygenSaturation)
            ),
            metric(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                summary: summary.respiratoryRate,
                unit: "br/min",
                decimals: 0,
                symbolName: "lungs.fill",
                symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
                chartPreviewStyle: .range,
                chartRangePreview: trends.rangeSeries(for: .respiratoryRate)
            ),
            energyMetric(
                kind: .activeEnergy,
                title: "Active Energy",
                summary: summary.activeEnergy,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartPreview: trends.series(for: .activeEnergy)
            ),
            energyMetric(
                kind: .restingEnergy,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
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
            temperatureUnitPreference: selectedTemperatureUnitPreference
        ).unit
        let energyUnit = selectedEnergyUnitPreference.unitLabel
        let cards = [
            homeTrendCard(
                kind: .recovery,
                title: "Recovery",
                series: trends.series(for: .recovery),
                chartStyle: .line,
                symbolName: "bolt.heart.fill",
                symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                messageStyle: .average(subject: "your recovery score"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .heartRate,
                title: "Heart Rate",
                series: trends.series(for: .heartRate),
                chartStyle: .line,
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " BPM" },
                messageStyle: .average(subject: "your heart rate"),
                includesStable: includesStable
            ),
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
                        temperatureUnitPreference: selectedTemperatureUnitPreference
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
                series: trends.series(for: .activeEnergy).mapValues {
                    BodyValueFormat.energyValue(
                        kilocalories: $0,
                        energyUnitPreference: selectedEnergyUnitPreference
                    ).value
                },
                chartStyle: .bar,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " " + energyUnit },
                messageStyle: .quantity(subject: "Your active energy"),
                includesStable: includesStable
            ),
            homeTrendCard(
                kind: .restingEnergy,
                title: "Resting Energy",
                series: trends.series(for: .restingEnergy).mapValues {
                    BodyValueFormat.energyValue(
                        kilocalories: $0,
                        energyUnitPreference: selectedEnergyUnitPreference
                    ).value
                },
                chartStyle: .bar,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " " + energyUnit },
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
                kind: .trainingLoad,
                title: "Training Load",
                series: trends.series(for: .trainingLoad),
                chartStyle: .line,
                symbolName: "figure.strengthtraining.traditional",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 2) },
                messageStyle: .quantity(subject: "Your training load ratio"),
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
        .filter { homeTrendCardSelection.includes($0.presentation.kind) }

        return cards
    }

    private var selectedAccent: BodyAppAccent {
        BodyAppAccent.storedValue(from: selectedAccentRawValue)
    }

    private var selectedWeightUnitPreference: BodyValueFormat.WeightUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.WeightUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.WeightUnitPreference.storedValue(from: selectedWeightUnitRawValue)
    }

    private var selectedEnergyUnitPreference: BodyValueFormat.EnergyUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.EnergyUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.EnergyUnitPreference.storedValue(from: selectedEnergyUnitRawValue)
    }

    private var selectedTemperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: selectedTemperatureUnitRawValue)
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
        chartPreviewStyle: BodyHomeMetricCardPreview.Style? = nil,
        chartPreview: HealthTrendSeries? = nil,
        chartRangePreview: HealthTrendRangeSeries? = nil
    ) -> BodyHealthMetricCard.Model {
        BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: summary.value.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor,
            chartPreviewStyle: chartPreviewStyle ?? BodyHomeMetricCardPreview.Style.matching(chartStyle: chartStyle),
            chartPreview: chartPreview,
            chartRangePreview: chartRangePreview
        )
    }

    private func recoveryMetric(
        summary: RecoverySummary,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let scoreText = summary.score.map { "\($0)" } ?? "--"

        return BodyHealthMetricCard.Model(
            kind: .recovery,
            title: "Recovery",
            value: scoreText,
            unit: summary.score == nil ? "" : "%",
            symbolName: "bolt.heart.fill",
            symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
            chartPreviewStyle: .line,
            chartPreview: chartPreview
        )
    }

    private func energyMetric(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        symbolName: String,
        symbolColor: Color,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let display = summary.value.map {
            BodyValueFormat.energyValue(kilocalories: $0, energyUnitPreference: selectedEnergyUnitPreference)
        }

        return BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: display.map { BodyValueFormat.numberText($0.value, decimals: 0) } ?? "--",
            unit: selectedEnergyUnitPreference.unitLabel,
            symbolName: symbolName,
            symbolColor: symbolColor,
            chartPreviewStyle: .bar,
            chartPreview: chartPreview.mapValues {
                BodyValueFormat.energyValue(
                    kilocalories: $0,
                    energyUnitPreference: selectedEnergyUnitPreference
                ).value
            }
        )
    }

    private func wristTemperatureMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let display = summary.wristTemperature.value.map {
            BodyValueFormat.temperatureDisplay(
                celsius: $0,
                temperatureUnitPreference: selectedTemperatureUnitPreference
            )
        }
        let temperatureUnit = BodyValueFormat.temperatureDisplay(
            celsius: 0,
            temperatureUnitPreference: selectedTemperatureUnitPreference
        ).unit
        let actualDisplay = BodyMetricDisplayValue(
            title: "Wrist Temperature",
            value: display?.value ?? "--",
            unit: display?.unit ?? temperatureUnit
        )
        let deviationDisplay = wristTemperatureBaselineDeviationDisplay(
            currentCelsius: summary.wristTemperature.value,
            series: chartPreview
        )

        return BodyHealthMetricCard.Model(
            kind: .wristTemperature,
            title: "Wrist Temp",
            value: display?.value ?? "--",
            unit: display?.unit ?? temperatureUnit,
            symbolName: "thermometer.medium",
            symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
            prominentMetrics: [deviationDisplay, actualDisplay],
            chartPreviewStyle: .line,
            chartPreview: chartPreview
        )
    }

    private func sleepMetric(
        summary: HealthSummarySnapshot,
        sleepHistory: SleepHistorySnapshot,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let prominentMetrics: [BodyMetricDisplayValue]
        if showSleepScore {
            let sleepScoreDisplay = SleepScoreSummary(
                sleep: summary.sleep,
                idealSleepDuration: sleepDurationGoal,
                recentSleepHistory: sleepHistory,
                on: summary.sleep.stageSnapshot.date
            ).map {
                BodyMetricDisplayValue(title: "Score", value: "\($0.total)", unit: "PTS")
            } ?? BodyMetricDisplayValue(title: "Score", value: "--", unit: "")

            prominentMetrics = [
                sleepScoreDisplay,
                BodyMetricDisplayValue(
                    title: "Duration",
                    value: formattedSleepDuration(summary.sleep.duration),
                    unit: ""
                )
            ]
        } else {
            prominentMetrics = []
        }

        return BodyHealthMetricCard.Model(
            kind: .sleep,
            title: "Sleep",
            value: formattedSleepDuration(summary.sleep.duration),
            unit: "",
            symbolName: "bed.double.fill",
            symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
            prominentMetrics: prominentMetrics,
            chartPreview: chartPreview
        )
    }

    private func basicsMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let weightDisplay = summary.bodyMass.value.map {
            BodyValueFormat.massDisplay(
                kilograms: $0,
                weightUnitPreference: selectedWeightUnitPreference,
                decimals: 2
            )
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
                weightUnitPreference: selectedWeightUnitPreference
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
                        weightUnitPreference: selectedWeightUnitPreference
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
        guard let result = trendComputationCache.result(
            for: kind,
            series: series,
            includesStable: includesStable
        ) else {
            return nil
        }

        let presentation = BodyHomeTrendCardPresentation.make(
            from: result,
            kind: kind,
            title: title,
            chartStyle: chartStyle,
            valueFormatter: valueFormatter,
            messageStyle: messageStyle
        )

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

    private func reorderableHomeCard(
        for card: BodyHomeCardKind,
        lookup: [HealthMetricKind: BodyHealthMetricCard.Model]
    ) -> some View {
        homeCardView(for: card, lookup: lookup)
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
    private func homeCardView(
        for card: BodyHomeCardKind,
        lookup: [HealthMetricKind: BodyHealthMetricCard.Model]
    ) -> some View {
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
               let metric = lookup[metricKind] {
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
        case .recovery:
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Recovery",
                value: summary.recovery.score.map { "\($0)" } ?? "--",
                unit: summary.recovery.score == nil ? "" : "%",
                symbolName: "bolt.heart.fill",
                symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
                series: trends.recovery,
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                highlightedRange: BodyRecoveryStatusPresentation.make(
                    for: summary.recovery.score.map(Double.init)
                ),
                highlightedRangeResolver: BodyRecoveryStatusPresentation.make(for:),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                secondaryValueFormatter: nil,
                recovery: summary.recovery,
                headerMetrics: [
                    BodyMetricDisplayValue(
                        title: "Recovery",
                        value: summary.recovery.score.map { "\($0)" } ?? "--",
                        unit: summary.recovery.score == nil ? "" : "%"
                    ),
                    BodyMetricDisplayValue(
                        title: "Status",
                        value: summary.recovery.status.title,
                        unit: ""
                    )
                ],
                helpText: kind.detailHelpText,
                dataSourceText: kind.detailDataSourceText
            )
        case .heartRate:
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Heart Rate",
                value: summary.heartRate.value.map { BodyValueFormat.numberText($0, decimals: 0) } ?? "--",
                unit: "bpm",
                symbolName: "heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                series: trends.heartRate,
                daySeries: trends.heartRateDaySamples,
                secondaryDaySeries: trends.secondaryDaySeries(for: kind),
                rangeSeries: trends.heartRateRanges,
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + " bpm" },
                secondaryValueFormatter: nil,
                sourceRangeComparisonTrend: workoutStore.sourceRangeComparisonTrend(for: kind),
                helpText: kind.detailHelpText,
                dataSourceText: kind.detailDataSourceText
            )
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
        case .trainingLoad:
            let trainingLoadInterval = BodyTrainingLoadIntervalPresentation.make(for: summary.trainingLoad.value)
            return metricDetail(
                kind: kind,
                title: "Training Load",
                summary: summary.trainingLoad,
                unit: "",
                decimals: 2,
                symbolName: "figure.strengthtraining.traditional",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .line,
                highlightedRange: trainingLoadInterval,
                highlightedRangeResolver: BodyTrainingLoadIntervalPresentation.make(for:)
            )
        case .wristTemperature:
            let display = summary.wristTemperature.value.map {
                BodyValueFormat.temperatureDisplay(
                    celsius: $0,
                    temperatureUnitPreference: selectedTemperatureUnitPreference
                )
            }
            let temperatureUnit = BodyValueFormat.temperatureDisplay(
                celsius: 0,
                temperatureUnitPreference: selectedTemperatureUnitPreference
            ).unit
            let actualDisplay = BodyMetricDisplayValue(
                title: "Wrist Temperature",
                value: display?.value ?? "--",
                unit: display?.unit ?? temperatureUnit
            )
            let deviationDisplay = wristTemperatureBaselineDeviationDisplay(
                currentCelsius: summary.wristTemperature.value,
                series: trends.wristTemperature
            )
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
                        temperatureUnitPreference: selectedTemperatureUnitPreference
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
                headerMetrics: [
                    deviationDisplay,
                    actualDisplay
                ],
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
                secondaryDaySeries: .empty,
                basicsTrend: nil,
                sleepStageSnapshot: summary.sleep.stageSnapshot,
                sleepScore: showSleepScore
                    ? SleepScoreSummary(
                        sleep: summary.sleep,
                        idealSleepDuration: sleepDurationGoal,
                        recentSleepHistory: trends.sleepHistory,
                        on: summary.sleep.stageSnapshot.date
                    )
                    : nil,
                sleepVitals: summary.sleep.vitals,
                sleepDuration: summary.sleep.duration,
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) + "h" },
                secondaryValueFormatter: nil,
                sourceLineComparisonTrend: workoutStore.sourceLineComparisonTrend(for: kind),
                dataSourceText: kind.detailDataSourceText
            )
        case .basics:
            let display = summary.bodyMass.value.map {
                BodyValueFormat.massDisplay(
                    kilograms: $0,
                    weightUnitPreference: selectedWeightUnitPreference,
                    decimals: 2
                )
            }
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                weightUnitPreference: selectedWeightUnitPreference
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
                        BodyValueFormat.massValue(
                            kilograms: $0,
                            weightUnitPreference: selectedWeightUnitPreference
                        ).value
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
                BodyValueFormat.massDisplay(
                    kilograms: $0,
                    weightUnitPreference: selectedWeightUnitPreference
                )
            }
            let massUnit = BodyValueFormat.massValue(
                kilograms: 0,
                weightUnitPreference: selectedWeightUnitPreference
            ).unit
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Weight",
                value: display?.value ?? "--",
                unit: display?.unit ?? massUnit,
                symbolName: "scalemass.fill",
                symbolColor: Color(red: 0.50, green: 0.34, blue: 1.00),
                series: trends.bodyMass.mapValues {
                    BodyValueFormat.massValue(
                        kilograms: $0,
                        weightUnitPreference: selectedWeightUnitPreference
                    ).value
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
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                sleepHistory: trends.sleepHistory
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
                unit: selectedEnergyUnitPreference.unitLabel,
                decimals: 0,
                symbolName: "flame.fill",
                symbolColor: Color(red: 1.00, green: 0.38, blue: 0.12),
                chartStyle: .bar,
                valueTransform: {
                    BodyValueFormat.energyValue(
                        kilocalories: $0,
                        energyUnitPreference: selectedEnergyUnitPreference
                    ).value
                }
            )
        case .restingEnergy:
            return metricDetail(
                kind: kind,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                unit: selectedEnergyUnitPreference.unitLabel,
                decimals: 0,
                symbolName: "leaf.fill",
                symbolColor: Color(red: 0.14, green: 0.72, blue: 0.42),
                chartStyle: .bar,
                valueTransform: {
                    BodyValueFormat.energyValue(
                        kilocalories: $0,
                        energyUnitPreference: selectedEnergyUnitPreference
                    ).value
                }
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
        chartStyle: BodyHealthMetricChartStyle = .line,
        highlightedRange: BodyHealthMetricTrendHighlightedRange? = nil,
        highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)? = nil,
        sleepHistory: SleepHistorySnapshot = .empty,
        valueTransform: @escaping (Double) -> Double = { $0 }
    ) -> BodyHealthMetricDetailModel {
        let suffix = unit.isEmpty ? "" : " " + unit
        let transformedValue = summary.value.map(valueTransform)
        return BodyHealthMetricDetailModel(
            kind: kind,
            title: title,
            value: transformedValue.map { BodyValueFormat.numberText($0, decimals: decimals) } ?? "--",
            unit: unit,
            symbolName: symbolName,
            symbolColor: symbolColor,
            series: workoutStore.healthTrends.series(for: kind).mapValues(valueTransform),
            daySeries: workoutStore.healthTrends.daySeries(for: kind).mapValues(valueTransform),
            secondaryDaySeries: workoutStore.healthTrends.secondaryDaySeries(for: kind).mapValues(valueTransform),
            rangeSeries: workoutStore.healthTrends.rangeSeries(for: kind),
            basicsTrend: nil,
            sleepStageSnapshot: nil,
            sleepScore: nil,
            sleepVitals: nil,
            sleepDuration: nil,
            sleepHistory: sleepHistory,
            chartStyle: chartStyle,
            highlightedRange: highlightedRange,
            highlightedRangeResolver: highlightedRangeResolver,
            valueFormatter: { BodyValueFormat.numberText($0, decimals: decimals) + suffix },
            secondaryValueFormatter: nil,
            sourceComparisonTrend: kind.usesSourceComparisonBarChart
                ? workoutStore.sourceComparisonTrend(for: kind)?.mapValues(valueTransform)
                : nil,
            sourceRangeComparisonTrend: kind.usesSourceComparisonRangeChart
                ? workoutStore.sourceRangeComparisonTrend(for: kind)
                : nil,
            sourceLineComparisonTrend: kind.usesSourceComparisonLineChart
                ? workoutStore.sourceLineComparisonTrend(for: kind)?.mapValues(valueTransform)
                : nil,
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
        case range

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

    static func rangeCalendarPoints(
        from series: HealthTrendRangeSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeCalendarPoint] {
        let bounds = previewDateBounds(for: series, calendar: calendar, date: date)
        let pointsByDay = Dictionary(grouping: rangePoints(from: series, calendar: calendar, date: date)) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<previewDayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: bounds.startDate) else {
                return nil
            }

            let point = pointsByDay[day]?.last
            return HealthTrendRangeCalendarPoint(
                date: day,
                lowValue: point?.lowValue.isFinite == true ? point?.lowValue : nil,
                highValue: point?.highValue.isFinite == true ? point?.highValue : nil,
                averageValue: point?.averageValue?.isFinite == true ? point?.averageValue : nil
            )
        }
    }

    private static func rangePoints(
        from series: HealthTrendRangeSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [HealthTrendRangeDataPoint] {
        let bounds = previewDateBounds(for: series, calendar: calendar, date: date)

        return series.points
            .filter { point in
                point.date >= bounds.startDate && point.date < bounds.endDate
            }
            .sorted { $0.date < $1.date }
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

    private static func previewDateBounds(
        for series: HealthTrendRangeSeries,
        calendar: Calendar,
        date: Date
    ) -> (startDate: Date, endDate: Date) {
        let currentDayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let hasCurrentDayValue = series.points.contains { point in
            point.date >= currentDayStart &&
                point.date < nextDayStart &&
                point.lowValue.isFinite &&
                point.highValue.isFinite
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
        let phrase = BodyHomeTrendCardPresentation.recentPeriodPhrase(days: recentDayCount)
        switch self {
        case .average(let subject):
            return "On average, \(subject) \(direction.averagePhrase) over the last \(phrase)."
        case .quantity(let subject):
            return "\(subject) \(direction.quantityPhrase) over the last \(phrase)."
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
    static let minimumTrendSegmentDayCount = 3
    static let minimumRelativeChange = 0.01
    static let minimumAbsoluteChange = 0.01
    static let averageLineStrokeWidth: CGFloat = 4
    static let maximumDisplayPointCount = 60

    struct WindowSpec: Equatable {
        let totalDayCount: Int
        let minimumSegmentDayCount: Int
        let preferredRecentDayCount: Int
    }

    static let windowSpecs: [WindowSpec] = [
        WindowSpec(totalDayCount: 28, minimumSegmentDayCount: 3, preferredRecentDayCount: 7),
        WindowSpec(totalDayCount: 90, minimumSegmentDayCount: 7, preferredRecentDayCount: 14),
        WindowSpec(totalDayCount: 180, minimumSegmentDayCount: 14, preferredRecentDayCount: 30),
        WindowSpec(totalDayCount: 270, minimumSegmentDayCount: 21, preferredRecentDayCount: 45),
        WindowSpec(totalDayCount: 365, minimumSegmentDayCount: 30, preferredRecentDayCount: 60)
    ]

    static var maximumWindowDayCount: Int {
        windowSpecs.map(\.totalDayCount).max() ?? 28
    }

    struct WindowResult: Equatable {
        let calendarPoints: [HealthTrendCalendarPoint]
        let displayCalendarPoints: [HealthTrendCalendarPoint]
        let displayBaselineEndIndex: Int
        let totalDayCount: Int
        let baselineDayCount: Int
        let recentDayCount: Int
        let baselineAverage: Double
        let recentAverage: Double
        let absoluteChange: Double
        let isMeaningful: Bool
    }

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
    let displayCalendarPoints: [HealthTrendCalendarPoint]
    let displayBaselineEndIndex: Int
    let totalDayCount: Int
    let baselineDayCount: Int
    let recentDayCount: Int

    var id: String {
        kind.id
    }

    var recentStartIndex: Int {
        baselineDayCount
    }

    var displayRecentStartIndex: Int {
        min(displayBaselineEndIndex + 1, max(displayCalendarPoints.count - 1, 0))
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
        guard let result = bestWindowResult(
            from: series,
            includesStable: includesStable,
            calendar: calendar,
            date: date
        ) else {
            return nil
        }
        return make(
            from: result,
            kind: kind,
            title: title,
            chartStyle: chartStyle,
            valueFormatter: valueFormatter,
            messageStyle: messageStyle
        )
    }

    static func make(
        from result: WindowResult,
        kind: HealthMetricKind,
        title: String,
        chartStyle: BodyHealthMetricChartStyle,
        valueFormatter: (Double) -> String,
        messageStyle: BodyHomeTrendMessageStyle
    ) -> BodyHomeTrendCardPresentation {
        let direction: BodyHomeTrendDirection
        if result.isMeaningful == false {
            direction = .stable
        } else {
            direction = result.absoluteChange > 0 ? .increased : .decreased
        }
        return BodyHomeTrendCardPresentation(
            kind: kind,
            title: title,
            messageText: messageStyle.text(direction: direction, recentDayCount: result.recentDayCount),
            baselineAverage: result.baselineAverage,
            recentAverage: result.recentAverage,
            baselineAverageText: valueFormatter(result.baselineAverage),
            recentAverageText: valueFormatter(result.recentAverage),
            baselinePeriodText: averagePeriodText(days: result.baselineDayCount),
            recentPeriodText: averagePeriodText(days: result.recentDayCount),
            chartStyle: chartStyle,
            calendarPoints: result.calendarPoints,
            displayCalendarPoints: result.displayCalendarPoints,
            displayBaselineEndIndex: result.displayBaselineEndIndex,
            totalDayCount: result.totalDayCount,
            baselineDayCount: result.baselineDayCount,
            recentDayCount: result.recentDayCount
        )
    }

    static func bestWindowResult(
        from series: HealthTrendSeries,
        includesStable: Bool,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> WindowResult? {
        let allPoints = comparisonCalendarPoints(
            from: series,
            dayCount: maximumWindowDayCount,
            calendar: calendar,
            date: date
        )
        var bestCandidate: ComparisonWindow?
        for spec in windowSpecs {
            let windowPoints = Array(allPoints.suffix(spec.totalDayCount))
            guard windowPoints.count == spec.totalDayCount else { continue }
            guard let candidate = bestComparisonWindow(
                in: windowPoints,
                spec: spec,
                includesStable: includesStable
            ) else { continue }
            if let current = bestCandidate {
                if isBetterComparisonWindow(candidate, than: current) {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }
        guard let chosen = bestCandidate else {
            return nil
        }

        let (displayPoints, displayBaselineEndIndex) = downsampledDisplayPoints(
            from: chosen.windowPoints,
            baselineDayCount: chosen.baselineDayCount,
            maximumCount: maximumDisplayPointCount
        )

        return WindowResult(
            calendarPoints: chosen.windowPoints,
            displayCalendarPoints: displayPoints,
            displayBaselineEndIndex: displayBaselineEndIndex,
            totalDayCount: chosen.totalDayCount,
            baselineDayCount: chosen.baselineDayCount,
            recentDayCount: chosen.recentDayCount,
            baselineAverage: chosen.baselineAverage,
            recentAverage: chosen.recentAverage,
            absoluteChange: chosen.absoluteChange,
            isMeaningful: chosen.isMeaningful
        )
    }

    func averageLineSegments(in width: CGFloat) -> (baseline: ClosedRange<CGFloat>, recent: ClosedRange<CGFloat>) {
        let pointCount = displayCalendarPoints.count
        let lastPointIndex = max(pointCount - 1, 0)
        let baselineEndIndex = min(max(displayBaselineEndIndex, 0), lastPointIndex)
        let recentStartIndex = min(max(displayBaselineEndIndex + 1, 0), lastPointIndex)
        let denominator = max(CGFloat(lastPointIndex), 1)
        let halfBucketWidth = width / denominator / 2
        let segmentExtension = max(halfBucketWidth - Self.averageLineStrokeWidth / 2, 0)

        func xPosition(for index: Int) -> CGFloat {
            width * CGFloat(index) / denominator
        }

        return (
            baseline: xPosition(for: 0)...min(width, xPosition(for: baselineEndIndex) + segmentExtension),
            recent: max(0, xPosition(for: recentStartIndex) - segmentExtension)...xPosition(for: lastPointIndex)
        )
    }

    static func recentPeriodPhrase(days: Int) -> String {
        if days < 28 {
            return "\(days) days"
        } else if days < 90 {
            let weeks = max(1, Int((Double(days) / 7).rounded()))
            return "\(weeks) weeks"
        } else {
            let months = max(1, Int((Double(days) / 30).rounded()))
            return "\(months) months"
        }
    }

    static func averagePeriodText(days: Int) -> String {
        if days < 28 {
            return "\(days)-day avg"
        } else if days < 90 {
            let weeks = max(1, Int((Double(days) / 7).rounded()))
            return "\(weeks)-week avg"
        } else {
            let months = max(1, Int((Double(days) / 30).rounded()))
            return "\(months)-month avg"
        }
    }

    private static func bestComparisonWindow(
        in calendarPoints: [HealthTrendCalendarPoint],
        spec: WindowSpec,
        includesStable: Bool
    ) -> ComparisonWindow? {
        let totalDayCount = spec.totalDayCount
        let minimumSegmentDayCount = spec.minimumSegmentDayCount
        let maximumBaselineDayCount = totalDayCount - minimumSegmentDayCount
        guard minimumSegmentDayCount <= maximumBaselineDayCount else { return nil }

        let candidates: [ComparisonWindow] = (minimumSegmentDayCount...maximumBaselineDayCount).compactMap { baselineDayCount -> ComparisonWindow? in
            let recentDayCount = totalDayCount - baselineDayCount
            let baselinePoints = Array(calendarPoints.prefix(baselineDayCount))
            let recentPoints = Array(calendarPoints.suffix(recentDayCount))
            let baselineValues = finiteValues(from: baselinePoints)
            let recentValues = finiteValues(from: recentPoints)

            guard baselineValues.count >= minimumSegmentDayCount,
                  recentValues.count >= minimumSegmentDayCount else {
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
                spec: spec,
                totalDayCount: totalDayCount,
                baselineDayCount: baselineDayCount,
                recentDayCount: recentDayCount,
                baselineValueCount: baselineValues.count,
                recentValueCount: recentValues.count,
                baselineAverage: baselineAverage,
                recentAverage: recentAverage,
                absoluteChange: absoluteChange,
                minimumMeaningfulChange: minimumMeaningfulChange,
                windowPoints: calendarPoints
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

        let lhsCoverage = lhs.coverageRatio
        let rhsCoverage = rhs.coverageRatio
        if abs(lhsCoverage - rhsCoverage) > 0.000001 {
            return lhsCoverage > rhsCoverage
        }

        let lhsRecentDistance = abs(lhs.recentDayCount - lhs.spec.preferredRecentDayCount)
        let rhsRecentDistance = abs(rhs.recentDayCount - rhs.spec.preferredRecentDayCount)
        if lhsRecentDistance != rhsRecentDistance {
            return lhsRecentDistance < rhsRecentDistance
        }

        if lhs.valueCount != rhs.valueCount {
            return lhs.valueCount > rhs.valueCount
        }

        if lhs.totalDayCount != rhs.totalDayCount {
            return lhs.totalDayCount > rhs.totalDayCount
        }

        return lhs.recentDayCount < rhs.recentDayCount
    }

    private static func comparisonCalendarPoints(
        from series: HealthTrendSeries,
        dayCount: Int,
        calendar: Calendar,
        date: Date
    ) -> [HealthTrendCalendarPoint] {
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -(dayCount - 1), to: currentDayStart)
            ?? currentDayStart
        let endDate = calendar.date(byAdding: .day, value: 1, to: currentDayStart)
            ?? date
        let pointsByDay = Dictionary(grouping: series.points.filter { point in
            point.date >= startDate && point.date < endDate
        }) {
            calendar.startOfDay(for: $0.date)
        }

        return (0..<dayCount).compactMap { offset in
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

    private static func downsampledDisplayPoints(
        from points: [HealthTrendCalendarPoint],
        baselineDayCount: Int,
        maximumCount: Int
    ) -> (display: [HealthTrendCalendarPoint], baselineEndIndex: Int) {
        guard points.count > maximumCount,
              baselineDayCount > 0,
              baselineDayCount < points.count else {
            return (points, max(baselineDayCount - 1, 0))
        }

        let bucketSize = max(1, Int(ceil(Double(points.count) / Double(maximumCount))))
        let baselineSlice = Array(points.prefix(baselineDayCount))
        let recentSlice = Array(points.suffix(points.count - baselineDayCount))
        let baselineBuckets = downsampleSegment(baselineSlice, bucketSize: bucketSize)
        let recentBuckets = downsampleSegment(recentSlice, bucketSize: bucketSize)
        let combined = baselineBuckets + recentBuckets
        let baselineEndIndex = max(baselineBuckets.count - 1, 0)
        return (combined, baselineEndIndex)
    }

    private static func downsampleSegment(
        _ points: [HealthTrendCalendarPoint],
        bucketSize: Int
    ) -> [HealthTrendCalendarPoint] {
        guard bucketSize > 1, points.count > bucketSize else {
            return points
        }
        var buckets: [HealthTrendCalendarPoint] = []
        var index = 0
        while index < points.count {
            let end = min(index + bucketSize, points.count)
            let slice = points[index..<end]
            let values = slice.compactMap(\.value).filter(\.isFinite)
            let bucketAverage = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            let midIndex = index + (end - index) / 2
            let date = points[min(midIndex, end - 1)].date
            buckets.append(HealthTrendCalendarPoint(date: date, value: bucketAverage))
            index = end
        }
        return buckets
    }

    private static func finiteValues(from points: [HealthTrendCalendarPoint]) -> [Double] {
        points.compactMap(\.value).filter(\.isFinite)
    }

    private static func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private struct ComparisonWindow {
        let spec: WindowSpec
        let totalDayCount: Int
        let baselineDayCount: Int
        let recentDayCount: Int
        let baselineValueCount: Int
        let recentValueCount: Int
        let baselineAverage: Double
        let recentAverage: Double
        let absoluteChange: Double
        let minimumMeaningfulChange: Double
        let windowPoints: [HealthTrendCalendarPoint]

        var isMeaningful: Bool {
            abs(absoluteChange) >= minimumMeaningfulChange
        }

        var score: Double {
            abs(absoluteChange) / max(minimumMeaningfulChange, .ulpOfOne)
        }

        var valueCount: Int {
            baselineValueCount + recentValueCount
        }

        var coverageRatio: Double {
            guard totalDayCount > 0 else { return 0 }
            return Double(valueCount) / Double(totalDayCount)
        }
    }
}

@MainActor
final class BodyHomeTrendComputationCache: ObservableObject {
    private struct CacheKey: Hashable {
        let kind: HealthMetricKind
        let includesStable: Bool
    }

    private struct Fingerprint: Equatable {
        let dayStart: Date
        let pointCount: Int
        let firstTimestamp: TimeInterval?
        let lastTimestamp: TimeInterval?
        let firstValue: Double?
        let lastValue: Double?
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let result: BodyHomeTrendCardPresentation.WindowResult?
    }

    private var entries: [CacheKey: Entry] = [:]

    func result(
        for kind: HealthMetricKind,
        series: HealthTrendSeries,
        includesStable: Bool,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> BodyHomeTrendCardPresentation.WindowResult? {
        let fingerprint = Fingerprint(
            dayStart: calendar.startOfDay(for: date),
            pointCount: series.points.count,
            firstTimestamp: series.points.first?.date.timeIntervalSinceReferenceDate,
            lastTimestamp: series.points.last?.date.timeIntervalSinceReferenceDate,
            firstValue: series.points.first?.value,
            lastValue: series.points.last?.value
        )
        let key = CacheKey(kind: kind, includesStable: includesStable)
        if let entry = entries[key], entry.fingerprint == fingerprint {
            return entry.result
        }
        let result = BodyHomeTrendCardPresentation.bestWindowResult(
            from: series,
            includesStable: includesStable,
            calendar: calendar,
            date: date
        )
        entries[key] = Entry(fingerprint: fingerprint, result: result)
        return result
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
    static let dayChartHeight: CGFloat = 252
    static let sleepVitalsHeight: CGFloat = 248
    static let sleepVitalsPlotHeight: CGFloat = 188
    static let sleepVitalsIconAxisHeight: CGFloat = 28
    static let yAxisLabelCount = 4
}

private enum BodySleepScoreDetailsSheetLayout {
    static let sheetHeight: CGFloat = 720
}

private struct BodyMetricDisplayValue: Identifiable {
    let title: String
    let value: String
    let unit: String

    var id: String {
        title
    }
}

struct BodyAnimatedMetricValueText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: String
    let fontSize: CGFloat
    let color: Color
    let minimumScaleFactor: CGFloat

    var body: some View {
        Text(value)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: value)
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
    }
}

private struct BodyHealthMetricTrendHighlightedRange {
    let title: String
    let lowerBound: Double?
    let upperBound: Double?
    let color: Color

    var domainValues: [Double] {
        [lowerBound, upperBound].compactMap { $0 }
    }

    func lowerPlotBound(in domain: ClosedRange<Double>) -> Double {
        max(lowerBound ?? domain.lowerBound, domain.lowerBound)
    }

    func upperPlotBound(in domain: ClosedRange<Double>) -> Double {
        min(upperBound ?? domain.upperBound, domain.upperBound)
    }
}

private enum BodyTrainingLoadIntervalPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let interval = TrainingLoadInterval.interval(for: value) else {
            return nil
        }

        return BodyHealthMetricTrendHighlightedRange(
            title: interval.title,
            lowerBound: interval.lowerBound,
            upperBound: interval.upperBound,
            color: color(for: interval)
        )
    }

    static func color(for interval: TrainingLoadInterval) -> Color {
        switch interval {
        case .stopTraining:
            return Color(red: 0.00, green: 0.88, blue: 0.82)
        case .optimal:
            return Color(red: 0.10, green: 0.82, blue: 0.20)
        case .mediumInjuryRisk:
            return Color(red: 1.00, green: 0.46, blue: 0.10)
        case .highInjuryRisk:
            return Color(red: 1.00, green: 0.17, blue: 0.16)
        }
    }
}

private extension TrainingLoadInterval {
    var symbolName: String {
        switch self {
        case .stopTraining:
            return "pause.circle.fill"
        case .optimal:
            return "checkmark.circle.fill"
        case .mediumInjuryRisk:
            return "exclamationmark.circle.fill"
        case .highInjuryRisk:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct BodyTrainingLoadIntervalBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    var calendar: Calendar = .bodyGregorian
    var date: Date = Date()

    private var entries: [TrainingLoadIntervalBreakdownEntry] {
        TrainingLoadIntervalBreakdown.entries(
            for: series,
            range: selectedRange,
            calendar: calendar,
            date: date
        )
    }

    private var totalDayCount: Int {
        entries.first?.totalDayCount ?? 0
    }

    private var maxDayCount: Int {
        entries.map(\.dayCount).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days by Interval")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if totalDayCount == 0 {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(entries) { entry in
                        intervalDistributionRow(entry)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.45))

            Text("No Training Load yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func intervalDistributionRow(_ entry: TrainingLoadIntervalBreakdownEntry) -> some View {
        GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDayCount > 0 ? Double(entry.dayCount) / Double(maxDayCount) : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                dayCountBar(entry)
                    .frame(width: barWidth, height: rowHeight)

                intervalDetails(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func dayCountBar(_ entry: TrainingLoadIntervalBreakdownEntry) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                .fill(
                    BodyTrainingLoadIntervalPresentation
                        .color(for: entry.interval)
                        .opacity(entry.dayCount == 0 ? 0.18 : 1)
                )

            Text(dayCountText(for: entry.dayCount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(entry.dayCount == 0 ? 0.42 : 0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
        }
    }

    private func intervalDetails(_ entry: TrainingLoadIntervalBreakdownEntry) -> some View {
        HStack(spacing: 9) {
            Image(systemName: entry.interval.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BodyTrainingLoadIntervalPresentation.color(for: entry.interval))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.interval.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("\(dayText(for: entry.dayCount)) • \(percentageText(for: entry))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
    }

    private func dayCountText(for dayCount: Int) -> String {
        "\(dayCount)d"
    }

    private func dayText(for dayCount: Int) -> String {
        dayCount == 1 ? "1 day" : "\(dayCount) days"
    }

    private func percentageText(for entry: TrainingLoadIntervalBreakdownEntry) -> String {
        guard entry.totalDayCount > 0 else { return "0%" }

        let percentage = Int((entry.fractionOfTotal * 100).rounded())
        return "\(percentage)%"
    }

    private func maximumBarWidth(for availableWidth: CGFloat) -> CGFloat {
        max(92, availableWidth - detailReserveWidth(for: availableWidth))
    }

    private func detailReserveWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 130), 172)
    }

    private var minimumBarWidth: CGFloat {
        92
    }

    private var rowHeight: CGFloat {
        50
    }

    private var rowSpacing: CGFloat {
        12
    }

    private var rowHorizontalSpacing: CGFloat {
        12
    }

    private var barCornerRadius: CGFloat {
        16
    }
}

private enum BodyRecoveryStatusPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let value, value.isFinite else {
            return nil
        }

        let status = RecoveryStatus.status(for: Int(value.rounded()))
        guard status != .unavailable else {
            return nil
        }

        return BodyHealthMetricTrendHighlightedRange(
            title: status.title,
            lowerBound: status.lowerBound,
            upperBound: status.upperBound,
            color: color(for: status)
        )
    }

    static func color(for status: RecoveryStatus) -> Color {
        switch status {
        case .prime:
            return Color(red: 0.84, green: 0.08, blue: 0.92)
        case .high:
            return Color(red: 0.20, green: 0.74, blue: 1.00)
        case .moderate:
            return Color(red: 0.10, green: 0.82, blue: 0.20)
        case .low:
            return Color(red: 1.00, green: 0.75, blue: 0.15)
        case .poor:
            return Color(red: 1.00, green: 0.25, blue: 0.12)
        case .unavailable:
            return Color.secondary
        }
    }
}

private extension RecoveryStatus {
    var symbolName: String {
        switch self {
        case .prime:
            return "sparkles"
        case .high:
            return "checkmark.circle.fill"
        case .moderate:
            return "circle.fill"
        case .low:
            return "exclamationmark.circle.fill"
        case .poor:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "questionmark.circle.fill"
        }
    }
}

private struct BodyRecoveryStatusBreakdownChart: View {
    let series: HealthTrendSeries
    let selectedRange: BodyHealthTrendRange
    var calendar: Calendar = .bodyGregorian
    var date: Date = Date()

    private var entries: [RecoveryStatusBreakdownEntry] {
        RecoveryStatusBreakdown.entries(
            for: series,
            range: selectedRange,
            calendar: calendar,
            date: date
        )
    }

    private var totalDayCount: Int {
        entries.first?.totalDayCount ?? 0
    }

    private var maxDayCount: Int {
        entries.map(\.dayCount).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Days by Status")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if totalDayCount == 0 {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(entries) { entry in
                        statusDistributionRow(entry)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.45))

            Text("No Recovery yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func statusDistributionRow(_ entry: RecoveryStatusBreakdownEntry) -> some View {
        GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDayCount > 0 ? Double(entry.dayCount) / Double(maxDayCount) : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                dayCountBar(entry)
                    .frame(width: barWidth, height: rowHeight)

                statusDetails(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func dayCountBar(_ entry: RecoveryStatusBreakdownEntry) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                .fill(
                    BodyRecoveryStatusPresentation
                        .color(for: entry.status)
                        .opacity(entry.dayCount == 0 ? 0.18 : 1)
                )

            Text(dayCountText(for: entry.dayCount))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(entry.dayCount == 0 ? 0.42 : 0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
        }
    }

    private func statusDetails(_ entry: RecoveryStatusBreakdownEntry) -> some View {
        HStack(spacing: 9) {
            Image(systemName: entry.status.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(BodyRecoveryStatusPresentation.color(for: entry.status))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text("\(dayText(for: entry.dayCount)) • \(percentageText(for: entry))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
    }

    private func dayCountText(for dayCount: Int) -> String {
        "\(dayCount)d"
    }

    private func dayText(for dayCount: Int) -> String {
        dayCount == 1 ? "1 day" : "\(dayCount) days"
    }

    private func percentageText(for entry: RecoveryStatusBreakdownEntry) -> String {
        guard entry.totalDayCount > 0 else { return "0%" }

        let percentage = Int((entry.fractionOfTotal * 100).rounded())
        return "\(percentage)%"
    }

    private func maximumBarWidth(for availableWidth: CGFloat) -> CGFloat {
        max(92, availableWidth - detailReserveWidth(for: availableWidth))
    }

    private func detailReserveWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 130), 172)
    }

    private var minimumBarWidth: CGFloat {
        92
    }

    private var rowHeight: CGFloat {
        50
    }

    private var rowSpacing: CGFloat {
        12
    }

    private var rowHorizontalSpacing: CGFloat {
        12
    }

    private var barCornerRadius: CGFloat {
        16
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
    let secondaryDaySeries: HealthTrendSeries
    let rangeSeries: HealthTrendRangeSeries?
    let basicsTrend: BasicsTrendSummary?
    let sleepStageSnapshot: SleepStageSnapshot?
    let sleepScore: SleepScoreSummary?
    let sleepVitals: SleepVitalsSummary?
    let sleepDuration: TimeInterval?
    let sleepHistory: SleepHistorySnapshot
    let recovery: RecoverySummary?
    let chartStyle: BodyHealthMetricChartStyle
    let highlightedRange: BodyHealthMetricTrendHighlightedRange?
    let highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)?
    let valueFormatter: (Double) -> String
    let secondaryValueFormatter: ((Double) -> String)?
    let sourceComparisonTrend: BodyHealthSourceComparisonTrend?
    let sourceRangeComparisonTrend: BodyHealthSourceRangeComparisonTrend?
    let sourceLineComparisonTrend: BodyHealthSourceComparisonTrend?
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
        secondaryDaySeries: HealthTrendSeries = .empty,
        rangeSeries: HealthTrendRangeSeries? = nil,
        basicsTrend: BasicsTrendSummary?,
        sleepStageSnapshot: SleepStageSnapshot?,
        sleepScore: SleepScoreSummary?,
        sleepVitals: SleepVitalsSummary?,
        sleepDuration: TimeInterval?,
        sleepHistory: SleepHistorySnapshot = .empty,
        chartStyle: BodyHealthMetricChartStyle,
        highlightedRange: BodyHealthMetricTrendHighlightedRange? = nil,
        highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)? = nil,
        valueFormatter: @escaping (Double) -> String,
        secondaryValueFormatter: ((Double) -> String)?,
        recovery: RecoverySummary? = nil,
        sourceComparisonTrend: BodyHealthSourceComparisonTrend? = nil,
        sourceRangeComparisonTrend: BodyHealthSourceRangeComparisonTrend? = nil,
        sourceLineComparisonTrend: BodyHealthSourceComparisonTrend? = nil,
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
        self.secondaryDaySeries = secondaryDaySeries
        self.rangeSeries = rangeSeries
        self.basicsTrend = basicsTrend
        self.sleepStageSnapshot = sleepStageSnapshot
        self.sleepScore = sleepScore
        self.sleepVitals = sleepVitals
        self.sleepDuration = sleepDuration
        self.sleepHistory = sleepHistory
        self.recovery = recovery
        self.chartStyle = chartStyle
        self.highlightedRange = highlightedRange
        self.highlightedRangeResolver = highlightedRangeResolver
        self.valueFormatter = valueFormatter
        self.secondaryValueFormatter = secondaryValueFormatter
        self.sourceComparisonTrend = sourceComparisonTrend
        self.sourceRangeComparisonTrend = sourceRangeComparisonTrend
        self.sourceLineComparisonTrend = sourceLineComparisonTrend
        self.headerMetrics = headerMetrics
        self.headerSecondaryText = headerSecondaryText
        self.helpText = helpText ?? kind.detailHelpText
        self.dataSourceText = dataSourceText
    }
}

enum BodyDateSliderTileLabel {
    private static let recentWeekDayCount = 7

    static func primaryText(
        for date: Date,
        today: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> String {
        let dayStart = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        let oldestRecentDay = calendar.date(
            byAdding: .day,
            value: -(recentWeekDayCount - 1),
            to: todayStart
        ) ?? todayStart

        if dayStart >= oldestRecentDay {
            return dayStart.formatted(.dateTime.weekday(.abbreviated))
        }

        return dayStart.formatted(.dateTime.month(.abbreviated))
    }
}

private enum BodyMetricDetailDatePicker {
    case sleep
    case metric
}

private struct BodyHealthMetricDetailView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: BodyHealthMetricDetailModel
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true
    @State private var selectedTrendRange: BodyHealthTrendRange
    @State private var selectedSleepDate: Date?
    @State private var selectedMetricDate: Date?
    @State private var selectedSleepScoreDetails: SleepScoreDetailsSelection?
    @State private var showsDataSourcePicker = false
    @State private var isPullRefreshing = false
    @State private var activeRecoveryTrendValue: Double?

    init(
        model: BodyHealthMetricDetailModel,
        initialTrendRange: BodyHealthTrendRange = BodyHealthTrendRange.defaultValue
    ) {
        self.model = model
        _selectedTrendRange = State(initialValue: initialTrendRange)
    }

    private var dayChartTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                if isSleepDetail {
                    BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                    trendCard
                    sleepDatePicker
                    selectedSleepCards
                    if showSleepScore {
                        aboutSleepScoreCard
                    }
                    dataSourceFooter
                } else {
                    BodyHealthTrendRangeSelector(selectedRange: $selectedTrendRange)
                    if isBasicsDetail {
                        basicsRangeCard
                    }
                    trendCard
                    if model.kind == .recovery, let recovery = model.recovery {
                        recoveryWhyCard(for: recovery, activeStatus: activeRecoveryStatus)
                    }
                    if isBasicsDetail {
                        bodyMassIndexTrendCard
                    }
                    if model.kind == .wristTemperature {
                        wristTemperatureBaselineCard
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
        .refreshable {
            let started = Date()
            isPullRefreshing = true
            await workoutStore.refreshHealthMetric(model.kind)
            await workoutStore.awaitRefreshCompletion(minimumDurationFrom: started)
            isPullRefreshing = false
        }
        .task {
            await workoutStore.loadIntradayMetricSamplesIfNeeded(model.kind)
        }
        .bodyPullToRefreshLoadingOverlay(isPresented: isPullRefreshing)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSleepScoreDetails) { selection in
            SleepScoreDetailsSheet(selection: selection, accentColor: model.symbolColor)
                .presentationDetents([.height(BodySleepScoreDetailsSheetLayout.sheetHeight), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(isPresented: $showsDataSourcePicker) {
            BodyHealthDataSourcePickerSheet(kind: model.kind, accentColor: model.symbolColor)
                .environmentObject(workoutStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(.systemGroupedBackground))
        }
    }

    private var selectedTemperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.TemperatureUnitPreference.storedValue(from: selectedTemperatureUnitRawValue)
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
        case .heartRate,
             .restingHeartRate,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation:
            return true
        case .recovery,
             .sleep,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .activeEnergy,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
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

    private var activeRecoveryStatus: RecoveryStatus? {
        guard model.kind == .recovery else {
            return nil
        }

        if let activeRecoveryTrendValue, activeRecoveryTrendValue.isFinite {
            return RecoveryStatus.status(for: Int(activeRecoveryTrendValue.rounded()))
        }

        return model.recovery?.status
    }

    private var recentDatePickerDates: [Date] {
        SleepHistorySnapshot.datePickerDates(dayCount: BodyHealthTrendRange.recentMonth.dayCount, futureDayCount: 1)
    }

    private var selectedMetricDaySeries: HealthTrendSeries {
        liveDaySeries.points(on: selectedMetricDay)
    }

    private var selectedMetricSecondaryDaySeries: HealthTrendSeries {
        guard model.kind.usesSourceComparisonDayLineChart else {
            return .empty
        }

        return liveSecondaryDaySeries.points(on: selectedMetricDay)
    }

    private var liveDaySeries: HealthTrendSeries {
        let storeSeries = workoutStore.healthTrends.daySeries(for: model.kind)
        return storeSeries.points.isEmpty ? model.daySeries : storeSeries
    }

    private var liveSecondaryDaySeries: HealthTrendSeries {
        let storeSeries = workoutStore.healthTrends.secondaryDaySeries(for: model.kind)
        return storeSeries.points.isEmpty ? model.secondaryDaySeries : storeSeries
    }

    private var selectedSleepSummary: SleepSummary? {
        sleepSummary(for: selectedSleepDay)
    }

    private var selectedSleepScore: SleepScoreSummary? {
        guard showSleepScore, let summary = selectedSleepSummary else {
            return nil
        }

        return SleepScoreSummary(
            sleep: summary,
            idealSleepDuration: BodySleepDurationGoal.duration(from: sleepDurationGoalMinutes),
            recentSleepHistory: model.sleepHistory,
            on: selectedSleepDay
        )
    }

    private var currentSleepSummary: SleepSummary? {
        currentSleepSummary(for: selectedSleepDay)
    }

    private func sleepSummary(for day: Date) -> SleepSummary? {
        model.sleepHistory.summary(
            on: day,
            currentDaySummary: currentSleepSummary(for: day),
            calendar: Calendar.bodyGregorian
        )
    }

    private func currentSleepSummary(for day: Date) -> SleepSummary? {
        let stageSnapshot = model.sleepStageSnapshot ?? SleepStageSnapshot(date: day, segments: [])
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
        if showSleepScore {
            if let sleepScore = selectedSleepScore {
                sleepScoreCard(sleepScore)
            } else {
                unavailableSleepScoreCard
            }
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

    private func recoveryWhyCard(for recovery: RecoverySummary, activeStatus: RecoveryStatus?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About your score")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(RecoveryStatus.displayOrder, id: \.self) { status in
                    recoveryStatusExplanationRow(
                        status: status,
                        isCurrent: activeStatus == status
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func recoveryStatusExplanationRow(status: RecoveryStatus, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(BodyRecoveryStatusPresentation.color(for: status))
                .frame(width: 4)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(status.title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(status.scoreRangeText)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyRecoveryStatusPresentation.color(for: status))

                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BodyRecoveryStatusPresentation.color(for: status))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                BodyRecoveryStatusPresentation.color(for: status)
                                    .opacity(0.14),
                                in: Capsule()
                            )
                    }
                }

                Text(status.explanation)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var dataSourceFooter: some View {
        if let dataSourceText = model.dataSourceText {
            Button {
                if model.kind.supportsHealthDataSourceSelection {
                    showsDataSourcePicker = true
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(model.symbolColor)

                    Text(dataSourceFooterText(defaultText: dataSourceText.sourceText))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if model.kind.supportsHealthDataSourceSelection {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.kind.supportsHealthDataSourceSelection)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
    }

    private func dataSourceFooterText(defaultText: String) -> String {
        guard model.kind.supportsHealthDataSourceSelection else {
            return defaultText
        }

        let primaryName = workoutStore.selectedHealthDataSourceOption(for: model.kind).name
        guard model.kind.supportsSecondaryHealthDataSourceSelection else {
            return primaryName
        }

        let secondaryOption = workoutStore.selectedSecondaryHealthDataSourceOption(for: model.kind)
        guard !secondaryOption.isNoComparison else {
            return primaryName
        }

        return "\(primaryName) vs \(secondaryOption.name)"
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
            BodyAnimatedMetricValueText(
                value: display.value,
                fontSize: 30,
                color: .primary,
                minimumScaleFactor: 0.6
            )

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
                } else if let sourceComparisonTrend = model.sourceComparisonTrend {
                    BodyHealthSourceLegend(
                        items: comparisonLegendItems(for: sourceComparisonTrend),
                        valueFormatter: model.valueFormatter
                    )
                } else if let sourceRangeComparisonTrend = model.sourceRangeComparisonTrend {
                    BodyHealthSourceLegend(
                        items: rangeComparisonLegendItems(for: sourceRangeComparisonTrend),
                        valueFormatter: model.valueFormatter
                    )
                } else if let sourceLineComparisonTrend = model.sourceLineComparisonTrend {
                    BodyHealthSourceLegend(
                        items: comparisonLegendItems(for: sourceLineComparisonTrend),
                        valueFormatter: model.valueFormatter
                    )
                } else if usesRangeTrendChart, let metricRangeHeaderText {
                    averageHeaderText(metricRangeHeaderText, prefix: "Range")
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
            } else if let sourceRangeComparisonTrend = model.sourceRangeComparisonTrend,
                      model.kind.usesSourceComparisonRangeBandLineChart {
                BodyHeartRateRangeTrendChart(
                    title: model.title,
                    selectedRange: selectedTrendRange,
                    rangeSeries: sourceRangeComparisonTrend.primary.series,
                    secondaryRangeSeries: sourceRangeComparisonTrend.secondary.series,
                    primarySourceName: sourceRangeComparisonTrend.primary.sourceName,
                    secondarySourceName: sourceRangeComparisonTrend.secondary.sourceName,
                    symbolColor: model.symbolColor,
                    secondaryColor: sourceComparisonSecondaryColor,
                    valueFormatter: model.valueFormatter,
                    showsAverageLineOverlay: true,
                    yDomain: metricRangeYDomain
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            } else if let sourceRangeComparisonTrend = model.sourceRangeComparisonTrend {
                BodyHealthSourceComparisonRangeChart(
                    title: model.title,
                    comparison: sourceRangeComparisonTrend,
                    selectedRange: selectedTrendRange,
                    primaryColor: model.symbolColor,
                    secondaryColor: sourceComparisonSecondaryColor,
                    valueFormatter: model.valueFormatter,
                    yDomain: metricRangeYDomain,
                    chartIdentity: "\(model.kind.rawValue)-source-range-comparison-\(selectedTrendRange.rawValue)"
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            } else if usesRangeTrendChart, let visibleMetricRangeSeries {
                BodyHeartRateRangeTrendChart(
                    title: model.title,
                    selectedRange: selectedTrendRange,
                    rangeSeries: visibleMetricRangeSeries,
                    symbolColor: model.symbolColor,
                    valueFormatter: model.valueFormatter,
                    showsAverageLineOverlay: model.kind == .heartRate || model.kind == .heartRateVariability,
                    yDomain: metricRangeYDomain
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            } else if let sourceComparisonTrend = model.sourceComparisonTrend {
                BodyHealthSourceComparisonBarChart(
                    title: model.title,
                    comparison: sourceComparisonTrend,
                    selectedRange: selectedTrendRange,
                    primaryColor: model.symbolColor,
                    secondaryColor: sourceComparisonSecondaryColor,
                    valueFormatter: model.valueFormatter,
                    chartIdentity: "\(model.kind.rawValue)-source-comparison-\(selectedTrendRange.rawValue)"
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            } else if let sourceLineComparisonTrend = model.sourceLineComparisonTrend {
                BodyHealthSourceComparisonLineChart(
                    title: model.title,
                    comparison: sourceLineComparisonTrend,
                    selectedRange: selectedTrendRange,
                    primaryColor: model.symbolColor,
                    secondaryColor: sourceComparisonSecondaryColor,
                    valueFormatter: model.valueFormatter,
                    isSleepDetail: isSleepDetail,
                    chartIdentity: "\(model.kind.rawValue)-source-line-comparison-\(selectedTrendRange.rawValue)"
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
            } else {
                BodyHealthMetricTrendChart(
                    title: model.title,
                    chartStyle: model.chartStyle,
                    symbolColor: model.symbolColor,
                    selectedRange: selectedTrendRange,
                    series: model.series,
                    valueFormatter: model.valueFormatter,
                    highlightedRange: model.highlightedRange,
                    highlightedRangeResolver: model.highlightedRangeResolver,
                    activeHighlightedValue: model.kind == .recovery ? $activeRecoveryTrendValue : nil,
                    isSleepDetail: isSleepDetail,
                    chartIdentity: "\(model.kind.rawValue)-\(selectedTrendRange.rawValue)"
                )
                .frame(height: BodyHealthDetailChartLayout.standardHeight)

                if model.kind == .trainingLoad {
                    BodyTrainingLoadIntervalBreakdownChart(
                        series: model.series,
                        selectedRange: selectedTrendRange
                    )
                    .padding(.top, 4)
                }

                if model.kind == .recovery {
                    BodyRecoveryStatusBreakdownChart(
                        series: model.series,
                        selectedRange: selectedTrendRange
                    )
                    .padding(.top, 4)
                }
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
                            BodyAnimatedMetricValueText(
                                value: metric.value,
                                fontSize: 24,
                                color: .primary,
                                minimumScaleFactor: 0.65
                            )
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

    private var wristTemperatureBaselineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Variation From Baseline")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            BodyWristTemperatureBaselineChart(
                series: workoutStore.healthTrends.wristTemperature,
                selectedRange: selectedTrendRange,
                symbolColor: model.symbolColor
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
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day View")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if !dayComparisonLegendItems.isEmpty {
                    BodyHealthSourceLegend(
                        items: dayComparisonLegendItems,
                        valueFormatter: model.valueFormatter
                    )
                }
            }

            if selectedMetricDaySeries.isEmpty && selectedMetricSecondaryDaySeries.isEmpty {
                Text("No data for this day")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: BodyHealthDetailChartLayout.dayChartHeight)
            } else {
                BodyHealthMetricDayChart(
                    series: selectedMetricDaySeries,
                    secondarySeries: selectedMetricSecondaryDaySeries,
                    day: selectedMetricDay,
                    title: model.title,
                    color: model.symbolColor,
                    secondaryColor: sourceComparisonSecondaryColor,
                    primarySourceName: workoutStore.selectedHealthDataSourceOption(for: model.kind).name,
                    secondarySourceName: workoutStore.selectedSecondaryHealthDataSourceOption(for: model.kind).name,
                    valueFormatter: model.valueFormatter,
                    contextIntervals: selectedMetricDayContextIntervals
                )
                .frame(height: BodyHealthDetailChartLayout.dayChartHeight)
                .id(selectedMetricDay)
                .transition(dayChartTransition)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private var selectedMetricDayContextIntervals: [BodyHealthMetricDayContextInterval] {
        guard model.kind == .heartRate || model.kind == .heartRateVariability else {
            return []
        }

        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: selectedMetricDay)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        let dayInterval = DateInterval(start: dayStart, end: nextDayStart)
        var intervals: [BodyHealthMetricDayContextInterval] = []

        if let sleepInterval = sleepSummary(for: selectedMetricDay)?.stageSnapshot.dateInterval,
           let clippedSleepInterval = sleepInterval.clamped(to: dayInterval) {
            intervals.append(
                BodyHealthMetricDayContextInterval(
                    kind: .sleep,
                    startDate: clippedSleepInterval.start,
                    endDate: clippedSleepInterval.end,
                    title: "Sleep",
                    symbolName: "bed.double.fill",
                    color: Color(red: 0.20, green: 0.72, blue: 1.00)
                )
            )
        }

        intervals.append(contentsOf: workouts(on: dayInterval).map { workout in
            let workoutEndDate = workout.startDate.addingTimeInterval(workout.duration)
            let clippedInterval = DateInterval(start: workout.startDate, end: workoutEndDate)
                .clamped(to: dayInterval)
            return clippedInterval.map {
                BodyHealthMetricDayContextInterval(
                    kind: .workout,
                    startDate: $0.start,
                    endDate: $0.end,
                    title: workout.type.displayName,
                    symbolName: workout.type.symbolName,
                    color: workout.type.color
                )
            }
        }.compactMap { $0 })

        return intervals.sorted { $0.startDate < $1.startDate }
    }

    private func workouts(on dayInterval: DateInterval) -> [WorkoutSummary] {
        var workoutsByID: [UUID: WorkoutSummary] = [:]
        for snapshot in workoutStore.monthSnapshots.values {
            for workout in snapshot.days.flatMap(\.workouts) {
                workoutsByID[workout.id] = workout
            }
        }

        return workoutsByID.values.filter { workout in
            let workoutEndDate = workout.startDate.addingTimeInterval(workout.duration)
            return workout.startDate < dayInterval.end && workoutEndDate > dayInterval.start
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func dateTile(for date: Date, picker: BodyMetricDetailDatePicker) -> some View {
        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let isSelected = calendar.isDate(dayStart, inSameDayAs: selectedDay(for: picker))
        let isFuture = dayStart > today
        let primaryText = BodyDateSliderTileLabel.primaryText(for: dayStart, today: today, calendar: calendar)

        return Button {
            guard !isFuture else {
                return
            }

            selectDate(dayStart, for: picker)
        } label: {
            VStack(spacing: 6) {
                Text(primaryText)
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
                        BodyAnimatedMetricValueText(
                            value: "\(score.total)",
                            fontSize: 44,
                            color: .primary,
                            minimumScaleFactor: 0.64
                        )

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
                    .transition(dayChartTransition)
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

            Text("Body scores each night from the data available for that sleep window: amount, continuity, start time consistency, deep and REM share, pressure from sleep HRV, sleep vitals, and wrist temperature. Missing sensors are skipped instead of counted as zero.")
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
                temperatureUnitPreference: selectedTemperatureUnitPreference
            )
            rows.append(SleepVitalDisplayRow(
                title: "Wrist Temperature",
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

    private var visibleBasicsTrend: BasicsTrendSummary? {
        model.basicsTrend?.limited(to: selectedTrendRange)
    }

    private var visibleMetricRangeSeries: HealthTrendRangeSeries? {
        model.rangeSeries?.limited(to: selectedTrendRange)
    }

    private var usesRangeTrendChart: Bool {
        model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .oxygenSaturation || model.kind == .respiratoryRate
    }

    private var metricRangeYDomain: (([Double]) -> ClosedRange<Double>)? {
        switch model.kind {
        case .oxygenSaturation:
            return BodyHealthMetricRangeYDomain.bloodOxygen
        case .respiratoryRate:
            return BodyHealthMetricRangeYDomain.respiratoryRate
        default:
            return nil
        }
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

    private var sourceComparisonSecondaryColor: Color {
        Color(red: 0.58, green: 0.36, blue: 0.98)
    }

    private func comparisonLegendItems(
        for comparison: BodyHealthSourceComparisonTrend
    ) -> [BodyHealthSourceLegendItem] {
        [
            BodyHealthSourceLegendItem(
                role: .primary,
                sourceName: comparison.primary.sourceName,
                averageValue: comparison.primary.averageValue(in: selectedTrendRange),
                color: model.symbolColor
            ),
            BodyHealthSourceLegendItem(
                role: .secondary,
                sourceName: comparison.secondary.sourceName,
                averageValue: comparison.secondary.averageValue(in: selectedTrendRange),
                color: sourceComparisonSecondaryColor
            )
        ]
    }

    private func rangeComparisonLegendItems(
        for comparison: BodyHealthSourceRangeComparisonTrend
    ) -> [BodyHealthSourceLegendItem] {
        [
            BodyHealthSourceLegendItem(
                role: .primary,
                sourceName: comparison.primary.sourceName,
                averageValue: comparison.primary.averageValue(in: selectedTrendRange),
                color: model.symbolColor
            ),
            BodyHealthSourceLegendItem(
                role: .secondary,
                sourceName: comparison.secondary.sourceName,
                averageValue: comparison.secondary.averageValue(in: selectedTrendRange),
                color: sourceComparisonSecondaryColor
            )
        ]
    }

    private var dayComparisonLegendItems: [BodyHealthSourceLegendItem] {
        var items: [BodyHealthSourceLegendItem] = []
        if !selectedMetricDaySeries.isEmpty {
            items.append(
                BodyHealthSourceLegendItem(
                    role: .primary,
                    sourceName: workoutStore.selectedHealthDataSourceOption(for: model.kind).name,
                    averageValue: selectedMetricDaySeries.hourlyAverage(on: selectedMetricDay),
                    color: model.symbolColor
                )
            )
        }
        if !selectedMetricSecondaryDaySeries.isEmpty {
            items.append(
                BodyHealthSourceLegendItem(
                    role: .secondary,
                    sourceName: workoutStore.selectedSecondaryHealthDataSourceOption(for: model.kind).name,
                    averageValue: selectedMetricSecondaryDaySeries.hourlyAverage(on: selectedMetricDay),
                    color: sourceComparisonSecondaryColor
                )
            )
        }
        return items
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

    private var metricRangeHeaderText: String? {
        guard let range = visibleMetricRangeSeries?.valueRange else {
            return nil
        }

        let lower = BodyValueFormat.numberText(range.lowerBound, decimals: 0)
        let upper = BodyValueFormat.numberText(range.upperBound, decimals: 0)
        let suffix = model.unit.isEmpty ? "" : " \(model.unit)"
        return "\(lower)-\(upper)\(suffix)"
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

    private func averageHeaderText(_ text: String, prefix: String = "Avg") -> some View {
        Text("\(prefix) \(text)")
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
    case .startTime:
        return Color(red: 0.10, green: 0.58, blue: 1.00)
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
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: BodyHomeTrendCardPresentation.averageLineStrokeWidth,
                lineCap: .round
            )
        )
    }

    private func plotEntries(in size: CGSize) -> [PlotEntry] {
        let points = presentation.displayCalendarPoints
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

        return entry.index >= presentation.displayRecentStartIndex
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
        presentation.displayCalendarPoints.compactMap(\.value).filter(\.isFinite)
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

private struct BodyHealthDataSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore

    let kind: HealthMetricKind
    let accentColor: Color

    @State private var updatingSelectionID: String?

    private var selectedOption: BodyHealthDataSourceOption {
        workoutStore.selectedHealthDataSourceOption(for: kind)
    }

    private var selectedSecondaryOption: BodyHealthDataSourceOption {
        workoutStore.selectedSecondaryHealthDataSourceOption(for: kind)
    }

    private var options: [BodyHealthDataSourceOption] {
        workoutStore.healthDataSourceOptions(for: kind)
    }

    private var secondaryOptions: [BodyHealthDataSourceOption] {
        workoutStore.secondaryHealthDataSourceOptions(for: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sourceSection(
                        title: "Primary Source",
                        detail: "Used for the summary value and primary chart bars.",
                        options: options,
                        selectedOption: selectedOption,
                        role: "primary"
                    )

                    if kind.supportsSecondaryHealthDataSourceSelection {
                        sourceSection(
                            title: "Secondary Source",
                            detail: "Used for the comparison bars on this chart.",
                            options: secondaryOptions,
                            selectedOption: selectedSecondaryOption,
                            role: "secondary"
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("\(kind.sourcePickerTitle) Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func sourceSection(
        title: String,
        detail: String,
        options: [BodyHealthDataSourceOption],
        selectedOption: BodyHealthDataSourceOption,
        role: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(detail)
                    .font(.system(.footnote, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(options) { option in
                    sourceOptionButton(option, selectedOption: selectedOption, role: role)
                }
            }
        }
    }

    private func sourceOptionButton(
        _ option: BodyHealthDataSourceOption,
        selectedOption: BodyHealthDataSourceOption,
        role: String
    ) -> some View {
        let isSelected = selectedOption.id == option.id
        let updatingID = "\(role)-\(option.id)"
        return Button {
            updateSelection(option, role: role)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 8)

                if updatingSelectionID == updatingID {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(accentColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(updatingSelectionID != nil || isSelected)
    }

    private func updateSelection(_ option: BodyHealthDataSourceOption, role: String) {
        updatingSelectionID = "\(role)-\(option.id)"
        Task {
            if role == "secondary" {
                await workoutStore.updateSecondaryHealthDataSource(for: kind, option: option)
            } else {
                await workoutStore.updateHealthDataSource(for: kind, option: option)
            }
            updatingSelectionID = nil
            dismiss()
        }
    }
}

private struct BodyHealthSourceLegendItem: Identifiable {
    let role: BodyHealthSourceRole
    let sourceName: String
    let averageValue: Double?
    let color: Color

    var id: BodyHealthSourceRole { role }
}

private struct BodyHealthSourceLegend: View {
    let items: [BodyHealthSourceLegendItem]
    let valueFormatter: (Double) -> String

    private var isMultiSource: Bool {
        items.count > 1
    }

    var body: some View {
        if isMultiSource {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 9, height: 9)

                        Text("\(item.sourceName) Avg \(averageText(for: item.averageValue))")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
            }
            .frame(maxWidth: 180, alignment: .leading)
        } else if let item = items.first {
            Text("Avg \(averageText(for: item.averageValue))")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func averageText(for value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return valueFormatter(value)
    }
}

private struct BodyHealthSourceComparisonLineChart: View {
    let title: String
    let comparison: BodyHealthSourceComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let isSleepDetail: Bool
    let chartIdentity: String

    private let entries: [BodyHealthSourceComparisonLineEntry]
    private let finiteEntries: [BodyHealthSourceComparisonLineEntry]
    private let primaryPointsByDate: [Date: BodyHealthSourceComparisonLineEntry]
    private let secondaryPointsByDate: [Date: BodyHealthSourceComparisonLineEntry]
    private let latestPrimaryDate: Date?
    private let latestSecondaryDate: Date?
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        comparison: BodyHealthSourceComparisonTrend,
        selectedRange: BodyHealthTrendRange,
        primaryColor: Color,
        secondaryColor: Color,
        valueFormatter: @escaping (Double) -> String,
        isSleepDetail: Bool,
        chartIdentity: String
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.isSleepDetail = isSleepDetail
        self.chartIdentity = chartIdentity

        let primaryPoints = comparison.primary.series.lineChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.lineChartCalendarPoints(to: selectedRange)
        let primaryEntries = primaryPoints.map {
            BodyHealthSourceComparisonLineEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: $0
            )
        }
        let secondaryEntries = secondaryPoints.map {
            BodyHealthSourceComparisonLineEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: $0
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter { $0.value?.isFinite == true }
        self.primaryPointsByDate = Dictionary(uniqueKeysWithValues: primaryEntries.compactMap { entry in
            entry.value?.isFinite == true ? (entry.date, entry) : nil
        })
        self.secondaryPointsByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.compactMap { entry in
            entry.value?.isFinite == true ? (entry.date, entry) : nil
        })
        self.latestPrimaryDate = primaryEntries.last { $0.value?.isFinite == true }?.date
        self.latestSecondaryDate = secondaryEntries.last { $0.value?.isFinite == true }?.date
        let domainDates = primaryEntries.map(\.date) + secondaryEntries.map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
        self.chartYDomain = BodyHealthMetricTrendChart.computeYDomain(
            from: allEntries.compactMap(\.value).filter(\.isFinite),
            chartStyle: .line
        )
    }

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                if let value = entry.value {
                    LineMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value(title, value),
                        series: .value("Source", entry.sourceRole.rawValue)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(lineStrokeColor(for: entry))
                    .lineStyle(StrokeStyle(lineWidth: lineStrokeWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        if selectedRange.usesPreviewLineChartStyle {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, value)
                            )
                            .symbol {
                                BodyLineChartPreviewPointSymbol(
                                    tintColor: color(for: entry),
                                    isCurrent: isLatestPoint(entry),
                                    pointDiameter: selectedRange.linePointDiameter,
                                    currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                )
                            }
                        } else {
                            PointMark(
                                x: .value("Date", entry.date, unit: .day),
                                y: .value(title, value)
                            )
                            .foregroundStyle(color(for: entry))
                            .symbolSize(28)
                        }
                    }
                }
            }

            if let selectedPoint {
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
                            values: selectedValues(for: selectedPoint.date),
                            date: selectedPoint.date,
                            dateText: bodyChartSelectionDateText(for: selectedPoint.point)
                        )
                    }

                ForEach(selectedValuesEntries(for: selectedPoint.date)) { entry in
                    if let value = entry.value {
                        PointMark(
                            x: .value("Selected Date", entry.date, unit: .day),
                            y: .value(title, value)
                        )
                        .foregroundStyle(color(for: entry))
                        .symbolSize(82)
                    }
                }
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
        .id(chartIdentity)
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedPoint: BodyHealthSourceComparisonLineEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private func selectedValuesEntries(for date: Date) -> [BodyHealthSourceComparisonLineEntry] {
        [primaryPointsByDate[date], secondaryPointsByDate[date]].compactMap { $0 }
    }

    private func selectedValues(for date: Date) -> [BodyChartSelectionValue] {
        selectedValuesEntries(for: date).compactMap { entry in
            guard let value = entry.value else {
                return nil
            }

            return BodyChartSelectionValue(
                title: entry.sourceName,
                value: chartSelectionText(for: value),
                color: color(for: entry)
            )
        }
    }

    private func chartSelectionText(for value: Double) -> String {
        if isSleepDetail {
            return BodyValueFormat.sleepDurationText(for: value * 60 * 60)
        }

        return valueFormatter(value)
    }

    private func isLatestPoint(_ entry: BodyHealthSourceComparisonLineEntry) -> Bool {
        entry.sourceRole == .primary
            ? entry.date == latestPrimaryDate
            : entry.date == latestSecondaryDate
    }

    private func color(for entry: BodyHealthSourceComparisonLineEntry) -> Color {
        entry.sourceRole == .primary ? primaryColor : secondaryColor
    }

    private func lineStrokeColor(for entry: BodyHealthSourceComparisonLineEntry) -> Color {
        selectedRange.usesMetricColorLineStroke ? color(for: entry) : color(for: entry).opacity(0.72)
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
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

private struct BodyHealthSourceComparisonLineEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendCalendarPoint

    var id: String {
        "\(sourceRole.rawValue)-\(point.date.timeIntervalSinceReferenceDate)"
    }

    var date: Date {
        point.date
    }

    var value: Double? {
        point.value
    }
}

private struct BodyHealthSourceComparisonBarChart: View {
    let title: String
    let comparison: BodyHealthSourceComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let chartIdentity: String

    private let entries: [BodyHealthSourceComparisonBarEntry]
    private let finiteEntries: [BodyHealthSourceComparisonBarEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        comparison: BodyHealthSourceComparisonTrend,
        selectedRange: BodyHealthTrendRange,
        primaryColor: Color,
        secondaryColor: Color,
        valueFormatter: @escaping (Double) -> String,
        chartIdentity: String
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.chartIdentity = chartIdentity

        let primaryPoints = comparison.primary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let dateOffset = selectedRange.sourceComparisonChartDateOffset
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(-dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonBarEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(dateOffset)
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter { $0.value?.isFinite == true }

        let domainDates = allEntries.map(\.chartDate)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
        self.chartYDomain = BodyHealthMetricTrendChart.computeYDomain(
            from: finiteEntries.compactMap(\.value),
            chartStyle: .bar
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.sourceComparisonChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(entries) { entry in
                    if let value = entry.value {
                        BarMark(
                            x: .value("Date", entry.chartDate),
                            y: .value(title, value),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(color(for: entry).gradient)
                        .cornerRadius(4)
                    }
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            BodyChartSelectionAnnotation(
                                eyebrow: selectedRange.sourceComparisonChartAggregationDayCount > 1 ? "AVG" : "TOTAL",
                                values: selectedValues(for: selectedPoint),
                                date: selectedPoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedPoint.point)
                            )
                        }
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
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var selectedPoint: BodyHealthSourceComparisonBarEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.chartDate.timeIntervalSince(selectedDate)) < abs(second.chartDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectedValues(for selectedPoint: BodyHealthSourceComparisonBarEntry) -> [BodyChartSelectionValue] {
        entries
            .filter { $0.date == selectedPoint.date && $0.value?.isFinite == true }
            .sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }
            .compactMap { entry -> BodyChartSelectionValue? in
                guard let value = entry.value else {
                    return nil
                }

                return BodyChartSelectionValue(
                    title: entry.sourceName,
                    value: valueFormatter(value),
                    color: color(for: entry)
                )
            }
    }

    private func color(for entry: BodyHealthSourceComparisonBarEntry) -> Color {
        entry.sourceRole == .primary ? primaryColor : secondaryColor
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

private struct BodyHealthSourceComparisonBarEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendCalendarPoint
    let chartDate: Date

    var id: String {
        "\(sourceRole.rawValue)-\(point.date.timeIntervalSinceReferenceDate)"
    }

    var date: Date {
        point.date
    }

    var value: Double? {
        point.value
    }
}

private struct BodyHealthSourceComparisonRangeChart: View {
    let title: String
    let comparison: BodyHealthSourceRangeComparisonTrend
    let selectedRange: BodyHealthTrendRange
    let primaryColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let chartIdentity: String

    private let entries: [BodyHealthSourceComparisonRangeEntry]
    private let finiteEntries: [BodyHealthSourceComparisonRangeEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        comparison: BodyHealthSourceRangeComparisonTrend,
        selectedRange: BodyHealthTrendRange,
        primaryColor: Color,
        secondaryColor: Color,
        valueFormatter: @escaping (Double) -> String,
        yDomain: (([Double]) -> ClosedRange<Double>)? = nil,
        chartIdentity: String
    ) {
        self.title = title
        self.comparison = comparison
        self.selectedRange = selectedRange
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.chartIdentity = chartIdentity

        let primaryPoints = comparison.primary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let secondaryPoints = comparison.secondary.series.sourceComparisonChartCalendarPoints(to: selectedRange)
        let dateOffset = selectedRange.sourceComparisonChartDateOffset
        let primaryEntries = primaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.primary.sourceName,
                sourceRole: .primary,
                point: point,
                chartDate: point.date.addingTimeInterval(-dateOffset)
            )
        }
        let secondaryEntries = secondaryPoints.map { point in
            BodyHealthSourceComparisonRangeEntry(
                sourceName: comparison.secondary.sourceName,
                sourceRole: .secondary,
                point: point,
                chartDate: point.date.addingTimeInterval(dateOffset)
            )
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter(\.hasValue)

        let domainDates = allEntries.map(\.chartDate)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
        let domainValues = allEntries.flatMap { entry -> [Double] in
            guard let low = entry.lowValue, let high = entry.highValue else {
                return []
            }

            return [low, high]
        }
        self.chartYDomain = yDomain?(domainValues) ?? Self.computeYDomain(from: domainValues)
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.sourceComparisonRangeChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(entries) { entry in
                    if let lowValue = entry.lowValue, let highValue = entry.highValue {
                        BarMark(
                            x: .value("Date", entry.chartDate),
                            yStart: .value("Low \(title)", lowValue),
                            yEnd: .value("High \(title)", highValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(color(for: entry).gradient)
                        .cornerRadius(chartBarWidth / 2)
                    }
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected Date", selectedPoint.chartDate))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            BodyChartSelectionAnnotation(
                                eyebrow: "RANGE",
                                values: selectedValues(for: selectedPoint),
                                date: selectedPoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedPoint.point)
                            )
                        }
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
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private var selectedPoint: BodyHealthSourceComparisonRangeEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.chartDate.timeIntervalSince(selectedDate)) < abs(second.chartDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectedValues(for selectedPoint: BodyHealthSourceComparisonRangeEntry) -> [BodyChartSelectionValue] {
        entries
            .filter { $0.date == selectedPoint.date && $0.hasValue }
            .sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }
            .compactMap { entry -> BodyChartSelectionValue? in
                guard let lowValue = entry.lowValue,
                      let highValue = entry.highValue else {
                    return nil
                }

                return BodyChartSelectionValue(
                    title: entry.sourceName,
                    value: "\(valueFormatter(lowValue))-\(valueFormatter(highValue))",
                    color: color(for: entry)
                )
            }
    }

    private func color(for entry: BodyHealthSourceComparisonRangeEntry) -> Color {
        entry.sourceRole == .primary ? primaryColor : secondaryColor
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

    private static func computeYDomain(from values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let maximum = finiteValues.max() else {
            return 0...200
        }

        let upper = max(ceil((maximum + max(maximum * 0.12, 10)) / 10) * 10, 120)
        return 0...upper
    }
}

private struct BodyHealthSourceComparisonRangeEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let point: HealthTrendRangeCalendarPoint
    let chartDate: Date

    var id: String {
        "\(sourceRole.rawValue)-\(point.date.timeIntervalSinceReferenceDate)"
    }

    var date: Date {
        point.date
    }

    var lowValue: Double? {
        point.lowValue
    }

    var highValue: Double? {
        point.highValue
    }

    var hasValue: Bool {
        point.hasValue
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

private extension DateInterval {
    func clamped(to boundary: DateInterval) -> DateInterval? {
        let clampedStart = max(start, boundary.start)
        let clampedEnd = min(end, boundary.end)
        guard clampedEnd > clampedStart else {
            return nil
        }

        return DateInterval(start: clampedStart, end: clampedEnd)
    }
}

private struct BodyHealthMetricDayContextInterval: Identifiable {
    enum Kind {
        case sleep
        case workout
    }

    let kind: Kind
    let startDate: Date
    let endDate: Date
    let title: String
    let symbolName: String
    let color: Color

    var id: String {
        "\(kind)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)-\(title)"
    }

    var midpointDate: Date {
        startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2)
    }
}

private extension HealthTrendSeries {
    func hourlyAverage(on day: Date) -> Double? {
        let values = hourlyAverageBuckets(on: day).map(\.averageValue).filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct BodyHealthMetricDayChart: View {
    let day: Date
    let title: String
    let color: Color
    let secondaryColor: Color
    let primarySourceName: String
    let secondarySourceName: String
    let valueFormatter: (Double) -> String
    let contextIntervals: [BodyHealthMetricDayContextInterval]

    private let hourlyBuckets: [HealthTrendHourlyBucket]
    private let secondaryHourlyBuckets: [HealthTrendHourlyBucket]
    private let entries: [BodyHealthMetricDayChartEntry]
    private let finiteEntries: [BodyHealthMetricDayChartEntry]
    private let primaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let secondaryEntriesByDate: [Date: BodyHealthMetricDayChartEntry]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestBucketDate: Date?
    private let latestSecondaryBucketDate: Date?

    private static let pointDiameter: CGFloat = 8
    private static let currentPointDiameter: CGFloat = 10

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false

    init(
        series: HealthTrendSeries,
        secondarySeries: HealthTrendSeries = .empty,
        day: Date,
        title: String,
        color: Color,
        secondaryColor: Color = Color(red: 0.58, green: 0.36, blue: 0.98),
        primarySourceName: String = "Primary",
        secondarySourceName: String = "Secondary",
        valueFormatter: @escaping (Double) -> String,
        contextIntervals: [BodyHealthMetricDayContextInterval] = []
    ) {
        self.day = day
        self.title = title
        self.color = color
        self.secondaryColor = secondaryColor
        self.primarySourceName = primarySourceName
        self.secondarySourceName = secondarySourceName
        self.valueFormatter = valueFormatter
        self.contextIntervals = contextIntervals

        let buckets = series.hourlyAverageBuckets(on: day)
        let secondaryBuckets = secondarySeries.hourlyAverageBuckets(on: day)
        self.hourlyBuckets = buckets
        self.secondaryHourlyBuckets = secondaryBuckets
        self.latestBucketDate = buckets.last?.plotDate
        self.latestSecondaryBucketDate = secondaryBuckets.last?.plotDate
        let primaryEntries = buckets.map {
            BodyHealthMetricDayChartEntry(sourceName: primarySourceName, sourceRole: .primary, bucket: $0)
        }
        let secondaryEntries = secondaryBuckets.map {
            BodyHealthMetricDayChartEntry(sourceName: secondarySourceName, sourceRole: .secondary, bucket: $0)
        }
        let allEntries = primaryEntries + secondaryEntries
        self.entries = allEntries
        self.finiteEntries = allEntries.filter { $0.averageValue.isFinite }
        self.primaryEntriesByDate = Dictionary(uniqueKeysWithValues: primaryEntries.map { ($0.plotDate, $0) })
        self.secondaryEntriesByDate = Dictionary(uniqueKeysWithValues: secondaryEntries.map { ($0.plotDate, $0) })
        self.chartYDomain = Self.computeYDomain(from: buckets + secondaryBuckets)

        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: day)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        self.chartXDomain = dayStart...nextDayStart
    }

    var body: some View {
        Chart {
            ForEach(contextIntervals) { interval in
                RectangleMark(
                    xStart: .value("\(interval.title) Start", interval.startDate),
                    xEnd: .value("\(interval.title) End", interval.endDate),
                    yStart: .value("Context Minimum", chartYDomain.lowerBound),
                    yEnd: .value("Context Maximum", chartYDomain.upperBound)
                )
                .foregroundStyle(interval.color.opacity(interval.kind == .sleep ? 0.14 : 0.10))

                RectangleMark(
                    xStart: .value("\(interval.title) Top Start", interval.startDate),
                    xEnd: .value("\(interval.title) Top End", interval.endDate),
                    yStart: .value("Context Top Start", contextTopLineLowerBound),
                    yEnd: .value("Context Top End", chartYDomain.upperBound)
                )
                .foregroundStyle(interval.color)

                PointMark(
                    x: .value("\(interval.title) Label", interval.midpointDate),
                    y: .value("Context Label", chartYDomain.upperBound)
                )
                .foregroundStyle(Color.clear)
                .annotation(position: .top, spacing: 3, overflowResolution: bodyChartSelectionOverflowResolution) {
                    Image(systemName: interval.symbolName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(interval.color)
                        .accessibilityHidden(true)
                }
            }

            ForEach(entries) { entry in
                LineMark(
                    x: .value("Time", entry.plotDate),
                    y: .value(title, entry.averageValue),
                    series: .value("Source", entry.sourceRole.rawValue)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: entry))
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Time", entry.plotDate),
                    y: .value(title, entry.averageValue)
                )
                .symbol {
                    BodyLineChartPreviewPointSymbol(
                        tintColor: color(for: entry),
                        isCurrent: isLatestEntry(entry),
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
                            bucket: selectedBucket.bucket,
                            values: selectedValues(for: selectedBucket.plotDate),
                            valueFormatter: valueFormatter
                        )
                    }

                ForEach(selectedEntries(for: selectedBucket.plotDate)) { entry in
                    PointMark(
                        x: .value("Selected Time", entry.plotDate),
                        y: .value(title, entry.averageValue)
                    )
                    .foregroundStyle(color(for: entry))
                    .symbolSize(82)
                }
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

    private var selectedBucket: BodyHealthMetricDayChartEntry? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteEntries.min { first, second in
            abs(first.plotDate.timeIntervalSince(selectedDate)) < abs(second.plotDate.timeIntervalSince(selectedDate))
        }
    }

    private func selectedEntries(for date: Date) -> [BodyHealthMetricDayChartEntry] {
        [primaryEntriesByDate[date], secondaryEntriesByDate[date]].compactMap { $0 }
    }

    private func selectedValues(for date: Date) -> [BodyChartSelectionValue] {
        selectedEntries(for: date).map { entry in
            BodyChartSelectionValue(
                title: entry.sourceName,
                value: valueFormatter(entry.averageValue),
                color: color(for: entry)
            )
        }
    }

    private func isLatestEntry(_ entry: BodyHealthMetricDayChartEntry) -> Bool {
        entry.sourceRole == .primary
            ? entry.plotDate == latestBucketDate
            : entry.plotDate == latestSecondaryBucketDate
    }

    private func color(for entry: BodyHealthMetricDayChartEntry) -> Color {
        entry.sourceRole == .primary ? color : secondaryColor
    }

    private var contextTopLineLowerBound: Double {
        let span = chartYDomain.upperBound - chartYDomain.lowerBound
        return chartYDomain.upperBound - max(span * 0.006, 0.5)
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

    private static func computeYDomain(from buckets: [HealthTrendHourlyBucket]) -> ClosedRange<Double> {
        let values = buckets.map(\.averageValue).filter(\.isFinite)
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
}

private struct BodyHealthMetricDayChartEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let bucket: HealthTrendHourlyBucket

    var id: String {
        "\(sourceRole.rawValue)-\(bucket.id)"
    }

    var plotDate: Date {
        bucket.plotDate
    }

    var averageValue: Double {
        bucket.averageValue
    }
}

private struct BodyHealthMetricDayAnnotation: View {
    let bucket: HealthTrendHourlyBucket
    let values: [BodyChartSelectionValue]
    let valueFormatter: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOURLY AVG")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(.secondary)

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
                .font(.system(size: values.count == 1 ? 20 : 16, weight: .bold, design: .rounded))
            }

            Text(hourRangeText)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if !sampleWindows.isEmpty {
                Divider()
                    .padding(.vertical, 1)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sampleWindows) { window in
                        HStack(spacing: 10) {
                            Text(windowRangeText(for: window))
                                .foregroundColor(.secondary)

                            Text(valueFormatter(window.averageValue))
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

    private var sampleWindows: [HealthTrendHourlySampleWindow] {
        bucket.sampleWindows()
    }

    private var hourRangeText: String {
        let hourEnd = bucket.hourStart.addingTimeInterval(60 * 60)
        return "\(timeText(for: bucket.hourStart))-\(timeText(for: hourEnd))"
    }

    private func windowRangeText(for window: HealthTrendHourlySampleWindow) -> String {
        "\(timeText(for: window.startDate))-\(timeText(for: window.endDate))"
    }

    private func timeText(for date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

private struct BodyBasicsBodyMassIndexTrendChart: View {
    let selectedRange: BodyHealthTrendRange
    let color: Color
    let valueFormatter: (Double) -> String

    private let calendarPoints: [HealthTrendCalendarPoint]
    private let finitePoints: [HealthTrendCalendarPoint]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestCalendarDate: Date?

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        series: HealthTrendSeries,
        selectedRange: BodyHealthTrendRange,
        color: Color,
        valueFormatter: @escaping (Double) -> String
    ) {
        self.selectedRange = selectedRange
        self.color = color
        self.valueFormatter = valueFormatter

        let points = series.lineChartCalendarPoints(to: selectedRange)
        self.calendarPoints = points
        self.finitePoints = points.filter { $0.value?.isFinite == true }
        self.chartYDomain = Self.computeYDomain(from: points)

        let domainDates = series.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)

        self.latestCalendarDate = points.last { $0.value?.isFinite == true }?.date
    }

    var body: some View {
        Chart {
            ForEach(calendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("BMI", value)
                    )
                    .interpolationMethod(.linear)
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
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var selectedPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private func isLatestPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == latestCalendarDate
    }

    private var lineStrokeColor: Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
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

    private static func computeYDomain(from points: [HealthTrendCalendarPoint]) -> ClosedRange<Double> {
        let values = points.compactMap(\.value).filter(\.isFinite)
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
}

private struct BodyHeartRateRangeTrendChart: View {
    let title: String
    let selectedRange: BodyHealthTrendRange
    let symbolColor: Color
    let secondaryColor: Color
    let valueFormatter: (Double) -> String
    let showsAverageLineOverlay: Bool

    private let rangePoints: [HealthTrendRangeCalendarPoint]
    private let secondaryRangePoints: [HealthTrendRangeCalendarPoint]
    private let averageEntries: [BodyHeartRateRangeAverageEntry]
    private let finiteRangePoints: [HealthTrendRangeCalendarPoint]
    private let latestPrimaryAveragePointDate: Date?
    private let latestSecondaryAveragePointDate: Date?
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let primarySourceName: String
    private let secondarySourceName: String?

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        selectedRange: BodyHealthTrendRange,
        rangeSeries: HealthTrendRangeSeries,
        secondaryRangeSeries: HealthTrendRangeSeries? = nil,
        primarySourceName: String = "Primary",
        secondarySourceName: String? = nil,
        symbolColor: Color,
        secondaryColor: Color = Color(red: 0.58, green: 0.36, blue: 0.98),
        valueFormatter: @escaping (Double) -> String,
        showsAverageLineOverlay: Bool = false,
        yDomain: (([Double]) -> ClosedRange<Double>)? = nil
    ) {
        self.title = title
        self.selectedRange = selectedRange
        self.symbolColor = symbolColor
        self.secondaryColor = secondaryColor
        self.valueFormatter = valueFormatter
        self.showsAverageLineOverlay = showsAverageLineOverlay
        self.primarySourceName = primarySourceName
        self.secondarySourceName = secondarySourceName

        let points = rangeSeries.chartCalendarPoints(to: selectedRange)
        let secondaryPoints = secondaryRangeSeries?.chartCalendarPoints(to: selectedRange) ?? []
        self.rangePoints = points
        self.secondaryRangePoints = secondaryPoints
        self.finiteRangePoints = points.filter(\.hasValue)
        self.latestPrimaryAveragePointDate = points.last { point in
            point.averageValue?.isFinite == true
        }?.date
        self.latestSecondaryAveragePointDate = secondaryPoints.last { point in
            point.averageValue?.isFinite == true
        }?.date
        self.averageEntries = Self.averageEntries(
            primaryPoints: points,
            secondaryPoints: secondaryPoints,
            primarySourceName: primarySourceName,
            secondarySourceName: secondarySourceName
        )
        let domainValues = (points + secondaryPoints).flatMap { point -> [Double] in
            guard let low = point.lowValue, let high = point.highValue else {
                return []
            }

            return [low, high]
        }
        self.chartYDomain = yDomain?(domainValues) ?? Self.computeYDomain(from: domainValues)
        let domainDates = rangeSeries.calendarPoints(to: selectedRange).map(\.date)
            + (secondaryRangeSeries?.calendarPoints(to: selectedRange).map(\.date) ?? [])
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.heartRateRangeChartBarWidth(forAvailableWidth: proxy.size.width)

            Chart {
                if let selectedRangePoint {
                    RuleMark(x: .value("Selected Date", selectedRangePoint.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(rangePoints) { point in
                    if let lowValue = point.lowValue, let highValue = point.highValue {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            yStart: .value("Low \(title)", lowValue),
                            yEnd: .value("High \(title)", highValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(rangeBarColor)
                        .cornerRadius(chartBarWidth / 2)
                    }
                }

                averageLineOverlay

                if let selectedRangePoint,
                   let lowValue = selectedRangePoint.lowValue,
                   let highValue = selectedRangePoint.highValue {
                    RuleMark(x: .value("Selected Date", selectedRangePoint.date, unit: .day))
                        .foregroundStyle(Color.clear)
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            BodyChartSelectionAnnotation(
                                eyebrow: "RANGE",
                                values: selectedValues(for: selectedRangePoint, lowValue: lowValue, highValue: highValue),
                                date: selectedRangePoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedRangePoint)
                            )
                        }

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
            .id("heart-rate-range-\(selectedRange.rawValue)")
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    @ChartContentBuilder
    private var averageLineOverlay: some ChartContent {
        if showsAverageLineOverlay {
            ForEach(averageEntries) { entry in
                LineMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Average \(title)", entry.value),
                    series: .value("Source", entry.sourceRole.rawValue)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(color(for: entry))
                .lineStyle(StrokeStyle(lineWidth: BodyLineChartPreviewStyle.lineWidth, lineCap: .round, lineJoin: .round))

                if selectedRange.showsPointMarks {
                    if selectedRange.usesPreviewLineChartStyle {
                        PointMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Average \(title)", entry.value)
                        )
                        .symbol {
                            BodyLineChartPreviewPointSymbol(
                                tintColor: color(for: entry),
                                isCurrent: isLatestAverageEntry(entry),
                                pointDiameter: selectedRange.linePointDiameter,
                                currentPointDiameter: selectedRange.lineCurrentPointDiameter
                            )
                        }
                    } else {
                        PointMark(
                            x: .value("Date", entry.date, unit: .day),
                            y: .value("Average \(title)", entry.value)
                        )
                        .foregroundStyle(color(for: entry))
                        .symbolSize(28)
                    }
                }
            }
        }
    }

    private var selectedRangePoint: HealthTrendRangeCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteRangePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private var rangeBarColor: Color {
        showsAverageLineOverlay ? Color.secondary.opacity(0.24) : symbolColor
    }

    private func selectedValues(
        for point: HealthTrendRangeCalendarPoint,
        lowValue: Double,
        highValue: Double
    ) -> [BodyChartSelectionValue] {
        guard !secondaryRangePoints.isEmpty else {
            return [
                BodyChartSelectionValue(
                    title: nil,
                    value: "\(valueFormatter(lowValue))-\(valueFormatter(highValue))",
                    color: symbolColor
                )
            ]
        }

        var values = [
            BodyChartSelectionValue(
                title: "Range",
                value: "\(valueFormatter(lowValue))-\(valueFormatter(highValue))",
                color: Color.secondary
            )
        ]

        values.append(contentsOf: averageEntries
            .filter { $0.date == point.date }
            .sorted { $0.sourceRole.rawValue < $1.sourceRole.rawValue }
            .map { entry in
                BodyChartSelectionValue(
                    title: entry.sourceName,
                    value: valueFormatter(entry.value),
                    color: color(for: entry)
                )
            })

        return values
    }

    private func isLatestAverageEntry(_ entry: BodyHeartRateRangeAverageEntry) -> Bool {
        entry.sourceRole == .primary
            ? entry.date == latestPrimaryAveragePointDate
            : entry.date == latestSecondaryAveragePointDate
    }

    private func color(for entry: BodyHeartRateRangeAverageEntry) -> Color {
        entry.sourceRole == .primary ? symbolColor : secondaryColor
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

    private static func computeYDomain(from values: [Double]) -> ClosedRange<Double> {
        let finiteValues = values.filter(\.isFinite)
        guard let maximum = finiteValues.max() else {
            return 0...200
        }

        let upper = max(ceil((maximum + max(maximum * 0.12, 10)) / 10) * 10, 120)
        return 0...upper
    }

    private static func averageEntries(
        primaryPoints: [HealthTrendRangeCalendarPoint],
        secondaryPoints: [HealthTrendRangeCalendarPoint],
        primarySourceName: String,
        secondarySourceName: String?
    ) -> [BodyHeartRateRangeAverageEntry] {
        let primaryEntries = primaryPoints.compactMap { point -> BodyHeartRateRangeAverageEntry? in
            guard let value = point.averageValue, value.isFinite else {
                return nil
            }

            return BodyHeartRateRangeAverageEntry(
                sourceName: primarySourceName,
                sourceRole: .primary,
                date: point.date,
                value: value
            )
        }
        let secondaryEntries = secondaryPoints.compactMap { point -> BodyHeartRateRangeAverageEntry? in
            guard let value = point.averageValue, value.isFinite else {
                return nil
            }

            return BodyHeartRateRangeAverageEntry(
                sourceName: secondarySourceName ?? "Secondary",
                sourceRole: .secondary,
                date: point.date,
                value: value
            )
        }

        return primaryEntries + secondaryEntries
    }
}

private struct BodyHeartRateRangeAverageEntry: Identifiable {
    let sourceName: String
    let sourceRole: BodyHealthSourceRole
    let date: Date
    let value: Double

    var id: String {
        "\(sourceRole.rawValue)-\(date.timeIntervalSinceReferenceDate)"
    }
}

private struct BodyHealthMetricTrendChart: View {
    let title: String
    let chartStyle: BodyHealthMetricChartStyle
    let symbolColor: Color
    let selectedRange: BodyHealthTrendRange
    let valueFormatter: (Double) -> String
    let highlightedRange: BodyHealthMetricTrendHighlightedRange?
    let highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)?
    let activeHighlightedValue: Binding<Double?>?
    let isSleepDetail: Bool
    let chartIdentity: String

    private let visibleCalendarPoints: [HealthTrendCalendarPoint]
    private let visibleFinitePoints: [HealthTrendCalendarPoint]
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>
    private let latestVisibleCalendarDate: Date?
    private let placeholderBarYValue: Double

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        chartStyle: BodyHealthMetricChartStyle,
        symbolColor: Color,
        selectedRange: BodyHealthTrendRange,
        series: HealthTrendSeries,
        valueFormatter: @escaping (Double) -> String,
        highlightedRange: BodyHealthMetricTrendHighlightedRange? = nil,
        highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)? = nil,
        activeHighlightedValue: Binding<Double?>? = nil,
        isSleepDetail: Bool,
        chartIdentity: String
    ) {
        self.title = title
        self.chartStyle = chartStyle
        self.symbolColor = symbolColor
        self.selectedRange = selectedRange
        self.valueFormatter = valueFormatter
        self.highlightedRange = highlightedRange
        self.highlightedRangeResolver = highlightedRangeResolver
        self.activeHighlightedValue = activeHighlightedValue
        self.isSleepDetail = isSleepDetail
        self.chartIdentity = chartIdentity

        let calendarPoints: [HealthTrendCalendarPoint]
        switch chartStyle {
        case .line:
            calendarPoints = series.lineChartCalendarPoints(to: selectedRange)
        case .bar:
            calendarPoints = series.chartCalendarPoints(to: selectedRange)
        }
        self.visibleCalendarPoints = calendarPoints
        self.visibleFinitePoints = calendarPoints.filter { $0.value?.isFinite == true }

        let aggregatedValues = calendarPoints.compactMap(\.value).filter(\.isFinite)
        let fallbackValues = series.limited(to: selectedRange).points.map(\.value).filter(\.isFinite)
        let highlightedRangeValues = highlightedRange?.domainValues ?? []
        let domainValues = (aggregatedValues.isEmpty ? fallbackValues : aggregatedValues) + highlightedRangeValues
        let yDomain = Self.computeYDomain(from: domainValues, chartStyle: chartStyle)
        self.chartYDomain = yDomain

        let domainDates = series.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)

        self.latestVisibleCalendarDate = calendarPoints.last { $0.value?.isFinite == true }?.date

        let span = yDomain.upperBound - yDomain.lowerBound
        self.placeholderBarYValue = yDomain.lowerBound + max(span * 0.025, 0.025)
    }

    private var activeHighlightedRange: BodyHealthMetricTrendHighlightedRange? {
        guard let highlightedRangeResolver, let activeHighlightSourcePoint else {
            return highlightedRange
        }

        return highlightedRangeResolver(activeHighlightSourcePoint.value) ?? highlightedRange
    }

    private var activeHighlightSourcePoint: HealthTrendCalendarPoint? {
        selectedTrendPoint ?? latestVisibleTrendPoint
    }

    private var activeHighlightSourceValue: Double? {
        activeHighlightSourcePoint?.value
    }

    private var latestVisibleTrendPoint: HealthTrendCalendarPoint? {
        visibleFinitePoints.last
    }

    var body: some View {
        GeometryReader { proxy in
            let chartBarWidth = selectedRange.chartBarWidth(forAvailableWidth: proxy.size.width)
            let displayedHighlightedRange = activeHighlightedRange

            Chart {
                if chartStyle == .bar, let selectedTrendPoint {
                    RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                }

                ForEach(visibleCalendarPoints) { point in
                    if let value = point.value {
                        switch chartStyle {
                        case .line:
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(title, value)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(lineChartStrokeColor)
                            .lineStyle(StrokeStyle(lineWidth: lineChartStrokeWidth, lineCap: .round, lineJoin: .round))

                            if selectedRange.showsPointMarks {
                                if selectedRange.usesPreviewLineChartStyle {
                                    PointMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value(title, value)
                                    )
                                    .symbol {
                                        BodyLineChartPreviewPointSymbol(
                                            tintColor: symbolColor,
                                            isCurrent: isLatestVisiblePoint(point),
                                            pointDiameter: selectedRange.linePointDiameter,
                                            currentPointDiameter: selectedRange.lineCurrentPointDiameter
                                        )
                                    }
                                } else {
                                    PointMark(
                                        x: .value("Date", point.date, unit: .day),
                                        y: .value(title, value)
                                    )
                                    .foregroundStyle(symbolColor)
                                    .symbolSize(28)
                                }
                            }
                        case .bar:
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value(title, value),
                                width: .fixed(chartBarWidth)
                            )
                            .foregroundStyle(symbolColor.gradient)
                            .cornerRadius(4)
                        }
                    } else if chartStyle == .bar {
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value(title, placeholderBarYValue),
                            width: .fixed(chartBarWidth)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.14))
                        .cornerRadius(4)
                    }
                }

                if let selectedTrendPoint, let selectedTrendValue = selectedTrendPoint.value {
                    RuleMark(x: .value("Selected Date", selectedTrendPoint.date, unit: .day))
                        .foregroundStyle(chartStyle == .bar ? Color.clear : Color.secondary.opacity(0.48))
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: bodyChartSelectionOverflowResolution
                        ) {
                            BodyChartSelectionAnnotation(
                                eyebrow: chartStyle == .bar ? barSelectionEyebrow : nil,
                                values: [
                                    BodyChartSelectionValue(
                                        title: nil,
                                        value: chartSelectionText(for: selectedTrendValue),
                                        color: symbolColor
                                    )
                                ],
                                date: selectedTrendPoint.date,
                                dateText: bodyChartSelectionDateText(for: selectedTrendPoint)
                            )
                        }

                    if chartStyle == .line {
                        PointMark(
                            x: .value("Selected Date", selectedTrendPoint.date, unit: .day),
                            y: .value(title, selectedTrendValue)
                        )
                        .foregroundStyle(symbolColor)
                        .symbolSize(82)
                    }
                }
            }
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: chartYDomain)
            .chartBackground { chartProxy in
                GeometryReader { geo in
                    if let highlightedRange = displayedHighlightedRange,
                       let plotFrame = chartProxy.plotFrame {
                        let plotRect = geo[plotFrame]
                        let upperY = (chartProxy.position(forY: highlightedRange.upperPlotBound(in: chartYDomain)) ?? 0) + plotRect.minY
                        let lowerY = (chartProxy.position(forY: highlightedRange.lowerPlotBound(in: chartYDomain)) ?? 0) + plotRect.minY
                        let bandHeight = max(lowerY - upperY, 0)
                        let stripeHeightPx: CGFloat = max(plotRect.height * 0.006, 1.5)

                        Rectangle()
                            .fill(highlightedRange.color.opacity(0.12))
                            .frame(width: plotRect.width, height: bandHeight)
                            .offset(x: plotRect.minX, y: upperY)

                        Rectangle()
                            .fill(highlightedRange.color.opacity(0.72))
                            .frame(width: plotRect.width, height: stripeHeightPx)
                            .offset(x: plotRect.minX, y: upperY)

                        Rectangle()
                            .fill(highlightedRange.color.opacity(0.72))
                            .frame(width: plotRect.width, height: stripeHeightPx)
                            .offset(x: plotRect.minX, y: lowerY - stripeHeightPx)
                    }
                }
            }
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
            .id(chartIdentity)
            .transition(
                .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
            )
            .transaction(value: highlightedRangeAnimationKey) { transaction in
                transaction.animation = reduceMotion ? nil : .smooth(duration: 0.55, extraBounce: 0)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                syncActiveHighlightedValue()
            }
            .onChange(of: activeHighlightSourceValue) { _, _ in
                syncActiveHighlightedValue()
            }
        }
    }

    private var selectedTrendPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return visibleFinitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private var highlightedRangeAnimationKey: String {
        guard let range = activeHighlightedRange else { return "none" }
        let lower = range.lowerBound.map { String(format: "%.4f", $0) } ?? "nil"
        let upper = range.upperBound.map { String(format: "%.4f", $0) } ?? "nil"
        return "\(range.title)|\(lower)|\(upper)"
    }

    private func isLatestVisiblePoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == latestVisibleCalendarDate
    }

    private var lineChartStrokeColor: Color {
        selectedRange.usesMetricColorLineStroke ? symbolColor : BodyLineChartPreviewStyle.lineColor
    }

    private var lineChartStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private var barSelectionEyebrow: String {
        selectedRange.chartAggregationDayCount > 1 ? "AVG" : "TOTAL"
    }

    private func chartSelectionText(for value: Double) -> String {
        if isSleepDetail {
            return BodyValueFormat.sleepDurationText(for: value * 60 * 60)
        }

        return valueFormatter(value)
    }

    private func syncActiveHighlightedValue() {
        activeHighlightedValue?.wrappedValue = activeHighlightSourceValue
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

    static func computeYDomain(
        from values: [Double],
        chartStyle: BodyHealthMetricChartStyle
    ) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        if chartStyle == .bar {
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

private struct BodyWristTemperatureBaselineChart: View {
    let selectedRange: BodyHealthTrendRange
    let symbolColor: Color

    private let baseline: Double
    private let deviationPoints: [HealthTrendCalendarPoint]
    private let finiteDeviationPoints: [HealthTrendCalendarPoint]
    private let latestPointDate: Date?
    private let chartXDomain: ClosedRange<Date>
    private let chartYDomain: ClosedRange<Double>

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(series: HealthTrendSeries, selectedRange: BodyHealthTrendRange, symbolColor: Color) {
        self.selectedRange = selectedRange
        self.symbolColor = symbolColor
        let baselineValue = wristTemperatureBaseline(from: series)
        self.baseline = baselineValue

        let visiblePoints = series.lineChartCalendarPoints(to: selectedRange)
        let deviations = visiblePoints.map { point in
            HealthTrendCalendarPoint(
                date: point.date,
                value: point.value.map { $0 - baselineValue },
                startDate: point.startDate,
                endDate: point.endDate
            )
        }
        self.deviationPoints = deviations
        let finiteDeviations = deviations.filter { $0.value?.isFinite == true }
        self.finiteDeviationPoints = finiteDeviations
        self.latestPointDate = finiteDeviations.last?.date

        let deviationValues = finiteDeviations.compactMap(\.value)
        let observedExtreme = deviationValues.map({ abs($0) }).max() ?? 0
        let halfRange = max(2.0, ceil(observedExtreme + 0.2))
        self.chartYDomain = -halfRange ... halfRange

        let domainDates = visiblePoints.map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Baseline", 0.0))
                .foregroundStyle(Color.secondary.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1.0))

            ForEach(deviationPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Variation", value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(symbolColor)
                    .lineStyle(StrokeStyle(lineWidth: BodyLineChartPreviewStyle.lineWidth, lineCap: .round, lineJoin: .round))

                    if selectedRange.showsPointMarks {
                        PointMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Variation", value)
                        )
                        .symbol {
                            BodyLineChartPreviewPointSymbol(
                                tintColor: symbolColor,
                                isCurrent: point.date == latestPointDate,
                                pointDiameter: selectedRange.linePointDiameter,
                                currentPointDiameter: selectedRange.lineCurrentPointDiameter
                            )
                        }
                    }
                }
            }

            if let selectedDeviationPoint, let value = selectedDeviationPoint.value {
                RuleMark(x: .value("Selected Date", selectedDeviationPoint.date, unit: .day))
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
                                    value: selectionText(for: value),
                                    color: symbolColor
                                )
                            ],
                            date: selectedDeviationPoint.date,
                            dateText: bodyChartSelectionDateText(for: selectedDeviationPoint)
                        )
                    }

                PointMark(
                    x: .value("Selected Date", selectedDeviationPoint.date, unit: .day),
                    y: .value("Variation", value)
                )
                .foregroundStyle(symbolColor)
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
            AxisMarks(position: .leading, values: yAxisValues) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.18))
                AxisTick()
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let yValue = value.as(Double.self) {
                        Text(yAxisLabel(for: yValue))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
        .id("wrist-temperature-baseline-\(selectedRange.rawValue)")
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var yAxisValues: [Double] {
        let upper = chartYDomain.upperBound
        return [-upper, 0, upper]
    }

    private func yAxisLabel(for value: Double) -> String {
        if abs(value) < 0.05 {
            return "Baseline"
        }

        let magnitude = BodyValueFormat.numberText(abs(value), decimals: 0)
        return value > 0 ? "+\(magnitude)°C" : "−\(magnitude)°C"
    }

    private func selectionText(for deviation: Double) -> String {
        if abs(deviation) < 0.05 {
            return "Baseline"
        }

        let magnitude = BodyValueFormat.numberText(abs(deviation), decimals: 1)
        return deviation > 0 ? "+\(magnitude)°C" : "−\(magnitude)°C"
    }

    private var selectedDeviationPoint: HealthTrendCalendarPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return finiteDeviationPoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
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
    let selectedRange: BodyHealthTrendRange
    let weightColor: Color
    let bodyFatColor: Color
    let weightFormatter: (Double) -> String
    let bodyFatFormatter: (Double) -> String

    private let weightCalendarPoints: [HealthTrendCalendarPoint]
    private let bodyFatCalendarPoints: [HealthTrendCalendarPoint]
    private let weightDomain: ClosedRange<Double>
    private let bodyFatDomain: ClosedRange<Double>
    private let chartXDomain: ClosedRange<Date>
    private let weightLatestCalendarDate: Date?
    private let bodyFatLatestCalendarDate: Date?
    private let weightFinitePointsByDate: [Date: HealthTrendCalendarPoint]
    private let bodyFatFinitePointsByDate: [Date: HealthTrendCalendarPoint]
    private let combinedFinitePoints: [HealthTrendCalendarPoint]

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let axisTickValues = [0.0, 0.25, 0.5, 0.75, 1.0]

    init(
        trend: BasicsTrendSummary,
        selectedRange: BodyHealthTrendRange,
        weightColor: Color,
        bodyFatColor: Color,
        weightFormatter: @escaping (Double) -> String,
        bodyFatFormatter: @escaping (Double) -> String
    ) {
        self.selectedRange = selectedRange
        self.weightColor = weightColor
        self.bodyFatColor = bodyFatColor
        self.weightFormatter = weightFormatter
        self.bodyFatFormatter = bodyFatFormatter

        let weightPoints = trend.weight.lineChartCalendarPoints(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
        let bodyFatPoints = trend.bodyFat.lineChartCalendarPoints(
            to: selectedRange,
            maximumPointCount: BodyHealthTrendRange.bodyFatWeightLineChartMaximumPointCount
        )
        self.weightCalendarPoints = weightPoints
        self.bodyFatCalendarPoints = bodyFatPoints
        self.weightDomain = Self.paddedDomain(from: weightPoints)
        self.bodyFatDomain = Self.paddedDomain(from: bodyFatPoints)

        let domainDates = trend.weight.calendarPoints(to: selectedRange).map(\.date)
            + trend.bodyFat.calendarPoints(to: selectedRange).map(\.date)
        self.chartXDomain = bodyHealthDetailChartXDomain(for: domainDates, selectedRange: selectedRange)

        self.weightLatestCalendarDate = weightPoints.last { $0.value?.isFinite == true }?.date
        self.bodyFatLatestCalendarDate = bodyFatPoints.last { $0.value?.isFinite == true }?.date

        var weightLookup: [Date: HealthTrendCalendarPoint] = [:]
        weightLookup.reserveCapacity(weightPoints.count)
        var bodyFatLookup: [Date: HealthTrendCalendarPoint] = [:]
        bodyFatLookup.reserveCapacity(bodyFatPoints.count)
        var combinedFinite: [HealthTrendCalendarPoint] = []
        combinedFinite.reserveCapacity(weightPoints.count + bodyFatPoints.count)
        for point in weightPoints where point.value?.isFinite == true {
            weightLookup[point.date] = point
            combinedFinite.append(point)
        }
        for point in bodyFatPoints where point.value?.isFinite == true {
            bodyFatLookup[point.date] = point
            combinedFinite.append(point)
        }
        self.weightFinitePointsByDate = weightLookup
        self.bodyFatFinitePointsByDate = bodyFatLookup
        self.combinedFinitePoints = combinedFinite
    }

    var body: some View {
        Chart {
            ForEach(weightCalendarPoints) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight", normalized(value, in: weightDomain)),
                        series: .value("Metric", "Weight")
                    )
                    .interpolationMethod(.linear)
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
                    .interpolationMethod(.linear)
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

                if let selectedWeightPoint = weightFinitePointsByDate[selectedTrendDate],
                   let selectedWeightValue = selectedWeightPoint.value {
                    PointMark(
                        x: .value("Selected Weight Date", selectedWeightPoint.date, unit: .day),
                        y: .value("Weight", normalized(selectedWeightValue, in: weightDomain))
                    )
                    .foregroundStyle(weightColor)
                    .symbolSize(82)
                }

                if let selectedBodyFatPoint = bodyFatFinitePointsByDate[selectedTrendDate],
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
        .transition(
            .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
        )
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

        return combinedFinitePoints.min { first, second in
            abs(first.date.timeIntervalSince(selectedDate)) < abs(second.date.timeIntervalSince(selectedDate))
        }
    }

    private var selectedTrendDateText: String? {
        selectedTrendPoint.flatMap { point in
            bodyChartSelectionDateText(for: point)
        }
    }

    private func isLatestWeightPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == weightLatestCalendarDate
    }

    private func isLatestBodyFatPoint(_ point: HealthTrendCalendarPoint) -> Bool {
        point.date == bodyFatLatestCalendarDate
    }

    private func lineStrokeColor(for color: Color) -> Color {
        selectedRange.usesMetricColorLineStroke ? color : BodyLineChartPreviewStyle.lineColor
    }

    private var lineStrokeWidth: CGFloat {
        selectedRange.usesPreviewLineChartStyle ? BodyLineChartPreviewStyle.lineWidth : selectedRange.trendLineWidth
    }

    private static func paddedDomain(from points: [HealthTrendCalendarPoint]) -> ClosedRange<Double> {
        let finiteValues = points.compactMap(\.value).filter(\.isFinite)
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

        if let point = bodyFatFinitePointsByDate[date], let value = point.value {
            values.append(BodyChartSelectionValue(
                title: "Body Fat",
                value: bodyFatFormatter(value),
                color: bodyFatColor
            ))
        }

        if let point = weightFinitePointsByDate[date], let value = point.value {
            values.append(BodyChartSelectionValue(
                title: "Weight",
                value: weightFormatter(value),
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
        let chartRangePreview: HealthTrendRangeSeries?

        init(
            kind: HealthMetricKind,
            title: String,
            value: String,
            unit: String,
            symbolName: String,
            symbolColor: Color,
            prominentMetrics: [BodyMetricDisplayValue] = [],
            chartPreviewStyle: BodyHomeMetricCardPreview.Style = .line,
            chartPreview: HealthTrendSeries? = nil,
            chartRangePreview: HealthTrendRangeSeries? = nil
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
            self.chartRangePreview = chartRangePreview
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
            if metric.chartPreview != nil || metric.chartRangePreview != nil {
                BodyHealthMetricCardTrendPreview(
                    series: metric.chartPreview,
                    rangeSeries: metric.chartRangePreview,
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
            BodyAnimatedMetricValueText(
                value: display.value,
                fontSize: valueFontSize,
                color: .primary,
                minimumScaleFactor: 0.60
            )
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
    let series: HealthTrendSeries?
    let rangeSeries: HealthTrendRangeSeries?
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
        guard let series else {
            return []
        }

        return BodyHomeMetricCardPreview.calendarPoints(from: series)
    }

    private var rangeCalendarPoints: [HealthTrendRangeCalendarPoint] {
        guard let rangeSeries else {
            return []
        }

        return BodyHomeMetricCardPreview.rangeCalendarPoints(from: rangeSeries)
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

    private var rangeValues: [Double] {
        rangeCalendarPoints.flatMap { point -> [Double] in
            guard let lowValue = point.lowValue,
                  let highValue = point.highValue,
                  lowValue.isFinite,
                  highValue.isFinite else {
                return []
            }

            return [lowValue, highValue]
        }
    }

    private var lastRangeValueIndex: Int? {
        rangeCalendarPoints.lastIndex { point in
            point.hasValue
        }
    }

    var body: some View {
        Group {
            switch style {
            case .line:
                linePreview
            case .bar:
                barPreview
            case .range:
                rangePreview
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
        case .range:
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

    private var rangePreview: some View {
        GeometryReader { proxy in
            let indexedPoints = Array(rangeCalendarPoints.enumerated())

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(indexedPoints, id: \.element.id) { index, point in
                    rangeBar(for: point, at: index, in: proxy.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
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

    private func rangeBar(for point: HealthTrendRangeCalendarPoint, at index: Int, in size: CGSize) -> some View {
        let frame = rangeBarFrame(for: point, in: size)

        return ZStack(alignment: .bottom) {
            Capsule(style: .continuous)
                .fill(rangeBarColor(for: point, at: index))
                .frame(width: 5, height: frame.height)
                .offset(y: -frame.bottomOffset)
        }
        .frame(width: 5, height: size.height, alignment: .bottom)
    }

    private func rangeBarFrame(for point: HealthTrendRangeCalendarPoint, in size: CGSize) -> (height: CGFloat, bottomOffset: CGFloat) {
        guard let lowValue = point.lowValue,
              let highValue = point.highValue,
              lowValue.isFinite,
              highValue.isFinite else {
            return (5, 0)
        }

        let minimum = rangeValues.min() ?? lowValue
        let maximum = rangeValues.max() ?? highValue
        let valueRange = max(maximum - minimum, 1)
        let plotHeight = max(size.height - 4, 1)
        let normalizedLow = (min(lowValue, highValue) - minimum) / valueRange
        let normalizedHigh = (max(lowValue, highValue) - minimum) / valueRange
        let bottomOffset = CGFloat(max(normalizedLow, 0)) * plotHeight
        let height = max(6, CGFloat(max(normalizedHigh - normalizedLow, 0)) * plotHeight)
        return (height, bottomOffset)
    }

    private func rangeBarColor(for point: HealthTrendRangeCalendarPoint, at index: Int) -> Color {
        guard point.hasValue else {
            return Color.secondary.opacity(0.14)
        }

        return index == (lastRangeValueIndex ?? -1) ? tintColor : Color.secondary.opacity(0.24)
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
