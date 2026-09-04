//
//  BodyHomeView.swift
//  Body
//

import Charts
import Observation
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

func bodyHealthDetailChartXDomain(for dates: [Date], selectedRange: BodyHealthTrendRange, immersive: Bool = false, immersivePairedBars: Bool = false, pairedBarComparison: Bool = false) -> ClosedRange<Date> {
    // Immersive charts hide the Y axis and fill the plot width. Pad each edge by about
    // half a data bucket so the first/last bar (or point) sits fully inside the plot
    // without clipping and no empty day appears. Non-immersive charts keep the small
    // leading padding and the larger right-side breathing room (room for the trailing
    // axis label).
    let leadingDatePadding: TimeInterval
    let trailingDatePadding: TimeInterval
    if immersive {
        let bucketSeconds = Double(selectedRange.chartAggregationDayCount) * 24 * 60 * 60
        if selectedRange == .recentWeek && !immersivePairedBars {
            // Week single-mark charts bias hard to the left: a little space on the left,
            // a bit more than a full day of breathing room on the right. Paired-bar
            // comparison charts keep symmetric padding — their two offset bars already
            // sit asymmetrically within the day.
            leadingDatePadding = 2 * 60 * 60
            trailingDatePadding = 26 * 60 * 60
        } else if !pairedBarComparison && selectedRange == .recentMonth {
            // Month charts keep a half-bucket (12h) leading nudge but stretch the trailing
            // edge to 28h of breathing room. Excludes the two-source paired-bar comparison
            // chart (it stays symmetric).
            leadingDatePadding = bucketSeconds * 0.5
            trailingDatePadding = 28 * 60 * 60
        } else if !pairedBarComparison && (selectedRange == .recentSixMonths || selectedRange == .recentYear) {
            // Six-month and year charts pin the first point or bar to the left wall (no
            // leading padding) and give the trailing edge one and a half buckets of
            // breathing room (9 days at six months, 18 days at year). Only the two-source
            // paired-bar comparison chart is excluded (it stays symmetric so its offset
            // outer bars aren't clipped); single-source charts and the line/range
            // comparison charts all get this.
            leadingDatePadding = 0
            trailingDatePadding = bucketSeconds * 1.5
        } else {
            let halfBucketPadding = bucketSeconds * 0.5
            leadingDatePadding = halfBucketPadding
            trailingDatePadding = halfBucketPadding
        }
    } else {
        leadingDatePadding = bodyHealthDetailChartLeadingDatePadding
        trailingDatePadding = bodyHealthDetailChartTrailingDatePadding(for: selectedRange)
    }

    guard let startDate = dates.min(), let endDate = dates.max() else {
        let now = Date()
        return now.addingTimeInterval(-leadingDatePadding)...now.addingTimeInterval(trailingDatePadding)
    }

    return startDate.addingTimeInterval(-leadingDatePadding)...endDate.addingTimeInterval(trailingDatePadding)
}

// Symbol area for a PointMark that renders a circle whose diameter matches a
// range bar's width, used to draw single-data-point days as a dot.
func bodyRangeChartPointSymbolSize(forBarWidth barWidth: CGFloat) -> CGFloat {
    .pi * pow(barWidth / 2, 2)
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
private func wristTemperatureBaselineValue(from finiteValues: [Double]) -> Double {
    let sorted = finiteValues.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

/// The chart-stable baseline median over the recent year, or `nil` when the
/// series has no finite values. The compression inside
/// `lineChartCalendarPoints` is the costly step — render paths should cache
/// the result (see `BodyHomeTrendComputationCache.wristTemperatureBaseline`).
func wristTemperatureBaselineIfAvailable(
    from series: HealthTrendSeries,
    calendar: Calendar = .bodyGregorian,
    date: Date = Date()
) -> Double? {
    let points = series.lineChartCalendarPoints(to: .recentYear, calendar: calendar, date: date)
    let finiteValues = points.compactMap(\.value).filter(\.isFinite)
    guard !finiteValues.isEmpty else {
        return nil
    }

    return wristTemperatureBaselineValue(from: finiteValues)
}

func wristTemperatureBaselineDeviationDisplay(
    currentCelsius: Double?,
    series: HealthTrendSeries,
    temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference
) -> BodyMetricDisplayValue {
    wristTemperatureBaselineDeviationDisplay(
        currentCelsius: currentCelsius,
        baseline: wristTemperatureBaselineIfAvailable(from: series),
        temperatureUnitPreference: temperatureUnitPreference
    )
}

func wristTemperatureBaselineDeviationDisplay(
    currentCelsius: Double?,
    baseline: Double?,
    temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference
) -> BodyMetricDisplayValue {
    guard
        let baseline,
        let current = currentCelsius,
        current.isFinite
    else {
        return BodyMetricDisplayValue(title: "Baseline", value: "--", unit: "")
    }

    // A temperature delta converts by scale only (1 °C of change = 1.8 °F of
    // change); the +32 offset of the absolute conversion must not be applied.
    let diffCelsius = current - baseline
    let diff = temperatureUnitPreference == .fahrenheit ? diffCelsius * 1.8 : diffCelsius
    let magnitude = BodyValueFormat.numberText(abs(diff), decimals: 1)
    let formattedValue: String
    if diff > 0.05 {
        formattedValue = "+\(magnitude)"
    } else if diff < -0.05 {
        formattedValue = "−\(magnitude)"
    } else {
        formattedValue = magnitude
    }

    return BodyMetricDisplayValue(
        title: "Baseline",
        value: formattedValue,
        unit: temperatureUnitPreference.unitLabel
    )
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
        return String(
            localized: "dateRange.sameMonth",
            defaultValue: "\(startMonth) \(startDay)-\(endDay), \(endYear)"
        )
    }

    if sameYear {
        return String(
            localized: "dateRange.sameYear",
            defaultValue: "\(startMonth) \(startDay)-\(endMonth) \(endDay), \(endYear)"
        )
    }

    return String(
        localized: "dateRange.differentYears",
        defaultValue: "\(startMonth) \(startDay), \(startYear)-\(endMonth) \(endDay), \(endYear)"
    )
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

/// Holds the home page's live scroll offset. Kept as a standalone `@Observable` so writing
/// it on each scroll frame only invalidates the views that actually read `offset` (the
/// readiness hero fade) instead of all of `BodyHomeView`, whose body rebuilds every metric
/// card model on every evaluation.
@Observable
private final class BodyHomeScrollState {
    var offset: CGFloat = 0
}

/// The card a readiness-hero warning badge last pointed at, glowing for a moment so
/// the scroll lands somewhere obvious. Its own `@Observable` for the same reason the
/// scroll offset is: only the grid's glow overlay reads it.
@Observable
private final class BodyHomeCardHighlightState {
    var card: BodyHomeCardKind?
}

/// The ring a card wears for a moment after a readiness-hero warning badge scrolled to
/// it. Reads the highlight state itself so only this small overlay re-renders when the
/// glow moves, not the grid that hosts it.
private struct BodyHomeCardHighlightGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let card: BodyHomeCardKind
    let highlightState: BodyHomeCardHighlightState
    let tint: Color

    private var isHighlighted: Bool {
        highlightState.card == card
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(tint.opacity(isHighlighted ? 0.9 : 0), lineWidth: 2)
            .shadow(color: tint.opacity(isHighlighted ? 0.7 : 0), radius: 12)
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isHighlighted)
    }
}

/// Applies the readiness hero's scroll fade and pin. It reads `scrollState.offset`, so this
/// small view re-renders as the page scrolls while `BodyHomeView`'s body does not.
private struct BodyReadinessHeroScrollFade<Content: View>: View {
    let scrollState: BodyHomeScrollState
    @ViewBuilder var content: Content

    private var opacity: Double {
        max(0, 1 - Double(scrollState.offset) / 70)
    }

    var body: some View {
        content
            // Stay put and fade out as the page scrolls up; fade back in at the top — it
            // pins via offset rather than scrolling away with the content.
            .opacity(opacity)
            .offset(y: min(scrollState.offset, 160))
            .allowsHitTesting(opacity > 0.1)
    }
}

/// Dims the fixed full-bleed star-hero backdrop as the page scrolls up — in step with the
/// hero number/text fade — so the translucent cards scrolling over it stay readable. Reads
/// `scrollState.offset` itself so only this layer re-renders per scroll frame, not all of
/// `BodyHomeView`.
private struct BodyHomeBackgroundScrollDim: View {
    let scrollState: BodyHomeScrollState

    private var opacity: Double {
        min(1, max(0, Double(scrollState.offset) / 70)) * 0.9
    }

