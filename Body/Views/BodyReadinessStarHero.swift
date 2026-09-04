//
//  BodyReadinessStarHero.swift
//  Body
//

import SwiftUI

/// Layout constants shared by the readiness hero's fixed color backdrop and its
/// scrolling text label so they stay vertically aligned.
enum BodyReadinessHeroMetrics {
    /// Height of the colored band at the top of Home (measured from the screen's
    /// top edge, i.e. behind the status bar) before it melts into the page.
    static let coloredHeight: CGFloat = 360
    /// Minimum height of the text label so the headline sits low in the colored band.
    static let labelMinHeight: CGFloat = 255
    /// Vertical center of the big score number's row (measured from the top of the
    /// colored band, i.e. the screen's top edge behind the status bar), used to center
    /// the fill's highlight band on the number in `BodyReadinessHeroLabel`.
    static let numberRowFromTop: CGFloat = 190
}

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

    var id: String {
        card.rawValue
    }

    /// The badges for the cards currently in the Home grid that are showing a
    /// warning glyph, in the order the grid lays them out. `visibleCards` is the
    /// grid's own order, so a card the user turned off contributes nothing and
    /// there is nowhere for a badge to point that isn't on screen.
    ///
    /// Only three cards can ever set `warningSymbolName`, so the row is capped by
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

/// Fixed, full-bleed color backdrop for the Readiness star hero. Lives in the home
/// page's `.ignoresSafeArea()` background so the readiness color reaches the very top
/// of the screen (behind the status bar) and melts into the page background lower down,
/// mirroring how the metric detail hero eases its tint behind the nav bar. The score
/// text scrolls over this in `BodyReadinessHeroLabel`.
struct BodyReadinessHeroBackdrop: View {
    let readiness: ReadinessSummary

    private var status: ReadinessStatus { readiness.status }
    private var tint: Color { BodyReadinessStatusPresentation.color(for: status) }

    private var fillFraction: Double {
        guard let score = readiness.score else { return 0 }
        return min(max(Double(score) / 100, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            BodyReadinessWaveFill(
                fraction: fillFraction,
                tint: tint
            )
            .frame(height: BodyReadinessHeroMetrics.coloredHeight)

            Color(.systemGroupedBackground)
        }
    }
}

/// The readiness score + status text that scrolls over `BodyReadinessHeroBackdrop`.
/// Transparent — the color comes entirely from the backdrop behind it.
struct BodyReadinessHeroLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let readiness: ReadinessSummary

    /// Today's frozen morning score (undrained, captured ~10 min after wake), so the
    /// starting value stays visible once the live score drains below it.
    let morningScore: Int?

    /// What sits in the explanation slot: the authored `heroExplanation` (feature off,
    /// unsupported, or generation failed), a placeholder while Apple Intelligence writes,
    /// or the generated comment itself.
    var aiComment: BodyReadinessAIComment = .authored
    /// Press-and-hold (3 s) on a generated comment asks Apple Intelligence for a
    /// fresh rewrite. Nil disables the hold; the authored line never offers it.
    var onRegenerateAIComment: (() -> Void)? = nil

    /// Warning signs mirrored from the Home cards, drawn beside the readiness
    /// level. Drawing only: the taps are handled by buttons the host overlays on
    /// these glyphs, outside the hero's own button. Empty everywhere but Home.
    var warningBadges: [BodyReadinessHeroWarningBadge] = []

    /// Animated score for the big number — counts up from 0 on launch and rolls to each
    /// new value, kept roughly in sync with the backdrop fill's rise.
    @State private var displayedScore = 0

    /// True once a generated comment has been shown; until then the explanation slot
    /// updates instantly instead of animating.
    @State private var hasShownGeneratedComment = false

    private var status: ReadinessStatus { readiness.status }

    private var numberText: String {
        readiness.score == nil ? "--" : "\(displayedScore)"
    }

