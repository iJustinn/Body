# Body — Issues Report

Audit of branch `codex/body-v0.3.3` on 2026-05-13. Read-only review; no code
was modified. No prior `Issues.md` was present at the repo root, so no
archive rename happened in this run (the previous report is preserved as
`docs/IssuesArchive-02.md`).

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

Body v0.3.3 is a coherent three-tab app (Summary / Workouts / Settings)
backed by a HealthKit-powered dashboard, a Workouts history surface, two
widgets, and a Body Pro upsell page. The architecture survived the v0.2.6
fix pass intact: silent `try?` JSON paths are gone, the metric detail view
branches on `HealthMetricKind` rather than display titles, and the
month-year picker rebuilds on day-change notifications. The most
user-affecting risks in this run cluster in three places: (1) version-string
drift across project / docs / in-app fallback now that the build bumped
from 1 to 2 mid-v0.3.3, (2) `BodyWorkoutsView` immediately switches to a
not-yet-loaded month and shows the "No workouts" empty state with no
loading hint, and (3) `BodyChartsView` plus several helpers in the same
file are dead code that the file's name still implies are alive.
Smaller hygiene items include a substantial copy-paste between the sleep
and metric day-pickers, two unused `accessoryMetrics` paths inside
`BodyHealthMetricCard.Model`, and a couple of `Calendar.current` callers in
otherwise-`bodyGregorian` code. Areas reviewed: app entry / scene phase,
HealthKit ingestion (authorization, summary, trends, activity rings),
workout aggregation, snapshot persistence (file + UserDefaults), Summary
dashboard, Workouts tab, settings (theme / accent / icon / units /
permissions / about / Body Pro), month-year picker, widgets, entitlements,
project build settings, privacy manifests, and the test suite.
Intentionally not reviewed: rendered runtime behavior on device (no build
in this run), asset catalog binary contents (only path existence per
`ProjectConfigurationTests`), LaunchScreen XML, Xcode scheme XML.

---

## 2. Issue list

### N1. `CURRENT_PROJECT_VERSION` bumped to 2 but README, VersionHistory, and the Settings fallback still report build 1

- **Severity:** Medium
- **Related files:** `body.xcodeproj/project.pbxproj:462,500,538,568,595,620`,
  `README.md:11`, `VersionHistory.md:3-5`,
  `Body/Views/BodySettingsView.swift:237-241`
