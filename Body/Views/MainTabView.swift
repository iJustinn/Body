//
//  MainTabView.swift
//  Body
//

import SwiftUI

enum BodyMainTab: Hashable, CaseIterable {
    case summary
    case workouts
    case settings

    var systemImage: String {
        switch self {
        case .summary: "waveform.path.ecg.text"
        case .workouts: "figure.mixed.cardio"
        case .settings: "slider.horizontal.3"
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .summary: "Summary"
        case .workouts: "Workouts"
        case .settings: "Settings"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .summary: BodyHomeView()
        case .workouts: BodyWorkoutsView()
        case .settings: BodySettingsView()
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: BodyMainTab = .summary
    @State private var summaryReselectCount = 0
    @State private var isFirstLaunchOverlayPresented = false
    @AppStorage(BodyAppearancePreference.onboardingCompletedVersionKey) private var onboardingCompletedVersion = ""
    @AppStorage(BodyAppearancePreference.updateOnboardingCompletedVersionKey) private var updateOnboardingCompletedVersion = ""

    /// Shown until onboarding has been completed on 1.0.0 or later
    /// (`BodyOnboardingGate`); pre-release installs recorded nothing, so they
    /// see it once after upgrading.
    private var showsOnboarding: Bool {
        BodyOnboardingGate.shouldPresent(completedVersion: onboardingCompletedVersion)
    }

    /// The cover is driven by the stored version rather than a transient
    /// `@State`, so dismissing it (only ever via `finish()`) records completion.
    private var isOnboardingPresented: Binding<Bool> {
        Binding {
            showsOnboarding
        } set: { isPresented in
            if !isPresented {
                onboardingCompletedVersion = BodyOnboardingGate.currentAppVersion()
                // A fresh install has nothing to rebuild, so first-run
                // completion also settles the update page.
                updateOnboardingCompletedVersion = BodyOnboardingGate.currentAppVersionAndBuild()
            }
        }
    }

    /// Shown once to installs that finished onboarding before 1.1.0 build 9,
    /// including earlier 1.1.0 builds; fresh installs stamp the running
    /// version and build at first run, so they never see it
    /// (`BodyOnboardingGate`).
    private var showsUpdateOnboarding: Bool {
        BodyOnboardingGate.shouldPresentUpdate(
            completedVersion: onboardingCompletedVersion,
            updateCompletedVersion: updateOnboardingCompletedVersion
        )
    }

    /// Same shape as `isOnboardingPresented`: dismissing the cover records the
    /// running version, so the page is one-shot.
    private var isUpdateOnboardingPresented: Binding<Bool> {
        Binding {
            showsUpdateOnboarding
        } set: { isPresented in
            if !isPresented {
                updateOnboardingCompletedVersion = BodyOnboardingGate.currentAppVersionAndBuild()
            }
        }
    }

    /// Wraps the tab selection so re-tapping the already-active Summary tab bumps
    /// `summaryReselectCount`. Both the native tab bar and the custom pill bar route
    /// selection through this; the selection itself still updates normally.
    private var tabSelection: Binding<BodyMainTab> {
        Binding {
            selectedTab
        } set: { newValue in
            if newValue == .summary && selectedTab == .summary {
                summaryReselectCount += 1
            }
            selectedTab = newValue
        }
    }

    var body: some View {
        content
            .environment(\.summaryReselectCount, summaryReselectCount)
            .accessibilityHidden(isFirstLaunchOverlayPresented || showsOnboarding || showsUpdateOnboarding)
            .overlay(alignment: .top) {
                BodyHealthSyncBadge(isSuppressed: isFirstLaunchOverlayPresented || showsOnboarding || showsUpdateOnboarding)
            }
            .overlay {
                BodyFirstLaunchLoadOverlay(onPresentationChange: { isFirstLaunchOverlayPresented = $0 })
            }
            .fullScreenCover(isPresented: isOnboardingPresented) {
                BodyOnboardingView(mode: .firstRun)
            }
            .fullScreenCover(isPresented: isUpdateOnboardingPresented) {
                BodyCacheRebuildView(entry: .update)
            }
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ already renders TabView as the native Liquid Glass pill
            // bar, so leave it untouched and only style the icons.
            TabView(selection: tabSelection) {
                ForEach(BodyMainTab.allCases, id: \.self) { tab in
                    tab.destination
                        .tabItem {
                            Image(systemName: tab.systemImage)
                                .accessibilityLabel(tab.accessibilityLabel)
                        }
                        .tag(tab)
                }
            }
        } else {
            // iOS 18: hide the legacy tab bar and float a custom pill bar that
            // imitates the iOS 26 look.
            TabView(selection: tabSelection) {
                ForEach(BodyMainTab.allCases, id: \.self) { tab in
                    tab.destination
                        .tag(tab)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 64)
            }
            .overlay(alignment: .bottom) {
                BodyPillTabBar(selection: tabSelection)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(HealthKitWorkoutStore())
}

private struct SummaryReselectCountKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Increments each time the already-selected Summary tab is tapped again, so views in
    /// the Summary tab can mirror the system's tap-to-pop-to-root — e.g. dismiss an overlay
    /// that lives outside the navigation stack.
    var summaryReselectCount: Int {
        get { self[SummaryReselectCountKey.self] }
        set { self[SummaryReselectCountKey.self] = newValue }
    }
}
