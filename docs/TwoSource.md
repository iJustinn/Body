# Two-Source Health Data Idea

## Summary

Body could display the same health metric from two different data sources on one detail chart. The first candidate is the HRV detail page, with one series from Apple Watch through Apple Health and another series from a Fitbit wristband, either through Apple Health if Fitbit-originated data is available there, or through a direct Fitbit integration.

The goal is not to merge the values into one average. The goal is to preserve source identity and let the user compare trends from each device.

## HRV Example

On the HRV page, the chart could show:

- Apple Watch / Apple Health HRV as one line.
- Fitbit HRV as a second line.
- A legend that clearly labels each source.
- Optional source toggles so the user can show Apple only, Fitbit only, or both.

Example legend labels:

- Apple Watch SDNN
- Fitbit RMSSD

The exact label matters because Apple Health HRV and Fitbit HRV may not be the same calculation. Apple Health exposes heart rate variability as SDNN in milliseconds. Fitbit commonly reports sleep-based HRV as RMSSD. They can both be useful, but they should not be presented as identical measurements without explanation.

## Current Body Shape

Body currently treats each health metric trend as one `HealthTrendSeries`.

For HRV, `HealthKitWorkoutStore` fetches `.heartRateVariabilitySDNN`, groups samples by day, and produces one daily series. That means samples from multiple HealthKit sources would currently be blended into one daily value.

To support two visible sources, Body would need to keep source metadata through the pipeline instead of discarding it during aggregation.

## Data Paths

### Option 1: HealthKit as the hub

If Fitbit-originated data is written into Apple Health, Body can read it through HealthKit along with Apple Watch data.

Implementation idea:

- Read HRV samples from HealthKit.
- Use each sample's source metadata to identify the producing app/device.
- Group samples by source and by day.
- Build one chart series per source.
- Render the selected sources together on the HRV chart.

This is the cleanest app-side path because Body already has HealthKit permission, fetch, storage, and chart infrastructure.

Open question: whether Fitbit HRV data is actually written into Apple Health on iOS, and under what source name. This needs device/app testing.

### Option 2: Direct Fitbit integration

If Fitbit does not write the needed HRV data into Apple Health, Body could fetch Fitbit data directly from Fitbit's API.

Implementation idea:

- Add Fitbit OAuth sign-in.
- Request only the needed scopes.
- Store and refresh tokens securely.
- Fetch Fitbit HRV data for the chart range.
- Normalize units, dates, time zones, and sleep-window semantics.
- Store Fitbit data as a separate source series.

This is more powerful but significantly larger. It adds account connection UX, network sync, token handling, privacy policy implications, API limits, error states, and possible Fitbit approval requirements.

## Proposed Model Direction

Instead of changing every metric immediately, start with a source-aware trend model for HRV.

Conceptually:

```swift
struct HealthSourceSeries {
    var sourceID: String
    var displayName: String
    var metricLabel: String
    var points: [HealthTrendDataPoint]
}

struct SourceGroupedHealthTrendSeries {
    var sources: [HealthSourceSeries]
}
```

The existing single-source `HealthTrendSeries` can stay in place for current charts. HRV can be the first detail page to opt into source-grouped rendering.

## Chart Behavior

Recommended HRV chart behavior:

- Show each source as a separate colored line.
- Include a compact legend near the chart title or under the chart.
- Use the same y-axis because both values are milliseconds.
- Do not average Apple and Fitbit into one displayed value.
- If the user selects a point, show values for each source on that day when available.
- If one source has no value for a day, leave a gap rather than inventing a value.

For the top summary number, choose one of these product decisions:

- Show the user's preferred source.
- Show the most recent Apple Health value and keep Fitbit as comparison only.
- Show two compact values side by side.

The least confusing first version is probably to keep the current headline value as the primary Apple Health value, then add the second Fitbit source to the chart and legend.

## Deduplication And Trust Rules

Avoid silent merging. Two devices can record overlapping data on the same day, and HealthKit may already apply source priority in Apple Health UI. Body should make its own behavior explicit.

Recommended rules:

- For source comparison charts, never dedupe across sources.
- For single summary cards, use one preferred source or HealthKit's effective current value.
- For combined totals like steps, energy, or exercise minutes, design source priority before summing anything.
- For HRV, present source lines separately because device algorithms and measurement windows can differ.

## Privacy And UX Notes

- Explain that source comparison is informational, not a medical diagnostic tool.
- Make the connected source visible in Settings.
- Let the user disconnect Fitbit and remove cached Fitbit data.
- Keep HealthKit-only behavior working when no Fitbit account is connected.
- If Fitbit data is imported through Apple Health, avoid implying Body has a direct Fitbit connection.

## Suggested First Implementation Slice

1. Add source-aware HRV fetch from HealthKit only.
2. Display multiple HealthKit HRV sources on the HRV detail chart.
3. Test with real Apple Watch data and any Fitbit/imported samples available in Apple Health.
4. Only consider direct Fitbit OAuth/API after confirming HealthKit cannot provide the needed source-separated Fitbit data.

This keeps the first version local-first and aligned with Body's existing Apple Health architecture.
