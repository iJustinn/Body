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
    /// The sleep goal plus `trainingAdjustment` and `hrvAdjustment`.
    var needDuration: TimeInterval
    /// Body's addition for the previous day's Training Load, 0 to 30 minutes.
    var trainingAdjustment: TimeInterval
    /// Body's addition for a low sleep HRV the night before, 0 to 20 minutes.
    var hrvAdjustment: TimeInterval
    /// Recorded nights in the 14 night window ending on this night.
    var recordedNightCount: Int
    /// Need minus actual summed over that window's recorded nights, floored at
    /// zero. Nil when fewer than 5 of them were recorded, and for today while
    /// today's night hasn't arrived.
    var debtAfterNight: TimeInterval?

    var id: Date {
        day
    }

    var isRecorded: Bool {
        actualDuration != nil
    }
}

/// The Sleep page's Sleep Debt: each night's need (the sleep goal plus
/// Training Load and sleep HRV adjustments) against what was slept, summed
/// over a rolling 14 night calendar window. Nights with no sleep recorded are
/// skipped, longer nights offset shorter ones, and the total never drops
/// below zero.
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
    }

    static let windowNightCount = 14
    static let minimumRecordedNightCount = 5
    /// Matches the Sleep page's date picker, so every pickable day has a night.
    static let selectableNightCount = BodyHealthTrendRange.recentMonth.dayCount
    /// The pickable nights, the 13 nights the oldest one's window reaches back
    /// to, and the day before those for its Training Load and sleep HRV.
    static let entryDayCount = selectableNightCount + windowNightCount
    /// Oura's published bands, which About Sleep Debt names and the chart draws
    /// as dashed rules and dot colors: a debt under 2 hours is low, 2 to 5 hours
    /// is moderate, and over 5 hours is high.
    static let lowDebtUpperBound: TimeInterval = 2 * 3_600
    static let moderateDebtUpperBound: TimeInterval = 5 * 3_600
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

    static let empty = SleepDebtChartModel(nights: [])

    /// The pickable wake days ending today, oldest first.
    var nights: [SleepDebtNight]

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
        /// Each entry day's Training Load ratio, aligned with `days`.
        var trainingLoadRatios: [Double?]
        var calendar: Calendar
    }

    /// One entry per wake day, `entryDayCount` days ending today: the history's
    /// night for the day (the live summary fills in today only, and only when
    /// it is today's), the day's Training Load ratio, and how the night's
    /// sleep HRV compared with the nights before it.
    static func entries(
        sleepHistory: SleepHistorySnapshot,
        currentDaySummary: SleepSummary?,
        trainingLoad: HealthTrendSeries,
        today: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> [Entry] {
        entries(from: inputs(
            sleepHistory: sleepHistory,
            currentDaySummary: currentDaySummary,
            trainingLoad: trainingLoad,
            today: today,
            calendar: calendar
        ))
    }

    /// Gathers what `entries(from:)` reads.
    static func inputs(
        sleepHistory: SleepHistorySnapshot,
        currentDaySummary: SleepSummary?,
        trainingLoad: HealthTrendSeries,
        today: Date = Date(),
        calendar: Calendar = .bodyGregorian
    ) -> Inputs {
        let days = SleepHistorySnapshot.datePickerDates(endingAt: today, dayCount: entryDayCount, calendar: calendar)
        guard let firstDay = days.first else {
            return Inputs(days: [], nights: [], trainingLoadRatios: [], calendar: calendar)
        }

        // Two days of slack keep a night stored under another zone's midnight
        // within reach of the start of day keying below. The first entry's
        // night is judged for HRV too, so the history reaches a whole HRV
        // baseline further back than the entries.
        let cutoff = calendar.date(byAdding: .day, value: -2, to: firstDay) ?? firstDay
        let historyCutoff = calendar.date(
            byAdding: .day,
            value: -ReadinessScoreCalculator.baselineDayCount,
            to: cutoff
        ) ?? cutoff

        // The first entry for a day wins, as in `SleepHistorySnapshot.summary(on:)`.
        // The live summary fills in today only, and only when it is today's; its
        // HRV never reaches a baseline, which only reads nights before the one
        // it judges.
        var nights: [Inputs.Night] = []
        var recordedDays: Set<Date> = []
        for day in sleepHistory.days where day.date >= historyCutoff {
            let dayStart = calendar.startOfDay(for: day.date)
            if recordedDays.insert(dayStart).inserted {
                nights.append(Inputs.Night(day: dayStart, summary: day.summary))
            }
        }
        let todayStart = calendar.startOfDay(for: today)
        if !recordedDays.contains(todayStart), let liveSummary = currentDaySummary?.asOf(today, calendar: calendar) {
            nights.append(Inputs.Night(day: todayStart, summary: liveSummary))
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
            trainingLoadRatios: days.map { ratiosByDay[$0]?.value },
            calendar: calendar
        )
    }

    /// The entries for `inputs`, judging each night's sleep HRV against the
    /// nights before it: the costly part, which the gathered inputs let a
    /// caller skip.
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
                hrvZScore: hrvZScore(night?.heartRateVariability, on: day, values: hrvValues, calendar: inputs.calendar)
            )
        }
    }

    /// Durations are summed as recorded; rounding happens only where values
    /// are shown.
    static func make(entries: [Entry], sleepGoal: TimeInterval) -> SleepDebtChartModel {
        guard entries.count == entryDayCount else {
            return .empty
        }

        // The first entry only lends its Training Load and sleep HRV to the
        // night after it.
        var trainingAdjustments = [TimeInterval](repeating: 0, count: entries.count)
        var hrvAdjustments = [TimeInterval](repeating: 0, count: entries.count)
        var needs = [TimeInterval](repeating: sleepGoal, count: entries.count)
        var actuals = [TimeInterval?](repeating: nil, count: entries.count)
        var gaps = [TimeInterval?](repeating: nil, count: entries.count)
        for index in entries.indices.dropFirst() {
            trainingAdjustments[index] = trainingAdjustment(forTrainingLoadRatio: entries[index - 1].trainingLoadRatio)
            hrvAdjustments[index] = hrvAdjustment(forHRVZScore: entries[index - 1].hrvZScore)
            needs[index] = sleepGoal + trainingAdjustments[index] + hrvAdjustments[index]
            if let duration = entries[index].duration, duration.isFinite, duration > 0 {
                actuals[index] = duration
                gaps[index] = needs[index] - duration
            }
        }

        let todayIndex = entries.count - 1
        let nights = ((entries.count - selectableNightCount)...todayIndex).map { index in
            let recordedGaps = ((index - windowNightCount + 1)...index).compactMap { gaps[$0] }
            // Today's night may still be syncing, so it has no point until it arrives.
            let isPendingToday = index == todayIndex && actuals[index] == nil
            let debt: TimeInterval? = recordedGaps.count >= minimumRecordedNightCount && !isPendingToday
                ? max(0, recordedGaps.reduce(0, +))
                : nil
            return SleepDebtNight(
                day: entries[index].day,
                actualDuration: actuals[index],
                needDuration: needs[index],
                trainingAdjustment: trainingAdjustments[index],
                hrvAdjustment: hrvAdjustments[index],
                recordedNightCount: recordedGaps.count,
                debtAfterNight: debt
            )
        }

        return SleepDebtChartModel(nights: nights)
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
