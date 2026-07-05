# Body — Full Project Code Review

**Reviewer:** Claude (Fable 5) · **Date:** 2026-07-04 · **Scope:** all 133 Swift files (~58k lines) across the iOS app, BodyMetricsKit, BodyShared, watch app, watch/widget extensions, plus entitlements and build settings.

**Method:** six parallel deep-read passes (HealthKit fetch engine; workout store & persistence; BodyMetricsKit domain logic; SwiftUI view layer; app entry / Body Pro / services; watch & widget targets), followed by cross-verification of every High-severity claim against the source. Every finding below cites the exact file and line and was confirmed by reading the code, not pattern-matching.

**Overall verdict:** This is a well-engineered codebase — meaningfully above typical indie-app standard. Persistence discipline (atomic writes, byte-compare save gating, tolerant decoders), continuation hygiene (no double-resume or leaked continuation found anywhere), memoization architecture in the views, and sleep-staleness double-guarding are all genuinely good. **No Critical (ship-blocking crash or guaranteed data-corruption) issue was found.** The real problems cluster in four places: silent data-loss edges in the incremental-fetch design, error handling that converts failures into "empty data", a handful of dead/incorrect UI paths, and a testability wall at the HealthKit/StoreKit/WCSession boundaries that leaves the app's data backbone entirely unverified by the (otherwise large) test suite.

---

## Architectural Concerns

These are systemic patterns behind many individual findings; fixing them pays off across the whole list.

**A1. Cross-file contracts live in comments, not types.**
The Basics trend cards say "Tapping pushes … via the stack's HealthMetricKind navigationDestination" (`BodyHealthMetricDetailView.swift:502`) — but no such destination exists anywhere (H4). The engine comment on `fetchIncrementalPrimaryDaySamples` claims secondary day samples "still refetch fully" — the store actually merges them incrementally (M6). When an invariant is only prose, the compiler can't catch drift, and both of these drifted.

**A2. No seams at the platform boundaries → the data backbone is untestable.**
`HealthKitFetchEngine` hard-wires `let healthStore = HKHealthStore()` (line 21), `BodyProStore` calls `Purchases.shared` at every site, `WatchConnectivityPublisher` hard-wires `WCSession.default`. Consequently: not one HealthKit predicate, statistics option, unit, or interval is asserted by any test; the purchase state machine and the watch queue/flush ordering are untested; and `ProjectConfigurationTests` compensates with source-string assertions that would pass against broken implementations. A thin protocol per boundary (execute/stop/save; customerInfo/purchase; activate/updateApplicationContext) plus recording fakes would unlock the ~40 query-composition sites and the trickiest state machines in the app.

**A3. Per-metric query recipes are duplicated across five orchestration sites.**
The (identifier, unit, aggregation, transform) tuple for each metric is restated in `fetchHealthSummary`, `fetchHealthTrends`, `fetchHealthDashboardSnapshot`, the `+Secondary` switches, and `+IntradaySamples` — the heart-rate unit expression alone appears ~12 times. One drifted copy produces quiet unit inconsistencies between dashboard and detail. A per-`HealthMetricKind` descriptor table would collapse hundreds of lines and make the switches exhaustive by construction.

**A4. Shared logic has divergent copies.**
The robust-baseline algorithm exists twice, currently identical (`ReadinessScoreCalculator.swift:213–250` vs `398–440`); iOS widget line charts bridge missing days while the watch sparkline breaks runs on them (L23); activity-ring summary parsing is copy-pasted three times (`+ActivityRings.swift:117/195/244`); `wristTemperatureBaselineDeviationDisplay` is a free function in a *view* file consumed by the widget snapshot builder. Each pair will desynchronize under maintenance.

**A5. Concurrency invariants are enforced ad hoc.**
`snapshotPersistQueue` exists specifically so "an earlier save can never land after a later one" — but workout-month saves bypass it via `Task.detached` (M4). The `isRefreshing` gate serializes refreshes — but the lazy intraday load writes `healthTrends` outside it (M5), and four settings paths silently drop their refetch because of it (M1). The invariants are right; enforcement is per-call-site convention.

