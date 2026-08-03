# Body iOS Project Code Review

Review date: 2026-08-03  
Reviewed revision: current on-disk worktree on branch body-0.9.10  
Method: whole-project static review using CodeGraph call-path analysis, targeted source/configuration inspection, existing-test inspection, and independent finding validation.

## Executive Summary

The project has a substantial amount of careful defensive work: HealthKit results are generally normalized before presentation, individual cache files use atomic replacement, the watch merge path has generation checks, expensive sleep/chart calculations have focused caches, and the pure-model test suite is broad. I found no credible Critical issue, no production force unwrap/cast that creates an obvious crash path, and no leaked secret or custom authentication-token handling.

The most important current defect is a logical Swift-concurrency race: a refresh can begin with one permission/source configuration and finish after those mutable settings have changed, allowing mixed-generation HealthKit results to be published and persisted. The next cluster is semantic rather than mechanical: sleep presentation preferences, naps, and overlapping stages can change scores or readiness in ways that do not represent the underlying night. Watch recovery and HealthKit cancellation also need hardening.

Finding count:

- Critical: 0
- High: 1
- Medium: 20
- Low: 15
- Suggestions: 5

This was a read-only audit apart from this report. Per the repository audit workflow, I did not run builds or tests. Where a test failure is described as deterministic, it is based on direct inspection of both the test and its current input data.

## Architectural Concerns

### Mutable refresh configuration is not modeled as one transaction

HealthKitWorkoutStore and HealthKitFetchEngine treat permissions, primary source, secondary source, combine-by-name, the date anchor, progressive publication, cache signatures, and watch publication as related concepts, but they are not carried through a refresh as one immutable value. The engine actor prevents unsynchronized memory access; it does not prevent actor reentrancy from making one logical refresh observe multiple setting generations. This is the root cause of H-01.

The durable direction is an immutable DashboardFetchContext plus a monotonically increasing refresh generation. Every query leaf, progressive update, cache commit, widget update, and watch publication should identify the same context and generation.

### Canonical health data and presentation preferences are mixed

Sleep parsing currently removes samples based on display preferences before the result reaches scoring. The same flattened wake-day snapshot also serves several meanings: the visual timeline, total sleep, continuity opportunity, the main-night wake time, and readiness workout-drain boundaries. Those are not interchangeable when naps or overlapping writers exist.

Keep a normalized, lossless canonical sleep model. Derive presentation-filtered segments, main-session scoring inputs, nap totals, and wake-cycle boundaries from it explicitly.

### Persistence and transport state span multiple independently committed values

The dashboard main snapshot, intraday sidecar, freshness timestamp, source signatures, watch compute seed, and WatchConnectivity application context are stored or acknowledged separately. Each individual file write is generally sound, but there is no cross-file commit identity and some APIs collapse “unchanged” and “failed” into the same Boolean. This makes crash recovery and stale-state invalidation harder to reason about.

Use versioned envelopes with a generation/content hash, structured I/O outcomes, and a single commit point for metadata that asserts freshness.

### Large integration hubs obscure ownership and test seams

Body/Services/HealthKitWorkoutStore.swift is roughly 4,100 lines, Body/Services/HealthKitFetchEngine.swift and its extensions coordinate many query types, Body/Views/BodySettingsView.swift is roughly 3,300 lines, and Body/Views/BodyWorkoutsView.swift and Body/Views/Health/BodyHealthMetricDetailView.swift each own substantial orchestration. BodyProStore also calls the RevenueCat singleton directly.

These files are not automatically wrong because they are large, but they combine state ownership, policy, transport, persistence, and UI concerns. That makes the high-risk paths difficult to isolate in tests. Extract refresh coordination, snapshot repositories, purchase clients, month loading, date-boundary handling, and focused view models behind small protocols.

### Calendar boundaries are handled independently by each surface

The phone, widgets, complications, and watch app each decide independently when “today,” the active sleep day, a month window, or a freshness interval changes. Several Low findings are variations of this problem. A shared, injectable boundary policy would make midnight, timezone-change, and clock-adjustment behavior deterministic.

## Critical

No Critical issue was confirmed. In particular, the review found no obvious production force unwrap/cast crash path, secret embedded in source, unbounded route rendering path, or proven data-destructive persistence operation.

## High

### H-01 — An in-flight dashboard refresh can publish a mixed permission/source configuration

**Locations**

- Body/Services/HealthKitWorkoutStore.swift:1463-1488, 1576-1589, 1605-1622, 1652-1715
- Body/Services/HealthKitWorkoutStore.swift:2702-2786, 3091-3118
- Body/Services/HealthKitFetchEngine.swift:195-213, 359-427, 488-527, 2088-2193

**Issue**

Permission, primary-source, secondary-source, and combine-by-name mutations update store/engine state before waiting for the current refresh to finish. HealthKitFetchEngine is an actor, but its refresh fans out through many awaited queries. Actor methods are reentrant at those suspension points, and query leaves consult mutable engine selection state rather than a refresh-local snapshot.

One refresh can therefore begin using the old source predicate, resume after a setting mutation, and run other leaves with the new predicate. HealthKitWorkoutStore progressively publishes partial results and later persists them using the store’s current signatures. This is a configuration-generation race, not an unsynchronized-memory race.

**Risk and breadth**

The user can see a dashboard assembled from different HealthKit source or permission policies. That inconsistent result can flow into trends, readiness, widgets, complications, watch seed data, and the disk cache. A corrective refresh normally limits duration, but it does not make the intermediate publication correct, and failure or termination can preserve it.

**Fix**

Capture every refresh input in one immutable Sendable context and pass it into every query leaf. Assign a generation before starting work. Accept progressive and final results only if both generation and context still match the store’s active refresh.

    struct DashboardFetchContext: Sendable, Equatable {
        let generation: UInt64
        let anchorDate: Date
        let permissions: BodyHealthPermissionSelection
        let primarySource: BodyHealthSourceSelection
        let secondarySource: BodyHealthSourceSelection
        let combineSourcesByName: Bool
    }

    guard result.context == activeContext,
          result.context.generation == activeGeneration else {
        return
    }

