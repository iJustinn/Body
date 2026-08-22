//
//  BodyIntroAnimationView.swift
//  Body
//

import SwiftUI

/// The word field behind the first run intro: a dense field of perfectly
/// horizontal wordmarks that stream in from past the left edge, cross the
/// screen at a constant speed, and carry straight on out through the right
/// edge without ever stopping. The intro runs the field twice, once for each
/// `Wave`, so the launch reads "oooh" and then "my". Everything is computed
/// from a seed and the screen size so the field is identical on every launch,
/// unit testable, and renderable frame by frame.
struct BodyIntroWordLayout: Equatable {
    /// The two passes of the intro. Each one builds its own field from its own
    /// seed, so the second wave never lands on the first wave's geometry.
    enum Wave: CaseIterable {
        /// "oooh": "o" repeated 2...12 times, then a closing "h".
        case oh
        /// "my": an "m" then "y" repeated 1...4 times.
        case my

        /// The seeds spell the wave; any other seed gives a different field.
        var defaultSeed: UInt64 {
            switch self {
            case .oh: return 0x6F68
            case .my: return 0x6D79
            }
        }
    }

    struct Word: Equatable, Identifiable {
        let id: Int
        /// The wave's wordmark: "oooh" with a variable run of "o", or "my"
        /// with a variable run of "y".
        let text: String
        let fontSize: CGFloat
        /// Stagger inside `BodyIntroTimeline.staggerSpan`, so the words stream
        /// past as a shoal rather than one wall.
        let delay: Double
        /// Off screen start, far enough past the left edge that the whole word
        /// is hidden.
        let origin: CGPoint
        /// Where the word sits when it is centred on screen, which it passes
        /// halfway through its slide. Never a resting place.
        let target: CGPoint
        /// Off screen finish, the mirror of `origin` past the right edge.
        let exit: CGPoint
        let opacity: Double
    }

    let words: [Word]

    /// Every cell of the grid carries a word: the field has to read as a solid
    /// wall of type, not as a scatter with holes in it.
    static let wordCount = columns * rows

    private static let columns = 5
    private static let rows = 12
    /// Font sizes are authored for a 402pt wide phone and scale with the
    /// smaller edge, so an iPad or a landscape screen gets the same field
    /// proportionally rather than 60 tiny words in a corner. At the reference
    /// width a row is about 73pt tall, so neighbouring words overlap heavily.
    private static let referenceEdge: CGFloat = 402
    private static let minimumFontSize: CGFloat = 44
    /// Matches the shadow radius the view draws, so the off screen margin
    /// covers the halo too.
    static let haloRadius: CGFloat = 8
    private static let maximumFontSize: CGFloat = 100

    static func make(in size: CGSize, wave: Wave, seed: UInt64? = nil) -> BodyIntroWordLayout {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        var random = BodyIntroRandom(seed: seed ?? wave.defaultSeed)

        let cellHeight = height / CGFloat(rows)
        let scale = min(width, height) / referenceEdge
        let farthestRow = Double(rows - 1) / 2

        let words = (0..<wordCount).map { cell -> Word in
            let row = cell / columns

            // The biggest type lands on the middle rows and the rim keeps the
            // smaller sizes, so the field has a weighted center.
            let centerness = 1 - abs(Double(row) - farthestRow) / farthestRow
            let rawSize = 44 + 44 * centerness + random.double(in: 0...12)
            let fontSize = min(max(rawSize, minimumFontSize), maximumFontSize) * scale
            let text: String
            switch wave {
            case .oh:
                text = String(repeating: "o", count: 2 + random.int(in: 0...10)) + "h"
            case .my:
                text = "m" + String(repeating: "y", count: 1 + random.int(in: 0...3))
            }

            // Every word rides one horizontal line: same y at the origin, the
            // centre, and the exit, so nothing tilts, drifts, or settles. The
            // travel is the width plus the word itself, split evenly either
            // side of centre, so the word is fully hidden at both ends and
            // passes the centre exactly halfway through its slide. The rounded
            // black face runs wider than a typical em, and the halo shadow
            // adds a few points more, so the estimate is generous: a sliver
            // peeking in before the slide or lingering after it reads as a
            // glitch.
            let lineY = (CGFloat(row) + 0.5) * cellHeight
                + CGFloat(random.double(in: -0.25...0.25)) * cellHeight
            let centerX = width / 2
            let estimatedWidth = fontSize * 0.8 * CGFloat(text.count) + 2 * haloRadius
            let halfTravel = centerX + estimatedWidth / 2 + fontSize * 0.5

            return Word(
                id: cell,
                text: text,
                fontSize: fontSize,
                delay: random.double(in: 0...BodyIntroTimeline.staggerSpan),
                origin: CGPoint(x: centerX - halfTravel, y: lineY),
                target: CGPoint(x: centerX, y: lineY),
                exit: CGPoint(x: centerX + halfTravel, y: lineY),
                opacity: random.double(in: 0.55...1)
            )
        }

        return BodyIntroWordLayout(words: words)
    }
}

