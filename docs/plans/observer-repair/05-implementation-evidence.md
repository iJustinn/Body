# Implementation evidence — September 12, 2026

Phase A is implemented and exercised on iPhonePro and, after the user's destination change, iPhoneAir. Phase B (historical completion under a real BGTask lease) remains required. Phase C is still conditional. The user authorized committing all current branch changes after these checks.

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

## Remaining work

1. **Phase B:** offer history-only receipts the remaining real BGTask lease after existing current/notification/workout ordering. Verify full intraday coverage, derived prerequisites, durable per-domain progress, expiration, source/context changes, and foreground takeover. Then repeat relevant build/test gates and capture a natural opportunity when available.
2. **Effort follow-up:** move automatic post-write Training Load recalculation into coalesced quiet maintenance. Preserve immediate manual-save feedback, durable obligations and Watch freshness. The current path can still cause a second visible refresh after Auto-Apply; add explicit trigger logging to distinguish callers.
3. **Complete performance evidence:** measure source/summary/history/intraday/compute/persistence stages, exact query/write work and queue age. Exercise natural repeated Watch deliveries and a full Air drain; confirm UI/foreground takeover while repair is actually active, not only after it has finished. Audit redundant full-trend follow-up plus observer reads before claiming coverage reuse eliminates all duplication.
4. **Localization:** translate the five extracted Force Align Sources strings and rerun the failing catalog check.
5. **Independent Watch follow-up:** Air logged `Compute seed dropped` because encoded seeds were about 54.6 KB against a 50 KB budget. Investigate the omitted compute seed and verify Watch behavior; this is separate from the measured second Training Load refresh. The new diagnostic Watch schemes also still need execution/confirmation before relying on them.

Further ordinary-refresh optimization is conditional Phase C work: current full reads still took approximately 10–15 seconds in these samples. Narrow reads or date cursors require measured justification and the targeted review described in the approved plan. A fast badge alone is insufficient; actual coverage and durable progress remain the acceptance criteria.