Do not let leaf queries read mutable selection fields. Setting mutations should invalidate the active generation and start exactly one replacement refresh.

**Recommended tests**

- Delay selected fake HealthKit queries, change each of permission/primary/secondary/combine settings mid-refresh, and complete old queries out of order.
- Assert that no old or mixed progressive value is published after invalidation.
- Assert that disk, widget, and watch publications all carry the winning generation and signatures.

## Medium

### M-01 — Fresh installs can expose fabricated “Preview” workouts as real data

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — store init now uses `WorkoutSnapshotStore.loadOrEmpty()`; `.placeholder` remains for the widget gallery and design previews only.

**Locations**

- Body/Services/HealthKitWorkoutStore.swift:296-302
- BodyShared/Services/WorkoutSnapshotStore.swift:194-200
- BodyMetricsKit/WorkoutMonthSnapshot.swift:194-230, 240-257
- Body/Views/BodyFirstLaunchOverlay.swift:31-106
- Body/Views/MainTabView.swift:61-66

**Issue**

HealthKitWorkoutStore initializes workout state with WorkoutSnapshotStore.loadOrPlaceholder(). When no cache exists, that helper returns a placeholder containing nine fabricated workouts whose source is “Preview.” The first-launch “Not Now” action only dismisses the overlay for the session; it does not replace the placeholder with an honest empty snapshot.

**Risk and breadth**

A new user who declines or postpones Health access can enter the normal Workouts UI and see fake records, totals, and details without a persistent demo-mode label. In a health application, fabricated live-state data is a trust and correctness problem even though it is intentional preview content.

**Fix**

Initialize production state with a load-or-empty API. Reserve placeholder data for SwiftUI previews, screenshots, or an explicit clearly labeled demo mode.

    initialSnapshot = WorkoutSnapshotStore.load()
        ?? .makeEmpty(containing: Date())

**Recommended tests**

- With no snapshot file, initialize the live store and dismiss onboarding; assert zero workouts and no “Preview” source.
- Keep a separate preview fixture test so design-time content remains available.

### M-02 — A completed purchase can return to an idle, locked paywall without explanation

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — a completed-but-not-entitled purchase performs one bounded `customerInfo(fetchPolicy: .fetchCurrent)` re-check, then parks in a new `.completedNotUnlocked` state that replaces the buy card with a dedicated recovery card (purchase disabled, Restore enabled); the entitlement stream clears it on late unlock. (`PurchasesClient` injection deferred with M-16.)

**Locations**

- Body/Services/BodyProStore.swift:89-118, 162-178
- Body/Views/BodyProView.swift:30-39, 93-104

**Issue**

Every non-cancelled RevenueCat purchase result is applied and purchaseState is set back to idle. apply maps a missing or inactive configured entitlement to isPro = false. If product-to-entitlement configuration is wrong or entitlement propagation is delayed, a completed transaction can therefore redisplay the buy card without an actionable error.

**Risk and breadth**

This is not guaranteed on a correctly configured RevenueCat project, but the failure mode is severe for the affected customer: the App Store transaction completes while paid features remain locked, and the UI offers no verification/recovery state.

**Fix**

Require the configured entitlement to be active before declaring the flow complete. On failure, perform one bounded sync/refetch and then present a distinct localized verification-failed state with Restore and support actions.

    let info = result.customerInfo
    guard info.entitlements[Self.entitlementID]?.isActive == true else {
        purchaseState = .verificationFailed
        return
    }
    apply(customerInfo: info)
    purchaseState = .idle

Inject a PurchasesClient rather than calling Purchases.shared directly so all states can be tested.

**Recommended tests**

- Active entitlement, missing entitlement, inactive entitlement, cancellation, transport error, delayed propagation, and successful recovery.
- StoreKitTest sandbox flows for purchase, restore, refund/revocation, reinstall, and another device.

### M-03 — Display-only awake-stage preferences change Sleep Score and Readiness

**Locations**

- Body/Services/HealthKitFetchEngine+Sleep.swift:32-49, 111-128
- BodyWatchSnapshotKit/BodySleepSampleParser.swift:82-153
- BodyMetricsKit/Sleep.swift:479-496
- BodyMetricsKit/ReadinessScoreCalculator.swift:647-650

**Issue**

“Show Awake Under 1 Min” and “Show Awake at Start & End” are presented as chart-display choices, but they are passed into parsing and remove awake intervals from the stored stage snapshot. Sleep Score continuity and readiness then calculate from that filtered snapshot.

**Risk and breadth**

Changing a visualization preference changes derived health scores without any HealthKit data changing. Phone and watch values can also diverge if they do not apply the same preference generation.

**Fix**

Preserve a canonical unfiltered, normalized stage timeline for calculations. Apply awake visibility rules only when producing chart segments.

    let canonicalStages = parser.normalizedStages(samples)
    let score = calculator.score(canonicalStages)
    let displayedStages = canonicalStages.filtered(for: displayPreferences)

**Recommended tests**

- Assert that both Sleep Score and readiness are invariant across all awake-display preference combinations.
- Assert only chart segment visibility changes.

### M-04 — A separated nap can spuriously improve sleep continuity and readiness

**Locations**

- BodyWatchSnapshotKit/BodySleepFetch.swift:84-117
- BodyWatchSnapshotKit/BodySleepSampleParser.swift:22-40
- BodyMetricsKit/Sleep.swift:479-496
- BodyMetricsKit/ReadinessScoreCalculator.swift:647-650

**Issue**

The wake-day snapshot intentionally preserves naps alongside the main night. continuityCategory and readiness use the flattened snapshot’s earliest-start-to-latest-end dateInterval as the sleep opportunity denominator. With a 23:00–07:00 night and a 14:00–15:00 nap, the daytime gap expands that denominator even though the gap is neither sleep nor explicit awake time.

**Risk and breadth**

Continuity can increase when a distant nap is added, boosting both the Sleep Score category and readiness. The result is mathematically inconsistent with the displayed meaning of continuity.

**Fix**

Calculate continuity from mainSession, or explicitly sum the opportunity intervals for each real sleep session. Naps may still contribute to the Amount category if that is the intended product policy.

