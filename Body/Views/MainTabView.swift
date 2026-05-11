//
//  MainTabView.swift
//  Body
//

import SwiftUI

private enum BodyMainTab: Hashable {
    case home
    case charts
    case settings
}

struct MainTabView: View {
    @State private var selectedTab: BodyMainTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            BodyHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(BodyMainTab.home)

            BodyChartsView()
                .tabItem {
                    Label("Charts", systemImage: "chart.bar.fill")
                }
                .tag(BodyMainTab.charts)

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
