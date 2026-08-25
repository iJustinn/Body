//
//  StressScoreCalculator.swift
//  Body
//

import Foundation

/// The two heart-rate-variability measures Stress can score against. A value is only
/// ever compared with a calibrated baseline of the *same* kind — SDNN and RMSSD live on
/// different scales, so mixing them would read as a large swing that never happened.
enum HRVKind: String, Codable, Equatable, CaseIterable {
    case sdnn
    case rmssd
}

/// Everything one calendar day of stress scoring needs, in plain value types the store
/// can assemble from cached day samples (no store or HealthKit internals).
struct StressDayInput: Equatable {
    /// Any moment inside the calendar day being scored.
    var date: Date
    var heartRateSamples: [HealthTrendDataPoint]
    var sdnnSamples: [HealthTrendDataPoint]
    var rmssdSamples: [HealthTrendDataPoint]
    /// Hourly buckets (bucket start date, total for that hour) — coarse movement mask;
    /// workouts provide the fine one.
    var hourlySteps: [HealthTrendDataPoint]
    var hourlyActiveEnergy: [HealthTrendDataPoint]
    /// Workout spans, built with `WorkoutSummary.effectiveEndDate` (see `workoutIntervals(for:)`).
    var workoutIntervals: [DateInterval]
    /// The day's main sleep session, used only for rest context.
    var sleepInterval: DateInterval?

    init(
        date: Date,
        heartRateSamples: [HealthTrendDataPoint] = [],
        sdnnSamples: [HealthTrendDataPoint] = [],
        rmssdSamples: [HealthTrendDataPoint] = [],
        hourlySteps: [HealthTrendDataPoint] = [],
        hourlyActiveEnergy: [HealthTrendDataPoint] = [],
        workoutIntervals: [DateInterval] = [],
        sleepInterval: DateInterval? = nil
    ) {
        self.date = date
        self.heartRateSamples = heartRateSamples
        self.sdnnSamples = sdnnSamples
        self.rmssdSamples = rmssdSamples
        self.hourlySteps = hourlySteps
        self.hourlyActiveEnergy = hourlyActiveEnergy
        self.workoutIntervals = workoutIntervals
        self.sleepInterval = sleepInterval
    }

    func samples(for kind: HRVKind) -> [HealthTrendDataPoint] {
        switch kind {
        case .sdnn:
            return sdnnSamples
        case .rmssd:
            return rmssdSamples
        }
    }

    /// `duration` excludes paused time, so `startDate + duration` can land before the
    /// workout really ended — the activity mask must use HealthKit's authoritative end.
    static func workoutIntervals(for workouts: [WorkoutSummary]) -> [DateInterval] {
        workouts.compactMap { workout in
            let end = workout.effectiveEndDate
            guard end > workout.startDate else {
                return nil
            }

            return DateInterval(start: workout.startDate, end: end)
        }
    }
}

/// The personal baselines a day is scored against. Quiet HR is required; the HRV
/// baselines are optional modulators, one per kind.
struct StressBaselines: Equatable {
    var quietHeartRate: ReadinessScoreCalculator.Baseline?
    var hrvByKind: [HRVKind: ReadinessScoreCalculator.Baseline]

    init(
        quietHeartRate: ReadinessScoreCalculator.Baseline? = nil,
        hrvByKind: [HRVKind: ReadinessScoreCalculator.Baseline] = [:]
    ) {
        self.quietHeartRate = quietHeartRate
        self.hrvByKind = hrvByKind
    }

    /// Stress can score at all only once quiet HR is calibrated. An uncalibrated RMSSD
    /// baseline must never surface as "calibrating" while SDNN already serves.
    var isCalibrated: Bool {
        quietHeartRate != nil
    }

    func baseline(for kind: HRVKind) -> ReadinessScoreCalculator.Baseline? {
        hrvByKind[kind]
    }
}

/// Baseline inputs reduced once and reused across every day of a series (mirrors
/// `ReadinessScoreCalculator`'s daily-series context: the per-day aggregation is the
/// expensive part, and it does not depend on the day being scored).
struct StressDailySeriesContext {
    private let calendar: Calendar
    private let quietHeartRateDailyMedians: [ReadinessScoreCalculator.DailyValue]
    private let hrvDailyMediansByKind: [HRVKind: [ReadinessScoreCalculator.DailyValue]]

