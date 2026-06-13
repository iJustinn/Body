# Body Test Plan

Generated 2026-06-10 against branch `body-v0.9.3` (app version 0.9.3 build 1).

> Apple Watch targets (`BodyWatch`, `BodyWatchWidgetExtension`) and the shared `BodyWatchShared` group are new in 0.9.3. `ProjectConfigurationTests` asserts their configuration (bundle identifiers, versions, App Group + HealthKit entitlements); behavior is not yet covered by automated cases. Manual watch verification is pending: iPhone→watch metric sync over WatchConnectivity, the live HR/HRV refresh when the snapshot is stale (including that a workout-only iPhone refresh does not mark the watch fresh, and that returning the watch app to the foreground re-checks staleness), and the ring complications (accessory circular + rectangular) for each metric. Known limitation: complications update when the watch app runs — snapshots pushed while it's closed are applied on next launch.

## 1. Project Testing Overview

### What Was Reviewed

- App entry and screens: `Body/BodyApp.swift`, `Body/Views/BodyHomeView.swift`, `Body/Views/BodyWorkoutsView.swift`, `Body/Views/BodyWorkoutListSheet.swift`, `Body/Views/BodyMonthYearPicker.swift`, `Body/Views/BodySettingsView.swift`, `Body/Views/BodyProView.swift`, `Body/Views/BodyActivityRingsDetailView.swift`
- HealthKit ingestion: `Body/Services/HealthKitWorkoutStore.swift` (`@MainActor` view-model — `@Published` outputs, public refresh entry points, snapshot publishing, source comparison helpers), `Body/Services/HealthKitFetchEngine.swift` (non-`@MainActor` `actor` — `HKHealthStore` ownership, predicate construction, every HK leaf query, dashboard fetch orchestrators), `Body/Services/HealthDashboardSnapshotStore.swift`
- Shared model/storage/UI: `BodyShared/Models/*`, `BodyShared/Services/WorkoutSnapshotStore.swift`, `BodyShared/Components/WorkoutCalendarView.swift`, `BodyShared/Components/WorkoutTypeBreakdownView.swift`
- Widget extension: `BodyWidgetExtension/WorkoutCalendarWidget.swift`, `BodyWidgetExtension/BodyWidgetExtensionBundle.swift`
- Configuration: `Body/Body.entitlements`, `BodyWidgetExtension.entitlements`, privacy manifests, `body.xcodeproj/project.pbxproj`
- Existing tests: `BodyTests/WorkoutMonthSnapshotTests.swift`, `BodyTests/ProjectConfigurationTests.swift`, `BodyTests/HealthKitWorkoutStoreTests.swift`, `BodyTests/BodyWorkoutTypeTests.swift`

## 2. Automated Tests

| ID | Priority | Case | Expected |
| --- | --- | --- | --- |
| A1 | Critical | Month snapshot groups workouts by day | Multiple workouts on one date roll up to one active day and preserve workout count |
| A2 | High | Sunday-first calendar alignment | May 2026 starts with five blank leading slots before Friday, May 1 |
| A3 | High | Longest workout controls day marker | The longest-duration workout controls the icon and color when a day has multiple workouts |
| A4 | Critical | Snapshot store round trip | Shared snapshot encodes and decodes through `UserDefaults` without data loss |
| A5 | Critical | App and widget app group entitlements match | Both targets use `group.com.zihengthedeveloper.Body` |
| A6 | Critical | App declares HealthKit entitlement and usage copy | Project has HealthKit entitlement and `NSHealthShareUsageDescription` |
| A7 | Medium | Privacy manifests declare UserDefaults access | App and widget privacy manifests include `CA92.1` and no tracking |
| A8 | Medium | Workout count indicators match Coin | Workout tiles render one star per workout, one moon per four workouts, and one sun for 13+ workouts |
| A9 | High | Workout type breakdown aggregates duration | Monthly workout type totals are sorted by total duration and keep workout counts |
| A10 | High | HealthKit workout activity mapping preserves specific types | Non-strength Apple Health workouts such as pickleball, pilates, rowing, soccer, tennis, cooldown, swim-bike-run, and underwater diving map to specific Body workout types instead of generic Workout |
| A11 | Medium | Unit preference overrides locale | Explicit Metric/Imperial choices override locale-driven kg/km vs lb/mi formatting |
| A12 | High | Workouts filter logic | Tapping a workout type plainly toggles it, and active-filter state remains visible even when the selected month has no matching types |
| A13 | Medium | Health trend ranges | Week, Month, 6 Months, and Year limit trend data to 7, 30, 183, and 365 days using Body's Gregorian calendar |
| A14 | Medium | Sleep-stage-only summaries | Health summaries with sleep stages but no duration or vitals are not treated as empty |
| A15 | Medium | Calendar day drill-down gating | Empty calendar days are not selectable, while workout days with a handler remain selectable |
| A16 | Medium | Month picker relative list | Month-year lists rebuild relative to the supplied current date so a new month can appear after a calendar-day change |
| A17 | High | Summary card permission filtering | Disabled Health permissions remove matching summary and trend data from the Summary dashboard while preserving enabled categories |
| A18 | Medium | Summary preview chart windows | Small-card preview charts use the most recent four eligible days, omit today's placeholder when today's data is missing, and preserve placeholders for earlier missing days |
| A19 | Medium | Health trend styling | Week, Month, 6 Months, and Year line charts use colored strokes and hollow point markers, long ranges cap dense point counts, and bar charts use range-aware widths |
| A20 | Medium | Metric About coverage | Every `HealthMetricKind` detail route has non-empty About text |
| A21 | Medium | Body Pro source coverage | Body Pro entry copy, icon assets, flippable icon state, feature list, and placeholder purchase copy stay wired |

