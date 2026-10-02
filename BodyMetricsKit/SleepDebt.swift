//
//  SleepDebt.swift
//  Body
//

import Foundation

/// One wake day on the Sleep Debt card: what was slept, what was needed, and
/// the 14 night debt as it stood after that night.
struct SleepDebtNight: Equatable, Identifiable {
    /// Start of the wake day the night is filed under.
    var day: Date
    /// Asleep time for the wake day, naps included (`SleepSummary.duration`),
    /// or nil when no sleep was recorded.
    var actualDuration: TimeInterval?
    /// The base need (the sleep goal moved a third of the way toward the need
    /// learned from the 8 weeks of sleep ending on this night, or the goal
    /// alone until the need is learned) plus `trainingAdjustment` and `hrvAdjustment`.
    var needDuration: TimeInterval
    /// False while the sleep goal stands in for this night's learned need; the
    /// card then shows a placeholder for the need.
    var isNeedLearned: Bool
    /// Body's addition for the previous day's Training Load, 0 to 30 minutes.
    var trainingAdjustment: TimeInterval
    /// Body's addition for a low sleep HRV the night before, 0 to 20 minutes.
    var hrvAdjustment: TimeInterval
    /// Recorded nights in the 14 night window ending on this night.
    var recordedNightCount: Int
    /// Need minus actual summed over that window's recorded nights, floored at
    /// zero and capped at 6 hours. Nil when fewer than 5 of them were recorded,
    /// and for today while today's night hasn't arrived.
    var debtAfterNight: TimeInterval?

    var id: Date {
        day
    }

    var isRecorded: Bool {
        actualDuration != nil
    }
}

/// A night frozen once its day has passed: every field the night row and the
/// chart read, so the night renders exactly as it did when it was captured,
/// and later nights sum its gap (`needDuration` minus `actualDuration`) as it
/// stood. Only a recorded night is frozen; a night with no sleep stays live so
/// a late sync can still fill it. Never rewritten: only a context change (the
/// goal, a source, a permission, the algorithm) drops the records, and then
/// every night is judged again from scratch (`recalculatingSleepDebt`).
struct SleepDebtRecord: Codable, Equatable, Identifiable {
    /// Start of the wake day, in the zone the night was captured in; readers
    /// key it by `startOfDay` again, like the Readiness records.
    var day: Date
    var actualDuration: TimeInterval
    var needDuration: TimeInterval
    var isNeedLearned: Bool
    var trainingAdjustment: TimeInterval
    var hrvAdjustment: TimeInterval
    var recordedNightCount: Int
    var debtAfterNight: TimeInterval?
    var capturedAt: Date

    var id: Date {
        day
    }

    /// Nil for a night with no sleep recorded.
    init?(night: SleepDebtNight, capturedAt: Date) {
        guard let actualDuration = night.actualDuration else {
            return nil
        }

        day = night.day
        self.actualDuration = actualDuration
        needDuration = night.needDuration
        isNeedLearned = night.isNeedLearned
        trainingAdjustment = night.trainingAdjustment
        hrvAdjustment = night.hrvAdjustment
        recordedNightCount = night.recordedNightCount
        debtAfterNight = night.debtAfterNight
        self.capturedAt = capturedAt
    }

    /// The night as it was captured, filed under `day`.
    func night(on day: Date) -> SleepDebtNight {
        SleepDebtNight(
            day: day,
            actualDuration: actualDuration,
            needDuration: needDuration,
            isNeedLearned: isNeedLearned,
            trainingAdjustment: trainingAdjustment,
            hrvAdjustment: hrvAdjustment,
            recordedNightCount: recordedNightCount,
            debtAfterNight: debtAfterNight
        )
    }
}

