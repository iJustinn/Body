//
//  StressChart.swift
//  Body
//

import SwiftUI
import UIKit

/// The Stress counterpart of `BodyReadinessStatusPresentation`: band colors and
/// the trend chart's highlighted range for whichever band today's score falls in.
enum BodyStressBandPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let value, value.isFinite else {
            return nil
        }

        let band = StressBand.band(for: value)
        return BodyHealthMetricTrendHighlightedRange(
            title: band.title,
            lowerBound: band.lowerBound,
            upperBound: band.upperBound,
            color: color(for: band)
        )
    }

    /// Cool-to-warm progression distinct from the readiness/training-load band
    /// palettes: calm blue at Rest through red at High.
    static func color(for band: StressBand) -> Color {
        rgb(for: band).color
    }

    /// The same palette as literal components, so the day-switch morph can blend
    /// one band's colour into the next instead of stacking two translucent draws.
    static func rgb(for band: StressBand) -> BodyStressRGB {
        switch band {
        case .rest:
            return BodyStressRGB(red: 0.20, green: 0.70, blue: 0.95)
        case .low:
            return BodyStressRGB(red: 0.20, green: 0.80, blue: 0.45)
        case .medium:
            return BodyStressRGB(red: 1.00, green: 0.72, blue: 0.15)
        case .high:
            return BodyStressRGB(red: 1.00, green: 0.30, blue: 0.20)
        }
    }

    /// Masked movement time is not a band, so it gets one neutral gray shared by the
    /// intraday plot's floor stubs and the day breakdown's Activity row.
    static let activityColor = Color.secondary.opacity(0.45)

    /// The Activity row/callout label. Dotted key: a bare "Activity" would inherit
    /// the Fitness-ring translation this display category does not mean.
    static var activityTitle: String {
        String(localized: "stress.stage.activity", defaultValue: "Activity")
    }
}

/// Literal sRGB components, so two band colours can be blended at an interpolated
/// geometry. `Color` itself is opaque — mixing two of them would mean drawing both
/// translucently, which dims the mark at the midpoint of every morph.
struct BodyStressRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func interpolated(_ from: BodyStressRGB, _ to: BodyStressRGB, at progress: Double) -> BodyStressRGB {
        BodyStressRGB(
            red: from.red + (to.red - from.red) * progress,
            green: from.green + (to.green - from.green) * progress,
            blue: from.blue + (to.blue - from.blue) * progress
        )
    }
}

/// A window's civil-clock identity. The day-switch morph pairs windows by this,
/// never by elapsed index: on a 23 hour spring-forward day the twelfth window is
/// 03:00 where a normal day's twelfth is 02:45, so an index pairing would slide
/// the whole afternoon. `occurrence` disambiguates the fall-back day, where 01:00
/// through 01:45 happen twice.
struct BodyStressPlotSlotKey: Hashable {
    let hour: Int
    let minute: Int
    let occurrence: Int
}

/// One drawable element of the intraday plot, carried through the morph. Identity
/// is the civil slot plus whether the slot is a scored mark or an activity stub:
/// a slot that changes category between days has two ids, so it cross-fades in
/// place instead of morphing a capsule into a floor stub.
struct BodyStressPlotTrack: Equatable {
    struct ID: Hashable {
        let key: BodyStressPlotSlotKey
        let isActivity: Bool
        /// Distinguishes the two halves of an already-crossfading track when a
        /// synthetic side (a rapid-tap rebase, or reduced motion) carries both.
        let variant: Int
    }

    var key: BodyStressPlotSlotKey
    var isActivity: Bool
    var variant: Int = 0
    var xStart: Double
    var xEnd: Double
    /// 0...100; ignored for activity stubs, which always sit on the floor.
    var score: Double = 0
    var rgb: BodyStressRGB = BodyStressRGB(red: 0, green: 0, blue: 0)
    var opacity: Double = 1

    var id: ID {
        ID(key: key, isActivity: isActivity, variant: variant)
    }

    func fading(to opacityScale: Double, variantOffset: Int = 0) -> BodyStressPlotTrack {
        var copy = self
        copy.opacity *= opacityScale
        copy.variant += variantOffset
        return copy
    }
}

/// A context (sleep/workout) highlight resolved into its own day's fractions.
struct BodyStressPlotContextBand: Equatable {
    var id: String
    var variant: Int = 0
    var xStart: Double
    var xEnd: Double
    var color: Color
    var fillOpacity: Double
    var symbolName: String
    var opacity: Double = 1

    func fading(to opacityScale: Double, variantOffset: Int = 0) -> BodyStressPlotContextBand {
        var copy = self
        copy.opacity *= opacityScale
        copy.variant += variantOffset
        return copy
    }
}

/// A time-axis tick with an opacity, so two days' axes can crossfade when DST
/// actually moved them. Distinct from `BodyStressIntradayTimeMark`, which is the
/// plot's public, opacity-free description of the axis.
struct BodyStressPlotTimeMark: Equatable {
    var fraction: Double
    var label: String
    var opacity: Double = 1
}

