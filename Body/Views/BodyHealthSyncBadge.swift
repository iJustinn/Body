//
//  BodyHealthSyncBadge.swift
//  Body
//

import Accessibility
import SwiftUI

/// Badge copy for each refresh phase. The strings live with the view rather
/// than the store because they are UI copy; `.fetching` keeps the original
/// "Loading data..." so the common case reads exactly as before.
extension HealthKitWorkoutStore.RefreshStage {
    var badgeText: LocalizedStringKey {
        switch self {
        case .authorizing: "Checking Health access..."
        case .fetching: "Loading data..."
        case .syncing: "Syncing..."
        case .updatingHealth: "Updating health data..."
        case .updatingRings: "Updating Activity Rings..."
        case .computing(let target):
            switch target {
            case .readiness: "Calculating Readiness..."
            case .stress: "Calculating Stress..."
            case .trainingLoad: "Calculating Training Load..."
            case .bodyRadar: "Calculating Body Radar..."
            }
        case .updating(let kind):
            switch kind {
            case .readiness: "Updating Readiness..."
            case .stress: "Updating Stress..."
            case .bodyRadar: "Updating Body Radar..."
            case .sleep: "Updating Sleep..."
            case .basics: "Updating Body Measurements..."
            case .heartRate: "Updating Heart Rate..."
            case .restingHeartRate: "Updating Resting Heart Rate..."
            case .bodyMass: "Updating Weight..."
            case .bodyFatPercentage: "Updating Body Fat..."
            case .heartRateVariability: "Updating Heart Rate Variability..."
            case .respiratoryRate: "Updating Respiratory Rate..."
            case .oxygenSaturation: "Updating Blood Oxygen..."
            case .bodyMassIndex: "Updating Body Mass Index..."
            case .activeEnergy: "Updating Active Energy..."
            case .restingEnergy: "Updating Resting Energy..."
            case .exerciseMinutes: "Updating Exercise Minutes..."
            case .trainingLoad: "Updating Training Load..."
            case .wristTemperature: "Updating Wrist Temperature..."
            case .timeInDaylight: "Updating Time in Daylight..."
            case .steps: "Updating Steps..."
            case .vitals: "Updating Vitals..."
            case .cardioFitness: "Updating Cardio Fitness..."
            }
        case .writingEffort: "Saving workout effort..."
        case .finishing: "Finishing up..."
        }
    }
}

/// One visible session spans active work and already-scheduled foreground work.
/// Execution and all time-dependent decisions live in the testable presentation
/// state; this adapter only sleeps until its next deadline and renders it.
struct BodyHealthSyncBadge: View {
    @Environment(HealthKitWorkoutStore.self) private var workoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    let isSuppressed: Bool
    @State private var suppressedSessionID: UUID?

    private var presentation: BodySyncPresentation { workoutStore.syncPresentation }
    private var showsBadge: Bool { !isSuppressed && presentation.sessionID != suppressedSessionID && presentation.phase != .hidden }

    var body: some View {
        ZStack(alignment: .top) {
            if showsBadge {
                BodySyncStatusBadgeLabel(
                    icon: presentation.phase == .syncing ? .spinner : .checkmark,
                    text: presentation.phase == .syncing ? presentation.displayedStage.badgeText : completionText,
                    textID: AnyHashable(presentation.displayedStage),
                    updatesFrequently: false
                )
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showsBadge)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: presentation.phase)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: presentation.displayedStage)
        .allowsHitTesting(false)
        .task(id: presentation) {
            let expected = presentation
            guard let deadline = expected.nextDeadline else { return }
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            workoutStore.advanceSyncPresentation(expected: expected)
        }
        .onAppear {
            if isSuppressed { suppressedSessionID = presentation.sessionID }
        }
        .onChange(of: presentation.sessionID) { _, id in
            if isSuppressed { suppressedSessionID = id }
        }
        .onChange(of: isSuppressed) { _, suppressed in
            if suppressed { suppressedSessionID = presentation.sessionID }
        }
        .onChange(of: presentation.phase) { _, phase in
            guard !isSuppressed, presentation.sessionID != suppressedSessionID else { return }
            if phase == .updated {
                AccessibilityNotification.Announcement(completionMessage).post()
            } else if phase == .partial {
                AccessibilityNotification.Announcement(String(localized: "Some health data updated")).post()
            }
        }
    }

    private var completionText: LocalizedStringKey {
        LocalizedStringKey(completionMessage)
    }

    private var completionMessage: String {
        if presentation.phase == .partial { return String(localized: "Some health data updated") }
        guard let completedAt = presentation.completedAt else { return "" }
        let time = completedAt.formatted(.dateTime.hour().minute().locale(locale))
        return String(localized: "All done · \(time)", locale: locale)
    }
}

