import Foundation

/// One cancellable unit at a time, rotating between ready owners. A task
/// waiting for another turn does not own the slot. Retired operations keep
/// their slot until they exit, while foreground work uses its own admission.
@MainActor
final class BodyMaintenanceScheduler {
    enum Owner: Int, CaseIterable { case observer, journal, records, stressInputs, stressHistory, ringHistory, trendHistory }

    private struct Request {
        let id: UUID
        let owner: Owner
        let operation: @MainActor (HealthDashboardPublicationToken) async -> Bool
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let isEligible: @MainActor () -> Bool
    private var requests: [Request] = []
    private var active: (id: UUID, token: HealthDashboardPublicationToken, task: Task<Void, Never>)?
    private var nextOwner = 0

    init(isEligible: @escaping @MainActor () -> Bool) { self.isEligible = isEligible }

    var hasActiveUnit: Bool { active != nil }

    /// Cleanup may join a retired unit; foreground admission never does.
    func awaitRetiredCompletion() async {
        guard let active, !active.token.isValid else { return }
        await active.task.value
    }

    func run(_ owner: Owner,
             operation: @escaping @MainActor (HealthDashboardPublicationToken) async -> Bool) async -> Bool {
        guard !Task.isCancelled else { return false }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                requests.append(Request(id: id, owner: owner, operation: operation, continuation: continuation))
                resumeIfEligible()
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    /// Admission is suspended by the caller's eligibility state. Cancel queued
    /// callers too, so an obsolete loop cannot restart after foreground work.
    func suspend() {
        #if DEBUG
        if active != nil { BodyObserverRefreshDiagnostics.log("maintenance preempt queued=\(requests.count)") }
        #endif
        active?.token.invalidate()
        active?.task.cancel()
        let waiting = requests
        requests.removeAll()
        for request in waiting { request.continuation.resume(returning: false) }
    }

    func resumeIfEligible() {
        guard active == nil, !requests.isEmpty, isEligible() else { return }
        let owners = Owner.allCases
        guard let index = (0..<owners.count).lazy.compactMap({ offset in
            self.requests.firstIndex { $0.owner == owners[(self.nextOwner + offset) % owners.count] }
        }).first else { return }
        let request = requests.remove(at: index)
        nextOwner = (request.owner.rawValue + 1) % owners.count
        let token = HealthDashboardPublicationToken()
        let task = Task { @MainActor in
            #if DEBUG
            let started = ContinuousClock.now
            BodyObserverRefreshDiagnostics.log("maintenance start owner=\(request.owner) queued=\(self.requests.count)")
            #endif
            let result = await request.operation(token)
            let accepted = result && token.isValid && !Task.isCancelled
            #if DEBUG
            BodyObserverRefreshDiagnostics.log("maintenance end owner=\(request.owner) accepted=\(accepted) duration=\(BodyObserverRefreshDiagnostics.elapsed(since: started))")
            #endif
            token.invalidate()
            self.active = nil
            request.continuation.resume(returning: accepted)
            self.resumeIfEligible()
        }
        active = (request.id, token, task)
    }

    private func cancel(_ id: UUID) {
        if active?.id == id {
            active?.token.invalidate()
            active?.task.cancel()
        } else if let index = requests.firstIndex(where: { $0.id == id }) {
            requests.remove(at: index).continuation.resume(returning: false)
        }
    }
}
