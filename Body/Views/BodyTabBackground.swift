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
    @Environment(BodyHingeState.self) private var hingeState: BodyHingeState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue
    @AppStorage(BodyAppearancePreference.foldedHomeContentWidthKey) private var foldedHomeContentWidth: Double = 0
    @AppStorage(BodyAppearancePreference.homeBackgroundEnabledKey) private var homeBackgroundEnabled = true
    @AppStorage(BodyAppearancePreference.homeBackgroundColorsKey) private var homeBackgroundColorsRawValue = ""
    @AppStorage(BodyAppearancePreference.homeBackgroundSeparatorsKey) private var homeBackgroundSeparatorsRawValue = ""

    private var starMetric: BodyStarMetric? {
        BodyStarMetric.from(rawValue: starredMetricRawValue)
    }

    private var isReadinessStarred: Bool {
        starMetric == .readiness
    }

    /// The hero's width and horizontal center in the full-bleed background: centered in
    /// the page (the safe area, which a foldable's outer screen insets for its camera,
    /// so the full-bleed center would miss the ring), or on a foldable's inner screen
    /// centered on the folded right column that holds the hero there (`BodyHomeView`).
    private func heroGeometry(pageWidth: CGFloat, safeAreaLeading: CGFloat, safeAreaTrailing: CGFloat) -> (width: CGFloat, centerX: CGFloat) {
        let foldedColumnWidth = AppLayout.foldedHomeColumnWidth(stored: foldedHomeContentWidth)
        if AppLayout.isFoldableSplit(contentWidth: min(pageWidth, AppLayout.homeContentWidth) - 32, columnWidth: foldedColumnWidth) {
            let columnWidth = AppLayout.foldableHomeColumnWidth(
                hinge: hingeState?.status ?? .unknown,
                pageWidth: pageWidth,
                safeAreaLeading: safeAreaLeading,
                safeAreaTrailing: safeAreaTrailing,
                foldedColumnWidth: foldedColumnWidth
            )
            return (columnWidth, safeAreaLeading + AppLayout.foldedHomeColumnCenterX(pageWidth: pageWidth, columnWidth: columnWidth))
        }
        return (BodyReadinessArcGeometry.heroWidth(pageWidth: pageWidth), safeAreaLeading + pageWidth / 2)
    }

    var body: some View {
        // The reader sits inside the safe area, so its top inset is the status bar strip
        // the full-bleed background extends behind; the glow needs it to land on the ring.
        GeometryReader { geo in
            content(
                safeAreaTop: geo.safeAreaInsets.top,
                safeAreaLeading: geo.safeAreaInsets.leading,
                safeAreaTrailing: geo.safeAreaInsets.trailing,
                pageWidth: geo.size.width
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(safeAreaTop: CGFloat, safeAreaLeading: CGFloat, safeAreaTrailing: CGFloat, pageWidth: CGFloat) -> some View {
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
                let hero = heroGeometry(pageWidth: pageWidth, safeAreaLeading: safeAreaLeading, safeAreaTrailing: safeAreaTrailing)
                BodyReadinessGlowBackground(
                    tint: status.map { BodyReadinessStatusPresentation.color(for: $0) },
                    circleCenterY: safeAreaTop + 10 + BodyReadinessArcGeometry.arcCenterY(width: hero.width),
                    glowRadius: BodyReadinessArcGeometry.glowRadius(width: hero.width),
                    circleCenterX: hero.centerX
                )
                .id(status)
                .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: status)
        } else if starMetric == .dayRing {
            // The same ring glow, colored for the part of the day and crossfading as it turns.
            TimelineView(.everyMinute) { context in
                let part = DayRingDayPart(hour: Calendar.bodyGregorian.component(.hour, from: context.date))
                ZStack {
                    let hero = heroGeometry(pageWidth: pageWidth, safeAreaLeading: safeAreaLeading, safeAreaTrailing: safeAreaTrailing)
                    BodyReadinessGlowBackground(
                        tint: part.glowColor,
                        circleCenterY: safeAreaTop + 10 + BodyReadinessArcGeometry.arcCenterY(width: hero.width),
                        glowRadius: BodyReadinessArcGeometry.glowRadius(width: hero.width),
                        circleCenterX: hero.centerX
                    )
                    .id(part)
                    .transition(.opacity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: part)
            }
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
/// a home hero is pinned, the app mix everywhere else. `TabView` swaps pages instantly
/// and every page paints this, so the background it lands on is picked from the
/// selected tab and switches with the page, without any fade between the two.
struct BodyTabPageBackground: View {
    @Environment(\.selectedMainTab) private var selectedTab
    @AppStorage(BodyAppearancePreference.starredMetricKey) private var starredMetricRawValue = BodyHomeCardKind.readiness.rawValue

    private var hasStarMetric: Bool {
        BodyStarMetric.from(rawValue: starredMetricRawValue) != nil
    }

    var body: some View {
        if hasStarMetric && selectedTab == .summary {
            BodyHomePageBackground()
        } else {
            BodyAppBackground().ignoresSafeArea()
        }
    }
}