/// The badge's visual: a small leading spinner or checkmark plus a short
/// status label in the shared capsule chrome. Also used by the Workouts
/// month-load indicator and the share sheet's media import so every loading
/// pill shares one design.
struct BodySyncStatusBadgeLabel: View {
    enum Icon { case spinner, checkmark }

    let icon: Icon
    let text: LocalizedStringKey
    /// Identity for the label alone, so a text change that keeps the same icon
    /// (one syncing stage to the next) still blur-replaces. Defaults to the
    /// icon, which is what every other call site wants.
    var textID: AnyHashable? = nil
    var updatesFrequently = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch icon {
                case .spinner:
                    if reduceMotion {
                        // Reduce Motion: fall back to the standard spinner (the
                        // system tones its animation down for us).
                        ProgressView().controlSize(.small).tint(.secondary)
                    } else {
                        BodyPixelGridLoader()
                            .accessibilityHidden(true)
                    }
                case .checkmark:
                    BodyGridCheckmarkIcon()
                        .accessibilityHidden(true)
                }
            }
            // Uniform icon slot so the capsule is the same height in every
            // state — the 14 pt loader would otherwise render a slightly
            // thinner pill than the ~18 pt checkmark glyph.
            .frame(width: 18, height: 18)
            // `id(icon)` swaps identity when the state flips, so the old
            // icon/text blur out as the new blur in — a clean in-place morph
            // instead of a garbled full-opacity crossfade of both strings.
            .id(icon)
            .transition(.blurReplace)
            Text(text)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .id(textID ?? AnyHashable(icon))
                .transition(.blurReplace)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .modifier(BodyHealthSyncBadgeBackground(colorScheme: colorScheme))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(updatesFrequently ? .updatesFrequently : [])
    }
}

/// iOS 26 Liquid Glass capsule; on iOS 18 mirrors the BodyPillTabBar recipe.
private struct BodyHealthSyncBadgeBackground: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .light ? 0.06 : 0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(colorScheme == .light ? 0.12 : 0.30), radius: 12, x: 0, y: 6)
            )
        }
    }
}

/// Pixel-grid checkmark in the pixel-grid loader's visual language: the
/// classic five-pixel tick drawn as lit white pixels with the loader's glow
/// instead of an SF Symbol, so the syncing → finished morph stays within one
/// design family. Decorative; the enclosing capsule carries the
/// accessibility label.
private struct BodyGridCheckmarkIcon: View {
    /// Tick pixels in `(col, row)` on a 5-wide grid: descending short arm
    /// (0,2) → (1,3), ascending long arm (2,2) → (3,1) → (4,0).
    private static let cells: [(col: Int, row: Int)] = [
        (0, 2), (1, 3), (2, 2), (3, 1), (4, 0)
    ]
    private static let squareSize: CGFloat = 2.4
    private static let gapSize: CGFloat = 0.5
    private static let stride = squareSize + gapSize
    private static let gridWidth = stride * 4 + squareSize
    private static let gridHeight = stride * 3 + squareSize
    /// Same canvas slack as the loader so the outer glow isn't clipped; the
    /// view still lays out at the grid size.
    private static let effectExtent: CGFloat = 5

    var body: some View {
        Color.clear
            .frame(width: Self.gridWidth, height: Self.gridHeight)
            .overlay {
                Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { canvas, _ in
                    let tick = Self.cells.map { Self.cellPath(col: $0.col, row: $0.row) }

                    // The loader's glow recipe: two screen-blended shadow-only
                    // passes over the lit pixels.
                    for (opacity, radius) in [(0.55, CGFloat(2.5)), (0.28, CGFloat(5))] {
                        canvas.drawLayer { layer in
                            layer.blendMode = .screen
                            layer.addFilter(
                                .shadow(color: .white.opacity(opacity), radius: radius, options: .shadowOnly),
                                options: .linearColor
                            )
                            for path in tick {
                                layer.fill(path, with: .color(.white))
                            }
                        }
                    }

                    for path in tick {
                        canvas.fill(path, with: .color(.white))
                    }
                }
                .frame(width: Self.gridWidth + Self.effectExtent * 2,
                       height: Self.gridHeight + Self.effectExtent * 2)
            }
    }

    private static func cellPath(col: Int, row: Int) -> Path {
        let rect = CGRect(
            x: effectExtent + CGFloat(col) * stride,
            y: effectExtent + CGFloat(row) * stride,
            width: squareSize,
            height: squareSize
        )
        return Path(roundedRect: rect, cornerRadius: 0.6)
    }
}