**Recommended tests**

- Add the same main night with and without a far-separated nap and assert unchanged continuity/readiness.
- Cover multiple naps and an awake interval inside the main session.

### M-05 — A nap can reset the wake-cycle boundary and remove valid workout drain

**Locations**

- BodyWatchSnapshotKit/BodySleepFetch.swift:84-117
- Body/Services/HealthKitWorkoutStore.swift:2488, 3056, 3174
- BodyWatch/WatchComputeCoordinator.swift:238
- BodyWatchSnapshotKit/WatchMetricsSnapshotBuilder.swift:64

**Issue**

Several consumers use the flattened stageSnapshot.dateInterval.end as the most recent wake time. Because the snapshot includes naps, a 14:00–15:00 nap changes that value from the main night’s 07:00 wake time to 15:00.

**Risk and breadth**

A morning or midday workout can disappear from same-day readiness drain after an afternoon nap, making readiness rebound incorrectly. The same semantics exist in phone and watch calculation paths.

**Fix**

Expose one canonical mainSleepEndDate based on mainSessionInterval.end, with dateInterval.end only as a legacy-data fallback, and use it consistently in all readiness/watch builders.

**Recommended tests**

- Night + morning workout + afternoon nap should retain the workout’s readiness drain.
- Assert phone/watch parity for the same canonical snapshot.

### M-06 — Overlapping stages from the same source can inflate stage totals and scores

**Locations**

- BodyWatchSnapshotKit/BodySleepSampleParser.swift:171-190, 242-246
- BodyMetricsKit/Sleep.swift:237-242, 384-399, 500-515
- BodyTests/BodySleepSampleParserDedupTests.swift:175-205

**Issue**

Single-source explicit stage segments bypass the cross-source normalization path, and overlaps from one writer are preserved. Stage duration(for:) raw-sums segment durations, and Deep/REM score components consume those totals.

**Risk and breadth**

Duplicated or conflicting samples from one HealthKit writer can make total stage minutes exceed actual sleep union time and inflate Deep/REM shares. Existing tests currently preserve the overlap rather than asserting a disjoint timeline.

**Fix**

Normalize each source independently into a non-overlapping timeline before applying cross-source ranking. Collapse same-stage duplicates and define deterministic precedence for conflicting stages.

**Recommended tests**

- Sum of stage durations must never exceed the union of the sleep interval.
- Cover duplicate same-stage samples, conflicting same-source stages, and cross-source priority.

### M-07 — Historical sleep is bucketed before its historical timezone is resolved

**Locations**

- BodyWatchSnapshotKit/BodySleepSessionizer.swift:81-91
- BodyWatchSnapshotKit/BodySleepFetch.swift:96-145
- Body/Services/HealthKitFetchEngine+Sleep.swift:15-18, 85-93
- Body/Services/HealthKitFetchEngine.swift:512-527, 2096-2098, 2278-2280

**Issue**

Sleep sessions are assigned to a wake day using the caller/current calendar. Only afterward does BodySleepFetch resolve HealthKit timezone metadata or the timezone ledger and stamp the result. That later zone cannot repair an already incorrect day bucket. The ledger’s production writes also occur inside sleep fetches, so disabling/hiding Sleep or lacking its permission can leave travel periods unrecorded.

**Risk and breadth**

Travel across large offsets or the date line can associate a night with the wrong date, affecting sleep history, trends, readiness, widgets, and watch seed data. The problem can persist in historical cache entries.

**Fix**

Resolve the best timezone for each session/end instant before deriving its wake day. Record timezone changes independently on app activation and NSSystemTimeZoneDidChange, not as a side effect of successfully fetching Sleep.

**Recommended tests**

- Absolute sample intervals spanning Tokyo/New York travel should map to the intended local wake day.
- Disable Sleep during travel, re-enable later, and verify ledger-based historical mapping.

### M-08 — A transient WatchConnectivity publication failure can strand the latest context

**Locations**

- Body/Services/WatchConnectivityPublisher.swift:228-250, 298-319

**Issue**

On a non-size updateApplicationContext failure, the publisher keeps the context as pending. Pending work is drained by activation completion, but sessionReachabilityDidChange is empty. If the WCSession is already activated, no later activation callback is guaranteed.

**Risk and breadth**

The latest phone snapshot/settings can remain unsent until some unrelated future publication or session reactivation. Watch dashboard, complications, permissions, and source selection can remain stale.

**Fix**

Add a bounded retry state machine with backoff and latest-sequence-wins replacement. Flush on activation, reachability, and other appropriate WCSession transitions; do not require reachability for application-context delivery, but use transitions as retry signals.

**Recommended tests**

- Inject one transient failure followed by success and assert automatic resend.
- Queue several generations while failed and assert only the newest is delivered.

### M-09 — A malformed or future permission payload fails open to all app-level permissions

**Locations**

- BodyMetricsKit/BodyHealthSelections.swift:265-283
- BodyWatch/WatchMetricsModel.swift:126-127, 407-430

**Issue**

Permission parsing compactMaps recognized tokens. If a present payload contains only unknown tokens, parsing returns the default selection, which enables all metrics. The watch stores the raw unvalidated string and considers synchronization complete based on presence.

**Risk and breadth**

A corrupted payload or a future-version payload read by an older app can broaden the app’s metric selection. This does not bypass iOS HealthKit authorization, but it violates the user’s in-app privacy/visibility policy and can trigger additional authorized reads.

**Fix**

Distinguish “field absent on a fresh install” from “field present but invalid.” Version the payload. Reject an all-unknown present value and retain the last valid selection or fail closed; preserve recognized values in a mixed known/unknown payload.

**Recommended tests**

- Absent, empty, all-unknown, mixed known/unknown, duplicate, and future-version payloads.
- Assert the watch never expands selection after an invalid update.

### M-10 — Watch compute-seed semantic deduplication is defeated by a transport timestamp

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — `WatchComputeSeed` now has a custom `encode(to:)` that omits `publishedAt` (CodingKeys/decode untouched for old payloads), so the store's byte compare dedups semantically.

**Locations**

