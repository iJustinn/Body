//
//  WatchPendingRecompute.swift
//  BodyWatchSnapshotKit
//
//  The watch's record that a workout CHANGED and readiness has not been
//  republished from it yet, plus the retry policy that drains that record.
//
//  Three things are deliberately kept apart, because collapsing them is how a
//  workout gets lost: DETECTING a change (`WatchWorkoutChangeTracker`'s
//  anchored query), ATTEMPTING a compute, and CONSUMING the change (a compute
//  whose queries ran after the detection, that published readiness, and whose
//  result reached disk). A run that merely started, that failed one readiness
//  input, that lost the generation race, or that was already in flight when the
//  workout was saved consumes nothing, and the work stays pending.
//
//  Lives in this shared folder, like `WatchComputeMerge`, so the rules are
//  covered from the iOS test bundle too. The watch model is the only caller.
//

import Foundation

struct WatchPendingReadinessWork: Codable, Equatable {
    /// When the oldest unconsumed change was detected. nil = nothing pending.
    var pendingSince: Date?
    /// Computes started on behalf of this work since the last detection.
    var attempts: Int = 0
    var lastAttempt: Date?
}

enum WatchPendingRecomputePolicy {
    /// Minimum spacing between two attempts for the same pending work.
    static let minimumSpacing: TimeInterval = 5 * 60
    /// Attempts a single detection may spend outside the ordinary 30 minute
    /// compute throttle. A compute is ~20 HealthKit round trips, and a readiness
    /// input that fails can fail all day (a source this watch cannot see), so
    /// the budget is what keeps pending work from becoming a standing poll.
    static let maximumAttempts = 6

    enum Decision: Equatable {
        /// Nothing pending.
        case idle
        /// Pending, and allowed to bypass the ordinary compute throttle now.
        case runNow
        /// Pending, but the last attempt was too recent.
        case retryAt(Date)
        /// Pending with the budget spent: no more bypasses. It is still
        /// consumed by whichever ordinary compute next succeeds.
        case exhausted
    }

    static func decision(_ work: WatchPendingReadinessWork, now: Date) -> Decision {
        guard work.pendingSince != nil else { return .idle }
        guard work.attempts < maximumAttempts else { return .exhausted }
        guard let lastAttempt = work.lastAttempt else { return .runNow }
        let elapsed = now.timeIntervalSince(lastAttempt)
        // A future-dated attempt (clock rollback) must not park the work.
        guard elapsed >= 0, elapsed < minimumSpacing else { return .runNow }
        return .retryAt(lastAttempt.addingTimeInterval(minimumSpacing))
    }

    /// A newly detected change. The budget and the spacing both restart: this
    /// is new information (a workout saved seconds after a compute started, an
    /// effort rating landing a minute later), and detections are real HealthKit
    /// writes, a handful a day. `pendingSince` moves to the NEWEST detection so
    /// an in-flight compute that predates it can't consume it.
    static func detecting(_ work: WatchPendingReadinessWork, at now: Date) -> WatchPendingReadinessWork {
        WatchPendingReadinessWork(pendingSince: now, attempts: 0, lastAttempt: nil)
    }

    static func attempting(_ work: WatchPendingReadinessWork, at now: Date) -> WatchPendingReadinessWork {
        guard work.pendingSince != nil else { return work }
        var next = work
        next.attempts += 1
        next.lastAttempt = now
        return next
    }

    /// Clears the work only for a compute that proves it saw the change:
    /// `coverage` (the instant its queries ran to) is not older than the
    /// detection, readiness was stamped (every eligible input succeeded), and
    /// the merged snapshot was persisted.
    static func consuming(
        _ work: WatchPendingReadinessWork,
        coverage: Date,
        publishedReadiness: Bool,
        persisted: Bool
    ) -> WatchPendingReadinessWork {
        guard let pendingSince = work.pendingSince,
              publishedReadiness, persisted, coverage >= pendingSince else {
            return work
        }
        return WatchPendingReadinessWork()
    }
}