/// Seeded xorshift64, not `SystemRandomNumberGenerator`: the field has to be the
/// same on every launch and inside the tests.
private struct BodyIntroRandom {
    private var state: UInt64

    init(seed: UInt64) {
        // xorshift is stuck at zero, so a zero seed borrows the golden ratio.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// 0..<1 from the top 53 bits (the ones with the longest period).
    mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unitDouble() * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Int(next() % UInt64(span))
    }
}

/// Every timing constant of the intro, and the pure (word, wave, time) to
/// geometry map the view draws. Keeping the motion in a function of elapsed
/// seconds means skipping is a clock jump, and a test can assert any instant.
///
/// The two waves overlap: the second is streaming in while the first is still
/// crossing the screen, so the computed schedule is: the "oooh" wave runs from
/// 0.35 s to 3.55 s, the "my" wave from 1.75 s to 4.95 s, the pages behind
/// begin to fade up at 4.25 s, and the overlay can unmount at 4.95 s.
enum BodyIntroTimeline {
    /// Words wait off screen while the cover's own transition settles.
    static let startDelay: TimeInterval = 0.35
    /// The window the per-word delays are spread over.
    static let staggerSpan: TimeInterval = 1.2
    /// How long one word takes to travel from its origin to its exit, linear:
    /// it never speeds up, slows down, or stops.
    static let slideDuration: TimeInterval = 2.0
    /// The second wave starts streaming in this long after the first, so the
    /// two fields overlap and the background never shows through.
    static let waveLead: TimeInterval = 1.4
    /// The pages behind fade up this long before the last word leaves, so the
    /// reveal lands under the tail of the second wave.
    static let revealLead: TimeInterval = 0.7
    /// How long the pages behind the field take to fade up, from `revealStart`.
    static let revealDuration: TimeInterval = 0.5

    /// When a wave's first words enter: 0.35 s for `.oh`, 1.75 s for `.my`.
    static func start(of wave: BodyIntroWordLayout.Wave) -> TimeInterval {
        switch wave {
        case .oh: return startDelay
        case .my: return startDelay + waveLead
        }
    }

    /// When a wave's last word has left the right edge: 3.55 s for `.oh`,
    /// 4.95 s for `.my`.
    static func end(of wave: BodyIntroWordLayout.Wave) -> TimeInterval {
        start(of: wave) + staggerSpan + slideDuration
    }

    /// The pages fade up under the tail of the second wave, at 4.25 s.
    static let revealStart: TimeInterval = end(of: .my) - revealLead
    /// The overlay can unmount at 4.95 s.
    static let totalDuration: TimeInterval = end(of: .my)

    /// `opacity` and `scale` are always 1: the words neither fade nor resize,
    /// they only slide. Both are kept so a caller can apply a frame whole.
    struct Frame: Equatable {
        let position: CGPoint
        let opacity: Double
        let scale: CGFloat
    }

    /// One straight line at one speed: origin to exit over `slideDuration`,
    /// linear, passing `target` at the halfway mark. Measured against the
    /// word's own wave, not the whole intro.
    static func frame(
        for word: BodyIntroWordLayout.Word,
        in wave: BodyIntroWordLayout.Wave,
        at time: TimeInterval
    ) -> Frame {
        let progress = clamped((time - start(of: wave) - word.delay) / slideDuration)
        return Frame(
            position: interpolate(from: word.origin, to: word.exit, progress: progress),
            opacity: 1,
            scale: 1
        )
    }

    /// 0 until `revealStart`, then eases to 1 over `revealDuration`; the pages
    /// behind fade up on the same curve.
    static func revealProgress(at time: TimeInterval) -> Double {
        let progress = clamped((time - revealStart) / revealDuration)
        return 1 - pow(1 - progress, 3)
    }

