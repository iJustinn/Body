# Observer refresh regression: revised fix and validation plan

Date: 2026-09-12  
Status: Observer-context correction, schema migration, durability recovery, and evidence-driven discovery fixes implemented. A later natural activation reproduced a **42.757s** delay: **38.673s** repairing 18 domains sequentially after a broad callback burst, then 0.576s notification evaluation and 3.477s ordinary refresh. All receipts cleared without context churn or timeout. Bounded foreground quantity reads are now implemented and installed on iPhonePro: up to three reads overlap while commits remain serial. Final full Body suite passed (2,449 passed, 0 failed, 3 skipped); Release and signed DEBUG builds passed. The new build's clean-ledger launch took 1.699s, with no repair work, so affected-case improvement is still unmeasured. See [ObserverRefreshBatchDesign.md](ObserverRefreshBatchDesign.md) and [ObserverRefreshValidation.md](ObserverRefreshValidation.md). Live logging remains attached for the next natural broad callback burst.

Implementation evidence: the baseline exposed source-selectable leaves exiting before reads. Regression tests confirmed that discovery used a later wall-clock timestamp than its freshness check and that installing its own source bucket advanced the revision the caller was checking. The corrected path uses one admission date and a settled engine-actor revision, retaining input/fence guards. A subsequent device trace exposed the three body measurements skipping their shared `.basics` discovery; they now use the existing query descriptor's source kind. Retired passes stop before the next leaf. No preparation union, scheduler change, or notification reordering was needed for these corrections.

## Objective and revised scope

Eliminate unnecessary observed history repairs and avoid repeating work under changing provenance, while preserving actual HealthKit mutations, current-day refresh, historical corrections, and widget/Watch/notification correctness.

The first implementation scope is diagnostics and deterministic reproduction, followed by a narrow ledger-context correction. The former fetch-requirement union is deferred, not the default solution. Further changes require evidence from tests or the iPhonePro trace. Do not implement all the earlier candidate optimizations together.

## Verified mechanism

`c784d0a` connected observer repair to activation. The coordinator uses the entire `currentDashboardCacheScope().signature` for ledger initialization, synchronization, and capture. That scope includes `summaryDayStart` and `sleepGoal` as well as sources and aggregation. `BodyHealthDirtyWorkStore.init` and `synchronize` replace entries whose context differs with new current-and-history-pending generations.

Therefore, changing only the day re-dirties every admitted metric in a previously clean ledger, without a HealthKit delivery. This is a deterministic invalidation defect. Its 60–120-second cost on iPhonePro is still unmeasured. On a warm process, `captureRefreshInputs` also detects midnight and schedules a context refresh before ordinary resume admission; `repairObservedMetrics` can refuse work while that context refresh is needed. Do not assume every midnight immediately executes the entire observed loop in a fixed order.

Source discovery during an observed leaf can also change the scope, invalidate the active observed publication fence, and asynchronously synchronize new ledger generations. This can abandon the pass and leave follow-up work. It is not proof of an infinite loop: a subsequent pass can converge once discovered identities are stable.

The observed 120-second race does not set the visible timeout notice; `runRefreshWithDeadline` does. A successfully drained ledger clears `observedHealthChanges`, so a second ordinary full pass is conditional.

## 1. Reproduce the context defect without changing a device clock

Use the existing injected `calendarContext` and `contextRefreshOverride`, plus the ledger's temporary-file and `write:` seams. Extend `HealthDashboardCalendarContextTests` and `BodyHealthDirtyWorkTests`; the current tests cover each component but not their combined ledger rollover behavior.

1. Create a scope and ledger for day A, flush and acknowledge all admitted domains, then advance only the injected calendar date to day B and synchronize. Demonstrate that current code dirties every domain's history. Test both a running ledger and reload from its saved file.
2. Repeat with unchanged day/context: no generation changes. Preserve a real pending receipt through rollover. Cover DST with calendar-day arithmetic, not a fixed 86,400 seconds.
3. Exercise warm activation across midnight within the 60-second debounce. Verify the existing context correction still refreshes today's expired fields. Also test cold hydration on day B.
4. Compare source identity changes, timezone changes, sleep-goal changes, and unresolved-to-resolved source discovery separately. Record whether each causes a legitimate read, derived recomputation, or unwanted global history repair.

