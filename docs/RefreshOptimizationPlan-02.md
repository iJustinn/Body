# Refresh Optimization Plan 02

Second-pass project review ahead of the 1.0.1 release, with two goals:

1. **Publish-blocking bugs/gaps** in the current code (Part 1).
2. **Cutting the per-app-open data refresh from ~10 s to ~5 s** without degrading user experience (Part 2).

> **Status (2026-08-28):** Review only — nothing in this document is implemented yet.
> Baseline: branch `body-1.0.1`, version 1.0.1 build 8, commit `74a5945`.
> Prior pass: `docs/RefreshOptimizationPlan-01.md` took cold-launch refresh from ~15–20 s to ~10 s. Its steps 2–6, 10–12 and follow-ons A–K are implemented; steps 1 (telemetry, now partly done — see §6), 7 (anchored queries), 8 (UUID merge), 9 (observers + background delivery), 14 are not. §5 below re-evaluates the unstarted ones against the 10→5 goal.
> Adversarial review: a Codex read-only review ran against this document (2026-08-28); its session stalled before producing a final report, but the two discrepancies it surfaced mid-run were verified and folded in: the default-layout trend census excludes the 9 secondary-source queries (gated on "no comparison"), and VO₂max is one batched range query per month, not a per-workout fan-out. A second, full adversarial review by a Claude agent (same day) was verified and folded in throughout: §1.1(b) downgraded (the readiness recompute is bounded at ~408 days, not uncapped), the trend census corrected to 17 primary leaves, **P0-A redesigned to merge cached series inside the fetch layer** (the original sequencing would have persisted a collapsed readiness history), the readiness-baseline question answered (57 days), P0-C split into two pools, P1-D/P1-E risk labels corrected, and a new pull-to-refresh lever added (P0-B2).

---

# Part 1 — Publish-blocking bugs and gaps

Two findings rise to release-gate level (§1.2, §1.3); §1.1 was downgraded to a should-fix launch hitch on adversarial review. Everything else checked came back clean (see §1.4) or is a non-blocking note (§1.5).

## 1.1 (MEDIUM, was HIGH) Main-thread work in `HealthKitWorkoutStore.init` before the first frame

`BodyApp.swift:11` builds the store as a `@StateObject`, so `init` runs on the main thread before the first frame. Two verified problems inside it:

**a) The largest cache is decoded twice per launch.** The default init arguments perform three synchronous file read+decodes (`HealthKitWorkoutStore.swift:622-624`; the remaining defaults at `:625-629` are UserDefaults reads), including `HealthDashboardSnapshotStore.loadOrEmpty()` — years of ring history plus ~365-point series across ~20 metrics. Then `HealthDashboardSnapshotStore.loadSummaryContextSignature()` (`Body/Services/HealthDashboardSnapshotStore.swift:377-383`) does its **own** `Data(contentsOf:)` + full `JSONDecoder().decode` of the *same file*. The `SummaryContextSignatureProbe` discards most fields, but `JSONDecoder` still tokenizes the whole document.

**b) A readiness recompute on a path the code itself says must stay cheap.** The comment at `HealthKitWorkoutStore.swift:652-656` explains the readiness recompute is skipped at init because it "would block the first frame." But the `hasStaleReadinessOverlay` exception right below (`:674-682`) calls `filtered(by:)` inline, which resolves to `filteredWithoutReadinessRecompute` + `recalculatingReadiness` (`HealthSummarySnapshot.swift:713-724`), running `ReadinessScoreCalculator.dailySeries` from `oldestTrendDate` at `:794-806`. Every other call site pushes this to `Task.detached`.

**Severity calibration (downgraded on adversarial review):** the recompute is structurally bounded, not uncapped — every readiness source series is *replaced wholesale* each refresh from a ≤ 365-day window (408 d for training load, `TrainingLoadCalculator.swift:14`); there is no accumulate path in `HealthTrend.swift`, so the span cannot grow with install tenure. Worst case is ~408 iterations against pre-built binary-searchable baseline caches (`ReadinessScoreCalculator.swift:63-115, 214-251`) — tens to low-hundreds of ms. Combined with the double decode this is a **launch hitch** (and the branch fires after any permission/source/grouping/sleep-goal change made while the app was closed, or after a failed refresh), not a plausible watchdog kill. Worth fixing, not publish-blocking.

