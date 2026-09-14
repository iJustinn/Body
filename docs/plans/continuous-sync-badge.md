# Continuous sync badge with specific calculation progress

Status: Implemented for 1.1.1 (build 4). The user authorized the complete implementation and build bump on September 13, 2026. Validation results are recorded below.

Revision: Appended review verified against the current source on September 13, 2026. The revised plan below is authoritative; the original review is preserved at the end with a response table.

## Intended behavior

Present one continuous sync badge for a refresh and its already-queued foreground follow-ups. Show what Body is actually calculating, such as “Calculating Stress…” or “Calculating Training Load…”, and show “All done · [completion time]” once the visible work has successfully settled.

The badge must not announce completion between related passes, restart its initial loading presentation for every metric batch, or substitute the generic “Calculating scores…” for a known calculation.

## Confirmed evidence

On iPhoneAir, September 13, 2026 (EDT), launch session `a3f309380`, PID `18443`:

| Time | Captured event |
| --- | --- |
| 15:03:36.328–36.364 | Training Load observer deliveries and a durable `reason=automaticEffort` obligation. |
| 15:03:36.837 | Initial full refresh completed in 14.067 seconds. |
| 15:03:37.859–37.872 | Foreground admission found pending Stress and Training Load work, with `rings=true`; a follow-up pass started. |
| 15:03:42.889 | Follow-up completed successfully in 5.027 seconds, acknowledging Stress and Training Load. |

The user saw one automatic restart of the badge during this capture. The first finish and next pass start were approximately 1.034 seconds apart. Badge completion currently waits 0.6 seconds, while foreground observer scheduling normally waits 1 second. The automatic-effort quiet path requires only Training Load to be pending and no ring repair; this capture did not meet that condition.

Raw trace: `/private/tmp/Body-iPhoneAir-refresh-20260913.log` (local diagnostic artifact; may not survive temporary-file cleanup). The earlier iPhonePro second full refresh was confirmed by the user to be a manual pull and is not evidence of an automatic restart. Multiple rapid repeats remain unverified.

## Scope and implementation sequence

### Alternatives and chosen scope

Option A is to preserve `beginSyncing()` state while already syncing and increase the completion delay from 0.6 to approximately 1.5 seconds. This would probably cover the captured 1.034-second gap. It would delay every ordinary success by another 0.9 seconds, would not cover prolonged admission or repeated deliveries, and would not address specific calculation labels. The coordinator's 5-second maximum wait caps a burst of rescheduled debounces; it is not a single 5-second sleep or an end-to-end admission bound.

Choose explicit pending-work presentation and specific labels together. Do not ship a timer-only stopgap first. Independently fix `beginSyncing()` so an already-active visible session does not reset `pendingStage`, `displayedStage`, its dwell timestamp, or the success baseline on every `isRefreshing` rising edge.

### 1. Represent the visible sync independently of the refresh slot

- Add the smallest observable presentation state needed to represent an active visible sync, its current operation, and queued foreground continuation. Keep this in the existing store/coordinator ownership model.
- Keep `isRefreshing` as the actual execution/serialization flag. Do not hold it true merely to keep the badge visible: that would block follow-up admission, wake-up waiters, and maintenance eligibility.
- Have the coordinator expose scheduled/being-admitted foreground continuation before releasing the current visible pass. Include debounce, admission, execution, and settlement; avoid a transient idle gap while an async admission check runs.
- Preserve one visible session and its outcome across those transitions. Do not reset its progress or success baseline whenever an individual pass acquires the refresh slot.
- Clear queued presentation state when work is cancelled, superseded, routed to quiet maintenance, found unnecessary, or abandoned by an existing deadline. Audit backgrounding, context/source changes, permission changes, and cache clearing for stale ownership.
- Track actual queued/admitted foreground work, not all dirty ledger entries. Retained history, failed receipts awaiting a future external opportunity, and quiet maintenance must not keep the badge alive indefinitely.
- Continue a visible session when related work arrives before completion. A genuinely later event after settlement may start a new session. Continuous incoming changes keep the badge accurate; existing execution deadlines remain in force.

Concrete state and notification contract:

