//
//  WatchBackgroundScheduler.swift
//  BodyWatch
//
//  Schedules the periodic `WKApplicationRefreshBackgroundTask` that recomputes
//  metrics while the app is closed. One-shot per schedule; the task handler
//  reschedules the next one. Gated on the standalone-compute toggle.
//

import Foundation
import WatchKit
import os

enum WatchBackgroundScheduler {
    /// Matches the snapshot staleness cadence so the complication never lags
    /// the pushed/computed data by more than one interval.
    static let refreshInterval: TimeInterval = WatchMetricsSnapshot.staleInterval

    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "WatchBackground")

    static func scheduleNextRefreshIfEnabled(now: Date = Date()) {
        guard WatchStandaloneCompute.isEnabled(),
              WatchStandaloneCompute.hasSyncedPermissionSelection() else { return }
        let preferredDate = now.addingTimeInterval(refreshInterval)
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: preferredDate,
            userInfo: nil
        ) { error in
            if let error {
                logger.error("scheduleBackgroundRefresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
