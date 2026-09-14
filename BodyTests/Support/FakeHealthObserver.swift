import Foundation
import HealthKit
@testable import Body

@MainActor
final class FakeHealthObserver: BodyHealthObserving {
    struct Registration {
        let type: HKSampleType
        let handler: @Sendable (BodyHealthObserverDelivery) -> Void
    }
    private(set) var registrations: [UUID: Registration] = [:]
    private(set) var stopped: [UUID] = []
    private(set) var enables: [(String, HKUpdateFrequency)] = []
    private(set) var disables: [String] = []
    var enableResults: [Bool] = []
    var disableResults: [Bool] = []
    var beforeEnable: (() async -> Void)?

    func observe(_ type: HKSampleType,
                 handler: @escaping @Sendable (BodyHealthObserverDelivery) -> Void) -> UUID {
        let id = UUID()
        registrations[id] = Registration(type: type, handler: handler)
        return id
    }
    func stop(_ id: UUID) {
        // Retain the old callback so tests can fire an already-enqueued delivery.
        stopped.append(id)
    }
    func enable(_ type: HKSampleType, frequency: HKUpdateFrequency) async -> Bool {
        enables.append((type.identifier, frequency))
        if let beforeEnable { await beforeEnable() }
        return enableResults.isEmpty ? true : enableResults.removeFirst()
    }
    func disable(_ type: HKSampleType) async -> Bool {
        disables.append(type.identifier)
        return disableResults.isEmpty ? true : disableResults.removeFirst()
    }
    func fire(_ id: UUID, failed: Bool = false, completion: @escaping () -> Void) {
        registrations[id]?.handler(BodyHealthObserverDelivery(failed: failed, completion: completion))
    }
}