## 3. Manual Tests

| ID | Priority | Case | Steps | Expected |
| --- | --- | --- | --- | --- |
| M1 | Critical | First launch before Health permission | Install fresh build and open Body | App shows health cards with empty states and no sync button without crashing |
| M2 | Critical | Apple Health authorization | Pull down on the Summary tab on a physical device with workout, sleep, heart, body, and energy data | Permission prompt appears; after approval, current month workouts and summary health cards render |
| M3 | Critical | Widget reads app snapshot | Refresh workouts, add the large widget to Home Screen | Widget calendar matches app snapshot |
| M4 | High | Widget placeholder | Add widget before opening app | Widget shows preview data for the current month |
| M5 | High | Widget background choices | Add both large widgets and edit their widget configuration background between System, Black, and White | Day numbers, glyphs, type bars, and labels remain readable in each background choice |
| M6 | Medium | Empty workout month | Test with a month/device that has no workouts | Calendar shows inactive days and zero workout summary |
| M7 | Medium | Multiple workout types in one day | Record/import running and strength workouts on one day | Day tile shows count badge and colored glyphs |
| M8 | Medium | Coin-style count indicators | Test days with 1, 4, 5, and 13 workouts | Tiles show star, moon, moon+star, and sun respectively |
| M9 | Medium | Settings app icon picker | Open Settings, choose each icon option, and return to Summary | App icon updates for Classic, Light, Rose, Classic Alt, Light Alt, and Rose Alt; the Summary/Workouts/Settings tabs remain available |
| M10 | High | Workout Types widget | Add the Workout Types widget from the widget gallery | Only large size is offered; no title/month header appears; bars directly fill the widget and reflect current-month workout durations by type |
| M11 | High | Workouts visualizations | Open Workouts after syncing or with preview data, then switch app theme between Light and Dark | The calendar appears above workout rows, the monthly total/type breakdown card appears at the bottom, and chart panel backgrounds follow the selected app theme |
| M12 | Medium | Appearance theme and accent | In Settings, choose System, Light, and Dark themes; choose several app accents | App color scheme follows the selected theme and app tint uses the selected accent color |
| M13 | High | Summary health cards | Refresh on a physical device with Apple Health samples | Summary shows a two-card-wide Activity Rings summary at the top, then same-sized tappable cards for Readiness (Beta), Exercise Minutes, Training Load, Skin Temperature, Time In Daylight, Steps, Sleep, Basics, Heart Rate, resting heart rate, HRV, blood oxygen, respiratory rate, active energy, and resting energy; each small card has a recent four-day preview chart positioned above the icon (Time In Daylight shows a `sun.max.fill` glyph, not a `plus`) |
| M14 | High | Calendar workout drill-down | In Workouts, tap a calendar day | A sheet opens with all workouts for that day |
| M15 | High | Workout type drill-down | In Workouts, tap a workout type row in the bottom summary card | A sheet opens with all workouts of that type for the month |
| M16 | High | Summary card health trends | Tap each Summary health card after refreshing Health data | A secondary screen opens with the current value and a Week chart by default; line-chart pages use colored lines and hollow dots across Week, Month, 6 Months, and Year while limiting dense long-range points; bar-chart pages use matching range-aware bar widths; Basics shows equal-size body fat and weight current values, a Difference Range card under the Week/Month/6 Months/Year selector with Body Fat, Weight, and BMI ranges, then a dual-axis Weight and Body Fat chart and a separate BMI chart; Sleep shows today's three-category Sleep Score, today's stage timeline with soft transition shading, an Apple-style high/typical/low Sleep Vitals chart with Sleep Duration as the fifth metric, and the range trend chart at the bottom |
| M17 | Medium | Unit setting | In Settings > Units, choose System, Metric, and Imperial | Basics weight display and chart switch between kg and lb, and workout distance rows switch between km and mi |
| M18 | Medium | Summary card detail trend range | Tap several Summary cards, then switch each detail screen between Week, Month, 6 Months, and Year | Detail charts switch between Last 7 Days, Last 30 Days, Last 6 Months, and Last Year for every Summary card, with Week as the default; Week x-axis labels show weekday names, Month labels show dates, and longer ranges show month labels |
| M19 | High | Workouts sort, filter, and search | Open Workouts, change sort order, filter to a single type, search by type/source/date, then change months | Visible rows, empty-state copy, and Reset Filters affordance match the active controls |
| M20 | High | Workout detail sheet | Tap a workout row from Workouts and from a workout chart drill-down sheet on small and large iPhones | The sheet shows duration, energy, distance, heart rate, effort, source, and chart content without clipped controls |
| M21 | High | Activity Rings pagination | Open Summary > Activity Rings and scroll upward one month at a time | Older months load only after user scroll gestures and do not prefetch empty placeholder months during initial layout |
| M22 | Medium | Month boundary refresh | Keep Workouts open across midnight at a month boundary, or simulate `.NSCalendarDayChanged` | The new current month appears in the picker without a cold launch |
| M23 | Medium | Activity Rings completion star | Complete Move, Exercise, and Stand rings for today, then open Summary | A gold star appears at the top right of the Summary rings graphic and scales with the smaller Summary ring size |
| M24 | High | Settings Data permissions | Open Settings > Data > Permissions and toggle several categories off and on | Disabled categories disappear or show empty data on Summary/detail charts while enabled categories remain visible; toggles persist across app relaunch |
| M25 | Medium | Metric About cards | Open every Summary card detail page | Every detail page shows an About card with metric-specific explanatory copy above the Apple Health data-source footer |
| M26 | Medium | Sleep score sheet height | Open Sleep detail and tap the Sleep Score card | The scoring breakdown sheet opens at a suitable height that shows all scoring metrics without needing to pull the sheet to full screen |
| M27 | Medium | Body Pro entry navigation | Open Settings and tap Body Pro | Body Pro opens from Settings with the premium feature list and current placeholder purchase actions |
| M28 | Medium | Body Pro icon flip | Open Body Pro and tap the large icon | The icon flips between front and back artwork and persists with `bodyProIconShowsBackKey` |
| M29 | Medium | Settings version-card unlock | Tap the Settings Version row five times | Creator-surprise icons unlock and the icon picker exposes the creator-surprise icon sheet |
| M30 | Medium | Creator-surprise icon sheet | After version-card unlock, open Settings > Appearance > App Icon | The creator-surprise icon sheet can be opened and dismissed without breaking the regular icon options |
| M31 | High | Training Load card and detail | Open Summary, locate the Training Load card, tap it | Card shows the current acute/chronic ratio with no unit; detail shows a line chart with a colored interval band (Resting / Optimal / Medium Injury Risk / High Injury Risk); scrubbing across an interval boundary smoothly transitions the band's color and bounds; the interval distribution bars below the chart show day counts per interval |
| M32 | High | Heart Rate card and detail | Open Summary, locate the Heart Rate card, tap it | Card shows the latest BPM reading; detail shows a line chart, a heart-rate range bar chart, and an hourly day-view chart below the date picker; range bars have a corner radius equal to bar width / 2 |
| M33 | Medium | Chart range-switch animation | On Heart Rate, Basics, BMI, and standard metric detail pages, tap between Week / Month / 6 Months / Year | All chart panels cross-fade between ranges; none hard-snap; reduce-motion users see an instant transition |
| M34 | Medium | Day-view chart switch | On Heart Rate detail, change the selected date in the day picker | The hourly day chart cross-fades between days; sleep / workout context bars update with the day |
| M35 | Medium | Activity Rings calendar opens on current month | Open Summary, tap the Activity Rings card | The calendar opens scrolled to the current month at the bottom of the screen; older months are visible above |
| M36 | Medium | Workouts pending-month load | In Workouts, tap a month with no cached snapshot | A "Loading [Month]" banner appears below the picker; the calendar and list keep showing the previous month; when the snapshot loads, the new month renders; if HealthKit hangs, the banner clears after 15 seconds |
| M37 | High | Readiness card and detail | Open Summary after refreshing Health data with sleep, heart, workout, respiratory, blood oxygen, and skin temperature permissions enabled | Readiness appears near the top of Summary, shows a 0-100% score with Prime/High/Moderate/Low/Poor status, opens a detail screen with confidence, trend chart, days-by-status chart, and an About section listing exact status ranges with short explanations; scrubbing the trend moves the Current label to the selected interval; Settings > Metrics > Summary Cards labels Readiness as Beta; disabling individual permissions lowers confidence or removes related drivers without crashing |
| M38 | High | Settings Data source defaults | Open Settings > Data > Source, toggle Combine Sources with Same Name, choose Primary Data Source and Secondary Data Source, then open supported metric details and change an individual source picker | Duplicate source names collapse only when the toggle is on; primary applies as the default source for source-selectable metrics including non-comparison metrics; secondary applies as the default comparison source for comparable metrics; metric detail choices override the global defaults without changing the defaults |

## 4. Deferred Coverage

- Historical month navigation beyond the loaded/paginated ranges.
- Lock Screen widgets.
- AppIntent widget configuration.
- HealthKit background delivery.
- Localization beyond English.
