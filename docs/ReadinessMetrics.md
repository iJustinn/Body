# Readiness Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `body-rtk-tdd` for every code-changing task in this repository. If delegating work, use `subagent-driven-development`; otherwise use `executing-plans`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Readiness Summary card and detail view that score near-term readiness from the user's own Apple Health baselines.

**Architecture:** Keep HealthKit fetching focused on raw health data. Add dedicated Readiness models and a pure `ReadinessScoreCalculator` that transforms existing `HealthSummarySnapshot`, `HealthTrendSnapshot`, and `SleepHistorySnapshot` data into a score, components, confidence, and drivers. Wire the result into existing Summary card ordering, dashboard caching, metric detail routing, and tests.

**Tech Stack:** Swift, SwiftUI, HealthKit, XCTest, existing Body snapshot models, existing `rtk xcodebuild` workflow.

---

## Ground Rules

- Run all shell commands through `rtk`.
- Do not commit unless the user explicitly asks for a commit.
- Keep Readiness non-diagnostic. Use phrases like "above baseline", "below baseline", and "needs more data"; avoid illness diagnosis and injury prediction.
- Use Red-Green-Refactor: failing XCTest first, smallest code to pass, refactor only after green.
- Preserve existing Summary card rhythm. Readiness should behave like the other health cards, not introduce a new landing page.

## Score Definition

> **Revised in 0.9.2 (recovery-anchored recalibration):** the original
> weighted-average score compressed real crash days into the High band
> (May 30 – Jun 11 2026 export vs WHOOP recovery: WHOOP 9–96, Body 76–95).
> The score is now anchored on an autonomic recovery core computed from
> overnight-first inputs, with sleep, training, and vitals acting as bounded
> multiplicative penalties instead of averaged weights.

Inputs (overnight-first):

- Autonomic and vitals metrics prefer the overnight values hydrated into
  `sleepHistory.days[].summary.vitals` (sleep-window HRV, heart rate,
  respiratory rate, blood oxygen, wrist temperature).
- A metric is overnight-qualified for a scoring day when at least 14 nights
  carry that vital inside the 56-day baseline window. The autonomic HRV+HR
  pair switches sources atomically (both overnight or both whole-day), and
  value + baseline always come from the same series.
- When an overnight-qualified metric has no value on the scoring day it is
  simply absent for that day — it never falls back to the whole-day value
  against an overnight baseline. Users without sleep tracking keep the
  whole-day trend series behavior exactly as before.

Score:

```text
z_hrv = clamp(robustZ(hrv), -2.5, +2.0)          // favorable = above baseline
z_hr  = clamp(-robustZ(heartRate), -2.5, +2.0)   // favorable = below baseline
z     = weighted mean of available parts (HRV 0.65, HR 0.35)
core  = 5 + 92 / (1 + exp(-(z + 0.55) / 0.55))   // −2→11, −1→33, 0→72, +1→92, +2→96
        (= 70 neutral when no autonomic data; confidence capped at low)

f_sleep  = 0.75 + 0.25·q      // q = mean of the available sub-progresses
                              // (duration vs goal, continuity); 1.0 if no sleep
f_strain = 1.0 at ACWR ≤ 1.0, easing to 0.90 at 1.3, 0.70 at ≥ 1.6; 1.0 if none
f_vitals = 1 − 0.45·maxAnomalyProgress           // resp/temp high-side, SpO₂
                                                 // low-side (< 95 % ⇒ ≥ 0.35)

Readiness = clamp(round(core × f_sleep × f_strain × f_vitals), 0, 100)
            capped at 25 when any vitals anomaly progress ≥ 0.95
```

Component sub-scores (autonomic = rounded core, sleep, training, vitals) are
still emitted with nominal weights 30/30/25/15 for display; the headline
score comes only from the formula above.

Status bands (also used as chart band colors via `highlightedRange`/`highlightedRangeResolver`, mirroring `BodyTrainingLoadIntervalPresentation`):

- `prime`: 95...100
- `high`: 80...94
- `moderate`: 65...79 — a typical all-at-baseline day lands here
- `low`: 30...64
- `poor`: 0...29
- `unavailable`: no score

Each band exposes `lowerBound`/`upperBound`/`title`/`color` so the line chart paints the active band behind the value (same pattern as `TrainingLoadInterval`).

Confidence:

- `high`: at least 3 scored components and at least 28 valid baseline days for a core signal.
- `medium`: at least 2 scored components and at least 14 valid baseline days for a core signal.
- `low`: a score exists, but baseline or component coverage is thin — always
  the cap when the autonomic core is neutral-filled (no HRV and no HR data).
- `unavailable`: no score.

Robust baseline:

```text
median = median(prior valid values)
spread = max(1.4826 * medianAbsoluteDeviation, metric-specific floor)
z = (today - median) / spread
```

Baseline window:

- Use prior 56 calendar days.
- Exclude the scored day.
- If at least 28 older valid values remain, exclude the most recent 3 days before the scored day.
- Require 14 valid values for baseline-driven sub-scores.

## File Map

- Create `Body/Models/Readiness/ReadinessModels.swift`
  - `ReadinessStatus` (with `lowerBound`/`upperBound`/`displayOrder` so chart bands can reuse the type), `ReadinessConfidence`, `ReadinessComponentKind`, `ReadinessDriverKind`, `ReadinessComponent`, `ReadinessDriver`, `ReadinessSummary`.
  - `ReadinessStatusBreakdownEntry`, `ReadinessStatusBreakdown` (parallels `TrainingLoadIntervalBreakdown` for the by-status day count chart).
- Create `Body/Models/Readiness/ReadinessScoreCalculator.swift`
  - Pure scoring, baseline math, component scoring, **and a `dailySeries(...)` entrypoint that scores each day in the trend window** so the line chart and by-status breakdown have real data.
- Modify `Body/Models/HealthSummarySnapshot.swift`
  - Add `.readiness` to `HealthMetricKind`.
  - Add `readiness: ReadinessSummary` to `HealthSummarySnapshot`.
  - Add `readiness: HealthTrendSeries` to `HealthTrendSnapshot`.
  - Add Codable fallback support for older cache snapshots.
  - Add `HealthDashboardSnapshot.recalculatingReadiness(on:calendar:)`.
- Modify `Body/Services/HealthKitWorkoutStore.swift`
  - Recalculate Readiness whenever dashboard summary/trends are updated or filtered.
  - Special-case `refreshHealthMetric(.readiness)` to recompute from cached/fetched health dashboard inputs.
