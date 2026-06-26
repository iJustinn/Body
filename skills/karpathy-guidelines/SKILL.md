---
name: karpathy-guidelines
description: Project-specific working guidelines for the Body iOS SwiftUI app. Use when Codex edits, reviews, refactors, documents, or debugs this repository, especially HealthKit sync, workout snapshots, widgets, SwiftUI card/detail screens, charts, settings, app icons, formatting, build verification, or regression fixes.
---

# Karpathy Guidelines

## Operating Style

Move in small, inspectable steps. Prefer the simplest working change that fits
the existing Body code over a clever abstraction. Read the local pattern first,
patch the smallest surface, and verify with the narrowest useful test or build.

Use this order:

1. Read relevant code with `rg` and narrow file reads.
2. Check `LessonsLearned.md` before touching HealthKit, workout aggregation,
   charts, widgets, app icons, build settings, formatting, or persistence.
3. Make the smallest coherent edit.
4. Verify with focused XCTest first when practical, then the strongest relevant
   `rtk xcodebuild` gate.
5. Summarize changed files, verification, and any blocked checks.

## Project Shape

- `Body/Services/HealthKitWorkoutStore.swift` owns HealthKit read permission,
  workout ingestion, health summaries, and recent trend series.
- `Body/Models/HealthSummarySnapshot.swift` is the shared app-side shape for
  Home health cards, detail screens, sleep vitals, activity rings, and trends.
- `BodyShared/Models/WorkoutMonthSnapshot.swift` and
  `BodyShared/Services/WorkoutSnapshotStore.swift` are the app-to-widget bridge.
- Widget UI must consume shared snapshots instead of querying HealthKit directly.
- Keep model changes synchronized across app, shared models, widgets, docs, and
  tests. A field added to Home data usually needs summary state, trend state,
  HealthKit fetches, card/detail UI, placeholder data, and tests.

## SwiftUI Product Taste

- Build actual app surfaces, not explanatory UI.
- Home is a dense health dashboard. Preserve the current order and card rhythm
  unless the user asks to reorder it.
- Detail pages should use the existing card, trend selector, chart, typography,
  and dark-mode patterns before inventing new styling.
- Charts must keep clear edge padding and independent series grouping when
  plotting multiple metrics.
- Avoid inactive controls. If an icon or button does nothing, remove it or wire
  the intended behavior.
- Keep widget and in-app chart styling aligned when they represent the same
  data, but do not force widget constraints onto full app screens.

## HealthKit And Formatting

- Treat HealthKit values as source-of-truth. Do not round or transform unless
  the user explicitly asks or HealthKit units require normalization.
- Sleep duration display should preserve exact minute intent from Health data.
- Use explicit `Calendar` and day boundaries for daily HealthKit aggregation.
- Use `BodyValueFormat` for user-facing health, workout, mass, distance, energy,
  sleep, temperature, and respiratory formatting.
- Unit settings must route through `BodyValueFormat.UnitPreference`.
- Keep sleep-window vitals separate from all-day Home metrics unless the user
  asks to combine them.

## Build And Verification

Use `rtk` for shell commands in this repo.

Focused test pattern:

```bash
rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO -only-testing:BodyTests/WorkoutMonthSnapshotTests/testName
```

Full test pattern:

```bash
rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO
```

Build fallback:

```bash
rtk xcodebuild -project body.xcodeproj -scheme Body -destination generic/platform=iOS -derivedDataPath /private/tmp/body-derived CODE_SIGNING_ALLOWED=NO build
```

The simulator may fail with `Busy` during app-launch preflight even after a
successful compile. Report that separately from real build or assertion
failures, and use the generic iOS build gate as fallback.

## Git Hygiene

- Expect a dirty worktree. Do not revert user changes.
- Do not commit, push, or delete files unless explicitly asked.
- Check `rtk git status --short` and relevant diffs before finalizing.
- Avoid committing `.DS_Store`, simulator output, generated caches, or unrelated
  artifacts.