/// A native pixel-display loader: nine white cells on a 3×3 grid light up on
/// staggered per-cell delays, hold, then fade back out together, so the grid
/// reads as a wave, spiral, snake, rain burst… depending on which delay
/// pattern is playing. One pattern is drawn at random each time the loader
/// appears, so repeated refreshes don't feel like the same canned clip.
///
/// Driven entirely from wall-clock time via `TimelineView` — no
/// `onAppear`-started repeating animation to lose when the badge is
/// conditionally inserted/removed — but measured from an `epoch` captured at
/// insertion rather than a shared reference date, so every appearance starts
/// its pattern from the first cell instead of joining mid-cycle.
///
/// Animation patterns and pixel-display look adapted from SwiftPixelGrid
/// (MIT, github.com/afetmin/SwiftPixelGrid).
/// Decorative; the enclosing capsule carries the accessibility label.
private struct BodyPixelGridLoader: View {
    /// SwiftPixelGrid's preset table: per-cell start delays in row-major order
    /// plus the fully-lit hold, both in milliseconds. Its colour variants are
    /// folded away — every cell here is white, so they'd be exact duplicates —
    /// leaving the 17 distinct rhythms.
    private static let patterns: [(delays: [Int], hold: Int)] = [
        (delays: [0, 120, 240, 0, 120, 240, 0, 120, 240], hold: 200),        // wave L→R
        (delays: [240, 120, 0, 240, 120, 0, 240, 120, 0], hold: 200),        // wave R→L
        (delays: [0, 0, 0, 120, 120, 120, 240, 240, 240], hold: 200),        // wave T→B
        (delays: [240, 240, 240, 120, 120, 120, 0, 0, 0], hold: 200),        // wave B→T
        (delays: [0, 80, 160, 560, 640, 240, 480, 400, 320], hold: 180),     // spiral CW
        (delays: [0, 200, 0, 200, 400, 200, 0, 200, 0], hold: 200),          // corners first
        (delays: [240, 120, 240, 120, 0, 120, 240, 120, 240], hold: 200),    // center out
        (delays: [0, 100, 200, 100, 200, 300, 200, 300, 400], hold: 180),    // diagonal TL
        (delays: [0, 80, 160, 400, 320, 240, 480, 560, 640], hold: 160),     // snake
        (delays: [300, 0, 300, 0, 0, 0, 300, 0, 300], hold: 250),            // cross
        (delays: [0, 250, 0, 250, 0, 250, 0, 250, 0], hold: 220),            // checkerboard
        (delays: [0, 180, 60, 120, 300, 240, 360, 80, 420], hold: 170),      // rain
        (delays: [0, 160, 480, 320, 640, 160, 480, 320, 0], hold: 150),      // pinwheel
        (delays: [0, 80, 160, 480, 640, 240, 400, 320, 560], hold: 120),     // orbit
        (delays: [0, 160, 80, 240, 320, 240, 80, 160, 0], hold: 260),        // converge
        (delays: [0, 160, 320, 400, 240, 80, 480, 560, 640], hold: 140),     // zigzag
        (delays: [0, 80, 160, 240, 320, 400, 480, 560, 640], hold: 160)      // linear sweep
    ]

    private static let cellCount = 9
    private static let columns = 3
    private static let squareSize: CGFloat = 4
    private static let gapSize: CGFloat = 1
    private static let stride = squareSize + gapSize      // 5 pt per cell
    private static let gridSize = stride * 2 + squareSize  // 14 pt logical footprint
    /// Slack around the grid inside the canvas so the outer glow can bleed past
    /// the cells instead of being clipped at the drawing bounds; the view still
    /// lays out at `gridSize` (a `Color.clear` frame) and the oversized canvas
    /// rides in an overlay, so the padding costs no layout space.
    private static let effectExtent: CGFloat = 5
    private static let canvasSize = gridSize + effectExtent * 2  // 24 pt
    /// Fade-in and fade-out length; the hold between them runs until every
    /// cell has had its turn (`maxDelay + hold`).
    private static let transitionDuration: TimeInterval = 0.3
    /// Beat of darkness after the last cell fades, so cycles don't butt together.
    private static let fadeOutPadding: TimeInterval = 0.05
    private static let innerGlowRadius: CGFloat = 2.5
    private static let outerGlowRadius: CGFloat = 5
    /// Always-visible "off" cells, so the animation reads as one pixel display
    /// lighting up rather than squares appearing out of nowhere.
    private static let offOpacity: Double = 0.3

