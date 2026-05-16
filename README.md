# Body

<p align="center">
  <img src="Body/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Body app icon" width="120">
</p>

Body is a privacy-focused iOS health visualization app built with SwiftUI. It turns Apple Health workouts, Activity Rings, sleep, energy, body measurements, daylight, steps, and vitals into a local-first app and widget experience.

Current app version: **0.4.1 (build 2)**

## Screenshots

<p align="center">
  <img src="Screenshots/v0.3.3-01.PNG" alt="Body screenshot 1" width="30%"/>
  <img src="Screenshots/v0.3.3-02.PNG" alt="Body screenshot 2" width="30%"/>
  <img src="Screenshots/v0.3.3-03.PNG" alt="Body screenshot 3" width="30%"/>
</p>

<p align="center">
  <img src="Screenshots/v0.3.3-04.PNG" alt="Body screenshot 4" width="30%"/>
  <img src="Screenshots/v0.3.3-05.PNG" alt="Body screenshot 5" width="30%"/>
  <img src="Screenshots/v0.3.3-06.PNG" alt="Body screenshot 6" width="30%"/>
</p>

## Features

- **Summary tab** - Activity Rings card plus health cards for Exercise Minutes, Wrist Temperature, Daylight, Steps, Sleep, Basics (body fat/weight/BMI), heart rate, Training Load, HRV, blood oxygen, respiratory rate, and energy. Each card includes a four-day preview chart and an About explainer. Detail screens support Week/Month/6 Months/Year ranges.
- **Workouts tab** - Searchable workout history with month browsing, sort, type filters, summary totals, an in-app workout calendar, and a workout type breakdown with monthly totals.
- **Sleep detail** - Today's sleep score, stage timeline, Apple-style Sleep Vitals chart, and range trend chart.
- **Widgets** - Large workout calendar widget (monthly tiles using SF workout icons, with star/moon/sun count markers) and large workout types widget (percentage-bar breakdown by type). System, Black, and White background choices.
- **Apple Health sync** - Read-only access to workouts, activity rings, sleep, heart, body measurements, energy, daylight, steps, exercise minutes, and wrist temperature. Workout summaries and dashboard snapshots are written to App Group storage for widgets.
- **Settings** - Appearance, Units, app icon selection, Data > Permissions to hide categories from the dashboard, and About rows.
- **Local-first** - Widgets read a cached JSON snapshot from the app group; they do not query HealthKit directly. A May 2026 seed snapshot keeps the UI useful before authorization.

## Requirements

- iOS 18.0+
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

Body reads Apple Health data only after permission is granted. Users can hide categories in Settings > Data > Permissions without changing system-level authorization. Workout summaries are stored locally and mirrored to the widget through the app group's shared `UserDefaults`. Body does not collect tracking data.

## Documentation

- [LessonsLearned.md](LessonsLearned.md) - implementation notes and gotchas.
- [TestPlan.md](TestPlan.md) - app and widget test plan.
- [VersionHistory.md](VersionHistory.md) - release notes.

## License

Body is source-available, not open source. The code is public for transparency and personal, non-commercial evaluation only. Commercial use, redistribution, App Store/TestFlight/enterprise distribution, derivative app publishing, sublicensing, and reuse of Body branding/assets are prohibited without prior written permission.

See [LICENSE](LICENSE) for the full Body Source-Available License. Third-party notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
