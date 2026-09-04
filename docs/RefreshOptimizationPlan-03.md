# Refresh Optimization Plan 03

Data-path refinement: correctness first, then durable reuse, freshness scheduling, and only the structural changes those require.

> **Status (2026-09-04): Review complete. Implementation Phase 1 authorized and in progress; later phases await approval.**
> Reviewed baseline: `ee65d15`; working tree was clean at entry. References below are to this revision, not RP-01/RP-02's line numbers. `Store` means `Body/Services/HealthKitWorkoutStore.swift`; `Engine` means `Body/Services/HealthKitFetchEngine.swift`.
> Method: CodeGraph first for the named orchestration, fetch, persistence, compute, consumer, and test seams. Several responses returned unrelated symbols or omitted the requested bodies; targeted source reads filled those specific gaps. Findings are static source proofs or explicitly labeled inferences, not claims of reproduced device failures.
> Performance: no new timing baseline is available. The unsandboxed device inventory reports both iPhones unavailable; the connected iPad is not an established RP-02 reference device/Health database. No speed estimate from RP-02 is carried forward. See §6.
> Adversarial review: completed by a separate read-only agent on 2026-09-04. Verified corrections are folded in and listed in §8. The reviewer made no file changes.

## 1. Findings, ranked by correctness and value

### F1 — HIGH: context changes can preserve old-source trends and stamp them as current

**Evidence.** `Store:3693` (`updateHealthDataSource`) changes the stored selection and engine selection before waiting for the running refresh; the default-source and group/combine paths have the same ordering (`Store:3622`, `:3603`, `:3444`). The corrective source refresh strips intraday samples, not the corresponding daily trends. In `fetchDashboardSnapshotProgressively` (`Store:5085`), the context signature gates summary fallback and the short trend window, but `cachedTrendsAtStart` is passed to `fetchHealthTrends` even on a signature mismatch. `Engine:3803` resolves a failed daily leaf with its cached series unconditionally. Finally, `updateHealthDashboardSnapshot` captures inputs before detached compute (`Store:5897`) but checks only `cacheEpoch` and the refresh generation at `:5983`; `:5993` stamps the *current* context signature after the await.

**Failure A, no concurrency required:** cached HRV daily trend from source A → select B → B trend query fails → engine returns A's cached trend → final publish stamps B → A's trend can feed readiness and survive on disk as B. The summary has a mismatch gate; the trend does not. A later successful full-window B fetch repairs it, but repeated failures do not.

**Failure B, interleaving:** A's queries or detached compute are suspended → source/group/permission changes → A completes → the unchanged refresh/cache generations admit A's payload and the new signature. The queued corrective refresh helps only if it subsequently succeeds. Disabling a permission can also race the detached filter captured before the disable (`updateHealthPermission`, `Store:3190`); the disable path has no corrective full refresh.

**Confidence:** high for the source-failure fallback; high for the missing commit-context guard, with the exact interleaving to reproduce using suspended fetch/compute barriers. This is not a claim that every source change fails.

**P1, proposed change.** Introduce a small immutable fetch/compute context covering query-affecting selections, effective source/group resolution, permission selection, sleep parsing preferences, and calendar aggregation identity, plus compute-affecting preferences such as the sleep goal, calculator version, and effective layout/Radar enablement. Fetch and compute compatibility may be separate projections so a sleep-goal change does not refetch raw HR. Capture the appropriate context before dispatch, carry it with results, and require equality at every progressive/final publication and persistence admission. Advance the revision synchronously on context changes, before the first await. Keep `cacheEpoch` for destructive cache resets and the refresh generation for abandonment; they are different fences. Filter cached *daily and intraday* fallback by its captured scope before dispatch. On a source mismatch, use no old-source fallback for affected leaves. Do not stamp an entire snapshot as current when some carried fields have another scope. Coalesce a corrective refresh under the latest context without delaying the settings interaction.

**Cost/risk.** Medium, spans entry points and publication guards. Overbroad invalidation can blank unrelated cards; use per-kind compatibility for cached values and one revision to reject in-flight work. Do not solve this by serializing the fast summary behind trends or by moving the whole store to a new architecture.

**Verification.** Extend `HealthKitFetchEngineFailureSemanticsTests`, source-resolution tests, and store integration tests with A→B plus B failure, group membership edit during query, permission disable during detached compute, and timeout followed by a new-context refresh. Check Home, persisted reload, widget input, watch input, and readiness inputs. A stale result must neither publish nor advance freshness. Source display-name-only changes must remain harmless.

### F2 — HIGH: ring progress and refresh freshness can outrun durable payloads

**Evidence.** `landActivityRingBackfillChunk` (`Store:5331`) applies a chunk, calls `persistActivityRingHistory`, then writes the resume point to UserDefaults (`:5345`). `persistActivityRingHistory` (`Store:5400`) only enqueues the snapshot save. The terminal backfill state is also saved before the final history save (`Store:5291`). Dashboard success is persisted by `markRefreshSucceeded` (`Store:6427`, success branch at `:6486`) before the deferred dashboard write at the end of `refreshRecentMonths` (`Store:4939`). `HealthDashboardSnapshotStore.save` (`Body/Services/HealthDashboardSnapshotStore.swift:241`) returns `Bool`, conflating unchanged data with a failed write.

**Failure:** ring chunk covering an old year lands → its checkpoint advances → process exits before the queue writes, or the atomic write fails → relaunch reads an older payload with a newer checkpoint → the skipped year is not queried again. A prematurely durable `completed` marker is worse: normal later refreshes only query recent rings. Separately, a successful dashboard fetch followed by a failed/deferred disk save can leave a fresh five-minute timestamp beside an old dashboard on relaunch.

**Confidence:** high for ordering and unchecked write failure; process-kill timing is an inferred reproducer. Per-file atomic writes are intact. The defect is metadata/payload consistency, not file truncation.

**P2, proposed change.** Put ring checkpoint/completion state and dashboard freshness metadata in the same versioned persisted dashboard envelope as the payload they describe. Migrate legacy UserDefaults progress conservatively: preserve existing history but restart an unprovable walk, with bounded queries. A save outcome must distinguish written, unchanged-and-valid, and failed; only the first two can acknowledge durability. Keep live success separate from durable success so progressive UI publication does not wait for disk. Fold the secondary-selection stamp into the envelope as well; it currently lives separately from the trends it qualifies. Keep the day-sample sidecar separate and independently scoped; this proposal does not require a cross-file transaction for every raw sample.

