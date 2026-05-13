# Body — Issues Report

Audit of branch `codex/body-v0.2.6` on 2026-05-12. The original review was
read-only; a follow-up fix pass on 2026-05-12 addressed all numbered findings
N1-N18. See "Fix pass resolution" at the end of this report for the code,
documentation, and verification notes.

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

Body has grown substantially since v0.1.0: a new Workouts tab with sort /
filter / search, a Health dashboard with cached snapshots, daily energy
charts, a sleep score / stage timeline / vitals region chart, and an
Activity Rings detail with paginated history. The shape is solid; the prior
audit's 16 findings are all addressed in code. The most user-affecting risks
in this run cluster around three areas: (1) the post-v0.1.0
`HealthDashboardSnapshotStore` regressed the `try?` silent-error pattern
that was fixed in `WorkoutSnapshotStore`; (2) the metric detail screen
branches on user-facing title strings (`model.title == "Sleep"` /
`"Basics"`) which is a maintenance trap; (3) the project's
`MARKETING_VERSION`, README, and VersionHistory have drifted from the
branch name and from each other. There are several smaller hygiene items
(dead methods, calendar inconsistencies, a non-obvious filter toggle, and a
widget empty-state icon that disappears on the White background). Areas
reviewed: app entry / scene phase, HealthKit ingestion / authorization /
trend fetch, workout summary aggregation, snapshot persistence (both file
and UserDefaults), Home dashboard cards, Workouts tab, Charts tab, Activity
Rings detail, settings, month / year picker, widgets, entitlements,
Info.plist keys, privacy manifests, project build settings, and unit
tests. Intentionally not reviewed: rendered runtime behavior on device (no
build in this run), asset catalog binary contents (PNG sizes only),
LaunchScreen XML, and Xcode shared scheme files.

---

## 2. Issue list

### N1. `HealthDashboardSnapshotStore.save` and `load` silently swallow JSON encode / decode failures

- **Severity:** Medium
- **Related files:** `Body/Models/HealthSummarySnapshot.swift:766-787`
- **Description:** `HealthDashboardSnapshotStore.save(_:defaults:)` uses
  `guard let data = try? JSONEncoder().encode(snapshot) else { return }`,
  and `load(defaults:)` uses `try? JSONDecoder().decode(...)`. There is no
  logger and no diagnostic on failure. This is the same pattern that the
  prior audit flagged on `WorkoutSnapshotStore` (archive item N12) and that
  was fixed there with `os.Logger`. The newer `HealthDashboardSnapshotStore`
  added in v0.2.x reintroduces the silent path for the Home health cache.
- **Why it matters:** This is the storage that round-trips the entire
  HealthSummarySnapshot / HealthTrendSnapshot / ActivityRingHistorySnapshot.
  An encode regression (e.g. someone adds a non-Codable property) would
  show up only as "Home cards stop persisting across launches" with no
  log trail. The cache is the difference between an instant Home and a
  blank Home until HealthKit re-fetches.
- **Suggested fix:** Mirror `WorkoutSnapshotStore`'s shape — declare a
  `private static let logger = Logger(subsystem: ..., category:
  "HealthDashboardSnapshotStore")`, replace `try?` with `do/catch` and
  `logger.error("...")` on both encode and decode failures.
- **Risks / dependencies:** None. Pure observability.

### N2. Metric detail view branches on user-visible title strings (`model.title == "Sleep"` / `"Basics"`)

- **Severity:** Medium
- **Related files:** `Body/Views/BodyHomeView.swift:591`,
  `Body/Views/BodyHomeView.swift:693`,
  `Body/Views/BodyHomeView.swift:1072`,
  `Body/Views/BodyHomeView.swift:1101-1107`
- **Description:** `BodyHealthMetricDetailView` exposes Sleep score / stages
  / vitals cards and Basics legend / dual-axis chart via three string
  comparisons:
  - `isSleepDetail = model.title == "Sleep"` (gates supplement cards,
    order of trend vs. supplements, and `chartSelectionText`).
  - `model.title == "Basics"` (gates `BodyBasicsTrendLegend` in the trend
    card header).
  - `model.title == "Sleep"` (gates `averageSleepText`).
  The model has no `kind` or `style` field; the only branching key is the
  display title.
- **Why it matters:** A localized title (TestPlan defers localization, but
  it is a planned direction) or a UX rename like Sleep → "Sleep Score" or
  Basics → "Body Basics" silently disables sleep stages, sleep vitals,
  basics legend, and the dual-axis chart. The detail view becomes a plain
  trend chart with no warning at build or runtime.
- **Suggested fix:** Add a stable identifier to `BodyHealthMetricDetailModel`
  — either pass through the `HealthMetricKind` from `detailModel(for:)`
  (it already exists there) and branch on `kind == .sleep` / `kind ==
  .basics`, or add a small enum like `enum BodyHealthMetricDetailStyle {
  case sleep, basics, standard }` populated at construction.
- **Risks / dependencies:** Touches the private `BodyHealthMetricDetailModel`
  type and all of its construction sites in `detailModel(for:)`. Watch the
  tests in `WorkoutMonthSnapshotTests.testHealthMetricDetailHelpOnlyTargetsRequestedCards`
  for any interaction (none expected — that test only reads `detailHelpText`).

### N3. `MARKETING_VERSION` / README / VersionHistory have drifted

- **Severity:** Medium
- **Related files:** `body.xcodeproj/project.pbxproj:479,517,550,580,605,630`,
  `README.md:7`, `VersionHistory.md:3-7`,
  `BodyTests/ProjectConfigurationTests.swift:59-60`
