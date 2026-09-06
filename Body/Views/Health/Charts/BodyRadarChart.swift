//
//  BodyRadarChart.swift
//  Body
//
//  The Body Radar hero: the last three weeks of frozen nights as dots in three
//  stacked bands, Major on top and None at the bottom. Derived from the sleep
//  vitals region plot, so a night reads the same way a vital does there.
//

import Charts
import SwiftUI

enum BodyRadarChartStyle {
    /// Share of the plot taken by the Major band, and by the Minor one. The
    /// None band keeps the rest, the way Typical does in the vitals plot.
    static let signBandFraction = Double(BodyHealthDetailChartLayout.sleepVitalsOutlierBandFraction)
    /// Smallest top of the Major band's evidence scale, so a single extreme
    /// night can't flatten every other Major night against the band's floor.
    static let majorEvidenceCeiling = 5.0
    static let dotDiameter: CGFloat = 11
    /// Opacity of a night with no data or no verdict: the same ring, faded, on
    /// the chart and the card preview.
    static let placeholderOpacity = 0.35
    /// The bands themselves, sized so the hero stands as tall as every other
    /// detail chart once the date axis is added under the plot.
    static let axisHeight: CGFloat = 24
    /// Dotted horizontal rules for the plot edges and the band boundaries.
    static let ruleStyle = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 4])
    static let plotHeight = BodyHealthDetailChartLayout.standardHeight - axisHeight

    static func color(for region: BodyRadarRegion) -> Color {
        switch region {
        case .none:
            return .secondary
        case .minor:
            return BodyVitalsChartStyle.lowColor
        case .major:
            return .red
        }
    }
}

/// One plotted night: where its dot sits and how it is drawn.
struct BodyRadarChartPoint: Identifiable {
    let night: BodyRadarNight

    var id: Date {
        night.date
    }

    var isScored: Bool {
        night.state.isScored
    }

    /// Height inside the night's own band, 0 at its floor and 1 at its ceiling.
    /// An unscored night has no evidence, so it rests on the None band's floor.
    func bandPosition(majorCeiling: Double) -> Double {
        guard isScored else {
            return 0
        }

        switch night.region {
        case .none:
            return fraction(night.evidence, from: 0, to: BodyRadarCalculator.Tuning.minorEvidence)
        case .minor:
            return fraction(
                night.evidence,
                from: BodyRadarCalculator.Tuning.minorEvidence,
                to: BodyRadarCalculator.Tuning.majorEvidence
            )
        case .major:
            return fraction(night.evidence, from: BodyRadarCalculator.Tuning.majorEvidence, to: majorCeiling)
        }
    }

    /// The band the dot is drawn in, as a share of the plot measured from its
    /// bottom edge. An unscored night has no verdict, so it sits in None.
    var bandBounds: (floor: Double, ceiling: Double) {
        let band = BodyRadarChartStyle.signBandFraction

        switch isScored ? night.region : .none {
        case .major:
            return (1 - band, 1)
        case .minor:
            return (1 - band * 2, 1 - band)
        case .none:
            return (0, 1 - band * 2)
        }
    }

    /// The dot's height in the chart's hidden 0…1 scale: its band's slot, then
    /// its own height inside that band. Each band is inset by the dot's radius
    /// so a night at either extreme sits inside its band rather than astride
    /// the line.
    func plotValue(majorCeiling: Double) -> Double {
        let bounds = bandBounds
        let bandHeight = (bounds.ceiling - bounds.floor) * BodyRadarChartStyle.plotHeight
        let inset = Double(min(BodyRadarChartStyle.dotDiameter / 2, CGFloat(bandHeight) / 3))
            / Double(BodyRadarChartStyle.plotHeight)
        let floor = bounds.floor + inset
        let ceiling = bounds.ceiling - inset
        return floor + bandPosition(majorCeiling: majorCeiling) * (ceiling - floor)
    }

    private func fraction(_ value: Double, from lowerBound: Double, to upperBound: Double) -> Double {
        guard upperBound > lowerBound else {
            return 0
        }

        return min(max((value - lowerBound) / (upperBound - lowerBound), 0), 1)
    }
}

