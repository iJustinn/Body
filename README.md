# Body

Body is a privacy-focused iOS health visualization app built with SwiftUI. The first release is centered on a Home Screen widget that turns Apple Health workouts into a bold monthly calendar.

The app shell follows Coin's simple tab structure: Home handles health cards and recent trends, Charts holds workout visualizations, and Settings handles appearance and app details.

Current app version: **0.1.0 (build 1)**

## v0.1.0 Scope

- **Workout calendar widget** - The large widget shows workout days for the current month with screenshot-style rounded square calendar tiles.
- **Workout types widget** - A second large-only widget shows monthly workout time by type with a Coin-style percentage-bar breakdown.
- **Widget appearance** - Widgets include Coin-style background choices for System, Black, and White.
- **Workout markers** - Workout days replace the date number with the Apple/SF workout icon in a solid color for the specific Apple Health workout type. If a day has multiple workouts, Body shows the longest-duration workout.
- **Count indicators** - Workout-day tiles keep Coin's count markers: stars count as 1, moons count as 4, and 13 or more workouts shows a sun.
- **Apple Health sync** - The app requests read-only access to workouts, sleep, heart, body measurement, and energy data; workout summaries are also written for widgets through an App Group.
- **Home health cards** - Home shows sleep, resting heart rate, weight, body fat, HRV, blood oxygen, VO2 max, BMI, active energy, and resting energy in Coin-style rounded cards that open recent-week charts by default, with a Coin-style Week/Month switch on each detail screen. Sleep details also include today's sleep-stage timeline.
- **Charts tab** - The in-app workout calendar and workout type breakdown live in Charts, use theme-aware panel backgrounds, and open workout list sheets when tapped.
- **Coin-style settings** - The Settings tab includes Appearance choices, Units, icon selection, and About rows for Copyright and Version.
- **Local-first widget bridge** - Widgets read a cached JSON snapshot from shared `UserDefaults`; they do not query HealthKit directly.
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
- [TestPlan.md](TestPlan.md) tracks the first-version test plan.
- [VersionHistory.md](VersionHistory.md) records release notes.