    /// Re-rolled whenever the loader gets a new identity, i.e. on every visible
    /// insertion of the spinner; a refresh that keeps the badge up is one load
    /// and keeps its pattern. Repeats across appearances are allowed.
    @State private var pattern = Self.patterns.randomElement()!
    /// Delays are relative to this, captured when the loader is inserted.
    @State private var epoch = Date()

    var body: some View {
        Color.clear
            .frame(width: Self.gridSize, height: Self.gridSize)
            .overlay {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    // The grid is tiny; drawing synchronously keeps the beat even
                    // instead of letting frames coalesce asynchronously.
                    Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { canvas, _ in
                        let elapsed = context.date.timeIntervalSince(epoch)
                        Self.draw(Self.intensities(at: elapsed, pattern: pattern), in: &canvas)
                    }
                    .frame(width: Self.canvasSize, height: Self.canvasSize)
                }
            }
    }

    /// Brightness of each of the nine cells at `elapsed`, in `0...1`.
    private static func intensities(
        at elapsed: TimeInterval,
        pattern: (delays: [Int], hold: Int)
    ) -> [Double] {
        let delays = pattern.delays.map { TimeInterval($0) / 1000 }
        let hold = TimeInterval(pattern.hold) / 1000
        let holdTime = (delays.max() ?? 0) + hold
        let cycle = 2 * holdTime + fadeOutPadding
        return delays.map { intensity(at: elapsed, delay: $0, holdTime: holdTime, cycle: cycle) }
    }

    private static func intensity(
        at elapsed: TimeInterval,
        delay: TimeInterval,
        holdTime: TimeInterval,
        cycle: TimeInterval
    ) -> Double {
        let local = elapsed - delay
        // Before a cell's delay elapses it is simply off. Wrapping the negative
        // through the modulo instead would drop the cell into the tail of an
        // imaginary previous cycle, flashing a stale fade-out at insertion.
        guard local >= 0 else { return 0 }

        let t = local.truncatingRemainder(dividingBy: cycle)
        if t < holdTime {
            guard t < transitionDuration else { return 1 }
            return easeOut(t / transitionDuration)
        }
        let fadeOut = t - holdTime
        guard fadeOut < transitionDuration else { return 0 }
        return 1 - easeOut(fadeOut / transitionDuration)
    }

    /// Cubic ease-out; visually the same curve SwiftPixelGrid solves as
    /// `cubic-bezier(0, 0, 0.58, 1)`, without the Newton iteration.
    private static func easeOut(_ x: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    private static func draw(_ intensities: [Double], in canvas: inout GraphicsContext) {
        // Glow first, in two passes over the whole grid rather than per cell: a
        // later cell's shadow would otherwise wash over an earlier cell's body
        // and leave uneven bright edges.
        drawGlow(intensities, in: &canvas, opacity: 0.55, radius: innerGlowRadius)
        drawGlow(intensities, in: &canvas, opacity: 0.28, radius: outerGlowRadius)

        for index in 0..<cellCount {
            canvas.fill(cellPath(at: index), with: .color(.white.opacity(offOpacity)))
        }

        // Lit cells only change opacity — the body colour stays white so a cell
        // never shows a differently tinted core while fading.
        for (index, intensity) in intensities.enumerated() where intensity > 0 {
            canvas.fill(cellPath(at: index), with: .color(.white.opacity(intensity)))
        }
    }

    /// One screen-blended shadow-only layer for the entire grid. A filter's
    /// colour is fixed for the layer, so the per-cell brightness rides in on
    /// the source alpha instead.
    private static func drawGlow(
        _ intensities: [Double],
        in canvas: inout GraphicsContext,
        opacity: Double,
        radius: CGFloat
    ) {
        canvas.drawLayer { layer in
            layer.blendMode = .screen
            layer.addFilter(
                .shadow(color: .white.opacity(opacity), radius: radius, options: .shadowOnly),
                options: .linearColor
            )
            for (index, intensity) in intensities.enumerated() where intensity > 0 {
                layer.fill(cellPath(at: index), with: .color(.white.opacity(intensity)))
            }
        }
    }

    /// Row-major cell `index` as a rounded square, offset by the glow extent.
    private static func cellPath(at index: Int) -> Path {
        let rect = CGRect(
            x: effectExtent + CGFloat(index % columns) * stride,
            y: effectExtent + CGFloat(index / columns) * stride,
            width: squareSize,
            height: squareSize
        )
        return Path(roundedRect: rect, cornerRadius: 1)
    }
}

#Preview {
    BodyHealthSyncBadge(isSuppressed: false)
        .environment(HealthKitWorkoutStore())
}
