import Foundation
import HealthKit

/// iOS-only observation seam. The watch-shared query protocol stays unchanged.
@MainActor
protocol BodyHealthObserving: AnyObject {
    func observe(_ type: HKSampleType,
                 handler: @escaping @Sendable (BodyHealthObserverDelivery) -> Void) -> UUID
    func stop(_ id: UUID)
    func enable(_ type: HKSampleType, frequency: HKUpdateFrequency) async -> Bool
    func disable(_ type: HKSampleType) async -> Bool
}

/// Completion can race shutdown/error paths. Invoke the HealthKit callback once,
/// outside the lock, even when invalidation persistence fails.
final class BodyHealthObserverDelivery: @unchecked Sendable {
    let failed: Bool
    private let lock = NSLock()
    private var completion: (() -> Void)?

    init(failed: Bool, completion: @escaping () -> Void) {
        self.failed = failed
        self.completion = completion
    }

    func complete() {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?()
    }
}

@MainActor
final class BodyHealthKitObserver: BodyHealthObserving {
    private let store: HKHealthStore
    private var queries: [UUID: HKObserverQuery] = [:]

    init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    func observe(_ type: HKSampleType,
                 handler: @escaping @Sendable (BodyHealthObserverDelivery) -> Void) -> UUID {
        let id = UUID()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, complete, error in
            handler(BodyHealthObserverDelivery(failed: error != nil, completion: complete))
        }
        queries[id] = query
        store.execute(query)
        return id
    }

    func stop(_ id: UUID) {
        if let query = queries.removeValue(forKey: id) { store.stop(query) }
    }

    func enable(_ type: HKSampleType, frequency: HKUpdateFrequency) async -> Bool {
        await withCheckedContinuation { continuation in
            store.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
                continuation.resume(returning: success && error == nil)
            }
        }
    }

    func disable(_ type: HKSampleType) async -> Bool {
        await withCheckedContinuation { continuation in
            store.disableBackgroundDelivery(for: type) { success, error in
                continuation.resume(returning: success && error == nil)
            }
        }
    }
}

/// Retains registrations and acknowledges every delivery, including the
/// foreground initialization callback that does not represent a new mutation.
@MainActor
final class BodyHealthChangeObserver {
    typealias Capture = @MainActor (String, Bool) async -> Void
    private let observer: any BodyHealthObserving
    private let capture: Capture
    private let suppressesInitialDelivery: @MainActor () -> Bool
    private var initialDeliveries: Set<UUID> = []
    private var handles: [String: UUID] = [:]
    private var types: [String: HKSampleType] = [:]
    private var enabled: [String: HKUpdateFrequency] = [:]
    private var desired: [String: BodyHealthObservation] = [:]
    private var configuring = false
    private var configurationRevision = 0

    init(observer: any BodyHealthObserving,
         suppressesInitialDelivery: @escaping @MainActor () -> Bool = { false },
         capture: @escaping Capture) {
        self.observer = observer
        self.suppressesInitialDelivery = suppressesInitialDelivery
        self.capture = capture
    }

    /// Reentrant configuration changes coalesce behind one enable/disable owner.
    /// Failed enable/disable remains retryable on the next configure call.
    func configure(_ registrations: [BodyHealthObservation]) async {
        let next = Dictionary(registrations.map { ($0.type.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        if next.mapValues({ $0.frequency.rawValue }) != desired.mapValues({ $0.frequency.rawValue }) {
            configurationRevision &+= 1
        }
        desired = next
        guard !configuring else { return }
        configuring = true
        defer { configuring = false }
        var attemptedEnable: Set<String> = []
        var attemptedDisable: Set<String> = []
        var processedRevision = configurationRevision
        while true {
            if processedRevision != configurationRevision {
                attemptedEnable.removeAll()
                attemptedDisable.removeAll()
                processedRevision = configurationRevision
            }
            if let id = handles.keys.first(where: { desired[$0] == nil }) {
                if let handle = handles.removeValue(forKey: id) { observer.stop(handle) }
                if let retired = registrationTokens.removeValue(forKey: id) {
                    initialDeliveries.remove(retired)
                }
                // Keep its type until disable succeeds, including enable that
                // completed after a configuration change while it was suspended.
                continue
            }
            if let id = types.keys.first(where: { desired[$0] == nil && !attemptedDisable.contains($0) }),
               let type = types[id] {
                attemptedDisable.insert(id)
                if await observer.disable(type) {
                    enabled.removeValue(forKey: id)
                    types.removeValue(forKey: id)
                }
                continue
            }
            if let registration = desired.values.first(where: { handles[$0.type.identifier] == nil }) {
                let id = registration.type.identifier
                types[id] = registration.type
                let token = UUID()
                if suppressesInitialDelivery() { initialDeliveries.insert(token) }
                // A separate identity prevents late deliveries from a stopped
                // query being admitted after the same type is registered again.
                let handle = observer.observe(registration.type) { [weak self] delivery in
                    Task { @MainActor in
                        defer { delivery.complete() }
                        guard let self, self.registrationTokens[id] == token,
                              self.desired[id] != nil else { return }
                        let initial = self.initialDeliveries.remove(token) != nil
                        // Never discard the first headless delivery: it may be
                        // the mutation that launched the process. Errors retain
                        // their conservative repair obligation too.
                        if initial, !delivery.failed, self.suppressesInitialDelivery() { return }
                        await self.capture(id, delivery.failed)
                    }
                }
                registrationTokens[id] = token
                handles[id] = handle
                continue
            }
            if let registration = desired.values.first(where: {
                enabled[$0.type.identifier] != $0.frequency && !attemptedEnable.contains($0.type.identifier)
            }) {
                let id = registration.type.identifier
                attemptedEnable.insert(id)
                if await observer.enable(registration.type, frequency: registration.frequency) {
                    enabled[id] = registration.frequency
                }
                continue
            }
            return
        }
    }

    private var registrationTokens: [String: UUID] = [:]
}
