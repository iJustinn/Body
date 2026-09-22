//
//  WatchDayRingHeroView.swift
//  BodyWatch
//
//  The iOS Day Ring hero (`BodyDayRingHero` in `Body/Views/BodyDayRingHero.swift`)
//  on the watch home screen, shown when the phone's Settings ▸ Home Hero is the
//  Day Ring. It draws the same shared `BodyDayRingTrackView`, laid out at
//  `WatchReadinessHero.referenceWidth` and scaled down to the watch exactly as
//  `WatchReadinessHeroView` is, so it rides the same pin, pull and flatten. The
//  entrance and stretch state below mirror the iOS hero's: keep the two in step.
//
//  What the watch leaves out: the warning badges (they point at Home cards the
//  watch doesn't have). The night comes from the snapshot's `sleepStages` and
//  the workouts from its `dayRingWorkouts`, both published by the phone.
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

struct WatchDayRingHeroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sleepStages: [WatchSleepStageSegment]
    let workouts: [WatchDayRingWorkout]
    /// The phone's Day Caption switch: "Today passed" under the number.
    var showsCaption = true
    /// The width the hero draws at on the watch.
    let width: CGFloat
    /// 0 = the full ring with the number, 1 = the flat pinned bar. Clamped here.
    let progress: Double
    /// Points the page has been pulled down past rest, in watch points.
    var pull: CGFloat = 0
    /// Previews only: freezes the clock.
    var previewDate: Date?

    @State private var stretch: CGFloat = 0
    @State private var trailingStretch: CGFloat = 0
    @State private var isStretchReleasing = false
    @State private var hasAppeared = false
    @State private var landingShortfall = Self.landingRunUp
    private static let landingRunUp: Double = 0.03

    private typealias Geometry = BodyReadinessArcGeometry
    private var referenceWidth: CGFloat { WatchReadinessHero.referenceWidth }
    private var scale: CGFloat { WatchReadinessHero.scale(width: width) }
    private var clampedProgress: Double { min(max(progress, 0), 1) }

    private static let sleepColor = Color(red: 0.20, green: 0.72, blue: 1.00)

    /// The phone resolves each workout's color, custom colors included.
    private var colorHexByType: [BodyWorkoutType: UInt32] {
        Dictionary(
            workouts.compactMap { workout in BodyWorkoutType(rawValue: workout.type).map { ($0, workout.colorHex) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var ringWorkouts: [DayRingTimeline.Workout] {
        workouts.compactMap { workout in
            guard let id = UUID(uuidString: workout.id), let type = BodyWorkoutType(rawValue: workout.type) else {
                return nil
            }
            return DayRingTimeline.Workout(id: id, start: workout.startDate, end: workout.endDate, type: type)
        }
    }

    var body: some View {
        let sleepSegments = WatchSleepStagesChartView.segments(from: sleepStages)
        let ringWorkouts = ringWorkouts
        let colorHexByType = colorHexByType
        // One clock for the whole hero, as on the phone.
        TimelineView(.everyMinute) { context in
            let timeline = DayRingTimeline.make(
                now: previewDate ?? context.date,
                calendar: .bodyGregorian,
                sleepSegments: sleepSegments,
                ringWorkouts: ringWorkouts
            )
            let isSettled = hasAppeared || reduceMotion || previewDate != nil
            let nowFraction = isSettled ? timeline.nowFraction : 0
            let percent = isSettled ? timeline.percentPassed : 0
            let workoutColor: (BodyWorkoutType) -> Color = { type in
                BodyWorkoutType.attachedWorkoutColor(hex: colorHexByType[type] ?? type.colorHex)
            }
            ZStack(alignment: .topLeading) {
                // Laid out at the phone's width and scaled from its top-left corner, so
                // the paths are the phone's paths.
                ZStack(alignment: .topLeading) {
                    trackView(.dial, timeline: timeline, nowFraction: nowFraction, workoutColor: workoutColor)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: nowFraction)

                    let segments = isSettled
                        ? Array(BodyDayRingGeometry.segments(for: timeline, trackLength: BodyDayRingGeometry.track(width: referenceWidth).dayLength).enumerated())
                        : []
                    ZStack(alignment: .topLeading) {
                        ForEach(segments, id: \.element.fadeID) { index, _ in
                            trackView(.segment(index), timeline: timeline, nowFraction: nowFraction, workoutColor: workoutColor)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: segments.map(\.element.fadeID))

                    let shortfall = (reduceMotion || previewDate != nil) ? 0 : landingShortfall
                    trackView(.now, timeline: timeline, nowFraction: max(nowFraction - shortfall, 0), workoutColor: workoutColor)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.53), value: nowFraction)
                }
                .frame(width: referenceWidth, height: Geometry.heroHeight(width: referenceWidth), alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: width, height: WatchReadinessHero.height(width: width), alignment: .topLeading)

                centerText(percent: percent)
                    .position(x: width / 2, y: (Geometry.numberCenterY(width: referenceWidth) - captionLineOffset) * scale)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: showsCaption)
            }
            .offset(y: -pull)
            .frame(width: width, height: WatchReadinessHero.height(width: width), alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Day Ring, \(timeline.percentPassed) percent of the day passed"))
        }
        // Nothing here opens anything, and the pin raises the flattened hero over the
        // first card, so it must never take that card's taps.
        .allowsHitTesting(false)
        .transaction(value: width) { $0.animation = nil }
        .onAppear {
            hasAppeared = true
            guard !reduceMotion, previewDate == nil else {
                landingShortfall = 0
                return
            }
            // The phone hero's landing: a later update than the sweep, so it bounces.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.33))
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 202.5, damping: 6.75)) {
                    landingShortfall = 0
                }
            }
        }
        .onChange(of: pull) { oldPull, newPull in
            followPull(from: oldPull, to: newPull)
        }
    }

    private func trackView(
        _ layer: BodyDayRingTrackView.Layer,
        timeline: DayRingTimeline,
        nowFraction: Double,
        workoutColor: @escaping (BodyWorkoutType) -> Color
    ) -> some View {
        BodyDayRingTrackView(
            layer: layer,
            timeline: timeline,
            nowFraction: nowFraction,
            progress: clampedProgress,
            width: referenceWidth,
            stretch: stretch,
            trailingStretch: trailingStretch,
            sleepColor: Self.sleepColor,
            workoutColor: workoutColor
        )
    }

    /// The pull is in watch points; the geometry's stretch curve is in phone points.
    private func followPull(from oldPull: CGFloat, to newPull: CGFloat) {
        guard !reduceMotion else { return }
        if newPull > oldPull {
            isStretchReleasing = false
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                stretch = Geometry.pullStretch(pull: newPull / max(scale, 0.001))
                trailingStretch = stretch
            }
        } else if !isStretchReleasing {
            isStretchReleasing = true
            let spring = Animation.interpolatingSpring(mass: 1, stiffness: 220, damping: 7)
            withAnimation(spring) {
                stretch = 0
            }
            withAnimation(spring.delay(Geometry.rippleDelay)) {
                trailingStretch = 0
            }
        }
        if newPull <= 0 {
            isStretchReleasing = false
        }
    }

    // MARK: - Center text (the watch Readiness Ring's score and level block)

    private static let captionLineHeight: CGFloat = 26
    private static let captionLineSpacing: CGFloat = -6

    private var captionLineOffset: CGFloat {
        showsCaption ? (Self.captionLineHeight - Self.captionLineSpacing) / 2 : 0
    }

    private func centerText(percent: Int) -> some View {
        VStack(spacing: Self.captionLineSpacing * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 2 * scale) {
                Text(verbatim: "\(percent)")
                    .font(.system(size: 66 * scale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(percent)))
                    .lineLimit(1)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: percent)

                Text(verbatim: "%")
                    .font(.system(size: 30 * scale, weight: .semibold, design: .rounded))
                    .opacity(0.9)
            }
            .fixedSize()
            .foregroundStyle(.primary)
            .offset(x: 6 * scale)

            if showsCaption {
                Text("Today passed")
                    .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: Self.captionLineHeight * scale)
                    .transition(.opacity)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.3), radius: 6 * scale, y: 1 * scale)
        .opacity(Geometry.textOpacity(progress: clampedProgress, width: referenceWidth))
    }
}

#Preview("Day Ring hero") {
    WatchDayRingHeroView(
        sleepStages: WatchMetricsSnapshot.placeholder.sleepStages ?? [],
        workouts: [],
        width: 176,
        progress: 0
    )
}