Report main-envelope and sidecar outcomes separately. The main file is written before the sidecar (`HealthDashboardSnapshotStore.swift:290`); main success must not clear raw-sample dirty coverage or acknowledge an authoritative-empty repair when the sidecar failed. A later sidecar retry may complete that repair without refetching a successfully captured payload, provided its context and input revision still match. Test both partial-write directions and reload behavior. Main-envelope completeness must not claim raw inputs were durably validated merely because a derived display value was saved.

**Invalidation key:** envelope schema, captured context revision/signatures, payload revision, and ring coverage/checkpoint carried together. Missing/legacy metadata means unverified coverage, never completed by assumption.

**Repair:** a legacy or inconsistent marker causes a resumable reconciliation without deleting existing months. A failed write retains the prior envelope and retries. Clear Cache remains an explicit complete rebuild, never the only way to recover skipped chunks.

**Cost of being wrong:** missing historical rings and false cold-start freshness; this can also defer correct derived-score inputs. Do not use a durable timestamp to authorize notifications.

**Cost/risk/verification.** Medium. Migration must not discard history or turn a sidecar failure into a destructive empty save. Inject encode/write failure and pause the persist queue between chunk arrival and write; reload at each boundary. Verify checkpoint never exceeds committed coverage, terminal completion is atomic with the final history, unchanged saves can acknowledge valid coverage, and a failed dashboard write does not arm cold-start freshness. Extend dashboard persistence, day-sample, ring chunk, and save-dedupe tests.

### F3 — HIGH value: age and loaded-state are not mutation detection

Three distinct artifacts share this problem; they need different repair boundaries.

| Artifact | Evidence | Concrete failure and existing repair |
| --- | --- | --- |
| Intraday sample sidecar | `HealthKitFetchEngine+IntradaySamples.swift:63,73,91`; `Engine:3957,3999` | Delete or backfill a sample seven days ago while the latest cached point is today. The 48-hour overlap never visits that day, so detail pull still shows the old sample or misses the new one. Daily statistics may be correct at the same time. Clear Cache repairs it; hourly cumulative paths have separate full-window handling and are not all subject to this exact failure. |
| Effort ledger | `Engine:333,356,420,477,2739`; `WorkoutEffortLedgerStore.swift:21` | Edit an effort score on a five-month-old workout. The 408-day training-load workout read sees the workout, but the aged UUID's cached effort is reused across launches. Home pull only clears its requested months. Training Load detail pull performs a full effort clear; pulling that workout's month or Clear Cache also repairs it. Merely opening an already-loaded month does not prove repair. |
| Month snapshots and all-time records | `Store:4351,5555,5596`; `HealthKitWorkoutStore+Records.swift:68,105,207` | Delete the record-holder from a previously loaded old month. `loadedMonthKeys` prevents another lazy read; the one-time completed record baseline does not rescan. The stale PR can remain until the affected month is explicitly refreshed or the cache is rebuilt. A fresh authoritative month *does* remove absent record UUIDs. |

**Confidence:** high. These are explicit reuse policies, not speculative query costs. The effort ledger already has a full reconcile path; the plan must not claim reinstall is required.

**Additional verified durability defect:** `HealthDashboardSnapshotStore.swift:310` preserves a populated sidecar when an incoming all-empty payload has matching scope. That protects pre-hydration saves but cannot distinguish them from an authoritative successful read that removed the final samples. In the latter case memory becomes empty while disk retains deleted samples, which can hydrate on relaunch. A full raw repair must fix this distinction, not merely widen its query.

**P3, proposed immediate repair.** Give explicit metric refresh a full retained-window reconciliation for sample-based intraday data, replacing only successfully queried coverage. Retain the 48-hour overlap for passive refresh. Add bounded freshness to existing effort entries and loaded workout months: store validation time independently of `generatedAt` (unchanged-content saves intentionally preserve that timestamp). Proposed conservative initial policy: aged effort entries revalidate after 24 hours, visible loaded months revalidate on resume after five minutes; clocks moving backward mean stale. Failures retain values without advancing validation. For all-time records and old rings, schedule a rolling bounded historical repair sweep instead of treating a completed baseline as proof of immutability; checkpoint it using P2's durability rule. Foreground work still takes priority.

Give sidecar persistence explicit per-series write intent/authoritative coverage: not loaded, failed, or successful (including empty). Successful empty coverage must clear those persisted samples; unhydrated or failed coverage must preserve them. This also permits safe scoped saves without interpreting a default empty series as a deletion. Test deleting the final samples, saving, and relaunching, as well as a pre-hydration save that must retain history.

**Invalidation key:** per-artifact context/schema plus last successful authoritative coverage check; for effort, UUID and workout dates plus validation date. This is bounded staleness, not exact mutation detection. P6 later adds dirty generations/anchors. A successfully empty queried interval must remove absent cached values; a failed read must not.

**Repair:** metric pull reconciles its retained raw window; Training Load pull reconciles all effort inputs; month pull reconciles that month's membership and record contributions. Rolling history repair must revisit already-scanned history. Clear Cache remains the broad fallback. Do not clear unrelated metrics or delete original HealthKit samples.

**Cost of being wrong:** intraday disagreement can affect stress baselines, effort staleness affects training load/readiness, and an old workout can misstate records. Ring counts/PR badges are display errors; cached score inputs must not be promoted to freshly validated data for downstream consumers.

**Cost/risk.** Medium. Reconciliation deliberately does more work in repair paths; no speed claim. The 24-hour policy bounds effort staleness only while the app is active often enough to run it. The historical sweep has no promised completion time while iOS denies execution. Track successful coverage, not just visits. Do not re-run full ten-year scans at each launch.

**Verification.** Fake-store add/delete/late-arrival scripts at 47 hours, 49 hours, seven days, five months, and a prior year; same UUID with changed effort; failed and successful-empty reads; relaunch; clock rollback; source change. Assert explicit pulls repair within their stated scope, passive policies expire, and record deletion reconciliation removes only absent UUIDs in the queried interval.

### F4 — MEDIUM: source discovery can stay stale for the process lifetime

