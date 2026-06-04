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
                    Image(systemName: "waveform.path.ecg.text")
                        .accessibilityLabel("Summary")
                }
                .tag(BodyMainTab.summary)

            BodyWorkoutsView()
                .tabItem {
                    Image(systemName: "figure.mixed.cardio")
                        .accessibilityLabel("Workouts")
                }
                .tag(BodyMainTab.workouts)

            BodySettingsView()
                .tabItem {
                    Image(systemName: "slider.horizontal.3")
                        .accessibilityLabel("Settings")
                }
                .tag(BodyMainTab.settings)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HealthKitWorkoutStore())
}