- Modify `Body/Models/BodyAppearancePreference.swift`
  - Add Readiness card and trend card ordering, title, subtitle, icon, tint, metric mapping.
- Modify `Body/Views/BodyHomeView.swift`
  - Add Readiness card model and detail model (line chart, same shape as Training Load).
  - Add `BodyReadinessStatusPresentation` (chart band colors per status) and `BodyReadinessStatusBreakdownChart` (Days-by-Status chart rendered below the trend).
  - Add a supplementary "About your score" card with exact status ranges and short interval explanations under the trend section.
  - Extend `BodyHealthMetricDetailModel` (and `metricDetail` helper) with an optional `readiness: ReadinessSummary?` field used only by the Readiness branch.
- Modify `BodyTests/WorkoutMonthSnapshotTests.swift`
  - Add calculator, snapshot Codable, filtering, ordering, and presentation tests.
- Modify `BodyTests/ProjectConfigurationTests.swift`
  - Add static coverage tests for card/detail routing if the current static tests need extension.
- Modify `TestPlan.md`, `README.md`, and `VersionHistory.md`
  - Document the Readiness card, manual checks, and release note.

## Task 1: Add Readiness Model Types

**Files:**

- Create: `Body/Models/Readiness/ReadinessModels.swift`
- Modify: `body.xcodeproj/project.pbxproj`
- Test: `BodyTests/WorkoutMonthSnapshotTests.swift`

- [ ] **Step 1: Write failing model tests**

Add tests near the existing health summary tests:

```swift
func testReadinessStatusMapsScoresToBands() {
    XCTAssertEqual(ReadinessStatus.status(for: nil), .unavailable)
    XCTAssertEqual(ReadinessStatus.status(for: 100), .prime)
    XCTAssertEqual(ReadinessStatus.status(for: 96), .prime)
    XCTAssertEqual(ReadinessStatus.status(for: 95), .high)
    XCTAssertEqual(ReadinessStatus.status(for: 75), .high)
    XCTAssertEqual(ReadinessStatus.status(for: 74), .moderate)
    XCTAssertEqual(ReadinessStatus.status(for: 50), .moderate)
    XCTAssertEqual(ReadinessStatus.status(for: 49), .low)
    XCTAssertEqual(ReadinessStatus.status(for: 25), .low)
    XCTAssertEqual(ReadinessStatus.status(for: 24), .poor)
    XCTAssertEqual(ReadinessStatus.status(for: 0), .poor)
}

func testReadinessSummaryUnavailableIsCodable() throws {
    let summary = ReadinessSummary.unavailable
    let encoded = try JSONEncoder().encode(summary)
    let decoded = try JSONDecoder().decode(ReadinessSummary.self, from: encoded)

    XCTAssertEqual(decoded, summary)
    XCTAssertNil(decoded.score)
    XCTAssertEqual(decoded.status, .unavailable)
    XCTAssertEqual(decoded.confidence, .unavailable)
    XCTAssertTrue(decoded.components.isEmpty)
    XCTAssertTrue(decoded.drivers.isEmpty)
}

func testReadinessStatusExposesBoundsForChartBands() {
    XCTAssertNil(ReadinessStatus.poor.lowerBound)
    XCTAssertEqual(ReadinessStatus.poor.upperBound, 25)
    XCTAssertEqual(ReadinessStatus.low.lowerBound, 25)
    XCTAssertEqual(ReadinessStatus.low.upperBound, 50)
    XCTAssertEqual(ReadinessStatus.moderate.lowerBound, 50)
    XCTAssertEqual(ReadinessStatus.moderate.upperBound, 75)
    XCTAssertEqual(ReadinessStatus.high.lowerBound, 75)
    XCTAssertEqual(ReadinessStatus.high.upperBound, 95)
    XCTAssertEqual(ReadinessStatus.prime.lowerBound, 95)
    XCTAssertNil(ReadinessStatus.prime.upperBound)
}
```

- [ ] **Step 2: Run the focused failing tests**

Run:

```bash
rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO -only-testing:BodyTests/WorkoutMonthSnapshotTests/testReadinessStatusMapsScoresToBands -only-testing:BodyTests/WorkoutMonthSnapshotTests/testReadinessSummaryUnavailableIsCodable -only-testing:BodyTests/WorkoutMonthSnapshotTests/testReadinessStatusExposesBoundsForChartBands
```

Expected: fail because `ReadinessStatus`, `ReadinessSummary`, and the band bounds do not exist.

- [ ] **Step 3: Add model file**

Create `ReadinessModels.swift`:

```swift
import Foundation

enum ReadinessStatus: String, Codable, Equatable {
    case prime
    case high
    case moderate
    case low
    case poor
    case unavailable

    static let displayOrder: [ReadinessStatus] = [.prime, .high, .moderate, .low, .poor]

    static func status(for score: Int?) -> ReadinessStatus {
        guard let score else { return .unavailable }
        switch score {
        case 96...100: return .prime
        case 75...95: return .high
        case 50..<75: return .moderate
        case 25..<50: return .low
        default: return .poor
        }
    }

    var title: String {
        switch self {
        case .prime: return "Prime"
        case .high: return "High"
        case .moderate: return "Moderate"
        case .low: return "Low"
        case .poor: return "Poor"
        case .unavailable: return "Needs Data"
        }
    }

    var lowerBound: Double? {
        switch self {
        case .poor: return nil
        case .low: return 25
        case .moderate: return 50
        case .high: return 75
        case .prime: return 95
        case .unavailable: return nil
        }
    }

    var upperBound: Double? {
        switch self {
        case .poor: return 25
        case .low: return 50
        case .moderate: return 75
        case .high: return 95
        case .prime: return nil
        case .unavailable: return nil
        }
    }
}

struct ReadinessStatusBreakdownEntry: Equatable, Identifiable {
    let status: ReadinessStatus
    let dayCount: Int
    let totalDayCount: Int

    var id: ReadinessStatus { status }

    var fractionOfTotal: Double {
        guard totalDayCount > 0 else { return 0 }
        return Double(dayCount) / Double(totalDayCount)
    }
}

enum ReadinessStatusBreakdown {
    static func entries(
        for series: HealthTrendSeries,
        range: BodyHealthTrendRange,
        calendar: Calendar = .bodyGregorian,
        date: Date = Date()
    ) -> [ReadinessStatusBreakdownEntry] {
        let statuses = series.calendarPoints(to: range, calendar: calendar, date: date)
            .compactMap { point -> ReadinessStatus? in
                guard let value = point.value, value.isFinite else { return nil }
                let status = ReadinessStatus.status(for: Int(value.rounded()))
                return status == .unavailable ? nil : status
            }
        let countsByStatus = Dictionary(grouping: statuses) { $0 }.mapValues(\.count)
        let totalDayCount = countsByStatus.values.reduce(0, +)

        return ReadinessStatus.displayOrder.map { status in
            ReadinessStatusBreakdownEntry(
                status: status,
                dayCount: countsByStatus[status, default: 0],
                totalDayCount: totalDayCount
            )
        }
    }
}

enum ReadinessConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
    case unavailable

    var title: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Provisional"
        case .unavailable: return "Needs more data"
        }
    }
}

enum ReadinessComponentKind: String, Codable, CaseIterable, Equatable {
    case autonomic
    case sleep
    case training
    case vitals

    var title: String {
        switch self {
        case .autonomic: return "Autonomic"
        case .sleep: return "Sleep"
        case .training: return "Training"
        case .vitals: return "Vitals"
        }
    }
}

enum ReadinessDriverKind: String, Codable, Equatable {
    case hrvBelowBaseline
    case heartRateAboveBaseline
    case sleepDurationBelowGoal
    case sleepFragmented
    case trainingLoadElevated
    case respiratoryRateAboveBaseline
    case oxygenSaturationLow
    case wristTemperatureAboveBaseline
    case mostlyTypical
    case needsMoreData
}

struct ReadinessComponent: Codable, Equatable, Identifiable {
    var kind: ReadinessComponentKind
    var score: Int?
    var weight: Double
    var message: String

    var id: ReadinessComponentKind { kind }
}

struct ReadinessDriver: Codable, Equatable, Identifiable {
    var kind: ReadinessDriverKind
    var message: String
    var impact: Double

    var id: ReadinessDriverKind { kind }
}

struct ReadinessSummary: Codable, Equatable {
    var score: Int?
    var status: ReadinessStatus
    var confidence: ReadinessConfidence
    var components: [ReadinessComponent]
    var drivers: [ReadinessDriver]

    static let unavailable = ReadinessSummary(
        score: nil,
        status: .unavailable,
        confidence: .unavailable,
        components: [],
        drivers: [
            ReadinessDriver(
                kind: .needsMoreData,
                message: "Readiness needs more Apple Health history.",
                impact: 0
            )
        ]
    )
}
```

- [ ] **Step 4: Add file to Xcode project**

Add `Body/Models/Readiness/ReadinessModels.swift` to the Body app target in `body.xcodeproj/project.pbxproj` following the existing model-file pattern.

- [ ] **Step 5: Run focused tests again**

Expected: pass.

## Task 2: Add Pure Readiness Calculator Baseline Math

**Files:**

- Create: `Body/Models/Readiness/ReadinessScoreCalculator.swift`
- Modify: `body.xcodeproj/project.pbxproj`
- Test: `BodyTests/WorkoutMonthSnapshotTests.swift`

- [ ] **Step 1: Write failing baseline tests**

```swift
func testReadinessRobustBaselineUsesMedianAndMad() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let values = (1...20).compactMap { offset -> ReadinessScoreCalculator.DailyValue? in
        guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else { return nil }
        return ReadinessScoreCalculator.DailyValue(date: date, value: offset == 1 ? 1000 : 50)
    }

    let baseline = try XCTUnwrap(ReadinessScoreCalculator.robustBaseline(
        for: scoreDay,
        values: values,
        floor: 1,
        calendar: calendar
    ))

    XCTAssertEqual(baseline.validDayCount, 20)
    XCTAssertEqual(baseline.median, 50, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(baseline.spread, 1)
}

func testReadinessRobustBaselineReturnsNilWithTooFewDays() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let values = (1...13).compactMap { offset -> ReadinessScoreCalculator.DailyValue? in
        guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else { return nil }
        return ReadinessScoreCalculator.DailyValue(date: date, value: 50)
    }

    XCTAssertNil(ReadinessScoreCalculator.robustBaseline(
        for: scoreDay,
        values: values,
        floor: 1,
        calendar: calendar
    ))
}
```

- [ ] **Step 2: Run failing baseline tests**

Expected: fail because `ReadinessScoreCalculator` does not exist.

- [ ] **Step 3: Add calculator shell and baseline helpers**

```swift
import Foundation

enum ReadinessScoreCalculator {
    struct DailyValue: Equatable {
        var date: Date
        var value: Double
    }

    struct Baseline: Equatable {
        var median: Double
        var spread: Double
        var validDayCount: Int
    }

    static let baselineDayCount = 56
    static let recentExclusionDayCount = 3
    static let minimumBaselineDayCount = 14

    static func robustBaseline(
        for date: Date,
        values: [DailyValue],
        floor: Double,
        calendar: Calendar = .bodyGregorian
    ) -> Baseline? {
        let scoringDay = calendar.startOfDay(for: date)
        let oldestDay = calendar.date(
            byAdding: .day,
            value: -baselineDayCount,
            to: scoringDay
        ) ?? scoringDay.addingTimeInterval(-Double(baselineDayCount) * 86_400)
        let recentCutoff = calendar.date(
            byAdding: .day,
            value: -recentExclusionDayCount,
            to: scoringDay
        ) ?? scoringDay

        let priorValues = values
            .filter { value in
                let day = calendar.startOfDay(for: value.date)
                return day < scoringDay && day >= oldestDay && value.value.isFinite
            }
            .sorted { $0.date < $1.date }

        let olderValues = priorValues.filter { calendar.startOfDay(for: $0.date) < recentCutoff }
        let baselineValues = olderValues.count >= 28 ? olderValues : priorValues
        let numericValues = baselineValues.map(\.value).sorted()

        guard numericValues.count >= minimumBaselineDayCount else {
            return nil
        }

        let medianValue = median(numericValues)
        let deviations = numericValues.map { abs($0 - medianValue) }.sorted()
        let spread = max(1.4826 * median(deviations), floor)

        return Baseline(
            median: medianValue,
            spread: spread,
            validDayCount: numericValues.count
        )
    }

    static func robustZScore(value: Double, baseline: Baseline) -> Double {
        guard value.isFinite, baseline.spread > 0 else { return 0 }
        return (value - baseline.median) / baseline.spread
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}
```

- [ ] **Step 4: Add file to Xcode project**

Add `Body/Models/Readiness/ReadinessScoreCalculator.swift` to the Body app target.

- [ ] **Step 5: Run focused baseline tests**

Expected: pass.

## Task 3: Score Autonomic, Sleep, Training, And Vitals Components

**Files:**