/// The Sleep page's Sleep Debt: each night's need (a base need that moves the
/// sleep goal a third of the way toward what the 8 weeks of sleep ending on
/// that night show, or the goal alone until enough nights exist, plus Training
/// Load and sleep HRV adjustments) against what was slept, summed over a
/// rolling 14 night calendar window. Nights with no sleep recorded are
/// skipped, longer nights offset shorter ones, and the total never drops below
/// zero or climbs past 6 hours. Each night keeps the need it learned on its
/// own day, so a point on the chart never moves as later nights arrive.
struct SleepDebtChartModel: Equatable {
    struct Entry: Equatable {
        /// Start of the wake day.
        var day: Date
        /// `SleepSummary.duration` for the day, naps included.
        var duration: TimeInterval?
        /// The day's Training Load ratio (acute over chronic), which sets the
        /// need of the night that ends the next morning.
        var trainingLoadRatio: Double?
        /// How far the night's sleep HRV sat from the nights before it, as
        /// Readiness's robust z score, which sets the need of the next night.
        /// Nil without a reading or a baseline.
        var hrvZScore: Double? = nil
        /// The need learned from the recorded nights of the 56 days ending on
        /// this day, or nil with fewer than 28 of them. The night is judged
        /// against it, so its need stays what it was on its own day.
        var learnedNeed: TimeInterval? = nil
    }

    /// Rides the records' context signature: bumping it drops every frozen
    /// night so the new rule judges them again, like Body Radar's.
    static let algorithmVersion = 1
    /// Frozen nights older than this many days before today are pruned: the
    /// entry days the model reads, plus a window of slack.
    static let recordRetentionDayCount = entryDayCount + windowNightCount

    static let windowNightCount = 14
    static let minimumRecordedNightCount = 5
    /// Matches the Sleep page's date picker, so every pickable day has a night.
    static let selectableNightCount = BodyHealthTrendRange.recentMonth.dayCount
    /// The pickable nights, the 13 nights the oldest one's window reaches back
    /// to, and the day before those for its Training Load and sleep HRV.
    static let entryDayCount = selectableNightCount + windowNightCount
    /// The nights the watch Sleep page charts: the same 14 the phone's chart
    /// draws (`chartNights`). Each is the same 14 night debt the phone shows
    /// for that night, since a night reads only its own window, the entry
    /// before it, and the 56 days of history behind them.
    static let watchNightCount = windowNightCount

    /// Days of sleep history, ending today, that `inputs` reads for a model of
    /// `nightCount` nights: the entry days, the two days of slack, and a whole
    /// HRV baseline before them (see `cutoff` and `historyCutoff` there). The
    /// watch's compute seed keeps this many nights so it reads what the phone does.
    static func historyDayCount(nightCount: Int) -> Int {
        nightCount + windowNightCount + 2 + ReadinessScoreCalculator.baselineDayCount
    }
    /// The bands About Sleep Debt names and the chart draws as dashed rules and
    /// dot colors: a debt under 2 hours is low, 2 to 4 hours is moderate, and
    /// over 4 hours is high. The total is capped at `maximumDebt`, so the chart's
    /// axis always ends there.
    static let lowDebtUpperBound: TimeInterval = 2 * 3_600
    static let moderateDebtUpperBound: TimeInterval = 4 * 3_600
    static let maximumDebt: TimeInterval = 6 * 3_600
    /// A night's learned need reads the recorded nights of the 56 days ending
    /// on it, needs 28 of them, and takes their 75th percentile: what you sleep on
    /// your longer nights, since the median of a short sleeper reflects the
    /// shortfall itself. It is kept between 6 and 10 hours, and the base need
    /// then moves the sleep goal a third of the way toward it, so the goal
    /// keeps most of its say and the learned figure can't run far from what
    /// you want to sleep.
    static let learnedNeedDayCount = ReadinessScoreCalculator.baselineDayCount
    static let minimumLearnedNeedNightCount = 28
    static let learnedNeedPercentile = 0.75
    static let learnedNeedRange: ClosedRange<TimeInterval> = 6 * 3_600 ... 10 * 3_600
    static let maximumTrainingAdjustment: TimeInterval = 30 * 60
    static let maximumHRVAdjustment: TimeInterval = 20 * 60
    private static let adjustmentStep: TimeInterval = 5 * 60
    /// A ratio of 1.0 (training at your usual level) adds nothing; the extra
    /// minutes grow linearly to the maximum at 1.5.
    private static let trainingAdjustmentRatioRange: ClosedRange<Double> = 1.0...1.5
    /// A z score of −1, where Body Radar starts counting a low HRV, adds
    /// nothing; the extra minutes grow linearly to the maximum at −2, where
    /// Body Radar flags it and Readiness's low HRV driver is at full weight.
    private static let hrvAdjustmentZScoreRange: ClosedRange<Double> = -2.0 ... -1.0
    /// The spread floor, in milliseconds, that Readiness and Body Radar give
    /// sleep HRV.
    private static let hrvSpreadFloor = 5.0