    static func isFinished(at time: TimeInterval) -> Bool {
        time >= totalDuration
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func interpolate(from start: CGPoint, to end: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * CGFloat(progress),
            y: start.y + (end.y - start.y) * CGFloat(progress)
        )
    }
}

/// Draws the field through `TimelineView(.animation)` instead of animating
/// state: one clock, so a tap can jump it forward and a preview can freeze it.
struct BodyIntroAnimationView: View {
    /// Fires once when the pages behind should begin to appear.
    let onReveal: () -> Void
    /// Fires once when the last word is gone and the overlay can unmount.
    let onFinished: () -> Void
    /// Previews and render tests only: freezes the field at this instant, with
    /// no clock and no callbacks.
    let previewTime: TimeInterval?

    @State private var startDate = Date()
    /// A tap adds the distance to `revealStart`, so the same clock runs on.
    @State private var skipOffset: TimeInterval = 0
    /// Bumped by a skip to restart the callback clock against the new offset.
    @State private var skipGeneration = 0
    @State private var hasRevealed = false
    @State private var hasFinished = false

    init(
        previewTime: TimeInterval? = nil,
        onReveal: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.previewTime = previewTime
        self.onReveal = onReveal
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { proxy in
            // Rebuilt whenever the size changes, so rotation and iPad get a
            // field spaced for the bounds they actually have.
            let layouts = BodyIntroWordLayout.Wave.allCases.map { wave in
                (wave: wave, layout: BodyIntroWordLayout.make(in: proxy.size, wave: wave))
            }

            ZStack {
                // A real button, not a tap gesture: VoiceOver and Switch
                // Control need something they can reach and activate.
                Button(action: skip) {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("onboarding.intro.skip"))

                TimelineView(.animation(paused: previewTime != nil)) { context in
                    let time = elapsed(at: context.date)

                    // `allCases` order puts the "oooh" wave below the "my"
                    // wave, so the second field streams in over the first.
                    ZStack {
                        ForEach(layouts, id: \.wave) { entry in
                            ForEach(entry.layout.words) { word in
                                let frame = BodyIntroTimeline.frame(for: word, in: entry.wave, at: time)

                                Text(word.text)
                                    .font(.system(size: word.fontSize, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.primary.opacity(word.opacity))
                                    // The user's own background can sit anywhere
                                    // in the scheme, so each word carries a soft
                                    // halo in the scheme's background color.
                                    .shadow(color: Color(.systemBackground).opacity(0.35), radius: BodyIntroWordLayout.haloRadius)
                                    .position(frame.position)
                            }
                        }
                    }
                }
                // The words are decoration over the skip target underneath.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .task(id: skipGeneration) {
            await runClock()
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        if let previewTime {
            return previewTime
        }
        return date.timeIntervalSince(startDate) + skipOffset
    }

    /// Drives the two callbacks off the same clock the field is drawn from. A
    /// skip cancels and restarts it, so the remaining waits are recomputed.
    private func runClock() async {
        guard previewTime == nil else {
            return
        }

        if !hasRevealed {
            let wait = BodyIntroTimeline.revealStart - elapsed(at: Date())
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else {
                    return
                }
            }
            fireReveal()
        }

        let wait = BodyIntroTimeline.totalDuration - elapsed(at: Date())
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else {
                return
            }
        }
        fireFinish()
    }

    /// Jumps the clock to the reveal, so a skip still ends on the same motion
    /// the flow would have shown anyway. A late tap does nothing.
    private func skip() {
        guard previewTime == nil else {
            return
        }

        let now = elapsed(at: Date())
        guard now < BodyIntroTimeline.revealStart else {
            return
        }

        skipOffset += BodyIntroTimeline.revealStart - now
        skipGeneration += 1
        fireReveal()
    }

    /// The latch is set before the closure runs, so a callback that lands at
    /// the same moment as a skip can't fire twice.
    private func fireReveal() {
        guard !hasRevealed else {
            return
        }
        hasRevealed = true
        onReveal()
    }

    private func fireFinish() {
        guard !hasFinished else {
            return
        }
        hasFinished = true
        onFinished()
    }
}

#Preview {
    ZStack {
        BodyAppBackground()
            .ignoresSafeArea()

        BodyIntroAnimationView(
            previewTime: BodyIntroTimeline.start(of: .oh)
                + BodyIntroTimeline.staggerSpan * 0.5
                + BodyIntroTimeline.slideDuration * 0.5,
            onReveal: {},
            onFinished: {}
        )
    }
}