- The observable `HealthKitWorkoutStore` owns a `foregroundContinuationID: UUID?`, the visible session identity, operation, and presentation outcome. The plain coordinator updates these through narrow store methods; the view does not observe the coordinator directly. A computed `hasQueuedForegroundContinuation` may derive from the token.
- `scheduleForeground()` installs/replaces the token synchronously with the scheduled task. Cancellation cleanup clears only its matching token, so an older cancelled task cannot erase its replacement. Creating a pending token alone does not reveal a badge while idle; it extends an already-visible session until admission determines whether visible work will run.
- Keep the token through the sleep, ledger inspection, `syncWhenAppBecomesActive()`, and its awaited admission/execution. In a matching-token `defer`, settle it when that opportunity exits. A replacement schedule keeps the session pending without a false idle transition.
- Explicitly cover `skip`, `freshCache`, `initialLoad`, no-work repair, and quiet-routing returns. A `busy` return releases this attempt while the active owner and existing rescheduling policy own further work. A `context` return transfers presentation ownership to the scheduled context refresh before releasing the old token. Backgrounding/reset and the observed non-foreground completion path invalidate pending and visible ownership without announcing success. Do not introduce new retries to satisfy UI state.
- The badge's settling task uses a composite key containing session identity, `isRefreshing`, and `foregroundContinuationID`, rather than `isRefreshing` alone. Clearing a no-op continuation therefore wakes settlement even if no refresh ever started. Revalidate the key and outcome after the delay.
- `finishRefresh()` currently sets `isRefreshing = false` before it synchronously calls `refreshDidFinish()`. Register pending continuation before publishing the presentation's completion candidate, or publish the composite state after that synchronous handoff. Do not rely on SwiftUI coalescing those mutations.

### 2. Report specific operations with stable presentation

Replace the unqualified `.computing` presentation with a typed calculation target. Use the existing product names and localization conventions.

| Operation | Proposed badge text |
| --- | --- |
| Initial broad HealthKit reads | Loading data... |
| Scheduled continuation awaiting admission | Syncing... |
| Readiness computation | Calculating Readiness... |
| Stress computation, including its required inputs | Calculating Stress... |
| Training Load computation, including its required workout inputs | Calculating Training Load... |
| Body Radar computation | Calculating Body Radar... |
| A metric refresh that only reads/updates data | A complete metric-specific phrase, such as Updating Heart Rate... |
| Concurrent quantity batch | Updating health data... |
| Activity Ring reconciliation | Updating Activity Rings... |
| Automatic workout-effort write | Saving workout effort... |
| Final required publication/persistence | Finishing up... |
| Successfully settled visible sync | All done · [completion time] |
| Some visible work succeeded, but required work failed | Some health data updated |

- Emit progress from actual operation boundaries in full refresh, single-metric refresh, observed repair/batches, and derived-score recomputation. Audit any other calculations encountered and give them the corresponding product name.
- A named operation owns its presentation across its nested reads and publication. Internal `.fetching` calls must not replace “Calculating Training Load…” with the initial “Loading data…” message.
- During the scheduling gap, use the neutral “Syncing...” label, subject to the same dwell/coalescing rule. Do not infer a target from a sleeping debounce or add ledger reads for badge copy. Select a named label after actual admission identifies the operation.
- Coalesce concurrent work with an explicit owner rule: broad concurrent fetching retains “Loading data...”; a concurrent quantity batch uses “Updating health data...” for its entire fetch/apply unit, and its children emit no competing badge labels. Individual derived operations use their named calculation label. Do not reorder or serialize HealthKit work just to create a cosmetic phase order.
- Preserve the current short dwell behavior (approximately 0.5 seconds), using the latest valid operation rather than queuing every transient phase for later playback. Fast or skipped calculations need not appear. Do not add artificial computation delays.
- Apply session/generation ownership to progress and delayed UI transitions. Late results from cancelled or quiet work must not repaint the badge.
- Preserve first-load suppression, Reduce Motion behavior, and readable layouts. Use three periods to match existing catalog keys. Add complete per-operation/per-metric phrases in English and Simplified Chinese, the locales present on the current badge keys; avoid concatenating “Updating” with a translated name. Audit catalog and runtime/source guard references before removing “Calculating scores...”. Shared first-load/rebuild consumers of stage text should receive meaningful labels without adopting inappropriate badge lifecycle behavior.
- Keep an accessible stable status such as “Updating health data” for intermediate animation changes; allow the current specific operation to be read when the user focuses the badge, without explicitly announcing every stage. Review/remove `.updatesFrequently` for this badge as appropriate, without changing unrelated shared-label consumers. Announce the final full or partial result once. Verify actual VoiceOver behavior on device, including changes while focused.

