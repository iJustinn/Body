//
//  HealthKitFetchEngine+Splits.swift
//  Body
//
//  Reads a workout's timestamped distance increments for the detail Splits
//  section. Uses the iOS 17 async `HKQuantitySeriesSampleQueryDescriptor`: it
//  terminates itself and honors `Task` cancellation, so a dismissed sheet stops
//  the read with no manual `stopQuery`. Raw HealthKit quantities are mapped to
//  app-owned `WorkoutDistanceSample`s so split boundaries stay unit-agnostic and
//  can be recomputed (km vs mi) without a refetch.
//

import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Timestamped distance increments for a workout, ordered by start date, plus
    /// the watch's recorded split segment events, for split computation. Returns
    /// `.empty` when the activity has no distance type, the workout can't be
    /// fetched, access is denied, or the summed sample meters diverge more than 5%
    /// from the workout's recorded distance — the same total the summary parsing
    /// reads (`totalDistance` or the attached statistic), which guards against
    /// multi-source overlap the raw sample walk doesn't dedupe. Any read FAILURE
    /// (a dismissed detail sheet's cancellation, a locked-device error, or an XPC
    /// drop) is propagated instead so the caller can tell "no splits" from "didn't
    /// finish reading" and not cache a false empty.
    func workoutSplitData(workoutID: UUID) async throws -> WorkoutSplitData {
        guard let workout = try await fetchWorkout(id: workoutID) else {
            return .empty
        }

        let type = HealthKitWorkoutStore.workoutType(for: workout.workoutActivityType)
        guard let identifier = BodyWorkoutFetch.distanceQuantityTypeIdentifier(for: type),
              let distanceType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return .empty
        }

        // The per-km/mi split windows the watch recorded at workout time — the
        // exact boundaries Apple Fitness displays. Prefer .segment intervals;
        // fall back to .lap events (some watchOS versions) only when no segment
        // events exist, converting instantaneous lap markers into windows between
        // consecutive marker times. The calculator still validates each window's
        // recorded distance, dropping pause slivers and off-unit segments.
        let events = workout.workoutEvents ?? []
        let segmentEvents = events.filter { $0.type == .segment }
        let splitEvents = segmentEvents.isEmpty ? events.filter { $0.type == .lap } : segmentEvents
        var segments = splitEvents
            .filter { $0.dateInterval.duration > 0 }
            .map { WorkoutTimeSegment(startDate: $0.dateInterval.start, endDate: $0.dateInterval.end) }
        if segments.isEmpty {
            var previous = workout.startDate
            for marker in splitEvents.map(\.dateInterval.start).sorted() where marker > previous {
                segments.append(WorkoutTimeSegment(startDate: previous, endDate: marker))
                previous = marker
            }
        }

        // Any read FAILURE here (cancellation, locked device, XPC drop) propagates
        // rather than collapsing to `.empty`, so the caller doesn't negative-cache a
        // false empty for a workout that actually has splits. The divergence guard
        // below still returns a genuine `.empty` non-throwing.
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(
            predicate: .quantitySample(
                type: distanceType,
                predicate: HKQuery.predicateForObjects(from: workout)
            ),
            options: [.orderByQuantitySampleStartDate]
        )

        var samples: [WorkoutDistanceSample] = []
        for try await result in descriptor.results(for: healthStore) {
            samples.append(WorkoutDistanceSample(
                startDate: result.dateInterval.start,
                endDate: result.dateInterval.end,
                meters: result.quantity.doubleValue(for: .meter())
            ))
        }
        samples.sort { $0.startDate < $1.startDate }

        // Total-validation guard: compare the summed sample meters to the
        // workout's recorded total. When no recorded total is available the
        // distance lives only in these samples, so there's nothing to overlap
        // and the samples pass through.
        let recordedTotal = workout.totalDistance?.doubleValue(for: .meter())
            ?? workout.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter())
        if let recordedTotal, recordedTotal > 0 {
            let summed = samples.reduce(0) { $0 + $1.meters }
            // Keep a tight 5% ceiling to reject multi-source overlap (samples
            // summing well *above* the recorded total — the double counting the
            // raw walk can't dedupe), but loosen the floor to the same 15% the
            // calculator's segment path tolerates for early-run GPS undercount,
            // so a legitimately undercounting workout isn't discarded here before
            // the calculator can recover its recorded splits.
            guard summed <= recordedTotal * 1.05, summed >= recordedTotal * 0.85 else {
                return .empty
            }
        }

        return WorkoutSplitData(
            distanceSamples: samples,
            segments: segments,
            stepSamples: try await workoutStepSamples(for: workout, type: type)
        )
    }

    /// Timestamped step increments from the workout's own step samples, for the
    /// per-split cadence column. `predicateForObjects(from:)` scopes the read to
    /// the workout's associated samples, avoiding the iPhone/Watch double counting
    /// a plain time-window query would sweep in (same rationale as the average
    /// step cadence statistics query). Empty for non-stepping activities or when
    /// the Workout Metrics permission is opted out. Any read FAILURE propagates
    /// (same rationale as the distance walk above) rather than collapsing to an
    /// empty cadence column — the store's catch returns `.empty` UNCACHED, so a
    /// transient failure just retries on reopen instead of silently losing
    /// cadence for the rest of the session.
    private func workoutStepSamples(for workout: HKWorkout, type: BodyWorkoutType) async throws -> [WorkoutStepSample] {
        guard type.supportsStepCadence,
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return []
        }

        // Split cadence is a Workout Metric, so honor the same opt-out as the summary
        // cadence path (`fetchStepCadence` is gated by `.workoutMetrics`). Without this
        // the split sidecar would surface cadence whenever `.stepCount` happens to be
        // authorized via the separate Steps toggle, ignoring the Workout Metrics opt-out.
        guard permissionSelection.includes(.workoutMetrics) else {
            return []
        }
        return try await readWorkoutStepSamples(for: workout, stepType: stepType)
    }

    private func readWorkoutStepSamples(for workout: HKWorkout, stepType: HKQuantityType) async throws -> [WorkoutStepSample] {
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(
            predicate: .quantitySample(
                type: stepType,
                predicate: HKQuery.predicateForObjects(from: workout)
            ),
            options: [.orderByQuantitySampleStartDate]
        )

        var samples: [WorkoutStepSample] = []
        for try await result in descriptor.results(for: healthStore) {
            samples.append(WorkoutStepSample(
                startDate: result.dateInterval.start,
                endDate: result.dateInterval.end,
                count: result.quantity.doubleValue(for: .count())
            ))
        }
        return samples.sorted { $0.startDate < $1.startDate }
    }
}
