import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Transient today-only inputs. No dashboard merges, backfills, or derived
    /// freshness writes. Leaf queries retain the existing two-permit pool.
    func fetchNotificationStressInput(now: Date, calendar: Calendar) async -> StressDayInput? {
        let day = calendar.startOfDay(for: now)
        let revision = queryContextRevision
        guard permissionSelection.includes(.heart), permissionSelection.includes(.steps),
              permissionSelection.includes(.energy), permissionSelection.includes(.sleep),
              permissionSelection.includes(.workouts) else { return nil }
        return await withBackgroundQueryPool {
            guard let hr = await self.fetchIntradayDaySamples(for: .heartRate, calendar: calendar, startDate: day, endDate: now),
                  let sdnn = await self.fetchIntradayDaySamples(for: .heartRateVariability, calendar: calendar, startDate: day, endDate: now),
                  let rmssd = await self.fetchHeartbeatRMSSDSamples(startDate: day, endDate: now),
                  let steps = await self.fetchStressMovementSamples(for: .steps, calendar: calendar, startDate: day, endDate: now),
                  let energy = await self.fetchStressMovementSamples(for: .activeEnergy, calendar: calendar, startDate: day, endDate: now),
                  let sleep = await self.fetchStressBackfillSleepIntervals(startDate: day, endDate: now, calendar: calendar),
                  let workouts = await self.notificationWorkoutMaskIntervals(start: day.addingTimeInterval(-86400), end: now),
                  self.queryContextRevision == revision, !Task.isCancelled else { return nil }
            return StressDayInput(date: day, heartRateSamples: hr.points, sdnnSamples: sdnn.points,
                rmssdSamples: rmssd.points, quarterHourSteps: steps.points, quarterHourActiveEnergy: energy.points,
                workoutMaskIntervals: workouts, sleepInterval: sleep[day])
        }
    }

    /// Each workout's masked span, from the same `StressDayInput.workoutMaskInterval`
    /// (and activity type mapper) the snapshot path uses, so an alert reads the
    /// recovery tail the Stress card does. A zero length workout is now dropped
    /// there, as on the snapshot path: with a tail it would mask minutes of nothing.
    private func notificationWorkoutMaskIntervals(start: Date, end: Date) async -> [DateInterval]? {
        await runCancellableQuery(cancelledValue: Optional<[DateInterval]>.none) { resume in
            HKSampleQuery(sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil, let workouts = samples as? [HKWorkout] else { resume(nil); return }
                resume(workouts.compactMap {
                    StressDayInput.workoutMaskInterval(
                        type: HealthKitWorkoutStore.workoutType(for: $0.workoutActivityType),
                        start: $0.startDate,
                        end: $0.endDate
                    )
                })
            }
        }
    }
}
