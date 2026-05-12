# Body

Body is a privacy-focused iOS health visualization app built with SwiftUI. It turns Apple Health workouts, sleep, energy, body measurements, and Activity Rings into a local-first app and widget experience.

The app shell follows Coin's simple tab structure: Home handles health cards and recent trends, Workouts provides searchable workout history, Charts holds workout visualizations, and Settings handles appearance and app details.

Current app version: **0.2.6 (build 6)**

## Current Scope

- **Workout calendar widget** - The large widget shows workout days for the current month with screenshot-style rounded square calendar tiles.
- **Workout types widget** - A second large-only widget shows monthly workout time by type with a Coin-style percentage-bar breakdown.
- **Widget appearance** - Widgets include Coin-style background choices for System, Black, and White.
- **Workout markers** - Workout days replace the date number with the Apple/SF workout icon in a solid color for the specific Apple Health workout type. If a day has multiple workouts, Body shows the longest-duration workout.
- **Count indicators** - Workout-day tiles keep Coin's count markers: stars count as 1, moons count as 4, and 13 or more workouts shows a sun.
- **Apple Health sync** - The app requests read-only access to workouts, activity rings, sleep, heart, body measurement, and energy data; workout summaries are also written for widgets through an App Group.
- **Home health cards** - Home shows a two-card-wide Activity Rings summary above sleep, Basics, resting heart rate, HRV, blood oxygen, respiratory rate, active energy, and resting energy cards that open recent-week charts by default, with a Coin-style Week/Month switch on each detail screen. Basics combines weight, body fat, and BMI, while Sleep details show today's sleep score, today's sleep-stage timeline, an Apple-style high/typical/low Sleep Vitals chart with sleep duration as the fifth metric, and the week/month trend chart at the bottom.
- **Charts tab** - The in-app workout calendar and workout type breakdown live in Charts, use theme-aware panel backgrounds, and open workout list sheets when tapped.
- **Workouts tab** - A dedicated workout history surface supports month browsing, search, sort, type filters, summary totals, and workout detail sheets.
- **Coin-style settings** - The Settings tab includes Appearance choices, Units, icon selection, and About rows for Copyright and Version.
- **Local-first widget bridge** - Widgets read a cached JSON snapshot from the app group's shared file container; they do not query HealthKit directly.
- **Preview seed data** - A May 2026 placeholder snapshot keeps the widget and app visually useful before HealthKit access is granted.

## Requirements

- iOS 18.0+
- Xcode 26.4+
- Swift 5 language mode
- Apple Health read permission

## Installation

1. Open `body.xcodeproj` in Xcode.
2. Select the `Body` scheme.
3. Build and run on an iPhone simulator or device.
4. On a real device, pull down on the Home tab to refresh and grant Apple Health access.

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

Body reads health data from Apple Health only after permission is granted. Workout summaries are stored locally on device and mirrored to the widget through the app group's shared `UserDefaults`. Body does not collect tracking data.

## Documentation

- [LessonsLearned.md](LessonsLearned.md) captures project-specific implementation notes and gotchas.
- [TestPlan.md](TestPlan.md) tracks the current app and widget test plan.
- [VersionHistory.md](VersionHistory.md) records release notes.
