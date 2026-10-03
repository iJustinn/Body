//
//  WatchStressChartGeometry.swift
//  BodyWatchShared
//
//  The geometry of the watch's "Last 12 hours" Stress chart, shared by the
//  Stress page (`WatchStressChartView`) and the Stress chart complication
//  (`WatchRecentHoursChartView`): the window, which 15 minute windows and
//  shaded stretches fall in it, and where a score sits. The drawing constants
//  stay with each view, since the page reads `StressChartStyle` and the
//  widget extension can't see BodyMetricsKit; only the band grid is copied
//  here, pinned to `StressChartStyle.gridFractions` by
//  `ProjectConfigurationTests`.
//
//  Shared by the iOS `Body` target, the `BodyWatch` target and the watch
//  widget extension, so it stays Foundation only.
//

import CoreGraphics
import Foundation

enum WatchStressChartGeometry {
    /// How far back the chart reaches: 12 hours, against the Heart Rate and
    /// HRV charts' 8.
    static let windowLength: TimeInterval = 12 * 60 * 60

    /// The dashed gridlines at the band boundaries' quarters,
    /// `StressChartStyle.gridFractions`.
    static let gridFractions: [Double] = [0, 0.25, 0.5, 0.75, 1]

    /// One window drawn on the chart: its span as fractions of the domain,
    /// clamped to it, and what it shows (never `.none`, which is a gap).
    struct Mark: Equatable {
        let xStart: Double
        let xEnd: Double
        let slot: WatchStressTimeline.Slot
    }

    /// One shaded stretch clipped to the domain, as fractions of it.
    struct ContextSpan: Equatable {
        let xStart: Double
        let xEnd: Double
        let band: WatchStressContextBand
    }

    /// The x domain: the Heart Rate and HRV charts' window ending at `now`,
    /// opened `windowLength` back, from its oldest slot's start through the
    /// current slot's end.
    static func domain(endingAt now: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let window = WatchIntradayWindow.endingAt(now, length: windowLength, calendar: calendar)
        return window.start...window.plotEnd
    }

    /// The Heart Rate and HRV charts' hour labels, over this chart's window.
    static func ticks(endingAt now: Date, calendar: Calendar = .current) -> [Date] {
        WatchIntradayChartGeometry.hourTicks(in: domain(endingAt: now, calendar: calendar), calendar: calendar)
    }

    /// The scored and activity windows that overlap the domain, oldest first,
    /// clipped to it. Unscored windows are gaps, so they never appear, and a
    /// window cut to nothing at the timeline's `end` is skipped.
    static func marks(in timeline: WatchStressTimeline, domain: ClosedRange<Date>) -> [Mark] {
        timeline.slots.indices.compactMap { index -> Mark? in
            let slot = timeline.slot(at: index)
            if case .none = slot { return nil }
            let interval = timeline.interval(at: index)
            guard interval.duration > 0,
                  interval.end > domain.lowerBound,
                  interval.start < domain.upperBound else { return nil }
            return Mark(
                xStart: WatchIntradayChartGeometry.fraction(for: interval.start, in: domain),
                xEnd: WatchIntradayChartGeometry.fraction(for: interval.end, in: domain),
                slot: slot
            )
        }
    }

    /// The context bands that overlap the domain, clipped to it.
    static func contextSpans(in timeline: WatchStressTimeline, domain: ClosedRange<Date>) -> [ContextSpan] {
        timeline.context.compactMap { band -> ContextSpan? in
            let xStart = WatchIntradayChartGeometry.fraction(for: band.start, in: domain)
            let xEnd = WatchIntradayChartGeometry.fraction(for: band.end, in: domain)
            guard xEnd > xStart else { return nil }
            return ContextSpan(xStart: xStart, xEnd: xEnd, band: band)
        }
    }

    /// Whether the window ending at `now` has anything to draw: the Stress
    /// page shows the chart, and scrolls, only then.
    static func hasVisibleMarks(_ timeline: WatchStressTimeline, endingAt now: Date, calendar: Calendar = .current) -> Bool {
        !marks(in: timeline, domain: domain(endingAt: now, calendar: calendar)).isEmpty
    }

    /// A score's height in the plot: 0 on the floor, 100 at the top, clamped.
    static func y(forScore score: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.maxY - plotRect.height * CGFloat(min(1, max(0, score / 100)))
    }

    /// A window's mark across the plot, inset by `inset` on each side so
    /// neighbors don't touch, but never narrower than `minimumWidth`. The page
    /// passes `StressChartStyle`'s values, the complication its own smaller
    /// ones.
    static func markSpan(xStart: Double, xEnd: Double, in plotRect: CGRect, inset: CGFloat, minimumWidth: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let leading = plotRect.minX + plotRect.width * CGFloat(xStart) + inset
        let trailing = plotRect.minX + plotRect.width * CGFloat(xEnd) - inset
        return (leading, max(minimumWidth, trailing - leading))
    }
}