**Evidence.** `HealthKitFetchEngine+SourceOptions.swift:79` skips discovery once permission raw value matches and the map is nonempty. `Engine:324` clears this cache; combine/group membership edits do so, but ordinary Home/metric pulls do not. `discoverHealthSources` (`+SourceOptions.swift:150`) also skips already-present kinds.

**Failure:** discover a combined-name source containing device A → a second same-name device B begins writing in the same app process → the selected group still resolves through A's old map → B's samples are omitted. All Sources queries do not have this particular predicate problem, but the source picker can still miss B. Restart or a cache/group reset repairs discovery.

**P4, proposed change.** Give discovery an explicit force/dirty/expiry policy, invoked by user-initiated source/metric repair and after the observed type changes. Refresh group membership before dependent leaf queries. Use a conservative 24-hour successful-discovery expiry as a fallback, independent of Body's permission string. Failures retain prior maps but keep discovery dirty. A changed resolved membership must invalidate matching artifacts even when the user's selected ID is unchanged (P1).

**Cost/risk/verification.** Small to medium, bounded extra source queries. No additional persisted source cache is proposed: it would require the same external-change detection anyway. Script changing source lists with stable preferences, partial discovery failure, deleted last source, and a rename-only custom-group edit. Confirm resolved source sets, dependent trends, and watch source expectations change together.

### F5 — MEDIUM, high confidence in key omission: daily aggregate cache identity omits time zone

**Evidence.** `currentPrimarySummarySignature` (`Store:5465`) has sources, permissions, combine/group and sleep parsing flags, but no calendar/time zone. The sidecar signature (`Store:5522`; `BodyMetricsKit/HealthTrend.swift:1240`) similarly has no aggregation zone. Daily statistics receive the current calendar (`Engine:1351`), while phase-one merge retains pre-window points (`Engine:896`). `Calendar.bodyGregorian` is rebuilt when the current zone ID changes (`BodyMetricsKit/WorkoutMonthSnapshot.swift:397`). Workout grouping already has an instant-scoped time-zone ledger (`Store:5657`; `BodyTimeZoneLedger.swift:99`), which must be preserved.

**Failure:** cache daily HRV buckets in New York → move to Los Angeles without changing selections → phase one merges newly bucketed recent days with old-zone historical buckets → chart/day matching and readiness baselines temporarily mix aggregation contexts. If phase two fails, the mixture lasts longer. A full successful year reconciliation repairs daily aggregates. This is an inference from bucket identity and merge logic, not a claim that the existing travel-day workout or sleep metadata logic is broken.

**P5, proposed change.** Add calendar identifier/time-zone ID and aggregation-policy version to *calendar-bucketed* artifact identity. On a zone change, retain instant-valued raw samples, invalidate/rebuild affected daily/hourly aggregate coverage, and recompute current derived state before labeling it current. Do not globally discard the workout time-zone ledger or move historical workout date keys to today's zone. Source metadata and sleep wake-day policies remain authoritative in their existing domains. Day rollover should invalidate today's summaries independently of a five-minute elapsed-time TTL.

Do not append the aggregation-zone key to frozen readiness/Radar observation reset signatures. Those signatures trigger wholesale record clearing (`HealthSummarySnapshot.swift:788,1043`), which is a different product behavior. Preserve frozen observations and their original day attribution; the new zone key governs recomputable aggregates and current calculation admission. A change to frozen-observation attribution itself would require a separately reviewed plan.

**Invalidation key:** captured calendar/time zone/aggregation version, plus ordinary source and input revisions; raw timestamps do not become invalid merely because the display zone changes.

**Repair:** scope mismatch queues full aggregate reconciliation with existing raw data reused where mathematically equivalent; explicit metric pull forces that reconciliation; failed reads remain unverified. No history deletion.

**Cost of being wrong:** misbucketed charts and changed derived baselines, higher consequence than formatting. Cost/risk medium: re-bucketing raw instants is cheap relative to fetching, but a statistics-only historical cache cannot be re-bucketed exactly without querying HealthKit.

**Verification.** NY↔LA and UTC±date-line transitions, DST 23/25-hour days, a change while phase one is suspended, midnight inside the five-minute TTL, and a failed phase-two fetch. Retain existing `BodyTimeZoneLedgerTests` and workout travel tests; verify daily trends separately from historical workout attribution.

### F6 — MEDIUM: one unrelated trend failure blocks all historical reconciliation

**Evidence.** `loadFullTrendWindow` (`Store:3043`) requires `!result.hadQueryFailure` before applying any full-window series. The aggregate failure includes secondary leaves and sleep-vital hydration (`Engine:3802,3840`). Phase one still merges older cached primary data. `mergeWindowedTrend` retains every point before the merge boundary, with no separate oldest-retained cutoff (`Engine:904`).

**Failure:** old primary steps changed → recent phase one cannot see the change → full steps query succeeds but an unrelated comparison source repeatedly fails → the whole phase-two result is discarded → old steps never reconcile through this path. Repeated short-window merges can also retain points beyond the nominal full-window horizon until a successful replacement occurs. A same-context explicit full metric pull repairs that metric today.

**P6a, proposed change.** Carry per-leaf outcome and successful coverage through the trend result, so phase two replaces successful compatible leaves while leaving failed ones dirty. Preserve live intraday/frozen fields as `applyingFullWindowTrendSeries` already does. Bound retained *rolling* trends to their documented retention interval; this must not prune recorded observations or unrelated ring/workout history. Require context and data-revision equality at admission, not only equality of `lastSuccessfulRefreshDate`: a failed or partial concurrent refresh can change data without advancing that timestamp.

**Cost/risk/verification.** Medium. Avoid teaching every consumer a new result algebra: metadata belongs at fetch/merge/admission boundaries. Test successful primary plus failed secondary, sleep-vital partial failure, a concurrent partial refresh, and data older than the nominal window. Assert early summary paint and per-month streaming remain, corrected primaries persist, failed leaves retain their own compatible cache, and no whole-snapshot replacement discards concurrent stress inputs.

### F7 — MEDIUM: background warning evaluation holds stale state across awaits

**Evidence.** `MetricWarningBackgroundEvaluator.swift:66` checks the master switch, selected kinds, and foreground status before awaited settings/query work. At `:103` it holds a local ledger across `postNotification`; `seed(kinds:)` can modify the actor's persisted ledger while the notification add suspends. The evaluator writes its older ledger copy afterward (`:118`). Stable kind/day request IDs (`:214`) reduce duplicate request identity, but do not prevent lost ledger updates. The previously reported unenforceable deadline is fixed: `fetchWarnings` now uses `OneShotDeadlineRace` (`:159`).

