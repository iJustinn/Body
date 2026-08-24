//
//  WatchComputeParityTests.swift
//  BodyTests
//
//  The on-watch realtime compute plan's core proof (Phase 5): the phone path
//  and the watch path produce IDENTICAL metrics when they see the same data.
//  Both paths here are built entirely from shared pure code — `WatchComputeMerge`,
//  `WatchDeltaSplicer`, `WatchComputeSeed`, `TrainingLoadCalculator`,
//  `ReadinessComputeSupport`, `WatchMetricsSnapshotBuilder`, and
//  `HealthDashboardSnapshot.filteredWithoutReadinessRecompute`/
//  `.recalculatingReadiness` — never a BodyWatch-target type.
//
//  Where this test CANNOT call the real `WatchComputeCoordinator`/
//  `WatchDeltaFetcher` and why:
//  * `BodyWatch/WatchComputeCoordinator.swift` and `WatchDeltaFetcher.swift` are
//    watchOS-only sources, not linked into the `BodyTests` (iOS) target. This
//    test's `watchSnapshot(...)` instead replicates the coordinator's exact
//    assembly order (splice → summary overlay → Training Load slot overwrite →
//    `filteredWithoutReadinessRecompute` → `recalculatingReadiness` →
//    `makeSnapshot(seriesRangeOverride:perKindDataAsOf:)`), reading
//    `BodyWatch/WatchComputeCoordinator.swift` line-for-line to keep the two
//    in lockstep. If that file's assembly order ever changes, this test's
//    helper must change with it.
//  * The real fetch layer (`BodyHealthSourceResolver` source resolution,
//    `BodyHealthQuantityFetch`/`BodySleepFetch`/`BodyWorkoutFetch` HealthKit
//    queries, `BodyWorkoutEffortFetcher` effort lookups) is not exercised —
//    this test hands the assembly line already-resolved fixture data (what a
//    successful, permission-granted, source-resolved fetch would have
//    returned). Source-resolution strictness and HealthKit failure paths are
//    covered by `BodyHealthSourceResolverTests` and `WatchDeltaSplicerTests`;
//    workouts here carry an explicit `effortLevel` rather than one resolved
//    from a saved HealthKit sample.
//

import XCTest
@testable import Body

final class WatchComputeParityTests: XCTestCase {
    private let permission = BodyHealthPermissionSelection.defaultValue

    // MARK: - Fixture

    private struct Fixture {
        var summary: HealthSummarySnapshot
        var trends: HealthTrendSnapshot
        var workouts: [WorkoutSummary]
        var trainingLoadStartDay: Date
        var trainingLoadDailyLoads: [Double]
        var settings: WatchComputeSettings
        var idealSleepDuration: TimeInterval
        var recordedReadinessContext: String
    }