- BodyWatchSnapshotKit/WatchComputeSeed.swift:118-128, 297-308
- Body/Services/HealthKitWorkoutStore.swift:3520, 3582-3587
- BodyWatch/WatchComputeSeedStore.swift:57-80
- BodyWatch/WatchMetricsModel.swift:204-214

**Issue**

publishedAt is documented as transport metadata and is refreshed for every publication, but deterministic encoding includes it. WatchComputeSeedStore compares exact bytes, so otherwise identical seeds are always considered changed.

**Risk and breadth**

Every redundant phone publication rewrites disk and increments watch compute generation. That can cancel/discard useful work or make current computation wait behind a stale multi-query pass, increasing latency and battery use.

**Fix**

Compare a semantic content hash that excludes publishedAt, or normalize the timestamp before equality. Keep publishedAt only for diagnostics/freshness if needed.

**Recommended tests**

- Two payloads differing only in publishedAt must return unchanged.
- A real permission/source/metric change must still increment generation.

### M-11 — Watch seed I/O APIs conflate “unchanged” with “failed”

**Locations**

- BodyWatch/WatchComputeSeedStore.swift:62-81, 141-151
- BodyWatch/WatchMetricsModel.swift:204-214, 296-318

**Issue**

save returns false for both equal bytes and a URL/write failure. clear returns false for both an absent file and removal failure. Intake and reset paths cannot distinguish a no-op from failure, and generation invalidation depends on the resulting Boolean.

**Risk and breadth**

A write failure can leave an old seed or old in-flight compute eligible. A failed clear can allow previously invalidated metrics to reappear on a later launch.

**Fix**

Return a structured result such as unchanged, written, removed, or failed(Error). On a persistence failure, invalidate in-memory generations and fail closed even if cleanup cannot complete.

**Recommended tests**

- Fault-inject URL, encode, write, and remove failures.
- Verify old compute cannot publish after any failed replace/reset.

### M-12 — Most HealthKit continuation queries are not cancellation-aware

**Locations**

- Body/Services/HealthKitFetchEngine.swift:741, 816, 886, 987, 1052, 1119, 1572, 1845, 1958, 2043
- BodyWatchSnapshotKit/BodyHealthQuantityFetch.swift:74, 118
- BodyWatchSnapshotKit/BodySleepFetch.swift:60, 179
- BodyWatch/WatchHealthStore.swift:115
- BodyWatch/WatchComputeCoordinator.swift:35-60

**Issue**

Only a small subset of engine queries use the cancellation wrapper. Most withCheckedContinuation bridges do not stop the underlying HKQuery when their Swift Task is cancelled. The watch coordinator awaits an old fan-out before starting the next generation.

**Risk and breadth**

After source, permission, seed, or lifecycle changes, stale queries continue consuming HealthKit work. A slow or never-completing query can delay the current watch generation and contributes to the month-loading retry issue in L-01.

**Fix**

Generalize the existing lock-safe cancellable-query wrapper so cancellation stops the HKQuery and resumes exactly once. Allow a replacement watch generation to begin without awaiting obsolete work.

**Recommended tests**

- Cancel before query start, during execution, and concurrently with completion.
- Assert exactly-once continuation resume and that a new generation is not blocked by a noncompleting old query.

### M-13 — Split average heart rate can be fabricated across gaps or from another split

**Locations**

- BodyMetricsKit/WorkoutSplitCalculator.swift:425-469
- BodyTests/WorkoutSplitCalculatorTests.swift:619-638

**Issue**

Average-HR integration interpolates across every adjacent sample without a maximum allowed gap. If a split has no coverage, it falls back to the nearest sample anywhere in the workout. A current test explicitly expects an empty later split to reuse 148 BPM from the prior split.

**Risk and breadth**

Long sensor dropouts appear as measured averages, and a split with no HR data can display another split’s heart rate. This undermines workout-detail accuracy.

**Fix**

Cap interpolation to a cadence-aware threshold, restrict boundary fallback to a small tolerance around the split, and return nil/“—” when coverage is insufficient. Optionally expose coverage percentage.

**Recommended tests**

- Empty split, long middle dropout, one boundary sample, sparse valid coverage, and watch pause intervals.

### M-14 — Effort calibration applies the target day’s resting HR to every prior workout

**Locations**

- Body/Services/HealthKitWorkoutStore.swift:722-739
- BodyMetricsKit/WorkoutEffortEstimator.swift:302-315, 393-412, 629-648

**Issue**

The store supplies one target-day resting-HR scalar. Calibration re-scores every prior workout through helpers that read that same scalar rather than each prior workout’s contemporaneous resting HR.

**Risk and breadth**

Real fitness, illness, or recovery changes can be interpreted as user-rating bias. Suggested effort and optional Auto-Apply HealthKit writes can shift by the calibration cap even when the user’s rating behavior is stable.

**Fix**

Carry day-keyed resting HR for each calibration workout, store the estimator basis with prior calibration records, or use one consistent non-HRR basis for both target and priors.

**Recommended tests**

- Keep workout data/ratings equal while varying target and prior-day RHR independently.
- Assert calibration reflects rating bias rather than physiological baseline drift.

### M-15 — Two live localization entries guarantee the catalog coverage test fails

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — live sleep explanation translated (en + zh-Hans, stale duplicate deleted) and “v3” filled following the v1/v2 pattern; `testChineseLocalizationCatalogsAreComplete` is green.

**Locations**

- Body/Localizable.xcstrings:1764-1766
- Body/Views/Health/BodyHealthMetricDetailView.swift:2238
- Body/Localizable.xcstrings:7963-7965
- Body/Views/BodySettingsView.swift:1898
- BodyTests/ProjectConfigurationTests.swift:2607-2645

**Issue**

The live sleep-score explanation has an empty localization entry, and “v3” is also an empty entry. The configuration test force-unwraps localizations for every nonempty catalog key and requires translated English and Simplified Chinese values.

**Risk and breadth**

The current test is statically guaranteed to fail at one of these entries, and the sleep explanation falls back to its English source text in Chinese UI. The stale prior explanation is translated but no longer matches the live text.

**Fix**

