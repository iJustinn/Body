//
//  MainTabView.swift
//  Body
//

import SwiftUI

private enum BodyMainTab: Hashable {
    case summary
    case workouts
    case settings
}

struct MainTabView: View {
    @State private var selectedTab: BodyMainTab = .summary

    var body: some View {
        TabView(selection: $selectedTab) {
            BodyHomeView()
                .tabItem {
                    Label("Summary", systemImage: "house.fill")
                }
                .tag(BodyMainTab.summary)

            BodyWorkoutsView()
                .tabItem {
                    Label("Workouts", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(BodyMainTab.workouts)

            BodySettingsView()
                .tabItem {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .tag(BodyMainTab.settings)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HealthKitWorkoutStore())
}
