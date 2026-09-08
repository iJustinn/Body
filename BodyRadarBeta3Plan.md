# Body Radar — Beta 3 handoff

Updated September 7, 2026. Status: pending Oura export and investigation; no Beta 3 algorithm has been selected or implemented.

## Start here

The user chose to implement Beta 2 with the available Apple Watch data, then revisit sensitivity when Oura's measured-data export arrives. Body uses Apple Watch measurements; Oura uses its own measurements. Keep their baselines separate. Matching Oura is a comparison objective, not proof of illness detection.

Read [BodyRadarBeta2Plan.md](BodyRadarBeta2Plan.md) for the original screenshots, CSV inventory/hash, proxy calculations, design rationale and references. Its **Selected Beta 2 scope** section records what was implemented; its original proposals include ideas that were deliberately deferred. This file is the active checklist for the next iteration.

## Beta 2 starting point

| Area | Implemented behavior to preserve or explicitly evaluate |
| --- | --- |
| Signals | Sleeping HR, respiratory rate, wrist temperature and SDNN HRV. Inactivity is excluded; its enum remains for legacy decoding. |
| Baseline | Per signal, previous 56 calendar days, minimum 14 observations. Exclude the latest three prior days only when at least 28 older observations remain. |
| Scaling | Median and `max(1.4826 × MAD, floor)`; signed deviation `d = clamp((value − median)/(2 × spread), −3, 3)`. Floors: HR 3 bpm, respiration 0.6 breaths/min, temperature 0.2 °C, SDNN 5 ms. One d unit is **two robust spreads**, not one standard deviation. |
| Evidence | Temperature weight 1.5; other physiological signals 1. HRV counts downward; other signals upward. Sum `weight × max(0, directional_d − 0.5)`. Opposite-direction readings contribute zero rather than canceling another signal. |
| Verdict | Minor at evidence ≥0.75. Major at evidence ≥2 plus two individually flagged physiological signals; flag threshold is strictly `directional_d > 1`. A single extreme signal caps at Minor. |
| Sufficiency | Two channels must have baseline history and seven observations in the last 14 calendar days. A scored channel also needs a finite current-night reading. |
| Unavailable states | Calibrating: fewer than two baseline/recent-history-supported channels. Insufficient Data: histories exist but fewer than two current readings qualify. Missing Sleep: no qualifying night. Unavailable current nights do not inherit yesterday's verdict. |
| Sleep eligibility | Three hours and an ended wake cycle when stages exist; vitals-only backfilled summaries are trusted without that stage-based check. |
| Finalization | Only scored nights freeze, at wake +10 minutes or 10:00 when wake is unknown. Unscored nights retry on subsequent refreshes. Scored mornings stay fixed through routine same-day refreshes. |
| History | 21-night chart; at most 60 recorded nights. Prefer compatible frozen history, backfill supported gaps, leave unsupported nights unscored. |
| Versioning | Nightly `algorithmVersion = 2`, plus `;radar[2]` in the record-context signature. Legacy records decode but are recomputed; legacy cached Radar summaries are discarded on cold launch without discarding other health fields. |
| Explanation | A Minor result without individually flagged signals says several small changes suggest strain. This did **not** introduce a new combined-change scoring rule. |
| Queries | Dedicated Radar hourly-step fetch removed; step/workout inputs and permissions removed from Radar's contract. No new sleep-query fan-out. |

Beta 2 verification: 46 focused XCTest cases passed on iPhone 17 Pro / iOS 26.5 Simulator, zero failures/skips; the test build compiled app/watch/widget dependencies. These are behavioral checks, not an accuracy validation. The exact focused command is under “Regression gate” below.

## Evidence to revisit

Original files were in `~/Downloads`; raw health exports/screenshots were not copied into the repository. Locate them again when work resumes rather than assuming Downloads or temporary scripts are permanent storage. Record the incoming Oura filenames, export time, covered dates and hashes in the eventual analysis report.

