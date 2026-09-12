# Design and correctness — revision 2

## 1. Goal and scope

Show cached content immediately; prioritize foreground data; keep historical repair and notification evaluation out of the opening wait. Repair must progress quietly while open and during eligible iOS background opportunities. User actions preempt maintenance. Pending changes are never discarded just to finish the badge.

Use existing full-scope metric reads and domain receipts first. A domain is the initial resumable unit, not a newly invented monthly scan. Shorter reads, date cursors, or anchored invalidation are conditional follow-ups, justified per domain by measurement. Initial-load/rebuild flows retain their explicit UI and real work; no maintenance is admitted until initial data loading completes.

## 2. Verified current mechanisms

| Code | Finding |
| --- | --- |
| HealthKitWorkoutStore.syncWhenAppBecomesActive | Awaits repair and notification evaluation before normal context/initial-load/freshness gates. |
| BodyHealthChangeCoordinator.repairOnActivation | Selects current or history pending; remaining history keeps observedHealthChanges true. |
| performObservedMetrics | Foreground full-scope leaves acknowledge both flags; background leaves acknowledge current only. History acknowledgment currently happens before the final derived recompute. |
| performHealthMetricRefresh | Foreground uses userInitiated retained-intraday reconciliation; passiveResume can use incremental intraday reads. Both may read retained daily history. |
| Background publication | Skips the foreground derived recompute but does publish companions when changed. Absence of derived compute is not proof of absence of publication. |
| HealthKitQueryBudget | Separate logical pools already exist: interactive 10, background 4, appRefresh 2. Ordinary acquire is not cancellation-aware while queued; leased admission is cancellation-aware. |
| BodyHealthQuerying | Scriptable callback leaves explicitly resume cancelled and call stop through BodyQueryResumeBox. Logical completion does not prove healthd has stopped all work. |
| scheduleWorkoutJournalIfNeeded | Automatic journal repair can set isRefreshing and call finishRefresh after activation. This must join quiet ownership to avoid bringing the badge back. |

## 3. Foreground admission and useful coverage

Split ledger current-pending state from history-pending state. A fresh current dashboard with only historical debt follows normal skip/freshness admission, then offers maintenance work. Current pending invalidates the corresponding domain; do not use any-history-pending as a global bypass.

Choose a single foreground plan:
- When ordinary freshness/context requires a full refresh, use that pass and collect coverage from its actual results.
- With otherwise fresh data, refresh affected current domains and necessary dependencies through existing metric fetches. Those reads may include history; Phase A does not promise a cheaper current-only query.
- Hidden but admitted companion domains remain eligible; changes needed by the visible dashboard are prioritized. Preserve current warnings, latest-sample quantity semantics, sleep-session lookback, and source selection.

Capture each receipt after source preparation settles and before the read it owns. Track successful coverage from that point through durable publication. Minimal per-domain coverage evidence is required; a replacement query engine is not.

After a successful foreground or explicit detail/manual refresh, acknowledge current and any history actually covered. An ordinary refresh that skips retained intraday reconciliation must not acknowledge it. Cache reuse, partial failures, skipped leaves, and a process-wide success flag are insufficient. Readiness/training-load/stress coverage must retain their existing dependency semantics. A delivery after read admission survives the older result.

At completion, update current freshness independently of remaining history. Do not launch a second full refresh simply because old history remains. Keep actual initial-load, source-change, cache-clear, and authorization behavior.

## 4. Quiet maintenance ownership and query budgets

Retain one metric maintenance task in the existing coordinator. Add a distinct operation purpose/token and owned cleanup. Do not call the existing repair entry point unchanged: it sets visible state, uses a different pool by default, and has completion side effects.

Quiet work binds withBackgroundQueryPool around its entire query path, including source preparation. It does not hold interactive permits or set isRefreshing/refreshStage. BGTask work retains its real lease and appRefresh pool; do not fabricate a lease to bypass foreground checks.

A new foreground operation invalidates the quiet token before cancellation and starts without awaiting the retired task's HealthKit callback. Preserve immutable captured requests and input revisions. Audit mutable source setup, training-load anchor/cache operations, compute, merge, queued disk writes, Watch/widgets, and notification sends; fencing only the last assignment is insufficient.

Use existing callback cancellation; add cancellation-aware waiter removal for the quiet paths if they can otherwise remain queued. Do not artificially release a permit twice or assume all query sites use the callback wrapper. Isolated background permits let an uncooperative old background read remain accounted for without blocking interactive admission.

Budgets describe application admission, not a provable hard count of healthd's physical work. Source discovery already fans multiple queries under one permit. Do not raise pool limits. Bound retired work to one unfinished quiet owner and do not repeatedly replace it with fresh quiet owners while it is stuck; foreground operations may proceed on their separate pool. Instrument cancellation/late completions and contention. This removes application-level waits, not all competition inside HealthKit.

Publication stays serialized and revision-fenced. Expensive compute uses the existing off-main facilities; utility task priority alone does not make MainActor work cheap. Maintenance cleanup must not release a newer owner's slot or run ordinary finishRefresh hooks recursively.

## 5. Explicit admission and fairness

Use a small admission arbiter in the existing store/coordinator, not another periodic scheduler. A retained task handle is not equivalent to owning a unit.

Foreground priority: cache clear/permission/context transactions and initial load, then explicit user refresh/current activation work. These suspend maintenance admission.

