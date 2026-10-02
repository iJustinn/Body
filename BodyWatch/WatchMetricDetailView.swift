//
//  WatchMetricDetailView.swift
//  BodyWatch
//
//  Immersive drill-down from a dashboard card (or a tapped complication): the
//  metric's fixed kind color washes the whole screen (the status-band color
//  appears only on the band highlight and the status label, matching the iOS
//  detail page), the title sits top-right, the recent-
//  week chart sits below it (on Heart Rate, HRV and Stress with each day's low
//  to high range under the line), and the current value reads large at the
//  bottom-left — followed, for Readiness, Training Load and Stress, by the
//  status level beside it ("85 · HIGH"; Readiness and Training Load also
//  highlight that level's band behind the week chart, Stress doesn't), and on
//  Sleep by the night's duration under the same dot ("85 pts · 7h 32m"). On the Sleep page, whenever the
//  snapshot carries
//  the night's stages or a Sleep Debt to chart, that first screen scrolls: the
//  week chart stays exactly where it is and the night's stages hypnogram
//  (`WatchSleepStagesChartView`) is added below the value row, reached by
//  scrolling down, followed by the last 14 nights' Sleep Debt line
//  (`WatchSleepDebtChartView`). The Training Load page scrolls the same way whenever the
//  snapshot carries the weekly workout minutes, adding the Weekly Workout Time
//  complication's bar chart (`WatchExerciseWeekChartView`) below its value row.
//  The Heart Rate and HRV pages scroll the same way whenever the watch has
//  readings from the last 8 hours, adding the "Last 8 hours" chart
//  (`WatchIntradayChartView`) below their value row. The Stress page scrolls
//  the same way whenever the snapshot's Stress timeline has a window in the
//  last 12 hours, adding its own "Last 12 hours" chart (`WatchStressChartView`)
//  below its value row.
//  The
//  tint fill is the page's own background so it slides with the vertical
//  pager, giving a smooth color transition between metrics. Display-only: it
//  reads the `weekly` series and its daily ranges, `statusBand`, sleep score, sleep stages, and
//  workout minutes the iPhone baked into the pushed snapshot, the Sleep Debt
//  the phone pushes or the watch recomputes, the Stress timeline likewise,
//  and the last 8 hours the watch reads itself (nothing is computed here).
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchMetricDetailView: View {
    let metric: WatchMetric
    /// The day the snapshot was generated on — `metric.weekly`'s last real
    /// slot. Used to re-window the series onto `referenceDate` when a cached
    /// snapshot is shown on a later day.
    var generatedAt: Date = Date()
    /// Today, the day the weekly series and its weekday labels should end on
    /// (a cached snapshot shown after midnight still labels "today", not the
    /// day it was generated).
    var referenceDate: Date = Date()
    /// The snapshot's `sleepStages` (the Sleep metric's night, main session
    /// only), drawn as a hypnogram below the Sleep page's info (the week chart
    /// stays). Ignored on every other page.
    var sleepStages: [WatchSleepStageSegment]? = nil
    /// The snapshot's `sleepDebt` (the last 14 nights' Sleep Debt), drawn as a
    /// line below the Sleep page's hypnogram; nil while the phone doesn't show
    /// Sleep Debt (the pager resolves `showsSleepDebt`). Ignored on every other
    /// page.
    var sleepDebt: WatchSleepDebt? = nil
    /// The snapshot's weekly workout minutes metric (the Weekly Workout Time
    /// complication's), drawn as bars below the Training Load page's info (the
    /// week chart stays). Ignored on every other page.
    var exerciseWeekMetric: WatchMetric? = nil
    /// The watch's own last 8 hours of readings for this kind (see
    /// `WatchIntradayChartStore`), drawn below the Heart Rate or HRV page's
    /// info (the week chart stays). Ignored on every other page.
    var intradayChart: WatchIntradayChart? = nil
    /// The snapshot's `stressTimeline` (the recent 15 minute Stress windows),
    /// drawn below the Stress page's info (the week chart stays). Ignored on
    /// every other page.
    var stressTimeline: WatchStressTimeline? = nil
    /// The snapshot's `workoutColorOverrides`, already resolved for Body Pro
    /// by the phone, for the workout shading on the Stress chart.
    var workoutColorOverrides: String? = nil

    /// The page theme (title, background wash, chart line): the metric's static
    /// kind color, matching the iOS detail page — never the status-band color.
    private var pageTint: Color { Color(WatchMetricKindKey.tint(forKind: metric.kind)) }
    /// The dynamic status color (band highlight, status label); falls back to
    /// the kind color for metrics without a status band.
    private var statusTint: Color { Color(metric.resolvedTint) }

    private var weekly: [Double?]? {
        Self.sparklineWeekly(metric: metric, generatedAt: generatedAt, today: referenceDate)
    }

    /// The weekly series for the sparkline, first re-windowed from the
    /// snapshot's generation day onto `today` (so a cached snapshot shown
    /// after midnight shifts its slots rather than mislabeling them). When
    /// the metric's own headline is cleared (`!hasValue`, e.g. a sleep night
    /// sanitized as not-today), today's slot is forced to nil so the chart
    /// doesn't show a value under a "--" headline (L-36); `cleared()` itself
    /// still keeps `weekly` for history.
    static func sparklineWeekly(metric: WatchMetric, generatedAt: Date, today: Date, calendar: Calendar = .current) -> [Double?]? {
        var weekly = metric.weeklyRewound(from: generatedAt, to: today, calendar: calendar)
        guard weekly.contains(where: { $0 != nil }) else { return nil }
        if !metric.hasValue, !weekly.isEmpty {
            weekly[weekly.count - 1] = nil
        }
        return weekly
    }

    /// Each day's low/high under the sparkline (Heart Rate and HRV), rewound
    /// onto `today` exactly like `sparklineWeekly` so every capsule stays
    /// under its own day's point. Today's slot follows the headline too: a
    /// cleared metric drops today's capsule along with today's point. Nil when
    /// no day has a range.
    static func sparklineRanges(metric: WatchMetric, generatedAt: Date, today: Date, calendar: Calendar = .current) -> [WatchDayRange?]? {
        var ranges = metric.weeklyRangesRewound(from: generatedAt, to: today, calendar: calendar)
        if !metric.hasValue, !ranges.isEmpty {
            ranges[ranges.count - 1] = nil
        }
        return ranges.contains(where: { $0 != nil }) ? ranges : nil
    }

    /// The status band highlighted behind the week chart: Readiness's and
    /// Training Load's. Stress names its band beside the value but draws its
    /// week as the daily averages and their ranges alone, so it has none.
    static func sparklineBand(for metric: WatchMetric) -> WatchStatusBand? {
        metric.kind == WatchMetricKindKey.stress ? nil : metric.statusBand
    }

    /// The night's 0–100 sleep score, as the iPhone baked it into the Sleep
    /// metric — nil when the phone's "Show Sleep Score" toggle is off, the
    /// night has no score, or the snapshot's sleep was cleared as not-today.
    /// Only the Sleep page reads it: Readiness already leads with its own
    /// score, and no other metric carries one.
    private var sleepScore: Int? {
        metric.kind == WatchMetricKindKey.sleep ? metric.score : nil
    }

    /// The Sleep page leads with the score and demotes the night's duration
    /// into the dot-separated slot the banded metrics use for their status
    /// level ("85 pts · 7h 32m"); scoreless nights keep the plain duration
    /// headline, and every other metric reads exactly as before.
    private var headlineValue: String {
        sleepScore.map { "\($0)" } ?? metric.displayValue
    }

    private var headlineUnit: String {
        sleepScore == nil ? metric.unit : String(localized: "pts")
    }

    /// The Sleep page's hypnogram segments, added below the page's info and
    /// making the page scroll, or nil (the page reads exactly like every other
    /// metric's) when the night's stages aren't in the snapshot: an un-synced
    /// or sanitized (no longer today) night, or a stage-less night.
    private var sleepStageSegments: [SleepStageSegment]? {
        guard metric.kind == WatchMetricKindKey.sleep, let sleepStages else { return nil }
        let segments = WatchSleepStagesChartView.segments(from: sleepStages)
        return segments.isEmpty ? nil : segments
    }

    /// The Sleep page's Sleep Debt, added below the hypnogram and making the
    /// page scroll, or nil (no section, and no scrolling for it) when the
    /// snapshot carries none or no night has a debt to plot yet.
    private var sleepDebtSection: WatchSleepDebt? {
        guard metric.kind == WatchMetricKindKey.sleep, let sleepDebt, sleepDebt.hasChartableNight else { return nil }
        return sleepDebt
    }

    /// The Training Load page's daily workout minutes, re-windowed onto
    /// `referenceDate` like the complication does, or nil (the page reads
    /// exactly like every other metric's) when the snapshot carries no workout
    /// minutes or a week with no data at all.
    private var exerciseWeekly: [Double?]? {
        guard metric.kind == WatchMetricKindKey.trainingLoad, let exerciseWeekMetric else { return nil }
        let weekly = exerciseWeekMetric.weeklyRewound(from: generatedAt, to: referenceDate)
        return weekly.contains(where: { $0 != nil }) ? weekly : nil
    }

    /// The Heart Rate or HRV page's last 8 hours, added below the page's info
    /// and making the page scroll, or nil (the page reads exactly like every
    /// other metric's) on any other page or when there are no readings.
    static func intradayChart(_ chart: WatchIntradayChart?, kind: String) -> WatchIntradayChart? {
        guard WatchIntradayChartStore.chartKinds.contains(kind), let chart, !chart.buckets.isEmpty else { return nil }
        return chart
    }

    private var visibleIntradayChart: WatchIntradayChart? {
        Self.intradayChart(intradayChart, kind: metric.kind)
    }

    /// The Stress page's timeline, added below the page's info and making the
    /// page scroll, or nil (the page reads exactly like every other metric's)
    /// on any other page or when no scored or movement window falls in the
    /// last 12 hours before `now` (a timeline that stopped advancing ages out
    /// here, so it needs no sanitize rule).
    static func stressTimeline(_ timeline: WatchStressTimeline?, kind: String, now: Date, calendar: Calendar = .current) -> WatchStressTimeline? {
        guard kind == WatchMetricKindKey.stress, let timeline,
              WatchStressChartView.hasVisibleMarks(timeline, endingAt: now, calendar: calendar) else { return nil }
        return timeline
    }

    private var visibleStressTimeline: WatchStressTimeline? {
        Self.stressTimeline(stressTimeline, kind: metric.kind, now: referenceDate)
    }

    private var trailingLabel: String? {
        guard sleepScore == nil else { return metric.displayValue }
        guard let label = metric.statusBand?.label else { return nil }
        return label.uppercased()
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            if sleepStageSegments != nil || sleepDebtSection != nil || exerciseWeekly != nil || visibleIntradayChart != nil
                || visibleStressTimeline != nil {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        pageContent
                            .containerRelativeFrame(.vertical, alignment: .topLeading)

                        if let sleepStageSegments {
                            WatchSleepStagesChartView(segments: sleepStageSegments)
                                .frame(height: 86)
                                .padding(.top, 10)
                                .padding(.bottom, 12)
                        }

                        if let sleepDebtSection {
                            WatchSleepDebtChartView(sleepDebt: sleepDebtSection, tint: pageTint)
                                .frame(height: 86)
                                .padding(.top, 10)
                                .padding(.bottom, 12)
                        }

                        if let exerciseWeekly {
                            WatchExerciseWeekChartView(weekly: exerciseWeekly, today: referenceDate, tint: pageTint)
                                .frame(height: 86)
                                .padding(.top, 10)
                                .padding(.bottom, 12)
                        }

                        if let visibleIntradayChart {
                            WatchIntradayChartView(chart: visibleIntradayChart, kind: metric.kind, tint: pageTint)
                                .frame(height: 86)
                                .padding(.top, 10)
                                .padding(.bottom, 12)
                        }

                        if let visibleStressTimeline {
                            WatchStressChartView(
                                timeline: visibleStressTimeline,
                                now: referenceDate,
                                palette: BodyWorkoutColorPalette(rawOverrides: workoutColorOverrides ?? "", isProUnlocked: true)
                            )
                            .frame(height: 86)
                            .padding(.top, 10)
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else {
                pageContent
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: - Pieces

    /// The page proper: title, week chart and big value row, sized to fill one
    /// full screen so the Sleep page's scrolling version opens on exactly the
    /// same first screen as every other metric.
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow

            if let weekly {
                WatchSparklineView(
                    values: weekly,
                    tint: pageTint,
                    band: Self.sparklineBand(for: metric),
                    bandTint: statusTint,
                    currentValue: metric.weeklyCurrentValue,
                    dayLabels: weekdayLabels(count: weekly.count),
                    ranges: Self.sparklineRanges(metric: metric, generatedAt: generatedAt, today: referenceDate)
                )
                .frame(height: 86)
                .padding(.top, 4)
            } else {
                Text("No recent data yet")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            }

            Spacer(minLength: 6)

            valueRow
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var titleRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(metric.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(pageTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Big current value at the bottom-left; for banded metrics the status level
    /// sits beside it, dot-separated ("85 · HIGH" / "1.23 · OPTIMAL"), and the
    /// Sleep page reads its score the same way ("85 pts · 7h 32m").
    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(headlineValue)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if !headlineUnit.isEmpty {
                Text(headlineUnit)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let label = trailingLabel {
                Text("·")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                Text(label)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer(minLength: 0)
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [pageTint.opacity(0.45), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Two-letter weekday abbreviations for the `count` days ending on
    /// `referenceDate` (oldest → newest), aligned with the chart's day slots.
    private func weekdayLabels(count: Int) -> [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let endDay = calendar.startOfDay(for: referenceDate)
        return (0..<count).map { offset in
            let day = calendar.date(byAdding: .day, value: offset - (count - 1), to: endDay) ?? endDay
            let weekday = calendar.component(.weekday, from: day)
            return String(symbols[(weekday - 1) % symbols.count].prefix(2))
        }
    }
}

#Preview("Training Load (banded)") {
    NavigationStack {
        WatchMetricDetailView(metric: WatchMetric(
            kind: WatchMetricKindKey.trainingLoad,
            title: "Load Ratio",
            displayValue: "1.23",
            unit: "",
            score: nil,
            fillFraction: 0.62,
            rawValue: 1.23,
            rangeMin: 0,
            rangeMax: 2,
            tint: WatchMetricColor(red: 0.10, green: 0.82, blue: 0.20),
            weekly: [0.95, 1.30, 1.05, 0.78, 1.32, 1.10, 1.23],
            statusBand: WatchStatusBand(min: 0.8, max: 1.3, label: "Optimal")
        ), exerciseWeekMetric: WatchMetricsSnapshot.placeholder.metric(forKind: WatchMetricKindKey.workoutMinutes))
    }
}

#Preview("Sleep (scored)") {
    let hour: TimeInterval = 3_600
    let debts: [TimeInterval?] = [0.6 * hour, 1.1 * hour, 1.8 * hour, 2.4 * hour, nil, 2.9 * hour, 3.6 * hour, 4.6 * hour, 5.4 * hour, 4.8 * hour, 3.9 * hour, 3.1 * hour, 2.2 * hour, 1.7 * hour]
    return NavigationStack {
        WatchMetricDetailView(
            metric: WatchMetric(
                kind: WatchMetricKindKey.sleep,
                title: "Sleep",
                displayValue: "7h 32m",
                unit: "",
                score: 85,
                fillFraction: 0.85,
                rawValue: 85,
                rangeMin: 0,
                rangeMax: 100,
                weekly: [6.5, 7.2, nil, 8.1, 7.0, 6.8, 7.53]
            ),
            sleepStages: WatchMetricsSnapshot.placeholder.sleepStages,
            sleepDebt: .preview(debts: debts, unrecorded: [8], headline: 1.7 * hour)
        )
    }
}

#Preview("Heart Rate") {
    NavigationStack {
        WatchMetricDetailView(metric: WatchMetric(
            kind: WatchMetricKindKey.heartRate,
            title: "Heart Rate",
            displayValue: "62",
            unit: "bpm",
            score: nil,
            fillFraction: 0.45,
            rawValue: 62,
            rangeMin: 54,
            rangeMax: 72,
            weekly: [58, 64, nil, 55, 72, 61, 62],
            weeklyRanges: [
                .init(low: 47, high: 131), .init(low: 49, high: 152), nil, .init(low: 46, high: 118),
                .init(low: 52, high: 166), .init(low: 48, high: 139), .init(low: 50, high: 127)
            ]
        ), intradayChart: .preview(kind: WatchMetricKindKey.heartRate))
    }
}

#Preview("HRV") {
    NavigationStack {
        WatchMetricDetailView(metric: WatchMetric(
            kind: WatchMetricKindKey.heartRateVariability,
            title: "HRV",
            displayValue: "44",
            unit: "ms",
            score: nil,
            fillFraction: 0.4,
            rawValue: 44,
            rangeMin: 30,
            rangeMax: 60,
            weekly: [41, 48, 39, nil, 52, 46, 44],
            weeklyRanges: [
                .init(low: 24, high: 66), .init(low: 29, high: 78), .init(low: 22, high: 61), nil,
                .init(low: 31, high: 84), .init(low: 27, high: 70), .init(low: 25, high: 68)
            ]
        ), intradayChart: .preview(kind: WatchMetricKindKey.heartRateVariability))
    }
}

#Preview("Stress") {
    NavigationStack {
        WatchMetricDetailView(metric: WatchMetric(
            kind: WatchMetricKindKey.stress,
            title: "Stress",
            displayValue: "42",
            unit: "",
            score: 42,
            fillFraction: 0.42,
            rawValue: 42,
            rangeMin: 0,
            rangeMax: 100,
            levelMin: 25.5,
            levelMax: 50.5,
            tint: WatchMetricColor(red: 0.20, green: 0.80, blue: 0.45),
            weekly: [38, 51, 44, nil, 35, 47, 42],
            weeklyRanges: [
                .init(low: 9, high: 78), .init(low: 12, high: 86), .init(low: 10, high: 74), nil,
                .init(low: 8, high: 69), .init(low: 11, high: 81), .init(low: 9, high: 82)
            ],
            statusBand: WatchStatusBand(min: 25.5, max: 50.5, label: "Relaxed")
        ), stressTimeline: .preview())
    }
}
