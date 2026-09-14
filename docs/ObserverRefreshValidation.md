# Observer refresh validation

Date: 2026-09-12  
Base commit: `dd98729` plus local observer changes.  
Plan: [ObserverRefreshFixPlan.md](ObserverRefreshFixPlan.md).

Raw `ObserverRefresh*-20260912.txt` console captures remain local under `docs/` and are intentionally excluded from Git. The measurements and conclusions below are the shared validation record. Device performance acceptance remains pending until a later natural refresh.

## Implemented behavior

The ledger now uses a typed, versioned `BodyHealthObserverContext` containing primary/secondary source requests and identities plus aggregation provenance. Day boundaries, sleep goal, and compute version no longer create observer history obligations. The full dashboard signature is unchanged: current-day expiration, context refresh, readiness recomputation, publication fences, notification validation, and metric freshness still use it.

Schema 1 migrates to schema 2 with a new reset ID and an atomic write. Recognized legacy scopes with matching projected provenance retain every pending flag and generation, including already-pending work that might have originated at midnight. Unknown or mismatched entries conservatively become current/history pending. Failed migration writes remain pending and retry on restart; stable schema-2 launches do not rewrite the ledger. Receipts carry the observer context type, including the heartbeat acknowledgment path.

Observed repair checks ledger durability before health reads. A concurrent failed mark may recover through one synchronous flush in acknowledgment, followed by the existing reset, generation, context, and durability checks. A newer delivery cannot be consumed by an older read.

Device traces and focused tests justified three source-discovery corrections:

- Discovery and freshness validation use the same captured admission date; fresh discovery no longer looks like a clock rollback.
- Discovery returns its settled revision from the engine actor. Installing its own source bucket no longer fails the caller's revision check. Internal discovery-generation guards and subsequent store input/publication checks remain active.
- Weight, body fat, and BMI discover and dirty their descriptor's shared `basics` source map.

A pass whose publication fence changes stops before the next metric or ring tail. Unresolved discovery still invalidates old provenance; the stable next pass can read, persist, and acknowledge. The initial corrections added no fetch union, new scheduler, notification reordering, or ordinary-refresh receipt reuse. The subsequent bounded quantity-read optimization is recorded below.

| Change | Observer ledger acceptance | Independent dashboard obligation |
| --- | --- | --- |
| Same context | Flags/generations unchanged, including restart | Existing freshness admission |
| Day only, including 23/25-hour DST days | No new history work; real pending receipts survive | Expire today's values and schedule context refresh within resume debounce |
| Sleep goal / compute only | No new history work | Existing derived recomputation/context validity |
| Source/member, permission request, timezone/aggregation | Conservative history invalidation | Fence incompatible payloads and re-read |
| Discovery becomes resolved | Reject old fence/receipt; stable follow-up converges | Install valid discovered provenance |

## Verification

The initial characterization stage passed 53 focused tests. After context/migration/durability implementation, 60 focused tests passed. Two store-level discovery regressions then passed after the timestamp/revision correction.

Final focused run: **16 passed, 0 failed, 0 skipped**, covering `BodyObserverLedgerContextTests`, `HealthSourceDiscoveryFreshnessTests`, and the affected metric-detail source guard. Result: `/private/tmp/body-observer-tests/Logs/Test/Test-Body-2026.09.12_14-10-22--0400.xcresult`.

Final full Body suite: **2,443 passed, 0 failed, 3 skipped** (2,446 total), with no runtime warnings in the result summary. Retained result: `/private/tmp/body-observer-final-tests.xcresult`.

The earlier full run executed 2,445 tests with 3 skips and two assertions failing in one source guard. Diagnostics pushed valid code beyond that test's fixed 8,000-character window; the guard now uses the next function boundary. The post-test simulator diagnostic collector stalled after tests finished and was terminated separately. The final passing rerun completed normally.

Simulator: iPhone 17 Pro, iOS 26.5 (23F77), `02E27E9C-4B6C-4EB6-A606-8D940058AB00`, DEBUG, `-parallel-testing-enabled NO`, signing disabled. An earlier focused attempt encountered simulator Busy preflight; two development runs were interrupted while debugging incomplete fake query scripts. These are not passing verification runs.

