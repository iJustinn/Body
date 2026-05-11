//
//  WorkoutSummary.swift
//  Body
//

import Foundation

struct WorkoutSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let type: BodyWorkoutType
    let startDate: Date
    let duration: TimeInterval
    let activeEnergyKilocalories: Double?
    let distanceMeters: Double?
    let sourceName: String

    init(
        id: UUID = UUID(),
        type: BodyWorkoutType,
        startDate: Date,
        duration: TimeInterval,
        activeEnergyKilocalories: Double? = nil,
        distanceMeters: Double? = nil,
        sourceName: String = "Apple Health"
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.duration = duration
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.distanceMeters = distanceMeters
        self.sourceName = sourceName
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
        unitPreference: UnitPreference = .system
    ) -> (value: String, unit: String) {
        let display = massValue(kilograms: kilograms, locale: locale, unitPreference: unitPreference)
        return (numberText(display.value, decimals: 1, locale: locale), display.unit)
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
            return usesUSMeasurements(locale: locale)
        }
    }

    private static func usesUSMeasurements(locale: Locale) -> Bool {
        if let regionIdentifier = locale.region?.identifier {
            return regionIdentifier == "US"
        }

        return locale.identifier.contains("_US")
    }
}
