# Body Radar — Beta 2 refinement plan

Prepared September 6, 2026. Status: exploration and proposal only; no app code changed.
Code reviewed at `087ea62`, with the existing working tree left intact.

Source clarification: the user confirmed that Body's results and the original CSV use Apple Watch measurements, while Oura's results use Oura's own measurements. A follow-up review of the newly supplied Oura measurements is pending locating that file; the analysis below currently covers the original files only.

## Recommendation

Make Beta 2 a more trustworthy detector of unusual overnight strain: validate the input night, distinguish incomplete data from a reassuring result, explain combined changes, and evaluate respiratory decreases and short-lived persistence. Keep the current personal robust baseline and morning-result concept.

Do not start by lowering all thresholds to reproduce Oura. The supplied data does not establish that Oura's five selected alerts are illness events. These are separate devices measuring the same person, so disagreement can reflect their measurement methods, sampling windows, and algorithms. First compare each device's changes against its own history and make exact Body replay possible; then compare a small number of interpretable candidates.

The recommended implementation order is **input/record correctness → explanations → controlled scoring experiments → versioned rollout**. Beta 2 should not ship a new sensitivity setting until the replay and prospective checks below support it.

## Evidence reviewed

All originals remain in `~/Downloads`; no raw health export or screenshot was copied into the repository. This plan includes selected personal measurements for the requested analysis.

| File | What it establishes |
| --- | --- |
| `IMG_4857.PNG` | Oura: August 20, Minor signs; combined-change explanation, no individual biometric highlighted |
| `IMG_4856.PNG` | Oura: August 21, Minor signs; same explanation |
| `IMG_4855.PNG` | Oura: August 22, Minor signs; same explanation |
| `IMG_4854.PNG` | Oura: September 3, Major signs; same explanation |
| `IMG_4853.PNG` | Oura: September 6, Minor signs; respiratory rate **13.5/min, decreased** |
| `IMG_3448.PNG` | Current Body: latest **No Signs**, August 17–September 6 chart, two pink Minor dots and two dim placeholder dots |
| `health_data_2026-06-01_to_2026-09-06.csv` | Apple Watch data, confirmed by user; 98 unique, consecutive daily rows; six measurement columns |

The screenshot dates are consistent with 2026 and the export; their day labels do not independently display a year. Only explicitly selected Oura dates are treated as firm comparison labels. Gaps and connecting segments in Oura's overview are not a complete daily verdict export.

Counting the 21 evenly spaced Body chart slots suggests Minor on August 23 and August 31, with dim/unscored slots on August 29–30. These historical dates are **visual inferences**, not confirmed scrubbed records. The chart does not identify whether a dim slot means missing sleep or calibration. September 6's No Signs headline is directly visible.

### CSV coverage and limits

| Column | Available / 98 | Median | Range | Relationship to Radar input |
| --- | --- | --- | --- | --- |
| Average heart rate, bpm | 98 | 67.515 | 51.17–106.76 | Daily average; not sleeping heart rate |
| Resting heart rate, bpm | 98 | 63.00 | 49.99–80.00 | Exploratory proxy only; not sleeping heart rate |
| Respiratory rate, breaths/min | 97 | 15.31 | 13.50–17.69 | Apple Watch; exact aggregation window not supplied |
| Sleeping wrist temperature, °C | 85 | 35.73 | 35.37–36.33 | Apple Watch overnight quantity; exact wake-day alignment still needs confirmation |
| HRV SDNN, ms | 98 | 58.875 | 16.43–180.16 | Daily SDNN; no overnight sample counts/windows |
| Steps | 98 | 5,148 | 457–22,037 | Daily total cannot reconstruct hourly inactivity |

Respiratory rate is absent August 7. Temperature is absent on 13 dates, including September 6. The final row is the current day and must be treated as potentially incomplete: 457 steps, no temperature, SDNN 180.16. This does not establish that SDNN is erroneous; inspect its samples and timing before judging it.

Missing from the export: sleep intervals/duration, sleep-window heart rate and SDNN, sample counts/timestamps, exact source identifiers/model and selection settings, hourly step completeness, workout timing, frozen Radar records, and symptom/context labels. Device family is confirmed as Apple Watch. CSV blanks remain missing, never zero.

**Cross-device difference:** September 6 respiratory rate is 15.03 from Apple Watch versus 13.5 in Oura. Different devices explain why equality should not be expected; this difference alone is not evidence of a Body ingestion bug. Compare each value with that device's own preceding respiratory baseline. The Apple Watch CSV's 13.5 occurs July 19; that coincidence provides no evidence for shifting dates.

