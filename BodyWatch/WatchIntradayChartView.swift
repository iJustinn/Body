//
//  WatchIntradayChartView.swift
//  BodyWatch
//
//  The "Last 8 hours" chart on the Heart Rate, HRV, Blood Oxygen, Steps and
//  Active Energy detail pages, drawn onto the page below its value row: a
//  header, then the rolling window in 30 minute slots with even local hours on
//  the bottom axis. Two styles share that frame. `.range` (Heart Rate, HRV,
//  Blood Oxygen): each slot's min to max range as a faint capsule under a
//  tinted line through the slot averages, broken where an hour or more has no
//  readings, and a ringed dot on every slot's average like the 7-day chart's,
//  the latest one solid. Blood Oxygen's value axis stops just above 100%
//  (`valueCeiling`), so no label reads past it. `.totals` (Steps, Active
//  Energy): a bar per slot from zero in the page color, nothing on an idle
//  slot, like the 7 day bars above it. Display-only: no selection or
//  scrubbing. Draws the chart it is handed: the one `WatchIntradayChartStore`
//  holds, or for Blood Oxygen the snapshot's (`WatchMetricDetailPager`). The
//  line breaks, value range and hour ticks come from
//  `WatchIntradayChartGeometry`, shared with the chart complications.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import Charts
import SwiftUI

struct WatchIntradayChartView: View {
    /// How a slot is drawn: Heart Rate, HRV and Blood Oxygen readings as a
    /// range under an average line, the daily total kinds as a bar of the
    /// slot's sum.
    enum Style: Equatable {
        case range
        case totals

        /// `.totals` for the daily total kinds (`WatchMetricKindKey.dailyTotalKinds`),
        /// `.range` for every other kind.
        static func style(forKind kind: String) -> Style {
            WatchMetricKindKey.dailyTotalKinds.contains(kind) ? .totals : .range
        }
    }

    let chart: WatchIntradayChart
    /// The line and dot color (`.range`) or the bar color (`.totals`): the
    /// page's kind tint.
    let tint: Color
    var style: Style = .range
    /// The highest value the metric can read (Blood Oxygen's 100%,
    /// `WatchMetricKindKey.valueCeiling`), which caps the `.range` value axis
    /// just above it; nil leaves the axis uncapped.
    var valueCeiling: Double? = nil

    /// Slots across the plot: the window plus the current slot.
    private static let slotCount = WatchIntradayWindow.length / WatchIntradayWindow.slotLength + 1
    private static let lineWidth: CGFloat = 2
    private static let pointDiameter: CGFloat = 5
    private static let latestPointDiameter: CGFloat = 7
    private static let pointRingWidth: CGFloat = 1.5
    private static let rangeColor = Color.white.opacity(0.28)

    private var xDomain: ClosedRange<Date> { chart.window.start...chart.window.plotEnd }