/// One whole day resolved for drawing: every position is already a fraction of
/// THAT day's interval, so a morph never evaluates one day's absolute dates
/// against the other day's interval (which would clamp the outgoing day's marks
/// onto the left edge on any day whose length differs).
struct BodyStressPlotSide: Equatable {
    var tracks: [BodyStressPlotTrack] = []
    var contextBands: [BodyStressPlotContextBand] = []
    var timeMarks: [BodyStressPlotTimeMark] = []
    /// 1 when the day draws nothing at all — the plot's internal empty state.
    var emptiness: Double = 1

    static func make(
        windows: [StressWindow],
        dayInterval: DateInterval,
        contextIntervals: [BodyHealthMetricDayContextInterval],
        calendar: Calendar = .bodyGregorian
    ) -> BodyStressPlotSide {
        let keys = slotKeys(for: windows, calendar: calendar)
        var tracks: [BodyStressPlotTrack] = []
        for (index, window) in windows.enumerated() {
            let xStart = BodyStressIntradayPlot.fraction(for: window.interval.start, in: dayInterval)
            let xEnd = BodyStressIntradayPlot.fraction(for: window.interval.end, in: dayInterval)
            if let score = window.score {
                tracks.append(
                    BodyStressPlotTrack(
                        key: keys[index],
                        isActivity: false,
                        xStart: xStart,
                        xEnd: xEnd,
                        score: score,
                        rgb: BodyStressBandPresentation.rgb(for: StressBand.band(for: score))
                    )
                )
            } else if window.state == .activity {
                tracks.append(
                    BodyStressPlotTrack(
                        key: keys[index],
                        isActivity: true,
                        xStart: xStart,
                        xEnd: xEnd
                    )
                )
            }
        }

        let bands = contextIntervals.map { interval in
            BodyStressPlotContextBand(
                id: interval.id,
                xStart: BodyStressIntradayPlot.fraction(for: interval.startDate, in: dayInterval),
                xEnd: BodyStressIntradayPlot.fraction(for: interval.endDate, in: dayInterval),
                color: interval.color,
                fillOpacity: interval.kind == .sleep ? 0.14 : 0.10,
                symbolName: interval.symbolName
            )
        }

        let marks = BodyStressIntradayPlot.timeMarks(for: dayInterval, calendar: calendar).map {
            BodyStressPlotTimeMark(fraction: $0.fraction, label: $0.label)
        }

        return BodyStressPlotSide(
            tracks: tracks,
            contextBands: bands,
            timeMarks: marks,
            emptiness: tracks.isEmpty ? 1 : 0
        )
    }

    /// Civil-clock keys for a day's windows, in window order.
    static func slotKeys(for windows: [StressWindow], calendar: Calendar = .bodyGregorian) -> [BodyStressPlotSlotKey] {
        var occurrences: [Int: Int] = [:]
        return windows.map { window in
            let components = calendar.dateComponents([.hour, .minute], from: window.interval.start)
            let hour = components.hour ?? 0
            let minute = components.minute ?? 0
            let slot = hour * 60 + minute
            let occurrence = occurrences[slot, default: 0]
            occurrences[slot] = occurrence + 1
            return BodyStressPlotSlotKey(hour: hour, minute: minute, occurrence: occurrence)
        }
    }

    /// The morph's pairing, as a pure function of two sides: slots present on
    /// both sides pair up, slots on only one side fade. Order is the outgoing
    /// side's, with the incoming side's unmatched slots appended.
    static func trackPairs(from: BodyStressPlotSide, to: BodyStressPlotSide) -> [BodyStressPlotTrackPair] {
        var incoming: [BodyStressPlotTrack.ID: BodyStressPlotTrack] = [:]
        for track in to.tracks where incoming[track.id] == nil {
            incoming[track.id] = track
        }

        var matched: Set<BodyStressPlotTrack.ID> = []
        var pairs: [BodyStressPlotTrackPair] = []
        for track in from.tracks {
            if !matched.contains(track.id), let partner = incoming[track.id] {
                matched.insert(track.id)
                pairs.append(BodyStressPlotTrackPair(from: track, to: partner))
            } else {
                pairs.append(BodyStressPlotTrackPair(from: track, to: nil))
            }
        }
        for track in to.tracks where !matched.contains(track.id) {
            pairs.append(BodyStressPlotTrackPair(from: nil, to: track))
        }

        return pairs
    }

