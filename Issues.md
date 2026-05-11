# Body — Issues Report

Audit of branch `codex/body-v0.1.0` on 2026-05-10. Read-only review; no code was
modified.

Severity legend: Critical (data loss / crash / store-blocking), High
(incorrect behavior or significant UX regression under normal use), Medium
(bug or hygiene risk under specific conditions), Low (quality, performance,
or maintainability delta).

---

## 1. Project review summary

Body v0.1.0 is in a coherent first-release shape: app shell, HealthKit
ingestion, shared models, calendar/breakdown components, two widgets, and
configuration tests are all in place and internally consistent. The most
load-bearing risks are concentrated in `HealthKitWorkoutStore`: post-prompt
authorization is treated as success regardless of the user's actual choice,
concurrent month loads can drop in-flight snapshot updates, and the sleep
aggregation sums overlapping samples in a way that can inflate totals when
more than one source logs sleep. UI quality is solid; the most visible gaps
are unit assumptions (kg / km / mL·kg⁻¹·min⁻¹) that ignore the user's
locale, and a small set of inconsistent labels/dead code. Tests cover the
big-shape behaviors well; widget reload behavior and the auth-state finite
state machine are not exercised. Areas reviewed: app entry/scene phase,
HealthKit ingestion and authorization, workout summary aggregation, snapshot
persistence, charts/calendar/breakdown rendering, month-year carousel,
settings/appearance, widgets (both kinds), entitlements, Info.plist
keys, privacy manifests, project build settings, and unit tests.
Intentionally not reviewed: rendered runtime behavior on device (no build
in this run), asset catalog binary contents (PNG sizes only), and the
Xcode workspace shared scheme XML.

---

## 2. Issue list

### N1. HealthKit refresh treats prompt completion as authorization

- **Severity:** High
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:55-72`,
  `Body/Services/HealthKitWorkoutStore.swift:284-296`
- **Description:** `requestAuthorization()` resolves successfully whenever
  `HKHealthStore.requestAuthorization(toShare:read:)` reports `success =
  true`, which Apple does *whenever the user dismisses the prompt* — denials
  included. The fallback `HealthKitWorkoutError.authorizationDenied` branch
  is therefore unreachable in practice, and the calling site immediately
  sets `authorizationState = .authorized` and proceeds to query.
- **Why it matters:** Users who deny part or all of the read scopes still
  see `authorizationState == .authorized`; every card and calendar shows
  empty data ("--") with no in-app explanation or follow-up CTA. There is
  no path to recover other than going into the
  system Settings, and the app gives no hint that this is required. This
  is the most user-affecting bug in the current build.
- **Suggested fix:** After the prompt resolves, call
  `healthStore.statusForAuthorizationRequest(toShare:read:)` (or rely on
  observed query results being empty) to classify the result as
  `shouldRequest`, `unnecessary`, or `unknown`, and surface a non-blocking
  banner on Home when reads return empty for types the user previously
  authorized. Even a basic "We didn't see any data — open Health Settings"
  CTA would close the loop.
- **Risks / dependencies:** `statusForAuthorizationRequest` is itself an
  imperfect signal (Apple intentionally returns "unnecessary" when authorized
  *or denied*). The UX needs to handle the "authorized but no samples"
  state alongside the "denied" state without being noisy on real
  empty-data accounts.

### N2. Concurrent month loads can overwrite each other's snapshots

- **Severity:** Medium
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:200-245`,
  `Body/Services/HealthKitWorkoutStore.swift:104-150`
- **Description:** `refresh(monthKeys:calendar:)` reads `monthSnapshots`
  into a local `var nextSnapshots`, awaits one or more `fetchWorkouts(...)`
  calls, then assigns the whole dictionary back to `monthSnapshots`. The
  class is `@MainActor`-bound, but `await` boundaries allow another call
  (e.g. `loadMonthIfNeeded` driven by the month carousel) to start before
  the first completes. Both invocations capture the same baseline snapshot
  dictionary; the one that finishes last wins and silently loses any keys
  the other added. `loadingMonthKeys` prevents the *same* key from being
  fetched twice but does not coordinate writes across different keys.
- **Why it matters:** A realistic sequence — `loadRecentWorkoutMonthsIfNeeded`
  fires from `.task` on Charts, the user immediately scrolls the month
  carousel to a fourth month, `loadMonthIfNeeded` starts and finishes after
  the recent-month batch — will leave `monthSnapshots` containing only the
  fourth month. The widget snapshot (current month) is unaffected because
  it round-trips through shared `UserDefaults` separately, but the Charts
  tab's other-month state silently disappears until the next refresh.
- **Suggested fix:** Re-read `monthSnapshots` inside the loop after each
  `await`, e.g. `monthSnapshots[key] = WorkoutMonthSnapshot.make(...)` per
  iteration instead of accumulating in a local copy and writing once.
  Alternative: serialize all month loads behind a single actor task using
  `AsyncStream` or a `Task` queue.