    init(
        quietHeartRateDailyMedians: [ReadinessScoreCalculator.DailyValue],
        sdnnSamples: [HealthTrendDataPoint],
        rmssdSamples: [HealthTrendDataPoint],
        calendar: Calendar = .bodyGregorian
    ) {
        self.calendar = calendar
        self.quietHeartRateDailyMedians = StressScoreCalculator.dailyMedians(
            of: quietHeartRateDailyMedians,
            calendar: calendar
        )
        hrvDailyMediansByKind = [
            .sdnn: StressScoreCalculator.dailyMedians(of: sdnnSamples, calendar: calendar),
            .rmssd: StressScoreCalculator.dailyMedians(of: rmssdSamples, calendar: calendar)
        ]
    }

    func baselines(for date: Date) -> StressBaselines {
        let quietHeartRate = ReadinessScoreCalculator.robustBaseline(
            for: date,
            values: quietHeartRateDailyMedians,
            floor: StressScoreCalculator.Tuning.quietHeartRateSpreadFloor,
            calendar: calendar
        )
        var hrvByKind: [HRVKind: ReadinessScoreCalculator.Baseline] = [:]
        for kind in HRVKind.allCases {
            guard let values = hrvDailyMediansByKind[kind], !values.isEmpty else {
                continue
            }

            hrvByKind[kind] = ReadinessScoreCalculator.robustBaseline(
                for: date,
                values: values,
                floor: StressScoreCalculator.Tuning.hrvSpreadFloor(for: kind),
                calendar: calendar
            )
        }

        return StressBaselines(quietHeartRate: quietHeartRate, hrvByKind: hrvByKind)
    }
}

enum StressScoreCalculator {
    /// Initial values, calibrated against the fixtures in `StressScoreCalculatorTests`.
    /// None of these are settled — the tests are the sensitivity harness for tuning them.
    enum Tuning {
        static let windowDuration: TimeInterval = 15 * 60

        /// Logistic `100 / (1 + exp(-k · (z − z0)))` over the quiet-HR z-score.
        /// At z = 0 this reads ~18 (Rest); at z = +3 it reads ~82 (High).
        static let heartRateLogisticSteepness = 1.0
        static let heartRateLogisticMidpoint = 1.5
        /// MAD floor in bpm, so a freakishly steady history can't make every window extreme.
        static let quietHeartRateSpreadFloor = 3.0

        static let hrvLogisticSteepness = 1.0
        static let hrvLogisticMidpoint = 1.5

        static func hrvSpreadFloor(for kind: HRVKind) -> Double {
            switch kind {
            case .sdnn: return 5.0
            case .rmssd: return 5.0
            }
        }

        /// How far an HRV sample can sit from a window and still influence it, and how
        /// much of the gap between the HR and HRV scores it closes at zero distance.
        static let hrvReach: TimeInterval = 45 * 60
        static let hrvBlendWeight = 0.35

        /// Recovery HR stays elevated after a session, so the mask runs past the workout.
        static let workoutMaskTail: TimeInterval = 30 * 60
        static let maskStepsPerHour = 200.0
        static let maskActiveEnergyKilocaloriesPerHour = 25.0

        /// Minimum coverage for a window to be scored at all — one stray sample (or a
        /// watch put on mid-window) must read as a gap, never as a zero.
        static let minimumHeartRateSampleCount = 2
        static let minimumHeartRateSampleSpan: TimeInterval = 5 * 60
    }

    // MARK: - Grid

