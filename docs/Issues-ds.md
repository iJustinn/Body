# Body — Issues Report (Data Science & Full Project Audit)

Audit of branch `body-v0.5.2` on 2026-05-18. Read-only review; no code was modified.

Severity legend: **Critical** (data loss / crash / store-blocking), **High** (incorrect behavior or significant UX regression under normal use), **Medium** (bug or hygiene risk under specific conditions), **Low** (quality, performance, or maintainability delta).

---

## 1. Project Review Summary

Body has evolved from v0.3.9 to v0.5.2 (build 4) with substantial engineering improvements: HealthKit fetch was extracted to a dedicated `actor` (`HealthKitFetchEngine`), N+1 queries were eliminated via OR-compound predicates and bounded `withTaskGroup`, cold-start latency was cut with persisted `lastSuccessfulRefreshDate`, progressive publishing streams dashboard data, and `Task.detached` isolation keeps readiness recompute and JSON saves off the main thread.

The code is clean and well-structured for an iOS SwiftUI app of this complexity. No force-unwraps, no `fatalError`, no leftover `Calendar.current` callers, no TODO/FIXME markers in source. Error handling is consistent through `do/catch` blocks with `os.Logger` fallbacks.

This audit surfaces 16 items — focused on one critical data science bug (readiness calculator ignores user-set sleep goal), several modeling inconsistencies, structural hypertrophy, and missing test coverage for the most mathematically sensitive component.

Areas reviewed: app entry / scene phase, HealthKit ingestion (engine + store), readiness calculator (all four components, baselines, scoring functions), workout aggregation, snapshot persistence (file + app-group + UserDefaults migration), Summary dashboard / detail screens, Workouts tab, Settings, Body Pro, widgets, entitlements, privacy manifests, project build settings, and all four test files.

---

## 2. Issue List

### Critical Bugs

#### C1. Readiness sleep component always uses hardcoded 8-hour goal, ignoring user's stored sleep duration preference

- **Severity:** Critical
- **Related files:**
  - `Body/Models/Readiness/ReadinessScoreCalculator.swift:241`
  - `Body/Views/BodySettingsView.swift:18,381,454-456`
- **Description:** The `ReadinessScoreCalculator.sleepComponent` normalizes sleep duration against `BodySleepDurationGoal.defaultDuration` (8 hours / 28,800 seconds):
  ```swift
  // ReadinessScoreCalculator.swift:241
  let durationProgress = min(max(duration / BodySleepDurationGoal.defaultDuration, 0), 1.10)
  ```
  The user can set a custom sleep goal via Settings > Metrics > Sleep Goal, which is stored in `UserDefaults` under `sleepDurationGoalMinutesKey` (range: 4–12 hours). The Settings sheet controls this value, and `BodyHomeView` reads it correctly when computing `SleepScoreSummary`:
  ```swift
  // BodyHomeView.swift:2985 — CORRECTLY uses user's goal
  idealSleepDuration: BodySleepDurationGoal.duration(from: sleepDurationGoalMinutes),
  ```
  But the Readiness calculator has no access to this stored preference — it is a static enum method with no `UserDefaults` parameter. Every readiness score computation on every day uses exactly 8 hours regardless of the user's actual goal.
- **Why it matters:** A user who sets a 6.5-hour sleep goal (or a 9-hour goal) gets readiness scores that diverge from the app's own sleep score. The Sleep detail page might show a "Good" sleep score (computed against the user's goal), while the Readiness score shows a depressed score because it compares the same sleep duration against a different (hardcoded) standard. Users cannot trust the readiness metric if one of its two sleep sub-signals (duration) is anchored to a wrong baseline. Readiness is a headlining feature — this is a correctness regression.
- **Suggested fix:** Thread the stored sleep goal into the readiness calculator. Simplest path: add an `idealSleepDuration: TimeInterval` parameter to `ReadinessScoreCalculator.summary()` and `sleepComponent()`, defaulting to `BodySleepDurationGoal.defaultDuration`. Have `HealthKitWorkoutStore.updateHealthDashboardSnapshot` read `@AppStorage(BodyAppearancePreference.sleepDurationGoalMinutesKey)` and pass the value through. Because `ReadinessScoreCalculator.dailySeries()` recomputes readiness for every day in a trend window, it should also accept and forward this parameter.
- **Risks / dependencies:** The calculator lives in `Body/Models/Readiness/` — a pure model with no SwiftUI dependency. The `@AppStorage` value is read from `UserDefaults` in the view layer; passing it down through `HealthKitWorkoutStore` → `HealthDashboardSnapshot.recalculatingReadiness` → `ReadinessScoreCalculator` is the cleanest approach. No data migration needed — existing cached readiness values will be recomputed on the next refresh with the correct goal.