Final generic iOS **Release build passed**, signing disabled, derived data `/private/tmp/body-observer-release`. Embedded widget, Watch, and Watch widget dependencies were included. Final signed DEBUG build and launch on iPhonePro also passed. `git diff --check` passed.

## Device measurements

Device: **iPhonePro**, iPhone 16 Pro Max (`iPhone17,2`), iOS 27.0, arm64, UDID `00008140-001A38C40A13001C`. Bundle `com.zihengthedeveloper.Body`, version 1.1.1 (3). All measured builds were signed DEBUG, launched by Xcode with the debugger attached, preserving the existing container and HealthKit data. No clock changes, cache clearing, uninstall, downgrade, or artificial health records were used.

Auto-Apply was read through the debugger and was already **off** (`autoApplyWorkoutEffort = 0`). It was never changed, so no restoration was necessary. No Auto-Apply-on/write scenario was exercised. These are cold process launches with retained data, not proven natural Watch-sync or rollover events. Badge-visible durations and companion/notification UI were not captured: physical-device interaction tooling could not select this device.

| Capture | Pending at admission | Observer pass | Notification evaluation | Ordinary refresh | Activation total | Deadline outcome |
| --- | --- | --- | --- | --- | --- | --- |
| Diagnostics baseline, 13:43 | 18 existing domains | 14.673s; 18 leaves, 3 accepted, 15 pending | 0.258s | 5.958s | 20.969s | Finished; no notice |
| Context + timestamp/revision fix, 14:05 | 15 existing domains; migration preserved generations | 34.628s; 12 accepted, 3 Basics children pending | 0.073s | 4.421s | 39.149s | Finished; no notice |
| Final build including Basics mapping, 14:11 | Clean; unchanged context, no ledger write needed | No observed pass | 0.025s | 7.782s | 7.908s | Finished; no notice |

Traces: baseline (local capture `ObserverRefreshBaseline-20260912.txt`), intermediate capture (local capture `ObserverRefreshIntermediate-20260912.txt`), and final capture (local capture `ObserverRefreshFinal-20260912.txt`). The intermediate trace covers the first activation through completion, not the entire launch session. Its three remaining obligations had drained by the final launch; that intervening drain was not captured. The final launch therefore verifies stable clean admission and restart, not a physical-device execution of the corrected Basics path. Focused tests verify all three Basics children discover the shared source map and reach reads.

These rows have different pending workloads and are **not a controlled speed comparison**. The intermediate run spends more time because successful health reads replace early exits; migration correctly preserves that backlog. No 60–120-second affected run or timeout was reproduced. Natural quick/stale Watch-sync resumes and rollover remain device acceptance work; the user-visible issue is not yet declared resolved.

Follow-up user report: two ordinary reopens took approximately **8–9 seconds** and **more than 40 seconds**. The long-refresh symptom therefore remains after the initial fixes. The prior Xcode launch session had ended before these durations were reported, so neither run has a matching captured trace. Direct retrieval of historical device logs requires administrator authentication unavailable to this session. Re-establish live capture on the existing iPhonePro build and correlate the next normal reopen before attributing the delay or changing refresh scheduling.

Live capture reconnected after device unlock: launch `c3bc96e80`, PID 3144, 14:45:57. The ledger was clean and unchanged; no observed repair ran. Notification evaluation took 0.062s, ordinary refresh 13.069s, total activation 13.397s, with no timeout notice. This is a new debugger launch, not either reported reopen. Reconnect trace (local capture `ObserverRefreshReconnect-20260912.txt`). The active Xcode workspace identifier is `windowtab-RlRMP4KQSt`; capture remains attached for the next normal background/foreground transition.

The user then switched away and reopened Body without force-quitting. Captured warm activation at **14:47:30** completed in **2.985s**, taking the `workoutOnly` branch. Notification evaluation took 0.720s and the workout refresh deadline completed in 2.237s without setting a notice. The observer ledger remained clean (`changedDomains=0`, `pending=[]`, `rings=false`); no observed repair or context replacement ran. Warm-resume trace (local capture `ObserverRefreshWarmResume-20260912.txt`). This successful short resume does not explain the earlier >40s report. Leave live capture connected for a recurrence during normal use; no additional behavioral change is justified by this trace alone.