Translate the current sleep explanation and remove/update the stale entry. For “v3,” either provide explicit values or mark it nontranslatable and update the test to intentionally skip entries whose shouldTranslate flag is false.

**Recommended tests**

- Keep the catalog coverage test, but make its nontranslatable policy explicit.
- Add a zh-Hans smoke test for the sleep explanation and Settings version row.

### M-16 — Production service singletons and hosted-test startup prevent isolation of critical flows

**Locations**

- Body/Services/BodyProStore.swift:56-156
- Body/BodyApp.swift:15-24, 35-48
- BodyTests/ProjectConfigurationTests.swift:2517-2581
- body.xcodeproj/project.pbxproj:894-935

**Issue**

BodyProStore calls Purchases.shared directly. Existing monetization tests mainly assert source text and cached boolean behavior. BodyTests are hosted in Body.app, whose launch path configures RevenueCat/WatchConnectivity and starts HealthKit sync plus an entitlement refresh, with no test-service override.

**Risk and breadth**

Unit tests can couple to network, HealthKit authorization, App Group files, and singleton state. The purchase state machine, refresh race, persistence failures, and lifecycle behavior cannot be tested deterministically.

**Fix**

Introduce small PurchasesClient, HealthKitClient, WatchSessionClient, Clock, and SnapshotRepository protocols. Construct AppServices at the composition root and supply no-op/fake services to hosted tests. Keep truly pure tests unhosted where practical and retain a separate explicit integration scheme.

**Recommended tests**

- Purchase/restore state matrices with a fake client.
- App launch with no service side effects in unit-test mode.
- Parallel tests using separate temporary snapshot repositories.

### M-17 — Metric detail rendering repeatedly rebuilds a whole-history workout index

**Locations**

- Body/Views/Health/BodyHealthMetricDetailView.swift:742-793, 1753-1806
- Body/Views/Health/BodyHealthMetricDetailView.swift:403, 1369

**Issue**

workouts(on:) traverses every loaded month/day, flatMaps all workouts, rebuilds a UUID dictionary, filters, and sorts. Multiple body helpers request the same result independently. Readiness chart scrubbing updates selection state and can cause this work to recur during gestures.

**Risk and breadth**

Cost grows with every history month loaded. On older phones or large libraries, health detail scrubbing can hitch and allocate heavily.

**Fix**

Maintain an interval/date workout index in the store, or cache the selected-day result by day plus a workout-snapshot revision. Compute dayWorkouts once per body evaluation and pass it to all consumers.

**Recommended tests**

- Load many synthetic months and assert index-build count is unchanged while only chart selection moves.
- Add signposts/performance tests around day selection and scrubbing.

### M-18 — The rolling month carousel can show a different month from its binding

**Locations**

- Body/Views/BodyMonthYearPicker.swift:87-92, 209-216, 237-245

**Issue**

When the selected oldest month falls out of the rolling 36-month list, the visual index remains zero and now points to the new oldest month. The bound selectedMonth/selectedYear remain the removed month because a missing bound value is silently ignored.

**Risk and breadth**

The header can show one month while the Workouts content and subsequent navigation still use another.

**Fix**

Define one absent-selection policy: either retain the selected item in the list or clamp the binding and visual index together through the selection callback. Never update only the visual fallback.

**Recommended tests**

- Select the oldest month, advance the reference date one month, and assert displayed label, binding, and loaded snapshot remain identical.

### M-19 — Home background editing is inaccessible without precision drag gestures

**Locations**

- Body/Views/BodySettingsView.swift:1281-1293, 1495-1634, 1694-1716, 1777-1797

**Issue**

Divider and color controls are drag-only. Disabled state uses allowsHitTesting rather than accessibility semantics. Profile selection uses an invisible Color.clear button label while visible text is a sibling, and deletion is exposed only through a custom swipe/reveal interaction.

**Risk and breadth**

VoiceOver, Switch Control, keyboard users, and users unable to make precise two-dimensional drags cannot reliably configure, select, rename, or delete this paid feature.

**Fix**

Make the visible row the actual Button label; expose selected traits plus named Rename/Delete actions. Add accessibilityAdjustableAction for divider percentages and labeled ColorPicker fallbacks. Use disabled and intentional accessibility visibility rather than hit testing alone.

**Recommended tests**

- Accessibility Inspector review.
- XCUI flow that selects, adjusts, renames, and deletes a profile without drag gestures.

### M-20 — Critical runtime flows have no UI or widget-provider test target

**Locations**

- body.xcodeproj/project.pbxproj:304-453
- body.xcodeproj/xcshareddata/xcschemes/BodyWidgetExtension.xcscheme:26-32

**Issue**

The project contains phone and watch unit-test bundles but no XCUI target and no executable widget-provider runtime test target; the widget scheme TestAction is empty. The roughly 1,000 pure/configuration tests are valuable, but they cannot exercise onboarding, scene lifecycle, real navigation, StoreKit UI, WidgetKit scheduling, or accessibility.

**Risk and breadth**

Several highest-risk user journeys can regress while source-shape tests remain green: first launch/permission denial, purchase and restore, widget empty/Pro/midnight states, watch foregrounding, and Chinese layout.

**Fix**

Add a small deterministic UI smoke suite with launch arguments and injected services. Add provider-level tests that construct timelines at controlled dates without requiring the WidgetKit host.

**Recommended tests**

- See the dedicated Test Coverage Gaps section below.

## Low

### L-01 — A genuinely hung month load remains cached after the 15-second UI timeout

**Locations**

- Body/Views/BodyWorkoutsView.swift:469-518

**Issue**

Ordinary failed loads correctly return false and remove their cached Task. A noncompleting or very long HealthKit load is different: the UI timeout clears only pendingMonthSelection, while monthLoadTasks continues to hold and reuse the same Task. Later taps time out against that task again.

**Risk and breadth**

One month can remain unretryable until the view/app is recreated, and the task can retain view-related state. This requires a hung query rather than a normal error, so it is Low by itself; M-12 makes the trigger credible.

**Fix**

Move coalescing into a store/coordinator with generation-aware deadlines. Once the underlying queries are cancellation-safe, evict and cancel the matching generation on timeout; a late old completion must not remove or navigate for a newer request.

