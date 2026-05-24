# Body — Issues Report

Audit of branch `body-v0.5.6` on 2026-05-24. Read-only review; no code was
modified. The previous report has been archived as
`docs/IssuesArchive-04.md`.

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

Body v0.5.6 build 4 is the current ship state. Since archive 03 (audited at
v0.3.9 build 2) the app added Readiness scoring with personal baselines,
two-source comparison for 9 metrics, a Settings > Data > Source page with
global primary/secondary defaults and a "Combine Sources with Same Name"
toggle, progressive HealthKit refresh streaming, a `HealthKitFetchEngine`
actor extracted from `HealthKitWorkoutStore`, a full-screen workout detail
sheet with a smoothed gradient-line heart rate chart, intraday day-line
charts for steps and active energy, a wrist-temperature dashed-baseline
overlay, the 15-second timeout for the Workouts pending-month banner, and
dedicated test coverage for the Readiness calculator. All eleven findings
from `docs/IssuesArchive-04.md` (N1-N11) are addressed in code:
N1 (chart-switch fade) — all three remaining charts now use
`.transition(.opacity.animation(...))` (`BodyHomeView.swift:6360-6362,
6572-6574, 7384-7386`); N2 (README screenshots) — README points at
`Screenshots/01-v0.5.2.PNG`/`04-v0.5.2.PNG` for the new chart screens;
N3 (TestPlan branch + cards) — generated 2026-05-18 against
`body-v0.5.6`, with new M31/M32/M33 cases for Training Load, Heart Rate,
range-switch animation, plus M34-M38 for new flows; N9
(`UIScrollView.appearance()`) — no callers remain
(`rg "UIScrollView.appearance" Body` is empty); N10 (Workouts
pending-month timeout) — `BodyWorkoutsView.swift:388-411` now wraps the
load in a `withTaskGroup` with a 15-second deadline; N11
(`versionTapCount` reset) — `BodySettingsView.swift:64` now resets the
counter inside `.onAppear`. N4-N5 (BodyPro placeholders) and N7-N8
(file-size hypertrophy) remain — they are intentionally deferred.

The current run surfaces twelve findings. The most user-facing is N1, a
copy-paste regression in three places that renders the Time In Daylight
metric (and its detail screen) with the SF Symbol `plus` ("+") rather than
the `sun.max.fill` icon used everywhere else in the app for that metric.
The remainder are hygiene items: three files past their growth budget
(`BodyHomeView.swift` 8,608 lines, `HealthKitFetchEngine.swift` 3,128
lines, `HealthSummarySnapshot.swift` 3,374 lines), an unconverted polling
loop in `loadMonthIfNeeded` that LessonsLearned said had been migrated to
continuations, the carry-forward BodyPro placeholder UX, a stringly-typed
`role` parameter in the new Source settings sheet, a global row-disable
during source picks, a force-unwrap on a constant array in the workout
heart-rate chart, a snapshot schema-version hardening item, and a
documentation drift in TestPlan M13.

Areas reviewed: app entry / scene phase, Readiness models + calculator,
HealthKit ingestion (engine + view-model orchestrator, sleep merging,
training-load memoization, source comparison, intraday lazy load),
workout aggregation, snapshot persistence (file-backed dashboard cache
with UserDefaults migration, app-group workout snapshots, persistent
last-refresh timestamp), Summary dashboard (16 metric cards, trends
section), Workouts tab (search/sort/filter, pending-month banner, the
new full-screen workout detail with gradient heart rate chart), Settings
(Appearance, Metrics, Data > Source / Permissions / Sync Status / Cache,
About, Body Pro entry), Body Pro page, month-year picker, widgets,
entitlements, project build settings, privacy manifests, and the four
test files. Intentionally not reviewed: rendered runtime behavior on
device (no build in this run), Lock Screen / accessory widget families,
HealthKit background delivery, localization, LaunchScreen XML, Xcode
shared scheme XML, asset catalog binary contents beyond
`ProjectConfigurationTests` validation.

---

## 2. Issue list

### N1. Time In Daylight card, trend card, and detail header render the SF Symbol `plus` instead of `sun.max.fill`

- **Severity:** High
- **Related files:** `Body/Views/BodyHomeView.swift:388-398` (Home metric
  card builder), `Body/Views/BodyHomeView.swift:673-683` (Home trend card
  builder), `Body/Views/BodyHomeView.swift:1169-1179` (detail model),
  `Body/Models/BodyAppearancePreference.swift:260,952,1185` (canonical icon
  declarations)
- **Description:** Three call sites construct the Time In Daylight
  presentation with `symbolName: "plus"`:
  ```swift
  // Home card
  metric(
      kind: .timeInDaylight,
      title: "Time In Daylight",
      summary: summary.timeInDaylight,
      unit: "min",
      decimals: 0,
      symbolName: "plus",
      symbolColor: Color(red: 0.10, green: 0.58, blue: 1.00),
      chartStyle: .bar,
      chartPreview: trends.series(for: .timeInDaylight)
  ),
  ```
  The Home metric card's icon tile, the small trend card's icon tile, and
  the detail screen's `headerCard` all bind their `Image(systemName:)` to
  this `symbolName`, so the user sees a `+` glyph in a blue rounded tile
  next to the label "Time In Daylight" on Home, in the trends row, and at
  the top of the detail page.
  Every other place that names an icon for this metric uses
  `sun.max.fill`:
  - `BodyHomeCardKind.timeInDaylight.iconName` =
    `"sun.max.fill"` (used in Settings > Metrics > Summary Cards row,
    `Body/Models/BodyAppearancePreference.swift:1185`).
  - `BodyHomeTrendCardKind.timeInDaylight.iconName` =
    `"sun.max.fill"` (Settings > Metrics > Trend Cards row,
    `Body/Models/BodyAppearancePreference.swift:952`).
  - `BodyHealthPermission.timeInDaylight.iconName` =
    `"sun.max.fill"` (Settings > Data > Permissions row,
    `Body/Models/BodyAppearancePreference.swift:260`).
- **Why it matters:** A user opening the Summary dashboard sees a "+"
  inside a blue tile labelled "Time In Daylight" — the icon does not
  communicate "daylight" and clashes with the same metric's sun icon in
  Settings. Tapping into the detail view perpetuates the mismatch in the
  header. Affects every Home, Trend, and Detail render of this metric;
  reaches every user with the metric enabled. Looks like a copy-paste
  regression carried in when Time In Daylight was added as a first-class
  card.
- **Suggested fix:** Replace `symbolName: "plus"` with
  `symbolName: "sun.max.fill"` at all three sites
  (`BodyHomeView.swift:394, 678, 1176`). No other changes needed — the
  tint color already matches `BodyHomeCardKind.timeInDaylight.tintColor`.