**Fix direction:** return the context signature from the single `loadOrEmpty()` decode instead of re-reading the file; defer the stale-overlay recompute to the same `Task.detached` + `cacheEpoch`-recheck shape already used at `HealthKitWorkoutStore.swift:5088`, publishing `filteredWithoutReadinessRecompute` synchronously in the meantime.

## 1.2 (HIGH) Widget "System" background renders black-on-black on light-appearance devices

`BodyWidgetExtension/Assets.xcassets/WidgetBackground.colorset/Contents.json` holds a **single universal** sRGB black with no `appearances` array — pure black in both light and dark. In `bodyWidgetBackground` (`BodyWidgetExtension/WorkoutCalendarWidget.swift:203-219`), `.black` and `.white` pin `\.colorScheme`, but `.system` — the **default** for all five home-screen widgets (`configuration.background ?? .system` at `HealthMetricWidget.swift:73`, `HealthTrendWidget.swift:152`, `SleepStagesWidget.swift:55`, `WorkoutCalendarWidget.swift:108`) — does not. On a light-appearance iPhone the content views resolve light-scheme adaptive colors (dark text) over the black background.

Worst case is first-run: a fresh non-Pro install shows `BodyWidgetLockedView` ("Unlock Body widgets in the app") with its `.primary`/`.secondary` text unreadable against the black background in the widget gallery (the yellow lock glyph stays visible). `TestPlan.md` M5 requires readable labels per background choice; a tester on a dark-mode phone passes it, which is why this has survived since v0.1.0. `ExerciseWeekWidget` is unaffected (accessory family, `.clear` container).

**Fix direction:** either add a light-appearance variant (white) to `WidgetBackground.colorset`, or — matching the app's dark-only design — pin `.environment(\.colorScheme, .dark)` in the `.system` branch too.

## 1.3 (HIGH, release gate not code change) RevenueCat dashboard values are unverifiable from source

`Body/Services/RevenueCatConfiguration.swift:20` sets `proEntitlementID = "Body: Health Dashboard Pro"`. A colon-and-spaces string is atypical for a RevenueCat entitlement *identifier* (usually a slug like `pro`) and reads like a display name. If it doesn't exactly match the dashboard entitlement id, `entitlements[...]?.isActive` is always nil: the customer is charged and Pro never unlocks (graceful `.completedNotUnlocked` degradation, but still a broken purchase and a Guideline 3.1.1 rejection).

Compounding it, the shared scheme attaches `Body.storekit` to the **Run** action (`body.xcodeproj/xcshareddata/xcschemes/Body.xcscheme:66-68`), so local purchase testing never touches RevenueCat's backend — exactly the configuration that masks a wrong id. `CustomerCenterView()` at `BodySettingsView.swift:98` likewise needs Customer Center configured in the dashboard or "Manage Purchases" opens empty.

**Release gate:** verify in TestFlight/sandbox with the StoreKit config detached — buy, restore, reinstall, refund, Customer Center. (Already tracked as `docs/issues-fable-5.md` H6 and `issues-sol-56.md`.)

## 1.4 Verified green (no action needed)

- **Build** exits 0. RevenueCat SPM genuinely in the project (`purchases-ios-spm` 5.80.2 pinned in committed `Package.resolved`; `RevenueCat` + `RevenueCatUI` linked). No missing-SDK risk.
- **Version/doc guards:** `ProjectConfigurationTests` all pass; `MARKETING_VERSION 1.0.1` / `CURRENT_PROJECT_VERSION 8` consistent across targets, README/VersionHistory/TestPlan aligned.
- **Purchases code:** clean StoreKit 2 removal; restore distinguishes "purchased but unresolved" from "nothing to restore"; Ask-to-Buy doesn't unlock; double-charge guarded.
- **Entitlements/App Group:** `group.com.zihengthedeveloper.Body` identical across all four entitlement files; HealthKit only on app + watch.
- **Info.plist / privacy:** BGTask identifier matches the scheduler; NSHealth* strings present and localized; `ITSAppUsesNonExemptEncryption = NO`; `PrivacyInfo.xcprivacy` in all three bundle targets with correct declared reasons.
- **Data-loss:** both snapshot stores write `.atomic`, encode-before-write, byte-compare dedupe. No truncating path.
- **Crash traps:** zero force unwraps in the 6,492-line store; no `try!`/`fatalError` outside safe idioms; continuations on the `runCancellableQuery` path resume exactly once via the lock-guarded `CancellableQueryCoordinator` (the sites that bypass it are listed in §1.5); 120 s refresh deadline intact.
- **Widget/watch fresh install:** providers return placeholders, explicit localized empty states, no HealthKit in widget targets, nil-safe App-Group reads.
- **zh-Hans:** 1,503 keys across 10 catalogs — 0 missing, 0 needs-review, CI-guarded.