    /// The presentation at `progress` — itself a side, which is what makes a
    /// rapid-tap rebase possible: the in-flight pair is evaluated at whatever
    /// the screen currently shows and becomes the next transition's outgoing
    /// side, so a second tap never jumps back to the first tap's destination.
    static func interpolated(
        from: BodyStressPlotSide,
        to: BodyStressPlotSide,
        at progress: Double,
        reduceMotion: Bool
    ) -> BodyStressPlotSide {
        guard progress > 0 else { return from }
        guard progress < 1 else { return to }

        let tracks: [BodyStressPlotTrack]
        if reduceMotion {
            // Stated choice: no geometry interpolation under Reduce Motion, just
            // a crossfade — still animated, nothing travels.
            tracks = from.tracks.map { $0.fading(to: 1 - progress) }
                + to.tracks.map { $0.fading(to: progress, variantOffset: 1) }
        } else {
            tracks = trackPairs(from: from, to: to).map { pair in
                switch (pair.from, pair.to) {
                case let (outgoing?, incoming?):
                    var merged = outgoing
                    merged.xStart = interpolate(outgoing.xStart, incoming.xStart, progress)
                    merged.xEnd = interpolate(outgoing.xEnd, incoming.xEnd, progress)
                    merged.score = interpolate(outgoing.score, incoming.score, progress)
                    merged.rgb = BodyStressRGB.interpolated(outgoing.rgb, incoming.rgb, at: progress)
                    merged.opacity = interpolate(outgoing.opacity, incoming.opacity, progress)
                    return merged
                case let (outgoing?, nil):
                    return outgoing.fading(to: 1 - progress)
                case let (nil, incoming?):
                    return incoming.fading(to: progress)
                case (nil, nil):
                    return BodyStressPlotTrack(key: BodyStressPlotSlotKey(hour: 0, minute: 0, occurrence: 0), isActivity: false, xStart: 0, xEnd: 0, opacity: 0)
                }
            }
        }

        // Context bands always crossfade, each drawn in its own day's fractions —
        // a sleep band that shifted by two hours should dissolve, not slide.
        let bands = from.contextBands.map { $0.fading(to: 1 - progress) }
            + to.contextBands.map { $0.fading(to: progress, variantOffset: 1) }

        let timeMarks: [BodyStressPlotTimeMark]
        if from.timeMarks.map(\.label) == to.timeMarks.map(\.label),
           from.timeMarks.map(\.fraction) == to.timeMarks.map(\.fraction),
           from.timeMarks.allSatisfy({ $0.opacity == 1 }) {
            // Same ticks in the same places (every switch between two days of
            // equal length): drawing them once keeps them at full strength.
            timeMarks = to.timeMarks
        } else {
            timeMarks = from.timeMarks.map { BodyStressPlotTimeMark(fraction: $0.fraction, label: $0.label, opacity: $0.opacity * (1 - progress)) }
                + to.timeMarks.map { BodyStressPlotTimeMark(fraction: $0.fraction, label: $0.label, opacity: $0.opacity * progress) }
        }

        return BodyStressPlotSide(
            tracks: tracks,
            contextBands: bands,
            timeMarks: timeMarks,
            emptiness: interpolate(from.emptiness, to.emptiness, progress)
        )
    }

    /// Smoothstep. The progress the plot animates is linear so a rebase can read
    /// the presented value off the wall clock; the easing lives here instead.
    static func eased(_ progress: Double) -> Double {
        let clamped = min(1, max(0, progress))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func interpolate(_ from: Double, _ to: Double, _ progress: Double) -> Double {
        from + (to - from) * progress
    }
}

/// One slot of the morph: either side may be missing, which is the fade case.
struct BodyStressPlotTrackPair: Equatable {
    var from: BodyStressPlotTrack?
    var to: BodyStressPlotTrack?
}

/// `bodyWorkoutChartAxisLabel`'s font-shrink rule, duplicated rather than shared:
/// the pace plot's helper is private to `BodyWorkoutsView`, whose source guards
/// count its lines.
private func bodyStressChartAxisLabel(
    _ label: String,
    in context: GraphicsContext
) -> GraphicsContext.ResolvedText {
    func resolve(_ size: CGFloat) -> GraphicsContext.ResolvedText {
        context.resolve(
            Text(label)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
        )
    }
    func fits(_ resolved: GraphicsContext.ResolvedText) -> Bool {
        resolved.measure(in: CGSize(width: 200, height: 40)).width <= 40
    }

    let base = resolve(14)
    if fits(base) {
        return base
    }
    let medium = resolve(12)
    if fits(medium) {
        return medium
    }
    return resolve(11)
}

/// One tick on the intraday plot's time axis: a civil clock hour resolved through
/// the calendar, expressed as its real fraction of the day interval.
struct BodyStressIntradayTimeMark: Equatable {
    let fraction: Double
    let label: String
}

/// Intraday Stress plot, drawn as a Canvas so it matches `BodyWorkoutBucketedSeriesPlot`
/// (the workout pace/cadence chart) in geometry and interaction: a 44pt right label
/// gutter, 34pt of bottom time labels, a dashed grid at the band boundaries, and a
/// faint column plus capsule per mark. Unlike the pace plot the colours come from the
/// band palette, so the plot and the breakdown rows below it never disagree.
///
/// The x domain is the FULL calendar day, not the range the marks happen to cover, so
/// today's chart fills left to right instead of stretching as windows arrive. Every
/// position is a fraction of the real `DateInterval`, which keeps 23 and 25 hour DST
/// days honest.
struct BodyStressIntradayPlot: View {
    let windows: [StressWindow]
    /// The selected day's real interval — `calendar.dateInterval(of: .day, for:)`.
    let dayInterval: DateInterval
    /// Sleep and workout background highlights, the same ones
    /// `BodyHealthMetricDayChart` shades behind the heart rate day view.
    var contextIntervals: [BodyHealthMetricDayContextInterval] = []
    /// Names the plot for VoiceOver.
    var title: String = ""
    /// Where a scrub publishes its callout; nil in previews and renders.
    var floatingCallout: BodyChartFloatingCalloutState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrubX: CGFloat?
    @State private var scrubbedMarkID: Int?
    @State private var accessibilityMarkIndex = 0

