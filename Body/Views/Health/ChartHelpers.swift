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

    private func legendItem(title: LocalizedStringKey, valueText: String?, color: Color) -> some View {
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
}

extension View {
    func bodyChartSelectionAnnotationBackground() -> some View {
        background {
            BodyGlassChip(
                color: Color(.secondarySystemGroupedBackground),
                cornerRadius: BodyChartSelectionAnnotationStyle.cornerRadius,
                fillOpacity: 0.90
            )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: BodyChartSelectionAnnotationStyle.cornerRadius, style: .continuous)
        )
    }
}

/// A scrub callout lifted out of its chart so the home view can draw it on the app's
/// topmost layer. The in-chart `.annotation` lives inside the chart's own layer, so it
/// can never cover the navigation bar — UIKit chrome (back chevron, title) that draws
/// above all page content. The immersive hero charts publish the callout here instead:
/// a global-coordinate anchor (x = the selection rule line, y = the plot's top edge)
/// plus the rendered content.
struct BodyChartFloatingCallout {
    let anchor: CGPoint
    let content: AnyView
}

/// Report-up channel for the floating callout. An `@Observable` box (mirroring
/// `BodyHomeScrollState`) rather than a `Binding` into `BodyHomeView` state, so
/// per-scrub-frame anchor updates re-render only `BodyChartFloatingCalloutLayer` —
/// not the whole home body.
@Observable
final class BodyChartFloatingCalloutState {
    var callout: BodyChartFloatingCallout?
}

/// Renders the published scrub callout. Hosted as an `.overlay` on the home
/// `NavigationStack` — above both nav bars — which is the whole reason the callout
/// leaves its chart. Never hit-testable: it's purely visual, and the scrub gesture
/// underneath must keep receiving touches.
struct BodyChartFloatingCalloutLayer: View {
    let state: BodyChartFloatingCalloutState

    @State private var calloutSize = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            if let callout = state.callout {
                let origin = geo.frame(in: .global).origin
                let frame = Self.calloutFrame(
                    anchor: CGPoint(x: callout.anchor.x - origin.x, y: callout.anchor.y - origin.y),
                    size: calloutSize,
                    in: geo.size
                )

                callout.content
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { size in
                        calloutSize = size
                    }
                    .position(x: frame.midX, y: frame.midY)
                    // Invisible until measured, so the first frame can't flash misplaced.
                    .opacity(calloutSize == .zero ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
    }

    /// Pure placement math: centered on the anchor x but kept on screen, bottom edge
    /// 8pt above the plot top (the in-chart annotation's spacing), and clamped to the
    /// container's top edge (the safe area) rather than running under the status bar.
    static func calloutFrame(anchor: CGPoint, size: CGSize, in container: CGSize) -> CGRect {
        let margin: CGFloat = 8
        let spacing: CGFloat = 8
        let x = min(max(anchor.x - size.width / 2, margin), max(container.width - size.width - margin, margin))
        let y = max(anchor.y - spacing - size.height, 0)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// The floating callout's global-coordinate anchor: the selection's x position within
/// the plot, at the plot's top edge. Marks plotted with `unit: .day` draw centered
/// within the day interval, so `centersOnDayInterval` shifts the anchor to that
/// midpoint; charts that select an exact timestamp (the paired source-comparison
/// bars) pass false.
private func bodyFloatingCalloutAnchor(
    selectionDate: Date?,
    centersOnDayInterval: Bool,
    chartProxy: ChartProxy,
    geo: GeometryProxy
) -> CGPoint? {
    guard let selectionDate,
          let plotFrame = chartProxy.plotFrame,
          let position = chartProxy.position(forX: selectionDate) else {
        return nil
    }

    var x = position
    if centersOnDayInterval,
       let nextDay = Calendar.bodyGregorian.date(byAdding: .day, value: 1, to: selectionDate),
       let nextPosition = chartProxy.position(forX: nextDay) {
        x = (position + nextPosition) / 2
    }

    let plotRect = geo[plotFrame]
    let globalFrame = geo.frame(in: .global)
    return CGPoint(
        x: globalFrame.minX + plotRect.minX + x,
        y: globalFrame.minY + plotRect.minY
    )
}

extension View {
    /// Publishes the chart's active scrub callout (content + global anchor) into `state`
    /// for `BodyChartFloatingCalloutLayer` to render on the topmost layer. No-op when
    /// `state` is nil — non-immersive callers keep their in-chart annotation.
    func bodyFloatingCalloutReporter(
        _ state: BodyChartFloatingCalloutState?,
        selectionDate: Date?,
        centersOnDayInterval: Bool = true,
        content: @escaping () -> AnyView
    ) -> some View {
        func publish(_ anchor: CGPoint?) {
            guard let state else { return }
            if let anchor {
                state.callout = BodyChartFloatingCallout(anchor: anchor, content: content())
            } else if state.callout != nil {
                state.callout = nil
            }
        }

        return chartOverlay { chartProxy in
            GeometryReader { geo in
                let anchor = bodyFloatingCalloutAnchor(
                    selectionDate: selectionDate,
                    centersOnDayInterval: centersOnDayInterval,
                    chartProxy: chartProxy,
                    geo: geo
                )

                Color.clear
                    .onAppear {
                        publish(anchor)
                    }
                    .onChange(of: anchor) { _, newAnchor in
                        publish(newAnchor)
                    }
                    // The hero charts are keyed by range (`.id`), so a mid-scrub range
                    // switch destroys the chart before the gesture can end — clear here
                    // or the callout sticks.
                    .onDisappear {
                        state?.callout = nil
                    }
            }
            .allowsHitTesting(false)
        }
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

/// Word-shaped metric values ("Typical", "2 Outliers"). Same type style as
/// `BodyAnimatedMetricValueText`, minus the monospaced digits, numeric-text
/// transition and aggressive shrink that only make sense for numbers.
struct BodyMetricStatusValueText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let fontSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
