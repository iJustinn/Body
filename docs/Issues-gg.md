# Body — Issues Report (Gemini Audit)

Audit of branch `body-v0.5.6` on 2026-05-24. Read-only review; no code was modified.

Severity legend: Critical (data loss / crash / store-blocking), High (incorrect behavior or significant UX regression under normal use), Medium (bug or hygiene risk under specific conditions), Low (quality, performance, or maintainability delta).

---

## 1. Project Review Summary

Body v0.5.6 is in a highly polished and stable state. The repository shows excellent codebase hygiene: there are no force-unwraps (`!`), no force-casts (`as!`), no force-try statements (`try!`), and no structural TODO/FIXME markers in the source files. 

Since the previous audit, the project has successfully addressed the major code organization and architectural feedback. Most notably:
1. **File Splits and De-cluttering**: 
   - `BodyHomeView.swift` was successfully split from 8,608 lines down to ~2,155 lines, moving detail views, components, and charts to structured peer files under `Body/Views/Health/`.
   - `HealthSummarySnapshot.swift` was refactored and split, shifting sleep, activity rings, and health trend models into dedicated files.
   - `HealthKitFetchEngine.swift` was divided into extensions (`+Sleep`, `+Secondary`, `+SourceOptions`, etc.) to isolate per-domain querying logic.
2. **Feature Additions**: A secondary sleep-stage comparison feature was added in the latest commit, enabling primary vs. secondary sleep timeline rendering.
3. **Bug Resolving**: The polling loops in `loadMonthIfNeeded` have been replaced with continuation-based structures, and the `TimeInDaylight` symbol name has been unified to `sun.max.fill`.

This audit identifies 9 issues across the codebase. The highest-priority items are a data-processing issue involving hardcoded dates in the widget seed preview (medium severity) and an O(N²) calculation issue in the Readiness daily trend generator (medium severity). The rest are low-severity visual parity or test-organization findings.

---

## 2. Issue List

### Data Processing Issues

#### DP1. Hardcoded May 2026 date in `WorkoutMonthSnapshot.placeholder` seed data

- **Severity:** Medium
- **Related files:** `BodyShared/Models/WorkoutMonthSnapshot.swift:174-189, 209`, `BodyShared/Services/WorkoutSnapshotStore.swift:167-170`
- **Description:** The static property `WorkoutMonthSnapshot.placeholder` generates sample workouts with hardcoded dates in May 2026:
  ```swift
  static var placeholder: WorkoutMonthSnapshot {
      let calendar = Calendar.bodyGregorian
      let sampleWorkouts: [WorkoutSummary] = [
          sampleWorkout(day: 1, type: .running, duration: 2_400, energy: 310, distance: 5_200, calendar: calendar),
          ...
      ]
      return make(month: 5, year: 2026, workouts: sampleWorkouts, calendar: calendar)
  }
  ```
  This is called by `WorkoutSnapshotStore.seedPreviewSnapshotIfNeeded()` on first launch if the on-disk snapshot file is empty.
- **Why it matters:** If a user runs the app for the first time in a different month or later year, the widget's calendar will display "May 2026" with mock workouts. It will remain in this stale state until the app performs a successful HealthKit sync and overwrites the file. This creates an immediate impression of a stale or broken app.
- **Suggested fix:** Dynamically resolve the placeholder's month and year using the current system date:
  ```swift
  static var placeholder: WorkoutMonthSnapshot {
      let calendar = Calendar.bodyGregorian
      let now = Date()
      let currentMonth = calendar.component(.month, from: now)
      let currentYear = calendar.component(.year, from: now)
      let sampleWorkouts: [WorkoutSummary] = [
          sampleWorkout(day: 1, type: .running, duration: 2_400, energy: 310, distance: 5_200, month: currentMonth, year: currentYear, calendar: calendar),
          ...
      ]
      return make(month: currentMonth, year: currentYear, workouts: sampleWorkouts, calendar: calendar)
  }
  ```
  Update the `sampleWorkout` helper to accept `month` and `year` parameters rather than hardcoding `month: 5, year: 2026`.
