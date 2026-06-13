//
//  BodyWatchApp.swift
//  BodyWatch
//

import SwiftUI
import WatchKit

@main
struct BodyWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var model = WatchMetricsModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(model)
        }
        .onChange(of: scenePhase) { _, phase in
            // `onAppear` doesn't reliably re-fire when watchOS returns the app
            // to the foreground, so re-check staleness here too.
            guard phase == .active else { return }
            Task { await model.refreshLiveMetricsIfStale() }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated {
            WatchMetricsModel.shared.activate()
        }
    }
}
