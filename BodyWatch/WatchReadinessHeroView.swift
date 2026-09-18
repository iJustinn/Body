//
//  WatchReadinessHeroView.swift
//  BodyWatch
//
//  The iOS Summary readiness hero on the watch home screen: five glass bar
//  segments on an arc over the big score, a pill in today's band, the page
//  glow in the band's color, the pull-down stretch, and the scroll-driven
//  flattening into a bar held at the top of the page. It is the iPhone hero
//  (`BodyReadinessArcHero` in `Body/Views/BodyReadinessStarHero.swift`) drawn
//  from the same shared `BodyReadinessArcGeometry`, laid out close to the width
//  the hero has on an iPhone (`referenceWidth`, a little narrower so the bars
//  read slightly thicker) and then scaled down uniformly to the watch, so the
//  distances and animations are the phone's. The state
//  machine below (launch slide, pill moves, glow delay, stretch release) is a
//  line-for-line mirror of the iOS hero's: keep the two in step.
//
//  What the watch leaves out: the warning badges (they point at Home cards the
//  watch doesn't have) and the comment under the hero (it needs the readiness
//  summary the watch snapshot doesn't carry).
//
//  Watch-only: not compiled into the iOS `Body` target.
//

import SwiftUI

/// The band the pill is resting on, for the page glow. Nil while the pill is in
/// flight and without a score. Mirrors `BodyReadinessHeroState`.
@Observable
final class WatchReadinessHeroState {
    var activeStatus: ReadinessStatus?
}

/// The dashboard's scroll offset and pull-down distance, published once per
/// scroll frame so only the hero pin and the glow dim re-render.
@Observable
final class WatchDashboardScrollState {
    var offset: CGFloat = 0
    var pull: CGFloat = 0
}

enum WatchReadinessHero {
    /// The width the geometry is laid out at before it is scaled to the watch.
    /// The iPhone hero is 361 pt wide (a 393 pt page inside Home's 16 pt
    /// padding); the geometry's bar, gap, and pill sizes are absolute, so a
    /// slightly narrower layout makes them about 9 percent heavier against the
    /// arc once scaled, which reads better at the watch's size.
    static let referenceWidth: CGFloat = 330

    static func scale(width: CGFloat) -> CGFloat {
        max(0, width / referenceWidth)
    }

    /// The hero's height on the watch at `width`.
    static func height(width: CGFloat) -> CGFloat {
        BodyReadinessArcGeometry.heroHeight(width: referenceWidth) * scale(width: width)
    }

    /// Scroll points that take the hero from the arc to the flat bar.
    static func morphDistance(width: CGFloat) -> CGFloat {
        BodyReadinessArcGeometry.morphDistance(width: referenceWidth) * scale(width: width)
    }

    /// Where the arc's circle center sits under the hero's top, on the watch.
    static func arcCenterY(width: CGFloat) -> CGFloat {
        BodyReadinessArcGeometry.arcCenterY(width: referenceWidth) * scale(width: width)
    }

    static func glowRadius(width: CGFloat) -> CGFloat {
        BodyReadinessArcGeometry.glowRadius(width: referenceWidth) * scale(width: width)
    }

    static func color(for status: ReadinessStatus) -> Color {
        guard let rgb = status.watchTintComponents else { return Color.secondary }
        return Color(rgb)
    }
}