- Modify: `Body/Models/Readiness/ReadinessScoreCalculator.swift`
- Test: `BodyTests/WorkoutMonthSnapshotTests.swift`

- [ ] **Step 1: Write failing component tests**

Add focused tests using synthetic `HealthTrendSnapshot` and `SleepHistorySnapshot`:

```swift
func testReadinessCalculatorScoresLowHrvAndHighRestingHeartRateBelowHigh() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let trends = readinessTrendSnapshot(
        scoreDay: scoreDay,
        hrvBaseline: 55,
        hrvToday: 30,
        restingHeartRateBaseline: 58,
        restingHeartRateToday: 72,
        trainingLoadToday: 1.0,
        calendar: calendar
    )

    let summary = ReadinessScoreCalculator.summary(
        on: scoreDay,
        healthSummary: .empty,
        trends: trends,
        calendar: calendar
    )

    XCTAssertNotNil(summary.score)
    XCTAssertLessThan(try XCTUnwrap(summary.score), 50)
    XCTAssertEqual(summary.status, .low)
    XCTAssertTrue(summary.drivers.contains { $0.kind == .hrvBelowBaseline })
    XCTAssertTrue(summary.drivers.contains { $0.kind == .heartRateAboveBaseline })
}

func testReadinessCalculatorDoesNotTreatMissingMetricsAsZero() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let trends = readinessTrendSnapshot(
        scoreDay: scoreDay,
        hrvBaseline: nil,
        hrvToday: nil,
        restingHeartRateBaseline: nil,
        restingHeartRateToday: nil,
        trainingLoadToday: 1.0,
        calendar: calendar
    )

    let summary = ReadinessScoreCalculator.summary(
        on: scoreDay,
        healthSummary: .empty,
        trends: trends,
        calendar: calendar
    )

    XCTAssertNotNil(summary.score)
    XCTAssertFalse(summary.components.contains { $0.kind == .autonomic })
    XCTAssertNotEqual(summary.score, 0)
}
```

Add helper builders at the bottom of the test file:

```swift
private func readinessTrendSnapshot(
    scoreDay: Date,
    hrvBaseline: Double?,
    hrvToday: Double?,
    restingHeartRateBaseline: Double?,
    restingHeartRateToday: Double?,
    trainingLoadToday: Double?,
    calendar: Calendar
) -> HealthTrendSnapshot {
    HealthTrendSnapshot(
        sleep: .empty,
        heartRate: .empty,
        restingHeartRate: readinessSeries(
            scoreDay: scoreDay,
            baseline: restingHeartRateBaseline,
            today: restingHeartRateToday,
            calendar: calendar
        ),
        bodyMass: .empty,
        bodyFatPercentage: .empty,
        heartRateVariability: readinessSeries(
            scoreDay: scoreDay,
            baseline: hrvBaseline,
            today: hrvToday,
            calendar: calendar
        ),
        respiratoryRate: .empty,
        oxygenSaturation: .empty,
        bodyMassIndex: .empty,
        activeEnergy: .empty,
        restingEnergy: .empty,
        trainingLoad: readinessSeries(
            scoreDay: scoreDay,
            baseline: trainingLoadToday,
            today: trainingLoadToday,
            calendar: calendar
        )
    )
}

private func readinessSeries(
    scoreDay: Date,
    baseline: Double?,
    today: Double?,
    calendar: Calendar
) -> HealthTrendSeries {
    var points: [HealthTrendDataPoint] = []
    if let baseline {
        for offset in 1...28 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: scoreDay) else {
                continue
            }
            points.append(HealthTrendDataPoint(date: date, value: baseline))
        }
    }
    if let today {
        points.append(HealthTrendDataPoint(date: scoreDay, value: today))
    }
    return HealthTrendSeries(points: points)
}
```

- [ ] **Step 2: Run tests to verify failure**

Expected: fail because `summary(on:healthSummary:trends:calendar:)` is not implemented.

- [ ] **Step 3: Implement component scoring**

Add public summary entrypoint:

```swift
static func summary(
    on date: Date,
    healthSummary: HealthSummarySnapshot,
    trends: HealthTrendSnapshot,
    calendar: Calendar = .bodyGregorian
) -> ReadinessSummary {
    let componentResults = [
        autonomicComponent(on: date, trends: trends, calendar: calendar),
        sleepComponent(on: date, healthSummary: healthSummary, trends: trends, calendar: calendar),
        trainingComponent(on: date, trends: trends, calendar: calendar),
        vitalsComponent(on: date, trends: trends, calendar: calendar)
    ].compactMap { $0 }

    guard !componentResults.isEmpty else {
        return .unavailable
    }

    let availableWeight = componentResults.reduce(0) { $0 + $1.component.weight }
    guard availableWeight > 0 else {
        return .unavailable
    }

    let weightedScore = componentResults.reduce(0) { partialResult, result in
        partialResult + Double(result.component.score ?? 0) * (result.component.weight / availableWeight)
    }
    let score = min(max(Int(weightedScore.rounded()), 0), 100)
    let drivers = prioritizedDrivers(from: componentResults)

    return ReadinessSummary(
        score: score,
        status: ReadinessStatus.status(for: score),
        confidence: confidence(for: componentResults),
        components: componentResults.map(\.component),
        drivers: drivers.isEmpty ? [ReadinessDriver(kind: .mostlyTypical, message: "Readiness signals are mostly typical.", impact: 0)] : drivers
    )
}
```

Use a private result type:

```swift
private struct ComponentResult {
    var component: ReadinessComponent
    var drivers: [ReadinessDriver]
    var bestBaselineDayCount: Int
}
```

Add smooth penalty helpers:

```swift
private static func scoreFromPenaltyProgress(_ progress: Double) -> Int {
    Int((100 - min(max(progress, 0), 1) * 100).rounded())
}

private static func adverseProgress(_ zScore: Double, start: Double = 0.5, full: Double = 2.0) -> Double {
    let normalized = min(max((zScore - start) / (full - start), 0), 1)
    return normalized * normalized * (3 - 2 * normalized)
}
```

Implement component helpers with these floors:

```swift
private enum MetricFloor {
    static let hrv = 5.0
    static let heartRate = 3.0
    static let respiratoryRate = 0.6
    static let oxygenSaturation = 1.0
    static let wristTemperature = 0.2
}
```

Rules:

- HRV adverse score uses `-robustZScore`.
- RHR and sleep HR adverse score uses `robustZScore`.
- Training load uses absolute thresholds: 0 penalty through 1.30, moderate to 1.50, full after 1.50.
- Respiratory and wrist temperature use high-side robust z-score.
- Blood oxygen uses low-side robust z-score and only creates a driver when today is below 95 or adverse z-score is above 1.5.

