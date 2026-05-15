# Body — Issues Report

Audit of branch `body-v0.3.5` on 2026-05-15. Read-only review; no code was
modified. The previous report has been archived as
`docs/IssuesArchive-03.md`.

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

Body has shipped v0.3.9 build 2 with new Heart Rate, Wrist Temperature, and
Training Load surfaces, a heart-rate range bar chart, a training-load
interval band with cross-fade-through-chartBackground animation, file-backed
dashboard cache, and refreshed Activity Rings calendar paging. All nine
findings from `docs/IssuesArchive-03.md` (N1-N9) are addressed in code:
project / README / VersionHistory / Settings fallback are aligned at 0.3.9
build 2 (Settings now falls back to "Unknown" rather than hardcoded
strings); the dead `BodyChartsView` file is gone; `accessoryMetrics` is
removed; the sleep/metric date pickers share `dateTile(for:picker:)`; the
sleep-stage axis and widget timeline use `Calendar.bodyGregorian`; and
`NSHealthShareUsageDescription` enumerates all 12 read categories.

The current run surfaces a smaller crop of issues focused on consistency,
not correctness. The most user-facing item is N1 — the chart-switch
fade animation that was added to `BodyHealthMetricTrendChart` is missing
from `BodyBasicsTrendChart`, `BodyBasicsBodyMassIndexTrendChart`, and
`BodyHeartRateRangeTrendChart`, so Basics / BMI / Heart Rate Range detail
pages still hard-snap when the user switches between Week / Month / etc.
N2-N3 are documentation drift (README screenshots and TestPlan branch /
card list both predate the v0.3.9 additions). N4-N5 are small Body Pro
purchase-page UX inconsistencies that were partly noted in archive 03.
The remainder are hygiene items: BodyHomeView.swift continues to grow
(now 6,289 lines), HealthSummarySnapshot.swift bundles model + calculator
+ store (2,608 lines), and a few small surprises in animations,
pagination timeouts, and global `UIScrollView.appearance()` side effects.

Areas reviewed: app entry / scene phase, HealthKit ingestion
(authorization, summary, trends, training-load and heart-rate-range
queries, activity rings), workout aggregation, snapshot persistence (file
+ app-group + UserDefaults legacy migration), Summary dashboard, Workouts
tab (now with pending-month banner), Settings (Body Pro entry, Permissions,
theme, accent, icon, units, version unlock), Body Pro page, month-year
picker, widgets, entitlements, project build settings, privacy manifests,
the recently-refactored training-load interval band (chartBackground +
SwiftUI Rectangles), and the test suite. Intentionally not reviewed:
rendered runtime behavior on device (no build in this run), Lock Screen /
Accessory widget families, localization, LaunchScreen XML, Xcode shared
scheme XML, asset catalog binary contents beyond
`ProjectConfigurationTests` validation.

---

## 2. Issue list

### N1. Range-switch fade only applies to `BodyHealthMetricTrendChart`; Basics, BMI, and Heart Rate Range charts snap

- **Severity:** Medium
- **Related files:** `Body/Views/BodyHomeView.swift:4280-4300` (trend chart
  with `.transition`), `Body/Views/BodyHomeView.swift:3835-3839`
  (`BodyBasicsBodyMassIndexTrendChart` — `.id` + `.transaction { animation = nil }`
  only), `Body/Views/BodyHomeView.swift:4614-4619`
  (`BodyBasicsTrendChart`), `Body/Views/BodyHomeView.swift:4014-4018`
  (`BodyHeartRateRangeTrendChart`)
