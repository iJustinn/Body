//
//  WorkoutTypeBreakdownView.swift
//  Body
//

import SwiftUI

enum WorkoutTypeBreakdownDisplayStyle: Equatable {
    case app
    case widgetMedium
    case widgetLarge
    /// The month-summary share card: the app's type and bar widths on a leaner row, so
    /// a 360 pt exported card reads like the Workouts page rather than like a widget.
    case shareCard
}

struct WorkoutTypeBreakdownRowPresentation: Equatable {
    let titleText: String
    let detailText: String

    init(entry: WorkoutTypeBreakdown) {
        titleText = "\(entry.type.displayName) × \(entry.count)"
        detailText = BodyValueFormat.durationText(for: entry.duration)
    }
}

struct WorkoutTypeBreakdownView: View {
    let snapshot: WorkoutMonthSnapshot
    /// Resolved workout colors (built-in defaults plus any Pro customization). Rendered
    /// in both the app and the widget extension, so this is an explicit stored property
    /// rather than an `@Environment` read — the widget's timeline entry supplies its own
    /// entry-derived palette, which the environment can't carry across the process.
    let palette: BodyWorkoutColorPalette
    let style: WorkoutTypeBreakdownDisplayStyle
    let onSelectType: ((BodyWorkoutType) -> Void)?
    /// Nil in the widgets, which have no second chart to switch to — and which
    /// therefore lay out exactly as they did before this control existed.
    let onSwitchChart: (() -> Void)?
    /// A caller-imposed ceiling on the rows drawn, *below* the style's own — the
    /// share card knows how tall its chart region is and can't afford five rows on a
    /// 360 pt-tall ratio. Nil everywhere else, which leaves the style in charge.
    let rowLimit: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The rank-slot morph's chart snapshot: it drives the sort order, the bar widths
    /// and the bar colors, and is assigned inside a 0.45 s ease-in-out. Because the
    /// rows are keyed on their rank rather than on the activity, a re-ranking reads as
    /// bars traveling and colors morphing in place instead of the list reshuffling.
    @State private var displayedBreakdown: [WorkoutTypeBreakdown]?
    /// The same data on a second clock, feeding only the in-bar percentages. Assigned
    /// *outside* the animation above so the digits start rolling immediately while the
    /// bars are still on their way.
    @State private var displayedTextBreakdown: [WorkoutTypeBreakdown]?

    init(
        snapshot: WorkoutMonthSnapshot,
        palette: BodyWorkoutColorPalette,
        style: WorkoutTypeBreakdownDisplayStyle = .app,
        rowLimit: Int? = nil,
        onSelectType: ((BodyWorkoutType) -> Void)? = nil,
        onSwitchChart: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.palette = palette
        self.style = style
        self.rowLimit = rowLimit
        self.onSelectType = onSelectType
        self.onSwitchChart = onSwitchChart
    }

    /// Both morph snapshots stay nil until the first `.task` pass, and the widgets
    /// never run one — every read falls back to the live snapshot, so a widget renders
    /// exactly the data it was handed.
    private var chartBreakdown: [WorkoutTypeBreakdown] {
        Array((displayedBreakdown ?? snapshot.workoutTypeBreakdown).prefix(displayLimit))
    }

    private var textBreakdown: [WorkoutTypeBreakdown] {
        displayedTextBreakdown ?? snapshot.workoutTypeBreakdown
    }

    /// Percentages are taken against the sum of what the text snapshot holds, so the
    /// visible rows always add up to ~100%.
    private var distributionTotal: TimeInterval {
        textBreakdown.reduce(0) { $0 + $1.duration }
    }

