import Foundation
import HealthKit

extension HealthKitFetchEngine {
    /// Only the foreground journal owner calls this. Existing fetch tiers
    /// and interactive dashboard paths do not gain an additional leaf.
    func fetchWorkoutChanges(_ request: BodyWorkoutChangesRequest) async -> BodyHealthReadOutcome<BodyWorkoutChanges> {
        guard permissionSelection.includes(.workouts) else { return .cancelled }
        let semaphore = HealthKitQueryPool.current.semaphore
        guard await semaphore.acquireForCurrentTask() else { return .cancelled }
        defer { semaphore.release() }
        guard BodyBackgroundLease.current?.isValid != false else { return .cancelled }
        guard !Task.isCancelled else { return .cancelled }
        BodyRefreshProfile.shared.enterQuery()
        defer { BodyRefreshProfile.shared.exitQuery() }
        return await healthStore.workoutChanges(request)
    }
}
