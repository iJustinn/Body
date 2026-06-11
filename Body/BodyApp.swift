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
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .bodyBaseInterfaceLevel()
                .environmentObject(workoutStore)
                .tint(selectedAccent.color)
                .accentColor(selectedAccent.color)
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

    private var selectedAccent: BodyAppAccent {
        BodyAppAccent.storedValue(from: selectedAccentRawValue)
    }
}
