# Version History

## 0.5.2 (build 3)

- Extracted a new `HealthKitFetchEngine` actor (`Body/Services/HealthKitFetchEngine.swift`) that owns `HKHealthStore`, the cached source map, predicate construction, every HealthKit query, and the dashboard fetch orchestrators (`fetchHealthSummary`, `fetchHealthTrends`, `fetchHealthDashboardSnapshot`, `fetchHealthDataSourceOptions`). `HealthKitWorkoutStore` shrank from ~3,900 to ~1,450 lines and now keeps only the `@Published` view-model state, public refresh entry points, and snapshot publishing — it delegates fetching to the engine via `await`. The bulk of the fetch-time Swift work no longer runs on `@MainActor`.
- Mirrored the three selections (`permissionSelection`, `healthDataSourceSelection`, `secondaryHealthDataSourceSelection`) onto the engine; the store syncs them via `setPermissionSelection` / `setHealthDataSourceSelection` / `setSecondaryHealthDataSourceSelection` whenever the user updates a permission or picks a different source.
- Updated `BodyTests/ProjectConfigurationTests.swift` so the four string-grep assertions covering moved HealthKit internals point at `HealthKitFetchEngine.swift` instead of `HealthKitWorkoutStore.swift`; semantic assertions are unchanged.
- Updated the app, widget, and test bundle version to 0.5.2 build 3.

## 0.5.2 (build 2)

- Incrementally load intraday metric day-view samples after the cached tail so detail screens fetch only new HealthKit samples on subsequent opens.
- Updated the Recovery detail header to show score and status directly.
- Deferred the cached-dashboard recovery recompute out of `HealthKitWorkoutStore.init`. The first frame paints from the cached `summary.recovery` value (correct as of its last successful refresh); the next refresh recomputes Recovery off the main thread.
- Moved the per-refresh `recalculatingRecovery` (day-by-day baseline iteration over ~365 trend points) into a `Task.detached(.userInitiated)` inside `updateHealthDashboardSnapshot` so it no longer blocks the main thread.
- Moved `HealthDashboardSnapshotStore.save` and `WorkoutSnapshotStore.save` / `savePrevious` + `WidgetCenter.shared.reloadAllTimelines()` into `Task.detached(.utility)` so JSON encode + atomic write + widget XPC round-trip no longer run on the main actor during refresh.
- Updated the app, widget, and test bundle version to 0.5.2 build 2.

## 0.5.1 (build 2)

- Expanded home Summary trend cards from a fixed 28-day comparison window to candidate windows up to one year (28/90/180/270/365 days), each with its own minimum segment size and preferred recent length; the card now picks the most meaningful window per metric and tiebreaks by data coverage so sparse metrics still default to the shortest fitting window.
- Cached trend card window selection behind a lightweight series fingerprint so the home Summary no longer recomputes comparisons on every view rebuild - only when the underlying data, units, or current day changes.
- Capped trend card preview charts at 60 visual points via per-segment bucketed averaging that preserves the baseline/recent boundary; longer windows render smoothed buckets while comparison math still uses full-resolution daily values.
- Trend card period labels and message phrasing now scale with the chosen window length (days for under 28, weeks for 28-89, months for 90+).
- Updated the app, widget, and test bundle version to 0.5.1 build 2.

## 0.5.1 (build 1)

- Improved HealthKit refresh performance by moving daily trend aggregation into `HKStatisticsCollectionQuery`, pairing average/range queries for vitals, and lazy-loading intraday day samples only when metric detail screens open.
- Reduced background refresh churn with continuation-based refresh completion waits, tiered app-resume refreshes, source-option caching, save-if-changed dashboard/workout snapshots, and widget reloads only when cached bytes change.
- Added a previous-month workout snapshot fallback for widgets so month rollovers can keep showing recent data until the app refreshes the new current month.
- Updated the app, widget, and test bundle version to 0.5.1 build 1.

## 0.5.0 (build 3)

- Added a Recovery Summary card that compares sleep, heart, training load, and sleep-window vitals against personal baselines, with confidence and driver explanations for missing or unusual signals.

## 0.5.0 (build 2)