## 1.5 Non-blocking notes

- `MetricWarningBackgroundEvaluator.swift:97-112` — reentrant actor holds a `ledger` copy across `await postNotification`; a concurrent `seed()` can be overwritten (lost update → possible duplicate notification). Reload the ledger after each `await`.
- `MetricWarningBackgroundEvaluator.swift:161-174` — the stated deadline isn't enforceable (`await work.value` after `cancel()` still hangs if a continuation never resumes). Leaks a task; not a BGTask crash since the expiration handler completes independently.
- ~12 reads (`HealthKitFetchEngine.swift:984, 1062, 1111, 1217, 1289, 1356, 2053, 2325, 2437, 2522`, `+HeartRateRecovery.swift:91`, `+MetricSeries.swift:316`) and 2 writes (`+Write.swift:304, 323`) skip the `runCancellableQuery` deadline machinery; on the app side these are bounded by the 120 s refresh deadline, not a crash. `BodyHealthQuantityFetch.swift:120` is in `BodyWatchSnapshotKit` (a watch target) where that deadline does **not** apply.
- `HealthWidgetTrendChartView.swift:189` — `0...(maximum + maximum * 0.08)` traps if `maximum < 0`; unreachable today (all `.bar` metrics non-negative) but live the moment a signed metric becomes `.bar`. Floor the upper bound.
- `BodyMetricsKit.xcstrings` `"Active %@"` / `"Total %@"` → zh `活动消耗` / `总消耗` drop the `%@`, so Chinese workout detail loses the "kcal" value. Safe at runtime, cosmetic gap.
- Watch corner/circular complications show a bare `applewatch` glyph with no text before first sync; exercise widget asserts "0 MIN THIS WEEK" with no snapshot rather than an unknown state.

---

# Part 2 — Refresh: 10 s → ~5 s

## 2. The critical path today

### 2.1 Entry

Cold launch with an existing cache (the ~10 s case):

```
BodyApp.swift:69  .task(priority: .utility) → syncWhenAppBecomesActive
  ↳ :3531 guard !needsInitialHealthDataLoad      (true first launch → BodyFirstLaunchOverlay path)
  ↳ :3546 < 5 min since lastSuccessfulRefreshDate → refreshWorkoutMonth only
  ↳ :3560 else → requestAuthorizationAndRefresh(intent: .passiveResume)
       ↳ :943 runRefreshWithDeadline(120s) { refreshRecentMonths(intent:) }
```

`.passiveResume` matters: `monthCount = 1` (2 across a wake-cycle/auto-apply month boundary, `:4134-4139`), `reusesCachedWorkoutHeartRate = true` (`:4164`), and `clearWorkoutEffortCache()` is skipped (`:4152`). Pull-to-refresh is `.userInitiated` → 3 months + a full effort-cache wipe, so **pull-to-refresh is materially more expensive than launch** — likely the path behind a "10 seconds" observation. Both are targets here.

### 2.2 Shape of `refreshRecentMonths` (`HealthKitWorkoutStore.swift:4112-4241`)

```
await hydratePersistedDaySamplesIfNeeded()          :4116  serial, disk (memoized Task)
await engine.setHealthTrendAnchorDate(date)         :4117  serial

async let workoutRefresh { refresh(monthKeys:) }    :4159  ─┐ concurrent
await fetchHealthDataSourceOptions(calendar:)       :4172   │ (0 queries steady-state; latched)
await fetchDashboardSnapshotProgressively(...)      :4174   │ summary ‖ trends
await updateHealthDashboardSnapshot(...)            :4183   │ full readiness + stress recompute #1
try await workoutRefresh                            :4193  ─┘ JOIN

── serial tail, all awaited, all after the join ──
updateCachedComputeTrainingLoadSeedIfNeeded         :4208
markRefreshSucceeded                                :4221
seedMetricWarningNotificationLedger                 :4222
updateCurrentMonthSnapshot                          :4223
reapplyActivityReadinessAfterWorkouts               :4224  readiness top-up + save #2 + widget #2
recomputeStress                                     :4226  ★ stress recompute #2 + save #3
publishWatchSnapshot                                :4227
startStressInputLoadIfNeeded                        :4228  fire-and-forget (correct)
updateHealthDataNotice                              :4229
await autoApplyPredictedEffortIfNeeded              :4232  ★ can issue NEW HK month fetches + HK writes
```

