//
//  BodyRadarCalculator.swift
//  Body
//
//  Body Radar (Beta v1) engine: grades five overnight signals against the same
//  56-day robust baseline the Vitals page uses, sums directional evidence, and
//  freezes one verdict per day the way the readiness morning record is frozen.
//
//  Not a medical device: this reports deviations from a personal baseline, it
//  does not diagnose anything.
//

import Foundation

enum BodyRadarCalculator {
    enum Tuning {
        /// Signal weights. Temperature leads because it is the least ambiguous
        /// overnight illness marker; inactive time is a weak corroborator.
        static func weight(for kind: BodyRadarSignalKind) -> Double {
            switch kind {
            case .wristTemperature:
                return 1.5
            case .respiratoryRate, .sleepingHeartRate, .heartRateVariability:
                return 1.0
            case .inactiveTime:
                return 0.5
            }
        }

        /// Deviation below which a signal contributes nothing, so ordinary
        /// night-to-night wobble never accumulates into a verdict.
        static let deadZone = 0.5
        /// A signal past this is called out by name on the card.
        static let flagThreshold = 1.0
        static let minorEvidence = 0.75
        static let majorEvidence = 2.0
        /// Major needs corroboration: one saturated signal caps at Minor.
        static let majorFlaggedSignalCount = 2

        /// Robust-spread floor for overnight SDNN, matching
        /// `StressScoreCalculator.Tuning.hrvSpreadFloor`.
        static let heartRateVariabilityFloor = 5.0
        /// Robust-spread floor for daily inactive hours.
        static let inactiveHoursFloor = 1.0
        /// An hour with fewer steps than this counts as inactive, matching the
        /// stress engine's activity mask.
        static let inactiveStepsPerHour = 200.0
        /// Inactive hours are counted between wake and this local hour.
        static let inactiveWindowEndHour = 22

        /// Recency gate: Oura's "7 of the last 14 nights" rule.
        static let recencyWindowDayCount = 14
        static let recencyMinimumNightCount = 7
        /// Shortest sleep that may be read as a night rather than a nap.
        static let minimumNightSleepDuration: TimeInterval = 3 * 3_600

        /// Nights kept in `BodyRadarSummary.recentNights`.
        static let recentNightCount = 21
        /// Frozen records kept on disk.
        static let recordedNightLimit = 60
        /// Freeze opens this long after wake.
        static let freezeDelayAfterWake: TimeInterval = 600
        /// Freeze hour when wake time is unknown.
        static let freezeFallbackHour = 10
    }

    // MARK: - Entry point

    /// The card's summary plus the frozen-record array to persist. `recorded`
    /// must already have been filtered for a changed input context by the
    /// caller; nothing here inspects the context signature.
    static func summary(
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        hourlySteps: [HealthTrendDataPoint],
        workoutDays: Set<Date>,
        recorded: [BodyRadarNight],
        today: Date,
        now: Date,
        wakeTime: Date?,
        calendar: Calendar = .bodyGregorian
    ) -> (summary: BodyRadarSummary, recorded: [BodyRadarNight]) {
        let scoringDay = calendar.startOfDay(for: today)
        let context = Context(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
            hourlySteps: hourlySteps,
            workoutDays: workoutDays,
            today: today,
            calendar: calendar
        )

        let tonight = context.night(on: scoringDay)
        let records = freezing(
            records: recorded,
            night: tonight,
            now: now,
            wakeTime: wakeTime,
            scoringDay: scoringDay,
            calendar: calendar
        )

        let recordsByDay = Dictionary(
            records.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let yesterday = calendar.date(byAdding: .day, value: -1, to: scoringDay) ?? scoringDay
        let latest = recordsByDay[scoringDay]
            ?? recordsByDay[yesterday]
            ?? BodyRadarNight(
                date: scoringDay,
                state: tonight.state == .missingSleep ? .missingSleep : .calibrating
            )

        // Past nights prefer the frozen record and fall back to a deterministic
        // recompute from the sleep cache. Today only ever shows a frozen record,
        // so the card never contradicts the morning's verdict. A past night that
        // had to be recomputed and scored is recorded too, so the next refresh
        // reads it back instead of scoring it again; an unscored past night is
        // not, since a late sleep sync can still fill it in.
        var recent: [BodyRadarNight] = []
        var backfilled: [BodyRadarNight] = []
        for offset in stride(from: Tuning.recentNightCount - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: scoringDay) else {
                continue
            }
            if let record = recordsByDay[day] {
                recent.append(record)
            } else if day < scoringDay {
                // Unscored days stay in, so the chart keeps a slot for every
                // night and can show where data or a verdict was missing.
                let night = context.night(on: day)
                recent.append(night)
                if night.state.isScored {
                    backfilled.append(night)
                }
            }
        }

        return (
            BodyRadarSummary(latest: latest, recentNights: recent),
            backfilled.isEmpty ? records : capped(records + backfilled, calendar: calendar)
        )
    }

