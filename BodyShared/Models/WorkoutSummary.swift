//
//  WorkoutSummary.swift
//  Body
//

import Foundation

struct WorkoutHeartRateSample: Codable, Equatable, Identifiable {
    let date: Date
    let beatsPerMinute: Double

    var id: String {
        "\(date.timeIntervalSince1970)-\(beatsPerMinute)"
    }
}

struct WorkoutSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let type: BodyWorkoutType
    let startDate: Date
    let duration: TimeInterval
    let activeEnergyKilocalories: Double?
    let totalEnergyKilocalories: Double?
    let distanceMeters: Double?
    let averageHeartRateBeatsPerMinute: Double?
    let effortLevel: Double?
    let heartRateSamples: [WorkoutHeartRateSample]?
    let sourceName: String

    init(
        id: UUID = UUID(),
        type: BodyWorkoutType,
        startDate: Date,
        duration: TimeInterval,
        activeEnergyKilocalories: Double? = nil,
        totalEnergyKilocalories: Double? = nil,
        distanceMeters: Double? = nil,
        averageHeartRateBeatsPerMinute: Double? = nil,
        effortLevel: Double? = nil,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        sourceName: String = "Apple Health"
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.duration = duration
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.totalEnergyKilocalories = totalEnergyKilocalories
        self.distanceMeters = distanceMeters
        self.averageHeartRateBeatsPerMinute = averageHeartRateBeatsPerMinute
        self.effortLevel = effortLevel
        self.heartRateSamples = heartRateSamples
        self.sourceName = sourceName
    }
}

struct WorkoutDetailMetric: Equatable {
    let title: String
    let value: String
}

enum WorkoutEffortIntensity: Equatable {
    case easy
    case moderate
    case hard
    case allOut
}

struct WorkoutEffortPresentation: Equatable {
    let normalizedScore: Double
    let valueText: String
    let descriptor: String
    let intensity: WorkoutEffortIntensity
    let segmentFills: [Double]

    init?(score: Double, locale: Locale = .current) {
        guard score.isFinite else {
            return nil
        }

        let normalizedScore = min(max(score, 1), 10)
        let roundedScore = Int(normalizedScore.rounded())
        let valueText: String
        self.normalizedScore = normalizedScore

        if abs(normalizedScore - Double(roundedScore)) < 0.05 {
            valueText = "\(roundedScore)"
        } else {
            valueText = BodyValueFormat.numberText(normalizedScore, decimals: 1, locale: locale)
        }
        self.valueText = valueText

        switch normalizedScore {
        case ..<4:
            descriptor = "Easy"
            intensity = .easy
        case ..<7:
            descriptor = "Moderate"
            intensity = .moderate
        case ..<9:
            descriptor = "Hard"
            intensity = .hard
        default:
            descriptor = "All Out"
            intensity = .allOut
        }

        segmentFills = (0..<5).map { index in
            min(max((normalizedScore - Double(index * 2)) / 2, 0), 1)
        }
    }
}

struct WorkoutDetailPresentation: Equatable {
    let title: String
    let dateTitle: String
    let timeRangeText: String
    let durationClockText: String
    let compactDurationText: String
    let activeEnergyText: String?
    let totalEnergyText: String?
    let averageHeartRateText: String?
    let distanceText: String?
    let effortText: String
    let effortPresentation: WorkoutEffortPresentation?
    let detailMetrics: [WorkoutDetailMetric]
    let heartRateSamples: [WorkoutHeartRateSample]
    let sourceText: String

