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
            // to the foreground, so re-check staleness here too. Compute first,
            // then the live HR/HRV fallback — see `WatchMetricsModel.onAppear`.
            // Background triggers (the workout observer, a pushed context, the
            // hourly scheduled refresh) run the same staleness gated compute,
            // but never raise an authorization sheet (see
            // `WatchMetricsModel.recomputeIfStale`).
            if phase == .active {
                Task {
                    await model.recomputeIfStale()
                    await model.refreshLiveMetricsIfStale()
                }
            }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated {
            WatchMetricsModel.shared.activate()
            // Here rather than from the UI: watchOS can launch the app straight
            // into the background for a workout, and the observer has to be
            // executing again before that wake is delivered. It also owns the
            // one time legacy background delivery cleanup, so the two can't race.
            WatchMetricsModel.shared.startWorkoutObserver()
        }
    }

    /// Holds WatchConnectivity background-refresh tasks open until the session
    /// delivers the pushed content (see `handleConnectivityBackgroundTask`);
    /// an application refresh runs the background compute (see
    /// `handleApplicationRefreshBackgroundTask`); other task kinds are
    /// completed immediately — the app doesn't use them.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let wcTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                // Hold open until WCSession delivers the pushed context/userInfo;
                // completing now would let watchOS suspend before the delegate
                // drains it, dropping background phone updates.
                Task { @MainActor in
                    WatchMetricsModel.shared.handleConnectivityBackgroundTask(wcTask)
                }
            } else if let refreshTask = task as? WKApplicationRefreshBackgroundTask {
                // The model's standing hourly wake, or an earlier retry for
                // pending workout work. The model completes the task, once,
                // after the compute or on expiration. `apply` reloads the
                // complication timelines itself, so no snapshot is requested.
                Task { @MainActor in
                    WatchMetricsModel.shared.handleApplicationRefreshBackgroundTask(refreshTask)
                }
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
