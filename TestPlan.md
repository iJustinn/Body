# Body Test Plan

Generated 2026-05-10 against branch `codex/body-v0.1.0`.

## 1. Project Testing Overview

### What Was Reviewed

- App entry and screens: `Body/BodyApp.swift`, `Body/Views/BodyHomeView.swift`, `Body/Views/BodyChartsView.swift`, `Body/Views/BodySettingsView.swift`
- HealthKit ingestion: `Body/Services/HealthKitWorkoutStore.swift`
- Shared model/storage/UI: `BodyShared/Models/*`, `BodyShared/Services/WorkoutSnapshotStore.swift`, `BodyShared/Components/WorkoutCalendarView.swift`
- Widget extension: `BodyWidgetExtension/WorkoutCalendarWidget.swift`, `BodyWidgetExtension/BodyWidgetExtensionBundle.swift`
- Configuration: `Body/Body.entitlements`, `BodyWidgetExtension.entitlements`, privacy manifests, `body.xcodeproj/project.pbxproj`
- Existing tests: `BodyTests/WorkoutMonthSnapshotTests.swift`, `BodyTests/ProjectConfigurationTests.swift`

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

## 3. Manual Tests

| ID | Priority | Case | Steps | Expected |
| --- | --- | --- | --- | --- |
| M1 | Critical | First launch before Health permission | Install fresh build and open Body | App shows health cards with empty states and no sync button without crashing |
| M2 | Critical | Apple Health authorization | Pull down on the Home tab on a physical device with workout, sleep, heart, body, and energy data | Permission prompt appears; after approval, current month workouts and home health cards render |
| M3 | Critical | Widget reads app snapshot | Refresh workouts, add the large widget to Home Screen | Widget calendar matches app snapshot |
| M4 | High | Widget placeholder | Add widget before opening app | Widget shows May 2026 preview data |
| M5 | High | Widget background choices | Add both large widgets and edit their widget configuration background between System, Black, and White | Day numbers, glyphs, type bars, and labels remain readable in each background choice |
| M6 | Medium | Empty workout month | Test with a month/device that has no workouts | Calendar shows inactive days and zero workout summary |
| M7 | Medium | Multiple workout types in one day | Record/import running and strength workouts on one day | Day tile shows count badge and colored glyphs |
| M8 | Medium | Coin-style count indicators | Test days with 1, 4, 5, and 13 workouts | Tiles show star, moon, moon+star, and sun respectively |
| M9 | Medium | Settings app icon picker | Open Settings, choose each icon option, and return to Home | App icon updates for Classic, Light, Rose, Classic Alt, Light Alt, and Rose Alt; the Home/Charts/Settings tabs remain available |
| M10 | High | Workout Types widget | Add the Workout Types widget from the widget gallery | Only large size is offered; no title/month header appears; bars directly fill the widget and reflect current-month workout durations by type |
| M11 | High | Charts tab visualizations | Open Charts after syncing or with preview data, then switch app theme between Light and Dark | Workout Calendar matches the large widget styling, Workout Types shows the monthly type breakdown, and chart panel backgrounds follow the selected app theme |
| M12 | Medium | Appearance theme and accent | In Settings, choose System, Light, and Dark themes; choose several app accents | App color scheme follows the selected theme and app tint uses the selected accent color |
| M13 | High | Home health cards | Refresh on a physical device with Apple Health samples | Home shows a two-card-wide Activity Rings summary at the top, then same-sized tappable cards for sleep, Basics, resting heart rate, HRV, blood oxygen, respiratory rate, active energy, and resting energy; Basics is second after Sleep and shows weight plus smaller Body Fat and BMI values; energy cards are at the bottom and Steps are not shown |
| M14 | High | Calendar workout drill-down | In Charts, tap a calendar day | A sheet opens with all workouts for that day |
| M15 | High | Workout type drill-down | In Charts, tap a Workout Types row | A sheet opens with all workouts of that type for the month |
| M16 | High | Home card health trends | Tap each Home health card after refreshing Health data | A secondary screen opens with the current value and a Last 7 Days chart by default; non-energy metrics use line charts with dot markers, Active Energy and Resting Energy use bar charts, Basics shows a single dual-axis Weight and Body Fat chart with no BMI chart, and Sleep shows today's three-category Sleep Score, today's stage timeline with soft transition shading, an Apple-style high/typical/low Sleep Vitals chart with Sleep Duration as the fifth metric, and the week/month trend chart at the bottom |
| M17 | Medium | Unit setting | In Settings > Units, choose System, Metric, and Imperial | Basics weight display and chart switch between kg and lb, and workout distance rows switch between km and mi |
| M18 | Medium | Home card detail trend range | Tap several Home cards, then switch each detail screen between Recent Week and Recent Month | Detail charts switch between Last 7 Days and Last 30 Days for every Home card, with Recent Week as the default; Recent Week x-axis labels show weekday names and Recent Month labels show dates |

## 4. Deferred Coverage

- Historical month navigation.
- Lock Screen widgets.
- AppIntent widget configuration.
- Workout detail drill-downs.
- HealthKit background delivery.
- Localization beyond English.
