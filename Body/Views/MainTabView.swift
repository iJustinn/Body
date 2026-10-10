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
    @Bindable private var notificationRoute = BodyAppRuntime.shared.notificationRoute
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthKitWorkoutStore.self) private var workoutStore
    @Environment(BodyProStore.self) private var proStore: BodyProStore?
    @State private var showsNotificationExplainer = false
    @State private var readinessHeroState = BodyReadinessHeroState()
    /// The hinge posture on a foldable iPhone, read once here for every tab.
    @State private var hingeState = BodyHingeState()

    private var selectedTab: BodyMainTab {
        get { notificationRoute.selectedTab }
        nonmutating set { notificationRoute.selectedTab = newValue }
    }
    @State private var summaryReselectCount = 0
    @State private var isFirstLaunchOverlayPresented = false
    @AppStorage(BodyAppearancePreference.navigationBarShowsLabelsKey) private var navigationBarShowsLabels = false
    @AppStorage(BodyAppearancePreference.onboardingCompletedVersionKey) private var onboardingCompletedVersion = ""
    @AppStorage(BodyAppearancePreference.updateOnboardingCompletedVersionKey) private var updateOnboardingCompletedVersion = ""
    @AppStorage(BodyAppearancePreference.proIntroPaywallShownVersionKey) private var proIntroPaywallShownVersion = ""
    @AppStorage(BodyAppearancePreference.proPaywallLastShownDateKey) private var proPaywallLastShownDate: Double = 0
    @State private var isProIntroPresented = false
    /// The page the update cover shows, kept once it has been due: stamping the
    /// completion on dismissal turns `dueUpdatePage` nil while the cover is
    /// still animating away, and the page must not swap underneath it.
    @State private var presentedUpdatePage: BodyOnboardingGate.UpdatePage?

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

    /// The update page due on this launch (`BodyOnboardingGate.dueUpdatePage`):
    /// the cache rebuild once for installs that finished onboarding before
    /// 1.1.0 build 9, including earlier 1.1.0 builds, otherwise the Stress
    /// update once for installs before 1.1.5 build 5 that show Stress. Fresh
    /// installs stamp the running version and build at first run, so they
    /// never see either.
    private var dueUpdatePage: BodyOnboardingGate.UpdatePage? {
        BodyOnboardingGate.dueUpdatePage(
            completedVersion: onboardingCompletedVersion,
            updateCompletedVersion: updateOnboardingCompletedVersion,
            includesStress: updateIncludesStress
        )
    }

    /// Who the Stress update is for: the Stress card on, by the rule the
    /// Stress input load itself uses, and Heart readable, without which there
    /// is nothing to load. Both are settled synchronously at launch.
    private var updateIncludesStress: Bool {
        BodyDashboardFetchSelection.load().includes(.stress) && workoutStore.permissionSelection.includes(.heart)
    }

    private var showsUpdateOnboarding: Bool {
        dueUpdatePage != nil
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

    /// Installs stamped below `BodyOnboardingGate.proIntroVersion` see the Body Pro paywall
    /// once, and every install sees it again at its first open (cold or warm launch) of the
    /// day two weeks after the app last showed it. Always after onboarding and the update
    /// page, and only once the entitlement has resolved so members who already own Pro are
    /// never shown it (`BodyOnboardingGate.shouldPresentProPaywall`). The first run ends on
    /// the paywall inside onboarding instead. Reread on every return to `.active`, which is
    /// what makes a warm launch on a due day show it.
    private var proIntroReady: Bool {
        scenePhase == .active
            && (proStore?.hasResolved ?? false)
            && BodyOnboardingGate.shouldPresentProPaywall(
                shownVersion: proIntroPaywallShownVersion,
                lastShownDate: proPaywallLastShownDate == 0 ? nil : Date(timeIntervalSinceReferenceDate: proPaywallLastShownDate),
                completedVersion: onboardingCompletedVersion,
                updateCompletedVersion: updateOnboardingCompletedVersion,
                includesStress: updateIncludesStress,
                now: Date()
            )
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

    private var notificationReady: Bool {
        scenePhase == .active && !showsOnboarding && !showsUpdateOnboarding && !isFirstLaunchOverlayPresented
            && !isProIntroPresented && !workoutStore.needsInitialHealthDataLoad && !workoutStore.isRefreshing
    }

    /// A tapped notification navigates as soon as the cached dashboard has data: the
    /// background pass that sent it already repaired and persisted that data, so the
    /// page opens on it while the launch refresh updates in place. Only an empty cache
    /// (first launch) still waits for the refresh to finish.
    private var notificationRouteReady: Bool {
        notificationReady || (scenePhase == .active && !showsOnboarding && !showsUpdateOnboarding
            && !isFirstLaunchOverlayPresented && workoutStore.hasHealthDataToShow)
    }

    var body: some View {
        content
            .task(id: notificationRouteReady) {
                notificationRoute.ready = notificationRouteReady
            }
            .task(id: notificationReady) {
                guard notificationReady else { return }
                if UserDefaults.standard.bool(forKey: BodyNotificationPreferences.onboardingPromptKey) {
                    showsNotificationExplainer = true
                } else if UserDefaults.standard.bool(forKey: BodyNotificationPreferences.automaticPromptKey) {
                    await BodyNotificationPermission.shared.request()
                    UserDefaults.standard.set(false, forKey: BodyNotificationPreferences.automaticPromptKey)
                }
            }
            .alert("notifications.permission.title", isPresented: $showsNotificationExplainer) {
                Button("notifications.permission.enable") {
                    UserDefaults.standard.set(false, forKey: BodyNotificationPreferences.onboardingPromptKey)
                    Task { await BodyNotificationPermission.shared.request() }
                }
                Button("notifications.permission.later", role: .cancel) {
                    UserDefaults.standard.set(false, forKey: BodyNotificationPreferences.onboardingPromptKey)
                }
            } message: { Text("notifications.permission.explainer") }
            .environment(\.summaryReselectCount, summaryReselectCount)
            .environment(\.selectedMainTab, selectedTab)
            .environment(readinessHeroState)
            .environment(hingeState)
            .background(BodyHingeReader(state: hingeState))
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
                switch presentedUpdatePage ?? dueUpdatePage {
                case .stressUpdate:
                    BodyCacheRebuildView(entry: .stressUpdate)
                case .cacheRebuild, nil:
                    BodyCacheRebuildView(entry: .update)
                }
            }
            // Decided once at launch, with the stamps and the Stress inputs all
            // read synchronously: a due page is kept for the cover, and an
            // install that has nothing to rescore settles the Stress page now,
            // so turning Stress on later never pops it.
            .onChange(of: dueUpdatePage, initial: true) { _, page in
                if let page {
                    presentedUpdatePage = page
                } else if BodyOnboardingGate.settlesStressUpdateSilently(
                    completedVersion: onboardingCompletedVersion,
                    updateCompletedVersion: updateOnboardingCompletedVersion,
                    includesStress: updateIncludesStress
                ) {
                    updateOnboardingCompletedVersion = BodyOnboardingGate.currentAppVersionAndBuild()
                }
            }
            .task(id: proIntroReady) {
                guard proIntroReady else { return }
                // Lets a cover that just closed (the update page) finish animating away.
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, proIntroReady else { return }
                // Recorded as soon as it is due, so it shows once even if the app is
                // closed on it; members who already own Pro just settle the stamps.
                proIntroPaywallShownVersion = BodyOnboardingGate.currentAppVersionAndBuild()
                proPaywallLastShownDate = Date().timeIntervalSinceReferenceDate
                if !(proStore?.isPro ?? false) {
                    isProIntroPresented = true
                }
            }
            .fullScreenCover(isPresented: $isProIntroPresented) {
                NavigationStack {
                    BodyProView(onContinue: { isProIntroPresented = false })
                }
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
                            if navigationBarShowsLabels {
                                Label(tab.accessibilityLabel, systemImage: tab.systemImage)
                            } else {
                                Image(systemName: tab.systemImage)
                                    .accessibilityLabel(tab.accessibilityLabel)
                            }
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
                Color.clear.frame(height: navigationBarShowsLabels ? 72 : 64)
            }
            .overlay(alignment: .bottom) {
                BodyPillTabBar(selection: tabSelection, showsLabels: navigationBarShowsLabels)
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