    /// The day currently being drawn TO. Seeded on appear so the first date
    /// switch already has an outgoing day to morph from.
    @State private var displayedSide: BodyStressPlotSide?
    /// The day being morphed FROM — after a rapid tap this is a synthetic side
    /// (the interpolated presentation), not the superseded destination.
    @State private var previousSide: BodyStressPlotSide?
    /// Linear 0→1; the easing is applied inside `BodyStressPlotSide.interpolated`
    /// so a rebase can read the presented progress straight off the wall clock.
    @State private var transitionProgress: Double = 1
    @State private var transitionStart: Date?
    @State private var isTransitioning = false
    /// Invalidates the completion of a transition a newer day switch superseded
    /// (the sleep stage chart's precedent).
    @State private var transitionGeneration = 0

    static let transitionDuration: TimeInterval = 0.45

    fileprivate static let yAxisLabelInset: CGFloat = 44
    fileprivate static let xAxisLabelOffset: CGFloat = 18
    fileprivate static let timeMarkLabelHorizontalInset: CGFloat = 24
    fileprivate static let gridFractions: [Double] = [0, 0.25, 0.5, 0.75, 1]
    fileprivate static let gridLabels: [String] = ["0", "25", "50", "75", "100"]
    fileprivate static let activityStubHeight: CGFloat = 6
    fileprivate static let capsuleMinimumHeight: CGFloat = 6
    fileprivate static let contextSymbolMinimumWidth: CGFloat = 18

    /// One drawable/scrubbable window. `.unscored` windows produce no mark at all —
    /// a literal gap, the way the pace plot drops a bucket with no samples.
    struct Mark: Identifiable, Equatable {
        enum Kind: Equatable {
            case scored(score: Double, band: StressBand)
            case activity
        }

        let id: Int
        let interval: DateInterval
        let xStart: Double
        let xEnd: Double
        let kind: Kind
    }

    private var marks: [Mark] {
        Self.marks(for: windows, in: dayInterval)
    }

    static func marks(for windows: [StressWindow], in dayInterval: DateInterval) -> [Mark] {
        windows.enumerated().compactMap { index, window in
            let kind: Mark.Kind
            if let score = window.score {
                kind = .scored(score: score, band: StressBand.band(for: score))
            } else if window.state == .activity {
                kind = .activity
            } else {
                return nil
            }

            return Mark(
                id: index,
                interval: window.interval,
                xStart: fraction(for: window.interval.start, in: dayInterval),
                xEnd: fraction(for: window.interval.end, in: dayInterval),
                kind: kind
            )
        }
    }

    /// A date's position in the day as a 0...1 fraction of the day's real duration.
    static func fraction(for date: Date, in dayInterval: DateInterval) -> Double {
        guard dayInterval.duration > 0 else { return 0 }
        let raw = date.timeIntervalSince(dayInterval.start) / dayInterval.duration
        return min(1, max(0, raw))
    }

    /// The 00/06/12/18 civil clock marks, positioned by asking the calendar where
    /// those wall-clock times actually fall — on a 23 hour spring-forward day 06:00
    /// is not at 0.25 of the day, and on a 25 hour fall-back day it is not either.
    static func timeMarks(
        for dayInterval: DateInterval,
        calendar: Calendar = .bodyGregorian
    ) -> [BodyStressIntradayTimeMark] {
        [0, 6, 12, 18].compactMap { hour in
            guard let date = calendar.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: dayInterval.start,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ), dayInterval.contains(date) || date == dayInterval.start else {
                return nil
            }

            return BodyStressIntradayTimeMark(
                fraction: fraction(for: date, in: dayInterval),
                label: date.formatted(.dateTime.hour())
            )
        }
    }

    /// Everything a side is built from, in one Equatable value so a single
    /// `onChange` can tell a DAY SWITCH (morph) from a same-day data refresh
    /// (today's windows growing, a background recompute landing — replace in
    /// place, no morph restart).
    private struct SideInput: Equatable {
        var windows: [StressWindow]
        var dayInterval: DateInterval
        var contextIntervals: [BodyHealthMetricDayContextInterval]
    }