This proves enqueue behavior and protects current-day correctness; it cannot establish real HealthKit query duration. No phone/system clock change is needed.

## 2. Minimal diagnostics and iPhonePro baseline

Extend existing DEBUG logging with a pass ID and local monotonic timing. Keep health values and sample/workout identities out of logs. Five event groups are sufficient initially:

- Admission and ledger marking: pending kinds/generations/current-history flags; reason `delivery`, `initialization`, `contextSynchronization`, or `reset`; whether the context difference is day-only, compute-only, or fetch-related.
- Per-kind completion: duration, query success, actual query count where available, acknowledgment result and reason (dirty ledger not durable, newer generation/reset, context mismatch, payload failure, cancellation/fence).
- Observed-pass start/end: total wall time, pending remainder, deadline outcome, and any actual notice-setting deadline owner.
- Activation branch: skip, workout-only, full, context/initial-load, or busy. Time notification evaluation separately because activation awaits it before this decision.
- Mid-pass source/context change: pass ID, changed dimensions, and whether it invalidated the observed fence. Include ring-capture persistence count/time to identify event-burst IO costs.

Start `BodyRefreshProfile.beginRefresh()` when a foreground observed pass is admitted, and retain its existing end dump. Do not reset it per leaf: use local leaf timers, preserving the whole-pass total and counts. Tag local events with a pass ID so late work is distinguishable; do not build a general tracing subsystem. The singleton profile remains supplementary because background or abandoned tasks can contribute samples.

After plan approval, use Xcode to build and run the signed instrumented Body app on **iPhonePro**, verifying its exact destination. Preserve the app container and HealthKit data. Record commit/build, OS, build configuration, cold/warm state, and Auto-Apply setting. Do not uninstall, clear caches, downgrade its container, or create artificial personal health records.

Save the original Auto-Apply setting, disable it for the baseline, and capture a natural Watch-sync activation through quiescence or timeout. Compare quick and stale resumes and day-rollover evidence where available. Restore the setting afterward; an Auto-Apply test counts only if actual writes occurred. Collect three comparable affected runs if feasible and report all durations, rather than waiting indefinitely for an unreproducible event. Missing events are not a successful reproduction.

Save traces and an absolute before/after table in `docs/ObserverRefreshValidation.md`. Device preflight previously timed out initializing CoreDeviceService; Xcode MCP requires project access through `XcodeOpenWorkspace`. No device timing has been obtained. Resolve those prerequisites at the device phase and report any remaining blocker.

**Decision gate:** test the ledger-context cause first. Use the device trace to identify its contribution and the notice owner. Do not require proof of repair/full-refresh overlap to fix the deterministic invalidation defect; do require that proof before adding overlap optimizations.

## 3. Narrow the dirty-work context while keeping cache safety

Add a dedicated, versioned observer-ledger context derived from fetch-relevant provenance. The smallest initial projection keeps the existing primary/secondary source maps and aggregation identity, while excluding `summaryDayStart` and `sleepGoal` from the ledger identity. Keep payload-affecting sleep-stage preferences embedded in source requests: despite their display-oriented names, the sleep fetch/parser consumes them.

Keep `HealthDashboardCacheScope.signature` unchanged for snapshot validity, current-day expiration, publication, freshness, and notification validation. The ledger context answers whether a mutation's underlying fetch provenance changed; the dashboard context also answers whether today's summary is reusable. They must not share an interchangeable string contract.

Update all ledger-context producers and consumers together:

- Coordinator init, configure, capture, reset, and receipt creation/synchronization.
- The metric receipt-versus-current-context guard in `performObservedMetrics`, including an equivalent consistent check for the heartbeat path.
- Migration and tests that currently assume a receipt context equals the full dashboard signature.

Do not change `observedMetricValidation` or notification freshness stamps to the narrower context: those still describe current validated payloads. Preserve existing input revisions and publication fences, including midnight and settings changes during reads.

