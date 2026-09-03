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
    /// Today's Stress rollup, mirroring `readiness` — the hero's calibration /
    /// empty-state split and the time-in-band breakdown both read it directly
    /// rather than re-parsing `value`.
    let stress: StressDaySummary?
    /// Live training-load ratio behind `value`, unformatted — the About your interval
    /// card marks the band it falls in while nothing is scrubbed.
    let trainingLoadValue: Double?
    /// Live VO₂ max behind `value`, unformatted — the About your level card marks
    /// the level it falls in while nothing is scrubbed.
    let cardioFitnessValue: Double?
    /// Age + sex the cardio fitness levels are indexed by. `nil` leaves every
    /// level unclassified: rows render without their VO₂ spans and nothing is
    /// marked current.
    let cardioFitnessProfile: CardioFitnessProfile?
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
        stress: StressDaySummary? = nil,
        trainingLoadValue: Double? = nil,
        cardioFitnessValue: Double? = nil,
        cardioFitnessProfile: CardioFitnessProfile? = nil,
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
        self.stress = stress
        self.trainingLoadValue = trainingLoadValue
        self.cardioFitnessValue = cardioFitnessValue
        self.cardioFitnessProfile = cardioFitnessProfile
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

    func color(palette: BodyWorkoutColorPalette) -> Color {
        switch activity {
        case .sleep:
            return Color(red: 0.20, green: 0.72, blue: 1.00)
        case .workout(let workoutType):
            return palette.color(for: workoutType)
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
                ?? average(in: workoutInterval, from: workout.heartRateSamples)
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
    @Environment(HealthKitWorkoutStore.self) private var workoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workoutColorPalette) private var workoutColorPalette

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
    @AppStorage(BodyAppearancePreference.sleepStageBreakdownShowsOptimalRangesKey) private var sleepStageShowsOptimalRanges = true
    @AppStorage(BodyAppearancePreference.metricDayViewSelectionKey) private var metricDayViewSelectionRawValue = BodyMetricDayViewSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricWarningsKey) private var metricWarningSelectionRawValue = BodyMetricWarningSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricWarningThresholdsKey) private var metricWarningThresholdsRawValue = BodyMetricWarningThresholds.defaultRawValue
    @State private var selectedTrendRangeSelection: BodyHealthTrendRange
    @State private var showBodyProPaywall = false
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @State private var selectedSleepDate: Date?
    @State private var selectedMetricDate: Date?
    @State private var selectedSleepScoreDetails: SleepScoreDetailsSelection?
    @State private var showsDataSourcePicker = false
    @State private var showsAddMeasurementSheet = false
    @State private var showsReadinessImpactExplanation = false
    /// Scrubbed trend value, in an observable box rather than three `@State`
    /// properties: only the small reader around the About card reads it, so a
    /// scrub frame no longer re-evaluates the whole page body.
    @State private var activeTrendValues = BodyActiveTrendValueState()
    /// One anchor for every chart on the page, captured when it opens. Each
    /// chart used to default to its own `Date()`, so a slow render could grid
    /// two charts against different "today"s; a stable anchor also lets the
    /// per-range point caches hit across renders.
    @State private var chartAnchorDate = Date()
    /// 220 − age, for the high heart rate warning's zone-3 default threshold.
    @State private var resolvedMaxHeartRate: Double?
    @StateObject private var trendComputationCache = BodyHomeTrendComputationCache()
    @StateObject private var daySeriesCache = BodyMetricDaySeriesCache()
    @StateObject private var sleepConsistencyCache = BodySleepConsistencyChartCache()
    @StateObject private var workoutIndex = BodyCachedWorkoutIndex()
    @StateObject private var rangePointsCache = BodyTrendRangePointsCache()

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
        // Keyed on entitlement, not bare: the Body Pro paywall is a sheet presented
        // from this very view (`showBodyProPaywall`), so buying or restoring leaves
        // this view mounted and a bare `.task` would never re-run. The entitlement
        // handler deliberately empties the comparison day samples on any flip, so
        // without this the paid comparison line stays missing until the user leaves
        // and reopens the detail. Re-running here pulls the full window (an empty
        // cache has no incremental anchor). The flip also re-runs this on a lapse,
        // which is what clears the line in place.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            // The page can sit open across midnight; re-anchor so "today" moves.
            chartAnchorDate = Date()
        }
        .task(id: isBodyProUnlocked) {
            await workoutStore.loadIntradayMetricSamplesIfNeeded(model.kind)
        }
        // Re-keyed on the permission selection so the anchor re-resolves when Date of
        // Birth toggles: out of scope, `userMaxHeartRate()` returns nil and the high
        // heart rate warning falls back to its fixed default.
        .task(id: workoutStore.permissionSelection.rawValue) {
            // Only the high heart rate warning's default tracks max HR.
            guard model.kind == .heartRate else { return }
            resolvedMaxHeartRate = await workoutStore.userMaxHeartRate()
        }
        .task(id: selectedMetricDay) {
            // The readiness day view derives its line from workouts, and the heart
            // rate day view excludes workout samples from the high heart rate
            // warning. Workouts live in month snapshots grouped by start-date month —
            // an older picker day (or a midnight-spanning workout from the day
            // before) can sit in an unloaded month. `loadMonthIfNeeded` is a cached
            // no-op once the month is in.
            guard model.kind == .readiness || model.kind == .heartRate else { return }
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
        .onChange(of: selectedMetricDay) { _, _ in
            // The warning cards are not keyed by day, so a day switch mid-scrub swaps
            // their samples without the reporter's `.onDisappear` firing.
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
                .environment(workoutStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAddMeasurementSheet) {
            BodyAddBasicsMeasurementSheet(
                accentColor: model.symbolColor,
                initialWeightKilograms: workoutStore.healthSummary.bodyMass.value,
                initialBodyFatPercent: workoutStore.healthSummary.bodyFatPercentage.value
            )
            .environment(workoutStore)
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
             .readiness,
             .stress:
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
             .cardioFitness,
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

    private func readinessStatus(forActiveTrendValue activeValue: Double?) -> ReadinessStatus? {
        guard model.kind == .readiness else {
            return nil
        }

        if let activeValue, activeValue.isFinite {
            return ReadinessStatus.status(for: Int(activeValue.rounded()))
        }

        return model.readiness?.status
    }

    private func trainingLoadInterval(forActiveTrendValue activeValue: Double?) -> TrainingLoadInterval? {
        guard model.kind == .trainingLoad else {
            return nil
        }

        if let activeValue, activeValue.isFinite {
            return TrainingLoadInterval.interval(for: activeValue)
        }

        return TrainingLoadInterval.interval(for: model.trainingLoadValue)
    }

    /// The profile only when the norm tables actually cover it. A missing profile
    /// and an age outside 20...79 both leave every level unclassified, and the
    /// level card treats them identically.
    private var classifiableCardioFitnessProfile: CardioFitnessProfile? {
        guard let profile = model.cardioFitnessProfile,
              CardioFitnessLevel.cutoffs(for: profile) != nil else {
            return nil
        }

        return profile
    }

    /// Every cardio fitness level boundary, so the chart's Y domain spans all
    /// four bands in every range. Without it each range scales to whatever it
    /// happened to contain, and the same reading sits at a different height from
    /// one range to the next — which is exactly what a level chart shouldn't do.
    /// Empty for every other metric, and when the profile can't be classified.
    private var cardioFitnessLevelDomainValues: [Double] {
        guard model.kind == .cardioFitness,
              let profile = classifiableCardioFitnessProfile,
              let cutoffs = CardioFitnessLevel.cutoffs(for: profile) else {
            return []
        }

        return [cutoffs.p20, cutoffs.p50, cutoffs.p75]
    }

    private func cardioFitnessLevel(forActiveTrendValue activeValue: Double?) -> CardioFitnessLevel? {
        guard model.kind == .cardioFitness else {
            return nil
        }

        if let activeValue, activeValue.isFinite {
            return CardioFitnessLevel.level(
                for: activeValue,
                profile: model.cardioFitnessProfile
            )
        }

        return CardioFitnessLevel.level(
            for: model.cardioFitnessValue,
            profile: model.cardioFitnessProfile
        )
    }

    /// Scrub report-out channel for the metrics whose About card marks the band the
    /// touched point falls in; other metrics don't track it.
    private var activeTrendValueBinding: Binding<Double?>? {
        let values = activeTrendValues
        switch model.kind {
        case .readiness:
            return Binding { values.readiness } set: { values.readiness = $0 }
        case .trainingLoad:
            return Binding { values.trainingLoad } set: { values.trainingLoad = $0 }
        case .cardioFitness:
            return Binding { values.cardioFitness } set: { values.cardioFitness = $0 }
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
        let recordedScore = workoutStore.healthTrends.recordedReadiness
            .first(where: { calendar.isDate($0.date, inSameDayAs: day) })?
            .score
        let trendValue = workoutStore.healthTrends.readiness.points
            .first(where: { calendar.isDate($0.date, inSameDayAs: day) && $0.value.isFinite })?
            .value

        return ReadinessDayTimeline.morningScore(
            isToday: calendar.isDateInToday(day),
            liveReadiness: model.readiness,
            recordedScore: recordedScore,
            trendValue: trendValue
        )
    }

    private var selectedReadinessDayTimeline: ReadinessDayTimeline? {
        guard model.kind == .readiness, let morningScore = selectedReadinessMorningScore else {
            return nil
        }

        // Today follows the live tile's window (the wake cycle, including a
        // carried-in pre-day workout); past days use the frozen record's
        // calendar-day window. Workout context shading stays calendar-day based
        // (it shows the day's workouts, which is correct for shading).
        let dayInterval = selectedMetricDayInterval
        let workouts: [WorkoutSummary]
        if Calendar.bodyGregorian.isDateInToday(selectedMetricDay) {
            let now = Date()
            workouts = ReadinessComputeSupport.wakeCycleWorkouts(
                from: allCachedWorkouts,
                now: now,
                sleepEnd: workoutStore.healthSummary.sleep.stageSnapshot.wakeCycleEnd,
                calendar: .bodyGregorian
            )
        } else {
            workouts = self.workouts(on: dayInterval)
        }

        return ReadinessDayTimeline.make(
            morningScore: morningScore,
            workouts: workouts,
            dayInterval: dayInterval
        )
    }

    /// The selected day's intraday Stress windows, scored live against the
    /// cached snapshot — there is no fetched day series to fall back to (Stress
    /// is derived, like Readiness), so an unscored day simply renders empty.
    private var selectedStressWindows: [StressWindow] {
        guard model.kind == .stress else {
            return []
        }

        return workoutStore.stressWindows(for: selectedMetricDay)
    }

    /// The selected day's Stress rollup: today comes off the live model (which
    /// tracks the current, still-updating score), any other day off the
    /// recorded history — the same recorded/live split
    /// `selectedReadinessMorningScore` makes for Readiness.
    private var selectedStressDaySummary: StressDaySummary? {
        guard model.kind == .stress else {
            return nil
        }

        guard !Calendar.bodyGregorian.isDateInToday(selectedMetricDay) else {
            return model.stress
        }

        return workoutStore.healthTrends.recordedStressDays.first {
            Calendar.bodyGregorian.isDate($0.date, inSameDayAs: selectedMetricDay)
        }
    }

    private var selectedMetricSecondaryDaySeries: HealthTrendSeries {
        // Day-line comparison reads the cached secondary series directly, bypassing the
        // store's secondary-source chokepoint — so gate it on Body Pro here too.
        guard isBodyProUnlocked, model.kind.usesSourceComparisonDayLineChart else {
            return .empty
        }

        return daySeriesCache.daySeries(from: liveSecondaryDaySeries, on: selectedMetricDay, slot: .secondary)
    }

    /// Whether the Day View is comparing two sources at all. The day slice
    /// above is empty both when no comparison source is picked and when the
    /// picked one has no readings on the selected day, so the chart reads this
    /// off the unsliced series instead: only a real second source wants its
    /// marks kept (invisibly) on a day it is silent, so they fade out.
    private var hasComparedSecondaryDaySource: Bool {
        guard isBodyProUnlocked, model.kind.usesSourceComparisonDayLineChart else {
            return false
        }

        return !liveSecondaryDaySeries.isEmpty
    }

    private var selectedMetricWarnings: [MetricWarningEvent] {
        let selection = BodyMetricWarningSelection.storedValue(from: metricWarningSelectionRawValue)
        // Kinds that exclude in-workout readings need workout coverage; with the
        // Workouts permission off the cached workouts are cleared, so an empty
        // exclusion list would misreport workout heart rate as an inactive high.
        let hasWorkoutCoverage = workoutStore.permissionSelection.includes(.workouts)
        let kinds = MetricThresholdWarning.kinds(for: model.kind).filter {
            selection.includes($0) && (!$0.excludesWorkouts || hasWorkoutCoverage)
        }
        guard !kinds.isEmpty else {
            return []
        }

        // Apple's high heart rate notification only counts inactive readings, so
        // the day's workouts are dropped from the samples for those kinds.
        let workoutIntervals: [DateInterval] = kinds.contains(where: \.excludesWorkouts)
            ? workouts(on: selectedMetricDayInterval).map { workout in
                MetricThresholdWarning.workoutExclusionInterval(start: workout.startDate, end: workout.effectiveEndDate)
            }
            : []

        let thresholds = BodyMetricWarningThresholds.storedValue(from: metricWarningThresholdsRawValue)

        return kinds.compactMap { kind in
            MetricThresholdWarning.detect(
                kind,
                in: selectedMetricDaySeries,
                on: selectedMetricDay,
                threshold: thresholds.threshold(for: kind, maxHeartRate: resolvedMaxHeartRate),
                excluding: kind.excludesWorkouts ? workoutIntervals : []
            )
        }
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

    private func cardioFitnessLevelCard(activeLevel: CardioFitnessLevel?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About your level")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Without a classifiable profile the rows carry no VO₂ spans, so say
            // why here rather than leaving four unexplained bare titles.
            if classifiableCardioFitnessProfile == nil {
                Text("Levels compare you against people of the same age and sex. Add your date of birth and sex in the Health app to see yours. Levels are available from age 20 through 79.")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(CardioFitnessLevel.displayOrder, id: \.self) { level in
                    cardioFitnessLevelExplanationRow(
                        level: level,
                        isCurrent: activeLevel == level
                    )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    private func cardioFitnessLevelExplanationRow(level: CardioFitnessLevel, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(BodyCardioFitnessLevelPresentation.color(for: level))
                .frame(width: 4)
                .padding(.vertical, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(level.title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    // Absent whenever the profile can't be classified; the note
                    // above the rows explains the gap.
                    if let profile = classifiableCardioFitnessProfile,
                       let rangeText = CardioFitnessLevel.rangeText(for: level, profile: profile) {
                        Text(rangeText)
                            .font(.system(.subheadline, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(BodyCardioFitnessLevelPresentation.color(for: level))
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(BodyCardioFitnessLevelPresentation.color(for: level))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                BodyCardioFitnessLevelPresentation.color(for: level)
                                    .opacity(0.14),
                                in: Capsule()
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Text(level.explanation)
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
        let primaryIcon: String
        if primary.isCustomSource {
            // A custom source's icon resolves from the group (the user's pick,
            // heart by default); the name-token lookup below would instead match
            // whatever the user called it.
            primaryIcon = workoutStore.customHealthSourceIconName(for: primary.id)
        } else if primary.isAllSources {
            primaryIcon = "heart.text.square"
        } else {
            primaryIcon = BodyHealthSourceIcon.systemImageName(
                name: primary.name,
                bundleIdentifier: primary.iconBundleIdentifierHint,
                fallback: "heart.text.square"
            )
        }

        guard model.kind.supportsSecondaryHealthDataSourceSelection else {
            return [primaryIcon]
        }

        let secondary = workoutStore.selectedSecondaryHealthDataSourceOption(for: model.kind)
        guard !secondary.isNoComparison else {
            return [primaryIcon]
        }

        let secondaryIcon: String
        if secondary.isCustomSource {
            secondaryIcon = workoutStore.customHealthSourceIconName(for: secondary.id)
        } else if secondary.isAllSources {
            secondaryIcon = "square.text.square"
        } else {
            secondaryIcon = BodyHealthSourceIcon.systemImageName(
                name: secondary.name,
                bundleIdentifier: secondary.iconBundleIdentifierHint,
                fallback: "square.text.square"
            )
        }

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
                metricWarningCards
                detailTrendComparisonCard
            } else {
                detailTrendComparisonCard
                metricWarningCards
            }
            if isBasicsDetail {
                bodyMassIndexTrendCard
                basicsMetricTrendCard(for: .bodyMass)
                basicsMetricTrendCard(for: .bodyFatPercentage)
            }
            // Each About card reads the scrubbed value inside its own reader, so
            // a scrub frame re-evaluates only the card, not this page body.
            if model.kind == .readiness, let readiness = model.readiness {
                BodyActiveTrendValueReader(state: activeTrendValues, value: \.readiness) { activeValue in
                    readinessWhyCard(for: readiness, activeStatus: readinessStatus(forActiveTrendValue: activeValue))
                }
            }
            if model.kind == .trainingLoad {
                BodyActiveTrendValueReader(state: activeTrendValues, value: \.trainingLoad) { activeValue in
                    trainingLoadIntervalCard(activeInterval: trainingLoadInterval(forActiveTrendValue: activeValue))
                }
            }
            if model.kind == .cardioFitness {
                BodyActiveTrendValueReader(state: activeTrendValues, value: \.cardioFitness) { activeValue in
                    cardioFitnessLevelCard(activeLevel: cardioFitnessLevel(forActiveTrendValue: activeValue))
                }
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
        // Untrimmed history, not `visibleBasicsTrend`: every morphing chart
        // windows each range itself so the other ranges' marks stay resident,
        // and a series already limited to the selected range leaves them
        // nothing older to morph from — the longer ranges would pop in.
        if let basicsTrend = model.basicsTrend {
            BodyBasicsTrendChart(
                trend: basicsTrend,
                selectedRange: selectedTrendRange,
                weightColor: model.symbolColor,
                bodyFatColor: basicsBodyFatColor,
                weightFormatter: model.valueFormatter,
                bodyFatFormatter: model.secondaryValueFormatter ?? {
                    BodyValueFormat.numberText($0, decimals: 1) + "%"
                },
                immersive: immersive,
                floatingCallout: immersive ? floatingCallout : nil,
                weightPointsByRange: rangePointsCache.points(
                    for: basicsTrend.weight,
                    style: .basicsLine,
                    date: chartAnchorDate,
                    slot: .weight
                ),
                bodyFatPointsByRange: rangePointsCache.points(
                    for: basicsTrend.bodyFat,
                    style: .basicsLine,
                    date: chartAnchorDate,
                    slot: .bodyFat
                )
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
                floatingCallout: immersive ? floatingCallout : nil,
                primaryPointsByRange: rangePointsCache.rangePoints(
                    for: sourceRangeComparisonTrend.primary.series,
                    style: .bars,
                    date: chartAnchorDate,
                    slot: .primary
                ),
                secondaryPointsByRange: rangePointsCache.rangePoints(
                    for: sourceRangeComparisonTrend.secondary.series,
                    style: .bars,
                    date: chartAnchorDate,
                    slot: .secondary
                )
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
                // Range switches must UPDATE the comparison charts so they
                // morph between ranges; metric/variant changes still reset them.
                chartIdentity: "\(model.kind.rawValue)-source-range-comparison",
                floatingCallout: immersive ? floatingCallout : nil,
                date: chartAnchorDate,
                primaryPointsByRange: rangePointsCache.rangePoints(
                    for: sourceRangeComparisonTrend.primary.series,
                    style: .sourceComparison,
                    date: chartAnchorDate,
                    slot: .primary
                ),
                secondaryPointsByRange: rangePointsCache.rangePoints(
                    for: sourceRangeComparisonTrend.secondary.series,
                    style: .sourceComparison,
                    date: chartAnchorDate,
                    slot: .secondary
                )
            )
            .frame(height: BodyHealthDetailChartLayout.standardHeight)
        } else if usesRangeTrendChart, let metricRangeSeries = model.rangeSeries {
            BodyHeartRateRangeTrendChart(
                title: model.title,
                selectedRange: selectedTrendRange,
                // Untrimmed, for the same reason as the Basics chart above.
                rangeSeries: metricRangeSeries,
                symbolColor: model.symbolColor,
                valueFormatter: model.valueFormatter,
                showsAverageLineOverlay: model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .stress,
                immersive: immersive,
                yDomain: metricRangeYDomain,
                floatingCallout: immersive ? floatingCallout : nil,
                primaryPointsByRange: rangePointsCache.rangePoints(
                    for: metricRangeSeries,
                    style: .bars,
                    date: chartAnchorDate,
                    slot: .primary
                )
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
                chartIdentity: "\(model.kind.rawValue)-source-comparison",
                floatingCallout: immersive ? floatingCallout : nil,
                date: chartAnchorDate,
                primaryPointsByRange: rangePointsCache.points(
                    for: sourceComparisonTrend.primary.series,
                    style: .sourceComparison,
                    date: chartAnchorDate,
                    slot: .primary
                ),
                secondaryPointsByRange: rangePointsCache.points(
                    for: sourceComparisonTrend.secondary.series,
                    style: .sourceComparison,
                    date: chartAnchorDate,
                    slot: .secondary
                )
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
                chartIdentity: "\(model.kind.rawValue)-source-line-comparison",
                floatingCallout: immersive ? floatingCallout : nil,
                date: chartAnchorDate,
                primaryPointsByRange: rangePointsCache.points(
                    for: sourceLineComparisonTrend.primary.series,
                    style: .line,
                    date: chartAnchorDate,
                    slot: .primary
                ),
                secondaryPointsByRange: rangePointsCache.points(
                    for: sourceLineComparisonTrend.secondary.series,
                    style: .line,
                    date: chartAnchorDate,
                    slot: .secondary
                )
            )
            .frame(height: BodyHealthDetailChartLayout.standardHeight)
        } else if model.kind == .vitals {
            BodyVitalsOutlierTrendChart(
                // Untrimmed, for the same reason as the Basics chart above: the
                // chart builds each range's buckets from its own day grid.
                nights: vitalsSnapshot.nights,
                selectedRange: selectedTrendRange,
                immersive: immersive,
                floatingCallout: immersive ? floatingCallout : nil,
                date: chartAnchorDate,
                rangeBuckets: rangePointsCache.vitalsRangeBuckets(
                    nights: vitalsSnapshot.nights,
                    date: chartAnchorDate
                )
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
                // Passed for every range, not just the week: the chart hides it
                // with opacity off the week range, and withholding it there
                // would remove the mark and pop it on a range switch.
                currentValuePoint: model.kind == .readiness
                    ? BodyReadinessStatusPresentation.currentTrendDot(readiness: model.readiness, series: model.series)
                    : nil,
                activeHighlightedValue: activeTrendValueBinding,
                floatingCallout: immersive ? floatingCallout : nil,
                isSleepDetail: isSleepDetail,
                baselineValue: wristTemperatureTrendBaseline,
                baselineDeviationFormatter: wristTemperatureTrendBaselineDeviationFormatter,
                immersive: immersive,
                usesSparseReadings: model.kind.usesSparseTrendReadings,
                additionalDomainValues: cardioFitnessLevelDomainValues,
                // Cardio Fitness is read against named levels, so the axis
                // figures add nothing the band and the level card don't say.
                hidesYAxisLabels: model.kind == .cardioFitness,
                // Range switches must UPDATE the chart so it morphs between
                // ranges; metric changes still reset it.
                chartIdentity: "\(model.kind.rawValue)",
                pointsByRange: rangePointsCache.points(
                    for: model.series,
                    style: model.chartStyle == .bar
                        ? .bars
                        : (model.kind.usesSparseTrendReadings ? .sparseLine : .line),
                    date: chartAnchorDate,
                    slot: .primary
                )
            )
            .frame(height: BodyHealthDetailChartLayout.standardHeight)
        }
    }

    // Readiness/training-load/cardio-fitness day breakdown bars, rendered below the
    // hero value row so the big current value reads directly beneath the line chart
    // and the day-by-status/interval/level bars sit under it.
    @ViewBuilder
    private var metricBreakdownChart: some View {
        if model.kind == .trainingLoad {
            BodyTrainingLoadIntervalBreakdownChart(
                series: model.series,
                selectedRange: selectedTrendRange,
                date: chartAnchorDate
            )
            .padding(.top, 4)
        }

        if model.kind == .readiness {
            BodyReadinessStatusBreakdownChart(
                series: model.series,
                selectedRange: selectedTrendRange,
                date: chartAnchorDate
            )
            .padding(.top, 4)
        }

        if model.kind == .cardioFitness {
            BodyCardioFitnessLevelBreakdownChart(
                series: model.series,
                selectedRange: selectedTrendRange,
                profile: model.cardioFitnessProfile,
                date: chartAnchorDate
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
                series: bodyMassIndexTrend,
                selectedRange: selectedTrendRange,
                color: basicsBodyMassIndexColor,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) },
                pointsByRange: rangePointsCache.points(
                    for: bodyMassIndexTrend,
                    style: .line,
                    date: chartAnchorDate,
                    slot: .bodyMassIndex
                )
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

        guard let baselineCelsius = trendComputationCache.wristTemperatureBaseline(
            from: workoutStore.healthTrends.wristTemperature,
            date: chartAnchorDate
        ) else {
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
        // Computed once per body evaluation and shared below: `selectedStressWindows`
        // re-scores the day's windows against the live snapshot, and the plot and
        // the breakdown-rows gate both need it.
        let stressWindows = selectedStressWindows

        return VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .firstTextBaseline) {
                Text("Day View")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                // Stress folds its old separate "Time by Band" card into this one, so
                // the day's average heads the card the breakdown rows belong to —
                // styled like `BodyHealthSourceLegend`'s single-source "Avg" line so
                // every Day View header reads the same.
                if model.kind == .stress, let averageScore = selectedStressDaySummary?.averageScore {
                    Text("Avg \("\(averageScore)")")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .bodyLegendNumberFlip(value: "\(averageScore)")
                }

                if !dayComparisonLegendItems.isEmpty {
                    BodyHealthSourceLegend(
                        items: dayComparisonLegendItems,
                        valueFormatter: model.valueFormatter
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if model.kind == .stress {
                    // Discrete banded windows (scored / activity / unscored gap)
                    // don't fit the continuous-line day chart, so Stress gets its
                    // own Canvas plot instead of `BodyHealthMetricDayChart`. It
                    // stays mounted on every day — the no-data state is drawn
                    // inside it, because swapping it for a `Text` (or keying it on
                    // the day) would tear down the morph coordinator.
                    BodyStressIntradayPlot(
                        windows: stressWindows,
                        dayInterval: selectedMetricDayInterval,
                        contextIntervals: selectedStressDayContextIntervals,
                        title: model.title,
                        floatingCallout: floatingCallout
                    )
                    // ~80% of the standard day-chart height: the banded blocks
                    // need less vertical resolution than the continuous-line
                    // charts, and the breakdown rows below reclaim the space.
                    .frame(height: BodyHealthDetailChartLayout.dayChartHeight * 0.8)
                    .transition(dayChartTransition)
                } else if selectedMetricDaySeries.isEmpty && selectedMetricSecondaryDaySeries.isEmpty {
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
                        hasConfiguredSecondary: hasComparedSecondaryDaySource,
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
                    // Scoped so only day-series content changes animate: marks glide to
                    // their new positions — day switches included, since mark identity is
                    // hour-of-day and survives the switch — matching the sleep Vitals
                    // plot's dot morph (same curve as `BodySleepVitalsRegionPlot`). The
                    // outer transaction keeps silencing inherited scroll/date-picker
                    // animations.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0), value: selectedMetricDaySeries)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0), value: selectedMetricSecondaryDaySeries)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0), value: selectedMetricDayContextIntervals)
                    .transition(dayChartTransition)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                }
            }

            // The band breakdown lives in this card rather than its own: the rows
            // read the same day the plot above them draws.
            if model.kind == .stress,
               stressWindows.contains(where: { $0.isScored || $0.state == .activity }) {
                BodyStressDayBreakdownRows(
                    summary: selectedStressDaySummary,
                    recordedDays: workoutStore.healthTrends.recordedStressDays
                )
                .padding(.top, -14)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
    }

    @ViewBuilder
    private var metricWarningCards: some View {
        let warnings = selectedMetricWarnings

        ForEach(warnings, id: \.kind) { event in
            let window = MetricThresholdWarning.chartWindow(for: event, clampedTo: selectedMetricDayInterval)

            BodyMetricWarningCard(
                event: event,
                samples: selectedMetricDaySeries.points.filter { window.contains($0.date) },
                window: window,
                tint: model.symbolColor,
                floatingCallout: floatingCallout
            )
            // A warning is detected only once the day's samples have loaded, so the
            // card's first render lands on a page that is already on screen — with no
            // ambient animation behind it, the transition below has nothing to run on.
            // The fade-in covers that arrival; the transition still carries the card
            // when the day picker moves.
            .bodyCardFadeIn()
            .transition(dayChartTransition)
        }
        // Warnings appear and disappear as the day picker moves, so the cards fade
        // with the day chart instead of popping the page layout.
        // Keyed on the kinds rather than the events: the samples inside an event
        // churn on every refresh tick, which restarted the animation while the
        // set of cards was unchanged.
        .animation(reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0), value: warnings.map(\.kind))
    }

    @ViewBuilder
    private var metricActivityAveragesCard: some View {
        if model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .activeEnergy || model.kind == .readiness {
            let rows = selectedMetricActivityAverages

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metricActivityAveragesTitle)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer(minLength: 0)

                    // Readiness only: the other kinds list plain averages, which need
                    // no explaining. The readiness rows are the ones that read wrong —
                    // they can sum past the day's starting score.
                    if model.kind == .readiness {
                        Button {
                            showsReadinessImpactExplanation = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                                // Grows the tap area to the 44 pt minimum without moving
                                // the glyph or the header's height: the slop is padded in
                                // here and cancelled out below, like the Details card's.
                                .padding(Self.activityImpactHelpTapSlop)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(-Self.activityImpactHelpTapSlop)
                        .accessibilityLabel(BodyReadinessImpactExplanationSheet.sheetTitle)
                    }
                }

                if rows.isEmpty {
                    Text(metricActivityAveragesEmptyText)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                } else {
                    // Identity is the row's position, never its activity or dates: the
                    // first row on one day has to *become* the first row on the next so
                    // its icon crossfades and its numbers roll over in place, where an
                    // activity- or date-keyed row would be torn down and replaced the
                    // moment the day's activities differ.
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            metricActivityAverageRow(row)

                            if index < rows.count - 1 {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                    // Only rows added or dropped at the end change the count; the ones
                    // that stay morph through their own animations above.
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0),
                        value: rows.count
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bodyCardBackground(translucent: true)
            .sheet(isPresented: $showsReadinessImpactExplanation) {
                BodyReadinessImpactExplanationSheet()
                    // Opens at half height, draggable to full.
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Invisible slop on all four sides of the Impact by Activity card's help button, so
    /// its 18 pt glyph still meets the 44 pt minimum target without changing the header.
    private static let activityImpactHelpTapSlop: CGFloat = 13

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
        let timeRangeText = activityAverageTimeRangeText(for: row)
        let valueText = model.valueFormatter(row.averageValue)

        return HStack(spacing: 12) {
            // The glyph is stacked rather than swapped in place: a symbol `Image`
            // ignores `contentTransition`, so the outgoing and incoming icons are
            // two views overlaid in the tile, dissolving into each other without
            // the row's height twitching.
            ZStack {
                Image(systemName: row.symbolName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(row.color(palette: workoutColorPalette))
                    .transition(.opacity)
                    .id(row.symbolName)
            }
            .frame(width: 38, height: 38)
            // Same continuous-corner tile as the Workouts page's workout-card
            // icons (18 pt radius at 58 pt, scaled to this 38 pt slot).
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(row.color(palette: workoutColorPalette).opacity(0.14))
            )
            // Keyed on the activity, not the glyph, so the tint and its tile also
            // cross over when two activities happen to share a symbol.
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0),
                value: row.activity.id
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: String.LocalizationValue(row.title)))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    // A name, like the source below: it crossfades on the same curve
                    // the icon beside it and the numbers opposite it settle on.
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .animation(
                        reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0),
                        value: row.title
                    )

                Text(timeRangeText)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .bodyLegendNumberFlip(value: timeRangeText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(valueText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(row.color(palette: workoutColorPalette))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .bodyLegendNumberFlip(value: valueText)

                if let source = row.source, !source.isEmpty {
                    Text(source)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        // A name, not a number: it dissolves while the reading beside it
                        // rolls, on the same curve.
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: source)
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

    /// Sleep and workout shading for the Stress intraday plot. Kept separate from
    /// `selectedMetricDayContextIntervals` (whose exact source text is guarded by
    /// `ProjectConfigurationTests`) but showing the same context: the main sleep
    /// session, each nap, and each workout explain a masked or Rest-banded stretch.
    private var selectedStressDayContextIntervals: [BodyHealthMetricDayContextInterval] {
        guard model.kind == .stress else {
            return []
        }

        let dayInterval = selectedMetricDayInterval
        var intervals: [BodyHealthMetricDayContextInterval] = []

        let stageSnapshot = sleepSummary(for: selectedMetricDay)?.stageSnapshot
        if let sleepInterval = stageSnapshot?.mainSession.dateInterval,
           let clipped = sleepInterval.clamped(to: dayInterval) {
            intervals.append(
                BodyHealthMetricDayContextInterval(
                    kind: .sleep,
                    startDate: clipped.start,
                    endDate: clipped.end,
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

        for workout in workouts(on: dayInterval) {
            // `duration` excludes paused time; the band must match the scoring
            // mask, which uses the workout's real end.
            let end = workout.effectiveEndDate
            guard let clipped = DateInterval(start: workout.startDate, end: end).clamped(to: dayInterval) else {
                continue
            }
            intervals.append(
                BodyHealthMetricDayContextInterval(
                    kind: .workout,
                    startDate: clipped.start,
                    endDate: clipped.end,
                    title: workoutStore.workoutCustomNames[workout.id] ?? workout.type.displayName,
                    symbolName: workout.type.symbolName,
                    color: workoutColorPalette.color(for: workout.type)
                )
            )
        }

        return intervals.sorted { $0.startDate < $1.startDate }
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
                    title: workoutStore.workoutCustomNames[workout.id] ?? workout.type.displayName,
                    symbolName: workout.type.symbolName,
                    color: workoutColorPalette.color(for: workout.type)
                )
            }
        }.compactMap { $0 })

        return intervals.sorted { $0.startDate < $1.startDate }
    }

    /// De-duplicated flatten of every cached month snapshot's workouts, shared by
    /// `workouts(on:)` and today's wake-cycle window. Memoized on the store's
    /// snapshot generation, so a progressive-refresh tick that leaves the
    /// workouts alone costs nothing.
    private var allCachedWorkouts: [WorkoutSummary] {
        workoutIndex.allWorkouts(
            in: workoutStore.monthSnapshots,
            generation: workoutStore.monthSnapshotsGeneration
        )
    }

    private func workouts(on dayInterval: DateInterval) -> [WorkoutSummary] {
        workoutIndex.workouts(
            on: dayInterval,
            in: workoutStore.monthSnapshots,
            generation: workoutStore.monthSnapshotsGeneration
        )
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
                    // Identity deliberately excludes the snapshot: a day switch
                    // must UPDATE the chart (its collapse-to-Core choreography
                    // runs from onChange), not replace it. Source switches
                    // still reset it.
                    .id("\(title)-\(sourceName ?? "default")")
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
        let restorativeText = BodyValueFormat.durationText(for: restorative)

        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(SleepStage.allCases.enumerated()), id: \.element) { index, stage in
                    if index > 0 {
                        Spacer(minLength: 8)
                    }

                    let durationText = BodyValueFormat.durationText(for: snapshot.duration(for: stage))

                    VStack(alignment: .center, spacing: 7) {
                        Rectangle()
                            .fill(stage.bodyChartColor)
                            .frame(width: 28, height: 3)

                        Text(durationText)
                            .font(.system(.callout, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                            .bodyLegendNumberFlip(value: durationText)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            Text("Restorative \(restorativeText)")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .bodyLegendNumberFlip(value: restorativeText)
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

    // Takes the whole-day snapshot and derives the naps itself, so callers stay
    // symmetric with `sleepStageCard`, which is handed the main session.
    private func napStageCard(_ snapshot: SleepStageSnapshot, sourceName: String? = nil) -> some View {
        let napsSnapshot = snapshot.napsSnapshot

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

            BodySleepStageChart(
                snapshot: napsSnapshot,
                axisMarkIntervals: snapshot.napSessions.compactMap(\.dateInterval)
            )
                .id("Nap Stages-\(sourceName ?? "default")")
                .transition(dayChartTransition)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .frame(height: BodyHealthDetailChartLayout.standardHeight)
                // No summary row here to carry the breakdown, so the chart itself
                // becomes the single VoiceOver element that spells it out.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(napStageBreakdownAccessibilityLabel(napsSnapshot))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bodyCardBackground(translucent: true)
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
                unit = "bpm"
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
        model.kind == .heartRate || model.kind == .heartRateVariability || model.kind == .oxygenSaturation || model.kind == .respiratoryRate || model.kind == .stress
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

    /// The untrimmed BMI history the chart itself needs to keep every range's
    /// marks resident; the range-limited series above still backs the average
    /// readout above the chart.
    private var bodyMassIndexTrend: HealthTrendSeries {
        model.basicsTrend?.bodyMassIndex ?? .empty
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
            .bodyLegendNumberFlip(value: text)
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

/// Scrub report-out for the metrics whose About card marks the band the touched
/// point falls in. An observable box read only by `BodyActiveTrendValueReader`,
/// so a scrub frame invalidates that one card instead of the whole detail page.
@Observable
final class BodyActiveTrendValueState {
    var readiness: Double?
    var trainingLoad: Double?
    var cardioFitness: Double?
}

/// Reads one scrubbed value inside its own body, so the observation stays off
/// the page body. `content` builds the About card from the value.
struct BodyActiveTrendValueReader<Content: View>: View {
    let state: BodyActiveTrendValueState
    let value: KeyPath<BodyActiveTrendValueState, Double?>
    @ViewBuilder let content: (Double?) -> Content

    var body: some View {
        content(state[keyPath: value])
    }
}

/// Memoizes the flatten of every cached month snapshot's workouts and the day
/// slices taken from it. `monthSnapshots` holds every month the user has
/// scrolled through, so the de-duplicating flatten is O(all cached workouts)
/// and the detail view takes several day slices per render.
@MainActor
final class BodyCachedWorkoutIndex: ObservableObject {
    /// Small enough that a day picker sweep never grows the cache unbounded,
    /// and large enough that one render's repeated slices all hit.
    private static let sliceCacheLimit = 8

    private var generation: Int?
    private var sortedWorkouts: [WorkoutSummary] = []
    private var slices: [DateInterval: [WorkoutSummary]] = [:]

    func allWorkouts(
        in monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot],
        generation: Int
    ) -> [WorkoutSummary] {
        refreshIfNeeded(monthSnapshots: monthSnapshots, generation: generation)
        return sortedWorkouts
    }

    func workouts(
        on dayInterval: DateInterval,
        in monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot],
        generation: Int
    ) -> [WorkoutSummary] {
        refreshIfNeeded(monthSnapshots: monthSnapshots, generation: generation)

        if let slice = slices[dayInterval] {
            return slice
        }

        if slices.count >= Self.sliceCacheLimit {
            slices.removeAll(keepingCapacity: true)
        }

        // `effectiveEndDate`, not `startDate + duration`: a paused workout's
        // wall-clock end runs past its accumulated duration, and the day
        // context and the warning exclusions must agree on which day it lands.
        let slice = sortedWorkouts.filter { workout in
            workout.startDate < dayInterval.end && workout.effectiveEndDate > dayInterval.start
        }
        slices[dayInterval] = slice
        return slice
    }

    private func refreshIfNeeded(
        monthSnapshots: [BodyWorkoutMonthKey: WorkoutMonthSnapshot],
        generation: Int
    ) {
        guard self.generation != generation else {
            return
        }

        var workoutsByID: [UUID: WorkoutSummary] = [:]
        for snapshot in monthSnapshots.values {
            for workout in snapshot.days.flatMap(\.workouts) {
                workoutsByID[workout.id] = workout
            }
        }
        sortedWorkouts = workoutsByID.values.sorted { $0.startDate < $1.startDate }
        slices.removeAll(keepingCapacity: true)
        self.generation = generation
    }
}

/// Memoizes every trend chart's per-range calendar points. Each morphing chart
/// derives points for ALL ranges (off-range dates stay resident as invisible
/// placeholder marks), which is the most expensive part of building the chart,
/// and the detail view rebuilds its charts on every progressive-refresh tick,
/// day selection and scroll.
@MainActor
final class BodyTrendRangePointsCache: ObservableObject {
    /// Which per-range derivation the consumer needs. Each case maps to the
    /// chart's own builder, so the cached points are byte-for-byte what the
    /// chart would have computed inline.
    enum Style: Hashable {
        case bars
        case line
        case sparseLine
        /// Weight and body fat, which share a Basics-specific point cap.
        case basicsLine
        /// The paired-bar aggregation the source-comparison charts use.
        case sourceComparison
    }

    /// One slot per consumer, so two charts on the same page never evict each
    /// other. Only one chart branch renders per metric, so the roles are enough.
    enum Slot: Hashable {
        case primary
        case secondary
        case weight
        case bodyFat
        case bodyMassIndex
    }

    private struct Key: Equatable {
        let style: Style
        let date: Date
        let series: HealthTrendSeries
    }

    private struct RangeKey: Equatable {
        let style: Style
        let date: Date
        let series: HealthTrendRangeSeries
    }

    private struct VitalsKey: Equatable {
        let date: Date
        let nights: [VitalsNightAssessment]
    }

    private var entriesBySlot: [Slot: (key: Key, points: [BodyHealthTrendRange: [HealthTrendCalendarPoint]])] = [:]
    private var rangeEntriesBySlot: [Slot: (key: RangeKey, points: [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]])] = [:]
    private var vitalsEntry: (key: VitalsKey, buckets: BodyVitalsOutlierRangeBuckets)?

    // `series ==` is the identity check; Array's COW fast path keeps the common
    // unchanged-render case O(1), since the series is usually the same buffer
    // as last render rather than a re-diffed copy.
    func points(
        for series: HealthTrendSeries,
        style: Style,
        date: Date,
        calendar: Calendar = .bodyGregorian,
        slot: Slot
    ) -> [BodyHealthTrendRange: [HealthTrendCalendarPoint]] {
        let key = Key(style: style, date: date, series: series)
        if let entry = entriesBySlot[slot], entry.key == key {
            return entry.points
        }

        let points: [BodyHealthTrendRange: [HealthTrendCalendarPoint]]
        switch style {
        case .bars:
            points = BodyHealthMetricTrendChart.makePointsByRange(
                series: series,
                chartStyle: .bar,
                usesSparseReadings: false,
                calendar: calendar,
                date: date
            )
        case .line:
            points = BodyHealthMetricTrendChart.makePointsByRange(
                series: series,
                chartStyle: .line,
                usesSparseReadings: false,
                calendar: calendar,
                date: date
            )
        case .sparseLine:
            points = BodyHealthMetricTrendChart.makePointsByRange(
                series: series,
                chartStyle: .line,
                usesSparseReadings: true,
                calendar: calendar,
                date: date
            )
        case .basicsLine:
            points = BodyBasicsTrendChart.makePointsByRange(for: series, calendar: calendar, date: date)
        case .sourceComparison:
            points = BodyHealthSourceComparisonBarChart.makePointsByRange(
                for: series,
                calendar: calendar,
                date: date
            )
        }
        entriesBySlot[slot] = (key, points)
        return points
    }

    func rangePoints(
        for series: HealthTrendRangeSeries,
        style: Style,
        date: Date,
        calendar: Calendar = .bodyGregorian,
        slot: Slot
    ) -> [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]] {
        let key = RangeKey(style: style, date: date, series: series)
        if let entry = rangeEntriesBySlot[slot], entry.key == key {
            return entry.points
        }

        let points: [BodyHealthTrendRange: [HealthTrendRangeCalendarPoint]]
        switch style {
        case .sourceComparison:
            points = BodyHealthSourceComparisonRangeChart.makePointsByRange(
                for: series,
                calendar: calendar,
                date: date
            )
        default:
            points = BodyHeartRateRangeTrendChart.makePointsByRange(
                for: series,
                calendar: calendar,
                date: date
            )
        }
        rangeEntriesBySlot[slot] = (key, points)
        return points
    }

    func vitalsRangeBuckets(
        nights: [VitalsNightAssessment],
        date: Date,
        calendar: Calendar = .bodyGregorian
    ) -> BodyVitalsOutlierRangeBuckets {
        let key = VitalsKey(date: date, nights: nights)
        if let vitalsEntry, vitalsEntry.key == key {
            return vitalsEntry.buckets
        }

        let buckets = BodyVitalsOutlierTrendChart.makeRangeBuckets(
            nights: nights,
            calendar: calendar,
            date: date
        )
        vitalsEntry = (key, buckets)
        return buckets
    }
}
