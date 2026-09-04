//
//  BodyRadarModels.swift
//  Body
//
//  Body Radar (Beta v1): the overnight signal set, the nightly verdict, and the
//  rolling summary the card and detail page read. Pure value types with no UI
//  dependency so the watch targets can compile the same sources.
//

import Foundation

/// The verdict for one night. `calibrating` and `missingSleep` are the two
/// states that carry no evidence.
enum BodyRadarState: String, Codable, CaseIterable {
    case calibrating
    case missingSleep
    case noSigns
    case minorSigns
    case majorSigns

    /// True once the night was actually scored, so callers can tell a verdict
    /// from a placeholder without matching every case.
    var isScored: Bool {
        switch self {
        case .calibrating, .missingSleep:
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

/// The five overnight signals. Declaration order is the display order.
enum BodyRadarSignalKind: String, Codable, CaseIterable, Identifiable {
    case sleepingHeartRate
    case respiratoryRate
    case wristTemperature
    case heartRateVariability
    case inactiveTime

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

    /// Deviation in the illness direction: HRV counts when it falls, everything
    /// else when it rises.
    var directionalDeviation: Double {
        kind.illnessDirectionIsUp ? deviation : -deviation
    }
}

/// One night's verdict, filed under the start of the wake day.
struct BodyRadarNight: Codable, Equatable, Identifiable {
    var date: Date
    var state: BodyRadarState
    var evidence: Double
    var signals: [BodyRadarSignal]

    var id: Date {
        date
    }

    init(date: Date, state: BodyRadarState, evidence: Double = 0, signals: [BodyRadarSignal] = []) {
        self.date = date
        self.state = state
        self.evidence = evidence
        self.signals = signals
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
