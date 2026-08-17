//
//  WorkoutTypeBreakdownView.swift
//  Body
//

import SwiftUI

enum WorkoutTypeBreakdownDisplayStyle: Equatable {
    case app
    case widgetMedium
    case widgetLarge
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
    let style: WorkoutTypeBreakdownDisplayStyle
    let onSelectType: ((BodyWorkoutType) -> Void)?
    /// Nil in the widgets, which have no second chart to switch to — and which
    /// therefore lay out exactly as they did before this control existed.
    let onSwitchChart: (() -> Void)?

    init(
        snapshot: WorkoutMonthSnapshot,
        style: WorkoutTypeBreakdownDisplayStyle = .app,
        onSelectType: ((BodyWorkoutType) -> Void)? = nil,
        onSwitchChart: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.style = style
        self.onSelectType = onSelectType
        self.onSwitchChart = onSwitchChart
    }

    private var displayedBreakdown: [WorkoutTypeBreakdown] {
        Array(snapshot.workoutTypeBreakdown.prefix(displayLimit))
    }

    private var distributionTotal: TimeInterval {
        snapshot.workoutTypeBreakdown.reduce(0) { $0 + $1.duration }
    }

    private var maxDuration: TimeInterval {
        displayedBreakdown.map(\.duration).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rows
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: style.isWidget ? .infinity : nil,
            alignment: .topLeading
        )
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
        VStack(alignment: .leading, spacing: rowSpacing) {
            if displayedBreakdown.isEmpty {
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
                ForEach(Array(displayedBreakdown.enumerated()), id: \.element.id) { index, entry in
                    workoutTypeDistributionRow(
                        entry,
                        switchAction: index == displayedBreakdown.count - 1 ? onSwitchChart : nil
                    )
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
                    percentageBar(entry)
                        .frame(width: barWidth, height: rowHeight)

                    workoutTypeDetails(entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func percentageBar(_ entry: WorkoutTypeBreakdown) -> some View {
        ZStack(alignment: .leading) {
            BodyGlassChip(color: entry.type.color, cornerRadius: barCornerRadius)

            Text(percentageText(for: entry.duration))
                .font(.system(size: percentageFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(style.isWidget ? 0.68 : 0.75)
                .padding(.horizontal, 16)
        }
    }

    private func workoutTypeDetails(_ entry: WorkoutTypeBreakdown) -> some View {
        let presentation = WorkoutTypeBreakdownRowPresentation(entry: entry)

        return HStack(spacing: detailSpacing) {
            Image(systemName: entry.type.symbolName)
                .font(.system(size: iconFontSize, weight: iconWeight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entry.type.color)
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

    private func percentageText(for duration: TimeInterval) -> String {
        guard distributionTotal > 0 else { return "0%" }

        let percentage = Int(((duration / distributionTotal) * 100).rounded())
        return "\(percentage)%"
    }

    private func detailReserveWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth * 0.42, 130), 172)
    }

    private func maximumBarWidth(for availableWidth: CGFloat, reservedTrailingWidth: CGFloat = 0) -> CGFloat {
        switch style {
        case .app:
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
        case .app:
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
        }
    }

    private var rowSpacing: CGFloat {
        style == .widgetMedium ? 10 : 12
    }

    private var rowHorizontalSpacing: CGFloat {
        switch style {
        case .app:
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
        }
    }

    private var detailSpacing: CGFloat {
        switch style {
        case .app:
            return 9
        case .widgetMedium:
            return 9
        case .widgetLarge:
            return 14
        }
    }

    private var iconFontSize: CGFloat {
        switch style {
        case .app:
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
        case .app:
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
        }
    }

    private var detailFontWeight: Font.Weight {
        style.isWidget ? .semibold : .bold
    }

    private var displayLimit: Int {
        switch style {
        case .app:
            return snapshot.workoutTypeBreakdown.count
        case .widgetMedium:
            return 2
        case .widgetLarge:
            return 5
        }
    }
}

private extension WorkoutTypeBreakdownDisplayStyle {
    var isWidget: Bool {
        switch self {
        case .app:
            return false
        case .widgetMedium, .widgetLarge:
            return true
        }
    }
}

#Preview {
    WorkoutTypeBreakdownView(snapshot: .placeholder)
        .padding()
        .background(Color.black)
}
