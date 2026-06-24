//
//  BodyApp.swift
//  Body
//

import SwiftUI

@main
struct BodyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workoutStore = HealthKitWorkoutStore()
    @AppStorage(BodyAppearancePreference.selectedThemeKey) private var selectedThemeRawValue = BodyAppTheme.defaultValue.rawValue

    init() {
        // Activate WatchConnectivity at startup so the session is ready and the
        // first snapshot push doesn't have to wait for activation.
        WatchConnectivityPublisher.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .bodyBaseInterfaceLevel()
                .environmentObject(workoutStore)
                .tint(.primary)
                .accentColor(.primary)
                .preferredColorScheme(selectedTheme.colorScheme)
                .task(priority: .utility) {
                    await workoutStore.syncWhenAppBecomesActive()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else {
                        return
                    }

                    Task(priority: .utility) {
                        await workoutStore.syncWhenAppBecomesActive()
                    }
                }
        }
    }

    private var selectedTheme: BodyAppTheme {
        BodyAppTheme.storedValue(from: selectedThemeRawValue)
    }
}
