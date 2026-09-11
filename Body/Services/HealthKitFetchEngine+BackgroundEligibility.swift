import Foundation
import HealthKit

/// A recorded decision permits an attempted read; HealthKit deliberately does
/// not disclose whether read access was granted. Never use this as data coverage.
enum BodyBackgroundReadEligibility: Equatable, Sendable {
    case eligible
    case deferred
    case unavailable
}

extension HealthKitFetchEngine {
    /// Uses the existing serialized status transaction, with prompting disabled.
    /// Independent of the UI store's launch-time `.unknown` authorization state.
    /// The caller includes this read in its deadline and rechecks protected data
    /// and context before admitting queries and publication.
    func backgroundReadEligibility(
        healthDataAvailable: Bool = HKHealthStore.isHealthDataAvailable(),
        protectedDataAvailable: Bool
    ) async -> BodyBackgroundReadEligibility {
        guard healthDataAvailable else { return .unavailable }
        guard protectedDataAvailable, !Task.isCancelled else { return .deferred }
        let revision = queryContextRevision
        guard !(await isAuthorizationPromptInFlight) else { return .deferred }
        do {
            let result = try await requestAuthorization(allowPrompt: false)
            guard !Task.isCancelled, revision == queryContextRevision else { return .deferred }
            return result == .authorized(didPrompt: false) ? .eligible : .deferred
        } catch {
            return .deferred
        }
    }
}
