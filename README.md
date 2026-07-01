# Body

<p align="center">
  <img src="Body/Assets.xcassets/BodyIcon01.imageset/BodyIcon01.png" alt="Body app icon" width="120">
</p>

Body is a privacy-focused iOS health visualization app built with SwiftUI. It turns Apple Health workouts, Activity Rings, Readiness, sleep, energy, body measurements, daylight, steps, and vitals into a local-first app and widget experience.

Current app version: **0.9.6 (build 1)**

## Screenshots

<p align="center">
  <img src="Screenshots/01-v0.5.2.PNG" alt="Body screenshot 1" width="32%"/>
  <img src="Screenshots/02-v0.3.3.PNG" alt="Body screenshot 2" width="32%"/>
  <img src="Screenshots/03-v0.3.3.PNG" alt="Body screenshot 3" width="32%"/>
</p>

<p align="center">
  <img src="Screenshots/04-v0.5.2.PNG" alt="Body screenshot 4" width="32%"/>
  <img src="Screenshots/05-v0.3.3.PNG" alt="Body screenshot 5" width="32%"/>
  <img src="Screenshots/06-v0.3.3.PNG" alt="Body screenshot 6" width="32%"/>
</p>

## Features

- **Summary tab** - A **Star Metric** hero leads the tab — one metric pinned to the top and rendered chrome-free (no card) on a full-bleed backdrop that bleeds behind the status bar; v1 defaults to **Readiness**, rendering today's readiness score on a wave-fill tinted by the readiness band that fills left-to-right to the score and melts into the page — the big score flips up from zero and the whole hero taps through to the Readiness detail. Choose the star metric, or turn it off, in Settings > Metrics > Star Metric (a new gold row); while Readiness is starred the custom Home Background is auto-disabled (the hero supplies the color). Below the hero, drag-to-reorder health cards for Activity Rings, Exercise Minutes, Skin Temperature, Daylight, Steps, Sleep, Basics (body fat/weight/BMI), heart rate, Training Load, HRV, blood oxygen, respiratory rate, and energy — the starred metric is lifted out of this grid. Each card includes a four-day preview chart and an About explainer. Detail screens support Week/Month/6 Months/Year ranges. Tapping a metric card, a trend card, or Activity Rings zooms its detail page out of the card itself (the morph clipped to the card's rounded corners) and collapses it back into the card on dismiss; a grid card and a trend card for the same metric each animate from their own position, and the transition cross-fades under Reduce Motion. The full-bleed Star Metric hero instead **cross-fades** its detail in and out (dismissed with a Back button) — a fade reads better for a hero with no card edges to grow from.
- **Trend cards** - Below the health cards, a scrollable stack of trend cards each summarize a metric's recent direction in plain language ("On average, your weight decreased over the last 4 months."), with a comparison chart that draws a gray baseline-average line against a colored recent-average line and labels both period averages. They cover the vital, sleep, and activity metrics (Readiness, heart rate, HRV, respiratory rate, blood oxygen, sleep, skin temperature, steps, energy, exercise minutes, training load, daylight) plus **Weight** and **Body Fat** (weight follows the kg/lb unit setting); the home shows the most significant few with a Show All Trends toggle, and you choose which appear in Settings > Metrics > Trend Cards. The Weight and Body Fat cards also appear on the Basics detail page, each tapping through to its focused metric screen.
- **Add measurements** - The Basics detail screen has an Add (+) button that opens a sheet to log a new weight and/or body-fat reading — chosen with wheel pickers that start from your latest values, with a date/time and an include checkbox per measurement so you can log either or both — saved straight to Apple Health.
- **Rate workout effort** - Tap the Effort card on a workout's detail screen and it expands in place (no popup) to reveal Cancel/Save on the left and − / + buttons on the right; set the rating 1–10 (Easy → All Out) and the triangle effort meter fills to the exact level. Body saves it to Apple Health, relates it to that workout, and recomputes Training Load.
- **Workout route map** - Workouts recorded with GPS show a map behind the top of their detail screen — the route drawn fit-to-bounds and **colored by pace** (red slow → green fast) with green start and red end markers, with the city (e.g. "New York, NY") shown below the workout title. The map is a fixed background that dims as the workout details scroll up over it. Indoor or route-less workouts are unchanged.
- **Activity-aware workout metrics** - A workout's detail card adapts its stat tiles to the activity. For distance-tracking workouts (walks, runs, hikes, rides, swims, and snow sports) the **distance now leads the detail header — a large number above the duration, with a small unit** — instead of sitting in the stat grid. Walks, runs, and hikes add average pace, elevation gain, cadence, and Cardio Fitness (VO₂max); rides add average speed, cadence, and power; swims add pace per 100 m and stroke count. Max heart rate shows wherever heart-rate data exists, on top of the energy and average heart rate every workout shows; workouts without a distance focus (e.g. strength) still show a distance tile when one is recorded. Tiles appear only when the activity and recorded data support them. When recent history exists, each tile shows a compact **`↑12%`** badge above its unit comparing that metric to your **30-day average for the same workout type**, with a single **`vs 30-day avg`** label beside the **Details** heading — direction only, with no good/bad coloring, and `≈0%` when you're on par. It's computed over the 30 days before the workout; metrics without a few comparable workouts show no badge, and the badges stay hidden while that history is still loading. Below the heart-rate chart, a **time-in-zone breakdown** lists Zones 0–5 by share and bpm range, with the bands set as a percentage of an age-estimated max HR (220 − age) read from Apple Health (falling back to the session's peak HR when no birth date is available).
- **Readiness** - Readiness score based on personal baselines for sleep, heart, training load, respiratory, blood oxygen, and skin temperature signals, with status bands, component scores, confidence, and driver explanations. Today's live score also **drops after workouts** — scaled by the activity's type, effort, and metrics (duration, heart rate, energy) — accumulating across the day and resetting the next morning. The value saved to the **Week / Month / 6 Months / Year history is frozen ~10 minutes after wake** (or after 10:00 when no sleep is tracked), so the activity drop and other later same-day changes are display-only and never alter recorded history.
- **Two-source comparison** - Supported metrics (Sleep, Heart Rate, Resting Heart Rate, HRV, Blood Oxygen, Steps, Active Energy, Resting Energy, Exercise Minutes) can overlay a secondary Apple Health source alongside the primary. Primary and secondary share x-axis buckets, the legend lists each source's average, and the picker hides whichever source is already in use as the other slot to prevent duplicate series.
- **Workouts tab** - Searchable workout history with month browsing, sort, type filters, summary totals, an in-app workout calendar, and a workout type breakdown with monthly totals. Tapping a workout zooms its detail out of the card you tapped (the morph clipped to the card's rounded corners) and opens it as a full-bleed page with the bottom tab bar still visible — closed with a top-right Liquid Glass ✕ and collapsing back into the card; the calendar-day and workout-type popups open the same detail from their rows. The morph falls back to a cross-fade under Reduce Motion.
- **Sleep detail** - Today's sleep score, stage timeline, and a tappable stage breakdown that flips between per-stage durations and an optimal-range bar chart (each stage's percentage of time in bed and duration, with a healthy reference band), plus a Sleep Consistency card with a 14-day consistency percentage, the Apple-style Sleep Vitals chart, and range trend chart. The breakdown choice persists until you tap again.
- **Pull-to-refresh feedback** - Summary, metric detail, and Workouts each show a "Loading data..." overlay during pull-to-refresh that stays on screen until the underlying HealthKit refresh actually finishes, including waiting for any background sync already in flight.
- **Widgets** - Large workout calendar widget (monthly tiles using SF workout icons, with star/moon/sun count markers) and large workout types widget (percentage-bar breakdown by type). System, Black, and White background choices.
- **Apple Watch** - A companion watch app shows Readiness, Sleep, Heart Rate, HRV, Resting Heart Rate, Training Load, and Skin Temperature in the iOS card style, plus a ring-style complication for each metric (accessory circular, rectangular, and corner). The home screen leads with Training Load, and the watch's Settings screen has a show/hide toggle for each metric so you can choose which cards appear (a watch-local preference — hidden metrics stay synced and can be turned back on). Tapping a card — or a metric complication on the watch face — opens a full-screen detail page for that metric, and you can swipe up/down (or use the Digital Crown) to page between every metric's detail directly. Each page is washed in the metric's color: the title top-right, the recent-week (7-day) line chart (ringed dot per day, today emphasized, with gridlines and weekday labels), and the current value large at the bottom-left, with Readiness and Training Load showing the status level beside it and highlighting today's status band behind the line. Metrics are pushed from the iPhone over WatchConnectivity and cached on the watch for its complications; Heart Rate and HRV are refreshed directly on the watch when the pushed snapshot is stale, and a refresh button on the top-left of the watch home screen re-pulls metrics on demand. Complications refresh when the watch app is opened; snapshots pushed while it's closed are applied on next launch.
- **Apple Health sync** - Reads workouts, workout routes, activity rings, sleep, heart, body measurements, energy, daylight, steps, exercise minutes, skin temperature, date of birth (to anchor workout heart-rate zones), and per-workout cardio fitness, power, cadence, swim strokes, and distance. The Basics detail can also write the weight and body-fat measurements you enter, and a workout's effort rating, back to Apple Health — the only data Body writes there. Workout summaries and dashboard snapshots are written to App Group storage for widgets.
- **Settings** - Appearance, Units, app icon selection, Data > Source defaults for Apple Health sources, Data > Permissions to toggle each Apple Health read category on or off (including **Workout Metrics** and **Date of Birth**), and About rows. The app currently defaults to Dark theme and shows the Theme row as disabled.
- **Body Pro** - A one-time **Lifetime** in-app purchase (StoreKit 2, non-consumable) unlocks the Pro features: longer-range metric charts (free users get the **Week** range only — Month / 6 Months / Year need Pro), **custom app backgrounds**, the **secondary-source comparison** on metric charts, and the **Home Screen widgets**. Metric and sleep day-pickers open the **3 most recent days** for free, with older days behind Pro. Tapping any locked control opens the paywall; **Restore Purchases** and **Redeem Pro** (offer codes) are supported.
- **Local-first** - Widgets read a cached JSON snapshot from the app group; they do not query HealthKit directly. A current-month preview snapshot keeps the UI useful before authorization. The dashboard cache invalidates stale secondary-source series automatically when the user changes a comparison source between launches.