An illustrative successful flow is `Loading data... → Calculating Readiness... → Calculating Stress... → Saving workout effort... → Syncing... → Calculating Training Load... → Finishing up... → All done · [completion time]`. The actual labels and order must follow actual operations; this is not a fixed animation script.

Verified operation boundaries and implementation cost:

- The captured observed pass executed Stress (1.066 seconds), then Training Load (2.321 seconds), sequentially. Neither has a quantity descriptor, so neither entered `repairObservedQuantityBatch`. The separate quantity batch admits at most three eligible adjacent receipts. Both named captured operations are long enough to be useful with the existing dwell, although these timings include inputs and persistence, not just CPU calculation.
- `updateHealthDashboardSnapshot` does run Readiness, Stress, and Body Radar in one detached task, but in sequential conditional calls. Keep that task and those calls in place. Add a small ordered, nonblocking progress channel at these boundaries, consumed on the main actor by the visible owner; for example, a bounded newest-value `AsyncStream` carrying session/operation identity and sequence. Do not await a main-actor hop between calculations or spawn an unordered task per event. Close/cancel the channel with the owner and discard superseded or already-finished operation events.
- The separate `reapplyActivityReadinessAfterWorkouts`, `recomputeStress`, and `recomputeBodyRadar` entry points can report through the same owner directly. Nested publishers inherit the current operation rather than resetting it. Standalone Training Load refresh owns its named label across required reads; broad parallel fetches keep their batch label.
- Measure/report actual calculation durations during validation. The current `RefreshProfile` table reports fetch leaves and does not establish individual Readiness/Stress/Radar CPU durations. Keep all requested named targets available, but do not force fast phases onto the screen or remove them merely because a single run is fast.

### 3. Settle once and preserve truthful outcomes

- Drive completion from the visible session having no active or queued foreground work, followed by the existing short presentation debounce. Recheck the same session and pending state when the debounce fires.
- Retain the existing brief success display and one accessibility completion announcement per successful visible session.
- Aggregate outcomes across visible passes. An earlier successful pass must not cause an unqualified success after a required follow-up fails or times out. Show “Some health data updated” when successful visible publication is followed by required failure; retain existing notices. A completely failed/no-query session gets no success confirmation. Cancellation/backgrounding terminates presentation without a completion announcement.
- A queued no-op or a continuation redirected to quiet maintenance releases its presentation claim without invalidating an otherwise successful visible refresh.

Concrete outcome contract: record `didPublishVisibleUpdate` and `hadRequiredFailure` per session, plus cancellation/invalidation. Existing successful visible counter increments can set the former, but observed-only repair must explicitly report durable accepted publication too. The existing observed Bool means “changed”, not “all required work succeeded”; never treat it as a complete success/failure result. Accumulate a small presentation-only pass result alongside the existing Bool from query, required persistence, and deadline outcomes, including partial batches. Preserve the Bool's existing callers and all ledger behavior. A superseded receipt that still has a scheduled replacement remains pending rather than counting as a terminal failure. The direct `.finishing` assignment in deadline recovery must pass through presentation ownership and record timeout even when the abandoned body can no longer report. Tests must cover successful observed-only sessions and success followed by failure. Existing notices are retained, but do not assume every observed failure currently creates one.

### 4. Preserve refresh correctness; assess quiet routing separately

For this implementation, keep HealthKit reads, observer capture and acknowledgement, automatic effort writes, freshness checks, query budgets, and quiet-maintenance admission rules intact. The captured post-write work cannot simply be discarded: it must reconcile the new effort and outstanding Stress/ring obligations.

Verify that already-quiet operations remain invisible and cannot acquire the visible session accidentally. Whether more Stress/ring work should move into quiet maintenance is a separate scheduling decision, requiring evidence and review after the presentation fix. Do not fold that policy change into this patch.

## Expected files