- **Risks / dependencies:** Touch must preserve the existing test
  `testWorkoutStoreKeepsRecentChartWindowToThreeMonths`. Behavior change
  is invisible in normal flows; verify by triggering recent-month load and
  a manual month tap nearly simultaneously.

### N3. Sleep duration sums overlapping samples without merging

- **Severity:** Medium
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:424-476`
- **Description:** `fetchSleepSummary` filters the most recent 14 days of
  sleep-analysis samples to those classified `asleep*`, then sums
  `endDate - startDate` across every sample in the 18-hour window before
  the latest end. If two sources (e.g. Apple Watch + iPhone "in bed" +
  AutoSleep) report overlapping intervals — or if a single source emits
  fine-grained core/REM/deep segments that overlap a coarser asleep
  envelope — the same time is counted multiple times.
- **Why it matters:** A real eight-hour night with the Watch logging
  asleep + core + deep + REM stages can compute to fifteen-plus hours.
  The Home card then renders something like "15h 12m", which is
  immediately wrong to any user and undermines confidence in the whole
  dashboard.
- **Suggested fix:** Before summing, either (a) merge overlapping intervals
  into a disjoint set and sum the merged lengths, or (b) restrict the
  aggregation to a single chosen source (prefer the source already used
  for the "main" sample). Option (a) is more correct; option (b) is
  simpler. Pair this with a unit test that builds overlapping
  `HKCategorySample` mocks and asserts the merged total.
- **Risks / dependencies:** Sleep stage encoding varies by iOS version
  (`asleepCore` / `asleepDeep` / `asleepREM` post-iOS 16). Merging across
  stages should keep stage information intact if a future card surfaces
  it.

### N4. Health card units are hardcoded to a single locale

- **Severity:** Medium
- **Related files:** `Body/Views/BodyHomeView.swift:65-128`,
  `Body/Views/BodyChartsView.swift:443-454`
- **Description:** Weight is fetched from HealthKit in kilograms and
  rendered with a hardcoded `"kg"` unit; distance is divided by 1000 and
  rendered as `" km"`; VO2 max as `"mL/kg/min"`; energy as `"kcal"`. The
  app does not consult `HKHealthStore.preferredUnits(for:)` or the user's
  `Locale.current.measurementSystem`. A US-locale device shows kg / km
  even though Health itself displays lb / mi.
- **Why it matters:** First impression on a US (imperial) device is that
  the dashboard is mis-numbered — 69.3 kg vs. 152.8 lb, 5.2 km vs. 3.2 mi.
  The other cards (`bpm`, `%`, `ms`) are locale-neutral, which makes the
  metric outliers more jarring rather than less.
- **Suggested fix:** Request preferred units from `HKHealthStore` once
  authorization completes and convert at render time using `Measurement<
  UnitMass>` / `UnitLength` / `UnitEnergy`, formatted with `.measurement(
  width: .abbreviated, usage: .personWeight / .road / .workout)`. Cache
  the units to avoid repeated calls.
- **Risks / dependencies:** Adds a small async call to the auth flow.
  Tests should pin both metric and imperial outputs against fixed samples.

### N5. `BodyWidgetBackground` shared enum is dead code

- **Severity:** Low
- **Related files:** `BodyShared/Components/BodyWidgetBackground.swift:1-37`
- **Description:** The shared `BodyWidgetBackground` enum exposes
  `gradient` and `chartGradient(for:)`. Nothing references either. The
  widget uses `BodyWidgetBackgroundSelection` (a separate type declared
  inside `WorkoutCalendarWidget.swift`) plus `.containerBackground(...)`;
  in-app chart panels moved to a solid Coin-style card background
  (`BodyChartsCardBackgroundModifier`).
- **Why it matters:** The file claims to be a shared building block but
  is no longer wired in. Grep confirms zero call sites:
  `rg BodyWidgetBackground` returns only the declaration itself plus the
  unrelated `BodyWidgetBackgroundSelection`. Keeping it costs future
  readers a re-derivation.
- **Suggested fix:** Delete `BodyShared/Components/BodyWidgetBackground.swift`.
  No imports follow.
- **Risks / dependencies:** None observed. Confirm with `rg` after the
  delete that no callers remain.

### N6. `leadingBlankDayCount` ternary has no effect

- **Severity:** Low
- **Related files:** `BodyShared/Models/WorkoutMonthSnapshot.swift:103-107`
- **Description:** `let sundayBasedWeekday = firstWeekday == 1 ? 1 :
  firstWeekday` always evaluates to `firstWeekday`. Both branches return
  the same value, so the expression reduces to `firstWeekday - 1`. The
  current Sunday-first calendar makes this correct, but the dead ternary
  hides the assumption.
- **Why it matters:** Anyone changing `Calendar.bodyGregorian.firstWeekday`
  later will see code that *looks* like it adapts but doesn't. The next
  reader has to reverse-engineer the no-op before trusting the function.
- **Suggested fix:** Replace with `return (firstWeekday - calendar
  .firstWeekday + 7) % 7` using the same calendar that builds the
  snapshot, and pass that calendar through (it's already available on
  `Self`). Add a Monday-first regression test if the calendar ever
  becomes locale-driven.
- **Risks / dependencies:** Must not change behavior for the existing
  `testMonthSnapshotBuildsSundayFirstCalendarDays` assertion (5 leading
  blanks for May 2026).

### N7. Calendar widget view branches on a family it can never receive

- **Severity:** Low
- **Related files:** `BodyWidgetExtension/WorkoutCalendarWidget.swift:78-95`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift:116-128`
- **Description:** `BodyWorkoutCalendarWidget` declares
  `.supportedFamilies([.systemLarge])` only, but `WorkoutCalendarWidgetView`
  ternaries on `family == .systemLarge ? .widgetLarge : .widgetMedium` —
  the medium branch is unreachable. Padding flips on the same dead
  predicate.
