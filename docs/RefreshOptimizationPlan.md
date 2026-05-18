# Refresh Optimization Plan

A targeted revision plan to reduce unnecessary HealthKit reloads, speed up app startup, and prefer incremental updates over full reloads.

> **Status (2026-05-18):** Steps 2, 3, 4, 5, 6, 10 (audit-only), 11, 12, plus the follow-on A, B, C, D1, D2, E1 (off-main refresh hot paths), and E2 (extract `HealthKitFetchEngine` actor) work are **implemented**. Observed cold-launch refresh dropped from ~15–20 s to ~10 s after A/B/C; D1+D2 add HK-side daily aggregation and pair the daily-average + range queries for HR/HRV/RR/SpO2 into single queries; E1 moves the day-by-day Recovery recompute and the dashboard/widget JSON writes off the main actor; E2 relocates all HK queries and dashboard fetch orchestrators to a non-`@MainActor` actor so refresh-time Swift work stops queueing behind UI on `@MainActor`. Steps 1 (telemetry), 7 (anchored queries), 8 (UUID merge), 9 (observer + background delivery), and 14 (telemetry surface) remain unstarted. See the bottom of this file for the implementation log.

This document describes the *current* state, the *proposed* changes, and (at the end) the implementation log so future work can pick up where this pass left off.

---

## 0. Glossary & key files

| Symbol / file | Path | Role |
| --- | --- | --- |
| `HealthKitWorkoutStore` | `Body/Services/HealthKitWorkoutStore.swift` | `@MainActor` `ObservableObject` that owns all HealthKit fetching and in-memory caches. ~3,500 LOC. |
| `WorkoutSnapshotStore` | `BodyShared/Services/WorkoutSnapshotStore.swift` | App‑Group JSON cache for the **current month** workout snapshot. Read by the widget. |
| `HealthDashboardSnapshotStore` | `Body/Services/HealthDashboardSnapshotStore.swift` | App‑private JSON cache for the full health dashboard (`summary` + `trends` + `activityRingHistory`). |
| `BodyApp.swift` | `Body/BodyApp.swift` | App entry; owns `@StateObject` `HealthKitWorkoutStore` and the scene‑phase hook. |
| `MainTabView.swift` | `Body/Views/MainTabView.swift` | Tab container for Summary / Workouts / Settings. |
| `BodyHomeView.swift` | `Body/Views/BodyHomeView.swift` | Summary tab (~8.2k LOC); two `.refreshable` blocks. |
| `BodyWorkoutsView.swift` | `Body/Views/BodyWorkoutsView.swift` | Workouts tab; one `.refreshable` block and one `.task` initial loader. |
| `BodyActivityRingsDetailView.swift` | `Body/Views/BodyActivityRingsDetailView.swift` | Activity Rings detail with backward‑pagination. |
| `WorkoutCalendarWidget.swift` | `BodyWidgetExtension/WorkoutCalendarWidget.swift` | Home‑screen widget; reads cache, never queries HealthKit. |

`recentChartMonthCount = 3` (current month + 2 prior) is the default refresh window.

---

## 1. Where refresh / reload logic currently exists

### 1.1 Startup / init

| Site | File:Line | Triggered by | Data loaded |
| --- | --- | --- | --- |
| `BodyApp` `.task` on `WindowGroup` | `BodyApp.swift:26-28` | App launch (cold or warm) | `workoutStore.syncWhenAppBecomesActive()` → full refresh of recent 3 months + health summary + trends + activity ring history |
| `HealthKitWorkoutStore.init(...)` | `HealthKitWorkoutStore.swift:93-129` | `@StateObject` instantiation | Synchronously reads `WorkoutSnapshotStore.loadOrPlaceholder()`, `HealthDashboardSnapshotStore.loadOrEmpty()`, three `UserDefaults`‑backed selection objects, then **filters and recalculates Recovery** on the cached snapshot in memory |
| `WorkoutSnapshotStore.seedPreviewSnapshotIfNeeded()` | `BodyApp.swift:16` (from `init`) | First launch only | Seeds placeholder workout snapshot if cache is empty |

### 1.2 Scene phase / app resume

| Site | File:Line | Triggered by | Action |
| --- | --- | --- | --- |
| `BodyApp` `.onChange(of: scenePhase)` | `BodyApp.swift:29-37` | Phase becomes `.active` | `syncWhenAppBecomesActive()` (60s debounce inside store) |
| `syncWhenAppBecomesActive` | `HealthKitWorkoutStore.swift:438-449` | Above | Skips if `isRefreshing` or `< 60s` since last `lastAppEntrySyncDate`, else calls `requestAuthorizationAndRefresh()` |
| `BodyMonthYearPicker` `.onChange(of: scenePhase)` | `BodyMonthYearPicker.swift:142-144` | Active phase | `refreshMonthYearListIfNeeded()` — UI list only, no data fetch |

### 1.3 Pull‑to‑refresh

| Site | File:Line | Calls | Scope |
| --- | --- | --- | --- |
| Home summary | `BodyHomeView.swift:271-277` | `requestAuthorizationAndRefresh()` | **Full** — recent 3 months + summary + trends + ring history |
| Metric detail (per kind) | `BodyHomeView.swift:2564-2570` | `refreshHealthMetric(model.kind)` | **Incremental** — one metric only |
| Workouts list | `BodyWorkoutsView.swift:101-107` | `refreshWorkoutMonth(month:year:)` | **Incremental** — one month only |

All three pad with `awaitRefreshCompletion(minimumDurationFrom:)` to guarantee a 0.6 s spinner. (`HealthKitWorkoutStore.swift:421-436`).

### 1.4 Manual / button-driven reloads (Settings & permissions)

`HealthKitWorkoutStore` public methods, with reload scope:

