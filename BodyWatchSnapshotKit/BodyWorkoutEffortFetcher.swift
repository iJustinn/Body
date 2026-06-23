//
//  BodyWorkoutEffortFetcher.swift
//  BodyWatchSnapshotKit
//
//  Shared `workoutEffortScore` lookup so the iOS engine and the watch's
//  standalone fetcher resolve per-workout effort the same way (one
//  relationship-predicate query per workout). Lives in a Body + BodyWatch group
//  (both link HealthKit). The iOS `HealthKitFetchEngine` keeps its caching layer
//  on top of this; the watch caches its own results.
//

import Foundation
import HealthKit

/// Distinguishes "the query completed and there is no saved effort" from "the
/// query errored" — only the former may feed a score-less confirmation cache; a
/// failure must stay retryable.
enum BodyWorkoutEffortOutcome {
    case found(Double)
    case noSavedEffort
    case failed
}

enum BodyWorkoutEffortFetcher {
    static func savedEffortOutcome(for workout: HKWorkout, store: HKHealthStore) async -> BodyWorkoutEffortOutcome {
        guard let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) else {
            return .failed
        }

        let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: effortType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                guard error == nil else {
                    continuation.resume(returning: .failed)
                    return
                }

                let effort = (samples as? [HKQuantitySample] ?? [])
                    .first?
                    .quantity
                    .doubleValue(for: .appleEffortScore())

                if let effort, effort.isFinite {
                    continuation.resume(returning: .found(effort))
                } else {
                    continuation.resume(returning: .noSavedEffort)
                }
            }

            store.execute(query)
        }
    }

    /// Convenience: the saved effort value, or `nil` when there's none / the
    /// query failed. Use when the found/errored distinction isn't needed.
    static func savedEffortLevel(for workout: HKWorkout, store: HKHealthStore) async -> Double? {
        if case .found(let effort) = await savedEffortOutcome(for: workout, store: store) {
            return effort
        }
        return nil
    }
}
