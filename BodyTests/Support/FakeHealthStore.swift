//
//  FakeHealthStore.swift
//  BodyTests
//
//  A scriptable `BodyHealthQuerying` so the shared query leaves — and anything
//  built on them — can be driven from a test host, which cannot run a real
//  `HKHealthStore` (HealthKit needs bundle identity, and a device's own data
//  would make every assertion environment-dependent).
//
//  Scripting is keyed by the queried type's identifier, per read kind, so one
//  fake can answer a fan-out that mixes several metrics. An UNSCRIPTED leaf
//  read defaults to `.never`: it suspends until the awaiting task is cancelled
//  and then returns `.cancelled`, which is what makes deadline/cancellation
//  behaviour testable without timing luck.
//
//  Only the leaf reads are scriptable. `execute` records the query and never
//  resumes it (the engine-internal callback sites own their own continuations,
//  which this fake has no way to reach), and the descriptor reads throw:
//  no production path under test takes them.
//

import Foundation
import HealthKit
@testable import Body

final class FakeHealthStore: BodyHealthQuerying, @unchecked Sendable {
    struct Unscripted: Error {}

    /// What a scripted leaf read answers with.
    enum Script {
        /// Resolves a `samples` read.
        case samples([HKSample])
        /// Resolves a `sources` read.
        case sources([HKSource])
        /// Resolves any leaf read as a failure. `nil` is HealthKit's
        /// "neither samples nor an error" (a locked device), which must stay
        /// distinct from an empty success.
        case failure(Error?)
        /// Suspends until the awaiting task is cancelled, then answers
        /// `.cancelled`. The default for unscripted reads.
        case never
        indirect case delay(Duration, then: Script)
    }

    /// Which leaf read a recorded request came from, with the queried type's
    /// identifier.
    enum LeafRequest: Equatable {
        case samples(String)
        case sources(String)
        case statistics(String)
        case statisticsCollection(String)
    }

    private let lock = NSLock()
    private var sampleScripts: [String: Script] = [:]
    private var sourceScripts: [String: Script] = [:]
    private var statisticsScripts: [String: Script] = [:]
    private var statisticsCollectionScripts: [String: Script] = [:]
    private var executedQueriesValue: [HKQuery] = []
    private var stoppedQueriesValue: [HKQuery] = []
    private var leafRequestsValue: [LeafRequest] = []
    private var savedObjectsValue: [HKObject] = []

    // MARK: - Scripting

    func scriptSamples(for type: HKSampleType, _ script: Script) {
        lock.lock(); sampleScripts[type.identifier] = script; lock.unlock()
    }

    func scriptSources(for type: HKSampleType, _ script: Script) {
        lock.lock(); sourceScripts[type.identifier] = script; lock.unlock()
    }

    func scriptStatistics(for type: HKQuantityType, _ script: Script) {
        lock.lock(); statisticsScripts[type.identifier] = script; lock.unlock()
    }

    func scriptStatisticsCollection(for type: HKQuantityType, _ script: Script) {
        lock.lock(); statisticsCollectionScripts[type.identifier] = script; lock.unlock()
    }

    // MARK: - Recorded traffic

    var executedQueries: [HKQuery] {
        lock.lock(); defer { lock.unlock() }; return executedQueriesValue
    }

    var stoppedQueries: [HKQuery] {
        lock.lock(); defer { lock.unlock() }; return stoppedQueriesValue
    }

    var leafRequests: [LeafRequest] {
        lock.lock(); defer { lock.unlock() }; return leafRequestsValue
    }

    var savedObjects: [HKObject] {
        lock.lock(); defer { lock.unlock() }; return savedObjectsValue
    }

    // MARK: - Callback passthroughs

    func execute(_ query: HKQuery) {
        lock.lock(); executedQueriesValue.append(query); lock.unlock()
        // The phone's hourly cumulative path still uses a callback collection
        // query. Honor the same failure script as the async seam so store-level
        // fallback tests reach their commit boundary instead of timing out.
        if let collection = query as? HKStatisticsCollectionQuery,
           let type = collection.objectType as? HKQuantityType,
           case .failure(let error) = script(statisticsCollectionScripts, type.identifier) {
            record(.statisticsCollection(type.identifier))
            collection.initialResultsHandler?(collection, nil, error)
        }
    }

    func stop(_ query: HKQuery) {
        lock.lock(); stoppedQueriesValue.append(query); lock.unlock()
    }

    // MARK: - Descriptor reads

    func result<Q: HKAsyncQuery>(for query: Q) async throws -> Q.Output {
        throw Unscripted()
    }

    func results<Q: HKAsyncSequenceQuery>(for query: Q) -> Q.Sequence {
        // No production path under test reads a descriptor sequence, and the
        // descriptors' `Sequence` types have no public initializer to stand in
        // for one.
        fatalError("FakeHealthStore cannot vend a descriptor result sequence")
    }

    // MARK: - Leaf reads