### Captured slow resume: 42.757 seconds

The user's next reported long refresh is captured in the slow-resume trace (local capture `ObserverRefreshSlowResume-20260912.txt`). At **14:49:30**, 19 admitted HealthKit callbacks arrived within approximately 65ms, creating pending work for all 18 metric domains, plus workout/ring obligations. At **14:51:43**, activation admitted those receipts with `changedDomains=0`: these obligations came from callbacks, not day/context invalidation. The callback trace proves signals were delivered, not which records changed or whether every signal represented a distinct mutation. The observer retains existing registrations when configuration is unchanged; this trace does not establish the HealthKit-side reason for the broad burst or distinguish delayed initial callbacks from later deliveries.

| Stage | Duration | Result |
| --- | --- | --- |
| Observer repair | 38.673s | 18 sequential leaves, all acknowledged; ledger remainder empty |
| Notification evaluation | 0.576s | Finished |
| Subsequent ordinary full refresh | 3.477s | Finished |
| Entire activation | **42.757s** | No timeout notice |

The 18 leaf durations total 36.912s; remaining observed-pass time includes admission/hydration/ring tail. Slowest leaves: steps 8.678s, sleep 6.019s, active energy 3.688s, exercise minutes 2.949s, heart rate 2.731s, resting energy 2.280s. Leaf query-start deltas sum to 655, including training load 475 and stress 121; these remain process-wide instrumentation counts, not distinct per-receipt coverage. Every leaf reports successful queries/payloads and accepted acknowledgment. There was no source/context fence invalidation, retry loop, or durability rejection during the pass. The body-measurement fixes now also have successful physical-device read/persist/ack evidence.

PID **3144** and launch session `c3bc96e80` are unchanged from the fast resume: the captured slow case is a warm process activation. This corrects the earlier inference that force-quitting was required. It also demonstrates the narrow context fix alone does not resolve broad callback-burst cost. Serial observed current/history repair is about 90% of this delay; removing only the subsequent full refresh could save at most its measured 3.477s for this run. Notification reordering is not a meaningful primary fix here.

The next optimization should target the measured serial repair path with explicit fetch/payload coverage and generation safety. Do not discard broad callbacks as spurious, acknowledge through a freshness TTL, or run the existing store-mutating metric method concurrently. Any batching proposal must preserve source discovery, retained historical windows, successful empty/deletion reads, durable payloads, and rejection of newer deliveries. The trace supplies evidence for a separate concrete design under plan section 6; it does not establish that the ordinary full fetch covers every observed historical obligation.

Signed initial-fix build log: `/var/folders/j8/yh3h7sdx5gs0z5pljzv5cfg40000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260912-141049.txt`. Initial-fix launch reference `985302580`, PID 2994; launch log `RunProject-Log-20260912-141122.txt` in the adjacent `RunProject` directory. The pre-fix signed baseline was saved at `/private/tmp/body-observer-baseline/Body.app`; do not reinstall it over the migrated container.

### Bounded foreground quantity reads

Implemented [the bounded batch design](ObserverRefreshBatchDesign.md): at most three consecutive independent quantity reads overlap after their sources are prepared. Results merge and persist serially in receipt order through the same commit helper as detail pulls. Historical windows, successful-empty semantics, generation checks, full dashboard context and publication fences remain intact. Single metrics, sleep, training load, heartbeat repair, and background leases retain their serial paths. A slow sibling can hold its batch until the existing deadline; this is not a promise that every refresh will be short.

Six new gated fake-store tests prove overlap and the concurrency cap, durable ledger restart, failed-query and failed-source isolation, newer-delivery preservation, cancellation with late results, and source A→B→A rejection. Focused run: **22 passed, 0 failed, 0 skipped**, `/private/tmp/body-observer-batch-focused-3.xcresult`. The first full run found one source-layout guard expecting the pre-extraction signature assignment; updating that guard to follow the read context passed in isolation (`/private/tmp/body-observer-batch-guard.xcresult`). The post-test diagnostic collector for the failed run was stopped after tests completed. Final full run: **2,449 passed, 0 failed, 3 skipped** (2,452 total), no runtime warnings, `/private/tmp/body-observer-batch-final.xcresult`.