    /// One night's verdict, with no freezing applied. Exposed for tests and for
    /// callers that only need today's live read.
    static func night(
        on date: Date,
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        hourlySteps: [HealthTrendDataPoint],
        workoutDays: Set<Date>,
        today: Date,
        calendar: Calendar = .bodyGregorian
    ) -> BodyRadarNight {
        Context(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
            hourlySteps: hourlySteps,
            workoutDays: workoutDays,
            today: today,
            calendar: calendar
        )
        .night(on: calendar.startOfDay(for: date))
    }

    // MARK: - Freezing

    /// Freezes the scoring day's verdict once, mirroring the readiness morning
    /// record: the window opens at `wakeTime + 10 min` (or 10:00 local when wake
    /// is unknown) and closes at the end of the scoring day. A record that
    /// already exists for the day is kept verbatim, so a later refresh with
    /// changed vitals cannot rewrite the morning's answer. Missing sleep is
    /// never frozen, so a late sleep sync can still fill the day in.
    static func freezing(
        records: [BodyRadarNight],
        night: BodyRadarNight,
        now: Date,
        wakeTime: Date?,
        scoringDay: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [BodyRadarNight] {
        let scoringDay = calendar.startOfDay(for: scoringDay)
        guard night.state != .missingSleep else {
            return capped(records, calendar: calendar)
        }
        guard !records.contains(where: { calendar.startOfDay(for: $0.date) == scoringDay }) else {
            return capped(records, calendar: calendar)
        }

        let freezeMoment: Date
        if let wakeTime {
            freezeMoment = wakeTime.addingTimeInterval(Tuning.freezeDelayAfterWake)
        } else {
            freezeMoment = calendar.date(
                bySettingHour: Tuning.freezeFallbackHour,
                minute: 0,
                second: 0,
                of: scoringDay
            ) ?? scoringDay
        }
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: scoringDay)
            ?? scoringDay.addingTimeInterval(86_400)
        guard now >= freezeMoment, now < windowEnd else {
            return capped(records, calendar: calendar)
        }

        var frozen = night
        frozen.date = scoringDay
        return capped(records + [frozen], calendar: calendar)
    }

    private static func capped(_ records: [BodyRadarNight], calendar: Calendar) -> [BodyRadarNight] {
        let sorted = records.sorted { $0.date < $1.date }
        guard sorted.count > Tuning.recordedNightLimit else {
            return sorted
        }
        return Array(sorted.suffix(Tuning.recordedNightLimit))
    }

    // MARK: - Scoring

    /// Weighted evidence past the dead zone; zero when the signal moved the
    /// healthy way.
    static func contribution(of signal: BodyRadarSignal) -> Double {
        Tuning.weight(for: signal.kind) * max(0, signal.directionalDeviation - Tuning.deadZone)
    }

    static func state(evidence: Double, flaggedCount: Int) -> BodyRadarState {
        if evidence >= Tuning.majorEvidence, flaggedCount >= Tuning.majorFlaggedSignalCount {
            return .majorSigns
        }
        if evidence >= Tuning.minorEvidence {
            return .minorSigns
        }
        return .noSigns
    }

    // MARK: - Context

    /// The per-signal day series a run of nights is scored against, built once
    /// so scoring the recent nights does not rebuild the history once per night.
    private struct Context {
        let series: [BodyRadarSignalKind: VitalsCalculator.VitalSeries]
        /// Days that hold a night worth scoring, keyed by start of the wake day.
        let nightDays: Set<Date>
        let calendar: Calendar