### L-02 — Sleep surfaces do not schedule an exact midnight invalidation

**Locations**

- BodyWidgetExtension/SleepStagesWidget.swift:35-59
- BodyWidgetExtension/HealthMetricWidget.swift:52-77
- BodyWatchWidgetExtension/WatchComplicationsProvider.swift:22-36
- BodyWatch/WatchMetricsModel.swift:102-116
- BodyWatch/BodyWatchApp.swift:21-32

**Issue**

Providers sanitize sleep when constructing their current entry, then request the next reload after a 30-minute interval. WidgetKit may defer that earliest reload. The watch sanitizes on appearance, but its scene-active path can enter freshness throttles without first applying the day boundary.

**Risk and breadth**

Already-rendered widget, complication, or watch pixels can label yesterday’s sleep as current for some time after midnight. Phone render sites generally call asOf and are not included in this claim.

**Fix**

Append an explicitly future-dated sanitized entry at the next local midnight, as WorkoutCalendarProvider already does for month rollover. Sanitize synchronously before watch foreground throttling.

### L-03 — Dashboard main/sidecar/freshness values do not share a commit generation

**Locations**

- Body/Services/HealthDashboardSnapshotStore.swift:165-204, 208-238
- Body/Services/HealthKitWorkoutStore.swift:394-406, 1229-1260, 3112-3120, 3299-3301

**Issue**

The stripped main snapshot is written before the intraday sidecar, while freshness metadata advances separately. A termination or write failure can pair generations when source/combine signatures happen to match.

**Risk and breadth**

Hydration validation and incremental detail loading limit the likely result to stale/missing intraday chart samples, avoidable cache churn, or an overstated freshness/watch watermark—not broad corruption of the entire dashboard.

**Fix**

Put a generation UUID/content hash in both files, write the sidecar first, and make the main envelope the commit record. Advance freshness/signatures only after a successful matching commit.

### L-04 — Home trend lines visually bridge missing measurements

> **Status (2026-08-03):** Intentional design — won’t fix. The user wants the preview line to look filled even with gaps in the actual data. Applies equally to the `BodyHealthMetricCard` polyline; do not re-flag either in future reviews.

**Locations**

- Body/Views/Health/BodyHomeTrendCard.swift:567-590
- BodyShared/Components/HealthWidgetTrendChartView.swift:207-248
- BodyWatch/WatchSparklineView.swift

**Issue**

The home line plot removes nil values and draws one continuous path through the remaining points. A value/nil/value sequence appears connected, implying measurements or interpolation through the gap.

**Risk and breadth**

This is a presentation error on line-style Home comparisons; it does not modify stored health data.

**Fix**

Retain optional positions and draw one path per contiguous nonnil run. Reuse the correct gap behavior already present in the widget/watch chart implementations.

### L-05 — Overlapping alternate-icon requests have no latest-request policy

**Locations**

- Body/Views/BodySettingsView.swift:669-692, 2935-2964

**Issue**

All icon tiles remain enabled while UIApplication.setAlternateIconName is in flight, and completions have no token. Reverse completion order can dismiss for an older tap, show a stale error, or leave an unexpected final icon.

**Fix**

Disable the grid during one request or use a latest-request-wins token. Wrap UIApplication behind an injectable icon service and test reverse completions.

### L-06 — Watch detail selection is not reconciled after its metric list changes

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — the pager reconciles via `.onChange(of: metrics.map(\.kind))`, snapping selection back to `initialKind` without animation when the selected metric disappears.

**Locations**

- BodyWatch/WatchMetricDetailPager.swift:25-57

**Issue**

If the currently selected noninitial metric is removed by a settings/phone update, TabView retains a selection value for which no tag exists.

**Risk and breadth**

The open watch detail pager can show a blank/wrong page until navigation resets.

**Fix**

Observe metrics.map(\.kind) and clamp selection without animation to initialKind or the first remaining metric.

### L-07 — Watch freshness throttles treat future timestamps as fresh

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — freshness split by clock domain: watch-local stamps reject negative elapsed (and a future persisted compute stamp is dropped at load); phone-stamped dates tolerate the 30-minute stale-interval skew so ordinary phone/watch drift doesn’t read as stale.

**Locations**

- BodyWatch/WatchMetricsModel.swift:479-492, 666-695

**Issue**

Freshness uses now.timeIntervalSince(date) <= limit without rejecting materially negative elapsed values. Clock rollback or a future persisted timestamp can suppress heart-rate/full recomputation until wall time catches up.

**Fix**

Treat only a bounded 0...limit interval as fresh, allow a small documented clock-skew tolerance, and invalidate larger negative values.

### L-08 — Watch source discovery serializes independent HealthKit kinds

**Locations**

- BodyWatch/WatchSourceResolver.swift:39-77, 107-155
- Body/Services/HealthKitFetchEngine+SourceOptions.swift:49-65

**Issue**

The watch awaits source reads one kind at a time, while the phone groups independent work. Each read can issue a HealthKit query.

**Risk and breadth**

Source refresh latency and watch battery cost scale with the number of selected kinds.

**Fix**

Use a bounded task group and preserve deterministic reduction order. Cache identical quantity/source requests within one refresh.

### L-09 — The timezone ledger assumes records are appended chronologically

**Locations**

- Body/Services/BodyTimeZoneLedger.swift:34-53

**Issue**

Lookup selects the last qualifying stored record rather than the qualifying record with the greatest effective date. Clock rollback, restored state, or out-of-order import can append an older record after a newer one.

**Fix**

Sort/coalesce on insertion or select max(by: effectiveDate) at lookup. Test out-of-order records and equal timestamps.

### L-10 — Sleep source identity normalization depends on the current locale

**Locations**

- BodyWatchSnapshotKit/BodySleepSampleParser.swift:156-168
- BodyWatchSnapshotKit/BodyHealthSourceResolver.swift:67-100

**Issue**

The parser lowercases/normalizes source identity with Locale.current while the shared source picker uses en_US_POSIX. Phone and watch in different locales can produce different identity keys for the same source name, especially around locale-sensitive “I” mappings.