- **Description:** The recent animation pass added a `.transition(
  .opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration:
  0.35)))` modifier between `.id(chartIdentity)` and the `.transaction`
  blocks of `BodyHealthMetricTrendChart`. The three other chart structs
  that also rebuild on range change — the Basics dual-axis chart, the BMI
  chart, and the Heart Rate Range bar chart — keep the older shape:
  ```swift
  .chartXSelection(value: $selectedDate)
  .simultaneousGesture(chartPressGesture)
  .id(selectedRange.rawValue)             // or .id("heart-rate-range-\(...)")
  .transaction { transaction in
      transaction.animation = nil
  }
  ```
  with no `.transition`. When the user taps Week → Month on the Basics
  detail (or BMI panel below, or Heart Rate detail's range bar chart),
  the chart hard-cuts; the line chart above (which is the standard trend
  chart) cross-fades. The mismatch is visible on a single screen because
  the Basics detail renders the dual-axis chart and BMI chart back to
  back, and the Heart Rate detail renders the line chart and the range
  chart back to back.
- **Why it matters:** UX inconsistency on the same screen. The behaviour
  reads as a partial fix rather than a polish pass. Reduce-Motion users
  are unaffected.
- **Suggested fix:** Mirror the trend-chart modifier shape on each of the
  three remaining charts. Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion`
  to each, then insert
  ```swift
  .transition(.opacity.animation(reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.35)))
  ```
  between the existing `.id(...)` and `.transaction { transaction.animation = nil }`.
  No new tests are required; the existing `ProjectConfigurationTests`
  chart-structure assertions do not pin these structs.
- **Risks / dependencies:** None. Mirrors the existing trend-chart change.

### N2. `README.md` screenshots are pinned to `v0.3.3` but the build is `v0.3.9`

- **Severity:** Low
- **Related files:** `README.md:14-23`, `Screenshots/v0.3.3-01.PNG`
  through `Screenshots/v0.3.3-06.PNG`
- **Description:** README v0.3.9 (build 2) embeds six screenshots whose
  filenames are `Screenshots/v0.3.3-NN.PNG`. v0.3.4 added animated Summary
  numbers; v0.3.9 added the Heart Rate, Training Load, and Wrist
  Temperature cards plus the training-load interval band. None of those
  surfaces can appear in v0.3.3 screenshots.
- **Why it matters:** A reader landing on README sees a v0.3.9 build line
  but stale UI screenshots. New cards / new range-aware long charts are
  invisible. Low impact because the README is also for repo browsers.
- **Suggested fix:** Either (a) refresh the screenshots and rename to
  `Screenshots/v0.3.9-NN.PNG`, updating the six `<img>` references in
  README, or (b) keep v0.3.3 screenshots but mark them "older UI". (a) is
  the cleaner option since the test file does not pin screenshot names.
- **Risks / dependencies:** None. No test references screenshot filenames
  (`rg "Screenshots/v0" BodyTests` is empty).

### N3. `TestPlan.md` is pinned to branch `codex/body-v0.3.4` and does not list Heart Rate or Training Load cards

- **Severity:** Low
- **Related files:** `TestPlan.md:3`, `TestPlan.md:58` (M13 enumeration)
- **Description:** `TestPlan.md:3` reads "Generated 2026-05-13 against
  branch `codex/body-v0.3.4`"; the current branch is `body-v0.3.5` and
  the shipped build is v0.3.9 (build 2). M13 enumerates the Summary
  cards as "Exercise Minutes, Wrist Temperature, Time In Daylight, Steps,
  Sleep, Basics, resting heart rate, HRV, blood oxygen, respiratory rate,
  active energy, and resting energy" (12 cards), but the live list now
  also includes `trainingLoad` (`Body/Views/BodyHomeView.swift:188-198`)
  and `heartRate` (`Body/Views/BodyHomeView.swift:227-236`). There is no
  case for the training-load interval bands, the training-load
  distribution breakdown, or the heart-rate range bar chart. Carry-forward
  from archive 03 N8.
- **Why it matters:** TestPlan is treated as authoritative in commit
  messages and audits. Drift hides untested surfaces (training-load
  interval transitions, heart-rate range chart axes, the new day-chart
  cross-fade) from the audit trail. Manual coverage matters for
  HealthKit-bound features that unit tests cannot exercise.
- **Suggested fix:** Update branch reference to `body-v0.3.5`; add cases
  for: Training Load card + interval band + interval distribution;
  Heart Rate card + range chart; the chart-switch cross-fade (M13 or a
  new manual case); the Workouts pending-month loading banner (no
  current case). Update "What Was Reviewed" to include
  `BodyHomeView.swift`'s new chart structs.
- **Risks / dependencies:** None. Pair with N2 so docs ship together.

### N4. Body Pro "Lifetime" card shows a price but the buy button only sets a status string

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:41-50,250-287`,
  `Body/Views/BodyProView.swift:80-110`
