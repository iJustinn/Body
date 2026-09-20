//
//  BodyReadinessStarHero.swift
//  Body
//

import SwiftUI

/// One warning sign mirrored onto the readiness hero from the Home card that is
/// already showing it. Built from the finished card models rather than from the
/// warning events, so the hero can never draw a glyph or a tint the card itself
/// isn't drawing.
struct BodyReadinessHeroWarningBadge: Identifiable, Equatable {
    let card: BodyHomeCardKind
    let symbolName: String
    let color: Color
    /// Spoken by the badge's button. Body Radar names its verdict; the heart
    /// cards fall back to their own localized title.
    let accessibilityLabel: String

    /// Namespaces the badge away from the scroll id of the very card it points at.
    /// Both live in Home's one ScrollView, so while this was the bare raw value the
    /// badge answered to the card's name too, and it sits near the top of the page
    /// where centering it is already satisfied at offset 0: `scrollTo` resolved to
    /// the badge and the page never moved, while the glow, which matches on the card
    /// rather than on the id, lit the right card off-screen below. Same reason
    /// `BodyHomeTrendCard.Model` carries one; that comment has the longer story.
    static let scrollIDPrefix = "hero-badge-"

    var id: String {
        Self.scrollIDPrefix + card.rawValue
    }

    /// The badges for the cards currently in the Home grid that are showing a
    /// warning glyph, in the order the grid lays them out. `visibleCards` is the
    /// grid's own order, so a card the user turned off contributes nothing and
    /// there is nowhere for a badge to point that isn't on screen.
    ///
    /// Only five cards can ever set `warningSymbolName` (Heart Rate, Blood
    /// Oxygen, Respiratory Rate, Skin Temp, Body Radar), so the row is capped by
    /// construction rather than by a `prefix` here.
    static func badges(
        visibleCards: [BodyHomeCardKind],
        lookup: [HealthMetricKind: BodyHealthMetricCard.Model]
    ) -> [BodyReadinessHeroWarningBadge] {
        visibleCards.compactMap { card in
            guard let metricKind = card.healthMetricKind,
                  let model = lookup[metricKind],
                  let symbolName = model.warningSymbolName else {
                return nil
            }

            return BodyReadinessHeroWarningBadge(
                card: card,
                symbolName: symbolName,
                color: model.warningColor,
                // `title` is a raw catalog key the card localizes at render time,
                // so it has to be resolved here rather than spoken as written.
                accessibilityLabel: model.warningAccessibilityLabel
                    ?? String(localized: String.LocalizationValue(model.title))
            )
        }
    }
}

