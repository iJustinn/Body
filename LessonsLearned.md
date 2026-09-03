# Lessons Learned

Persistent project-specific troubleshooting notes for future Codex runs.

## Entries

### 2026-06-10 - `JSONEncoder` output is not byte-stable; save-if-changed compares need `.sortedKeys`
- Context: All three snapshot stores (dashboard, workout, widget) dedupe disk writes by encoding and comparing bytes against the existing file, and gate widget reloads on that result (2026-05-18 "Save-if-changed" entry).
- Symptom: A new test asserting `save(x); save(x) == false` failed reproducibly — two `JSONEncoder().encode(...)` calls on the *same value instance* returned equal-length but different bytes ("2542 bytes is not equal to 2542 bytes").
- Cause: Foundation's `JSONEncoder` randomizes keyed-container key order between encode calls. The byte-compare therefore almost never matched, so every refresh rewrote every snapshot file and requested a widget reload — the dedupe had been silently broken since it was introduced.
- Fix: The stores set `encoder.outputFormatting = [.sortedKeys]` (see `HealthDashboardSnapshotStore.makeSnapshotEncoder()`); `testSnapshotEncoderIsByteStableAcrossEncodes` guards the property.
- Reuse: Any encode-and-compare or encode-and-hash scheme over `Codable` JSON must use `.sortedKeys` (and a fixed date strategy). Never assume encoder output is canonical.

### 2026-06-10 - Persist large lazily-loaded series in a sidecar file so cold launch decodes stay small
- Context: The intraday `*DaySamples` series (tens of thousands of raw points once a metric detail view has been opened) were persisted inside the main dashboard snapshot, which `HealthKitWorkoutStore.init` decodes synchronously on the main thread before the first frame.
- Fix: `HealthDashboardSnapshotStore.save` strips day samples from the main file (`HealthTrendSnapshot.strippingDaySamples()`) and writes them to `lastHealthDashboardDaySamples.json`; `HealthKitWorkoutStore.hydratePersistedDaySamplesIfNeeded()` decodes the sidecar off-main and merges only still-empty fields. Every refresh/lazy-load entry point awaits the hydrate first so a save can't clobber the sidecar with empty series and the incremental fetch sees the cache. Legacy combined files still decode (`decodeIfPresent ?? .empty`).
- Reuse: When a cache blob mixes launch-critical and lazily-consumed data, split the files rather than tuning the decoder. Merge policy must be fill-only-empty so background hydration never overwrites fresher in-session data, and saves must be ordered after hydration.

### 2026-06-10 - Extend the OR-compound batching pattern to per-day vitals; recompute readiness at most once
- Context: After the 2026-05-18 N+1 fixes, full-refresh sleep-vitals hydration still issued up to ~365 days × 5 per-night `HKSampleQuery`s (concurrency-bounded, total unchanged). Separately, `updateHealthDashboardSnapshot` chained `filtered(by:)` — which internally recomputes readiness — *and then* an anchored `recalculatingReadiness`, so every refresh paid the per-day readiness walk twice.
- Fix: `fetchSleepVitals(forIntervals:)` runs ONE query per vital type with an OR-compound of the per-night predicates (so only in-night samples cross IPC) and partitions per night in memory (`averageVitalValues`, two-pointer over sorted samples). `updateHealthDashboardSnapshot` now uses `filteredWithoutReadinessRecompute` plus a single anchored recompute, skipped entirely when the refreshed metric is outside `readinessInputMetricKinds`. Heart-rate partitioning binary-searches each workout's first sample instead of rescanning the month, and effort-score fan-out is pumped at ≤12 in-flight queries.
- Reuse: The OR-compound + in-memory partition pattern scales to hundreds of subpredicates; prefer it over bounding concurrency when the per-element predicate is a plain date window. When a transform chain hides a recompute inside a convenience method (`filtered(by:)`), call the explicit no-recompute variant and recompute once at the end.