- **Description:** `BodyProPurchaseOptionCard` renders "Lifetime — One
  purchase for lifetime Body Pro access — $5.99 — arrow button". Tapping
  the arrow calls `onChoose`, which is `statusMessage = "Body Pro
  lifetime purchases are not available in this build."` (line 48). The
  same shape repeats for "Redeem Pro" (line 89) and "Restore Purchases"
  (line 100). A user landing on the page sees a price and a styled
  purchase button — nothing in the disabled state suggests this is a
  placeholder. The footnote-sized "not available" status only appears
  after the tap. Already partially noted in archive 03's UI/UX section.
- **Why it matters:** Mistakes Body Pro for a real purchase surface.
  Either users get confused or — once IAP wiring exists — the visual
  states will need redoing anyway. Low priority because the page is
  reachable only from Settings > Body Pro.
- **Suggested fix:** Either (a) disable the three buttons + show a
  static "Coming Soon" pill on the Lifetime card, or (b) gate the
  Lifetime / Redeem / Restore stack behind a `#if PRO_PURCHASES_ENABLED`
  feature flag and ship a single "Body Pro is coming" message until
  the IAP wiring exists. Visual verification on device.
- **Risks / dependencies:** None.

### N5. Body Pro feature rows and the "Future Pro Updates" placeholder share the same gold checkmark

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:289-315,363-388`
- **Description:** `BodyProFeatureRow` (line 289) renders a feature with
  `BodyProFeatureCheckmark()` on the right edge — a gold filled
  checkmark — used as an "unlocked" indicator. `BodyProFutureUpdatesNote`
  (line 363) is a placeholder row that says "More Body Pro features will
  be added in future updates" and renders the same
  `BodyProFeatureCheckmark()`. The placeholder reads as if "future
  updates" is itself an unlocked feature.
- **Why it matters:** Confusing semantics on a marketing page. The
  checkmark icon implies "this is included"; the row body says "this is
  coming later". Trivial to fix; low impact.
- **Suggested fix:** Replace the checkmark on `BodyProFutureUpdatesNote`
  with a less definitive glyph (`sparkles`, `arrow.up.forward.circle`,
  or simply omit it). Keep the gold checkmark on real feature rows.
- **Risks / dependencies:** None.

### N6. `BodyHealthMetricTrendChart` has a leftover empty line where the highlight `RectangleMark`s used to live

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift:4136-4143`
- **Description:** When the highlight-band rendering moved out of
  `Chart { ... }` and into `.chartBackground { chartProxy in ... }`
  earlier in this branch, the conditional `if let highlightedRange =
  displayedHighlightedRange { ... }` block was removed but the empty
  line it occupied was not collapsed:
  ```swift
  Chart {

      if chartStyle == .bar, let selectedTrendPoint {
  ```
  Two-line-pad before the first remaining mark. Cosmetic only.
- **Why it matters:** Style nit; will eventually drift into a "why is
  this here?" comment thread on a future PR. Affects nothing at
  runtime.
- **Suggested fix:** Delete the blank line after `Chart {`.
- **Risks / dependencies:** None.

### N7. `BodyHomeView.swift` is now 6,289 lines and bundles every detail screen, ring graphic, and card background extension

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift` (whole file)
- **Description:** The file grew from ~5,585 lines in archive 03 to 6,289
  lines in this run with the Training Load / Heart Rate / Wrist
  Temperature additions and the chartBackground refactor. It still
  bundles: the Home grid, `BodyHealthMetricDetailView` (and every sleep
  supplement card, basics range card, BMI panel), 5 distinct chart
  structs (`BodyHealthMetricTrendChart`, `BodyHealthMetricDayChart`,
  `BodyBasicsTrendChart`, `BodyBasicsBodyMassIndexTrendChart`,
  `BodyHeartRateRangeTrendChart`), the `BodySleepStageChart` and
  `BodySleepVitalsRegionChart`, `BodyActivityRingsDetailView` + ring
  graphic / arc / completion-star, training-load interval
  presentation + interval breakdown chart, and several View extensions
  for card backgrounds.
- **Why it matters:** Editor latency, find-in-file pain, and merge
  conflicts. Same observation as archive 03 N7; the file kept growing.
- **Suggested fix:** Carve off in three medium-size moves: (1)
  `BodyActivityRingsDetailView` + ring graphic into
  `BodyActivityRingsDetailView.swift` (~900 lines), (2)
  `BodyHealthMetricDetailView` plus its sleep / basics panels into
  `BodyHealthMetricDetailView.swift` (~1,500 lines), (3) the five chart
  structs into a `Charts/` group. Each split must be verified against
  `ProjectConfigurationTests`'s several `source.range(of: "private struct
  ...")` lookups (chart prefixes are 7,500 / 12,000 / 3,200 chars wide
  in different tests) — increasing prefixes if necessary.