**Failure:** background evaluation starts enabled → user disables notifications/changes thresholds or sources while fetch is pending → old event is still submitted. Or foreground seeds kind B while background posts kind A → background saves its pre-seed ledger → B's suppression record is lost. Duplicate alert behavior depends on notification-center delivery timing; the lost update itself follows from actor reentrancy.

**P7, proposed change.** Capture an evaluation settings/context revision and recheck it, cancellation, enabled kinds, and foreground status immediately before each add. Reload and merge the ledger after the awaited add rather than writing a stale copy; reserve an in-flight kind/day on the actor if overlapping evaluations are permitted. A notification already handed to the system cannot be recalled by a later pre-submit guard; define the guarantee at submission. Keep warnings on fresh event queries. Current warnings are low/high HR and low oxygen, not readiness notifications.

**Cost/risk/verification.** Small, one evaluator and a notification-submission test seam. Suspend before submission and during add; toggle master/kind/threshold/source, seed another kind, cancel, and start a second evaluation. Assert stale events are not submitted after a pre-submit change and unrelated ledger entries survive. Do not mark notified on failed delivery.

## 2. Persist more, load less: verdict and bounded expansion

The app already persists the expensive reusable outputs: dashboard/daily trends, intraday sidecar, multiple workout months, settled workout details, effort outcomes, record contributions, stress history, and frozen readiness/Radar observations. The immediate opportunity is making those caches *verifiably reusable*. A new blob without invalidation would duplicate the current weaknesses.

### P6b — Reopen anchors as mutation detection; retain statistics aggregation

RP-02's rejection was appropriate for replacing statistics queries with client aggregation to save seconds. It is too broad for this pass. Anchors can identify changes that invalidate a cached statistical bucket without replacing `HKStatisticsCollectionQuery` as its authoritative calculator. Apple documents anchored additions/deletions and observer notifications as separate mechanisms: [anchored queries](https://developer.apple.com/documentation/healthkit/executing-anchored-object-queries), [observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries).

**Proposed first scope:** a bounded workout change journal and canonical workout input cache; no high-frequency raw HR mirror. Consume additions/deletions, dirty affected workout months, effort outcomes, record contributions, and dependent training-load/readiness inputs. A deletion supplies identity; preserve UUID→interval metadata so it can invalidate the old interval. If that mapping is absent, conservatively dirty the retained dependency window and the record baseline. Do not assume a workout anchor observes edits to related effort or HR samples: those types need their own change signals or P3's revalidation policy. Keep the effort TTL/full-pull repair even after workout anchors land.

