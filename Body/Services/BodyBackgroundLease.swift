import Foundation

/// An admission/publication fence, not a promise that healthd stops on time.
final class BodyBackgroundLease: @unchecked Sendable {
    @TaskLocal static var current: BodyBackgroundLease?
    private let lock = NSLock()
    private var admitted = true
    private let deadline: ContinuousClock.Instant

    init(duration: Duration = BodyHealthObservationPolicy.appRefreshDeadline) {
        deadline = ContinuousClock.now.advanced(by: duration)
    }

    var remaining: Duration { max(.zero, ContinuousClock.now.duration(to: deadline)) }
    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return admitted && ContinuousClock.now < deadline
    }
    func invalidate() {
        lock.lock()
        admitted = false
        lock.unlock()
    }

    nonisolated(nonsending)
    func run<Value>(_ operation: nonisolated(nonsending) () async throws -> Value) async rethrows -> Value {
        try await Self.$current.withValue(self, operation: {
            try await HealthKitQueryPool.$current.withValue(.appRefresh, operation: operation)
        })
    }
}

/// Data and notification wakes share admission instead of racing two budgets.
@MainActor
enum BodyBackgroundAdmission {
    private static var current: BodyBackgroundLease?
    static func acquire(isForegroundActive: Bool? = nil) -> BodyBackgroundLease? {
        guard !(isForegroundActive ?? BodyAppRuntime.isForegroundActive), current?.isValid != true else { return nil }
        let lease = BodyBackgroundLease()
        current = lease
        return lease
    }
    static func cancel() {
        current?.invalidate()
        current = nil
    }
}