**A6. God files.**
`HealthKitWorkoutStore.swift` (2,733), `HealthKitFetchEngine.swift` (2,575 + 10 extensions), `BodySettingsView.swift` (3,011), `BodyWorkoutsView.swift` (2,435), `BodyHealthMetricDetailView.swift` (2,344), `BodyHomeView.swift` (2,320). Well-commented and internally consistent, but every store publish invalidates giant view bodies, and the highest-value extractions are concrete: the 435-line `detailModel(for:)` factory out of BodyHomeView (it's where H4 hid); `BodyWorkoutDetailSheet` + the hand-drawn HR chart stack out of BodyWorkoutsView (where H5 lives, and `BodyWorkoutHeartRateChartMetrics` becomes unit-testable); sleep/basics sections out of BodyHealthMetricDetailView; the ~20 private sheet structs out of BodySettingsView.

**A7. Widget freshness relies on build-time sanitization plus a single timeline entry.**
Stale-sleep clearing is correct *when a timeline is built*, but every provider emits exactly one entry with `.after(~30 min)` — a request WidgetKit is free to defer, especially overnight. The architecture needs future-dated pre-sanitized entries (M14) rather than more sanitization call sites.

---

## Critical

**None found.** Specifically verified absent: `try!` / `as!` / `fatalError` / force-unwraps in production targets; double-resumed or leaked continuations (all `withCheckedContinuation` sites resume exactly once on every path); `@MainActor` violations on observable state (all `nonisolated` delegate callbacks hop correctly); unseeded `reduce`, `first!`/`last!`, unguarded indexing in the metrics kit and charts; health values or tokens in log output (all `Logger` calls emit error descriptions/paths only; `privacy: .public` applied only to error strings and the App Group id).

---

## High

### H1. Backfilled HealthKit samples are permanently dropped by the incremental day-sample merge — `Body/Services/HealthKitFetchEngine+IntradaySamples.swift:95`

**What:** Incremental refresh for intraday series (heart rate, resting HR, HRV, respiratory rate, SpO₂) uses a pure date cursor:

```swift
nonisolated static func incrementalFetchStart(after cached: HealthTrendSeries, windowStart: Date) -> Date {
    guard let lastDate = cached.points.last?.date else { return windowStart }
    let next = lastDate.addingTimeInterval(0.001)
    return max(next, windowStart)
}
```

Only samples newer than the newest cached point are ever fetched again (`mergeIntradaySamples` appends; consumed by `fetchIncrementalPrimaryDaySamples` at `HealthKitFetchEngine.swift:2145–2163` and `HealthKitWorkoutStore.loadIntradayMetricSamplesIfNeeded`).

**Why risky:** HealthKit arrival order is not time order. Apple Watch syncs in lagging batches and third-party sources backfill hours later. Once any sample with a newer `endDate` lands first (a chest-strap app writing "now" while the morning's Watch samples are still queued), everything timestamped before that cursor becomes permanently invisible — the per-metric refresh, `fetchHealthTrends` (which carries cached day samples forward, lines 1854–1866), and the persisted sidecar (`HealthDashboardSnapshotStore`) all preserve the hole across restarts. There is no reconciling path.

**Impact:** Intraday detail charts for 5 metrics; anyone with more than one writing source or laggy Watch sync. Silent, permanent gaps in health data.

**Fix:** Refetch a trailing overlap window (24–48 h) and de-duplicate on merge, or track an `HKQueryAnchor` per metric instead of a date cursor — anchors see late arrivals regardless of timestamp.

### H2. Disabling a health permission doesn't strip cached overnight vitals — readiness keeps scoring metrics the user turned off — `BodyMetricsKit/HealthTrend.swift:724–795`

**What:** `HealthTrendSnapshot.filtered(by:)` clears `sleepHistory` only when `.sleep` is disabled. Disabling `.heart`, `.bloodOxygen`, `.respiratory`, or `.wristTemperature` empties the whole-day trend series but leaves the per-night vitals inside `sleepHistory.days[].summary.vitals` intact. `ReadinessScoreCalculator` builds its *preferred* overnight HR/HRV series exactly from those vitals (`ReadinessScoreCalculator.swift:98–104, 151–176`), and SpO₂/respiratory/wrist-temp anomalies drive the vitals component the same way. So after the user turns Heart off, `filtered(by:).recalculatingReadiness(...)` (`HealthSummarySnapshot.swift:538–549`, called from `HealthKitWorkoutStore.swift:263, 2025`) still computes the autonomic core from cached overnight data.

**Why risky:** The intent is unambiguous — `HealthSummarySnapshot.filtered(by:)` *does* nil the same vitals for the current-day summary (`HealthSummarySnapshot.swift:387–415`), and the `recordedReadinessContext` machinery exists to invalidate scores when inputs change. This is a privacy/consent-semantics bug: a toggle that claims to stop using a metric doesn't.

**Impact:** Readiness scores and drivers for any user who disables a vitals permission while sleep history is cached.

**Fix:** In `HealthTrendSnapshot.filtered(by:)`, map `sleepHistory`/`sleepHistorySecondary` days and strip the corresponding `vitals` fields per disabled permission, mirroring `HealthSummarySnapshot.filtered`.

### H3. 6-month and year charts silently drop the newest partial bucket — today (and up to 5 recent days) vanishes — `BodyMetricsKit/HealthTrend.swift:1004–1019`

**What:**

```swift
if let finalRange = ranges.last,
   finalRange.count < aggregationDayCount,
   ranges.count > 1 {
    ranges.removeLast()
}
```

`calendarPoints` runs oldest→newest ending at today; buckets are built from index 0, so the trailing partial bucket holds the **most recent** days. 6 months: 183 days / 6-day buckets → the newest 3 days (including today) are removed. Year: 365/12 → newest 5 days removed. Source-comparison 6M/Y (aggregation 12/24) drops 3/5 days likewise.

**Why risky:** Every consumer of `chartCalendarPoints`/`chartSeries`/`lineChartCalendarPoints`/`sourceComparisonChartCalendarPoints` (MetricCharts, BasicsCharts, SourceComparisonCharts, HeartRateRangeChart, the home year sparkline) shows long-range charts whose newest point can lag today by days — while week/month ranges do include today, so the latest reading appears and disappears as the user switches ranges. Reads as data loss.

**Fix:** If a partial bucket must be dropped, anchor bucketing from the **newest** day backwards so the partial bucket is the oldest. Add a test asserting today's point appears in the year chart.

### H4. Inert NavigationLinks: no `navigationDestination(for: HealthMetricKind.self)` is registered anywhere — `Body/Views/Health/BodyHealthMetricDetailView.swift:515`

**What:** The Basics detail page wraps Weight and Body Fat trend cards in `NavigationLink(value: kind)` where `kind: HealthMetricKind`, with a comment asserting the stack registers a `HealthMetricKind` destination. Verified project-wide: the only registrations are `navigationDestination(for: HomeMetricRoute.self)` (`BodyHomeView.swift:441`) and `navigationDestination(item: $selectedWorkoutForDetails)` (`BodyWorkoutsView.swift:131`).

**Why risky:** Tapping either card does nothing (plus a runtime "no matching navigationDestination" warning). Two visibly tappable cards on a default summary page are dead. The readiness overlay's own `NavigationStack` (`BodyHomeView.swift:535`) registers no destinations either.

**Fix:** Register on the Home stack (and in the overlay stack if Basics becomes reachable there):

```swift
.navigationDestination(for: HealthMetricKind.self) { kind in
    BodyHealthMetricDetailView(model: detailModel(for: kind), initialTrendRange: defaultTrendRange)
}
```

Or, if the push was intentionally removed, delete the `NavigationLink` wrappers so the cards aren't tappable.

### H5. Workout detail sheet re-runs its entire body — comparisons, splits, HR-sample sort — on every scroll frame — `Body/Views/BodyWorkoutsView.swift:843`

**What:** `BodyWorkoutDetailSheet` stores the live scroll offset in plain `@State` (`onScrollGeometryChange` → `scrollOffset = offset`), invalidating the whole sheet per frame. Each body pass then evaluates the computed `presentation` (lines 1346–1355, calling `workoutStore.comparisonContext(for:)` and building a full `WorkoutDetailPresentation`) **four times** (topEntryPanel, workoutDetailsCard, heartRateSection, sourceFooter), plus `splitsPresentation` (1376–1392, re-running `WorkoutSplitCalculator.splits` over all distance samples), plus `BodyWorkoutHeartRateChartMetrics(samples:)` (1827–1829) which **sorts every heart-rate sample** (line 2175) per evaluation.

**Why risky:** For a long workout (thousands of HR samples), that's a sort + comparison scan + splits calculation at up to 120 Hz while scrolling — dropped frames on the most content-heavy page in the app. The codebase already knows this hazard: the `prediction` property is cached for exactly this reason (comment at 781–783), and BodyHomeView isolates its scroll offset in an `@Observable` (`BodyHomeScrollState`, 299–302) so per-frame writes don't re-render the dashboard.

**Fix:** Mirror `BodyHomeScrollState`: move `scrollOffset` into a small `@Observable` read only by the map-dim overlay; compute `presentation`, `splitsPresentation`, and the chart metrics once into `@State` keyed by `(workout.id, splitData, unit prefs)` via `.task(id:)`.

### H6. RevenueCat public API key cannot be verified as the real dashboard key; a wrong key fails silently — `Body/Services/RevenueCatConfiguration.swift:15`

**What:** `static let publicAPIKey = "appl_PoWnLIjBBShPqMturjPyogVqdEH"`. The migration is documented as mid-flight (real `appl_` key pending). The guard test (`ProjectConfigurationTests.swift:1979–1982`) only asserts the `appl_` prefix and that it isn't the old test key — a plausible placeholder passes.

**Why risky:** With a wrong key, `Purchases.configure` still succeeds; every `customerInfo`/`products`/`purchase` call then fails at runtime, and `refreshEntitlement()`'s catch block silently keeps the cached value (`BodyProStore.swift:138–140`). Failure mode: Pro silently never unlocks; purchases show a generic error. Production-only, invisible to unit tests.

**Fix:** Before shipping, verify the string against RevenueCat dashboard ▸ API keys; during bring-up set `Purchases.logLevel = .debug` and confirm one successful `CustomerInfo` fetch on device. Log loudly (once) on `ErrorCode.invalidCredentialsError` so a bad key can't be quiet.

---

## Medium

### M1. Primary source/permission changes silently drop their refetch when a refresh is in flight — `Body/Services/HealthKitWorkoutStore.swift:906, 944, 894, 810`

`updateDefaultHealthDataSource`, `updateHealthDataSource(for:)`, `updateCombinesHealthDataSourcesByName`, and the enable branch of `updateHealthPermission` all end with `await requestAuthorizationAndRefresh()`, whose first line is `guard !isRefreshing else { return }` (line 405). The *secondary*-source variants handle this correctly — they `await awaitNextRefreshCompletion()` first (lines 935, 966). If a resume-triggered or pull-to-refresh is in flight when the user changes the default source (a multi-second window), the published selection updates but no refetch runs: the dashboard shows old-source data labeled with the new source's name until the next refresh. **Fix:** mirror the secondary variants — `await awaitNextRefreshCompletion(); guard !Task.isCancelled else { return }; await requestAuthorizationAndRefresh()`.

### M2. Lazy month/ring loads bump `lastSuccessfulRefreshDate`, defeating the dashboard-freshness TTL — `Body/Services/HealthKitWorkoutStore.swift:1858, 1452`

`loadMonthKeysIfNeeded` and `loadPreviousActivityRingMonthIfNeeded` call `markRefreshSucceeded(date: Date(), refreshedVitals: false)`, which unconditionally sets and persists `lastSuccessfulRefreshDate` (lines 2172–2173). `syncWhenAppBecomesActive` (line 1155) and the cold-start tiered TTL treat that timestamp < 5 min as "dashboard fresh" and skip the vitals refresh. A user paging workout months or ring history keeps re-arming it — subsequent resumes (and relaunches, since it's persisted) skip vitals refresh even though trends haven't been refetched. `lastVitalsRefreshDate` protects the watch from exactly this conflation; the app's own TTL still conflates. **Fix:** gate the persisted timestamp update on `refreshedVitals == true` (or track a separate workout-refresh date).

### M3. Disabling the Workouts permission leaves full workout JSON at rest in the App Group; the widget keeps showing it — `Body/Services/HealthKitWorkoutStore.swift:2331, 2351–2371`

The workouts-off branch calls `clearWorkoutSnapshots()` (in-memory only) and requests a widget reload — which makes the widget re-read the **untouched** `currentMonthWorkoutSnapshot.json`/`previousMonthWorkoutSnapshot.json` via `WorkoutSnapshotStore.loadCurrentOrPreviousIfEmpty()` (`WorkoutSnapshotStore.swift:189`) and re-render the same workouts. The `.workoutMetrics` opt-out right below explicitly rewrites both files "so this clears the data at rest on opt-out" (comment at 2383–2387); the coarser workouts opt-out doesn't. Wrong at-rest behavior for a privacy toggle, inconsistent with the store's own precedent. **Fix:** in the workouts-off branch, persist an empty month snapshot (or delete both files) through `snapshotPersistQueue`, then request the reload.

### M4. Workout snapshot saves use unordered `Task.detached`, violating the store's own write-ordering invariant — `Body/Services/HealthKitWorkoutStore.swift:2414–2424`

`updateCurrentMonthSnapshot` persists via fire-and-forget `Task.detached(priority: .utility)`, bypassing `snapshotPersistQueue`, whose doc comment (2265–2267) states the invariant: an earlier save must never land after a later one. Two successive refreshes spawn two unordered detached saves; save #1 landing after save #2 overwrites newer workout data with older (byte-compare saving doesn't help — the bytes differ) and triggers a widget reload showing the stale month. `sanitizeWorkoutMetricsSnapshots`'s load-modify-write (2388) can likewise interleave with a concurrent refresh save and resurrect stripped metrics on disk. **Fix:** route these saves through `Self.snapshotPersistQueue.async { ... }` like every other persist path.

### M5. Lazy intraday load races an overlapping refresh; freshly fetched series get clobbered and persisted stale — `Body/Services/HealthKitWorkoutStore.swift:637–753`

`loadIntradayMetricSamplesIfNeeded` awaits `awaitNextRefreshCompletion()` once at entry (649) but never sets `isRefreshing` nor re-checks after its engine fetches (691–707). A refresh starting during those suspension points captures `cachedTrendsAtStart = healthTrends` (1746); after the intraday load writes `healthTrends = trends` (753), the refresh overwrites it wholesale from the stale capture (1796, 2046) and persists that — including the day-sample sidecar rebuilt from `snapshot.trends` (`HealthDashboardSnapshotStore.swift:137`). The user's just-loaded hourly chart disappears and the sidecar regresses (self-heals on next detail open). **Fix:** re-check `isRefreshing` after the fetches and merge (the `mergingMissingDaySamples`-style merge exists) instead of overwriting, or funnel the write through the refresh gate.

### M6. Changing a data source contaminates cached day samples; the engine comment contradicts store behavior — `Body/Services/HealthKitFetchEngine.swift:2142`

The doc comment on `fetchIncrementalPrimaryDaySamples` claims secondary day samples refetch fully because "an incremental merge would extend the old source's samples instead of replacing them." Verified: (1) the same hazard is unhandled for the **primary** source — `updateHealthDataSource(for:)` (`HealthKitWorkoutStore.swift:945–955`) only updates the selection; nothing clears cached `*DaySamples`, and `fetchHealthTrends` preserves them (1854–1866, 2120–2132), so the next detail load merges new-source samples onto old-source history and presents the mix as one source; (2) the store *does* incrementally merge secondary day samples despite the comment (`HealthKitWorkoutStore.swift:683, 716–726`), so the exact failure the comment guards against exists there too. **Fix:** key cached series by resolved source-option ID and treat a mismatch as an empty cache (full refetch).

### M7. Every HealthKit query error is silently mapped to empty data, which then overwrites good cached trends — `Body/Services/HealthKitFetchEngine.swift:566` (pattern)

The error parameter is discarded in essentially every callback in the main file and the Sleep/SourceOptions/ActivityRings/TrainingLoad extensions (verified instances: 566, 639, 710, 773, 850, 911, 974, 1025, 1074, 1317, 1527; `+Sleep.swift:36, 101, 280`; `+SourceOptions.swift:218`; `+ActivityRings.swift:39–41, 149–151, 210–212`; `+TrainingLoad.swift:62–64, 79–81`). Only the workout-list fetch propagates errors. `errorDatabaseInaccessible` (device locked — exactly when background refresh fires), `errorHealthDataUnavailable`, and transient XPC failures all become `.empty`, indistinguishable from "no data"; `fetchHealthTrends` builds a full replacement snapshot from those results and the store persists it, blanking previously good series until the next successful refresh. **Fix:** distinguish failure from empty for series that replace cached state (return `nil`/`Result` and keep the cached series on failure) — `ActivityRingOlderHistoryProbe.failed` already models this for the ring probe.

### M8. Continuation-wrapped queries ignore Task cancellation; year-scale fetches survive view dismissal — `Body/Services/HealthKitFetchEngine.swift:1045–1089`

No `withCheckedContinuation` wrapper installs a cancellation handler or calls `healthStore.stop(query)`. The Route and Splits extensions deliberately use the async descriptor APIs *because* they honor cancellation (their headers say so) — but the biggest fetch (`fetchQuantitySampleSeries`, default window 365 days, `HKObjectQueryNoLimit`) does not. Pop into an HR detail and immediately leave: the `.task` cancels, but the query, full-array materialization, and `compactMap` run to completion, and the awaiting task can't finish until then. **Fix:** wrap in `withTaskCancellationHandler` calling `healthStore.stop(query)` (single-resume guarded), or migrate large sample fetches to `HKSampleQueryDescriptor` as `+Route`/`+Splits` already do.

### M9. Unbounded 365-day raw-sample fetch for intraday series — `Body/Services/HealthKitFetchEngine.swift:1059`

Same site, distinct problem: a first-ever detail load (`fetchIncrementalPrimaryDaySamples` with empty cache, 2151) fetches the full year window of raw samples in one shot. The file's own estimate (line 1852) is "~50k HR samples"; a 24/7 Watch wearer is realistically 100k–500k `HKQuantitySample` objects materialized plus a same-size mapped array — doubled with a secondary comparison source. **Fix:** fetch per-range chunks lazily (the chart shows one range at a time), or derive year-scale intraday views from a statistics-collection downsample (e.g. 15-minute buckets).

### M10. Engine owns its `HKHealthStore` — every query path is untestable — `Body/Services/HealthKitFetchEngine.swift:21`

`let healthStore = HKHealthStore()` is hard-wired; no protocol seam, no injected store. The tests cover only the `nonisolated static` pure helpers: not one predicate, statistics option, unit, or interval passed to HealthKit is asserted anywhere. This is the app's data backbone. **Fix:** a thin `HealthStoreProtocol` (execute/stop/save/relate + authorization) with a recording fake; see A2.

### M11. WCSession activation-complete handler ignores `error`, enabling an unbounded re-activate loop — `Body/Services/WatchConnectivityPublisher.swift:88–99`

`session(_:activationDidCompleteWith:error:)` checks neither `error` nor `activationState` before flushing `pending` into `send()`. If activation completed with an error (state stays `.notActivated`), `send()`'s guard re-stashes `pending` and calls `session.activate()` again (58–59) — which delivers another failed callback, repeating indefinitely with no backoff whenever activation persistently fails. **Fix:** `guard error == nil, activationState == .activated else { return }`.

### M12. Snapshot stashed after a failed `updateApplicationContext` is never retried — `Body/Services/WatchConnectivityPublisher.swift:80–83`

The catch block sets `pending = (snapshot, permissionRawValue)`, but `pending` is only ever flushed from `activationDidCompleteWith` — which never fires again for an already-activated session (the only case in which this catch runs). The stash is dead code that reads like a retry: a transient WC error on the session's last refresh means the watch keeps stale metrics until some newer snapshot happens to be sent. **Fix:** delete the stash (accept best-effort) or flush `pending` from `sessionReachabilityDidChange` / the next `send()`.

### M13. Widgets can show a stale Pro entitlement until the app is next foregrounded — `BodyShared/Services/BodyProEntitlement.swift:28–29` + `Body/BodyApp.swift:43–48`

Widgets gate on the App Group flag, which is only rewritten when `BodyProStore` runs (launch/foreground). After a refund/revocation, widgets render Pro content indefinitely if the app stays closed; a purchase on another device doesn't unlock widgets until this phone foregrounds the app. Inherent to the no-server design — but currently undocumented. **Fix:** accept and document the staleness bound in TestPlan, or add a `BGAppRefreshTask` that calls `refreshEntitlement()` periodically.

### M14. Single-entry widget timelines let yesterday's sleep (and "today" highlights) survive past midnight — `BodyWidgetExtension/SleepStagesWidget.swift:35–43`, `HealthMetricWidget.swift:52–59`, `WorkoutCalendarWidget.swift:62–68`, `BodyWatchWidgetExtension/WatchComplicationsProvider.swift:32–37`

Every provider emits exactly one entry dated `Date()` with `.after(~30 min)`, and stale-sleep sanitization runs only at entry-build time. `.after` is a request, not a guarantee — WidgetKit/complication budgets routinely defer reloads well past the requested date, especially overnight with no phone-side nudges. A timeline built at 23:40 keeps rendering last night's sleep score after midnight until the system deigns to reload; the workout calendar's today-highlight (`referenceDate: entry.date`) goes stale the same way. This partially defeats the recent "prevent stale sleep carryover" fix. **Fix:** add a second, pre-sanitized entry dated at the next local midnight in the same timeline so the blank-out is exact and budget-independent:

```swift
let now = Date()
let midnight = calendar.startOfDay(for: now).addingTimeInterval(86_400)
let entries = [
    Entry(date: now, snapshot: snapshot.sanitized(asOf: now)),
    Entry(date: midnight, snapshot: snapshot.sanitized(asOf: midnight))
]
```

### M15. Watch merge wipes a same-day, valid sleep value on any blank push — the sleep arm of the don't-downgrade rule is effectively dead — `BodyWatch/WatchMetricsModel.swift:63–70, 123–127` + `BodyWatchShared/Models/WatchMetricsSnapshot.swift:256–263`

`applyReceivedContext` does `apply(merging(received).sanitized())`. The merge preserves the local sleep *metric* when the incoming one is blank, but `merging` starts from `var merged = received`, so `merged.sleepNight` is always the received snapshot's — and a blank incoming sleep metric implies `sleepNight == nil` (`WatchMetricsSnapshotBuilder.swift:44–45`). `sanitized()` treats nil `sleepNight` as not-today and clears the metric the merge just preserved — even when the local night was today and valid (e.g. a transient phone-side sleep fetch failure). The readiness carve-out was written specifically to prevent this class of wipe; for sleep it can never survive `sanitized()`. **Fix:** when the merge keeps the local sleep metric, carry the local `sleepNight` too (then `sanitized()` still clears genuinely stale nights).

### M16. Workout widgets show fabricated placeholder workouts as real data — `BodyWidgetExtension/WorkoutCalendarWidget.swift:71–78` + `BodyShared/Services/WorkoutSnapshotStore.swift:171–178, 189–198`

`WorkoutCalendarProvider.loadEntry` uses `loadCurrentOrPreviousIfEmpty()` for both previews and **live** timelines; with no snapshot it returns `.placeholder` — 9 fake workouts pinned to days 1–9 of the month (`WorkoutMonthSnapshot.swift:194–217`) — and the app even seeds this placeholder to disk at launch (`loadOrSeedPlaceholder`). No "sample" affordance exists in the widget views. A user adding the calendar/type widget on a fresh install sees invented workout history presented as their own — a data-honesty problem in a health app, and inconsistent with every other provider (which reserve `.placeholder` for `context.isPreview`). **Fix:** route live timelines to an empty month snapshot (`WorkoutCalendarView` already renders an all-numbers grid; `WorkoutTypeBreakdownView` has an empty state) and keep the placeholder for previews only.

### M17. Workout-type percentages are computed over the truncated widget subset — widget and app disagree — `BodyShared/Components/WorkoutTypeBreakdownView.swift:39–49, 159–164`

`distributionTotal` sums only `displayedBreakdown` (prefix 2 for medium, 5 for large), so a 50/30/20% split renders as 62/38% in the medium widget while the in-app view (unlimited) shows 50/30% from the same snapshot through the same view. **Fix:** `snapshot.workoutTypeBreakdown.reduce(0) { $0 + $1.duration }`.

### M18. Route-map snapshot composited on the main thread, one stroke per GPS segment — `Body/Views/Health/BodyWorkoutRouteMapHero.swift:80–188`

`renderSnapshot` is `@MainActor`; after the snapshotter returns, `Self.draw` maps every coordinate through `snapshot.point(for:)` and, in the pace-colored branch, issues move/addLine/strokePath per segment inside a `UIGraphicsImageRenderer` pass — thousands of fixes for a multi-hour outdoor workout, executed on the main actor exactly while the detail sheet animates in, and re-run on size/appearance changes via `.task(id:)`. **Fix:** the draw step is pure CPU on `Sendable` inputs — run it off-main and assign the image on the main actor; optionally downsample points before stroking.

### M19. `workouts(on:)` rebuilds a dictionary of every workout in every loaded month, twice per render — `Body/Views/Health/BodyHealthMetricDetailView.swift:1553–1559`

Called from `selectedMetricActivityAverages` (621) and `selectedMetricDayContextIntervals` (1534), both evaluated per body pass of the HR/HRV/energy/steps detail — a view that re-renders on every progressive-refresh publish and day-tile tap. With months of history in `monthSnapshots`, that's an O(total workouts) scan + `flatMap` allocation ×2 per render, on a view that otherwise memoizes aggressively (`BodyMetricDaySeriesCache`, `BodySleepConsistencyChartCache`) for exactly this reason. **Fix:** memoize per `(selectedMetricDay, monthSnapshots identity)` alongside the existing caches, or add a store-level day-indexed lookup.

### M20. Detail charts recompute full series bucketing in `init` on every parent body evaluation — `Body/Views/Health/Charts/MetricCharts.swift:68–95` (also `SourceComparisonCharts.swift:112–145`, `HeartRateRangeChart.swift:57–85`, `BasicsCharts.swift:51–66`)

`BodyHealthMetricTrendChart.init` runs `lineChartCalendarPoints(to:)`/`chartCalendarPoints(to:)` **and** a second full `calendarPoints(to:)` pass just for the X domain; the same double-pass pattern repeats in the three sibling charts. These inits run on every body evaluation of the 2,344-line detail view — each store publish, sheet toggle, or date-picker change — not just when range/data changed. On `.recentYear` with dense HR series this is several full-series passes per event. **Fix:** derive the domain dates from the already-bucketed points (the second pass duplicates work), and/or memoize chart inputs keyed on `(kind, range, series fingerprint)` like `BodyHomeTrendComputationCache`.

### M21. Workout detail has no visible Back/Close control — dismissal is gesture-only — `Body/Views/BodyWorkoutsView.swift:849` + `Body/Views/BodyWorkoutListSheet.swift:130–134`

`BodyWorkoutDetailSheet` hides the navigation bar entirely and is presented both pushed and as a `fullScreenCover`. Full-screen covers have no system swipe-down by default; the zoom transition's drag is undiscoverable, and Switch Control/AssistiveTouch users may be unable to leave the screen. The route full-screen view already solves this with an xmark button — mirror it here when the nav bar is hidden.

### M22. Training component score is non-monotonic at ACWR 1.30 — worse load displays a better score — `BodyMetricsKit/ReadinessScoreCalculator.swift:781–799, 900–914`

`scoreFromSustainableTrainingLoad(1.30)` returns 62, but any value just above 1.30 switches to the penalty curve, which starts at `base: 70` — so a ratio of 1.29 shows ~63 while 1.31 shows ~70 (with an "elevated load" driver). The overall score is unaffected (`strainFactor` is continuous), but the displayed Training component jumps *up* ~8 points exactly as load crosses into risky territory. **Fix:** start the penalty curve at `base: 62` (or end the sustainable curve at 70).

### M23. Unknown `BodyWorkoutType` raw value fails the entire snapshot decode — `BodyMetricsKit/WorkoutSummary.swift:98–116` + `BodyMetricsKit/BodyWorkoutType.swift:16`

`WorkoutSummary.type` uses synthesized Codable for a String-raw enum; an unrecognized rawValue throws and aborts the whole `WorkoutMonthSnapshot`/dashboard payload. These snapshots cross the iOS app, watch, and widget processes — a version-skewed writer that gained a new workout case (cases *have* been added historically: `swimBikeRun`, `underwaterDiving`, …) makes older readers throw away entire months of cached data. `ReadinessSummary` is shielded by `try? decodeIfPresent` (`HealthSummarySnapshot.swift:355`); workout types aren't. **Fix:** custom `init(from:)` decoding unknown values to `.other` (consider the same for `SleepStage`).

### M24. O(scoredDays × historyDays) sleep scan in readiness history recompute — `BodyMetricsKit/Sleep.swift:78–81` via `ReadinessScoreCalculator.swift:606–618`

`SleepHistorySnapshot.summary(on:)` linearly scans all history days, recomputing `calendar.startOfDay` per element. `dailySeries` calls `sleepAssessment` per scored day, and `recalculatingReadiness` scores from the oldest trend point (up to ~450 days) — ~200k `startOfDay` calls per full recompute, on the refresh path. `ReadinessDailySeriesContext` already pre-indexes every *other* metric by day. **Fix:** build a `[Date: SleepDaySummary]` once and give sleep the same treatment.

---

## Low

### L1. Second queued post-write refresh is silently dropped — `Body/Services/HealthKitWorkoutStore.swift:489–492`
Two writes queued during one refresh resume together; the first re-claims `isRefreshing`, the second's `refreshHealthMetric` bails permanently — that metric doesn't reflect the write until a manual refresh. **Fix:** `while isRefreshing { await awaitNextRefreshCompletion() }` before calling.

### L2. `proEntitlementObserver` never removed; class has no `deinit` — `Body/Services/HealthKitWorkoutStore.swift:311–319`
Block-based observers must be removed explicitly. App-lifetime object today, so latent — but add `deinit { proEntitlementObserver.map(NotificationCenter.default.removeObserver) }`.

### L3. Refresh/month-load awaiters aren't cancellation-responsive once registered — `Body/Services/HealthKitWorkoutStore.swift:185–192, 208–215`
`Task.isCancelled` is checked only before registering; a cancelled `.task` still blocks until the whole refresh finishes, then runs follow-up fetches for a view that's gone (`loadMonthIfNeeded` doesn't re-check; line 937 does). **Fix:** `withTaskCancellationHandler` or re-check after resuming.

### L4. Session route/split caches are unbounded — `Body/Services/HealthKitWorkoutStore.swift:153–159`
`routeCache` (full GPS arrays) and `distanceSampleCache` grow per detail open for the app's lifetime; `monthSnapshots` got a 12-month LRU cap for exactly this reason. **Fix:** small FIFO cap mirroring `noteMonthSnapshotStored`.

### L5. Synchronous disk *writes* on the main thread at init — `HealthKitWorkoutStore.swift:217–219`, `WorkoutSnapshotStore.swift:171–178`, `HealthDashboardSnapshotStore.swift:224`
The main-file read on main is a documented tradeoff, but first-launch placeholder seeding and the legacy-migration re-encode+write run synchronously during launch. **Fix:** return the decoded value and defer the writes to `snapshotPersistQueue`.

### L6. Failed training-load fetch is memoized until the next anchor reset — `Body/Services/HealthKitFetchEngine+TrainingLoad.swift:35`
A thrown error is cached in `sharedTrainingLoadWorkoutsTask`; both training-load consumers fail together for the rest of the refresh cycle and a widget/detail re-request can't recover. **Fix:** nil the memo when `task.value` throws.

### L7. `saveBodyComposition` doesn't clamp; out-of-range body-fat can raise an Obj-C exception in HealthKit — `Body/Services/HealthKitFetchEngine+Write.swift:66`
`bodyFatPercent > 100` produces a quantity fraction > 1.0, which HealthKit rejects with a validation exception rather than a catchable error. The only caller clamps via wheel ranges (latent), and `saveWorkoutEffort` in the same file clamps defensively. **Fix:** clamp to 0…100 and sanity-bound weight.

### L8. `?? Date()` fallbacks produce wrong-window fetches instead of failures — `Body/Services/HealthKitFetchEngine.swift:1099`
Invalid month/year silently fetches "now…now" and returns `[]`, which the store would cache as the month's truth. Practically unreachable today; a `guard … else throw` is cheaper than the eventual debugging session.

### L9. Baseline algorithm duplicated verbatim — `BodyMetricsKit/ReadinessScoreCalculator.swift:213–250` vs `398–440`
`ReadinessBaselineCache.baseline(for:)` and `robustBaseline(for:values:floor:)` implement the same 56-day/3-day-exclusion/MAD logic twice; a retune of one silently desynchronizes the other. Extract the shared computation.

### L10. `ReadinessStatus.status(for:)` maps scores above 100 to `.poor` — `BodyMetricsKit/ReadinessModels.swift:23–34`
`case 95...100` + `default: .poor`. The calculator clamps today, but this is a public entry point also fed from persisted scores. Use `case 95...:`.

### L11. `SleepSummary.score` is dead code with divergent semantics — `BodyMetricsKit/Sleep.swift:23–25`
No call site; anyone reaching for it scores against a default 8 h goal with no baselines, producing a different number than the sheet. Remove or plumb the goal through.

### L12. Hardcoded 24-hour `"HH:mm"` ignores 12-hour locales — `BodyMetricsKit/WorkoutSummary.swift:501–516`
`timeRangeText` shows "18:05-19:02" to US-style users while the rest of the app uses locale templates. Use template `"jmm"` via the existing formatter cache. (Same class of issue: the sleep widget axis `hour(.twoDigits(amPM: .omitted))` renders "09:30" ambiguously for AM/PM — `HealthWidgetSleepStagesView.swift:102–104`.)

### L13. `Calendar.bodyGregorian` pins Sunday-first for all locales, rebuilt on every access — `BodyMetricsKit/WorkoutMonthSnapshot.swift:280–286`
Month grids render Sunday-first for Monday-first locales even though the rotation helper supports any `firstWeekday`; it's also a computed `static var` reconstructed per access. If Sunday-first is deliberate for chart stability, document it; otherwise feed the locale value.

### L14. CLGeocoder throttle/transient failure is cached for the whole session as "no locality" — `Body/Services/BodyReverseGeocoder.swift:26` + `HealthKitWorkoutStore.swift:563–566`
`try?` collapses `CLError.network` rate-limit throttles into `nil`, which the caller caches in `routeCache` for the session; concurrent one-off `CLGeocoder()` instances evade the one-request-at-a-time guidance and make throttling likely. **Fix:** one shared geocoder actor; don't cache a nil locality on network errors.

### L15. Dead `sleepStageSnapshot` parameter, immediately shadowed — `Body/Services/HealthWidgetSnapshotBuilder.swift:64, 77–78`
The passed value is never used (the shadowing recompute is what makes the stale-sleep guard correct); the production caller and tests compute it for nothing, and a caller passing a *different* snapshot would be silently ignored. Delete the parameter.

### L16. `hasResolved` never flips when Purchases is unconfigured — `Body/Services/BodyProStore.swift:43, 55`
SwiftUI previews (the documented unconfigured case) show a permanently "checking…" paywall card. Set `hasResolved = true` in the guard's early return.

### L17. `BodyProEntitlement.isUnlocked` read as a bare static in two sheets — `Body/Views/BodySettingsView.swift:2038` + `Body/Views/Health/BodyHealthDataSourcePickerSheet.swift:21`
The static produces no SwiftUI invalidation; the comments concede reactivity piggybacks on unrelated `workoutStore` publishes. Buying Pro from the paywall those very rows present leaves lock icons stale until an unrelated re-render. **Fix:** read `@Environment(BodyProStore.self)` like the rest of the app.

### L18. `BodyAppTheme.storedValue` can only ever return `.dark` — `Body/Models/BodyAppearancePreference.swift:1381`
`.system`/`.light` (with full displayName/icon/tint plumbing) are unreachable through the parser and no Settings row exposes the theme. Dead code that reads like a live feature — delete the branches or parse honestly.

### L19. `UIScreen.main.bounds.width` drives card-preview sizing — wrong under iPad Split View/Stage Manager — `Body/Views/Health/BodyHealthMetricCard.swift:34, 148, 272` + `BodyHomeView.swift:665`
A narrow Split View window on a wide screen selects the regular preview width; the app otherwise adapts via `horizontalSizeClass`, and `UIScreen.main` is effectively deprecated for scene-based apps. Thread the container width in — it's already part of the memo key.

### L20. `Dictionary(uniqueKeysWithValues:)` on workout IDs traps on any duplicate — `Body/Views/BodyWorkoutsView.swift:552`
Elsewhere the code defensively dedupes workout IDs by subscript (`BodyHealthMetricDetailView.swift:1557`), acknowledging duplicates can occur. If a snapshot ever lists one workout under two days, the first search keystroke crashes. **Fix:** `Dictionary(_, uniquingKeysWith: { first, _ in first })`. (Same hardening for the day-bucketed maps in `MetricCharts.swift:520–521`, `SourceComparisonCharts.swift:131–136` — currently unique by construction.)

### L21. `@State` holding a plain mutable class as a cache — `Body/Views/BodyWorkoutsView.swift:23`
`searchCorpusCache` is a non-observable class mutated during body evaluation, and a fresh instance is allocated and discarded on every view init. The three `@StateObject` caches in `BodyHealthMetricDetailView` are the codebase's own better pattern — use it.

### L22. `WKSnapshotRefreshBackgroundTask` completed through the generic path — `BodyWatch/BodyWatchApp.swift:58–70`
Snapshot tasks should complete via `setTaskCompleted(restoredDefaultState:estimatedSnapshotExpiration:userInfo:)`; completing generically means the dock snapshot is never deliberately refreshed after a data push, so the app switcher can show a stale dashboard.

### L23. iOS widget line charts silently bridge missing days; the watch sparkline breaks them — `BodyShared/Components/HealthWidgetTrendChartView.swift:207–230` vs `BodyWatch/WatchSparklineView.swift:183–196`
`linePath` skips nil points with `continue`, connecting the neighbors of a gap as if a reading existed; the watch deliberately splits runs on nil. Same data, opposite gap semantics — the iOS rendering fabricates trend segments. **Fix:** reset `started = false` on nil, mirroring the watch.

### L24. Month rollover: the calendar widget silently renders the previous month with no label — `BodyShared/Services/WorkoutSnapshotStore.swift:189–198` + `BodyWidgetExtension/WorkoutCalendarWidget.swift:131–142`
`loadCurrentOrPreviousIfEmpty()` falls back to the previous month whenever the current month is empty, and the widget renders no month title — early each month the grid shown is last month's, indistinguishable to the user. Render `snapshot.monthTitle`, at least when the fallback fires.

---

## Suggestions

- **S1. Entitlement flip bypasses `BodyWidgetReloadCoalescer`** — `BodyProStore.swift:174` calls `WidgetCenter.shared.reloadAllTimelines()` directly; a purchase completing during a health refresh issues two XPC reloads within a second. Route through the coalescer (its 1 s debounce is imperceptible post-purchase).
- **S2. `restore()` reports silent success when nothing was restored** — `BodyProStore.swift:116–125`; the paywall gives no "no purchases found" feedback — a classic App Review/support nit.
- **S3. Reload requested before the at-rest strip is written** — `HealthKitWorkoutStore.swift:2381–2395`: `requestReload()` fires ~1 s later, potentially before the utility-priority rewrite lands, so the widget can rebuild from the un-stripped file with no follow-up reload. Move `requestReload()` into the detached task after the saves.
- **S4. Dashboard snapshot cache is backed up** — `HealthDashboardSnapshotStore.swift:71–83`: fully regenerable data (potentially years of series) sits in Application Support without `isExcludedFromBackup`. Exclude it or move to Caches.
- **S5. Displayed readiness component `weight`s (30/30/25/15) don't reflect the multiplicative formula** — `ReadinessScoreCalculator.swift:321–368`: the score is `core × sleepFactor × strainModifier × vitalsFactor`; presenting the weights as percentage contributions misstates the math.
- **S6. Identifiable IDs can collide** — `HealthTrendDataPoint.id = date` (`HealthTrend.swift:1494–1501`) and `WorkoutHeartRateSample.id = "\(t)-\(bpm)"` (`WorkoutSummary.swift:8–15`) duplicate when two sources emit samples at the same timestamp — undefined behavior in `ForEach`.
- **S7. `TrainingLoadInterval` band boundaries overlap** — `TrainingLoadCalculator.swift:177–221`: `interval(for: 1.3)` returns `.optimal` while a chart drawing band edges labels 1.3 as medium risk; pick one canonical inclusivity.
- **S8. Activity-ring summary parsing duplicated three times** — `HealthKitFetchEngine+ActivityRings.swift:117/195/244`; extract one helper.
- **S9. `userMaxHeartRate` uses `Calendar.current`** while the rest of the engine threads an injected calendar (`HealthKitFetchEngine.swift:128`).
- **S10. iOS widgets have no `widgetURL` deep links** — the watch complications deep-link per metric; the iOS metric/trend/sleep widgets all open the app root, and `BodyWidgetLockedView` could deep-link to the paywall.
- **S11. Corner-gauge unit inference is brittle** — `WatchComplicationView.swift:107–124`: `metric.unit.contains("F")` infers Fahrenheit from a display string, and `String(format: "%.1f")` isn't locale-aware while the rest of the watch uses `formatted`.
- **S12. `HealthTrendProvider` is the only iOS provider that skips `sanitizingStaleSleep`** — `HealthTrendWidget.swift:146–147`: benign today, a trap if the trend view ever reads `displayValues`/`sleep`. Apply uniformly.
- **S13. Swift 6 readiness** — the `HKWorkout`/`HKSource` captures in `group.addTask` closures (`HealthKitFetchEngine.swift:1436, 1582, 1649`) are safe under Swift 5 (immutable objects) but will need `@unchecked Sendable` wrappers (like the existing `KindSources`) for a strict-concurrency migration.

---

## Sound Areas (verified correct)

- **Continuation discipline** — every `withCheckedContinuation` across the engine, watch store, and effort fetcher resumes exactly once on all paths; throwing continuations in authorization/write paths included. No double-resume or leak anywhere.
- **Persistence discipline** — all four snapshot stores: `.atomic` writes, `.sortedKeys` deterministic encoding with byte-compare save gating (correctly reasoned about key-order randomization), `fileReadNoSuchFile` distinguished from real errors, decode failures degraded to nil/placeholder; mtime+size-keyed, lock-protected decode caches bound widget-process I/O and memory.
- **Schema evolution** — consistent `decodeIfPresent ?? default` for post-v1 fields, tolerant legacy decoder for the widget trend shape (migration-tested), string metric kinds + ISO-8601 dates on the watch snapshot so mixed phone/watch builds degrade instead of rejecting.
- **Statistics semantics** — `.cumulativeSum` for steps/energy/exercise/daylight, discrete min/max/avg for vitals, `.mostRecent` for body-mass; per-workout steps/distance use `predicateForObjects(from:)` to avoid iPhone/Watch double counting.
- **Refresh reentrancy** — `isRefreshing` claimed before the first suspension; continuation register/resume sites MainActor-isolated with no check-to-append gap; `finishRefresh`/`finishMonthLoad` defers always drain awaiters. Out-of-order watch pushes guarded by `lastQueuedGeneratedAt` stamping.
- **Sleep staleness** — double-guarded at build time (`SleepSummary.asOf`) and display time (`sanitizingStaleSleep`/`sanitized(asOf:)`), with regression tests on both sides (residual edges are M14/M15).
- **View-layer memoization** — `BodyHomeTrendComputationCache` (content-hash fingerprints incl. backdated-edit invalidation), day-series and sleep-consistency caches, and the deliberate `@Observable` scroll-state isolation on Home are exemplary; no `@ObservedObject`-where-`@StateObject`-needed, no timer/observer leaks, no force-unwraps in any `ForEach`.
- **Chart crash-safety** — degenerate y-domains, `fiveStepDomain` lower≥upper guard, gradient-polyline strictly-increasing-location guard, watch weekday index `% count` guard.
- **Pro gating** — applied to the *effective* value (range clamps, day-picker clamps, secondary-series gates), uniform across all five iOS widgets with preview intentionally unlocked; entitlement cache write path is single-writer, value-guarded, with locked fallback.
- **Domain math** — `WorkoutMetricComparisonBuilder` (near-zero guards, isFinite before `Int()`, ±999% clamps), `WorkoutSplitCalculator` (interval clipping, strict >0 duration guards), circular sleep-consistency math (atan2 mean, near-zero resultant guard) are all correct and well-tested.
- **Logging & entitlements** — no health values or tokens logged anywhere; App Group id consistent across all four targets and matches the stores; HealthKit entitlement only on app+watch; `APPLICATION_EXTENSION_API_ONLY` on the widget extension; RevenueCat linked to the iOS app only, widgets correctly reading the cached flag.

---

## Test Coverage Gaps (prioritized)

1. **HealthKit query composition — zero coverage** (blocked by M10). Not one predicate, statistics option, unit, or interval is asserted. Highest-value seam in the codebase.
2. **Out-of-order sample arrival** — no test for `incrementalFetchStart`/`mergeIntradaySamples` with backfilled samples (would have caught H1). Existing tests cover trimming/appending only.
3. **Permission filtering → readiness interaction** — no assertion that disabling Heart removes autonomic input given cached sleep-history vitals (would have caught H2).
4. **Trend bucketing** — `calendarPoints`/`bodyTrendAggregationBuckets`/`compressedStableLineChartPoints` have zero direct tests; a "today appears in the year chart" assertion would have caught H3.
5. **Navigation graph** — nothing exercises route registration (H4 invisible to the suite); a test asserting every `NavigationLink(value:)` type has a matching destination is cheap.
6. **Watch merge rules** — the don't-downgrade rule, readiness carve-out, and merge×`sanitized()` interplay (exactly where M15 lives) are pure value-type code with no tests.
7. **Timeline providers** — none of the 6 providers has tests for entry dates, midnight behavior (M14), placeholder-vs-empty routing (M16), or Pro gating.
8. **BodyProStore state machine** — `BodyProEntitlementTests` covers only the App Group flag; purchase/cancel/pending/failed transitions, `restore()` outcomes, and reload-on-flip are untested (needs the M10-style seam for `Purchases`). `ProjectConfigurationTests`' string assertions would pass against a broken implementation.
9. **Persistence ordering/concurrency** — interleaved saves, `snapshotPersistQueue` FIFO, intraday-vs-refresh race (M4/M5), double-queued `refreshAfterWrite` (L1) — all deterministically testable, all untested.
10. **Untested pure logic** — `TrainingLoadCalculator` (no dedicated tests), `SleepScoreSummary` curves, `BodyValueFormat` conversions, `ActivityRingHistorySnapshot` merge/prune, `BodyWorkoutHeartRateChartMetrics` (extract first), `wristTemperatureBaseline*`, `WorkoutRoutePaceColoring`, `WatchMetricDeepLink` round-trip, `BodyReverseGeocoder.format`.
11. **Well covered (for the record):** ReadinessScoreCalculator, WorkoutEffortEstimator, WorkoutSplitCalculator, WorkoutMonthSnapshot (238 KB suite), sleep stage/as-of models, snapshot load caches, widget snapshot migration, reload coalescer burst collapse.

---

## Priority Fix List

Ranked by user-visible risk × breadth × cost to fix:

1. **H6 — verify the RevenueCat API key** (minutes of work, gates all revenue; silent production failure mode if wrong).
2. **H4 — register the `HealthMetricKind` navigation destination** (one modifier; two dead cards on a default page today).
3. **H1 — overlap window or anchor for incremental intraday fetches** (permanent, compounding health-data loss for multi-source users; moderate effort + regression test #2).
4. **H2 — strip sleep-history vitals in `filtered(by:)`** (privacy-semantics bug: permissions toggle doesn't do what it says; small, contained fix + test #3).
5. **H3 — anchor long-range bucketing from the newest day** (today missing from 6M/Y charts for every user; small fix + test #4).
6. **M14 + M15 — midnight timeline entries and the watch sleep-merge night carry** (every-night staleness class; finishes the job the 0.9.7 stale-sleep fix started).
7. **H5 — stop the workout-detail per-frame recompute** (worst perf hazard in the app; the codebase already contains the right pattern to copy).
8. **M7 — distinguish HK query failure from empty** (prevents a locked-device background refresh from blanking good cached trends; unlocks honest error UX later).
9. **M1 + M5 + M4 — close the refresh-gate gaps** (dropped refetch on source change, intraday lost-update, unordered detached saves — three instances of the same invariant-enforcement theme; fix together).
10. **M16 + M17 — widget data honesty** (placeholder workouts shown as real; wrong percentages; both trivial).
11. **M3 + M2 — permission-revoke at-rest wipe and TTL conflation** (privacy consistency + stale-vitals-on-resume).
12. **M23 — tolerant `BodyWorkoutType` decoding** (cheap insurance before the next workout-type addition breaks version-skewed readers).
13. **M10/A2 — introduce the `HKHealthStore`/`Purchases`/`WCSession` seams** (the enabling investment for gaps #1, #6, #8; do it opportunistically as the files above are touched).
14. **A6 — extract the four god files along the seams identified** (do incrementally with each fix above rather than as a big-bang refactor; extracting `BodyWorkoutDetailSheet` naturally accompanies fix #7, the detail-model factory accompanies fix #2).

Expected payoff: items 1–5 remove all known incorrect-behavior paths visible to users; item 6 closes the recurring "stale sleep" bug family for good; items 7–9 eliminate the main perf hazard and the data-consistency race class; items 13–14 convert the least-tested, highest-risk code in the app into testable units so the next review finds less.
