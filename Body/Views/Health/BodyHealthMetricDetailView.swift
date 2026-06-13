//
//  BodyHealthMetricDetailView.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHealthMetricDetailModel {
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
    let sleepHistorySecondary: SleepHistorySnapshot
    let readiness: ReadinessSummary?
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
        sleepHistorySecondary: SleepHistorySnapshot = .empty,
        chartStyle: BodyHealthMetricChartStyle,
        highlightedRange: BodyHealthMetricTrendHighlightedRange? = nil,
        highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)? = nil,
        valueFormatter: @escaping (Double) -> String,
        secondaryValueFormatter: ((Double) -> String)?,
        readiness: ReadinessSummary? = nil,
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
        self.sleepHistorySecondary = sleepHistorySecondary
        self.readiness = readiness
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

struct BodyMetricActivityAverage: Equatable, Identifiable {
    enum Activity: Equatable {
        case sleep
        case workout(BodyWorkoutType)
    }

    let activity: Activity
    let startDate: Date
    let endDate: Date
    let averageValue: Double
    let source: String?

    var id: String {
        "\(activity.id)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)"
    }

    var title: String {
        switch activity {
        case .sleep:
            return "Sleep"
        case .workout(let workoutType):
            return workoutType.displayName
        }
    }

    var symbolName: String {
        switch activity {
        case .sleep:
            return "bed.double.fill"
        case .workout(let workoutType):
            return workoutType.symbolName
        }
    }

    var color: Color {
        switch activity {
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .workout(let workoutType):
            return workoutType.color
        }
    }
}

extension BodyMetricActivityAverage.Activity {
    var id: String {
        switch self {
        case .sleep:
            return "sleep"
        case .workout(let workoutType):
            return "workout-\(workoutType.rawValue)"
        }
    }
}

enum BodyMetricActivityAverages {
    static func makeHeartRate(
        day: Date,
        heartRateSeries: HealthTrendSeries,
        sleepSummary: SleepSummary?,
        workouts: [WorkoutSummary],
        sleepSource: String? = nil,
        calendar: Calendar = .bodyGregorian
    ) -> [BodyMetricActivityAverage] {
        let dayInterval = interval(for: day, calendar: calendar)
        var rows = makeSleepOnly(
            day: day,
            series: heartRateSeries,
            sleepSummary: sleepSummary,
            fallbackValue: sleepSummary?.vitals.heartRate,
            source: sleepSource,
            calendar: calendar
        )

        rows.append(contentsOf: workouts.compactMap { workout in
            let workoutEndDate = workout.startDate.addingTimeInterval(workout.duration)
            guard let workoutInterval = DateInterval(start: workout.startDate, end: workoutEndDate)
                .clamped(to: dayInterval) else {
                return nil
            }

            let sampleAverage = average(in: workoutInterval, from: heartRateSeries)
                ?? average(in: workoutInterval, from: workout.heartRateSamples ?? [])
            let fallbackAverage = workout.averageHeartRateBeatsPerMinute
                .flatMap { $0.isFinite ? $0 : nil }
            guard let average = sampleAverage ?? fallbackAverage else {
                return nil
            }

            return BodyMetricActivityAverage(
                activity: .workout(workout.type),
                startDate: workoutInterval.start,
                endDate: workoutInterval.end,
                averageValue: average,
                source: workout.sourceName
            )
        })

        var seenIDs = Set<String>()
        return rows
            .filter { seenIDs.insert($0.id).inserted }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }

                return $0.title < $1.title
            }
    }

    static func makeSleepOnly(
        day: Date,
        series: HealthTrendSeries,
        sleepSummary: SleepSummary?,
        fallbackValue: Double?,
        source: String? = nil,
        calendar: Calendar = .bodyGregorian
    ) -> [BodyMetricActivityAverage] {
        let dayInterval = interval(for: day, calendar: calendar)
        guard let sleepSummary,
              let sleepInterval = sleepSummary.stageSnapshot.dateInterval?.clamped(to: dayInterval),
              let average = average(in: sleepInterval, from: series)
                ?? fallbackValue.flatMap({ $0.isFinite ? $0 : nil }) else {
            return []
        }

        return [
            BodyMetricActivityAverage(
                activity: .sleep,
                startDate: sleepInterval.start,
                endDate: sleepInterval.end,
                averageValue: average,
                source: source
            )
        ]
    }

    private static func interval(for day: Date, calendar: Calendar) -> DateInterval {
        let dayStart = calendar.startOfDay(for: day)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        return DateInterval(start: dayStart, end: nextDayStart)
    }

    private static func average(in interval: DateInterval, from series: HealthTrendSeries) -> Double? {
        finiteAverage(series.points
            .filter { $0.date >= interval.start && $0.date < interval.end }
            .map(\.value))
    }

    private static func average(in interval: DateInterval, from samples: [WorkoutHeartRateSample]) -> Double? {
        finiteAverage(samples
            .filter { $0.date >= interval.start && $0.date < interval.end }
            .map(\.beatsPerMinute))
    }

    private static func finiteAverage(_ values: [Double]) -> Double? {
        let finiteValues = values.filter(\.isFinite)
        guard !finiteValues.isEmpty else {
            return nil
        }

        return finiteValues.reduce(0, +) / Double(finiteValues.count)
    }
}

enum BodyMetricDetailDatePicker {
    case sleep
    case metric
}

