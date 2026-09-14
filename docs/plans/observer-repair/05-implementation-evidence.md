# Implementation evidence — September 12, 2026

Phases A and B and the follow-ups below are implemented. App/Watch suites, focused final-guard tests and Release build passed; remaining device evidence is listed below. User authorized bulk commit and push after these checks. Phase C is still conditional.

## Implemented behavior

- Activation configures observer metadata, then decides from initial-load/context/freshness/current-pending state. History-only backlog no longer precedes the current refresh decision. A fresh cache can return while quiet repair is blocked.
- Foreground notification evaluation is a retained, coalesced, cancellable task after current completion/cache acceptance. Existing notification consent, deduplication, send-time checks, and background ordering remain.
- One maintenance unit runs at a time using the existing background query pool. Rotation includes observer metric, journal page/month, record chunk, stress input batch, stress history chunk, ring month, and full trend history. Long retained task handles do not monopolize admission.
- A foreground refresh retires maintenance without joining a blocked query. The old operation retains its maintenance slot until it exits; its token rejects late engine setup, publication, and queued persistence. Interactive/background/app-refresh pool limits remain 10/4/2.
- Automatic journal repair no longer sets the refresh badge. Stress uses its own inputs and chronological robust baseline; completion of the all-time workout record ledger is not a data prerequisite.
- Quiet observer repair captures a current receipt after source preparation and uses the existing full metric shape, one domain at a time. Raw durable publication can clear current work; history clears only after the affected derived tail is durably saved under the same valid owner.
- Ordinary successful reads acknowledge only measured coverage in their result contracts. Cache-only training load and derived stress cannot claim raw-input coverage. Full retained reads for quantities without intraday dependencies can discharge history; incremental/intraday coverage remains conservative.
- Stress heartbeat preparation now resolves the actual HRV source. A focused unresolved-source fixture verifies that failure retains the obligation and a successful required read can complete it.

Integration testing found an automatic ring follow-up entering the foreground refresh-slot helper before checking eligibility. That cancelled a just-started journal unit even with rings disabled. Ring and full-trend follow-ups now use maintenance admission; a dashboard revision fence also rejects obsolete quiet computation if a separately requested history page publishes meanwhile.

## Domain coverage and baseline cost

The following whole-leaf measurements come from the earlier ignored `ObserverRefreshSlowResume-20260912.txt` capture (42.757-second activation). They are **not** controlled before/after comparisons or a current/history cost split. Query deltas are process-wide starts during each leaf, including overlapping owners; they are not exact per-domain query counts. Source/summary/range/comparison/intraday/compute/persistence stage costs remain unmeasured where the existing logs do not distinguish them. No narrower API or new date cursor is justified by these numbers alone.

| Domain | Existing retained read / ordinary coverage limitation | Earlier leaf seconds | Process query-start delta |
| --- | --- | ---: | ---: |
| Sleep | Retained nights, vitals, secondary source; ordinary current only | 6.019 | 12 |
| Heart rate | Latest, daily/comparison, retained raw intraday; ordinary current only | 2.731 | 8 |
| Resting heart rate | Latest, daily/comparison, retained raw intraday; ordinary current only | 0.751 | 2 |
| Body mass | Latest, daily/comparison; successful full trend plus summary can cover history | 0.678 | 2 |
| Body fat | Latest, daily/comparison; successful full trend plus summary can cover history | 1.464 | 2 |
| HRV | Latest, daily/comparison, retained raw intraday; ordinary current only | 1.042 | 3 |
| Respiratory rate | Latest, daily, retained raw intraday; ordinary current only | 1.041 | 3 |
| Oxygen saturation | Latest, daily/comparison, retained raw intraday; ordinary current only | 1.004 | 4 |
| BMI | Latest, daily/comparison; successful full trend plus summary can cover history | 0.697 | 2 |
| Active energy | Current total, daily/comparison, hourly history; ordinary current only | 3.688 | 5 |
| Resting energy | Current total, daily/comparison, secondary source; full trend plus summary can cover history | 2.280 | 3 |
| Exercise minutes | Current total, daily/comparison, secondary source; full trend plus summary can cover history | 2.949 | 2 |
| Training load | Retained 408-day workouts/effort invalidation; ordinary cached/shared reads excluded | 1.169 | 475 |
| Wrist temperature | Current average and daily history; full trend plus summary can cover history | 0.781 | 2 |
| Time in daylight | Current total and daily history; full trend plus summary can cover history | 0.786 | 2 |
| Steps | Current total, daily/comparison, hourly history; ordinary current only | 8.678 | 5 |
| Cardio fitness | Latest and daily history; full trend plus summary can cover history | 0.526 | 2 |
| Stress | Required heartbeat samples and derived tail; specialized stress history owner retained; ordinary excluded | 0.628 | 121 |