Rollover must still schedule the ordinary current-day/context correction and expire today's fields. A sleep-goal change must still recompute readiness through its existing context path. Excluding either from the ledger must not make the resume TTL suppress these obligations.

Continue conservative history invalidation for actual source/member, permission, and timezone/aggregation changes. A single global fetch context is sufficient for the initial correction; per-domain dependency contexts are a separate optimization if measured necessary. Do not reuse `fetchChanged` as a day-free predicate: it currently includes `summaryDayStart`.

Migration: version the new representation. For a recognized legacy full scope, project its provenance while preserving pending flags and receipt history, with an atomic ledger write and a reset-ID change so old in-flight receipts cannot acknowledge the migrated state. Only keep clean flags where the projected provenance still matches. Unknown/corrupt provenance must trigger a documented one-time conservative repair. Never clear a genuine pending mutation merely because it may have originated at midnight. Test migration persistence failure and restart; no schema churn on subsequent launches.

## 4. Stabilize discovery and handle durability failures only where reproduced

### Source-discovery invalidation

First test a previously unresolved source becoming resolved during an observed pass, and stable identities on the next pass. Require convergence and rejection of the old receipt/fence. Do not simply suppress `contextDidChange`: `reconcileDashboardCacheScope` independently invalidates the active token, and real source changes require immediate invalidation.

If the test/trace shows avoidable abandoned work, move discovery for the admitted dirty kinds and their dependencies into a bounded preparation step under the existing refresh slot. Settle source identity, reconcile the scope, synchronize the ledger, and recapture receipts before installing the query/publication fence for the actual repair. Reuse the freshly discovered sources during that pass. Keep eligibility checks and the same total deadline/lease budget across preparation and reads; moving discovery outside the measured budget is not a fix.

A genuine change after preparation still cancels/fences the old work and schedules one pending-work check. Do not defer validity checks until completion or continue through all leaves after the owner is invalid. Concurrent deliveries during preparation must survive receipt recapture. Apply this ordering to a background lease only if needed and test its deadline/foreground handoff explicitly.

### Ledger durability

The `!needsSave` gate in `acknowledge` is deliberate: an undurable capture cannot be consumed. Existing configure/activation flushes can clear it, so a single transient failure is not permanently sticky. However, the coordinator ignores flush results and can spend time reading while acknowledgment remains impossible.

Check the flush result before launching expensive observed reads. On failure retain the obligation, log the failure, and leave normal lifecycle/background opportunities intact. If a concurrent mark fails during a pass, `acknowledge` may make one synchronous flush attempt, then repeat all reset/generation/context checks; it must still return false if persistence fails or a newer receipt supersedes it. Do not remove the durability gate or skip the payload durability requirement. Implement this recovery only with transient and persistent failure tests.

## 5. Keep scheduling changes small and evidence-based

Retain the existing coordinator debounce and refresh-completion hook. A busy-slot return should leave a pending-work hint and wait for that completion signal. The current guard returns before the defer is installed; it does not autonomously re-arm every second. Repeated external deliveries can still schedule repeated checks, which can be coalesced by checking slot ownership before arming the existing debounce.

Do not add the former 5/15/30/60-second retry ladder or a separate scheduler. Failed captures/queries remain pending for existing activation, delivery, manual refresh, or background opportunities. Ensure new valid generations arriving during a successful pass still receive a bounded foreground follow-up using the existing one-second debounce/five-second ceiling once the slot is free. An isolated failure with no subsequent event is not promised an immediate timer retry by this scope.

Do not preserve an expired `firstWake` while repeatedly re-arming a busy slot: that would make `delay` zero. Use the owner-completion signal instead. If timer behavior changes, add a small injectable now/sleep seam to this coordinator only; this seam is new work, unlike the already-injectable calendar context.

Keep notification evaluation in its current order initially and measure it. If its separate 20-second race is material, move foreground evaluation to one retained, coalesced task after the appropriate refresh completion, preserving sleep/readiness data eligibility, foreground cancellation, and re-evaluation after a newer pass. A bare fire-and-forget task before fresh inputs are ready is insufficient. Keep background notification ordering intact.

