//
//  MainTabView.swift
//  Body
//

import SwiftUI
import UIKit

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
                    boldTabIcon("waveform.path.ecg.text")
                        .accessibilityLabel("Summary")
                }
                .tag(BodyMainTab.summary)

            BodyWorkoutsView()
                .tabItem {
                    boldTabIcon("figure.mixed.cardio")
                        .accessibilityLabel("Workouts")
                }
                .tag(BodyMainTab.workouts)

            BodySettingsView()
                .tabItem {
                    boldTabIcon("slider.horizontal.3")
                        .accessibilityLabel("Settings")
                }
                .tag(BodyMainTab.settings)
        }
        .overlay {
            BodyFirstLaunchLoadOverlay()
        }
    }

    /// Tab bar icons ignore SwiftUI font-weight modifiers, so bake the bold
    /// weight into the symbol image itself.
    private func boldTabIcon(_ systemName: String) -> Image {
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        if let image = UIImage(systemName: systemName, withConfiguration: configuration) {
            return Image(uiImage: image)
        }
        return Image(systemName: systemName)
    }
}

#Preview {
    MainTabView()
        .environmentObject(HealthKitWorkoutStore())
}
