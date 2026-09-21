import SwiftUI

/// The Day Ring star hero: an inner 24 hour dial with hour ticks and a thick line at now, an
/// outer bar that only draws the day's sleep and workouts, and the share of the day
/// that has passed in the middle.
struct BodyDayRingHero: View {
    private typealias Geometry = BodyDayRingGeometry

    let sleepSegments: [SleepStageSegment]
    /// Any superset of the day's workouts; the timeline keeps the ones that overlap it.
    let workouts: [WorkoutSummary]
    let width: CGFloat
    /// Whether the caption shows under the number (Settings > Home Hero > Day Caption).
    var showsCaption = true
    var mainSleepInterval: DateInterval?
    /// Warning signs mirrored from the Home cards, drawn under the number as on the
    /// Readiness Ring. Drawing only: the host overlays the tap targets.
    var warningBadges: [BodyReadinessHeroWarningBadge] = []
    /// 0 = the full ring with the number, 1 = the flat bar pinned under the status bar,
    /// the Readiness Ring's scroll morph.
    var progress: Double = 0
    /// Points the page has been pulled down past rest. As on the Readiness Ring, the hero
    /// holds its place on screen while the ring is dragged open, then bounces home.
    var pull: CGFloat = 0
    /// Previews and render tests only: freezes the clock.
    var previewDate: Date?

    @Environment(\.workoutColorPalette) private var workoutColorPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The Readiness Ring's stretch pair: `stretch` follows the pull and springs back on
    /// release, `trailingStretch` lags it at the ring's ends so the bounce ripples outward.
    @State private var stretch: CGFloat = 0
    @State private var trailingStretch: CGFloat = 0
    @State private var isStretchReleasing = false
    /// Off until the hero is on screen, so the now line sweeps in from midnight and the
    /// number counts up from zero, as the Readiness Ring's pill and score do.
    @State private var hasAppeared = false
    /// How far short of now the pointer's sweep in stops, as a share of the day. A loose
    /// spring then carries it the rest of the way, so it runs a little past now, comes
    /// back, and swings a few more times before it lands.
    @State private var landingShortfall = Self.landingRunUp
    private static let landingRunUp: Double = 0.03