| Method | File:Line | Scope | Reloads widget? |
| --- | --- | --- | --- |
| `requestAuthorizationAndRefresh()` | `:195-212` | Full | Yes (via `updateCurrentMonthSnapshot`) |
| `refreshHealthMetric(_:date:)` | `:214-251` | Single metric (summary + trends only) | No |
| `refreshWorkoutMonth(month:year:)` | `:253-272` | Single month | Yes |
| `refreshCurrentMonth(date:)` | `:582-593` | Current month + summary side effects | Yes |
| `loadRecentWorkoutMonthsIfNeeded(date:)` | `:464-483` | Missing months only | No |
| `loadMonthIfNeeded(month:year:)` | `:486-510` | Single month if not loaded | No |
| `loadPreviousActivityRingMonthIfNeeded(date:)` | `:512-580` | Single previous Activity Ring month | No |
| `updateHealthPermission(...)` | `:274` | Full refresh on enable | Yes |
| `updateHealthDataSource(for:option:)` | `:318` | Full refresh on change | Yes |
| `updateSecondaryHealthDataSource(for:option:)` | `:329` | Metric‑specific | Yes |
| `clearLocalCache(date:)` | `:595-623` | Full reset; clears both stores | Yes |

### 1.5 View‑attached loaders

| Site | File:Line | What it does |
| --- | --- | --- |
| `BodyWorkoutsView` `.task` | `BodyWorkoutsView.swift:145-148` | `loadRecentWorkoutMonthsIfNeeded()` (no‑op if loaded) + UI animation |
| `BodyActivityRingsDetailView` `.task` | `BodyActivityRingsDetailView.swift:136-143` | UI setup only — scrolls to current month, enables `canLoadOlderMonths` |
| `BodyActivityRingsDetailView` month `.onAppear` | `BodyActivityRingsDetailView.swift:203-204` | `loadPreviousMonthIfNeeded(for:)` — paginates back when scrolling up |

### 1.6 Widget timeline

| Site | File:Line | Behaviour |
| --- | --- | --- |
| `WorkoutCalendarProvider.timeline` | `WorkoutCalendarWidget.swift:60-67` | Returns a single entry, `policy: .after(now + 30m)` |
| `WorkoutCalendarProvider.loadEntry` | `:69-75` | `WorkoutSnapshotStore.loadOrPlaceholder()` — pure read of App Group JSON. Widget never queries HealthKit. |
| `WidgetCenter.shared.reloadAllTimelines()` | `HealthKitWorkoutStore.swift:622, 831, 842` | Called from `clearLocalCache`, `clearWorkoutSnapshots`, `updateCurrentMonthSnapshot` |

### 1.7 Notification / observer / timer

- **HealthKit observers**: **none**. No `HKObserverQuery`, `HKAnchoredObjectQuery`, or `enableBackgroundDelivery` anywhere in the app.
- **NotificationCenter**: only `NSCalendarDayChanged` in `BodyMonthYearPicker.swift:139` — refreshes the picker UI; **does not** trigger a data fetch.
- **Timers / periodic loops**: none in the app. Widget uses a 30 min `.after` timeline policy only.

### 1.8 Tab re-entry

`MainTabView` (`MainTabView.swift:14-38`) does not observe `selectedTab`; switching tabs does not trigger any fetch. Each tab's own `.task` handles initial load with `loadedMonthKeys` guarding against repeats.

---

## 2. What each refresh does and when it fires

### 2.1 Full reload — `refreshRecentMonths(date:)` (`HealthKitWorkoutStore.swift:625-660`)

Called from `requestAuthorizationAndRefresh()`. Performs:

1. `refresh(monthKeys:)` — sequential loop fetching `fetchWorkouts(month:year:)` for **each** of the recent 3 months, even when the in‑memory snapshot is identical (`:745-756`).
2. `fetchHealthDataSourceOptions(calendar:)` — queries source lists for every supported `HealthMetricKind`.
3. Concurrently:
   - `fetchHealthSummary(calendar:)`
   - `fetchHealthTrends(calendar:)`
   - `fetchActivityRingHistory(calendar:)`
4. `updateHealthDashboardSnapshot(...)` (`:758-787`) — writes the merged dashboard to `HealthDashboardSnapshotStore`, recomputes Recovery, persists secondary-source signature.
5. `updateCurrentMonthSnapshot(date:calendar:)` (`:834-843`) — writes `WorkoutSnapshotStore` and `WidgetCenter.shared.reloadAllTimelines()`.

This is the heaviest path: **every** `scenePhase → active` fire that survives the 60 s debounce runs it.

### 2.2 Incremental metric refresh — `refreshHealthMetric(_:date:)` (`:214-251`)

Refreshes a single metric's summary + trends; replaces it in the in-memory snapshots via `replacingMetric(...)`. Does **not** refetch workouts or activity rings, and (notably) does **not** call `WidgetCenter.shared.reloadAllTimelines()`.

### 2.3 Incremental workout refresh — `refreshWorkoutMonth(month:year:)` (`:253-272`)

Fetches workouts for one month, updates `monthSnapshots[key]`, then (if it is the current month) calls `updateCurrentMonthSnapshot(...)` which reloads the widget timeline.

### 2.4 Lazy month loads — `loadRecentWorkoutMonthsIfNeeded` / `loadMonthIfNeeded`

Both subtract `loadedMonthKeys` and `loadingMonthKeys` before fetching, and use `loadMonthKeysIfNeeded(_:)` (`:707-743`) which double‑checks before kicking off `fetchWorkouts`.

### 2.5 Activity Rings pagination — `loadPreviousActivityRingMonthIfNeeded(date:)` (`:512-580`)

The cleanest existing incremental path: identifies the month *before* the earliest loaded month, fetches only that month, merges via `activityRingHistory.replacingLoadedMonths(with:)`, and re-persists.

---

## 3. What is unnecessary, duplicated, or too expensive

> **Convention.** Each finding is tagged with severity: **P0 = visible perf or correctness issue, P1 = noticeable churn / wasted work, P2 = nice-to-have.**

### 3.1 (P0) Cold-launch and warm-resume both go straight to the network path