- **Risks / dependencies:** `ProjectConfigurationTests` performs source
  substring assertions across `BodyHomeView.swift`; splits must keep
  those assertions valid (most tests look up by struct name so they
  survive file moves).

### N8. `HealthSummarySnapshot.swift` is 2,608 lines and bundles snapshot, trend, calculator, and store types

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift` (whole
  file)
- **Description:** The file holds `HealthMetricKind`, `HealthMetricSummary`,
  `HealthSummarySnapshot`, `HealthDashboardSnapshot`,
  `HealthDashboardSnapshotStore` (file-backed),
  `HealthTrendSnapshot`, `HealthTrendSeries`,
  `HealthTrendCalendarPoint`, `HealthTrendRangeCalendarPoint`,
  `HealthTrendHourlyBucket`, `HealthTrendStableLineBucket`,
  `HealthTrendRangeSeries`, `SleepSummary`, `SleepStageSnapshot`,
  `SleepScoreSummary`, `SleepVitalsSummary`, `SleepHistorySnapshot`,
  `ActivityRingSummary`, `ActivityRingMetric`,
  `ActivityRingHistorySnapshot`, `ActivityRingDaySummary`,
  `ActivityRingCalendarMonth`, `ActivityRingCalendarDay`,
  `ActivityRingMonthKey`, `TrainingLoadCalculator`,
  `TrainingLoadInterval`, `TrainingLoadIntervalBreakdownEntry`, and
  `TrainingLoadIntervalBreakdown`. Plus `decodeIfPresent` plumbing for
  each new property as snapshots evolved.
- **Why it matters:** Same class of issue as N7. The file is the
  authoritative source for HealthKit data shapes; future contributors
  do a lot of scrolling.
- **Suggested fix:** Split by concern: `Models/Snapshots/` for
  summary / dashboard / trend snapshots; `Models/Sleep/` for sleep
  summary + score + vitals; `Models/ActivityRings/` for ring summary +
  history + calendar; `Models/TrainingLoad/` for calculator + interval
  + breakdown; `Services/HealthDashboardSnapshotStore.swift` for the
  file-backed store (it is a service, not a model). No fix until N7 is
  also touched, to avoid two large concurrent moves.
- **Risks / dependencies:** `decodeIfPresent` round-trip is covered by
  `HealthKitWorkoutStoreTests.testHealthDashboardSnapshotStoreRoundTripsCachedHomeData`
  and friends; any move must keep `HealthDashboardSnapshot.CodingKeys`
  stable so cached files keep decoding.

### N9. `BodyApp.init()` sets `UIScrollView.appearance()` indicator flags globally

- **Severity:** Low
- **Related files:** `Body/BodyApp.swift:16-19`
- **Description:**
  ```swift
  init() {
      UIScrollView.appearance().showsVerticalScrollIndicator = false
      UIScrollView.appearance().showsHorizontalScrollIndicator = false
      WorkoutSnapshotStore.seedPreviewSnapshotIfNeeded()
  }
  ```
  `UIScrollView.appearance()` affects every `UIScrollView` the process
  hosts — Body's `ScrollView`s, system sheets that contain
  `UIScrollView`s, presentation sheets, alerts that scroll, the
  app-icon picker scroll view inside a system sheet, and (in theory)
  any third-party `SFSafariViewController` content. All Body's
  `ScrollView` callers already pass `showsIndicators: false`, so the
  global pin is redundant for app-owned views; the side effect on
  system views is the concern.
- **Why it matters:** Subtle global mutation. The intent reads "hide
  scroll indicators app-wide", but the side effect on system / sheet
  scroll views may not be desirable. Users on iOS 18+ generally expect
  the system's auto-hide indicator behavior on system sheets.
- **Suggested fix:** Remove both `UIScrollView.appearance()` lines and
  rely on the `showsIndicators: false` parameter already passed to each
  SwiftUI `ScrollView`. If the in-app picker scroll behaviors regress,
  add `.scrollIndicators(.hidden)` per view instead of using the global
  appearance proxy. Needs visual verification on device.
- **Risks / dependencies:** Visual diff on Settings > App Icon picker
  scroll view, Sleep Score detail sheet, and any other scrollable
  sheet.

### N10. Workouts pending-month banner has no timeout if the HealthKit query never completes

- **Severity:** Low
- **Related files:** `Body/Views/BodyWorkoutsView.swift:360-387`
- **Description:** `requestMonthYearSelection` sets `pendingMonthSelection
  = monthYear`, fires a task that calls `workoutStore.loadMonthIfNeeded(...)`,
  and only clears `pendingMonthSelection` inside the task's
  `MainActor.run` block. If `loadMonthIfNeeded` hangs (the store's
  `while isRefreshing, !Task.isCancelled { try? await Task.sleep(...) }`
  loop in `HealthKitWorkoutStore.swift:173-183,181-183` can in theory
  spin forever if `isRefreshing` never flips false), the
  pending-month banner stays visible until the user navigates away.
  No user-visible failure mode short of a HealthKit query hang.
- **Why it matters:** Theoretical, not observed. Worth a timeout for
  defensive UX once we have telemetry.
- **Suggested fix:** Either (a) wrap the load in
  `await withTaskCancellationHandler` and set a 15-second deadline that
  clears `pendingMonthSelection` + shows a one-shot "Try again later"
  toast, or (b) add a `cancelPendingMonthLoad()` button to the banner
  that the user can hit if the load stalls. (a) is more robust; (b) is
  cheaper.
- **Risks / dependencies:** None. Touches view state only.

### N11. `versionTapCount` persists across navigations away from Settings

- **Severity:** Low
- **Related files:** `Body/Views/BodySettingsView.swift:20,343-355`
- **Description:** `versionTapCount` is a `@State` on `BodySettingsView`.
  `handleVersionCardTap()` only resets the counter when it reaches 5
  (the unlock count). If the user taps 4 times on the Version row,
  navigates to Body Pro / Permissions / another tab, comes back, and
  taps once more, the counter is at 5 and the unlock fires. Practically
  the counter never resets unless the unlock triggers (the view stays
  in the tab navigation stack), so the "five taps in a row" guarantee
  isn't enforced.
- **Why it matters:** The five-tap unlock is a subtle Easter-egg gate;
  carrying the count silently is mildly surprising. Edge case. Same
  view-state pattern as `versionTapCount` carry-over is harmless if
  the user is doing it on purpose.
- **Suggested fix:** Reset `versionTapCount = 0` in an
  `.onAppear { versionTapCount = 0 }` on the Settings view, or wrap
  taps in a debounce that resets the counter when 1.5 seconds elapse
  between taps. The `.onAppear` reset is the smallest behavior change.
- **Risks / dependencies:** None.

---

## 3. Code quality findings

- **Duplicated code:**
  - `Body/Views/BodyHomeView.swift:4053-4302` (`BodyHealthMetricTrendChart`)
    vs. `Body/Views/BodyHomeView.swift:3890-4020` (`BodyHeartRateRangeTrendChart`)
    vs. `Body/Views/BodyHomeView.swift:4380-4620` (`BodyBasicsTrendChart`)
    vs. `Body/Views/BodyHomeView.swift:3698-3840`
    (`BodyBasicsBodyMassIndexTrendChart`) — all four chart structs
    redeclare the same `chartPressGesture`, `selectedDate` /
    `isSelecting` selection state, `chartXAxis` / `chartYAxis` axis
    styling, and `chartXSelection` wiring. Lifting a shared
    `BodyHealthChartSelectionState` view modifier (or extracting the
    axis bodies into private functions) would cut ~200 lines and is
    a precondition to fixing N1 cleanly.
  - The weekday-header pair in `BodyActivityRingsDetailView`
    (`Body/Views/BodyHomeView.swift:5433-5450`) still inlines
    `weekdayHeader` + `weekdaySymbols` instead of calling the shared
    helper in `BodyShared/Models/WorkoutMonthSnapshot.swift:206-220`.
    Carry-forward observation from archive 03.

- **Unused or outdated files / symbols:**
  - None new. `BodyChartsView.swift` and `BodyHealthMetricCard.AccessoryMetric`
    from archive 03 are gone.

- **Overly complex files or functions:**
  - `Body/Views/BodyHomeView.swift` — 6,289 lines (see N7).
  - `Body/Models/HealthSummarySnapshot.swift` — 2,608 lines (see N8).
  - `Body/Services/HealthKitWorkoutStore.swift` — 2,187 lines; smaller
    surface than the above two, but `loadMonthIfNeeded` polling
    (`HealthKitWorkoutStore.swift:166-191`) with three nested
    `while ... { try? await Task.sleep(nanoseconds: 100_000_000) }`
    busy-waits is a smell that could be replaced with a single
    `withCheckedContinuation` keyed off the `loadingMonthKeys` set.
    Same intent, no 100 ms polling loop. Not blocking; flag only.

- **Naming inconsistencies:**
  - `BodyHealthMetricCard.Model.unit` is `""` for the home-card preview
    of Exercise Minutes / Steps / Training Load
    (`Body/Views/BodyHomeView.swift:181,192,218`) but the detail page
    sets `unit: "min"` / `"steps"` / `""` for the same metrics
    (`Body/Views/BodyHomeView.swift:741,809,753`). The home card by
    design omits the unit, but the inconsistency in the model parameter
    name (`unit: ""` vs. `unit: "min"` for the same `kind`) makes the
    helper call hard to read. Cosmetic.

- **Structural improvements:**
  - Lift a `BodyTrendChartContainer` modifier or wrapper that supplies
    `.chartXSelection`, `.simultaneousGesture`, `.id`, `.transition`,
    and the `.transaction { animation = nil }` to all four range-aware
    chart structs. This is the cleanest way to fix N1 without copying
    the same six modifiers four times.

---

## 4. Functional issues

- **Range-switch animation gap (N1):** Basics dual-axis, BMI, and Heart
  Rate Range charts snap when switching Week / Month / 6 Months /
  Year; the other line and bar charts cross-fade. Visible on the
  Basics and Heart Rate detail screens because both render multiple
  charts back-to-back.
- **No other functional regressions surfaced in this run.** All nine
  prior findings (N1-N9 in archive 03) have been confirmed against
  the current code:
  - Version drift (archive N1) — fixed; tests pin 0.3.9 build 2.
  - Workouts pending-month UX (archive N2) — fixed; banner at
    `BodyWorkoutsView.swift:40-44`.
  - `BodyChartsView` dead code (archive N3) — file removed.
  - `accessoryMetrics` dead branch (archive N4) — removed.
  - Sleep / metric date-picker duplicates (archive N5) — collapsed
    into `dateTile(for:picker:)` at `BodyHomeView.swift:2344`.
  - `Calendar.current` callers (archive N6) — none remain
    (`rg "Calendar.current" Body BodyShared BodyWidgetExtension` is
    empty; widget timeline uses `Calendar.bodyGregorian`).
  - HealthKit usage description (archive N7) — enumerates all 12
    categories at `body.xcodeproj/project.pbxproj:468,506`.
  - TestPlan branch reference (archive N8) — partially fixed; see N3
    above.
  - Settings appVersionDisplay fallback (archive N9) — now "Unknown"
    at `BodySettingsView.swift:238-240`.

---

## 5. UI/UX issues

- **Chart-switch animation inconsistency (N1)** — most visible issue.
- **Body Pro purchase buttons (N4) and "Future Updates" checkmark
  (N5)** — small marketing-page polish items.
- **Body Pro page presents a real-looking purchase UI without a
  disabled state** (carry-forward observation from archive 03 N4) —
  the only disabled feedback is the post-tap status message; nothing
  in the steady state communicates "placeholder".

---

## 6. Data and persistence issues

- **`HealthDashboardSnapshotStore` now writes to Application Support
  (`HealthDashboardSnapshotStore/lastHealthDashboardSnapshot.json`)
  with proper `do/catch` and `os.Logger` failure paths.** Verified at
  `Body/Models/HealthSummarySnapshot.swift:1299-1402`. The legacy
  UserDefaults blob is migrated on first load and deleted after a
  successful re-write.
- **No schema version field on either `WorkoutMonthSnapshot` or
  `HealthDashboardSnapshot`.** Carry-forward observation. Additions
  tolerate via `decodeIfPresent`, but a workout-type case removal
  would break the entire decode. Not a near-term concern.
- **No new persistence regressions.** `WorkoutSnapshotStore` and the
  shared app group key `group.com.zihengthedeveloper.Body` are
  unchanged and covered by `testAppAndWidgetShareAppGroupEntitlement`.

---

## 7. Configuration and platform issues

- **Build settings:** `MARKETING_VERSION = 0.3.9` /
  `CURRENT_PROJECT_VERSION = 2` in all six configurations
  (`body.xcodeproj/project.pbxproj:462,479,500,517,538,550,568,580,595,605,620,630`).
  `ProjectConfigurationTests.swift:355-373` pins this.
- **HealthKit usage description:** Now enumerates "workouts, Activity
  Rings, sleep, heart rate, HRV, blood oxygen, respiratory rate, body
  measurements, energy, exercise minutes, wrist temperature,
  daylight, and steps" (project.pbxproj:468, 506). All 12 read
  categories are covered.
- **App group:** `group.com.zihengthedeveloper.Body` parities app +
  widget entitlements.
- **Privacy manifests:** `Body/PrivacyInfo.xcprivacy` and
  `BodyWidgetExtension/PrivacyInfo.xcprivacy` both declare
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` and
  `NSPrivacyTracking = false`. No `NSPrivacyCollectedDataTypes`.
