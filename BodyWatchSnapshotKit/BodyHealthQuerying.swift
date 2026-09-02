//
//  BodyHealthQuerying.swift
//  BodyWatchSnapshotKit
//
//  The seam between Body's HealthKit callers and `HKHealthStore`. Every query
//  the iOS engine and the shared kit leaves issue goes through this protocol,
//  so tests can drive the leaves (and anything built on them) against a
//  scripted fake instead of the real store, which a test host cannot exercise
//  without HealthKit bundle identity.
//
//  Three shapes live here, deliberately kept apart:
//
//  * The *leaf reads* (`samples`, `sources`, `statistics`,
//    `statisticsCollection`) are the scriptable surface. Their `HKHealthStore`
//    implementations are the leaves' own callback queries MOVED here verbatim —
//    `HKSampleQuery`/`HKStatisticsQuery`/`HKStatisticsCollectionQuery`/
//    `HKSourceQuery`, not the async descriptors — because the descriptors
//    collapse "HealthKit returned neither samples nor an error" (a locked
//    device) into a throw, and because the leaves' `NSSortDescriptor`s have no
//    descriptor equivalent. That distinction is `BodyHealthReadOutcome.failure(nil)`,
//    and it is why a locked device keeps cached values instead of blanking a card.
//  * The *callback passthroughs* (`execute`, `stop`) carry the engine-internal
//    query sites, which own their own continuations and cancellation.
//  * The *descriptor reads*, *authorization*, *writes* and *characteristics* are
//    forwarded 1:1 to the concrete store.
//
//  Cancellation lives here rather than in the leaves: each leaf read wraps its
//  query in `BodyQueryResumeBox`, so a cancelled awaiting task yields
//  `.cancelled` and the in-flight `HKQuery` is stopped exactly once.
//

import Foundation
import HealthKit

/// Tri-state read result. `failure(nil)` is "HealthKit returned neither samples
/// nor an error" (device locked, store unavailable) and must stay distinct from
/// an empty success, which is a genuine absence.
enum BodyHealthReadOutcome<Value> {
    case success(Value)
    case failure(Error?)
    case cancelled
}

/// One `HKSampleQuery`'s inputs. `@unchecked Sendable` for the same reason the
/// engine's hoisted predicates are `nonisolated(unsafe)`: `NSPredicate` and
/// `NSSortDescriptor` are not marked `Sendable` by Foundation, but each is
/// built at the call site, never mutated afterwards, and only read by the query.
struct BodySampleRequest: @unchecked Sendable {
    let sampleType: HKSampleType
    let predicate: NSPredicate?
    let limit: Int
    let sortDescriptors: [NSSortDescriptor]

    init(sampleType: HKSampleType, predicate: NSPredicate?, limit: Int, sortDescriptors: [NSSortDescriptor]) {
        self.sampleType = sampleType
        self.predicate = predicate
        self.limit = limit
        self.sortDescriptors = sortDescriptors
    }
}

/// One `HKStatisticsQuery`'s inputs. `@unchecked Sendable`: see `BodySampleRequest`.
struct BodyStatisticsRequest: @unchecked Sendable {
    let quantityType: HKQuantityType
    let predicate: NSPredicate?
    let options: HKStatisticsOptions

    init(quantityType: HKQuantityType, predicate: NSPredicate?, options: HKStatisticsOptions) {
        self.quantityType = quantityType
        self.predicate = predicate
        self.options = options
    }
}

/// One `HKStatisticsCollectionQuery`'s inputs. `@unchecked Sendable`: see `BodySampleRequest`.
struct BodyStatisticsCollectionRequest: @unchecked Sendable {
    let quantityType: HKQuantityType
    let predicate: NSPredicate?
    let options: HKStatisticsOptions
    let anchorDate: Date
    let intervalComponents: DateComponents

    init(
        quantityType: HKQuantityType,
        predicate: NSPredicate?,
        options: HKStatisticsOptions,
        anchorDate: Date,
        intervalComponents: DateComponents
    ) {
        self.quantityType = quantityType
        self.predicate = predicate
        self.options = options
        self.anchorDate = anchorDate
        self.intervalComponents = intervalComponents
    }
}

/// Everything Body asks of `HKHealthStore`, so the store can be substituted in
/// tests. `HKHealthStore` itself is `NS_SWIFT_SENDABLE`, which is what lets the
/// engine hoist an `any BodyHealthQuerying` into the `@Sendable` bodies its
/// external-query bracket runs unstructured.
protocol BodyHealthQuerying: AnyObject, Sendable {
    // Callback passthroughs: the engine-internal query sites own their own
    // continuations and cancellation, so they only need execute/stop.
    func execute(_ query: HKQuery)
    func stop(_ query: HKQuery)