    private var sideInput: SideInput {
        SideInput(windows: windows, dayInterval: dayInterval, contextIntervals: contextIntervals)
    }

    private var renderSide: BodyStressPlotSide {
        displayedSide ?? Self.side(for: sideInput)
    }

    private static func side(for input: SideInput) -> BodyStressPlotSide {
        BodyStressPlotSide.make(
            windows: input.windows,
            dayInterval: input.dayInterval,
            contextIntervals: input.contextIntervals
        )
    }

    var body: some View {
        let marks = self.marks

        return GeometryReader { geometry in
            let plotRect = Self.plotRect(in: geometry.size)

            BodyStressIntradayRenderPlot(
                progress: transitionProgress,
                previousSide: previousSide,
                currentSide: renderSide,
                plotRect: plotRect,
                reduceMotion: reduceMotion,
                scrubX: scrubbedMarkID == nil ? nil : scrubX
            )
            .contentShape(Rectangle())
            .gesture(
                // Scrubbing is ignored mid-morph: the marks under the finger are
                // interpolated geometry that belongs to neither day.
                BodyChartScrubGesture(isEnabled: !marks.isEmpty && !isTransitioning) { location in
                    scrub(to: location, marks: marks, plotRect: plotRect, plotFrame: geometry.frame(in: .global))
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValueText(marks))
        .accessibilityAdjustableAction { direction in
            guard !marks.isEmpty else { return }
            switch direction {
            case .increment:
                accessibilityMarkIndex = min(accessibilityMarkIndex + 1, marks.count - 1)
            case .decrement:
                accessibilityMarkIndex = max(accessibilityMarkIndex - 1, 0)
            @unknown default:
                break
            }
        }
        .onAppear {
            // Seed while the props still describe THIS day: by the time
            // `onChange` fires they are already the incoming day's.
            if displayedSide == nil {
                displayedSide = Self.side(for: sideInput)
            }
        }
        .onChange(of: sideInput) { oldInput, newInput in
            if oldInput.dayInterval.start == newInput.dayInterval.start {
                // Same day, new data: swap the destination under the running
                // transition rather than restarting it.
                displayedSide = Self.side(for: newInput)
            } else {
                beginTransition(from: oldInput, to: newInput)
            }
        }
        .onDisappear {
            clearScrub()
        }
    }

    /// Starts (or rebases) the day-switch morph.
    private func beginTransition(from oldInput: SideInput, to newInput: SideInput) {
        transitionGeneration += 1
        let generation = transitionGeneration
        // The old day's callout and rule mean nothing on the new day.
        clearScrub()
        accessibilityMarkIndex = 0

        let outgoingTarget = displayedSide ?? Self.side(for: oldInput)
        let outgoing: BodyStressPlotSide
        if isTransitioning, let previousSide, let transitionStart {
            // Rapid tap: rebase from what is ON SCREEN, not from the destination
            // the superseded transition was heading for.
            let raw = min(1, max(0, Date().timeIntervalSince(transitionStart) / Self.transitionDuration))
            outgoing = BodyStressPlotSide.interpolated(
                from: previousSide,
                to: outgoingTarget,
                at: BodyStressPlotSide.eased(raw),
                reduceMotion: reduceMotion
            )
        } else {
            outgoing = outgoingTarget
        }

        var instant = Transaction()
        instant.animation = nil
        withTransaction(instant) {
            previousSide = outgoing
            displayedSide = Self.side(for: newInput)
            transitionProgress = 0
        }
        isTransitioning = true

        // One runloop turn later, so the progress reset commits before the
        // animation reads it — otherwise the two updates coalesce and 1 → 1
        // animates nothing.
        DispatchQueue.main.async {
            guard generation == transitionGeneration else { return }
            transitionStart = Date()
            withAnimation(.linear(duration: Self.transitionDuration)) {
                transitionProgress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.transitionDuration) {
                guard generation == transitionGeneration else { return }
                isTransitioning = false
                transitionStart = nil
                previousSide = nil
            }
        }
    }

    fileprivate static func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: 0,
            y: 6,
            width: max(1, size.width - Self.yAxisLabelInset),
            height: max(1, size.height - 34)
        )
    }

    // MARK: - Scrubbing