Generic iOS Release build passed with signing disabled, `/private/tmp/body-observer-release`. Signed DEBUG build passed: `BuildProject-Log-20260912-150845.txt` in the same artifact directory above. Deployed to the existing iPhonePro container, launch **`c3bcb3480`**, PID **3228**, `RunProject-Log-20260912-150915.txt`. At 15:09:21, the ledger was clean and unchanged, with no observer pass: notification evaluation 0.021s, ordinary workout-only refresh 1.546s, total activation **1.699s**, no timeout notice. Batch-build launch trace (local capture `ObserverRefreshBatchLaunch-20260912.txt`).

This verifies deployment and clean admission only. No comparable broad callback burst has yet run on the batch build, so the improvement over 42.757s remains unmeasured. Live capture stays attached to `windowtab-RlRMP4KQSt` for normal use; no predictable Watch-sync time or artificial HealthKit record is required. Auto-Apply remains unchanged/off. The outstanding device check is batch duration and receipt drainage after a natural burst.

Latest user-triggered check: warm activation at **15:16:23** on the same batch-build process completed in **9.092s**. The ledger was clean (`pending=[]`, `rings=false`, `changedDomains=0`), so no observed repair or quantity batch ran. Notification evaluation took 0.023s; the ordinary full refresh took 9.024s and finished without a timeout notice. Its longest profiled leaf was sleep history at 4.195s; ordinary-fetch leaf timings overlap and must not be summed. Saved resume trace (local capture `ObserverRefreshBatchResume-20260912.txt`). This run confirms the ordinary full-refresh path but still does not measure broad-burst repair performance.

Further iPhonePro checks on the same PID: the refresh ending **15:17:50** completed in **16.971s**, with no observed batch or activation marker identifying its trigger. Ordinary-fetch profiling reports training-load summary/trend at 10.536s each, sleep history 9.095s, and 304 effort candidates; shared/overlapping timings are not additive. The latest warm activation at **15:20:33** took **2.875s** (`workoutOnly`), with notification evaluation 0.672s and ordinary refresh 2.154s. Its ledger was clean and unchanged, and no timeout notice was set. Saved follow-up trace (local capture `ObserverRefreshProFollowup-20260912.txt`). Broad-burst batch performance remains unmeasured.

The user also requested iPhoneAir logs. Device `00008150-00095D9E22F8401C` is connected, but the only Xcode launch session available is iPhonePro. Console initially had no active stream; live capture was started for iPhoneAir with an `ObserverRefresh` filter. No matching messages were available at this check, so its earlier refresh duration cannot be reported from this capture. A new ordinary reopen while capture is active is needed.

Follow-up captured iPhoneAir at **15:28:03**, launch **`c3bce0c00`**, PID **13539**; identity was confirmed by Xcode's active iPhoneAir destination and matching Console messages. Total activation **9.260s**: observed pass 2.043s, notification evaluation 0.009s, ordinary full refresh 7.178s. One stress receipt (`g3006`, current/history pending) was present on unchanged-context admission and remained pending afterward. The stress leaf returned false in 0.002s with zero query starts, no cancellation, and valid input/lease checks. No quantity batch ran and no timeout notice was set. Raw local capture: `ObserverRefreshAir-20260912.txt`.

This exposes an unresolved stress admission case, not a successful ledger drain. The heartbeat fetch has an early nil return when the HRV source selection is unresolved; unlike quantity repair, the stress branch does not prepare that source first. This is a code-supported candidate explanation for the zero-query exit, not yet a device-state-confirmed diagnosis. Check a subsequent stable admission before changing acknowledgment semantics.

At this check the prior iPhonePro launch reference was no longer available; Xcode's current launch belongs to Air. Pro's Console had no retained stream, so its newer refresh cannot be timed from available logs. Started Pro Console capture with the same refresh filter while retaining Air's current Xcode capture. A new Pro reopen is required for fresh evidence; the earlier 2.875s timing must not be presented as its latest uncaptured run.

### Long batch-build run: background revalidation plus concurrent deliveries

