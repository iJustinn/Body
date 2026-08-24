//
//  WatchComputeCoordinator.swift
//  BodyWatch
//
//  Runs one on-watch metric compute end to end: phone seed + short HealthKit
//  delta (`WatchDeltaFetcher`) → spliced trends → summary overlay → Training
//  Load replay → permission filter → readiness recompute → the same
//  `WatchMetricsSnapshotBuilder` the phone uses. Everything between the fetch
//  and the builder is shared `BodyMetricsKit`/`BodyWatchSnapshotKit` code, so a
//  metric computed here and the same metric computed on the phone come out of
//  the identical implementation.
//
//  An actor with in-flight coalescing: `onAppear`, scene-active and the manual
//  refresh button can all fire within a second of each other, and a compute is
//  ~20 HealthKit round trips. A caller that arrives while one is running gets
//  that run's result; if the compute generation moved in the meantime the model
//  discards it (see `WatchComputeResult.generation`) and the next trigger
//  recomputes.
//

import Foundation
import os

actor WatchComputeCoordinator {
    private let fetcher = WatchDeltaFetcher()
    private var inFlight: (generation: UInt64, task: Task<WatchComputeResult?, Never>)?
    private static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "WatchCompute"
    )

    /// `nil` when the watch must keep whatever the phone pushed: no stored seed,
    /// a seed whose data window is older than the watch's own HealthKit
    /// retention can bridge, or a compute that produced nothing usable.
    func recompute(
        permission: BodyHealthPermissionSelection,
        generation: UInt64,
        now: Date = Date()
    ) async -> WatchComputeResult? {
        // Coalesce ONLY onto a run of the same generation. A seed replacement /
        // permission change bumps the generation while a compute is running;
        // coalescing this caller onto that stale run would hand back a result
        // the model must discard — and with no rerun ever started for the NEW
        // generation, the replacement seed would sit uncomputed behind the
        // 30-minute rate limit. A mismatched in-flight run is awaited (to
        // serialize HealthKit fan-outs) and then a fresh run starts for the
        // caller's generation. Loop, not `if`: a third caller can install a
        // new run while this one awaits.
        while let current = self.inFlight {
            if current.generation == generation {
                return await current.task.value
            }
            _ = await current.task.value
            // The run's originating caller clears `inFlight` in its own
            // continuation, which may not have resumed yet — clear it here too
            // (guarded, idempotent) so this loop can't spin on a finished run.
            if self.inFlight?.task == current.task {
                self.inFlight = nil
            }
        }

        let task = Task { [fetcher] in
            await Self.compute(
                fetcher: fetcher,
                permission: permission,
                generation: generation,
                now: now
            )
        }
        inFlight = (generation, task)
        let result = await task.value
        // Guarded: another caller may have cleared this run and installed a
        // NEWER one while this continuation was waiting to resume — blindly
        // nil-ing would deregister that run and let a duplicate start.
        if self.inFlight?.task == task {
            self.inFlight = nil
        }
        return result
    }

    // MARK: - The compute

    private static func compute(
        fetcher: WatchDeltaFetcher,
        permission: BodyHealthPermissionSelection,
        generation: UInt64,
        now: Date
    ) async -> WatchComputeResult? {
        guard let seed = WatchComputeSeedStore.load() else { return nil }
        let calendar = Calendar.bodyGregorian
        let windowStart = WatchDeltaSplicer.deltaStart(dataThrough: seed.dataThrough, calendar: calendar)
        // The watch's own HealthKit store retains roughly a week
        // (`maxComputeAge`), so the ENTIRE delta window — which starts two
        // calendar days BEFORE `dataThrough` for the re-fetch overlap — must
        // fit inside that retention, not just the seed's own age. Gating on
        // `dataThrough` alone would let a 5–7-day-old seed run a 7–9-day query
        // whose oldest days the watch no longer holds; those "successfully"
        // empty results would then be spliced as authoritative, deleting seeded
        // points and zero-filling Training Load days the phone actually knows.
        guard now.timeIntervalSince(windowStart) <= WatchComputeSeed.maxComputeAge else {
            logger.info("Compute skipped: the delta window would reach past the watch's HealthKit retention.")
            return nil
        }
        // …and reject the other direction too. `dataThrough` drives `deltaStart`
        // and the Training Load day slots, so a phone clock far AHEAD of this
        // watch's would put the delta window entirely in the future and the
        // compute would splice nothing over a history it believes is current.
        // The tolerance is the snapshot stale window (30 min), which comfortably
        // absorbs ordinary phone/watch clock skew while catching a genuinely
        // broken one.
        guard seed.dataThrough <= now.addingTimeInterval(WatchMetricsSnapshot.staleInterval) else {
            logger.info("Compute skipped: seed dataThrough is implausibly far in the future.")
            return nil
        }

        let delta = await fetcher.fetchDelta(
            seed: seed,
            permission: permission,
            windowStart: windowStart,
            now: now,
            calendar: calendar
        )

        var trends = seed.trends
        trends.heartRate = WatchDeltaSplicer.splice(
            seedSeries: trends.heartRate, delta: delta.heartRateSeries, from: windowStart, calendar: calendar
        )
        trends.restingHeartRate = WatchDeltaSplicer.splice(
            seedSeries: trends.restingHeartRate, delta: delta.restingHeartRateSeries, from: windowStart, calendar: calendar
        )
        trends.heartRateVariability = WatchDeltaSplicer.splice(
            seedSeries: trends.heartRateVariability, delta: delta.heartRateVariabilitySeries, from: windowStart, calendar: calendar
        )
        trends.respiratoryRate = WatchDeltaSplicer.splice(
            seedSeries: trends.respiratoryRate, delta: delta.respiratoryRateSeries, from: windowStart, calendar: calendar
        )
        trends.oxygenSaturation = WatchDeltaSplicer.splice(
            seedSeries: trends.oxygenSaturation, delta: delta.oxygenSaturationSeries, from: windowStart, calendar: calendar
        )
        trends.wristTemperature = WatchDeltaSplicer.splice(
            seedSeries: trends.wristTemperature, delta: delta.wristTemperatureSeries, from: windowStart, calendar: calendar
        )
        trends.sleepHistory = WatchDeltaSplicer.spliceSleepHistory(
            seed: trends.sleepHistory, deltaNights: delta.sleepNights, from: windowStart, calendar: calendar
        )
        // The sleep duration series is derived from the history on the phone too
        // (`trends.sleep = fetchedSleepHistory.durationSeries`), so derive the
        // delta from the SPLICED history rather than fetching a second series —
        // then splice it over the seed's own window. Re-deriving it wholesale
        // would widen the series to every seeded night (the seed trims sleep
        // STAGES, not nights), and `trends.sleep` is a readiness source series:
        // its oldest point sets how many days the readiness daily-series
        // recompute walks. That must stay the seed's 70-day window on a watch.
        let sleepDurationDelta: WatchFetchOutcome<HealthTrendSeries>
        if case .success = delta.sleepNights {
            sleepDurationDelta = .success(trends.sleepHistory.durationSeries)
        } else {
            sleepDurationDelta = .failure
        }
        trends.sleep = WatchDeltaSplicer.splice(
            seedSeries: seed.trends.sleep, delta: sleepDurationDelta, from: windowStart, calendar: calendar
        )

        // Summary overlay: a freshly-read value wins, otherwise the phone's
        // seeded value survives. A missing read on the watch means "no local
        // data for it", never an authoritative clear.
        var summary = seed.summary
        // HR / HRV / RHR: `HealthMetricSummary` carries only a value — the seed
        // side has NO watermark to compare the fetched sample's `endDate`
        // against, so fetched-wins stands. It is also the safe direction here:
        // these come from `latestQuantitySample` bounded to the daily trend
        // window, i.e. the newest in-window sample this watch can see, and a
        // watch that genuinely has an older newest-sample than the phone (a
        // source it can't see) already resolves `.skip` through
        // `WatchSourceResolver` and never gets here. Clearing a value that has
        // since aged OUT of the window is not this overlay's job — an absent
        // read is indistinguishable from a failed one here, so it is done at
        // display time by `WatchMetricsSnapshot.sanitized(asOf:)`.
        if let heartRate = delta.heartRateSample {
            summary.heartRate = HealthMetricSummary(value: heartRate.value, measuredAt: heartRate.measuredAt)
        }
        if let restingHeartRate = delta.restingHeartRateSample {
            summary.restingHeartRate = HealthMetricSummary(value: restingHeartRate.value, measuredAt: restingHeartRate.measuredAt)
        }
        if let heartRateVariability = delta.heartRateVariabilitySample {
            summary.heartRateVariability = HealthMetricSummary(value: heartRateVariability.value, measuredAt: heartRateVariability.measuredAt)
        }
        // Sleep DOES carry a real watermark on both sides (the night's day), so
        // it's guarded: the watch's HealthKit retention is far shorter than the
        // phone's, and a night the watch can no longer see would otherwise
        // replace the seed's newer night with an older one — silently rolling
        // back both the Sleep card and the readiness that reads it.
        let freshSleepNight = Self.overlaidSleepNight(
            fetched: delta.latestNight,
            seeded: seed.summary.sleep,
            calendar: calendar
        )
        if let freshSleepNight {
            summary.sleep = freshSleepNight
        }

        // Training Load: replay the phone's dense day-indexed loads with the
        // watch's own workouts overwriting every slot from the delta window
        // onward, then re-run the identical acute/chronic EWA. Overwriting (not
        // adding) is what makes a deleted or re-rated workout land.
        let trainingLoad = trainingLoadSeries(
            seed: seed,
            workouts: delta.workouts,
            windowStart: windowStart,
            now: now,
            calendar: calendar
        )
        if let trainingLoad {
            // The EWA has to run over the whole 408-day load array to warm up,
            // but only the seed's own window is KEPT: `trends.trainingLoad` is
            // a readiness source series, and carrying 408 points would make the
            // readiness daily-series recompute walk a year of days on a watch
            // CPU, every app open.
            let oldestSeededDay = seed.trends.trainingLoad.points.map(\.date).min()
                ?? calendar.startOfDay(for: windowStart)
            trends.trainingLoad = HealthTrendSeries(
                points: trainingLoad.points.filter { $0.date >= oldestSeededDay }
            )
            summary.trainingLoad = HealthMetricSummary(
                value: trainingLoad.point(on: calendar.startOfDay(for: now))?.value
            )
        }

        let idealSleepDuration = TimeInterval(seed.settings.idealSleepDurationMinutes * 60)
        let fetchedWorkouts: [WorkoutSummary]
        if case .success(let workouts) = delta.workouts {
            fetchedWorkouts = workouts
        } else {
            // Workouts permitted but the query FAILED: the recompute below runs
            // with an empty `todaysWorkouts`, i.e. with today's activity drain
            // removed. That readiness is not publishable — `dataAsOf`'s
            // all-inputs-fresh rule leaves it unstamped, so the merge never
            // adopts the inflated score. (When Workouts is OFF a drain-less
            // recompute matches the phone's own permission-filtered one.)
            fetchedWorkouts = []
        }
        let sleepEnd = summary.sleep.stageSnapshot.wakeCycleEnd

        let recomputed = HealthDashboardSnapshot(summary: summary, trends: trends)
            .filteredWithoutReadinessRecompute(by: permission)
            .recalculatingReadiness(
                on: now,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar,
                todaysWorkouts: ReadinessComputeSupport.wakeCycleWorkouts(
                    from: fetchedWorkouts,
                    now: now,
                    sleepEnd: sleepEnd,
                    calendar: calendar
                ),
                wakeTime: nil,
                // DELIBERATE DEVIATIONS from the phone's call, both documented
                // in the plan:
                // * `freezesRecordedReadiness: false` — the frozen morning
                //   record is phone-authoritative and can't be synced back, so
                //   the watch must never mint one. Today's headline can
                //   therefore lag the phone's same-day coverage-based record
                //   upgrade until the next push.
                // * `recordedReadinessContext: nil` — passing a context the
                //   watch can't reproduce byte-for-byte would drop every seeded
                //   record on the first compute; nil means "don't re-key them".
                now: now,
                freezesRecordedReadiness: false,
                recordedReadinessContext: nil
            )

        let dataAsOf = Self.dataAsOf(
            delta: delta,
            freshSleepNight: freshSleepNight,
            recomputedSleep: recomputed.summary.sleep,
            replayedTrainingLoad: trainingLoad != nil,
            permission: permission,
            now: now,
            calendar: calendar
        )

        var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: recomputed.summary,
            trends: recomputed.trends,
            lastRefreshDate: seed.lastVitalsRefreshDate,
            permissionSelection: permission,
            temperatureUnitPreference: Self.temperatureUnitPreference(for: seed.settings),
            idealSleepDuration: idealSleepDuration,
            showSleepScore: seed.settings.showSleepScore,
            now: now,
            // Union the phone's broader history into each carried range so the
            // watch's short delta window can't shrink the ring/chart bounds.
            seriesRangeOverride: { seed.seriesRanges[$0] },
            perKindDataAsOf: { dataAsOf[$0] }
        )
        snapshot.source = "watch"

        guard snapshot.metrics.contains(where: \.hasValue) else { return nil }
        return WatchComputeResult(
            snapshot: snapshot,
            dataAsOf: dataAsOf,
            chartDataAsOf: Self.chartDataAsOf(delta: delta, now: now),
            // The instant this compute's queries ran to — the information
            // cutoff the merge compares against PHONE-derived stamps (which
            // are themselves refresh/query times, the same domain).
            coverage: now,
            generation: generation
        )
    }

    // MARK: - Pieces

    /// The seeded daily loads with the watch's delta days overwritten, replayed
    /// through the shared EWA. `nil` — keep the seed's own Training Load — when
    /// the seed carries no loads, when the workout query FAILED (extending the
    /// array to today would then fabricate rest days the watch never
    /// confirmed), or when the loads' own coverage no longer reaches the delta
    /// window: the loads can lag the seed's `dataThrough` (phone-side cost
    /// gate skips the rebuild while the Training Load / Readiness cards are
    /// hidden; a phone relaunch loses the cache entirely), and the delta only
    /// re-fetches from `windowStart` — every day between the loads' coverage
    /// and `windowStart` would be silently zero-filled as a fabricated rest
    /// day.
    private static func trainingLoadSeries(
        seed: WatchComputeSeed,
        workouts: WatchFetchOutcome<[WorkoutSummary]>,
        windowStart: Date,
        now: Date,
        calendar: Calendar
    ) -> HealthTrendSeries? {
        guard let startDay = seed.trainingLoadStartDay,
              let loads = seed.trainingLoadDailyLoads,
              !loads.isEmpty,
              let loadsThrough = seed.trainingLoadDataThrough,
              calendar.startOfDay(for: loadsThrough) >= calendar.startOfDay(for: windowStart),
              case .success(let deltaWorkouts) = workouts else {
            return nil
        }

        var dailyLoads: [(date: Date, load: Double)] = []
        dailyLoads.reserveCapacity(loads.count + 3)
        var day = calendar.startOfDay(for: startDay)
        for load in loads {
            dailyLoads.append((date: day, load: load))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = nextDay
        }
        // Extend to today: the seed's last slot is the phone's last refresh day,
        // which can be up to `maxComputeAge` behind.
        let today = calendar.startOfDay(for: now)
        while day <= today {
            dailyLoads.append((date: day, load: 0))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = nextDay
        }

        let windowStartDay = calendar.startOfDay(for: windowStart)
        let loadsByDay = deltaWorkouts.reduce(into: [Date: Double]()) { partialResult, workout in
            guard let load = TrainingLoadCalculator.load(for: workout) else { return }
            partialResult[calendar.startOfDay(for: workout.startDate), default: 0] += load
        }
        for index in dailyLoads.indices where dailyLoads[index].date >= windowStartDay {
            dailyLoads[index].load = loadsByDay[dailyLoads[index].date] ?? 0
        }

        return TrainingLoadCalculator.series(fromDailyLoads: dailyLoads)
    }

    /// The freshly-fetched night to overlay onto the seed's summary, or `nil` to
    /// keep the seed's. Applied only when the fetched night is not OLDER than
    /// the seeded one: the watch retains far less sleep history than the phone,
    /// and its "latest" night can genuinely predate the phone's. A fetched night
    /// with no day at all can't be proven newer, so it's refused too (it would
    /// fail `SleepSummary.asOf` and blank the card anyway).
    private static func overlaidSleepNight(
        fetched: SleepSummary?,
        seeded: SleepSummary,
        calendar: Calendar
    ) -> SleepSummary? {
        guard let fetched, let fetchedDay = fetched.stageSnapshot.date else { return nil }
        guard let seededDay = seeded.stageSnapshot.date else { return fetched }
        return calendar.startOfDay(for: fetchedDay) >= calendar.startOfDay(for: seededDay)
            ? fetched
            : nil
    }

    /// The anti-laundering watermark map (see `WatchComputeResult.dataAsOf`).
    /// Only kinds this run genuinely re-read from HealthKit appear; a
    /// seed-carried kind is omitted so the merge never adopts (and never
    /// re-stamps) the phone's own number as freshly measured.
    private static func dataAsOf(
        delta: WatchComputeDelta,
        freshSleepNight: SleepSummary?,
        recomputedSleep: SleepSummary,
        replayedTrainingLoad: Bool,
        permission: BodyHealthPermissionSelection,
        now: Date,
        calendar: Calendar
    ) -> [String: Date] {
        var map: [String: Date] = [:]
        if let heartRate = delta.heartRateSample {
            map[WatchMetricKindKey.heartRate] = heartRate.measuredAt
        }
        if let restingHeartRate = delta.restingHeartRateSample {
            map[WatchMetricKindKey.restingHeartRate] = restingHeartRate.measuredAt
        }
        if let heartRateVariability = delta.heartRateVariabilitySample {
            map[WatchMetricKindKey.heartRateVariability] = heartRateVariability.measuredAt
        }
        // Sleep is stamped ONLY from the night this run actually fetched — never
        // from `recomputedSleep`, which falls back to the seed's night whenever
        // the sleep fetch failed or was refused above. Reading the watermark off
        // the recomputed summary would launder the phone's own night into
        // "measured on the watch just now" and let it outrank later pushes.
        // It still has to be the night the builder will PUBLISH
        // (`SleepSummary.asOf` — a night that's no longer today blanks the
        // card), so the recomputed summary is consulted for that alone.
        if let freshSleepNight,
           let freshDay = freshSleepNight.stageSnapshot.date,
           let nightEnd = freshSleepNight.stageSnapshot.dateInterval?.end,
           let published = recomputedSleep.asOf(now),
           let publishedDay = published.stageSnapshot.date,
           calendar.isDate(publishedDay, inSameDayAs: freshDay) {
            map[WatchMetricKindKey.sleep] = nightEnd
        }
        // Training Load is stamped only when the replay actually ran:
        // `trainingLoadSeries` returns nil (seed value carried through) when
        // the seed has no daily-load array or the workout query FAILED, and
        // stamping then would present the phone's own EWA as watch-measured.
        // When it did run, the watermark is the workout query's COVERAGE end
        // (`now`, the window bound the query ran to — captured at fetch time,
        // not read at stamp time), not the newest workout's end date: a
        // successful EMPTY query is fresh information too. The EWA ratio
        // decays through confirmed rest days, and stamping only when a workout
        // exists would leave the recomputed rest-day value permanently
        // rejected by the merge, freezing yesterday's phone value on the card.
        // This is coverage semantics, the same thing the phone's own refresh-
        // date stamp means — not the laundering the "never `Date()`" rule
        // forbids, which is about values that were NOT re-derived this run.
        if replayedTrainingLoad {
            map[WatchMetricKindKey.trainingLoad] = now
        }
        // Readiness consumes the trend SERIES the splice refreshed (whole-day
        // HR, HRV, resting HR, respiratory, O₂, wrist temperature), the sleep
        // history, and — when Workouts is permitted — the workout list plus the
        // Training Load replay. Its watermark is therefore coverage-based, like
        // Training Load's: stamped with the query window's end only when EVERY
        // permission-eligible input query succeeded this run. Anything less
        // means the recomputed score mixed fresh and seed-carried inputs — the
        // phone's own value is the fully-consistent one and must stay
        // authoritative (a failed workout query, for instance, would have
        // removed today's activity drain and inflated the score). The
        // latest-HR HEADLINE sample deliberately plays no part: it never feeds
        // the score, and stamping readiness off it let a seed-derived score
        // masquerade as fresh whenever the worn watch produced a recent HR
        // sample.
        var readinessInputsFresh = true
        if permission.includes(.heart) {
            readinessInputsFresh = readinessInputsFresh
                && delta.heartRateSeries.isSuccess
                && delta.restingHeartRateSeries.isSuccess
                && delta.heartRateVariabilitySeries.isSuccess
        }
        if permission.includes(.respiratory) {
            readinessInputsFresh = readinessInputsFresh && delta.respiratoryRateSeries.isSuccess
        }
        if permission.includes(.bloodOxygen) {
            readinessInputsFresh = readinessInputsFresh && delta.oxygenSaturationSeries.isSuccess
        }
        if permission.includes(.wristTemperature) {
            readinessInputsFresh = readinessInputsFresh && delta.wristTemperatureSeries.isSuccess
        }
        if permission.includes(.sleep) {
            readinessInputsFresh = readinessInputsFresh && delta.sleepNights.isSuccess
        }
        if permission.includes(.workouts) {
            readinessInputsFresh = readinessInputsFresh && delta.workouts.isSuccess && replayedTrainingLoad
        }
        if readinessInputsFresh {
            map[WatchMetricKindKey.readiness] = now
        }
        // Skin temperature is deliberately absent from THIS map: its headline
        // is the seeded daily summary (phone-sourced by design), so there is
        // no measurement watermark to claim. Its freshly-spliced TREND still
        // reaches the card through the separate chart-only channel
        // (`chartDataAsOf` below) — without that, the documented "headline
        // stays phone-sourced, trend recomputes on-watch" deviation would
        // silently become "nothing updates on-watch".
        return map
    }

    /// Chart-only adoption channel (see `WatchComputeResult.chartDataAsOf`):
    /// kinds whose weekly series + carried range were freshly re-derived even
    /// though the headline stayed seed-carried.
    private static func chartDataAsOf(delta: WatchComputeDelta, now: Date) -> [String: Date] {
        var map: [String: Date] = [:]
        if delta.wristTemperatureSeries.isSuccess {
            map[WatchMetricKindKey.wristTemperature] = now
        }
        return map
    }

    private static func temperatureUnitPreference(
        for settings: WatchComputeSettings
    ) -> BodyValueFormat.TemperatureUnitPreference {
        settings.followsSystemUnits
            ? BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.TemperatureUnitPreference.storedValue(from: settings.selectedTemperatureUnitRaw)
    }
}
