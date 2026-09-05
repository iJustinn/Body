//
//  HealthKitWorkoutStore+Records.swift
//  Body
//
//  Lifecycle for the all-time personal-record ledger: hydration happens in the
//  store's init (the stored properties live on the main class — an extension
//  can't declare them); everything else lives here.
//
//  Four feeds keep the ledger honest:
//
//  1. A one-time, resumable BASELINE scan walks the whole workout history in
//     one-year chunks. It runs only after a refresh has finished, never inside
//     one — "Body refresh must never hang" — and every chunk is cancellable and
//     persisted, so a kill mid-scan resumes from `scannedThrough`.
//  2. Each month the progressive loader publishes is folded in, which repairs
//     late-arriving distances and removes workouts deleted inside that month.
//  3. A Clear Cache / Workouts opt-out cancels the scan, empties the ledger and
//     deletes the file.
//  4. After baseline completion, bounded monthly repair revisits old inputs;
//     its cursor and repaired contributions share the same atomic ledger.
//

import Foundation
import HealthKit

extension HealthKitWorkoutStore {
    /// One year per baseline chunk: long enough that a decade of history is ten
    /// round-trips, short enough that a chunk's per-workout distance fan-out stays
    /// bounded and a cancellation loses at most a year of scanning.
    private static let recordBaselineChunkYears = 1

    // MARK: - Reads

    /// The metrics this workout currently holds the all-time, per-type record in.
    ///
    /// Empty until the baseline scan has covered the whole history — a partial
    /// ledger would crown whatever it happened to have folded in so far. The
    /// ledger enforces that itself; this is the app's only read path into it.
    func personalRecords(for workout: WorkoutSummary) -> Set<WorkoutRecordMetric> {
        recordLedger.records(for: workout)
    }

    /// How this workout stands in each of its type's record metrics: still the holder,
    /// or beaten since. Surfaces that dim a superseded badge read this; surfaces that
    /// only ever show a live record (the share cards) read `personalRecords(for:)`.
    func personalRecordStandings(for workout: WorkoutSummary) -> [WorkoutRecordMetric: WorkoutRecordStanding] {
        recordLedger.recordStandings(for: workout)
    }

    /// The single standing a dense list row draws: one glyph however many metrics
    /// the workout holds, and a record it still holds outranks one it has lost.
    func rowRecordStanding(for workout: WorkoutSummary) -> WorkoutRecordStanding? {
        let standings = personalRecordStandings(for: workout).values
        if standings.contains(.current) { return .current }
        return standings.isEmpty ? nil : .former
    }

    // MARK: - Incremental folding