- Added a "Loading data" overlay to every pull-to-refresh (Summary, metric detail, Workouts) that stays on screen until the underlying refresh finishes; the overlay also rides out any background refresh already in flight, and has a 600 ms minimum display so fast refreshes still register visually.
- Updated the Day View chart legend so it shows only "Avg N" without a source name when a single source is active, and falls back to the dot + per-source layout only when a secondary source is selected. The single-source style matches the existing range/trend chart legend.
- Increased Day View chart spacing for charts that overlay sleep/workout context icons (Heart Rate, HRV) so the icons no longer crowd the title row; the day chart now uses a dedicated taller layout constant.
- Updated the in-app How to Use guide with a new "Compare Two Sources" section, mentions of the loading overlay in Summary/Day Views/Workouts, and a note on the single-source vs. comparison legend behavior.
- Updated the README features section to reflect the two-source comparison flow, the loading overlay, and the secondary-cache invalidation on launch.
- Removed helper subtitles from the data source picker rows so source choices show only the source name.
- Updated the app, widget, and test bundle version to 0.5.0 build 2.

## 0.5.0 (build 1)

- Added two-source comparison for Sleep, Heart Rate, Resting Heart Rate, HRV, Blood Oxygen, Steps, Active Energy, Resting Energy, and Exercise Minutes: supported metric detail screens can overlay a secondary Apple Health source alongside the primary with shared x-axis buckets and per-source averages in the legend.
- Added a deterministic secondary-selection signature persisted alongside the dashboard snapshot so cached `*Secondary` series are zeroed out on launch when the comparison source has changed since the snapshot was written.
- Fixed the secondary source picker including whichever source was already chosen as the primary, which let users render two identical overlapping series; the secondary picker now filters out the active primary option.
- Fixed `updateSecondaryHealthDataSource` swallowing requests while another refresh was in flight; the call now waits for the in-flight refresh and then runs a focused per-metric refresh.
- Fixed a `ForEach` identity collision in comparison charts when two sources reported the same display name by introducing a `BodyHealthSourceRole` discriminator threaded through every chart entry id.
- Fixed `averageValue` accepting (and ignoring) a source argument; the API now lives on `BodyHealthSourceTrend`/`BodyHealthSourceRangeTrend` and accepts an explicit calendar/date for testability.
- Fixed the day-view chart legend showing a misleading "--" for an empty side; the legend now omits sides that have no data.
- Fixed bucket drift between primary and secondary series near midnight by anchoring each refresh's interval to a single `Date()` plumbed through `recentHealthTrendInterval` via a new `healthTrendAnchorDate` field.
- Fixed a race where rapid secondary-source changes could leak the new selection into still-running HealthKit queries; each secondary fetch helper now pins the option at entry instead of re-reading it inside every case.
- Performance: comparison chart inits no longer call `calendarPoints` three times for the x-domain; pre-computed entries are reused. Legend averages are computed once per render via stored `BodyHealthSourceLegendItem` rows instead of being re-walked inside the view body.
- Performance: secondary HealthKit fetches in `fetchHealthTrends` are now gated on the per-metric "No Comparison" state through a new `fetchSecondaryIfEnabled` helper, so default installs no longer spawn ~12 trivial `async let` tasks per refresh.
- Refactors: collapsed five near-identical `usesSourceComparison*` predicates into a single `supportedComparisonCharts: Set<SourceComparisonChartKind>` table; merged two `sourceComparisonChartCalendarPoints` copies into a shared private aggregator; unified three legend views into one `BodyHealthSourceLegend` driven by `[BodyHealthSourceLegendItem]`; replaced "primary"/"secondary" string literals with the `BodyHealthSourceRole` enum across all chart entries; hoisted unexplained magic numbers (`1.12`, `0.16`, the `*2` aggregation doubling) into named constants on `BodyHealthTrendRange`.
- Tests: added value-level coverage for `supportedComparisonCharts`, `BodyHealthSourceTrend.id` role discrimination, `BodyHealthSourceTrend.averageValue(in:calendar:date:)`, secondary-selection signature determinism, `HealthTrendSnapshot.clearingSecondarySeries()`, and `sourceComparisonChartDateOffset` for the six-month and year ranges; updated string-grep configuration tests to match the unified legend and pinned-option structure.

## 0.4.1 (build 2)

- Updated the in-app How to Use guide for Metrics settings, Data Refresh, Cache, and current Summary controls.
- Updated the app, widget, and test bundle version to 0.4.1 build 2.