struct WatchReadinessHeroView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WatchReadinessHeroState.self) private var heroState: WatchReadinessHeroState?

    /// Today's readiness score; nil shows `--` over neutral bands.
    let score: Int?
    /// The phone's Readiness Level switch: name today's level under the score.
    var showsLevel: Bool = true
    /// The width the hero draws at on the watch.
    let width: CGFloat
    /// 0 = full arc with the score, 1 = the flat pinned bar. Clamped here.
    let progress: Double
    /// Points the page has been pulled down past rest, in watch points.
    var pull: CGFloat = 0

    @State private var displayedScore = 0
    @State private var presentedScore: Double = 0
    @State private var pillAnimation: Animation?
    @State private var stretch: CGFloat = 0
    @State private var isStretchReleasing = false
    @State private var glowTask: Task<Void, Never>?
    @State private var returnTask: Task<Void, Never>?

    private typealias Geometry = BodyReadinessArcGeometry
    private var referenceWidth: CGFloat { WatchReadinessHero.referenceWidth }
    private var scale: CGFloat { WatchReadinessHero.scale(width: width) }

    private var status: ReadinessStatus { ReadinessStatus.status(for: score) }
    private var clampedProgress: Double { min(max(progress, 0), 1) }

    private var numberText: String {
        score == nil ? "--" : "\(displayedScore)"
    }

    private var textOpacity: Double {
        Geometry.textOpacity(progress: clampedProgress, width: referenceWidth)
    }

    private static let bouncingDotAnimation = Animation.interpolatingSpring(
        mass: Geometry.pillSpringMass,
        stiffness: Geometry.pillSpringStiffness,
        damping: Geometry.pillSpringDamping
    )
    private static let settlingDotAnimation = Animation.easeOut(duration: 0.7)
    private static let rushDotAnimation = Animation.easeIn(duration: 0.32)
    private static let returnDotAnimation = Animation.easeInOut(duration: 0.6)
    private static let rushDuration: Duration = .milliseconds(320)
    private static let glowDelay: Duration = .milliseconds(300)
    private static var hasPlayedLaunchSlide = false

    /// Slides the pill to `score`, switching the glow off as it sets off and back
    /// on the landed band `glowDelay` later. Same moves as the iOS hero.
    private func movePill(to score: Int?) {
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
        }
    }

    private func placePill(at score: Int?) {
        glowTask?.cancel()
        returnTask?.cancel()
        presentedScore = Double(score ?? 0)
        heroState?.activeStatus = score.map { Geometry.segmentOrder[Geometry.segmentIndex(forScore: $0)] }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Laid out at the phone's width and scaled from its top-left corner, so
            // the paths are the phone's paths and the outer frame below stays the
            // watch's size.
            WatchReadinessTrackView(
                score: presentedScore,
                hasScore: score != nil,
                progress: clampedProgress,
                width: referenceWidth,
                stretch: stretch,
                reduceMotion: reduceMotion
            )
            .animation(pillAnimation, value: presentedScore)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: WatchReadinessHero.height(width: width), alignment: .topLeading)
            .offset(y: -pull)

            scoreText
                .position(x: width / 2, y: (Geometry.numberCenterY(width: referenceWidth) - levelLineOffset) * scale)
                .offset(y: -pull)
        }
        .frame(width: width, height: WatchReadinessHero.height(width: width), alignment: .topLeading)
        // The same morph-aware tap target as the iPhone hero: the bands widened to a
        // finger plus the score while it is visible, scaled to the watch. A plain
        // rectangle kept the flattened hero's full height above the cards (the pin
        // raises its z-index), so a tap on the card under the bar opened Readiness.
        .contentShape(WatchReadinessHeroHitShape(
            layout: Geometry.layout(progress: clampedProgress, width: referenceWidth),
            lineWidth: max(Geometry.barWidth(progress: clampedProgress), 44),
            textRect: Geometry.isTextVisible(progress: clampedProgress, width: referenceWidth) ? textRect : nil,
            scale: scale
        ))
        .transaction(value: width) { $0.animation = nil }
        .onChange(of: pull) { oldPull, newPull in
            followPull(from: oldPull, to: newPull)
        }
        .onAppear {
            // Flip from 0 up to today's score once per launch; a later re-creation
            // of the hero lands the pill in place with the glow already on.
            displayedScore = score ?? 0
            if !Self.hasPlayedLaunchSlide {
                Self.hasPlayedLaunchSlide = true
                movePill(to: score)
            } else {
                placePill(at: score)
            }
        }
        .onChange(of: score) { _, newScore in
            displayedScore = newScore ?? 0
            movePill(to: newScore)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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
            }
        } else if !isStretchReleasing {
            isStretchReleasing = true
            withAnimation(.interpolatingSpring(mass: 1, stiffness: 180, damping: 12)) {
                stretch = 0
            }
        }
        if newPull <= 0 {
            isStretchReleasing = false
        }
    }

    /// The rectangle the score occupies, in phone points (scaled by the hit shape).
    private var textRect: CGRect {
        let centerY = Geometry.numberCenterY(width: referenceWidth)
        return CGRect(x: referenceWidth / 2 - 90, y: centerY - 44, width: 180, height: 88)
    }

    private var scoreCenterNudge: CGFloat {
        score == nil ? 0 : 6 * scale
    }

    /// Height of the level line under the score, in phone points.
    private static let levelLineHeight: CGFloat = 26
    /// Pulls the level up into the number's own line spacing, so the pair reads
    /// as one block. Phone points; negative tightens.
    private static let levelLineSpacing: CGFloat = -6

    /// The score and its level line are centered together, so raising that
    /// center by half of what the line adds lifts the number by the whole
    /// line's height whatever the spacing between the two.
    private var levelLineOffset: CGFloat {
        showsLevelLine ? (Self.levelLineHeight - Self.levelLineSpacing) / 2 : 0
    }

    private var showsLevelLine: Bool { showsLevel && score != nil }

    private var scoreText: some View {
        VStack(spacing: Self.levelLineSpacing * scale) {
            scoreNumber
                .offset(x: scoreCenterNudge)

            if showsLevelLine {
                Text(status.title)
                    .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: Self.levelLineHeight * scale)
            }
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.3), radius: 6 * scale, y: 1 * scale)
        .opacity(textOpacity)
    }

    private var scoreNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2 * scale) {
            Text(numberText)
                .font(.system(size: 66 * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: displayedScore)

            if score != nil {
                Text(verbatim: "%")
                    .font(.system(size: 30 * scale, weight: .semibold, design: .rounded))
                    .opacity(0.9)
            }
        }
        .fixedSize()
        .foregroundStyle(.primary)
    }

    private var accessibilityLabel: String {
        guard let score else {
            return String(localized: "Readiness, needs more data")
        }
        return String(localized: "Readiness \(score) percent, \(status.title)")
    }
}

