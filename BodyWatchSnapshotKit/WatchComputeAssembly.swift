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

    /// `nil` when the compute produced nothing usable. `warningSettings` is
    /// the iPhone's, from its last push; nil checks no warning.
    static func assemble(
        seed: WatchComputeSeed,
        delta: WatchComputeDelta,
        permission: BodyHealthPermissionSelection,
        generation: UInt64,
        windowStart: Date,
        now: Date,
        calendar: Calendar,
        warningSettings: WatchWarningSettings? = nil
    ) -> WatchComputeResult? {
        // The iPhone's ratings for workouts this watch read as unrated, filled in
        // before anything reads the workouts, so Training Load, the Readiness
        // drain and Stress all count the same efforts (see `applyingEffortHints`).
        var delta = delta
        if case .success(let workouts) = delta.workouts {
            delta.workouts = .success(Self.applyingEffortHints(workouts, hints: seed.trainingLoadEffortHints))
        }
        var trends = seed.trends
        trends.heartRate = WatchDeltaSplicer.splice(
            seedSeries: trends.heartRate, delta: delta.heartRateSeries, from: windowStart, calendar: calendar
        )
        // The week charts' daily min/max capsules, spliced like the averages
        // they sit under. Accepted edge: the range read is its own query and
        // not a readiness input, so when it fails while the average succeeds
        // the week keeps the seed's capsules (today's may be missing, or an
        // older partial day's) under a fresh average point, until the next
        // compute or push.
        trends.heartRateRanges = WatchDeltaSplicer.spliceRanges(
            seedSeries: trends.heartRateRanges, delta: delta.heartRateRanges, from: windowStart
        )
        trends.restingHeartRate = WatchDeltaSplicer.splice(
            seedSeries: trends.restingHeartRate, delta: delta.restingHeartRateSeries, from: windowStart, calendar: calendar
        )
        trends.heartRateVariability = WatchDeltaSplicer.splice(
            seedSeries: trends.heartRateVariability, delta: delta.heartRateVariabilitySeries, from: windowStart, calendar: calendar
        )
        trends.heartRateVariabilityRanges = WatchDeltaSplicer.spliceRanges(
            seedSeries: trends.heartRateVariabilityRanges, delta: delta.heartRateVariabilityRanges, from: windowStart
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
        // STAGES, not nights, and keeps `sleepHistoryDayCount` nights for
        // Sleep Debt), and `trends.sleep` is a readiness source series:
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

        // Steps, Active Energy and Resting Energy: the week this run read
        // replaces the series WHOLESALE rather than splicing, because the seed
        // carries no history for these kinds (`watchComputeTrimmed` collapses
        // them to `.empty`), and today's point is the card's headline, the
        // same "today's bucket only" the phone's summary means (nil when today
        // has no total yet). Set here, beside the other overlays, so they ride
        // the permission filter below like every other card's inputs. A failed
        // read leaves the seed's values: its empty series, and the phone's own
        // summary from the last push, which the builder may still show. That
        // is safe because the kind then stays out of `dataAsOf` (and
        // `chartDataAsOf`), and `WatchComputeMerge.mergingComputed` adopts no
        // unstamped kind, so whatever the card already shows stands.
        if case .success(let stepsWeek) = delta.stepsWeek {
            trends.steps = stepsWeek
            summary.steps = HealthMetricSummary(value: stepsWeek.point(on: calendar.startOfDay(for: now))?.value)
        }
        if case .success(let activeEnergyWeek) = delta.activeEnergyWeek {
            trends.activeEnergy = activeEnergyWeek
            summary.activeEnergy = HealthMetricSummary(value: activeEnergyWeek.point(on: calendar.startOfDay(for: now))?.value)
        }
        if case .success(let restingEnergyWeek) = delta.restingEnergyWeek {
            trends.restingEnergy = restingEnergyWeek
            summary.restingEnergy = HealthMetricSummary(value: restingEnergyWeek.point(on: calendar.startOfDay(for: now))?.value)
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
                // The watch's own drain report (see `WatchReadinessDrainReconciler`).
                // Only when the workout query SUCCEEDED: a failed one leaves
                // `fetchedWorkouts` empty for lack of an answer, which must not
                // be reported as "no workouts this wake cycle".
                wakeCycleStart: delta.workouts.isSuccess
                    ? ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: sleepEnd, calendar: calendar)
                    : nil,
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
                // Stress below makes the same `recordedStressContext: nil`
                // call, and one more documented deviation of its own:
                // * "Yesterday": when the last 12 hours cross midnight the
                //   watch reads all of yesterday, so its recompute replaces
                //   the seeded record for yesterday (fresh wins) and the
                //   adopted week shows the watch's score for it. Local only;
                //   the next seed brings the phone's record back.
                now: now,
                freezesRecordedReadiness: false,
                recordedReadinessContext: nil
            )

        // Stress: the phone's `recalculatingStress` over the seed's recorded
        // days (the baselines and the week) plus this run's intraday reads,
        // then the "Last 12 hours" timeline over the same inputs. Only the
        // Stress fields are taken from it, so everything the builder reads
        // for the other cards is exactly `recomputed`. With no reads at all
        // it rebuilds the week from the seeded records alone.
        var display = recomputed
        var stressTimeline: WatchStressTimeline?
        if permission.includes(.heart) {
            var stressInputs = recomputed
            stressInputs.trends.heartRateDaySamples = Self.daySamples(delta.stressHeartRateSamples)
            stressInputs.trends.heartRateVariabilityDaySamples = Self.daySamples(delta.stressSDNNSamples)
            stressInputs.trends.heartbeatRMSSDDaySamples = Self.daySamples(delta.stressRMSSDSamples)
            // The movement mask reads only what the phone's permission filter
            // leaves it.
            stressInputs.trends.stressStepsDaySamples = permission.includes(.steps)
                ? Self.daySamples(delta.stressQuarterHourSteps)
                : .empty
            stressInputs.trends.stressActiveEnergyDaySamples = permission.includes(.energy)
                ? Self.daySamples(delta.stressQuarterHourActiveEnergy)
                : .empty
            let stressed = stressInputs.recalculatingStress(
                on: now,
                workouts: fetchedWorkouts,
                calendar: calendar,
                now: now,
                recordedStressContext: nil
            )
            display.summary.stress = stressed.summary.stress
            display.summary.stressCurrentScore = stressed.summary.stressCurrentScore
            display.trends.stress = stressed.trends.stress
            display.trends.stressRanges = stressed.trends.stressRanges
            stressTimeline = WatchStressTimelineBuilder.make(
                dashboard: stressed,
                workouts: fetchedWorkouts,
                now: now,
                calendar: calendar,
                computedAt: now
            )
        }

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
            summary: display.summary,
            trends: display.trends,
            lastRefreshDate: seed.lastVitalsRefreshDate,
            permissionSelection: permission,
            temperatureUnitPreference: Self.temperatureUnitPreference(for: seed.settings),
            energyUnitPreference: Self.energyUnitPreference(for: seed.settings),
            idealSleepDuration: idealSleepDuration,
            showSleepScore: seed.settings.showSleepScore,
            now: now,
            workoutWeeklyMinutes: workoutWeekly,
            // Union the phone's broader history into each carried range so the
            // watch's short delta window can't shrink the ring/chart bounds.
            seriesRangeOverride: { seed.seriesRanges[$0] },
            perKindDataAsOf: { dataAsOf[$0] },
            // Always built: whether it shows is the phone's pushed flag
            // (`WatchMetricsSnapshot.showsSleepDebt`), not the compute's call.
            includesSleepDebt: true,
            // No `workoutColorOverrides`: a display preference only the
            // phone's push carries.
            stressTimeline: stressTimeline
        )
        snapshot.source = "watch"
        snapshot.heartCharts = Self.heartCharts(delta: delta, permission: permission)
        snapshot.workoutSpans = Self.workoutSpans(delta: delta, now: now, calendar: calendar)
        snapshot.warningChecks = Self.warningChecks(
            delta: delta,
            settings: warningSettings,
            permission: permission,
            now: now,
            calendar: calendar
        )

        guard snapshot.metrics.contains(where: \.hasValue) else { return nil }
        return WatchComputeResult(
            snapshot: snapshot,
            dataAsOf: dataAsOf,
            chartDataAsOf: Self.chartDataAsOf(delta: delta, now: now),
            // The instant this compute's queries ran to — the information
            // cutoff the merge compares against PHONE-derived stamps (which
            // are themselves refresh/query times, the same domain).
            coverage: now,
            generation: generation,
            drainIsFresh: permission.includes(.workouts) && delta.workouts.isSuccess,
            readinessCarriedInputs: Self.readinessCarriedInputs(delta: delta),
            readinessBlockers: Self.readinessBlockers(
                delta: delta,
                replayedTrainingLoad: trainingLoad != nil,
                permission: permission
            ),
            sleepDebtAsOf: Self.sleepDebtAsOf(
                delta: delta,
                replayedTrainingLoad: trainingLoad != nil,
                permission: permission,
                now: now
            )
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
              let loadsThrough = seed.trainingLoadDataThrough else {
            logger.info("Training Load not replayed: the seed carries no daily loads.")
            return nil
        }
        guard calendar.startOfDay(for: loadsThrough) >= calendar.startOfDay(for: windowStart) else {
            logger.info("Training Load not replayed: the seed's loads stop before the delta window.")
            return nil
        }
        guard case .success(let deltaWorkouts) = workouts else {
            logger.info("Training Load not replayed: no workout read this run.")
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

    /// `workouts` with the iPhone's rating (`WatchComputeSeed.trainingLoadEffortHints`)
    /// filled in for each one this watch read as unrated: a rating made on the
    /// iPhone can take hours to reach the watch's own store, or never arrive,
    /// and until then the watch would count the workout at the default effort
    /// while the iPhone counts the rating. A rating the watch read itself always
    /// wins, being the live read of the store that holds the sample.
    static func applyingEffortHints(_ workouts: [WorkoutSummary], hints: [String: Double]?) -> [WorkoutSummary] {
        guard let hints, !hints.isEmpty else { return workouts }
        return workouts.map { workout in
            guard workout.effortLevel == nil, let hint = hints[workout.id.uuidString] else { return workout }
            return workout.replacingEffortLevel(hint)
        }
    }

    /// The trailing week's daily workout minutes, oldest → today, matching the
    /// builder's own `weekly` windowing (7 slots ending on `now`'s day). A
    /// workout counts toward the day it STARTED, in the watch's CURRENT zone,
    /// the same rule `trainingLoadSeries` uses. The phone's month snapshots
    /// resolve each workout's day through the device time-zone ledger instead,
    /// so on a travel day the two can name different days for the same workout;
    /// the phone's answer wins wherever a month snapshot is what gets published.
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
        // Steps, Active Energy and Resting Energy are COVERAGE claims for the
        // same reason: each card's headline and bars come from this run's week
        // of daily totals alone, and a successful read with no total today is
        // fresh information too (nothing counted yet, a "--" the merge never
        // adopts over a value), so the watermark is the query window's end.
        // Absent when the permission is off or the read failed: nothing was
        // re-derived, and the phone's own card stays authoritative. Neither
        // readiness nor Stress inputs.
        if permission.includes(.steps), delta.stepsWeek.isSuccess {
            map[WatchMetricKindKey.steps] = now
        }
        if permission.includes(.energy), delta.activeEnergyWeek.isSuccess {
            map[WatchMetricKindKey.activeEnergy] = now
        }
        if permission.includes(.energy), delta.restingEnergyWeek.isSuccess {
            map[WatchMetricKindKey.restingEnergy] = now
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
        let readinessInputsFresh = Self.readinessBlockers(
            delta: delta,
            replayedTrainingLoad: replayedTrainingLoad,
            permission: permission
        ).isEmpty
        if readinessInputsFresh {
            map[WatchMetricKindKey.readiness] = now
        }
        // Stress: coverage semantics again, under its own all-inputs rule
        // (`stressAsOf`).
        if let stressAsOf = Self.stressAsOf(delta: delta, permission: permission, now: now) {
            map[WatchMetricKindKey.stress] = stressAsOf
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

    /// The Sleep Debt's watermark (see `WatchComputeResult.sleepDebtAsOf`),
    /// or nil when the debt must not be adopted. Coverage semantics, like
    /// Training Load's and Readiness's above: the debt reads the sleep history
    /// (its durations and sleep HRV) and, when Workouts is permitted, the
    /// Training Load series, so it is stamped with the query window's end only
    /// when EVERY one of those was re-read this run. A failed or carried sleep
    /// read leaves the seed's own nights in the history, and a Training Load
    /// replay that didn't run leaves the phone's own ratios; stamping either
    /// would launder the phone's debt as computed on the watch just now and
    /// let it outrank the next push.
    static func sleepDebtAsOf(
        delta: WatchComputeDelta,
        replayedTrainingLoad: Bool,
        permission: BodyHealthPermissionSelection,
        now: Date
    ) -> Date? {
        guard permission.includes(.sleep),
              delta.sleepNights.isSuccess,
              !delta.carriedKinds.contains(.sleep),
              !permission.includes(.workouts) || replayedTrainingLoad else {
            return nil
        }
        return now
    }

    /// Stress's watermark in `dataAsOf`, which also covers the "Last 12 hours"
    /// timeline (`WatchComputeMerge.mergingComputed`), or nil when neither
    /// may be adopted. Coverage semantics, like Sleep Debt's: Stress scores
    /// today's intraday heart rate, SDNN and RMSSD, masks movement with the
    /// 15 minute steps and active energy and the workouts, and reads the main
    /// sleep session as rest context, so it is stamped with the query window's
    /// end only when every one of those that is permitted was re-read this
    /// run. A carried heart kind (no source on this watch) was not re-read,
    /// whatever its outcome says. Anything less leaves the phone's Stress
    /// standing; an uncalibrated baseline still stamps, and its blank card is
    /// never adopted over a value.
    static func stressAsOf(
        delta: WatchComputeDelta,
        permission: BodyHealthPermissionSelection,
        now: Date
    ) -> Date? {
        guard permission.includes(.heart),
              delta.stressHeartRateSamples.isSuccess,
              delta.stressSDNNSamples.isSuccess,
              delta.stressRMSSDSamples.isSuccess,
              !delta.carriedKinds.contains(.heartRate),
              !delta.carriedKinds.contains(.heartRateVariability),
              !permission.includes(.steps) || delta.stressQuarterHourSteps.isSuccess,
              !permission.includes(.energy) || delta.stressQuarterHourActiveEnergy.isSuccess,
              !permission.includes(.sleep) || (delta.sleepNights.isSuccess && !delta.carriedKinds.contains(.sleep)),
              !permission.includes(.workouts) || delta.workouts.isSuccess else {
            return nil
        }
        return now
    }

    /// A Stress intraday read's series, empty when it didn't succeed.
    private static func daySamples(_ outcome: WatchFetchOutcome<HealthTrendSeries>) -> HealthTrendSeries {
        if case .success(let series) = outcome {
            return series
        }
        return .empty
    }

    /// The permission-eligible readiness inputs that did not succeed this run,
    /// by name. Empty means readiness may be stamped (see `dataAsOf`).
    ///
    /// A kind in `delta.carriedKinds` (no local source on this watch at all)
    /// is not a blocker: nothing the watch could read is missing, and the
    /// phone's seeded series stands in for it until the next push. That only
    /// holds while the watch re-read SOMETHING itself. With every vitals and
    /// sleep input carried, the score would be the phone's own numbers
    /// presented as freshly computed, so that case still blocks.
    static func readinessBlockers(
        delta: WatchComputeDelta,
        replayedTrainingLoad: Bool,
        permission: BodyHealthPermissionSelection
    ) -> [String] {
        var inputs: [(kind: HealthMetricKind, succeeded: Bool)] = []
        if permission.includes(.heart) {
            // The HR / HRV range reads are deliberately absent: they only draw
            // the week charts' capsules, which the score never reads.
            inputs.append((.heartRate, delta.heartRateSeries.isSuccess))
            inputs.append((.restingHeartRate, delta.restingHeartRateSeries.isSuccess))
            inputs.append((.heartRateVariability, delta.heartRateVariabilitySeries.isSuccess))
        }
        if permission.includes(.respiratory) {
            inputs.append((.respiratoryRate, delta.respiratoryRateSeries.isSuccess))
        }
        if permission.includes(.bloodOxygen) {
            inputs.append((.oxygenSaturation, delta.oxygenSaturationSeries.isSuccess))
        }
        if permission.includes(.wristTemperature) {
            inputs.append((.wristTemperature, delta.wristTemperatureSeries.isSuccess))
        }
        if permission.includes(.sleep) {
            inputs.append((.sleep, delta.sleepNights.isSuccess))
        }
        var blockers = inputs
            .filter { !$0.succeeded && !delta.carriedKinds.contains($0.kind) }
            .map(\.kind.rawValue)
        if !inputs.isEmpty, !inputs.contains(where: \.succeeded) {
            blockers = inputs.map(\.kind.rawValue)
        }
        if permission.includes(.workouts) {
            if !delta.workouts.isSuccess {
                blockers.append("workouts")
            } else if !replayedTrainingLoad {
                blockers.append("trainingLoad")
            }
        }
        return blockers
    }

    /// The readiness inputs carried from the phone's seed because this watch
    /// holds no source for them. Diagnostics only.
    static func readinessCarriedInputs(delta: WatchComputeDelta) -> [String] {
        delta.carriedKinds.map(\.rawValue).sorted()
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

    /// The Heart Rate and HRV chart complications' slots
    /// (`WatchMetricsSnapshot.heartCharts`), keyed by kind: every chart this
    /// run read, an empty one included (the merge's "remove"), and no key for
    /// a read that failed or was skipped (the merge's "keep"). Nil without
    /// Heart, and nil when no read succeeded, so a compute that read no chart
    /// carries no field at all. Display only, like the week charts' ranges:
    /// no watermark, since each chart carries its own read time
    /// (`WatchIntradayWindow.end`), which is what `WatchComputeMerge` compares.
    static func heartCharts(
        delta: WatchComputeDelta,
        permission: BodyHealthPermissionSelection
    ) -> [String: WatchIntradayChart]? {
        guard permission.includes(.heart) else { return nil }
        var charts: [String: WatchIntradayChart] = [:]
        if case .success(let chart) = delta.heartRateIntraday {
            charts[WatchMetricKindKey.heartRate] = chart
        }
        if case .success(let chart) = delta.heartRateVariabilityIntraday {
            charts[WatchMetricKindKey.heartRateVariability] = chart
        }
        return charts.isEmpty ? nil : charts
    }

    /// The warning kinds the watch checks itself: the ones with a watch card
    /// (Low and High Heart Rate on Heart Rate, High Skin Temperature on Skin
    /// Temp), in `MetricWarningKind.allCases` order. `WatchDeltaFetcher`
    /// reads today's readings for these kinds only.
    static let checkedWarningKinds: [MetricWarningKind] = [.lowHeartRate, .highHeartRate, .highWristTemperature]

    /// The workouts this run read whose High Heart Rate exclusion (the
    /// workout plus its 30 minute recovery grace,
    /// `MetricThresholdWarning.workoutExclusionInterval`) reaches into today,
    /// in start order (`WatchMetricsSnapshot.workoutSpans`): a workout that
    /// ran past midnight, or ended no more than 30 minutes before it, still
    /// counts, and one starting after `now` doesn't. Nil when the workout
    /// read failed or was skipped (the merge's "keep"), empty when it found
    /// none (its "clear").
    static func workoutSpans(
        delta: WatchComputeDelta,
        now: Date,
        calendar: Calendar
    ) -> [WatchWorkoutSpan]? {
        guard case .success(let workouts) = delta.workouts else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        return workouts
            .filter { workout in
                workout.startDate <= now
                    && MetricThresholdWarning.workoutExclusionInterval(
                        start: workout.startDate,
                        end: workout.effectiveEndDate
                    ).end >= startOfToday
            }
            .map { WatchWorkoutSpan(start: $0.startDate, end: $0.effectiveEndDate) }
            .sorted { $0.start < $1.start }
    }

    /// The warnings this run checked itself (`WatchMetricsSnapshot.warningChecks`),
    /// in `checkedWarningKinds` order: one for each kind with the iPhone's
    /// threshold and a reading that succeeded, carrying the day's earliest
    /// episode past that threshold through the iPhone's own detection
    /// (`MetricThresholdWarning.detect`), or none. High Heart Rate follows the
    /// iPhone's `fetchTodayHighHeartRateWarning`: it is checked only with
    /// Workouts on and a workout read that succeeded, and leaves out the
    /// readings inside today's workouts and their recovery grace. Nil when no
    /// kind was checked, so such a compute carries no field.
    static func warningChecks(
        delta: WatchComputeDelta,
        settings: WatchWarningSettings?,
        permission: BodyHealthPermissionSelection,
        now: Date,
        calendar: Calendar
    ) -> [WatchWarningCheck]? {
        guard let settings else { return nil }
        let checks = checkedWarningKinds.compactMap { kind -> WatchWarningCheck? in
            guard let threshold = settings.thresholds[kind.rawValue],
                  case .success(let readings) = delta.warningReadings[kind] else {
                return nil
            }
            var exclusions: [DateInterval] = []
            if kind.excludesWorkouts {
                guard permission.includes(.workouts), case .success(let workouts) = delta.workouts else {
                    return nil
                }
                exclusions = todaysWorkoutExclusions(workouts, now: now, calendar: calendar)
            }
            let episode = MetricThresholdWarning.detect(
                kind,
                inSamples: readings,
                threshold: threshold,
                excluding: exclusions
            )
            return WatchWarningCheck(
                kind: kind.rawValue,
                checkedAt: now,
                threshold: threshold,
                episode: episode.map {
                    WatchWarningCheck.Episode(startDate: $0.startDate, endDate: $0.endDate, extremeValue: $0.extremeValue)
                }
            )
        }
        return checks.isEmpty ? nil : checks
    }

    /// The iPhone's High Heart Rate exclusions over this run's workouts, its
    /// `fetchTodayWorkoutIntervals` filter: every workout that started before
    /// `now` and ended after today's start (an overnight one from yesterday
    /// included), plus its recovery grace.
    private static func todaysWorkoutExclusions(
        _ workouts: [WorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> [DateInterval] {
        let startOfToday = calendar.startOfDay(for: now)
        return workouts.compactMap { workout in
            guard workout.startDate < now,
                  workout.effectiveEndDate > startOfToday,
                  workout.startDate <= workout.effectiveEndDate else {
                return nil
            }
            return MetricThresholdWarning.workoutExclusionInterval(
                start: workout.startDate,
                end: workout.effectiveEndDate
            )
        }
    }

    static func temperatureUnitPreference(
        for settings: WatchComputeSettings
    ) -> BodyValueFormat.TemperatureUnitPreference {
        settings.followsSystemUnits
            ? BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.TemperatureUnitPreference.storedValue(from: settings.selectedTemperatureUnitRaw)
    }

    /// The phone's `HealthWidgetSnapshotBuilder.storedEnergyUnitPreference()`
    /// resolution, exactly, so a watch-built Active or Resting Energy card
    /// reads in the iPhone card's unit. The seed carries no raw value for
    /// kilocalories (`selectedEnergyUnitRaw` nil), which falls back to the
    /// default like an unset preference on the phone.
    static func energyUnitPreference(
        for settings: WatchComputeSettings
    ) -> BodyValueFormat.EnergyUnitPreference {
        settings.followsSystemUnits
            ? BodyValueFormat.EnergyUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.EnergyUnitPreference.storedValue(
                from: settings.selectedEnergyUnitRaw ?? BodyValueFormat.EnergyUnitPreference.defaultValue.rawValue
            )
    }
}
