//
//  VitalsSnapshot.swift
//  Body
//

import Foundation

enum VitalKind: String, CaseIterable, Identifiable {
    case sleepingHeartRate
    case respiratoryRate
    case wristTemperature
    case bloodOxygen
    case sleepDuration

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .sleepingHeartRate:
            return String(localized: "Heart Rate", table: "BodyMetricsKit")
        case .respiratoryRate:
            return String(localized: "Respiratory Rate", table: "BodyMetricsKit")
        case .wristTemperature:
            return String(localized: "Skin Temperature", table: "BodyMetricsKit")
        case .bloodOxygen:
            return String(localized: "Blood Oxygen", table: "BodyMetricsKit")
        case .sleepDuration:
            return String(localized: "Sleep Duration", table: "BodyMetricsKit")
        }
    }

    var symbolName: String {
        switch self {
        case .sleepingHeartRate:
            return "heart.fill"
        case .respiratoryRate:
            return "lungs.fill"
        case .wristTemperature:
            return "thermometer.medium"
        case .bloodOxygen:
            return "drop.fill"
        case .sleepDuration:
            return "bed.double.fill"
        }
    }
}

/// One vital on one night, graded against that vital's own baseline. `value` is
/// always in the vital's native unit (bpm, br/min, °C, %, hours).
struct VitalMeasurement: Equatable {
    var kind: VitalKind
    var value: Double
    var baseline: ReadinessScoreCalculator.Baseline
    /// Distance from the baseline median in typical-band half-widths, clamped
    /// to ±`VitalsCalculator.deviationCap`; |deviation| > 1 is an outlier.
    var normalizedDeviation: Double
    var region: SleepVitalRegion
    var referenceRange: SleepVitalReferenceRange
}

struct VitalsNightAssessment: Equatable, Identifiable {
    /// Start of the day the night is filed under.
    var date: Date
    /// Vitals that had both a reading and a baseline that night, in
    /// `VitalKind.allCases` order.
    var measurements: [VitalMeasurement]

    var id: Date {
        date
    }

    var regions: [SleepVitalRegion] {
        measurements.map(\.region)
    }

    var outlierCount: Int {
        measurements.filter { $0.region != .typical }.count
    }

    var minDeviation: Double {
        measurements.map(\.normalizedDeviation).min() ?? 0
    }

    var maxDeviation: Double {
        measurements.map(\.normalizedDeviation).max() ?? 0
    }

    /// Computed rather than stored so a stored snapshot never replays a title
    /// localized for a language the reader has since left.
    var statusText: String {
        SleepVitalStatusTitle.text(for: regions)
    }
}

struct VitalsSnapshot: Equatable {
    /// Ascending by date.
    var nights: [VitalsNightAssessment]

    static let empty = VitalsSnapshot(nights: [])

    var latestNight: VitalsNightAssessment? {
        nights.last
    }

    func nights(in interval: DateInterval) -> [VitalsNightAssessment] {
        nights.filter { interval.contains($0.date) }
    }

    static func statusText(for nights: [VitalsNightAssessment]) -> String {
        SleepVitalStatusTitle.text(for: nights.flatMap(\.regions))
    }
}

enum VitalsCalculator {
    /// Half-width of the personal typical band, in robust spreads: a reading
    /// this far from the median is where "typical" ends and an outlier starts.
    static let typicalBandMultiplier = 2.0
    /// Wide enough that real outlier nights keep distinct magnitudes on the
    /// trend chart instead of saturating together; the band edge stays at ±1.
    static let deviationCap = 3.0

    /// Smallest spread each vital may claim, so a very steady sleeper does not
    /// turn sensor noise into outliers. The first four mirror the readiness
    /// engine's metric floors — see docs/ReadinessMetrics.md.
    enum Floor {
        static let heartRate = 3.0
        static let respiratoryRate = 0.6
        static let oxygenSaturation = 1.0
        static let wristTemperature = 0.2
        static let sleepDurationHours = 0.5
    }

    static func snapshot(
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        today: Date,
        calendar: Calendar
    ) -> VitalsSnapshot {
        let series = seriesByKind(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
            today: today,
            calendar: calendar
        )

        let nights = nightDates(in: series).compactMap { date in
            assessment(on: date, series: series, calendar: calendar)
        }

        return VitalsSnapshot(nights: nights)
    }

    /// Today's night only, for callers that just need the current headline:
    /// baselines are computed for that one night instead of every night in
    /// history. Nil when today's sleep has not arrived (or can't be graded
    /// yet), so a sync delay or a skipped night reads as a placeholder rather
    /// than replaying an older night's status.
    static func currentNightAssessment(
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        today: Date,
        calendar: Calendar
    ) -> VitalsNightAssessment? {
        let series = seriesByKind(
            sleepHistory: sleepHistory,
            currentDaySleep: currentDaySleep,
            today: today,
            calendar: calendar
        )

        return assessment(on: calendar.startOfDay(for: today), series: series, calendar: calendar)
    }