## Requirements

- iOS 18.0+
- watchOS 11.0+ (optional Apple Watch app)
- Xcode 26.4+
- Swift 5 language mode
- Apple Health read permission

## Installation

1. Open `body.xcodeproj` in Xcode.
2. Select the `Body` scheme.
3. Build and run on an iPhone simulator or device.
4. On a real device, pull down on the Summary tab to refresh and grant Apple Health access.

## Project Structure

```text
Body/
├── Body/                  # SwiftUI app and HealthKit workout ingestion
├── BodyShared/            # Shared workout models, snapshot storage, and calendar UI
├── BodyWidgetExtension/   # WidgetKit calendar widget
├── BodyTests/             # Unit and configuration tests
└── body.xcodeproj/        # Xcode project and shared schemes
```

## Privacy

Body reads Apple Health data only after permission is granted. Users can choose default Apple Health sources in Settings > Data > Source and hide categories in Settings > Data > Permissions without changing system-level authorization. Workout summaries are stored locally and mirrored to the widget through the app group's shared `UserDefaults`. Body does not collect tracking data. The only data Body writes to Apple Health is the weight and body-fat measurements you add in the Basics detail and the effort ratings you set on a workout. The Privacy row in Settings > About opens Body's hosted privacy policy (https://docs.ijustinz.com/body/privacy) in an in-app browser.

## Documentation

- [LessonsLearned.md](LessonsLearned.md) - implementation notes and gotchas.
- [TestPlan.md](TestPlan.md) - app and widget test plan.
- [VersionHistory.md](VersionHistory.md) - release notes.

## License

Body is source-available, not open source. The code is public for transparency and personal, non-commercial evaluation only. Commercial use, redistribution, App Store/TestFlight/enterprise distribution, derivative app publishing, sublicensing, and reuse of Body branding/assets are prohibited without prior written permission.

See [LICENSE](LICENSE) for the full Body Source-Available License. Third-party notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