- **Description:** The branch is `codex/body-v0.2.6`. The pbxproj pins all
  six configurations to `MARKETING_VERSION = 0.2.3` and
  `CURRENT_PROJECT_VERSION = 3`. README.md line 7 says "Current app version:
  **0.2.3 (build 1)**" — both the marketing version and the *build number*
  disagree with the project. VersionHistory.md's most recent entry is
  "0.2.3 (build 1)", with no 0.2.4 / 0.2.5 / 0.2.6 entries even though
  `git log` shows merged work on "Body v0.2.5 activity updates" and the
  current branch claims v0.2.6.
- **Why it matters:** Three sources of truth — the branch name, the build
  settings, and the docs — disagree. The `ProjectConfigurationTests.testProjectBuildSettingsMatchInitialReleasePlan`
  test pins `MARKETING_VERSION = 0.2.3` and `CURRENT_PROJECT_VERSION = 3`,
  so the version-bump update has to happen across pbxproj, the
  configuration test, README, VersionHistory, and (probably) the in-app
  Settings hardcoded fallback in one change.
- **Suggested fix:** Decide the intended version for this branch and update
  all five places at once. Either bump to 0.2.6 (and add VersionHistory
  entries for 0.2.5 and 0.2.6) or rename the branch to match 0.2.3.
- **Risks / dependencies:** `ProjectConfigurationTests` is the
  build-time canary per the 2026-05-12 lessons learned; updating
  `CURRENT_PROJECT_VERSION` without the test update fails the suite.

### N4. Tapping an empty calendar day opens a sheet with confusing "0 workouts · 0m" summary header

- **Severity:** Medium
- **Related files:** `Body/Views/BodyChartsView.swift:40-51`,
  `Body/Views/BodyChartsView.swift:282-329`,
  `BodyShared/Components/WorkoutCalendarView.swift:70-82`
- **Description:** `WorkoutCalendarView` fires `onSelectDay?(day)` from the
  cell tap gesture for *every* day, including days with `workoutCount == 0`
  (the empty days that show only a number). The Charts tab's
  `selectedWorkouts = .day(day)` is then handed to `BodyWorkoutListSheet`,
  which renders a `summaryCard` showing `selection.title` (the formatted
  date), `selection.subtitle` (which is `BodyValueFormat.workoutCountText(0)`
  → "0 workouts"), `selection.totalDuration` formatted ("0m"), and
  `selection.totalEnergyKilocalories` formatted ("0 kcal"). Beneath that
  the empty state reads "No workouts for this selection." So the sheet
  shows both a "0 workouts · 0m" header card *and* an empty-state message.
- **Why it matters:** Users will discover that any tap on a blank day
  opens an empty sheet — the calendar reads more like a button than a
  date label. Either suppress the tap on empty days or collapse the
  summary card when there are no workouts.
- **Suggested fix:** Either (a) in `WorkoutCalendarView.calendarCellContent`
  guard the tap with `if day.workoutCount > 0 { onSelectDay?(day) }`, or
  (b) in `BodyWorkoutListSheet.summaryCard` short-circuit on
  `selection.workouts.isEmpty` and show only the empty state. Option (a)
  is the cleaner default — there is no useful sheet content for an empty
  day.
- **Risks / dependencies:** None. The widget calendar uses the same
  component but does not pass an `onSelectDay`, so widget behavior is
  unchanged.

### N5. Workout filter `toggleWorkoutType` is non-obvious — tapping when one type is selected re-selects ALL types

