# Version History

## 0.9.6 (build 3)

- **Body now speaks Simplified Chinese.** The entire app UI is localized to **Simplified Chinese (zh-Hans)**, following the iOS system language (or the per-app language in iOS Settings > Body > Language): all three tabs and every detail screen, the trend-card sentences, the Apple Watch app and its complications, the Home Screen widgets and their configuration options, the HealthKit permission prompts, and the Body Pro StoreKit product strings. English remains the development language and is untouched.
- Strings moved into per-target **String Catalogs** (`.xcstrings`) — a `Localizable` catalog per app/extension target plus named tables for the shared folders (`BodyMetricsKit`, `BodyShared`, `BodyWatchShared`, `BodyWatchSnapshotKit`) and `InfoPlist` catalogs for the usage descriptions. `zh-Hans` was added to the project's known regions.
- Month/weekday date formats now go through **localized date templates** (`setLocalizedDateFormatFromTemplate`) via a new `BodyDateFormatterCache.formatter(template:calendar:locale:timeZone:)`, so dates order correctly in Chinese (e.g. 2026年7月) while English output is unchanged. Unit abbreviations (kg, km, kcal, bpm) stay Latin per Apple Health convention.
- Updated the app, widget, watch, and test bundle version to 0.9.6 build 3.

## 0.9.6 (build 2)

- **The Readiness star on Home now keeps your morning starting point in view.** When today's live Readiness has drained below the score you woke up with (after a workout or late-arriving data), the hero adds a **`Started today with NN%`** line beneath the status text so the morning value stays readable at a glance. It appears only when the score has actually dropped.
- **The Readiness hero explanation now names what's moving your score.** Instead of one generic sentence per band, the hero picks copy keyed to today's strongest signal — short sleep, restless sleep, elevated training load, a soft HRV, a high resting heart rate, elevated breathing rate, low blood oxygen, or above-baseline skin temperature — so the one-liner reflects your actual metrics. The "About your score" card keeps its static per-band legend.
- Updated the app, widget, watch, and test bundle version to 0.9.6 build 2.

## 0.9.6 (build 1)

- **Workout metrics now compare to your 30-day average.** Each tile on the workout detail card shows a compact **`↑12%`** badge above its unit — comparing that metric to the average of your **same-type** workouts over the 30 days before that workout — with a single **`vs 30-day avg`** label beside the **Details** heading. It's direction only (no good/bad coloring), shows `≈0%` when you're on par, and shows no badge for metrics without enough comparable history or while that history is still loading. Rate metrics (pace, speed, swim pace) use a distance-weighted baseline with a per-style minimum distance so short workouts don't skew it, and each tile's VoiceOver label speaks the comparison in words.
- Updated the app, widget, watch, and test bundle version to 0.9.6 build 1.

## 0.9.5 (build 11)

- **Refreshed the summary card beta badges.** The Readiness card's badge now reads **Beta v3**, and the **Sleep Score** toggle in Settings no longer carries a beta badge.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 11.

## 0.9.5 (build 10)

- **Activity-aware workout details.** The workout detail card now adapts its metrics to the activity: walks, runs, and hikes add **Avg Pace**, **Elevation Gain**, **Cadence**, and **Cardio Fitness (VO₂max)**; rides add **Avg Speed**, **Cadence**, and **Power**; swims add **Swim Pace** (per 100 m) and **Stroke Count**. **Max Heart Rate** appears wherever heart-rate data exists, and every workout still shows distance, energy, and average heart rate. Each tile is shown only when the activity and recorded data support it.
- Added Apple Health read access for **Cardio Fitness (VO₂max), running/cycling power, cycling cadence, swimming stroke count, and steps** (steps power foot cadence) so the new metrics can populate; power, cadence, and stroke count are best-effort and appear only when the recording source provides them.
- **New permission toggles in Settings → Data → Permissions.** **Workout Metrics** (VO₂max, power, cadence, and swim strokes) and **Date of Birth** (which anchors the workout heart-rate zones at the age-estimated max HR, 220 − age) each get their own switch. Turning Workout Metrics off removes those detail tiles while distance, pace, energy, and heart rate stay; turning Date of Birth off falls the HR zones back to the session's peak. Workout distance and date of birth are now part of the requested read set, and a one-time migration keeps both new categories on for anyone who had already customized their permissions.
- **Readiness now reacts to your day.** After a workout, today's live Readiness drops based on the activity's type, effort, and recorded metrics (duration, heart rate, energy) — a hard session can pull it down by up to ~two status bands while an easy one barely moves it. The drop accumulates across the day's workouts and stays until the next morning (no same-day rebound).
- **Readiness history is locked to your morning.** The score recorded into the Week / Month / 6 Months / Year charts is your readiness ~10 minutes after you wake (or after 10:00 when no sleep is tracked). Every later same-day change — the activity drop and late-arriving data — is display-only and never alters the recorded history.
- Switching a readiness data **source** (or how same-name sources are combined), or toggling a readiness **permission** (sleep, heart, blood oxygen, respiratory, workouts, or skin temperature), now rebuilds the recorded morning history from the new inputs instead of keeping values captured under the old ones; fresh morning records resume the next day. Changing a source or permission that does not feed Readiness leaves its history untouched.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 10.

## 0.9.5 (build 9)

- Replaced every app icon with Apple **Icon Composer** (`.icon`) artwork: the primary icon plus the five color alternates (Rose, Violet, Midnight, Neutral, Light) now ship as layered icons that render the iOS 26 light / dark / tinted (Liquid Glass) appearances, with an automatic flat raster fallback on iOS 18–25.
- Removed the **"Present" creator-surprise alternate icons** and the Settings version-card tap that unlocked them; the app-icon picker now shows the six standard color options only.
- Updated the **Apple Watch app and Home Screen widget** icons to the new Classic design so every surface matches.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 9.

## 0.9.5 (build 8)

