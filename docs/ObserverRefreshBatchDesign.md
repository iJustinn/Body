# Bounded foreground observer reads

Date: 2026-09-12. Builds on [the captured 42.757-second resume](ObserverRefreshValidation.md).

The measured observer pass spent 38.673 seconds processing 18 receipts serially. The implemented change overlaps independent quantity reads, retaining the existing historical query windows and serial publication. This is a bounded first step; it does not reuse the subsequent ordinary refresh as proof that an observer receipt was covered.

## Execution

1. Keep the existing refresh slot, 120-second observed deadline, task-local publication fence, and captured receipt list.
2. Take up to three consecutive descriptor-backed quantity metrics from that list. Preserve order. Single metrics, sleep, training load, heartbeat repair, and background leases use their existing serial paths.
3. Discover the batch's source kinds before starting metric reads. Body measurements share Basics discovery. An unresolved/failed source excludes only dependent metrics. A changed context still invalidates the owner; no read or receipt is rebased onto new provenance mid-pass.
4. Capture one immutable existing snapshot plus the full dashboard scope, settings revision, engine query revision, calendar/date, and day-sample signatures. Run at most three existing `fetchHealthDashboardSnapshot(for:)` calls concurrently. The existing HealthKit query pool still controls leaf query concurrency.
5. After the batch reads finish, apply each result in receipt order through the same commit method used by serial metric pulls. Merge only that metric into current store state; never replace the whole dashboard with an earlier snapshot. Preserve query-success, current-input, full-scope, publication, protected-data, and day-sample checks.
6. Await each durable payload before acknowledging its original ledger receipt. A failed sibling remains pending; a newer delivery cannot be consumed by an older receipt. Complete the existing ring, derived-compute, and companion tail after the metrics.

At most three fetched snapshots are retained per batch. No concurrent calls to the store-mutating metric refresh method, detached prefetch owner, separate scheduler, source-change deferral, TTL acknowledgment, or reduced historical window is introduced. Waiting for a batch means a stalled read can delay its healthy siblings until the existing deadline; cancellation leaves all uncommitted receipts pending.

## Verification

Use gated fake HealthKit reads to establish actual overlap without timing assumptions: three requests enter while completions are held, the fourth does not enter, and pending flags stay set until release and commit. Cover successful empty reads and restart, failed-read siblings, shared-source discovery failure, newer delivery during reads, cancellation with late completions, and source A→B→A. Retain the earlier source-convergence and migration tests; preparation may now discover multiple sources before fencing all metric reads.

Run focused tests, the full Body suite, and the generic iOS Release gate. Then deploy to the same iPhonePro container and measure a natural broad callback burst. A fast launch with a clean ledger is not evidence that batching improved the slow case. Compare batch read/commit duration and final pending state, not just the visible badge.

Results: 22 focused tests passed, followed by the full Body suite with **2,449 passed, 0 failed, 3 skipped**. Release and signed DEBUG device builds passed. The first full run exposed one source guard still expecting the old inline signature capture; it now follows the captured context into the shared commit helper, passed in isolation, and passed in the final full run. No production change was needed for that failure.

The build is installed on iPhonePro, launch `c3bcb3480`, PID 3228. Its clean-ledger launch activation completed in 1.699s, with no observer pass. Saved smoke trace (local capture `ObserverRefreshBatchLaunch-20260912.txt`). Live logging remains attached; measurement of a comparable broad callback burst is still pending.