Coverage describes accessible HealthKit results under existing privacy semantics, not proof of read permission. Successful empty results remain distinct from failures. Schema 2, full-domain receipts, and existing specialized cursors remain unchanged.

## Executed checks

- `/private/tmp/body-maintenance-coverage4.xcresult`: 55 passed, 0 failed. Covers observer receipts/source/coverage, notification separation, deadline/lease cancellation, maintenance rotation and quiet publication.
- `/private/tmp/body-maintenance-integration2.xcresult`: 26 passed, 0 failed. Includes actual journal/queued-record foreground preemption, history-only activation, raw-save/derived interruption, seven-owner rotation, and source guards.
- Earlier full suite `/private/tmp/body-maintenance-full2.xcresult`: 2,469 passed, 4 failed, 3 skipped. Three refresh source guards were corrected and pass above. The remaining failure is the existing local `Force Align Sources` catalog entry missing Chinese translation; unrelated localization edits are preserved.
- Final full suite `/private/tmp/body-maintenance-full4.xcresult`: **2,473 passed, 1 failed, 3 skipped**. The sole failure is `ProjectConfigurationTests.testChineseLocalizationCatalogsAreComplete`, reporting the untranslated `Align` key. JSON comparison identifies five newly extracted Force Align Sources strings without translations. Existing translations are preserved; the rest of the catalog diff is formatting/order.
- Generic iOS Release build passed with `/private/tmp/body-observer-release`, including Watch and widget build dependencies. Signed iPhonePro Debug build passed at 19:01. The same implementation subsequently built and launched on iPhoneAir at the user's request. The separate Watch test schemes have not been run in this implementation session.

## Device evidence

iPhonePro launch `c3bc97600`, PID 4374: activation with all 18 domains pending completed in **10.123s** (ordinary refresh **9.996s**). Maintenance began at 19:03:26.763; all 18 history receipts, including stress, were acknowledged by 19:04:25.284. The final unit exited at 19:04:25.790, approximately **59 seconds after visible refresh completion**. This proves a stable quiet drain in that capture; it is not a guaranteed drain deadline. The user then reopened and pulled to refresh and reported that refresh felt shorter/better. The reopen took **1.677s**, with an empty ledger; two ordinary full refreshes took **13.306s** and **12.607s**. Raw filtered history is ignored in `ObserverRefreshQuietRepair-20260912.txt`.

iPhoneAir launch `c3a6b0f00`, PID 14923: the initial 18-domain full activation took **15.418s**. A separate **6.701s** Training Load refresh followed an effort-rating save at 19:10:01. The code schedules `refreshAfterWrite(.trainingLoad)` after manual effort saves and successful Auto-Apply writes; the timing supports Auto-Apply during the first refresh, but logging does not distinguish those callers. A later affected-current stress activation took **2.531s**. Quiet work was preempted and resumed, with successful per-domain acknowledgments; the capture did not prove a full Air drain. Findings are also in [ObserverRefreshValidation.md](../../ObserverRefreshValidation.md).

## Remaining work at the Phase A commit