- **Body Pro is now a real in-app purchase.** The paywall's Lifetime card, **Restore Purchases**, and **Redeem Pro** are wired to StoreKit 2 (non-consumable `com.zihengthedeveloper.body.pro.lifetime`); once purchased, an owned state replaces the buy card and all features unlock instantly.
- **Five features are now gated behind Body Pro.** Longer-range metric charts (free users get the **Week** range only; **Month / 6 Months / Year** require Pro), **full day history** in the metric and sleep day-pickers (free users browse the 3 most recent days — older day tiles dim, show a lock badge, and open the paywall), **custom app backgrounds** (free users stay on the app-default background across Home, Workouts, and Settings), the **secondary data source** comparison on metric charts (gated in both the chart's source picker and Settings → Data → Source), and the five **Home Screen widgets** (which show an "Unlock Body widgets" state until purchased).
- The paywall now shows a brief **"Checking your purchases…"** state until the entitlement resolves (so a returning purchaser never sees the buy card first), and disables purchase / restore / redeem while a purchase is in flight. When a pending **Ask-to-Buy** purchase is later approved, the paywall unlocks and re-enables Restore / Redeem instead of staying stuck on "pending".
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 8.

## 0.9.5 (build 7)

- The readable content-width cap — which centers a page's content instead of stretching it edge to edge on iPad and other wide canvases — now also applies to the **workout detail** page, the **metric detail hero** (the range tabs, trend chart, big value, and breakdown chart such as Sleep Stages), and the **Body Pro** page, matching the dashboard, Workouts, Settings, and the metric detail cards. Each page's full-bleed background (route map, tint gradient, or grouped background) still fills the screen while the content centers; iPhone layout is unchanged.
- Raised the **Body Pro** Lifetime purchase price shown on the paywall to **$9.99** (up from $5.99).
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 7.

## 0.9.5 (build 6)

- The colored **workout calendar squares** and **type-breakdown bars** now use a flat, slightly translucent fill so the backdrop shows through, matching the app's flat glass surfaces — no heavy material frost or specular sheen. The **breakdown bars** add a thin white edge rim; the **calendar squares** have no border. Empty calendar day cells are unchanged.
- Workout cards now **zoom into their detail the same way Summary cards do**: tapping a workout on the Workouts list morphs the card open into a full-bleed detail page (the morph clipped to the card's rounded corners) that collapses back into the card when you close it with a top-right **Liquid Glass ✕** button — replacing the old partial-height detail sheet. The detail opens as a navigation push, so the **bottom tab bar stays visible**, and the route map now extends to the very top of the screen (under the status bar). The same morphing detail also opens from the **calendar-day** and **workout-type** popups — their rows are now tappable, and those popups dropped their **Done** button (swipe down to dismiss). Built on iOS 18's zoom transition, which falls back to a cross-fade under Reduce Motion.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 6.

## 0.9.5 (build 5)

- Sleep detail card header values now use the same number-flipping transition as the Summary metric values: the Sleep Stages duration and Sleep Consistency percentage animate when the selected day changes, while respecting Reduce Motion.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 5.

## 0.9.5 (build 3)

- Workouts recorded with GPS now show a **route map** behind the top of the workout detail sheet: the route is drawn fit-to-bounds and **colored by pace** (red slow → green fast) with a green start marker and a red end marker, and the city (e.g. "New York, NY") is shown below the workout title. The map is a static snapshot (no panning) that sits as a fixed background and dims as the workout details scroll up over it; indoor or route-less workouts show no map and are otherwise unchanged. Reading routes adds a one-time Apple Health permission prompt the next time you refresh.
- Tapping a metric on the Home screen now **zooms the detail page out of the card you tapped** instead of sliding it in from the screen edge. The grid metric cards, the trend cards, and the Activity Rings card all use the new transition — each detail page collapses back into its own card on dismiss. The morph is clipped to the cards' rounded corners, and when a grid card and a trend card for the same metric are both on screen, each animates from its own position. Built on iOS 18's zoom navigation transition, which falls back to a cross-fade under Reduce Motion. The full-bleed Readiness star hero instead **cross-fades its detail in and out** (dismissed with a Back button) — a fade reads better for a hero with no card edges to grow from.
- Sleep detail now shows a 14-day Sleep Consistency percentage in the card header instead of the selected Apple Health source name.
- Dark theme is now the app default; Settings keeps the Theme row visible but disabled while Light/System theme selection is gated.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 3.

## 0.9.5 (build 2)

- Added a **Star Metric** to the Summary tab: one metric is pinned to the top of the home screen as a full-bleed hero (no card) and lifted out of the drag-to-reorder grid. v1 ships **Readiness** as the default star metric — today's readiness score sits on a wave-fill tinted by the readiness band that fills left-to-right to the score, bleeds behind the status bar, and melts into the page; the score flips up from zero (and rolls to each new value) and the whole hero taps through to the Readiness detail. Pick the star metric, or turn it off (which returns the Readiness card to the grid), under Settings > Metrics > Star Metric, a new gold row at the bottom of the Metrics section. While Readiness is starred the custom Home Background is auto-disabled (the hero supplies the color); the remaining cards still drag-to-reorder, and Readiness keeps fetching its inputs even when it's hidden in Summary Cards.
- Updated the app, widget, watch, and test bundle version to 0.9.5 build 2.

## 0.9.5 (build 1)

- Updated the app, widget, watch, and test bundle version to 0.9.5 build 1.

## 0.9.3 (build 8)

- Added Apple Watch **metric detail pages**: tapping a metric card — or a metric complication on the watch face — opens a full-screen detail view for that metric, and you can swipe up/down (or turn the Digital Crown) to page between every metric's detail directly, the page's color sliding smoothly as you go. Each page is washed in the metric's color — the title sits top-right, the last 7 days plot as a line chart (a tinted line with a ringed dot per day and a solid dot for today when today has a reading, faint per-day gridlines, and weekday labels), and the current value reads large at the bottom-left, with Readiness and Training Load showing today's status level beside it ("85 · HIGH"). Those two also highlight today's status band — the colored value range with top/bottom edge stripes — behind the line, matching the iPhone chart. The 7-day series, band, and status are computed on the iPhone and carried in the pushed snapshot, so the watch stays display-only. A snapshot from an older iPhone build (no weekly data) shows a "No recent data yet" state.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 8.

## 0.9.3 (build 7)

- Removed the Apple Watch "Standalone Compute" feature. The watch no longer computes Readiness, Sleep, or Training Load on-device; it always shows the metrics the iPhone computes and pushes over WatchConnectivity. It still refreshes Heart Rate and HRV directly from its own HealthKit when the pushed snapshot is stale (and via the home-screen refresh button), exactly as the original watch app did. The Settings > Apple Watch page and the on-watch toggle are gone, the watch's HealthKit background-delivery entitlement was dropped (only foreground HR/HRV reads remain), and its Apple Health permission prompt now reflects that narrower access.
- Added an accessory **corner** complication for every Apple Watch metric — a curved gauge that hugs the bezel on corner-style watch faces (e.g. Infograph), showing the metric's value with a tinted fill arc. Also slightly reduced the value text in the circular ring complication.
- The Apple Watch home screen now leads with **Training Load**, and the watch Settings screen adds a show/hide toggle for each metric so you can choose which cards appear on the watch. Visibility is a watch-local preference — hidden metrics stay in the synced snapshot and can be turned back on, and the home screen shows an "All Metrics Hidden" state if you turn them all off.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 7.

## 0.9.3 (build 6)

- Aligned the Apple Watch standalone Readiness and Sleep computation with the iPhone so both produce the same result from the same Apple Health data. The watch now fetches each workout's real effort score (instead of assuming a default), shares the iPhone's exact sleep-stage parsing and 180-day training-load window through new shared code, and honors the iPhone's "show sub-minute awake stages" setting (synced over WatchConnectivity). An effort edit on the phone now also wakes the watch to recompute.
- Added a note on the Settings > Apple Watch (Standalone Compute) page explaining that, with Standalone Compute on, choosing a non-default Apple Health source for a metric can make the watch's numbers differ from the iPhone (the watch reads all sources).
- Standalone Compute now defaults to off (it previously defaulted on). Turn it on from Settings > Apple Watch to compute Readiness and Sleep on the watch; with it off, the watch keeps showing the iPhone-pushed metrics.
- Added an Add (+) button to the top-right of the Basics detail screen. It opens a sheet to log a new weight and body-fat measurement — both on one page, chosen with wheel pickers that start from your latest values, with a date/time picker and an include checkbox on each so you can log just weight, just body fat, or both — and saves the enabled values to Apple Health. This is the first data Body writes to Apple Health, so the Health write-permission prompt appears the first time you save.
- Made the Effort card on a workout's detail screen tappable to add or change that workout's effort rating. The card expands in place (no popup) to reveal Cancel/Save on the left and − / + buttons on the right; adjust 1–10 (Easy → All Out) and the bar meter animates as it changes. Body saves it to Apple Health, relates it to the workout, and recomputes Training Load (which effort feeds) so the trend — and the Apple Watch snapshot pushed on the next refresh — pick up the change.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 6.

## 0.9.3 (build 5)

- Settings > Apple Watch now matches the other settings groups: the Standalone Compute control is a tappable row (showing its On/Off state) that opens a popup page containing the toggle, instead of sitting inline in the settings list.
- Fixed the Apple Watch app reporting an inflated Sleep duration (e.g. 26h) when Apple Health holds overlapping sleep samples (an aggregate "asleep" sample plus detailed Core/REM/Deep stages, or multiple sources). The watch now merges overlapping asleep samples into their union — matching the iPhone's calculation — instead of summing them, so on-watch Sleep, the Sleep score, and the Readiness they feed line up with the phone.
- Added a refresh button to the top-left of the Apple Watch home screen. Tapping it recomputes the on-watch metrics (when Standalone Compute is on) and pulls a fresh Heart Rate / HRV reading, showing a spinner while it works.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 5.

## 0.9.3 (build 3)

- The Sleep Stages card's breakdown below the timeline is now tappable. Tap it to switch between the per-stage durations (the existing summary) and a new optimal-range bar chart: each stage shows its percentage of total time in bed, its duration, and an overlaid healthy reference band (Awake 0–5%, REM 20–25%, Core 45–55%, Deep 13–23%). The choice persists until you tap again (including across the two-source comparison cards and app relaunches). Changing the selected day animates the bars to their new lengths (respecting Reduce Motion). The bands are an illustrative reference and are independent of the sleep-score grading, which judges Deep/REM one-sided against asleep time — so a stage's chart percentage can differ slightly from the score card's, by design.
- Refreshed the in-app How to Use guide (Settings > About): the Sleep Details section now covers the tap-to-toggle stage breakdown, Readiness is named in the Summary card list, and a new Apple Watch section explains the companion app and its ring complications.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 3.

## 0.9.3 (build 2)

- Reorganized Settings > About into How to Use, Privacy, More, and Version. Feedback, Disclaimer, and Copyright now live together on a single More page (Feedback Email as a row, Disclaimer and Copyright inline).
- Privacy now opens Body's hosted privacy policy (https://docs.ijustinz.com/body/privacy) in an in-app browser instead of a bundled in-app page.
- About row icons are now gray.
- Performance: the Sleep detail page no longer stutters while the Sleep Consistency chart is on screen. The chart's static layers (grid, average lines, and night bars) are flattened into a single GPU-rendered layer, so scrolling composites one cached texture instead of dozens of continuous-corner clip masks; the 14-day chart model is also memoized so it isn't rebuilt on every re-render.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 2.

## 0.9.3 (build 1)

- Added an Apple Watch app and ring-style complications. The watch app shows Readiness, Sleep, Heart Rate, HRV, Resting Heart Rate, Training Load, and Skin Temperature in the iOS card style, and ships a complication per metric (accessory circular and rectangular). The iPhone stays the source of truth: it builds a compact metrics snapshot at the end of each successful refresh and pushes it to the watch over WatchConnectivity, and the watch caches it for its complications. When that snapshot is stale, the watch refreshes Heart Rate and HRV directly from its own HealthKit so those stay live without re-running the Readiness or Training Load computation on-device.
- Added two watchOS targets (`BodyWatch`, `BodyWatchWidgetExtension`) and a shared `BodyWatchShared` group; the watch app is embedded in the iOS app and the complication bundle is embedded in the watch app. The watch app reuses the iOS app icon.
- Hardened the watch sync: the snapshot's freshness date now tracks the last vitals refresh (workout-only refreshes no longer mark the watch fresh), watch-measured HR/HRV carry per-metric freshness so an older phone push can't roll them back, the watch re-checks staleness when it returns to the foreground, the last pushed snapshot is adopted on cold start once the session activates, watch-local samples older than 4 hours are ignored, and snapshot decode failures are logged. The complication gallery previews sample rings instead of an empty state, live-refreshed values respect the device locale, and each metric's key, tint, and symbol are defined once in `BodyWatchShared` (pinned to the iOS widget styling by a configuration test). Known limitation: complications update when the watch app runs — snapshots pushed while it's closed are applied on next launch.
- Updated the app, widget, watch, and test bundle version to 0.9.3 build 1.

## 0.9.2 (build 8)

- Performance: workout effort scores are now cached for the app session. Effort needs one HealthKit query per workout, and every refresh re-asked it for the 180-day Training Load window and the current month (~100–300 queries for an active user); passive resumes now query only workouts without a cached answer, while any pull-to-refresh (Home, Workouts tab, Training Load detail) clears the cache first so re-rated workouts always reconcile.
- Performance: automatic warm resumes reuse the heart-rate payload already fetched for finished workouts instead of re-downloading and re-downsampling every workout's raw samples in the month on each resume. Reuse only applies when the workout's identity and dates match exactly, its cached samples are non-empty, and it ended over 24 hours ago (so late or partial Apple Watch syncs always re-fetch); the workout list itself is still fetched fresh on every refresh, and user-initiated refreshes re-fetch all heart-rate data unconditionally.
- Added child performance signposts (workout months, source discovery, dashboard summary/trends/rings, training-load fetch, readiness recompute) inside the existing RefreshRecentMonths interval so future optimization is measured in Instruments instead of guessed.
- Updated the app, widget, and test bundle version to 0.9.2 build 8.

## 0.9.2 (build 7)

- Performance: an automatic warm resume that finds the dashboard stale (foregrounding the app more than five minutes after the last refresh) now re-fetches only the current month of workouts instead of the full three-month window. Past months are effectively immutable, the Workouts tab still loads its three-month window on demand, and a pull-to-refresh still reconciles all three months — so this drops redundant heart-rate/effort fetching from the common "reopen to catch up" path without losing any data.
- Updated the app, widget, and test bundle version to 0.9.2 build 7.

## 0.9.2 (build 6)

- Performance: the Summary dashboard no longer waits on the Workouts tab during a warm launch or pull-to-refresh. The full refresh used to fetch three months of workouts (with their per-workout heart-rate and effort-score queries) before it even began loading the dashboard metrics, Activity Rings, and trend charts; the workout months now load concurrently with the dashboard, so the Summary cards fill in as soon as their own data lands instead of after the workout fetch finishes.
- Performance: Apple Health source discovery (which apps and devices wrote each metric) now runs its per-metric queries concurrently instead of one metric at a time, collapsing a serial stretch that gated the first refresh of each app launch.
- A failed workout fetch no longer blocks the dashboard from appearing, and the refresh is only marked fresh when the workouts also load — so a partial failure re-runs the full refresh on the next app entry instead of being skipped by the five-minute resume shortcut.
- Updated the app, widget, and test bundle version to 0.9.2 build 6.

## 0.9.2 (build 3)

- The Sleep Score was recalibrated after a 13-night comparison against WHOOP sleep scores showed every night landing 80–92: REM, start-time, vitals, and temperature were near-guaranteed points, and HRV was graded against a fixed 80 ms target. Pressure (HRV), sleeping heart rate, respiratory rate, and wrist temperature are now graded against the user's own 14-night overnight medians (falling back to the previous absolute bands below 5 nights of history), continuity and duration use steeper curves, deep/REM use floor-anchored one-sided ramps (high REM and long sleep are never penalized), and the total passes through a breadth-aware decompression map so only truly strong nights score 90+. Typical nights now read ~75–88, disturbed or crash nights drop to ~55–70, and a perfect night still reads 100; sleep scores users saw previously will drop — expected.
- The Sleep Stages card now shows the night's total sleep time (hours and minutes, awake time excluded) in the header next to the source label, so the duration is visible without adding up stages — including per-source totals on the two-source comparison cards.
- Sleep durations on the week, month, six-month, and year trend charts (axis labels, selection readouts, and average annotations) now display as hours and minutes ("7h 54m") instead of decimal hours ("7.9h"), matching the Sleep card and widget.
- Updated the app, widget, and test bundle version to 0.9.2 build 3.

## 0.9.2 (build 2)

- Today's date now stands out in the Workouts calendar and the Workout Calendar widget: its day number uses the primary label color (white in dark mode, black in light mode) instead of the muted gray shared by the other days.
- Calendar workout icons, count markers, and day numbers now scale with the cell size so they keep their proportions on iPad's larger calendar instead of staying pinned to the iPhone point sizes.
- Fixed the iPad windowed app (Stage Manager, Split View, and Slide Over) rendering its dashboard and cards a washed-out gray: iPadOS raises the window's trait collection to `.elevated`, which lightens every semantic system background one step, so the host window now pins its interface level back to `.base` to match the full-screen appearance.
- The Sleep detail Sleep Stages chart now labels only the actual sleep start and end times on the x-axis instead of fixed two-hour ticks, with the first and last labels anchored to the chart edges so the end time no longer clips off the right side.
- Readiness was recalibrated to a recovery-anchored model after a 13-day comparison against WHOOP recovery showed the weighted average compressing real crash days into 76–95 "High": the autonomic core (HRV-led, with resting heart rate) now maps through a logistic curve and sleep, training load, and vitals anomalies apply bounded multiplicative penalties, so typical days read Moderate (~65–79), crash days drop into Low/Poor, and extreme breathing/temperature/blood-oxygen anomalies cap the score at 25.
- Readiness now scores overnight (sleep-window) HRV, heart rate, respiratory rate, blood oxygen, and wrist temperature whenever at least 14 nights of hydrated sleep vitals exist in the 56-day baseline window — whole-day averages had masked overnight physiology (e.g. a daytime HRV average of 89 ms on a morning WHOOP scored 17) — with the HRV+heart-rate pair switching sources atomically and falling back to the previous whole-day behavior for users without sleep tracking. Historical readiness trend scores are recomputed wholesale under the new model.
- Updated the app, widget, and test bundle version to 0.9.2 build 2.

## 0.9.2 (build 1)

- Performance: cold launch no longer decodes lazily loaded intraday chart samples on the main thread — they live in a sidecar cache hydrated in the background after the first frame, and the current-month workout snapshot is read once at launch instead of twice.
- Performance: full refresh batches sleep-vitals hydration into five window-wide HealthKit queries partitioned per night in memory, replacing up to ~1,800 per-day queries.
- Performance: workout heart-rate samples are partitioned per workout with binary search instead of rescanning the month's samples per workout, and effort-score fetches run with bounded concurrency.
- Performance: metric-detail pull-to-refresh extends cached intraday samples incrementally instead of refetching the full trend window of raw samples, and metrics that do not feed Readiness skip the readiness recompute.
- Performance: Summary metric cards precompute their preview points once per model update instead of regrouping the full trend series several times per render, metric detail views slice the intraday day series once per selected day instead of rescanning it on every render, calendar and workout text reuses cached date formatters, and the Settings cache row reads disk sizes off the main thread.
- Performance: widget timeline reloads are coalesced to a single reload per refresh, and cached workout months are capped in memory.
- Fixed the snapshot save-if-changed compare: `JSONEncoder` randomizes key order between encodes, so every refresh previously rewrote all snapshot caches and requested widget reloads even when nothing changed. Snapshot encoders now emit sorted keys, making the byte compare reliable.
- Updated the app, widget, and test bundle version to 0.9.2 build 1.

## 0.9.1 (build 3)

- Fixed the Steps trend card icon to use the walking figure instead of the Active Energy flame.
- Clear Cache now also deletes the shared health widget snapshot so the Health Metric, Health Trend, and Sleep Stages widgets empty out with the rest of the local cache, and the Settings cache size readout includes that file.
- Skin Temperature baseline deviation now converts to the selected temperature unit on the Summary card, the detail header, and the Health Metric widget, matching the detail chart's annotation.
- Refresh entry points now claim the refresh slot before requesting HealthKit authorization so concurrent triggers can no longer start overlapping full refreshes or dismiss the loading overlay early.
- The small Health Metric widget now shows its empty state for metrics without chartable data instead of a blank chart with "--".
- Cumulative metric summaries (Steps, Active Energy, Resting Energy, Exercise Minutes, Time In Daylight) now report only today's total instead of showing yesterday's full-day total under the Current label before today's first sample.
- Hardened cached dashboard decoding so an unreadable readiness blob degrades to "Needs Data" instead of discarding the entire cached snapshot.
- Removed an unused duplicate activity-ring month key helper from `HealthKitWorkoutStore` and refreshed stale "May 2026 seed" references in README/TestPlan plus the Health Trend widget's header comment.
- Updated the app, widget, and test bundle version to 0.9.1 build 3.

## 0.9.1 (build 2)

- Added iPad support with a two-column dashboard, a side column for trends, larger preview charts, and readable width limits on the dashboard, workouts, settings, and metric detail screens.
- Enabled landscape orientation on iPad.
- Removed an unused Sign in with Apple entitlement from the widget extension so automatic signing succeeds.
- Renamed the Wrist Temperature metric to Skin Temperature across the app, widgets, and the Health permission description.
- Updated the app, widget, and test bundle version to 0.9.1 build 2.

## 0.9.1 (build 1)

- Updated the app, widget, and test bundle version to 0.9.1 build 1.

## 0.7.0 (build 2)

- Updated the app, widget, and test bundle version to 0.7.0 build 2.

## 0.7.0 (build 1)

- Added average heart metric cards below Day View for Heart Rate and HRV, with HRV limited to sleep averages.
- Fixed Summary trend bar overflow and kept Day View activity highlight headers consistently thin across y-axis scales.
- Updated the app, widget, and test bundle version to 0.7.0 build 1.

## 0.6.0 (build 2)

- Updated the app, widget, and test bundle version to 0.6.0 build 2.

## 0.6.0 (build 1)

- Updated the app, widget, and test bundle version to 0.6.0 build 1.

## 0.5.6 (build 4)

- Added Settings > Data > Source with global primary and secondary Apple Health source defaults, an option to combine duplicate source names, and per-metric overrides still available from detail pages.
- Combined source names now treat `iWatch X` and `iWatchX` as the same `iWatchX` source and preserve both underlying HealthKit sources for combined queries without broadening matching for unrelated names.
- Fixed combined sleep-source timelines so generic sleep intervals from another source are kept when they add time outside detailed sleep-stage samples.
- Updated the app, widget, and test bundle version to 0.5.6 build 4.

## 0.5.6 (build 3)

- Redesigned the workout detail heart rate chart with a smoothed gradient line (cyan → red by BPM intensity), faded color-coded scatter dots per raw sample, a horizontal average reference line, and inline header (title + min-max range) plus right-side Y-axis tick labels matching the Apple Health style.
- Updated the app, widget, and test bundle version to 0.5.6 build 3.

## 0.5.6 (build 2)

- Added step-count day-line support with hourly totals and secondary-source comparison handling.
- Moved wrist temperature baseline context into the primary trend chart with a dashed baseline and selection deviation annotation.
- Updated the app, widget, and test bundle version to 0.5.6 build 2.

## 0.5.6 (build 1)

- Readiness scoring now honors the configured sleep goal when computing the current score and readiness trend series.
- Wrist temperature baseline displays now use a median baseline so card copy stays aligned with Readiness's robust baseline behavior.
- Added dedicated Readiness calculator coverage for sleep-goal forwarding, robust baselines, z-scores, and empty-signal behavior.
- Updated the app, widget, and test bundle version to 0.5.6 build 1.

## 0.5.2 (build 4)

- Cut cold-launch dashboard refresh latency by eliminating N+1 HealthKit queries: workout heart-rate samples are now fetched per month via a single OR'd compound predicate and partitioned in memory, per-workout `HKWorkoutEffortScore` fetches run concurrently via `withTaskGroup`, and the per-sleep-day `fetchSleepVitals` loop runs through a bounded (16) `withTaskGroup` helper.
- Memoized the shared 180-day training-load workout fetch so `fetchTrainingLoadSummary` and `fetchTrainingLoadSeries` no longer issue duplicate queries within the same refresh.
- Refresh now publishes progressively: summary, trends, and Activity Ring history each write to `@Published` state as soon as their fetch completes (three publishes instead of one at the end). Per-month workouts also publish individually as each task-group result lands. Readiness is preserved at its cached value during the stream and recomputed once at the end.
- Persisted `lastSuccessfulRefreshDate` in `UserDefaults` so cold-start applies the same tiered TTL as a warm resume (`<60 s` skip, `60 s–5 min` current-month workouts only, `≥5 min` full refresh). Previously, every cold-start fell through to a full refresh because the timestamp lived only in memory.
- Added a `PrivacyInfo.xcprivacy` manifest declaring required-reason API usage (`NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`). `NSPrivacyTracking` is `false`; no data is collected externally.
- Updated the app, widget, and test bundle version to 0.5.2 build 4.

## 0.5.2 (build 3)

- Extracted a new `HealthKitFetchEngine` actor (`Body/Services/HealthKitFetchEngine.swift`) that owns `HKHealthStore`, the cached source map, predicate construction, every HealthKit query, and the dashboard fetch orchestrators (`fetchHealthSummary`, `fetchHealthTrends`, `fetchHealthDashboardSnapshot`, `fetchHealthDataSourceOptions`). `HealthKitWorkoutStore` shrank from ~3,900 to ~1,450 lines and now keeps only the `@Published` view-model state, public refresh entry points, and snapshot publishing — it delegates fetching to the engine via `await`. The bulk of the fetch-time Swift work no longer runs on `@MainActor`.
- Mirrored the three selections (`permissionSelection`, `healthDataSourceSelection`, `secondaryHealthDataSourceSelection`) onto the engine; the store syncs them via `setPermissionSelection` / `setHealthDataSourceSelection` / `setSecondaryHealthDataSourceSelection` whenever the user updates a permission or picks a different source.
- Updated `BodyTests/ProjectConfigurationTests.swift` so the four string-grep assertions covering moved HealthKit internals point at `HealthKitFetchEngine.swift` instead of `HealthKitWorkoutStore.swift`; semantic assertions are unchanged.
- Updated the app, widget, and test bundle version to 0.5.2 build 3.

## 0.5.2 (build 2)

- Incrementally load intraday metric day-view samples after the cached tail so detail screens fetch only new HealthKit samples on subsequent opens.
- Updated the Readiness detail header to show score and status directly.
- Deferred the cached-dashboard readiness recompute out of `HealthKitWorkoutStore.init`. The first frame paints from the cached `summary.readiness` value (correct as of its last successful refresh); the next refresh recomputes Readiness off the main thread.
- Moved the per-refresh `recalculatingReadiness` (day-by-day baseline iteration over ~365 trend points) into a `Task.detached(.userInitiated)` inside `updateHealthDashboardSnapshot` so it no longer blocks the main thread.
- Moved `HealthDashboardSnapshotStore.save` and `WorkoutSnapshotStore.save` / `savePrevious` + `WidgetCenter.shared.reloadAllTimelines()` into `Task.detached(.utility)` so JSON encode + atomic write + widget XPC round-trip no longer run on the main actor during refresh.
- Updated the app, widget, and test bundle version to 0.5.2 build 2.

## 0.5.1 (build 2)

- Expanded home Summary trend cards from a fixed 28-day comparison window to candidate windows up to one year (28/90/180/270/365 days), each with its own minimum segment size and preferred recent length; the card now picks the most meaningful window per metric and tiebreaks by data coverage so sparse metrics still default to the shortest fitting window.
- Cached trend card window selection behind a lightweight series fingerprint so the home Summary no longer recomputes comparisons on every view rebuild - only when the underlying data, units, or current day changes.
- Capped trend card preview charts at 60 visual points via per-segment bucketed averaging that preserves the baseline/recent boundary; longer windows render smoothed buckets while comparison math still uses full-resolution daily values.
- Trend card period labels and message phrasing now scale with the chosen window length (days for under 28, weeks for 28-89, months for 90+).
- Updated the app, widget, and test bundle version to 0.5.1 build 2.

## 0.5.1 (build 1)

- Improved HealthKit refresh performance by moving daily trend aggregation into `HKStatisticsCollectionQuery`, pairing average/range queries for vitals, and lazy-loading intraday day samples only when metric detail screens open.
- Reduced background refresh churn with continuation-based refresh completion waits, tiered app-resume refreshes, source-option caching, save-if-changed dashboard/workout snapshots, and widget reloads only when cached bytes change.
- Added a previous-month workout snapshot fallback for widgets so month rollovers can keep showing recent data until the app refreshes the new current month.
- Updated the app, widget, and test bundle version to 0.5.1 build 1.

## 0.5.0 (build 3)

- Added a Readiness Summary card that compares sleep, heart, training load, and sleep-window vitals against personal baselines, with confidence and driver explanations for missing or unusual signals.

## 0.5.0 (build 2)

- Added a "Loading data" overlay to every pull-to-refresh (Summary, metric detail, Workouts) that stays on screen until the underlying refresh finishes; the overlay also rides out any background refresh already in flight, and has a 600 ms minimum display so fast refreshes still register visually.
- Updated the Day View chart legend so it shows only "Avg N" without a source name when a single source is active, and falls back to the dot + per-source layout only when a secondary source is selected. The single-source style matches the existing range/trend chart legend.
- Increased Day View chart spacing for charts that overlay sleep/workout context icons (Heart Rate, HRV) so the icons no longer crowd the title row; the day chart now uses a dedicated taller layout constant.
- Updated the in-app How to Use guide with a new "Compare Two Sources" section, mentions of the loading overlay in Summary/Day Views/Workouts, and a note on the single-source vs. comparison legend behavior.
- Updated the README features section to reflect the two-source comparison flow, the loading overlay, and the secondary-cache invalidation on launch.
- Removed helper subtitles from the data source picker rows so source choices show only the source name.
- Updated the app, widget, and test bundle version to 0.5.0 build 2.

## 0.5.0 (build 1)

- Added two-source comparison for Sleep, Heart Rate, Resting Heart Rate, HRV, Blood Oxygen, Steps, Active Energy, Resting Energy, and Exercise Minutes: supported metric detail screens can overlay a secondary Apple Health source alongside the primary with shared x-axis buckets and per-source averages in the legend.
- Added a deterministic secondary-selection signature persisted alongside the dashboard snapshot so cached `*Secondary` series are zeroed out on launch when the comparison source has changed since the snapshot was written.
- Fixed the secondary source picker including whichever source was already chosen as the primary, which let users render two identical overlapping series; the secondary picker now filters out the active primary option.
- Fixed `updateSecondaryHealthDataSource` swallowing requests while another refresh was in flight; the call now waits for the in-flight refresh and then runs a focused per-metric refresh.
- Fixed a `ForEach` identity collision in comparison charts when two sources reported the same display name by introducing a `BodyHealthSourceRole` discriminator threaded through every chart entry id.
- Fixed `averageValue` accepting (and ignoring) a source argument; the API now lives on `BodyHealthSourceTrend`/`BodyHealthSourceRangeTrend` and accepts an explicit calendar/date for testability.
- Fixed the day-view chart legend showing a misleading "--" for an empty side; the legend now omits sides that have no data.
- Fixed bucket drift between primary and secondary series near midnight by anchoring each refresh's interval to a single `Date()` plumbed through `recentHealthTrendInterval` via a new `healthTrendAnchorDate` field.
- Fixed a race where rapid secondary-source changes could leak the new selection into still-running HealthKit queries; each secondary fetch helper now pins the option at entry instead of re-reading it inside every case.
- Performance: comparison chart inits no longer call `calendarPoints` three times for the x-domain; pre-computed entries are reused. Legend averages are computed once per render via stored `BodyHealthSourceLegendItem` rows instead of being re-walked inside the view body.
- Performance: secondary HealthKit fetches in `fetchHealthTrends` are now gated on the per-metric "No Comparison" state through a new `fetchSecondaryIfEnabled` helper, so default installs no longer spawn ~12 trivial `async let` tasks per refresh.
- Refactors: collapsed five near-identical `usesSourceComparison*` predicates into a single `supportedComparisonCharts: Set<SourceComparisonChartKind>` table; merged two `sourceComparisonChartCalendarPoints` copies into a shared private aggregator; unified three legend views into one `BodyHealthSourceLegend` driven by `[BodyHealthSourceLegendItem]`; replaced "primary"/"secondary" string literals with the `BodyHealthSourceRole` enum across all chart entries; hoisted unexplained magic numbers (`1.12`, `0.16`, the `*2` aggregation doubling) into named constants on `BodyHealthTrendRange`.
- Tests: added value-level coverage for `supportedComparisonCharts`, `BodyHealthSourceTrend.id` role discrimination, `BodyHealthSourceTrend.averageValue(in:calendar:date:)`, secondary-selection signature determinism, `HealthTrendSnapshot.clearingSecondarySeries()`, and `sourceComparisonChartDateOffset` for the six-month and year ranges; updated string-grep configuration tests to match the unified legend and pinned-option structure.

## 0.4.1 (build 2)

- Updated the in-app How to Use guide for Metrics settings, Data Refresh, Cache, and current Summary controls.
- Updated the app, widget, and test bundle version to 0.4.1 build 2.

## 0.4.1 (build 1)

- Updated the app, widget, and test bundle version to 0.4.1 build 1.

## 0.3.9 (build 2)

- Added Heart Rate, Wrist Temperature, and Training Load dashboard cards with dedicated detail charts.
- Added Training Load interval highlighting, selected-point interval updates, and interval distribution counts.
- Fixed long-range chart right-edge padding for month, six-month, and year views.
- Moved the dashboard cache out of UserDefaults into file-backed storage to avoid oversized preferences writes.
- Updated the app, widget, and test bundle version to 0.3.9 build 2.

## 0.3.4 (build 2)

- Added animated Summary metric number transitions and Activity Rings sweep updates.
- Updated the app, widget, and test bundle version to 0.3.4 build 2.

## 0.3.4 (build 1)

- Updated the app, widget, and test bundle version to 0.3.4 build 1.

## 0.3.3 (build 2)

- Added range-aware chart aggregation for six-month and year health charts, including averaged buckets and timeframe-aware selection labels.
- Added average values to the Basics weight/body fat legend and kept those labels visually secondary.
- Updated long-range and day-view line charts to use consistent point markers, capped dense line charts, and tuned bar widths for weekly and small-screen long-range views.
- Updated the app, widget, and test bundle version to 0.3.3 build 2.

## 0.3.3 (build 1)

- Updated the app, widget, and test bundle version to 0.3.3 build 1.

## 0.3.0 (build 1)

- Renamed the Home tab to Summary and moved workout visualizations into Workouts.
- Placed the monthly workout calendar above workout rows and merged monthly totals with the workout type breakdown at the bottom of Workouts.
- Updated the app, widget, and test bundle version to 0.3.0 build 1.

## 0.2.7 (build 3)

- Added Exercise Minutes, Wrist Temperature, Time In Daylight, and Steps as first-class Home cards with dedicated detail screens and matching bar or line chart previews.
- Added recent four-day preview charts to Home metric cards, including placeholder behavior for missing prior-day data and no preview placeholder for missing current-day data.
- Added Basics detail refinements for Body Fat/Weight ordering, selected chart annotation sizing, a separate BMI chart, and a timeframe-aware Difference Range card for Body Fat, Weight, and BMI above the Basics charts.
- Expanded Home card detail trend ranges from Week and Month to Week, Month, 6 Months, and Year.
- Updated Week and Month line charts to use colored lines and colored hollow point markers; longer ranges hide points, and the Year line is slightly thinner than 6 Months.
- Added range-transition safeguards so line chart dots rebuild immediately instead of lingering while moving to new positions.
- Added average labels across non-Basics trend charts, while leaving the combined Weight and Body Fat chart focused on its two-series comparison.
- Added a scaled gold completion star to the Home Activity Rings card when all three rings are complete today.
- Added Settings > Data > Permissions toggles so users can control which Health categories appear in Body.
- Added About cards for every metric detail page.
- Refined Sleep card sizing, Sleep Score display, Sleep Score sheet height, Sleep Stages date display, and Sleep Vitals chart layout.
- Updated the app, widget, and test bundle version to 0.2.7 build 3.

## 0.2.6 (build 7)

- Bumped the app, widget, and test bundle build number to 7.

## 0.2.6 (build 6)

- Fixed the `Issues.md` v0.2.6 audit findings across dashboard snapshot logging, health detail routing, workout calendar taps, workout filters, trend limiting, month-picker refresh, Activity Rings pagination, and widget/banner color consistency.
- Updated project build settings, app version fallback text, README, TestPlan, and issue-tracking documentation to match v0.2.6 build 6.
- Removed stale snapshot and HealthKit helper APIs that were no longer used by production code.

## 0.2.5 (build 5)

- Added Activity Rings history detail with lazy month pagination and safeguards against synthesizing unloaded months.
- Expanded Health dashboard tests for Activity Rings history, sleep vitals, trend chart behavior, and pagination gates.

## 0.2.4 (build 4)

- Added the Workouts tab with month browsing, sort and filter sheets, search, summary totals, and workout detail sheets.
- Moved current-month workout snapshot sharing to the app group's JSON file path used by widgets.

## 0.2.3 (build 1)

- Updated the app version to 0.2.3 build 1.
- Reverted completed Activity Rings to solid full-circle rendering after 100%.

## 0.2.0 (build 3)

- Added the initial SwiftUI app, WidgetKit extension, and Xcode project structure.
- Added read-only Apple Health workout sync for the current month.
- Added shared workout month snapshots for app-to-widget data handoff.
- Added a bold workout calendar UI for the Charts tab and large widget.
- Added app group, HealthKit entitlement, privacy manifests, app icons, and project configuration tests.
- Updated workout calendar styling so workout days use one solid-color Apple/SF workout icon selected by longest duration.
- Carried over Coin's star, moon, and sun count indicators for workout-day tiles.
- Added a Coin-style Home/Charts/Settings tab shell with app icon selection, Copyright, and Version rows.
- Added a large-only Workout Types widget that adapts Coin's By Category chart for workout duration by type.
- Removed the title/month header and inner card from the Workout Types widget so it matches Coin's full-widget breakdown style.
- Moved in-app workout visualizations into Charts and simplified Home health refresh to pull-to-refresh.
- Added Settings appearance choices for app theme and app accent color, defaulting the app accent to blue.
- Added Coin-style Home health cards for sleep, resting heart rate, weight, body fat, HRV, blood oxygen, respiratory rate, and BMI.
- Added secondary Home card visualization screens with 30-day line charts and dot markers.
- Added Charts drill-down sheets for tapped calendar days and workout type rows.
- Expanded Apple Health workout recognition so specific non-strength workout types no longer collapse into generic Workout.
- Simplified Home health cards by making Sleep the same size as other cards, reducing value typography, and removing range bars and non-functional navigation cues.
- Added widget background configuration for System, Black, and White backgrounds, matching Coin's widget appearance picker.
- Made in-app chart panel backgrounds follow the selected app theme instead of staying dark.
- Expanded workout type colors into a more distinguishable shared palette while keeping traditional strength training red.
- Added home health card icons, removed the sleep source label, and refresh Health data automatically when the app becomes active.
- Updated the in-app workout type chart to use the same full-widget layout as the Workout Types widget.
- Replaced the default Body 01 app icon artwork with the new blue icon.
- Added Pink and White app icon choices using Coin-style appicon and preview asset naming.
- Refreshed the Classic, Light, and Rose app icons and added Classic Alt, Light Alt, and Rose Alt as the second icon-picker row.
- Added Coin-style month history browsing to Charts with the latest three months preloaded and older months loaded on demand.
- Muted overly bright workout colors so calendar icons and By Type bars stay visually consistent.
- Switched in-app chart panels from the widget gradient to Coin's solid card background.
- Added a medium Workout Types widget that shows the top two workout types and kept the large widget capped at five.
- Made the in-app By Type chart height adapt to the selected month's number of workout types.
- Added a subtle fade between the fixed month picker and scrolling Charts content.
- Rebuilt workout type colors from the attached reference swatches only.
- Fixed the `Issues.md` audit findings across HealthKit sync state, sleep aggregation, locale units, widget families, accessibility, and settings consistency.
- Added a Settings Units section for System, Metric, and Imperial formatting.
- Added Active Energy and Resting Energy Home cards with daily bar-chart detail screens.
- Moved the Home card trend range option onto each detail screen with Coin-style Recent Week and Recent Month buttons.
- Added today's sleep-stage timeline to the Sleep detail screen and aligned Sleep summary duration with the latest sleep day bucket.
- Added Health-style sleep-stage transition shading and denser time labels to the Sleep detail timeline.
- Added average sleep duration labels to Sleep trend charts and a three-category Sleep Score card for today's Sleep detail.
- Added sleep-window vitals using HealthKit heart rate, respiratory rate, blood oxygen, and sleeping wrist temperature data.
- Replaced the Home VO2 Max card with Respiratory Rate and refreshed Blood Oxygen card coloring.
- Changed Sleep Vitals to an Apple-style high/typical/low region chart, with Sleep Duration as the fifth metric and red dots for high or low values.
- Moved the Sleep week/month trend charts to the end of the Sleep detail screen after score, stages, and vitals.
- Added a two-card-wide Apple-style Activity Rings card at the top of Home using HealthKit Activity Summary values and goals.
- Combined Weight, Body Fat, and BMI into a Basics Home card with a dual-axis Weight and Body Fat detail chart.
