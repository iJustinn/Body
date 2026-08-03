# Body — Issues Report

Audit of branch `body-v0.9.1` on 2026-06-09. Read-only review; no code was
modified. This is the first report in the `Issues-cc.md` chain; the most
recent prior audits are `Issues.md` (v0.5.6, 2026-05-24) and the legacy
`docs/IssuesArchive-01..04.md` chain, which were cross-referenced but left
untouched.

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

Body v0.9.1 build 2 is in very good shape. Since the v0.5.6 audit the repo
completed the long-deferred file splits (`BodyHomeView.swift` 8,608 → 1,955
lines with detail views and charts carved into `Body/Views/Health/` and
`Charts/`; `HealthSummarySnapshot.swift` 3,374 → 590 lines with models split
into `HealthTrend.swift`, `Sleep.swift`, `ActivityRings.swift`,
`SourceComparison.swift`, `Readiness/`; the fetch engine split into six
`HealthKitFetchEngine+*.swift` extensions), added `schemaVersion` to both
persisted snapshots, replaced the last polling loop with per-month
continuations, fixed every carried-forward finding except the intentionally
deferred Body Pro placeholders, and shipped three new health widgets backed
by a new `HealthWidgetSnapshot` pipeline plus iPad adaptive layout.

This run surfaces eleven findings. The most user-visible is N1, a
copy-paste icon regression that renders the Steps home trend card with the
Active Energy flame instead of `figure.walk` — the same regression class as
the prior audit's Time In Daylight `plus` icon. The next tier concerns the
new widget pipeline and units: Settings > Data > Cache > Clear Cache never
deletes the health widget snapshot so health widgets keep showing cleared
data (N2), and the Skin Temperature baseline deviation is always computed
and labeled in Celsius even for Fahrenheit users, disagreeing with the
chart annotation on the same detail screen (N3). The rest are a narrow
re-entrancy window in the refresh entry points (N4) and hygiene items.

Areas reviewed: app entry / scene phase, the full `HealthKitWorkoutStore` +
`HealthKitFetchEngine` (all six extensions), snapshot persistence (dashboard
file store, workout app-group stores, the new `HealthWidgetSnapshotStore`),
the widget snapshot builder and all five widgets, shared components, all
health models (trends, sleep scoring, readiness calculator, training load,
activity rings, source comparison), Summary dashboard + trend cards, metric
detail view, Workouts tab, Settings (targeted: source sheet, cache, sync
status), Body Pro (carry-forward check), entitlements, build settings,
privacy manifests, and the six test files. Intentionally not reviewed:
runtime behavior on device (no build in this run), the chart struct
internals under `Body/Views/Health/Charts/` beyond transition-parity greps
(audited in detail at v0.5.6 before the mechanical file split),
`BodyActivityRingsDetailView`/`BodyMonthYearPicker`/`BodyWorkoutListSheet`
(unchanged since the prior audit), Lock Screen widget families, and
localization beyond English.

---

## 2. Issue list

### N1. Steps home trend card renders the Active Energy flame icon instead of `figure.walk`

- **Severity:** High
- **Related files:** `Body/Views/Health/BodyHomeTrendCard.swift:364-374`
  (the `.steps` configuration), `Body/Views/Health/BodyHomeTrendCard.swift:386`
  (the `.activeEnergy` configuration it was copied from),
  `Body/Models/BodyAppearancePreference.swift:1091` (canonical
  `BodyHomeTrendCardKind.steps.iconName = "figure.walk"`),
  `Body/Views/BodyHomeView.swift:441` (home metric card uses `figure.walk`),
  `BodyShared/Models/HealthWidgetSnapshot.swift:69` (widget uses `figure.walk`)
- **Description:** `BodyHomeTrendCardFactory.configuration(for: .steps)`
  builds the Steps trend card with
  ```swift
  case .steps:
      return Configuration(
          kind: .steps,
          title: "Steps",
          ...
          symbolName: "flame.fill",
  ```
  Every other Steps surface uses `figure.walk`: the Summary metric card,
  Settings > Metrics > Trend Cards row (`BodyHomeTrendCardKind.steps.iconName`),
  Settings > Data > Permissions row, and the widget metric
  (`HealthWidgetMetric.steps.symbolName`). The flame is Active Energy's
  glyph. Because `BodyHealthMetricDetailView.detailTrendComparisonCard`
  uses the same factory, the trend comparison card on the **Steps detail
  page** also shows the flame.