        init(
            sleepHistory: SleepHistorySnapshot,
            currentDaySleep: SleepSummary?,
            hourlySteps: [HealthTrendDataPoint],
            workoutDays: Set<Date>,
            today: Date,
            calendar: Calendar
        ) {
            self.calendar = calendar
            let todayKey = calendar.startOfDay(for: today)

            var summariesByDay: [Date: SleepSummary] = [:]
            for day in sleepHistory.days {
                let key = calendar.startOfDay(for: day.date)
                // A travel day that files two nights on one key keeps the first,
                // same as the Vitals page.
                if summariesByDay[key] == nil {
                    summariesByDay[key] = day.summary
                }
            }
            if summariesByDay[todayKey] == nil, let todaySleep = currentDaySleep?.asOf(today, calendar: calendar) {
                summariesByDay[todayKey] = todaySleep
            }

            var valuesByDayByKind: [BodyRadarSignalKind: [Date: Double]] = [:]
            var nights: Set<Date> = []
            for (day, summary) in summariesByDay {
                guard Context.isNight(summary) else {
                    continue
                }
                nights.insert(day)
                for kind in BodyRadarSignalKind.allCases {
                    guard let value = Context.value(of: kind, in: summary), value.isFinite else {
                        continue
                    }
                    valuesByDayByKind[kind, default: [:]][day] = value
                }
            }

            // Inactive hours for day D describe the day *before* the night is
            // read, so they are filed under D + 1 and line up with the other
            // signals without a separate lookup rule.
            let inactiveByDay = Context.inactiveHours(
                hourlySteps: hourlySteps,
                summariesByDay: summariesByDay,
                workoutDays: Set(workoutDays.map { calendar.startOfDay(for: $0) }),
                calendar: calendar
            )
            for (day, hours) in inactiveByDay {
                guard let filedDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                    continue
                }
                valuesByDayByKind[.inactiveTime, default: [:]][filedDay] = hours
            }

            self.nightDays = nights
            self.series = valuesByDayByKind.reduce(into: [:]) { result, entry in
                let sorted = entry.value.sorted { $0.key < $1.key }
                result[entry.key] = VitalsCalculator.VitalSeries(
                    floor: Context.floor(for: entry.key),
                    valuesByDay: entry.value,
                    days: sorted.map(\.key),
                    values: sorted.map(\.value)
                )
            }
        }

        func night(on day: Date) -> BodyRadarNight {
            guard nightDays.contains(day) else {
                return BodyRadarNight(date: day, state: .missingSleep)
            }

            let oldestDay = calendar.date(
                byAdding: .day,
                value: -ReadinessScoreCalculator.baselineDayCount,
                to: day
            ) ?? day.addingTimeInterval(-Double(ReadinessScoreCalculator.baselineDayCount) * 86_400)
            let recentCutoff = calendar.date(
                byAdding: .day,
                value: -ReadinessScoreCalculator.recentExclusionDayCount,
                to: day
            ) ?? day

            let signals = BodyRadarSignalKind.allCases.compactMap { kind -> BodyRadarSignal? in
                guard let series = series[kind],
                      let value = series.valuesByDay[day],
                      let baseline = VitalsCalculator.windowedBaseline(
                          series: series,
                          scoringDay: day,
                          oldestDay: oldestDay,
                          recentCutoff: recentCutoff
                      ) else {
                    return nil
                }

                let deviation = VitalsCalculator.normalizedDeviation(value: value, baseline: baseline)
                var signal = BodyRadarSignal(kind: kind, deviation: deviation, flagged: false)
                signal.flagged = signal.directionalDeviation > Tuning.flagThreshold
                return signal
            }

            guard !signals.isEmpty, hasRecentNights(endingOn: day) else {
                return BodyRadarNight(date: day, state: .calibrating)
            }

            let evidence = signals.reduce(0) { $0 + BodyRadarCalculator.contribution(of: $1) }
            let flaggedCount = signals.filter(\.flagged).count

            return BodyRadarNight(
                date: day,
                state: BodyRadarCalculator.state(evidence: evidence, flaggedCount: flaggedCount),
                evidence: evidence,
                signals: signals
            )
        }