### Data Processing / Modeling Issues

#### D1. Wrist temperature baseline uses simple arithmetic mean in UI while Readiness calculator uses robust median

- **Severity:** Medium
- **Related files:**
  - `Body/Views/BodyHomeView.swift:72-80` (`wristTemperatureBaseline`)
  - `Body/Models/Readiness/ReadinessScoreCalculator.swift:70-112` (`robustBaseline`)
- **Description:** The `wristTemperatureBaseline` helper in `BodyHomeView.swift` computes the average wrist temperature as a simple arithmetic mean across all available year-long points:
  ```swift
  return finiteValues.reduce(0, +) / Double(finiteValues.count)
  ```
  The Readiness calculator's `robustBaseline` method uses the median and a robust spread estimate (1.4826 × MAD), then computes a z-score. The mean is sensitive to outliers (a single fever night can shift the baseline), while the median is not. The Readiness vitals component correctly uses the median-based baseline for wrist temperature anomaly detection; the UI display uses a different (less robust) estimate.
- **Why it matters:** The baseline deviation shown on the wrist temperature card can disagree with the Readiness vitals driver for the same day. A user sees "Baseline +0.3°C" on the card but no wrist-temperature driver in Readiness (or vice versa), reducing trust in both surfaces.
- **Suggested fix:** Either (a) replace the UI mean with the median from the same `robustBaseline` call, or (b) add a shared `HealthTrendSeries.robustBaseline(floor:)` method that both surfaces call. Option (b) is cleaner and prevents future drift.
- **Risks / dependencies:** Low. The mean and median will agree on typical data; the divergence only appears with outliers.

#### D2. Readiness `dailySeries()` recomputes full readiness from scratch for every day — O(n²) trend generation

- **Severity:** Medium
- **Related files:** `Body/Models/Readiness/ReadinessScoreCalculator.swift:122-155`
- **Description:** `dailySeries()` iterates day-by-day over a date range (up to 365 days for a Year trend) and calls `summary()` for each day. Each `summary()` call runs `autonomicComponent`, `sleepComponent`, `trainingComponent`, and `vitalsComponent`, each of which builds a 56-day robust baseline from scratch. For a 365-day trend, this means ~365 x 4 = 1,460 baseline computations, many scanning the same overlapping 56-day windows. On Apple Watch users with dense HealthKit data, the detached `Task.detached(.userInitiated)` already offloads this from the main thread, but the CPU cost is still high and contributes to the "refresh feels frozen for ~10 s" symptom noted in `LessonsLearned.md`.
- **Why it matters:** Readiness trend chart generation is the single heaviest computation in the app. On a 365-day window with rich data, the baseline recomputation is mostly redundant — 90% of the work repeats across adjacent days. While already off-main, this still delays the final `@Published` update and burns CPU.
- **Suggested fix:** Precompute a rolling window of daily readiness component scores (one forward pass, one backward pass for baselines), store them, and then assemble final scores by weighted combination. This reduces the complexity from O(n x baseline_window) to O(n). The tradeoff is added state management, but the speedup is substantial for long trends.
- **Risks / dependencies:** This is a non-trivial refactor of the readiness calculator's internal architecture. The public API should remain unchanged. Worth pairing with a dedicated readiness calculator test suite (see T1).

#### D3. `adjustedSummaryScore` caps readiness at <=24 with a binary severe-limiter gate that may be too aggressive