- **Deployment target:** `IPHONEOS_DEPLOYMENT_TARGET = 18.0` across
  all six configurations.
- **`UIScrollView.appearance()` global (N9)** — process-wide
  side effect from `BodyApp.init()`.

---

## 8. Testing gaps

- **Highest-risk uncovered features:**
  - `BodyHealthMetricTrendChart` chartBackground render path (the new
    SwiftUI Rectangle overlay) — `testTrainingLoadTrendChartDrawsDynamicHorizontalCurrentIntervalBandWithoutInlineLabel`
    (`BodyTests/ProjectConfigurationTests.swift:168`) covers the source
    shape but not the runtime layout against the chart proxy's
    `plotFrame` and `position(forY:)`.
  - The three charts in N1 — no test pins their range-switch
    transition (which is what makes the missing `.transition` invisible
    until you flip ranges on a device).
  - `BodyActivityRingsDetailView` scroll-to-current-month after the
    recent `ScrollViewReader + proxy.scrollTo` restore — no test pins
    that the calendar opens with the current month at the bottom.
  - `loadMonthIfNeeded` polling loop in
    `HealthKitWorkoutStore.swift:166-191` — no test for the
    "while isRefreshing" wait timing.

- **Suggested tests:**
  - Add a `ProjectConfigurationTests` source-shape assertion for the
    three charts in N1 (similar to the existing
    `testTrainingLoadTrendChart...` block) that pins
    `.transition(.opacity.animation(...))` on each.
  - Add an integration / preview test that renders
    `BodyActivityRingsDetailView` with a fixture history and asserts
    the bottom-most month section ID matches today's `ActivityRingMonthKey`.
  - Manual / on-device cases that need to land in `TestPlan.md`
    (see N3):
    - Training Load card on Summary, interval band at scrub, interval
      distribution bar (per range).
    - Heart Rate card on Summary, heart-rate range bar chart at each
      range, range-switch animation parity (post-N1 fix).
    - Body Pro Lifetime / Redeem / Restore in placeholder state (N4).
    - Workouts pending-month banner during a real HealthKit load.

