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

    /// Animated score for the big number — counts up from 0 on launch and rolls to each
    /// new value, kept roughly in sync with the backdrop fill's rise.
    @State private var displayedScore = 0

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

    /// Crossfades every change of the explanation slot — authored → placeholder →
    /// generated, or a regenerated comment replacing the last — skipped under Reduce
    /// Motion like the score roll.
    private var aiCommentAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ZStack(alignment: .topLeading) {
                explanationText
                    .id(explanationString)
                    .transition(statusTextTransition)
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