- **Why it matters:** A card titled "Steps" with a flame icon appears in
  the Summary trends section (whenever the steps trend qualifies or "Show
  All Trends" is tapped) and on every visit to the Steps detail page. On
  the Summary it sits in the same list as the real Active Energy trend
  card, which uses the identical flame + orange tint — two different
  metrics with the same icon. Same regression class as the prior audit's
  N1 (Time In Daylight `plus` icon), which was fixed at three sites but
  this fourth icon table was not aligned.
- **Suggested fix:** Change `symbolName: "flame.fill"` to
  `symbolName: "figure.walk"` at `BodyHomeTrendCard.swift:370`. Longer
  term, source the factory's `symbolName`/`symbolColor` from
  `BodyHomeTrendCardKind.iconName`/`tintColor` so the table exists once
  (see Structural improvements).
- **Risks / dependencies:** None. No test pins the factory's symbol names
  (`grep "flame.fill" BodyTests` only matches unrelated chart assertions).

### N2. Settings > Data > Cache > Clear Cache leaves the health widget snapshot on disk, so health widgets keep showing cleared data

- **Severity:** Medium
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:957-989`
  (`clearLocalCache`), `BodyShared/Services/HealthWidgetSnapshotStore.swift:119-130`
  (`delete()` — zero production callers),
  `Body/Services/HealthKitWorkoutStore.swift:244-259` (`cacheStatus`)
- **Description:** `clearLocalCache` deletes the current/previous workout
  snapshots and the dashboard snapshot, clears the refresh timestamp, then
  calls `WidgetCenter.shared.reloadAllTimelines()`:
  ```swift
  WorkoutSnapshotStore.delete()
  WorkoutSnapshotStore.deletePrevious()
  HealthDashboardSnapshotStore.delete()
  HealthDashboardSnapshotStore.clearLastSuccessfulRefreshDate()
  WidgetCenter.shared.reloadAllTimelines()
  ```
  It never calls `HealthWidgetSnapshotStore.delete()`, and
  `grep -rn "HealthWidgetSnapshotStore"` confirms the only production
  callers are `save` (store) and `load` (the three health widget
  providers) — `delete()`, `exists()`, and `fileSize(at:)` are dead. The
  triggered timeline reload makes the Health Metric, Health Trend, and
  Sleep Stages widgets re-read the untouched
  `healthWidgetSnapshot.json` and re-render the supposedly cleared data,
  while the workout widgets correctly go empty. The stale file survives
  until the next successful dashboard refresh rewrites it.
  Relatedly, `cacheStatus.diskSizeBytes` sums only
  `WorkoutSnapshotStore.totalDiskSizeBytes + HealthDashboardSnapshotStore.totalDiskSizeBytes`,
  so the "On-disk size" line in Settings > Data > Cache under-reports by
  the health widget snapshot's size.
- **Why it matters:** "Clear Cache" is a privacy-flavored action; a user
  clearing local health data still has trend values, current readings,
  and last night's sleep stages rendered on their Home Screen widgets and
  stored in the app group. The in-app cache status simultaneously reports
  "Empty".
- **Suggested fix:** Add `HealthWidgetSnapshotStore.delete()` to
  `clearLocalCache` before the timeline reload, and add
  `HealthWidgetSnapshotStore.fileSize(at:)` (exposed as a
  `totalDiskSizeBytes` to match the sibling stores) to
  `cacheStatus.diskSizeBytes`.
- **Risks / dependencies:** None. Widgets already render an "Open Body to
  sync" empty state when `load()` returns nil.

### N3. Skin Temperature baseline deviation is always computed and labeled in Celsius, disagreeing with the Fahrenheit chart annotation on the same screen

- **Severity:** Medium
- **Related files:** `Body/Views/BodyHomeView.swift:101-128`
  (`wristTemperatureBaselineDeviationDisplay` — hardcoded `unit: "C"`,
  math on the raw Celsius series), `Body/Views/BodyHomeView.swift:654-689`
  (Summary card), `Body/Views/BodyHomeView.swift:948-995` (detail header),
  `Body/Views/Health/BodyHealthMetricDetailView.swift:1085-1121`
  (chart baseline + deviation formatter, which DO use the preference unit),
  `Body/Services/HealthWidgetSnapshotBuilder.swift:241-268` (widget mirror,
  "the deviation is always reported in C")
- **Description:** The Skin Temp card and the detail page's header show two
  prominent values: the baseline deviation and the actual temperature. The
  actual value is converted via the user's temperature unit preference, but
  the deviation is always derived from the raw Celsius series and returned
  with `unit: "C"`. On the detail page itself, the trend chart's dashed
  baseline (`wristTemperatureTrendBaseline`) and its scrub deviation
  formatter (`wristTemperatureTrendBaselineDeviationFormatter`) are
  computed from the **transformed** series and the preferred unit. For a
  Fahrenheit user this means: card shows "Baseline +0.3 C" next to
  "97.2 F", and scrubbing the chart below shows "+0.5 F" for the same
  excursion (a 0.3 °C delta is 0.54 °F). The small Health Metric widget
  reproduces the header pair, so the mismatch also ships to the Home
  Screen.
- **Why it matters:** Two different numbers and units for the same concept
  on one screen reads as wrong data. Only affects users with Fahrenheit
  (explicit, or System units in a US-region locale) — but those are
  exactly the users who can't interpret a Celsius delta at a glance.
- **Suggested fix:** Convert the deviation in
  `wristTemperatureBaselineDeviationDisplay` and
  `HealthWidgetSnapshotBuilder.wristTemperatureDeviation`: multiply the
  Celsius delta by 1.8 when the preference resolves to Fahrenheit and emit
  the preference's unit label (deltas convert by scale only, no +32
  offset — don't reuse `temperatureValue(celsius:)` on the delta). Thread
  the temperature preference into both helpers; the builder already
  receives it.
- **Risks / dependencies:** Keep the home card, detail header, chart
  formatter, and widget builder consistent in one pass — the duplication
  between `BodyHomeView.swift:101` and `HealthWidgetSnapshotBuilder.swift:241`
  is what allowed this divergence (see Code quality findings).

### N4. Refresh entry points check `isRefreshing` but don't set it until after an `await`, so two callers can run full refreshes concurrently

- **Severity:** Medium
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:261-278`
  (`requestAuthorizationAndRefresh`), `:991-994` (`refreshRecentMonths`
  sets `isRefreshing` on entry), `:280-293` (`refreshHealthMetric` — same
  shape), `:454-473` (`refreshWorkoutMonth` — same shape)
- **Description:** `requestAuthorizationAndRefresh` guards on
  `!isRefreshing`, then suspends at `try await engine.requestAuthorization()`
  (an XPC round-trip) before `refreshRecentMonths` finally sets
  `isRefreshing = true`. Because the store is `@MainActor`, a second
  caller that arrives during that suspension — e.g. pull-to-refresh on the
  Summary while `updateDefaultHealthDataSource` /
  `updateCombinesHealthDataSourcesByName` (Settings > Data > Source) is in
  its authorization await — passes the same guard and starts a second full
  dashboard refresh. The two `refreshRecentMonths` calls then interleave
  their progressive `@Published` writes, and the first to finish runs
  `finishRefresh()`, flipping `isRefreshing = false` and resuming all
  `awaitNextRefreshCompletion()` waiters (the pull-to-refresh overlay
  dismisses) while the second refresh is still streaming results.
- **Why it matters:** Duplicate fetch cost (the full ~25-query trend fan
  out twice) and an overlay/`isRefreshing` indicator that can drop early.
  No data corruption — last write wins on value-typed snapshots — but the
  "Loading data..." contract from v0.5.0 ("stays on screen until the
  underlying refresh actually finishes") can be violated in this window.
  `Needs verification` on device for how often the window is hit; the
  suspension is short but real.
- **Suggested fix:** Set `isRefreshing = true` (and `defer { finishRefresh() }`)
  at the top of `requestAuthorizationAndRefresh` / `refreshHealthMetric` /
  `refreshWorkoutMonth` before the first `await`, and have the inner
  `refreshRecentMonths` / `refresh(month:year:)` accept that the flag is
  already set (or convert the flag writes into a small
  `beginRefresh()/finishRefresh()` pair with a reentrancy count).
- **Risks / dependencies:** `finishRefresh()` must still run exactly once
  per entry; audit the `defer` blocks so a nested call doesn't resume
  waiters early. Touches the same machinery as the pull-to-refresh
  overlay (`awaitRefreshCompletion`).

### N5. Small Health Metric widget shows a "--" card for metrics with no data instead of the empty state the medium widget shows

- **Severity:** Low
- **Related files:** `BodyShared/Components/HealthWidgetMetricCardView.swift:18-24`
  (`if let trend` routing), `BodyShared/Models/HealthWidgetSnapshot.swift:217-219`
  (`hasAnyData`), `BodyShared/Components/HealthWidgetTrendChartView.swift:22-44`
  (medium widget's `series.isEmpty` routing),
  `Body/Services/HealthWidgetSnapshotBuilder.swift:74-88` (builder always
  emits all 16 metrics)
- **Description:** The small widget only falls back to its
  "No … data / Open Body to sync" empty state when `trend == nil`. The
  builder emits a `HealthWidgetMetricTrend` for every
  `HealthWidgetMetric.allCases`, so once any snapshot exists, a metric the
  user has disabled in Settings > Data > Permissions (or that simply has
  no samples) renders title + blank 36 pt chart area + "--" + icon. The
  medium trend widget checks `series?.isEmpty == false` and correctly
  shows its empty state for the same metric.
- **Why it matters:** Inconsistent empty handling between the two new
  widgets; a blank-chart "--" card looks broken rather than intentionally
  empty.
- **Suggested fix:** In `HealthWidgetMetricCardView.body`, route to
  `emptyState` when `trend == nil || trend?.hasAnyData == false` (or
  `trend.week.isEmpty`, matching the chart actually drawn).
- **Risks / dependencies:** None.

### N6. `HealthKitWorkoutStore.recentActivityRingMonthKeys` is dead code duplicating the engine's copy

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:1440-1457`,
  `Body/Services/HealthKitFetchEngine+ActivityRings.swift:127-149` (the
  live copy)
- **Description:** The store's `private static func
  recentActivityRingMonthKeys(count:from:calendar:)` has no callers —
  `grep -rn "recentActivityRingMonthKeys" Body BodyShared BodyTests`
  matches only the declaration and the engine extension's own definition +
  internal call (`Self.recentActivityRingMonthKeys` at
  `HealthKitFetchEngine+ActivityRings.swift:41`). The logic moved to the
  engine during the extraction; the store copy was left behind.
- **Why it matters:** Dead, near-identical duplicate of live code invites
  a future edit to the wrong copy.
- **Suggested fix:** Delete the store's version.
- **Risks / dependencies:** None (no test references it).

### N7. README and TestPlan still describe the "May 2026 seed snapshot", but the placeholder now generates for the current month

- **Severity:** Low
- **Related files:** `README.md:36` ("A May 2026 seed snapshot keeps the
  UI useful before authorization."), `TestPlan.md:49` (M4 expects "Widget
  shows May 2026 preview data"),
  `BodyShared/Models/WorkoutMonthSnapshot.swift:174-197`
  (`placeholder` → `makePlaceholder(generatedAt: Date())`)
- **Description:** The hardcoded May 2026 seed flagged as a "watch" item
  in the prior audit was fixed — `WorkoutMonthSnapshot.placeholder` now
  derives month/year from the current date. The README feature bullet and
  TestPlan M4's expected result were not updated and still pin May 2026
  (already one month stale as of this audit).
- **Why it matters:** A tester following M4 in June 2026+ would fail the
  case against correct behavior; the README misdescribes shipped behavior.
- **Suggested fix:** Reword both to "a current-month preview snapshot"
  (M4: "Widget shows preview data for the current month").
- **Risks / dependencies:** Doc-only.
  `ProjectConfigurationTests` does not pin either sentence.

### N8. `HealthTrendWidget` header comment promises a secondary-source series the widget no longer renders

- **Severity:** Low
- **Related files:** `BodyWidgetExtension/HealthTrendWidget.swift:5-7`,
  `BodyShared/Models/HealthWidgetSnapshot.swift:222-257` (tolerant decoder
  that drops the legacy `{ primary, secondary }` shape, keeping primary),
  `BodyShared/Components/HealthWidgetTrendChartView.swift` (renders a
  single series)
- **Description:** The file comment reads "charts a chosen metric's
  weekly/monthly trend (primary source, plus the secondary source when one
  is selected in the app)". The current `HealthWidgetMetricTrend` schema
  carries only the primary series — the migration decoder explicitly
  discards the legacy secondary — and the chart view draws one series with
  one average line.
- **Why it matters:** The comment documents the pre-redesign behavior; a
  contributor could "fix" the widget to match the comment, or vice versa,
  without knowing which is intended.
- **Suggested fix:** Drop the parenthetical from the comment (or, if
  secondary overlay is still intended, track it as a feature gap instead).
- **Risks / dependencies:** None.

### N9. Body Pro purchase page still presents a live-looking $5.99 purchase row and a gold checkmark on the "Future Pro Updates" placeholder

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:48,89,101` (taps only
  set "… not available in this build." status text),
  `Body/Views/BodyProView.swift:269` (`Text("$5.99")`),
  `Body/Views/BodyProView.swift:365-387` (`BodyProFutureUpdatesNote` with
  `BodyProFeatureCheckmark()`)
- **Description:** Carry-forward from archives 03/04 and `Issues.md` N6/N7,
  unchanged at v0.9.1: the Lifetime card shows a price and arrow button
  whose only effect is a footnote status message, and the "future updates"
  placeholder row trails the same gold checkmark as real unlocked
  features. The prior reports note this is intentionally deferred until
  IAP wiring exists; restated so it isn't lost.
- **Why it matters:** Reads as a real purchase surface until tapped;
  bounded blast radius (only reachable from Settings > Body Pro).
- **Suggested fix:** Unchanged from prior reports — disable the three
  buttons with a "Coming Soon" pill, or gate the stack behind a build
  flag; swap the placeholder row's checkmark for `sparkles` or nothing.
- **Risks / dependencies:**
  `testBodyProPageUsesCoinStyleSettingsEntryAndIconAssets` pins page
  strings; update its assertions with any copy change.

### N10. `HealthSummarySnapshot` decode is strict for `readiness` but tolerant for `activityRings`/`sleep`, so one bad readiness blob discards the whole cached dashboard

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift:352-372`
  (`init(from:)` — `(try? container.decodeIfPresent(...))` for
  `activityRings` and `sleep`, plain `try` for `readiness` and the metric
  fields), `Body/Models/Readiness/ReadinessModels.swift:8-14`
  (`ReadinessStatus` / `ReadinessConfidence` / driver `String` raw-value
  enums embedded in the persisted summary)
- **Description:** A `ReadinessSummary` that fails to decode (e.g. a
  future rename/removal of a `ReadinessStatus`, `ReadinessComponentKind`,
  or `ReadinessDriverKind` case — these enums are persisted by raw value
  inside the dashboard snapshot) throws out of
  `HealthSummarySnapshot.init(from:)`, which fails
  `HealthDashboardSnapshot` decoding entirely, and
  `HealthDashboardSnapshotStore.loadOrEmpty()` falls back to an empty
  dashboard — losing all cached metrics until the next full refresh. The
  same corruption in the `sleep` field degrades to an empty sleep summary
  only. The new `schemaVersion` field makes a deliberate migration
  possible, but accidental case removal would still nuke the cache.
- **Why it matters:** Cold launch after such an update shows an empty
  dashboard instead of cached values (recoverable by refresh — annoying,
  not data loss, since HealthKit remains the source of truth).
- **Suggested fix:** Either wrap `readiness` in the same
  `(try? decodeIfPresent) ?? .unavailable` shape as its siblings, or keep
  it strict deliberately and add a comment + a test asserting that enum
  cases in persisted readiness types are append-only.
- **Risks / dependencies:** None today; the enums have only ever grown.

### N11. Cumulative metric summaries fall back to yesterday's total under a "Current" header when today has no samples yet

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitFetchEngine.swift:773-828`
  (`dailyCumulativeQuantitySummary` enumerates yesterday→tomorrow and
  keeps the last non-nil sum), `Body/Views/Health/BodyHealthMetricDetailView.swift:795`
  (header labels the value "Current")
- **Description:** Active Energy, Resting Energy, Exercise Minutes, Time
  In Daylight, and Steps summaries use a two-day statistics window and
  keep the **latest** day that has any sum. When today has no samples yet
  (shortly after midnight; or a daylight/steps source that hasn't synced
  today), the Summary card and the detail "Current" header show
  yesterday's full-day total with no date qualifier — e.g. a Steps card
  reading 12,400 at 00:30. Once today's first sample lands, the value
  drops to today's small total. `Needs verification` on device: whether
  `HKStatisticsCollectionQuery` reports a nil `sumQuantity()` for a
  sample-less today (expected) — the fallback only engages in that case.
- **Why it matters:** A "Current" value that silently means "yesterday"
  overstates today's activity for a window every day and produces a
  confusing overnight drop. Mild, but it also feeds the widget
  `displayValues`, so the Home Screen card shows the same stale total.
- **Suggested fix:** Either restrict the summary to today's bucket
  (showing 0/“--” until data arrives — matches Apple's Fitness behavior),
  or keep the fallback but caption the value with its day ("Yesterday")
  by carrying the bucket date in `HealthMetricSummary`.
- **Risks / dependencies:** `HealthMetricSummary` is persisted
  (`value`-only Codable); adding a date field is a forward-compatible
  `decodeIfPresent` addition. Widget builder reads the same summary.

---

## 3. Code quality findings

- **Duplicated code:**
  - Skin-temperature baseline deviation logic exists twice and has already
    diverged in intent: `Body/Views/BodyHomeView.swift:101-128`
    (`wristTemperatureBaselineDeviationDisplay`) vs.
    `Body/Services/HealthWidgetSnapshotBuilder.swift:241-268`
    (`wristTemperatureDeviation`). Both compute a median over
    `lineChartCalendarPoints(to: .recentYear)`; N3's fix should collapse
    them into one shared helper.
  - Per-metric icon/color/title tables exist in five places —
    `BodyHomeView.metricCards` builders, `BodyHomeTrendCardFactory.configuration`
    (`Body/Views/Health/BodyHomeTrendCard.swift:258-441`),
    `BodyHomeCardKind` (`BodyAppearancePreference.swift:1321+`),
    `BodyHomeTrendCardKind` (`BodyAppearancePreference.swift:1074+`), and
    `HealthWidgetMetric` (`BodyShared/Models/HealthWidgetSnapshot.swift:60-106`).
    N1 is the direct cost of this duplication.
  - `HealthKitWorkoutStore.recentActivityRingMonthKeys` duplicates the
    engine's version (N6); the sibling `recentMonthKeys`
    (`HealthKitWorkoutStore.swift:1422-1438`) is live but nearly identical
    in shape.
  - `fetchHealthSummary` / `fetchHealthTrends`
    (`HealthKitFetchEngine.swift:1259-1681`) still repeat one
    `async let … fetchDashboardMetricIfNeeded` block per metric (~17 and
    ~25 respectively) — carry-forward observation from `Issues.md`.
- **Unused or outdated files / symbols:**
  - `HealthKitWorkoutStore.recentActivityRingMonthKeys` (N6;
    `grep -rn "recentActivityRingMonthKeys"` shows no caller).
  - `HealthWidgetSnapshotStore.delete()/exists()/fileSize(at:)` have zero
    production callers (`grep -rn "HealthWidgetSnapshotStore"`) — `delete`
    *should* gain a caller via N2; `exists` is genuinely unused.
- **Overly complex files or functions:**
  - `Body/Views/BodySettingsView.swift` — 2,784 lines; still bundles every
    Settings sheet. Same growth class the home view had before its split.
  - `Body/Services/HealthKitFetchEngine.swift` — 2,099 lines even after
    the six-extension split; the two orchestrators dominate.
  - `Body/Models/BodyAppearancePreference.swift` — 1,958 lines of
    preference enums + selections; mostly mechanical but houses four of
    the five duplicated metric tables.
  - The v0.5.6 hypertrophy findings on `BodyHomeView.swift` and
    `HealthSummarySnapshot.swift` are **resolved** by the splits.
- **Naming inconsistencies:**
  - `BodyHomeCardKind` vs. `BodyHomeTrendCardKind` remain two
    near-identical enums with duplicated `title`/`subtitle`/`iconName`/
    `tintColor` tables (carry-forward from `Issues.md`).
  - The `wristTemperature` identifier persists across models/engine while
    all user-facing copy now says "Skin Temperature" — consistent and
    deliberate (rename kept persistence keys stable), worth knowing when
    grepping.
- **Structural improvements:**
  - Introduce a single `HomeMetricSpec` table (kind → title, symbol,
    color, chart style, formatter) consumed by `metricCards`,
    `BodyHomeTrendCardFactory`, and `HealthWidgetMetric`'s app-side
    builder, so N1-class regressions become impossible by construction.
  - Give `HealthWidgetSnapshotStore` a `totalDiskSizeBytes` mirroring the
    other two stores and fold it into `cacheStatus` (pairs with N2).

---

## 4. Functional issues

- **N1 — Steps trend card icon:** flame instead of `figure.walk` on the
  Summary trends section and the Steps detail comparison card.
- **N2 — Clear Cache leaves health widgets populated:** the three new
  widgets re-render stale data immediately after the user clears the
  local cache.
- **N4 — concurrent refresh window:** double full refresh + early
  overlay dismissal when a second entry point fires during the
  authorization await. `Needs verification` on device.
- **N11 — "Current" shows yesterday's total** for cumulative metrics
  until today's first sample arrives. `Needs verification` against real
  HealthKit bucket behavior.
- **Prior-report verification:** all twelve `Issues.md` (v0.5.6) findings
  were re-checked: N1 (daylight icon) fixed at all three sites
  (`BodyHomeView.swift:429,1003`, detail model); N5 (per-month polling)
  fixed via `monthLoadContinuations`
  (`HealthKitWorkoutStore.swift:100-141`); N8 (schemaVersion) added to
  both snapshots; N9/N10 (source sheet `role: String`, sheet-wide lock)
  fixed with a typed `Role` enum and per-section locking
  (`BodySettingsView.swift:1433-1586`); N11 (`colorStops.last!`) gone (no
  force-unwraps repo-wide); N2/N3/N4 (file splits) done; N12 (TestPlan
  M13) fixed — M13 now lists Readiness (Beta). N6/N7 (Body Pro) remain →
  restated as N9 here.

---

## 5. UI/UX issues

- **N3 — Celsius deviation for Fahrenheit users** on the Skin Temp card,
  detail header, and small widget, while the chart annotation on the same
  detail page uses Fahrenheit.
- **N5 — small widget "--" card vs. medium widget empty state** for the
  same disabled metric.
- **N9 — Body Pro placeholder purchase surface** (deferred carry-forward).
- **Metric-card preview sizing keys off `UIScreen.main.bounds.width`**
  (`Body/Views/Health/BodyHealthMetricCard.swift:138,187,279,283`): on
  iPad Split View / Stage Manager the *screen* is ≥ 700 pt even when the
  app's window is iPhone-width, so cards pick the larger 5-day/50 pt
  preview in a compact window (and the reverse never happens). The new
  iPad layout otherwise sizes off the window. Low; needs a quick
  Stage Manager pass — replace with a `GeometryReader`/container-width
  driven value if it visibly crowds compact windows.
- **Sync-status copy nit:** `healthSyncStatusSummaryText` shows a bare
  timestamp (e.g. "Jun 9, 14:02") as the row value when authorized
  (`HealthKitWorkoutStore.swift:196-221`) — readable, but the row label is
  "Sync Status" and siblings show words ("Refreshing", "Denied"). Cosmetic
  only; flag if copy polish is planned.

---

## 6. Data and persistence issues

- **N2 — `healthWidgetSnapshot.json` survives Clear Cache** in the app
  group; also excluded from the cache-size readout.
- **N10 — uneven decode tolerance** in `HealthSummarySnapshot.init(from:)`
  makes the readiness blob a single point of failure for the cached
  dashboard.
- **Widget snapshot migration is well handled:** the tolerant
  `HealthWidgetMetricTrend` decoder keeps legacy `{primary, secondary}`
  caches readable and is covered by
  `BodyTests/HealthWidgetSnapshotMigrationTests.swift` (legacy decode +
  current round-trip).
- **`schemaVersion` now present** on `WorkoutMonthSnapshot` (`:57-63`) and
  `HealthDashboardSnapshot` (`HealthSummarySnapshot.swift:491-496`) —
  prior N8 resolved; decoders treat `nil` as baseline v0.
- **Secondary-selection signature** behavior unchanged since the prior
  audit (init clears `*Secondary` series on signature mismatch,
  `HealthKitWorkoutStore.swift:180-185`); the known caveat that the
  signature excludes the primary selection and combine flag still holds
  and is still masked by the immediate refresh both setters trigger.
- **Save-if-changed discipline** extends to the new store
  (`HealthWidgetSnapshotStore.save` byte-compares before writing and
  gates the widget reload on the result) — consistent with the other two.

---

## 7. Configuration and platform issues

- **Versions:** `MARKETING_VERSION = 0.9.1` / `CURRENT_PROJECT_VERSION = 2`
  in all six configurations (`body.xcodeproj/project.pbxproj:464-632`);
  pinned by `ProjectConfigurationTests.swift:928-941` and matched by
  README/VersionHistory.
- **HealthKit usage strings:** `NSHealthShareUsageDescription`
  (project.pbxproj:470) enumerates all 13 read categories and was updated
  for the "skin temperature" rename. `NSHealthUpdateUsageDescription`
  (line 471, "Body does not write data to Apple Health.") was added at
  v0.9.1; the app requests no share types
  (`engine.requestAuthorization` passes an empty share set), so the string
  is defensive only — harmless.
- **Entitlements:** app has HealthKit + app group; widget has the app
  group only (the stray Sign in with Apple entitlement was removed at
  0.9.1 build 2 per VersionHistory). App-group ID
  `group.com.zihengthedeveloper.Body` matches on both sides.
- **Privacy manifests:** present for both targets
  (`Body/PrivacyInfo.xcprivacy`, `BodyWidgetExtension/PrivacyInfo.xcprivacy`).
- **Deployment target:** `IPHONEOS_DEPLOYMENT_TARGET = 18.0` everywhere.
- **No issues found** in widget `Info.plist` (extension point only) or in
  the test-pinned config surface; nothing store-blocking surfaced.

---

## 8. Testing gaps

- **Highest-risk uncovered features:**
  - **Trend-card factory presentation (N1):** no test pins
    `BodyHomeTrendCardFactory`'s symbol names/colors against
    `BodyHomeTrendCardKind` — the exact gap that let `flame.fill` ship.
  - **`clearLocalCache` completeness (N2):** no test asserts that all
    three persisted stores are deleted; a snapshot-store test writing all
    three files and asserting removal would lock the contract.
  - **Unit-preference parity for derived values (N3):**
    `HealthWidgetSnapshotBuilder` has no unit tests for `displayValues` /
    `wristTemperatureDeviation`; a Fahrenheit-preference fixture would
    have caught the Celsius deviation.
  - **Refresh reentrancy (N4):** no test drives two concurrent
    `requestAuthorizationAndRefresh` callers; an injected-engine test
    that suspends authorization and asserts a single refresh pass would
    pin the fix.
  - **Widget empty states (N5):** nothing asserts the small widget's
    routing for `hasAnyData == false`.
- **Suggested tests:**
  - `ProjectConfigurationTests` assertion that the `.steps` configuration
    in `BodyHomeTrendCard.swift` contains `symbolName: "figure.walk"` (or,
    post-refactor, that the factory reads
    `BodyHomeTrendCardKind.iconName`).
  - A `HealthWidgetSnapshotBuilderTests` file: deviation sign/unit under
    Celsius and Fahrenheit preferences, sleep `displayValues` with score
    on/off, energy unit conversion of `averageText`.
  - Extend `HealthKitWorkoutStoreTests` with a clear-cache test using
    temporary file URLs for all three stores.
  - Manual cases to add to `TestPlan.md`: Clear Cache then check all five
    widgets (post-N2); Skin Temp card/detail/widget under Fahrenheit
    units (post-N3); Steps trend card icon (post-N1); update M4's "May
    2026" wording (N7). Device required for all HealthKit-backed cases.

---

## 9. Priority recommendations

- **Fix first:**
  - **N1** — one-line icon fix; user-visible on Summary and Steps detail
    every day.
  - **N2** — one call + one addend; "Clear Cache" currently doesn't do
    what it says wherever a health widget is installed.
  - **N3** — unit-correctness on three surfaces; pairs naturally with
    deduplicating the deviation helper.
- **Fix next:**
  - **N4** — move the `isRefreshing` flag ahead of the first await in the
    three entry points; verify the overlay contract on device.
  - **N5** — small-widget empty-state routing.
  - **N11** — decide the intended "Current" semantics for cumulative
    metrics and either scope to today or label the fallback.
- **Optional cleanup:**
  - **N6** — delete the dead store helper.
  - **N7** — refresh the README/TestPlan placeholder wording.
  - **N8** — fix the trend-widget header comment.
  - **N10** — align readiness decode tolerance (or document strictness).
  - **N9** — Body Pro placeholder polish whenever IAP work starts.

---

## What was checked

- App entry / layout: `Body/BodyApp.swift`, `Body/Views/MainTabView.swift`,
  `Body/Utils/AppLayout.swift` (full).
- Services (full): `HealthKitWorkoutStore.swift`,
  `HealthKitFetchEngine.swift` + all six extensions (`+Sleep`,
  `+TrainingLoad`, `+ActivityRings`, `+SourceOptions`, `+Secondary`,
  `+IntradaySamples`, `+SampleParsers`),
  `HealthDashboardSnapshotStore.swift`, `HealthWidgetSnapshotBuilder.swift`.
- Models (full): `HealthSummarySnapshot.swift`, `HealthTrend.swift`,
  `Sleep.swift`, `ActivityRings.swift`, `SourceComparison.swift`,
  `TrainingLoadCalculator.swift`, `Readiness/ReadinessModels.swift`,
  `Readiness/ReadinessScoreCalculator.swift`;
  `BodyAppearancePreference.swift` (targeted: permission/card/trend-card
  enums, icon tables, source-option identity, source-selectable kinds).
- Shared (full): `WorkoutMonthSnapshot.swift`, `WorkoutSummary.swift`
  (incl. `BodyValueFormat`), `WorkoutSnapshotStore.swift`,
  `HealthWidgetSnapshotStore.swift`, `HealthWidgetSnapshot.swift`, all
  five shared components.
- Widgets (full): all five widget files + bundle + `Info.plist`.
- Views: `BodyHomeView.swift` (full), `BodyHealthMetricDetailView.swift`
  (full), `BodyHealthMetricCard.swift` (full), `BodyHomeTrendCard.swift`
  (full), `BodyWorkoutsView.swift` (first 700 lines + targeted greps),
  `BodySettingsView.swift` (targeted: data tabs, source sheet
  `Role`/locking, cache sheet, sync status), `BodyProView.swift`
  (targeted carry-forward greps).
- Configuration: `Body/Body.entitlements`,
  `BodyWidgetExtension.entitlements`, privacy manifest presence,
  `project.pbxproj` (versions, usage strings, deployment target).
- Tests: `HealthWidgetSnapshotMigrationTests.swift` (full),
  `ProjectConfigurationTests.swift` (function index + version pins),
  test-function counts across all six files.
- Grep queries: `TODO|FIXME|HACK|XXX` (none); `Calendar.current` (none);
  `.last!|.first!|try!|as!|fatalError` (none);
  `recentActivityRingMonthKeys` (dead store copy);
  `HealthWidgetSnapshotStore` (no `delete` callers); `Task.sleep` (four
  legitimate uses: 15 s timeout, two UI delays, overlay minimum);
  `DispatchQueue` (three bounded UI delays); `UIScreen.main` (metric-card
  preview sizing); `.transition(` across `Charts/`; `flame.fill` /
  `figure.walk` icon cross-check; `NSHealth*` usage strings.
- Archive cross-reference: `Issues.md` (v0.5.6) N1–N12 verified
  individually; `docs/IssuesArchive-04.md` read in full;
  `Issues-gg.md` / `docs/Issues-ds.md` noted as parallel third-party
  audits (headers only).

## Not checked (worth a follow-up)

- Running the app or widgets on simulator/device. N3 (Fahrenheit
  rendering), N4 (refresh race timing), N5 (widget empty states), N11
  (HK empty-bucket behavior), and the `UIScreen.main` Split View sizing
  all need a device or simulator pass to confirm user-visible impact.
- Chart struct internals in `Body/Views/Health/Charts/*.swift` and
  `ChartHelpers.swift` — scanned for transition parity and force-unwraps
  only; their logic was last fully audited at v0.5.6 (`Issues.md`) before
  the mechanical split, and `git status`/log show no behavioral edits
  since beyond the split and the dot-rendering fix (commit 82bca0b).
- `BodyActivityRingsDetailView.swift`, `BodyMonthYearPicker.swift`,
  `BodyWorkoutListSheet.swift`, `SleepScoreSheet.swift`,
  `BodyHealthDataSourcePickerSheet.swift`, `BodyWorkoutsView.swift`
  lines 700+ (workout detail sheet/heart-rate chart) — unchanged areas,
  skimmed or skipped this run.
- `WorkoutMonthSnapshotTests.swift` (4,030 lines) — counted, not read.
- Settings "How to Use" guide copy vs. current feature set (would need a
  full `BodySettingsView` read).
- Readiness/sleep-score calibration against real HealthKit exports
  (heuristic weights carried forward from prior audits, still
  empirically unverified).
- Lock Screen / accessory widget families, HealthKit background
  delivery, localization beyond English (deferred per TestPlan §4).
