//
//  WatchSparklineView.swift
//  BodyWatch
//
//  Recent-week line chart for the metric-detail page, styled after the iPhone
//  trend chart: faint per-day gridlines, a tinted line through the daily values
//  with a ringed dot per day and a solid dot for today (line broken across
//  missing days), and weekday labels along the bottom. For banded metrics
//  (Readiness, Training Load) it also highlights today's status band behind the
//  line — a translucent fill bounded by two bright stripes.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchSparklineView: View {
    /// Daily values, oldest → today; `nil` for a day with no reading.
    let values: [Double?]
    let tint: Color
    /// Today's status band to highlight (Readiness, Training Load); `nil` otherwise.
    var band: WatchStatusBand? = nil
    /// Today's live value when it dropped below today's plotted slot
    /// (Readiness: the drained score under the frozen morning point) — drawn
    /// as a faded tint dot in today's column. `nil` otherwise.
    var currentValue: Double? = nil
    /// Per-day labels (oldest → today), drawn along the bottom of the chart.
    var dayLabels: [String] = []

    private let topInset: CGFloat = 5
    private let bottomPlotInset: CGFloat = 3
    private let labelHeight: CGFloat = 15
    private let lineWidth: CGFloat = 2.5
    private let pointDiameter: CGFloat = 5
    private let currentPointDiameter: CGFloat = 7
    private let pointRingWidth: CGFloat = 1.5
    private let stripeHeight: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let plotHeight = max(size.height - labelHeight, 1)

            ZStack {
                gridlines(in: size)

                if let domain = yDomain() {
                    let plotPoints = points(in: size, plotHeight: plotHeight, domain: domain)
                    // The solid dot marks "today" — the final slot, and only when
                    // it actually has a reading. If today's value is missing, no
                    // dot is solid: an earlier day with data must not be rendered
                    // as if it were current.
                    let currentIndex = values.indices.last.flatMap { values[$0]?.isFinite == true ? $0 : nil }

                    bandLayer(in: size, plotHeight: plotHeight, domain: domain)

                    Path { path in
                        for run in contiguousRuns(plotPoints) where run.count > 1 {
                            path.move(to: run[0])
                            for point in run.dropFirst() { path.addLine(to: point) }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                    ForEach(Array(plotPoints.enumerated()), id: \.offset) { index, point in
                        if let point {
                            pointDot(at: point, isCurrent: index == currentIndex)
                        }
                    }

                    // The faded "current" dot under today's plotted point —
                    // where readiness actually is now after today's drain.
                    if let dotValue = Self.currentDotValue(values: values, currentValue: currentValue),
                       let todayPoint = plotPoints.last ?? nil {
                        Circle()
                            .fill(tint.opacity(0.8))
                            .frame(width: currentPointDiameter, height: currentPointDiameter)
                            .position(x: todayPoint.x, y: y(for: dotValue, plotHeight: plotHeight, domain: domain))
                    }
                }

                dayLabelRow(in: size)
            }
        }
    }

    // MARK: - Gridlines & labels

    private func gridlines(in size: CGSize) -> some View {
        let count = max(values.count, 1)
        return Path { path in
            for index in 0..<count {
                let x = size.width * CGFloat(index) / CGFloat(count)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
    }

    @ViewBuilder
    private func dayLabelRow(in size: CGSize) -> some View {
        if !dayLabels.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: size.width, height: labelHeight)
            .position(x: size.width / 2, y: size.height - labelHeight / 2)
        }
    }

    // MARK: - Status band

    @ViewBuilder
    private func bandLayer(in size: CGSize, plotHeight: CGFloat, domain: (lo: Double, hi: Double)) -> some View {
        if let band, band.min != nil || band.max != nil {
            // Clamp to the plot domain (open ends fill to the edge), matching the
            // iPhone chart's `lowerPlotBound`/`upperPlotBound`.
            let topValue = Swift.min(band.max ?? domain.hi, domain.hi)
            let bottomValue = Swift.max(band.min ?? domain.lo, domain.lo)
            let yTop = y(for: topValue, plotHeight: plotHeight, domain: domain)
            let yBottom = y(for: bottomValue, plotHeight: plotHeight, domain: domain)
            let centerX = size.width / 2

            ZStack {
                Rectangle()
                    .fill(tint.opacity(0.22))
                    .frame(width: size.width, height: Swift.max(yBottom - yTop, 0))
                    .position(x: centerX, y: (yTop + yBottom) / 2)
                Rectangle()
                    .fill(tint.opacity(0.75))
                    .frame(width: size.width, height: stripeHeight)
                    .position(x: centerX, y: yTop + stripeHeight / 2)
                Rectangle()
                    .fill(tint.opacity(0.75))
                    .frame(width: size.width, height: stripeHeight)
                    .position(x: centerX, y: yBottom - stripeHeight / 2)
            }
        }
    }

    private func pointDot(at point: CGPoint, isCurrent: Bool) -> some View {
        let diameter = isCurrent ? currentPointDiameter : pointDiameter
        return Circle()
            .fill(isCurrent ? tint : Color.black)
            .overlay(Circle().stroke(tint, lineWidth: pointRingWidth))
            .frame(width: diameter, height: diameter)
            .position(point)
    }

    /// The value for the faded "current" dot under today's (last) slot, or
    /// `nil`: needs a finite today reading and a finite current value strictly
    /// below it — the dot only marks a same-day decrease.
    static func currentDotValue(values: [Double?], currentValue: Double?) -> Double? {
        guard let currentValue, currentValue.isFinite,
              let todayValue = values.last ?? nil, todayValue.isFinite,
              currentValue < todayValue else {
            return nil
        }
        return currentValue
    }

    // MARK: - Geometry

    /// Y domain over the finite values plus any finite band bounds and the
    /// current-value dot, padded 12% and clamped ≥ 0 — mirroring the iPhone
    /// line chart's `computeYDomain`.
    private func yDomain() -> (lo: Double, hi: Double)? {
        var domainValues = values.compactMap { $0 }.filter(\.isFinite)
        if let dotValue = Self.currentDotValue(values: values, currentValue: currentValue) {
            domainValues.append(dotValue)
        }
        if let band {
            if let low = band.min, low.isFinite { domainValues.append(low) }
            if let high = band.max, high.isFinite { domainValues.append(high) }
        }
        guard let low = domainValues.min(), let high = domainValues.max() else { return nil }
        guard low != high else {
            let padding = Swift.max(abs(low) * 0.12, 1)
            return (Swift.max(0, low - padding), high + padding)
        }
        let padding = Swift.max((high - low) * 0.12, 1)
        return (Swift.max(0, low - padding), high + padding)
    }

    /// Maps a value to a y within the plot area (above the label row).
    private func y(for value: Double, plotHeight: CGFloat, domain: (lo: Double, hi: Double)) -> CGFloat {
        let usableHeight = Swift.max(plotHeight - topInset - bottomPlotInset, 1)
        let span = domain.hi - domain.lo
        let fraction = span > 0 ? (value - domain.lo) / span : 0.5
        return topInset + (1 - CGFloat(fraction)) * usableHeight
    }

    /// Each value as a point (centered in its day slot so points line up with the
    /// gridlines and labels); `nil` for missing days.
    private func points(in size: CGSize, plotHeight: CGFloat, domain: (lo: Double, hi: Double)) -> [CGPoint?] {
        let count = Swift.max(values.count, 1)
        return values.enumerated().map { index, value in
            guard let value, value.isFinite else { return nil }
            let x = size.width * (CGFloat(index) + 0.5) / CGFloat(count)
            return CGPoint(x: x, y: y(for: value, plotHeight: plotHeight, domain: domain))
        }
    }

    /// Runs of consecutive non-nil points, split on each `nil` gap.
    private func contiguousRuns(_ points: [CGPoint?]) -> [[CGPoint]] {
        var runs: [[CGPoint]] = []
        var current: [CGPoint] = []
        for point in points {
            if let point {
                current.append(point)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}