struct BodyRadarChart: View {
    let nights: [BodyRadarNight]
    /// Optional report-out of the scrub callout, so the immersive host can float it on
    /// the topmost layer (above the nav bar). Nil keeps the in-chart annotation.
    let floatingCallout: BodyChartFloatingCalloutState?

    @State private var selectedDate: Date?
    @GestureState private var isSelecting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(nights: [BodyRadarNight], floatingCallout: BodyChartFloatingCalloutState? = nil) {
        self.nights = nights
        self.floatingCallout = floatingCallout
    }

    var body: some View {
        Chart {
            // The plot's top and bottom edges and the two band boundaries are
            // all dotted horizontal rules; there is no box and no vertical line.
            ForEach(horizontalRules, id: \.self) { rule in
                RuleMark(y: .value("Band Boundary", rule))
                    .foregroundStyle(Color.secondary.opacity(0.28))
                    .lineStyle(BodyRadarChartStyle.ruleStyle)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected Date", slotCenter(for: selectedPoint)))
                    .foregroundStyle(Color.secondary.opacity(0.48))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected Date", slotCenter(for: selectedPoint)))
                    .foregroundStyle(Color.clear)
                    .annotation(
                        position: .top,
                        spacing: 8,
                        overflowResolution: bodyChartSelectionOverflowResolution
                    ) {
                        if floatingCallout == nil {
                            selectionAnnotation(for: selectedPoint)
                        }
                    }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...1)
        .chartPlotStyle { plot in
            plot
                .frame(height: BodyRadarChartStyle.plotHeight)
        }
        .chartXAxis {
            // Drawn at the plot's own edges, so neither end label is clipped;
            // the trailing one is still named for the last night, not for the
            // domain's exclusive end.
            AxisMarks(values: axisDates) { value in
                AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                    if let date = value.index == 0 ? nights.first?.date : nights.last?.date {
                        Text(dateText(for: date))
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        // The scale is evidence inside a band, not a readable number: the band
        // lines carry the reading on their own.
        .chartYAxis(.hidden)
        // The nights are laid over the plot rather than drawn as mark
        // annotations. Charts rebuilds annotation content on every render, so a
        // dot snapped to its new band and color instead of travelling there;
        // as ordinary SwiftUI views keyed by their own night they glide and
        // cross-fade the way the sleep vitals plot's dots do. It is also what
        // makes the three-week window shift read as motion: every night keeps
        // its view across a refresh, so the dots slide a slot left while the
        // night that fell out of the window fades and the new one fades in.
        .chartOverlay { chartProxy in
            GeometryReader { geo in
                if let plotFrame = chartProxy.plotFrame {
                    let plotRect = geo[plotFrame]

                    ForEach(points) { point in
                        if let x = chartProxy.position(forX: slotCenter(for: point)),
                           let y = chartProxy.position(forY: point.plotValue(majorCeiling: majorCeiling)) {
                            BodyRadarNightDot(point: point)
                                .position(x: plotRect.minX + x, y: plotRect.minY + y)
                                .transition(.opacity)
                        }
                    }
                }
            }
            // The scrub reads the plot underneath, so the dots must not take the
            // touch that drives it.
            .allowsHitTesting(false)
        }
        .chartXSelection(value: $selectedDate)
        .simultaneousGesture(chartPressGesture)
        .bodyFloatingCalloutReporter(
            floatingCallout,
            selectionDate: selectedPoint.map { slotCenter(for: $0) },
            centersOnDayInterval: false
        ) {
            guard let point = selectedPoint else {
                return AnyView(EmptyView())
            }
            return AnyView(selectionAnnotation(for: point))
        }
        .accessibilityLabel(Text("Body Radar nights"))
        .accessibilityValue(
            Text(
                String(
                    localized: "bodyRadar.chart.bandsDescription",
                    defaultValue: "Three stacked bands, tinted red for Major on top, pink for Minor in the middle, and plain for No signs at the bottom."
                )
            )
        )
        .id("body-radar")
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.45, extraBounce: 0),
            value: nights
        )
    }

    private var points: [BodyRadarChartPoint] {
        nights.map { BodyRadarChartPoint(night: $0) }
    }

    /// The Major band's ceiling floats up with the worst night on show, so a
    /// severe night still has room above the ones below it.
    private var majorCeiling: Double {
        max(nights.map(\.evidence).max() ?? 0, BodyRadarChartStyle.majorEvidenceCeiling)
    }

    /// One day-wide slot per night, so a dot lands in the middle of its own slot
    /// the way the hand-drawn plot spaced them.
    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.bodyGregorian
        guard let first = nights.first?.date, let last = nights.last?.date else {
            let today = calendar.startOfDay(for: Date())
            return today...(calendar.date(byAdding: .day, value: 1, to: today) ?? today)
        }

        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return first...end
    }

    private var axisDates: [Date] {
        guard let first = nights.first?.date, let last = nights.last?.date, first != last else {
            return nights.map(\.date)
        }

        let calendar = Calendar.bodyGregorian
        return [first, calendar.date(byAdding: .day, value: 1, to: last) ?? last]
    }

    /// Marks plot at the middle of the night's own day-wide slot, the way the
    /// hand-drawn plot spaced them across the width.
    static func slotCenter(for point: BodyRadarChartPoint) -> Date {
        point.night.date.addingTimeInterval(12 * 60 * 60)
    }

    private func slotCenter(for point: BodyRadarChartPoint) -> Date {
        Self.slotCenter(for: point)
    }

    private var horizontalRules: [Double] {
        [1, 1 - BodyRadarChartStyle.signBandFraction, 1 - BodyRadarChartStyle.signBandFraction * 2, 0]
    }

    private var selectedPoint: BodyRadarChartPoint? {
        guard isSelecting, let selectedDate else {
            return nil
        }

        return Self.nearestPoint(to: selectedDate, in: points)
    }

    /// The dot the scrub lands on. Compared against the slot center each dot is
    /// drawn at, not the night's midnight, so the boundary between two nights
    /// falls where the eye puts it.
    static func nearestPoint(to date: Date, in points: [BodyRadarChartPoint]) -> BodyRadarChartPoint? {
        points.min { first, second in
            abs(slotCenter(for: first).timeIntervalSince(date))
                < abs(slotCenter(for: second).timeIntervalSince(date))
        }
    }

    private func selectionAnnotation(for point: BodyRadarChartPoint) -> BodyRadarSelectionAnnotation {
        BodyRadarSelectionAnnotation(
            point: point,
            dateText: point.night.date.formatted(.dateTime.month(.abbreviated).day().year())
        )
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

    private func dateText(for date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The scrubbed night: its verdict, the signals that were flagged, and when.
struct BodyRadarSelectionAnnotation: View {
    let point: BodyRadarChartPoint
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(point.night.state.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            if point.isScored {
                if point.night.flaggedSignals.isEmpty {
                    Text(String(localized: "bodyRadar.card.allTypical", defaultValue: "All typical"))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(point.night.flaggedSignals) { signal in
                        HStack(spacing: 6) {
                            Image(systemName: signal.deviation >= 0 ? "arrow.up" : "arrow.down")
                                .foregroundStyle(BodyRadarChartStyle.color(for: point.night.region))
                                .accessibilityHidden(true)

                            Text(signal.kind.shortTitle)
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
            }

            Text(dateText)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .bodyChartSelectionAnnotationBackground()
    }
}

/// One night. A scored night takes its band's color; a night that could not be
/// scored keeps the muted placeholder ring so a gap never reads as "No signs".
struct BodyRadarNightDot: View {
    let point: BodyRadarChartPoint

    var body: some View {
        Circle()
            .fill(Color(.systemGroupedBackground))
            .overlay(
                Circle()
                    .stroke(ringColor, lineWidth: 4)
            )
            .shadow(color: ringColor.opacity(point.night.region == .none ? 0 : 0.26), radius: 5)
            .frame(width: BodyRadarChartStyle.dotDiameter, height: BodyRadarChartStyle.dotDiameter)
            // No data or no verdict: the same ring, faded, resting on the floor.
            .opacity(point.isScored ? 1 : BodyRadarChartStyle.placeholderOpacity)
            .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var ringColor: Color {
        BodyRadarChartStyle.color(for: point.night.region)
    }

    private var accessibilityLabel: String {
        "\(point.night.date.formatted(.dateTime.month(.abbreviated).day())), \(point.night.state.title)"
    }
}