**Anchor scope:** query type, fixed predicate definition/version, store-local installation identity, and schema. Do not reuse an anchor against a moving `now − 408 days` predicate. Start with a fixed lower-bound journal epoch; advancing retention is a separate prune/rebootstrap operation. Bound batches and commit between them. A schema/scope change or rejected/unreadable anchor triggers bootstrap; an empty incremental result is not proof that read authorization is still granted. HealthKit does not expose ordinary read permission as a reliable yes/no status: [authorization guidance](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

**Commit rule:** write delta effects and new anchor in one atomic journal envelope, or persist the dirty work and anchor atomically before acknowledging the batch. Never advance the anchor first. Replayed UUID updates/deletes must be idempotent. Mark an artifact clean only after its recomputation and durable write succeed under the same revision. On suspension/deadline, retain the durable dirty work and retry; a partially applied batch must not become a complete cache.

**Invalidation key:** journal schema/query scope and anchor generation; canonical workout UUID revisions; independent effort validation revision; permissions/source/calendar/calculator versions for derived payloads. No content hash computed only from yesterday's cache can detect a HealthKit edit.

**Repair:** discard the cursor, not user history, then bootstrap into a temporary generation and reconcile covered intervals. Unknown deletions dirty the full relevant window. Explicit Training Load/month pull bypasses delta trust. Clear Cache deletes the rebuildable journal and restarts it. Keep a periodic full reconciliation because permission changes and interrupted/unsupported delivery cannot be inferred from an empty delta alone.

**Cost of being wrong:** missed deletion could retain a record or incorrect training load and readiness. Thus new journal validity cannot by itself advance watch `dataThrough`; all input dependencies must have validated coverage. No cached journal authorizes warning notifications or automatic effort writes.

**Cost/risk/verification.** High relative to the earlier fixes: new persistent protocol and HealthKit seam, not a small query swap. Extend `BodyHealthQuerying`/`FakeHealthStore` with scriptable anchored batches, deletions, anchor failures, and cancellation; do not fake only `execute(HKQuery)` counts. Test first bootstrap, multi-batch replay, delete-before-mapping, kill after every commit boundary, invalid anchor, denied/empty reads, and mutation during reconciliation. Device verification is mandatory. Implement only after P1/P2/P3/P6a and the baseline gate. If the device experiment cannot establish safe mutation coverage, stop and revise this step with the user; do not silently substitute UUID union merging.

### P8 — Conditional durable training-load inputs, not another derived-score cache

`HealthKitFetchEngine+TrainingLoad.swift:34,81,104,130` already shares one in-flight workout fetch across summary, series, and watch daily-load seed. It still fetches a 408-day window each refresh. Persisted month snapshots alone do not establish complete coverage for that window, and their downsampled/detail-enriched shape is not a replacement for canonical compute inputs.

**Proposal, conditional on P6b correctness and §6 measurement:** retain the minimal canonical workout fields needed by `TrainingLoadCalculator`, with independently validated effort outcomes and an explicit covered interval. Reuse that cache to derive summary, series, and watch seed when complete and clean. Do not persist another readiness/stress result merely to avoid an unmeasured recompute. Raw workout objects and routes are unnecessary for this artifact.

**Invalidation key:** canonical workout journal revision, effort revision/validation expiry, complete 408-day coverage, calculator version, calendar and permission context. New current-day boundaries advance the requested coverage. Any dirty dependency prevents a claim of fresh reuse.

**Repair:** explicit Training Load refresh re-fetches/revalidates its complete input window; missing/corrupt/incompatible coverage falls back to the existing shared query and replaces only covered inputs after success. Bootstrap does not delete usable month history. Periodic full audit checks delta correctness.

**Cost of being wrong:** stale training load propagates to readiness and the watch compute seed, so a stale display may remain available with its old watermark, but cannot be advertised as freshly validated or used to bypass write-time checks.

**Cost/risk/verification.** Medium after P6b; otherwise high and not justified. Dual-run existing query-derived versus cache-derived daily loads on identical fixtures and on-device data, including removed/re-rated workouts, complete empty days, midnight, and no workout permission. Require identical inputs/results and measured reduction in queries/launch cost before switching the production path. This is a conditional follow-on, not approval to infer completeness from six month files.

### Persistence proposals deliberately not selected

- **More dense workout HR/route data:** the detail cache already persists settled routes, splits, metric series and recovery; dense HR is session-only (`BodyWorkoutDetailCacheStore.swift:72`). No measured reason to add another large sidecar. Its independent sample mutation and permission invalidation costs are unresolved for a net benefit.
- **Persisted source discovery maps:** cheap correctness invalidation must precede this; current session latch is already too strong (F4).
- **Replace sleep summary with history's latest day:** still not equivalent. Summary and historical sleep have different vital/session and failure semantics. Keep their independent early publication; no coupling to the slow bucket.
- **Automatically rewrite frozen morning observations:** intentionally not selected. Readiness overlay (`HealthSummarySnapshot.swift:771`) and Radar freeze (`BodyRadarCalculator.swift:72,177`) are product contracts, covered by `TestPlan.md` M55/M64/M358. A changed historical HealthKit sample can disagree with an observation recorded that morning without violating that contract. Source/context changes already reset these records. Preserve that distinction in tests and repair UI; do not silently turn the feature into retrospectively recalculated history. Historical stress, which is recomputed data rather than a once-per-morning verdict, does need dirty-window repair through P3/P6b. Reconstructing discarded morning observations after Clear Cache is inherently impossible; never describe Clear Cache as a lossless restore of those observations.

## 3. Freshness and when work happens

### P9 — Observer-driven invalidation plus bounded refresh scheduling

**Current state.** No phone observer/anchored/background-delivery implementation was found in `Body` or `BodyWatchSnapshotKit`. `BodyBackgroundRefreshScheduler.swift:51,71` schedules a 30-minute-earliest task only when warning notifications are enabled and executes `MetricWarningBackgroundEvaluator`; it does not refresh dashboard/widget snapshots. Its one-shot completion and expiration handling are useful existing mechanisms. `syncWhenAppBecomesActive` (`Store:4205`) uses 60-second debounce / 300-second dashboard freshness and current-month-only warm refresh.

**Failure/freshness gap:** a new sleep/workout/sample arrives while Body is backgrounded → warning BG task, even if it runs, does not update Home/widget data → user resumes inside the TTL and receives only the workout path, or no refresh inside 60 seconds. No signal overrides the time gate. This is a policy limitation, not a claim of a missed OS delivery that Body registered for.

**Proposal.** Install observers at app launch, initially for the types covered by the reconciliation design. Their job is to persist coalesced dirty generations and request bounded work; they are not a second dashboard store. Foreground dirty kinds/context/day changes override the debounce/TTL. A refresh that was already running must leave a pending follow-up if it did not cover the newest dirty generation. Keep user pull as an explicit repair intent. A normal clean resume keeps the current policy until measurement supports changing it.

For background delivery, enable only supported/needed types and use the required entitlement/lifecycle setup. Route bounded reconciliation through a single owner, using the background query pool and a task budget below the OS expiration window. Do not run the foreground 120-second pipeline blindly in a background callback. Persist dirty work if the device is locked, a query fails, or execution expires. Complete each observer delivery exactly once after its change has been safely accounted for, including error paths, without waiting for unrelated history walks. Do not claim delivery is immediate or guaranteed. Apple explicitly requires completion handling and real-device testing for background queries: [observer lifecycle](https://developer.apple.com/documentation/healthkit/executing-observer-queries).

Keep warning scheduling independent: disabling notifications must not disable data invalidation. If a BGAppRefresh reconciliation fallback is added, give it an explicit separate responsibility from warning evaluation; do not make notification opt-in a hidden dashboard-freshness toggle. Registration occurs at launch; scheduling remains best-effort. Reuse the existing scheduler's completion pattern, not its warning-only policy.

**Invalidation key for persisted dirty work:** sample type/domain plus monotonically increasing dirty generation and context revision; reconciliation records the highest generation actually covered. Dirty journal schema belongs to P6b's envelope, or a small independently atomic queue if anchors are not yet enabled.

**Repair:** launch/resume drains dirty work even if no background callback ran; explicit pull reconciles the requested domain; periodic coverage audit repairs missed/unknown changes. Failed background execution never marks clean.

**Cost of being wrong:** falsely clearing dirty state leaves misleading scores or stale widgets. Extra dirty events cost queries/battery, so favor conservative retry and coalescing over suppressing uncertain work. Warning submission still uses P7's fresh-query path.

**Cost/risk/verification.** Medium to high: lifecycle/reentrancy and energy work, not a speed tweak. Test duplicate/coalesced events, change during refresh, failure/cancellation/locked reads, opt-out, relaunch with dirty work, and callback completion counts. On device: sleep sync and workout arrival with app backgrounded, notification toggle off, Background App Refresh disabled, and foreground re-entry. Record query counts and energy behavior; retain the two pools and early Home-card paint.

## 4. Verified green, no action needed in these mechanisms

“Green” here means inspected source satisfies the named property; it does **not** mean the full test suite or a device benchmark was run in this plan-only pass.

- **Deadline abandonment:** `Store:590` races without joining a hung loser, retires the refresh generation, resets the engine anchor, awaits dashboard recovery persistence, enqueues landed workout months, and republishes watch data. Keep this shape. The 120-second constant remains at `Store:559`. Persistence consistency still needs F2; the deadline is not proof that disk or every background task finishes within 120 seconds.
- **Bounded ring queries:** `HealthKitFetchEngine+ActivityRings.swift:402,520` uses a stoppable query and 20-second timeout. Keep bounded chunks, permission/epoch gates, and `replacingLoadedMonths` (`Store:5384`); replace only queried months, never the entire ring history with the recent window.
- **Two query pools:** `HealthKitQueryBudget.swift:88` defines interactive 10/background 4; task-local routing and query wrappers release permits in `defer`. No proposal to retune limits from RP-02 estimates. Semaphore waiters are not themselves cancellable; this is not a proof that arbitrary background walks cannot stall.
- **Fetch tiers:** `Engine:1015` defaults leaves to `fullOnly`. The three `inputCapable` sites remain summary sleep (`:3356`), history sleep (`:3572`), and HRV trend pair (`:3647`), with existing sleep/history clamps. `BodyDashboardFetchSelection` (`BodyAppearancePreference.swift:958`) distinguishes readiness, stress, and Radar dependencies. New observer/repair work must not broaden a stress-only foreground layout's payload by accident.
- **Progressive publication:** independent summary/trend buckets (`Store:5127`) and out-of-band rings preserve the three visible stages; month results stream at `Store:5652`. Do not restore a single barrier for all three or make summary depend on history completion.
- **Atomic files and byte dedupe:** dashboard store encodes before atomic write and scopes its sidecar; workout store (`BodyShared/Services/WorkoutSnapshotStore.swift:130`) and widget store (`HealthWidgetSnapshotStore.swift:42`) likewise encode first, sort keys, compare bytes, and preserve the old file on encode failure. Workout/widget stores also ignore timestamp-only differences. F2 concerns separate metadata, not these per-file guarantees.
- **Cold restore and scoped hydration:** dashboard payload/context use one decode (`HealthDashboardSnapshotStore.loadOrEmptyWithContext`); intraday hydration is off-main and scope filtered (`Store:2508`, `HealthTrend.swift:1408`), with fill-only behavior. Unknown sidecar schema and disabled comparisons do not hydrate. Do not reintroduce the old double decode or inline readiness rebuild. The populated-sidecar preservation guard is not globally green: F3 covers its authoritative-empty failure.
- **Existing effort and detail safety:** effort clear/hydration generations and FIFO disk deletion (`Engine:333,420`) prevent pre-clear effort writes returning; scoped pull repair and Training Load full repair exist. Detail hydration checks live app permissions and bypasses persisted seeding after background transitions (`Store:2291`); positive-only persistence and failed-read handling are worth retaining. These do not establish retroactive-mutation detection or close every in-flight permission race (P1).
- **Record month reconciliation:** `HealthKitWorkoutStore+Records.swift:68` removes absent UUIDs from the refreshed interval and upserts arrivals. The bug is not an append-only *month* merge; it is never revisiting old coverage after baseline completion.
- **Shared training-load fetch:** one memoized task feeds summary, series, and watch loads, and anchor reset cancels it (`+TrainingLoad.swift:34`, `Engine:308`). No duplicate workout fetch should be “removed” here.
- **Watch ordering and freshness distinctions:** capture sequence admission (`WatchConnectivityPublisher.swift:71,175`) plus durable publisher epoch/revision prevents older captures winning merely by finishing later. `BodyCompanionPublisher.swift:201` distinguishes readiness, training load, workout minutes, and metric-pull timestamps; `Store:6427` does not re-arm dashboard TTL on workout-only refresh. Preserve these instead of collapsing freshness to `generatedDate`.
- **Warnings:** source discovery for the headless engine exists (`Engine:2194`); high-HR warnings require usable workout exclusion intervals; delivery failure does not mark the ledger. The evaluator deadline already uses the fixed one-shot race. Fix F7, not the superseded RP-02 deadline bug.
- **Widget derivation:** widget payloads are built from cached app data, not independent widget HealthKit queries; sleep is aged with `asOf` at build (`HealthWidgetSnapshotBuilder.swift:52`). Changing display preferences can rebuild them without a HealthKit fetch. A rebuild timestamp is not evidence of new HealthKit data.

## 5. Structural changes that pay for themselves

No file-size target, extension shuffle, general persistence framework, or metrics-algorithm rewrite is proposed.

1. **One captured-context admission rule (P1):** replaces repeated incomplete cache/generation checks where their missing dimension causes F1. Keep thin orchestration methods and explicit leaf outcomes.
2. **One dashboard persistence envelope and acknowledgment (P2):** removes repeated opportunities to stamp metadata separately from payload. Preserve FIFO queue ordering and sidecar independence.
3. **One per-leaf outcome/coverage representation (P6a):** fixes all-or-nothing history repair and gives later dirty scheduling a precise completion signal. Keep the explicit field merge that protects live derived/intraday state.
4. **One canonical workout input owner only if P6b/P8 earn it:** existing month enrichment, record scanning, and training-load reads need different detail/coverage shapes. Do not combine their queries solely because all return `WorkoutSummary`. Share validated canonical membership/compute inputs, then retain independent detail enrichment and presentation.

The summary/history sleep overlap and summary/series training-load computations were examined; neither justifies a new shared fetch path in this pass. Existing leaf descriptors already centralize much ordinary quantity dispatch (`Engine:3249,3287,3325`); extending that into a generic refresh framework has no demonstrated benefit.

## 6. Measurement and verification gates

### Current measurement result

No comparable phone runs were captured. Initial sandbox device/simulator inventory failed with CoreDevice/CoreSimulator connection errors; a read-only unsandboxed `devicectl list devices --timeout 15` succeeded and showed both iPhones unavailable. No app was installed, relaunched, or its Health database modified for benchmarking. The available iPad is not substituted for the user's prior phone/database baseline.

`BodyPerformanceSignposts.swift:53,63,114` already records leaves, counts, effort candidates, and pool high-water marks and dumps at `finishRefresh`. Use it unchanged. Full-refresh `beginRefresh` supplies wall time; the warm workout-only path can report `total=n/a` and needs the existing `WorkoutMonths` interval plus externally measured entry-to-usable time. Leaf durations overlap, so their sum is not wall time; post-refresh background work can fall outside the foreground dump.

### Required baseline before performance-dependent P8 or budget/window tuning

Same physical phone, Health DB, build configuration, layout, permissions, primary/secondary groups, timezone, and settled background-backfill state. Three runs each:

| Path | Capture |
| --- | --- |
| Cold launch with dashboard >5 minutes stale, `.passiveResume` | Launch→first usable frame, `DashboardSnapshotLoad`, `DaySamplesSidecarLoad`, `RefreshRecentMonths`, per-leaf table, first summary/trend paint, phase-two completion |
| Home pull, `.userInitiated` | Same refresh intervals, three-month workout completion, effort candidates, write counts, early card publication |
| Warm resume 60 seconds–5 minutes | Entry→usable, `WorkoutMonths`, query/pool counts, verify vitals TTL does not advance |

Record each run and median/range, cache sizes, query count by type, and interactive/background overlap. Repeat after a behavior step only when it changes the measured path. For P8, compare query-derived and disk-derived inputs/results before timing; measure warm clean reuse, mutation repair, and bootstrap separately. No numeric speed target is proposed before these measurements. Correctness P1–P7 does not depend on an assumed speed win.

### Phase 2 gates, after explicit approval only

Each implementation commit contains one logical plan step, corresponding behavior tests, and synchronized `README.md`, `TestPlan.md`, and relevant documentation guards in `ProjectConfigurationTests`. Fetch tests use the real `BodyHealthQuerying` / `FakeHealthStore` seam, extended as necessary for anchored batches and controlled suspension; property-only or source-string tests are insufficient for races and persistence failures.

After **each** commit-sized change: build Body, run `BodyTests`, and run the repository's watch build/test gate whenever shared query types, calculator inputs, watermark/publisher behavior, or watch-consumed models change. A simulator launch/preflight failure must be reported separately from compile or assertion failure; a fallback build does not count as a passing test suite. Retain the 120-second deadline, bounded rings, input-only clamps, early publication, coherent abandonment snapshot, atomic writes, and history-preserving coverage replacement in every step.

No changes to `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `VersionHistory.md`, or version guards. No dashes in new user-facing copy. No unrelated cleanup. If an approved approach proves incorrect in implementation, stop and report the flaw rather than reinterpret this plan.

## 7. Suggested implementation sequence and approval scope

| Order | Logical step | Depends on | Scope of approval requested |
| --- | --- | --- | --- |
| 1 | P1 captured-context admission and scoped fallback | None | Correctness fix, including late publications and source failure |
| 2 | P2 atomic dashboard progress/freshness envelope | P1 for captured identity | Correctness/migration fix; retain old history |
| 3 | P7 warning reentrancy and pre-submit revalidation | P1 context semantics | Independent small correctness fix |
| 4 | P4 source discovery invalidation | P1 | Correctness/freshness fix, no new source cache |
| 5 | P5 aggregation-context and rollover invalidation | P1/P2 | Correctness fix preserving workout/sleep attribution policy |
| 6 | P3 explicit raw repair and bounded cache revalidation | P1/P2/P4/P5 | Split into intraday repair, effort validation, and historical/month repair commits; each separately tested |
| 7 | P6a per-leaf historical reconciliation | P1/P2/P5 | Correctness fix with bounded retention for rolling trends only |
| 8 | P6b workout journal and anchored invalidation | P1/P2/P3/P6a; capture §6 baseline first | Separate schema/transaction, fetch seam, and reconciliation commits; device proof required |
| 9 | P9 observer and background scheduling | P6b durable dirty protocol, P7 | Separate foreground dirty scheduling and background delivery commits; no notification coupling |
| 10 | P8 reuse persisted canonical training-load inputs | P6b; parity and measured benefit | Conditional follow-on, not an unconditional performance rewrite |

P6b's first rollout is deliberately limited to workouts. Quantity-type anchors, sleep deltas, and independent effort relationship change handling require their own verified dependency mapping before broadening it. Until then P3's explicit/periodic repair stays active. Frozen morning observation semantics remain unchanged. Approval of the plan does not authorize an implementation to guess at mutation coverage or skip any failed gate.

## 8. Adversarial review corrections

The separate read-only reviewer completed the review on 2026-09-04. It supported F1/F2/F3/F4/F6/F7 from source and agreed F5 should remain an inference pending a controlled timezone reproduction. The following corrections were checked against the code and folded in:

1. **Authoritative empty sidecar repair:** F3/P3 now distinguishes successfully queried empty coverage from unhydrated/default emptiness. The existing matching-scope preservation guard (`HealthDashboardSnapshotStore.swift:318`) would otherwise resurrect the final deleted samples after reload. The green hydration section is qualified accordingly.
2. **Compute-context admission:** P1 now includes sleep goal and effective compute/layout preferences, with separate fetch/compute projections to avoid needless raw refetch. The detached path captures these at `Store:5901,5939`; a fetch-only signature would leave the race open.
3. **Partial durability acknowledgment:** P2 now requires separate main-envelope/sidecar outcomes. A successful main write cannot acknowledge failed raw-sample persistence or clear its dirty coverage.
4. **Frozen observation protection:** P5 explicitly keeps aggregate timezone invalidation out of the frozen observation reset signatures. A global signature extension would clear history and violate the intended freeze contract.
5. **Reference corrections:** method anchors for source changes, ring checkpoints/persistence, sidecar signatures, snapshot save, and the notification ledger now point to the current definitions/statements.

No implementation, tests, versions, or app copy were changed during this review. Remaining evidence limits are explicit: no device reproduction, no new timing baseline, and no claim that every unmodified leaf/calculator has been exhaustively proven correct.

## 9. Implementation phases and acceptance checklist

These are implementation phases, distinct from the original two-part review/approval workflow. The user has authorized documenting the full sequence and starting **Implementation Phase 1 only**. Finish its verification and report before proceeding to Phase 2. A phase may contain multiple commits, but each commit must be one independently verified logical change. The detailed findings and persistence contracts above remain binding.

### Implementation Phase 1: context admission and scoped fallback (P1)

**Work:** capture immutable query and compute identity before asynchronous work; invalidate in-flight admission synchronously when selections change; reject late progressive/final results and freshness stamps; reuse cached summary, daily series, and raw samples only within compatible source/permission scope. Include effective group membership, sleep parsing preferences, calendar identity, sleep goal, and effective compute/layout settings. Retain separate cache-reset and abandonment fences. Settings changes must leave a corrective refresh for the latest context, not silently lose it behind a busy refresh slot.

**Commit boundaries:** first implement the in-flight settings-context fence and detached-compute admission (P1a); then implement compatible cache fallback, effective resolved-source provenance, durable scope admission, and corrective scheduling (P1b). Verify each commit separately. P1a alone does not fix F1's no-concurrency source-failure scenario; Phase 1 is complete only after both land. No progress/freshness envelope migration, new query type, TTL tuning, or calculator formula changes.

**Acceptance:** scripted A→B with B failure cannot return A as B; suspended queries/compute cannot publish after source/group/permission changes; timeout recovery remains coherent; rename-only group edits preserve compatibility; unrelated compatible metrics remain usable. Check persisted reload and widget/watch inputs as well as Home/readiness. Build Body, run all `BodyTests`, and run the watch gate because companion inputs are affected. Synchronize README, TestPlan, and applicable documentation guards in this commit.

### Implementation Phase 2: durable progress and freshness (P2)

**Depends on:** Phase 1's captured identity.

**Work:** version the dashboard envelope to bind ring progress/completion, secondary scope, and durable freshness to its payload. Distinguish written, unchanged-valid, and failed saves. Migrate legacy checkpoints conservatively without discarding history. Keep main-envelope and sidecar acknowledgments independent, and keep progressive paint independent of disk latency.

**Acceptance:** injected write/encode failures and process-exit boundaries never let progress exceed durable coverage; reload retries uncommitted work; main success cannot acknowledge sidecar failure. Build/test/watch gates and synchronized docs accompany the envelope/migration commit.

### Implementation Phase 3: consumer and context freshness (P7, P4, P5)

**Depends on:** Phase 1; P5 also needs Phase 2's durable identity.

**Work, separate commits in this order:** (1) revalidate warning eligibility immediately before submission and prevent actor-reentrancy ledger loss; (2) add force/dirty/expiry source discovery and propagate resolved-membership changes; (3) add aggregate timezone/day-rollover reconciliation while retaining raw instants and original frozen-observation attribution.

**Acceptance:** suspended warning evaluation respects changed settings/foreground state; changed source lists are detected with unchanged preferences; timezone travel and midnight invalidate only the appropriate aggregates. Each commit gets behavior tests, Body build, full BodyTests, applicable watch gate, and synchronized docs. No new source cache or frozen-history reset policy.

### Implementation Phase 4: explicit repair and historical coverage (P3, P6a)

**Depends on:** Phases 1–3.

**Work, separate commits:** (1) explicit retained-window intraday reconciliation and authoritative-empty sidecar writes; (2) effort validation timestamps and bounded revalidation; (3) loaded-month validation and resumable historical/record repair; (4) per-leaf historical reconciliation and input revisions so one failed leaf does not discard successful repairs. Retain the passive overlap and existing query-budget/deadline limits.

**Acceptance:** add/delete/late-write cases across the overlap, old months, and prior years repair through the documented user gesture or bounded policy. Successful empty clears only authoritative coverage, failures preserve it without marking it validated, and relaunch does not resurrect deletions. Run all commit gates and synchronize docs after each logical change.

### Implementation Phase 5: anchored workout journal (P6b, separate approval gate)

**Depends on:** Phase 4 and the §6 baseline protocol.

**Work:** limit the first journal to workouts; implement schema/transaction durability, the anchored fake-store seam, and reconciliation as separate commits. Commit deltas and their anchor together, preserve explicit/periodic repair, and prove deletion, bootstrap, interruption, and invalid-anchor recovery. Do not assume workout anchors detect effort-relationship edits.

**Acceptance:** deterministic transaction tests plus physical-device mutation/relaunch evidence. No broad quantity/sleep rollout without reviewed dependency mapping. If a comparable device baseline or mutation proof is unavailable, report the gate as blocked rather than claiming delta reuse is safe.

### Implementation Phase 6: observer-driven and background work (P9)

**Depends on:** Phase 5's durable dirty protocol and Phase 3's warning safety.

**Work:** first connect observer changes to coalesced foreground dirty work; then add background delivery/scheduler integration in a separate commit. Persist unfinished obligations, acknowledge callbacks promptly, and keep data freshness independent of notification enablement. Background execution is opportunistic, not a freshness guarantee.

**Acceptance:** repeated callbacks coalesce, foreground work retains priority, interruption leaves repair pending, and disabled notifications do not disable data repair. Verify simulated callbacks and physical-device delivery with the standard per-commit gates.

### Implementation Phase 7: measured disk-derived compute reuse (conditional P8)

**Depends on:** Phase 5; repeat §6 measurements after the intervening changes.

**Work:** only proceed if canonical persisted training-load inputs have demonstrated query parity and useful measured benefit. Specify the artifact's invalidation key, repair path, and stale-value consequence before introducing it. Compare bootstrap, clean reuse, and mutation repair separately.

**Acceptance:** unchanged calculator results and watch parity, reliable invalidation/repair, and a recorded benefit on the same device/database baseline. If the evidence does not justify persistence, close this phase with a documented no-change decision. No budget/window retuning or speculative speed estimates.

### Execution record

- Phase 1a: implemented and verified on 2026-09-04. `HealthKitWorkoutStore` now captures canonical source/settings identity and an independent monotonic revision, carries it through deadline-guarded refreshes, observes store-owned changes before their first suspension, and rejects incompatible detached dashboard/permission/readiness/stress/Radar results and late Training Load seed updates. The queued watch-send callback checks the captured inputs as well as the cache epoch. Four new `HealthKitRefreshInputContextTests` cover stable identity, cosmetic source naming, cancelled A→B→A edits, and a scripted HealthKit read followed by a goal change before freshness admission. README, TestPlan, and a dedicated documentation guard are synchronized. No formulas, query budgets, deadline limits, versions, or UI strings changed.
- Phase 1a verification: generic iOS Body build passed; focused context/deadline run passed 15 tests; full BodyTests single-worker run passed 2,207 tests with 1 skip; BodyWatchTests passed 85 tests with 1 skip (unsigned-host App Group access). The initial parallel BodyTests run had 2,206 passes, 1 skip, and one existing publisher-test five-second expectation timeout alongside simulator worker launch errors. The publisher/context/doc retry passed all 9 tests before the clean full single-worker run. No test timeout or assertion was weakened. Results: `/private/tmp/body-rp03-context-full-serial.xcresult` and `/private/tmp/body-rp03-watch-context.xcresult`.
- Phase 1b: not started. Source-compatible cached fallback, effective resolved-membership provenance, durable scope admission, and coalesced latest-context correction remain required. In particular, P1a does **not** fix F1's A→B plus failed-B cached-trend reuse, prove cold-start scope safety, or provide the remaining suspended-compute/consumer integration coverage. Phase 1 as a whole is not complete.
- Phases 2–7: not started; require subsequent approval. P6b/P8 retain their additional evidence gates.