    // Descriptor reads (route, quantity series, statistics collections,
    // activity summaries): forwarded 1:1.
    func result<Q: HKAsyncQuery>(for query: Q) async throws -> Q.Output
    func results<Q: HKAsyncSequenceQuery>(for query: Q) -> Q.Sequence

    // Leaf reads: the scriptable surface. Cancelling the awaiting task yields
    // `.cancelled` and stops the query.
    func samples(_ request: BodySampleRequest) async -> BodyHealthReadOutcome<[HKSample]>
    func sources(for sampleType: HKSampleType) async -> BodyHealthReadOutcome<[HKSource]>
    func statistics(_ request: BodyStatisticsRequest) async -> BodyHealthReadOutcome<HKStatistics>
    func statisticsCollection(
        _ request: BodyStatisticsCollectionRequest
    ) async -> BodyHealthReadOutcome<HKStatisticsCollection>

    // Authorization, writes and characteristics: forwarded 1:1, in the exact
    // shapes the call sites use.
    func requestAuthorization(
        toShare typesToShare: Set<HKSampleType>?,
        read typesToRead: Set<HKObjectType>?,
        completion: @escaping @Sendable (Bool, (any Error)?) -> Void
    )
    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus
    func statusForAuthorizationRequest(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus
    func save(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void)
    func save(_ object: HKObject, withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void)
    func delete(_ objects: [HKObject], withCompletion completion: @escaping @Sendable (Bool, (any Error)?) -> Void)
    @discardableResult
    func relateWorkoutEffortSample(
        _ sample: HKSample,
        with workout: HKWorkout,
        activity: HKWorkoutActivity?
    ) async throws -> Bool
    func dateOfBirthComponents() throws -> DateComponents
    func biologicalSex() throws -> HKBiologicalSexObject
}

extension HKHealthStore: BodyHealthQuerying {
    // The descriptor reads invert the framework's spelling (`descriptor.result(for: store)`)
    // so the store stays the single seam every caller talks to.
    func result<Q: HKAsyncQuery>(for query: Q) async throws -> Q.Output {
        try await query.result(for: self)
    }

    func results<Q: HKAsyncSequenceQuery>(for query: Q) -> Q.Sequence {
        query.results(for: self)
    }

    // `execute`, `stop`, `authorizationStatus(for:)`,
    // `statusForAuthorizationRequest(toShare:read:)`, `requestAuthorization(toShare:read:completion:)`,
    // `save`, `delete`, `relateWorkoutEffortSample`, `dateOfBirthComponents` and
    // `biologicalSex` are satisfied by the framework's own methods.

    func samples(_ request: BodySampleRequest) async -> BodyHealthReadOutcome<[HKSample]> {
        await bodyCancellableRead { resume in
            let query = HKSampleQuery(
                sampleType: request.sampleType,
                predicate: request.predicate,
                limit: request.limit,
                sortDescriptors: request.sortDescriptors
            ) { _, samples, error in
                guard let samples else {
                    resume(.failure(error))
                    return
                }

                resume(.success(samples))
            }

            self.execute(query)
            return query
        }
    }

    func sources(for sampleType: HKSampleType) async -> BodyHealthReadOutcome<[HKSource]> {
        await bodyCancellableRead { resume in
            let query = HKSourceQuery(
                sampleType: sampleType,
                samplePredicate: nil
            ) { _, sources, error in
                guard let sources else {
                    resume(.failure(error))
                    return
                }

                resume(.success(Array(sources)))
            }

            self.execute(query)
            return query
        }
    }

    func statistics(_ request: BodyStatisticsRequest) async -> BodyHealthReadOutcome<HKStatistics> {
        await bodyCancellableRead { resume in
            let query = HKStatisticsQuery(
                quantityType: request.quantityType,
                quantitySamplePredicate: request.predicate,
                options: request.options
            ) { _, statistics, error in
                guard let statistics else {
                    resume(.failure(error))
                    return
                }

                resume(.success(statistics))
            }

            self.execute(query)
            return query
        }
    }

    func statisticsCollection(
        _ request: BodyStatisticsCollectionRequest
    ) async -> BodyHealthReadOutcome<HKStatisticsCollection> {
        await bodyCancellableRead { resume in
            let query = HKStatisticsCollectionQuery(
                quantityType: request.quantityType,
                quantitySamplePredicate: request.predicate,
                options: request.options,
                anchorDate: request.anchorDate,
                intervalComponents: request.intervalComponents
            )

            query.initialResultsHandler = { _, statisticsCollection, error in
                guard let statisticsCollection else {
                    resume(.failure(error))
                    return
                }

                resume(.success(statisticsCollection))
            }

            self.execute(query)
            return query
        }
    }

