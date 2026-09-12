# Responsive refresh and deferred repair

Date: 2026-09-12  
Status: **Revision 2 approved; Phase A implemented and exercised on both phones. User authorized committing all changes. Phase B remains outstanding.**

The original appended review is preserved below. The revised design and stages are authoritative; [review verification](04-review-verification.md) records accepted findings and corrections against code and Apple documentation.

## Intended experience

Opening the app shows saved data immediately. Refresh prioritizes the current dashboard and finishes without waiting for the historical repair queue. Historical corrections continue in small, resumable pieces during iOS background opportunities and quietly while the app is open. A new user refresh takes priority over maintenance.

“Quietly while open” is part of this proposal: repair may execute while the app is foregrounded, but does not own the visible refresh badge, block refresh gestures, or hold the foreground refresh behind a long HealthKit query. Background-only execution cannot guarantee timely correction because iOS chooses when to run tasks and a locked device may prevent HealthKit reads.

## Approved decisions

| Area | Proposed behavior |
| --- | --- |
| App opening | Show cache; run one current-dashboard refresh when needed; do not await historical repair first. |
| Historical repair | One retained maintenance owner; start with existing full-scope metric reads and existing per-domain durable receipts. Smaller date chunks require measured justification. |
| While app is open | Start maintenance after the initial refresh settles; yield immediately to a user refresh or context change. |
| While app is backgrounded | Reuse the existing data-refresh task and lease; preserve notification ordering and use remaining time for proven historical coverage. This remains part of the goal. |
| Displayed values | Keep last available values during repair. Recompute affected scores after their required inputs are repaired. Do not stamp unfinished history as fully validated. |
| Pull to refresh | Prioritize the requested screen/data. Do not drain unrelated historical obligations before completing the gesture. |
| Scope | Metric observer repair and the shared scheduling/publication changes necessary for it. Keep workout, record, and stress history owners; integrate with them rather than duplicate them. |
| Deployment | Initially iPhonePro; the user subsequently authorized switching to iPhoneAir for timing validation. Preserve data and settings on both. |

## Read in this order

1. [Design and correctness](01-design.md): current causes, ownership, query coverage, resumable history, and freshness.
2. [Implementation stages](02-implementation.md): ordered changes, affected files, and release gates.
3. [Validation](03-validation.md): deterministic tests, performance criteria, and iPhonePro scenarios.
4. [Review verification](04-review-verification.md): R1–R10 decisions, supporting evidence, and limits of the suggested Phase A.

## What this can and cannot promise

The acceptance target is **zero waiting for historical repair on the foreground refresh path**, including when an old repair query is slow or never returns. Merely hiding the badge does not satisfy the target.

This does not promise a fixed refresh time, instant fresh data, or a deadline by which iOS will complete background work. Current HealthKit queries, authorization, cold loading, and legitimate user-requested history can still take time. History and dependent scores may temporarily reflect the previously saved data. The design explicitly retains pending work until coverage and persistence are proven.

Phase A moves repair and notification waits out of activation, reuses successful foreground coverage, and provides preemptible quiet work using the existing query pools. Phase B completes historical coverage during background opportunities. Together they deliver the approved direction. Phase C (narrow current-only fetches or sub-domain checkpoints) is conditional on per-domain timing, query-count, and persistence evidence. It is no longer a prerequisite for responsiveness.

Domain-level progress is already resumable: each fully repaired receipt is saved; interruption retries only still-pending domains under the current generation. The plan no longer prescribes calendar-month and seven-day splits for all metrics. Existing stress/workout progress owners keep their specialized units. Removing the old awaited route still requires coverage and ownership tests, not just moving the call into a Task.

## Baseline

Based on the September 12 working tree at HEAD `31bec82`, including the uncommitted periodic-background revalidation fix and its six regression tests. Other local UI/documentation work is outside this plan. Earlier investigation and measurements remain in [ObserverRefreshValidation.md](../../ObserverRefreshValidation.md); this plan supersedes earlier deferred scheduling proposals only for the scope described here.

The latest corrected build launched on iPhonePro with an 11.655-second activation. The earlier affected sequence lasted approximately 129.1 seconds across several operations, including 63.696 and 34.290-second observed passes. These workloads differ; they are evidence of the problem, not a measured speedup for this proposed design.

## Platform references

- [Apple: choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) — the system chooses background execution opportunities.
- [Apple: protecting HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy) — locked-device protection can prevent background reads.

Implementation evidence and remaining gates are tracked in [05-implementation-evidence.md](05-implementation-evidence.md). The appended review below remains unchanged.

---

## Adversarial review (2026-09-12, Claude)