- `Body/Services/HealthKitWorkoutStore.swift`: visible ownership/outcomes and meaningful operation boundaries.
- `Body/Services/BodyHealthChangeCoordinator.swift`: observable foreground continuation lifecycle and handoff to quiet work.
- `Body/Views/BodyHealthSyncBadge.swift`: session-based display, specific localized labels, dwell, completion, and announcements.
- A small app-local presentation state helper and ordered progress adapter: explicit state transitions and time-dependent decisions, without a general task framework.
- `Body/Localizable.xcstrings`, `Body/Views/BodyCacheRebuildView.swift`, and any other actual shared-stage consumers required by the typed change.
- `BodyTests/HealthKitWorkoutStoreRefreshStageTests.swift`, `BodyTests/LocalizationRuntimeKeyTests.swift`, affected `SourceGuardTests` expectations, and focused coordinator/presentation tests. Replace the hand-enumerated bare enum cases with representative typed-target fixtures; `LocalizedStringKey` equality itself still works, but fixtures must supply associated values.
- `README.md` and `TestPlan.md` for changed behavior and QA. Inspect/update affected `BodyTests/ProjectConfigurationTests.swift` guards in the same implementation change. The user subsequently authorized build 4; update `VersionHistory.md`, current-version documentation, and configuration guards while retaining marketing version 1.1.1.

## Validation and acceptance criteria

Extract a plain presentation state machine with explicit events and an injected monotonic time value; test its settle/dwell decisions directly. The SwiftUI adapter owns cancellable waits and dispatches timed events back with their session key. Add a narrow injectable sleep/clock seam to coordinator scheduling so its actual token handoffs can be exercised deterministically. Reuse `BodyTests/Support/FakeHealthObserver.swift`, `FakeHealthStore`, and temporary-ledger fixture patterns already present in `BodyHealthObservationTests` and `BodyBackgroundRevalidationTests`. This extraction is required scope, not an optional follow-up. Use controlled async events rather than long wall-clock sleeps or source-text assertions.

1. Replay the captured timing: pass finishes; 0.6 seconds elapse; a queued follow-up starts around 1 second later. The badge remains in one visible session, never shows intermediate success, and completes once after the follow-up.
2. Chain two or three follow-ups, including a callback during admission and during another pass. No initial-loading restart, duplicate success, dropped pending state, or blocked refresh slot.
3. Exercise named Stress, Training Load, Readiness, and Body Radar operations; nested fetches and batch callbacks cannot reset their labels. Fast phases coalesce, concurrent callbacks cannot cause label oscillation, and stale owners cannot publish progress.
4. Exercise quiet-only work, no-op admission, redirected quiet work, failed/timed-out follow-ups, cancellation/backgrounding, and context replacement. Assert that a continuation clearing without any `isRefreshing` edge settles the badge, and that cancellation of an old token cannot clear its replacement. Verify full/partial/no-success outcomes, no stuck badge, and no late completion announcement.
5. Run focused XCTest for the affected stage/presentation and observer coordination behavior, then the relevant Body build gate. Report simulator infrastructure failures separately from test failures.
6. On iPhoneAir, attempt a natural launch/resume after at least five minutes of rest and capture both the badge behavior and DEBUG logs, with a VoiceOver pass as well. Verify one continuous badge if an automatic-effort follow-up occurs. Clearly distinguish manual pulls from automatic work. Do not manufacture Health data changes to force reproduction. If no new effort write occurs, report device reproduction as not observed; deterministic tests must still establish the captured chain, no-op settlement, partial failure, and repeated follow-ups. Do not claim a device regression pass from an ordinary clean launch alone.
7. Add minimal DEBUG presentation diagnostics if needed to correlate session IDs, operation changes, pending handoffs, and completion with existing observer pass IDs. Log no health values or source/sample identities. This allows verification of the visible transition, which current refresh logs alone do not record.

Acceptance: the observed single-repeat case becomes one continuous sync with specific operation labels and one honest completion; required reads and acknowledgements still occur. Automated coverage handles multiple follow-ups even if that longer device sequence does not recur during validation.

## Review boundary

The review-only boundary was superseded by the user's instruction to implement the complete plan in one run and set the app build number to 4.

## Implementation and validation record

