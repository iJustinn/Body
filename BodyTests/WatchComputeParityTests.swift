//
//  WatchComputeParityTests.swift
//  BodyTests
//
//  The on-watch realtime compute plan's core proof (Phase 5): the phone path
//  and the watch path produce IDENTICAL metrics when they see the same data,
//  and the same Sleep Debt the iPhone card shows for the nights the watch charts.
//  The watch side runs the REAL `WatchComputeAssembly.assemble` — the same
//  function `WatchComputeCoordinator` calls after its fetch — so there is no
//  replica of the assembly order left here to drift.
//
//  What this test still does NOT exercise, and why:
//  * The impure half of the coordinator (`WatchComputeSeedStore.load`, the
//    actor's in-flight coalescing) is watchOS-only and stays out; the window
//    gate it consults, `WatchComputeAssembly.windowDecision`, is covered by
//    `WatchComputeAssemblyWindowTests`.
//  * The real fetch layer (`BodyHealthSourceResolver` source resolution,
//    `BodyHealthQuantityFetch`/`BodySleepFetch`/`BodyWorkoutFetch` HealthKit
//    queries, `BodyWorkoutEffortFetcher` effort lookups) is not exercised —
//    this test hands the assembly a `WatchComputeDelta` built from fixture
//    data (what a successful, permission-granted, source-resolved fetch would
//    have returned). Source-resolution strictness and HealthKit failure paths
//    are covered by `BodyHealthSourceResolverTests` and
//    `WatchDeltaSplicerTests`; workouts here carry an explicit `effortLevel`
//    rather than one resolved from a saved HealthKit sample.
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
        var recordedStressContext: String
    }

    /// 365 days of vitals trends, ~70 nights of sleep history (multi-segment
    /// nights with leading/interior/trailing awake time in nights 8–15, which
    /// straddle the seed's `sleepSegmentDayCount` (15) collapse boundary), and
    /// workouts spanning the full 408-slot Training Load lookback — everything
    /// `HealthKitWorkoutStore.makeComputeSeed` needs to build a realistic seed,
    /// and everything the phone's own dashboard recompute needs to score
    /// Readiness. `anchor` is both "today" and the instant the fixture's data
    /// extends through.
    ///
    /// `hardensSleepDebt` swaps in the Sleep Debt fixture instead: 111 nights
    /// (`sleepDebtNight`), so the seed's trim really cuts the history and the
    /// card's 30 night model learns a need for every compared night, plus one
    /// heavier workout 5 days back so some Training Load ratios clear 1.0.
    private func makeFixture(anchor: Date, calendar: Calendar, hardensSleepDebt: Bool = false) throws -> Fixture {
        let anchorDay = calendar.startOfDay(for: anchor)
        let idealSleepDuration: TimeInterval = 8 * 3_600

        var trends = HealthTrendSnapshot.empty
        trends.heartRate = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 64, amplitude: 6)
        trends.restingHeartRate = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 56, amplitude: 4)
        trends.heartRateVariability = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 52, amplitude: 10)
        trends.respiratoryRate = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 15, amplitude: 1.2)
        trends.oxygenSaturation = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 97, amplitude: 1.0)
        trends.wristTemperature = dailySeries(dayCount: 365, anchor: anchor, calendar: calendar, baseline: 36.2, amplitude: 0.4)
        trends.heartRateRanges = rangeSeries(around: trends.heartRate, spread: 18, anchor: anchor, calendar: calendar)
        trends.heartRateVariabilityRanges = rangeSeries(around: trends.heartRateVariability, spread: 25, anchor: anchor, calendar: calendar)
        // The day's running totals: a month is plenty, the watch reads only
        // the trailing week and the seed trims them away entirely.
        trends.steps = dailySeries(dayCount: 30, anchor: anchor, calendar: calendar, baseline: 8_400, amplitude: 2_600)
        trends.activeEnergy = dailySeries(dayCount: 30, anchor: anchor, calendar: calendar, baseline: 520, amplitude: 180)
        trends.restingEnergy = dailySeries(dayCount: 30, anchor: anchor, calendar: calendar, baseline: 1_640, amplitude: 40)
        let recordedStressContext = "fixture-stress-context"
        stressFixture(into: &trends, anchor: anchor, calendar: calendar)
        trends.recordedStressContext = recordedStressContext

        var nights: [SleepDaySummary] = []
        for offset in 0...(hardensSleepDebt ? Self.sleepDebtNightCount - 1 : 70) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: anchorDay) else { continue }
            nights.append(hardensSleepDebt
                ? sleepDebtNight(on: day, ageInDays: offset, calendar: calendar)
                : sleepNight(on: day, ageInDays: offset, calendar: calendar))
        }
        trends.sleepHistory = SleepHistorySnapshot(days: nights)
        // Mirrors the phone's own invariant (documented in
        // `WatchComputeCoordinator`): the sleep duration series is DERIVED from
        // the history, never a separately-tracked series.
        trends.sleep = trends.sleepHistory.durationSeries

        let trainingLoadStartDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -407, to: anchorDay))
        var workouts = workoutsFixture(startDay: trainingLoadStartDay, anchor: anchor, calendar: calendar)
        if hardensSleepDebt {
            let heavyDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: anchorDay))
            workouts.append(WorkoutSummary(
                type: .running,
                startDate: heavyDay.addingTimeInterval(17 * 3_600),
                duration: 60 * 60,
                effortLevel: 7
            ))
        }
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
            activeEnergy: HealthMetricSummary(value: trends.activeEnergy.point(on: anchorDay)?.value),
            restingEnergy: HealthMetricSummary(value: trends.restingEnergy.point(on: anchorDay)?.value),
            exerciseMinutes: HealthMetricSummary(value: nil),
            trainingLoad: HealthMetricSummary(value: trends.trainingLoad.point(on: anchorDay)?.value),
            wristTemperature: HealthMetricSummary(value: trends.wristTemperature.point(on: anchorDay)?.value),
            timeInDaylight: HealthMetricSummary(value: nil),
            steps: HealthMetricSummary(value: trends.steps.point(on: anchorDay)?.value)
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
            recordedReadinessContext: recordedContext,
            recordedStressContext: recordedStressContext
        )
    }

    /// Stress's inputs: 80 recorded days behind today (past the seed's 60 day
    /// trim, so the trim is really exercised) carrying the quiet heart rate
    /// and RMSSD baselines and the week's ranges, plus today's intraday reads
    /// up to `anchor`: heart rate in every window from midnight, a few SDNN
    /// and RMSSD readings, and Stress's 15 minute movement mask with two
    /// windows of steps and one of active energy over the per window
    /// thresholds. The fixture's workout an hour before `anchor` masks its
    /// windows too, apart from those movement windows.
    private func stressFixture(into trends: inout HealthTrendSnapshot, anchor: Date, calendar: Calendar) {
        let anchorDay = calendar.startOfDay(for: anchor)
        trends.recordedStressDays = (1...80).compactMap { age -> StressDaySummary? in
            guard let day = calendar.date(byAdding: .day, value: -age, to: anchorDay) else { return nil }
            let average = 30 + (age * 7) % 40
            return StressDaySummary(
                date: day,
                averageScore: average,
                minutesByBand: [.low: 240, .medium: 120],
                scoredWindowCount: 40,
                hrvCoveredWindowCount: 12,
                quietHRMedian: 60 + Double(age % 5),
                rmssdDailyMedian: 34 + Double(age % 4),
                minScore: max(average - 20, 0),
                maxScore: min(average + 30, 100),
                activityMinutes: 30
            )
        }
        .sorted { $0.date < $1.date }

        // Absolute 15 minute steps from midnight, the stress grid's own rule,
        // so a DST day lines up too.
        let elapsedWindows = Int(anchor.timeIntervalSince(anchorDay) / 900)
        trends.heartRateDaySamples = HealthTrendSeries(points: (0..<elapsedWindows).flatMap { index -> [HealthTrendDataPoint] in
            let windowStart = anchorDay.addingTimeInterval(Double(index) * 900)
            let value = 58 + Double(index % 9) * 3
            return [
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(60), value: value),
                HealthTrendDataPoint(date: windowStart.addingTimeInterval(420), value: value + 2)
            ]
        })
        trends.heartRateVariabilityDaySamples = HealthTrendSeries(points: [2.0, 5.0, 8.0].map {
            HealthTrendDataPoint(date: anchorDay.addingTimeInterval($0 * 3_600), value: 40 + $0)
        })
        trends.heartbeatRMSSDDaySamples = HealthTrendSeries(points: [3.0, 6.0].map {
            HealthTrendDataPoint(date: anchorDay.addingTimeInterval($0 * 3_600 + 600), value: 30 + $0)
        })
        // 15 minute buckets dated at their window's start, the shape the phone's
        // Stress input load and the watch's `stressMovementSeries` both read.
        trends.stressStepsDaySamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: anchorDay.addingTimeInterval(7 * 3_600), value: 400),
            HealthTrendDataPoint(date: anchorDay.addingTimeInterval(7 * 3_600 + 900), value: 400)
        ])
        trends.stressActiveEnergyDaySamples = HealthTrendSeries(points: [
            HealthTrendDataPoint(date: anchorDay.addingTimeInterval(6 * 3_600), value: 20)
        ])
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

    /// Age (days before `anchor`) of the one day whose average has no range:
    /// inside the charted week, so a nil capsule slot has to line up on both
    /// sides.
    private static let rangelessAgeDay = 3

    /// The daily min/max capsules the phone's one collection query yields
    /// beside `series`' averages: an asymmetric spread around each day's
    /// average (so low and high can't be swapped unnoticed), with the average
    /// itself as `averageValue`. `rangelessAgeDay` has none.
    private func rangeSeries(
        around series: HealthTrendSeries, spread: Double, anchor: Date, calendar: Calendar
    ) -> HealthTrendRangeSeries {
        let anchorDay = calendar.startOfDay(for: anchor)
        return HealthTrendRangeSeries(points: series.points.compactMap { point in
            let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: point.date), to: anchorDay).day ?? 0
            guard age != Self.rangelessAgeDay else { return nil }
            let swing = spread * (1 + Double(age % 5) / 10)
            return HealthTrendRangeDataPoint(
                date: point.date,
                lowValue: point.value - swing * 0.4,
                highValue: point.value + swing * 0.6,
                averageValue: point.value
            )
        })
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

    /// Nights in the Sleep Debt fixture: past the seed's 86 night trim and the
    /// 102 days the card's 30 night model reads.
    private static let sleepDebtNightCount = 111

    /// One Sleep Debt fixture night, `ageInDays` before the anchor. The main
    /// session (22:00 to about 07:00) has an awake stretch INSIDE it, 20 to 50
    /// minutes, so once the seed collapses a night 15 or more days old to one
    /// segment spanning the session, a duration derived from the segments
    /// would differ from the stored one the debt reads. Asleep time drifts
    /// around the 8 hour goal, with one 6 hour night 3 days back, and sleep
    /// HRV around 58 ms drops 2 to 3 spreads low on a few nights, so both the
    /// learned need and the HRV addition move the compared nights.
    private func sleepDebtNight(on day: Date, ageInDays age: Int, calendar: Calendar) -> SleepDaySummary {
        let dayStart = calendar.startOfDay(for: day)
        var asleepHours = 8.2 + 0.3 * sin(Double(age) / 3.5) + 0.25 * sin(Double(age) / 1.7)
        if age == 3 {
            asleepHours = 6
        }
        let asleep = asleepHours * 3_600
        let leadingAwakeStart = dayStart.addingTimeInterval(-2 * 3_600)
        let leadingAwakeEnd = leadingAwakeStart.addingTimeInterval(10 * 60)
        let coreEnd = leadingAwakeEnd.addingTimeInterval(asleep * 0.45)
        let interiorAwakeEnd = coreEnd.addingTimeInterval(TimeInterval(20 + (age % 4) * 10) * 60)
        let remEnd = interiorAwakeEnd.addingTimeInterval(asleep * 0.2)
        let deepEnd = remEnd.addingTimeInterval(asleep * 0.35)
        let snapshot = SleepStageSnapshot(date: dayStart, segments: [
            SleepStageSegment(stage: .awake, startDate: leadingAwakeStart, endDate: leadingAwakeEnd),
            SleepStageSegment(stage: .core, startDate: leadingAwakeEnd, endDate: coreEnd),
            SleepStageSegment(stage: .awake, startDate: coreEnd, endDate: interiorAwakeEnd),
            SleepStageSegment(stage: .rem, startDate: interiorAwakeEnd, endDate: remEnd),
            SleepStageSegment(stage: .deep, startDate: remEnd, endDate: deepEnd)
        ])
        var heartRateVariability = 58 + 3 * sin(Double(age) / 3.1)
        if [2, 9, 16].contains(age) {
            heartRateVariability = 42
        } else if [5, 12].contains(age) {
            heartRateVariability = 49
        }
        let vitals = SleepVitalsSummary(
            heartRate: 56, heartRateVariability: heartRateVariability, respiratoryRate: 14.8,
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
    private func phoneSnapshot(
        fixture: Fixture,
        now: Date,
        calendar: Calendar,
        permission: BodyHealthPermissionSelection = .defaultValue
    ) -> WatchMetricsSnapshot {
        let rawSnapshot = HealthDashboardSnapshot(summary: fixture.summary, trends: fixture.trends)
        let filtered = rawSnapshot.filteredWithoutReadinessRecompute(by: permission)

        let sleepEnd = fixture.summary.sleep.stageSnapshot.wakeCycleEnd
        let wakeTime = ReadinessComputeSupport.freezeWakeTime(
            sleepEnd: sleepEnd, scoringDay: now, now: now, calendar: calendar
        )
        let todaysWorkouts = ReadinessComputeSupport.wakeCycleWorkouts(
            from: fixture.workouts, now: now, sleepEnd: sleepEnd, calendar: calendar
        )

        var recomputed = filtered.recalculatingReadiness(
            on: now,
            idealSleepDuration: fixture.idealSleepDuration,
            calendar: calendar,
            todaysWorkouts: todaysWorkouts,
            wakeCycleStart: ReadinessComputeSupport.wakeCycleStart(now: now, sleepEnd: sleepEnd, calendar: calendar),
            wakeTime: wakeTime,
            now: now,
            freezesRecordedReadiness: true,
            recordedReadinessContext: fixture.recordedReadinessContext
        )

        // Then Stress, as the refresh runs it after readiness (with the
        // records' own context and the whole stress window's workouts), and
        // the "Last 12 hours" `BodyCompanionPublisher` builds over the result.
        var stressTimeline: WatchStressTimeline?
        if permission.includes(.heart) {
            recomputed = recomputed.recalculatingStress(
                on: now,
                workouts: fixture.workouts,
                calendar: calendar,
                now: now,
                recordedStressContext: fixture.recordedStressContext
            )
            stressTimeline = WatchStressTimelineBuilder.make(
                dashboard: recomputed,
                workouts: fixture.workouts,
                now: now,
                calendar: calendar,
                computedAt: now
            )
        }

        var snapshot = WatchMetricsSnapshotBuilder.makeSnapshot(
            summary: recomputed.summary,
            trends: recomputed.trends,
            lastRefreshDate: now,
            permissionSelection: permission,
            temperatureUnitPreference: .celsius,
            idealSleepDuration: fixture.idealSleepDuration,
            showSleepScore: true,
            now: now,
            // What the publisher passes while Body Pro and the Sleep Debt
            // toggle are on.
            includesSleepDebt: true,
            stressTimeline: stressTimeline
        )
        snapshot.source = "phone"
        return snapshot
    }

    // MARK: - Watch path (the real `WatchComputeAssembly`)

    /// Builds the `WatchComputeDelta` a successful, permission-granted,
    /// source-resolved fetch would have returned for this fixture and hands it
    /// to the production `WatchComputeAssembly.assemble` — the same function
    /// `WatchComputeCoordinator` calls after its own fetch. Nothing about the
    /// assembly order is reimplemented here.
    ///
    /// `seedSummary`/`seedTrainingLoadStartDay`/`seedTrainingLoadDailyLoads`
    /// are the inputs `makeComputeSeed` would have been called with AT
    /// `dataThrough` — for cases 1 and 3 that's just `fixture`'s own fields
    /// (`dataThrough == now`, so "as of now" and "as of dataThrough" coincide);
    /// case 4 passes a genuinely earlier snapshot of the same fixture (see
    /// `seedInputs(from:asOf:calendar:)`), since real `summary`/Training-Load
    /// seed inputs are captured live at publish time, not retroactively
    /// filled in from the future.
    ///
    /// `mutateDelta` edits that delta before the assembly runs, for the cases
    /// where a query failed or a kind was carried.
    private func watchResult(
        fixture: Fixture,
        seedSummary: HealthSummarySnapshot,
        seedTrainingLoadStartDay: Date,
        seedTrainingLoadDailyLoads: [Double],
        seedEffortHints: [String: Double]? = nil,
        dataThrough: Date, now: Date, calendar: Calendar,
        permission: BodyHealthPermissionSelection = .defaultValue,
        mutateDelta: (inout WatchComputeDelta) -> Void = { _ in }
    ) throws -> (result: WatchComputeResult, seed: WatchComputeSeed) {
        let seed = HealthKitWorkoutStore.makeComputeSeed(
            summary: seedSummary,
            trends: fixture.trends,
            dataThrough: dataThrough,
            lastVitalsRefreshDate: dataThrough,
            trainingLoadStartDay: seedTrainingLoadStartDay,
            trainingLoadDailyLoads: seedTrainingLoadDailyLoads,
            trainingLoadDataThrough: dataThrough,
            trainingLoadEffortHints: seedEffortHints,
            expectedSourceIDsByKind: nil,
            settings: fixture.settings,
            publishedAt: dataThrough
        )

        let decision = WatchComputeAssembly.windowDecision(seed: seed, now: now, calendar: calendar)
        guard case .fetch(let windowStart) = decision else {
            XCTFail("The fixture's seed must be inside the compute window, got \(decision)")
            throw XCTSkip("no window")
        }
        let windowStartDay = calendar.startOfDay(for: windowStart)

        func deltaSlice(_ series: HealthTrendSeries) -> WatchFetchOutcome<HealthTrendSeries> {
            .success(HealthTrendSeries(points: series.points.filter { $0.date >= windowStart && $0.date <= now }))
        }
        func deltaRangeSlice(_ series: HealthTrendRangeSeries) -> WatchFetchOutcome<HealthTrendRangeSeries> {
            .success(HealthTrendRangeSeries(points: series.points.filter { $0.date >= windowStart && $0.date <= now }))
        }
        // `latestQuantitySample` has NO date predicate on the real fetch path —
        // the absolute newest sample wins regardless of the delta window — so
        // these read the fixture's global latest point, not a windowed slice.
        func latestSample(_ series: HealthTrendSeries) -> WatchDeltaSample? {
            series.points.max(by: { $0.date < $1.date }).map { WatchDeltaSample(value: $0.value, measuredAt: $0.date) }
        }

        let deltaNights = fixture.trends.sleepHistory.days.filter { calendar.startOfDay(for: $0.date) >= windowStartDay }
        var delta = WatchComputeDelta()
        delta.heartRateSeries = deltaSlice(fixture.trends.heartRate)
        delta.restingHeartRateSeries = deltaSlice(fixture.trends.restingHeartRate)
        delta.heartRateVariabilitySeries = deltaSlice(fixture.trends.heartRateVariability)
        delta.heartRateRanges = deltaRangeSlice(fixture.trends.heartRateRanges)
        delta.heartRateVariabilityRanges = deltaRangeSlice(fixture.trends.heartRateVariabilityRanges)
        delta.respiratoryRateSeries = deltaSlice(fixture.trends.respiratoryRate)
        delta.oxygenSaturationSeries = deltaSlice(fixture.trends.oxygenSaturation)
        delta.wristTemperatureSeries = deltaSlice(fixture.trends.wristTemperature)
        delta.sleepNights = .success(deltaNights)
        delta.workouts = .success(fixture.workouts.filter { $0.startDate >= windowStart && $0.startDate <= now })
        delta.heartRateSample = latestSample(fixture.trends.heartRate)
        delta.restingHeartRateSample = latestSample(fixture.trends.restingHeartRate)
        delta.heartRateVariabilitySample = latestSample(fixture.trends.heartRateVariability)
        // The night with the latest stage date among the delta nights — the
        // same pick `WatchDeltaFetcher.sleepDelta` makes.
        delta.latestNight = deltaNights.max { lhs, rhs in
            (lhs.summary.stageSnapshot.date ?? .distantPast) < (rhs.summary.stageSnapshot.date ?? .distantPast)
        }?.summary
        // Stress's intraday reads cover whole days from the one `now - 13h`
        // falls on (`WatchDeltaFetcher`'s Stress window).
        let stressWindowStart = calendar.startOfDay(for: now.addingTimeInterval(-WatchStressTimelineBuilder.span))
        func stressSlice(_ series: HealthTrendSeries) -> WatchFetchOutcome<HealthTrendSeries> {
            .success(HealthTrendSeries(points: series.points.filter { $0.date >= stressWindowStart && $0.date <= now }))
        }
        delta.stressHeartRateSamples = stressSlice(fixture.trends.heartRateDaySamples)
        delta.stressSDNNSamples = stressSlice(fixture.trends.heartRateVariabilityDaySamples)
        delta.stressRMSSDSamples = stressSlice(fixture.trends.heartbeatRMSSDDaySamples)
        delta.stressQuarterHourSteps = stressSlice(fixture.trends.stressStepsDaySamples)
        delta.stressQuarterHourActiveEnergy = stressSlice(fixture.trends.stressActiveEnergyDaySamples)
        // The day's running totals: a fixed trailing week ending today, the
        // window `WatchDeltaFetcher.weeklyTotalSeries` reads whatever the
        // delta window is (the seed carries nothing to splice onto).
        let totalsWeekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        func weekSlice(_ series: HealthTrendSeries) -> WatchFetchOutcome<HealthTrendSeries> {
            .success(HealthTrendSeries(points: series.points.filter { $0.date >= totalsWeekStart && $0.date <= now }))
        }
        delta.stepsWeek = weekSlice(fixture.trends.steps)
        delta.activeEnergyWeek = weekSlice(fixture.trends.activeEnergy)
        delta.restingEnergyWeek = weekSlice(fixture.trends.restingEnergy)
        mutateDelta(&delta)

        let result = try XCTUnwrap(WatchComputeAssembly.assemble(
            seed: seed,
            delta: delta,
            permission: permission,
            generation: 1,
            windowStart: windowStart,
            now: now,
            calendar: calendar
        ))
        return (result, seed)
    }

    /// `watchResult`'s snapshot and per-kind watermarks, for the cases that
    /// compare dashboard metrics.
    private func watchSnapshot(
        fixture: Fixture,
        seedSummary: HealthSummarySnapshot,
        seedTrainingLoadStartDay: Date,
        seedTrainingLoadDailyLoads: [Double],
        dataThrough: Date, now: Date, calendar: Calendar
    ) throws -> (snapshot: WatchMetricsSnapshot, dataAsOf: [String: Date], seed: WatchComputeSeed) {
        let (result, seed) = try watchResult(
            fixture: fixture,
            seedSummary: seedSummary,
            seedTrainingLoadStartDay: seedTrainingLoadStartDay,
            seedTrainingLoadDailyLoads: seedTrainingLoadDailyLoads,
            dataThrough: dataThrough, now: now, calendar: calendar
        )
        return (result.snapshot, result.dataAsOf, seed)
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
        summary.steps = HealthMetricSummary(value: fixture.trends.steps.point(on: dataThroughDay)?.value)
        summary.activeEnergy = HealthMetricSummary(value: fixture.trends.activeEnergy.point(on: dataThroughDay)?.value)
        summary.restingEnergy = HealthMetricSummary(value: fixture.trends.restingEnergy.point(on: dataThroughDay)?.value)
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
            // Fixture values carried through untouched (no arithmetic on
            // either side), so exact even under `accuracy`.
            XCTAssertEqual(phoneMetric.weeklyRanges, watchMetric.weeklyRanges, "\(kind).weeklyRanges", file: file, line: line)
            XCTAssertEqual(phoneMetric.tint, watchMetric.tint, "\(kind).tint", file: file, line: line)
            XCTAssertEqual(phoneMetric.statusBand, watchMetric.statusBand, "\(kind).statusBand", file: file, line: line)
            XCTAssertEqual(phoneMetric.levelMin, watchMetric.levelMin, "\(kind).levelMin", file: file, line: line)
            XCTAssertEqual(phoneMetric.levelMax, watchMetric.levelMax, "\(kind).levelMax", file: file, line: line)
        }
        // The Stress page's "Last 12 hours" is the same windows on both sides
        // (both paths stamp it with `now` here).
        if !excluding.contains(WatchMetricKindKey.stress) {
            XCTAssertEqual(phone.stressTimeline, watch.stressTimeline, "stressTimeline", file: file, line: line)
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
        let (watch, _, _) = try watchSnapshot(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar
        )

        assertMetricsMatch(phone, watch)

        // The drain REPORT has to match too, workout for workout: the watch
        // merge reconciles the two devices' reports by workout identity
        // (`WatchReadinessDrainReconciler`), so a report that differed for
        // identical data would double count or drop a workout's drain.
        let phoneDrain = try XCTUnwrap(phone.metric(forKind: WatchMetricKindKey.readiness)?.drain)
        let watchDrain = try XCTUnwrap(watch.metric(forKind: WatchMetricKindKey.readiness)?.drain)
        XCTAssertEqual(phoneDrain, watchDrain)
        XCTAssertEqual(phoneDrain.contributions.count, 1, "the fixture's one wake cycle workout")

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

        // Stress was compared for real: a scored average over a week with
        // ranges, and a timeline with scored and masked windows under sleep
        // and workout shading.
        let phoneStress = try XCTUnwrap(phone.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertTrue(phoneStress.hasValue)
        XCTAssertNotNil(phoneStress.statusBand)
        XCTAssertNotNil(phoneStress.weeklyRanges)
        let timeline = try XCTUnwrap(watch.stressTimeline)
        XCTAssertTrue(timeline.slots.contains { ($0 ?? -1) >= 0 })
        XCTAssertTrue(timeline.slots.contains(WatchStressTimeline.activityMarker))
        XCTAssertEqual(
            Set(timeline.context.map(\.kind)),
            [WatchStressContextBand.sleepKind, WatchStressContextBand.workoutKind]
        )
    }

    // MARK: - A rating the watch hasn't seen yet (the seed's effort hints)

    /// The iPhone has a rating for a workout the watch reads as unrated (made
    /// on the iPhone, by hand or by Auto-Apply, and not replicated yet). With
    /// the seed's effort hints the watch counts the iPhone's rating, so every
    /// metric and the drain report match the iPhone exactly; without them it
    /// counts the default effort and Training Load differs, the mismatch the
    /// hints exist to close. Built on case 1's fresh seed (`dataThrough ==
    /// now`): the watch never freezes readiness records, so a stale seed would
    /// drift Readiness for reasons that have nothing to do with the hints.
    func testSeedEffortHintsCountARatingTheWatchHasNotSeen() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar)
        // Today's wake cycle workout: it feeds Training Load's today slot and
        // the same-day drain.
        let rated = try XCTUnwrap(fixture.workouts.max { $0.startDate < $1.startDate })
        let ratedEffort = try XCTUnwrap(rated.effortLevel)
        XCTAssertNotEqual(ratedEffort, TrainingLoadCalculator.defaultEffortLevel)
        let readAsUnrated: (inout WatchComputeDelta) -> Void = { delta in
            guard case .success(let workouts) = delta.workouts else { return }
            delta.workouts = .success(workouts.map { $0.id == rated.id ? $0.replacingEffortLevel(nil) : $0 })
        }
        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar)

        let hinted = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            seedEffortHints: [rated.id.uuidString: ratedEffort],
            dataThrough: anchor, now: anchor, calendar: calendar,
            mutateDelta: readAsUnrated
        ).result.snapshot
        assertMetricsMatch(phone, hinted)
        XCTAssertEqual(
            try XCTUnwrap(phone.metric(forKind: WatchMetricKindKey.readiness)?.drain),
            try XCTUnwrap(hinted.metric(forKind: WatchMetricKindKey.readiness)?.drain)
        )

        let unhinted = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar,
            mutateDelta: readAsUnrated
        ).result.snapshot
        XCTAssertNotEqual(
            try XCTUnwrap(phone.metric(forKind: WatchMetricKindKey.trainingLoad)?.rawValue),
            try XCTUnwrap(unhinted.metric(forKind: WatchMetricKindKey.trainingLoad)?.rawValue)
        )
    }

    /// A rating the watch read itself beats a conflicting hint (it is the live
    /// read of the store holding the sample), and a hint only fills a workout
    /// the watch read as unrated.
    func testApplyingEffortHintsFillsOnlyUnratedWorkouts() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let unrated = WorkoutSummary(type: .running, startDate: start, duration: 1_800)
        let rated = WorkoutSummary(type: .running, startDate: start.addingTimeInterval(3_600), duration: 1_800, effortLevel: 8)
        let unhinted = WorkoutSummary(type: .cycling, startDate: start.addingTimeInterval(7_200), duration: 1_800)
        let hints = [unrated.id.uuidString: 6.0, rated.id.uuidString: 3.0]

        let applied = WatchComputeAssembly.applyingEffortHints([unrated, rated, unhinted], hints: hints)

        XCTAssertEqual(applied.map(\.effortLevel), [6, 8, nil])
        XCTAssertEqual(applied.map(\.id), [unrated.id, rated.id, unhinted.id])
        XCTAssertEqual(applied[0], unrated.replacingEffortLevel(6))
        XCTAssertEqual(WatchComputeAssembly.applyingEffortHints([unrated], hints: nil), [unrated])
    }

    // MARK: - The day's running totals (Steps, Active Energy, Resting Energy)

    /// The three cards are compared for real in `assertMetricsMatch` (they
    /// are in `displayOrder`); this makes the stamping explicit: a successful
    /// week read stamps the kind with the query window's end (coverage
    /// semantics, like `workoutMinutes`), carries a real total and a dense
    /// week, and a read that failed, or a permission that is off, leaves the
    /// kind out of `dataAsOf` so the merge never adopts what the builder
    /// still shows from the seed.
    func testDailyTotalsAreStampedOnlyWhenTheirWeekWasRead() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar)
        let totals = [WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy, WatchMetricKindKey.restingEnergy]

        func result(
            permission: BodyHealthPermissionSelection = .defaultValue,
            _ mutateDelta: @escaping (inout WatchComputeDelta) -> Void = { _ in }
        ) throws -> WatchComputeResult {
            try watchResult(
                fixture: fixture,
                seedSummary: fixture.summary,
                seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
                seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
                dataThrough: anchor, now: anchor, calendar: calendar,
                permission: permission,
                mutateDelta: mutateDelta
            ).result
        }

        // Every week read succeeded: all three stamped at `now`, each with
        // today's total and a 7 slot week matching the phone's.
        let fresh = try result()
        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar)
        for kind in totals {
            XCTAssertEqual(fresh.dataAsOf[kind], anchor, kind)
            let metric = try XCTUnwrap(fresh.snapshot.metric(forKind: kind), kind)
            XCTAssertTrue(metric.hasValue, kind)
            XCTAssertEqual(metric.weekly?.count, 7, kind)
            XCTAssertEqual(metric.weekly, phone.metric(forKind: kind)?.weekly, kind)
            XCTAssertEqual(metric.displayValue, phone.metric(forKind: kind)?.displayValue, kind)
        }
        XCTAssertEqual(fresh.snapshot.metric(forKind: WatchMetricKindKey.steps)?.unit, "")
        XCTAssertEqual(fresh.snapshot.metric(forKind: WatchMetricKindKey.activeEnergy)?.unit, "kcal")
        XCTAssertEqual(fresh.snapshot.metric(forKind: WatchMetricKindKey.restingEnergy)?.usesKilojoules, false)

        // One failed read leaves exactly that kind unstamped; the others are
        // untouched. Not a readiness or Stress input, so neither moves.
        let failedSteps = try result { $0.stepsWeek = .failure }
        XCTAssertNil(failedSteps.dataAsOf[WatchMetricKindKey.steps])
        XCTAssertEqual(failedSteps.dataAsOf[WatchMetricKindKey.activeEnergy], anchor)
        XCTAssertEqual(failedSteps.dataAsOf[WatchMetricKindKey.restingEnergy], anchor)
        XCTAssertEqual(failedSteps.dataAsOf[WatchMetricKindKey.readiness], fresh.dataAsOf[WatchMetricKindKey.readiness])
        XCTAssertEqual(failedSteps.dataAsOf[WatchMetricKindKey.stress], fresh.dataAsOf[WatchMetricKindKey.stress])
        XCTAssertTrue(failedSteps.readinessBlockers.isEmpty)
        // The seed carries no week for it, so the bars are blank; the headline
        // is whatever the seed's summary said, which the merge never adopts
        // because the kind is unstamped (`WatchComputeMergeTests`).
        XCTAssertEqual(
            failedSteps.snapshot.metric(forKind: WatchMetricKindKey.steps)?.weekly?.compactMap { $0 },
            []
        )

        // A successful read with nothing today still stamps (coverage), and
        // the card is blank: nothing counted yet.
        let emptyToday = try result { delta in
            if case .success(let week) = delta.restingEnergyWeek {
                delta.restingEnergyWeek = .success(HealthTrendSeries(
                    points: week.points.filter { !calendar.isDate($0.date, inSameDayAs: anchor) }
                ))
            }
        }
        XCTAssertEqual(emptyToday.dataAsOf[WatchMetricKindKey.restingEnergy], anchor)
        let restingToday = try XCTUnwrap(emptyToday.snapshot.metric(forKind: WatchMetricKindKey.restingEnergy))
        XCTAssertFalse(restingToday.hasValue)
        XCTAssertEqual(restingToday.weekly?.last ?? nil, nil)
        XCTAssertEqual(restingToday.weekly?.compactMap { $0 }.count, 6)

        // Permission off: the builder omits the card and nothing is stamped,
        // even though the delta still carries a successful read.
        var withoutMovement = BodyHealthPermissionSelection.defaultValue
        withoutMovement.enabledPermissions.remove(.steps)
        withoutMovement.enabledPermissions.remove(.energy)
        let hidden = try result(permission: withoutMovement)
        for kind in totals {
            XCTAssertNil(hidden.dataAsOf[kind], kind)
            XCTAssertNil(hidden.snapshot.metric(forKind: kind), kind)
        }
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
        let (watch, _, _) = try watchSnapshot(
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
        //
        // Stress is excluded for the stale seed itself: the seed's records
        // end at `dataThrough`, and the watch reads only the last 8 hours'
        // days, so the day between has no record on the watch (a gap in its
        // week and one less baseline day) until the next seed brings it.
        assertMetricsMatch(
            phone, watch,
            excluding: [WatchMetricKindKey.wristTemperature, WatchMetricKindKey.stress],
            accuracy: 1e-6
        )
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

        let (watch, dataAsOf, seed) = try watchSnapshot(
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

    // MARK: - Weekly ranges (the HR / HRV week charts' capsules)

    /// The watch computes the capsules from the seed's one trimmed week plus
    /// its own delta re-read, the phone from its full range series: on a seed
    /// 2 days stale, the last 2 days exist only in the delta, so equality
    /// here proves the splice, not just the seed.
    func testWeeklyRangesMatchThePhoneWithTheDeltaSplicedOverAStaleSeed() throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let dataThrough = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
        let fixture = try makeFixture(anchor: now, calendar: calendar)
        let seededInputs = try seedInputs(from: fixture, asOf: dataThrough, calendar: calendar)

        let phone = phoneSnapshot(fixture: fixture, now: now, calendar: calendar)
        let (result, seed) = try watchResult(
            fixture: fixture,
            seedSummary: seededInputs.summary,
            seedTrainingLoadStartDay: seededInputs.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: seededInputs.trainingLoadDailyLoads,
            dataThrough: dataThrough, now: now, calendar: calendar
        )

        XCTAssertEqual(seed.trends.heartRateRanges.points.map(\.date).max(), calendar.startOfDay(for: dataThrough))
        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability] {
            let phoneRanges = try XCTUnwrap(phone.metric(forKind: kind)?.weeklyRanges, kind)
            XCTAssertEqual(phoneRanges.count, 7, kind)
            XCTAssertNil(phoneRanges[6 - Self.rangelessAgeDay], "\(kind): the day without a range")
            XCTAssertNotNil(phoneRanges[5], kind)
            XCTAssertNotNil(phoneRanges[6], kind)
            XCTAssertEqual(result.snapshot.metric(forKind: kind)?.weeklyRanges, phoneRanges, kind)
        }
    }

    /// The range reads are display only: failed on a fresh seed, the seed's
    /// week still matches the phone, and readiness is stamped as usual.
    func testFailedRangeReadOnAFreshSeedCarriesTheSeedAndNeverBlocksReadiness() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar)

        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar)
        let (result, _) = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar,
            mutateDelta: { delta in
                delta.heartRateRanges = .failure
                delta.heartRateVariabilityRanges = .failure
            }
        )

        assertMetricsMatch(phone, result.snapshot)
        XCTAssertNotNil(phone.metric(forKind: WatchMetricKindKey.heartRate)?.weeklyRanges)
        XCTAssertEqual(result.readinessBlockers, [])
        XCTAssertEqual(result.dataAsOf[WatchMetricKindKey.readiness], anchor)
    }

    /// The accepted edge (`WatchComputeAssembly.assemble`): with the range
    /// read failed on a stale seed, the week keeps the seed's capsules, so the
    /// days after `dataThrough` have none under their fresh average points
    /// until the next compute or push.
    func testFailedRangeReadOnAStaleSeedKeepsOnlyTheSeedsCapsules() throws {
        let calendar = Calendar.bodyGregorian
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let dataThrough = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
        let fixture = try makeFixture(anchor: now, calendar: calendar)
        let seededInputs = try seedInputs(from: fixture, asOf: dataThrough, calendar: calendar)

        let phone = phoneSnapshot(fixture: fixture, now: now, calendar: calendar)
        let (result, _) = try watchResult(
            fixture: fixture,
            seedSummary: seededInputs.summary,
            seedTrainingLoadStartDay: seededInputs.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: seededInputs.trainingLoadDailyLoads,
            dataThrough: dataThrough, now: now, calendar: calendar,
            mutateDelta: { delta in
                delta.heartRateRanges = .failure
                delta.heartRateVariabilityRanges = .failure
            }
        )

        for kind in [WatchMetricKindKey.heartRate, WatchMetricKindKey.heartRateVariability] {
            let phoneRanges = try XCTUnwrap(phone.metric(forKind: kind)?.weeklyRanges, kind)
            let watchMetric = try XCTUnwrap(result.snapshot.metric(forKind: kind), kind)
            let watchRanges = try XCTUnwrap(watchMetric.weeklyRanges, kind)
            XCTAssertEqual(Array(watchRanges.prefix(5)), Array(phoneRanges.prefix(5)), "\(kind): the seed's days")
            XCTAssertEqual(Array(watchRanges.suffix(2)), [nil, nil], "\(kind): no capsule after dataThrough")
            XCTAssertNotNil(phoneRanges[5], kind)
            XCTAssertNotNil(phoneRanges[6], kind)
            XCTAssertNotNil(watchMetric.weekly?[5] ?? nil, "\(kind): the average was re-read")
            XCTAssertNotNil(watchMetric.weekly?[6] ?? nil, "\(kind): the average was re-read")
        }
        XCTAssertEqual(result.readinessBlockers, [])
    }

    // MARK: - Stress

    /// Coverage semantics: Stress (and its timeline, which rides the same
    /// watermark) is stamped only when every permitted input it scores with
    /// was re-read on the watch this run.
    func testStressIsStampedOnlyWhenEveryPermittedInputWasReRead() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar)
        func result(
            permission: BodyHealthPermissionSelection = .defaultValue,
            _ mutateDelta: (inout WatchComputeDelta) -> Void
        ) throws -> WatchComputeResult {
            try watchResult(
                fixture: fixture,
                seedSummary: fixture.summary,
                seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
                seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
                dataThrough: anchor, now: anchor, calendar: calendar,
                permission: permission,
                mutateDelta: mutateDelta
            ).result
        }
        func stressAsOf(
            permission: BodyHealthPermissionSelection = .defaultValue,
            _ mutateDelta: (inout WatchComputeDelta) -> Void
        ) throws -> Date? {
            try result(permission: permission, mutateDelta).dataAsOf[WatchMetricKindKey.stress]
        }

        XCTAssertEqual(try stressAsOf { _ in }, anchor)
        XCTAssertNil(try stressAsOf { $0.stressHeartRateSamples = .failure }, "the heart rate read failed")
        XCTAssertNil(try stressAsOf { $0.carriedKinds = [.heartRate] }, "heart rate carried: no source on this watch")
        XCTAssertNil(try stressAsOf { $0.stressSDNNSamples = .failure })
        XCTAssertNil(try stressAsOf { $0.carriedKinds = [.heartRateVariability] })
        XCTAssertNil(try stressAsOf { $0.stressRMSSDSamples = .failure }, "the beat to beat read failed or timed out")
        XCTAssertNil(try stressAsOf { $0.stressQuarterHourSteps = .failure }, "steps permitted but not read")
        XCTAssertNil(try stressAsOf { $0.stressQuarterHourActiveEnergy = .failure }, "energy permitted but not read")
        XCTAssertNil(
            try stressAsOf { delta in
                delta.sleepNights = .failure
                delta.latestNight = nil
            },
            "the sleep read failed: the rest context is the seed's"
        )
        XCTAssertNil(try stressAsOf { $0.carriedKinds = [.sleep] }, "sleep carried")
        XCTAssertNil(try stressAsOf { $0.workouts = .failure }, "the workout mask is missing")

        // A permission that's off is not an input: the phone scores without it too.
        let maskOff = BodyHealthPermissionSelection.defaultValue
            .setting(.steps, isEnabled: false)
            .setting(.energy, isEnabled: false)
        XCTAssertEqual(
            try stressAsOf(permission: maskOff) { delta in
                delta.stressQuarterHourSteps = .failure
                delta.stressQuarterHourActiveEnergy = .failure
            },
            anchor
        )
        XCTAssertEqual(
            try stressAsOf(permission: BodyHealthPermissionSelection.defaultValue.setting(.sleep, isEnabled: false)) { delta in
                delta.sleepNights = .failure
                delta.latestNight = nil
            },
            anchor
        )

        // No Heart: no Stress at all, and nothing to stamp.
        let heartOff = try result(permission: BodyHealthPermissionSelection.defaultValue.setting(.heart, isEnabled: false)) { _ in }
        XCTAssertNil(heartOff.dataAsOf[WatchMetricKindKey.stress])
        XCTAssertNil(heartOff.snapshot.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertNil(heartOff.snapshot.stressTimeline)
    }

    /// Without steps and active energy the movement mask is the workouts
    /// alone, on both sides: the phone's permission filter drops the series,
    /// and the watch never reads them.
    func testStressMatchesThePhoneWithTheMovementPermissionsOff() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar)
        let maskOff = BodyHealthPermissionSelection.defaultValue
            .setting(.steps, isEnabled: false)
            .setting(.energy, isEnabled: false)

        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar, permission: maskOff)
        let (result, _) = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar,
            permission: maskOff,
            mutateDelta: { delta in
                delta.stressQuarterHourSteps = .failure
                delta.stressQuarterHourActiveEnergy = .failure
            }
        )

        // The Steps, Active Energy and Resting Energy cards ride these same
        // permissions, so both sides omit them here.
        assertMetricsMatch(
            phone, result.snapshot,
            excluding: [WatchMetricKindKey.steps, WatchMetricKindKey.activeEnergy, WatchMetricKindKey.restingEnergy]
        )
        for kind in WatchMetricKindKey.dailyTotalKinds {
            XCTAssertNil(phone.metric(forKind: kind), kind)
            XCTAssertNil(result.snapshot.metric(forKind: kind), kind)
        }
        XCTAssertNotEqual(
            result.snapshot.stressTimeline?.slots,
            phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar).stressTimeline?.slots,
            "the case must differ from the one with the movement windows masked"
        )
    }

    /// An uncalibrated baseline (no recorded days to learn quiet heart rate
    /// from) scores nothing: the watch stamps that honestly, and the blank card
    /// is still never adopted over the phone's value.
    func testUncalibratedStressIsStampedButBlankAndNeverReplacesAValue() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let calibrated = try makeFixture(anchor: anchor, calendar: calendar)
        var fixture = calibrated
        fixture.trends.recordedStressDays = []

        let (result, _) = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar
        )

        XCTAssertEqual(result.dataAsOf[WatchMetricKindKey.stress], anchor)
        let stress = try XCTUnwrap(result.snapshot.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertFalse(stress.hasValue)
        XCTAssertNil(stress.statusBand)
        XCTAssertNil(result.snapshot.stressTimeline, "every uncalibrated window is a gap")

        let phone = phoneSnapshot(fixture: calibrated, now: anchor.addingTimeInterval(-1_800), calendar: calendar)
        let merged = WatchComputeMerge.mergingComputed(result, into: phone)
        XCTAssertEqual(merged.metric(forKind: WatchMetricKindKey.stress), phone.metric(forKind: WatchMetricKindKey.stress))
        XCTAssertTrue(merged.metric(forKind: WatchMetricKindKey.stress)?.hasValue == true)
        XCTAssertEqual(merged.stressTimeline, phone.stressTimeline)
    }

    // MARK: - Sleep Debt: watch = phone = the iPhone card's last 14 nights

    /// The iPhone Sleep Debt card's model over the inputs the phone publish
    /// reads (the permission-filtered dashboard, as the store holds it, with
    /// its frozen nights): the default 30 night `make`, whose last 14 nights
    /// the watch must show.
    private func cardSleepDebt(
        fixture: Fixture,
        now: Date,
        calendar: Calendar,
        permission: BodyHealthPermissionSelection = .defaultValue
    ) -> SleepDebtChartModel {
        let filtered = HealthDashboardSnapshot(summary: fixture.summary, trends: fixture.trends)
            .filteredWithoutReadinessRecompute(by: permission)
        return SleepDebtChartModel.make(
            entries: SleepDebtChartModel.entries(
                sleepHistory: filtered.trends.sleepHistory,
                currentDaySummary: filtered.summary.sleep,
                trainingLoad: filtered.trends.trainingLoad,
                today: now,
                calendar: calendar
            ),
            sleepGoal: fixture.idealSleepDuration,
            records: filtered.trends.recordedSleepDebt,
            calendar: calendar
        )
    }

    /// Night for night and the headline: the phone builder's debt and the
    /// watch compute's both equal the card's last 14 nights. `computedAt` is
    /// provenance, which differs by design.
    private func assertSleepDebtsMatch(
        phone: WatchMetricsSnapshot,
        watch: WatchMetricsSnapshot,
        card: SleepDebtChartModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let phoneDebt = try XCTUnwrap(phone.sleepDebt, "phone debt", file: file, line: line)
        let watchDebt = try XCTUnwrap(watch.sleepDebt, "watch debt", file: file, line: line)
        let cardNights = card.nights.suffix(SleepDebtChartModel.watchNightCount).map {
            WatchSleepDebt.Night(day: $0.day, debt: $0.debtAfterNight, isRecorded: $0.isRecorded)
        }

        XCTAssertEqual(cardNights.count, SleepDebtChartModel.watchNightCount, file: file, line: line)
        XCTAssertEqual(phoneDebt.nights, cardNights, "phone builder vs the card", file: file, line: line)
        XCTAssertEqual(watchDebt.nights, cardNights, "watch compute vs the card", file: file, line: line)
        XCTAssertEqual(phoneDebt.debt, card.debt, "phone headline", file: file, line: line)
        XCTAssertEqual(watchDebt.debt, card.debt, "watch headline", file: file, line: line)
    }

    /// The watch computes Sleep Debt from the TRIMMED seed (86 nights, the
    /// older ones collapsed) plus its own delta, the phone from its full
    /// history, and the iPhone card from that history with 30 nights: all
    /// three must agree on the 14 nights the watch charts.
    func testSleepDebtMatchesThePhoneAndTheCardsLastFourteenNights() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let anchorDay = calendar.startOfDay(for: anchor)
        let fixture = try makeFixture(anchor: anchor, calendar: calendar, hardensSleepDebt: true)

        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar)
        let (result, seed) = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar
        )
        let card = cardSleepDebt(fixture: fixture, now: anchor, calendar: calendar)

        try assertSleepDebtsMatch(phone: phone, watch: result.snapshot, card: card)
        XCTAssertEqual(result.sleepDebtAsOf, anchor, "every input was re-read: the compute's coverage")
        XCTAssertEqual(result.snapshot.sleepDebt?.nights.last?.day, anchorDay)

        // The fixture makes that comparison mean something. The trim really
        // cut the history the watch read…
        XCTAssertEqual(seed.trends.sleepHistory.days.count, WatchComputeSeed.sleepHistoryDayCount)
        XCTAssertLessThan(seed.trends.sleepHistory.days.count, fixture.trends.sleepHistory.days.count)
        // …and a duration derived from a collapsed night's segments would
        // differ from the stored one the debt reads.
        XCTAssertTrue(seed.trends.sleepHistory.days.contains { day in
            let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: day.date), to: anchorDay).day ?? 0
            guard age >= WatchComputeSeed.sleepSegmentDayCount, let duration = day.summary.duration else { return false }
            return day.summary.stageSnapshot.segments.count == 1
                && abs(day.summary.stageSnapshot.mergedAsleepDuration - duration) >= 20 * 60
        })
        // Every compared night learned its need, the windows behind them
        // carry Training Load and HRV additions, and no debt sits at a clamp
        // that could hide a different sum.
        let compared = card.nights.suffix(SleepDebtChartModel.watchNightCount)
        let windows = card.nights.suffix(SleepDebtChartModel.watchNightCount + SleepDebtChartModel.windowNightCount - 1)
        XCTAssertTrue(compared.allSatisfy(\.isNeedLearned))
        XCTAssertTrue(windows.contains { $0.trainingAdjustment > 0 })
        XCTAssertTrue(windows.contains { $0.hrvAdjustment > 0 })
        let debts = compared.compactMap(\.debtAfterNight)
        XCTAssertEqual(debts.count, SleepDebtChartModel.watchNightCount)
        XCTAssertTrue(debts.allSatisfy { $0 > 0 && $0 < SleepDebtChartModel.maximumDebt })
        XCTAssertGreaterThan(Set(debts).count, 1)

        // The wider seed history must not move a dashboard metric either. Case
        // 1's 71 nights fit inside the trim; these 111 don't, so this is the
        // case that would catch a readiness or sleep score reading past it.
        assertMetricsMatch(phone, result.snapshot)
    }

    /// The phone's frozen nights ride the seed: every night of the card's
    /// model except yesterday's and today's is recorded with a need 10 minutes
    /// above and a debt 10 minutes off what the history gives, so a side that
    /// ignored the records would differ on the frozen nights it emits and on
    /// the two live nights, whose windows sum the frozen gaps. Yesterday is
    /// left live as after a partial refresh, today as always.
    func testSleepDebtMatchesWithThePhonesFrozenNights() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let anchorDay = calendar.startOfDay(for: anchor)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: anchorDay))
        var fixture = try makeFixture(anchor: anchor, calendar: calendar, hardensSleepDebt: true)
        let liveCard = cardSleepDebt(fixture: fixture, now: anchor, calendar: calendar)
        fixture.trends.recordedSleepDebt = liveCard.nights
            .filter { $0.day < yesterday }
            .compactMap { night -> SleepDebtRecord? in
                var perturbed = night
                perturbed.needDuration += 10 * 60
                perturbed.debtAfterNight = night.debtAfterNight.map { $0 + 10 * 60 }
                return SleepDebtRecord(night: perturbed, capturedAt: night.day.addingTimeInterval(36 * 3_600))
            }
        fixture.trends.recordedSleepDebtContext = "fixture-sleep-debt-context"
        XCTAssertEqual(fixture.trends.recordedSleepDebt.count, SleepDebtChartModel.selectableNightCount - 2)

        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar)
        let (result, seed) = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar
        )
        let card = cardSleepDebt(fixture: fixture, now: anchor, calendar: calendar)

        try assertSleepDebtsMatch(phone: phone, watch: result.snapshot, card: card)
        XCTAssertEqual(result.snapshot.sleepDebt?.nights.last?.day, anchorDay)

        // The seed carried the frozen nights the watch reads…
        XCTAssertEqual(
            seed.trends.recordedSleepDebt.count,
            SleepDebtChartModel.watchNightCount + SleepDebtChartModel.windowNightCount - 2
        )
        // …the charted frozen nights are the records, verbatim…
        let compared = Array(card.nights.suffix(SleepDebtChartModel.watchNightCount))
        let liveCompared = Array(liveCard.nights.suffix(SleepDebtChartModel.watchNightCount))
        for (frozen, live) in zip(compared, liveCompared).dropLast(2) {
            XCTAssertEqual(frozen.needDuration, live.needDuration + 10 * 60)
            XCTAssertEqual(try XCTUnwrap(frozen.debtAfterNight), try XCTUnwrap(live.debtAfterNight) + 10 * 60, accuracy: 0.001)
        }
        // …and the two live nights moved with the frozen gaps, not the
        // history's, with no debt at a clamp that could hide a different sum.
        for (frozen, live) in zip(compared, liveCompared).suffix(2) {
            XCTAssertEqual(frozen.needDuration, live.needDuration, "a live night keeps its own need")
            XCTAssertNotEqual(frozen.debtAfterNight, live.debtAfterNight, "a live night sums the frozen gaps")
        }
        let debts = compared.compactMap(\.debtAfterNight)
        XCTAssertEqual(debts.count, SleepDebtChartModel.watchNightCount)
        XCTAssertTrue(debts.allSatisfy { $0 > 0 && $0 < SleepDebtChartModel.maximumDebt })
    }

    /// With Workouts off, both sides drop Training Load from the needs (the
    /// filtered dashboard has none), and the watch doesn't wait on a replay it
    /// can't run.
    func testSleepDebtMatchesWithWorkoutsOff() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar, hardensSleepDebt: true)
        let workoutsOff = BodyHealthPermissionSelection.defaultValue.setting(.workouts, isEnabled: false)

        let phone = phoneSnapshot(fixture: fixture, now: anchor, calendar: calendar, permission: workoutsOff)
        let (result, _) = try watchResult(
            fixture: fixture,
            seedSummary: fixture.summary,
            seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
            seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
            dataThrough: anchor, now: anchor, calendar: calendar,
            permission: workoutsOff,
            // The fetcher never runs the workout query without the permission.
            mutateDelta: { $0.workouts = .failure }
        )
        let card = cardSleepDebt(fixture: fixture, now: anchor, calendar: calendar, permission: workoutsOff)

        // Debt only: this harness's phone path drains readiness from the
        // fixture's workouts regardless of the permission.
        try assertSleepDebtsMatch(phone: phone, watch: result.snapshot, card: card)
        XCTAssertEqual(result.sleepDebtAsOf, anchor)
        XCTAssertTrue(card.nights.allSatisfy { $0.trainingAdjustment == 0 })
        XCTAssertNotEqual(
            card.nights.suffix(SleepDebtChartModel.watchNightCount).map(\.needDuration),
            cardSleepDebt(fixture: fixture, now: anchor, calendar: calendar)
                .nights.suffix(SleepDebtChartModel.watchNightCount).map(\.needDuration),
            "the case must differ from the Workouts on one"
        )
    }

    /// The anti-laundering rule for the debt: stamped only when every input
    /// it reads was re-read on the watch this run.
    func testSleepDebtIsStampedOnlyWhenEveryInputWasReRead() throws {
        let calendar = Calendar.bodyGregorian
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: 10)))
        let fixture = try makeFixture(anchor: anchor, calendar: calendar, hardensSleepDebt: true)
        func sleepDebtAsOf(
            permission: BodyHealthPermissionSelection = .defaultValue,
            _ mutateDelta: (inout WatchComputeDelta) -> Void
        ) throws -> Date? {
            try watchResult(
                fixture: fixture,
                seedSummary: fixture.summary,
                seedTrainingLoadStartDay: fixture.trainingLoadStartDay,
                seedTrainingLoadDailyLoads: fixture.trainingLoadDailyLoads,
                dataThrough: anchor, now: anchor, calendar: calendar,
                permission: permission,
                mutateDelta: mutateDelta
            ).result.sleepDebtAsOf
        }

        XCTAssertEqual(try sleepDebtAsOf { _ in }, anchor)
        XCTAssertNil(
            try sleepDebtAsOf { delta in
                delta.sleepNights = .failure
                delta.latestNight = nil
            },
            "the sleep query failed: the history is the seed's"
        )
        XCTAssertNil(
            try sleepDebtAsOf { delta in
                delta.sleepNights = .failure
                delta.latestNight = nil
                delta.carriedKinds = [.sleep]
            },
            "sleep carried: this watch holds no source for it"
        )
        XCTAssertNil(
            try sleepDebtAsOf { $0.carriedKinds = [.sleep] },
            "a carried kind never counts as re-read, whatever its outcome says"
        )
        XCTAssertNil(
            try sleepDebtAsOf { $0.workouts = .failure },
            "Workouts permitted but the Training Load replay didn't run: the ratios are the seed's"
        )
        XCTAssertNil(
            try sleepDebtAsOf(permission: BodyHealthPermissionSelection.defaultValue.setting(.sleep, isEnabled: false)) { _ in },
            "no Sleep permission, no debt"
        )
    }
}