| Case | Established observation | Next investigation |
| --- | --- | --- |
| Aug 20–22, 2026 | Oura explicitly shows Minor on each date, with a combined-change explanation and no individual callout. | Inspect Oura's own changes over these nights and their preceding history. Determine whether Apple Watch captures corresponding changes. |
| Sep 3 | Oura explicitly shows Major with no individual callout. Apple Watch daily proxy evidence was zero. | Examine Oura values and prior nights; do not force an Apple Watch Major simply to match this label. |
| Sep 6 | Oura shows Minor and decreased respiration, 13.5/min. Apple Watch CSV respiration is 15.03; Body screenshot says No Signs. | Compare each device to its own respiratory baseline and sleep window. The difference alone is not an ingestion bug. |
| Aug 23 / Aug 31 | Body chart appears to have Minor on these dates. | Confirm by frozen records or scrubbing; dates were inferred from dot positions. |
| Aug 29–30 | Body chart appears to have unscored/dim slots, while daily proxies produce Major/Minor. | Determine whether sleep, baseline, hydration or historical record timing explains the gaps. Confirm dates first. |
| Sep 6 partial export row | Apple Watch SDNN 180.16 ms, no temperature and 457 steps. | Inspect sampling/time of export; do not assume either sensor failure or a full day's observations. |

The original Apple Watch export contains 98 unique daily rows, June 1–September 6. The exploratory formula replay substitutes daily RHR for sleeping HR, uses daily SDNN, and omits inactivity and real sleep/freeze gates. It produced 14 baseline-unavailable rows, 74 No Signs, nine Minor and one Major. It is **not** a replay of Body's actual nightly inputs. All five explicitly selected Oura alert dates had zero evidence in that proxy calculation. The complete reproduction recipe and SHA-256 are in the Beta 2 plan; do not rely on the temporary analysis script surviving.

Only the five selected Oura dates are firm screenshot verdict labels. Do not infer complete daily labels from connecting chart segments. Illness, fatigue, travel, alcohol, unusual training and explicitly well periods remain unconfirmed; no response was received to the optional context question. Missing annotations are not healthy labels.

## Ordered work checklist

- [ ] **Inventory and normalize the Oura export.** Inspect schema, units, missingness, duplicate dates, device/source identity, timezone and wake-day assignment. Distinguish main sleep from naps and daily from overnight aggregation. Check average versus lowest/resting HR, the HRV statistic, and absolute temperature versus deviations from Oura's own reference. Do not presume the export contains Symptom Radar labels.
- [ ] **Assemble two separate timelines.** Oura measurements against Oura history; Apple Watch measurements against Apple Watch history. Never pool raw values, substitute one device's value for a gap in the other, convert SDNN to RMSSD, or apply SDNN-specific floors to a differently defined HRV statistic without an explicitly labeled experiment. An already normalized temperature field needs its own interpretation.
- [ ] **Build exact local Body replay/export.** Export actual sleep-window inputs and frozen records, not only Home daily aggregates. Obtain 56 days before the first scored comparison date where possible; mark shorter warm-up explicitly. Match Beta 2 production evidence within a declared floating-point tolerance and states/exclusion reasons exactly before evaluating new candidates. Retain the Beta 1 proxy as historical context only.
- [ ] **Explain the selected dates.** Produce a day-by-day comparison of within-device deviations, contributions, missing channels and verdicts. Confirm the inferred Body dates and separate measurement differences from algorithm differences and incomplete inputs.
- [ ] **Measure Beta 2 coverage and finalization.** Count eligible/unavailable nights, per-channel exclusions, late arrivals and first-freeze timing. Check whether the two-channel/per-channel-recency rules create excessive unavailability or whether early two-channel freezing hides important later readings.
- [ ] **Run isolated candidate experiments.** Use the definitions below, record every constant and compare against Beta 2. Keep a decision log including rejected candidates and why they were rejected.
- [ ] **Validate prospectively and choose scope.** Freeze constants before the next observation period. Select the smallest justified improvement; keeping Beta 2 scoring is an acceptable outcome if evidence remains inconclusive.
- [ ] **Implement, version and verify only selected changes.** Preserve missing-data behavior, source isolation and unrelated caches. Update help text, localization, chart explanations and regression coverage for the final behavior.

### Required replay record

Capture canonical wake day and calendar/timezone; sleep intervals/duration and stage availability; each physiological value, unit/statistic, source identity, sample count and temporal coverage where available; baseline median/spread/count/recency; signed deviation, contribution and exclusion reason; raw daily evidence/state; provisional/frozen status and freeze time; algorithm version and source context. Include per-query completion/failure metadata if instrumentation is added. Mark unavailable metadata as unknown rather than deriving confidence from its absence.

