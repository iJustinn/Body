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

    var accessibilityLabel: String {
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

    var body: some View {
        content
            .overlay {
                BodyFirstLaunchLoadOverlay()
            }
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ already renders TabView as the native Liquid Glass pill
            // bar, so leave it untouched and only style the icons.
            TabView(selection: $selectedTab) {
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
            TabView(selection: $selectedTab) {
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
                BodyPillTabBar(selection: $selectedTab)
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HealthKitWorkoutStore())
}
