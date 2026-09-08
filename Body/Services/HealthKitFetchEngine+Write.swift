//
//  HealthKitFetchEngine+Write.swift
//  Body
//

import Foundation
import HealthKit
import os

/// Stage logger for the effort write path. File-scope because extensions can't
/// declare stored properties.
private let workoutEffortWriteLogger = Logger(
    subsystem: "com.zihengthedeveloper.Body",
    category: "WorkoutEffortWrite"
)

/// A workout-effort write failure tagged with the stage that failed, so the
/// detail screen's alert can name it (field reports can't pull Console logs).
struct WorkoutEffortWriteError: LocalizedError {
    let stage: String
    let underlying: Error

    var errorDescription: String? {
        "\(underlying.localizedDescription) [\(stage)]"
    }
}

// The app is otherwise read-only against HealthKit (see `requestAuthorization(allowPrompt:)`
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

        try await authorizationCoordinator.run { [self] in
            try await presentAuthorization(toShare: shareTypes, read: Set<HKObjectType>())
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

    /// What the effort *share* status implies for the write path.
    enum EffortWriteDecision {
        case authorized
        case denied
        case prompt
    }

    nonisolated static func effortWriteDecision(for status: HKAuthorizationStatus) -> EffortWriteDecision {
        switch status {
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        case .notDetermined:
            return .prompt
        @unknown default:
            return .prompt
        }
    }

    /// Ensures Body may write workout effort, presenting the HealthKit *write*
    /// permission sheet only when no decision has been recorded yet.
    ///
    /// `authorizationStatus(for:)` is consulted only as a shortcut: `.sharingAuthorized`
    /// skips the sheet entirely. It is deliberately NOT a fail-fast gate — devices
    /// have reported `.sharingDenied` while the Health app showed Full Access — so
    /// every other status goes through the request-status check (no sheet once a
    /// decision is recorded) and the save itself is the arbiter. Runs inside
    /// `authorizationCoordinator` so it can't stack a sheet on the read flow. (The iOS Simulator does
    /// not persist HealthKit authorization reliably and may re-prompt across
    /// rebuilds regardless; a real device asks only once.)
    func requestWorkoutEffortWriteAuthorization() async throws {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            return
        }

        let store = healthStore
        try await authorizationCoordinator.run { [self] in
            switch Self.effortWriteDecision(for: store.authorizationStatus(for: effortType)) {
            case .authorized:
                return
            case .denied, .prompt:
                // `.sharingDenied` is NOT a fail-fast signal: devices have reported it
                // while the Health app shows Full Access (stale per-process status after
                // access was re-enabled in Settings). Fall through and let `save` be the
                // arbiter — a real denial surfaces as HealthKit's own error.
                workoutEffortWriteLogger.notice("effort write: \("share status not authorized; checking request status", privacy: .public)")
            }

            let shareTypes: Set<HKSampleType> = [effortType]
            let requestStatus = try await store.statusForAuthorizationRequest(
                toShare: shareTypes,
                read: Set<HKObjectType>()
            )
            if requestStatus != .unnecessary {
                do {
                    try await presentAuthorization(toShare: shareTypes, read: Set<HKObjectType>())
                } catch {
                    throw WorkoutEffortWriteError(stage: "permission-sheet", underlying: error)
                }
            }

            // No status check after the sheet either (see above) — `save` decides.
        }
    }

    /// Whether Body currently has permission to *write* workout effort. Share (write)
    /// authorization is reportable — unlike read, where a denial is deliberately
    /// indistinguishable from "no data" — so the settings toggle can detect a denied
    /// write and reset itself instead of appearing on while every refresh silently fails.
    func isWorkoutEffortWriteAuthorized() -> Bool {
        guard let effortType = HKObjectType.quantityType(forIdentifier: .workoutEffortScore) else {
            return false
        }
        return healthStore.authorizationStatus(for: effortType) == .sharingAuthorized
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

        workoutEffortWriteLogger.debug("effort write: \("fetching workout", privacy: .public)")
        let workout: HKWorkout
        do {
            guard let found = try await fetchWorkout(id: workoutID) else {
                workoutEffortWriteLogger.error("effort write: \("workoutNotFound", privacy: .public)")
                throw HealthKitWorkoutError.workoutNotFound
            }
            workout = found
        } catch {
            throw WorkoutEffortWriteError(stage: "lookup", underlying: error)
        }

        // Capture Body's prior ratings before writing anything; they're deleted
        // only after the replacement saves and relates, so a failed write can't
        // strip an existing rating.
        workoutEffortWriteLogger.debug("effort write: \("querying prior samples", privacy: .public)")
        let staleEffortSamples = await ownRelatedEffortSamples(for: workout, effortType: effortType)

        let clampedScore = min(max(score, 1), 10)
        let now = Date()
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: clampedScore),
            start: now,
            end: now
        )

        workoutEffortWriteLogger.debug("effort write: \("saving sample", privacy: .public)")
        do {
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
        } catch {
            workoutEffortWriteLogger.error("effort write: save failed \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            throw WorkoutEffortWriteError(stage: "save", underlying: error)
        }

        workoutEffortWriteLogger.debug("effort write: \("relating sample", privacy: .public)")
        do {
            try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
        } catch {
            workoutEffortWriteLogger.error("effort write: relate failed \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
            // The sample saved but couldn't be related to the workout. Cleanup
            // only ever queries *related* effort samples, so an unrelated sample
            // would never be reclaimed — delete it now so a failed edit doesn't
            // leave orphaned effort data in HealthKit, then surface the failure.
            await deleteEffortSamples([sample])
            throw WorkoutEffortWriteError(stage: "relate", underlying: error)
        }

        workoutEffortWriteLogger.debug("effort write: \("cleaning up prior samples", privacy: .public)")
        await deleteEffortSamples(staleEffortSamples)

        // Write through to the effort cache (and its persisted ledger): the
        // score we just saved is authoritative, and for an aged workout nothing
        // would otherwise re-query it. Auto-apply writes land here too, via
        // `autoApplyWorkoutEffort`. Hydrate first — the ledger is rewritten from
        // the in-memory maps, so persisting before the file has been read would
        // drop every aged entry it holds.
        await hydratePersistedEffortLedgerIfNeeded()
        effortLevelsByWorkoutID[workoutID] = clampedScore
        effortResultRevisions[workoutID, default: 0] &+= 1
        confirmedNoEffortWorkoutIDs.remove(workoutID)
        effortWorkoutDatesByID[workoutID] = WorkoutEffortDateRange(
            startDate: workout.startDate,
            endDate: workout.endDate,
            validatedAt: now
        )
        persistEffortLedger()

        workoutEffortWriteLogger.debug("effort write: \("completed", privacy: .public)")
    }

    /// Outcome of an auto-apply effort write attempt.
    enum AutoApplyEffortOutcome {
        case written        // a predicted-effort sample was saved
        case alreadyRated   // a rating already exists (Body or another source); skip for good
        case unresolved     // the effort query couldn't be resolved; retry on a later refresh
    }

    /// Auto-apply variant of `saveWorkoutEffort`, and the authoritative "still unrated?"
    /// gate for the recent (1-48h) auto-apply window. It re-reads effort *fresh*
    /// (uncached) right before writing, so a rating that synced from the Apple Watch
    /// after the last refresh is never shadowed by our `now`-stamped sample. It writes
    /// ONLY when the read positively returns no saved effort; a failed read yields
    /// `.unresolved` (retryable) rather than a blind write.
    func autoApplyWorkoutEffort(workoutID: UUID, score: Double) async throws -> AutoApplyEffortOutcome {
        // A failed lookup (throw) and a genuinely absent workout (nil) both map
        // to `.unresolved` so a transient failure retries on a later refresh
        // instead of blind-writing a predicted effort.
        guard let workout = try? await fetchWorkout(id: workoutID) else {
            return .unresolved
        }
        switch await BodyWorkoutEffortFetcher.savedEffortOutcome(for: workout, store: healthStore) {
        case .found:
            return .alreadyRated
        case .failed:
            return .unresolved
        case .noSavedEffort:
            try await saveWorkoutEffort(workoutID: workoutID, score: score)
            return .written
        }
    }

    // Internal (not private) so the peer `+Route` extension can resolve a
    // workout by UUID before querying its `HKWorkoutRoute`. Throws on a query
    // FAILURE (device locked, XPC drop) so callers can distinguish it from a
    // genuinely absent workout (`nil` without error); route/splits propagate
    // that error rather than caching a false empty.
    func fetchWorkout(id: UUID) async throws -> HKWorkout? {
        try await trackedThrowingHealthQuery { (resume: @escaping @Sendable (Result<HKWorkout?, Error>) -> Void) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: id),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    resume(.failure(error))
                    return
                }
                resume(.success(samples?.first as? HKWorkout))
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
        // A cancelled query deletes nothing, which is the same best-effort
        // outcome as a failed one: the new sample's later timestamp still wins.
        let samples: [HKSample] = await trackedHealthQuery(cancelledValue: []) { resume in
            let query = HKSampleQuery(
                sampleType: effortType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                resume(samples ?? [])
            }
            healthStore.execute(query)
        }

        return samples.filter { $0.sourceRevision.source == HKSource.default() }
    }

    /// Best-effort deletion of Body's previous effort samples, so repeated edits
    /// don't accumulate. Failures are logged and swallowed: the new sample's later
    /// timestamp still makes Body's read prefer it.
    private func deleteEffortSamples(_ samples: [HKSample]) async {
        guard !samples.isEmpty else {
            return
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.delete(samples as [HKObject]) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            workoutEffortWriteLogger.error("effort write: delete failed \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)")
        }
    }
}