    var body: some View {
        Color(.systemGroupedBackground)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}

/// Navigation route for Home → detail pushes. The section (`metric` grid/hero vs
/// `trend`) is part of the value so a grid card and a trend card of the same
/// `HealthMetricKind` — frequently both on screen — get distinct
/// `matchedTransitionSource` ids and each detail page zooms from its own card.
enum HomeMetricRoute: Hashable {
    case metric(HealthMetricKind)   // grid card or the readiness star hero
    case trend(HealthMetricKind)    // home trends section card
    case basicsTrend(HealthMetricKind)  // Basics detail page's Weight/Body Fat trend card — a distinct id from `.trend` so its zoom source doesn't collide with the same-kind home trends card one nav level below
    case activityRings              // activity rings card
}

struct BodyHomeView: View {
    @Environment(HealthKitWorkoutStore.self) private var workoutStore
    @AppStorage(BodyAppearancePreference.followsSystemUnitsKey) private var followsSystemUnits = true
    @AppStorage(BodyAppearancePreference.selectedWeightUnitKey) private var selectedWeightUnitRawValue = BodyValueFormat.WeightUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedEnergyUnitKey) private var selectedEnergyUnitRawValue = BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedTemperatureUnitKey) private var selectedTemperatureUnitRawValue = BodyValueFormat.TemperatureUnitPreference.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey) private var sleepDurationGoalMinutes = BodySleepDurationGoal.defaultMinutes
    @AppStorage(BodyAppearancePreference.showSleepScoreKey) private var showSleepScore = true
    @AppStorage(BodyAppearancePreference.homeCardOrderKey) private var homeCardOrderRawValue = BodyHomeCardKind.defaultRawValue
    @AppStorage(BodyAppearancePreference.summaryCardSelectionKey) private var summaryCardSelectionRawValue = BodySummaryCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var homeBackgroundEnabled = true
    @AppStorage(BodyAppearancePreference.homeBackgroundColorsKey) private var homeBackgroundColorsRawValue = ""
    @AppStorage(BodyAppearancePreference.homeBackgroundSeparatorsKey) private var homeBackgroundSeparatorsRawValue = ""
    @AppStorage(BodyAppearancePreference.defaultTrendRangeKey) private var defaultTrendRangeRawValue = BodyHealthTrendRange.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.homeTrendCardSelectionKey) private var homeTrendCardSelectionRawValue = BodyHomeTrendCardSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.showReadinessAICommentKey) private var showReadinessAIComment = true
    @AppStorage(BodyAppearancePreference.metricWarningsKey) private var metricWarningSelectionRawValue = BodyMetricWarningSelection.defaultRawValue
    @AppStorage(BodyAppearancePreference.metricWarningsOnReadinessHeroKey) private var showsWarningsOnReadinessHero = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.summaryReselectCount) private var summaryReselectCount
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(ReadinessCommentGenerator.self) private var readinessComment
    @State private var dragState = BodyHomeCardDragState()
    @State private var showsAllHomeTrends = false
    // Scroll offset lives in an @Observable so per-frame scroll updates only re-render the
    // hero fade wrapper that reads it — not this whole body. (The metric-card models are
    // additionally memoized in BodyHomeTrendComputationCache, keyed on their full input set.)
    @State private var scrollState = BodyHomeScrollState()
    // Which card a readiness-hero warning badge just scrolled to, held in its own
    // @Observable for the same reason as the scroll offset: setting it on this view
    // would rebuild every metric card model twice per tap.
    @State private var cardHighlightState = BodyHomeCardHighlightState()
    /// Clears the glow after its moment. Held so a second badge tap replaces the
    /// first one's countdown instead of racing it.
    @State private var cardHighlightTask: Task<Void, Never>?
    @StateObject private var trendComputationCache = BodyHomeTrendComputationCache()
    /// Shared namespace for the card → detail zoom transition (matchedTransitionSource +
    /// `.navigationTransition(.zoom)`). Threaded into `BodyHomeTrendsSection` for trends.
    @Namespace private var metricZoom
    /// Drives the Readiness star's detail presentation. The full-bleed hero has no card
    /// edges for a zoom to read cleanly from, so it cross-fades in/out as an overlay
    /// instead of pushing — see `readinessDetailOverlay`.
    @State private var readinessDetailPresented = false
    /// The metric detail hero charts publish their scrub callout here (an @Observable
    /// box, so per-scrub-frame updates re-render only the callout layer, not this body).
    /// Rendered as the topmost overlay below, above the nav bar's back chevron/title.
    @State private var heroChartCallout = BodyChartFloatingCalloutState()
    /// The width of the Home content column, measured from the layout rather than
    /// read off `UIScreen`: under Split View and Stage Manager the screen is wider
    /// than the page, and the metric cards sized their previews for a screen they
    /// did not have. Quantized to 8 pt so a resize drag does not rebuild every card
    /// model per point. Seeded from the foreground scene's width so the cards are
    /// built in the first body pass, before the readiness hero's appear animations
    /// start; a cold launch that waited for the measured width rebuilt every card
    /// model one frame later, on top of the hero's score roll, and stuttered it.
    /// The measured width still wins (Split View, Stage Manager, rotation). Zero
    /// only when no scene is connected yet, and the grid renders a placeholder then.
    @State private var homeContentWidth: CGFloat = BodyHomeView.initialContentWidthEstimate()

    /// Same quantization as the `onGeometryChange` below, applied to the scene width
    /// capped at the home column's maximum, which is what the layout measures on
    /// every phone and on a full-width iPad.
    private static func initialContentWidthEstimate() -> CGFloat {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let width = scene?.coordinateSpace.bounds.width, width > 0 else { return 0 }
        return (min(width, AppLayout.homeContentWidth) / 8).rounded(.up) * 8
    }

    var body: some View {
        let metricCardLookup = homeContentWidth > 0 ? metricCardsByKind : [:]
        // Derived once per body: the visible list, the "has trends" check and the
        // "Show all" affordance used to rebuild the card factory's output up to
        // three times per pass, on both layout paths.
        let trendCards = homeTrendCards

        return NavigationStack {
            // The page width comes from a GeometryReader, which always fills what the
            // navigation host proposes. On iPad (windowed apps, Stage Manager) the
            // vertical ScrollView reports its content's width as its own, so any width
            // derived from the scroll view or its ancestors (`containerRelativeFrame`,
            // `ScrollGeometry.containerSize`, measuring the ZStack) fed back into the
            // content pin and the page stuck at a stale width: a narrow centered column
            // in a wide window, overflow in a narrow one.
            GeometryReader { page in
            ZStack {
                homeBackground
                    .ignoresSafeArea()

                BodyHomeBackgroundScrollDim(scrollState: scrollState)
                    .ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 14) {
                            if let healthDataNotice = workoutStore.healthDataNotice {
                                BodyHealthNoticeBanner(message: healthDataNotice)
                            }

                            starMetricHero(proxy: scrollProxy, lookup: metricCardLookup)

                            if horizontalSizeClass == .regular {
                                HStack(alignment: .top, spacing: 14) {
                                    metricCardsGrid(lookup: metricCardLookup)
                                        .frame(maxWidth: .infinity, alignment: .top)

                                    if !trendCards.visible.isEmpty {
                                        homeTrendsContent(trendCards)
                                            .frame(maxWidth: .infinity, alignment: .top)
                                    }
                                }
                            } else {
                                metricCardsGrid(lookup: metricCardLookup)

                                homeTrendsSection(trendCards)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 110)
                        .readableContentColumn(maxWidth: AppLayout.homeContentWidth)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            // Rounded up to the next 8 pt: the preview sizing reads
                            // thresholds, so a sub-point difference must not churn
                            // the memoized card models.
                            (proxy.size.width / 8).rounded(.up) * 8
                        } action: { width in
                            homeContentWidth = width
                        }
                        // Pin the content to the page width: a vertical ScrollView becomes
                        // horizontally pannable as soon as its content reports even a fraction
                        // of a point wider than the viewport, which let the whole page drift
                        // sideways under a diagonal drag.
                        .frame(width: page.size.width)
                    }
                    .bodyPullToRefresh(isRefreshing: workoutStore.isRefreshing) {
                        Task { await workoutStore.requestAuthorizationAndRefresh() }
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        geometry.contentOffset.y + geometry.contentInsets.top
                    } action: { _, offset in
                        scrollState.offset = max(0, offset)
                    }
                }
            }
            .frame(width: page.size.width, height: page.size.height)
            }
            .accessibilityHidden(readinessDetailPresented)
            .navigationDestination(for: HomeMetricRoute.self) { route in
                switch route {
                case .metric(let kind), .trend(let kind), .basicsTrend(let kind):
                    BodyHealthMetricDetailView(
                        model: detailModel(for: kind),
                        initialTrendRange: defaultTrendRange,
                        zoomNamespace: metricZoom,
                        floatingCallout: heroChartCallout
                    )
                    .navigationTransition(.zoom(sourceID: route, in: metricZoom))
                case .activityRings:
                    BodyActivityRingsDetailView()
                        .navigationTransition(.zoom(sourceID: route, in: metricZoom))
                }
            }
        }
        // Readiness star: cross-fade its detail in/out over Home as an overlay instead of a
        // navigation push (SwiftUI has no fade push transition, and the full-bleed hero has
        // no card edges for a zoom to read cleanly from).
        .overlay {
            if readinessDetailPresented {
                readinessDetailOverlay
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
            }
        }
        // Scrub callouts float here, on the topmost layer — above both nav bars — so the
        // back chevron/title (UIKit chrome no page content can cover) can't draw over them.
        .overlay {
            BodyChartFloatingCalloutLayer(state: heroChartCallout)
        }
        // Re-tapping the Summary tab dismisses the Readiness overlay, mirroring how the
        // system pops a pushed detail to root (the overlay lives outside the nav stack).
        .onChange(of: summaryReselectCount) { _, _ in
            if readinessDetailPresented {
                dismissReadinessDetail()
            }
        }
        // Apple Intelligence readiness comment: generated (or read from cache) when the
        // score changes, when the setting flips, and on foreground so a comment written
        // yesterday refreshes after a day rollover. Never while a Health refresh is in
        // flight or before today's first clean refresh has landed — the summary is a
        // stale snapshot or mid-update then, so any comment would describe a
        // half-loaded score; the refresh's completion runs it instead.
        .task {
            refreshReadinessComment()
        }
        .onChange(of: workoutStore.healthSummary.readiness) { _, _ in
            refreshReadinessComment()
        }
        .onChange(of: showReadinessAIComment) { _, _ in
            refreshReadinessComment()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                refreshReadinessComment()
            }
        }
        .onChange(of: workoutStore.isRefreshing) { _, isRefreshing in
            if !isRefreshing {
                refreshReadinessComment()
            }
        }
        .onChange(of: workoutStore.lastSuccessfulRefreshDate) { _, _ in
            refreshReadinessComment()
        }
    }

    private var heroAIComment: BodyReadinessAIComment {
        guard showReadinessAIComment else { return .authored }
        if let comment = readinessComment.comment { return .comment(comment) }
        return readinessComment.isGenerating ? .generating : .authored
    }

    /// True once today's Health data has finished loading: not mid-refresh, and a
    /// clean full refresh has completed today (`lastSuccessfulRefreshDate` is
    /// restored from disk at launch, so a stale date means the on-screen summary
    /// is still yesterday's snapshot).
    private var readinessDataIsLoaded: Bool {
        guard !workoutStore.isRefreshing,
              let refreshed = workoutStore.lastSuccessfulRefreshDate else { return false }
        return Calendar.bodyGregorian.isDateInToday(refreshed)
    }

    private func refreshReadinessComment() {
        guard readinessDataIsLoaded else { return }
        readinessComment.refresh(
            for: workoutStore.healthSummary.readiness,
            enabled: showReadinessAIComment
        )
    }

    /// Hero press-and-hold: throw away today's comment and write a new one.
    private func regenerateReadinessComment() {
        guard readinessDataIsLoaded else { return }
        readinessComment.regenerate(
            for: workoutStore.healthSummary.readiness,
            enabled: showReadinessAIComment
        )
    }

    private var homeCardOrder: [BodyHomeCardKind] {
        BodyHomeCardKind.storedOrder(from: homeCardOrderRawValue)
    }

    private var starredHomeCard: BodyHomeCardKind? {
        BodyHomeCardKind.starredMetric(from: starredMetricRawValue)
    }

    private var visibleHomeCards: [BodyHomeCardKind] {
        // The starred metric is shown as the top hero, so exclude it from the grid via
        // an effective selection. Filtering the order won't work — `visibleOrder` repairs
        // missing cards back in. The persisted order is untouched, so reordering the
        // remaining cards is unaffected and the card returns to its slot when un-starred.
        let gridSelection = starredHomeCard.map { summaryCardSelection.setting($0, isEnabled: false) } ?? summaryCardSelection
        return BodyHomeCardKind.visibleOrder(from: homeCardOrder, visibleIn: gridSelection)
    }

    /// Today's frozen morning readiness (undrained, captured ~10 min after wake), read
    /// the same way as `BodyWorkoutsView`, so the hero can show where the day started
    /// once the live score drains below it.
    private var todaysMorningReadiness: Int? {
        let calendar = Calendar.bodyGregorian
        let today = calendar.startOfDay(for: Date())
        return workoutStore.healthTrends.recordedReadiness
            .first { calendar.startOfDay(for: $0.date) == today }?.score
    }

    /// The home-page star hero promoted above the grid. Readiness shows its score text
    /// here, over the full-bleed color backdrop supplied by `homeBackground` (which
    /// bleeds behind the status bar). Readiness is the only star-eligible metric.
    ///
    /// Takes the card lookup rather than reading `metricCardsByKind` itself: that
    /// property snapshots the whole summary and trend store to key its memo, and
    /// `body` has already paid for it once this pass.
    @ViewBuilder
    private func starMetricHero(
        proxy: ScrollViewProxy,
        lookup: [HealthMetricKind: BodyHealthMetricCard.Model]
    ) -> some View {
        switch starredHomeCard {
        case .readiness:
            let badges = heroWarningBadges(lookup: lookup)
            // The scroll fade/pin lives in the wrapper (which reads scrollState.offset) so
            // scrolling re-renders only it, not this body. Reading the offset here would
            // rebuild every metric card model on each scroll frame.
            BodyReadinessHeroScrollFade(scrollState: scrollState) {
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        readinessDetailPresented = true
                    }
                } label: {
                    BodyReadinessHeroLabel(
                        readiness: workoutStore.healthSummary.readiness,
                        morningScore: todaysMorningReadiness,
                        aiComment: heroAIComment,
                        onRegenerateAIComment: regenerateReadinessComment,
                        warningBadges: badges
                    )
                }
                .buttonStyle(.plain)
                // The badges draw inside the button's label — the only place they stay
                // aligned with the headline — but a nested button there never gets the
                // tap and a SwiftUI gesture fights this button (the reason the comment's
                // press-and-hold is a UIKit recognizer). So the tap targets are real
                // buttons laid over the glyphs from out here, where hit testing, the
                // button trait and VoiceOver all work normally. They sit inside the
                // fade wrapper, so they go inert with the hero as the page scrolls.
                .overlayPreferenceValue(BodyReadinessHeroBadgeAnchorKey.self) { anchors in
                    GeometryReader { geometry in
                        ForEach(badges) { badge in
                            if let anchor = anchors[badge.id] {
                                let frame = geometry[anchor]
                                Button {
                                    revealHomeCard(badge.card, proxy: proxy)
                                } label: {
                                    Color.clear.contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: badge.accessibilityLabel))
                                // Full height, glyph width: the row is narrow so the
                                // headline keeps its space, but a 28 pt-tall target is
                                // a mean thing to ask a thumb for. Widening it instead
                                // would overlap the neighbouring badge's target.
                                .frame(width: frame.width, height: max(frame.height, 44))
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    /// The warning signs the hero mirrors from the grid. Reads the visible card order so
    /// a card the user turned off contributes nothing, and there is nowhere for a badge
    /// to point that isn't on screen.
    private func heroWarningBadges(
        lookup: [HealthMetricKind: BodyHealthMetricCard.Model]
    ) -> [BodyReadinessHeroWarningBadge] {
        guard showsWarningsOnReadinessHero else {
            return []
        }

        return BodyReadinessHeroWarningBadge.badges(visibleCards: visibleHomeCards, lookup: lookup)
    }

    /// Scrolls the grid to a card and glows it for a moment, so a badge tap lands
    /// somewhere the eye can find.
    private func revealHomeCard(_ card: BodyHomeCardKind, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            // `BodyHomeCardKind.id` is its raw value, which is what the grid's
            // ForEach publishes — an explicit `.id()` on the card would give it a
            // second identity and is exactly what the flat-ForEach drag reorder
            // cannot survive.
            proxy.scrollTo(card.id, anchor: .center)
        }

        // Set plainly: the glow scopes its own fade, so an animation here would only
        // give the change a second, competing curve.
        cardHighlightTask?.cancel()
        cardHighlightState.card = card
        cardHighlightTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            cardHighlightState.card = nil
        }
    }

    /// The Readiness star's detail, presented as a full-screen cross-fade overlay rather
    /// than a navigation push (so it fades instead of zooming/sliding). Wrapped in its own
    /// NavigationStack for the title bar; the Back button and a swipe in from the left
    /// edge both dismiss it through `dismissReadinessDetail()`.
    private var readinessDetailOverlay: some View {
        NavigationStack {
            BodyHealthMetricDetailView(
                model: detailModel(for: .readiness),
                initialTrendRange: defaultTrendRange,
                floatingCallout: heroChartCallout
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismissReadinessDetail()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .simultaneousGesture(readinessEdgeBackGesture)
    }

    /// Stands in for the interactive pop the other detail pages get for free: this one
    /// isn't on a navigation stack that can pop, so the system's edge gesture never arms.
    /// Recognized simultaneously so it can't block the page's own scrolling or chart
    /// scrubbing, and it dismisses with the Back button's cross-fade rather than tracking
    /// the finger — the overlay has no slide-off transition to follow.
    private var readinessEdgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { value in
                guard Self.isEdgeBackSwipe(startX: value.startLocation.x, translation: value.translation) else {
                    return
                }

                dismissReadinessDetail()
            }
    }

    /// A drag counts as a back swipe when it starts within the system's edge-gesture
    /// strip, travels far enough to the right, and stays no steeper than 45° — so a
    /// scroll, a chart scrub, or a leftward drag never dismisses the page.
    static func isEdgeBackSwipe(startX: CGFloat, translation: CGSize) -> Bool {
        startX <= 20
            && translation.width >= 80
            && abs(translation.height) <= translation.width
    }

    private func dismissReadinessDetail() {
        withAnimation(.easeInOut(duration: 0.28)) {
            readinessDetailPresented = false
        }
    }

    /// Fixed full-bleed backdrop behind the scroll view: the custom Background
    /// color mix when enabled, otherwise the plain grouped background. The mix is
    /// auto-suppressed while Readiness is starred — that hero is colored by today's
    /// readiness level, so a separate background tint would clash.
    @ViewBuilder
    private var homeBackground: some View {
        if starredHomeCard == .readiness {
            // Readiness colors the top of Home directly — fixed, bleeding behind the
            // status bar, melting into the page — so it replaces the custom mix here.
            BodyReadinessHeroBackdrop(readiness: workoutStore.healthSummary.readiness)
        } else if homeBackgroundEnabled {
            let isPro = proStore?.isPro ?? false
            BodyActivityRingsCard.heroBackground(
                colors: BodyHomeBackground.proGatedColors(from: homeBackgroundColorsRawValue, isProUnlocked: isPro),
                separators: BodyHomeBackground.proGatedSeparators(from: homeBackgroundSeparatorsRawValue, isProUnlocked: isPro)
            )
        } else {
            Color(.systemGroupedBackground)
        }
    }

    /// The two-column grid of summary metric cards (identical on iPhone and iPad).
    ///
    /// One flat `ForEach` inside `BodyHomeCardGridLayout` rather than a `ForEach` of rows:
    /// a card keeps the same identity wherever it lands, so the reorder that runs while a
    /// drag is in flight moves the dragged card's view instead of destroying it.
    @ViewBuilder
    private func metricCardsGrid(lookup: [HealthMetricKind: BodyHealthMetricCard.Model]) -> some View {
        if homeContentWidth > 0 {
            BodyHomeCardGridLayout(spacing: 14) {
                ForEach(visibleHomeCards) { card in
                    reorderableHomeCard(for: card, lookup: lookup)
                        .bodyHomeCardSlots(card.slotCount)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: homeCardOrder)
        } else {
            // The width lands in the same layout pass that measures it, so this
            // placeholder holds the column open for one pass rather than showing.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 132)
        }
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

    /// The trends list without the leading section divider, shared by the iPhone
    /// (stacked below the metrics) and iPad (right-hand column) layouts.
    @ViewBuilder
    private func homeTrendsContent(_ cards: HomeTrendCards) -> some View {
        if !cards.visible.isEmpty {
            BodyHomeTrendsSection(
                cards: cards.visible,
                canToggleAll: cards.canToggleAll,
                showsAllTrends: showsAllHomeTrends,
                toggleAll: toggleAllHomeTrends,
                zoomNamespace: metricZoom
            )
        }
    }

    /// iPhone layout: trends stacked beneath the metrics with a divider separator.
    @ViewBuilder
    private func homeTrendsSection(_ cards: HomeTrendCards) -> some View {
        if !cards.visible.isEmpty {
            BodyHomeSectionDivider()
                .padding(.top, 8)

            homeTrendsContent(cards)
                .padding(.top, 8)
        }
    }

    private var metricCardsByKind: [HealthMetricKind: BodyHealthMetricCard.Model] {
        let inputs = metricCardsInputs
        return trendComputationCache.metricCards(inputs: inputs) {
            self.buildMetricCards(
                today: inputs.dayStart,
                metricWarningSelectionRawValue: inputs.metricWarningSelectionRawValue,
                previewDayCount: inputs.previewDayCount
            )
        }
    }

    /// Snapshot of every input `buildMetricCards()` reads, used as the memoization key.
    /// The locale covers `BodyValueFormat` text output, the time zone covers
    /// `.bodyGregorian` day bucketing, and `dayStart` invalidates on day rollover
    /// while the app stays foregrounded.
    private var metricCardsInputs: BodyHomeTrendComputationCache.MetricCardsInputs {
        BodyHomeTrendComputationCache.MetricCardsInputs(
            summary: workoutStore.healthSummary,
            trends: workoutStore.healthTrends,
            weightUnitPreference: selectedWeightUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference,
            temperatureUnitPreference: selectedTemperatureUnitPreference,
            showSleepScore: showSleepScore,
            sleepDurationGoalMinutes: sleepDurationGoalMinutes,
            dayStart: Calendar.bodyGregorian.startOfDay(for: Date()),
            previewDayCount: BodyHomeMetricCardPreview.dayCount(forScreenWidth: homeContentWidth),
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier,
            metricWarningSelectionRawValue: metricWarningSelectionRawValue
        )
    }

    private func buildMetricCards(
        today: Date,
        metricWarningSelectionRawValue: String,
        previewDayCount: Int
    ) -> [BodyHealthMetricCard.Model] {
        let summary = workoutStore.healthSummary
        let trends = workoutStore.healthTrends
        let warningSelection = BodyMetricWarningSelection.storedValue(from: metricWarningSelectionRawValue)

        return [
            readinessMetric(
                summary: summary.readiness,
                chartPreview: trends.series(for: .readiness),
                previewDayCount: previewDayCount
            ),
            stressMetric(
                summary: summary.stress,
                currentScore: summary.stressCurrentScore,
                chartPreview: trends.series(for: .stress),
                previewDayCount: previewDayCount
            ),
            bodyRadarMetric(summary: summary.bodyRadar),
            metric(
                kind: .exerciseMinutes,
                title: "Exercise Minutes",
                summary: summary.exerciseMinutes,
                chartStyle: .bar,
                chartPreview: trends.series(for: .exerciseMinutes),
                previewDayCount: previewDayCount
            ),
            metric(
                kind: .trainingLoad,
                title: "Training Load",
                summary: summary.trainingLoad,
                chartStyle: .line,
                chartPreview: trends.series(for: .trainingLoad),
                previewDayCount: previewDayCount
            ),
            wristTemperatureMetric(
                summary: summary,
                chartPreview: trends.series(for: .wristTemperature),
                previewDayCount: previewDayCount
            ),
            metric(
                kind: .timeInDaylight,
                title: "Time In Daylight",
                summary: summary.timeInDaylight,
                chartStyle: .bar,
                chartPreview: trends.series(for: .timeInDaylight),
                previewDayCount: previewDayCount
            ),
            metric(
                kind: .steps,
                title: "Steps",
                summary: summary.steps,
                chartStyle: .bar,
                chartPreview: trends.series(for: .steps),
                previewDayCount: previewDayCount
            ),
            sleepMetric(
                summary: summary,
                sleepHistory: trends.sleepHistory,
                chartPreview: trends.series(for: .sleep),
                today: today,
                previewDayCount: previewDayCount
            ),
            vitalsMetric(summary: summary, trends: trends, today: today),
            basicsMetric(summary: summary, chartPreview: trends.series(for: .bodyMass), previewDayCount: previewDayCount),
            metric(
                kind: .heartRate,
                title: "Heart Rate",
                summary: summary.heartRate,
                chartPreview: trends.series(for: .heartRate),
                warningSymbolName: warningSymbolName(for: .heartRate, summary: summary, selection: warningSelection),
                previewDayCount: previewDayCount
            ),
            metric(
                kind: .restingHeartRate,
                title: "Resting Heart Rate",
                summary: summary.restingHeartRate,
                chartPreview: trends.series(for: .restingHeartRate),
                previewDayCount: previewDayCount
            ),
            cardioFitnessMetric(summary: summary),
            metric(
                kind: .heartRateVariability,
                title: "HRV",
                summary: summary.heartRateVariability,
                chartPreview: trends.series(for: .heartRateVariability),
                previewDayCount: previewDayCount
            ),
            metric(
                kind: .oxygenSaturation,
                title: "Blood Oxygen",
                summary: summary.oxygenSaturation,
                chartPreviewStyle: .range,
                chartRangePreview: trends.rangeSeries(for: .oxygenSaturation),
                warningSymbolName: warningSymbolName(for: .oxygenSaturation, summary: summary, selection: warningSelection),
                previewDayCount: previewDayCount
            ),
            metric(
                kind: .respiratoryRate,
                title: "Respiratory Rate",
                summary: summary.respiratoryRate,
                chartPreviewStyle: .range,
                chartRangePreview: trends.rangeSeries(for: .respiratoryRate),
                previewDayCount: previewDayCount
            ),
            energyMetric(
                kind: .activeEnergy,
                title: "Active Energy",
                summary: summary.activeEnergy,
                chartPreview: trends.series(for: .activeEnergy),
                previewDayCount: previewDayCount
            ),
            energyMetric(
                kind: .restingEnergy,
                title: "Resting Energy",
                summary: summary.restingEnergy,
                chartPreview: trends.series(for: .restingEnergy),
                previewDayCount: previewDayCount
            )
        ]
    }

    /// The trend list plus the "Show all" affordance, derived together so `body`
    /// runs the card factory at most twice per pass instead of once per reader.
    struct HomeTrendCards {
        let visible: [BodyHomeTrendCard.Model]
        let canToggleAll: Bool
    }

    private var homeTrendCards: HomeTrendCards {
        let all = makeHomeTrendCards(includesStable: true)
        if showsAllHomeTrends {
            return HomeTrendCards(visible: all, canToggleAll: true)
        }

        let visible = Array(makeHomeTrendCards(includesStable: false).prefix(4))
        return HomeTrendCards(visible: visible, canToggleAll: all.count > visible.count)
    }

    private func makeHomeTrendCards(includesStable: Bool) -> [BodyHomeTrendCard.Model] {
        BodyHomeTrendCardFactory.cards(
            trends: workoutStore.healthTrends,
            selection: homeTrendCardSelection,
            temperatureUnitPreference: selectedTemperatureUnitPreference,
            energyUnitPreference: selectedEnergyUnitPreference,
            weightUnitPreference: selectedWeightUnitPreference,
            includesStable: includesStable,
            cache: trendComputationCache
        )
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

    private func warningSymbolName(
        for metric: HealthMetricKind,
        summary: HealthSummarySnapshot,
        selection: BodyMetricWarningSelection
    ) -> String? {
        let hasActiveWarning = summary.metricWarnings.contains { event in
            event.kind.metric == metric
                && selection.includes(event.kind)
                && Calendar.bodyGregorian.isDateInToday(event.startDate)
        }

        return hasActiveWarning ? "exclamationmark.triangle.fill" : nil
    }

    /// A summary card whose value is a plain number with a unit. Symbol, tint,
    /// unit and decimals come from the shared metric table, so the card, the
    /// trend card for the same metric and the widget that mirrors it cannot
    /// drift apart. Every kind routed through here has a `summaryFormat` row,
    /// so the fallbacks are unreachable (`HealthMetricPresentationTests`).
    private func metric(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        chartStyle: BodyHealthMetricChartStyle = .line,
        chartPreviewStyle: BodyHomeMetricCardPreview.Style? = nil,
        chartPreview: HealthTrendSeries? = nil,
        chartRangePreview: HealthTrendRangeSeries? = nil,
        warningSymbolName: String? = nil,
        previewDayCount: Int
    ) -> BodyHealthMetricCard.Model {
        let presentation = HealthMetricPresentation.presentation(for: kind)
        let summaryFormat = presentation?.summaryFormat
        return BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: summary.value.map {
                BodyValueFormat.numberText($0, decimals: summaryFormat?.decimals ?? 0)
            } ?? "--",
            unit: summaryFormat?.unitSuffix ?? "",
            symbolName: presentation?.symbolName ?? "questionmark.circle",
            symbolColor: presentation?.tint ?? .secondary,
            chartPreviewStyle: chartPreviewStyle ?? BodyHomeMetricCardPreview.Style.matching(chartStyle: chartStyle),
            chartPreview: chartPreview,
            chartRangePreview: chartRangePreview,
            warningSymbolName: warningSymbolName,
            previewDayCount: previewDayCount
        )
    }

    private func readinessMetric(
        summary: ReadinessSummary,
        chartPreview: HealthTrendSeries,
        previewDayCount: Int
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
            chartPreview: chartPreview,
            previewDayCount: previewDayCount
        )
    }

    private func stressMetric(
        summary: StressDaySummary?,
        currentScore: Int?,
        chartPreview: HealthTrendSeries,
        previewDayCount: Int
    ) -> BodyHealthMetricCard.Model {
        let scoreText = summary?.averageScore.map { "\($0)" } ?? "--"
        // Band follows the CURRENT stress reading when one is fresh (see
        // `stressCurrentScore`'s staleness guard), falling back to the day
        // average so the card still shows a band once any score exists.
        let bandScore = currentScore ?? summary?.averageScore
        let bandDisplay = bandScore.map { StressBand.band(for: $0) }.map {
            BodyMetricDisplayValue(title: "Band", value: $0.title, unit: "")
        }

        return BodyHealthMetricCard.Model(
            kind: .stress,
            title: "Stress",
            value: scoreText,
            unit: "",
            symbolName: "brain.head.profile.fill",
            symbolColor: Color(red: 0.90, green: 0.35, blue: 0.75),
            prominentMetrics: bandDisplay.map { [$0] } ?? [],
            chartPreviewStyle: .line,
            chartPreview: chartPreview,
            previewDayCount: previewDayCount
        )
    }

    /// Body Radar reads as a verdict rather than a number: one word for the band
    /// the night landed in, with the preview's ring showing where inside it, the
    /// way the Vitals card reads.
    private func bodyRadarMetric(summary: BodyRadarSummary?) -> BodyHealthMetricCard.Model {
        // Only a scored night in the Minor or Major band earns the badge.
        let warningRegion: BodyRadarRegion? = summary?.latest.flatMap { night in
            night.state.isScored && night.region != BodyRadarRegion.none ? night.region : nil
        }
        return BodyHealthMetricCard.Model(
            kind: .bodyRadar,
            title: "Body Radar",
            value: Self.bodyRadarCardValue(for: summary),
            unit: "",
            symbolName: BodyHomeCardKind.bodyRadar.iconName,
            symbolColor: BodyHomeCardKind.bodyRadar.tintColor,
            chartPreviewStyle: .dots,
            previewDotEntries: Self.bodyRadarDotEntries(for: summary),
            // Same three slots as Vitals, read top to bottom as Major / Minor /
            // None: fixed thresholds, so the bands stay equal; no standing
            // highlight, the verdict washes its own band; and the pending
            // skeleton shows the single ring the verdict will.
            dotPreviewHighlightedRegion: nil,
            dotPreviewEqualRegions: true,
            dotPreviewPlaceholderCount: 1,
            // Its own verdict, not a HealthKit warning event, so it doesn't go
            // through the metric-warning preference the heart cards read.
            warningSymbolName: warningRegion == nil ? nil : "exclamationmark.triangle.fill",
            warningColor: BodyRadarChartStyle.color(for: warningRegion ?? BodyRadarRegion.none),
            warningAccessibilityLabel: Self.bodyRadarCardValue(for: summary)
        )
    }

    /// One word, the band the night landed in, so the card reads at a glance
    /// the way the Vitals card does. A night with no verdict keeps its state's
    /// own word instead, and a missing summary (Sleep access off, so nothing can
    /// ever be scored) reads as No Data rather than a calibration that never ends.
    static func bodyRadarCardValue(for summary: BodyRadarSummary?) -> String {
        guard let summary else {
            return Self.bodyRadarNoDataTitle
        }

        switch summary.state {
        case .calibrating, .missingSleep:
            return summary.state.title
        case .noSigns:
            return String(localized: "Typical")
        case .minorSigns:
            return BodyRadarRegion.minor.title
        case .majorSigns:
            return BodyRadarRegion.major.title
        }
    }

    /// The preview reads like the Vitals one, with a single ring for the latest
    /// night: None rests in the typical band, Minor in the low region and Major
    /// in the high one, so the ring takes the same color the detail chart's dot
    /// does. A night with no data or no verdict shows the same ring faded on
    /// the floor; only a missing summary leaves the skeleton.
    /// Shown when there is no Body Radar summary at all, so no night can be
    /// scored and no calibration is under way.
    static var bodyRadarNoDataTitle: String {
        String(localized: "bodyRadar.state.noData", defaultValue: "No Data")
    }

    static func bodyRadarDotEntries(for summary: BodyRadarSummary?) -> [BodyHealthMetricCard.Model.DotEntry] {
        guard let summary, let latest = summary.latest else {
            return []
        }

        guard latest.state.isScored else {
            return [.init(
                position: 0.02,
                region: .low,
                tint: Color.secondary,
                opacity: BodyRadarChartStyle.placeholderOpacity
            )]
        }

        let position = BodyRadarChartPoint(night: latest)
            .bandPosition(majorCeiling: BodyRadarChartStyle.majorEvidenceCeiling)
        let third = 1.0 / 3.0
        // Held just inside each third so the ring never lands on the boundary
        // the preview reads the region from.
        let inset = 0.01

        // The preview's slots are the Vitals ones (low / typical / high, bottom
        // to top); Body Radar reads them as None / Minor / Major, so each ring
        // carries its own color and washes its own band. A typical night keeps
        // everything gray.
        switch latest.region {
        case .none:
            return [.init(
                position: position * (third - inset),
                region: .low,
                tint: Color.secondary
            )]
        case .minor:
            let color = BodyRadarChartStyle.color(for: .minor)
            return [.init(
                position: third + inset + position * (third - inset * 2),
                region: .typical,
                tint: color,
                bandTint: color
            )]
        case .major:
            let color = BodyRadarChartStyle.color(for: .major)
            return [.init(
                position: third * 2 + inset + position * (third - inset),
                region: .high,
                tint: color,
                bandTint: color
            )]
        }
    }

    private func energyMetric(
        kind: HealthMetricKind,
        title: String,
        summary: HealthMetricSummary,
        chartPreview: HealthTrendSeries,
        previewDayCount: Int
    ) -> BodyHealthMetricCard.Model {
        let presentation = HealthMetricPresentation.presentation(for: kind)
        let display = summary.value.map {
            BodyValueFormat.energyValue(kilocalories: $0, energyUnitPreference: selectedEnergyUnitPreference)
        }

        return BodyHealthMetricCard.Model(
            kind: kind,
            title: title,
            value: display.map {
                BodyValueFormat.numberText($0.value, decimals: presentation?.summaryFormat?.decimals ?? 0)
            } ?? "--",
            unit: selectedEnergyUnitPreference.unitLabel,
            symbolName: presentation?.symbolName ?? "questionmark.circle",
            symbolColor: presentation?.tint ?? .secondary,
            chartPreviewStyle: .bar,
            chartPreview: chartPreview.mapValues {
                BodyValueFormat.energyValue(
                    kilocalories: $0,
                    energyUnitPreference: selectedEnergyUnitPreference
                ).value
            },
            previewDayCount: previewDayCount
        )
    }

    private func wristTemperatureMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries,
        previewDayCount: Int
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
            title: "Skin Temperature",
            value: display?.value ?? "--",
            unit: display?.unit ?? temperatureUnit
        )
        let deviationDisplay = wristTemperatureBaselineDeviationDisplay(
            currentCelsius: summary.wristTemperature.value,
            baseline: trendComputationCache.wristTemperatureBaseline(from: chartPreview),
            temperatureUnitPreference: selectedTemperatureUnitPreference
        )

        return BodyHealthMetricCard.Model(
            kind: .wristTemperature,
            title: "Skin Temp",
            value: display?.value ?? "--",
            unit: display?.unit ?? temperatureUnit,
            symbolName: "thermometer.medium",
            symbolColor: Color(red: 0.00, green: 0.75, blue: 0.85),
            prominentMetrics: [deviationDisplay, actualDisplay],
            chartPreviewStyle: .line,
            chartPreview: chartPreview,
            previewDayCount: previewDayCount
        )
    }

    private func sleepMetric(
        summary: HealthSummarySnapshot,
        sleepHistory: SleepHistorySnapshot,
        chartPreview: HealthTrendSeries,
        today: Date,
        previewDayCount: Int
    ) -> BodyHealthMetricCard.Model {
        let todaySleep = summary.sleep.asOf(today)
        let prominentMetrics: [BodyMetricDisplayValue]
        if showSleepScore {
            let sleepScoreDisplay = todaySleep.flatMap {
                SleepScoreSummary(
                    sleep: $0,
                    idealSleepDuration: sleepDurationGoal,
                    recentSleepHistory: sleepHistory,
                    on: $0.stageSnapshot.date
                )
            }.map {
                BodyMetricDisplayValue(title: "Score", value: "\($0.total)", unit: "pts")
            } ?? BodyMetricDisplayValue(title: "Score", value: "--", unit: "")

            prominentMetrics = [
                sleepScoreDisplay,
                BodyMetricDisplayValue(
                    title: "Duration",
                    value: formattedSleepDuration(todaySleep?.duration),
                    unit: ""
                )
            ]
        } else {
            prominentMetrics = []
        }

        return BodyHealthMetricCard.Model(
            kind: .sleep,
            title: "Sleep",
            value: formattedSleepDuration(todaySleep?.duration),
            unit: "",
            symbolName: "bed.double.fill",
            symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
            prominentMetrics: prominentMetrics,
            chartPreview: chartPreview,
            previewDayCount: previewDayCount
        )
    }

    private func vitalsMetric(
        summary: HealthSummarySnapshot,
        trends: HealthTrendSnapshot,
        today: Date
    ) -> BodyHealthMetricCard.Model {
        // The card headline only needs the newest night, so the home grid takes
        // the cheap path instead of baselining every night in history.
        let assessment = VitalsCalculator.currentNightAssessment(
            sleepHistory: trends.sleepHistory,
            currentDaySleep: summary.sleep.asOf(today),
            today: today,
            calendar: .bodyGregorian
        )

        return BodyHealthMetricCard.Model(
            kind: .vitals,
            title: "Vitals",
            value: assessment?.statusText ?? "--",
            unit: "",
            symbolName: "heart.badge.bolt.fill",
            symbolColor: Color(red: 0.25, green: 0.62, blue: 1.00),
            chartPreviewStyle: .dots,
            previewDotEntries: assessment?.measurements.map { measurement in
                BodyHealthMetricCard.Model.DotEntry(
                    position: measurement.referenceRange.markerPosition(for: measurement.value),
                    region: measurement.region
                )
            } ?? []
        )
    }

    /// The headline is the reading itself, like every other numeric card. The
    /// level is carried by the preview's ring rather than by words: level names
    /// run long enough to truncate at card width ("Below Av…"), and the ring
    /// already says which of the four bands the reading landed in.
    private func cardioFitnessMetric(summary: HealthSummarySnapshot) -> BodyHealthMetricCard.Model {
        let value = summary.cardioFitness.value
        let profile = summary.cardioFitnessProfile

        return BodyHealthMetricCard.Model(
            kind: .cardioFitness,
            title: "Cardio Fitness",
            value: value.map { BodyValueFormat.numberText($0, decimals: 1) } ?? "--",
            unit: "VO₂ max",
            symbolName: "arrow.up.heart.fill",
            symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
            chartPreviewStyle: .levels,
            levelPreviewEntry: cardioFitnessLevelPreviewEntry(value: value, profile: profile)
        )
    }

    /// Where the reading sits inside its own level's band, which is what the
    /// preview's ring is placed by.
    private func cardioFitnessLevelPreviewEntry(
        value: Double?,
        profile: CardioFitnessProfile?
    ) -> BodyHealthMetricCard.Model.LevelEntry? {
        guard let value,
              let profile,
              let level = CardioFitnessLevel.level(for: value, profile: profile),
              let bounds = CardioFitnessLevel.bounds(for: level, profile: profile) else {
            return nil
        }

        // The lowest and highest bands are open-ended, so there is no span to
        // measure the reading against — the ring rests in the middle of the row.
        guard let lower = bounds.lower, let upper = bounds.upper, upper > lower else {
            return BodyHealthMetricCard.Model.LevelEntry(level: level, position: 0.5)
        }

        return BodyHealthMetricCard.Model.LevelEntry(
            level: level,
            position: min(max((value - lower) / (upper - lower), 0), 1)
        )
    }

    private func basicsMetric(
        summary: HealthSummarySnapshot,
        chartPreview: HealthTrendSeries,
        previewDayCount: Int
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
            symbolName: "figure.arms.open",
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
            chartPreview: chartPreview,
            previewDayCount: previewDayCount
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
            // `onDrag`'s closure runs while UIKit is building the drag session; writing
            // observed state here would re-evaluate this whole view at that moment, so the
            // dragged card is parked in an unobserved box instead.
            .onDrag {
                dragState.card = card
                return NSItemProvider(object: card.rawValue as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: BodyHomeCardDropDelegate(
                    destination: card,
                    dragState: dragState,
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
            // Outermost, after the drop: applied any earlier and the glow (and its
            // shadow) would be baked into UIKit's drag preview snapshot. The cost is
            // that it sits outside `matchedTransitionSource`, so tapping a glowing
            // card drops the glow as the zoom starts.
            .overlay {
                // The card's own accent, so the glow reads as that card lighting up
                // rather than a generic selection ring.
                BodyHomeCardHighlightGlow(
                    card: card,
                    highlightState: cardHighlightState,
                    tint: card.tintColor
                )
            }
    }

    @ViewBuilder
    private func homeCardView(
        for card: BodyHomeCardKind,
        lookup: [HealthMetricKind: BodyHealthMetricCard.Model]
    ) -> some View {
        switch card {
        case .activityRings:
            NavigationLink(value: HomeMetricRoute.activityRings) {
                BodyActivityRingsCard(summary: workoutStore.healthSummary.activityRings)
                    .matchedTransitionSource(id: HomeMetricRoute.activityRings, in: metricZoom) {
                        $0.clipShape(.rect(cornerRadius: 28, style: .continuous))
                    }
            }
            .buttonStyle(.plain)
        default:
            if let metricKind = card.healthMetricKind,
               let metric = lookup[metricKind] {
                NavigationLink(value: HomeMetricRoute.metric(metric.kind)) {
                    BodyHealthMetricCard(
                        metric: metric,
                        isRefreshing: workoutStore.isRefreshing,
                        containerWidth: homeContentWidth
                    )
                        .matchedTransitionSource(id: HomeMetricRoute.metric(metric.kind), in: metricZoom) {
                            $0.clipShape(.rect(cornerRadius: 28, style: .continuous))
                        }
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
                highlightedRangeResolver: BodyTrainingLoadIntervalPresentation.make(for:),
                trainingLoadValue: summary.trainingLoad.value
            )
        case .cardioFitness:
            // The hero stays numeric — the level name belongs to the band card
            // and the shaded chart region, the same split Training Load uses.
            return metricDetail(
                kind: kind,
                title: "Cardio Fitness",
                summary: summary.cardioFitness,
                unit: "VO₂ max",
                decimals: 1,
                symbolName: "arrow.up.heart.fill",
                symbolColor: Color(red: 1.00, green: 0.25, blue: 0.45),
                chartStyle: .line,
                highlightedRange: BodyCardioFitnessLevelPresentation.make(
                    for: summary.cardioFitness.value,
                    profile: summary.cardioFitnessProfile
                ),
                highlightedRangeResolver: {
                    BodyCardioFitnessLevelPresentation.make(
                        for: $0,
                        profile: summary.cardioFitnessProfile
                    )
                },
                // The level card classifies from the same snapshot the band
                // does, so the shaded region and the "Current" chip can't
                // disagree about which level the reading is in.
                cardioFitnessValue: summary.cardioFitness.value,
                cardioFitnessProfile: summary.cardioFitnessProfile
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
                title: "Skin Temperature",
                value: display?.value ?? "--",
                unit: display?.unit ?? temperatureUnit
            )
            let deviationDisplay = wristTemperatureBaselineDeviationDisplay(
                currentCelsius: summary.wristTemperature.value,
                series: trends.wristTemperature,
                temperatureUnitPreference: selectedTemperatureUnitPreference
            )
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Skin Temperature",
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
            let todaySleep = summary.sleep.asOf(Date())
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Sleep",
                value: formattedSleepDuration(todaySleep?.duration),
                unit: "",
                symbolName: "bed.double.fill",
                symbolColor: Color(red: 0.20, green: 0.72, blue: 1.00),
                series: trends.sleep,
                secondaryDaySeries: .empty,
                basicsTrend: nil,
                sleepStageSnapshot: todaySleep?.stageSnapshot,
                sleepScore: showSleepScore
                    ? todaySleep.flatMap {
                        SleepScoreSummary(
                            sleep: $0,
                            idealSleepDuration: sleepDurationGoal,
                            recentSleepHistory: trends.sleepHistory,
                            on: $0.stageSnapshot.date
                        )
                    }
                    : nil,
                sleepVitals: todaySleep?.vitals,
                sleepDuration: todaySleep?.duration,
                sleepHistory: trends.sleepHistory,
                sleepHistorySecondary: trends.sleepHistorySecondary,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.sleepDurationText(for: $0 * 60 * 60) },
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
                symbolName: "figure.arms.open",
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
                symbolColor: Color(red: 0.00, green: 0.62, blue: 0.70)
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
                sleepHistory: trends.sleepHistory,
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
        case .vitals:
            // Vitals has no metric series of its own — every chart and card on the
            // page is derived from the sleep history, so the model carries that and
            // the newest night's headline. The detail view baselines the full
            // history itself (memoized) for the trend chart.
            let today = Date()
            let assessment = VitalsCalculator.currentNightAssessment(
                sleepHistory: trends.sleepHistory,
                currentDaySleep: summary.sleep.asOf(today),
                today: today,
                calendar: .bodyGregorian
            )
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Vitals",
                value: assessment?.statusText ?? "--",
                unit: "",
                symbolName: "heart.badge.bolt.fill",
                symbolColor: Color(red: 0.25, green: 0.62, blue: 1.00),
                series: .empty,
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                sleepHistory: trends.sleepHistory,
                chartStyle: .bar,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
                secondaryValueFormatter: nil,
                helpText: kind.detailHelpText,
                dataSourceText: kind.detailDataSourceText
            )
        case .stress:
            let statusText: String
            if let band = summary.stress?.band {
                statusText = band.title
            } else if workoutStore.permissionSelection.includes(.heart), summary.heartRate.value != nil {
                // A quiet-HR baseline takes several days of heart data to
                // calibrate; until then `summary.stress` stays nil even though
                // heart data is flowing, so this reads as "still building" rather
                // than "no data at all".
                statusText = String(localized: "Calibrating")
            } else {
                statusText = String(localized: "stress.status.noData", defaultValue: "No Data")
            }

            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Stress",
                value: summary.stress?.averageScore.map { "\($0)" } ?? "--",
                unit: "",
                symbolName: "brain.head.profile.fill",
                symbolColor: Color(red: 0.90, green: 0.35, blue: 0.75),
                series: trends.stress,
                rangeSeries: trends.rangeSeries(for: kind),
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                highlightedRange: BodyStressBandPresentation.make(
                    for: summary.stress?.averageScore.map(Double.init)
                ),
                highlightedRangeResolver: BodyStressBandPresentation.make(for:),
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 0) },
                secondaryValueFormatter: nil,
                stress: summary.stress,
                headerMetrics: [
                    BodyMetricDisplayValue(
                        title: "Stress",
                        value: summary.stress?.averageScore.map { "\($0)" } ?? "--",
                        unit: ""
                    ),
                    BodyMetricDisplayValue(
                        title: "Status",
                        value: statusText,
                        unit: ""
                    )
                ],
                helpText: kind.detailHelpText,
                dataSourceText: kind.detailDataSourceText
            )
        case .bodyRadar:
            // Like Vitals, Body Radar has no metric series of its own: the page is
            // drawn from the nights the summary carries, so the model hands the
            // summary over and the detail view charts it.
            let radar = summary.bodyRadar
            return BodyHealthMetricDetailModel(
                kind: kind,
                title: "Body Radar",
                value: radar?.state.title ?? Self.bodyRadarNoDataTitle,
                unit: "",
                symbolName: BodyHomeCardKind.bodyRadar.iconName,
                symbolColor: BodyHomeCardKind.bodyRadar.tintColor,
                series: radar?.evidenceSeries() ?? HealthTrendSeries(points: []),
                basicsTrend: nil,
                sleepStageSnapshot: nil,
                sleepScore: nil,
                sleepVitals: nil,
                sleepDuration: nil,
                sleepHistory: trends.sleepHistory,
                chartStyle: .line,
                valueFormatter: { BodyValueFormat.numberText($0, decimals: 1) },
                secondaryValueFormatter: nil,
                bodyRadar: radar,
                helpText: kind.detailHelpText,
                dataSourceText: kind.detailDataSourceText
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
        trainingLoadValue: Double? = nil,
        cardioFitnessValue: Double? = nil,
        cardioFitnessProfile: CardioFitnessProfile? = nil,
        sleepHistory: SleepHistorySnapshot = .empty,
        valueTransform: @escaping @Sendable (Double) -> Double = { $0 }
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
            trainingLoadValue: trainingLoadValue,
            cardioFitnessValue: cardioFitnessValue,
            cardioFitnessProfile: cardioFitnessProfile,
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

/// The card a Home grid drag is carrying. A reference box rather than `@State` so that
/// recording it from `onDrag`, mid drag-session setup, does not invalidate `BodyHomeView`.
@MainActor
private final class BodyHomeCardDragState {
    var card: BodyHomeCardKind?
}

private struct BodyHomeCardDropDelegate: DropDelegate {
    let destination: BodyHomeCardKind
    let dragState: BodyHomeCardDragState
    let order: [BodyHomeCardKind]
    let saveOrder: ([BodyHomeCardKind]) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedCard = dragState.card, draggedCard != destination else {
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
        dragState.card = nil
        return true
    }
}

enum BodyHomeMetricCardPreview {
    static let previewDayCount = 4
    static let compactPreviewDayCount = 3
    static let regularPreviewDayCount = 5
    static let compactScreenMaximumWidth: CGFloat = 375
    static let regularScreenMinimumWidth: CGFloat = 700
    static let linePreviewWidth: CGFloat = 42
    static let barPreviewWidth: CGFloat = 42
    static let compactPreviewHeight: CGFloat = 42
    static let regularPreviewWidth: CGFloat = 50
    static let regularPreviewHeight: CGFloat = 50
    static let linePointDiameter: CGFloat = 6
    static let lineCurrentPointDiameter: CGFloat = 7

    enum Style: Equatable {
        case line
        case bar
        case range
        case dots
        case levels

        static func matching(chartStyle: BodyHealthMetricChartStyle) -> Style {
            switch chartStyle {
            case .line:
                return .line
            case .bar:
                return .bar
            }
        }
    }

    static func dayCount(forScreenWidth screenWidth: CGFloat) -> Int {
        guard screenWidth.isFinite, screenWidth > 0 else {
            return previewDayCount
        }

        if screenWidth >= regularScreenMinimumWidth {
            return regularPreviewDayCount
        }

        return screenWidth <= compactScreenMaximumWidth ? compactPreviewDayCount : previewDayCount
    }

    /// iPad-class screens (same threshold as the larger preview point count) get a roomier preview chart.
    static func isRegularPreviewWidth(_ screenWidth: CGFloat) -> Bool {
        screenWidth.isFinite && screenWidth >= regularScreenMinimumWidth
    }

    static func previewWidth(for style: Style, screenWidth: CGFloat) -> CGFloat {
        if isRegularPreviewWidth(screenWidth) {
            return regularPreviewWidth
        }

        switch style {
        case .line:
            return linePreviewWidth
        case .bar, .range, .dots, .levels:
            return barPreviewWidth
        }
    }

    static func previewHeight(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        isRegularPreviewWidth(screenWidth) ? regularPreviewHeight : compactPreviewHeight
    }

    static func calendarPoints(
        from series: HealthTrendSeries,
        previewDayCount: Int = Self.previewDayCount,
        calendar: Calendar = .bodyGregorian
    ) -> [HealthTrendCalendarPoint] {
        let count = max(previewDayCount, 1)
        let sortedPoints = series.points
            .filter { $0.value.isFinite }
            .sorted { $0.date < $1.date }
        let pointsByDay = Dictionary(grouping: sortedPoints) {
            calendar.startOfDay(for: $0.date)
        }

        return pointsByDay.keys
            .sorted()
            .suffix(count)
            .map { day in
                HealthTrendCalendarPoint(date: day, value: pointsByDay[day]?.last?.value)
            }
    }

    static func rangeCalendarPoints(
        from series: HealthTrendRangeSeries,
        previewDayCount: Int = Self.previewDayCount,
        calendar: Calendar = .bodyGregorian
    ) -> [HealthTrendRangeCalendarPoint] {
        let count = max(previewDayCount, 1)
        let sortedPoints = series.points
            .filter { $0.lowValue.isFinite && $0.highValue.isFinite }
            .sorted { $0.date < $1.date }
        let pointsByDay = Dictionary(grouping: sortedPoints) {
            calendar.startOfDay(for: $0.date)
        }

        return pointsByDay.keys
            .sorted()
            .suffix(count)
            .map { day in
                let point = pointsByDay[day]?.last
                return HealthTrendRangeCalendarPoint(
                    date: day,
                    lowValue: point?.lowValue,
                    highValue: point?.highValue,
                    averageValue: point?.averageValue?.isFinite == true ? point?.averageValue : nil
                )
            }
    }
}

enum BodyHomeTrendMessageStyle {
    case average(subject: String)
    case quantity(subject: String)

    func text(direction: BodyHomeTrendDirection, recentDayCount: Int) -> String {
        let phrase = BodyHomeTrendCardPresentation.recentPeriodPhrase(days: recentDayCount)
        switch self {
        case .average(let subject):
            let localizedSubject = String(localized: String.LocalizationValue(subject))
            return String(localized: "On average, \(localizedSubject) \(direction.averagePhrase) over the last \(phrase).")
        case .quantity(let subject):
            let localizedSubject = String(localized: String.LocalizationValue(subject))
            return String(localized: "\(localizedSubject) \(direction.quantityPhrase) over the last \(phrase).")
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
            return String(localized: "increased")
        case .decreased:
            return String(localized: "decreased")
        case .stable:
            return String(localized: "stayed about the same")
        }
    }

    var quantityPhrase: String {
        switch self {
        case .increased:
            return String(localized: "was higher")
        case .decreased:
            return String(localized: "was lower")
        case .stable:
            return String(localized: "stayed about the same")
        }
    }
}

struct BodyHomeTrendCardPresentation: Identifiable {
    static let minimumTrendSegmentDayCount = 3
    static let minimumRelativeChange = 0.01
    static let minimumAbsoluteChange = 0.01
    static let averageLineStrokeWidth: CGFloat = 4
    static let maximumDisplayPointCount = 60

    /// How many readings a sparse metric needs on each side of a comparison.
    ///
    /// `WindowSpec.minimumSegmentDayCount` doubles as both the shortest a segment may
    /// be and how many days in it must carry data. That holds for metrics recorded
    /// daily, but Cardio Fitness records one estimate per qualifying outdoor workout,
    /// so a 60-day segment might hold eight readings and could never reach the 30 the
    /// year window asks for. Left alone, even a weekly runner would never see the card
    /// at any window size. Sparse metrics keep the segment *length* rules and use this
    /// reading count instead — the same floor the 28-day window already applies.
    static let sparseMinimumSegmentReadingCount = 3

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
            kind: kind,
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
        kind: HealthMetricKind,
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
                minimumSegmentReadingCount: kind.usesSparseTrendReadings
                    ? min(spec.minimumSegmentDayCount, sparseMinimumSegmentReadingCount)
                    : spec.minimumSegmentDayCount,
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
            return String(localized: "\(days) days")
        } else if days < 90 {
            let weeks = max(1, Int((Double(days) / 7).rounded()))
            return String(localized: "\(weeks) weeks")
        } else {
            let months = max(1, Int((Double(days) / 30).rounded()))
            return String(localized: "\(months) months")
        }
    }

    static func averagePeriodText(days: Int) -> String {
        if days < 28 {
            return String(localized: "\(days)-day avg")
        } else if days < 90 {
            let weeks = max(1, Int((Double(days) / 7).rounded()))
            return String(localized: "\(weeks)-week avg")
        } else {
            let months = max(1, Int((Double(days) / 30).rounded()))
            return String(localized: "\(months)-month avg")
        }
    }

    private static func bestComparisonWindow(
        in calendarPoints: [HealthTrendCalendarPoint],
        spec: WindowSpec,
        minimumSegmentReadingCount: Int,
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

            guard baselineValues.count >= minimumSegmentReadingCount,
                  recentValues.count >= minimumSegmentReadingCount else {
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
        // The window covers full days ending yesterday: today's in-progress data
        // would bias the recent average low for cumulative metrics (steps, energy).
        let currentDayStart = calendar.startOfDay(for: date)
        let startDate = calendar.date(byAdding: .day, value: -dayCount, to: currentDayStart)
            ?? currentDayStart
        let endDate = currentDayStart
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

    /// The cached series is compared alongside the fingerprint instead of hashing
    /// every point into it: `==` on an unchanged array is an identity check, so a
    /// hit costs a pointer compare rather than an O(n) walk on every render, while
    /// a backdated edit to a non-edge day (manually editable Basics metrics:
    /// weight/body fat) still misses. The store's write counter is deliberately
    /// not part of the key: a refresh writes `healthTrends` several times per
    /// launch, and keying on the counter recomputed every card on each write even
    /// when the series came back equal, which stalled the hero animations.
    private struct Entry {
        let fingerprint: Fingerprint
        let series: HealthTrendSeries
        let result: BodyHomeTrendCardPresentation.WindowResult?
    }

    /// Full-equality snapshot of every input the metric-card build reads; an exact
    /// key, so the cached models can never go stale. Comparing the snapshots is
    /// COW-cheap because the cached copy shares buffers with the store's values
    /// until a refresh publishes new ones.
    struct MetricCardsInputs: Equatable {
        let summary: HealthSummarySnapshot
        let trends: HealthTrendSnapshot
        let weightUnitPreference: BodyValueFormat.WeightUnitPreference
        let energyUnitPreference: BodyValueFormat.EnergyUnitPreference
        let temperatureUnitPreference: BodyValueFormat.TemperatureUnitPreference
        let showSleepScore: Bool
        let sleepDurationGoalMinutes: Int
        let dayStart: Date
        let previewDayCount: Int
        let localeIdentifier: String
        let timeZoneIdentifier: String
        let metricWarningSelectionRawValue: String
    }

    /// Fingerprint of the sleep history the Vitals snapshot is derived from.
    /// Night count plus the edge dates catch a refresh that appends or trims a
    /// night; the content hash catches a night whose vitals were re-fetched in
    /// place (a late overnight sample landing hours after the night was filed).
    private struct VitalsFingerprint: Equatable {
        let dayStart: Date
        let dayCount: Int
        let firstTimestamp: TimeInterval?
        let lastTimestamp: TimeInterval?
        let contentHash: Int
    }

    private var entries: [CacheKey: Entry] = [:]
    private var wristTemperatureBaselineEntry: (fingerprint: Fingerprint, series: HealthTrendSeries, baseline: Double?)?
    private var vitalsSnapshotEntry: (fingerprint: VitalsFingerprint, snapshot: VitalsSnapshot)?
    private var metricCardsEntry: (inputs: MetricCardsInputs, cardsByKind: [HealthMetricKind: BodyHealthMetricCard.Model])?

    func result(
        for kind: HealthMetricKind,
        series: HealthTrendSeries,
        includesStable: Bool,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> BodyHomeTrendCardPresentation.WindowResult? {
        let fingerprint = Self.fingerprint(for: series, dayStart: calendar.startOfDay(for: date))
        let key = CacheKey(kind: kind, includesStable: includesStable)
        if let entry = entries[key], entry.fingerprint == fingerprint, entry.series == series {
            return entry.result
        }
        let result = BodyHomeTrendCardPresentation.bestWindowResult(
            from: series,
            kind: kind,
            includesStable: includesStable,
            calendar: calendar,
            date: date
        )
        entries[key] = Entry(fingerprint: fingerprint, series: series, result: result)
        return result
    }

    /// Memoizes the full set of summary metric-card models. Rebuilding them
    /// re-derives every card's preview point set (sort + day grouping over each
    /// series), so `body` only pays that cost when an input actually changes.
    func metricCards(
        inputs: MetricCardsInputs,
        build: () -> [BodyHealthMetricCard.Model]
    ) -> [HealthMetricKind: BodyHealthMetricCard.Model] {
        if let entry = metricCardsEntry, entry.inputs == inputs {
            return entry.cardsByKind
        }

        let cardsByKind = Dictionary(uniqueKeysWithValues: build().map { ($0.kind, $0) })
        metricCardsEntry = (inputs, cardsByKind)
        return cardsByKind
    }

    /// Memoizes the Skin Temperature baseline median — its stable-line
    /// compression is the most expensive per-render computation in the
    /// metric-card build, and the series only changes when a refresh lands.
    func wristTemperatureBaseline(
        from series: HealthTrendSeries,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> Double? {
        let fingerprint = Self.fingerprint(for: series, dayStart: calendar.startOfDay(for: date))
        if let entry = wristTemperatureBaselineEntry,
           entry.fingerprint == fingerprint,
           entry.series == series {
            return entry.baseline
        }

        let baseline = wristTemperatureBaselineIfAvailable(from: series, calendar: calendar, date: date)
        wristTemperatureBaselineEntry = (fingerprint, series, baseline)
        return baseline
    }

    /// Memoizes the Vitals snapshot. Building it walks every night in the sleep
    /// history and computes a robust baseline per vital per night — by far the
    /// most expensive derivation on the Vitals detail page, and one that only
    /// changes when a refresh publishes new sleep data.
    func vitalsSnapshot(
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        today: Date,
        calendar: Calendar = .bodyGregorian
    ) -> VitalsSnapshot {
        let fingerprint = Self.fingerprint(
            for: sleepHistory,
            currentDaySleep: currentDaySleep,
            dayStart: calendar.startOfDay(for: today)
        )
        if let entry = vitalsSnapshotEntry, entry.fingerprint == fingerprint {
            return entry.snapshot
        }

        let snapshot = VitalsCalculator.snapshot(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
            today: today,
            calendar: calendar
        )
        vitalsSnapshotEntry = (fingerprint, snapshot)
        return snapshot
    }

    private static func fingerprint(
        for sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        dayStart: Date
    ) -> VitalsFingerprint {
        var hasher = Hasher()
        for day in sleepHistory.days {
            hasher.combine(day.date)
            combine(&hasher, day.summary)
        }
        if let currentDaySleep {
            combine(&hasher, currentDaySleep)
        }
        return VitalsFingerprint(
            dayStart: dayStart,
            dayCount: sleepHistory.days.count,
            firstTimestamp: sleepHistory.days.first?.date.timeIntervalSinceReferenceDate,
            lastTimestamp: sleepHistory.days.last?.date.timeIntervalSinceReferenceDate,
            contentHash: hasher.finalize()
        )
    }

    /// Only the fields `VitalsCalculator` reads — hashing the whole summary would
    /// drag in the stage segments, which change far more often than the vitals.
    private static func combine(_ hasher: inout Hasher, _ summary: SleepSummary) {
        hasher.combine(summary.duration)
        hasher.combine(summary.vitals.heartRate)
        hasher.combine(summary.vitals.respiratoryRate)
        hasher.combine(summary.vitals.oxygenSaturation)
        hasher.combine(summary.vitals.wristTemperatureCelsius)
    }

    private static func fingerprint(for series: HealthTrendSeries, dayStart: Date) -> Fingerprint {
        Fingerprint(
            dayStart: dayStart,
            pointCount: series.points.count,
            firstTimestamp: series.points.first?.date.timeIntervalSinceReferenceDate,
            lastTimestamp: series.points.last?.date.timeIntervalSinceReferenceDate,
            firstValue: series.points.first?.value,
            lastValue: series.points.last?.value
        )
    }
}