Ring-related deliveries each request an awaited full snapshot persistence. Measure counts and cost; queue ordering is established, but a distinct expensive encode for every callback is not proven because storage can deduplicate. Any later batching must still make capture durable before HealthKit completion. Leave badge debounce unchanged; legitimate adjacent passes may still look like one continuous spinner.

## 6. Defer overlap and effort optimizations

Removing artificial history work may resolve the regression without changing the full refresh engine. Re-measure before considering any of these:

- Moving observed repair after ordinary admission: safe only if pending mutations and initial/context work still obtain an owner. Moving it below an early return can starve work; reordering alone also does not remove query cost.
- Reusing full-refresh work: needs exact captured-receipt coverage, successful authoritative reads for the required current/history window, and awaited durable payloads. A 30-minute `observedMetricValidation` TTL cannot establish coverage of a newer mutation. Do not skip/acknowledge receipts by that TTL. The existing observed gates already supply these protections; only reuse from the ordinary path would need new coverage metadata.
- Combining Body effort writes with observer repair: preserve durable local-write obligations and every observer delivery. No time-window self-write suppression; no assumption that enabling Auto-Apply produces writes on each activation.
- Incremental training load: retain the full historical fallback for unknown external edits/deletions. Require affected-workout identification and result-equivalence tests before narrowing a rebuild.

The former fetch-requirement union is not in the initial scope. If traces still show significant duplication after the narrow fixes, write a separate concrete design around the proven overlap rather than implementing a refresh-engine rewrite speculatively.

## 7. Tests, device acceptance, and delivery

Focused XCTest cases:

- Clean same-context synchronization and reload; day-only and sleep-goal-only changes do not create history work; real pending receipts survive both.
- Warm midnight within the resume debounce, cold rollover, DST, and timezone/source/permission changes retain correct current summaries and historical provenance.
- Legacy migration preserves dirty flags, invalidates old receipts, persists atomically, and does not recur on every launch.
- Unresolved-to-resolved discovery rejects old publications and converges once stable; source A→B→A, new delivery during discovery/read, timeout, cancellation, and foreground handoff cannot clear newer work.
- Failed flush avoids futile queries; transient recovery succeeds; persistent failure and newer-generation acknowledgment remain conservative after restart.
- Busy-slot admission waits for completion without timer polling; finite valid bursts coalesce and newer post-read mutations still receive follow-up. Add timer injection only if needed for the scheduling change.
- Keep existing current/history split, query-failure/empty-deletion, snapshot/sidecar durability, notification, ring/journal, hidden companion, and historical effort tests passing. Do not rebuild these safety mechanisms merely to restate them.

Run focused tests with `-parallel-testing-enabled NO`; run the full Body suite for an implemented orchestration change, with the generic iOS build fallback if simulator launch fails. Test changed shared code against relevant companion targets. This document revision itself requires no app build; the review verification below is source/test inspection, not an XCTest run.

On iPhonePro repeat comparable baseline scenarios and record absolute activation-to-settle and badge-visible durations, query/repair counts, reasons, deadline outcomes, and Auto-Apply writes. Drop the ungrounded 50% threshold. Accept only when:

- With a clean stable ledger, midnight alone creates **no observer historical obligation**; the necessary current-day/context refresh still runs. No-delivery does not imply no current-day refresh.
- Genuine pending work, missing/corrupt-ledger initialization, migration fallback, and fetch-provenance changes retain their necessary repairs. The rollover criterion does not apply to those cases.
- Stable source identity does not repeatedly replace the same context or abandon follow-up passes; newer mutations remain pending until durably repaired.
- Comparable affected runs show the artificial repair cost is gone and no timeout notice. If a timeout/long delay remains, identify its actual owner and continue the measured investigation before declaring the user-visible issue resolved.
- Dashboard, history, widget/Watch payloads, and notifications remain correct; a finite successful burst settles without redundant passes against consumed receipts.

Keep diagnostics and behavioral changes separately reviewable. Preserve unrelated edits to `BodyReadinessStarHero.swift` and the current `BodyWatchTests.xcscheme`. No code changes, commits, or device operations are part of this plan revision.

## Review verification and disposition

