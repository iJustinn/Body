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
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "Performance"
    )

    /// Clears the table and starts the wall clock. Called at the top of a
    /// full refresh; lighter refresh paths simply accumulate into whatever the
    /// last full refresh left behind and dump that.
    func beginRefresh() {
        #if DEBUG
        state.withLock { state in
            state = State(startedAt: .now())
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
            state.peakQueryDepth = max(state.peakQueryDepth, state.queryDepth)
        }
        #endif
    }

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
            state = State()
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