- `BodySyncPresentation` owns explicit session/pass identities, pending tokens, outcomes, and monotonic settle/dwell deadlines. The view keys its timer on the complete presentation value, including pending membership; a no-op admission can therefore settle without an `isRefreshing` transition.
- Pending ownership uses a set of tokens alongside the latest observable `foregroundContinuationID`. Replacing a sleeping debounce only removes that debounce's token; an older admission, callback capture, or context handoff retains its own claim until its matching cleanup.
- Typed operations cover Readiness, Stress, Training Load, Body Radar, individual metric updates, rings, and neutral concurrent batches. A bounded ordered stream reports detached calculation boundaries without awaiting UI work. DEBUG profiles include the three detached calculation durations.
- Visible outcomes aggregate accepted publication and required failure across passes. Quiet/background work cannot report; backgrounding, cache clearing, and context invalidation retire presentation ownership. The badge announces only final full/partial completion and suppresses a session that was covered by the rebuild UI.
- English and Simplified Chinese complete phrases, README, TestPlan, VersionHistory, and all 12 build-number settings/guards updated for build 4.
- Automated run 1: 49 passed, one background-history deadline failure, and one undispatched stale test-list entry. All 12 new presentation/continuation tests passed, plus stage, observed batch, context, and refresh-timeout coverage. The failed background case's log showed its real-time lease expired during a slow simulator read.
- Automated run 2: 33/33 passed, including that background-history case on rerun, successful/partially failed observed publication assertions, localization, source wiring, and all project configuration checks. No production timeout was changed to accommodate the simulator.
- Final focused rerun after the month-refresh persistence, batch-stage, and calculation-diagnostic edits: 33/33 passed (presentation, continuation, observed quantity batch, refresh timeout). Final physical iPhoneAir build succeeded in 18.45 seconds with no build errors. Launch was blocked by the locked device; Xcode explicitly requested unlocking iPhoneAir. No build-4 natural automatic-effort replay or device calculation timings were captured. The device-interaction tool also rejected physical iPhoneAir and offered simulators only, so physical VoiceOver, Dynamic Type, and visual localization QA remain unverified. The deterministic tests establish the captured continuation behavior; a clean build alone is not a device regression pass.

### Build 4 physical-device capture after unlocking

On September 13, 2026, iPhoneAir successfully launched build 4 under session `a3f31bc00`, PID `18634`, after the user unlocked it. Capture: `/private/tmp/Body-iPhoneAir-build4-sync-20260913.log`.

- 15:44:50.209: one visible session began (`6C89FF42-880C-4ACF-A346-D3608052F0F2`). Displayed stages were fetching, Readiness calculation, updating health data, and finishing.
- 15:44:58.100: the refresh finished without deadline failure in 7.731 seconds. Detached Readiness computation measured 0.151 seconds; no detached Stress/Radar timing was reported in this pass.
- 15:44:58.704: exactly one updated confirmation; 15:45:00.556: hidden. Later quiet Stress-input, trend-history, observer, journal, and record maintenance did not reopen the badge through the captured interval ending 15:45:18.
- The user reported that this refresh looked fine. No automatic-effort write or visible foreground follow-up occurred, so the original automatic-repeat trigger was not reproduced. VoiceOver and visual locale/Dynamic Type checks remain unverified.

## Response to appended review

The comments below are preserved verbatim. These decisions resolve them for the revised draft:

| Comment | Verification and disposition |
| --- | --- |
| R1 | Evaluated the 1.5-second timer option. It probably covers this capture but is not a scheduling guarantee and delays every success. No stopgap release proposed. The 5-second setting caps debounce rescheduling, not each sleep. |
| R2 | Accepted the need for store-observable pending state and a distinct settle edge; specified token replacement, matching cleanup, composite task key, and exit/handoff rules. Corrected the order: `isRefreshing` becomes false before `refreshDidFinish()` runs. The coordinator is plain, and its store reference is not itself an observable signal. |
| R3 | Accepted the cost of reporting detached progress, not deferral of the user's named labels. The detached block has sequential calculation boundaries; the plan now specifies ordered nonblocking reporting. Existing leaf timings cannot prove all calculation stages too short to show. |
| R4 | Corrected: the captured Stress and Training Load leaves were sequential, not one concurrent batch; descriptor-backed batches are limited to three. Specified a neutral batch owner and “Syncing...” during debounce, with no extra ledger lookup. |
| R5 | Accepted that the Bool/counter cannot express complete outcomes. Specified explicit publication/failure reporting and a partial-result confirmation rather than either silently hiding prior success or claiming an unqualified success after failure. |
| R6 | Accepted the reset fix as an explicit first step. It prevents resets while already syncing; it cannot alone prevent a restart after the badge has transitioned to updated. |
| R7 | Accepted mandatory presentation extraction and scheduling time seams. Confirmed fake observer/health-store/ledger fixtures exist. Typed stages require new case fixtures, not abandonment of `LocalizedStringKey` equality. |
| R8 | Accepted catalog punctuation and complete localized phrases. Current badge keys cover `en` and `zh-Hans`; “Calculating scores...” has one catalog key plus its English value, not two distinct catalog entries. Runtime and source guards also reference it. |
| R9 | Accepted explicit VoiceOver validation and separation of visual phase changes from automatic announcements. |
| R10 | Added documentation/configuration guard obligations and the rebuild consumer. `VersionHistory.md` requires an entry on version/build bumps; this plan does not itself authorize a bump. |
| R11 | Accepted limited natural reproducibility. Deterministic tests are required; device reproduction is reported honestly if the trigger does not recur. |

