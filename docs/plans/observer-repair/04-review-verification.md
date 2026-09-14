# Verification of the appended review

Date: 2026-09-12. The original review in README is preserved verbatim. This response reflects read-only inspection of the current working tree and Apple documentation; no new performance tests or implementation were performed.

## Decisions

| Point | Verification and plan response |
| --- | --- |
| R1: full-scope reads versus new scans | **Accept the simplification.** Current metric repair already fetches retained series; no mandatory date cursor is needed to move it off activation. Keep domain reads/receipts; gate narrower reads or sub-domain progress on measured benefit. **Correct the explanation:** passive intraday coverage differs, and background already publishes companions. |
| R2: activation/notification waits | **Confirmed.** syncWhenAppBecomesActive awaits repairOnActivation before its gates; that method awaits notification evaluation. Both changes move into Phase A, with retained owners and send-time/cancellation tests. |
| R3: double fetching/current invalidation | **Confirmed risk, not an unconditional rule.** Remaining history bypasses freshness and can cause another full pass. A successful drain can clear observedHealthChanges, so every callback does not necessarily imply a full refresh on every later activation. Reuse actual foreground/manual coverage and separate current pending from history. Ordinary 9.614s cost is explicitly retained in expectations. |
| R4: generation starvation | **Accept the risk; reject “guaranteed” as proven from this trace.** The captured burst proves overlapping newer receipts, not permanent continuous churn. Choose the review's first option: existing full-scope per-domain reads and latest admission receipts. Do not introduce restarting multi-month cursors. A recent-window heuristic is unsafe for undated old edits. |
| R5: cancellation/budget conflict | **Original plan overclaimed; review omitted existing mechanisms.** There are three separate logical pools. Callback leaves already resume cancelled and call stop. Quiet work uses the existing background pool; foreground has separate admission. Keep logical limits and bounded retired work, without claiming a hard physical healthd limit or guaranteed stop timing. Legacy queued acquire still needs audit/adaptation. |
| R6: fairness | **Confirmed.** Background admission tests entire task handles; retained loops can monopolize availability. Plan now specifies eligibility, foreground priority, rotation, dependency skipping, and existing-unit yield boundaries. Also includes journal repair's visible busy-state side effect. |
| R7: empty/privacy | **Privacy concern confirmed; proposed authorization heuristics rejected.** Read denial is not observable through sharing status, source discovery, or neighboring samples. Preserve current accessible-data result semantics and remove the proposed new interval-deletion policy from A/B. No claim that an empty result proves deletion of underlying HealthKit records. |
| R8: write amplification | **Confirmed structurally; counts need measurement.** Existing acknowledge encodes/compares/writes the ledger and metric success persists dashboard data. Dropping universal date units avoids multiplying those writes. Record actual count/bytes/time and coalesce derived/companion publication. |
| R9: migration/rollback | **Confirmed.** Init accepts schema 1/2; schema 3 would cause conservative reconstruction. A/B keep schema 2 unchanged. Optional versioned progress is only a future candidate, and older writers lose it even if they decode it successfully. |
| R10: manual coverage, initial load, stress, tests | **Accepted.** Full manual coverage can acknowledge matching history; no maintenance before initial load completes; stress gets an independent reproduction/fix; validation now concentrates on A/B instead of hypothetical date-cursor APIs. |

## Why the recommended Phase A is not copied verbatim

It usefully moves the cheap wins first, but three parts would leave the goal incomplete or unsafe:

1. Calling repairObservedMetrics unchanged still owns isRefreshing, uses foreground query defaults and finishRefresh side effects, and chooses acknowledgment scope based on lease presence. Its owner/purpose wrapper and admission must change before quiet use.
2. Keeping BGTask history handling unchanged forever leaves history-only receipts ineligible. Revised Phase B preserves the agreed background-repair goal using existing full-scope reads when their coverage fits the lease.
3. Simply removing the observed wait does not eliminate the existing automatic workout-journal badge or solve whole-task admission starvation. Those integration hooks remain Phase A work, without rewriting the underlying journal/record/stress algorithms.

The reduced plan does not pretend this is a one-line scheduling change. It removes speculative scanning/schema work while retaining required ownership, coverage, fairness, and persistence work.

## Evidence checked

- Body/Services/BodyHealthChangeCoordinator.swift: repairOnActivation, runBackground, capture, pending.
- Body/Services/HealthKitWorkoutStore.swift: syncWhenAppBecomesActive, awaitRefreshSlotFree, finishRefresh, applyHealthMetricRefresh, performObservedMetrics, scheduleWorkoutJournalIfNeeded, notification evaluation.
- Body/Services/HealthKitQueryBudget.swift: separate 10/4/2 permit pools, legacy acquire, leased acquireForCurrentTask.
- BodyWatchSnapshotKit/BodyHealthQuerying.swift: bodyCancellableRead and BodyQueryResumeBox.cancel resume once and stop the installed query.
- Body/Services/BodyHealthDirtyWorkStore.swift: schema acceptance, receipt guards, payload-independent ledger acknowledgment/write.
- Body/Services/HealthKitWorkoutStore+StressBackfill.swift and +Records.swift: retained loops, existing durable units, dependency/completion hooks.
- docs/ObserverRefreshValidation.md: measured burst/activation timings; no per-domain summary-versus-history cost proof yet.

[Apple's HKAuthorizationStatus documentation](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus) explicitly describes authorization as permission to save and says denied reads expose only the app's own written data. Therefore even a nonempty result does not establish access to every source.

[Apple's earliest authorized sample date documentation](https://developer.apple.com/documentation/healthkit/hkhealthstore/getearliestauthorizedsampledate%28for%3Acompletion%3A%29) describes limited-history boundaries and says missing entries cannot distinguish full access from denial. This is documented as beta at review time; the plan does not add it as a dependency or assume availability on every supported OS.

## Unchanged goal

Fast interactive opening and foreground refresh; quiet and opportunistic background repair; no lost obligations or false freshness. Phase C is evidence-gated. iPhonePro remains the only deployment target. This revision changes the route to the goal, not the goal or the requirement for review before implementation.