### 2.3 Query census (all permissions on, default layout)

`BodyDashboardFetchSelection.load()` defaults `starredMetric` to `.readiness` (`BodyAppearancePreference.swift:1029-1032`), which expands `readinessDependencyKinds` (`:933-941`) — the default layout fetches essentially everything.

| Phase | HK round-trips | Window | Concurrency |
| --- | --- | --- | --- |
| `fetchHealthSummary` (`Engine:2554-2761`) | ~23 leaves (sleep = 6, 2 sequential stages) | mostly 365 d `limit:1`; 5 leaves today-only | 22 bare `async let`, **unbounded** |
| `fetchHealthTrends` (`Engine:2763-3129`) | 26 `async let` leaves = **17 primary** + 9 secondary (secondary only when the user has enabled a comparison source — `fetchSecondaryIfEnabled` at `Engine:658-669` returns early on the default "no comparison"). Of the primaries, ~15 are `HKStatisticsCollectionQuery`; the four avg/min/max "pair" leaves are **one** query each (`options: [.discreteAverage, .discreteMin, .discreteMax]`, `Engine:1016-1019`) | **365 d for every leaf** | bare `async let`, **unbounded** |
| Training load (`+TrainingLoad.swift:29-50`) | 1 workout query + **1 effort query per workout over 408 d** | 408 d (`TrainingLoadCalculator.swift:14`) | effort pool = 12 |
| Workout months (`Store:4845-4916`) | per month: 1 workout + 1 batched HR + 1 batched VO₂max (`Engine:2292-2326`, single range query) + N effort + N cadence + N distance | 1 month (passive) / 3 (pull) | 3 independent per-workout pools × 12, × months |
| Sleep | 12 total (6 summary, 6 trends) | 14 d + 365 d | 5-wide |
| Rings | 1 (3-month window) — already off-path via `startActivityRingHistoryLoadIfNeeded` (`Store:4470-4491`) | 3 months | separate Task |
| Source options | 0 steady-state (latched by permission signature) | — | — |

**Peak in-flight HK queries: can exceed 100.** There is no global concurrency budget — the three per-workout pools (effort `Engine:2211`, cadence `:2378`, distance `:2465`) each cap at 12 *independently*, concurrently across months and concurrently with ~45 unbounded dashboard leaves. `healthd` is a single XPC service; past roughly 8–16 concurrent queries the app buys queueing and IPC overhead, and the *visible* summary leaves wait behind the invisible workout fan-out.

### 2.4 Where the ~10 s plausibly goes (estimates — §6 exists to replace these with data)

| Component | Est. share | Confidence |
| --- | --- | --- |
| ~15 × 365-day `HKStatisticsCollectionQuery` in `fetchHealthTrends` | 2–3 s | med-high |
| ~21 `fetchHealthSummary` leaves (mostly 365 d `limit:1` latest-sample reads — cheap individually, but they share the unbounded pool and are the *visible* Home-card bucket) | 0.5–1 s | med |
| 408-day training-load workout fetch + per-workout effort fan-out (cold) | 2–3 s | med-high |
| 365-day sleep history + 5 OR-compound nightly-vital queries, no limit | 1–2 s | med |
| Workout months: per-workout effort/VO₂max/cadence/distance fan-out | 0.5–2 s | med |
| Serial tail: 2× stress recompute, readiness top-up, `autoApplyPredictedEffortIfNeeded` | 0.5–1.5 s | med |
| Contention/queueing loss from 100+ concurrent queries | 0.5–1.5 s | low |

## 3. Ranked optimizations

Ordered by (estimated seconds saved) / risk. Suggested implementation sequence is in §7.

### P0-A — Two-phase trend window with the merge INSIDE the fetch layer
**Est. 1.5–2.5 s · Medium risk · The flagship change** *(redesigned after adversarial review)*