    private func scrub(to location: CGPoint?, marks: [Mark], plotRect: CGRect, plotFrame: CGRect) {
        guard let location, let mark = self.mark(atX: location.x, marks: marks, in: plotRect) else {
            clearScrub()
            return
        }

        let centreX = plotRect.minX + plotRect.width * CGFloat((mark.xStart + mark.xEnd) / 2)
        let callout = BodyChartFloatingCallout(
            anchor: CGPoint(x: plotFrame.minX + centreX, y: plotFrame.minY + plotRect.minY),
            content: AnyView(calloutContent(for: mark)),
            placement: .aboveOrBelow(anchorBottom: plotFrame.minY + plotRect.maxY)
        )

        if scrubX == nil {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                scrubX = centreX
                scrubbedMarkID = mark.id
                floatingCallout?.callout = callout
            }
        } else {
            scrubX = centreX
            scrubbedMarkID = mark.id
            floatingCallout?.callout = callout
        }
    }

    private func clearScrub() {
        guard scrubX != nil || floatingCallout?.callout != nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            scrubX = nil
            scrubbedMarkID = nil
            floatingCallout?.callout = nil
        }
    }

    /// The window under the finger, or the nearest drawn one. `.unscored` stretches
    /// never became marks, so the snap skips straight over a gap to its neighbour.
    private func mark(atX x: CGFloat, marks: [Mark], in plotRect: CGRect) -> Mark? {
        guard plotRect.width > 0, !marks.isEmpty else { return nil }
        let fraction = Double((x - plotRect.minX) / plotRect.width)
        if let hit = marks.first(where: { fraction >= $0.xStart && fraction <= $0.xEnd }) {
            return hit
        }
        return marks.min {
            abs(($0.xStart + $0.xEnd) / 2 - fraction) < abs(($1.xStart + $1.xEnd) / 2 - fraction)
        }
    }

    private func calloutContent(for mark: Mark) -> some View {
        let values: [BodyChartSelectionValue]
        let eyebrow: String
        switch mark.kind {
        case let .scored(score, band):
            eyebrow = band.title.uppercased()
            values = [
                BodyChartSelectionValue(
                    title: nil,
                    value: "\(Int(score.rounded()))",
                    color: BodyStressBandPresentation.color(for: band)
                )
            ]
        case .activity:
            // Masked time has no score, so the callout is the label and the range.
            eyebrow = BodyStressBandPresentation.activityTitle.uppercased()
            values = []
        }

        return BodyChartSelectionAnnotation(
            eyebrow: eyebrow,
            values: values,
            date: mark.interval.start,
            dateText: Self.timeRangeText(for: mark.interval)
        )
        .accessibilityHidden(true)
    }

    static func timeRangeText(for interval: DateInterval) -> String {
        let start = interval.start.formatted(date: .omitted, time: .shortened)
        let end = interval.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    // MARK: - Accessibility

    private func accessibilityValueText(_ marks: [Mark]) -> String {
        guard marks.indices.contains(accessibilityMarkIndex) else { return "" }
        let mark = marks[accessibilityMarkIndex]
        let range = Self.timeRangeText(for: mark.interval)
        switch mark.kind {
        case let .scored(score, band):
            return "\(range), \(Int(score.rounded())), \(band.title)"
        case .activity:
            return "\(range), \(BodyStressBandPresentation.activityTitle)"
        }
    }
}

/// The plot's render half: an ordinary `Animatable` view whose `animatableData`
/// is the transition's progress, so SwiftUI re-evaluates the Canvas every frame
/// with a freshly interpolated side. All state (which days, which generation)
/// lives in `BodyStressIntradayPlot`; this struct only draws.
private struct BodyStressIntradayRenderPlot: View, Animatable {
    var progress: Double
    var previousSide: BodyStressPlotSide?
    var currentSide: BodyStressPlotSide
    var plotRect: CGRect
    var reduceMotion: Bool
    var scrubX: CGFloat?

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// What is on screen right now.
    private var side: BodyStressPlotSide {
        guard let previousSide else { return currentSide }
        return BodyStressPlotSide.interpolated(
            from: previousSide,
            to: currentSide,
            at: BodyStressPlotSide.eased(progress),
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        let side = self.side

        ZStack {
            Canvas { context, _ in
                drawContextBands(side.contextBands, in: plotRect, context: &context)
                drawGrid(in: plotRect, context: &context)
                drawTracks(side.tracks, in: plotRect, context: &context)
                drawTimeMarks(side.timeMarks, in: plotRect, context: &context)
                drawSelection(in: plotRect, context: &context)
            }

            // The no-data state is an OVERLAY, never a replacement view: swapping
            // the plot for a `Text` would tear down the coordinator and lose the
            // transition, so data ↔ empty fades like every other day switch.
            Text("No data for this day")
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(side.emptiness)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Drawing

    /// Sleep and workout shading, drawn first so the grid and the marks sit on top —
    /// the same translucent fill plus full-colour top stripe the Swift Charts day
    /// chart uses, ported to Canvas.
    private func drawContextBands(
        _ bands: [BodyStressPlotContextBand],
        in plotRect: CGRect,
        context: inout GraphicsContext
    ) {
        let stripeHeight = max(1.5, plotRect.height * CGFloat(BodyHealthMetricDayContextBand.topStripeHeightRatio))

        for band in bands where band.opacity > 0.001 {
            let leading = plotRect.minX + plotRect.width * CGFloat(band.xStart)
            let trailing = plotRect.minX + plotRect.width * CGFloat(band.xEnd)
            let width = trailing - leading
            guard width > 0 else { continue }

            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: plotRect.height)),
                with: .color(band.color.opacity(band.fillOpacity * band.opacity))
            )
            context.fill(
                Path(CGRect(x: leading, y: plotRect.minY, width: width, height: stripeHeight)),
                with: .color(band.color.opacity(band.opacity))
            )

            guard width >= BodyStressIntradayPlot.contextSymbolMinimumWidth else { continue }
            context.draw(
                context.resolve(
                    Text(Image(systemName: band.symbolName))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(band.color.opacity(band.opacity))
                ),
                at: CGPoint(x: leading + width / 2, y: plotRect.minY + stripeHeight + 9)
            )
        }
    }

