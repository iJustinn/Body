//
//  BodyApp.swift
//  Body
//

import SwiftUI
import UIKit

@main
struct BodyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workoutStore = HealthKitWorkoutStore()
    @AppStorage(BodyAppearancePreference.selectedThemeKey) private var selectedThemeRawValue = BodyAppTheme.defaultValue.rawValue
    @AppStorage(BodyAppearancePreference.selectedAccentKey) private var selectedAccentRawValue = BodyAppAccent.defaultValue.rawValue

    init() {
        UIScrollView.appearance().showsVerticalScrollIndicator = false
        UIScrollView.appearance().showsHorizontalScrollIndicator = false
        WorkoutSnapshotStore.seedPreviewSnapshotIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(workoutStore)
                .tint(selectedAccent.color)
                .accentColor(selectedAccent.color)
                .preferredColorScheme(selectedTheme.colorScheme)
                .task {
                    await workoutStore.syncWhenAppBecomesActive()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else {
                        return
                    }

                    Task {
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
