//
//  HealthKitFetchEngine+HeartRateRecovery.swift
//  Body
//
//  Reads a workout's 1-minute heart-rate recovery for the detail tile grid.
//  Apple Watch writes a single `heartRateRecoveryOneMinute` sample a minute
//  after a workout ends, but where it lands varies: some watchOS versions
//  attach it to the workout's statistics, some associate it with the workout
//  object, and some leave it as a standalone sample just past the end date.
//  All three are tried in that order (cheapest and most authoritative first)
//  so the tile shows up regardless.
//

import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// The workout's 1-minute heart-rate recovery in bpm, or nil when the
    /// workout can't be fetched, the Heart permission is opted out, or no
    /// recovery sample exists. Any read FAILURE (a dismissed detail sheet's
    /// cancellation, a locked-device error, an XPC drop) propagates so the
    /// caller can tell "no recovery" from "didn't finish reading" and not cache
    /// a false absence.
    func workoutHeartRateRecovery(workoutID: UUID) async throws -> Double? {
        guard let workout = try await fetchWorkout(id: workoutID) else {
            return nil
        }

        // Recovery is heart data, so it rides the Heart toggle rather than the
        // Workout Metrics one — its read type is requested in the `.heart` block.
        guard permissionSelection.includes(.heart),
              let recoveryType = HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) else {
            return nil
        }

        let unit = HKUnit.count().unitDivided(by: .minute())

        if let attached = workout.statistics(for: recoveryType)?.mostRecentQuantity() {
            return attached.doubleValue(for: unit)
        }

        if let associated = try await latestRecoverySample(
            type: recoveryType,
            predicate: HKQuery.predicateForObjects(from: workout)
        ) {
            return associated.quantity.doubleValue(for: unit)
        }

        // Standalone sample: the watch writes it about a minute after the end, so
        // a 5-minute window covers a late write without reaching the next
        // workout. Other sources can also write into that window, so prefer a
        // sample from the workout's own source; latest wins either way.
        let windowSamples = try await recoverySamples(
            type: recoveryType,
            predicate: HKQuery.predicateForSamples(
                withStart: workout.endDate,
                end: workout.endDate.addingTimeInterval(5 * 60)
            )
        )
        let workoutSource = workout.sourceRevision.source
        let preferred = windowSamples.filter { $0.sourceRevision.source == workoutSource }
        return (preferred.isEmpty ? windowSamples : preferred).first?.quantity.doubleValue(for: unit)
    }

    private func latestRecoverySample(
        type: HKQuantityType,
        predicate: NSPredicate
    ) async throws -> HKQuantitySample? {
        try await recoverySamples(type: type, predicate: predicate, limit: 1).first
    }

    /// Recovery samples matching `predicate`, latest first.
    private func recoverySamples(
        type: HKQuantityType,
        predicate: NSPredicate,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }
}