Quiet admission requires foreground active, initial load complete, protected data available, eligible existing authorization-request state, no foreground operation/transaction, no current maintenance unit, and no unfinished retired quiet owner. It does not require every historical task handle to be nil.

Rotate ready maintenance owners after each durable unit, in this initial order: observer metric repair, workout journal repair, record repair/baseline, stress input load, stress history, ring history, full trend history. Skip absent/failed owners and unmet dependencies; stress history waits for its own required inputs and preserves its chronological robust-baseline algorithm. It does not depend on completion of the all-time workout record ledger: the former record-task gate serialized contention rather than a data prerequisite. Ring/trend follow-ups join the rotation because integration testing exposed automatic ring admission preempting the journal owner. Repeated callbacks update pending state, not queue position. Within observer work rotate domains; capture the latest receipt immediately before each domain's read.

Units reuse existing boundaries: one full metric read; one journal scan page or repair month; one existing record chunk; one existing stress input batch or history chunk. Adapt existing loops to yield admission at those boundaries while keeping their storage/progress formats. No unit receives unlimited ownership merely because its task remains alive. Pending-work fairness is bounded in successful eligible turns, not seconds if HealthKit hangs.

Use one completion offer function from foreground completion, maintenance completion, activation skip, and existing owner exits. Do not depend on isRefreshing to serialize quiet writers, nor await one background task from another. An existing unit can finish or be fenced before the next acquires ownership. Read-only late completions never regain publication rights.

A failed domain is attempted once per external opportunity for that generation; offer other ready domains and stop self-retrying it. Retry on activation, new delivery, manual refresh, relevant dependency completion, or BGTask. No retry ladder and no one-second polling of a busy foreground owner.

## 6. Domain-level progress, generation changes, and persistence

Keep ledger schema 2 and existing current/history flags in Phases A/B. Fully repaired domains acknowledge durably and drop from pending work. Interrupted/failed domains remain pending. Stress/workout/record cursors remain with their existing owners.

New generations invalidate old acknowledgments but do not reset completed work for unrelated domains. Keep one full-scope read per affected metric, avoiding a multi-month cursor that restarts on each Watch burst. Capture close to query admission rather than reusing an entire pass's obsolete receipts.

This reduces starvation risk; it cannot guarantee convergence under continuous changes faster than a valid read. Do not replace full history with a recent 7–14-day window: undated callbacks can represent older edits/deletions. If stable opportunities still cannot complete a domain, measurement gates a targeted split or anchored design before claiming that domain solved.

Save the payload before acknowledging its receipt. Preserve ordering across dashboard and intraday sidecars. A crash between payload and ledger repeats work safely; failed writes cannot clear pending flags. Start with no more than existing per-domain saves/acks. Measure writes/bytes/time and coalesce derived recompute and companion publication across completed domains; do not multiply writes through speculative date units.

If Phase C later requires progress, first consider an optional versioned schema-2 field with unchanged required fields. Older decoders can ignore it, but their next save loses it; all pending flags must survive. Any incompatible schema requires an explicit migration/rollback design. No progress field is proposed now.

## 7. Background history remains required

Phase A preserves the existing BGTask current/periodic behavior while quiet foreground routing is verified. Phase B adds selection of history-only receipts using remaining lease after existing current/notification/workout priorities. Keeping background history permanently disabled would not meet the agreed goal.

Use the same full metric coverage as quiet repair when it can finish within the lease. Explicitly request needed retained intraday reconciliation; never clear history solely because the background leaf returned success. Complete required derived publication under a valid owner before stamping it validated; if the dependency/compute/save cannot finish safely headless, leave its obligation pending for quiet foreground completion. Raw accessible data can still be published under its own coverage.

Finish one domain before attempting another. On expiry retain unfinished receipts, preserve completed acknowledgments, and reject late writes. Do not extend the lease, manufacture new dirty work for periodic staleness, or put long history ahead of notifications. A domain repeatedly exceeding the available lease may still complete quietly foregrounded; report that limitation, and consider measured splitting in Phase C rather than claiming it is background-resumable internally.

## 8. Freshness, notification timing, and empty results

Current validation, retained data coverage, and derived validity are distinct. Preserve last available values until coherent recomputation. Quiet repair must not mint global refresh success or newer derived/Watch timestamps from incomplete dependencies. Audit current watermark consumers and retain their meanings; derive validity from the existing durable inputs/revisions where possible. If extra durable debt is necessary, specify the smallest representation before enabling that domain.

One retained, coalesced foreground notification task runs after eligible current/dependency publication, including a valid-cache activation. It does not delay the foreground completion. Deliveries during evaluation request one follow-up, not parallel evaluations. Preserve consent, deduplication, cancellation, and send-time input validity; do not allow an old unstructured child to send after retirement. Background ordering remains as today.

HealthKit does not reveal read denial through sharing authorization or request status. Source discovery and neighboring samples are not proof of full read authorization; an app can still read its own samples when other data is hidden. See [Apple's authorization semantics](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus).

Phases A/B preserve existing successful-empty versus failed-query semantics. A successful scoped query describes data currently accessible to the app; replacement of cached series is not proof that hidden HealthKit samples were deleted. Failures/lock/cancellation are not authoritative empty. Do not add a new permission-detection heuristic or a new interval-deletion policy in a scheduling fix. Known limited-access bounds, where supported, mean earlier history is unknown, not empty; avoid widening that behavior in this change. A future finer-grained deletion/cache-retention policy needs explicit design for both genuine deletions and privacy-driven omissions.
