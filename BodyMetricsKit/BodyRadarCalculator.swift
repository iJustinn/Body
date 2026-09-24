//
//  BodyRadarCalculator.swift
//  Body
//
//  Body Radar (Beta v3) engine: grades four overnight signals against the same
//  56-day robust baseline the Vitals page uses, sums directional evidence, lets
//  it alert only when two signal families or two adjacent nights agree, and
//  freezes one verdict per day the way the readiness morning record is frozen.
//
//  Not a medical device: this reports deviations from a personal baseline, it
//  does not diagnose anything.
//

import Foundation

enum BodyRadarCalculator {
    static let algorithmVersion = 3

    enum Tuning {
        /// Fixed signal weights; inactivity is retained only for legacy decoding.
        static func weight(for kind: BodyRadarSignalKind) -> Double {
            switch kind {
            case .wristTemperature:
                return 1.5
            case .respiratoryRate, .sleepingHeartRate, .heartRateVariability:
                return 1.0
            case .inactiveTime:
                return 0
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
        /// Same-night corroboration: a family (heart signals, breathing,
        /// temperature) counts once its summed contribution reaches this, and
        /// two families must count.
        static let familyContributionMinimum = 0.25
        /// Persistence: the previous calendar night's raw evidence, from any
        /// signal in any direction, that lets a single family alert tonight.
        static let persistenceEvidence = minorEvidence

        /// Robust-spread floor for overnight SDNN, matching
        /// `StressScoreCalculator.Tuning.hrvSpreadFloor`.
        static let heartRateVariabilityFloor = 5.0
        /// Each scored signal needs recent observations as well as a baseline.
        static let recencyWindowDayCount = 14
        static let recencyMinimumNightCount = 7
        static let minimumSignalCount = 2
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
        // An unavailable current night must not inherit yesterday's reassurance.
        // A scored night awaiting its freeze time may still show yesterday.
        let latest = recordsByDay[scoringDay]
            ?? (tonight.state.isScored ? recordsByDay[yesterday] : nil)
            ?? BodyRadarNight(
                date: scoringDay,
                state: tonight.state.isScored ? .calibrating : tonight.state
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
            } else if day < scoringDay || !tonight.state.isScored {
                // Unscored days stay in, so the chart keeps a slot for every
                // night and can show where data or a verdict was missing.
                var night = context.night(on: day)
                if night.state.isScored {
                    night.capturedAt = now
                    night.capture = .backfill
                    backfilled.append(night)
                }
                recent.append(night)
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
        today: Date,
        calendar: Calendar = .bodyGregorian
    ) -> BodyRadarNight {
        Context(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
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
    /// changed vitals cannot rewrite the morning's answer. Unscored nights are
    /// never frozen, so late sleep or vital sync can still fill the day in.
    static func freezing(
        records: [BodyRadarNight],
        night: BodyRadarNight,
        now: Date,
        wakeTime: Date?,
        scoringDay: Date,
        calendar: Calendar = .bodyGregorian
    ) -> [BodyRadarNight] {
        let scoringDay = calendar.startOfDay(for: scoringDay)
        let records = records.filter { $0.isCurrentAlgorithm && $0.state.isScored }
        guard night.isCurrentAlgorithm, night.state.isScored else {
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
        frozen.capturedAt = now
        frozen.capture = .freeze
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

    /// An uncorroborated night is held at No Signs whatever its evidence.
    static func state(evidence: Double, flaggedCount: Int, corroborated: Bool) -> BodyRadarState {
        guard corroborated else {
            return .noSigns
        }
        if evidence >= Tuning.majorEvidence, flaggedCount >= Tuning.majorFlaggedSignalCount {
            return .majorSigns
        }
        if evidence >= Tuning.minorEvidence {
            return .minorSigns
        }
        return .noSigns
    }

    /// Each family's summed contribution; inactivity belongs to none.
    static func familyContributions(of signals: [BodyRadarSignal]) -> [BodyRadarSignalFamily: Double] {
        signals.reduce(into: [:]) { sums, signal in
            guard let family = signal.kind.family else {
                return
            }
            sums[family, default: 0] += contribution(of: signal)
        }
    }

    /// The support a scored night has: two families moving on the same night,
    /// otherwise a previous calendar night that was scored with raw evidence
    /// of at least `persistenceEvidence`. `previousRawNight` must be the
    /// ungated night, so support never chains further back than one day.
    static func corroboration(
        signals: [BodyRadarSignal],
        previousRawNight: BodyRadarNight?
    ) -> BodyRadarCorroboration {
        let corroboratingFamilies = familyContributions(of: signals).values
            .filter { $0 >= Tuning.familyContributionMinimum }
            .count
        if corroboratingFamilies >= 2 {
            return .sameNight
        }
        if let previousRawNight,
           previousRawNight.state.isScored,
           previousRawNight.evidence >= Tuning.persistenceEvidence {
            return .persistence
        }
        return .none
    }

    // MARK: - Context

    /// The per-signal day series a run of nights is scored against, built once
    /// so scoring the recent nights does not rebuild the history once per night.
    /// Internal rather than private so the replay exporter reads the same inputs.
    struct Context {
        /// Ungated nights by day, shared by every copy of one context so a
        /// night and the next night's persistence lookup score it once.
        private final class RawNightCache {
            var nightsByDay: [Date: BodyRadarNight] = [:]
        }

        /// Why a signal was left out of a night's score.
        enum SignalExclusion: String {
            case noBaseline
            case sparseRecent
            case noCurrentValue
        }

        /// One signal's inputs on one night: the baseline it is read against,
        /// its recent observations, and the scored signal when it has a value.
        struct SignalEvaluation {
            let kind: BodyRadarSignalKind
            let baseline: ReadinessScoreCalculator.Baseline?
            let recentNightCount: Int
            let signal: BodyRadarSignal?
            let exclusion: SignalExclusion?

            /// Has a baseline and recent nights, whether or not tonight has a value.
            var isCalibrated: Bool {
                exclusion == nil || exclusion == .noCurrentValue
            }
        }

        let series: [BodyRadarSignalKind: VitalsCalculator.VitalSeries]
        /// Days that hold a night worth scoring, keyed by start of the wake day.
        let nightDays: Set<Date>
        /// Every day's summary before the night and finite-value filters, so the
        /// replay can report why a value was left out.
        let summariesByDay: [Date: SleepSummary]
        let calendar: Calendar
        private let rawNights = RawNightCache()

        init(
            sleepHistory: SleepHistorySnapshot,
            currentDaySleep: SleepSummary?,
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
                for kind in BodyRadarSignalKind.scoringKinds {
                    guard let value = Context.value(of: kind, in: summary), value.isFinite else {
                        continue
                    }
                    valuesByDayByKind[kind, default: [:]][day] = value
                }
            }

            self.nightDays = nights
            self.summariesByDay = summariesByDay
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

        /// The gated verdict: the raw night, held at No Signs when neither a
        /// second family nor the previous night's raw evidence supports it.
        func night(on day: Date) -> BodyRadarNight {
            var night = rawNight(on: day)
            guard night.state.isScored else {
                return night
            }

            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)
                .map { calendar.startOfDay(for: $0) }
            let corroboration = BodyRadarCalculator.corroboration(
                signals: night.signals,
                previousRawNight: previousDay.map(rawNight(on:))
            )
            night.corroboration = corroboration
            night.state = BodyRadarCalculator.state(
                evidence: night.evidence,
                flaggedCount: night.flaggedSignals.count,
                corroborated: corroboration != .none
            )
            return night
        }

        /// The night scored on its own evidence and flags, with no gate.
        func rawNight(on day: Date) -> BodyRadarNight {
            if let cached = rawNights.nightsByDay[day] {
                return cached
            }
            let night = scoreRawNight(on: day)
            rawNights.nightsByDay[day] = night
            return night
        }

        private func scoreRawNight(on day: Date) -> BodyRadarNight {
            guard nightDays.contains(day) else {
                return BodyRadarNight(date: day, state: .missingSleep)
            }

            let evaluations = signalEvaluations(on: day)
            let calibratedSignalCount = evaluations.filter(\.isCalibrated).count
            let signals = evaluations.compactMap(\.signal)

            guard calibratedSignalCount >= Tuning.minimumSignalCount else {
                return BodyRadarNight(date: day, state: .calibrating)
            }
            guard signals.count >= Tuning.minimumSignalCount else {
                return BodyRadarNight(date: day, state: .insufficientData)
            }

            let evidence = signals.reduce(0) { $0 + BodyRadarCalculator.contribution(of: $1) }
            let flaggedCount = signals.filter(\.flagged).count

            return BodyRadarNight(
                date: day,
                state: BodyRadarCalculator.state(
                    evidence: evidence,
                    flaggedCount: flaggedCount,
                    corroborated: true
                ),
                evidence: evidence,
                signals: signals
            )
        }

        /// The baseline window edges for one night: the oldest day it reads and
        /// the start of the recent days it leaves out once enough history remains.
        func baselineWindow(endingOn day: Date) -> (oldestDay: Date, recentCutoff: Date) {
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
            return (oldestDay, recentCutoff)
        }

        /// Every scoring kind on one night, in display order, scored or not.
        func signalEvaluations(on day: Date) -> [SignalEvaluation] {
            let window = baselineWindow(endingOn: day)
            return BodyRadarSignalKind.scoringKinds.map { kind in
                guard let series = series[kind] else {
                    return SignalEvaluation(
                        kind: kind,
                        baseline: nil,
                        recentNightCount: 0,
                        signal: nil,
                        exclusion: .noBaseline
                    )
                }
                let recentNightCount = recentNightCount(in: series, endingOn: day)
                guard let baseline = VitalsCalculator.windowedBaseline(
                    series: series,
                    scoringDay: day,
                    oldestDay: window.oldestDay,
                    recentCutoff: window.recentCutoff
                ) else {
                    return SignalEvaluation(
                        kind: kind,
                        baseline: nil,
                        recentNightCount: recentNightCount,
                        signal: nil,
                        exclusion: .noBaseline
                    )
                }
                guard recentNightCount >= Tuning.recencyMinimumNightCount else {
                    return SignalEvaluation(
                        kind: kind,
                        baseline: baseline,
                        recentNightCount: recentNightCount,
                        signal: nil,
                        exclusion: .sparseRecent
                    )
                }
                guard let value = series.valuesByDay[day] else {
                    return SignalEvaluation(
                        kind: kind,
                        baseline: baseline,
                        recentNightCount: recentNightCount,
                        signal: nil,
                        exclusion: .noCurrentValue
                    )
                }
                let deviation = VitalsCalculator.normalizedDeviation(value: value, baseline: baseline)
                var signal = BodyRadarSignal(kind: kind, deviation: deviation, flagged: false)
                signal.flagged = signal.directionalDeviation > Tuning.flagThreshold
                return SignalEvaluation(
                    kind: kind,
                    baseline: baseline,
                    recentNightCount: recentNightCount,
                    signal: signal,
                    exclusion: nil
                )
            }
        }

        /// Count this channel's observations, not the union of unrelated sensors.
        private func recentNightCount(in series: VitalsCalculator.VitalSeries, endingOn day: Date) -> Int {
            guard let windowStart = calendar.date(
                byAdding: .day,
                value: -(Tuning.recencyWindowDayCount - 1),
                to: day
            ) else {
                return 0
            }
            return series.days.filter { $0 >= windowStart && $0 <= day }.count
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

        static func value(of kind: BodyRadarSignalKind, in summary: SleepSummary) -> Double? {
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

        static func floor(for kind: BodyRadarSignalKind) -> Double {
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
                return 1 // Legacy kind; never enters a Beta 2 series.
            }
        }
    }
}
