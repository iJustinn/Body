# Version History

## 0.9.12 (build 16)

- Updated the app, widget, watch, and test bundle version to 0.9.12 build 16.

## 0.9.12 (build 15)

- **Draw Route is offered only for the styles that can draw.** The **Map** style composites its pace-colored route into the map snapshot rather than stroking it, so there is no line to grow: on Map the Draw Route switch in Settings > Workouts > Route Style is greyed out and inert, with the line "Not available with the Map style, which draws its route onto the map." in place of its usual subtitle, and a loading Map route shows the shimmer placeholder. Your stored preference isn't overwritten — picking Plain or 3D again brings the switch back exactly as you left it — and the Route Style row drops its `Draw · ` prefix while Map is selected.
- **The warning card's threshold rule is bolder and no longer labelled.** The dashed yellow line doubled in thickness, and the yellow value that rode above or below its right end is gone — the sentence over the chart already names the threshold.
- **Heart rate on a workout's detail page now reads `bpm` rather than `BPM`** — average heart rate, Max Heart Rate, and HR Recovery — matching the lowercase unit abbreviations the rest of that page's cards already use.
- **Both chart-switch buttons wear the app's glass chip** — the workout cards' own translucent fill under a thin white rim — with a grey glyph matching the calendar's day numbers: `chart.bar.yaxis` on the calendar, `square.grid.2x2` on the breakdown.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 15.

## 0.9.12 (build 13)

- **Metric warning cards now stand exactly as tall as the trend comparison card below them.** Their chart grew from 128 to 205 points, absorbing the divider and averages row the comparison card carries and they do not, so the two cards read as a matched pair on a metric detail page instead of the warning sitting short.
- **The warning glyph on the home preview cards is a little smaller** — 20 points instead of 24, matching the glyph inside the warning card itself.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 13.

## 0.9.12 (build 12)

- **A workout's route now draws itself in instead of appearing all at once.** Body checks whether a workout has a GPS route before its fixes finish loading, so the detail page moves into the with-route layout up front rather than dropping the stats ~324 pt part-way through. The route then strokes itself on from start to finish over about a second in the **Plain** and **3D** styles. Reopening a workout whose route is already loaded still shows it instantly with no replay, and Reduce Motion skips the draw while keeping the steadier layout. Settings > Workouts > Route Style gains a **Draw Route** switch (on by default) at the top of the sheet, above the style rows; with it off the reserved area shimmers and cross-fades to the route instead. The Route Style row reads **`Draw · 3D`** while the draw is on, and just the style name when it's off. The route's city label is also fetched separately from the fixes now, so the trace no longer waits on a reverse-geocode round trip.

- **The Workouts page now shows one chart at a time.** The workout calendar and the activity-type breakdown share a single card slot at the top of the page, and the breakdown no longer sits at the bottom below the workout list. A small button in each card's bottom-right corner switches to the other chart — on the calendar it takes the last cell of the final week row, dropping onto a new row of its own when the month fills that row exactly; on the breakdown it sits at the end of the last bar's row, which gives up a little of its bar length to make room rather than crowding the activity name. The calendar shows by default, the two cards cross-fade into each other, and the pick is remembered across launches. The monthly totals stay part of the breakdown card, so they now appear alongside the bars rather than on every visit. The Home Screen widgets are unchanged.
- **Metric warning cards are a little taller.** Their chart now stands at the home trend comparison card's height, so the two stack at the same size instead of the warning sitting slightly short.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 12.

## 0.9.12 (build 11)

- **The metric warning card's chart now draws in the same hand as the Day View and range trend charts.** Its readings are the shared ringed dot — hollow, tint-stroked, at the Day View's own diameters — instead of small flat discs, and the past-threshold readings take the filled form those charts reserve for their latest point, so they still stand out in yellow.
- **The Readiness Week chart's current-readiness dot now morphs instead of blinking.** Hiding it — a scrub callout going up, or a switch to Month/6 Months/Year — sends it climbing into today's plotted morning point directly above it as it fades, and releasing the scrub drops it back out of that point. Reduce Motion keeps the instant appearance/disappearance.
- **A workout detail page's header now reads the start time only** — "Mon, May 11 - 3:57 PM" instead of "3:57 PM-4:58 PM". The share card still carries the full start-end range.
- **Workout share cards gain selectable aspect ratios (Body Pro).** A new **Ratio** tray offers Portrait 9:16 (default, free), Landscape 16:9, Portrait 4:5, Landscape 5:4, and Square — the four non-9:16 shapes carry a lock badge and open the paywall for non-Pro users, and a stored non-9:16 pick silently falls back to 9:16 for the session, without overwriting the stored choice, if Pro lapses. The Body Pro page's feature list adds a new **Share Card Sizes** entry. Export is the card at 3× on the short side: 1080×1920, 1920×1080, 1080×1350, 1350×1080, or 1080×1080, and the Map background re-snapshots per ratio.
- **A new Arrange tray sets the landscape layout.** On a landscape ratio with a route, Stacked (route over a metrics row) or Side by Side (route beside a metrics column) controls how the centered card lays out the route and metrics; it's greyed out while the Map background is active, since Map bakes the route into its own snapshot.
- **The share page is now an Instagram-Story-style composer.** The option strip below the preview is gone — a vertical icon rail (Font, Ratio, Arrange, Route Color, Background, 3D, Metrics) sits over the trailing (right) edge of the full-bleed preview, and tapping an icon expands a tray of that option's tiles out to its left, one tray open at a time; tapping the preview closes the open tray.
- **Workout cards animate as they arrive.** A workout landing on the Workouts page while it's open — an app-foreground sync, a pull-to-refresh, or a month's first load — fades its card in while the cards around it glide to their new places, instead of the whole list jumping. Rows entering or leaving on a search/filter change fade the same way, and the list ↔ "No Workouts Found" swap now cross-fades. A re-sort keeps its existing re-order animation, a month switch keeps its single cross-fade, and a refresh that finds nothing new moves nothing at all. Reduce Motion swaps everything instantly.
- **You can now pick which metrics a workout share card shows (Body Pro).** A new **Metrics** rail icon (last on the rail) opens a chip strip under the preview listing every Details metric the card can render for that workout plus Time and Distance; pick 1 to 3 and the card follows immediately. The pick is remembered per workout type and treated as a preference — a later workout of that type that lacks one of them simply drops it, falling back to the automatic pick when none survive. Free users see a locked Metrics icon that opens the paywall and keep the automatic pick, and a Pro lapse falls back the same way without erasing what's stored. On the Map card the header already carries Distance and Duration, so its bottom row shows the other picks. The route-less card's stack now holds up to three metrics instead of four.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 11.