1. **Phase B:** offer history-only receipts the remaining real BGTask lease after existing current/notification/workout ordering. Verify full intraday coverage, derived prerequisites, durable per-domain progress, expiration, source/context changes, and foreground takeover. Then repeat relevant build/test gates and capture a natural opportunity when available.
2. **Effort follow-up:** move automatic post-write Training Load recalculation into coalesced quiet maintenance. Preserve immediate manual-save feedback, durable obligations and Watch freshness. The current path can still cause a second visible refresh after Auto-Apply; add explicit trigger logging to distinguish callers.
3. **Complete performance evidence:** measure source/summary/history/intraday/compute/persistence stages, exact query/write work and queue age. Exercise natural repeated Watch deliveries and a full Air drain; confirm UI/foreground takeover while repair is actually active, not only after it has finished. Audit redundant full-trend follow-up plus observer reads before claiming coverage reuse eliminates all duplication.
4. **Localization:** translate the five extracted Force Align Sources strings and rerun the failing catalog check.
5. **Independent Watch follow-up:** Air logged `Compute seed dropped` because encoded seeds were about 54.6 KB against a 50 KB budget. Investigate the omitted compute seed and verify Watch behavior; this is separate from the measured second Training Load refresh. The new diagnostic Watch schemes also still need execution/confirmation before relying on them.

Further ordinary-refresh optimization is conditional Phase C work: current full reads still took approximately 10–15 seconds in these samples. Narrow reads or date cursors require measured justification and the targeted review described in the approved plan. A fast badge alone is insufficient; actual coverage and durable progress remain the acceptance criteria.

## Follow-up implementation — 19:38

New uncommitted work:

- Real BGTask opportunities offer history-only domains after current reads, notifications and workout repair. Each uses the original lease/appRefresh pool and full retained intraday reconciliation. History clears after derived computation and durable save. Pending current dependencies or a changed ledger revision prevent completion; expiry and foreground takeover invalidate publication. No new cursor or schema.
- Automatic effort writes capture a durable Training Load obligation even without a HealthKit callback. Their follow-up uses quiet observer maintenance; debounced Training Load-only callbacks coalesce while that obligation is outstanding. Other current changes and actual activation retain ordinary freshness handling. Immediate effort overrides and explicit manual-save behavior remain.
- Watch compute sleep history now drops nights older than the existing 70-day compute lookback. The 56-day readiness baseline, 15 nights of stage detail, codec, schema and transport budgets remain. Parity and size fixtures now begin with 365 nights; parity covers the following week.
- Added English and Simplified Chinese translations for the five Force Align Sources strings.

Checks and device evidence:

- `/private/tmp/body-background-history1.xcresult`: **47 passed, 0 failed** (background repair, quantity batches, localization runtime keys).
- `/private/tmp/body-background-history2.xcresult`: **64 passed, 0 failed**, including derived dependency admission, per-domain expiry, foreground takeover, automatic effort obligation durability, intraday reconciliation and Watch seed/parity/store/publisher checks.
- Signed Air build/launch succeeded: `c36514c00`, PID 15039. Activation at 19:31:10 took **7.166s**, ordinary refresh **7.038s**. Empty ledger at launch proves prior Air backlog had drained before this launch, without measuring when. Quiet units finished: stress inputs **0.905s**, full trends **7.356s**, journal **0.017s**, records **0.491s**. No second visible refresh or oversized-seed error appeared in this capture. No eligible automatic effort write occurred, so the new route is not yet device-validated.
- User opened Body on the paired Watch and locked Air. No new observer delivery or natural BGTask was visible by the latest check. This does not prove Watch receipt/compute, actual seed size, or background completion.
- `/private/tmp/body-watch-history1.xcresult`: canonical BodyWatchTests scheme built and executed the seed intake suite: 10 passed, 1 skipped, 1 failed. Failure was fixture-directory creation, POSIX 28: **No space left on device**. Rerun required; diagnostic variants remain unexecuted.
- `/private/tmp/body-background-full1.xcresult`: interrupted after simulator launch failures, file-write assertions and a permission-change timeout during disk exhaustion. Not a clean verification gate. Removed this task's earlier 1.3 GB Release build cache and Watch intermediates; retained test results. Diagnostic collection was stopped after execution ended.
- `git diff --check` passed.

