//
//  BodyHealthSyncBadge.swift
//  Body
//

import Accessibility
import SwiftUI

/// Floating capsule status badge (Apple Health-style "Syncing…" pill) shown
/// top-center over all tabs while a HealthKit refresh runs, then briefly
/// confirming completion before auto-dismissing.
struct BodyHealthSyncBadge: View {
    @EnvironmentObject private var workoutStore: HealthKitWorkoutStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the first-launch load overlay is presented; that modal
    /// already narrates the initial load, so the badge suppresses the whole
    /// refresh cycle (no late "updated" flash or announcement).
    let isSuppressed: Bool

    private enum Phase: Equatable { case hidden, syncing, updated }
    @State private var phase: Phase = .hidden
    /// The store's success count captured when syncing began; confirmation
    /// shows only if the count advanced past this (i.e. the refresh actually
    /// succeeded — finishRefresh() also runs on errors). The count, not
    /// `lastSuccessfulRefreshDate`, because workout-month, single-metric, and
    /// warm-resume refreshes deliberately leave that date alone.
    @State private var successCountAtSyncStart = 0

    var body: some View {
        ZStack(alignment: .top) {
            if phase != .hidden {
                badgeLabel
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        // Animate only presence (slide/fade in and out). Binding the animation to
        // `phase` itself would crossfade the syncing → updated content swap,
        // briefly double-exposing both strings in the capsule.
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: phase == .hidden)
        .allowsHitTesting(false)
        .onAppear {
            if workoutStore.isRefreshing && !isSuppressed { beginSyncing() }
        }
        .onChange(of: isSuppressed) { _, suppressed in
            if suppressed {
                phase = .hidden
            } else if workoutStore.isRefreshing {
                beginSyncing()
            }
        }
        .onChange(of: workoutStore.isRefreshing) { _, isRefreshing in
            guard !isSuppressed, isRefreshing else { return }
            beginSyncing()
        }
        // Falling edge, debounced: a chained follow-up refresh cancels this
        // (task id flips back to true) and the badge stays in .syncing; the
        // 0.6 s floor also keeps the syncing state readable on fast refreshes.
        .task(id: workoutStore.isRefreshing) {
            guard !workoutStore.isRefreshing, phase == .syncing else { return }
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled, !workoutStore.isRefreshing, phase == .syncing else { return }
            if workoutStore.syncBadgeSuccessCount != successCountAtSyncStart {
                phase = .updated
                AccessibilityNotification.Announcement(String(localized: "Health data updated")).post()
            } else {
                phase = .hidden   // failed/no-op refresh: no false confirmation
            }
        }
        // task(id:) cancels the pending dismiss if a new refresh flips back to .syncing.
        .task(id: phase) {
            guard phase == .updated else { return }
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { phase = .hidden }
        }
    }

    private func beginSyncing() {
        if phase != .syncing {
            successCountAtSyncStart = workoutStore.syncBadgeSuccessCount
        }
        phase = .syncing
    }

    private var badgeLabel: some View {
        BodySyncStatusBadgeLabel(
            icon: phase == .syncing ? .spinner : .checkmark,
            text: phase == .syncing ? "Syncing health data…" : "Health data updated"
        )
    }
}

/// The badge's visual: a small leading spinner or checkmark plus a short
/// status label in the shared capsule chrome. Also used by the Workouts
/// month-load indicator so every loading pill shares one design.
struct BodySyncStatusBadgeLabel: View {
    enum Icon { case spinner, checkmark }

    let icon: Icon
    let text: LocalizedStringKey
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
                        BodyMarchingSquaresLoader()
                            .accessibilityHidden(true)
                    }
                case .checkmark:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            // Uniform icon slot so the capsule is the same height in every
            // state — the 14 pt loader would otherwise render a slightly
            // thinner pill than the ~18 pt checkmark glyph.
            .frame(width: 18, height: 18)
            Text(text)
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .modifier(BodyHealthSyncBadgeBackground(colorScheme: colorScheme))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
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

/// A native "marching squares" loader: seven small squares hop one cell at a
/// time around a 3×3 snake path (the bottom-right cell stays empty), so a
/// single gap appears to travel around the grid. Driven entirely from
/// wall-clock time via `TimelineView` — no `onAppear`-started repeating
/// animation to lose when the badge is conditionally inserted/removed.
/// Decorative; the enclosing capsule carries the accessibility label.
private struct BodyMarchingSquaresLoader: View {
    /// Snake path over the 3×3 grid in `(col, row)`, excluding the bottom-right
    /// cell so it is never occupied and the gap circles the remaining eight.
    private static let path: [(col: Int, row: Int)] = [
        (0, 0), (1, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2), (0, 1)
    ]
    private static let cellCount = path.count            // 8 cells, 7 squares
    private static let period: Double = 2.8              // seconds per full gap loop
    private static let squareSize: CGFloat = 4
    private static let gapSize: CGFloat = 1
    private static let stride = squareSize + gapSize     // 5 pt per cell
    /// Fraction of each hop slot spent sliding; the remainder is a dwell — a
    /// quick eased hop (~2% of the period) then a hold (~10.5%).
    private static let slidePortion: Double = 0.16
    /// Cell the gap sits in at t = 0.
    private static let gapStart = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { canvas, _ in
                let t = context.date.timeIntervalSinceReferenceDate
                for rect in Self.squareRects(at: t) {
                    canvas.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.secondary))
                }
            }
        }
        .frame(width: Self.stride * 2 + Self.squareSize,
               height: Self.stride * 2 + Self.squareSize)
    }

    /// Positions of the seven squares at time `t`: six stationary plus the one
    /// currently sliding into the gap.
    private static func squareRects(at t: TimeInterval) -> [CGRect] {
        let hopDuration = period / Double(cellCount)
        let hopCount = t / hopDuration
        let k = Int(floor(hopCount))
        let frac = hopCount - floor(hopCount)

        // The gap steps one cell backward along the path per hop; the square
        // just behind it slides forward to fill it.
        let gapCell = mod(gapStart - k, cellCount)
        let moverOrigin = mod(gapCell - 1, cellCount)
        let moverTarget = gapCell

        // Quick eased slide over the first `slidePortion` of the hop, then hold.
        let p = frac < slidePortion ? easeInOut(frac / slidePortion) : 1

        var rects: [CGRect] = []
        rects.reserveCapacity(cellCount - 1)
        for index in 0..<cellCount where index != gapCell && index != moverOrigin {
            rects.append(rect(forCell: index))
        }
        let origin = point(forCell: moverOrigin)
        let target = point(forCell: moverTarget)
        rects.append(CGRect(x: origin.x + (target.x - origin.x) * p,
                            y: origin.y + (target.y - origin.y) * p,
                            width: squareSize, height: squareSize))
        return rects
    }

    private static func point(forCell index: Int) -> CGPoint {
        let cell = path[index]
        return CGPoint(x: CGFloat(cell.col) * stride, y: CGFloat(cell.row) * stride)
    }

    private static func rect(forCell index: Int) -> CGRect {
        let p = point(forCell: index)
        return CGRect(x: p.x, y: p.y, width: squareSize, height: squareSize)
    }

    private static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
    }

    private static func mod(_ a: Int, _ n: Int) -> Int {
        ((a % n) + n) % n
    }
}

#Preview {
    BodyHealthSyncBadge(isSuppressed: false)
        .environmentObject(HealthKitWorkoutStore())
}