At **16:52:22** iPhonePro admitted another long activation, captured in local file `ObserverRefreshProLongBatch-20260912.txt`. The recovered Xcode launch is **`c35493300`**, PID **3365**, started at 15:27. Console's selected iPhonePro stream contains matching pass IDs; Xcode's currently selected iPhoneAir destination does not identify the already-running Pro session. This session also recovers the previously incomplete 15:30 Pro reopen: **2.592s**, workout-only, clean ledger, no timeout. The standalone Console stream had omitted its completion; absence of a streamed completion was not evidence of a hung refresh.

The later long run has a different source of initial work. At **16:28:17**, `reason=backgroundRevalidation` marked all **18 domains** current/history pending at generation 1756. The background pass then returned in 0.001s without any metric leaves or acknowledgments; all obligations remained. There were no context differences at the subsequent foreground admission. Code inspection confirms `runBackground` uses the ordinary mutation-marking method for periodic fallback, creating both pending flags even without an observer delivery. The trace does not identify the specific eligibility guard that prevented background reads.

| Stage | Duration | Outcome |
| --- | --- | --- |
| First foreground observed pass, 16:52:24–16:53:28 | **63.696s** | 18 admitted domains; batching active; 12 domains still pending |
| Another refresh ending 16:53:54 | **25.872s** deadline span | Completed; exact caller not identified by this diagnostic |
| Follow-up observed pass, 16:53:55–16:54:29 | **34.290s** | All 12 remaining domains acknowledged; pending ledger empty |
| Final notification evaluation | **1.959s** | Completed |

From the first foreground admission at 16:52:22.531 to the final notification completion at 16:54:31.655 is approximately **129.1s**. This is a measured sequence of operations, not a separately measured badge-visible duration or one 129-second deadline. The first activation logged `branch=busy` after 66.846s because another refresh occupied the slot. No timeout notice was set.

**70 admitted HealthKit callbacks** arrived between 16:52:51 and 16:52:57, during the first repair. Ten old acknowledgments were correctly rejected for newer generations. Sleep and active energy were acknowledged earlier, then dirtied again; together this left 12 pending domains. These are callback counts, not a count of distinct changed samples. The second pass had no such rejections and drained all remaining work. Quantity batch logs prove overlapping reads on the device, but do not establish a speedup over the earlier 42.757s case because workload, callback arrivals, and query timing differ. Sleep alone took 13.797s in the first pass; the HR/HRV/oxygen batch took 12.899s.

The next correction must distinguish periodic background revalidation from durable mutation/history obligations. Merely changing background fallback to current-only flags is insufficient by itself: foreground admission currently includes current-pending work and runs the full observed historical path. Preserve actual callbacks, missing/corrupt-ledger recovery, source/context invalidation, and ordinary freshness checks. Separately investigate whether newer receipts can be captured immediately before their reads under the same still-valid owner, instead of reading against already-obsolete pass-start generations. Never acknowledge newer generations with reads that started before their delivery. The intervening refresh's caller also needs identification before changing scheduling. No further production change is included in this log-check update.

### Periodic background revalidation correction

`runBackground` now selects stale periodic reads separately from durable observer receipts. It no longer calls `ledger.mark` for `backgroundRevalidation`. The existing background lease, eligibility checks, source preparation, fenced metric publication, durable payload saves, and notification/companion ordering still apply. Periodic reads never acknowledge receipts, so a real callback arriving during a read remains pending for repair.

Failed, denied, or expired periodic work remains eligible for a later freshness check without creating foreground historical repair work. Actual observer deliveries, source/context changes, and missing/corrupt-ledger recovery still create durable obligations. Existing pending entries are preserved because the stored ledger cannot distinguish old synthetic marks from real changes; an already queued repair may therefore still run after installing this correction.

Six coordinator regression tests cover successful publication with a clean ledger across reload, repeated deferred admission, failed reads, an actual callback during a periodic read, lease expiration during a read, and preservation of a real history obligation across later background opportunities. The focused run passed **29 tests**, including observer and quantity-batch regressions (`/private/tmp/body-observer-fallback-focused.xcresult`). The full suite passed **2,455 tests, zero failures, three skipped** (`/private/tmp/body-observer-fallback-full.xcresult`); the final test-fixture capture cleanup also passed all six new tests (`/private/tmp/body-observer-fallback-final-focused.xcresult`). Generic iOS **Release** and signed device **Debug** builds passed. Device validation is pending at this point. This correction does not establish a new latency bound for genuine broad callback bursts or resolve the separate intervening ordinary-refresh scheduling question.