/// `BodyReadinessHeroHitShape` laid out at the phone width and scaled down to the
/// watch hero's frame, so the tap target follows the bars through the morph.
private struct WatchReadinessHeroHitShape: Shape {
    let layout: BodyReadinessArcGeometry.Layout
    let lineWidth: CGFloat
    let textRect: CGRect?
    let scale: CGFloat

    func path(in rect: CGRect) -> Path {
        BodyReadinessHeroHitShape(layout: layout, lineWidth: lineWidth, textRect: textRect)
            .path(in: rect)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

/// The five bands and the pill: `BodyReadinessTrackView` from the iOS hero, with
/// the band colors read from the shared watch tint table.
private struct WatchReadinessTrackView: View, Animatable {
    var score: Double
    let hasScore: Bool
    let progress: Double
    let width: CGFloat
    var stretch: CGFloat
    let reduceMotion: Bool

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(score, stretch) }
        set {
            score = newValue.first
            stretch = newValue.second
        }
    }

    private typealias Geometry = BodyReadinessArcGeometry

    private var activeSegmentIndex: Int? {
        guard hasScore else { return nil }
        return Geometry.segmentIndex(forScore: Int(score.rounded(.down)))
    }

    var body: some View {
        let layout = Geometry.layout(progress: progress, width: width, stretch: stretch)

        ZStack(alignment: .topLeading) {
            ForEach(layout.segments.indices, id: \.self) { index in
                segment(layout: layout, index: index)
            }

            if hasScore, let activeSegmentIndex {
                dot(layout: layout, tint: WatchReadinessHero.color(for: Geometry.segmentOrder[activeSegmentIndex]))
                    .transition(.opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.28)))
            }
        }
        .frame(width: width, height: Geometry.heroHeight(width: width), alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func segment(layout: Geometry.Layout, index: Int) -> some View {
        let shape = BodyReadinessSegmentShape(layout: layout, index: index)
        let isActive = activeSegmentIndex == index
        let color = isActive
            ? WatchReadinessHero.color(for: Geometry.segmentOrder[index]).opacity(0.34)
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

    private func dot(layout: Geometry.Layout, tint: Color) -> some View {
        let distance = layout.dotDistance(score: score)
        let center = layout.point(atDistance: distance)
        let tangent = layout.tangent(atDistance: distance)
        let angle = Angle.radians(atan2(Double(tangent.dy), Double(tangent.dx)))
        let thickness = max(layout.barWidth - 4, 6)

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

/// Pins the hero and drives its flattening, as `BodyReadinessHeroScrollPin` does
/// on iOS: once the page has scrolled past the hero's resting position it is held
/// at the top by a counter-offset while `progress` ramps over the morph distance,
/// then released to scroll away with the cards. The watch has nothing between the
/// hero and the first card, so the hold ends exactly as the morph completes, with
/// the first card sitting the grid spacing under the flat bar.
struct WatchReadinessHeroScrollPin<Content: View>: View {
    let scrollState: WatchDashboardScrollState
    let width: CGFloat
    /// The hero's resting top in the viewport at offset 0, reported so the page
    /// glow can center on the ring.
    @Binding var heroRestingTop: CGFloat
    @ViewBuilder var content: (Double, CGFloat) -> Content

    @State private var heroContentY: CGFloat = 0

    private var travel: CGFloat {
        scrollState.offset - heroContentY
    }

    private var progress: Double {
        guard width > 0 else { return 0 }
        let raw = min(1, max(0, Double(travel) / Double(WatchReadinessHero.morphDistance(width: width))))
        return (raw * 120).rounded() / 120
    }

    private var pinOffset: CGFloat {
        min(max(0, travel), WatchReadinessHero.morphDistance(width: width))
    }

    private struct Tops: Equatable {
        var viewport: CGFloat
        var global: CGFloat
    }

    var body: some View {
        content(progress, scrollState.pull)
            .onGeometryChange(for: Tops.self) { proxy in
                Tops(
                    viewport: proxy.frame(in: .named(WatchDashboardView.viewportCoordinateSpace)).minY,
                    global: proxy.frame(in: .global).minY
                )
            } action: { drawn in
                // `minY` is where the hero is drawn (after the pin offset), so undoing
                // the pin and adding the scroll offset gives its resting position.
                // Ignore sub-point jitter so the pin doesn't churn every frame.
                let measured = drawn.viewport + scrollState.offset - pinOffset
                if abs(measured - heroContentY) > 0.5 {
                    heroContentY = measured
                }
                let resting = drawn.global + scrollState.offset - pinOffset
                if abs(resting - heroRestingTop) > 0.5 {
                    heroRestingTop = resting
                }
            }
            .offset(y: pinOffset)
            .zIndex(pinOffset > 0 ? 1 : 0)
    }
}

/// The page behind the dashboard while the hero is showing: black with a soft glow
/// of today's band color centered in the ring (`BodyReadinessGlowBackground`),
/// crossfading when the band changes and dimming toward black as the page scrolls
/// (`BodyHomeBackgroundScrollDim`), so the cards scrolling over it stay readable.
struct WatchReadinessPageBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let heroState: WatchReadinessHeroState
    let scrollState: WatchDashboardScrollState
    /// The arc's circle center, in this view's coordinates.
    let circleCenterY: CGFloat
    let glowRadius: CGFloat

    private var dimOpacity: Double {
        min(1, max(0, Double(scrollState.offset) / 70)) * 0.9
    }

    var body: some View {
        let status = heroState.activeStatus
        ZStack {
            Color.black

            GeometryReader { geo in
                if let status {
                    let tint = WatchReadinessHero.color(for: status)
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
                    .id(status)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: status)

            Color.black
                .opacity(dimOpacity)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Readiness hero") {
    let heroState = WatchReadinessHeroState()
    let scrollState = WatchDashboardScrollState()
    let width: CGFloat = 176
    return ZStack {
        WatchReadinessPageBackground(
            heroState: heroState,
            scrollState: scrollState,
            circleCenterY: 40 + WatchReadinessHero.arcCenterY(width: width),
            glowRadius: WatchReadinessHero.glowRadius(width: width)
        )
        .ignoresSafeArea()

        VStack(spacing: 8) {
            WatchReadinessHeroView(score: 78, width: width, progress: 0)
            WatchMetricCardView(metric: WatchMetricsSnapshot.placeholder.orderedMetrics[1])
        }
        .padding(.horizontal, 4)
    }
    .environment(heroState)
}