    /// Reconciles one freshly fetched month against the ledger.
    ///
    /// Upserts validated arriving workouts (so a distance that resolved on this
    /// pass replaces the earlier valueless contribution) and drops any
    /// contribution inside the month that the fetch did NOT return — that workout
    /// was deleted in Health, and an all-time record must not outlive it.
    ///
    /// Deliberately NOT wired to the detail-snapshot prune: that keep-set spans
    /// only the current and previous month, so applying it to an all-time ledger
    /// would delete the entire baseline on every refresh.
    func foldMonthIntoRecordLedger(
        key: BodyWorkoutMonthKey,
        workouts: [WorkoutSummary],
        calendar: Calendar,
        unvalidatedRecordIDs: Set<UUID> = []
    ) {
        guard permissionSelection.includes(.workouts) else { return }
        guard let start = calendar.date(from: DateComponents(year: key.year, month: key.month, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return
        }

        var ledger = recordLedger
        ledger.reconcile(workouts: workouts, start: start, end: end,
            unvalidatedRecordIDs: unvalidatedRecordIDs)
        guard ledger.contributions != recordLedger.contributions else { return }
        publishRecordLedger(ledger)
        persistRecordLedger(ledger)
    }

    // MARK: - Baseline scan

    /// Starts the baseline scan, or one eligible historical repair after completion.
    ///
    /// Called from `finishRefresh`, so it can only begin once a refresh is over.
    /// Requires confirmed authorization: an empty scan under undetermined or
    /// denied reads must never be mistaken for "this user has no workouts" and
    /// finalize an empty baseline.
    func scheduleRecordBaselineBackfillIfNeeded() {
        guard recordBackfillTask == nil,
              !isClearingLocalCache,
              permissionSelection.includes(.workouts),
              authorizationState == .authorized else {
            return
        }

        let epoch = currentCacheEpoch
        recordBackfillTask = Task { [weak self] in
            guard let self else { return }
            if self.recordLedger.baselineComplete {
                await self.runRecordHistoricalRepair(capturedEpoch: epoch)
            } else {
                await self.runRecordBaselineBackfill(capturedEpoch: epoch)
            }
        }
    }

    private func runRecordHistoricalRepair(capturedEpoch: Int) async {
        defer {
            recordBackfillTask = nil
            scheduleStressBackfillIfNeeded()
        }
        guard !isRefreshing, !Task.isCancelled else { return }
        let inputs = captureRefreshInputs()
        let revision = recordLedgerRevision
        let engine = self.engine
        let queryRevision = await engine.queryContextRevision
        let calendar = Calendar.bodyGregorian
        let now = Date()
        let context = "record-v1|\(inputs.inputs.permissions)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        let progress = recordLedger.historicalRepair
        let cachedFloor = recordLedger.contributions.values.map(\.startDate).min()
        let fetch = Task { () -> (Date, Date, HealthKitFetchEngine.WorkoutSummariesFetchResult)? in
            let healthFloor = await engine.earliestWorkoutStartDate()
            guard !Task.isCancelled, let floor = [cachedFloor, healthFloor].compactMap({ $0 }).min(),
                  let month = HistoricalMonthRepairProgress.candidate(after: progress, now: now,
                    earliest: floor, context: context, calendar: calendar),
                  let end = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            guard let result = try? await withBackgroundQueryPool({
                try await engine.fetchWorkoutSummariesWithValidation(startDate: month, endDate: end,
                    includesHeartRateSamples: false, includesDetailMetrics: true)
            }) else { return nil }
            return (month, floor, result)
        }
        let outcome = await withTaskCancellationHandler {
            await OneShotDeadlineRace.run(deadline: Self.healthRefreshDeadline) { await fetch.value }
        } onCancel: { fetch.cancel() }
        fetch.cancel()
        guard await engine.queryContextRevision == queryRevision,
              case .finished(let chunk?) = outcome, !Task.isCancelled,
              !isRefreshing, recordLedgerRevision == revision,
              Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: currentCacheEpoch),
              mayApplyRefreshInputs(inputs),
              chunk.2.unvalidatedRecordIDs.isEmpty,
              let end = calendar.date(byAdding: .month, value: 1, to: chunk.0) else { return }
        var ledger = recordLedger
        ledger.reconcile(workouts: chunk.2.workouts, start: chunk.0, end: end, unvalidatedRecordIDs: [])
        ledger.historicalRepair = .completed(month: chunk.0, now: now, earliest: chunk.1,
            context: context, calendar: calendar)
        publishRecordLedger(ledger)
        persistRecordLedger(ledger)
    }

    /// Cancels the scan and waits for it to actually exit, so a caller about to
    /// delete the ledger file can be sure no chunk write is still queued behind
    /// the delete. The task clears its own handle on the way out.
    func cancelRecordBaselineBackfill() async {
        guard let task = recordBackfillTask else { return }
        task.cancel()
        await task.value
    }

    /// Walks `scannedThrough` (or the earliest workout) forward to now in yearly
    /// chunks. Every chunk publishes and persists before the next one starts, so
    /// the scan is resumable at chunk granularity.
    ///
    /// The fetch runs on the engine actor, so the only main-actor work here is the
    /// ledger fold itself — bounded by one year of workouts, once per install.
    private func runRecordBaselineBackfill(capturedEpoch: Int) async {
        defer {
            recordBackfillTask = nil
            // Re-offer the Stress backfill slot on every exit — success, an
            // early bail, or a fetch failure — mirroring how the Stress input
            // load already does when it finishes. `finishRefresh` starts this
            // scan before calling `scheduleStressBackfillIfNeeded()`, so that
            // first call always stands down on `recordBackfillTask`, and the
            // input load's own re-offer usually fires while this multi-year
            // scan is still running. Without a re-offer here, nothing left
            // re-checks the guard once both of those moments have passed.
            scheduleStressBackfillIfNeeded()
        }

        let calendar = Calendar.bodyGregorian
        let inputs = captureRefreshInputs()
        let queryRevision = await engine.queryContextRevision
        // A nil earliest date means either "no workouts at all" or "reads we
        // aren't allowed to see" — HealthKit doesn't distinguish them. Neither is
        // a baseline worth finalizing, so bail and let the next launch retry.
        guard let earliest = await engine.earliestWorkoutStartDate() else { return }

        let end = Date()
        var cursor = max(recordLedger.scannedThrough ?? earliest, earliest)

        while cursor < end {
            guard !Task.isCancelled,
                  mayApplyRefreshInputs(inputs),
                  Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: currentCacheEpoch) else {
                return
            }

            let chunkEnd = min(
                calendar.date(byAdding: .year, value: Self.recordBaselineChunkYears, to: cursor) ?? end,
                end
            )

            let revision = recordLedgerRevision
            let result: HealthKitFetchEngine.WorkoutSummariesFetchResult
            do {
                // `includesHeartRateSamples: false` skips the expensive per-workout
                // HR payload the ledger never reads. `includesDetailMetrics` must
                // stay TRUE: it also gates `fetchWorkoutDistances`, which is the
                // only way an associated-sample distance (no `totalDistance`
                // aggregate) is resolved — without it the distance and pace records
                // would permanently miss those workouts.
                // Multi-year chunks of the same shared fetch the refresh runs,
                // so the chunk spends the background budget: this scan must
                // never queue ahead of a visible dashboard leaf.
                result = try await withBackgroundQueryPool {
                    try await engine.fetchWorkoutSummariesWithValidation(
                        startDate: cursor,
                        endDate: chunkEnd,
                        includesHeartRateSamples: false,
                        includesDetailMetrics: true
                    )
                }
            } catch {
                // A failed or cancelled chunk leaves `scannedThrough` where it is
                // and never finalizes; the next refresh resumes from here.
                return
            }

            guard await engine.queryContextRevision == queryRevision,
                  !Task.isCancelled, recordLedgerRevision == revision, mayApplyRefreshInputs(inputs),
                  Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: currentCacheEpoch) else {
                return
            }