## 0.4.1 (build 1)

- Updated the app, widget, and test bundle version to 0.4.1 build 1.

## 0.3.9 (build 2)

- Added Heart Rate, Wrist Temperature, and Training Load dashboard cards with dedicated detail charts.
- Added Training Load interval highlighting, selected-point interval updates, and interval distribution counts.
- Fixed long-range chart right-edge padding for month, six-month, and year views.
- Moved the dashboard cache out of UserDefaults into file-backed storage to avoid oversized preferences writes.
- Updated the app, widget, and test bundle version to 0.3.9 build 2.

## 0.3.4 (build 2)

- Added animated Summary metric number transitions and Activity Rings sweep updates.
- Updated the app, widget, and test bundle version to 0.3.4 build 2.

## 0.3.4 (build 1)

- Updated the app, widget, and test bundle version to 0.3.4 build 1.

## 0.3.3 (build 2)

- Added range-aware chart aggregation for six-month and year health charts, including averaged buckets and timeframe-aware selection labels.
- Added average values to the Basics weight/body fat legend and kept those labels visually secondary.
- Updated long-range and day-view line charts to use consistent point markers, capped dense line charts, and tuned bar widths for weekly and small-screen long-range views.
- Updated the app, widget, and test bundle version to 0.3.3 build 2.

## 0.3.3 (build 1)

- Updated the app, widget, and test bundle version to 0.3.3 build 1.

## 0.3.0 (build 1)

- Renamed the Home tab to Summary and moved workout visualizations into Workouts.
- Placed the monthly workout calendar above workout rows and merged monthly totals with the workout type breakdown at the bottom of Workouts.
- Updated the app, widget, and test bundle version to 0.3.0 build 1.

## 0.2.7 (build 3)

- Added Exercise Minutes, Wrist Temperature, Time In Daylight, and Steps as first-class Home cards with dedicated detail screens and matching bar or line chart previews.
- Added recent four-day preview charts to Home metric cards, including placeholder behavior for missing prior-day data and no preview placeholder for missing current-day data.
- Added Basics detail refinements for Body Fat/Weight ordering, selected chart annotation sizing, a separate BMI chart, and a timeframe-aware Difference Range card for Body Fat, Weight, and BMI above the Basics charts.
- Expanded Home card detail trend ranges from Week and Month to Week, Month, 6 Months, and Year.
- Updated Week and Month line charts to use colored lines and colored hollow point markers; longer ranges hide points, and the Year line is slightly thinner than 6 Months.
- Added range-transition safeguards so line chart dots rebuild immediately instead of lingering while moving to new positions.
- Added average labels across non-Basics trend charts, while leaving the combined Weight and Body Fat chart focused on its two-series comparison.
- Added a scaled gold completion star to the Home Activity Rings card when all three rings are complete today.
- Added Settings > Data > Permissions toggles so users can control which Health categories appear in Body.
- Added About cards for every metric detail page.
- Refined Sleep card sizing, Sleep Score display, Sleep Score sheet height, Sleep Stages date display, and Sleep Vitals chart layout.
- Updated the app, widget, and test bundle version to 0.2.7 build 3.

## 0.2.6 (build 7)

- Bumped the app, widget, and test bundle build number to 7.

## 0.2.6 (build 6)

- Fixed the `Issues.md` v0.2.6 audit findings across dashboard snapshot logging, health detail routing, workout calendar taps, workout filters, trend limiting, month-picker refresh, Activity Rings pagination, and widget/banner color consistency.
- Updated project build settings, app version fallback text, README, TestPlan, and issue-tracking documentation to match v0.2.6 build 6.
- Removed stale snapshot and HealthKit helper APIs that were no longer used by production code.

## 0.2.5 (build 5)

- Added Activity Rings history detail with lazy month pagination and safeguards against synthesizing unloaded months.
- Expanded Health dashboard tests for Activity Rings history, sleep vitals, trend chart behavior, and pagination gates.

## 0.2.4 (build 4)

- Added the Workouts tab with month browsing, sort and filter sheets, search, summary totals, and workout detail sheets.
- Moved current-month workout snapshot sharing to the app group's JSON file path used by widgets.

## 0.2.3 (build 1)

- Updated the app version to 0.2.3 build 1.
- Reverted completed Activity Rings to solid full-circle rendering after 100%.