`BodyApp` runs `.task { await workoutStore.syncWhenAppBecomesActive() }` *and* `.onChange(of: scenePhase)` fires for the initial `.active` transition. Because `lastAppEntrySyncDate` is `nil` at launch, the `.task` always runs `requestAuthorizationAndRefresh()`, which schedules ~10 HealthKit queries before SwiftUI has even drawn the cached dashboard. The user sees the spinner state of the in‑flight refresh ahead of the cached data they could have read from disk in <50 ms.

### 3.2 (P0) Every active resume past 60 s does a *full* dashboard reload

`syncWhenAppBecomesActive` only debounces, it does not narrow the scope. If you put the phone down for 10 minutes and reopen, the app refetches **3 months of workouts + every health metric summary + every trend + multi-month Activity Ring history**, even though 99 % of those values cannot have changed. There is no anchor and no per-metric staleness check.

### 3.3 (P1) Recent-month workouts are refetched serially

`refresh(monthKeys:)` (`:745-756`) iterates `for key in monthKeys.sortedByDate` and `await`s each `fetchWorkouts` one at a time. Three months → three serial round-trips. The three calls are independent and would parallelize cleanly under `withTaskGroup` or `async let`.

### 3.4 (P1) No HKObserverQuery / background delivery

The app cannot react to "new workout saved while app was foregrounded" or "new HealthKit sample since last refresh" without a pull. The only signal we get is `scenePhase → active`, so the natural workaround is the 60‑s blanket refresh. `HKObserverQuery + enableBackgroundDelivery + HKAnchoredObjectQuery` (with persisted anchors) is the standard Apple pattern and would let us:

- Fire a narrow refresh only when HealthKit signals new data.
- Use anchors to fetch only deltas instead of `start..now` windows.

### 3.5 (P1) `fetchHealthDataSourceOptions(calendar:)` runs on every full refresh

Source lists almost never change. They are recomputed on every `refreshRecentMonths` call and on every metric refresh. Caching the source list with an invalidation hook (permission change, source-picker change) avoids this work.

### 3.6 (P1) `updateHealthDashboardSnapshot` always rewrites the disk cache

`:779-786` saves to `HealthDashboardSnapshotStore` *and* writes the secondary signature on every successful refresh, even when the snapshot is bitwise unchanged. JSON encode + atomic write of ~100 KB on every resume is wasted I/O. A `prev == next` short‑circuit before save is cheap.

### 3.7 (P1) Widget reloads on every successful refresh, even when the current-month snapshot did not change

`updateCurrentMonthSnapshot` (`:834-843`) unconditionally calls `WidgetCenter.shared.reloadAllTimelines()` after a refresh. iOS rate-limits widget reloads but each call is still a system round-trip and forces a re-render of all 4 widget kinds. We should only reload when the *encoded* snapshot bytes differ from what is already on disk.

### 3.8 (P1) `HealthKitWorkoutStore.init` does a synchronous Recovery recalculation on a 100 KB JSON load

`init` (`:93-129`) reads two JSON files from disk, filters by permission, then `recalculatingRecovery(on:calendar:)` runs over the cached health summary on the main actor. This is part of `@StateObject` setup so it blocks the first frame. The cached snapshot is already correct as of its `lastSuccessfulRefreshDate` — the recompute can be deferred until *after* first paint.

### 3.9 (P2) Pull-to-refresh on the Summary tab uses the full-reload path

`BodyHomeView.swift:271-277` calls `requestAuthorizationAndRefresh()`. The pull gesture is the user's "I think this is stale" signal — but it nukes everything. A more focused "refresh visible cards only" version would still feel responsive while being cheaper.

### 3.10 (P2) `loadRecentWorkoutMonthsIfNeeded` re-runs on every Workouts tab visit even if data is loaded

The guard inside the method correctly short-circuits when `missingKeys` is empty, so this is fine in steady state. **However**, after `clearLocalCache(date:)` (`:595-623`) the workouts tab's `.task` does not re-trigger because the view is already mounted. Cache-clear leaves Workouts blank until the user pulls to refresh.

### 3.11 (P2) `awaitRefreshCompletion` busy-waits with a 100 ms sleep loop

`HealthKitWorkoutStore.swift:421-436` polls `isRefreshing` every 100 ms. An `AsyncStream`/`Combine`-based completion signal would be cleaner and there is already an Issues.md note (N10) about an edge case where this loop could spin forever if `isRefreshing` never flips. Low priority but pairs naturally with this work.

---

## 4. Where to use cached data instead of reloading

| Surface | Currently | Recommended |
| --- | --- | --- |
| First frame after launch | Cached values are present via `init`, but the in-flight refresh covers them immediately. | **Render cached values immediately** (already happens). Delay the network refresh until the first frame is committed (see §6). |
| `scenePhase → active` after short backgrounding (e.g. 60 s – 5 min) | Either skipped (<60 s) or full reload (≥60 s). | Tier the staleness: workouts can use a longer TTL (e.g. 10 min) than Recovery; some metrics (height, body mass) almost never change and could have a 24 h TTL. |
| Settings entry / Settings → Permissions | No fetch; reads `cacheStatus` view-model fields. | Keep as-is. |
| Workouts tab opening when months are loaded | Reads `monthSnapshots[key]`. | Keep as-is. |
| Workouts tab opening to a not-yet-loaded month | `loadMonthIfNeeded` fetches. | Keep, but display the cached widget snapshot as a placeholder while loading (currently a spinner). |
| Activity Ring detail scroll-up | Already incremental. | Keep as-is. |
| Widget refresh | Reads `WorkoutSnapshotStore`. | Keep. Optionally add a second cached snapshot for prior month to avoid widget showing "no data" the morning of a month-rollover before the first app launch of the new month. |
| Source picker (Health Data Sources sheet) | Fetched on every full refresh via `fetchHealthDataSourceOptions`. | Cache results in `UserDefaults` and refetch only on permission change / source-picker open. |

---

## 5. Where to use incremental updates instead of full reloads

### 5.1 HealthKit anchor-based deltas

Add per-`HealthMetricKind` anchors (`HKQueryAnchor`) persisted alongside the dashboard snapshot. Use `HKAnchoredObjectQuery` to fetch only samples added since the last anchor. Today every "trend" fetch reads a multi-week window each refresh.