- **Risks / dependencies:** None. Visual-only change; no test pins the
  current `"plus"` value (the
  `testMetricCardPreviewStylesMatchRequestedChartKinds` test in
  `BodyTests/ProjectConfigurationTests.swift:194` grep-checks the chart
  preview style, not the symbol name).

### N2. `BodyHomeView.swift` is 8,608 lines and continues to bundle every detail screen, ring graphic helper, and chart struct

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift` (whole file)
- **Description:** The file has grown from 6,289 lines in archive 03 to
  8,608 lines (28 top-level structs / enums / extensions, indexed via
  `rg "^(struct|enum|extension|private struct|private enum|@MainActor)"`).
  It still bundles:
  - The `BodyHomeView` grid (~1,200 lines for `metricCards`,
    `homeTrendCard` builders, layout)
  - `BodyHealthMetricDetailView` (~1,500 lines, every metric's detail
    branch)
  - Sleep supplement cards (`SleepScoreDetailsSheet`,
    `BodySleepStageChart`, `BodySleepVitalsRegionChart`,
    `BodySleepVitalsRegionPlot`, `BodySleepVitalsIconAxis`,
    `BodySleepVitalRegionDot`, `BodySleepVitalRegionLabels`)
  - The Readiness presentation (`BodyReadinessStatusPresentation`,
    `BodyReadinessStatusBreakdownChart`, the "About your score"
    explanation card)
  - Five distinct chart structs (`BodyHealthMetricTrendChart`,
    `BodyHealthMetricDayChart`, `BodyBasicsTrendChart`,
    `BodyBasicsBodyMassIndexTrendChart`, `BodyHeartRateRangeTrendChart`)
  - Three source-comparison chart structs
    (`BodyHealthSourceComparisonLineChart`,
    `BodyHealthSourceComparisonBarChart`,
    `BodyHealthSourceComparisonRangeChart`) plus their entry types
  - The training-load interval presentation (`BodyTrainingLoadIntervalPresentation`,
    `BodyTrainingLoadIntervalBreakdownChart`)
  - The trend-card scaffolding (`BodyHomeTrendsSection`,
    `BodyHomeTrendCard`, `BodyHomeTrendComparisonChart`,
    `BodyHomeTrendCardPresentation`, `BodyHomeTrendComputationCache`)
  - Six `View` extensions / animatable shapes at the tail
    (`BodyCardBackgroundModifier`, `AnimatablePolyline`,
    `AnimatableVector`).
  Same growth pattern flagged as archive 03 N7 and archive 04 N7; the
  file kept growing.
- **Why it matters:** Editor latency, find-in-file friction, and merge
  conflicts. Adding a new chart modifier risks colliding with any other
  concurrent edit. The `ProjectConfigurationTests` source-grep
  assertions across this file mean any split needs coordination.
- **Suggested fix:** Carve in three medium moves so each is verifiable
  against `ProjectConfigurationTests`:
  1. `Body/Views/Health/BodyHealthMetricDetailView.swift` — the detail
     view, its sleep panels, and the BMI / Basics range cards
     (~2,000 lines).
  2. `Body/Views/Health/Charts/*.swift` — one file per chart struct
     (`BodyHealthMetricTrendChart`, `BodyHealthMetricDayChart`,
     `BodyBasicsTrendChart`, `BodyBasicsBodyMassIndexTrendChart`,
     `BodyHeartRateRangeTrendChart`) and one for the three source
     comparison charts.
  3. `Body/Views/Health/BodyReadinessExplanation.swift` plus
     `BodyReadinessStatusBreakdownChart` (~250 lines).
- **Risks / dependencies:** `ProjectConfigurationTests` has many string
  substring assertions against `BodyHomeView.swift`. Most look up by
  struct name (e.g.
  `testHeartRateRangeChartUsesStandardBarSelectionRule`,
  `testTrainingLoadTrendChart...`), so they survive file moves. The
  four assertions in
  `BodyTests/ProjectConfigurationTests.swift:194,224,256,278` that grep
  the file's source text need their `source.range(of: "private struct
  ...")` prefixes audited if the struct's surrounding context changes.

### N3. `HealthSummarySnapshot.swift` is 3,374 lines and bundles 40+ types across summary, trend, sleep, ring history, training load, and source-trend categories

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift` (whole
  file)
- **Description:** The file holds: `HealthMetricKind` (with
  `detailHelpText` / `detailDataSourceText` extensions),
  `HealthMetricDetailHelpText`, `HealthMetricDetailDataSourceText`,
  `HealthMetricSummary`, `HealthSummarySnapshot`,
  `HealthDashboardSnapshot` (with `filtered` /
  `filteredWithoutReadinessRecompute` / `recalculatingReadiness`),
  `HealthTrendSnapshot` (with `series(for:)`, `rangeSeries(for:)`,
  `daySeries(for:)`, `secondarySeries(for:)`, `secondaryDaySeries(for:)`,
  `secondaryRangeSeries(for:)`, `replacingMetric`, `filtered`,
  `clearingSecondarySeries`, `readinessSourceSeries`),
  `BasicsTrendSummary`, `HealthTrendRangeSeries`,
  `HealthTrendRangeDataPoint`, `HealthTrendRangeCalendarPoint`,
  `HealthTrendSeries` (`points`, `calendarPoints`, range-aware
  bucketing), `HealthTrendDataPoint`, `BodyHealthSourceRole`,
  `BodyHealthSourceTrend`, `BodyHealthSourceComparisonTrend`,
  `BodyHealthSourceRangeTrend` (plus the Range-comparison-trend),
  `SleepSummary`, `SleepDaySummary`, `SleepHistorySnapshot`,
  `SleepVitalsSummary`, `SleepVitalRegion`, `SleepVitalStatusTitle`,
  `SleepVitalReferenceRange`, `SleepStageSnapshot`, `SleepScoreSummary`
  (a 350-line scoring engine), `SleepScoreCategory`,
  `SleepStageSegment`, `SleepStage`, `ActivityRingSummary`,
  `ActivityRingMetric`, `ActivityRingDaySummary`,
  `ActivityRingCalendarDay`, `ActivityRingCalendarMonth`,
  `ActivityRingMonthKey`, `ActivityRingHistorySnapshot`, and
  `TrainingLoadCalculator`.
- **Why it matters:** Same class of issue as N2. The file is the
  authoritative source for every HealthKit data shape; future
  contributors scroll past a sleep-score calculator to find a training
  load helper.
- **Suggested fix:** Split into focused files (carry-forward of archive
  04 N8 plan):
  - `Body/Models/Health/HealthMetricKind.swift` (`HealthMetricKind`,
    help text, source text)
  - `Body/Models/Health/HealthSummarySnapshot.swift`
    (`HealthMetricSummary`, `HealthSummarySnapshot`)
  - `Body/Models/Health/HealthDashboardSnapshot.swift`
    (`HealthDashboardSnapshot` and its filter/recompute helpers)
  - `Body/Models/Health/HealthTrend.swift` (`HealthTrendSnapshot`,
    `HealthTrendSeries`, `HealthTrendRangeSeries`, calendar points,
    `BasicsTrendSummary`)
  - `Body/Models/Health/Sleep.swift` (`SleepSummary`,
    `SleepDaySummary`, `SleepHistorySnapshot`, `SleepStageSnapshot`,
    `SleepStageSegment`, `SleepStage`, `SleepScoreSummary`,
    `SleepScoreCategory`, `SleepVitalsSummary`, vital references)
  - `Body/Models/Health/ActivityRings.swift`
  - `Body/Models/Health/SourceComparison.swift`
    (`BodyHealthSourceRole`, `BodyHealthSource*Trend`)
  - `Body/Models/Health/TrainingLoadCalculator.swift`
- **Risks / dependencies:** Codable round-trips for
  `HealthDashboardSnapshot`, `WorkoutMonthSnapshot`, and the trend
  snapshots are covered by
  `BodyTests/HealthKitWorkoutStoreTests.swift:64-130` and
  `BodyTests/WorkoutMonthSnapshotTests.swift`; any move must keep
  `CodingKeys` stable so cached files keep decoding. The file rename
  itself is free because no test grep targets
  `HealthSummarySnapshot.swift` by name — only by type names.

### N4. `HealthKitFetchEngine.swift` is 3,128 lines after the extraction; new fan-outs (sleep vitals parallel hydration, source-options inversion, training-load memoization) have accumulated

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitFetchEngine.swift` (whole
  file)
- **Description:** When `HealthKitWorkoutStore` shrank from ~3,900 to
  ~1,450 lines in the engine extraction (LessonsLearned 2026-05-18),
  the engine landed at ~2,815 lines. It is now 3,128 lines and holds:
  selection setters, authorization, permission / source mapping,
  source-predicate construction (with combined-name expansion),
  recent-trend interval helpers, eight different fetch-family helpers
  (`fetchDailyQuantitySeries`, `fetchDailyQuantityRangeSeries`,
  `fetchDailyQuantityAverageAndRangeSeries`, `sleepQuantitySummary`,
  `dailyQuantitySummary`, `dailyCumulativeQuantitySummary`,
  `fetchHourlyCumulativeQuantitySeries`,
  `fetchDailyCumulativeQuantitySeries`, `latestQuantity`,
  `fetchQuantitySampleSeries`), workout / heart-rate / effort fetches,
  sleep summary + history with parallel vitals hydration, training load
  shared-task memo, activity ring summary + history (with two overloads
  and a third private helper), source options + map (with combine-by-name
  expansion), incremental + merge intraday helpers, the two large
  orchestrators (`fetchHealthSummary`, `fetchHealthTrends`,
  `fetchHealthDashboardSnapshot`, plus the
  `fetchSecondaryTrend` / `fetchSecondaryDaySamples` /
  `fetchSecondaryRangeTrend` / `fetchIntradayDaySamples` family), and a
  block of `nonisolated static` pure-function helpers at the end.
- **Why it matters:** Same maintainability class as N2 / N3 — a future
  contributor adding a new metric must scan two thousand lines to find
  the right fetch helper. Per-metric helpers are repetitive
  (`async let metricName = fetchIfPermitted(.permission, default: ...) { await ... }`),
  and any new metric duplicates ~10 lines in both
  `fetchHealthSummary` and `fetchHealthTrends`.
- **Suggested fix:** Two-step carve:
  1. Move the `nonisolated static` helpers in the
     `// MARK: - Static helpers (nonisolated)` block to a sibling file
     `Body/Services/HealthKitSampleParsers.swift` (~250 lines moved out,
     no behavior change because everything is already `nonisolated
     static`).
  2. Lift the four `// MARK: -` sections into peer files via an
     extension on `HealthKitFetchEngine` declared in
     `Body/Services/HealthKitFetchEngine+Sleep.swift`,
     `+TrainingLoad.swift`, `+ActivityRings.swift`,
     `+SourceMapping.swift`. The actor type stays in the original
     file; the extensions add the related fetch methods. Each split
     reduces the main file by 400-700 lines without changing the
     external API.
- **Risks / dependencies:** None. All actor-isolated mutable state
  (`healthSourcesByKind`, `anchorDate`, etc.) stays on the actor
  declaration in the original file, so extensions can read/write it
  without compiler errors. Splits do not change the engine's public
  surface, so `HealthKitWorkoutStore` is unaffected.

### N5. `loadMonthIfNeeded` still busy-waits on `loadingMonthKeys` with a 100 ms `Task.sleep` polling loop after LessonsLearned says polling was converted to continuations

- **Severity:** Low
- **Related files:**
  `Body/Services/HealthKitWorkoutStore.swift:830-852`,
  `LessonsLearned.md:99-104`
- **Description:** The 2026-05-18 LessonsLearned entry "Replace
  `while isRefreshing { sleep(100ms) }` with continuation-based
  completion" lists `awaitRefreshCompletion`, `loadMonthIfNeeded`,
  `loadPreviousActivityRingMonthIfNeeded`, and
  `updateSecondaryHealthDataSource` as the call sites that were
  migrated to `refreshCompletionContinuations`. Three of those four
  now use `awaitNextRefreshCompletion()`. `loadMonthIfNeeded` does
  call `awaitNextRefreshCompletion()` on entry — but it then keeps
  the per-month polling loop on `loadingMonthKeys`:
  ```swift
  while loadingMonthKeys.contains(key), !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 100_000_000)
  }
  ```
  The continuation list (`refreshCompletionContinuations`) is keyed
  on `isRefreshing` only, not per-month, so it can't replace the
  `loadingMonthKeys` wait.
- **Why it matters:** Theoretical, not observed — `loadingMonthKeys`
  is a `Set` mutation under `@MainActor` isolation and gets removed
  in a `defer` block, so the loop terminates in practice. But the
  code reads as if the lesson-learned migration was complete; it
  isn't, and the documented intent (no busy waits) is partially
  unmet. Polls 10 times per second per concurrent month load while
  awaiting another caller — small CPU/scheduling cost.
- **Suggested fix:** Add a per-month continuation map alongside
  `refreshCompletionContinuations`:
  ```swift
  private var monthLoadContinuations: [BodyWorkoutMonthKey: [CheckedContinuation<Void, Never>]] = [:]
  ```
  In `loadMonthKeysIfNeeded`, the `defer { loadingMonthKeys.subtract(keysToLoad) }`
  block also drains and resumes continuations for each key. The
  polling loop in `loadMonthIfNeeded` becomes an `await
  withCheckedContinuation { ... }` registration under the
  `loadingMonthKeys` guard. Update the LessonsLearned entry to note
  the per-key wait was added in this pass.
- **Risks / dependencies:** Must ensure every exit path
  (`Task.isCancelled`, thrown error, normal completion) drains the
  continuations for that key, otherwise leaked continuations stall
  future callers indefinitely. Cover with a focused test that
  enqueues two concurrent `loadMonthIfNeeded` calls for the same key
  and asserts both return the loaded snapshot.

### N6. BodyPro Lifetime purchase card still shows a real-looking price (`$5.99`) and arrow button but only sets a status string

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:41-50,250-287,78-110`
- **Description:** `BodyProPurchaseOptionCard` renders "Lifetime — One
  purchase for lifetime Body Pro access — `$5.99` — arrow button". The
  arrow tap calls `onChoose`, which sets
  `statusMessage = "Body Pro lifetime purchases are not available in this build."`.
  The "Redeem Pro" and "Restore Purchases" buttons in `restoreSection`
  follow the same pattern (lines 88-108). The footnote-sized status
  only appears after the tap; the steady state of the page presents as
  a real purchase surface. Carry-forward from archive 03 N4 and archive
  04 N4.
- **Why it matters:** Mistakes Body Pro for a real purchase surface
  before the user taps. Reachable only from Settings > Body Pro, so
  blast radius is bounded — but the inconsistency reads as a bug to
  any first-time visitor.
- **Suggested fix:** Two options:
  (a) Disable the three buttons and replace the price with a
      `"Coming Soon"` pill on the Lifetime card. Keeps the visual
      shape so the page is ready for IAP wiring.
  (b) Gate the entire purchase + redeem + restore stack behind a
      `#if PRO_PURCHASES_ENABLED` flag and ship a single "Body Pro is
      coming" hero panel until IAP wiring exists.
  Either preserves the future IAP design without misrepresenting the
  current state. Needs visual verification on device.
- **Risks / dependencies:** None.
  `BodyTests/ProjectConfigurationTests.swift:1119-1170`
  (`testBodyProPageUsesCoinStyleSettingsEntryAndIconAssets`) asserts
  the page strings — confirm the assertions still pass after copy
  changes.

### N7. BodyPro `Future Pro Updates` row uses the same gold `BodyProFeatureCheckmark()` as real unlocked-feature rows

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:333-339` (the
  checkmark), `Body/Views/BodyProView.swift:363-387` (the future-updates
  row), `Body/Views/BodyProView.swift:289-315` (the feature row)
- **Description:** `BodyProFeatureRow` renders an unlocked feature with
  `BodyProFeatureCheckmark()` — a gold filled checkmark.
  `BodyProFutureUpdatesNote` is a placeholder row that reads "More Body
  Pro features will be added in future updates." but still trails with
  the same `BodyProFeatureCheckmark()` glyph. The visual semantic of
  the gold checkmark is "this is included", which contradicts the row
  body's "this is coming later". Carry-forward from archive 03 N5 and
  archive 04 N5.
- **Why it matters:** Confusing semantics on the marketing page.
  Trivial to fix; reachable only from Settings > Body Pro.
- **Suggested fix:** Replace the checkmark on `BodyProFutureUpdatesNote`
  with a less definitive glyph — `sparkles`,
  `arrow.up.forward.circle`, or just omit it. Keep the gold checkmark
  on real `BodyProFeatureRow` items.
- **Risks / dependencies:** None.

### N8. Snapshot models (`WorkoutMonthSnapshot`, `HealthDashboardSnapshot`) have no `schemaVersion` field

- **Severity:** Low
- **Related files:** `BodyShared/Models/WorkoutMonthSnapshot.swift:52-203`,
  `Body/Models/HealthSummarySnapshot.swift:1470-1558`
- **Description:** Both snapshot types persist to JSON files in the
  shared app group / Application Support directories. Neither carries
  an explicit `schemaVersion: Int?` field. The current decode uses
  `decodeIfPresent` everywhere, so additions are forward-compatible.
  Removal or rename of a case in `BodyWorkoutType`,
  `HealthMetricKind`, or `BodyHealthSourceRole` would still fail the
  entire decode and fall back to `.placeholder` / `.empty`, losing all
  cached workout data and the dashboard snapshot. Carry-forward from
  Issues-ds.md C2 — still defensible hardening.
- **Why it matters:** `BodyWorkoutType` has only grown (the
  HealthKit-to-Body activity-type switch at
  `Body/Services/HealthKitWorkoutStore.swift:1502-1671` adds new
  cases; never removed one), so no near-term breakage. A future case
  rename or removal would mass-invalidate caches across every existing
  install on update day.
- **Suggested fix:** Add an optional `schemaVersion: Int?` field to
  each snapshot's `CodingKeys`. On decode, check the version and (in
  a future commit) run a lightweight migration if needed. One-line
  Codable additions per type plus a `static let currentSchemaVersion = 1`
  constant; no behavior change today.
- **Risks / dependencies:** Adds one optional key per snapshot. Covered
  by the existing round-trip tests
  (`testHealthDashboardSnapshotStoreWritesCachedHomeDataToFileNotUserDefaults`
  and friends at `BodyTests/HealthKitWorkoutStoreTests.swift:64-130`)
  — the new optional field will be `nil` for existing decoded
  snapshots and will be set on the next save.

### N9. `BodySourceSettingsSheet.sourceOptionButton` keys updating state with a stringly-typed `role: String`

- **Severity:** Low
- **Related files:**
  `Body/Views/BodySettingsView.swift:1411-1494`
- **Description:** `BodySourceSettingsSheet` builds two source-option
  sections (Primary, Secondary) and passes the section identifier as
  `role: String` ("primary" / "secondary") through
  `sourceOptionSection`, `sourceOptionButton`, `optionIconName(for:role:)`,
  and `updateSelection(_:role:)`. `updateSelection` branches on
  `role == "secondary"` to call either
  `updateDefaultSecondaryHealthDataSource` or
  `updateDefaultHealthDataSource`; `optionIconName` branches on
  `role == "primary"` for `"heart.text.square.fill"` vs.
  `"square.stack.3d.up.fill"`. The `updatingSelectionID` state key
  is `"\(role)-\(option.id)"`. A typo (`"Primary"` capitalised,
  `"first"`, etc.) compiles cleanly and silently misroutes to the
  default branch.
- **Why it matters:** Refactor risk if the page grows to a third role.
  Compile-time enums are cheap; the existing two-role string layer
  is the only stringly-typed part of an otherwise well-typed page.
- **Suggested fix:** Replace `role: String` with a private nested
  enum:
  ```swift
  private enum Role {
      case primary
      case secondary
  }
  ```
  Thread `Role` through `sourceOptionSection`, `sourceOptionButton`,
  `optionIconName(for:role:)`, and `updateSelection(_:role:)`.
  `updatingSelectionID` becomes `"\(role)-\(option.id)"` after a
  `var stringValue: String { rawValue }` extension.
- **Risks / dependencies:** None. Single-file refactor inside the
  sheet.

### N10. `BodySourceSettingsSheet` disables every row across both Primary and Secondary sections while any single selection is being applied

- **Severity:** Low
- **Related files:**
  `Body/Views/BodySettingsView.swift:1441-1473`
- **Description:** Each row's `.disabled(updatingSelectionID != nil || isSelected)`
  treats the single `updatingSelectionID` state as a sheet-wide
  exclusivity lock. While the user is updating Primary to
  "Apple Watch", every row in both the Primary section and the
  Secondary section is greyed out until the engine finishes
  re-fetching and `updatingSelectionID` is cleared (~1-3s under real
  HealthKit). A user who wants to quickly change both Primary and
  Secondary must wait for the first update to finish before tapping
  the second row.
- **Why it matters:** Mild UX friction on a low-traffic page. Each
  selection triggers a full refresh
  (`workoutStore.updateDefaultHealthDataSource` calls
  `requestAuthorizationAndRefresh`), so concurrent edits are not
  strictly safe today — but the disable should be scoped to the
  same role to communicate "this section is busy".
- **Suggested fix:** Pair with N9. Once `role` is an enum, change the
  disable expression to:
  ```swift
  .disabled(
      isSelected
          || (updatingSelectionID.map { $0.hasPrefix("\(role.stringValue)-") } ?? false)
  )
  ```
  Alternatively, queue concurrent selections through a separate
  `Task` chain in the store so two distinct rows can be applied
  back-to-back without the sheet locking out. The first option is
  the smaller change.
- **Risks / dependencies:** Coordinate with the store's
  `requestAuthorizationAndRefresh` early-return on
  `isRefreshing` — back-to-back selections would otherwise be
  dropped. Keep the per-section disable plus an explicit
  "Refreshing…" indicator on rows that are queued.

### N11. `colorStops.last!` force-unwrap in `BodyWorkoutHeartRateChartMetrics.color(forFraction:)`

- **Severity:** Low
- **Related files:** `Body/Views/BodyWorkoutsView.swift:1383-1400`
- **Description:** The gradient-line heart rate chart's color
  interpolation walks a static `colorStops` array, falling through to
  a force-unwrap when no stop matches:
  ```swift
  static func color(forFraction fraction: Double) -> Color {
      let f = max(0, min(1, fraction))
      for i in 1..<colorStops.count {
          if f <= colorStops[i].location {
              ...
              return Color(...)
          }
      }
      let last = colorStops.last!
      return Color(red: last.red, green: last.green, blue: last.blue)
  }
  ```
  `colorStops` is a non-empty private static constant with five
  entries, so the unwrap is effectively safe. Style-only.
- **Why it matters:** Force-unwraps are a hard "don't" elsewhere in
  the codebase (the existing
  `rg "try!|fatalError|preconditionFailure|as!"` greps are empty,
  and the project consistently uses optional-binding or default
  values). A reader scanning this file's loop control flow can
  miss that the fallthrough is unreachable when the loop exits
  without returning, and trips on the `!`.
- **Suggested fix:** Replace with a `guard let` and a documented
  fallback:
  ```swift
  guard let last = colorStops.last else {
      return Color(red: 1.0, green: 0.30, blue: 0.30)
  }
  ```
  Or, since `f >= 0` and the loop visits `i = 1..<count`, the only
  way to exit without returning is `f > colorStops[count-1].location`
  — which `min(f, 1)` already prevents. The `if` boundary can be
  `>=` instead of `<=` and the fallthrough disappears entirely.
- **Risks / dependencies:** None. Pure-function color interpolation
  with no callers outside the workout-detail chart.

### N12. TestPlan M13 enumerates 14 Home cards but omits Readiness from the list

- **Severity:** Low
- **Related files:** `TestPlan.md:58` (the M13 row),
  `Body/Views/BodyHomeView.swift:357-484` (live `metricCards`),
  `Body/Models/BodyAppearancePreference.swift:1002-1019`
  (`BodyHomeCardKind.defaultOrder`)
- **Description:** M13 reads "Summary shows a two-card-wide Activity
  Rings summary at the top, then same-sized tappable cards for
  Exercise Minutes, Training Load, Wrist Temperature, Time In
  Daylight, Steps, Sleep, Basics, Heart Rate, resting heart rate,
  HRV, blood oxygen, respiratory rate, active energy, and resting
  energy". Fourteen non-Activity-Rings cards. The Home view actually
  renders fifteen non-Activity-Rings cards — the Readiness card
  (`readinessMetric(...)` at `BodyHomeView.swift:357-361` and the
  `BodyHomeCardKind.readiness` entry in
  `defaultOrder` at line 1009) is missing from M13's enumeration.
  M37 covers the Readiness card + detail in detail, but a tester
  reading M13 first would not notice the Readiness card while
  walking the Home grid.
- **Why it matters:** M13 is the "all Summary cards rendered" sanity
  check; the omission means a Readiness rendering regression could
  slip past this case (it would still be caught by M37 if the tester
  runs both).
- **Suggested fix:** Add "Readiness" between "Activity Rings" and
  "Exercise Minutes" in M13's enumeration. Note that Readiness ships
  with a Beta badge (per M37), so add ", Readiness (Beta)" to keep
  the enumeration accurate. While there, reflect the
  `BodyHomeCardKind.defaultOrder` ordering in the prose (current
  order is Activity Rings, Sleep, Basics, Heart Rate, HRV,
  Training Load, Readiness, Active Energy, Resting Energy,
  Wrist Temperature, RHR, Blood Oxygen, Respiratory Rate, Exercise
  Minutes, Steps, Time In Daylight). The order is user-reorderable
  via drag, so either phrase as a default ordering or omit ordering
  entirely.
- **Risks / dependencies:** Doc-only.

---

## 3. Code quality findings

- **Duplicated code:**
  - `Body/Services/HealthKitFetchEngine.swift:2088-2217`
    (`fetchHealthSummary`) and `:2219-2400+` (`fetchHealthTrends`)
    repeat one `async let` per metric (~17 calls in summary, ~25 in
    trends). A `[HealthMetricKind: MetricFetchSpec]` table plus a
    single fan-out helper would cut roughly 200 lines and make adding
    a new metric a single table entry instead of two edits.
  - `Body/Views/BodyHomeView.swift:357-484` (`metricCards`) and
    `:507-689` (`makeHomeTrendCards`) repeat per-metric construction
    14 / 15 times. The two lists share metric kind, symbol name,
    symbol color, and chart style; a shared
    `HomeMetricSpec(kind, title, symbol, color, chartStyle, valueFormatter, messageStyle)`
    table would dedupe both call sites.
  - The Home metric card builder uses `symbolName: "plus"` for Time
    In Daylight in three places (`BodyHomeView.swift:394, 678, 1176`,
    flagged as N1). The underlying issue is that the `symbolName`
    is duplicated across the Home card builder, trend card builder,
    and detail model rather than sourced from
    `BodyHomeCardKind.timeInDaylight.iconName`.

- **Unused or outdated files / symbols:**
  - None new. `BodyChartsView.swift`,
    `BodyHealthMetricCard.AccessoryMetric`,
    `BodyHealthMetricCardTrendPreview`'s dead branches from prior
    archives are gone.

- **Overly complex files or functions:**
  - `Body/Views/BodyHomeView.swift` — 8,608 lines (see N2).
  - `Body/Models/HealthSummarySnapshot.swift` — 3,374 lines (see N3).
  - `Body/Services/HealthKitFetchEngine.swift` — 3,128 lines (see N4).
  - `Body/Views/BodySettingsView.swift` — 2,710 lines, bundles every
    Settings sheet (Theme, App Accent, App Icon, Sleep Duration Goal,
    Summary Cards, Default Trend Range, Home Trend Cards, Units,
    Source, Permissions, Sync Status, Cache, App Icon picker,
    Creator-surprise overlay, How To Use, Feedback). Same growth
    class as the others. No immediate fix required — splitting each
    sheet to a peer file would mirror the
    `BodyHomeView` plan.
  - `Body/Services/HealthKitWorkoutStore.swift:1502-1671` —
    `workoutType(for:)` is a 170-line flat switch with one case per
    `HKWorkoutActivityType.rawValue`. Skip-numbered (no case 81
    between 80 cooldown and 82 swimBikeRun — matches Apple's
    discontiguous raw values). Replace with a static dictionary
    `[Int: BodyWorkoutType]` if it grows again; current form is
    fine.

- **Naming inconsistencies:**
  - `BodyHomeCardKind` and `BodyHomeTrendCardKind`
    (`Body/Models/BodyAppearancePreference.swift:814-981, 984-1236`)
    are two near-identical enums with overlapping cases. The trend
    enum lacks `.activityRings` and `.basics`; the home enum lacks
    nothing the trend version has. Each duplicates `title`,
    `subtitle`, `iconName`, `tintColor`. Lift a single
    `BodyHomeCardKind` plus a `var supportsTrendCard: Bool`
    filter, or a single `BodyMetricKind` enum with two membership
    sets, so the title / icon / color tables exist once. Low
    priority; current form works.
  - `role: String` ("primary" / "secondary") in
    `BodySourceSettingsSheet` (see N9).

- **Structural improvements:**
  - Source the metric card's `symbolName` from
    `BodyHomeCardKind.healthMetricKind.symbolName` (or a new
    `BodyHomeCardKind.iconName` overload returning the Home icon)
    so the icon is declared in one place. This fixes N1 by
    construction and prevents future divergence.
  - Add a `Body/Views/Health/` directory and migrate the chart
    structs out of `BodyHomeView.swift` (see N2).

---

## 4. Functional issues

- **N1 — Time In Daylight icon mismatch:** the Home card, trend card,
  and detail page render the `plus` SF Symbol instead of
  `sun.max.fill`. Visible to every user with the metric enabled.
- **N5 — Polling loop in `loadMonthIfNeeded`:** the per-month busy
  wait still polls at 10 Hz; LessonsLearned says it was migrated to
  continuations but only the global `isRefreshing` wait was.
- **No other functional regressions surfaced in this run.** All eleven
  prior findings (N1-N11 in archive 04) have been confirmed against
  current code (see "Project review summary").

---

## 5. UI/UX issues

- **N1 — Time In Daylight icon mismatch** is the most user-visible
  UX issue in this run.
- **N6 — BodyPro Lifetime purchase placeholder** still presents as a
  live purchase surface until tap.
- **N7 — BodyPro Future Updates checkmark** still uses the same gold
  glyph as real unlocked features.
- **N10 — BodySourceSettingsSheet locks every row** during any single
  selection update.
- **Workouts pending-month 15-second timeout (archive 04 N10
  resolution) reads as "timed out, returned to previous selection"
  with no toast.** When the timeout fires
  (`BodyWorkoutsView.swift:402-411`), `pendingMonthSelection` clears
  but `applyMonthSelection` is not called — the picker carousel may
  visually rest on the requested month while the calendar / list
  show the prior month. A small "Couldn't load [Month]" toast on
  timeout would close the loop. Low priority.

---

## 6. Data and persistence issues

- **`HealthDashboardSnapshotStore` continues to write to Application
  Support with proper `do/catch` and `os.Logger` failure paths**
  (`Body/Services/HealthDashboardSnapshotStore.swift:56-92`). The
  bytes-diff gate at line 75 still skips writes when the encoded
  snapshot is unchanged.
- **N8 — No schema version field on snapshot models.** Carry-forward
  defensible hardening (see N8 above).
- **`secondaryHealthDataSourceSelection.signature` is persisted in
  UserDefaults and compared on launch**
  (`Body/Services/HealthKitWorkoutStore.swift:156-161, 1222-1226`).
  When the signature differs from disk, the cached `*Secondary`
  series get zeroed via `clearingSecondarySeries()`. The signature
  string contains the default option ID plus per-kind overrides — it
  does NOT include the primary selection or the
  `combinesHealthDataSourcesByName` flag. Toggling either of those
  could leave a stale secondary cache visible until the next refresh.
  Observed; not flagged separately because both already trigger a
  full `requestAuthorizationAndRefresh` in the same call path that
  changes them (lines 542, 560, 580, 592, 611), so the stale window
  is at most one frame. Worth noting if either changes-flag setter
  is ever refactored to defer the refresh.
- **`WorkoutSnapshotStore.seedPreviewSnapshotIfNeeded()` writes a
  hardcoded May 2026 placeholder** at first launch
  (`BodyShared/Services/WorkoutSnapshotStore.swift:167-170`,
  `BodyShared/Models/WorkoutMonthSnapshot.swift:153-167`). Today the
  audit date (2026-05-24) is inside that month so the placeholder is
  contemporaneous. For installs in later years the widget would show
  a "May 2026" calendar until the app opens and overwrites the file;
  the real snapshot replaces it on first `refreshCurrentMonth`.
  Watch: if the project ships into 2027 without revisiting the seed,
  the first-launch widget will look stale.
- **No new persistence regressions.** App-group key
  `group.com.zihengthedeveloper.Body` parities across both targets
  (covered by `testAppAndWidgetShareAppGroupEntitlement`).

---

## 7. Configuration and platform issues

- **Build settings:** `MARKETING_VERSION = 0.5.6` /
  `CURRENT_PROJECT_VERSION = 4` in all six configurations
  (`body.xcodeproj/project.pbxproj:462-630`).
  `BodyTests/ProjectConfigurationTests.swift:777-778` pins this.
- **HealthKit usage description** enumerates "workouts, Activity
  Rings, sleep, heart rate, HRV, blood oxygen, respiratory rate, body
  measurements, energy, exercise minutes, wrist temperature,
  daylight, and steps" (project.pbxproj:468, 506). All 13 read
  categories are covered.
- **App group:** `group.com.zihengthedeveloper.Body` parities app +
  widget entitlements.
- **Privacy manifests:** `Body/PrivacyInfo.xcprivacy` and
  `BodyWidgetExtension/PrivacyInfo.xcprivacy` both declare
  `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`),
  `NSPrivacyAccessedAPICategoryFileTimestamp` (`C617.1`) (app only),
  and `NSPrivacyTracking = false`. No
  `NSPrivacyCollectedDataTypes`.
- **Deployment target:** `IPHONEOS_DEPLOYMENT_TARGET = 18.0` across
  all six configurations.
- **No `NSHealthUpdateUsageDescription`** — correct; the app never
  writes HealthKit samples.

---

## 8. Testing gaps

- **Highest-risk uncovered features:**
  - **Time In Daylight icon binding (N1).** No
    `ProjectConfigurationTests` assertion grep-checks the
    `symbolName` for the Time In Daylight card builder — adding one
    would have caught this regression.
  - **Per-month load continuation (N5).** No test pins the wait
    semantics for two concurrent `loadMonthIfNeeded` calls on the
    same key. Adding one would also document the contract.
  - **`HealthKitFetchEngine` direct tests.** The engine (`3,128`
    lines, single point of contact with `HKHealthStore`) has no
    direct test file. Most behavior is indirectly covered via
    `HealthKitWorkoutStoreTests`. Pure-logic helpers
    (`healthPermission(forMetric:)`,
    `recentHealthTrendInterval(calendar:anchor:date:)`,
    `incrementalFetchStart(after:windowStart:)`,
    `mergeIntradaySamples(existing:incoming:windowStart:)`,
    `sourceOptionsAndMap(from:)`,
    `sleepStageSegments(from:)`,
    `uncoveredSleepIntervals(in:coveredBy:)`,
    `hydrateSleepVitalsInParallel(...)`,
    `downsampleHeartRateSamples(_:maximumCount:)`) are all
    `nonisolated static` or pure-actor methods that can be tested
    without a HealthKit store. Add
    `BodyTests/HealthKitFetchEngineTests.swift`.
  - **`BodyWorkoutHeartRateChart` rendering.** No test asserts the
    smoothed-line path, the color stop interpolation, or that the
    label inset keeps time marks inside the plot edges (covered for
    the chart-edge case at `testWorkoutHeartRateXAxisLabelsStayInsidePlotEdges`,
    but not for the gradient stroke). A snapshot test of the
    `Canvas` output for a known sample series would pin the new
    chart's appearance.
  - **Workouts pending-month timeout (N12 follow-up).** No test
    pins the 15-second deadline behavior in
    `BodyWorkoutsView.requestMonthYearSelection`. Adding a fixture
    that delays `loadMonthIfNeeded` past 15 s would lock in the
    timeout contract.

- **Suggested tests:**
  - Add a `ProjectConfigurationTests` source-shape assertion that
    the three Time In Daylight call sites in `BodyHomeView.swift`
    contain `symbolName: "sun.max.fill"` (or, better, route the
    icon name through `BodyHomeCardKind.timeInDaylight.iconName`
    once the structural improvement from N1 lands).
  - Add a unit test for the new
    `monthLoadContinuations` machinery once N5 is fixed.
  - Add manual / on-device cases that need to land in `TestPlan.md`:
    - **M13 update:** add Readiness (Beta) to the enumerated card
      list (see N12).
    - **M-new:** Time In Daylight Home, Trend, and Detail icon
      visual check (post-N1 fix).
    - **M-new:** Source settings Primary → Secondary back-to-back
      tap (validate N10 disable behavior on device).
    - **M-new:** BodyPro Lifetime placeholder visual state (post-N6
      fix).

---

## 9. Priority recommendations

- **Fix first:**
  - **N1** — replace `symbolName: "plus"` with `"sun.max.fill"` at
    three sites in `BodyHomeView.swift`. Single-screen visible
    regression on every Home view with Time In Daylight enabled.
- **Fix next:**
  - **N5** — convert the per-month polling loop in
    `loadMonthIfNeeded` to a `[BodyWorkoutMonthKey: [CheckedContinuation<Void, Never>]]`
    map. Closes the gap with the LessonsLearned migration.
  - **N12** — add Readiness to TestPlan M13's enumeration so the
    Home-cards sanity check covers all 16 cards.
  - **N6** — disable the BodyPro purchase + redeem + restore buttons
    (or gate behind a feature flag) and show a clear "Coming Soon"
    affordance.
- **Optional cleanup:**
  - **N7** — swap the `BodyProFutureUpdatesNote` gold checkmark for
    `sparkles` or omit it.
  - **N2 / N3 / N4** — split `BodyHomeView.swift`,
    `HealthSummarySnapshot.swift`, and `HealthKitFetchEngine.swift`
    in the moves described above. Pair the
    `HealthKitFetchEngine` split with `BodyTests/HealthKitFetchEngineTests.swift`
    so the carve-out is verified.
  - **N8** — add `schemaVersion: Int?` to snapshot Codables.
  - **N9** — replace `role: String` with a private enum in
    `BodySourceSettingsSheet`.
  - **N10** — scope the row-disable to the same source-role (pairs
    with N9).
  - **N11** — replace `colorStops.last!` with a `guard let`
    fallback or tighten the loop condition so the fallthrough is
    unreachable without the force-unwrap.

---

## What was checked

- App entry: `Body/BodyApp.swift`, `Body/Views/MainTabView.swift`.
- Readiness: `Body/Models/Readiness/ReadinessModels.swift` (full),
  `Body/Models/Readiness/ReadinessScoreCalculator.swift` (full).
- App models: `Body/Models/BodyAppearancePreference.swift` (full),
  `Body/Models/HealthSummarySnapshot.swift` (selective via `rg`:
  `HealthMetricKind`, `HealthSummarySnapshot`,
  `HealthDashboardSnapshot`, `filtered(by:)`,
  `recalculatingReadiness`, `replacingMetric`,
  `readinessSourceSeries`).
- App services: `Body/Services/HealthKitWorkoutStore.swift` (selective:
  init, `requestAuthorizationAndRefresh`, `refreshHealthMetric`,
  `loadIntradayMetricSamplesIfNeeded`, `refreshWorkoutMonth`,
  source / secondary / combine updaters,
  `loadMonthIfNeeded`, `loadPreviousActivityRingMonthIfNeeded`,
  `clearLocalCache`, `refreshRecentMonths`,
  `fetchDashboardSnapshotProgressively`,
  `updateHealthDashboardSnapshot`,
  `applyPermissionSelectionToCachedData`,
  `updateCurrentMonthSnapshot`, `storedIdealSleepDuration`,
  `readObjectTypes`, `workoutType(for:)`),
  `Body/Services/HealthKitFetchEngine.swift` (selective: actor init,
  authorization, permission / source mappers, source predicate,
  combined predicate, recent-trend interval, `fetchIfPermitted` /
  `fetchSecondaryIfEnabled` helpers, `fetchSleepSummary`,
  `fetchDailySleepHistory`, `fetchSleepVitals`,
  `hydrateSleepVitalsInParallel`, training-load memoization,
  `fetchSecondaryTrend`, `fetchSecondaryRangeTrend`,
  `fetchSecondaryDaySamples`, `fetchIntradayDaySamples`,
  `incrementalFetchStart`, `mergeIntradaySamples`,
  `fetchHealthSummary`, `fetchHealthTrends`, `sourceOptionsAndMap`,
  static parser helpers),
  `Body/Services/HealthDashboardSnapshotStore.swift` (full).
- App views: `Body/Views/BodyHomeView.swift` (selective via `rg`:
  `metricCards`, every chart struct, source comparison charts,
  training-load presentation, sleep stage / vitals charts, Readiness
  why card, `BodyHealthMetricCard`,
  `BodyHealthMetricCardTrendPreview`, sleep / metric date pickers,
  detail-view dispatch, `.transition` modifiers), full reads of
  `Body/Views/BodyWorkoutsView.swift` (with focus on the new full-
  screen workout detail and `BodyWorkoutHeartRateChart`),
  `Body/Views/BodyProView.swift`, `Body/Views/BodyMonthYearPicker.swift`,
  `Body/Views/BodyActivityRingsDetailView.swift`,
  `Body/Views/BodyWorkoutListSheet.swift`, selective reads of
  `Body/Views/BodySettingsView.swift` (Settings root, version
  display, source sheet, sleep duration goal sheet, version-tap
  unlock).
- Shared models / services: `BodyShared/Models/WorkoutMonthSnapshot.swift`
  (full), `BodyShared/Services/WorkoutSnapshotStore.swift` (full),
  `BodyShared/Models/BodyWorkoutType.swift` (skim),
  `BodyShared/Models/WorkoutSummary.swift` (skim).
- Widget: `BodyWidgetExtension/WorkoutCalendarWidget.swift` (full).
- Configuration: `Body/PrivacyInfo.xcprivacy`,
  `body.xcodeproj/project.pbxproj` (build settings, version pins,
  HealthKit usage description, deployment target).
- Tests: `BodyTests/ProjectConfigurationTests.swift` (function index,
  58 test functions), `BodyTests/ReadinessScoreCalculatorTests.swift`
  (function index — 14+ tests for sleep goal, robust baseline, z-score,
  summary unavailability),
  `BodyTests/HealthKitWorkoutStoreTests.swift` (function index, 14
  tests),
  `BodyTests/BodyWorkoutTypeTests.swift` (function index, 4 tests),
  `BodyTests/WorkoutMonthSnapshotTests.swift` (function index, 147
  tests).
- Docs: `README.md`, `VersionHistory.md`, `TestPlan.md`,
  `LessonsLearned.md`, `Issues-ds.md` (the parallel v0.5.2 audit),
  `Issues.md` (full, prior to archive).
- Archive cross-reference: `docs/IssuesArchive-04.md` N1-N11
  (carry-forward fix verification), spot-check of
  `docs/IssuesArchive-03.md`, `docs/IssuesArchive-02.md`,
  `docs/IssuesArchive-01.md`.
- Grep queries:
  - `rg "TODO|FIXME|XXX|HACK" Body BodyShared BodyWidgetExtension BodyTests`
    — only asset-catalog binary matches; no source TODOs.
  - `rg "Calendar.current" Body BodyShared BodyWidgetExtension` —
    no matches in production (archive 03 N6 stayed fixed).
  - `rg "try!|fatalError|preconditionFailure|as!" Body BodyShared BodyWidgetExtension`
    — no matches.
  - `rg "\.last!|\.first!" Body BodyShared BodyWidgetExtension` —
    one match in `BodyWorkoutsView.swift:1398` (see N11).
  - `rg "UIScrollView.appearance" Body` — no matches (archive 04
    N9 stayed fixed).
  - `rg "DispatchQueue.main" Body BodyShared BodyWidgetExtension` —
    only `BodyProView` flip animation (lines 172, 181) and
    `BodySettingsView:559` (icon-change callback hop). Both are
    bounded UI delays; acceptable.
  - `rg "symbolName: \"plus\"" Body` — three matches at
    `BodyHomeView.swift:394, 678, 1176` (see N1).
  - `rg "Task.sleep" Body BodyShared BodyWidgetExtension` —
    five matches: 15 s timeout in `BodyWorkoutsView`
    (line 394), 100 ms animation in `BodyWorkoutsView:471`, 220 ms
    sheet open delay in `BodySettingsView:590`, 600 ms minimum
    overlay in `HealthKitWorkoutStore:764`, 100 ms per-month busy
    wait in `HealthKitWorkoutStore:843` (see N5).
  - `rg "@AppStorage" Body BodyShared BodyWidgetExtension` —
    44 matches; reviewed for consistency with
    `BodyAppearancePreference` keys.
  - `rg "secondaryHealthDataSourceSelection.signature|secondarySignature" Body/Services`
    — confirmed save-on-update and load-on-init paths.

## Not checked (worth a follow-up)

- Running the project on simulator or device. Verifying N1's icon
  appearance on Home / Trends / Detail, N10's source-row disable
  behavior, the new gradient heart rate chart's render fidelity, the
  combined-sleep-source timeline merging from build 4, and the
  Readiness scoring on real HealthKit data all require a build.
- Lock Screen / accessory widget families (deferred per TestPlan §4).
- HealthKit background delivery (deferred per TestPlan §4).
- Localization beyond English (deferred per TestPlan §4).
- LaunchScreen XML and Xcode shared scheme XML.
- Asset catalog `Contents.json` JSON validation beyond
  `ProjectConfigurationTests.testAppIconAssetsIncludePrimaryAndAlternateOptions`.
- `BodyTests/WorkoutMonthSnapshotTests.swift` (3,631 lines, 147 tests)
  was function-indexed but not read in full; the recent
  `XCTAssertEqual` updates flagged in `git status` were not diffed
  case-by-case.
- Readiness scoring calibration against real multi-user HealthKit
  exports (the weights 30/30/25/15 and the 0.78/0.18 sleep efficiency
  thresholds are heuristic — Issues-ds.md D3 / D4 carried this
  forward; still defensible but unverified empirically).
- The pre-existing modified files visible at the start of this run
  (the Recovery → Readiness rename across docs, tests, and source)
  were taken as the intended branch state and not re-validated.
- Carry-forward verification: archives 01-03 fix resolutions were
  cross-referenced via `rg` and the prior archive's verification
  section, not by re-deriving each fix's behavior on device.