### 2026-05-18 - Eliminate N+1 HK queries with OR'd predicates + bounded task groups
- Context: After moving HK fetch orchestration off the main actor (engine refactor), per-workout and per-sleep-day fan-outs still serialized inside the engine. `fetchWorkoutSummaries` awaited `fetchHeartRateSamples(for: workout)` and `fetchSavedEffortLevel(for: workout)` once per workout in a `for` loop; `fetchDailySleepHistory` awaited `fetchSleepVitals(...)` once per sleep day in a `for` loop. With ~30 workouts/month × 3 months and up to ~365 sleep days, that's hundreds of sequential HK round-trips on every full refresh.
- Symptom: ~8–10 s cold-launch dashboard refresh even after HK queries were already off-main.
- Cause: Each per-element `await` released the actor but blocked the parent coroutine, so HK queries ran one-at-a-time within a category. The actor's reentrancy didn't help because there was only one waiter per category.
- Fix:
  - **Heart-rate samples** are now batched: build an OR-compound predicate of every workout's `predicateForSamples(withStart:end:)` and issue *one* `HKSampleQuery` for the month. Samples are partitioned per workout in memory afterward by linear scan (handles overlapping workouts correctly because we filter per-workout against `[startDate, endDate)`).
  - **`HKWorkoutEffortScore`** can't be batched (the relationship predicate is per-workout) but can fan out via `withTaskGroup`; each `group.addTask { await self.fetchSavedEffortLevel(for: workout) }` re-enters the actor briefly to call `healthStore.execute(query)`, then releases at the continuation `await`, letting HK serve them in parallel.
  - **Per-day sleep vitals** use a static helper `hydrateSleepVitalsInParallel(days:maxConcurrentDays:hydrate:)` that pumps a `withTaskGroup` with bounded concurrency (16). 16 days × 5 sub-queries = ≤80 concurrent HK queries — fast without flooding the framework.
- Reuse: When a HK orchestrator has an `await` inside a `for` loop, ask: can the predicate be unioned (OR-compound)? If yes, fold into one query and partition client-side. If no (per-element relationship predicate), use a bounded `withTaskGroup` so HK can parallelize the round-trips. The actor pattern naturally supports this — actor reentrancy through `await` boundaries means concurrent `group.addTask`s don't deadlock.

### 2026-05-18 - Memoize shared fetches inside the actor with a `Task<>` cache keyed by request window
- Context: `fetchTrainingLoadSummary` (running inside `fetchHealthSummary`) and `fetchTrainingLoadSeries` (running inside `fetchHealthTrends`) both fetched the same 180-day `HKWorkout` window independently — once per orchestrator, run in parallel via `async let`. Same data, two HK round-trips, two per-workout effort fan-outs.
- Symptom: Wasted ~1 s on every full refresh.
- Cause: The two orchestrators had no way to share — each lived inside its own `async let` chain, and `async let` resolves to a `Task` that can't be reused across callers.
- Fix: Engine holds `private var sharedTrainingLoadWorkoutsTask: Task<[WorkoutSummary], Error>?` plus a `TrainingLoadWorkoutsWindow` cache key. The first caller creates the task and stores it; subsequent callers inside the same refresh return `try await task.value` of the cached task. `setHealthTrendAnchorDate(_:)` (which is called at refresh start *and* end) clears the cache so each refresh starts fresh.
- Reuse: When two concurrent actor methods need the same expensive fetch and the result is value-typed, cache the *Task* (not the value). Actor serialization guarantees exactly one task is created; both callers await the same `.value`. Key the cache by request parameters so wider-window fetches don't get reused for narrower windows. Clear on a refresh-boundary signal that's already wired (`setHealthTrendAnchorDate` here).