- **Why it matters:** Dead branches encourage stale styling assumptions.
  When someone later adds `.systemMedium` to the calendar widget, the
  branch already "supports" it but with untested 16-pt padding and a
  shared-component style that hasn't been visually proofed.
- **Suggested fix:** Hardcode `.widgetLarge` and `14` padding in
  `WorkoutCalendarWidgetView` until medium is intentionally enabled,
  then design the medium variant on purpose.
- **Risks / dependencies:** Trivial; affects only the calendar widget.

### N8. Theme picker and accent picker swap headline vs. subtitle

- **Severity:** Low
- **Related files:** `Body/Views/BodySettingsView.swift:240-247`,
  `Body/Views/BodySettingsView.swift:289-296`
- **Description:** The theme tile passes `title: theme.displayName` ("System")
  and `subtitle: theme.selectionSubtitle` ("Auto"). The accent tile passes
  `title: accent.selectionSubtitle` ("Classic") and `subtitle:
  accent.displayName` ("Blue"). Two structurally identical pickers display
  the same model field in opposite slots.
- **Why it matters:** Visually one picker labels by canonical name ("System
  / Auto"), the other by descriptor ("Classic / Blue"). It reads as
  inconsistent UX and is easy to miscopy when a third picker is added.
- **Suggested fix:** Pick one convention. Most natural is canonical name
  on top ("Blue / Classic"), which matches the theme picker and the
  settings row value rendering (`currentAccent.displayName` is the row's
  value text on line 71).
- **Risks / dependencies:** Both pickers route through `BodySymbolSelectionTile`;
  no model changes needed.

### N9. `BodyAppIconOption.title` / `subtitle` are inverted relative to UX

- **Severity:** Low
- **Related files:** `Body/Views/BodySettingsView.swift:369-410`,
  `Body/Views/BodySettingsView.swift:579-593`,
  `Body/Views/BodySettingsView.swift:86`
- **Description:** `BodyAppIconOption` declares `title = "Original"` and
  `subtitle = "Classic"` for the default icon, yet both the settings row
  (`currentAppIconOption.subtitle`) and the picker tile (`Text(option
  .subtitle)` styled as headline) show `subtitle` as the primary label.
  Internal naming reads upside down: the field called `title` is
  consistently displayed as a secondary line and the field called
  `subtitle` is the headline.
- **Why it matters:** Editing this struct correctly requires reverse-reading
  the property names. A reasonable rename (e.g. `displayName` /
  `descriptor`) would remove the mental flip.
- **Suggested fix:** Rename properties to match their display roles, or
  swap the assigned strings so `title` becomes the headline and
  `subtitle` the descriptor. The on-screen output should stay identical.
- **Risks / dependencies:** Pure naming refactor; touch all three sites
  in `BodySettingsView.swift`.

### N10. Charts section title "By Type" diverges from feature name

- **Severity:** Low
- **Related files:** `Body/Views/BodyChartsView.swift:53`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift:110`,
  `README.md:13`, `TestPlan.md:44`
- **Description:** README and TestPlan refer to the workout-types feature
  as "Workout Types" and the widget's `configurationDisplayName` is
  "Workout Types", but the in-app Charts header reads "By Type". The
  earlier Charts header above is "Workout Calendar" — matching across
  surfaces.
- **Why it matters:** Inconsistent labeling reduces the feeling that the
  widget and the Charts tab are the same feature.
- **Suggested fix:** Change the Charts section title to "Workout Types"
  (or update README/TestPlan/widget if "By Type" is the intended brand).
- **Risks / dependencies:** Section name change only; no test depends on
  the literal "By Type".

### N11. `HealthMetricSummary.previousValue` / `sourceName` / `date` are populated but never read

- **Severity:** Low
- **Related files:** `Body/Models/HealthSummarySnapshot.swift:53-58`,
  `Body/Services/HealthKitWorkoutStore.swift:381-422`,
  `Body/Views/BodyHomeView.swift:136-162`
- **Description:** Every metric fetch reads two samples and stores
  `previousValue`, `sourceName`, and `date` on `HealthMetricSummary`, plus
  `sourceName`/`startDate`/`endDate` on `SleepSummary`. The Home cards
  only render `value` (and the formatted sleep duration). The other
  fields are wired through the store and the model but never displayed,
  per the simplification noted in VersionHistory ("removed range bars and
  non-functional navigation cues").
- **Why it matters:** Reading two samples per metric instead of one is a
  small but pointless HealthKit query cost (every sync, every metric).
  More importantly, the model carries fields that imply UI affordances
  that no longer exist; future contributors will reasonably assume those
  fields are surfaced somewhere.
- **Suggested fix:** Drop `previousValue`/`sourceName`/`date` from
  `HealthMetricSummary` and the matching extras from `SleepSummary`,
  and change `latestQuantity`'s sample limit to `1`. If the fields are
  intentionally being held for a near-term feature, leave a single
  one-line `// reserved for trend display` comment.
- **Risks / dependencies:** Watch for re-encoded health-summary fixtures
  in any future test.

### N12. `WorkoutSnapshotStore.save` silently drops JSON encoding errors

- **Severity:** Low
- **Related files:** `BodyShared/Services/WorkoutSnapshotStore.swift:26-29`
- **Description:** `save` uses `try?` on `JSONEncoder().encode(snapshot)`.
  A failure (extremely unlikely for the current shape, but possible if the
  model gains a non-Codable property) results in *no widget update at all*
  with no log or breadcrumb.
- **Why it matters:** Diagnosing a stuck widget would require setting a
  breakpoint inside the silent path. Cheap insurance to log the error
  via `os.Logger`.
- **Suggested fix:** Replace `try?` with `do { ... } catch { Logger
  .subsystem.error("Snapshot encode failed: \(error)") }`. Same treatment
  for `JSONDecoder().decode(...)` in `load`.
- **Risks / dependencies:** None.

### N13. Calendar cells lack accessibility labels and hints

- **Severity:** Low
- **Related files:** `BodyShared/Components/WorkoutCalendarView.swift:73-119`
- **Description:** Each calendar day tile only contains glyph + marker
  imagery. No `accessibilityLabel` describes the day number, workout
  count, or primary workout type, and no `accessibilityHint` indicates
  that tapping opens a sheet (in-app) or that the tile is decorative
  (widget). VoiceOver users hear concatenated symbol descriptions.
- **Why it matters:** Workouts are personal-health data; an
  inaccessible calendar excludes users who rely on VoiceOver/Switch
  Control. Apple's review explicitly looks for accessibility in
  Health-category apps.
- **Suggested fix:** On the cell, add `.accessibilityElement(children:
  .ignore)` and `.accessibilityLabel("\(day) — \(count) workouts,
  \(primaryWorkoutType?.displayName ?? \"no workouts\")")`, plus
  `.accessibilityHint("Open workouts for this day")` when
  `onSelectDay != nil`. Mark inactive days as elements too, with just
  the date label.
- **Risks / dependencies:** Localization will eventually replace the
  literal strings. Test with VoiceOver enabled.

### N14. `handleRefreshError` mislabels first failure as `.denied`

- **Severity:** Low
- **Related files:** `Body/Services/HealthKitWorkoutStore.swift:258-264`
- **Description:** When `authorizationState == .unknown` and a refresh
  throws (e.g. a transient HealthKit failure), the state transitions to
  `.denied`. Otherwise it becomes `.failed(error.localizedDescription)`.
  But "unknown + error" really means "we never confirmed authorization
  and an error occurred" — that's not denied.
- **Why it matters:** Today the path is rarely exercised because
  `requestAuthorizationAndRefresh` sets `.authorized` before refreshing,
  but `loadMonthKeysIfNeeded` can run with `.unknown` state (no prior
  call) and any throw immediately classifies the user as denied. That
  mislabeling later misroutes any UX built on top of `.denied`.
- **Suggested fix:** Always set `.failed(...)` when an error occurs;
  reserve `.denied` for an explicit denial signal (post-prompt
  `statusForAuthorizationRequest` returning `shouldRequest`).
- **Risks / dependencies:** Pairs naturally with N1.

### N15. `ProjectConfigurationTests` widget-family test name implies broader coverage than it asserts

- **Severity:** Low
- **Related files:** `BodyTests/ProjectConfigurationTests.swift:83-95`
- **Description:** `testWorkoutTypeWidgetSupportsMediumAndLargeFamilies`
  string-matches the entire widget source. It happens to pass while the
  calendar widget supports only large, because the substring
  `.supportedFamilies([.systemMedium, .systemLarge])` exists *somewhere*
  in the file (the breakdown widget). The test is named as if both
  widgets had family expectations.
- **Why it matters:** A future change that accidentally removes the
  breakdown widget's family list while keeping the calendar widget's
  `.supportedFamilies([.systemLarge])` would still pass the substring
  test if it happens to match elsewhere. The test does not pin which
  widget supports which families.
- **Suggested fix:** Parse the file by widget struct name (or split the
  widgets across files) and assert family lists per widget. Simpler:
  add an assertion that `.supportedFamilies([.systemLarge])` appears
  exactly once (for the calendar widget) and the medium+large literal
  appears exactly once (for the breakdown widget).
- **Risks / dependencies:** Test-only change.

### N16. `BodyMonthYearPicker.monthYearListCache` is static mutable state with no eviction

- **Severity:** Low
- **Related files:** `Body/Views/BodyMonthYearPicker.swift:33-37,53,151-186`
- **Description:** `private static var monthYearListCache: [BodyMonthYearListCacheKey:
  [BodyMonthYear]]` accumulates a fresh entry per
  (current month, current year, requested count). Entries are never
  evicted. Concurrent access is safe today because all `View` body
  evaluation happens on the main thread, but the cache shape encourages
  treating it as a generic memoization that could be called from
  background contexts.
- **Why it matters:** The cache is bounded by distinct (month, year,
  count) triples, so practical growth is tiny. The reason to flag it is
  shape: a `static var` mutable dictionary without `@MainActor` and
  without explicit eviction is the kind of pattern that quietly grows
  unsafe as the file is touched later.
- **Suggested fix:** Either annotate the type as `@MainActor` (force
  main-thread access), or replace with a same-shape instance-level cache
  on the `View` (one entry per view lifetime is sufficient).
- **Risks / dependencies:** None observed at current call sites.

---

## 3. Code quality findings

- **Duplicated code:**
  - `durationText(for:)` formatter is reimplemented in
    `Body/Views/BodyChartsView.swift:429-441` and
    `BodyShared/Components/WorkoutTypeBreakdownView.swift:160-172`. Same
    "Xh Ym / Xh / Ym" logic. Consolidate in a shared file (BodyShared)
    used by both.
  - Card background modifiers are near-identical across
    `Body/Views/BodyHomeView.swift:241-262`,
    `Body/Views/BodyChartsView.swift:401-427`, and
    `Body/Views/BodySettingsView.swift:651-677`. Same corner radius / fill
    / shadow / overlay logic with one different cornerRadius. Extract one
    `BodyCardBackgroundModifier(cornerRadius:)` for all three.
  - Hardcoded "workout" / "workouts" pluralization at
    `Body/Views/BodyChartsView.swift:194` and
    `BodyShared/Components/WorkoutTypeBreakdownView.swift:156`.
- **Unused or outdated files / symbols:**
  - `BodyShared/Components/BodyWidgetBackground.swift:1-37` — entire file
    is unreferenced (`rg BodyWidgetBackground` finds only the
    declaration and the unrelated `BodyWidgetBackgroundSelection`). See
    N5.
  - `HealthMetricSummary.previousValue` / `.sourceName` / `.date` and
    `SleepSummary.startDate` / `.endDate` / `.sourceName` populated but
    not displayed. See N11.
- **Overly complex files or functions:**
  - `Body/Views/BodySettingsView.swift` (682 lines) bundles five sheets,
    seven private view types, and three styling modifiers. Splitting per
    sheet (theme / accent / icon / copyright) would shrink the file by
    half and isolate icon-change side effects.
  - `Body/Services/HealthKitWorkoutStore.swift:518-689` workout-type
    raw-value switch is mechanical but very long; the table-driven form
    (`[Int: BodyWorkoutType]`) is more compact and trivial to keep in
    sync.
- **Naming inconsistencies:**
  - `BodyAppIconOption.title` / `.subtitle` semantically inverted versus
    UI (N9).
  - `BodyAppTheme.selectionSubtitle` vs `BodyAppAccent.selectionSubtitle`
    used as opposite layout slots (N8).
  - `BodyWidgetBackground` (shared enum, unused) vs
    `BodyWidgetBackgroundSelection` (widget extension enum, used) —
    nearly identical names with no relationship.
- **Structural improvements:**
  - `HealthKitWorkoutStore` would benefit from extracting the HealthKit
    query plumbing into a `HealthKitProbing` protocol so the
    auth/refresh state machine and the workout-type mapping can be tested
    without a real `HKHealthStore`.

---

## 4. Functional issues

- **HealthKit authorization (N1).** After the prompt completes the app
  reports authorized regardless of the user's actual choice. Empty home
  cards and empty calendar are indistinguishable from "no data" vs
  "denied". Pull-to-refresh shows no dedicated error state.
- **Concurrent month loads (N2).** Fast scrolling through the month
  carousel while the recent-months batch is still in flight can leave
  the chart with only the most recently fetched month populated.
- **Sleep inflation (N3).** Multi-source / multi-stage sleep input can
  produce visibly impossible durations on the Home Sleep card.
- **Locale (N4).** Imperial-locale users see metric units throughout
  Home and Charts.
- **Charts month-year picker.** `BodyMonthYearPicker` declines to keep a
  selection if the requested month is future (`allowFutureMonths = false`,
  `isFuture` checks against device clock). If a user's device clock is
  ahead of real time and they pick an "already-current" month, the
  picker may bounce them back. Low probability.
- **App icon change.** `UIApplication.setAlternateIconName` callback
  posts results via `DispatchQueue.main.async` from inside a private
  callback — fine, but does not invalidate `@AppStorage` or any picker
  state. After change, returning to the picker should reflect the new
  selection — it does, via `selectedAppIconName` `onAppear` refresh,
  but only on `onAppear`. If the user changes the icon then opens
  another sheet without dismissing first, the displayed selection may
  briefly mismatch the system.

---

## 5. UI/UX issues

- **Charts section title** "By Type" diverges from the widget /
  README / TestPlan name "Workout Types" (N10).
- **Theme vs Accent picker inconsistency** (N8) — visually subtle but
  breaks the rhythm of the appearance section.
- **VO2 Max card** uses `"mL/kg/min"` as a unit string — at large
  Dynamic Type sizes the card has a 0.6 minimumScaleFactor and `lineLimit(1)`
  on both the value and the unit, so values shrink heavily before
  wrapping. Acceptable but worth eyeballing.
- **Calendar inactive-day color** uses `Color.primary.opacity(0.1)` on
  the rounded rectangle plus secondary-foreground text. In dark mode
  against `.secondarySystemBackground` panel, the contrast ratio is
  near WCAG AA threshold for body text. Consider raising to
  `Color.primary.opacity(0.14)` in dark mode.
- **Charts month-picker tap zones** at the left/right 34% overlap the
  neighbor month carousel item visually. Tapping the visible
  "previous-month" text triggers the explicit prev/next button (because
  the zone overlay wins) instead of feeling like a direct touch on the
  text. Acceptable but worth deciding intentionally.
- **No empty/error state when HealthKit data is empty after auth.**
  Home shows a grid of "--" cards with no banner. Charts shows an empty
  calendar with the placeholder month if no real data has arrived. A
  one-line Home banner would clarify the state.
- **Workout list sheet** dynamically reformats date as
  `.dateTime.weekday(.wide).month(.wide).day()` — good. Sheet title
  truncates with `lineLimit(1)` and `minimumScaleFactor(0.75)` on
  Wednesday-style long days. Acceptable.

---

## 6. Data and persistence issues

- **Race during concurrent month loads (N2)** can drop newly fetched
  month snapshots from the in-memory `monthSnapshots` dictionary. The
  shared-defaults persisted snapshot (current month only) is unaffected,
  but the Charts tab silently loses other-month data until the next
  load.
- **Silent encode/decode failures (N12)** in `WorkoutSnapshotStore`
  leave the widget on stale data without any signal.
- **No schema version on `WorkoutMonthSnapshot`.** A new app version that
  removes a `BodyWorkoutType` enum case would fail to decode an older
  snapshot at the widget (the widget falls back to placeholder via
  `loadOrPlaceholder`). New enum cases are tolerated because `BodyWorkoutType`
  is a string raw-value Codable — unknown raw strings fail to decode
  the *entire* snapshot, not just one case. This is a foot-gun.
  Consider per-day `try?` decoding, or storing only raw-string types in
  the snapshot and resolving to `BodyWorkoutType` at the consumer.
- **Widget reload on snapshot change.** `updateCurrentMonthSnapshot`
  calls `WidgetCenter.shared.reloadAllTimelines()` only when the
  *current* month is updated. If a user looking at a widget right after
  a workout sees the widget refresh; but if a non-current month update
  happens to invalidate state (won't, in this app), the widget would
  miss it. Currently fine.
- **App group container fall-through.** `WorkoutSnapshotStore
  .sharedUserDefaults` returns `nil` when the container URL is
  unavailable (previews, mis-signed debug runs). Subsequent `save` /
  `load` are silent no-ops. Worth a `Logger.error` here too, scoped
  to non-preview builds.

---

## 7. Configuration and platform issues

- **`NSHealthShareUsageDescription`** present in
  `body.xcodeproj/project.pbxproj` for both Debug and Release.
  `NSHealthUpdateUsageDescription` is absent — correct, since
  `requestAuthorization(toShare: [])` requests no write scopes.
- **App group identifier** `group.com.zihengthedeveloper.Body` matches
  in `Body/Body.entitlements`, `BodyWidgetExtension.entitlements`, and
  `BodyShared/Services/WorkoutSnapshotStore.swift:9`. Tests verify
  entitlement parity (`testAppAndWidgetShareAppGroupEntitlement`).
- **Privacy manifests** declare `NSPrivacyAccessedAPICategoryUserDefaults`
  with reason `CA92.1` and `NSPrivacyTracking = false` on both app and
  widget. Good.
- **Deployment target** `IPHONEOS_DEPLOYMENT_TARGET = 18.0` for all four
  configurations. `AppIntentTimelineProvider` requires iOS 17+, so fine.
- **`SUPPORTS_MACCATALYST = NO`** and `TARGETED_DEVICE_FAMILY = 1`
  iPhone-only — matches README's "iOS 18.0+" claim.
- **Widget target** is `APPLICATION_EXTENSION_API_ONLY = YES`. Good.
- **`Body02 BodyPink BodyWhite`** listed in
  `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; matches the four
  options in `BodyAppIconOption.all` (one primary + three alternates).
- **Initial `git` state** is a single commit with everything else
  untracked. Worth landing the v0.1.0 source in tracked history before
  any audit work continues.

---

## 8. Testing gaps

- **Highest-risk uncovered features:**
  - HealthKit authorization state machine (N1, N14) — no tests because
    `HKHealthStore` is hard to fake.
  - Concurrent month load race (N2) — no integration test asserts
    `monthSnapshots` preserves both keys after overlapping calls.
  - Sleep aggregation merging (N3) — no test builds overlapping
    `HKCategorySample` mocks.
  - Widget timeline reload — the widget reads `loadOrPlaceholder` but no
    test verifies that `WidgetCenter.shared.reloadAllTimelines` is
    triggered after a snapshot save.
  - Locale-aware unit formatting (N4) — no test covers preferred-unit
    output.
- **Suggested tests:**
  - `HealthKitWorkoutStoreTests`: introduce a `HealthKitProbing`
    protocol seam (see Code Quality / Structural). Then add
    `testRefreshDoesNotDropConcurrentMonthSnapshots` driving two
    overlapping refreshes against in-memory fixtures.
  - `WorkoutMonthSnapshotTests`: add `testWorkoutTypeBreakdownTieBreaksByDisplayPriority`
    using two types with identical totals.
  - `HealthKitWorkoutStoreTests`: cover raw values 81 (gap → `.other`)
    and any newly added Apple HKWorkoutActivityType raw values above 84
    as they appear in OS updates.
  - `ProjectConfigurationTests`: pin per-widget supported families
    explicitly (see N15).
  - Manual / on-device:
    - VoiceOver pass over Charts calendar.
    - Imperial-locale device check that weight / distance render in
      imperial units (currently they will not — see N4).
    - Multi-source sleep night to validate N3.
    - Run `xcodebuild test -destination 'platform=iOS Simulator,
      name=iPhone 17 Pro'` per LessonsLearned 2026-05-10 (current
      machine has 17 Pro, not 16 Pro).

---

## 9. Priority recommendations

- **Fix first:**
  - N1 — authorization is the user-facing show-stopper; everything else
    can wait until users can trust the dashboard reflects their real
    permission state.
  - N2 — silent data loss is hard to reproduce and erodes the value of
    historical month browsing introduced in v0.1.0.
  - N3 — visibly wrong sleep totals will be the first thing reviewers
    notice on a real multi-source account.
  - N4 — imperial-locale users get wrong-feeling numbers on a fresh
    install; cheap to address before launch.
- **Fix next:**
  - N11 — drop unused metric fields and reduce per-metric HK reads.
  - N12 — log encode/decode failures so production silence becomes
    investigable.
  - N13 — accessibility coverage for the calendar before submission.
- **Optional cleanup:**
  - N5, N6, N7, N8, N9, N10, N14, N15, N16 — quality / consistency
    items; safe to bundle into a "v0.1.1 polish" branch.

---

## 10. Fix pass completed on 2026-05-10

All named issues above were addressed in the app code in this pass.

- **N1 — HealthKit prompt completion vs. authorization:** `HealthKitWorkoutStore` now checks `statusForAuthorizationRequest(toShare:read:)` before/after requesting HealthKit access, reserves `.denied` for an explicit denied signal, and exposes a Home notice when no Apple Health data is found after sync so "no data" is not silent.
- **N2 — Concurrent month snapshots:** month refresh now writes each fetched snapshot directly back into `monthSnapshots` after its `await`, and marks each month loaded individually instead of assigning a stale dictionary copy at the end.
- **N3 — Sleep overlaps:** sleep samples are merged into disjoint intervals before duration is summed, preventing overlapping stage/source samples from inflating the Sleep card. Added a regression test for overlapping intervals.
- **N4 — Locale units:** Home weight and workout-list distance now format through `BodyValueFormat`, using pounds/miles for US locale and kg/km elsewhere. Settings also offers System, Metric, and Imperial unit choices that override locale. Duration, energy, and count formatting were centralized in the same formatter.
- **N5 — Dead widget background enum:** removed the unused shared `BodyWidgetBackground.swift`; only the active widget background selection remains in the widget extension.
- **N6 — Leading blanks:** replaced the no-op Sunday ternary with a calendar-relative leading-blank formula that preserves the current Sunday-first behavior.
- **N7 — Calendar widget dead medium branch:** the calendar widget view now hardcodes the only supported large style and 14 pt padding.
- **N8 — Theme/accent picker consistency:** the accent picker now matches the theme picker convention, with canonical display name as the headline and descriptor as the subtitle.
- **N9 — App icon option naming:** renamed inverted icon model fields to `displayName` and `descriptor`, preserving the on-screen order while making the code match the UX.
- **N10 — Charts title:** changed the in-app Charts section title from "By Type" to "Workout Types" to match the widget and docs.
- **N11 — Unused health fields:** removed unused previous/source/date fields from `HealthMetricSummary` and unused source/date fields from `SleepSummary`; quantity queries now fetch only the latest sample.
- **N12 — Snapshot store silence:** `WorkoutSnapshotStore` now logs unavailable app group defaults plus JSON encode/decode failures with `os.Logger`.
- **N13 — Calendar accessibility:** workout calendar cells now expose explicit accessibility labels and sheet-opening hints, and inactive day contrast was slightly raised in dark mode.
- **N14 — Error state labeling:** refresh errors now become `.failed(...)` unless they are explicit authorization denials.
- **N15 — Widget family tests:** project tests now pin the calendar widget's large-only family and the workout-types widget's medium+large family independently.
- **N16 — Month picker cache:** removed the static mutable month list cache; the picker builds its bounded month list per view instance.

Additional cleanup completed:

- Consolidated duplicate duration / workout-count / energy / distance formatting into `BodyValueFormat`.
- Consolidated duplicate Home / Charts / Settings card background modifiers into one shared in-app `bodyCardBackground(cornerRadius:)` modifier.

Verification completed:

- `rtk xcodebuild build -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` passed.
- `rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` passed.

---

## What was checked

- App entry: `Body/BodyApp.swift`.
- App models: `Body/Models/BodyAppearancePreferences.swift`,
  `Body/Models/HealthSummarySnapshot.swift`.
- App services: `Body/Services/HealthKitWorkoutStore.swift` (full).
- App views: `Body/Views/MainTabView.swift`,
  `Body/Views/BodyHomeView.swift`,
  `Body/Views/BodyChartsView.swift`,
  `Body/Views/BodySettingsView.swift`,
  `Body/Views/BodyMonthYearPicker.swift`.
- Shared models: `BodyShared/Models/BodyWorkoutType.swift`,
  `BodyShared/Models/WorkoutMonthSnapshot.swift`,
  `BodyShared/Models/WorkoutSummary.swift`.
- Shared components: `BodyShared/Components/WorkoutCalendarView.swift`,
  `BodyShared/Components/WorkoutTypeBreakdownView.swift`,
  `BodyShared/Components/BodyWidgetBackground.swift`.
- Shared services: `BodyShared/Services/WorkoutSnapshotStore.swift`.
- Widgets: `BodyWidgetExtension/BodyWidgetExtensionBundle.swift`,
  `BodyWidgetExtension/WorkoutCalendarWidget.swift`,
  `BodyWidgetExtension/Info.plist`.
- Tests: `BodyTests/WorkoutMonthSnapshotTests.swift`,
  `BodyTests/HealthKitWorkoutStoreTests.swift`,
  `BodyTests/BodyWorkoutTypeTests.swift`,
  `BodyTests/ProjectConfigurationTests.swift`.
- Configuration: `Body/Body.entitlements`,
  `BodyWidgetExtension.entitlements`,
  `Body/PrivacyInfo.xcprivacy`,
  `BodyWidgetExtension/PrivacyInfo.xcprivacy`,
  `body.xcodeproj/project.pbxproj` (target sections and configs).
- Docs: `README.md`, `VersionHistory.md`, `TestPlan.md`,
  `LessonsLearned.md`.
- Grep queries:
  - `rg "BodyWidgetBackground"` to confirm the shared enum is unused.
  - `rg "import UIKit|import HealthKit|UIApplication"` against
    `BodyShared/` to confirm widget-safe shared sources.
  - `rg "TODO|FIXME|XXX"` across `Body/ BodyShared/ BodyWidgetExtension/
    BodyTests/` — no source matches.
  - `rg "WorkoutCalendarView|WorkoutTypeBreakdownView|BodyWidgetBackground"`
    to verify call sites.
  - `rg "id: \\\\.self|ForEach\\("` to inspect ForEach identity hygiene.
  - `rg "0\\.(09|56|88)|systemBackground|secondarySystemBackground"` to
    audit shared color/background patterns.

## Not checked (worth a follow-up)

- Running the project on a real device or simulator to verify N1, N3,
  and N4 user-visible effects (HealthKit needs a real device for full
  signal).
- Asset catalog `Contents.json` files beyond confirming the relevant
  PNGs exist; alternate-icon JSON wiring is asserted in
  `ProjectConfigurationTests`.
- Visual review of light/dark mode switches and Dynamic Type scaling
  (requires a build).
- Localization beyond English (TestPlan defers this; reviewed code is
  English-only as documented).
- Lock Screen / accessory widget families (deferred in TestPlan).
- Carry-forward verification from prior archives — none exist on this
  branch; this is the inaugural `Issues.md`.