    private var headline: String {
        status == .unavailable ? String(localized: "Readiness") : String(localized: "\(status.title) Readiness")
    }

    /// Shown only when today's live score has dropped below the morning value, so the
    /// user can still read where the day started at a glance.
    private var startedTodayText: String? {
        guard let morning = morningScore,
              let current = readiness.score,
              morning > current else { return nil }
        return String(localized: "Started today with \(morning)%")
    }

    private var statusTextAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    private var statusTextTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.28))
    }

    /// Crossfades changes of the explanation slot, but only once the first generated
    /// comment has landed: the cold-launch population (authored → generating → comment,
    /// or authored → cached comment) appears in place with no animation, so the hero's
    /// growth from one line to several doesn't slide the text upward. Every later change
    /// (a press-and-hold regenerate, a workout drain rewriting the comment) crossfades.
    /// Skipped under Reduce Motion like the score roll.
    private var aiCommentAnimation: Animation? {
        guard hasShownGeneratedComment, !reduceMotion else { return nil }
        return .easeInOut(duration: 0.28)
    }

    /// Matches `aiCommentAnimation`: no fade on the first comment, the usual crossfade after.
    private var aiCommentTransition: AnyTransition {
        hasShownGeneratedComment ? statusTextTransition : .identity
    }

    /// The text of the explanation slot, whichever state it's in. Drives the crossfade
    /// identity: any change of wording is a change of view.
    private var explanationString: String {
        switch aiComment {
        case .authored:
            return readiness.heroExplanation
        case .generating:
            return String(localized: "Generating comment…")
        case .comment(let text):
            return text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 95)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(numberText)
                    .font(.system(size: 66, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.4, extraBounce: 0), value: displayedScore)

                if readiness.score != nil {
                    Text("%")
                        .font(.system(size: 30, weight: .heavy))
                        .opacity(0.9)
                }
            }

            Spacer().frame(height: 35)

            ZStack(alignment: .leading) {
                statusText
                    .id(status)
                    .transition(statusTextTransition)
            }
            .animation(statusTextAnimation, value: status)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 6)
        }
        // `.primary` resolves to white in dark mode (the tuned look) but near-black in
        // light mode, so the headline/explanation stay legible where they extend past the
        // colored fill onto the light page background instead of vanishing white-on-light.
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: BodyReadinessHeroMetrics.labelMinHeight, alignment: .leading)
        // Whole area (including the transparent gaps) taps through to the detail page.
        .contentShape(Rectangle())
        .onAppear {
            // Flip from 0 up to today's score on launch. The roll lives on the number
            // itself (same .smooth / .numericText as the metric cards), nothing else.
            displayedScore = readiness.score ?? 0
        }
        .onChange(of: readiness.score) { _, newScore in
            displayedScore = newScore ?? 0
        }
        .onChange(of: aiComment) { _, newValue in
            // Flipped here, not in onAppear: the change delivering the first comment is
            // evaluated while the animation is still nil, so it lands in place and only
            // later changes crossfade.
            if case .comment = newValue, !hasShownGeneratedComment {
                hasShownGeneratedComment = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 6) {
            // The row is pinned to the full width rather than hugging its
            // content: the explanation slot below swaps between a one-liner and
            // a paragraph, and the VStack sizing to its widest child would slide
            // the badges in and out with it.
            HStack(alignment: .center, spacing: 8) {
                Text(headline)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Takes the leftover width itself instead of leaving it to a
                    // Spacer: given only its ideal width to report, the headline
                    // truncated rather than scaling when the badges crowded it.
                    .frame(maxWidth: .infinity, alignment: .leading)

                warningBadgeRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topLeading) {
                explanationText
                    .id(explanationString)
                    .transition(aiCommentTransition)
            }
            .animation(aiCommentAnimation, value: explanationString)
            .contentShape(Rectangle())
            .gesture(BodyReadinessCommentRegenerateGesture(
                isEnabled: onRegenerateAIComment != nil && aiComment != .authored && aiComment != .generating,
                onRecognized: { onRegenerateAIComment?() }
            ))

            if let startedTodayText {
                Text(startedTodayText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The warning signs beside the readiness level, each the same glyph and tint
    /// its own Home card is showing. Publishes its glyphs' bounds so the host can
    /// lay tap targets over them; nothing here is interactive.
    private var warningBadgeRow: some View {
        HStack(spacing: 0) {
            ForEach(warningBadges) { badge in
                Image(systemName: badge.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(badge.color)
                    // A fixed box rather than the glyph's own size, so three badges
                    // cost a predictable width and the tap targets laid over them
                    // are all the same. Kept tight: at 34 a three-badge row pushed
                    // "Moderate Readiness" past its scale floor and truncated it on
                    // a narrow screen. The host gives the targets their height back.
                    .frame(width: 28, height: 28)
                    .anchorPreference(key: BodyReadinessHeroBadgeAnchorKey.self, value: .bounds) {
                        [badge.id: $0]
                    }
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        // The same fade the card badges use, so a warning arriving mid-refresh
        // reads as one change in both places.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: warningBadges)
    }

    /// The explanation slot: the Apple Intelligence glyph leads both the placeholder and
    /// the generated comment; the authored one-liner has no glyph. Same type, size and
    /// color in every state.
    @ViewBuilder
    private var explanationText: some View {
        switch aiComment {
        case .authored:
            Text(explanationString)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .generating:
            // The placeholder is one short line, so the glyph can sit in its own view
            // here and spin while the model writes.
            HStack(spacing: 5) {
                BodyAppleIntelligenceSpinningGlyph()
                Text(explanationString)
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(BodyAppleIntelligenceShimmer(looping: true))
        case .comment:
            // The glyph is interpolated into the text run rather than laid out in an
            // HStack, so wrapped lines flow full-width instead of indenting past it.
            (Text(Image(systemName: BodyAppleIntelligenceGlyph.symbolName))
                .font(.system(size: 13, weight: .semibold))
                + Text(verbatim: " ")
                + Text(explanationString))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(BodyAppleIntelligenceShimmer(looping: false))
        }
    }

    private var accessibilityLabel: String {
        guard let score = readiness.score else {
            return String(localized: "Readiness, needs more data")
        }
        var label = String(localized: "Readiness \(score) percent, \(status.title)")
        if let morning = morningScore, morning > score {
            label += String(localized: ", started today at \(morning) percent")
        }
        // The label suppresses child elements, so the generated comment is only spoken
        // if it's folded in here.
        if case .comment(let text) = aiComment {
            label += ". " + String(localized: "Apple Intelligence comment: \(text)")
        }
        return label
    }
}

/// A 3-second hold on the generated comment. UIKit rather than SwiftUI so it
/// coexists with the hero's tap-to-open button and the surrounding scroll: a tap
/// still opens the detail, a scroll still scrolls, and only a stationary hold
/// regenerates (see the Activity Rings peek gesture for the same reasoning).
private struct BodyReadinessCommentRegenerateGesture: UIGestureRecognizerRepresentable {
    static let minimumPressDuration: TimeInterval = 3

    let isEnabled: Bool
    let onRecognized: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = Self.minimumPressDuration
        recognizer.allowableMovement = 12
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        guard recognizer.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onRecognized()
    }
}

/// The Apple Intelligence glyph turning continuously while a comment generates.
/// Static under Reduce Motion.
private struct BodyAppleIntelligenceSpinningGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isSpinning = false

    var body: some View {
        Image(systemName: BodyAppleIntelligenceGlyph.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    isSpinning = true
                }
            }
    }
}

/// The Apple Intelligence multicolor wave: a blue → purple → pink → orange band, with a
/// soft blurred glow under it, sweeping left to right across the text it modifies.
/// `looping` (the placeholder) repeats the sweep until the view goes away; otherwise
/// (a freshly generated comment) it sweeps once and settles to the plain text. The
/// modifier is re-created whenever the slot's text identity changes, so every new
/// comment earns its own sweep. Skipped entirely under Reduce Motion.
private struct BodyAppleIntelligenceShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let looping: Bool

    /// 0 = band fully off the leading edge, 1 = fully off the trailing edge.
    @State private var phase: CGFloat = 0
    @State private var isVisible = true

    private static let colors: [Color] = [
        .clear,
        Color(red: 0.36, green: 0.62, blue: 1.0),
        Color(red: 0.68, green: 0.42, blue: 1.0),
        Color(red: 1.0, green: 0.42, blue: 0.72),
        Color(red: 1.0, green: 0.62, blue: 0.30),
        .clear
    ]

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible && !reduceMotion {
                    ZStack {
                        band.blur(radius: 6).opacity(0.8)
                        band
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear(perform: start)
    }

    private var band: some View {
        LinearGradient(
            colors: Self.colors,
            startPoint: UnitPoint(x: phase * 2 - 1, y: 0.5),
            endPoint: UnitPoint(x: phase * 2, y: 0.5)
        )
    }

    private func start() {
        guard !reduceMotion else { return }
        if looping {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                phase = 1
            }
        } else {
            withAnimation(.easeInOut(duration: 1.4)) {
                phase = 1
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                isVisible = false
            }
        }
    }
}

/// State of the hero's explanation slot when the Apple Intelligence readiness comment
/// is involved.
enum BodyReadinessAIComment: Equatable {
    /// Body's own authored explanation (feature off, unsupported, or generation failed).
    case authored
    /// Apple Intelligence is writing; a placeholder shows so the authored line never
    /// flashes up only to be replaced a moment later.
    case generating
    case comment(String)
}

/// The animated fill: solid `tint` from the left edge out to `fraction` of the width,
/// with a soft horizontal highlight band centered on the score number's row, the fill
/// front cut crisply and the lower portion melting into the page background. The level
/// animates via frame width so it rises from empty and slosh-springs to each new value.
private struct BodyReadinessWaveFill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fraction: Double
    let tint: Color

    @State private var hasAppeared = false

    private var clamped: Double { min(max(fraction, 0), 1) }

    /// Soft horizontal highlight across the fill, centered on the score number's row and
    /// kept fairly tight so the number sits precisely on its bright center line.
    private var highlightBand: LinearGradient {
        let center = BodyReadinessHeroMetrics.numberRowFromTop / BodyReadinessHeroMetrics.coloredHeight
        let halfSpread: CGFloat = 0.30
        return LinearGradient(
            stops: [
                .init(color: .clear, location: center - halfSpread),
                .init(color: .white.opacity(0.26), location: center),
                .init(color: .clear, location: center + halfSpread)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let target: CGFloat = (hasAppeared || reduceMotion) ? CGFloat(clamped) : 0

            ZStack(alignment: .leading) {
                // "Unfilled" track = a much darker shade of the readiness color (the
                // tint laid over the page background) so the area past the score reads as
                // a deep version of today's color rather than a hard black block, while
                // still staying far dimmer than the filled side to keep the cut crisp.
                Color(.systemGroupedBackground)
                tint.opacity(0.28)

                // Filled color region: solid tint with a soft horizontal highlight band
                // centered on the score number's row, cut sharply at the fill front.
                ZStack {
                    Rectangle().fill(tint)

                    highlightBand
                        .blendMode(.screen)
                }
                .frame(width: target * width)
                .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 55, damping: 8.25), value: target)

                // Concentrate the color up top and melt the lower portion into the page
                // background — mirroring how the metric detail hero eases its tint into
                // the page — so the headline reads in white and the panel blends into
                // the cards below.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: Color(.systemGroupedBackground).opacity(0.85), location: 0.78),
                        .init(color: Color(.systemGroupedBackground), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: height)
        }
        .onAppear { hasAppeared = true }
    }
}