### Exploratory Beta 1 formula replay

I ran a local JavaScript calculation using resting HR in place of sleeping HR, CSV respiratory rate/temperature/daily SDNN, and no inactivity. It uses the actual Beta 1 56-day window, exclusion fallback, median/MAD floors, normalized deviation, weights and classification gates described below. It cannot reproduce sleep eligibility, source selection, recent qualified-night coverage, freezing, or late sync. **These are proxy calculations, not actual Body verdicts or an accuracy test.**

| Date | Selected Oura result | Proxy Beta 1 evidence | Proxy class |
| --- | --- | ---: | --- |
| Aug 20 | Minor | 0.000 | No Signs |
| Aug 21 | Minor | 0.000 | No Signs |
| Aug 22 | Minor | 0.000 | No Signs |
| Sep 3 | Major | 0.000 | No Signs |
| Sep 6 | Minor, respiratory decrease | 0.000 | No Signs |

Across 98 rows: 14 lack baseline history, 74 produce No Signs, 9 Minor, and 1 Major. The Major proxy is August 29 (evidence 2.365). Recent Minor proxies include August 23 (1.535), August 28 (1.968), and August 30 (1.852). The disagreement with Body's dim August 29–30 slots and apparent August 31 Minor is another reason exact sleep inputs and frozen records are necessary.

Two examples make the mismatch concrete:

- September 3: resting HR 58 vs baseline median 62.5; respiratory rate 14.82 vs 15.295; temperature 35.66 vs 35.655; SDNN 61.58 vs 59.09. Beta 1's directional evidence is zero. Simply lowering a positive aggregate threshold cannot recreate Oura's Major here.
- August 23: temperature 36.31 vs median 35.655, robust spread 0.214977. Normalized deviation is 1.523419, giving `1.5 × (1.523419 − 0.5) = 1.535128` evidence. Other proxy signals contribute zero. The temperature-driven Minor is consistent with the apparent Body chart point, but does not verify its exact inputs.

Reproduction specification: parse dates as calendar days; for scoring day D, select finite metric values in `[D−56, D)`; use `[D−56, D−3)` only if it has at least 28 values, otherwise use all prior values; require 14 values; apply the formulas below. Skip a missing current value. Use RHR/respiration/temperature/SDNN floors 3/0.6/0.2/5, respectively. Omit sleep gates and inactivity explicitly. Treat the first 14 rows as baseline-unavailable.

CSV SHA-256: `51bb971dd7612af0c5370d2b8c57fdcc1efbe21db9f3da908d1a129347e50f6a`.

## Current Beta 1 behavior

Primary code: `BodyMetricsKit/BodyRadarCalculator.swift`, `BodyRadarModels.swift`, `VitalsSnapshot.swift`, `ReadinessScoreCalculator.swift`; integration in `HealthSummarySnapshot.swift` and `Body/Services/HealthKitWorkoutStore.swift`; presentation in `BodyRadarChart.swift` and Home/detail views.

1. File each sleep summary under the wake day. Require at least three hours with an ended wake cycle when stages exist; trust vitals-only backfilled summaries when stages are absent.
2. Build separate 56-day histories per signal. Require 14 previous observations per baseline. Exclude the latest three days only when at least 28 older observations remain.
3. Use `spread = max(1.4826 × MAD, floor)` and `d = clamp((value − median) / (2 × spread), −3, 3)`. **One d unit is two robust spreads, not one standard deviation.**
4. Orient HRV downward; all other signals upward. Weight temperature 1.5, HR/respiration/HRV 1 each, inactivity 0.5. Sum `weight × max(0, directional_d − 0.5)`.
5. Flag an individual signal only above directional d = 1. Minor begins at evidence 0.75. Major needs evidence ≥2 and at least two individually flagged signals. One extreme signal can only yield Minor.
6. Require seven nights in the last 14 with at least one overnight vital, but today's score needs only one baseline-backed signal. Recency is pooled across signals rather than checked for each usable channel.
7. Previous-day inactivity counts hours after wake until 22:00 with fewer than 200 steps. Any workout masks that day's inactivity. One sampled hour makes a day eligible, after which missing buckets default to zero steps.
8. Freeze at wake +10 minutes or 10:00 when wake is unknown. Missing sleep is not frozen; **Calibrating can be frozen**. Existing records win over later data. History prefers frozen nights and backfills scored gaps; recent chart holds 21 nights, record cap 60.
9. The record-context signature includes permissions/source selections/grouping/sleep parsing, but no explicit Radar algorithm version.

