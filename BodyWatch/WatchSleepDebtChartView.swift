//
//  WatchSleepDebtChartView.swift
//  BodyWatch
//
//  The iPhone Sleep Debt card's line (`BodySleepDebtChart`), drawn onto the
//  Sleep detail page below the stages hypnogram: a header with the headline
//  debt, the 14 night debt as it stood after each of the last 14 nights on the
//  phone's fixed 0 to 6 hour scale, and weekday letters underneath. Same band
//  colors, dashed 2 and 4 hour rules, and line that blends from one night's
//  color to the next and breaks where a night has no debt; a night with no
//  sleep recorded fades its dot. Display-only: no selection or scrubbing. Reads
//  the snapshot's `sleepDebt`, which the phone pushes and the watch recomputes.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchSleepDebtChartView: View {
    let sleepDebt: WatchSleepDebt
    /// A night's color while its debt is low: the page's kind tint.
    let tint: Color

    /// Room right of the plot for the rule labels; the weekday row leaves the
    /// same room so its letters stay under the dots.
    private static let gutterWidth: CGFloat = 18
    private static let pointDiameter: CGFloat = 6
    private static let lineWidth: CGFloat = 2
    /// `BodySleepDebtChart`'s faded dot for a night with no sleep recorded
    /// whose debt still carries over from the nights before.
    private static let unrecordedOpacity = 0.35
    private static let ruleDurations = [SleepDebtChartModel.lowDebtUpperBound, SleepDebtChartModel.moderateDebtUpperBound]

    private var nights: [WatchSleepDebt.Night] { sleepDebt.nights }

    private var headlineText: String {
        sleepDebt.debt.map { BodyValueFormat.durationText(for: $0) } ?? "--"
    }

    private var headlineColor: Color {
        sleepDebt.debt.map { Self.bandColor(for: $0, lowColor: tint) } ?? .white.opacity(0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            plot
                .frame(maxHeight: .infinity)
            weekdayRow
                .padding(.trailing, Self.gutterWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("Sleep Debt")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(headlineText)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(headlineColor)
                .lineLimit(1)
        }
    }

    private var plot: some View {
        GeometryReader { proxy in
            let plotWidth = max(proxy.size.width - Self.gutterWidth, 1)
            let plotHeight = proxy.size.height

            ZStack(alignment: .topLeading) {
                rules(plotWidth: plotWidth, plotHeight: plotHeight)
                debtLine(plotWidth: plotWidth, plotHeight: plotHeight)
                markers(plotWidth: plotWidth, plotHeight: plotHeight)
            }
        }
    }

    /// Dashed rules at the 2 and 4 hour band edges, labeled in the gutter.
    @ViewBuilder
    private func rules(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        ForEach(Self.ruleDurations, id: \.self) { duration in
            let lineY = y(for: duration, plotHeight: plotHeight)

            Path { path in
                path.move(to: CGPoint(x: 0, y: lineY))
                path.addLine(to: CGPoint(x: plotWidth, y: lineY))
            }
            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            Text(BodyValueFormat.durationText(for: duration))
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.gutterWidth - 2, alignment: .trailing)
                .position(x: plotWidth + 2 + (Self.gutterWidth - 2) / 2, y: lineY)
        }
    }

    /// Lifted wherever a night has no debt, as on the phone. Each segment fades
    /// from its first night's band color to its second's.
    private func debtLine(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        Canvas { context, _ in
            var previous: (point: CGPoint, color: Color)?
            for (index, night) in nights.enumerated() {
                guard let debt = night.debt else {
                    previous = nil
                    continue
                }

                let point = CGPoint(x: columnCenterX(index, plotWidth: plotWidth), y: y(for: debt, plotHeight: plotHeight))
                let pointColor = Self.bandColor(for: debt, lowColor: tint)
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
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                    )
                }
                previous = (point, pointColor)
            }
        }
    }

    @ViewBuilder
    private func markers(plotWidth: CGFloat, plotHeight: CGFloat) -> some View {
        ForEach(Array(nights.enumerated()), id: \.offset) { index, night in
            if let debt = night.debt {
                Circle()
                    .fill(Self.bandColor(for: debt, lowColor: tint))
                    .frame(width: Self.pointDiameter, height: Self.pointDiameter)
                    .opacity(night.isRecorded ? 1 : Self.unrecordedOpacity)
                    .position(x: columnCenterX(index, plotWidth: plotWidth), y: y(for: debt, plotHeight: plotHeight))
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                Text(Self.weekdayLetter(for: night.day))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
        .textCase(.uppercase)
    }

    private var accessibilityLabel: String {
        guard sleepDebt.debt != nil else {
            return String(localized: "Sleep Debt, needs more data")
        }
        return String(localized: "Sleep Debt, \(headlineText)")
    }

    /// The phone's Body Radar Minor pink (`BodyVitalsChartStyle.lowRGB`), which
    /// is iOS-only.
    static let moderateColor = Color(red: 1.00, green: 0.55, blue: 0.75)

    /// A night's color by its debt band: `lowColor` under 2 hours, pink from 2
    /// through 4 hours, and red past 4. Mirrors `BodySleepDebtChart.bandColor`
    /// (Body/Views/Health/Charts/SleepDebtChart.swift), which is iOS-only.
    static func bandColor(for debt: TimeInterval, lowColor: Color) -> Color {
        if debt < SleepDebtChartModel.lowDebtUpperBound {
            return lowColor
        }
        if debt <= SleepDebtChartModel.moderateDebtUpperBound {
            return moderateColor
        }
        return .red
    }

    /// Inset by half a dot, so a point on the zero line or at the 6 hour cap
    /// isn't clipped.
    private func y(for debt: TimeInterval, plotHeight: CGFloat) -> CGFloat {
        let inset = Self.pointDiameter / 2 + 1
        let usableHeight = max(plotHeight - inset * 2, 1)
        let fraction = min(max(debt / SleepDebtChartModel.maximumDebt, 0), 1)
        return inset + CGFloat(1 - fraction) * usableHeight
    }

    private func columnCenterX(_ index: Int, plotWidth: CGFloat) -> CGFloat {
        let columnWidth = plotWidth / CGFloat(max(nights.count, 1))
        return columnWidth * (CGFloat(index) + 0.5)
    }

    /// Weekday letter for `date`, in the user's locale, with the
    /// complication's ASCII fallback.
    private static func weekdayLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        let fallback = ["S", "M", "T", "W", "T", "F", "S"]
        let source = symbols.count == 7 ? symbols : fallback
        let index = Calendar.current.component(.weekday, from: date) - 1
        guard source.indices.contains(index) else { return "" }
        return source[index]
    }
}