- **Risks / dependencies:** Minimal. A test in `WorkoutMonthSnapshotTests` checks the schema structure of the placeholder; its assertions should be adjusted to be year-independent.

---

### Model / Data Science Issues

#### M1. O(N²) baseline calculations in Readiness `dailySeries` trend generation

- **Severity:** Medium
- **Related files:** `Body/Models/Readiness/ReadinessScoreCalculator.swift:129-164`
- **Description:** The `dailySeries()` method iterates day-by-day over a date range (up to 365 days for a Year trend) and calls `summary(on:)` for each day. Each `summary` call separately executes `autonomicComponent`, `sleepComponent`, `trainingComponent`, and `vitalsComponent` from scratch. Each of these components independently triggers `robustBaseline(...)` which filters, sorts, and extracts median values from a 56-day sliding window of values. For a 365-day trend, this results in roughly `365 × 4 = 1,460` baseline computations, redundantly scanning overlapping historical arrays.
- **Why it matters:** Although offloaded to a background thread (`Task.detached`), this O(N²) baseline computation is computationally wasteful, consumes device battery, and contributes to trends refresh latency.
- **Suggested fix:** Refactor the baseline computation to accept pre-calculated rolling baseline values or implement a single-pass rolling median and spread aggregator. This reduces the time complexity of trend generation to O(N).
- **Risks / dependencies:** Highly sensitive mathematical code. Must be carefully verified against the existing `ReadinessScoreCalculatorTests` suite.

#### M2. Binary severe-limiter gate in Readiness score may over-penalize minor anomalies

- **Severity:** Low
- **Related files:** `Body/Models/Readiness/ReadinessScoreCalculator.swift:517-532` (`adjustedSummaryScore` and `isSevereLimiter`)
- **Description:** The Readiness calculator applies a hard binary cap if any component score is `<= 25` and its strongest driver impact is `>= 0.90`:
  ```swift
  private static func isSevereLimiter(_ result: ComponentResult) -> Bool {
      guard let componentScore = result.component.score else { return false }
      let strongestImpact = result.drivers.map(\.impact).max() ?? 0
      return componentScore <= 25 && strongestImpact >= 0.90
  }
  ```
  If this returns true, the entire daily Readiness score is clamped to `min(score, 24)`.
- **Why it matters:** A user with optimal sleep, training, and autonomic scores could have their overall readiness score clamped to `<= 24` due to a single anomalous vital reading (e.g., a low blood oxygen reading during sleep). This binary gate can cause sudden, alarming score drops that degrade user trust.
- **Suggested fix:** Transition from a binary clamp to a graduated penalty proportional to the number and severity of limiters, or require at least two severe limiters before applying the cap.
- **Risks / dependencies:** Shifts the readiness score distribution. Needs empirical validation.

#### M3. Sleep continuity scoring relies on population-wide hardcoded efficiency thresholds instead of personal baselines

- **Severity:** Low
- **Related files:** `Body/Models/Readiness/ReadinessScoreCalculator.swift:265-275`
- **Description:** The sleep continuity score is calculated by comparing sleep efficiency (awake vs. in-bed ratio) against a hardcoded threshold of 78% with a span of 18%:
  ```swift
  let continuityProgress = min(max((efficiency - 0.78) / 0.18, 0), 1)
  ```
  Unlike the autonomic and vitals metrics, this is a static population threshold rather than a personal baseline.
- **Why it matters:** Sleep efficiency is highly individual. High-efficiency sleepers (e.g., typically 95%) can drop to 80% (a major personal disruption) without penalty, whereas naturally low-efficiency sleepers (e.g., typically 75%) will be constantly flagged as having fragmented sleep.
- **Suggested fix:** Use a rolling historical median (e.g., 7-day or 14-day median) for sleep efficiency to personalize the continuity calculation, falling back to the 78% population threshold when history is insufficient.
- **Risks / dependencies:** Requires at least 7 days of sleep stage data to compute a personal baseline.