- [ ] **Step 4: Run focused tests**

Expected: pass.

## Task 4: Add Readiness To Dashboard Snapshots And Cache

**Files:**

- Modify: `Body/Models/HealthSummarySnapshot.swift`
- Test: `BodyTests/WorkoutMonthSnapshotTests.swift`

- [ ] **Step 1: Write failing snapshot tests**

```swift
func testHealthDashboardSnapshotRecalculatesReadinessFromTrends() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let trends = readinessTrendSnapshot(
        scoreDay: scoreDay,
        hrvBaseline: 55,
        hrvToday: 56,
        restingHeartRateBaseline: 58,
        restingHeartRateToday: 58,
        trainingLoadToday: 1.0,
        calendar: calendar
    )

    let dashboard = HealthDashboardSnapshot(
        summary: .empty,
        trends: trends
    ).recalculatingReadiness(on: scoreDay, calendar: calendar)

    XCTAssertNotNil(dashboard.summary.readiness.score)
    XCTAssertEqual(dashboard.trends.readiness.point(on: scoreDay)?.value, Double(try XCTUnwrap(dashboard.summary.readiness.score)))
}

func testHealthSummarySnapshotDecodesOldCacheWithoutReadiness() throws {
    let data = Data("""
    {
      "activityRings": {},
      "sleep": { "duration": null },
      "restingHeartRate": { "value": null },
      "bodyMass": { "value": null },
      "bodyFatPercentage": { "value": null },
      "heartRateVariability": { "value": null },
      "respiratoryRate": { "value": null },
      "oxygenSaturation": { "value": null },
      "bodyMassIndex": { "value": null },
      "activeEnergy": { "value": null },
      "restingEnergy": { "value": null }
    }
    """.utf8)

    let decoded = try JSONDecoder().decode(HealthSummarySnapshot.self, from: data)

    XCTAssertEqual(decoded.readiness, .unavailable)
}
```

- [ ] **Step 2: Run tests to verify failure**

Expected: fail because Readiness fields and recalculation do not exist.

- [ ] **Step 3: Add `HealthMetricKind.readiness`**

In `HealthMetricKind`, add:

```swift
case readiness
```

Add help text:

```swift
case .readiness:
    return HealthMetricDetailHelpText(
        title: "About Readiness",
        body: "Readiness compares your recent sleep, heart, training, respiratory, blood oxygen, and wrist temperature signals with your own baseline. Missing sensors are skipped instead of counted as poor readiness. Treat the score as daily context, not a diagnosis or a guarantee of performance."
    )
```

Add data source text:

```swift
case .readiness:
    return HealthMetricDetailDataSourceText(sourceText: "Calculated from Apple Health")
```

- [ ] **Step 4: Add summary and trend fields**

Add to `HealthSummarySnapshot`:

```swift
var readiness: ReadinessSummary
```

Default to `.unavailable` in `empty`, cache decoding, preview sample data, filtering, and replacement paths.

Add to `HealthTrendSnapshot`:

```swift
var readiness: HealthTrendSeries
```

Default to `.empty` in `empty`, init defaults, Codable fallback, `isEmpty`, `series(for:)`, `replacingMetric`, and `filtered(by:)`.

- [ ] **Step 5: Add daily series backfill to the calculator**

Add a sibling entrypoint that scores every day across an interval so the trend chart and by-interval breakdown have real data, not just one point. This mirrors `TrainingLoadCalculator.dailySeries(from:startDate:endDate:calendar:)` (see `HealthKitWorkoutStore.swift` for usage).

```swift
static func dailySeries(
    healthSummary: HealthSummarySnapshot,
    trends: HealthTrendSnapshot,
    startDate: Date,
    endDate: Date,
    calendar: Calendar = .bodyGregorian
) -> HealthTrendSeries {
    let start = calendar.startOfDay(for: startDate)
    let end = calendar.startOfDay(for: endDate)
    guard start <= end else { return .empty }

    var points: [HealthTrendDataPoint] = []
    var cursor = start
    while cursor <= end {
        let summary = self.summary(
            on: cursor,
            healthSummary: healthSummary,
            trends: trends,
            calendar: calendar
        )
        if let score = summary.score {
            points.append(HealthTrendDataPoint(date: cursor, value: Double(score)))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
    }

    return HealthTrendSeries(points: points)
}
```

Per-day scoring is intentional: each day uses its own rolling 56-day baseline. Cost is bounded by the trend window (up to `BodyHealthTrendRange.maximumDayCount`). Since `summary(on:...)` is pure and already reads from in-memory snapshots, this is in the millisecond range for realistic data.

- [ ] **Step 6: Add dashboard recalculation**

```swift
func recalculatingReadiness(
    on date: Date = Date(),
    calendar: Calendar = .bodyGregorian
) -> HealthDashboardSnapshot {
    var nextSummary = summary
    var nextTrends = trends

    let todaySummary = ReadinessScoreCalculator.summary(
        on: date,
        healthSummary: nextSummary,
        trends: nextTrends,
        calendar: calendar
    )
    nextSummary.readiness = todaySummary

    let oldestOffset = BodyHealthTrendRange.maximumDayCount - 1
    let scoringStart = calendar.date(byAdding: .day, value: -oldestOffset, to: calendar.startOfDay(for: date))
        ?? calendar.startOfDay(for: date)
    nextTrends.readiness = ReadinessScoreCalculator.dailySeries(
        healthSummary: nextSummary,
        trends: nextTrends,
        startDate: scoringStart,
        endDate: date,
        calendar: calendar
    )

    return HealthDashboardSnapshot(
        summary: nextSummary,
        trends: nextTrends,
        activityRingHistory: activityRingHistory
    )
}
```

Rebuilding the series from inputs each call (instead of appending to a cached series) keeps the trend a pure function of the underlying signals — toggling source/permission filters yields a coherent series instead of a mix of pre- and post-filter scores.

- [ ] **Step 7: Run focused snapshot tests**

Expected: pass. Add a test that exercises `dailySeries` over a ≥14-day window with synthetic HRV/RHR/training-load inputs and asserts the returned series has one point per scorable day.

## Task 5: Recalculate Readiness In `HealthKitWorkoutStore`

**Files:**

- Modify: `Body/Services/HealthKitWorkoutStore.swift`
- Test: `BodyTests/ProjectConfigurationTests.swift`

- [ ] **Step 1: Write failing static coverage test**