---

## Adversarial review (September 13, 2026)

Reviewed against `HealthKitWorkoutStore.swift`, `BodyHealthChangeCoordinator.swift`, `BodyHealthSyncBadge.swift`, `BodyCacheRebuildView.swift`, and `HealthKitWorkoutStoreRefreshStageTests.swift` on `body-v1.1.1`. Verdict: the diagnosis is right, but the plan skips the cheapest fix, promises stage labels the code cannot produce at real boundaries, and leaves the two hardest mechanics (settling a continuation that never becomes a refresh, and aggregating outcomes) unspecified. Recommend trimming Section 2 heavily and making Section 1 concrete before authorizing work.

### R1. The one-line fix is not evaluated

The badge's falling-edge comment already says a chained follow-up "cancels this (task id flips back to true) and the badge stays in .syncing". The mechanism exists and is mistuned: the badge waits 0.6 s, the coordinator debounce is `foregroundDebounce = 1 s`, and the capture shows a 1.034 s gap. Raising the badge floor above the debounce plus admission latency (about 1.5 s) closes the observed case with no new state. The plan should list this as option A and say why it is rejected. Real reasons exist (`foregroundMaximumWait` lets the debounce stretch to 5 s under repeated deliveries; admission runs two async `configure()` and ledger flushes; every ordinary refresh would show success 0.9 s later), but they must be stated, and this tuning should probably ship first as a stopgap while the larger change is built.

### R2. Section 1 does not say where the state lives or what wakes the badge

The badge observes exactly two things: `isRefreshing` and `refreshStage`. `BodyHealthChangeCoordinator` is a plain class, not `@Observable`, held privately by the store. "Have the coordinator expose scheduled/being-admitted foreground continuation" therefore cannot reach the view without a store-level published property. Note that `finishRefresh()` calls `refreshDidFinish()` synchronously, which calls `scheduleForeground()` synchronously, so at the instant `isRefreshing` flips false the coordinator's `debounce` task already exists. The minimal design is a store-published `hasQueuedForegroundContinuation` (or a session token) that the coordinator sets when it creates the debounce and clears in every exit: quiet routing, `syncWhenAppBecomesActive` taking the `skip`, `freshCache`, `busy`, `context`, or `initialLoad` branch, `repairOnActivation` finding no work, `enteredBackground()`, and the non-foreground exit in `repairObservedMetrics` that bypasses `finishRefresh()`. The plan lists the audit but not the trigger. Critically, the badge's completion task is keyed on `isRefreshing`; a continuation that is dropped without ever starting a refresh changes nothing the badge watches, so the badge sticks in `.syncing` forever. The settle path needs its own observable edge. Name it.

### R3. The label table promises boundaries that do not exist in the code

Readiness, Stress, and Body Radar are recomputed together inside one `Task.detached` in `updateHealthDashboardSnapshot` (line 6874 onward), off the main actor, as a single unit. There is no point at which "Calculating Readiness…" is true and "Calculating Stress…" is not. Producing three labels requires either emitting stage changes from inside the detached compute (a main-actor hop per phase, which the plan forbids as artificial serialization) or lying. With the 0.5 s latest-wins dwell and "fast phases need not appear", most of these labels would never be visible anyway. The full refresh in the capture spent 14 s almost entirely in `.fetching`. Before adopting the taxonomy, read `BodyRefreshProfile` per-leaf timings and keep only labels whose phase reliably exceeds the dwell. Expected survivors: Loading data, Saving workout effort, Updating [metric] for observed passes, Finishing up.

### R4. Concurrent observed reads have no single owner