    /// 365 days of vitals trends, ~70 nights of sleep history (multi-segment
    /// nights with leading/interior/trailing awake time in nights 8–15, which
    /// straddle the seed's `sleepSegmentDayCount` (15) collapse boundary), and
    /// workouts spanning the full 408-slot Training Load lookback — everything
    /// `HealthKitWorkoutStore.makeComputeSeed` needs to build a realistic seed,
    /// and everything the phone's own dashboard recompute needs to score
    /// Readiness. `anchor` is both "today" and the instant the fixture's data
    /// extends through.
    private func makeFixture(anchor: Date, calendar: Calendar) throws -> Fixture {
        let anchorDay = calendar.startOfDay(for: anchor)
        let idealSleepDuration: TimeInterval = 8 * 3_600

        var trends = HealthTrendSnapshot.empty
        trends.heartRate = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 64, amplitude: 6)
        trends.restingHeartRate = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 56, amplitude: 4)
        trends.heartRateVariability = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 52, amplitude: 10)
        trends.respiratoryRate = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 15, amplitude: 1.2)
        trends.oxygenSaturation = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 97, amplitude: 1.0)
        trends.wristTemperature = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 36.2, amplitude: 0.4)

        var nights: [SleepDaySummary] = []
        for offset in 0...70 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchorDay) else { continue }
            nights.append(sleepNight(on: day, ageInDays: offset, calendar: calendar))
        }
        trends.sleepHistory = SleepHistorySnapshot(days: nights)
        // Mirrors the phone's own invariant (documented in
        // `WatchComputeCoordinator`): the sleep duration series is DERIVED from
        // the history, never a separately-tracked series.
        trends.sleep = trends.sleepHistory.durationSeries

        let trainingLoadStartDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -407, to: anchorDay))
        let workouts = workoutsFixture(startDay: trainingLoadStartDay, anchor: anchor, calendar: calendar)
        let dailyLoadValues = try XCTUnwrap(TrainingLoadCalculator.dailyLoadValues(
            from: workouts, startDate: trainingLoadStartDay, endDate: anchorDay, calendar: calendar
        ))
        XCTAssertEqual(dailyLoadValues.loads.count, 408, "408 slots: 407 lookback days + today, inclusive")
        trends.trainingLoad = Self.trainingLoadSeries(startDay: dailyLoadValues.startDay, loads: dailyLoadValues.loads, calendar: calendar)

        let todayNight = try XCTUnwrap(nights.first { calendar.isDate($0.date, inSameDayAs: anchorDay) }).summary

        var summary = HealthSummarySnapshot(
            activityRings: .empty,
            readiness: .unavailable,
            sleep: todayNight,
            heartRate: HealthMetricSummary(value: trends.heartRate.point(on: anchorDay)?.value),
            restingHeartRate: HealthMetricSummary(value: trends.restingHeartRate.point(on: anchorDay)?.value),
            bodyMass: HealthMetricSummary(value: nil),
            bodyFatPercentage: HealthMetricSummary(value: nil),
            heartRateVariability: HealthMetricSummary(value: trends.heartRateVariability.point(on: anchorDay)?.value),
            respiratoryRate: HealthMetricSummary(value: trends.respiratoryRate.point(on: anchorDay)?.value),
            oxygenSaturation: HealthMetricSummary(value: trends.oxygenSaturation.point(on: anchorDay)?.value),
            bodyMassIndex: HealthMetricSummary(value: nil),
            activeEnergy: HealthMetricSummary(value: nil),
            restingEnergy: HealthMetricSummary(value: nil),
            exerciseMinutes: HealthMetricSummary(value: nil),
            trainingLoad: HealthMetricSummary(value: trends.trainingLoad.point(on: anchorDay)?.value),
            wristTemperature: HealthMetricSummary(value: trends.wristTemperature.point(on: anchorDay)?.value),
            timeInDaylight: HealthMetricSummary(value: nil),
            steps: HealthMetricSummary(value: nil)
        )

        // A morning record for TODAY is already frozen — matching the seed's
        // own record set, not a divergent one the phone freeze would later
        // overwrite. Readiness is exact-parity provable specifically when this
        // holds (see the plan's Phase 5 note): the watch never freezes new
        // records (`freezesRecordedReadiness: false`), so it can only match the
        // phone's history when the record it needs is already there.
        let recordedContext = "fixture-readiness-context"
        let coverage = HealthDashboardSnapshot(summary: summary, trends: trends)
            .readinessCoverage(on: anchorDay, calendar: calendar, today: anchor)
        let undrained = ReadinessScoreCalculator.summary(
            on: anchorDay, healthSummary: summary, trends: trends,
            idealSleepDuration: idealSleepDuration, calendar: calendar, today: anchor
        )
        let todayScore = try XCTUnwrap(undrained.score, "fixture must be rich enough to produce a real readiness score")
        trends.recordedReadiness = [
            RecordedReadinessEntry(
                date: anchorDay, score: todayScore,
                includedSleep: coverage.contains(.sleepDuration), coverage: coverage
            )
        ]
        trends.recordedReadinessContext = recordedContext
        summary.readiness = undrained

        // `followsSystemUnits: false` + an explicit Celsius raw value keeps the
        // watch's derived `temperatureUnitPreference` (Phase 4's
        // `WatchComputeCoordinator.temperatureUnitPreference(for:)`, which reads
        // `systemValue(locale:)` when `followsSystemUnits` is true) from
        // depending on the test machine's locale — the phone side below is
        // built with the literal `.celsius` preference, so both sides must
        // agree on the unit by construction, not by locale coincidence.
        let settings = WatchComputeSettings(
            idealSleepDurationMinutes: Int(idealSleepDuration / 60),
            followsSystemUnits: false,
            selectedTemperatureUnitRaw: BodyValueFormat.TemperatureUnitPreference.celsius.rawValue,
            showSleepScore: true,
            showsSubMinuteAwakeSleepStages: true,
            showsLeadingTrailingAwakeSleepStages: true,
            healthDataSourceSelectionRaw: "",
            combinesHealthDataSourcesByName: false
        )

        return Fixture(
            summary: summary,
            trends: trends,
            workouts: workouts,
            trainingLoadStartDay: trainingLoadStartDay,
            trainingLoadDailyLoads: dailyLoadValues.loads,
            settings: settings,
            idealSleepDuration: idealSleepDuration,
            recordedReadinessContext: recordedContext
        )
    }

    /// Age (days before `anchor`) of a single planted extreme value in every
    /// vitals series — deliberately OUTSIDE the seed's 70-day trim window
    /// (`WatchComputeSeed.trendDayCount`) and the readiness baseline lookback
    /// (`ReadinessScoreCalculator.baselineDayCount`, 56 days), so it can't
    /// perturb any score computation on either side, but well within the
    /// FULL 365-day history `seriesRanges(from:)` draws from.
    private static let extremeAgeDay = 120

    private func dailySeries(
        dayCount: Int, anchor: Date, calendar: Calendar, baseline: Double, amplitude: Double
    ) -> HealthTrendSeries {
        let anchorDay = calendar.startOfDay(for: anchor)
        var points: [HealthTrendDataPoint] = []
        for age in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { continue }
            // A 7-day phase (unchanged) PLUS a slow ~97-day drift that never
            // repeats across the fixture's 365 days: a purely 7-periodic
            // series can't distinguish the real 70-day trim window from any
            // other multiple of 7 (63, 77, …) — the drift can.
            let weeklyPhase = (Double(age % 7) - 3) / 3
            let drift = sin(Double(age) / 97.0 * 2 * Double.pi)
            var value = baseline + amplitude * (0.7 * weeklyPhase + 0.3 * drift)
            // A single extreme planted OUTSIDE the trim window: the phone's
            // own displayed range must include it (`makeComputeSeed`'s
            // `seriesRanges` is built from the FULL untrimmed trends), while
            // the watch's short delta re-read could never rediscover it on
            // its own — so this makes the `rangeMin`/`rangeMax` parity
            // assertions in `assertMetricsMatch` meaningful rather than
            // vacuously true (both sides otherwise seeing only the trimmed
            // window's own, much narrower, bounds).
            if age == Self.extremeAgeDay {
                value = baseline + amplitude * 6
            }
            points.append(HealthTrendDataPoint(date: day, value: value))
        }
        return HealthTrendSeries(points: points)
    }

    /// One night, `ageInDays` before the anchor. Nights 8–15 (inclusive) get a
    /// realistic multi-segment shape — leading, interior, AND trailing awake
    /// time around two asleep blocks — straddling the seed's 15-day full-detail
    /// boundary (`WatchComputeSeed.sleepSegmentDayCount`) with real segment
    /// lists rather than a trivial one-segment night. Every other night uses a
    /// simpler awake+asleep shape (reused from `ReadinessScoreCalculatorTests`'s
    /// `stageSnapshot` style).
    private func sleepNight(on day: Date, ageInDays: Int, calendar: Calendar) -> SleepDaySummary {
        let dayStart = calendar.startOfDay(for: day)
        let segments: [SleepStageSegment]
        if (8...15).contains(ageInDays) {
            let leadingAwakeStart = dayStart.addingTimeInterval(3_600)
            let leadingAwakeEnd = leadingAwakeStart.addingTimeInterval(20 * 60)
            let core1End = leadingAwakeEnd.addingTimeInterval(3 * 3_600)
            let interiorAwakeEnd = core1End.addingTimeInterval(15 * 60)
            let remEnd = interiorAwakeEnd.addingTimeInterval(3_600)
            let core2End = remEnd.addingTimeInterval(3 * 3_600)
            let trailingAwakeEnd = core2End.addingTimeInterval(10 * 60)
            segments = [
                SleepStageSegment(stage: .awake, startDate: leadingAwakeStart, endDate: leadingAwakeEnd),
                SleepStageSegment(stage: .core, startDate: leadingAwakeEnd, endDate: core1End),
                SleepStageSegment(stage: .awake, startDate: core1End, endDate: interiorAwakeEnd),
                SleepStageSegment(stage: .rem, startDate: interiorAwakeEnd, endDate: remEnd),
                SleepStageSegment(stage: .core, startDate: remEnd, endDate: core2End),
                SleepStageSegment(stage: .awake, startDate: core2End, endDate: trailingAwakeEnd)
            ]
        } else {
            let awakeStart = dayStart.addingTimeInterval(3_600)
            let awakeEnd = awakeStart.addingTimeInterval(15 * 60)
            // A slow, non-periodic duration drift (period ~11 nights, never
            // aligning with a 7- or 15-day boundary) rather than the old
            // 3-night-periodic pattern — a short-period series can mask a
            // window-length regression the same way the vitals series' old
            // 7-day phase could.
            let coreEnd = awakeEnd.addingTimeInterval((7.6 + 0.3 * sin(Double(ageInDays) / 11.0)) * 3_600)
            segments = [
                SleepStageSegment(stage: .awake, startDate: awakeStart, endDate: awakeEnd),
                SleepStageSegment(stage: .core, startDate: awakeEnd, endDate: coreEnd)
            ]
        }
        let snapshot = SleepStageSnapshot(date: dayStart, segments: segments)
        let vitals = SleepVitalsSummary(
            heartRate: 56, heartRateVariability: 58, respiratoryRate: 14.8,
            oxygenSaturation: 97.2, wristTemperatureCelsius: 36.2
        )
        return SleepDaySummary(
            date: dayStart,
            summary: SleepSummary(duration: snapshot.mergedAsleepDuration, stageSnapshot: snapshot, vitals: vitals)
        )
    }

    /// A workout every third day across the full 408-day Training Load lookback,
    /// plus one inside today's wake cycle (an hour before `anchor`) so the
    /// same-day activity drain and Training Load's today-slot both have real
    /// input on both paths.
    private func workoutsFixture(startDay: Date, anchor: Date, calendar: Calendar) -> [WorkoutSummary] {
        var workouts: [WorkoutSummary] = []
        for index in 0...407 {
            guard index % 3 == 0, let day = calendar.date(byAdding: .day, value: index, to: startDay) else { continue }
            let start = day.addingTimeInterval(17 * 3_600)
            let durationMinutes = 30 + Double(index % 5) * 8
            workouts.append(WorkoutSummary(
                type: .running,
                startDate: start,
                duration: durationMinutes * 60,
                effortLevel: Double(3 + index % 6)
            ))
        }
        workouts.append(WorkoutSummary(
            type: .running,
            startDate: anchor.addingTimeInterval(-3_600),
            duration: 35 * 60,
            effortLevel: 6
        ))
        return workouts
    }

    private static func trainingLoadSeries(startDay: Date, loads: [Double], calendar: Calendar) -> HealthTrendSeries {
        var pairs: [(date: Date, load: Double)] = []
        var day = calendar.startOfDay(for: startDay)
        for load in loads {
            pairs.append((date: day, load: load))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return TrainingLoadCalculator.series(fromDailyLoads: pairs)
    }

    // MARK: - Phone path

    /// `HealthKitWorkoutStore.updateHealthDashboardSnapshot`'s real call
    /// sequence (`Body/Services/HealthKitWorkoutStore.swift:2932-2946`):
    /// `filteredWithoutReadinessRecompute` → `recalculatingReadiness` (freezing
    /// today's morning record) → `WatchMetricsSnapshotBuilder.makeSnapshot`.
    private func phoneSnapshot(fixture: Fixture, now: Date, calendar: Calendar) -> WatchMetricsSnapshot {
        let rawSnapshot = HealthDashboardSnapshot(summary: fixture.summary, trends: fixture.trends)
        let filtered = rawSnapshot.filteredWithoutReadinessRecompute(by: permission)

        let sleepEnd = fixture.summary.sleep.stageSnapshot.wakeCycleEnd
        let wakeTime = ReadinessComputeSupport.freezeWakeTime(
            sleepEnd: sleepEnd, scoringDay: now, now: now, calendar: calendar
        )
        let todaysWorkouts = ReadinessComputeSupport.wakeCycleWorkouts(
            from: fixture.workouts, now: now, sleepEnd: sleepEnd, calendar: calendar
        )

        let recomputed = filtered.recalculatingReadiness(
            on: now,
            idealSleepDuration: fixture.idealSleepDuration,
            calendar: calendar,
            todaysWorkouts: todaysWorkouts,
            wakeTime: wakeTime,
            now: now,
            freezesRecordedReadiness: true,
            recordedReadinessContext: fixture.recordedReadinessContext
        )

        var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: recomputed.summary,
            trends: recomputed.trends,
            lastRefreshDate: now,
            permissionSelection: permission,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: fixture.idealSleepDuration,
            showSleepScore: true,
            now: now
        )
        snapshot.source = "phone"
        return snapshot
    }

    // MARK: - Watch path (manual replica of `WatchComputeCoordinator.compute`)

    /// Replicates `BodyWatch/WatchComputeCoordinator.swift`'s `compute(...)`
    /// step for step: splice deltas onto the seed's trends, overlay the
    /// summary with freshly-"fetched" values, replay Training Load over the
    /// overwritten daily-load array, `filteredWithoutReadinessRecompute` →
    /// `recalculatingReadiness` with the watch's deliberate deviations
    /// (`freezesRecordedReadiness: false`, `recordedReadinessContext: nil`,
    /// `wakeTime: nil`), then `makeSnapshot(seriesRangeOverride:perKindDataAsOf:)`.
    /// `delta*` values are sliced straight out of `fixture` (the fixture's own
    /// truth in `[windowStart, now]`) rather than fetched, per the file header.
    ///
    /// `seedSummary`/`seedTrainingLoadStartDay`/`seedTrainingLoadDailyLoads`
    /// are the inputs `makeComputeSeed` would have been called with AT
    /// `dataThrough` — for cases 1 and 3 that's just `fixture`'s own fields
    /// (`dataThrough == now`, so "as of now" and "as of dataThrough" coincide);
    /// case 4 passes a genuinely earlier snapshot of the same fixture (see
    /// `seedInputs(from:asOf:calendar:)`), since real `summary`/Training-Load
    /// seed inputs are captured live at publish time, not retroactively
    /// filled in from the future.
    private func watchSnapshot(
        fixture: Fixture,
        seedSummary: HealthSummarySnapshot,
        seedTrainingLoadStartDay: Date,
        seedTrainingLoadDailyLoads: [Double],
        dataThrough: Date, now: Date, calendar: Calendar
    ) -> (snapshot: WatchMetricsSnapshot, dataAsOf: [String: Date], seed: WatchComputeSeed) {
        let seed = HealthKitWorkoutStore.makeComputeSeed(
            summary: seedSummary,
            trends: fixture.trends,
            dataThrough: dataThrough,
            lastVitalsRefreshDate: dataThrough,
            trainingLoadStartDay: seedTrainingLoadStartDay,
            trainingLoadDailyLoads: seedTrainingLoadDailyLoads,
            trainingLoadDataThrough: dataThrough,
            expectedSourceIDsByKind: nil,
            settings: fixture.settings,
            publishedAt: dataThrough
        )

        let windowStart = WatchDeltaSplicer.deltaStart(dataThrough: seed.dataThrough, calendar: calendar)
        let windowStartDay = calendar.startOfDay(for: windowStart)

        func deltaSlice(_ series: HealthTrendSeries) -> WatchFetchOutcome<HealthTrendSeries> {
            .success(HealthTrendSeries(points: series.points.filter { $0.date >= windowStart && $0.date <= now }))
        }

        var trends = seed.trends
        trends.heartRate = WatchDeltaSplicer.splice(seedSeries: trends.heartRate, delta: deltaSlice(fixture.trends.heartRate), from: windowStart, calendar: calendar)
        trends.restingHeartRate = WatchDeltaSplicer.splice(seedSeries: trends.restingHeartRate, delta: deltaSlice(fixture.trends.restingHeartRate), from: windowStart, calendar: calendar)
        trends.heartRateVariability = WatchDeltaSplicer.splice(seedSeries: trends.heartRateVariability, delta: deltaSlice(fixture.trends.heartRateVariability), from: windowStart, calendar: calendar)
        trends.respiratoryRate = WatchDeltaSplicer.splice(seedSeries: trends.respiratoryRate, delta: deltaSlice(fixture.trends.respiratoryRate), from: windowStart, calendar: calendar)
        trends.oxygenSaturation = WatchDeltaSplicer.splice(seedSeries: trends.oxygenSaturation, delta: deltaSlice(fixture.trends.oxygenSaturation), from: windowStart, calendar: calendar)
        trends.wristTemperature = WatchDeltaSplicer.splice(seedSeries: trends.wristTemperature, delta: deltaSlice(fixture.trends.wristTemperature), from: windowStart, calendar: calendar)

        let deltaNights = fixture.trends.sleepHistory.days.filter { calendar.startOfDay(for: $0.date) >= windowStartDay }
        trends.sleepHistory = WatchDeltaSplicer.spliceSleepHistory(seed: trends.sleepHistory, deltaNights: .success(deltaNights), from: windowStart, calendar: calendar)
        // Derive the delta sleep-DURATION series from the SPLICED history (not a
        // second independent fetch) — mirrors the coordinator's documented
        // reasoning: re-deriving wholesale would widen `trends.sleep` (a
        // readiness source series) beyond the seed's own window.
        trends.sleep = WatchDeltaSplicer.splice(seedSeries: seed.trends.sleep, delta: .success(trends.sleepHistory.durationSeries), from: windowStart, calendar: calendar)

        var summary = seed.summary
        // `latestQuantitySample` has NO date predicate on the coordinator's real
        // path — the absolute newest sample wins regardless of the delta
        // window — so these read the fixture's global latest point, not a
        // windowed slice.
        if let hr = fixture.trends.heartRate.points.max(by: { $0.date < $1.date }) {
            summary.heartRate = HealthMetricSummary(value: hr.value, measuredAt: hr.date)
        }
        if let rhr = fixture.trends.restingHeartRate.points.max(by: { $0.date < $1.date }) {
            summary.restingHeartRate = HealthMetricSummary(value: rhr.value, measuredAt: rhr.date)
        }
        if let hrv = fixture.trends.heartRateVariability.points.max(by: { $0.date < $1.date }) {
            summary.heartRateVariability = HealthMetricSummary(value: hrv.value, measuredAt: hrv.date)
        }
        // The night with the latest stage date among the delta nights — the
        // same pick `WatchDeltaFetcher.sleepDelta` makes.
        let latestNight = deltaNights.max { lhs, rhs in
            (lhs.summary.stageSnapshot.date ?? .distantPast) < (rhs.summary.stageSnapshot.date ?? .distantPast)
        }?.summary
        if let latestNight {
            summary.sleep = latestNight
        }

        let deltaWorkouts = fixture.workouts.filter { $0.startDate >= windowStart && $0.startDate <= now }
        let trainingLoad = Self.replayTrainingLoad(
            seed: seed, deltaWorkouts: deltaWorkouts, windowStart: windowStart, now: now, calendar: calendar
        )
        if let trainingLoad {
            let oldestSeededDay = seed.trends.trainingLoad.points.map(\.date).min() ?? calendar.startOfDay(for: windowStart)
            trends.trainingLoad = HealthTrendSeries(points: trainingLoad.points.filter { $0.date >= oldestSeededDay })
            summary.trainingLoad = HealthMetricSummary(value: trainingLoad.point(on: calendar.startOfDay(for: now))?.value)
        }

        let idealSleepDuration = TimeInterval(seed.settings.idealSleepDurationMinutes * 60)
        let sleepEnd = summary.sleep.stageSnapshot.wakeCycleEnd

        let recomputed = HealthDashboardSnapshot(summary: summary, trends: trends)
            .filteredWithoutReadinessRecompute(by: permission)
            .recalculatingReadiness(
                on: now,
                idealSleepDuration: idealSleepDuration,
                calendar: calendar,
                todaysWorkouts: ReadinessComputeSupport.wakeCycleWorkouts(
                    from: deltaWorkouts, now: now, sleepEnd: sleepEnd, calendar: calendar
                ),
                wakeTime: nil,
                now: now,
                // Deliberate deviations, exactly as `WatchComputeCoordinator`
                // documents them: the watch never freezes a morning record
                // (phone-authoritative) and never re-keys the seeded records
                // (nil context ⇒ never dropped).
                freezesRecordedReadiness: false,
                recordedReadinessContext: nil
            )

        let dataAsOf = Self.dataAsOf(
            heartRateSample: fixture.trends.heartRate.points.max(by: { $0.date < $1.date }).map { ($0.value, $0.date) },
            restingHeartRateSample: fixture.trends.restingHeartRate.points.max(by: { $0.date < $1.date }).map { ($0.value, $0.date) },
            heartRateVariabilitySample: fixture.trends.heartRateVariability.points.max(by: { $0.date < $1.date }).map { ($0.value, $0.date) },
            sleepSummary: recomputed.summary.sleep,
            now: now,
            replayedTrainingLoad: trainingLoad != nil
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
            seriesRangeOverride: { seed.seriesRanges[$0] },
            perKindDataAsOf: { dataAsOf[$0] }
        )
        snapshot.source = "watch"
        return (snapshot, dataAsOf, seed)
    }

    /// `WatchComputeCoordinator.trainingLoadSeries` (private to that file),
    /// reimplemented here: the seeded dense daily-load array (extended to
    /// `now` with zero-filled rest days), with the delta window's slots
    /// overwritten from the watch's own workouts, replayed through the shared
    /// EWA. `nil` exactly when the coordinator's would be: no seeded loads.
    private static func replayTrainingLoad(
        seed: WatchComputeSeed, deltaWorkouts: [WorkoutSummary], windowStart: Date, now: Date, calendar: Calendar
    ) -> HealthTrendSeries? {
        guard let startDay = seed.trainingLoadStartDay,
              let loads = seed.trainingLoadDailyLoads,
              !loads.isEmpty else {
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

    /// `WatchComputeCoordinator.dataAsOf` (private to that file), reimplemented:
    /// the anti-laundering watermark map — only kinds genuinely re-read this
    /// run appear. Wrist temperature is deliberately absent (see the file
    /// header and `testDeltaNewerThanSeedAdoptsFreshDataWithHonestWatermarks`).
    private static func dataAsOf(
        heartRateSample: (value: Double, measuredAt: Date)?,
        restingHeartRateSample: (value: Double, measuredAt: Date)?,
        heartRateVariabilitySample: (value: Double, measuredAt: Date)?,
        sleepSummary: SleepSummary,
        now: Date,
        replayedTrainingLoad: Bool
    ) -> [String: Date] {
        var map: [String: Date] = [:]
        if let heartRateSample {
            map[WatchMetricKindKey.heartRate] = heartRateSample.measuredAt
        }
        if let restingHeartRateSample {
            map[WatchMetricKindKey.restingHeartRate] = restingHeartRateSample.measuredAt
        }
        if let heartRateVariabilitySample {
            map[WatchMetricKindKey.heartRateVariability] = heartRateVariabilitySample.measuredAt
        }
        if sleepSummary.asOf(now) != nil, let nightEnd = sleepSummary.stageSnapshot.dateInterval?.end {
            map[WatchMetricKindKey.sleep] = nightEnd
        }
        // Coverage semantics, mirroring the coordinator: a replay that ran over
        // a SUCCESSFUL workout query is stamped with the query's window end
        // (`now`) even when the window held no workouts — a confirmed rest day
        // decays the EWA and must be adoptable by the merge.
        if replayedTrainingLoad {
            map[WatchMetricKindKey.trainingLoad] = now
        }
        // Mirroring the coordinator's all-inputs-fresh rule: readiness is
        // stamped with the query window's end only when EVERY
        // permission-eligible input query succeeded. This fixture hands the
        // watch path fully-successful resolved data by construction, so the
        // only contingent input here is the Training Load replay.
        if replayedTrainingLoad {
            map[WatchMetricKindKey.readiness] = now
        }
        return map
    }

    private static func temperatureUnitPreference(for settings: WatchComputeSettings) -> BodyValueFormat.TemperatureUnitPreference {
        settings.followsSystemUnits
            ? BodyValueFormat.TemperatureUnitPreference.systemValue(locale: .current)
            : BodyValueFormat.TemperatureUnitPreference.storedValue(from: settings.selectedTemperatureUnitRaw)
    }

    /// Reconstructs the `summary`/Training-Load seed inputs as they genuinely
    /// were `asOf` an earlier instant, from the same fixture's underlying
    /// trend/workout truth — for case 4, where the seed was built 2 days
    /// before `now`. Mirrors `HealthKitWorkoutStore.publishWatchSnapshot`:
    /// `summary` is always a LIVE capture (never retroactively "filled in"),
    /// and the Training Load dense array's own start day slides with its own
    /// anchor, so this recomputes both from scratch at `asOf` rather than
    /// truncating the `now`-anchored fixture versions.
    private func seedInputs(
        from fixture: Fixture, asOf dataThrough: Date, calendar: Calendar
    ) throws -> (summary: HealthSummarySnapshot, trainingLoadStartDay: Date, trainingLoadDailyLoads: [Double]) {
        let dataThroughDay = calendar.startOfDay(for: dataThrough)
        var summary = fixture.summary
        summary.heartRate = HealthMetricSummary(value: fixture.trends.heartRate.point(on: dataThroughDay)?.value)
        summary.restingHeartRate = HealthMetricSummary(value: fixture.trends.restingHeartRate.point(on: dataThroughDay)?.value)
        summary.heartRateVariability = HealthMetricSummary(value: fixture.trends.heartRateVariability.point(on: dataThroughDay)?.value)
        summary.respiratoryRate = HealthMetricSummary(value: fixture.trends.respiratoryRate.point(on: dataThroughDay)?.value)
        summary.oxygenSaturation = HealthMetricSummary(value: fixture.trends.oxygenSaturation.point(on: dataThroughDay)?.value)
        summary.wristTemperature = HealthMetricSummary(value: fixture.trends.wristTemperature.point(on: dataThroughDay)?.value)
        summary.sleep = fixture.trends.sleepHistory.summary(on: dataThroughDay, calendar: calendar)?.summary ?? SleepSummary(duration: nil)

        let trainingLoadStartDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -407, to: dataThroughDay))
        let dailyLoadValues = try XCTUnwrap(TrainingLoadCalculator.dailyLoadValues(
            from: fixture.workouts, startDate: trainingLoadStartDay, endDate: dataThroughDay, calendar: calendar
        ))
        summary.trainingLoad = HealthMetricSummary(value: dailyLoadValues.loads.last)
        return (summary, trainingLoadStartDay, dailyLoadValues.loads)
    }

    // MARK: - Assertions

    /// Per-metric equality across every field the plan calls out, for all
    /// seven dashboard kinds. `excluding` skips kinds with a documented
    /// deliberate deviation for the case at hand (e.g. the wrist-temperature
    /// headline lag when the seed's `dataThrough` is stale relative to `now` —
    /// see `testDeltaNewerThanSeedAdoptsFreshDataWithHonestWatermarks`).
    ///
    /// `accuracy` (default 0, i.e. bit-exact) loosens the Double comparisons
    /// only: when `dataThrough` is stale, Training Load's dense daily-load
    /// array is reconstructed with a start day anchored to the STALE
    /// `dataThrough` (mirroring `WatchComputeCoordinator`'s real replay) —
    /// genuinely more leading warm-up days feed the acute/chronic EWA than
    /// the phone's own directly-computed window, so the two converge to the
    /// same ratio rather than reproducing identical float bits. A tight
    /// tolerance (≪ the 2-decimal display rounding) still catches any real
    /// divergence while absorbing that inherent floating-point residue.
    private func assertMetricsMatch(
        _ phone: WatchMetricsSnapshot, _ watch: WatchMetricsSnapshot,
        excluding: Set<String> = [],
        accuracy: Double = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        func assertDoublesMatch(_ lhs: Double, _ rhs: Double, _ message: String) {
            if accuracy > 0 {
                XCTAssertEqual(lhs, rhs, accuracy: accuracy, message, file: file, line: line)
            } else {
                XCTAssertEqual(lhs, rhs, message, file: file, line: line)
            }
        }
        func assertOptionalDoublesMatch(_ lhs: Double?, _ rhs: Double?, _ message: String) {
            switch (lhs, rhs) {
            case (nil, nil):
                return
            case let (l?, r?):
                assertDoublesMatch(l, r, message)
            default:
                XCTFail("\(message): \(String(describing: lhs)) is not equal to \(String(describing: rhs))", file: file, line: line)
            }
        }
        func assertWeeklyMatches(_ lhs: [Double?]?, _ rhs: [Double?]?, _ message: String) {
            guard let lhs, let rhs else {
                XCTAssertEqual(lhs == nil, rhs == nil, message, file: file, line: line)
                return
            }
            guard lhs.count == rhs.count else {
                XCTFail("\(message).count: \(lhs.count) is not equal to \(rhs.count)", file: file, line: line)
                return
            }
            for (l, r) in zip(lhs, rhs) {
                assertOptionalDoublesMatch(l, r, message)
            }
        }

        for kind in WatchMetricKindKey.displayOrder where !excluding.contains(kind) {
            guard let phoneMetric = phone.metric(forKind: kind) else {
                XCTFail("Phone snapshot missing metric \(kind)", file: file, line: line)
                continue
            }
            guard let watchMetric = watch.metric(forKind: kind) else {
                XCTFail("Watch snapshot missing metric \(kind)", file: file, line: line)
                continue
            }
            XCTAssertEqual(phoneMetric.displayValue, watchMetric.displayValue, "\(kind).displayValue", file: file, line: line)
            XCTAssertEqual(phoneMetric.unit, watchMetric.unit, "\(kind).unit", file: file, line: line)
            XCTAssertEqual(phoneMetric.score, watchMetric.score, "\(kind).score", file: file, line: line)
            assertDoublesMatch(phoneMetric.fillFraction, watchMetric.fillFraction, "\(kind).fillFraction")
            assertOptionalDoublesMatch(phoneMetric.rawValue, watchMetric.rawValue, "\(kind).rawValue")
            assertOptionalDoublesMatch(phoneMetric.rangeMin, watchMetric.rangeMin, "\(kind).rangeMin")
            assertOptionalDoublesMatch(phoneMetric.rangeMax, watchMetric.rangeMax, "\(kind).rangeMax")
            assertWeeklyMatches(phoneMetric.weekly, watchMetric.weekly, "\(kind).weekly")
            XCTAssertEqual(phoneMetric.tint, watchMetric.tint, "\(kind).tint", file: file, line: line)
            XCTAssertEqual(phoneMetric.statusBand, watchMetric.statusBand, "\(kind).statusBand", file: file, line: line)
            XCTAssertEqual(phoneMetric.levelMin, watchMetric.levelMin, "\(kind).levelMin", file: file, line: line)
            XCTAssertEqual(phoneMetric.levelMax, watchMetric.levelMax, "\(kind).levelMax", file: file, line: line)
        }
    }

    // MARK: - Case 1: exact parity (folds in trimmed-sleep equivalence)

    /// The core proof: identical data in ⇒ identical metrics out. The watch
    /// side is built from `HealthKitWorkoutStore.makeComputeSeed` — which ships
    /// the TRIMMED sleep history (`SleepHistorySnapshot.watchComputeTrimmed`) —
    /// against the phone's UNTRIMMED fixture, so passing this also proves the
    /// trimmed-sleep equivalence the plan calls out (Phase 1's own equivalence
    /// test covers the trim in isolation; this proves it holds through the
    /// WHOLE pipeline).
    func testExactParityWhenTheWatchSeesIdenticalData() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar)

        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar)
        let (watch, _, _) = watchSnapshot(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar
        )

        assertMetricsMatch(phone, watch)

        // Wrist temperature: the watch's SUMMARY headline is carried from the
        // seed unconditionally (`WatchComputeCoordinator` never overlays a
        // fetched reading onto it — only the TREND series is spliced). Parity
        // holds here only because `dataThrough == now` in this fixture (the
        // seed isn't stale yet); `testDeltaNewerThanSeedAdoptsFreshDataWithHonestWatermarks`
        // demonstrates the documented headline-lag once `now` moves past
        // `dataThrough`. `assertMetricsMatch` above already proved the TREND
        // (`weekly`) is identical; this is just making that explicit.
        let phoneWristTemp = try XCTUnwrap(phone.metric(forKind: WatchMetricKindKey.wristTemperature))
        let watchWristTemp = try XCTUnwrap(watch.metric(forKind: WatchMetricKindKey.wristTemperature))
        XCTAssertEqual(phoneWristTemp.weekly, watchWristTemp.weekly)
    }

    // MARK: - Case 3: DST transition inside the delta window

    /// Same "delta newer than the seed" shape as Case 4 below (a genuinely
    /// STALE seed the delta must overwrite) — deliberately, NOT a
    /// `dataThrough == now` build like Case 1: when the seed and the delta
    /// both come from the identical instant, the splice re-inserts exactly
    /// what it removed and passes REGARDLESS of what `deltaStart` computes —
    /// window-independent, and not actually proof the DST-crossing window
    /// spliced correctly. Making the seed 2 days stale (spanning the
    /// spring-forward) means a broken/mis-windowed splice would leave gaps or
    /// stale points in `.weekly` and feed wrong inputs to Training
    /// Load/readiness — genuinely observable by `assertMetricsMatch`.
    /// `deltaStart`'s own calendar-day-vs-fixed-48h math across this exact
    /// transition is locked precisely in
    /// `WatchDeltaSplicerTests.testDeltaStartAcrossDSTTransitionUsesCalendarDaysNotFixedSeconds`;
    /// this proves the whole pipeline still reaches full parity once real
    /// splicing happens across that window.
    func testParityHoldsAcrossADSTTransitionInTheDeltaWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // US spring-forward 2026 falls on March 8; the delta window
        // (dataThrough's day − 2 calendar days) spans March 7 → March 9.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 10)))
        let dataThrough = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
        let fixture = try makeFixture(anchor: now, calendar: calendar)
        let seededInputs = try seedInputs(from: fixture, asOf: dataThrough, calendar: calendar)

        let phone = phoneSnapshot(fixture: fixture, now: now, calendar: calendar)
        let (watch, _, _) = watchSnapshot(
            fixture: fixture,
            seedSummary: seededInputs.summary,
            seedTrainingLoadStartDay: seededInputs.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: seededInputs.trainingLoadDailyLoads,
            dataThrough: dataThrough, now: now, calendar: calendar
        )

        // Wrist temperature carries its SUMMARY headline from the seed
        // unconditionally (never overlaid by the delta) — the same
        // documented deviation Case 4 demonstrates explicitly — so it's
        // excluded from the blanket sweep here rather than re-proven.
        //
        // Training Load's dense daily-load array is reconstructed with a
        // start day anchored 2 days earlier (the stale `dataThrough`) than
        // the phone's own directly-computed window — genuinely more EWA
        // warm-up days feed the replay, so the acute/chronic ratio converges
        // to the same value rather than reproducing identical float bits
        // (confirmed: without a tolerance, `trainingLoad.fillFraction`/
        // `.rawValue`/`.weekly` differ at the 9th significant digit — nothing
        // else does). A 1e-6 tolerance is ~5000× tighter than the 2-decimal
        // display rounding, so it still catches any real divergence.
        assertMetricsMatch(phone, watch, excluding: [WatchMetricKindKey.wristTemperature], accuracy: 1e-6)
    }

    // MARK: - Case 4: delta newer than the seed

    /// The seed's `dataThrough` is 2 days stale relative to `now`; the delta
    /// window still reaches `now`, so it knows about data the seed does not.
    /// Asserts the watch result reflects the newer data and that
    /// `WatchComputeMerge.mergingComputed` adopts it with the real watermark
    /// (never `now`) — and makes the wrist-temperature headline deviation
    /// concrete: the summary headline stays at the seed's stale value while
    /// the trend series picks up the fresh point.
    func testDeltaNewerThanSeedAdoptsFreshDataWithHonestWatermarks() throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let dataThrough = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
        let fixture = try makeFixture(anchor: now, calendar: calendar)
        let seededInputs = try seedInputs(from: fixture, asOf: dataThrough, calendar: calendar)

        let (watch, dataAsOf, seed) = watchSnapshot(
            fixture: fixture,
            seedSummary: seededInputs.summary,
            seedTrainingLoadStartDay: seededInputs.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: seededInputs.trainingLoadDailyLoads,
            dataThrough: dataThrough, now: now, calendar: calendar
        )

        let nowDay = calendar.startOfDay(for: now)
        let trueHeartRateToday = try XCTUnwrap(fixture.trends.heartRate.point(on: nowDay)?.value)
        let watchHeartRate = try XCTUnwrap(watch.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(watchHeartRate.rawValue, trueHeartRateToday, "the watch's own delta re-read must reflect data newer than the seed")

        let heartRateAsOf = try XCTUnwrap(dataAsOf[WatchMetricKindKey.heartRate])
        XCTAssertGreaterThan(heartRateAsOf, dataThrough, "the watermark must be the fresh sample's own date, not the stale seed's dataThrough")
        XCTAssertEqual(heartRateAsOf, nowDay)

        // `mergingComputed`: a "current" displayed snapshot is what the phone
        // pushed at `dataThrough` (uniform stamps at that date); the fresher
        // watch compute must win and carry the REAL watermark forward, never
        // `now`, while leaving the phone's publication line untouched.
        let current = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: seed.summary,
            trends: seed.trends,
            lastRefreshDate: dataThrough,
            permissionSelection: permission,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: fixture.idealSleepDuration,
            showSleepScore: true,
            now: dataThrough
        )
        let merged = WatchComputeMerge.mergingComputed(
            WatchComputeResult(
                snapshot: watch,
                dataAsOf: dataAsOf,
                // Mirrors the coordinator: the wrist-temperature SERIES query
                // succeeded, so its chart rides the chart-only channel while
                // the headline stays phone-sourced.
                chartDataAsOf: [WatchMetricKindKey.wristTemperature: now],
                coverage: now,
                generation: 1
            ),
            into: current
        )

        XCTAssertEqual(merged.generatedAt, current.generatedAt, "the phone's publication line must never be advanced by a watch compute")
        XCTAssertEqual(merged.lastRefreshDate, current.lastRefreshDate)
        let mergedHeartRate = try XCTUnwrap(merged.metric(forKind: WatchMetricKindKey.heartRate))
        XCTAssertEqual(mergedHeartRate.rawValue, trueHeartRateToday)
        XCTAssertEqual(mergedHeartRate.computedAt, heartRateAsOf, "adopted stamp must be the real watermark, never `now`")
        XCTAssertEqual(mergedHeartRate.liveUpdatedAt, heartRateAsOf)

        // Wrist temperature: the documented headline deviation, made concrete.
        // The summary headline is still the SEED's (stale, `dataThrough`-day)
        // value — never overlaid — while the trend's last (today's) weekly
        // point reflects the fresh delta-spliced reading.
        let dataThroughDay = calendar.startOfDay(for: dataThrough)
        let staleWristTemp = try XCTUnwrap(fixture.trends.wristTemperature.point(on: dataThroughDay)?.value)
        let freshWristTemp = try XCTUnwrap(fixture.trends.wristTemperature.point(on: nowDay)?.value)
        XCTAssertNotEqual(staleWristTemp, freshWristTemp, "fixture must give the headline-lag assertion something real to distinguish")
        let watchWristTemp = try XCTUnwrap(watch.metric(forKind: WatchMetricKindKey.wristTemperature))
        XCTAssertEqual(watchWristTemp.rawValue, staleWristTemp, "the watch never overlays a fresh reading onto the wrist-temperature HEADLINE")
        XCTAssertEqual(watchWristTemp.weekly?.last ?? nil, freshWristTemp, "but the TREND series is spliced with fresh data")
        XCTAssertNil(dataAsOf[WatchMetricKindKey.wristTemperature], "wrist temperature is deliberately absent from the anti-laundering map")

        // …and the chart-only channel is what carries that fresh trend to the
        // CARD: the merged wrist-temperature metric keeps the phone's headline
        // and stamps but adopts the recomputed weekly series.
        let mergedWristTemp = try XCTUnwrap(merged.metric(forKind: WatchMetricKindKey.wristTemperature))
        XCTAssertEqual(mergedWristTemp.weekly ?? nil, watchWristTemp.weekly ?? nil, "the freshly spliced trend must reach the merged card")
        XCTAssertEqual(mergedWristTemp.weekly?.last ?? nil, freshWristTemp)
        XCTAssertNil(mergedWristTemp.liveUpdatedAt, "chart adoption makes no provenance claim")
    }
}