```swift
func testHealthDashboardUpdatesRecalculateReadinessBeforeSaving() throws {
    let source = try sourceText("Body/Services/HealthKitWorkoutStore.swift")
    let updateStart = try XCTUnwrap(source.range(of: "private func updateHealthDashboardSnapshot(")?.lowerBound)
    let saveStart = try XCTUnwrap(source.range(of: "HealthDashboardSnapshotStore.save(", range: updateStart..<source.endIndex)?.lowerBound)
    let updateBlock = String(source[updateStart..<saveStart])

    XCTAssertTrue(updateBlock.contains(".recalculatingReadiness("))
}
```

- [ ] **Step 2: Run test to verify failure**

Expected: fail because the store does not recalculate Readiness.

- [ ] **Step 3: Update dashboard update path**

Change `updateHealthDashboardSnapshot` to build, filter, and recalculate:

```swift
let filteredSnapshot = HealthDashboardSnapshot(
    summary: summary,
    trends: trends,
    activityRingHistory: activityRingHistory
)
.filtered(by: permissionSelection)
.recalculatingReadiness(on: healthTrendAnchorDate ?? Date(), calendar: calendar)
```

- [ ] **Step 4: Add individual refresh handling**

In `fetchHealthDashboardSnapshot(for:calendar:)`, handle `.readiness` by returning the current cached dashboard recalculated:

```swift
case .readiness:
    return HealthDashboardSnapshot(
        summary: healthSummary,
        trends: healthTrends,
        activityRingHistory: activityRingHistory
    ).recalculatingReadiness(on: healthTrendAnchorDate ?? Date(), calendar: calendar)
```

Also ensure `healthPermission(forMetric:)` returns a permission that does not block Readiness. Use `.heart` only if that function requires a concrete permission, then special-case `.readiness` before the permission guard. Prefer the special-case before the guard.

- [ ] **Step 5: Run focused store test**

Expected: pass.

## Task 6: Add Readiness Card Ordering And Settings Metadata

**Files:**

- Modify: `Body/Models/BodyAppearancePreference.swift`
- Test: `BodyTests/WorkoutMonthSnapshotTests.swift`

- [ ] **Step 1: Write failing ordering tests**

```swift
func testBodyHomeCardKindIncludesReadinessAfterActivityRings() {
    XCTAssertEqual(BodyHomeCardKind.readiness.healthMetricKind, .readiness)
    XCTAssertTrue(BodyHomeCardKind.defaultOrder.contains(.readiness))
    XCTAssertLessThan(
        try XCTUnwrap(BodyHomeCardKind.defaultOrder.firstIndex(of: .readiness)),
        try XCTUnwrap(BodyHomeCardKind.defaultOrder.firstIndex(of: .exerciseMinutes))
    )
    XCTAssertEqual(BodyHomeCardKind.readiness.title, "Readiness")
    XCTAssertEqual(BodyHomeCardKind.readiness.iconName, "bolt.heart.fill")
}

func testBodyHomeTrendCardKindIncludesReadiness() {
    XCTAssertEqual(BodyHomeTrendCardKind.readiness.metricKind, .readiness)
    XCTAssertTrue(BodyHomeTrendCardKind.defaultOrder.contains(.readiness))
    XCTAssertEqual(BodyHomeTrendCardKind.readiness.title, "Readiness")
}
```

- [ ] **Step 2: Run tests to verify failure**

Expected: fail because card kinds do not include Readiness.

- [ ] **Step 3: Add Readiness to `BodyHomeCardKind`**

Add case:

```swift
case readiness
```

Place `.readiness` immediately after `.activityRings` in `defaultOrder`.

Add switch values:

```swift
case .readiness:
    return .readiness
```

```swift
case .readiness:
    return "Readiness"
```

```swift
case .readiness:
    return "Readiness from sleep, strain, and vitals"
```

```swift
case .readiness:
    return "bolt.heart.fill"
```

```swift
case .readiness:
    return Color(red: 0.12, green: 0.68, blue: 0.55)
```

- [ ] **Step 4: Add Readiness to `BodyHomeTrendCardKind`**

Add case and place it first in `defaultOrder`:

```swift
case readiness
```

Switch values:

```swift
case .readiness:
    return "Readiness"
```

```swift
case .readiness:
    return "Readiness score trend"
```

```swift
case .readiness:
    return "bolt.heart.fill"
```

```swift
case .readiness:
    return Color(red: 0.12, green: 0.68, blue: 0.55)
```

- [ ] **Step 5: Run focused ordering tests**

Expected: pass.

## Task 7: Add Summary Card And Detail Routing

**Files:**

- Modify: `Body/Views/BodyHomeView.swift`
- Test: `BodyTests/ProjectConfigurationTests.swift`

- [ ] **Step 1: Write failing static UI routing test**

```swift
func testReadinessCardAndDetailAreRouted() throws {
    let source = try sourceText("Body/Views/BodyHomeView.swift")

    XCTAssertTrue(source.contains("metric(\n                kind: .readiness"))
    XCTAssertTrue(source.contains("case .readiness:"))
    XCTAssertTrue(source.contains("summary.readiness"))
    XCTAssertTrue(source.contains("trends.series(for: .readiness)"))
    XCTAssertTrue(source.contains("BodyReadinessStatusPresentation"))
    XCTAssertTrue(source.contains("BodyReadinessStatusBreakdownChart"))
}
```

- [ ] **Step 2: Run test to verify failure**

Expected: fail because Readiness UI routing is absent.

- [ ] **Step 3: Add Readiness card model**

At the front of `metricCards`, after `let summary` and `let trends`, add:

```swift
metric(
    kind: .readiness,
    title: "Readiness",
    summary: HealthMetricSummary(value: summary.readiness.score.map(Double.init)),
    unit: "",
    decimals: 0,
    symbolName: "bolt.heart.fill",
    symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
    chartStyle: .line,
    chartPreview: trends.series(for: .readiness)
)
```

- [ ] **Step 4: Add Readiness detail model**

Match Training Load's detail-model shape: call the existing `metricDetail(...)` helper so the standard `series`/`daySeries`/`rangeSeries` defaults populate, and wire `highlightedRange` + `highlightedRangeResolver` to the new `BodyReadinessStatusPresentation` (defined in Step 5).

In `detailModel(for:)` add:

```swift
case .readiness:
    let readinessBand = BodyReadinessStatusPresentation.make(for: summary.readiness.score.map(Double.init))
    return metricDetail(
        kind: kind,
        title: "Readiness",
        summary: HealthMetricSummary(value: summary.readiness.score.map(Double.init)),
        unit: "",
        decimals: 0,
        symbolName: "bolt.heart.fill",
        symbolColor: Color(red: 0.12, green: 0.68, blue: 0.55),
        chartStyle: .line,
        highlightedRange: readinessBand,
        highlightedRangeResolver: BodyReadinessStatusPresentation.make(for:),
        readiness: summary.readiness
    )
```

Notes:

- Pass `unit: ""` because `metricDetail` concatenates the unit onto every formatted tick value (e.g. `"82 BPM"`). The status name (`"Typical"`) belongs in the supplementary "About your score" card and on the band label, not on every chart tick.
- Extend `metricDetail` and `BodyHealthMetricDetailModel` with `readiness: ReadinessSummary? = nil` so the Readiness branch can pass the summary through to the breakdown chart and "About your score" card. Other call sites continue to compile unchanged.

- [ ] **Step 5: Add Readiness band presentation and breakdown chart**

Add `BodyReadinessStatusPresentation` (parallels `BodyTrainingLoadIntervalPresentation` at `BodyHomeView.swift:1890`) and `BodyReadinessStatusBreakdownChart` (parallels `BodyTrainingLoadIntervalBreakdownChart` at `BodyHomeView.swift:1933`). Reuse the same row layout helpers (`intervalDistributionRow`, `dayCountBar`, etc.) — either share them across both charts or copy the structure if generalization adds noise.

```swift
private enum BodyReadinessStatusPresentation {
    static func make(for value: Double?) -> BodyHealthMetricTrendHighlightedRange? {
        guard let value, value.isFinite else { return nil }
        let status = ReadinessStatus.status(for: Int(value.rounded()))
        guard status != .unavailable else { return nil }
        return BodyHealthMetricTrendHighlightedRange(
            title: status.title,
            lowerBound: status.lowerBound,
            upperBound: status.upperBound,
            color: color(for: status)
        )
    }

    static func color(for status: ReadinessStatus) -> Color {
        switch status {
        case .prime: return Color(red: 0.84, green: 0.08, blue: 0.92)
        case .high: return Color(red: 0.20, green: 0.74, blue: 1.00)
        case .moderate: return Color(red: 0.10, green: 0.82, blue: 0.20)
        case .low: return Color(red: 1.00, green: 0.75, blue: 0.15)
        case .poor: return Color(red: 1.00, green: 0.25, blue: 0.12)
        case .unavailable: return Color.secondary
        }
    }
}

private extension ReadinessStatus {
    var symbolName: String {
        switch self {
        case .prime: return "sparkles"
        case .high: return "checkmark.circle.fill"
        case .moderate: return "circle.fill"
        case .low: return "exclamationmark.circle.fill"
        case .poor: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        }
    }
}
```

Then add `BodyReadinessStatusBreakdownChart` whose `entries` come from `ReadinessStatusBreakdown.entries(for: series, range: selectedRange, calendar: calendar, date: date)` and whose row colors come from `BodyReadinessStatusPresentation.color(for:)`. Title: `"Days by Status"`.

- [ ] **Step 6: Render the breakdown chart inside the Readiness detail trend section**

Inside the trend card where Training Load already adds its breakdown (currently `if model.kind == .trainingLoad { BodyTrainingLoadIntervalBreakdownChart(...) }` near `BodyHomeView.swift:2703`), add a sibling branch:

```swift
if model.kind == .readiness {
    BodyReadinessStatusBreakdownChart(
        series: model.series,
        selectedRange: selectedTrendRange
    )
    .padding(.top, 4)
}
```

Below the trend card, add a slimmer supplementary section that explains the exact status intervals. This keeps the user-facing guidance aligned with `ReadinessStatus.displayOrder` and the same thresholds used by the calculator:

```swift
if model.kind == .readiness, let readiness = model.readiness {
    readinessWhyCard(for: readiness, activeStatus: activeReadinessStatus)
}
```

```swift
private func readinessWhyCard(for readiness: ReadinessSummary, activeStatus: ReadinessStatus?) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text("About your score")
            .font(.system(size: 18, weight: .bold, design: .rounded))

        ForEach(ReadinessStatus.displayOrder, id: \.self) { status in
            readinessStatusExplanationRow(
                status: status,
                isCurrent: activeStatus == status
            )
        }
    }
    .padding(18)
    .bodyCardBackground()
}
```

- [ ] **Step 7: Run focused UI routing test**

Expected: pass.

## Task 8: Add Readiness Calculator Coverage For Sleep, Training, And Vitals

**Files:**

- Modify: `BodyTests/WorkoutMonthSnapshotTests.swift`
- Modify: `Body/Models/Readiness/ReadinessScoreCalculator.swift`

- [ ] **Step 1: Add failing behavior tests**

Add tests:

```swift
func testReadinessCalculatorPenalizesHighTrainingLoad() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let trends = readinessTrendSnapshot(
        scoreDay: scoreDay,
        hrvBaseline: 55,
        hrvToday: 55,
        restingHeartRateBaseline: 58,
        restingHeartRateToday: 58,
        trainingLoadToday: 1.62,
        calendar: calendar
    )

    let summary = ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar)

    XCTAssertTrue(summary.drivers.contains { $0.kind == .trainingLoadElevated })
    XCTAssertLessThan(try XCTUnwrap(summary.components.first { $0.kind == .training }?.score), 70)
}

func testReadinessCalculatorCreatesLowConfidenceForThinHistory() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let trends = HealthTrendSnapshot.empty

    let summary = ReadinessScoreCalculator.summary(on: scoreDay, healthSummary: .empty, trends: trends, calendar: calendar)

    XCTAssertNil(summary.score)
    XCTAssertEqual(summary.confidence, .unavailable)
}
```

- [ ] **Step 2: Run tests to verify failure**

Expected: fail until component scoring handles these branches.

- [ ] **Step 3: Complete component logic**

Complete Sleep, Training, and Vitals scoring:

- Sleep duration score uses `duration / BodySleepDurationGoal.defaultDuration`, capped at 1.0.
- Sleep continuity uses awake duration divided by sleep window duration when stage interval exists.
- Training score uses:

```swift
private static func trainingLoadScore(_ value: Double) -> (score: Int, driver: ReadinessDriver?) {
    guard value.isFinite else { return (100, nil) }
    if value <= 1.30 {
        return (100, nil)
    }
    let progress = min(max((value - 1.30) / 0.20, 0), 1)
    return (
        scoreFromPenaltyProgress(progress),
        ReadinessDriver(
            kind: .trainingLoadElevated,
            message: "Training load is elevated.",
            impact: progress
        )
    )
}
```

