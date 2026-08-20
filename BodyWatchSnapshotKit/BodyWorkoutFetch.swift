//
//  BodyWorkoutFetch.swift
//  BodyWatchSnapshotKit
//
//  Workout fetching + `HKWorkout` → `WorkoutSummary` mapping shared by Body and
//  BodyWatch. The parity surface is the three pieces below — the query
//  predicate, the sort, and `summary(for:)` — not a single entry point: both
//  sides run their own fan-out around them (the iOS `HealthKitFetchEngine` for
//  batched heart-rate samples, effort/VO₂max/cadence/distance and query
//  cancellation; `WatchDeltaFetcher` for per-workout effort on its short
//  training-load delta), then map through the same `summary(for:)`. That's what
//  makes a workout produce the same activity type, energies and distances on
//  both devices — the first standalone-compute attempt mapped every watch
//  workout to `.other`, which quietly drained the training-load contribution of
//  the workouts it was supposed to add.
//

import Foundation
import HealthKit
import os

enum BodyWorkoutFetch {
    // MARK: - Query

    /// The workout-list predicate: `.strictStartDate` so a workout is owned by
    /// the window its START falls in (an overnight session belongs to the day it
    /// began), matching how the training-load day slots are keyed.
    static func workoutPredicate(start: Date, end: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
    }

    /// Ascending by start date — the order the training-load accumulation and
    /// month grouping both assume.
    static var startDateAscendingSort: NSSortDescriptor {
        NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    }

    /// Every workout that STARTED in `[start, end)`, ascending, with NO source
    /// filter (workouts are never source-selectable). `.failure` marks a query
    /// error so the caller keeps its cache instead of blanking the window.
    static func workouts(
        store: HKHealthStore,
        start: Date,
        end: Date,
        onFailure: ((Error?) -> Void)? = nil
    ) async -> WatchFetchOutcome<[HKWorkout]> {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: workoutPredicate(start: start, end: end),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [startDateAscendingSort]
            ) { _, samples, error in
                guard error == nil else {
                    onFailure?(error)
                    continuation.resume(returning: .failure)
                    return
                }

                continuation.resume(returning: .success(samples as? [HKWorkout] ?? []))
            }