---

## 9. Priority recommendations

- **Fix first:**
  - **N1** — extend the chart-switch fade to Basics, BMI, and
    Heart Rate Range charts. Single-screen visible inconsistency.
- **Fix next:**
  - **N2** — refresh README screenshots to v0.3.9 (or note them as
    older UI).
  - **N3** — update `TestPlan.md` branch reference and add Training
    Load / Heart Rate / range-switch animation / pending-month
    coverage.
  - **N4** — clarify Body Pro purchase placeholder UI.
- **Optional cleanup:**
  - **N5** — remove the misleading checkmark on the Body Pro
    "Future Updates" row.
  - **N6** — collapse the blank line inside `Chart {}` after the
    chartBackground refactor.
  - **N7 / N8** — split `BodyHomeView.swift` and
    `HealthSummarySnapshot.swift` into smaller files.
  - **N9** — drop the global `UIScrollView.appearance()` calls.
  - **N10** — add a timeout / cancel for the Workouts pending-month
    banner.
  - **N11** — reset `versionTapCount` on Settings appear.

---

## What was checked

- App entry: `Body/BodyApp.swift`, `Body/Views/MainTabView.swift`.
- App models: `Body/Models/BodyAppearancePreference.swift` (selective:
  `BodyHealthPermission`, `BodyHealthPermissionSelection`,
  `BodyHomeCardKind`, `BodyHealthTrendRange`),
  `Body/Models/HealthSummarySnapshot.swift` (selective: training-load
  calculator, training-load interval, dashboard store, trend snapshot,
  metric detail help text).
