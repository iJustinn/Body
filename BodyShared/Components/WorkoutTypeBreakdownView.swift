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

    init(
        snapshot: WorkoutMonthSnapshot,
        style: WorkoutTypeBreakdownDisplayStyle = .app,
        onSelectType: ((BodyWorkoutType) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.style = style
        self.onSelectType = onSelectType
    }

    private var displayedBreakdown: [WorkoutTypeBreakdown] {
        Array(snapshot.workoutTypeBreakdown.prefix(displayLimit))
    }

    private var distributionTotal: TimeInterval {
        displayedBreakdown.reduce(0) { $0 + $1.duration }
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

            Text("No workouts yet")
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
            } else {
                ForEach(displayedBreakdown) { entry in
                    workoutTypeDistributionRow(entry)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture {
                            onSelectType?(entry.type)
                        }
                }
            }
        }
    }

    private func workoutTypeDistributionRow(_ entry: WorkoutTypeBreakdown) -> some View {
        GeometryReader { geometry in
            let maxBarWidth = maximumBarWidth(for: geometry.size.width)
            let minBarWidth = min(minimumBarWidth, maxBarWidth)
            let relativeAmount = maxDuration > 0 ? entry.duration / maxDuration : 0
            let barWidth = minBarWidth + ((maxBarWidth - minBarWidth) * CGFloat(relativeAmount))

            HStack(spacing: rowHorizontalSpacing) {
                percentageBar(entry)
                    .frame(width: barWidth, height: rowHeight)

                workoutTypeDetails(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: rowHeight)
    }

    private func percentageBar(_ entry: WorkoutTypeBreakdown) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                .fill(entry.type.color)

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

    private func maximumBarWidth(for availableWidth: CGFloat) -> CGFloat {
        switch style {
        case .app:
            return max(92, availableWidth - detailReserveWidth(for: availableWidth))
        case .widgetMedium:
            return min(max(availableWidth * 0.46, 94), 156)
        case .widgetLarge:
            return min(max(availableWidth * 0.55, 156), 202)
        }
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