**Fix**

Route both through the shared POSIX identity helper. Add Turkish-locale and mixed-device-locale tests.

### L-11 — HealthKit write validation is incomplete and store publication can disagree with the persisted value

**Locations**

- Body/Services/HealthKitFetchEngine+Write.swift:45-85, 142-160
- Body/Services/HealthKitWorkoutStore.swift:659-678

**Issue**

Weight/body-fat validation does not reject every nonfinite, implausible, future-date, or both-values-missing request atomically. Effort saving clamps the HealthKit value, but the store records the original score as its override.

**Risk and breadth**

Current UI bounds make invalid inputs unlikely, but internal/test callers can create a transient UI/persistence disagreement or attempt an invalid HealthKit write.

**Fix**

Validate the complete request first, return a typed invalidInput error, clamp/normalize once, and publish exactly the value passed to HealthKit.

### L-12 — Restore with no active entitlement has no user-visible outcome

> **Status (2026-08-03):** Fixed in 0.9.10 build 21 — restore distinguishes three outcomes: active entitlement → idle/owned; lifetime product purchased but entitlement inactive (`allPurchasedProductIdentifiers`) → the `.completedNotUnlocked` recovery card; no purchase at all → a localized “No purchases to restore.” notice via the existing `.failed` path. Notices clear automatically if Pro later unlocks.

**Locations**

- Body/Services/BodyProStore.swift:121-129
- Body/Views/BodyProView.swift:54-63, 140-175

**Issue**

A successful restore request that finds no active entitlement returns to idle with no “nothing to restore” or success message.

**Fix**

Publish localized restored, nothingToRestore, revoked, and failed outcomes. Keep Restore available and direct ambiguous cases to support.

### L-13 — The Body Pro SwiftUI preview remains permanently in “Checking”

**Locations**

- Body/Services/BodyProStore.swift:52-56
- Body/Views/BodyProView.swift:25-28, 93-97, 580-584

**Issue**

The unconfigured preview store never resolves entitlement state, so the design-time preview cannot exercise the real free or Pro layout.

**Fix**

Provide explicit preview fixtures for unresolved, free, purchasing, failed, and Pro states.

### L-14 — Free-form localized error descriptions are marked public in unified logs

**Locations**

- Body/Services/HealthKitFetchEngine.swift:66-69
- BodyShared/Services/WorkoutSnapshotStore.swift:60-62, 100-102
- Body/Services/HealthDashboardSnapshotStore.swift:178-194
- BodyWatchShared/Services/WatchMetricsSnapshotStore.swift:65-67
- Body/Services/RevenueCatConfiguration.swift:26

**Issue**

No health measurement or auth token is intentionally logged, and the RevenueCat appl_ key is public by design. However, arbitrary error.localizedDescription values are interpolated as public; they can contain file paths or internal diagnostic context. RevenueCat is also configured at info verbosity.

**Fix**

Log stable public context plus NSError domain/code, mark free-form descriptions private, and reduce RevenueCat release verbosity to warning/error while retaining richer debug logging.

### L-15 — An open metric day picker does not explicitly roll its “today” window at midnight

**Locations**

- Body/Views/Health/BodyHealthMetricDetailView.swift:431-451, 708-710, 1523-1549

**Issue**

The free-day window and Today/future styling derive from Date() during rendering, but the view has no calendar-day notification or scene-phase reconciliation to guarantee a render after midnight.

**Risk and breadth**

A detail page left active across midnight can keep stale Today styling or free-day bounds until unrelated state changes.

**Fix**

Maintain an injectable today state and update it on NSCalendarDayChanged, timezone changes, and foregrounding.

## Suggestion

### S-01 — Set an explicit file-protection and backup policy for health caches

**Locations**

- Body/Services/HealthDashboardSnapshotStore.swift:180-240
- BodyShared/Services/WorkoutSnapshotStore.swift
- BodyShared/Services/HealthWidgetSnapshotStore.swift:82-90
- BodyWatchShared/Services/WatchMetricsSnapshotStore.swift:58-64
- BodyWatch/WatchComputeSeedStore.swift

Atomic writes and sandboxing are already present, and this review did not find plaintext credential storage. Still, health-derived caches rely on default file attributes and may be backed up unnecessarily.

Choose protection intentionally: complete protection for app-only private caches, or complete-until-first-user-authentication where widgets/complications must read after reboot. Mark regenerable caches excluded from backup. Verify the expected locked-device widget behavior before tightening protection.

### S-02 — Enable staged strict Swift concurrency checking

**Locations**

- body.xcodeproj/project.pbxproj:787, 828, 857, 886, 909, 933 and watch/widget counterparts

Targets remain on Swift 5 mode without SWIFT_STRICT_CONCURRENCY. This concurrency-heavy project would benefit from enabling targeted checking, clearing warnings, then moving to complete checking/Swift 6. Add a configuration assertion so the setting does not silently regress.

This will not by itself fix H-01, which is a logical reentrancy issue, but it will expose unchecked Sendable/isolation boundaries early.

### S-03 — Split integration hubs around explicit service boundaries

Prioritize these seams:

- DashboardRefreshCoordinator: immutable context, generation, progressive/final acceptance.
- DashboardSnapshotRepository: versioned transaction and freshness commit.
- SleepModelBuilder: canonical normalization, main session, naps, presentation filtering.
- PurchasesClient and BodyProStateMachine.
- WorkoutMonthLoader with cancellation/deadline/coalescing.
- AppBoundaryClock for day, month, timezone, and scene changes.

Keep HealthKitWorkoutStore as the observable composition surface, but move policy and side effects into testable collaborators.

### S-04 — Treat RevenueCat dashboard verification as a release gate

**Locations**

- Body/Services/RevenueCatConfiguration.swift:15, 20
- Body/Services/BodyProStore.swift:21
- Body.storekit:31
- body.xcodeproj/xcshareddata/xcschemes/Body.xcscheme:66-68

The source key is the expected public appl_ form, the product identifier matches Body.storekit, and the StoreKit configuration is attached to the scheme. Source code cannot prove the external RevenueCat product-to-entitlement attachment. Before release, verify the exact app/key/environment, entitlement “Body: Health Dashboard Pro,” product attachment, offering, restore, refund/revocation, reinstall, and another-device behavior.