## 0.9.12 (build 10)

- **Workout share cards gain a 3D route ribbon (Body Pro).** The Background section for a route workout now shows two labelled rows, **2D** (today's flat trace) and **3D**, on all four backgrounds. 3D draws the route as an elevation ribbon — oblique on the gradient presets and photo background, and rising straight up off the actual roads (with the pace-colored line and start/end markers riding the lifted line) on Map. 3D is gated behind Body Pro — its tiles carry a lock badge and open the paywall on tap — and a stored 3D pick silently falls back to 2D for the session, without overwriting the stored choice, if Pro lapses or the route lacks usable elevation data. A route with no altitude data greys the 3D row out entirely with the line "3D needs a route with elevation data." The Body Pro page's feature list adds a new **3D Route Share** entry.
- **A new Font row** on the share strip lets you pick Rounded (default), Standard, Serif, or Monospaced for the card's text — the Body wordmark always stays Rounded — remembered across shares, on both route and route-less workouts.
- **A new Route color row** (route workouts only) recolors the card-drawn 2D trace and 3D ribbon — Body Blue (default), Workout Color, White, Black, Orange, Green, or Pink — remembered across shares; it's greyed out while Map is the active background, since the map keeps its own pace-colored line.
- **Photo backgrounds get a two-step adjust.** Picking a photo now opens a **Photo** step first — drag to move the photo, pinch to zoom (centered anchor), double-tap to reset — clamped so the photo always keeps the card fully covered, then a **Next** button (or the Photo \| Layout toggle) advances to the **Layout** step for today's route/metrics block placement. Both adjustments are baked into the export together and reset on a new photo pick or on leaving photo mode.
- The route-less share card's type glyph is now smaller (30 pt, down from 56 pt).
- On the centered (preset/photo) share card, the route's lowest point is now bottom-anchored and the metrics stack top-anchored, so the gap between them stays a fixed 42 pt regardless of the route's shape.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 10.

## 0.9.12 (build 9)

- **Metric warnings gain per-warning custom thresholds.** Settings > Metrics > Warnings now shows one card per warning (Low Heart Rate, High Heart Rate, Low Blood Oxygen), each with its toggle plus a new **Threshold** row: tapping its value pill opens a wheel-picker popover to set a custom threshold, with a **Use Default** button to clear the override. Changing a threshold immediately refreshes that warning's glyph and card without waiting for a fresh Apple Health fetch, and every subtitle (in the sheet, and the badge/card copy) reflects the effective threshold.
- **High Heart Rate's default threshold is now the lower bound of heart-rate zone 3** — 70% of your estimated max heart rate, read from your Apple Health date of birth — instead of a flat 120 bpm; without a birth date on file it still falls back to 120 bpm.
- **High Heart Rate ignores workout recovery too.** Readings within 30 minutes after a logged workout's end no longer trigger the warning (cool-down heart rate is still elevated), the card explains that a warning during a workout clears once the workout is logged, and the threshold label now sits at the right end of the dashed rule — above it for Low Heart Rate and Low Blood Oxygen, below it for High Heart Rate.
- The Home-card warning glyph now **fades in and out** as the warning appears and clears instead of popping (instant under Reduce Motion).
- A metric detail's warning card now **animates its chart** the same way the day chart does when the selected day or its underlying samples change, instead of popping to the new data.
- A workout detail's Effort card now reads **Body's prediction: Calculating…** while the estimator's inputs (the 30-day comparison history and your max heart rate) load, and the settled number crossfades into its place — the same stand-in-then-crossfade the Details card's legend uses, on the same curve. The line no longer appears out of nowhere once the estimate lands; a workout that settles without a usable signal fades the stand-in away instead of cutting it, and Reduce Motion swaps both instantly.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 9.

## 0.9.12 (build 8)

- The workout detail's 3D Route Style hero now rotates: a horizontal swipe on the route area turns the elevation ribbon about its vertical axis, in either direction. The rest framing — the size and centering the ribbon starts at — stays exactly what it was before and holds constant while you turn it, so the hero never rescales mid-gesture. Tap still opens the full-screen map, and VoiceOver gains **Rotate Left** and **Rotate Right** actions on the hero.
- Every workout detail page — reached from the Workouts list or from the calendar/list's full-screen popup — now shows a glass circle **Back** button top-left, matching the Share button's chrome on the opposite corner, so there's always a visible way back without relying on the edge swipe.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 8.

## 0.9.12 (build 7)

- The Summary grid's **Basics** card now leads with an open-arms figure glyph in place of the plain person silhouette, matching the figure symbols the rest of the app's activity icons use. The Basics detail page's header carries the same glyph, so the card→detail zoom no longer swaps icons mid-flight.
- The activity rows in a metric detail page's by-activity card — **Heart Rate by Activity**, **Energy by Activity**, **Average HRV**, and **Impact by Activity** — now crossfade their icon when the selected day changes. Rows hold their position rather than their activity, so a slot whose activity changes dissolves its glyph, tinted tile, and name into the new activity's while the numbers beside them roll, on the same curve, instead of the row being swapped out; a day with fewer or more activities drops or adds its trailing rows on that curve too. Nothing animates under Reduce Motion.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 7.

## 0.9.12 (build 6)

- The home Readiness star hero can now show an **Apple Intelligence** comment in place of its authored one-liner. When today's score is available, Body hands only qualitative readiness facts — the status band, each driver signal in plain words, and whether today's workouts noticeably or slightly drained the score, never any number — to the on-device system language model as a rewrite brief — Body's own authored explanation for today as the reference comment, plus what's below usual and Body's training verdict and advice for the band — which it rewords into one or two sentences in the device's language and in the voice of Body's authored explanations: every signal that's below usual, then advice that matches the verdict (Prime/High/Moderate train, Low/Poor rest or go easy, a real same-day workout drain reads as earned load). It speaks about readiness only, never quotes scores or points (those are already on the hero) and never mentions the app or its data. Nothing is generated until today's Health refresh has finished, so a cold launch from a stale snapshot never produces a comment about a half-loaded score. Comments are kept to very plain sentences: a reply that echoes the brief back (field labels, more than one paragraph) or uses a dash or semicolon is rejected in favor of the authored line. **Press and hold the comment for 3 seconds** to throw it away and have Apple Intelligence write a fresh one. While the model writes, the hero shows a **Generating comment…** placeholder rather than flashing the authored line first, and every change of that slot — placeholder to comment, or one comment to the next — crossfades, with the Apple Intelligence glyph leading the sentence inline so wrapped lines run the full width (no fade under Reduce Motion), VoiceOver reads it as part of the hero's label, and it regenerates only when the readiness state actually changes: a new score, a workout drain, a day rollover, or a language change. Everything runs on device — no health data leaves the phone — and the last comment is cached so a relaunch shows it immediately; Settings > Data > Cache > Clear Cache purges it along with the rest. Turn it on or off under Settings > **AI** > **Readiness**, where it defaults to On. The feature needs iOS 26 or later on a device with Apple Intelligence enabled in a supported language; without that the row reads **Unavailable** with its toggle disabled, and Body's own authored explanation is shown instead — as it also is whenever the setting is off or a generation fails.
- The workout Share button now appears on every workout's detail page, not just ones with a GPS route — it fades in once the route fetch settles rather than only when a route loads. Indoor and other route-less workouts (strength, yoga, HIIT, …) get the same share flow with the map tile dropped: a route-less card shows the workout-type symbol above a centered stack of up to four metrics (Distance, Pace/Speed, Time, and now Active Energy, with elevation or avg heart rate filling any remaining slots), on the same Midnight/Workout Color presets and Pro photo background with drag/pinch, exporting at the same 1080×1920. A Map background remembered from a route workout opens on Midnight instead for a route-less share, without overwriting the remembered choice.
- Workout detail's Route Style gains a third option, **3D**: an oblique, north-up elevation ribbon in the workout's tint (lifted line, translucent walls, faint ground trace), exaggerated up to 30% of the route's width for climbs of 200 m or more, with a flat route still shown as a raised plank — it needs at least half the route's fixes to carry altitude, else it falls back to Plain. Settings > Workouts > Route Style is now a picker sheet in the Star Metric row style (icon tile, title, subtitle, checkmark) instead of chips.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 6.

## 0.9.12 (build 3)

- New **Cardio Fitness** metric. A Summary grid card reads your latest VO₂ max estimate from Apple Health and shows it above a four-row levels preview, with a ring marking which of **Low**, **Below Average**, **Above Average**, or **High** the reading falls in; the ring glides between rows when a new reading moves you. The detail page shades your level behind the trend line, lists all four levels with their VO₂ max spans in an **About your level** card, and breaks the range down under **Days by Level**. Levels compare you against people of the same age and sex using published FRIEND registry percentiles, cut at the 20th, the median, and the 75th, and are available from ages 20 through 79; without a date of birth and biological sex in the Health app the chart still draws but no level is claimed. Because Apple Watch records one estimate per qualifying Outdoor Walk, Run, or Hike rather than continuously, this chart plots every reading on its own measurement date instead of averaging into buckets, so short ranges are often legitimately empty. A **Cardio Fitness** trend card also joins the Summary trends list and the bottom of the detail page, comparing a recent run of readings against the ones before it; it needs three readings on each side rather than the days-with-data every other trend card asks for, which no realistic VO₂ max cadence could reach. Enable it under Settings > Data > Permissions > **Cardio Fitness**, and turn the trend card off in Settings > Metrics > Trend Cards.
- The workout detail's **Details** card no longer leaves a `0%` stand-in on a tile once its 30-day comparison has settled. The stand-in now appears only while the line beside the heading reads `Calculating…`, so a zero is never shown as a measured result under `vs 30-day avg` or alongside `Not enough history yet`.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 3.

## 0.9.12 (build 2)

- The workout detail's **Details** card now names the state of its 30-day comparison instead of silently showing nothing: the line beside the heading reads `Calculating…` while the history loads and `Not enough history yet` when there isn't enough of it, with a `0%` stand-in on every comparable tile. When the history lands the badge digits roll over to the real percentages and the line crossfades back to `vs 30-day avg`. A stuck window (Workouts permission off, Apple Health unavailable, a failed fetch) settles to `Not enough history yet` rather than calculating forever.
- The Sleep detail's stage breakdown rolls its numbers over when the selected day changes — Pct. and Duration in the optimal-range view, and each stage's duration plus the Restorative line in the plain-durations view.
- The Vitals detail headline now rolls its digits when only the outlier count changes ("2 Outliers" → "5 Outliers") and keeps crossfading when the words change.
- Updated the app, widget, watch, and test bundle version to 0.9.12 build 2.

## 0.9.12 (build 1)

- Updated the app, widget, watch, and test bundle version to 0.9.12 build 1.

## 0.9.11 (build 13)

- **Basics and BMI charts join the range-switch morph.** Switching Week/Month/6M/Year on the Basics detail page used to crossfade the dual-axis Weight & Body Fat chart and the BMI chart to the new range. Both now morph like every other trend chart: the lines stretch between the dates they share, dots glide to their new positions, and points with no counterpart in the new range fade in or out where they stand. Reduce Motion still swaps instantly.
- **Longer ranges now morph instead of appearing.** The Heart Rate-style min-max pages and the Vitals outlier chart were handed only the selected range's history, so a switch to a longer range could still only morph the marks the short range already covered — everything older popped in. Every morphing chart now receives the full history it needs to hold those marks ready.
- **Chart legends roll their numbers over too.** The labels beside a chart — a source comparison's "Apple Watch Avg 784 kcal" rows, the "Range 9-241 ms" header on the min-max pages, the Basics legend's averages, and every other "Avg …" header — used to hard-cut to the new figure while the chart morphed under them. Their digits now flip in place, in the same motion and timing as the hero value above them (instant with Reduce Motion).
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 13.

## 0.9.11 (build 12)

- **Range-switch morph animation.** Switching Week/Month/6M/Year on standard metric pages and the Heart Rate-style min-max range pages now morphs the chart instead of crossfading it: bars slide and shrink/extend as the time window zooms, the line stretches and dots glide to their new positions, marks with no counterpart in the new range fade in/out, and shared bucket dates (always including today's mark) morph value-to-value. The two-source comparison charts (bar, line, and min-max range) and the Vitals outlier chart morph the same way, so pages like a two-source Active Energy, Skin Temperature, and Vitals join in; Basics and BMI keep their crossfade for now. Reduce Motion swaps instantly.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 12.

## 0.9.11 (build 11)

- **Sleep stage breakdown defaults to the optimal-range bar chart.** The tappable breakdown below the stage timeline now opens showing the bar-chart view (stage percentages with their optimal-range bands) instead of the text durations; tapping still flips between the two and the choice still persists.
- **Sleep stage timeline gets a collapse-and-expand date-switch animation.** Changing the selected day used to crossfade the whole stage chart. Now every Awake/REM/Deep segment sinks onto the Core row with its color blending smoothly into the Core tint — the connector lines between segments shrinking and recoloring in step — until everything merges into a single flat Core-colored band, and the new day's segments grow back out of it up to their stage rows, colors returning as they rise. Nothing slides sideways: each night is drawn as a fraction of its own bed-to-wake span, so the segments resize where they stand and the start/end times roll their digits over in place, in step with the card's duration. The whole move takes as long as that numeric flip (naps card included; instant with Reduce Motion; rapid day flips retarget the in-flight animation).
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 11.

## 0.9.11 (build 10)

- **Day View line tails now fade during day switches.** Stretches of the hourly-average line covering hours the new day has no data for used to freeze in place through the whole transition and then vanish, making the chart look stuck before redrawing. The line is now drawn as per-hour segment marks with day-stable identity — matching stretches morph, and stretches with no counterpart fade out where they stood.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 10.

## 0.9.11 (build 9)

- **Day View placeholder dots are now truly invisible.** Build 7's cross-day fade keeps a dot mark alive for every hour so dots fade instead of popping, but the placeholders for data-less hours drew fully visible — constant-height dot rows after switching to a sparser day, and twin dots beside isolated readings — because Swift Charts does not apply mark opacity to custom symbol views. The transparency now lives inside the dot symbol itself, so hours without data render nothing while the fade behavior stays.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 9.

## 0.9.11 (build 8)

- **Sleep Regularity card polish.** The top time label in the chart's right gutter is no longer cut off when its grid line sits on the plot's upper edge, and the day axis now shows bare day numbers instead of the locale's suffixed form (e.g. `12` rather than `12日`).
- **Swipe from the left edge to close the Readiness detail.** It is presented as a cross-fade overlay rather than a navigation push, so it never got the system's interactive back gesture that every other detail page has. A left-edge swipe now closes it with the same cross-fade as its back chevron.
- **Bigger tap target on the workout Share button.** The route map behind the workout detail page opens full screen when its area is tapped, and a near-miss on the Share capsule — or a hit on one of its rounded corners — used to land on the map instead. The button now carries invisible tap slop on its sides and bottom.
- Hike workouts now read 徒步 in Simplified Chinese.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 8.

## 0.9.11 (build 7)

- **Day View day switches now morph in place.** Changing the selected day no longer slides chart marks sideways or folds the line into mid-animation zigzags: hourly bars shrink or extend and dots move vertically within their hour, sleep/workout highlight regions shrink or extend into the new day's same-type regions (main sleep to main sleep, naps in order, workouts matched by type), and marks or regions with no counterpart on the new day fade in or out. Under the hood, marks now plot on a fixed reference day so the chart's x-domain never moves, and highlight regions carry day-stable identity.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 7.

## 0.9.11 (build 6)

- **Custom data sources (Body Pro).** Settings can now combine several discovered Apple Health sources into one named source for primary or comparison charts. Custom groups sync to the Apple Watch compute seed, preserve their setup if Pro lapses, and return automatically when entitlement is restored.
- **Sleep Stages card now shows only the main session.** A daytime nap no longer stretches the night's hypnogram across the whole day; the card (and the matching Home Screen widget) draws only the day's auto-detected primary session, while total sleep duration elsewhere is unchanged. The Heart Rate, HRV, Active Energy, Steps, and Readiness Day View charts likewise shade the night and each nap as separate sleep bands (nap bands get a moon icon) instead of one block spanning bedtime to the nap's end, and the Heart Rate/HRV "Sleep" activity-average row now averages over the night only.
- **New Nap Stages card.** On a day with naps, a card matching the Sleep Stages card's style appears below it, combining every nap into one hypnogram (nap times read off the chart's x-axis) with the total nap duration in its header.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 6.

## 0.9.11 (build 3)

- **Day View now renders instantly.** A metric detail's Day View used to show "No data for this day" until a fresh Apple Health fetch completed; it now renders cached intraday data immediately on entry, then refreshes in the background on every visit (same refresh cadence as before).
- **Day View chart animations.** When the background refresh lands, chart marks morph to their new positions and new data fades in; switching days glides each dot, line, and range bar to the new day's values — the same dot morph the sleep Vitals plot uses; Reduce Motion disables the chart motion.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 3.

## 0.9.11 (build 2)

- Added an **About your interval** card to the Training Load detail, directly above the About Training Load card. It mirrors the Readiness "About your score" card: every interval (High Injury Risk → Medium Injury Risk → Optimal → Resting) with its ratio range and a one-line explanation, and a Current chip on the band the displayed ratio falls in — which follows the trend chart while you scrub, as Readiness's does.
- The Heart Rate and Respiratory Rate details' **Day View** now draws hourly range bars: behind the hourly-average line, each hour gets a translucent gray capsule spanning its lowest-to-highest sample — the same treatment their Week/Month/6 Months/Year chart gives each day — and the y-axis widens to fit those extremes. Only these two day views get them; a compared secondary source still contributes just its line.
- The Vitals card's dots preview now shows a **pending state** instead of disappearing while last night's vitals haven't arrived: the same three regions render dimmed with five gray rings resting in the typical band, and when the assessment lands the band takes its color and the rings glide to their regions (and colors) in one animation. Reduce Motion still lands on the same end state without the movement.
- Updated the app, widget, watch, and test bundle version to 0.9.11 build 2.

## 0.9.11 (build 1)

- Updated the app, widget, watch, and test bundle version to 0.9.11 build 1.

## 0.9.10 (build 21)

- **Vitals chart axis labels removed.** The Vitals detail hero's Week/Month/6 Months/Year charts no longer draw the trailing High/Typical/Low y-axis labels — the bars and the highlighted typical band carry the reference on their own, and the plot takes the freed trailing width.
- Fixed the Readiness detail's "About your score" card marking the wrong band as Current (e.g. Moderate flagged while the displayed score read 64, a Low value): while nothing is scrubbed, the Current chip and the chart's highlighted status band now follow the same live score the hero displays instead of the last plotted (frozen morning) point, which can land in a different band. Scrubbing and the drained-score dot behave as before. The same idle fallback applies to the Training Load interval band.
- Moved the About your score card to the bottom of the Readiness detail, just above the About Readiness card, and enlarged its title to match the other About cards.
- **Body Pro purchase/restore feedback.** A completed purchase whose Pro entitlement hasn't resolved yet now performs one bounded network re-check and then replaces the buy card with a dedicated "Purchase Completed / Body Pro isn't unlocked yet" recovery card (the purchase button is withheld so a paying customer is never invited to buy again; Restore stays enabled as the recovery path), instead of silently returning to the buy card. Restore distinguishes three outcomes: it re-unlocks Pro, shows the same recovery card when the lifetime purchase exists but its entitlement is inactive, and says "No purchases to restore." only when no purchase exists. Any lingered notice clears automatically once Pro actually unlocks.
- Fresh installs no longer show the sample "Preview" workouts as if they were real history: the app now starts from an honest empty workouts state until HealthKit data loads (preview content remains for the widget gallery and design previews).
- Restored the Simplified Chinese Sleep Score explanation (updated for the v3 vitals-band wording) and the Settings "v3" badge localization, fixing the catalog-coverage test.
- **Watch reliability.** A phone republish carrying identical data no longer discards an in-flight on-watch compute (the seed's transport timestamp is no longer part of its identity); future-dated freshness stamps (e.g. after a clock rollback) can no longer park watch recomputation, while normal phone/watch clock skew stays tolerated; and the metric detail pager now recovers to a valid page when the currently open metric is removed by a phone update mid-visit.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 21.

## 0.9.10 (build 19)

- **Sleep Score v3.** Five points move from Deep (15 → 10) to Vitals (10 → 15), and the Vitals category is now graded against the same robust typical bands the Vitals chart uses — full credit inside your personal band, falling proportionally to zero one band half-width past its edge. Heart rate and respiratory rate deduct on both high and low outliers; blood oxygen deducts on the low side only and keeps the absolute clinical 92–96% ramp as a ceiling (a 99%+ night is never penalized, while a clinically low reading still costs points even if typical for that sleeper). With fewer than ~14 nights of history the previous grading applies unchanged. The Settings ▸ Metrics Sleep Score badge now reads v3.
- **Vitals chart region proportions.** The trend hero's typical band now takes about 45% of the plot height (roughly 1.5× the previous share): the High/Low regions draw on a compressed display scale (half scale past ±1) while the underlying ±3 deviation cap keeps outlier lengths granular and proportional. Vitals breakdown icons and their translucent tiles now switch from white in dark appearance to black in light appearance so every row stays visible on grouped backgrounds.
- Fixed the Readiness Week chart's current-readiness dot lingering ~half a second (or seeming not to hide) after the scrub callout appeared: the status band's easing animation was applied chart-wide, so it also animated the dot's removal. The easing is now scoped to the band itself, and the dot, rule line, and selection point snap instantly while scrubbing.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 19.

## 0.9.10 (build 18)

- **Vitals chart shape and outlier readouts.** The trend hero's smallest mark now always renders as a circle: a bucket's bar is padded to at least its own width in scale units (computed from the chart's real geometry), so spread-less buckets can no longer draw as squat wider-than-tall blobs. In the Day View card, an outlier vital's reading is tinted purple (high) or pink (low) and cross-fades with the dots when switching days. Outlier magnitudes are more granular too: per-night deviations now cap at ±3 typical spreads instead of ±2 (the chart scale widened to match), so heavy-outlier stretches no longer saturate into same-length bars. New metric icons: Basics uses person, Vitals uses heart.badge.bolt (home cards, detail pages, and Settings > Metrics lists).
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 18.

## 0.9.10 (build 17)

- **Vitals detail refinements.** The merged night card is titled "Day View" like the other metric detail pages (the date picker carries the date), its scatter dots glide to their new positions and cross-fade color when switching days, and the breakdown icon tiles are translucent white behind the white glyphs. On the trend hero, a bucket with no real spread draws as a bar-width dot instead of a stubby capsule, and the purple/pink outlier colors are more saturated with a tighter blend and a minimum tip length past the band, so even a small excursion past the typical range clearly turns color.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 17.

## 0.9.10 (build 16)

- **Vitals UI polish.** The outlier trend hero now draws one continuous bar per bucket with a gradient anchored to the deviation scale — blue through the typical band, blending to dark purple toward High and light pink toward Low — and the purple/pink language replaces red on the Last Night dots, home preview rings, and scrub-callout dots. The Last Night scatter and per-vital breakdown merge into one card with white row icons, no region chips, and smaller dots, plus a date picker (free tier: last 3 days) to review any recent night's vitals. Home-card preview rings are smaller and the "Typical"/"N Outliers" headline sizes align with the numeric cards (28pt card / 40pt hero). About Vitals copy rewritten; Simplified Chinese now uses 生命体征 across the Vitals page.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 16.

## 0.9.10 (build 15)

- **New Vitals metric (Beta).** A new home summary card (after Sleep, toggleable in Settings → Summary Cards) reviews five overnight measurements — sleeping heart rate, respiratory rate, skin temperature, blood oxygen, and sleep duration — against personal typical ranges learned from your own recent nights (median ± 2×robust spread over an 8-week window; ~2 weeks of sleep data to calibrate). The card headline reads "Typical" or "N Outliers" with an Apple-Health-style preview: a blue typical band between gray high/low bars, one ring per vital. The detail page adds an outlier-deviation bar chart across Week/Month/6 Months/Year (Pro beyond Week), a Last Night typical-range scatter, a per-vital breakdown, and an About Vitals card. Vitals has no trend card by design and derives entirely from existing sleep data (no new Health permissions).
- Fixed the sleep-vital range marker math so narrow personal typical bands (like skin temperature's) keep their markers inside the typical third of the plot.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 15.

## 0.9.10 (build 14)

- **Activity Rings calendar month headers now count each ring's closed days.** Next to the existing star total (days all three rings closed), each month shows three more counts — days the Move, Exercise, and Stand ring each closed — with a mini tri-ring icon highlighting the counted ring in white.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 14.

## 0.9.10 (build 13)

- **Share flow opens full screen with the whole card always visible.** The workout share flow now opens as a full-screen page instead of a sheet: a ✕ close button sits top-left, and the 9:16 card preview always fits the screen — on small phones the card previously could be cut off at the bottom.
- The bottom Share/Save capsule buttons are replaced by native Liquid Glass circle buttons top-right (share = `square.and.arrow.up`, save = `square.and.arrow.down`; translucent material circles pre-iOS 26).
- The plain "Route Only" route on the workout detail page now draws at 90% of its fitted size, up from 60%, so it reads larger and bolder against the black backdrop.
- The workout detail page's top-right share button is now a Liquid Glass **Share** text capsule (previously a share icon that rendered slightly elliptical on iOS 26), and the share page title is now **Share** with a **Beta v2** badge.
- Fixed the Workouts empty-state message rendering the year with digit grouping ("August 2,026"), and the month picker's VoiceOver label doing the same.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 13.

## 0.9.10 (build 12)

- **Photo share cards: move and resize the info block.** With a photo as the share background, drag the route trace + metrics block anywhere on the card and pinch to resize it; double-tap the preview to reset, and picking a new photo or switching backgrounds also resets. The exported image matches the preview placement exactly, placement is never remembered across opens, and a hint caption under the preview explains the gestures. Gradient presets and the map keep their fixed layouts.
- The centered share card's metric text now carries the same soft shadow as the route trace, so it stays legible when the block sits over a bright photo area the scrims don't reach.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 12.

## 0.9.10 (build 11)

- **Redesigned the share card for all non-map backgrounds.** With a gradient preset (Midnight, Workout Color) or a photo as the background, the card is now headerless — no type icon, title, locality, or date — with the blue route trace running across the top and a centered stack of large metrics below it: a small label over a big value, Distance then Pace (Speed for speed-based types) then Time, falling back to elevation or avg heart rate when distance/pace is missing (up to 3 metrics), and the Body app icon and wordmark centered at the bottom. Only the map background keeps the existing header + bottom-row layout, and for a stored map pick the sheet stays in that classic layout while the snapshot loads so there's no flash into the centered layout.
- The share sheet now opens on the Midnight background by default instead of the route map; the map loads when its tile is picked, and an explicit map pick is still remembered across opens.
- Added a small blue "v2" beta capsule badge beside the "Share Workout" sheet title, matching the style of the settings sheets' v1/v2 badges.
- The share card's own blue route trace (gradient and photo backgrounds) no longer draws green/red start/end dots; only the map background's route keeps its markers.
- The Midnight share background is now pure black instead of a dark-gray-to-black fade.
- Saving the share card now closes the share sheet automatically after the brief "Saved" confirmation; a failed save keeps the sheet open.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 11.

## 0.9.10 (build 10)

- **Sharper readiness fill edge.** The readiness fill's front edge is now a sharp cut instead of the previous short feather into the page background, so the Home hero's fill level reads precisely.
- The workout calendar's empty-day grid cells now use the same fill in dark mode as in light mode (primary at 10% opacity, previously 14% in dark mode), matching the Coin app's calendar widget.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 10.

## 0.9.10 (build 9)

- **The Workouts page and workout widgets now follow the calendar into a new month.** When a month rolls over while the app stays alive (across midnight, or on returning to the foreground), the Workouts page automatically advances to the new — possibly still-empty — month if you were viewing the old current month; a deliberately browsed older month stays put. The live workout calendar and workout types widgets are now month-strict: they always render the actual current month, flipping at the boundary via a timeline entry dated at the month start, instead of holding last month's snapshot or falling back to the previous month's data when the new month has no workouts yet (the previous-month fallback now applies only to widget-gallery previews).
- The month carousel refreshes its month list on appearance, so a just-rolled-over month can be found and centered immediately.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 9.

## 0.9.10 (build 8)

- **The loading badge now plays random white pixel-grid animations.** The sync badge's marching-squares loader is replaced with a 3×3 pixel display: nine white cells over a faint always-on base light up and fade with a soft glow in one of 17 delay patterns (waves, spiral, snake, rain, pinwheel, orbit, checkerboard, and more — design adapted from SwiftPixelGrid), picked at random each time the badge or the Workouts "Loading data…" pill appears. The completion checkmark is drawn in the same language — white lit pixels with the same glow. Reduce Motion still falls back to the standard spinner.
- The sync badge's loading text now reads "Loading data..." (matching the Workouts month-load pill) instead of "Syncing health data…".
- The by-Activity cards on metric detail pages (Energy/Impact/Heart Rate by Activity, Average HRV) now draw their row icons in the same continuous rounded-rectangle tile as the Workouts page's workout cards, instead of a circle.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 8.

## 0.9.10 (build 7)

- **Workouts filter and search now also narrow the calendar chart, type breakdown, and totals.** Previously the type-filter sheet and search field only filtered the workout cards list; now the calendar chart, the workout-type breakdown bars, and the monthly totals header (total duration and workout count) all reflect the same filtered set, and the calendar-day and type-breakdown popups list only the matching workouts. Clearing the filter and search restores the full month everywhere.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 7.

## 0.9.10 (build 6)

- **Chart scrub callouts now float on the topmost layer.** On the metric detail pages, scrubbing the hero chart draws the selection callout above everything on screen — including the navigation bar's back chevron and title, which previously drew over it. The navigation title no longer hides while scrubbing (the build-3 workaround), since the callout simply covers it. Charts in the cards below the hero keep their in-place callouts.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 6.

## 0.9.10 (build 5)

- **Added a current-readiness dot to the Readiness week chart.** On the Readiness detail's Week range, an 80%-opacity dot in the line's color now marks today's live (post-workout) score below the plotted morning point — drawn only for today, and only when a workout visibly lowered readiness that day. While nothing is scrubbed, the highlighted status band follows that dot instead of the morning point, so the band reads the current status; scrubbing still retargets the band to the touched day and hides the dot until release.
- The watch app's Readiness detail chart draws the same faded current-readiness dot below today's point (the watch payload now carries the drained value; its status band already tracked the current status).
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 5.

## 0.9.10 (build 3)

- **Added a Readiness day view.** The Readiness detail now shows a date-tile day picker, a Day View line chart tracing the selected day's score from its frozen morning value down through each workout (workouts drawn as tinted bands with their icons), and an Impact by Activity card listing each workout's readiness drop — placed between the Days by Status chart and the About your score card. The line is derived from the morning score plus that day's workouts, and flat stretches draw only their start and end dots (instead of one per hour); the readiness row is toggleable in Settings > Metrics > Day View, and older picker days follow the existing 3-free-days Body Pro gating.
- A Day View selection saved before this build (when Readiness wasn't offered) upgrades once to include Readiness; custom subsets, an all-off selection, and any choice made on this build — including turning off just Readiness — are preserved as saved.
- Updated the app, widget, watch, and test bundle version to 0.9.10 build 3.

## 0.9.10 (build 2)

- Updated the app, widget, watch, and test bundle version to 0.9.10 build 2.
- Tinted every app-styled sheet's iOS 26 Liquid Glass background with a half-opacity black wash so sheets no longer read as fully transparent.
- Fixed the metric detail chart callout colliding with the navigation title: the title now hides while a chart point is selected.
- Sleep consistency (the chart and the sleep score's Consistency category) now ignores daytime naps by reading bed/wake times from only the day's main sleep session.

## 0.9.10 (build 1)

- Updated the app, widget, watch, and test bundle version to 0.9.10 build 1.

## 0.9.9 (build 13)

- **Restyled the workout share sheet's action buttons.** Share now sits on the left and Save on the right, and both carry the same flat translucent fill of the workout type's color under a thin white rim (no gradient or blur), instead of a tinted Share beside a neutral Save.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 13.

## 0.9.9 (build 12)

- **The workout share sheet now opens on the route map.** The dark route-map background is the default instead of the Midnight gradient, it loads as soon as the sheet opens, and whichever background you pick last — map or gradient — is restored the next time you share (photo picks stay session-only).
- The Ocean, Sunset, and Forest gradient backgrounds were retired; the strip is now Midnight, Workout Color, the route map, and your photo.
- The share card's route trace is now blue (`#0128F4`) instead of white, and its bottom-left row shows at most two metrics for every activity (previously up to three).
- **Added a Save button beside Share.** It writes the rendered 1080×1920 card straight to your photo library using add-only Photos access, confirming with a "Saved" state on the button.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 12.

## 0.9.9 (build 11)

- **Fixed the Sleep Stages chart with two or more sleep sources.** When multiple sources write sleep data for the same night (e.g. Apple Watch + Oura), the hypnogram no longer draws overlapping duplicate timelines with an inflated total; overlapping samples across sources are now deduplicated (the more detailed tracker wins) and the card's header duration uses the overlap-merged total, matching the night's actual length.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 11.

## 0.9.9 (build 10)

- **Added a workout share function.** A new circle share button top-right of a route workout's detail page opens a preview sheet for a Strava-style share card. The card's header mirrors the detail page — type icon, title, locality, and date/time on the left with big Distance and Duration numbers on the right — the GPS route trace fills the middle, and a bottom-left row carries the per-type extras (avg pace for a run, avg speed for a ride, elevation gain for snow sports, plus avg heart rate when recorded). Choose from five built-in gradient backgrounds or a dark route-map background for free, or pick a photo from your library as the background with **Body Pro**; tapping the photo tile without Pro opens the paywall. Workouts whose route is too degenerate to draw render a metrics-only card (workouts without a route don't show the button at all). Share exports a 1080×1920 image and hands it to the standard iOS share sheet.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 10.

## 0.9.9 (build 9)

- The Heart Rate detail page's activity-breakdown card is now titled "Heart Rate by Activity" (previously "Average Heart Rate").
- The "by activity" card titles on the Heart Rate, HRV, and Active Energy detail pages now localize (Simplified Chinese) instead of always rendering in English.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 9.

## 0.9.9 (build 8)

- The Active Energy detail page now shows an "Energy by Activity" card below the day chart: one row per workout with its icon, time range, recorded energy in the selected unit (kcal/kJ), and recording source.
- The Training Load workout look-back grew from 180 days to a full year plus the chronic-EWA warm-up, so the detail chart's Year range now shows ratio points across the whole year instead of only the last ~6 months.
- Workout list rows now lead with energy (flame icon) and show distance as the trailing detail; distance stays primary only for workouts without recorded energy.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 8.

## 0.9.9 (build 7)

- Workout splits now highlight the slowest split in addition to the fastest.
- The floating sync status badge morphs into its completion state instead of swapping abruptly, and the version badge tokens in Settings are localized.
- Renamed the Effort Suggestions badge in Settings from "Beta v2" to "v1".
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 7.

## 0.9.9 (build 5)

- Added a floating capsule status badge at the top of the screen that shows an animated marching-squares loader (small squares snaking around a 3×3 grid, one traveling gap; Reduce Motion falls back to the standard spinner) with "Syncing health data…" while a HealthKit refresh runs and briefly confirms "Health data updated" before auto-dismissing (only when the refresh actually succeeded). Uses Liquid Glass on iOS 26 and the translucent pill-tab-bar material recipe on iOS 18. Pull-to-refresh on Summary, Workouts, and metric detail pages now shows this badge instead of the full-screen loading overlay, and uses a custom pull gesture with no system refresh control so no system spinner ever appears; the Workouts month-switch load now shows a matching floating "Loading data…" capsule too — the old full-screen dimming overlay is removed entirely.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 5.

## 0.9.9 (build 3)

- **Sleep score consistency and the Sleep Consistency detail chart are now timezone-aware.** Each night is scored in the time zone it was slept in, using HealthKit's per-sample time-zone metadata, instead of the device's current zone. Short trips (three nights or fewer in a differing zone) keep a meaningful consistency score via local-clock comparison; longer stays drop the consistency category starting the fourth night until the rolling 14-day baseline has re-filled with nights from the current zone. Readiness is unaffected — it does not read the consistency category.
- **Sources without time-zone metadata (e.g. Apple Watch) get the same travel behavior.** The app keeps a small ledger of device time-zone changes and resolves metadata-less nights through it, and a night whose bed and wake times are both uniformly shifted 1.5h+ from the baseline while any night's zone is unknown is treated as an unrecorded zone shift — the consistency category is omitted instead of penalized.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 3.

## 0.9.9 (build 1)

- Hardened HealthKit refreshes so transient failures preserve source-scoped cached data, sleep sessions remain intact across midnight, workout detail reads retry instead of caching failed results, and readiness/training-load inputs distinguish missing data from failed queries.
- Made cache clearing and companion delivery authoritative with generation guards, versioned day-sample provenance, monotonic Watch revisions, and a persisted Watch reset tombstone.
- Improved settings, Body Pro recovery states, widget preference updates, accessibility motion handling, required-reason privacy manifests, and regression coverage across the iOS and Watch targets.
- Updated the app, widget, watch, and test bundle version to 0.9.9 build 1.

## 0.9.8 (build 8)

- **Sleep detail now surfaces restorative sleep (Deep + REM combined).** The stage breakdown shows a Restorative total in both views: the duration view adds a Restorative duration line under the per-stage durations (separated by a divider), and the bar chart adds a dedicated Restorative bar with its own optimal-range band (≈33–48% of time in bed), percentage, and duration. A new About Restorative Sleep card above the About Sleep Score card explains the metric. In Simplified Chinese the stage timeline y-axis reads 醒/眼/核/深 and the breakdown bars use shortened stage names 清醒/眼动/核心/深度/恢复. Long or localized stage labels no longer wrap; the bar shrinks to fit the text instead.
- Updated the app, widget, watch, and test bundle version to 0.9.8 build 8.

## 0.9.8 (build 7)

- Trend detail pages give month, six-month, and year charts more right-side breathing room and a left-biased start. Month keeps a half-bucket (12h) leading nudge with a 28h trailing edge; six-month and year charts pin the first mark to the left wall (no leading padding) with a 1.5-bucket trailing edge (9 days / 18 days). This applies to single-source line, range, and bar charts and to the line/range source-comparison charts; the two-source paired-bar comparison chart stays symmetric so its offset outer bars aren't clipped.
- Updated the app, widget, watch, and test bundle version to 0.9.8 build 7.

## 0.9.8 (build 6)

- Settings polish: section titles are slightly smaller, section and Body Pro entry cards have a slightly smaller corner radius, and each settings row's leading icon sits a touch closer to the left edge.
- Updated the app, widget, watch, and test bundle version to 0.9.8 build 6.

## 0.9.8 (build 5)

- **Readiness now says when it's still waiting on last night's sleep.** Past midnight but before you wake, today's sleep session isn't recorded yet, so Readiness is computed from your other signals as usual — the score is unchanged. The hero line under the number now reads "Today's sleep data isn't in yet. Get some rest and check back later for a more accurate result." (with a Simplified Chinese translation) instead of a signal-specific explanation, until today's sleep lands.
- Updated the app, widget, watch, and test bundle version to 0.9.8 build 5.

## 0.9.8 (build 3)

- **Very low Readiness no longer crashes straight to 0% after a workout.** Once the day's activity drain brings today's live Readiness down to its raw zero, the score now shows **5%** and eases down only 1% for every further 5% of deficit — so it reaches 0% only when the underlying score is 25 points or more into the red. The softening never lifts the number above where the day started, and the frozen "Started today with NN%" value and the history chart are unchanged.
- Updated the app, widget, watch, and test bundle version to 0.9.8 build 3.

## 0.9.8 (build 2)

- **The Basics detail page's Weight and Body Fat trend cards now morph into their detail screens.** Tapping either card zooms it into that metric's focused detail using the same card→detail transition the Home cards use, instead of a flat push. (Reduce Motion cross-fades, as elsewhere.)
- **Auto-Apply Effort (opt-in, off by default).** A new toggle in Settings ▸ Metrics ▸ Effort Suggestions automatically saves Body's predicted effort to Apple Health for unrated workouts that ended 1–48 hours ago and have heart-rate data — the 1-hour wait lets a rating synced from your Apple Watch land first, and nothing older than 2 days is touched. It detects a denied write and switches itself back off. The Effort Suggestions sheet is now split into two sections (Effort Suggestions and Auto-Apply Effort), each with its own explanation.
- The Simplified Chinese term for "workout" changed from 体能训练 to 运动 across the app.
- Updated the app, widget, watch, and test bundle version to 0.9.8 build 2.

## 0.9.8 (build 1)

- Updated the app, widget, watch, and test bundle version to 0.9.8 build 1.

## 0.9.7 (build 7)

- Updated the app, widget, watch, and test bundle version to 0.9.7 build 7.

## 0.9.7 (build 5)

- Updated the app, widget, watch, and test bundle version to 0.9.7 build 5.

## 0.9.7 (build 3)

- **Body Pro now runs on RevenueCat.** Purchases, entitlements, restore, and pending (Ask to Buy) handling moved from the hand-rolled StoreKit 2 store to the RevenueCat SDK, with the paywall UI and the shared App Group entitlement flag (read by widgets and the watch) unchanged. Added a **Manage Purchases** entry in Settings ▸ About that opens the RevenueCat **Customer Center** (restore, refunds, support), localized in Simplified Chinese.
- Performance: the watch snapshot (weekly aggregations, sleep score) is now built and encoded off the main thread on every refresh, mirroring the existing widget-snapshot path, with a paired permission value and a latest-wins ordering guard so a delayed build can never ship stale or out-of-order data to the watch.
- Performance: the watch app now reloads its complication timelines only when the pushed snapshot actually changed on disk, instead of on every refresh and every foreground live heart-rate/HRV update.
- Performance: the widget and complication snapshot stores now cache decoded snapshots by file identity (modification date + size), so repeated timeline passes across widget kinds and complications no longer each re-read and re-decode the same App Group file.
- Performance: the Home screen's summary metric cards are now memoized against their full set of inputs (health data, unit preferences, sleep settings, day, locale, and time zone), so they're rebuilt only when something they depend on actually changes instead of on every render.
- Performance: the Workouts tab flattens the selected month once per render instead of twice, and search text is matched against a cached per-workout corpus instead of re-lowercasing and re-formatting every workout's type, source, and date on each keystroke.
- Performance: Apple Health source discovery for multi-metric categories (e.g. weight, body fat, and BMI together) now runs its per-metric-type queries concurrently instead of one at a time.
- Updated the app, widget, watch, and test bundle version to 0.9.7 build 3.

## 0.9.7 (build 2)

- **Workout details now show pace splits.** A new **Splits** section on the workout detail page breaks running, walking, hiking, wheelchair, and cycling workouts into per-kilometer or per-mile segments — each row showing the segment, a relative pace bar (shortest for the fastest split), its pace (speed for cycling), and average heart rate, with the fastest split highlighted in the Heart Rate card's blue; a partial final split is labeled with its fraction of a full unit. It appears only when a workout has enough recorded distance data for at least one complete split, and the km/mi boundaries switch live with the Settings distance unit.
- Updated the app, widget, watch, and test bundle version to 0.9.7 build 2.

## 0.9.7 (build 1)

- **Fixed: the morning "Started today with" readiness value could get stuck without sleep data.** The frozen morning score (captured ~10 minutes after wake) now upgrades **once, same-day**, if today's actual sleep hadn't synced from Apple Health yet at freeze time — previously the first score of the day, computed without sleep, stayed locked in for the rest of the day even after sleep data arrived. Once the upgrade happens (or if sleep was already available at freeze time), the value stays pinned as before.
- Updated the app, widget, watch, and test bundle version to 0.9.7 build 1.

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