        /// Oura's recency rule: enough of the last 14 days carried a night with
        /// at least one overnight vital.
        private func hasRecentNights(endingOn day: Date) -> Bool {
            guard let windowStart = calendar.date(
                byAdding: .day,
                value: -(Tuning.recencyWindowDayCount - 1),
                to: day
            ) else {
                return true
            }

            var days: Set<Date> = []
            for kind in BodyRadarSignalKind.allCases where kind != .inactiveTime {
                guard let series = series[kind] else {
                    continue
                }
                for candidate in series.days where candidate >= windowStart && candidate <= day {
                    days.insert(candidate)
                }
            }

            return days.count >= Tuning.recencyMinimumNightCount
        }

        /// A nap or a partial night must not be read as a night. Summaries that
        /// carry vitals but no stages (backfilled history) are trusted as-is.
        private static func isNight(_ summary: SleepSummary) -> Bool {
            guard !summary.stageSnapshot.isEmpty else {
                return !summary.vitals.isEmpty
            }
            guard summary.stageSnapshot.wakeCycleEnd != nil else {
                return false
            }
            return (summary.duration ?? 0) >= Tuning.minimumNightSleepDuration
        }

        private static func value(of kind: BodyRadarSignalKind, in summary: SleepSummary) -> Double? {
            switch kind {
            case .sleepingHeartRate:
                return summary.vitals.heartRate
            case .respiratoryRate:
                return summary.vitals.respiratoryRate
            case .wristTemperature:
                return summary.vitals.wristTemperatureCelsius
            case .heartRateVariability:
                return summary.vitals.heartRateVariability
            case .inactiveTime:
                return nil
            }
        }

        private static func floor(for kind: BodyRadarSignalKind) -> Double {
            switch kind {
            case .sleepingHeartRate:
                return VitalsCalculator.Floor.heartRate
            case .respiratoryRate:
                return VitalsCalculator.Floor.respiratoryRate
            case .wristTemperature:
                return VitalsCalculator.Floor.wristTemperature
            case .heartRateVariability:
                return Tuning.heartRateVariabilityFloor
            case .inactiveTime:
                return Tuning.inactiveHoursFloor
            }
        }

        /// Whole clock hours between that day's wake and 22:00 local that carried
        /// fewer than `inactiveStepsPerHour` steps. Days with a workout are
        /// masked so a rest day does not read as illness, and a day with no step
        /// samples at all is skipped rather than counted as fully inactive.
        private static func inactiveHours(
            hourlySteps: [HealthTrendDataPoint],
            summariesByDay: [Date: SleepSummary],
            workoutDays: Set<Date>,
            calendar: Calendar
        ) -> [Date: Double] {
            guard !hourlySteps.isEmpty else {
                return [:]
            }

            var stepsByHour: [Date: Double] = [:]
            var sampledDays: Set<Date> = []
            for point in hourlySteps where point.value.isFinite {
                guard let hourStart = calendar.dateInterval(of: .hour, for: point.date)?.start else {
                    continue
                }
                stepsByHour[hourStart, default: 0] += point.value
                sampledDays.insert(calendar.startOfDay(for: point.date))
            }

            var hoursByDay: [Date: Double] = [:]
            for (day, summary) in summariesByDay {
                guard sampledDays.contains(day), !workoutDays.contains(day) else {
                    continue
                }
                guard let wake = summary.stageSnapshot.wakeCycleEnd,
                      calendar.isDate(wake, inSameDayAs: day),
                      let windowEnd = calendar.date(
                          bySettingHour: Tuning.inactiveWindowEndHour,
                          minute: 0,
                          second: 0,
                          of: day
                      ),
                      let firstHour = calendar.dateInterval(of: .hour, for: wake)?.end else {
                    continue
                }

                var hour = firstHour
                var inactive = 0.0
                while hour < windowEnd {
                    if (stepsByHour[hour] ?? 0) < Tuning.inactiveStepsPerHour {
                        inactive += 1
                    }
                    guard let next = calendar.date(byAdding: .hour, value: 1, to: hour), next > hour else {
                        break
                    }
                    hour = next
                }

                hoursByDay[day] = inactive
            }

            return hoursByDay
        }
    }
}