- **Severity:** Low
- **Related files:** `Body/Models/Readiness/ReadinessScoreCalculator.swift:506-521`
- **Description:** If ANY component has a score <=25 AND its strongest driver impact >=0.90, the entire readiness score is capped at `min(score, 24)`:
  ```swift
  private static func isSevereLimiter(_ result: ComponentResult) -> Bool {
      guard let componentScore = result.component.score else { return false }
      let strongestImpact = result.drivers.map(\.impact).max() ?? 0
      return componentScore <= 25 && strongestImpact >= 0.90
  }
  ```
  This means a readiness score could be, say, 72 (from three healthy components) but get clamped to 24 because one component (e.g., vitals with a single borderline blood oxygen reading) triggers the gate. The gate treats "any one component in severe distress" as equivalent to "overall readiness is Poor," which may over-penalize users who have one noisy metric.
- **Why it matters:** The adjusted score is shown to users as their primary readiness number. A single anomalous night (e.g., one low-HRV reading after drinking) can drag the score from "Moderate" to "Poor" even when sleep and training load are fine. Users may lose trust in the metric if one variable dominates.
- **Suggested fix:** Consider a graduated cap — e.g., limit at 24 if >=2 components are severe limiters, or use a weighted penalty that reduces the score proportional to the number and severity of limiters rather than a hard binary gate. Alternatively, increase the impact threshold from 0.90 to 0.95 to reduce false positives.
- **Risks / dependencies:** Changes the readiness score distribution for users with noisy data. Should be validated against real HealthKit exports before shipping.

#### D4. Sleep continuity scoring uses hardcoded efficiency thresholds without personal baselines

- **Severity:** Low
- **Related files:** `Body/Models/Readiness/ReadinessScoreCalculator.swift:251-265`
- **Description:** Sleep fragmentation is scored by computing `efficiency = 1 - awakeDuration / inBedDuration` and then normalizing against fixed thresholds:
  ```swift
  let continuityProgress = min(max((efficiency - 0.78) / 0.18, 0), 1)
  ```
  The 78% and 18% constants are not documented as to their origin (population averages? WHO guidelines?). Unlike heart rate and HRV — which use personal robust baselines — sleep continuity uses a one-size-fits-all threshold. A user who typically sleeps at 85% efficiency will never trigger a fragmentation driver even if they drop to 79% (a significant personal deviation), while a user who typically sleeps at 95% can drop to 89% without penalty.
- **Why it matters:** Less personalized than the autonomic component. The sleep component's "fragmented" driver may miss real disruptions for high-efficiency sleepers and over-flag low-efficiency sleepers who are at their personal normal.
- **Suggested fix:** Replace the fixed 0.78 threshold with a 7-day rolling personal median. Keep the fixed threshold as a fallback when history is insufficient.
- **Risks / dependencies:** Requires at least 7 days of sleep stage data to compute a personal baseline. The fallback to fixed thresholds handles the cold-start case.

### Code Quality Issues

#### Q1. `BodyHomeView.swift` is 8,656 lines — bundles the Home grid, every detail screen, five chart structs, sleep charts, activity rings, training-load presentation, source comparison charts, and card background extensions

- **Severity:** Medium
- **Related files:** `Body/Views/BodyHomeView.swift` (entire file)
- **Description:** The file has grown from ~6,289 lines in the prior audit to 8,656 lines in this run. It still bundles: the Home grid, `BodyHealthMetricDetailView` (with sleep supplements, basics range card, BMI panel), five distinct chart structs, sleep stage/vitals charts, `BodyActivityRingsDetailView` + ring graphic (partially — the file is 691 lines but ring structs remain in `BodyHomeView`), training-load interval presentation + breakdown, source-comparison charts, and several `View` extensions. Carry-forward from `Issues.md` N7.
- **Why it matters:** Editor latency, find-in-file friction, and merge conflicts. A single change to a chart modifier now risks merge collision with any other simultaneous edit. The `ProjectConfigurationTests` perform substring assertions across this file, so splits must be coordinated.
- **Suggested fix:** Carve off in medium-size moves: (1) ring graphic structs from `BodyHomeView` into `BodyActivityRingsDetailView.swift`, (2) `BodyHealthMetricDetailView` + sleep/basics panels into `BodyHealthMetricDetailView.swift`, (3) five chart structs into `Body/Views/Charts/` group. Each split must keep `ProjectConfigurationTests` assertions valid.
- **Risks / dependencies:** `ProjectConfigurationTests` has ~20 string-grep assertions targeting this file. Most look up by struct name, so they survive file moves. Four use `source.range(of: "private struct ...")` with char-width assertions; those need prefix size updates.

