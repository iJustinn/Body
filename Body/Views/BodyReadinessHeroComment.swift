//
//  BodyReadinessHeroComment.swift
//  Body
//

import SwiftUI

/// State of the hero comment's explanation slot when the Apple Intelligence readiness
/// comment is involved.
enum BodyReadinessAIComment: Equatable {
    /// Body's own authored explanation (feature off, unsupported, or generation failed).
    case authored
    /// Apple Intelligence is writing; a placeholder shows so the authored line never
    /// flashes up only to be replaced a moment later.
    case generating
    case comment(String)
}

/// The explanation slot and the morning-score line, as plain text on the page directly
/// under the arc hero (no card, like the original hero). The score and level title live
/// in `BodyReadinessArcHero`; this never repeats them, so VoiceOver hears each fact once.
struct BodyReadinessHeroComment: View {
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

    /// True once a generated comment has been shown; until then the explanation slot
    /// updates instantly instead of animating.
    @State private var hasShownGeneratedComment = false

    /// Shown only when today's live score has dropped below the morning value, so the
    /// user can still read where the day started at a glance.
    private var startedTodayText: String? {
        guard let morning = morningScore,
              let current = readiness.score,
              morning > current else { return nil }
        return String(localized: "Started today with \(morning)%")
    }

    private var statusTextTransition: AnyTransition {
        .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.28))
    }

    /// Crossfades changes of the explanation slot, but only once the first generated
    /// comment has landed: the cold-launch population (authored → generating → comment,
    /// or authored → cached comment) appears in place with no animation, so the card's
    /// growth from one line to several doesn't slide the text upward. Every later change
    /// (a press-and-hold regenerate, a workout drain rewriting the comment) crossfades.
    /// Skipped under Reduce Motion.
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
        VStack(alignment: .leading, spacing: 6) {
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
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 1)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Whole area (including the gaps) taps through to the detail page.
        .contentShape(Rectangle())
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

    /// Built from the strings on screen, each once: whatever the explanation slot shows
    /// (authored line, placeholder, or the generated comment), then the morning line
    /// when it is visible.
    private var accessibilityLabel: String {
        var parts: [String] = []
        if case .comment(let text) = aiComment {
            parts.append(String(localized: "Apple Intelligence comment: \(text)"))
        } else {
            parts.append(explanationString)
        }
        if let startedTodayText {
            parts.append(startedTodayText)
        }
        return parts.joined(separator: ". ")
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
