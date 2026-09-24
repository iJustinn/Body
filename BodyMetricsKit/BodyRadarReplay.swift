//
//  BodyRadarReplay.swift
//  Body
//
//  A local export of what Body Radar scored each night: the nightly inputs,
//  every signal's baseline and exclusion reason, and the raw and gated results,
//  so the algorithm can be checked offline. `recomputed` is scored from the
//  sleep cache at export time; `recorded` is the stored frozen array verbatim.
//  The two are never merged: a recomputed night cannot say what the user was
//  shown on that morning.
//

import Foundation

/// The rules a replay scores under, so the same cached inputs can be compared
/// across algorithm versions.
enum BodyRadarRules {
    /// Version 2: respiratory rate counts only when it rises, and there is no
    /// corroboration gate.
    case beta2
    /// The current production rules.
    case beta3

    var version: Int {
        switch self {
        case .beta2:
            return 2
        case .beta3:
            return 3
        }
    }

    /// Deviation in the illness direction under these rules.
    func directionalDeviation(of signal: BodyRadarSignal) -> Double {
        switch self {
        case .beta2:
            return signal.kind.illnessDirectionIsUp ? signal.deviation : -signal.deviation
        case .beta3:
            return signal.directionalDeviation
        }
    }
}

struct BodyRadarReplayExport: Codable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var meta: BodyRadarReplayMeta
    var recomputed: [BodyRadarReplayNight]
    var recorded: [BodyRadarNight]

    /// The file contract: sorted keys, and dates as ISO 8601 in UTC with whole
    /// second precision.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

struct BodyRadarReplayMeta: Codable {
    var exportedAt: Date
    var appVersion: String?
    var build: String?
    var algorithmVersion: Int
    /// The signature the recorded nights were captured under.
    var recordContextSignature: String?
    var calendarIdentifier: String
    var timeZoneIdentifier: String
    /// The Body Radar input context configured at export time. It is not the
    /// set of sources that actually contributed samples, which Body does not keep.
    var configuredSourceSelection: String?
    var notes: [String]

    private enum CodingKeys: String, CodingKey {
        case exportedAt
        case appVersion
        case build
        case algorithmVersion
        case recordContextSignature
        case calendarIdentifier
        case timeZoneIdentifier
        case configuredSourceSelection
        case notes
    }

    /// Optionals are written as literal nulls, never omitted.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(build, forKey: .build)
        try container.encode(algorithmVersion, forKey: .algorithmVersion)
        try container.encode(recordContextSignature, forKey: .recordContextSignature)
        try container.encode(calendarIdentifier, forKey: .calendarIdentifier)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(configuredSourceSelection, forKey: .configuredSourceSelection)
        try container.encode(notes, forKey: .notes)
    }
}

/// One wake day recomputed from the sleep cache.
struct BodyRadarReplayNight: Codable {
    /// Start of the wake day as `yyyy-MM-dd` in the export calendar's time zone.
    var day: String
    var dayEpoch: Int
    /// The main sleep session, or the span of all stages when the cache predates it.
    var sleepStart: Date?
    var sleepEnd: Date?
    var sleepDuration: Double?
    var hasStages: Bool
    var wakeCycleEnd: Date?
    /// One per scoring kind, in display order, scored or not.
    var signals: [BodyRadarReplaySignal]
    /// Null when the night was not scored.
    var rawEvidence: Double?
    var rawState: BodyRadarState
    var flaggedCount: Int?
    /// Null under Beta 2 rules and on unscored nights.
    var corroboration: BodyRadarCorroboration?
    /// The verdict after the gate; equal to `rawState` under Beta 2 rules.
    var state: BodyRadarState
    var rulesVersion: Int
    /// Not kept by Body, so always null.
    var sampleCounts: String?
    var queryCompletion: String?
    var sourceIdentity: String?
    /// The zone the night's stages were recorded in; null when none was recorded.
    var historicalTimeZone: String?

    private enum CodingKeys: String, CodingKey {
        case day
        case dayEpoch
        case sleepStart
        case sleepEnd
        case sleepDuration
        case hasStages
        case wakeCycleEnd
        case signals
        case rawEvidence
        case rawState
        case flaggedCount
        case corroboration
        case state
        case rulesVersion
        case sampleCounts
        case queryCompletion
        case sourceIdentity
        case historicalTimeZone
    }

