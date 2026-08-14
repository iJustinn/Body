//
//  BodyApp.swift
//  Body
//

import SwiftUI

@main
struct BodyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workoutStore = HealthKitWorkoutStore()
    @State private var proStore: BodyProStore
    @AppStorage(BodyAppearancePreference.selectedThemeKey) private var selectedThemeRawValue = BodyAppTheme.defaultValue.rawValue

    init() {
        // Configure RevenueCat before constructing BodyProStore so the store's async
        // entitlement work always runs against a configured SDK.
        RevenueCatConfiguration.configure()
        _proStore = State(initialValue: BodyProStore())

        // Activate WatchConnectivity at startup so the session is ready and the
        // first snapshot push doesn't have to wait for activation.
        WatchConnectivityPublisher.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .bodyBaseInterfaceLevel()
                .environmentObject(workoutStore)
                .environment(proStore)
                .tint(.primary)
                .accentColor(.primary)
                .preferredColorScheme(selectedTheme.colorScheme)
                .task(priority: .utility) {
                    // The intraday day-sample sidecar is the only cached series not
                    // restored synchronously in the store's init, so the Day View
                    // charts would otherwise stay empty until a full refresh or a
                    // metric-detail visit hydrated it. Same task body as the sync
                    // below, not a second `.task` — sibling `.task` modifiers run
                    // concurrently, and the read has to win against any save the
                    // refresh triggers. Skipped on a true first launch: the
                    // day-sample fields count toward `needsInitialHealthDataLoad`,
                    // so hydrating a stranded sidecar there would suppress the load
                    // overlay and leave every passive load idled.
                    if !workoutStore.needsInitialHealthDataLoad {
                        await workoutStore.hydratePersistedDaySamplesIfNeeded()
                    }
                    await workoutStore.syncWhenAppBecomesActive()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else {
                        return
                    }

                    Task(priority: .utility) {
                        await workoutStore.syncWhenAppBecomesActive()
                        // RevenueCat doesn't push backend changes; re-resolve on foreground
                        // so refunds / other-device purchases update Pro and the widgets.
                        await proStore.refreshEntitlement()
                    }
                }
        }
    }

    private var selectedTheme: BodyAppTheme {
        BodyAppTheme.storedValue(from: selectedThemeRawValue)
    }
}