#### Q2. `HealthSummarySnapshot.swift` is 3,341 lines — bundles 25+ types (models, snapshots, trends, store logic)

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift` (entire file)
- **Description:** The file holds: `HealthMetricKind`, `HealthMetricSummary`, `HealthSummarySnapshot`, `HealthDashboardSnapshot`, `HealthTrendSnapshot`, `HealthTrendSeries`, `HealthTrendRangeSeries`, `HealthTrendCalendarPoint`, `HealthTrendHourlyBucket`, `SleepSummary`, `SleepStageSnapshot`, `SleepScoreSummary`, `SleepVitalsSummary`, `SleepHistorySnapshot`, `ActivityRingSummary` + related types, `BasicsTrendSummary`, and filtering/convenience extensions. Mixed concerns: pure models, Codable conformance, filtering logic, and trend computation.
- **Why it matters:** Same as Q1 — navigational friction. A developer looking for `HealthTrendSnapshot` must scroll past 15 unrelated type definitions.
- **Suggested fix:** Split into focused files: `Body/Models/Health/HealthMetricKind.swift`, `Body/Models/Health/SleepModels.swift`, `Body/Models/Health/ActivityRingModels.swift`, keeping `HealthSummarySnapshot.swift` for the core snapshot types. The `HealthDashboardSnapshotStore` is already separate.
- **Risks / dependencies:** No test-grep assertions are coupled to this file's name — all model types are referenced by type name. Low risk.

#### Q3. `WorkoutMonthSnapshotTests.swift` at 3,551 lines with no clear sub-structure

- **Severity:** Low
- **Related files:** `BodyTests/WorkoutMonthSnapshotTests.swift`
- **Description:** The test file bundles unit tests for snapshot building, store round-trips, workout type breakdowns, row presentations, value formatting, locale overrides, unit preferences, color validation, calendar alignment, and more — with no `// MARK:` separators.
- **Why it matters:** Adding a new test requires scanning 3,500+ lines to find the right insertion point. Risk of duplicate test names.
- **Suggested fix:** Add `// MARK: - Snapshot Construction`, `// MARK: - Store Round-Trips`, `// MARK: - Value Formatting`, etc. sub-sections.
- **Risks / dependencies:** None.

#### Q4. Sleep duration goal is read by views but never threaded into the readiness calculator — architectural gap

- **Severity:** Medium
- **Related files:**
  - `Body/Views/BodySettingsView.swift:18`
  - `Body/Views/BodyHomeView.swift:224,2985`
  - `Body/Models/Readiness/ReadinessScoreCalculator.swift:241`
- **Description:** The user's sleep duration goal is stored via `@AppStorage` and passed correctly to `SleepScoreSummary` in the Sleep detail view. But the Readiness calculator — which also scores sleep duration — has no access to this preference. This is an architectural gap: the calculator is a pure `enum` with static methods; it has no dependency injection point for user preferences.
- **Why it matters:** Beyond the specific bug (C1), this reveals a fragility pattern: any future user-configurable parameter that affects Readiness scoring (e.g., training load sensitivity, HRV baseline window) will hit the same gap.
- **Suggested fix:** Introduce a `ReadinessScoreCalculator.Configuration` struct with `idealSleepDuration: TimeInterval` and any future tunables. Pass it as a parameter to `summary()` and `dailySeries()`. The `BodyAppearancePreference` enum already centralizes keys — the configuration can be assembled from `UserDefaults` at the call site.
- **Risks / dependencies:** Non-breaking if the `Configuration` type has sensible defaults.