    /// Optionals are written as literal nulls, never omitted, and a non-finite
    /// number is written as null.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(dayEpoch, forKey: .dayEpoch)
        try container.encode(sleepStart, forKey: .sleepStart)
        try container.encode(sleepEnd, forKey: .sleepEnd)
        try container.encodeFinite(sleepDuration, forKey: .sleepDuration)
        try container.encode(hasStages, forKey: .hasStages)
        try container.encode(wakeCycleEnd, forKey: .wakeCycleEnd)
        try container.encode(signals, forKey: .signals)
        try container.encodeFinite(rawEvidence, forKey: .rawEvidence)
        try container.encode(rawState, forKey: .rawState)
        try container.encode(flaggedCount, forKey: .flaggedCount)
        try container.encode(corroboration, forKey: .corroboration)
        try container.encode(state, forKey: .state)
        try container.encode(rulesVersion, forKey: .rulesVersion)
        try container.encode(sampleCounts, forKey: .sampleCounts)
        try container.encode(queryCompletion, forKey: .queryCompletion)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
        try container.encode(historicalTimeZone, forKey: .historicalTimeZone)
    }
}

/// One signal on one recomputed night, with the baseline it was read against.
struct BodyRadarReplaySignal: Codable {
    var kind: BodyRadarSignalKind
    var unit: String
    var statistic: String
    /// The nightly input; null with `valueReason` when it could not be used.
    var value: Double?
    /// `nonFinite`, `absent`, `notNight`, or null when `value` is present.
    var valueReason: String?
    var baselineMedian: Double?
    /// The spread the deviation divides by, after the floor.
    var baselineSpread: Double?
    /// 1.4826 times the median absolute deviation, before the floor.
    var rawSpread: Double?
    var floor: Double
    /// True when `rawSpread` is below `floor`, so the floor set the spread.
    var floorBound: Bool?
    var baselineCount: Int
    var recentCount: Int
    var deviation: Double?
    var directionalDeviation: Double?
    var contribution: Double?
    var flagged: Bool?
    /// `noBaseline`, `sparseRecent`, `noCurrentValue`, `nonFinite`, `notNight`,
    /// or null when the signal was scored.
    var exclusionReason: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case unit
        case statistic
        case value
        case valueReason
        case baselineMedian
        case baselineSpread
        case rawSpread
        case floor
        case floorBound
        case baselineCount
        case recentCount
        case deviation
        case directionalDeviation
        case contribution
        case flagged
        case exclusionReason
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(unit, forKey: .unit)
        try container.encode(statistic, forKey: .statistic)
        try container.encodeFinite(value, forKey: .value)
        try container.encode(valueReason, forKey: .valueReason)
        try container.encodeFinite(baselineMedian, forKey: .baselineMedian)
        try container.encodeFinite(baselineSpread, forKey: .baselineSpread)
        try container.encodeFinite(rawSpread, forKey: .rawSpread)
        try container.encodeFinite(floor, forKey: .floor)
        try container.encode(floorBound, forKey: .floorBound)
        try container.encode(baselineCount, forKey: .baselineCount)
        try container.encode(recentCount, forKey: .recentCount)
        try container.encodeFinite(deviation, forKey: .deviation)
        try container.encodeFinite(directionalDeviation, forKey: .directionalDeviation)
        try container.encodeFinite(contribution, forKey: .contribution)
        try container.encode(flagged, forKey: .flagged)
        try container.encode(exclusionReason, forKey: .exclusionReason)
    }
}

private extension KeyedEncodingContainer {
    /// Writes a finite number, or a literal null for nil, NaN or infinity, so a
    /// bad reading can never make the encoder throw.
    mutating func encodeFinite(_ value: Double?, forKey key: Key) throws {
        try encode(value.flatMap { $0.isFinite ? $0 : nil }, forKey: key)
    }
}