- **Severity:** Medium
- **Related files:** `Body/Views/BodyWorkoutsView.swift:1143-1153`
- **Description:** `toggleWorkoutType(_:)` has three branches:
  - If `tempSelectedWorkoutTypes` is a superset of all available types,
    tapping any type narrows to `[workoutType]` (replace, not toggle).
  - If `tempSelectedWorkoutTypes == [workoutType]` (i.e. one type
    selected, and it's the tapped one), the function calls `formUnion(all)`
    — tapping the single selected type *expands* selection to all.
  - Otherwise it toggles normally.
  The two non-toggle branches are surprising and undocumented.
- **Why it matters:** A user with one type filtered who taps that type to
  deselect it accidentally enables all types. A user who starts with all
  types and taps one to "filter to that one" finds the tap *narrows*
  rather than *toggles* — which is also surprising the other way.
  Standard iOS filter UIs toggle one type per tap and use a Select All /
  Deselect All button for the bulk operations (which this view already
  provides).
- **Suggested fix:** Replace the body of `toggleWorkoutType` with the
  plain toggle: `if contains, remove; else insert`. Rely on the Select
  All / Deselect All buttons for bulk changes.
- **Risks / dependencies:** Pure behavior change in the sheet. No tests
  pin the current behavior. Verify on the simulator with multiple types
  in a month.

### N6. `hasActiveFilters` is computed against month-local types, hiding active filters when no filtered types exist in the month

- **Severity:** Low
- **Related files:** `Body/Views/BodyWorkoutsView.swift:127-138,158-165,267-310`
- **Description:** `availableWorkoutTypes` is the set of types actually
  present in the selected month. `hasActiveFilters` returns
  `!availableTypes.isSubset(of: selectedTypes)` — meaning the answer is
  `true` only when the current month has types that the user has
  unchecked. When the user filters to `[running]` and switches to a month
  with no running workouts, `availableWorkoutTypes == []`, so
  `hasActiveFilters` returns `false`, the "Try selecting more workout
  types in the filter" hint is suppressed, and the empty state reads "No
  workouts for May 2026" — without revealing that a filter is dropping
  results.
- **Why it matters:** A real user-flow scenario: filter to Running, scroll
  to a month with zero running workouts, see "No workouts" with no hint
  that the filter caused it. The Reset Filters button disappears with
  the hint.
- **Suggested fix:** Compute `hasActiveFilters` against
  `BodyWorkoutType.allCases` (the universal set of types the user could
  have unchecked) rather than the month-local set. Today the only branch
  reading the result is the empty state — flagging it true even when the
  current month has no matching types is the correct signal.
- **Risks / dependencies:** None.

### N7. `WorkoutTypeBreakdownView` empty-state icon uses `Color.white.opacity(0.45)` — invisible on the widget's White background

- **Severity:** Low
- **Related files:** `BodyShared/Components/WorkoutTypeBreakdownView.swift:52-63`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift:142-157`
- **Description:** When the Workout Types widget has no data, the view
  renders a centered `figure.mixed.cardio` glyph with
  `.foregroundStyle(Color.white.opacity(0.45))`. The widget supports a
  user-selectable `BodyWidgetBackgroundSelection.white` background, which
  `containerBackground(Color.white, for: .widget)` paints white. The
  white-on-white glyph at 45% opacity is effectively invisible — only the
  "No workouts yet" text below (which uses `.secondary`, resolved in light
  scheme via `.environment(\.colorScheme, .light)`) remains legible.
- **Why it matters:** Visible regression for users who pick the White
  widget background and have an empty month (or a freshly installed
  build before HealthKit sync).
- **Suggested fix:** Replace `Color.white.opacity(0.45)` with
  `Color.secondary.opacity(0.45)` so the glyph follows the resolved
  colorScheme that the widget already forces.
- **Risks / dependencies:** Confirm the in-app `style: .app` empty state
  doesn't regress against a light background (it uses the same enum
  branch, so the change applies there too — but the in-app card uses
  `Color.secondary` for the text already, so a matching icon color
  reads better).

### N8. `HealthKitWorkoutStore.dailyQuantitySummary` is dead code

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:868-888`
- **Description:** The private helper builds a daily series via
  `fetchDailyQuantitySeries` and returns the latest point as a
  `HealthMetricSummary`. Grep across `Body/`, `BodyShared/`,
  `BodyWidgetExtension/`, `BodyTests/` finds zero callers. The Home
  summary uses `latestQuantity` (single sample) for non-energy metrics
  and `dailyCumulativeQuantitySummary` for energy; the daily-series-then-latest
  shape is unused.
- **Why it matters:** Future contributors will reasonably assume the
  function is wired somewhere and reach for it before realizing it has
  no consumers. Removing it keeps the file aligned with its actual
  responsibilities.
- **Suggested fix:** Delete `dailyQuantitySummary(for:unit:aggregation:calendar:valueTransform:)`.
  Confirm with `rg dailyQuantitySummary` that no callers remain.
- **Risks / dependencies:** None.

### N9. `HealthKitWorkoutStore.isLoadingSnapshot(month:year:)` is dead code

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:116-118`
- **Description:** The public method reads `loadingMonthKeys.contains(...)`.
  Grep finds no caller — `BodyChartsView` uses its own `pendingMonthSelection`
  state for the loading banner, and `BodyWorkoutsView` does not show a
  per-month loading hint at all.
- **Why it matters:** Suggests an in-progress UI hook that never landed.
  Either wire it (so Charts/Workouts can show the store's `loadingMonthKeys`
  directly and stay in sync after edge cases) or remove it.
- **Suggested fix:** Either delete the method, or wire `BodyChartsView.BodyChartsLoadingBanner`
  to read `workoutStore.isLoadingSnapshot(month:year:)` for the requested
  month instead of (or in addition to) `pendingMonthSelection`. Pick
  delete unless there is a known case where the local state misses a
  store update.
- **Risks / dependencies:** Low.

### N10. `WorkoutSnapshotStore.save(_:defaults:)` / `load(defaults:)` are test-only helpers in the public API

- **Severity:** Low
- **Related files:** `BodyShared/Services/WorkoutSnapshotStore.swift:102-133`,
  `BodyTests/WorkoutMonthSnapshotTests.swift:28-45`
- **Description:** Production code paths use the file-based
  `save(_:fileURL:)` / `load(fileURL:)`. The
  `UserDefaults`-keyed overloads (`save(_:defaults:)` /
  `load(defaults:)`) survive from the v0.1.0 storage shape. The only
  caller is `WorkoutMonthSnapshotTests.testSnapshotStoreRoundTripsCurrentMonthSnapshot`,
  which round-trips a snapshot through a private suite.
  `testSnapshotStoreRoundTripsCurrentMonthSnapshotFromFileURL` already
  covers the production round-trip via the file API.
- **Why it matters:** Two parallel storage backends in the type's public
  surface invite future code to pick the wrong one. The widget reads
  from the file path; if someone wires the app to the defaults path,
  the widget will not see the new data.
- **Suggested fix:** Either (a) remove the two methods and drop the
  redundant test (the file-URL test already covers the round-trip), or
  (b) keep them as internal/file-private with a `// test helper — use
  the file APIs in production` comment. Option (a) is simpler.
- **Risks / dependencies:** Drops `testSnapshotStoreRoundTripsCurrentMonthSnapshot`;
  no production callers.

### N11. `Calendar.current` defaults in trend `limited` helpers diverge from `Calendar.bodyGregorian` used elsewhere

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift:853`,
  `Body/Models/HealthSummarySnapshot.swift:893-908`,
  `Body/Views/BodyHomeView.swift:1051-1064`
- **Description:** `HealthTrendSeries.limited(to:calendar:date:)` and
  `BasicsTrendSummary.limited(to:...)` both default `calendar` to
  `.current`. The series is fetched via `HealthKitWorkoutStore` using
  `Calendar.bodyGregorian` (sunday-first, gregorian). The view-side
  callers in `BodyHealthMetricDetailView.visibleSeries` and
  `visibleBasicsTrend` do not pass a calendar, so the filter uses the
  user's system calendar (which is usually gregorian but can differ
  for some locales / calendar overrides).
