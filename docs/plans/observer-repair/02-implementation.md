# Implementation stages — revision 2

Implementation is approved. Phases A and B are implemented; verification and remaining device checks are recorded in [05-implementation-evidence.md](05-implementation-evidence.md). User authorized bulk commit and push after verification. Phase C is conditional, not automatically authorized work.

## A0. Focused evidence and independent stress fix

Record per-domain source preparation, summary, daily/range history, comparison, intraday, compute, persistence, and query counts from existing instrumentation plus targeted leaf timing. Parallel timings are not additive. Identify current coverage already supplied by ordinary and manual refreshes. Do not demand a new current-only API merely to obtain a baseline; prototype narrower reads only when the existing timing supports them.

Reproduce the Pro/Air stress zero-query exit with a fake unresolved HRV source. Correct source preparation and verify it as a separate scoped fix, preserving acknowledgment guards. It is an existing bug, not evidence that a new historical scanning system is necessary.

**Gate:** a coverage/cost table for all admitted domains; clear distinction between measured timings and unmeasured hypotheses; focused stress test before declaring that domain repaired.

## A1. Ownership and early notification separation

Use the existing separate pools: quiet work uses background, visible work uses interactive, BGTask uses appRefresh. Add explicit quiet operation identity and foreground preemption, including context/cache/source setup and queued persistence. Keep logical permit accounting correct and avoid spawning replacement quiet tasks behind an uncooperative retired owner.

Move foreground notification evaluation to one retained coalesced task after current publication or a valid-cache decision. This can ship independently once late-send/cancellation and deduplication tests pass. Preserve the BGTask route.

Integrate admission hooks for existing journal/record/stress owners using the concrete rotation in the design. Remove the automatic journal repair's visible isRefreshing ownership when migrated; keep explicit user workout refresh visible. Unit completion re-offers maintenance without ordinary finishRefresh recursion.

**Main files:** coordinator/store; HealthKitQueryBudget.swift and BodyHealthQuerying.swift only where verified gaps require changes; BodyAppRuntime.swift; existing workout/record/stress admission hooks.

**Gate:** blocked quiet query cannot hold foreground task/permit admission or overwrite newer data; no automatic historical owner brings the visible badge back; fairness tests cover long retained task handles.

## A2. Switch activation using existing metric reads

Decide initial-load/context/freshness/current-pending needs before historical repair. Use one foreground plan: existing full refresh when stale, or affected metric/dependency fetches when otherwise fresh. Stop awaiting historical repair before that decision.

Attach receipt coverage to actual successful foreground/manual reads. Acknowledge only coverage durably obtained, including history if a full retained read was actually performed. Keep history-only backlog from bypassing current freshness gates. Schedule one retained quiet task after completion or skip.

Quiet observer repair reuses existing source preparation and full metric read shapes, one domain at a time initially. Keep schema 2 and domain-level durable completion. Existing three-read batching remains available to explicit foreground repair callers where applicable; do not silently retain that concurrency in quiet work.

**Main files:** coordinator/store; engine fetch result aggregation for minimal per-domain coverage evidence; observer, timeout, durability, and manual-refresh tests.

**Gate:** clean/history-only opening does not await repair; current changes are not lost; ordinary-plus-observed duplicate reads are avoided where coverage proves reuse. Do not claim all ordinary history fetches have disappeared.

## A3. Measure Phase A on iPhonePro

Run focused tests, full Body suite, generic Release and signed device builds. Run on iPhonePro only. Capture current refresh and quiet drain separately, foreground preemption, UI interaction, and receipt/persistence outcomes.

The prior 11.655-second activation included a 9.614-second ordinary refresh; removing repair waits cannot eliminate that ordinary cost. Compare like workloads and count queries/writes, rather than treating badge disappearance as a data-latency improvement.

**Gate:** Phase A achieves the responsiveness criteria and completes quiet repair after a stable eligible opportunity. Preserve residual limitations and measure source/ordinary work still visible.

## B. Complete repair during background opportunities

After current work and existing notification/workout ordering, offer history-only receipts the remaining real BGTask lease. Use verified full coverage and correct historical intraday behavior; keep derived validity and durable publication checks. A full-scope read that does not finish within the lease remains pending.

Add tests for history-only background admission, completion of one domain before expiration of the next, derived prerequisites, and foreground takeover. Keep the periodic-fallback regression tests. Preserve existing specialized progress owners rather than cloning their scans.

**Main files:** coordinator/store, BodyDataRefreshScheduler.swift only where integration requires it; focused background tests.

**Gate:** eligible background opportunities actually complete historical work when coverage fits, and quiet foreground provides the fallback. Unobserved natural background scheduling is reported honestly. Phase A alone is not reported as completion of the whole goal.

## C. Conditional optimization after A/B evidence

For each residual slow domain, decide independently:
- Keep the single full-scope read if narrower current reads would not materially improve current-value latency or would duplicate cheap retained statistics queries.
- Add a narrow current path only with meaningful measured benefit and complete latest-sample, sleep, warning, comparison, and derived dependency semantics.
- Add sub-domain progress only if the existing domain cannot reasonably complete in available opportunities. Measure query/write amplification and define generation handling before implementation.
- If frequent deliveries would repeatedly restart that proposed cursor, choose a justified anchored/dated invalidation design before enabling it. A recent-window-only heuristic cannot cover arbitrary historical changes.

No blanket monthly quantity scans, seven-day intraday checkpoints, schema bump, or new anchored-query subsystem is included by default. Bring a targeted amendment for review if Phase C is justified.

## Rollout and rollback

Preserve all current work and local settings. No permission widening, metric formula change, cache clear, uninstall, artificial personal HealthKit records, or Air deployment. Use ignored raw capture files and reviewed Markdown findings.

Keep commits/stages independently reviewable; commit/push only on request. Schema 2 remains unchanged in A/B, so rollback retains pending flags. Restore routing if necessary without clearing obligations; do not downgrade the user's device container to test compatibility.