The appended review below is preserved verbatim for history; the revised plan above and this disposition supersede its proposed actions where they differ.

| Review point | Verified result and action |
| --- | --- |
| P1.1: day-dependent ledger | Confirmed from `HealthDashboardCacheScope` fields/signature, `currentDashboardCacheScope`, and ledger init/synchronize. Promoted to the first correction. The claim of a deterministic 1–2-minute run is unmeasured; warm context-refresh admission can alter execution order. Domain count depends on permissions/consumers. |
| P1.2: discovery re-dirties receipts | Confirmed conditional invalidation/re-generation path. More directly, the observed task-local fence is the invalidated token, so the leaf may exit before persistence. Infinite repetition and “nothing acknowledged” for every pass are not established; earlier stable leaves may have succeeded. Deleting the callback alone would not fix token invalidation. |
| P1.3: `needsSave` | Confirmed gate; partial conclusion. Existing configure/synchronize and explicit flush can recover it. Added pre-read flush admission and guarded recovery; retain its durability invariant. |
| P1.4: excessive union scope | Accepted scope criticism; broad union deferred. `refreshRecentMonths` currently spans roughly 180 lines, not 600, although its downstream surface is substantial. Neither suggested small alternative is accepted unconditionally: reordering can starve work and TTL skipping can lose new mutations/history. |
| P2.5: existing safety gates | Accepted. Describe these as invariants to preserve; new exact coverage is required only if ordinary-refresh results are reused. |
| P2.6: scheduler ownership/polling | Removed speculative retry ladder. The alleged self-rearm on busy return is contradicted by control flow: return precedes defer, and that branch never calls `scheduleForeground`. External events/context tasks can still cause repeated checks. Retaining expired `firstWake` is not a valid fix. |
| P2.7: diagnostics scope | Accepted a smaller diagnostic design. Kept explicit notice owner, notification timing, and query/ack counts needed for attribution. Start the observed timer, but do not reset the global profile per kind. |
| P2.8: sequencing | Accepted. Offline ledger/context reproduction precedes the broader device diagnosis; overlap is no longer assumed. |
| P3: targets and test seams | Dropped 50% target; added query counts and precise rollover acceptance. Calendar injection already exists in the store and rollover tests; debounce-clock injection would be new. Do not alter the physical device clock. |
| P3: notifications/rings/badge | Notification timing was already in original section 1 and remains measured; moving evaluation is conditional. Ring capture does request persistence per relevant delivery, but actual encode cost needs measurement. Badge may merge legitimate passes; retained. |
| Proposed narrower context | Accepted with migration and all comparison sites updated. Keep fetch-affecting sleep-stage preferences. `fetchChanged` itself includes the day, so it cannot be used unchanged. |
| Proposed defer-all-context-change / TTL skip | Rejected as written: real provenance changes must invalidate immediately, and time freshness is not generation coverage. Safe alternatives are specified above. |

Verification inspected the live scope/ledger/coordinator/repair/persistence code, `HealthKitFetchEngine+Sleep` preference use, the background scheduler, and existing calendar and dirty-work tests. No device behavior or performance figure has been verified, and no XCTest suite was run for this documentation-only edit.

---

## Adversarial review, Claude, 2026-09-12

**Verdict: keep Section 1 and the decision gate; do not approve Sections 2 to 5 as written.** The plan assumes the delay is duplicated overlapping work between observed repair and the ordinary refresh. Code reading shows a deterministic cause that needs no observer deliveries at all, plus a self-retriggering loop inside observed repair, and neither is addressed by the Section 2 fetch-requirement union. All findings below were verified against the current tree.

### P1

1. **The ledger context is the full dashboard cache-scope signature, which changes every day.** `BodyHealthChangeCoordinator.swift:38-41` uses `currentDashboardCacheScope().signature` as the ledger context. That signature JSON-encodes the whole scope including `summaryDayStart: Date?` (`HealthDashboardCacheScope.swift:42,51-56`). `BodyHealthDirtyWorkStore.synchronize` (`:101-107`) and `init` (`:44-47`) mark every admitted domain dirty at a new generation whenever the stored context differs. Domains are the widget kinds plus the Watch display order (`BodyHealthObservationPolicy.swift:33-36`), roughly 15 to 18 kinds. So the first activation after any midnight rollover (or any source, sleep-goal, timezone or Pro change) runs a sequential observed repair of every kind, with sleep pulling five vitals sources and training load clearing its seed, anchor and effort cache for a 408-day rebuild. That alone is a reproducible 1-2 minute activation, matches "Auto-Apply on and off", and a fetch-requirement union would still fetch all of them.

