//
//  ChartHelpers.swift
//  Body
//

import Charts
import SwiftUI

struct BodyHealthTrendRangeSelector: View {
    /// Standard grouped-background pills, or translucent "glass" pills for the
    /// metric gradient hero where the selector floats over the gradient wash.
    enum Appearance {
        case standard
        case onGradient
    }

    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedRange: BodyHealthTrendRange
    var appearance: Appearance = .standard
    /// When false, every range but the free `.recentWeek` is locked: its pill shows a
    /// lock and a tap routes to `onLockedRangeTap` (the paywall) instead of selecting.
    var isProUnlocked: Bool = true
    var onLockedRangeTap: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BodyHealthTrendRange.allCases) { range in
                Button {
                    if isLocked(range) {
                        onLockedRangeTap()
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedRange = range
                        }
                    }
                } label: {
                    pillLabel(for: range)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                .accessibilityHint(isLocked(range) ? "Requires Body Pro" : "")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isLocked(_ range: BodyHealthTrendRange) -> Bool {
        !isProUnlocked && range != .recentWeek
    }

    @ViewBuilder
    private func pillLabel(for range: BodyHealthTrendRange) -> some View {
        let isSelected = selectedRange == range
        let locked = isLocked(range)
        let label = HStack(spacing: 3) {
            Text(range.displayName)
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundColor(textColor(isSelected: isSelected, locked: locked))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(maxWidth: .infinity, minHeight: 42)

        switch appearance {
        case .standard:
            label.bodyTrendRangeTabBackground(isSelected: isSelected, colorScheme: colorScheme)
        case .onGradient:
            label.bodyTrendRangeTabBackgroundOnGradient(isSelected: isSelected)
        }
    }

    private func textColor(isSelected: Bool, locked: Bool) -> Color {
        switch appearance {
        case .standard:
            if locked { return .secondary }
            return isSelected ? .accentColor : .primary
        case .onGradient:
            if locked { return .primary.opacity(0.4) }
            return isSelected ? .primary : .primary.opacity(0.6)
        }
    }
}

struct BodyChartBaselineLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            DashedLegendLine()
                .stroke(
                    Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 3])
                )
                .frame(width: 16, height: 1)

            Text("Baseline")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private struct DashedLegendLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let midY = rect.midY
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            return path
        }
    }
}

struct BodyBasicsTrendLegend: View {
    let weightColor: Color
    let bodyFatColor: Color
    let weightAverageText: String?
    let bodyFatAverageText: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            legendItem(title: "Body Fat", valueText: bodyFatAverageText, color: bodyFatColor)
            legendItem(title: "Weight", valueText: weightAverageText, color: weightColor)
        }
        .frame(maxWidth: 180, alignment: .trailing)
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[.lastTextBaseline]
        }
    }

    private func legendItem(title: String, valueText: String?, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if let valueText {
                Text("Avg \(valueText)")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
    }
}

struct BodyChartSelectionValue: Identifiable {
    let title: String?
    let value: String
    let color: Color

    var id: String {
        "\(title ?? "")-\(value)"
    }
}

struct BodyChartSelectionAnnotation: View {
    let eyebrow: String?
    let values: [BodyChartSelectionValue]
    let date: Date
    var dateText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if values.count == 1, let value = values.first {
                Text(value.value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            } else {
                ForEach(values) { value in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(value.color)
                            .frame(width: 8, height: 8)

                        if let title = value.title {
                            Text(title)
                                .foregroundColor(.secondary)
                        }

                        Text(value.value)
                            .foregroundColor(.primary)
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }

            Text(dateText ?? date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .bodyChartSelectionAnnotationBackground()
    }
}

private enum BodyChartSelectionAnnotationStyle {
    static let cornerRadius: CGFloat = 8
    static let fillOpacity = 0.82
}

extension View {
    func bodyChartSelectionAnnotationBackground() -> some View {
        background {
            RoundedRectangle(cornerRadius: BodyChartSelectionAnnotationStyle.cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground).opacity(BodyChartSelectionAnnotationStyle.fillOpacity))
        }
        .clipShape(
            RoundedRectangle(cornerRadius: BodyChartSelectionAnnotationStyle.cornerRadius, style: .continuous)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
    }
}

extension DateInterval {
    func clamped(to boundary: DateInterval) -> DateInterval? {
        let clampedStart = max(start, boundary.start)
        let clampedEnd = min(end, boundary.end)
        guard clampedEnd > clampedStart else {
            return nil
        }

        return DateInterval(start: clampedStart, end: clampedEnd)
    }
}

// Chart helpers moved from BodyHomeView.swift (line 2155 onward in pre-split).

enum BodyLineChartPreviewStyle {
    static let lineWidth: CGFloat = 4
    static let lineColor = Color.secondary.opacity(0.28)
    static let pointStrokeColor = Color.secondary.opacity(0.28)
    static let pointStrokeWidth: CGFloat = 2
}

struct BodyLineChartPreviewPointSymbol: View {
    let tintColor: Color
    let isCurrent: Bool
    let pointDiameter: CGFloat
    let currentPointDiameter: CGFloat

    var body: some View {
        let diameter = isCurrent
            ? currentPointDiameter
            : pointDiameter

        Circle()
            .fill(isCurrent ? tintColor : Color(.secondarySystemBackground))
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .stroke(
                        tintColor,
                        lineWidth: BodyLineChartPreviewStyle.pointStrokeWidth
                    )
            )
    }
}

enum BodyHealthMetricChartStyle {
    case line
    case bar
}

enum BodyHealthDetailChartLayout {
    static let standardHeight: CGFloat = 220
    static let dayChartHeight: CGFloat = 252
    static let sleepVitalsHeight: CGFloat = 248
    static let sleepVitalsPlotHeight: CGFloat = 188
    static let sleepVitalsIconAxisHeight: CGFloat = 28
    static let sleepConsistencyHeight: CGFloat = 248
    static let yAxisLabelCount = 4
}

enum BodySleepScoreDetailsSheetLayout {
    static let sheetHeight: CGFloat = 720
}

struct BodyMetricDisplayValue: Identifiable {
    let title: String
    let value: String
    let unit: String

    var id: String {
        title
    }
}

struct BodyAnimatedMetricValueText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: String
    let fontSize: CGFloat
    let color: Color
    let minimumScaleFactor: CGFloat

    var body: some View {
        Text(value)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: value)
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
    }
}

struct BodyHealthMetricTrendHighlightedRange {
    let title: String
    let lowerBound: Double?
    let upperBound: Double?
    let color: Color

    var domainValues: [Double] {
        [lowerBound, upperBound].compactMap { $0 }
    }

    func lowerPlotBound(in domain: ClosedRange<Double>) -> Double {
        max(lowerBound ?? domain.lowerBound, domain.lowerBound)
    }

    func upperPlotBound(in domain: ClosedRange<Double>) -> Double {
        min(upperBound ?? domain.upperBound, domain.upperBound)
    }
}