---

### UI / Dashboard Issues

#### U1. BodyPro Lifetime purchase card displays a real-looking price ($5.99) but is just a static placeholder

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:41-50, 250-287`
- **Description:** `BodyProPurchaseOptionCard` displays a purchase option displaying a price of `$5.99` and an arrow button indicating it can be chosen. Tapping it does not initiate a purchase flow; it merely updates `statusMessage` to `"Body Pro lifetime purchases are not available in this build."`.
- **Why it matters:** The checkout flow appears fully functional. A user is presented with a specific price and a call-to-action arrow, only to find out post-tap that the feature is placeholder-only.
- **Suggested fix:** Replace the price with a `"Coming Soon"` badge, disable the button, or gate the purchase card under a compilation flag like `#if PRO_PURCHASES_ENABLED`.
- **Risks / dependencies:** None. Asserts in `ProjectConfigurationTests` that check for the page strings will need updates if wording is modified.

#### U2. BodyPro Future Updates note uses the gold checkmark circle icon, suggesting the features are already unlocked

- **Severity:** Low
- **Related files:** `Body/Views/BodyProView.swift:363-387`
- **Description:** The placeholder row `BodyProFutureUpdatesNote` reads `"More Body Pro features will be added in future updates."` but displays the same `BodyProFeatureCheckmark()` (a gold-filled checkmark) as features that are already unlocked and available.
- **Why it matters:** The gold checkmark carries a strong visual semantic of "completed", "unlocked", or "active". Using it on a row representing future updates creates confusing visual cues.
- **Suggested fix:** Replace the checkmark in `BodyProFutureUpdatesNote` with a more appropriate glyph (e.g., `sparkles`, `calendar`, or omit it).
- **Risks / dependencies:** None.

---

### Code Quality Issues

#### Q1. High file size and lack of logical structure in `WorkoutMonthSnapshotTests.swift`

- **Severity:** Low
- **Related files:** `BodyTests/WorkoutMonthSnapshotTests.swift`
- **Description:** `WorkoutMonthSnapshotTests.swift` is a single test file of 178,510 bytes (~3,500 lines) containing tests for snapshot building, store operations, breakdowns, localization, and formatting. The file contains zero `// MARK:` comments or logical groupings.
- **Why it matters:** Navigating the file, adding new assertions, and maintaining tests is difficult, and the file is prone to merge conflicts.
- **Suggested fix:** Add `// MARK: -` sections to partition tests logically (e.g., Snapshot Construction, Formatting, Database Store), or split the file into smaller targeted test files.
- **Risks / dependencies:** None.

#### Q2. Large file size and lack of structure in `ProjectConfigurationTests.swift`

- **Severity:** Low
- **Related files:** `BodyTests/ProjectConfigurationTests.swift`
- **Description:** `ProjectConfigurationTests.swift` is ~90,327 bytes (around 1,800 lines) of automated verification rules with zero `// MARK:` annotations to separate tests for assets, info plists, source-grep rules, or view layouts.
- **Why it matters:** Impedes developer speed when adding new configuration checks or maintaining existing tests.
- **Suggested fix:** Add `// MARK:` comments to separate different types of assertions.
- **Risks / dependencies:** None.

---

### Missing Tests

#### T1. Direct test coverage is missing for `HealthKitFetchEngine` and its sub-extensions

- **Severity:** Medium
- **Related files:** `Body/Services/HealthKitFetchEngine.swift` and related extension files (`HealthKitFetchEngine+Sleep.swift`, etc.)
- **Description:** While `HealthKitWorkoutStore` has test coverage that covers some high-level behavior, the underlying `HealthKitFetchEngine` actor (which performs query construction, source selection mapping, sleep merging, and downsampling) has no dedicated direct unit tests.
- **Why it matters:** The fetch engine is the single point of entry for raw HealthKit data. A bug in its incremental fetch bounds, date interval calculations, or source mapping can lead to silent data processing errors.
- **Suggested fix:** Create a dedicated test suite `BodyTests/HealthKitFetchEngineTests.swift` that uses mocked data inputs to test pure helpers like `incrementalFetchStart`, `mergeIntradaySamples`, `sleepStageSegments`, and `hydrateSleepVitalsInParallel`.
- **Risks / dependencies:** Requires writing tests inside an async/actor context.

