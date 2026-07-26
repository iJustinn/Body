# Body iOS Project Review

**Review date:** July 12, 2026  
**Branch:** body-0.9.8  
**Reviewed commit:** 18575ed  
**Method:** Whole-project static review of the iOS app, widget extension, watch app, watch widget, shared model packages, project configuration, persistence formats, and test targets.

## Executive Summary

The project has a thoughtful core: UI-owned observable state is generally main-actor isolated, HealthKit work is moved into an actor, snapshot writes are atomic, widget placeholder handling is honest, source and permission controls are extensive, and the pure scoring/aggregation layer has substantial tests. No production force unwraps, forced casts, fatal errors, obvious credential leaks, or health-value logging were found.

The remaining risks are concentrated at asynchronous boundaries. HealthKit callbacks frequently do not distinguish a failed query from a successful query with no samples; source-selection state can change while an actor is suspended; deletion is not ordered with queued persistence writes; and several cross-device freshness decisions use insufficient provenance. Those weaknesses can turn a transient HealthKit or timing failure into persisted blank data, mixed-source data, stale Watch data, or a cache that reappears after the user cleared it.

This review found:

- 1 Critical issue
- 12 High-severity issues
- 20 Medium-severity issues
- 15 Low-severity issues
- 5 Suggestions

CodeGraph was attempted first because the repository is indexed, but its database returned “database disk image is malformed” on the initial call and the required retry. The review therefore used direct source inspection and repository-wide searches. No build or test run was performed because this was a read-only audit; runtime-only behaviors called out below remain explicit verification items.

## Fix Round Outcome (2026-07-13)

A verified bug-fix round (branch `body-0.9.8`, five subagent waves) addressed the approved clear-wins + cheap-hardening batch. Of the 58 findings below, **31 were fixed** (several partial) and **27 were skipped or deferred** (by design, refuted, latent, or architecture-level). By severity:

- **Critical:** 1 / 1 fixed — C1.
- **High:** 11 / 12 fixed — all but H5 (FetchContext architecture, deferred).
- **Medium:** 9 / 20 fixed — M2, M3, M5, M7, M10, M15, M16, M19, M20 (partial); the rest are by-design (M8, M9), invisible/latent (M11, M12), bounded (M13, M14), perf-measure-first (M17, M18), or deferred (M1, M4, M6).
- **Low:** 10 / 15 fixed — L1, L2 (partial), L4, L6, L7, L10, L12, L13, L14, L15; L3 (perf), L5 (by design), L8, L9, and L11 deferred.
- **Architectural (A1–A5) and Suggestions (S1–S5):** deferred; A1/A3/A5 are partially realized via the typed `QueryOutcome` failure boundary, versioned sidecar/watch signatures, and the new behavioral tests.

Each finding below carries an **Outcome (2026-07-13)** line under its heading noting what was done (with key files) or why it was skipped.

## Fix Round 2 (2026-07-14)

Codex (GPT-5-family, read-only) re-audited the round-1 fixes and found ten "Fixed" outcomes above were actually partial, each with a concrete remaining gap: H2 (cold-start-only summary signature, sleep-vital `.valueOr([])` masking, and no failure flag on trends/ring history), H4 (the UI source picker still collapsed a stored selection to All Sources when discovery hadn't populated yet), H6 (source/combine setters never cleared stale-source day samples, and the sidecar signature omitted the combine flag), H7 (Clear Cache never reached the Watch), H8 (only `CancellationError` was rethrown from route/split/`fetchWorkout` reads; every other error still got negative-cached), H12 (a failed-and-uncached effort read still fabricated a default-5 training load), M5 (the wall-clock admission gate ran before revision assignment), M15 (no cancellation handler on the underlying HK queries), L7 (the Activity Rings completion star wasn't Reduce-Motion gated), and L15 (readiness still read the wall clock internally in four places). All ten gaps were verified against source, fixed, and are now genuinely Fixed — see each finding's **Round 2 (2026-07-14)** note below. H5's Outcome line also carried a false justification (claiming the settings paths already awaited the in-flight refresh before mutating selection); that has been corrected in place. H5 itself remains deferred, though H6a's day-sample stripping now closes the persistence side of that risk. iOS (681 tests) and watch (30 tests) suites pass.

## Fix Round 3 (2026-07-14)

