import Foundation
import HealthKit

struct BodyHealthObservation {
    let type: HKSampleType
    let frequency: HKUpdateFrequency
    /// Quantity/sleep obligations use the small domain ledger. Workout sample
    /// notifications use the existing journal's scan-needed receipt instead.
    let metrics: Set<HealthMetricKind>
    let scansWorkouts: Bool
    /// Current ring invalidation uses its existing snapshot/repair owner.
    let invalidatesActivityRings: Bool
}

enum BodyHealthObservationPolicy {
    static let fallbackInterval: TimeInterval = 30 * 60
    static let appRefreshDeadline: Duration = .seconds(20)
    static let foregroundDebounce: Duration = .seconds(1)
    static let foregroundMaximumWait: Duration = .seconds(5)

    /// Concrete iOS identifiers, filtered against Body's actual requested read
    /// set. Characteristics and activity summaries are not observer samples.
    /// Unsupported delivery is handled by enable failure, never assumed live.
    static func registrations(
        permissions: BodyHealthPermissionSelection,
        selection: BodyDashboardFetchSelection,
        includesCompanionConsumers: Bool = false
    ) -> [BodyHealthObservation] {
        let readable = BodyHealthReadTypes.readObjectTypes(for: permissions)
        // The app maintains the shared widget snapshot and watch payload even
        // when a metric's phone card is hidden. Reuse their canonical mappings.
        let companionKinds: Set<HealthMetricKind> = includesCompanionConsumers
            ? Set(HealthWidgetMetric.allCases.map(\.healthMetricKind))
                .union(WatchMetricKindKey.displayOrder.compactMap(HealthMetricKind.init(rawValue:)))
            : []
        var result: [BodyHealthObservation] = []
        func add(_ type: HKSampleType?, metrics: Set<HealthMetricKind>, immediate: Bool = false,
                 workouts: Bool = false) {
            guard let type, readable.contains(type) else { return }
            let needed = Set(metrics.filter { selection.includes($0) || companionKinds.contains($0) })
            let ringInputs: Set<String> = [HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                HKQuantityTypeIdentifier.appleExerciseTime.rawValue, HKQuantityTypeIdentifier.appleStandTime.rawValue]
            let rings = selection.includesActivityRings && ringInputs.contains(type.identifier)
            guard workouts || rings || !needed.isEmpty else { return }
            result.append(.init(type: type, frequency: immediate ? .immediate : .hourly,
                                metrics: needed, scansWorkouts: workouts, invalidatesActivityRings: rings))
        }
        func quantity(_ id: HKQuantityTypeIdentifier, _ metrics: Set<HealthMetricKind>) {
            add(HKObjectType.quantityType(forIdentifier: id), metrics: metrics)
        }
        add(HKObjectType.workoutType(), metrics: [], immediate: true, workouts: true)
        add(HKObjectType.categoryType(forIdentifier: .sleepAnalysis), metrics: [.sleep], immediate: true)
        quantity(.heartRate, [.heartRate, .sleep])
        quantity(.heartRateVariabilitySDNN, [.heartRateVariability, .sleep])
        quantity(.restingHeartRate, [.restingHeartRate])
        quantity(.respiratoryRate, [.respiratoryRate, .sleep])
        quantity(.oxygenSaturation, [.oxygenSaturation, .sleep])
        quantity(.appleSleepingWristTemperature, [.wristTemperature, .sleep])
        quantity(.stepCount, [.steps])
        quantity(.activeEnergyBurned, [.activeEnergy])
        quantity(.basalEnergyBurned, [.restingEnergy])
        quantity(.appleExerciseTime, [.exerciseMinutes])
        quantity(.bodyMass, [.bodyMass])
        quantity(.bodyFatPercentage, [.bodyFatPercentage])
        quantity(.bodyMassIndex, [.bodyMassIndex])
        quantity(.vo2Max, [.cardioFitness])
        quantity(.timeInDaylight, [.timeInDaylight])
        quantity(.workoutEffortScore, [.trainingLoad])
        // Raw heartbeat series is a Stress dependency, not an HRV SDNN trend.
        add(HKSeriesType.heartbeat(), metrics: [.stress])
        return result.sorted { $0.type.identifier < $1.type.identifier }
    }
}
