//
//  BodyPerformanceSignposts.swift
//  Body
//

import Foundation
import os

/// Shared signposter for the performance-critical paths tuned in 0.9.2.
/// Inspect intervals in Instruments (os_signpost) under subsystem
/// com.zihengthedeveloper.Body, category "Performance".
enum BodyPerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: "com.zihengthedeveloper.Body",
        category: "Performance"
    )
}

#if DEBUG
/// Local observer diagnostics only. Never log scope strings, health values,
/// source identities, or workout/sample identifiers.
enum BodyObserverRefreshDiagnostics {
    @TaskLocal static var passID: String?
    private static let logger = Logger(subsystem: "com.zihengthedeveloper.Body", category: "Performance")

    static func log(_ event: String, passID localPassID: String? = nil) {
        logger.notice("ObserverRefresh pass=\(localPassID ?? passID ?? "none", privacy: .public) \(event, privacy: .public)")
    }

    static func elapsed(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: .now).components
        return String(format: "%.3fs", Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }

    static func pending(_ envelope: BodyHealthDirtyWorkStore.Envelope) -> String {
        envelope.entries.sorted { $0.key < $1.key }.compactMap { kind, entry in
            guard entry.currentPending || entry.historyPending else { return nil }
            return "\(kind):g\(entry.generation):c\(entry.currentPending ? 1 : 0)h\(entry.historyPending ? 1 : 0)\(entry.deferredAt == nil ? "" : "d")"
        }.joined(separator: ",")
    }

    static func contextDifference(from previous: String?, to next: String) -> String {
        guard previous != next else { return "unchanged" }
        if let nextObserver = BodyHealthObserverContext(signature: next) {
            let oldObserver = previous.flatMap { BodyHealthObserverContext(signature: $0) }
                ?? HealthDashboardCacheScope(signature: previous).map { BodyHealthObserverContext(scope: $0) }
            guard let oldObserver else { return "unknown" }
            var dimensions: [String] = []
            if oldObserver.primary != nextObserver.primary { dimensions.append("primary") }
            if oldObserver.secondary != nextObserver.secondary { dimensions.append("secondary") }
            if oldObserver.aggregation != nextObserver.aggregation { dimensions.append("aggregation") }
            return dimensions.isEmpty ? "representationOnly" : dimensions.joined(separator: ",")
        }
        guard let old = HealthDashboardCacheScope(signature: previous),
              let new = HealthDashboardCacheScope(signature: next) else { return "unknown" }
        var dimensions: [String] = []
        if old.primary != new.primary { dimensions.append("primary") }
        if old.secondary != new.secondary { dimensions.append("secondary") }
        if old.aggregation != new.aggregation { dimensions.append("aggregation") }
        if old.summaryDayStart != new.summaryDayStart { dimensions.append("day") }
        if old.sleepGoal != new.sleepGoal || old.computeVersion != new.computeVersion { dimensions.append("compute") }
        return dimensions.joined(separator: ",")
    }
}
#endif

/// Refresh-scoped measurement sink behind the per-leaf timings that the signpost
/// intervals above only expose through Instruments. Accumulates one duration per
/// dashboard fetch leaf plus the HealthKit concurrency high-water mark, and dumps
/// a sorted table to the unified log at the end of each refresh, so a run on a
/// real device can be read in Console without a trace.
///
/// Measurement only: nothing here feeds a fetch decision. Every mutation is
/// compiled out of release builds, so the release cost is an empty call.
///
/// Read the table in Console (or `log stream`) under subsystem
/// `com.zihengthedeveloper.Body`, category `Performance`.
final class BodyRefreshProfile: Sendable {
    static let shared = BodyRefreshProfile()

    private struct State {
        var startedAt: DispatchTime?
        var leafDurations: [String: TimeInterval] = [:]
        var leafCounts: [String: Int] = [:]
        var effortCandidates = 0
        var queryDepth = 0
        var peakQueryDepth = 0
        var peakPoolDepth: [String: Int] = [:]
        var queryStarts: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "Performance"
    )

    /// Clears the table and starts the wall clock. Called at the top of a
    /// full refresh or foreground observed pass. Never reset per observed leaf.
    func beginRefresh() {
        #if DEBUG
        state.withLock { state in
            state = State(startedAt: .now(), queryStarts: state.queryStarts)
        }
        #endif
    }

    /// Adds one leaf sample. Leaves with the same name (e.g. a metric fetched by
    /// more than one orchestrator pass) accumulate their durations.
    func recordLeaf(_ name: String, duration: TimeInterval) {
        #if DEBUG
        state.withLock { state in
            state.leafDurations[name, default: 0] += duration
            state.leafCounts[name, default: 0] += 1
        }
        #endif
    }

    /// Number of workouts the per-workout effort fan-out actually queried this
    /// refresh, i.e. the ones the process cache could not answer.
    func addEffortCandidates(_ count: Int) {
        #if DEBUG
        state.withLock { state in
            state.effortCandidates += count
        }
        #endif
    }

    /// Called from HealthKit query paths, including HealthKit's own callback
    /// queues, hence the lock rather than actor isolation.
    func enterQuery() {
        #if DEBUG
        state.withLock { state in
            state.queryDepth += 1
            state.queryStarts &+= 1
            state.peakQueryDepth = max(state.peakQueryDepth, state.queryDepth)
        }
        #endif
    }

    #if DEBUG
    /// Process-wide actual query starts through enterQuery, including concurrent
    /// or abandoned work. Deltas supplement local timings, not receipt coverage.
    var queryStarts: UInt64 { state.withLock { $0.queryStarts } }
    #endif

    func exitQuery() {
        #if DEBUG
        state.withLock { state in
            state.queryDepth -= 1
        }
        #endif
    }

    /// High-water mark of one of the two `HealthKitQuerySemaphore` budgets, so
    /// the dump shows whether a pool actually saturated (and therefore whether
    /// its ceiling is the thing to tune).
    func notePoolDepth(_ pool: String, depth: Int) {
        #if DEBUG
        state.withLock { state in
            state.peakPoolDepth[pool] = max(state.peakPoolDepth[pool] ?? 0, depth)
        }
        #endif
    }

    /// Logs the accumulated table, newest measurements only: the state is reset
    /// so the next refresh starts clean even if it never calls `beginRefresh()`.
    func dumpAndReset() {
        #if DEBUG
        let snapshot = state.withLock { state -> State in
            let current = state
            state = State(queryStarts: state.queryStarts)
            return current
        }
        guard !snapshot.leafDurations.isEmpty else {
            return
        }

        let total = snapshot.startedAt.map { started in
            Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000_000
        }
        let totalText = total.map { String(format: "%.3fs", $0) } ?? "n/a"
        let poolText = snapshot.peakPoolDepth
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        Self.logger.notice(
            """
            RefreshProfile total=\(totalText, privacy: .public) \
            leaves=\(snapshot.leafDurations.count, privacy: .public) \
            peakHKQueries=\(snapshot.peakQueryDepth, privacy: .public) \
            peakPools=[\(poolText, privacy: .public)] \
            effortCandidates=\(snapshot.effortCandidates, privacy: .public)
            """
        )
        for (name, duration) in snapshot.leafDurations.sorted(by: { $0.value > $1.value }) {
            let line = String(
                format: "  %8.3fs  x%d  %@",
                duration,
                snapshot.leafCounts[name] ?? 1,
                name
            )
            Self.logger.notice("RefreshProfile \(line, privacy: .public)")
        }
        #endif
    }
}