    private func drawGrid(in plotRect: CGRect, context: inout GraphicsContext) {
        var grid = Path()
        for fraction in BodyStressIntradayPlot.gridFractions {
            let y = self.y(for: fraction, in: plotRect)
            grid.move(to: CGPoint(x: plotRect.minX, y: y))
            grid.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(
            grid,
            with: .color(Color.secondary.opacity(0.26)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
        )

        let fractions = BodyStressIntradayPlot.gridFractions
        for (index, label) in BodyStressIntradayPlot.gridLabels.enumerated() where index < fractions.count {
            context.draw(
                bodyStressChartAxisLabel(label, in: context),
                at: CGPoint(x: plotRect.maxX + 22, y: y(for: fractions[index], in: plotRect))
            )
        }
    }

    private func drawTracks(
        _ tracks: [BodyStressPlotTrack],
        in plotRect: CGRect,
        context: inout GraphicsContext
    ) {
        for track in tracks where track.opacity > 0.001 {
            let leading = plotRect.minX + plotRect.width * CGFloat(track.xStart) + 1
            let trailing = plotRect.minX + plotRect.width * CGFloat(track.xEnd) - 1
            let width = max(2, trailing - leading)

            if track.isActivity {
                let stub = CGRect(
                    x: leading,
                    y: plotRect.maxY - BodyStressIntradayPlot.activityStubHeight,
                    width: width,
                    height: BodyStressIntradayPlot.activityStubHeight
                )
                context.fill(
                    Path(roundedRect: stub, cornerRadius: width / 2),
                    with: .color(BodyStressBandPresentation.activityColor.opacity(track.opacity))
                )
                continue
            }

            let color = track.rgb.color
            let valueY = y(for: track.score / 100, in: plotRect)

            context.fill(
                Path(
                    roundedRect: CGRect(
                        x: leading,
                        y: valueY,
                        width: width,
                        height: max(0, plotRect.maxY - valueY)
                    ),
                    cornerRadius: min(2, width / 2)
                ),
                with: .color(color.opacity(0.10 * track.opacity))
            )

            // A window carries one score, not a range, so every capsule uses the
            // pace plot's centred fixed-height form.
            let capsule = CGRect(
                x: leading,
                y: valueY - BodyStressIntradayPlot.capsuleMinimumHeight / 2,
                width: width,
                height: BodyStressIntradayPlot.capsuleMinimumHeight
            )
            context.fill(
                Path(roundedRect: capsule, cornerRadius: width / 2),
                with: .color(color.opacity(track.opacity))
            )
        }
    }

    private func drawTimeMarks(
        _ marks: [BodyStressPlotTimeMark],
        in plotRect: CGRect,
        context: inout GraphicsContext
    ) {
        let lowerBound = plotRect.minX + BodyStressIntradayPlot.timeMarkLabelHorizontalInset
        let upperBound = max(lowerBound, plotRect.maxX - BodyStressIntradayPlot.timeMarkLabelHorizontalInset)
        for mark in marks where mark.opacity > 0.001 {
            let rawX = plotRect.minX + plotRect.width * CGFloat(mark.fraction)
            context.draw(
                context.resolve(
                    Text(mark.label)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.secondary.opacity(mark.opacity))
                ),
                at: CGPoint(
                    x: min(max(rawX, lowerBound), upperBound),
                    y: plotRect.maxY + BodyStressIntradayPlot.xAxisLabelOffset
                )
            )
        }
    }

    private func drawSelection(in plotRect: CGRect, context: inout GraphicsContext) {
        guard let scrubX else { return }

        var rule = Path()
        rule.move(to: CGPoint(x: scrubX, y: plotRect.minY))
        rule.addLine(to: CGPoint(x: scrubX, y: plotRect.maxY))
        context.stroke(rule, with: .color(Color.secondary.opacity(0.48)), lineWidth: 1.4)
    }

    private func y(for fraction: Double, in plotRect: CGRect) -> CGFloat {
        plotRect.maxY - plotRect.height * CGFloat(min(1, max(0, fraction)))
    }
}

/// The day's time breakdown, in the same row language as
/// `BodySleepStageOptimalRangeChart`: a label, a gray track with a coloured fill, a
/// percentage and a duration. Five rows — the four bands plus Activity, which is a
/// display category rather than a band, so the percentages share the scored +
/// masked denominator and the rows account for the whole measured day. There is no
/// "optimal" stress band, so the dashed boxes read as the user's OWN typical share
/// of each band rather than a target — and the Activity row has none at all.
struct BodyStressDayBreakdownRows: View {
    let summary: StressDaySummary?
    /// The recorded history the personal baseline is computed from. Empty (the
    /// default) simply means no boxes.
    var recordedDays: [StressDaySummary] = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Recomputed when the recorded history changes, not once per appearance:
    /// the stress backfill publishes new recorded days while this view is
    /// mounted, and a once-only compute would freeze the boxes at whatever the
    /// history was when the detail view opened.
    @State private var baselineShares: [StressBand: Double]?

