//
//  BodyRadarModels.swift
//  Body
//
//  Body Radar (Beta v3): the overnight signal set, the nightly verdict, and the
//  rolling summary the card and detail page read. Pure value types with no UI
//  dependency so the watch targets can compile the same sources.
//

import Foundation

/// Unscored states distinguish baseline learning, absent sleep and sparse vitals.
enum BodyRadarState: String, Codable, CaseIterable {
    case calibrating
    case missingSleep
    case insufficientData
    case noSigns
    case minorSigns
    case majorSigns

    /// True once the night was actually scored, so callers can tell a verdict
    /// from a placeholder without matching every case.
    var isScored: Bool {
        switch self {
        case .calibrating, .missingSleep, .insufficientData:
            return false
        case .noSigns, .minorSigns, .majorSigns:
            return true
        }
    }

    var title: String {
        switch self {
        case .calibrating:
            return String(
                localized: "bodyRadar.state.calibrating",
                defaultValue: "Calibrating",
                table: "BodyMetricsKit"
            )
        case .missingSleep:
            return String(
                localized: "bodyRadar.state.missingSleep",
                defaultValue: "Missing Sleep",
                table: "BodyMetricsKit"
            )
        case .noSigns:
            return String(
                localized: "bodyRadar.state.noSigns",
                defaultValue: "No Signs",
                table: "BodyMetricsKit"
            )
        case .insufficientData:
            return String(
                localized: "bodyRadar.state.insufficientData",
                defaultValue: "Insufficient Data",
                table: "BodyMetricsKit"
            )
        case .minorSigns:
            return String(
                localized: "bodyRadar.state.minorSigns",
                defaultValue: "Minor Signs",
                table: "BodyMetricsKit"
            )
        case .majorSigns:
            return String(
                localized: "bodyRadar.state.majorSigns",
                defaultValue: "Major Signs",
                table: "BodyMetricsKit"
            )
        }
    }
}

/// Bands of the detail chart, drawn top to bottom Major / Minor / None. Distinct
/// from `SleepVitalRegion`, which grades one vital rather than a whole night.
enum BodyRadarRegion: String, Codable, CaseIterable {
    case none
    case minor
    case major

    var title: String {
        switch self {
        case .none:
            return String(
                localized: "bodyRadar.region.none",
                defaultValue: "None",
                table: "BodyMetricsKit"
            )
        case .minor:
            return String(
                localized: "bodyRadar.region.minor",
                defaultValue: "Minor",
                table: "BodyMetricsKit"
            )
        case .major:
            return String(
                localized: "bodyRadar.region.major",
                defaultValue: "Major",
                table: "BodyMetricsKit"
            )
        }
    }
}

/// Declaration order is the display order. Inactivity remains decodable for
/// legacy records, but Beta 2 scores only the four overnight physiological signals.
enum BodyRadarSignalKind: String, Codable, CaseIterable, Identifiable {
    case sleepingHeartRate
    case respiratoryRate
    case wristTemperature
    case heartRateVariability
    case inactiveTime

    static let scoringKinds: [Self] = [
        .sleepingHeartRate, .respiratoryRate, .wristTemperature, .heartRateVariability
    ]

    var id: String {
        rawValue
    }

    /// Which way the signal moves when the body is fighting something: every
    /// signal but HRV rises.
    var illnessDirectionIsUp: Bool {
        self != .heartRateVariability
    }

    var title: String {
        switch self {
        case .wristTemperature:
            return String(
                localized: "bodyRadar.signal.wristTemperature",
                defaultValue: "Skin Temperature",
                table: "BodyMetricsKit"
            )
        case .respiratoryRate:
            return String(
                localized: "bodyRadar.signal.respiratoryRate",
                defaultValue: "Respiratory Rate",
                table: "BodyMetricsKit"
            )
        case .sleepingHeartRate:
            return String(
                localized: "bodyRadar.signal.sleepingHeartRate",
                defaultValue: "Sleeping Heart Rate",
                table: "BodyMetricsKit"
            )
        case .heartRateVariability:
            return String(
                localized: "bodyRadar.signal.heartRateVariability",
                defaultValue: "Heart Rate Variability",
                table: "BodyMetricsKit"
            )
        case .inactiveTime:
            return String(
                localized: "bodyRadar.signal.inactiveTime",
                defaultValue: "Inactive Time",
                table: "BodyMetricsKit"
            )
        }
    }

    /// Short enough to list two or three of them on the card's unit line.
    var shortTitle: String {
        switch self {
        case .wristTemperature:
            return String(
                localized: "bodyRadar.signal.wristTemperature.short",
                defaultValue: "Temp",
                table: "BodyMetricsKit"
            )
        case .respiratoryRate:
            return String(
                localized: "bodyRadar.signal.respiratoryRate.short",
                defaultValue: "Resp Rate",
                table: "BodyMetricsKit"
            )
        case .sleepingHeartRate:
            return String(
                localized: "bodyRadar.signal.sleepingHeartRate.short",
                defaultValue: "Heart Rate",
                table: "BodyMetricsKit"
            )
        case .heartRateVariability:
            return String(
                localized: "bodyRadar.signal.heartRateVariability.short",
                defaultValue: "HRV",
                table: "BodyMetricsKit"
            )
        case .inactiveTime:
            return String(
                localized: "bodyRadar.signal.inactiveTime.short",
                defaultValue: "Inactivity",
                table: "BodyMetricsKit"
            )
        }
    }