### S-05 — Harden pure formatters against nonfinite cached/model input

**Locations**

- BodyMetricsKit/WorkoutSummary.swift:55-64
- BodyMetricsKit/WorkoutSummary.swift duration-to-Int helpers

Normal HealthKit/cache paths currently filter values sufficiently that this is not a confirmed runtime defect. For defense in depth, reject nonfinite max-HR/duration values before Double-to-Int conversion and return an unavailable placeholder. Add NaN and infinity model-fixture tests.

## Test Coverage Gaps

The pure-model test base is a project strength, but the following critical paths need the most urgent executable coverage:

1. **Refresh generation and configuration changes**
   - Delayed fake HealthKit queries.
   - Permission, primary/secondary source, and combine-by-name changes during a refresh.
   - Progressive, final, disk, widget, and watch generation agreement.

2. **Canonical sleep semantics**
   - Score/readiness invariance under display preferences.
   - Main night plus separated naps.
   - Same-source overlap normalization.
   - Historical timezone/date-line travel.
   - Phone/watch parity.

3. **First launch**
   - No cache and no Health permission.
   - “Not Now,” denial, partial authorization, and later enablement.
   - Assert no fabricated production workout data.

4. **Purchases**
   - Full BodyProStore state matrix through an injected client.
   - StoreKitTest purchase, cancel, verification anomaly, restore-none, restore-owned, refund/revocation, reinstall, another device, and customer-center return.

5. **Persistence and transport fault injection**
   - Dashboard failure between sidecar/main/freshness commits.
   - Watch seed encode/write/remove failures.
   - WatchConnectivity transient failure and latest-generation retry.

6. **Cancellation and recovery**
   - Exactly-once continuation behavior when HKQuery cancellation races completion.
   - Hung month load, timeout, second attempt, and late first completion.
   - Watch old-generation query that never completes.

7. **Calendar/lifecycle behavior**
   - Widget timelines one minute before midnight.
   - Watch foreground after midnight while compute throttles are fresh.
   - Metric detail and month carousel across day/month rollover.
   - Clock rollback and timezone changes.

8. **UI, localization, and accessibility**
   - zh-Hans smoke coverage for Home, health details, Settings, and paywall.
   - Background editor/profile operations without drag gestures.
   - Alternate-icon reverse completions and watch pager list mutation.
   - Deep links/navigation restoration and empty/error/loading states.

Tests that assert source substrings or configuration shape should remain secondary guards; they are not substitutes for state-machine and user-flow tests.

## Reviewed Areas That Look Sound

- No production try!, as!, fatalError, or precondition path was found that creates an obvious user-triggered crash. Test-only force operations were not treated as runtime defects.
- The reviewed @unchecked Sendable wrappers use locking around their mutable state. Strict-concurrency checking is still recommended.
- Query outcome/cache logic generally distinguishes confirmed empty results from fetch failures, avoiding stale-cache deletion on transient errors.
- Cache epoch/tombstone handling and watch snapshot generation checks are careful and should be preserved.
- Individual snapshot writes use deterministic encoding/atomic replacement or save-if-changed patterns. L-03 concerns cross-file commit identity, not torn bytes inside one atomic file.
- HealthKit routes are bounded before rendering, the full-screen map dismantles delegates/overlays/annotations, and share-photo loading includes cancellation/latest-selection guards.
- SwiftUI root ownership is generally correct: the app owns long-lived reference state with StateObject and descendants consume it through environment/observation.
- Expensive intraday and sleep consistency chart calculations have focused memoization.
- Dark-only appearance is intentional in the current product and was not reported as a theme bug.
- App Group and HealthKit entitlements, privacy manifests, usage descriptions, and StoreKit product identifiers are internally consistent.
- The RevenueCat public SDK key is not a secret and was not reported as credential leakage.
- No custom networking/auth-token persistence layer exists beyond SDK-managed RevenueCat behavior.

## Priority Fix List

1. **Make dashboard refreshes immutable and generation-checked (H-01).**  
   This is the only confirmed High issue and has the broadest data-consistency impact. It also creates the correct foundation for cancellation, cache commits, widgets, and watch publication.

2. **Separate canonical sleep data from presentation and main-session semantics (M-03 through M-06).**  
   One coherent model change fixes four score/readiness accuracy defects and prevents phone/watch semantic drift.

3. **Remove placeholder workouts from production initialization (M-01).**  
   This is small, low-risk work with an immediate trust benefit for every new/permission-declining user.

4. **Verify entitlements after purchase and inject PurchasesClient (M-02, M-16).**  
   Prevent the worst paid-user failure and unlock deterministic monetization tests.

5. **Resolve historical timezone before sleep bucketing and record zones independently (M-07).**  
   This prevents durable travel-related misclassification that is difficult to repair later.

6. **Repair watch transport/seed recovery (M-08 through M-11).**  
   Structured I/O outcomes, semantic dedupe, and retry remove a cluster of stale-state and wasted-compute failures.

7. **Make HealthKit queries cancellation-aware (M-12, L-01).**  
   This improves lifecycle correctness, watch responsiveness, battery use, and month-load recovery.

8. **Correct split HR and effort calibration math (M-13, M-14).**  
   These are user-visible workout metrics and can feed HealthKit writes; correctness should precede UI polish.

9. **Fix the two empty localization entries (M-15).**  
   Restore a green catalog test and prevent English fallback in the Chinese sleep explanation.

10. **Add the generation, sleep, purchase, and fault-injection tests before broader refactoring (M-16, M-20).**  
    These tests define the behavioral contract and reduce the risk of extracting the large integration hubs.

11. **Index workout queries and reconcile rolling UI state (M-17, M-18, L-05, L-06).**  
    Expected benefit: smoother detail interaction and fewer visual/data mismatches.

12. **Close accessibility and exact-boundary gaps (M-19, L-02, L-15).**  
    Expected benefit: paid customization is usable by assistive-technology users, and sleep/date UI stays truthful across calendar changes.
