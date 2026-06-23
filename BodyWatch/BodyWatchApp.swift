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
            switch phase {
            case .active:
                Task {
                    await model.refreshLiveMetricsIfStale()
                    await model.recomputeStandalone()
                }
            case .background:
                WatchBackgroundScheduler.scheduleNextRefreshIfEnabled()
            default:
                break
            }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated {
            WatchMetricsModel.shared.activate()
        }
        // `startIfEnabled()` is async (it authorizes before registering), so it
        // can't run inside the synchronous `assumeIsolated` block.
        Task { @MainActor in
            await WatchHealthObserver.shared.startIfEnabled()
        }
        WatchBackgroundScheduler.scheduleNextRefreshIfEnabled()
    }

    /// Handles the scheduled background refresh: recompute standalone, reschedule
    /// the next refresh, then mark the task complete. Other task kinds are
    /// completed immediately — the app doesn't use them.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let refreshTask = task as? WKApplicationRefreshBackgroundTask {
                Task { @MainActor in
                    await WatchMetricsModel.shared.recomputeStandalone()
                    WatchBackgroundScheduler.scheduleNextRefreshIfEnabled()
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }
            } else if let wcTask = task as? WKWatchConnectivityRefreshBackgroundTask {
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