`recentHealthTrendInterval` (`Engine:595-607`) always resolves to `BodyHealthTrendRange.maximumDayCount` = **365** (`BodyMetricsKit/BodyHealthSelections.swift:577-590`) for *every* leaf on *every* refresh — while `BodyHealthTrendRange.defaultValue == .recentWeek` and the user's actual range lives in `@AppStorage(defaultTrendRangeKey)` (`BodyHomeView.swift:330`). A user on Week pays for 358 days of scan on ~22 leaves they never look at.

**Change:** thread a `windowDays` into `fetchHealthTrends`, and make each windowed leaf return **cached-beyond-window + fresh-within-window**, merged *inside* `fetchHealthTrends` before anything downstream sees the result. The machinery already exists: `fetchHealthTrends` already receives `cachedTrends` (`Store:4409-4413`) and already carries cached fields forward on exactly this pattern for stress (`Engine:2790-2795` → `:3101-3124`). Phase 1 fetches the user's actual range and publishes through the existing progressive path; phase 2 fires *after* `finishRefresh()` (same pattern as `startStressInputLoadIfNeeded`, `Store:4228`) to refetch the full 365 d.

**Why the merge location is load-bearing (original design was unsafe):** `updateHealthDashboardSnapshot` recomputes readiness from whatever trends it is handed (`Store:5088-5114` → `HealthSummarySnapshot.swift:794-806`), and `recalculatingReadiness` scores each day against that day's own prior 56 days (`ReadinessScoreCalculator.swift:270`). Handing it a bare 60–90-day window would score most of the visible chart as nil/degraded, assign the collapsed series to the published state (`Store:5128-5131`), save it (`Store:5152`) — and if the 120 s deadline fired before phase 2, `persistPublishedDashboardSnapshot` (`Store:554-594`) would make the collapse **durable**, violating the §4 abandonment invariant. Merging in the fetch layer means the recompute always sees a full-span series, so readiness, the widget builder, and `WatchComputeSeed` are all automatically correct with no special-casing.

**Readiness-baseline question — answered:** today's score is fully determined by a **57-day** window (`baselineDayCount = 56` at `ReadinessScoreCalculator.swift:270` + the scoring day; `recentExclusionDayCount`/`minimumBaselineDayCount`/confidence tiers all count points *inside* those 56 days). With the fetch-layer merge, though, the baseline length stops gating the phase-1 window at all — the window can be as short as the user's actual range.

**Remaining risks:**
- Cache-vs-selection mismatch: `currentPrimarySelectionSignature()` (`Store:4388-4390`) gates **summary** reuse, not trend series — there is no per-trend-series signature today. The precedent for scoping cached trend data to a selection is `scopedForHydration` on the day-sample sidecar (`Store:2134-2140`); the merge needs an equivalent guard (on mismatch, fetch the full window).
- `BodyHealthTrendRange.recentTrendWindowStart` (`BodyHealthSelections.swift:580-583`) is documented as the shared boundary for both trend charts and summary latest-sample queries "so a card can never show a value its own chart has no room for" — with cached points filling the chart beyond the fetch window, that invariant is preserved in effect, but the doc-comment's premise changes; keep summary and phase-2 windows aligned.
- Mid-refresh navigation to a Year chart shows cached-year + fresh-recent — correct, not stale.

### P0-B — Persist the workout effort ledger across launches
**Est. 1–2 s · Low risk**

`effortLevelsByWorkoutID` / `confirmedNoEffortWorkoutIDs` (`Engine:58-59`) are actor-local and never persisted. Every process start re-queries `HKWorkoutEffortScore` once per workout across the 408-day training-load window (`fetchEffortLevels` `Engine:2192-2275`; per-workout `BodyWorkoutEffortFetcher.savedEffortOutcome`, a relationship-predicate `HKSampleQuery(limit:1)`). For a 5×/week athlete that's ~290 queries in ~24 waves of 12, every cold launch.

**Change:** persist the two maps (precedent: `WorkoutRecordLedgerStore.swift`); hydrate the engine at init. Only persist entries older than `effortConfirmationAge` and re-query the trailing ~7 days each launch, so a score edited in Apple Fitness converges without a manual refresh. `clearWorkoutEffortCache()` on `.userInitiated` (`Store:4152`) stays as the full-reconcile escape hatch.

