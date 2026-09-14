import Foundation

/// One coalesced foreground evaluation, independent of the visible refresh.
/// Cancellation retires send authority even if a HealthKit read returns late.
@MainActor
final class BodyForegroundNotificationScheduler {
    private let isEligible: () -> Bool
    private let evaluate: (HealthDashboardPublicationToken) async -> Void
    private var task: Task<Void, Never>?
    private var token: HealthDashboardPublicationToken?
    private var requested = false

    init(isEligible: @escaping () -> Bool,
         evaluate: @escaping (HealthDashboardPublicationToken) async -> Void) {
        self.isEligible = isEligible
        self.evaluate = evaluate
    }

    func request() {
        requested = true
        resumeIfEligible()
    }

    func suspend() {
        token?.invalidate()
        task?.cancel()
    }

    private func resumeIfEligible() {
        guard requested, task == nil, isEligible() else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while self.requested, self.isEligible(), !Task.isCancelled {
                self.requested = false
                let token = HealthDashboardPublicationToken()
                self.token = token
                await self.evaluate(token)
                token.invalidate()
                self.token = nil
            }
            self.task = nil
            // A request made while cancellation was unwinding is retained.
            self.resumeIfEligible()
        }
    }
}