Beta 1 already sums subthreshold contributions: Minor with no individually flagged vital is possible. Its limitation is specifically the **Major flag-count gate**, plus absent temporal evidence and one-way respiration—not a complete lack of multimetric scoring.

## Beta 2 design

### 1. Establish a reproducible input contract

Maintain two independent analysis tracks: Apple Watch inputs → Body/Beta 2 candidates, and Oura measurements → within-Oura deviations compared with Oura's displayed verdicts. Never pool the devices' raw values into a shared baseline. Compare same-night direction, relative magnitude and persistence only after establishing units, measurement definitions and wake-day alignment. An Oura alert with no corresponding Apple Watch deviation is a cross-device disagreement, not automatically a Body algorithm failure.

For the new Oura file, inspect date coverage, missingness, sleep windows, average versus lowest/resting HR, HRV statistic, and whether temperature is absolute or a deviation from Oura's own reference. Keep temperature deviations distinct from Apple Watch absolute wrist temperature, and retain any reference-baseline caveat when analyzing an already normalized Oura field. Do not apply the Apple Watch SDNN floor to an Oura HRV series with a different definition without an explicitly labeled sensitivity experiment.

Add a development-only local export/replay path for the actual nightly inputs. One row/record per wake day should contain:

- Canonical wake day, timezone/calendar context, sleep interval, duration, stage availability and main-sleep eligibility.
- Each sleep-window value, unit/HRV type, selected and effective source identity, valid sample count and temporal coverage when available. Preserve raw readings; transformations belong inside scoring only.
- For each signal: baseline median, spread, baseline count and recency, signed deviation, contribution, and reason for exclusion.
- Previous-day activity inputs and completeness if retained; current/provisional/frozen status, freeze time, algorithm version and record context.
- Existing Beta 1 evidence/state and enough prior inputs to replay it. Obtain 56 days before the first comparison date where possible; explicitly label incomplete warm-up history.

Keep SDNN separate from RMSSD. The export explicitly labels SDNN; no conversion or substitution should be inferred. Keep daytime averages separate from sleep-window observations. Source compatibility applies to baseline history as well as frozen results.

Success: exact-input replay matches the production calculator's evidence to a tight floating-point tolerance and matches states, exclusion reasons and freeze behavior exactly. Investigate mismatches before changing scoring.

### 2. Fix data sufficiency and finalization first

Proposed Beta 2 minimum: at least **two usable overnight physiological channels**, each with the existing 14-day baseline and seven valid observations in the last 14 days including the current night. Inactivity never satisfies this minimum. Device capability may remove temperature or respiration; HR + HRV should remain a supported two-channel case. The stricter per-channel coverage rule is provisional and must be measured for excessive unavailable nights.

Distinguish insufficient baseline (Calibrating), no qualifying sleep (Missing Sleep), and an otherwise eligible night lacking enough usable current data (Insufficient Data). Map these states consistently to muted chart slots and useful accessibility text; none should render as No Signs.

Freeze only scored nights, after relevant overnight hydration attempts have settled and the existing wake-delay gate is open. Failed or incomplete queries must remain retryable; do not wait indefinitely for a sensor the device lacks. Once a sufficiently supported scored result is finalized, keep it stable through routine same-day refreshes. A nap must not replace the main night. Deliberate source/context changes still invalidate incompatible records.

Preserve the existing timing initially; do not invent a longer fixed delay without sync evidence. Test a late temperature arrival before and after finalization explicitly. Historical backfill must use the same completeness contract.

### 3. Remove unsupported inactivity evidence

Recommended initial Beta 2 policy: **omit inactivity from the scored evidence until observation completeness is demonstrable**. Retain the model's legacy enum/coding compatibility as needed. This reduces a questionable source of both alerts and query work; measure the loss of legitimate corroboration in replay.

If retained after validation, only count hours for which a completed query and suitable observation/wear evidence justify interpreting no steps as inactivity. A successfully queried zero-step interval alone does not prove the device was worn. Sparse samples must never become a full inactive day. Compare an inactive fraction over valid observed awake hours, with a minimum coverage gate; keep it a weak contextual contributor that cannot cause an alert or satisfy Major corroboration by itself.

