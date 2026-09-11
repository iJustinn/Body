import BackgroundTasks
import Foundation

/// Independent of notification opt-in. The requested time is an earliest date;
/// iOS may delay or refuse a wake. Foreground repair remains available.
enum BodyDataRefreshScheduler {
    static let taskIdentifier = "com.zihengthedeveloper.Body.dataRefresh"
    @MainActor private static var checkingPending = false

    static func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task)
        }
    }

    @MainActor static func schedule() {
        guard !checkingPending else { return }
        checkingPending = true
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            Task { @MainActor in
                defer { checkingPending = false }
                let hasDomains = !BodyHealthObservationPolicy.registrations(
                    permissions: BodyAppRuntime.shared.workoutStore.permissionSelection, selection: .load(), includesCompanionConsumers: true).isEmpty
                guard hasDomains else {
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
                    return
                }
                // Do not replace an existing request on every foreground event:
                // submitting again would continually push its earliest date out.
                guard !requests.contains(where: { $0.identifier == taskIdentifier }) else { return }
                let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: BodyHealthObservationPolicy.fallbackInterval)
                try? BGTaskScheduler.shared.submit(request)
            }
        }
    }

    private static func handle(_ task: BGTask) {
        let completion = Completion(task)
        let work = Task { @MainActor in
            schedule()
            guard let lease = BodyBackgroundAdmission.acquire(), completion.install(lease) else {
                completion.finish(success: true)
                return
            }
            BodyAppRuntime.shared.startObserving()
            guard let coordinator = BodyAppRuntime.shared.workoutStore.healthChangeCoordinator else {
                completion.finish(success: false)
                return
            }
            let operation = Task { await coordinator.runBackground(lease: lease) }
            let outcome = await OneShotDeadlineRace.run(deadline: lease.remaining) { await operation.value }
            lease.invalidate()
            operation.cancel()
            BodyAppRuntime.shared.workoutStore.retireBackgroundRefresh()
            completion.finish(outcome: outcome)
        }
        task.expirationHandler = {
            completion.finish(success: false)
            work.cancel()
        }
    }

    /// Expiration fences results immediately, even if the MainActor is occupied.
    final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var complete: (@Sendable (Bool) -> Void)?
        private var lease: BodyBackgroundLease?
        init(_ task: BGTask) { complete = { task.setTaskCompleted(success: $0) } }
        init(complete: @escaping @Sendable (Bool) -> Void) { self.complete = complete }
        func install(_ lease: BodyBackgroundLease) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard complete != nil else { lease.invalidate(); return false }
            self.lease = lease
            return true
        }
        func finish(outcome: OneShotDeadlineRace.Outcome<Bool>) {
            switch outcome {
            // The result describes publication, not task health. A completed
            // no-op is a successful opportunity; pending obligations stay queued.
            case .finished: finish(success: true)
            case .timedOut: finish(success: false)
            }
        }

        func finish(success: Bool) {
            lock.lock()
            let pending = complete
            complete = nil
            lease?.invalidate()
            lock.unlock()
            pending?(success)
        }
    }
}