## Reading the diagnostics

Filter the DEBUG console for `ObserverRefresh` and `RefreshProfile` (`com.zihengthedeveloper.Body`, `Performance`). Ledger events report pending kinds/generations/current-history flags and durability. Pass/leaf/query/payload/ack events carry a pass ID; context events report dimensions and fence invalidation. Activation timing separates notification evaluation. `deadline owner=runRefreshWithDeadline` identifies the race that sets the visible notice; observed and notification races report `setsNotice=false`. Ring capture logs count persistence requests, not necessarily distinct encodes/writes.

The corrected Debug build launched successfully on **iPhonePro** at **17:21**, session **`c35493480`**, PID **3630**. Initial activation completed in **11.655s**: observed pass 1.998s, notifications 0.008s, ordinary refresh 9.614s. The unchanged-context ledger contained only stress (`g1830`); its leaf returned false in 0.004s with zero query starts and remained pending, matching the separate unresolved-source admission candidate noted on Air. No timeout notice was set. A later natural background opportunity is still needed to validate periodic behavior on the device. iPhoneAir's attempted launch failed; the user selected Pro for this deployment.

Pass starts now report `revalidating=[...]` separately from the receipt count, and periodic leaves log `revalidation kind=... success=... leaseValid=...`. A clean periodic opportunity should report zero receipts and leave the ledger clean unless a real delivery or context change occurs.

`processQueryStartsDelta` is a process-wide count from the existing profile instrumentation; concurrent or abandoned work may contribute. It supplements local timing and is not per-receipt query coverage. Only kinds, flags, generations, random pass IDs, dimension names, outcomes, and timings are added to logs; health values and sample/source/workout identities are excluded.

### Quiet repair build: iPhoneAir monitoring

The user explicitly switched the validation destination from iPhonePro to **iPhoneAir**. Xcode confirmed the physical iPhoneAir destination, iOS 27.0, Body scheme. The current implementation built and launched at **19:09**, session **`c3a6b0f00`**, PID **14923**. No commit or push was performed.

The first activation admitted 18 current/history obligations with unchanged context. It completed the ordinary full-refresh route in **15.418s** at 19:10:02 (refresh deadline span **15.399s**), without an awaited historical pass beforehand. A subsequent separate refresh completed in **6.701s** at 19:10:09; the diagnostic does not identify its exact caller. At 19:10:10 the remaining current stress obligation took the affected-current route; activation completed in **2.531s**, and the stress receipt was successfully acknowledged after actual heartbeat queries and durable derived publication. These are distinct operations, not directly comparable workloads or measured badge durations. None set a timeout notice.

Quiet journal/record/metric units ran between visible operations. Foreground admission retired a respiratory repair in **0.297s** without acknowledging it; later quiet receipts completed successfully. A sleep unit was cancelled at 19:10:47 and remained unacknowledged. The capture does not establish a complete Air backlog drain or the cause of that last preemption. Raw filtered history is ignored in `ObserverRefreshAirQuietRepair-20260912.txt`. Xcode log capture remains attached to this Air launch.

Follow-up inspection recovered the second refresh's purpose: an effort rating was saved at **19:10:01.830–01.860**, with resulting Training Load deliveries, followed by a Training Load-only refresh that acknowledged its current receipt at **19:10:09.113**. `refreshAfterWrite(.trainingLoad)` waits for the active refresh then claims visible metric-refresh ownership. Both manual saves and successful Auto-Apply call it; Auto-Apply during the first refresh is the timing-supported explanation, not a uniquely identified trigger. Moving that automatic follow-up into quiet maintenance remains outstanding. The same Air logs report Watch compute seeds around **54.6 KB**, exceeding the **50 KB** limit and being dropped; track this independently from refresh scheduling. Consolidated Pro/Air results and all remaining work are in [the implementation evidence](plans/observer-repair/05-implementation-evidence.md).