- **Why it matters:** Inconsistency. For most users the two calendars
  resolve to the same dates; for users whose default calendar differs
  the recent-week filter window may shift by a day at the edge. The
  fetch and the filter should agree.
- **Suggested fix:** Change the default to `.bodyGregorian` in both
  `BasicsTrendSummary.limited` and `HealthTrendSeries.limited`. Verify
  `WorkoutMonthSnapshotTests.testHealthTrendSeriesLimitsToRecentWeek`
  still passes (it explicitly passes `calendar: calendar`, so the
  default change does not affect it).
- **Risks / dependencies:** None.

### N12. `HealthTrendSeries.limited(to: .recentMonth)` returns the series unfiltered

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift:893-908`
- **Description:** `guard range != .recentMonth else { return self }`
  short-circuits for `.recentMonth` and returns the entire backing
  series. Today the data is already capped at 30 days by
  `recentHealthTrendInterval` in `HealthKitWorkoutStore`, so this is a
  silent no-op in production. A reader looking at `limited(to:)` would
  reasonably assume both ranges are limited.
- **Why it matters:** Fragile to changes. If
  `recentHealthTrendInterval` is widened in the future, `.recentMonth`
  would silently surface more than 30 days. The function name implies
  filtering; the early return hides that the recent-month case relies
  on upstream length.
- **Suggested fix:** Make `.recentMonth` filter to the last 30 days
  explicitly, matching `.recentWeek`'s `dayCount`-driven window. Add
  a unit test that builds a 40-day series and asserts `.recentMonth`
  returns 30 points.
- **Risks / dependencies:** None for current production data; just
  removes the implicit dependency.

### N13. `BodyMonthYearPicker.monthYearList` is fixed at init; does not refresh across the month boundary

- **Severity:** Low
- **Related files:** `Body/Views/BodyMonthYearPicker.swift:48-68,144-169`
- **Description:** The carousel list is computed once in the View's
  `init` with `relativeTo: Date()`. If the user keeps the app
  foregrounded across midnight on the last day of a month (or returns
  to the Charts / Workouts tab after midnight without restarting),
  the picker still presents the prior month as the "current month"
  and the new month is absent from the list. `BodyApp.syncWhenAppBecomesActive`
  refreshes the workout snapshot but the picker is not rebuilt.
- **Why it matters:** Edge case (open Charts at 11:55 PM on May 31,
  swipe back at 12:05 AM on June 1) but reproducible. The user
  cannot navigate to June until they cold-launch the app.
- **Suggested fix:** Either (a) listen for `.NSCalendarDayChanged`
  notifications and rebuild the list when the month changes, or (b)
  recompute the list in a `.task(id: scenePhase)` when the app
  returns to foreground after a day boundary, or (c) make the list
  computed from a `@State` "today date" that updates on scene-phase
  changes.
- **Risks / dependencies:** Both `BodyChartsView` and `BodyWorkoutsView`
  embed the picker.

### N14. `HealthSummarySnapshot.isEmpty` checks `sleep.duration == nil` but ignores `sleep.stageSnapshot`, causing the "no Apple Health data" banner to remain hidden in a specific edge case

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift:85-98`,
  `Body/Services/HealthKitWorkoutStore.swift:380-387`
- **Description:** `isEmpty` returns true only when every metric value is
  nil and the sleep duration is nil and vitals are empty. The check
  reads `sleep.duration == nil && sleep.vitals.isEmpty` but does not
  consider `sleep.stageSnapshot`. If a user has only sleep-stage data
  recorded for the most recent night (no asleep totals returned by
  HealthKit), `fetchSleepSummary` builds a `SleepSummary` with
  `duration > 0` from `Self.sleepDuration(from:)`, so this is rarely
  observed in practice. But the inverse is also possible — a snapshot
  reconstructed from a cached decode that has a non-empty
  `stageSnapshot` but `duration == nil` would still be `isEmpty == true`
  for the banner predicate, even though sleep data exists.
- **Why it matters:** The banner test in
  `updateHealthDataNotice()` triggers the "No Apple Health data was
  found" copy when `snapshot.workoutCount == 0 && healthSummary.isEmpty
  && activityRingHistory.isEmpty`. A user with only sleep-stage data
  could see the banner even though data exists. Minor.
- **Suggested fix:** Extend `isEmpty` to also check
  `sleep.stageSnapshot.isEmpty`, or introduce a single
  `isLikelyNoData` test that the notice path consults.
- **Risks / dependencies:** Verify the existing test
  `testSleepVitalsMakeSleepSummaryNonEmptyAndUseSleepWindow` (which
  asserts `summary.isEmpty == false` when only `vitals` is populated)
  still passes.

### N15. `BodyHealthNoticeBanner` icon is hardcoded to `.blue`, ignoring the user's selected accent

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift:2441-2462`
- **Description:** `Image(systemName: "heart.text.square.fill")
  .foregroundColor(.blue)` paints the banner glyph system blue. Every
  other prominent accent surface (theme picker, accent picker, section
  highlights, trend range selector) follows
  `BodyApp.tint(selectedAccent.color)` / `.accentColor`. The banner is
  the one place the app uses a fixed `.blue`.
- **Why it matters:** Theming inconsistency for users who chose a
  non-blue accent (especially red, green, gray). The banner is small
  but appears prominently when HealthKit returns no data.
- **Suggested fix:** Use `.foregroundColor(.accentColor)` to inherit
  the selected accent. Or pick a semantic color (`.secondary`) if the
  banner should read as neutral guidance rather than accented call to
  action.