Daily steps in this CSV cannot validate either policy. Avoid replacing hourly inactivity with low daily steps. Revisit the current all-workout-day mask only with workout timing/coverage evidence.

### 4. Separate scoring support from individual callouts

Keep signed native-direction deviations for arrows. Add an explicit reason for a verdict: individual deviations, combined changes, or persistent changes. A Major or Minor result with no individual flags should explain the combination; `BodyRadarSelectionAnnotation` currently says “All typical” whenever the flagged array is empty.

Retain the current clear individual-callout threshold initially. Score corroboration using meaningful contributions, independently from that display threshold. Do not rename modest contributors “outliers” to justify a classification.

### 5. Evaluate three small scoring candidates

All constants below are **engineering starting points for replay, not validated physiological thresholds or claims about Oura's formula**. Keep Vitals and Readiness normalization unchanged; Radar-specific experiments must not silently change those metrics.

| Candidate | Exact starting change | Purpose and limits |
| --- | --- | --- |
| A: combined changes | Preserve Beta 1 weights, dead zone and evidence thresholds over usable physiological signals. Major requires evidence ≥2 plus either ≥2 physiological flags, or ≥3 physiological contributors each contributing ≥0.25 with respiration or temperature among them. | Allows several modest changes to produce Major without individual callouts. Still caps one-signal events at Minor; measured support is not proof of statistical independence. |
| B: respiratory decrease | A, but score respiratory deviation as `abs(d)` while preserving its signed value for the displayed Increased/Decreased explanation. | Directly tests the missing direction observed in Oura. Do not apply absolute value to HRV, HR or temperature. A respiratory-only event remains at most Minor. Compare upper/lower directions separately. |
| C: restrained persistence | B, plus a Minor-only path when today's evidence ≥0.55, at least two physiological channels each contribute ≥0.15 today, and at least one of the preceding two consecutive scored nights had evidence ≥0.75. | Captures continuing small changes without carrying an old alert into a currently quiet night. No temporal-only Major; missing nights break continuity. Derive from prior raw daily evidence, not prior boosted states. |

Run A, B and C as separate ablations against Beta 1 and against the correctness-only version. Do not bundle them and claim which part helped. Candidate B may increase isolated respiratory alerts; it must earn adoption. Candidate C is optional if the exact inputs show meaningful persistent changes; the supplied September 3 proxy alone does not justify it.

Avoid scaling remaining signals upward when a sensor is missing: loss of data must not mechanically amplify confidence. An isolated high HRV should contribute zero, not cancel other evidence or trigger strain solely because it is unusual.

Defer log-HRV, covariance models, demographic weights, automatic baseline exclusion of alerted days, adaptive thresholds and machine learning. This single-person export with five selected comparison dates cannot support fitting those reliably. Log-HRV can be a later isolated experiment if actual overnight SDNN shows a reproducible distribution problem.

### 6. Version the result and preserve chart meaning

Add a Radar algorithm identifier to the record context, with backward-compatible decoding if record fields change. A Beta 2 run must not silently reuse Beta 1 records as Beta 2 outputs. Recommended migration: invalidate Radar-derived records for the new version and recompute the supported recent history from compatible cached inputs; leave unavailable nights explicitly unscored. Do not clear unrelated health caches or readiness/stress records.

Use the same rule for rollback: a version/context mismatch recomputes Radar records. Retain Beta 1 only in development comparison fixtures rather than shipping two concurrent user-visible histories.

Update the Beta v1 chip, About text, localization and documentation only when the selected Beta 2 behavior is implemented. The chart currently positions points using evidence within the state's band. A persistence-derived Minor below the ordinary Minor evidence threshold must have a deliberate band-position rule and truthful underlying evidence; do not inflate the stored evidence just to draw the point higher.

## Validation and delivery stages

### Stage 1 — explain the current disagreement

Export exact Apple Watch sleep inputs/frozen Body records, verify source settings/timezone choices, and confirm the inferred Body historical dates by record data or scrubbing. Analyze September 6's Oura 13.5 and Apple Watch 15.03 separately against their respective histories rather than trying to reconcile them into one value. Capture whether August 29–30 were missing sleep, calibration or incomplete hydration. Obtain optional symptom/context annotations without treating silence as “healthy.”

Deliverable: a local day-by-day Beta 1 replay report with source and exclusion reasons. No production sensitivity changes yet.

### Stage 2 — implement correctness and explanations