    /// The body system a signal reads. Same-night corroboration needs two
    /// families, so heart rate and HRV moving together count once. Inactivity
    /// has no family and never corroborates.
    var family: BodyRadarSignalFamily? {
        switch self {
        case .sleepingHeartRate, .heartRateVariability:
            return .autonomic
        case .respiratoryRate:
            return .respiratory
        case .wristTemperature:
            return .thermal
        case .inactiveTime:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .wristTemperature:
            return "thermometer.medium"
        case .respiratoryRate:
            return "lungs.fill"
        case .sleepingHeartRate:
            return "heart.fill"
        case .heartRateVariability:
            return "waveform.path.ecg"
        case .inactiveTime:
            return "figure.seated.side"
        }
    }
}

/// Groups of signals that corroborate each other only across groups.
enum BodyRadarSignalFamily {
    case autonomic
    case respiratory
    case thermal
}

/// Why a scored night may show Minor or Major signs: two families moved on the
/// same night, or the previous night's raw evidence was already elevated.
/// `none` on a night whose raw evidence reached Minor means it was held.
enum BodyRadarCorroboration: String, Codable {
    case sameNight
    case persistence
    case none
}

/// How a night entered the recorded array: frozen on its own day, or
/// recomputed later for the recent-nights chart.
enum BodyRadarCapture: String, Codable {
    case freeze
    case backfill
}

/// One signal on one night. `deviation` keeps the signal's native direction
/// (positive means the reading was above the personal median), so the detail
/// page can draw an up or down arrow without re-deriving it.
struct BodyRadarSignal: Codable, Equatable, Identifiable {
    var kind: BodyRadarSignalKind
    var deviation: Double
    var flagged: Bool

    var id: String {
        kind.rawValue
    }

    /// Deviation in the illness direction: HRV counts when it falls,
    /// respiratory rate in either direction, everything else when it rises.
    var directionalDeviation: Double {
        if kind == .respiratoryRate {
            return abs(deviation)
        }
        return kind.illnessDirectionIsUp ? deviation : -deviation
    }
}

/// One night's verdict, filed under the start of the wake day.
struct BodyRadarNight: Codable, Equatable, Identifiable {
    var date: Date
    var state: BodyRadarState
    var evidence: Double
    var signals: [BodyRadarSignal]
    /// Absent in Beta 1 payloads. Old results can be decoded, but never reused
    /// as a verdict from the current algorithm.
    var algorithmVersion: Int?
    /// Set by the calculator on every scored night; absent in version 2 payloads.
    var corroboration: BodyRadarCorroboration?
    /// When and how the night was recorded; absent on live nights and in
    /// version 2 payloads.
    var capturedAt: Date?
    var capture: BodyRadarCapture?

    var id: Date {
        date
    }

    init(
        date: Date,
        state: BodyRadarState,
        evidence: Double = 0,
        signals: [BodyRadarSignal] = [],
        corroboration: BodyRadarCorroboration? = nil
    ) {
        self.date = date
        self.state = state
        self.evidence = evidence
        self.signals = signals
        self.algorithmVersion = BodyRadarCalculator.algorithmVersion
        self.corroboration = corroboration
    }

    var isCurrentAlgorithm: Bool {
        algorithmVersion == BodyRadarCalculator.algorithmVersion
    }

    /// A night whose raw evidence reached Minor but found no corroboration
    /// shows No Signs; say why rather than leave it reading as typical.
    var holdExplanation: String? {
        guard state == .noSigns, evidence >= BodyRadarCalculator.Tuning.minorEvidence else {
            return nil
        }
        return String(
            localized: "bodyRadar.heldNight",
            defaultValue: "Changes on one night only, not enough to confirm strain",
            table: "BodyMetricsKit"
        )
    }

    /// A combination can cross the Minor threshold without an individual
    /// signal crossing its callout threshold. Never describe that as typical.
    var unflaggedExplanation: String {
        if let holdExplanation {
            return holdExplanation
        }
        if !state.isScored {
            return state.title
        }
        if state == .minorSigns || state == .majorSigns {
            return String(
                localized: "bodyRadar.combinedChanges",
                defaultValue: "Several small changes suggest strain",
                table: "BodyMetricsKit"
            )
        }
        return String(
            localized: "bodyRadar.allTypical",
            defaultValue: "All typical",
            table: "BodyMetricsKit"
        )
    }

    var flaggedSignals: [BodyRadarSignal] {
        signals.filter(\.flagged)
    }

    var region: BodyRadarRegion {
        switch state {
        case .majorSigns:
            return .major
        case .minorSigns:
            return .minor
        default:
            return .none
        }
    }
}

/// What the card and detail page read: the frozen night to show now, plus the
/// recent nights behind the preview chart.
struct BodyRadarSummary: Codable, Equatable {
    /// Always a frozen record (or a calibrating / missing-sleep placeholder),
    /// never a live re-score of the current day.
    var latest: BodyRadarNight?
    /// Ascending by date, at most `BodyRadarCalculator.Tuning.recentNightCount`.
    var recentNights: [BodyRadarNight]

    init(latest: BodyRadarNight? = nil, recentNights: [BodyRadarNight] = []) {
        self.latest = latest
        self.recentNights = recentNights
    }

    static let empty = BodyRadarSummary(latest: nil, recentNights: [])

    var state: BodyRadarState {
        latest?.state ?? .calibrating
    }

    /// One point per night, valued by evidence, for the card's line preview.
    func evidenceSeries() -> HealthTrendSeries {
        HealthTrendSeries(
            points: recentNights
                .filter { $0.state.isScored }
                .map { HealthTrendDataPoint(date: $0.date, value: $0.evidence) }
        )
    }
}