    var body: some View {
        // One clock for the whole hero: the day, ticks, spans, marker, number and the
        // spoken summary all come from the same `now`, so they roll over together.
        TimelineView(.everyMinute) { context in
            let timeline = DayRingTimeline.make(
                now: previewDate ?? context.date,
                calendar: .bodyGregorian,
                sleepSegments: sleepSegments,
                mainSleepInterval: mainSleepInterval,
                workouts: workouts
            )
            // A frozen preview has no appearance to wait for.
            let isSettled = hasAppeared || reduceMotion || previewDate != nil
            let nowFraction = isSettled ? timeline.nowFraction : 0
            let percent = isSettled ? timeline.percentPassed : 0
            ZStack(alignment: .topLeading) {
                trackView(.dial, timeline: timeline, nowFraction: nowFraction)
                    // Each minute's step, and the sweep in, glide rather than jump.
                    .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: nowFraction)

                // Every activity bar is its own layer, so one that arrives fades in
                // instead of popping onto the ring.
                let spans = isSettled ? Array(timeline.spans.enumerated()) : []
                ZStack(alignment: .topLeading) {
                    ForEach(spans, id: \.element.fadeID) { index, _ in
                        trackView(.span(index), timeline: timeline, nowFraction: nowFraction)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: spans.map(\.element.fadeID))

                // A frozen preview and Reduce Motion show the pointer already landed.
                let shortfall = (reduceMotion || previewDate != nil) ? 0 : landingShortfall
                trackView(.now, timeline: timeline, nowFraction: max(nowFraction - shortfall, 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.53), value: nowFraction)

                let textOpacity = BodyReadinessArcGeometry.textOpacity(progress: min(max(progress, 0), 1), width: width)
                ZStack(alignment: .topLeading) {
                    centerText(percent: percent)
                }
                .frame(width: width, height: BodyReadinessArcGeometry.heroHeight(width: width), alignment: .topLeading)
                .opacity(textOpacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: textBlockLayout)

                BodyHeroWarningBadgeRow(badges: warningBadges, opacity: textOpacity)
                    .position(x: width / 2, y: BodyReadinessArcGeometry.badgeRowCenterY(width: width))
            }
            .offset(y: -pull)
            .frame(width: width, height: BodyReadinessArcGeometry.heroHeight(width: width), alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(timeline))
        }
        .onAppear {
            hasAppeared = true
            guard !reduceMotion, previewDate == nil else {
                // No entrance to play, so nothing may be left to hold the pointer back
                // if Reduce Motion is turned off while the hero stays on screen.
                landingShortfall = 0
                return
            }
            // Takes over as the sweep runs out: underdamped, so the landing bounces. It
            // starts in a later update than the sweep, or the sweep's own animation
            // would claim this change too and the pointer would land without a bounce.
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

    private func trackView(_ layer: BodyDayRingTrackView.Layer, timeline: DayRingTimeline, nowFraction: Double) -> some View {
        BodyDayRingTrackView(
            layer: layer,
            timeline: timeline,
            nowFraction: nowFraction,
            progress: min(max(progress, 0), 1),
            width: width,
            stretch: stretch,
            trailingStretch: trailingStretch,
            sleepColor: BodyHomeCardKind.sleep.tintColor,
            workoutColor: { workoutColorPalette.color(for: $0) }
        )
    }

    /// The Readiness Ring's `followPull`: the ring follows the finger while the pull
    /// grows, and the first frame it shrinks a bouncy spring carries it home on its own.
    /// Reduce Motion leaves the ring unstretched.
    private func followPull(from oldPull: CGFloat, to newPull: CGFloat) {
        guard !reduceMotion else { return }
        if newPull > oldPull {
            isStretchReleasing = false
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                stretch = BodyReadinessArcGeometry.pullStretch(pull: newPull)
                trailingStretch = stretch
            }
        } else if !isStretchReleasing {
            isStretchReleasing = true
            let spring = Animation.interpolatingSpring(mass: 1, stiffness: 220, damping: 7)
            withAnimation(spring) {
                stretch = 0
            }
            withAnimation(spring.delay(BodyReadinessArcGeometry.rippleDelay)) {
                trailingStretch = 0
            }
        }
        if newPull <= 0 {
            isStretchReleasing = false
        }
    }

    // MARK: - Center text (the Readiness Ring's score block and its rules)

    private static let captionHeight: CGFloat = 18
    private static let captionGap: CGFloat = 4
    /// How far the number and caption drop while no warning badge is showing, so the
    /// block doesn't float over an empty badge row: 40% of a badge's height.
    private static let noBadgeDrop: CGFloat = BodyReadinessArcGeometry.badgeRowHeight * 0.4

    /// What the block's position depends on. A change glides it to its new place.
    private struct TextBlockLayout: Equatable {
        let showsCaption: Bool
        let hasBadges: Bool
    }

    private var textBlockLayout: TextBlockLayout {
        // Badges only move the block while the caption shows.
        TextBlockLayout(showsCaption: showsCaption, hasBadges: showsCaption && !warningBadges.isEmpty)
    }

    /// Without the caption the number keeps its centered place whether or not badges
    /// show; only the number and caption block lifts for the caption and drops without
    /// badges, exactly as the Readiness Ring's score and level do.
    private var numberCenterY: CGFloat {
        let centered = BodyReadinessArcGeometry.numberCenterY(width: width)
        guard showsCaption else { return centered }
        return centered - Self.captionHeight - Self.captionGap + (warningBadges.isEmpty ? Self.noBadgeDrop : 0)
    }

    @ViewBuilder
    private func centerText(percent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(percent)")
                .font(.system(size: 66, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(percent)))
                .lineLimit(1)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: percent)

            Text("%")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .opacity(0.9)
        }
        .fixedSize()
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .position(x: width / 2 + 6, y: numberCenterY)

        if showsCaption {
            Text("Today passed")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
                .position(
                    x: width / 2,
                    y: numberCenterY + BodyReadinessArcGeometry.numberHalfHeight + Self.captionGap + Self.captionHeight / 2
                )
                .transition(.opacity)
        }
    }

    private func accessibilityLabel(_ timeline: DayRingTimeline) -> String {
        let sleepText = BodyValueFormat.durationText(for: timeline.sleepDuration)
        return String(
            localized: "Day Ring, \(timeline.percentPassed) percent of the day passed, \(sleepText) asleep, \(timeline.workoutCount) workouts"
        )
    }
}
