//
//  SleepDebtChart.swift
//  Body
//
//  The Sleep Debt card's line: the 14 night debt as it stood after each of
//  the last 14 nights, over the same columns as the Sleep Consistency chart.
//  Each night's dot takes its debt band's color, and the line blends from one
//  night's color to the next. Tapping a column or its day label selects that
//  night. Holding on the plot
//  shows a callout for the night under the finger, as the other detail charts
//  do, without selecting it; only a stationary hold starts it, so a swipe that
//  starts on the chart still scrolls the page.
//

import SwiftUI

struct BodySleepDebtChart: View {
    let nights: [SleepDebtNight]
    let selectedDay: Date
    /// A night's color while its debt is low.
    let color: Color
    /// Where a hold publishes its callout; nil in previews.
    var floatingCallout: BodyChartFloatingCalloutState? = nil
    let onSelectDay: (Date) -> Void

    @State private var scrubbedDay: Date?
    @State private var calloutOwner = UUID()

    private let gutterWidth: CGFloat = 50
    private let dayLabelHeight: CGFloat = 30
    private let gutterLabelHeight: CGFloat = 14
    private let pointDiameter: CGFloat = 8
    private let selectedPointDiameter: CGFloat = 10
    /// Body Radar's faded ring for a night with no data: here, a night with
    /// no sleep recorded whose debt still carries over from the nights before.
    private let unrecordedOpacity = 0.35

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - gutterWidth, 1)
                let plotHeight = proxy.size.height

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        gridLines(plotWidth: plotWidth, plotHeight: plotHeight)
                        scrubRule(plotWidth: plotWidth, plotHeight: plotHeight)
                        debtLine(plotWidth: plotWidth, plotHeight: plotHeight)
                        markers(plotWidth: plotWidth, plotHeight: plotHeight)
                    }
                    .drawingGroup()

                    dayTapTargets(plotWidth: plotWidth, plotHeight: plotHeight)
                }
                .contentShape(Rectangle())
                .gesture(
                    BodyChartScrubGesture(isEnabled: nights.contains { $0.debtAfterNight != nil }) { location in
                        scrub(to: location, plotWidth: plotWidth, plotFrame: proxy.frame(in: .global))
                    }
                )
            }

            dayLabels
                .frame(height: dayLabelHeight)
                .padding(.trailing, gutterWidth)
        }
        .bodyChartScrubHaptics(selection: scrubbedDay)
        .onDisappear {
            clearScrub()
        }
    }

    /// A solid zero line, dashed rules at the 2 and 5 hour band edges, and a
    /// dashed top rule when a debt past 5 hours stretches the axis.
    @ViewBuilder
    private func gridLines(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        let zeroY = y(for: 0, plotHeight: plotHeight)

        horizontalLine(at: zeroY, width: plotWidth)
            .stroke(Color.secondary.opacity(0.28), lineWidth: 1)

        Text(0.formatted())
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Color.secondary)
            .position(x: plotWidth + gutterWidth / 2, y: gutterLabelY(forLineY: zeroY, plotHeight: plotHeight))

        ForEach(ruleDurations, id: \.self) { duration in
            let lineY = y(for: duration, plotHeight: plotHeight)

            horizontalLine(at: lineY, width: plotWidth)
                .stroke(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            Text(BodyValueFormat.durationText(for: duration))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.secondary)
                .position(x: plotWidth + gutterWidth / 2, y: gutterLabelY(forLineY: lineY, plotHeight: plotHeight))
        }
    }

    /// The held night's rule, as the other detail charts draw under a callout.
    @ViewBuilder
    private func scrubRule(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        if let index = scrubbedIndex {
            let x = columnCenterX(index, plotWidth: plotWidth)
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: plotHeight))
            }
            .stroke(Color.secondary.opacity(0.48), lineWidth: 1.4)
        }
    }

    /// Lifted wherever a night has no debt value, so the line never bridges a
    /// gap it can't account for. Each segment fades from its first night's
    /// band color to its second's; the round caps meet in the shared night's
    /// color, so the joins stay seamless.
    private func debtLine(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        Canvas { context, _ in
            var previous: (point: CGPoint, color: Color)?
            for (index, night) in nights.enumerated() {
                guard let debt = night.debtAfterNight else {
                    previous = nil
                    continue
                }

                let point = CGPoint(x: columnCenterX(index, plotWidth: plotWidth), y: y(for: debt, plotHeight: plotHeight))
                let pointColor = Self.bandColor(for: debt, lowColor: color)
                if let previous {
                    var segment = Path()
                    segment.move(to: previous.point)
                    segment.addLine(to: point)
                    context.stroke(
                        segment,
                        with: .linearGradient(
                            Gradient(colors: [previous.color, pointColor]),
                            startPoint: previous.point,
                            endPoint: point
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
                previous = (point, pointColor)
            }
        }
    }

    @ViewBuilder
    private func markers(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
            if let debt = night.debtAfterNight {
                let selected = isSelected(night.day)

                BodyLineChartPreviewPointSymbol(
                    tintColor: Self.bandColor(for: debt, lowColor: color),
                    isCurrent: selected,
                    pointDiameter: pointDiameter,
                    currentPointDiameter: selectedPointDiameter
                )
                .opacity(night.isRecorded || selected ? 1 : unrecordedOpacity)
                .position(x: columnCenterX(index, plotWidth: plotWidth), y: y(for: debt, plotHeight: plotHeight))
            }
        }
    }

    @ViewBuilder
    private func dayTapTargets(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        let columnWidth = plotWidth / CGFloat(max(nights.count, 1))

        ForEach(Array(nights.enumerated()), id: \.element.id) { index, night in
            Color.clear
                .frame(width: columnWidth, height: plotHeight)
                .contentShape(Rectangle())
                .position(x: columnCenterX(index, plotWidth: plotWidth), y: plotHeight / 2)
                .onTapGesture {
                    onSelectDay(night.day)
                }
                .accessibilityLabel(accessibilityLabel(for: night))
                .accessibilityAddTraits(isSelected(night.day) ? [.isButton, .isSelected] : .isButton)
        }
    }

    private var dayLabels: some View {
        HStack(spacing: 0) {
            ForEach(nights) { night in
                let selected = isSelected(night.day)

                VStack(spacing: 2) {
                    Text(night.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: selected ? .heavy : .semibold, design: .rounded))

                    // Bare day number, as on the Sleep Consistency chart: the
                    // locale-formatted day field adds a suffix in some languages.
                    Text(Calendar.bodyGregorian.component(.day, from: night.day).formatted(.number.grouping(.never)))
                        .font(.system(size: 12, weight: selected ? .heavy : .semibold, design: .rounded))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(selected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelectDay(night.day)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// A night's color by its debt band: `lowColor` under 2 hours, Body Radar's
    /// Minor pink from 2 through 5 hours, and its Major red past 5.
    static func bandColor(for debt: TimeInterval, lowColor: Color) -> Color {
        if debt < SleepDebtChartModel.lowDebtUpperBound {
            return lowColor
        }
        if debt <= SleepDebtChartModel.moderateDebtUpperBound {
            return BodyRadarChartStyle.color(for: .minor)
        }
        return BodyRadarChartStyle.color(for: .major)
    }

    /// The band edges, plus the stretched top when the debt passes 5 hours.
    private var ruleDurations: [TimeInterval] {
        var durations = [SleepDebtChartModel.lowDebtUpperBound, SleepDebtChartModel.moderateDebtUpperBound]
        if yUpperBound > SleepDebtChartModel.moderateDebtUpperBound {
            durations.append(yUpperBound)
        }
        return durations
    }

    /// At least 5 hours, so the moderate band's edge is always on the chart; a
    /// deeper debt rounds the top up to the next whole hour.
    private var yUpperBound: TimeInterval {
        let deepest = nights.compactMap(\.debtAfterNight).max() ?? 0
        return max(SleepDebtChartModel.moderateDebtUpperBound, (deepest / 3_600).rounded(.up) * 3_600)
    }

    /// Inset by half a selected marker, so a point on the zero line or the top
    /// rule isn't clipped by the rasterized layer.
    private func y(for debt: TimeInterval, plotHeight: CGFloat) -> CGFloat {
        let inset = selectedPointDiameter / 2 + 1
        let usableHeight = max(plotHeight - inset * 2, 1)
        let fraction = min(max(debt / yUpperBound, 0), 1)
        return inset + CGFloat(1 - fraction) * usableHeight
    }

    private func columnCenterX(_ index: Int, plotWidth: CGFloat) -> CGFloat {
        let columnWidth = plotWidth / CGFloat(max(nights.count, 1))
        return columnWidth * (CGFloat(index) + 0.5)
    }

    // MARK: - Scrubbing

    private var scrubbedIndex: Int? {
        scrubbedDay.flatMap { day in nights.firstIndex { $0.day == day } }
    }

    /// Calls out the plotted night nearest the finger. A hold never selects:
    /// only a tap changes the page's day, so no hold can open the paywall.
    private func scrub(to location: CGPoint?, plotWidth: CGFloat, plotFrame: CGRect) {
        guard let location,
              let index = nearestPlottedIndex(toX: location.x, plotWidth: plotWidth),
              let debt = nights[index].debtAfterNight else {
            clearScrub()
            return
        }

        scrubbedDay = nights[index].day
        floatingCallout?.publish(
            BodyChartFloatingCallout(
                anchor: CGPoint(x: plotFrame.minX + columnCenterX(index, plotWidth: plotWidth), y: plotFrame.minY),
                content: AnyView(
                    BodyChartSelectionAnnotation(
                        eyebrow: nil,
                        values: [
                            BodyChartSelectionValue(
                                title: nil,
                                value: BodyValueFormat.durationText(for: debt),
                                color: Self.bandColor(for: debt, lowColor: color)
                            )
                        ],
                        date: nights[index].day
                    )
                )
            ),
            owner: calloutOwner
        )
    }

    private func clearScrub() {
        scrubbedDay = nil
        floatingCallout?.clear(owner: calloutOwner)
    }

    /// The column under the finger, or the nearest one with a point: a night
    /// without a debt has nothing to call out, so the hold snaps past it.
    private func nearestPlottedIndex(toX x: CGFloat, plotWidth: CGFloat) -> Int? {
        let columnWidth = plotWidth / CGFloat(max(nights.count, 1))
        let column = min(max(Int(x / columnWidth), 0), max(nights.count - 1, 0))
        return nights.indices
            .filter { nights[$0].debtAfterNight != nil }
            .min { abs($0 - column) < abs($1 - column) }
    }

    private func isSelected(_ day: Date) -> Bool {
        Calendar.bodyGregorian.isDate(day, inSameDayAs: selectedDay)
    }

    /// Keeps a gutter label fully inside the plot, as on the Sleep Consistency
    /// chart: the rasterized layer clips at its bounds.
    private func gutterLabelY(forLineY lineY: CGFloat, plotHeight: CGFloat) -> CGFloat {
        guard plotHeight > gutterLabelHeight else {
            return plotHeight / 2
        }

        let inset = gutterLabelHeight / 2
        return min(max(lineY, inset), plotHeight - inset)
    }

    private func horizontalLine(at lineY: CGFloat, width: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: lineY))
        path.addLine(to: CGPoint(x: width, y: lineY))
        return path
    }

    private func accessibilityLabel(for night: SleepDebtNight) -> String {
        let dayText = night.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let needText = BodyValueFormat.durationText(for: night.needDuration)
        let label: String
        switch (night.actualDuration, night.debtAfterNight) {
        case let (actual?, debt?):
            label = String(localized: "\(dayText): slept \(BodyValueFormat.sleepDurationText(for: actual)), need \(needText), debt \(BodyValueFormat.durationText(for: debt))")
        case let (nil, debt?):
            label = String(localized: "\(dayText): no sleep recorded, debt \(BodyValueFormat.durationText(for: debt))")
        case let (actual?, nil):
            return String(localized: "\(dayText): slept \(BodyValueFormat.sleepDurationText(for: actual)), need \(needText)")
        case (nil, nil):
            return String(localized: "\(dayText): no sleep data")
        }

        guard night.recordedNightCount < SleepDebtChartModel.windowNightCount else {
            return label
        }
        return [label, String(localized: "Based on \(night.recordedNightCount) of 14 nights")].joined(separator: ". ")
    }
}