    /// The legend text, resolved through a dotted key: a bare "Personal baseline"
    /// would land in the catalog under a generic phrase other features could
    /// inherit.
    static var baselineLegendTitle: String {
        String(localized: "stress.stage.baselineLegend", defaultValue: "Personal baseline")
    }

    // Duplicated from `BodySleepStageOptimalRangeChart`, whose constants are private.
    private let labelWidth: CGFloat = 52
    private let percentColumnWidth: CGFloat = 44
    private let durationColumnWidth: CGFloat = 68
    private let columnSpacing: CGFloat = 12
    private let trackHeight: CGFloat = 22
    private let barHeight: CGFloat = 14

    private struct Row: Identifiable {
        let id: String
        let label: String
        let color: Color
        let minutes: Int
        /// nil on the Activity row, and on every row until the baseline exists.
        let baselineRange: ClosedRange<Double>?
    }

    private var totalMinutes: Int {
        summary?.totalMeasuredMinutes ?? 0
    }

    private var rows: [Row] {
        let bandRows = StressBand.displayOrder.map { band in
            Row(
                id: band.rawValue,
                label: band.title,
                color: BodyStressBandPresentation.color(for: band),
                minutes: summary?.minutes(in: band) ?? 0,
                baselineRange: baselineShares?[band].map(StressScoreCalculator.baselineShareRange(around:))
            )
        }

        return bandRows + [
            Row(
                id: "activity",
                label: BodyStressBandPresentation.activityTitle,
                color: BodyStressBandPresentation.activityColor,
                minutes: summary?.activityMinutes ?? 0,
                baselineRange: nil
            )
        ]
    }

    var body: some View {
        content
            .onAppear(perform: refreshBaselineShares)
            .onChange(of: recordedDays) { _, _ in
                refreshBaselineShares()
            }
    }

    @ViewBuilder
    private var content: some View {
        if totalMinutes == 0 {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    self.row(row)
                }

                if baselineShares != nil {
                    legend
                        .padding(.top, 2)
                }
            }
        }
    }

    private func refreshBaselineShares() {
        baselineShares = StressScoreCalculator.baselineBandShares(from: recordedDays)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.45))

            Text("No Stress yet today")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func row(_ row: Row) -> some View {
        let fraction = totalMinutes > 0 ? Double(row.minutes) / Double(totalMinutes) : 0
        let percentText = "\(Int((fraction * 100).rounded()))%"
        let durationText = BodyValueFormat.durationText(for: TimeInterval(row.minutes) * 60)

        return HStack(spacing: columnSpacing) {
            Text(row.label)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: labelWidth, alignment: .leading)

            track(fraction: fraction, color: row.color, baselineRange: row.baselineRange)
                .frame(maxWidth: .infinity)
                .frame(height: trackHeight)

            Text(percentText)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .bodyLegendNumberFlip(value: percentText)
                .frame(width: percentColumnWidth, alignment: .trailing)

            Text(durationText)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .bodyLegendNumberFlip(value: durationText)
                .frame(width: durationColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label), \(percentText), \(durationText)")
    }

    private func track(fraction: Double, color: Color, baselineRange: ClosedRange<Double>?) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fillWidth = CGFloat(min(1, max(0, fraction))) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(height: barHeight)

                Capsule()
                    .fill(color)
                    .frame(width: fillWidth, height: barHeight)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: fraction)

                // Day-independent, so it carries no animation of its own: it must
                // stay put while the bar beside it morphs between days.
                if let baselineRange {
                    baselineBox
                        .frame(
                            width: max(0, CGFloat(baselineRange.upperBound - baselineRange.lowerBound) * width),
                            height: trackHeight
                        )
                        .offset(x: CGFloat(baselineRange.lowerBound) * width)
                }
            }
            .frame(height: trackHeight)
        }
    }

    /// `BodySleepStageOptimalRangeChart.optimalBand`'s styling, reused verbatim so
    /// the two breakdowns read as the same control.
    private var baselineBox: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        Color.secondary.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
            )
    }

    private var legend: some View {
        HStack(spacing: 8) {
            baselineBox
                .frame(width: 22, height: 14)

            Text(Self.baselineLegendTitle)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
