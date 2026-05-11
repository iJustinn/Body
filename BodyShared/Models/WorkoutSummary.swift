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
    static func durationText(for duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
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

    static func massDisplay(kilograms: Double, locale: Locale = .current) -> (value: String, unit: String) {
        if usesUSMeasurements(locale: locale) {
            let pounds = Measurement(value: kilograms, unit: UnitMass.kilograms)
                .converted(to: .pounds)
                .value
            return (numberText(pounds, decimals: 1, locale: locale), "lb")
        }

        return (numberText(kilograms, decimals: 1, locale: locale), "kg")
    }

    static func distanceText(meters: Double, locale: Locale = .current) -> String {
        if usesUSMeasurements(locale: locale) {
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

    private static func usesUSMeasurements(locale: Locale) -> Bool {
        if let regionIdentifier = locale.region?.identifier {
            return regionIdentifier == "US"
        }

        return locale.identifier.contains("_US")
    }
}