    func samples(_ request: BodySampleRequest) async -> BodyHealthReadOutcome<[HKSample]> {
        let identifier = request.sampleType.identifier
        record(.samples(identifier))
        return await resolve(script(sampleScripts, identifier)) { script in
            switch script {
            case .samples(let samples):
                return .success(samples)
            case .failure(let error):
                return .failure(error)
            case .sources, .never, .delay:
                return nil
            }
        }
    }

    func sources(for sampleType: HKSampleType) async -> BodyHealthReadOutcome<[HKSource]> {
        let identifier = sampleType.identifier
        record(.sources(identifier))
        return await resolve(script(sourceScripts, identifier)) { script in
            switch script {
            case .sources(let sources):
                return .success(sources)
            case .failure(let error):
                return .failure(error)
            case .samples, .never, .delay:
                return nil
            }
        }
    }

    func statistics(_ request: BodyStatisticsRequest) async -> BodyHealthReadOutcome<HKStatistics> {
        let identifier = request.quantityType.identifier
        record(.statistics(identifier))
        return await resolve(script(statisticsScripts, identifier)) { script in
            // `HKStatistics` has no public initializer, so only the failure and
            // cancellation halves of this leaf are scriptable.
            switch script {
            case .failure(let error):
                return .failure(error)
            case .samples, .sources, .never, .delay:
                return nil
            }
        }
    }

    func statisticsCollection(
        _ request: BodyStatisticsCollectionRequest
    ) async -> BodyHealthReadOutcome<HKStatisticsCollection> {
        let identifier = request.quantityType.identifier
        record(.statisticsCollection(identifier))
        return await resolve(script(statisticsCollectionScripts, identifier)) { script in
            // `HKStatisticsCollection` has no public initializer; see `statistics`.
            switch script {
            case .failure(let error):
                return .failure(error)
            case .samples, .sources, .never, .delay:
                return nil
            }
        }
    }

    // MARK: - Authorization, writes, characteristics

    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>?,
        read typesToRead: Set<HKObjectType>?,
        completion: @escaping @Sendable (Bool, (any Error)?) -> Void
    ) {
        completion(true, nil)
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        .sharingAuthorized
    }

    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        .unnecessary
    }

    func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        lock.lock(); savedObjectsValue.append(contentsOf: objects); lock.unlock()
        completion(true, nil)
    }

    func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        save([object], withCompletion: completion)
    }

    func delete(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        completion(true, nil)
    }

    @discardableResult
    func relateWorkoutEffortSample(
        _ sample: HKSample,
        with workout: HKWorkout,
        activity: HKWorkoutActivity?
    ) async throws -> Bool {
        true
    }

    func dateOfBirthComponents() throws -> DateComponents {
        throw Unscripted()
    }

    func biologicalSex() throws -> HKBiologicalSexObject {
        throw Unscripted()
    }

    // MARK: - Resolution

    private func record(_ request: LeafRequest) {
        lock.lock(); leafRequestsValue.append(request); lock.unlock()
    }

    private func script(_ table: [String: Script], _ identifier: String) -> Script {
        lock.lock(); defer { lock.unlock() }; return table[identifier] ?? .never
    }

    /// Applies `map` to the script; `nil` (the script cannot answer this read
    /// kind, or is `.never`) suspends until cancellation and answers `.cancelled`.
    private func resolve<Value>(
        _ script: Script,
        _ map: (Script) -> BodyHealthReadOutcome<Value>?
    ) async -> BodyHealthReadOutcome<Value> {
        if case .delay(let duration, let inner) = script {
            do {
                try await Task.sleep(for: duration)
            } catch {
                return .cancelled
            }
            return await resolve(inner, map)
        }
        if let outcome = map(script) {
            return outcome
        }
        return await neverResolving()
    }

    /// Suspends until the awaiting task is cancelled. `CheckedContinuation`
    /// enforces the one-shot resume; `OneShotResume` keeps `onCancel` and a
    /// (never-arriving) result from racing.
    private func neverResolving<Value>() async -> BodyHealthReadOutcome<Value> {
        let resume = OneShotResume<BodyHealthReadOutcome<Value>>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resume.arm(continuation)
            }
        } onCancel: {
            resume.fire(.cancelled)
        }
    }
}

/// Lock-guarded one-shot continuation holder for `FakeHealthStore`'s `.never`
/// reads: `onCancel` can fire before, during or after the continuation is
/// installed.
private final class OneShotResume<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var pendingValue: Value?
    private var settled = false

    func arm(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock()
        if settled {
            lock.unlock()
            return
        }
        if let pendingValue {
            settled = true
            lock.unlock()
            continuation.resume(returning: pendingValue)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func fire(_ value: Value) {
        lock.lock()
        guard !settled else {
            lock.unlock()
            return
        }
        guard let continuation else {
            pendingValue = value
            lock.unlock()
            return
        }
        settled = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
    }
}