Keep exports local and opt-in. Use existing snapshot/source-admission machinery, value-type replay inputs and bounded background computation. Avoid a new per-night HealthKit query for each diagnostic field. A development-only exporter and structured replay diagnostics were **not implemented in Beta 2**.

## Deferred scoring experiments

These are starting hypotheses, not validated thresholds or a reconstruction of Oura's proprietary algorithm.

| Candidate | Starting definition | Evaluation concern |
| --- | --- | --- |
| A — combined Major | Keep Beta 2 evidence. Major requires evidence ≥2 plus either ≥2 physiological flags, or ≥3 contributors each contributing ≥0.25 with respiration or temperature among them. | Can combined mild changes add useful Major cases? Correlated HR/HRV changes are not automatically independent corroboration. Single-signal events must remain capped. |
| B — respiratory decrease | Score respiration using `abs(d)`, retaining signed d for Increased/Decreased arrows. Keep other directions unchanged. | Compare low- and high-direction alerts separately; evaluate isolated respiratory alerts and ordinary variation. Do not generalize absolute deviation to HRV, HR or temperature. |
| C — restrained persistence | Additional Minor-only path: today's evidence ≥0.55, ≥2 current physiological contributions each ≥0.15, and at least one of the preceding two consecutive scored nights with raw evidence ≥0.75. | Missing nights/context changes break continuity; require current support. No temporal-only Major or recursive carry of already boosted states. Define the gap rule explicitly in fixtures before coding. |

Run Beta 2, A-only, B-only and C-only first; then A+B and A+B+C only if component results justify combination. The original plan described B/C cumulatively; isolated runs are needed to identify which change caused an effect. Every comparison must share the same input eligibility and baseline rules unless those rules are themselves the named experiment.

Do not increase remaining signal weights merely because a sensor is missing. Do not let high HRV cancel positive evidence elsewhere. A persistence-derived Minor below the normal evidence threshold needs a deliberate within-band chart position; never inflate stored evidence to make its dot fit.

## Other limitations and decisions to revisit

- **Hydration completion:** Beta 2 knows whether two usable readings exist, not whether every sensor query completed. Third/fourth readings arriving after a scored freeze do not update it. Investigate completion-aware finalization, supported sensor capability and bounded retry semantics before changing the wake delay; do not wait forever for absent hardware or denied data.
- **Night selection:** vitals-only backfills bypass duration/stage eligibility. Review duplicate wake days, travel/DST, naps, stale history versus refreshed current sleep and late corrected/deleted observations. Establish whether any issue occurs before changing shared sleep aggregation.
- **Sparse devices:** evaluate two-channel coverage across supported sensor sets. If fewer than two channels can ever be obtained, consider a clearer unavailable explanation rather than indefinite calibration. Missing data must not imply health or greater confidence.
- **Inactivity:** leave excluded unless observed awake/wear coverage supports it. A completed query with zero steps is not proof of wear. If reconsidered, evaluate inactive fraction over valid observed awake hours and minimum coverage; never use low daily steps as a substitute or let inactivity alone trigger/corroborate Major. Revisit the legacy all-workout-day mask only with timing evidence.
- **Baseline robustness:** investigate signal spread floors, lookback and recent-exclusion fallback as separate experiments if actual nightly data warrants them. Log-HRV, covariance models, demographic weights, automatic exclusion of alerted days, adaptive thresholds and machine learning remain deferred; five selected labels and one person's data cannot justify fitting these together.
- **History migration/rollback:** version 3 must not relabel version 2 records. Decide which compatible recent inputs can be recomputed and leave unsupported history unscored. Keep chronological scoring free of future-data leakage. A new version can reject old records, but rollback to an already released older binary must be checked explicitly—do not assume that binary understands future payload semantics.

## Evaluation and acceptance

Use June–July as historical warm-up/design material and August–September as descriptive comparisons. The selected August–September cases already informed the design and are not an unseen holdout. Reserve at least the next 2–4 weeks with fixed constants for prospective observation; collect more events if the period is uninformative.