            // A partial result remains displayable in month refreshes, but cannot
            // move baseline coverage past a failed record input.
            guard applyRecordBackfillChunk(result: result, scannedThrough: chunkEnd) else { return }
            cursor = chunkEnd
            await Task.yield()
        }

        finalizeRecordBaseline(capturedEpoch: capturedEpoch)
    }

    private func applyRecordBackfillChunk(
        result: HealthKitFetchEngine.WorkoutSummariesFetchResult, scannedThrough: Date
    ) -> Bool {
        let workouts = result.workouts
        // The baseline scan is the one pass that visits every workout ever logged,
        // so it seeds the color editor's known-workout-types census with activity
        // types that live outside the loaded months (no-op write when nothing new).
        BodyWorkoutColorStore.mergeKnownWorkoutTypes(Set(workouts.map(\.type)))
        var ledger = recordLedger
        // Batched: rebuilds the index once for the whole chunk instead of once
        // per workout, which is otherwise quadratic in chunk size and can
        // freeze the main actor on a multi-year history.
        guard ledger.applyValidatedBaselineChunk(workouts: workouts, scannedThrough: scannedThrough,
            unvalidatedRecordIDs: result.unvalidatedRecordIDs) else { return false }
        publishRecordLedger(ledger)
        persistRecordLedger(ledger)
        return true
    }

    /// Only reached when every chunk from the earliest workout to now fetched
    /// successfully under confirmed authorization.
    private func finalizeRecordBaseline(capturedEpoch: Int) {
        guard Self.mayApplyLoad(capturedEpoch: capturedEpoch, currentEpoch: currentCacheEpoch),
              permissionSelection.includes(.workouts),
              !recordLedger.baselineComplete else {
            return
        }

        var ledger = recordLedger
        ledger.baselineComplete = true
        publishRecordLedger(ledger)
        persistRecordLedger(ledger)
    }

    // MARK: - Persistence

    /// Writes on the shared serial persist queue so ledger saves keep FIFO order
    /// with the snapshot saves and the Clear Cache delete barrier.
    private func persistRecordLedger(_ ledger: WorkoutRecordLedger) {
        Self.snapshotPersistQueue.async {
            WorkoutRecordLedgerStore.save(ledger)
        }
    }
}

extension HealthKitFetchEngine {
    /// Start date of the oldest workout in Health, or nil when there is none (or
    /// the reads aren't authorized — HealthKit reports both as an empty result).
    ///
    /// A single ascending, limit-1 sample query: the baseline scan needs a floor
    /// to walk up from, and walking back from today until a chunk comes up empty
    /// would either stop early on a gap year or never stop at all.
    func earliestWorkoutStartDate() async -> Date? {
        // Only the record baseline scan asks for this floor, so it always spends
        // the background budget.
        await withBackgroundQueryPool {
            await runCancellableQuery(cancelledValue: Date?.none) { resume in
                HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: nil,
                    limit: 1,
                    sortDescriptors: [BodyWorkoutFetch.startDateAscendingSort]
                ) { _, samples, _ in
                    resume((samples?.first as? HKWorkout)?.startDate)
                }
            }
        }
    }
}