### 2026-05-18 - Stream the dashboard refresh in buckets so users see progress instead of a 10 s wait
- Context: `refreshRecentMonths` used `async let nextHealthSummary / nextHealthTrends / nextActivityRingHistory`, awaited all three, then called `updateHealthDashboardSnapshot` once. UI saw zero change during the whole refresh — then one big update at the end.
- Symptom: User-reported "nothing is changing for 10 seconds." Even though disk-cached values were already visible from `init`, the dashboard refresh produced no visible motion until completion.
- Cause: The collect-then-publish pattern. Even though sub-fetches finish at different times (summary ≪ trends), nothing landed until the slowest one returned.
- Fix: New `fetchDashboardSnapshotProgressively(calendar:)` helper runs the three engine fetches inside `withTaskGroup(of: DashboardFetchUnit.self)` and the `for await unit in group` loop writes to `@Published` state immediately for each bucket. UI sees: cached data → fresh summary numbers (~1 s) → fresh rings (~1–2 s) → fresh trend charts (3–5 s) → final readiness recompute. The final `updateHealthDashboardSnapshot` still runs after the loop for filter + readiness recompute + disk save.
- Readiness preservation: progressive summary publish uses `s.replacingMetric(.readiness, with: healthSummary)` so the cached readiness stays visible during the stream — the freshly fetched summary has empty/default readiness because recompute hasn't run yet. The final commit overwrites it with the recomputed value.
- Per-month workouts: `refresh(monthKeys:)` previously collected `(key, workouts)` pairs into a dict, then wrote `monthSnapshots[key]` in a separate loop. Moved the write inside the `for try await` so each month publishes the moment it returns from the task group. Workouts tab fills in per-month rather than waiting for the slowest month.
- Reuse: For multi-bucket parallel fetches whose results land in independent `@Published` fields, prefer `withTaskGroup` + `for await` over `async let` + sequential awaits. Even with the same total wall-clock time, the perceived latency drops significantly because each bucket commits as soon as it's ready.

### 2026-05-18 - Persist refresh-debounce timestamps so cold start uses the same TTL as warm resume
- Context: `syncWhenAppBecomesActive` had three tiers based on `lastSuccessfulRefreshDate`: under 60 s skip, 60 s–5 min current-month workouts only, ≥5 min full refresh. But `lastSuccessfulRefreshDate` was in-memory only, so every cold start saw it as `nil` and fell through to the full path — even when the on-disk snapshot was seconds old.
- Symptom: Cold start = full refresh, always. Warm resume = tiered TTL, fast. Closing and reopening the app paid the same 8 s cost the user thought refresh deduplication should have avoided.
- Cause: `markRefreshSucceeded(date:)` set the in-memory value but didn't persist; `init` defaulted it to `nil`.
- Fix: Added `saveLastSuccessfulRefreshDate / loadLastSuccessfulRefreshDate / clearLastSuccessfulRefreshDate` to `HealthDashboardSnapshotStore` (UserDefaults under `lastHealthDashboardSuccessfulRefreshDate`). `init` restores it; `markRefreshSucceeded(date:)` persists; `clearLocalCache` clears. After this, cold start hits the same tiered TTL.
- Reuse: Any debounce/TTL state used by a `.task`/scenePhase entry point must be persisted, otherwise it's only effective for warm resumes within a single process. The cached *payload* on disk isn't enough — the *meta* (when it was written) has to ride along, or the launch path has no way to honor the TTL.