**Why UX-safe:** effort scores for aged workouts are immutable — already the premise of `confirmableNoEffortWorkoutIDs` (`Engine:2136-2146`). Body's own writes go through `saveWorkoutEffort` (`Store:1125`) and can update the ledger directly.

### P0-B2 — Scope the `.userInitiated` effort-cache wipe
**Est. 1–2 s on pull-to-refresh · Low-medium risk** *(added after adversarial review — the doc previously had no lever for this)*

P0-B by construction does **not** help pull-to-refresh: `.userInitiated` calls `clearWorkoutEffortCache()` (`Store:4152` → `Engine:280-281`) *before* `sharedTrainingLoadWorkouts` runs, so every pull re-pays the full per-workout effort fan-out over 408 days (`fetchEffortLevels` runs unconditionally at `Engine:1844`, including for the training-load fetch, which passes `includesDetailMetrics: false` but gets no effort skip). Since pull-to-refresh is the path §2.1 identifies as the likely "10 seconds," the plan needs a lever here.

**Change:** scope the `.userInitiated` wipe to the displayed month keys (the months the user is actually looking at and could have edited in Fitness), keeping the persisted ledger for the rest of the 408-day training-load window; or equivalently exempt the training-load-only fetch from effort re-query. The trailing-7-day re-query from P0-B still catches recent external edits. **Risk:** an effort score edited in Apple Fitness on a workout months old converges only via the displayed-month path — acceptable, since such edits are rare and the current behavior (full wipe) remains available via clear-cache in Settings.

### P0-C — HealthKit concurrency budget: two pools, not one
**Est. 0.5–1.5 s · Low-medium risk · Do first — it de-risks everything else** *(revised after adversarial review)*

Bound in-flight HealthKit queries with **two separate pools** on the engine: an *interactive* pool (~8–12 permits) for refresh-path queries, and a smaller *background* pool for the long walks deliberately kept off the refresh path — the ten-year ring backfill (`+ActivityRings.swift:410`; the store comment at `Store:4456-4464` says it "can run for minutes or hang outright"), the stress backfill (`+StressBackfill.swift:284`), and lazy month/intraday loads. Today the three per-workout pools (`Engine:2211/:2378/:2465`) each cap at 12 independently and the ~45 dashboard leaves cap at nothing.

Why not one global pool: `AsyncSemaphore` has no priority, so a single budget would let a minutes-long (or hung) background ring query starve the visible summary leaves — and the 120 s deadline bounds the *refresh*, not those background walks, so `defer`-released permits don't save you from a query that never resumes. Two pools keep a stuck background walk from touching refresh latency at all. Implementation surface: 16 sites (14 direct `healthStore.execute` calls + the `CancellableQueryCoordinator` path), not one choke point — budget the wrapper functions, not each site.

### P1-D — Drop the second full stress recompute
**Est. 0.3–0.8 s · Low risk**

`recalculatingStress` runs twice per refresh: `Store:5105` (inside `updateHealthDashboardSnapshot`, before the workout join) and `Store:5265` (inside `recomputeStress`, after it — the comment at `:4225` explains the activity mask needs workouts). The first pass's result is thrown away.

**Change:** the switch already exists — `updateHealthDashboardSnapshot` takes `recomputesStress: Bool = true` (`Store:5062`, consumed at `:5104`, already passed `false` at `:1043`) — so the effort is smaller than it looks. But flipping it is **not** enough on its own: the cached-stress preservation at `Store:4433-4435` covers only the progressive publish, while the final publish at `:5128` assigns `healthSummary = filteredSnapshot.summary` unconditionally — and per the comment at `:4430`, a fetched summary "always carries them [readiness and stress] empty." Skipping the first recompute therefore **must** also carry the cached stress into the final publish (e.g. `.replacingMetric(.stress, with:)` at `:5128`, mirroring what the trend side already does at `Engine:2790-2795`/`:3101-3124`), or the Stress card blanks between `:5128` and `recomputeStress` landing at `:5250` — and the abandonment path would persist the blank. That carry-forward is part of the change, not a residual risk.

### P1-E — Move `autoApplyPredictedEffortIfNeeded` off the awaited path
**Est. 0–1 s (bimodal) · Medium risk** *(risk raised after adversarial review)*

`Store:4232` awaits it last; it can trigger **new** `refresh(monthKeys:)` HK fetches for missing months (`:1463, :1504`) and writes to HealthKit. Nothing on screen waits for it, and it already fires its own `Task { refreshAfterWrite(.trainingLoad) }` (`:1563`) when it applies something.

