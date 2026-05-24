# Readiness Card Design

## Goal

Add a Summary card named Readiness that estimates a user's near-term readiness state from Apple Health data already collected by Body. The score should be useful for day-to-day training decisions, but it must avoid medical claims and avoid presenting a proprietary-style readiness number as objective truth.

Readiness is a personal-baseline score. The same raw HRV, resting heart rate, respiratory rate, or blood oxygen value can mean different things for different users, so the algorithm compares today's signals against the user's recent valid history.

## Product Shape

The Summary card shows:

- Title: `Readiness`
- Primary value: integer score from 0 to 100
- Status label: `Ready`, `Typical`, `Strained`, or `Low`
- Preview: recent readiness scores when enough historical data exists

The detail screen shows:

- Header card with score, status, confidence, and 2 to 3 driver messages
- Component rows for Autonomic, Sleep, Training, and Vitals
- Trend chart across existing ranges
- About card explaining that Body compares recent signals to the user's own baseline and that missing sensors are skipped

Driver examples:

- `HRV below baseline`
- `Sleep duration below goal`
- `Training load elevated`
- `Respiratory rate above baseline`
- `Vitals mostly typical`

## Inputs

Use existing app data first:

- Sleep history and sleep-window vitals from `SleepHistorySnapshot`
- HRV from `heartRateVariabilitySDNN`
- Resting heart rate and sleep-window heart rate
- Training load ratio from the existing 7-day acute / 42-day chronic EWMA calculator
- Respiratory rate
- Blood oxygen
- Wrist temperature

Do not require every input. Missing metrics reduce confidence and reweight available components.

## Baseline Model

For each metric, compute a robust personal baseline from prior valid days:

- Normal baseline window: previous 56 days
- Minimum provisional window: 14 valid days
- Exclude the scored day
- Prefer excluding the most recent 3 days from baseline when at least 28 older valid values exist
- Baseline center: median
- Baseline spread: median absolute deviation, scaled with `1.4826 * MAD`
- Fallback spread: small metric-specific floor to prevent division by near-zero spread

Robust z-score:

```text
z = (todayValue - baselineMedian) / max(1.4826 * MAD, metricFloor)
```

For metrics where lower is worse, invert the sign before scoring.

## Score Model

Readiness starts at 100 and subtracts weighted penalties.

```text
Readiness = clamp(100 - weightedPenalty, 0, 100)
```

Component weights:

- Autonomic strain: 30%
- Sleep readiness: 30%
- Training pressure: 25%
- Vitals and illness-like anomalies: 15%

Within a component, average available sub-scores. If a component has no usable inputs, omit it and renormalize the remaining component weights.

### Autonomic Strain

Inputs:

- HRV, preferably sleep-window HRV when available
- Resting heart rate
- Sleep-window heart rate

Rules:

- HRV below baseline increases penalty.
- RHR or sleep HR above baseline increases penalty.
- HRV above baseline is normally positive or neutral. Very high HRV should only apply a small caution penalty when paired with elevated HR, poor sleep, or high training pressure.

Penalty shape:

```text
penaltyProgress = smoothstep(start: 0.5, full: 2.0, adverseZ)
```

### Sleep Readiness

Inputs:

- Sleep duration versus configured sleep goal
- Sleep efficiency from awake time inside the sleep window
- Start-time consistency versus recent sleep-start baseline
- Deep and REM percentages as minor signals only

Rules:

- Weight duration and continuity more than sleep stages.
- Treat sleep stages as advisory because consumer wearable staging is less reliable than sleep/wake and total sleep time.
- Reuse the app's existing Sleep Score concepts where practical, but avoid making Readiness equal to Sleep Score.

### Training Pressure

Inputs:

- Existing Training Load ratio
- Optional recent daily load spike when raw daily load is available

Rules:

- 0.80 to 1.30 is neutral.
- 1.31 to 1.50 is moderate pressure.
- Above 1.50 is high pressure.
- Very low load should not heavily reduce Readiness. It can lower training readiness context, but it is not a readiness deficit by itself.

Training load is a context signal, not an injury prediction.

### Vitals And Illness-Like Anomalies

Inputs:

- Respiratory rate
- Blood oxygen
- Wrist temperature

Rules:

- Respiratory rate above baseline adds penalty.
- Wrist temperature above baseline adds penalty.
- Blood oxygen should be conservative: penalize persistent low readings, large drops from personal baseline, or values below common clinical caution ranges, but keep copy non-diagnostic.
- Prefer max anomaly over averaging many correlated anomaly flags so one bad sensor does not dominate the full score.

## Status Bands

Use score plus confidence:

- `Ready`: 85 to 100
- `Typical`: 70 to 84
- `Strained`: 50 to 69
- `Low`: 0 to 49

If confidence is low, show `Provisional` in the detail screen and avoid strong driver language.

## Confidence

Compute confidence from input coverage and baseline quality:

- High: at least 3 components, at least 28 valid baseline days for core autonomic or sleep inputs
- Medium: at least 2 components, at least 14 valid baseline days for one core input
- Low: fewer than 2 components or baseline is too short

The Summary card can show a score with low confidence, but the detail screen should explain that Body needs more nights of data to personalize Readiness.

## Data Model

Add dedicated readiness models rather than expanding generic metric summaries too far:

```swift
struct ReadinessSummary: Codable, Equatable {
    var score: Int?
    var status: ReadinessStatus
    var confidence: ReadinessConfidence
    var components: [ReadinessComponent]
    var drivers: [ReadinessDriver]
}

struct ReadinessTrendSnapshot: Codable, Equatable {
    var series: HealthTrendSeries
}
```

The calculator should live separately from the HealthKit store:

```swift
enum ReadinessScoreCalculator {
    static func summary(
        on date: Date,
        trends: HealthTrendSnapshot,
        sleepHistory: SleepHistorySnapshot,
        calendar: Calendar
    ) -> ReadinessSummary
}
```

HealthKit should keep fetching raw health data. The calculator should transform existing snapshots into readiness output.

## Implementation Scope

1. Add readiness model and calculator tests.
2. Generate today's readiness summary and recent readiness trend from cached/fetched health trends.
3. Add `.readiness` to Summary card ordering and metric display.
4. Add Readiness detail screen content using existing card and chart patterns.
5. Add About copy and manual test plan entries.

Avoid direct HealthKit query changes unless an existing trend needed by Readiness is missing.

## Test Plan

Unit tests:

- New user with insufficient baseline returns low confidence.
- Missing sensors reweight available components without treating missing values as zero.
- Low HRV plus high RHR lowers Autonomic.
- Adequate sleep with normal vitals keeps Sleep and Vitals strong.
- Short, fragmented sleep lowers Sleep even when HRV is normal.
- Training load above 1.50 lowers Training.
- Elevated respiratory rate and wrist temperature create anomaly drivers.
- Low blood oxygen only affects score when persistent or meaningfully low.
- Readiness score clamps to 0...100.

Integration/UI tests where practical:

- Readiness appears in Summary card ordering.
- Disabled permissions remove affected readiness inputs and lower confidence rather than crashing.
- Card and detail render with no score, provisional score, and high-confidence score.

## Research Notes

- Apple HealthKit HRV uses SDNN, not RMSSD. This matters because much readiness literature uses RMSSD or lnRMSSD. Source: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifierheartratevariabilitysdnn
- HRV-guided training can improve endurance markers, but meta-analysis did not find clear superiority over predefined training. Source: https://www.mdpi.com/2076-3417/10/23/8532
- ACWR-style training load commonly uses 7-day acute and 3 to 6 week chronic windows with an often-cited 0.8 to 1.3 range, but the evidence is contested. Source: https://pmc.ncbi.nlm.nih.gov/articles/PMC8138569/
- Sleep extension and naps have the strongest sleep-intervention support for athlete performance and readiness outcomes, though evidence quality varies. Source: https://link.springer.com/article/10.1186/s40798-023-00599-z
- Wearable sleep staging is promising but less reliable than sleep/wake and total sleep time; use stages lightly. Source: https://www.nature.com/articles/s41746-024-01016-9
- Wearable respiratory rate, HR, HRV, sleep, and steps can reflect illness-related physiological changes, but this should be treated as anomaly context, not diagnosis. Source: https://www.nature.com/articles/s41746-020-00363-7
- Apple Watch SpO2 has low mean bias in normoxic ranges but wide limits of agreement and more variability in hypoxic ranges. Source: https://www.nature.com/articles/s41746-025-02238-1