- **Risks / dependencies:** None.

### N16. Activity Rings detail uses `DispatchQueue.main.async` to delay `canLoadOlderMonths` instead of `Task`/`@MainActor`

- **Severity:** Low
- **Related files:** `Body/Views/BodyHomeView.swift:1906-1913`
- **Description:** `.onAppear { ...; DispatchQueue.main.async {
  canLoadOlderMonths = true } }` waits one runloop turn before allowing
  pagination. The async hop is the workaround for `LazyVStack`'s
  pre-fetch of off-screen `onAppear` sections during the initial
  scroll-to-current-month — the 2026-05-12 lessons-learned entry
  describes the exact bug. The fix works but mixes GCD into a
  SwiftUI/Concurrency view that otherwise uses `Task` and `await`.
- **Why it matters:** Concurrency-model drift. A future refactor that
  removes the GCD hop could re-introduce the pre-fetch bug. The
  invariant ("don't let pagination fire during initial layout") is
  invisible in the code.
- **Suggested fix:** Either replace with `Task { @MainActor in
  canLoadOlderMonths = true }`, or move the gate into
  `ActivityRingCalendarPaginationGate` itself (e.g. a "user has
  scrolled at least once" flag), keeping the SwiftUI view free of
  GCD.
- **Risks / dependencies:** Confirm with the pagination tests
  (`WorkoutMonthSnapshotTests.testActivityRingCalendarPaginationGateAllowsOneLoadPerUserScroll`)
  that semantics are preserved.

### N17. `WorkoutCalendarView.workoutMarkers` color fallback `.white` is unreachable

- **Severity:** Low
- **Related files:** `BodyShared/Components/WorkoutCalendarView.swift:105-114`
- **Description:** `workoutMarkers(count: day.workoutCount, color:
  day.primaryWorkoutType?.calendarContentColor ?? .white)` is invoked
  only inside `if day.workoutCount > 0`. `WorkoutDaySummary.primaryWorkoutType`
  is nil only when `workouts` is empty, so the `?? .white` branch is
  unreachable in production.
- **Why it matters:** Dead branch. Future reader has to follow the
  `primaryWorkoutType` semantics across files to verify safety.
  Likewise, mistakenly inverting the surrounding condition would silently
  surface white markers on a Coin-palette tile.
- **Suggested fix:** Either inline the implicit unwrap with an `else`
  guard, or call `workoutMarkers(count:color:)` with a non-optional
  color derived inside the guarded branch.
- **Risks / dependencies:** None.

### N18. Documentation drift: `README.md` scope and `TestPlan.md` omit the Workouts tab and the dashboard / detail expansions

- **Severity:** Low
- **Related files:** `README.md:9-22`, `TestPlan.md:7-15,32-54`
- **Description:** README's "v0.1.0 Scope" list and "Project Structure"
  still describe a Home / Charts / Settings tab shell. The current
  `MainTabView` has four tabs — Home, Workouts, Charts, Settings.
  TestPlan's "What Was Reviewed" lists `BodyHomeView`, `BodyChartsView`,
  `BodySettingsView` and does not mention `BodyWorkoutsView`,
  `BodyMonthYearPicker`, the Activity Rings detail, or the Workout
  detail sheet. The automated and manual tables also stop at the
  v0.1.0 surface (no sort/filter/search cases for the Workouts tab,
  no activity-rings-pagination case, no workout-detail-sheet case).
- **Why it matters:** TestPlan and README are presented as authoritative
  test scope and product description; drift undermines both. The audit
  trail also makes it hard to recall which surfaces were covered at
  which version.
- **Suggested fix:** Refresh both docs in the same pass that lands a
  version bump (see N3). For README, add the Workouts tab and the
  expanded Home health dashboard. For TestPlan, add the new view files
  to "What Was Reviewed", and add manual cases for Workouts
  sort/filter/search, workout detail sheet, and Activity Rings
  pagination.
- **Risks / dependencies:** Pair with N3 — these docs and the version
  shipping should change together.

---

## 3. Code quality findings

- **Duplicated code:**
  - `weekdaySymbols` is reimplemented in
    `BodyShared/Components/WorkoutCalendarView.swift:125-131` and
    `Body/Views/BodyHomeView.swift:2004-2010` (Activity Rings detail).
    Both apply the same Sunday-first rotation. Lift one shared helper.
  - `leadingBlankCount` rotation is implemented in
    `BodyShared/Models/WorkoutMonthSnapshot.swift:103-107` and
    `Body/Views/BodyHomeView.swift:2012-2019`. Same `(firstWeekday -
    calendar.firstWeekday + 7) % 7` formula.
- **Unused or outdated files / symbols:**
  - `Body/Services/HealthKitWorkoutStore.swift:868-888` —
    `dailyQuantitySummary` is never called (see N8).
  - `Body/Services/HealthKitWorkoutStore.swift:116-118` —
    `isLoadingSnapshot(month:year:)` is never called (see N9).
  - `BodyShared/Services/WorkoutSnapshotStore.swift:102-133` — defaults
    overloads are only used by one test that the file-URL test
    duplicates (see N10).
- **Overly complex files or functions:**
  - `Body/Views/BodyHomeView.swift` is 2662 lines and bundles the Home
    grid, the metric detail navigation destination, every sleep
    supplement card, the basics dual-axis chart, the Activity Rings
    detail, the rings graphic, and the metric card. Splitting Activity
    Rings out (it already has its own data shape and pagination gate)
    into a dedicated file shrinks Home by ~700 lines without changing
    behavior.
  - `Body/Services/HealthKitWorkoutStore.swift:1409-1580` workout-type
    raw-value switch is mechanical. The 2026-05-10 prior audit
    suggested a table-driven map; the code still uses the long
    `switch`. Low priority; flag for the same future refactor.
- **Naming inconsistencies:**
  - Fixed in the follow-up pass: `BodyAppearancePreferences.swift`
    was renamed to `BodyAppearancePreference.swift` to match
    `enum BodyAppearancePreference`.
  - Both `Calendar.bodyGregorian` and `Calendar.current` appear; the
    project's intent is bodyGregorian (see N11).
- **Structural improvements:**
  - Detail-screen branching by display title (N2) would be cleaner if
    `BodyHealthMetricDetailModel` carried a `kind` field. The
    construction site (`detailModel(for:)`) already has the kind in
    scope.

---

## 4. Functional issues

- **Empty-day calendar tap (N4)** opens a sheet with a "0 workouts ·
  0m · 0 kcal" header followed by "No workouts for this selection."
- **Filter toggle (N5)** is surprising — tapping a singly-selected
  type re-selects all types instead of clearing the selection.
- **Filter visibility (N6)** disappears when the current month
  contains none of the unchecked types; the empty-state hint then
  reads "No workouts for May 2026" without mentioning the filter.
- **Activity Rings pagination (N16)** relies on a one-runloop GCD
  delay to avoid `LazyVStack` pre-fetch; the invariant is hidden.
- **Month-year picker (N13)** does not refresh when the device clock
  crosses a month boundary while the app is foregrounded.
- **HealthKit notice predicate (N14)** ignores `sleep.stageSnapshot`,
  so a snapshot with only sleep-stage data could still trigger the
  empty-data banner.

---

## 5. UI/UX issues

- **Workout Type widget empty state (N7)** renders the glyph in
  `Color.white.opacity(0.45)` which is invisible on the user-selected
  White background.
- **Health notice banner accent (N15)** is fixed to system blue
  regardless of the user's selected accent.
- **Workouts tab filter behavior (N5)** is non-standard; standard
  toggle plus Select All / Deselect All would match iOS conventions.
- **`BodyHealthNoticeBanner` copy** at
  `Body/Services/HealthKitWorkoutStore.swift:386` is appropriately
  specific ("No Apple Health data was found. If you expected data,
  check Body's permissions in the Health app.") but the banner has no
  affordance to deep-link to the Health app; tapping it does nothing.
  Consider a `Link` to Apple Health's privacy controls or a hint that
  the path is Settings → Health → Data Access & Devices → Body.
- **Workout detail sheet** uses a `presentationDetents([.height(730)])`
  (`Body/Views/BodyWorkoutsView.swift:529`). On smaller devices
  (iPhone SE, iPhone 12 mini) 730 pt may exceed available height,
  forcing the system to clamp to full-screen. Acceptable but
  device-dependent.

---

## 6. Data and persistence issues

- **Silent encode/decode in `HealthDashboardSnapshotStore` (N1)**
  leaves the cached Home dashboard stuck on stale data without a
  log signal.
- **`HealthTrendSeries.limited` recentMonth no-op (N12)** depends
  on upstream fetch length to remain at 30 days; the function does
  not enforce it locally.
- **`WorkoutSnapshotStore` legacy defaults API (N10)** is parallel to
  the production file path; future code could pick the wrong one.
- **Snapshot codec resilience:** Decoding errors at
  `WorkoutSnapshotStore.load(fileURL:)` log via `os.Logger`. The new
  `HealthDashboardSnapshotStore` does not. Once N1 lands, the two
  stores would share consistent failure observability.
- **Schema versions:** Neither `WorkoutMonthSnapshot` nor
  `HealthDashboardSnapshot` carry an explicit schema version. The
  v0.2.x dashboard added `activityRingHistory` and uses
  `decodeIfPresent` for forward compatibility; the snapshot however
  still encodes `BodyWorkoutType` raw strings — unknown future raw
  strings fail the entire decode rather than the per-day decode.
  Same v0.1.0 foot-gun, not addressed by the fix pass. Low priority
  until a `BodyWorkoutType` case is removed (additions are tolerated
  via the `.other` fallback in the mapping, not in decode).

---

## 7. Configuration and platform issues

- **Version drift (N3):** `MARKETING_VERSION = 0.2.3`,
  `CURRENT_PROJECT_VERSION = 3`, README says "0.2.3 (build 1)", branch
  is `codex/body-v0.2.6`, VersionHistory tops out at 0.2.3.
- **`NSHealthShareUsageDescription`** present in pbxproj for both
  Debug and Release; no `NSHealthUpdateUsageDescription` (no write
  scopes requested) — correct.
- **App group identifier** `group.com.zihengthedeveloper.Body` matches
  in both entitlements files and the snapshot store; tests confirm
  the parity.
- **Privacy manifests** at `Body/PrivacyInfo.xcprivacy` and
  `BodyWidgetExtension/PrivacyInfo.xcprivacy` declare
  `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` and
  `NSPrivacyTracking = false`.
- **Deployment target** `IPHONEOS_DEPLOYMENT_TARGET = 18.0` across all
  six configurations; matches README and uses of
  `AppIntentTimelineProvider`.
- **`SUPPORTS_MACCATALYST = NO`** and `TARGETED_DEVICE_FAMILY = 1`
  (iPhone-only).
- **Widget target** is `APPLICATION_EXTENSION_API_ONLY = YES`.
- **Alternate app icons** in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`
  match the six `BodyAppIconOption.all` entries.
- **`appVersionDisplay` hardcoded fallback** of "0.2.3" / "1" in
  `Body/Views/BodySettingsView.swift:147-151` is stale relative to
  `CURRENT_PROJECT_VERSION = 3` and to the branch's claimed v0.2.6;
  this is unreachable when the Info.plist values are present, but
  silently becomes a wrong number if the keys ever go missing.
- **`AccentColor.colorset`** (lime green 0xC9FF05-ish) exists but is
  overridden at runtime by `BodyApp.tint(selectedAccent.color)`; it
  surfaces only in SwiftUI previews. Not dead, just rarely seen.

---

## 8. Testing gaps

- **Highest-risk uncovered features:**
  - `HealthDashboardSnapshotStore` silent-error path (N1) — no test
    asserts a logger / error path; today there is no failure mode to
    test, but adding `do/catch` enables an asserted log.
  - `BodyWorkoutsView` sort and filter — no automated coverage for
    `sorted(workouts:)` ordering, `toggleWorkoutType` semantics, or
    `hasActiveFilters` empty-month behavior (N5, N6). These are pure
    functions that are easy to test.
  - `BodyMonthYearPicker` cross-day refresh (N13) — no test or manual
    case covers the month-boundary scenario.
  - `WorkoutTypeBreakdownView` empty-state on white widget background
    (N7) — visual regression that can be guarded with a snapshot
    test using `WidgetCenter` previews.
  - `BodyChartsView` empty-day tap behavior (N4) — no test covers
    the empty-day sheet flow.
- **Suggested tests:**
  - Add `BodyWorkoutsViewTests` for `sorted(workouts:)` and
    `toggleWorkoutType` (extract the toggle into a pure helper that
    can be exercised without SwiftUI).
  - Add `HealthDashboardSnapshotStoreTests` for explicit
    encode-failure logging (after N1 lands, assert via a logger
    interceptor or a small test seam).
  - Pin `BodyChartsView`'s empty-day sheet behavior with a UI test
    or a focused unit test on `BodyWorkoutListSelection.day(_)`
    construction.
  - Pin `HealthTrendSeries.limited(to: .recentMonth)` against a
    40-day series after N12.
  - Manual / on-device cases not currently in `TestPlan.md`:
    - Workouts tab filter + month change + empty state copy (N6).
    - Workout Type widget on White background with no data (N7).
    - Workout detail sheet on iPhone SE / 12 mini for the 730-pt
      detent clamp.
    - Charts tab tap on an empty calendar day (N4).
    - `xcodebuild test -destination 'platform=iOS Simulator,
      name=iPhone 17 Pro'` per lessons-learned (current machine has
      17 Pro available).

---

## 9. Priority recommendations

- **Fix first:**
  - N1 — silent JSON failures in the Home dashboard cache will
    silently undercut the new health UI.
  - N2 — title-string branching in the detail screen is a maintenance
    landmine; trivial to fix while the structure is fresh.
  - N3 — version drift across pbxproj, docs, and branch is confusing
    and will block the next archive run.
  - N4 — empty-day tap is the most user-facing UX bug in this audit.
- **Fix next:**
  - N5 — non-standard filter toggle.
  - N6 — hidden filter state on month change.
  - N7 — invisible widget empty-state icon on white background.
  - N18 — sync README + TestPlan with the new Workouts tab and
    dashboard scope.
- **Optional cleanup:**
  - N8 — delete `dailyQuantitySummary`.
  - N9 — delete or wire `isLoadingSnapshot`.
  - N10 — drop the UserDefaults overloads.
  - N11, N12 — calendar default + recent-month explicit limit.
  - N13 — month picker cross-day refresh.
  - N14 — `isEmpty` should consider `stageSnapshot`.
  - N15 — banner icon should follow selected accent.
  - N16 — replace GCD hop with `Task` / pagination-gate flag.
  - N17 — delete unreachable `.white` fallback in workout markers.

---

## What was checked

- App entry: `Body/BodyApp.swift`, `Body/Views/MainTabView.swift`.
- App models: `Body/Models/BodyAppearancePreference.swift`,
  `Body/Models/HealthSummarySnapshot.swift`.
- App services: `Body/Services/HealthKitWorkoutStore.swift` (full).
- App views: `Body/Views/BodyHomeView.swift` (full),
  `Body/Views/BodyChartsView.swift`,
  `Body/Views/BodySettingsView.swift`,
  `Body/Views/BodyWorkoutsView.swift`,
  `Body/Views/BodyMonthYearPicker.swift`.
- Shared models: `BodyShared/Models/BodyWorkoutType.swift`,
  `BodyShared/Models/WorkoutMonthSnapshot.swift`,
  `BodyShared/Models/WorkoutSummary.swift`.
- Shared components: `BodyShared/Components/WorkoutCalendarView.swift`,
  `BodyShared/Components/WorkoutTypeBreakdownView.swift`.
- Shared services: `BodyShared/Services/WorkoutSnapshotStore.swift`.
- Widgets: `BodyWidgetExtension/BodyWidgetExtensionBundle.swift`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift`,
  `BodyWidgetExtension/Info.plist`.
- Tests: `BodyTests/WorkoutMonthSnapshotTests.swift`,
  `BodyTests/HealthKitWorkoutStoreTests.swift`,
  `BodyTests/BodyWorkoutTypeTests.swift`,
  `BodyTests/ProjectConfigurationTests.swift`.
- Configuration: `Body/Body.entitlements`,
  `BodyWidgetExtension.entitlements`, `Body/PrivacyInfo.xcprivacy`,
  `BodyWidgetExtension/PrivacyInfo.xcprivacy`,
  `body.xcodeproj/project.pbxproj` (build settings, target configs,
  alternate app icons, deployment target).
- Asset catalog: `Body/Assets.xcassets/AccentColor.colorset/Contents.json`
  (color values only; PNG sizes confirmed in
  `ProjectConfigurationTests.testAppIconAssetsIncludePrimaryAndAlternateOptions`).
- Docs: `README.md`, `VersionHistory.md`, `TestPlan.md`,
  `LessonsLearned.md`, `AGENTS.md`.
- Archive cross-reference: `docs/IssuesArchive-01.md` (all 16 prior
  findings verified against current code; one regression of the silent
  JSON pattern surfaced in the newer `HealthDashboardSnapshotStore`).
- Grep queries:
  - `rg "TODO|FIXME|XXX|HACK"` across the project — no matches.
  - `rg "try?"` to enumerate silent-error paths.
  - `rg "Calendar.current"` to find calendar inconsistencies.
  - `rg "model.title =="` to find string-equality branching.
  - `rg "dailyQuantitySummary|isLoadingSnapshot|respiratoryRateText"`
    to confirm dead-method claims.
  - `rg "WorkoutSnapshotStore"` to verify production vs. test call
    sites.
  - `rg "Color.white"` to find white-on-white widget risks.

## Not checked (worth a follow-up)

- Running the project on a real device or simulator to verify N4, N5,
  N7, N13 user-visible effects; HealthKit/widget interactions still
  need a real device for full signal.
- LaunchScreen XML and the workspace shared scheme files.
- Asset catalog `Contents.json` JSON validation beyond confirming the
  PNGs exist (asset wiring is asserted in `ProjectConfigurationTests`).
- Visual review of light/dark mode and Dynamic Type for the new sleep
  vitals region chart, the basics dual-axis chart, and the Activity
  Rings detail (requires a build).
- Localization beyond English (TestPlan continues to defer this).
- Lock Screen / accessory widget families (still deferred per
  TestPlan).
- Carry-forward verification: all 16 issues in
  `docs/IssuesArchive-01.md` were confirmed addressed in code, but
  the audit did not exhaustively re-derive each fix from runtime
  behavior. N1 is the one observed regression of the archive's N12
  pattern (silent JSON failures), surfaced in the newer
  `HealthDashboardSnapshotStore`.

## Fix pass resolution

Completed on 2026-05-12 on branch `codex/body-v0.2.6`.

### Fixed numbered findings

| ID | Resolution |
| --- | --- |
| N1 | Added `os.Logger` diagnostics and explicit `do`/`catch` encode/decode handling to `HealthDashboardSnapshotStore`. |
| N2 | Added stable `HealthMetricKind` routing to `BodyHealthMetricDetailModel`; Sleep and Basics detail behavior no longer depends on display titles. |
| N3 | Bumped all project `MARKETING_VERSION` values to `0.2.6`, all `CURRENT_PROJECT_VERSION` values to `6`, updated settings fallback text, and refreshed README / VersionHistory / configuration tests. |
| N4 | Empty workout calendar days no longer trigger drill-down selection or expose an "Open workouts" accessibility hint. |
| N5 | Replaced the Workouts filter type picker with plain toggle semantics; Select All and Deselect All remain the bulk controls. |
| N6 | Active filter state now compares against `BodyWorkoutType.allCases`, so empty filtered months still show filter-aware empty-state guidance. |
| N7 | Changed the Workout Types empty-state icon from white opacity to secondary opacity so it remains visible on white widget backgrounds. |
| N8 | Removed unused `HealthKitWorkoutStore.dailyQuantitySummary`. |
| N9 | Removed unused `HealthKitWorkoutStore.isLoadingSnapshot(month:year:)`. |
| N10 | Removed the legacy `WorkoutSnapshotStore` UserDefaults overloads and the redundant defaults round-trip test; the file-URL round-trip remains. |
| N11 | Changed `HealthTrendSeries.limited` and `BasicsTrendSummary.limited` defaults to `Calendar.bodyGregorian`. |
| N12 | Made `.recentMonth` explicitly filter to the last 30 days and updated unit coverage. |
| N13 | Made `BodyMonthYearPicker` keep its month list in state and rebuild on `.NSCalendarDayChanged` and foreground activation; added coverage for relative month-list generation. |
| N14 | Updated `HealthSummarySnapshot.isEmpty` to treat non-empty sleep stage snapshots as data. |
| N15 | Changed `BodyHealthNoticeBanner` to use `.accentColor` instead of hardcoded blue. |
| N16 | Replaced the Activity Rings detail GCD pagination delay with a main-actor `Task.yield()` and documented the LazyVStack layout gate. |
| N17 | Removed the unreachable white marker fallback in `WorkoutCalendarView` by deriving marker color only from an available primary workout type. |
| N18 | Refreshed README and TestPlan for the Workouts tab, Activity Rings detail, workout detail sheets, filter/search cases, and expanded Home dashboard scope. |

### Additional cleanup

- Lifted duplicated weekday-symbol rotation and leading-blank calendar math into shared `Calendar` helpers used by the workout calendar and Activity Rings detail.
- Renamed `BodyAppearancePreferences.swift` to `BodyAppearancePreference.swift` so the file name matches the contained type.
- Added focused tests for workout filter semantics, calendar-day selectability, trend limiting, sleep-stage emptiness, and month-list generation.
- Added a `LessonsLearned.md` entry for the CoreSimulator / generic-build verification fallback encountered during this pass.

### Verification

- `xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO -only-testing:BodyTests/WorkoutMonthSnapshotTests` did not reach compilation because CoreSimulator had no matching available simulator runtimes.
- `xcodebuild build-for-testing -project body.xcodeproj -scheme Body -destination generic/platform=iOS -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO` did not complete because asset compilation required unavailable simulator runtimes.
- `xcodebuild -project body.xcodeproj -scheme Body -destination generic/platform=iOS -derivedDataPath /private/tmp/body-derived CODE_SIGNING_ALLOWED=NO build` passed after the fixes.