## 0.2.0 (build 3)

- Added the initial SwiftUI app, WidgetKit extension, and Xcode project structure.
- Added read-only Apple Health workout sync for the current month.
- Added shared workout month snapshots for app-to-widget data handoff.
- Added a bold workout calendar UI for the Charts tab and large widget.
- Added app group, HealthKit entitlement, privacy manifests, app icons, and project configuration tests.
- Updated workout calendar styling so workout days use one solid-color Apple/SF workout icon selected by longest duration.
- Carried over Coin's star, moon, and sun count indicators for workout-day tiles.
- Added a Coin-style Home/Charts/Settings tab shell with app icon selection, Copyright, and Version rows.
- Added a large-only Workout Types widget that adapts Coin's By Category chart for workout duration by type.
- Removed the title/month header and inner card from the Workout Types widget so it matches Coin's full-widget breakdown style.
- Moved in-app workout visualizations into Charts and simplified Home health refresh to pull-to-refresh.
- Added Settings appearance choices for app theme and app accent color, defaulting the app accent to blue.
- Added Coin-style Home health cards for sleep, resting heart rate, weight, body fat, HRV, blood oxygen, respiratory rate, and BMI.
- Added secondary Home card visualization screens with 30-day line charts and dot markers.
- Added Charts drill-down sheets for tapped calendar days and workout type rows.
- Expanded Apple Health workout recognition so specific non-strength workout types no longer collapse into generic Workout.
- Simplified Home health cards by making Sleep the same size as other cards, reducing value typography, and removing range bars and non-functional navigation cues.
- Added widget background configuration for System, Black, and White backgrounds, matching Coin's widget appearance picker.
- Made in-app chart panel backgrounds follow the selected app theme instead of staying dark.
- Expanded workout type colors into a more distinguishable shared palette while keeping traditional strength training red.
- Added home health card icons, removed the sleep source label, and refresh Health data automatically when the app becomes active.
- Updated the in-app workout type chart to use the same full-widget layout as the Workout Types widget.
- Replaced the default Body 01 app icon artwork with the new blue icon.
- Added Pink and White app icon choices using Coin-style appicon and preview asset naming.
- Refreshed the Classic, Light, and Rose app icons and added Classic Alt, Light Alt, and Rose Alt as the second icon-picker row.
- Added Coin-style month history browsing to Charts with the latest three months preloaded and older months loaded on demand.
- Muted overly bright workout colors so calendar icons and By Type bars stay visually consistent.
- Switched in-app chart panels from the widget gradient to Coin's solid card background.
- Added a medium Workout Types widget that shows the top two workout types and kept the large widget capped at five.
- Made the in-app By Type chart height adapt to the selected month's number of workout types.
- Added a subtle fade between the fixed month picker and scrolling Charts content.
- Rebuilt workout type colors from the attached reference swatches only.
- Fixed the `Issues.md` audit findings across HealthKit sync state, sleep aggregation, locale units, widget families, accessibility, and settings consistency.
- Added a Settings Units section for System, Metric, and Imperial formatting.
- Added Active Energy and Resting Energy Home cards with daily bar-chart detail screens.
- Moved the Home card trend range option onto each detail screen with Coin-style Recent Week and Recent Month buttons.
- Added today's sleep-stage timeline to the Sleep detail screen and aligned Sleep summary duration with the latest sleep day bucket.
- Added Health-style sleep-stage transition shading and denser time labels to the Sleep detail timeline.
- Added average sleep duration labels to Sleep trend charts and a three-category Sleep Score card for today's Sleep detail.
- Added sleep-window vitals using HealthKit heart rate, respiratory rate, blood oxygen, and sleeping wrist temperature data.
- Replaced the Home VO2 Max card with Respiratory Rate and refreshed Blood Oxygen card coloring.
- Changed Sleep Vitals to an Apple-style high/typical/low region chart, with Sleep Duration as the fifth metric and red dots for high or low values.
- Moved the Sleep week/month trend charts to the end of the Sleep detail screen after score, stages, and vitals.
- Added a two-card-wide Apple-style Activity Rings card at the top of Home using HealthKit Activity Summary values and goals.
- Combined Weight, Body Fat, and BMI into a Basics Home card with a dual-axis Weight and Body Fat detail chart.