- Vitals score uses the maximum anomaly progress from respiratory rate, oxygen saturation, and wrist temperature.

- [ ] **Step 4: Run full calculator test group**

Run:

```bash
rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO -only-testing:BodyTests/WorkoutMonthSnapshotTests
```

Expected: pass.

## Task 9: Permission Filtering And Source Selection Rules

**Files:**

- Modify: `Body/Models/HealthSummarySnapshot.swift`
- Modify: `Body/Models/BodyAppearancePreference.swift`
- Modify: `Body/Services/HealthKitWorkoutStore.swift`
- Test: `BodyTests/WorkoutMonthSnapshotTests.swift`

- [ ] **Step 1: Write failing permission tests**

```swift
func testReadinessIsNotSourceSelectable() {
    XCTAssertFalse(HealthMetricKind.readiness.supportsHealthDataSourceSelection)
    XCTAssertFalse(HealthMetricKind.readiness.supportsSecondaryHealthDataSourceSelection)
}

func testFilteringHeartPermissionLowersReadinessConfidenceInsteadOfRemovingReadinessCard() throws {
    let calendar = Calendar.bodyGregorian
    let scoreDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 17)))
    let dashboard = HealthDashboardSnapshot(
        summary: .empty,
        trends: readinessTrendSnapshot(
            scoreDay: scoreDay,
            hrvBaseline: 55,
            hrvToday: 30,
            restingHeartRateBaseline: 58,
            restingHeartRateToday: 72,
            trainingLoadToday: 1.0,
            calendar: calendar
        )
    ).filtered(by: BodyHealthPermissionSelection(selectedPermissions: [.workouts]))
     .recalculatingReadiness(on: scoreDay, calendar: calendar)

    XCTAssertNotEqual(dashboard.summary.readiness.confidence, .high)
}
```

- [ ] **Step 2: Run tests to verify failure**

Expected: fail until Readiness source/permission handling is explicit.

- [ ] **Step 3: Update source-selection extensions**

Ensure `.readiness` is absent from:

- `HealthMetricKind.sourceSelectableKinds`
- `supportsHealthDataSourceSelection`
- `supportsSecondaryHealthDataSourceSelection`
- `supportedComparisonCharts` unless Readiness comparison charts are intentionally supported

- [ ] **Step 4: Run permission tests**

Expected: pass.

## Task 10: Documentation And Manual Test Plan

**Files:**

- Modify: `TestPlan.md`
- Modify: `README.md`
- Modify: `VersionHistory.md`

- [ ] **Step 1: Update manual test plan**

Add a row:

```markdown
| M36 | High | Readiness card and detail | Open Summary after refreshing Health data with sleep, heart, workout, respiratory, blood oxygen, and wrist temperature permissions enabled | Readiness appears near the top of Summary, shows a 0-100% score with Prime/High/Moderate/Low/Poor status, opens a detail screen with confidence, trend chart, days-by-status chart, and an About section listing exact status ranges with short explanations; scrubbing the trend moves the Current label to the selected interval; Settings > Metrics > Summary Cards labels Readiness as Beta; disabling individual permissions lowers confidence or removes related drivers without crashing |
```

- [ ] **Step 2: Update README**

Add Readiness to the Summary metrics list:

```markdown
- Readiness score based on personal baselines for sleep, heart, training load, respiratory, blood oxygen, and wrist temperature signals.
```

- [ ] **Step 3: Update VersionHistory**

Add:

```markdown
- Added a Readiness Summary card that compares sleep, heart, training load, and sleep-window vitals against personal baselines, with confidence and driver explanations for missing or unusual signals.
```

- [ ] **Step 4: Run markdown/source sanity checks**

Run:

```bash
rtk rg -n "Readiness|readiness" ReadinessMetrics.md TestPlan.md README.md VersionHistory.md
```

Expected: each file contains intentional Readiness references.

## Task 11: Final Verification

**Files:**

- All modified files from earlier tasks.

- [ ] **Step 1: Check worktree scope**

Run:

```bash
rtk git status --short
```

Expected: only Readiness-related files are modified by this implementation, plus pre-existing unrelated local changes.

- [ ] **Step 2: Run focused tests**

Run:

```bash
rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO -only-testing:BodyTests/WorkoutMonthSnapshotTests -only-testing:BodyTests/ProjectConfigurationTests
```

Expected: pass.

- [ ] **Step 3: Run full test gate**

Run:

```bash
rtk xcodebuild test -project body.xcodeproj -scheme Body -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /private/tmp/body-test-derived CODE_SIGNING_ALLOWED=NO
```

Expected: pass. If Simulator reports `Busy` after compile, run the build fallback.

- [ ] **Step 4: Run generic iOS build fallback if simulator is unavailable**

Run:

```bash
rtk xcodebuild -project body.xcodeproj -scheme Body -destination generic/platform=iOS -derivedDataPath /private/tmp/body-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: build succeeds.

- [ ] **Step 5: Final implementation summary**

Report:

- RTK path used.
- Files changed.
- Tests run and exact result.
- Any Simulator/system-service failure separated from real compile or assertion failures.
- Remaining risks, especially Readiness validation against real Apple Health data.

## Known Risks

- Apple Health HRV is SDNN, while much readiness literature uses RMSSD or lnRMSSD. The plan weights HRV as one autonomic signal rather than the dominant signal.
- Wearable sleep stages are less reliable than sleep duration and sleep/wake detection. The plan weights stages lightly.
- Blood oxygen has measurement variability, especially in low ranges. The plan uses it conservatively as an anomaly signal.
- Training load ratio is useful context but contested as an injury-risk tool. The UI copy must not imply injury prediction.
- Real-device HealthKit data distribution will vary. After implementation, the scoring constants should be reviewed against exported local Health data before release.

## References

- Apple HealthKit HRV uses SDNN: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifierheartratevariabilitysdnn
- HRV-guided training meta-analysis: https://www.mdpi.com/2076-3417/10/23/8532
- ACWR evidence and controversy: https://pmc.ncbi.nlm.nih.gov/articles/PMC8138569/
- Sleep interventions and athletic performance: https://link.springer.com/article/10.1186/s40798-023-00599-z
- Wearable sleep staging reliability: https://www.nature.com/articles/s41746-024-01016-9
- Wearable vitals and illness-related physiological changes: https://www.nature.com/articles/s41746-020-00363-7
- Apple Watch SpO2 accuracy meta-analysis: https://www.nature.com/articles/s41746-025-02238-1