**Why a bare `Task { … }` is wrong:** the doc-comment at `Store:1569-1580` states the invariant explicitly — running inside the refresh means its internal `refresh(monthKeys:)` calls "can't interleave with a concurrently starting real refresh, and every other entry point (all `guard !isRefreshing`) stays out while the pass runs." Detaching it lets `finishRefresh()` clear `isRefreshing` while the pass is mid-flight, so a pull-to-refresh or scene resume can mutate `monthSnapshots`/`loadingMonthKeys` concurrently and duplicate the `HKHealthStore.save` effort writes; `isAutoApplyingEffort` (`:1441/:1448`) only guards re-entry into auto-apply, and a generation check doesn't cover the interleaving.

**Change:** detach it, but have the detached pass **claim the refresh slot** the way `autoApplyPredictedEffortNow()` does — or keep it awaited and instead make its month fetches cheap (they get cheaper anyway once P0-B lands).

### P1-F — Collapse redundant snapshot + widget writes
**Est. 0.1–0.4 s · Low risk**

`HealthDashboardSnapshotStore.save` fires up to 3× per refresh (`Store:5152, :5330, :5440`) and `saveHealthWidgetSnapshot` 2× (`:5160, :5446`), each a full JSON encode of summary+trends, and `save` re-reads the file for its byte-compare (`HealthDashboardSnapshotStore.swift:255`). All are off-main on `snapshotPersistQueue`, so the win is modest — coalesce to one write after the tail settles.

### P1-G — Reuse immutable per-workout detail metrics
**Est. 0.3–1 s · Low-medium risk**

`fetchCardioFitness` / `fetchStepCadence` / `fetchWorkoutDistances` (`Engine:2291, 2366, 2454`) have no session cache and re-run every refresh — cadence and distance as per-workout query pools, VO₂max as one batched range query (cheap; the win here is mostly cadence/distance); `reusableSummariesByID` (`Store:4870-4878`) is only a *failure* fallback, and `heartRateReuseEligibleWorkoutIDs` (`Engine:1987-2010`) covers HR only, passive-resume only.

**Change:** extend the aged-workout reuse gate (> `heartRateReuseMinimumAge` = 24 h) to VO₂max/cadence/distance from cached summaries. **Caveat verified in code** (`Engine:1851-1856`): a workout cached before those fields existed decodes them as nil — gate reuse on the field being non-nil, not on the workout being cached.

### P1-H — Clamp the stress-input HRV window
**Est. 0.1–0.3 s (stress-only layouts) · Very low risk**

`sleepHistory` (`Engine:2800-2806`) is `.inputCapable` and clamps to `stressInputSleepHistoryDays = 100`; `heartRateVariabilityPair` (`Engine:2874-2878`) is also `.inputCapable` but gets **no** `maxDays` clamp — stress-only layouts still pay 365 d. Subsumed by P0-A, but trivially fixable now.

### P2-I — Derive the sleep summary from sleep history — **deliberately deferred**

`fetchSleepSummary` (`+Sleep.swift:15-73`) largely overlaps `fetchDailySleepHistory` (`+Sleep.swift:83-158`) — the summary corresponds to the history's last day (`:51-56`) — but it is **not** a strict subset: the summary scopes vitals to the nap-excluding `mainSessionInterval` (`:57-72`) and fails atomically on any vital failure, while the history hydrates per-night and merges cached vitals on failure. So deriving one from the other is a semantic change, not a pure refactor. The summary queries are also cheap (14 d, one night) and the two leaves are concurrent siblings: coupling them would serialize the fast Home-card bucket behind the slow trends bucket and make one failure blank both. Revisit only after P0-A shrinks the history window, if at all.

## 4. Invariants that must survive this pass

- **120 s refresh deadline + bounded ring queries** — refresh must never hang. P0-C's semaphore must release permits in `defer` so a hung query can't starve the pool past the deadline.
- **Input-only fetch tier** — leaves default `fullOnly`; the 3 `inputCapable` leaves keep their clamps; new leaves must opt in for stress-only layouts.
- **Progressive 3-bucket publish + per-month workout streaming** — P0-A phase 1 publishes through this path; nothing may regress the early Home-card paint.
- **Abandonment path** (`persistPublishedDashboardSnapshot`) must keep persisting a coherent snapshot if the deadline fires mid-refresh (relevant to P1-D and P0-A phase 2).