Reviewed against the working tree: `BodyHealthChangeCoordinator.swift`, `BodyHealthDirtyWorkStore.swift`, and the activation, refresh-slot, `repairObservedMetrics`, `performObservedMetrics`, and notification paths in `HealthKitWorkoutStore.swift`. The stated purpose is: show cache and prioritize today's metrics on open; repair history in small resumable chunks during background opportunities; allow quiet repair while the app is open without holding the badge or delaying interaction.

### Verdict

The diagnosis in 01-design §1 is accurate. The proposed solution is much larger than the purpose requires, and parts of it would likely make the app do more HealthKit work, not less. Recommend splitting into a small Phase A that delivers all three goals with existing machinery, measuring, and only then deciding whether Stages 3 and 4 are justified.

### R1. The plan redefines "history" into work that does not exist today

In the current code the `historyPending` flag does not correspond to any separate historical scan. `performObservedMetrics` acknowledges `current: true, history: lease == nil` after one ordinary full-scope descriptor read (`fetchHealthDashboardSnapshot(for:)`, which already returns today's summary, the retained daily series, comparison data, and the retained intraday window). So "history repaired" today means "the normal dashboard read for that metric ran in the foreground". Background passes deliberately leave history pending only because they skip the derived recompute and publication.

Stages 3 and 4 replace that single read with (a) a new narrower current-only query contract and (b) a new per-domain chunked scan in calendar-month daily units and 7-day intraday units, each with its own durable checkpoint. For most quantity metrics a statistics-collection query over the whole retained window is one HealthKit round trip; chunking it into months multiplies queries, snapshot persists, and checkpoint writes. The 63.7s and 34.3s passes in the validation doc were slow because 18 full-scope leaves plus source preparation ran serially-ish under a 3-wide batch on the activation path while the user waited, not because the reads were individually wrong. Moving that same work off the awaited path solves the user-visible problem without changing what is read.

Ask: before approving Stages 3 and 4, Stage 1 must produce a per-domain cost split (current-only portion versus retained-history portion of each leaf). If the current-only portion is not materially cheaper for a domain, that domain should keep its single full-scope read and Stages 3 and 4 should not apply to it.

### R2. The cheapest wins are buried in Stage 5 and §6

Two changes are independent of everything else and address the purpose directly:

1. `syncWhenAppBecomesActive` awaits `repairOnActivation()` before it even checks `needsContextRefresh`, `needsInitialHealthDataLoad`, or the freshness gates. Stop awaiting it. Decide the current refresh from freshness plus `currentPending`, then hand repair to a retained task after the refresh settles.
2. `repairOnActivation` awaits `evaluateNewNotifications()` with a 20s deadline before the activation decision completes. That is up to 20s of potential activation delay unrelated to any data the user sees. Move it behind the current refresh into its own retained task now.

Both should be Phase A, with tests, before any ledger or engine work.

### R3. "One current pass rather than observed plus duplicate full pass" is the real double-fetch today

After `repairOnActivation` runs full-scope reads for every pending domain and sets `isRefreshing`, `observedRepairDidSettle(pending:)` leaves `observedHealthChanges` true whenever anything remains, and `syncWhenAppBecomesActive` then bypasses both freshness gates and runs `requestAuthorizationAndRefresh` as well. Even with nothing pending, `invalidateObservedHealthChanges()` is set on every delivery in `capture`, so under frequent Watch deliveries every activation does a full refresh. The plan's fix (per-domain current invalidation instead of a global Boolean) is correct and belongs in Phase A. Note also that the README's good-case measurement (11.655s activation) is 9.614s of ordinary refresh. Eliminating repair waiting alone will not make opening feel fast; the plan should say so.

### R4. Conservative generation invalidation guarantees starvation for Watch-driven domains

§4 says a new observer generation invalidates that domain's old history progress "conservatively" because a callback carries no dates. Heart rate, HRV, and energy deliveries arrive every few minutes while a Watch syncs. Under the proposed rule those domains' chunked history would restart on nearly every delivery and never finish while the app is in use. The plan defers "dated/anchored invalidation" to a future design and says to stop rollout if starvation appears. Starvation is predictable from the delivery pattern already captured in the validation doc, so the deferral makes Stage 4 unshippable for exactly the domains that matter.

Options, in order of preference: keep the single full-scope read per domain (R1) so there is no multi-unit progress to invalidate; or scope re-validation after a new generation to a recent window (for example the last 7 to 14 days) rather than the whole retained range; or adopt `HKAnchoredObjectQuery` anchors per type so changed sample dates are known and invalidation is exact. Pick one before Stage 4, not after.

### R5. Query-pool cancellation versus the "no extra concurrency" exit criterion

§2 requires that cancelling a maintenance query "release any logical admission capacity needed by foreground work". Stage 2's exit requires "no extra query concurrency beyond the defined pool budget". A one-shot `HKSampleQuery` or statistics query cannot be interrupted by Swift task cancellation; `HKHealthStore.stop(_:)` exists but its effect on in-flight one-shot queries is not guaranteed. Releasing the permit early means real concurrency exceeds the budget; not releasing it means a foreground pull waits on the slow query the plan promises it never waits on. The plan must choose explicitly: accept transient over-budget with a hard cap, or call `stop` and treat the permit as released on callback. Check the existing pool implementation before Stage 2, since I did not verify whether it has any cancellation path.

### R6. Foreground maintenance admission will starve behind existing owners

`awaitRefreshSlotFree(background: true)` returns false whenever any of `workoutJournalTask`, `recordBackfillTask`, `pendingStressInputLoadTask`, or `stressBackfillTask` is non-nil. Stress backfill chains itself behind record and input loads for long periods. If quiet foreground maintenance reuses that rule it will rarely be admitted; if it does not, it competes with those owners for the same HealthKit pool. §5 says "bounded fairness" but gives no rule. Specify the actual admission predicate and priority order for the quiet owner relative to the three existing backfill owners. Also note `finishRefresh()` is what kicks record and stress backfill today; if maintenance completion no longer goes through `finishRefresh`, something else must offer them work.

### R7. "Authoritative empty interval deletes cached points" is unsafe with HealthKit read privacy

HealthKit returns an empty result, not an error, when read authorization is denied or was revoked for a type. §4 proposes that a successful empty interval removes cached points inside that interval. Without a reliable way to distinguish "no data" from "not authorized" (HealthKit does not expose read authorization status), a user who toggles a permission off in Health could have retained chart history wiped. Require an independent authorization or source-discovery signal before treating empty as authoritative, or restrict deletion to intervals where the query also returned neighboring data.

### R8. Checkpoint and persistence write amplification

Every `acknowledge` rewrites the whole ledger JSON atomically and reads the file first to compare. Every leaf today already persists the full dashboard snapshot. Month-unit history across 18 domains with payload-before-checkpoint ordering means on the order of hundreds of full-snapshot writes plus hundreds of ledger writes for one backlog drain. Batch several completed units per persist and checkpoint, or persist per domain rather than per unit, and measure disk time in Stage 1.

### R9. Ledger schema and rollback

`BodyHealthDirtyWorkStore.init` accepts only schema 1 or 2. If progress is added by bumping to schema 3, a rollback build rejects the file entirely and conservatively marks all 18 domains current and history pending, then rewrites it as schema 2, so a later upgrade finds no progress. That matches "safely restart" but is a full re-repair on rollback. Prefer keeping schema 2 and adding an optional `progress` field: old decoders ignore unknown keys, pending flags survive, and only the cursor is lost.

### R10. Smaller issues

- Pull-to-refresh uses `.userInitiated` and a full-scope read. Under the new coverage rules it should acknowledge history coverage for the metrics it actually re-read, or the quiet owner will redundantly repeat that work.
- The first-launch `needsInitialHealthDataLoad` path and its overlay are not mentioned anywhere in the plan. State whether maintenance is admitted before the initial load completes.
- The "18 domains" fixture and the zero-query stress exit (stress leaf returning false in 0.004s with no queries) are the only two scenarios grounded in captured evidence. The stress case is an existing bug independent of this plan and should be fixed and verified on its own.
- 03-validation lists 25 scenarios before any code exists. Most depend on APIs Stage 3 and 4 would invent. Trim the validation plan to Phase A and re-derive the rest if Stages 3 and 4 survive R1.

### Recommended Phase A (delivers the stated purpose)

1. Do not await `repairOnActivation` in `syncWhenAppBecomesActive`. Gate the current refresh on freshness plus per-domain `currentPending` instead of the global `observedHealthChanges`.
2. Run the existing `repairObservedMetrics` (unchanged full-scope reads) from one retained, cancellable task after `finishRefresh`, without setting `isRefreshing`, fenced by the existing `dashboardPublicationToken` and `mayApplyRefreshResults` checks. Cancel it on any user refresh, context change, cache clear, or background entry.
3. Move `evaluateNewNotifications` into its own retained task behind the current refresh.
4. Keep the BGTask route as is; it already processes current work first and leaves history for the foreground.
5. Measure on iPhonePro: activation duration, visible refresh duration, time to first current publication, and quiet drain time. Then decide on Stages 3 and 4 domain by domain per R1.