A round-3 re-audit (Codex, GPT-5-family, read-only) checked the round-2 "Fixed" outcomes against source once more and found four residual gaps: H4/H2 (the engine-side `resolvedHealthDataSourceOption`/`resolvedSecondaryHealthDataSourceOption` resolvers in `HealthKitFetchEngine.swift` still collapsed an unresolved discovery to an all-sources/no-comparison fallback instead of keeping the stored selection, unlike the store-side resolvers and `sourceQueryResolution`'s tri-state that round 2 fixed), H8 (`readWorkoutStepSamples` still swallowed step-cadence read errors, including cancellation, into `[]` and got cached as confirmed data — the one split/route catch round 2 missed), H12 (the HR-reuse branch in `fetchWorkoutSummaries` used `??` fallbacks onto cached VO₂max/cadence, so a successful query confirming absence could never clear a stale reused value), and M15 (`CancellableQueryCoordinator.install` unlocked before calling `healthStore.execute`, so a cancel landing in that window stopped a no-op and let install execute the query anyway, leaking the HK work round 2 meant to close off). Each gap was verified against source, the fix was adversarially reviewed by Codex before being applied, and all four are now genuinely fixed — see each finding's **Round 3 (2026-07-14)** note below.

## Architectural Concerns

### A1. HealthKit is not injectable at the failure boundary

**Outcome (2026-07-13): Partially realized / deferred.** A narrow typed outcome (`QueryOutcome`) was introduced at the failure boundary (H2–H4, H12), but full HealthKit injection is out of scope this round.

**Evidence:** [HealthKitFetchEngine.swift:21](Body/Services/HealthKitFetchEngine.swift#L21) constructs its own HKHealthStore. Query construction, callback interpretation, caching, source selection, and result assembly are consequently coupled to the concrete framework.

**Why it matters:** The highest-risk paths in this report—failure versus empty, cancellation, partial fan-out, source changes during suspension, and stale-result rejection—cannot be tested deterministically. Most existing tests exercise static post-processing or inspect source text rather than the live state machine.

**Recommendation:** Inject a narrow asynchronous query client, not the entire HealthKit API. It should return typed outcomes such as success(value), permissionDisabled, noData, cancelled, and failure(error). Keep HKSample conversion in a production adapter and business rules in pure code.

### A2. Refreshes are publications, not transactions

**Outcome (2026-07-13): Deferred.** The immutable FetchContext/generation model is deferred (see H5); the concrete settings paths await in-flight refreshes as an interim guard.

**Evidence:** HealthKitFetchEngine is reentrant across HealthKit suspension points; HealthKitWorkoutStore progressively publishes summaries and later persists snapshots; source/permission settings mutate independently; and no refresh generation is checked before publication. Representative paths are [HealthKitWorkoutStore.swift:1208](Body/Services/HealthKitWorkoutStore.swift#L1208), [HealthKitWorkoutStore.swift:1985](Body/Services/HealthKitWorkoutStore.swift#L1985), and [HealthKitWorkoutStore.swift:2090](Body/Services/HealthKitWorkoutStore.swift#L2090).

**Why it matters:** A result may have been fetched under more than one source configuration, or may be obsolete by the time it commits. The current isRefreshing gate prevents some duplicate work but does not make the inputs immutable.

**Recommendation:** Capture an immutable FetchContext at refresh start—generation, permissions, primary/secondary source signatures, source-grouping flag, entitlement state, calendar/time zone, and anchor date. Reject every result whose generation is no longer current.

### A3. Persistence provenance is fragmented

**Outcome (2026-07-13): Partially realized / deferred.** Persisted envelopes gained schema versions and source/permission signatures (H6) and the watch snapshot gained a publisher epoch + monotonic revision (M5); a uniform versioned envelope across every store remains deferred.

**Evidence:** Dashboard data, an intraday sidecar, current/previous workout widget files, WatchConnectivity application context, and an on-watch App Group file each carry different freshness metadata. The day-sample sidecar has no source signature, Watch data orders primarily by Date, and a cache reset has no end-to-end tombstone.

**Why it matters:** “Newest,” “non-empty,” and “same file size” are being used as proxies for authoritative data. That is insufficient when the user changes sources, clears data, the clock changes, or processes write concurrently.

**Recommendation:** Version persisted envelopes and carry a monotonic revision, source/permission context, schema version, and explicit reset/no-data state through every companion snapshot.

### A4. Several feature files have become integration hubs

**Outcome (2026-07-13): Deferred.** No large-file extraction was undertaken; changes were kept surgical within the existing hubs.

**Evidence:** BodySettingsView.swift and HealthKitWorkoutStore.swift are each over 3,000 lines; HealthKitFetchEngine.swift, BodyWorkoutsView.swift, BodyHealthMetricDetailView.swift, and BodyHomeView.swift are each roughly 2,300–2,600 lines.

**Why it matters:** Views co-locate navigation, gestures, persistence bindings, expensive presentation transforms, and asynchronous lifecycle tasks. The store combines permissions, refresh orchestration, persistence, prediction, widget/watch publication, and cache policy. The cancellation, timeout, settings, and per-render performance issues below are direct symptoms.

**Recommendation:** Extract testable feature state machines: month browsing, workout-detail loading, settings drafts, trend presentation, companion publication, and persistence ownership. Keep the app-level store as an orchestrator rather than the implementation site for every concern.

### A5. Configuration coverage relies too heavily on source-shape assertions

**Outcome (2026-07-13): Partially realized.** Behavioral unit tests (failure semantics, sleep sessionization, cache hygiene, watch freshness, readiness coverage, save dedupe) and a per-target built-product privacy-manifest table were added; broader StoreKitTest / widget-timeline harnesses remain future work.

**Evidence:** [ProjectConfigurationTests.swift](BodyTests/ProjectConfigurationTests.swift) contains many checks that search source or project text. These catch accidental deletion, but they cannot prove timeout behavior, task cancellation, state ordering, target resource inclusion in the built product, or StoreKit/Watch state transitions.

**Recommendation:** Retain a small set of project-file invariants, then move behavioral expectations to injected unit tests, StoreKitTest, widget timeline tests, and a built-product privacy-manifest inspection.

## Critical

### C1. Required-reason privacy manifests are missing or incomplete

**Outcome (2026-07-13): Fixed.** Added FileTimestamp `C617.1` to the iOS widget manifest and new `PrivacyInfo.xcprivacy` files for the watch app (UserDefaults `CA92.1` + FileTimestamp `C617.1`) and watch widget (FileTimestamp `C617.1` only); `ProjectConfigurationTests.testPrivacyManifestsDeclareUserDefaultsAndNoTracking` now asserts a per-target category matrix, verified in the built products.

**Confirmed from code.**

**What:** The iOS widget manifest declares UserDefaults only at [BodyWidgetExtension/PrivacyInfo.xcprivacy:5](BodyWidgetExtension/PrivacyInfo.xcprivacy#L5), while shared code compiled into that executable reads file metadata at [HealthWidgetSnapshotStore.swift:124](BodyShared/Services/HealthWidgetSnapshotStore.swift#L124) and [WorkoutSnapshotStore.swift:133](BodyShared/Services/WorkoutSnapshotStore.swift#L133). BodyWatch has no PrivacyInfo.xcprivacy despite UserDefaults usage at [WatchMetricsModel.swift:82](BodyWatch/WatchMetricsModel.swift#L82) and file metadata usage at [WatchMetricsSnapshotStore.swift:119](BodyWatchShared/Services/WatchMetricsSnapshotStore.swift#L119). BodyWatchWidgetExtension also compiles that shared file-metadata code but has no manifest.

**Risk:** Apple states that each bundle containing an executable that uses a required-reason API must contain a privacy manifest describing it, and App Store Connect does not accept apps that omit required reasons. This is a release-blocking submission risk, not merely documentation debt. See [Apple: Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) and [Apple: File timestamp required reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

**Breadth:** iOS widget, watch app, and watch complication bundles. [ProjectConfigurationTests.swift:1293](BodyTests/ProjectConfigurationTests.swift#L1293) checks only the app and iOS widget and checks only UserDefaults, so CI cannot detect the two missing watch manifests or the widget’s missing FileTimestamp category.

**Fix:**

- Add FileTimestamp reason C617.1 to BodyWidgetExtension/PrivacyInfo.xcprivacy.
- Add BodyWatch/PrivacyInfo.xcprivacy with UserDefaults reason CA92.1 and FileTimestamp reason C617.1.
- Add BodyWatchWidgetExtension/PrivacyInfo.xcprivacy with FileTimestamp reason C617.1. Add UserDefaults too if final target membership includes a direct/defaults-using file.
- Replace the current loop with target-specific expected categories, and inspect built products so target membership is verified rather than inferred from source paths.

## High

### H1. Sleep stages are split into separate “nights” at midnight

**Outcome (2026-07-13): Fixed.** New `BodyWatchSnapshotKit/BodySleepSessionizer.swift` stitches samples into sessions (2 h max gap) and attributes each to its wake day; `HealthKitFetchEngine+Sleep.swift` groups by wake-day session and derives overnight vitals from the main session's window only. Covered by `BodyTests/BodySleepSessionizerTests.swift`.

**Confirmed from code; device data is needed only to quantify prevalence.**

**What:** Both current sleep and historical sleep group every HKCategorySample by calendar.startOfDay(sample.endDate) at [HealthKitFetchEngine+Sleep.swift:31](Body/Services/HealthKitFetchEngine+Sleep.swift#L31) and [HealthKitFetchEngine+Sleep.swift:103](Body/Services/HealthKitFetchEngine+Sleep.swift#L103). A Core segment ending at 23:50 and Deep/REM segments after midnight become different nights. The current summary selects only the latest bucket, and its vitals window at [HealthKitFetchEngine+Sleep.swift:63](Body/Services/HealthKitFetchEngine+Sleep.swift#L63) is derived from that truncated bucket.

**Risk:** Pre-midnight sleep and vitals disappear from the selected night. Duration, stage percentages, sleep score, consistency, overnight-vitals baselines, readiness, widgets, and Watch snapshots can all be wrong.

**Breadth:** Every overnight session containing a stage segment that ends before midnight, especially nonstandard sleep schedules or source-generated short stages.

**Fix:** Sessionize chronological samples first, using a documented maximum gap, normalize the complete session, and assign the session to its wake day. Put the rule in BodySleepSampleParser so current summary, history, widget, and Watch paths share it.

    let sessions = SleepSessionizer.sessions(from: samples, maximumGap: 2 * 60 * 60)
    let days = Dictionary(grouping: sessions) {
        calendar.startOfDay(for: $0.endDate)
    }

Add a raw-sample test spanning midnight and assert a single SleepDaySummary with the union interval and all stage durations.

### H2. Transient HealthKit errors are interpreted as real empty data and persisted

**Outcome (2026-07-13): Fixed.** Introduced `QueryOutcome` so a failed query keeps the cached value (resolved only against a cache captured under the same primary + permission signature) and skips the freshness-TTL advance, while a confirmed-empty / permission-off result still clears the tile; applied across every summary leaf in `HealthKitFetchEngine.swift`. Covered by `BodyTests/HealthKitFetchEngineFailureSemanticsTests.swift`. **Round 2 (2026-07-14): Fixed.** Closed three remaining gaps: the primary-summary signature is now persisted inside the dashboard snapshot itself (extended to also cover the two sleep-stage display prefs and the combine flag) so a cold-start failure can reuse the prior snapshot instead of discarding it; sleep-history vitals now merge per-vital against the cached night (matched by wake day) instead of `valueOr([])` blanking a vital on failure; and a new `hadQueryFailure` flag now also covers secondary trends, secondary range trends, sleep-vital failures, and activity-ring history/backfill (not just the summary), so any failed leaf withholds the freshness-TTL advance and the next resume retries. **Round 3 (2026-07-14): Fixed.** The round-3 re-audit found the ENGINE's own `resolvedHealthDataSourceOption`/`resolvedSecondaryHealthDataSourceOption` (`HealthKitFetchEngine.swift`) still collapsed an *unresolved* discovery (no successful source discovery this process — `healthSourcesByKind[kind] == nil`) to `.allSources`/`.noComparison`, unlike `sourceQueryResolution`'s tri-state and unlike the store-side resolvers fixed in round 2 (see H4). For a stored secondary selection, that meant every secondary fetcher returned the intentional `.empty` that clears the cached secondary series instead of `nil` (keep cache + `hadQueryFailure` + freshness-TTL withheld); the unresolved-primary collapse could also wrongly turn an `.allSources` secondary into `.noComparison` via the identity comparison in `selectedSecondaryHealthDataSourceOption`. Both resolvers now delegate the discovery decision to a new pure `resolvedSourceOption(_:discoveredNonemptyIDs:absentFallback:)` helper (nil = unresolved → keep stored option so leaf queries skip via `sourceSelectionUnresolved`; discovered-but-absent → fallback). Covered by new truth-table tests plus an actor-path test in `BodyTests/HealthKitFetchEngineFailureSemanticsTests.swift`.

**Confirmed from code; locked-device/XPC reproduction should be verified on a device.**

**What:** Representative callbacks ignore error and convert missing samples to nil/empty: latestQuantity at [HealthKitFetchEngine.swift:1039](Body/Services/HealthKitFetchEngine.swift#L1039), current sleep at [HealthKitFetchEngine+Sleep.swift:31](Body/Services/HealthKitFetchEngine+Sleep.swift#L31), sleep vitals at [HealthKitFetchEngine+Sleep.swift:266](Body/Services/HealthKitFetchEngine+Sleep.swift#L266), and activity rings at [HealthKitFetchEngine+ActivityRings.swift:23](Body/Services/HealthKitFetchEngine+ActivityRings.swift#L23). fetchHealthSummary substitutes empty models at [HealthKitFetchEngine.swift:1745](Body/Services/HealthKitFetchEngine.swift#L1745). The store publishes the summary at [HealthKitWorkoutStore.swift:2136](Body/Services/HealthKitWorkoutStore.swift#L2136) and can persist it before all concurrent work has resolved.

**Risk:** A locked-device, HealthKit XPC, or partial query failure can blank cards, sleep, rings, and readiness inputs; the blank state is then saved and sent to widgets/Watch as a “successful” refresh. A later workout error does not undo the already published dashboard.

**Breadth:** Current summary, ranges, secondary data, sleep vitals, activity rings, companion snapshots, and readiness.

**Fix:** Use one typed result across the HealthKit boundary. Preserve cached data only on failure/cancellation; clear it only on a successful zero-sample result or explicit permission-off.

    enum HealthFetch<Value> {
        case success(Value)       // Value may legitimately be empty
        case permissionDisabled
        case cancelled
        case failure(Error)
    }

Resolve every field against the prior snapshot, then publish and persist one transaction. Add paired tests for “query failed” and “query succeeded with zero samples” for every query shape.

### H3. Failed intraday queries delete valid cached samples

**Outcome (2026-07-13): Fixed.** Intraday series fetches now return nil + log on a query error and merge only on success (a successful-empty result still replaces); the store keeps the cached series on failure. Files: `HealthKitFetchEngine.swift`, `+IntradaySamples.swift`, `+Secondary.swift`, `HealthKitWorkoutStore.swift`.

**Confirmed from code.**

**What:** fetchQuantitySampleSeries ignores query error and returns an empty series at [HealthKitFetchEngine.swift:1078](Body/Services/HealthKitFetchEngine.swift#L1078). mergeIntradaySamples treats that empty series as authoritative and removes cached samples from the overlap window at [HealthKitFetchEngine+IntradaySamples.swift:118](Body/Services/HealthKitFetchEngine+IntradaySamples.swift#L118). Active-energy and step series replace the entire cached window at [HealthKitWorkoutStore.swift:1014](Body/Services/HealthKitWorkoutStore.swift#L1014).

**Risk:** Opening or refreshing a detail while HealthKit fails can erase the last 48 hours of HR/HRV/SpO₂ samples or the full hourly energy/step series. The damage can be persisted to the day-sample sidecar.

**Breadth:** Every lazily loaded intraday chart, including primary and comparison series.

**Fix:** Make the raw query throwing/result-typed and merge only success. A successful empty result may replace the overlap; failure must return the original series unchanged.

### H4. Failed source discovery silently falls back to all sources for the session

**Outcome (2026-07-13): Fixed.** Tri-state source resolution — a specific selection with no successful discovery this process is `.unresolved` (query skipped, cache kept) instead of an all-sources fallback; discovery merges per kind and the permission signature is recorded only on a fully successful discovery so failed kinds retry. Files: `HealthKitFetchEngine+SourceOptions.swift`, `HealthKitFetchEngine.swift`. **Round 2 (2026-07-14): Fixed.** The UI-facing source picker read a separate map from the query resolution above: `resolvedHealthDataSourceOption`/`resolvedSecondaryHealthDataSourceOption` in `HealthKitWorkoutStore.swift` collapsed a stored individual selection to All Sources / No Comparison whenever `healthDataSourceOptionsByKind` hadn't been populated yet (cold start, or mid-clear). They now keep the stored selection while discovery is unresolved and only fall back once the option is confirmed absent from a completed discovery. **Round 3 (2026-07-14): Fixed.** Same gap, one layer down: `resolvedHealthDataSourceOption`/`resolvedSecondaryHealthDataSourceOption` in `HealthKitFetchEngine.swift` — the ENGINE's own resolvers, distinct from the store-side ones round 2 fixed — still collapsed an unresolved discovery (`healthSourcesByKind[kind] == nil`, no successful discovery this process) to `.allSources`/`.noComparison` instead of keeping the stored selection (see H2 for the secondary-comparison fallout this also produced). Both resolvers now delegate to a new pure `resolvedSourceOption(_:discoveredNonemptyIDs:absentFallback:)` helper: nil discovery keeps the stored option (leaf queries skip via `sourceSelectionUnresolved`), discovered-but-absent falls back as before. Covered by new truth-table tests plus an actor-path test in `BodyTests/HealthKitFetchEngineFailureSemanticsTests.swift`.

**Confirmed from code; the HealthKit failure itself should be reproduced on device.**

**What:** HKSourceQuery ignores error and maps nil to an empty source list at [HealthKitFetchEngine+SourceOptions.swift:213](Body/Services/HealthKitFetchEngine+SourceOptions.swift#L213). fetchHealthDataSourceOptions then caches empty per-kind maps and records the current permission signature at [HealthKitFetchEngine+SourceOptions.swift:15](Body/Services/HealthKitFetchEngine+SourceOptions.swift#L15). sourcePredicate returns nil when the selected source cannot be found at [HealthKitFetchEngine.swift:322](Body/Services/HealthKitFetchEngine.swift#L322); nil means no source predicate, or all sources.

**Risk:** Source-picker choices disappear and a user-selected device silently becomes an all-source aggregate. Metrics and readiness may change without an obvious error, and the bad discovery result is cached for the remainder of the session.

**Breadth:** All source-selectable metrics.

**Fix:** Return a failure outcome from each HKSourceQuery. Do not advance fetchedHealthDataSourcePermissionRawValue when any required discovery query fails. Preserve successful maps per kind and retry only failed kinds. A missing selected source should be an explicit unresolved state, never equivalent to allSources.

### H5. Source settings can change during a suspended refresh, producing a mixed-source snapshot

**Outcome (2026-07-13): Deferred.** The full FetchContext/generation architecture is out of scope; the signature-scoped cache reuse from H2/H6 covers the persisted-blank risk. **Round 2 (2026-07-14): Justification corrected, still deferred.** The prior claim that the concrete settings paths already await the in-flight refresh was wrong: `updateDefaultHealthDataSource`/`updateCombinesHealthDataSourcesByName`/`updateDefaultSecondaryHealthDataSource` mutate the store and engine selection BEFORE calling `awaitNextRefreshCompletion()`, and there is no refresh-generation guard, so an in-flight refresh reading engine state live can still publish and persist a mixed-source snapshot during that window — a real, if transient, risk. Round 2 closes the persistence side: after the awaited refresh, each setter now strips the affected day-sample series and persists the stripped sidecar before the corrective refetch (H6a), so a mixed-source snapshot can no longer survive on disk. The full FetchContext/generation architecture that would close the remaining in-memory publish race stays deferred; reordering the mutation to after the await was deliberately not done because it would lag the source picker UI for the length of the in-flight refresh.

**Confirmed actor-reentrancy path; timing should be exercised with an injected delayed query.**

**What:** HealthKitFetchEngine stores mutable source selections at [HealthKitFetchEngine.swift:24](Body/Services/HealthKitFetchEngine.swift#L24). Settings mutate store and engine selection at [HealthKitWorkoutStore.swift:1208](Body/Services/HealthKitWorkoutStore.swift#L1208) while an existing refresh may be suspended in HealthKit. Because actors are reentrant, early predicates can use the old selection and later predicates the new selection. The old refresh can still publish.

**Risk:** One dashboard can mix devices or combine policies. The corrective refresh is not a safety guarantee: its task can be cancelled or fail after the mixed snapshot has already been saved.

**Breadth:** Summary, trends, secondary comparisons, readiness inputs, widgets, and Watch.

**Fix:** Capture a FetchContext and generation at refresh start; every leaf query receives that immutable context, and the store discards stale generations before any publication.

    let context = await engine.makeFetchContext()
    let result = await engine.fetchDashboard(context: context)
    guard context.generation == refreshGeneration else { return }

### H6. Persisted intraday samples are not scoped to the selected sources

**Outcome (2026-07-13): Fixed.** `HealthTrendDaySampleSnapshot` gained a schema version plus primary/secondary/permission signatures; hydration only merges signature-matching, permission-filtered day samples, with a legacy-secondary-signature fallback and a one-time drop of legacy primary-scoped series. Files: `BodyMetricsKit/HealthTrend.swift`, `Body/Models/BodyAppearancePreference.swift`, `HealthKitWorkoutStore.swift`; tests in `HealthDashboardDaySamplesTests.swift`. **Round 2 (2026-07-14): Fixed.** The source/combine setters now clear the affected day-sample series (scoped per-kind for a single metric's source change, primary+secondary for the default-source/combine setters) after the awaited in-flight refresh and persist the stripped sidecar immediately — closing the gap where a full trend refresh re-emitted cached old-source samples verbatim and no setter cleared them, so they got saved under a freshly-stamped new-source signature. The sidecar schema is now version 2 and its primary/secondary signatures include `combinesHealthDataSourcesByName`; acceptance gates on `schemaVersion == 2` exactly, so v1 and any unrecognized future schema fail closed and the legacy day-sample cache is dropped once.

**Confirmed from code.**

**What:** HealthTrendDaySampleSnapshot carries only series data at [HealthTrend.swift:934](BodyMetricsKit/HealthTrend.swift#L934). On launch a changed secondary signature clears the dashboard series, but hydration at [HealthKitWorkoutStore.swift:903](Body/Services/HealthKitWorkoutStore.swift#L903) immediately merges empty fields from the old sidecar. Full trend refresh deliberately preserves cached day samples at [HealthKitFetchEngine.swift:1884](Body/Services/HealthKitFetchEngine.swift#L1884). Primary-source changes have no persisted signature at all.

**Risk:** Charts can show the wrong device or a mixture of old-source and new-source samples across launches. Comparison charts can claim to compare two sources while one side contains data from a previous selection.

**Breadth:** HR, resting HR, HRV, respiratory rate, SpO₂, active energy, steps, and every primary/secondary intraday path.

**Fix:** Persist a versioned envelope containing primary and secondary selection signatures, combines-sources-by-name, permission signature, and samples. Clear/refetch only affected series when context changes, and add a generation check after every await in lazy loading.

### H7. “Clear Cache” can be undone by queued or in-flight work

**Outcome (2026-07-13): Fixed.** `clearLocalCache` is now async and ordered after pending writes; a MainActor `cacheEpoch` counter guards every resurrection-capable path and the Clear Cache button is disabled while refreshing. Known benign residual: a refresh that starts during the clear's sub-second awaits can write FRESH (not stale) data. Files: `HealthKitWorkoutStore.swift`, `BodySettingsView.swift`; tests `StoreCacheHygieneTests.swift`. **Round 2 (2026-07-14): Fixed.** Clear Cache never reached the Watch — `publishWatchSnapshot` had no epoch check, and the watch's blank-preserve merge kept every prior metric on a blank push, so even a same-process reset publish would neither be reliably ordered nor visibly clear anything. `publishWatchSnapshot` is now epoch-gated against `cacheEpoch`; Clear Cache separately sends a data-free `WatchMetricsSnapshot` with a new `isReset: true` flag directly (bypassing the epoch-gated path); the watch adopts (not merges) a reset that supersedes its current snapshot and persists it as a tombstone via `WatchMetricsSnapshotStore.save` — never deleting the file — so a delayed lower-revision push after a watch process restart can't resurrect the cleared data.

**Confirmed from code.**

**What:** clearLocalCache deletes files synchronously outside the persistence queue at [HealthKitWorkoutStore.swift:1873](Body/Services/HealthKitWorkoutStore.swift#L1873), while dashboard and workout saves are enqueued asynchronously at [HealthKitWorkoutStore.swift:2415](Body/Services/HealthKitWorkoutStore.swift#L2415) and [HealthKitWorkoutStore.swift:2832](Body/Services/HealthKitWorkoutStore.swift#L2832). Engine cache clearing is fire-and-forget. The Settings action remains enabled during refresh at [BodySettingsView.swift:2501](Body/Views/BodySettingsView.swift#L2501).

**Risk:** The UI reports “Local cache cleared,” then an older queued save recreates the health files or an in-flight refresh republishes them. This violates the user’s privacy expectation and can repopulate widgets.

**Breadth:** Dashboard, day samples, current/previous workout snapshots, widget snapshot, engine source/effort caches, and Watch state.

**Fix:** Make clear async and generation-aware. Cancel or invalidate current refreshes, await engine clears, enqueue deletion on the same persistence owner after prior writes, publish an authoritative companion reset, and do not allow an older generation to save afterward.

    refreshGeneration &+= 1
    await persistence.clearAfterPendingWrites()
    await engine.clearCaches()

Add a test that blocks an older save, invokes clear, releases the queue, and verifies all files remain absent.

### H8. Cancelling workout detail can poison route and split negative caches

**Outcome (2026-07-13): Fixed.** `CancellationError` is rethrown from route/split reads and neither route nor splits are cached on cancel or failure; negative caching applies only to confirmed-absent data. Files: `HealthKitFetchEngine+Route.swift`, `+Splits.swift`, `HealthKitWorkoutStore.swift`. **Round 2 (2026-07-14): Fixed.** Round 1 only rethrew `CancellationError` — every other route/split query error still fell into a `catch { return [] / .empty }` fallback and got negative-cached like a confirmed-absent result, and `fetchWorkout(id:)` discarded its error entirely. All route and split query errors now propagate (the swallowing `catch` blocks were removed) and `fetchWorkout(id:)` is `async throws` and rethrows instead of returning `nil` on error; the store's route/split caches skip caching on any thrown error, so only a genuine empty result gets negative-cached (splits keep the pre-existing >24h-old-workout gate before caching a confirmed-empty result, so a recent, possibly still-syncing workout keeps retrying). **Round 3 (2026-07-14): Fixed.** One swallowing catch remained: `readWorkoutStepSamples` in `HealthKitFetchEngine+Splits.swift` converted any step-cadence read error (including cancellation) to `[]`, which `loadWorkoutSplitData` then cached as confirmed data, silently losing the cadence column for the session. Both step helpers are now `async throws` and errors propagate out of `workoutSplitData`; the store's existing catch returns `.empty` uncached so reopening retries. Documented tradeoff, matching the round-2 distance/route/`fetchWorkout` treatment: a step-read failure now aborts that invocation's whole `WorkoutSplitData` — distance splits hidden once, uncached, self-healing on reopen. Pinned by a source-contract test in `ProjectConfigurationTests.swift` (`testWorkoutStepSamplesPropagateReadFailuresInsteadOfSwallowingErrors`).

**Confirmed from code.**

**What:** BodyWorkoutDetailSheet launches route and split reads in a SwiftUI task at [BodyWorkoutsView.swift:889](Body/Views/BodyWorkoutsView.swift#L889). Dismissal cancels it, but the route descriptor catches every error and returns empty at [HealthKitFetchEngine+Route.swift:21](Body/Services/HealthKitFetchEngine+Route.swift#L21); the store caches nil at [HealthKitWorkoutStore.swift:841](Body/Services/HealthKitWorkoutStore.swift#L841). Splits similarly map cancellation/failure to empty at [HealthKitFetchEngine+Splits.swift:24](Body/Services/HealthKitFetchEngine+Splits.swift#L24) and cache old-workout emptiness at [HealthKitWorkoutStore.swift:863](Body/Services/HealthKitWorkoutStore.swift#L863).

**Risk:** Open a workout and dismiss quickly; reopening can show no route or splits for the rest of the process even though HealthKit has them. The same issue occurs on transient descriptor errors.

**Breadth:** Route workouts and pace/speed workouts, with historical workouts most affected by split negative caching.

**Fix:** Propagate CancellationError and distinguish found, confirmedAbsent, and failed. Cache found or confirmed absence only.

    catch is CancellationError {
        throw CancellationError()
    }

Add delayed-engine tests that cancel the first load and prove reopening performs a second fetch and caches real data.

### H9. The advertised 15-second month-load timeout can still wait indefinitely

**Outcome (2026-07-13): Fixed.** Replaced the `withTaskGroup` race with a token-guarded first-wins latch and one reused in-flight task per month; the overlay always clears at 15 s while the load continues in the background, and a re-tap applies instantly once cached (L14 uniquing dictionary included). File: `Body/Views/BodyWorkoutsView.swift`.

**Confirmed from Swift structured-concurrency semantics.**

**What:** requestMonthYearSelection races load and sleep in withTaskGroup at [BodyWorkoutsView.swift:417](Body/Views/BodyWorkoutsView.swift#L417), takes the first result, then calls cancelAll. A task group cannot leave scope until all children finish. loadMonthIfNeeded waits through non-cancellation-aware checked continuations at [HealthKitWorkoutStore.swift:1608](Body/Services/HealthKitWorkoutStore.swift#L1608), so the cancelled load can keep the group alive and the blocking overlay at [BodyWorkoutsView.swift:123](Body/Views/BodyWorkoutsView.swift#L123) visible indefinitely.

**Risk:** A stalled HealthKit query can trap the Workouts UI in loading despite the stated timeout.

**Breadth:** Any uncached month/year selection.

**Fix:** Put cancellation at the query boundary and separately time out UI ownership. A token/generation can clear pendingMonthSelection at 15 seconds while a shared load finishes or is abandoned; use defer so cancellation always clears UI state. Test with a fake load that intentionally ignores cancellation.

### H10. Watch “live” HR/HRV uses query time instead of measurement time

**Outcome (2026-07-13): Fixed.** Watch readings now carry `measuredAt`; both acceptance and `isStale` use per-kind windows (HR 30 min, HRV 4 h) judged by measurement time. Files: `BodyWatch/WatchHealthStore.swift`, `WatchMetricsModel.swift`; tests `WatchSnapshotFreshnessTests.swift`.

**Confirmed from code.**

**What:** WatchHealthStore accepts a sample up to four hours old and returns only Double at [WatchHealthStore.swift:37](BodyWatch/WatchHealthStore.swift#L37), discarding HKQuantitySample.endDate. WatchMetricsModel stamps liveUpdatedAt = Date() at [WatchMetricsModel.swift:232](BodyWatch/WatchMetricsModel.swift#L232). Merge logic at [WatchMetricsModel.swift:93](BodyWatch/WatchMetricsModel.swift#L93) treats that query timestamp as sample freshness.

**Risk:** A several-hours-old reading is presented as live, suppresses another refresh, and can win over a genuinely newer phone snapshot.

**Breadth:** Watch heart rate and HRV cards/complications, especially off-wrist or sensor-unavailable periods.

**Fix:** Return value plus measuredAt and set liveUpdatedAt to sample.endDate. Apply a much tighter limit to “live” HR than to HRV.

    struct WatchQuantityReading: Sendable {
        let value: Double
        let measuredAt: Date
    }

### H11. Morning readiness can freeze before overnight vitals finish syncing

**Outcome (2026-07-13): Fixed.** Readiness records now carry a `ReadinessCoverage` over eight atomic inputs; within the freeze window a strict-superset on the same day upgrades the record, while the legacy one-shot sleep rule is preserved for coverage-less records. Files: `BodyMetricsKit/HealthSummarySnapshot.swift`, `HealthTrend.swift`; tests `ReadinessRecordCoverageTests.swift`.

**Confirmed from code; real Watch sync timing should be verified on device.**

**What:** RecordedReadinessEntry stores only includedSleep at [HealthTrend.swift:8](BodyMetricsKit/HealthTrend.swift#L8). freezingRecordedReadiness at [HealthSummarySnapshot.swift:692](BodyMetricsKit/HealthSummarySnapshot.swift#L692) permits one upgrade from “no sleep” to “has any sleep,” then makes the record immutable. Sleep duration/stages may arrive before overnight HR/HRV/temperature/SpO₂.

**Risk:** A score frozen at wake + 10 minutes with sleep but incomplete vitals can remain permanently wrong. Later richer recomputation is overridden by the saved record in [HealthTrend.swift:1498](BodyMetricsKit/HealthTrend.swift#L1498).

**Breadth:** Readiness history for users whose Watch health samples sync in phases or whose first morning refresh has a partial failure.

**Fix:** Persist input coverage, not a Boolean. Within a bounded post-wake stabilization window, replace the record when coverage is a strict superset.

    struct RecordedReadinessEntry {
        var date: Date
        var score: Int
        var coverage: ReadinessCoverage
    }

Tests should freeze with duration only, then add HR/HRV, then add other overnight vitals; richer data may upgrade once, while later workout drain must not rewrite the morning record.

### H12. Workout enrichment failures remove valid metrics and can fabricate training load

**Outcome (2026-07-13): Fixed (narrow).** `fetchEffortLevels` distinguishes failed IDs from confirmed-unrated and HR batches reuse cached values on failure, so a default-5 training load is only used for confirmed-unrated or no-prior workouts. Files: `HealthKitFetchEngine.swift`, `HealthKitWorkoutStore.swift`. (The broader per-field FetchContext is deferred with H5.) **Round 2 (2026-07-14): Fixed.** A failed-and-uncached effort read still fell back to `TrainingLoadCalculator`'s default-5, indistinguishable from a genuinely unrated workout. `WorkoutSummary` now carries an `effortUnresolved` flag (failed query + no cached value) that `TrainingLoadCalculator.load` excludes from the acute/chronic calculation entirely, while a genuinely unrated workout still defaults to moderate (5) as before; the flag survives `removingWorkoutMetrics()` so it isn't silently reverted to fabricated-5 when Workout Metrics is disabled and cached snapshots are sanitized. VO₂max, cadence, and distance queries now also reuse the cached value on failure instead of collapsing to a missing field. `ActivityReadinessImpact.estimatedEffort` was deliberately left unchanged (out of surgical scope). **Round 3 (2026-07-14): Fixed.** The reuse fix itself had a gap: the HR-reuse branch in `fetchWorkoutSummaries` passed `resolvedVO2 ?? cached.cardioFitnessVO2Max` / `resolvedCadence ?? cached.averageStepCadenceSPM`, so a *successful* query confirming absence could never clear those fields for reused workouts — the stale value re-persisted every passive resume. The per-field decision is now the pure `resolvedWorkoutDetailMetric(fetched:failed:cached:)` (failure → cached; success → fetched, where nil is confirmed-absent and clears), used for VO₂max, cadence, and distance in both branches, with the `??` fallbacks removed. Truth-table tests in `HealthKitFetchEngineFailureSemanticsTests.swift` plus a reintroduction-guard source assertion in `ProjectConfigurationTests.swift`.

**Confirmed from code; live HealthKit failure should be exercised on device.**

**What:** A successful workout-list query is treated as success even when batched HR/detail subqueries fail. HR ignores error at [HealthKitFetchEngine.swift:1325](Body/Services/HealthKitFetchEngine.swift#L1325). Effort outcomes distinguish failure internally, but fetchEffortLevels collapses failed and confirmed-unrated into a missing dictionary value at [HealthKitFetchEngine.swift:1444](Body/Services/HealthKitFetchEngine.swift#L1444). [TrainingLoadCalculator.swift:16](BodyMetricsKit/TrainingLoadCalculator.swift#L16) converts missing effort to default 5.

**Risk:** A transient failed effort read can become a fabricated effort 5, replacing the training-load series and altering readiness. Failed HR, VO₂max, cadence, or distance reads can replace cached workout fields with empty/nil values.

**Breadth:** Workout details, month snapshots, predicted effort, training load, readiness, widgets, and Watch.

**Fix:** Carry per-field outcomes into summary assembly. Default effort 5 only for confirmed noSavedEffort, never failure. On enrichment failure, preserve the cached field or fail the derived metric transaction. Add tests for one failed effort among otherwise successful workouts and for failed-versus-empty HR batches.

## Medium

### M1. Overlapping explicit sleep stages are double-counted

**Outcome (2026-07-13): Deferred.** Sleep duration is already union-merged; disjoint de-overlap of explicit stages only matters with two explicit-stage sources and was deferred.

**Confirmed calculation; source-overlap frequency needs device data.**

**What:** [BodySleepSampleParser.swift:47](BodyWatchSnapshotKit/BodySleepSampleParser.swift#L47) carves unspecified sleep around explicit segments but concatenates explicit segments from multiple sources. [Sleep.swift:205](BodyMetricsKit/Sleep.swift#L205) sums their durations. Duplicate Deep samples from 01:00–02:00 therefore contribute two hours to a one-hour interval; conflicting Deep/REM overlaps also remain unresolved.

**Risk:** Stage totals can exceed the canonical sleep window, inflating percentages, awake duration, stage credit, and continuity.

**Breadth:** Users with overlapping Watch/iPhone/third-party sleep sources, particularly when sources are combined by name.

**Fix:** Normalize explicit stages into disjoint intervals with documented source/stage precedence. At minimum union same-stage intervals; conflicting-stage overlap needs a deterministic winner. Assert total allocated stage duration never exceeds the session window.

### M2. Auto-Apply can continue writing workout effort after the user turns it off

**Outcome (2026-07-13): Fixed.** The auto-apply loop checks `shouldContinue` (prefs + `!Task.isCancelled`) per candidate and the settings task is retained and cancelled on OFF / onDisappear. Files: `HealthKitWorkoutStore.swift`, `BodySettingsView.swift`.

**Confirmed from code.**

**What:** Settings starts an untracked task only on the true transition at [BodySettingsView.swift:1857](Body/Views/BodySettingsView.swift#L1857). The store reads the opt-in only once at [HealthKitWorkoutStore.swift:732](Body/Services/HealthKitWorkoutStore.swift#L732), then the loop at [HealthKitWorkoutStore.swift:689](Body/Services/HealthKitWorkoutStore.swift#L689) writes multiple candidates without rechecking cancellation or the current preference.

**Risk:** The app can perform additional HealthKit writes after the user explicitly disabled the feature.

**Breadth:** Recent eligible workouts in the active batch.

**Fix:** Retain and cancel the settings task on false/disappear, and enforce the invariant inside the service loop before every write:

    guard !Task.isCancelled,
          UserDefaults.standard.bool(forKey: autoApplyKey) else { break }

Test by disabling after the first fake write and asserting no later candidate is saved.

### M3. Sleep-stage preference refreshes can be dropped

**Outcome (2026-07-13): Fixed.** New `refetchAfterSleepDisplayPreferenceChange()` awaits any in-flight refresh before re-fetching, and both sleep-preference onChange handlers point at it. Files: `HealthKitWorkoutStore.swift`, `BodySettingsView.swift`.

**Confirmed from code.**

**What:** Two independent onChange handlers launch untracked refresh tasks at [BodySettingsView.swift:98](Body/Views/BodySettingsView.swift#L98). requestAuthorizationAndRefresh drops work when isRefreshing is already true. HealthKitFetchEngine captures each awake-stage preference at query start at [HealthKitFetchEngine+Sleep.swift:28](Body/Services/HealthKitFetchEngine+Sleep.swift#L28).

**Risk:** Toggle both preferences during one in-flight refresh and the second refresh may be discarded; the first task can commit old semantics until some unrelated later refresh.

**Breadth:** Current sleep, history, score, readiness, widget, and Watch stage presentation.

**Fix:** Coalesce settings into a preference signature and guarantee a refresh for the latest signature after current work completes. A task(id:) or store-level pending-refresh generation is appropriate.

### M4. Watch merge cannot represent authoritative no-data or cache reset

**Outcome (2026-07-13): Skipped / deferred.** The watch sleep-clear-on-blank-push half is intentional design (recorded in memory); the no-reset-tombstone gap was deferred with the broader per-metric watch state work (M6).

**Confirmed from code.**

**What:** [WatchMetricsModel.swift:96](BodyWatch/WatchMetricsModel.swift#L96) preserves any prior non-readiness metric when the incoming metric is blank. That conflates “not fetched” with “the source now has no data,” deletion, source change, or phone cache reset. In addition, merging starts from the received snapshot; if it preserves a local Sleep metric but received.sleepNight is nil, sanitization at [WatchMetricsSnapshot.swift:237](BodyWatchShared/Models/WatchMetricsSnapshot.swift#L237) clears the preserved value immediately.

**Risk:** Old metrics can survive indefinitely, while one intended local-preservation path for Sleep does the opposite. clearLocalCache does not publish a reset state that can override the merge rule.

**Breadth:** Sleep, training load, temperature, HR/HRV, Watch dashboard, and complications.

**Fix:** Carry per-metric state: value, notFetched, noData, permissionDisabled; add a snapshot reset revision. Preserve local values only for notFetched. When preserving local Sleep, preserve its sleepNight too. Extract merging into a pure helper with exhaustive state tests.

### M5. Watch snapshot ordering loses subsecond updates

**Outcome (2026-07-13): Fixed.** `WatchMetricsSnapshot` gained `publisherEpoch` + monotonic `revision`; the comparator orders same-epoch pushes by revision (surviving clock rollback) and adopts a new epoch on reinstall. Files: `WatchMetricsSnapshot.swift`, `WatchMetricsModel.swift`, `WatchConnectivityPublisher.swift`; tests `WatchSnapshotFreshnessTests.swift` + `WatchRevisionAllocatorTests.swift`. **Round 2 (2026-07-14): Fixed.** The round-1 fix ordered pushes by revision once queued, but `WatchConnectivityPublisher.send`'s admission gate (`guard snapshot.generatedAt >= lastQueuedGeneratedAt`) still ran on wall-clock time before any revision was assigned, so a backward clock change could suppress every subsequent publish indefinitely. The publisher now owns a monotonic `captureSequence` (via `nextCaptureSequence()`) requested by the store at the same point it captures `generatedAt`; the admission gate compares `captureSequence >= lastQueuedCaptureSequence` instead, and the activation-retry path re-sends with the original sequence rather than a fresh one, so ordering is clock-immune.

**Confirmed from code.**

**What:** WatchMetricsSnapshot uses JSONEncoder/Decoder .iso8601 at [WatchMetricsSnapshot.swift:270](BodyWatchShared/Models/WatchMetricsSnapshot.swift#L270), which serializes the ordering Date without reliable fractional precision. The watch accepts only received.generatedAt > current.generatedAt at [WatchMetricsModel.swift:63](BodyWatch/WatchMetricsModel.swift#L63). Two phone publications within one encoded second can compare equal, dropping the later settings or permission state.

**Risk:** Rapid updates can leave Watch on the earlier snapshot; clock rollback can make date ordering worse.

**Breadth:** All Watch metrics and synchronized settings.

**Fix:** Add a monotonic UInt64 revision to the payload and persisted snapshot; compare revision when present, falling back to generatedAt only for old versions. Add an encoding test with publications 100 ms apart.

### M6. Failed WatchConnectivity application context has no reliable retry

**Outcome (2026-07-13): Deferred.** Post-activation WatchConnectivity failures are mostly persistent conditions and frequent publications already mask them; bounded retry/backoff was deferred.

**Confirmed from code.**

**What:** [WatchConnectivityPublisher.swift:69](Body/Services/WatchConnectivityPublisher.swift#L69) stores pending after updateApplicationContext throws. The only flush is activationDidComplete at [WatchConnectivityPublisher.swift:88](Body/Services/WatchConnectivityPublisher.swift#L88). An already-activated session will not complete activation again; failed activation can also re-enter activation without bounded backoff.

**Risk:** A metric, permission, or entitlement update can remain unsent until a newer unrelated publication overwrites it; repeated activation attempts can waste power.

**Breadth:** Phone-to-Watch synchronization.

**Fix:** Classify transient versus permanent errors, retry transient failures with capped backoff, and flush pending on relevant session-state changes. Guard activationDidComplete on a successful activated state.

### M7. Unit and sleep preferences update Watch but leave iOS widgets stale

**Outcome (2026-07-13): Fixed.** New `republishCompanionSnapshots()` rebuilds both the iOS widget and watch payloads and is invoked from every formatting preference, including new energy/weight handlers. Files: `HealthKitWorkoutStore.swift`, `BodySettingsView.swift`, `HealthWidgetSnapshotBuilder.swift`.

**Confirmed from code.**

**What:** Settings onChange handlers at [BodySettingsView.swift:108](Body/Views/BodySettingsView.swift#L108) call publishWatchSnapshot only. Health-widget values are preformatted with temperature, energy, weight, sleep-goal, and Show Sleep Score preferences in [HealthWidgetSnapshotBuilder.swift:60](Body/Services/HealthWidgetSnapshotBuilder.swift#L60). Energy and weight changes have no equivalent companion callback.

**Risk:** Home-screen widgets can retain the old unit, goal, or score display until a later HealthKit refresh.

**Breadth:** Health metric and sleep widgets.

**Fix:** Add one republishCompanionSnapshots method that rebuilds both Watch and iOS widget payloads, then invoke it for every formatting/goal preference. Test saved snapshot output for each preference.

### M8. A valid empty current month is replaced by an unlabeled previous month in widgets

**Outcome (2026-07-13): Skipped — intentional design.** The previous-month fallback for the workout calendar/type widgets is deliberate; the user re-confirmed "leave as designed" on 2026-07-12 (recorded in project memory).

**Confirmed from code.**

**What:** [WorkoutSnapshotStore.swift:196](BodyShared/Services/WorkoutSnapshotStore.swift#L196) returns the previous snapshot whenever current.workoutCount == 0, even when the current file is valid and current. The live provider uses that method at [WorkoutCalendarWidget.swift:83](BodyWidgetExtension/WorkoutCalendarWidget.swift#L83). WorkoutCalendarView renders weekday/grid content without a visible snapshot month title.

**Risk:** From the first day of a new month until the first workout, the “this month” calendar/type widgets can silently show last month’s activity.

**Breadth:** Workout calendar and workout-type widgets at every month boundary for users with no current-month workout yet.

**Fix:** Fall back only when the current file is missing/stale, not when it is a valid empty current month. If product design intentionally shows the prior month, label the month prominently.

### M9. Widget timelines do not carry a deterministic midnight entry

**Outcome (2026-07-13): Skipped — intentional design.** Single-entry widget timelines with no forced midnight entry are a deliberate design choice.

**Confirmed from code; actual scheduling delay depends on WidgetKit.**

**What:** HealthMetric, SleepStages, WorkoutCalendar, HealthTrend, and Watch complication providers each create one entry and request another after roughly 30 minutes; representative lines are [HealthMetricWidget.swift:52](BodyWidgetExtension/HealthMetricWidget.swift#L52), [SleepStagesWidget.swift:35](BodyWidgetExtension/SleepStagesWidget.swift#L35), [WorkoutCalendarWidget.swift:66](BodyWidgetExtension/WorkoutCalendarWidget.swift#L66), and [WatchComplicationsProvider.swift:32](BodyWatchWidgetExtension/WatchComplicationsProvider.swift#L32).

**Risk:** WidgetKit does not guarantee an exact .after refresh. Yesterday’s Sleep or “today” highlight can remain visible beyond midnight until the system grants the next timeline request.

**Breadth:** Date-bound widgets and complications.

**Fix:** Include a second entry at the next local calendar midnight that clears date-bound sleep and advances the reference date. Compute with Calendar.date(byAdding:.day) rather than +86,400 to handle DST.

### M10. “Save if changed” is defeated by regenerated timestamps

**Outcome (2026-07-13): Fixed.** Both snapshot stores now decode the existing file, substitute the prior `generatedAt`/`generatedDate`, and skip the write when the bytes are equal, preserving the timestamp as a search-corpus cache key. Files: `WorkoutSnapshotStore.swift`, `HealthWidgetSnapshotStore.swift`; tests `SnapshotStoreSaveDedupeTests.swift`.

**Confirmed from code.**

**What:** HealthWidgetSnapshot.generatedDate is rebuilt on every publication at [HealthWidgetSnapshotBuilder.swift:97](Body/Services/HealthWidgetSnapshotBuilder.swift#L97) but is not used by readers. WorkoutMonthSnapshot.make defaults generatedAt to Date at [WorkoutMonthSnapshot.swift:152](BodyMetricsKit/WorkoutMonthSnapshot.swift#L152). Byte equality in [HealthWidgetSnapshotStore.swift:39](BodyShared/Services/HealthWidgetSnapshotStore.swift#L39) and [WorkoutSnapshotStore.swift:45](BodyShared/Services/WorkoutSnapshotStore.swift#L45) therefore changes even when user-visible content does not.

**Risk:** Unnecessary atomic writes, JSON encoding, file-cache invalidation, and WidgetKit reload-budget pressure on passive/five-minute refreshes.

**Breadth:** App Group widget persistence and reload scheduling.

**Fix:** Compare semantic payloads excluding generation metadata, remove unused generatedDate, or preserve prior generatedAt when content is equal. Test two independently built equal-content snapshots and assert the second save is a no-op.

### M11. Training-load readiness score improves at the penalty threshold

**Outcome (2026-07-13): Skipped — latent.** The training-load component score is not rendered anywhere, so the ~1.30 discontinuity is not user-visible; left for a future scoring pass.

**Confirmed pure logic.**

**What:** trainingLoadScore uses the sustainable curve through 1.30 at [ReadinessScoreCalculator.swift:781](BodyMetricsKit/ReadinessScoreCalculator.swift#L781). The sustainable score at 1.30 is 62 at [ReadinessScoreCalculator.swift:900](BodyMetricsKit/ReadinessScoreCalculator.swift#L900), but a value just above 1.30 starts a penalty curve at base 70. A worse load therefore raises the component score by about eight points.

**Risk:** The displayed component and any dependent explanation are non-monotonic at a clinically meaningful boundary.

**Breadth:** Readiness days with training-load ratio around 1.30.

**Fix:** Make the penalty curve continuous from the 1.30 score, or redesign one monotonic curve. Add boundary tests for 1.299, 1.300, and 1.301.

### M12. Readiness confidence uses the best baseline count and hides normal vitals

**Outcome (2026-07-13): Skipped — informational.** Readiness confidence and the vitals component are not displayed, so the described semantics have no user-facing effect today.

**Confirmed calculation; desired product semantics should be confirmed.**

**What:** vitalsAssessment at [ReadinessScoreCalculator.swift:690](BodyMetricsKit/ReadinessScoreCalculator.swift#L690) returns nil when qualified vitals are normal, so vitals appear “unavailable” only on good days. confidence at [ReadinessScoreCalculator.swift:801](BodyMetricsKit/ReadinessScoreCalculator.swift#L801) receives bestBaselineDayCounts.max rather than the limiting evidence count. Long synthetic training history can therefore produce high confidence while physiological baselines are short.

**Risk:** Confidence communicates more evidence than the score actually has, and component availability changes based on whether the reading is abnormal.

**Breadth:** Readiness confidence/status explanation.

**Fix:** Track “reading available” separately from anomaly magnitude; produce a neutral vitals component for qualified normal readings. Base confidence on per-component thresholds or the limiting core baseline, not the maximum.

### M13. Effort calibration scores all prior workouts with the target day’s resting HR

**Outcome (2026-07-13): Skipped.** The calibration bias is already bounded by a ±2 clamp, capping any target-day resting-HR skew.

**Confirmed pure logic.**

**What:** [HealthKitWorkoutStore.swift:566](Body/Services/HealthKitWorkoutStore.swift#L566) supplies one target-workout resting-HR input. calibrationBias at [WorkoutEffortEstimator.swift:619](BodyMetricsKit/WorkoutEffortEstimator.swift#L619) re-scores every historical prior with that same input.

**Risk:** Changes in resting HR are incorrectly attributed to historical rating bias. For example, a target-day RHR of 50 is applied to workouts completed when RHR was 70, overstating their heart-rate reserve and shifting the learned offset.

**Breadth:** Predicted workout effort for users whose resting HR changes over time.

**Fix:** Supply a per-day resting-HR lookup and build a prior-specific input, or choose a calibration basis that deliberately does not use target-day RHR. Add a test with two distinct prior-day resting HR values.

### M14. HealthKit write boundaries accept invalid or partial body-composition input

**Outcome (2026-07-13): Skipped.** The only caller of the body-composition write path is a bounded picker UI, so invalid / infinite / future inputs cannot reach it.

**Confirmed app-side acceptance; HealthKit’s response to each invalid value needs runtime verification.**

**What:** [HealthKitFetchEngine+Write.swift:50](Body/Services/HealthKitFetchEngine+Write.swift#L50) checks weight only for > 0, so infinity passes; body fat accepts values above 100 and infinity; date may be arbitrarily future. Invalid fields can be silently skipped while valid siblings save. Effort clamps without first requiring a finite value at [HealthKitFetchEngine+Write.swift:142](Body/Services/HealthKitFetchEngine+Write.swift#L142).

**Risk:** Opaque HealthKit errors, inconsistent partial saves, or invalid/future records if an internal caller bypasses the picker.

**Breadth:** Body composition and workout effort writes.

**Fix:** Validate all inputs atomically at the service boundary and throw a dedicated invalidInput error before creating any sample. Require finite values, product-approved ranges, at least one field, and a nonfuture date.

### M15. Raw intraday loading fetches a year of unlimited samples and is not cancellable

**Outcome (2026-07-13): Fixed.** Added `intradayDaySampleInterval(calendar:)` bounding intraday fetches to the UI-reachable ~33 days (with 48 h overlap), leaving the 365-day trend charts unaffected. File: `HealthKitFetchEngine.swift`. **Round 2 (2026-07-14): Fixed.** Bounding the fetch window didn't address the other half of the finding — none of the ~26 continuation-based query wrappers used `withTaskCancellationHandler`/`healthStore.stop`, so a cancelled task left the underlying HK query running. Added a `runCancellableQuery` helper with a lock-protected state machine (`pendingNoQuery` / `pendingWithQuery(HKQuery)` / `cancelled` / `completed`, handling cancellation landing before the query is even installed) and applied it to the two heaviest queries — `fetchQuantitySampleSeries` (intraday series) and the month workouts query; other lightweight wrappers are left unchanged (surgical scope). Follow-on: `handleRefreshError` now early-returns on `CancellationError` so a cancelled refresh no longer surfaces a failure notice to the user. **Round 3 (2026-07-14): Fixed.** `CancellableQueryCoordinator.install` set `.pendingWithQuery`, unlocked, then called `healthStore.execute(query)`; a cancel landing in that window stopped a not-yet-executed query (no-op) and resumed the caller, after which install executed the query anyway — leaking the HK work, the exact gap the round-2 fix targeted. The coordinator now has an explicit `.executing` phase with a deferred exactly-once stop (`.cancelledAwaitingStop` → install's post-execute re-check performs the single `stop`), injectable execute/stop closures, and internal visibility; deterministic latch-controlled race tests live in the new `BodyTests/CancellableQueryCoordinatorTests.swift`. Scope honestly unchanged: this still covers only the two `runCancellableQuery` call sites — `fetchQuantitySampleSeries` and the month-workouts query in `fetchWorkoutSummaries`; the other checked-continuation query wrappers (e.g. the effort/source/sleep/write paths) still execute HK queries without cancellation handling and remain a deliberate surgical deferral.

**Confirmed from code.**

**What:** [HealthKitFetchEngine.swift:1078](Body/Services/HealthKitFetchEngine.swift#L1078) defaults to the 365-day trend interval, uses HKObjectQueryNoLimit, materializes all samples, and wraps HKSampleQuery in withCheckedContinuation without a cancellation handler. The detail day picker exposes only 30 past days plus tomorrow at [BodyHealthMetricDetailView.swift:615](Body/Views/Health/BodyHealthMetricDetailView.swift#L615).

**Risk:** Heart-rate data can mean tens of thousands of objects, high memory/IPC cost, and continued work after the detail view is dismissed.

**Breadth:** First intraday load per metric/source, most severe for heart rate.

**Fix:** Fetch only the UI-reachable window plus overlap, or page/downsample older data if year navigation is planned. Use async descriptors or withTaskCancellationHandler and healthStore.stop(query).

### M16. Intraday day-slice cache can return stale values

**Outcome (2026-07-13): Fixed.** `BodyMetricDaySeriesCache` now stores the source `HealthTrendSeries` and requires `entry.source == series` on a hit, so a backdated edit invalidates the cached day slice. File: `Body/Views/Health/BodyHealthMetricDetailView.swift`.

**Confirmed from code.**

**What:** BodyMetricDaySeriesCache.Key at [BodyHealthMetricDetailView.swift:2342](Body/Views/Health/BodyHealthMetricDetailView.swift#L2342) includes selected day, count, firstDate, and lastDate only. A backdated edit or source refresh can change middle values while preserving every key field.

**Risk:** A detail chart and its average can continue showing old samples after the store publishes changed data.

**Breadth:** Intraday detail charts.

**Fix:** Include a content revision/fingerprint from HealthTrendSeries, or compare/hash the selected day’s points. Test two series with identical count/endpoints but different middle values.

### M17. Home trend assembly repeats full-series hashing during one render

**Outcome (2026-07-13): Deferred — perf.** Home trend re-fingerprinting is a measure-first optimization; not addressed this round.

**Confirmed from code; measure on target devices before choosing the final cache strategy.**

**What:** hasHomeTrends, homeTrendsContent, canToggleAllHomeTrends, and visible card getters repeatedly invoke model assembly at [BodyHomeView.swift:632](Body/Views/BodyHomeView.swift#L632) and [BodyHomeView.swift:823](Body/Views/BodyHomeView.swift#L823). Cache hits still fingerprint every point at [BodyHomeView.swift:2321](Body/Views/BodyHomeView.swift#L2321). Progressive store publications amplify the work.

**Risk:** Avoidable main-thread CPU during Home updates with 365-day series.

**Breadth:** Home dashboard, especially all-metrics mode.

**Fix:** Compute the visible models and toggle eligibility once per body pass, or key the model factory by a store-provided snapshot revision. Add a signpost assertion that each metric is fingerprinted at most once per body update.

### M18. Long-workout split computation repeats on unrelated detail state changes

**Outcome (2026-07-13): Deferred — perf.** Split-computation memoization is a measure-first optimization; not addressed this round.

**Confirmed from code.**

**What:** splitsPresentation calls WorkoutSplitCalculator over raw distance samples at [BodyWorkoutsView.swift:1386](Body/Views/BodyWorkoutsView.swift#L1386) each time BodyWorkoutDetailSheet evaluates. Effort edits, prediction resolution, route updates, and store publications can all trigger it.

**Risk:** Large raw split series are recomputed on the main actor during interactions.

**Breadth:** Long distance workouts with many distance samples.

**Fix:** Memoize by split-data revision, units, workout bounds, and type; recompute only when those inputs change. Performance-test with a long synthetic run while editing effort.

### M19. Background customization writes UserDefaults on every drag frame

**Outcome (2026-07-13): Fixed.** The color/separator editors now drag against local `@State` drafts and persist to AppStorage only on gesture end. File: `BodySettingsView.swift`.

**Confirmed from code.**

**What:** Persisted color/separator bindings parse and serialize AppStorage strings at [BodySettingsView.swift:1168](Body/Views/BodySettingsView.swift#L1168). Gesture onChanged handlers mutate them continuously at [BodySettingsView.swift:1627](Body/Views/BodySettingsView.swift#L1627) and [BodySettingsView.swift:1698](Body/Views/BodySettingsView.swift#L1698).

**Risk:** Preference-write churn and invalidation of all AppStorage consumers can make the editor visibly janky.

**Breadth:** Background color and separator dragging.

**Fix:** Edit local State drafts, update preview from drafts, and persist on gesture end, Done, or a short throttle.

### M20. A pending purchase can strand every recovery action

**Outcome (2026-07-13): Fixed (partial).** While a purchase is pending, only re-purchase is disabled — Restore and Redeem stay enabled for in-session recovery. File: `Body/Views/BodyProView.swift`. (An authoritative-inactive auto-clear / "Check status" action was not added.)

**Confirmed state-machine path; Ask-to-Buy/SCA behavior should be tested with StoreKitTest.**

**What:** BodyProStore clears pending only when entitlement becomes active at [BodyProStore.swift:161](Body/Services/BodyProStore.swift#L161). BodyProView treats pending as an active flow at [BodyProView.swift:29](Body/Views/BodyProView.swift#L29) and disables Purchase, Restore, and Redeem at [BodyProView.swift:130](Body/Views/BodyProView.swift#L130). A declined or abandoned external approval can remain pending until process restart.

**Risk:** The user has no in-session recovery/check action.

**Breadth:** Ask-to-Buy and SCA purchase attempts.

**Fix:** Disable only duplicate purchase submission while pending; retain Restore/manage/check-status actions. Clear pending after an authoritative inactive refresh or expose “Check status.” Cover the state machine with StoreKitTest or an injected purchase client.

## Low

### L1. Resume freshness checks fail open when the system clock moves backward

**Outcome (2026-07-13): Fixed.** `syncWhenAppBecomesActive` now treats a negative elapsed interval as stale in both checks. File: `HealthKitWorkoutStore.swift`.

**What:** [HealthKitWorkoutStore.swift:1485](Body/Services/HealthKitWorkoutStore.swift#L1485) treats a negative elapsed interval as less than 60/300 seconds. A future lastAppEntrySyncDate suppresses resumes until wall time catches up; a future persisted lastSuccessfulRefreshDate selects the “fresh dashboard” path.

**Impact:** Health data can remain stale for hours or days after manual clock correction.

**Fix:** Treat elapsed < 0 as stale and reset the relevant timestamp. Add negative-elapsed tests.

### L2. Route display waits for reverse geocoding

**Outcome (2026-07-13): Fixed (partial).** The store seam publishes coordinates first and resolves locality separately; the detail view still awaits the full route call, so the optional "show map before locality" polish is deferred. Files: `HealthKitWorkoutStore.swift`, `HealthKitFetchEngine+Route.swift`.

**What:** [HealthKitWorkoutStore.swift:841](Body/Services/HealthKitWorkoutStore.swift#L841) fetches coordinates, then awaits BodyReverseGeocoder before returning. [BodyWorkoutsView.swift:889](Body/Views/BodyWorkoutsView.swift#L889) assigns route only after the entire call.

**Impact:** A valid map hero remains absent behind a slow/throttled geocoder.

**Fix:** Publish coordinates immediately and resolve locality independently; update only the label later.

### L3. Home preview sizing uses global screen width

**Outcome (2026-07-13): Deferred — perf.** Container-width preview sizing is a measure-first change; not addressed this round.

**What:** [BodyHomeView.swift:672](Body/Views/BodyHomeView.swift#L672) and [BodyHealthMetricCard.swift:23](Body/Views/Health/BodyHealthMetricCard.swift#L23) derive point counts/widths from UIScreen.main.bounds.

**Impact:** iPad Split View, Stage Manager, and multiwindow layouts can receive a “wide screen” preview in a compact container, causing compression and excess work.

**Fix:** Use container width or a parent-supplied layout category and include it in the memo key.

### L4. Workout list popups eagerly construct every row

**Outcome (2026-07-13): Fixed.** The workout list popup switched from `VStack` to `LazyVStack`. File: `Body/Views/BodyWorkoutListSheet.swift`.

**What:** [BodyWorkoutListSheet.swift:90](Body/Views/BodyWorkoutListSheet.swift#L90) uses VStack inside ScrollView for all selected workouts.

**Impact:** Large month/type selections create every row and formatter immediately.

**Fix:** Use LazyVStack and test with several hundred workout summaries.

### L5. Gesture-only workout-detail dismissal is an accessibility risk

**Outcome (2026-07-13): Skipped — intentional design.** The gesture-only workout-detail dismissal (no close button) is deliberate; drag-to-dismiss was verified working on the fullScreenCover path.

**What:** BodyWorkoutDetailSheet hides the navigation bar and has no dismiss action at [BodyWorkoutsView.swift:848](Body/Views/BodyWorkoutsView.swift#L848). The calendar/type path presents it with fullScreenCover at [BodyWorkoutListSheet.swift:129](Body/Views/BodyWorkoutListSheet.swift#L129). [ProjectConfigurationTests.swift:1556](BodyTests/ProjectConfigurationTests.swift#L1556) explicitly pins the absence of a close button.

**Impact:** Drag-to-dismiss is undiscoverable and can be difficult with Switch Control, AssistiveTouch, motor impairments, or an interrupted transition. The fullScreenCover path needs direct device verification.

**Fix:** Add an accessible top-leading/back or close action using Environment dismiss. It can coexist with the zoom gesture.

### L6. Custom full-screen overlays do not declare modal accessibility

**Outcome (2026-07-13): Fixed.** Both the readiness overlay and the first-launch overlay now set `.isModal` and hide the background from accessibility while presented. Files: `BodyHomeView.swift`, `MainTabView.swift`, `BodyFirstLaunchOverlay.swift`.

**What:** Readiness uses a plain overlay at [BodyHomeView.swift:472](Body/Views/BodyHomeView.swift#L472); initial load is also a custom overlay at [MainTabView.swift:57](Body/Views/MainTabView.swift#L57).

**Impact:** VoiceOver may traverse controls visually blocked behind the overlay.

**Fix:** Prefer fullScreenCover, or mark the overlay modal, hide underlying accessibility nodes while presented, and move focus into the overlay. Add accessibility UI coverage.

### L7. Reduce Motion is inconsistently honored

**Outcome (2026-07-13): Fixed.** Reduce-motion gates were added to the star-hero count-up, the wave-fill slosh, and the Pro icon flip. Files: `BodyReadinessStarHero.swift`, `BodyProView.swift`. **Round 2 (2026-07-14): Fixed.** The round-1 gates missed the Activity Rings completion star — a separate view from the readiness star hero. `BodyActivityRingsCard` now reads `@Environment(\.accessibilityReduceMotion)` and skips the `.easeInOut(0.35)` fade animation and transition when Reduce Motion is on, matching the existing `BodyActivityRingGraphic` pattern. File: `BodyActivityRingsDetailView.swift`.

**What:** BodyReadinessStarHero observes reduce motion but still uses smooth/spring animation at [BodyReadinessStarHero.swift:54](Body/Views/BodyReadinessStarHero.swift#L54); activity completion and the Pro icon also animate without a complete reduce-motion branch.

**Impact:** Accessibility preference is not respected across major celebratory/transform animations.

**Fix:** Gate animations or apply immediate state transitions when accessibilityReduceMotion is true.

### L8. Watch permission synchronization fails open on malformed data

**Outcome (2026-07-13): Skipped.** Strict fail-closed parsing of synchronized permissions is cross-version defense-in-depth against data the app itself never writes; deferred.

**What:** [WatchMetricsModel.swift:80](BodyWatch/WatchMetricsModel.swift#L80) stores any nonnil permission string and thereby opens the Watch HealthKit read gate. [BodyHealthSelections.swift:264](BodyMetricsKit/BodyHealthSelections.swift#L264) uses an all-enabled fallback for malformed persisted values.

**Impact:** Corrupted paired-context data can enable HR/HRV reads that the phone selection did not authorize in-app.

**Fix:** Strictly parse remote data; distinguish missing fresh-install state from present-but-invalid state, and fail closed for invalid synchronized values.

### L9. App Group load-cache identity has an ABA hole

**Outcome (2026-07-13): Skipped — theoretical.** The App Group load-cache ABA requires a same-size replacement with a colliding timestamp; atomic writes and sub-second mtimes make it non-actionable.

**What:** Load caches in [HealthWidgetSnapshotStore.swift:78](BodyShared/Services/HealthWidgetSnapshotStore.swift#L78), [WorkoutSnapshotStore.swift:86](BodyShared/Services/WorkoutSnapshotStore.swift#L86), and [WatchMetricsSnapshotStore.swift:73](BodyWatchShared/Services/WatchMetricsSnapshotStore.swift#L73) key only on modification date and file size.

**Impact:** A same-size replacement with a colliding/restored timestamp can return stale decoded data.

**Fix:** Add file identifier/inode or a payload revision to the key, and explicitly invalidate local cache entries after save/delete. Add a same-size/same-mtime replacement test.

### L10. The day-sample sidecar is not migration tolerant

**Outcome (2026-07-13): Fixed (with H6).** The day-sample sidecar's `init(from:)` uses `decodeIfPresent` with defaults for every field, so adding a metric no longer fails the whole legacy sidecar. File: `BodyMetricsKit/HealthTrend.swift`.

**What:** [HealthTrend.swift:931](BodyMetricsKit/HealthTrend.swift#L931) relies on synthesized Codable with every field required.

**Impact:** Adding an intraday metric can make the entire older sidecar fail to decode rather than defaulting only the new field.

**Fix:** Add schemaVersion and a custom init(from:) using decodeIfPresent(... ) ?? .empty for each field.

### L11. RevenueCat’s long-lived listener task is not cancelled

**Outcome (2026-07-13): Skipped — intentional.** The RevenueCat listener task lives for the app-lifetime single store; cancelling it in deinit was judged unnecessary.

**What:** BodyProStore retains updatesTask at [BodyProStore.swift:47](Body/Services/BodyProStore.swift#L47), but has no deinit cancellation. Weak self prevents retaining the store; it does not cancel the underlying infinite Task consuming customerInfoStream.

**Impact:** Recreating the store can leave orphan stream consumers. Production breadth is low because the app normally owns one store for its lifetime.

**Fix:** Cancel updatesTask in deinit.

### L12. The fallback Pro price is storefront-specific

**Outcome (2026-07-13): Fixed.** Removed the guessed `$9.99` fallback — the paywall shows a loading-price placeholder until the product resolves and an unavailable / Retry card on load failure. Files: `Body/Services/BodyProStore.swift`, `Body/Views/BodyProView.swift`.

**What:** [BodyProStore.swift:26](Body/Services/BodyProStore.swift#L26) and [BodyProView.swift:20](Body/Views/BodyProView.swift#L20) show “$9.99” before or after product loading failure.

**Impact:** Users in other storefronts see the wrong currency/price and can tap a product that is unavailable.

**Fix:** Show loading/unavailable until StoreProduct.localizedPriceString exists; do not guess a price.

### L13. ReadinessStatus classifies scores above 100 as poor

**Outcome (2026-07-13): Fixed.** `ReadinessStatus` now uses `case 95...` so scores above 100 classify as prime. File: `BodyMetricsKit/ReadinessModels.swift`.

**What:** [ReadinessModels.swift:18](BodyMetricsKit/ReadinessModels.swift#L18) matches prime only for 95...100, then sends every other value—including >100—to poor.

**Impact:** Current calculators clamp inputs, so this is mainly a robustness/migration risk for corrupted or future persisted values.

**Fix:** Clamp before classification or use case 95....

### L14. The workout search cache can trap on duplicate IDs

**Outcome (2026-07-13): Fixed (with H9).** The workout search cache builds via `Dictionary(_:uniquingKeysWith:)`, so a duplicate ID no longer traps. File: `Body/Views/BodyWorkoutsView.swift`.

**What:** [BodyWorkoutsView.swift:552](Body/Views/BodyWorkoutsView.swift#L552) builds Dictionary(uniqueKeysWithValues:). A duplicate WorkoutSummary.ID in a corrupted/legacy snapshot causes a runtime precondition failure.

**Impact:** The Workouts tab can crash on malformed cached data.

**Fix:** Use Dictionary(..., uniquingKeysWith:) with an explicit winner and validate/deduplicate at snapshot decode.

### L15. Several small presentation inconsistencies remain

**Outcome (2026-07-13): Fixed (all four).** L15a locale time template (`WorkoutSummary.swift`), L15b widget chart splits at nil gaps (`HealthWidgetTrendChartView.swift`), L15c dead `sleepStageSnapshot` param removed (`HealthWidgetSnapshotBuilder.swift`), and L15d engine `anchorDate` threaded into the sleep window (`HealthKitFetchEngine+Sleep.swift`). **Round 2 (2026-07-14): Fixed.** L15d's original fix only threaded the anchor into the HealthKit sleep-window fetch; `ReadinessScoreCalculator` still created fresh `Date()` internally in `summary(on:)`, `dailySeries`, `sleepAssessment`, and `currentDaySleepSummary`, making historical/test computations nondeterministic. An explicit `today` parameter is now threaded through all four functions (and into `HealthDashboardSnapshot.readinessCoverage`'s `currentDaySleepInput`, which compared against a fresh `Date()` too), so callers pass one captured as-of date instead of each function reading the wall clock; live behavior is unchanged.

**What:**

- [WorkoutSummary.swift:501](BodyMetricsKit/WorkoutSummary.swift#L501) hardcodes HH:mm instead of a locale-sensitive hour template.
- [HealthWidgetTrendChartView.swift:207](BodyShared/Components/HealthWidgetTrendChartView.swift#L207) continues across missing points, visually connecting a gap; the Watch sparkline splits gaps.
- [HealthWidgetSnapshotBuilder.swift:61](Body/Services/HealthWidgetSnapshotBuilder.swift#L61) accepts sleepStageSnapshot and immediately shadows it.
- [HealthKitFetchEngine+Sleep.swift:24](Body/Services/HealthKitFetchEngine+Sleep.swift#L24) and readiness helpers use fresh Date() despite accepting anchor/as-of dates.

**Impact:** Incorrect 24-hour formatting in some locales, misleading widget continuity, dead API surface, and nondeterministic historical/test computations.

**Fix:** Use localized date templates, reset paths at nil gaps, remove or honor the shadowed parameter, and thread one captured asOf through each computation.

## Suggestion

### S1. Introduce a single persistence actor

**Outcome (2026-07-13): Deferred — suggestion.** A single persistence actor was not introduced this round.

Own dashboard, day sidecar, workout files, widget files, cache identities, disk-size reporting, and clear/reset ordering in one actor. This would make save/delete FIFO semantics explicit and remove DispatchQueue plus nested Task handoffs from HealthKitWorkoutStore.

### S2. Add explicit data protection and backup policy for regenerable health caches

**Outcome (2026-07-13): Deferred — suggestion.** Explicit data-protection / backup policy for regenerable caches was not changed this round.

Snapshot JSON contains health/workout values. Document the intended file-protection class for app and App Group files, apply it explicitly after atomic replacement, and exclude regenerable app-cache files from backup where appropriate. Balance stronger protection against the requirement for widgets/Watch to read data while the phone is locked; make the choice deliberate and covered by a release check.

### S3. Bound session caches

**Outcome (2026-07-13): Deferred — suggestion.** Session-cache bounding (LRU) was not added this round.

routeCache and distanceSampleCache in [HealthKitWorkoutStore.swift:148](Body/Services/HealthKitWorkoutStore.swift#L148) grow for the app session. Route data is downsampled to roughly 400 points, which is good, but a long browsing session can retain many routes/split arrays. Add a modest LRU/count limit and clear it on memory warning or source/permission change.

### S4. Move per-render transforms into revision-keyed presentation models

**Outcome (2026-07-13): Deferred — suggestion.** Revision-keyed presentation models were not introduced; M16 addressed the specific stale-day-cache case.

Home trend analysis, detail day slicing, split calculation, and settings drafts should consume immutable snapshot revisions. This reduces body complexity, avoids ad hoc fingerprints, and gives focused unit/performance tests without changing app-wide ownership.

### S5. Keep a release-time external configuration checklist

**Outcome (2026-07-13): Deferred — suggestion.** A formal release-time external-configuration checklist was not added; the relevant gates are tracked in the TestPlan manual cases.

The repository cannot verify RevenueCat dashboard entitlement/product mapping, App Store Connect product availability/price, privacy-report output, Watch target resource inclusion, or real HealthKit locked-device behavior. Record these as explicit release gates rather than implying source-string tests prove them.

## Test Coverage Gaps

The pure model suite is substantial, especially workout-month snapshots, readiness calculation, effort estimation, chart aggregation, cache migration, and widget snapshot construction. The most urgent missing tests are the asynchronous and cross-process state machines:

1. **HealthKit failure semantics:** For every query shape, distinguish failed/cancelled from successful-empty and verify cached values are retained only on failure.
2. **Sleep sessionization:** Raw samples spanning midnight, duplicate same-stage overlaps, conflicting-stage overlaps, and phased overnight-vitals arrival.
3. **Refresh generation:** Suspend a fake query, change source/permission/preference, resume it, and assert no stale or mixed result publishes.
4. **Day-sample provenance:** Primary, default-primary, secondary, combine-by-name, permission, entitlement, and launch-time signature changes.
5. **Cache clear ordering:** Block a queued save, clear, release, and assert all disk files, widget state, Watch state, and engine caches remain cleared.
6. **Workout detail cancellation:** Cancel route/split load, then reopen and prove a real retry occurs.
7. **Month timeout:** Use a non-cooperative fake load and assert pending UI state clears at 15 seconds.
8. **Auto-Apply cancellation:** Disable after the first write and assert no later HealthKit writes.
9. **Watch state machine:** Measurement-time ordering, same-second phone revisions, noData versus notFetched, authoritative reset, malformed permissions, and retry/backoff.
10. **Widget timelines/preferences:** Midnight entry behavior, empty-current-month behavior, semantic save dedupe, and every display-unit/goal preference.
11. **StoreKit:** pending/declined/approved/restore transitions and product-unavailable UI using StoreKitTest or an injected RevenueCat client.
12. **Accessibility/UI:** explicit detail dismissal, modal overlay focus, Reduce Motion, iPad Split View/Stage Manager sizing, and large workout lists.
13. **Privacy manifests:** Assert expected required-reason categories for every built executable bundle, not only source files.

## Reviewed Areas That Look Sound

- HealthKitWorkoutStore is main-actor isolated, while HealthKitFetchEngine is an actor; refresh entry points generally claim isRefreshing before their first suspension.
- The app owns HealthKitWorkoutStore with StateObject and injects it once; major SwiftUI ownership wrappers are generally appropriate.
- No production try!, as!, fatalError, or obvious force-unwrap crash path was found.
- Snapshot file writes use atomic replacement and deterministic sorted-key JSON. Load caches are lock protected.
- Live widget paths do not fabricate sample workouts; placeholder data is limited to previews/gallery.
- App Group identifiers and entitlements align across app, widgets, and Watch targets.
- Workout route points are downsampled before map rendering, and UIViewRepresentable map teardown removes delegates/overlays/annotations.
- Per-scroll-frame state in major Home/workout screens has been isolated from heavy content trees.
- Permission-off filtering strips dependent data, and several primary trend/history queries already preserve cache on failure—the pattern should be extended consistently.
- Daily aggregation generally uses explicit calendars and month workout queries use strict start dates.
- Body-owned effort replacement saves/relates the new HealthKit sample before deleting prior Body samples.
- No custom authentication/token networking layer exists. RevenueCat is the only production network SDK reviewed; its public SDK key is not a secret, and no sensitive health values or tokens were found in production logs.

## Priority Fix List

1. **Complete all privacy manifests (C1).** This can block App Store submission. Benefit: release eligibility and a reliable target-level compliance test.
2. **Sessionize sleep across midnight (H1).** This is a foundational data bug feeding sleep, vitals, readiness, widgets, and Watch. Benefit: correct nightly source-of-truth data.
3. **Introduce failure-versus-empty HealthKit outcomes (H2/H3/H4/H12).** Benefit: transient platform failures stop destroying or fabricating persisted health state.
4. **Add immutable refresh context and generation rejection (H5/H6).** Benefit: no mixed-source snapshots or stale source data after settings changes.
5. **Make cache clear ordered, awaited, and authoritative (H7).** Benefit: the privacy action becomes truthful and old data cannot reappear.
6. **Fix workout detail cancellation and the false timeout (H8/H9).** Benefit: routes/splits retry correctly and Workouts cannot remain behind an endless loading overlay.
7. **Use Watch measurement timestamps and explicit revisions/states (H10, M4, M5).** Benefit: stale samples stop masquerading as live, and cross-device merges become deterministic.
8. **Make readiness freezing coverage-aware (H11), then fix the training-load discontinuity (M11).** Benefit: historical readiness becomes stable for the right reason and the score remains monotonic.
9. **Make Auto-Apply cancellation authoritative (M2).** Benefit: no HealthKit writes occur after opt-out.
10. **Correct widget publication semantics (M7–M10).** Benefit: correct month/date/unit display with fewer writes and fewer reload-budget requests.
11. **Bound/cancel raw intraday loading and fix cache keys (M15/M16).** Benefit: lower memory/IPC cost and no stale day chart after edits/source changes.
12. **Add the asynchronous test harness described above.** This is the enabling investment for the riskiest fixes; without it, future regressions will continue to escape source-shape tests.