Affected fetch methods inside `HealthKitWorkoutStore`:

- `fetchHealthSummary(calendar:)`
- `fetchHealthTrends(calendar:)`
- `fetchActivityRingHistory(calendar:)` (rings need their own anchor, one per ring metric)
- `fetchWorkouts(month:year:calendar:)` — switch to anchor + month-windowed predicate so the second resume of the same day fetches near-zero samples.

### 5.2 Scoped resume refresh

Replace the current `syncWhenAppBecomesActive → requestAuthorizationAndRefresh` chain with a `resumeRefresh(staleness:)` that, for each metric:

1. Computes `staleness = now - lastSuccessfulRefreshDate(forKind:)`.
2. Skips kinds where `staleness < ttl(forKind)`.
3. Runs anchored queries for the remaining kinds in parallel.

This converts the 60-s blanket gate into per-metric TTLs.

### 5.3 Incremental workout merge

`refresh(monthKeys:)` currently overwrites `monthSnapshots[key]` with `WorkoutMonthSnapshot.make(workouts: newWorkouts)`. Switch to "diff against existing" using HealthKit's `UUID`: insert added, update changed, delete deleted-uuids. This:

- Keeps stable identity for SwiftUI list animations (today the entire list rebuilds on refresh).
- Avoids regenerating workout-type summaries when no rows changed.

### 5.4 Parallelize the 3-month workout fetch

In `refresh(monthKeys:)` (`:745-756`) replace the serial `for` with `withTaskGroup`. Already returning typed results, so the change is a few lines.

### 5.5 Per-metric trend refresh on demand

`refreshHealthMetric(_:date:)` already supports this. Surface it: when the user opens a metric detail view we should refresh **that** metric (not the whole dashboard). Today opening a detail view does no refresh — the user only gets new data after a full pull or app resume.

---

## 6. Startup loading — making the app open faster

Current chain at cold launch:

```
App init
  ↳ HealthKitWorkoutStore.init (sync disk read + Recovery recompute on main actor)
First frame composes from cached values
  ↳ .task fires: syncWhenAppBecomesActive
       ↳ requestAuthorizationAndRefresh
            ↳ requestAuthorization (UI prompt on first launch)
            ↳ refreshRecentMonths (3 serial workout fetches + 3 concurrent dashboard fetches + source options)
            ↳ updateHealthDashboardSnapshot (disk write + recovery recompute)
            ↳ updateCurrentMonthSnapshot (disk write + WidgetCenter.reloadAllTimelines)
```

Proposed cold-launch chain:

```
App init
  ↳ HealthKitWorkoutStore.init (sync disk read only)
First frame composes from cached values            ◀── unchanged for the user
  ↳ Defer Recovery recompute to .task with low priority
  ↳ .task fires shortly after first frame:
       ↳ resumeRefresh(staleness:)  (only stale kinds, anchored)
            ↳ async let workouts (parallel across months)
            ↳ async let dashboard kinds (per-metric anchored queries)
            ↳ diff-and-write snapshot only if changed
            ↳ widget reload only if current-month snapshot bytes changed
```

Specific changes:

1. **Move Recovery recalculation out of `init`** (`HealthKitWorkoutStore.swift:104-127`). Store the cached value as-is; recompute inside `.task` after first paint.
2. **Lower `.task` priority and add a small launch-debounce.** `Task(priority: .utility) { try? await Task.sleep(...); await store.resumeRefresh() }` lets the first frame paint before we touch HealthKit.
3. **Use the cached snapshot as a "seed".** Most UI in `BodyHomeView` already binds to `@Published` properties seeded from cache, so this works today — we just need to stop *immediately* overwriting them with placeholders during a refresh. Audit any `@Published` set to `.empty` inside the refresh path.
4. **Don't request authorization on every launch.** `requestAuthorization()` runs even after auth has been granted; gate it behind "we have not seen a successful refresh ever".
5. **Skip the full refresh entirely if all cached values are fresh.** Anchor age check before scheduling any query.

Target: first frame painted from cache in <100 ms after launch on cold start; HealthKit work fully off the first-frame path.

---

## 7. How pull-to-refresh should behave after optimization

Pull-to-refresh remains the explicit "force refresh" gesture, but its scope should match the visible content. After optimization:

| View | Pull-to-refresh action |
| --- | --- |
| `BodyHomeView` (Summary) | Refresh **only the metrics that are visible / pinned to the home order**. Parallel anchored fetch. Skip Activity Ring history pagination (rings detail has its own refresh). Always update widget snapshot if current month workouts changed. |
| `BodyHomeView` metric detail | Keep current behaviour: `refreshHealthMetric(model.kind)`. |
| `BodyWorkoutsView` | Keep `refreshWorkoutMonth(selectedMonth, selectedYear)`. Add: if the selected month is the current month, *also* refresh the Recovery / activity-ring summary on the calendar header (currently silently stale). |
| `BodyActivityRingsDetailView` | Add a `.refreshable` that refreshes the **visible** rings months (currently no pull-to-refresh here at all). |

Pull-to-refresh should **never** be slower than the current 0.6 s floor, but the work it kicks off should be visibly scoped. The 0.6 s `awaitRefreshCompletion` floor stays — it only governs the spinner.

---

## 8. Risks, edge cases, and what could go wrong