    init(
        workout: WorkoutSummary,
        calendar: Calendar = .bodyGregorian,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        unitPreference: BodyValueFormat.UnitPreference = .system
    ) {
        let endDate = workout.startDate.addingTimeInterval(max(0, workout.duration))

        title = workout.type.displayName
        dateTitle = Self.formattedDate(
            workout.startDate,
            dateFormat: "EEE, MMM d",
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        timeRangeText = [
            Self.formattedDate(
                workout.startDate,
                dateFormat: "HH:mm",
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            Self.formattedDate(
                endDate,
                dateFormat: "HH:mm",
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        ].joined(separator: "-")
        durationClockText = BodyValueFormat.stopwatchDurationText(for: workout.duration)
        compactDurationText = BodyValueFormat.durationText(for: workout.duration)
        activeEnergyText = workout.activeEnergyKilocalories.map {
            BodyValueFormat.energyText(kilocalories: $0, locale: locale)
        }
        totalEnergyText = workout.totalEnergyKilocalories.map {
            BodyValueFormat.energyText(kilocalories: $0, locale: locale)
        }
        let storedHeartRate = workout.averageHeartRateBeatsPerMinute
        let sortedHeartRateSamples = (workout.heartRateSamples ?? [])
            .sorted { $0.date < $1.date }
        let computedHeartRate = Self.averageHeartRate(from: sortedHeartRateSamples)
        averageHeartRateText = (storedHeartRate ?? computedHeartRate).map {
            BodyValueFormat.heartRateText(beatsPerMinute: $0, locale: locale)
        }
        distanceText = workout.distanceMeters.flatMap { distanceMeters in
            guard distanceMeters > 0 else {
                return nil
            }

            return BodyValueFormat.distanceText(
                meters: distanceMeters,
                locale: locale,
                unitPreference: unitPreference
            )
        }
        sourceText = workout.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Apple Health"
            : workout.sourceName
        effortPresentation = workout.effortLevel.flatMap {
            WorkoutEffortPresentation(score: $0, locale: locale)
        }
        effortText = effortPresentation.map { "\($0.valueText) \($0.descriptor)" } ?? "No Saved Effort"
        heartRateSamples = sortedHeartRateSamples

        var metrics = [
            WorkoutDetailMetric(title: "Active Kcal", value: activeEnergyText ?? "No Data"),
            WorkoutDetailMetric(title: "Total Kcal", value: totalEnergyText ?? "No Data"),
            WorkoutDetailMetric(title: "Avg Heart Rate", value: averageHeartRateText ?? "No Data")
        ]
        if let distanceText {
            metrics.append(WorkoutDetailMetric(title: "Distance", value: distanceText))
        }
        detailMetrics = metrics
    }

    private static func formattedDate(
        _ date: Date,
        dateFormat: String,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }

    private static func averageHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        guard !samples.isEmpty else {
            return nil
        }

        let total = samples.reduce(0) { $0 + $1.beatsPerMinute }
        return total / Double(samples.count)
    }

}

enum BodyValueFormat {
    enum UnitPreference: String, CaseIterable, Identifiable {
        case system
        case metric
        case imperial

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .system:
                return "System"
            case .metric:
                return "Metric"
            case .imperial:
                return "Imperial"
            }
        }

        var selectionSubtitle: String {
            switch self {
            case .system:
                return "Device"
            case .metric:
                return "kg / km"
            case .imperial:
                return "lb / mi"
            }
        }

        static let defaultValue: UnitPreference = .system

        static func storedValue(from rawValue: String) -> UnitPreference {
            UnitPreference(rawValue: rawValue) ?? defaultValue
        }
    }

    static func durationText(for duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        return durationText(minutes: minutes)
    }

    static func sleepDurationText(for duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded(.up)))
        return durationText(minutes: minutes)
    }

    static func stopwatchDurationText(for duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }

        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private static func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        }

        return "\(remainingMinutes)m"
    }

    static func workoutCountText(_ count: Int) -> String {
        let label = count == 1 ? "workout" : "workouts"
        return "\(count) \(label)"
    }

    static func massDisplay(
        kilograms: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system,
        decimals: Int = 1
    ) -> (value: String, unit: String) {
        let display = massValue(kilograms: kilograms, locale: locale, unitPreference: unitPreference)
        return (numberText(display.value, decimals: decimals, locale: locale), display.unit)
    }

    static func massValue(
        kilograms: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> (value: Double, unit: String) {
        if usesImperialMeasurements(locale: locale, unitPreference: unitPreference) {
            let pounds = Measurement(value: kilograms, unit: UnitMass.kilograms)
                .converted(to: .pounds)
                .value
            return (pounds, "lb")
        }

        return (kilograms, "kg")
    }

    static func distanceText(
        meters: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> String {
        if usesImperialMeasurements(locale: locale, unitPreference: unitPreference) {
            let miles = Measurement(value: meters, unit: UnitLength.meters)
                .converted(to: .miles)
                .value
            return numberText(miles, decimals: 1, locale: locale) + " mi"
        }

        let kilometers = Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: .kilometers)
            .value
        return numberText(kilometers, decimals: 1, locale: locale) + " km"
    }

    static func energyText(kilocalories: Double, locale: Locale = .current) -> String {
        numberText(kilocalories.rounded(), decimals: 0, locale: locale) + " kcal"
    }

    static func heartRateText(beatsPerMinute: Double, locale: Locale = .current) -> String {
        numberText(beatsPerMinute.rounded(), decimals: 0, locale: locale) + " BPM"
    }

    static func respiratoryRateText(breathsPerMinute: Double, locale: Locale = .current) -> String {
        numberText(breathsPerMinute.rounded(), decimals: 0, locale: locale) + " br/min"
    }

    static func temperatureDisplay(
        celsius: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> (value: String, unit: String) {
        let display = temperatureValue(celsius: celsius, locale: locale, unitPreference: unitPreference)
        return (numberText(display.value, decimals: 1, locale: locale), display.unit)
    }

    static func temperatureValue(
        celsius: Double,
        locale: Locale = .current,
        unitPreference: UnitPreference = .system
    ) -> (value: Double, unit: String) {
        if usesImperialMeasurements(locale: locale, unitPreference: unitPreference) {
            let fahrenheit = Measurement(value: celsius, unit: UnitTemperature.celsius)
                .converted(to: .fahrenheit)
                .value
            return (fahrenheit, "F")
        }

        return (celsius, "C")
    }

    static func numberText(_ value: Double, decimals: Int, locale: Locale = .current) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(decimals))
                .locale(locale)
        )
    }

    private static func usesImperialMeasurements(locale: Locale, unitPreference: UnitPreference) -> Bool {
        switch unitPreference {
        case .imperial:
            return true
        case .metric:
            return false
        case .system:
            return locale.measurementSystem == .us
        }
    }
}
