//
//  HealthKitFetchEngine+Write.swift
//  Body
//

import Foundation
import HealthKit

// The app is otherwise read-only against HealthKit (see `requestAuthorization()`
// in HealthKitFetchEngine.swift, which always passes an empty `toShare` set).
// This is the only place Body *writes* samples: the manual weight / body-fat
// entry from the Basics detail screen, and the manual workout-effort rating from
// the workout detail screen. Authorization is requested lazily here rather than
// folded into the main read-permission flow so onboarding is unchanged for users
// who never add data.
extension HealthKitFetchEngine {
    /// Quantity types Body can write. Weight and body fat only — BMI is derived
    /// and not user-entered.
    private static var bodyCompositionShareTypes: Set<HKSampleType> {
        Set(
            [
                HKQuantityType.quantityType(forIdentifier: .bodyMass),
                HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)
            ]
            .compactMap { $0 } as [HKSampleType]
        )
    }

    /// Presents the HealthKit *write* permission sheet for body mass and body
    /// fat the first time it's needed. A no-op once the user has answered.
    func requestBodyCompositionWriteAuthorization() async throws {
        let shareTypes = Self.bodyCompositionShareTypes
        guard !shareTypes.isEmpty else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: Set<HKObjectType>()) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitWorkoutError.authorizationDenied)
                }
            }
        }
    }

    /// Saves the supplied measurements to Apple Health as samples timestamped at
    /// `date`. `nil` inputs are skipped; passing both `nil` is a no-op.
    ///
    /// `bodyFatPercent` is a 0–100 percentage as shown in the UI. HealthKit
    /// stores body fat as a 0–1 fraction (the read path scales it back up via
    /// `normalizedPercentDisplayValue`), so it's divided by 100 here.
    func saveBodyComposition(weightKilograms: Double?, bodyFatPercent: Double?, date: Date) async throws {
        var samples: [HKQuantitySample] = []

        if let weightKilograms,
           weightKilograms > 0,
           let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKilograms)
            samples.append(HKQuantitySample(type: weightType, quantity: quantity, start: date, end: date))
        }

        if let bodyFatPercent,
           bodyFatPercent >= 0,
           let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            let quantity = HKQuantity(unit: .percent(), doubleValue: bodyFatPercent / 100.0)
            samples.append(HKQuantitySample(type: bodyFatType, quantity: quantity, start: date, end: date))
        }

        guard !samples.isEmpty else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitWorkoutError.authorizationDenied)
                }
            }
        }
    }

    // MARK: - Workout effort

    /// Presents the HealthKit *write* permission sheet for workout effort the
    /// first time it's needed.
    func requestWorkoutEffortWriteAuthorization() async throws {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            return
        }

        let shareTypes: Set<HKSampleType> = [effortType]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: Set<HKObjectType>()) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitWorkoutError.authorizationDenied)
                }
            }
        }
    }

    /// Saves a manual effort rating (1–10) for the workout with `workoutID` and
    /// relates it so HealthKit — and Body's relationship-based read — associate
    /// it with that workout. The new sample is timestamped now so it wins the
    /// latest-by-date read even when another source (e.g. the Apple Watch) already
    /// rated the workout. Body's own prior rating is removed only after the new
    /// sample saves and relates, so a failed write leaves the existing rating intact.
    func saveWorkoutEffort(workoutID: UUID, score: Double) async throws {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            throw HealthKitWorkoutError.workoutEffortUnavailable
        }

        guard let workout = await fetchWorkout(id: workoutID) else {
            throw HealthKitWorkoutError.workoutNotFound
        }

        // Capture Body's prior ratings before writing anything; they're deleted
        // only after the replacement saves and relates, so a failed write can't
        // strip an existing rating.
        let staleEffortSamples = await ownRelatedEffortSamples(for: workout, effortType: effortType)

        let clampedScore = min(max(score, 1), 10)
        let now = Date()
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: clampedScore),
            start: now,
            end: now
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitWorkoutError.authorizationDenied)
                }
            }
        }

        do {
            try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
        } catch {
            // The sample saved but couldn't be related to the workout. Cleanup
            // only ever queries *related* effort samples, so an unrelated sample
            // would never be reclaimed — delete it now so a failed edit doesn't
            // leave orphaned effort data in HealthKit, then surface the failure.
            await deleteEffortSamples([sample])
            throw error
        }

        await deleteEffortSamples(staleEffortSamples)
    }

    // Internal (not private) so the peer `+Route` extension can resolve a
    // workout by UUID before querying its `HKWorkoutRoute`.
    func fetchWorkout(id: UUID) async -> HKWorkout? {
        await withCheckedContinuation { (continuation: CheckedContinuation<HKWorkout?, Never>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: id),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            healthStore.execute(query)
        }
    }

    /// Best-effort lookup of effort samples Body previously wrote for this
    /// workout. Samples from other sources (e.g. Apple Watch) aren't owned by
    /// this app and are filtered out so they're never deleted — the new sample's
    /// later timestamp makes Body's read prefer it instead.
    private func ownRelatedEffortSamples(for workout: HKWorkout, effortType: HKQuantityType) async -> [HKSample] {
        let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        let samples: [HKSample] = await withCheckedContinuation { (continuation: CheckedContinuation<[HKSample], Never>) in
            let query = HKSampleQuery(
                sampleType: effortType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }

        return samples.filter { $0.sourceRevision.source == HKSource.default() }
    }

    /// Best-effort deletion of Body's previous effort samples, so repeated edits
    /// don't accumulate. Failures are ignored — the new sample's later timestamp
    /// still makes Body's read prefer it.
    private func deleteEffortSamples(_ samples: [HKSample]) async {
        guard !samples.isEmpty else {
            return
        }

        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.delete(samples as [HKObject]) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