    /// Runs one callback query under `BodyQueryResumeBox`, so the awaiting task's
    /// cancellation resumes `.cancelled` and stops the query exactly once.
    private func bodyCancellableRead<Value>(
        _ body: @escaping (@escaping @Sendable (BodyHealthReadOutcome<Value>) -> Void) -> HKQuery
    ) async -> BodyHealthReadOutcome<Value> {
        let box = BodyQueryResumeBox<BodyHealthReadOutcome<Value>>(stop: { [self] query in self.stop(query) })
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                box.install(continuation: continuation, cancelledValue: .cancelled, body: body)
            }
        } onCancel: {
            box.cancel(cancelledValue: .cancelled)
        }
    }
}

/// Lock-protected one-shot resume backing every leaf read above, so
/// `withTaskCancellationHandler`'s `onCancel` (which can fire concurrently with
/// `install`, before or after the query executes) and the query's own completion
/// callback can't both resume the continuation.
///
/// Generalised from the source-discovery box this file replaced. Mirrors
/// `TrackedQueryResumeBox` in `HealthKitFetchEngine.swift` for the
/// pending/armed/cancelledBeforeInstall/settled locking pattern, kept
/// independent (rather than shared or moved) because this file compiles into
/// both the iOS app and the watch app and must not reference `Body/Services`
/// types. Unlike `TrackedQueryResumeBox` this box also has to stop the `HKQuery`
/// on cancellation, the same concern `CancellableQueryCoordinator` handles in
/// the engine — `stop` is injected rather than a stored `HKHealthStore` so the
/// box stays testable (and `HKHealthStore.execute`/`.stop` are not safely
/// callable from a test host without a HealthKit bundle identity).
///
/// `install`'s `body` builds and executes the query and returns it; if
/// cancellation lands while `body` is still running (before the query is
/// stashed), `install`'s post-call re-check stops it instead, so the query is
/// stopped exactly once either way. `@unchecked Sendable` is sound because
/// every access is lock-guarded.
final class BodyQueryResumeBox<Value>: @unchecked Sendable {
    private enum State {
        case pending
        case armed(CheckedContinuation<Value, Never>)
        case cancelledBeforeInstall
        case settled
    }

    private let stop: (HKQuery) -> Void
    private let lock = NSLock()
    private var state: State = .pending
    private var executedQuery: HKQuery?
    /// Set only by `cancel(cancelledValue:)`: `install` uses it to tell
    /// "cancelled while the query was executing" apart from "the query's
    /// callback already resumed synchronously", which settles the state just the
    /// same but must not stop a finished query.
    private var wasCancelledWhileArmed = false

    init(stop: @escaping (HKQuery) -> Void) {
        self.stop = stop
    }

    /// Arms the box and runs `body`, which builds and executes the query and
    /// returns it, unless cancellation already fired — in which case the
    /// continuation resumes with the cancelled value and no query is ever
    /// created.
    func install(
        continuation: CheckedContinuation<Value, Never>,
        cancelledValue: @autoclosure () -> Value,
        body: (@escaping @Sendable (Value) -> Void) -> HKQuery
    ) {
        lock.lock()
        switch state {
        case .cancelledBeforeInstall:
            state = .settled
            lock.unlock()
            continuation.resume(returning: cancelledValue())
            return
        case .pending:
            state = .armed(continuation)
            lock.unlock()
        case .armed, .settled:
            // `install` runs exactly once; these are unreachable.
            lock.unlock()
            return
        }
        // Outside the lock: `body` builds and executes the query, and a
        // same-thread callback would otherwise re-enter.
        let query = body { [weak self] value in
            self?.resume(value)
        }

        lock.lock()
        if wasCancelledWhileArmed {
            // Cancelled while `body` was still running, before this box had a
            // query to hand to a concurrent `cancel()` — stop it here instead.
            lock.unlock()
            stop(query)
        } else {
            executedQuery = query
            lock.unlock()
        }
    }

    /// The query's callback. Drops the value if cancellation already resumed.
    private func resume(_ value: Value) {
        lock.lock()
        switch state {
        case .armed(let continuation):
            state = .settled
            lock.unlock()
            continuation.resume(returning: value)
        case .pending, .cancelledBeforeInstall, .settled:
            lock.unlock()
        }
    }

    /// Resumes `cancelledValue` once and stops the executed query, if any. Safe
    /// to call before, during, or after `install`.
    func cancel(cancelledValue: @autoclosure () -> Value) {
        lock.lock()
        switch state {
        case .pending:
            // Continuation not installed yet; `install` resumes immediately
            // without ever executing the query.
            state = .cancelledBeforeInstall
            lock.unlock()
        case .armed(let continuation):
            state = .settled
            wasCancelledWhileArmed = true
            let query = executedQuery
            lock.unlock()
            continuation.resume(returning: cancelledValue())
            if let query {
                stop(query)
            }
        case .cancelledBeforeInstall, .settled:
            lock.unlock()
        }
    }
}