2. **Observed repair can re-dirty its own receipts mid-pass.** The observed branch of `performHealthMetricRefresh` calls `reconcileDashboardCacheScope()` and then `healthChangeCoordinator?.contextDidChange()` when the scope changed (`HealthKitWorkoutStore.swift:1519-1525`). `contextDidChange` reconfigures, re-synchronizes the ledger at a new generation and calls `scheduleForeground()`. The in-flight receipts then fail the exact-generation check in `acknowledge` (`BodyHealthDirtyWorkStore.swift:88-91`) and the per-kind context guard (`:8532`). `reconcileDashboardCacheScope` also invalidates `dashboardPublicationToken` (`:6128-6129`), so the awaited persist returns false and nothing is acknowledged. The pass finishes, the follow-up fires, and the cycle repeats. Not mentioned in the plan or the diagnosis.

3. **`acknowledge` is hard-gated on `!needsSave` (`BodyHealthDirtyWorkStore.swift:89`).** One failed ledger write makes every acknowledgment return false until a later flush succeeds, so every repair pass redoes all work. Section 3 mentions the generation check but not this sticky failure gate, and Section 4's backoff does not cover it.

4. **Section 2 is a refresh-engine rewrite presented as a fix.** The union design touches `syncWhenAppBecomesActive`, `repairOnActivation`, `repairObservedMetrics` and `performObservedMetrics`, the observed/ordinary split in `performHealthMetricRefresh`, `refreshRecentMonths` (about 600 lines), `updateHealthDashboardSnapshot`, the publication fence and `runRefreshWithDeadline` ownership, plus the ledger: five or six files and more than fifteen functions on the only data path. Two much smaller alternatives are not even listed in the Section 2 table: (a) move `await repairOnActivation()` after the freshness and debounce decision and expose a cheap `hasPendingWork` for the gates, about two functions; (b) have the ordinary full refresh stamp `observedMetricValidation[kind]` for kinds it fetched successfully and let `performObservedMetrics` skip current-pending kinds already stamped under the same context, reusing `observedMetricNeedsValidation` (`:8708-8713`) and its 30-minute TTL, about three functions.

### P2

5. **Section 3 is mostly restatement.** Captured-before-read receipts with reset ID, generation and context (`Coordinator:150-166`), the query-ran and no-failure gates (`:1580`), the current/history split (`DirtyWorkStore:10-11`, acks history only when `lease == nil` at `:8526,8533`), the awaited durable persist before ack (`:1587-1595`), and the fence and context checks (`:795-805, 8484-8494, 8532`) all exist. Genuinely missing: a record of which kinds an ordinary refresh covered, and ring/journal coverage is ad hoc (`:8536-8552`). Say that and stop.

6. **Section 4's 5/15/30/60 s backoff is a fourth scheduler with no owner.** There is already the 1 s debounce with 5 s ceiling (`Coordinator:71-85`), `BodyDataRefreshScheduler` with a 30-minute non-replacing earliest date (`:29-32`), and the 300 ms context coalescer (`:749`). The plan does not say where the timer lives, whether `enteredBackground()` cancels it (it cancels only `debounce` and `foregroundWork`, `Coordinator:87-92`), or how it avoids pushing out the background request, and Section 2 explicitly forbids a second scheduler. The real defect today is narrower: when `repairOnActivation` bails on `store.isRefreshing` (`Coordinator:102-106`) it sets `followupNeeded` and re-arms, and each firing nils `firstWake` (`:82`), so it re-arms every second for the whole duration of a long refresh.