1. **Stale Recovery after permission flip.** If a user enables a new permission (e.g. HRV) we must still do a full metric refresh for that kind, ignoring TTLs. `updateHealthPermission` already triggers a refresh — preserve that path.
2. **Anchor drift / missed samples.** If `HKQueryAnchor` is corrupted or HealthKit returns a stale anchor we could miss samples until the user pulls to refresh. Mitigation: fall back to a full window query if anchor decode fails; ship a "Reset HealthKit anchors" entry under the existing Clear Cache flow.
3. **Background delivery and widget refresh interaction.** If we add `enableBackgroundDelivery`, the OS may wake the app extension while the foreground app is also refreshing. The store is `@MainActor`; any extension-side write would need a separate path that only writes `WorkoutSnapshotStore` (not the full dashboard).
4. **Diff‑merging workouts by `UUID`.** HealthKit allows late-arriving samples (e.g. an Apple Watch syncing a workout 2 days later). The merge must accept inserts into prior months, not just the current month. The current full-month refresh accidentally handles this; the optimized path must too.
5. **Widget showing stale data over a month rollover.** The widget reads `WorkoutSnapshotStore` which is only the **current** month. On the morning of the first day of a new month, before the user opens the app, the widget will show an empty calendar. The current code has this same issue — it's worth fixing as part of this work by snapshotting *both* the current and prior month (see §5).
6. **Recovery recompute timing.** Deferring the `recalculatingRecovery` from `init` to a post-launch task means there is a sub-100 ms window where the on-screen Recovery score is the value persisted from the last session. If yesterday's score is shown for a fraction of a second before today's appears, that may flicker. Mitigation: store the *recovery anchor date* alongside the cache and only show the cached value if its anchor date is today.
7. **`isRefreshing` busy-wait** (Issues.md N10). If we move to anchored / parallel queries we should also replace the polling loop in `awaitRefreshCompletion` and `loadMonthIfNeeded` (`:492-494, 500-502, 513-515`) with a proper async signal. Without that, a hung HealthKit query holds every pull-to-refresh and month-load indefinitely.
8. **Permission selection persistence.** `applyPermissionSelectionToCachedData` (`:793-811`) currently saves the filtered snapshot to disk. After optimization we still need this on permission change — make sure the new save-only-if-changed gate doesn't skip permission-driven writes.
9. **Test coverage.** `BodyTests/HealthKitWorkoutStoreTests` already round-trips the dashboard cache. Add anchor-based round-trip tests and a TTL-bypass test before shipping.

---

## 9. Step-by-step implementation plan

Each step is independently shippable, gated by tests, and ordered to keep the user-visible behaviour stable.

### Step 1 — Instrument current behaviour (no behaviour change)
- Add lightweight `os.Logger` signposts around `refreshRecentMonths`, `fetchWorkouts`, `fetchHealthSummary`, `fetchHealthTrends`, `fetchActivityRingHistory`, `updateCurrentMonthSnapshot`, and `WidgetCenter.shared.reloadAllTimelines()` call sites.
- Verify: launch the app, background, foreground, and confirm in Console which calls fire and how long they take.
- Success criterion: we have a baseline for "cold launch first frame" and "warm resume to UI updated" durations.

### Step 2 — Defer the post-launch refresh until after first frame
- In `BodyApp.swift:26-28`, wrap the `.task` body with a short low-priority detached scheduling so the first frame paints from cache before HealthKit is touched.
- Move `recalculatingRecovery(...)` out of `HealthKitWorkoutStore.init` (`:104-127`) into a `prepareCachedData()` method that is called from a `.task` after init.
- Tests: add a unit test asserting `HealthKitWorkoutStore.init` does not call `recalculatingRecovery`.
- Verify: cold launch first-frame time visibly drops; UI shows last-session values then transitions to current.

### Step 3 — Cache `fetchHealthDataSourceOptions` results
- Persist `healthDataSourceOptionsByKind` between launches (UserDefaults JSON).
- Invalidate on permission change and on opening the source picker sheet.
- Verify: profile a warm resume — confirm source-options query no longer fires.

### Step 4 — Short-circuit `HealthDashboardSnapshotStore.save` when unchanged
- In `updateHealthDashboardSnapshot` (`:758-787`), compare the about-to-save snapshot with the loaded-or-`.empty` previous one (encode once, compare bytes). Skip the write if identical.
- Same idea for `WorkoutSnapshotStore.save` in `updateCurrentMonthSnapshot` (`:834-843`) — and **gate** `WidgetCenter.shared.reloadAllTimelines()` on that change.
- Tests: a no-op refresh should leave file mtime unchanged and not call `WidgetCenter.reloadAllTimelines()`.

### Step 5 — Parallelize the 3-month workout fetch
- In `refresh(monthKeys:)` (`:745-756`) replace the serial `for` with `withTaskGroup` (or three `async let`s for the typical case of 3 keys).
- Watch for HealthKit throttling — wrap each fetch in `Task.yield()` boundaries if needed.
- Verify: cold-launch refresh of the 3 recent months is now bounded by the slowest single month, not the sum.

### Step 6 — Per-kind staleness gate (TTLs) for resume refresh
- Persist `lastSuccessfulRefreshDate` *per `HealthMetricKind`*, not globally.
- Implement `resumeRefresh()` that, for each kind, decides whether to refetch based on a TTL table (e.g. workouts 5 min, recovery 5 min, sleep 30 min, body mass 24 h, activity ring history 5 min).
- Replace the call from `syncWhenAppBecomesActive` (`:438-449`).
- Keep the 60 s global `lastAppEntrySyncDate` as a hard floor below all TTLs.
- Tests: a resume 7 min after launch with TTL(workouts)=5 min and TTL(body mass)=24 h should refetch workouts only.

### Step 7 — `HKAnchoredObjectQuery` for workouts and quantity types
- Add `HKQueryAnchor` persistence keyed by `HKObjectType`.
- Replace `HKSampleQuery` calls inside `fetchWorkouts`, `fetchHealthSummary` aggregators, and `fetchHealthTrends` with anchored versions that fetch deltas.
- Fall back to a windowed `HKSampleQuery` on anchor decode failure.
- Tests: a refresh after a no-op resume should report zero new samples per anchor.

### Step 8 — Incremental workout merge by UUID
- Replace `monthSnapshots[key] = WorkoutMonthSnapshot.make(workouts: fetched)` with a merge that respects existing `UUID`s.
- Handle deletions reported by the anchored query (`deletedObjects`).
- Verify: SwiftUI list animations stay stable across pull-to-refresh; new workouts slide in instead of reloading the entire list.