Remaining at that point: free sufficient Mac disk space; rerun full app and Watch tests, including the catalog-completeness check, then Release build. Confirm actual Watch transport/compute, automatic effort follow-up on a genuine eligible workout, and a natural BGTask opportunity. No artificial HealthKit data was created.

Redundant-work audit: `loadFullTrendWindow` still refetches daily series quietly without acknowledging observer history. Its result proves daily-series coverage, not current-summary or full intraday coverage. Clearing arbitrary receipts there would be incorrect. Air's unit took **7.356s**; detailed query/write attribution and any targeted Phase C proposal remain outstanding.

## Recovered verification and latest Air evidence — 19:47

Stopping the failed parallel run released its temporary simulator storage, restoring roughly 5 GB free. Rerunning suites individually with `-parallel-testing-enabled NO` avoided the environment failures:

- `/private/tmp/body-background-full2.xcresult`: **2,478 passed, 0 failed, 3 skipped**, including catalog completeness.
- `/private/tmp/body-watch-history2.xcresult`: **85 passed, 0 failed, 1 skipped**. Canonical Watch test scheme executes successfully despite Xcode's nonfatal preferred-buildables warning.
- A final background guard additionally requires fresh, scope-matching validation stamps for registered derived dependencies. A clean ledger alone cannot substitute for successful dependency reads. `/private/tmp/body-background-guard1.xcresult`: **20 passed, 0 failed** after that change. The full app suite above preceded this final guard.
- Generic iOS Release build passed again after the final guard, including Watch/widget dependencies, using `/private/tmp/body-observer-release`.
- All three diagnostic Watch schemes executed `WatchComputeSeedIntakeTests.testSaveReportsChangeOnlyWhenTheBytesDiffer` successfully (one pass each): `/private/tmp/body-watch-diagnostic-no-profile.xcresult`, `/private/tmp/body-watch-diagnostic-explicit-host.xcresult`, `/private/tmp/body-watch-diagnostic-independent-env.xcresult`. No scheme edits were necessary; the explicit-host variant also avoids Xcode's preferred-buildables warning.
- Signed build and deployment of the final guard to Air succeeded: launch `c3a6b3600`, PID 15195. Fresh-cache/workout-only activation took **1.581s**, ledger empty; quiet work completed without a second visible refresh.
- In the preceding Air session, new HealthKit changes for sleep, heart rate, resting energy, active energy and steps were processed in **13.150s**, with all current/history receipts acknowledged and an empty remainder. The user's subsequent manual refreshes took **11.795s** and **12.818s**. These are different workloads from the fresh-cache launch, not a controlled speedup comparison. User confirmed **Air remained responsive**. The last trend-history unit was preempted after **0.263s** when the app left foreground.
- A read-only debugger expression inspected Air's outgoing `WCSession.applicationContext["computeSeed"]`: **27,022 bytes**, versus the previous roughly 54,600-byte rejected payload. The existing 50,000-byte budget now admits the seed. The process was resumed after inspection. This proves outgoing context inclusion, not a Watch-side receipt/compute acknowledgment; the physical Watch was not exposed as a directly connected development device.
- Filtered device capture is ignored: `docs/ObserverRefreshBackgroundRepair-20260912.txt`. Original appended review remains unchanged. No commits or pushes.

Outstanding device evidence: a natural eligible BGTask with pending history, and an actual automatic effort write triggering the new quiet route. Opening the Watch and locking Air did not produce a logged BGTask in this session; debugger attachment and locked-device HealthKit protection also limit that observation. Watch-side receipt/compute and finer query/write attribution remain unverified. No additional metric algorithm or date-cursor optimization is included.

At the subsequent bulk-commit survey, Xcode had updated `ProfileAction/MacroExpansion` in BodyWatchTests and two diagnostic schemes. These profiling-only metadata changes are preserved in a separate tooling commit; test actions are unchanged. The appended adversarial review and ignored raw log captures remain unchanged.
