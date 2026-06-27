//
//  BodyHealthReadTypes.swift
//  BodyWatchSnapshotKit
//
//  Single source of truth for the HealthKit read set the iOS
//  `HealthKitWorkoutStore` requests. Lives in a Body + BodyWatch group (both
//  link HealthKit); the widget extensions, which read cached snapshots, don't
//  compile it.
//

import Foundation
import HealthKit

enum BodyHealthReadTypes {
    /// The set of HealthKit object types to request read access for, derived
    /// from the user's enabled permission categories.
    nonisolated static func readObjectTypes(
        for selection: BodyHealthPermissionSelection = .defaultValue
    ) -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        if selection.includes(.activityRings) {
            types.insert(HKObjectType.activitySummaryType())
        }
        if selection.includes(.workouts) {
            types.insert(HKObjectType.workoutType())
            // GPS route for the workout-detail map hero. Folded into the standard
            // request so existing users are re-prompted on the next refresh; read
            // authorization stays opaque, so an absent route just yields no hero.
            types.insert(HKSeriesType.workoutRoute())
            if let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) {
                types.insert(effortType)
            }
        }

        var quantityIdentifiers: [HKQuantityTypeIdentifier] = []
        if selection.includes(.heart) {
            quantityIdentifiers += [
                .restingHeartRate,
                .heartRate,
                .heartRateVariabilitySDNN
            ]
        }
        if selection.includes(.basics) {
            quantityIdentifiers += [
                .bodyMass,
                .bodyFatPercentage,
                .bodyMassIndex
            ]
        }
        if selection.includes(.respiratory) {
            quantityIdentifiers.append(.respiratoryRate)
        }
        if selection.includes(.bloodOxygen) {
            quantityIdentifiers.append(.oxygenSaturation)
        }
        if selection.includes(.energy) {
            quantityIdentifiers += [
                .activeEnergyBurned,
                .basalEnergyBurned
            ]
        }
        if selection.includes(.exerciseMinutes) {
            quantityIdentifiers.append(.appleExerciseTime)
        }
        if selection.includes(.wristTemperature) {
            quantityIdentifiers.append(.appleSleepingWristTemperature)
        }
        if selection.includes(.timeInDaylight) {
            quantityIdentifiers.append(.timeInDaylight)
        }
        if selection.includes(.steps) {
            quantityIdentifiers.append(.stepCount)
        }

        quantityIdentifiers
            .compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { types.insert($0) }

        if selection.includes(.sleep),
           let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        return types
    }
}