/// Reports each hero badge glyph's bounds so the tap targets can be laid over
/// them from outside the hero's own button. The glyphs sit inside that button's
/// label, where a nested button never receives a tap and a SwiftUI gesture
/// fights the button (see `BodyReadinessCommentRegenerateGesture`), so the row
/// draws here and `BodyHomeView` overlays real buttons on top.
struct BodyReadinessHeroBadgeAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// The warning signs under a hero's number, each the same glyph and tint its own Home
/// card is showing. Shared by the Readiness Ring and the Day Ring. Publishes its glyphs'
/// bounds so the host can lay tap targets over them; nothing here is interactive.
struct BodyHeroWarningBadgeRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let badges: [BodyReadinessHeroWarningBadge]
    /// The hero's text opacity, so the row fades with the number as the ring flattens.
    let opacity: Double

    /// The width of one badge's box, and so of the tap target laid over it. Three
    /// badges have to share the row; one or two can spend it.
    private var badgeSlotWidth: CGFloat {
        switch badges.count {
        case 0, 1:
            return 44
        case 2:
            return 36
        default:
            return 28
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(badges) { badge in
                Image(systemName: badge.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(badge.color)
                    // A fixed box rather than the glyph's own size, so the tap
                    // targets laid over the badges are all the same. The host
                    // gives the targets their height back.
                    .frame(width: badgeSlotWidth, height: 28)
                    .anchorPreference(key: BodyReadinessHeroBadgeAnchorKey.self, value: .bounds) {
                        [badge.id: $0]
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .opacity(opacity)
        // The same fade the card badges use, so a warning arriving mid-refresh
        // reads as one change in both places.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: badges)
    }
}

/// The Home readiness gauge: five glass bar segments, one per readiness band, on an
/// arc over the big score, with a more opaque pill inside today's band marking the
/// score. `progress` (0 = arc, 1 = flat) is scroll-driven by the host: the arc unfurls
/// into a horizontal bar held under the status bar while the score and warning badges
/// fade out, then leaves with the cards. Pure: no scroll state, so onboarding and tests
/// render it as-is.
/// Today's level ("High readiness") sits under the score; the explanation lives in
/// `BodyReadinessHeroComment` beneath the hero.
struct BodyReadinessArcHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let readiness: ReadinessSummary

    /// The width the hero draws at. The ring's radius, and with it the hero's height,
    /// follow it, so the host (which knows its page width) passes it in rather than the
    /// hero measuring a frame it is itself sizing.
    let width: CGFloat

    /// 0 = full arc with the score, 1 = the flat pinned bar. Clamped here.
    let progress: Double

    /// Points the page has been pulled down past rest. The score, level and warning badges
    /// are counter-offset so
    /// it stays put on screen while the ring, whose top is held the same way, is dragged
    /// open after the finger (bigger, wider sweep, bands pulling apart) and springs back
    /// on release. Zero everywhere but Home.
    var pull: CGFloat = 0

    /// Warning signs mirrored from the Home cards, drawn under the score. Drawing
    /// only: the taps are handled by buttons the host overlays on these glyphs,
    /// outside the hero's own button. Empty everywhere but Home.
    var warningBadges: [BodyReadinessHeroWarningBadge] = []

    /// Whether today's level shows under the score (Settings > Home Hero > Readiness Level).
    /// Off, the score sits centered in the ring as it does without a score.
    var showsLevel = true

    /// Animated score for the big number: counts up from 0 on launch and rolls to each
    /// new value.
    @State private var displayedScore = 0

    /// The score the pill sits at. Animates separately from the scroll-driven geometry,
    /// so a score change slides the pill while a scroll frame mid-slide just moves the
    /// track under it without cancelling the spring.
    @State private var presentedScore: Double = 0

    /// The animation of the move in flight: the bouncing spring, or a critically damped
    /// one when the bounce would carry the pill across a band edge.
    @State private var pillAnimation: Animation?

    /// The ring's stretch, 0...1. Follows the pull directly while the finger drags and
    /// springs back to zero from the moment the pull starts to let go.
    @State private var stretch: CGFloat = 0
    /// The stretch at the ring's ends, which trails `stretch` on the release so the
    /// bounce ripples outward from the middle band.
    @State private var trailingStretch: CGFloat = 0
    @State private var isStretchReleasing = false
    @Environment(BodyReadinessHeroState.self) private var heroState: BodyReadinessHeroState?
    @State private var glowTask: Task<Void, Never>?
    @State private var returnTask: Task<Void, Never>?

    private typealias Geometry = BodyReadinessArcGeometry

    private var status: ReadinessStatus { readiness.status }
    private var clampedProgress: Double { min(max(progress, 0), 1) }

    private var numberText: String {
        readiness.score == nil ? "--" : "\(displayedScore)"
    }

    /// Opacity of the score and badges for a scroll progress; shared with the host so
    /// the badge tap targets switch off at the same moment the glyphs vanish.
    static func textOpacity(progress: Double, width: CGFloat) -> Double {
        Geometry.textOpacity(progress: progress, width: width)
    }

    static func isTextVisible(progress: Double, width: CGFloat) -> Bool {
        Geometry.isTextVisible(progress: progress, width: width)
    }

    private var textOpacity: Double { Self.textOpacity(progress: clampedProgress, width: width) }
    private var isTextVisible: Bool { Self.isTextVisible(progress: clampedProgress, width: width) }

    /// Underdamped on purpose: the pill overshoots its mark, swings back past it, and
    /// settles over a couple of shrinking bounces, the slosh the old wave fill had. The
    /// track clamps its position, so the overshoot can't leave the band's cap.
    private static let bouncingDotAnimation = Animation.interpolatingSpring(
        mass: Geometry.pillSpringMass,
        stiffness: Geometry.pillSpringStiffness,
        damping: Geometry.pillSpringDamping
    )

    /// For a target at the far edge of its band, where a bounce would cross into the
    /// next band: a timed ease-out with no overshoot.
    private static let settlingDotAnimation = Animation.easeOut(duration: 0.7)

    /// For a target at the near edge of its band, where a swing back would cross into
    /// the band the pill came from: a quick rush past the target into the band, then a
    /// slower return to it. Timed curves rather than springs, so the pill is never
    /// parked against the previous band's cap (the track clamps it there) waiting for a
    /// spring's tail to carry it over the edge.
    private static let rushDotAnimation = Animation.easeIn(duration: 0.32)
    private static let returnDotAnimation = Animation.easeInOut(duration: 0.6)
    private static let rushDuration: Duration = .milliseconds(320)

    /// Slides the pill to `score`. The page glow switches off as the pill sets off and
    /// fades back in on the target band a fixed `glowDelay` later, so the color never
    /// leads the pill. A newer move cancels an older one's pending fade-in.
    private func movePill(to score: Int?, from oldScore: Int? = nil, isLaunchSlide: Bool = false) {
        let dropsSharply = (oldScore ?? 0) - (score ?? 0) >= Self.sharpDropPoints
        let target = Double(score ?? 0)
        let landedStatus: ReadinessStatus? = score.map { Geometry.segmentOrder[Geometry.segmentIndex(forScore: $0)] }
        if reduceMotion {
            placePill(at: score)
            return
        }
        heroState?.activeStatus = nil
        returnTask?.cancel()
        switch Geometry.pillMove(from: presentedScore, to: target) {
        case .bounce:
            pillAnimation = Self.bouncingDotAnimation
            withAnimation(pillAnimation) {
                presentedScore = target
            }
        case .settle:
            pillAnimation = Self.settlingDotAnimation
            withAnimation(pillAnimation) {
                presentedScore = target
            }
        case .overshootThenReturn(let overshoot):
            pillAnimation = Self.rushDotAnimation
            withAnimation(pillAnimation) {
                presentedScore = overshoot
            }
            returnTask = Task {
                try? await Task.sleep(for: Self.rushDuration)
                guard !Task.isCancelled else { return }
                pillAnimation = Self.returnDotAnimation
                withAnimation(pillAnimation) {
                    presentedScore = target
                }
            }
        }
        glowTask?.cancel()
        glowTask = Task {
            try? await Task.sleep(for: Self.glowDelay)
            guard !Task.isCancelled else { return }
            heroState?.activeStatus = landedStatus
            // Home only: the launch slide lands softly, a sharp live drop warns.
            guard heroState != nil, score != nil else { return }
            if dropsSharply {
                BodyConfirmationHaptics.play(.warning)
            } else if isLaunchSlide {
                BodyConfirmationHaptics.playScoreReveal()
            }
        }
    }

    /// A fall this large between two live scores buzzes as a warning.
    private static let sharpDropPoints = 10

    /// Lands the pill on `score` with no slide and the glow on immediately.
    private func placePill(at score: Int?) {
        glowTask?.cancel()
        returnTask?.cancel()
        presentedScore = Double(score ?? 0)
        heroState?.activeStatus = score.map { Geometry.segmentOrder[Geometry.segmentIndex(forScore: $0)] }
    }

    private static let glowDelay: Duration = .milliseconds(300)
    private static var hasPlayedLaunchSlide = false

    var body: some View {
        let layout = Geometry.layout(progress: clampedProgress, width: width)
        let barWidth = layout.barWidth

        return ZStack(alignment: .topLeading) {
            BodyReadinessTrackView(
                score: presentedScore,
                hasScore: readiness.score != nil,
                progress: clampedProgress,
                width: width,
                stretch: stretch,
                trailingStretch: trailingStretch,
                reduceMotion: reduceMotion
            )
            .animation(pillAnimation, value: presentedScore)
            .offset(y: -pull)

            // The score and level move as one block: up a line for the level, down a
            // little while no warning badge is showing. Each change glides with the badge
            // fade's timing; the level itself fades in and out.
            ZStack(alignment: .topLeading) {
                scoreText
                    .position(x: width / 2 + scoreCenterNudge, y: scoreCenterY(width: width))

                if let levelText {
                    Text(levelText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
                        .opacity(textOpacity)
                        .position(x: width / 2, y: levelTextCenterY(width: width))
                        .transition(.opacity)
                }
            }
            .frame(width: width, height: Geometry.heroHeight(width: width), alignment: .topLeading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: scoreBlockLayout)
            .offset(y: -pull)

            // Held still with the score during a pull. The host's tap targets read these
            // glyphs' anchors, which carry the offset, so they stay on the glyphs.
            warningBadgeRow
                .position(x: width / 2, y: Geometry.badgeRowCenterY(width: width))
                .offset(y: -pull)
        }
        .frame(width: width, height: Geometry.heroHeight(width: width), alignment: .topLeading)
        .contentShape(BodyReadinessHeroHitShape(
            layout: layout,
            lineWidth: max(barWidth, 44),
            textRect: isTextVisible ? textRect(width: width) : nil
        ))
        // The hero's size follows `width`, and the pill's spring is a `withAnimation`,
        // so a width arriving in that same update would ride the spring and swing the
        // whole ring into place. Only the pill animates here; the ring is laid out.
        .transaction(value: width) { $0.animation = nil }
        .onChange(of: pull) { oldPull, newPull in
            followPull(from: oldPull, to: newPull)
        }
        .onAppear {
            // Flip from 0 up to today's score once per launch, with the glow's delayed
            // fade-in. Coming back to the tab (or any later re-creation of the hero)
            // lands the pill in place with the glow already on, as does Reduce Motion.
            // Only the Home hero counts as the launch slide; the onboarding demo has no
            // shared state and does not use it up.
            displayedScore = readiness.score ?? 0
            if heroState == nil || !Self.hasPlayedLaunchSlide {
                if heroState != nil { Self.hasPlayedLaunchSlide = true }
                movePill(to: readiness.score, isLaunchSlide: true)
            } else {
                placePill(at: readiness.score)
            }
        }
        .onChange(of: readiness.score) { oldScore, newScore in
            displayedScore = newScore ?? 0
            // A first score arriving after launch reveals like the launch slide.
            movePill(to: newScore, from: oldScore, isLaunchSlide: oldScore == nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Drives `stretch` from the pull. While the pull grows the ring follows the finger
    /// with no animation of its own; the first frame it shrinks is the release, and from
    /// there a bouncy spring carries the ring home on its own rather than trailing the
    /// scroll view's rubber band. Reduce Motion leaves the ring unstretched.
    private func followPull(from oldPull: CGFloat, to newPull: CGFloat) {
        guard !reduceMotion else { return }
        if newPull > oldPull {
            isStretchReleasing = false
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                stretch = Geometry.pullStretch(pull: newPull)
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

    /// The score row is centered as a whole, so the percent sign's width pulls the digits
    /// off to the left of the ring. Nudging the row right splits the difference: the
    /// digits read as centered without the sign hanging far off the ring's midline.
    /// Zero without a score, where there is no sign to balance.
    private var scoreCenterNudge: CGFloat {
        readiness.score == nil ? 0 : 6
    }

    private var scoreText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(numberText)
                .font(.system(size: 66, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: displayedScore)

            if readiness.score != nil {
                // Sharing the digits' baseline puts the two on the same bottom edge:
                // neither the digits nor this sign descend below it. A lift here would
                // have to be drawn (`offset`) rather than a baseline offset, which grows
                // the row's bounds upward and would push the digits themselves down out
                // of the middle of the ring this row is centered in.
                Text("%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .opacity(0.9)
            }
        }
        .fixedSize()
        // `.primary` resolves to white in dark mode (the tuned look) but near-black in
        // light mode, so the number stays legible over the light page tones.
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .opacity(textOpacity)
    }

    /// Today's level under the score. Nil without a score, where `--` stays centered, and
    /// when the Readiness Level setting is off.
    private var levelText: String? {
        guard showsLevel else { return nil }
        switch status {
        case .prime:
            return String(localized: "Prime readiness")
        case .high:
            return String(localized: "High readiness")
        case .moderate:
            return String(localized: "Moderate readiness")
        case .low:
            return String(localized: "Low readiness")
        case .poor:
            return String(localized: "Poor readiness")
        case .unavailable:
            return nil
        }
    }

    /// One line of the level text. The score lifts by this much and the level takes the
    /// space it left, so the pair ends where the score alone did and the badge row and
    /// the hero's height stay put. The watch hero does the same in `WatchReadinessHeroView`.
    private static let levelTextHeight: CGFloat = 18

    /// Breathing room between the score's digits and the level. The score lifts by this
    /// much too, so the level and the badge row under it stay where they were.
    private static let levelTextGap: CGFloat = 4

    /// How far the score and level drop while no warning badge is showing, so the block
    /// doesn't float over an empty badge row: 40% of a badge's height.
    private static let noBadgeDrop: CGFloat = Geometry.badgeRowHeight * 0.4

    /// What the score block's position depends on, apart from width (a width change is
    /// laid out, never animated). A change glides the block to its new place.
    private struct ScoreBlockLayout: Equatable {
        let showsLevel: Bool
        let hasBadges: Bool
    }

    private var scoreBlockLayout: ScoreBlockLayout {
        // Badges only move the block while the level shows.
        ScoreBlockLayout(showsLevel: levelText != nil, hasBadges: levelText != nil && !warningBadges.isEmpty)
    }

    /// Without the level the score keeps its centered place whether or not badges show;
    /// only the score-and-level block lifts for the level and drops without badges.
    private func scoreCenterY(width: CGFloat) -> CGFloat {
        guard levelText != nil else { return Geometry.numberCenterY(width: width) }
        return Geometry.numberCenterY(width: width)
            - Self.levelTextHeight
            - Self.levelTextGap
            + (warningBadges.isEmpty ? Self.noBadgeDrop : 0)
    }

    private func levelTextCenterY(width: CGFloat) -> CGFloat {
        scoreCenterY(width: width) + Geometry.numberHalfHeight + Self.levelTextGap + Self.levelTextHeight / 2
    }

    /// The rectangle the score, level and badges occupy, used as a tap target while visible.
    private func textRect(width: CGFloat) -> CGRect {
        let top = scoreCenterY(width: width) - 44
        return CGRect(x: width / 2 - 90, y: top, width: 180, height: Geometry.badgeRowCenterY(width: width) + 22 - top)
    }

    private var warningBadgeRow: some View {
        BodyHeroWarningBadgeRow(badges: warningBadges, opacity: textOpacity)
    }

    private var accessibilityLabel: String {
        guard let score = readiness.score else {
            return String(localized: "Readiness, needs more data")
        }
        return String(localized: "Readiness \(score) percent, \(status.title)")
    }
}

/// The page background while Readiness is starred: the plain grouped background with a
/// soft glow of today's band color centered on the arc's circle, so the color sits in
/// the ring rather than washing the top of the page. `circleCenterY` is where the arc's
/// center lands in this view's own coordinates (the host adds its safe-area and padding
/// offsets) and `glowRadius` how far the color reaches from it, both sized by the host
/// from the hero's width, since the backdrop is full-bleed and the ring is not. `tint`
/// is nil without a score, which leaves the page plain.
struct BodyReadinessGlowBackground: View {
    let tint: Color?
    let circleCenterY: CGFloat
    let glowRadius: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGroupedBackground)

                if let tint {
                    RadialGradient(
                        stops: [
                            .init(color: tint.opacity(0.26), location: 0),
                            .init(color: tint.opacity(0.10), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        center: UnitPoint(x: 0.5, y: geo.size.height > 0 ? circleCenterY / geo.size.height : 0),
                        startRadius: 0,
                        endRadius: glowRadius
                    )
                }
            }
        }
    }
}

/// The five bands and the pill, drawn from one animatable score so the band lights up
/// at the moment the pill actually crosses into it. `animatableData` is the presented
/// score alone: positions and the active band are recomputed from the live scroll
/// geometry on every render, so a score change animates while a scroll frame just moves
/// the track.
private struct BodyReadinessTrackView: View, Animatable {
    var score: Double
    let hasScore: Bool
    let progress: Double
    let width: CGFloat
    /// The pull-down stretch, 0...1, dipping below zero into a squeeze as the release
    /// spring bounces the bands home.
    var stretch: CGFloat
    var trailingStretch: CGFloat
    let reduceMotion: Bool

    var animatableData: AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(score, AnimatablePair(stretch, trailingStretch)) }
        set {
            score = newValue.first
            stretch = newValue.second.first
            trailingStretch = newValue.second.second
        }
    }

    private typealias Geometry = BodyReadinessArcGeometry

    /// The segment the pill currently sits on, from the interpolated score. Nil without
    /// a score, so every band stays neutral.
    private var activeSegmentIndex: Int? {
        guard hasScore else { return nil }
        return Geometry.segmentIndex(forScore: Int(score.rounded(.down)))
    }

    var body: some View {
        let layout = Geometry.layout(progress: progress, width: width, stretch: stretch, trailingStretch: trailingStretch)

        ZStack(alignment: .topLeading) {
            ForEach(layout.segments.indices, id: \.self) { index in
                segment(layout: layout, index: index)
            }

            if hasScore, let activeSegmentIndex {
                dot(layout: layout, tint: BodyReadinessStatusPresentation.color(for: Geometry.segmentOrder[activeSegmentIndex]))
                    .transition(.opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.28)))
            }
        }
        .frame(width: width, height: Geometry.heroHeight(width: width), alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// One band's bar in the flat-glass language the app's chips use: a translucent
    /// fill, a soft top highlight and a one-point rim. Only the band the pill is on
    /// carries its color; the others stay neutral glass and crossfade when it arrives.
    ///
    /// The top highlight fades out as the arc flattens: pinned at the top of the page the
    /// row sits directly above the cards, and the highlight made the bars read lighter
    /// than the card fill right under them.
    private func segment(layout: Geometry.Layout, index: Int) -> some View {
        let shape = BodyReadinessSegmentShape(layout: layout, index: index)
        let isActive = activeSegmentIndex == index
        let color = isActive
            ? BodyReadinessStatusPresentation.color(for: Geometry.segmentOrder[index]).opacity(0.34)
            : Color.primary.opacity(0.10)

        return ZStack {
            shape.fill(color)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: isActive)

            LinearGradient(
                colors: [Color.white.opacity(0.18 * (1 - progress)), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .mask(shape)

            shape
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        }
    }

    /// The pill marking today's score inside its band's segment, rotated to the track.
    private func dot(layout: Geometry.Layout, tint: Color) -> some View {
        let distance = layout.dotDistance(score: score)
        let center = layout.point(atDistance: distance)
        let tangent = layout.tangent(atDistance: distance)
        let angle = Angle.radians(atan2(Double(tangent.dy), Double(tangent.dx)))
        // The pill fattens and thins with the band it rides as the ring wobbles.
        let thickness = max((activeSegmentIndex.map { layout.segmentBarWidths[$0] } ?? layout.barWidth) - 4, 6)

        // Only the tint crossfades when the band flips. The position jumps from one
        // band's cap to the next and must not be tweened, or the pill crosses the gap.
        return ZStack {
            Capsule()
                .fill(tint.opacity(0.85))

            Capsule()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: activeSegmentIndex)
        .frame(width: Geometry.dotLength, height: thickness)
        .rotationEffect(angle)
        .position(center)
    }
}

extension BodyReadinessArcGeometry {
    /// The hero's width inside Home's page padding, for the full-bleed backdrop, which
    /// paints outside the content column but centers its glow on the ring. iOS-only:
    /// the geometry itself is shared with the watch, which has no content column.
    static func heroWidth(pageWidth: CGFloat) -> CGFloat {
        max(0, min(pageWidth, AppLayout.homeContentWidth) - 32)
    }
}
