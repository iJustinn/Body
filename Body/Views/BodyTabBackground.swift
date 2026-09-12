//
//  BodyTabBackground.swift
//  Body
//

import SwiftUI

private struct SelectedMainTabKey: EnvironmentKey {
    static let defaultValue: BodyMainTab = .summary
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
    /// background knows whether it is the one being shown.
    var selectedMainTab: BodyMainTab {
        get { self[SelectedMainTabKey.self] }
        set { self[SelectedMainTabKey.self] = newValue }
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
            content(safeAreaTop: geo.safeAreaInsets.top, pageWidth: geo.size.width)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(safeAreaTop: CGFloat, pageWidth: CGFloat) -> some View {
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
                let heroWidth = BodyReadinessArcGeometry.heroWidth(pageWidth: pageWidth)
                BodyReadinessGlowBackground(
                    tint: status.map { BodyReadinessStatusPresentation.color(for: $0) },
                    circleCenterY: safeAreaTop + 10 + BodyReadinessArcGeometry.arcCenterY(width: heroWidth),
                    glowRadius: BodyReadinessArcGeometry.glowRadius(width: heroWidth)
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

/// A main tab page's full-bleed background: the Summary page's ring glow while
/// Readiness is starred, the app mix everywhere else. `TabView` swaps pages instantly
/// and every page paints this, so the background it lands on is picked from the
/// selected tab and switches with the page, without any fade between the two.
struct BodyTabPageBackground: View {
    @Environment(\.selectedMainTab) private var selectedTab
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue

    private var isReadinessStarred: Bool {
        BodyHomeCardKind.starredMetric(from: starredMetricRawValue) == .readiness
    }

    var body: some View {
        if isReadinessStarred && selectedTab == .summary {
            BodyHomePageBackground()
        } else {
            BodyAppBackground().ignoresSafeArea()
        }
    }
}
