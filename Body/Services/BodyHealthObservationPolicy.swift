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
    /// How long after the latest night ended (or arrived) a vital delivery still
    /// reads sleep immediately. Covers the wake+10 Readiness and Radar freezes,
    /// the morning Watch sync and background scheduling delays.
    static let sleepVitalsWindow: TimeInterval = 6 * 60 * 60
    /// A deferred sleep read becomes ordinary work at the latest this long after
    /// its first deferral.
    static let sleepDeferralLimit: TimeInterval = 24 * 60 * 60
    /// Vitals Body reads inside each night's main session. A delivery only says
    /// when it arrived, not the sample's interval, so outside the window their
    /// sleep read is deferred, never dropped. Wrist temperature is nightly and
    /// stays immediate; RMSSD and the heartbeat series never map to sleep.
    static let sleepWindowVitals: Set<String> = [
        HKQuantityTypeIdentifier.heartRate.rawValue,
        HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
        HKQuantityTypeIdentifier.respiratoryRate.rawValue,
        HKQuantityTypeIdentifier.oxygenSaturation.rawValue
    ]

    /// Concrete iOS identifiers, filtered against Body's actual requested read
    /// set. Characteristics and activity summaries are not observer samples.
    /// Unsupported delivery is handled by enable failure, never assumed live.
    static func registrations(
        permissions: BodyHealthPermissionSelection,
        selection: BodyDashboardFetchSelection,
        includesCompanionConsumers: Bool = false,
        includesNotificationConsumers: Bool? = nil
    ) -> [BodyHealthObservation] {
        let readable = BodyHealthReadTypes.readObjectTypes(for: permissions)
        // The app maintains the shared widget snapshot and watch payload even
        // when a metric's phone card is hidden. Reuse their canonical mappings.
        let companionKinds: Set<HealthMetricKind> = includesCompanionConsumers
            ? Set(HealthWidgetMetric.allCases.map(\.healthMetricKind))
                .union(WatchMetricKindKey.displayOrder.compactMap(HealthMetricKind.init(rawValue:)))
            : []
        // Notification-only consumers require a wake, not dashboard history
        // repair. Their current-day inputs are read by the transient evaluator.
        var notificationKinds: Set<HealthMetricKind> = includesCompanionConsumers
            && (includesNotificationConsumers ?? BodyNotificationPreferences.enabled(BodyNotificationPreferences.stressKey))
            ? [.heartRate, .heartRateVariability, .steps, .activeEnergy, .sleep, .stress] : []
        // Readiness alerts wait on the same night's sleep sync, so they wake on sleep too.
        if includesCompanionConsumers, BodyNotificationPreferences.enabled(BodyNotificationPreferences.sleepKey)
            || BodyNotificationPreferences.enabled(BodyNotificationPreferences.readinessKey) {
            notificationKinds.insert(.sleep)
        }
        // Sleep's leaf reads nothing without the sleep analysis type, so a vital
        // must not enqueue a sleep obligation it can never complete. This is
        // Body's requested read set, not proof of a grant.
        let sleepReadable = HKObjectType.categoryType(forIdentifier: .sleepAnalysis).map { readable.contains($0) } ?? false
        var result: [BodyHealthObservation] = []
        func add(_ type: HKSampleType?, metrics: Set<HealthMetricKind>, immediate: Bool = false,
                 workouts: Bool = false) {
            guard let type, readable.contains(type) else { return }
            let needed = Set(metrics.filter {
                ($0 != .sleep || sleepReadable) && (selection.includes($0) || companionKinds.contains($0))
            })
            let ringInputs: Set<String> = [HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
                HKQuantityTypeIdentifier.appleExerciseTime.rawValue, HKQuantityTypeIdentifier.appleStandTime.rawValue]
            let rings = selection.includesActivityRings && ringInputs.contains(type.identifier)
            guard workouts || rings || !needed.isEmpty || !metrics.isDisjoint(with: notificationKinds) else { return }
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
        // Recovery HRV (RMSSD) is both the HRV page's Recovery view and Stress's
        // preferred HRV input, so it wakes the same consumers as the heartbeat
        // series below plus the HRV trend.
        if #available(iOS 27, *) {
            quantity(.heartRateVariabilityRMSSD, [.heartRateVariability, .stress])
        }
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