- App services: `Body/Services/HealthKitWorkoutStore.swift` (selective:
  `loadMonthIfNeeded`, `fetchTrainingLoadSummary` /
  `fetchTrainingLoadSeries`, `fetchSavedEffortLevel`,
  `recentHealthTrendInterval`).
- App views: `Body/Views/BodyHomeView.swift` (selective via `rg`:
  trend card, day chart card, training-load presentation /
  breakdown, heart-rate range chart, activity rings detail, basics
  range card, animations + `.transition` modifiers, `Calendar.current`
  callers, `metricCards` definition site),
  `Body/Views/BodyWorkoutsView.swift` (full),
  `Body/Views/BodySettingsView.swift` (selective: appearance section,
  Body Pro entry card, version unlock handler, `appVersionDisplay`),
  `Body/Views/BodyProView.swift` (full),
  `Body/Views/BodyMonthYearPicker.swift` (skim).
- Shared models / services: `BodyShared/Models/WorkoutMonthSnapshot.swift`,
  `BodyShared/Services/WorkoutSnapshotStore.swift`.
- Widget: `BodyWidgetExtension/WorkoutCalendarWidget.swift` (full).
- Configuration: `Body/PrivacyInfo.xcprivacy`,
  `body.xcodeproj/project.pbxproj` (build settings, version pins,
  HealthKit usage description, deployment target).