#### T2. No test coverage for `BodyWorkoutHeartRateChart` drawing logic

- **Severity:** Low
- **Related files:** `Body/Views/BodyWorkoutsView.swift`
- **Description:** `BodyWorkoutHeartRateChart` uses a custom `Canvas` to draw smoothed curves, scatter dots, and color-gradient stops. No automated test asserts that the interpolation works correctly or that label positioning keeps elements within screen boundaries.
- **Why it matters:** Visual changes or layout modifications to the chart can introduce rendering issues that go undetected by current configuration tests.
- **Suggested fix:** Implement a snapshot test or a specific drawing logic unit test using mocked coordinates to verify boundary and color calculations.
- **Risks / dependencies:** None.

---

## 3. Priority Recommendations

### Fix First
1. **DP1 — Hardcoded May 2026 placeholder in WorkoutMonthSnapshot**: Resolving this avoids a jarring "May 2026" visual bug on first launch of the widget for new installs in later months or years.
2. **T1 — Add direct test coverage for HealthKitFetchEngine**: The fetch engine is the core data ingestion pipeline. Dedicated unit tests for its pure/actor helpers will prevent silent regressions.

### Fix Next
3. **M1 — Optimize dailySeries baseline calculations to O(N)**: Optimizing this computation will save battery power and reduce trend refresh latency.
4. **U1 — Update BodyPro Lifetime purchase card**: Replacing the mock price with "Coming Soon" or disabling the button avoids frustrating users who expect a functioning purchase flow.
5. **U2 — Swap checkmark on BodyPro Future Updates note**: Eliminates conflicting visual cues on the pricing page.

### Optional Cleanup
6. **M2 / M3 — Review Readiness z-score cap and sleep continuity baseline**: Fine-tune scoring parameters to improve score personalization and reduce sensitivity to single-point noise.
7. **Q1 / Q2 — Split/Structure WorkoutMonthSnapshotTests and ProjectConfigurationTests**: Improve test suite maintainability by adding MARK sections or splitting into modular files.
8. **T2 — Add snapshot/drawing logic test for heart rate chart**: Ensure the Canvas rendering of workout heart rate data remains stable.

---

## What was checked
- **App entry & configuration**: `Body/BodyApp.swift`, `body.xcodeproj/project.pbxproj`
- **Models**: `Body/Models/Sleep.swift`, `Body/Models/HealthTrend.swift`, `BodyShared/Models/WorkoutMonthSnapshot.swift`
- **Readiness calculator**: `Body/Models/Readiness/ReadinessScoreCalculator.swift`
- **Services**: `Body/Services/HealthKitWorkoutStore.swift`, `Body/Services/HealthKitFetchEngine.swift`, `Body/Services/HealthKitFetchEngine+Sleep.swift`, `Body/Services/HealthKitFetchEngine+Secondary.swift`
- **Views**: `Body/Views/BodyHomeView.swift`, `Body/Views/BodyProView.swift`, `Body/Views/BodyWorkoutsView.swift`, `Body/Views/Health/BodyHealthDataSourcePickerSheet.swift`, `Body/Views/Health/BodyHealthMetricDetailView.swift`, `Body/Views/Health/Charts/SleepCharts.swift`
- **Widget**: `BodyWidgetExtension/WorkoutCalendarWidget.swift`
- **Tests**: `BodyTests/ReadinessScoreCalculatorTests.swift`, `BodyTests/WorkoutMonthSnapshotTests.swift`, `BodyTests/ProjectConfigurationTests.swift`
- **Docs**: `README.md`, `LessonsLearned.md`, `TestPlan.md`, `Issues.md`, `docs/Issues-ds.md`

## Not checked
- Running the project on a simulator or physical device (no build performed in this run).
