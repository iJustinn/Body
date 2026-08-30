//
//  BodyBackgroundRefreshScheduler.swift
//  Body
//

import BackgroundTasks
import Foundation
import os

/// Owns the BGAppRefresh task that evaluates metric threshold warnings while the
/// app isn't on screen.
///
/// Call sites:
/// - `registerTask()` once, from `BodyApp.init()` (registration must happen
///   before the app finishes launching).
/// - `schedule()` on every foreground activation, and whenever the master
///   warning-notifications toggle is turned ON.
/// - `cancelPending()` when that toggle is turned OFF.
enum BodyBackgroundRefreshScheduler {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    static let taskIdentifier = "com.zihengthedeveloper.Body.warningRefresh"

    /// The earliest the system may run the task. A floor, not a promise — iOS
    /// schedules on its own budget.
    static let refreshInterval: TimeInterval = 30 * 60

    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "BackgroundRefresh")

    /// Reads the app's foreground state for the evaluator's skip gate.
    /// `nonisolated(unsafe)` + MainActor writes only: a stale read is harmless
    /// (the evaluator either skips a pass it could have run, or runs one the
    /// foreground refresh will redo).
    nonisolated(unsafe) private static var isForegroundActive = false

    /// Read by `MetricWarningBackgroundEvaluator.shared`'s skip gate.
    static var isAppForegroundActive: Bool {
        isForegroundActive
    }

    @MainActor
    static func setForegroundActive(_ isActive: Bool) {
        isForegroundActive = isActive
    }

    static func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task)
        }
    }

    static func schedule() {
        guard UserDefaults.standard.bool(forKey: BodyAppearancePreference.metricWarningNotificationsKey) else {
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator, an over-budget app, or Background App Refresh turned
            // off system-wide. Nothing to recover: the next activation retries.
            logger.debug("Background refresh submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func cancelPending() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func handle(_ task: BGTask) {
        // Re-arm first: the system only holds one pending request per
        // identifier, and an early return below would otherwise end the chain.
        schedule()

        let completion = TaskCompletion(task)
        let work = Task {
            let outcome = await MetricWarningBackgroundEvaluator.shared.evaluate()
            switch outcome {
            case .success, .skipped:
                completion.complete(success: true)
            case .partialFailure, .failure:
                completion.complete(success: false)
            }
        }

        // Installed before any work starts, so an immediate expiration still
        // stops the evaluation.
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }

    /// One-shot owner of `setTaskCompleted(success:)`: calling it twice (work
    /// finishing as the expiration handler fires) is a crash.
    private final class TaskCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var task: BGTask?

        init(_ task: BGTask) {
            self.task = task
        }

        func complete(success: Bool) {
            lock.lock()
            let pending = task
            task = nil
            lock.unlock()
            pending?.setTaskCompleted(success: success)
        }
    }
}