### Step 9 — `HKObserverQuery` + background delivery (optional, behind feature flag)
- Register an observer on `HKWorkoutType.workoutType()` (and the highest-signal quantity types: heart rate, HRV, sleep) with `enableBackgroundDelivery(.immediate)`.
- On observer fire, kick off a `resumeRefresh()` scoped to the type that fired.
- Test surface: must coexist with foreground refreshes (re-entrancy guard inside the store already prevents overlap; verify it doesn't deadlock with the new path).
- Gate behind a `@AppStorage("usesBackgroundDelivery")` toggle in Settings during rollout.

### Step 10 — Tighten pull-to-refresh scope
- Update `BodyHomeView.swift:271-277` to call `resumeRefresh(forKinds: visibleKinds)` instead of `requestAuthorizationAndRefresh()`.
- Add a `.refreshable` to `BodyActivityRingsDetailView` that refreshes visible rings months only.
- Confirm the 0.6 s spinner floor still applies.

### Step 11 — Snapshot prior month for the widget
- In `updateCurrentMonthSnapshot`, also save the prior month's snapshot to a second App Group file (`previousMonthWorkoutSnapshot.json`).
- Have the widget read both and prefer the current month, falling back to prior on month-rollover.

### Step 12 — Replace the `isRefreshing` busy-wait
- Introduce an `AsyncStream<Void>` (or `CheckedContinuation`) wake-up signal fired from `defer { isRefreshing = false }` paths.
- Replace the `while isRefreshing { sleep(100ms) }` loops in `awaitRefreshCompletion`, `loadMonthIfNeeded`, `loadPreviousActivityRingMonthIfNeeded`.
- Closes Issues.md N10's theoretical hang.

### Step 13 — Verification pass
- Run `BodyTests` (cache round-trip, recovery calc).
- Manual smoke test:
  - Cold launch → time to first frame.
  - Background 30 s → resume → no network spinner.
  - Background 10 min → resume → only Recovery + workouts refresh.
  - Pull-to-refresh on Summary → only visible cards refresh.
  - Toggle a permission → full refresh fires as before.
  - Clear Cache → cold-launch-equivalent state, both Summary and Workouts tabs repopulate.
  - Widget swap from current to prior month at month rollover.

### Step 14 — Documentation & telemetry
- Update `LessonsLearned.md` with the new refresh model.
- Add a brief note to `docs/TwoSource.md` if any of the source-picker caching changes affect dual-source behaviour.
- Consider an optional Settings → Diagnostics row that shows per-kind `lastSuccessfulRefreshDate` to help future debugging.

---

## 10. Out of scope for this plan

- ~~Switching off `@MainActor` for `HealthKitWorkoutStore`.~~ Done in step E2: the store stays `@MainActor` for SwiftUI binding, but all HK queries and fetch orchestrators now live on a separate `actor HealthKitFetchEngine`.
- Rewriting `BodyHomeView.swift` (8.2k LOC). The plan changes what the store exposes, not how the view consumes it.
- Adding a true server-side sync layer. Body is local-only by design; no cloud changes are proposed.
- Migrating snapshot storage to `SwiftData` / `CoreData`. JSON in App Group + Application Support is correct for this size; switching containers is independent work.

---

## 11. Implementation log

### Step 2 — Launch refresh priority (`BodyApp.swift`)
- `.task` and the scenePhase resume both run at `.utility` priority so UI work preempts them. First frame paints from cache before the launch refresh runs (SwiftUI's `.task` ordering already guaranteed this; the priority change keeps the post-paint work from blocking other UI updates).

### Step 3 — Cached source options (`HealthKitWorkoutStore.swift`)
- New `fetchedHealthDataSourcePermissionRawValue: String?` field.
- `fetchHealthDataSourceOptions` short-circuits when `permissionSelection.rawValue` matches the previous fetch's signature and `healthSourcesByKind` is non-empty.
- Invalidated by `clearLocalCache` (sets fields to `nil`/empty) and naturally by permission changes (different `rawValue`).
- Avoids ~14 `HKSourceQuery` round-trips on routine resumes; only refires on first launch and after permission edits.

### Step 4 — Save-if-changed + gated widget reloads
- `WorkoutSnapshotStore.save(_:)` and `HealthDashboardSnapshotStore.save(_:)` now encode once, compare against on-disk bytes, and return `@discardableResult Bool` indicating whether a write actually happened.
- `updateCurrentMonthSnapshot(date:calendar:)` gates `WidgetCenter.shared.reloadAllTimelines()` on the returned bool (current + prior month combined).
- Skipped writes for unchanged snapshots; widget no longer reloads on no-op refreshes.

### Step 5 — Parallel workout fetch
- `refresh(monthKeys:)` switched from `for key in monthKeys.sortedByDate` to `withThrowingTaskGroup`. The three recent-month fetches now run concurrently; total time bound by the slowest single month instead of the sum.

### Step 6 — Tiered resume TTL
- `syncWhenAppBecomesActive` now tiers:
  - `< 60 s` since `lastAppEntrySyncDate` → skip (unchanged).
  - `60 s – 5 min` since `lastSuccessfulRefreshDate` and workouts permission enabled → `refreshWorkoutMonth(currentMonth, currentYear)` only.
  - `≥ 5 min` (or never refreshed, or workouts disabled) → full `requestAuthorizationAndRefresh()`.
- Constants: `Self.shortResumeDebounceInterval = 60`, `Self.dashboardFreshnessInterval = 300`.

### Step 10 — Pull-to-refresh audit (no view changes)
- Home pull (full refresh) is the user's explicit "force refresh" gesture — kept full-scoped.
- Metric-detail pull (`refreshHealthMetric`) and Workouts pull (`refreshWorkoutMonth`) are already incremental.
- `requestAuthorization()` already short-circuits when status is `.unnecessary`.

### Step 11 — Prior-month widget snapshot
- `WorkoutSnapshotStore` gained `previousMonthSnapshotFileName`, `previousSnapshotFileURL`, `savePrevious(_:)`, `loadPrevious()`, `loadCurrentOrPreviousIfEmpty()`, and `deletePrevious()`.
- `updateCurrentMonthSnapshot` saves both current and (if present in `monthSnapshots`) prior month on each refresh; reloads widgets only when either file's bytes changed.
- `WorkoutCalendarWidget.loadEntry` now calls `WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty()` so on month-rollover (current month empty) the widget falls back to last month's calendar instead of an empty grid.
- `clearLocalCache` also calls `WorkoutSnapshotStore.deletePrevious()`.

### Step 12 — Continuation-based completion
- `HealthKitWorkoutStore` keeps `refreshCompletionContinuations: [CheckedContinuation<Void, Never>]`.
- Refresh `defer` blocks call `finishRefresh()` which sets `isRefreshing = false` *and* resumes every waiting continuation.
- `awaitNextRefreshCompletion()` replaces the four `while isRefreshing, !Task.isCancelled { try? await Task.sleep(nanoseconds: 100_000_000) }` busy-waits inside `awaitRefreshCompletion`, `loadMonthIfNeeded`, `loadPreviousActivityRingMonthIfNeeded`, and `updateSecondaryHealthDataSource`. Closes Issues.md N10's theoretical hang.

### Step A — Lazy intraday daySamples
- `fetchHealthTrends` no longer fetches `heartRateDaySamples`, `restingHeartRateDaySamples`, `heartRateVariabilityDaySamples`, `respiratoryRateDaySamples`, `oxygenSaturationDaySamples` (or their secondary-source variants). The largest source of HK IPC traffic on launch (`HKSampleQuery` with `HKObjectQueryNoLimit` over 365 days for high-frequency types) is gone from the dashboard path.
- `fetchHealthTrends` captures the existing `*DaySamples` fields from `healthTrends` at the top of the method and threads them through the new `HealthTrendSnapshot`. Lazy-loaded samples survive subsequent dashboard refreshes.
- New `HealthKitWorkoutStore.loadIntradayMetricSamplesIfNeeded(_ kind: HealthMetricKind)`: returns immediately for kinds without intraday data; awaits any in-flight refresh; fetches primary + secondary day samples in parallel for the requested kind; direct-merges into `healthTrends`. Does not persist (cheap to refetch next session).
- `BodyHealthMetricDetailView` has a new `.task { await workoutStore.loadIntradayMetricSamplesIfNeeded(model.kind) }` and reads `daySeries` / `secondaryDaySeries` via `liveDaySeries` / `liveSecondaryDaySeries` computed properties that prefer `workoutStore.healthTrends.daySeries(for: model.kind)` and fall back to `model.daySeries` for the first frame. The `@Published healthTrends` mutation re-renders the chart when the lazy load finishes.

### Step B — Tighten Training Load window
- New constant `Self.trainingLoadSummaryDayCount = 180`.
- `fetchTrainingLoadSummary` and `fetchTrainingLoadSeries` both fetch workouts over the trailing 180 days instead of the trend-range maximum (365). The EWMA chronic-load smoothing reaches ≥95 % influence at ~126 days, so 180 is past the stability threshold.
- Trade-off: Training Load's `recentYear` chart truncates to ~6 months of history; default Week/Month/6-Month ranges are unaffected. The EWMA already required ~126 days of pre-history to stabilise so the Year edge was partial even at 365 days.

### Step C — Tight cumulative-summary window
- `dailyCumulativeQuantitySummary` no longer routes through the year-long `fetchDailyCumulativeQuantitySeries` just to take `points.last`. It runs a 2-day `HKStatisticsCollectionQuery` with `.cumulativeSum`, daily buckets, anchored at `now - 1 day`, and returns the most recent non-nil bucket value. Preserves the "fall back to yesterday if today has no data yet" semantics. Affects steps, active energy, resting energy, exercise minutes, time in daylight.
- `dailyQuantitySummary` (wrist temperature, one query, low frequency) left as-is.

### Step D1 — HK-side aggregation for daily series and ranges
- `fetchDailyQuantitySeries` body replaced: `HKStatisticsCollectionQuery(quantityType:quantitySamplePredicate:options:anchorDate:intervalComponents:)` with `.discreteAverage` or `.mostRecent`, daily intervals. Enumerates `averageQuantity()` / `mostRecentQuantity()` per bucket.
- `fetchDailyQuantityRangeSeries` body replaced: same shape with combined `[.discreteMin, .discreteMax, .discreteAverage]`. Enumerates `minimumQuantity()` / `maximumQuantity()` / `averageQuantity()` per bucket.
- HK aggregates inside its daemon; the app now receives ≤365 lightweight statistics buckets instead of up to ~50k raw sample objects per metric.
- **Linearity caveat:** `valueTransform` now runs on the aggregate, not per-sample. Current transforms in use (identity, `normalizedPercentDisplayValue`) are linear so results match exactly. Comment in the new helpers documents this so a future non-linear transform doesn't silently break.
- `.latest` aggregation maps to HK's `.mostRecent` — equivalent to the previous "max by endDate" pick.
- `fetchSecondaryTrend` / `fetchSecondaryRangeTrend` call through the same helpers and pick up the speedup automatically.

### Step D2 — Combined avg+range single query
- New `fetchDailyQuantityAverageAndRangeSeries` returns `(HealthTrendSeries, HealthTrendRangeSeries)` from one `HKStatisticsCollectionQuery` with combined `[.discreteAverage, .discreteMin, .discreteMax]` options.
- `fetchHealthTrends` uses the paired fetch for HR, HRV, Respiratory Rate, SpO2 — eight separate queries (four daily-avg + four range) collapsed to four queries.
- `fetchHealthDashboardSnapshot(for: kind)` (per-kind detail refresh) uses the paired fetch in the `.heartRate`, `.heartRateVariability`, `.respiratoryRate`, `.oxygenSaturation` branches.

### Step E1 — Off-main recovery recompute and JSON saves
- Added `HealthDashboardSnapshot.filteredWithoutRecoveryRecompute(by:)`. `HealthKitWorkoutStore.init` now uses the non-recomputing variant so the cached `summary.recovery` value from disk is preserved through filtering instead of triggering the day-by-day `RecoveryScoreCalculator.dailySeries` loop before the first frame paints.
- `updateHealthDashboardSnapshot` is now `async`. The `.filtered(by:) .recalculatingRecovery(...)` chain runs inside `Task.detached(priority: .userInitiated)`; the result is awaited and then assigned to `@Published` state on the main actor. `HealthDashboardSnapshotStore.save(...)` and `saveSecondarySelectionSignature(...)` run inside `Task.detached(priority: .utility)` (fire-and-forget; in-memory state is published before the disk write completes).
- `updateCurrentMonthSnapshot` captures the snapshots and dispatches `WorkoutSnapshotStore.save` / `savePrevious` + `WidgetCenter.shared.reloadAllTimelines()` inside `Task.detached(.utility)`.
- `applyPermissionSelectionToCachedData` is now `async` with the same off-main filter+recompute + disk-save pattern; `updateHealthPermission` awaits it.
- Single-metric Recovery refresh in `fetchHealthDashboardSnapshot` wraps its `.recalculatingRecovery(...)` in `Task.detached(.userInitiated)`.
- Side effect: a brief few-ms window during refresh where in-memory state is updated but the disk JSON hasn't been written yet — recovers on the next refresh; no user-visible impact unless the app is force-quit mid-refresh.

### Step E2 — Extract `HealthKitFetchEngine` actor (off-main fetch orchestration)
- New `Body/Services/HealthKitFetchEngine.swift` (~2,550 lines). `actor HealthKitFetchEngine` owns `HKHealthStore`, `healthSourcesByKind`, `fetchedHealthDataSourcePermissionRawValue`, `healthTrendAnchorDate`, and mirrored copies of `permissionSelection` / `healthDataSourceSelection` / `secondaryHealthDataSourceSelection`. Engine exposes `setPermissionSelection`, `setHealthDataSourceSelection`, `setSecondaryHealthDataSourceSelection`, `setHealthTrendAnchorDate`, `clearSourceCache`.
- Moved into the engine: HK auth (`requestAuthorization`, `authorizationRequestStatus`), predicate helpers (`sourcePredicate`, `combinedPredicate`), permission/source mappers, `recentHealthTrendInterval` / `activityRingHistoryInterval`, `fetchIfPermitted` / `fetchSecondaryIfEnabled`, every leaf HK query (quantity helpers, series fetchers, workouts, sleep, activity rings, intraday, secondary trend/range/day samples, source list), and the dashboard fetch orchestrators (`fetchHealthSummary`, `fetchHealthTrends`, `fetchHealthDashboardSnapshot`, `fetchHealthDataSourceOptions`). The static helpers used inside fetches (`activityDateComponents`, `sleepSummary(from:date:)`, `summary(for:heartRateSamples:effortLevel:)`, `downsampleHeartRateSamples`, etc.) live on the engine.
- `HealthKitWorkoutStore` shrank from ~3,900 to ~1,450 lines. It keeps all `@Published` outputs, public refresh entry points (`requestAuthorizationAndRefresh`, `refreshHealthMetric`, `refreshWorkoutMonth`, `syncWhenAppBecomesActive`, `refreshCurrentMonth`, `loadIntradayMetricSamplesIfNeeded`, `loadRecentWorkoutMonthsIfNeeded`, `loadMonthIfNeeded`, `loadPreviousActivityRingMonthIfNeeded`, `clearLocalCache`), selection updaters (which now also `await engine.setX(...)`), snapshot publishing (`updateHealthDashboardSnapshot`, `updateCurrentMonthSnapshot`, `applyPermissionSelectionToCachedData`, `clearWorkoutSnapshots`, `updateHealthDataNotice`), refresh internals (`refresh(monthKeys:calendar:)`, `refreshRecentMonths`, `loadMonthKeysIfNeeded`), and the source comparison helpers. Test-accessed statics (`recentChartMonthCount`, `readObjectTypes`, `workoutType(for:)`, `mergedSleepDuration`, `sleepDuration`) stay on the store.
- API shape changes: `fetchHealthTrends` and `fetchHealthDashboardSnapshot` take `cachedTrends:` / `existing:` parameters so the engine can read previous trend state (preserving lazy-loaded intraday day samples, handling the single-metric Recovery early return) without touching the store's `@Published` directly. `fetchHealthDataSourceOptions` now *returns* the next `[HealthMetricKind: [BodyHealthDataSourceOption]]` (or `nil` for "no change because cache valid") and the store assigns it to its `@Published` property. `HealthKitWorkoutError` was hoisted to file-level visibility so the engine in a separate file can throw/match it.
- Tests: four string-grep assertions in `BodyTests/ProjectConfigurationTests.swift` (`testHealthKitFetchesApplySourcePreferencesToRequestedMetrics`, `testSourceSelectableDayChartsUsePrimarySecondaryComparisonLines`, `testHealthKitFetchesBarAndRangeSecondarySourceComparisons`, `testMetricDetailScreensPullToRefreshOnlyCurrentMetric`) were redirected from `HealthKitWorkoutStore.swift` to `HealthKitFetchEngine.swift`. Semantic assertions unchanged. `BUILD SUCCEEDED` + `TEST SUCCEEDED` on iPhone 17 simulator after the refactor.

### Not implemented (still open in §9)
- **Step 1** — `os.Logger` signposts for refresh phases. Cheap to add if future profiling is needed.
- **Step 7** — `HKAnchoredObjectQuery` with persisted `HKQueryAnchor` for true delta fetches. Would let resume refreshes pull only samples added since last refresh.
- **Step 8** — UUID-based incremental workout merge (depends on Step 7).
- **Step 9** — `HKObserverQuery` + `enableBackgroundDelivery` for push-based refresh of workouts / HR / HRV / sleep. Gated behind a feature flag per the original plan.
- **Step 14** — Settings → Diagnostics row showing per-kind `lastSuccessfulRefreshDate`.

### Verification
- `xcodebuild -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` passes after each step.
- Cold-launch refresh time observed by the user: ~15–20 s → ~10 s after A/B/C. D1/D2 target the remaining 50k-sample HR-trend queries; expected to bring the figure closer to the ~5 s ideal but not yet measured on-device.