extension BodyRadarCalculator {
    /// Every night in the sleep cache up to `today`, plus `today`, scored under
    /// `rules` with the diagnostics behind each verdict. `recorded` passes
    /// through untouched. Meta fields the calculator cannot know (app version,
    /// build, signatures) are left nil for the caller to fill in.
    static func replay(
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        recorded: [BodyRadarNight],
        today: Date,
        rules: BodyRadarRules,
        calendar: Calendar = .bodyGregorian
    ) -> BodyRadarReplayExport {
        let context = Context(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
            today: today,
            calendar: calendar
        )
        let todayKey = calendar.startOfDay(for: today)
        let days = context.nightDays.filter { $0 <= todayKey }.union([todayKey]).sorted()

        return BodyRadarReplayExport(
            schemaVersion: BodyRadarReplayExport.schemaVersion,
            meta: BodyRadarReplayMeta(
                exportedAt: Date(),
                appVersion: nil,
                build: nil,
                algorithmVersion: algorithmVersion,
                recordContextSignature: nil,
                calendarIdentifier: (calendar as NSCalendar).calendarIdentifier.rawValue,
                timeZoneIdentifier: calendar.timeZone.identifier,
                configuredSourceSelection: nil,
                notes: replayNotes
            ),
            recomputed: days.map { replayNight(on: $0, context: context, rules: rules) },
            recorded: recorded
        )
    }

    private static let replayNotes = [
        "recomputed is scored from the sleep cache at export time, so late or corrected data can make it differ from what was shown on that morning.",
        "recorded is the stored frozen array as is. A record without capturedAt was captured at an unknown time.",
        "Nightly values are the unweighted mean of samples overlapping the main sleep session. When a query failed, the cached value for that night was kept.",
        "sampleCounts, queryCompletion and sourceIdentity are not kept by Body and are always null.",
        "configuredSourceSelection is the configured input context at export time, not the sources that contributed samples.",
        "rulesVersion 2 replays Beta 2 rules on the same inputs: respiratory rate counts only when it rises, and there is no corroboration gate."
    ]