    private var latestBucket: WatchIntradayBucket? {
        chart.buckets.max { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Last 8 hours")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { proxy in
                switch style {
                case .range:
                    plot(capsuleWidth: Self.capsuleWidth(forPlotWidth: proxy.size.width))
                case .totals:
                    totalsPlot(barWidth: Self.barWidth(forPlotWidth: proxy.size.width))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Last 8 hours"))
    }

    /// `.totals`: one bar per slot, its sum, from the axis.
    private func totalsPlot(barWidth: CGFloat) -> some View {
        Chart {
            ForEach(chart.buckets, id: \.start) { bucket in
                BarMark(
                    x: .value("Time", bucket.midpoint),
                    y: .value("Total", bucket.average),
                    width: .fixed(barWidth)
                )
                .foregroundStyle(tint)
                .cornerRadius(2)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: Self.yDomain(for: chart, style: .totals))
        .chartXAxis { hourAxis }
        .chartYAxis { valueAxis }
    }

    private func plot(capsuleWidth: CGFloat) -> some View {
        Chart {
            ForEach(chart.buckets, id: \.start) { bucket in
                if bucket.minimum < bucket.maximum {
                    BarMark(
                        x: .value("Time", bucket.midpoint),
                        yStart: .value("Start", bucket.minimum),
                        yEnd: .value("End", bucket.maximum),
                        width: .fixed(capsuleWidth)
                    )
                    .foregroundStyle(Self.rangeColor)
                    .cornerRadius(capsuleWidth / 2)
                } else {
                    // A single reading: a zero length capsule, so a dot.
                    PointMark(x: .value("Time", bucket.midpoint), y: .value("Average", bucket.average))
                        .symbol {
                            Circle()
                                .fill(Self.rangeColor)
                                .frame(width: capsuleWidth, height: capsuleWidth)
                        }
                }
            }

            ForEach(Array(WatchIntradayChartGeometry.lineRuns(chart.buckets).enumerated()), id: \.offset) { _, run in
                ForEach(run, id: \.start) { bucket in
                    LineMark(
                        x: .value("Time", bucket.midpoint),
                        y: .value("Average", bucket.average),
                        series: .value("Time", run[0].start)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }

            // On top of the line: a ringed dot per slot average.
            ForEach(chart.buckets, id: \.start) { bucket in
                PointMark(x: .value("Time", bucket.midpoint), y: .value("Average", bucket.average))
                    .symbol { dot(isLatest: false) }
            }

            // Drawn last so the latest slot's solid dot covers its ringed one.
            if let latestBucket {
                PointMark(x: .value("Time", latestBucket.midpoint), y: .value("Average", latestBucket.average))
                    .symbol { dot(isLatest: true) }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: Self.yDomain(for: chart, style: .range, ceiling: valueCeiling))
        .chartXAxis { hourAxis }
        .chartYAxis { valueAxis }
    }

    /// Even local hours under the plot, shared by both styles.
    private var hourAxis: some AxisContent {
        AxisMarks(values: WatchIntradayChartGeometry.hourTicks(in: xDomain)) { value in
            AxisGridLine()
                .foregroundStyle(.white.opacity(0.18))
            AxisTick()
                .foregroundStyle(.white.opacity(0.28))
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    /// The value labels on the left, shared by both styles.
    private var valueAxis: some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine()
                .foregroundStyle(.white.opacity(0.18))
            AxisTick()
                .foregroundStyle(.white.opacity(0.28))
            AxisValueLabel {
                if let number = value.as(Double.self) {
                    Text(number, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    /// `WatchSparklineView`'s dots: ringed on black, the latest solid and larger.
    private func dot(isLatest: Bool) -> some View {
        let diameter = isLatest ? Self.latestPointDiameter : Self.pointDiameter
        return Circle()
            .fill(isLatest ? tint : Color.black)
            .overlay(Circle().stroke(tint, lineWidth: Self.pointRingWidth))
            .frame(width: diameter, height: diameter)
    }

    // MARK: - Geometry

    /// `.range`: spans every slot's range so no capsule clips, padded and
    /// clamped (`WatchIntradayChartGeometry.rangeDomain`, which the chart
    /// complications share), and with a `ceiling` stopped half a unit above
    /// it. `.totals`: from zero, so the bars grow from the axis, to the
    /// tallest bar plus the same 16 percent headroom; no ceiling applies.
    static func yDomain(for chart: WatchIntradayChart, style: Style = .range, ceiling: Double? = nil) -> ClosedRange<Double> {
        if style == .totals {
            let maximum = chart.buckets.map(\.average).filter(\.isFinite).max() ?? 0
            return 0...max(maximum * 1.16, 1)
        }
        return WatchIntradayChartGeometry.rangeDomain(for: chart.buckets, ceiling: ceiling)
    }

    /// About 62% of one slot's share of the plot, kept between 2 and 8 points.
    static func capsuleWidth(forPlotWidth width: CGFloat) -> CGFloat {
        min(max(width / slotCount * 0.62, 2), 8)
    }

    /// `.totals`: about 80% of one slot's share of the plot, kept between 3
    /// and 10 points, so neighbouring bars keep a gap.
    static func barWidth(forPlotWidth width: CGFloat) -> CGFloat {
        min(max(width / slotCount * 0.8, 3), 10)
    }
}

#Preview("Steps") {
    ZStack {
        Color.black.ignoresSafeArea()
        WatchIntradayChartView(
            chart: .preview(kind: WatchMetricKindKey.steps),
            tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.steps)),
            style: .totals
        )
        .frame(height: 86)
        .padding(.horizontal, 8)
    }
}

#Preview("Active Energy") {
    ZStack {
        Color.black.ignoresSafeArea()
        WatchIntradayChartView(
            chart: .preview(kind: WatchMetricKindKey.activeEnergy),
            tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.activeEnergy)),
            style: .totals
        )
        .frame(height: 86)
        .padding(.horizontal, 8)
    }
}

#Preview("Heart Rate") {
    ZStack {
        Color.black.ignoresSafeArea()
        WatchIntradayChartView(
            chart: .preview(kind: WatchMetricKindKey.heartRate),
            tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.heartRate))
        )
        .frame(height: 130)
        .padding(.horizontal, 8)
    }
}

#Preview("HRV") {
    ZStack {
        Color.black.ignoresSafeArea()
        WatchIntradayChartView(
            chart: .preview(kind: WatchMetricKindKey.heartRateVariability),
            tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.heartRateVariability))
        )
        .frame(height: 130)
        .padding(.horizontal, 8)
    }
}

#Preview("Blood Oxygen") {
    ZStack {
        Color.black.ignoresSafeArea()
        WatchIntradayChartView(
            chart: .preview(kind: WatchMetricKindKey.oxygenSaturation),
            tint: Color(WatchMetricKindKey.tint(forKind: WatchMetricKindKey.oxygenSaturation)),
            valueCeiling: WatchMetricKindKey.valueCeiling(forKind: WatchMetricKindKey.oxygenSaturation)
        )
        .frame(height: 130)
        .padding(.horizontal, 8)
    }
}