- Tests: `BodyTests/ProjectConfigurationTests.swift` (function index +
  recent version / chart assertions), `BodyTests/HealthKitWorkoutStoreTests.swift`
  (function index), `BodyTests/BodyWorkoutTypeTests.swift` (function
  index).
- Docs: `README.md`, `VersionHistory.md`, `TestPlan.md`,
  `LessonsLearned.md`.
- Archive cross-reference: `docs/IssuesArchive-03.md` N1-N9.
- Grep queries:
  - `rg "TODO|FIXME|XXX|HACK" Body BodyShared BodyWidgetExtension BodyTests`
    — no matches.
  - `rg "Calendar.current" Body BodyShared BodyWidgetExtension` — no
    matches.
  - `rg "try!|fatalError|preconditionFailure|as!" Body BodyShared
    BodyWidgetExtension` — no matches.
  - `rg "try?" Body BodyShared BodyWidgetExtension` — only
    `try? await Task.sleep(...)` callers remain; no silent JSON
    paths.
  - `rg "model.title ==" Body/Views` — no matches (archive 02 N2 stayed
    fixed).
  - `rg "BodyChartsView" Body BodyShared BodyTests` — no matches.
  - `rg "accessoryMetrics|AccessoryMetric" Body BodyShared` — no
    matches.
  - `rg "\.transition" Body/Views/BodyHomeView.swift` — confirms only
    the trend chart, the day-chart card, and the sleep-stage card use
    `.transition(...)`; the three charts in N1 do not.
  - `rg "displayedHighlightedRange" Body/Views/BodyHomeView.swift` —
    confirms the let binding is read inside `chartBackground` after
    the refactor.

## Not checked (worth a follow-up)

- Running the project on simulator or device. Verifying N1's range-switch
  animation on Basics / BMI / Heart Rate detail pages, the Activity
  Rings calendar's scroll-to-current-month on first open, the new
  training-load interval band + color cross-fade, and the heart-rate
  range chart axes all require a build.
- Lock Screen / accessory widget families (deferred per TestPlan §4).
- HealthKit background delivery (deferred per TestPlan §4).
- Localization beyond English (deferred per TestPlan §4).
- LaunchScreen XML and Xcode shared scheme XML.
- Asset catalog `Contents.json` JSON validation beyond
  `ProjectConfigurationTests.testAppIconAssetsIncludePrimaryAndAlternateOptions`.
- `WorkoutMonthSnapshotTests.swift` (2,420 lines) was function-indexed
  but not read in full.
- N9 (`UIScrollView.appearance()` global) needs visual verification on
  sheets and the app-icon picker.
- N10 (pending-month timeout) is theoretical; needs Instruments to
  confirm the `while isRefreshing` busy-wait can actually stall.