7. **Section 1 is over-specified.** Five log lines decide the gate: (1) at `repairOnActivation` entry, the pending kinds, generations and a mark reason (delivery / init / synchronize) carried on `DirtyWorkStore.mark`; (2) per kind in `performObservedMetrics`, duration, success and acknowledged-or-why-not; (3) in `repairObservedMetrics`, whole-pass wall time and deadline outcome; (4) in `syncWhenAppBecomesActive`, which branch ran after the repair; (5) one line when `contextDidChange()` fires mid-repair (tests finding 2). `BodyRefreshProfile.beginRefresh()` is only called from `refreshRecentMonths` (`:5270`) but observed repair still hits `dumpAndReset` via `finishRefresh` (`:8477-8480`), so today it dumps a table with no start time; call `beginRefresh()` in `repairObservedMetrics` and reset per kind. No new infrastructure needed.

8. **The sequencing contradiction is real.** If the trace shows finding 1 (bulk re-dirty, no overlap with a full refresh), Section 2's central mechanism is invalidated wholesale and the fix moves to `synchronize` and context granularity instead. Approve Section 1 plus the gate only.

### P3

- The 50% target has no baseline and no variance. If finding 1 is the cause the honest criterion is binary: the first activation after a day rollover repairs at most the kinds with a genuine delivery.
- "No duplicate query for a covered requirement" is not measurable from Section 1's fields; only durations are logged, and `leafCounts` resets per dump.
- There is no injectable clock or sleeper today (`BodyHealthObservationTests` has none; policy constants are `static let`). The `write:` seam on the ledger, the `observing:` and `suppressesInitialDelivery:` seams on the coordinator, and `withRefreshSlotHeld` (`:634`) already cover the context-change and acknowledgment cases; the clock is net-new infra the plan under-scopes.
- Forgotten: `evaluateNewNotifications()` is awaited inside `repairOnActivation` (`Coordinator:124`) with its own 20 s race (`:8594-8597`), on the activation critical path before the ordinary refresh decision. `capture` also awaits a full `persistDashboardSnapshot` per delivery via `captureRingObservation` (`:8441-8449`), so a burst serializes N snapshot encodes. The badge will still merge two legitimate passes into one spinner (`BodyHealthSyncBadge.swift:102-111`); the plan should say so.
- Verified as stated: persistence is fire-and-forget at the full-refresh call sites (`:5437`, `:5565`); the observed race sets no notice (`:8491-8495` vs `:851`); the uncommitted `BodyReadinessStarHero.swift` edit exists.

### Smallest defensible plan

- Cut Section 1 to the five log lines above plus the mark reason; start the profile timer in observed repair.
- Falsify finding 1 first, offline: move the device or simulator clock past midnight and activate. If that alone reproduces the 60-120 s badge, Section 2 is moot.
- Fix finding 1: give the ledger a narrower context than the full dashboard signature (sources, permissions, aggregation only; exclude `summaryDayStart` and presentation prefs), or mark in `synchronize` only domains whose fetch-relevant scope changed (`reconcileDashboardCacheScope` already computes `fetchChanged`, `:6125-6128`).
- Fix finding 2: do not call `contextDidChange()` from inside an observed repair; set a flag and decide at `repairOnActivation` completion.
- Fix finding 3: have `acknowledge` attempt a flush instead of returning false while `needsSave` is set.
- Stop re-arming every second while a refresh holds the slot: do not clear `firstWake` on a bail-out re-arm.
- Move `evaluateNewNotifications()` off the awaited activation path.
- Only if the trace still shows overlap: adopt alternative (b), the ordinary refresh stamps `observedMetricValidation` and observed repair skips stamped kinds. Do not build the fetch-requirement union.
- Drop the 5/15/30/60 s timer. Add an injectable clock only for the debounce and re-arm tests.
- Replace the 50% target with the binary rollover criterion plus absolute badge-visible times before and after.

### Not verified

- Which mechanism fires on the user's device; finding 1 is deterministic from the code and cheap to falsify, finding 2 is a code-derived hypothesis.
- Whether `refreshRecentMonths` awaits persistence on every path, or the partial/incremental-window claims in Section 2 (not read end to end).
- Device and Xcode tooling state; the self-write observer wake premise in Section 5.
