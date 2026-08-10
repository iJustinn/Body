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
    /// Live training-load ratio behind `value`, unformatted — the About your interval
    /// card marks the band it falls in while nothing is scrubbed.
    let trainingLoadValue: Double?
    let chartStyle: BodyHealthMetricChartStyle
    let highlightedRange: BodyHealthMetricTrendHighlightedRange?
    let highlightedRangeResolver: ((Double?) -> BodyHealthMetricTrendHighlightedRange?)?
    let valueFormatter: (Double) -> String
    let secondaryValueFormatter: ((Double) -> String)?
    let sourceComparisonTrend: BodyHealthSourceComparisonTrend?
    let sourceRangeComparisonTrend: BodyHealthSourceRangeComparisonTrend?
    let sourceLineComparisonTrend: BodyHealthSourceComparisonTrend?
    let headerMetrics: [BodyMetricDisplayValue]
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
        trainingLoadValue: Double? = nil,
        sourceComparisonTrend: BodyHealthSourceComparisonTrend? = nil,
        sourceRangeComparisonTrend: BodyHealthSourceRangeComparisonTrend? = nil,
        sourceLineComparisonTrend: BodyHealthSourceComparisonTrend? = nil,
        headerMetrics: [BodyMetricDisplayValue] = [],
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
        self.trainingLoadValue = trainingLoadValue
        self.chartStyle = chartStyle
        self.highlightedRange = highlightedRange
        self.highlightedRangeResolver = highlightedRangeResolver
        self.valueFormatter = valueFormatter
        self.secondaryValueFormatter = secondaryValueFormatter
        self.sourceComparisonTrend = sourceComparisonTrend
        self.sourceRangeComparisonTrend = sourceRangeComparisonTrend
        self.sourceLineComparisonTrend = sourceLineComparisonTrend
        self.headerMetrics = headerMetrics
        self.helpText = helpText ?? kind.detailHelpText
        self.dataSourceText = dataSourceText
    }
}

enum BodyDateSliderTileLabel {
    private static let recentWeekDayCount = 7

    static func dayNumberText(
        for date: Date,
        calendar: Calendar = .bodyGregorian
    ) -> String {
        String(calendar.component(.day, from: date))
    }

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

    /// Per-workout active energy rows (no sleep row): each workout's recorded
    /// total, converted to the display unit. The day chart's hourly buckets
    /// can't be clipped to workout intervals without misattributing energy at
    /// hour boundaries, so the workout's own recorded total is used instead.
    static func makeActiveEnergy(
        day: Date,
        workouts: [WorkoutSummary],
        energyUnitPreference: BodyValueFormat.EnergyUnitPreference,
        calendar: Calendar = .bodyGregorian
    ) -> [BodyMetricActivityAverage] {
        let dayInterval = interval(for: day, calendar: calendar)
        let rows = workouts.compactMap { workout -> BodyMetricActivityAverage? in
            let workoutEndDate = workout.startDate.addingTimeInterval(workout.duration)
            guard let workoutInterval = DateInterval(start: workout.startDate, end: workoutEndDate)
                .clamped(to: dayInterval),
                  let kilocalories = workout.activeEnergyKilocalories,
                  kilocalories.isFinite else {
                return nil
            }

            return BodyMetricActivityAverage(
                activity: .workout(workout.type),
                startDate: workoutInterval.start,
                endDate: workoutInterval.end,
                averageValue: BodyValueFormat.energyValue(
                    kilocalories: kilocalories,
                    energyUnitPreference: energyUnitPreference
                ).value,
                source: workout.sourceName
            )
        }

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

    /// Per-workout readiness impact rows: each workout's marginal drain on the
    /// day's score, shown negative. Workouts whose drain rounds below one point
    /// are omitted.
    static func makeReadinessImpact(timeline: ReadinessDayTimeline) -> [BodyMetricActivityAverage] {
        timeline.impacts
            .filter { $0.roundedDrainPoints >= 1 }
            .map { impact in
                BodyMetricActivityAverage(
                    activity: .workout(impact.workoutType),
                    startDate: impact.startDate,
                    endDate: impact.endDate,
                    averageValue: Double(-impact.roundedDrainPoints),
                    source: impact.sourceName
                )
            }
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
              let sleepInterval = sleepSummary.stageSnapshot.mainSession.dateInterval?.clamped(to: dayInterval),
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
    /// Shared with `BodyHomeView` so the Basics page's Weight/Body Fat cards are zoom sources for
    /// their detail push; nil off that stack (e.g. the readiness overlay), where they never render.
    let zoomNamespace: Namespace.ID?
    /// Report-up channel for the hero chart's scrub callout. `BodyHomeView` renders it as
    /// an overlay on the NavigationStack — the topmost layer — so the nav bar's back
    /// chevron and title can't draw over it (they're UIKit chrome that always beats any
    /// content inside this page).
    let floatingCallout: BodyChartFloatingCalloutState?
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedWeightUnitKey) private var selectedWeightUnitRawValue = BodyValueFormat.WeightUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true
    @AppStorage(BodyAppearancePreference.sleepStageBreakdownShowsOptimalRangesKey) private var sleepStageShowsOptimalRanges = false
    @AppStorage(BodyAppearancePreference.metricDayViewSelectionKey) private var metricDayViewSelectionRawValue = BodyMetricDayViewSelection.defaultRawValue
    @State private var selectedTrendRangeSelection: BodyHealthTrendRange
    @State private var showBodyProPaywall = false
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @State private var selectedSleepDate: Date?
    @State private var selectedMetricDate: Date?
    @State private var selectedSleepScoreDetails: SleepScoreDetailsSelection?
    @State private var showsDataSourcePicker = false
    @State private var showsAddMeasurementSheet = false
    @State private var activeReadinessTrendValue: Double?
    @State private var activeTrainingLoadTrendValue: Double?
    @StateObject private var trendComputationCache = BodyHomeTrendComputationCache()
    @StateObject private var daySeriesCache = BodyMetricDaySeriesCache()
    @StateObject private var sleepConsistencyCache = BodySleepConsistencyChartCache()

    init(
        model: BodyHealthMetricDetailModel,
        initialTrendRange: BodyHealthTrendRange = BodyHealthTrendRange.defaultValue,
        zoomNamespace: Namespace.ID? = nil,
        floatingCallout: BodyChartFloatingCalloutState? = nil
    ) {
        self.model = model
        self.zoomNamespace = zoomNamespace
        self.floatingCallout = floatingCallout
        _selectedTrendRangeSelection = State(initialValue: initialTrendRange)
    }

    private var isBodyProUnlocked: Bool {
        proStore?.isPro ?? false
    }

    /// The raw range-picker selection, clamped to the free `.recentWeek` for non-Pro
    /// users. Every chart, data slice, legend average, and chart identity below reads
    /// this (not the raw selection), so longer ranges never render without Body Pro.
    private var selectedTrendRange: BodyHealthTrendRange {
        isBodyProUnlocked ? selectedTrendRangeSelection : .recentWeek
    }

    /// Free users can browse the 3 most recent days in every metric day-picker; older
    /// days are a Body Pro feature.
    private static let freeDatePickerDayCount = 3

    /// The oldest day a non-Pro user may select, or `nil` for Pro (no day limit).
    private var oldestUnlockedDatePickerDay: Date? {
        guard !isBodyProUnlocked else { return nil }
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(Self.freeDatePickerDayCount - 1), to: today)
    }