- **Description:** The latest commit `309578d` ("Refine health chart range
  presentation") bumped `CURRENT_PROJECT_VERSION` from 1 to 2 in all six
  configurations and updated `ProjectConfigurationTests.testProjectBuildSettingsMatchInitialReleasePlan`
  (`BodyTests/ProjectConfigurationTests.swift:201` now asserts `= 2`). The
  rest of the project still presents build 1:
  - `README.md:11` — "Current app version: **0.3.3 (build 1)**"
  - `VersionHistory.md:3-5` — only "0.3.3 (build 1)" exists; no entry for
    build 2 even though build 2 added range-aware line caps, basics
    averages legend, and aggregated long-range chart buckets.
  - `Body/Views/BodySettingsView.swift:239` — `appVersionDisplay` falls
    back to `"1"` (`buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"`).
- **Why it matters:** Three sources of truth (project settings, docs,
  in-app Settings fallback) disagree. The Settings fallback is unreachable
  while the Info.plist is intact, but it silently becomes wrong if those
  keys ever go missing. The README/VersionHistory drift is the same class
  of bug archive N3 flagged for v0.2.6.
- **Suggested fix:** Either (a) decide build 2 is the shipped state, add a
  VersionHistory entry for "0.3.3 (build 2)" that lists the chart range /
  basics legend / point-cap changes, bump the README line to "build 2", and
  change the Settings fallback to `"2"`, or (b) revert the project to
  `CURRENT_PROJECT_VERSION = 1` and update the configuration test. Option
  (a) matches the recent commits; pick it unless build 2 was unintended.
- **Risks / dependencies:** `ProjectConfigurationTests.testProjectBuildSettingsMatchInitialReleasePlan`
  must agree with the chosen number; per the 2026-05-12 lessons-learned
  entry, missing this is the usual gate that fails on a fresh test run.

### N2. `BodyWorkoutsView` shows the "No workouts" empty state during a pending month load

- **Severity:** Medium
- **Related files:** `Body/Views/BodyWorkoutsView.swift:11-13,125-131,304-351,353-370`
- **Description:** `requestMonthYearSelection(_:)` updates
  `selectedMonth/Year` immediately (lines 358-359), starts a detached
  `Task { _ = await workoutStore.loadMonthIfNeeded(...) }`, and returns
  `true` so the picker keeps the new selection. `selectedSnapshot`
  immediately resolves to `workoutStore.snapshot(month:year:)`, which for
  unloaded months returns an empty placeholder built by
  `WorkoutMonthSnapshot.make(... workouts: [])`
  (`Body/Services/HealthKitWorkoutStore.swift:132-139`). `allWorkouts`
  becomes `[]`, `filteredWorkouts` becomes `[]`, and the view renders
  `emptyStateView`:
  ```swift
  if visibleWorkouts.isEmpty {
      emptyStateView
  }
  ```
  with either "Try selecting more workout types in the filter" (when
  `hasActiveFilters`) or "No workouts for May 2026". There is no loading
  indicator while the HealthKit query is in flight. The deleted
  `BodyChartsView` (`Body/Views/BodyChartsView.swift:31-35,144-164`) used
  to render a `BodyChartsLoadingBanner` for the same flow.
- **Why it matters:** A user scrubbing the month picker quickly past
  unloaded months sees an empty state that reads as "this month has no
  workouts" rather than "loading". For months that genuinely have data,
  the user has no signal that anything is happening — they may scroll
  back, conclude the data is missing, and try to refresh.
- **Suggested fix:** Add a pending-month state to `BodyWorkoutsView`
  (similar to the `pendingMonthSelection` state in the dead
  `BodyChartsView`) and either (a) hold the previous month's content
  until the load finishes, or (b) render a "Loading [Month]" banner above
  the list while the task is in flight. Option (b) matches the existing
  loading banner shape and keeps the calendar/empty-state UX out of the
  picture during loads.
- **Risks / dependencies:** Touches view state only. Does not affect the
  store's `loadMonthIfNeeded` semantics. Verify with
  `WorkoutMonthSnapshotTests` — no test pins the current empty-flow
  behavior.

### N3. `BodyChartsView`, `BodyChartsLoadingBanner`, and `BodyChartsScrollTransitionShade` are dead code in `BodyChartsView.swift`

- **Severity:** Low
- **Related files:** `Body/Views/BodyChartsView.swift:8-126,128-142,144-164`,
  `Body/Views/MainTabView.swift`
- **Description:** `MainTabView` defines three tabs (Summary, Workouts,
  Settings) — no Charts tab. The `BodyChartsView` struct, the
  `BodyChartsScrollTransitionShade` overlay, and the
  `BodyChartsLoadingBanner` row inside it are referenced only by the
  file's `#Preview` and by each other. The same file still hosts
  `BodyWorkoutListSelection`, `BodyWorkoutListSheet`, and
  `BodyWorkoutRecordRow` (lines 166-407), which `BodyWorkoutsView` uses
  for tap-through sheets. Grep:
  ```
  rg "BodyChartsView\b|BodyChartsLoadingBanner|BodyChartsScrollTransitionShade" Body BodyShared BodyTests
  ```
  finds only the self-references and one previously-noted
  `requestMonthYearSelection` parallel in `BodyWorkoutsView`.
- **Why it matters:** Future contributors look at `BodyChartsView.swift`
  and reasonably assume it's the active Charts tab. The dead view also
  duplicates pending-month state machinery (`pendingMonthSelection`,
  loading banner) that `BodyWorkoutsView` is missing (see N2).
- **Suggested fix:** Either (a) delete `BodyChartsView` /
  `BodyChartsScrollTransitionShade` / `BodyChartsLoadingBanner` and
  rename the file to `BodyWorkoutListSheet.swift` (or move the surviving
  types alongside `BodyWorkoutsView.swift`), or (b) reuse
  `BodyChartsLoadingBanner` from the same file to fix N2. Option (b)
  makes the dead code worth keeping until N2 lands.
- **Risks / dependencies:** None. `BodyWorkoutListSelection` /
  `BodyWorkoutListSheet` / `BodyWorkoutRecordRow` must remain for
  `BodyWorkoutsView`'s tap-through sheets.

### N4. `BodyHealthMetricCard.Model.accessoryMetrics` and its render branch are unreachable

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift:5160-5167,5175,5187,5198,5224-5228,5247-5259,5314-5333`
- **Description:** `BodyHealthMetricCard.Model` declares an
  `accessoryMetrics: [AccessoryMetric]` property with a default of `[]`.
  Every construction site (`Body/Views/BodyHomeView.swift:447, 467, 490,
  524`) omits the argument. `cardContent` branches:
  ```swift
  if !metric.prominentMetrics.isEmpty {
      prominentContent
  } else if metric.accessoryMetrics.isEmpty {
      regularContent
  } else {
      accessoryContent
  }
  ```
  The else branch (`accessoryContent`) is unreachable because no caller
  ever populates `accessoryMetrics`. The nested `AccessoryMetric` struct,
  the `accessoryContent` view, and `accessoryMetricStrip` (lines
  5314-5333) are all dead.
- **Why it matters:** Hidden API surface. A future contributor reading the
  card model would assume Body has a third card layout that just isn't
  used today. Removing the dead branch makes the card's two real states
  (regular vs. prominent) visible.
- **Suggested fix:** Delete the `AccessoryMetric` struct, the
  `accessoryMetrics` property and its init parameter, the
  `accessoryContent` view, and `accessoryMetricStrip`. Replace the
  three-way `cardContent` branch with `metric.prominentMetrics.isEmpty ?
  regularContent : prominentContent`.
- **Risks / dependencies:** None — no test references
  `accessoryMetrics`.

### N5. `sleepDateTile(for:)` and `metricDateTile(for:)` are near-identical 95-line duplicates

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift:2051-2098,2100-2147`
- **Description:** Both functions construct an identical day-tile button
  with the same fonts, frames, colors, shadow, accessibility, and disabled
  behavior. They differ only in which date the tile updates
  (`selectedSleepDate` vs. `selectedMetricDate`) and which derived day
  the selection comparison reads (`selectedSleepDay` vs.
  `selectedMetricDay`). The companion picker computed properties
  `sleepDatePickerDates` and `metricDatePickerDates`
  (`Body/Views/BodyHomeView.swift:1535-1541`) are also duplicates of
  each other and call `SleepHistorySnapshot.datePickerDates(...)` with
  the same arguments. The `sleepDatePicker` / `metricDatePicker`
  scroll containers (lines 1953-2021) repeat the same shape.
- **Why it matters:** Five SwiftUI helpers exist where one would do.
  Future styling tweaks must be applied twice; the basics range card
  and BMI trend card already follow that same pair shape, so the cost
  scales with each new "tappable detail day picker".
- **Suggested fix:** Extract `dateTile(for:isSelected:onSelect:)` as a
  single function that takes a `Binding<Date?>` (or a `(Date) -> Void`
  closure) plus the comparison day; collapse the date-picker computed
  property into one `recentDatePickerDates`. Or move the date-picker
  scaffold into its own `private struct BodyDayPicker` that the sleep
  and metric detail panels each instantiate.
- **Risks / dependencies:** Touches `BodyHealthMetricDetailView` only.
  No existing test pins the duplicated structure.

### N6. `Calendar.current` in the sleep-stage chart and the widget timeline diverge from `Calendar.bodyGregorian` used everywhere else

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift:4199`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift:65`
- **Description:** The sleep-stage detail chart's `axisValues(strideHours:minimumCount:)`
  helper builds its hourly axis ticks from `Calendar.current` (line
  4199), while every other date-math site in the project goes through
  `Calendar.bodyGregorian`. The widget timeline at line 65 of
  `WorkoutCalendarWidget.swift` computes the next refresh window with
  `Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)`.
- **Why it matters:** For users on a non-gregorian default calendar
  (or for the rare case of a calendar override) the sleep stage axis
  labels may shift relative to `chartXDomain`, which is built from the
  HealthKit segment dates in the user's wall-clock timezone. The widget
  timeline is even less risky (it's just an interval) but inconsistent.
  Same class of issue as archive N11.
- **Suggested fix:** Replace both with `Calendar.bodyGregorian`. For the
  widget case, since the goal is "30 minutes from now", an explicit
  `.bodyGregorian` is no worse and makes the convention consistent.
- **Risks / dependencies:** None. No tests rely on the current behavior.

### N7. `NSHealthShareUsageDescription` understates the read scopes Body actually requests

- **Severity:** Low
- **Related files:** `body.xcodeproj/project.pbxproj:468,506`,
  `Body/Services/HealthKitWorkoutStore.swift:571-636`
- **Description:** The Info.plist usage description reads "Body reads
  workout, sleep, heart, and body measurement data from Apple Health to
  build your health dashboard, charts, and widgets." But
  `HealthKitWorkoutStore.readObjectTypes(for:)` requests:
  workouts, activitySummaryType, workoutEffortScore, restingHeartRate,
  heartRate, heartRateVariabilitySDNN, bodyMass, bodyFatPercentage,
  bodyMassIndex, respiratoryRate, oxygenSaturation, activeEnergyBurned,
  basalEnergyBurned, appleExerciseTime, appleSleepingWristTemperature,
  timeInDaylight, stepCount, and sleepAnalysis. The user-visible
  permission prompt does not mention exercise minutes, daylight, steps,
  wrist temperature, blood oxygen, respiratory rate, energy, or activity
  rings.
- **Why it matters:** The system permission sheet (the only chance the
  user has to see this string) lists permissions Apple shows from the
  request — a category the user can't predict from the description.
  Apple does not require an exact match, but stricter App Store reviews
  flag this if it materially understates scope. Users denying a category
  Body actually requests is also more likely when the description omits
  it.
- **Suggested fix:** Broaden the description to enumerate the actual
  categories — e.g. "Body reads workouts, Activity Rings, sleep, heart
  rate, HRV, blood oxygen, respiratory rate, body measurements, energy,
  exercise minutes, wrist temperature, daylight, and steps from Apple
  Health to power your dashboard, charts, and widgets."
- **Risks / dependencies:** None. Description is build-time text in the
  pbxproj `INFOPLIST_KEY_NSHealthShareUsageDescription`.

### N8. `TestPlan.md` is pinned to branch `codex/body-v0.3.0` and omits `BodyProView` from its reviewed-files list

- **Severity:** Low
- **Related files:** `TestPlan.md:3,9-15`
- **Description:** `TestPlan.md:3` reads "Generated 2026-05-13 against
  branch `codex/body-v0.3.0`" — the current branch is
  `codex/body-v0.3.3`. The "What Was Reviewed" section lists app entry,
  HealthKit, shared models, widgets, and configuration — but not
  `Body/Views/BodyProView.swift`, which was added in commits `9f639d8`
  and `3ba63bc` and is the destination of the Settings > Body Pro
  navigation. The automated tables include `A20 Metric About coverage`
  but no Body Pro coverage; the manual tables likewise omit any
  Body Pro / creator-surprise icon case.
- **Why it matters:** TestPlan is presented as authoritative scope.
  Drift hides untested surfaces (Body Pro's flippable icon, the
  five-tap version unlock for creator surprises, the lifetime / restore
  buttons that today only set status text) from the audit trail.
- **Suggested fix:** Bump the branch reference, add `BodyProView.swift`
  to "What Was Reviewed", and add manual cases for: Body Pro entry
  navigation, the flippable icon toggling `bodyProIconShowsBackKey`,
  the five-tap version-card unlock, and the creator-surprise icon
  sheet. Bundle this with N1 so docs ship together.
- **Risks / dependencies:** Pair with N1.

### N9. Settings `appVersionDisplay` formats the build with a hardcoded fallback that diverges from the test-asserted project version

- **Severity:** Low
- **Related files:** `Body/Views/BodySettingsView.swift:237-241`,
  `BodyTests/ProjectConfigurationTests.swift:200-201`
- **Description:** Already partly covered by N1, but worth flagging
  separately: when Info.plist values are missing, the Settings card
  displays "0.3.3 (1)", while the project's actual build number is 2
  (`ProjectConfigurationTests` pins it at 2). The fallback never runs
  when Info.plist is intact, but it codifies the wrong number.
- **Why it matters:** Defensive fallback that's already wrong. If the
  Info.plist generation ever regresses, the user-visible Settings
  Version row will silently lie about the build.
- **Suggested fix:** Replace the fallback strings with "Unknown" (which
  is what `supportEmailBody` at line 1457-1458 already does), or update
  them in lockstep with `CURRENT_PROJECT_VERSION`.
- **Risks / dependencies:** None.

---

## 3. Code quality findings

- **Duplicated code:**
  - `Body/Views/BodyHomeView.swift:2051-2098` and `:2100-2147` —
    `sleepDateTile` and `metricDateTile` are 95-line near-duplicates
    (see N5).
  - `Body/Views/BodyHomeView.swift:1535-1541` —
    `sleepDatePickerDates` and `metricDatePickerDates` are identical
    one-liners.
  - `Body/Views/BodyHomeView.swift:1953-2021` —
    `sleepDatePicker` and `metricDatePicker` use the same
    `ScrollViewReader` shape and `.task(id:)` body.
  - Calendar weekday-symbol rotation already lives at
    `BodyShared/Models/WorkoutMonthSnapshot.swift:206-220`; the
    Activity Rings detail still inlines a `weekdayHeader` /
    `weekdaySymbols` pair (`Body/Views/BodyHomeView.swift:4684-4701`)
    rather than calling the shared helper. The duplication is small
    (~15 lines) and harmless today; lift the helper if it grows again.
- **Unused or outdated files / symbols:**
  - `Body/Views/BodyChartsView.swift:8-126,128-142,144-164` — dead
    `BodyChartsView`, `BodyChartsScrollTransitionShade`,
    `BodyChartsLoadingBanner` (see N3). Verified with
    `rg "BodyChartsView\b" Body BodyShared BodyTests`.
  - `Body/Views/BodyHomeView.swift:5160-5167,5247-5259,5314-5333` —
    dead `AccessoryMetric`, `accessoryContent`, `accessoryMetricStrip`
    (see N4). Verified with `rg "accessoryMetrics: \[" Body BodyShared`.
  - Archive `docs/IssuesArchive-02.md` claimed
    `HealthKitWorkoutStore.dailyQuantitySummary` was removed in N8.
    The function is back at
    `Body/Services/HealthKitWorkoutStore.swift:1221-1241` and is now
    used by wrist-temperature aggregation
    (`Body/Services/HealthKitWorkoutStore.swift:815-820`) — it is no
    longer dead, so N8 in archive 02 is stale, not regressed.
- **Overly complex files or functions:**
  - `Body/Views/BodyHomeView.swift` is now 5,585 lines and still
    bundles the Home grid, the entire detail-view machinery, every
    sleep-supplement card, Activity Rings, basics dual-axis chart,
    line/bar previews, and the card backgrounds extension. Splitting
    `BodyActivityRingsDetailView` (and its ring graphic stack) into
    its own file would drop ~900 lines; splitting
    `BodyHealthMetricDetailView` plus all its sleep panels another
    ~1,300. Same observation as archive 02; the file kept growing.
- **Naming inconsistencies:**
  - `Body/Views/BodyChartsView.swift` is misnamed — the file's only
    living types are workout-list helpers used by `BodyWorkoutsView`.
- **Structural improvements:**
  - Repeat the archive-02 suggestion: lift the metric-detail day
    picker into a reusable `BodyMetricDayPicker(selectedDate:dates:)`
    component, replacing the sleep/metric duplicate pair.
  - `BodyChartsView`'s pending-month state machine
    (`pendingMonthSelection` + banner) is almost the right scaffolding
    for the N2 fix in `BodyWorkoutsView`; consider lifting it out as a
    standalone helper instead of deleting it.

---

## 4. Functional issues

- **Month switch in Workouts shows the empty state during a HealthKit
  load (N2):** `BodyWorkoutsView` immediately swaps to the new month;
  for an unloaded month the user sees "No workouts for [month]" or
  "Try selecting more workout types" with no hint that a query is in
  flight. The calendar card on top of the workouts list also renders
  empty during the load.
- **`BodyChartsView` is wired only to a `#Preview`:** the dead view
  itself isn't a user-visible bug, but its dead pending-month banner
  (`BodyChartsLoadingBanner`) is exactly what Workouts is missing for
  N2.
- **Sleep-stage axis builds with `Calendar.current` (N6):** axis tick
  positions can diverge by an hour at boundary timezones / non-gregorian
  default calendars; downstream display of `chartXDomain` is unaffected.

---

## 5. UI/UX issues

- **No loading state in Workouts month switch (N2)** — empty state is
  the most user-facing UX gap in this audit.
- **`NSHealthShareUsageDescription` understates scope (N7)** — the
  system permission prompt user-visible text omits exercise minutes,
  daylight, steps, wrist temperature, blood oxygen, respiratory rate,
  energy, and Activity Rings.
- **Sleep / metric date picker pairs duplicate styling (N5)** — small
  divergences are easy to introduce because the two surfaces share no
  helper.
- **Body Pro lifetime / restore buttons set a status string instead of
  showing a non-functional indicator** (`Body/Views/BodyProView.swift:47-49,88-101`)
  — the page is intentionally a placeholder for future IAP wiring, but
  the only feedback today is a small footnote-sized "not available in
  this build" line under both buttons. A reader doesn't know whether
  the buttons are intended to work; consider disabling them and
  pointing at a clearer "Coming Soon" affordance, or hiding them until
  the IAP path is real. Needs verification on device — visual only.
- **Workout Calendar Widget configuration display name "Workout
  Calendar" vs. "Workout Types" — both widgets use the same
  configuration intent (`BodyWidgetConfigurationIntent`), which has a
  single `background` parameter (`BodyWidgetExtension/WorkoutCalendarWidget.swift:24-36`).
  No issue.

---

## 6. Data and persistence issues

- **Snapshot codec resilience (carry-forward from archive 02):**
  `WorkoutSnapshotStore.load(fileURL:)` and
  `HealthDashboardSnapshotStore.load(defaults:)` now log on decode
  failures via `os.Logger`. `HealthDashboardSnapshot.init(from:)` uses
  `decodeIfPresent` for the optional `activityRingHistory` and
  per-trend `decodeIfPresent` calls for added trends. Forward-compatible.
- **No schema version field:** `WorkoutMonthSnapshot` and
  `HealthDashboardSnapshot` still don't carry an explicit schema
  version. A `BodyWorkoutType` raw-value rename would fail the entire
  decode (additions are tolerated by the mapping fallback to `.other`,
  but enum-removal would break the decode). Same observation as archive
  02 — low priority until a workout-type case is removed.
- **App group / file path round-trip:** `WorkoutSnapshotStore` writes
  the current month snapshot to the app-group container; the widget
  reads from the same path. Verified by `testAppAndWidgetShareAppGroupEntitlement`.
- **`HealthDashboardSnapshotStore` UserDefaults round-trip:** Now
  covered by `HealthKitWorkoutStoreTests.testHealthDashboardSnapshotStoreRoundTripsCachedHomeData`
  and `testHealthDashboardSnapshotStoreLoadsOlderCacheWithoutActivityRingHistory`.
- **No new data loss paths surfaced in this run.**

---

## 7. Configuration and platform issues

- **Version drift (N1):** Project at `MARKETING_VERSION = 0.3.3` /
  `CURRENT_PROJECT_VERSION = 2`. README and VersionHistory still report
  build 1. Settings fallback hardcodes "0.3.3" / "1".
- **`NSHealthShareUsageDescription` description text is too narrow (N7).**
- **App group identifier** `group.com.zihengthedeveloper.Body` parities
  app + widget entitlements; asserted by
  `testAppAndWidgetShareAppGroupEntitlement`.
- **HealthKit entitlement** present at `Body/Body.entitlements:5-6`;
  asserted by `testAppDeclaresHealthKitEntitlement`.
- **Privacy manifests** for both targets declare
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` and
  `NSPrivacyTracking = false`; asserted by
  `testPrivacyManifestsDeclareUserDefaultsAndNoTracking`.
- **Deployment target** `IPHONEOS_DEPLOYMENT_TARGET = 18.0` across all
  six configurations.
- **Alternate app icons** match `BodyAppIconOption.standard +
  creatorSurprises` and the `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
  list; asserted by `testAppIconAssetsIncludePrimaryAndAlternateOptions`
  and `testSettingsVersionTapUnlocksCreatorSurpriseIcons`.
- **No `NSHealthUpdateUsageDescription`** — correct, since the app never
  writes HealthKit samples.

---

## 8. Testing gaps

- **Highest-risk uncovered features:**
  - `BodyWorkoutsView` pending-month UX (N2) — no test covers the
    loading-state path; today the empty state is the load state.
  - `BodyHealthMetricDetailView` sleep vs. metric date-picker pair (N5)
    — visual test or focused snapshot test could pin the parity
    between the two surfaces.
  - `BodyProView` flippable icon, version-tap unlock, and the
    "not available in this build" buttons — no behavioral tests beyond
    the `ProjectConfigurationTests` source-grep checks.
  - `Calendar.bodyGregorian` vs. `Calendar.current` (N6) — no test
    pins the sleep-stage axis calendar.
- **Suggested tests:**
  - Add a `BodyWorkoutsView`/store integration test that exercises
    `requestMonthYearSelection` against an unloaded month, asserts an
    expected pending-state flag, and confirms the empty state is gated
    on `!isLoading`.
  - Add a unit test pinning the sleep-stage axis values against
    `Calendar.bodyGregorian` after N6 lands.
  - Manual / on-device cases not in `TestPlan.md` (N8):
    - Body Pro entry navigation, icon flip, version-tap unlock.
    - Workouts tab pending-month load (N2).
    - HealthKit permission prompt copy (N7) — verify the description
      reads correctly on first launch.
    - Widget timeline behavior across midnight and DST boundaries
      (N6, follow-up).

---

## 9. Priority recommendations

- **Fix first:**
  - N1 — version drift across project / docs / Settings fallback; this
    is the only item that blocks a clean v0.3.3 ship and the next
    archive run.
  - N2 — Workouts tab "No workouts" empty state during pending month
    loads is the most user-visible UX bug in this run.
- **Fix next:**
  - N3 — delete (or repurpose for N2) the dead `BodyChartsView` and
    its loading banner.
  - N7 — broaden the HealthKit usage description so the system prompt
    matches the actual read scopes.
  - N8 — refresh `TestPlan.md` for the branch and add `BodyProView`
    coverage.
- **Optional cleanup:**
  - N4 — remove unused `accessoryMetrics` branch in
    `BodyHealthMetricCard.Model`.
  - N5 — collapse `sleepDateTile` / `metricDateTile` and their
    picker scaffolds into a shared helper.
  - N6 — switch the sleep-stage axis and widget timeline to
    `Calendar.bodyGregorian`.
  - N9 — change the Settings version fallback strings to "Unknown" or
    bump them in lockstep with N1.

---

## What was checked

- App entry: `Body/BodyApp.swift`, `Body/Views/MainTabView.swift`.
- App models: `Body/Models/BodyAppearancePreference.swift`,
  `Body/Models/HealthSummarySnapshot.swift` (full).
- App services: `Body/Services/HealthKitWorkoutStore.swift` (full).
- App views: `Body/Views/BodyHomeView.swift` (selective: detail-view
  routing, basics chart, sleep date picker pair, activity rings detail,
  card model, card background; full file scanned via `rg`),
  `Body/Views/BodyWorkoutsView.swift` (full),
  `Body/Views/BodyChartsView.swift` (full),
  `Body/Views/BodyMonthYearPicker.swift` (full),
  `Body/Views/BodySettingsView.swift` (full),
  `Body/Views/BodyProView.swift` (full).
- Shared models: `BodyShared/Models/BodyWorkoutType.swift`,
  `BodyShared/Models/WorkoutMonthSnapshot.swift`,
  `BodyShared/Models/WorkoutSummary.swift`.
- Shared components: `BodyShared/Components/WorkoutCalendarView.swift`,
  `BodyShared/Components/WorkoutTypeBreakdownView.swift`.
- Shared services: `BodyShared/Services/WorkoutSnapshotStore.swift`.
- Widgets: `BodyWidgetExtension/BodyWidgetExtensionBundle.swift`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift`,
  `BodyWidgetExtension/Info.plist`.
- Tests: `BodyTests/WorkoutMonthSnapshotTests.swift` (top 250 lines +
  function index; 94 test functions),
  `BodyTests/HealthKitWorkoutStoreTests.swift`,
  `BodyTests/BodyWorkoutTypeTests.swift`,
  `BodyTests/ProjectConfigurationTests.swift`.
- Configuration: `Body/Body.entitlements`,
  `BodyWidgetExtension.entitlements`,
  `body.xcodeproj/project.pbxproj` (build settings, version pins,
  alternate icon list, HealthKit usage description, deployment target,
  target families).
- Docs: `README.md`, `VersionHistory.md`, `TestPlan.md`,
  `LessonsLearned.md`, `AGENTS.md` (skim).
- Archive cross-reference: `docs/IssuesArchive-02.md` and (skim)
  `docs/IssuesArchive-01.md`. Archive 02 N1-N18 confirmed against
  current code; N8's "removed `dailyQuantitySummary`" claim is now
  stale because the method is reused by wrist-temperature aggregation.
- Grep queries:
  - `rg "TODO|FIXME|XXX|HACK" Body BodyShared BodyWidgetExtension BodyTests` — no source matches.
  - `rg "model.title ==" Body/Views` — no matches (archive N2 stayed fixed).
  - `rg "model.kind ==" Body/Views/BodyHomeView.swift` — 4 hits, all
    on the new `HealthMetricKind` branching path.
  - `rg "Calendar.current" Body BodyShared BodyWidgetExtension` —
    surfaces the two N6 callers.
  - `rg "try?" Body BodyShared BodyWidgetExtension` — only `Task.sleep`
    callers remain; no silent JSON paths.
  - `rg "BodyChartsView\b" Body BodyShared BodyTests` — confirmed dead.
  - `rg "accessoryMetrics" Body/Views/BodyHomeView.swift` — confirmed
    no non-default caller.
  - `rg "dailyQuantitySummary|isLoadingSnapshot|recentActivityRingMonthKeys"
    Body/Services/HealthKitWorkoutStore.swift` — confirmed
    `dailyQuantitySummary` and `recentActivityRingMonthKeys` are used;
    `isLoadingSnapshot` is removed.
  - `rg "DispatchQueue\.main" Body BodyShared BodyWidgetExtension` —
    surfaces the icon-flip / icon-change / haptic GCD hops in
    `BodyProView` and `BodySettingsView`; archive N16's GCD-in-rings
    case is fixed (`Task { @MainActor in ... await Task.yield() }` at
    `BodyHomeView.swift:4603-4606`).

## Not checked (worth a follow-up)

- Running the project on simulator or device. Verifying N2's empty-state
  flow during a real HealthKit query, N7's permission prompt copy on
  first launch, and any of the visual checks in §5 requires a build.
- Lock Screen / accessory widget families (deferred per
  `TestPlan.md` §4).
- Localization beyond English (deferred per `TestPlan.md` §4).
- LaunchScreen XML and the workspace shared scheme XML.
- HealthKit background delivery (deferred per `TestPlan.md` §4).
- Asset catalog `Contents.json` JSON validation beyond
  `ProjectConfigurationTests.testAppIconAssetsIncludePrimaryAndAlternateOptions`
  (which confirms file existence and non-zero PNG bytes only).
- `WorkoutMonthSnapshotTests.swift` (2,137 lines, 94 tests) was
  function-indexed but not read in full; spot checks against the
  recent commits suggest range-cap and aggregation coverage is in
  place.
- Carry-forward verification: archive 02's "Fix pass resolution" was
  cross-referenced via grep, not by re-deriving each fix's behavior
  on device.