### Performance Issues

#### P1. `loadMonthIfNeeded` busy-waits with a 100ms polling loop instead of using structured concurrency

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:676-678`
- **Description:** When a requested month is already being loaded by another task, `loadMonthIfNeeded` enters a polling loop:
  ```swift
  while loadingMonthKeys.contains(key), !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 100_000_000)
  }
  ```
  At 10 Hz, this is not CPU-intensive but it's a code smell. The same intent can be expressed more idiomatically with `withCheckedContinuation` keyed off the `loadingMonthKeys` set.
- **Why it matters:** Polling loops are fragile — the 100ms sleep adds 0-100ms of latency to every concurrent month load. Under a full refresh with 3 concurrent months, the worst case is 300ms of unnecessary delay. Not user-visible, but a maintainability concern.
- **Suggested fix:** Replace with a `[BodyWorkoutMonthKey: [CheckedContinuation<Void, Never>]]` map. When a load completes, resume all continuations for that key.
- **Risks / dependencies:** Must ensure continuations are always resumed (including on cancellation) to avoid leaks.

### Configuration & Platform Issues

#### C2. Snapshot models lack schema version fields — type case removal or renaming breaks all stored caches

- **Severity:** Medium
- **Related files:**
  - `BodyShared/Models/WorkoutMonthSnapshot.swift` (Codable, no version key)
  - `Body/Models/HealthSummarySnapshot.swift:1485` (`HealthDashboardSnapshot`, Codable, no version key)
- **Description:** Both `WorkoutMonthSnapshot` and `HealthDashboardSnapshot` are persisted to disk as JSON. Neither includes a `schemaVersion` field. The current decode uses `decodeIfPresent` which tolerates additions. However, if a `BodyWorkoutType` case is ever removed or renamed, existing JSON on disk will fail to decode the entire snapshot — causing a fallback to `.placeholder` (losing all cached workout data) in the widget, and `.empty` in the app.
- **Why it matters:** Workout type addition is backward-compatible, but removal is not. Not an immediate concern — `BodyWorkoutType` has only grown — but worth proactive hardening.
- **Suggested fix:** Add an optional `schemaVersion: Int?` field to both snapshot types. On decode, check the version and run a lightweight migration if needed.
- **Risks / dependencies:** One-line Codable addition per type. No migration needed until a breaking change actually occurs.

### Missing Tests

#### T1. Readiness score calculator has zero unit tests despite containing the most mathematically complex code in the app

- **Severity:** High
- **Related files:**
  - `Body/Models/Readiness/ReadinessScoreCalculator.swift` (601 lines, no corresponding test file)
  - `BodyTests/` (no `ReadinessScoreCalculatorTests.swift`)
- **Description:** The readiness calculator implements robust median baselines, z-scores, smoothstep functions, weighted scoring, penalized scoring, sleep progress scoring, training load scoring, severe-limiter gating, and confidence computation — all with zero automated tests. C1, D1, D3, and D4 in this report are all readiness-calculator issues that would have been caught by even basic parameterized tests.
- **Why it matters:** The readiness score is a headlining feature. Any regression in scoring logic silently changes the user's readiness number. Without tests, future changes to baselines, thresholds, or scoring curves are unverifiable.
- **Suggested fix:** Create `BodyTests/ReadinessScoreCalculatorTests.swift` with test cases for:
  - `robustBaseline` with known values (verify median, MAD, validDayCount)
  - `robustZScore` with above/below/at baseline values
  - `scoreFromBaselineZScore` across the range
  - `sleepComponent` with known duration and stage data
  - `trainingLoadScore` across the thresholds
  - `adjustedSummaryScore` with and without severe limiters
  - `confidence` with varying component counts
  - Edge cases: empty data, single-point baselines, NaN/Inf values, zero spread
- **Risks / dependencies:** The calculator is pure logic with no HealthKit dependency — tests run without a device. All inputs are value types.

#### T2. `HealthKitFetchEngine` has no direct tests — all HealthKit behavior is tested indirectly

- **Severity:** Medium
- **Related files:**
  - `Body/Services/HealthKitFetchEngine.swift` (2,815 lines, no test file)
  - `BodyTests/HealthKitWorkoutStoreTests.swift` (tests store init and persistence, not fetch logic)
- **Description:** The engine is the single point of contact with `HKHealthStore`. It owns predicate construction, source mapping, trend aggregation, incremental fetch logic, training-load memoization, and sleep-vitals parallel hydration. None of these have direct tests.
- **Why it matters:** The engine is the highest-risk file for regressions — a predicate bug can silently return wrong data. The memoization cache has subtle lifecycle rules (cleared on `setHealthTrendAnchorDate`); a regression would duplicate the expensive fetch without any test catching it.
- **Suggested fix:** Add `BodyTests/HealthKitFetchEngineTests.swift` with tests for:
  - `healthPermission(forMetric:)` mapping completeness
  - `healthSampleType(forSourceKind:)` mapping
  - `recentHealthTrendInterval` window boundaries
  - `incrementalFetchStart` logic
  - `mergeIntradaySamples` deduplication
  - `sleepDuration` / `mergedSleepDuration` merging logic
- **Risks / dependencies:** The engine is an `actor` — tests need `async` context. The `nonisolated static` helpers can be tested synchronously.

#### T3. Readiness component weights and scoring thresholds are undocumented magic numbers

- **Severity:** Low
- **Related files:**
  - `Body/Models/Readiness/ReadinessScoreCalculator.swift`
  - `docs/ReadinessMetrics.md`
- **Description:** Weight constants (30, 30, 25, 15) are inline; sleep efficiency thresholds (0.78/0.18) have no comments; z-score start/full parameters have no justification. A future developer modifying these numbers has no guidance.
- **Why it matters:** Readiness scoring is the most scientifically sensitive part of the app. Undocumented magic numbers invite uninformed changes.
- **Suggested fix:** Add doc comments explaining the rationale (e.g., "Weights sum to 100" or "Thresholds derived from population norms"). If heuristic, state that explicitly.
- **Risks / dependencies:** None. Comment-only change.

---

## 3. Priority Recommendations

### Fix First (Critical / High)

1. **C1 — Readiness sleep component ignores user's sleep goal.** Thread `idealSleepDuration` through the calculator. High user impact — Readiness is a headlining feature.
2. **T1 — Add Readiness score calculator tests.** Without tests, C1 and any future scoring changes are unverifiable. Zero device dependency.

### Fix Next (Medium)

3. **D1 — Unify wrist temperature baseline between UI (mean) and Readiness (median).** Small code change, eliminates a visible disagreement.
4. **C2 — Add schema version fields to snapshot models.** One-line Codable addition per type. Prevents silent data loss on type evolution.
5. **U1 — Disable Body Pro purchase buttons or gate behind feature flag.** User-facing trust issue.
6. **Q1 — Split `BodyHomeView.swift` (8,656 lines).** Start with the smallest carve-out to build the pattern.

### Optional Cleanup (Low)

7. D2 — Optimize readiness dailySeries to O(n). Worth doing after T1.
8. D3 — Review adjustedSummaryScore binary gate.
9. D4 — Personalize sleep continuity efficiency baseline.
10. Q2 — Split `HealthSummarySnapshot.swift`.
11. Q3 — Add MARK sub-sections to `WorkoutMonthSnapshotTests.swift`.
12. Q4 — Add configuration struct to readiness calculator.
13. P1 — Replace polling loop with continuation map.
14. T2 — Add `HealthKitFetchEngine` tests for pure-logic helpers.
15. T3 — Document readiness scoring weights and thresholds.
16. U2 — Fix Body Pro future-updates checkmark icon.

---

## What Was Checked

- App entry / scene phase: `Body/BodyApp.swift`
- HealthKit ingestion: `Body/Services/HealthKitFetchEngine.swift` (full, 2,815 lines), `Body/Services/HealthKitWorkoutStore.swift` (full, 1,531 lines)
- Readiness calculator: `Body/Models/Readiness/ReadinessScoreCalculator.swift` (full, 601 lines), `Body/Models/Readiness/ReadinessModels.swift` (full, 259 lines)
- Dashboard persistence: `Body/Services/HealthDashboardSnapshotStore.swift` (full), `BodyShared/Services/WorkoutSnapshotStore.swift` (full)
- Models: `Body/Models/HealthSummarySnapshot.swift` (selective — key types), `Body/Models/BodyAppearancePreference.swift` (selective — keys, permissions, source comparison), `BodyShared/Models/WorkoutSummary.swift`, `BodyShared/Models/WorkoutMonthSnapshot.swift`, `BodyShared/Models/BodyWorkoutType.swift`
- Views: `Body/Views/BodyHomeView.swift` (selective — metricCards, chart structs, source comparison, training-load, sleep detail, activity rings), `Body/Views/BodyWorkoutsView.swift` (full), `Body/Views/BodySettingsView.swift` (selective — sleep goal, version display), `Body/Views/BodyProView.swift` (full), `Body/Views/MainTabView.swift`, `Body/Views/BodyActivityRingsDetailView.swift` (header)
- Widget: `BodyWidgetExtension/WorkoutCalendarWidget.swift` (full), `BodyWidgetExtension/BodyWidgetExtensionBundle.swift`
- Configuration: `Body/Body.entitlements`, `BodyWidgetExtension.entitlements`, `Body/PrivacyInfo.xcprivacy`, `BodyWidgetExtension/PrivacyInfo.xcprivacy`, `body.xcodeproj/project.pbxproj` (build settings, version pins, HealthKit usage description, deployment target)
- Tests: `BodyTests/WorkoutMonthSnapshotTests.swift` (function index), `BodyTests/ProjectConfigurationTests.swift` (function index), `BodyTests/HealthKitWorkoutStoreTests.swift` (full), `BodyTests/BodyWorkoutTypeTests.swift` (full)
- Docs: `README.md`, `VersionHistory.md`, `TestPlan.md`, `LessonsLearned.md`, `Issues.md` (full)
- Archive cross-reference: `docs/IssuesArchive-01.md`, `docs/IssuesArchive-02.md`, `docs/IssuesArchive-03.md`

Grep queries:
- `rg "try!|fatalError|preconditionFailure|as!" Body BodyShared BodyWidgetExtension` — no matches
- `rg "try\?" Body` — 19 matches, all in `Task.sleep`, JSON encode/decode guards, and `Data(contentsOf:)` guards (appropriate)
- `rg "#if DEBUG" Body BodyShared BodyWidgetExtension` — no matches in production (only `WorkoutSnapshotStore` for Xcode Previews)
- `rg "Calendar.current" Body BodyShared BodyWidgetExtension` — no matches in production code
- `rg "TODO|FIXME|XXX|HACK" Body BodyShared BodyWidgetExtension BodyTests` — no source matches
- `rg "UIScrollView.appearance" Body` — no matches (confirmed fixed)
- `rg "import UIKit|import HealthKit" BodyShared` — no matches (widget-safe shared sources)
- `rg "BodySleepDurationGoal.defaultDuration" Body` — 2 matches (C1 bug + default parameter)

## Not Checked (Worth a Follow-Up)

- Running the project on simulator or device. Verifying C1 on a real HealthKit store requires a build.
- Lock Screen / accessory widget families (deferred per TestPlan).
- HealthKit background delivery (deferred per TestPlan).
- Localization beyond English.
- LaunchScreen XML and Xcode shared scheme XML.
- Asset catalog `Contents.json` JSON validation beyond `ProjectConfigurationTests`.
- `WorkoutMonthSnapshotTests.swift` (3,551 lines) was function-indexed but not read in full.
- Readiness scoring calibration against real multi-user HealthKit exports (weights and thresholds would benefit from empirical validation).
- `docs/ReadinessMetrics.md` content accuracy against current code.
