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
            // Birth date (a read-only characteristic) anchors the workout heart-rate
            // zones at a percentage of the age-estimated max HR (220 − age). Gated on
            // its own `.dateOfBirth` toggle in addition to `.heart` — its only consumer
            // (the HR-zone chart) needs heart data anyway, so don't request it alone.
            if selection.includes(.dateOfBirth),
               let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
                types.insert(dateOfBirth)
            }
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
        if selection.includes(.workouts) {
            // Distance for the hero number + pace/speed. Many non-GPS workouts leave
            // `totalDistance`/attached statistics nil, so distance is read from the
            // workout's own samples — which needs these read scopes. Distance is core
            // workout data (hero/pace/totals), so it rides `.workouts`, not the
            // `.workoutMetrics` toggle.
            quantityIdentifiers += [
                .distanceWalkingRunning,
                .distanceCycling,
                .distanceSwimming,
                .distanceWheelchair
            ]
        }
        if selection.includes(.workouts) && selection.includes(.workoutMetrics) {
            // Activity-aware workout-detail metrics, gated on the Workout Metrics toggle
            // (and on `.workouts`, since they're only surfaced in the workout detail).
            // Foot cadence is derived from `.stepCount` (requested here so it doesn't
            // depend on the separate `.steps` toggle); power/cadence/strokes are best-effort.
            quantityIdentifiers += [
                .vo2Max,
                .runningPower,
                .cyclingPower,
                .cyclingCadence,
                .swimmingStrokeCount,
                .stepCount
            ]
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
