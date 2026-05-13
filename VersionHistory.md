# Version History

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