    private var maxDuration: TimeInterval {
        chartBreakdown.map(\.duration).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rows
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: style == .app ? nil : .infinity,
            alignment: .topLeading
        )
        .task(id: snapshot.workoutTypeBreakdown) {
            publishBreakdown(snapshot.workoutTypeBreakdown)
        }
    }

    /// Hands the new arrangement to the two snapshots. The first fill and any hop in or
    /// out of the empty state land unanimated: there is no previous arrangement to morph
    /// from, and an intro sweep on appear is exactly what the rank-slot morph exists to
    /// avoid — a month switch already cross-fades the whole card.
    private func publishBreakdown(_ breakdown: [WorkoutTypeBreakdown]) {
        let hasPreviousArrangement = !(displayedBreakdown ?? []).isEmpty
        let morphs = hasPreviousArrangement && !breakdown.isEmpty && !reduceMotion

        withAnimation(morphs ? .easeInOut(duration: 0.45) : nil) {
            displayedBreakdown = breakdown
        }
        displayedTextBreakdown = breakdown
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.mixed.cardio")
                .font(.system(size: style == .widgetMedium ? 22 : 28, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.45))

            Text(String(localized: "No workouts yet", table: "BodyShared"))
                .font(.system(size: style == .widgetMedium ? 13 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: style == .widgetMedium ? 96 : 210)
    }

    @ViewBuilder
    private var rows: some View {
        if style == .app {
            rowStack
        } else {
            rowStack
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var rowStack: some View {
        let rows = chartBreakdown

        return VStack(alignment: .leading, spacing: rowSpacing) {
            if rows.isEmpty {
                emptyState

                // No last bar row to sit on, so the control keeps a row of its
                // own here — without it an empty month would strand the user on
                // this chart with no way back to the calendar.
                if let onSwitchChart {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        switchControlButton(onSwitchChart)
                    }
                }
            } else {
                // Keyed on the rank slot, never on the activity: row 1 stays row 1 and
                // its contents morph in place when the rankings change.
                ForEach(rows.indices, id: \.self) { index in
                    workoutTypeDistributionRow(
                        rows[index],
                        rank: index,
                        switchAction: index == rows.count - 1 ? onSwitchChart : nil
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    private func switchControlButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // The workout cards' own fill — `bodyCardBackground(translucent:)`
                // is `Color.primary.opacity(0.06)` — so the control never reads
                // as another activity type's bar.
                BodyGlassChip(color: .primary, cornerRadius: 12, fillOpacity: 0.06)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .bold))
                    // The calendar day numbers' grey, so both switch buttons
                    // read at the same weight.
                    .foregroundColor(.secondary)
            }
            .frame(width: switchControlSide, height: switchControlSide)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Show workout calendar", table: "BodyShared"))
        .accessibilityHint(String(localized: "Switches between the workout calendar and the activity breakdown", table: "BodyShared"))
    }

    private func workoutTypeDistributionRow(
        _ entry: WorkoutTypeBreakdown,
        rank: Int,
        switchAction: (() -> Void)? = nil
    ) -> some View {
        GeometryReader { geometry in
            // The control eats into the BAR's room, not the label's: the
            // shrink then scales with the bar itself, so a short last bar
            // barely moves while the full-width single-type case gives up
            // exactly the space the control needs.
            let reservedWidth = switchAction == nil ? 0 : switchControlSide + rowHorizontalSpacing
            let maxBarWidth = maximumBarWidth(for: geometry.size.width, reservedTrailingWidth: reservedWidth)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDuration > 0 ? entry.duration / maxDuration : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                HStack(spacing: rowHorizontalSpacing) {
                    percentageBar(entry, rank: rank)
                        .frame(width: barWidth, height: rowHeight)

                    workoutTypeDetails(entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Identity is the activity, so when a different one takes this
                        // slot the whole icon + name + duration group cross-fades old to
                        // new rather than swapping through a blank frame.
                        .id(entry.type)
                        .transition(.opacity)
                }
                // Scoped to the bar and label rather than the whole row, so the
                // control never doubles as this row's drill-down.
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    onSelectType?(entry.type)
                }

                if let switchAction {
                    switchControlButton(switchAction)
                }
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func percentageBar(_ entry: WorkoutTypeBreakdown, rank: Int) -> some View {
        let percentage = percentage(atRank: rank)

        return ZStack(alignment: .leading) {
            BodyGlassChip(color: palette.color(for: entry.type), cornerRadius: barCornerRadius)

            // Verbatim: an interpolated `Text` would register `%lld%%` as a
            // localizable key, and the percentage is the same in every language.
            Text(verbatim: "\(percentage)%")
                .font(.system(size: percentageFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.82))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(style.isWidget ? 0.68 : 0.75)
                .padding(.horizontal, 16)
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(percentage)))
                .animation(reduceMotion ? nil : .snappy(duration: 0.38, extraBounce: 0), value: percentage)
                // The label rides inside a bar that is traveling under the 0.45 s morph.
                // Under Reduce Motion nothing may move, so the inherited animation is
                // dropped here too — `.animation(nil, value:)` above only governs the
                // label's own change.
                .transaction { transaction in
                    if reduceMotion {
                        transaction.animation = nil
                    }
                }
        }
    }

    private func workoutTypeDetails(_ entry: WorkoutTypeBreakdown) -> some View {
        let presentation = WorkoutTypeBreakdownRowPresentation(entry: entry)

        return HStack(spacing: detailSpacing) {
            Image(systemName: entry.type.symbolName)
                .font(.system(size: iconFontSize, weight: iconWeight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(palette.color(for: entry.type))
                .frame(width: iconFrameSide, height: iconFrameSide)

            VStack(alignment: .leading, spacing: detailTextSpacing) {
                Text(presentation.titleText)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(presentation.detailText)
                    .font(.system(size: detailFontSize, weight: detailFontWeight, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
        }
    }

    /// Read at the rank slot rather than from the row's own entry: the number comes
    /// from the text snapshot, which is already showing the new arrangement while the
    /// bar under it is still traveling to its new width.
    private func percentage(atRank rank: Int) -> Int {
        let breakdown = textBreakdown
        guard distributionTotal > 0, rank < breakdown.count else { return 0 }

        return Int(((breakdown[rank].duration / distributionTotal) * 100).rounded())
    }

    private func detailReserveWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 130), 172)
    }

    private func maximumBarWidth(for availableWidth: CGFloat, reservedTrailingWidth: CGFloat = 0) -> CGFloat {
        switch style {
        case .app, .shareCard:
            // `detailReserveWidth` still reads the FULL width, so reserving the
            // control's slot never squeezes the activity name.
            return max(92, availableWidth - reservedTrailingWidth - detailReserveWidth(for: availableWidth))
        case .widgetMedium:
            return min(max(availableWidth * 0.46, 94), 156)
        case .widgetLarge:
            return min(max(availableWidth * 0.55, 156), 202)
        }
    }

    private var switchControlSide: CGFloat {
        44
    }

    private var minimumBarWidth: CGFloat {
        switch style {
        case .app, .shareCard:
            return 92
        case .widgetMedium:
            return 72
        case .widgetLarge:
            return 94
        }
    }

    private var rowHeight: CGFloat {
        switch style {
        case .app:
            return 50
        case .widgetMedium:
            return 44
        case .widgetLarge:
            return 48
        case .shareCard:
            return 42
        }
    }

    private var rowSpacing: CGFloat {
        style == .widgetMedium ? 10 : 12
    }

    private var rowHorizontalSpacing: CGFloat {
        switch style {
        case .app, .shareCard:
            return 12
        case .widgetMedium:
            return 10
        case .widgetLarge:
            return 14
        }
    }

    private var barCornerRadius: CGFloat {
        switch style {
        case .app:
            return 16
        case .widgetMedium:
            return 15
        case .widgetLarge:
            return 18
        case .shareCard:
            return 14
        }
    }

    private var percentageFontSize: CGFloat {
        switch style {
        case .app:
            return 22
        case .widgetMedium:
            return 20
        case .widgetLarge:
            return 25
        case .shareCard:
            return 19
        }
    }

    private var detailSpacing: CGFloat {
        switch style {
        case .app, .shareCard:
            return 9
        case .widgetMedium:
            return 9
        case .widgetLarge:
            return 14
        }
    }

    private var iconFontSize: CGFloat {
        switch style {
        case .app, .shareCard:
            return 22
        case .widgetMedium:
            return 23
        case .widgetLarge:
            return 28
        }
    }

    private var iconWeight: Font.Weight {
        style.isWidget ? .bold : .semibold
    }

    private var iconFrameSide: CGFloat {
        switch style {
        case .app, .shareCard:
            return 30
        case .widgetMedium:
            return 30
        case .widgetLarge:
            return 38
        }
    }

    private var detailTextSpacing: CGFloat {
        style.isWidget ? 3 : 2
    }

    private var titleFontSize: CGFloat {
        switch style {
        case .app:
            return 15
        case .widgetMedium:
            return 16
        case .widgetLarge:
            return 18
        case .shareCard:
            return 13
        }
    }

    private var detailFontSize: CGFloat {
        switch style {
        case .app:
            return 12
        case .widgetMedium:
            return 12
        case .widgetLarge:
            return 14
        case .shareCard:
            return 11
        }
    }

    private var detailFontWeight: Font.Weight {
        style.isWidget ? .semibold : .bold
    }

    /// The caller's ceiling can only ever tighten the style's — a widget asking for
    /// ten rows still draws the five it was designed for.
    private var displayLimit: Int {
        min(rowLimit ?? styleLimit, styleLimit)
    }

    private var styleLimit: Int {
        switch style {
        case .app:
            return .max
        case .widgetMedium:
            return 2
        case .widgetLarge:
            return 5
        case .shareCard:
            // The share card picks its own number of bars (the user's, up to the
            // month's activity count) and scales the chart down to fit them, so the
            // ceiling here is the caller's alone.
            return .max
        }
    }
}

private extension WorkoutTypeBreakdownDisplayStyle {
    var isWidget: Bool {
        switch self {
        case .app, .shareCard:
            return false
        case .widgetMedium, .widgetLarge:
            return true
        }
    }
}

#Preview {
    WorkoutTypeBreakdownView(snapshot: .placeholder, palette: .builtIn)
        .padding()
        .background(Color.black)
}