`performObservedMetrics` fetches every receipt kind in one `withTaskGroup` (line 8898). In the captured follow-up, Stress and Training Load were read concurrently in one batch. "Calculating Stress… including its required inputs" and "Calculating Training Load… including its required workout inputs" cannot both be true, and the plan's "coalesce into one deliberate display choice" gives no rule. Specify it: for a batch, label by a fixed priority (Training Load over Stress over metric), or use a single "Updating health data…" batch label. Also, "Updating Training Load…" during the scheduling gap is not honest: the debounce is asleep and nothing is updating. Keep the current hold-last-label behavior for the gap, or use a neutral "Syncing…". The debounce also does not know its targets until it runs `pending()`; showing a target during the gap needs an extra ledger snapshot at schedule time.

### R5. Outcome aggregation has no failure signal, and the chosen UX may be wrong

The badge decides success by comparing `syncBadgeSuccessCount` before and after. There is no failure counter; `repairObservedMetrics` returns a Bool the badge never sees, and the deadline-abandon path sets `refreshStage = .finishing` directly outside the guard. Section 3 needs a new signal (per-session outcome, or a failure count) and must handle the abandon path. Separately, question the rule itself: if the 14 s full refresh succeeded and the 5 s Training Load follow-up failed, the dashboard did update. Hiding the badge with no confirmation after 20 s of spinner reads as a crash, and the existing `healthDataNotice` already reports the failure. Recommend: session success = at least one visible pass advanced the success count; failures surface through the existing notice. State the choice either way.

### R6. `beginSyncing()` is the restart bug, and it is two lines

`onChange(of: isRefreshing)` calls `beginSyncing()`, which unconditionally resets `pendingStage`, `displayedStage`, and the dwell timestamp to `refreshStage ?? .fetching`. That is the "Loading data…" flash. Guarding the reset with `phase != .syncing` fixes the restart independent of everything else. Call it out as its own step so it is not buried in the session rewrite.

### R7. Testability claims are not backed by the code

The badge uses `Date()` and `Task.sleep` inside SwiftUI `.task` modifiers, with no injectable clock; view `@State` is not reachable from XCTest. Criteria 1 through 4 cannot be met without extracting the phase machine into a plain type with an injected clock. The plan says "only if needed"; it is needed, say so and budget it. Coordinator tests need a `BodyHealthObserving` fake and a ledger file; confirm one exists in `BodyTests` before estimating. The existing `testEveryStageHasBadgeText` enumerates cases by hand and compares `LocalizedStringKey`; a stage with an associated metric kind breaks both the enumeration and the equality check.

### R8. Localization and copy conventions

Existing keys use three periods ("Loading data...") and the plan uses the Unicode ellipsis. Match the catalog. "Updating [localized metric name]…" is a format string with word-order issues in several supported languages; every new key needs entries across all locales in the 426 KB `Localizable.xcstrings`, which the plan does not budget. Check the two existing "Calculating scores..." entries before removing the key. The project rule bans dashes in user-facing copy; none of the proposed strings violate it, keep it that way.

### R9. Accessibility regression risk

The capsule carries `.updatesFrequently` and the label is combined. More label changes means more VoiceOver chatter per refresh; a session that spans two passes with six labels is worse for VoiceOver users than today. Consider suppressing intermediate label announcements and keeping only the completion announcement, and test with VoiceOver on, not just Reduce Motion.

### R10. Missing project obligations

`Expected files` omits `README.md`, `VersionHistory.md`, `TestPlan.md`, and `BodyTests/ProjectConfigurationTests.swift`, which CLAUDE.md requires on any behavior change and version bump. `BodyCacheRebuildView` consumes `badgeText` with a `.fetching` fallback; a typed stage must keep that consumer compiling and meaningful.

### R11. Evidence is n = 1 and reproduction is not under our control

One capture, one restart. The automatic-effort follow-up only occurs when a new workout needs an effort write, so criterion 6 may never fire naturally during validation. Acceptable, but the automated tests then carry the whole claim, which raises the bar on R7.

### Recommended sequencing

1. Ship R6 and the R1 tuning as a small patch with a presentation-helper test. This likely resolves the reported symptom.
2. Then, if still wanted, do Section 1 as a single store-published continuation flag with an explicit settle edge (R2) and the aggregation decision (R5).
3. Defer Section 2 until per-phase timings justify each label (R3, R4). Do not start with the ten-row table.