## 5. Verdict on the unstarted RefreshOptimizationPlan-01 items

| Item | Verdict |
| --- | --- |
| Step 7 — `HKAnchoredObjectQuery` | **Skip.** The trend path is now almost entirely `HKStatisticsCollectionQuery` (Steps D1/D2), which has no anchored equivalent — a statistics collection cannot be updated incrementally. Anchors would help only the 3 remaining unlimited `HKSampleQuery` sites and would require a client-side aggregation layer replacing what `healthd` does. High cost, high risk; P0-A gets more of the same win. |
| Step 8 — UUID merge | **Skip for this pass.** Depends on Step 7; its real benefit is list-animation stability, not refresh time. |
| Step 9 — `HKObserverQuery` + background delivery | **Defer.** Changes *when* the cost is paid, not its size; valuable for perceived freshness later, but adds a re-entrancy surface against the `@MainActor` store and is not the 10→5 lever. |
| Steps 1/14 — telemetry | **Do first** — see §6. |

## 6. Measurement first

Every number in §2.4 is an estimate. `BodyPerformanceSignposts` (`Body/Utils/BodyPerformanceSignposts.swift:11`) already provides 8 coarse intervals (`RefreshRecentMonths`, `DashboardSummary`, `DashboardTrends`, `WorkoutMonths`, `ReadinessRecompute`, `SourceOptions`, `TrainingLoadWorkouts`, `SleepVitalsHydration`, plus 3 in the snapshot store) — what's missing is per-leaf granularity and readability without Instruments.

1. **Per-leaf signposts.** Wrap each `async let` in `fetchHealthSummary` (`Engine:2559-2695`) and `fetchHealthTrends` (`Engine:2800-3031`) with a signpost interval named by metric kind via a small `withLeafSignpost(_:) async -> T` helper. Add one around the effort pool in `fetchEffortLevels` (`Engine:2212`) emitting the candidate count — that number decides whether P0-B is worth 2 s or 0.2 s.
2. **Debug aggregate log.** A `[String: TimeInterval]` on the engine populated by the same helper, dumped once via `os.Logger` at `finishRefresh()` (`Store:417`) under `#if DEBUG` — a sorted per-leaf table in Console on a real device, no Instruments trace needed.
3. **Concurrency-depth counter.** Increment/decrement around `healthStore.execute`; log the high-water mark at refresh end. This directly confirms or falsifies P0-C (the one low-confidence line).
4. **Baseline protocol.** Same device, same Health DB, 3 runs each of: (a) cold launch > 5 min stale → `.passiveResume` full path; (b) Home pull-to-refresh → `.userInitiated` 3-month path; (c) warm resume 60 s–5 min → `refreshWorkoutMonth` only. Record `RefreshRecentMonths` wall time + the per-leaf table. Path (b) is the most expensive and is likely what "10 seconds" refers to.
5. **Measure launch-to-usable, not just the refresh signpost.** Two costs this document itself raises sit *outside* `RefreshRecentMonths`: the §1.1 init decodes (pre-first-frame) and `BodyApp.swift:66-68`'s awaited `hydratePersistedDaySamplesIfNeeded()`, which blocks on a full decode of the day-sample sidecar before `syncWhenAppBecomesActive()` even starts (already signposted as `DaySamplesSidecarLoad`). If "~10 s" is user-perceived, the cold-launch baseline must be launch → first-usable-frame with those intervals included.

## 7. Suggested sequence

1. §6 telemetry (no behavior change) → capture baseline, including launch-to-usable.
2. **P0-C** two-pool concurrency budget — so later wins aren't eaten by queueing.
3. **P0-B** effort ledger persistence, then **P0-B2** scoped `.userInitiated` wipe — together they cover both the launch and pull-to-refresh paths.
4. **P1-D / P1-F** tail cleanup (P1-E only with the refresh-slot claim, or deferred).
5. **P0-A** two-phase trend window with the fetch-layer merge — the big one; the readiness-baseline question is answered (57 d) and no longer gates the window.
6. **P1-G / P1-H** as follow-ups; re-measure after each step against the §6 baseline.

Expected trajectory: P0-B/B2 + P0-C + P1-D/F plausibly reach ~7 s on both paths; **P0-A is what gets to ~5 s.**