            store.execute(query)
        }
    }

    // MARK: - Mapping

    static func summary(
        for workout: HKWorkout,
        heartRateSamples: [WorkoutHeartRateSample] = [],
        effortLevel: Double? = nil,
        effortUnresolved: Bool? = nil,
        cardioFitnessVO2Max: Double? = nil,
        averageStepCadenceSPM: Double? = nil,
        resolvedDistanceMeters: Double? = nil,
        includesWorkoutMetrics: Bool = true,
        includesHeartMetrics: Bool = false
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        let averageHeartRate = averageHeartRate(from: heartRateSamples)
        let type = workoutType(for: workout.workoutActivityType)

        #if DEBUG
        // Distinguishes "HealthKit gave us no weather metadata" from "mapper dropped it".
        if workout.metadata?[HKMetadataKeyWeatherTemperature] == nil {
            Logger(subsystem: "com.zihengthedeveloper.Body", category: "WorkoutWeather")
                .debug("No weather metadata: start=\(workout.startDate), source=\(workout.sourceRevision.source.name, privacy: .public), keys=\(workout.metadata?.keys.sorted() ?? [], privacy: .public)")
        }
        #endif

        return WorkoutSummary(
            id: workout.uuid,
            type: type,
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: distanceMeters(for: workout, type: type) ?? resolvedDistanceMeters,
            averageHeartRateBeatsPerMinute: averageHeartRate,
            maximumHeartRateBeatsPerMinute: maximumHeartRate(from: heartRateSamples),
            effortLevel: effortLevel,
            effortUnresolved: effortUnresolved,
            heartRateSamples: downsampleHeartRateSamples(heartRateSamples),
            elevationAscendedMeters: elevationAscendedMeters(for: workout),
            averagePowerWatts: includesWorkoutMetrics ? averagePowerWatts(for: workout, type: type) : nil,
            averageStepCadenceSPM: includesWorkoutMetrics ? averageStepCadenceSPM : nil,
            averageCyclingCadenceRPM: includesWorkoutMetrics ? averageCyclingCadenceRPM(for: workout, type: type) : nil,
            swimmingStrokeCount: includesWorkoutMetrics ? swimmingStrokeCount(for: workout, type: type) : nil,
            cardioFitnessVO2Max: includesWorkoutMetrics ? cardioFitnessVO2Max : nil,
            sourceName: workout.sourceRevision.source.name,
            endDate: workout.endDate,
            weatherTemperatureCelsius: weatherTemperatureCelsius(for: workout),
            weatherHumidityPercent: weatherHumidityPercent(for: workout),
            weatherCondition: weatherCondition(for: workout),
            averageMETs: averageMETs(for: workout),
            heartRateRecoveryBPM: includesHeartMetrics ? heartRateRecoveryBPM(for: workout) : nil
        )
    }

    /// Summary for a workout whose heart-rate payload is reused from a cached
    /// summary (passive resumes; eligibility decided by
    /// `heartRateReuseEligibleWorkoutIDs`). Metadata comes fresh from the
    /// `HKWorkout`; the cached average + samples are copied verbatim — the
    /// cached average was computed from the raw samples *before* downsampling,
    /// so re-deriving it from the stored ≤96 samples would drift.
    static func summary(
        for workout: HKWorkout,
        reusingHeartRateFrom cached: WorkoutSummary,
        effortLevel: Double? = nil,
        effortUnresolved: Bool? = nil,
        cardioFitnessVO2Max: Double? = nil,
        averageStepCadenceSPM: Double? = nil,
        resolvedDistanceMeters: Double? = nil,
        includesWorkoutMetrics: Bool = true,
        includesHeartMetrics: Bool = false
    ) -> WorkoutSummary {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        let type = workoutType(for: workout.workoutActivityType)

        return WorkoutSummary(
            id: workout.uuid,
            type: type,
            startDate: workout.startDate,
            duration: workout.duration,
            activeEnergyKilocalories: activeEnergy,
            totalEnergyKilocalories: totalEnergyKilocalories(for: workout) ?? activeEnergy,
            distanceMeters: distanceMeters(for: workout, type: type) ?? resolvedDistanceMeters,
            averageHeartRateBeatsPerMinute: cached.averageHeartRateBeatsPerMinute,
            maximumHeartRateBeatsPerMinute: cached.maximumHeartRateBeatsPerMinute,
            effortLevel: effortLevel,
            effortUnresolved: effortUnresolved,
            heartRateSamples: cached.heartRateSamples ?? [],
            elevationAscendedMeters: elevationAscendedMeters(for: workout),
            averagePowerWatts: includesWorkoutMetrics ? averagePowerWatts(for: workout, type: type) : nil,
            averageStepCadenceSPM: includesWorkoutMetrics ? averageStepCadenceSPM : nil,
            averageCyclingCadenceRPM: includesWorkoutMetrics ? averageCyclingCadenceRPM(for: workout, type: type) : nil,
            swimmingStrokeCount: includesWorkoutMetrics ? swimmingStrokeCount(for: workout, type: type) : nil,
            cardioFitnessVO2Max: includesWorkoutMetrics ? cardioFitnessVO2Max : nil,
            sourceName: workout.sourceRevision.source.name,
            endDate: workout.endDate,
            weatherTemperatureCelsius: weatherTemperatureCelsius(for: workout),
            weatherHumidityPercent: weatherHumidityPercent(for: workout),
            weatherCondition: weatherCondition(for: workout),
            averageMETs: averageMETs(for: workout),
            heartRateRecoveryBPM: includesHeartMetrics ? heartRateRecoveryBPM(for: workout) : nil
        )
    }

    private static func activeEnergyKilocalories(for workout: HKWorkout) -> Double? {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        return workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    private static func totalEnergyKilocalories(for workout: HKWorkout) -> Double? {
        let activeEnergy = activeEnergyKilocalories(for: workout)
        guard let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
              let basalEnergy = workout.statistics(for: basalEnergyType)?
              .sumQuantity()?
              .doubleValue(for: .kilocalorie()) else {
            return activeEnergy
        }

        return (activeEnergy ?? 0) + basalEnergy
    }

    private static func averageHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        let values = samples.map(\.beatsPerMinute).filter(\.isFinite)
        guard !values.isEmpty else {
            return nil
        }

        return values.reduce(0, +) / Double(values.count)
    }

    private static func maximumHeartRate(from samples: [WorkoutHeartRateSample]) -> Double? {
        samples.map(\.beatsPerMinute).filter(\.isFinite).max()
    }

    private static func elevationAscendedMeters(for workout: HKWorkout) -> Double? {
        (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
    }

    /// Weather temperature the watch recorded with the workout, in °C. Any sign is
    /// valid (sub-zero outdoor sessions); only a non-finite reading is rejected.
    private static func weatherTemperatureCelsius(for workout: HKWorkout) -> Double? {
        finite((workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity)?
            .doubleValue(for: .degreeCelsius()))
    }

    /// The recorded sky condition, collapsed from HealthKit's 28 cases to the
    /// buckets the detail hero has an icon for. `.none` and anything unrecognized
    /// map to `nil`, which leaves the hero on its thermometer glyph.
    private static func weatherCondition(for workout: HKWorkout) -> WorkoutWeatherCondition? {
        guard let rawValue = workout.metadata?[HKMetadataKeyWeatherCondition] as? NSNumber,
              let condition = HKWeatherCondition(rawValue: rawValue.intValue) else {
            return nil
        }

        switch condition {
        case .none: return nil
        case .clear, .fair: return .clear
        case .partlyCloudy: return .partlyCloudy
        case .mostlyCloudy, .cloudy: return .cloudy
        case .foggy: return .fog
        case .haze, .smoky, .dust: return .haze
        case .windy, .blustery: return .wind
        case .drizzle: return .drizzle
        case .showers, .scatteredShowers: return .showers
        case .thunderstorms: return .thunderstorms
        case .snow, .mixedRainAndSnow, .mixedSnowAndSleet: return .snow
        case .sleet, .freezingDrizzle, .freezingRain, .mixedRainAndSleet: return .sleet
        case .hail, .mixedRainAndHail: return .hail
        case .tropicalStorm, .hurricane, .tornado: return .tropicalStorm
        @unknown default: return nil
        }
    }

    /// Recorded relative humidity as a percentage. Apple Watch writes humidity as
    /// a 0…1 fraction under `.percent()`, but some third-party sources store the
    /// percent number itself (e.g. 55), so both are accepted; out-of-range
    /// readings are malformed and dropped.
    private static func weatherHumidityPercent(for workout: HKWorkout) -> Double? {
        guard let raw = finite((workout.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity)?
            .doubleValue(for: .percent())) else {
            return nil
        }

        return normalizedHumidityPercent(fromPercentUnitValue: raw)
    }

    /// Scales a `.percent()`-unit humidity reading to 0…100, accepting either a
    /// 0…1 fraction (Apple Watch's convention) or an already-scaled percent
    /// (some third-party sources): `raw` in 0...1 is treated as a fraction and
    /// multiplied by 100; `raw` in 1...100 is treated as already a percent.
    /// The 1.0 boundary resolves to 100 (fraction semantics win). Non-finite or
    /// out-of-range values are malformed and return `nil`.
    static func normalizedHumidityPercent(fromPercentUnitValue raw: Double) -> Double? {
        guard raw.isFinite else {
            return nil
        }

        if (0...1).contains(raw) {
            return raw * 100
        }
        if (1...100).contains(raw) {
            return raw
        }
        return nil
    }

    /// The 1-minute heart-rate recovery from the statistics HealthKit already
    /// attached to the workout — no extra query, so it costs nothing on the list
    /// fetch. Absent for sources that don't attach it (and for a just-finished
    /// workout whose sample hasn't landed yet); the detail sheet's lazy read is
    /// the fallback. Gated on the Heart permission by the caller.
    private static func heartRateRecoveryBPM(for workout: HKWorkout) -> Double? {
        guard let recoveryType = HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute),
              let value = finite(workout.statistics(for: recoveryType)?
                  .mostRecentQuantity()?
                  .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) else {
            return nil
        }

        return value > 0 ? value : nil
    }

    /// Average metabolic equivalent, in kcal/(kg·hr) — the unit HealthKit stores
    /// `HKMetadataKeyAverageMETs` in.
    private static func averageMETs(for workout: HKWorkout) -> Double? {
        guard let value = finite((workout.metadata?[HKMetadataKeyAverageMETs] as? HKQuantity)?
            .doubleValue(for: HKUnit(from: "kcal/(kg*hr)"))) else {
            return nil
        }

        return value > 0 ? value : nil
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }

        return value
    }

    /// The distance `HKQuantityType` identifier for an activity, or nil when the
    /// activity isn't distance-tracking. Shared by the synchronous statistics read
    /// and the per-workout distance sample query in the fetch engine.
    static func distanceQuantityTypeIdentifier(for type: BodyWorkoutType) -> HKQuantityTypeIdentifier? {
        switch type.paceStyle {
        case .distancePace:
            return (type == .wheelchairWalkPace || type == .wheelchairRunPace)
                ? .distanceWheelchair
                : .distanceWalkingRunning
        case .speed:
            return .distanceCycling
        case .swimPace:
            return .distanceSwimming
        case .none:
            return nil
        }
    }

    /// Total workout distance (m): the legacy `totalDistance` aggregate when
    /// present, otherwise the activity-appropriate distance statistic attached to
    /// the workout. Distance that lives only in the workout's associated samples
    /// (not its attached statistics) is resolved asynchronously in the fetch engine
    /// and passed in as `resolvedDistanceMeters`.
    private static func distanceMeters(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        if let total = workout.totalDistance?.doubleValue(for: .meter()) {
            return total
        }

        guard let identifier = distanceQuantityTypeIdentifier(for: type),
              let distanceType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter())
    }

    /// Average running/cycling power (W), best-effort from the workout's attached
    /// statistics — present only when the recording source accumulated it.
    private static func averagePowerWatts(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        let identifier: HKQuantityTypeIdentifier
        if type.supportsRunningPower {
            identifier = .runningPower
        } else if type.paceStyle == .speed {
            identifier = .cyclingPower
        } else {
            return nil
        }
        return discreteAverage(for: workout, identifier: identifier, unit: .watt())
    }

    private static func averageCyclingCadenceRPM(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        guard type.paceStyle == .speed else { return nil }
        return discreteAverage(
            for: workout,
            identifier: .cyclingCadence,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
    }

    private static func swimmingStrokeCount(for workout: HKWorkout, type: BodyWorkoutType) -> Double? {
        guard type.paceStyle == .swimPace,
              let strokeType = HKQuantityType.quantityType(forIdentifier: .swimmingStrokeCount) else {
            return nil
        }
        return workout.statistics(for: strokeType)?.sumQuantity()?.doubleValue(for: .count())
    }

    private static func discreteAverage(
        for workout: HKWorkout,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return workout.statistics(for: quantityType)?.averageQuantity()?.doubleValue(for: unit)
    }

    private static func downsampleHeartRateSamples(
        _ samples: [WorkoutHeartRateSample],
        maximumCount: Int = 96
    ) -> [WorkoutHeartRateSample] {
        let sortedSamples = samples.sorted { $0.date < $1.date }
        guard sortedSamples.count > maximumCount, maximumCount > 1 else {
            return sortedSamples
        }

        let stride = Double(sortedSamples.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            sortedSamples[Int((Double(index) * stride).rounded())]
        }
    }

    // MARK: - Activity types

    static func workoutType(for activityType: HKWorkoutActivityType) -> BodyWorkoutType {
        switch activityType.rawValue {
        case 1:
            return .americanFootball
        case 2:
            return .archery
        case 3:
            return .australianFootball
        case 4:
            return .badminton
        case 5:
            return .baseball
        case 6:
            return .basketball
        case 7:
            return .bowling
        case 8:
            return .boxing
        case 9:
            return .climbing
        case 10:
            return .cricket
        case 11:
            return .crossTraining
        case 12:
            return .curling
        case 13:
            return .cycling
        case 14:
            return .dance
        case 15:
            return .danceInspiredTraining
        case 16:
            return .elliptical
        case 17:
            return .equestrianSports
        case 18:
            return .fencing
        case 19:
            return .fishing
        case 20:
            return .functionalStrengthTraining
        case 21:
            return .golf
        case 22:
            return .gymnastics
        case 23:
            return .handball
        case 24:
            return .hiking
        case 25:
            return .hockey
        case 26:
            return .hunting
        case 27:
            return .lacrosse
        case 28:
            return .martialArts
        case 29:
            return .mindAndBody
        case 30:
            return .mixedMetabolicCardioTraining
        case 31:
            return .paddleSports
        case 32:
            return .play
        case 33:
            return .preparationAndReadiness
        case 34:
            return .racquetball
        case 35:
            return .rowing
        case 36:
            return .rugby
        case 37:
            return .running
        case 38:
            return .sailing
        case 39:
            return .skatingSports
        case 40:
            return .snowSports
        case 41:
            return .soccer
        case 42:
            return .softball
        case 43:
            return .squash
        case 44:
            return .stairClimbing
        case 45:
            return .surfingSports
        case 46:
            return .swimming
        case 47:
            return .tableTennis
        case 48:
            return .tennis
        case 49:
            return .trackAndField
        case 50:
            return .strengthTraining
        case 51:
            return .volleyball
        case 52:
            return .walking
        case 53:
            return .waterFitness
        case 54:
            return .waterPolo
        case 55:
            return .waterSports
        case 56:
            return .wrestling
        case 57:
            return .yoga
        case 58:
            return .barre
        case 59:
            return .coreTraining
        case 60:
            return .crossCountrySkiing
        case 61:
            return .downhillSkiing
        case 62:
            return .flexibility
        case 63:
            return .hiit
        case 64:
            return .jumpRope
        case 65:
            return .kickboxing
        case 66:
            return .pilates
        case 67:
            return .snowboarding
        case 68:
            return .stairs
        case 69:
            return .stepTraining
        case 70:
            return .wheelchairWalkPace
        case 71:
            return .wheelchairRunPace
        case 72:
            return .taiChi
        case 73:
            return .mixedCardio
        case 74:
            return .handCycling
        case 75:
            return .discSports
        case 76:
            return .fitnessGaming
        case 77:
            return .cardioDance
        case 78:
            return .socialDance
        case 79:
            return .pickleball
        case 80:
            return .cooldown
        case 82:
            return .swimBikeRun
        case 83:
            return .transition
        case 84:
            return .underwaterDiving
        default:
            return .other
        }
    }
}