    private static func replayNight(
        on day: Date,
        context: Context,
        rules: BodyRadarRules
    ) -> BodyRadarReplayNight {
        let calendar = context.calendar
        let summary = context.summariesByDay[day]
        let isNight = context.nightDays.contains(day)
        let window = context.baselineWindow(endingOn: day)

        let evaluated = context.signalEvaluations(on: day).map { evaluation in
            replaySignal(
                evaluation,
                input: summary.flatMap { Context.value(of: evaluation.kind, in: $0) },
                isNight: isNight,
                series: context.series[evaluation.kind],
                day: day,
                window: window,
                rules: rules
            )
        }
        let signals = evaluated.map { $0.row }

        let raw = context.rawNight(on: day)
        let rawEvidence: Double?
        let flaggedCount: Int?
        let rawState: BodyRadarState
        let state: BodyRadarState
        let corroboration: BodyRadarCorroboration?
        if raw.state.isScored {
            let scored = evaluated.compactMap { $0.scored }
            let evidence = scored.reduce(0) { $0 + $1.contribution }
            let flagged = scored.filter { $0.flagged }.count
            rawEvidence = evidence
            flaggedCount = flagged
            rawState = BodyRadarCalculator.state(evidence: evidence, flaggedCount: flagged, corroborated: true)
            switch rules {
            case .beta2:
                state = rawState
                corroboration = nil
            case .beta3:
                let night = context.night(on: day)
                state = night.state
                corroboration = night.corroboration
            }
        } else {
            rawEvidence = nil
            flaggedCount = nil
            rawState = raw.state
            state = raw.state
            corroboration = nil
        }

        let stages = summary?.stageSnapshot
        let interval = stages?.mainSessionInterval ?? stages?.dateInterval
        let components = calendar.dateComponents([.year, .month, .day], from: day)

        return BodyRadarReplayNight(
            day: String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            ),
            dayEpoch: Int(day.timeIntervalSince1970),
            sleepStart: interval?.start,
            sleepEnd: interval?.end,
            sleepDuration: summary?.duration,
            hasStages: !(stages?.isEmpty ?? true),
            wakeCycleEnd: stages?.wakeCycleEnd,
            signals: signals,
            rawEvidence: rawEvidence,
            rawState: rawState,
            flaggedCount: flaggedCount,
            corroboration: corroboration,
            state: state,
            rulesVersion: rules.version,
            sampleCounts: nil,
            queryCompletion: nil,
            sourceIdentity: nil,
            historicalTimeZone: stages?.timeZoneIdentifier
        )
    }

    private static func replaySignal(
        _ evaluation: Context.SignalEvaluation,
        input: Double?,
        isNight: Bool,
        series: VitalsCalculator.VitalSeries?,
        day: Date,
        window: (oldestDay: Date, recentCutoff: Date),
        rules: BodyRadarRules
    ) -> (row: BodyRadarReplaySignal, scored: (contribution: Double, flagged: Bool)?) {
        let kind = evaluation.kind
        let floor = Context.floor(for: kind)

        // A nap day is never read, so its readings are not reported as inputs.
        var value: Double?
        let valueReason: String?
        if !isNight {
            valueReason = "notNight"
        } else if let input {
            value = input.isFinite ? input : nil
            valueReason = input.isFinite ? nil : "nonFinite"
        } else {
            valueReason = "absent"
        }

        let exclusionReason: String?
        if !isNight {
            exclusionReason = "notNight"
        } else if evaluation.exclusion == .noCurrentValue, valueReason == "nonFinite" {
            exclusionReason = "nonFinite"
        } else {
            exclusionReason = evaluation.exclusion?.rawValue
        }

        let spread = series.map { baselineSpread(of: $0, scoringDay: day, window: window) }
        var row = BodyRadarReplaySignal(
            kind: kind,
            unit: replayUnit(of: kind),
            statistic: replayStatistic(of: kind),
            value: value,
            valueReason: valueReason,
            baselineMedian: evaluation.baseline?.median,
            baselineSpread: evaluation.baseline?.spread,
            rawSpread: spread?.rawSpread,
            floor: floor,
            floorBound: spread?.rawSpread.map { $0 < floor },
            baselineCount: spread?.count ?? 0,
            recentCount: evaluation.recentNightCount,
            deviation: nil,
            directionalDeviation: nil,
            contribution: nil,
            flagged: nil,
            exclusionReason: exclusionReason
        )

        guard let signal = evaluation.signal else {
            return (row, nil)
        }
        let directional = rules.directionalDeviation(of: signal)
        let contribution = Tuning.weight(for: kind) * max(0, directional - Tuning.deadZone)
        let flagged = directional > Tuning.flagThreshold
        row.deviation = signal.deviation
        row.directionalDeviation = directional
        row.contribution = contribution
        row.flagged = flagged
        return (row, (contribution, flagged))
    }

    /// The same window `VitalsCalculator.windowedBaseline` reads, reporting its
    /// size and the spread before the floor is applied.
    private static func baselineSpread(
        of series: VitalsCalculator.VitalSeries,
        scoringDay: Date,
        window: (oldestDay: Date, recentCutoff: Date)
    ) -> (count: Int, rawSpread: Double?) {
        let days = series.days
        let start = days.firstIndex { $0 >= window.oldestDay } ?? days.count
        let end = days.firstIndex { $0 >= scoringDay } ?? days.count
        let cutoff = min(max(days.firstIndex { $0 >= window.recentCutoff } ?? days.count, start), end)
        let range = (cutoff - start) >= 28 ? start..<cutoff : start..<end
        guard range.count >= ReadinessScoreCalculator.minimumBaselineDayCount else {
            return (range.count, nil)
        }

        let values = series.values[range].sorted()
        let median = ReadinessScoreCalculator.median(values)
        let deviations = values.map { abs($0 - median) }.sorted()
        return (range.count, 1.4826 * ReadinessScoreCalculator.median(deviations))
    }

    private static func replayUnit(of kind: BodyRadarSignalKind) -> String {
        switch kind {
        case .sleepingHeartRate, .respiratoryRate:
            return "count/min"
        case .heartRateVariability:
            return "ms"
        case .wristTemperature:
            return "degC"
        case .inactiveTime:
            return ""
        }
    }

    private static func replayStatistic(of kind: BodyRadarSignalKind) -> String {
        switch kind {
        case .sleepingHeartRate:
            return "mean of heart rate samples overlapping the main sleep session"
        case .respiratoryRate:
            return "mean of respiratory rate samples overlapping the main sleep session"
        case .wristTemperature:
            return "mean of sleeping wrist temperature samples overlapping the main sleep session"
        case .heartRateVariability:
            return "mean of SDNN samples overlapping the main sleep session"
        case .inactiveTime:
            return ""
        }
    }
}
