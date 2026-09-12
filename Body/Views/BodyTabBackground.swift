//
//  BodyTabBackground.swift
//  Body
//

import SwiftUI

private struct SelectedMainTabKey: EnvironmentKey {
    static let defaultValue: BodyMainTab = .summary
}

private struct PreviousMainTabKey: EnvironmentKey {
    static let defaultValue: BodyMainTab? = nil
}

/// The band the hero's pill is heading for, cleared as a slide starts and published a
/// fixed delay later, so the page glow stays off at the start of the slide and fades in
/// on the target band as the pill arrives.
@Observable
final class BodyReadinessHeroState {
    var activeStatus: ReadinessStatus?
}

extension EnvironmentValues {
    /// The main tab currently on screen, published by `MainTabView` so each page's
    /// background can crossfade when the selection changes.
    var selectedMainTab: BodyMainTab {
        get { self[SelectedMainTabKey.self] }
        set { self[SelectedMainTabKey.self] = newValue }
    }

    /// The tab shown before `selectedMainTab`, nil until the first switch, so a page
    /// appearing after a switch knows which background to fade from.
    var previousMainTab: BodyMainTab? {
        get { self[PreviousMainTabKey.self] }
        set { self[PreviousMainTabKey.self] = newValue }
    }
}

/// The Summary page's fixed full-bleed backdrop: the custom Background color mix when
/// enabled, otherwise the plain grouped background. While Readiness is starred the mix
/// is replaced by a soft glow of today's band color centered in the hero's ring,
/// crossfading when the band changes.
struct BodyHomePageBackground: View {
    @Environment(HealthKitWorkoutStore.self) private var workoutStore
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @Environment(BodyReadinessHeroState.self) private var heroState: BodyReadinessHeroState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var homeBackgroundEnabled = true
    @AppStorage(BodyAppearancePreference.homeBackgroundColorsKey) private var homeBackgroundColorsRawValue = ""
    @AppStorage(BodyAppearancePreference.homeBackgroundSeparatorsKey) private var homeBackgroundSeparatorsRawValue = ""

    private var isReadinessStarred: Bool {
        BodyHomeCardKind.starredMetric(from: starredMetricRawValue) == .readiness
    }

    var body: some View {
        // The reader sits inside the safe area, so its top inset is the status bar strip
        // the full-bleed background extends behind; the glow needs it to land on the ring.
        GeometryReader { geo in
            content(safeAreaTop: geo.safeAreaInsets.top)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(safeAreaTop: CGFloat) -> some View {
        if isReadinessStarred {
            let readiness = workoutStore.healthSummary.readiness
            // The glow is off while the pill is sliding and fades in on the band it
            // landed on; without a hero to report (onboarding) it shows today's band.
            // Gradient stops don't interpolate on their own, so a band change is a
            // crossfade between two backgrounds. The glow is centered on the arc's
            // circle: the hero rests under the safe area and the content's top padding.
            let status: ReadinessStatus? = if let heroState {
                heroState.activeStatus
            } else {
                readiness.score == nil ? nil : readiness.status
            }
            ZStack {
                BodyReadinessGlowBackground(
                    tint: status.map { BodyReadinessStatusPresentation.color(for: $0) },
                    circleCenterY: safeAreaTop + 10 + BodyReadinessArcGeometry.arcCenterY
                )
                .id(status)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: status)
        } else if homeBackgroundEnabled {
            let isPro = proStore?.isPro ?? false
            BodyActivityRingsCard.heroBackground(
                colors: BodyHomeBackground.proGatedColors(from: homeBackgroundColorsRawValue, isProUnlocked: isPro),
                separators: BodyHomeBackground.proGatedSeparators(from: homeBackgroundSeparatorsRawValue, isProUnlocked: isPro)
            )
        } else {
            Color(.systemGroupedBackground)
        }
    }
}

/// A main tab page's full-bleed background. While Readiness is starred, Summary paints
/// the ring glow and the other tabs the app mix, so a tab switch dissolves between the
/// two: `TabView` swaps pages instantly, so every page paints the app mix with the glow
/// laid over it, and the glow's opacity follows whether Summary is the selected tab.
/// The fade is driven explicitly on appear, starting from the background of the tab
/// just left, because a page that is shown in the same update as the selection change
/// would otherwise start at its final opacity and show no dissolve at all. When
/// Readiness is not starred every tab shares the same app background, so nothing
/// animates. Skipped under Reduce Motion.
struct BodyTabCrossfadeBackground: View {
    @Environment(\.selectedMainTab) private var selectedTab
    @Environment(\.previousMainTab) private var previousTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue
    @State private var glowOpacity: Double = 0

    private var isReadinessStarred: Bool {
        BodyHomeCardKind.starredMetric(from: starredMetricRawValue) == .readiness
    }

    private var targetGlowOpacity: Double { selectedTab == .summary ? 1 : 0 }

    var body: some View {
        if isReadinessStarred {
            ZStack {
                BodyAppBackground().ignoresSafeArea()

                BodyHomePageBackground()
                    .opacity(glowOpacity)
            }
            .ignoresSafeArea()
            .onAppear {
                let from = previousTab.map { $0 == .summary ? 1.0 : 0.0 } ?? targetGlowOpacity
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { glowOpacity = from }
                fadeToTarget()
            }
            .onChange(of: selectedTab) { _, _ in
                fadeToTarget()
            }
        } else {
            BodyAppBackground().ignoresSafeArea()
        }
    }

    private func fadeToTarget() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            glowOpacity = targetGlowOpacity
        }
    }
}
