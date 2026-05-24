//
//  BodyHomeView.swift
//  Body
//

import Charts
import SwiftUI
import UniformTypeIdentifiers

let bodyChartSelectionOverflowResolution = AnnotationOverflowResolution(
    x: .fit(to: .chart),
    y: .disabled
)

let bodyHealthDetailChartLeadingDatePadding: TimeInterval = 2 * 60 * 60
let bodyHealthDetailChartMinimumTrailingDatePadding: TimeInterval = 36 * 60 * 60

func bodyHealthDetailChartTrailingDatePadding(for selectedRange: BodyHealthTrendRange) -> TimeInterval {
    let rangeScaledPadding = Double(selectedRange.axisStrideDayCount) * 24 * 60 * 60 * 0.55
    return max(bodyHealthDetailChartMinimumTrailingDatePadding, rangeScaledPadding)
}

func bodyHealthDetailChartXDomain(for dates: [Date], selectedRange: BodyHealthTrendRange) -> ClosedRange<Date> {
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

func bodyChartSelectionDateText(for point: HealthTrendCalendarPoint) -> String? {
    bodyChartSelectionDateText(startDate: point.startDate, endDate: point.endDate)
}

func bodyChartSelectionDateText(for point: HealthTrendRangeCalendarPoint) -> String? {
    bodyChartSelectionDateText(startDate: point.startDate, endDate: point.endDate)
}

// Median (not mean) so a single fever night cannot pull the displayed
// baseline away from the robust median Readiness's vitals component uses.
// Without this, the card can show "Baseline +0.3 °C" while Readiness shows
// no wrist-temperature driver (or vice versa) for the same day.
func wristTemperatureBaselineValue(from finiteValues: [Double]) -> Double {
    let sorted = finiteValues.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

func wristTemperatureBaseline(from series: HealthTrendSeries) -> Double {
    let points = series.lineChartCalendarPoints(to: .recentYear)
    let finiteValues = points.compactMap(\.value).filter(\.isFinite)
    guard !finiteValues.isEmpty else {
        return 0
    }

    return wristTemperatureBaselineValue(from: finiteValues)
}

func wristTemperatureBaselineDeviationDisplay(
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

    let baseline = wristTemperatureBaselineValue(from: finiteValues)
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

func bodyChartSelectionDateText(startDate: Date, endDate: Date) -> String? {
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

extension Array where Element == HealthTrendCalendarPoint {
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
            readinessMetric(
                summary: summary.readiness,
                chartPreview: trends.series(for: .readiness)
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
                symbolName: "sun.max.fill",
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
                kind: .readiness,
                title: "Readiness",
                series: trends.series(for: .readiness),
                chartStyle: .line,
                symbolName: "bolt.heart.fill",
                symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                messageStyle: .average(subject: "your readiness score"),
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
                symbolName: "sun.max.fill",
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

    private func readinessMetric(
        summary: ReadinessSummary,
        chartPreview: HealthTrendSeries
    ) -> BodyHealthMetricCard.Model {
        let scoreText = summary.score.map { "\($0)" } ?? "--"

        return BodyHealthMetricCard.Model(
            kind: .readiness,
            title: "Readiness",
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
        case .readiness:
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Readiness",
                value: summary.readiness.score.map { "\($0)" } ?? "--",
                unit: summary.readiness.score == nil ? "" : "%",
                symbolName: "bolt.heart.fill",
                symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
                series: trends.readiness,
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                highlightedRange: BodyReadinessStatusPresentation.make(
                    for: summary.readiness.score.map(Double.init)
                ),
                highlightedRangeResolver: BodyReadinessStatusPresentation.make(for:),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) + "%" },
                secondaryValueFormatter: nil,
                readiness: summary.readiness,
                headerMetrics: [
                    BodyMetricDisplayValue(
                        title: "Readiness",
                        value: summary.readiness.score.map { "\($0)" } ?? "--",
                        unit: summary.readiness.score == nil ? "" : "%"
                    ),
                    BodyMetricDisplayValue(
                        title: "Status",
                        value: summary.readiness.status.title,
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
                symbolName: "sun.max.fill",
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
                chartStyle: .bar,
                sleepHistory: trends.sleepHistory
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
                sleepHistorySecondary: trends.sleepHistorySecondary,
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
