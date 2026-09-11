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
                  let steps = await self.fetchIntradayDaySamples(for: .steps, calendar: calendar, startDate: day, endDate: now),
                  let energy = await self.fetchIntradayDaySamples(for: .activeEnergy, calendar: calendar, startDate: day, endDate: now),
                  let sleep = await self.fetchStressBackfillSleepIntervals(startDate: day, endDate: now, calendar: calendar),
                  let workouts = await self.notificationWorkoutIntervals(start: day.addingTimeInterval(-86400), end: now),
                  self.queryContextRevision == revision, !Task.isCancelled else { return nil }
            return StressDayInput(date: day, heartRateSamples: hr.points, sdnnSamples: sdnn.points,
                rmssdSamples: rmssd.points, hourlySteps: steps.points, hourlyActiveEnergy: energy.points,
                workoutIntervals: workouts, sleepInterval: sleep[day])
        }
    }

    private func notificationWorkoutIntervals(start: Date, end: Date) async -> [DateInterval]? {
        await runCancellableQuery(cancelledValue: Optional<[DateInterval]>.none) { resume in
            HKSampleQuery(sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil, let workouts = samples as? [HKWorkout] else { resume(nil); return }
                resume(workouts.compactMap {
                    guard $0.endDate >= $0.startDate else { return nil }
                    return DateInterval(start: $0.startDate, end: $0.endDate)
                })
            }
        }
    }
}