    /// 15-minute grid over the calendar day, built by repeated +900 s from the day's start
    /// so a DST day yields 92 or 100 windows instead of a hard-coded 96. Today clamps at
    /// `now`; a past day ends at `dayEnd − 1` because a sample exactly at next midnight
    /// belongs to the next day (same rule as `ReadinessDayTimeline.make`).
    static func windowIntervals(
        for date: Date,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> [DateInterval] {
        guard let dayInterval = calendar.dateInterval(of: .day, for: date) else {
            return []
        }

        let isToday = calendar.isDate(date, inSameDayAs: now)
        let limit = isToday ? min(now, dayInterval.end - 1) : dayInterval.end - 1
        guard limit > dayInterval.start else {
            return []
        }

        var intervals: [DateInterval] = []
        var cursor = dayInterval.start
        while cursor < limit {
            let end = min(cursor.addingTimeInterval(Tuning.windowDuration), limit)
            intervals.append(DateInterval(start: cursor, end: end))
            cursor = cursor.addingTimeInterval(Tuning.windowDuration)
        }

        return intervals
    }

    // MARK: - Windows

    private struct WindowScan {
        var interval: DateInterval
        var isActivity: Bool
        var isAsleep: Bool
        /// nil when the window fails the minimum-coverage rule.
        var medianHeartRate: Double?
    }

    static func windows(
        for input: StressDayInput,
        baselines: StressBaselines,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> [StressWindow] {
        let scans = windowScans(for: input, calendar: calendar, now: now)

        // No quiet-HR baseline yet: the metric is still building its baseline, so nothing
        // is scored (rather than scored against a stand-in that would be wrong).
        guard let heartRateBaseline = baselines.quietHeartRate else {
            return scans.map { StressWindow(interval: $0.interval, state: .unscored) }
        }

        let hrvSamplesByKind = calibratedHRVSamples(input: input, baselines: baselines, calendar: calendar)

        return scans.map { scan in
            if scan.isActivity {
                return StressWindow(interval: scan.interval, state: .activity)
            }
            guard let medianHeartRate = scan.medianHeartRate else {
                return StressWindow(interval: scan.interval, state: .unscored)
            }

            let heartRateScore = logistic(
                ReadinessScoreCalculator.robustZScore(value: medianHeartRate, baseline: heartRateBaseline),
                steepness: Tuning.heartRateLogisticSteepness,
                midpoint: Tuning.heartRateLogisticMidpoint
            )

            guard let influence = hrvInfluence(
                for: scan.interval,
                samplesByKind: hrvSamplesByKind,
                baselines: baselines
            ) else {
                return StressWindow(
                    interval: scan.interval,
                    state: .scored(score: clampedScore(heartRateScore), hrOnly: true)
                )
            }

            // Blending toward the HRV score (instead of switching to it) keeps the curve
            // continuous as a sample drifts out of reach.
            let blended = heartRateScore
                + Tuning.hrvBlendWeight * influence.proximity * (influence.score - heartRateScore)

            return StressWindow(
                interval: scan.interval,
                state: .scored(score: clampedScore(blended), hrOnly: false)
            )
        }
    }

    /// The day's quiet-HR estimand: the median of unmasked, awake window-median heart
    /// rates. Computable without any baseline, so it both bootstraps the baseline from
    /// history and accumulates into the recorded days.
    static func quietHeartRateDailyMedian(
        for input: StressDayInput,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> Double? {
        let values = windowScans(for: input, calendar: calendar, now: now)
            .compactMap { scan -> Double? in
                guard !scan.isActivity, !scan.isAsleep else {
                    return nil
                }

                return scan.medianHeartRate
            }

        return median(values)
    }

    private static func windowScans(
        for input: StressDayInput,
        calendar: Calendar,
        now: Date
    ) -> [WindowScan] {
        let intervals = windowIntervals(for: input.date, calendar: calendar, now: now)
        guard !intervals.isEmpty else {
            return []
        }

        let maskIntervals = input.workoutIntervals.map {
            DateInterval(start: $0.start, end: $0.end.addingTimeInterval(Tuning.workoutMaskTail))
        }
        let stepsByHour = hourlyBuckets(input.hourlySteps, calendar: calendar)
        let energyByHour = hourlyBuckets(input.hourlyActiveEnergy, calendar: calendar)
        let heartRateSamples = input.heartRateSamples
            .filter { $0.value.isFinite }
            .sorted { $0.date < $1.date }

        var sampleIndex = 0

        return intervals.map { interval in
            while sampleIndex < heartRateSamples.count, heartRateSamples[sampleIndex].date < interval.start {
                sampleIndex += 1
            }

            var windowSamples: [HealthTrendDataPoint] = []
            var lookahead = sampleIndex
            while lookahead < heartRateSamples.count, heartRateSamples[lookahead].date < interval.end {
                windowSamples.append(heartRateSamples[lookahead])
                lookahead += 1
            }

            let hasCoverage = windowSamples.count >= Tuning.minimumHeartRateSampleCount
                && (windowSamples[windowSamples.count - 1].date
                    .timeIntervalSince(windowSamples[0].date) >= Tuning.minimumHeartRateSampleSpan)

            let hourStart = calendar.dateInterval(of: .hour, for: interval.start)?.start
            let steps = hourStart.flatMap { stepsByHour[$0] } ?? 0
            let energy = hourStart.flatMap { energyByHour[$0] } ?? 0
            let isActivity = maskIntervals.contains { overlaps(interval, $0) }
                || steps > Tuning.maskStepsPerHour
                || energy > Tuning.maskActiveEnergyKilocaloriesPerHour

            return WindowScan(
                interval: interval,
                isActivity: isActivity,
                isAsleep: input.sleepInterval.map { overlaps(interval, $0) } ?? false,
                medianHeartRate: hasCoverage ? median(windowSamples.map(\.value)) : nil
            )
        }
    }

    // MARK: - HRV influence

    private struct HRVInfluence {
        var score: Double
        var proximity: Double
    }

    /// Only kinds with a calibrated baseline of their own can be read, so a lone RMSSD
    /// sample never discards the day's SDNN coverage.
    private static func calibratedHRVSamples(
        input: StressDayInput,
        baselines: StressBaselines,
        calendar: Calendar
    ) -> [HRVKind: [HealthTrendDataPoint]] {
        var samplesByKind: [HRVKind: [HealthTrendDataPoint]] = [:]
        for kind in HRVKind.allCases where baselines.baseline(for: kind) != nil {
            let samples = input.samples(for: kind)
                .filter { $0.value.isFinite }
                .sorted { $0.date < $1.date }
            if !samples.isEmpty {
                samplesByKind[kind] = samples
            }
        }

        return samplesByKind
    }

    /// RMSSD preferred, SDNN as the fallback — decided per window, not per day.
    private static func hrvInfluence(
        for interval: DateInterval,
        samplesByKind: [HRVKind: [HealthTrendDataPoint]],
        baselines: StressBaselines
    ) -> HRVInfluence? {
        let midpoint = interval.start.addingTimeInterval(interval.duration / 2)

        for kind in [HRVKind.rmssd, .sdnn] {
            guard let samples = samplesByKind[kind],
                  let baseline = baselines.baseline(for: kind),
                  let nearest = nearestSample(to: midpoint, in: samples) else {
                continue
            }

            let distance = abs(nearest.date.timeIntervalSince(midpoint))
            // Strictly inside the reach: at exactly the edge the sample contributes
            // nothing, so the window is honestly HR-only.
            guard distance < Tuning.hrvReach else {
                continue
            }

            // Depression below baseline is the adverse direction for HRV.
            let adverseZScore = -ReadinessScoreCalculator.robustZScore(value: nearest.value, baseline: baseline)

            return HRVInfluence(
                score: logistic(
                    adverseZScore,
                    steepness: Tuning.hrvLogisticSteepness,
                    midpoint: Tuning.hrvLogisticMidpoint
                ),
                proximity: 1 - distance / Tuning.hrvReach
            )
        }

        return nil
    }

    private static func nearestSample(to date: Date, in samples: [HealthTrendDataPoint]) -> HealthTrendDataPoint? {
        samples.min { first, second in
            abs(first.date.timeIntervalSince(date)) < abs(second.date.timeIntervalSince(date))
        }
    }

    // MARK: - Day summary

    static func daySummary(
        windows: [StressWindow],
        date: Date,
        quietHRMedian: Double? = nil,
        rmssdDailyMedian: Double? = nil
    ) -> StressDaySummary {
        var minutesByBand: [StressBand: Int] = [:]
        var scores: [Double] = []
        var hrvCoveredWindowCount = 0

        for window in windows {
            guard let score = window.score else {
                continue
            }

            scores.append(score)
            if !window.isHROnly {
                hrvCoveredWindowCount += 1
            }
            let band = StressBand.band(for: score)
            minutesByBand[band, default: 0] += Int((window.interval.duration / 60).rounded())
        }

        let average = scores.isEmpty ? nil : Int((scores.reduce(0, +) / Double(scores.count)).rounded())
        let minScore = scores.min().map { Int($0.rounded()) }
        let maxScore = scores.max().map { Int($0.rounded()) }

        return StressDaySummary(
            date: date,
            averageScore: average,
            minutesByBand: minutesByBand,
            scoredWindowCount: scores.count,
            hrvCoveredWindowCount: hrvCoveredWindowCount,
            quietHRMedian: quietHRMedian,
            rmssdDailyMedian: rmssdDailyMedian,
            minScore: minScore,
            maxScore: maxScore
        )
    }

    static func daySummary(
        for input: StressDayInput,
        baselines: StressBaselines,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> StressDaySummary {
        let dayWindows = windows(for: input, baselines: baselines, calendar: calendar, now: now)

        return daySummary(
            windows: dayWindows,
            date: calendar.startOfDay(for: input.date),
            quietHRMedian: quietHeartRateDailyMedian(for: input, calendar: calendar, now: now),
            rmssdDailyMedian: median(input.rmssdSamples.map(\.value).filter(\.isFinite))
        )
    }

    // MARK: - Daily series

    /// Freshly computed days win over their recorded counterparts; everything else comes
    /// from the recorded days, which outlive the ~32-day intraday sample cache.
    static func daySummaries(
        recorded: [StressDaySummary],
        computedWindowDays: [StressDayInput],
        context: StressDailySeriesContext,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> [StressDaySummary] {
        var summariesByDay: [Date: StressDaySummary] = [:]
        for entry in recorded {
            summariesByDay[calendar.startOfDay(for: entry.date)] = entry
        }
        for input in computedWindowDays {
            let summary = daySummary(
                for: input,
                baselines: context.baselines(for: input.date),
                calendar: calendar,
                now: now
            )
            summariesByDay[calendar.startOfDay(for: input.date)] = summary
        }

        return summariesByDay.values.sorted { $0.date < $1.date }
    }

    static func dailySeries(
        recorded: [StressDaySummary],
        computedWindowDays: [StressDayInput],
        context: StressDailySeriesContext,
        calendar: Calendar = .bodyGregorian,
        now: Date = Date()
    ) -> HealthTrendSeries {
        let points = daySummaries(
            recorded: recorded,
            computedWindowDays: computedWindowDays,
            context: context,
            calendar: calendar,
            now: now
        )
        .compactMap { summary -> HealthTrendDataPoint? in
            guard let score = summary.averageScore else {
                return nil
            }

            return HealthTrendDataPoint(date: calendar.startOfDay(for: summary.date), value: Double(score))
        }

        return HealthTrendSeries(points: points)
    }

    // MARK: - Baselines

    static func baselines(
        for date: Date,
        quietHeartRateDailyMedians: [ReadinessScoreCalculator.DailyValue],
        sdnnSamples: [HealthTrendDataPoint],
        rmssdSamples: [HealthTrendDataPoint],
        calendar: Calendar = .bodyGregorian
    ) -> StressBaselines {
        StressDailySeriesContext(
            quietHeartRateDailyMedians: quietHeartRateDailyMedians,
            sdnnSamples: sdnnSamples,
            rmssdSamples: rmssdSamples,
            calendar: calendar
        )
        .baselines(for: date)
    }

    /// One aggregate per distinct day. `robustBaseline`'s minimum-count check counts
    /// values, so feeding it raw samples would let a single dense day satisfy the
    /// 14-day minimum on its own.
    static func dailyMedians(
        of points: [HealthTrendDataPoint],
        calendar: Calendar = .bodyGregorian
    ) -> [ReadinessScoreCalculator.DailyValue] {
        dailyMedians(
            of: points.map { ReadinessScoreCalculator.DailyValue(date: $0.date, value: $0.value) },
            calendar: calendar
        )
    }

    static func dailyMedians(
        of values: [ReadinessScoreCalculator.DailyValue],
        calendar: Calendar = .bodyGregorian
    ) -> [ReadinessScoreCalculator.DailyValue] {
        var valuesByDay: [Date: [Double]] = [:]
        for value in values where value.value.isFinite {
            valuesByDay[calendar.startOfDay(for: value.date), default: []].append(value.value)
        }

        return valuesByDay.compactMap { day, dayValues -> ReadinessScoreCalculator.DailyValue? in
            guard let dayMedian = median(dayValues) else {
                return nil
            }

            return ReadinessScoreCalculator.DailyValue(date: day, value: dayMedian)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Math

    private static func logistic(_ zScore: Double, steepness: Double, midpoint: Double) -> Double {
        guard zScore.isFinite else {
            return 0
        }

        return 100 / (1 + exp(-steepness * (zScore - midpoint)))
    }

    private static func clampedScore(_ score: Double) -> Double {
        guard score.isFinite else {
            return 0
        }

        return min(100, max(0, score))
    }

    private static func overlaps(_ first: DateInterval, _ second: DateInterval) -> Bool {
        first.start < second.end && first.end > second.start
    }

    private static func hourlyBuckets(
        _ points: [HealthTrendDataPoint],
        calendar: Calendar
    ) -> [Date: Double] {
        var buckets: [Date: Double] = [:]
        for point in points where point.value.isFinite {
            guard let hourStart = calendar.dateInterval(of: .hour, for: point.date)?.start else {
                continue
            }
            buckets[hourStart, default: 0] += point.value
        }

        return buckets
    }

    /// Local helper so `ReadinessScoreCalculator`'s private internals stay private.
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else {
            return nil
        }

        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }
}

/// RMSSD from beat-to-beat intervals — pure math so Phase 2's `HKHeartbeatSeriesQuery`
/// path and its tests share one implementation with no HealthKit dependency.
enum StressRMSSD {
    struct RRInterval: Equatable {
        var seconds: Double
        /// `HKHeartbeatSeries`' per-beat flag: a gap precedes this interval, so the
        /// successive difference across it is not a real beat-to-beat change.
        var precededByGap: Bool

        init(seconds: Double, precededByGap: Bool = false) {
            self.seconds = seconds
            self.precededByGap = precededByGap
        }
    }

    static let minimumIntervalSeconds = 0.270
    static let maximumIntervalSeconds = 2.000
    /// A single missed or doubled beat can inflate a short-window RMSSD several-fold.
    static let maximumMedianDeviationRatio = 0.30
    static let minimumSuccessiveDifferenceCount = 30

    nonisolated static func rmssdMilliseconds(intervals: [RRInterval]) -> Double? {
        guard intervals.count > 1 else {
            return nil
        }

        let isValid = intervals.map {
            $0.seconds.isFinite
                && $0.seconds >= minimumIntervalSeconds
                && $0.seconds <= maximumIntervalSeconds
        }

        // Seeded from every valid interval so the first pair has a reference too; from
        // then on the reference is the running median of the accepted intervals.
        let validSeconds = zip(intervals, isValid).compactMap { pair in pair.1 ? pair.0.seconds : nil }
        guard var reference = medianValue(of: validSeconds) else {
            return nil
        }

        var accepted: [Double] = []
        var differences: [Double] = []

        for index in 1..<intervals.count {
            let previous = intervals[index - 1]
            let current = intervals[index]
            guard isValid[index - 1], isValid[index], !current.precededByGap else {
                continue
            }
            guard !deviates(previous.seconds, from: reference),
                  !deviates(current.seconds, from: reference) else {
                continue
            }

            differences.append(current.seconds - previous.seconds)
            insert(current.seconds, into: &accepted)
            reference = medianValue(of: accepted) ?? reference
        }

        guard differences.count >= minimumSuccessiveDifferenceCount else {
            return nil
        }

        let meanSquare = differences.reduce(0) { $0 + $1 * $1 } / Double(differences.count)

        return meanSquare.squareRoot() * 1000
    }

    private static func deviates(_ value: Double, from reference: Double) -> Bool {
        guard reference > 0 else {
            return false
        }

        return abs(value - reference) / reference > maximumMedianDeviationRatio
    }

    private static func insert(_ value: Double, into sorted: inout [Double]) {
        var lower = 0
        var upper = sorted.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if sorted[middle] < value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        sorted.insert(value, at: lower)
    }

    private static func medianValue(of values: [Double]) -> Double? {
        StressScoreCalculator.median(values)
    }
}
