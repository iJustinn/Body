//
//  WatchComputeAssembly.swift
//  Body
//
//  The pure half of the watch's metric compute: given a phone seed and one
//  fetched HealthKit delta, it produces the same `WatchComputeResult` the
//  watch publishes. `WatchComputeCoordinator` keeps only the impure parts
//  (seed load, actor coalescing, the HealthKit fetch) and calls in here, so
//  the assembly itself is ordinary shared kit code the phone's test target
//  compiles and exercises directly.
//

import Foundation
import os

enum WatchComputeAssembly {
    private static let logger = Logger(
        subsystem: "com.zihengthedeveloper.Body",
        category: "WatchCompute"
    )

    /// What the seed's own data window allows this run to do.
    enum WindowDecision: Equatable {
        /// The delta window would reach past the watch's HealthKit retention.
        case tooOld
        /// The seed's `dataThrough` is implausibly far in the future.
        case futureDataThrough
        /// Fetch the delta from this instant.
        case fetch(windowStart: Date)
    }

    static func windowDecision(
        seed: WatchComputeSeed,
        now: Date,
        calendar: Calendar
    ) -> WindowDecision {
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
            return .tooOld
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
            return .futureDataThrough
        }
        return .fetch(windowStart: windowStart)
    }

    // MARK: - The assembly

    /// `nil` when the compute produced nothing usable.
    static func assemble(
        seed: WatchComputeSeed,
        delta: WatchComputeDelta,
        permission: BodyHealthPermissionSelection,
        generation: UInt64,
        windowStart: Date,
        now: Date,
        calendar: Calendar
    ) -> WatchComputeResult? {
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
        // The weekly workout-minutes bars come from THIS run's fetch alone (no
        // seeded workout history to fall back on), so a failed or
        // permission-refused query leaves them absent rather than publishing a
        // fabricated week of rest days.
        let workoutWeekly: [Double?]? = delta.workouts.isSuccess
            ? Self.workoutWeeklyMinutes(workouts: fetchedWorkouts, now: now, calendar: calendar)
            : nil
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
            workoutWeeklyMinutes: workoutWeekly,
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
    static func trainingLoadSeries(
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

    /// The trailing week's daily workout minutes, oldest → today, matching the
    /// builder's own `weekly` windowing (7 slots ending on `now`'s day). A
    /// workout counts toward the day it STARTED, the same rule
    /// `trainingLoadSeries` and the phone's month snapshots use.
    ///
    /// Dense by construction: a day with no workouts is an explicit `0`, never
    /// `nil`. A nil-padded week would make the metric blank
    /// (`WatchMetric.hasValue`) and the merge's blank-preserve rule would refuse
    /// it, freezing the phone's older bars on the complication forever.
    static func workoutWeeklyMinutes(
        workouts: [WorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> [Double?] {
        let minutesByDay = workouts.reduce(into: [Date: Double]()) { partialResult, workout in
            partialResult[calendar.startOfDay(for: workout.startDate), default: 0] += workout.duration / 60
        }
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return 0 }
            return minutesByDay[day] ?? 0
        }
    }

    /// The freshly-fetched night to overlay onto the seed's summary, or `nil` to
    /// keep the seed's. Applied only when the fetched night is not OLDER than
    /// the seeded one: the watch retains far less sleep history than the phone,
    /// and its "latest" night can genuinely predate the phone's. A fetched night
    /// with no day at all can't be proven newer, so it's refused too (it would
    /// fail `SleepSummary.asOf` and blank the card anyway).
    static func overlaidSleepNight(
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
    static func dataAsOf(
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
        // The weekly workout-minutes bars are a COVERAGE claim for the same
        // reason: a successful EMPTY query is fresh information (a genuine rest
        // day must be able to fall back to a zero bar), so the watermark is the
        // query window's end. Absent when Workouts is off or the query failed —
        // nothing was re-derived, and the phone's own bars stay authoritative.
        if permission.includes(.workouts), delta.workouts.isSuccess {
            map[WatchMetricKindKey.workoutMinutes] = now
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
    static func chartDataAsOf(delta: WatchComputeDelta, now: Date) -> [String: Date] {
        var map: [String: Date] = [:]
        if delta.wristTemperatureSeries.isSuccess {
            map[WatchMetricKindKey.wristTemperature] = now
        }
        return map
    }

    static func temperatureUnitPreference(
        for settings: WatchComputeSettings
    ) -> BodyValueFormat.TemperatureUnitPreference {
        settings.followsSystemUnits
            ? BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.TemperatureUnitPreference.storedValue(from: settings.selectedTemperatureUnitRaw)
    }
}