Scope: `BodyRadarCalculator.swift`, `BodyRadarModels.swift`, integration/context handling in `HealthSummarySnapshot.swift` and `HealthKitWorkoutStore.swift`, relevant hydration metadata only where needed, and chart/detail text/localization. Reuse existing source provenance and refresh admission machinery. Keep fetch work off the main actor and avoid extra per-night HealthKit fan-out.

Deliverable: reliable unavailable states, retryable incomplete mornings, explicit combination explanations, and versioned records. Quantify eligible-night coverage with and without inactivity.

### Stage 3 — replay candidates before selection

Use chronological evaluation: June–July for warm-up/design checks and August–September as a descriptive comparison period. Since the August–September examples have already informed this plan, they are **not a clean unseen holdout**. Reserve at least the next 2–4 weeks for prospective observation with fixed candidate constants; gather more events if that window contains no informative cases.

Report eligible/unavailable nights, Minor/Major frequency, episode count and duration, isolated alerts, reason distribution, sensitivity to missing each sensor, and differences from Beta 1. Compare Oura agreement only on reliably labeled dates. With user-provided symptom periods, report timing relative to onset and alerts during explicitly annotated well periods; do not call unlabeled disagreement a false positive or missed illness.

No dates hardcoded into rules, no tuning to force all five Oura matches, and no diagnostic sensitivity/specificity claims from this dataset. Choose the smallest candidate that improves interpretable behavior without unacceptable alert burden or loss of coverage; retain correctness-only changes if scoring evidence is inconclusive.

### Stage 4 — focused tests and build

Extend existing `BodyRadarCalculatorTests` and relevant chart/context/Codable tests with behavioral cases:

- Three/four moderate changes can produce the intended combined verdict with no individually flagged signals; single extreme signal cannot produce Major.
- Respiratory decrease is flagged with a down arrow only in the chosen candidate; ordinary noise is quiet; isolated high HRV remains noncontributing.
- Dropping a sensor does not raise evidence; one remaining physiological channel produces insufficient data; missing values and non-finite values never become zero measurements.
- Baseline uses only prior days; exclusion fallback, exact threshold boundaries, source changes, recency and baseline warm-up remain deterministic.
- Sparse step hours never create inactivity evidence; day-D activity belongs only to the day-D+1 night if the signal is retained.
- Calibrating/incomplete mornings retry after hydration; scored mornings stay frozen; naps and late same-day refreshes do not rewrite them; historical backfill respects the same rules.
- Persistence breaks across gaps/context changes, requires current support and cannot escalate a quiet current night through recursion.
- Old Codable payloads load; algorithm changes invalidate only Radar records; rollback is deterministic.
- Calendar/DST/travel boundaries preserve one canonical wake-day result; muted placeholders and combined explanations are accessible and never say “All typical” for a strain verdict.

Run focused XCTest using the project's existing `rtk xcodebuild test` workflow, then the strongest relevant build gate. Include chart tests if evidence/state mapping changes and source/context guards if integration changes. No app build was run for this documentation-only exploration.

## Open information and decision points

- Device families are confirmed: the original CSV and Body result use Apple Watch; Oura uses its own measurements. Exact export aggregation definitions, source settings and device models remain unconfirmed.
- Whether August 20–22, September 3 or September 6 coincided with illness, fatigue, travel, alcohol, unusual training or feeling well remains unconfirmed. An optional question was sent during exploration; no response is assumed.
- The user reports adding Oura measured data. Its file was not yet visible in Downloads during the initial follow-up inventory; its contents have not been analyzed. A full daily verdict export is also not established. Screenshots remain comparison observations, not a training dataset.
- Proposed default scope: overnight strain deviations, stable morning results, conservative Major corroboration, and no inactivity scoring until coverage is supported. Respiratory decreases and persistence require the staged evaluation above.

## External references

Oura describes Symptom Radar as combining biometrics over time, using sleep data, providing three levels, and needing seven nights within 14 days. It also distinguishes insufficient sleep data from calibration. Its public article does not disclose the weights or thresholds needed to reproduce the algorithm. These product facts support comparison and state design, not the numerical candidates proposed here. [Oura Health Radar, Symptom Radar section](https://support.ouraring.com/hc/en-us/articles/52627030482707-Health-Radar), reviewed September 6, 2026.

Apple identifies HealthKit's HRV quantity as SDNN; that type must remain explicit in the input contract. [Apple HealthKit: heartRateVariabilitySDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn). No interchangeability with another HRV statistic is assumed.