    private func isDatePickerDateLocked(_ date: Date) -> Bool {
        guard let oldestUnlockedDatePickerDay else { return false }
        return Calendar.bodyGregorian.startOfDay(for: date) < oldestUnlockedDatePickerDay
    }

    /// Clamps a picker selection up into the free window for non-Pro users, so a locked
    /// day can never be the effective selection that the day charts read.
    private func clampedDatePickerDay(_ date: Date?) -> Date {
        let calendar = Calendar.bodyGregorian
        let dayStart = calendar.startOfDay(for: date ?? Date())
        if let oldestUnlockedDatePickerDay, dayStart < oldestUnlockedDatePickerDay {
            return oldestUnlockedDatePickerDay
        }
        return dayStart
    }

    private var dayChartTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                metricHero
                VStack(alignment: .leading, spacing: 16) {
                    metricDetailCards
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .bodyPullToRefresh(isRefreshing: workoutStore.isRefreshing) {
            Task { await workoutStore.refreshHealthMetric(model.kind) }
        }
        .task {
            await workoutStore.loadIntradayMetricSamplesIfNeeded(model.kind)
        }
        .task(id: selectedMetricDay) {
            // The readiness day view derives its line from workouts, which live in
            // month snapshots grouped by start-date month — an older picker day (or a
            // midnight-spanning workout from the day before) can sit in an unloaded
            // month. `loadMonthIfNeeded` is a cached no-op once the month is in.
            guard model.kind == .readiness else { return }
            let calendar = Calendar.bodyGregorian
            let dayStart = calendar.startOfDay(for: selectedMetricDay)
            let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
            for date in [dayStart, previousDay] {
                let components = calendar.dateComponents([.month, .year], from: date)
                if let month = components.month, let year = components.year {
                    await workoutStore.loadMonthIfNeeded(month: month, year: year)
                }
            }
        }
        .background {
            // Fixed (non-scrolling) backdrop for every metric detail: the metric tint
            // at the very top — behind the transparent nav bar — easing into the page
            // background by mid-screen. The hero content and cards scroll over this;
            // the nav bar stays clear over the tint at rest and picks up its standard
            // material as cards scroll beneath it.
            LinearGradient(
                colors: [model.symbolColor.opacity(0.45), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.5)
            )
            .ignoresSafeArea()
        }
        .navigationTitle(String(localized: String.LocalizationValue(model.title)))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedTrendRange) { _, _ in
            // The hero charts are keyed by range, so switching mid-scrub destroys the chart
            // instance before it can report the selection ending. The reporter's
            // `.onDisappear` clears too, but this exact stale-callout bug happened once —
            // keep the belt-and-braces reset.
            floatingCallout?.callout = nil
        }
        .tint(model.symbolColor)
        .accentColor(model.symbolColor)
        .toolbar {
            if isBasicsDetail {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAddMeasurementSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Measurement")
                }
            }
        }
        .sheet(item: $selectedSleepScoreDetails) { selection in
            SleepScoreDetailsSheet(selection: selection, accentColor: model.symbolColor)
                .presentationDetents([.height(BodySleepScoreDetailsSheetLayout.sheetHeight), .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsDataSourcePicker) {
            BodyHealthDataSourcePickerSheet(kind: model.kind, accentColor: model.symbolColor)
                .environmentObject(workoutStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAddMeasurementSheet) {
            BodyAddBasicsMeasurementSheet(
                accentColor: model.symbolColor,
                initialWeightKilograms: workoutStore.healthSummary.bodyMass.value,
                initialBodyFatPercent: workoutStore.healthSummary.bodyFatPercentage.value
            )
            .environmentObject(workoutStore)
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

    private var selectedWeightUnitPreference: BodyValueFormat.WeightUnitPreference {
        if followsSystemUnits {
            return BodyValueFormat.WeightUnitPreference.systemValue(locale: .current)
        }

        return BodyValueFormat.WeightUnitPreference.storedValue(from: selectedWeightUnitRawValue)
    }

    private var detailTrendComparisonModel: BodyHomeTrendCard.Model? {
        BodyHomeTrendCardFactory.card(
            for: model.kind,
            trends: workoutStore.healthTrends,
            temperatureUnitPreference: selectedTemperatureUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference,
            weightUnitPreference: selectedWeightUnitPreference,
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

    // The combined Basics page has no trend card of its own (the `.basics` kind maps
    // to no `BodyHomeTrendCardKind`), so surface the standalone Weight and Body Fat
    // trend cards here. This page is only ever pushed onto the Home stack (see
    // `BodyHomeView`), so tapping pushes that metric's focused detail via the same
    // `HomeMetricRoute` navigationDestination the home trends section uses. The push
    // uses the `.basicsTrend` route (not `.trend`) so each card's zoom-morph source has
    // a distinct id from the same-kind home trends card one nav level below.
    @ViewBuilder
    private func basicsMetricTrendCard(for kind: HealthMetricKind) -> some View {
        if let card = BodyHomeTrendCardFactory.card(
            for: kind,
            trends: workoutStore.healthTrends,
            temperatureUnitPreference: selectedTemperatureUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference,
            weightUnitPreference: selectedWeightUnitPreference,
            includesStable: true,
            cache: trendComputationCache
        ) {
            NavigationLink(value: HomeMetricRoute.basicsTrend(kind)) {
                basicsTrendZoomSource(BodyHomeTrendCard(model: card), for: kind)
            }
            .buttonStyle(.plain)
        }
    }

    /// Wraps a Basics trend card as its card→detail zoom (morph) source when the Home stack's
    /// namespace is available — mirroring `BodyHomeTrendsSection`, with the 28pt corner clip so
    /// the source hugs the card. Falls back to a plain card when no namespace was supplied.
    @ViewBuilder
    private func basicsTrendZoomSource(_ card: BodyHomeTrendCard, for kind: HealthMetricKind) -> some View {
        if let zoomNamespace {
            card.matchedTransitionSource(id: HomeMetricRoute.basicsTrend(kind), in: zoomNamespace) {
                $0.clipShape(.rect(cornerRadius: 28, style: .continuous))
            }
        } else {
            card
        }
    }

    private var isSleepDetail: Bool {
        model.kind == .sleep
    }

    private var isBasicsDetail: Bool {
        model.kind == .basics
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
             .steps,
             .readiness:
            return true
        case .restingHeartRate,
             .sleep,
             .basics,
             .bodyMass,
             .bodyFatPercentage,
             .bodyMassIndex,
             .restingEnergy,
             .exerciseMinutes,
             .trainingLoad,
             .wristTemperature,
             .timeInDaylight,
             .vitals:
            return false
        }
    }

    private var metricDayViewEnabled: Bool {
        BodyMetricDayViewSelection
            .storedValue(from: metricDayViewSelectionRawValue)
            .includes(model.kind)
    }

    private var selectedSleepDay: Date {
        clampedDatePickerDay(selectedSleepDate)
    }

    private var selectedMetricDay: Date {
        clampedDatePickerDay(selectedMetricDate)
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

    private var activeTrainingLoadInterval: TrainingLoadInterval? {
        guard model.kind == .trainingLoad else {
            return nil
        }

        if let activeTrainingLoadTrendValue, activeTrainingLoadTrendValue.isFinite {
            return TrainingLoadInterval.interval(for: activeTrainingLoadTrendValue)
        }

        return TrainingLoadInterval.interval(for: model.trainingLoadValue)
    }

    /// Scrub report-out channel for the metrics whose About card marks the band the
    /// touched point falls in; other metrics don't track it.
    private var activeTrendValueBinding: Binding<Double?>? {
        switch model.kind {
        case .readiness:
            return $activeReadinessTrendValue
        case .trainingLoad:
            return $activeTrainingLoadTrendValue
        default:
            return nil
        }
    }

    private var recentDatePickerDates: [Date] {
        SleepHistorySnapshot.datePickerDates(dayCount: BodyHealthTrendRange.recentMonth.dayCount, futureDayCount: 1)
    }

    // `points(on:)` scans the whole intraday series (tens of thousands of
    // points for heart rate); these are read several times per render, so the
    // day slice is memoized until the series or selected day changes.
    private var selectedMetricDaySeries: HealthTrendSeries {
        if model.kind == .readiness {
            // Derived from the morning score + workouts, not fetched samples —
            // tiny (~100 points), so it skips the day-series cache.
            return selectedReadinessDayTimeline?.sampledSeries() ?? .empty
        }

        return daySeriesCache.daySeries(from: liveDaySeries, on: selectedMetricDay, slot: .primary)
    }

    private var selectedReadinessMorningScore: Int? {
        let calendar = Calendar.bodyGregorian
        let day = selectedMetricDay
        if let entry = workoutStore.healthTrends.recordedReadiness
            .first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            return entry.score
        }
        if let point = workoutStore.healthTrends.readiness.points
            .first(where: { calendar.isDate($0.date, inSameDayAs: day) && $0.value.isFinite }) {
            return Int(point.value.rounded())
        }
        if calendar.isDateInToday(day), let readiness = model.readiness {
            return readiness.activityDrainMorningScore ?? readiness.score
        }
        return nil
    }

    private var selectedReadinessDayTimeline: ReadinessDayTimeline? {
        guard model.kind == .readiness, let morningScore = selectedReadinessMorningScore else {
            return nil
        }

        return ReadinessDayTimeline.make(
            morningScore: morningScore,
            workouts: workouts(on: selectedMetricDayInterval),
            dayInterval: selectedMetricDayInterval
        )
    }

    private var selectedMetricSecondaryDaySeries: HealthTrendSeries {
        // Day-line comparison reads the cached secondary series directly, bypassing the
        // store's secondary-source chokepoint — so gate it on Body Pro here too.
        guard isBodyProUnlocked, model.kind.usesSourceComparisonDayLineChart else {
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
        case .activeEnergy:
            return BodyMetricActivityAverages.makeActiveEnergy(
                day: selectedMetricDay,
                workouts: workouts(on: selectedMetricDayInterval),
                energyUnitPreference: selectedEnergyUnitPreference
            )
        case .readiness:
            guard let timeline = selectedReadinessDayTimeline else {
                return []
            }
            return BodyMetricActivityAverages.makeReadinessImpact(timeline: timeline)
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
    private var sleepScoreSummaryCard: some View {
        if showSleepScore {
            if let sleepScore = selectedSleepScore {
                sleepScoreCard(sleepScore)
            } else {
                unavailableSleepScoreCard
            }
        }
    }

    @ViewBuilder
    private var selectedSleepCards: some View {
        if let sourceLineComparisonTrend = model.sourceLineComparisonTrend {
            sleepStageCard(
                selectedSleepStageSnapshot.mainSession,
                sourceName: sourceLineComparisonTrend.primary.sourceName,
                emptyMessage: "No sleep stages for this source on this day"
            )
            sleepStageCard(
                selectedSecondarySleepStageSnapshot.mainSession,
                sourceName: sourceLineComparisonTrend.secondary.sourceName,
                emptyMessage: "No sleep stages for this source on this day"
            )
        } else {
            sleepStageCard(selectedSleepStageSnapshot.mainSession)
        }

        if !selectedSleepStageSnapshot.napSessions.isEmpty {
            // In comparison mode the primary source's name repeats here so the
            // nap card doesn't read as part of the secondary card above it.
            napStageCard(
                selectedSleepStageSnapshot,
                sourceName: model.sourceLineComparisonTrend?.primary.sourceName
            )
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
            .bodyCardBackground(translucent: true)
        }
    }

    private func trainingLoadIntervalCard(activeInterval: TrainingLoadInterval?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About your interval")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(TrainingLoadInterval.displayOrder, id: \.self) { interval in
                    trainingLoadIntervalExplanationRow(
                        interval: interval,
                        isCurrent: activeInterval == interval
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private func trainingLoadIntervalExplanationRow(interval: TrainingLoadInterval, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(BodyTrainingLoadIntervalPresentation.color(for: interval))
                .frame(width: 4)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    // Interval titles run longer than the readiness status titles, so the
                    // title compresses rather than wrapping the range and Current chip.
                    Text(interval.title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(interval.rangeText)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(BodyTrainingLoadIntervalPresentation.color(for: interval))
                        .fixedSize(horizontal: true, vertical: false)

                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BodyTrainingLoadIntervalPresentation.color(for: interval))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                BodyTrainingLoadIntervalPresentation.color(for: interval)
                                    .opacity(0.14),
                                in: Capsule()
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(interval.explanation)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func readinessWhyCard(for readiness: ReadinessSummary, activeStatus: ReadinessStatus?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About your score")
                .font(.system(size: 22, weight: .bold, design: .rounded))
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
        .bodyCardBackground(translucent: true)
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
                    ForEach(Array(dataSourceFooterIconNames.enumerated()), id: \.offset) { _, iconName in
                        Image(systemName: iconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(model.symbolColor)
                    }

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

    private var dataSourceFooterIconNames: [String] {
        guard model.kind.supportsHealthDataSourceSelection else {
            return ["heart.text.square.fill"]
        }

        let primary = workoutStore.selectedHealthDataSourceOption(for: model.kind)
        let primaryIcon = primary.isAllSources
            ? "heart.text.square"
            : BodyHealthSourceIcon.systemImageName(
                name: primary.name,
                bundleIdentifier: primary.iconBundleIdentifierHint,
                fallback: "heart.text.square"
            )

        guard model.kind.supportsSecondaryHealthDataSourceSelection else {
            return [primaryIcon]
        }

        let secondary = workoutStore.selectedSecondaryHealthDataSourceOption(for: model.kind)
        guard !secondary.isNoComparison else {
            return [primaryIcon]
        }

        let secondaryIcon = secondary.isAllSources
            ? "square.text.square"
            : BodyHealthSourceIcon.systemImageName(
                name: secondary.name,
                bundleIdentifier: secondary.iconBundleIdentifierHint,
                fallback: "square.text.square"
            )

        return [primaryIcon, secondaryIcon]
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

        return String(localized: "\(primaryName) vs \(secondaryOption.name)")
    }

    // Apple Watch–style immersive header, shared by every metric. The metric-tint→
    // page-color gradient is a fixed, non-scrolling backdrop (set on `body`), so it
    // stays put behind the nav bar while the cards scroll over it. This hero is just
    // the transparent content laid on top: the range tabs as floating pills, the
    // metric's chart blended in (Y-axis hidden), and the current value reading large
    // at the bottom-left.
    private var metricHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            BodyHealthTrendRangeSelector(
                // Bind to the effective (clamped) range, not the raw selection, so a
                // locked pill can't appear selected while the chart renders Week.
                selectedRange: Binding(
                    get: { selectedTrendRange },
                    set: { selectedTrendRangeSelection = $0 }
                ),
                appearance: .onGradient,
                isProUnlocked: isBodyProUnlocked,
                onLockedRangeTap: { showBodyProPaywall = true }
            )
            .sheet(isPresented: $showBodyProPaywall) {
                NavigationStack { BodyProView() }
            }

            if vitalsNeedsMoreSleepData {
                // The calibration notice replaces the outlier hero: without a
                // baseline the typical band and axes would chart nothing real.
                Text("Vitals needs about two weeks of sleep data to learn your typical ranges.")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: BodyHealthDetailChartLayout.standardHeight)
            } else {
                metricTrendChart(immersive: true)
            }

            metricHeroValueRow

            if sleepDataUnavailableForToday {
                Text("No sleep data yet")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            metricBreakdownChart
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sleepDataUnavailableForToday: Bool {
        model.kind == .sleep &&
            model.sleepDuration == nil &&
            (model.sleepStageSnapshot?.isEmpty ?? true) &&
            (model.sleepVitals?.isEmpty ?? true)
    }

    // The per-metric cards that scroll below the hero (unchanged from the prior
    // layout, minus the header/selector/trend-card now folded into the hero).
    @ViewBuilder
    private var metricDetailCards: some View {
        if isSleepDetail {
            sleepScoreSummaryCard
            sleepDatePicker
            selectedSleepCards
            detailTrendComparisonCard
            aboutRestorativeSleepCard
            if showSleepScore {
                aboutSleepScoreCard
            }
            dataSourceFooter
        } else if isVitalsDetail {
            if !vitalsSnapshot.nights.isEmpty {
                metricDatePicker
                vitalsNightCard
            }
            helpTextCard
            dataSourceFooter
        } else {
            if isBasicsDetail {
                basicsRangeCard
            }
            if supportsMetricDayView {
                metricDatePicker
                metricDayChartCard
                metricActivityAveragesCard
                detailTrendComparisonCard
            } else {
                detailTrendComparisonCard
            }
            if isBasicsDetail {
                bodyMassIndexTrendCard
                basicsMetricTrendCard(for: .bodyMass)
                basicsMetricTrendCard(for: .bodyFatPercentage)
            }
            if model.kind == .readiness, let readiness = model.readiness {
                readinessWhyCard(for: readiness, activeStatus: activeReadinessStatus)
            }
            if model.kind == .trainingLoad {
                trainingLoadIntervalCard(activeInterval: activeTrainingLoadInterval)
            }
            helpTextCard
            dataSourceFooter
        }
    }

    private var metricHeroValueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            heroValueLeading
            Spacer(minLength: 8)
            heroValueTrailing
        }
    }

    @ViewBuilder
    private var heroValueLeading: some View {
        if model.kind == .vitals {
            // The headline follows the chart: it reads the visible range, not the
            // single latest night the home card shows.
            BodyMetricStatusValueText(text: vitalsHeroStatusText, fontSize: 40)
        } else if !model.value.isEmpty {
            heroBigValue(model.value, unit: model.unit)
        } else if let firstMetric = model.headerMetrics.first {
            heroBigValue(firstMetric.value, unit: firstMetric.unit)
        }
    }

    private func heroBigValue(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            BodyAnimatedMetricValueText(
                value: value,
                fontSize: 44,
                color: .primary,
                minimumScaleFactor: 0.5
            )

            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    // Metric-specific legend or average, relocated from the old trend-card header to
    // the hero's value row.
    @ViewBuilder
    private var heroValueTrailing: some View {
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
            averageHeaderText(
                metricRangeHeaderText,
                prefix: String(localized: "chart.legendRange", defaultValue: "Range")
            )
        } else if let averageTrendText {
            VStack(alignment: .trailing, spacing: 4) {
                averageHeaderText(averageTrendText)
                if wristTemperatureTrendBaseline != nil {
                    BodyChartBaselineLegend()
                }
            }
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.lastTextBaseline]
            }
        }
    }

    // The metric's trend chart, blended into the hero (no card, Y-axis hidden when
    // `immersive`). Each branch preserves that metric's chart: range bars for
    // heart-rate-style metrics, primary/secondary comparison charts, the dual-line
    // basics chart, and the highlight strips on the line chart. The training-load /
    // readiness day breakdowns render separately in `metricBreakdownChart`, below the
    // hero value row.
    @ViewBuilder
    private func metricTrendChart(immersive: Bool) -> some View {
        if let visibleBasicsTrend {
            BodyBasicsTrendChart(
                trend: visibleBasicsTrend,
                selectedRange: selectedTrendRange,
                weightColor: model.symbolColor,
                bodyFatColor: basicsBodyFatColor,
                weightFormatter: model.valueFormatter,
                bodyFatFormatter: model.secondaryValueFormatter ?? {
                    BodyValueFormat.numberText($0, decimals: 1) + "%"
                },
                immersive: immersive,
                floatingCallout: immersive ? floatingCallout : nil
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
                immersive: immersive,
                yDomain: metricRangeYDomain,
                floatingCallout: immersive ? floatingCallout : nil
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
                immersive: immersive,
                chartIdentity: "\(model.kind.rawValue)-source-range-comparison-\(selectedTrendRange.rawValue)",
                floatingCallout: immersive ? floatingCallout : nil
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
                immersive: immersive,
                yDomain: metricRangeYDomain,
                floatingCallout: immersive ? floatingCallout : nil
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
                immersive: immersive,
                chartIdentity: "\(model.kind.rawValue)-source-comparison-\(selectedTrendRange.rawValue)",
                floatingCallout: immersive ? floatingCallout : nil
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
                immersive: immersive,
                chartIdentity: "\(model.kind.rawValue)-source-line-comparison-\(selectedTrendRange.rawValue)",
                floatingCallout: immersive ? floatingCallout : nil
            )
            .frame(height: BodyHealthDetailChartLayout.standardHeight)
        } else if model.kind == .vitals {
            BodyVitalsOutlierTrendChart(
                nights: visibleVitalsNights,
                selectedRange: selectedTrendRange,
                immersive: immersive,
                floatingCallout: immersive ? floatingCallout : nil
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
                currentValuePoint: model.kind == .readiness && selectedTrendRange == .recentWeek
                    ? BodyReadinessStatusPresentation.currentTrendDot(readiness: model.readiness, series: model.series)
                    : nil,
                activeHighlightedValue: activeTrendValueBinding,
                floatingCallout: immersive ? floatingCallout : nil,
                isSleepDetail: isSleepDetail,
                baselineValue: wristTemperatureTrendBaseline,
                baselineDeviationFormatter: wristTemperatureTrendBaselineDeviationFormatter,
                immersive: immersive,
                chartIdentity: "\(model.kind.rawValue)-\(selectedTrendRange.rawValue)"
            )
            .frame(height: BodyHealthDetailChartLayout.standardHeight)
        }
    }

    // Readiness/training-load day breakdown bars, rendered below the hero value row so
    // the big current value reads directly beneath the line chart and the
    // day-by-status/interval bars sit under it.
    @ViewBuilder
    private var metricBreakdownChart: some View {
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
                        Text(String(localized: String.LocalizationValue(metric.title)))
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
        .bodyCardBackground(translucent: true)
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
        .bodyCardBackground(translucent: true)
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
            // Fade the scroll ends by masking the tiles to transparent (not a colored
            // overlay), so the edges blend into whatever is behind — including the
            // tinted page gradient — with no dark wedge.
            .mask(sleepDateSliderEdgeMask)
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

            ZStack {
                if selectedMetricDaySeries.isEmpty && selectedMetricSecondaryDaySeries.isEmpty {
                    Text("No data for this day")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: BodyHealthDetailChartLayout.dayChartHeight)
                        .transition(dayChartTransition)
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
                        includesSampleBreakdown: selectedMetricDayIncludesSampleBreakdown,
                        // The readiness line is a step function that is flat most of the
                        // day — a dot on every hour reads as noise, so flat runs keep
                        // only their start and end dots.
                        collapsesUnchangedPoints: model.kind == .readiness,
                        // Heart rate and respiratory rate plot min-max bars on their
                        // Week/Month/6M/Year chart, so their Day View carries the same
                        // bars per hour.
                        showsHourlyRangeBars: model.kind == .heartRate || model.kind == .respiratoryRate
                    )
                    .frame(height: BodyHealthDetailChartLayout.dayChartHeight)
                    // Scoped so only day-series content changes animate (marks morph on
                    // refresh landings with stable hourly identities); day switches still
                    // crossfade via `.id` below, and the outer transaction keeps silencing
                    // inherited scroll/date-picker animations.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: selectedMetricDaySeries)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: selectedMetricSecondaryDaySeries)
                    .id(selectedMetricDay)
                    .transition(dayChartTransition)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    @ViewBuilder
    private var metricActivityAveragesCard: some View {
        if model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .activeEnergy || model.kind == .readiness {
            let rows = selectedMetricActivityAverages

            VStack(alignment: .leading, spacing: 14) {
                Text(metricActivityAveragesTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if rows.isEmpty {
                    Text(metricActivityAveragesEmptyText)
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
            .bodyCardBackground(translucent: true)
        }
    }

    private var metricActivityAveragesTitle: String {
        switch model.kind {
        case .activeEnergy:
            return String(localized: "Energy by Activity")
        case .heartRateVariability:
            return String(localized: "Average HRV")
        case .readiness:
            return String(localized: "Impact by Activity")
        default:
            return String(localized: "Heart Rate by Activity")
        }
    }

    private var metricActivityAveragesEmptyText: String {
        switch model.kind {
        case .activeEnergy:
            return "No workout energy for this day"
        case .heartRateVariability:
            return "No sleep HRV for this day"
        case .readiness:
            return String(localized: "No workouts for this day")
        default:
            return "No sleep or workout heart rate for this day"
        }
    }

    private func metricActivityAverageRow(_ row: BodyMetricActivityAverage) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbolName)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(row.color)
                .frame(width: 38, height: 38)
                // Same continuous-corner tile as the Workouts page's workout-card
                // icons (18 pt radius at 58 pt, scaled to this 38 pt slot).
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(row.color.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: String.LocalizationValue(row.title)))
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
            return String(localized: "HOURLY TOTAL")
        case .readiness:
            return String(localized: "READINESS")
        default:
            return String(localized: "HOURLY AVG")
        }
    }

    private var selectedMetricDayIncludesSampleBreakdown: Bool {
        // Hourly cumulative metrics already report one value per hour — there's no
        // intra-hour sample window to break down. Readiness samples are synthetic,
        // so their sub-hour windows carry no information either.
        switch model.kind {
        case .activeEnergy, .steps, .readiness:
            return false
        default:
            return true
        }
    }

    private var selectedMetricDayContextIntervals: [BodyHealthMetricDayContextInterval] {
        guard model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .activeEnergy || model.kind == .steps || model.kind == .readiness else {
            return []
        }

        let dayInterval = selectedMetricDayInterval
        var intervals: [BodyHealthMetricDayContextInterval] = []

        // The main session and each nap shade their own bands; the whole-day
        // `dateInterval` would stretch one "sleep" region from bedtime to the
        // end of an afternoon nap.
        let stageSnapshot = sleepSummary(for: selectedMetricDay)?.stageSnapshot
        if let sleepInterval = stageSnapshot?.mainSession.dateInterval,
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

        for napSession in stageSnapshot?.napSessions ?? [] {
            if let napInterval = napSession.dateInterval?.clamped(to: dayInterval) {
                intervals.append(
                    BodyHealthMetricDayContextInterval(
                        kind: .sleep,
                        startDate: napInterval.start,
                        endDate: napInterval.end,
                        title: "Nap",
                        symbolName: "moon.zzz.fill",
                        color: Color(red: 0.20, green: 0.72, blue: 1.00)
                    )
                )
            }
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
        // Days older than the free window are a Body Pro feature: the tile dims, shows a
        // lock badge, and routes a tap to the paywall instead of changing the selection.
        let isLocked = isDatePickerDateLocked(dayStart)
        let primaryText = BodyDateSliderTileLabel.primaryText(for: dayStart, today: today, calendar: calendar)
        let dayNumberText = BodyDateSliderTileLabel.dayNumberText(for: dayStart, calendar: calendar)
        let tileFill = Color.primary.opacity(isFuture ? 0.03 : 0.06)
        let tileStroke: Color = isSelected
            ? dateSliderSelectionColor
            : Color.primary.opacity(isFuture ? 0.06 : 0.10)

        return Button {
            guard !isFuture else {
                return
            }

            selectDatePickerDay(dayStart, for: picker)
        } label: {
            VStack(spacing: 6) {
                Text(primaryText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text(dayNumberText)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundColor(dateTileForegroundColor(isFuture: isFuture || isLocked))
            .frame(width: 58, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tileFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tileStroke, lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeInOut(duration: 0.16), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(dayStart.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityHint(isFuture ? "Future date is not selectable" : (isLocked ? "Requires Body Pro" : ""))
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

    /// Shared selection entry point for every day-picker surface (the date tiles and the
    /// Sleep Consistency chart): a locked day opens the paywall instead of silently
    /// clamping. Callers still gate out future days themselves where applicable.
    private func selectDatePickerDay(_ date: Date, for picker: BodyMetricDetailDatePicker) {
        if isDatePickerDateLocked(date) {
            showBodyProPaywall = true
            return
        }

        selectDate(date, for: picker)
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

    private var sleepDateSliderEdgeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)

            Rectangle().fill(Color.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
        }
    }

    private var dateSliderSelectionColor: Color {
        model.symbolColor
    }

    private func dateTileForegroundColor(isFuture: Bool) -> Color {
        if colorScheme == .dark {
            return isFuture ? Color.white.opacity(0.34) : .white
        }
        return isFuture ? Color.black.opacity(0.32) : .black
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
            .bodyCardBackground(translucent: true)
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
        .bodyCardBackground(translucent: true)
    }

    private func sleepStageCard(
        _ snapshot: SleepStageSnapshot,
        title: String = "Sleep Stages",
        sourceName: String? = nil,
        emptyMessage: LocalizedStringKey = "No sleep stages for this day"
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: String.LocalizationValue(title)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if snapshot.mergedAsleepDuration > 0 {
                    BodyAnimatedMetricValueText(
                        value: BodyValueFormat.sleepDurationText(for: snapshot.mergedAsleepDuration),
                        fontSize: 22,
                        color: .secondary,
                        minimumScaleFactor: 0.75
                    )
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

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sleepStageShowsOptimalRanges.toggle()
                    }
                } label: {
                    Group {
                        if sleepStageShowsOptimalRanges {
                            BodySleepStageOptimalRangeChart(snapshot: snapshot)
                        } else {
                            sleepStageDurationSummary(snapshot)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sleepStageBreakdownAccessibilityLabel(snapshot))
                .accessibilityValue(sleepStageShowsOptimalRanges ? "Showing optimal ranges" : "Showing durations")
                .accessibilityHint("Switches between stage durations and optimal ranges")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private func sleepStageDurationSummary(_ snapshot: SleepStageSnapshot) -> some View {
        let restorative = snapshot.restorativeDuration

        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(SleepStage.allCases.enumerated()), id: \.element) { index, stage in
                    if index > 0 {
                        Spacer(minLength: 8)
                    }

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
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            Text("Restorative \(BodyValueFormat.durationText(for: restorative))")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // The toggle Button collapses its content into a single VoiceOver element, so spell out each
    // stage's share and duration here — otherwise the chart's per-stage values are unreadable.
    private func sleepStageBreakdownAccessibilityLabel(_ snapshot: SleepStageSnapshot) -> String {
        let total = SleepStage.allCases.reduce(0) { $0 + snapshot.duration(for: $1) }
        let descriptions = SleepStage.allCases.map { stage -> String in
            let duration = snapshot.duration(for: stage)
            let percent = total > 0 ? Int((duration / total * 100).rounded()) : 0
            return String(localized: "\(stage.displayName) \(percent) percent, \(BodyValueFormat.durationText(for: duration))")
        }
        let restorative = snapshot.restorativeDuration
        let restorativePercent = total > 0 ? Int((restorative / total * 100).rounded()) : 0
        let restorativeDescription = String(localized: "Restorative \(restorativePercent) percent, \(BodyValueFormat.durationText(for: restorative))")
        return String(localized: "Sleep stage breakdown. \(descriptions.joined(separator: ". ")). \(restorativeDescription).")
    }

    private func sleepStageChartIdentity(for snapshot: SleepStageSnapshot) -> String {
        let dateIdentity = snapshot.date.map { String($0.timeIntervalSinceReferenceDate) } ?? "no-date"
        let segmentIdentity = snapshot.segments.map(\.id).joined(separator: "|")
        return "\(dateIdentity)-\(segmentIdentity)"
    }

    // Takes the whole-day snapshot and derives the naps itself, so callers stay
    // symmetric with `sleepStageCard`, which is handed the main session.
    private func napStageCard(_ snapshot: SleepStageSnapshot, sourceName: String? = nil) -> some View {
        let napsSnapshot = snapshot.napsSnapshot
        let napTimeRanges = snapshot.napSessions.compactMap { napSessionTimeRangeText(for: $0) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nap Stages")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if napsSnapshot.mergedAsleepDuration > 0 {
                    BodyAnimatedMetricValueText(
                        value: BodyValueFormat.sleepDurationText(for: napsSnapshot.mergedAsleepDuration),
                        fontSize: 22,
                        color: .secondary,
                        minimumScaleFactor: 0.75
                    )
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

            BodySleepStageChart(snapshot: napsSnapshot)
                .id("Nap Stages-\(sourceName ?? "default")-\(sleepStageChartIdentity(for: napsSnapshot))")
                .transition(dayChartTransition)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
                // No summary row here to carry the breakdown, so the chart itself
                // becomes the single VoiceOver element that spells it out.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(napStageBreakdownAccessibilityLabel(napsSnapshot))

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(napTimeRanges.enumerated()), id: \.offset) { _, timeRange in
                    Text(timeRange)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private func napSessionTimeRangeText(for session: SleepStageSnapshot) -> String? {
        guard let interval = session.dateInterval else {
            return nil
        }

        let startText = interval.start.formatted(.dateTime.hour().minute())
        let endText = interval.end.formatted(.dateTime.hour().minute())
        return "\(startText) – \(endText)"
    }

    // Mirrors `sleepStageBreakdownAccessibilityLabel` for the nap chart, which
    // has no visible per-stage row of its own.
    private func napStageBreakdownAccessibilityLabel(_ snapshot: SleepStageSnapshot) -> String {
        let total = SleepStage.allCases.reduce(0) { $0 + snapshot.duration(for: $1) }
        let descriptions = SleepStage.allCases.map { stage -> String in
            let duration = snapshot.duration(for: stage)
            let percent = total > 0 ? Int((duration / total * 100).rounded()) : 0
            return String(localized: "\(stage.displayName) \(percent) percent, \(BodyValueFormat.durationText(for: duration))")
        }
        let restorative = snapshot.restorativeDuration
        let restorativePercent = total > 0 ? Int((restorative / total * 100).rounded()) : 0
        let restorativeDescription = String(localized: "Restorative \(restorativePercent) percent, \(BodyValueFormat.durationText(for: restorative))")
        return String(localized: "Nap stage breakdown. \(descriptions.joined(separator: ". ")). \(restorativeDescription).")
    }

    private var sleepConsistencyCard: some View {
        let chartModel = sleepConsistencyChartModel

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep Consistency")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if let consistencyPercentage = chartModel.consistencyPercentage {
                    BodyAnimatedMetricValueText(
                        value: "\(consistencyPercentage)%",
                        fontSize: 22,
                        color: .secondary,
                        minimumScaleFactor: 0.75
                    )
                        .multilineTextAlignment(.trailing)
                }
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
                        selectDatePickerDay(day, for: .sleep)
                    }
                )
                .frame(height: BodyHealthDetailChartLayout.sleepConsistencyHeight)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    // One pass over the history instead of 14 `sleepSummary(for:)` scans;
    // same precedence as that helper (history first, live summary only for
    // today's slot). The resulting 14 entries are the cache key, so re-renders
    // only rebuild the model when a displayed night actually changes.
    private var sleepConsistencyChartModel: SleepConsistencyChartModel {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        let days = SleepHistorySnapshot.datePickerDates(dayCount: SleepConsistencyChartModel.dayCount)
        let historyByDay = Dictionary(
            model.sleepHistory.days.map { (calendar.startOfDay(for: $0.date), $0.summary) },
            uniquingKeysWith: { _, newest in newest }
        )
        let currentSummary = currentSleepSummary(for: today)
        let entries = days.map { day in
            let summary = historyByDay[day] ?? (day == today ? currentSummary : nil)
            return (day: day, snapshot: summary?.stageSnapshot)
        }

        return sleepConsistencyCache.model(entries: entries, calendar: calendar)
    }

    private var aboutRestorativeSleepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About Restorative Sleep")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Restorative sleep is your Deep and REM time combined, the portion of the night that does the most to repair the body and consolidate memory. Deep sleep drives physical recovery while REM supports learning and mood. The total below the stage breakdown sums both stages and shows them as a share of your time in bed, so you can see how much of the night went toward genuine recovery.")
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private var aboutSleepScoreCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About Sleep Score")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Body scores each night from the data available for that sleep window: amount, continuity, start time consistency, deep and REM share, pressure from sleep HRV, sleep vitals, and skin temperature. Pressure, vitals, and temperature are graded against your own recent overnight baselines — sleep vitals use the same typical bands as the Vitals chart, so an outlier there costs points in proportion to how far it sits outside your band — and the total is calibrated so only truly strong nights score high. Missing sensors are skipped instead of counted as zero.")
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    // MARK: - Vitals

    private var isVitalsDetail: Bool {
        model.kind == .vitals
    }

    /// Every assessable night in the sleep history, graded against each vital's
    /// own baseline. Memoized: the grading walks the whole history.
    private var vitalsSnapshot: VitalsSnapshot {
        guard isVitalsDetail else {
            return .empty
        }

        let today = Date()
        return trendComputationCache.vitalsSnapshot(
            sleepHistory: model.sleepHistory,
            currentDaySleep: workoutStore.healthSummary.sleep.asOf(today),
            today: today,
            calendar: .bodyGregorian
        )
    }

    private var visibleVitalsNights: [VitalsNightAssessment] {
        let calendar = Calendar.bodyGregorian
        let currentDayStart = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(
            byAdding: .day,
            value: -(selectedTrendRange.dayCount - 1),
            to: currentDayStart
        ) else {
            return vitalsSnapshot.nights
        }

        return vitalsSnapshot.nights.filter { $0.date >= startDate }
    }

    /// Nothing has enough history to be graded yet — the baselines need roughly
    /// two weeks of nights before any vital gets a typical range.
    private var vitalsNeedsMoreSleepData: Bool {
        isVitalsDetail && vitalsSnapshot.nights.isEmpty
    }

    private var vitalsHeroStatusText: String {
        let nights = visibleVitalsNights
        guard !nights.isEmpty else {
            return "--"
        }

        return VitalsSnapshot.statusText(for: nights)
    }

    /// The graded night for the day the picker is on. `night.date` is already the
    /// start of the wake day, so a same-day match is all this needs.
    private var selectedVitalsNight: VitalsNightAssessment? {
        let calendar = Calendar.bodyGregorian
        let day = selectedMetricDay
        return vitalsSnapshot.nights.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Plot and per-vital rows for the selected night in one card, so the readings
    /// sit directly under the marker that graded them. The date picker above
    /// carries the day, so the title stays "Day View" like the other metric pages.
    private var vitalsNightCard: some View {
        let night = selectedVitalsNight
        let rows = night.map(vitalsDisplayRows(for:)) ?? []

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day View")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12)

                if let night {
                    Text(night.statusText)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if rows.isEmpty {
                vitalsEmptyNightText
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                BodySleepVitalsRegionChart(rows: rows)
                    .frame(height: BodyHealthDetailChartLayout.sleepVitalsHeight)

                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        BodyVitalRowView(row: row)

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
        .bodyCardBackground(translucent: true)
    }

    private var vitalsEmptyNightText: Text {
        Calendar.bodyGregorian.isDateInToday(selectedMetricDay)
            ? Text("No vitals for last night")
            : Text("No vitals for this day")
    }

    /// Only the vitals that were actually measured that night get a row, so a
    /// missing sensor leaves a gap rather than a fabricated reading. Each row
    /// grades against that vital's personal range, not a population one.
    private func vitalsDisplayRows(for night: VitalsNightAssessment) -> [SleepVitalDisplayRow] {
        night.measurements.map { measurement in
            let value: String
            let unit: String

            switch measurement.kind {
            case .sleepingHeartRate:
                value = BodyValueFormat.numberText(measurement.value.rounded(), decimals: 0)
                unit = "BPM"
            case .respiratoryRate:
                value = BodyValueFormat.numberText(measurement.value.rounded(), decimals: 0)
                unit = "br/min"
            case .wristTemperature:
                let display = BodyValueFormat.temperatureDisplay(
                    celsius: measurement.value,
                    temperatureUnitPreference: selectedTemperatureUnitPreference
                )
                value = display.value
                unit = display.unit
            case .bloodOxygen:
                value = BodyValueFormat.numberText(measurement.value.rounded(), decimals: 0)
                unit = "%"
            case .sleepDuration:
                value = BodyValueFormat.sleepDurationText(for: measurement.value * 3_600)
                unit = ""
            }

            return SleepVitalDisplayRow(
                title: measurement.kind.displayName,
                value: value,
                unit: unit,
                symbolName: measurement.kind.symbolName,
                // The plot places the marker against the reference range, so the
                // numeric value stays in the vital's native unit (°C, hours) even
                // when the label above is shown in °F.
                numericValue: measurement.value,
                referenceRange: measurement.referenceRange
            )
        }
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
        // The readiness day line is derived from the morning score + workouts,
        // not fetched from a health source — a source/average legend would mislead.
        guard model.kind != .readiness else {
            return []
        }

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

    private func averageHeaderText(
        _ text: String,
        prefix: String = String(localized: "detail.avgPrefix", defaultValue: "Avg")
    ) -> some View {
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
        let source: HealthTrendSeries
    }

    private var entriesBySlot: [Slot: (key: Key, series: HealthTrendSeries)] = [:]

    func daySeries(from series: HealthTrendSeries, on day: Date, slot: Slot) -> HealthTrendSeries {
        let key = Key(day: day, source: series)
        // `source == series` is the true identity check (a same-count/first/last
        // coincidence previously could false-positive on a changed middle point);
        // Array's COW fast path keeps the common unchanged-render case O(1) since
        // `series` is usually the same buffer as last render, not a re-diffed copy.
        if let entry = entriesBySlot[slot], entry.key == key {
            return entry.series
        }

        let daySeries = series.points(on: day)
        entriesBySlot[slot] = (key, daySeries)
        return daySeries
    }
}

/// Memoizes the 14-day sleep-consistency model. `make()` is cheap, but the
/// detail view rebuilds it on every `body` evaluation (each day selection or
/// progressive-refresh tick). Keyed only on the 14 displayed (day, stage
/// snapshot) pairs the chart actually reads, so the comparison stays bounded to
/// the window instead of deep-checking the full sleep history.
@MainActor
final class BodySleepConsistencyChartCache: ObservableObject {
    private struct Entry: Equatable {
        let day: Date
        let snapshot: SleepStageSnapshot?
    }

    private var cached: (key: [Entry], model: SleepConsistencyChartModel)?

    func model(
        entries: [(day: Date, snapshot: SleepStageSnapshot?)],
        calendar: Calendar = .bodyGregorian
    ) -> SleepConsistencyChartModel {
        let key = entries.map { Entry(day: $0.day, snapshot: $0.snapshot) }
        if let cached, cached.key == key {
            return cached.model
        }

        let model = SleepConsistencyChartModel.make(entries: entries, calendar: calendar)
        cached = (key, model)
        return model
    }
}