extension WatchSleepDebt {
    /// Nights ending today for previews: `debts` oldest first, with the
    /// nights in `unrecorded` marked as having no sleep recorded.
    static func preview(debts: [TimeInterval?], unrecorded: Set<Int> = [], headline: TimeInterval?) -> WatchSleepDebt {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nights = debts.enumerated().map { index, debt in
            Night(
                day: calendar.date(byAdding: .day, value: index - (debts.count - 1), to: today) ?? today,
                debt: debt,
                isRecorded: !unrecorded.contains(index)
            )
        }
        return WatchSleepDebt(debt: headline, nights: nights, computedAt: nil)
    }
}

#Preview("Bands, gap, unrecorded") {
    let hour: TimeInterval = 3_600
    let debts: [TimeInterval?] = [0.6 * hour, 1.1 * hour, 1.8 * hour, 2.4 * hour, nil, 2.9 * hour, 3.6 * hour, 4.6 * hour, 5.4 * hour, 4.8 * hour, 3.9 * hour, 3.1 * hour, 2.2 * hour, 1.7 * hour]
    return ZStack {
        Color.black.ignoresSafeArea()
        WatchSleepDebtChartView(
            sleepDebt: .preview(debts: debts, unrecorded: [8], headline: 1.7 * hour),
            tint: .indigo
        )
        .frame(height: 86)
        .padding(.horizontal, 8)
    }
}

#Preview("No headline") {
    let hour: TimeInterval = 3_600
    let debts: [TimeInterval?] = [nil, nil, nil, nil, nil, nil, nil, nil, nil, 0.8 * hour, 1.1 * hour, 0.4 * hour, nil, nil]
    return ZStack {
        Color.black.ignoresSafeArea()
        WatchSleepDebtChartView(
            sleepDebt: .preview(debts: debts, headline: nil),
            tint: .indigo
        )
        .frame(height: 86)
        .padding(.horizontal, 8)
    }
}
