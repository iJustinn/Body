//
//  BodyWatchApp.swift
//  BodyWatch
//

import HealthKit
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
            // to the foreground, so re-check live HR/HRV staleness here too.
            if phase == .active {
                Task { await model.refreshLiveMetricsIfStale() }
            }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated {
            WatchMetricsModel.shared.activate()
        }
        disableLegacyStandaloneBackgroundDelivery()
    }

    /// One-time cleanup for installs upgraded from a build that ran standalone
    /// compute: that feature enabled HealthKit background delivery for its
    /// observers (now removed). Disable any lingering registrations so watchOS
    /// stops waking the app for samples nothing consumes anymore.
    private func disableLegacyStandaloneBackgroundDelivery() {
        let key = "didDisableStandaloneBackgroundDelivery"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        HKHealthStore().disableAllBackgroundDelivery { success, _ in
            // Latch only on success so a failed first attempt retries on the next
            // launch instead of leaving legacy registrations active forever.
            guard success else { return }
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    /// Holds WatchConnectivity background-refresh tasks open until the session
    /// delivers the pushed content (see `handleConnectivityBackgroundTask`);
    /// other task kinds are completed immediately — the app doesn't use them.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let wcTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                // Hold open until WCSession delivers the pushed context/userInfo;
                // completing now would let watchOS suspend before the delegate
                // drains it, dropping background phone updates.
                Task { @MainActor in
                    WatchMetricsModel.shared.handleConnectivityBackgroundTask(wcTask)
                }
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