    private struct VitalSeries {
        var floor: Double
        var valuesByDay: [Date: Double]
        var dailyValues: [ReadinessScoreCalculator.DailyValue]
    }

    /// One value per night per vital from the hydrated sleep history, plus the
    /// current day's sleep summary when history does not cover it.
    private static func seriesByKind(
        sleepHistory: SleepHistorySnapshot,
        currentDaySleep: SleepSummary?,
        today: Date,
        calendar: Calendar
    ) -> [VitalKind: VitalSeries] {
        let todayKey = calendar.startOfDay(for: today)
        let todaySleep = currentDaySleep?.asOf(today, calendar: calendar)

        var valuesByDayByKind: [VitalKind: [Date: Double]] = [:]
        for day in sleepHistory.days {
            let dayKey = calendar.startOfDay(for: day.date)
            for kind in VitalKind.allCases {
                guard let value = value(of: kind, in: day.summary) else {
                    continue
                }
                valuesByDayByKind[kind, default: [:]][dayKey] = value
            }
        }

        if let todaySleep {
            for kind in VitalKind.allCases {
                guard valuesByDayByKind[kind]?[todayKey] == nil,
                      let value = value(of: kind, in: todaySleep) else {
                    continue
                }
                valuesByDayByKind[kind, default: [:]][todayKey] = value
            }
        }

        return valuesByDayByKind.reduce(into: [:]) { result, entry in
            result[entry.key] = VitalSeries(
                floor: floor(for: entry.key),
                valuesByDay: entry.value,
                dailyValues: entry.value.map { day, value in
                    ReadinessScoreCalculator.DailyValue(date: day, value: value)
                }
            )
        }
    }

    private static func nightDates(in series: [VitalKind: VitalSeries]) -> [Date] {
        Set(series.values.flatMap(\.valuesByDay.keys)).sorted()
    }

    private static func assessment(
        on date: Date,
        series: [VitalKind: VitalSeries],
        calendar: Calendar
    ) -> VitalsNightAssessment? {
        let measurements = VitalKind.allCases.compactMap { kind -> VitalMeasurement? in
            guard let series = series[kind],
                  let value = series.valuesByDay[date],
                  let baseline = ReadinessScoreCalculator.robustBaseline(
                      for: date,
                      values: series.dailyValues,
                      floor: series.floor,
                      calendar: calendar
                  ) else {
                return nil
            }

            return measurement(kind: kind, value: value, baseline: baseline)
        }

        guard !measurements.isEmpty else {
            return nil
        }

        return VitalsNightAssessment(date: date, measurements: measurements)
    }

    private static func measurement(
        kind: VitalKind,
        value: Double,
        baseline: ReadinessScoreCalculator.Baseline
    ) -> VitalMeasurement {
        let bandHalfWidth = typicalBandMultiplier * baseline.spread
        let deviation = min(max((value - baseline.median) / bandHalfWidth, -deviationCap), deviationCap)

        let region: SleepVitalRegion
        if deviation < -1 {
            region = .low
        } else if deviation > 1 {
            region = .high
        } else {
            region = .typical
        }

        return VitalMeasurement(
            kind: kind,
            value: value,
            baseline: baseline,
            normalizedDeviation: deviation,
            region: region,
            referenceRange: SleepVitalReferenceRange(
                typicalLowerBound: baseline.median - bandHalfWidth,
                typicalUpperBound: baseline.median + bandHalfWidth
            )
        )
    }

    private static func value(of kind: VitalKind, in summary: SleepSummary) -> Double? {
        let value: Double?
        switch kind {
        case .sleepingHeartRate:
            value = summary.vitals.heartRate
        case .respiratoryRate:
            value = summary.vitals.respiratoryRate
        case .wristTemperature:
            value = summary.vitals.wristTemperatureCelsius
        case .bloodOxygen:
            value = summary.vitals.oxygenSaturation
        case .sleepDuration:
            value = summary.duration.flatMap { $0 > 0 ? $0 / 3_600 : nil }
        }

        guard let value, value.isFinite else {
            return nil
        }

        return value
    }

    private static func floor(for kind: VitalKind) -> Double {
        switch kind {
        case .sleepingHeartRate:
            return Floor.heartRate
        case .respiratoryRate:
            return Floor.respiratoryRate
        case .wristTemperature:
            return Floor.wristTemperature
        case .bloodOxygen:
            return Floor.oxygenSaturation
        case .sleepDuration:
            return Floor.sleepDurationHours
        }
    }
}