### 2026-05-18 - PrivacyInfo.xcprivacy required for required-reason API usage; Xcode 16 synced groups bundle it automatically
- Context: Body uses `UserDefaults` extensively and calls `FileManager.default.attributesOfItem(atPath:)` on its own cache files (to display "On-disk size: X" in the Settings cache status). Both APIs fall under Apple's required-reason API list and need a `PrivacyInfo.xcprivacy` manifest at App Store submission time.
- Cause: Missing privacy manifest produces App Store Connect warnings on submission of any iOS 17+ build.
- Fix: Added `Body/PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (in-app interactive functionality) and `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1` (inspect timestamps for files in the app container). `NSPrivacyTracking = false`, `NSPrivacyCollectedDataTypes` empty (no off-device data collection).
- Xcode 16 specific: the project uses `PBXFileSystemSynchronizedRootGroup` for `Body/` (and `BodyShared/`, `BodyWidgetExtension/`, `BodyTests/`). Files placed in those directories are automatically included in the corresponding target's build — no `project.pbxproj` edit is needed. `PrivacyInfo.xcprivacy` placed at `Body/PrivacyInfo.xcprivacy` ships in `Body.app/PrivacyInfo.xcprivacy` and is also replicated into the embedded widget extension's appex bundle.
- Reuse: Before submitting a new build with privacy-sensitive APIs, grep the codebase for the four required-reason categories (`UserDefaults`, `FileTimestamp` via `attributesOfItem`/`stat`-family, `SystemBootTime`, `DiskSpace`) and update the manifest. For Xcode 16 synced-folder projects, just edit the file in place — no project file changes.


### 2026-05-18 - Extract HK fetch work into a non-`@MainActor` actor when the store grows
- Context: `HealthKitWorkoutStore` was a 3,900-line `@MainActor final class: ObservableObject`. Every HK query, predicate construction, source-map mutation, and dashboard fetch orchestrator (`fetchHealthSummary` with ~17 `async let`s, `fetchHealthTrends` with ~25, `fetchHealthDashboardSnapshot`, `fetchHealthDataSourceOptions`) ran on the main actor. HK callbacks dispatched off-main, but every continuation resumed back on main, and Swift-level orchestration between awaits stayed on the main thread.
- Symptom: After Phase 1 (off-main readiness recompute + off-main JSON saves) the worst CPU spikes were gone but refresh still caused noticeable main-thread pressure from continuation resumption flood + repeated `@Published` writes triggering SwiftUI redraws of ~14 metric cards.
- Cause: `@MainActor` isolation on the orchestration layer means *every* `async let` resumption, every aggregate read, and every per-fetch helper call queues behind UI work.
- Fix: New `actor HealthKitFetchEngine` (`Body/Services/HealthKitFetchEngine.swift`) owns `HKHealthStore`, `healthSourcesByKind`, `fetchedHealthDataSourcePermissionRawValue`, `healthTrendAnchorDate`, and mirrored copies of the three selections. All leaf HK queries, predicate helpers, and orchestrators moved into it. `HealthKitWorkoutStore` kept `@Published` outputs, public refresh entry points, snapshot publishing, and source comparison helpers — its refresh methods now look like: `let result = await engine.fetchX(...); publish on main`. Selection setters on the engine (`setPermissionSelection` etc.) are awaited from the store's `updateHealthPermission` / `updateHealthDataSource` / `updateSecondaryHealthDataSource`.
- Special cases: `fetchHealthTrends` and `fetchHealthDashboardSnapshot` needed a `cachedTrends:` / `existing:` parameter because they previously read `self.healthTrends` / `self.healthSummary` directly to preserve lazy-loaded intraday day samples and to handle the single-metric Readiness early-return. `fetchHealthDataSourceOptions` changed from mutating the store's `@Published healthDataSourceOptionsByKind` to *returning* the next dict (or `nil` for "no change"), with the store assigning the result. `loadIntradayMetricSamplesIfNeeded` stayed on the store because it reads/writes the `@Published healthTrends` — it just delegates the actual HK fetches to `engine.fetchIntradayDaySamples` / `engine.fetchSecondaryDaySamples`.
- Test impact: Five static helpers (`recentChartMonthCount`, `readObjectTypes`, `workoutType(for:)`, `mergedSleepDuration`, `sleepDuration`) stayed on the store because tests reference them via `HealthKitWorkoutStore.X`. `HealthKitWorkoutError` was hoisted to file-level visibility (was `private`) so the engine in a separate file could throw/match it. Four string-grep assertions in `BodyTests/ProjectConfigurationTests.swift` were redirected from the store's source file to the engine's; semantic assertions unchanged.
- Reuse: For any `@MainActor ObservableObject` that grows past ~1,500 lines and starts to host non-UI orchestration, push the orchestration into a separate `actor` and have the view-model own only `@Published` state plus the public refresh entry points. Mirror selections instead of passing them per-call when many fetches need them — single source of truth on the view-model, engine holds a synced copy. Move `fetchedHealthDataSourcePermissionRawValue`-style caches with the data they guard, not with the publisher. Return new state from engine methods that previously wrote `@Published` directly so the view-model decides when to publish.

### 2026-05-18 - Defer first-frame readiness recompute and offload JSON saves with `Task.detached`
- Context: Cold launch ran `HealthDashboardSnapshot.filtered(by:)` inside `HealthKitWorkoutStore.init`, which transitively called `recalculatingReadiness(calendar:)` — a per-day iteration over up to ~365 trend points × multi-metric baselines, on the main thread, before the first frame could paint. Every successful refresh also re-ran the same recompute synchronously in `updateHealthDashboardSnapshot`, then JSON-encoded ~100 KB and atomic-wrote to disk (twice for dashboard + workouts) plus called `WidgetCenter.shared.reloadAllTimelines()` (XPC round-trip), all on the main actor.
- Symptom: First frame stalled noticeably at cold launch; refresh felt frozen for ~10 s on Apple Watch users even though HK queries themselves dispatched off-main.
- Cause: `recalculatingReadiness` and `JSONEncoder.encode` + `Data.write(to:options:[.atomic])` are CPU/disk-heavy and were tied to the main actor by virtue of being inline inside `@MainActor` methods.
- Fix:
  - Added `HealthDashboardSnapshot.filteredWithoutReadinessRecompute(by:)` and used it in `HealthKitWorkoutStore.init` so the cached `summary.readiness` value from disk is preserved through filtering. The next refresh recomputes it on a background thread.
  - Made `updateHealthDashboardSnapshot` `async`. Wrapped the filter+`recalculatingReadiness` chain in `Task.detached(priority: .userInitiated)` and awaited the result before publishing. Wrapped `HealthDashboardSnapshotStore.save(...)` + `saveSecondarySelectionSignature(...)` in `Task.detached(priority: .utility)` (fire-and-forget; in-memory state is already updated when the disk write starts).
  - Made `persistRecentMonthSnapshots` (then `updateCurrentMonthSnapshot`) capture the snapshots and run `WorkoutSnapshotStore.save` for each persisted month + `WidgetCenter.shared.reloadAllTimelines()` inside `Task.detached(.utility)`.
  - Made `applyPermissionSelectionToCachedData` `async` with the same pattern.
  - Single-metric Readiness refresh in `fetchHealthDashboardSnapshot` wraps its `.recalculatingReadiness(...)` in `Task.detached(.userInitiated)`.
- Tradeoff: Brief few-ms window during refresh where in-memory state is updated but the disk JSON hasn't been written yet. If the app is force-quit in that window, the next launch reads the slightly older cached snapshot — re-derived on the next refresh, no user-visible impact.
- Reuse: For `@MainActor` view-models that have day-by-day baseline recomputes or JSON-on-disk caches firing inside refresh paths, lift them into `Task.detached` (`.userInitiated` for compute, `.utility` for I/O). Pass value-typed snapshots into the detached closure to avoid main-actor hops inside. Skip the recompute at init if the cached value was correct when written and the next refresh will refresh it anyway.

### 2026-05-18 - Prefer HKStatisticsCollectionQuery over HKSampleQuery for daily-aggregated trends
- Context: Dashboard refresh ran ~30 daily trend queries in parallel and took 15–20 s. `fetchDailyQuantitySeries` and `fetchDailyQuantityRangeSeries` issued `HKSampleQuery(limit: HKObjectQueryNoLimit)` over a 365-day window and grouped results in-app.
- Symptom: For heart rate alone, ~50,000 raw samples per refresh crossed the HK IPC boundary just to compute 365 daily averages.
- Cause: HK only aggregates server-side via `HKStatisticsCollectionQuery`; raw `HKSampleQuery` ships every sample to the app.
- Fix: Replace daily-series and range-series fetches with `HKStatisticsCollectionQuery` using `.discreteAverage` / `.mostRecent` (single-stat) or `[.discreteAverage, .discreteMin, .discreteMax]` (paired). Source filtering still works via the same predicate.
- Reuse: When a HealthKit trend aggregates one or a few stats per day (mean, min, max, sum, latest), use `HKStatisticsCollectionQuery` with daily `intervalComponents` and skip the raw-samples-into-app round-trip. Note that `valueTransform` is now applied to the aggregate, not per-sample — only safe for linear transforms. Non-linear transforms must stay on the sample-based path.

### 2026-05-18 - Lazy-load intraday HK day samples only when the detail view appears
- Context: Dashboard refresh fetched intraday `heart rate / RHR / HRV / respiratory rate / SpO2` sample series (`fetchQuantitySampleSeries` with `HKObjectQueryNoLimit` over 365 days) even though Home never renders them — they only feed the metric detail view's hourly chart.
- Symptom: Apple Watch users paid ~50k HR sample reads per launch refresh for data the Home view never displays.
- Cause: `fetchHealthTrends` unconditionally populated `*DaySamples*` fields on every dashboard refresh.
- Fix: Strip the `*DaySamples` fetches from `fetchHealthTrends`. Add `HealthKitWorkoutStore.loadIntradayMetricSamplesIfNeeded(_:)` and call it from `BodyHealthMetricDetailView.task`. The detail view reads `daySeries` directly from the live `workoutStore.healthTrends` (with the captured `model.daySeries` as a fallback for the first frame) so the `@Published` change re-renders when the lazy load finishes.
- Preserve across refreshes: `fetchHealthTrends` now captures the existing `*DaySamples` fields at the top and threads them through the new `HealthTrendSnapshot`. A later background refresh won't blank a chart that was just lazy-loaded.
- Reuse: For any HK data that is large *and* gated behind a navigation step (detail view, sheet), keep it out of the dashboard refresh path and load it from the consuming view's `.task`. Preserve previously-loaded values across refreshes by reading the live store value when assembling the new snapshot.

### 2026-05-18 - Save-if-changed for snapshot caches, gate widget reloads on the bytes diff
- Context: Every successful refresh re-wrote `WorkoutSnapshotStore` and `HealthDashboardSnapshotStore` and called `WidgetCenter.shared.reloadAllTimelines()` regardless of whether the encoded snapshot had changed.
- Symptom: Wasted ~100 KB atomic disk writes plus widget reloads on every resume.
- Cause: `save(_:)` unconditionally wrote the encoded bytes.
- Fix: `save(_:)` now encodes once, compares against the existing on-disk bytes, and returns `Bool` indicating whether the write actually happened. `updateCurrentMonthSnapshot` gates `WidgetCenter.shared.reloadAllTimelines()` on the returned flag.
- Reuse: For JSON-on-disk caches that are rewritten by background sync paths, compare encoded bytes before `write(to:options:[.atomic])` and propagate a `Bool` to callers that drive expensive downstream side effects (widget reloads, push registrations).

### 2026-05-18 - Tier the scenePhase resume refresh by elapsed time
- Context: `syncWhenAppBecomesActive` debounced by 60 s, but every active transition past 60 s ran the full dashboard refresh (workouts + all metrics + ring history).
- Symptom: Resuming the app 90 s after backgrounding re-fetched a year of trend data the user almost certainly hadn't changed.
- Cause: One-tier debounce — under 60 s skip, over 60 s full refresh.
- Fix: Tier the path: <60 s skip, 60 s–5 min run `refreshWorkoutMonth(currentMonth, currentYear)` only (workouts are user-visible and cheap), ≥5 min run the full path. Tunable via `Self.shortResumeDebounceInterval` (60) and `Self.dashboardFreshnessInterval` (300).
- Reuse: For HK-backed apps where the user's resume cadence is irregular, prefer a tiered debounce over a single threshold — short resumes can refresh only the cheapest user-visible surface.

### 2026-05-18 - Replace `while isRefreshing { sleep(100ms) }` with continuation-based completion
- Context: Several call sites (`awaitRefreshCompletion`, `loadMonthIfNeeded`, `loadPreviousActivityRingMonthIfNeeded`, `updateSecondaryHealthDataSource`) busy-waited on `isRefreshing` by sleeping 100 ms in a loop. `docs/IssuesArchive-04.md` N10 flagged a theoretical hang if `isRefreshing` never flipped false.
- Symptom: Polling latency on every cross-task wait; risk of an indefinite loop on a stuck HealthKit query.
- Cause: No completion signal — only the `@Published` flag.
- Fix: `HealthKitWorkoutStore` keeps a `refreshCompletionContinuations: [CheckedContinuation<Void, Never>]`. Refresh `defer` blocks call `finishRefresh()` which flips `isRefreshing = false` *and* resumes all waiters. Waiters use `awaitNextRefreshCompletion()` instead of the polling loop.
- Reuse: When code awaits a state change on a `@MainActor` observable, accumulate `CheckedContinuation`s in a list and resume them all in the producer's `defer` — cleaner and avoids the busy-wait/stall trade-off.

### 2026-05-24 - Add headroom for normalized dual-axis Swift Charts
- Context: Basics weight/body-fat detail chart needed to match the source-comparison legend-to-plot spacing after right-aligning its legend.
- Symptom: The Basics legend looked horizontally correct, but the top y-axis labels and gridline started immediately below the legend while Sleep/source charts had a larger header band gap.
- Cause: `BodyBasicsTrendChart` normalized both axes to `0...1` and also drew ticks at `1.0`, pinning the top visible axis row to the plot edge.
- Fix: Keep the displayed tick values at `0.0...1.0`, but set the chart scale to `0.0...1.1` so the top tick sits below the legend band. Source-shape tests that inspect a large SwiftUI view need a slice long enough to include both declarations and chained modifiers.
- Reuse: For normalized Swift Charts with explicit edge ticks, add domain headroom instead of padding the whole card when the issue is the first visible grid/axis row crowding the header.

### 2026-05-24 - Run `git mv` operations sequentially
- Context: Renaming the Readiness model directory, Swift files, and docs in one refactor.
- Symptom: Parallel `git mv` calls intermittently failed with `.git/index.lock` already existing.
- Cause: Each `git mv` updates the Git index; concurrent Git index writes collide even when the file moves are independent.
- Fix: Let the completed moves stand, wait for the transient lock to disappear, then retry remaining `git mv` commands sequentially.
- Reuse: For multi-file renames in this repo, parallelize content reads/searches, but run Git index-mutating commands one at a time.

### 2026-05-24 - Await actor values before XCTest autoclosure assertions
- Context: Adding async `HealthKitFetchEngine` helper tests with an actor probe for concurrency limits.
- Symptom: `XCTAssertLessThanOrEqual(await probe.maximumActiveCount(), 1)` failed to compile with `'await' in an autoclosure that does not support concurrency`.
- Cause: XCTest assertion arguments are autoclosures, and actor-isolated calls cannot be awaited inside those synchronous autoclosures.
- Fix: Await the actor method into a local first, then pass the local to the assertion.
- Reuse: In async XCTest methods, avoid `await` directly inside `XCTAssert*` arguments when the awaited expression is actor-isolated.

## Archive

Older entries (2026-05-10 through 2026-05-15) have been moved to [`docs/LessonsLearnedArchive.md`](docs/LessonsLearnedArchive.md) to keep this file scannable. Topics archived so far include: HealthKit cumulative-energy aggregation, `HKActivitySummary` calendar requirements, `HKWorkoutActivityType` test unwrapping, async authorization status API, Activity Rings pagination/synthesis rules, sleep-day bucketing and partial-minute formatting, Swift Charts axis/value gotchas, `LazyVGrid` span limitations, app-group `UserDefaults` guards, computed-property/`some View` return-statement rules, simulator/CoreSimulator/DerivedData build workarounds, and the chart-source-shape configuration tests.

**Before a large or risky edit** (refactoring `HealthKitWorkoutStore` / `HealthKitFetchEngine`, touching activity-ring pagination or sleep aggregation, restructuring SwiftUI chart code, changing HealthKit authorization or query plumbing, or bumping project build numbers), grep the archive for the area you're touching — those gotchas still apply to the current codebase even though they're not on this page.
