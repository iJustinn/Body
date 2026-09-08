import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Only the foreground journal owner calls this. Existing fetch tiers
    /// and interactive dashboard paths do not gain an additional leaf.
    func fetchWorkoutChanges(_ request: BodyWorkoutChangesRequest) async -> BodyHealthReadOutcome<BodyWorkoutChanges> {
        guard permissionSelection.includes(.workouts) else { return .cancelled }
        let semaphore = HealthKitQueryPool.current.semaphore
        await semaphore.acquire()
        defer { semaphore.release() }
        guard !Task.isCancelled else { return .cancelled }
        BodyRefreshProfile.shared.enterQuery()
        defer { BodyRefreshProfile.shared.exitQuery() }
        return await healthStore.workoutChanges(request)
    }
}
