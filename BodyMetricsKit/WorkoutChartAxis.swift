//
//  WorkoutChartAxis.swift
//  BodyMetricsKit
//
//  The y-axis range every workout-detail chart shares. Starting at zero squashes
//  a run's pace or a hill's profile into the top of the plot, so the axis instead
//  brackets the data tightly and then snaps outward to round ticks.
//

import Foundation

/// Picks the y-axis range and tick values for a workout-detail chart.
enum WorkoutChartAxis {
    /// A tight axis around `low`…`high` whose bounds land on multiples of `step`.
    ///
    /// Two passes: first the data gets padded (thinly — 10 % of its own span, or
    /// half the finest tick) and widened to `minimumSpan` so a flat series doesn't
    /// read as a cliff; then the padded bounds snap outward to the most granular
    /// tick on the `step` ladder that leaves 2…6 intervals, i.e. 3…7 labels, so a
    /// small span gets finer labels and the differences stay visible.
    ///
    /// - Parameters:
    ///   - low: Lowest value to show, in the display unit.
    ///   - high: Highest value to show, in the display unit.
    ///   - step: The metric's coarsest comfortable tick, in the display unit; the
    ///     ladder may go down to a tenth of it for small spans.
    ///   - minimumSpan: Smallest range the axis may cover, in the display unit.
    ///   - clampToZero: Whether a range reaching below zero is shifted up so it
    ///     starts at zero — true for rates and counts, false for elevation.
    /// - Returns: The axis range and its ticks, ordered bottom to top.
    static func niceRange(
        low: Double,
        high: Double,
        step: Double,
        minimumSpan: Double,
        clampToZero: Bool
    ) -> (range: ClosedRange<Double>, ticks: [Double]) {
        var lowest = low.isFinite ? low : 0
        var highest = high.isFinite ? high : 0
        if lowest > highest { swap(&lowest, &highest) }
        let step = (step.isFinite && step > 0) ? step : 1
        // `step` is the metric's coarsest comfortable tick; a small data span
        // borrows finer ticks from this ladder so the differences stay legible
        // (5 m elevation → 2 m or 1 m ticks, 0.05 m stride → 0.02 / 0.01, …).
        let finestTick = step * 0.1
        let minimumSpan = (minimumSpan.isFinite && minimumSpan > 0) ? minimumSpan : 0

        // Pass 1 — pad the data, then widen symmetrically to the minimum span.
        let padding = max(finestTick / 2, 0.1 * (highest - lowest))
        var minimum = lowest - padding
        var maximum = highest + padding
        let deficit = minimumSpan - (maximum - minimum)
        if deficit > 0 {
            minimum -= deficit / 2
            maximum += deficit / 2
        }
        if clampToZero, minimum < 0 {
            maximum -= minimum
            minimum = 0
        }

        // Pass 2 — walk the tick ladder from finest to coarsest (0.1, 0.2, 0.4,
        // 1, 2, 3, … × step) and take the FIRST tick whose outward snap leaves
        // 2…6 intervals, i.e. the most granular labels that still fit. Adjacent
        // ladder rungs differ by ≤ 2.5×, so once a rung overshoots six intervals
        // the next rung lands at two or more — a fit always exists.
        var ladder: [Double] = [0.1, 0.2, 0.4].map { $0 * step }
        let stepsInSpan = (maximum - minimum) / step
        let coarsest = max(1, Int(min(stepsInSpan / 2, 1_000_000)) + 2)
        ladder += (1...coarsest).map { Double($0) * step }
        var fallback: (range: ClosedRange<Double>, ticks: [Double])?
        for tick in ladder {
            let lowIndex = (minimum / tick + 1e-9).rounded(.down)
            let highIndex = (maximum / tick - 1e-9).rounded(.up)
            let intervals = Int(highIndex - lowIndex)
            guard intervals >= 2 else { break }
            let bottom = lowIndex * tick
            let ticks = (0...intervals).map { bottom + Double($0) * tick }
            let candidate = (range: bottom...(bottom + Double(intervals) * tick), ticks: ticks)
            if intervals <= 6 { return candidate }
            fallback = candidate
        }
        return fallback ?? (range: minimum...maximum, ticks: [minimum, maximum])
    }
}