    static let empty = SleepDebtChartModel(nights: [], sleepGoal: 0)

    /// The pickable wake days ending today, oldest first.
    var nights: [SleepDebtNight]
    /// The Settings sleep goal, which the night row shows beside the need.
    var sleepGoal: TimeInterval

    /// The chart's columns: the last 14 wake days, the same days as the Sleep
    /// Consistency chart.
    var chartNights: [SleepDebtNight] {
        Array(nights.suffix(Self.windowNightCount))
    }

    /// The night the headline reports: today's once it's recorded, otherwise
    /// yesterday's. Only today's pending night is waited for; a day with no
    /// sleep recorded still moves the window on.
    var latestNight: SleepDebtNight? {
        guard let today = nights.last else {
            return nil
        }

        return today.isRecorded ? today : nights.dropLast().last
    }

    var debt: TimeInterval? {
        latestNight?.debtAfterNight
    }

    func night(on date: Date, calendar: Calendar = .bodyGregorian) -> SleepDebtNight? {
        nights.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// Everything the model reads from the history, the live summary, and the
    /// Training Load series, one value per day: cheap to gather and to compare,
    /// so a caller can skip the HRV baselines while nothing it reads changed.
    struct Inputs: Equatable {
        struct Night: Equatable {
            var day: Date
            var duration: TimeInterval?
            var heartRateVariability: Double?

            init(day: Date, summary: SleepSummary) {
                self.day = day
                duration = summary.duration
                heartRateVariability = summary.vitals.heartRateVariability
            }
        }

        /// The entry days, oldest first.
        var days: [Date]
        /// One night per recorded day, from a whole HRV baseline before the
        /// first entry day through today.
        var nights: [Night]
        /// Each entry day's Training Load ratio, aligned with `days`; nil for
        /// today, whose ratio only sets tomorrow's need.
        var trainingLoadRatios: [Double?]
        var calendar: Calendar
    }

    /// One entry per wake day, `nightCount + windowNightCount` days ending
    /// today: the history's night for the day (the live summary fills in today
    /// only, and only when it is today's), the day's Training Load ratio, how
    /// the night's sleep HRV compared with the nights before it, and the need
    /// learned by that day.
    static func entries(
        sleepHistory: SleepHistorySnapshot,
        currentDaySummary: SleepSummary?,
        trainingLoad: HealthTrendSeries,
        nightCount: Int = selectableNightCount,
        today: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [Entry] {
        entries(from: inputs(
            sleepHistory: sleepHistory,
            currentDaySummary: currentDaySummary,
            trainingLoad: trainingLoad,
            nightCount: nightCount,
            today: today,
            calendar: calendar
        ))
    }

    /// Gathers what `entries(from:)` reads.
    static func inputs(
        sleepHistory: SleepHistorySnapshot,
        currentDaySummary: SleepSummary?,
        trainingLoad: HealthTrendSeries,
        nightCount: Int = selectableNightCount,
        today: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> Inputs {
        let days = SleepHistorySnapshot.datePickerDates(
            endingAt: today,
            dayCount: nightCount + windowNightCount,
            calendar: calendar
        )
        guard let firstDay = days.first else {
            return Inputs(days: [], nights: [], trainingLoadRatios: [], calendar: calendar)
        }

        // Two days of slack keep a night stored under another zone's midnight
        // within reach of the start of day keying below. The first entry's
        // night is judged for HRV too, so the history reaches a whole HRV
        // baseline further back than the entries, which also covers the 56
        // days each entry learns its need from.
        let cutoff = calendar.date(byAdding: .day, value: -2, to: firstDay) ?? firstDay
        let historyCutoff = calendar.date(
            byAdding: .day,
            value: -ReadinessScoreCalculator.baselineDayCount,
            to: cutoff
        ) ?? cutoff

        // The first entry for a day wins, as in `SleepHistorySnapshot.summary(on:)`.
        // The live summary fills in today only, and only when it is today's.
        // Today's sleep HRV and Training Load ratio are left out: they only set
        // tomorrow's need, so an HRV revision or a workout logged today would
        // rebuild the model for the same result.
        let todayStart = calendar.startOfDay(for: today)
        var nights: [Inputs.Night] = []
        var recordedDays: Set<Date> = []
        for day in sleepHistory.days where day.date >= historyCutoff {
            let dayStart = calendar.startOfDay(for: day.date)
            if recordedDays.insert(dayStart).inserted {
                nights.append(Inputs.Night(day: dayStart, summary: day.summary))
            }
        }
        if !recordedDays.contains(todayStart), let liveSummary = currentDaySummary?.asOf(today, calendar: calendar) {
            nights.append(Inputs.Night(day: todayStart, summary: liveSummary))
        }
        if let todayIndex = nights.firstIndex(where: { $0.day == todayStart }) {
            nights[todayIndex].heartRateVariability = nil
        }

        // The latest point of a day wins.
        var ratiosByDay: [Date: HealthTrendDataPoint] = [:]
        for point in trainingLoad.points where point.date >= cutoff && point.value.isFinite {
            let dayStart = calendar.startOfDay(for: point.date)
            if let existing = ratiosByDay[dayStart], existing.date > point.date {
                continue
            }
            ratiosByDay[dayStart] = point
        }

        return Inputs(
            days: days,
            nights: nights,
            trainingLoadRatios: days.map { $0 == todayStart ? nil : ratiosByDay[$0]?.value },
            calendar: calendar
        )
    }

    /// The entries for `inputs`, judging each night's sleep HRV against the
    /// nights before it and learning each day's need from the 56 days ending
    /// on it: the costly part, which the gathered inputs let a caller skip.
    static func entries(from inputs: Inputs) -> [Entry] {
        let hrvValues = inputs.nights.compactMap { night in
            usableHRV(night.heartRateVariability).map {
                ReadinessScoreCalculator.DailyValue(date: night.day, value: $0)
            }
        }
        let nightsByDay = Dictionary(inputs.nights.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return zip(inputs.days, inputs.trainingLoadRatios).map { day, ratio in
            let night = nightsByDay[day]
            return Entry(
                day: day,
                duration: night?.duration,
                trainingLoadRatio: ratio,
                hrvZScore: hrvZScore(night?.heartRateVariability, on: day, values: hrvValues, calendar: inputs.calendar),
                learnedNeed: learnedNeed(on: day, nights: inputs.nights, calendar: inputs.calendar)
            )
        }
    }

    /// The base need learned by `day`: the 75th percentile of the asleep time
    /// of the recorded nights in the 56 days ending on it, or nil with fewer
    /// than 28 of them.
    private static func learnedNeed(on day: Date, nights: [Inputs.Night], calendar: Calendar) -> TimeInterval? {
        guard let firstDay = calendar.date(byAdding: .day, value: 1 - learnedNeedDayCount, to: day) else {
            return nil
        }

        let durations = nights.compactMap { night -> TimeInterval? in
            guard night.day >= firstDay, night.day <= day,
                  let duration = night.duration, duration.isFinite, duration > 0 else {
                return nil
            }
            return duration
        }
        return learnedNeed(durations: durations)
    }

    /// The 75th percentile of `durations` (linearly interpolated), rounded to
    /// 5 minutes and kept between 6 and 10 hours, or nil with fewer than 28.
    static func learnedNeed(durations: [TimeInterval]) -> TimeInterval? {
        guard durations.count >= minimumLearnedNeedNightCount else {
            return nil
        }

        let sorted = durations.sorted()
        let position = learnedNeedPercentile * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        let percentile = sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
        let stepped = (percentile / adjustmentStep).rounded() * adjustmentStep
        return min(max(stepped, learnedNeedRange.lowerBound), learnedNeedRange.upperBound)
    }

    /// The sleep goal moved a third of the way toward the learned need, in 5
    /// minute steps.
    static func baseNeed(learnedNeed: TimeInterval, sleepGoal: TimeInterval) -> TimeInterval {
        ((sleepGoal + (learnedNeed - sleepGoal) / 3) / adjustmentStep).rounded() * adjustmentStep
    }

    /// Durations are summed as recorded; rounding happens only where values
    /// are shown. Each night is judged against `baseNeed(learnedNeed:sleepGoal:)`
    /// with its own entry's learned need, and against `sleepGoal` alone while
    /// that is nil, so no night is judged again by a need learned later.
    /// `nightCount` is how many nights the model keeps (the watch charts 14);
    /// `entries` must hold `nightCount + windowNightCount` days. A day with a
    /// frozen record in `records` takes its slept time, need and adjustments
    /// from the record, so every window that reaches it sums the gap it was
    /// frozen with, and is emitted as the record's night, unchanged.
    static func make(
        entries: [Entry],
        sleepGoal: TimeInterval,
        nightCount: Int = selectableNightCount,
        records: [SleepDebtRecord] = [],
        calendar: Calendar = .bodyGregorian
    ) -> SleepDebtChartModel {
        guard nightCount > 0, entries.count == nightCount + windowNightCount else {
            return .empty
        }

        let recordsByDay = Dictionary(
            records.map { (calendar.startOfDay(for: $0.day), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let frozen = entries.map { recordsByDay[calendar.startOfDay(for: $0.day)] }

        let baseNeeds = entries.map { entry in
            entry.learnedNeed.map { baseNeed(learnedNeed: $0, sleepGoal: sleepGoal) } ?? sleepGoal
        }

        // The first entry only lends its Training Load and sleep HRV to the
        // night after it.
        var trainingAdjustments = [TimeInterval](repeating: 0, count: entries.count)
        var hrvAdjustments = [TimeInterval](repeating: 0, count: entries.count)
        var needs = baseNeeds
        var actuals = [TimeInterval?](repeating: nil, count: entries.count)
        var gaps = [TimeInterval?](repeating: nil, count: entries.count)
        for index in entries.indices.dropFirst() {
            if let record = frozen[index] {
                trainingAdjustments[index] = record.trainingAdjustment
                hrvAdjustments[index] = record.hrvAdjustment
                needs[index] = record.needDuration
                actuals[index] = record.actualDuration
                gaps[index] = record.needDuration - record.actualDuration
                continue
            }
            trainingAdjustments[index] = trainingAdjustment(forTrainingLoadRatio: entries[index - 1].trainingLoadRatio)
            hrvAdjustments[index] = hrvAdjustment(forHRVZScore: entries[index - 1].hrvZScore)
            needs[index] = baseNeeds[index] + trainingAdjustments[index] + hrvAdjustments[index]
            if let duration = entries[index].duration, duration.isFinite, duration > 0 {
                actuals[index] = duration
                gaps[index] = needs[index] - duration
            }
        }

        let todayIndex = entries.count - 1
        let nights = ((entries.count - nightCount)...todayIndex).map { index in
            if let record = frozen[index] {
                return record.night(on: entries[index].day)
            }
            let recordedGaps = ((index - windowNightCount + 1)...index).compactMap { gaps[$0] }
            // Today's night may still be syncing, so it has no point until it arrives.
            let isPendingToday = index == todayIndex && actuals[index] == nil
            let debt: TimeInterval? = recordedGaps.count >= minimumRecordedNightCount && !isPendingToday
                ? min(max(0, recordedGaps.reduce(0, +)), maximumDebt)
                : nil
            return SleepDebtNight(
                day: entries[index].day,
                actualDuration: actuals[index],
                needDuration: needs[index],
                isNeedLearned: entries[index].learnedNeed != nil,
                trainingAdjustment: trainingAdjustments[index],
                hrvAdjustment: hrvAdjustments[index],
                recordedNightCount: recordedGaps.count,
                debtAfterNight: debt
            )
        }

        return SleepDebtChartModel(nights: nights, sleepGoal: sleepGoal)
    }

    /// `records` with every night of `nights` whose day is before `today`'s
    /// and that has sleep recorded frozen as it stands, when it has no record
    /// yet. An existing record is never rewritten; today's night stays live so
    /// a late sync still lands. Records older than `recordRetentionDayCount`
    /// days before today are dropped, and the result is sorted by day.
    static func freezing(
        records: [SleepDebtRecord],
        nights: [SleepDebtNight],
        today: Date,
        now: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [SleepDebtRecord] {
        let todayStart = calendar.startOfDay(for: today)
        var recordedDays = Set(records.map { calendar.startOfDay(for: $0.day) })
        var updated = records
        for night in nights {
            let day = calendar.startOfDay(for: night.day)
            guard day < todayStart, !recordedDays.contains(day),
                  let record = SleepDebtRecord(night: night, capturedAt: now) else {
                continue
            }
            recordedDays.insert(day)
            updated.append(record)
        }

        let cutoff = calendar.date(byAdding: .day, value: -recordRetentionDayCount, to: todayStart) ?? todayStart
        return updated
            .filter { calendar.startOfDay(for: $0.day) >= cutoff }
            .sorted { $0.day < $1.day }
    }

    /// Body's own addition to a night's need after a day of heavier than usual
    /// training: nothing at a Training Load ratio of 1.0 or less, then linearly
    /// up to 30 minutes at 1.5, in 5 minute steps.
    static func trainingAdjustment(forTrainingLoadRatio ratio: Double?) -> TimeInterval {
        guard let ratio, ratio.isFinite else {
            return 0
        }

        let range = trainingAdjustmentRatioRange
        return steppedAdjustment(
            maximum: maximumTrainingAdjustment,
            progress: (ratio - range.lowerBound) / (range.upperBound - range.lowerBound)
        )
    }

    /// Body's own addition to a night's need after a night whose sleep HRV sat
    /// well below your usual range: nothing at a z score of −1 or above, then
    /// linearly up to 20 minutes at −2, in 5 minute steps.
    static func hrvAdjustment(forHRVZScore zScore: Double?) -> TimeInterval {
        guard let zScore, zScore.isFinite else {
            return 0
        }

        let range = hrvAdjustmentZScoreRange
        return steppedAdjustment(
            maximum: maximumHRVAdjustment,
            progress: (range.upperBound - zScore) / (range.upperBound - range.lowerBound)
        )
    }

    /// `maximum` scaled by `progress` clamped to 0...1, in 5 minute steps.
    private static func steppedAdjustment(maximum: TimeInterval, progress: Double) -> TimeInterval {
        let clamped = min(max(progress, 0), 1)
        return (maximum * clamped / adjustmentStep).rounded() * adjustmentStep
    }

    /// The night's sleep HRV as Readiness's robust z score against the 56
    /// nights before it. Judged on the night's own day, so the night never
    /// counts in its own baseline.
    private static func hrvZScore(
        _ hrv: Double?,
        on day: Date,
        values: [ReadinessScoreCalculator.DailyValue],
        calendar: Calendar
    ) -> Double? {
        guard let hrv = usableHRV(hrv),
              let baseline = ReadinessScoreCalculator.robustBaseline(
                  for: day,
                  values: values,
                  floor: hrvSpreadFloor,
                  calendar: calendar
              ) else {
            return nil
        }

        return ReadinessScoreCalculator.robustZScore(value: hrv, baseline: baseline)
    }

    private static func usableHRV(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }

        return value
    }
}
