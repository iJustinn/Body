//
//  BodyLaunchReveal.swift
//  Body
//

import SwiftUI

/// The cold launch animation. The launch screen (`UILaunchScreen` in Info.plist)
/// already shows the `LaunchIcon` image, so the wait before the first frame is
/// covered; this splash draws the same image in the same place, so the handoff
/// is invisible. The icon gives one heartbeat, then a rounded window the shape
/// of the icon opens where it sits, the icon dissolves into the app behind it,
/// and the window grows past the screen edges. The app itself is never scaled:
/// a transform on the TabView throws off the system tab bar's safe area, so the
/// bar would sit high until the transform went away. It plays once per process,
/// so returning from the background never replays it. Reduce Motion keeps only
/// a fade.
struct BodyLaunchRevealModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasStarted = false
    @State private var isBeating = false
    /// Flipped without animation: the window has to be cut the instant the icon
    /// starts to fade, not fade in underneath it.
    @State private var isRevealing = false
    @State private var isIconFaded = false
    /// 0 with the window the size of the icon, 1 with it far past every screen
    /// edge.
    @State private var revealProgress: CGFloat = 0
    @State private var isFinished = false

    /// The `LaunchIcon` asset's point size: the launch screen draws it unscaled.
    static let iconSize: CGFloat = 68
    private static let iconCornerRadius: CGFloat = 15

    func body(content: Content) -> some View {
        content
            .environment(\.bodyLaunchRevealPending, !isRevealing)
            .overlay {
                if !isFinished {
                    splash
                }
            }
            // Waits for the scene to come on screen, so a prewarmed launch does
            // not spend the animation before anyone can see it.
            .task(id: scenePhase == .active) {
                guard scenePhase == .active, !hasStarted else { return }
                hasStarted = true
                await play()
            }
    }

    private var splash: some View {
        GeometryReader { proxy in
            let windowScale = 1 + (Self.coverScale(for: proxy.size) - 1) * revealProgress

            ZStack {
                // The launch screen's `UIColorName`: black in light and dark mode.
                Color("LaunchBackground")
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: Self.iconCornerRadius, style: .continuous)
                                    .frame(width: Self.iconSize, height: Self.iconSize)
                                    .scaleEffect(windowScale)
                                    .opacity(isRevealing && !reduceMotion ? 1 : 0)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }

                // The launch screen's image, which carries its own icon mask.
                // The launch screen cannot follow an alternate icon, so neither
                // does this.
                Image("LaunchIcon")
                    .resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .scaleEffect((isBeating ? 1.08 : 1) * windowScale)
                    .opacity(isIconFaded ? 0 : 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .opacity(reduceMotion && isRevealing ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func play() async {
        if reduceMotion {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.35)) { isRevealing = true }
            try? await Task.sleep(for: .milliseconds(350))
            isFinished = true
            return
        }

        withAnimation(.easeOut(duration: 0.12)) { isBeating = true }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.spring(duration: 0.35, bounce: 0.5)) { isBeating = false }
        try? await Task.sleep(for: .milliseconds(220))

        isRevealing = true
        withAnimation(.easeOut(duration: 0.2)) { isIconFaded = true }
        // Accelerating, not easing out: the window is still gaining speed as it
        // crosses the screen edges, so it never looks like it stops near them.
        withAnimation(.timingCurve(0.5, 0, 0.9, 0.7, duration: 0.42)) { revealProgress = 1 }
        try? await Task.sleep(for: .milliseconds(420))
        isFinished = true
    }

    /// The window's final scale: twice what clears every corner of `size`, so it
    /// passes the edges about halfway through its growth, at speed, rather than
    /// arriving at them as the animation ends.
    static func coverScale(for size: CGSize) -> CGFloat {
        max(hypot(size.width, size.height) * 2.4 / iconSize, 1)
    }
}

extension View {
    func bodyLaunchReveal() -> some View {
        modifier(BodyLaunchRevealModifier())
    }
}

private struct BodyLaunchRevealPendingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the launch reveal still covers the app, so Home's hero holds its
    /// launch slide until the app comes into view.
    var bodyLaunchRevealPending: Bool {
        get { self[BodyLaunchRevealPendingKey.self] }
        set { self[BodyLaunchRevealPendingKey.self] = newValue }
    }
}
