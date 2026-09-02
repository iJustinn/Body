//
//  WatchComputeCoordinator.swift
//  BodyWatch
//
//  Runs one on-watch metric compute end to end: phone seed + short HealthKit
//  delta (`WatchDeltaFetcher`) → spliced trends → summary overlay → Training
//  Load replay → permission filter → readiness recompute → the same
//  `WatchMetricsSnapshotBuilder` the phone uses. Everything between the fetch
//  and the builder is shared `BodyMetricsKit`/`BodyWatchSnapshotKit` code, so a
//  metric computed here and the same metric computed on the phone come out of
//  the identical implementation.
//
//  An actor with in-flight coalescing: `onAppear`, scene-active and the manual
//  refresh button can all fire within a second of each other, and a compute is
//  ~20 HealthKit round trips. A caller that arrives while one is running gets
//  that run's result; if the compute generation moved in the meantime the model
//  discards it (see `WatchComputeResult.generation`) and the next trigger
//  recomputes.
//

import Foundation

actor WatchComputeCoordinator {
    private let fetcher = WatchDeltaFetcher()
    private var inFlight: (generation: UInt64, task: Task<WatchComputeResult?, Never>)?

    /// `nil` when the watch must keep whatever the phone pushed: no stored seed,
    /// a seed whose data window is older than the watch's own HealthKit
    /// retention can bridge, or a compute that produced nothing usable.
    func recompute(
        permission: BodyHealthPermissionSelection,
        generation: UInt64,
        now: Date = Date()
    ) async -> WatchComputeResult? {
        // Coalesce ONLY onto a run of the same generation. A seed replacement /
        // permission change bumps the generation while a compute is running;
        // coalescing this caller onto that stale run would hand back a result
        // the model must discard — and with no rerun ever started for the NEW
        // generation, the replacement seed would sit uncomputed behind the
        // 30-minute rate limit. A mismatched in-flight run is awaited (to
        // serialize HealthKit fan-outs) and then a fresh run starts for the
        // caller's generation. Loop, not `if`: a third caller can install a
        // new run while this one awaits.
        while let current = self.inFlight {
            if current.generation == generation {
                return await current.task.value
            }
            _ = await current.task.value
            // The run's originating caller clears `inFlight` in its own
            // continuation, which may not have resumed yet — clear it here too
            // (guarded, idempotent) so this loop can't spin on a finished run.
            if self.inFlight?.task == current.task {
                self.inFlight = nil
            }
        }

        let task = Task { [fetcher] in
            await Self.compute(
                fetcher: fetcher,
                permission: permission,
                generation: generation,
                now: now
            )
        }
        inFlight = (generation, task)
        let result = await task.value
        // Guarded: another caller may have cleared this run and installed a
        // NEWER one while this continuation was waiting to resume — blindly
        // nil-ing would deregister that run and let a duplicate start.
        if self.inFlight?.task == task {
            self.inFlight = nil
        }
        return result
    }

    // MARK: - The compute

    private static func compute(
        fetcher: WatchDeltaFetcher,
        permission: BodyHealthPermissionSelection,
        generation: UInt64,
        now: Date
    ) async -> WatchComputeResult? {
        guard let seed = WatchComputeSeedStore.load() else { return nil }
        let calendar = Calendar.bodyGregorian
        let windowStart: Date
        switch WatchComputeAssembly.windowDecision(seed: seed, now: now, calendar: calendar) {
        case .tooOld, .futureDataThrough:
            return nil
        case .fetch(let start):
            windowStart = start
        }

        let delta = await fetcher.fetchDelta(
            seed: seed,
            permission: permission,
            windowStart: windowStart,
            now: now,
            calendar: calendar
        )

        return WatchComputeAssembly.assemble(
            seed: seed,
            delta: delta,
            permission: permission,
            generation: generation,
            windowStart: windowStart,
            now: now,
            calendar: calendar
        )
    }
}