Report eligible and unavailable nights with reasons; Minor/Major frequencies; episode count/duration; isolated alerts; current versus temporal contributions; sensitivity to removing each sensor; freeze timing and late-data changes; and agreement only on reliably labeled Oura dates. Report symptom-relative timing and alerts during explicitly annotated well periods only if those annotations exist. Keep unlabeled days out of false-positive/missed-illness claims.

Before selecting a candidate, document its incremental benefit, alert burden, coverage loss, unresolved disagreements and chosen acceptance limits. Do not hardcode dates or tune until all five screenshots match. No diagnostic sensitivity/specificity claim follows from this sample.

## Code map and regression gate

| Files/symbols | Role |
| --- | --- |
| `BodyMetricsKit/BodyRadarCalculator.swift` | Eligibility, baseline use, evidence, summary/backfill and freezing |
| `BodyMetricsKit/BodyRadarModels.swift` | States, signal direction, versioned records and unflagged explanation |
| `BodyMetricsKit/VitalsSnapshot.swift`, `ReadinessScoreCalculator.swift` | Shared normalization/baseline helpers; avoid unintended Vitals/Readiness changes |
| `BodyMetricsKit/HealthSummarySnapshot.swift` | `recalculatingBodyRadar`, source-context invalidation and cold-cache decoding |
| `Body/Services/HealthKitWorkoutStore.swift` | Input/source/permission sets, versioned signature and refresh publication |
| `Body/Models/BodyAppearancePreference.swift`, `BodyDashboardFetchSelectionTests.swift` | Dashboard dependency expansion: Radar alone requests sleep, not steps; Stress or a displayed Steps card may still request steps. Keep explicit layout assertions independent of mirrored dependency fixtures. |
| `Body/Views/Health/Charts/BodyRadarChart.swift`, `BodyHomeView.swift`, `BodyAppearancePreference.swift` | State/evidence presentation, explanations, badges and version chip |
| App and BodyMetricsKit string catalogs; README, TestPlan, VersionHistory | English/Chinese copy and product documentation |

Retain Beta 2 tests for per-channel recency, two-sensor support, non-finite/missing inputs, nonamplification after sensor removal, retry then freeze, legacy decoding/recompute, cold-cache isolation and muted placeholders. Add selected-candidate boundaries, chronological replay, source/timezone changes, missing-night persistence breaks, no recursive boosts, late sensor completion and version 2→3 migration/rollback cases. Validate only the behavior actually selected for Beta 3.

The Beta 2 focused gate, reusable as a starting point:

```sh
rtk xcodebuild test -project body.xcodeproj -scheme Body \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/body-radar-v3-derived CODE_SIGNING_ALLOWED=NO \
  -only-testing:BodyTests/BodyRadarCalculatorTests \
  -only-testing:BodyTests/BodyRadarChartTests \
  -only-testing:BodyTests/BodyDashboardFetchSelectionTests \
  -only-testing:BodyTests/LocalizationRuntimeKeyTests/testBodyRadarKeysResolveInCatalogs \
  -only-testing:BodyTests/WorkoutMonthSnapshotTests/testVitalsHomeCardKindConfiguration \
  -only-testing:BodyTests/SourceGuardTests/testBodyRadarDoesNotLoadActivityInputs \
  -only-testing:BodyTests/SourceGuardTests/testBodyRadarRecordContextSignatureTracksVitalSourceChanges \
  -only-testing:BodyTests/SourceGuardTests/testBodyRadarSignedSourceKindsCoverTheSleepVitals \
  -only-testing:BodyTests/SourceGuardTests/testFullRefreshRecomputesBodyRadarOnceAndCarriesItForward
```

Resolve the then-current simulator destination and test names when resuming. Expand checks only for changed integration surfaces. Read the project's current guidelines and LessonsLearned before editing. Preserve concurrent local work; this handoff does not authorize a release, commit or push.

## Expected Beta 3 deliverables

An input inventory and data dictionary; reproducible local replay; a dated comparison report for the selected cases and the full eligible period; an experiment/decision log; explicit selected versus deferred scope; implemented/versioned changes if supported; focused test results and updated user-facing documentation. If evidence does not support a scoring change, document that decision and retain Beta 2 rather than manufacturing a new threshold.