struct BodyHealthMetricDetailView: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let model: BodyHealthMetricDetailModel
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true
    @AppStorage(BodyAppearancePreference.metricDayViewSelectionKey) private var metricDayViewSelectionRawValue = BodyMetricDayViewSelection.defaultRawValue
    @State private var selectedTrendRange: BodyHealthTrendRange
    @State private var selectedSleepDate: Date?
    @State private var selectedMetricDate: Date?
    @State private var selectedSleepScoreDetails: SleepScoreDetailsSelection?
    @State private var showsDataSourcePicker = false
    @State private var isPullRefreshing = false
    @State private var activeReadinessTrendValue: Double?
    @StateObject private var trendComputationCache = BodyHomeTrendComputationCache()
    @StateObject private var daySeriesCache = BodyMetricDaySeriesCache()

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
                    detailTrendComparisonCard
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
                    if supportsMetricDayView {
                        metricDatePicker
                        metricDayChartCard
                        metricActivityAveragesCard
                        detailTrendComparisonCard
                    } else {
                        if model.kind == .readiness, let readiness = model.readiness {
                            readinessWhyCard(for: readiness, activeStatus: activeReadinessStatus)
                        }
                        detailTrendComparisonCard
                    }
                    if isBasicsDetail {
                        bodyMassIndexTrendCard
                    }
                    helpTextCard
                    dataSourceFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .readableContentColumn()
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
        .tint(model.symbolColor)
        .accentColor(model.symbolColor)
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

    private var detailTrendComparisonModel: BodyHomeTrendCard.Model? {
        BodyHomeTrendCardFactory.card(
            for: model.kind,
            trends: workoutStore.healthTrends,
            temperatureUnitPreference: selectedTemperatureUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference,
            includesStable: true,
            cache: trendComputationCache
        )
    }

    @ViewBuilder
    private var detailTrendComparisonCard: some View {
        if let card = detailTrendComparisonModel {
            BodyHomeTrendCard(model: card, showsNavigationIndicator: false)
        }
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
        guard metricDayViewEnabled else {
            return false
        }

        switch model.kind {
        case .heartRate,
             .heartRateVariability,
             .respiratoryRate,
             .oxygenSaturation,
             .activeEnergy,
             .steps:
            return true
        case .readiness,
             .restingHeartRate,
             .sleep,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight:
            return false
        }
    }

    private var metricDayViewEnabled: Bool {
        BodyMetricDayViewSelection
            .storedValue(from: metricDayViewSelectionRawValue)
            .includes(model.kind)
    }

    private var selectedSleepDay: Date {
        let calendar = Calendar.bodyGregorian
        return calendar.startOfDay(for: selectedSleepDate ?? Date())
    }

    private var selectedMetricDay: Date {
        let calendar = Calendar.bodyGregorian
        return calendar.startOfDay(for: selectedMetricDate ?? Date())
    }

    private var selectedMetricDayInterval: DateInterval {
        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: selectedMetricDay)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
        return DateInterval(start: dayStart, end: nextDayStart)
    }

    private var activeReadinessStatus: ReadinessStatus? {
        guard model.kind == .readiness else {
            return nil
        }

        if let activeReadinessTrendValue, activeReadinessTrendValue.isFinite {
            return ReadinessStatus.status(for: Int(activeReadinessTrendValue.rounded()))
        }

        return model.readiness?.status
    }

    private var recentDatePickerDates: [Date] {
        SleepHistorySnapshot.datePickerDates(dayCount: BodyHealthTrendRange.recentMonth.dayCount, futureDayCount: 1)
    }

    // `points(on:)` scans the whole intraday series (tens of thousands of
    // points for heart rate); these are read several times per render, so the
    // day slice is memoized until the series or selected day changes.
    private var selectedMetricDaySeries: HealthTrendSeries {
        daySeriesCache.daySeries(from: liveDaySeries, on: selectedMetricDay, slot: .primary)
    }

    private var selectedMetricSecondaryDaySeries: HealthTrendSeries {
        guard model.kind.usesSourceComparisonDayLineChart else {
            return .empty
        }

        return daySeriesCache.daySeries(from: liveSecondaryDaySeries, on: selectedMetricDay, slot: .secondary)
    }

    private var selectedMetricActivityAverages: [BodyMetricActivityAverage] {
        switch model.kind {
        case .heartRate:
            return BodyMetricActivityAverages.makeHeartRate(
                day: selectedMetricDay,
                heartRateSeries: selectedMetricDaySeries,
                sleepSummary: sleepSummary(for: selectedMetricDay),
                workouts: workouts(on: selectedMetricDayInterval),
                sleepSource: workoutStore.selectedHealthDataSourceOption(for: model.kind).name
            )
        case .heartRateVariability:
            let sleepSummary = sleepSummary(for: selectedMetricDay)
            return BodyMetricActivityAverages.makeSleepOnly(
                day: selectedMetricDay,
                series: selectedMetricDaySeries,
                sleepSummary: sleepSummary,
                fallbackValue: sleepSummary?.vitals.heartRateVariability,
                source: workoutStore.selectedHealthDataSourceOption(for: model.kind).name
            )
        default:
            return []
        }
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

    private var selectedSecondarySleepStageSnapshot: SleepStageSnapshot {
        model.sleepHistorySecondary.summary(on: selectedSleepDay, calendar: .bodyGregorian)?.summary.stageSnapshot
            ?? SleepStageSnapshot(date: selectedSleepDay, segments: [])
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

        if let sourceLineComparisonTrend = model.sourceLineComparisonTrend {
            sleepStageCard(
                selectedSleepStageSnapshot,
                sourceName: sourceLineComparisonTrend.primary.sourceName,
                emptyMessage: "No sleep stages for this source on this day"
            )
            sleepStageCard(
                selectedSecondarySleepStageSnapshot,
                sourceName: sourceLineComparisonTrend.secondary.sourceName,
                emptyMessage: "No sleep stages for this source on this day"
            )
        } else {
            sleepStageCard(selectedSleepStageSnapshot)
        }

        sleepConsistencyCard
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

    private func readinessWhyCard(for readiness: ReadinessSummary, activeStatus: ReadinessStatus?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About your score")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(ReadinessStatus.displayOrder, id: \.self) { status in
                    readinessStatusExplanationRow(
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

    private func readinessStatusExplanationRow(status: ReadinessStatus, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(BodyReadinessStatusPresentation.color(for: status))
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
                        .foregroundStyle(BodyReadinessStatusPresentation.color(for: status))

                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BodyReadinessStatusPresentation.color(for: status))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                BodyReadinessStatusPresentation.color(for: status)
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
                .foregroundColor(model.symbolColor)
                .frame(width: 58, height: 58)
                .background(model.symbolColor.opacity(0.16))
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
                    VStack(alignment: .trailing, spacing: 4) {
                        averageHeaderText(averageTrendText)
                        if wristTemperatureTrendBaseline != nil {
                            BodyChartBaselineLegend()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    activeHighlightedValue: model.kind == .readiness ? $activeReadinessTrendValue : nil,
                    isSleepDetail: isSleepDetail,
                    baselineValue: wristTemperatureTrendBaseline,
                    baselineDeviationFormatter: wristTemperatureTrendBaselineDeviationFormatter,
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

                if model.kind == .readiness {
                    BodyReadinessStatusBreakdownChart(
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

    private var wristTemperatureTrendBaseline: Double? {
        guard model.kind == .wristTemperature else {
            return nil
        }

        let baselineCelsius = wristTemperatureBaseline(from: workoutStore.healthTrends.wristTemperature)
        guard baselineCelsius.isFinite, baselineCelsius != 0 else {
            return nil
        }

        return BodyValueFormat.temperatureValue(
            celsius: baselineCelsius,
            temperatureUnitPreference: selectedTemperatureUnitPreference
        ).value
    }

    private var wristTemperatureTrendBaselineDeviationFormatter: ((Double) -> String)? {
        guard model.kind == .wristTemperature else {
            return nil
        }

        let unit = BodyValueFormat.temperatureValue(
            celsius: 0,
            temperatureUnitPreference: selectedTemperatureUnitPreference
        ).unit

        return { deviation in
            let magnitude = BodyValueFormat.numberText(abs(deviation), decimals: 1)
            if deviation > 0.05 {
                return "+\(magnitude) \(unit)"
            } else if deviation < -0.05 {
                return "−\(magnitude) \(unit)"
            } else {
                return "\(magnitude) \(unit)"
            }
        }
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
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    contextIntervals: selectedMetricDayContextIntervals,
                    aggregationLabel: selectedMetricDayAggregationLabel,
                    includesSampleBreakdown: selectedMetricDayIncludesSampleBreakdown
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

    @ViewBuilder
    private var metricActivityAveragesCard: some View {
        if model.kind == .heartRate || model.kind == .heartRateVariability {
            let rows = selectedMetricActivityAverages

            VStack(alignment: .leading, spacing: 14) {
                Text(model.kind == .heartRate ? "Average Heart Rate" : "Average HRV")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if rows.isEmpty {
                    Text(model.kind == .heartRate ? "No sleep or workout heart rate for this day" : "No sleep HRV for this day")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            metricActivityAverageRow(row)

                            if index < rows.count - 1 {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bodyCardBackground()
        }
    }

    private func metricActivityAverageRow(_ row: BodyMetricActivityAverage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(row.color)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(row.color.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(activityAverageTimeRangeText(for: row))
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(model.valueFormatter(row.averageValue))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(row.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let source = row.source, !source.isEmpty {
                    Text(source)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func activityAverageTimeRangeText(for row: BodyMetricActivityAverage) -> String {
        let startText = row.startDate.formatted(.dateTime.hour().minute())
        let endText = row.endDate.formatted(.dateTime.hour().minute())
        return "\(startText)-\(endText)"
    }

    private var selectedMetricDayAggregationLabel: String {
        switch model.kind {
        case .activeEnergy, .steps:
            return "HOURLY TOTAL"
        default:
            return "HOURLY AVG"
        }
    }

    private var selectedMetricDayIncludesSampleBreakdown: Bool {
        // Hourly cumulative metrics already report one value per hour — there's no
        // intra-hour sample window to break down.
        switch model.kind {
        case .activeEnergy, .steps:
            return false
        default:
            return true
        }
    }

    private var selectedMetricDayContextIntervals: [BodyHealthMetricDayContextInterval] {
        guard model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .activeEnergy || model.kind == .steps else {
            return []
        }

        let dayInterval = selectedMetricDayInterval
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
            .foregroundColor(dateTileForegroundColor(isFuture: isFuture))
            .frame(width: 58, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isFuture ? sleepDateTileBackground.opacity(0.62) : sleepDateTileBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? dateSliderSelectionColor : dateTileStrokeColor(isFuture: isFuture),
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
        model.symbolColor
    }

    private var sleepDateSliderBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.02, green: 0.02, blue: 0.025)
            : Color(red: 0.91, green: 0.91, blue: 0.93)
    }

    private var sleepDateTileBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.08)
            : Color.white
    }

    private func dateTileForegroundColor(isFuture: Bool) -> Color {
        if colorScheme == .dark {
            return isFuture ? Color.white.opacity(0.34) : .white
        }
        return isFuture ? Color.black.opacity(0.32) : .black
    }

    private func dateTileStrokeColor(isFuture: Bool) -> Color {
        let base: Color = colorScheme == .dark ? .white : .black
        return base.opacity(isFuture ? 0.08 : 0.16)
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

    private func sleepStageCard(
        _ snapshot: SleepStageSnapshot,
        title: String = "Sleep Stages",
        sourceName: String? = nil,
        emptyMessage: String = "No sleep stages for this day"
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if snapshot.asleepDuration > 0 {
                    Text(BodyValueFormat.sleepDurationText(for: snapshot.asleepDuration))
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                if let sourceName {
                    Text(sourceName)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.trailing)
                }
            }

            if snapshot.isEmpty {
                Text(emptyMessage)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodySleepStageChart(snapshot: snapshot)
                    .id("\(title)-\(sourceName ?? "default")-\(sleepStageChartIdentity(for: snapshot))")
                    .transition(dayChartTransition)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    .frame(height: BodyHealthDetailChartLayout.standardHeight)

                sleepStageDurationSummary(snapshot)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    private func sleepStageDurationSummary(_ snapshot: SleepStageSnapshot) -> some View {
        HStack(spacing: 10) {
            ForEach(SleepStage.allCases) { stage in
                VStack(alignment: .center, spacing: 7) {
                    Rectangle()
                        .fill(stage.bodyChartColor)
                        .frame(width: 28, height: 3)

                    Text(BodyValueFormat.durationText(for: snapshot.duration(for: stage)))
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func sleepStageChartIdentity(for snapshot: SleepStageSnapshot) -> String {
        let dateIdentity = snapshot.date.map { String($0.timeIntervalSinceReferenceDate) } ?? "no-date"
        let segmentIdentity = snapshot.segments.map(\.id).joined(separator: "|")
        return "\(dateIdentity)-\(segmentIdentity)"
    }

    private var sleepConsistencyCard: some View {
        let chartModel = sleepConsistencyChartModel

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Consistency")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                Text(workoutStore.selectedHealthDataSourceOption(for: model.kind).name)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.trailing)
            }

            if chartModel.nights.count < 2 {
                Text("Not enough sleep data yet")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                BodySleepConsistencyChart(
                    model: chartModel,
                    selectedDay: selectedSleepDay,
                    onSelectDay: { day in
                        selectDate(day, for: .sleep)
                    }
                )
                .frame(height: BodyHealthDetailChartLayout.sleepConsistencyHeight)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground()
    }

    // One pass over the history instead of 14 `sleepSummary(for:)` scans;
    // same precedence as that helper (history first, live summary only for
    // today's slot).
    private var sleepConsistencyChartModel: SleepConsistencyChartModel {
        let calendar = Calendar.bodyGregorian
        let days = SleepHistorySnapshot.datePickerDates(dayCount: SleepConsistencyChartModel.dayCount)
        let historyByDay = Dictionary(
            model.sleepHistory.days.map { (calendar.startOfDay(for: $0.date), $0.summary) },
            uniquingKeysWith: { _, newest in newest }
        )
        let today = calendar.startOfDay(for: Date())

        return SleepConsistencyChartModel.make(
            entries: days.map { day in
                let summary = historyByDay[day] ?? (day == today ? currentSleepSummary(for: day) : nil)
                return (day: day, snapshot: summary?.stageSnapshot)
            },
            calendar: calendar
        )
    }

    private var aboutSleepScoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About Sleep Score")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Body scores each night from the data available for that sleep window: amount, continuity, start time consistency, deep and REM share, pressure from sleep HRV, sleep vitals, and skin temperature. Pressure, vitals, and temperature are graded against your own recent overnight baselines, and the total is calibrated so only truly strong nights score high. Missing sensors are skipped instead of counted as zero.")
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
                title: "Skin Temperature",
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

/// Memoizes the day slice of the intraday sample series. Filtering is O(full
/// series) — up to tens of thousands of points for heart rate — and the
/// detail view reads the slice several times per render while the store
/// publishes multiple progressive-refresh updates.
@MainActor
final class BodyMetricDaySeriesCache: ObservableObject {
    enum Slot {
        case primary
        case secondary
    }

    private struct Key: Equatable {
        let day: Date
        let pointCount: Int
        let firstDate: Date?
        let lastDate: Date?
    }

    private var entriesBySlot: [Slot: (key: Key, series: HealthTrendSeries)] = [:]

    func daySeries(from series: HealthTrendSeries, on day: Date, slot: Slot) -> HealthTrendSeries {
        let key = Key(
            day: day,
            pointCount: series.points.count,
            firstDate: series.points.first?.date,
            lastDate: series.points.last?.date
        )
        if let entry = entriesBySlot[slot], entry.key == key {
            return entry.series
        }

        let daySeries = series.points(on: day)
        entriesBySlot[slot] = (key, daySeries)
        return daySeries
    }
}
